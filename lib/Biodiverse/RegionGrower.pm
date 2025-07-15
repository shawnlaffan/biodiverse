package Biodiverse::RegionGrower;
use 5.010;
use strict;
use warnings;

our $VERSION = '4.99_007';

use parent qw /
    Biodiverse::Cluster
/;


our %PARAMS = (  #  most of these are not used
    DEFAULT_CLUSTER_INDEX => 'RICHNESS_ALL',
    DEFAULT_LINKAGE       => 'link_recalculate',
    TYPE                  => 'RegionGrower',
    OUTSUFFIX             => 'bts',
    #OUTSUFFIX_XML         => 'btx',
    OUTSUFFIX_YAML        => 'bty',
    OUTPUT_QUOTE_CHAR     => q{"},
    OUTPUT_SEP_CHAR       => q{,},
    COMPLETED             => 0,
);


#  use the new sub from Cluster

sub get_default_linkage {
    return 'link_recalculate';
}

#  need to modify to use something else
sub get_default_cluster_index {
    return $PARAMS{DEFAULT_CLUSTER_INDEX};
}

sub get_default_objective_function {
    return 'get_max_value';
}

sub get_type {
    return $PARAMS{TYPE};
}

sub get_valid_indices_sub {
    return 'get_valid_region_grower_indices';
}

#  Get a list of the all the publicly available linkages.
#  Overrides those in Biodiverse::Cluster
#  Will need to restructure if we allow other linkages
sub get_linkage_functions {  
    my $self = shift;

    my @linkages = qw /link_recalculate/;

    return wantarray ? @linkages : \@linkages;
}

#  Allows early stopping of the merging process.  
sub get_max_poss_matrix_value {
    my $self = shift;
    my %args = @_;

    #  shadow matrix
    my $mx = $args{matrix};
    
    my $sp_conditions_array = $self->get_spatial_conditions;
    my $final_cond  = $sp_conditions_array->[-1];
    my $result_type = $final_cond->get_result_type;

    #  Drop out unless we have one condition and its result type is always_true
    return if scalar @$sp_conditions_array > 1 || $result_type ne 'always_true';

    my $indices_object = $self->get_indices_object_for_matrix_and_clustering;
    my $elements       = $mx->get_elements_as_array;

    my $analysis_args = $self->get_param('ANALYSIS_ARGS');
    my $results = $indices_object->run_calculations(
        %args,
        %$analysis_args,
        element_list1   => $elements,
        element_list2   => undef,
        label_hash1     => undef,
        label_hash2     => undef,
    );

    my $index = $args{index} || $self->get_param ('CLUSTER_INDEX');
    my $index_value = $results->{$index};

    if (defined $index_value) {
        say "[REGIONGROWER] Early stopping enabled, target value is $index_value";
    }

    return $index_value;
}


1;
