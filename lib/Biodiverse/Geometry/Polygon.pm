package Biodiverse::Geometry::Polygon;
use strict;
use warnings;
use 5.036;
use Carp qw /croak/;

use experimental /for_list declared_refs refaliasing/;

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
        ($e->[0] + $e->[2]) / 2,
        ($e->[1] + $e->[3]) / 2
    ];
}

sub get_centroid {
    $_[0]->centre;
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
    use experimental qw /declared_refs/;
    use Ref::Util qw /is_arrayref/;
    my $clone = $self->clone;
    my $g = $clone->get_geometry;
    my @queue = $g;
    ITEM:
    while (my $item = shift @queue) {
        if (is_arrayref $item->[0]) {
            push @queue, @$item;
            next ITEM;
        }
        $item->[0] += $xoff;
        $item->[1] += $yoff;
    }
    $clone->{centre} = undef;
    my $e = $clone->get_extent;
    $e->[0] += $xoff;
    $e->[1] += $yoff;
    $e->[2] += $xoff;
    $e->[3] += $yoff;
    $clone;
}

sub as_gdal_geometry {
    my ($self) = @_;
    Geo::GDAL::FFI::Geometry->new(WKT => $self->as_wkt);
}

sub as_wkt {
    my ($self) = @_;
    my $geom = $self->get_geometry;
    my $wkt = 'MULTIPOLYGON (';
    foreach my $poly (@$geom) {
        foreach my $part (@$poly) {
            my $wkt_part = '((';
            my @vertices = map {"$_->[0] $_->[1]"} @$part;
            $wkt_part .= join ', ', @vertices;
            $wkt_part .= ')), ';
            $wkt .= $wkt_part;
        }
        $wkt =~ s/,\s*$//;
    }
    $wkt .= ')';
    # say STDERR $wkt;
}

1;
