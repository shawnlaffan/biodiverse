package Biodiverse::BaseStruct;

#  Package to provide generic methods for the
#  GROUPS and LABELS sub components of a Biodiverse object,
#  and also for the SPATIAL ones

#  Need a mergeElements method

use strict;
use warnings;
use Carp;
use 5.010;

use English ( -no_match_vars );

use autovivification;

#use Data::DumpXML qw{dump_xml};
use Data::Dumper;
use Scalar::Util qw /looks_like_number/;
use List::Util qw /min max sum/;
use List::MoreUtils qw /first_index/;
use File::Basename;
use Path::Class;
use POSIX qw /fmod floor/;
use Time::localtime;
use Geo::Shapefile::Writer;
use Ref::Util qw { :all };

our $VERSION = '1.99_006';

my $EMPTY_STRING = q{};

use parent qw /Biodiverse::Common/; #  access the common functions as methods

use Biodiverse::Statistics;
my $stats_class = 'Biodiverse::Statistics';

my $metadata_class = 'Biodiverse::Metadata::BaseStruct';
use Biodiverse::Metadata::BaseStruct;

use Biodiverse::Metadata::Export;
my $export_metadata_class = 'Biodiverse::Metadata::Export';

use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';

sub new {
    my $class = shift;

    my $self = bless {}, $class;

    my %args = @_;

    # do we have a file to load from?
    my $file_loaded;
    if ( defined $args{file} ) {
        $self->load_file( @_ );
    };
    return $file_loaded if defined $file_loaded;

    #  default parameters to load.  These will be overwritten if needed.
    my %params = (  
        OUTPFX              =>  'BIODIVERSE_BASESTRUCT',
        OUTSUFFIX           => 'bss',
        #OUTSUFFIX_XML      => "bsx",
        OUTSUFFIX_YAML      => 'bsy',
        TYPE                => undef,
        OUTPUT_QUOTE_CHAR   => q{"},
        OUTPUT_SEP_CHAR     => q{,},   #  used for output data strings
        QUOTES              => q{'},
        JOIN_CHAR           => q{:},   #  used for labels and groups
        #INDEX_CONTAINS     => 4,  #  average number of basestruct elements per index element
        PARAM_CHANGE_WARN   => undef,
    );

    #  load the defaults, with the rest of the args as params
    my @args_for = (%params, @_);
    $self->set_params (@args_for);

    # predeclare the ELEMENT subhash (don't strictly need to do it...)
    $self->{ELEMENTS} = {};  

    #  avoid memory leak probs with circular refs
    $self->weaken_basedata_ref;

    return $self;
}

sub metadata_class {
    return $metadata_class;
}

sub rename {
    my $self = shift;
    my %args = @_;

    my $name = $args{new_name};
    if (not defined $name) {
        croak "[Basestruct] Argument 'new_name' not defined\n";
    }

    $self->set_param (NAME => $name);

    return;
}

sub get_axis_count {
    my $self = shift;

    my $elements = $self->get_element_list;
    my $el       = $elements->[0];
    my $axes     = $self->get_element_name_as_array (element => $el);

    return scalar @$axes;
}

sub get_reordered_element_names {
    my $self = shift;
    my %args = @_;

    my %reordered;

    my $axis_count = $self->get_axis_count;

    return wantarray ? %reordered : \%reordered
      if $axis_count == 1;

    my $csv_object = $args{csv_object};

    my @reorder_cols = @{$args{reordered_axes}};
    my $reorder_count = scalar @reorder_cols;
    croak "Attempting to reorder more axes ($reorder_count) "
        . "than are in the basestruct ($axis_count)\n"
      if scalar $reorder_count > $axis_count;

    my $i = 0;
    foreach my $col (@reorder_cols) {
        if (not defined $col) {  #  undef cols stay where they are
            $col = $i;
        }
        elsif ($col < 0) {  #  make negative subscripts positive for next check step
            $col += $axis_count;
        }
        $i++;
    }

    #  is the new order out of bounds?
    my $max_subscript = $axis_count - 1;
    my $min = List::Util::min(@reorder_cols);
    my $max = List::Util::max(@reorder_cols);
    croak "reordered axes are out of bounds ([$min..$max] does not match [0..$max_subscript])\n"
      if $min != 0 || $max != $max_subscript;  # out of bounds

    #  if we don't have all values assigned then we have issues
    my %tmp;
    @tmp{@reorder_cols} = undef;
    croak "incorrect or clashing axes\n"
      if scalar keys %tmp != scalar @reorder_cols;

    my $quote_char = $self->get_param('QUOTES');
    foreach my $element ($self->get_element_list) {
        my $el_array = $self->get_element_name_as_array (element => $element);
        my @new_el_array = @$el_array[@reorder_cols];

        my $new_element = $self->list2csv (
            list       => \@new_el_array,
            csv_object => $csv_object,
        );
        $self->dequote_element(element => $new_element, quote_char => $quote_char);

        $reordered{$element} = $new_element;
    }

    return wantarray ? %reordered : \%reordered;
}

#  metadata is bigger than the actual sub...
sub get_metadata_export {
    my $self = shift;

    #  get the available lists
    #my @lists = $self->get_lists_for_export;

    #  need a list of export subs
    my %subs = $self->get_subs_with_prefix (prefix => 'export_');

    my @formats;
    my %format_labels;  #  track sub names by format label

    #  loop through subs and get their metadata
    my %params_per_sub;

    LOOP_EXPORT_SUB:
    foreach my $sub (sort keys %subs) {
        my %sub_args = $self->get_args (sub => $sub);

        my $format = $sub_args{format};

        croak "Metadata item 'format' missing\n"
            if not defined $format;

        $format_labels{$format} = $sub;

        next LOOP_EXPORT_SUB
            if $sub_args{format} eq $EMPTY_STRING;

        $params_per_sub{$format} = $sub_args{parameters};

        my $params_array = $sub_args{parameters};

        push @formats, $format;
    }

    @formats = sort @formats;
    $self->move_to_front_of_list (
        list => \@formats,
        item => 'Delimited text'
    );
    
    my $format_choice = bless
        {
            name        => 'format',
            label_text  => 'Format to use',
            type        => 'choice',
            choices     => \@formats,
            default     => 0
        },
        $parameter_metadata_class;

    my %metadata = (
        parameters     => \%params_per_sub,
        format_choices => [$format_choice],
        format_labels  => \%format_labels,
    ); 

    return $export_metadata_class->new (\%metadata);
}

# export to a file
sub export {
    my $self = shift;
    my %args = @_;

    #  get our own metadata...  Much of the following can be shifted into the export metadata package
    my $metadata   = $self->get_metadata (sub => 'export');
    my $sub_to_use = $metadata->get_sub_name_from_format (%args);

    #  convert no_data_values if appropriate
    if (defined $args{no_data_value}) {
        if ($args{no_data_value} eq 'undef') {
            $args{no_data_value} = undef;
        }
        elsif ($args{no_data_value} =~ /^([-+]?)(\d+)\*\*(\d+)$/) {  #  e.g. -2**128
            my $val = $2 ** $3;
            if ($1 eq '-') {
                $val *= -1;
            };
            $args{no_data_value} = $val;
        }
    }

    eval {$self->$sub_to_use (%args)};
    croak $EVAL_ERROR if $EVAL_ERROR;

    return;
}

sub get_common_export_metadata {
    my $self = shift;

    #  get the available lists
    my @lists = $self->get_lists_for_export;

    my $default_idx = 0;
    if (my $last_used_list = $self->get_cached_value('LAST_SELECTED_LIST')) {
        $default_idx = first_index {$last_used_list eq $_} @lists;
    }

    # look for a default value for def query
    my $def_query_default = "";
    if($self->get_def_query()) {
        $def_query_default = $self->get_def_query()->get_conditions();
        $def_query_default =~ s/\n//g;
    }
    #say "Default def_query value is: .$def_query_default.";

    my $metadata = [
        {
            name => 'file',
            type => 'file'
        }, # GUI supports just one of these
        {
            name        => 'list',
            label_text  => 'List to export',
            type        => 'choice',
            choices     => \@lists,
            default     => $default_idx,
        },
        {
            name        => 'def_query',
            label_text  => 'Def query',
            type        => 'spatial_conditions',
            default     => $def_query_default,
            tooltip     => 'Only elements which pass this def query ' .
                           'will be exported.',
        },
    ];
    foreach (@$metadata) {
        bless $_, $parameter_metadata_class;
    }

    return wantarray ? @$metadata : $metadata;
}

sub get_table_export_metadata {
    my $self = shift;

    my @no_data_values = $self->get_nodata_values;
    my @sep_chars
        = defined $ENV{BIODIVERSE_FIELD_SEPARATORS}
            ? @$ENV{BIODIVERSE_FIELD_SEPARATORS}
            : (',', 'tab', ';', 'space', ':');

    my @quote_chars = qw /" ' + $/; #"
    my $el_quote_char = $self->get_param('QUOTES');

    my $mx_explanation = $self->get_tooltip_sparse_normal;

    my $table_metadata_defaults = [
        {
            name       => 'symmetric',
            label_text => 'Force symmetric (matrix) format',
            tooltip    => "Rectangular matrix, one row per element (group).\n"
                        . $mx_explanation,
            type       => 'boolean',
            default    => 1,
        },
        {
            name       => 'one_value_per_line',
            label_text => "One value per line",
            tooltip    => "Sparse matrix, repeats elements for each value.\n"
                        . $mx_explanation,
            type       => 'boolean',
            default    => 0,
        },
        {
            name       => 'sep_char',
            label_text => 'Field separator',
            tooltip    => 'Suggested options are comma for .csv files, tab for .txt files',
            type       => 'choice',
            choices    => \@sep_chars,
            default    => 0,
        },
        {
            name       => 'quote_char',
            label_text => 'Quote character',
            tooltip    => 'For delimited text exports only',
            type       => 'choice',
            choices    => \@quote_chars,
            default    => 0,
        },
        {
            name       => 'no_data_value',
            label_text => 'NoData value',
            tooltip    => 'Zero is not a safe value to use for nodata in most '
                        . 'cases, so be warned',
            type       => 'choice',
            choices    => \@no_data_values,
            default    => 0,
        },
        {
            name       => 'quote_element_names_and_headers',
            label_text => 'Quote element names and headers',
            tooltip    => 'Should the element names (labels and groups) and column headers be quoted?  '
                        . 'MS Excel otherwise misinterprets characters such as colons in the names '
                        . 'as a range operator or time variable, wrecking the data on import.'
                        . "\nThis uses the internal quote character, which is $el_quote_char.",
            type       => 'boolean',
            default    => 0,
        },
    ];
    for (@$table_metadata_defaults) {
        bless $_, $parameter_metadata_class;
    }

    return wantarray ? @$table_metadata_defaults : $table_metadata_defaults;
}

sub get_metadata_export_table_delimited_text {
    my $self = shift;

    my @parameters = (
        $self->get_common_export_metadata(),
        $self->get_table_export_metadata(),
    );
    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    my %args = (
        format => 'Delimited text',
        parameters => \@parameters,
    ); 

    return wantarray ? %args : \%args;
}

#  generic - should be factored out to Biodiverse::Common?
sub export_table_delimited_text {
    my $self = shift;
    my %args = @_;

    my $filename = $args{file} || croak "file arg not specified\n";
    my $fh;
    if (!$args{_no_fh}) {  #  allow control of $fh for test purposes
        open $fh, '>', $filename or croak "Could not open $filename\n";
    }

    my $table = $self->to_table (symmetric => 1, %args, file_handle => $fh);

    if (scalar @$table) {  #  won't need this once issue #350 is fixed
        $self->write_table_csv (%args, data => $table);
    }

    return;
}

sub get_metadata_export_table_html {
    my $self = shift;

    my %args = (
        format => 'HTML table',
        parameters => [
            $self->get_common_export_metadata(),
            $self->get_table_export_metadata()
        ],
    ); 

    return wantarray ? %args : \%args;
}

sub export_table_html {
    my $self = shift;
    my %args = @_;

    my $table = $self->to_table (symmetric => 1, %args);

    $self->write_table_html (%args, data => $table);

    return;
}

sub get_metadata_export_table_xml {
    my $self = shift;

    my %args = (
        format => 'XML table',
        parameters => [
            $self->get_common_export_metadata(),
            $self->get_table_export_metadata()
        ],
    ); 

    return wantarray ? %args : \%args;
}

sub export_table_xml {
    my $self = shift;
    my %args = @_;

    my $table = $self->to_table (symmetric => 1, %args);

    $self->write_table_xml (%args, data => $table);

    return;
}

sub get_metadata_export_table_yaml {
    my $self = shift;

    my %args = (
        format => 'YAML table',
        parameters => [
            $self->get_common_export_metadata(),
            $self->get_table_export_metadata()
        ],
    ); 

    return wantarray ? %args : \%args;    
}

sub export_table_yaml {
    my $self = shift;
    my %args = @_;

    my $table = $self->to_table (symmetric => 1, %args);

    $self->write_table_yaml (%args, data => $table);

    return;
}

sub get_metadata_export_table_json {
    my $self = shift;

    my %args = (
        format => 'JSON table',
        parameters => [
            $self->get_common_export_metadata(),
            $self->get_table_export_metadata()
        ],
    ); 

    return wantarray ? %args : \%args;    
}

sub export_table_json {
    my $self = shift;
    my %args = @_;

    my $table = $self->to_table (symmetric => 1, %args);

    $self->write_table_json (%args, data => $table);

    return;
}

sub get_nodata_values {
    my @vals = qw /undef 0 -9 -9999 -99999 -2**31 -2**128 NA/; #/
    return wantarray ? @vals : \@vals;
}

sub get_nodata_export_metadata {
    my $self = shift;

    my @no_data_values = $self->get_nodata_values;

    my $metadata = [ 
        {
            name        => 'no_data_value',
            label_text  => 'NoData value',
            tooltip     => 'Zero is not a safe value to use for nodata in most '
                         . 'cases, so be warned',
            type        => 'choice',
            choices     => \@no_data_values,
            default     => 0
        },   
    ];
    foreach (@$metadata) {
        bless $_, $parameter_metadata_class;
    }

    return wantarray ? @$metadata : $metadata;
}


sub get_raster_export_metadata {
    my $self = shift;

    return $self->get_nodata_export_metadata;
}

sub get_metadata_export_ers {
    my $self = shift;

    my %args = (
        format => 'ER-Mapper BIL file',
        parameters => [
            $self->get_common_export_metadata(),
            $self->get_raster_export_metadata(),
        ],
    ); 

    return wantarray ? %args : \%args;
}

sub export_ers {
    my $self = shift;
    my %args = @_;

    my $table = $self->to_table (%args, symmetric => 1);

    $self->write_table_ers (%args, data => $table);

    return;
}

sub get_metadata_export_asciigrid {
    my $self = shift;

    my %args = (
        format => 'ArcInfo asciigrid files',
        parameters => [
            $self->get_common_export_metadata(),
            $self->get_raster_export_metadata(),
        ],
    ); 

    return wantarray ? %args : \%args;
}

sub export_asciigrid {
    my $self = shift;
    my %args = @_;

    my $table = $self->to_table (%args, symmetric => 1);

    $self->write_table_asciigrid (%args, data => $table);

    return;
}

sub get_metadata_export_floatgrid {
    my $self = shift;

    my %args = (
        format => 'ArcInfo floatgrid files',
        parameters => [
            $self->get_common_export_metadata(),
            $self->get_raster_export_metadata(),
        ],
    ); 

    return wantarray ? %args : \%args;
}

sub export_floatgrid {
    my $self = shift;
    my %args = @_;

    my $table = $self->to_table (%args, symmetric => 1);

    $self->write_table_floatgrid (%args, data => $table);

    return;
}


sub get_metadata_export_geotiff {
    my $self = shift;

    my %args = (
        format => 'GeoTIFF',
        parameters => [
            $self->get_common_export_metadata(),
            $self->get_raster_export_metadata(),
        ],
    ); 

    return wantarray ? %args : \%args;
}

sub export_geotiff {
    my $self = shift;
    my %args = @_;

    my $table = $self->to_table (%args, symmetric => 1);

    $self->write_table_geotiff (%args, data => $table);

    return;
}

sub get_metadata_export_divagis {
    my $self = shift;

    my %args = (
        format => 'DIVA-GIS raster files',
        parameters => [
            $self->get_common_export_metadata(),
            $self->get_raster_export_metadata(),
        ],
    ); 

    return wantarray ? %args : \%args;
}

sub export_divagis {
    my $self = shift;
    my %args = @_;

    my $table = $self->to_table (%args, symmetric => 1);

    $self->write_table_divagis (%args, data => $table);

    return;
}

my $shape_export_comment_text = <<'END_OF_SHAPE_COMMENT'
Note: If you export a list then each shape (point or polygon) 
will be repeated for each list item.

Choose the __no_list__ option to not do this,
in which case to attach any lists you will need to run a second 
export to the delimited text format and then join them.  
This is needed because shapefile field names can only be
11 characters long and cannot contain non-alphanumeric characters.

Note also that shapefiles do not have an undefined value 
so any undefined values will be converted to zeroes.

Export of array lists to shapefiles is not supported. 
END_OF_SHAPE_COMMENT
  ;

sub get_metadata_export_shapefile {
    my $self = shift;
    #  get the available lists
    my @lists = $self->get_lists_for_export (no_array_lists => 1);
    unshift @lists, '__no_list__';

    #  nodata won't have much effect until we make the outputs symmetric
    my @nodata_meta = $self->get_nodata_export_metadata;

    # look for a default value for def query
    my $def_query_default = "";
    if($self->get_def_query()) {
        $def_query_default = $self->get_def_query()->get_conditions();
        $def_query_default =~ s/\n//g;
    }

    
    my @parameters = (
        {  # GUI supports just one of these
            name => 'file',
            type => 'file'
        },
        {
            name        => 'list',
            label_text  => 'List to export',
            type        => 'choice',
            choices     => \@lists,
            default     => 0,
        },
        {
            name        => 'shapetype',
            label_text  => 'Shape type',
            type        => 'choice',
            choices     => [qw /POLYGON POINT/],
            default     => 0,
        },
        @nodata_meta,
        {
            name        => 'def_query',
            label_text  => 'Def query',
            type        => 'spatial_conditions',
            default     => $def_query_default,
            tooltip     => 'Only elements which pass this def query ' .
                'will be exported.',
        },
        {
            type        => 'comment',
            label_text  => $shape_export_comment_text,
        },
    );
    foreach (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    my %args = (
        format     => 'Shapefile',
        parameters => \@parameters,
    );
    
    return wantarray ? %args : \%args;
}

sub export_shapefile {
    my $self = shift;
    my %args = (nodata_value => -2**128, @_);

    $args{file} =~ s/\.shp$//i;
    my $file    = $args{file};

    my $list_name = $args{list};
    if (defined $list_name && $list_name eq '__no_list__') {
        $list_name = undef;
    }

    my $nodata = $args{nodata_value};
    if (!looks_like_number $nodata) {
        $nodata = -1 * 2**128;
    }

    # we are writing as 2D or 3D points or polygons,
    # only Point, PointZ or Polygon are used
    my $shape_type = uc ($args{shapetype} // 'POLYGON');
    croak "Invalid shapetype for shapefile export\n"
      if $shape_type ne 'POINT' and $shape_type ne 'POLYGON';

    say "Exporting to shapefile $file";

    my $def_query = $args{def_query};
    
    my @elements;
    if ($def_query) {
        @elements = $self->get_elements_that_pass_def_query(defq => $def_query);
        my $length = scalar @elements;
        if( $length == 0) {
            say "[BaseStruct] No elements passed the def query!";
            @elements = $self->get_element_list;
            $args{def_query} = '';
        }
    }
    else {
        @elements = $self->get_element_list;
    }

    

    my @cell_sizes  = $self->get_cell_sizes;  #  get a copy
    my @axes_to_use = (0, 1);
    if ($shape_type eq 'POINT' && scalar @cell_sizes > 2) {
        @axes_to_use = (0, 1, 2);  #  we use Z in this case
    }

    my $half_csizes = [];
    foreach my $size (@cell_sizes[@axes_to_use]) {
        # disabled checking for sizes, specify shapetype='point' instead
        #return $self->_export_shape_point (%args)
        #  if $size == 0;  #  we are a point file

        my $half_size = $size > 0 ? $size / 2 : 0.5;

        push @$half_csizes, $half_size;
    }

    my $first_el_coord = $self->get_element_name_coord (element => $elements[0]);

    my @axis_col_specs;
    foreach my $axis (0 .. $#$first_el_coord) {
        my $csize = $cell_sizes[$axis];
        if ($csize < 0) {
            #  should check actual sizes
            push @axis_col_specs, [ ('axis_' . $axis) => 'C', 100];
        }
        else {
            #  width and decimals needs automation
            push @axis_col_specs, [ ('axis_' . $axis) => 'F', 16, 3 ];
        }
    }


# code for multiple labels per shape
# 
#    # find all labels.  only possible by examining all the groups,
#    # unless labels are passed as a parameter
#    my %label_hash;
#    foreach my $element (@elements) {
#        my %label_counts = $self->get_sub_element_hash (
#            element => $element
#        );
#        @label_hash{keys %label_counts} = values %label_counts;
#    }
#    my @label_count_specs;
#    my $l_idx = 0;
#    foreach my $this_label (keys %label_hash) {
#        $l_idx++;
#        push @label_count_specs, [ "label_${l_idx}" => 'C', 100];
#        push @label_count_specs, [ "count_${l_idx}" => 'N', 8, 0];
#    }

    my @label_count_specs;
    if (defined $list_name) {  # repeated polys per list item
        push @label_count_specs, (
            [ key   => 'C', 100  ],
            [ value => 'F', 16, 3 ],
        );
    }

    my $shp_writer = Geo::Shapefile::Writer->new (
        $file, $shape_type,
        [ element => 'C', 100 ],
        @axis_col_specs,
        @label_count_specs,
    );

  NODE:
    foreach my $element (@elements) {
        my $coord_axes = $self->get_element_name_coord (element => $element);
        my $name_axes  = $self->get_element_name_as_array (element => $element);

        my %axis_col_data;
        foreach my $axis (0 .. $#$first_el_coord) {
            $axis_col_data{'axis_' . $axis} = $name_axes->[$axis];
        }

        my $shape;
        if ($shape_type eq 'POLYGON')  { 
            my $min_x = $coord_axes->[$axes_to_use[0]] - $half_csizes->[$axes_to_use[0]];
            my $max_x = $coord_axes->[$axes_to_use[0]] + $half_csizes->[$axes_to_use[0]];
            my $min_y = $coord_axes->[$axes_to_use[1]] - $half_csizes->[$axes_to_use[1]];
            my $max_y = $coord_axes->[$axes_to_use[1]] + $half_csizes->[$axes_to_use[1]];

            $shape = [[
                [$min_x, $min_y],
                [$min_x, $max_y],
                [$max_x, $max_y],
                [$max_x, $min_y],
                [$min_x, $min_y],  #  close off
            ]];
        }
        elsif ($shape_type eq 'POINT') { 
            $shape = [
                $coord_axes->[$axes_to_use[0]],
                $coord_axes->[$axes_to_use[1]],
            ];
        }

# merging duplicated code, not clear about differences yet
#        # get labels and counts in this cell
#        my %label_counts = $self->get_sub_element_hash (
#            element => $element
#        );
        #foreach my $this_label (keys %label_counts) {
        #    #say "$this_label count $label_counts{$this_label}";
        #   { name => $name, type => 'N', length => 8,  decimals => 0 } 
        #}
        # write a separate shape for each label
#        foreach my $label (keys %label_counts) {
#            
#            $shp_writer->add_shape(
#                $shape,
#                {
#                    element => $element,
#                    %axis_col_data,
#                    label => $label,
#                    count => $label_counts{$label}
##                    %label_counts
#                },
#            );
#        }



        #  temporary - this needs to be handled differently
        if ($list_name) {
            my %list_data = $self->get_list_values (
                element => $element,
                list    => $list_name,
            );

            # write a separate shape for each label
            foreach my $key (sort keys %list_data) {
                $shp_writer->add_shape(
                    $shape,
                    {
                        element => $element,
                        %axis_col_data,
                        key     => $key,
                        value   => ($list_data{$key} // $nodata),
                    },
                );
            }
        }
        else {
            $shp_writer->add_shape(
                $shape,
                {
                    element => $element,
                    %axis_col_data,
                },
            );
        }
    }

    $shp_writer->finalize();

    return;
}

#sub export_shapefile_point {
#    my $self = shift;
#    my %args = @_;
#    
#    $args{file} =~ s/\.shp$//;
#    my $file = $args{file};
#
#    say "Exporting to point shapefile $file";
#
#    my @elements    = $self->get_element_list;
#    my @cell_sizes  = @{$self->get_param ('CELL_SIZES')};  #  get a copy
#    my @axes_to_use = (0, 1);
#
#    my $first_el_coord = $self->get_element_name_coord (element => $elements[0]);
#
#    my @axis_col_specs;
#    foreach my $axis (0 .. $#$first_el_coord) {
#        #  width and decimals needs automation
#        push @axis_col_specs, [ ('axis_' . $axis) => 'F', 16, 3 ];
#    }
#
#    my $shp_writer = Geo::Shapefile::Writer->new (
#        $file, 'POINT',
#        [ element => 'C', 100 ],
#        @axis_col_specs,
#    );
#
#  NODE:
#    foreach my $element (@elements) {
#        my $coord_axes = $self->get_element_name_coord (element => $element);
#        my $name_axes  = $self->get_element_name_as_array (element => $element);
#
#        my %axis_col_data;
#        foreach my $axis (0 .. $#$first_el_coord) {
#            $axis_col_data{'axis_' . $axis} = $name_axes->[$axis];
#        }
#
#        my $shape = [
#            $coord_axes->[$axes_to_use[0]],
#            $coord_axes->[$axes_to_use[1]]
#        ];
#
#        $shp_writer->add_shape(
#            $shape,
#            {
#                element => $element,
#                %axis_col_data,
#            },
#        );
#    }
#
#    $shp_writer->finalize();
#
#    return;
#}

#sub get_metadata_export_shapefile_point {
#    my $self = shift;
#
#    my %args = (
#        format => 'Shapefile_Point',
#        parameters => [
#            {
#                name => 'file',
#                type => 'file'
#            }, # GUI supports just one of these
#            {
#                type => 'comment',
#                label_text =>
#                      'Note: To attach any lists you will need to run a second '
#                    . 'export to the delimited text format and then join them.  '
#                    . 'This is needed because shapefiles do not have an undefined value '
#                    . 'and field names can only be 11 characters long.',
#            }
#        ],
#    );
#
#    return wantarray ? %args : \%args;
#}



sub get_lists_for_export {
    my $self = shift;
    my %args = @_;

    my $skip_array_lists = $args{no_array_lists};

    #  get the available lists
    my $lists = $self->get_lists_across_elements (no_private => 1);
    my $array_lists = $skip_array_lists
        ? []
        : $self->get_array_lists_across_elements (no_private => 1);

    #  sort appropriately
    my @lists;
    foreach my $list (sort (@$lists, @$array_lists)) {
        next if $list =~ /^_/;

        if ($list eq 'SPATIAL_RESULTS') {
            unshift @lists, $list;  #  put at the front
        }
        else {
            push @lists, $list;  #  put at the end
        }
    }

    return wantarray ? @lists : \@lists;
}

#  handler for the available set of structures.
sub write_table {
    my $self = shift;
    my %args = @_;
    croak "file argument not specified\n"
      if !defined $args{file};
    my $data = $args{data} || croak "data argument not specified\n";
    is_arrayref($data) || croak "data arg must be an array ref\n";

    $args{file} = Path::Class::file($args{file})->absolute;

    return;
}


#  control whether a file is written symetrically or not
sub to_table {
    my $self = shift;
    my %args = @_;
    #  modify to make the default, rather than required
    #my $file = $args{file} || ($self->get_param('OUTPFX') . ".csv");  
    my $as_symmetric = $args{symmetric} || 0;

    croak "[BaseStruct] argument 'list' not specified\n"
      if !defined $args{list}; 

    my $list = $args{list};
    my $check_elements;
    if( $args{def_query} ) {
        $check_elements = 
            $self->get_elements_that_pass_def_query( defq => $args{def_query} );

        my $length = scalar @{ $check_elements };
        if( $length == 0 ) {
            say "[BASESTRUCT] No elements passed the def query!";
            $check_elements = $self->get_element_list;
            $args{def_query} = '';
        }
    }
    else {
        $check_elements = $self->get_element_list;
    }
    
  
    #  Check if the lists in this object are symmetric.  Check the list type as well.
    #  Assumes type is constant across all elements, and that all elements have this list.
    my $last_contents_count = -1;
    my $is_asym = 0;
    my %list_keys;
    my $prev_list_keys;

    say "[BASESTRUCT] Checking elements for list symmetry: $list";
  CHECK_ELEMENTS:
    foreach my $i (0 .. $#$check_elements) {  # sample the lot
        my $check_element = $check_elements->[$i];
        last CHECK_ELEMENTS if ! defined $check_element;

        my $values = $self->get_list_values (
            element => $check_element,
            list    => $list,
        );
        if (is_hashref($values)) {
            if (defined $prev_list_keys and $prev_list_keys != scalar keys %$values) {
                $is_asym ++;  #  This list is of different length from the previous.  Allows for zero length lists.
                last CHECK_ELEMENTS;
            }
            $prev_list_keys //= scalar keys %$values;
            @list_keys{keys %$values} = undef;
        }
        elsif (is_arrayref($values)) {
            $is_asym = 1;  #  arrays are always treated as asymmetric
            last CHECK_ELEMENTS;
        }

        #  Increment if not first check and we have added new keys from previous run.
        #  Allows for lists of same length but with different keys.
        if ($i && $last_contents_count != scalar keys %list_keys) {
            $is_asym ++ ;
            last CHECK_ELEMENTS if $is_asym;
        }

        $last_contents_count = scalar keys %list_keys;
    }

    my $data;

    if (! $as_symmetric and $is_asym) {
        say "[BASESTRUCT] Converting asymmetric data from $list "
              . "to asymmetric table";
        $data = $self->to_table_asym (%args);
    }
    elsif ($as_symmetric && $is_asym) {
        say "[BASESTRUCT] Converting asymmetric data from $list "
              . "to symmetric table";
        $data = $self->to_table_asym_as_sym (%args);
    }
    else {
        say "[BASESTRUCT] Converting symmetric data from $list "
              . "to symmetric table";
        $data = $self->to_table_sym (%args);
    }

    return wantarray ? @$data : $data;
}

#  sometimes we have names of unequal length
sub get_longest_name_array_length {
    my $self = shift;

    my $longest = -1;
    foreach my $element ($self->get_element_list) {
        my $array = $self->get_element_name_as_array (element => $element);
        my $len = scalar @$array;
        if ($len > $longest) {
            $longest = $len;
        }
    }
    return $longest;
}

#  Write parts of the object to a CSV file
#  Assumes these are always hashes, which may blow
#  up in our faces later.  We'll fix it then
sub to_table_sym {  
    my $self = shift;
    my %args = @_;
    defined $args{list} || croak "list not defined\n";

    my $no_data_value      = $args{no_data_value};
    my $one_value_per_line = $args{one_value_per_line};
    my $no_element_array   = $args{no_element_array};
    my $quote_el_names     = $args{quote_element_names_and_headers};
    my $def_query          = $args{def_query};

    my $fh = $args{file_handle};
    my $csv_obj = $fh ? $self->get_csv_object_for_export (%args) : undef;

    my $quote_char = $self->get_param('QUOTES');

    my @data;
    my @elements;
    if ($def_query) {
        @elements = 
            sort @{$self->get_elements_that_pass_def_query( defq=>$def_query )};
    }
    else {
        @elements = sort $self->get_element_list;
    }

    my $list_hash_ref = $self->get_hash_list_values(
        element => $elements[0],
        list    => $args{list},
    );
    my @print_order = sort keys %$list_hash_ref;
    my @quoted_print_order =
        map {$quote_el_names ? "$quote_char$_$quote_char" : $_}
        @print_order;

    my $max_element_array_len;  #  used in some sections, set below if needed

    #  need the number of element components for the header
    my @header = ('ELEMENT');  

    if (! $no_element_array) {
        my $i = 0;
        #  get the number of element columns
        $max_element_array_len = $self->get_longest_name_array_length - 1;

        foreach my $null (0 .. $max_element_array_len) {
            push (@header, 'Axis_' . $i);
            $i++;
        }
    }

    if ($one_value_per_line) {
        push @header, qw /Key Value/; #/
    }
    else {
        push @header, @quoted_print_order;
    }

    if ($quote_el_names) {
        for (@header) {
            next if $_ =~ /^$quote_char/;  #  already quoted
            $_ = "$quote_char$_$quote_char";
        }
    }

    push @data, \@header;
    
    #  now add the data to the array
    foreach my $element (@elements) {
        my $el = $quote_el_names ? "$quote_char$element$quote_char" : $element;
        my @basic = ($el);
        if (! $no_element_array) {
            my @array = $self->get_element_name_as_array (element => $element);
            if ($#array < $max_element_array_len) {  #  pad if needed
                push @array, (undef) x ($max_element_array_len - $#array);
            }
            push @basic, @array;
        }

        my $list_ref = $self->get_hash_list_values(
            element => $element,
            list    => $args{list},
        );

        if ($one_value_per_line) {  
            #  repeat the elements, once for each value or key/value pair
            if (!defined $no_data_value) {
                foreach my $key (@print_order) {
                    push @data, [@basic, $key, $list_ref->{$key}];
                }
            }
            else {  #  need to change some values
                foreach my $key (@print_order) {
                    my $val = $list_ref->{$key} // $no_data_value;
                    push @data, [@basic, $key, $val];
                }
            }
        }
        else {
            if (!defined $no_data_value) {
                push @data, [@basic, @{$list_ref}{@print_order}];
            }
            else {
                my @vals = map {defined $_ ? $_ : $no_data_value} @{$list_ref}{@print_order};
                push @data, [@basic, @vals];
            }
        }

        if ($fh) {
            #  print to file, clear @data - gets header on first run
            while (my $list_data = shift @data) {
                my $string = $self->list2csv (
                    csv_object => $csv_obj,
                    list       => $list_data,
                );
                say { $fh } $string;
            }
        }
    }

    return wantarray ? @data : \@data;
}

sub to_table_asym {  #  get the data as an asymmetric table
    my $self = shift;
    my %args = @_;
    defined $args{list} || croak "list not specified\n";

    my $list = $args{list};

    my $no_data_value      = $args{no_data_value};
    my $one_value_per_line = $args{one_value_per_line};
    my $no_element_array   = $args{no_element_array};
    my $quote_el_names     = $args{quote_element_names_and_headers};
    my $def_query          = $args{def_query};

    my $fh = $args{file_handle};
    my $csv_obj = $fh ? $self->get_csv_object_for_export (%args) : undef;
    my $quote_char = $self->get_param('QUOTES');

    my @data;  #  2D array to hold the data
    my @elements;
    if ($def_query) {
        @elements = 
            sort $self->get_elements_that_pass_def_query( defq => $def_query );
    }
    else {
        @elements = sort $self->get_element_list;
    }
    push my @header, 'ELEMENT'; 
    if (! $no_element_array) {  #  need the number of element components for the header
        my $i = 0;
        #  get the number of element columns
        foreach my $null (@{$self->get_element_name_as_array (element => $elements[0])}) {  
            push (@header, "Axis_$i");
            $i++;
        }
    }

    if ($one_value_per_line) {
        push @header, qw /Key Value/;
    }
    else {
        push @header, "Value";
    }

    if ($quote_el_names) {
        for (@header) {
            next if $_ =~ /^$quote_char/;  #  already quoted
            $_ = "$quote_char$_$quote_char" ;
        }
    }

    push @data, \@header;
    
    

    foreach my $element (@elements) {
        my $el = $quote_el_names ? "$quote_char$element$quote_char" : $element;
        my @basic = ($el);
        if (! $no_element_array) {
            push @basic, ($self->get_element_name_as_array (element => $element));
        }
        #  get_list_values returns a list reference in scalar context - could be a hash or an array
        my $list =  $self->get_list_values (element => $element, list => $list);
        if ($one_value_per_line) {  #  repeats the elements, once for each value or key/value pair
            if (is_arrayref($list)) {
                foreach my $value (@$list) {
                    if (!defined $value) {
                        $value = $no_data_value;
                    }
                    push @data, [@basic, $value];  #  preserve internal ordering - useful for extracting iteration based values
                }
            }
            elsif (is_hashref($list)) {
                my %hash = %$list;
                foreach my $key (sort keys %hash) {
                    push @data, [@basic, $key, defined $hash{$key} ? $hash{$key} : $no_data_value];
                }
            }
            #else {  #  we have a scale - probably undef so treat it as such
                #  atually, don't do anything for the moment.
            #}
        }
        else {
            my @line = @basic;
            if (is_arrayref($list)) {
                #  preserve internal ordering - useful for extracting iteration based values
                push @line, map {defined $_ ? $_ : $no_data_value} @$list;  
            }
            elsif (is_hashref($list)) {
                my %hash = %$list;
                foreach my $key (sort keys %hash) {
                    push @line, ($key, defined $hash{$key} ? $hash{$key} : $no_data_value);
                }
            }
            push @data, \@line;
        }

        if ($fh) {
            #  print to file, clear @data - gets header on first run
            while (my $list_data = shift @data) {
                my $string = $self->list2csv (
                    csv_object => $csv_obj,
                    list       => $list_data,
                );
                say { $fh } $string;
            }
        }
    }

    return wantarray ? @data : \@data;
}

sub to_table_asym_as_sym {  #  write asymmetric lists to a symmetric format
    my $self = shift;
    my %args = @_;
    defined $args{list} || croak "list not specified\n";

    my $list = $args{list};

    my $no_data_value      = $args{no_data_value};
    my $one_value_per_line = $args{one_value_per_line};
    my $no_element_array   = $args{no_element_array};
    my $quote_el_names     = $args{quote_element_names_and_headers};
    my $def_query          = $args{def_query};

    my $fh = $args{file_handle};
    my $csv_obj = $fh ? $self->get_csv_object_for_export (%args) : undef;

    # Get all possible indices by sampling all elements
    # - this allows for asymmetric lists

    my $elements;
    if ($def_query) {
        $elements = $self->get_element_hash_that_pass_def_query( defq => $def_query );
    }
    else {
        $elements = $self->get_element_hash();
    }

    my %indices_hash;

    my $quote_char = $self->get_param('QUOTES');

    say "[BASESTRUCT] Getting keys...";

  BY_ELEMENT1:
    foreach my $elt (keys %$elements) {
        my $sub_list = $elements->{$elt}{$list};
        if (is_arrayref($sub_list)) {
            @indices_hash{@$sub_list} = (undef) x scalar @$sub_list;
        }
        elsif (is_hashref($sub_list)) {
            @indices_hash{keys %$sub_list} = (undef) x scalar keys %$sub_list;
        }
    }
    my @print_order = sort keys %indices_hash;
    my @quoted_print_order =
        map {$quote_el_names && !looks_like_number ($_) ? "$quote_char$_$quote_char" : $_}
        @print_order;

    my @data;

    my @elements;
    if ($def_query) {
        @elements = 
            sort $self->get_elements_that_pass_def_query( defq => $def_query );
    }
    else {
        @elements = sort keys %$elements;
    }

    push my @header, 'ELEMENT';  #  need the number of element components for the header
    if (! $no_element_array) {
        my $i = 0;
        foreach my $null (@{$self->get_element_name_as_array(element => $elements[0])}) {  #  get the number of element columns
            push (@header, "Axis_$i");
            $i++;
        }
    }

    if ($one_value_per_line) {
        push @header, qw /Key Value/;
    }
    else {
        push @header, @quoted_print_order;
    }

    if ($quote_el_names) {
        for (@header) {
            next if $_ =~ /^$quote_char/;  #  already quoted
            $_ = "$quote_char$_$quote_char" ;
        }
    }

    push @data, \@header;
    
    print "[BASESTRUCT] Processing elements...\n";

    BY_ELEMENT2:
    foreach my $element (@elements) {
        my $el = looks_like_number ($element) ? $element : "$quote_char$element$quote_char";
        my @basic = ($el);

        if (! $no_element_array) {
            push @basic, ($self->get_element_name_as_array (element => $element)) ;
        }
        my $list = $self->get_list_ref (
            element => $element,
            list    => $list,
            autovivify => 0,
        );
        my %data_hash = %indices_hash;
        @data_hash{keys %data_hash}
          = ($no_data_value) x scalar keys %data_hash;
        if (is_arrayref($list)) {
            foreach my $val (@$list) {
                $data_hash{$val}++;  #  track dups
            }
        }
        elsif (is_hashref($list)) {
            @data_hash{keys %$list} = values %$list;
        }

        #  we've built the hash, now print it out
        if ($one_value_per_line) {  #  repeats the elements, once for each value or key/value pair
            foreach my $key (@print_order) {
                push @data, [@basic, $key, $data_hash{$key}];
            }
        }
        else {
            push @data, [@basic, @data_hash{@print_order}];
        }

        if ($fh) {
            #  print to file, clear @data - gets header on first run
            while (my $list_data = shift @data) {
                my $string = $self->list2csv (
                    csv_object => $csv_obj,
                    list       => $list_data,
                );
                say { $fh } $string;
            }
        }
    }

    return wantarray ? @data : \@data;
}

#  write a table out as a series of ESRI asciigrid files, one per field based on row 0.
#  skip any that contain non-numeric values
sub write_table_asciigrid {
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    is_arrayref($data) || croak "data arg must be an array ref\n";

    my $file = $args{file} || croak "file arg not specified\n";
    my ($name, $path, $suffix) = fileparse (Path::Class::file($file)->absolute, qr/\.asc/, qr/\.txt/);
    my $file_list_ref = $args{filelist} || [];
    
    if (! defined $suffix || $suffix eq q{}) {  #  clear off the trailing .asc and store it
        $suffix = '.asc';
    }

    #  now process the generic stuff
    my $r = $self->raster_export_process_args ( %args );

    my @min       = @{$r->{MIN}};
    my @max       = @{$r->{MAX}};
    my @min_ids   = @{$r->{MIN_IDS}};
    my @max_ids   = @{$r->{MAX_IDS}};
    my %data_hash = %{$r->{DATA_HASH}};
    my @band_cols = @{$r->{BAND_COLS}};
    my $header    =   $r->{HEADER};
    my $no_data   =   $r->{NODATA};
    my @res       = @{$r->{RESOLUTIONS}};
    my $ncols     = $r->{NCOLS};
    my $nrows     = $r->{NROWS};

    my %coord_cols_hash = %{$r->{COORD_COLS_HASH}};

    my @fh;  #  file handles
    my @file_names;
    foreach my $i (@band_cols) {
        next if $coord_cols_hash{$i};  #  skip if it is a coordinate

        my $this_file = $name . "_" . $header->[$i];
        $this_file = $self->escape_filename (string => $this_file);

        my $filename    = Path::Class::file($path, $this_file)->stringify;
        $filename      .= $suffix;
        $file_names[$i] = $filename;
        push @$file_list_ref, $filename; # record file in list

        my $fh;
        my $success = open ($fh, '>', $filename);
        croak "Cannot open $filename\n"
          if ! $success;

        $fh[$i] = $fh;
        print $fh "nrows $nrows\n";
        print $fh "ncols $ncols\n";
        print $fh "xllcenter $min[0]\n";
        print $fh "yllcenter $min[1]\n";
        print $fh "cellsize $res[0]\n";  #  CHEATING 
        print $fh "nodata_value $no_data\n";
    }

    my %coords;
    #my @default_line = ($no_data x scalar @$header);

    for my $y (reverse ($min_ids[1] .. $max_ids[1])) {
        for my $x ($min_ids[0] .. $max_ids[0]) {
            my $coord_name = join (':', $x, $y);
            foreach my $i (@band_cols) {
                next if $coord_cols_hash{$i};  #  skip if it is a coordinate
                my $value = $data_hash{$coord_name}[$i] // $no_data;
                my $ofh = $fh[$i];
                print $ofh "$value ";
            }
        }
        #  end of lines
        foreach my $i (@band_cols) { 
            #next if $coord_cols_hash{$i};  #  skip if it is a coordinate
            my $fh = $fh[$i];
            print $fh "\n";
        }
    }

    FH:
    for (my $i = 0; $i <= $#fh; $i++) {
        my $fh = $fh[$i];

        next if ! defined $fh;

        if (close $fh) {
            print "[BASESTRUCT] Write to file $file_names[$i] successful\n";
        }
        else {
            print "[BASESTRUCT] Write to file $file_names[$i] failed\n";
        }

    }

    return;
}

#  write a table out as a series of ESRI floatgrid files,
#  one per field based on row 0.
#  Skip any fields that contain non-numeric values
sub write_table_floatgrid {
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    is_arrayref($data) || croak "data arg must be an array ref\n";

    my $file = $args{file} || croak "file arg not specified\n";
    my ($name, $path, $suffix) = fileparse (Path::Class::file($file)->absolute, qr/\.flt/);
    if (! defined $suffix || $suffix eq q{}) {  #  clear off the trailing .flt and store it
        $suffix = '.flt';
    }

    #  now process the generic stuff
    my $r = $self->raster_export_process_args ( %args );

    my @min       = @{$r->{MIN}};
    my @max       = @{$r->{MAX}};
    my @min_ids   = @{$r->{MIN_IDS}};
    my @max_ids   = @{$r->{MAX_IDS}};
    my %data_hash = %{$r->{DATA_HASH}};
    my @band_cols = @{$r->{BAND_COLS}};
    my $header    =   $r->{HEADER};
    my $no_data   =   $r->{NODATA};
    my @res       = @{$r->{RESOLUTIONS}};
    my $ncols     =   $r->{NCOLS};
    my $nrows     =   $r->{NROWS};


    my %coord_cols_hash = %{$r->{COORD_COLS_HASH}};

    #  are we LSB or MSB?
    my $is_little_endian = unpack( 'c', pack( 's', 1 ) );

    my @fh;  #  file handles
    my @file_names;
    foreach my $i (@band_cols) {
        #next if $coord_cols_hash{$i};  #  skip if it is a coordinate
        my $this_file = $name . "_" . $header->[$i];
        $this_file = $self->escape_filename (string => $this_file);

        my $filename = Path::Class::file($path, $this_file)->stringify;
        $filename .= $suffix;
        $file_names[$i] = $filename;

        my $fh;
        my $success = open ($fh, '>', $filename);
        croak "Cannot open $filename\n"
          if ! $success;

        binmode $fh;
        $fh[$i] = $fh;

        my $header_file = $filename;
        $header_file =~ s/$suffix$/\.hdr/;
        $success = open (my $fh_hdr, '>', $header_file);
        croak "Cannot open $header_file\n" if ! $success;

        print $fh_hdr "nrows $nrows\n";
        print $fh_hdr "ncols $ncols\n";
        print $fh_hdr "xllcenter $min[0]\n";
        print $fh_hdr "yllcenter $min[1]\n";
        print $fh_hdr "cellsize $res[0]\n"; 
        print $fh_hdr "nodata_value $no_data\n";
        print $fh_hdr 'byteorder ',
                      ($is_little_endian ? 'LSBFIRST' : 'MSBFIRST'),
                      "\n";
        $fh_hdr->close;
    }

    my %coords;
    #my @default_line = ($no_data x scalar @$header);

    foreach my $y (reverse ($min_ids[1] .. $max_ids[1])) {
        foreach my $x ($min_ids[0] .. $max_ids[0]) {

            my $coord_name = join (':', $x, $y);
            foreach my $i (@band_cols) { 
                next if $coord_cols_hash{$i};  #  skip if it is a coordinate
                my $value = $data_hash{$coord_name}[$i] // $no_data;
                my $fh = $fh[$i];
                print $fh pack ('f', $value);
            }
        }
    }

    FH:
    for (my $i = 0; $i <= $#fh; $i++) {
        my $fh = $fh[$i];

        next FH if ! defined $fh;

        if (close $fh) {
            print "[BASESTRUCT] Write to file $file_names[$i] successful\n";
        }
        else {
            print "[BASESTRUCT] Write to file $file_names[$i] failed\n";
        }
    }

    return;
}

#  lots of overlap with write_table_floatgrid - should refactor
sub write_table_divagis {
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    is_arrayref($data) || croak "data arg must be an array ref\n";

    my $file = $args{file} || croak "file arg not specified\n";
    my ($name, $path, $suffix) = fileparse (Path::Class::file($file)->stringify, qr'\.gri');
    if (! defined $suffix || $suffix eq q{}) {  #  clear off the trailing .gri and store it
        $suffix = '.gri';
    }

    #  now process the generic stuff
    my $r = $self->raster_export_process_args ( %args );

    my @min       = @{$r->{MIN}};
    my @max       = @{$r->{MAX}};
    my @min_ids   = @{$r->{MIN_IDS}};
    my @max_ids   = @{$r->{MAX_IDS}};
    my %data_hash = %{$r->{DATA_HASH}};
    my @band_cols = @{$r->{BAND_COLS}};
    my $header    =   $r->{HEADER};
    my $no_data   =   $r->{NODATA};
    my @res       = @{$r->{RESOLUTIONS}};
    my $ncols     =   $r->{NCOLS};
    my $nrows     =   $r->{NROWS};

    my %coord_cols_hash = %{$r->{COORD_COLS_HASH}};

    #  are we LSB or MSB?
    my $is_little_endian = unpack( 'c', pack( 's', 1 ) );

    my @fh;  #  file handles
    my @file_names;
    foreach my $i (@band_cols) {
        #next if $coord_cols_hash{$i};  #  skip if it is a coordinate
        my $this_file = $name . "_" . $header->[$i];
        $this_file = $self->escape_filename (string => $this_file);

        my $filename = Path::Class::file($path, $this_file)->stringify;
        $filename .= $suffix;
        $file_names[$i] = $filename;

        my $fh;
        my $success = open ($fh, '>', $filename);
        croak "Cannot open $filename\n"
          if ! $success;

        binmode $fh;
        $fh[$i] = $fh;

        my $header_file = $filename;
        $header_file =~ s/$suffix$/\.grd/;
        $success = open (my $fh_hdr, '>', $header_file);
        croak "Cannot open $header_file\n" if ! $success;

        my $time = localtime;
        my $create_time = ($time->year + 1900) . ($time->mon + 1) . $time->mday;
        my $minx = $min[0] - $res[0] / 2;
        my $maxx = $max[0] + $res[0] / 2;
        my $miny = $min[1] - $res[1] / 2;
        my $maxy = $max[1] + $res[1] / 2;
        my $stats = $self->get_list_value_stats (list => $args{list}, index => $header->[$i]);

        my $diva_hdr = <<"DIVA_HDR"
[General]
Version= 1.0
Creator= Biodiverse $VERSION
Title=$header->[$i]
Created= $create_time

[GeoReference]
Projection=unknown
Columns=$ncols
Rows=$nrows
MinX=$minx
MaxX=$maxx
MinY=$miny
MaxY=$maxy
ResolutionX= $res[0]
ResolutionY= $res[1]

[Data]
DataType=FLT4S
MinValue=$stats->{MIN}
MaxValue=$stats->{MAX}
NoDataValue=$no_data
Transparent=1


DIVA_HDR
  ;
        print $fh_hdr $diva_hdr;
        $fh_hdr->close;
    }

    my %coords;
    #my @default_line = ($no_data x scalar @$header);

    foreach my $y (reverse ($min_ids[1] .. $max_ids[1])) {
        foreach my $x ($min_ids[0] .. $max_ids[0]) {

            my $coord_name = join (':', $x, $y);
            foreach my $i (@band_cols) { 
                next if $coord_cols_hash{$i};  #  skip if it is a coordinate
                my $value = $data_hash{$coord_name}[$i] // $no_data;
                my $fh = $fh[$i];
                print $fh pack ('f', $value);
            }
        }
    }

    FH:
    for (my $i = 0; $i <= $#fh; $i++) {
        my $fh = $fh[$i];

        next FH if ! defined $fh;

        if (close $fh) {
            print "[BASESTRUCT] Write to file $file_names[$i] successful\n";
        }
        else {
            print "[BASESTRUCT] Write to file $file_names[$i] failed\n";
        }
    }

    return;
}

#  write a table out as a series of ESRI floatgrid files,
#  one per field based on row 0.
#  Skip any fields that contain non-numeric values
sub write_table_geotiff {
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    is_arrayref($data) || croak "data arg must be an array ref\n";

    my $file = $args{file} || croak "file arg not specified\n";
    my ($name, $path, $suffix) = fileparse (Path::Class::file($file)->absolute, qr/\.tif{1,2}/);
    if (! defined $suffix || $suffix eq q{}) {  #  clear off the trailing .tif and store it
        $suffix = '.tif';
    }

    #  now process the generic stuff
    my $r = $self->raster_export_process_args ( %args );

    my @min       = @{$r->{MIN}};
    my @max       = @{$r->{MAX}};
    my @min_ids   = @{$r->{MIN_IDS}};
    my @max_ids   = @{$r->{MAX_IDS}};
    my %data_hash = %{$r->{DATA_HASH}};
    my @band_cols = @{$r->{BAND_COLS}};
    my $header    =   $r->{HEADER};
    my $no_data   =   $r->{NODATA};
    my @res       = @{$r->{RESOLUTIONS}};
    my $ncols     =   $r->{NCOLS};
    my $nrows     =   $r->{NROWS};

    my %coord_cols_hash = %{$r->{COORD_COLS_HASH}};

    my $ll_cenx = $min[0];  # - 0.5 * $res[0];
    my $ul_ceny = $max[1];  # - 0.5 * $res[1];

    my $tfw = <<"END_TFW"
$res[0]
0
0
-$res[1]
$ll_cenx
$ul_ceny
END_TFW
  ;

    #  are we LSB or MSB?
    my $is_little_endian = unpack( 'c', pack( 's', 1 ) );

    my @file_names;
    foreach my $i (@band_cols) {
        my $this_file = $name . "_" . $header->[$i];
        $this_file = $self->escape_filename (string => $this_file);

        my $filename = Path::Class::file($path, $this_file)->stringify;
        $filename   .= $suffix;
        $file_names[$i] = $filename;
    }

    my %coords;
    my @bands;

    foreach my $y (reverse ($min_ids[1] .. $max_ids[1])) {
        foreach my $x ($min_ids[0] .. $max_ids[0]) {

            my $coord_id = join (':', $x, $y);
            foreach my $i (@band_cols) { 
                next if $coord_cols_hash{$i};  #  skip if it is a coordinate
                my $value = $data_hash{$coord_id}[$i] // $no_data;
                $bands[$i] .= pack 'f', $value;
            }
        }
    }

    my $format = "GTiff";
    my $driver = Geo::GDAL::GetDriverByName( $format );

    foreach my $i (@band_cols) {
        my $f_name = $file_names[$i];
        my $pdata  = $bands[$i];

        my $out_raster = $driver->Create($f_name, $ncols, $nrows, 1, 'Float32');

        my $out_band = $out_raster->GetRasterBand(1);
        $out_band->SetNoDataValue ($no_data);
        $out_band->WriteRaster(0, 0, $ncols, $nrows, $pdata);

        my $f_name_tfw = $f_name . 'w';
        open(my $fh, '>', $f_name_tfw) or die "cannot open $f_name_tfw";
        print {$fh} $tfw;
        $fh->close;
    }

    return;
}

#  write a table out as an ER-Mapper ERS BIL file.
sub write_table_ers {
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    is_arrayref($data) || croak "data arg must be an array ref\n";
    my $file = $args{file} || croak "file arg not specified\n";

    my ($name, $path, $suffix)
        = fileparse (Path::Class::file($file)->absolute, qr/\.ers/);

    #  add suffix if not specified
    if (!defined $suffix || $suffix eq q{}) {
        $suffix = '.ers';
    }

    #  now process the generic stuff
    my $r = $self->raster_export_process_args ( %args );

    my @min       = @{$r->{MIN}};
    my @max       = @{$r->{MAX}};
    my @min_ids   = @{$r->{MIN_IDS}};
    my @max_ids   = @{$r->{MAX_IDS}};
    my %data_hash = %{$r->{DATA_HASH}};
    my @band_cols = @{$r->{BAND_COLS}};
    my $header    =   $r->{HEADER};
    my $no_data   =   $r->{NODATA};
    my @res       = @{$r->{RESOLUTIONS}};
    #my $ncols     =   $r->{NCOLS};
    #my $nrows     =   $r->{NROWS};

    my %coord_cols_hash = %{$r->{COORD_COLS_HASH}};

    #my %stats;

    my $data_file = Path::Class::file($path, $name)->stringify;
    my $success = open (my $ofh, '>', $data_file);
    if (! $success) {
        croak "Could not open output file $data_file\n";
    }
    binmode $ofh;

    my ($ncols, $nrows) = (0, 0);

    foreach my $y (reverse ($min_ids[1] .. $max_ids[1])) {

        $nrows ++;
        foreach my $band (@band_cols) {
            $ncols = 0;

            foreach my $x ($min_ids[0] .. $max_ids[1]) {

                my $ID = "$x:$y";
                my $value = $data_hash{$ID}[$band] // $no_data;

                eval {
                    print {$ofh} pack 'f', $value;
                };
                croak $EVAL_ERROR if $EVAL_ERROR;

                $ncols ++;
                #print "$ID, $value\n" if $band == $band_cols[0];
            }
        }
    }

    if (! close $ofh) {
        croak "Unable to write to $data_file\n";
    }
    else {
        print "[BASESTRUCT] Write to file $data_file successful\n";
    }

    #  are we LSB or MSB?
    my $is_little_endian = unpack( 'c', pack( 's', 1 ) );
    my $LSB_or_MSB = $is_little_endian ? 'LSBFIRST' : 'MSBFIRST';
    my $gm_time = (gmtime);
    $gm_time =~ s/(\d+)$/GMT $1/;  #  insert "GMT" before the year
    my $n_bands = scalar @band_cols;

    #  The RegistrationCell[XY] values should be 0.5,
    #  but 0 plots properly in ArcMap
    #  -- fixed in arc 10.2, and prob earlier, so we are OK now
    my @reg_coords = (
        $min[0] - ($res[0] / 2),
        $max[1] + ($res[1] / 2),
        #$min[0], $max[1],
    );


    my $header_start =<<"END_OF_ERS_HEADER_START"
DatasetHeader Begin
\tVersion         = "5.5"
\tName		= "$name$suffix"
\tLastUpdated     = $gm_time
\tDataSetType     = ERStorage
\tDataType        = Raster
\tByteOrder       = $LSB_or_MSB
\tCoordinateSpace Begin
\t\tDatum           = "Unknown"
\t\tProjection      = "Unknown"
\t\tCoordinateType  = EN
\t\tRotation        = 0:0:0.0
\tCoordinateSpace End
\tRasterInfo Begin
\t\tCellType        = IEEE4BYTEREAL
\t\tNullCellValue = $no_data
\t\tCellInfo Begin
\t\t\tXdimension      = $res[0]
\t\t\tYdimension      = $res[1]
\t\tCellInfo End
\t\tNrOfLines       = $nrows
\t\tNrOfCellsPerLine        = $ncols
\t\tRegistrationCoord Begin
\t\t\tEastings        = $reg_coords[0]
\t\t\tNorthings       = $reg_coords[1]
\t\tRegistrationCoord End
\t\tRegistrationCellX  = 0
\t\tRegistrationCellY  = 0
\t\tNrOfBands       = $n_bands
END_OF_ERS_HEADER_START
;

    my @header = $header_start;

    #  add the band info
    foreach my $i (@band_cols) {
        push @header, (
            qq{\t\tBandId Begin},
            qq{\t\t\tValue           = "}
              . $self->escape_filename(string => $header->[$i])
              . qq{"},
            qq{\t\tBandId End},
        );
    }

    push @header, (
        "\tRasterInfo End",
        "DatasetHeader End"
    );

    my $header_file = Path::Class::file($path, $name)->stringify . $suffix;
    open (my $header_fh, '>', $header_file)
      or croak "Could not open header file $header_file\n";

    say {$header_fh} join ("\n", @header);

    croak "Unable to write to $header_file\n"
      if !$header_fh->close;
    
    say "[BASESTRUCT] Write to file $header_file successful";

    return;
}

sub raster_export_process_args {
    my $self = shift;
    my %args = @_;
    my $data = $args{data};

    my @axes_to_use = (0,1);

    my $no_data = defined $args{no_data_value}
                ? eval $args{no_data_value}
                : undef;

    if (! defined $no_data or not looks_like_number $no_data ) {
        $no_data = -9999 ;
        print "[BASESTRUCT] Overriding undefined or non-numeric no_data_value with $no_data\n";
    }

    my @res = defined $args{resolutions}
            ? @{$args{resolutions}}
            : $self->get_cell_sizes;

    #  check the resolutions.
    eval {
        $self->raster_export_test_axes_validity (
            resolutions => [@res[@axes_to_use]],
        );
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    my @coord_cols = $self->raster_export_get_coord_cols (%args);
    my %coord_cols_hash;
    @coord_cols_hash{@coord_cols} = @coord_cols;

    my $header = shift @$data;
    my $data_start_col = (scalar @res) + 1;  #  first three columns are ID, followed by coords
    my @band_cols = ($data_start_col .. $#$header);  

    my $res = $self->raster_export_process_table (
        data       => $data,
        coord_cols => \@coord_cols,
        res        => \@res,
    );
    my @max = $res->{MAX};
    my @min = $res->{MIN};
    my $dimensions = $res->{DIMENSIONS};
    my $ncols = $dimensions->[0]; 
    my $nrows = $dimensions->[1];

    #  add some more keys to $res
    $res->{HEADER}          = $header;
    $res->{BAND_COLS}       = \@band_cols;
    $res->{NODATA}          = $no_data;
    $res->{RESOLUTIONS}     = \@res; 
    $res->{COORD_COLS_HASH} = \%coord_cols_hash;
    $res->{NCOLS}           = $ncols;
    $res->{NROWS}           = $nrows;

    return wantarray ? %$res : $res;
}

sub raster_export_test_axes_validity {
    my $self = shift;
    my %args = @_;
    my @resolutions = @{$args{resolutions}};

    my $i = 0;
    foreach my $r (@resolutions) {

        croak "[BASESTRUCT] Cannot export text axes to raster, axis $i\n"
          if $r < 0;

        croak "[BASESTRUCT] Cannot export point axes to raster, axis $i\n"
          if $r == 0;

        $i++;
    }

    return 1;
}

sub raster_export_get_coord_cols {
    my $self = shift;
    my %args = @_;

    my @coord_cols = defined $args{coord_cols} ? @{$args{coord_cols}} : (1,2);

    return wantarray ? @coord_cols : \@coord_cols;
}

sub raster_export_process_table {
    my $self = shift;
    my %args = @_;

    my $data = $args{data};
    my @coord_cols = @{$args{coord_cols}};
    my @res = @{$args{res}};

    #  loop through and get the min and max coords,
    #  as well as converting the array to a hash
    my @min = ( 10e20, 10e20);
    my @max = (-10e20,-10e20);
    my @min_ids = ( 10e20, 10e20);
    my @max_ids = (-10e20,-10e20);
    my %data_hash;
    foreach my $line (@$data) {
        my @coord = @$line[@coord_cols];
        $min[0] = min ($min[0], $coord[0]);
        $min[1] = min ($min[1], $coord[1]);
        $max[0] = max ($max[0], $coord[0]);
        $max[1] = max ($max[1], $coord[1]);
        my $cell_idx = floor ($coord[0] / $res[0]);
        my $cell_idy = floor ($coord[1] / $res[1]);
        $min_ids[0] = min ($min_ids[0], $cell_idx);
        $min_ids[1] = min ($min_ids[1], $cell_idy);
        $max_ids[0] = max ($max_ids[0], $cell_idx);
        $max_ids[1] = max ($max_ids[1], $cell_idy);
        
        $data_hash{join (':', $cell_idx, $cell_idy)} = $line;
    }

    my @dimensions = ($max_ids[0] - $min_ids[0] + 1, $max_ids[1] - $min_ids[1] + 1);

    my %results = (
        MIN        => \@min,
        MAX        => \@max,
        MIN_IDS    => \@min_ids,
        MAX_IDS    => \@max_ids,
        DATA_HASH  => \%data_hash,
        DIMENSIONS => \@dimensions,
    );

    return wantarray ? %results : \%results;
}

#  get the covariance matrix for a table of values
sub get_covariance_from_table {
    my $self = shift;
    my %args = @_;

    my $data = $args{data};
    my $flds  = $args{fields};
    my $means = $args{means};

    my $prefix = $args{prefix};  #  for as_text

    if (! defined $flds) {
        my $first_line = $data->[0];
        $flds = [0.. $#$first_line];
    }

    my @sums;
    my @counts;

    foreach my $line (@$data) {
        my $ii = -1;

        PASS1:
        foreach my $i (@$flds) {
            $ii ++;
            next PASS1 if ! defined $line->[$i];

            my $jj = -1;

            PASS2:
            foreach my $j (@$flds) {
                $jj ++;
                next PASS2 if ! defined $line->[$j];
                $sums[$ii][$jj] += ($line->[$i] - $means->[$i]) * ($line->[$j] - $means->[$j]);
                $counts[$ii][$jj] ++;
            }
        }
    }

    my @covariance;

    foreach my $row (0 .. $#$flds) {
        foreach my $col (0 .. $#$flds) {
            $covariance[$row][$col] = $counts[$row][$col]
                ? $sums[$row][$col] / $counts[$row][$col]
                : 0;
        }
    }

    if ($args{as_text}) {
        my $string;
        foreach my $row (@covariance) {
            $string .= $prefix . join ("\t", @$row) . "\n";
        }
        $string =~ s/\n$//;  #  strip trailing newline
        return $string;
    }

    return wantarray ? @covariance : \@covariance;
}

#  convert the elements to a tree format, eg family - genus - species
#  won't make sense for many types of basedata, but oh well.  
sub to_tree {
    my $self = shift;
    my %args = @_;

    my $name = $args{name} // $self->get_param ('NAME') . "_AS_TREE";
    my $tree = Biodiverse::Tree->new (NAME => $name);

    my $elements = $self->get_element_hash;

    my $quotes = $self->get_param ('QUOTES');  #  for storage, not import
    my $el_sep = $self->get_param ('JOIN_CHAR');
    my $csv_obj = $self->get_csv_object (
        sep_char   => $el_sep,
        quote_char => $quotes,
    );

    foreach my $element (keys %$elements) {
        my @components = $self->get_element_name_as_array (element => $element);
        #my @so_far;
        my @prev_names = ();
        #for (my $i = 0; $i <= $#components; $i++) {
        foreach my $i (0 .. $#components) {
            #$so_far[$i] = $components[$i];
            my $node_name = $self->list2csv (
                csv_object  => $csv_obj,
                list        => [@components[0..$i]],
            );
            $node_name = $self->dequote_element (
                element    => $node_name,
                quote_char => $quotes,
            );

            my $parent_name = $i ? $prev_names[$i-1] : undef;  #  no parent if at highest level

            if (not $tree->node_is_in_tree (node => $node_name)) {
                my $node = $tree->add_node (
                    name   => $node_name,
                    length => 1,
                );

                if ($parent_name) {
                    my $parent_node = $tree->get_node_ref (node => $parent_name);
                    #  create the parent if need be - SHOULD NOT HAPPEN
                    #if (not defined $parent_node) {
                    #    $parent_node = $tree->add_node (name => $parent_name, length => 1);
                    #}
                    #  now add the child with the element as the name so we can link properly to the basedata in labels tab
                    $node->set_parent (parent => $parent_node);
                    $parent_node->add_children (children => [$node]);
                }
            }
            #push @so_far, $node_name;
            $prev_names[$i] = $node_name;
        }
    }

    #  set a master root node of length zero if we have more than one.
    #  All the current root nodes will be its children
    my $root_nodes = $tree->get_root_node_refs;
    my $root_node  = $tree->add_node (name => '0___', length => 0);
    $root_node->add_children (children => [@$root_nodes]);
    foreach my $node (@$root_nodes) {
        $node->set_parent (parent => $root_node);
    }

    $tree->set_parents_below;  #  run a clean up just in case
    return $tree;
}

sub get_element_count {
    my $self = shift;
    my $el_hash = $self->{ELEMENTS};
    return scalar keys %$el_hash;
}

sub get_element_list {
    my $self = shift;
    my $el_hash = $self->{ELEMENTS};
    return wantarray ? keys %$el_hash : [keys %$el_hash];
}

sub sort_by_axes {
    my $self = shift;
    my $item_a = shift;
    my $item_b = shift;

    my $axes = $self->get_cell_sizes;
    my $res = 0;
    my $a_array = $self->get_element_name_as_array (element => $item_a);
    my $b_array = $self->get_element_name_as_array (element => $item_b);
    foreach my $i (0 .. $#$axes) {
        $res = $axes->[$i] < 0
            ? $a_array->[$i] cmp $b_array->[$i]
            : $a_array->[$i] <=> $b_array->[$i];

        return $res if $res;
    }

    return $res;
};

#  get a list sorted by the axes
sub get_element_list_sorted {
    my $self = shift;
    my %args = @_;

    my @list = $args{list} ? @{$args{list}} : $self->get_element_list;
    my @array = sort {$self->sort_by_axes ($a, $b)} @list;

    return wantarray ? @array : \@array;
}

# pass in a string def query, this returns a list of all elements that
# pass the def query.
sub get_elements_that_pass_def_query {
    my ($self, %args) = @_;
    my $def_query = $args{defq};    
    
    my $elements_that_pass_hash = 
        $self->get_element_hash_that_pass_def_query( defq => $args{defq} );

    my @elements_that_pass = keys %$elements_that_pass_hash;
    
    return wantarray ? @elements_that_pass : \@elements_that_pass;
}

# gets the complete element hash and then weeds out elements that
# don't pass a given def query.
sub get_element_hash_that_pass_def_query {
    my ($self, %args) = @_;
    my $def_query = $args{defq};
     
    $def_query =
        Biodiverse::SpatialConditions::DefQuery->new(
            conditions => $def_query, );

    my $bd = $self->get_basedata_ref;
    if (Biodiverse::MissingBasedataRef->caught) {
        # What do we do here?
        say "[BaseStruct.pm]: Missing BaseStruct in 
                       get_elements_hash_that_pass_def_query";
        return;
    }
    
    my $groups        = $bd->get_groups;
    my $element       = $groups->[0];

    my $elements_that_pass_hash = $bd->get_neighbours(
        element            => $element,
        spatial_conditions => $def_query,
        is_def_query       => 1,
        );

    
    # at this stage we have a hash in the form "element_name" -> 1 to
    # indicate that it passed the def query. We want this in the form
    # "element_name" -> all the data about this element. This is the
    # format used by get_element_hash and so by a lot of the
    # basestruct functions.
    
    my %formatted_element_hash = $self->get_element_hash;

    my %formatted_elements_that_pass;
    foreach my $element (keys %formatted_element_hash) {
        if ($elements_that_pass_hash->{$element}) {
            $formatted_elements_that_pass{$element} 
                  = $formatted_element_hash{$element};
        }
    }
    
    return \%formatted_elements_that_pass;
}

sub get_element_hash {
    my $self = shift;

    my $elements = $self->{ELEMENTS};

    return wantarray ? %$elements : $elements;
}

sub get_element_name_as_array_aa {
    my ($self, $element) = @_;

    return $self->get_array_list_values_aa ($element, '_ELEMENT_ARRAY');
}

sub get_element_name_as_array {
    my $self = shift;
    my %args = @_;

    my $element = $args{element} //
      croak "element not specified\n";

    return $self->get_array_list_values (
        element => $element,
        list    => '_ELEMENT_ARRAY',
    );
}

#  get a list of the unique values for one axis
sub get_unique_element_axis_values {
    my $self = shift;
    my %args = @_;

    my $axis = $args{axis};
    croak "get_unique_element_axis_values: axis arg not defined\n"
      if !defined $axis;

    my %values;

    ELEMENT:
    foreach my $element ($self->get_element_list) {
        my $coord_array
          = $self->get_element_name_as_array (element => $element);

        croak "not enough axes\n" if !exists ($coord_array->[$axis]);

        $values{$coord_array->[$axis]} ++;
    }

    return wantarray ? keys %values : [keys %values];
}

#  get a coordinate for the element
#  allows us to handle text axes for display
sub get_element_name_coord {
    my $self = shift;
    my %args = @_;
    defined $args{element} || croak "element not specified\n";
    my $element = $args{element};

    my $values = eval {
        $self->get_array_list_values (element => $element, list => '_ELEMENT_COORD');
    };
    if (Biodiverse::BaseStruct::ListDoesNotExist->caught) {  #  doesn't exist, so generate it 
        $self->generate_element_coords;
        $values = $self->get_element_name_coord (element => $element);
    }
    #croak $EVAL_ERROR if $EVAL_ERROR;  #  need tests before putting this in.  

    return wantarray ? @$values : $values;
}

#  generate the coords
sub generate_element_coords {
    my $self = shift;

    $self->delete_param ('AXIS_LIST_ORDER');  #  force recalculation for first one

    #my @is_text;
    foreach my $element ($self->get_element_list) {
        my $element_coord = [];  #  make a copy
        my $cell_sizes = $self->get_cell_sizes;
        #my $element_array = $self->get_array_list_values (element => $element, list => '_ELEMENT_ARRAY');
        my $element_array = eval {$self->get_element_name_as_array (element => $element)};
        if ($EVAL_ERROR) {
            print "PRIBBLEMMS";
            say Data::Dumper::Dump $self->{ELEMENTS}{$element};
        }
        

        foreach my $i (0 .. $#$cell_sizes) {
            if ($cell_sizes->[$i] >= 0) {
                $element_coord->[$i] = $element_array->[$i];
            }
            else {
                $element_coord->[$i] = $self->get_text_axis_as_coord (
                    axis => $i,
                    text => $element_array->[$i] // '',
                );
            }
        }
        $self->{ELEMENTS}{$element}{_ELEMENT_COORD} = $element_coord;
    }

    return 1;
}

sub get_text_axis_as_coord {
    my $self = shift;
    my %args = @_;
    my $axis = $args{axis};
    my $text = $args{text};
    croak 'Argument "text" is undefined' if !defined $text;

    #  store the axes as an array of hashes with value being the coord
    my $lists = $self->get_param ('AXIS_LIST_ORDER') || [];

    if (! $args{recalculate} and defined $lists->[$axis]) {  #  we've already done it, so return what we have
        return $lists->[$axis]{$text};
    }

    my %this_axis;
    #  go through and get a list of all the axis text
    foreach my $element (sort $self->get_element_list) {
        my $axes = $self->get_element_name_as_array (element => $element);
        $this_axis{$axes->[$axis] // ''}++;
    }
    #  assign a number based on the sort order.  "z" will be lowest, "a" will be highest
    use Sort::Naturally;
    @this_axis{reverse nsort keys %this_axis}
      = (0 .. scalar keys %this_axis);
    $lists->[$axis] = \%this_axis;

    $self->set_param (AXIS_LIST_ORDER => $lists);

    return $lists->[$axis]{$text};
}

sub get_sub_element_list {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element} // croak "argument 'element' not specified\n";

    my $el_hash = $self->{ELEMENTS}{$element}{SUBELEMENTS}
      // return;

    return wantarray ?  keys %$el_hash : [keys %$el_hash];
}

sub get_sub_element_hash {
    my $self = shift;
    my %args = @_;

    no autovivification;
    
    my $element = $args{element}
      // croak "argument 'element' not specified\n";

    #  Ideally we should throw an exception, but at the moment too many other
    #  things need a result and we aren't testing for them.
    my $hash = $self->{ELEMENTS}{$element}{SUBELEMENTS} // {};
      #// Biodiverse::NoSubElementHash->throw (
      #      message => "Element $element does not exist or has no SUBELEMENT hash\n",
      #  );

    #  No explicit return statement used here.  
    #  This is a hot path when called from Biodiverse::Indices::_calc_abc
    #  and perl versions pre 5.20 do not optimise the return.
    #  End result is ~30% faster for this line, although that might not
    #  translate to much in real terms when it works at millions of iterations per second
    #  (hence the lack of further optimisations on this front for now).
    wantarray ? %$hash : $hash;
}

sub get_sub_element_hash_aa {
    my ($self, $element) = @_;

    no autovivification;

    croak "argument 'element' not specified\n"
      if !defined $element;

    #  Ideally we should throw an exception, but at the moment too many other
    #  things need a result and we aren't testing for them.
    my $hash = $self->{ELEMENTS}{$element}{SUBELEMENTS} // {};

    wantarray ? %$hash : $hash;
}

sub get_subelement_count {
    my $self = shift;

    my %args = @_;
    my $element = $args{element};
    croak "argument 'element' not defined\n" if ! defined $element;

    my $sub_element = $args{sub_element};
    croak "argument 'sub_element' not defined\n" if ! defined $sub_element;

    if (exists $self->{ELEMENTS}{$element} && exists $self->{ELEMENTS}{$element}{SUBELEMENTS}{$sub_element}) {
        return $self->{ELEMENTS}{$element}{SUBELEMENTS}{$sub_element};
    }

    return;
}

#  pre-assign the hash buckets to avoid rehashing larger structures
sub _set_elements_hash_key_count {
    my $self = shift;
    my %args = @_;

    my $count = $args{count} // 'undef';

    #  do nothing if undef, zero or negative
    croak "Invalid count argument $count\n"
      if !looks_like_number $count || $count < 0;

    my $href = $self->{ELEMENTS};

    return if $count <= scalar keys %$href;  #  needed?

    return keys %$href = $count;
}


#  add an element to a baseStruct object
sub add_element {  
    my $self = shift;
    my %args = @_;

    my $element = $args{element} //
      croak "element not specified\n";

    #  don't re-create the element array
    return if $self->{ELEMENTS}{$element}{_ELEMENT_ARRAY};

    my $quote_char = $self->get_param('QUOTES');
    my $element_list_ref = $self->csv2list(
        string     => $element,
        sep_char   => $self->get_param('JOIN_CHAR'),
        quote_char => $quote_char,
        csv_object => $args{csv_object},
    );

    if (scalar @$element_list_ref == 1) {
        $element_list_ref->[0] //= ($quote_char . $quote_char)
    }
    else {
        for my $el (@$element_list_ref) {
            $el //= $EMPTY_STRING;
        }
    }

    $self->{ELEMENTS}{$element}{_ELEMENT_ARRAY} = $element_list_ref;

    return;
}

sub add_sub_element {  #  add a subelement to a BaseStruct element.  create the element if it does not exist
    my $self = shift;
    my %args = (count => 1, @_);

    no autovivification;

    my $element = $args{element} //
      croak "element not specified\n";

    my $sub_element = $args{subelement} //
      croak "subelement not specified\n";

    my $elts_ref = $self->{ELEMENTS};

    if (! exists $elts_ref->{$element}) {
        $self->add_element (
            element    => $element,
            csv_object => $args{csv_object},
        );
    }

    #  previous base_stats invalid - clear them if needed
    #if (exists $self->{ELEMENTS}{$element}{BASE_STATS}) {
        delete $elts_ref->{$element}{BASE_STATS};
    #}

    $elts_ref->{$element}{SUBELEMENTS}{$sub_element} += $args{count};

    return;
}

#  array args version for high frequency callers
sub add_sub_element_aa {
    my ($self, $element, $sub_element, $count, $csv_object) = @_;

    #no autovivification;

    croak "element not specified\n"    if !defined $element;
    croak "subelement not specified\n" if !defined $sub_element;

    my $elts_ref = $self->{ELEMENTS};

    if (! exists $elts_ref->{$element}) {
        $self->add_element (
            element    => $element,
            csv_object => $csv_object,
        );
    }

    #  previous base_stats invalid - clear them if needed
    delete $elts_ref->{$element}{BASE_STATS};

    $elts_ref->{$element}{SUBELEMENTS}{$sub_element} += ($count // 1);

    return;
}

sub rename_element {
    my $self = shift;
    my %args = @_;
    
    my $element  = $args{element};
    my $new_name = $args{new_name};

    croak "element does not exist\n"
      if !$self->exists_element (element => $element);
    croak "argument 'new_name' is undefined\n"
      if !defined $new_name;

    my @sub_elements =
        $self->get_sub_element_list (element => $element);

    my $el_hash = $self->{ELEMENTS};
    
    #  increment the subelements
    if ($self->exists_element (element => $new_name)) {
        my $sub_el_hash_target = $self->{ELEMENTS}{$new_name}{SUBELEMENTS};
        my $sub_el_hash_source = $self->{ELEMENTS}{$element}{SUBELEMENTS};
        foreach my $sub_element (keys %$sub_el_hash_source) {
            #if (exists $sub_el_hash_target->{$sub_element} {
                $sub_el_hash_target->{$sub_element} += $sub_el_hash_source->{$sub_element};
            #}
        }
    }
    else {
        $self->add_element (element => $new_name);
        my $el_array = $el_hash->{$new_name}{_ELEMENT_ARRAY};
        $el_hash->{$new_name} = $el_hash->{$element};
        #  reinstate the _EL_ARRAY since it will be overwritten bythe previous line
        $el_hash->{$new_name}{_ELEMENT_ARRAY} = $el_array;
        #  the coord will need to be recalculated
        delete $el_hash->{$new_name}{_ELEMENT_COORD};
    }
    delete $el_hash->{$element};

    return wantarray ? @sub_elements : \@sub_elements;
}

sub rename_subelement {
    my $self = shift;
    my %args = @_;
    
    my $element     = $args{element};
    my $sub_element = $args{sub_element};
    my $new_name    = $args{new_name};
    
    croak "element does not exist\n"
      if ! exists $self->{ELEMENTS}{$element};

    my $sub_el_hash = $self->{ELEMENTS}{$element}{SUBELEMENTS};

    croak "sub_element does not exist\n"
      if !exists $sub_el_hash->{$sub_element};

    $sub_el_hash->{$new_name} += $sub_el_hash->{$sub_element};
    delete $sub_el_hash->{$sub_element};

    return;
}

#  delete the element, return a list of fully cleansed elements
sub delete_element {  
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if ! defined $args{element};

    my $element = $args{element};

    my @deleted_sub_elements =
        $self->get_sub_element_list(element => $element);

    %{$self->{ELEMENTS}{$element}{SUBELEMENTS}} = ();
    %{$self->{ELEMENTS}{$element}} = ();
    delete $self->{ELEMENTS}{$element};

    return wantarray ? @deleted_sub_elements : \@deleted_sub_elements;
}

#  remove a sub element label or group from within
#  a group or label element.
#  Usually called when deleting a group or label element
#  in a related object.
sub delete_sub_element {  
    my $self = shift;
    my %args = (@_);

    #croak "element not specified\n" if ! defined $args{element};
    #croak "subelement not specified\n" if ! defined $args{subelement};
    my $element     = $args{element} // croak "element not specified\n";
    my $sub_element = $args{subelement} // croak "subelement not specified\n";

    return if ! exists $self->{ELEMENTS}{$element};

    my $href = $self->{ELEMENTS}{$element};

    if (exists $href->{BASE_STATS}) {
        delete $href->{BASE_STATS}{REDUNDANCY};  #  gets recalculated if needed
        delete $href->{BASE_STATS}{VARIETY};
        if (exists $href->{BASE_STATS}{SAMPLECOUNT}) {
            $href->{BASE_STATS}{SAMPLECOUNT} -= $href->{SUBELEMENTS}{$sub_element};
        }
    }
    if (exists $href->{SUBELEMENTS}) {
        delete $href->{SUBELEMENTS}{$sub_element};
    }

    1;
}

#  array args version to avoid the args hash creation
#  (benchmarking indicates it takes a meaningful slab of time)
sub delete_sub_element_aa {
    my ($self, $element, $sub_element) = @_;
    
    croak "element not specified\n" if !defined $element;
    croak "subelement not specified\n" if !defined $sub_element;

    no autovivification;

    my $href = $self->{ELEMENTS}{$element}
     // return;

    if (exists $href->{BASE_STATS}) {
        delete $href->{BASE_STATS}{REDUNDANCY};  #  gets recalculated if needed
        delete $href->{BASE_STATS}{VARIETY};
        if (exists $href->{BASE_STATS}{SAMPLECOUNT}) {
            $href->{BASE_STATS}{SAMPLECOUNT} -= $href->{SUBELEMENTS}{$sub_element};
        }
    }
    delete $href->{SUBELEMENTS}{$sub_element};

    scalar keys %{$href->{SUBELEMENTS}};
}

sub exists_element {
    my $self = shift;
    my %args = @_;

    my $el = $args{element}
      // croak "element not specified\n";

    #  no explicit return for speed under pre-5.20 perls
    exists $self->{ELEMENTS}{$el};
}

sub exists_sub_element {
    my $self = shift;

    #return if ! $self->exists_element (@_);  #  no point going further if element doesn't exist

    my %args = @_;

    #defined $args{element} || croak "Argument 'element' not specified\n";
    #defined $args{subelement} || croak "Argument 'subelement' not specified\n";
    my $element = $args{element}
      // croak "Argument 'element' not specified\n";
    my $subelement = $args{subelement}
      // croak "Argument 'subelement' not specified\n";

    no autovivification;
    exists $self->{ELEMENTS}{$element}{SUBELEMENTS}{$subelement};
}

#  array args variant, with no testing of args - let perl warn as needed
sub exists_sub_element_aa {
    my ($self, $element, $subelement) = @_;

    no autovivification;
    exists $self->{ELEMENTS}{$element}{SUBELEMENTS}{$subelement};
}

sub add_values {  #  add a set of values and their keys to a list in $element
    my $self = shift;
    my %args = @_;

    my $element = $args{element}
      // croak "element not specified\n";
    delete $args{element};

    my $el_ref = $self->{ELEMENTS}{$element};
    #  we could assign it directly, but this ensures everything is uppercase
    #  {is uppercase necessary?}
    foreach my $key (keys %args) {
        $el_ref->{uc($key)} = $args{$key};
    }

    return;
}

#  increment a set of values and their keys to a list in $element
sub increment_values {
    my $self = shift;
    my %args = @_;

    my $element = $args{element}
      // croak "element not specified";
    delete $args{element};

    #  we could assign it directly, but this ensures everything is uppercase
    foreach my $key (keys %args) {  
        $self->{ELEMENTS}{$element}{uc($key)} += $args{$key};
    }

    return;
}

#  get a list from an element
#  returns a direct ref in scalar context
sub get_list_values {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element}
      // croak "element not specified\n";
    my $list = $args{list}
      // croak "List not defined\n";

    my $element_ref = $self->{ELEMENTS}{$element}
     // croak "Element $element does not exist in BaseStruct\n";

    return if ! exists $element_ref->{$list};
    return $element_ref->{$list} if ! wantarray;

    #  need to return correct type in list context
    return %{$element_ref->{$list}}
      if is_hashref($element_ref->{$list});

    return @{$element_ref->{$list}}
      if is_arrayref($element_ref->{$list});

    return;
}

sub get_hash_list_values {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};
    croak "element not specified\n" if not defined $element;

    my $list = $args{list};
    croak  "list not specified\n" if not defined $list;

    croak "element does not exist\n" if ! exists $self->{ELEMENTS}{$element};

    return if ! exists $self->{ELEMENTS}{$element}{$list};

    croak "list is not a hash\n"
        if !is_hashref($self->{ELEMENTS}{$element}{$list});

    return wantarray
        ? %{$self->{ELEMENTS}{$element}{$list}}
        : $self->{ELEMENTS}{$element}{$list};
}

#  array args version for speed
sub get_array_list_values_aa {
    my ($self, $element, $list) = @_;

    no autovivification;

    #$element // croak "Element not specified\n";
    #$list    // croak "List not specified\n";

    my $list_ref = $self->{ELEMENTS}{$element}{$list}
      // Biodiverse::BaseStruct::ListDoesNotExist->throw (
            message => "Element $element does not exist or does not have a list ref for $list\n",
        );

    #  does this need to be tested for?  Maybe caller beware is needed?
    croak "List is not an array\n"
        if !is_arrayref($list_ref);

    return wantarray ? @$list_ref : $list_ref;
}


sub get_array_list_values {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element} // croak "Element not specified\n";
    my $list    = $args{list}    // croak "List not specified\n";

    #croak "Element $element does not exist.  Do you need to rebuild the spatial index?\n"
    #  if ! exists $self->{ELEMENTS}{$element};

#if (!$self->{ELEMENTS}{$element}{$list}) {
#    print "PRIBLEMS with list $list in element $element";
#    say Data::Dumper::Dumper $self->{ELEMENTS}{$element};
#}

    my $list_ref = $self->{ELEMENTS}{$element}{$list}
      // Biodiverse::BaseStruct::ListDoesNotExist->throw (
            message => "Element $element does not exist or does not have a list ref for $list\n",
        );

    #  does this need to be tested for?  Maybe caller beware is needed?
    croak "List is not an array\n"
      if !is_arrayref($list_ref);

    return wantarray ? @$list_ref : $list_ref;
}

#  does a list exist in an element?
#  if so then return its type
sub exists_list {
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if not defined $args{element};
    croak "list not specified\n" if not defined $args{list};

    if (exists $self->{ELEMENTS}{$args{element}}{$args{list}}) {
        return ref $self->{ELEMENTS}{$args{element}}{$args{list}};
    }

    return;
}

sub add_lists {
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if not defined $args{element};

    my $element = $args{element};

    delete $args{element};
    @{$self->{ELEMENTS}{$element}}{keys %args} = values %args;

    return;
}

sub add_to_array_lists {
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};

    my $element = $args{element};

    delete $args{element};
    foreach my $key (keys %args) {
        push @{$self->{ELEMENTS}{$element}{$key}}, @{$args{$key}};
    }

    return;
}

sub add_to_hash_list {
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};

    defined $args{list} || croak "List not specified\n"; 
    my $list = $args{list};

    delete @args{qw /list element/};
    #  create it if not already there
    $self->{ELEMENTS}{$element}{$list} //= {};

    #  now add to it
    $self->{ELEMENTS}{$element}{$list}
      = {%{$self->{ELEMENTS}{$element}{$list}}, %args};

    return;
}

sub add_to_lists {  #  add to a list, create if not already there.
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};
    delete $args{element};

    my $use_ref = $args{use_ref};  #  set a direct ref?  currently overrides any previous values so take care
    delete $args{use_ref};  #  should it be in its own sub?

    foreach my $list_name (keys %args) {
        my $list_values = $args{$list_name};
        if ($use_ref) {
            $self->{ELEMENTS}{$element}{$list_name} = $list_values;
        }
        elsif (is_hashref($list_values)) {  #  slice assign
            my $listref = ($self->{ELEMENTS}{$element}{$list_name} //= {});
            @$listref{keys %$list_values} = values %$list_values;
        }
        elsif (is_arrayref($list_values)) {
            my $listref = ($self->{ELEMENTS}{$element}{$list_name} //= []);
            push @$listref, @$list_values;
        }
        else {
            croak "no valid list ref passed to add_to_lists, %args\n";
        }
    }

    return;
}

sub delete_lists {
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if not defined $args{element};
    croak "argument 'lists' not specified\n" if not defined $args{lists};

    my $element = $args{element};
    my $lists   = $args{lists};
    croak "argument 'lists' is not an array ref\n" if !is_arrayref($lists);

    foreach my $list (@$lists) {
        delete $self->{ELEMENTS}{$element}{$list};
    }

    return;
}

sub get_lists {
    my $self = shift;
    my %args = @_;

    croak "[BaseStruct] element not specified\n"
      if not defined $args{element};
    croak "[BaseStruct] element $args{element} does not exist\n"
      if !$self->exists_element (@_);

    my $element = $args{element};

    my @list;
    foreach my $tmp (keys %{$self->{ELEMENTS}{$element}}) {
        push @list, $tmp if (is_arrayref($self->{ELEMENTS}{$element}{$tmp}) 
                            || is_hashref($self->{ELEMENTS}{$element}{$tmp}));
    }

    return @list if wantarray;
    return \@list;
}

#  should just return the stats object
sub get_list_value_stats {
    my $self = shift;
    my %args = @_;
    my $list = $args{list};
    croak "List not specified\n" if not defined $list;
    my $index = $args{index};
    croak "Index not specified\n" if not defined $index ;

    my @data;
    foreach my $element ($self->get_element_list) {
        my $list_ref = $self->get_list_ref (
            element    => $element,
            list       => $list,
            autovivify => 0,
        );
        next if ! defined $list_ref;
        next if ! exists  $list_ref->{$index};
        next if ! defined $list_ref->{$index};  #  skip undef values

        push @data, $list_ref->{$index};
    }

    my %stats_hash = (
        MAX    => undef,
        MIN    => undef,
        MEAN   => undef,
        SD     => undef,
        PCT025 => undef,
        PCT975 => undef,
        PCT05  => undef,
        PCT95  => undef,
    );

    if (scalar @data) {  #  don't bother if they are all undef
        my $stats = $stats_class->new;
        $stats->add_data (\@data);

        %stats_hash = (
            MAX    => $stats->max,
            MIN    => $stats->min,
            MEAN   => $stats->mean,
            SD     => $stats->standard_deviation,
            PCT025 => scalar $stats->percentile (2.5),
            PCT975 => scalar $stats->percentile (97.5),
            PCT05  => scalar $stats->percentile (5),
            PCT95  => scalar $stats->percentile (95),
        );
    }

    return wantarray ? %stats_hash : \%stats_hash;
}

sub clear_lists_across_elements_cache {
    my $self = shift;
    my $keys = $self->get_cached_value_keys;
    my @keys_to_delete = grep {$_ =~ /^LISTS_ACROSS_ELEMENTS/} @$keys;
    $self->delete_cached_values (keys => \@keys_to_delete);
    return;
}

sub get_array_lists_across_elements {
    my $self = shift;
    return $self->get_lists_across_elements (list_method => 'get_array_lists');
}

sub get_hash_lists_across_elements {
    my $self = shift;
    return $self->get_lists_across_elements (list_method => 'get_hash_lists');
}


#  get a list of all the lists in all the elements
#  up to $args{max_search}
sub get_lists_across_elements {
    my $self = shift;
    my %args = @_;
    my $max_search = $args{max_search} || $self->get_element_count;
    my $no_private = $args{no_private} // 0;
    my $rerun = $args{rerun};
    my $list_method = $args{list_method} || 'get_hash_lists';

    croak "max_search arg is negative\n" if $max_search < 0;

    #  get from cache
    my $cache_name_listnames   = "LISTS_ACROSS_ELEMENTS_${list_method}_${no_private}";
    my $cache_name_last_update = "LISTS_ACROSS_ELEMENTS_MAX_SEARCH_${list_method}_${no_private}";
    my $cache_name_max_search  = "LISTS_ACROSS_ELEMENTS_LAST_UPDATE_TIME_${list_method}_${no_private}";

    my $cached_list = $self->get_cached_value ($cache_name_listnames);
    my $cached_list_max_search
        = $self->get_cached_value ($cache_name_max_search);

    my $last_update_time = $self->get_last_update_time;

    if (!defined $last_update_time) {  #  store for next time
        $self->set_last_update_time (time - 10); # ensure older given time precision
    }

    my $last_cache_time
        = $self->get_cached_value ($cache_name_last_update)
          || time;

    my $time_diff = defined $last_update_time
                    ? $last_cache_time - $last_update_time
                    : -1;

    if (1 
        && defined $cached_list                     #  return cache
        && ! $rerun
        && defined $cached_list_max_search          #  if it exists and
        && $time_diff > 0                           #  was updated after $self
        && $cached_list_max_search >= $max_search   #  the max search was
        ) {                                         #  the same or bigger

        #print "[BASESTRUCT] Using cached list items\n";
        return (wantarray ? @$cached_list : $cached_list);   
    }

    my $elements = $self->get_element_hash;

    my %tmp_hash;
    my $count = 0;

    SEARCH_FOR_LISTS:
    foreach my $elt (keys %$elements) {

        my $list = $self->$list_method (element => $elt);
        if (scalar @$list) {
            @tmp_hash{@$list} = undef;  #  we only care about the keys
        }
        $count++;
        last SEARCH_FOR_LISTS if $count > $max_search;
    }

    #  remove private lists if needed - should just use a grep
    if ($no_private) {
        foreach my $key (keys %tmp_hash) {
            if ($key =~ /^_/) {  #  not those starting with an underscore
                delete $tmp_hash{$key};
            }
        }
    }
    my @lists = keys %tmp_hash;

    #  cache
    $self->set_cached_values (
        $cache_name_listnames   => \@lists,
        $cache_name_max_search  => $max_search,
        $cache_name_last_update => $last_cache_time,
    );

    return wantarray ? @lists : \@lists;
}

#  get a list of hash lists with numeric values in them
#  ignores undef values
sub get_numeric_hash_lists {  
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};

    my %lists;
    LIST:
    foreach my $list ($self->get_hash_lists (element => $element)) {
        $lists{$list} = 1;
        foreach my $value (values %{$self->get_list_values(element => $element, list => $list)}) {
            next if ! defined $value ;
            if (! looks_like_number ($value)) {
                $lists{$list} = 0;
                next LIST;
            }
        }
    }

    return wantarray ? %lists : \%lists;
}

sub get_array_lists {
    my $self = shift;
    my %args = @_;

    my $element = $args{element}
      // croak "Element not specified, get_array_lists\n";

    no autovivification;

    my $el_ref = $self->{ELEMENTS}{$element}
      // croak "Element $element does not exist, cannot get hash list\n";

    my @list = grep {is_arrayref($el_ref->{$_})} keys %$el_ref;

    return wantarray ? @list : \@list;
}

sub get_hash_lists {
    my $self = shift;
    my %args = @_;

    my $element = $args{element}
      // croak "Element not specified, get_hash_lists\n";

    no autovivification;

    my $el_ref = $self->{ELEMENTS}{$element}
      // croak "Element $element does not exist, cannot get hash list\n";

    my @list = grep {is_hashref ($el_ref->{$_})} keys %$el_ref;

    return wantarray ? @list : \@list;
}

sub get_hash_list_keys_across_elements {
    my $self = shift;
    my %args = @_;

    my $list_name = $args{list};

    my $elements = $self->get_element_hash() || {};

    my %hash_keys;

    ELEMENT:
    foreach my $elt (keys %$elements) {
        my $hash = $self->get_list_ref (
            element    => $elt,
            list       => $list_name,
            autovivify => 0,
        );
        next ELEMENT if ! $hash;
        next ELEMENT if ! (is_hashref($hash));

        if (scalar keys %$hash) {
            @hash_keys{keys %$hash} = undef; #  no need for values and assigning undef is faster
        }
    }
    my @sorted_keys = sort keys %hash_keys;
    
    return wantarray ? @sorted_keys : [@sorted_keys];
}

#  return a reference to the specified list
#  - allows for direct operation on its values
sub get_list_ref {
    my $self = shift;
    my %args = (
        autovivify => 1,
        @_,
    );

    my $list    = $args{list}
      // croak "Argument 'list' not defined\n";
    my $element = $args{element}
      // croak "Argument 'element' not defined\n";

    #croak "Element $args{element} does not exist\n"
    #  if ! $self->exists_element (element => $element);

    no autovivification;

    my $el = $self->{ELEMENTS}{$element}
      // croak "Element $args{element} does not exist\n";

    if (! exists $el->{$list}) {
        return if ! $args{autovivify};  #  should croak?
        $el->{$list} = {};  #  should we default to a hash?
    }
    return $el->{$list};
}

sub rename_list {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $list = $args{list};
    my $new_name = $args{new_name};
    my $element  = $args{element};
    
    my $el = $self->{ELEMENTS}{$element}
      // croak "Element $args{element} does not exist\n";

    #croak "element $element does not contain a list called $list"
    return if !exists $el->{$list};

    $el->{$new_name} = $el->{$list};
    delete $el->{$list};

    return;
}

sub get_sample_count {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element}
      // croak "element not specified\n";

    my $href = $self->{ELEMENTS}{$element}{SUBELEMENTS}
      // return;  #  should croak? 

    my $count = sum (0, values %$href);

    return $count;
}

sub get_variety {
    my ($self, %args) = @_;

    no autovivification;

    my $element = $args{element} //
      croak "element not specified\n";

    my $href = $self->{ELEMENTS}{$element}{SUBELEMENTS}
      // return;  #  should croak? 

    #  no explicit return - minor speedup prior to perl 5.20
    scalar keys %$href;
}

sub get_variety_aa {
    no autovivification;

    my $href = $_[0]->{ELEMENTS}{$_[1]}{SUBELEMENTS}
      // return;  #  should croak? 

    #  no explicit return - minor speedup prior to perl 5.20
    scalar keys %$href;
}

sub get_redundancy {
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};

    return if ! $self->exists_element (element => $args{element});

    my $redundancy = eval {
        1 - $self->get_variety (element => $element)
          / $self->get_sample_count (element => $element)
    };

    return $redundancy;
}

#  calculate basestats for all elements - poss redundant now there are indices that do this
sub get_base_stats_all {
    my $self = shift;

    foreach my $element ($self->get_element_list) {
        $self->add_lists (
            element    => $element,
            BASE_STATS => $self->calc_base_stats(element => $element)
        );
    }

    return;
}

sub binarise_subelement_sample_counts {
    my $self = shift;

    foreach my $element ($self->get_element_list) {
        my $list_ref = $self->get_list_ref (element => $element, list => 'SUBELEMENTS');
        foreach my $val (values %$list_ref) {
            $val = 1;
        }
        $self->delete_lists(element => $element, lists => ['BASE_STATS']);
    }

    $self->delete_cached_values;

    return;
}

#  are the sample counts floats or ints?
#  Could use Scalar::Util::Numeric::isfloat here if speed becomes an issue
sub sample_counts_are_floats {
    my $self = shift;

    my $cached_val = $self->get_cached_value('SAMPLE_COUNTS_ARE_FLOATS');
    return $cached_val if defined $cached_val;
    
    foreach my $element ($self->get_element_list) {
        my $count = $self->get_sample_count (element => $element);

        next if !(fmod ($count, 1));

        $cached_val = 1;
        $self->set_cached_value(SAMPLE_COUNTS_ARE_FLOATS => 1);

        return $cached_val;
    }

    $self->set_cached_value(SAMPLE_COUNTS_ARE_FLOATS => 0);

    return $cached_val;
}


sub get_metadata_get_base_stats {
    my $self = shift;

    #  types are for GUI's benefit - should really add a guessing routine instead
    my $sample_type = eval {$self->sample_counts_are_floats} 
        ? 'Double'
        : 'Uint';

    my $types = [
        {VARIETY    => 'Int'},
        {SAMPLES    => $sample_type},
        {REDUNDANCY => 'Double'},
    ];

    my $property_keys = $self->get_element_property_keys;
    foreach my $property (sort @$property_keys) {
        push @$types, {$property => 'Double'};
    }

    return $self->metadata_class->new({types => $types});
}

sub get_base_stats {  #  calculate basestats for a single element
    my $self = shift;
    my %args = @_;

    defined $args{element} || croak "element not specified\n";

    my $element = $args{element};

    my %stats = (
        VARIETY    => $self->get_variety      (element => $element),
        SAMPLES    => $self->get_sample_count (element => $element),
        REDUNDANCY => $self->get_redundancy   (element => $element),
    );

    #  get all the user defined properties
    my $props = $self->get_list_ref (
        element    => $element,
        list       => 'PROPERTIES',
        autovivify => 0,
    );

    PROP:
    foreach my $prop (keys %$props) {
        $stats{$prop} = $props->{$prop};
    }

    return wantarray ? %stats : \%stats;
}

sub get_element_property_keys {
    my $self = shift;

    my $keys = $self->get_cached_value ('ELEMENT_PROPERTY_KEYS');

    return wantarray ? @$keys : $keys if $keys;

    my @keys = $self->get_hash_list_keys_across_elements (list => 'PROPERTIES');

    $self->set_cached_value ('ELEMENT_PROPERTY_KEYS' => \@keys);

    return wantarray ? @keys : \@keys;
}

sub get_element_properties {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};
    croak "element argument not given\n" if ! defined $element;

    my $props = $self->get_list_ref (
        element    => $element,
        list       => 'PROPERTIES',
        autovivify => 0,
    )
    || {};  # or a blank hash

    my %p = %$props;  #  make a copy;
    delete @p{qw /INCLUDE EXCLUDE/};  #  don't want these

    return wantarray ? %p : \%p;
}

sub get_element_properties_summary_stats {
    my $self = shift;
    my %args = @_;

    my $bd = $self->get_basedata_ref;
    if (Biodiverse::MissingBasedataRef->caught) {
        $bd = undef;
    }

    my $range_weighted = defined $bd ? $args{range_weighted} : undef;

    my %results;

    my %stats_data;
    foreach my $prop_name ($self->get_element_property_keys) {
        $stats_data{$prop_name} = [];
    }

    foreach my $element ($self->get_element_list) {    
        my %p = $self->get_element_properties(element => $element);
        while (my ($prop, $data) = each %stats_data) {
            next if ! defined $p{$prop};
            my $weight = $range_weighted ? $bd->get_range (element => $element) : 1;
            push @$data, ($p{$prop}) x $weight;
        }
    }

    while (my ($prop, $data) = each %stats_data) {
        next if not scalar @$data;

        my $stats_object = $stats_class->new;
        $stats_object->add_data($data);
        foreach my $stat (qw /mean sum standard_deviation count/) { 
            $results{$prop}{$stat} = $stats_object->$stat;
        }
    }

    return wantarray ? %results : \%results;
}

sub has_element_properties {
    my $self = shift;
    
    my @keys = $self->get_element_property_keys;
    
    return scalar @keys;
}

#  return true if the labels are all numeric
sub elements_are_numeric {
    my $self = shift;
    foreach my $element ($self->get_element_list) {
        return 0 if ! looks_like_number($element);
    }
    return 1;  # if we get this far then they must all be numbers
}

#  like elements_are_numeric, but checks each axis
#  this is all or nothing
sub element_arrays_are_numeric {
    my $self = shift;
    foreach my $element ($self->get_element_list) {
        my $array = $self->get_element_name_as_array (element => $element);
        foreach my $iter (@$array) {
            return 0 if ! looks_like_number($iter);
        }
    }
    return 1;  # if we get this far then they must all be numbers
}


sub DESTROY {
    my $self = shift;
    #my $name = $self->get_param ('NAME');
    #print "DESTROYING BASESTRUCT $name\n";
    #undef $name;
    my $success = $self->set_param (BASEDATA_REF => undef);

    #$self->_delete_params_all;

    foreach my $key (sort keys %$self) {  #  clear all the top level stuff
        #print "Deleting BS $key\n";
        #$self->{$key} = undef;
        delete $self->{$key};
    }
    undef %$self;

    #  let perl handle the rest
    return;
}

1;

__END__

=head1 NAME

Biodiverse::BaseStruct

=head1 SYNOPSIS

  use Biodiverse::BaseStruct;
  $object = Biodiverse::BaseStruct->new();

=head1 DESCRIPTION

TO BE FILLED IN

=head1 METHODS

=over

=item INSERT METHODS

=back

=head1 REPORTING ERRORS

Use the issue tracker at http://www.purl.org/biodiverse

=head1 COPYRIGHT

Copyright (c) 2010 Shawn Laffan. All rights reserved.  

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut

