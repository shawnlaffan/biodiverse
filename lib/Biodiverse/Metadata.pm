package Biodiverse::Metadata;
use strict;
use warnings;

our $VERSION = '1.0';

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}


1;
