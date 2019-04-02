package Biodiverse::Indices::Numeric_Labels;
use strict;
use warnings;
use 5.010;

use List::Util qw /sum min max/;
#use List::MoreUtils qw /apply pairwise/;

use Carp;

our $VERSION = '2.99_002';

use Biodiverse::Statistics;

my $stats_package = 'Biodiverse::Statistics';

my $metadata_class = 'Biodiverse::Metadata::Indices';

######################################################
#
#  routines to calculate statistics from numeric labels
#

sub labels_are_numeric {
    my $self = shift;
    my $bd = $self->get_basedata_ref;
    return $bd->labels_are_numeric;
}

#  get a statistics::descriptive2 object from the numeric labels.
#  used in two or more subs, so this will save extra calcs

sub get_metadata_get_numeric_label_stats_object {

    my %metadata = (
        name           => 'get_numeric_label_stats_object',
        description    => "Generate a summary statistics object from a set of numeric labels\n"
                        . 'Accounts for multiple occurrences by using calc_abc3.',
        pre_calc       => [qw /calc_abc3/],
        pre_conditions => ['labels_are_numeric'],
        uses_nbr_lists => 1,  #  how many sets of lists it must have
        indices        => {
            numeric_label_stats_object => {
                description => 'Numeric labels stats object',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_numeric_label_stats_object {
    my $self = shift;
    my %args = @_;

    if (! $self->get_basedata_ref->labels_are_numeric) {
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

    my %metadata = (
        name           =>  'Numeric label statistics',
        description    => "Calculate summary statistics from a set of numeric labels.\n"
                        . "Weights by samples so multiple occurrences are accounted for.\n",
        type           => 'Numeric Labels',
        pre_calc       => [qw /get_numeric_label_stats_object/],
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

    return $metadata_class->new(\%metadata);
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

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_numeric_label_other_means {

    my %metadata = (
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

    return $metadata_class->new(\%metadata);
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

    my %metadata = (
        name           => 'Numeric label quantiles',
        description    => "Calculate quantiles from a set of numeric labels.\n"
                        . "Weights by samples so multiple occurrences are accounted for.\n",
        type           => 'Numeric Labels',
        pre_calc       => [qw /get_numeric_label_stats_object/],
        uses_nbr_lists => 1,  #  how many sets of lists it must have
        indices        => \%Q,
    );

    return $metadata_class->new(\%metadata);
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

    my %metadata = (
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
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
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

    my %metadata = (
        name           => 'Numeric label dissimilarity',
        description    => q{Compare the set of numeric labels in one neighbour set with those in another. },
        type           => 'Numeric Labels',
        pre_calc       => 'calc_abc3',
        uses_nbr_lists => 2,  #  how many sets of lists it must have
        pre_conditions => ['labels_are_numeric'],
        indices        => {
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
            NUMD_VARIANCE   => {
                description => 'Variance of the dissimilarity values (mean squared deviation), set 1 vs set 2.',
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

    return $metadata_class->new(\%metadata);    
}

#  compare the set of labels in one neighbour set with those in another
sub calc_numeric_label_dissimilarity {
    my $self = shift;
    my %args = @_;
    
    if (! $self->get_param ('BASEDATA_REF')->labels_are_numeric) {
        my %results = (NUMD_IS_INVALID => 1);
        return wantarray ? %results : \%results;
    }

    my $list1 = $args{label_hash1};
    my $list2 = $args{label_hash2};

    #  handle empty assemblages (neighbour sets)
    if (! scalar keys %$list1 || ! scalar keys %$list2) {
        my %results = (
            NUMD_ABSMEAN  => undef,
            NUMD_VARIANCE => undef,
            NUMD_COUNT    => undef,
        );
        return wantarray ? %results : \%results;
    }


    #  make %$l1 the shorter, as it is used in the loop with more calculations
    if (scalar keys %$list1 > scalar keys %$list2) {  
        $list1 = $args{label_hash2};
        $list2 = $args{label_hash1};
    }

    my ($sum_absX, $sum_X_sqr, $sum_wts) = (undef, undef, 0);

    my @val1_arr = sort {$a <=> $b} keys %$list1;
    my @val2_arr = sort {$a <=> $b} keys %$list2;

    # thanks to quadratics, we can avoid all the inner loops for the variance
    my ($ssq_v2, $sum_v2, $sum_wt2, @cum_sum_arr, @cum_wt2_arr);
    for my $val2 (@val2_arr) {
        my $wt2  =  $list2->{$val2};
        my $wtd_val = $val2 * $wt2;
        $sum_v2  += $wtd_val;
        $ssq_v2  += $val2 ** 2 * $wt2;
        $sum_wt2 += $wt2;
        push @cum_sum_arr, $sum_v2;
        push @cum_wt2_arr, $sum_wt2;
    }
    my $val2_min  = $val2_arr[0];
    my $val2_max  = $val2_arr[-1];
    my $val2_mean = $sum_v2 / $sum_wt2;

    my $i = 0;

  BY_LABEL1:
    foreach my $val1 (@val1_arr) {
        my $wt1 = $list1->{$val1};

        ###  the variance code
        $sum_X_sqr  += $wt1 * ($ssq_v2 - 2 * $val1 * $sum_v2 + $sum_wt2 * $val1**2);

        ###  sum the wts
        $sum_wts  += $wt1 * $sum_wt2;

        ####  the mean diff code
        #  if we are outside the bounds of @val2 then it is a one-sided comparison
        if ($val1 < $val2_min || $val1 > $val2_max) {
            my $diff = abs ($val1 - $val2_mean);
            $sum_absX += $wt1 * $sum_wt2 * $diff;
            next BY_LABEL1;
        }

        #  If we get here then it is two-sided, check above and below.  
        #  First find out where we are in the sorted sequence.
        my $j = min ($i, $#val2_arr);
        for ($j .. $#val2_arr) {
            if ($val1 < $val2_arr[$i]) {
                $i--;  #  allow for non-ties
                last;
            }
            last if $val1 == $val2_arr[$i];
            $i++;            
        }

        #  now get the mean absolute difference above and below, and sum them
        my $cum_sum_i = $cum_sum_arr[$i];
        my $n_le = $cum_wt2_arr[$i];
        my $n_gt = $sum_wt2 - $n_le;
        my $mean_lt = $cum_sum_arr[$i] / ($n_le || 1);
        my $mean_gt = ($sum_v2 - $cum_sum_i) / ($n_gt || 1);
        my $diff_lt = abs ($val1 - $mean_lt) * $n_le;
        my $diff_gt = abs ($val1 - $mean_gt) * $n_gt;

        $sum_absX += $wt1 * ($diff_lt + $diff_gt);
    }

    my %results;
    {
        #  suppress these warnings within this block
        no warnings qw /uninitialized numeric/;

        $results{NUMD_ABSMEAN}  = eval {$sum_absX / $sum_wts};
        $results{NUMD_VARIANCE} = eval {$sum_X_sqr / $sum_wts};
        $results{NUMD_COUNT}    = $sum_wts;
    }

    return wantarray ? %results : \%results;
}

sub _get_metadata_calc_numeric_label_rao_qe {
    return;
}

sub _calc_numeric_label_rao_qe {
    return;
}

sub get_metadata__get_num_label_global_summary_stats {
    my $descr = 'Global summary stats for numeric labels';

    my %metadata = (
        description     => $descr,
        name            => $descr,
        type            => 'Numeric Labels',
        indices         => {
            NUM_LABELS_GLOBAL_SUMMARY_STATS => {
                description => $descr,
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub _get_num_label_global_summary_stats {
    my $self = shift;
    my %args = @_;

    my $bd = $self->get_basedata_ref;

    if (! $self->get_basedata_ref->labels_are_numeric) {
        my %results = (NUM_LABELS_GLOBAL_SUMMARY_STATS => undef);
        return wantarray ? %results : \%results;
    }

    my $lb = $bd->get_labels_ref;

    my $labels = $bd->get_labels;

    my @data;
    foreach my $label (@$labels) {
        my $count = $lb->get_sample_count (element => $label);
        push @data, ($label) x $count;  # add as many as there are samples
    }

    #my $stats_object = $stats_package->new;
    #$stats_object->add_data (\@data);
    #
    #my %stats_hash;
    #foreach my $stat (qw /mean sum standard_deviation count/) { 
    #    $stats_hash{$stat} = $stats_object->$stat;
    #}

    my ($sumx, $sumxx, $n, $mean, $sd, $variance);
    foreach my $label (@$labels) {
        my $count = $lb->get_sample_count (element => $label);
        $sumx  += $count * $label;
        $sumxx += $count * $label**2;
        $n     += $count;
    }
    
    if ($n) {
        $mean     = $sumx / $n;
        $variance = $sumxx - $n * $mean**2;
        $variance /= $n - 1;  #  won't work for non-integer weights
        $variance = max ($variance, 0);
        $sd       = sqrt $variance;
    }

    my %stats_hash = (
        mean  => $mean,
        sum   => $sumx,
        count => $n,
        standard_deviation => $sd,
    );

    my %results = (NUM_LABELS_GLOBAL_SUMMARY_STATS => \%stats_hash);
    return wantarray ? %results : \%results;
}


sub get_metadata_calc_num_labels_gistar {
    my $self = shift;

    my $desc = 'Getis-Ord Gi* statistic for numeric labels across both neighbour sets';
    my $ref  = 'Getis and Ord (1992) Geographical Analysis. https://doi.org/10.1111/j.1538-4632.1992.tb00261.x';

    my %metadata = (
        description     => $desc,
        name            => 'Numeric labels Gi* statistic',
        type            => 'Numeric Labels',
        pre_calc        => ['get_numeric_label_stats_object'],
        pre_calc_global => [qw /_get_num_label_global_summary_stats/],
        uses_nbr_lists  => 1,
        reference       => $ref,
        indices         => {
            NUM_GISTAR => {
                description => 'List of Gi* scores',
                lumper      => 1,
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_num_labels_gistar {
    my $self = shift;
    my %args = @_;

    my $global_hash   = $args{NUM_LABELS_GLOBAL_SUMMARY_STATS};
    my $local_object = $args{numeric_label_stats_object};

    my $res;
    if ($local_object) {
        $res = $self->_get_gistar_score(
            global_data => $global_hash,
            local_data  => $local_object,
        );
    }

    my %results = (NUM_GISTAR => $res);

    return wantarray ? %results : \%results;
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
