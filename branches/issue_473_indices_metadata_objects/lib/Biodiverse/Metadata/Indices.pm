package Biodiverse::Metadata::Indices;
use strict;
use warnings;
use 5.016;
use Carp;
use Readonly;
use Scalar::Util qw /reftype/;

sub new {
    my ($class, $data) = @_;
    $data //= {};
    
    my $self = bless $data, $class;
    return $self;
}


my %methods_and_defaults = (
    name           => 'no_name',
    description    => 'no_description',
    uses_nbr_lists => 1,
    required_args  => [],
    preconditions  => undef,
    reference      => '',
    indices        => {},
);


sub _make_access_methods {
    my ($pkg, $methods) = @_;

    no strict 'refs';
    foreach my $key (keys %$methods) {
        *{$pkg . '::' . "get_$key"} =
            do {
                sub {
                    my $self = shift;
                    return $self->{$key} // $self->get_default ($key);
                };
            };
    }

    return;
}

sub get_default {
    my ($self, $key) = @_;

    #  set defaults - make sure they are new each time
    my $default = $methods_and_defaults{$key};
    return $default if !defined $default;

    if (reftype ($default) eq 'ARRAY') {
        $default = [];
    }
    elsif (reftype ($default) eq 'HASH') {
        $default = {};
    }
    return $default;
}

__PACKAGE__->_make_access_methods (\%methods_and_defaults);



Readonly my %dep_types = (
    pre_calc_global  => 1,
    pre_calc         => 1,
    post_calc        => 1,
    post_calc_global => 1,
);

sub _get_dep_list {
    my ($self, $type) = shift;
    
    croak "Invalid dependency type $type" if !$dep_types{$type};

    my $pc = $self->{$type} // [];

    if (!ref ($pc)) {
        $pc = [$pc];
    }

    return $pc;    
}

sub get_pre_calc_global_list {
    my $self = @_;
    return $self->_get_dep_list ('pre_calc_global');
}

sub get_pre_calc_list {
    my $self = @_;
    return $self->_get_dep_list ('pre_calc');
}

sub get_post_calc_list {
    my $self = @_;
    return $self->_get_dep_list ('post_calc');
}

sub get_post_calc_global_list {
    my $self = @_;
    return $self->_get_dep_list ('post_calc_global');
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

1;
