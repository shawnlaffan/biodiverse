package Biodiverse::GUI::BasedataImport;

use 5.010;
use strict;
use warnings;
use English ( -no_match_vars );

use Carp;

our $VERSION = '1.99_006';

use File::Basename;
use Gtk2;
use Glib;
use Text::Wrapper;
use File::BOM qw / :subs /;
use Scalar::Util qw /reftype looks_like_number blessed/;
use Geo::ShapeFile 2.54;    #  min version we neeed is 2.54
use List::Util qw /all min/;
use List::MoreUtils qw /first_index/;
use Spreadsheet::Read 0.60;

no warnings
  'redefine';    #  getting redefine warnings, which aren't a problem for us

use Biodiverse::GUI::Project;
use Biodiverse::ElementProperties;

#  for use in check_if_r_data_frame
use Biodiverse::Common;

use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';

#  A few name setups for a change-over that never happened,
#  so the the $import_n part is actually redundant.
#  The other import dialogue (#3) is no longer in the xml file.
my $import_n = '';  #  use "" for orig, 3 for the one with embedded params table
my $import_dlg_name    = "dlgImport1";
my $chk_new            = "chkNew$import_n";
my $btn_next           = "btnNext$import_n";
my $file_format        = "format_box$import_n";
my $filechooser_input  = "filechooserInput$import_n";
my $txt_import_new     = "txtImportNew$import_n";
my $table_parameters   = "tableParameters$import_n";
my $importmethod_combo = "format_box$import_n";      # not sure about the suffix
my $combo_import_basedatas     = "comboImportBasedatas$import_n";
my $chk_import_one_bd_per_file = "chk_import_one_bd_per_file$import_n";

my $text_idx      = 0;    # index in combo box
my $raster_idx    = 1;    # index in combo box of raster format
my $shapefile_idx = 2;    # index in combo box

# maintain reference for these, to allow referring when import method changes
my $txtcsv_filter;
my $allfiles_filter;
my $shapefiles_filter;
my $spreadsheets_filter;

my $lat_lon_widget_tooltip_text = <<'END_LL_TOOLTIP_TEXT'
Set to 'is_lat' if column contains latitude values,
is_lon' if longitude values. Leave as blank if neither.
END_LL_TOOLTIP_TEXT
  ;

my $max_row_spinner_tooltip_text = <<'END_MAX_ROW_TOOLTIP_TEXT'
Too many columns will slow down the GUI.
Set this to a small number to make it
manageable when the input file has a large
number of columns and the options can be set
using the first few columns,
e.g. a large matrix format file
END_MAX_ROW_TOOLTIP_TEXT
  ;

##################################################
# High-level procedure
##################################################

