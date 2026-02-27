package Biodiverse::SpatialConditions::TextMatch;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

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


1;