package Biodiverse::Randomise::CurveBall;

use strict;
use warnings;
use 5.022;

our $VERSION = '5.0';

use Carp qw /croak/;

use experimental 'refaliasing';
use experimental 'declared_refs';
no warnings 'experimental::refaliasing';
no warnings 'experimental::declared_refs';

use Time::HiRes qw { time gettimeofday tv_interval };
use List::Unique::DeterministicOrder 0.003;
use Scalar::Util qw /blessed looks_like_number/;
use List::Util qw /max min/;
#use List::MoreUtils qw /bsearchidx/;
use Statistics::Sampler::Multinomial 1.00;
use Statistics::Sampler::Multinomial::Indexed 1.00;
use Hash::Util::Set qw /keys_difference/;
use POSIX qw /floor ceil/;

use Biodiverse::Metadata::Parameter;
my $parameter_rand_metadata_class = 'Biodiverse::Metadata::Parameter';


sub get_curveball_spatial_allocation_metadata {
    my $self = shift;

    my $spatial_condition_param = bless {
        name       => 'spatial_condition_for_swap_pairs',
        label_text => "Spatial condition\nto define a target swap group\nneighbourhood",
        default    => '# default is whole data set',
        type       => 'spatial_conditions',
        tooltip    => 'On selecting a first group, the second group to swap labels with '
            . 'will be selected within the specified neighbourhood. '
            . 'If left blank then any group can be selected.',
    }, $parameter_rand_metadata_class;

    return $spatial_condition_param;
}

sub get_metadata_rand_curveball {
    my $self = shift;

    my $hyperball = bless {
        name       => 'use_hypergeometric',
        label_text => 'Use hypergeometric sampler',
        default    => 0,
        type       => 'boolean',
        box_group  => 'Curveball',
        tooltip    =>
            'If true then a hypergeometric sampling approach will be used to determine how many labels to swap. '
                . 'This is currently slightly slower than the default approach.',
    }, $parameter_rand_metadata_class;

    my $maxswap = bless {
        name       => 'use_max_swap',
        label_text => 'Swap maximum labels',
        default    => 0,
        type       => 'boolean',
        box_group  => 'Curveball',
        tooltip    =>
            'If true then as many labels as possible will be swapped each iteration. '
                . 'The default approach swaps a random number in the interval [0, maxswaps].',
    }, $parameter_rand_metadata_class;

    my @parameters = (
        $self->get_curveball_spatial_allocation_metadata,
        $hyperball,
        $maxswap,
        $self->get_common_independent_swaps_metadata,
        $self->get_common_rand_metadata,
    );
    for (@parameters) {
        next if blessed $_;
        bless $_, $parameter_rand_metadata_class;
    }


    my %metadata = (
        parameters  => \@parameters,
        description => "Randomly swap labels across groups using an implementation "
            . "of the curveball algorithm "
            . "(Strona et al. 2014)\n",
    );

    return $self->metadata_class->new(\%metadata);
}

