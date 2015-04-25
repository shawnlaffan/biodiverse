package Biodiverse::Metadata::SpatialConditions;
use strict;
use warnings;
use 5.016;
use Carp;
use Readonly;
use Scalar::Util qw /reftype/;

our $VERSION = '1.0';

sub new {
    my ($class, $data) = @_;
    $data //= {};
    
    my $self = bless $data, $class;
    return $self;
}


my %methods_and_defaults = (
    description    => 'no_description',
    result_type    => 'no_type',    
    index_max_dist => undef,
    example        => 'no_example',
    required_args  => [],
    optional_args  => [],
    index_no_use   => 1,
    use_euc_distances => undef,
    use_euc_distance  => undef,
);


sub _make_access_methods {
    my ($pkg, $methods) = @_;

    no strict 'refs';
    foreach my $key (keys %$methods) {
        *{$pkg . '::' . 'get_' . $key} =
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

    return $default if !defined $default or !reftype $default;

    if (reftype ($default) eq 'ARRAY') {
        $default = [];
    }
    elsif (reftype ($default) eq 'HASH') {
        $default = {};
    }
    return $default;
}

__PACKAGE__->_make_access_methods (\%methods_and_defaults);


1;
