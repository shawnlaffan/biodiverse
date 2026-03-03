package Biodiverse::Geometry::Polygon;
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
    $_[0]->{centre} = undef;
    $_[1];
}

sub get_extent {
    my $e = $_[0]{extent};
    wantarray ? @$e : $e;
}

sub bbox {
    shift->get_extent;
}

sub centre {
    my ($self) = @_;
    return $self->{centre} if $self->{centre};
    my $e = $self->get_extent;
    return $self->{centre} = [
        $e->[0] + $e->[2] / 2,
        $e->[1] + $e->[3] / 2
    ];
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

sub clone {
    my $self = shift;
    use Clone;
    return Clone::clone ($self);
}

sub shift {
    my ($self, $xoff, $yoff) = @_;
    my $clone = $self->clone;
    my $g = $clone->get_geometry;
    foreach my \@part (@$g) {
        foreach my \@vertices (@part) {
            $vertices[0] += $xoff;
            $vertices[1] += $yoff;
        }
    }
    $clone;
}


1;
