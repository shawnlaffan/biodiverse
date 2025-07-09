package Biodiverse::Common::Caching;
use strict;
use warnings;


our $VERSION = '4.99_006';

#  set any value - allows user specified additions to the core stuff
sub set_cached_value {
    my $self = shift;
    my %args = @_;
    @{$self->{_cache}}{keys %args} = values %args;

    return;
}

sub set_cached_values {
    my $self = shift;
    $self->set_cached_value (@_);
}

#  hot path, so needs to be lean and mean, even if less readable
sub get_cached_value {
    return if ! exists $_[0]->{_cache}{$_[1]};
    return $_[0]->{_cache}{$_[1]};
}

#  dor means defined-or - too obscure?
sub get_cached_value_dor_set_default_aa {
    $_[0]->{_cache}{$_[1]} //= $_[2];
}

sub get_cached_value_dor_set_default_href {
    $_[0]->{_cache}{$_[1]} //= {};
}

sub get_cached_value_dor_set_default_aref {
    $_[0]->{_cache}{$_[1]} //= [];
}



sub get_cached_value_keys {
    my $self = shift;

    return if ! exists $self->{_cache};

    return wantarray
        ? keys %{$self->{_cache}}
        : [keys %{$self->{_cache}}];
}

sub delete_cached_values {
    my $self = shift;
    my %args = @_;

    return if ! exists $self->{_cache};

    my $keys = $args{keys} || $self->get_cached_value_keys;
    return if not defined $keys or scalar @$keys == 0;

    delete @{$self->{_cache}}{@$keys};
    delete $self->{_cache} if scalar keys %{$self->{_cache}} == 0;

    #  This was generating spurious warnings under test regime.
    #  It should be unnecesary anyway.
    #warn "Cache deletion problem\n$EVAL_ERROR\n"
    #  if $EVAL_ERROR;

    #warn "XXXXXXX "  . $self->get_name . "\n" if exists $self->{_cache};

    return;
}

sub delete_cached_value {
    my ($self, $key) = @_;
    no autovivification;
    delete $self->{_cache}{$key};
}


1;
