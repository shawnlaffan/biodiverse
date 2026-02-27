package Biodiverse::SpatialConditions::Sidedness;

use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use experimental qw /refaliasing for_list/;

use Carp;
use English qw /-no_match_vars/;

use Math::Trig qw/deg2rad/;
use Ref::Util qw / is_arrayref /;


sub get_metadata_sp_is_left_of {
    my $self = shift;

    my $description =<<~'EOD'
        Are we to the left of a vector radiating out from the processing cell?
        Use the `axes` argument to control which are used (default is `[0,1]`).
        EOD
    ;

    my %metadata = (
        description => $description,

        #  flag the index dist if easy to determine
        index_max_dist => undef,
        optional_args => [qw /axes vector_angle vector_angle_deg/],
        result_type   => 'side',
        example       =>
            'sp_is_left_of (vector_angle => 1.5714)',
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_is_left_of {
    my $self = shift;
    #my %args = @_;

    #  no explicit return here for speed reasons
    $self->_sp_side(@_) < 0;
}

sub get_metadata_sp_is_right_of {
    my $self = shift;

    my $description =<<~'EOD'
        Are we to the right of a vector radiating out from the processing cell?
        Use the `axes` argument to control which are used (default is `[0,1]`).
        EOD
    ;

    my %metadata = (
        description => $description,
        #  flag the index dist if easy to determine
        index_max_dist => undef,
        optional_args => [qw /axes vector_angle vector_angle_deg/],
        result_type   => 'side',
        example       => 'sp_is_right_of (vector_angle => 1.5714)',
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_is_right_of {
    my $self = shift;

    #  no explicit return here for speed reasons
    $self->_sp_side(@_) > 0;
}

sub get_metadata_sp_in_line_with {
    my $self = shift;

    my $description =<<~'EOD'
        Are we in line with a vector radiating out from the processing cell?
        Use the `axes` argument to control which are used (default is `[0,1]`).
        EOD
    ;

    my %metadata = (
        description => $description,
        #  flag the index dist if easy to determine
        index_max_dist => undef,
        optional_args => [qw /axes vector_angle vector_angle_deg/],
        result_type   => 'side',
        example       => 'sp_in_line_with (vector_angle => Math::Trig::pip2) #  pi/2 = 90 degree angle',
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_in_line_with {
    my $self = shift;
    #my %args = @_;

    #  no explicit return here for speed reasons
    $self->_sp_side(@_) == 0;
}


sub _sp_side {
    my ($self, %args) = @_;

    my $axes_ref = $args{axes};
    if ( defined $axes_ref ) {
        croak "_sp_side:  axes arg is not an array ref\n"
            if ( !is_arrayref($axes_ref) );
        croak
            "_sp_side:  axes array needs two axes, you have given " . (scalar @$axes_ref) . "\n"
            if @$axes_ref != 2;
    }

    \my @axes = $axes_ref // [0,1];

    my $h = $self->get_current_args;

    #  Need to de-ref to get the values
    \my @coord     = $h->{coord_array};
    \my @nbr_coord = $h->{nbrcoord_array};

    #  coincident points are in line
    return 0 if (
        $nbr_coord[$axes[1]] == $coord[$axes[1]]
            && $nbr_coord[$axes[0]] == $coord[$axes[0]]
    );

    #  set the default offset as east in radians
    my $vector_angle = $args{vector_angle} // deg2rad($args{vector_angle_deg} // 0);

    #  Rotate so easterly vector points north.
    #  This lets us use the x-axis to check sidedness.
    $vector_angle = Math::Trig::pip2 - ($vector_angle // 0);
    my $coord_id     = $h->{coord_id1};
    my $nbr_coord_id = $h->{coord_id2};
    my $bd = $self->get_basedata_ref(%args);
    \my %rotated  = $bd->_get_rotated_scaled_axis_coords_hash (
        %args,
        angle => $vector_angle,
        axes => \@axes,
    );

    state %cache;  #  global cache, should maybe have one per basedata?
    \my @rot_coord = $rotated{$coord_id}
        // ($cache{$coord_id}{join ':', @axes}{$vector_angle} //=
        $bd->_get_rotated_scaled_coords_aa(@coord, $vector_angle, \@axes)
    );
    \my @rot_nbrcoord = $rotated{$nbr_coord_id}
        // ($cache{$nbr_coord_id}{join ':', @axes}{$vector_angle} //=
        $bd->_get_rotated_scaled_coords_aa(@nbr_coord, $vector_angle, \@axes)
    );

    return $rot_nbrcoord[0] <=> $rot_coord[0];
}

1;