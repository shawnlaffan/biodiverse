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

    my $size = $args{size};    #  need a handler for size == 0
    if ( !is_arrayref($size) ) {
        $size = [ ($size) x scalar @coord ];
    };    #  make it an array if necessary;

    #  the origin allows the user to shift the blocks around
    my $origin = $args{origin} || [ (0) x scalar @coord ];
    if ( !is_arrayref($origin) ) {
        $origin = [ ($origin) x scalar @coord ];
    }    #  make it an array if necessary

    #  no trailing sizes
    if (@$size > @coord) {
        $#$size = $#coord;
    }
    if (@$origin > @coord) {
        $#$origin = $#coord;
    }

    my $cache = $self->get_cached_href('sp_block_element_hash');
    my $cache_key = sprintf (
        'Size %s, Origin %s',
        join (':', map {$_ // ''} @$size),
        join (':', map {$_ // ''} @$origin),
    );
    my $cached_href = $cache->{$cache_key};
    if (!$cached_href) {
        my $bd = $self->get_basedata_ref;
        my %aggregated;
        my @orgn = map {$_ // 0} @$origin;
        my @axes = grep {defined $size->[$_]} (0 .. $#$size);
        use POSIX qw/floor/;
        foreach my $element (sort $bd->get_groups) {
            \my @coord = $bd->get_group_element_as_array_aa ($element);
            my $el_blocked = join ':', (map { floor(($coord[$_] - $orgn[$_]) / $size->[$_]) } (@axes));
            $aggregated{$element} = $el_blocked;
        }
        $cached_href = $cache->{$cache_key} = \%aggregated;
    }

    #  Index checks don't pass elements through so an exact check does not work.
    #  Instead we process each axis in turn, as per the previous method.
    if (!defined $cached_href->{$h->{coord_id1}} || !defined $cached_href->{$h->{coord_id2}}) {
        \my @nbrcoord = $h->{nbrcoord_array};
        foreach my $i (0 .. $#coord) {
            next if !defined $size->[$i]; #  ignore if this is undef

            my $c_val = floor(($coord[$i] - $origin->[$i]) / $size->[$i]);
            my $n_val = floor(($nbrcoord[$i] - $origin->[$i]) / $size->[$i]);

            return 0 if $c_val != $n_val;
        }
        return 1;
    }

    return $cached_href->{$h->{coord_id1}} eq $cached_href->{$h->{coord_id2}};
}

sub vec_sp_block {
    my ($self, %args) = @_;

    use PDL::Lite;

    my $h = $self->get_current_args;

    my $this_coord_pdl = pdl ($h->{coord_array});

    my $size = $args{size};    #  need a handler for size == 0
    my $origin = $args{origin} // 0;
    my (@axes, $n_axes);
    if ( is_arrayref($size) ) {
        #  no trailing sizes
        if (@$size > @{$h->{coord_array}}) {
            $#$size = $#{$h->{coord_array}};
        }
        @axes = grep {defined $size->[$_]} (0 .. $#$size);
        if (@axes < @$size) {
            $this_coord_pdl = pdl(@{$h->{coord_array}}[@axes]);
            $size = pdl [ @$size[@axes] ];
            $n_axes = @axes;
        }
    };
    #  the origin allows the user to shift the blocks around
    if ( is_arrayref $origin ) {
        if (!@axes) {
            @axes = (0 .. $#$origin);
        };
        $origin = pdl [ map {$_ // 0} @$origin[@axes]];
    }

    my $cache = $self->get_volatile_cache->get_cached_href ('vec_sp_block');
    my $cache_key = "$size $origin " . join ':', @axes;

    my $block_this_coord = ($this_coord_pdl - $origin)->inplace->divide ($size)->floor;
    my $mask;
    my $bd = $self->get_basedata_ref;
    my $n = $bd->get_group_count;

    #  Non-indexed if element is not in the basedata or we have not many elements.
    #  Still does not handle elements beyond bd bounds.
    if (!$bd->exists_group_aa($h->{coord_id1}) || $n < 50) {
        my $block_coords = $cache->{coords}{$cache_key} //= do {
            my $all_coord_pdl = $self->get_vector_set_coords_pdl;
            if ($n_axes) {
                $all_coord_pdl = $all_coord_pdl->dice(\@axes);
            }
            (($all_coord_pdl - $origin) / $size)->floor;
        };
        $mask = ($block_coords - $block_this_coord)->orover->not->transpose;
        return $mask;
    }

    $mask = PDL->zeroes($n);
    my $block_idx_cache = $cache->{block_idx}{$cache_key};
    if (!$block_idx_cache) {
        my %hash;
        \my %universe = $self->get_vector_set_universe;
        foreach my $element (sort $bd->get_groups) {
            my $coord = $bd->get_group_element_as_array_aa ($element);
            if ($n_axes) {
                $coord = @$coord[@axes];
            }
            my $block_coord = (pdl ($coord) - $origin)->inplace->divide ($size)->floor;
            my $aref = $hash{$block_coord} //= [];
            push @$aref, $universe{$element};
        }
        $_ = pdl(PDL::indx(), $_)
            for values %hash;
        $block_idx_cache = $cache->{block_idx}{$cache_key} = \%hash;
    }

    my $indx = $block_idx_cache->{$block_this_coord};
    $mask->index($indx) .= 1;

    return $mask->transpose;
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

