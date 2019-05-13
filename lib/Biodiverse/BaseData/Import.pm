package Biodiverse::BaseData::Import;
use strict;
use warnings;
use 5.022;
use English qw { -no_match_vars };

our $VERSION = '2.99_004';

use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';

use Carp;
use Data::Dumper;
use POSIX qw {fmod floor ceil log2};
use Scalar::Util qw /looks_like_number blessed reftype/;
use List::Util 1.45 qw /max min sum any all none notall pairs uniq/;
use List::MoreUtils qw /first_index/;
use Path::Class;
use Geo::Converter::dms2dd qw {dms2dd};
use Regexp::Common qw /number/;
use Data::Compare ();
use Geo::ShapeFile;

use Ref::Util qw { :all };
use Sort::Key::Natural qw /natkeysort/;
use Spreadsheet::Read 0.60;

use Geo::GDAL::FFI 0.07;

#  these are here for PAR purposes to ensure they get packed
#  Spreadsheet::Read calls them as needed
#  (not sure we need all of them, though)
require Spreadsheet::ReadSXC;
require Spreadsheet::ParseExcel;
require Spreadsheet::ParseXLSX;


#  how much input file to read in one go
our $input_file_chunk_size   = 10000000;
our $lines_to_read_per_chunk = 50000;

our $EMPTY_STRING = q{};
our $bytes_per_MB = 1056784;


sub get_metadata_import_data_common {
    my $self = shift;

    my @parameters = (
        {
            name       => 'allow_empty_labels',
            label_text => 'Allow labels with no groups?',
            tooltip    => "Retain labels with no groups.\n"
              . "Requires a sample count column with value zero\n"
              . "(undef/empty is treated as 1).",
            type    => 'boolean',
            default => 0,
        },
        {
            name       => 'allow_empty_groups',
            label_text => 'Allow empty groups?',
            tooltip    => "Retain groups with no labels.\n"
              . "Requires a sample count column with value zero\n"
              . "(undef/empty is treated as 1).",
            type    => 'boolean',
            default => 0,
        },
        {
            name       => 'data_in_matrix_form',
            label_text => 'Data are in matrix form?',
            tooltip => 'Are the data in a form like a site by species matrix?',
            type    => 'boolean',
            default => 0,
        },
        {
            name       => 'skip_lines_with_undef_groups',
            label_text => 'Skip lines with undef groups?',
            tooltip    => 'Turn on if some records have undefined/blank/NA '
              . 'group values and should be skipped.  '
              . 'Import will otherwise fail if they are found.',
            type    => 'boolean',
            default => 1,
        },
        {
            name       => 'binarise_counts',
            label_text => 'Convert sample counts to binary?',
            tooltip    => 'Any non-zero sample count will be '
              . "converted to a value of 1.  \n"
              . 'Applies to each record, not to groups.',
            type    => 'boolean',
            default => 0,
        },
    );
    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    #  these parameters are only for the GUI, so are not a full set
    my %arg_hash = ( parameters => \@parameters, );

    return wantarray ? %arg_hash : \%arg_hash;
}

sub get_metadata_import_data_text {
    my $self = shift;

    my @sep_chars = my @separators =
      defined $ENV{BIODIVERSE_FIELD_SEPARATORS}
      ? @$ENV{BIODIVERSE_FIELD_SEPARATORS}
      : ( q{,}, 'tab', q{;}, 'space', q{:} );
    my @input_sep_chars = ( 'guess', @sep_chars );

    my @quote_chars =
      qw /" ' + $/;    # " (comment just catching runaway quote in eclipse)
    my @input_quote_chars = ( 'guess', @quote_chars );

    my @parameters = (

        #{ name => 'input_files', type => 'file' }, # not for the GUI
        {
            name       => 'input_sep_char',
            label_text => 'Input field separator',
            tooltip    => 'Select character',
            type       => 'choice',
            choices    => \@input_sep_chars,
            default    => 0,
        },
        {
            name       => 'input_quote_char',
            label_text => 'Input quote character',
            tooltip    => 'Select character',
            type       => 'choice',
            choices    => \@input_quote_chars,
            default    => 0,
        },
    );
    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    #  these parameters are only for the GUI, so are not a full set
    my %arg_hash = ( parameters => \@parameters, );

    return wantarray ? %arg_hash : \%arg_hash;
}

sub get_metadata_import_data_raster {
    my $self = shift;

    my @parameters = (
        {
            name       => 'labels_as_bands',
            label_text => 'Read bands as labels?',
            tooltip => 'When reading raster data, does each band represent a '
              . 'label (eg species)?',
            type    => 'boolean',
            default => 1,
        },
        {
            name       => 'strip_file_extensions_from_names',
            label_text => 'Strip file extensions from names?',
            tooltip =>
              'Strip any file extensions from label names when treating '
              . 'band names as labels',
            type    => 'boolean',
            default => 1,
        },
        {
            name       => 'raster_cellsize_e',
            label_text => 'Cell size east/long',
            tooltip    => 'Size of group cells (Eastings/Longitude)',
            type       => 'float',
            default    => 100000,
            digits     => 10,
        },
        {
            name       => 'raster_cellsize_n',
            label_text => 'Cell size north/lat',
            tooltip    => 'Size of group cells (Northings/Latitude)',
            type       => 'float',
            default    => 100000,
            digits     => 10,
        },
        {
            name       => 'raster_origin_e',
            label_text => 'Cell origin east/long',
            tooltip    => 'Origin of group cells (Eastings/Longitude)',
            type       => 'float',
            default    => 0,
            digits     => 10,
        },
        {
            name       => 'raster_origin_n',
            label_text => 'Cell origin north/lat',
            tooltip    => 'Origin of group cells (Northings/Latitude)',
            type       => 'float',
            default    => 0,
            digits     => 10,
        },
    );

    #  these parameters are only for the GUI, so are not a full set
    my %arg_hash = ( parameters => \@parameters, );

    return wantarray ? %arg_hash : \%arg_hash;
}

*load_data = \&import_data;

