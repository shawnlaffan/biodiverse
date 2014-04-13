package Biodiverse::Indices::Rarity;
use strict;
use warnings;

our $VERSION = '0.19';

#  we need access to one sub from Endemism.pm
use parent qw /Biodiverse::Indices::Endemism/;

sub get_metadata_calc_rarity_central {

    my %arguments = (
        description     => "Calculate rarity for species only in neighbour set 1, "
                           . "but with local sample counts calculated from both neighbour sets. \n"
                           . "Uses the same algorithm as the endemism indices but weights "
                           . "by sample counts instead of by groups occupied.",
        name            => 'Rarity central',
        type            => 'Rarity',
        pre_calc        => '_calc_rarity_central',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            RAREC_CWE      => {
                description => 'Corrected weighted rarity',
                lumper      => 0,
                formula     => [
                    '= \frac{RAREC\_WE}{RAREC\_RICHNESS}',
                ],
            },
            RAREC_WE       => {
                description => 'Weighted rarity',
                lumper      => 0,
                formula     => [
                    '= \sum_{t \in T} \frac {s_t} {S_t}',
                    ' where ',
                    't',
                    ' is a label (taxon) in the set of labels (taxa) ',
                    'T',
                    ' across neighbour set 1, ',
                    's_t',
                    ' is sum of the sample counts for ',
                    't',
                    ' across the elements in neighbour sets 1 & 2 '
                      . '(its value in list ABC3_LABELS_ALL), and ',
                    'S_t',
                    ' is the total number of samples across the data set for label ',
                    't',
                    ' (unless the total sample count is specified at import).'
                ],
            },
            RAREC_RICHNESS => {
                description => 'Richness used in RAREC_CWE (same as index RICHNESS_SET1).',
                lumper      => 0,
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_rarity_central {
    my $self = shift;
    my %args = @_;

    #  extract those we want here
    my @keys = qw /RAREC_CWE RAREC_WE RAREC_RICHNESS/;
    my %results;
    @results{@keys} = @args{@keys};

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_rarity_central {
    my $self = shift;

    my %metadata = (
        pre_calc => 'calc_abc3',
    );

    return wantarray ? %metadata : \%metadata;
}

sub get_metadata_calc_rarity_central_lists {

    my %arguments = (
        description     => 'Lists used in rarity central calculations',
        name            => 'Rarity central lists',
        type            => 'Rarity',
        pre_calc        => qw /_calc_rarity_central/,
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            RAREC_WTLIST      => {
                description => 'List of weights for each label used in the'
                                . 'rarity central calculations',
                type => 'list',
                },
            RAREC_RANGELIST   => {
                description => 'List of ranges for each label used in the '
                                . 'rarity central calculations',
                type => 'list',
            },
        },

    );  #  add to if needed

    return wantarray ? %arguments : \%arguments;
}

sub calc_rarity_central_lists {
    my $self = shift;
    my %args = @_;

    #my $hashRef = $self -> _calc_endemism(%args, end_central => 1);

    my %results = (
        RAREC_WTLIST     => $args{RAREC_WTLIST},
        RAREC_RANGELIST  => $args{RAREC_RANGELIST},
    );

    return wantarray ? %results : \%results;
}

sub _calc_rarity_central {
    my $self = shift;
    my %args = @_;

    my %hash = $self -> _calc_endemism (
        %args,
        end_central => 1,
        function    => 'get_label_abundance'
    );

    my %hash2;
    while (my ($key, $value) = each %hash) {
        my $key2 = $key;
        $key2 =~ s/^END/RAREC/;
        $hash2{$key2} = $hash{$key};
    }

    return wantarray ? %hash2 : \%hash2;
}

sub get_metadata_calc_rarity_whole {

    my %arguments = (
        description     => "Calculate rarity using all species in both neighbour sets.\n"
                           . "Uses the same algorithm as the endemism indices but weights \n"
                           . "by sample counts instead of by groups occupied.\n",
        name            => 'Rarity whole',
        type            => 'Rarity',
        pre_calc        => '_calc_rarity_whole',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            RAREW_CWE      => {
                description => 'Corrected weighted rarity',
                formula     => [
                    '= \frac{RAREW\_WE}{RAREW\_RICHNESS}',
                ],
            },
            RAREW_WE       => {
                description => 'Weighted rarity',
                formula     => [
                    '= \sum_{t \in T} \frac {s_t} {S_t}',
                    ' where ',
                    't',
                    ' is a label (taxon) in the set of labels (taxa) ',
                    'T',
                    ' across both neighbour sets, ',
                    's_t',
                    ' is sum of the sample counts for ',
                    't',
                    ' across the elements in neighbour sets 1 & 2 '
                      . '(its value in list ABC3_LABELS_ALL), and ',
                    'S_t',
                    ' is the total number of samples across the data set for label ',
                    't',
                    ' (unless the total sample count is specified at import).'
                ],
            },
            RAREW_RICHNESS => {
                description => 'Richness used in RAREW_CWE (same as index RICHNESS_ALL).',
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_rarity_whole {
    my $self = shift;
    my %args = @_;

    #  extract those we want here
    my @keys = qw /RAREW_CWE RAREW_WE RAREW_RICHNESS/;
    my %results;
    @results{@keys} = @args{@keys};

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_rarity_whole {
    my $self = shift;

    my %metadata = (
        pre_calc => 'calc_abc3',
    );

    return wantarray ? %metadata : \%metadata;
}

sub get_metadata_calc_rarity_whole_lists {

    my %arguments = (
        description     => 'Lists used in rarity whole calculations',
        name            => 'Rarity whole lists',
        type            => 'Rarity',
        pre_calc        => qw /_calc_rarity_whole/,
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            RAREW_WTLIST      => {
                description => 'List of weights for each label used in the'
                                . 'rarity whole calculations',
                type => 'list',
                },
            RAREW_RANGELIST   => {
                description => 'List of ranges for each label used in the '
                                . 'rarity whole calculations',
                type => 'list',
            },
        },

    );  #  add to if needed

    return wantarray ? %arguments : \%arguments;
}

sub calc_rarity_whole_lists {
    my $self = shift;
    my %args = @_;

    #my $hashRef = $self -> _calc_endemism(%args, end_central => 1);

    my %results = (
        RAREW_WTLIST     => $args{RAREW_WTLIST},
        RAREW_RANGELIST  => $args{RAREW_RANGELIST},
    );

    return wantarray ? %results : \%results;
}

sub _calc_rarity_whole {
    my $self = shift;
    my %args = @_;

    my %hash = $self -> _calc_endemism (
        %args,
        end_central => 0,
        function    => 'get_label_abundance'
    );

    my %hash2;
    while (my ($key, $value) = each %hash) {
        my $key2 = $key;
        $key2 =~ s/^END/RAREW/;
        $hash2{$key2} = $hash{$key};
    }

    return wantarray ? %hash2 : \%hash2;
}

1;

__END__

=head1 NAME

Biodiverse::Indices::Rarity

=head1 SYNOPSIS

  use Biodiverse::Indices;

=head1 DESCRIPTION

Rarity indices for the Biodiverse system.
It is inherited by Biodiverse::Indices and not to be used on it own.


=head1 METHODS

=over

=item INSERT METHODS

=back

=head1 REPORTING ERRORS

Use the issue tracker at http://www.purl.org/biodiverse

=head1 COPYRIGHT

Copyright (c) 2010 Shawn Laffan. All rights reserved.  

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut
