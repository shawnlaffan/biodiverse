package Biodiverse::GUI::BasedataImport;

use 5.010;
use strict;
use warnings;
use English ( -no_match_vars );

use Carp;

our $VERSION = '0.19';

use File::Basename;
use Gtk2;
use Gtk2::GladeXML;
use Glib;
use Text::Wrapper;
use File::BOM qw / :subs /;

use Scalar::Util qw /reftype/;

no warnings 'redefine';  #  getting redefine warnings, which aren't a problem for us

use Biodiverse::GUI::Project;
use Biodiverse::ElementProperties;

#  for use in check_if_r_data_frame
use Biodiverse::Common;

use Geo::ShapeFile;

#  a few name setups for a change-over that never happened
my $import_n = ""; #  use "" for orig, 3 for the one with embedded params table
my $dlg_name = "dlgImport1";
my $chk_new = "chkNew$import_n";
my $btn_next = "btnNext$import_n";
my $file_format = "format_box$import_n";
my $combo_import_basedatas = "comboImportBasedatas$import_n";
my $filechooser_input = "filechooserInput$import_n";
my $txt_import_new = "txtImportNew$import_n";
my $table_parameters = "tableParameters$import_n";
my $importmethod_combo = "format_box$import_n"; # not sure about the suffix

my $text_idx      = 0;  # index in combo box 
my $raster_idx    = 1;  # index in combo box of raster format
my $shapefile_idx = 2;  # index in combo box 

my $txtcsv_filter; # maintain reference for these, to allow referring when import method changes
my $allfiles_filter;  
my $shapefiles_filter;  

##################################################
# High-level procedure
##################################################

