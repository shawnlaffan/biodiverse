package Biodiverse::Metadata::Indices;
use strict;
use warnings;
use 5.016;
use Carp;

sub new {
    my ($class, $data) = @_;
    $data //= {};
    
    my $self = bless $data, $class;
    return $self;
}


sub get_name {
    my $self = shift;
    return $self->{name} // 'no_name';
}

sub get_description {
    my $self = shift;
    return $self->{description} // 'no_description';
}

sub get_indices {
    my $self = shift;
    return $self->{indices} // {};
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