#  import data from a delimited text file
sub import_data {
    my $self = shift;
    my %args = @_;

    my $progress_bar = Biodiverse::Progress->new( gui_only => 1 );

    croak "input_files array not provided\n"
      if !$args{input_files} || (!is_arrayref($args{input_files}));

    $args{label_columns} //= $self->get_param('LABEL_COLUMNS');
    $args{group_columns} //= $self->get_param('GROUP_COLUMNS');

    if ( $args{data_in_matrix_form} ) {    #  clunky but needed for lower down
        $args{label_columns} //= [];
    }

    $args{cell_is_lat} =
         $self->get_param('CELL_IS_LAT')
      || $args{cell_is_lat}
      || [];

    $args{cell_is_lon} =
         $self->get_param('CELL_IS_LON')
      || $args{cell_is_lon}
      || [];

    $args{sample_count_columns} //= [];

    my $labels_ref = $self->get_labels_ref;
    my $groups_ref = $self->get_groups_ref;

    say "[BASEDATA] Loading from files "
      . join( q{ }, @{ $args{input_files} } );

    my @label_columns        = @{ $args{label_columns} };
    my @group_columns        = @{ $args{group_columns} };
    my @cell_sizes           = $self->get_cell_sizes;
    my @cell_origins         = $self->get_cell_origins;
    my @cell_is_lat_array    = @{ $args{cell_is_lat} };
    my @cell_is_lon_array    = @{ $args{cell_is_lon} };
    my @sample_count_columns = @{ $args{sample_count_columns} };
    my $exclude_columns      = $args{exclude_columns};
    my $include_columns      = $args{include_columns};
    my $binarise_counts = $args{binarise_counts};   #  make sample counts 1 or 0
    my $data_in_matrix_form = $args{data_in_matrix_form};
    my $allow_empty_groups  = $args{allow_empty_groups};
    my $allow_empty_labels  = $args{allow_empty_labels};

    my $skip_lines_with_undef_groups =
      exists $args{skip_lines_with_undef_groups}
      ? $args{skip_lines_with_undef_groups}
      : 1;

    #  check the exclude and include args
    $exclude_columns //= [];
    $include_columns //= [];
    croak "exclude_columns argument is not an array reference"
      if !is_arrayref($exclude_columns);
    croak "include_columns argument is not an array reference"
      if !is_arrayref($include_columns);

    #  clear out any undef columns
    $exclude_columns = [ grep { defined $_ } @$exclude_columns ];
    $include_columns = [ grep { defined $_ } @$include_columns ];

    #  croak if we have differing array lengths
    croak
"Number of group columns differs from cellsizes ($#group_columns != $#cell_sizes)"
      if scalar @group_columns != scalar @cell_sizes;

    my @half_cellsize = map { $_ / 2 } @cell_sizes;

    my $quotes = $self->get_param('QUOTES');      #  for storage, not import
    my $el_sep = $self->get_param('JOIN_CHAR');

    #  for parsing lines to element components
    my %line_parse_args = (
        label_columns        => \@label_columns,
        group_columns        => \@group_columns,
        cell_sizes           => \@cell_sizes,
        half_cellsize        => \@half_cellsize,
        cell_origins         => \@cell_origins,
        sample_count_columns => \@sample_count_columns,
        exclude_columns      => $exclude_columns,
        include_columns      => $include_columns,
        allow_empty_groups   => $allow_empty_groups,
        allow_empty_labels   => $allow_empty_labels,
    );

    my $line_count_all_input_files = 0;
    my $orig_group_count           = $self->get_group_count;
    my $orig_label_count           = $self->get_label_count;

#print "[BASEDATA] Input files to load are ", join (" ", @{$args{input_files}}), "\n";
    foreach my $file ( @{ $args{input_files} } ) {
        $file = Path::Class::file($file)->absolute;
        say "[BASEDATA] INPUT FILE: $file";
        my $file_base = $file->basename;

        my $file_handle = $self->get_file_handle (
            file_name => $file,
            use_bom   => 1,
        );
        my $file_size_bytes = $self->get_file_size_aa ($file);

        my $file_size_Mb = $self->set_precision(
            precision => "%.3f",
            value     => $file_size_bytes
          ) /
          $bytes_per_MB;

        #  for progress bar stuff
        my $size_comment =
          $file_size_Mb > 10
          ? "This could take a while\n"
          . "(it is still working if the progress bar is not moving)"
          : $EMPTY_STRING;

        my $input_binary = $args{binary}
          // 1;    #  a boolean flag for Text::CSV_XS
        my $input_quote_char = $args{input_quote_char};
        my $sep              = $args{input_sep_char};

        my $in_csv = $self->get_csv_object_using_guesswork(
            fname      => $file,
            sep_char   => $sep,
            quote_char => $input_quote_char,
            binary     => $input_binary,
        );
        my $out_csv = $self->get_csv_object(
            sep_char   => $el_sep,
            quote_char => $quotes,
        );

        my $lines = $self->get_next_line_set(
            file_handle       => $file_handle,
            file_name         => $file,
            target_line_count => $lines_to_read_per_chunk,
            csv_object        => $in_csv,
        );

        #  Get the header line, assumes no binary chars in it.
        #  If there are then there is something really wrong with the file.
        my $header = shift @$lines;

        #  parse the header line if we are using a matrix format file
        my $matrix_label_col_hash = {};
        if ($data_in_matrix_form) {
            my $label_start_col = $args{label_start_col};
            my $label_end_col   = $args{label_end_col};

            #  if we've been passed an array then
            #  use the first one for the start and the last for the end
            #  - this can happen due to the way GUI::BasedataImport
            #  handles options and is something we need to clean
            #  up with better metadata
            if ( ref $label_start_col ) {
                $label_start_col = $label_start_col->[0];
            }
            if ( ref $label_end_col ) {
                $label_end_col = $label_end_col->[-1];
            }
            my $header_array = $header;
            $matrix_label_col_hash = $self->get_label_columns_for_matrix_import(
                csv_object      => $out_csv,
                label_array     => $header_array,
                label_start_col => $label_start_col,
                label_end_col   => $label_end_col,
                %line_parse_args,
            );
        }

        my $line_count =
          scalar @$lines + 1;    # count number of lines, incl header
        my $line_count_used_this_file = 1;    #  allow for headers
        my $line_num_end_prev_chunk   = 1;

        my $line_num = 0;

        #my $line_num_end_last_chunk = 0;
        my $chunk_count = 0;

    #my $total_chunk_text = $self->get_param_as_ref ('IMPORT_TOTAL_CHUNK_TEXT');
        my $total_chunk_text = '>0';
        my %gp_lb_hash;
        my %args_for_add_elements_collated = (
            csv_object         => $out_csv,
            binarise_counts    => $binarise_counts,
            allow_empty_groups => $allow_empty_groups,
            allow_empty_labels => $allow_empty_labels,
        );

        say '[BASEDATA] Line number: 1';
        say "[BASEDATA]  Chunk size $line_count lines";

        #  destroy @lines as we go, saves a bit of memory for big files
        #  keep going if we have lines to process or haven't hit the end of file
      BYLINE:
        while ( scalar @$lines or not( eof $file_handle ) ) {
            $line_num++;

            #  read next chunk if needed.
            #  section must be here in case we have an
            #  exclude on or near the last line of the chunk
            if ( scalar @$lines == 0 ) {
                $lines = $self->get_next_line_set(
                    progress          => $progress_bar,
                    file_handle       => $file_handle,
                    file_name         => $file,
                    target_line_count => $lines_to_read_per_chunk,
                    csv_object        => $in_csv,
                );

                $line_num_end_prev_chunk = $line_count;
                $line_count += scalar @$lines;

                $chunk_count++;
                $total_chunk_text =
                  $file_handle->eof ? $chunk_count : ">$chunk_count";

                #  add the collated data
                $self->add_elements_collated(
                    data => \%gp_lb_hash,
                    %args_for_add_elements_collated,
                );
                %gp_lb_hash = ();    #  clear the collated list
            }

            if ( $line_num % 1000 == 0 ) {    # progress information

                my $line_count_text =
                  eof($file_handle)
                  ? " $line_count"
                  : ">$line_count";

                my $frac = eval {
                    ( $line_num - $line_num_end_prev_chunk ) /
                      ( $line_count - $line_num_end_prev_chunk );
                };
                $progress_bar->update(
                    "Loading $file_base\n"
                      . "Line $line_num of $line_count_text\n"
                      . "Chunk #$chunk_count",
                    $frac
                );

                if ( $line_num % 10000 == 0 ) {
                    print "Loading $file_base line "
                      . "$line_num of $line_count_text, "
                      . "chunk $chunk_count\n";
                }
            }

            my $fields_ref = shift @$lines;

            #  skip blank lines or those that failed
            next BYLINE if !defined $fields_ref or !scalar @$fields_ref;

            #  should we explicitly exclude or include this record?
            next BYLINE
              if scalar @$exclude_columns
              && any { $fields_ref->[$_] } @$exclude_columns;
            next BYLINE
              if scalar @$include_columns
              && none { $fields_ref->[$_] } @$include_columns;

            #  get the group for this row
            my @group;
            my $i = 0;
            foreach my $column (@group_columns) {    #  build the list of groups
                my $coord = $fields_ref->[$column];

                if ( $cell_sizes[$i] >= 0 ) {
                    next BYLINE
                      if $skip_lines_with_undef_groups
                      && ( !defined $coord || $coord eq 'NA' || $coord eq '' );

                    if ( $cell_is_lat_array[$i] ) {
                        my $lat_args = {
                            value  => $coord,
                            is_lat => 1,
                        };
                        $coord = eval { dms2dd($lat_args) };
                        croak $EVAL_ERROR if $EVAL_ERROR;
                    }
                    elsif ( $cell_is_lon_array[$i] ) {
                        my $lon_args = {
                            value  => $coord,
                            is_lon => 1,
                        };
                        $coord = eval { dms2dd($lon_args) };
                        croak $EVAL_ERROR if $EVAL_ERROR;
                    }
                    if ( !looks_like_number($coord) ) {
                        #next BYLINE if $skip_lines_with_undef_groups;
                        my $one_based_column = $column + 1;
                        
                        croak "[BASEDATA] Non-numeric group field in column $column"
                             . " ($coord) \n(column count starts at 0,"
                             . " you may need to check column $one_based_column)."
                             . " Check your data or cellsize arguments.\n"
                             . "near line $line_num of file $file\n";
                    }
                }

                if ( $cell_sizes[$i] > 0 ) {

                    #  allow for different snap value - shift before aggregation
                    my $tmp = $coord - $cell_origins[$i];

                    #  how many cells away from the origin are we?
                    #  snap to 10dp precision to avoid cellsize==0.1 issues
                    my $tmp_prec =
                      $self->round_to_precision_aa( $tmp / $cell_sizes[$i] );

                    my $offset = floor($tmp_prec);

                    #  which cell are we?
                    my $gp_val = $offset * $cell_sizes[$i];

                    #  now assign the centre of the cell we are in
                    $gp_val += $half_cellsize[$i];

                    #  now shift the aggregated cell back to where it should be
                    $group[$i] = $gp_val + $cell_origins[$i];
                }
                else {
#  commented next check - don't trap undef text fields as they can be useful
#croak "Null field value for text field, column $i, line $line_num of file $file\n$_"
#        if ! defined $fields_ref->[$column];

                    #  negative cell sizes denote non-numeric groups,
                    #  zero means keep the original values
                    $group[$i] = $coord;
                }
                $i++;
            }

            my $group = $self->list2csv(
                list       => \@group,
                csv_object => $out_csv,
            );
            if ( scalar @group == 1 ) {
                $group = $self->dequote_element(
                    element    => $group,
                    quote_char => $quotes,
                );
            }

            my %elements;
            if ($data_in_matrix_form) {
                %elements = $self->get_labels_from_line_matrix(
                    fields_ref     => $fields_ref,
                    csv_object     => $out_csv,
                    line_num       => $line_num,
                    file           => $file,
                    label_col_hash => $matrix_label_col_hash,
                    %line_parse_args,
                );
            }
            else {
                %elements = $self->get_labels_from_line(
                    fields_ref => $fields_ref,
                    csv_object => $out_csv,
                    line_num   => $line_num,
                    file       => $file,
                    %line_parse_args,
                );
            }

          ADD_ELEMENTS:
            while ( my ( $el, $count ) = each %elements ) {
                if ( defined $count ) {
                    next ADD_ELEMENTS if $count eq 'NA';

                    next ADD_ELEMENTS
                      if $data_in_matrix_form
                      && $count eq $EMPTY_STRING;

                    next ADD_ELEMENTS
                      if !$count and !$allow_empty_groups;
                }
                else {    #  don't allow undef counts in matrices
                    next ADD_ELEMENTS
                      if $data_in_matrix_form;
                }

                #  single label col or matrix form data
                #  need extra quotes to be stripped
                #  should clean up mx form on first pass
                #  or do as a post-processing step
                if ( scalar @label_columns <= 1 ) {
                    $el = $self->dequote_element(
                        element    => $el,
                        quote_char => $quotes,
                    );
                }

                #  collate them so we can add them in a batch later
                if ( looks_like_number $count) {
                    $gp_lb_hash{$group}{$el} += $count;
                }
                else {
                    #  don't override existing counts with undef
                    $gp_lb_hash{$group}{$el} //= $count;
                }
            }

            $line_count_used_this_file++;
            $line_count_all_input_files++;
        }

        #  add the last set
        $self->add_elements_collated(
            data => \%gp_lb_hash,
            %args_for_add_elements_collated,
        );

        $file_handle->close;
        say "\tDONE (used $line_count_used_this_file of $line_count lines)";
    }

    $self->run_import_post_processes(
        %line_parse_args,
        orig_group_count => $orig_group_count,
        orig_label_count => $orig_label_count,
    );

    return 1;    #  success
}