sub run {
    my $gui = shift;

    #########
    # 1. Get the target basedata & filename
    #########
    my ($dlgxml, $dlg) = make_filename_dialog($gui);
    my $response = $dlg->run();
    
    if ($response ne 'ok') {  #  clean up and drop out
        $dlg->destroy;
        return;
    }
    
    my ($use_new, $basedata_ref);

    #if ($response eq 'ok') {

    $use_new = $dlgxml->get_widget($chk_new)->get_active();
    if ($use_new) {
        # Add it
        # FIXME: why am i adding it now?? better at the end?
        my $basedata_name = $dlgxml->get_widget($txt_import_new)->get_text();
        #$basedata_ref = $gui->get_project->add_base_data($basedata_name);
        $basedata_ref = Biodiverse::BaseData->new (
            NAME       => $basedata_name,
            CELL_SIZES => [100000,100000],  #  default, gets overridden later
        );
    }
    else {
        # Get selected basedata
        my $selected = $dlgxml->get_widget($combo_import_basedatas)->get_active_iter();
        $basedata_ref = $gui->get_project->get_basedata_model->get($selected, MODEL_OBJECT);
    }

    # Get selected filenames
    my @filenames = $dlgxml->get_widget($filechooser_input)->get_filenames();
    my @file_names_tmp = @filenames;
    if (scalar @filenames > 5) {
        @file_names_tmp = @filenames[0..5];
        push @file_names_tmp, '... plus ' . (scalar @filenames - 5) . ' others';
    }
    my $file_list_as_text = join ("\n", @file_names_tmp);
    
    # interpret if raster or text depending on format box
    #my $read_raster;
    my $read_format = $dlgxml->get_widget($file_format)->get_active();
    #if (defined $dlgxml->get_widget($combo_import_basedatas)) {
    #    print "$combo_import_basedatas defined\n";
    #}
    #else { print "nope\n"; }  
    
    #if (defined $dlgxml->get_widget($file_format)) {
    # $read_raster = ($dlgxml->get_widget($file_format)->get_active() == $raster_idx);
    #}
    #else {
    #    print "widget $file_format not defined\n";
    #}

    $dlg->destroy();

    #########
    # 1a. Get parameters to use
    #########
    $dlgxml = Gtk2::GladeXML->new($gui->get_glade_file, 'dlgImportParameters');
    $dlg = $dlgxml->get_widget('dlgImportParameters');
    
    #  add file name labels to display
    my $vbox = Gtk2::VBox->new (0, 0);
    my $file_title = Gtk2::Label ->new('<b>Files:</b>');
    $file_title->set_use_markup(1);
    $file_title->set_alignment (0, 1);
    $vbox->pack_start ($file_title, 0, 0, 0);

    my $file_list_label = Gtk2::Label ->new($file_list_as_text . "\n\n");
    $file_list_label->set_alignment (0, 1);
    $vbox->pack_start ($file_list_label, 0, 0, 0);
    my $import_vbox = $dlgxml->get_widget('import_parameters_vbox');
    $import_vbox->pack_start($vbox, 0, 0, 0);
    $import_vbox->reorder_child($vbox, 0);  #  move to start

    #  get any options
    # Get the Parameters metadata
    my %args;
    # set visible fields in import dialog
    if ($read_format == $text_idx) {
        %args = $basedata_ref->get_args (sub => 'import_data_text');        
    }
    elsif ($read_format == $raster_idx) {
        %args = $basedata_ref->get_args (sub => 'import_data_raster');        
    }
    #elsif ($read_format == $shapefile_idx) {
        #croak('import for shapefiles not defined');
    #}
    
    # only show this dialog if args/parameters are defined (ignored for shapefile input)
    my %import_params;
    my $params;
    if (%args) {
        $params = $args{parameters};

        # set some default values (a bit of a hack)
        my @cell_sizes   = @{$basedata_ref->get_param('CELL_SIZES')};
        my @cell_origins = @{$basedata_ref->get_cell_origins};

        foreach my $thisp (@$params) {
            $thisp->{default} = $cell_origins[0] if ($thisp->{name} eq 'raster_origin_e');
            $thisp->{default} = $cell_origins[1] if ($thisp->{name} eq 'raster_origin_n');
            $thisp->{default} = $cell_sizes[0]   if ($thisp->{name} eq 'raster_cellsize_e');
            $thisp->{default} = $cell_sizes[1]   if ($thisp->{name} eq 'raster_cellsize_n');        
        }

        # Build widgets for parameters
        my $table = $dlgxml->get_widget ('tableImportParameters');
        # (passing $dlgxml because generateFile uses existing glade widget on the dialog)
        my $extractors = Biodiverse::GUI::ParametersTable::fill ($params, $table, $dlgxml); 

        $dlg->show_all;
        $response = $dlg->run;
        $dlg->destroy;

        if ($response ne 'ok') {  #  clean up and drop out
            if ($use_new) {
                $gui->getProject->deleteBaseData($basedata_ref);
            }
            return;
        }
        my $import_params = Biodiverse::GUI::ParametersTable::extract ($extractors);
        %import_params = @$import_params;
    }
    
    # next stage, if we are reading as raster, just call import function here and exit.
    # for shapefile and text, find columns and ask how to interpret 
    my $col_names_for_dialog;
    my $col_options = undef;
    my $use_matrix;
    if ($read_format == $raster_idx) {
        my $labels_as_bands = $import_params{raster_labels_as_bands};
        my $success = eval {
            $basedata_ref->import_data_raster(
                %import_params,
                #%rest_of_options,
                #%gp_lb_cols,
                labels_as_bands => $labels_as_bands,
                input_files     => \@filenames
            )
        };
        if ($EVAL_ERROR) {
            my $text = $EVAL_ERROR;
            if (not $use_new) {
                $text .= "\tWarning: Records prior to this line have been imported.\n";
            }
            $gui->report_error ($text);
        }

        return if !$success;

        if ($use_new) {
            $gui->get_project->add_base_data($basedata_ref);
        }
        return $basedata_ref;
    }
    elsif ($read_format == $shapefile_idx) {
        # process as shapefile

        # find available columns from first file, assume all the same
        croak ('no files given') if !scalar @filenames;

        say $filenames[0];
        my $fnamebase = $filenames[0];
        $fnamebase =~ s/\.[^.]+?$//;  #  use lazy quantifier so we get chars from the last dot - should use Path::Class::File
        my $shapefile = Geo::ShapeFile->new($fnamebase);

        my @field_names = qw /x y/; # we always have x,y data
        push (@field_names, 'z') if defined $shapefile->z_min();
        push (@field_names, 'm') if defined $shapefile->m_min();
        $col_names_for_dialog = \@field_names;

        #  need to get the remaining columns from the dbf
    }
    else {
        # process as text input, get columns from file

        # Get header columns
        print "[GUI] Discovering columns from $filenames[0]\n";
        my $fh;
        my $filename_utf8 = Glib::filename_display_name $filenames[0];

        #use Path::Class::Unicode;
        #my $file = ufile("path", $filename_utf8);
        #print $file . "\n";

        # have unicode filename issues - see http://code.google.com/p/biodiverse/issues/detail?id=272
        if (not open $fh, '<:via(File::BOM)', $filename_utf8) {
            my $exists = -e $filename_utf8 || 0;
            my $msg = "Unable to open $filenames[0].\n";
            $msg .= $exists
                ? "Check file read permissions."
                : "If the file name contains unicode characters then please rename the file so its name does not contain them.\n"
                  . "See http://code.google.com/p/biodiverse/issues/detail?id=272";
            $msg .= "\n";
            croak $msg;
        }

        my $line = <$fh>;
        close ($fh);

        my $sep = $import_params{input_sep_char} eq 'guess' 
                ? $gui->get_project->guess_field_separator (string => $line)
                : $import_params{input_sep_char};

        my $quotes  = $import_params{input_quote_char} eq 'guess'
                    ? $gui->get_project->guess_quote_char (string => $line)
                    : $import_params{input_quote_char};

        my $eol     = $gui->get_project->guess_eol (string => $line);

        my @header  = $gui->get_project->csv2list(
            string      => $line,
            quote_char  => $quotes,
            sep_char    => $sep,
            eol         => $eol,
        );

        #  R data frames are saved missing the first field in the header
        my $is_r_data_frame = check_if_r_data_frame (
            file     => $filenames[0],
            quotes   => $quotes,
            sep_char => $sep,
        );
        #  add a field to the header if needed
        if ($is_r_data_frame) {
            unshift @header, 'R_data_frame_col_0';
        }
        
        $use_matrix = $import_params{data_in_matrix_form};
        $col_names_for_dialog = \@header;
        $col_options = undef;
        
        if ($use_matrix) {
            $col_options = [qw /
                Ignore
                Group
                Text_group
                Label_start_col
                Label_end_col
                Include_columns
                Exclude_columns
            /];
        }
    }
    
    #########
    # 2. Get column types (using first file...)
    #########
    my $row_widgets;
    ($dlg, $row_widgets) = make_columns_dialog (
        $col_names_for_dialog,
        $gui->get_widget('wndMain'),
        $col_options,
        $file_list_as_text,
    );
    my $column_settings;
    
    GET_COLUMN_TYPES:
    while (1) { # Keep showing dialog until have at least one label & group
        $response = $dlg->run();
        if ($response eq 'help') {
            #  do stuff
            #print "hjelp me!\n";
            explain_import_col_options($dlg, $use_matrix);
        }
        elsif ($response eq 'ok') {
            $column_settings = get_column_settings($row_widgets, $col_names_for_dialog);
            my $num_groups = scalar @{$column_settings->{groups}};
            my $num_labels = 0;
            if ($use_matrix) {
                if (exists $column_settings->{Label_start_col}) {  #  not always present
                    $num_labels = scalar @{$column_settings->{Label_start_col}};
                }
            }
            else {
                $num_labels = scalar @{$column_settings->{labels}};
            }

            # removed minimum label constraint for now, to allow "default" label to be used,
            # for example for records which simply have x,y coords, and each is given a simple
            # label ("1")
            if ($num_groups == 0) { # || $num_labels == 0) {
                my $text = $use_matrix
                     ? 'Please select at least one group and the label start column'
                     : 'Please select at least one label and one group';
                
                my $msg = Gtk2::MessageDialog->new (
                    undef,
                    'modal',
                    'error',
                    'ok',
                    $text
                );
                
                $msg->run();
                $msg->destroy();
                $column_settings = undef;
            }
            else {
                last GET_COLUMN_TYPES;
            }
        }
        else {
            last GET_COLUMN_TYPES;
        }
    }
    $dlg->destroy();
    
    if (not $column_settings) {  #  clean up and drop out
        if ($use_new) {
            $gui->get_project->delete_base_data ($basedata_ref) ;
        }
        return;
    }

    if ($read_format == $shapefile_idx) {
        # process data
        my $success = eval {
            $basedata_ref->import_data_shapefile(
                %import_params,
                input_files             => \@filenames,
                group_fields            => $column_settings->{groups},
                label_fields            => $column_settings->{labels},
                use_new                 => $use_new
            )
        };
        if ($EVAL_ERROR) {
            my $text = $EVAL_ERROR;
            if (not $use_new) {
                $text .= "\tWarning: Records prior to this line have been imported.\n";
            }
            $gui->report_error ($text);
        }
    
        my @tmpcell_sizes = @{$basedata_ref->get_param("CELL_SIZES")};  #  work on a copy
        say 'checking set cell sizes: ', join (',', @tmpcell_sizes);

        return if !$success;

        if ($use_new) {
            $gui->get_project->add_base_data($basedata_ref);
        }
        return $basedata_ref;
    }
    
    #########
    # 3. Get column order
    #########
    my $old_labels_array = $column_settings->{labels};
    if ($use_matrix) {
        $column_settings->{labels}
            = [{name => 'From file', id => 0}];
    }
    
    ($dlgxml, $dlg) = make_reorder_dialog($gui, $column_settings);
    $response = $dlg->run();
    
    $params = fill_params($dlgxml);
    $dlg->destroy();

    if ($response ne 'ok') {  #  clean up and drop out
        if ($use_new) {
            $gui->get_project->delete_base_data ($basedata_ref);
        }
        return;
    }

    if ($use_matrix) {
        $column_settings->{labels} = $old_labels_array;
    }

    #########
    # 3a. Load the label and group properties
    #########
    my %other_properties = (
        label => [qw /range sample_count/],
        group => ['sample_count'],    
    );
    
    foreach my $type (qw /label group/) {
        if ($import_params{"use_$type\_properties"}) {
            my %remap_data = get_remap_info (
                $gui,
                $filenames[0],
                $type,
                $other_properties{$type},
            );

            #  now do something with them...
            my $remap;
            if ($remap_data{file}) {
                #my $file = $remap_data{file};
                $remap = Biodiverse::ElementProperties->new;
                $remap->import_data (%remap_data);
            }
            $import_params{"$type\_properties"} = $remap;
            if (not defined $remap) {
                $import_params{"use_$type\_properties"} = undef;
            }
        }
    }

    #########
    # 4. Load the data
    #########
    # Set the cellsize and origins parameters if we are new
    if ($use_new) {
        $basedata_ref->set_param(CELL_SIZES   => $params->{CELL_SIZES});
        $basedata_ref->set_param(CELL_ORIGINS => $params->{CELL_ORIGINS});
    }

    #  get the sample count columns.  could do in fill_params, but these are
    #    not reordered while fill_params deals with the re-ordering.  
    my @sample_count_columns;
    foreach my $index (@{$column_settings->{sample_counts}}) {
        push @sample_count_columns, $index->{id};
    }
    
    my @include_columns;
    foreach my $index (@{$column_settings->{include_columns}}) {
        push @include_columns, $index->{id};
    }
    
    my @exclude_columns;
    foreach my $index (@{$column_settings->{exclude_columns}}) {
        push @exclude_columns, $index->{id};
    }
    
    my %rest_of_options;
    my %checked_already;
    my @tmp = qw/sample_counts exclude_columns include_columns groups labels/;
    @checked_already{@tmp} = (1) x scalar @tmp;  #  clunky
    
    COLUMN_SETTING:
    foreach my $key (keys %$column_settings) {
        next COLUMN_SETTING if exists $checked_already{$key};
        
        my $array_ref = [];
        foreach my $index (@{$column_settings->{$key}}) {
            push @$array_ref, $index->{id};
        }
        $key = lc $key;
        $rest_of_options{$key} = $array_ref;
    }

    #  get the various columns    
    my %gp_lb_cols;
    while (my ($key, $value) = each %$params) {
        next if $key =~ /^CELL_(?:SIZE|ORIGINS)/;
        $gp_lb_cols{lc $key} = $value;
    }

    my $success = eval {
        $basedata_ref->load_data(
            %import_params,
            %rest_of_options,
            %gp_lb_cols,
            input_files             => \@filenames,
            include_columns         => \@include_columns,
            exclude_columns         => \@exclude_columns,
            sample_count_columns    => \@sample_count_columns,
        )
    };
    if ($EVAL_ERROR) {
        my $text = $EVAL_ERROR;
        if (not $use_new) {
            $text .= "\tWarning: Records prior to this line have been imported.\n";
        }
        $gui->report_error ($text);
    }

    if ($success) {
        if ($use_new) {
            $gui->get_project->add_base_data($basedata_ref);
        }
        return $basedata_ref;
    }

    return;
}


