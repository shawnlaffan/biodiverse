#  Inter-event interval stats
#  A plugin for the biodiverse system and not to be used on its own.

package Biodiverse::Indices::Numeric_Labels;
use strict;
use warnings;

use Carp;

our $VERSION = '0.16';

use Biodiverse::Statistics;

my $stats_package = 'Biodiverse::Statistics';

######################################################
#
#  routines to calculate statistics from numeric labels
#

#  get a statistics::descriptive2 object from the numeric labels.
#  used in two or more subs, so this will save extra calcs

sub get_metadata_get_numeric_label_stats_object {

    my %arguments = (
        name           => 'get_numeric_label_stats_object',
        description    => "Generate a summary statistics object from a set of numeric labels\n"
                        . 'Accounts for multiple occurrences by using calc_abc3.',
        pre_calc       => [qw /calc_abc3/],
        uses_nbr_lists => 1,  #  how many sets of lists it must have
    );

    return wantarray ? %arguments : \%arguments;
}

sub get_numeric_label_stats_object {
    my $self = shift;
    my %args = @_;

    if (! $self->get_param ('BASEDATA_REF')->labels_are_numeric) {
        my %results = (numeric_label_stats_object => undef);
        return wantarray ? %results : \%results;
    }

    my @data;
    while (my ($key, $count) = each %{$args{label_hash_all}}) {
        push @data, ($key) x $count;  # add as many as there are samples
    }

    my $stats = $stats_package->new;
    $stats->add_data (\@data);

    $stats->sort_data;

    my %results = (numeric_label_stats_object => $stats);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_numeric_label_stats {

    my %arguments = (
        name =>  'Numeric label statistics',
        description => "Calculate summary statistics from a set of numeric labels.\n"
                     . "Weights by samples so multiple occurrences are accounted for.\n",
        type => 'Numeric Labels',
        pre_calc => [qw /get_numeric_label_stats_object/],
        uses_nbr_lists => 1,  #  how many sets of lists it must have
        indices => {
            NUM_SD      => {description => 'Standard deviation',},
            NUM_MEAN    => {description => 'Mean',},
            NUM_N       => {description => 'Number of samples',},
            NUM_RANGE   => {description => 'Range (max - min)',},
            NUM_SKEW    => {description => 'Skewness',},
            NUM_KURT    => {description => 'Kurtosis',},
            NUM_CV      => {description => 'Coefficient of variation (NUM_SD / NUM_MEAN)',},
            NUM_MIN     => {description => 'Minimum value (zero quantile)',},
            NUM_MAX     => {description => 'Maximum value (100th quantile)',},
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_numeric_label_stats {
    my $self = shift;
    my %args = @_;

    my $stats = $args{numeric_label_stats_object};

    my %results;

    if (! defined $stats) {
        return wantarray ? %results : \%results;  #  safe exit, just in case
    }

    # supppress divide by zero and other undef value warnings
    no warnings qw /uninitialized numeric/;

    #  this approach looks awkward,
    #  but appears to make things faster
    #  as there are fewer redundant calculations
    my $n = $stats->count;
    if ($n) {
        my $cv = eval {$stats->standard_deviation / $stats->mean};

        %results = (
            NUM_MEAN  => $stats->mean,
            NUM_SD    => $stats->standard_deviation,
            NUM_N     => $n,
            NUM_RANGE => $stats->sample_range,
            NUM_SKEW  => $stats->skewness,
            NUM_KURT  => $stats->kurtosis,
            NUM_CV    => $cv,
            NUM_MIN   => $stats->min,
            NUM_MAX   => $stats->max,
        );
    }
    else {
        %results = (
            NUM_MEAN  => undef,
            NUM_SD    => undef,
            NUM_N     => $n,
            NUM_RANGE => undef,
            NUM_SKEW  => undef,
            NUM_KURT  => undef,
            NUM_CV    => undef,
            NUM_MIN   => undef,
            NUM_MAX   => undef,
        );
    }

    return wantarray
            ? %results
            : \%results;

}

sub get_metadata_calc_numeric_label_other_means {

    my %arguments = (
        name            =>  'Numeric label harmonic and geometric means',
        description     => "Calculate geometric and harmonic means for a set of numeric labels.\n",
        type            => 'Numeric Labels',
        pre_calc        => [qw /get_numeric_label_stats_object/],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            NUM_HMEAN => {description => 'Harmonic mean',  },
            NUM_GMEAN => {description => 'Geometric mean', },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_numeric_label_other_means {
    my $self = shift;
    my %args = @_;

    my $stats = $args{numeric_label_stats_object};

    my %results;

    if (! defined $stats) {
        return wantarray ? %results : \%results;  #  safe exit, just in case
    }

    # supppress divide by zero and other undef value warnings
    no warnings qw /uninitialized numeric/;

    my $n = $stats->count;
    if ($n) {
        my $gmean = eval {$stats->geometric_mean};
        my $hmean = eval {$stats->harmonic_mean};
        %results = (
            NUM_HMEAN => $hmean,
            NUM_GMEAN => $gmean,
        );
    }
    else {
        %results = (
            NUM_HMEAN => undef,
            NUM_GMEAN => undef,
        );
    }

    return wantarray
            ? %results
            : \%results;

}

sub get_metadata_calc_numeric_label_quantiles {

    my %Q;  #  all the other quartiles
    for (my $value = 5; $value <= 95; $value += 5) {
        $Q{sprintf 'NUM_Q%03u', $value} = {description => $value . 'th percentile'};
    }

    my %arguments = (
        name            => 'Numeric label quantiles',
        description     => "Calculate quantiles from a set of numeric labels.\n"
                         . "Weights by samples so multiple occurrences are accounted for.\n",
        type            => 'Numeric Labels',
        pre_calc        => [qw /get_numeric_label_stats_object/],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => \%Q,
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_numeric_label_quantiles {
    my $self = shift;
    my %args = @_;

    my $stats = $args{numeric_label_stats_object};

    my %results;

    if (! defined $stats) {
        return wantarray ? %results : \%results;  #  safe exit, just in case
    }

    #  get the quantiles
    #my $null;
    for (my $quantile = 5; $quantile <= 95; $quantile += 5) {
        my $label = sprintf "NUM_Q%03u", $quantile;
        $results{$label} = $stats->percentile($quantile);
    }

    return wantarray
            ? %results
            : \%results;
}

sub get_metadata_calc_numeric_label_data {

    my %arguments = (
        name            =>  'Numeric label data',
        description     => qq{The underlying data used for the numeric labels stats, as an array.\n}
                           . q{For the hash form, use the ABC3_LABELS_ALL index from the }
                           . q{'Sample count lists' calculation.},
        type            => 'Numeric Labels',
        pre_calc        => [qw /get_numeric_label_stats_object/],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            NUM_DATA_ARRAY => {
                description => 'Numeric label data in array form.  '
                               . 'Multiple occurrences are repeated '
                               . 'based on their sample counts.',
                TYPE        => 'list',
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_numeric_label_data {
    my $self = shift;
    my %args = @_;

    my $stats = $args{numeric_label_stats_object};

    my $data = defined $stats
             ? [ $stats->get_data ]
             : [ ];

    my %results = (
        NUM_DATA_ARRAY => $data,
    );

    return wantarray ? %results : \%results;

}

sub get_metadata_calc_numeric_label_dissimilarity {
    my $self = shift;

    my @values_as_for = (
        'where values are as for ',
        'NUMD\_ABSMEAN',
    );

    my %arguments = (
        name            => 'Numeric label dissimilarity',
        description     => q{Compare the set of numeric labels in one neighbour set with those in another. },
        type            => 'Numeric Labels',
        pre_calc        => 'calc_abc3',
        uses_nbr_lists  => 2,  #  how many sets of lists it must have
        indices => {
            NUMD_ABSMEAN       => {
                description => 'Mean absolute dissimilarity of labels in set 1 to those in set 2.',
                cluster     => 1,
                formula     => [
                    '= \frac{\sum_{l_{1i} \in L_1} \sum_{l_{2j} \in L_2} abs (l_{1i} - l_{2j})(w_{1i} \times w_{2j})}{n_1 \times n_2}',
                    'where',
                    'L1',
                    ' and ',
                    'L2',
                    ' are the labels in neighbour sets 1 and 2 respectively, and ',
                    'n1',
                    ' and ',
                    'n2',
                    ' are the sample counts in neighbour sets 1 and 2'
                ],
            },
            NUMD_MEAN       => {
                description => 'Mean dissimilarity of labels in set 1 to those in set 2.',
                cluster     => 1,
                formula     => [
                    '= \frac{\sum_{l_{1i} \in L_1} \sum_{l_{2j} \in L_2} (l_{1i} - l_{2j})(w_{1i} \times w_{2j})}{n_1 \times n_2}',
                    @values_as_for,
                ],
            },
            NUMD_VARIANCE   => {
                description => 'Variance of the dissimilarity values, set 1 vs set 2.',
                cluster     => 1,
                formula     => [
                    '= \frac{\sum_{l_{1i} \in L_1} \sum_{l_{2j} \in L_2} (l_{1i} - l_{2j})^2(w_{1i} \times w_{2j})}{n_1 \times n_2}',
                    @values_as_for,
                ],
            },
            NUMD_COUNT   => {
                description => 'Count of comparisons used.',
                formula     => [
                    '= n1 * n2',
                    @values_as_for,
                ],
            },
        },
    );

    return wantarray ? %arguments : \%arguments;    
}

#  compare the set of labels in one neighbour set with those in another
sub calc_numeric_label_dissimilarity {
    my $self = shift;
    my %args = @_;
    
    if (! $self->get_param ('BASEDATA_REF')->labels_are_numeric) {
        my %results = (NUMD_IS_INVALID => 1);
        return wantarray ? %results : \%results;
    }

    my $label_list1     = $args{label_hash1};
    my $label_list2     = $args{label_hash2};

    my ($sumX, $sum_absX, $sumXsqr, $count) = (undef, undef, undef, 0);

    #  should look into using PDL to handle this, as it will be much, much faster
    #  (but it will use more memory, which will be bad for large label lists)
    BY_LABEL1:
    while (my ($label1, $count1) = each %{$label_list1}) {

        BY_LABEL2:
        while (my ($label2, $count2) = each %{$label_list2}) {

            my $value = $label1 - $label2;
            my $joint_count = $count1 * $count2;

            #  tally the stats
            my $x = $value * $joint_count;
            $sumX     += $x;
            $sum_absX += abs($x);
            $sumXsqr  += $value ** 2 * $joint_count;
            $count    += $joint_count;
        }
    }

    my %results;
    {
        #  suppress these warnings within this block
        no warnings qw /uninitialized numeric/;

        $results{NUMD_MEAN}     = eval {$sumX / $count};
        $results{NUMD_ABSMEAN}  = eval {$sum_absX / $count};
        $results{NUMD_VARIANCE} = eval {$sumXsqr / $count};
        $results{NUMD_COUNT}    = $count;
    }

    return wantarray ? %results : \%results;
}

sub _get_metadata_calc_numeric_label_rao_qe {
    return;
}

sub _calc_numeric_label_rao_qe {
    return;
}

#sub numerically {$a <=> $b};

1;

__END__

=head1 NAME

Biodiverse::Indices::Numeric_Labels

=head1 SYNOPSIS

  use Biodiverse::Indices;

=head1 DESCRIPTION

Numeric label indices for the Biodiverse system.
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
