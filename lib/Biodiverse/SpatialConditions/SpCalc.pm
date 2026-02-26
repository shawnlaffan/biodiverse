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

sub get_metadata_sp_select_all {
    my $self = shift;

    my %metadata = (
        description    => 'Select all elements as neighbours',
        result_type    => 'always_true',
        example        => 'sp_select_all() #  select every group',
        index_max_dist => -1,  #  search whole index if using this in a complex condition
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_all {
    return 1;    #  always returns true
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

sub get_metadata_sp_select_element {
    my $self = shift;

    my $example =<<~'END_SP_SELECT_ELEMENT'
        # match where the whole coordinate ID (element name)
        # is 'Biome1:savannah forest'
        sp_select_element (element => 'Biome1:savannah forest')
        END_SP_SELECT_ELEMENT
    ;

    my %metadata = (
        description => 'Select a specific element.  Basically the same as sp_match_text, but with optimisations enabled',
        index_max_dist => undef,

        required_args => [
            'element',  #  the element name
        ],
        optional_args => [
            'type',  #  nbr or proc to control use of nbr or processing groups
        ],
        index_no_use => 1,
        result_type  => 'always_same',
        example => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_element {
    my $self = shift;
    my %args = @_;

    delete $args{axes};  #  remove the axes arg if set

    my $comparator = $self->get_comparator_for_text_matching (%args);

    return $args{element} eq $comparator;
}


sub get_metadata_sp_match_text {
    my $self = shift;

    my $example =<<~'END_SP_MT_EX'
        #  use any neighbour where the first axis has value of "type1"
        sp_match_text (text => 'type1', axis => 0, type => 'nbr')

        # match only when the third neighbour axis is the same
        #   as the processing group's second axis
        sp_match_text (text => $coord[2], axis => 2, type => 'nbr')

        # match where the whole coordinate ID (element name)
        # is 'Biome1:savannah forest'
        sp_match_text (text => 'Biome1:savannah forest')

        # Set a definition query to only use groups with 'NK' in the third axis
        sp_match_text (text => 'NK', axis => 2, type => 'proc')
        END_SP_MT_EX
    ;

    my %metadata = (
        description    => 'Select all neighbours matching a text string',
        index_max_dist => undef,

        #required_args => ['axis'],
        required_args => [
            'text',  #  the match text
        ],
        optional_args => [
            'axis',  #  which axis from nbrcoord to use in the match
            'type',  #  nbr or proc to control use of nbr or processing groups
        ],
        index_no_use => 1,                   #  turn the index off
        result_type  => 'text_match_exact',
        example => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_match_text {
    my $self = shift;
    my %args = @_;

    my $comparator = $self->get_comparator_for_text_matching (%args);
    
    return $args{text} eq $comparator;
}

sub get_metadata_sp_match_regex {
    my $self = shift;

    my $example = <<~'END_RE_EXAMPLE'
        #  use any neighbour where the first axis includes the text "type1"
        sp_match_regex (re => qr'type1', axis => 0, type => 'nbr')

        # match only when the third neighbour axis starts with
        # the processing group's second axis
        sp_match_regex (re => qr/^$coord[2]/, axis => 2, type => 'nbr')

        # match the whole coordinate ID (element name)
        # where Biome can be 1 or 2 and the rest of the name contains "dry"
        sp_match_regex (re => qr/^Biome[12]:.+dry/)

        # Set a definition query to only use groups where the
        # third axis ends in 'park' (case insensitive)
        sp_match_regex (text => qr{park$}i, axis => 2, type => 'proc')

        END_RE_EXAMPLE
    ;

    my $description
        = 'Select all neighbours with an axis matching a regular expression';

    my %metadata = (
        description        => $description,
        index_max_dist => undef,

        required_args => [
            're',    #  the regex
        ],
        optional_args => [
            'type',  #  nbr or proc to control use of nbr or processing groups
            'axis',  #  which axis from nbrcoord to use in the match
        ],
        index_no_use => 1,                   #  turn the index off
        result_type  => 'non_overlapping',
        example      => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_match_regex {
    my $self = shift;
    my %args = @_;

    my $comparator = $self->get_comparator_for_text_matching (%args);

    return $comparator =~ $args{re};
}

#  get the relevant string for the text match subs
sub get_comparator_for_text_matching {
    my $self = shift;
    my %args = @_;

    my $axis = $args{axis};

    if ( defined $axis ) { #  check against one axis

        my $compcoord = $self->get_current_coord_array (%args);

        croak (
            "axis argument $axis beyond array bounds, comparing with "
            . join (q{ }, @$compcoord)
            )
          if abs ($axis) > $#$compcoord;
    
        return $compcoord->[ $axis ];
    }

    return $self->get_current_coord_id;
}




sub get_metadata_sp_select_sequence {
    my $self = shift;

    my $example = <<~'END_SEL_SEQ_EX'
        # Select every tenth group (groups are sorted alphabetically)
        sp_select_sequence (frequency => 10)

        #  Select every tenth group, starting from the third
        sp_select_sequence (frequency => 10, first_offset => 2)

        #  Select every tenth group, starting from the third last
        #  and working backwards
        sp_select_sequence (
            frequency     => 10,
            first_offset  =>  2,
            reverse_order =>  1,
        )
        END_SEL_SEQ_EX
    ;

    my %metadata = (
        description =>
            'Select a subset of all available neighbours based on a sample sequence '
            . '(note that groups are sorted south-west to north-east)',
        #  flag index dist if easy to determine
        index_max_dist => undef,
        #  frequency is how many groups apart they should be
        required_args      => [qw /frequency/],
        optional_args => [
            'first_offset',     #  the first offset, defaults to 0
            'use_cache',        #  a boolean flag, defaults to 1
            'reverse_order',    #  work from the other end
            'cycle_offset',
        ],
        index_no_use => 1,          #  turn the index off
        result_type  => 'subset',
        example      => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_sequence {
    my $self = shift;
    my %args = @_;

    my $h = $self->get_current_args;

    my $bd        = $args{caller_object} || $h->{basedata};
    my $coord_id1 = $h->{coord_id1};
    my $coord_id2 = $h->{coord_id2};

    my $verifying = $self->get_param('VERIFYING');

    my $spacing      = $args{frequency};
    my $cycle_offset = $args{cycle_offset} // 1;
    my $use_cache    = $args{use_cache} // 1;

    if ($args{clear_cache}) {
        $self->set_param(SP_SELECT_SEQUENCE_CLEAR_CACHE => 1);
    }

    my $ID                = join q{,}, @_;
    my $cache_gp_name     = 'SP_SELECT_SEQUENCE_CACHED_GROUP_LIST' . $ID;
    my $cache_nbr_name    = 'SP_SELECT_SEQUENCE_CACHED_NBRS' . $ID;
    my $cache_offset_name = 'SP_SELECT_SEQUENCE_LAST_OFFSET' . $ID;
    my $cache_last_coord_id_name = 'SP_SELECT_SEQUENCE_LAST_COORD_ID1' . $ID;
    
    #  inefficient - should put in metadata
    $self->set_param(NBR_CACHE_PFX => 'SP_SELECT_SEQUENCE_CACHED_NBRS');

    #  get the offset and increment if needed
    my $offset = $self->get_cached_value($cache_offset_name);

    #my $start_pos;

    my $last_coord_id1;
    if ( not defined $offset ) {
        $offset = $args{first_offset} || 0;

        #$start_pos = $offset;
    }
    else {    #  should we increment the offset?
        $last_coord_id1 = $self->get_cached_value($cache_last_coord_id_name);
        if ( defined $last_coord_id1 and $last_coord_id1 ne $coord_id1 ) {
            $offset++;
            if ( $cycle_offset and $offset >= $spacing ) {
                $offset = 0;
            }
        }
    }
    $self->set_cached_value( $cache_last_coord_id_name => $coord_id1 );
    $self->set_cached_value( $cache_offset_name        => $offset );

    my $cached_nbrs = $self->get_cached_value_dor_set_default_aa($cache_nbr_name, {});

    my $nbrs;
    if (    $use_cache
        and scalar keys %$cached_nbrs
        and exists $cached_nbrs->{$coord_id1} )
    {
        $nbrs = $cached_nbrs->{$coord_id1};
    }
    else {
        my @groups;
        my $cached_gps = $self->get_cached_value($cache_gp_name);
        if ( $use_cache and $cached_gps ) {
            @groups = @$cached_gps;
        }
        else {

            #  get in some order
            #  (should also put in a random option)

            if ( $args{reverse_order} ) {
                @groups = reverse $bd->get_groups_ref->get_element_list_sorted;
            }
            else {
                @groups = $bd->get_groups_ref->get_element_list_sorted;
            }

            if ( $use_cache and not $verifying ) {
                $self->set_cached_value( $cache_gp_name => \@groups );
            }
        }

        my $last_i = -1;
        for ( my $i = $offset; $i <= $#groups; $i += $spacing ) {
            my $ii = int $i;

            #print "$ii ";

            next if $ii == $last_i;    #  if we get spacings less than 1

            my $gp = $groups[$ii];

            #  should we skip this comparison?
            #next if ($args{ignore_after_use} and exists $cached_nbrs->{$gp});

            $nbrs->{$gp} = 1;
            $last_i = $ii;
        }

        #if ($use_cache and not $verifying) {
        if ( not $verifying ) {
            $cached_nbrs->{$coord_id1} = $nbrs;
        }
    }

    return defined $coord_id2 ? exists $nbrs->{$coord_id2} : 0;
}

#  get the list of cached nbrs - VERY BODGY needs generalising
sub get_cached_subset_nbrs {
    my $self = shift;
    my %args = @_;

    #  this sub only works for simple cases
    return
        if $self->get_result_type ne 'subset';

    my $cache_name;
    my $cache_pfx = $self->get_param('NBR_CACHE_PFX');
    #'SP_SELECT_SEQUENCE_CACHED_NBRS';    #  BODGE

    my %params = $self->get_params_hash;    #  find the cache name
    foreach my $param ( keys %params ) {
        next if not $param =~ /^$cache_pfx/;
        $cache_name = $param;
    }

    return if not defined $cache_name;

    my $cache     = $self->get_param($cache_name);
    my $sub_cache = $cache->{ $args{coord_id} };

    return wantarray ? %$sub_cache : $sub_cache;
}

sub clear_cached_subset_nbrs {
    my $self = shift;

    my $clear = $self->get_param('SP_SELECT_SEQUENCE_CLEAR_CACHE');
    return if ! $clear;
    
    my $cache_name;
    my $cache_pfx = 'SP_SELECT_SEQUENCE_CACHED';    #  BODGE
    
    my %params = $self->get_params_hash;    #  find the cache name
    foreach my $param ( keys %params ) {
        next if not $param =~ /^$cache_pfx/;
        $cache_name = $param;
        $self->delete_param ($cache_name);
    }

    return;
}


sub get_metadata_sp_select_block {
    my $self = shift;
    my %args = @_;
    
    my $example = <<~'END_SPSB_EX'
        # Select up to two groups per block with each block being 5 groups
        on a side where the group size is 100
        sp_select_block (size => 500, count => 2)

        #  Now do it non-randomly and start from the lower right
        sp_select_block (size => 500, count => 10, random => 0, reverse => 1)

        #  Rectangular block with user specified PRNG starting seed
        sp_select_block (size => [300, 500], count => 1, prng_seed => 454678)

        # Lower memory footprint (but longer running times for neighbour searches)
        sp_select_block (size => 500, count => 2, clear_cache => 1)
        END_SPSB_EX
    ;

    my %metadata = (
        description =>
            'Select a subset of all available neighbours based on a block sample sequence',
        #  flag index dist if easy to determine
        index_max_dist => ( looks_like_number $args{size} ? $args{size} : undef ),
        required_args      => [
            'size',           #  size of the block
        ],    
        optional_args => [
            'count',          #  how many groups per block?
            'use_cache',      #  a boolean flag, defaults to 1
            'reverse_order',  #  work from the other end
            'random',         #  randomise within blocks?
            'prng_seed',      #  seed for the PRNG
        ],
        result_type  => 'complex',  #  need to make it a subset, but that part needs work
        example      => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_block {
    my $self = shift;
    my %args = @_;

    #  do stuff here
    my $h = $self->get_current_args;

    my $bd        = $args{caller_object} || $h->{basedata} || $self->get_basedata_ref;
    my $coord_id1 = $h->{coord_id1};
    my $coord_id2 = $h->{coord_id2};

    # my $verifying = $self->get_param('VERIFYING');

    my $frequency    = $args{count} // 1;
    my $size         = $args{size}; #  should be a function of cellsizes
    my $prng_seed    = $args{prng_seed};
    my $random       = $args{random} // 1;
    # my $use_cache    = $args{use_cache} // 1;

    if ($args{clear_cache}) {
        $self->set_param(SP_SELECT_BLOCK_CLEAR_CACHE => 1);
    }

    my $cache_sp_out_name   = 'SP_SELECT_BLOCK_CACHED_SP_OUT';
    my $cached_sp_list_name = 'SP_BLOCK_NBRS';

    #  generate the spatial output and get the relevant groups
    #  NEED TO USE THE PARENT DEF QUERY IF SET? Not if this is to calculate it...
    my $sp = $self->get_param ($cache_sp_out_name);
    my $prng;
    if (! $sp) {
        $sp = $self->get_spatial_output_sp_select_block (
            basedata_ref => $bd,
            size         => $size,
        );    
        $self->set_param($cache_sp_out_name => $sp);
        $prng = $sp->initialise_rand(seed => $prng_seed);
        $sp->set_param(PRNG => $prng);
    }
    else {
        $prng = $sp->get_param ('PRNG');
    }

    my $nbrs = {};
    my @groups;
    
    if ( $sp->exists_list(list => $cached_sp_list_name, element => $coord_id1) ) {
        $nbrs = $sp->get_list_values (
            element => $coord_id1,
            list    => $cached_sp_list_name,
        );
    }
    else {
        my $these_nbrs = $sp->get_list_values (
            element => $coord_id1,
            list    => '_NBR_SET1',
        );
        my $sorted_nbrs = $sp->get_element_list_sorted(list => $these_nbrs);

        if ( $args{reverse_order} ) {
            $sorted_nbrs = [reverse @$sorted_nbrs];
        }
        if ($random) {
            $sorted_nbrs = $prng->shuffle($sorted_nbrs);
        }

        my $target = min (($frequency - 1), $#$sorted_nbrs);
        @groups = @$sorted_nbrs[0 .. $target];
        @$nbrs{@groups} = (1) x scalar @groups;

        foreach my $nbr (@$these_nbrs) {  #  cache it
            $sp->add_to_lists (
                element              => $nbr,
                $cached_sp_list_name => $nbrs,
                use_ref              => 1,
            );
        }
    }

    return defined $coord_id2 ? exists $nbrs->{$coord_id2} : 0;
}


sub get_spatial_output_sp_select_block {
    my $self = shift;
    my %args = @_;

    my $size = $args{size};

    my $bd = $args{basedata_ref} // $self->get_basedata_ref;
    my $sp = $bd->add_spatial_output (name => 'get nbrs for sp_select_block ' . time());
    $bd->delete_output(output => $sp, delete_basedata_ref => 0);

    #  add a null element to avoid some errors
    #$sp->add_element(group => 'null_group', label => 'null_label');

    my $spatial_conditions = ["sp_block (size => $size)"];

    $sp->run_analysis(
        calculations                  => [],
        override_valid_analysis_check => 1,
        spatial_conditions            => $spatial_conditions,
        #definition_query              => $definition_query,
        no_create_failed_def_query    => 1,  #  only want those that pass the def query
        calc_only_elements_to_calc    => 1,
        #basedata_ref                  => $bd,
    );

    return $sp;
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


sub get_example_sp_get_spatial_output_list_value {

    state $ex = <<~'END_EXAMPLE_GSOLV'
        #  Get the spatial results value for the current neighbour group
        # (or processing group if used as a def query)
        sp_get_spatial_output_list_value (
            output  => 'sp1',              #  using spatial output called sp1
            list    => 'SPATIAL_RESULTS',  #  from the SPATIAL_RESULTS list
            index   => 'PE_WE_P',          #  get index value for PE_WE_P
        )

        #  Get the spatial results value for group 128:254
        #  Note that the SPATIAL_OUTPUTS list is assumed if
        #  no 'list' arg is passed.
        sp_get_spatial_output_list_value (
            output  => 'sp1',
            element => '128:254',
            index   => 'PE_WE_P',
        )
        END_EXAMPLE_GSOLV
    ;

    return $ex;
}


sub get_metadata_sp_get_spatial_output_list_value {
    my $self = shift;

    my $description =
        q{Obtain a value from a list in a previously calculated spatial output.};

    my $example = $self->get_example_sp_get_spatial_output_list_value;

    my %metadata = (
        description => $description,
        index_no_use   => 1,  #  turn index off since this doesn't cooperate with the search method
        required_args  => [qw /output index/],
        optional_args  => [qw /list element no_error_if_no_index/],
        result_type    => 'always_same',
        example        => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  get the value from another spatial output
sub sp_get_spatial_output_list_value {
    my $self = shift;
    my %args = @_;

    my $list_name = $args{list} // 'SPATIAL_RESULTS';
    my $index     = $args{index};
    my $no_die_if_not_exists = $args{no_error_if_no_index};
    
    my $element = $args{element} // $self->get_current_coord_id;

    my $bd      = $self->get_basedata_ref;
    my $sp_name = $args{output};
    croak "Spatial output name not defined\n" if not defined $sp_name;

    my $sp = $bd->get_spatial_output_ref (name => $sp_name)
      or croak 'Spatial output $sp_name does not exist in basedata '
                . $bd->get_param ('NAME')
                . "\n";

    croak "element $element is not in spatial output $sp_name\n"
      if not $sp->exists_element (element => $element);

    my $list = $sp->get_list_ref (
        list    => $list_name,
        element => $element,
    );
    
    state $idx_ex_cache_name
      = 'sp_get_spatial_output_list_value_list_exists';

    if (   !exists $list->{$index}
        && !$no_die_if_not_exists
        && !$self->get_cached_value ($idx_ex_cache_name)
        ) {
        #  See if the index exists in another element.
        #  Croak if it is in none, as that is
        #  probably a typo.
        my $found_index;
        foreach my $el ($sp->get_element_list) {
            my $el_list = $sp->get_list_ref (
                list    => $list_name,
                element => $el,
            );
            $found_index ||= exists $el_list->{$index};
            last if $found_index;
        }
        
        croak "Index $index does not exist across "
            . "elements of spatial output $sp_name\n"
          if !$found_index;
    };
    
    #  in the event of a missing list in another element
    $self->set_cached_value (
        $idx_ex_cache_name => 1,
    );
    
    #no autovivification;

    return $list->{$index};
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


sub get_metadata_sp_spatial_output_passed_defq {
    my $self = shift;

    my $description =
        "Returns 1 if an element passed the definition query "
        . "for a previously calculated spatial output";

    #my $example = $self->get_example_sp_get_spatial_output_list_value;
    my $examples = <<~'END_EX'
        #  Used for spatial or cluster type analyses:
        #  The simplest case is where the current
        #  analysis includes a def query and you
        #  want to use it in a spatial condition.
        sp_spatial_output_passed_defq();

        #  Using another output in this basedata
        #  In this case the output is called 'analysis1'
        sp_spatial_output_passed_defq(
            output => 'analysis1',
        );

        #  Return true if a specific element passed the def query
        sp_spatial_output_passed_defq(
            element => '153.5:-32.5',
        );
        END_EX
    ;

    my %metadata = (
        description => $description,
        index_no_use   => 1,  #  turn index off since this doesn't cooperate with the search method
        #required_args  => [qw /output/],
        optional_args  => [qw /element output/],
        result_type    => 'always_same',
        example        => $examples,
    );

    return $self->metadata_class->new (\%metadata);
}


#  get the value from another spatial output
sub sp_spatial_output_passed_defq {
    my $self = shift;
    my %args = @_;

    my $element = $args{element} // $self->get_current_coord_id;
    
    my $bd      = $self->get_basedata_ref;
    my $sp_name = $args{output};
    my $sp;
    if (defined $sp_name) {
        $sp = $bd->get_spatial_output_ref (name => $sp_name)
            or croak 'Spatial output $sp_name does not exist in basedata '
                . $bd->get_name
            . "\n";

        # make sure we aren't trying to access ourself
        my $my_name = $self->get_name;
        croak "def_query can't reference itself"
          if defined $my_name
             && $my_name eq $sp_name 
             && $self->is_def_query;
    }
    else {
        # default to the caller spatial output
        $sp = $self->get_caller_spatial_output_ref;

        # make sure we aren't trying to access ourself
        croak "def_query can't reference itself"
          if $self->is_def_query;

        return 1
          if !$self->is_def_query && $self->get_param('VERIFYING');
    }
    
    croak "output argument not defined "
        . "or we are not being used for a spatial analysis\n"
          if !defined $sp;

    croak "element $element is not in spatial output\n"
      if not $sp->exists_element_aa ($element);

    my $passed_defq = $sp->get_pass_def_query;
    return 1 if !$passed_defq;

    return exists $passed_defq->{$element};
}

sub set_caller_spatial_output_ref {
    my ($self, $ref) = @_;
    $self->set_param (SPATIAL_OUTPUT_CALLER_REF => $ref);
    $self->weaken_param ('SPATIAL_OUTPUT_CALLER_REF');
}

sub get_caller_spatial_output_ref {
    my $self = shift;
    return $self->get_param ('SPATIAL_OUTPUT_CALLER_REF');
}

sub get_metadata_sp_points_in_same_cluster {
    my $self = shift;

    my $examples = <<~'END_EXAMPLES'
        #  Try to use the highest four clusters from the root.
        #  Note that the next highest number will be used
        #  if four is not possible, e.g. there are five
        #  siblings below the root.  Fewer will be returned
        #  if the tree has insufficient tips.
        sp_points_in_same_cluster (
          output       => "some_cluster_output",
          num_clusters => 4,
        )

        #  Cut the tree at a distance of 0.25 from the tips
        sp_points_in_same_cluster (
          output          => "some_cluster_output",
          target_distance => 0.25,
        )

        #  Cut the tree at a depth of 3.
        #  The root is depth 1.
        sp_points_in_same_cluster (
          output          => "some_cluster_output",
          target_distance => 3,
          group_by_depth  => 1,
        )

        #  work from an arbitrary node
        sp_points_in_same_cluster (
          output       => "some_cluster_output",
          num_clusters => 4,
          from_node    => '118___',  #  use the node's name
        )

        #  target_distance is ignored if num_clusters is set
        sp_points_in_same_cluster (
          output          => "some_cluster_output",
          num_clusters    => 4,
          target_distance => 0.25,
        )

        END_EXAMPLES
    ;

    my %metadata = (
        description =>
              'Returns true when two points are within the same '
            . ' cluster or region grower group, or if '
            . ' neither point is in the selected clusters/groups.',
        required_args => [
            qw /output/,
        ],
        optional_args => [
            qw /
              num_clusters
              group_by_depth
              target_distance
              from_node
            /
        ],
        index_no_use => 1,
        result_type  => 'non_overlapping',
        example => $examples,
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_points_in_same_cluster {
    my $self = shift;
    my %args = @_;
    
    croak 'One of "num_clusters" or "target_distance" arguments must be defined'
      if !defined ($args{num_clusters} // $args{target_distance});

    my $cl_name = $args{output}
      // croak "Cluster output name not defined\n";

    my $h = $self->get_current_args;

    my $bd = $self->get_basedata_ref;
    
    my $element1 = $args{element1};
    my $element2 = $args{element2};
    #  only need to check existence if user passed the element names
    croak "element $element1 is not in basedata\n"
      if defined $element1 and not $bd->exists_group_aa ($element1);
    croak "element $element2 is not in basedata\n"
      if defined $element2 and not $bd->exists_group_aa ($element2);
    $element1 //= $h->{coord_id1};
    $element2 //= $h->{coord_id2};

    my $cl = $bd->get_cluster_output_ref (name => $cl_name)
      or croak "Spatial output $cl_name does not exist in basedata "
                . $bd->get_name
                . "\n";

    state $cache_name = 'sp_points_in_same_cluster_output_group';
    $cache_name   .= join $SUBSEP, %args{sort keys %args}; # $SUBSEP is \034 by default
    my $by_element = $self->get_cached_value ($cache_name);
    if (!$by_element) {
        my $root = defined $args{from_node}
          ? $cl->get_node_ref_aa($args{from_node})
          : $cl;
        #  tree object also caches
        my $target_nodes
          = $root->group_nodes_below (%args);
        foreach my ($node_name, $node) (%$target_nodes) {
            my $terminals = $node->get_terminal_elements;
            @$by_element{keys %$terminals} = ($node_name) x keys %$terminals;
        }
        $self->set_cached_value($cache_name => $by_element);
    }

    return ($by_element->{$element1} // $SUBSEP) eq ($by_element->{$element2} // $SUBSEP);
}


sub get_metadata_sp_point_in_cluster {
    my $self = shift;

    my $examples = <<~'END_EXAMPLES';
        #  Use any element that is a terminal in the cluster output.
        #  This is useful if the cluster analysis was run under
        #  a definition query and you want the same set of groups.
        sp_point_in_cluster (
          output       => "some_cluster_output",
        )

        #  Now specify a cluster within the output
        sp_point_in_cluster (
          output       => "some_cluster_output",
          from_node    => '118___',  #  use the node's name
        )

        #  Specify an element to check instead of the current
        #  processing element.
        sp_point_in_cluster (
          output       => "some_cluster_output",
          from_node    => '118___',  #  use the node's name
          element      => '123:456', #  specify an element to check
        )

        END_EXAMPLES

    my %metadata = (
        description =>
              'Returns true when the group is in a '
            . ' cluster or region grower output cluster.',
        required_args => [
            qw /output/,
        ],
        optional_args => [qw /element from_node/],
        index_no_use => 1,
        result_type  => 'always_same',
        example => $examples,
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_point_in_cluster {
    my $self = shift;
    my %args = @_;

    my $cl_name = $args{output}
      // croak "Cluster output name not defined\n";

    my $bd = $self->get_basedata_ref;

    croak "element $args{element} is not in basedata\n"
      if defined $args{element} and not $bd->exists_group_aa ($args{element});

    my $element = $self->get_current_coord_id;

    my $cl = $bd->get_cluster_output_ref (name => $cl_name)
      or croak "Spatial output $cl_name does not exist in basedata "
                . $bd->get_name
                . "\n";

    state $cache_name = 'sp_points_in_cluster_output_group';
    $cache_name   .= join $SUBSEP, %args{sort keys %args}; # $SUBSEP is \034 by default
    my $terminal_elements = $self->get_cached_value ($cache_name);
    if (!$terminal_elements) {
        my $root = $args{from_node}
          ? $cl->get_node_ref_aa($args{from_node})
          : $cl->get_root_node;
        #  tree object also caches
        $terminal_elements = $root->get_terminal_elements;
        $self->set_cached_value($cache_name => $terminal_elements);
    }

    return !!$terminal_elements->{$element};
}


1;