sub check_if_r_data_frame {
    my %args = @_;
    
    my $package = 'Biodiverse::Common';
    my $csv = $package->get_csv_object (@_);
    
    my $fh;
    open ($fh, '<:via(File::BOM)', $args{file})
        || croak "Unable to open file $args{file}\n";

    my @lines = $package->get_next_line_set (
        target_line_count => 10,
        file_handle       => $fh,
        csv_object        => $csv,
    );

    $fh->close;

    my $header = shift @lines;
    my $header_count = scalar @$header;

    my $is_r_style = 0;
    foreach my $line (@lines) {
        if (scalar @$line == $header_count + 1) {
            $is_r_style = 1;
        }
    }
    
    return $is_r_style;
}

##################################################
# Extracting information from widgets
##################################################

# Extract column types and sizes into lists that can be passed to the reorder dialog
#  special handling for groups, the rest are returned "as-is"
sub get_column_settings {
    my $cols = shift;
    my $headers = shift;
    #my $num = @$cols;
    my (@labels, @groups, @sample_counts, @exclude_columns, @include_columns);
    my %rest_of_options;

    foreach my $i (0..$#$cols) {
        my $widgets = $cols->[$i];
        # widgets[0] - combo
        # widgets[1] - cell size
        # widgets[2] - cell origin

        my $type = $widgets->[0]->get_active_text;

        next if $type eq 'Ignore';
        if ($type eq 'Label') {
            my $hash_ref = {
                name    => $headers->[$i],
                id      => $i
            };
            push (@labels, $hash_ref);
        }
        elsif ($type eq 'Text_group') {
            my $hash_ref = {
                name        => $headers->[$i],
                id          => $i,
                cell_size   => -1,
                cell_origin => 0,
            };
            push (@groups, $hash_ref);
        }
        elsif ($type eq 'Group') {
            my $hash_ref = {
                name        => $headers->[$i],
                id          => $i,
                cell_size   => $widgets->[1]->get_value(),
                cell_origin => $widgets->[2]->get_value(),
            };
            my $dms = $widgets->[3]->get_active_text();
            if ($dms eq 'is_lat') {
                $hash_ref->{is_lat} = 1;
            }
            elsif ($dms eq 'is_lon') {
                $hash_ref->{is_lon} = 1;
            }
            push (@groups, $hash_ref);
        }
        elsif ($type eq 'Sample_counts') {
            my $hash_ref = {
                name    => $headers->[$i],
                id      => $i,
            };
            push @sample_counts, $hash_ref;
        }
        elsif ($type eq 'Include_columns') {
            my $hash_ref = {
                name    => $headers->[$i],
                id      => $i,
            };
            push @include_columns, $hash_ref;
        }
        elsif ($type eq 'Exclude_columns') {
            my $hash_ref = {
                name    => $headers->[$i],
                id      => $i,
            };
            push @exclude_columns, $hash_ref;
        }
        else {
            # initialise
            if (not exists $rest_of_options{$type}
                or reftype ($rest_of_options{$type}) eq 'ARRAY'
                ) {  
                $rest_of_options{$type} = [];
            }
            my $array_ref = $rest_of_options{$type};
            
            my $hash_ref = {
                name    => $headers->[$i],
                id      => $i,
            };
            push @$array_ref, $hash_ref;
        }
    }

    my %results = (
        groups          => \@groups,
        labels          => \@labels,
        sample_counts   => \@sample_counts,
        exclude_columns => \@exclude_columns,
        include_columns => \@include_columns,
        %rest_of_options,
    );
    
    return wantarray ? %results : \%results;
}

