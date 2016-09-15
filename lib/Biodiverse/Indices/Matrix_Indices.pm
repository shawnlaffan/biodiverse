#  Inter-event interval stats
#  A plugin for the biodiverse system and not to be used on its own.

package Biodiverse::Indices::Matrix_Indices;
use strict;
use warnings;

use Carp;

our $VERSION = '1.99_006';

#use Statistics::Descriptive;
#my $stats_class = 'Statistics::Descriptive::Full';

use Biodiverse::Statistics;
my $stats_class = 'Biodiverse::Statistics';

my $metadata_class = 'Biodiverse::Metadata::Indices';

######################################################
#
#  routines to calculate indices based on matrices
#

sub get_metadata_calc_matrix_stats {
    
    my %metadata = (
        name            => 'Matrix statistics',
        description     => 'Calculate summary statistics of matrix elements'
                            . ' in the selected matrix for labels found'
                            . " across both neighbour sets.\n"
                            . 'Labels not in the matrix are ignored.',
        type            => 'Matrix',
        required_args   => {matrix_ref => 1}, #  must be set for it to be used
        pre_calc        => 'calc_abc',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            MX_MEAN      => {description => 'Mean'},
            MX_SD        => {description => 'Standard deviation'},
            MX_N         => {description => 'Number of samples (matrix elements, not labels)'},
            MX_MEDIAN    => {description => 'Median'},
            MX_RANGE     => {description => 'Range (max-min)'},
            MX_MINVALUE  => {description => 'Minimum value'},
            MX_MAXVALUE  => {description => 'Maximum value'},
            MX_SKEW      => {description => 'Skewness'},
            MX_KURT      => {description => 'Kurtosis'},
            MX_PCT95     => {description => '95th percentile value'},
            MX_PCT05     => {description => '5th percentile value'},
            MX_PCT25     => {description => 'First quartile (25th percentile)'},
            MX_PCT75     => {description => 'Third quartile (75th percentile)'},
            MX_VALUES    => {
                description => 'List of the matrix values',
                type        => 'list'
            },
            MX_LABELS    => {
                description => 'List of the matrix labels in the neighbour sets',
                type        => 'list'
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_matrix_stats {
    my $self = shift;
    my %ABC = @_;  #  rest of args into a hash


    my $matrix = $ABC{matrix_ref};

    #  this will contain label_hash2 if element_list2 or label_list2  was specified
    my %label_list = %{$ABC{label_hash_all}};  

    #  we need to get the distance between two percentiles
    my @value_list;
    my %done;
    
    my $labels_in_matrix = $matrix->get_elements;
    my %tmp = %label_list;
    delete @tmp{keys %$labels_in_matrix};  #  get a list of those not in the matrix
    delete @label_list{keys %tmp};  #  these should be the ones in the matrix
    
    
    foreach my $label1 (keys %label_list) {
        foreach my $label2 (keys %label_list) {
            next if $done{$label2};

            my $value = $matrix->get_value (element1 => $label1, element2 => $label2);
            next if !defined $value;
            
            #$value = 0 if ! defined $value && $label1 eq $label2;
            
            push (@value_list, $value);
        }
        $done{$label1}++;
    }

    my $stats = $stats_class->new;
    $stats->add_data (\@value_list);

    $stats->sort_data;
    my $values_ref = [$stats->get_data];
    my $null;
    (my $mx_pct95, $null) = eval {$stats->percentile(95)};
    (my $mx_pct05, $null) = eval {$stats->percentile( 5)};
    (my $mx_pct25, $null) = eval {$stats->percentile(25)};
    (my $mx_pct75, $null) = eval {$stats->percentile(75)};

    #print $stats->count . "\t";

    my %results = (
        MX_MEAN     => $stats->mean,
        MX_SD       => $stats->standard_deviation,
        MX_N        => $stats->count,
        MX_MEDIAN   => $stats->median,
        MX_RANGE    => $stats->sample_range,
        MX_MINVALUE => $stats->min,
        MX_MAXVALUE => $stats->max,
        MX_SKEW     => $stats->skewness,
        MX_KURT     => $stats->kurtosis,
        MX_PCT95    => $mx_pct95,
        MX_PCT05    => $mx_pct05,
        MX_PCT25    => $mx_pct25,
        MX_PCT75    => $mx_pct75,
        MX_VALUES   => $values_ref,
        MX_LABELS   => \%label_list,
    );

    return wantarray
            ? %results
            : \%results;
}

sub get_metadata_calc_compare_dissim_matrix_values {
    my $self = shift;
    
    my %metadata = (
        name            => 'Compare dissimilarity matrix values',
        description     => q{Compare the set of labels in one neighbour set with those in another }
                           . q{using their matrix values. Labels not in the matrix are ignored. }
                           . q{This calculation assumes a matrix of dissimilarities }
                           . q{and uses 0 as identical, so take care).},
        type            => 'Matrix',
        pre_calc        => 'calc_abc',
        required_args   => ['matrix_ref'],
        uses_nbr_lists  => 2,  #  how many sets of lists it must have
        indices => {
            MXD_MEAN       => {
                description => 'Mean dissimilarity of labels in set 1 to those in set 2.',
                cluster     => 1,
            },
            MXD_VARIANCE   => {
                description => 'Variance of the dissimilarity values, set 1 vs set 2.',
                cluster     => 1,
            },
            MXD_COUNT   => {
                description => 'Count of comparisons used.',
            },
            MXD_LIST1   => {
                description => "List of the labels used from neighbour set 1 (those in the matrix).\n"
                             . "The list values are the number of times each label was used in the calculations.\n"
                             . "This will always be 1 for labels in neighbour set 1.",
                type        => 'list',
            },
            MXD_LIST2   => {
                description => "List of the labels used from neighbour set 2 (those in the matrix).\n"
                             . "The list values are the number of times each label was used in the calculations.\n"
                             . "This will equal the number of labels used from neighbour set 1.",
                type        => 'list',
            },
        },
    );  #  add to if needed
    
    return $metadata_class->new(\%metadata);
    
}

#  compare the set of labels in one neighbour set with those in another,
#  using their matrix values (assumes dissimilarities)
sub calc_compare_dissim_matrix_values {
    my $self = shift;
    my %args = @_;
    
    my $self_similarity = $args{self_similarity} || 0;
    
    my $label_list1     = $args{label_hash1};
    my $label_list2     = $args{label_hash2};
    
    my $matrix = $args{matrix_ref};

    my (%tmp, %tmp2);
    #  delete elements from label_list1 that are not in the matrix
    my $labels_in_matrix = $matrix -> get_elements;
    
    $label_list1 = $self -> get_list_intersection (
        list1 => [keys %$labels_in_matrix],
        list2 => [keys %$label_list1],
    );

    $label_list2 = $self -> get_list_intersection (
        list1 => [keys %$labels_in_matrix],
        list2 => [keys %$label_list2],
    );
    
    #  we need to get the distance between and across two groups
    my ($sum_X, $sum_X_sqr, $count) = (undef, undef, 0);
    #my ($totalSumX, $totalSumXsqr, $totalCount) = (undef, undef, 0);
    my (%list1_hash, %list2_hash);
    
    #my (%done, %compared, %centre_compared);
    BY_LABEL1:
    foreach my $label1 (@{$label_list1}) {
        $list1_hash{$label1} ++;  #  track the times it is used
        
        BY_LABEL2:
        foreach my $label2 (@{$label_list2}) {

            #next BY_LABEL2 if $done{$label2};  #  we've already compared these
            $list2_hash{$label2} ++;
            
            my $value = $matrix->get_value(
                element1 => $label1,
                element2 => $label2
            );
            
            #  trap self-self values not in matrix but don't override ones that are
            if (! defined $value) {
                $value = $self_similarity;
            }
            elsif ($label1 eq $label2) {
                $value = $self_similarity;
            }

            #  tally the stats
            $sum_X += $value;
            $sum_X_sqr += $value**2;
            $count ++;
            #$centre_compared{$label2} ++;

        }
        #$done{$label1}++;
    }
    
    #
    #@list1_hash{@{$label_list1}} = (1) x scalar @{$label_list1};
    #@list2_hash{@{$label_list2}} = (1) x scalar @{$label_list2};
    
    my %results;
    {
        #  suppress these warnings within this block
        no warnings qw /uninitialized numeric/;  
        
        $results{MXD_MEAN}      = eval {$sum_X / $count};
        $results{MXD_VARIANCE}  = eval {$sum_X_sqr / $count};
        $results{MXD_COUNT}     = $count;
        $results{MXD_LIST1}     = \%list1_hash;
        $results{MXD_LIST2}     = \%list2_hash;
    }
    
    return wantarray ? %results : \%results;
}

1;


__END__

=head1 NAME

Biodiverse::Indices::Matrix_Indices

=head1 SYNOPSIS

  use Biodiverse::Indices;
  
=head1 DESCRIPTION

Matrix indices for the Biodiverse system.
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
