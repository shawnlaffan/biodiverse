package Biodiverse::GUI::Overlays::Geometry;
use strict;
use warnings;
use 5.036;
use Carp qw /croak/;

sub new {
    my ($class, %args) = @_;
    croak 'No geometry argument' if !$args{geometry};
    croak 'No extent argument' if !$args{extent};
    bless \%args, $class || __PACKAGE__;
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
