package Biodiverse::Indices::Rarity;
use strict;
use warnings;
use 5.020;

our $VERSION = '5.0';

#  we need access to one sub from Endemism.pm,
#  but since we are loaded by Indices.pm
#  there is no need to inherit from it here.
# use parent qw /Biodiverse::Indices::Endemism/;

my $metadata_class = 'Biodiverse::Metadata::Indices';

sub get_metadata_get_label_abundance_hash {
    my $self = shift;

    my %metadata = (
        name            => 'Label abundance hash',
        description     => 'Hash of the label abundances across the basedata',
        type            => 'Rarity',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            label_abundance_hash => {
                description => 'Global label abundance hash',
                type        => 'list',
            },
        }
    );

    return $metadata_class->new(\%metadata);
}

sub get_label_abundance_hash {
    my $self = shift;

    my $bd = $self->get_basedata_ref;

    my %abundance_hash;

    foreach my $label ($bd->get_labels) {
        $abundance_hash{$label} = $bd->get_label_abundance (element => $label);
    }

    my %results = (label_abundance_hash => \%abundance_hash);

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_rarity_central {

    my %metadata = (
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
                description  => 'Corrected weighted rarity',
                lumper       => 0,
                formula      => [
                    '= \frac{RAREC\_WE}{RAREC\_RICHNESS}',
                ],
                distribution => 'unit_interval',
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

    return $metadata_class->new(\%metadata);
}

sub calc_rarity_central {
    my $self = shift;
    my %args = @_;

    #  extract those we want here
    my @keys = qw /RAREC_CWE RAREC_WE RAREC_RICHNESS/;
    my %results = %args{@keys};

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_rarity_central_lists {

    my %metadata = (
        description     => 'Lists used in rarity central calculations',
        name            => 'Rarity central lists',
        type            => 'Rarity',
        pre_calc        => ['_calc_rarity_central'],
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

    return $metadata_class->new(\%metadata);
}

sub calc_rarity_central_lists {
    my $self = shift;
    my %args = @_;

    my %results = (
        RAREC_WTLIST     => $args{RAREC_WTLIST},
        RAREC_RANGELIST  => $args{RAREC_RANGELIST},
    );

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_rarity_central {
    my $self = shift;

    my %metadata = (
        name            => '_calc_rarity_central',
        description     => 'Internal calc for calc_rarity_central',
        pre_calc_global => 'get_label_abundance_hash',
        pre_calc        => 'calc_abc3',
    );

    return $metadata_class->new(\%metadata);
}

sub _calc_rarity_central {
    my $self = shift;
    my %args = @_;

    #  If we have no nbrs in set 2 then we are the same as the "whole" variant.
    #  So just grab its values if it has already been calculated.
    if (!keys %{$args{label_hash2}}) {
        my $cache_hash = $self->get_param('AS_RESULTS_FROM_LOCAL');
        if (my $cached = $cache_hash->{_calc_rarity_whole}) {
            my %remapped;
            foreach my $key (keys %$cached) {
                my $key2 = ($key =~ s/^RAREW/RAREC/r);
                $remapped{$key2} = $cached->{$key};
            }
            return wantarray ? %remapped : \%remapped;
        }
    }

    my %hash = $self->_calc_endemism (
        %args,
        end_central => 1,
        function    => 'get_label_abundance',
        label_range_hash => $args{label_abundance_hash},
    );

    my %hash2;
    foreach my $key (keys %hash) {
        my $key2 = ($key =~ s/^END/RAREC/r);
        $hash2{$key2} = $hash{$key};
    }

    return wantarray ? %hash2 : \%hash2;
}

sub get_metadata_calc_rarity_whole {

    my %metadata = (
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

    return $metadata_class->new(\%metadata);
}

sub calc_rarity_whole {
    my $self = shift;
    my %args = @_;

    #  extract those we want here
    my @keys = qw /RAREW_CWE RAREW_WE RAREW_RICHNESS/;
    my %results = %args{@keys};

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_rarity_whole {
    my $self = shift;

    my %metadata = (
        name            => '_calc_rarity_whole',
        description     => 'Internal calc for calc_rarity_whole',
        pre_calc_global => 'get_label_abundance_hash',
        pre_calc        => 'calc_abc3',
    );

    return $metadata_class->new(\%metadata);
}

sub get_metadata_calc_rarity_whole_lists {

    my %metadata = (
        description     => 'Lists used in rarity whole calculations',
        name            => 'Rarity whole lists',
        type            => 'Rarity',
        pre_calc        => '_calc_rarity_whole',
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

    return $metadata_class->new(\%metadata);
}

sub calc_rarity_whole_lists {
    my $self = shift;
    my %args = @_;

    #my $hashRef = $self->_calc_endemism(%args, end_central => 1);

    my %results = (
        RAREW_WTLIST     => $args{RAREW_WTLIST},
        RAREW_RANGELIST  => $args{RAREW_RANGELIST},
    );

    return wantarray ? %results : \%results;
}

sub _calc_rarity_whole {
    my $self = shift;
    my %args = @_;

    #  If we have no nbrs in set 2 then we are the same as the "whole" variant.
    #  So just grab its values if it has already been calculated.
    if (!keys %{$args{label_hash2}}) {
        my $cache_hash = $self->get_param('AS_RESULTS_FROM_LOCAL');
        if (my $cached = $cache_hash->{_calc_rarity_central}) {
            my %remapped;
            foreach my $key (keys %$cached) {
                my $key2 = ($key =~ s/^RAREC/RAREW/r);
                $remapped{$key2} = $cached->{$key};
            }
            return wantarray ? %remapped : \%remapped;
        }
    }


    my %hash = $self->_calc_endemism (
        %args,
        end_central => 0,
        function    => 'get_label_abundance',
        label_range_hash => $args{label_abundance_hash},
    );

    my %hash2;
    foreach my $key (keys %hash) {
        my $key2 = ($key =~ s/^END/RAREW/r);
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