sub rand_curveball {
    my ($self, %args) = @_;

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');

    my $name = $self->get_param ('NAME');

    #  can't store MRMA objects to all output formats and then recreate
    my $rand = delete $args{rand_object};

    my $target_swap_count = $args{swap_count};
    my $max_swap_attempts = $args{max_swap_attempts};
    my $stop_on_all_swapped = $args{stop_on_all_swapped};
    #  Defaults are set below following
    #  Miklos & Podani (2004) Ecology, 85(1) 86–92:
    #  "Therefore, we suggest that the number of trials
    #  should be set such that the expected number of swaps
    #  equals twice the number of 1’s in the matrix. Given an
    #  initial matrix, both the number of checkerboard units
    #  and the number of possible 2 x 2 submatrices can be
    #  calculated, and their ratio can be used as estimation for
    #  the proportion of the successful trials."

    my $progress_bar = Biodiverse::Progress->new(no_gui_progress => $args{no_gui_progress});

    my $use_hyper    = !!$args{use_hypergeometric};
    my $use_max_swap = !!$args{use_max_swap};

    my $vcache = $self->get_volatile_cache;
    \my %sequence_cache  = $vcache->get_cached_href('CURVEBALL_PDL_SEQUENCES');
    \my %cum_hgeom_cache = $vcache->get_cached_href('CURVEBALL_PDL_HGEOM_CUM_SUMS');

    my %empty_groups;
    @empty_groups{$bd->get_empty_groups} = undef;
    my %empty_labels;
    @empty_labels{$bd->get_rangeless_labels} = undef;

    my @sorted_groups = sort grep {!exists $empty_groups{$_}} $bd->get_groups;
    my @sorted_labels = sort grep {!exists $empty_labels{$_}} $bd->get_labels;
    my $n_groups = scalar @sorted_groups;
    my $n_labels = scalar @sorted_labels;

    my (%lb_hash, %has_max_richness, %lb_gp_moved);
    my $non_zero_mx_cells = 0;  #  sum of richness and range scores
    foreach my $group (@sorted_groups) {
        my $label_hash = $bd->get_labels_in_group_as_hash_aa($group);
        $non_zero_mx_cells += scalar keys %$label_hash;
        $lb_hash{$group} = {%$label_hash};
        if ($bd->get_richness_aa ($group) == @sorted_labels) {
            #  cannot be swapped around
            $has_max_richness{$group}++;
        }
    }

    say "[RANDOMISE] Randomise using curveball algorithm for $n_labels labels from $n_groups groups";

    #  No need to consider groups that cannot be swapped out.
    #  Could use a binary search but this is only done once per iteration.
    if (keys %has_max_richness) {
        @sorted_groups = grep {!exists $has_max_richness{$_}} @sorted_groups;
        $n_groups = scalar @sorted_groups;
    }

    $progress_bar->reset;

    #  If we are running under spatial stratification then
    #  we cache on the main rand, not the stratified subset.
    my $caching_rand = $args{rand_object} // $self;
    my $cached_lists = $caching_rand->get_cached_value_dor_set_default_href ('RAND_CURVEBALL_LISTS');
    #  Go one level in, keyed by first group as sets are non-overlapping
    $cached_lists = $cached_lists->{$sorted_groups[0]};

    state $cache_key_sp_swap_list = 'SP_SWAP_LIST';
    state $cache_key_gps_w_nbrs   = 'GPS_WITH_NBRS';
    my (%sp_swap_list, @gps_with_nbrs);

    my $sp_conditions = $args{spatial_condition_for_swap_pairs};
    if (defined $sp_conditions) {
        if (my $cached_swap_list = $cached_lists->{$cache_key_sp_swap_list}) {
            \%sp_swap_list  = $cached_swap_list;
            \@gps_with_nbrs = $cached_lists->{$cache_key_gps_w_nbrs};
        }
        else {
            my $sp_swapper = $self->get_spatial_output_for_label_allocation(
                %args,
                spatial_conditions_for_label_allocation => $sp_conditions,
                param_name                              => 'SPATIAL_OUTPUT_FOR_SWAP_CANDIDATES',
                elements_to_calc                        => \@sorted_groups, #  excludes empty and full groups
            );
            if ($sp_swapper) {
                my $spatial_conditions_arr = $sp_swapper->get_spatial_conditions;
                my $sp_cond_obj = $spatial_conditions_arr->[0];
                my $result_type = $sp_cond_obj->get_result_type;
                if ($result_type eq 'always_true') {
                    say "[Randomise] spatial condition always_true, reverting to non-spatial allocation";
                }
                elsif ($result_type =~ /^always_false|self_only$/) {
                    croak "Spatial condition type $result_type means it is impossible for groups to have neighbours, "
                        . "thus swapping is not possible.";
                }
                else {
                    foreach my $element ($sp_swapper->get_element_list) {
                        my $nbrs = $sp_swapper->get_list_ref_aa($element, '_NBR_SET1') // [];
                        #  prefilter the focal group
                        my @filtered = sort grep {$_ ne $element} @$nbrs;
                        next if !@filtered;
                        $sp_swap_list{$element} = \@filtered;
                    }
                    @gps_with_nbrs = sort keys %sp_swap_list;
                    my $n_gps_w_nbrs = @gps_with_nbrs;
                    say "[Randomise] $n_gps_w_nbrs of $n_groups groups have swappable neighbours";
                    croak "[Randomise] Curveball spatial: No groups have neighbours, cannot swap labels"
                        if !@gps_with_nbrs;
                }
            }
            #  Hash is empty if condition parses to nothing.
            #  Subsequent runs thus do not process the condition again.
            $cached_lists->{$cache_key_sp_swap_list} = \%sp_swap_list;
            $cached_lists->{$cache_key_gps_w_nbrs}   = \@gps_with_nbrs;
        }
    }
    my $use_spatial_swap = !!@gps_with_nbrs;

    #  Basic algorithm:
    #  pick two different groups at random
    #  swap as many labels as possible

    if (!looks_like_number $target_swap_count || $target_swap_count <= 0) {
        $target_swap_count = 2 * $non_zero_mx_cells;
    }
    if (!looks_like_number $max_swap_attempts || $max_swap_attempts <= 0) {
        $max_swap_attempts = 100 * $target_swap_count;
    }

    my $swap_count  = 0;
    my $attempts    = 0;
    my $moved_pairs = 0;

    say "[RANDOMISE] Target swap count is $target_swap_count, max attempts is $max_swap_attempts";

    #  handle pathological case of only one group
    my $gt_one_gp = $n_groups > 1;

    MAIN_ITER:
    while (   $swap_count  < $target_swap_count
        && $attempts    < $max_swap_attempts
        && $moved_pairs < $non_zero_mx_cells
        && $gt_one_gp
    ) {
        $attempts++;

        my ($group1, $group2);

        if ($use_spatial_swap) {
            $group1 = $gps_with_nbrs[int $rand->rand (scalar @gps_with_nbrs)];
            my $n = scalar @{$sp_swap_list{$group1}};
            next MAIN_ITER if !$n;
            #  we have already filtered group1 from its list
            $group2 = $sp_swap_list{$group1}[int $rand->rand($n)]
        }
        else {
            $group1 = $sorted_groups[int $rand->rand ($n_groups)];
            $group2 = $sorted_groups[int $rand->rand ($n_groups)];
            while ($group1 eq $group2) {  #  keep trying - a bit wasteful but should be rare
                $group2 = $sorted_groups[int $rand->rand($n_groups)];
            }
        }

        my \%labels1 = $lb_hash{$group1};
        my \%labels2 = $lb_hash{$group2};

        my @swappable_from1 = sort +keys_difference (%labels1, %labels2);
        my @swappable_from2 = sort +keys_difference (%labels2, %labels1);

        my ($n1, $n2) = List::MoreUtils::minmax (
            scalar @swappable_from1,
            scalar @swappable_from2,
        );

        #  skip if nothing can be swapped
        next MAIN_ITER if !$n1;

        my (@swap_from1, @swap_from2);
        my $ratio =  $n1 / $n2;

        if ($use_max_swap) {
            my $max_idx = $n1 - 1;             #  index
            $rand->shuffle(\@swappable_from1)  #  shuffle array if needed
              if @swappable_from1 > $n1;
            $#swappable_from1 = $max_idx;      #  shorten it
            \@swap_from1 = \@swappable_from1;  #  take alias
            $rand->shuffle(\@swappable_from2)  #  same for swaps2
              if @swappable_from2 > $n1;
            $#swappable_from2 = $max_idx;
            \@swap_from2 = \@swappable_from2;
        }
        elsif ($n1 == 1 || $ratio <= 0.05 || $use_hyper) {

            my $nswaps = 0;
            if ($n1 == 1) {
                #  straight proportional sample 1/(n1+n2)
                $nswaps = ($rand->rand > 1/(1+$n2)) || 0;
            }
            elsif ($ratio <= 0.05) {
                #  Quick binomial approximation to hypergeometric when many more $n2 than $n1.
                #  "binomial(ratio, n1)" is the number retained so take the complement.
                $nswaps = $n1 - $rand->binomial($ratio, $n1);
            }
            elsif (!!$use_hyper) {
                #  Hypergeometric sampler.  Slow.
                use PDL::Lite;
                use PDL::GSL::CDF ();
                #  The peak probability is at n1/n2 when n1 < n2, so CDF==0.5 at n1/n2.
                #  This means we can work with the left side of the distribution in nearly all cases.
                #  It is not exact but works well enough for this application given the probabilities
                #  to the right of 2*n1/n2 are of the order of one in one million or less.
                state $lower_ratio = 1e-6;
                state $upper_ratio = 1 - $lower_ratio;
                my $r    = 1 - $rand->rand;  #  interval (0,1]
                my $N    = $n1 + $n2;
                my ($kmin, $kmax) = (0, $n1);
                #  We normally don't need all the values in the CDF.
                #  This approach gets us the centre of mass within 4sd of the mean
                #  which should cover 99.99% or more of cases.
                if ($N > 40) {  #  arbitrary threshold
                    my $mean  = $n1 * $n1 / $N;
                    #  Width is a multiple of the SD.  We could use 3 but the plus step
                    #  in the CDF calc below balances out any savings.
                    my $width = 4 * sqrt($mean * ($N-$n1) / $N * ($N-$n1) / ($N-1));
                    $kmin = $r > $lower_ratio ? max(0,  floor($mean - $width)) : 0;
                    $kmax = $r < $upper_ratio ? min($n1, ceil($mean + $width)) : $n1;
                }
                my $cdf  = $cum_hgeom_cache{"$n1:$n2:$kmin:$kmax"} //= do {
                    my $k = $sequence_cache{$kmax - $kmin} //= PDL->sequence($kmax-$kmin+1);
                    $kmin
                        ? $k->plus($kmin)->gsl_cdf_hypergeometric_P($n1, $n2, $n1)
                        : $k->gsl_cdf_hypergeometric_P($n1, $n2, $n1);
                };

                #  The hypergeom distr tells us how many remain so the swap count is the n1 complement
                #  for the leftmost search.  This is the kmax complement for the subset adjusted for kmin.
                $nswaps = $kmax - PDL::vsearch_insert_leftmost($r, $cdf)->sclr + $kmin;
            }

            next MAIN_ITER if !$nswaps;

            if ($nswaps == 1) {
                #  grab a pair
                $swap_from1[0] = $swappable_from1[$rand->irand % @swappable_from1];
                $swap_from2[0] = $swappable_from2[$rand->irand % @swappable_from2];
            }
            else {
                #  Find $nswaps samples
                #  List::Util::sample is _very_ slow...
                # local $List::Util::RAND = sub {$rand->rand};
                # @swap_from1 = List::Util::sample ($nswaps, @swappable_from1);
                # @swap_from2 = List::Util::sample ($nswaps, @swappable_from2);
                $nswaps--;                         #  used as an index instead of a count now
                $rand->shuffle(\@swappable_from1); #  shuffle array
                $#swappable_from1 = $nswaps;       #  shorten it
                \@swap_from1 = \@swappable_from1;  #  take alias
                $rand->shuffle(\@swappable_from2); #  rinse and repeat for array 2
                $#swappable_from2 = $nswaps;
                \@swap_from2 = \@swappable_from2;
            }
        }
        else {
            #  Old and incorrect method as the number of swaps is in the interval [0,$n], not exactly $n.
            # #  Get a random subset of the longer array.
            # #  Sort is needed to guarantee repeatability, and in-place sort is optimised by Perl.
            # #  In-place shuffle is apparently fastest (MRMA docs)
            # if (@swappable_from1 > $max_labels_to_swap) {
            #     @swappable_from1 = sort @swappable_from1;
            #     $rand->shuffle (\@swappable_from1);
            #     @swappable_from1 = @swappable_from1[0..$max_labels_to_swap-1];
            # }
            # elsif (@swappable_from2 > $max_labels_to_swap) {
            #     @swappable_from2 = sort @swappable_from2;
            #     $rand->shuffle (\@swappable_from2);
            #     @swappable_from2 = @swappable_from2[0..$max_labels_to_swap-1];
            # }

            #  Concatenate the two swappable sets, then go looking for which ones need to be swapped.
            #  The search uses while-loops to avoid grepping very large lists for small numbers of possible swaps.

            #  Each list is already sorted so no need to re-sort the whole thing.
            my @shuffled = (@swappable_from1, @swappable_from2);
            $rand->shuffle(\@shuffled);
            my $s_count = 0; #  used for early stop once we have found all the swappers

            #  Search the first part of the list.
            #  Anything originally from label_list2 is to be swapped to label_list1.
            my $i = 0;
            while ($s_count != $n1 && $i < @swappable_from1) {
                if (exists $labels2{$shuffled[$i]}) {
                    push @swap_from2, $shuffled[$i];
                    $s_count++;
                }
                $i++;
            }
            #  Now search the second part of the list.
            #  Anything originally from label_list1 is to be swapped to label_list2.
            #  count $s_count down
            $i = @swappable_from1;
            while ($s_count != 0 && $i < @shuffled) {
                if (exists $labels1{$shuffled[$i]}) {
                    push @swap_from1, $shuffled[$i];
                    $s_count--;
                }
                $i++;
            }

            #  skip if nothing to be swapped
            next MAIN_ITER if !@swap_from1;
        }

        # die "Horribly" if @swap_from1 != @swap_from2;
        # say STDERR join ' ', scalar @swap_from1, scalar @swap_from2;

        #  track before moving
        if ($stop_on_all_swapped && @swap_from1) {
            foreach my $i (0..$#swap_from1) {
                my $lb1 = $swap_from1[$i];
                if ($lb_hash{$group1}{$lb1} && !$lb_gp_moved{$lb1}{$group1}) {
                    $moved_pairs++;
                    $lb_gp_moved{$lb1}{$group1} = 1;
                }
                my $lb2 = $swap_from2[$i];
                if ($lb_hash{$group2}{$lb2} && !$lb_gp_moved{$lb2}{$group2}) {
                    $moved_pairs++;
                    $lb_gp_moved{$lb2}{$group2} = 1;
                }
            }
        }

        @labels2{@swap_from1} = delete @labels1{@swap_from1};
        @labels1{@swap_from2} = delete @labels2{@swap_from2};

        $swap_count += scalar @swap_from1;

        #  update here as otherwise we spend a huge amount
        #  of time running the progress bar
        $progress_bar->update (
            "Swap count: $swap_count\n(target: $target_swap_count)\n"
                . "Swap attempts: $attempts\n(max: $max_swap_attempts)\n"
                . ($moved_pairs ? "Pairs moved: $moved_pairs\n(target: $non_zero_mx_cells)" : ''),
            $swap_count / $target_swap_count,
        );
    }


    if ($attempts == $max_swap_attempts) {
        say "[RANDOMISE] rand_curveball: max attempts threshold "
            . "$max_swap_attempts reached.";
    }
    elsif ($moved_pairs >= $non_zero_mx_cells) {
        say "[RANDOMISE] rand_curveball: All "
            . "group/label elements swapped at least once";
    }
    say "[RANDOMISE] rand_curveball: ran $swap_count swaps across "
        . "$attempts attempts for basedata $name with $n_labels labels and "
        . "$n_groups groups";
    if ($moved_pairs > 0) {
        say "[RANDOMISE]  Swapped $moved_pairs of the $non_zero_mx_cells group/label "
            . "elements at least once.\n";
    }

    #  now we populate a new basedata
    my $new_bd = $self->get_new_bd_from_gp_lb_hash (
        name             => $name,
        source_basedata  => $bd,
        gp_hash          => \%lb_hash,
        empty_label_hash => \%empty_labels,
        empty_group_hash => \%empty_groups,
        transpose        => 1,
    );

    # say 'Done';
    return $new_bd;
}


1;

