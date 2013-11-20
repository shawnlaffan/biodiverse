package Biodiverse::Indices::RichnessEstimation;
use strict;
use warnings;
use Carp;

our $VERSION = '0.19';


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
            }
        },
    );

    return wantarray ? %metadata : \%metadata;
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

    my $chao1_partial = 0;
    my $variance;

    #  if $f1 == $f2 == 0 then the partial is zero.
    if ($f1) {
        if ($f2) {      #  one or more doubletons
            $chao1_partial = $f1 ** 2 / (2 * $f2);
            my $f12_ratio  = $f1 / $f2;
            $variance      = $f2 * (  $f12_ratio ** 2 / 2
                                    + $f12_ratio ** 3
                                    + $f12_ratio ** 4 / 4);
        }
        elsif ($f1 > 1) {   #  no doubletons, but singletons
            $chao1_partial = $f1 * ($f1 - 1) / 2;
        }
        #  if only one singleton and no doubletons then the estimate stays zero
    }

    $chao1_partial *= ($n - 1) / $n;

    my $chao1 = $richness + $chao1_partial;

    my %results = (
        CHAO1          => $chao1,
        CHAO1_F1_COUNT => $f1,
        CHAO1_F2_COUNT => $f2,
        CHAO1_VARIANCE => $variance,
        CHAO1_UNDETECTED => $chao1_partial,
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
            CHAO2_UNDETECTED  => {
                description   => 'Estiumated nmber of undetected species',
            },
        },
    );

    return wantarray ? %metadata : \%metadata;
}

#  very similar to chao1 - could refactor common code
sub calc_chao2 {
    my $self = shift;
    my %args = @_;

    my $label_hash = $args{label_hash_all};
    my $R = $args{element_count_all};

    my $correction = ($R - 1) / $R;

    my ($Q1, $Q2) = (0, 0, 0);  #  singletons and doubletons

    foreach my $freq (values %$label_hash) {
        if ($freq == 1) {
            $Q1 ++;
        }
        elsif ($freq == 2) {
            $Q2 ++;
        }
        #$n += $freq;
    }

    my $richness = scalar keys %$label_hash;

    my $chao2_partial = 0;
    my $variance;

    #  if $f1 == $f2 == 0 then the partial is zero.
    if ($Q1) {
        if ($Q2) {      #  one or more doubletons
            $chao2_partial = $Q1 ** 2 / (2 * $Q2);
            my $Q12_ratio  = $Q1 / $Q2;
            $variance      = $Q2 * (  $Q12_ratio ** 2 * $correction / 2
                                    + $Q12_ratio ** 3 * $correction ** 2
                                    + $Q12_ratio ** 4 * $correction ** 2 / 4);
        }
        elsif ($Q1 > 1) {   #  no doubletons, but singletons
            $chao2_partial = $Q1 * ($Q1 - 1) / 2;
        }
        #  if only one singleton and no doubletons then it stays zero
    }

    $chao2_partial *= $correction;
    my $chao2 = $richness + $chao2_partial;

    my %results = (
        CHAO2          => $chao2,
        CHAO2_Q1_COUNT => $Q1,
        CHAO2_Q2_COUNT => $Q2,
        CHAO2_VARIANCE => $variance,
        CHAO2_UNDETECTED => $chao2_partial,
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
