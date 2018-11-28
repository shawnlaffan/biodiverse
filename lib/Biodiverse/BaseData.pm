package Biodiverse::BaseData;

#  package containing methods to access and store a Biodiverse BaseData object
use 5.022;

use strict;
use warnings;

#  avoid redefined warnings due to
#  https://github.com/rurban/Cpanel-JSON-XS/issues/65
use JSON::PP ();

use Carp;
use Data::Dumper;
use POSIX qw {fmod floor ceil};
use Scalar::Util qw /looks_like_number blessed reftype/;
use List::Util 1.45 qw /max min sum any all none notall pairs uniq/;
use IO::File;
use File::BOM qw /:subs/;
use Path::Class;
use POSIX qw /floor/;
use Geo::Converter::dms2dd qw {dms2dd};
use Regexp::Common qw /number/;
use Data::Compare ();
use Geo::ShapeFile;

use Ref::Util qw { :all };
use Sort::Key::Natural qw /natkeysort/;
use Spreadsheet::Read 0.60;

use Geo::GDAL::FFI 0.0601;
#  dirty and underhanded
BEGIN {
    if ($Geo::GDAL::FFI::VERSION <= 0.0601) {
        no strict 'refs';
        no warnings 'redefine';
        *Geo::GDAL::FFI::SpatialReference::DESTROY = sub {
            my $self = shift;
            #  OSRGetReferenceCount method not yet implemented
            my $refcount = (Geo::GDAL::FFI::OSRReference ($$self)-1);
            Geo::GDAL::FFI::OSRDereference ($$self);  #  immediately decrement 
            if ($refcount == 0) {
                #warn "Calling DESTROY method for $$self\n";
                Geo::GDAL::FFI::OSRDestroySpatialReference($$self);
            }
        };
    }
}

#  these are here for PAR purposes to ensure they get packed
#  Spreadsheet::Read calls them as needed
#  (not sure we need all of them, though)
require Spreadsheet::ReadSXC;
require Spreadsheet::ParseExcel;
require Spreadsheet::ParseXLSX;

#require Spreadsheet::XLSX;  latest version does not install

use English qw { -no_match_vars };

#use Math::Random::MT::Auto qw /rand srand shuffle/;

use Biodiverse::BaseStruct; #  main output goes to a Biodiverse::BaseStruct object
use Biodiverse::Cluster;  #  we use methods to control the cluster objects
use Biodiverse::Spatial;
use Biodiverse::RegionGrower;
use Biodiverse::Index;
use Biodiverse::Randomise;
use Biodiverse::Progress;
use Biodiverse::Indices;

        
use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';

our $VERSION = '2.99_001';

use parent qw {Biodiverse::Common};

#  how much input file to read in one go
our $input_file_chunk_size   = 10000000;
our $lines_to_read_per_chunk = 50000;

our $EMPTY_STRING = q{};
our $bytes_per_MB = 1056784;

