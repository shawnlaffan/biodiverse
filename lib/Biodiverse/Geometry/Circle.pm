package Biodiverse::Geometry::Circle;
use strict;
use warnings;
use 5.036;
use feature qw /signatures current_sub/;

use List::Util qw /all shuffle/;
use Carp qw /croak/;

our $VERSION = '5.0';


sub new ($class, $p, $r) {
    return bless { centre => $p, radius => $r }, (ref($class) || $class // __PACKAGE__);
}

#  slurpy to avoid arity checks
sub centre ($self, @c) {
    $self->{centre} = $c[0] if @c;
    return $self->{centre};
}

sub radius ($self, @r) {
    $self->{radius} = $r[0] if @r;
    return $self->{radius};
}

sub bbox ($self) {
    my $c = $self->centre;
    my $r = $self->radius;

    my @bbox = (
        $c->[0] - $r,
        $c->[1] - $r,
        $c->[0] + $r,
        $c->[1] + $r,
    );

    return wantarray ? @bbox : \@bbox;
}

sub contains_point ($self, $p) {
    sqrt (
        ($self->{centre}[0] - $p->[0])**2
            + ($self->{centre}[1] - $p->[1])**2
    ) <= $self->{radius};
}

sub contains_all_points ($self, $points) {
    List::Util::all {$self->contains_point ($_)} @$points;
}

#  we use state subs so we do not pollute the @ISA with some very specific functions
sub get_circumcircle ($self, $p) {
    state $circ_class = __PACKAGE__;

    # Function to return the euclidean distance between two points
    state sub dist ($p1, $p2) {
        return sqrt(($p1->[0] - $p2->[0]) ** 2 + ($p1->[1] - $p2->[1]) ** 2)
    }

    # Helper method to get a circle defined by 3 points
    state sub get_circle_centre ($bx, $by, $cx, $cy) {
        my $b0 = $bx * $bx + $by * $by;
        my $c0 = $cx * $cx + $cy * $cy;
        my $d  = $bx * $cy - $by * $cx;
        return [
            ($cy * $b0 - $by * $c0) / (2 * $d),
            ($bx * $c0 - $cx * $b0) / (2 * $d),
        ];
    }

    # Function to return a unique circle that intersects three points
    state sub circle_from ($p0, $p1, $p2) {
        return circle_from_two($p0, $p1)
            if !defined $p2;

        my $centre = get_circle_centre(
            $p1->[0] - $p0->[0], $p1->[1] - $p0->[1],
            $p2->[0] - $p0->[0], $p2->[1] - $p0->[1],
        );
        $centre->[0] += $p0->[0];
        $centre->[1] += $p0->[1];

        return $circ_class->new($centre, dist($centre, $p0));
    }

    # Function to return the smallest circle that intersects 2 points
    state sub circle_from_two ($p0, $p1) {
        my $c = [
            ($p0->[0] + $p1->[0]) / 2,
            ($p0->[1] + $p1->[1]) / 2,
        ];
        return $circ_class->new ($c, dist($c, $p1));
    }

    # Function to return the minimum enclosing circle for N <= 3
    state sub min_circle_trivial ($p) {
        croak if @$p > 3;

        return $circ_class->new([ 0, 0 ], -1)
            if !@$p;
        return $circ_class->new($p->[0], 0)
            if @$p == 1;
        return circle_from_two(@$p[0,1])
            if @$p == 2;

        for my $i (0..2) {
            for my $j ($i+1..2) {
                my $c = circle_from_two(@$p[$i, $j]);
                return $c
                    if $c->contains_all_points($p)
            }
        }

        return circle_from(@$p);
    }


    #  should probably use the non-recursive algorithm
    state sub welzl_helper ($p, $r, $n) {

        #  make sure we pass a copy of $r
        return min_circle_trivial([ @$r ])
            if $n == 0 or @$r == 3;

        #  Use system rand as we only need it to
        #  permute the sequence to achieve O(n)
        #  complexity.  The order does not matter.
        my $idx = int(rand() * $n);
        my $pnt = $p->[$idx];
        @$p[$idx, $n - 1] = @$p[$n - 1, $idx];

        my $d = __SUB__->($p, $r, $n - 1);

        return $d if $d->contains_point($pnt);

        # Append without modifying original r
        return __SUB__->($p, [@$r, $pnt ], $n -1);
    }

    return welzl_helper([List::Util::shuffle @$p], [], scalar @$p);
}

sub clone {
    my $self = shift;
    use Clone;
    return Clone::clone ($self);
}

#  named for consistency with Geo::GDAL::FFI
sub Buffer {
    my ($self, $buffer) = @_;
    my $clone = $self->clone;
    $clone->{radius} += $buffer;
    $clone;
}


1;