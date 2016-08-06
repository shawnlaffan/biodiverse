package Biodiverse::Indices::Indices;
use strict;
use warnings;
use 5.010;

use Carp;

use Scalar::Util qw /blessed weaken reftype/;
use List::Util 1.39 qw /min max pairs pairkeys sum/;
use English ( -no_match_vars );
use Readonly;

our $VERSION = '1.99_004';

use Biodiverse::Statistics;
my $stats_class = 'Biodiverse::Statistics';

my $metadata_class = 'Biodiverse::Metadata::Indices';

Readonly my $RE_ABC_REQUIRED_ARGS => qr /(?:element_list|(?:label_)(?:hash|list))[12]/;

###########################################
#  test/debug methods
#sub get_metadata_debug_print_nothing {
#    my %metadata = (
#        pre_calc_global => 'get_iei_element_cache',
#    );
#    
#    return $metadata_class->new(\%metadata);
#}
#
#sub debug_print_nothing {
#    my $self = shift;
#    my $count = $self -> get_param_as_ref ('DEBUG_PRINT_NOTHING_COUNT');
#    if (not defined $count) {
#        my $x = 0;
#        $count = \$x;
#        $self -> set_param ('DEBUG_PRINT_NOTHING_COUNT' => $count);
#    };
#
#    print "$$count\n";
#    $$count ++;
#    
#    return wantarray ? () : {};
#}

#####################################
#
#    methods to actually calculate the indices
#    these should be hived off to their own packages by type
#    unless they are utility subs




