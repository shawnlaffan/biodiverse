#  Phylogenetic indices
#  A plugin for the biodiverse system and not to be used on its own.
package BiodiverseX::Indices::Phylogenetic;
use 5.020;
use strict;
use warnings;

use English qw /-no_match_vars/;
use Carp;

use Biodiverse::Progress;

use List::Util 1.33 qw /any sum min max/;
use Scalar::Util qw /blessed/;

our $VERSION = '4.99_011';


my $metadata_class = 'Biodiverse::Metadata::Indices';


sub get_metadata_calc_taxonomic_distinctness {
    my $self = shift;

    my $indices = {
        TD_DISTINCTNESS => {
            description    => 'Taxonomic distinctness',
            #formula        => [],
        },
        TD_DENOMINATOR  => {
            description    => 'Denominator from TD_DISTINCTNESS calcs',
        },
        TD_NUMERATOR    => {
            description    => 'Numerator from TD_DISTINCTNESS calcs',
        },
        TD_VARIATION    => {
            description    => 'Variation of the taxonomic distinctness',
            #formula        => [],
        },
    };
    
    my $ref = 'Warwick & Clarke (1995) Mar Ecol Progr Ser. '
            . 'https://doi.org/10.3354/meps129301 ; '
            . 'Clarke & Warwick (2001) Mar Ecol Progr Ser. '
            . 'https://doi.org/10.3354/meps216265';
    
    my %metadata = (
        description     => 'Taxonomic/phylogenetic distinctness and variation. '
                         . 'THIS IS A BETA LEVEL IMPLEMENTATION.',
        name            => 'Taxonomic/phylogenetic distinctness',
        type            => 'Taxonomic Distinctness Indices',
        reference       => $ref,
        pre_calc        => ['calc_abc3'],
        pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => $indices,
    );

    return $metadata_class->new(\%metadata);
}

#  sample count weighted version
sub calc_taxonomic_distinctness {
    my $self = shift;
    
    return $self->_calc_taxonomic_distinctness (@_);
}


sub get_metadata_calc_taxonomic_distinctness_binary {
    my $self = shift;

    my $indices = {
        TDB_DISTINCTNESS => {
            description    => 'Taxonomic distinctness, binary weighted',
            formula        => [
                '= \frac{\sum \sum_{i \neq j} \omega_{ij}}{s(s-1)}',
                'where ',
                '\omega_{ij}',
                'is the path length from label ',
                'i',
                'to the ancestor node shared with ',
                'j',
            ],
        },
        TDB_DENOMINATOR  => {
            description    => 'Denominator from TDB_DISTINCTNESS',
        },
        TDB_NUMERATOR    => {
            description    => 'Numerator from TDB_DISTINCTNESS',
        },
        TDB_VARIATION    => {
            description    => 'Variation of the binary taxonomic distinctness',
            formula        => [
                '= \frac{\sum \sum_{i \neq j} \omega_{ij}^2}{s(s-1)} - \bar{\omega}^2',
                'where ',
                '\bar{\omega} = \frac{\sum \sum_{i \neq j} \omega_{ij}}{s(s-1)} \equiv TDB\_DISTINCTNESS',
            ],
        },
    };

    my $ref = 'Warwick & Clarke (1995) Mar Ecol Progr Ser. '
            . 'https://doi.org/10.3354/meps129301 ; '
            . 'Clarke & Warwick (2001) Mar Ecol Progr Ser. '
            . 'https://doi.org/10.3354/meps216265';

    my %metadata = (
        description     => 'Taxonomic/phylogenetic distinctness and variation '
                         . 'using presence/absence weights.  '
                         . 'THIS IS A BETA LEVEL IMPLEMENTATION.',
        name            => 'Taxonomic/phylogenetic distinctness, binary weighted',
        type            => 'Taxonomic Distinctness Indices',
        reference       => $ref,
        pre_calc        => ['calc_abc'],
        pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => $indices,
    );

    return $metadata_class->new(\%metadata);
}

#  sample count weighted version
sub calc_taxonomic_distinctness_binary {
    my $self = shift;
    
    my %results = $self->_calc_taxonomic_distinctness (@_);
    my %results2;
    foreach my $key (keys %results) {
        my $key2 = $key;
        $key2 =~ s/^TD_/TDB_/;
        $results2{$key2} = $results{$key};
    }
    
    return wantarray ? %results2 : \%results2;
}

sub _calc_taxonomic_distinctness {
    my $self = shift;
    my %args = @_;

    my $label_hash = $args{label_hash_all};
    my $tree = $args{trimmed_tree};

    my $numerator;
    my $denominator = 0;
    my $ssq_wtd_value;
    my @labels = sort keys %$label_hash;
    
    #  Need to loop over each label and get the weighted contribution
    #  for each level of the tree.
    #  The weight for each comparison is the distance along the tree to
    #  the shared ancestor.

    #  We should use the distance from node a to b to avoid doubled comparisons
    #  and use get_path_to_node for the full path length.
    #  We can pop from @labels as we go to achieve this
    #  (this is the i<j constraint from Warwick & Clarke, but used in reverse)
    
    #  Actually, it's simpler to loop over the list twice and get the lengths to shared ancestor


    BY_LABEL:
    foreach my $label (@labels) {
        my $label_count1 = $label_hash->{$label};

        #  save some calcs (if ever this happens)
        next BY_LABEL if $label_count1 == 0;

        my $node = $tree->get_node_ref (node => $label);

        LABEL2:
        foreach my $label2 (@labels) {

            #  skip same labels
            next LABEL2 if $label eq $label2;

            my $label_count2 = $label_hash->{$label2};
            next LABEL2 if $label_count2 == 0;

            my $node2 = $tree->get_node_ref (node => $label2);

            my $ancestor = $node->get_shared_ancestor (node => $node2);

            my $path_length = $ancestor->get_total_length
                            - $node2->get_total_length;

            my $weight = $label_count1 * $label_count2;

            my $wtd_value = $path_length * $weight;

            $numerator     += $wtd_value;
            $ssq_wtd_value += $wtd_value ** 2;
            $denominator   += $weight;
        }
    }

    my $distinctness;
    my $variance;

    {
        no warnings 'uninitialized';
        $distinctness  = eval {$numerator / $denominator};
        $variance = eval {$ssq_wtd_value / $denominator - $distinctness ** 2}
    }

    my %results = (
        TD_DISTINCTNESS => $distinctness,
        TD_DENOMINATOR  => $denominator,
        TD_NUMERATOR    => $numerator,
        TD_VARIATION    => $variance,
    );


    return wantarray ? %results : \%results;
}

1;

