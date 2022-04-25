package Biodiverse::Indices::RichnessEstimation;

use 5.016;

use strict;
use warnings;
use Carp;

use List::Util qw /max min sum/;

our $VERSION = '3.99_003';

my $metadata_class = 'Biodiverse::Metadata::Indices';

use Readonly;

Readonly my $z_for_ci => 1.959964;  #  currently hard coded for 0.95

sub get_metadata_calc_chao1 {
    my %metadata = (
        description     => 'Chao1 species richness estimator (abundance based)',
        name            => 'Chao1',
        type            => 'Richness estimators',
        pre_calc        => 'calc_abc3',
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            CHAO1_ESTIMATE  => {
                description => 'Chao1 index',
                reference   => 'NEEDED',
                formula     => [],
            },
            CHAO1_F1_COUNT    => {
                description => 'Number of singletons in the sample',
            },
            CHAO1_F2_COUNT    => {
                description => 'Number of doubletons in the sample',
            },
            CHAO1_SE => {
                description => 'Standard error of the Chao1 estimator [= sqrt(variance)]',
            },
            CHAO1_VARIANCE    => {
                description => 'Variance of the Chao1 estimator',
            },
            CHAO1_UNDETECTED  => {
                description   => 'Estimated number of undetected species',
            },
            CHAO1_CI_LOWER    => {
                description => 'Lower confidence interval for the Chao1 estimate',
            },
            CHAO1_CI_UPPER    => {
                description => 'Upper confidence interval for the Chao1 estimate',
            },
            CHAO1_META        => {
                description => 'Metadata indicating which formulae were used in the '
                            . 'calculations. Numbers refer to EstimateS equations at '
                            . 'http://viceroy.eeb.uconn.edu/EstimateS/EstimateSPages/EstSUsersGuide/EstimateSUsersGuide.htm',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new (\%metadata);
}

sub calc_chao1 {
    my $self = shift;
    my %args = @_;

    my $label_hash = $args{label_hash_all};

    my ($f1, $f2, $n) = (0, 0, 0);  #  singletons and doubletons

    foreach my $abundance (values %$label_hash) {
        if ($abundance == 1) {
            $f1 ++;
        }
        elsif ($abundance == 2) {
            $f2 ++;
        }
        $n += $abundance;
    }

    my $richness = scalar keys %$label_hash;
    #  correction factors
    my $cn1 = $n ? ($n - 1) / $n : 1;  #  avoid divide by zero issues with empty sets
    my $cn2 = $cn1 ** 2;

    my $chao_formula = 2;
    my $chao_partial = 0;
    my $variance;
    #  flags to use variance formaulae from EstimateS website
    my $variance_uses_eq8 = !$f1;  #  no singletons
    my $variance_uses_eq7;

    #  if $f1 == $f2 == 0 then the partial is zero.
    if ($f1) {
        if ($f2) {      #  one or more doubletons
            $chao_partial = $f1 ** 2 / (2 * $f2);
            my $f12_ratio = $f1 / $f2;
            $variance     = $f2 * (   ($cn1 * $f12_ratio ** 2) / 2
                                    +  $cn2 * $f12_ratio ** 3
                                    + ($cn2 * $f12_ratio ** 4) / 4);
        }
        elsif ($f1 > 1) {   #  no doubletons, but singletons
            $chao_partial      = $f1 * ($f1 - 1) / 2;
            $variance_uses_eq7 = 1;  # need the chao score to estimate this variance
        }
        else {
            #  if only one singleton and no doubletons then the estimate stays zero
            $variance_uses_eq8 = 1;
            $chao_formula      = 0;
        }
    }
    
    $chao_partial *= $cn1;

    my $chao = $richness + $chao_partial;
    
    if ($variance_uses_eq7) {
        $variance = $cn1 * ($f1 * ($f1 - 1)) / 2
                  + $cn2 *  $f1 * (2 * $f1 - 1)**2 / 4
                  - $cn2 *  $f1 ** 4 / 4 / $chao;
        #$chao_formula = 0;
    }
    elsif ($variance_uses_eq8) {
        my %sums;
        foreach my $freq (values %$label_hash) {
            $sums{$freq} ++;
        }
        my ($part1, $part2);
        foreach my $i (keys %sums) {
            my $f = $sums{$i};
            #say "$i $f";
            $part1 += $f * (exp (-$i) - exp (-2 * $i));
            $part2 += $i * exp (-$i) * $f;
        }
        $variance = $n ? $part1 - $part2 ** 2 / $n : 0;
        $chao_formula = 0;
    }

    $variance = max (0, $variance);

    #  and now the confidence interval
    my $ci_scores = $self->_calc_chao_confidence_intervals (
        F1 => $f1,
        F2 => $f2,
        chao_score => $chao,
        richness   => $richness,
        variance   => $variance,
        label_hash => $label_hash,
    );

    my $chao_meta = {
        VARIANCE_FORMULA => $variance_uses_eq7 ? 7 :
                            $variance_uses_eq8 ? 8 : 6,
        CHAO_FORMULA     => $chao_formula,
        CI_FORMULA       => $variance_uses_eq8 ? 14 : 13,
    };

    my %results = (
        CHAO1_ESTIMATE => $chao,
        CHAO1_F1_COUNT => $f1,
        CHAO1_F2_COUNT => $f2,
        CHAO1_SE       => sqrt ($variance),
        CHAO1_VARIANCE => $variance,
        CHAO1_UNDETECTED => $chao_partial,
        CHAO1_CI_LOWER => $ci_scores->{ci_lower},
        CHAO1_CI_UPPER => $ci_scores->{ci_upper},
        CHAO1_META     => $chao_meta,
    );

    return wantarray ? %results : \%results;    
}


sub get_metadata_calc_chao2 {
    my %metadata = (
        description     => 'Chao2 species richness estimator (incidence based)',
        name            => 'Chao2',
        type            => 'Richness estimators',
        pre_calc        => 'calc_abc2',
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            CHAO2_ESTIMATE  => {
                description => 'Chao2 index',
                reference   => 'NEEDED',
                formula     => [],
            },
            CHAO2_Q1_COUNT    => {
                description => 'Number of uniques in the sample',
            },
            CHAO2_Q2_COUNT    => {
                description => 'Number of duplicates in the sample',
            },
            CHAO2_VARIANCE    => {
                description => 'Variance of the Chao2 estimator',
            },
            CHAO2_SE          => {
                description => 'Standard error of the Chao2 estimator [= sqrt (variance)]',
            },
            CHAO2_CI_LOWER    => {
                description => 'Lower confidence interval for the Chao2 estimate',
            },
            CHAO2_CI_UPPER    => {
                description => 'Upper confidence interval for the Chao2 estimate',
            },
            CHAO2_UNDETECTED  => {
                description   => 'Estimated number of undetected species',
            },
            CHAO2_META        => {
                description => 'Metadata indicating which formulae were used in the '
                            . 'calculations. Numbers refer to EstimateS equations at '
                            . 'http://viceroy.eeb.uconn.edu/EstimateS/EstimateSPages/EstSUsersGuide/EstimateSUsersGuide.htm',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

#  very similar to chao1 - could refactor common code
sub calc_chao2 {
    my $self = shift;
    my %args = @_;

    my $label_hash = $args{label_hash_all};
    my $R = $args{element_count_all};

    my ($Q1, $Q2) = (0, 0);  #  singletons and doubletons

    foreach my $freq (values %$label_hash) {
        if ($freq == 1) {
            $Q1 ++;
        }
        elsif ($freq == 2) {
            $Q2 ++;
        }
    }

    my $richness = scalar keys %$label_hash;
    my $c1 = $R ? ($R - 1) / $R : 1;
    my $c2 = $c1 ** 2;

    my $chao_partial = 0;
    my $variance;

    #  flags to use variance formaulae from EstimateS website
    my $variance_uses_eq12 = !$Q1;  #  no uniques
    my $variance_uses_eq11;

    my $chao_formula = 4;  #  eq 2 from EstimateS

    #  if $f1 == $f2 == 0 then the partial is zero.
    if ($Q1) {
        if ($Q2) {      #  one or more doubletons
            $chao_partial = $Q1 ** 2 / (2 * $Q2);
            my $Q12_ratio = $Q1 / $Q2;
            $variance     = $Q2 * (  $Q12_ratio ** 2 * $c1 / 2
                                   + $Q12_ratio ** 3 * $c2
                                   + $Q12_ratio ** 4 * $c2 / 4);
        }
        elsif ($Q1 > 1) {   #  no doubletons, but singletons
            $chao_partial = $Q1 * ($Q1 - 1) / 2;
            $variance_uses_eq11 = 1;
        }
        elsif ($Q1) {
            $variance_uses_eq12 = 1;
            $chao_formula       = 0;
        }
        #  if only one singleton and no doubletons then chao stays zero
    }

    $chao_partial *= $c1;

    my $chao = $richness + $chao_partial;

    if ($variance_uses_eq11) {
        $variance = $c1 * ($Q1 * ($Q1 - 1)) / 2
                  + $c2 * ($Q1 * (2 * $Q1 - 1) ** 2) / 4
                  - $c2 *  $Q1 ** 4 / 4 / $chao;
    }
    elsif ($variance_uses_eq12) {  #  same structure as eq8 - could refactor
        my %sums;
        foreach my $freq (values %$label_hash) {
            $sums{$freq} ++;
        }
        my ($part1, $part2);
        while (my ($i, $Q) = each %sums) {
            $part1 += $Q * (exp (-$i) - exp (-2 * $i));
            $part2 += $i *  exp (-$i) * $Q;
        }
        $variance = $R ? ($part1 - $part2 ** 2 / $R) : 0;
        $chao_formula = 0;
    }

    #  could use ($variance &&= ...) if speed ever becomes an issue here
    if (defined $variance) {
        $variance = max (0, $variance);
    }

    #  and now the confidence interval
    my $ci_scores = $self->_calc_chao_confidence_intervals (
        F1 => $Q1,
        F2 => $Q2,
        chao_score => $chao,
        richness   => $richness,
        variance   => $variance,
        label_hash => $label_hash,
    );

    my $chao_meta = {
        VARIANCE_FORMULA => $variance_uses_eq11 ? 11 :
                            $variance_uses_eq12 ? 12 : 10,
        CHAO_FORMULA     => $chao_formula,
        CI_FORMULA       => $variance_uses_eq12 ? 14 : 13,
    };

    my %results = (
        CHAO2_ESTIMATE => $chao,
        CHAO2_Q1_COUNT => $Q1,
        CHAO2_Q2_COUNT => $Q2,
        CHAO2_VARIANCE => $variance,
        CHAO2_SE       => sqrt ($variance),
        CHAO2_UNDETECTED => $chao_partial,
        CHAO2_CI_LOWER => $ci_scores->{ci_lower},
        CHAO2_CI_UPPER => $ci_scores->{ci_upper},
        CHAO2_META     => $chao_meta,
    );

    return wantarray ? %results : \%results;    
}


sub _calc_chao_confidence_intervals {
    my $self = shift;
    my %args = @_;
    
    my $f1 = $args{F1};
    my $f2 = $args{F2};
    my $chao     = $args{chao_score};
    my $richness = $args{richness};
    my $variance = $args{variance};
    my $label_hash = $args{label_hash};

    #  and now the confidence interval
    my ($lower, $upper);
    if (($f1 && $f2) || ($f1 > 1)) {
        my $T = $chao - $richness;
        my $K;
        eval {
            no warnings qw /numeric uninitialized/;
            $K = exp ($z_for_ci * sqrt (log (1 + $variance / $T ** 2)));
            $lower = $richness + $T / $K;
            $upper = $richness + $T * $K;
        };
    }
    else {
        my $P = 0;
        my %sums;
        foreach my $freq (values %$label_hash) {
            $sums{$freq} ++;
        }
        #  set CIs to undefined if we only have singletons/uniques
        if ($richness && ! (scalar keys %sums == 1 && exists $sums{1})) {
            while (my ($f, $count) = each %sums) {
                $P += $count * exp (-$f);
            }
            $P /= $richness;
            my $part1 = $richness / (1 - $P);
            my $part2 = $z_for_ci * sqrt ($variance) / (1 - $P);
            $lower = max ($richness, $part1 - $part2);
            $upper = $part1 + $part2;
        }
    }

    my %results = (
        ci_lower => $lower,
        ci_upper => $upper,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_ace {
    my %metadata = (
        description     => 'Abundance Coverage-based Estimator os species richness',
        name            => 'ACE',
        type            => 'Richness estimators',
        pre_calc        => 'calc_abc3',
        uses_nbr_lists  => 1,  #  how many lists it must have
        reference       => 'needed',
        indices         => {
            ACE_ESTIMATE => {
                description => 'ACE score',
            },
            ACE_SE => {
                description => 'ACE standard error',
            },
            ACE_VARIANCE => {
                description => 'ACE variance',
            },
            ACE_CI_UPPER => {
                description => 'ACE upper confidence interval estimate',
            },
            ACE_CI_LOWER => {
                description => 'ACE lower confidence interval estimate',
            },
            ACE_UNDETECTED  => {
                description => 'Estimated number of undetected species',
            },
            ACE_INFREQUENT_COUNT => {
                description => 'Count of infrequent species',
            },
            ACE_ESTIMATE_USED_CHAO => {
                description => 'Set to 1 when ACE cannot be calculated '
                             . 'and so Chao1 estimate is used',
            }
        },
    );

    return $metadata_class->new (\%metadata);
}


my %ace_ice_remap = (
    ACE_ESTIMATE   => 'ICE_ESTIMATE',
    ACE_SE         => 'ICE_SE',
    ACE_VARIANCE   => 'ICE_VARIANCE',
    ACE_CI_UPPER   => 'ICE_CI_UPPER',
    ACE_CI_LOWER   => 'ICE_CI_LOWER',
    ACE_UNDETECTED => 'ICE_UNDETECTED',
    ACE_INFREQUENT_COUNT => 'ICE_INFREQUENT_COUNT',
    ACE_ESTIMATE_USED_CHAO => 'ICE_ESTIMATE_USED_CHAO',
);

sub calc_ace {
    my $self = shift;
    my %args = @_;

    my $label_hash = $args{label_hash_all};

    my %results = (
        ACE_ESTIMATE_USED_CHAO => 0,
    );

    #  Only the gamma differs between the two
    #  (apart from the inputs)
    my $calc_ice = $args{calc_ice};
    my $t = $args{EL_COUNT_NONEMPTY_ALL};

    my %f_rare;
    my $S_abundants = 0;
    my $S_rare      = 0;
    my $f1     = 0;
    my $n_rare = 0;
    my $richness = scalar keys %$label_hash;
    my %all_freqs;  #  all taxa

    foreach my $freq (values %$label_hash) {
        $all_freqs{$freq}++;
        if ($freq <= 10) {
            $f_rare{$freq} ++;
            $n_rare += $freq;
            $S_rare ++;
            if ($freq == 1) {
                $f1 ++;
            }
        }
        else {
            $S_abundants ++;
        }
    }

    #  single sample loc for ICE 
    #  or ACE and all samples are singletons
    #  or no labels
    if (   !$richness
        || ($calc_ice && $t <= 1)
        || ($f1 == $richness)
        ) {
        @results{keys %ace_ice_remap} = undef;
        $results{ACE_INFREQUENT_COUNT} = $S_rare;
        $results{ACE_ESTIMATE} = $richness;
        $results{ACE_ESTIMATE_USED_CHAO} = 0;
        return wantarray ? %results : \%results;
    }

    #  if no rares or no singletons or all rares are singletons
    #  then use Chao1 or Chao2 as they handle such cases
    #  while the ACE/ICE code does not (e.g divide by zero errors)
    #  This is broadly consistent with EstimateS.
    if (!$n_rare || !$f1 || $f1 == $n_rare) {
        $results{ACE_INFREQUENT_COUNT} = $S_rare;
        $results{ACE_ESTIMATE_USED_CHAO} = 1;
        my $tmp_results;
        my $pfx = 'ACE';
        if ($calc_ice) {
            $tmp_results = $self->calc_chao2(%args);
            $pfx = 'ICE';
        }
        else {
            $tmp_results = $self->calc_chao1(%args);
        }
        foreach my $key (keys %$tmp_results) {
            next if $key =~ /(?:META|[QF][12]_COUNT)$/;
            my $new_key = $key;
            $new_key =~ s/^CHAO\d/$pfx/;
            $results{$new_key} = $tmp_results->{$key};
        }
        return wantarray ? %results : \%results;
    }

    my $C_ace = 1 - $f1 / $n_rare;

    my ($a1, $a2);  #  $a names from SpadeR
    for my $i (1 .. 10) {
        next if !$f_rare{$i};
        $a1 += $i * ($i-1) * $f_rare{$i};
        $a2 += $i * $f_rare{$i};
    }

    my $gamma_rare_hat_square;
    if ($calc_ice) {
        #  Correction factor for C_ace from
        #  https://github.com/AnneChao/SpadeR::SpecInciModelh.R
        #  Seems undocumented as it is not in the cited refs,
        #  but we'll use it under the assumption that Chao's code is canonical.
        my $A = 1;
        if ($f_rare{1}) {
            if ($f_rare{2}) {
                $A = 2 * $f_rare{2} / (($t-1) * $f_rare{1} + 2 * $f_rare{2});
            }
            else {
                $A = 2 / (($t-1) * ($f_rare{1} - 1) + 2);
            }
        }
        $C_ace = 1 - ($f1 / $n_rare) * (1 - $A);
        $gamma_rare_hat_square = !$C_ace  #  avoid divide by zero
             ? 0
             : ($S_rare / $C_ace)
               * $t  / ($t - 1)  
               * $a1 / $a2 / ($a2 - 1)
               - 1;
    }
    else {
        $gamma_rare_hat_square = !$C_ace  #  avoid divide by zero
            ? 0
            : ($S_rare / $C_ace)
               * $a1 / $a2 / ($a2 - 1)
               - 1;
    }
    $gamma_rare_hat_square = max ($gamma_rare_hat_square, 0);

    my $S_ace = $S_abundants
              + $S_rare / $C_ace
              + $f1 / $C_ace * $gamma_rare_hat_square;

    my $cv = sqrt $gamma_rare_hat_square;
    
    my $variance_method = $calc_ice ? '_get_ice_variance' : '_get_ace_variance';

    my $variance = $self->$variance_method (
        freq_counts => \%all_freqs,
        f_rare      => \%f_rare,
        cv     => $cv,
        n_rare => $n_rare,
        C_rare => $C_ace,
        S_rare => $S_rare,
        s_estimate => $S_ace,
        t      => $t,
    );
    my $se = sqrt $variance;
    
    my $ci_vals = $self->_calc_ace_confidence_intervals (
        freq_counts => \%all_freqs,
        variance    => $variance,
        s_estimate  => $S_ace,
        richness    => $richness,
        label_hash  => $label_hash,
    );

    my %partial_results = (
        ACE_ESTIMATE => $S_ace,
        ACE_SE    => $se,
        ACE_UNDETECTED => $S_ace - $richness,
        ACE_VARIANCE   => $variance,
        ACE_CI_LOWER   => $ci_vals->{ci_lower},
        ACE_CI_UPPER   => $ci_vals->{ci_upper},
        ACE_INFREQUENT_COUNT => $S_rare,
    );
    @results{keys %partial_results} = values %partial_results;

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_ice {
    my %metadata = (
        description     => 'Incidence Coverage-based Estimator of species richness',
        name            => 'ICE',
        type            => 'Richness estimators',
        pre_calc        => [qw /calc_abc2 calc_nonempty_elements_used/],
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            ICE_ESTIMATE => {
                description => 'ICE score',
            },
            ICE_SE => {
                description => 'ICE standard error',
            },
            ICE_VARIANCE => {
                description => 'ICE variance',
            },
            ICE_CI_UPPER => {
                description => 'ICE upper confidence interval estimate',
            },
            ICE_CI_LOWER => {
                description => 'ICE lower confidence interval estimate',
            },
            ICE_UNDETECTED  => {
                description => 'Estimated number of undetected species',
            },
            ICE_INFREQUENT_COUNT => {
                description => 'Count of infrequent species',
            },
            ICE_ESTIMATE_USED_CHAO => {
                description => 'Set to 1 when ICE cannot be calculated '
                             . 'and so Chao2 estimate is used',
            }

        },
    );

    return $metadata_class->new (\%metadata);
}

sub calc_ice {
    my $self = shift;
    my %args = @_;

    my $tmp_results = $self->calc_ace (%args, calc_ice => 1);
    my %results;
    foreach my $ace_key (keys %$tmp_results) {
        my $ice_key = $ace_key;
        $ice_key =~ s/^ACE/ICE/;
        $results{$ice_key} = $tmp_results->{$ace_key};
    };

    return wantarray ? %results : \%results;
}

#  almost identical to _get_ice_variance but integrating the two 
#  would prob result in more complex code
sub _get_ace_variance {
    my $self = shift;
    my %args = @_;

    my $freq_counts = $args{freq_counts};

    #  precalculate the differentials and covariances
    my (%diff, %cov);
    my @sorted = sort {$a <=> $b} keys %$freq_counts;
    foreach my $i (@sorted) {
        $diff{$i} = $self->_get_ace_differential (%args, f => $i);
        foreach my $j (@sorted) {
            $cov{$i}{$j}
              //= $cov{$j}{$i}
              //= $self->_get_ace_ice_cov (%args, i => $i, j => $j);
            last if $i == $j;
        }
    }

    my $var_ace = 0;
    foreach my $i (keys %$freq_counts) {
        foreach my $j (keys %$freq_counts) {
            my $partial
                = $diff{$i} * $diff{$j} * $cov{$i}{$j};
            $var_ace += $partial;
        }
    }

    $var_ace ||= undef;

    return $var_ace;
}

sub _get_ice_variance {
    my $self = shift;
    my %args = @_;

    my $freq_counts = $args{freq_counts};

    #  precalculate the differentials and covariances
    my (%diff, %cov);
    my @sorted = sort {$a <=> $b} keys %$freq_counts;
    foreach my $i (@sorted) {
        $diff{$i} = $self->_get_ice_differential (%args, f => $i);
        foreach my $j (@sorted) {
            $cov{$i}{$j}
              //= $cov{$j}{$i}
              //= $self->_get_ace_ice_cov (%args, i => $i, j => $j);
            last if $i == $j;
        }
    }

    my $var_ice = 0;
    foreach my $i (keys %$freq_counts) {
        foreach my $j (keys %$freq_counts) {
            my $partial
                = $diff{$i} * $diff{$j} * $cov{$i}{$j};
            $var_ice += $partial;
        }
    }

    $var_ice ||= undef;

    return $var_ice;
}

#  common to ACE and ICE
sub _get_ace_ice_cov {
    my ($self, %args) = @_;
    my ($i, $j, $s_ice) = @args{qw/i j s_estimate/};
    my $Q = $args{freq_counts};

    return $i == $j
      ? $Q->{$i} * (1 - $Q->{$i} / $s_ice)
      : -1 * $Q->{$i} * $Q->{$j} / $s_ice;
}


sub _get_ice_differential {
    my $self = shift;
    my %args = @_;
    
    my $k = 10;  #  later we will make this an argument

    my $q = $args{q} // $args{f};

    return 1 if $q > $k;

    my $CV_infreq_h = $args{cv};
    my $freq_counts = $args{freq_counts};
    my $n_infreq    = $args{n_rare};
    my $C_infreq    = $args{C_rare};  #  get from gamma calcs
    my $D_infreq    = $args{S_rare};  #  richness of labels with sample counts < $k
    my $Q           = $args{f_rare};
    my $t           = $args{t};

    my @u = (1..$k);

    $n_infreq //=
        sum
        map  {$_ * $freq_counts->{$_}}
        grep {$_ < $k}
        keys %$freq_counts;

    my $si = sum map {$_ * ($_-1) * ($Q->{$_} // 0)} @u;

    my ($Q1, $Q2) = @$Q{1,2};
    $Q1 //= 0;
    $Q2 //= 0;

    my ($d, $dc_infreq);

    if ($CV_infreq_h != 0) {
        if ($q == 1) {
            $dc_infreq =
              -1 * (
                    $n_infreq * (($t - 1) * $Q1 + 2 * $Q2) * 2 * $Q1 * ($t - 1)
                 - ($t - 1) * $Q1**2 * (($t - 1) * ($Q1 + $n_infreq) + 2 * $Q2)
                 )
              / ($n_infreq * (($t - 1) * $Q1 + 2 * $Q2)) ** 2;

            $d = ($C_infreq - $D_infreq * $dc_infreq) / $C_infreq ** 2
                + $t / ($t - 1)
                  * ($C_infreq**2*$n_infreq*($n_infreq - 1)
                        * ($D_infreq * $si + $Q1 * $si)
                        - $Q1 * $D_infreq * $si *
                        (2 * $C_infreq * $dc_infreq
                         * $n_infreq * ($n_infreq - 1)
                         + $C_infreq ** 2
                         * ($n_infreq - 1)
                         + $C_infreq ** 2
                         * $n_infreq
                         )
                    ) / $C_infreq ** 4 / $n_infreq ** 2 / ($n_infreq - 1) ** 2
                - ($C_infreq - $Q1 * $dc_infreq) / $C_infreq**2;
        }
        elsif ($q == 2){
            $dc_infreq
              = -( -($t - 1) * $Q1**2 *
                  (2 * ($t - 1) * $Q1 + 2 * ($n_infreq + 2 * $Q2))
                )
                /
                ($n_infreq * (($t - 1) * $Q1 + 2 * $Q2))**2;

            $d = ($C_infreq - $D_infreq * $dc_infreq)
                / $C_infreq**2
              + $t / ($t - 1)
              * ($C_infreq**2 * $n_infreq * ($n_infreq - 1) * $Q1 * ($si + 2 * $D_infreq) - $Q1 * $D_infreq * $si *
                             (2 * $C_infreq * $dc_infreq * $n_infreq * ($n_infreq - 1) + $C_infreq**2 * 2 * ($n_infreq - 1) + $C_infreq**2 * $n_infreq * 2)
                )
              / $C_infreq**4 / $n_infreq**2 / ($n_infreq - 1)**2
              - ( -$Q1 * $dc_infreq) / $C_infreq**2;
        }
        else {
            $dc_infreq =
              - ( - ($t - 1) * $Q1**2 * (($t - 1) * $Q1 * $q + 2 * $Q2 * $q))
              / ($n_infreq * (($t - 1) * $Q1 + 2 * $Q2))**2;

            $d = ($C_infreq - $D_infreq * $dc_infreq) / $C_infreq**2
              + $t/($t - 1)
              * ($C_infreq**2 * $n_infreq * ($n_infreq - 1) * $Q1 * ($si + $q * ($q - 1) * $D_infreq) - $Q1 * $D_infreq * $si
                * (2 * $C_infreq * $dc_infreq * $n_infreq * ($n_infreq - 1)
                   + $C_infreq**2 * $q * ($n_infreq - 1)
                   + $C_infreq**2 * $n_infreq * $q
                  )
              )
              / $C_infreq**4 / $n_infreq**2 / ($n_infreq - 1)**2
              - ( - $Q1 * $dc_infreq) / $C_infreq**2;
        }
    }
    else {
        if ($q == 1) {
            $dc_infreq
              = -1 *
                ($n_infreq * (($t - 1) * $Q1 + 2 * $Q2) * 2 * $Q1 * ($t - 1)
                 - ($t - 1) * $Q1**2 * (($t - 1) * ($Q1 + $n_infreq) + 2 * $Q2)
                )
              / ($n_infreq * (($t - 1) * $Q1 + 2 * $Q2))**2;
        }
        elsif ($q == 2) {
            $dc_infreq
              = -1 *
                ( -1 * ($t - 1) * $Q1**2 *
                  (2 * ($t - 1) * $Q1 + 2 * ($n_infreq + 2 * $Q2))
                )
              / ($n_infreq * (($t - 1) * $Q1 + 2 * $Q2))**2;
        }
        else {
            $dc_infreq
             =  -1 *
                ( -1 * ($t - 1) * $Q1**2 * (($t - 1) * $Q1 * $q + 2 * $Q2 * $q))
              / ($n_infreq * (($t - 1) * $Q1 + 2 * $Q2))**2;
        }
        $d = ($C_infreq - $D_infreq * $dc_infreq) / $C_infreq**2;
    }
    
    return $d;
}

sub _get_ace_differential {
    my $self = shift;
    my %args = @_;
    
    my $k = 10;  #  later we will make this an argument

    my $f = $args{f};

    return 1 if $f > $k;

    my $cv_rare_h   = $args{cv};
    my $n_rare      = $args{n_rare};
    my $c_rare      = $args{C_rare};  #  get from gamma calcs
    my $D_rare      = $args{S_rare};  #  richness of labels with sample counts < $k
    my $F           = $args{freq_counts};
    my $t           = $args{t};

    my @u = (1..$k);

    $n_rare //=
        sum
        map  {$_ * $F->{$_}}
        grep {$_ <= $k}
        keys %$F;

    my $si = sum map {$_ * ($_-1) * ($F->{$_} // 0)} @u;

    my $f1 = $F->{1};
    my $d;

    if ($cv_rare_h != 0) {
        if ($f == 1) {
            $d = (1 - $f1 / $n_rare + $D_rare * ($n_rare - $f1) / $n_rare**2)
                 / (1 - $f1/$n_rare)**2
                +
                (
                 (1 - $f1/$n_rare)**2 * $n_rare * ($n_rare - 1)
                   * ($D_rare * $si + $f1 * $si)
                   - $f1 * $D_rare * $si
                   * (-2 * (1 - $f1 / $n_rare) * ($n_rare - $f1) / $n_rare**2
                      * $n_rare * ($n_rare - 1)
                      + (1 - $f1/$n_rare)**2*(2*$n_rare - 1)
                     )
                )
                / (1 - $f1/$n_rare)**4 / $n_rare**2 / ($n_rare - 1)**2
                  - (1 - $f1 / $n_rare + $f1 * ($n_rare - $f1)
                     / $n_rare**2)
                  / (1 - $f1 / $n_rare)**2;
        }
        else {
            $d = (1 - $f1 / $n_rare - $D_rare * $f * $f1 / $n_rare**2)
                     / (1 - $f1 / $n_rare)**2
                  + (
                     (1 - $f1 / $n_rare)**2
                      * $n_rare * ($n_rare - 1) * $f1 *
                      ($si + $D_rare * $f * ($f - 1))
                      - $f1 * $D_rare * $si *
                        (2 * (1 - $f1 / $n_rare) * $f1 * $f / $n_rare**2
                         * $n_rare * ($n_rare - 1)
                         + (1 - $f1 / $n_rare)**2 * $f * ($n_rare - 1)
                         + (1 - $f1 / $n_rare)**2 * $n_rare * $f
                        )
                    )
                  / (1 - $f1/$n_rare)**4 / ($n_rare)**2 / ($n_rare - 1)**2
                  + ($f * $f1**2 / $n_rare**2)
                  / (1 - $f1 / $n_rare)**2;
        }
    }
    else {
        if ($f == 1) {
            $d = (1 - $f1 / $n_rare + $D_rare * ($n_rare - $f1) / $n_rare**2)
               / (1 - $f1 / $n_rare)**2;
        }
        else {
            $d = (1 - $f1 / $n_rare - $D_rare * $f * $f1 / $n_rare**2)
               / (1 - $f1 / $n_rare)**2;
        }
    }

    return $d;
}


sub _calc_ace_confidence_intervals {    
    my $self = shift;
    my %args = @_;

    my $estimate = $args{s_estimate};
    my $richness = $args{richness};
    my $variance = $args{variance};
    my $label_hash  = $args{label_hash};
    my $freq_counts = $args{freq_counts};

    #  and now the confidence interval
    my ($lower, $upper);

    #  SpadeR treats values this close to zero as zero
    if (($estimate - $richness) >= 0.00001) {
        my $T = $estimate - $richness;
        my $K = exp ($z_for_ci * sqrt (log (1 + $variance / $T**2)));
        $lower = $richness + $T / $K;
        $upper = $richness + $T * $K;
    }
    else {
        my ($part1, $part2, $P) = (0, 0, 0);
        foreach my $f (keys %$freq_counts) {
            $part1 += $freq_counts->{$f} * (exp(-$f) - exp(-2*$f));
            $part2 += $f * exp (-$f) * $freq_counts->{$f};
            $P     += $freq_counts->{$f} * exp (-$f) / $richness;
        }
        my $n = sum values %$label_hash;
        my $var_obs = $part1 - $part2**2 / $n;  # should be passed as an arg?
#say "var_obs is the same as the variance argument\n" if $var_obs == $variance;
#say "$n $richness $P $var_obs $part1 $part2";
        $lower = max($richness, $richness / (1 - $P) - $z_for_ci * sqrt($var_obs) / (1 - $P));
        $upper = $richness / (1 - $P) + $z_for_ci * sqrt($var_obs) / (1 - $P);
    }

    my %results = (
        ci_lower => $lower,
        ci_upper => $upper,
    );

    return wantarray ? %results : \%results;
}
1;

__END__

=head1 NAME

Biodiverse::Indices::EstimateS

=head1 SYNOPSIS

  use Biodiverse::Indices;

=head1 DESCRIPTION

Species richness estimation indices for the Biodiverse system,
based on the EstimateS (L<http://purl.oclc.org/estimates>)
and SpadeR (L<https://github.com/AnneChao/SpadeR>) software.

It is inherited by Biodiverse::Indices and not to be used on it own.

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
