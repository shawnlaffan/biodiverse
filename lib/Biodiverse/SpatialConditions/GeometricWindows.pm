package Biodiverse::SpatialConditions::GeometricWindows;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use Carp;
use English qw /-no_match_vars/;

use Math::Trig qw /deg2rad/;
use Scalar::Util qw /looks_like_number/;
use List::MoreUtils qw /uniq/;
use List::Util qw /min max any/;
use Ref::Util qw /is_arrayref/;


sub get_metadata_sp_circle {
    my $self = shift;
    my %args = @_;

    my $example = <<~'END_CIRC_EX'
        #  A circle of radius 1000 across all axes
        sp_circle (radius => 1000)

        #  use only axes 0 and 3
        sp_circle (radius => 1000, axes => [0, 3])
        END_CIRC_EX
    ;

    my $descr = <<~'EOD'
        A circle.  Assessed against all dimensions by default
        (more properly called a hypersphere)
        but you can use the optional `axes => []` arg to specify a subset.
        Uses group (map) distances.
        EOD
    ;

    my %metadata = (
        description => $descr,
        use_abs_euc_distances => ($args{axes} // []),
        #  don't need $D if we're using a subset
        use_euc_distance      => !$args{axes},
        #  flag index dist if easy to determine
        index_max_dist =>
            ( looks_like_number $args{radius} ? $args{radius} : undef ),
        required_args => ['radius'],
        optional_args => [qw /axes/],
        result_type   => 'circle',
        example       => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  sub to run a circle (or hypersphere for n-dimensions)
sub sp_circle {
    my $self = shift;
    my %args = @_;

    my $h = $self->get_current_args;

    my $dist;
    if (my $axes = $args{axes} ) {
        my $dists = $h->{dists}{D_list};
        my $d_sqr = 0;
        foreach my $axis (@$axes) {

            #  drop out clause to save some comparisons over large data sets
            return if $dists->[$axis] > $args{radius};

            # increment
            $d_sqr += $dists->[$axis]**2;
        }
        $dist = sqrt $d_sqr;
    }
    else {
        $dist = $h->{dists}{D};
    }

    return $dist <= $args{radius};
}

sub get_metadata_sp_circle_cell {
    my $self = shift;
    my %args = @_;

    my $example = <<~'END_CIRC_CELL_EX'
        #  A circle of radius 3 cells across all axes
        sp_circle (radius => 3)

        #  use only axes 0 and 3
        sp_circle_cell (radius => 3, axes => [0, 3])
        END_CIRC_CELL_EX
    ;

    my $descr = <<~'EOD'
        A circle.  Assessed against all dimensions by default
        (more properly called a hypersphere)
        but you can use the optional `axes => []` arg to specify a subset.
        Uses cell (map) distances.
        EOD
    ;

    my %metadata = (
        description => $descr,
        use_abs_cell_distances => ($args{axes} // []),
        #  don't need $C if we're using a subset
        use_cell_distance      => !$args{axes},
        required_args => ['radius'],
        result_type   => 'circle',
        example       => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  cell based circle.
sub sp_circle_cell {
    my $self = shift;
    my %args = @_;

    my $h = $self->get_current_args;

    my $dist;
    if (my $axes = $args{axes}) {
        my $dists = $h->{dists}{C_list};
        my $d_sqr = 0;
        foreach my $axis (@$axes) {
            $d_sqr += $dists->[$axis]**2;
        }
        $dist = sqrt $d_sqr;
    }
    else {
        $dist = $h->{dists}{C};
    }

    return $dist <= $args{radius};
}


my $rectangle_example = <<~'END_RECTANGLE_EXAMPLE'
    #  A rectangle of equal size on the first two axes,
    #  and 100 on the third.
    sp_rectangle (sizes => [100000, 100000, 100])

    #  The same, but with the axes reordered
    #  (an example of using the axes argument)
    sp_rectangle (
        sizes => [100000, 100, 100000],
        axes  => [0, 2, 1],
    )

    #  Use only the first an third axes
    sp_rectangle (sizes => [100000, 100000], axes => [0,2])
    END_RECTANGLE_EXAMPLE
;

sub get_metadata_sp_rectangle {
    my $self = shift;
    my %args = @_;

    my $shape_type = 'rectangle';

    #  sometimes complex conditions are passed, not just numeric scalars
    my @unique_axis_vals = uniq @{$args{sizes}};
    my $non_numeric_axis_count = grep {!looks_like_number $_} @unique_axis_vals;
    my ($largest_axis, $axis_count);
    $axis_count = 0;
    if ($non_numeric_axis_count == 0) {
        $largest_axis = max @unique_axis_vals;
        $axis_count   = scalar @{$args{sizes}};
    }

    if ($axis_count > 1 && scalar @unique_axis_vals == 1) {
        $shape_type = 'square';
    }

    my $descr = <<~'EOD'
        A rectangle.  Assessed against all dimensions by default
        (more properly called a hyperbox)
        but use the optional `axes => []` arg to specify a subset.
        Uses group (map) distances.
        EOD
    ;

    my %metadata = (
        description => $descr,
        use_euc_distance => 1,
        required_args => ['sizes'],
        optional_args => [qw /axes/],
        result_type   => 'circle',  #  centred on processing group, so leave as type circle
        example       => $rectangle_example,
        index_max_dist => $largest_axis,
        shape_type     => $shape_type,
    );

    return $self->metadata_class->new (\%metadata);
}

#  sub to run a circle (or hypersphere for n-dimensions)
sub sp_rectangle {
    my $self = shift;
    my %args = @_;

    my $sizes = $args{sizes};
    my $axes = $args{axes} // [0 .. $#$sizes];

    #  should check this in the metadata phase
    croak "Too many axes in call to sp_rectangle\n"
        if $#$axes > $#$sizes;

    my $h     = $self->get_current_args;
    my $dists = $h->{dists}{D_list};

    my $i = -1;  #  @$sizes is in the same order as @$axes
    foreach my $axis (@$axes) {
        ###  need to trap refs to non-existent axes.

        $i++;
        #  coarse filter
        return if $dists->[$axis] > $sizes->[$i];
        #  now check with precision adjusted
        my $d = $self->round_to_precision_aa ($dists->[$axis]);
        return if $d > $sizes->[$i] / 2;
    }

    return 1;
}


sub get_metadata_sp_annulus {
    my $self = shift;
    my %args = @_;

    my $descr = <<~'EOD'
        An annulus.  Assessed against all dimensions by default
        but use the optional `axes => []` arg to specify a subset.
        Uses group (map) distances.
        EOD
    ;

    my $example = <<~'EOEX'
        #  an annulus assessed against all axes
        sp_annulus (inner_radius => 2000000, outer_radius => 4000000)

        #  an annulus assessed against axes 0 and 1
        sp_annulus (inner_radius => 2000000, outer_radius => 4000000, axes => [0,1])
        EOEX
    ;

    my %metadata = (
        description => $descr,
        #  don't need $D if we're using a subset
        use_abs_euc_distances => ($args{axes} // []),
        #  flag index dist if easy to determine
        use_euc_distance   => $args{axes} ? undef : 1,
        index_max_dist     => $args{outer_radius},
        required_args      => [ 'inner_radius', 'outer_radius' ],
        optional_args      => [qw /axes/],
        result_type        => 'circle',
        example            => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  sub to run an annulus
sub sp_annulus {
    my $self = shift;
    my %args = @_;

    my $h = $self->get_current_args;

    my $dist;
    if ( $args{axes} ) {
        my $axes  = $args{axes};
        my $dists = $h->{dists}{D_list};
        my $d_sqr = 0;
        foreach my $axis (@$axes) {

            #  drop out clause to save some comparisons over large data sets
            return if $dists->[$axis] > $args{outer_radius};

            # increment
            $d_sqr += $dists->[$axis]**2;
        }
        $dist = sqrt $d_sqr;
    }
    else {
        $dist = $h->{dists}{D};
    }

    my $test =
        eval { $dist >= $args{inner_radius} && $dist <= $args{outer_radius} };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $test;
}

sub get_metadata_sp_square {
    my $self = shift;
    my %args = @_;

    my $example = <<~'END_SQR_EX'
        #  An overlapping square, cube or hypercube
        #  depending on the number of axes
        #   Note - you cannot yet specify which axes to use
        #   so it will be square on all sides
        sp_square (size => 300000)
        END_SQR_EX
    ;

    my %metadata = (
        description =>
            "An overlapping square assessed against all dimensions (more properly called a hypercube).\n"
                . 'Uses group (map) distances.',
        use_euc_distance => 1,    #  need all the distances
        #  flag index dist if easy to determine
        index_max_dist =>
            ( looks_like_number $args{size} ? $args{size} : undef ),
        required_args => ['size'],
        result_type   => 'square',
        shape_type    => 'square',
        example       =>  $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  sub to run a square (or hypercube for n-dimensions)
#  should allow control over which axes to use
sub sp_square {
    my $self = shift;
    my %args = @_;

    croak "Size argument to sp_square is not numeric.  Did you mean to use sp_rectangle?\n"
        if !looks_like_number $args{size};

    my $size = $args{size} / 2;

    my $h = $self->get_current_args;
    my $aref = $h->{dists}{D_list} // [];
    return List::Util::all {$_ <= $size} @$aref;
}

sub get_metadata_sp_square_cell {
    my $self = shift;
    my %args = @_;

    my $index_max_dist;
    my $bd = $self->get_basedata_ref;
    if (defined $args{size} && $bd) {
        my $cellsizes = $bd->get_cell_sizes;
        my @u = uniq @$cellsizes;
        if (@u == 1 && looks_like_number $u[0]) {
            $index_max_dist = $args{size} * $u[0] / 2;
        }
    }

    my $description =
        'A square assessed against all dimensions '
            . "(more properly called a hypercube).\n"
            . q{Uses 'cell' distances.};

    my %metadata = (
        description => $description,
        use_cell_distance => 1,    #  need all the distances
        index_max_dist    => $index_max_dist,
        required_args => ['size'],
        result_type   => 'square',
        example       => 'sp_square_cell (size => 3)',
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_square_cell {
    my $self = shift;
    my %args = @_;

    my $size = $args{size} / 2;

    my $h = $self->get_current_args;
    my $aref = $h->{dists}{C_list} // [];
    return List::Util::all {$_ <= $size} @$aref;
}

sub get_metadata_sp_ellipse {
    my $self = shift;
    my %args = @_;

    my $axes = $args{axes};
    if ( !is_arrayref($axes) ) {
        $axes = [ 0, 1 ];
    }

    my $description =
        q{A two dimensional ellipse.  Use the `axes` argument to control }
            . q{which are used (default is `[0,1]`).  The default rotate_angle is 0, }
            . q{such that the major axis is east-west.};
    my $example = <<~'END_ELLIPSE_EX'
        # North-south aligned ellipse
        sp_ellipse (
            major_radius => 300000,
            minor_radius => 100000,
            axes         => [0,1],
            rotate_angle => 1.5714,
        )
        END_ELLIPSE_EX
    ;

    my %metadata = (
        description => $description,
        use_euc_distances => $axes,
        use_euc_distance  => $axes ? undef : 1,

        #  flag the index dist if easy to determine
        index_max_dist => (
            looks_like_number $args{major_radius}
                ? $args{major_radius}
                : undef
        ),
        required_args => [qw /major_radius minor_radius/],
        optional_args => [qw /axes rotate_angle rotate_angle_deg/],
        result_type   => 'ellipse',
        example       => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  a two dimensional ellipse -
#  it would be nice to generalise to more dimensions,
#  but that involves getting mediaeval with matrices
sub sp_ellipse {
    my $self = shift;
    my %args = @_;

    my $axes = $args{axes};
    if ( defined $axes ) {
        croak "sp_ellipse:  axes arg is not an array ref\n"
            if (! is_arrayref($axes));
        my $axis_count = scalar @$axes;
        croak
            "sp_ellipse:  axes array needs two axes, you have given $axis_count\n"
            if $axis_count != 2;
    }
    else {
        $axes = [ 0, 1 ];
    }

    my $h = $self->get_current_args;

    my @d = @{ $h->{dists}{d_list} };

    my $major_radius = $args{major_radius};    #  longest axis
    my $minor_radius = $args{minor_radius};    #  shortest axis

    #  set the default offset as east-west in radians (anticlockwise 1.57 is north)
    my $rotate_angle = $args{rotate_angle};
    if ( defined $args{rotate_angle_deg} and not defined $rotate_angle ) {
        $rotate_angle = deg2rad ( $args{rotate_angle_deg} );
    }
    $rotate_angle //= 0;

    my $d0 = $d[ $axes->[0] ];
    my $d1 = $d[ $axes->[1] ];
    my $D  = sqrt ($d0 ** 2 + $d1 ** 2);

    #  now calc the bearing to rotate the coords by
    my $bearing = atan2( $d0, $d1 ) + $rotate_angle;

    my $r_x = sin($bearing) * $D;    #  rotated x coord
    my $r_y = cos($bearing) * $D;    #  rotated y coord

    my $a_dist = ( $r_y ** 2 ) / ( $major_radius**2 );
    my $b_dist = ( $r_x ** 2 ) / ( $minor_radius**2 );
    #my $precision = '%.14f';
    my $precision = 1.4 * (10 ** 10);
    $a_dist = $self->round_to_precision_aa ($a_dist, $precision) + 0;
    $b_dist = $self->round_to_precision_aa ($b_dist, $precision) + 0;

    my $test = eval { 1 >= ( $a_dist + $b_dist ) };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $test;
}

1;