# Set the column parameters based on the reorder dialog
sub fill_params {
    my $dlgxml = shift;

    my $labels_model = $dlgxml->get_widget('labels')->get_model();
    my $groups_model = $dlgxml->get_widget('groups')->get_model();
    my $iter;

    my %params = (
        LABEL_COLUMNS => [],
        GROUP_COLUMNS => [],
        CELL_SIZES    => [],
        CELL_ORIGINS  => [],
        CELL_IS_LAT   => [],
        CELL_IS_LON   => [],
    );

    # Do labels
    $iter = $labels_model->get_iter_first();
    while ($iter) {
        my $info = $labels_model->get($iter, 1);

        push (@{$params{'LABEL_COLUMNS'}}, $info->{id});
    
        $iter = $labels_model->iter_next($iter);
    }

    # Do groups
    $iter = $groups_model->get_iter_first();
    while ($iter) {
        my $info2 = $groups_model->get($iter, 1);

        push (@{$params{'GROUP_COLUMNS'}}, $info2->{id});
        push (@{$params{'CELL_SIZES'}},    $info2->{cell_size});
        push (@{$params{'CELL_ORIGINS'}},  $info2->{cell_origin});
        push (@{$params{'CELL_IS_LAT'}},   $info2->{is_lat});
        push (@{$params{'CELL_IS_LON'}},   $info2->{is_lon});

        $iter = $groups_model->iter_next($iter);
    }

    return \%params;
}

#  this needs to be kept in synch better,
#  poss by making the lists package lexical
sub explain_import_col_options {
    my $parent     = shift;
    my $use_matrix = shift;
    
    my %explain = (
        Ignore          => 'There is no setting for this column.  '
                         . 'It will be ignored or used depending on your other settings.',
        Group           => 'Use records in this column to define a group axis '
                         . '(numerical type).  Values will be aggregated according '
                         . 'to your cellsize settings.  Non-numeric values will cause an error.',
        Text_group      => 'Use records in this column as a group axis (text type).  '
                         . 'Values will be used exactly as given.',
        Include_columns => 'Only those records with a value of 1 in '
                         . '<i>at least one</i> of the Include_columns will '
                         . 'be imported.',
        Exclude_columns => 'Those records with a value of 1 in any '
                         . 'Exclude_column will not be imported.',
    );
    if ($use_matrix) {
        %explain = (
            %explain,
            Label_start_col => 'This column is the start of the labels. '
                             . 'The headers will be used as the labels, '
                             . 'the values as the abundance scores. '
                             . 'All columns set to Ignore until the '
                             . 'Label_end_col will be treated as labels.',
            Label_end_col   => 'This column is the last of the labels.  '
                             . 'Not setting one will use all columns from the '
                             . 'Label_start_col to the end.',
        );
    }
    else {
        %explain = (
            %explain,
            Label           => 'Values in this column will be used as one of the label axes.',
            Sample_counts   => 'Values in this column represent sample counts (abundances).  '
                             . 'If this is not set then each record is assumed to equal one sample.',
        );
    }

    show_expl_dialog (\%explain, $parent);

    return;
}

sub explain_remap_col_options {
    my $parent = shift;
    
    my $inc_exc_suffix = 'This applies to the main input file, '
                       . 'and is assessed before any remapping is done.';

    my %explain = (
        Ignore           => 'There is no setting for this column.  '
                          . 'It will be ignored or used depending on your other settings.',
        Property         => 'The value for this field will be added as a property, '
                          . 'using the name of the column as the property name.',
        Input_element    => 'Values in this column will be used as one of the element (label or group) axes. '
                          . 'Make sure you have as many of these columns set as you have '
                          . 'element axes or they will not match and the properties will be ignored.',
        Remapped_element => 'The input element (label or group) will be renamed to this. '
                          . 'Set as many remapped label axes as you like, '
                          . 'but make sure the group axes remain the same',
        Include_columns  => 'Only those Input_elements with a value of 1 in '
                          . '<i>at least one</i> of the Include_columns will '
                          . 'be imported. '
                          . $inc_exc_suffix,
        Exclude_columns  => 'Those Input_elements with a value of 1 in any '
                          . 'Exclude_column will not be imported.  '
                          . $inc_exc_suffix,
    );

    show_expl_dialog (\%explain, $parent);

    return;
}

sub show_expl_dialog {
    my $expl_hash = shift;
    my $parent    = shift;
#$parent = undef;
    my $dlg = Gtk2::Dialog->new(
        'Column options',
        $parent,
        'destroy-with-parent',
        'gtk-ok' => 'ok',
    );

    my $text_wrapper = Text::Wrapper->new(columns => 90);

    my $table = Gtk2::Table->new(1 + scalar keys %$expl_hash, 2);
    $table->set_row_spacings(5);
    $table->set_col_spacings(5);

    # Make scroll window for table
    #my $scroll = Gtk2::ScrolledWindow->new;
    #$scroll->add_with_viewport($table);
    #$scroll->set_policy('never', 'automatic');
    #$dlg->vbox->pack_start($scroll, 1, 1, 5);

    $dlg->vbox->pack_start($table, 1, 1, 5);

    my $col = 0;
    # Make header column
    my $label1 = Gtk2::Label->new('<b>Column option</b>');
    $label1->set_alignment(0, 1);
    $label1->set_use_markup(1);
    $table->attach($label1, 0, 1, $col, $col + 1, ['expand', 'fill'], 'shrink', 0, 0);
    my $label2 = Gtk2::Label->new('<b>Explanation</b>');
    $label2->set_alignment(0, 1);
    $label2->set_use_markup(1);
    $table->attach($label2, 1, 2, $col, $col + 1, ['expand', 'fill'], 'shrink', 0, 0);

    my $text;
    #while (my ($label, $expl) = each %explain) {
    foreach my $label (sort keys %$expl_hash) {
        $col++;
        my $label_widget = Gtk2::Label->new("<b>$label</b>");
        $table->attach($label_widget, 0, 1, $col, $col + 1, ['expand', 'fill'], 'shrink', 0, 0);

        my $expl = $expl_hash->{$label};
        #$expl = $text_wrapper->wrap($expl);
        my $expl_widget  = Gtk2::Label->new($expl);
        $table->attach($expl_widget,  1, 2, $col, $col + 1, ['expand', 'fill'], 'shrink', 0, 0);

        foreach my $widget ($expl_widget, $label_widget) {
            $widget->set_alignment(0, 0);
            $widget->set_use_markup(1);
            $widget->set_selectable(1);
        }
    }

    $dlg->set_modal(undef);
    #$dlg->set_focus(undef);
    $dlg->show_all;

    #  Callbacks are sort of redundant now, since dialogs are always modal
    #  so we cannot return control to the input window that called us.
    #my $destroy_sub = sub {$_[0]->destroy};
    #$dlg->signal_connect_swapped(
    #    response => $destroy_sub,
    #    $dlg,
    #);
    #$dlg->signal_connect_swapped(
    #    close => $destroy_sub,
    #    $dlg,
    #);

    $dlg->run;
    $dlg->destroy;

    return;
}


##################################################
# Column reorder dialog
##################################################

sub make_reorder_dialog {
    my $gui = shift;
    my $columns = shift;

    my $dlgxml = Gtk2::GladeXML->new($gui->get_glade_file, 'dlgReorderColumns');
    my $dlg = $dlgxml->get_widget('dlgReorderColumns');
    $dlg->set_transient_for( $gui->get_widget('wndMain') );
    
    my $list_groups = setup_reorder_list('groups', $dlgxml, $columns->{groups});
    my $list_labels = setup_reorder_list('labels', $dlgxml, $columns->{labels});

    # Make the selections mutually exclusive (if selection made, unselect selection in other list)
    $list_groups->get_selection->signal_connect(
        changed => \&unselect_other,
        $list_labels,
    );
    $list_labels->get_selection->signal_connect(
        changed => \&unselect_other,
        $list_groups,
    );

    # Connect up/down buttons
    $dlgxml->get_widget('btnUp')->signal_connect(
        clicked => \&on_up_down,
        ['up', $list_groups, $list_labels],
    );
    $dlgxml->get_widget('btnDown')->signal_connect(
        clicked => \&on_up_down,
        ['down', $list_groups, $list_labels],
    );

    return ($dlgxml, $dlg);
}

sub setup_reorder_list {
    my $type = shift;
    my $dlgxml = shift;
    my $columns = shift;

    # Create the model
    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::Scalar');

    foreach my $column (@{$columns}) {
        my $iter = $model->append();
        $model->set($iter, 0, $column->{name});
        $model->set($iter, 1, $column);
    }
    
    # Initialise the list
    my $list = $dlgxml->get_widget($type);
    
    my $col_name = Gtk2::TreeViewColumn->new();
    my $name_renderer = Gtk2::CellRendererText->new();
    $col_name->set_sizing('fixed');
    $col_name->pack_start($name_renderer, 1);
    $col_name->add_attribute($name_renderer,  text => 0);
    
    $list->insert_column($col_name, -1);
    $list->set_headers_visible(0);
    $list->set_reorderable(1);
    $list->set_model( $model );
    
    return $list;
}


# If selected something, clear the other lists' selection
sub unselect_other {
    my $selection = shift;
    my $other_list = shift;

    if ($selection->count_selected_rows() > 0) {
        $other_list->get_selection->unselect_all();
    }
    
    return;
}

sub on_up_down {
    shift;
    my $args = shift;
    my ($btn, $list1, $list2) = @$args;

    # Get selected iter
    my ($model, $iter);

    ($model, $iter) = $list1->get_selection->get_selected();
    if (not $iter) {
        # try other list
        ($model, $iter) = $list2->get_selection->get_selected();
        if (not $iter) {
            return;
        }
    }

    if ($btn eq 'up') {
        my $path = $model->get_path($iter);
        if ($path->prev()) {

            my $iter_prev = $model->get_iter($path);
            $model->move_before($iter, $iter_prev);

        }

        else {
            # If at the top already, move to bottom
            $model->move_before($iter, undef);

        }
    }
    elsif ($btn eq 'down') {
        $model->move_after($iter, $model->iter_next($iter));
    }
    
    return;
}

##################################################
# First (choose filename) dialog
##################################################
    
sub make_filename_dialog {
    my $gui = shift;
    #my $object = shift || return;
    
    my $dlgxml = Gtk2::GladeXML->new($gui->get_glade_file, $dlg_name);
    my $dlg = $dlgxml->get_widget($dlg_name);
    my $x = $gui->get_widget('wndMain');
    $dlg->set_transient_for( $x );
    
#    # Get the Parameters metadata
#    my $tmp = Biodiverse::BaseData->new;
#        my %args = $tmp->get_args (sub => 'import_data');
#    my $params = $args{parameters};
#
#    # Build widgets for parameters
#    my $table = $dlgxml->get_widget($table_parameters);
#    # (passing $dlgxml because generateFile uses existing glade widget on the dialog)
#    my $extractors = Biodiverse::GUI::ParametersTable::fill($params, $table, $dlgxml); 


    # Initialise the basedatas combo
    $dlgxml->get_widget($combo_import_basedatas)->set_model($gui->get_project->get_basedata_model());
    my $selected = $gui->get_project->get_selected_base_data_iter();
    if (defined $selected) {
        $dlgxml->get_widget($combo_import_basedatas)->set_active_iter($selected);
    }

    # If there are no basedatas, force "New" checkbox on
    if (not $selected) {
        $dlgxml->get_widget($chk_new)->set_sensitive(0);
        $dlgxml->get_widget($btn_next)->set_sensitive(0);
    }

    # Default to new
    $dlgxml->get_widget($chk_new)->set_active(1);
    $dlgxml->get_widget($combo_import_basedatas)->set_sensitive(0);


    # Init the file chooser
    
    # define file selection filters (stored in txtcsv_filter etc)
    $txtcsv_filter = Gtk2::FileFilter->new();
    $txtcsv_filter->add_pattern('*.csv');
    $txtcsv_filter->add_pattern('*.txt');
    $txtcsv_filter->set_name('txt and csv files');
    $dlgxml->get_widget($filechooser_input)->add_filter($txtcsv_filter);

    $allfiles_filter = Gtk2::FileFilter->new();
    $allfiles_filter->add_pattern('*');
    $allfiles_filter->set_name('all files');
    $dlgxml->get_widget($filechooser_input)->add_filter($allfiles_filter);
    
    $shapefiles_filter = Gtk2::FileFilter->new();
    $shapefiles_filter->add_pattern('*.shp');
    $shapefiles_filter->set_name('shapefiles');
    $dlgxml->get_widget($filechooser_input)->add_filter($shapefiles_filter);
    
    $dlgxml->get_widget($filechooser_input)->set_select_multiple(1);
    $dlgxml->get_widget($filechooser_input)->signal_connect('selection-changed' => \&onFileChanged, $dlgxml);

    $dlgxml->get_widget($chk_new)->signal_connect(toggled => \&on_new_toggled, [$gui, $dlgxml]);
    $dlgxml->get_widget($txt_import_new)->signal_connect(changed => \&on_new_changed, [$gui, $dlgxml]);
    
    $dlgxml->get_widget($file_format)->set_active(0);
    $dlgxml->get_widget($importmethod_combo)->signal_connect(changed => \&onImportMethodChanged, [$gui, $dlgxml]);
    
    return ($dlgxml, $dlg);
}

