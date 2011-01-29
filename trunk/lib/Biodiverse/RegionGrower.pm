package Biodiverse::RegionGrower;
use strict;
use warnings;

use base qw /
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

#  need to modify to use something else
sub get_default_cluster_index {
    return $PARAMS{DEFAULT_CLUSTER_INDEX};
}

sub get_type {
    return $PARAMS{TYPE};
}

#sub get_valid_indices {
#    my $self = shift;
#    my %args = @_;
#
#    my $bd = $args{BASEDATA_REF};
#    my $indices = Biodiverse::Indices->new(BASEDATA_REF => $bd);
#
#    return $self->get_valid_region_grower_indices (@_);
#}

#sub get_valid_indices {
#    my $self = shift;
#    return $self->get_valid_region_grower_indices (@_);
#}

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


1;
