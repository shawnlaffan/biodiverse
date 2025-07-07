package Biodiverse::BaseStruct::Export;

use strict;
use warnings;
use 5.022;

our $VERSION = '4.99_005';

use Carp;
use English ( -no_match_vars );
use Scalar::Util qw /looks_like_number reftype/;
use List::Util qw /min max sum any/;
use List::MoreUtils qw /first_index/;
use File::Basename;
use Path::Tiny qw /path/;
use POSIX qw /fmod floor/;
use Time::localtime;
use Ref::Util qw { :all };
use Sort::Key::Natural qw /natsort rnatsort/;
use Geo::GDAL::FFI 0.06 qw /GetDriver/;
#  silence a used-once warning - clunky
{
    my $xx_frob_temp_zort = $FFI::Platypus::TypeParser::ffi_type;
    my $xx_frob_temp_zert = $FFI::Platypus::keep;
}

my $EMPTY_STRING = q{};

use parent qw /Biodiverse::Common/; #  access the common functions as methods

my $metadata_class = 'Biodiverse::Metadata::BaseStruct';
use Biodiverse::Metadata::BaseStruct;

use Biodiverse::Metadata::Export;
my $export_metadata_class = 'Biodiverse::Metadata::Export';

use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';



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
        $fh = $self->get_file_handle (
            mode      => '>',
            file_name => $filename,
        );
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

