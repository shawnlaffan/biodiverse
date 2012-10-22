package Biodiverse::GUI::BasedataImport;

use strict;
use warnings;
use English ( -no_match_vars );

use Carp;

our $VERSION = '0.16';

use File::Basename;
use Gtk2;
use Gtk2::GladeXML;
use Text::Wrapper;
use File::BOM qw / :subs /;

use Scalar::Util qw /reftype/;

no warnings 'redefine';  #  getting redefine warnings, which aren't a problem for us

use Biodiverse::GUI::Project;
use Biodiverse::ElementProperties;

#  for use in check_if_r_data_frame
use Biodiverse::Common;

#  a few name setups for a change-over that never happened
my $import_n = ""; #  use "" for orig, 3 for the one with embedded params table
my $dlg_name = "dlgImport1";
my $chkNew = "chkNew$import_n";
my $btnNext = "btnNext$import_n";
my $comboImportBasedatas = "comboImportBasedatas$import_n";
my $filechooserInput = "filechooserInput$import_n";
my $txtImportNew = "txtImportNew$import_n";
my $tableParameters = "tableParameters$import_n";


##################################################
# High-level procedure
##################################################

sub run {
    my $gui = shift;

    #########
    # 1. Get the target basedata & filename
    #########
    my ($dlgxml, $dlg) = makeFilenameDialog($gui);
    my $response = $dlg->run();
    
    if ($response ne 'ok') {  #  clean up and drop out
        $dlg -> destroy;
        return;
    }
    
    my ($use_new, $basedata_ref);

    #if ($response eq 'ok') {

    $use_new = $dlgxml->get_widget($chkNew)->get_active();
    if ($use_new) {
        # Add it
        # FIXME: why am i adding it now?? better at the end?
        my $basedata_name = $dlgxml->get_widget($txtImportNew)->get_text();
        $basedata_ref = $gui->getProject->addBaseData($basedata_name);
    }
    else {
        # Get selected basedata
        my $selected = $dlgxml->get_widget($comboImportBasedatas)->get_active_iter();
        $basedata_ref = $gui->getProject->getBasedataModel->get($selected, MODEL_OBJECT);
    }

    # Get selected filenames
    my @filenames = $dlgxml->get_widget($filechooserInput)->get_filenames();
    my $file_list_as_text = join ("\n", @filenames);
    $dlg->destroy();
    
    #########
    # 1a. Get parameters to use
    #########
    $dlgxml = Gtk2::GladeXML->new($gui->getGladeFile, 'dlgImportParameters');
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
    my %args = $basedata_ref -> get_args (sub => 'import_data');
    my $params = $args{parameters};

    # Build widgets for parameters
    my $table = $dlgxml -> get_widget ('tableImportParameters');
    # (passing $dlgxml because generateFile uses existing glade widget on the dialog)
    my $extractors = Biodiverse::GUI::ParametersTable::fill ($params, $table, $dlgxml); 
    
    $dlg->show_all;
    $response = $dlg -> run;
    $dlg -> destroy;
    
    if ($response ne 'ok') {  #  clean up and drop out
        if ($use_new) {
            $gui->getProject->deleteBaseData($basedata_ref);
        }
        return;
    }
    my $import_params = Biodiverse::GUI::ParametersTable::extract ($extractors);
    my %import_params = @$import_params;


    # Get header columns
    print "[GUI] Discovering columns from $filenames[0]\n";
    
    my $open_success = open (my $fh, '<:via(File::BOM)', $filenames[0]);
    my $line = <$fh>;
    close ($fh);

    my $sep     = $import_params{input_sep_char} eq 'guess' 
                ? $gui->getProject->guess_field_separator (string => $line)
                : $import_params{input_sep_char};

    my $quotes  = $import_params{input_quote_char} eq 'guess'
                ? $gui->getProject->guess_quote_char (string => $line)
                : $import_params{input_quote_char};
            
    my $eol     = $gui->getProject->guess_eol (string => $line);

    my @header  = $gui->getProject->csv2list(
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

    my $use_matrix = $import_params{data_in_matrix_form};
    my $col_names_for_dialog = \@header;
    my $col_options = undef;

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

    #########
    # 2. Get column types (using first file...)
    #########
    my $row_widgets;
    ($dlg, $row_widgets) = makeColumnsDialog (
        $col_names_for_dialog,
        $gui->getWidget('wndMain'),
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
            $column_settings = getColumnSettings($row_widgets, $col_names_for_dialog);
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
            #$num_labels = 1 if $use_matrix;  #  sidestep the next check for labels

            if ($num_groups == 0 || $num_labels == 0) {
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
            $gui->getProject->deleteBaseData ($basedata_ref) ;
        }
        return;
    }

    #########
    # 3. Get column order
    #########
    my $old_labels_array = $column_settings->{labels};
    if ($use_matrix) {
        $column_settings->{labels}
            = [{name => 'From file', id => 0}];
    }
    
    ($dlgxml, $dlg) = makeReorderDialog($gui, $column_settings);
    $response = $dlg->run();
    
    $params = fillParams($dlgxml);
    $dlg->destroy();

    if ($response ne 'ok') {  #  clean up and drop out
        if ($use_new) {
            $gui -> getProject -> deleteBaseData ($basedata_ref);
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
            my %remap_data = getRemapInfo (
                $gui,
                $filenames[0],
                $type,
                $other_properties{$type},
            );

            #  now do something with them...
            my $remap;
            if ($remap_data{file}) {
                #my $file = $remap_data{file};
                $remap = Biodiverse::ElementProperties -> new;
                $remap -> import_data (%remap_data);
            }
            $import_params{"$type\_properties"} = $remap;
            if (not defined $remap) {
                $import_params{"use_$type\_properties"} = undef;
            }
        }
    }


    $params->{INPUT_FILES} = \@filenames;

    #########
    # 4. Load the data
    #########
    # Set the parameters   #  SWL - need to rethink this to work with args instead
    foreach my $param (keys %$params) {
        $basedata_ref->set_param($param, $params->{$param});
    }
    
    #  get the sample count columns.  could do in fillParams, but these are
    #    not reordered while fillParams deals with the re-ordering.  
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

    #my $progress = Biodiverse::GUI::ProgressDialog->new;
    my $success = eval {
        $basedata_ref->load_data(
            #progress                => $progress,
            %import_params,
            %rest_of_options,
            #label_remap            => $remap,
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
        #$progress->destroy;
        $gui -> report_error ($text);
    }
    #else {
        #$progress->destroy;
    #}

    return $basedata_ref if $success;
    
    # Delete new basedata if there's a cancel and we get this far
    # (which we should not)
    if ($use_new && $basedata_ref) {
        $gui->getProject->deleteBaseData($basedata_ref);
    }

    #$dlg->destroy();
    
    return;
}


sub check_if_r_data_frame {
    my %args = @_;
    
    my $package = 'Biodiverse::Common';
    my $csv = $package -> get_csv_object (@_);
    
    my $fh;
    open ($fh, '<:via(File::BOM)', $args{file})
        || croak "Unable to open file $args{file}\n";

    my @lines = $package -> get_next_line_set (
        target_line_count => 10,
        file_handle       => $fh,
        csv_object        => $csv,
    );

    $fh -> close;

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
sub getColumnSettings {
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
sub fillParams {
    my $dlgxml = shift;

    my $labelsModel = $dlgxml->get_widget('labels')->get_model();
    my $groupsModel = $dlgxml->get_widget('groups')->get_model();
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
    $iter = $labelsModel->get_iter_first();
    while ($iter) {
        my $info = $labelsModel->get($iter, 1);

        push (@{$params{'LABEL_COLUMNS'}}, $info->{id});
    
        $iter = $labelsModel->iter_next($iter);
    }

    # Do groups
    $iter = $groupsModel->get_iter_first();
    while ($iter) {
        my $info2 = $groupsModel->get($iter, 1);

        push (@{$params{'GROUP_COLUMNS'}}, $info2->{id});
        push (@{$params{'CELL_SIZES'}},    $info2->{cell_size});
        push (@{$params{'CELL_ORIGINS'}},  $info2->{cell_origin});
        push (@{$params{'CELL_IS_LAT'}},   $info2->{is_lat});
        push (@{$params{'CELL_IS_LON'}},   $info2->{is_lon});

        $iter = $groupsModel->iter_next($iter);
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

sub makeReorderDialog {
    my $gui = shift;
    my $columns = shift;

    my $dlgxml = Gtk2::GladeXML->new($gui->getGladeFile, 'dlgReorderColumns');
    my $dlg = $dlgxml->get_widget('dlgReorderColumns');
    $dlg->set_transient_for( $gui->getWidget('wndMain') );
    
    my $listGroups = setupReorderList('groups', $dlgxml, $columns->{groups});
    my $listLabels = setupReorderList('labels', $dlgxml, $columns->{labels});

    # Make the selections mutually exclusive (if selection made, unselect selection in other list)
    $listGroups->get_selection->signal_connect(
        changed => \&unselectOther,
        $listLabels,
    );
    $listLabels->get_selection->signal_connect(
        changed => \&unselectOther,
        $listGroups,
    );

    # Connect up/down buttons
    $dlgxml->get_widget('btnUp')->signal_connect(
        clicked => \&onUpDown,
        ['up', $listGroups, $listLabels],
    );
    $dlgxml->get_widget('btnDown')->signal_connect(
        clicked => \&onUpDown,
        ['down', $listGroups, $listLabels],
    );

    return ($dlgxml, $dlg);
}

sub setupReorderList {
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
    
    my $colName = Gtk2::TreeViewColumn->new();
    my $nameRenderer = Gtk2::CellRendererText->new();
    $colName->set_sizing('fixed');
    $colName->pack_start($nameRenderer, 1);
    $colName->add_attribute($nameRenderer,  text => 0);
    
    $list->insert_column($colName, -1);
    $list->set_headers_visible(0);
    $list->set_reorderable(1);
    $list->set_model( $model );
    
    return $list;
}


# If selected something, clear the other lists' selection
sub unselectOther {
    my $selection = shift;
    my $other_list = shift;

    if ($selection->count_selected_rows() > 0) {
        $other_list->get_selection->unselect_all();
    }
    
    return;
}

sub onUpDown {
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
    
sub makeFilenameDialog {
    my $gui = shift;
    #my $object = shift || return;
    
    my $dlgxml = Gtk2::GladeXML->new($gui->getGladeFile, $dlg_name);
    my $dlg = $dlgxml->get_widget($dlg_name);
    my $x = $gui->getWidget('wndMain');
    $dlg->set_transient_for( $x );
    
#    # Get the Parameters metadata
#    my $tmp = Biodiverse::BaseData -> new;
#        my %args = $tmp -> get_args (sub => 'import_data');
#    my $params = $args{parameters};
#
#    # Build widgets for parameters
#    my $table = $dlgxml->get_widget($tableParameters);
#    # (passing $dlgxml because generateFile uses existing glade widget on the dialog)
#    my $extractors = Biodiverse::GUI::ParametersTable::fill($params, $table, $dlgxml); 


    # Initialise the basedatas combo
    $dlgxml->get_widget($comboImportBasedatas)->set_model($gui->getProject->getBasedataModel());
    my $selected = $gui->getProject->getSelectedBaseDataIter();
    if (defined $selected) {
        $dlgxml->get_widget($comboImportBasedatas)->set_active_iter($selected);
    }

    # If there are no basedatas, force "New" checkbox on
    if (not $selected) {
        $dlgxml->get_widget($chkNew)->set_sensitive(0);
        $dlgxml->get_widget($btnNext)->set_sensitive(0);
    }

    # Default to new
    $dlgxml->get_widget($chkNew)->set_active(1);
    $dlgxml->get_widget($comboImportBasedatas)->set_sensitive(0);


    # Init the file chooser
    my $filter = Gtk2::FileFilter->new();
    $filter->add_pattern('*.csv');
    $filter->add_pattern('*.txt');
    #$filter->add_pattern("*");
    $filter->set_name('txt and csv files');
    $dlgxml->get_widget($filechooserInput)    -> add_filter($filter);
    $filter = Gtk2::FileFilter->new();
    $filter->add_pattern('*');
    $filter->set_name('all files');
    $dlgxml->get_widget($filechooserInput)    -> add_filter($filter);
    
    $dlgxml->get_widget($filechooserInput)    -> set_select_multiple(1);
    $dlgxml->get_widget($filechooserInput)    -> signal_connect('selection-changed' => \&onFileChanged, $dlgxml);

    $dlgxml->get_widget($chkNew)->signal_connect(toggled => \&onNewToggled, [$gui, $dlgxml]);
    $dlgxml->get_widget($txtImportNew)->signal_connect(changed => \&onNewChanged, [$gui, $dlgxml]);
    
    return ($dlgxml, $dlg);
}

sub onFileChanged {
    my $chooser = shift;
    my $dlgxml = shift;

    my $text = $dlgxml->get_widget("txtImportNew$import_n");
    my @filenames = $chooser->get_filenames();

    # Default name to selected filename
    if ( scalar @filenames > 0) {
        my $filename = $filenames[0];
        if (-f $filename) {
            my($name, $dir, $suffix) = fileparse($filename, qr/\.[^.]*/);
            $text->set_text($name);
        }
    }
    
    return;
}

sub onNewChanged {
    my $text = shift;
    my $args = shift;
    my ($gui, $dlgxml) = @{$args};

    my $name = $text->get_text();
    if ($name ne "") {

        $dlgxml->get_widget($btnNext)->set_sensitive(1);
    }
    else {

        # Disable Next if have no basedatas
        my $selected = $gui->getProject->getSelectedBaseDataIter();
        if (not $selected) {
            $dlgxml->get_widget($btnNext)->set_sensitive(0);
        }
    }
    
    return;
}

sub onNewToggled {
    my $checkbox = shift;
    my $args = shift;
    my ($gui, $dlgxml) = @{$args};

    if ($checkbox->get_active) {
        # New basedata

        $dlgxml->get_widget($txtImportNew)->set_sensitive(1);
        $dlgxml->get_widget($comboImportBasedatas)->set_sensitive(0);
    }
    else {
        # Must select existing - NOTE: checkbox is disabled if there aren't any

        $dlgxml->get_widget($txtImportNew)->set_sensitive(0);
        $dlgxml->get_widget($comboImportBasedatas)->set_sensitive(1);
    }

    return;
}

##################################################
# Column selection dialog
##################################################

sub makeColumnsDialog {
    # We have to dynamically generate the choose columns dialog since
    # the number of columns is unknown

    my $header      = shift; # ref to column header array
    my $wndMain     = shift;
    my $row_options = shift;
    my $file_list   = shift;

    my $num_columns = @$header;
    print "[GUI] Generating make columns dialog for $num_columns columns\n";

    # Make dialog
    my $dlg = Gtk2::Dialog->new(
        'Choose columns',
        $wndMain,
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
        my $row_label_text = defined $header->[$i] ? $header->[$i] : q{};
        addRow($row_widgets, $table, $i, $row_label_text, $row_options);
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

sub addRow {
    my ($row_widgets, $table, $colId, $header, $row_options) = @_;
    
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
    my $i_label = Gtk2::Label->new($colId);
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
    my $adj1  = Gtk2::Adjustment -> new (100000, 0, 10000000, 100, 10000, 0);
    my $spin1 = Gtk2::SpinButton -> new ($adj1, 100, 4);

    my $adj2  = Gtk2::Adjustment -> new (0, -1000000, 1000000, 100, 10000, 0);
    my $spin2 = Gtk2::SpinButton -> new ($adj2, 100, 4);

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
            $colId + 1,
            $colId + 2,
            'shrink',
            'shrink',
            0,
            0,
        );
        $i++;
    }

    # Signal to enable/disable spin buttons
    $combo->signal_connect_swapped(
        changed => \&onTypeComboChanged,
        [$spin1, $spin2, $combo_dms],
    );

    # Store widgets
    $row_widgets->[$colId] = [$combo, $spin1, $spin2, $combo_dms];
    
    return;
}

sub onTypeComboChanged {
    my $spins = shift;
    my $combo = shift;
    
    # show/hide other widgets depending on if selected is to be a group column
    my $selected = $combo->get_active_text;
    my $show_or_hide = $selected eq 'Group' ? 'show' : 'hide';
    foreach my $widget (@$spins) {
        $widget -> $show_or_hide;
    }

    return;
}


##################################################
# Load Label remap file
##################################################

# Asks user whether remap is required
#   returns (filename, in column, out column)
sub getRemapInfo {
    my $gui = shift;
    my $data_filename = shift;
    my $type = shift || "";
    my $other_properties = shift || [];
    
    my ($_file, $data_dir, $_suffixes) = fileparse($data_filename);

    # Get filename for the name-translation file
    my $filename = $gui->showOpenDialog("Select $type properties file", '*', $data_dir);
    if (! defined $filename) {
        return wantarray ? () : {}
    };
    
    my $remap = Biodiverse::ElementProperties -> new;
    my %args = $remap -> get_args (sub => 'import_data');
    my $params = $args{parameters};
    
    #  much of the following is used elsewhere to get file options, almost verbatim.  Should move to a sub.
    my $dlgxml = Gtk2::GladeXML->new($gui->getGladeFile, 'dlgImportParameters');
    my $dlg = $dlgxml->get_widget('dlgImportParameters');
    $dlg -> set_title(ucfirst "$type property file options");

    # Build widgets for parameters
    my $table_name = 'tableImportParameters';
    my $table = $dlgxml -> get_widget ($table_name );
    # (passing $dlgxml because generateFile uses existing glade widget on the dialog)
    my $extractors = Biodiverse::GUI::ParametersTable::fill ($params, $table, $dlgxml); 
    
    $dlg->show_all;
    my $response = $dlg -> run;
    $dlg -> destroy;
    
    if ($response ne 'ok') {  #  drop out
        return wantarray ? () : {};
    }
    
    my $properties_params = Biodiverse::GUI::ParametersTable::extract ($extractors);
    my %properties_params = @$properties_params;
    
    # Get header columns
    print "[GUI] Discovering columns from $filename\n";
    
    open (my $input_fh, '<:via(File::BOM)', $filename)
      || croak "Cannot open $filename\n";

    my ($line, $line_unchomped);
    while (<$input_fh>) { # get first non-blank line
        $line = $_;
        $line_unchomped = $line;
        chomp $line;
        last if $line;
    }
    close ($input_fh);
    
    my $sep     = $properties_params{input_sep_char} eq 'guess' 
                ? $gui->getProject->guess_field_separator (string => $line)
                : $properties_params{input_sep_char};
                
    my $quotes  = $properties_params{input_quote_char} eq 'guess'
                ? $gui->getProject->guess_quote_char (string => $line)
                : $properties_params{input_quote_char};
                
    my $eol     = $gui->getProject->guess_eol (string => $line_unchomped);
    
    my @headers_full = $gui->getProject->csv2list(
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

    ($dlg, my $col_widgets) = makeRemapColumnsDialog (
        \@headers,
        $gui->getWidget('wndMain'),
        $other_properties
    );
    
    my $column_settings = {};
    $dlg -> set_title(ucfirst "$type property column types");

    RUN_DLG:
    while (1) {
        $response = $dlg->run();
        if ($response eq 'help') {
            explain_remap_col_options($dlg);
            next RUN_DLG;
        }
        elsif ($response eq 'ok') {
            $column_settings = getRemapColumnSettings ($col_widgets, \@headers);
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
    

    return wantarray ? %results : \%results;
}


sub makeRemapColumnsDialog {
    # We have to dynamically generate the choose columns dialog since
    # the number of columns is unknown

    my $header = shift; # ref to column header array
    my $wndMain = shift;
    my $other_props = shift || [];

    my $num_columns = @$header;
    print "[GUI] Generating make columns dialog for $num_columns columns\n";

    # Make dialog
    my $dlg = Gtk2::Dialog->new(
        'Choose columns',
        $wndMain,
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
        addRemapRow($row_widgets, $table, $i, $header->[$i], $other_props);
    }

    $dlg->set_resizable(1);
    $dlg->set_default_size(0, 400);
    $dlg->show_all();

    return ($dlg, $row_widgets);
}

sub getRemapColumnSettings {
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

sub addRemapRow {
    my ($row_widgets, $table, $colId, $header, $other_props) = @_;

    #  column number
    my $i_label = Gtk2::Label->new($colId);
    $i_label->set_alignment(0.5, 1);
    $i_label->set_use_markup(1);

    # Column header
    my $label = Gtk2::Label -> new("<tt>$header</tt>");
    $label -> set_use_markup(1);

    # Type combo box
    my $combo = Gtk2::ComboBox->new_text;
    #foreach (qw /Ignore Input_element Remapped_element Range Sample_count Include Exclude Use_field_name/) {
    foreach (qw /Ignore Input_element Remapped_element Include Exclude Property/, @$other_props) {
        $combo->append_text($_);
    }
    $combo -> set_active(0);


    # Attach to table
    $table->attach($i_label, 0, 1, $colId + 1, $colId + 2, 'shrink', 'shrink', 0, 0);
    $table->attach($label, 1, 2, $colId + 1, $colId + 2, 'shrink', 'shrink', 0, 0);
    $table->attach($combo, 2, 3, $colId + 1, $colId + 2, 'shrink', 'shrink', 0, 0);
    
    # Store widgets
    $row_widgets->[$colId] = [$combo];
    
    return;
}


1;
