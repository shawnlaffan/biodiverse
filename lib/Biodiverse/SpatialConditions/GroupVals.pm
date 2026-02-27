package Biodiverse::SpatialConditions::GroupVals;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use Carp;
use English qw /-no_match_vars/;

my $NULL_STRING = q{};

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