sub onImportMethodChanged {
    # change file filter used
    my $format_combo = shift;
    my $args = shift;
    my ($gui, $dlgxml) = @{$args};
    
    my $active_choice = $format_combo->get_active();
    my $f_widget      = $dlgxml->get_widget($filechooser_input);
    
    # find which is selected
    if ($active_choice == $text_idx) {
        $f_widget->set_filter($txtcsv_filter);
    }
    elsif ($active_choice == $raster_idx) {
        $f_widget->set_filter($allfiles_filter);
    }
    elsif ($active_choice == $shapefile_idx) {
        $f_widget->set_filter($shapefiles_filter);
    }

    return;
}

sub onFileChanged {
    my $chooser = shift;
    my $dlgxml = shift;

    my $text = $dlgxml->get_widget("txtImportNew$import_n");
    my @filenames = $chooser->get_filenames();

    # Default name to selected filename
    if ( scalar @filenames > 0) {
        my $filename = $filenames[0];
        #print $filename . "\n";
        #my $filename_in_local_encoding = Glib::filename_from_unicode $filename;
        #my $z = -f $filename_in_local_encoding;
        if ($filename =~ /\.[^.]*/) {
            my($name, $dir, $suffix) = fileparse($filename, qr/\.[^.]*/);
            $text->set_text($name);
        }
    }
    
    return;
}

sub on_new_changed {
    my $text = shift;
    my $args = shift;
    my ($gui, $dlgxml) = @{$args};

    my $name = $text->get_text();
    if ($name ne "") {

        $dlgxml->get_widget($btn_next)->set_sensitive(1);
    }
    else {

        # Disable Next if have no basedatas
        my $selected = $gui->get_project->get_selected_base_data_iter();
        if (not $selected) {
            $dlgxml->get_widget($btn_next)->set_sensitive(0);
        }
    }
    
    return;
}

sub on_new_toggled {
    my $checkbox = shift;
    my $args = shift;
    my ($gui, $dlgxml) = @{$args};

    if ($checkbox->get_active) {
        # New basedata

        $dlgxml->get_widget($txt_import_new)->set_sensitive(1);
        $dlgxml->get_widget($combo_import_basedatas)->set_sensitive(0);
    }
    else {
        # Must select existing - NOTE: checkbox is disabled if there aren't any

        $dlgxml->get_widget($txt_import_new)->set_sensitive(0);
        $dlgxml->get_widget($combo_import_basedatas)->set_sensitive(1);
    }

    return;
}

##################################################
# Column selection dialog
##################################################

sub make_columns_dialog {
    # We have to dynamically generate the choose columns dialog since
    # the number of columns is unknown

    my $header      = shift; # ref to column header array
    my $wnd_main     = shift;
    my $row_options = shift;
    my $file_list   = shift;

    my $num_columns = @$header;
    print "[GUI] Generating make columns dialog for $num_columns columns\n";

    # Make dialog
    my $dlg = Gtk2::Dialog->new(
        'Choose columns',
        $wnd_main,
        'modal',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
        'gtk-help'   => 'help',
    );

    if (defined $file_list) {
        my $file_title = Gtk2::Label ->new('<b>Files:</b>');
        $file_title->set_use_markup(1);
        $file_title->set_alignment (0, 1);
        $dlg->vbox->pack_start ($file_title, 0, 0, 0);

        my $file_list_label = Gtk2::Label ->new($file_list . "\n\n");
        $file_list_label->set_alignment (0, 1);
        $dlg->vbox->pack_start ($file_list_label, 0, 0, 0);
    }

    #my $sep = Gtk2::HSeparator->new();
    #$dlg->vbox->pack_start ($sep, 0, 0, 0);

    my $label = Gtk2::Label->new('<b>Set column options</b>');
    $label->set_use_markup(1);
    $dlg->vbox->pack_start ($label, 0, 0, 0);

    # Make table
    my $table = Gtk2::Table->new($num_columns + 1, 8);
    $table->set_row_spacings(5);
    $table->set_col_spacings(20);

    # Make scroll window for table
    my $scroll = Gtk2::ScrolledWindow->new;
    $scroll->add_with_viewport($table);
    $scroll->set_policy('never', 'automatic');
    $dlg->vbox->pack_start($scroll, 1, 1, 5);

    my $col = 0;
    # Make header column
    $label = Gtk2::Label->new('<b>#</b>');
    $label->set_alignment(0.5, 1);
    $label->set_use_markup(1);
    $table->attach($label, $col, $col + 1, 0, 1, ['expand', 'fill'], 'shrink', 0, 0);
    
    $col++;
    $label = Gtk2::Label->new('<b>Column</b>');
    $label->set_alignment(0, 1);
    $label->set_use_markup(1);
    $table->attach($label, $col, $col + 1, 0, 1, ['expand', 'fill'], 'shrink', 0, 0);

    $col++;
    $label = Gtk2::Label->new('Type');
    $label->set_alignment(0.5, 1);
    $label->set_has_tooltip(1);
    $label->set_tooltip_text ('Click on the help to see the column meanings');
    $table->attach($label, $col, $col + 1, 0, 1, ['expand', 'fill'], 'shrink', 0, 0);

    $col++;
    $label = Gtk2::Label->new('Cell size');
    $label->set_alignment(0.5, 1);
    $label->set_has_tooltip(1);
    $label->set_tooltip_text ('Width of the group along this axis');
    $table->attach($label, $col, $col + 1, 0, 1, ['expand', 'fill'], 'shrink', 50, 0);

    $col++;
    $label = Gtk2::Label->new('Cell origin');
    $label->set_alignment(0.5, 1);
    $label->set_has_tooltip(1);
    $label->set_tooltip_text ('Origin of this axis.\nGroup corners will be offset by this amount.');
    $table->attach($label, $col, $col + 1, 0, 1, ['expand', 'fill'], 'shrink', 50, 0);
    
    $col++;
    $label = Gtk2::Label->new("Data in\ndegrees?");
    $label->set_alignment(0.5, 1);
    $label->set_has_tooltip(1);
    $label->set_tooltip_text ('Are the group data for this axis in degrees latitude or longitude?');
    $table->attach($label, $col, $col + 1, 0, 1, ['expand', 'fill'], 'shrink', 0, 0);

    # Add columns
    # use row_widgets to store the radio buttons, spinboxes
    my $row_widgets = [];
    foreach my $i (0..($num_columns - 1)) {
        my $row_label_text = $header->[$i] // q{};
        add_row($row_widgets, $table, $i, $row_label_text, $row_options);
    }

    $dlg->set_resizable(1);
    $dlg->set_default_size(0, 400);
    $dlg->show_all();

    # Hide the cell size textboxes since all columns are "Ignored" by default
    foreach my $row (@$row_widgets) {
        $row->[1]->hide;
        $row->[2]->hide;
        $row->[3]->hide;
    }
    
    #  now add the help text

    return ($dlg, $row_widgets);
}

