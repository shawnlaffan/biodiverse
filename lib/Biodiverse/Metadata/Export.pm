package Biodiverse::Metadata::Export;
use strict;
use warnings;

use 5.016;
use Carp;
use Readonly;

our $VERSION = '1.99_008';

use parent qw /Biodiverse::Metadata/;


Readonly my %methods_and_defaults => (
    parameters     => {},
    format_choices => [],
    format_labels  => {},
    component_map  => {},
);

sub _get_method_default_hash {
    return wantarray ? %methods_and_defaults : {%methods_and_defaults};
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
    croak "neither 'format_label' nor 'format' argument is not defined\n"
      if !defined $check_name;
      
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
