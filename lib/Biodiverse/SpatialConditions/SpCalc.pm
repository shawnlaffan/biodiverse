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
    Biodiverse::SpatialConditions::GeometricWindows
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

