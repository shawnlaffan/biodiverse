#  Inter-event interval stats
#  A plugin for the biodiverse system and not to be used on its own.

package BiodiverseX::Indices::IEI;
use strict;
use warnings;
use Ref::Util qw { :all };

use Carp;

our $VERSION = '4.99_009';

use Biodiverse::Statistics;
my $stats_package = 'Biodiverse::Statistics';

my $metadata_class = 'Biodiverse::Metadata::Indices';

my $EMPTY_STRING = q{};

sub get_metadata_calc_iei_data {

    my %metadata = (
        name            => 'Inter-event interval statistics data',
        description     => 'The underlying data used for the IEI stats.',
        type            => 'Inter-event Interval Statistics',
        pre_calc        => [qw /get_iei_stats_object/],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            IEI_DATA_ARRAY => {
                description => 'Interval data in array form.  Multiple occurrences are repeated ',
                type        => 'list',
            },
            IEI_DATA_HASH  => {
                description => "Interval data in hash form where the \n"
                               . "interval is the key and number of occurrences is the value",
                type        => 'list',
            },
            
        },
    );

    return $metadata_class->new(\%metadata);
}


#  purely an accessor method to get at the iei data
sub calc_iei_data {
    my $self = shift;
    my %args = @_;
    
    my $stats = $args{IEI_stats_object};
    
    my $data = defined $stats 
                ? [$stats->get_data]
                : [];

    my %results = (
        IEI_DATA_ARRAY => $data,
        IEI_DATA_HASH  => $args{IEI_interval_hash} || {},
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_iei_stats {
    my $self = shift;

    my %metadata = (
        name            => 'Inter-event interval statistics',
        description     => "Calculate summary statistics from a set of numeric "
                         . "labels that represent event times.\n"
                         . "Event intervals are calculated within groups, then aggregated "
                         . "across the neighbourhoods, and then summary stats are calculated.",
        type            => 'Inter-event Interval Statistics',
        pre_calc        => [qw /get_iei_stats_object/],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            IEI_SD      => {
                description => 'Standard deviation',
            },
            IEI_MEAN    => {
                description => 'Mean',
                cluster     => 1,
            },
            IEI_GMEAN   => {
                description => 'Geometric mean',
            },
            IEI_N       => {
                description => 'Number of samples',
            },
            IEI_RANGE   => {
                description => 'Range (max - min)',
            },
            IEI_SKEW    => {
                description => 'Skewness',
            }, 
            IEI_KURT    => {
                description => 'Kurtosis',
            },
            IEI_CV      => {
                description => 'Coefficient of variation (IEI_SD / IEI_MEAN)',
            },
            IEI_MIN     => {
                description => 'Minimum value (zero percentile)',
            },
            IEI_MAX     => {
                description => 'Maximum value (100th percentile)',
            },
        },
    );

    return $metadata_class->new(\%metadata);    
}

sub calc_iei_stats {
    my $self = shift;
    my %args = @_;
    
    my $stats = $args{IEI_stats_object};
    
    my %results;
    
    if (! defined $stats) {
        return wantarray ? %results : \%results;  #  safe exit, just in case
    }
    
    
    # supppress divide by zero and other undef value warnings
    no warnings qw /uninitialized numeric/;
    
    my $n = $stats->count;
    
    if ($n) {
        my $sd    = eval {$stats->standard_deviation};
        my $mean  = eval {$stats->mean};
        my $cv    = defined $sd ? $sd / $mean : undef;
        my $gmean = eval {$stats->geometric_mean};  #  put these here to trap some errors

        %results = (
            IEI_GMEAN   => $gmean,
            IEI_MEAN    => $mean,
            IEI_SD      => $sd,
            IEI_N       => $stats->count,
            IEI_RANGE   => $stats->sample_range,
            IEI_SKEW    => $stats->skewness,
            IEI_KURT    => $stats->kurtosis,
            IEI_CV      => $cv,
            IEI_MIN     => $stats->min,
            IEI_MAX     => $stats->max,
        );
    }
    #  statistics::descriptive uses a default mean of zero if no values - not what we want
    else {  
        %results = (
            IEI_GMEAN   => undef,
            IEI_MEAN    => undef,
            IEI_SD      => undef,
            IEI_N       => $n,
            IEI_RANGE   => undef,
            IEI_SKEW    => undef,
            IEI_KURT    => undef,
            IEI_CV      => undef,
            IEI_MIN     => undef,
            IEI_MAX     => undef,
        );
    }
    return wantarray
            ? %results
            : \%results;
    
}

sub get_metadata_get_iei_data_for_elements {
    my $self = shift;
    
    my %metadata = (
        name            => 'get_iei_data_for_elements',
        description     => "get the IEI data for a set of elements and cache them\n",
        pre_calc_global => [qw /get_iei_element_cache/],
        uses_nbr_lists  => 1,
        indices         => {
            IEI_DATA_BY_ELEMENT_AS_HASH  => {
                description => 'Data in hash form',
            },
            IEI_DATA_BY_ELEMENT_AS_ARRAY => {
                description => 'Data in array form',
            },
        }
    );

    return $metadata_class->new(\%metadata);
}

#  get the IEI data for a set of elements and cache them
#  the cache can be cleared later using cleanup_iei_element_cache
#  as a post_calc
sub get_iei_data_for_elements {
    my $self = shift;
    my %args = @_;
    
    my $bd = $self->get_basedata_ref;

    if (! $bd->labels_are_numeric) {
        my %results = (IEI_STATS_OBJECT => undef);
        return wantarray ? %results : \%results;  
    }

    croak "neither of args element_list1, element_list2 specified\n"
        if (   ! defined $args{element_list1}
            && ! defined $args{element_list2}
        );

    my $hash_cache  = $args{IEI_ELEMENT_HASH_CACHE};
    my $array_cache = $args{IEI_ELEMENT_ARRAY_CACHE};

    my %out_hash;
    my %out_array;

    my %element_check = (1 => {}, 2 => {});
    my %element_check_master;

    #  loop iter variables
    my ($listname, $iter, $label);

    #  work through the elements we've been fed and extract
    #  their labels and sample counts
    my %hash = (element_list1 => 1, element_list2 => 2);

    BY_LIST:
    while (($listname, $iter) = each (%hash)) {
        #print "$listname, $iter\n";
        next BY_LIST if ! defined $args{$listname};

        #  silently convert the hash to an array
        if (is_hashref($args{$listname})) {  
            $args{$listname} = [keys %{$args{$listname}}];
        }
        elsif (! ref ($args{$listname})) {
            croak "argument $listname is not a list ref\n";
        }

        my @checked_elements;

        BY_ELEMENT:
        foreach my $element (@{$args{$listname}}) {
            #  deal with lazy array refs pointing to
            #  longer lists than we have elements
            next BY_ELEMENT if ! defined $element;  

            my $interval_hash_sub  = {};  #  sub hash
            my $interval_array_sub = [];  #  and sub array

            #  get it if not cached
            if (! exists $hash_cache->{$element}) {
                my %labels
                    = $bd->get_labels_in_group_as_hash_aa ($element);
                my @sorted_labels = sort numerically keys %labels;

                #  add to the cache
                $hash_cache->{$element}  = $interval_hash_sub;
                $array_cache->{$element} = $interval_array_sub;

                #  need two events to have an interval
                if (scalar @sorted_labels > 1) {  
    
                    #  get the inter-event distances
                    my $last_label = shift @sorted_labels;

                    if ($labels{$last_label} > 1) {
                        my $zero_event_count = $labels{$last_label} - 1;
                        push @$interval_array_sub, ((0) x $zero_event_count);
                        $interval_hash_sub->{0} += $zero_event_count;
                    }

                    foreach my $label (@sorted_labels) {
                        my $event_length = $label - $last_label;
                        push @$interval_array_sub, $event_length;
                        $interval_hash_sub->{$event_length} ++;

                        if ($labels{$label} > 1) {
                            my $zero_event_count = $labels{$label} - 1;
                            push @$interval_array_sub, ((0) x $zero_event_count);
                            $interval_hash_sub->{0} += $zero_event_count;
                        }

                        $last_label = $label;
                    }
                }
            }
            else {  #  we have the cache
                $interval_hash_sub  = $hash_cache->{$element};
                $interval_array_sub = $array_cache->{$element};
            }

            $out_hash{$element}  = $interval_hash_sub;
            $out_array{$element} = $interval_array_sub;

            push @checked_elements, $element;
        }


        @{$element_check{$iter}}{@checked_elements}
            = (1) x @checked_elements;
        
        #  hash slice is faster than looping
        @element_check_master{@checked_elements}
            = (1) x scalar @checked_elements;
    }
    

    #  run some checks on the elements
    my $element_count_master = scalar keys %element_check_master;
    my $element_count1 = scalar keys %{$element_check{1}};
    my $element_count2 = scalar keys %{$element_check{2}};
    if ($element_count1 + $element_count2 > $element_count_master) {
        croak "[INDICES] DOUBLE COUNTING OF ELEMENTS IN get_iei_stats_object"
            . ", $element_count1 + $element_count2 > $element_count_master\n";        
    }
    
    my %results = (
        IEI_DATA_BY_ELEMENT_AS_HASH  => \%out_hash,
        IEI_DATA_BY_ELEMENT_AS_ARRAY => \%out_array,
    );
    
    return wantarray ? %results : \%results;
}


sub get_metadata_get_iei_stats_object {
    
    my %metadata = (
        name            => 'get_iei_stats_object',
        description     => "Generate a statistics object for an Inter-event Interval analysis\n"
                           . "Calculates intervals within each element and returns the overall list of intervals\n",
        pre_calc_global => [qw /get_iei_element_cache/],
        pre_calc        => [qw /get_iei_data_for_elements/],
        post_calc       => [qw /cleanup_iei_element_cache/],
        uses_nbr_lists  => 1,
    );
    
    return $metadata_class->new(\%metadata);
}

#  loop over the IEI data for each element and treat them
#  as an aggregate set of events
sub get_iei_stats_object {
    my $self = shift;
    my %args = @_;
    
    #  assume we are in a spatial or tree object first,
    #  or a basedata object otherwise
    my $bd = $self->get_basedata_ref;

    if (! $bd->labels_are_numeric) {
        my %results = (IEI_STATS_OBJECT => undef);
        return wantarray ? %results : \%results;  
    }

    #my $stats = $args{IEI_stats_object};
    my $hash_list   = $args{IEI_DATA_BY_ELEMENT_AS_HASH};
    my $array_list  = $args{IEI_DATA_BY_ELEMENT_AS_ARRAY};

    my @interval_array;  #  stores all the intervals as an array
    my %interval_hash;  #  same, but as a hash (for convenience more than anything else)
    
    BY_ELEMENT:
    foreach my $element (keys %$array_list) {

        my $interval_hash_sub  = {};  #  sub hash
        my $interval_array_sub = [];  #  and sub array
        
        my $array_this_el = $array_list->{$element};
        my $hash_this_el  = $hash_list->{$element};


        #  push the cached array onto the main array
        push @interval_array, @$array_this_el;
        #  and increment the main hash as appropriate
        foreach my $key (keys %$hash_this_el) {
            $interval_hash{$key} += $hash_this_el->{$key};
        }
    }

    
    my $stats = $stats_package->new;
    $stats->add_data (\@interval_array);
    
    $stats->sort_data;
    
    #my $x = $hash_cache;
    #  the hash saves extracting it from the stats object again later
    my %results = (
        IEI_stats_object  => $stats,
        IEI_interval_hash => \%interval_hash,  
    );
    
    return wantarray ? %results : \%results;
}

sub get_metadata_get_iei_element_cache {
    my $self = shift;

    my %metadata = (
        name        => 'get_iei_element_cache',
        description => 'Create a hash in which to cache the IEI lists for each element',
        indices     => {
            IEI_ELEMENT_ARRAY_CACHE => {
                description => 'The IEI array cache for each element',
            },
            IEI_ELEMENT_HASH_CACHE => {
                description => 'The IEI hash cache for each element',
            },
        },
    );
    
    return $metadata_class->new(\%metadata);
}


sub get_iei_element_cache {
    my $self = shift;
    my %args = @_;


    my %results = (
        IEI_ELEMENT_ARRAY_CACHE => {},
        IEI_ELEMENT_HASH_CACHE  => {},
    );

    return wantarray ? %results : \%results;
}

#  cleanup the element cache if appropriate
sub cleanup_iei_element_cache {
    my $self = shift;
    my %args = @_;

    my $hash_cache  = $args{IEI_ELEMENT_HASH_CACHE};
    my $array_cache = $args{IEI_ELEMENT_ARRAY_CACHE};
    my $results_are_recyclable          # param will be renamed at some stage
        = $self->get_param ('RESULTS_ARE_RECYCLABLE');

    print $EMPTY_STRING;

    #  clear the cache if needed
    if ($args{no_IEI_cache} || $args{no_cache} || $results_are_recyclable) {
        delete @{$hash_cache}{keys %$hash_cache};
        delete @{$array_cache}{keys %$array_cache};
    }

    return;
}

sub get_metadata_cleanup_iei_element_cache {
    my $self = shift;
    
    my %metadata = (
        name            => 'cleanup_iei_element_cache',
        description     => 'Clean up the IEI element cache',
        pre_calc_global => [qw /get_iei_element_cache/],
    );
    
    return $metadata_class->new(\%metadata);
}


#  summarise the IEI stats across the neighbourhood
#  hidden for now - incomplete
sub _calc_iei_summary_stats_per_nbrhood {
    my $self = shift;
    my %args = @_;
    
    my $hash_list   = $args{IEI_DATA_BY_ELEMENT_AS_HASH};
    my $array_list  = $args{IEI_DATA_BY_ELEMENT_AS_ARRAY};

    my @interval_array;  #  stores all the intervals as an array
    my %interval_hash;  #  same, but as a hash (for convenience more than anything else)
    
    my $summary_stats = $stats_package->new;
    
    #  list of arrays named by the function to be called
    my $stat_arrays = {
        mean                => [],
        standard_deviation  => [],
        count               => [],
        geometric_mean      => [],
        sample_range        => [],
        min                 => [],
        max                 => [],
    };

    #  remap the stat names
    my $remap = {
        mean                => 'MEAN',
        standard_deviation  => 'SD',
        count               => 'N',
        geometric_mean      => 'GMEAN',
        sample_range        => 'RANGE',
        min                 => 'MIN',
        max                 => 'MAX',
    };

    BY_ELEMENT:
    foreach my $element (keys %$array_list) {
        my $data = $array_list->{$element};

        next BY_ELEMENT if scalar @$data == 0;

        my $stats = $stats_package->new;
        $stats->add_data ($data);
        $stats->sort_data;

        FUNC:
        foreach my $stat_func (keys %$stat_arrays) {
            my $result = eval {$stats->$stat_func };
            next FUNC if not defined $result;
            push @{$stat_arrays->{$stat_func}}, $result;
        }
    }

    my %results;

    foreach my $stat (keys %$stat_arrays) {
        my $key = 'IEI_S_MEAN_' . $remap->{$stat};

        #  only calc if we have samples, but always do the sample count
        if ($stat eq 'count' || scalar @{$stat_arrays->{$stat}}) { 
            my $stats = $stats_package->new;
            $stats->add_data ($stat_arrays->{$stat});
            $results{$key} = eval {$stats->mean};
        }
        else {
            $results{$key} = undef;
        }
    }

    return wantarray ? %results : \%results;
}

sub _get_metadata_calc_iei_summary_stats_per_nbrhood {
    my $self = shift;
    
    my %metadata = (
        name            => 'Inter-event interval statistics summary stats',
        description     => "Calculate summary statistics of the IEI results across a neighbourhood\n"
                            . "IEI summary statistics are calculated for each group and then summarised"
                            . "across the neighbourhood",
        type            => 'Inter-event Interval Statistics',
        pre_calc        => [qw /get_iei_data_for_elements/],
        #pre_calc_global => [qw /get_iei_element_cache/],
        post_calc       => [qw /cleanup_iei_element_cache/],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            IEI_S_MEAN_SD    => {
                description => 'Mean of the standard deviations',
            },
            IEI_S_MEAN_MEAN    => {
                description => 'Mean of the means',
                cluster     => 1,
            },
            IEI_S_MEAN_GMEAN   => {
                description => 'Mean of the geometric means',
            },
            IEI_S_MEAN_N       => {
                description => 'Mean number of samples',
            },
            IEI_S_MEAN_RANGE   => {
                description => 'Mean range',
            },
            IEI_S_MEAN_MIN     => {
                description => 'Mean minimum value',
            },
            IEI_S_MEAN_MAX     => {
                description => 'Mean maximum value',
            },
        },
    );
    
    return $metadata_class->new(\%metadata);
}


sub numerically {$a <=> $b};

1;


__END__

=head1 NAME

Biodiverse::Indices::IEI

=head1 SYNOPSIS

  use Biodiverse::Indices;
  
=head1 DESCRIPTION

Inter-event interval indices for the Biodiverse system.
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
