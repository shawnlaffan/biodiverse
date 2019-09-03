package Biodiverse::Metadata::Parameter;
use strict;
use warnings;

#  Mostly needed by Biodiverse::GUI::ParametersTable,
#  with params and specified extensively in import and export metadata

use 5.016;
use Carp;
use Readonly;

use parent qw /Biodiverse::Metadata/;

our $VERSION = '3.00';


#  Poss too many, but we are a catch-all class.
my %methods_and_defaults = (
    name        => '',
    label_text  => '',
    tooltip     => '',
    type        => '',
    choices     => [],
    default     => '',
    sensitive   => 1,
    min         => undef,
    max         => undef,
    digits      => undef,
    increment   => 1,
    always_sensitive => undef,
    mutable     => undef,
    box_group   => undef,
);

sub _get_method_default_hash {
    return wantarray ? %methods_and_defaults : {%methods_and_defaults};
}

__PACKAGE__->_make_access_methods (\%methods_and_defaults);


#  choice type returns an index, not the actual value
sub get_default_param_value {
    my $self = shift;

    my $val = $self->get_default;

    return $val if $self->get_type ne 'choice';

    my $choices = $self->get_choices;

    return $choices->[$val];
}

1;