sub new {
    my $class = shift;

    #my %self;

    #my $self = {};
    my $self = bless {}, $class;

    my %args = @_;

    # try to load from a file if the file arg is given
    if ( defined $args{file} ) {
        my $file_loaded;
        $file_loaded = $self->load_file(@_);
        return $file_loaded;
    }

    #  we got this far, so create a new and empty object

    my %exclusion_hash = (
        LABELS => {
            minVariety    => undef,
            maxVariety    => undef,
            minSamples    => undef,
            maxSamples    => undef,
            minRedundancy => undef,
            maxRedundancy => undef,
            min_range     => undef,
            max_range     => undef,
        },
        GROUPS => {
            minVariety    => undef,
            maxVariety    => undef,
            minSamples    => undef,
            maxSamples    => undef,
            minRedundancy => undef,
            maxRedundancy => undef,
        },
    );

    my %PARAMS = (    #  default parameters to load.
                      #  These will be overwritten if needed.
                      #  those commented out are redundant
                      #NAME  =>  "BASEDATA",
        OUTSUFFIX => __PACKAGE__->get_file_suffix,

        #OUTSUFFIX_XML      => 'bdx',
        OUTSUFFIX_YAML                 => __PACKAGE__->get_file_suffix_yaml,
        LAST_FILE_SERIALISATION_FORMAT => undef,
        INPFX                          => q{.},
        QUOTES            => q{'},    #  for Dan
        OUTPUT_QUOTE_CHAR => q{"},
        JOIN_CHAR         => q{:},    #  used for labels
        NODATA            => undef,
        PARAM_CHANGE_WARN => undef,
    );

    my %args_for = ( %PARAMS, @_ );
    $self->set_params(%args_for);

    #  check the cell sizes
    my $cell_sizes = $self->get_cell_sizes;
    croak 'CELL_SIZES parameter not specified'
      if !defined $cell_sizes;
    croak 'CELL_SIZES parameter is not an array ref'
      if (!is_arrayref($cell_sizes));

    foreach my $size (@$cell_sizes) {
        croak
          "Cell size $size is not numeric, you might need to check the locale\n"
          . "(one that uses a . as the decimal place works best)\n"
          if !looks_like_number($size);
    }

    my $cell_origins = $self->get_cell_origins;
    croak 'CELL_ORIGINS do not align with CELL_SIZES'
      if scalar @$cell_origins != scalar @$cell_sizes;

    #  create the groups and labels
    my %params_hash = $self->get_params_hash;
    my $name = $self->get_param('NAME') // $EMPTY_STRING;
    $self->{GROUPS} = Biodiverse::BaseStruct->new(
        %params_hash,
        TYPE         => 'GROUPS',
        NAME         => $name . "_GROUPS",
        BASEDATA_REF => $self,
    );
    $self->{LABELS} = Biodiverse::BaseStruct->new(
        %params_hash,
        TYPE         => 'LABELS',
        NAME         => $name . "_LABELS",
        BASEDATA_REF => $self,
    );
    $self->{CLUSTER_OUTPUTS} = {};
    $self->{SPATIAL_OUTPUTS} = {};
    $self->{MATRIX_OUTPUTS}  = {};

    $self->set_param( EXCLUSION_HASH => \%exclusion_hash );

    %params_hash = ();    #  (vainly) hunting memory leaks

    return $self;
}

sub get_file_suffix {
    return 'bds';
}

sub get_file_suffix_yaml {
    return 'bdy';
}

sub binarise_sample_counts {
    my $self = shift;

    die "Cannot binarise a basedata with existing outputs\n"
      if $self->get_output_ref_count;

    my $gp = $self->get_groups_ref;
    my $lb = $self->get_labels_ref;

    $gp->binarise_subelement_sample_counts;
    $lb->binarise_subelement_sample_counts;
    $self->delete_cached_values;
}

sub set_group_hash_key_count {
    my $self = shift;
    my %args = @_;

    my $ref = $self->get_groups_ref;
    return $ref->_set_elements_hash_key_count( count => $args{count} );
}

sub set_label_hash_key_count {
    my $self = shift;
    my %args = @_;

    my $ref = $self->get_labels_ref;
    return $ref->_set_elements_hash_key_count( count => $args{count} || 1 );
}

sub rename {
    my $self = shift;
    my %args = @_;

    $args{name} //= $args{new_name};

    croak "[BASEDATA] rename: argument name not supplied\n"
      if not defined $args{name};

    my $name = $self->get_param('NAME');
    print "[BASEDATA] Renaming $name to $args{name}\n";

    $self->set_param( NAME => $args{name} );

    return;
}

sub rename_output {
    my $self = shift;
    my %args = @_;

    my $object = $args{output};
    croak 'Argument "output" not defined'
      if !defined $object;

    my $new_name = $args{new_name};
    my $name     = $object->get_name;

    my $class = ( blessed $object) // $EMPTY_STRING;

    my $o_type =
        $class =~ /Spatial/                   ? 'SPATIAL_OUTPUTS'
      : $class =~ /Cluster|RegionGrower|Tree/ ? 'CLUSTER_OUTPUTS'
      : $class =~ /Matrix/                    ? 'MATRIX_OUTPUTS'
      : $class =~ /Randomise/                 ? 'RANDOMISATION_OUTPUTS'
      :                                         undef;

    croak "[BASEDATA] Cannot rename this type of output: $class\n"
      if !$o_type;

    my $hash_ref = $self->{$o_type};

    my $type = $class;
    $type =~ s/.*://;
    say "[BASEDATA] Renaming output $name to $new_name, type is $type";

    # only if it exists in this basedata
    if ( exists $hash_ref->{$name} ) {

        croak
"Cannot rename $type output $name to $new_name.  Name is already in use\n"
          if exists $hash_ref->{$new_name};

        $hash_ref->{$new_name} = $object;
        $hash_ref->{$name}     = undef;
        delete $hash_ref->{$name};

        $object->rename( new_name => $new_name );
    }
    else {
        warn "[BASEDATA] Cannot locate object with name $name\n"
          . 'Currently have '
          . join( ' ', sort keys %$hash_ref ) . "\n";
    }

    $object = undef;
    return;
}

#  deletion of randomisations is more complex than spatial and cluster outputs
sub do_rename_randomisation_lists {
    my $self = shift;
    my %args = @_;

    my $object   = $args{output};
    my $name     = $object->get_name;
    my $new_name = $args{new_name};

    croak "Argument new_name not defined\n"
      if !defined $new_name;

    #  loop over the spatial outputs and rename the lists
  BY_SPATIAL_OUTPUT:
    foreach my $sp_output ( $self->get_spatial_output_refs ) {
        my @lists =
          grep { $_ =~ /^$name>>/ } $sp_output->get_lists_across_elements;

        foreach my $list (@lists) {
            my $new_list_name = $list;
            $new_list_name =~ s/^$name>>/$new_name>>/;
            foreach my $element ( $sp_output->get_element_list ) {
                $sp_output->rename_list(
                    list     => $list,
                    element  => $element,
                    new_name => $new_list_name,
                );
            }
        }
        $sp_output->delete_cached_values;
    }

    #  and now the cluster outputs
    my @node_lists = ( $name, $name . '_ID_LDIFFS', $name . '_DATA', );

  BY_CLUSTER_OUTPUT:
    foreach my $cl_output ( $self->get_cluster_output_refs ) {
        my @lists = grep { $_ =~ /^$name>>/ } $cl_output->get_list_names_below;
        my @lists_to_rename = ( @node_lists, @lists );

        foreach my $list (@lists_to_rename) {
            my $new_list_name = $list;
            $new_list_name =~ s/^$name/$new_name/;

            foreach my $node_ref ( $cl_output->get_node_refs ) {
                $node_ref->rename_list(
                    list     => $list,
                    new_name => $new_list_name,
                );
            }
        }
        $cl_output->delete_cached_values;
    }

    return;
}

#  define our own clone method for more control over what is cloned.
#  use the SUPER method (should be from Biodiverse::Common) for the components.
sub clone {
    my $self = shift;
    my %args = @_;
    my $cloneref;

    if ( $args{no_outputs} ) {    #  clone all but the outputs

       #  temporarily override the outputs - this is so much cleaner than before
        local $self->{SPATIAL_OUTPUTS}       = {};
        local $self->{CLUSTER_OUTPUTS}       = {};
        local $self->{RANDOMISATION_OUTPUTS} = {};
        local $self->{MATRIX_OUTPUTS}        = {};
        $cloneref = $self->SUPER::clone();

    }
    elsif ( $args{no_elements} ) {

        #  temporarily override the groups and labels so they aren't cloned
        local $self->{GROUPS}{ELEMENTS} =
          {}; # very dirty - basedata should not know about basestruct internals
        local $self->{LABELS}{ELEMENTS}      = {};
        local $self->{SPATIAL_OUTPUTS}       = {};
        local $self->{CLUSTER_OUTPUTS}       = {};
        local $self->{RANDOMISATION_OUTPUTS} = {};
        local $self->{MATRIX_OUTPUTS}        = {};
        $cloneref = $self->SUPER::clone();

    }
    else {
        $cloneref = $self->SUPER::clone(%args);
    }

    #my $clone2 = $cloneref;  #  for testing purposes
    return $cloneref;
}

sub _describe {
    my $self = shift;

    my @description = ( 'TYPE: ' . blessed $self, );

    my @keys = qw /
      NAME
      CELL_SIZES
      CELL_ORIGINS
      JOIN_CHAR
      QUOTES
      NUMERIC_LABELS
      /;    #/

    foreach my $key (@keys) {
        my $desc = $self->get_param ($key);
        if (is_arrayref($desc)) {
            $desc = join q{, }, @$desc;
        }
        push @description, "$key: $desc";
    }

    my $gp_count = $self->get_group_count;
    my $lb_count = $self->get_label_count;
    my $sp_count = scalar @{ $self->get_spatial_output_refs };
    my $cl_count = scalar @{ $self->get_cluster_output_refs };
    my $rd_count = scalar @{ $self->get_randomisation_output_refs };
    my $mx_count = scalar @{ $self->get_matrix_output_refs };

    push @description, "Group count: $gp_count";
    push @description, "Label count: $lb_count";
    push @description, "Spatial outputs: $sp_count";
    push @description, "Cluster outputs: $cl_count";
    push @description, "Randomisation outputs: $rd_count";
    push @description, "Matrix outputs: $mx_count";

    push @description,
      'Using spatial index: '
      . ( $self->get_param('SPATIAL_INDEX') ? 'yes' : 'no' );

    my $ex_count = $self->get_param('EXCLUSION_COUNT') || 0;
    push @description, "Run exclusions count: $ex_count";

    my $bounds  = $self->get_coord_bounds;
    my $bnd_max = $bounds->{MAX};
    my $bnd_min = $bounds->{MIN};
    push @description, 'Group coord minima: ' . ( join q{, }, @$bnd_min );
    push @description, 'Group coord maxima: ' . ( join q{, }, @$bnd_max );

    my $description = join "\n", @description;

    #foreach my $row (@description) {
    #    #$description .= join "\t", @$row;
    #    $description .= $row;
    #    $description .= "\n";
    #}

    return wantarray ? @description : $description;
}

sub get_coord_bounds {
    my $self = shift;

    #  do we use numeric or string comparison?
    my @numeric_comp;
    my @string_comp;
    my $cellsizes = $self->get_cell_sizes;
    my $i         = 0;
    foreach my $size (@$cellsizes) {
        if ( $size < 0 ) {
            push @string_comp, $i;
        }
        else {
            push @numeric_comp, $i;
        }
        $i++;
    }

    my ( @min, @max );

    my $gp = $self->get_groups_ref;

    my $group_hash = $gp->get_element_hash;

    return wantarray ? () : {}
      if !scalar keys %$group_hash;

    my $progress = Biodiverse::Progress->new();
    my $to_do    = scalar keys %$group_hash;

    $i = -1;
  GROUP:
    foreach my $gp_name ( keys %$group_hash ) {
        $i++;
        my $coord = $gp->get_element_name_as_array( element => $gp_name );

        if ( !$i ) {    #  first one
            my $j = 0;
            foreach my $axis (@$coord) {
                $min[$j] = $axis;
                $max[$j] = $axis;
                $j++;
            }
            next GROUP;
        }

        $progress->update( "Getting coord bounds\n($i of $to_do)",
            $i / $to_do );

        if (@string_comp) {    #  rarer than numeric
            foreach my $j (@string_comp) {
                my $axis = $coord->[$j];
                if ( $axis lt $min[$j] ) {
                    $min[$j] = $axis;
                }
                elsif ( $axis gt $max[$j] ) {
                    $max[$j] = $axis;
                }
            }
        }
        foreach my $j (@numeric_comp) {
            my $axis = $coord->[$j];
            if ( $axis < $min[$j] ) {
                $min[$j] = $axis;
            }
            elsif ( $axis > $max[$j] ) {
                $max[$j] = $axis;
            }
        }

    }

    my %bounds = (
        MIN => \@min,
        MAX => \@max,
    );

    return wantarray ? %bounds : \%bounds;
}

#  return a new BaseData object with transposed GROUPS and LABELS.
#  all other results are ignored, as they will no longer make sense
sub transpose {
    my $self = shift;
    my %args = @_;

    #  create the new object.         retain the the current params
    my $params = $self->clone(    #  but clone to avoid ref clash problems
        data => scalar $self->get_params_hash
    );

    my $new = Biodiverse::BaseData->new(%$params);
    my $name = $args{name} // ( $new->get_param('NAME') . "_T" );

    $new->set_param( NAME => $name );

    #  get refs for the current object
    my $groups = $self->get_groups_ref->clone;
    my $labels = $self->get_labels_ref->clone;

    #  assign the transposed groups and labels
    #  no need to worry about parent refs, as they don't have any (yet)
    $new->{GROUPS} = $labels;
    $new->{LABELS} = $groups;

    #  set the correct cell sizes.
    #  The default is just in case, and may cause trouble later on
    my $cell_sizes = $labels->get_param('CELL_SIZES') || [-1];
    $new->set_param( CELL_SIZES => [@$cell_sizes] );    #  make sure it's a copy

    return $new;
}

#  create a tree object from the labels
sub to_tree {
    my $self = shift;
    return $self->get_labels_ref->to_tree(@_);
}

#  get the embedded trees used in the outputs
sub get_embedded_trees {
    my $self = shift;

    my $outputs = $self->get_output_refs;
    my %tree_hash;    #  index by ref to allow for duplicates

  OUTPUT:
    foreach my $output (@$outputs) {
        next OUTPUT if !$output->can('get_embedded_tree');

        my $tree = $output->get_embedded_tree;
        if ($tree) {
            $tree_hash{$tree} = $tree;
        }
    }

    return wantarray ? values %tree_hash : [ values %tree_hash ];
}

#  get the embedded trees used in the outputs
sub get_embedded_matrices {
    my $self = shift;

    my $outputs = $self->get_output_refs;
    my %mx_hash;    #  index by ref to allow for duplicates

  OUTPUT:
    foreach my $output (@$outputs) {
        next OUTPUT if !$output->can('get_embedded_matrix');

        my $mx = $output->get_embedded_matrix;
        if ($mx) {
            $mx_hash{$mx} = $mx;
        }
    }

    return wantarray ? values %mx_hash : [ values %mx_hash ];
}

#  weaken all the child refs to this basedata object
#  otherwise they are not properly deleted when this is deleted
sub weaken_child_basedata_refs {
    my $self = shift;
    foreach my $sub_ob ( $self->get_spatial_output_refs,
        $self->get_cluster_output_refs )
    {
        $sub_ob->weaken_basedata_ref;
    }
    foreach my $sub_ob ( $self->get_cluster_output_refs ) {
        $sub_ob
          ->weaken_parent_refs;  #  loop through tree and weaken the parent refs
    }

    #print $EMPTY_STRING;

    return;
}

#  get the basestats from the groups (or labels)
sub get_base_stats {
    my $self = shift;
    my %args = @_;
    my $type = uc( $args{type} ) || 'GROUPS';
    $type = 'GROUPS' if ( $type !~ /GROUPS|LABELS/ );

    return $self->{$type}->get_base_stats(@_);
}

sub get_metadata_get_base_stats {
    my $self = shift;
    my %args = @_;

    #  probably not needed, but doesn't hurt...
    my $type = uc( $args{type} ) || 'GROUPS';

    $type = 'GROUPS' if ( $type !~ /GROUPS|LABELS/ );

    return $self->{$type}->get_metadata_get_base_stats(@_);
}

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

#my @sep_chars = my @separators = defined $ENV{BIODIVERSE_FIELD_SEPARATORS}
#              ? @$ENV{BIODIVERSE_FIELD_SEPARATORS}
#              : (q{,}, 'tab', q{;}, 'space', q{:});
#my @input_sep_chars = ('guess', @sep_chars);
#
#my @quote_chars = qw /" ' + $/;      # " (comment just catching runaway quote in eclipse)
#my @input_quote_chars = ('guess', @quote_chars);

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

        my $file_handle = IO::File->new;

        if ( -e $file and -r $file ) {
            $file_handle->open( $file, '<:via(File::BOM)' );
        }
        else {
            croak
"[BASEDATA] $file DOES NOT EXIST OR CANNOT BE READ - CANNOT LOAD DATA\n";
        }

        my $file_size_Mb = $self->set_precision(
            precision => "%.3f",
            value     => ( -s $file )
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
          if !( -e $file and -r $file );

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
        binarise_counts    => $args{binarise_counts},
        allow_empty_groups => $args{allow_empty_groups},
        allow_empty_labels => $args{allow_empty_labels},
    );
    
    my @input_files = @{ $args{input_files} };
    my $num_files = @input_files;
    my $file_progress;
    if (@input_files > 1) {
        $file_progress = Biodiverse::Progress->new (gui_only => 1);
    }

    # load each file, using same arguments/parameters
    my $file_num = 0;
    foreach my $file ( @input_files ) {
        $file_num++;
        $file = Path::Class::file($file)->absolute;
        say "[BASEDATA] INPUT FILE: $file";
        
        if ($file_progress) {
            $file_progress->update (
                "File $file_num of $num_files",
                $file_num / $num_files,
            );
        }

        # open as shapefile
        my $fnamebase = $file->stringify;

        my $layer = Geo::GDAL::FFI::Open($fnamebase)->GetLayer;
        $layer->ResetReading;
        my $defn = $layer->GetDefn;
        #  needs a method
        my $schema     = $defn->GetSchema;
        my $shape_type = $schema->{GeometryFields}[0]{Type};

        croak "[BASEDATA] $fnamebase: Import of feature type $shape_type is not supported.\n"
          if not $shape_type =~ /Point|Polygon/;

        #  some validation
        #  keys are case insensitive, values store case  
        my %fld_names = map {lc ($_->{Name}) => $_->{Name}} @{$schema->{Fields}};
        foreach my $key (@label_field_names) {
            croak "Shapefile $file does not have a field called $key\n"
              if !exists $fld_names{$key};
        }

        #  get a Fishnet Identity overlay if we have polygons        
        if ($shape_type =~ 'Polygon') {
            my $f_layer = $self->get_fishnet_identity_layer (
                source_layer => $layer,
                schema       => $schema,
            );
            $layer = undef;
            $layer = $f_layer;  #  assigning in method call causes failures?
            $layer->ResetReading;
            #  update a few things
            $defn   = $layer->GetDefn;
            $schema = $defn->GetSchema;
            %fld_names = map {lc ($_->{Name}) => $_->{Name}} @{$schema->{Fields}};
            #warn 'Intersected field names: ' . join ' ', sort keys %fld_names; 
        }

        #my $shape_count = $layer->GetFeatureCount();
        #  interim solution
        my $shape_count = 0;
        while ($layer->GetNextFeature) {
            $shape_count++;
        }
        $layer->ResetReading;
        say "File has $shape_count shapes";

        # iterate over shapes
        my %gp_lb_hash;
        my $count = 0;
      SHAPE:
        while (my $shape = $layer->GetNextFeature) {
            $count ++;

            # just get all the points from the shape.
            my $geom = $shape->GetGeomField;
            my $ptlist;
            my $default_count = 1;
            if ($shape_type =~ 'Point') {
                $ptlist = $geom->GetPoints;
            }
            elsif ($shape_type =~ 'Polygon') {
                #  get the centroid until we find more efficient methods
                $ptlist = $geom->Centroid->GetPoints;
                #say $geom->AsText;
                if (!scalar @smp_count_field_names  ) {
                    $default_count = $geom->Area;
                }
            }

            # Get database record for this shape.
            # Same for all features in the shape.
            # Awkward - should just get the fields we need
            #say 'Getting fields: ' . join ' ', sort keys %fld_names;
            my %db_rec = map {lc ($_) => ($shape->GetField ($_) // undef)} values %fld_names;

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

    my $layer = $args{source_layer};
    my $schema = $args{schema};
    
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
    my @group_sizes   = $self->get_cell_sizes;

    my $fishnet = $self->get_fishnet_polygon_layer (
        extent => $self->_get_ogr_layer_extent ($layer),
        resolutions => \@group_sizes,
        origins     => \@group_origins,
        shape_type  => $shape_type,
        spatial_reference => $sr_clone1,
    );

    my $last_p = time() - 1;
    my $progress = sub {
        return 1 if $_[0] < 1 and abs(time() - $last_p) < 0.5;
        my ($fraction, $msg, $data) = @_;
        local $| = 1;
        printf "%.3g ", $fraction;
        $last_p = time();
        1;
    };
    #$progress = undef;
    
    #  get the fishnet cells that intersect the polygons
    $layer->ResetReading;
    #  create the layer now so we only get polygons back
    my $overlay_result
        = Geo::GDAL::FFI::GetDriver('ESRI Shapefile')
            ->Create ('/vsimem/_' . time())
            ->CreateLayer({
                Name => 'overlay_result_' . Scalar::Util::refaddr ($self),
                SpatialReference => $sr_clone2,
                GeometryType     => $shape_type,
                Options => {SPATIAL_INDEX => 'YES'},
        });
    #  not sure these have any effect
    my $options = {
        PROMOTE_TO_MULTI    => 'NO',
        #PRETEST_CONTAINMENT => 'YES',
    };
    say 'Intersecting fishnet with polygon layer';
    $layer->Intersection(
        $fishnet,
        {
            Result   => $overlay_result,
            Progress => $progress,
            Options  => $options,
        }
    );
    say 'Intersection complete';
    
    #  close fishnet data set
    $fishnet = undef;
    
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
    $out_fname = ('/vsimem/fishnet_' . time());
    #}
    #say "Generating fishnet file $out_fname";
    
    my $shape_type = $args{shape_type} // 'Polygon';
    my $sr = $args{spatial_reference};
    if (defined $sr && !blessed $sr) {
        $sr = Geo::GDAL::FFI::SpatialReference->new($sr);
    }

    my $extent      = $args{extent};
    my $resolutions = $args{resolutions};
    my $origins     = $args{origins};

    my ($xmin, $xmax, $ymin, $ymax) = @$extent;
    my ($grid_height, $grid_width)  = @$resolutions;
    
    
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

    my $fishnet_fld_name = '_fsh_name';
    my $fishnet_lyr
        = Geo::GDAL::FFI::GetDriver($driver)
            ->Create ($out_fname)
            ->CreateLayer({
                Name => 'Fishnet_Layer' . Scalar::Util::refaddr ($self),
                GeometryType => $shape_type,
                SpatialReference => $sr,
                Fields => [{
                    Name => $fishnet_fld_name,
                    Type => 'String'
                }],
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
            my $poly = 'POLYGON (('
                . "$ring_X_left_origin  $ring_Y_top, "
                . "$ring_X_right_origin $ring_Y_top, "
                . "$ring_X_right_origin $ring_Y_bottom, "
                . "$ring_X_left_origin  $ring_Y_bottom, "
                . "$ring_X_left_origin  $ring_Y_top"
                . '))';
            #say $poly;
            my $f = Geo::GDAL::FFI::Feature->new($fishnet_lyr->GetDefn);
            $f->SetField($fishnet_fld_name => "$countrows x $countcols");
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
            
    return $fishnet_lyr;
}

#  until Geo::GDAL::FFI provides this
sub _get_ogr_layer_extent {
    my ($self, $layer, $force) = @_;
    my $extent = [0,0,0,0];
    my $e = Geo::GDAL::FFI::OGR_L_GetExtent ($$layer, $extent, $force ? 1 : 0);
    confess Geo::GDAL::FFI::error_msg({OGRError => $e})
      if $e;
    return $extent;
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

        croak
"[BASEDATA] Undefined input_file array item passed to import_data_spreadsheet\n"
          if !defined $book;    # assuming undef on fail

        if ( blessed $book || !ref $book ) {    #  we have a file name
            my $file = Path::Class::file($book)->absolute;
            say "[BASEDATA] INPUT FILE: $file";

            # open as spreadsheet
            my $fnamebase = $file->stringify;
            $book = ReadData($fnamebase);

            croak "[BASEDATA] Failed to read $file with SpreadSheet\n"
              if !defined $book;                # assuming undef on fail
        }

        my $sheet_id = $sheet_array[$file_i] // 1;
        if ( !looks_like_number $sheet_id) {    #  must be a named sheet
            $sheet_id = $book->[0]{sheet}{$sheet_id};
        }

        my @rows   = Spreadsheet::Read::rows( $book->[$sheet_id] );
        my $header = shift @rows;

        #  some validation (and get the col numbers)
        my $i = -1;
        my %db_rec1 = map { $_ => ++$i } @$header;
        foreach my $key (@label_field_names) {
            croak
"Spreadsheet does not have a field called $key in book $sheet_id\n"
              if !exists $db_rec1{$key};
        }
        foreach my $key (@group_field_names) {
            croak
"Spreadsheet does not have a field called $key in book $sheet_id\n"
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

            my %db_rec;
            @db_rec{@$header} = @$row
              ; #  inefficient - we should get the row numbers and slice on them

# form group text from group fields (defined as csv string of central points of group)
# Needs to process the data in the same way as for text imports - refactoring is in order.
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

#  attach the current ranges as RANGE properties
sub attach_label_ranges_as_properties {
    my $self = shift;

    return $self->_attach_label_ranges_or_counts_as_properties( @_,
        type => 'ranges', );
}

#  attach the current sample counts as ABUNDANCE properties
sub attach_label_abundances_as_properties {
    my $self = shift;

    return $self->_attach_label_ranges_or_counts_as_properties( @_,
        type => 'sample_counts', );
}

sub _attach_label_ranges_or_counts_as_properties {
    my $self = shift;
    my %args = @_;

    my $override = $args{override};
    my $type     = $args{type};

    my ( $method, $key );
    if ( lc $type eq 'sample_counts' ) {
        $method = 'get_label_sample_count';
        $key    = 'ABUNDANCE';
    }
    elsif ( lc $type eq 'ranges' ) {
        $method = 'get_range';
        $key    = 'RANGE';
    }

    my $lb = $self->get_labels_ref;
    $lb->delete_cached_values;

  LABEL:
    foreach my $label ( $args{target_labels} || $self->get_labels ) {

        if ( !$override ) {
            my $list_ref = $lb->get_list_ref(
                element => $label,
                list    => 'PROPERTIES',
            );
            next LABEL
              if exists $list_ref->{$key} && defined $list_ref->{$key};
        }

        my $value = $self->$method( element => $label );
        $lb->add_to_lists(
            element    => $label,
            PROPERTIES => { $key => $value },
        );
    }

    return;
}

sub assign_element_properties {
    my $self = shift;
    my %args = @_;

    my $type = $args{type}
      or croak 'argument "type" not specified';
    my $prop_obj = $args{properties_object}
      or croak 'argument properties_object not given';

    croak "Cannot assign properties to a basedata with existing outputs"
      if $self->get_output_ref_count;

    my $method    = 'get_' . $type . '_ref';
    my $gp_lb_ref = $self->$method;

  #  Clean up in case we add different ones.
  #  We cannot get the list here as we might only be adding a subset of elements
  #$gp_lb_ref->delete_cached_value ('ELEMENT_PROPERTY_KEYS');
    $gp_lb_ref->delete_cached_values;

    my $count = 0;

  ELEMENT_PROPS:
    foreach my $element ( $prop_obj->get_element_list ) {
        next ELEMENT_PROPS
          if !$gp_lb_ref->exists_element( element => $element );

        my %props = $prop_obj->get_element_properties( element => $element );

        #  but don't add these ones
        delete @props{qw /INCLUDE EXCLUDE REMAP/};    #/

        next ELEMENT_PROPS if !scalar keys %props;

        $gp_lb_ref->add_to_lists(
            element    => $element,
            PROPERTIES => \%props,
        );

        $count++;
    }

    return $count;
}

# returns a hash. 'groups' maps to a hash mapping from element names
# to element property hashes for this basedata's groups. 'labels'
# likewise.
sub get_all_element_properties {
    my ($self, %args) = shift;
    my %results_hash;
    
    my $gp = $self->get_groups_ref;
    $results_hash{groups} = $gp->get_all_element_properties();
    
    my $lb = $self->get_labels_ref;
    $results_hash{labels} = $lb->get_all_element_properties();

    return wantarray ? %results_hash : \%results_hash;
}

sub delete_group_element_property {
    my ($self, %args) = @_;
    $self->get_groups_ref->delete_element_property(%args);
}

sub delete_label_element_property {
    my ($self, %args) = @_;
    $self->get_labels_ref->delete_element_property(%args);
}

sub delete_group_element_property_aa {
    my ($self, $prop) = @_;
    $self->get_groups_ref->delete_element_property(prop => $prop);
}

sub delete_label_element_property_aa {
    my ($self, $prop) = @_;
    $self->get_labels_ref->delete_element_property(prop => $prop);
}

sub delete_individual_group_properties {
    my ($self, %args) = @_;
    $self->get_groups_ref->delete_properties_for_given_element(%args);
}

sub delete_individual_label_properties {
    my ($self, %args) = @_;
    $self->get_labels_ref->delete_properties_for_given_element(%args);
}

sub delete_individual_group_properties_aa {
    my ($self, $el) = @_;
    $self->get_groups_ref->delete_properties_for_given_element(el => $el);
}

sub delete_individual_label_properties_aa {
    my ($self, $el) = @_;
    $self->get_labels_ref->delete_properties_for_given_element(el => $el);
}

sub rename_labels {
    my $self = shift;
    return $self->_rename_groups_or_labels( @_, type => 'label' );
}

sub rename_groups {
    my $self = shift;
    return $self->_rename_groups_or_labels( @_, type => 'group' );
}

#  should probably wipe the cache if we do rename something
sub _rename_groups_or_labels {
    my $self = shift;
    my %args = @_;

    my $type = $args{type}
      // croak "Need to specify arg type => group or label\n";

    croak "Cannot rename ${type}s when basedata has existing outputs\n"
      if $self->get_output_ref_count;

    my $remap = $args{remap};
    my $labels_are_numeric = $type eq 'label' && $self->labels_are_numeric;
    my $remap_labels_are_all_numeric = 1;
    my $remap_count                  = 0;

    #my %remapped_names;
    my $method = "rename_$type";

  ELEMENT:
    foreach my $label ( $remap->get_element_list ) {
        my $remapped = $remap->get_element_remapped( element => $label );

        next ELEMENT if !defined $remapped;

        $self->$method(
            $type            => $label,
            new_name         => $remapped,
            no_numeric_check => 1,
        );
        $remap_count++;

        #$remapped_names{$remapped}++;

        if ( $type eq 'label' ) {
            $remap_labels_are_all_numeric &&= looks_like_number $remapped;
            if ( $labels_are_numeric && !$remap_labels_are_all_numeric ) {
                $labels_are_numeric = 0;
                $self->set_param( NUMERIC_LABELS => 0 );
            }
        }
    }

    #  trigger a recheck on next call to labels_are_numeric
    if (
           $type eq 'label'
        && !$labels_are_numeric
        && $remap_labels_are_all_numeric

        #&& scalar keys %remapped_names == $self->get_label_count
      )
    {
        $self->set_param( NUMERIC_LABELS => undef );
    }

    return;
}

#  should probably wipe the cache if we do rename something
sub rename_label {
    my $self = shift;
    my %args = @_;

    croak "Argument 'label' not specified\n"
      if !defined $args{label};
    croak "Argument 'new_name' not specified\n"
      if !defined $args{new_name};

    my $lb       = $self->get_labels_ref;
    my $gp       = $self->get_groups_ref;
    my $label    = $args{label};
    my $new_name = $args{new_name};
    my $labels_are_numeric =
      !$args{no_numeric_check} && $self->labels_are_numeric;


    if( $label eq $new_name ) {
        say "[BASEDATA] Tried to rename a label to itself, nothing was done.";
        return;
    }

        
    if ( !$lb->exists_element( element => $label ) ) {
        say "[BASEDATA] Label $label does not exist, not renaming it";
        return;
    }

    my @sub_elements =
      $lb->rename_element( element => $label, new_name => $new_name );
    foreach my $group (@sub_elements) {
        $gp->rename_subelement(
            element     => $group,
            sub_element => $label,
            new_name    => $new_name,
        );
    }
    if ( $labels_are_numeric && !looks_like_number $new_name) {
        $self->set_param( NUMERIC_LABELS => 0 );
    }

    say "[BASEDATA] Renamed $label to $new_name";

    return 1;
}

#  should combine with rename_label
sub rename_group {
    my $self = shift;
    my %args = @_;

    croak "Argument 'group' not specified\n"
      if !defined $args{group};
    croak "Argument 'new_name' not specified\n"
      if !defined $args{new_name};

    my $lb       = $self->get_labels_ref;
    my $gp       = $self->get_groups_ref;
    my $group    = $args{group};
    my $new_name = $args{new_name};

    if ( !$gp->exists_element( element => $group ) ) {
        say "[BASEDATA] Element $group does not exist, not renaming it";
        return;
    }

    my @sub_elements =
      $gp->rename_element( element => $group, new_name => $new_name );
    foreach my $sub_element (@sub_elements) {
        $lb->rename_subelement(
            element     => $sub_element,
            sub_element => $group,
            new_name    => $new_name,
        );
    }

    say "[BASEDATA] Renamed $group to $new_name";

    return;
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

#  these are superseded by $label_col_hash
#my $label_start_col     = $args{label_start_col};
#my $label_end_col       = $args{label_end_col} || $#$fields_ref;  #  not yet supported by GUI (03Oct2009)

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

sub labels_are_numeric {
    my $self = shift;

    my $is_numeric = $self->get_param('NUMERIC_LABELS');
    return $is_numeric if defined $is_numeric;

    $is_numeric = $self->get_labels_ref->elements_are_numeric || 0;
    $self->set_param( NUMERIC_LABELS => $is_numeric );
    return $is_numeric;
}

#  are the sample counts floats or ints?
sub sample_counts_are_floats {
    my $self = shift;

    my $lb = $self->get_labels_ref;

    return $lb->sample_counts_are_floats;
}

sub add_element {    #  run some calls to the sub hashes
    my $self = shift;
    my %args = @_;

    my $label = $args{label};
    my $group = $args{group};
    my $count = $args{count} // 1;

    #  make count binary if asked to
    if ( $args{binarise_counts} ) {
        $count = $count ? 1 : 0;
    }

    my $gp_ref = $self->get_groups_ref;
    my $lb_ref = $self->get_labels_ref;

    if ( not defined $label )
    {    #  one of these will break if neither label nor group is defined
        $gp_ref->add_element(
            element    => $group,
            csv_object => $args{csv_object},
        );
        return;
    }
    if ( not defined $group ) {
        $lb_ref->add_element(
            element    => $label,
            csv_object => $args{csv_object},
        );
        return;
    }

    if ($count) {

        #  add the labels and groups as element and subelement
        #  labels is the transpose of groups
        $gp_ref->add_sub_element_aa( $group, $label, $count,
            $args{csv_object} );
        $lb_ref->add_sub_element_aa( $label, $group, $count,
            $args{csv_object} );
    }
    else {
        if ( $args{allow_empty_groups} ) {
            $gp_ref->add_element(
                element    => $group,
                csv_object => $args{csv_object},
            );
        }
        if ( $args{allow_empty_labels} ) {
            $lb_ref->add_element(
                element    => $label,
                csv_object => $args{csv_object},
            );
        }
    }
    
    #  we could use the labels_are_numeric method, but don't want to trigger the search in an early import
    if (!looks_like_number $label && $self->get_param ('NUMERIC_LABELS')) {
        $self->set_param (NUMERIC_LABELS => 0);
    }

    return;
}

#  add groups and labels without any of the options in add_element,
#  array args version for speed
sub add_element_simple_aa {
    my ( $self, $label, $group, $count, $csv_object ) = @_;

    $count //= 1;

    my $gp_ref = $self->get_groups_ref;
    if ( not defined $label )
    {    #  one of these will break if neither label nor group is defined
        $gp_ref->add_element(
            element    => $group,
            csv_object => $csv_object,
        );
        return;
    }

    my $lb_ref = $self->get_labels_ref;
    if ( not defined $group ) {
        $lb_ref->add_element(
            element    => $label,
            csv_object => $csv_object,
        );
        return;
    }

    if ($count) {

        #  add the labels and groups as element and subelement
        #  labels is the transpose of groups
        $gp_ref->add_sub_element_aa( $group, $label, $count, $csv_object );
        $lb_ref->add_sub_element_aa( $label, $group, $count, $csv_object );

        #  potential slowdown - this sub is a hot path under the randomisations...        
        ##  we could use the labels_are_numeric method, but don't want to trigger the search in an early import
        #if (!looks_like_number $label && $self->get_param ('NUMERIC_LABELS')) {
        #    $self->set_param (NUMERIC_LABELS => 0);
        #}
    }

    1;
}

#  add elements from a collated hash
#  assumes {gps}{labels}{counts}
sub add_elements_collated {
    my $self = shift;
    my %args = @_;

    my $gp_lb_hash = $args{data};
    my $csv_object = $args{csv_object} // croak "csv_object arg not passed\n";

    my $allow_empty_groups = $args{allow_empty_groups};

    #  now add the collated data
    foreach my $gp_lb_pair ( pairs %$gp_lb_hash ) {
        my ( $gp, $lb_hash ) = @$gp_lb_pair;

        if ( $allow_empty_groups && !scalar %$lb_hash ) {
            $self->add_element(
                group              => $gp,
                count              => 0,
                csv_object         => $csv_object,
                allow_empty_groups => 1,
            );
        }
        else {

            foreach my $lb_count_pair ( pairs %$lb_hash ) {
                my ( $lb, $count ) = @$lb_count_pair;

                # add to elements (skipped if the label is nodata)
                $self->add_element(
                    %args,
                    label      => $lb,
                    group      => $gp,
                    count      => $count,
                    csv_object => $csv_object,
                );
            }
        }
    }

    return;
}

#  simplified array args version for speed
sub add_elements_collated_simple_aa {
    my ( $self, $gp_lb_hash, $csv_object, $allow_empty_groups ) = @_;

    croak "csv_object arg not passed\n"
      if !$csv_object;

    #  now add the collated data
    foreach my $gp_lb_pair ( pairs %$gp_lb_hash ) {
        my ( $gp, $lb_hash ) = @$gp_lb_pair;

        if ( $allow_empty_groups && !scalar %$lb_hash ) {
            $self->add_element( undef, $gp, 0, $csv_object );
        }
        else {
            foreach my $lb_count_pair ( pairs %$lb_hash ) {
                my ( $lb, $count ) = @$lb_count_pair;
                $self->add_element_simple_aa( $lb, $gp, $count, $csv_object );
            }
        }
    }

    return;
}

sub add_elements_collated_by_label {
    my $self = shift;
    my %args = @_;

    my $gp_lb_hash = $args{data};
    my $csv = $args{csv_object} // croak "csv_object arg not passed\n";

    #  now add the collated data
    foreach my $gp_lb_pair ( pairs %$gp_lb_hash ) {
        my ( $lb, $gp_hash ) = @$gp_lb_pair;
        foreach my $gp_count_pair ( pairs %$gp_hash ) {
            my ( $gp, $count ) = @$gp_count_pair;

            # add to elements (skipped if the label is nodata)
            $self->add_element(
                %args,
                label      => $lb,
                group      => $gp,
                count      => $count,
                csv_object => $csv,
            );
        }
    }

    return;
}

sub get_group_element_as_array {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};
    croak "element not specified\n"
      if !defined $element;

    return $self->{GROUPS}->get_element_name_as_array( element => $element );
}

sub get_label_element_as_array {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};
    croak "element not specified\n"
      if !defined $element;

    return $self->get_labels_ref->get_element_name_as_array(
        element => $element );
}

#  reorder group and/or label axes
#  Clone the basedata and add the remapped elements
#  This avoids complexities with name clashes that an in-place
#  re-ordering would cause
sub new_with_reordered_element_axes {
    my $self = shift;
    my %args = @_;

    my $group_cols = $args{GROUP_COLUMNS};
    my $label_cols = $args{LABEL_COLUMNS};

    my $csv_object = $self->get_csv_object(
        quote_char => $self->get_param('QUOTES'),
        sep_char   => $self->get_param('JOIN_CHAR')
    );

    #  get the set of reordered labels
    my $lb          = $self->get_labels_ref;
    my $lb_remapped = $lb->get_reordered_element_names(
        reordered_axes => $label_cols,
        csv_object     => $csv_object,
    );

    #  and the set of reordered groups
    my $gp          = $self->get_groups_ref;
    my $gp_remapped = $gp->get_reordered_element_names(
        reordered_axes => $group_cols,
        csv_object     => $csv_object,
    );

    my $new_bd = $self->clone( no_elements => 1 );

    foreach my $group ( $gp->get_element_list ) {
        my $new_group = $gp_remapped->{$group};
        foreach my $label ( $self->get_labels_in_group( group => $group ) ) {
            my $new_label = $lb_remapped->{$label};
            if ( not defined $new_label ) {
                $new_label = $label;
            }

            my $count = $gp->get_subelement_count(
                element     => $group,
                sub_element => $label,
            );

            $new_bd->add_element(
                group      => $new_group,
                label      => $new_label,
                count      => $count,
                csv_object => $csv_object,
            );
        }
    }

    $self->transfer_label_properties(
        %args,
        receiver => $new_bd,
        remap    => $lb_remapped,
    );
    $self->transfer_group_properties(
        %args,
        receiver => $new_bd,
        remap    => $gp_remapped,
    );

    return $new_bd;
}

sub transfer_label_properties {
    my $self = shift;

    return $self->transfer_element_properties( @_, type => 'labels' );
}

sub transfer_group_properties {
    my $self = shift;

    return $self->transfer_element_properties( @_, type => 'groups' );
}

#  sometimes we have element properties defined like species ranges.
#  need to copy these across.
#  Push system - should it be pull (although it's only a semantic difference)
sub transfer_element_properties {
    my $self = shift;
    my %args = @_;

    my $to_bd = $args{receiver} || croak "Missing receiver argument\n";
    my $remap = $args{remap} || {};    #  remap hash

    my $progress_bar = Biodiverse::Progress->new();

    my $type = $args{type};
    croak "argument 'type => $type' is not valid (must be groups or labels)\n"
      if not( $type eq 'groups' or $type eq 'labels' );
    my $get_ref_sub = $type eq 'groups' ? 'get_groups_ref' : 'get_labels_ref';

    my $elements_ref    = $self->$get_ref_sub;
    my $to_elements_ref = $to_bd->$get_ref_sub;

    my $name    = $self->get_param('NAME');
    my $to_name = $to_bd->get_param('NAME');
    my $text    = "Transferring $type properties from $name to $to_name";

    my $total_to_do = $elements_ref->get_element_count;
    print "[BASEDATA] Transferring properties for $total_to_do $type\n";

    my $count = 0;
    my $i     = -1;

  BY_ELEMENT:
    foreach my $element ( $elements_ref->get_element_list ) {
        $i++;
        my $progress = $i / $total_to_do;
        $progress_bar->update( "$text\n" . "(label $i of $total_to_do)",
            $progress );

        #  remap element if needed
        my $to_element =
          exists $remap->{$element} ? $remap->{$element} : $element;

        #  avoid working with those not in the receiver
        next BY_ELEMENT
          if not $to_elements_ref->exists_element( element => $to_element );

        my $props = $elements_ref->get_list_values(
            element => $element,
            list    => 'PROPERTIES'
        );

        next BY_ELEMENT if !defined $props;    #  none there

        $to_elements_ref->add_to_lists(
            element    => $to_element,
            PROPERTIES => {%$props}
            ,    #  make sure it's a copy so bad things don't happen
        );
        $count++;
    }

    #  scorched earth approach
    $to_elements_ref
      ->delete_cached_values;    # (keys => ['ELEMENT_PROPERTY_KEYS']);

    return $count;
}

sub run_exclusions {
    my $self = shift;
    my %args = @_;

    croak "Cannot run exclusions on a baseData with existing outputs\n"
      if ( my @array = $self->get_output_refs );

    my $feedback =
        'The data initially fall into '
      . $self->get_group_count
      . ' groups with '
      . $self->get_label_count
      . " unique labels\n\n";

    my $orig_group_count = $self->get_group_count;

#  now we go through and delete any of the groups that are beyond our stated exclusion values
    my %exclusion_hash =
      $self->get_exclusion_hash(%args);    #  generate the exclusion hash

    $args{delete_empty_groups} //= $exclusion_hash{delete_empty_groups};
    $args{delete_empty_labels} //= $exclusion_hash{delete_empty_labels};

    #  $_[0] is $base_type_ref, $_[1] is $element
    my %test_callbacks = (
        minVariety => sub { $_[0]->get_variety( element => $_[1] ) <= $_[2] },
        maxVariety => sub { $_[0]->get_variety( element => $_[1] ) >= $_[2] },
        minSamples =>
          sub { $_[0]->get_sample_count( element => $_[1] ) <= $_[2] },
        maxSamples =>
          sub { $_[0]->get_sample_count( element => $_[1] ) >= $_[2] },
        minRedundancy =>
          sub { $_[0]->get_redundancy( element => $_[1] ) <= $_[2] },
        maxRedundancy =>
          sub { $_[0]->get_redundancy( element => $_[1] ) >= $_[2] },
    );

    my ( $label_regex, $label_regex_negate );
    if ( $exclusion_hash{LABELS}{regex} ) {
        my $re_text = $exclusion_hash{LABELS}{regex}{regex};
        my $re_modifiers = $exclusion_hash{LABELS}{regex}{modifiers} // q{};

        $label_regex        = eval qq{ qr /$re_text/$re_modifiers };
        $label_regex_negate = $exclusion_hash{LABELS}{regex}{negate};
    }

    my ( $label_check_list, $label_check_list_negate );
    if ( my $check_list = $exclusion_hash{LABELS}{element_check_list}{list} ) {
        $label_check_list = {};
        $label_check_list_negate =
          $exclusion_hash{LABELS}{element_check_list}{negate};
        if ( blessed $check_list)
        {    #  we have an object with a get_element_list method
            my $list = $check_list->get_element_list;
            @{$label_check_list}{@$list} = (1) x scalar @$list;
        }
        elsif (is_arrayref($check_list)) {
            @{$label_check_list}{@$check_list} = (1) x scalar @$check_list;
        }
        else {
            $label_check_list = $check_list;
        }
    }

    my $group_check_list;
    if ( my $definition_query = $exclusion_hash{GROUPS}{definition_query} ) {
        if ( !blessed $definition_query) {
            $definition_query =
              Biodiverse::SpatialConditions::DefQuery->new(
                conditions => $definition_query, );
        }
        my $groups        = $self->get_groups;
        my $element       = $groups->[0];
        my $defq_progress = Biodiverse::Progress->new( text => 'def query' );
        $group_check_list = $self->get_neighbours(
            element            => $element,
            spatial_conditions => $definition_query,
            is_def_query       => 1,
            progress           => $defq_progress,
        );
    }

    #  check the labels first, then the groups
    #  equivalent to range then richness
    my ( @delete_list, %tally );
    my $excluded = 0;

  BY_TYPE:
    foreach my $type ( 'LABELS', 'GROUPS' ) {

        my $other_type = $type eq 'GROUPS' ? 'LABELS' : 'GROUPS';

        my $base_type_ref = $self->{$type};

        my $cut_count     = 0;
        my $sub_cut_count = 0;
        @delete_list = ();

      BY_ELEMENT:
        foreach my $element ( $base_type_ref->get_element_list ) {

            #next if ! defined $element;  #  ALL SHOULD BE DEFINED

#  IGNORE NEXT CONDITION - sometimes we get an element called ''
#next if (not defined $element);  #  we got an empty list, so don't try anything

            my $failed_a_test = 0;

          BY_TEST:
            foreach my $test ( keys %test_callbacks ) {
                next BY_TEST if !defined $exclusion_hash{$type}{$test};

            #  old string eval approach
            #my $condition = $test_funcs{$test} . $exclusion_hash{$type}{$test};
            #my $check = eval $condition;

                my $callback = $test_callbacks{$test};
                my $chk      = $callback->(
                    $base_type_ref, $element, $exclusion_hash{$type}{$test}
                );

                next BY_TEST if !$chk;

                $failed_a_test = 1
                  ; #  if we get here we have failed a test, so drop out of the loop
                last BY_TEST;
            }

            if ( not $failed_a_test and $type eq 'LABELS' )
            {       #  label specific tests - need to generalise these
                if (
                    (
                        defined $exclusion_hash{$type}{max_range}
                        && $self->get_range( element => $element ) >=
                        $exclusion_hash{$type}{max_range}
                    )
                    || ( defined $exclusion_hash{$type}{min_range}
                        && $self->get_range( element => $element ) <=
                        $exclusion_hash{$type}{min_range} )
                  )
                {

                    $failed_a_test = 1;
                }
                if ( !$failed_a_test && $label_regex ) {
                    $failed_a_test = $element =~ $label_regex;
                    if ($label_regex_negate) {
                        $failed_a_test = !$failed_a_test;
                    }
                }
                if ( !$failed_a_test && $label_check_list ) {
                    $failed_a_test = exists $label_check_list->{$element};
                    if ($label_check_list_negate) {
                        $failed_a_test = !$failed_a_test;
                    }
                }
            }

            if ( !$failed_a_test && $type eq 'GROUPS' && $group_check_list ) {
                $failed_a_test = exists $group_check_list->{$element};
            }

            next BY_ELEMENT
              if not $failed_a_test;    #  no fails, so check next element

            $cut_count++;
            push( @delete_list, $element );
        }

        foreach my $element (@delete_list)
        {  #  having it out here means all are checked against the initial state
            $sub_cut_count += $self->delete_element(
                %args,
                type    => $type,
                element => $element,
            );
        }

        my $lctype       = lc $type;
        my $lc_othertype = lc $other_type;
        if ( $cut_count || $sub_cut_count ) {
            $feedback .= "Cut $cut_count $lctype on exclusion criteria, "
              . "deleting $sub_cut_count $lc_othertype in the process\n\n";
            $feedback .= sprintf
              "The data now fall into %d groups with %d unique labels\n\n",
              $self->get_group_count,
              $self->get_label_count;
            $tally{ $type . '_count' }       += $cut_count;
            $tally{ $other_type . '_count' } += $sub_cut_count;
            $excluded++;
        }
        else {
            $feedback .=
              "No $lctype excluded when checking $lctype criteria.\n";
        }
        print $feedback;
    }

    if ($excluded) {
        my $e_count = $self->get_param_as_ref('EXCLUSION_COUNT');
        if ( !defined $e_count ) {    #  create it if needed
            $self->set_param( EXCLUSION_COUNT => 1 );
        }
        else {                        # else increment it
            $$e_count++;
        }
    }

    #  now rebuild the index if need be
    if (    $orig_group_count != $self->get_group_count
        and $self->get_param('SPATIAL_INDEX') )
    {
        $self->rebuild_spatial_index();
    }

    $tally{feedback} = $feedback;
    return wantarray ? %tally : \%tally;
}

sub get_exclusion_hash {    #  get the exclusion_hash from the PARAMS
    my $self = shift;
    my %args = @_;

    my $exclusion_hash =
         $args{exclusion_hash}
      || $self->get_param('EXCLUSION_HASH')
      || {};

    return wantarray ? %$exclusion_hash : $exclusion_hash;
}

sub trim {
    my $self = shift;
    my %args = @_;

    my @outputs = $self->get_output_refs;
    croak "Cannot trim a basedata with existing outputs\n"
      if scalar @outputs;

    croak "neither trim nor keep args specified\n"
      if !defined $args{keep} && !defined $args{trim};

    my $delete_empty_groups = $args{delete_empty_groups};
    my $delete_empty_labels = $args{delete_empty_labels};

    my $data;
    my $keep = $args{keep};    #  keep only these (overrides trim)
    my $trim = $args{trim};    #  delete all of these
    if ($keep) {
        $trim = undef;
        $data = $keep;
        say "[BASEDATA] Trimming labels from basedata using keep option";
    }
    else {
        $data = $trim;
        say "[BASEDATA] Trimming labels from basedata using trim option";
    }

    croak "keep or trim argument is not a ref\n"
      if !ref $data;

    my %keep_or_trim;

    if ( blessed $data) {

        #  assume it is a tree or matrix if blessed
      METHOD:
        foreach
          my $method (qw /get_named_nodes get_elements get_labels_as_hash/)
        {
            if ( $data->can($method) ) {
                %keep_or_trim = $data->$method;
                last METHOD;
            }
        }
    }
    elsif (is_arrayref($data)) {  #  convert to hash if needed
        @keep_or_trim{@$data} = (1) x scalar @$data;
    }
    elsif (is_hashref($data)) {
        %keep_or_trim = %$keep;
    }

    my $delete_count     = 0;
    my $delete_sub_count = 0;

  LABEL:
    foreach my $label ( $self->get_labels ) {
        if ($keep) {                        #  keep if in the list
            next LABEL if exists $keep_or_trim{$label};
        }
        elsif ($trim) {                     #  trim if not in the list
            next LABEL if !exists $keep_or_trim{$label};
        }

        $delete_sub_count += $self->delete_element(
            type                => 'LABELS',
            element             => $label,
            delete_empty_groups => $delete_empty_groups,
            delete_empty_labels => $delete_empty_labels,
        );
        $delete_count++;
    }

    if ($delete_count) {
        say "Deleted $delete_count labels and $delete_sub_count groups";
        $self->delete_cached_values;
        $self->get_groups_ref->delete_cached_values;
        $self->get_labels_ref->delete_cached_values;
        $self->rebuild_spatial_index;
    }

    my %results = (
        DELETE_COUNT     => $delete_count,
        DELETE_SUB_COUNT => $delete_sub_count,
    );

    return wantarray ? %results : \%results;
}

sub delete_labels {
    my $self = shift;
    my %args = @_;

    croak "Cannot delete labels when basedata has outputs\n"
      if $self->get_output_ref_count;

    my $elements = $args{labels};
    if (is_hashref($elements)) {
        $elements = [keys %$elements];
    }

    foreach my $element (@$elements) {
        $self->delete_element( type => 'LABELS', element => $element );
    }
    
    #  clear the numeric labels flag, just in case
    if (!$self->get_param ('NUMERIC_LABELS')) {
        $self->delete_param ('NUMERIC_LABELS');
    }

    return;
}

sub delete_groups {
    my $self = shift;
    my %args = @_;

    croak "Cannot delete groups when basedata has outputs\n"
      if $self->get_output_ref_count;

    my $elements = $args{groups};
    if (is_hashref($elements)) {
        $elements = [keys %$elements];
    }

    foreach my $element (@$elements) {
        $self->delete_element( type => 'GROUPS', element => $element );
    }

    return;
}

sub delete_label {
    my $self = shift;
    my %args = @_;

    my $label = $args{label} // croak "Argument 'label' not defined\n";

    my $result = $self->delete_element( %args, type => 'LABELS', element => $label );
    
    #  clear the numeric labels flag, just in case we only have numeric data remaining
    if (!$self->get_param ('NUMERIC_LABELS')) {
        $self->delete_param ('NUMERIC_LABELS');
    }
    
    return $result;
}

sub delete_group {
    my $self = shift;
    my %args = @_;

    my $group = $args{group} // croak "Argument 'group' not defined\n";

    return $self->delete_element( %args, type => 'GROUPS', element => $group );
}

#  delete all occurrences of this label (or group) from the LABELS and GROUPS sub hashes
sub delete_element {
    my $self = shift;
    my %args = @_;

    croak "Label or Group not specified in delete_element call\n"
      if !defined $args{type};

    my $type = uc( $args{type} );
    if ($type eq 'GROUP' || $type eq 'LABEL') {
        $type .= 'S';  
    }
    croak "Invalid element type in call to delete_element, $type\n"
      if $type ne 'GROUPS' && $type ne 'LABELS';

    croak "Element not specified in delete_element call\n"
      if !defined $args{element};
    my $element = $args{element};

    #  allows us to deal with both labels and groups
    my $other_type =
      $type eq 'GROUPS'
      ? 'LABELS'
      : 'GROUPS';

    my $type_ref       = $self->{$type};
    my $other_type_ref = $self->{$other_type};

    my $remove_other_empties = $args{
        $type eq 'GROUPS'
        ? 'delete_empty_labels'
        : 'delete_empty_groups'
    };
    $remove_other_empties //= 1;

    my $subelement_cut_count = 0;

#  call the Biodiverse::BaseStruct::delete_element sub to clean the $type element
    my @deleted_subelements = $type_ref->delete_element( element => $element );

    #  could use it directly in the next loop, but this is more readable

#  now we adjust those $other_type elements that have been affected (eg correct Label ranges etc).
#  use the set of groups containing deleted labels that need correcting (or vice versa)
    foreach my $subelement (@deleted_subelements) {

#print "ELEMENT $element, SUBELEMENT $subelement\n";
#  switch the element/subelement values as they are reverse indexed in $other_type
        $other_type_ref->delete_sub_element(
            %args,
            element    => $subelement,
            subelement => $element,
        );
        if (   $remove_other_empties
            && $other_type_ref->get_variety( element => $subelement ) == 0 )
        {
            # we have wiped out all groups with this label
            # so we need to remove it from the data set
            $other_type_ref->delete_element( element => $subelement );
            $subelement_cut_count++;
        }
    }

    return $subelement_cut_count;
}

#  delete a subelement from a label or a group
sub delete_sub_element {
    my ( $self, %args ) = @_;

    my $label = $args{label};
    my $group = $args{group};

    my $groups_ref = $self->get_groups_ref;
    my $labels_ref = $self->get_labels_ref;

    my $labels_remaining = $labels_ref->delete_sub_element_aa( $label, $group )
      // 1;
    my $groups_remaining = $groups_ref->delete_sub_element_aa( $group, $label )
      // 1;

    #  clean up if labels or groups are now empty
    my $delete_empty_gps = $args{delete_empty_groups} // 1;
    my $delete_empty_lbs = $args{delete_empty_labels} // 1;

    if ( $delete_empty_gps && !$groups_remaining ) {
        $self->delete_element(
            type    => 'GROUPS',
            element => $group,
        );
    }
    if ( $delete_empty_lbs && !$labels_remaining ) {
        $self->delete_element(
            type    => 'LABELS',
            element => $label,
        );
    }

    1;
}

#  Array args version of delete_sub_element.
#  Always deletes elements if they are empty.
sub delete_sub_element_aa {
    my ( $self, $label, $group ) = @_;

    #my $groups_ref = $self->get_groups_ref;
    #my $labels_ref = $self->get_labels_ref;

    #  return value of delete_sub_element_aa
    #  is the number of subelements remaining,
    #  or undef if no subelements list

    if ( !( $self->get_labels_ref->delete_sub_element_aa( $label, $group ) // 1 ) ) {
        $self->delete_element(
            type    => 'LABELS',
            element => $label,
        );
    }

    if ( !( $self->get_groups_ref->delete_sub_element_aa( $group, $label ) // 1 ) ) {
        $self->delete_element(
            type    => 'GROUPS',
            element => $group,
        );
    }

    1;
}

sub delete_sub_elements_collated_by_group {
    my $self       = shift;
    my %args       = @_;
    my $gp_lb_hash = $args{data};

    #  clean up if labels or groups are now empty
    my $delete_empty_gps = $args{delete_empty_groups} // 1;
    my $delete_empty_lbs = $args{delete_empty_labels} // 1;

    my $groups_ref = $self->get_groups_ref;
    my $labels_ref = $self->get_labels_ref;

    my %labels_processed;

    foreach my $group ( keys %$gp_lb_hash ) {
        my $label_subhash = $gp_lb_hash->{$group};
        foreach my $label ( keys %$label_subhash ) {
            $labels_processed{$label}++;
            $labels_ref->delete_sub_element_aa( $label, $group );
            $groups_ref->delete_sub_element_aa( $group, $label );
        }
    }

    if ($delete_empty_gps) {
        foreach my $group ( keys %$gp_lb_hash ) {
            next if $groups_ref->get_variety_aa($group);
            $self->delete_element(
                type    => 'GROUPS',
                element => $group,
            );
        }
    }
    if ($delete_empty_lbs) {
        foreach my $label (%labels_processed) {
            next if $labels_ref->get_variety_aa($label);
            $self->delete_element(
                type    => 'LABELS',
                element => $label,
            );
        }
    }

    1;
}

sub get_redundancy
{    #  A cheat method, assumes we want group redundancy by default,
        # drops the call down to the GROUPS object
    my $self = shift;

    return $self->get_groups_ref->get_redundancy(@_);
}

sub get_diversity {    #  more cheat methods
    my $self = shift;

    return $self->get_groups_ref->get_variety(@_);
}

sub get_richness {
    my $self = shift;

    return $self->get_groups_ref->get_variety(@_);
}

sub get_richness_aa {
    $_[0]->get_groups_ref->get_variety_aa( $_[1] );
}

sub get_label_sample_count {
    my ( $self, %args ) = @_;

    return $self->get_labels_ref->get_sample_count(
        element => $args{label},
        %args
    );
}

sub get_group_sample_count {
    my ( $self, %args ) = @_;

    return $self->get_groups_ref->get_sample_count(
        element => $args{group},
        %args
    );
}

#  get the abundance for a label as defined by the user,
#  or based on the variety of groups this labels occurs in
#  take the max if abundance < sample_count
sub get_label_abundance {
    my $self = shift;

    #no autovivification;

    my $labels_ref = $self->get_labels_ref;
    my $props = $labels_ref->get_list_values( @_, list => 'PROPERTIES' );

    my $sample_count = $self->get_label_sample_count(@_);

    my $abundance = max( ( $props->{ABUNDANCE} // -1 ), $sample_count );

    return $abundance;
}

#  get the range as defined by the user,
#  or based on the variety of groups this labels occurs in
#  take the max if range is < variety
sub get_range {
    my $self = shift;

    #no autovivification;

    my $labels_ref = $self->get_labels_ref;
    my $props = $labels_ref->get_list_values( @_, list => 'PROPERTIES' );

    my $variety = $labels_ref->get_variety(@_);

    my $range = max( ( $props->{RANGE} // -1 ), $variety );

    return $range;
}

#  for backwards compatibility
*get_range_shared     = \&get_range_intersection;
*get_range_aggregated = \&get_range_union;

# get the shared range for a set of labels
#  should return the range in scalar context and the keys in list context
#  WARNING - does not work for ranges set externally.
sub get_range_intersection {
    my $self = shift;
    my %args = @_;

    my $labels = $args{labels}
      || croak
      "[BaseData] get_range_intersection argument labels not specified\n";
    my $t = ref $labels;

    croak "[BaseData] get_range_intersection argument labels not an array or hash ref\n" 
        if (!is_arrayref($labels) && !is_hashref($labels));
    
    $labels = [keys %{$labels}] if (is_hashref($labels));
    
    #  now loop through the labels and get the groups that contain all the species
    my $elements = {};
    foreach my $label (@$labels) {
        next
          if not $self->exists_label( label => $label )
          ;    #  skip if it does not exist
        my $res = $self->calc_abc(
            label_hash1 => $elements,
            label_hash2 =>
              { $self->get_groups_with_label_as_hash( label => $label ) }
        );

        #  delete those that are not shared (label_hash1 and label_hash2)
        my @tmp =
          delete @{ $res->{label_hash_all} }{ keys %{ $res->{label_hash1} } };
        @tmp =
          delete @{ $res->{label_hash_all} }{ keys %{ $res->{label_hash2} } };
        $elements = $res->{label_hash_all};
    }

    return wantarray
      ? ( keys %$elements )
      : [ keys %$elements ];
}

#  get the aggregate range for a set of labels
sub get_range_union {
    my $self = shift;
    my %args = @_;

    my $labels = $args{labels} // croak "argument labels not specified\n";


    croak "argument labels not an array or hash ref"
        if !is_arrayref($labels) && !is_hashref($labels);

    if (is_hashref($labels)) {
        $labels = [keys %$labels];
    }

    #  now loop through the labels and get the elements they occur in
    my %shared_elements;
  LABEL:
    foreach my $label (@$labels) {
        my $elements_now =
          $self->get_groups_with_label_as_hash_aa ( $label );
        #  if empty hash then must be no groups with this label
        next LABEL if !scalar keys %$elements_now; 
        #  add these elements as a hash slice
        @shared_elements{ keys %$elements_now } = undef;
    }

    return scalar keys %shared_elements if $args{return_count};    #/

    return wantarray
      ? ( keys %shared_elements )
      : [ keys %shared_elements ];
}

sub get_groups {    #  get a list of the groups in the data set
    my $self = shift;

    #my %args = @_;
    return $self->get_groups_ref->get_element_list;
}

sub get_labels {    #  get a list of the labels in the selected BaseData
    my $self = shift;

    #my %args = @_;
    return $self->get_labels_ref->get_element_list;
}

#  get a hash of the labels in the selected BaseData
#  returns a copy to avoid autoviv problems
sub get_labels_as_hash {
    my $self = shift;

    #my %args = @_;
    my $labels = $self->get_labels;
    my %hash;
    @hash{@$labels} = (1) x @$labels;
    return wantarray ? %hash : \%hash;
}

sub get_groups_with_label {    #  get a list of the groups that contain $label
    my $self = shift;
    my %args = @_;
    confess "Label not specified\n" if !defined $args{label};
    return $self->get_labels_ref->get_sub_element_list(
        element => $args{label} );
}

sub get_groups_with_label_as_hash
{                              #  get a hash of the groups that contain $label
    my $self = shift;
    my %args = @_;

    croak "Label not specified\n" if !defined $args{label};

    if ( !defined $args{use_elements} ) {

        #  takes care of the wantarray stuff this way
        return $self->get_labels_ref->get_sub_element_hash_aa( $args{label} );
    }

    #  Not sure why the rest is here - is it used anywhere?
    #  violates the guideline that subs should do one thing only

    #  make a copy - don't want to delete the original
    my %results =
      $self->get_labels_ref->get_sub_element_hash( element => $args{label} );

    #  get a list of keys we don't want
    no warnings
      'uninitialized';    #  in case a list containing nulls is sent through
    my %sub_results = %results;
    delete @sub_results{ @{ $args{use_elements} } };

    #  now we delete those keys we don't want.  Twisted, but should work.
    delete @results{ keys %sub_results };

    return wantarray ? %results : \%results;
}

sub get_groups_with_label_as_hash_aa {
    $_[0]->get_labels_ref->get_sub_element_hash_aa( $_[1] );
}

#  get the complement of the labels in a group
#  - everything not in this group
sub get_groups_without_label {
    my $self = shift;

    my $groups = $self->get_groups_without_label_as_hash(@_);

    return wantarray ? keys %$groups : [ keys %$groups ];
}

sub get_groups_without_label_as_hash {
    my $self = shift;
    my %args = @_;

    croak "Label not specified\n"
      if !defined $args{label};

    my $label_gps =
      $self->get_labels_ref->get_sub_element_hash( element => $args{label} );

    my $gps = $self->get_groups_ref->get_element_hash;

    my %groups = %$gps;    #  make a copy
    delete @groups{ keys %$label_gps };

    return wantarray ? %groups : \%groups;
}

sub get_empty_groups {
    my $self = shift;
    my %args = @_;

    my @gps = grep { !$self->get_richness( element => $_ ) } $self->get_groups;

    return wantarray ? @gps : \@gps;
}

sub get_labels_in_group {    #  get a list of the labels that occur in $group
    my $self = shift;
    my %args = @_;
    croak "Group not specified\n" if !defined $args{group};
    return $self->get_groups_ref->get_sub_element_list(
        element => $args{group} );
}

#  get a hash of the labels that occur in $group
sub get_labels_in_group_as_hash {
    my $self = shift;
    my %args = @_;
    croak "Group not specified\n" if !defined $args{group};

   #return $self->get_groups_ref->get_sub_element_hash(element => $args{group});
    $self->get_groups_ref->get_sub_element_hash_aa( $args{group} );
}

#  get a hash of the labels that occur in $group
sub get_labels_in_group_as_hash_aa {
    my ( $self, $group ) = @_;
    $self->get_groups_ref->get_sub_element_hash_aa($group);
}

#  get the complement of the labels in a group
#  - everything not in this group
sub get_labels_not_in_group {
    my $self = shift;
    my %args = @_;
    croak "Group not specified\n" if !defined $args{group};
    my $gp_labels =
      $self->get_groups_ref->get_sub_element_hash( element => $args{group} );

    my %labels = $self->get_labels_ref->get_element_hash;    #  make a copy

    delete @labels{ keys %$gp_labels };

    return wantarray ? keys %labels : [ keys %labels ];
}

sub get_label_count {
    my $self = shift;

    return $self->get_labels_ref->get_element_count;
}

#  get the number of columns used to build the labels
sub get_label_column_count {
    my $self = shift;

    my $labels_ref = $self->get_labels_ref;
    my @labels     = $labels_ref->get_element_list;

    return 0 if not scalar @labels;

    my $label_columns =
      $labels_ref->get_element_name_as_array( element => $labels[0] );

    return scalar @$label_columns;
}

sub get_group_count {
    my $self = shift;

    return $self->get_groups_ref->get_element_count;
}

sub exists_group {
    my $self = shift;
    my %args = @_;
    return $self->get_groups_ref->exists_element(
        element => ( $args{group} // $args{element} ) );
}

sub exists_label {
    my $self = shift;
    my %args = @_;
    return $self->get_labels_ref->exists_element(
        element => ( $args{label} // $args{element} ) );
}

sub exists_label_aa {
    $_[0]->get_labels_ref->exists_element_aa( $_[1] );
}

sub exists_group_aa {
    $_[0]->get_groups_ref->exists_element_aa( $_[1] );
}

sub exists_label_in_group {
    my $self = shift;
    my %args = @_;

    $self->get_groups_ref->exists_sub_element_aa( $args{group}, $args{label} );
}

sub exists_group_with_label {
    my $self = shift;
    my %args = @_;

    $self->get_labels_ref->exists_sub_element_aa( $args{label}, $args{group} );
}

sub write_table {    #  still needed?
    my $self = shift;
    my %args = @_;
    croak "Type not specified\n" if !defined $args{type};

    #  Just pass the args straight through
    $self->{ $args{type} }->write_table(@_);

    return;
}

#  is this still needed?
sub write_sub_elements_csv {
    my $self = shift;
    my %args = @_;
    croak "Type not specified\n" if !defined $args{type};
    my $data = $self->{ $args{type} }->to_table( @_, list => 'SUBELEMENTS' );
    $self->write_table( @_, data => $data );

    return;
}

#  heavy usage sub, so bare-bones code
sub get_groups_ref {
    $_[0]->{GROUPS};
}

#  heavy usage sub, so bare-bones code
sub get_labels_ref {
    $_[0]->{LABELS};
}

sub build_spatial_index {    #  builds GROUPS, not LABELS
    my $self = shift;
    my %args = @_;

    my $gp_object   = $self->get_groups_ref;
    my $resolutions = $args{resolutions};
    my $cell_sizes  = $gp_object->get_cell_sizes;
    croak "[INDEX] Resolutions array does not match the "
        . "group object ($#$resolutions != $#$cell_sizes)\n"
      if $#$resolutions != $#$cell_sizes;

    #  now check each axis
    for my $i ( 0 .. $#$cell_sizes ) {
        no autovivification;
        #  we aren't worried about text or zero axes
        next if $cell_sizes->[$i] <= 0;
        
        croak "[INDEX] Non-text group axis resolution is "
            . "less than the index resolution, "
            . "axis $i ($resolutions->[$i] < $cell_sizes->[$i])\n"
          if $resolutions->[$i] < $cell_sizes->[$i];

        my $ratio = $resolutions->[$i] / $cell_sizes->[$i];

        croak "[INDEX] Index resolution is not a multiple "
            . "of the group axis resolution, "
            . "axis $i  ($resolutions->[$i] vs $cell_sizes->[$i])\n"
          if $ratio != int($ratio);
    }

    #  need to get a hash of all the groups and their coords.
    my %groups;
    foreach my $gp ( $self->get_groups ) {
        $groups{$gp} = $gp_object->get_element_name_as_array( element => $gp );
    }

    my $index;

    #  if no groups then remove it
    if ( !scalar keys %groups ) {
        $self->delete_param('SPATIAL_INDEX');
    }
    else {
        $index = Biodiverse::Index->new( %args, element_hash => \%groups );
        $self->set_param( SPATIAL_INDEX => $index );
    }

    return $index;
}

#sub delete_spatial_index {
#    my $self = shift;
#
#    my $name = $self->get_param ('NAME');
#
#    if ($self->get_param ('SPATIAL_INDEX')) {
#        print "[Basedata] Deleting spatial index from $name\n";
#        $self->delete_param('SPATIAL_INDEX');
#        return 1;
#    }
#
#    #print "[Basedata] Unable to delete a spatial index that does not exist\n";
#
#    return;
#}

sub rebuild_spatial_index {
    my $self = shift;

    my $index = $self->get_param('SPATIAL_INDEX');
    return if !defined $index;

    my $resolutions = $index->get_param('RESOLUTIONS');
    $self->build_spatial_index( resolutions => $resolutions );

    return;
}

sub delete_output {
    my $self = shift;
    my %args = @_;

    my $object = $args{output};
    my $name   = $object->get_param('NAME');

    my $class = blessed($object) || $EMPTY_STRING;
    my $type = $class;
    $type =~ s/.*://;    #  get the last part
    print "[BASEDATA] Deleting $type output $name\n";

    if ( $type =~ /Spatial/ ) {
        $self->{SPATIAL_OUTPUTS}{$name} = undef;
        delete $self->{SPATIAL_OUTPUTS}{$name};
    }
    elsif ( $type =~ /Cluster|Tree|RegionGrower/ ) {
        my $x = eval { $object->delete_cached_values_below };
        $self->{CLUSTER_OUTPUTS}{$name} = undef;
        delete $self->{CLUSTER_OUTPUTS}{$name};
    }
    elsif ( $type =~ /Matrix/ ) {
        $self->{MATRIX_OUTPUTS}{$name} = undef;
        delete $self->{MATRIX_OUTPUTS}{$name};
    }
    elsif ( $type =~ /Randomise/ ) {
        $self->do_delete_randomisation_lists(@_);
    }
    else {
        croak "[BASEDATA] Cannot delete this type of output: $class\n";
    }

    if ( $args{delete_basedata_ref} // 1 ) {
        $object->set_param( BASEDATA_REF => undef );    #  free its parent ref
    }
    $object = undef;                                    #  clear it

    return;
}

#  deletion of these is more complex than spatial and cluster outputs
sub do_delete_randomisation_lists {
    my $self = shift;
    my %args = @_;

    my $object = $args{output};
    my $name   = $object->get_name;

    say "[BASEDATA] Deleting randomisation output $name";

    #  loop over the spatial outputs and clear the lists
  BY_SPATIAL_OUTPUT:
    foreach my $sp_output ( $self->get_spatial_output_refs ) {
        my @lists =
          grep { $_ =~ /^$name>>/ } $sp_output->get_lists_across_elements;
        unshift @lists, $name;    #  for backwards compatibility

      BY_ELEMENT:
        foreach my $element ( $sp_output->get_element_list ) {
            $sp_output->delete_lists(
                lists   => \@lists,
                element => $element
            );
        }
    }

    #  and now the cluster outputs
    my @node_lists = (
        $name,
        $name . '_SPATIAL',    #  for backwards compat
        $name . '_ID_LDIFFS',
        $name . '_DATA',
    );

  BY_CLUSTER_OUTPUT:
    foreach my $cl_output ( $self->get_cluster_output_refs ) {
        my @lists = grep { $_ =~ /^$name>>/ } $cl_output->get_list_names_below;
        my @lists_to_delete = ( @node_lists, @lists );
        $cl_output->delete_lists_below( lists => \@lists_to_delete );
    }

    $self->{RANDOMISATION_OUTPUTS}{$name} = undef;
    delete $self->{RANDOMISATION_OUTPUTS}{$name};

    $object->set_param( BASEDATA_REF => undef );    #  free its parent ref

    return;
}

#  generic handler for adding outputs.
#  could eventually replace the specific forms
sub add_output {
    my $self = shift;
    my %args = @_;

    my $object =
         $args{object}
      || $args{type}
      || croak "[BASEDATA] No valid object or type arg specified, add_output\n";

    my $class = blessed($object) || $object;
    if ( $class =~ /spatial/i ) {
        return $self->add_spatial_output(@_);
    }
    elsif ( $class =~ /Cluster|RegionGrower/i ) {
        return $self->add_cluster_output(@_);
    }
    elsif ( $class =~ /randomisation/i ) {
        return $self->add_randomisation_output(@_);
    }
    elsif ( $class =~ /matrix/i ) {
        return $self->add_matrix_output(@_);
    }

    #  if we get this far then we have problems
    croak "[BASEDATA] No valid object or type arg specified, add_output\n";
}

#  get refs to the spatial and cluster objects
sub get_output_refs {
    my $self = shift;

    my @refs = (
        $self->get_spatial_output_refs,       $self->get_cluster_output_refs,
        $self->get_randomisation_output_refs, $self->get_matrix_output_refs,
    );

    return wantarray ? @refs : \@refs;
}

sub get_output_ref_count {
    my $self = shift;

    my $refs = $self->get_output_refs;

    return scalar @$refs;
}

sub get_output_refs_sorted_by_name {
    my $self = shift;

    my @sorted = natkeysort { $_->get_param('NAME') }
      $self->get_output_refs;

    return wantarray ? @sorted : \@sorted;
}

sub get_output_refs_of_class {
    my $self = shift;
    my %args = @_;

    my $class = blessed $args{class} // $args{class}
      or croak "argument class not specified\n";

    my @outputs;
    foreach my $ref ( $self->get_output_refs ) {
        next if !( blessed($ref) eq $class );
        push @outputs, $ref;
    }

    return wantarray ? @outputs : \@outputs;
}

sub delete_all_outputs {
    my $self = shift;

    foreach my $output ( $self->get_output_refs ) {
        $self->delete_output( output => $output );
    }

    return;
}

########################################################
#  methods to set, create and select the cluster outputs

sub add_cluster_output {
    my $self = shift;
    my %args = @_;

    my $object = $args{object};
    delete $args{object};    #  add an existing output

    my $class = $args{type} || 'Biodiverse::Cluster';
    my $name = $object ? $object->get_param('NAME') : $args{name};
    delete $args{name};

    croak "[BASEDATA] argument 'name' not specified\n"
      if !defined $name;

    croak
"[BASEDATA] Cannot replace existing cluster object $name. Use a different name.\n"
      if exists $self->{CLUSTER_OUTPUTS}{$name};

    if ($object) {

#  check if it is the correct type, warn if not - caveat emptor if wrong type
#  check is a bit underhanded, as it does not allow abstraction - clean up later if needed

        my $obj_class = blessed($object);
        carp "[BASEDATA] Object is not of valid type ($class)"
          if not $class =~ /cluster|regiongrower/i;

        $object->set_param( BASEDATA_REF => $self );
        $object->weaken_basedata_ref;
    }
    else {    #  create a new object
        $object = $class->new(
            QUOTES    => $self->get_param('QUOTES'),
            JOIN_CHAR => $self->get_param('JOIN_CHAR'),
            %args,
            NAME => $name
            ,    #  these two always over-ride user args (NAME can be an arg)
            BASEDATA_REF => $self,
        );
    }

    $self->{CLUSTER_OUTPUTS}{$name} = $object;

    return $object;
}

sub delete_cluster_output {
    my $self = shift;
    my %args = @_;
    croak "parameter 'name' not specified\n"
      if !defined $args{name};

    #delete $self->{CLUSTER_OUTPUTS}{$args{name}};
    $self->delete_output( output => $self->{CLUSTER_OUTPUTS}{ $args{name} }, );

    return;
}

sub get_cluster_output_ref {    #  return the reference for a specified output
    my $self = shift;
    my %args = @_;

    return if !exists $self->{CLUSTER_OUTPUTS}{ $args{name} };

    return $self->{CLUSTER_OUTPUTS}{ $args{name} };
}

sub get_cluster_output_refs {
    my $self = shift;
    return values %{ $self->{CLUSTER_OUTPUTS} } if wantarray;
    return [ values %{ $self->{CLUSTER_OUTPUTS} } ];
}

sub get_cluster_output_names {
    my $self = shift;
    return keys %{ $self->{CLUSTER_OUTPUTS} } if wantarray;
    return [ keys %{ $self->{CLUSTER_OUTPUTS} } ];
}

sub get_cluster_outputs {
    my $self = shift;
    return %{ $self->{CLUSTER_OUTPUTS} } if wantarray;
    return { %{ $self->{CLUSTER_OUTPUTS} } };
}

#  delete any cached values from the trees, eg _cluster_colour
#  allow more specific deletions by passing on the args
sub delete_cluster_output_cached_values {
    my $self = shift;
    print "[BASEDATA] Deleting cached values in cluster trees\n";
    foreach my $cluster ( $self->get_cluster_output_refs ) {
        $cluster->delete_cached_values_below(@_);
    }

    return;
}

########################################################
#  methods to set, create and select the current spatial object

sub add_spatial_output {
    my $self = shift;
    my %args = @_;

    croak "[BASEDATA] argument name not specified\n"
      if ( !defined $args{name} );

    my $class = 'Biodiverse::Spatial';
    my $name  = $args{name};
    delete $args{name};

    croak
"[BASEDATA] Cannot replace existing spatial object $name.  Use a different name.\n"
      if defined $self->{SPATIAL_OUTPUTS}{$name};

    my $object = $args{object};
    delete $args{object};    #  add an existing output

    if ($object) {

#  check if it is the correct type, warn if not - caveat emptor if wrong type
#  check is a bit underhanded, as it does not allow abstraction - clean up later if needed
        my $obj_class = blessed($object);
        carp "[BASEDATA] Object is not of type $class"
          if $class ne $obj_class;

        $object->set_param( BASEDATA_REF => $self );
    }
    else {    #  create a new object
        $object = $class->new(
            QUOTES    => $self->get_param('QUOTES'),
            JOIN_CHAR => $self->get_param('JOIN_CHAR'),
            %args,
            NAME => $name
            ,    #  these two always over-ride user args (NAME can be an arg)
            BASEDATA_REF => $self,
        );
    }
    $object->weaken_basedata_ref;

    $self->{SPATIAL_OUTPUTS}{$name} =
      $object;    #  add or replace (take care with the replace)

    return $object;
}

sub get_spatial_output_ref {    #  return the reference for a specified output
    my $self = shift;
    my %args = @_;

    my $name = $args{name};

    croak "Spatial output $name does not exist in the basedata\n"
      if !exists $self->{SPATIAL_OUTPUTS}{$name};

    return $self->{SPATIAL_OUTPUTS}{$name};
}

sub get_spatial_output_list {
    my $self = shift;

    my @result = sort keys %{ $self->{SPATIAL_OUTPUTS} };
    return wantarray ? @result : \@result;
}

sub delete_spatial_output {
    my $self = shift;
    my %args = @_;

    croak "parameter name not specified\n" if !defined $args{name};

    #delete $self->{SPATIAL_OUTPUTS}{$args{name}};
    $self->delete_output( output => $self->{SPATIAL_OUTPUTS}{ $args{name} } );

    return;
}

sub get_spatial_output_refs {
    my $self = shift;
    return wantarray
      ? values %{ $self->{SPATIAL_OUTPUTS} }
      : [ values %{ $self->{SPATIAL_OUTPUTS} } ];
}

sub get_spatial_output_names {
    my $self = shift;
    return wantarray
      ? keys %{ $self->{SPATIAL_OUTPUTS} }
      : [ keys %{ $self->{SPATIAL_OUTPUTS} } ];
}

sub get_spatial_outputs {
    my $self = shift;
    return wantarray
      ? %{ $self->{SPATIAL_OUTPUTS} }
      : { %{ $self->{SPATIAL_OUTPUTS} } };
}

########################################################
#  methods to set, create and select the current matrix output object

sub add_matrix_output {
    my $self = shift;
    my %args = @_;

    my $class = 'Biodiverse::Matrix';

    my $object = $args{object};
    delete $args{object};    #  add an existing output

    my $name;

    if ($object) {

#  check if it is the correct type, warn if not - caveat emptor if wrong type
#  check is a bit underhanded, as it does not allow abstraction - clean up later if needed
        my $obj_class = blessed($object);
        carp "[BASEDATA] Object is not of type $class"
          if not $class =~ /^$class/;

        $name = $object->get_param('NAME');

        croak
"[BASEDATA] Cannot replace existing matrix object $name.  Use a different name.\n"
          if defined $self->{MATRIX_OUTPUTS}{$name};

        $object->set_param( BASEDATA_REF => $self );
        $object->weaken_basedata_ref;
    }
    else {    #  create a new object
        croak 'Creation of matrix new objects is not supported - '
          . "they are added by the clustering system\n";

#croak "[BASEDATA] argument name not specified\n"
#    if (! defined $args{name});
#
#$name = $args{name};
#delete $args{name};
#
#croak "[BASEDATA] Cannot replace existing matrix object $name.  Use a different name.\n"
#    if defined $self->{MATRIX_OUTPUTS}{$name};
#
#$object = $class->new (
#    QUOTES       => $self->get_param('QUOTES'),
#    JOIN_CHAR    => $self->get_param('JOIN_CHAR'),
#    %args,
#    NAME         => $name,  #  these two always over-ride user args (NAME can be an arg)
#    BASEDATA_REF => $self,
#);
    }

    $self->{MATRIX_OUTPUTS}{$name} =
      $object;    #  add or replace (take care with the replace)

    return $object;
}

sub get_matrix_output_ref {    #  return the reference for a specified output
    my $self = shift;
    my %args = @_;

    return if !exists $self->{MATRIX_OUTPUTS}{ $args{name} };

    return $self->{MATRIX_OUTPUTS}{ $args{name} };
}

sub get_matrix_output_list {
    my $self   = shift;
    my @result = sort keys %{ $self->{MATRIX_OUTPUTS} };
    return wantarray ? @result : \@result;
}

sub delete_matrix_output {
    my $self = shift;
    my %args = @_;

    croak "parameter name not specified\n" if !defined $args{name};

    #delete $self->{MATRIX_OUTPUTS}{$args{name}};
    $self->delete_output( output => $self->{MATRIX_OUTPUTS}{ $args{name} } );

    return;
}

sub get_matrix_output_refs {
    my $self = shift;
    $self->_set_matrix_ouputs_hash;
    return wantarray
      ? values %{ $self->{MATRIX_OUTPUTS} }
      : [ values %{ $self->{MATRIX_OUTPUTS} } ];
}

sub get_matrix_output_names {
    my $self = shift;
    $self->_set_matrix_ouputs_hash;
    return wantarray
      ? keys %{ $self->{MATRIX_OUTPUTS} }
      : [ keys %{ $self->{MATRIX_OUTPUTS} } ];
}

sub get_matrix_outputs {
    my $self = shift;
    $self->_set_matrix_ouputs_hash;
    return wantarray
      ? %{ $self->{MATRIX_OUTPUTS} }
      : { %{ $self->{MATRIX_OUTPUTS} } };
}

sub _set_matrix_ouputs_hash {
    my $self = shift;
    if ( !$self->{MATRIX_OUTPUTS} ) {
        $self->{MATRIX_OUTPUTS} = {};
    }
}

########################################################
#  methods to set, create and select randomisation objects

sub add_randomisation_output {
    my $self = shift;
    my %args = @_;
    if ( !defined $args{name} ) {
        croak "[BASEDATA] argument name not specified\n";

        #return undef;
    }
    my $class = 'Biodiverse::Randomise';

    my $name = $args{name};
    delete $args{name};

    croak
"[BASEDATA] Cannot replace existing randomisation object $name.  Use a different name.\n"
      if exists $self->{RANDOMISATION_OUTPUTS}{$name};

    my $object = $args{object};
    delete $args{object};    #  add an existing output

    if ($object) {

#  check if it is the correct type, warn if not - caveat emptor if wrong type
#  check is a bit underhanded, as it does not allow abstraction - clean up later if needed
        my $obj_class = blessed($object);

        carp "[BASEDATA] Object is not of type $class"
          if $class ne $obj_class;

        $object->set_param( BASEDATA_REF => $self );
        $object->weaken_basedata_ref;
    }
    else {    #  create a new object
        $object = eval {
            $class->new(
                %args,
                NAME => $name
                ,   #  these two always over-ride user args (NAME can be an arg)
                BASEDATA_REF => $self,
            );
        };
        croak $EVAL_ERROR if $EVAL_ERROR;
    }

    $self->{RANDOMISATION_OUTPUTS}{$name} = $object;
    undef $object;
    return $self->{RANDOMISATION_OUTPUTS}{$name};

    #  fiddling to avoid SV leaks, possibly pointless
    #my $object2 = $object;
    #undef $object;
    #return $object2;
}

sub get_randomisation_output_ref
{    #  return the reference for a specified output
    my $self = shift;
    my %args = @_;
    return undef if !exists $self->{RANDOMISATION_OUTPUTS}{ $args{name} };
    return $self->{RANDOMISATION_OUTPUTS}{ $args{name} };
}

sub get_randomisation_output_list {
    my $self = shift;
    my @list = sort keys %{ $self->{RANDOMISATION_OUTPUTS} };
    return wantarray ? @list : \@list;
}

sub delete_randomisation_output {
    my $self = shift;
    my %args = @_;
    croak "parameter name not specified\n" if !defined $args{name};

    #delete $self->{SPATIAL_OUTPUTS}{$args{name}};
    $self->delete_output(
        output => $self->{RANDOMISATION_OUTPUTS}{ $args{name} } );

    return;
}

sub get_randomisation_output_refs {
    my $self = shift;
    return values %{ $self->{RANDOMISATION_OUTPUTS} } if wantarray;
    return [ values %{ $self->{RANDOMISATION_OUTPUTS} } ];
}

sub get_randomisation_output_names {
    my $self = shift;
    return keys %{ $self->{RANDOMISATION_OUTPUTS} } if wantarray;
    return [ keys %{ $self->{RANDOMISATION_OUTPUTS} } ];
}

sub get_randomisation_outputs {
    my $self = shift;
    return %{ $self->{RANDOMISATION_OUTPUTS} } if wantarray;
    return { %{ $self->{RANDOMISATION_OUTPUTS} } };
}

sub get_unique_randomisation_name {
    my $self = shift;

    my @names  = $self->get_randomisation_output_names;
    my $prefix = 'Rand';

    my $max = 0;
    foreach my $name (@names) {
        if ( $name =~ /^$prefix(\d+)$/ ) {
            my $num = $1;
            $max = $num if $num > $max;
        }
    }

    my $unique_name = $prefix . ( $max + 1 );

    return $unique_name;
}

########################################################
#  methods to get neighbours, parse parameters etc.

#  get the list of neighbours that satisfy the spatial condition
#  (or the set of elements that satisfy definition query)
sub get_neighbours {
    my $self = shift;
    my %args = @_;

    my $progress = $args{progress};

    my $element1 = $args{element};
    croak "argument element not specified\n" if !defined $element1;

    my $spatial_conditions = $args{spatial_conditions} // $args{spatial_params}
      || croak "[BASEDATA] No spatial_conditions argument\n";
    my $index         = $args{index};
    my $index_offsets = $args{index_offsets};
    my $is_def_query =
      $args{is_def_query};    #  some processing changes if a def query
    my $cellsizes = $self->get_cell_sizes;

    #  skip those elements that we want to ignore - allows us to avoid including
    #  element_list1 elements in these neighbours,
    #  therefore making neighbourhood parameter definitions easier.
    my %exclude_hash = $self->array_to_hash_keys(
        list  => $args{exclude_list},
        value => 1,
    );

    my $centre_coord_ref =
      $self->get_group_element_as_array( element => $element1 );

    my $groups_ref = $self->get_groups_ref;

#  Get the list of possible neighbours - should allow this as an arg?
#  Don't check the index unless it will result in fewer loop iterations overall.
#  Assumes the neighbour comparison checks cost as much as the index offset checks.
    my @compare_list;
    if (
           !defined $index
        || !defined $index_offsets
        || ( $index->get_item_density_across_all_poss_index_elements * scalar
            keys %$index_offsets ) > ( $self->get_group_count / 2 )
      )
    {
        @compare_list = $self->get_groups;
    }
    else
    { #  We have a spatial index defined and a favourable ratio of offsets to groups
            #  so we get the possible list of neighbours from the index.
        my $element_array =
          $self->get_group_element_as_array( element => $element1 );

        my $index_csv_obj = $index->get_cached_value('CSV_OBJECT');

        my $index_coord = $index->snap_to_index(
            element_array => $element_array,
            as_array      => 1,
        );
        foreach my $offset ( values %{ $args{index_offsets} } ) {

            #  need to get an array from the index to fit
            #  with the get_groups results
            push @compare_list,
              $index->get_index_elements_as_array(
                element    => $index_coord,
                offset     => $offset,
                csv_object => $index_csv_obj,
              );
        }
    }

    #  Do we have a shortcut where we don't have to deal
    #  with all of the comparisons? (messy at the moment)
    my $type_is_subset = ( $spatial_conditions->get_result_type eq 'subset' );

    #print "$element1  Evaluating ", scalar @compare_list, " nbrs\n";

    my $target_comparisons = scalar @compare_list;
    my $i                  = 0;
    my %valid_nbrs;
  NBR:
    foreach my $element2 ( sort @compare_list ) {

        if ($progress) {
            $i++;
            $progress->update(
                "Neighbour comparison $i of $target_comparisons\n",
                $i / $target_comparisons,
            );
        }

        #  some of the elements may be undefined based
        #  on calls to get_index_elements
        next NBR if not defined $element2;

        #  skip if in the exclusion list
        next NBR if exists $exclude_hash{$element2};

        #  warn and skip if already done
        if ( exists $valid_nbrs{$element2} ) {
            warn "[BaseData] get_neighbours: Double checking of $element2\n";
            next NBR;
        }

        #  make the neighbour coord available to the spatial_conditions
        my @coord = $self->get_group_element_as_array( element => $element2 );

        my %eval_args;

        #  Reverse some args for def queries,
        #  partly for backwards compatibility,
        #  partly for cleaner logic.
        if ($is_def_query) {
            %eval_args = (
                coord_array1 => \@coord,
                coord_id1    => $element2,
                coord_id2    => $element2,
            );
        }
        else {
            %eval_args = (
                coord_array1 => $centre_coord_ref,
                coord_array2 => \@coord,
                coord_id1    => $element1,
                coord_id2    => $element2,
            );
        }

        my $success = $spatial_conditions->evaluate(
            %eval_args,
            cellsizes     => $cellsizes,
            caller_object => $self,        #  pass self on by default
        );

        if ($type_is_subset) {
            my $subset_nbrs = $spatial_conditions->get_cached_subset_nbrs(
                coord_id => $element1 );
            if ($subset_nbrs) {
                %valid_nbrs = %$subset_nbrs;

                #print "Found ", scalar keys %valid_nbrs, " valid nbrs\n";
                delete @valid_nbrs{ keys %exclude_hash };
                $spatial_conditions->clear_cached_subset_nbrs(
                    coord_id => $element1 );
                last NBR;
            }
        }

        #  skip if not a nbr
        next NBR if not $success;

# If it has survived then it must be valid.
#$valid_nbrs{$element2} = $spatial_conditions->get_param ('LAST_DISTS');  #  store the distances for possible later use
#  Don't store the dists - serious memory issues for large files
#  But could store $success if we later want to support weighted calculations
        $valid_nbrs{$element2} = 1;
    }

    if ( $args{as_array} ) {
        return wantarray ? keys %valid_nbrs : [ keys %valid_nbrs ];
    }
    else {
        return wantarray ? %valid_nbrs : \%valid_nbrs;
    }
}

sub get_neighbours_as_array {
    my $self = shift;
    return $self->get_neighbours( @_, as_array => 1 );

#  commented old stuff, hopefully the new approach will save some shunting around of memory?
#my @array = sort keys %{$self->get_neighbours(@_)};
#return wantarray ? @array : \@array;  #  return reference in scalar context
}

#  Modified version of get_spatial_outputs_with_same_nbrs.
#  Useful for faster nbr searching for spatial analyses, and matrix building for cluster analyses
#  It can eventually supplant that sub.
sub get_outputs_with_same_spatial_conditions {
    my $self = shift;
    my %args = @_;

    my $compare = $args{compare_with}
      || croak "[BASEDATA] compare_with argument not specified\n";

    my $sp_params = $compare->get_spatial_conditions;
    my $def_query = $compare->get_def_query;
    if ( defined $def_query && ( length $def_query ) == 0 ) {
        $def_query = undef;
    }

    my $def_conditions;
    if ( blessed $def_query) {
        $def_conditions = $def_query->get_conditions_unparsed();
    }

    my @outputs = $self->get_output_refs_of_class( class => $compare );

    my @comparable_outputs;

  LOOP_OUTPUTS:
    foreach my $output (@outputs) {
        next LOOP_OUTPUTS if $output eq $compare;    #  skip the one to compare

        my $completed = $output->get_param('COMPLETED');
        next LOOP_OUTPUTS if defined $completed and !$completed;

        my $def_query_comp = $output->get_def_query;
        if ( defined $def_query_comp && ( length $def_query_comp ) == 0 ) {
            $def_query_comp = undef;
        }

        next LOOP_OUTPUTS
          if ( defined $def_query ) ne ( defined $def_query_comp );

        if ( defined $def_query ) {

            #  check their def queries match
            my $def_conditions_comp =
              eval { $def_query_comp->get_conditions_unparsed() }
              // $def_query_comp;
            my $def_conditions_text =
              eval { $def_query->get_conditions_unparsed() } // $def_query;
            next LOOP_OUTPUTS if $def_conditions_comp ne $def_conditions_text;
        }

        my $sp_params_comp = $output->get_spatial_conditions || [];

        #  must have same number of conditions
        next LOOP_OUTPUTS if scalar @$sp_params_comp != scalar @$sp_params;

        my $i = 0;
        foreach my $sp_obj (@$sp_params_comp) {
            next LOOP_OUTPUTS
              if ( $sp_params->[$i]->get_param('CONDITIONS') ne
                $sp_obj->get_conditions_unparsed() );
            $i++;
        }

        #  if we get this far then we have a match
        push @comparable_outputs, $output;    #  we want to keep this one
    }

    return wantarray ? @comparable_outputs : \@comparable_outputs;
}

sub has_empty_groups {
    my $self = shift;

    foreach my $group ( $self->get_groups ) {
        my $labels = $self->get_labels_in_group( group => $group );

        return 0 if scalar @$labels;
    }

    return 1;
}

sub cellsizes_and_origins_match {
    my $self = shift;
    my %args = @_;

    my $from_bd = $args{from} || croak "from argument is undefined\n";

    my @cellsizes      = $self->get_cell_sizes;
    my @from_cellsizes = $from_bd->get_cell_sizes;

    my @cellorigins      = $self->get_cell_origins;
    my @from_cellorigins = $from_bd->get_cell_origins;

    for my $i ( 0 .. $#cellsizes ) {
        return 0
          if $cellsizes[$i] != $from_cellsizes[$i]
          || $cellorigins[$i] != $from_cellorigins[$i];
    }

    return 1;
}

#  merge labels and groups from another basedata into this one
sub merge {
    my $self = shift;
    my %args = @_;

    my $from_bd = $args{from} || croak "from argument is undefined\n";

    croak "Cannot merge into self" if $self eq $from_bd;

    croak "Cannot merge into basedata with existing outputs"
      if $self->get_output_ref_count;

    croak "cannot merge into basedata with different cell sizes and offsets"
      if !$self->cellsizes_and_origins_match(%args);

    my $csv_object = $self->get_csv_object(
        sep_char   => $self->get_param('JOIN_CHAR'),
        quote_char => $self->get_param('QUOTES'),
    );

    foreach my $group ( $from_bd->get_groups ) {
        my $tmp = $from_bd->get_labels_in_group_as_hash_aa($group);

        if ( !scalar keys %$tmp ) {

            #  make sure we get any empty groups
            #  - needed?  should be handled in add_elements_collated call
            $self->add_element(
                group              => $group,
                count              => 0,
                csv_object         => $csv_object,
                allow_empty_groups => 1,
            );
        }
        $self->add_elements_collated_simple_aa( { $group => $tmp },
            $csv_object );
    }

    #  make sure we get any labels without groups
    foreach my $label ( $from_bd->get_labels ) {
        my $tmp = $from_bd->get_groups_with_label_as_hash( label => $label );

        next if scalar keys %$tmp;

        $self->add_element(
            label              => $label,
            count              => 0,
            csv_object         => $csv_object,
            allow_empty_groups => 1,
        );
    }

    return;
}

sub reintegrate_after_parallel_randomisations {
    my $self = shift;
    my %args = @_;
    
    my $bd_from = $args{from} || croak "'from' argument is undefined\n";

    croak "Cannot merge into self" if $self eq $bd_from;
    croak "Cannot merge into basedata with different cell sizes and offsets"
      if !$self->cellsizes_and_origins_match (%args);
    croak "No point reintegrating into basedata with no outputs"
      if !$self->get_output_ref_count;

    my @randomisations_to   = $self->get_randomisation_output_refs;
    my @randomisations_from = $bd_from->get_randomisation_output_refs;

    return if !scalar @randomisations_to || !scalar @randomisations_from;

    my @outputs_to   = $self->get_output_refs_sorted_by_name;
    my @outputs_from = $bd_from->get_output_refs_sorted_by_name;
    
    croak "Cannot reintegrate when number of outputs differs"
      if scalar @outputs_to != scalar @outputs_from;

    foreach my $i (0 .. $#outputs_to) {
        croak "mismatch of output names"
          if $outputs_to[$i]->get_name ne $outputs_from[$i]->get_name;
    }

    #  Check groups and labels unless told otherwise
    #  (e.g. we have control of the process so they will always match)
    my $comp = Data::Compare->new;
    if (!$args{no_check_groups_and_labels}) {
        my $gp_to   = $self->get_groups_ref;
        my $gp_from = $bd_from->get_groups_ref;
        croak "Group and/or label mismatch"
          if !$comp->Cmp (
            scalar $gp_to->get_element_hash,
            scalar $gp_from->get_element_hash,
          );
    }

    my @randomisations_to_reintegrate;

  RAND_FROM:
    foreach my $rand_from (@randomisations_from) {
        my $name_from  = $rand_from->get_name;
        my $rand_to    = $self->get_randomisation_output_ref (
            name => $name_from,
        );
        my $init_states_to   = $rand_to->get_prng_init_states_array;
        my $init_states_from = $rand_from->get_prng_init_states_array;

        # avoid double reintegration
        foreach my $init_state_to (@$init_states_to) {
            foreach my $init_state_from (@$init_states_from) {
                croak 'Attempt to reintegrate randomisation '
                     .'when its initial PRNG state has already been used'
                  if $comp->Cmp ($init_state_to, $init_state_from);
            }
        }

        push @randomisations_to_reintegrate, $name_from;

        # We are going to add this one, so update the
        # init and end states, and the iteration counts 
        push @$init_states_to, @$init_states_from;
        my $prng_total_counts_array   = $rand_to->get_prng_total_counts_array;
        push @$prng_total_counts_array, $rand_from->get_prng_total_counts_array;
        my $prng_end_states_array     = $rand_to->get_prng_end_states_array;
        push @$prng_end_states_array,   $rand_from->get_prng_end_states_array;

        my $total_iters = sum (@$prng_total_counts_array);
        $rand_to->set_param (TOTAL_ITERATIONS => $total_iters);
    }

    my $rand_list_re_text
      = '^(?:'
      . join ('|', uniq @randomisations_to_reintegrate)
      . ')>>(?!p_rank>>)';
    my $re_rand_list_names = qr /$rand_list_re_text/;

    #  now we can finally get some work done
    #  working on spatial only for now
  OUTPUT:
    foreach my $i (0 .. $#outputs_to) {
        my $to   = $outputs_to[$i];
        my $from = $outputs_from[$i];

        #  this is not a generic enough check
        next OUTPUT
          if not blessed ($to) =~ /Spatial|Cluster|RegionGrower|Tree/;

        $to->reintegrate_after_parallel_randomisations (
            from => $from,
            no_check_groups_and_labels => 1,
            randomisations_to_reintegrate => \@randomisations_to_reintegrate,
        );

    }

    return;
}


sub numerically {$a <=> $b};


#  let the system handle it most of the time
sub DESTROY {
    my $self = shift;
    my $name = $self->get_param('NAME') || $EMPTY_STRING;

    #print "DESTROYING BASEDATA $name\n";
    #$self->delete_all_outputs;  #  delete children which refer to this object
    #print "DELETED BASEDATA $name\n";

    #$self->_delete_params_all;

    foreach my $key ( sort keys %$self ) {    #  clear all the top level stuff
                                              #$self->{$key} = undef;
                                              #print "Deleting BD $key\n";
        delete $self->{$key};
    }
    undef %$self;

    #  let perl handle the rest

    return;
}

# could probably implement this by creating an ElementProperty object
# and calling rename_labels. Would need an 'import from hash' function
# for ElementProperty.

# doesn't handle numeric labels
sub remap_labels_from_hash {
    my $self  = shift;
    my %args  = @_;
    my %remap = %{ $args{remap} };

    foreach my $label ( keys %remap ) {
        my $remapped = $remap{$label};
 
        next if !defined $remapped || $label eq $remapped;

        $self->rename_label(
            label            => $label,
            new_name         => $remapped,
            no_numeric_check => 1,
        );
    }

    return;
}

=head1 NAME

Biodiverse::BaseData

=head1 SYNOPSIS

  use Biodiverse::BaseData;
  $object = Biodiverse::BaseData->new();

=head1 DESCRIPTION

TO BE FILLED IN

=head1 METHODS

=over

=item remap_labels_from_hash

Given a hash mapping from names of labels currently in this BaseData
to desired new names, renames the labels accordingly.

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

1;
