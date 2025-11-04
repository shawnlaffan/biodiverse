package Biodiverse::GUI::Overlays::Geometry;
use strict;
use warnings;
use 5.036;
use Carp qw /croak/;

our $VERSION = '5.0';

sub new {
    my ($class, %args) = @_;
    croak 'No extent argument' if !$args{extent};
    croak 'No id argument' if !defined $args{id};
    bless \%args, $class || __PACKAGE__;
}

sub get_id {
    $_[0]{id};
}

sub set_geometry {
    $_[0]{geometry} = $_[1];
}

sub get_geometry {
    $_[0]{geometry};
}

sub set_extent {
    $_[0]{extent} = $_[1];
}

sub get_extent {
    my $e = $_[0]{extent};
    wantarray ? @$e : $e;
}

sub xmin {
    $_[0]{extent}[0];
}
sub xmax {
    $_[0]{extent}[2];
}
sub ymin {
    $_[0]{extent}[1];
}
sub ymax {
    $_[0]{extent}[3];
}


1;
