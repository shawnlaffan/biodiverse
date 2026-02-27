package Biodiverse::SpatialConditions::SpCalc;

use strict;
use warnings;
use 5.022;

our $VERSION = '5.0';

use experimental qw /refaliasing for_list/;

use Carp;
use English qw /-no_match_vars/;

use POSIX qw /fmod floor/;
use Scalar::Util qw /looks_like_number/;
use Ref::Util qw { is_arrayref };

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



sub get_metadata_sp_self_only {
    my $self = shift;

    my %metadata = (
        description    => 'Select only the processing group',
        result_type    => 'self_only',
        index_max_dist => 0,    #  search only self if using index
        example        => 'sp_self_only() #  only use the processing cell',
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_self_only {
    my $self = shift;

    my $h = $self->get_current_args;

    return $h->{coord_id1} eq $h->{coord_id2};
}





1;

