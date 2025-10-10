package Biodiverse::Metadata::Indices;
use strict;
use warnings;
use 5.016;
use Carp;
use Readonly;
use Ref::Util qw /is_hashref/;

use parent qw /Biodiverse::Metadata/;

our $VERSION = '4.99_013';

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

sub new {
    my ($class, $data) = @_;
    $data //= {};

    my $self = __PACKAGE__->SUPER::new ($data);
    bless $self, $class;

    my $indices = $self->{indices} // {};
    croak "Indices not a hash ref for $self->{name}"
     if !is_hashref $indices;

    foreach my $index (keys %{$indices}) {
        #  triggers it being set
        $self->get_index_bounds ($index);
    }

    return $self;
}


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

sub get_index_bounds {
    my ($self, $index) = @_;

    no autovivification;
    my $idx_hash = $self->{indices}{$index};
    croak "No index $index" if !$idx_hash;

    my $bounds
          = $self->{indices}{$index}{bounds}
        //= $self->get_index_is_unit_interval($index) ? [0,1]
          : $self->get_index_is_nonnegative($index)   ? [0,'Inf']
          : $self->get_index_is_categorical($index)   ? []
          : ['-Inf','Inf'];

    return $bounds;
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


my %valid_distributions = (
    ''            => 1,
    sequential    => 1,
    unit_interval => 1,
    zscore        => 1,
    divergent     => 1,
    categorical   => 1,
    nonnegative   => 1,
    nonnegative_ratio => 1,
);

sub index_distribution_is_valid {
    my ($self, $index) = @_;
    my $distr = $self->get_index_distribution($index);
    return $valid_distributions{$distr};
}

sub get_index_is_ratio {
    my ($self, $index) = @_;
    return $self->get_index_distribution($index) =~ /ratio$/;
}

sub get_index_is_categorical {
    my ($self, $index) = @_;
    return $self->get_index_distribution($index) eq 'categorical';
}

sub get_index_is_nonnegative {
    my ($self, $index) = @_;

    return 0 if $self->get_index_is_zscore($index);
    return 1 if $self->get_index_is_unit_interval ($index);

    return $self->get_index_distribution($index) =~ '^nonnegative';
}

#  default is sequential
sub get_index_is_sequential {
    my ($self, $index) = @_;
    return $self->get_index_distribution($index) eq 'sequential';
}

sub get_index_distribution {
    my ($self, $index) = @_;

    no autovivification;
    my $indices = $self->get_indices;
    return $indices->{$index}{distribution} // $self->{distribution} // 'sequential';
}

sub get_index_category_labels {
    my ($self, $index) = @_;

    return if !$self->get_index_is_categorical($index);

    no autovivification;

    my $indices = $self->get_indices;
    my $hash = $indices->{$index}{labels};
    return wantarray ? %$hash : $hash;
}

sub get_index_category_colours {
    my ($self, $index) = @_;

    return if !$self->get_index_is_categorical($index);

    no autovivification;

    my $indices = $self->get_indices;
    my $hash = $indices->{$index}{colours};
    return wantarray ? %$hash : $hash;
}

__PACKAGE__->_make_distribution_methods (keys %valid_distributions);

sub _make_distribution_methods {
    my ($pkg, @methods) = @_;
    # print "Calling _make_access_methods for $pkg";
    no strict 'refs';
    #  filter blanks
    foreach my $key (grep {$_} @methods) {
        my $method = "get_index_is_$key";
        next if $pkg->can($method);  #  do not override
        # say STDERR "Building $method in package $pkg";
        *{"${pkg}::${method}"} =
            do {
                sub {
                    my ($self, $index) = @_;
                    return $self->get_index_distribution($index) eq $key;
                };
            };
    }

    return;
}


sub TO_JSON {
    my ($self) = @_;
    my $ref = {%$self};  # a crude unbless
    $ref;
}

1;