sub add_row {
    my ($row_widgets, $table, $col_id, $header, $row_options) = @_;
    
    if (!defined $header) {
        $header = q{};
    }
    
    if ((ref $row_options) !~ /ARRAY/ or scalar @$row_options == 0) {
        $row_options = [qw /
            Ignore
            Label
            Group
            Text_group
            Sample_counts
            Include_columns
            Exclude_columns
        /];
    }

    #  column number
    my $i_label = Gtk2::Label->new($col_id);
    $i_label->set_alignment(0.5, 1);
    $i_label->set_use_markup(1);

    # Column header    
    my $label = Gtk2::Label->new("<tt>$header</tt>");
    $label->set_alignment(0.5, 1);
    $label->set_use_markup(1);

    # Type combo box
    my $combo = Gtk2::ComboBox->new_text;
    foreach (@$row_options) {
        $combo->append_text($_);
    }
    $combo->set_active(0);

    # Cell sizes/snaps
    my $adj1  = Gtk2::Adjustment->new (100000, 0, 10000000, 100, 10000, 0);
    my $spin1 = Gtk2::SpinButton->new ($adj1, 100, 7);

    my $adj2  = Gtk2::Adjustment->new (0, -1000000, 1000000, 100, 10000, 0);
    my $spin2 = Gtk2::SpinButton->new ($adj2, 100, 7);

    $spin1->hide(); # By default, columns are "ignored" so cell sizes don't apply
    $spin2->hide();
    $spin1->set_numeric(1);
    $spin2->set_numeric(1);
    
    #  degrees minutes seconds
    my $combo_dms = Gtk2::ComboBox->new_text;
    $combo_dms->set_has_tooltip (1);
    my $tooltip_text = q{Set to 'is_lat' if column contains latitude values, }
                       . q{'is_lon' if longitude values. Leave as blank if neither.};
    $combo_dms->set_tooltip_text ($tooltip_text);
    foreach my $choice ('', 'is_lat', 'is_lon') {
        $combo_dms->append_text($choice);
    }
    $combo_dms->set_active(0);

    # Attach to table
    my $i = 0;
    foreach my $option ($i_label, $label, $combo, $spin1, $spin2, $combo_dms) {
        $table->attach(
            $option,
            $i,
            $i + 1,
            $col_id + 1,
            $col_id + 2,
            'shrink',
            'shrink',
            0,
            0,
        );
        $i++;
    }

    # Signal to enable/disable spin buttons
    $combo->signal_connect_swapped(
        changed => \&on_type_combo_changed,
        [$spin1, $spin2, $combo_dms],
    );

    # Store widgets
    $row_widgets->[$col_id] = [$combo, $spin1, $spin2, $combo_dms];
    
    return;
}

sub on_type_combo_changed {
    my $spins = shift;
    my $combo = shift;
    
    # show/hide other widgets depending on if selected is to be a group column
    my $selected = $combo->get_active_text;
    my $show_or_hide = $selected eq 'Group' ? 'show' : 'hide';
    foreach my $widget (@$spins) {
        $widget->$show_or_hide;
    }

    return;
}


##################################################
# Load Label remap file
##################################################

# Asks user whether remap is required
#   returns (filename, in column, out column)
sub get_remap_info {
    my $gui              = shift;
    my $data_filename    = shift;
    my $type             = shift // "";
    my $other_properties = shift || [];
    my $column_overrides = shift;
    my $filename         = shift;
    
    my ($_file, $data_dir, $_suffixes) = $data_filename && length $data_filename
        ? fileparse($data_filename)
        : ();

    # Get filename for the name-translation file
    $filename //= $gui->show_open_dialog("Select $type properties file", '*', $data_dir);
    if (! defined $filename) {
        return wantarray ? () : {}
    };
    
    my $remap = Biodiverse::ElementProperties->new;
    my %args = $remap->get_args (sub => 'import_data');
    my $params = $args{parameters};
    
    #  much of the following is used elsewhere to get file options, almost verbatim.  Should move to a sub.
    my $dlgxml = Gtk2::GladeXML->new($gui->get_glade_file, 'dlgImportParameters');
    my $dlg = $dlgxml->get_widget('dlgImportParameters');
    $dlg->set_title(ucfirst "$type property file options");

    # Build widgets for parameters
    my $table_name = 'tableImportParameters';
    my $table = $dlgxml->get_widget ($table_name );
    # (passing $dlgxml because generateFile uses existing glade widget on the dialog)
    my $extractors = Biodiverse::GUI::ParametersTable::fill ($params, $table, $dlgxml); 
    
    $dlg->show_all;
    my $response = $dlg->run;
    $dlg->destroy;
    
    if ($response ne 'ok') {  #  drop out
        return wantarray ? () : {};
    }
    
    my $properties_params = Biodiverse::GUI::ParametersTable::extract ($extractors);
    my %properties_params = @$properties_params;
    
    # Get header columns
    print "[GUI] Discovering columns from $filename\n";
    
    open (my $input_fh, '<:via(File::BOM)', $filename)
      or croak "Cannot open $filename\n";

    my ($line, $line_unchomped);
    while (<$input_fh>) { # get first non-blank line
        $line = $_;
        $line_unchomped = $line;
        chomp $line;
        last if $line;
    }
    close ($input_fh);
    
    my $sep     = $properties_params{input_sep_char} eq 'guess' 
                ? $gui->get_project->guess_field_separator (string => $line)
                : $properties_params{input_sep_char};
                
    my $quotes  = $properties_params{input_quote_char} eq 'guess'
                ? $gui->get_project->guess_quote_char (string => $line)
                : $properties_params{input_quote_char};
                
    my $eol     = $gui->get_project->guess_eol (string => $line_unchomped);
    
    my @headers_full = $gui->get_project->csv2list(
        string     => $line_unchomped,
        quote_char => $quotes,
        sep_char   => $sep,
        eol        => $eol
    );

    # add non-blank columns
    # - SWL 20081201 - not sure this is a good idea, should just use all
    my @headers;
    foreach my $header (@headers_full) {
        if ($header) {
            push @headers, $header;
        }
    }

    ($dlg, my $col_widgets) = make_remap_columns_dialog (
        \@headers,
        $gui->get_widget('wndMain'),
        $other_properties,
        $column_overrides,
    );
    
    my $column_settings = {};
    $dlg->set_title(ucfirst "$type property column types");

    RUN_DLG:
    while (1) {
        $response = $dlg->run();
        if ($response eq 'help') {
            explain_remap_col_options($dlg);
            next RUN_DLG;
        }
        elsif ($response eq 'ok') {
            $column_settings = get_remap_column_settings ($col_widgets, \@headers);
        }
        else {
            $dlg->destroy();
            return wantarray ? () : {};
        }

        #  drop out
        last RUN_DLG if $column_settings->{Input_element};

        #  need to check we have the right number...
        my $text = 'Please select as many Input_element columns as you have label axes';
        my $msg = Gtk2::MessageDialog->new (
            undef,
            'modal',
            'error',
            'ok',
            $text
        );

        $msg->run();
        $msg->destroy();
    }
    
    $dlg->destroy();

    #Input_label Remapped_label Range
    
    my (@in_cols, @out_cols, @include_cols, @exclude_cols);
    
    my $in_ref = $column_settings->{Input_element};
    foreach my $i (@$in_ref) {
        push @in_cols, $i->{id};
    }
    my $out_ref = $column_settings->{Remapped_element};
    foreach my $i (@$out_ref) {
        push @out_cols, $i->{id};
    }
    my $include_ref = $column_settings->{Include};
    foreach my $i (@$include_ref) {
        push @include_cols, $i->{id};
    }
    my $exclude_ref = $column_settings->{Exclude};
    foreach my $i (@$exclude_ref) {
        push @exclude_cols, $i->{id};
    }

    my %results = (
        file                    => $filename,
        input_element_cols      => \@in_cols,
        remapped_element_cols   => \@out_cols,
        input_sep_char          => $args{input_sep_char},  #  header might be sufficiently different to matter
        input_quote_char        => $args{input_quote_char},
        include_cols            => \@include_cols,
        exclude_cols            => \@exclude_cols,
    );

    #foreach my $type (qw /Range Sample_count Property/) {
    foreach my $type (@$other_properties, 'Property') {
        my $ref = $column_settings->{$type};
        next if ! defined $ref;
        $ref = [$ref] if $ref !~ /ARRAY/;
        foreach my $i (@$ref) {
            my $t = $type;
            if ($t eq 'Property') {
                $t = $i->{name};
            }
            $results{lc($t)} = $i->{id};  #  take the last one selected
        }
    }

    if ($sep ne 'guess') {
        $results{input_sep_char} = $sep;
    }
    if ($quotes ne 'guess') {
        $results{input_quote_char} = $quotes;
    }
    #if ($eol ne 'guess') {
    #    $results{eol} = $eol;
    #}

    return wantarray ? %results : \%results;
}