# subroutine to read a data file using GDAL library.  arguments
# input_files: list of files to read(?)
# labels_as_bands: if true, read each band as a label, and each cell value as count.
#   otherwise read a single raster band (?), and interpret numeric values as labels
# further questions: interpreting coordinates, assume values are UTM? provide other options?
sub import_data_raster {
    my $self = shift;
    my %args = @_;

    my $orig_group_count = $self->get_group_count;
    my $orig_label_count = $self->get_label_count;

    my $progress_bar_files = Biodiverse::Progress->new( gui_only => 1 );
    my $progress_bar       = Biodiverse::Progress->new( gui_only => 0 );

    croak "Input files array not provided\n"
      if !$args{input_files} || (!is_arrayref($args{input_files}));
    my $labels_as_bands = exists $args{labels_as_bands} ? $args{labels_as_bands} : 1;
    my $strip_file_extensions_from_names
      = exists $args{strip_file_extensions_from_names}
        ? $args{strip_file_extensions_from_names}
        : 1;
    my $cellorigin_e    = $args{raster_origin_e};
    my $cellorigin_n    = $args{raster_origin_n};
    my $cellsize_e      = $args{raster_cellsize_e};
    my $cellsize_n      = $args{raster_cellsize_n};
    my $given_label     = $args{given_label};

    my $labels_ref = $self->get_labels_ref;
    my $groups_ref = $self->get_groups_ref;

    say "[BASEDATA] Loading from files as GDAL "
      . join( q{ }, @{ $args{input_files} } );

    # hack, set parameters here? using local ref arrays?
    my @cell_sizes   = $self->get_cell_sizes;
    my @cell_origins = $self->get_cell_origins;
    if ( !@cell_sizes ) {
        @cell_sizes   = ( $cellsize_e,   $cellsize_n );
        @cell_origins = ( $cellorigin_e, $cellorigin_n );
        $self->set_param( CELL_SIZES   => \@cell_sizes );
        $self->set_param( CELL_ORIGINS => \@cell_origins );
    }
    else {
        croak "Unable to import more than two axes from raster data"
          if @cell_sizes > 2;

        $cellsize_e   = $cell_sizes[0];
        $cellsize_n   = $cell_sizes[1];
        $cellorigin_e = $cell_origins[0];
        $cellorigin_n = $cell_origins[1];
    }

    my @half_cellsize  = map { $_ / 2 } @cell_sizes;
    my $halfcellsize_e = $half_cellsize[0];
    my $halfcellsize_n = $half_cellsize[1];

    my $quotes = $self->get_param('QUOTES');      #  for storage, not import
    my $el_sep = $self->get_param('JOIN_CHAR');

    my $out_csv = $self->get_csv_object(
        sep_char   => $el_sep,
        quote_char => $quotes,
    );

    my %args_for_add_elements_collated = (
        csv_object => $out_csv,
        %args,                                    #  we can finesse this later
    );

  # load each file, using same arguments/parameters
  #say "[BASEDATA] Input files to load are ", join (" ", @{$args{input_files}});
    my $file_iter      = 0;
    my $input_file_arr = $args{input_files};
    my $file_count     = scalar @$input_file_arr;

    foreach my $file (@$input_file_arr) {
        $file_iter++;
        if ( scalar @$input_file_arr > 1 ) {
            $progress_bar_files->update(
                "Raster file $file_iter of $file_count\n",
                $file_iter / $file_count,
            );
        }

        $file = Path::Class::file($file)->absolute;
        my $file_base = Path::Class::File->new($file)->basename();
        say "[BASEDATA] INPUT FILE: $file";

        croak "[BASEDATA] $file DOES NOT EXIST OR CANNOT BE READ "
            . "- CANNOT LOAD DATA\n"
          if !$self->file_is_readable (file_name => $file);

        # process using GDAL library
        my $data = Geo::GDAL::FFI::Open( $file->stringify() );

        croak "[BASEDATA] Failed to read $file with GDAL\n"
          if !defined $data;

        my $gdal_driver = $data->GetDriver();
        my $band_count  = $data->GetBands;
        my ($xsize, $ysize) = ($data->GetWidth, $data->GetHeight);
        say '[BASEDATA] Driver: ', $gdal_driver->GetName;
        say "[BASEDATA] Size is $xsize x $ysize x $band_count";
        my $info = $data->GetInfo;
        my ($coord_sys) = grep {/Coordinate System/i} split /[\r\n]+/, $info;
        #my $x = $data->GetProjectionString;  #  should use this?
        say '[BASEDATA] ' . $coord_sys;

        my @tf = $data->GetGeoTransform();
        say '[BASEDATA] Transform is ', join( ' ', @tf );
        say "[BASEDATA] Origin = ($tf[0], $tf[3])";
        say "[BASEDATA] Pixel Sizes = ($tf[1], $tf[2], $tf[4], $tf[5])"
          ;    #  $tf[5] is negative to allow for line order
               #  avoid repeated array lookups below
        my ( $tf_0, $tf_1, $tf_2, $tf_3, $tf_4, $tf_5 ) = @tf;

        #  does not allow for rotations, but not sure
        #  that it should since Biodiverse doesn't either.
        $cellsize_e ||= abs $tf_1;
        $cellsize_n ||= abs $tf_5;

        # iterate over each band
        foreach my $b ( 1 .. $band_count ) {
            my $band = $data->GetBand($b);
            my ( $blockw, $blockh, $maxw, $maxh );
            my ( $wpos, $hpos ) = ( 0, 0 );
            my $nodata_value = $band->GetNoDataValue;
            my $this_label;

            say "Band $b, type ", $band->GetDataType;
            if ( defined $given_label ) {
                $this_label = $given_label;
            }
            elsif ($labels_as_bands) {

                # if single band, set label as filename
                if ( $band_count == 1 ) {
                    $this_label =
                      Path::Class::File->new( $file->stringify )->basename();
                    if ($strip_file_extensions_from_names) {
                        $this_label =~ s/\.\w+$//;    #  should use fileparse?
                    }
                }
                else {
                    $this_label = "band$b";
                }
            }
            if ( defined $this_label ) {
                $this_label = $self->dequote_element(
                    element    => $this_label,
                    quote_char => $quotes,
                );
            }

            # get category names for this band, which will attempt
            # to be used as labels based on cell values (if ! labels_as_bands)
            my @catnames = $band->can ('GetCategoryNames') ? $band->GetCategoryNames : ();
            my %catname_hash;
            @catname_hash{ ( 0 .. $#catnames ) } = @catnames;

            # read as preferred size blocks?
            ( $blockw, $blockh ) = $band->GetBlockSize();
            say   "Block size ($blockw, $blockh), "
                . "full size ($xsize, $ysize)";

            my $target_count    = $xsize * $ysize;
            my $processed_count = 0;

            # read a "block" at a time
            # assume @cell_sizes is ($xsize, $ysize)
            $hpos = 0;
            while ( $hpos < $ysize ) {

                # progress bar stuff
                my $frac = $hpos / $ysize;
                $progress_bar->update(
                    "Loading $file_base\n"
                      . "Cell $processed_count of $target_count\n",
                    $frac
                );

                if ( $hpos % 10000 == 0 ) {
                    say "Loading $file_base "
                      . "Cell $processed_count of $target_count\n",
                      $frac;
                }

                #  temporary store for groups and labels so
                #  we can reduce the calls to add_element
                my %gp_lb_hash;

                $wpos = 0;
                while ( $wpos < $xsize ) {
                    $maxw = min( $xsize, $wpos + $blockw );
                    $maxh = min( $ysize, $hpos + $blockh );

            #say "reading tile at origin ($wpos, $hpos), to max ($maxw, $maxh)";
                    my $lr = $band->Read(
                        $wpos, $hpos,
                        $maxw - $wpos,
                        $maxh - $hpos
                    );
                    my @tile  = @$lr;
                    my $gridy = $hpos;

                  ROW:
                    foreach my $lineref (@tile) {
                        my ( $ngeo, $ncell, $grpn, $grpstring );
                        if ( !$tf_4 )
                        {    #  no transform so constant y for this line
                            $ngeo = $tf_3 + $gridy * $tf_5;
                            $ncell =
                              floor( ( $ngeo - $cellorigin_n ) / $cellsize_n );
                            $grpn =
                              $cellorigin_n +
                              $ncell * $cellsize_n -
                              $halfcellsize_n;
                        }

                        my $gridx = $wpos - 1;
                        my $prev_x =
                          $tf_0 - 100; #  just need something west of the origin

                      COLUMN:
                        foreach my $entry (@$lineref) {
                            $gridx++;

                            # need to add check for empty groups
                            # when it is added as an argument
                            next COLUMN
                              if defined $nodata_value
                              && $entry == $nodata_value;

                            # data points are 0,0 at top-left of data,
                            # however grid coordinates used for
                            # transformation start at bottom-left
                            # corner (transform handled by following
                            # affine transformation, with y-pixel size = -1).

                            # find transformed position (see GDAL specs)
                            #Egeo = GT(0) + Xpixel*GT(1) + Yline*GT(2)
                            #Ngeo = GT(3) + Xpixel*GT(4) + Yline*GT(5)
                            #  then calculate "group" from this position.
                            #  (defined as csv string of central points of group)
                            # note "geo" coordinates are the top-left of the cell (NW)
                            my $egeo = $tf_0 + $gridx * $tf_1 + $gridy * $tf_2;
                            my $ecell =
                              floor( ( $egeo - $cellorigin_e ) / $cellsize_e );
                            my $grpe =
                              $cellorigin_e +
                              $ecell * $cellsize_e +
                              $halfcellsize_e;

                            my $new_gp;
                            if ($tf_4) {    #  need to transform the y coords
                                $ngeo = $tf_3 + $gridx * $tf_4 + $gridy * $tf_5;
                                $ncell = floor( ( $ngeo - $cellorigin_n ) / $cellsize_n );

                                # subtract half cell width since position is top-left
                                $grpn =
                                  $cellorigin_n +
                                  $ncell * $cellsize_n -
                                  $halfcellsize_n;

                                #  cannot guarantee constant groups
                                #  for rotated/transformed data
                                #  so we need a new group name
                                $new_gp = 1;
                            }
                            else {
                                #  if $grpe has not changed then
                                #  we can re-use the previous group name
                                $new_gp = $prev_x != $grpe;
                            }

                            if ($new_gp) {
                                #  no need to even use the csv object to
                                #  stick them together (this was a
                                #  bottleneck due to all the csv calls)
                                $grpstring = join $el_sep, ( $grpe, $grpn );
                            }

                            # set label if determined at cell level
                            my $count = 1;
                            if ( $labels_as_bands || defined $given_label ) {
                                # set count to cell value if using
                                # band as label or provided label
                                $count = $entry;
                            }
                            else {
                                # set label from cell value or category if valid
                                $this_label = $catname_hash{$entry} // $entry;
                            }

                            #  collate the data
                            $gp_lb_hash{$grpstring}{$this_label} += $count;

                            $prev_x = $grpe;

                        }    # each entry on line

                        $gridy++;
                        #  saves incrementing inside the loop
                        $processed_count += scalar @$lineref;
                    }    # each line in block

                    $wpos += $blockw;
                }    # each block in width

                $hpos += $blockh;

                $self->add_elements_collated(
                    %args_for_add_elements_collated,
                    data => \%gp_lb_hash,
                );

            }    # each block in height
        }    # each raster band

        $progress_bar->update( 'Done', 1 );
    }    # each file

    $self->run_import_post_processes(
        %args,
        label_axis_count => 1,    #  FIXME - might change if we have a remap
        orig_group_count => $orig_group_count,
        orig_label_count => $orig_label_count,
    );

    return 1;
}

# subroutine to read a data file as shapefile.  arguments
# input_files: list of files to read(?)
# label_fields: fields which are read as labels (from ('x','y','z','m'))
# group_fields: fields which are read as labels (from ('x','y','z','m'))
# use_dbf_label: looks for label entry in dbf record, use for labels (supercedes label fields)
sub import_data_shapefile {
    my $self = shift;
    my %args = @_;

    my $orig_group_count = $self->get_group_count;
    my $orig_label_count = $self->get_label_count;

    my $progress_bar = Biodiverse::Progress->new();

    croak "Input files array not provided\n"
      if !$args{input_files} || (!is_arrayref($args{input_files}));

    my $skip_lines_with_undef_groups =
      exists $args{skip_lines_with_undef_groups}
      ? $args{skip_lines_with_undef_groups}
      : 1;

    my @group_field_names
      = map {lc $_}
        @{ $args{group_fields} // $args{group_field_names} };
    my @label_field_names
      = map {lc $_} 
        @{ $args{label_fields} // $args{label_field_names} };
    my @smp_count_field_names
      = map {lc $_}
        @{ $args{sample_count_col_names} // [] };
    
    my $is_lat_field = $args{is_lat_field};
    my $is_lon_field = $args{is_lon_field};

    my $binarise_counts = $args{binarise_counts};

    my @group_origins = $self->get_cell_origins;
    my @group_sizes   = $self->get_cell_sizes;

    my $labels_ref = $self->get_labels_ref;
    my $groups_ref = $self->get_groups_ref;

    say '[BASEDATA] Loading from files as shapefile '
      . join( q{ }, @{ $args{input_files} } );

    # needed to construct the groups and labels
    my $quotes  = $self->get_param('QUOTES');      #  for storage, not import
    my $el_sep  = $self->get_param('JOIN_CHAR');
    my $out_csv = $self->get_csv_object(
        sep_char   => $el_sep,
        quote_char => $quotes,
    );
    my %args_for_add_elements_collated = (
        csv_object         => $out_csv,
        binarise_counts    => $binarise_counts,
        allow_empty_groups => $args{allow_empty_groups},
        allow_empty_labels => $args{allow_empty_labels},
    );
    
    my @input_files = @{ $args{input_files} };
    my $num_files = @input_files;
    my $file_progress;
    if (@input_files > 1) {
        $file_progress = Biodiverse::Progress->new (gui_only => 1);
    }
    
    my @field_names_used_lc
      = grep {not $_ =~ /^:/}
        (@label_field_names,
         @group_field_names,
         @smp_count_field_names);

    my $need_shape_geometry
      = grep {$_ =~ /\:shape_(?:area|length)/} (
        @label_field_names,
        @group_field_names,
        @smp_count_field_names
    );
    $need_shape_geometry = $binarise_counts ? 0 : $need_shape_geometry;

    ##  CHECK WE NEED :shape_x and :shape_y
    my $need_shape_xy
      = grep {$_ =~ m/\:shape_[xy]/} @group_field_names;

    # load each file, using same arguments/parameters
    my $file_num = 0;
    foreach my $file ( @input_files ) {
        $file_num++;
        $file = Path::Class::file($file)->absolute->stringify;
        say "[BASEDATA] INPUT FILE: $file";
        
        if ($file_progress) {
            $file_progress->update (
                "File $file_num of $num_files",
                $file_num / $num_files,
            );
        }

        # open as shapefile
        my $fnamebase = $file;
        my $layer_dataset = Geo::GDAL::FFI::Open($fnamebase);
        my $layer = $layer_dataset->GetLayer;
        $layer->ResetReading;
        my $defn = $layer->GetDefn;
        my $layer_name = $defn->GetName;
        #  needs a method
        my $schema     = $defn->GetSchema;
        my $shape_type = $schema->{GeometryFields}[0]{Type};

        croak "[BASEDATA] $fnamebase: Import of feature type $shape_type is not supported.\n"
          if not $shape_type =~ /Point|Polygon|Line/;

        #  some validation
        #  keys are case insensitive, values store case
        my %fld_names = map {lc ($_->{Name}) => $_->{Name}} @{$schema->{Fields}};
        foreach my $key (@label_field_names) {
            croak "Shapefile $file does not have a field called $key\n"
              if ($key !~ /^:/) && !exists $fld_names{$key};
        }

        #  get a Fishnet Identity overlay if we have polygons
        my ($f_dataset, $f_layer);
        if ($need_shape_xy && $shape_type =~ 'Polygon|LineString') {

            croak "Polygon and polyline imports need both "
             . ":shape_x and :shape_y in the group field names\n"
               if $need_shape_xy < 2;

            #  what to do if one is used twice?
            my $shape_x_index = first_index {$_ eq ':shape_x'} @group_field_names;
            my $shape_y_index = first_index {$_ eq ':shape_y'} @group_field_names;
            
            $layer_dataset->ExecuteSQL(qq{CREATE SPATIAL INDEX ON "$layer_name"});

            if ($need_shape_geometry) {
                $f_layer = $self->get_fishnet_identity_layer (
                    source_layer => $layer,
                    schema       => $schema,
                    axes         => [$shape_x_index, $shape_y_index],
                );
                $layer = undef;
                $layer = $f_layer;  #  assigning in method call causes failures?
                $layer->ResetReading;
                #  update a few things
                $defn   = $layer->GetDefn;
                $schema = $defn->GetSchema;
                %fld_names = map {lc ($_->{Name}) => $_->{Name}} @{$schema->{Fields}};
            }
            else {
                ($f_dataset, $f_layer) = $self->get_fishnet_polygon_layer (
                    source_layer => $layer,
                    schema       => $schema,
                    resolutions  => [@group_sizes[  $shape_x_index, $shape_y_index]],
                    origins      => [@group_origins[$shape_x_index, $shape_y_index]],
                    extent       => $layer->GetExtent,
                    shape_type   => $shape_type,
                    inner_buffer => 'auto',
                );
            }
        }

        #my $shape_count = $layer->GetFeatureCount();
        #  interim solution
        my $shape_count = 0;
        while ($layer->GetNextFeature) {
            $shape_count++;
        }
        $layer->ResetReading;
        say "File has $shape_count shapes";
        
        %fld_names = %fld_names{@field_names_used_lc};

        # iterate over shapes
        my %gp_lb_hash;
        my $count = 0;
      SHAPE:
        while (my $shape = $layer->GetNextFeature) {
            $count ++;

            # Get database record for this shape.
            # Same for all features in the shape.
            # Awkward - should just get the fields we need
            #say 'Getting fields: ' . join ' ', sort keys %fld_names;
            my %db_rec = map {lc ($_) => ($shape->GetField ($_) // undef)} values %fld_names;

            my $ptlist = [];
            my $default_count = 1;
            # just get all the points from the shape.
            my $geom = $need_shape_xy ? $shape->GetGeomField : '';
            if (!$need_shape_xy) {
                $ptlist = [[0,0]];  #  dummy list
            }
            elsif ($shape_type =~ 'Point') {
                $ptlist = $geom->GetPoints;
            }
            elsif ($shape_type =~ 'Polygon|Line') {
                if ($need_shape_geometry) {
                    #  use the centroid until we find more efficient methods
                    #  it will be snapped to the group coord lower down
                    $ptlist = $geom->Centroid->GetPoints;
                    #say $geom->AsText;
                    if (!scalar @smp_count_field_names  ) {
                        $default_count = $shape_type =~ /gon/ ? $geom->Area : $geom->Length;
                    }
                    if ($shape_type =~ /gon/) {
                        # need to convert to linestring for length - implement later if we have a need
                        $db_rec{':shape_area'}   = $geom->Area;
                    }
                    else {
                        $db_rec{':shape_length'} = $geom->Length;
                    }
                }
                else {
                    my $f_layer_name = $f_layer->GetName;
                    my $tiles = $f_dataset->ExecuteSQL (
                        qq{SELECT * FROM "$f_layer_name"},
                        $geom,
                    );
                    #  guard against empty result (paranoia)
                    if ($tiles) {
                        $tiles->ResetReading;
                        while (my $tile = $tiles->GetNextFeature) {
                            my $tile_geom = $tile->GetGeomField;
                            my $centroid = $tile_geom->Centroid->GetPoints;
                            push @$ptlist, @$centroid;
                        }
                    }
                }
            }

            # read over all points in the shape
            foreach my $point (@$ptlist) {

                #  add the coords to the db_rec hash
                $db_rec{':shape_x'} = $point->[0];
                $db_rec{':shape_y'} = $point->[1];
                if ($#$point > 1) {
                    $db_rec{':shape_z'} = $point->[2];
                    if ($#$point > 2) {
                        $db_rec{':shape_m'} = $point->[3];
                    }
                }

                my @these_labels;
                my $this_count =
                  scalar @smp_count_field_names
                  ? sum 0, @db_rec{@smp_count_field_names}
                  : $default_count;

                my @lb_fields  = @db_rec{@label_field_names};
                my $this_label = $self->list2csv(
                    list       => \@lb_fields,
                    csv_object => $out_csv
                );
                push @these_labels, $this_label;


                # form group text from group fields
                # (defined as csv string of central points of group)
                # Needs to process the data in the same way as for
                # text imports - refactoring is in order.
                my @group_field_vals = @db_rec{@group_field_names};
                my @gp_fields;
                my $i = -1;
                foreach my $val (@group_field_vals) {
                    $i++;

                    if ( $val eq '-1.79769313486232e+308' ) {
                        next SHAPE if $skip_lines_with_undef_groups;
                        croak "record $count has an undefined coordinate\n";
                    }

                    my $origin = $group_origins[$i];
                    my $g_size = $group_sizes[$i];

                    #  refactor this - duplicated from spreadsheet read
                    if ( $g_size < 0 ) {
                        push @gp_fields, $val;
                    }
                    else {
                        if (   $is_lat_field
                            && $is_lat_field->{ $group_field_names[$i] } )
                        {
                            $val = dms2dd( { value => $val, is_lat => 1 } );
                        }
                        elsif ($is_lon_field
                            && $is_lon_field->{ $group_field_names[$i] } )
                        {
                            $val = dms2dd( { value => $val, is_lon => 1 } );
                        }

                        croak "$val is not numeric\n"
                          if !looks_like_number $val;

                        if ( $g_size > 0 ) {
                            my $cell = floor( ( $val - $origin ) / $g_size );
                            my $grp_centre =
                              $origin + $cell * $g_size + ( $g_size / 2 );
                            push @gp_fields, $grp_centre;
                        }
                        else {
                            push @gp_fields, $val;
                        }
                    }

                }
                my $grpstring = $self->list2csv(
                    list       => \@gp_fields,
                    csv_object => $out_csv,
                );

                foreach my $this_label (@these_labels) {
                    if ( scalar @label_field_names <= 1 ) {
                        $this_label = $self->dequote_element(
                            element    => $this_label,
                            quote_char => $quotes,
                        );
                    }

                    #  collate the groups and labels so we can add them in a batch later
                    if ( looks_like_number $this_count) {
                        $gp_lb_hash{$grpstring}{$this_label} += $this_count;
                    }
                    else {
                        #  don't override existing counts with undef
                        $gp_lb_hash{$grpstring}{$this_label} //= $this_count;
                    }
                }
            }    # each point

            # progress bar stuff
            my $frac = $count / $shape_count;
            $progress_bar->update(
                "Loading $file\n" . "Shape $count of $shape_count\n", $frac );

        }    # each shape

        $layer = undef;  #  a spot of paranoia to close the file
        $progress_bar->update( 'Done', 1 );

        #  add the collated data
        $self->add_elements_collated(
            data => \%gp_lb_hash,
            %args_for_add_elements_collated,
        );
        %gp_lb_hash = ();    #  clear the collated list

    }    # each file

    $progress_bar = undef;  #  some cleanup, prob not needed

    $self->run_import_post_processes(
        %args,
        label_axis_count => scalar @label_field_names,
        orig_group_count => $orig_group_count,
        orig_label_count => $orig_label_count,
    );

    return 1;    #  success
}

sub get_fishnet_identity_layer {
    my ($self, %args) = @_;

    my $layer  = $args{source_layer};
    my $schema = $args{schema};
    my $axes   = $args{axes} // [0,1];
    
    my ($defn, $shape_type, $sr);
    eval {
        #$defn = $layer->GetDefn;
        #$schema = $defn->GetSchema;
        $shape_type = $schema ? $schema->{GeometryFields}[0]{Type} : 'Polygon';
        $sr = $schema ? $schema->{GeometryFields}[0]{SpatialReference} : undef;
    };
    croak $@ if $@;
    
    $sr = Geo::GDAL::FFI::SpatialReference->new($sr);
    #  It is safer to not re-use a spatial reference object 
    my $sr_clone1 = $sr->Clone;
    my $sr_clone2 = $sr->Clone;


    my @group_origins = $self->get_cell_origins;
    my @group_sizes
      = $args{gp_sizes}
      ? @{$args{gp_sizes}}
      : $self->get_cell_sizes;
    
    @group_origins = @group_origins[@$axes];
    @group_sizes   = @group_sizes[@$axes];
    
    #  Use a subdivide approach to handle large polygons.
    #  Should check individual features, as we only really
    #  need this when there are large and complex features.
    my $extent = $layer->GetExtent;
    my $nx = ceil (abs ($extent->[1] - $extent->[0]) / $group_sizes[0]);
    my $ny = ceil (abs ($extent->[3] - $extent->[2]) / $group_sizes[1]);
    if (max ($nx, $ny) > 32) {
        my @coarse_gp_sizes = map {$_ * 8} @group_sizes;
        my $layer2 = $self->get_fishnet_identity_layer (
            %args,
            gp_sizes => \@coarse_gp_sizes,
            axes     => undef,
            source_layer => $layer,
            inner_buffer => $args{inner_buffer} // 'auto',
        );
        $layer = $layer2;
    }

    my $fishnet = $self->get_fishnet_polygon_layer (
        extent => $layer->GetExtent,
        resolutions  => \@group_sizes,
        origins      => \@group_origins,
        inner_buffer => $args{inner_buffer},
        #shape_type  => $shape_type,
        spatial_reference => $sr_clone1,
    );

    my $input_layer_name = $layer->GetName;
    my $progress_text
      = "Processing fishnet intersection for $input_layer_name\n"
      . "Resolution this pass: $group_sizes[0] x $group_sizes[1]";
    my $gui_progress = Biodiverse::Progress->new(
        gui_only => 1,
        text     => $progress_text,
    );
    my $last_p = time() - 1;
    my $progress = sub {
        return 1 if $_[0] < 1 and abs(time() - $last_p) < 0.3;
        my ($fraction, $msg, $data) = @_;
        local $| = 1;
        printf "%.3g ", $fraction;
        $gui_progress->update (
            $progress_text . ($msg // ''),
            $fraction,
        );
        $last_p = time();
        1;
    };
    #$progress = undef;
    
    #my $pulse_progress = Biodiverse::Progress->new(gui_only => 1);
    #$pulse_progress->pulsate ('pulsating');
    #sleep(30);
    
    #  get the fishnet cells that intersect the polygons
    $layer->ResetReading;
    $fishnet->ResetReading;
    
    my $start_time = time();
    
    #  create the layer now so we only get polygons back
    my $layer_name
      = join '_',
        'overlay_result',
        @group_sizes,
        Scalar::Util::refaddr ($self);
    my $overlay_result
        = Geo::GDAL::FFI::GetDriver('GPKG')
            ->Create ($self->_get_scratch_name(prefix => '/vsimem/_', suffix => '.gpkg'))
            ->CreateLayer({
                Name => $layer_name,
                SpatialReference => $sr_clone2,
                GeometryType     => $shape_type,
                Options => {SPATIAL_INDEX => 'YES'},
        });
    #  not sure these have any effect
    my $options = {
        PROMOTE_TO_MULTI        => 'NO',
        USE_PREPARED_GEOMETRIES => 'YES',
        PRETEST_CONTAINMENT     => 'YES',
        KEEP_LOWER_DIMENSION_GEOMETRIES => 'NO',  #  be explicit
        #SKIP_FAILURES           => 'YES',
    };
    
    my $skip_error_re = qr/A geometry of type (MULTI(POLYGON|LINESTRING)|GEOMETRYCOLLECTION) is inserted into layer/;
    say 'Intersecting fishnet with feature layer';
    eval {
        $layer->Intersection(
            $fishnet,
            {
                Result   => $overlay_result,
                Progress => $progress,
                Options  => $options,
            }
        );
    };
    if (my $err = $@) {
        my @errors = split "\n", $err;
        while (@errors and $errors[0] =~ $skip_error_re) {
            shift @errors;
        }
        croak join "\n", @errors
          if @errors;
    }
    
    #  this is dirty and underhanded    
    #if (@Geo::GDAL::FFI::errors) {
        while (@Geo::GDAL::FFI::errors
               and $Geo::GDAL::FFI::errors[0] =~ $skip_error_re
            ) {
            shift @Geo::GDAL::FFI::errors
        }
        croak Geo::GDAL::FFI::error_msg()
          if @Geo::GDAL::FFI::errors;
    #}
    
    my $time_taken = time() - $start_time;
    say "\nIntersection completed in $time_taken seconds";
    
    #  close fishnet data set
    $fishnet = undef;
    
    #$pulse_progress->pulsate_stop;
    
    #my $check = $overlay_result->GetDefn->GetSchema;
    
    return $overlay_result;
}

sub get_fishnet_polygon_layer {
    my ($self, %args) = @_;
    
    local $| = 1;
    
    my $driver = $args{driver} // 'Memory';
    $driver = 'ESRI Shapefile';

    my $out_fname = $args{out_fname};
    if (not $driver =~ /Memory/) {
        $out_fname //= ('fishnet_' . time());
    }
    #else {
    #  override
    $out_fname = $self->_get_scratch_name(
        prefix => '/vsimem/fishnet_',
    );
    #}
    #say "Generating fishnet file $out_fname";
    my $schema = $args{schema};
    
    my $shape_type = $args{shape_type} // ($schema ? $schema->{GeometryFields}[0]{Type} : 'Polygon');
    my $sr = $args{spatial_reference} // ($schema ? $schema->{GeometryFields}[0]{SpatialReference} : undef);

    if (!blessed $sr) {
        $sr = Geo::GDAL::FFI::SpatialReference->new($sr);
    }

    my $extent      = $args{extent};
    my $resolutions = $args{resolutions};
    my $origins     = $args{origins};
    
    croak "Cannot generate a fishnet for fewer than two axes\n"
      if scalar @$resolutions < 2;
    my $has_zero_res = grep {$_ <= 0} @$resolutions[0,1];
    croak "Cannot generate a fishnet where one axis has a negative or zero spacing\n"
      if $has_zero_res;

    #  This avoids cases where polygon edges touch, but there are no interior overlaps.
    #  Such cases occur when reimporting square polygons of exactly the same resolution.  
    my $bt = $args{inner_buffer} // 0;
    if ($bt eq 'auto') {
        $bt = 10e-14 * ($resolutions->[0] + $resolutions->[1]) / 2;
        #  experiment, need to check tests before instating
        #$bt = max (10e-14, 10e-14 / 2 * ($resolutions->[0] + $resolutions->[1]));
    }

    my ($xmin, $xmax, $ymin, $ymax) = @$extent;
    my ($grid_width, $grid_height)  = @$resolutions;
    say "Height and width: $grid_height, $grid_width"; 
    
    say "Input bounds are $xmin, $ymin, $xmax, $ymax";
    
    if ($origins) {    
        my @ll = ($xmin, $ymin);
        foreach my $i (0,1) {
            next if $resolutions->[$i] <= 0;
            my $tmp_prec = $ll[$i] / $resolutions->[$i];
            my $offset = floor ($tmp_prec);
            #  and shift back to index units
            $ll[$i] = $offset * $resolutions->[$i];
        }
        ($xmin, $ymin) = @ll;
        my @ur = ($xmax, $ymax);
        foreach my $i (0,1) {
            next if $resolutions->[$i] <= 0;
            my $tmp_prec = $ur[$i] / $resolutions->[$i];
            my $offset = ceil ($tmp_prec);
            #  and shift back to index units
            $ur[$i] = $offset * $resolutions->[$i];
        }
        ($xmax, $ymax) = @ur;
    }
    
    say "Fishnet bounds are $xmin, $ymin, $xmax, $ymax";
    say "Driver and layer names: $driver, $out_fname";

    my $layer_name = $self->_get_scratch_name (
        prefix => 'Fishnet_Layer'
    );
    my $fishnet_dataset
        = Geo::GDAL::FFI::GetDriver($driver)
            ->Create ($out_fname);
    my $fishnet_lyr
      = $fishnet_dataset->CreateLayer({
                Name => $layer_name,
                GeometryType => $shape_type,
                SpatialReference => $sr,
                Options => {SPATIAL_INDEX => 'YES'},
        });
    #my $featureDefn = $fishnet_lyr->GetDefn();

    my $rows = ceil(($ymax - $ymin) / $grid_height);
    my $cols = ceil(($xmax - $xmin) / $grid_width);
    say "Generating fishnet of size $rows x $cols";
    say "Origins are: " . join ' ', @$origins;

    # start grid cell envelope
    my $ring_X_left_origin   = $xmin;
    my $ring_X_right_origin  = $xmin + $grid_width;
    my $ring_Y_top_origin    = $ymax;
    my $ring_Y_bottom_origin = $ymax - $grid_height;

    # create grid cells
    foreach my $countcols (1 .. $cols) {
        # reset envelope for rows;
        my $ring_Y_top    = $ring_Y_top_origin;
        my $ring_Y_bottom = $ring_Y_bottom_origin;
        
        foreach my $countrows (1 .. $rows) {
            my $north = $ring_Y_top    - $bt;
            my $south = $ring_Y_bottom + $bt;
            my $west  = $ring_X_left_origin  + $bt;
            my $east  = $ring_X_right_origin - $bt;

            my $poly = 'POLYGON (('
                . "$east $north, "
                . "$west $north, "
                . "$west $south, "
                . "$east $south, "
                . "$east $north"
                . '))';
            #say $poly;
            my $f = Geo::GDAL::FFI::Feature->new($fishnet_lyr->GetDefn);
            $f->SetGeomField([WKT => $poly]);
            $fishnet_lyr->CreateFeature($f);
            # new envelope for next poly
            $ring_Y_top    -= $grid_height;
            $ring_Y_bottom -= $grid_height;
        }
        # new envelope for next poly;
        $ring_X_left_origin  += $grid_width;
        $ring_X_right_origin += $grid_width;
    }

    #$fishnet_lyr->SyncToDisk;  #  try to flush the features
    #$fishnet_lyr = undef;
    #
    #$fishnet_lyr = Geo::GDAL::FFI::Open ("$out_fname/Fishnet_Layer.shp")->GetLayer;
    
    #my $layer_name = $fishnet_lyr->GetName;
    $fishnet_dataset->ExecuteSQL(qq{CREATE SPATIAL INDEX ON "$layer_name"});

    return wantarray ? ($fishnet_dataset, $fishnet_lyr) : $fishnet_lyr;
}

#  get a temporary name 
sub _get_scratch_name {
    my ($self, %args) = @_;

    state $i = 0;
    $i++;

    my $name
      = join '_',
          (($args{prefix} // 'temp'),
          Scalar::Util::refaddr ($self),
          $i,
          int (1000 * rand()),
          ($args{suffix} // '')
        );

    return $name;
}

sub import_data_spreadsheet {
    my $self = shift;
    my %args = @_;

    my $orig_group_count    = $self->get_group_count;
    my $orig_label_count    = $self->get_label_count;
    my $data_in_matrix_form = $args{data_in_matrix_form};
    my $allow_empty_groups  = $args{allow_empty_groups};
    my $allow_empty_labels  = $args{allow_empty_labels};

    my $progress_bar = Biodiverse::Progress->new();

    croak "Input files array not provided\n"
      if !$args{input_files} || (!is_arrayref($args{input_files}));

    my $skip_lines_with_undef_groups =
      exists $args{skip_lines_with_undef_groups}
      ? $args{skip_lines_with_undef_groups}
      : 1;

    my @group_field_names =
      @{ $args{group_fields} // $args{group_field_names} };
    my @label_field_names = @{ $data_in_matrix_form ? [] : $args{label_fields}
          // $args{label_field_names} };
    my @smp_count_field_names = @{ $args{sample_count_col_names} // [] };
    my $is_lat_field          = $args{is_lat_field};
    my $is_lon_field          = $args{is_lon_field};

    my @group_origins = $self->get_cell_origins;
    my @group_sizes   = $self->get_cell_sizes;

    my $labels_ref = $self->get_labels_ref;
    my $groups_ref = $self->get_groups_ref;

    say '[BASEDATA] Loading from files as spreadsheet: '
        . join (q{, },
            map {(is_ref ($_) && !blessed ($_)) ? '<<preloaded book>>' : $_}
            map {$_ // 'undef'}
            @{$args{input_files}}
        );

    # needed to construct the groups and labels
    my $quotes  = $self->get_param('QUOTES');      #  for storage, not import
    my $el_sep  = $self->get_param('JOIN_CHAR');
    my $out_csv = $self->get_csv_object(
        sep_char   => $el_sep,
        quote_char => $quotes,
    );
    my %args_for_add_elements_collated = (
        csv_object         => $out_csv,
        binarise_counts    => $args{binarise_counts},
        allow_empty_groups => $args{allow_empty_groups},
        allow_empty_labels => $args{allow_empty_labels},
    );

    my @label_axes       = $self->get_labels_ref->get_cell_sizes;
    my $label_axis_count = scalar @label_axes;

    #  could use a hash, but this allows open books to be passed
    my @sheet_array = @{ $args{sheet_ids} // [] };

    # load each file, using same arguments/parameters
    my $file_i = -1;
    foreach my $book ( @{ $args{input_files} } ) {
        $file_i++;

        croak "[BASEDATA] Undefined input_file array item "
            . "passed to import_data_spreadsheet\n"
          if !defined $book;    # assuming undef on fail

        if ( blessed $book || !ref $book ) {    #  we have a file name
            my $file = Path::Class::file($book)->absolute;
            say "[BASEDATA] INPUT FILE: $file";
            
            $book = $self->get_book_struct_from_spreadsheet_file (
                file_name => $file,
            );
        }

        my $sheet_id = $sheet_array[$file_i] // 1;
        if ( !looks_like_number $sheet_id) {    #  must be a named sheet
            $sheet_id = $book->[0]{sheet}{$sheet_id};
        }

        my @rows   = Spreadsheet::Read::rows( $book->[$sheet_id] );
        my $header = shift @rows;

        #  some validation (and get the col numbers)
        my $i = -1;
        my %db_rec1 = map { ($_ // '') => ++$i } @$header;
        foreach my $key (@label_field_names) {
            croak "Spreadsheet does not have a field "
                . "called $key in book $sheet_id\n"
              if !exists $db_rec1{$key};
        }
        foreach my $key (@group_field_names) {
            croak "Spreadsheet does not have a field "
                . "called $key in book $sheet_id\n"
              if !exists $db_rec1{$key};
        }

        #  parse the header line if we are using a matrix format file
        my $matrix_label_col_hash = {};
        if ($data_in_matrix_form) {
            my $label_start_col = $args{label_start_col};
            my $label_end_col   = $args{label_end_col};

            #  if we've been passed an array then
            #  use the first one for the start and the last for the end
            #  - this can happen due to the way GUI::BasedataImport
            #  handles options and is something we need to clean
            #  up with better metadata
            if ( ref $label_start_col ) {
                $label_start_col = $label_start_col->[0];
            }
            if ( ref $label_end_col ) {
                $label_end_col = $label_end_col->[-1];
            }
            $matrix_label_col_hash = $self->get_label_columns_for_matrix_import(
                csv_object      => $out_csv,
                label_array     => $header,
                label_start_col => $label_start_col,
                label_end_col   => $label_end_col,

                #%line_parse_args,
            );
        }

        my %gp_lb_hash;

        my $count     = 0;
        my $row_count = scalar @rows;

        # iterate over rows
      ROW:
        foreach my $row (@rows) {
            $count++;

            #  inefficient - we should get the row numbers and slice on them
            my %db_rec;
            @db_rec{@$header} = @$row;

            # form group text from group fields
            # (defined as csv string of central points of group)
            # Needs to process the data in the same way
            # as for text imports - refactoring is in order.
            my @group_field_vals = @db_rec{@group_field_names};
            my @gp_fields;
            my $i = -1;
            foreach my $val (@group_field_vals) {
                $i++;
                if ( !defined $val) {
                    next ROW if $skip_lines_with_undef_groups;
                    croak "record $count has an undefined coordinate\n";
                }

                my $origin = $group_origins[$i];
                my $g_size = $group_sizes[$i];

                if ( $g_size >= 0 ) {
                    next ROW if (!(length $val) || $val eq 'NA') && $skip_lines_with_undef_groups;
                    if (   $is_lat_field
                        && $is_lat_field->{ $group_field_names[$i] } )
                    {
                        $val = dms2dd( { value => $val, is_lat => 1 } );
                    }
                    elsif ($is_lon_field
                        && $is_lon_field->{ $group_field_names[$i] } )
                    {
                        $val = dms2dd( { value => $val, is_lon => 1 } );
                    }

                    croak "$val is not numeric\n"
                      if !looks_like_number $val;

                    if ( $g_size > 0 ) {
                        my $cell = floor( ( $val - $origin ) / $g_size );
                        my $grp_centre =
                          $origin + $cell * $g_size + ( $g_size / 2 );
                        push @gp_fields, $grp_centre;
                    }
                    else {
                        push @gp_fields, $val;
                    }
                }
                else {
                    push @gp_fields, $val;
                }
            }
            my $grpstring = $self->list2csv(
                list       => \@gp_fields,
                csv_object => $out_csv,
            );

   #print "adding point label $this_label group $grpstring count $this_count\n";

            my %elements;
            if ($data_in_matrix_form) {
                %elements = $self->get_labels_from_line_matrix(
                    fields_ref => $row,
                    csv_object => $out_csv,

                    #line_num        => $line_num,
                    #file            => $file,
                    label_col_hash => $matrix_label_col_hash,

                    #%line_parse_args,
                );
            }
            else {
                my $this_count =
                  scalar @smp_count_field_names
                  ? sum 0, @db_rec{@smp_count_field_names}
                  : 1;
                my @lb_fields  = @db_rec{@label_field_names};
                my $this_label = $self->list2csv(
                    list       => \@lb_fields,
                    csv_object => $out_csv
                );
                %elements = ( $this_label => $this_count );

                #%elements =
                #    $self->get_labels_from_line (
                #        fields_ref      => $fields_ref,
                #        csv_object      => $out_csv,
                #        line_num        => $line_num,
                #        file            => $file,
                #        #%line_parse_args,
                #    );
            }

          ADD_ELEMENTS:
            while ( my ( $el, $count ) = each %elements ) {
                if ( defined $count ) {
                    next ADD_ELEMENTS if $count eq 'NA';

                    next ADD_ELEMENTS
                      if $data_in_matrix_form
                      && $count eq $EMPTY_STRING;

                    next ADD_ELEMENTS
                      if !$count and !$allow_empty_groups;
                }
                else {    #  don't allow undef counts in matrices
                    next ADD_ELEMENTS
                      if $data_in_matrix_form;
                }

        #  single label col or matrix form data need extra quotes to be stripped
        #  should clean up mx form on first pass
        #  or do as a post-processing step
                if ( $label_axis_count <= 1 || $data_in_matrix_form ) {
                    $el = $self->dequote_element(
                        element    => $el,
                        quote_char => $quotes,
                    );
                }

                #  collate them so we can add them in a batch later
                if ( looks_like_number $count) {
                    $gp_lb_hash{$grpstring}{$el} += $count;
                }
                else {
                    #  don't override existing counts with undef
                    $gp_lb_hash{$grpstring}{$el} //= $count;
                }
            }

            # progress bar stuff
            my $frac = $count / $row_count;
            $progress_bar->update(
                "Loading spreadsheet\n" . "Row $count of $row_count\n", $frac );

        }    # each row

        #  add the collated data
        $self->add_elements_collated(
            data => \%gp_lb_hash,
            %args_for_add_elements_collated,
        );
        %gp_lb_hash = ();    #  clear the collated list

        $progress_bar->update( 'Done', 1 );
    }    # each file

    $self->run_import_post_processes(
        %args,
        label_axis_count => scalar @label_field_names,
        orig_group_count => $orig_group_count,
        orig_label_count => $orig_label_count,
    );

    return 1;    #  success
}

sub run_import_post_processes {
    my $self = shift;
    my %args = @_;

    my $orig_group_count = $args{orig_group_count};
    my $orig_label_count = $args{orig_label_count};

    my $groups_ref = $self->get_groups_ref;
    my $labels_ref = $self->get_labels_ref;

    #  how many label axes do we have?
    #  Assume 1 axis if no labels have yet been set.
    my $labels      = $self->get_labels;
    my $first_label = $labels->[0] // '';
    my $lb_csv_obj  = $labels_ref->get_csv_object(
        quote_char => $labels_ref->get_param('QUOTES'),
        sep_char   => $labels_ref->get_param('JOIN_CHAR'),
    );
    my @components = $self->csv2list(
        string     => $first_label,
        csv_object => $lb_csv_obj,
    );
    my $label_axis_count = scalar @components;

    #  set whatever label properties are in the table
    if ( $args{use_label_properties} ) {
        $self->assign_element_properties(
            type              => 'labels',
            properties_object => $args{label_properties},
        );
    }

    #  add the group properties
    if ( $args{use_group_properties} ) {
        $self->assign_element_properties(
            type              => 'groups',
            properties_object => $args{group_properties},
        );
    }

    # Set CELL_SIZE on the GROUPS BaseStruct
    $groups_ref->set_param( CELL_SIZES => [ $self->get_cell_sizes ] );

    #  check if the labels are numeric (or still numeric)
    #  set flags and cell sizes accordingly
    if ( $self->get_param('NUMERIC_LABELS') // 1 ) {
        my $is_numeric = $labels_ref->elements_are_numeric || 0;
        $self->set_param( NUMERIC_LABELS => ($is_numeric) );
    }

    #  set the labels cell size in case we are transposed at some point
    my $label_cellsize = $labels_ref->element_arrays_are_numeric ? 0 : -1;
    my @label_cell_sizes = ($label_cellsize) x $label_axis_count;
    $labels_ref->set_param( CELL_SIZES => \@label_cell_sizes );

    #  clear some params (should these be cached?)
    $groups_ref->delete_param('RTREE');
    $labels_ref->delete_param('SAMPLE_COUNTS_ARE_FLOATS');
    $groups_ref->delete_param('SAMPLE_COUNTS_ARE_FLOATS');

    if ( $orig_label_count != $self->get_label_count ) {
        #$labels_ref->generate_element_coords;
        #  defer recalculation until needed (saves some time)
        $labels_ref->delete_param('AXIS_LIST_ORDER');
    }

    if ( $orig_group_count != $self->get_group_count ) {
        $groups_ref->generate_element_coords;

        if ( $self->get_param('SPATIAL_INDEX') ) {
            $self->rebuild_spatial_index();
        }
    }

    return 1;
}


sub get_labels_from_line {
    my $self = shift;
    my %args = @_;

    #  these assignments look redundant, but this makes for cleaner code
    my $fields_ref           = $args{fields_ref};
    my $csv_object           = $args{csv_object};
    my $label_columns        = $args{label_columns};
    my $sample_count_columns = $args{sample_count_columns};
    my $label_properties     = $args{label_properties};
    my $use_label_properties = $args{use_label_properties};
    my $line_num             = $args{line_num};
    my $file                 = $args{file};

 #  return a set of results that are the label and its corresponding count value
    my %elements;

    #  get the label for this row  using a slice
    my @tmp   = @$fields_ref[@$label_columns];
    my $label = $self->list2csv(
        list       => \@tmp,
        csv_object => $csv_object,
    );

    #  get the sample count
    my $sample_count;
    foreach my $column (@$sample_count_columns) {
        my $col_value = $fields_ref->[$column] // 0;

#  need this check now?  Not sure it worked properly anyway, as it could return early
        if ( $args{allow_empty_groups} or $args{allow_empty_labels} ) {
            return if not defined $col_value;    #  only skip undefined records
        }

        if ( !looks_like_number($col_value) )
        {    #  check the record if we get this far
            croak "[BASEDATA] Field $column in line $line_num "
              . "does not look like a number, File $file\n";
        }
        $sample_count += $col_value;
    }

    #  set default count - should only get valid records if we get this far
    $sample_count //= 1;

    #$elements{$label} = $sample_count if $sample_count;
    $elements{$label} = $sample_count;

    return wantarray ? %elements : \%elements;
}

#  parse a line from a matrix format file and return all the elements in it
sub get_labels_from_line_matrix {
    my $self = shift;
    my %args = @_;

    #return;  #  temporary drop out

    #  these assignments look redundant, but this makes for cleaner code and
    #  the compiler should optimise it all away
    my $fields_ref           = $args{fields_ref};
    my $csv_object           = $args{csv_object};
    my $label_array          = $args{label_array};
    my $label_properties     = $args{label_properties};
    my $use_label_properties = $args{use_label_properties};
    my $line_num             = $args{line_num};
    my $file                 = $args{file};
    my $label_col_hash       = $args{label_col_hash};

#  All we need to do is get a hash of the labels with their relevant column values
#  Any processing of null or zero fields is handled by calling subs
#  All label remapping has already been handled by get_label_columns_for_matrix_import (assuming it is not renamed)
#  Could possibly check for zero count values, but that adds another loop which might slow things too much,
#       even if using List::MoreUtils and its XS implementation

    my %elements;
    @elements{ keys %$label_col_hash } =
      @$fields_ref[ values %$label_col_hash ];

    return wantarray ? %elements : \%elements;
}

#  process the header line and sort out which columns we want, and remap any if needed
sub get_label_columns_for_matrix_import {
    my $self = shift;
    my %args = @_;

    my $csv_object           = $args{csv_object};
    my $label_array          = $args{label_array};
    my $label_properties     = $args{label_properties};
    my $use_label_properties = $args{use_label_properties};

    my $label_start_col = $args{label_start_col};
    my $label_end_col = $args{label_end_col} // $#$label_array;

    my %label_hash;
  LABEL_COLS:
    for my $i ( $label_start_col .. $label_end_col ) {

        #  get the label for this row from the header
        my @tmp   = $label_array->[$i];
        my $label = $self->list2csv(
            list       => \@tmp,
            csv_object => $csv_object,
        );

        $label_hash{$label} = $i;
    }

#  this will be a label/column hash which we can use to slice data from the matrix row arrays
    return wantarray ? %label_hash : \%label_hash;
}


1;
