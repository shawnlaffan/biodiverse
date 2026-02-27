package Biodiverse::SpatialConditions::SpCalc;

use strict;
use warnings;
use 5.022;

our $VERSION = '5.0';

use experimental qw /refaliasing for_list/;

use Carp;
use English qw /-no_match_vars/;

use POSIX qw /fmod floor ceil/;
use Math::Trig;
use Math::Trig ':pi';
use Math::Polygon;
use Geo::ShapeFile 3.00;
use Tree::R;
use Biodiverse::Progress;
use Scalar::Util qw /looks_like_number blessed/;
use List::MoreUtils qw /uniq/;
use List::Util qw /min max any/;
use Ref::Util qw { :all };

use parent qw /
    Biodiverse::SpatialConditions::LabelRanges
    Biodiverse::SpatialConditions::Polygons
    Biodiverse::SpatialConditions::Sidedness
    Biodiverse::SpatialConditions::Select
    Biodiverse::SpatialConditions::CalculatedOutputs
    Biodiverse::SpatialConditions::TextMatch
/;


use Biodiverse::Metadata::SpatialConditions;

our $NULL_STRING = q{};

################################################################################
#  now for a set of shortcut subs so people don't have to learn so much perl syntax,
#    and it doesn't have to guess things

#  process still needs thought - eg the metadata

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

sub get_metadata_sp_block {
    my $self = shift;
    my %args = @_;

    my $shape_type = 'complex';
    if (looks_like_number $args{size} && !defined $args{origin}) {
        $shape_type = 'square';
    }
    
    my $index_max_dist = looks_like_number $args{size} ? $args{size} : undef;

    my %metadata = (
        description =>
            'A non-overlapping block.  Set an axis to undef to ignore it.',
        index_max_dist => $index_max_dist,
        shape_type     => $shape_type,
        required_args  => ['size'],
        optional_args  => ['origin'],
        result_type    => 'non_overlapping'
        , #  we can recycle results for this (but it must contain the processing group)
          #  need to add optionals for origin and axes_to_use
        example => "sp_block (size => 3)\n"
            . 'sp_block (size => [3,undef,5]) #  rectangular block, ignores second axis',
    );

    return $self->metadata_class->new (\%metadata);
}

