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

    \my @coord    = $h->{coord_array};
    \my @nbrcoord = $h->{nbrcoord_array};

    my $size = $args{size};    #  need a handler for size == 0
    if ( !is_arrayref($size) ) {
        $size = [ ($size) x scalar @coord ];
    };    #  make it an array if necessary;

    #  the origin allows the user to shift the blocks around
    my $origin = $args{origin} || [ (0) x scalar @coord ];
    if ( !is_arrayref($origin) ) {
        $origin = [ ($origin) x scalar @coord ];
    }    #  make it an array if necessary

    foreach my $i ( 0 .. $#coord ) {
        next if !defined $size->[$i];    #  ignore if this is undef

        my $c_val = floor (($coord[$i]    - $origin->[$i]) / $size->[$i]);
        my $n_val = floor (($nbrcoord[$i] - $origin->[$i]) / $size->[$i]);

        return 0 if $c_val != $n_val;
    }
    return 1;
}

sub vec_sp_block {
    my ($self, %args) = @_;

    use PDL::Lite;

    my $h = $self->get_current_args;

    my $this_coord_pdl = pdl ($h->{coord_array});
    my $all_coord_pdl = $self->get_vector_set_coords_pdl;

    my $size = $args{size};    #  need a handler for size == 0
    my $origin = $args{origin} // 0;
    if ( is_arrayref($size) ) {
        my @axes = grep {defined $size->[$_]} (0 .. $#$size);
        $all_coord_pdl = $all_coord_pdl->dice(\@axes);
        $this_coord_pdl = pdl (@{$h->{coord_array}}[@axes]);
        $size = pdl [ @$size[@axes]];
        #  the origin allows the user to shift the blocks around
        if (is_arrayref $origin) {
            $origin = pdl [ @$origin[@axes]];
        }
    };
    my $cache = $self->get_volatile_cache->get_cached_href ('vec_sp_block');
    my $cache_key = "$size $origin";
    my $block_coords     = $cache->{$cache_key} //= (($all_coord_pdl  - $origin) / $size)->floor;
    my $block_this_coord = (($this_coord_pdl - $origin) / $size)->floor;
    # my $diff = $block_coords - $block_this_coord;
    my $mask = ($block_coords - $block_this_coord)->orover->not->transpose;

    return $mask;
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

sub vec_sp_self_only {
    my ($self, %args) = @_;

    use PDL::Lite;

    my $h = $self->get_current_args;
    my $this_coord = $h->{coord_id1};

    my $u_hash = $self->get_vector_set_universe;

    my $n = scalar keys %$u_hash;
    my $pdl = PDL->zeroes($n);
    $pdl->index(pdl (PDL::indx, $u_hash->{$this_coord})) .= 1;

    return $pdl;
}




1;

