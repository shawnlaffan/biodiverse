package Biodiverse::BaseData;

#  package containing methods to access and store a Biodiverse BaseData object
use 5.036;

use strict;
use warnings;

#  avoid redefined warnings due to
#  https://github.com/rurban/Cpanel-JSON-XS/issues/65
use JSON::PP ();

use Carp;
#use Data::Dumper;
use POSIX qw {fmod floor};
use Scalar::Util qw /looks_like_number blessed/;
use List::Util 1.45 qw /max min sum pairs uniq pairmap/;
use List::MoreUtils qw /first_index/;
use Path::Tiny qw /path/;
use Geo::Converter::dms2dd qw {dms2dd};
use Regexp::Common qw /number/;
use Data::Compare ();

use Ref::Util qw { :all };
use Sort::Key::Natural qw /natkeysort/;


use experimental qw /refaliasing declared_refs for_list/;


use English qw { -no_match_vars };

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

our $VERSION = '5.0';

use parent qw {
    Biodiverse::Common
    Biodiverse::BaseData::Import
    Biodiverse::BaseData::ManageOutputs
    Biodiverse::BaseData::Exclusions
    Biodiverse::BaseData::LabelRanges
};

our $EMPTY_STRING = q{};

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
        #  hack to avoid seg faults with csv objects
        $file_loaded->get_groups_ref->delete_element_name_csv_object;
        $file_loaded->get_labels_ref->delete_element_name_csv_object;

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
    #  Ideally we would not copy the basedata cell info,
    #  but for now we ensure it is not the same reference.
    $self->{LABELS} = Biodiverse::BaseStruct->new(
        %params_hash,
        CELL_SIZES   => [@$cell_sizes],
        CELL_ORIGINS => [@$cell_origins],
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
        local $self->{_cache}                = undef;
        $cloneref = $self->SUPER::clone();

    }
    elsif ( $args{no_elements} ) {

        #  temporarily override the groups and labels so they aren't cloned
        # element deletion is very dirty
        # - basedata should not know about basestruct internals
        local $self->{GROUPS}{ELEMENTS}      = {};
        local $self->{LABELS}{ELEMENTS}      = {};
        local $self->{SPATIAL_OUTPUTS}       = {};
        local $self->{CLUSTER_OUTPUTS}       = {};
        local $self->{RANDOMISATION_OUTPUTS} = {};
        local $self->{MATRIX_OUTPUTS}        = {};
        local $self->{_cache}                = undef;
        $cloneref = $self->SUPER::clone();

    }
    else {
        $cloneref = $self->SUPER::clone(%args);
    }

    #my $clone2 = $cloneref;  #  for testing purposes
    return $cloneref;
}