sub get_metadata_calc_richness {

    my %metadata = (
        name            => 'Richness',
        description     => 'Count the number of labels in the neighbour sets',
        type            => 'Lists and Counts',
        pre_calc        => 'calc_abc',
        uses_nbr_lists  => 1,  #  how many sets of neighbour lists it must have
        indices         => {
            RICHNESS_ALL    => {
                description     => 'for both sets of neighbours'
            },
            RICHNESS_SET1   => {
                description     => 'for neighbour set 1',
                lumper          => 0,
            },
            RICHNESS_SET2   => {
                description     => 'for neighbour set 2',
                uses_nbr_lists  => 2,
                lumper          => 0,
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_richness {  #  calculate the aggregate richness for a set of elements
    my $self = shift;
    my %args = @_;  #  rest of args into a hash

    my %results = (RICHNESS_ALL => $args{ABC},
                   RICHNESS_SET1 => $args{A} + $args{B},
                   RICHNESS_SET2 => $args{A} + $args{C},
                  );

    return wantarray
        ? (%results)
        : \%results;
}

sub get_metadata_calc_redundancy {

    my %metadata = (
        name            => "Redundancy",
        description     => "Ratio of labels to samples.\n"
                         . "Values close to 1 are well sampled while zero means \n"
                         . "there is no redundancy in the sampling\n",
        formula         => ['= 1 - \frac{richness}{sum\ of\ the\ sample\ counts}', q{}],
        type            => 'Lists and Counts',
        pre_calc        => 'calc_abc3',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        reference       => 'Garcillan et al. (2003) J Veget. Sci. '
                         . 'http://dx.doi.org/10.1111/j.1654-1103.2003.tb02174.x',
        indices         => {
            REDUNDANCY_ALL  => {
                description     => 'for both neighbour sets',
                lumper          => 1,
                formula         => [
                    '= 1 - \frac{RICHNESS\_ALL}{ABC3\_SUM\_ALL}',
                    q{},
                ],
            },
            REDUNDANCY_SET1 => {
                description     => 'for neighour set 1',
                lumper          => 0,
                formula         => [
                    '= 1 - \frac{RICHNESS\_SET1}{ABC3\_SUM\_SET1}',
                    q{},
                ],
            },
            REDUNDANCY_SET2 => {
                description     => 'for neighour set 2',
                lumper          => 0,
                formula         => [
                    '= 1 - \frac{RICHNESS\_SET2}{ABC3\_SUM\_SET2}',
                    q{},
                ],
                uses_nbr_lists  => 2,
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_redundancy {  #  calculate the sample redundancy for a set of elements
    my $self = shift;
    my %ABC = @_;  #  rest of args into a hash

    my $label_list_all = $ABC{label_hash_all};
    my $label_list1 = $ABC{label_hash1};
    my $label_list2 = $ABC{label_hash2};
    my $label_count_all   = keys %{$label_list_all};
    my $label_count_inner = keys %{$label_list1};
    my $label_count_outer = keys %{$label_list2};
    my ($sample_count_all, $sample_count_inner, $sample_count_outer);

    foreach my $sub_label (keys %{$label_list_all}) {
        $sample_count_all += $label_list_all->{$sub_label};
        $sample_count_inner += $label_list1->{$sub_label} if exists $label_list1->{$sub_label};
        $sample_count_outer += $label_list2->{$sub_label} if exists $label_list2->{$sub_label};
    }

    my %results;
    {
        no warnings qw /uninitialized numeric/;  #  avoid these warnings
        $results{REDUNDANCY_ALL} = eval {
            1 - ($label_count_all / $sample_count_all)
        };
        $results{REDUNDANCY_SET1} = eval {
            1 - ($label_count_inner / $sample_count_inner)
        };
        $results{REDUNDANCY_SET2} = eval {
            1 - ($label_count_outer / $sample_count_outer)
        };
    }

    return wantarray
        ? %results
        : \%results;
}


sub get_metadata_is_dissimilarity_valid {
    my $self = shift;
    
    my %metadata = (
        name            => 'Dissimilarity is valid',
        description     => 'Check if the dissimilarity analyses will produce valid results',
        indices         => {
            DISSIMILARITY_IS_VALID  => {
                description => 'Dissimilarity validity check',
            }
        },
        type            => 'Taxonomic Dissimilarity and Comparison',
        pre_calc        => 'calc_abc',
    );

    return $metadata_class->new(\%metadata);
}

sub is_dissimilarity_valid {
    my $self = shift;
    my %args = @_;

    my %result = (
        DISSIMILARITY_IS_VALID => ($args{A} || ($args{B} && $args{C})),
    );

    return wantarray ? %result : \%result;
}

#  for the formula metadata
sub get_formula_explanation_ABC {
    my $self = shift;
    
    my @explanation = (
        ' where ',
        'A',
        'is the count of labels found in both neighbour sets, ',
        'B',
        ' is the count unique to neighbour set 1, and ',
        'C',
        ' is the count unique to neighbour set 2. '
        . q{Use the 'Label counts' calculation to derive these directly.},
    );
    
    return wantarray ? @explanation : \@explanation;
}

#  off for now - k1 index can go negative so we don't want it for clustering
#sub get_metadata_calc_kulczynski1 {
#    my $self = shift;
#
#    my %metadata = (
#        name            => 'Kulczynski 1',
#        description     => "Kulczynski 1 dissimilarity between two sets of labels.\n",
#        formula         => [
#             '= 1 - \frac{A}{B + C}',
#            $self -> get_formula_explanation_ABC,
#        ],
#        indices         => {
#            KULCZYNSKI1      => {
#                cluster     => 1,
#                description => 'Kulczynski 1 index',
#            }
#        },
#        type            => 'Taxonomic Dissimilarity and Comparison',
#        pre_calc        => [qw /calc_abc is_dissimilarity_valid/],
#        uses_nbr_lists  => 2,
#    );
#
#    return $metadata_class->new(\%metadata);
#}
#
#sub calc_kulczynski1 {
#    my $self = shift;
#    my %args = @_;
#
#    my $value = $args{DISSIMILARITY_IS_VALID}
#        ? eval {1 - $args{A} / ($args{B} + $args{C})}
#        : undef;
#
#    my %result = (KULCZYNSKI1 => $value);
#
#    return wantarray ? %result : \%result;
#}

sub get_metadata_calc_kulczynski2 {
    my $self = shift;

    my %metadata = (
        name            => 'Kulczynski 2',
        description     => "Kulczynski 2 dissimilarity between two sets of labels.\n",
        formula         => [
            '= 1 - 0.5 * (\frac{A}{A + B} + \frac{A}{A + C})',
            $self -> get_formula_explanation_ABC,
        ],
        indices         => {
            KULCZYNSKI2      => {
                cluster     => 1,
                description => 'Kulczynski 2 index',
            }
        },
        type            => 'Taxonomic Dissimilarity and Comparison',
        pre_calc        => [qw /calc_abc is_dissimilarity_valid/],
        uses_nbr_lists  => 2,
    );

    return $metadata_class->new(\%metadata);
}

sub calc_kulczynski2 {
    my $self = shift;
    my %args = @_;

    my $value;
    if ($args{DISSIMILARITY_IS_VALID}) {
        my ($a, $b, $c) = @args{'A', 'B', 'C'};
        $value = eval {
            1 - 0.5 * ($a / ($a + $b) + $a / ($a + $c));
        };
    }

    my %result = (KULCZYNSKI2 => $value);

    return wantarray ? %result : \%result;
}


sub get_metadata_calc_sorenson {
    my $self = shift;

    my %metadata = (
        name            => 'Sorenson',
        description     => "Sorenson dissimilarity between two sets of labels.\n"
                         . "It is the complement of the (unimplemented) "
                         . "Czechanowski index, and numerically the same as Whittaker's beta.",
        formula         => [
            '= 1 - \frac{2A}{2A + B + C}',
            $self -> get_formula_explanation_ABC,
        ],
        indices         => {
            SORENSON      => {
                cluster     => 1,
                description => 'Sorenson index',
            }
        },
        type            => 'Taxonomic Dissimilarity and Comparison',
        pre_calc        => [qw /calc_abc is_dissimilarity_valid/],
        uses_nbr_lists  => 2,
    );

    return $metadata_class->new(\%metadata);
}

# calculate the Sorenson dissimilarity index between two lists (1 - Czechanowski)
#  = 2a/(2a+b+c) where a is shared presence between groups, b&c are in one group only
sub calc_sorenson {
    my $self = shift;
    my %args = @_;

    my $value = $args{DISSIMILARITY_IS_VALID}
                ? eval {1 - ((2 * $args{A}) / ($args{A} + $args{ABC}))}
                : undef;

    my %result = (SORENSON => $value);

    return wantarray ? %result : \%result;
}


sub get_metadata_calc_jaccard {
    my $self = shift;

    my %metadata = (
        name            => 'Jaccard',
        description     => 'Jaccard dissimilarity between the labels in neighbour sets 1 and 2.',
        type            => 'Taxonomic Dissimilarity and Comparison',
        uses_nbr_lists  => 2,  #  how many sets of lists it must have
        pre_calc        => [qw /calc_abc is_dissimilarity_valid/],
        formula         => [
            '= 1 - \frac{A}{A + B + C}',
            $self -> get_formula_explanation_ABC,
        ],
        indices         => {
            JACCARD       => {
                cluster     => 1,
                description => 'Jaccard value, 0 is identical, 1 is completely dissimilar',
                
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

#  calculate the Jaccard dissimilarity index between two label lists.
#  J = a/(a+b+c) where a is shared presence between groups, b&c are in one group only
#  this is almost identical to calc_sorenson    
sub calc_jaccard {    
    my $self = shift;
    my %args = @_;

    my $value = $args{DISSIMILARITY_IS_VALID}
                ? eval {1 - ($args{A} / $args{ABC})}
                : undef;

    my %result = (JACCARD => $value);

    return wantarray ? %result : \%result;
}


##  fager index - not ready yet - probably needs to run over multiple nbr sets
#sub get_metadata_calc_fager {
#    my $self = shift;
#    
#    my $formula = [
#        '= 1 - \frac{A}{\sqrt {(A + B)(A + C)}} '
#        . '- \frac {1} {2 \sqrt {max [(A + B), (A + C)]}}',
#        $self -> get_formula_explanation_ABC,
#    ];
#
#    my $ref = 'Hayes, W.B. (1978) http://dx.doi.org/10.2307/1936649, '
#              . 'McKenna (2003) http://dx.doi.org/10.1016/S1364-8152(02)00094-4';
#    
#    my %metadata = (
#        name           => 'Fager',
#        description    => "Fager dissimilarity between two sets of labels\n",
#        type           => 'Taxonomic Dissimilarity and Comparison',
#        uses_nbr_lists => 2,  #  how many sets of lists it must have
#        pre_calc       => 'calc_abc',
#        formula        => $formula,
#        reference      => $ref,
#        indices => {
#            FAGER => {
#                #cluster     => 1,
#                description => 'Fager index',
#            }
#        },
#    );
#    
#    return $metadata_class->new(\%metadata);
#}

#sub calc_fager {
#    my $self = shift;
#    my %abc = @_;
#
#    if ($abc{get_args}) {
#    
#    my ($A, $B, $C) = @abc{qw /A B C/};
#    
#    my $value = eval {
#        ($A / sqrt (($A + $B) * ($A + $C))
#        - (1 / (2 * sqrt (max ($A + $B, $A + $C)))))
#    };
#
#    return wantarray
#            ? (FAGER => $value)
#            : {FAGER => $value};
#
#}

sub get_metadata_calc_nestedness_resultant {
    my $self = shift;
    
    my %metadata = (
        name            => 'Nestedness-resultant',
        description     => 'Nestedness-resultant index between the '
                            . 'labels in neighbour sets 1 and 2. ',
        type            => 'Taxonomic Dissimilarity and Comparison',
        uses_nbr_lists  => 2,  #  how many sets of lists it must have
        reference       => 'Baselga (2010) Glob Ecol Biogeog.  '
                           . 'http://dx.doi.org/10.1111/j.1466-8238.2009.00490.x',
        pre_calc        => [qw /calc_abc/],
        formula         => [
            '=\frac{ \left | B - C \right | }{ 2A + B + C } '
            . '\times \frac { A }{ A + min (B, C) }'
            . '= SORENSON - S2',
            $self -> get_formula_explanation_ABC,
        ],
        indices         => {
            NEST_RESULTANT  => {
                cluster     => 1,
                description => 'Nestedness-resultant index',
            }
        },
    );

    return $metadata_class->new(\%metadata);    
}

#  nestedness-resultant dissimilarity
#  from Baselga (2010) http://dx.doi.org/10.1111/j.1466-8238.2009.00490.x
sub calc_nestedness_resultant {
    my $self = shift;
    my %args = @_;
    
    my ($A, $B, $C, $ABC) = @args{qw /A B C ABC/};
    
    my $score;
    if (!$A && $B && $C) {
        #  nothing in common, no nestedness
        $score = 0;
    }
    elsif (!$A && ! ($B && $C)) {  #  could be re-arranged
        #  only one set has labels (possibly neither)
        $score = undef;
    }
    else {
        my $part1 = eval {abs ($B - $C) / ($A + $ABC)};
        my $part2 = eval {$A / ($A + min ($B, $C))};
        $score = eval {$part1 * $part2};
    }

    my %results     = (
        NEST_RESULTANT => $score,
    );
    
    return wantarray ? %results : \%results;
}


sub get_metadata_calc_bray_curtis {

    my %metadata = (
        name            => 'Bray-Curtis non-metric',
        description     => "Bray-Curtis dissimilarity between two sets of labels.\n"
                         . "Reduces to the Sorenson metric for binary data (where sample counts are 1 or 0).",
        type            => 'Taxonomic Dissimilarity and Comparison',
        uses_nbr_lists  => 2,  #  how many sets of lists it must have
        pre_calc        => 'calc_abc3',
        #formula     => "= 1 - (2 * W / (A + B))\n"
        #             . "where A is the sum of the samples in set 1, B is the sum of samples at set 2,\n"
        #             . "and W is the sum of the minimum sample count for each label across both sets",
        formula     => [
            '= 1 - \frac{2W}{A + B}',
            'where ',
            'A',
            ' is the sum of the sample counts in neighbour set 1, ',
            'B',
            ' is the sum of sample counts in neighbour set 2, and ',
            'W=\sum^n_{i=1} min(sample\_count\_label_{i_{set1}},sample\_count\_label_{i_{set2}})',
            ' (meaning it sums the minimum of the sample counts for each of the ',
            'n',
            ' labels across the two neighbour sets), ',
        ],
        indices         => {
            BRAY_CURTIS  => {
                cluster     => 1,
                description => 'Bray Curtis dissimilarity',
                lumper      => 0,
            },
            BC_A => {
                description => 'The A factor used in calculations (see formula)',
                lumper      => 0,
            },
            BC_B => {
                description => 'The B factor used in calculations (see formula)',
                lumper      => 0,
            },
            BC_W => {
                description => 'The W factor used in calculations (see formula)',
                lumper      => 1,
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

# calculate the Bray-Curtis dissimilarity index between two label lists.
sub calc_bray_curtis {  
    my $self = shift;
    my %args = @_;

    #  make copies of the label hashes so we don't mess things
    #  up with auto-vivification
    my %l1 = %{$args{label_hash1}};
    my %l2 = %{$args{label_hash2}};
    #my %labels = (%l1, %l2);
    my $labels_all = $args{label_hash_all};

    my ($A, $B, $W) = (0, 0, 0);
    foreach my $label (keys %$labels_all) {
        #  treat undef as zero, and don't complain
        no warnings 'uninitialized';

        #  $W is the sum of mins
        $W += $l1{$label} < $l2{$label} ? $l1{$label} : $l2{$label};  
        $A += $l1{$label};
        $B += $l2{$label};
    }

    my %results = (
        BRAY_CURTIS => eval {1 - (2 * $W / ($A + $B))},
        BC_A => $A,
        BC_B => $B,
        BC_W => $W,
    );

    return wantarray
            ? %results
            : \%results;
}

sub get_metadata_calc_bray_curtis_norm_by_gp_counts {
    my $self = shift;
    
    my $description = <<END_BCN_DESCR
Bray-Curtis dissimilarity between two neighbourhoods, 
where the counts in each neighbourhood are divided 
by the number of groups in each neighbourhood to correct
for unbalanced sizes.
END_BCN_DESCR
;

    my %metadata = (
        name            => 'Bray-Curtis non-metric, group count normalised',
        description     => $description,
        type            => 'Taxonomic Dissimilarity and Comparison',
        uses_nbr_lists  => 2,  #  how many sets of lists it must have
        pre_calc        => [qw/calc_abc3 calc_elements_used/],
        formula     => [
            '= 1 - \frac{2W}{A + B}',
            'where ',
            'A',
            ' is the sum of the sample counts in neighbour set 1 normalised '
            . '(divided) by the number of groups, ',
            'B',
            ' is the sum of the sample counts in neighbour set 2 normalised '
            . 'by the number of groups, and ',
            'W = \sum^n_{i=1} min(sample\_count\_label_{i_{set1}},sample\_count\_label_{i_{set2}})',
            ' (meaning it sums the minimum of the normalised sample counts for each of the ',
            'n',
            ' labels across the two neighbour sets), ',
        ],
        indices         => {
            BRAY_CURTIS_NORM  => {
                cluster     => 1,
                description => 'Bray Curtis dissimilarity normalised by groups',
            },
            BCN_A => {
                description => 'The A factor used in calculations (see formula)',
                lumper      => 0,
            },
            BCN_B => {
                description => 'The B factor used in calculations (see formula)',
                lumper      => 0,
            },
            BCN_W => {
                description => 'The W factor used in calculations (see formula)',
                lumper      => 1,
            },
        },

    );

    return $metadata_class->new(\%metadata);
}

sub calc_bray_curtis_norm_by_gp_counts {
    my $self = shift;
    my %args = @_;

    #  make copies of the label hashes so we don't mess things
    #  up with auto-vivification
    my %l1 = %{$args{label_hash1}};
    my %l2 = %{$args{label_hash2}};
    #my %labels = (%l1, %l2);
    my $labels_all = $args{label_hash_all};

    my $counts1 = $args{EL_COUNT_SET1};
    my $counts2 = $args{EL_COUNT_SET2};

    my ($A, $B, $W) = (0, 0, 0);
    foreach my $label (keys %$labels_all) {
        #  treat undef as zero, and don't complain
        no warnings 'uninitialized';

        my $l1_wt = eval { $l1{$label} / $counts1 };
        my $l2_wt = eval { $l2{$label} / $counts2 };

        #  $W is the sum of mins
        $W += $l1_wt < $l2_wt ? $l1_wt : $l2_wt;  
        $A += $l1_wt;
        $B += $l2_wt;
    }

    my $BCN = eval {1 - (2 * $W / ($A + $B))};
    my %results = (
        BRAY_CURTIS_NORM => $BCN,
        BCN_A => $A,
        BCN_B => $B,
        BCN_W => $W,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_beta_diversity {
    my $self = shift;

    my %metadata = (
        name            => 'Beta diversity',
        description     => "Beta diversity between neighbour sets 1 and 2.\n",
        indices         => {
            BETA_2 => {
                cluster     => 1,
                description => 'The other beta',
                formula         => [  #'ABC / ((A+B + A+C) / 2) - 1'
                    '= \frac{A + B + C}{max((A+B), (A+C))} - 1',
                    $self -> get_formula_explanation_ABC,
                ],
                #formula     => 'ABC / max (A+B, A+C) - 1',
            },
        },
        type            => 'Taxonomic Dissimilarity and Comparison',
        uses_nbr_lists  => 2,  #  how many sets of lists it must have
        pre_calc        => 'calc_abc',
    );

    return $metadata_class->new(\%metadata);
}

# calculate the beta diversity dissimilarity index between two label lists.
sub calc_beta_diversity {  
    my $self = shift;
    my %abc = @_;

    no warnings 'numeric';

    my $beta_2 = eval {
        $abc{ABC} / max ($abc{A} + $abc{B}, $abc{A} + $abc{C}) - 1
    };
    my %results = (
        BETA_2 => $beta_2,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_s2 {
    my $self = shift;

    my %metadata = (
        name            => 'S2',
        type            => 'Taxonomic Dissimilarity and Comparison',
        description     => "S2 dissimilarity between two sets of labels\n",
        pre_calc        => 'calc_abc',
        uses_nbr_lists  => 2,  #  how many sets of lists it must have
        reference   => 'Lennon et al. (2001) J Animal Ecol.  '
                        . 'http://dx.doi.org/10.1046/j.0021-8790.2001.00563.x',
        formula     => [
            '= 1 - \frac{A}{A + min(B, C)}',
            $self -> get_formula_explanation_ABC,
        ],
        indices         => {
            S2 => {
                cluster     => 1,
                description => 'S2 dissimilarity index',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_s2 {  #  Used to calculate the species turnover between two element sets.
              #  This is a subcomponent of the species turnover index of
                    #    Lennon, J.J., Koleff, P., Greenwood, J.J.D. & Gaston, K.J. (2001)
                    #    The geographical structure of British bird distributions:
                    #    diversity, spatial turnover and scale.
                    #    Journal of Animal Ecology, 70, 966-979
                    #
    my $self = shift;
    my %args = @_;

    no warnings 'uninitialized';
    my $value = $args{ABC}
                ? eval { 1 - ($args{A} / ($args{A} + min ($args{B}, $args{C}))) }
                : undef;

    return wantarray
        ? (S2 => $value)
        : {S2 => $value};

}

sub get_metadata_calc_simpson_shannon {
    my $self = shift;

    my %metadata = (
        name            => 'Simpson and Shannon',
        description     => "Simpson and Shannon diversity metrics using samples from all neighbourhoods.\n",
        formula         => [
            undef,
            'For each index formula, ',
            'p_i',
            q{is the number of samples of the i'th label as a proportion }
             . q{of the total number of samples },
            'n',
            q{in the neighbourhoods.}
        ],
        type            => 'Taxonomic Dissimilarity and Comparison',
        pre_calc        => 'calc_abc3',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            SIMPSON_D       => {
                description => q{Simpson's D. A score of zero is more similar.},
                formula     => ['D = 1 - \sum^n_{i=1} p_i^2'],
            },
            SHANNON_H       => {
                description => q{Shannon's H},
                formula     => ['H = - \sum^n_{i=1} (p_i \cdot ln (p_i))'],
            },
            SHANNON_HMAX    => {
                description => q{maximum possible value of Shannon's H},
                formula     => ['HMAX = ln(richness)'],
            },
            SHANNON_E       => {
                description => q{Shannon's evenness (H / HMAX)},
                formula     => ['Evenness = \frac{H}{HMAX}'],
            },
        },    
    );

    return $metadata_class->new(\%metadata);
}

#  calculate the simpson and shannon indices
sub calc_simpson_shannon {
    my $self = shift;
    my %args = @_;

    my $labels   = $args{label_hash_all};
    my $richness = $args{ABC};

    my %results;

    if ($richness) {  #  results not valid if cells are empty
        my $n = sum 0, values %$labels;
    
        my ($simpson_d, $shannon_h, $sum_labels, $shannon_e);
        foreach my $value (values %$labels) {  #  don't need the labels, so don't use keys
            my $p_i     = $value / $n;
            $simpson_d += $p_i ** 2;
            $shannon_h += $p_i * log ($p_i);
        }
        $shannon_h *= -1;
        #$simpson_d /= $richness ** 2;
        #  trap divide by zero when sum_labels == 1
        my $shannon_hmax = log ($richness);
        $shannon_e = $shannon_hmax == 0
            ? undef
            : $shannon_h / $shannon_hmax;
    
        %results = (
            SHANNON_H    => $shannon_h,
            SHANNON_HMAX => $shannon_hmax,
            SHANNON_E    => $shannon_e,
            SIMPSON_D    => 1 - $simpson_d,
        );
    }
    else {
        @results{qw /SHANNON_H SHANNON_HMAX SHANNON_E SIMPSON_D/} = undef;
    }

    return wantarray ? %results : \%results;
}


sub get_formula_qe {
    my $self = shift;
    
    my @formula = (
        '= \sum_{i \in L} \sum_{j \in L} d_{ij} p_i p_j',
        ' where ',
        'p_i',
        ' and ',
        'p_j',
        q{ are the sample counts for the i'th and j'th labels, },
    );
    
    return wantarray ? @formula : \@formula;
}

sub get_metadata_calc_tx_rao_qe {
    my $self = shift;

    my %metadata = (
        name            => q{Rao's quadratic entropy, taxonomically weighted},
        description     => "Calculate Rao's quadratic entropy for a taxonomic weights scheme.\n"
                         . "Should collapse to be the Simpson index for presence/absence data.",
        type            => 'Taxonomic Dissimilarity and Comparison',
        pre_calc        => 'calc_abc3',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        formula         => [
            $self -> get_formula_qe,
            'd_{ij}',
            ' is a value of zero if ',
            'i = j',
            ', and a value of 1 otherwise. ',
            'L',
            ' is the set of labels across both neighbour sets.',
        ],
        indices => {
            TX_RAO_QE       => {
                description => 'Taxonomically weighted quadratic entropy',
            },
            TX_RAO_TN       => {
                description => 'Count of comparisons used to calculate TX_RAO_QE',
            },
            TX_RAO_TLABELS  => {
                description => 'List of labels and values used in the TX_RAO_QE calculations',
                type        => 'list',
            },
        },
    );  #  add to if needed

    return $metadata_class->new(\%metadata);
}

sub calc_tx_rao_qe {
    my $self = shift;
    my %args = @_;

    my $r = $self -> _calc_rao_qe (@_, use_matrix => 0);
    my %results = (
        TX_RAO_TN        => $r->{RAO_TN},
        TX_RAO_TLABELS   => $r->{RAO_TLABELS},
        TX_RAO_QE        => $r->{RAO_QE},
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_mx_rao_qe {
    my $self = shift;

    my %metadata = (
        name            => q{Rao's quadratic entropy, matrix weighted},
        description     => qq{Calculate Rao's quadratic entropy for a matrix weights scheme.\n}
                         .  q{BaseData labels not in the matrix are ignored},
        type            => 'Matrix',
        pre_calc        => 'calc_abc3',
        required_args   => ['matrix_ref'],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        formula     => [
            $self -> get_formula_qe,
            'd_{ij}',
            ' is the matrix value for the pair of labels ',
            'ij',
            ' and ',
            'L',
            ' is the set of labels across both neighbour sets that occur in the matrix.',
        ],
        indices         => {
            MX_RAO_QE       => {
                description => 'Matrix weighted quadratic entropy',
            },
            MX_RAO_TN       => {description => 'Count of comparisons used to calculate MX_RAO_QE'},
            MX_RAO_TLABELS  => {
                description => 'List of labels and values used in the MX_RAO_QE calculations',
                type => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_mx_rao_qe {
    my $self = shift;
    my %args = @_;

    my $r = $self -> _calc_rao_qe (@_, use_matrix => 1);
    my %results = (MX_RAO_TN        => $r->{RAO_TN},
                   MX_RAO_TLABELS   => $r->{RAO_TLABELS},
                   MX_RAO_QE        => $r->{RAO_QE},
                   );

    return wantarray ? %results : \%results;
}

sub _calc_rao_qe {  #  calculate Rao's Quadratic entropy with or without a matrix
    my $self = shift;
    my %args = @_;  #  rest of args into a hash

    my $use_matrix = $args{use_matrix};  #  boolean variable
    my $self_similarity = $args{self_similarity} || 0;

    my $full_label_list = $args{label_hash_all};

    my $matrix;
    if ($use_matrix) {
        $matrix = $args{matrix_ref};
        if (! defined $matrix) {
            return wantarray ? (MX_RAO_QE => undef) : {MX_RAO_QE => undef};
        }

        #  don't want elements from full_label_list that are not in the matrix 
        my $labels_in_matrix = $matrix -> get_elements;
        my $labels_in_mx_and_full_list = $self -> get_list_intersection (
            list1 => [keys %$labels_in_matrix],
            list2 => [keys %$full_label_list],
        );

        $full_label_list = {};  #  clear it
        @{$full_label_list}{@$labels_in_mx_and_full_list} = (1) x scalar @$labels_in_mx_and_full_list;

        ##  delete elements from full_label_list that are not in the matrix - NEED TO ADD TO A SEPARATE SUB - REPEATED FROM _calc_overlap
        #my %tmp = %$full_label_list;  #  don't want to disturb original data, as it is used elsewhere
        #my %tmp2 = %tmp;
        #delete @tmp{keys %$labels_in_matrix};  #  get a list of those not in the matrix
        #delete @tmp2{keys %tmp};  #  those remaining are the ones in the matrix
        #$full_label_list = \%tmp2;
    }

    my $n = 0;
    foreach my $value (values %$full_label_list) {
        $n += $value;
    }

    my ($total_count, $qe) = (undef, undef);
    my (%done, %p_values);

    BY_LABEL1:
    foreach my $label1 (keys %{$full_label_list}) {

        #  save a few double calcs
        if (! defined $p_values{$label1}) {
            $p_values{$label1} = $full_label_list->{$label1} / $n;
        }

        BY_LABEL2:
        foreach my $label2 (keys %{$full_label_list}) {

            next if $done{$label2};  #  we've already looped through these 

            if (! defined $p_values{$label2}) {
                $p_values{$label2} = $full_label_list->{$label2} / $n ;
            }

            my $value = 1;

            if (defined $matrix) {
                $value = $matrix->get_defined_value (
                    element1 => $label1,
                    element2 => $label2
                );

                #  trap self-self values not in matrix but don't override ones that are
                if (! defined $value) {
                    $value = $self_similarity;
                }
            }
            elsif ($label1 eq $label2) {
                $value = $self_similarity;
            }

            #  multiply by 2 to allow for loop savings
            $qe += 2 * $value * $p_values{$label1} * $p_values{$label2};
            #$compared{$label2} ++;
        }
        $done{$label1}++;
    }

    my %results;

    $results{RAO_TLABELS}   = \%p_values;
    $results{RAO_TN}        = (scalar keys %p_values) ** 2;
    $results{RAO_QE}        = $qe;

    return wantarray
            ? %results
            : \%results;
}

######################################################
#
#  routines to get the lists of labels in elements and combine other lists.
#  they all depend on calc_abc in the end.
#

sub get_metadata_calc_local_range_stats {
    my %metadata = (
        name            => 'Local range summary statistics',
        description     => 'Summary stats of the local ranges within neighour sets.',
        type            => 'Lists and Counts',
        pre_calc        => 'calc_abc2',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            ABC2_MEAN_ALL      => {
                description     => 'Mean label range in both element sets',
                lumper          => 1,
            },
            ABC2_SD_ALL        => {
                description     => 'Standard deviation of label ranges in both element sets',
                uses_nbr_lists  => 2,
                lumper          => 1,
            },
            ABC2_MEAN_SET1     => {
                description     => 'Mean label range in neighbour set 1',
                lumper          => 0,
            },
            ABC2_SD_SET1       => {
                description => 'Standard deviation of label ranges in neighbour set 1',
                lumper      => 0,
            },
            ABC2_MEAN_SET2     => {
                description     => 'Mean label range in neighbour set 2',
                uses_nbr_lists  => 2,
                lumper          => 0,
            },
            ABC2_SD_SET2       => {
                description     => 'Standard deviation of label ranges in neighbour set 2',
                uses_nbr_lists  => 2,
                lumper          => 0,
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

#  store the lists from calc_abc2 - mainly the lists
sub calc_local_range_stats {
    my $self = shift;
    my %args = @_;  #  rest of args into a hash

    #  these should be undef if no labels
    my %results = (
        ABC2_MEAN_ALL  => undef,
        ABC2_SD_ALL    => undef,
        ABC2_MEAN_SET1 => undef,
        ABC2_SD_SET1   => undef,
        ABC2_MEAN_SET2 => undef,
        ABC2_SD_SET2   => undef,
    );

    my $stats;

    if (scalar keys %{$args{label_hash_all}}) {
        $stats = $stats_class->new;
        #my @barry = values %{$args{label_hash_all}};
        $stats -> add_data (values %{$args{label_hash_all}});
        $results{ABC2_MEAN_ALL} = $stats->mean;
        $results{ABC2_SD_ALL}   = $stats->standard_deviation;
    }
    
    if (scalar keys %{$args{label_hash1}}) {
        $stats = $stats_class->new;
        $stats->add_data (values %{$args{label_hash1}});
        $results{ABC2_MEAN_SET1} = $stats->mean;
        $results{ABC2_SD_SET1}   = $stats->standard_deviation;
    }
    
    if (scalar keys %{$args{label_hash2}}) {
        $stats = $stats_class->new;
        $stats->add_data (values %{$args{label_hash2}});
        $results{ABC2_MEAN_SET2} = $stats->mean;
        $results{ABC2_SD_SET2}   = $stats->standard_deviation;
    }
    
    return wantarray
            ? %results
            : \%results;

}

sub get_metadata_calc_local_range_lists {
    my %metadata = (
        name            => 'Local range lists',
        description     => "Lists of labels with their local ranges as values. \n"
                           . 'The local ranges are the number of elements in '
                           . 'which each label is found in each neighour set.',
        type            => 'Lists and Counts',
        pre_calc        => 'calc_abc2',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            ABC2_LABELS_ALL    => {
                description     => 'List of labels in both neighbour sets',
                uses_nbr_lists  => 2,
                type            => 'list',
            },
            ABC2_LABELS_SET1   => {
                description     => 'List of labels in neighbour set 1',
                type            => 'list',
            },
            ABC2_LABELS_SET2   => {
                description     => 'List of labels in neighbour set 2',
                uses_nbr_lists  => 2,
                type            => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

#  store the lists from calc_abc2 - mainly the lists
sub calc_local_range_lists {
    my $self = shift;
    my %args = @_;  #  rest of args into a hash

    my %results = (
        ABC2_LABELS_ALL  => $args{label_hash_all},
        ABC2_LABELS_SET1 => $args{label_hash1},
        ABC2_LABELS_SET2 => $args{label_hash2},
    );

    return wantarray
            ? %results
            : \%results;

}

sub get_metadata_calc_local_sample_count_stats {
    my $self = shift;

    my %metadata = (
        name            => 'Sample count summary stats',
        description     => "Summary stats of the sample counts across the neighbour sets.\n",
        indices         => {
            ABC3_MEAN_ALL      => {
                description     => 'Mean of label sample counts across both element sets.',
                uses_nbr_lists  => 2,
                lumper      => 1,
            },
            ABC3_SD_ALL        => {
                description     => 'Standard deviation of label sample counts in both element sets.',
                uses_nbr_lists  => 2,
                lumper      => 1,
            },
            ABC3_MEAN_SET1     => {
                description     => 'Mean of label sample counts in neighbour set1.',
                lumper      => 0,
            },
            ABC3_SD_SET1       => {
                description     => 'Standard deviation of sample counts in neighbour set 1.',
                lumper      => 0,
            },
            ABC3_MEAN_SET2     => {
                description     => 'Mean of label sample counts in neighbour set 2.',
                uses_nbr_lists  => 2,
                lumper      => 0,
            },
            ABC3_SD_SET2       => {
                description     => 'Standard deviation of label sample counts in neighbour set 2.',
                uses_nbr_lists  => 2,
                lumper      => 0,
            },
            ABC3_SUM_ALL       => {
                description     => 'Sum of the label sample counts across both neighbour sets.',
                uses_nbr_lists  => 2,
                lumper      => 1,
            },
            ABC3_SUM_SET1      => {
                description     => 'Sum of the label sample counts across both neighbour sets.',
                lumper      => 0,
            },
            ABC3_SUM_SET2      => {
                description     => 'Sum of the label sample counts in neighbour set2.',
                uses_nbr_lists  => 2,
                lumper      => 0,
            },
        },
        type            => 'Lists and Counts',
        pre_calc        => 'calc_abc3',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        );  #  add to if needed
        return $metadata_class->new(\%metadata);
}

sub calc_local_sample_count_stats {
    my $self = shift;
    my %args = @_;  #  rest of args into a hash

    my %results = (
        ABC3_MEAN_ALL  => undef,
        ABC3_SD_ALL    => undef,
        ABC3_MEAN_SET1 => undef,
        ABC3_SD_SET1   => undef,
        ABC3_MEAN_SET2 => undef,
        ABC3_SD_SET2   => undef,
    );

    my $stats;
    
    # ensure undef if no samples

    if (scalar keys %{$args{label_hash_all}}) {
        $stats = $stats_class->new;
        #my @barry = values %{$args{label_hash_all}};
        $stats->add_data (values %{$args{label_hash_all}});
        $results{ABC3_MEAN_ALL} = $stats->mean;
        $results{ABC3_SD_ALL}   = $stats->standard_deviation;
        $results{ABC3_SUM_ALL}  = $stats->sum;
    }
    
    if (scalar keys %{$args{label_hash1}}) {
        $stats = $stats_class->new;
        $stats->add_data (values %{$args{label_hash1}});
        $results{ABC3_MEAN_SET1} = $stats->mean;
        $results{ABC3_SD_SET1}   = $stats->standard_deviation;
        $results{ABC3_SUM_SET1}  = $stats->sum;
    }
    
    if (scalar keys %{$args{label_hash2}}) {
        $stats = $stats_class->new;
        $stats->add_data (values %{$args{label_hash2}});
        $results{ABC3_MEAN_SET2} = $stats->mean;
        $results{ABC3_SD_SET2}   = $stats->standard_deviation;
        $results{ABC3_SUM_SET2}  = $stats->sum;
    }
    
    return wantarray ? %results : \%results;
}

sub get_metadata_calc_local_sample_count_lists {
    my $self = shift;

    my %metadata = (
        name            => 'Sample count lists',
        description     => "Lists of sample counts for each label within the neighbour sets.\n"
                         . "These form the basis of the sample indices.",
        indices         => {
            ABC3_LABELS_ALL    => {
                description     => 'List of labels in both neighbour sets with their sample counts as the values.',
                uses_nbr_lists  => 2,
                type            => 'list',
            },
            ABC3_LABELS_SET1   => {
                description     => 'List of labels in neighbour set 1. Values are the sample counts.  ',
                type            => 'list',
            },
            ABC3_LABELS_SET2   => {
                description     => 'List of labels in neighbour set 2. Values are the sample counts.',
                uses_nbr_lists  => 2,
                type            => 'list',
            },
        },
        type            => 'Lists and Counts',
        pre_calc        => 'calc_abc3',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        );  #  add to if needed
        return $metadata_class->new(\%metadata);
}

sub calc_local_sample_count_lists {
    my $self = shift;
    my %args = @_;  #  rest of args into a hash

    my %results = (
        ABC3_LABELS_ALL  => $args{label_hash_all},
        ABC3_LABELS_SET1 => $args{label_hash1},
        ABC3_LABELS_SET2 => $args{label_hash2},
    );

    return wantarray
        ? %results
        : \%results;

}

sub get_metadata_calc_abc_counts {
    my $self = shift;

    my %metadata = (
        name            => 'Label counts',
        description     => "Counts of labels in neighbour sets 1 and 2.\n"
                           . 'These form the basis for the Taxonomic Dissimilarity and Comparison indices.',
        type            => 'Lists and Counts',
        indices         => {
            ABC_A   => {
                description => 'Count of labels common to both neighbour sets',
                lumper      => 1,
            },
            ABC_B   => {
                description => 'Count of labels unique to neighbour set 1',
                lumper      => 1,
            },
            ABC_C   => {
                description => 'Count of labels unique to neighbour set 2',
                lumper      => 1,
            },
            ABC_ABC => {
                description => 'Total label count across both neighbour sets (same as RICHNESS_ALL)',
                lumper      => 1,
            },
        },
        pre_calc        => 'calc_abc',
        uses_nbr_lists  => 2,  #  how many sets of lists it must have
    );  #  add to if needed

    return $metadata_class->new(\%metadata);
}

sub calc_abc_counts {
    my $self = shift;

    my %args = @_;  #  rest of args into a hash

    my %results = (
        ABC_A   => $args{A},
        ABC_B   => $args{B},
        ABC_C   => $args{C},
        ABC_ABC => $args{ABC},
    );

    return wantarray
            ? %results
            : \%results;

}

#  for some indices where a, b, c & d are needed
sub calc_d {
    my $self = shift;
    my %args = @_;

    my $bd = $self->get_basedata_ref;

    my $count = eval {
        $bd -> get_label_count - $args{ABC};
    };

    my %results = (ABC_D => $count);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_d {
    my $self = shift;

    my $description =
      "Count of basedata labels not in either neighbour set (shared absence)\n"
      . 'Used in some of the dissimilarity metrics.';

    my %metadata = (
        name            => 'Label counts not in sample',
        description     => $description,
        type            => 'Lists and Counts',
        uses_nbr_lists  => 1,
        pre_calc        => 'calc_abc',
        indices         => {
            ABC_D => {
                description => 'Count of labels not in either neighbour set (D score)',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}


sub get_metadata_calc_elements_used {
    my $self = shift;

    my %metadata = (
        name            => 'Element counts',
        description     => "Counts of elements used in neighbour sets 1 and 2.\n",
        type            => 'Lists and Counts',
        pre_calc        => 'calc_abc',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            EL_COUNT_SET1 => {
                description    => 'Count of elements in neighbour set 1',
                lumper      => 0,
            },
            EL_COUNT_SET2 => {
                description    => 'Count of elements in neighbour set 2',
                uses_nbr_lists => 2,
                lumper      => 0,
            },
            EL_COUNT_ALL  => {
                description    => 'Count of elements in both neighbour sets',
                uses_nbr_lists => 1,
                lumper      => 1,
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_elements_used {
    my $self = shift;

    my %args = @_;  #  rest of args into a hash

    my %results = (
        EL_COUNT_SET1 => $args{element_count1},
        EL_COUNT_SET2 => $args{element_count2},
        EL_COUNT_ALL  => $args{element_count_all},
    );

    return wantarray
            ? %results
            : \%results;

}

sub get_metadata_calc_nonempty_elements_used {
    my $self = shift;

    my %metadata = (
        name            => 'Non-empty element counts',
        description     => "Counts of non-empty elements in neighbour sets 1 and 2.\n",
        type            => 'Lists and Counts',
        pre_calc        => 'calc_abc',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            EL_COUNT_NONEMPTY_SET1 => {
                description    => 'Count of non-empty elements in neighbour set 1',
                lumper      => 0,
            },
            EL_COUNT_NONEMPTY_SET2 => {
                description    => 'Count of non-empty elements in neighbour set 2',
                uses_nbr_lists => 2,
                lumper      => 0,
            },
            EL_COUNT_NONEMPTY_ALL  => {
                description    => 'Count of non-empty elements in both neighbour sets',
                uses_nbr_lists => 1,
                lumper      => 1,
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_nonempty_elements_used {
    my $self = shift;
    my %args = @_;  #  rest of args into a hash

    #  should run a precalc_gobal to check if the
    #  basedata has empty groups as then we can shortcut
    my $bd   = $self->get_basedata_ref;
    my $list = $args{element_list_all};

    my %nonempty;
    foreach my $gp (@$list) {
        my $ref = $bd->get_labels_in_group_as_hash (group => $gp);
        next if !scalar keys %$ref;
        $nonempty{$gp}++;
    }
    my $non_empty_all  = scalar keys %nonempty;
    my $non_empty_set1 = grep {exists $nonempty{$_}} keys %{$args{element_list1} // {}};
    my $non_empty_set2 = $args{element_list2}
        ? grep {exists $nonempty{$_}} keys %{$args{element_list2}}
        : undef;

    my %results = (
        EL_COUNT_NONEMPTY_SET1 => $non_empty_set1,
        EL_COUNT_NONEMPTY_SET2 => $non_empty_set2,
        EL_COUNT_NONEMPTY_ALL  => $non_empty_all,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_element_lists_used {
    my $self = shift;

    my %metadata = (
        name            => "Element lists",
        description     => "Lists of elements used in neighbour sets 1 and 2.\n"
                           . 'These form the basis for all the spatial calculations.',
        type            => 'Lists and Counts',
        pre_calc        => 'calc_abc',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            EL_LIST_SET1  => {
                description    => 'List of elements in neighbour set 1',
                type           => 'list',
            },
            EL_LIST_SET2  => {
                description    => 'List of elements in neighbour set 2',
                uses_nbr_lists => 2,
                type           => 'list',
            },
            EL_LIST_ALL   => {
                description    => 'List of elements in both neighour sets',
                uses_nbr_lists => 2,
                type           => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_element_lists_used {
    my $self = shift;

    my %args = @_;  #  rest of args into a hash

    my %results = (
        EL_LIST_SET1 => $args{element_list1},
        EL_LIST_SET2 => $args{element_list2},
        EL_LIST_ALL  => $args{element_list_all},
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_abc {

    my %metadata = (
        name            => 'calc_abc',
        description     => 'Calculate the label lists in the element sets.',
        type            => 'not_for_gui',
        indices         => {},
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        required_args   => [$RE_ABC_REQUIRED_ARGS],  #experimental - https://github.com/shawnlaffan/biodiverse/issues/336
    );

    return $metadata_class->new(\%metadata);
}

sub calc_abc {  #  wrapper for _calc_abc - use the other wrappers for actual GUI stuff
    my $self = shift;
    #my %args = @_;

    return $self->_calc_abc (
        @_,
        count_labels  => 0,
        count_samples => 0,
    );
}

sub get_metadata_calc_abc2 {
    my %metadata = (
        name            => 'calc_abc2',
        description     => 'Calculate the label lists in the element sets, '
                           . 'recording the count of groups per label.',
        type            => 'not_for_gui',  #  why not???
        indices         => {},
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        required_args   => [$RE_ABC_REQUIRED_ARGS],  #experimental - issue https://github.com/shawnlaffan/biodiverse/issues/336
    );

    return $metadata_class->new(\%metadata);
}

sub calc_abc2 {  #  run calc_abc, but keep a track of the label counts across groups
    my $self = shift;
    #my %args = @_;

    return $self -> _calc_abc(@_, count_labels => 1);
}

sub get_metadata_calc_abc3 {

    my %metadata = (
        name            => 'calc_abc3',
        description     => 'Calculate the label lists in the element sets, '
                           . 'recording the count of samples per label.',
        type            => 'not_for_gui',  #  why not?
        indices         => {},
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        required_args   => [$RE_ABC_REQUIRED_ARGS],  #experimental - issue https://github.com/shawnlaffan/biodiverse/issues/336
    );

    return $metadata_class->new(\%metadata);
}

sub calc_abc3 {  #  run calc_abc, but keep a track of the label counts and samples across groups
    my $self = shift;
    #my %args = @_;

    return $self->_calc_abc(@_, count_samples => 1);
}

sub _calc_abc {  #  required by all the other indices, as it gets the labels in the elements
    my $self = shift;
    my %args = @_;

    my $bd = $self->get_basedata_ref;

    croak "At least one of element_list1, element_list2, label_list1, "
          . "label_list2, label_hash1, label_hash2 must be specified\n"
        if ! defined (
                $args{element_list1}
             // $args{element_list2}
             // $args{label_hash1}
             // $args{label_hash2}
             // $args{label_list1}
             // $args{label_list2}
        );

    my $count_labels  = $args{count_labels};
    my $count_samples = $args{count_samples};

    my ($a, $b, $c, $abc);
    my %label_list = (1 => {}, 2 => {});
    my %label_list_master;

    my %element_check = (1 => {}, 2 => {});
    my %element_check_master;

    #  loop iter variables
    my ($listname, $iter, $label, $value);

    my %hash = (element_list1 => 1, element_list2 => 2);
    
    LISTNAME:
    while (($listname, $iter) = each (%hash)) {
        #print "$listname, $iter\n";
        my $el_listref = $args{$listname}
          // next LISTNAME;

        croak "_calc_abc argument $listname is not a list ref\n"
          if !ref $el_listref;

        if (reftype ($el_listref) eq 'HASH') {  #  silently convert the hash to an array
            $el_listref = [keys %$el_listref];
        }

        my (@checked_elements, @label_list);

        ELEMENT:
        foreach my $element (@$el_listref) {
            my $sublist = $bd->get_labels_in_group_as_hash_aa ($element);
            push @label_list, %$sublist;
            push @checked_elements, $element;
        }

        if ($count_labels) {
            #  track the number of times each label occurs
            foreach my $label (pairkeys @label_list) {
                $label_list{$iter}{$label}++;
                $label_list_master{$label}++;
            }
        }
        elsif ($count_samples) {
            #  track the number of samples for each label
            foreach my $pair (pairs @label_list) {
                my ($label, $value) = @$pair;
                $label_list{$iter}{$label} += $value;
                $label_list_master{$label} += $value;
            }
        }
        else {
            %{$label_list{$iter}} = @label_list;
            @label_list_master{keys %{$label_list{$iter}}}
              = (1) x scalar keys %{$label_list{$iter}};
        }
        #  hash slice is faster than looping
        @{$element_check{$iter}}{@checked_elements} = (1) x @checked_elements;
        @element_check_master{@checked_elements}    = (1) x scalar @checked_elements;
    }

    #  run some checks on the elements
    my $element_count_master = scalar keys %element_check_master;
    my $element_count1       = scalar keys %{$element_check{1}};
    my $element_count2       = scalar keys %{$element_check{2}};

    croak '[INDICES] DOUBLE COUNTING OF ELEMENTS IN calc_abc, '
          . "$element_count1 + $element_count2 > $element_count_master\n"
      if $element_count1 + $element_count2 > $element_count_master;

    %hash = (label_list1 => 1, label_list2 => 2);
    while (($listname, $iter) = each %hash) {
        next if !defined $args{$listname};

        my $label_listref = $args{$listname};
        if ((ref $label_listref) !~ /ARRAY/) {
            carp "[INDICES] $label_listref is not an array ref\n";
            next;
        }

        if ($count_labels || $count_samples) {
            foreach my $lbl (@$label_listref) {
                $label_list_master{$lbl}++;
                $label_list{$iter}{$lbl}++;
            }
        }
        else {
            @label_list_master{@$label_listref}    = (1) x scalar @$label_listref;
            @{$label_list{$iter}}{@$label_listref} = (1) x scalar @$label_listref;
        }
    }

    %hash = (label_hash1 => 1, label_hash2 => 2);
    while (($listname, $iter) = each %hash) {
        next if ! defined $args{$listname};

        my $label_hashref = $args{$listname};

        croak "[INDICES] $label_hashref is not a hash ref\n"
          if (ref $label_hashref) !~ /HASH/;

        if ($count_labels || $count_samples) {
            while (($label, $value) = each %$label_hashref) {
                $label_list_master{$label} += $value;
                $label_list{$iter}{$label} += $value;
            }
        }
        else {  #  don't care about counts yet - assign using a slice
            @label_list_master{keys %$label_hashref}    = (1) x scalar keys %$label_hashref;
            @{$label_list{$iter}}{keys %$label_hashref} = (1) x scalar keys %$label_hashref;
        }
    }

    #  set the counts to one if using plain old abc, as the elements section doesn't obey it properly
    if (!($count_labels || $count_samples)) {
        @label_list_master{keys %label_list_master} = (1) x scalar keys %label_list_master;
        @{$label_list{1}}{keys %{$label_list{1}}}   = (1) x scalar keys %{$label_list{1}};
        @{$label_list{2}}{keys %{$label_list{2}}}   = (1) x scalar keys %{$label_list{2}};
    }

    $abc = scalar keys %label_list_master;

    #  a, b and c are simply differences of the lists
    $a = scalar (keys %{$label_list{1}})
       + scalar (keys %{$label_list{2}})
       - scalar (keys %label_list_master);
    $b = scalar (keys %label_list_master)    #  all keys not in label_list2
       - scalar (keys %{$label_list{2}});
    $c = scalar (keys %label_list_master)    #  all keys not in label_list1
       - scalar (keys %{$label_list{1}});

    my %results = (
        A   => $a,
        B   => $b,
        C   => $c,
        ABC => $abc,

        label_hash_all    => \%label_list_master,
        label_hash1       => \%{$label_list{1}},
        label_hash2       => \%{$label_list{2}},
        element_list1     => $element_check{1},
        element_list2     => $element_check{2},
        element_list_all  => [keys %element_check_master],
        element_count1    => $element_count1,
        element_count2    => $element_count2,
        element_count_all => $element_count_master,
    );

    return wantarray ? %results : \%results;
}


#########################################
#
#  miscellaneous local routines

#sub min {
#    no warnings 'uninitialized';
#    $_[0] < $_[1] ? $_[0] : $_[1];
#}
#
#sub max {
#    no warnings 'uninitialized';
#    $_[0] > $_[1] ? $_[0] : $_[1];
#}

sub numerically {$a <=> $b};

1;

__END__

=head1 NAME

Biodiverse::Indices::Indices

=head1 SYNOPSIS

  use Biodiverse::Indices::Indices;

=head1 DESCRIPTION

Indices for the Biodiverse system.
Inherited by Biodiverse::Indices.  Do not use directly.
See L<http://purl.org/biodiverse/wiki/Indices> for more details.

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