sub run {
    my $gui = shift;

    #########
    # 1. Get the target basedata & filename
    #########
    my ( $dlgxml, $dlg ) = make_filename_dialog($gui);
    my $response = $dlg->run();

    if ( $response ne 'ok' ) {    #  clean up and drop out
        $dlg->destroy;
        return;
    }

    my ( $use_new, $basedata_ref );
    my @format_uses_columns = qw /shapefile text spreadsheet/;

    # Get selected filenames
    my @filenames = $dlgxml->get_object($filechooser_input)->get_filenames();
    my @file_names_tmp = @filenames;
    if ( scalar @filenames > 5 ) {
        @file_names_tmp = @filenames[ 0 .. 5 ];
        push @file_names_tmp,
          '... plus ' . ( scalar @filenames - 5 ) . ' others';
    }
    my $file_list_as_text = join( "\n", @file_names_tmp );
    my @def_cellsizes = ( 100000, 100000 );

    $use_new = $dlgxml->get_object($chk_new)->get_active();

    #  do we want to import each file into its own basedata?
    my $w = $dlgxml->get_object($chk_import_one_bd_per_file);
    my $one_basedata_per_file = $w->get_active();
    my %multiple_brefs
      ;    # mapping from basedata name (eg from shortened file) to basedata ref
    my %multiple_file_lists
      ;    # mapping from basedata name to array (ref) of files
    my %multiple_is_new
      ; # mapping from basedata name to flag indicating if new (vs existing) basedata ref

    if ($one_basedata_per_file) {

        # create a new basedata for each file
        # get existing basedatas (in tree form), to check if given name exists
        my $basedata_list = $gui->get_project->get_base_data_list();

        my $count = 0;
        foreach my $file (@filenames) {

         # use basedata_ref locally, and then maintain a ref to the last created
         # basedata for some of the subsequent 'get' calls
            my $dispname = "unnamed_$count";
            $count++;
            my $existing = 0;
            if ( $file =~ /\.[^.]*/ ) {
                my ( $name, $dir, $suffix ) = fileparse( $file, qr/\.[^.]*/ );
                $dispname = $name;

    # if use_new flag is not set, check if basedata exists with given file
    # name, if so add to existing.  if not found, a new basedata will be created
                if ( !$use_new ) {
                    foreach my $existing_bdref (@$basedata_list) {
                        if ( $existing_bdref->get_param('NAME') eq $dispname ) {
                            $existing     = 1;
                            $basedata_ref = $existing_bdref;
                            last;
                        }
                    }
                }
            }

            if ( !$existing ) {
                $basedata_ref = Biodiverse::BaseData->new(
                    NAME => $dispname,
                    CELL_SIZES =>
                      \@def_cellsizes    #  default, gets overridden later
                );
            }

            $multiple_brefs{$file}      = $basedata_ref;
            $multiple_file_lists{$file} = [$file];
            $multiple_is_new{$file}     = !$existing;
        }
    }
    elsif ($use_new) {
        my $basedata_name = $dlgxml->get_object($txt_import_new)->get_text();

        $basedata_ref = Biodiverse::BaseData->new(
            NAME       => $basedata_name,
            CELL_SIZES => \@def_cellsizes    #  default, gets overridden later
        );
        $multiple_brefs{$basedata_name}      = $basedata_ref;
        $multiple_file_lists{$basedata_name} = \@filenames;
        $multiple_is_new{$basedata_name}     = 1;
    }
    else {
        # Get selected basedata
        my $selected =
          $dlgxml->get_object($combo_import_basedatas)->get_active_iter();
        $basedata_ref =
          $gui->get_project->get_basedata_model->get( $selected, MODEL_OBJECT );
        my $basedata_name = $basedata_ref->get_param('NAME');
        $multiple_brefs{$basedata_name}      = $basedata_ref;
        $multiple_file_lists{$basedata_name} = \@filenames;
    }

    # interpret if raster, text etc depending on format box
    my $read_format = lc $dlgxml->get_object($file_format)->get_active_text;

    $dlg->destroy();

    #########
    # 1a. Get parameters to use
    #########
    $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file( $gui->get_gtk_ui_file('dlgImportParameters.ui') );
    $dlg = $dlgxml->get_object('dlgImportParameters');

    #  add file name labels to display
    my $vbox = Gtk2::VBox->new( 0, 0 );
    my $file_title = Gtk2::Label->new('<b>Files:</b>');
    $file_title->set_use_markup(1);
    $file_title->set_alignment( 0, 1 );
    $vbox->pack_start( $file_title, 0, 0, 0 );

    my $file_list_label = Gtk2::Label->new( $file_list_as_text . "\n\n" );
    $file_list_label->set_alignment( 0, 1 );
    $vbox->pack_start( $file_list_label, 0, 0, 0 );
    my $import_vbox = $dlgxml->get_object('import_parameters_vbox');
    $import_vbox->pack_start( $vbox, 0, 0, 0 );
    $import_vbox->reorder_child( $vbox, 0 );    #  move to start

    #  get any options
    # Get the Parameters metadata
    # start with common parameters
    my %args = $basedata_ref->get_args( sub => 'import_data_common' );

    # set visible fields in import dialog
    if ( $read_format eq 'text' ) {
        my %text_args = $basedata_ref->get_args( sub => 'import_data_text' );

        # add new params to args
        push @{ $args{parameters} }, @{ $text_args{parameters} };
    }
    elsif ( $read_format eq 'raster' ) {
        my %raster_args =
          $basedata_ref->get_args( sub => 'import_data_raster' );

        # add new params to args
        push @{ $args{parameters} }, @{ $raster_args{parameters} };
    }
    else {
        #  for spreadsheet and shapefile we filter out the remap stuff
        #  until we remove it completely from the import stage
        my $p  = $args{parameters};
        my @p2 = grep {
            print $_->get_name;
            not $_->get_name =~ /use_(label|group)_properties/
        } @$p;
        $args{parameters} = \@p2;
    }
    my $max_col_spinner = {
        name    => 'max_opt_cols',
        type    => 'integer',
        default => 100,
        label_text =>
'Maximum number of header columns to show options for (includes remap dialogues)',
        tooltip => $max_row_spinner_tooltip_text,
    };
    push @{ $args{parameters} }, $max_col_spinner;

    my $gp_axis_dp = $ENV{BD_IMPORT_DP} || 7;
    if ( !looks_like_number $gp_axis_dp) {
        $gp_axis_dp = 7;
    }
    my $gp_axis_precision_spinner = {
        name       => 'gp_axis_precision',
        type       => 'integer',
        default    => $gp_axis_dp,
        min        => 1,
        max        => 15,
        label_text => 'Number of decimal places used in cell sizes',
        tooltip =>
'Number of decimal places in cell size specifiers (sizes and offsets)',
    };
    push @{ $args{parameters} }, $gp_axis_precision_spinner;

    #  should not need to do this
    for ( @{ $args{parameters} } ) {
        bless $_, $parameter_metadata_class if !blessed $_;
    }

    my %import_params;
    my $table_params;
    $table_params = $args{parameters};

    my @cell_sizes;
    my @cell_origins;
    if ( $read_format eq 'raster' ) {

        # set some default values (a bit of a hack)
        @cell_sizes   = $basedata_ref->get_cell_sizes;
        @cell_origins = $basedata_ref->get_cell_origins;

        foreach my $thisp (@$table_params) {
            $thisp->set_default( $cell_origins[0] )
              if ( $thisp->get_name eq 'raster_origin_e' );
            $thisp->set_default( $cell_origins[1] )
              if ( $thisp->get_name eq 'raster_origin_n' );
            $thisp->set_default( $cell_sizes[0] )
              if ( $thisp->get_name eq 'raster_cellsize_e' );
            $thisp->set_default( $cell_sizes[1] )
              if ( $thisp->get_name eq 'raster_cellsize_n' );
        }
    }

    # Build widgets for parameters
    my $table = $dlgxml->get_object('tableImportParameters');

    # (passing $dlgxml because generateFile uses existing widget on the dialog)
    my $parameters_table = Biodiverse::GUI::ParametersTable->new;
    my $extractors = $parameters_table->fill( $table_params, $table, $dlgxml );

    $dlg->show_all;
    $response = $dlg->run;
    $dlg->destroy;

    if ( $response ne 'ok' ) {

        #  clean up and drop out
        cleanup_new_basedatas( \%multiple_brefs, \%multiple_is_new, $gui )
          if $use_new || $one_basedata_per_file;
        return;
    }
    my $import_params = $parameters_table->extract($extractors);
    %import_params = @$import_params;

# next stage, if we are reading as raster, just call import function here and exit.
# for shapefile and text, find columns and ask how to interpret
    my $col_names_for_dialog;
    my $col_options = undef;
    my $use_matrix;

    # (no pre-processing needed for raster)

    if ( $read_format eq 'raster' ) {

        # just set cell sizes etc values from dialog
        @cell_origins =
          ( $import_params{raster_origin_e}, $import_params{raster_origin_n} );
        @cell_sizes = (
            $import_params{raster_cellsize_e},
            $import_params{raster_cellsize_n}
        );
    }
    elsif ( $read_format eq 'shapefile' ) {

        # process as shapefile

        # find available columns from first file, assume all the same
        croak 'no files given' if !scalar @filenames;

        my $fnamebase = $filenames[0];
        $fnamebase =~ s/\.[^.]+?$//
          ; #  use lazy quantifier so we get chars from the last dot - should use Path::Class::File

        my $shapefile = Geo::ShapeFile->new($fnamebase);

        my $shape_type = $shapefile->type( $shapefile->shape_type );
        croak '[BASEDATA] Import of non-point shapefiles is not supported.  '
          . "$fnamebase is type $shape_type\n"
          if not $shape_type =~ /Point/;

        my @field_names = qw {:shape_x :shape_y};    # we always have x,y data
        if ( defined $shapefile->z_min() ) {
            push( @field_names, ':shape_z' );
        }
        if ( defined $shapefile->m_min() ) {
            push( @field_names, ':shape_m' );
        }

#  need to get the remaining columns from the dbf - read first record to get colnames from hash keys
#  these will then be fed into make_columns_dialog
        my $fld_names = $shapefile->get_dbf_field_names // [];
        push @field_names, @$fld_names;

        $col_names_for_dialog = \@field_names;
    }
    elsif ( $read_format eq 'text' || $read_format eq 'spreadsheet' ) {

        # process as tabular input, get columns from file

        # Get header columns
        say "[GUI] Discovering columns from $filenames[0]";
        my $filename_utf8 = Glib::filename_display_name $filenames[0];
        my ( @line2_cols, @header );

        if ( $read_format eq 'text' ) {

            my $fh;

# have unicode filename issues - see https://github.com/shawnlaffan/biodiverse/issues/272
            if ( not open $fh, '<:via(File::BOM)', $filename_utf8 ) {
                my $exists = -e $filename_utf8 || 0;
                my $msg = "Unable to open $filenames[0].\n";
                $msg .=
                  $exists
                  ? "Check file read permissions."
                  : "If the file name contains unicode characters then please rename the file so its name does not contain them.\n"
                  . "See https://github.com/shawnlaffan/biodiverse/issues/272";
                $msg .= "\n";
                croak $msg;
            }

            my $csv_obj = $gui->get_project->get_csv_object_using_guesswork(
                fname => $filename_utf8, );

     #  Sometimes we have \r as a separator which messes up the csv2list calls
     #  We should really just use csv->get_line directly, but csv2list has other
     #  error handling code
            local $/ = $csv_obj->eol;

            my $line = <$fh>;
            @header = $gui->get_project->csv2list(
                string     => $line,
                csv_object => $csv_obj,
            );

            #  R data frames are saved missing the first field in the header
            my $is_r_data_frame = check_if_r_data_frame(
                file       => $filenames[0],
                csv_object => $csv_obj,
            );

            #  add a field to the header if needed
            if ($is_r_data_frame) {
                unshift @header, ':R_data_frame_col_0:';
            }

            # check data, if additional lines in data, append in column list.
            if ( !$fh->eof ) {    #  handle files with headers only
                my $line2 = <$fh>;
                @line2_cols = $gui->get_project->csv2list(
                    string     => $line2,
                    csv_object => $csv_obj,
                );
            }

            close $fh;
        }
        else {                    #  we have a spreadsheet
            my $book = Spreadsheet::Read::ReadData($filename_utf8);
            croak "Unable to read spreadsheet $filename_utf8\n"
              if !$book;

            #  need to sort the sheets by file order
            my $sheets = $book->[0]{sheet};
            my @sheet_names =
              sort { $sheets->{$a} <=> $sheets->{$b} } keys %$sheets;

            #  need to find which one they want
            my $sheet_id = 1;

            my $param = bless {
                type    => 'choice',
                choices => \@sheet_names,
                default => 0,
                name    => 'sheet_id',
            }, $parameter_metadata_class;

            #  get the sheet ID - need to refactor this code
            my $s_dlgxml = Gtk2::Builder->new();
            $s_dlgxml->add_from_file(
                $gui->get_gtk_ui_file('dlgImportParameters.ui') );
            $dlg = $s_dlgxml->get_object('dlgImportParameters');
            my $table = $s_dlgxml->get_object('tableImportParameters');

     # (passing $dlgxml because generateFile uses existing widget on the dialog)
            my $parameters_table = Biodiverse::GUI::ParametersTable->new;
            my $extractors =
              $parameters_table->fill( [$param], $table, $s_dlgxml );

            $dlg->show_all;
            $response = $dlg->run;
            $dlg->destroy;

            return if $response ne 'ok';

            my $chosen_params = $parameters_table->extract($extractors);
            my %chosen_params = @$chosen_params;
            $sheet_id = $sheets->{ $chosen_params{'sheet_id'} };

            my @rows = Spreadsheet::Read::rows( $book->[$sheet_id] );

            @header     = @{ $rows[0] };
            @line2_cols = @{ $rows[1] };

            #  avoid the need to re-read the file,
            #  as import_data_spreadsheet can handle books as file args
            $filenames[0] = $book;
        }

        # Check for empty fields in header.
        # CSV files from excel can have dangling headers
        #  should use a map for this?
        my $col_num = 0;
        while ( $col_num <= $#header ) {
            if ( !defined $header[$col_num] || !length $header[$col_num] ) {
                $header[$col_num] = "col_$col_num";
            }
            $col_num++;
        }
        while ( $col_num <= $#line2_cols ) {
            $header[$col_num] = "col_$col_num";
            $col_num++;
        }

        $use_matrix           = $import_params{data_in_matrix_form};
        $col_names_for_dialog = \@header;
        $col_options          = undef;

        if ($use_matrix) {
            $col_options = [
                qw /
                  Ignore
                  Group
                  Text_group
                  Label_start_col
                  Label_end_col
                  Include_columns
                  Exclude_columns
                  /
            ];
        }
    }

    #########
    # 2. Get column types (using first file...)
    #########
    my $column_settings;
    if ( my $xx = grep { $_ eq $read_format } @format_uses_columns ) {
        my $row_widgets;
        ( $dlg, $row_widgets ) = make_columns_dialog(
            header            => $col_names_for_dialog,
            wnd_main          => $gui->get_object('wndMain'),
            row_options       => $col_options,
            file_list_text    => $file_list_as_text,
            max_opt_rows      => $import_params{max_opt_cols},
            gp_axis_precision => $import_params{gp_axis_precision},
        );

      GET_COLUMN_TYPES:
        while (1) {  # Keep showing dialog until have at least one label & group
            $response = $dlg->run();

            last GET_COLUMN_TYPES
              if $response ne 'help' && $response ne 'ok';

            if ( $response eq 'help' ) {

                #  do stuff
                #print "hjelp me!\n";
                explain_import_col_options( $dlg, $use_matrix );
            }
            elsif ( $response eq 'ok' ) {
                $column_settings =
                  get_column_settings( $row_widgets, $col_names_for_dialog );
                my $num_groups = scalar @{ $column_settings->{groups} };
                my $num_labels = 0;
                if ($use_matrix) {
                    if ( exists $column_settings->{Label_start_col} )
                    {    #  not always present
                        $num_labels =
                          scalar @{ $column_settings->{Label_start_col} };  #>=1
                            #$num_labels = 1;  #  just binary flag it
                    }
                }
                else {
                    $num_labels = scalar @{ $column_settings->{labels} };
                }

                last GET_COLUMN_TYPES if $num_groups && $num_labels;

                my $text =
                  $use_matrix
                  ? 'Please select at least one group and the label start column'
                  : 'Please select at least one label and one group column';

                my $msg =
                  Gtk2::MessageDialog->new( undef, 'modal', 'error', 'ok',
                    $text );

                $msg->run();
                $msg->destroy();
                $column_settings = undef;
            }
        }
        $dlg->destroy();

        if ( not $column_settings ) {    #  clean up and drop out
            cleanup_new_basedatas( \%multiple_brefs, \%multiple_is_new, $gui )
              if ( $use_new || $one_basedata_per_file );
            return;
        }
    }

    #########
    # 3. Get column order
    #########
    my $reorder_params;
    if ( my $xx = grep { $_ eq $read_format } @format_uses_columns ) {
        my $old_labels_array = $column_settings->{labels};
        if ($use_matrix) {
            $column_settings->{labels} =
              [ { name => 'From file', id => 0 } ];
        }

        ( $dlgxml, $dlg ) = make_reorder_dialog( $gui, $column_settings );
        $response = $dlg->run();

        $reorder_params = fill_params($dlgxml);
        $dlg->destroy();

        if ( $response ne 'ok' ) {    #  clean up and drop out
            cleanup_new_basedatas( \%multiple_brefs, \%multiple_is_new, $gui )
              if $use_new || $one_basedata_per_file;
            return;
        }

        if ($use_matrix) {
            $column_settings->{labels} = $old_labels_array;
        }

        @cell_sizes   = @{ $reorder_params->{CELL_SIZES} };
        @cell_origins = @{ $reorder_params->{CELL_ORIGINS} };
    }

    #########
    # 4. Load the data
    #########
    # Set the cellsize and origins parameters if we are new
    if ( $use_new || $one_basedata_per_file ) {
        foreach my $file ( keys %multiple_brefs ) {
            next if !$multiple_is_new{$file};

            $multiple_brefs{$file}->set_param( CELL_SIZES => [@cell_sizes] );
            $multiple_brefs{$file}
              ->set_param( CELL_ORIGINS => [@cell_origins] );
        }
    }

    #  get the sample count columns.  could do in fill_params, but these are
    #    not reordered while fill_params deals with the re-ordering.
    my @sample_count_columns;
    foreach my $index ( @{ $column_settings->{sample_counts} } ) {
        push @sample_count_columns, $index->{id};
    }

    my @include_columns;
    foreach my $index ( @{ $column_settings->{include_columns} } ) {
        push @include_columns, $index->{id};
    }

    my @exclude_columns;
    foreach my $index ( @{ $column_settings->{exclude_columns} } ) {
        push @exclude_columns, $index->{id};
    }

    my %rest_of_options;
    my %checked_already;
    my @tmp = qw/sample_counts exclude_columns include_columns groups labels/;
    @checked_already{@tmp} = (1) x scalar @tmp;    #  clunky

  COLUMN_SETTING:
    foreach my $key ( keys %$column_settings ) {
        next COLUMN_SETTING if exists $checked_already{$key};

        my $array_ref = [];
        foreach my $index ( @{ $column_settings->{$key} } ) {
            push @$array_ref, $index->{id};
        }
        $key = lc $key;
        $rest_of_options{$key} = $array_ref;
    }

    #  get the various columns
    my %gp_lb_cols;
    foreach my $key ( keys %$reorder_params ) {
        next if $key =~ /^CELL_(?:SIZE|ORIGINS)/;
        my $value = $reorder_params->{$key};
        $gp_lb_cols{ lc $key } = $value;
    }

    my $success = 1;

    # run appropriate import routine
    if ( $read_format eq 'raster' ) {
        my $labels_as_bands = $import_params{labels_as_bands};
        foreach my $bdata ( keys %multiple_file_lists ) {
            $success &&= eval {
                $multiple_brefs{$bdata}->import_data_raster(
                    %import_params,

                    #%rest_of_options,
                    #%gp_lb_cols,
                    labels_as_bands => $labels_as_bands,
                    input_files     => $multiple_file_lists{$bdata}
                );
            };
        }
    }
    elsif ( $read_format eq 'shapefile' or $read_format eq 'spreadsheet' ) {

        #  shapefiles and spreadsheets import based on names, so extract them
        my ( @group_col_names, @label_col_names );

        #  these should stay undef if not used
        my ( $is_lat_field, $is_lon_field );

        my $lb_col_order = $gp_lb_cols{label_columns};
        my $lb_specs     = $column_settings->{labels};
        foreach my $col (@$lb_col_order) {
            my $idx = first_index { $col eq $_->{id} } @$lb_specs;
            croak "aaaaaaargghhhhh this should not happen\n" if $idx < 0;
            push @label_col_names, $lb_specs->[$idx]{name};
        }

        my $gp_col_order = $gp_lb_cols{group_columns};
        my $gp_specs     = $column_settings->{groups};
        my $i            = -1;
        foreach my $col (@$gp_col_order) {
            $i++;
            my $idx = first_index { $col eq $_->{id} } @$gp_specs;
            croak "aaaaaaargghhhhh this should not happen\n" if $idx < 0;
            my $name = $gp_specs->[$idx]{name};
            push @group_col_names, $name;
            if ( $gp_lb_cols{cell_is_lat}[$i] ) {
                $is_lat_field //= {};
                $is_lat_field->{$name} = 1;
            }
            elsif ( $gp_lb_cols{cell_is_lon}[$i] ) {
                $is_lon_field //= {};
                $is_lon_field->{$name} = 1;
            }
        }

        my @sample_count_col_names;
        foreach my $specs ( @{ $column_settings->{sample_counts} } ) {
            push @sample_count_col_names, $specs->{name};
        }

        my $import_method = "import_data_$read_format";

        # process data
        foreach my $bdata ( keys %multiple_file_lists ) {
            $success &= eval {
                $multiple_brefs{$bdata}->$import_method(
                    %import_params,
                    %rest_of_options,
                    input_files            => $multiple_file_lists{$bdata},
                    group_fields           => \@group_col_names,
                    label_fields           => \@label_col_names,
                    sample_count_col_names => \@sample_count_col_names,
                    is_lat_field           => $is_lat_field,
                    is_lon_field           => $is_lon_field,
                );
            };
        }
    }
    elsif ( $read_format eq 'text' ) {
        foreach my $bdata ( keys %multiple_file_lists ) {
            $success &&= eval {
                $multiple_brefs{$bdata}->load_data(
                    %import_params,
                    %rest_of_options,
                    %gp_lb_cols,
                    input_files          => $multiple_file_lists{$bdata},
                    include_columns      => \@include_columns,
                    exclude_columns      => \@exclude_columns,
                    sample_count_columns => \@sample_count_columns,
                );
            };
        }
    }

    if ($EVAL_ERROR) {
        my $text = $EVAL_ERROR;
        if ( not $use_new ) {
            $text .=
              "\tWarning: Records prior to this line have been imported.\n";
        }
        $gui->report_error($text);
    }

    if ($success) {
        if (   $use_new
            && !$one_basedata_per_file
            && !$basedata_ref->get_label_count
            && !$basedata_ref->get_group_count )
        {
            #  we are empty!
            my $message = "No valid records were imported into this basedata.\n"
              . 'do you want to add it to the project anyway?';
            my $response =
              Biodiverse::GUI::YesNoCancel->run( { header => $message } );
            return if $response ne 'yes';
        }

        if ( $use_new || $one_basedata_per_file ) {

            #  warn if they are all empty
            my $sum = 0;
            foreach my $bd ( values %multiple_brefs ) {
                $sum += $bd->get_group_count + $bd->get_label_count;
                last if $sum;
            }
            if ( !$sum ) {
                my $message =
                    "No valid records were imported into any basedata.\n"
                  . 'do you want to add them to the project anyway?';
                my $response =
                  Biodiverse::GUI::YesNoCancel->run( { header => $message } );
                return if $response ne 'yes';
            }

            # ask if they want to auto remap


            # run the remap gui, get all their decisions in one go
            my $remapper           = Biodiverse::GUI::RemapGUI->new();
            my $remap_dlg_results  = $remapper->run_remap_gui(gui => $gui);

            # will be 'auto' 'manual' or 'none'
            my $remap_type = $remap_dlg_results->{remap_type};



            if ( $remap_type eq 'auto' ) {
                my $remapper = Biodiverse::GUI::RemapGUI->new();
                foreach my $file ( keys %multiple_brefs ) {
                    $remap_dlg_results->{gui} = $gui;
                    $remap_dlg_results->{old_source} = $remap_dlg_results->{datasource_choice};
                    $remap_dlg_results->{new_source} = $multiple_brefs{$file};
                    
                    $remapper->perform_remap($remap_dlg_results);
                }
            }
            elsif ( $remap_type eq 'manual' ) {
                say "[BasedataImport] Manual remapping at import time not yet implemented.";
            }

            foreach my $file ( keys %multiple_brefs ) {
                next if !$multiple_is_new{$file};
                $gui->get_project->add_base_data( $multiple_brefs{$file} );
            }
        }
        return $basedata_ref;
    }

    return;
}