sub clone_with_reduced_resolution {
    my ($self, %args) = @_;
    
    my $new_cell_sizes     = $args{cell_sizes};
    my $new_cell_origins   = $args{cell_origins}
                           // $self->get_cell_origins;
    my $current_cell_sizes   = $self->get_cell_sizes;
    my $current_cell_origins = $self->get_cell_origins;
    
    croak "No new cell sizes passed, process is futile\n"
      if !$new_cell_sizes;
    croak "New cell size array has incorrect dimensions\n"
      if scalar @$new_cell_sizes != scalar @$current_cell_sizes;
    croak "New cell origins array has incorrect dimensions\n"
      if scalar @$new_cell_origins != scalar @$current_cell_origins;

    #  per-axis sanity checks
    my $same_count = 0;
    foreach my $i (0 .. $#$current_cell_sizes) {
        my $current = $current_cell_sizes->[$i];
        my $new     = $new_cell_sizes->[$i];
        
        croak "cannot change resolution of a non-numeric axis (axis $i)\n"
          if $current < 0 and $current != $new;
        croak "new axis size is less than current"
          if $current > $new;
        #  could lead to precision issues later
        #  ...and it did so we now have the nasty sprintf code
        my $fmod = ($current and $new and $current ne $new)
          ? fmod (sprintf("%.14f",$new) / sprintf("%.14f",$current), 1)
          : 0;
        croak "new size for axis $i of $new is not a multiple of current ($current), off by $fmod"
          if ($current and $new) and $fmod;
        if ($current == $new) {
            $same_count++;
        }
        
        my $current_o = $current_cell_origins->[$i];
        my $new_o     = $new_cell_origins->[$i];
        $fmod = ($current and $current_o ne $new_o)
          ? fmod (
                sprintf ("%.14f", abs ($new_o - $current_o)) /
                sprintf ("%.14f", $current),
            1)
          : 0;
        croak "new origin for axis $i of $new_o does not conform "
            . "with current ($current_o) and axis size ($current)"
          if $fmod;
    }      
    
    my $new_bd = Biodiverse::BaseData->new (
        NAME => $args{name} // (($self->get_name // '') . '_but_coarser'),
        CELL_SIZES   => $new_cell_sizes,
        CELL_ORIGINS => $new_cell_origins,
    );
    
    my $out_csv = $self->get_csv_object(
        sep_char   => $self->get_param('JOIN_CHAR'),
        quote_char => $self->get_param('QUOTES'),
    );
    
    my $lb_props = Biodiverse::ElementProperties->new;
    my %label_props_checked;
    my $label_props_count;

    my $lb  = $self->get_labels_ref;
    my $gps = $self->get_groups;
    foreach my $group (@$gps) {
        my @gp_fields;
        my $gp_array = $self->get_group_element_as_array (element => $group);
        foreach my $i (0 .. $#$gp_array) {
            my $origin = $new_cell_origins->[$i];
            my $g_size = $new_cell_sizes->[$i];
            if ( $g_size > 0 ) {
                my $cell = floor( ( $gp_array->[$i] - $origin ) / $g_size );
                my $grp_centre =
                  $origin + $cell * $g_size + ( $g_size / 2 );
                push @gp_fields, $grp_centre;
            }
            else {
                push @gp_fields, $gp_array->[$i];
            }
        }
        my $grpstring = $self->list2csv(
            list       => \@gp_fields,
            csv_object => $out_csv,
        );
        my $labels = $self->get_labels_in_group_as_hash_aa ($group);
        LABEL:
          foreach my $label (keys %$labels) {
            $new_bd->add_element (
                group => $grpstring,
                label => $label,
                count => $labels->{$label},
            );
            next LABEL if $label_props_checked{$label};
            $label_props_checked{$label}++;
            my $props = $lb->get_list_ref (
                element    => $label,
                list       => 'PROPERTIES',
                autovivify => 0,
            );
            if ($props) {
                $lb_props->set_element_properties (
                    element    => $label,
                    properties => {%$props},  #  shallow copy
                );
                $label_props_count++;
            }
        }
    }
    if ($label_props_count) {
        $new_bd->assign_element_properties (
            type              => 'labels',
            properties_object => $lb_props,
        );
    }
    
    return $new_bd;
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

    my $gp_count  = $self->get_group_count;
    my $lb_count  = $self->get_label_count;
    my $smp_count = $self->get_sample_count;
    my $sp_count = scalar @{ $self->get_spatial_output_refs };
    my $cl_count = scalar @{ $self->get_cluster_output_refs };
    my $rd_count = scalar @{ $self->get_randomisation_output_refs };
    my $mx_count = scalar @{ $self->get_matrix_output_refs };

    push @description, "Group count: $gp_count";
    push @description, "Label count: $lb_count";
    push @description, "Sample count: $smp_count";
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
        my $coord = $gp->get_element_name_as_array_aa ( $gp_name );

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

    my $new = $self->clone(no_outputs => 1);

    #  transpose groups and labels
    @$new{qw /GROUPS LABELS/} = @$new{qw /LABELS GROUPS/};

    #  set the correct cell sizes.
    #  The default is just in case, and may cause trouble later on
    my @cell_sizes = $self->get_labels_ref->get_cell_sizes || (-1);
    $new->set_param( CELL_SIZES => [@cell_sizes] );    #  make sure it's a copy

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

#  what a name!  
sub get_stats_for_assign_group_properties_from_rasters {
    my %stats
      = reverse map {$_ => lc $_ =~ s/^NUM_//r}
        (qw /NUM_CV NUM_KURT NUM_MAX NUM_MEAN NUM_MIN NUM_N NUM_RANGE NUM_SD NUM_SKEW/);
    return wantarray ? %stats : \%stats;
}

#  issue 761 - make this easier
sub assign_group_properties_from_rasters {
    my $self = shift;
    my %args = @_;

    #  Clean up in case we add different ones.
    #  We cannot get the list here as we might
    #  only be adding a subset of elements
    my $gp_ref = $self->get_groups_ref;
    $gp_ref->delete_cached_values;

    my @cell_sizes   = $self->get_cell_sizes;
    my @cell_origins = $self->get_cell_origins;

    my $axis_count = scalar @cell_sizes;    
    croak "Target basedata must have 2 axes to attach group properties from raster.  You have $axis_count."
      if $axis_count != 2;
    croak "rasters argument must be an array ref"
      if not is_arrayref($args{rasters});

    my $stats = $args{stats} // ['mean'];
    $stats = [map {lc} @$stats];
    croak "stats argument must be an array ref"
      if not is_arrayref($stats);

    my $die_if_no_overlap = $args{die_if_no_overlap};
    my $return_basedatas  = $args{return_basedatas};
    my @raster_basedatas;
    my @rasters = @{$args{rasters}};

    #  this should be in its own sub and be generated from the indices metadata
    my %valid_prop_stats
      = $self->get_stats_for_assign_group_properties_from_rasters;
    my %target_props;
    @target_props{@$stats} = @valid_prop_stats{@$stats};
    croak "invalid stats argument passed, must be one or more of "
         . (join ' ', sort keys %valid_prop_stats)
      if grep {!defined} values %target_props;


    my %common_args = (
        labels_as_bands   => 0,
        raster_origin_e   => $cell_origins[0],
        raster_origin_n   => $cell_origins[1],
        raster_cellsize_e => $cell_sizes[0],
        raster_cellsize_n => $cell_sizes[1],
    );
    my %gp_prop_list_ref_cache; 
    my $class = blessed $self;

    my $bounds  = $self->get_coord_bounds;
    my $bnd_max = $bounds->{MAX};
    my $bnd_min = $bounds->{MIN};

    foreach my $raster (@rasters) {
        my $path = path ($raster);
        my $raster_name = $path->basename;
        #  will go wrong if file has dot but no extension like .tif
        $raster_name =~ s/\.\w+?$//;

        my $new_bd = $class->new(
            NAME         => 'raster_props_from_' . $raster_name,
            CELL_SIZES   => [@cell_sizes],
            CELL_ORIGINS => [@cell_origins],
        );
        $new_bd->import_data_raster (
            %common_args,
            input_files => [$raster],
        );

        if ($die_if_no_overlap) {
            #  ideally we would check this before importing
            my $bounds_new_bd  = $new_bd->get_coord_bounds;
            my $new_bnd_max = $bounds_new_bd->{MAX};
            my $new_bnd_min = $bounds_new_bd->{MIN};
            die "Raster $raster_name does not overlap with the target basedata"
              if   $new_bnd_min->[0] > $bnd_max->[0]
                or $new_bnd_min->[1] > $bnd_max->[1]
                or $new_bnd_max->[0] < $bnd_min->[0]
                or $new_bnd_max->[1] < $bnd_min->[1];
        }
        
        #  calculate the stats per cell
        my $sp = $new_bd->add_spatial_output (
            name => 'numeric_labels',
        );
        $sp->run_analysis (
            spatial_conditions => ['sp_self_only()'],
            calculations       => ['calc_numeric_label_stats'],
        );

        #  now extract the relevant stats
      GROUP:
        foreach my $gp ($self->get_groups) {
            next GROUP if !$sp->exists_element_aa($gp);

            my $sp_list = $sp->get_list_ref (
                element    => $gp,
                autovivify => 0,
                list       => 'SPATIAL_RESULTS',
            );
            next GROUP if !$sp_list;

            my $el_props = $gp_prop_list_ref_cache{$gp}
              //= $gp_ref->get_list_ref (
                element => $gp,
                list    => 'PROPERTIES',
            );

            #  need to handle more than the mean
            foreach my $stat (keys %target_props) {
                my $old_key = $target_props{$stat};
                my $new_key = "${raster_name}_${stat}";
                $el_props->{$new_key} = $sp_list->{$old_key};
            }
        }
        if ($return_basedatas) {
            push @raster_basedatas, $new_bd;
        }
    }

    return wantarray ? @raster_basedatas : \@raster_basedatas
      if $return_basedatas;
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
    my ($self) = shift;
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

sub drop_label_axis {
    my ($self, %args) = @_;
    return $self->drop_element_axis (
        %args,
        type => 'label',
    );
}

sub drop_group_axis {
    my ($self, %args) = @_;
    return $self->drop_element_axis (
        %args,
        type => 'group',
    );
}

sub get_group_axis_count {
    my ($self) = @_;
    my $c = $self->get_cell_sizes;
    return scalar @$c;
}


sub drop_element_axis {
    my ($self, %args) = @_;
    
    my $type = $args{type} // croak "type arg not specified\n";
    croak "type arg must be label or group, not $type"
      if not $type =~ /^(label|group)$/;
    
    croak "Cannot drop axes from basedata with outputs\n"
      if $self->get_output_ref_count;

    my $target = $type eq 'label'
      ? $self->get_labels_ref
      : $self->get_groups_ref;
    my $rename_method = "rename_${type}";

    my $axis = $args{axis};
    croak "Axis arg must be numeric\n"
      if !looks_like_number $axis;
    croak "Axis arg too large\n"
      if abs($axis) > $target->get_axis_count;
    

    my $quotes  = $self->get_param('QUOTES');      #  for storage, not import
    my $el_sep  = $self->get_param('JOIN_CHAR');
    my $csv = $self->get_csv_object(
        sep_char   => $el_sep,
        quote_char => $quotes,
    );

    foreach my $element ($target->get_element_list) {
        my @el_array = $target->get_element_name_as_array_aa ($element);
        next if abs($axis) > $#el_array;  #  labels do not yet have fixed item length
        splice @el_array, $axis, 1;
        my $new_name = $self->list2csv(
            list       => \@el_array,
            csv_object => $csv
        );
        #  in-place rename, could lead to grief?
        $self->$rename_method (
            $type    => $element,
            new_name => $new_name,
            silent   => 1,
        );
    }
    
    #  simplify logic below
    if ($axis < 0) {
        $axis += @$axis;
    }
    my $bd_cell_sizes   = $self->get_param('CELL_SIZES');
    my $bd_cell_origins = $self->get_param('CELL_ORIGINS');

    my $cell_sizes   = $target->get_param('CELL_SIZES');
    my $cell_origins = $target->get_param('CELL_ORIGINS');
    
    #  disconnect some shared arrays
    #  that ideally would not exist
    if ($type eq 'label') {
        if ($cell_sizes eq $bd_cell_sizes) {
            $cell_sizes = [@$cell_sizes];
            $target->set_param(CELL_SIZES => $cell_sizes);
        }
        if ($cell_origins eq $bd_cell_origins) {
            $cell_origins = [@$cell_origins];
            $target->set_param(CELL_ORIGINS => $cell_origins);
        }
    }
    #say "Splicing item $axis from sizes (" . (join ' ', @$cell_sizes) . ')';
    splice @$cell_sizes, $axis, 1;
    #  looks like we can get mismatches in cell size and origin array lengths
    if ($axis < @$cell_origins) {
        #say "Splicing item $axis from origins (" . (join ' ', @$cell_origins) . ')';
        splice @$cell_origins, $axis, 1;
    }
    
    if ($type eq 'group') {
        if ($bd_cell_sizes ne $cell_sizes) {  #  check if same ref 
            splice @$bd_cell_sizes, $axis, 1;
        }
        if ($bd_cell_origins ne $cell_origins and $axis < @$bd_cell_origins) {  #  check if same ref 
            splice @$bd_cell_origins, $axis, 1;
        }
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

    my @sub_elements = $lb->rename_element(
        element  => $label,
        new_name => $new_name
    );
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

    say "[BASEDATA] Renamed $label to $new_name"
      if !$args{silent};

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

    my @sub_elements = $gp->rename_element(
        element  => $group,
        new_name => $new_name,
    );
    foreach my $sub_element (@sub_elements) {
        $lb->rename_subelement(
            element     => $sub_element,
            sub_element => $group,
            new_name    => $new_name,
        );
    }

    say "[BASEDATA] Renamed $group to $new_name"
      if !$args{silent};

    return;
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

    #  one of these next conditions will break
    #  if neither label nor group is defined

    #  obscure code but micro-optimised as it is a hot path
    #  so we avoid scopes
    return $self->get_groups_ref->add_element(
        element    => $group,
        csv_object => $csv_object,
    ) if !defined $label;

    return $self->get_labels_ref->add_element(
        element    => $label,
        csv_object => $csv_object,
    ) if !defined $group;

    $count //= 1;

    return if !$count;

    #  add the labels and groups as element and subelement
    #  labels is the transpose of groups
    $self->get_groups_ref->add_sub_element_aa( $group, $label, $count, $csv_object );
    $self->get_labels_ref->add_sub_element_aa( $label, $group, $count, $csv_object );

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
    my ( $self, $gp_lb_hash, $csv_object, $allow_empty_groups, $transpose ) = @_;

    croak "csv_object arg not passed\n"
      if !$csv_object;

    #  blank slate so set directly
    return $self->_set_elements_collated_simple_aa($gp_lb_hash, $csv_object, $allow_empty_groups, $transpose)
      if !$self->get_group_count && !$self->get_label_count;

    #  now add the collated data
    #  duplicated loops to avoid conditions inside them
    if (!$transpose) {
        foreach my $gp_lb_pair (pairs % $gp_lb_hash) {
            my ($gp, $lb_hash) = @$gp_lb_pair;

            if ($allow_empty_groups && !scalar %$lb_hash) {
                $self->add_element_simple_aa(undef, $gp, 0, $csv_object);
            }
            else {
                pairmap {$self->add_element_simple_aa($a, $gp, $b, $csv_object)} %$lb_hash;
            }
        }
    }
    else {
        foreach my $pair (pairs % $gp_lb_hash) {
            my ($lb, $gp_hash) = @$pair;

            if ($allow_empty_groups && !scalar %$gp_hash) {
                $self->add_element_simple_aa($lb, undef, 0, $csv_object);
            }
            else {
                pairmap {$self->add_element_simple_aa($lb, $a, $b, $csv_object)} %$gp_hash;
            }
        }
    }

    return;
}

#  currently an internal sub as we might later take ownership of the input data
#  using refaliasing to squeeze a bit more speed
sub _set_elements_collated_simple_aa {
    my ( $self, $gp_lb_hash, $csv_object, $allow_empty_groups, $transpose ) = @_;

    croak "csv_object arg not passed\n"
        if !$csv_object;

    my %lb_gp_hash; # transposed version

    my $groups_ref = $self->get_groups_ref;
    my $labels_ref = $self->get_labels_ref;
    if ($transpose) {
        ($groups_ref, $labels_ref) = ($labels_ref, $groups_ref);
    }

    #  now add the collated data to the groups object
    foreach \my @gp_lb_pair ( pairs %$gp_lb_hash ) {
        my ( $gp, \%lb_hash ) = @gp_lb_pair;

        if ( $allow_empty_groups && !scalar %lb_hash ) {
            $self->add_element_simple_aa ( undef, $gp, 0, $csv_object );
        }
        else {
            delete local @lb_hash{grep !$lb_hash{$_}, keys %lb_hash}; # filter zeroes
            \my %subelement_hash = $groups_ref->get_sub_element_href_autoviv_aa($gp);
            %subelement_hash = %lb_hash;
            #  postfix for speed
            $lb_gp_hash{$_}{$gp} = $subelement_hash{$_} for keys %subelement_hash;
        }
    }
    #  and add the transposed data to the labels object
    foreach \my @lb_gp_pair ( pairs %lb_gp_hash ) {
        my ( $lb, \%gp_hash ) = @lb_gp_pair;

        if ( $allow_empty_groups && !scalar %gp_hash ) {
            $self->add_element_simple_aa ( $lb, undef, 0, $csv_object );
        }
        else {
            #  avoid a temp variable to be ever so slightly faster
            %{$labels_ref->get_sub_element_href_autoviv_aa($lb)} = %gp_hash;
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

    my $element = $args{element} // $args{group};
    croak "element not specified\n"
      if !defined $element;

    return $self->{GROUPS}->get_element_name_as_array_aa ($element);
}

sub get_group_element_as_array_aa {
    my ($self, $element) = @_;

    croak "element not specified\n"
      if !defined $element;

    return $self->{GROUPS}->get_element_name_as_array_aa ($element);
}

sub get_label_element_as_array {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};
    croak "element not specified\n"
      if !defined $element;

    return $self->get_labels_ref->get_element_name_as_array_aa ($element);
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
    
    my @cell_sizes   = $self->get_cell_sizes;
    my @cell_origins = $self->get_cell_origins;
    $new_bd->set_param (CELL_SIZES   => [@cell_sizes[@$group_cols]]);
    $new_bd->set_param (CELL_ORIGINS => [@cell_origins[@$group_cols]]);
    $gp->set_param (CELL_SIZES   => [@cell_sizes[@$group_cols]]);
    $gp->set_param (CELL_ORIGINS => [@cell_origins[@$group_cols]]);
    my @lb_cell_sizes   = $lb->get_cell_sizes;
    my @lb_cell_origins = $lb->get_cell_origins;
    $lb->set_param (CELL_SIZES   => [@lb_cell_sizes[@$label_cols]]);
    $lb->set_param (CELL_ORIGINS => [@lb_cell_origins[@$label_cols]]);

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

    my $type = $args{type};
    croak "argument 'type => $type' is not valid (must be groups or labels)\n"
      if not( $type eq 'groups' or $type eq 'labels' );
    my $get_ref_sub = $type eq 'groups' ? 'get_groups_ref' : 'get_labels_ref';

    my $elements_ref    = $self->$get_ref_sub;

    return if !$elements_ref->has_element_properties;

    my $to_elements_ref = $to_bd->$get_ref_sub;

    my $name    = $self->get_param('NAME');
    my $to_name = $to_bd->get_param('NAME');
    my $text    = "Transferring $type properties from $name to $to_name";

    my $progress_bar = Biodiverse::Progress->new(
        no_gui_progress => $args{no_gui_progress},
    );
    my $total_to_do  = $elements_ref->get_element_count;
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
    $to_elements_ref->delete_cached_values;

    return $count;
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
    my $deleted_subelements = $type_ref->delete_element( element => $element );

    #  could use it directly in the next loop, but this is more readable

#  now we adjust those $other_type elements that have been affected (eg correct Label ranges etc).
#  use the set of groups containing deleted labels that need correcting (or vice versa)
    foreach my $subelement (@$deleted_subelements) {

#print "ELEMENT $element, SUBELEMENT $subelement\n";
#  switch the element/subelement values as they are reverse indexed in $other_type
        $other_type_ref->delete_sub_element(
            %args,
            element    => $subelement,
            subelement => $element,
        );
        if (   $remove_other_empties
            && $other_type_ref->get_variety_aa( $subelement ) == 0 )
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

    foreach my ($group, $label_subhash) ( %$gp_lb_hash ) {
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
        foreach my $label (keys %labels_processed) {
            next if $labels_ref->get_variety_aa($label);
            $self->delete_element(
                type    => 'LABELS',
                element => $label,
            );
        }
    }

    1;
}

#  A cheat method, assumes we want group redundancy by default,
# drops the call down to the GROUPS object
sub get_redundancy {
    my $self = shift;

    return $self->get_groups_ref->get_redundancy(@_);
}

sub get_redundancy_aa {
    $_[0]->get_groups_ref->get_redundancy_aa($_[1]);
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

    my $labels_ref = $self->get_labels_ref;
    my $props = $labels_ref->get_list_values( @_, list => 'PROPERTIES' );

    my $variety = $labels_ref->get_variety(@_);

    return defined $props
        ? max( ( $props->{RANGE} // -1 ), $variety )
        : $variety;
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
      or croak "[BaseData] get_range_intersection argument labels not specified\n";

    croak "[BaseData] get_range_intersection argument labels not an array or hash ref\n" 
        if (!is_arrayref($labels) && !is_hashref($labels));
    
    $labels = [keys %{$labels}] if (is_hashref($labels));
    
    #  now loop through the labels and get the groups that contain all the species
    my $elements = {};
    foreach my $label (@$labels) {
        #  skip if it does not exist
        next
          if not $self->exists_label_aa( $label );

        my $res = $self->calc_abc(
            label_hash1 => $elements,
            label_hash2 =>
              { $self->get_groups_with_label_as_hash( label => $label ) }
        );

        #  delete those that are not shared (label_hash1 and label_hash2)
        delete @{ $res->{label_hash_all} }{ keys %{ $res->{label_hash1} } };
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

    if ($args{return_hash}) {
        @shared_elements{keys %shared_elements} = (1) x keys %shared_elements;
        return wantarray
            ? %shared_elements
            : \%shared_elements;
    }

    return scalar keys %shared_elements if $args{return_count};    #/

    return wantarray
      ? ( keys %shared_elements )
      : [ keys %shared_elements ];
}

#  get the labels object as a hash
sub get_labels_object_as_hash {
    my $self = shift;
    # my $lb = $self->get_labels_ref;
    my %h;
    foreach my $label ($self->get_labels) {
        #  we need a copy
        my $subhash = $self->get_groups_with_label_as_hash_aa($label);
        $h{$label} = {%$subhash};
    }
    return wantarray ? %h : \%h;
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

#  get a hash of the groups that contain $label
sub get_groups_with_label_as_hash {
    my ($self, %args) = @_;

    croak "Label not specified\n" if !defined $args{label};

    return $self->get_labels_ref->get_sub_element_hash_aa( $args{label} );
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

sub get_empty_group_count {
    my $self = shift;
    my $gps = $self->get_empty_groups;
    return scalar @$gps;
}

sub get_empty_groups {
    my $self = shift;
    #my %args = @_;
    state $cache_key = 'LIST_OF_EMPTY_GROUPS';

    if (my $cached = $self->get_cached_value ($cache_key)) {
        return wantarray ? @$cached : $cached;
    }

    my @gps = grep { !$self->get_richness_aa( $_ ) } $self->get_groups;

    $self->set_cached_value($cache_key => \@gps);

    return wantarray ? @gps : \@gps;
}

sub get_rangeless_label_count {
    my $self = shift;
    my $lbs = $self->get_rangeless_labels;
    return scalar @$lbs;
}

sub get_rangeless_labels {
    my $self = shift;

    state $cache_key = 'LIST_OF_RANGELESS_LABELS';

    if (my $cached = $self->get_cached_value ($cache_key)) {
        return wantarray ? @$cached : $cached;
    }

    my $lb = $self->get_labels_ref;
    my @labels = grep { !$lb->get_variety_aa( $_ ) } $self->get_labels;

    $self->set_cached_value($cache_key => \@labels);

    return wantarray ? @labels : \@labels;
}

sub get_labels_with_nonzero_ranges {
    my $self = shift;

    state $cache_name = 'LIST_OF_LABELS_WITH_NONZERO_RANGES';
    my $cached = $self->get_cached_value($cache_name);

    return wantarray ? @$cached : $cached
        if $cached;

    my $labels = $self->get_labels;
    my $rangeless_labels = $self->get_rangeless_labels;

    return wantarray ? @$labels : $labels
        if @$rangeless_labels == 0;

    my %lb_hash;
    @lb_hash{@$labels} = ();
    my @lb = grep {!exists $lb_hash{$_}} @$rangeless_labels;

    $self->set_cached_value ($cache_name => \@lb);

    return wantarray ? @lb : \@lb;
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

#  get a hash of the labels that occur in a group
sub get_labels_in_group_as_hash_aa {
    $_[0]->get_groups_ref->get_sub_element_hash_aa($_[1]);
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
    $_[0]->get_labels_ref->get_element_count;
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
    $_[0]->get_groups_ref->get_element_count;
}

sub get_sample_count {
    my ($self) = @_;
    my $gp = $self->get_groups_ref;
    my $count = 0;
    foreach my $element ($gp->get_element_list) {
        $count += $gp->get_sample_count_aa($element);
    }
    return $count;
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

sub rebuild_spatial_index {
    my $self = shift;

    my $index = $self->get_param('SPATIAL_INDEX');
    return if !defined $index;

    my $resolutions = $index->get_param('RESOLUTIONS');
    $self->build_spatial_index( resolutions => $resolutions );

    return;
}

#  get a 2D STR R-tree index
sub get_strtree_index {
    my ($self, %args) = @_;

    use Tree::STR 0.02;

    \my @axes = $args{axes} // [0,1];
    croak "Must specify two axes" if @axes != 2;

    my $cache = $self->get_cached_value_dor_set_default_href ('GP_STRTREES');
    my $cache_key = join ':', @axes;
    if (my $cached = $cache->{$cache_key}) {
        return $cached;
    }

    my @cellsizes = $self->get_cell_sizes;

    croak "Cannot build an STR Tree for one axis"
        if @cellsizes == 1;

    my ($c1, $c2) = map {$_ / 2} @cellsizes[@axes];

    croak "Cannot generate an index for point or text axes"
        if $c1 <= 0 || $c2 <= 0;

    my @data;
    my $gp = $self->get_groups_ref;
    foreach my $group ($self->get_groups) {
        my $coords = $gp->get_element_name_as_array_aa($group);
        my ($x, $y) = @$coords[@axes];
        my ($x1, $x2) = ($x - $c1, $x + $c1);
        my ($y1, $y2) = ($y - $c2, $y + $c2);
        push @data, [$x1, $y1, $x2, $y2, $group];
    }
    my $tree = Tree::STR->new(\@data);

    return $cache->{$cache_key} = $tree;
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
    my %exclude_hash;
    if ($args{exclude_list}) {
        #  can we use undef as the val?
        @exclude_hash{@{$args{exclude_list}}} = (1) x @{$args{exclude_list}};
    }

    my $centre_coord_ref =
      $self->get_group_element_as_array( element => $element1 );

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
          $self->get_group_element_as_array_aa ( $element1 );

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
        my @coord = $self->get_group_element_as_array_aa ($element2 );

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

    my @outputs = $self->get_outputs_with_same_def_query (%args);

    my @comparable_outputs;

    LOOP_OUTPUTS:
    foreach my $output (@outputs) {
        next LOOP_OUTPUTS if $output eq $compare;    #  skip the one to compare

        my $completed = $output->get_param('COMPLETED');
        next LOOP_OUTPUTS if defined $completed and !$completed;

        my $sp_params_comp = $output->get_spatial_conditions || [];

        #  must have same number of conditions
        next LOOP_OUTPUTS if scalar @$sp_params_comp != scalar @$sp_params;

        my $i = 0;
        foreach my $sp_obj (@$sp_params_comp) {
            next LOOP_OUTPUTS
                if ( $sp_params->[$i]->get_param('CONDITIONS') ne
                    $sp_obj->get_conditions_unparsed() );

            my $tree_ref = $sp_params->[$i]->get_tree_ref;
            my $tree_ref_comp = $sp_obj->get_tree_ref;
            next LOOP_OUTPUTS
                if ($tree_ref // '') ne ($tree_ref_comp // '');

            $i++;
        }

        #  if we get this far then we have a match
        push @comparable_outputs, $output;    #  we want to keep this one
    }

    return wantarray ? @comparable_outputs : \@comparable_outputs;
}

sub get_outputs_with_same_def_query {
    my $self = shift;
    my %args = @_;

    my $compare = $args{compare_with}
        || croak "[BASEDATA] compare_with argument not specified\n";

    my $def_query = $compare->get_def_query;
    if ( defined $def_query && ( length $def_query ) == 0 ) {
        $def_query = undef;
    }

    my $def_conditions;
    my $tree_ref;
    if ( blessed $def_query) {
        $def_conditions = $def_query->get_conditions_unparsed();
        $tree_ref = $def_query->get_tree_ref;
    }

    #  could be more general with def queries
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

        if (!defined $def_query && !defined $def_query_comp) {
            push @comparable_outputs, $output;
            next LOOP_OUTPUTS;
        }

        if ( defined $def_query ) {

            #  check their def queries match
            my $def_conditions_comp =
                eval { $def_query_comp->get_conditions_unparsed() }
                    // $def_query_comp;
            my $def_conditions_text =
                eval { $def_query->get_conditions_unparsed() } // $def_query;
            next LOOP_OUTPUTS if $def_conditions_comp ne $def_conditions_text;

            my $tree_ref_comp = $def_query_comp->get_tree_ref;
            next LOOP_OUTPUTS if ($tree_ref // '') ne ($tree_ref_comp // '');
        }

        #  if we get this far then we have a match
        push @comparable_outputs, $output;    #  we want to keep this one
    }

    return wantarray ? @comparable_outputs : \@comparable_outputs;
}

#  not sure this does what is meant by the name
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

    $from_bd->transfer_group_properties (
        receiver => $self,
    );
    $from_bd->transfer_label_properties (
        receiver => $self,
    );

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