sub get_rgb_geotiff_export_metadata {
    my $self = shift;

    my $tooltip = <<'TOOLTIP'
Generate RGBA format TIFF files
of each index that has been
displayed in the GUI.
This allows reproduction of
colour stretches using GIS software.
Indices that have not been
displayed are not exported.
TOOLTIP
  ;

    my $metadata = [ 
        {
            name        => 'generate_rgb_rasters',
            label_text  => 'Generate RGB rasters',
            tooltip     => $tooltip,
            type        => 'boolean',
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
            $self->get_rgb_geotiff_export_metadata(),
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

sub get_metadata_export_rgb_geotiff {
    my $self = shift;

    my %args = (
        format => 'RGB GeoTIFF',
        parameters => [
            $self->get_common_export_metadata(),
            #$self->get_raster_export_metadata(),
        ],
    ); 

    return wantarray ? %args : \%args;
}

sub export_rgb_geotiff {
    my $self = shift;
    my %args = @_;

    $self->write_rgb_geotiff (%args);

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
            name        => 'shape_export_comment',
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
        if( !scalar @elements) {
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
    my $use_z;
    if (scalar @cell_sizes > 2) {
        @axes_to_use = (0, 1, 2);  #  we use Z in this case
        $use_z = 1;
    }

    my $half_csizes = [];
    foreach my $size (@cell_sizes[@axes_to_use]) {
        push @$half_csizes, $size > 0 ? $size / 2 : 0.5;
    }

    my $first_el_coord
      = $self->get_element_name_coord (element => $elements[0]);

    my @axis_col_specs_gdal;
    foreach my $axis (0 .. $#$first_el_coord) {
        my $csize = $cell_sizes[$axis];
        if ($csize < 0) {
            push @axis_col_specs_gdal,
              { Name => "AXIS_$axis",
                Type => 'String',
              };
        }
        else {
            push @axis_col_specs_gdal,
              { Name => "AXIS_$axis",
                Type => 'Real',
              };
        }
    }

    my @list_col_specs_gdal;
    if (defined $list_name) {  # repeated polys per list item
        push @list_col_specs_gdal,
          {Name => 'KEY',   Type => 'String'},
          {Name => 'VALUE', Type => $args{list_val_type} // 'Real'},
    }

    my $layer = GetDriver('ESRI Shapefile')
    ->Create($file . '.shp')
    ->CreateLayer({
        Name => 'export',
        GeometryType => ucfirst (lc $shape_type),
        Fields => [
            {
                Name => 'ELEMENT',
                Type => 'String'
            },
            @axis_col_specs_gdal,
            @list_col_specs_gdal,
        ],
    });

  NODE:
    foreach my $element (@elements) {
        my $coord_axes = $self->get_element_name_coord (element => $element);
        my $name_axes  = $self->get_element_name_as_array (element => $element);

        my %axis_col_data
          = (map
            {; "AXIS_$_" => $name_axes->[$_]}
            (0 .. $#$first_el_coord));

        my $wkt;
        my $z_wkt = $use_z ? ' Z' : '';
        if ($shape_type eq 'POLYGON')  {
            my ($x, $y) = @{$coord_axes}[@axes_to_use];
            my ($width, $height) = @{$half_csizes}[@axes_to_use];
            my $min_x = $x - $width;
            my $max_x = $x + $width;
            my $min_y = $y - $height;
            my $max_y = $y + $height;
            my $z = $use_z
                  ? $coord_axes->[$axes_to_use[2]]
                  : '';

            $wkt = "POLYGON$z_wkt (("
                 . "$min_x $min_y $z, "
                 . "$min_x $max_y $z, "
                 . "$max_x $max_y $z, "
                 . "$max_x $min_y $z, "
                 . "$min_x $min_y $z"
                 . '))';
        }
        elsif ($shape_type eq 'POINT') {
            my @pt = @{$coord_axes}[@axes_to_use];
            $wkt = "POINT$z_wkt ("
                 . join (' ', @pt)
                 . ")";
        }

        my @data_for_gdal_layer;
        if ($list_name) {
            my %list_data = $self->get_list_values (
                element => $element,
                list    => $list_name,
            );

            # write a separate shape for each label
            foreach my $key (natsort keys %list_data) {
                my %data = (
                    ELEMENT => $element,
                    %axis_col_data,
                    KEY     => $key,
                    VALUE   => ($list_data{$key} // $nodata),
                );
                push @data_for_gdal_layer, \%data;
            }
        }
        else {
            my %data = (
                ELEMENT => $element,
                %axis_col_data,
            );
            push @data_for_gdal_layer, \%data;
        }

        foreach my $data_hr (@data_for_gdal_layer) {
            my $f = Geo::GDAL::FFI::Feature->new($layer->GetDefn);
            foreach my $key (keys %$data_hr) {
                $f->SetField(uc ($key) => $data_hr->{$key});
            }
            my $g = Geo::GDAL::FFI::Geometry->new(WKT => $wkt);
            $f->SetGeomField($g);
            $layer->CreateFeature($f);
        }
    }

    #  close off
    $layer = undef;

    return;
}

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

    $args{file} = path($args{file})->absolute;

    return;
}


sub list_contents_are_symmetric {
    my ($self, %args) = @_;
    
    my $list_name = $args{list_name};
    croak 'argument list_name undefined'
      if !defined $list_name;

    #  Check if the lists in this object are symmetric.  Check the list type as well.
    #  Assumes type is constant across all elements, and that all elements have this list.
    my $last_contents_count = -1;
    my $is_asym = 0;
    my %list_keys;
    my $prev_list_keys;

    my $check_elements = $self->get_element_list;

    say "[BASESTRUCT] Checking elements for list symmetry: $list_name";
    my $i = -1;
  CHECK_ELEMENTS:
    foreach my $check_element (@$check_elements) {  # sample the lot
        $i++;
        last CHECK_ELEMENTS if ! defined $check_element;

        my $values = $self->get_list_values (
            element => $check_element,
            list    => $list_name,
        );
        
        $values //= {};

        if (is_hashref($values)) {
            if (defined $prev_list_keys and $prev_list_keys != scalar keys %$values) {
                #  This list is of different length from the previous.
                #  Allows for zero length lists.
                $is_asym ++;
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

    return !$is_asym;
}

#  control whether a file is written symetrically or not
sub to_table {
    my $self = shift;
    my %args = @_;

    my $as_symmetric = $args{symmetric} || 0;

    croak "[BaseStruct] neither of 'list' or 'list_names' "
          . "arguments specified\n"
      if !defined $args{list_names} and !defined $args{list};
    croak "[BaseStruct] cannot specify both of 'list' "
          . "and 'list_names' arguments\n"
      if defined $args{list_names} && defined $args{list};

    my $list_names = $args{list_names} // [$args{list}];
    
    croak 'list_names arg must be an array ref'
      if !is_arrayref $list_names;

    my $is_asym
        = any
          {!$self->list_contents_are_symmetric (list_name => $_)}
          @$list_names;
    my $list_string = join ',', @$list_names;

    my $data;

    if (! $as_symmetric and $is_asym) {
        say "[BASESTRUCT] Converting asymmetric data from $list_string "
              . "to asymmetric table";
        $data = $self->to_table_asym (%args, list_names => $list_names);
    }
    elsif ($as_symmetric && $is_asym) {
        say "[BASESTRUCT] Converting asymmetric data from $list_string "
              . "to symmetric table";
        $data = $self->to_table_asym_as_sym (%args, list_names => $list_names);
    }
    else {
        say "[BASESTRUCT] Converting symmetric data from $list_string "
              . "to symmetric table";
        $data = $self->to_table_sym (%args, list_names => $list_names);
    }

    return wantarray ? @$data : $data;
}

#  sometimes we have names of unequal length
#  should probably cache this
sub get_longest_name_array_length {
    my $self = shift;

    my $longest = -1;
    foreach my $element ($self->get_element_list) {
        my $array = $self->get_element_name_as_array (
            element => $element,
        );
        $longest = max ($longest, scalar @$array);
    }

    return $longest;
}

#  Write parts of the object to a CSV file
#  Assumes these are always hashes, which may blow
#  up in our faces later.  We'll fix it then
sub to_table_sym {  
    my $self = shift;
    my %args = @_;
    defined $args{list_names} || croak "list_names not defined\n";

    my $list_names = $args{list_names};
    croak "list_names arg is not an array ref\n"
      if !is_arrayref $list_names;

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

    #  only need to search first element,
    #  as the lists must be present for symmetry to apply
    my @print_order;
    foreach my $list_name (@$list_names) {
        my $list_hash_ref = $self->get_hash_list_values(
            element => $elements[0],
            list    => $list_name,
        );
        #  check for dups, as we don't handle them yet
        if (@$list_names > 1) {
            croak 'Cannot export duplicate keys across multiple lists'
              if any {exists $list_hash_ref->{$_}} @print_order;
        }
        push @print_order, natsort keys %$list_hash_ref;
    }
    my @quoted_print_order =
        map {$quote_el_names ? "$quote_char$_$quote_char" : $_}
        @print_order;

    #  need the number of element components for the header
    my @header = ('ELEMENT');
    my @element_axes;
    if (! $no_element_array) {
        @element_axes = $self->get_axis_header_fields_for_table;
        push @header, @element_axes;
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
            my @name_array = $self->get_element_name_as_array (element => $element);
            if (@name_array < @element_axes) {
                push @name_array, ('') x (@element_axes - @name_array);
            }
            push @basic, @name_array;
        }
        
        my %aggregated_data;
        foreach my $list_name (@$list_names) {
            my $list_ref = $self->get_hash_list_values(
                element => $element,
                list    => $list_name,
            );
            @aggregated_data{keys %$list_ref} = values %$list_ref;
        }

        if ($one_value_per_line) {  
            #  repeat the elements, once for each value or key/value pair
            if (!defined $no_data_value) {
                foreach my $key (@print_order) {
                    push @data, [@basic, $key, $aggregated_data{$key}];
                }
            }
            else {  #  need to change some values
                foreach my $key (@print_order) {
                    my $val = $aggregated_data{$key} // $no_data_value;
                    push @data, [@basic, $key, $val];
                }
            }
        }
        else {
            if (!defined $no_data_value) {
                push @data, [@basic, @aggregated_data{@print_order}];
            }
            else {
                my @vals = map {$_ // $no_data_value} @aggregated_data{@print_order};
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
    defined $args{list_names} || croak "list_names not specified\n";

    my $list_names = $args{list_names};
    croak "list_names arg is not an array ref\n"
      if !is_arrayref $list_names;

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
    my @element_axes;
    if (! $no_element_array) {
         @element_axes = $self->get_axis_header_fields_for_table;
         push @header, @element_axes;
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
            my @name_array = $self->get_element_name_as_array (element => $element);
            if (@name_array < @element_axes) {
                push @name_array, ('') x (@element_axes - @name_array);
            }
            push @basic, @name_array;
        }
        if ($one_value_per_line) {  #  repeats the elements, once for each value or key/value pair
            foreach my $list_name (@$list_names) {
                #  get_list_values returns a list reference in scalar context
                #  - could be a hash or an array
                my $list_ref =  $self->get_list_values (element => $element, list => $list_name);
                if (is_arrayref($list_ref)) {
                    foreach my $value (@$list_ref) {
                        #  preserve internal ordering - useful for extracting iteration based values
                        push @data, [@basic, $value // $no_data_value];
                    }
                }
                elsif (is_hashref($list_ref)) {
                    foreach my $key (natsort keys %$list_ref) {
                        push @data, [@basic, $key, $list_ref->{$key} // $no_data_value];
                    }
                }
            }
        }
        else {
            my @line = @basic;
            foreach my $list_name (@$list_names) {
                #  get_list_values returns a list reference in scalar context
                #  - could be a hash or an array
                my $list_ref =  $self->get_list_values (element => $element, list => $list_name);
                if (is_arrayref($list_ref)) {
                    #  preserve internal ordering - useful for extracting iteration based values
                    push @line, map {$_ // $no_data_value} @$list_ref;  
                }
                elsif (is_hashref($list_ref)) {
                    foreach my $key (natsort keys %$list_ref) {
                        push @line, ($key, $list_ref->{$key} // $no_data_value);
                    }
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

    defined $args{list_names} || croak "list_names not specified\n";

    my $list_names = $args{list_names};
    croak "list_names arg is not an array ref\n"
      if !is_arrayref $list_names;

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

    my $quote_char = $self->get_param('QUOTES');

    say "[BASESTRUCT] Getting keys...";
    
    my @print_order;

    foreach my $list_name (@$list_names) {
        my %indices_hash;

        BY_ELEMENT1:
          foreach my $elt (keys %$elements) {
              #  should use a method here
              my $sub_list = $elements->{$elt}{$list_name};
              if (is_arrayref($sub_list)) {
                  @indices_hash{@$sub_list} = (undef) x scalar @$sub_list;
              }
              elsif (is_hashref($sub_list)) {
                  @indices_hash{keys %$sub_list} = (undef) x scalar keys %$sub_list;
              }
          }
          #  check for dups
          if (@$list_names > 1) {
              croak "cannot export duplicated keys across multiple lists\n"
                if any {exists $indices_hash{$_}} @print_order;
          }
          push @print_order, natsort keys %indices_hash;
    }
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
    my @element_axes;
    if (! $no_element_array) {
        @element_axes = $self->get_axis_header_fields_for_table;
        push @header, @element_axes;
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
    
    my %default_indices_hash;
    @default_indices_hash{@print_order} = ($no_data_value) x @print_order;

    BY_ELEMENT2:
    foreach my $element (@elements) {
        my $el = $quote_el_names ? "$quote_char$element$quote_char" : $element;
        my @basic = ($el);

        if (! $no_element_array) {
            my @name_array = $self->get_element_name_as_array (element => $element);
            if (@name_array < @element_axes) {
                push @name_array, ('') x (@element_axes - @name_array);
            }
            push @basic, @name_array;
        }

        my %data_hash = %default_indices_hash;

        foreach my $list_name (@$list_names) {
            my $list = $self->get_list_ref (
                element => $element,
                list    => $list_name,
                autovivify => 0,
            );
            if (is_arrayref($list)) {
                foreach my $val (@$list) {
                    $data_hash{$val}++;  #  track dups
                }
            }
            elsif (is_hashref($list)) {
                @data_hash{keys %$list} = values %$list;
            }
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

sub get_axis_header_fields_for_table {
    my $self = shift;

    my $i = 0;
    #  get the number of element columns
    my $max_element_array_len = $self->get_longest_name_array_length;

    my @axes;
    foreach (0 .. $max_element_array_len - 1) {
        push (@axes, 'Axis_' . $i);
        $i++;
    }

    return wantarray ? @axes : \@axes;
}

#  write a table out as a series of ESRI asciigrid files, one per field based on row 0.
#  skip any that contain non-numeric values
sub write_table_asciigrid {
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    is_arrayref($data) || croak "data arg must be an array ref\n";

    my $file = $args{file} || croak "file arg not specified\n";
    my ($name, $path, $suffix) = fileparse (path($file)->absolute, qr/\.asc/, qr/\.txt/);
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

        my $filename    = path($path, $this_file)->stringify;
        $filename      .= $suffix;
        $file_names[$i] = $filename;
        push @$file_list_ref, $filename; # record file in list

        my $this_fh
          = $self->get_file_handle (file_name => $filename, mode => '>');

        $fh[$i] = $this_fh;
        print $this_fh "nrows $nrows\n";
        print $this_fh "ncols $ncols\n";
        print $this_fh "xllcenter $min[0]\n";
        print $this_fh "yllcenter $min[1]\n";
        print $this_fh "cellsize $res[0]\n";  #  CHEATING 
        print $this_fh "nodata_value $no_data\n";
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
    my ($name, $path, $suffix) = fileparse (path($file)->absolute, qr/\.flt/);
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

        my $filename = path($path, $this_file)->stringify;
        $filename .= $suffix;
        $file_names[$i] = $filename;

        my $this_fh = $self->get_file_handle (file_name => $filename, mode => '>');

        binmode $this_fh;
        $fh[$i] = $this_fh;

        my $header_file = $filename;
        $header_file =~ s/$suffix$/\.hdr/;
        my $fh_hdr = $self->get_file_handle (
            file_name => $header_file,
            mode      => '>',
        );

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
    my ($name, $path, $suffix) = fileparse (path($file)->stringify, qr'\.gri');
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

    my @fh;  #  file handles
    my @file_names;
    foreach my $i (@band_cols) {
        #next if $coord_cols_hash{$i};  #  skip if it is a coordinate
        my $this_file = $name . "_" . $header->[$i];
        $this_file = $self->escape_filename (string => $this_file);

        my $filename = path($path, $this_file)->stringify;
        $filename .= $suffix;
        $file_names[$i] = $filename;

        my $fh = $self->get_file_handle (
            file_name => $filename,
            mode      => '>',
        );

        binmode $fh;
        $fh[$i] = $fh;

        my $header_file = $filename;
        $header_file =~ s/$suffix$/\.grd/;
        my $fh_hdr = $self->get_file_hande (
            file_name => $header_file,
            mode      => '>',
        );

        my $time = localtime;
        my $create_time = ($time->year + 1900) . ($time->mon + 1) . $time->mday;
        my $minx = $min[0] - $res[0] / 2;
        my $maxx = $max[0] + $res[0] / 2;
        my $miny = $min[1] - $res[1] / 2;
        my $maxy = $max[1] + $res[1] / 2;
        my $stats = $self->get_list_value_stats (
            list  => $args{list},
            index => $header->[$i],
        );

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
        print {$fh_hdr} $diva_hdr;
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

#  write a table out as a series of geotiff files,
#  one per field based on row 0.
#  Skip any fields that contain non-numeric values
sub write_table_geotiff {
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    is_arrayref($data) || croak "data arg must be an array ref\n";

    my $file = $args{file} || croak "file arg not specified\n";
    my ($name, $path, $suffix) = fileparse (path($file)->absolute, qr/\.tif{1,2}/);
    if (! defined $suffix || $suffix eq q{}) {  #  clear off the trailing .tif and store it
        $suffix = '.tif';
    }
    
    my $generate_rgb_rasters = $args{generate_rgb_rasters};
    
    my $band_type = $args{band_type} // 'Float32';  #  should probably detect this from the data
    #  need more
    my %pack_codes = (
        Float32 => 'f',
        UInt32  => 'L',
    );
    my $pack_code = $pack_codes{$band_type};
    croak "Unsupported band_type $band_type\n"
      if !defined $pack_code;

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

    my $ll_cenx = $min[0] - 0.5 * $res[0];
    my $ul_cenx = $min[0] - 0.5 * $res[0];
    my $ll_ceny = $min[1] - 0.5 * $res[1];
    my $ul_ceny = $max[1] + 0.5 * $res[1];
    my $tfw_tfm = [$ul_cenx, $res[0], 0, $ul_ceny, 0, -$res[1]];

    my @file_names;
    my %index_fname_hash;
    foreach my $i (@band_cols) {
        my $this_file = $name . "_" . $header->[$i];
        $this_file = $self->escape_filename (string => $this_file);

        my $filename = path($path, $this_file)->stringify;
        $filename   .= $suffix;
        $file_names[$i] = $filename;
        $index_fname_hash{$header->[$i]} = $filename;
    }

    my %coords;
    my @bands;

    my $y_col = -1;
    foreach my $y (reverse ($min_ids[1] .. $max_ids[1])) {
        $y_col++;
        my $x_col = -1;
        foreach my $x ($min_ids[0] .. $max_ids[0]) {
            $x_col++;

            my $coord_id = join (':', $x, $y);
            foreach my $i (@band_cols) { 
                next if $coord_cols_hash{$i};  #  skip if it is a coordinate
                my $value = $data_hash{$coord_id}[$i] // $no_data;
                $bands[$i][$y_col][$x_col] = 0+$value;
            }
        }
    }

    my $format = "GTiff";
    my $driver = Geo::GDAL::FFI::GetDriver( $format );

    foreach my $i (@band_cols) {
        my $f_name = $file_names[$i];
        my $pdata  = $bands[$i];

        my $out_raster
          = $driver->Create($f_name, {
                Width    => $ncols,
                Height   => $nrows,
                Bands    => 1,
                DataType => $band_type
            });

        $out_raster->SetGeoTransform ($tfw_tfm);
        my $out_band = $out_raster->GetBand();
        $out_band->SetNoDataValue ($no_data);
        $out_band->Write($pdata, 0, 0, $ncols, $nrows);
    }
    

    if ($generate_rgb_rasters) {
        $self->write_rgb_geotiff (%args);
    }

    return;
}

#  write a table out as a series of ESRI floatgrid files,
#  one per field based on row 0.
#  Skip any fields that contain non-numeric values
sub write_rgb_geotiff {
    my ($self, %args) = @_;

    my $file = $args{file} || croak "file arg not specified\n";
    my ($name, $path, $suffix) = fileparse (path($file)->absolute, qr/\.tif{1,2}/);
    if (! defined $suffix || $suffix eq q{}) {  #  clear off the trailing .tif and store it
        $suffix = '.tif';
    }

    my $format = "GTiff";
    my $driver = Geo::GDAL::FFI::GetDriver( $format );

    #  generate a four band RGB tiff
    #  https://gis.stackexchange.com/questions/247906/how-to-create-an-rgb-geotiff-file-raster-from-bands-using-the-gdal-python-module
    my $cached_colours = $self->get_cached_value ('GUI_CELL_COLOURS');
    my $list_name = $args{list};  #  should handle {list_names} also
    my $indices = $self->get_hash_list_keys_across_elements (list => $list_name);

    foreach my $index (@$indices) {
        no autovivification;
        my $href = $cached_colours->{$list_name}{$index};
        next if !$href;
        
        my $this_file = "${name}_${index}_rgb";
        $this_file = $self->escape_filename (string => $this_file);

        my $f_name = path($path, $this_file)->stringify;
        $f_name   .= $suffix;

        #  we really should cache using a basestruct        
        my $bs = Biodiverse::BaseStruct->new (
            NAME => $f_name,
            CELL_SIZES   => [$self->get_cell_sizes],
            CELL_ORIGINS => [$self->get_cell_origins],
        );
        foreach my $elt (keys %$href) {
            # my @rgb_arr = $href->{$elt} =~ /([a-fA-F\d]{4})/g;
            # @rgb_arr = map {0 + hex "0x$_"} @rgb_arr;
            my %rgb_hash;
            my $rgb = $href->{$elt};
            if (is_arrayref $rgb) {
                #  rgb vals in [0,1]
                @rgb_hash{qw/red green blue/} = map {$_ * (2**16-1)} @$rgb;
            }
            elsif (!is_ref $rgb) {
                #  rgb vals in [0,255] as, e.g., rgb(123,201,0)
                my @arr = $rgb =~ /\d+/g;
                $rgb = [@arr];
                @rgb_hash{qw/red green blue/} = map {$_ * 255} @$rgb;
            }
            $bs->add_element (element => $elt);
            $bs->add_lists (
                element => $elt,
                rgb     => \%rgb_hash,
            );
        }
        my $data_table = $bs->to_table (list => 'rgb', symmetric => 1);
        my $r = $self->raster_export_process_args (
            %args,
            data => $data_table,
            no_data_value => 0,
        );
        my @min       = @{$r->{MIN}};
        my @max       = @{$r->{MAX}};
        my @min_ids   = @{$r->{MIN_IDS}};
        my @max_ids   = @{$r->{MAX_IDS}};
        my @band_cols = @{$r->{BAND_COLS}};
        my $header    =   $r->{HEADER};
        #my $no_data   =   $r->{NODATA};
        my @res       = @{$r->{RESOLUTIONS}};
        my $ncols     =   $r->{NCOLS};
        my $nrows     =   $r->{NROWS};
    
        my %coord_cols_hash = %{$r->{COORD_COLS_HASH}};
    
        my $ll_cenx = $min[0] - 0.5 * $res[0];
        my $ul_cenx = $min[0] - 0.5 * $res[0];
        my $ll_ceny = $min[1] - 0.5 * $res[1];
        my $ul_ceny = $max[1] + 0.5 * $res[1];
        my $tfw_tfm = [$ul_cenx, $res[0], 0, $ul_ceny, 0, -$res[1]];
        my $rgb_data_hash = $r->{DATA_HASH};
        my $y_col = -1;
        my @rgb_band_cols = (5,4,3);  #  rgb alpha sorted
        my @rgb_band_data;
        state $max_val = 2**16 - 1;  # UInt16
        foreach my $y (reverse ($min_ids[1] .. $max_ids[1])) {
            $y_col++;
            my $x_col = -1;
            foreach my $x ($min_ids[0] .. $max_ids[0]) {
                $x_col++;
                my $coord_id = join (':', $x, $y);
                foreach my $i (@rgb_band_cols) { 
                    next if $coord_cols_hash{$i};  #  skip if it is a coordinate
                    my $value = $rgb_data_hash->{$coord_id}[$i];
                    if (defined $value) {
                        $rgb_band_data[$i][$y_col][$x_col] = 0+$value;
                        $rgb_band_data[6][$y_col][$x_col]  //= $max_val;
                    }
                    else {
                        $rgb_band_data[$i][$y_col][$x_col] = 0;
                        $rgb_band_data[6][$y_col][$x_col]  = 0;
                    }
                }
            }
        }
        
        my $out_raster
          = $driver->Create($f_name, {
                Width    => $ncols,
                Height   => $nrows,
                Bands    => 4,
                DataType => 'UInt16',
            });
        $out_raster->SetGeoTransform ($tfw_tfm);
        my $band_id = 0;
        #  ensure rgba sort order
        foreach my $rgb_data (@rgb_band_data[5,4,3,6]) {
            #next if !defined $rgb_data;
            $band_id++;
            my $out_band = $out_raster->GetBand($band_id);
            $out_band->Write($rgb_data, 0, 0, $ncols, $nrows);
            $out_band->SetMetadata({   #  helps with some displays
                STATISTICS_MAXIMUM => "$max_val",
                STATISTICS_MINIMUM => '0',
            }, '');
        }
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
        = fileparse (path($file)->absolute, qr/\.ers/);

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

    my $data_file = path($path, $name)->stringify;
    my $ofh = $self->get_file_handle (
        file_name => $data_file,
        mode      => '>',
    );
    binmode $ofh;

    my ($ncols, $nrows) = (0, 0);

    foreach my $y (reverse ($min_ids[1] .. $max_ids[1])) {

        $nrows ++;
        foreach my $band (@band_cols) {
            $ncols = 0;

            foreach my $x ($min_ids[0] .. $max_ids[0]) {

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

    croak "Unable to write to $data_file\n"
      if !$ofh->close;

    print "[BASESTRUCT] Write to file $data_file successful\n";

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

    my $header_file = path($path, $name)->stringify . $suffix;
    my $header_fh = $self->get_file_handle (
        file_name => $header_file,
        mode      => '>:utf8',
    );

    say {$header_fh} (join "\n", @header);

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

1;
