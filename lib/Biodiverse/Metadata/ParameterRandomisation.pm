package Biodiverse::Metadata::ParameterRandomisation;
use strict;
use warnings;

# Almost identical to Biodiverse::Metadata::Parameter
# need to refactor

use 5.016;
use Carp;
use Readonly;
use Scalar::Util qw /reftype/;

our $VERSION = '1.0_001';

sub new {
    my ($class, $data) = @_;
    $data //= {};
    
    my $self = bless $data, $class;
    return $self;
}


my %methods_and_defaults = (
    name        => '',
    
    tooltip     => '',
    type        => '',
    choices     => [],
    default     => '',
    sensitive   => 1,
    increment   => 1,
    digits      => undef,
);


sub _make_access_methods {
    my ($pkg, $methods) = @_;

    no strict 'refs';
    foreach my $key (keys %$methods) {
        *{$pkg . '::' . 'get_' . $key} =
            do {
                sub {
                    my $self = shift;
                    return $self->{$key} // $self->get_default_value ($key);
                };
            };
        *{$pkg . '::' . 'set_' . $key} =
            do {
                sub {
                    my ($self, $val) = @_;
                    $self->{$key} = $val;
                };
            };
    }

    return;
}

sub get_default_value {
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