#  non-overlapping block, cube or hypercube
#  should drop the guts into another sub so we can call it with cell based args
sub sp_block {
    my $self = shift;
    my %args = @_;

    croak "sp_block: argument 'size' not specified\n"
        if not defined $args{size};

    my $h = $self->get_current_args;

    my $coord    = $h->{coord_array};
    my $nbrcoord = $h->{nbrcoord_array};

    my $size = $args{size};    #  need a handler for size == 0
    if ( !is_arrayref($size) ) {
        $size = [ ($size) x scalar @$coord ];
    };    #  make it an array if necessary;

    #  the origin allows the user to shift the blocks around
    my $origin = $args{origin} || [ (0) x scalar @$coord ];
    if ( !is_arrayref($origin) ) {
        $origin = [ ($origin) x scalar @$coord ];
    }    #  make it an array if necessary

    foreach my $i ( 0 .. $#$coord ) {
        #  should add an arg to use a slice (subset) of the coord array
        #  Should also use floor() instead of fmod()

        next if not defined $size->[$i];    #  ignore if this is undef
        my $axis   = $coord->[$i];
        my $tmp    = $axis - $origin->[$i];
        my $offset = fmod( $tmp, $size->[$i] );
        my $edge   = $offset < 0               #  "left" edge
            ? $axis - $offset - $size->[$i]    #  allow for -ve fmod results
            : $axis - $offset;
        my $dist = $nbrcoord->[$i] - $edge;
        return 0 if $dist < 0 or $dist > $size->[$i];
    }
    return 1;
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

sub get_metadata_sp_self_only {
    my $self = shift;

    my %metadata = (
        description    => 'Select only the processing group',
        result_type    => 'self_only',
        index_max_dist => 0,    #  search only self if using index
        example        => 'sp_self_only() #  only use the proceessing cell',
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_self_only {
    my $self = shift;

    my $h = $self->get_current_args;

    return $h->{coord_id1} eq $h->{coord_id2};
}



sub get_metadata_sp_group_not_empty {
    my $self = shift;

    my $example = <<~'END_GP_NOT_EMPTY_EX'
        # Restrict calculations to those non-empty groups.
        #  Will use the processing group if a def query,
        #  the neighbour group otherwise.
        sp_group_not_empty ()

        # The same as above, but being specific about which group (element) to test.
        #  This is probably best used in cases where the element
        #  to check is varied spatially.}
        sp_group_not_empty (element => '5467:9876')
        END_GP_NOT_EMPTY_EX
    ;

    my %metadata = (
        description   => 'Is a basedata group non-empty? (i.e. contains one or more labels)',
        required_args => [],
        optional_args => [
            'element',      #  which element to use 
        ],
        result_type   => $NULL_STRING,
        example       => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_group_not_empty {
    my $self = shift;
    my %args = @_;

    my $element = $args{element} // $self->get_current_coord_id;

    my $bd  = $self->get_basedata_ref;

    return !!$bd->get_richness_aa ($element);
}


sub get_example_sp_richness_greater_than {

    state $ex = <<~'END_EXAMPLE_RGT'
        #  Uses the processing group for definition queries,
        #  and the neigbour group for spatial conditions.
        sp_richness_greater_than (
            threshold => 3, # any group with 3 or fewer labels will return false
        )

        sp_richness_greater_than (
            element   => '128:254',  #  an arbitrary element
            threshold => 4,          #  with a threshold of 4
        )
        END_EXAMPLE_RGT
    ;

    return $ex;
}

sub get_metadata_sp_richness_greater_than {
    my $self = shift;

    my $description =
        q{Return true if the richness for an element is greater than the threshold.};

    my $example = $self->get_example_sp_richness_greater_than;

    my %metadata = (
        description    => $description,
        index_no_use   => 1,  #  turn index off since this doesn't cooperate with the search method
        required_args  => [qw /threshold/],
        optional_args  => [qw /element/],
        result_type    => 'always_same',
        example        => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_richness_greater_than {
    my $self = shift;
    my %args = @_;

    my $element = $args{element} // $self->get_current_coord_id;
    my $threshold = $args{threshold}
      // croak 'sp_richness_greater_than: threshold arg must be passed';

    my $bd = $self->get_basedata_ref;

    #  needed if element arg not passed?
    croak "element $element is not in basedata\n"
      if not $bd->exists_group_aa ($element);
    
    return $bd->get_richness_aa($element) > $threshold;
}

sub get_example_sp_redundancy_greater_than {

    state $ex = <<~'END_EXAMPLE_REDUNDGT'
        #  Uses the processing group for definition queries,
        #  and the neighbour group for spatial conditions.
        #  In this example, # any group with a redundncy
        #  score of 0.5 or fewerless will return false
        sp_redundancy_greater_than (
            threshold => 0.5,
        )

        sp_redundancy_greater_than (
            element   => '128:254',  #  an arbitrary element
            threshold => 0.2,          #  with a threshold of 0.2
        )
        END_EXAMPLE_REDUNDGT
    ;

    return $ex;
}

sub get_metadata_sp_redundancy_greater_than {
    my $self = shift;

    my $description =
        q{Return true if the sample redundancy for an element is greater than the threshold.};

    my $example = $self->get_example_sp_redundancy_greater_than;

    my %metadata = (
        description    => $description,
        index_no_use   => 1,  #  turn index off since this doesn't cooperate with the search method
        required_args  => [qw /threshold/],
        optional_args  => [qw /element/],
        result_type    => 'always_same',
        example        => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_redundancy_greater_than {
    my $self = shift;
    my %args = @_;

    my $element = $args{element} // $self->get_current_coord_id;
    my $threshold = $args{threshold}
      // croak 'sp_redundancy_greater_than: threshold arg must be passed';

    my $bd = $self->get_basedata_ref;

    #  needed if element arg not passed and we used the default?
    croak "element $element is not in basedata\n"
      if not $bd->exists_group_aa ($element);
    
    return $bd->get_redundancy_aa ($element) > $threshold;
}



1;