# We have to dynamically generate the choose columns dialog since
# the number of columns is unknown
sub make_remap_columns_dialog {
    my $header           = shift; # ref to column header array
    my $wnd_main          = shift;
    my $other_props      = shift || [];
    my $column_overrides = shift;

    my $num_columns = @$header;
    print "[GUI] Generating make columns dialog for $num_columns columns\n";

    # Make dialog
    my $dlg = Gtk2::Dialog->new(
        'Choose columns',
        $wnd_main,
        'modal',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
        'gtk-help'   => 'help',
    );
    my $label = Gtk2::Label->new("<b>Select column types</b>");
    $label->set_use_markup(1);
    $dlg->vbox->pack_start ($label, 0, 0, 0);

    # Make table    
    my $table = Gtk2::Table->new($num_columns + 1, 8);
    $table->set_row_spacings(5);
    $table->set_col_spacings(20);

    # Make scroll window for table
    my $scroll = Gtk2::ScrolledWindow->new;
    $scroll->add_with_viewport($table);
    $scroll->set_policy('never', 'automatic');
    $dlg->vbox->pack_start($scroll, 1, 1, 5);

    my $col = 0;

    # Make ID column
    $label = Gtk2::Label->new('<b>#</b>');
    $label->set_alignment(0.5, 1);
    $label->set_use_markup(1);
    $table->attach($label, $col, $col + 1, 0, 1, ['expand', 'fill'], 'shrink', 0, 0);

    # Make header column
    $col ++;
    $label = Gtk2::Label->new('<b>Column</b>');
    $label->set_alignment(0.5, 1);
    $label->set_use_markup(1);
    $table->attach($label, $col, $col + 1, 0, 1, ['expand', 'fill'], 'shrink', 0, 0);

    $col ++;
    $label = Gtk2::Label->new('Type');
    $label->set_alignment(0.5, 1);
    $table->attach($label, $col, $col + 1, 0, 1, ['expand', 'fill'], 'shrink', 0, 0);

    # Add columns
    # use row_widgets to store the radio buttons, spinboxes
    my $row_widgets = [];
    foreach my $i (0..($num_columns - 1)) {
        add_remap_row($row_widgets, $table, $i, $header->[$i], $other_props, $column_overrides);
    }

    $dlg->set_resizable(1);
    $dlg->set_default_size(0, 400);
    $dlg->show_all();

    return ($dlg, $row_widgets);
}

sub get_remap_column_settings {
    my $cols = shift;
    my $headers = shift;
    my $num = @$cols;
    my (@in, @out);
    my %results;

    foreach my $i (0..($num - 1)) {
        my $widgets = $cols->[$i];
        # widgets[0] - combo

        my $type = $widgets->[0]->get_active_text;
        
        #  sweep up all those we should not ignore
        if ($type ne "Ignore") {
            $results{$type} = [] if ! defined $results{$type};
            my $ref = $results{$type};
            push @{$ref}, {name => $headers->[$i], id => $i };
        }
    }

    return wantarray ? %results : \%results;
}

sub add_remap_row {
    my ($row_widgets, $table, $col_id, $header, $other_props, $column_overrides) = @_;

    #  column number
    my $i_label = Gtk2::Label->new($col_id);
    $i_label->set_alignment(0.5, 1);
    $i_label->set_use_markup(1);

    # Column header
    my $label = Gtk2::Label->new("<tt>$header</tt>");
    $label->set_use_markup(1);

    # Type combo box
    my $combo = Gtk2::ComboBox->new_text;
    my @options = $column_overrides
        ? @$column_overrides
        : (qw /Input_element Remapped_element Include Exclude Property/, @$other_props);
    unshift @options, 'Ignore';

    foreach (@options) {
        $combo->append_text($_);
    }
    $combo->set_active(0);


    # Attach to table
    $table->attach($i_label, 0, 1, $col_id + 1, $col_id + 2, 'shrink', 'shrink', 0, 0);
    $table->attach($label,   1, 2, $col_id + 1, $col_id + 2, 'shrink', 'shrink', 0, 0);
    $table->attach($combo,   2, 3, $col_id + 1, $col_id + 2, 'shrink', 'shrink', 0, 0);

    # Store widgets
    $row_widgets->[$col_id] = [$combo];

    return;
}


1;
