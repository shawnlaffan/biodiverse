package Biodiverse::Metadata::Indices;
use strict;
use warnings;
use 5.016;
use Carp;
use Readonly;

use parent qw /Biodiverse::Metadata/;

our $VERSION = '3.99_001';

Readonly my %methods_and_defaults => (
    name           => 'no_name',
    description    => 'no_description',
    uses_nbr_lists => 1,
    required_args  => undef,
    pre_conditions => undef,
    reference      => '',
    indices        => {},
    type           => '',
    formula        => undef,
);


sub _get_method_default_hash {
    return wantarray ? %methods_and_defaults : {%methods_and_defaults};
}


__PACKAGE__->_make_access_methods (\%methods_and_defaults);



Readonly my %dep_types => (
    pre_calc_global  => 1,
    pre_calc         => 1,
    post_calc        => 1,
    post_calc_global => 1,
);

sub get_dep_list {
    my ($self, $type) = @_;

    croak "Invalid dependency type $type" if !$dep_types{$type};

    my $pc = $self->{$type};

    return $pc if !defined $pc;

    if (!ref ($pc)) {
        $pc = [$pc];
    }

    return $pc;    
}

sub get_pre_calc_global_list {
    my $self = shift;
    return $self->get_dep_list ('pre_calc_global');
}

sub get_pre_calc_list {
    my $self = shift;
    return $self->get_dep_list ('pre_calc');
}

sub get_post_calc_list {
    my $self = shift;
    return $self->get_dep_list ('post_calc');
}

sub get_post_calc_global_list {
    my $self = shift;
    return $self->get_dep_list ('post_calc_global');
}



#  some subs do not have indices, e.g. post_calc_globals which just do cleanup
sub has_no_indices {
    my $self = shift;
    return $self->{no_indices};
}

sub get_index_description {
    my ($self, $index) = @_;

    no autovivification;
    
    my $indices = $self->get_indices;
    my $descr = $indices->{$index}{description};

    croak "Index $index has no description" if !$descr;

    return $descr;
}

sub get_index_description_hash {
    my $self = shift;

    my $descriptions = $self->get_indices;
    my %hash;
    foreach my $index (keys %$descriptions) {
        $hash{$index} = $self->get_index_description ($index);
    }

    return wantarray ? %hash : \%hash;
}

sub get_index_formula {
    my ($self, $index) = @_;

    no autovivification;
    
    my $indices = $self->get_indices;
    my $formula = $indices->{$index}{formula};

    return $formula;
}

sub get_index_reference {
    my ($self, $index) = @_;

    no autovivification;
    
    my $indices   = $self->get_indices;
    my $reference = $indices->{$index}{reference};

    return $reference;
}

sub get_index_uses_nbr_lists {
    my ($self, $index) = @_;

    no autovivification;
    
    my $indices = $self->get_indices;
    return $indices->{$index}{uses_nbr_lists} // 1;
}

sub get_index_is_cluster_metric {
    my ($self, $index) = @_;

    no autovivification;
    
    my $indices = $self->get_indices;
    return $indices->{$index}{cluster};
}

sub get_index_is_lumper {
    my ($self, $index) = @_;

    no autovivification;
    
    my $indices = $self->get_indices;
    return $indices->{$index}{lumper} // 1;
}

sub get_index_is_list {
    my ($self, $index) = @_;

    no autovivification;
    
    my $indices = $self->get_indices;
    return ($indices->{$index}{type} // '') eq 'list';
}


1;
