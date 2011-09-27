package Biodiverse::Indices::Indices;
use strict;
use warnings;

use Carp;

use Scalar::Util qw /blessed weaken/;
use English ( -no_match_vars );

our $VERSION = '0.16';

use Biodiverse::Statistics;

my $stats_class = 'Biodiverse::Statistics';


###########################################
#  test/debug methods
#sub get_metadata_debug_print_nothing {
#    my %metadata = (
#        pre_calc_global => 'get_iei_element_cache',
#    );
#    
#    return wantarray ? %metadata : \%metadata;
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

    my %arguments = (
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
            COMPL           => {
                cluster         => [1,0],  #  largest to smallest
                description     => "A crude complementarity index for use in clustering.\n"
                                    . "It is actually the same as RICHNESS_ALL and "
                                    . "might be disabled in a later release.",
                uses_nbr_lists  => 2,
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_richness {  #  calculate the aggregate richness for a set of elements
    my $self = shift;
    my %args = @_;  #  rest of args into a hash

    my %results = (RICHNESS_ALL => $args{ABC},
                   RICHNESS_SET1 => $args{A} + $args{B},
                   RICHNESS_SET2 => $args{A} + $args{C},
                   COMPL => $args{ABC}
                  );

    return wantarray
        ? (%results)
        : \%results;
}

sub get_metadata_calc_redundancy {

    my %arguments = (
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

    return wantarray ? %arguments : \%arguments;
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

    foreach my $subLabel (keys %{$label_list_all}) {
        $sample_count_all += $label_list_all->{$subLabel};
        $sample_count_inner += $label_list1->{$subLabel} if exists $label_list1->{$subLabel};
        $sample_count_outer += $label_list2->{$subLabel} if exists $label_list2->{$subLabel};
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
    
    my %arguments = (
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

    return wantarray ? %arguments : \%arguments;
}

sub is_dissimilarity_valid {
    my $self = shift;
    my %args = @_;

    my %result = (
        DISSIMILARITY_IS_VALID => ($args{A} || $args{B}) && ($args{A} || $args{C}),
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

sub get_metadata_calc_sorenson {
    my $self = shift;

    my %arguments = (
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

    return wantarray ? %arguments : \%arguments;
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

    my %arguments = (
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

    return wantarray ? %arguments : \%arguments;
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
#    my %arguments = (
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
#    return wantarray ? %arguments : \%arguments;
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
    
    my %arguments = (
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

    return wantarray ? %arguments : \%arguments;    
}

#  nestedness-resultant dissimilarity
#  from Baselga (2010) http://dx.doi.org/10.1111/j.1466-8238.2009.00490.x
sub calc_nestedness_resultant {
    my $self = shift;
    my %args = @_;
    
    my ($A, $B, $C, $ABC) = @args{qw /A B C ABC/};
    
    my $score;
    if ($A == 0 and $B > 0 and $C > 0) {
        #  nothing in common, no nestedness
        $score = 0;
    }
    elsif ($A == 0 and min ($B, $C) == 0) {
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

    my %arguments = (
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

    return wantarray ? %arguments : \%arguments;
}

# calculate the Bray-Curtis dissimilarity index between two label lists.
sub calc_bray_curtis {  
    my $self = shift;
    my %args = @_;

    #  make copies of the label hashes so we don't mess things
    #  up with auto-vivification
    my %l1 = %{$args{label_hash1}};
    my %l2 = %{$args{label_hash2}};
    my %labels = (%l1, %l2);

    my ($A, $B, $W) = (0, 0, 0);
    foreach my $label (keys %labels) {
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
            '= \frac{2W}{A + B}',
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

    return wantarray ? %metadata : \%metadata;
}

sub calc_bray_curtis_norm_by_gp_counts {
    my $self = shift;
    my %args = @_;

    #  make copies of the label hashes so we don't mess things
    #  up with auto-vivification
    my %l1 = %{$args{label_hash1}};
    my %l2 = %{$args{label_hash2}};
    my %labels = (%l1, %l2);
    my $counts1 = $args{EL_COUNT_SET1};
    my $counts2 = $args{EL_COUNT_SET2};

    my ($A, $B, $W) = (0, 0, 0);
    foreach my $label (keys %labels) {
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

    my %arguments = (
        name            => 'Beta diversity',
        description     => "Beta diversity between neighbour sets 1 and 2.\n",
        indices         => {
            BETA_W => {
                cluster     => 1,
                description => qq{Whittaker's beta\n}
                             . "(Note that this is numerically the same as the Sorenson index.)",
                formula         => [  #'ABC / ((A+B + A+C) / 2) - 1'
                    '= \frac{A + B + C}{(\frac{(A+B) + (A+C)}{2})} - 1',
                    $self -> get_formula_explanation_ABC,
                ],
            },
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

    return wantarray ? %arguments : \%arguments;
}

sub calc_beta_diversity {  # calculate the beta diversity dissimilarity index between two label lists.
    my $self = shift;
    my %abc = @_;

    no warnings 'numeric';

    #my $beta_w = eval {$abc{ABC} / (($abc{A} * 2 + $abc{B} + $abc{C}) / 2) - 1};
    my $beta_2 = eval {
        $abc{ABC} / max ($abc{A} + $abc{B}, $abc{A} + $abc{C}) - 1
    };
    my %results = (
        #BETA_W => $beta_w,
        BETA_2 => $beta_2,
    );

    return wantarray ? %results : \%results;
}

#  this is identical to the more commonly used Sorenson index
#sub _calc_s1 {  #  calculate the Sorenson species turnover between two element sets.
#                    #  This is identical to calcCzechanowski
#                    #  name derived from
#                    #    Lennon, J.J., Koleff, P., Greenwood, J.J.D. & Gaston, K.J. (2001)
#                    #    The geographical structure of British bird distributions:
#                    #    diversity, spatial turnover and scale.
#                    #    Journal of Animal Ecology, 70, 966-979
#    my $self = shift;
#    my %abc = @_;
#
#    if ($abc{get_args}) {
#        my %arguments = (name => 'S1',
#                         description => "Sorenson dissimilarity between two sets of labels.\n" .
#                                          "This is actually identical to the Czechanowski index.  Source:\n" .
#                                          "Lennon, J.J., Koleff, P., Greenwood, J.J.D. and Gaston, K.J. (2001)\n" .
#                                          "The geographical structure of British bird distributions: " .
#                                          "diversity, spatial turnover and scale.\n" .
#                                          "Journal of Animal Ecology, 70, 966-979.",
#                         Formula => 'S1 = 1 - (2A / (2A + B + C))',
#                         indices => {S1 => {cluster => 1,
#                                            description => '= 1 - (2A / (2A + B + C))'
#                                            }
#                                     },
#                         type => 'Taxonomic Dissimilarity and Comparison',
#                         uses_nbr_lists => 2,  #  how many sets of lists it must have
#                         pre_calc => 'calc_abc',
#                        );  #  add to if needed
#        return wantarray ? %arguments : \%arguments;
#    }
#
#
#    my $value = 1 - ((2 * $abc{A}) / ($abc{A} + $abc{ABC}));
#
#    return wantarray
#            ? (S1 => $value)
#            : {S1 => $value};
#
#}

sub get_metadata_calc_s2 {
    my $self = shift;

    my %arguments = (
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

    return wantarray ? %arguments : \%arguments;
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

    my %arguments = (
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
                cluster     => 1,
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

    return wantarray ? %arguments : \%arguments;
}

#  calculate the simpson and shannon indices
sub calc_simpson_shannon {
    my $self = shift;
    my %args = @_;

    my $labels = $args{label_hash_all};
    my $richness = $args{ABC};

    my $n = 0;
    foreach my $value (values %$labels) {
        $n += $value;
    }

    my ($simpson_d, $shannon_h, $sum_labels, $shannon_e);
    foreach my $value (values %$labels) {  #  don't need the labels, so don't use keys
        my $p_i = $value / $n;
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

    my %results = (
        SHANNON_H    => $shannon_h,
        SHANNON_HMAX => $shannon_hmax,
        SHANNON_E    => $shannon_e,
        SIMPSON_D    => 1 - $simpson_d,
    );

    return wantarray ? %results : \%results;
}



sub get_metadata_calc_overlap_tx {

    my $desc = <<OLAP_TX_DESC
Calculate taxonomic overlap metrics between the two sets of elements.
Uses deviation from zero for variances.  In most cases the means and
variances will be the same.  
Bears some relation to Rao's quadratic entropy if this calculation
were modified to weight by sample counts.
It is best to apply these indices using a small neighbour set 1
relative to a large neighbour set 2.
OLAP_TX_DESC
  ;

    my %arguments = (
        name            => 'Taxonomic overlap',
        description     => $desc,
        type            => 'Taxonomic Dissimilarity and Comparison',
        pre_calc        => 'calc_abc',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            TXO_M_RATIO     => {
                description     => 'Ratio of the set1 mean to the mean of the combined neighbour sets',
                lumper          => 0,
                formula         => [
                    '= \frac{TXO\_MEAN}{TXO\_TMEAN}'
                ],
            },
            TXO_V_RATIO     => {
                description     => 'Ratio of the set1 variance to the variance of the combined neighbour sets.',
                lumper          => 0,
                formula         => [
                    '= \frac{ TXO\_VARIANCE }{ TXO\_TVARIANCE }'
                ],
            },
            TXO_Z_RATIO     => {
                description     => '(TXO_MEAN / TXO_VARIANCE) / (TXO_TMEAN / TXO_TVARIANCE)',
                lumper          => 0,
                formula         => [
                    '= \frac{ \frac{TXO\_MEAN}{\sqrt {TXO\_VARIANCE}} }{ \frac{TXO\_TMEAN}{\sqrt {TXO\_TVARIANCE}} }',                    
                ],
            },
            TXO_Z_SCORE     => {
                description     => 'Z-score of the set1 mean given the mean and SD of the combined neighbour sets',
                lumper          => 0,
                formula         => [
                    '= \frac{TXO\_MEAN - TXO\_TMEAN }{\sqrt {TXO\_TVARIANCE}}'
                ],
            },
            #TXO_WARD            => {
            #    cluster         => 1,
            #    description     => "Ward's dissimilarity metric, set1 versus set2.",
            #    uses_nbr_lists  => 2
            #},
            TXO_MEAN       => {description => "Mean of neighbour set 1.", lumper => 0,},
            TXO_TMEAN      => {description => "Mean of both neighbour sets.", lumper => 1,},
            TXO_VARIANCE   => {description => "Variance of neighbour set 1 (mean squared difference from zero).", lumper => 0,},
            TXO_TVARIANCE  => {description => "Variance of the combined neighbour sets (mean squared difference from zero).", lumper => 1,},
            TXO_N          => {description => "Count of labels used in neighbour set 1.", lumper => 0,},
            TXO_TN         => {description => "Count of all labels used in the combined neighbour sets.", lumper => 1,},
            TXO_LABELS     => {
                description => 'List of labels in neighbour set 1.',
                type        => 'list',
            },
            TXO_TLABELS    => {
                description => 'List of all labels used (across both neighbour sets).',
                type        => 'list',
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_overlap_tx {
    my $self = shift;
    my %args = @_;

    #  grab the results and rename them.  Could loop over them, but this will be faster
    my $r = $self -> _calc_overlap (%args, use_matrix => 0);
    my %results = (
        TXO_M_RATIO   => $r->{M_RATIO},
        TXO_V_RATIO   => $r->{V_RATIO},
        TXO_Z_RATIO   => $r->{Z_RATIO},
        TXO_Z_SCORE   => $r->{Z_SCORE},
        #TXO_WARD      => $r->{WARD},
        TXO_MEAN      => $r->{MEAN},
        TXO_TMEAN     => $r->{TMEAN},
        TXO_VARIANCE  => $r->{VARIANCE},
        TXO_TVARIANCE => $r->{TVARIANCE},
        TXO_N         => $r->{N},
        TXO_TN        => $r->{TN},
        TXO_TLABELS   => $r->{TLABELS},
        TXO_LABELS    => $r->{LABELS},
    );

    return wantarray
        ? %results
        : \%results;
}

sub get_metadata_calc_overlap_mx  {

    my %arguments = (
        name            => 'Matrix overlap',
        description     => "Calculate matrix overlap metrics between the two sets of groups.\n"
                         . "Many of them measure homogeneity, where 0 = homogeneous.\n"
                         . "Excludes labels not in the selected matrix, and variances are deviations from zero.\n"
                         . 'It is best to apply these using a small neighbour set 1 relative to a large neighbour set 2',
        type            => 'Matrix',
        required_args   => {matrix_ref => 1}, #  must be set for it to be used
        pre_calc        => 'calc_abc',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            MXO_M_RATIO    => {
                description => 'Ratio of the set1 mean to the total mean',
                formula     => [
                    '= \frac { MXO\_MEAN }{ MXO\_TMEAN }',
                ],
            },
            MXO_V_RATIO    => {
                description => 'Ratio of the set1 variance to the total variance',
                formula     => [
                    '= \frac { MXO\_VARIANCE }{ MXO\_TVARIANCE }',
                ],
            },
            MXO_Z_RATIO    => {
                description => 'A ratio of the local to total z-scores.',
                formula     => [
                    '= \frac { \frac { MXO\_MEAN }{ \sqrt { MXO\_VARIANCE }} }{ \frac { MXO\_TMEAN }{ \sqrt {MXO\_TVARIANCE}} }',
                    ],
            },
            MXO_Z_SCORE    => {
                description => 'Z-score of the set1 mean given the total mean and SD',
                formula     => [
                    '= \frac {MXO\_MEAN - MXO\_TMEAN }{ \sqrt { MXO\_TVARIANCE} }',
                ]
            },
            #MXO_WARD       => {
            #    cluster => 1,
            #    description => "Ward's dissimilarity metric - set1 versus set2",
            #    uses_nbr_lists => 2
            #},
            MXO_MEAN       => {description => 'Mean of neighbour set 1', lumper => 0,},
            MXO_TMEAN      => {
                description => 'Mean of both neighbour sets',
                #cluster     => 1,
                lumper => 1,
            },
            MXO_VARIANCE   => {description => 'Variance of neighbour set 1 (mean squared difference from zero)', lumper => 0,},
            MXO_TVARIANCE  => {description => 'Variance of both neighbour sets (mean squared difference from zero)', lumper => 1,},
            MXO_N          => {description => 'Count of labels used in neighbour set 1', lumper => 0,},
            MXO_TN         => {description => 'Count of all labels used', lumper => 1,},
            MXO_LABELS     => {
                description => 'List of labels in neighbour set 1.',
                type        => 'list',
            },
            MXO_TLABELS    => {
                description => 'List of all labels used (across both neighbour sets).',
                type        => 'list',
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_overlap_mx {
    my $self = shift;
    my %args = @_;

    my $r = $self -> _calc_overlap (
        %args,
        use_matrix => 1,
    );

    my %results = exists $r->{MXO}
                ? (MXO => undef)
                : (MXO_M_RATIO      => $r->{M_RATIO},
                   MXO_V_RATIO      => $r->{V_RATIO},
                   MXO_Z_RATIO      => $r->{Z_RATIO},
                   MXO_Z_SCORE      => $r->{Z_SCORE},
                   #MXO_WARD         => $r->{WARD},
                   MXO_MEAN         => $r->{MEAN},
                   MXO_TMEAN        => $r->{TMEAN},
                   MXO_VARIANCE     => $r->{VARIANCE},
                   MXO_TVARIANCE    => $r->{TVARIANCE},
                   MXO_N            => $r->{N},
                   MXO_TN           => $r->{TN},
                   MXO_TLABELS      => $r->{TLABELS},
                   MXO_LABELS       => $r->{LABELS},
                   );

    return wantarray
            ? %results
            : \%results;
}

#  calculate the degree of overlap between two sets of groups, use matrix values if specified
sub _calc_overlap {
    my $self = shift;
    my %args = @_;  #  rest of args into a hash

    my $use_matrix      = $args{use_matrix};  #  boolean variable
    my $self_similarity = $args{self_similarity} || 0;

    my $full_label_list = $args{label_hash_all};
    my $label_list1     = $args{label_hash1};
    my $label_list2     = $args{label_hash2};

    #my $ward_valid = 1;

    my $matrix;
    if ($use_matrix) {
        $matrix = $args{matrix_ref};
        croak if ! defined $matrix;

        #  delete elements from full_label_list that are not in the matrix
        my $labels_in_matrix = $matrix -> get_elements;
        my %tmp = %$full_label_list;  #  don't want to disturb original data, as it is used elsewhere
        my %tmp2 = %tmp;
        delete @tmp{keys %$labels_in_matrix};  #  get a list of those not in the matrix
        delete @tmp2{keys %tmp};  #  those remaining are the ones in the matrix
        $full_label_list = \%tmp2;

        #  check list1 for matrix elements
        %tmp = %$label_list1;
        my $count = scalar keys %tmp;
        delete @tmp{%$labels_in_matrix};
        #$ward_valid = ($count > scalar keys %tmp);  #  we have matrix elements if some were deleted

        #if ($ward_valid) {  #  check the second set of labels
        #    %tmp = %$label_list2;
        #    $count = scalar keys %tmp;
        #    delete @tmp{%$labels_in_matrix};
        #    $ward_valid = ($count > scalar keys %tmp);  #  we have matrix elements here too if some were deleted
        #}
    }

    #  we need to get the distance between and across two groups
    my ($sumX, $sumXsqr, $count) = (undef, undef, 0);
    my ($totalSumX, $totalSumXsqr, $totalCount) = (undef, undef, 0);

    my (%done, %compared, %centre_compared);

    BY_LABEL1:
    foreach my $label1 (keys %{$full_label_list}) {

        BY_LABEL2:
        foreach my $label2 (keys %{$full_label_list}) {

            next BY_LABEL2 if $done{$label2};  #  we've already looped through these 

            my $value = 1;

            if (defined $matrix) {
                $value = $matrix->get_value(element1 => $label1, element2 => $label2);
                #  trap self-self values not in matrix but don't override ones that are
                if (! defined $value) {
                    $value = $self_similarity;
                }
            }
            elsif ($label1 eq $label2) {
                $value = $self_similarity;
            }

            #  count labels shared between groups
            if (exists $label_list1->{$label1} && exists ($label_list2->{$label2})) {
                $sumX    += $value;
                $sumXsqr += $value**2;
                $count   ++;
                $centre_compared{$label2} ++;
            }

            #  sum the total relationship between all labels across both groups
            $totalSumX    += $value;
            $totalSumXsqr += $value**2;
            $totalCount   ++;
            $compared{$label2} ++;
        }
        $done{$label1}++;
    }

    my %results;

    $results{TLABELS} = \%compared;
    $results{LABELS} = \%centre_compared;

    #  all the variances are predicated on the "mean" being zero,
    #  as we assume a dissimilarity matrix ranging from zero
    {
        #  suppress these warnings within this block
        no warnings qw /uninitialized numeric/;  

        $results{N}         = $count;
        $results{TN}        = $totalCount;
        $results{MEAN}      = eval {$sumX / $count};
        $results{VARIANCE}  = eval {$sumXsqr / $count};
        $results{TMEAN}     = eval {$totalSumX / $totalCount};

        $results{TVARIANCE} = eval {
            $totalSumXsqr / $totalCount
        };

        $results{M_RATIO} = eval {
            $results{MEAN} / $results{TMEAN}
        };

        $results{V_RATIO} = eval {
            $results{VARIANCE} / $results{TVARIANCE}
        };

        $results{Z_RATIO} = eval {
            ($results{MEAN} / ($results{VARIANCE} ** 0.5))
            / ($results{TMEAN} / ($results{TVARIANCE} ** 0.5))
        };

        $results{Z_SCORE} = eval {
                ($results{MEAN} - $results{TMEAN}) / ($results{TVARIANCE} ** 0.5)
            };

        #  differs from TVARIANCE because it compares values in both nbr sets
        #$results{WARD}      = $ward_valid ? eval {$totalSumXsqr / $totalCount} : undef;

    };

    return wantarray
            ? %results
            : \%results;
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

    my %arguments = (
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
                type        => 'list',
            },
            TX_RAO_TLABELS  => {
                description => 'List of labels and values used in the TX_RAO_QE calculations',
                type        => 'list',
            },
        },
    );  #  add to if needed

    return wantarray ? %arguments : \%arguments;
}

sub calc_tx_rao_qe {
    my $self = shift;
    my %args = @_;

    my $r = $self -> _calc_rao_qe (@_, use_matrix => 0);
    my %results = (TX_RAO_TN        => $r->{RAO_TN},
                   TX_RAO_TLABELS   => $r->{RAO_TLABELS},
                   TX_RAO_QE        => $r->{RAO_QE},
                   );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_mx_rao_qe {
    my $self = shift;

    my %arguments = (
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

    return wantarray ? %arguments : \%arguments;
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

    my ($totalCount, $qe) = (undef, undef);
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
                $value = $matrix -> get_value (
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
    my %arguments = (
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

    return wantarray ? %arguments : \%arguments;
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
    my %arguments = (
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

    return wantarray ? %arguments : \%arguments;
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

    my %arguments = (
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
                description     => 'Sum of the label sample counts in neighbour set2.',
                uses_nbr_lists  => 2,
                lumper      => 1,
            },
            ABC3_SUM_SET1      => {
                description     => 'Sum of the label sample counts in neighbour set1.',
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
        return wantarray ? %arguments : \%arguments;
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
        $stats -> add_data (values %{$args{label_hash_all}});
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
    
    return wantarray
            ? %results
            : \%results;

}

sub get_metadata_calc_local_sample_count_lists {
    my $self = shift;

    my %arguments = (
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
        return wantarray ? %arguments : \%arguments;
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

    my %arguments = (
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

    return wantarray ? %arguments : \%arguments;
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

    return wantarray ? %metadata : \%metadata;
}


sub get_metadata_calc_elements_used {
    my $self = shift;

    my %arguments = (
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
                uses_nbr_lists => 2,
                lumper      => 1,
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
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

sub get_metadata_calc_element_lists_used {
    my $self = shift;

    my %arguments = (
        name            => "Element lists",
        description     => "Lists of elements used in neighbour sets 1 and 2.\n"
                           . 'These form the basis for all the spatial calculations.',
        type            => 'Lists and Counts',
        pre_calc        => 'calc_abc',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            EL_LIST_SET1  => {
                description    => 'List of elements in neighbour set 1',
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

    return wantarray ? %arguments : \%arguments;
}

sub calc_element_lists_used {
    my $self = shift;

    my %args = @_;  #  rest of args into a hash

    my %results = (
        EL_LIST_SET1 => $args{element_list1},
        EL_LIST_SET2 => $args{element_list2},
        EL_LIST_ALL  => $args{element_list_all},
    );

    return wantarray
            ? %results
            : \%results;

}

sub get_metadata_calc_abc {

    my %arguments = (
        description     => 'Calculate the label lists in the element sets.',
        type            => 'not_for_gui',
        indices         => {},
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_abc {  #  wrapper for _calc_abc - use the other wrappers for actual GUI stuff
    my $self = shift;
    #my %args = @_;

    return $self -> _calc_abc(
        @_,
        count_labels  => 0,
        count_samples => 0,
    );
}

sub get_metadata_calc_abc2 {
    my %arguments = (
        description     => 'Calculate the label lists in the element sets, '
                           . 'recording the count of groups per label.',
        type            => 'not_for_gui',  #  why not???
        indices         => {},
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_abc2 {  #  run calc_abc, but keep a track of the label counts across groups
    my $self = shift;
    #my %args = @_;

    return $self -> _calc_abc(@_, count_labels => 1);
}

sub get_metadata_calc_abc3 {

    my %arguments = (
        description     => 'Calculate the label lists in the element sets, '
                           . 'recording the count of samples per label.',
        type            => 'not_for_gui',  #  why not?
        indices         => {},
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_abc3 {  #  run calc_abc, but keep a track of the label counts and samples across groups
    my $self = shift;
    #my %args = @_;

    return $self -> _calc_abc(@_, count_samples => 1);
}

sub _calc_abc {  #  required by all the other indices, as it gets the labels in the elements
    my $self = shift;
    my %args = @_;

    my $bd = $self->get_basedata_ref;

    croak "none of refs element_list1, element_list2, label_list1, "
          . "label_list2, label_hash1, label_hash2 specified\n"
        if (! defined $args{element_list1}
            && ! defined $args{element_list2}
            && ! defined $args{label_list1}
            && ! defined $args{label_list2}
            && ! defined $args{label_hash1}
            && ! defined $args{label_hash2}
        );

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
        next LISTNAME if ! defined $args{$listname};
        if ((ref $args{$listname}) =~ /HASH/) {  #  silently convert the hash to an array
            $args{$listname} = [keys %{$args{$listname}}];
        }
        elsif (! ref ($args{$listname})) {
            croak "_calc_abc argument $listname is not a list ref\n";
        }

        my @checked_elements;
        my @label_list;
        
        ELEMENT:
        foreach my $element (@{$args{$listname}}) {
            #  Deal with lazy array refs pointing
            #  to longer lists than we have elements.
            #  Should really croak these days.
            next ELEMENT if ! defined $element;

            push (@label_list, $bd->get_labels_in_group_as_hash (group => $element));
            push @checked_elements, $element;
        }
        if ($args{count_labels}) {
            #  track the number of times each label occurs
            for (my $i = 0; $i <= $#label_list; $i += 2) {
                my $label = $label_list[$i];
                $label_list{$iter}{$label}++;
                $label_list_master{$label}++;
            }
        }
        elsif ($args{count_samples}) {
            #  track the number of samples for each label
            for (my $i = 0; $i < $#label_list; $i += 2) {
                #print "$i, $#label_list\n";
                my $label = $label_list[$i];
                my $value = $label_list[$i+1];
                $label_list{$iter}{$label} += $value;
                $label_list_master{$label} += $value;
            }
        }
        else {
            %{$label_list{$iter}} = @label_list;
            @label_list_master{keys %{$label_list{$iter}}} = (1) x scalar keys %{$label_list{$iter}};
        }
        @{$element_check{$iter}}{@checked_elements} = (1) x @checked_elements;
        #  hash slice is faster than looping
        @element_check_master{@checked_elements} = (1) x scalar @checked_elements;
    }

    #  run some checks on the elements
    my $element_count_master = scalar keys %element_check_master;
    my $element_count1 = scalar keys %{$element_check{1}};
    my $element_count2 = scalar keys %{$element_check{2}};
    if ($element_count1 + $element_count2 > $element_count_master) {
        croak '[INDICES] DOUBLE COUNTING OF ELEMENTS IN calc_abc, '
              . "$element_count1 + $element_count2 > $element_count_master\n";
    }

    %hash = (label_list1 => 1, label_list2 => 2);
    while (($listname, $iter) = each (%hash)) {
        next if ! defined $args{$listname};
        if ((ref $args{$listname}) !~ /ARRAY/) {
            carp "[INDICES] $args{$listname} is not an array ref\n";
            next;
        }

        if ($args{count_labels} || $args{count_samples}) {
            foreach my $lbl (@{$args{$listname}}) {
                $label_list_master{$lbl}++;
                $label_list{$iter}{$lbl}++;
            }
        }
        else {
            @label_list_master{@{$args{$listname}}} = (1) x scalar @{$args{$listname}};
            @{$label_list{$iter}}{@{$args{$listname}}} = (1) x scalar @{$args{$listname}};
        }
    }

    %hash = (label_hash1 => 1, label_hash2 => 2);
    while (($listname, $iter) = each (%hash)) {
        next if ! defined $args{$listname};
        if ((ref $args{$listname}) !~ /HASH/) {
            croak "[INDICES] $args{$listname} is not a hash ref\n";
        }

        if ($args{count_labels} || $args{count_samples}) {
            while (($label, $value) = each %{$args{$listname}}) {
                $label_list_master{$label} += $value;
                $label_list{$iter}{$label} += $value;
            }
        }
        else {  #  don't care about counts yet - assign using a slice
            @label_list_master{keys %{$args{$listname}}} = (1) x scalar keys %{$args{$listname}};
            @{$label_list{$iter}}{keys %{$args{$listname}}} = (1) x scalar keys %{$args{$listname}};
        }
    }

    #  set the counts to one if using plain old abc, as the elements section doesn't obey it properly
    if (! $args{count_labels} && ! $args{count_samples}) {
        @label_list_master{keys %label_list_master} = (1) x scalar keys %label_list_master;
        @{$label_list{1}}{keys %{$label_list{1}}} = (1) x scalar keys %{$label_list{1}};
        @{$label_list{2}}{keys %{$label_list{2}}} = (1) x scalar keys %{$label_list{2}};
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

    return wantarray
        ? %results
        : \%results;
}


#########################################
#
#  miscellaneous local routines

sub min {
    no warnings 'uninitialized';
    $_[0] < $_[1] ? $_[0] : $_[1];
}

sub max {
    no warnings 'uninitialized';
    $_[0] > $_[1] ? $_[0] : $_[1];
}

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
See L<http://code.google.com/p/biodiverse/wiki/Indices> for more details.

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
