package Biodiverse::Metadata::Export;
use strict;
use warnings;

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
    parameters     => {},
    format_choices => [],
    format_labels  => {},
    component_map  => {},
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

sub get_valid_subs {
    my $self = shift;

    my $format_labels = $self->get_format_labels;
    my %valid = reverse %$format_labels;

    return wantarray ? %valid : \%valid;
}

sub format_is_valid {
    my ($self, $format_label) = @_;

    my $format_labels = $self->get_format_labels;

    return exists $format_labels->{$format_label};
}

#  get a sub name from either the format label or the format
sub get_sub_name_from_format {
    my ($self, %args) = @_;

    no autovivification;

    my $check_name = $args{format_label} // $args{format};
    my $check_sub_name = "export_$check_name";

    my $format_labels = $self->get_format_labels;
    my %reversed      = reverse %$format_labels;

    my $is_valid = $format_labels->{$check_name}
                // ($reversed{$check_name} ? $check_name : undef)
                // $format_labels->{$check_sub_name}
                // $reversed{$check_sub_name};

    croak "Sub name cannot be identified from $check_name"
      if !$is_valid;

    return $is_valid;
}

sub get_parameters_for_format {
    my ($self, %args) = @_;
    
    no autovivification;

    my $params = $self->get_parameters;
    my $p = $params->{$args{format} // $args{format_label}};

    return $p;    
}

1;