sub cleanup_new_basedatas {
    my ( $brefs, $bdata_is_new, $gui ) = @_;

    #  clean up and drop out
    # note we have to check for new basedatas if one_basedata_per_file set
    # and use_new not set, as a new one is created if not found
    foreach my $file ( keys %$brefs ) {

        # check if newly created
        next if !$bdata_is_new->{$file};
        $gui->get_project->delete_base_data( $brefs->{$file} );
    }
    return;
}

sub check_if_r_data_frame {
    my %args = @_;

    my $package = 'Biodiverse::Common';
    my $csv = $args{csv_object} // $package->get_csv_object(@_);

    my $fh;
    open( $fh, '<:via(File::BOM)', $args{file} )
      || croak "Unable to open file $args{file}\n";

    my @lines = $package->get_next_line_set(
        target_line_count => 10,
        file_handle       => $fh,
        csv_object        => $csv,
    );

    $fh->close;

    my $header       = shift @lines;
    my $header_count = scalar @$header;

    my $is_r_style = 0;
    foreach my $line (@lines) {
        if ( scalar @$line == $header_count + 1 ) {
            $is_r_style = 1;
            last;
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
    my $cols    = shift;
    my $headers = shift;

    #my $num = @$cols;
    my ( @labels, @groups, @sample_counts, @exclude_columns, @include_columns );
    my %rest_of_options;

    foreach my $i ( 0 .. $#$cols ) {
        my $widgets = $cols->[$i];

        # widgets[0] - combo
        # widgets[1] - cell size
        # widgets[2] - cell origin

        my $type = $widgets->[0]->get_active_text;

        next if $type eq 'Ignore';
        if ( $type eq 'Label' ) {
            my $hash_ref = {
                name => $headers->[$i],
                id   => $i
            };
            push( @labels, $hash_ref );
        }
        elsif ( $type eq 'Text_group' ) {
            my $hash_ref = {
                name        => $headers->[$i],
                id          => $i,
                cell_size   => -1,
                cell_origin => 0,
            };
            push( @groups, $hash_ref );
        }
        elsif ( $type eq 'Group' ) {
            my $hash_ref = {
                name        => $headers->[$i],
                id          => $i,
                cell_size   => $widgets->[1]->get_value(),
                cell_origin => $widgets->[2]->get_value(),
            };
            my $dms = $widgets->[3]->get_active_text();
            if ( $dms eq 'is_lat' ) {
                $hash_ref->{is_lat} = 1;
            }
            elsif ( $dms eq 'is_lon' ) {
                $hash_ref->{is_lon} = 1;
            }
            push( @groups, $hash_ref );
        }
        elsif ( $type eq 'Sample_counts' ) {
            my $hash_ref = {
                name => $headers->[$i],
                id   => $i,
            };
            push @sample_counts, $hash_ref;
        }
        elsif ( $type eq 'Include_columns' ) {
            my $hash_ref = {
                name => $headers->[$i],
                id   => $i,
            };
            push @include_columns, $hash_ref;
        }
        elsif ( $type eq 'Exclude_columns' ) {
            my $hash_ref = {
                name => $headers->[$i],
                id   => $i,
            };
            push @exclude_columns, $hash_ref;
        }
        else {
            # initialise
            if ( not exists $rest_of_options{$type}
                or reftype( $rest_of_options{$type} ) eq 'ARRAY' )
            {
                $rest_of_options{$type} = [];
            }
            my $array_ref = $rest_of_options{$type};

            my $hash_ref = {
                name => $headers->[$i],
                id   => $i,
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

    my $labels_model = $dlgxml->get_object('labels')->get_model();
    my $groups_model = $dlgxml->get_object('groups')->get_model();
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
        my $info = $labels_model->get( $iter, 1 );

        push( @{ $params{'LABEL_COLUMNS'} }, $info->{id} );

        $iter = $labels_model->iter_next($iter);
    }

    # Do groups
    $iter = $groups_model->get_iter_first();
    while ($iter) {
        my $info2 = $groups_model->get( $iter, 1 );

        push( @{ $params{'GROUP_COLUMNS'} }, $info2->{id} );
        push( @{ $params{'CELL_SIZES'} },    $info2->{cell_size} );
        push( @{ $params{'CELL_ORIGINS'} },  $info2->{cell_origin} );
        push( @{ $params{'CELL_IS_LAT'} },   $info2->{is_lat} );
        push( @{ $params{'CELL_IS_LON'} },   $info2->{is_lon} );

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
        Ignore => 'There is no setting for this column.  '
          . 'It will be ignored or used depending on your other settings.',
        Group => 'Use records in this column to define a group axis '
          . '(numerical type).  Values will be aggregated according '
          . 'to your cellsize settings.  Non-numeric values will cause an error.',
        Text_group =>
          'Use records in this column as a group axis (text type).  '
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
            Label_end_col => 'This column is the last of the labels.  '
              . 'Not setting one will use all columns from the '
              . 'Label_start_col to the end.',
        );
    }
    else {
        %explain = (
            %explain,
            Label =>
              'Values in this column will be used as one of the label axes.',
            Sample_counts =>
              'Values in this column represent sample counts (abundances).  '
              . 'If this is not set then each record is assumed to equal one sample.',
        );
    }

    show_expl_dialog( \%explain, $parent );

    return;
}

sub explain_remap_col_options {
    my $parent = shift;

    my $inc_exc_suffix = 'This applies to the main input file, '
      . 'and is assessed before any remapping is done.';

    my %explain = (
        Ignore => 'There is no setting for this column.  '
          . 'It will be ignored or its use will depend on your other settings.',
        Property => 'The value for this field will be added as a property, '
          . 'using the name of the column as the property name.',
        Input_element =>
'Values in this column will be used as one of the element (label or group) axes. '
          . 'Make sure you have as many of these columns set as you have '
          . 'element axes or they will not match and the properties will be ignored.',
        Remapped_element =>
          'The input element (label or group) will be renamed to this. '
          . 'Set as many remapped label axes as you like, '
          . 'but make sure the group axes remain the same',
        Include_columns => 'Only those Input_elements with a value of 1 in '
          . '<i>at least one</i> of the Include_columns will '
          . 'be imported. '
          . $inc_exc_suffix,
        Exclude_columns => 'Those Input_elements with a value of 1 in any '
          . 'Exclude_column will not be imported.  '
          . $inc_exc_suffix,
    );

    show_expl_dialog( \%explain, $parent );

    return;
}

sub show_expl_dialog {
    my $expl_hash = shift;
    my $parent    = shift;

    my $dlg = Gtk2::Dialog->new( 'Column options',
        $parent, 'destroy-with-parent', 'gtk-ok' => 'ok', );

    my $text_wrapper = Text::Wrapper->new( columns => 90 );

    my $table = Gtk2::Table->new( 1 + scalar keys %$expl_hash, 2 );
    $table->set_row_spacings(5);
    $table->set_col_spacings(5);

    # Make scroll window for table
    #my $scroll = Gtk2::ScrolledWindow->new;
    #$scroll->add_with_viewport($table);
    #$scroll->set_policy('never', 'automatic');
    #$dlg->vbox->pack_start($scroll, 1, 1, 5);

    $dlg->vbox->pack_start( $table, 1, 1, 5 );

    my $col = 0;

    # Make header column
    my $label1 = Gtk2::Label->new('<b>Column option</b>');
    $label1->set_alignment( 0, 1 );
    $label1->set_use_markup(1);
    $table->attach( $label1, 0, 1, $col, $col + 1, [ 'expand', 'fill' ],
        'shrink', 0, 0 );
    my $label2 = Gtk2::Label->new('<b>Explanation</b>');
    $label2->set_alignment( 0, 1 );
    $label2->set_use_markup(1);
    $table->attach( $label2, 1, 2, $col, $col + 1, [ 'expand', 'fill' ],
        'shrink', 0, 0 );

    my $text;

    #while (my ($label, $expl) = each %explain) {
    foreach my $label ( sort keys %$expl_hash ) {
        $col++;
        my $label_widget = Gtk2::Label->new("<b>$label</b>");
        $table->attach( $label_widget, 0, 1, $col, $col + 1,
            [ 'expand', 'fill' ],
            'shrink', 0, 0 );

        my $expl = $expl_hash->{$label};

        #$expl = $text_wrapper->wrap($expl);
        my $expl_widget = Gtk2::Label->new($expl);
        $table->attach( $expl_widget, 1, 2, $col, $col + 1,
            [ 'expand', 'fill' ],
            'shrink', 0, 0 );

        foreach my $widget ( $expl_widget, $label_widget ) {
            $widget->set_alignment( 0, 0 );
            $widget->set_use_markup(1);
            $widget->set_selectable(1);
        }
    }

    $dlg->set_modal(undef);

    #$dlg->set_focus(undef);
    $dlg->show_all;

    $dlg->run;
    $dlg->destroy;

    return;
}

##################################################
# Column reorder dialog
##################################################

sub make_reorder_dialog {
    my $gui     = shift;
    my $columns = shift;

    my $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file( $gui->get_gtk_ui_file('dlgReorderColumns.ui') );
    my $dlg = $dlgxml->get_object('dlgReorderColumns');
    $dlg->set_transient_for( $gui->get_object('wndMain') );

    my $list_groups =
      setup_reorder_list( 'groups', $dlgxml, $columns->{groups} );
    my $list_labels =
      setup_reorder_list( 'labels', $dlgxml, $columns->{labels} );

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
    $dlgxml->get_object('btnUp')->signal_connect(
        clicked => \&on_up_down,
        [ 'up', $list_groups, $list_labels ],
    );
    $dlgxml->get_object('btnDown')->signal_connect(
        clicked => \&on_up_down,
        [ 'down', $list_groups, $list_labels ],
    );

    return ( $dlgxml, $dlg );
}

sub setup_reorder_list {
    my $type    = shift;
    my $dlgxml  = shift;
    my $columns = shift;

    # Create the model
    my $model = Gtk2::ListStore->new( 'Glib::String', 'Glib::Scalar' );

    foreach my $column ( @{$columns} ) {
        my $iter = $model->append();
        $model->set( $iter, 0, $column->{name} );
        $model->set( $iter, 1, $column );
    }

    # Initialise the list
    my $list = $dlgxml->get_object($type);

    my $col_name      = Gtk2::TreeViewColumn->new();
    my $name_renderer = Gtk2::CellRendererText->new();
    $col_name->set_sizing('fixed');
    $col_name->pack_start( $name_renderer, 1 );
    $col_name->add_attribute( $name_renderer, text => 0 );

    $list->insert_column( $col_name, -1 );
    $list->set_headers_visible(0);
    $list->set_reorderable(1);
    $list->set_model($model);

    return $list;
}

# If selected something, clear the other lists' selection
sub unselect_other {
    my $selection  = shift;
    my $other_list = shift;

    if ( $selection->count_selected_rows() > 0 ) {
        $other_list->get_selection->unselect_all();
    }

    return;
}

sub on_up_down {
    shift;
    my $args = shift;
    my ( $btn, $list1, $list2 ) = @$args;

    # Get selected iter
    my ( $model, $iter );

    ( $model, $iter ) = $list1->get_selection->get_selected();
    if ( not $iter ) {

        # try other list
        ( $model, $iter ) = $list2->get_selection->get_selected();
        return if not $iter;
    }

    if ( $btn eq 'up' ) {
        my $path = $model->get_path($iter);
        if ( $path->prev() ) {

            my $iter_prev = $model->get_iter($path);
            $model->move_before( $iter, $iter_prev );

        }

        else {
            # If at the top already, move to bottom
            $model->move_before( $iter, undef );

        }
    }
    elsif ( $btn eq 'down' ) {
        $model->move_after( $iter, $model->iter_next($iter) );
    }

    return;
}

##################################################
# First (choose filename) dialog
##################################################

sub make_filename_dialog {
    my $gui = shift;

    my $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file( $gui->get_gtk_ui_file('dlgImport1.ui') );
    my $dlg = $dlgxml->get_object($import_dlg_name);
    my $x   = $gui->get_object('wndMain');
    $dlg->set_transient_for($x);

    # Initialise the basedatas combo
    $dlgxml->get_object($combo_import_basedatas)
      ->set_model( $gui->get_project->get_basedata_model() );
    my $selected = $gui->get_project->get_selected_base_data_iter();
    if ( defined $selected ) {
        $dlgxml->get_object($combo_import_basedatas)
          ->set_active_iter($selected);
    }

    # If there are no basedatas, force "New" checkbox on
    if ( not $selected ) {
        $dlgxml->get_object($chk_new)->set_sensitive(0);
        $dlgxml->get_object($btn_next)->set_sensitive(0);
    }

    # Default to new
    $dlgxml->get_object($chk_new)->set_active(1);
    $dlgxml->get_object($combo_import_basedatas)->set_sensitive(0);

    # Init the file chooser
    my $filechooser = $dlgxml->get_object($filechooser_input);

    use Cwd;
    $filechooser->set_current_folder_uri( getcwd() );

    # define file selection filters (stored in txtcsv_filter etc)
    $txtcsv_filter = Gtk2::FileFilter->new();
    $txtcsv_filter->add_pattern('*.csv');
    $txtcsv_filter->add_pattern('*.txt');
    $txtcsv_filter->set_name('txt and csv files');
    $filechooser->add_filter($txtcsv_filter);

    $allfiles_filter = Gtk2::FileFilter->new();
    $allfiles_filter->add_pattern('*');
    $allfiles_filter->set_name('all files');
    $filechooser->add_filter($allfiles_filter);

    $shapefiles_filter = Gtk2::FileFilter->new();
    $shapefiles_filter->add_pattern('*.shp');
    $shapefiles_filter->set_name('shapefiles');
    $filechooser->add_filter($shapefiles_filter);

    $spreadsheets_filter = Gtk2::FileFilter->new();
    $spreadsheets_filter->add_pattern('*.xlsx');
    $spreadsheets_filter->add_pattern('*.xls');
    $spreadsheets_filter->add_pattern('*.ods');
    $spreadsheets_filter->set_name('spreadsheets');
    $filechooser->add_filter($spreadsheets_filter);

    $filechooser->set_select_multiple(1);
    $filechooser->signal_connect(
        'selection-changed' => \&on_file_changed,
        $dlgxml
    );

    $dlgxml->get_object($chk_new)
      ->signal_connect( toggled => \&on_new_toggled, [ $gui, $dlgxml ] );
    $dlgxml->get_object($txt_import_new)
      ->signal_connect( changed => \&on_new_changed, [ $gui, $dlgxml ] );

    $dlgxml->get_object($chk_import_one_bd_per_file)->signal_connect(
        toggled => \&on_separate_toggled,
        [ $gui, $dlgxml ],
    );

    $dlgxml->get_object($file_format)->set_active(0);
    $dlgxml->get_object($importmethod_combo)->signal_connect(
        changed => \&on_import_method_changed,
        [ $gui, $dlgxml ],
    );

    return ( $dlgxml, $dlg );
}

sub on_import_method_changed {

    # change file filter used
    my $format_combo = shift;
    my $args         = shift;
    my ( $gui, $dlgxml ) = @$args;

    my $active_choice = lc $format_combo->get_active_text;
    my $f_widget      = $dlgxml->get_object($filechooser_input);

    # find which is selected
    if ( $active_choice eq 'text' ) {
        $f_widget->set_filter($txtcsv_filter);
    }
    elsif ( $active_choice eq 'raster' ) {
        $f_widget->set_filter($allfiles_filter);
    }
    elsif ( $active_choice eq 'shapefile' ) {
        $f_widget->set_filter($shapefiles_filter);
    }
    elsif ( $active_choice eq 'spreadsheet' ) {
        $f_widget->set_filter($spreadsheets_filter);
    }

    return;
}

sub on_file_changed {
    my $chooser = shift;
    my $dlgxml  = shift;

    my $text      = $dlgxml->get_object("txtImportNew$import_n");
    my @filenames = $chooser->get_filenames();

    # Default name to selected filename
    if ( scalar @filenames > 0 ) {
        my $filename = $filenames[0];

        #print $filename . "\n";
        #my $filename_in_local_encoding = Glib::filename_from_unicode $filename;
        #my $z = -f $filename_in_local_encoding;
        if ( $filename =~ /\.[^.]*/ ) {
            my ( $name, $dir, $suffix ) = fileparse( $filename, qr/\.[^.]*/ );
            $text->set_text($name);
        }
    }

    return;
}

sub on_new_changed {
    my $text = shift;
    my $args = shift;
    my ( $gui, $dlgxml ) = @{$args};

    my $name = $text->get_text();
    if ( $name ne "" ) {

        $dlgxml->get_object($btn_next)->set_sensitive(1);
    }
    else {

        # Disable Next if have no basedatas
        my $selected = $gui->get_project->get_selected_base_data_iter();
        if ( not $selected ) {
            $dlgxml->get_object($btn_next)->set_sensitive(0);
        }
    }

    return;
}

sub on_new_toggled {
    my $checkbox = shift;
    my $args     = shift;
    my ( $gui, $dlgxml ) = @$args;

# if we are doing multiple files as separate, keep basedata selection and new filename
# fields as disabled
    if ( $dlgxml->get_object($chk_import_one_bd_per_file)->get_active ) {
        $dlgxml->get_object($txt_import_new)->set_sensitive(0);
        $dlgxml->get_object($combo_import_basedatas)->set_sensitive(0);
    }
    else {
        #  if true then new, else must select existing
        my $sens_val = $checkbox->get_active;
        $dlgxml->get_object($txt_import_new)->set_sensitive($sens_val);
        $dlgxml->get_object($combo_import_basedatas)
          ->set_sensitive( !$sens_val );
    }

    return;
}

sub on_separate_toggled {
    my $checkbox = shift;
    my $args     = shift;
    my ( $gui, $dlgxml ) = @$args;

    if ( $checkbox->get_active ) {

        # separate chosen
        $dlgxml->get_object($txt_import_new)->set_sensitive(0);
        $dlgxml->get_object($combo_import_basedatas)->set_sensitive(0);
    }
    else {
# de-selected use of separate.  set sensitivity of import_new and import_basedata
# according to selection of new
        my $sens_val = $dlgxml->get_object($chk_new)->get_active;
        $dlgxml->get_object($txt_import_new)->set_sensitive($sens_val);
        $dlgxml->get_object($combo_import_basedatas)
          ->set_sensitive( !$sens_val );
    }

    return;
}

##################################################
# Column selection dialog
##################################################

# We have to dynamically generate the choose columns dialog since
# the number of columns is unknown
sub make_columns_dialog {
    my %args         = @_;
    my $header       = $args{header};               # ref to column header array
    my $wnd_main     = $args{wnd_main};
    my $row_options  = $args{row_options};
    my $file_list    = $args{file_list_text};
    my $max_opt_rows = $args{max_opt_rows} || 100;
    my $gp_axis_prec = $args{gp_axis_precision};

    #  don't try to generate ludicrous number of rows...
    my $num_columns = min( scalar @$header, $max_opt_rows );
    my $quant = $num_columns == scalar @$header ? q{} : 'first';
    say "[GUI] Generating make columns dialog for $quant $num_columns columns";

    # Make dialog
    my $dlg = Gtk2::Dialog->new(
        'Choose columns',
        $wnd_main,
        'modal',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
        'gtk-help'   => 'help',
    );

    if ( defined $file_list ) {
        my $file_title = Gtk2::Label->new('<b>Files:</b>');
        $file_title->set_use_markup(1);
        $file_title->set_alignment( 0, 1 );
        $dlg->vbox->pack_start( $file_title, 0, 0, 0 );

        my $file_list_label = Gtk2::Label->new( $file_list . "\n\n" );
        $file_list_label->set_alignment( 0, 1 );
        $dlg->vbox->pack_start( $file_list_label, 0, 0, 0 );
    }

    my $label = Gtk2::Label->new('<b>Set column options</b>');
    $label->set_use_markup(1);
    $dlg->vbox->pack_start( $label, 0, 0, 0 );

    # Make table
    my $table = Gtk2::Table->new( $num_columns + 1, 8 );
    $table->set_row_spacings(5);
    $table->set_col_spacings(20);

    # Make scroll window for table
    my $scroll = Gtk2::ScrolledWindow->new;
    $scroll->add_with_viewport($table);
    $scroll->set_policy( 'never', 'automatic' );
    $dlg->vbox->pack_start( $scroll, 1, 1, 5 );

    my $col = 0;

    # Make header column
    $label = Gtk2::Label->new('<b>#</b>');
    $label->set_alignment( 0.5, 1 );
    $label->set_use_markup(1);
    $table->attach( $label, $col, $col + 1, 0, 1, [ 'expand', 'fill' ],
        'shrink', 0, 0 );

    $col++;
    $label = Gtk2::Label->new('<b>Column</b>');
    $label->set_alignment( 0, 1 );
    $label->set_use_markup(1);
    $table->attach( $label, $col, $col + 1, 0, 1, [ 'expand', 'fill' ],
        'shrink', 0, 0 );

    $col++;
    $label = Gtk2::Label->new('Type');
    $label->set_alignment( 0.5, 1 );
    $label->set_has_tooltip(1);
    $label->set_tooltip_text('Click on the help to see the column meanings');
    $table->attach( $label, $col, $col + 1, 0, 1, [ 'expand', 'fill' ],
        'shrink', 0, 0 );

    $col++;
    $label = Gtk2::Label->new('Cell size');
    $label->set_alignment( 0.5, 1 );
    $label->set_has_tooltip(1);
    $label->set_tooltip_text('Width of the group along this axis');
    $table->attach( $label, $col, $col + 1, 0, 1, [ 'expand', 'fill' ],
        'shrink', 50, 0 );

    $col++;
    $label = Gtk2::Label->new('Cell origin');
    $label->set_alignment( 0.5, 1 );
    $label->set_has_tooltip(1);
    $label->set_tooltip_text(
        'Origin of this axis.\nGroup corners will be offset by this amount.');
    $table->attach( $label, $col, $col + 1, 0, 1, [ 'expand', 'fill' ],
        'shrink', 50, 0 );

    $col++;
    $label = Gtk2::Label->new("Data in\ndegrees?");
    $label->set_alignment( 0.5, 1 );
    $label->set_has_tooltip(1);
    $label->set_tooltip_text(
        'Are the group data for this axis in degrees latitude or longitude?');
    $table->attach( $label, $col, $col + 1, 0, 1, [ 'expand', 'fill' ],
        'shrink', 0, 0 );

    # Add columns
    # use row_widgets to store the radio buttons, spinboxes
    my $row_widgets = [];
    foreach my $i ( 0 .. ( $num_columns - 1 ) ) {
        my $row_label_text = $header->[$i] // q{};
        add_row( $row_widgets, $table, $i, $row_label_text, $row_options,
            $gp_axis_prec );

        #last if $i >= $max_opt_rows;
    }

    $dlg->set_resizable(1);
    $dlg->set_default_size( 0, 400 );
    $dlg->show_all();

    # Hide the cell size textboxes since all columns are "Ignored" by default
    foreach my $row (@$row_widgets) {
        $row->[1]->hide;
        $row->[2]->hide;
        $row->[3]->hide;
    }

    return ( $dlg, $row_widgets );
}

sub add_row {
    my ( $row_widgets, $table, $col_id, $header, $row_options, $gp_axis_prec )
      = @_;

    $header //= q{};

    if ( ( ref $row_options ) !~ /ARRAY/ or scalar @$row_options == 0 ) {
        $row_options = [
            qw /
              Ignore
              Label
              Group
              Text_group
              Sample_counts
              Include_columns
              Exclude_columns
              /
        ];
    }

    #  column number
    my $i_label = Gtk2::Label->new($col_id);
    $i_label->set_alignment( 0.5, 1 );
    $i_label->set_use_markup(1);

    $header = Glib::Markup::escape_text($header);

    # Column header
    my $label = Gtk2::Label->new("<tt>$header</tt>");
    $label->set_alignment( 0.5, 1 );
    $label->set_use_markup(1);

    # Type combo box
    my $combo = Gtk2::ComboBox->new_text;
    foreach (@$row_options) {
        $combo->append_text($_);
    }
    $combo->set_active(0);

    my $dp = $gp_axis_prec || $ENV{BD_IMPORT_DP} || 7;
    if ( !looks_like_number $dp) {
        $dp = 7;
    }

    # Cell sizes/snaps
    my $adj1 = Gtk2::Adjustment->new( 100000, 0, 10000000, 100, 10000, 0 );
    my $spin1 = Gtk2::SpinButton->new( $adj1, 100, $dp );

    my $adj2 = Gtk2::Adjustment->new( 0, -1000000, 1000000, 100, 10000, 0 );
    my $spin2 = Gtk2::SpinButton->new( $adj2, 100, $dp );

    foreach my $spin ( $spin1, $spin2 ) {
        $spin->hide()
          ;    # By default, columns are "ignored" so cell sizes don't apply
        $spin->set_numeric(1);
    }

    #  degrees minutes seconds
    my $combo_dms = Gtk2::ComboBox->new_text;
    $combo_dms->set_has_tooltip(1);
    $combo_dms->set_tooltip_text($lat_lon_widget_tooltip_text);
    foreach my $choice ( '', 'is_lat', 'is_lon' ) {
        $combo_dms->append_text($choice);
    }
    $combo_dms->set_active(0);

    # Attach to table
    my $i = 0;
    my $c = $col_id;
    foreach my $option ( $i_label, $label, $combo, $spin1, $spin2, $combo_dms )
    {
        $table->attach( $option, $i, $i + 1, $c + 1, $c + 2,
            'shrink', 'shrink', 0, 0, );
        $i++;
    }

    # Signal to enable/disable spin buttons
    $combo->signal_connect_swapped(
        changed => \&on_type_combo_changed,
        [ $spin1, $spin2, $combo_dms ],
    );

    # Store widgets
    $row_widgets->[$col_id] = [ $combo, $spin1, $spin2, $combo_dms ];

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
    my %args             = @_;
    my $gui              = $args{gui};
    my $get_dir_from     = $args{get_dir_from};
    my $type             = $args{type} // "";
    my $other_properties = $args{other_properties} || [];
    my $column_overrides = $args{column_overrides};
    my $filename         = $args{filename};
    my $max_cols_to_show = $args{max_cols_to_show} || 100;
    my $required_cols    = $args{required_cols} // [qw/Input_element/];

    my ( $_file, $data_dir, $_suffixes ) =
      $get_dir_from && length $get_dir_from
      ? fileparse($get_dir_from)
      : ();

    # Get filename for the name-translation file
    $filename //= $gui->show_open_dialog(
        title       => "Select $type properties file",
        suffix      => '*',
        initial_dir => $data_dir,
    );

    return wantarray ? () : {} if !defined $filename;

    my $remap      = Biodiverse::ElementProperties->new;
    my $remap_args = $remap->get_args( sub => 'import_data' );
    my $params     = $remap_args->{parameters};

#  much of the following is used elsewhere to get file options, almost verbatim.  Should move to a sub.
    my $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file( $gui->get_gtk_ui_file('dlgImportParameters.ui') );
    my $dlg = $dlgxml->get_object('dlgImportParameters');
    $dlg->set_title( ucfirst "$type property file options" );

    # Build widgets for parameters
    my $table_name = 'tableImportParameters';
    my $table      = $dlgxml->get_object($table_name);

    # (passing $dlgxml because generateFile uses existing widget on the dialog)
    my $parameters_table = Biodiverse::GUI::ParametersTable->new;
    my $extractors = $parameters_table->fill( $params, $table, $dlgxml );

    $dlg->show_all;
    my $response = $dlg->run;
    $dlg->destroy;

    return wantarray ? () : {} if $response ne 'ok';

    my $properties_params = $parameters_table->extract($extractors);
    my %properties_params = @$properties_params;

    # Get header columns
    say "[GUI] Discovering columns from $filename";

    open( my $input_fh, '<:via(File::BOM)', $filename )
      or croak "Cannot open $filename\n";

    my ( $line, $line_unchomped );
    while (<$input_fh>) {    # get first non-blank line
        $line           = $_;
        $line_unchomped = $line;
        chomp $line;
        last if $line;
    }
    close($input_fh);

    my $csv_obj = $gui->get_project->get_csv_object_using_guesswork(
        fname      => $filename,
        quote_char => $properties_params{input_quote_char},
        sep_char   => $properties_params{input_sep_char},
    );

    my @headers_full = $gui->get_project->csv2list(
        string     => $line_unchomped,
        csv_object => $csv_obj,
    );

    my @headers = map { defined $_ ? $_ : '{null}' }
      @headers_full[ 0 .. min( $#headers_full, $max_cols_to_show - 1 ) ];

    ( $dlg, my $col_widgets ) = make_remap_columns_dialog(
        header           => \@headers,
        wnd_main         => $gui->get_object('wndMain'),
        other_props      => $other_properties,
        column_overrides => $column_overrides,
    );

    my $column_settings = {};
    $dlg->set_title( ucfirst "$type property column types" );

  RUN_DLG:
    while (1) {
        $response = $dlg->run();
        if ( $response eq 'help' ) {
            explain_remap_col_options($dlg);
            next RUN_DLG;
        }
        elsif ( $response eq 'ok' ) {
            $column_settings =
              get_remap_column_settings( $col_widgets, \@headers );
        }
        else {
            $dlg->destroy();
            return wantarray ? () : {};
        }

        #  drop out
        last RUN_DLG if all { $column_settings->{$_} } @$required_cols;

        #  need to check we have the right number...
        my $text =
          'Insufficient columns chosen of types.  Must have at least one of: '
          . join ' ', @$required_cols;
        my $msg =
          Gtk2::MessageDialog->new( undef, 'modal', 'error', 'ok', $text );

        $msg->run();
        $msg->destroy();
    }

    $dlg->destroy();

    #Input_label Remapped_label Range

    my ( @in_cols, @out_cols, @include_cols, @exclude_cols );

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
        file                  => $filename,
        input_element_cols    => \@in_cols,
        remapped_element_cols => \@out_cols,
        input_sep_char        => $remap_args->{input_sep_char}
        ,    #  header might be sufficiently different to matter
        input_quote_char => $remap_args->{input_quote_char},
        include_cols     => \@include_cols,
        exclude_cols     => \@exclude_cols,
    );

    foreach my $type ( @$other_properties, 'Property' ) {
        my $ref = $column_settings->{$type};
        next if !defined $ref;
        $ref = [$ref] if $ref !~ /ARRAY/;
        foreach my $i (@$ref) {
            my $t = $type;
            if ( $t eq 'Property' ) {
                $t = $i->{name};
            }
            $results{ lc($t) } = $i->{id};    #  take the last one selected
        }
    }

    #  just pass them onwards, even if it means guessing again
    $results{input_sep_char}     = $properties_params{input_quote_char},
      $results{input_quote_char} = $properties_params{input_sep_char};

    return wantarray ? %results : \%results;
}

# We have to dynamically generate the choose columns dialog since
# the number of columns is unknown
sub make_remap_columns_dialog {
    my %args             = @_;
    my $header           = $args{header};           # ref to column header array
    my $wnd_main         = $args{wnd_main};
    my $other_props      = $args{other_props} || [];
    my $column_overrides = $args{column_overrides};

    my $num_columns = @$header;
    say "[GUI] Generating make columns dialog for $num_columns columns";

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
    $dlg->vbox->pack_start( $label, 0, 0, 0 );

    # Make table
    my $table = Gtk2::Table->new( $num_columns + 1, 8 );
    $table->set_row_spacings(5);
    $table->set_col_spacings(20);

    # Make scroll window for table
    my $scroll = Gtk2::ScrolledWindow->new;
    $scroll->add_with_viewport($table);
    $scroll->set_policy( 'never', 'automatic' );
    $dlg->vbox->pack_start( $scroll, 1, 1, 5 );

    my $col = 0;

    # Make ID column
    $label = Gtk2::Label->new('<b>#</b>');
    $label->set_alignment( 0.5, 1 );
    $label->set_use_markup(1);
    $table->attach( $label, $col, $col + 1, 0, 1, [ 'expand', 'fill' ],
        'shrink', 0, 0 );

    # Make header column
    $col++;
    $label = Gtk2::Label->new('<b>Column</b>');
    $label->set_alignment( 0.5, 1 );
    $label->set_use_markup(1);
    $table->attach( $label, $col, $col + 1, 0, 1, [ 'expand', 'fill' ],
        'shrink', 0, 0 );

    $col++;
    $label = Gtk2::Label->new('Type');
    $label->set_alignment( 0.5, 1 );
    $table->attach( $label, $col, $col + 1, 0, 1, [ 'expand', 'fill' ],
        'shrink', 0, 0 );

    # Add columns
    # use row_widgets to store the radio buttons, spinboxes
    my $row_widgets = [];
    foreach my $i ( 0 .. ( $num_columns - 1 ) ) {
        add_remap_row( $row_widgets, $table, $i, $header->[$i], $other_props,
            $column_overrides );
    }

    $dlg->set_resizable(1);
    $dlg->set_default_size( 0, 400 );
    $dlg->show_all();

    return ( $dlg, $row_widgets );
}

sub get_remap_column_settings {
    my $cols    = shift;
    my $headers = shift;
    my $num     = @$cols;
    my ( @in, @out );
    my %results;

    foreach my $i ( 0 .. ( $num - 1 ) ) {
        my $widgets = $cols->[$i];

        # widgets[0] - combo

        my $type = $widgets->[0]->get_active_text;

        #  sweep up all those we should not ignore
        if ( $type ne "Ignore" ) {
            $results{$type} = [] if !defined $results{$type};
            my $ref = $results{$type};
            push @{$ref}, { name => $headers->[$i], id => $i };
        }
    }

    return wantarray ? %results : \%results;
}

sub add_remap_row {
    my ( $row_widgets, $table, $col_id, $header, $other_props,
        $column_overrides )
      = @_;

    #  column number
    my $i_label = Gtk2::Label->new($col_id);
    $i_label->set_alignment( 0.5, 1 );
    $i_label->set_use_markup(1);

    # Column header
    my $label = Gtk2::Label->new("<tt>$header</tt>");
    $label->set_use_markup(1);

    # Type combo box
    my $combo = Gtk2::ComboBox->new_text;
    my @options =
        $column_overrides
      ? @$column_overrides
      : (
        qw /Input_element Remapped_element Include Exclude Property/,
        @$other_props
      );
    unshift @options, 'Ignore';

    foreach (@options) {
        $combo->append_text($_);
    }
    $combo->set_active(0);

    # Attach to table
    $table->attach(
        $i_label, 0, 1,
        $col_id + 1,
        $col_id + 2,
        'shrink', 'shrink', 0, 0
    );
    $table->attach(
        $label, 1, 2,
        $col_id + 1,
        $col_id + 2,
        'shrink', 'shrink', 0, 0
    );
    $table->attach(
        $combo, 2, 3,
        $col_id + 1,
        $col_id + 2,
        'shrink', 'shrink', 0, 0
    );

    # Store widgets
    $row_widgets->[$col_id] = [$combo];

    return;
}

1;
