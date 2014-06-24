package Biodiverse::Indices::RichnessEstimation;
use strict;
use warnings;
use Carp;

use List::Util qw /max min/;

our $VERSION = '0.99_001';

my $metadata_class = 'Biodiverse::Metadata::Indices';


sub get_metadata_calc_chao1 {
    my %metadata = (
        description     => 'Chao1 species richness estimator (abundance based)',
        name            => 'Chao1',
        type            => 'Richness estimators',
        pre_calc        => 'calc_abc3',
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            CHAO1              => {
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
    my $correction = ($n - 1) / $n;

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
            $variance     = $f2 * (  $f12_ratio ** 2 / 2
                                    + $f12_ratio ** 3
                                    + $f12_ratio ** 4 / 4);
        }
        elsif ($f1 > 1) {   #  no doubletons, but singletons
            $chao_partial      = $f1 * ($f1 - 1) / 2;
            $variance_uses_eq7 = 1;  # need the chao score to estimate this variance
        }
        else {
            #  if only one singleton and no doubletons then the estimate stays zero
            $variance_uses_eq8 = 1;
            $chao_formula      = undef;
        }
    }
    
    $chao_partial *= ($n - 1) / $n;

    my $chao = $richness + $chao_partial;
    
    if ($variance_uses_eq7) {
        $variance = $correction      * ($f1 * ($f1 - 1)) / 2
                  + $correction ** 2 * ($f1 * (2 * $f1 - 1)) ** 2
                  - $correction ** 2 *  $f1 ** 4 / (4 * $chao);
        $chao_formula = undef;
    }
    elsif ($variance_uses_eq8) {
        my %sums;
        foreach my $freq (values %$label_hash) {
            $sums{$freq} ++;
        }
        my ($part1, $part2);
        while (my ($i, $f) = each %sums) {
            $part1 += $f * (exp -$i - exp (-2 * $i));
            $part2 += $i * exp (-$i) * $f;
        }
        $variance = $part1 - $part2 ** 2 / $n;
        $chao_formula = undef;
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
        CHAO1          => $chao,
        CHAO1_F1_COUNT => $f1,
        CHAO1_F2_COUNT => $f2,
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
            CHAO2              => {
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
                description => 'Variance of the Chao1 estimator',
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

    my ($Q1, $Q2) = (0, 0, 0);  #  singletons and doubletons

    foreach my $freq (values %$label_hash) {
        if ($freq == 1) {
            $Q1 ++;
        }
        elsif ($freq == 2) {
            $Q2 ++;
        }
    }

    my $richness = scalar keys %$label_hash;
    my $correction = ($R - 1) / $R;

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
            my $Q12_ratio  = $Q1 / $Q2;
            $variance      = $Q2 * (  $Q12_ratio ** 2 * $correction / 2
                                    + $Q12_ratio ** 3 * $correction ** 2
                                    + $Q12_ratio ** 4 * $correction ** 2 / 4);
        }
        elsif ($Q1 > 1) {   #  no doubletons, but singletons
            $chao_partial = $Q1 * ($Q1 - 1) / 2;
            $variance_uses_eq11 = 1;
        }
        elsif ($Q1) {
            $variance_uses_eq12 = 1;
            $chao_formula       = undef;
        }
        #  if only one singleton and no doubletons then chao stays zero
    }

    $chao_partial *= $correction;
    my $chao = $richness + $chao_partial;

    
    if ($variance_uses_eq11) {
        $variance = $correction      * ($Q1 * ($Q1 - 1)) / 2
                  + $correction ** 2 * ($Q1 * (2 * $Q1 - 1) ** 2) / 4
                  - $correction ** 2 *  $Q1 ** 4 / (4 * $chao);
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
        $variance = $part1 - $part2 ** 2 / $R;
        $chao_formula = undef;
    }
    
    $variance = max (0, $variance);

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
        CHAO2          => $chao,
        CHAO2_Q1_COUNT => $Q1,
        CHAO2_Q2_COUNT => $Q2,
        CHAO2_VARIANCE => $variance,
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
    if ($f1 && $f2) {
        my $T = $chao - $richness;
        my $K;
        eval {
            no warnings qw /numeric uninitialized/;
            $K = exp (1.96 * sqrt (log (1 + $variance / $T ** 2)));
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
        if (! (scalar keys %sums == 1 && exists $sums{1})) {
            while (my ($f, $count) = each %sums) {
                $P += $count * exp -$f;
            }
            $P /= $richness;
            my $part1 = $richness / (1 - $P);
            my $part2 = 1.96 * sqrt ($variance) / (1 - $P);
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
        indices         => {
            ACE_SCORE => {
                description => 'ACE score',
                reference   => 'NEEDED',
                formula     => [],
            },
            
        },
    );

    return $metadata_class->new (\%metadata);
}


sub calc_ace {
    my $self = shift;
    my %args = @_;

    my $label_hash = $args{label_hash_all};

    #  Only the gamma differs between the two
    #  (apart from the inputs)
    my $calc_ice = $args{calc_ice};

    my %f_rare;
    my $S_abundants = 0;
    my $S_rare      = 0;
    my $f1     = 0;
    my $n_rare = 0;

    foreach my $freq (values %$label_hash) {
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

    my $C_ace = $n_rare ? (1 - $f1 / $n_rare) : undef;

    if (!$C_ace) {
        my %results = (
            ACE_SCORE => undef,
        );
        return wantarray ? %results : \%results;
    }

    my $fnurble;  #  need to use a better name here...
    for my $i (2 .. 10) {
        next if !$f_rare{$i};
        $fnurble += $i * ($i-1) * $f_rare{$i};
    }

    my $gamma;
    if ($calc_ice) {
        $gamma = ($S_rare  /  $C_ace)
               * ($n_rare  / ($n_rare - 1))
               * ($fnurble /  $n_rare ** 2) 
               - 1;
    }
    else {
        $gamma = ($S_rare  /  $C_ace)
               * ($fnurble / ($n_rare * ($n_rare - 1)))
               - 1;
    }
    $gamma = max ($gamma, 0);

    my $S_ace = $S_abundants
              + $S_rare / $C_ace
              + $f1 / $C_ace * $gamma ** 2;

    my %results = (
        ACE_SCORE => $S_ace,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_ice {
    my %metadata = (
        description     => 'Incidence Coverage-based Estimator of species richness',
        name            => 'ICE',
        type            => 'Richness estimators',
        pre_calc        => 'calc_abc2',
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            ICE_SCORE => {
                description => 'ICE score',
                reference   => 'NEEDED',
                formula     => [],
            },
            
        },
    );

    return $metadata_class->new (\%metadata);
}

sub calc_ice {
    my $self = shift;
    my %args = @_;
    
    my $tmp_results = $self->calc_ace (%args, calc_ice => 1);
    my %results = (
        ICE_SCORE => $tmp_results->{ACE_SCORE},
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
based on the EstimateS software (L<http://purl.oclc.org/estimates>).
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
