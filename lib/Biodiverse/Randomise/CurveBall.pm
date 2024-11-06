package Biodiverse::Randomise::CurveBall;

use strict;
use warnings;
use 5.022;

our $VERSION = '4.99_002';

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

my $multinomial_class = 'Statistics::Sampler::Multinomial::Indexed';

use Biodiverse::Metadata::Parameter;
my $parameter_rand_metadata_class = 'Biodiverse::Metadata::Parameter';


my $tooltip_swap_count = <<'TOOLTIP_SWAP_COUNT'
Target number of swaps to attempt.
Default is twice the number of
non-zero matrix (basedata) entries.
TOOLTIP_SWAP_COUNT
;

my $tooltip_map_swap_attempts = <<'TOOLTIP_SWAP_ATTEMPTS'
Maximum number of swaps to attempt.
Default is 100 times the target
number of swaps.
TOOLTIP_SWAP_ATTEMPTS
;

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

    my @parameters = (
        $self->get_curveball_spatial_allocation_metadata,
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

    my $start_time = [gettimeofday];

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

    my $progress_text =<<"END_PROGRESS_TEXT"
$name
Curveball randomisation
END_PROGRESS_TEXT
    ;

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

    my (%sp_swap_list, @gps_with_nbrs);
    if (my $sp_conditions = $args{spatial_condition_for_swap_pairs}) {
        my $sp_swapper = $self->get_spatial_output_for_label_allocation (
            %args,
            spatial_conditions_for_label_allocation => $sp_conditions,
            param_name                              => 'SPATIAL_OUTPUT_FOR_SWAP_CANDIDATES',
            elements_to_calc                        => \@sorted_groups,  #  excludes empty and full groups
        );
        if ($sp_swapper) {
            my $spatial_conditions_arr = $sp_swapper->get_spatial_conditions;
            my $sp_cond_obj = $spatial_conditions_arr->[0];
            my $result_type = $sp_cond_obj->get_result_type;
            if ($result_type eq 'always_true') {
                say "[Randomise] spatial condition always_true, reverting to non-spatial allocation";
            }
            elsif ($result_type =~ /^always_false|self_only$/) {
                croak "Spatial condition means it is impossible for groups to have neighbours, "
                    . "so cannot swap labels with neighbours"
                      if !@gps_with_nbrs;
            }
            else {
                foreach my $element ($sp_swapper->get_element_list) {
                    my $nbrs = $sp_swapper->get_list_ref_aa ($element, '_NBR_SET1') // [];
                    #  prefilter the focal group
                    my @filtered = sort grep {$_ ne $element} @$nbrs;
                    next if !@filtered;
                    $sp_swap_list{$element} = \@filtered;
                }
                @gps_with_nbrs = sort keys %sp_swap_list;
                my $n_gps_w_nbrs = @gps_with_nbrs;
                say "[Randomise] $n_gps_w_nbrs of $n_groups groups have swappable neighbours";
                croak "No groups have neighbours, cannot swap labels with neighbours"
                    if !@gps_with_nbrs;
            }
        }
    }
    my $use_spatial_swap = !!%sp_swap_list;

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

    MAIN_ITER:
    while (   $swap_count  < $target_swap_count
        && $attempts    < $max_swap_attempts
        && $moved_pairs < $non_zero_mx_cells
    ) {
        $attempts++;

        #  handle pathological case of only one group
        last MAIN_ITER if $n_groups == 1;

        my $group1; ;
        my $group2;
        if ($use_spatial_swap) {
            $group1 = $gps_with_nbrs[int $rand->rand (scalar @gps_with_nbrs)];
            my $n = scalar @{$sp_swap_list{$group1}};
            next MAIN_ITER if !$n;
            #  we have already filtered group1 from its list
            $group2 = $sp_swap_list{$group1}[int $rand->rand($n)]
        }
        else {
            $group1 = $sorted_groups[int $rand->rand ($n_groups)];
            $group2 = $sorted_groups[int $rand->rand($n_groups)];
            while ($group1 eq $group2) {  #  keep trying - a bit wasteful but should be rare
                $group2 = $sorted_groups[int $rand->rand($n_groups)];
            }
        }

        my \%labels1 = $lb_hash{$group1};
        my \%labels2 = $lb_hash{$group2};

        #  brute force for now - but we have better methods in turnover indices
        my @swappable_from1 = grep {!exists $labels2{$_}} keys %labels1;
        my @swappable_from2 = grep {!exists $labels1{$_}} keys %labels2;

        my $n_labels_to_swap
            = min (scalar @swappable_from1, scalar @swappable_from2);

        #  skip if nothing can be swapped
        next MAIN_ITER if !$n_labels_to_swap;



        #  Get a random subset of the longer array.
        #  Sort is needed to guarantee repeatability, and in-place sort is optimised by Perl.
        #  In-place shuffle is apparently fastest (MRMA docs)
        if (@swappable_from1 > $n_labels_to_swap) {
            @swappable_from1 = sort @swappable_from1;
            $rand->shuffle (\@swappable_from1);
            @swappable_from1 = @swappable_from1[0..$n_labels_to_swap-1];
        }
        elsif (@swappable_from2 > $n_labels_to_swap) {
            @swappable_from2 = sort @swappable_from2;
            $rand->shuffle (\@swappable_from2);
            @swappable_from2 = @swappable_from2[0..$n_labels_to_swap-1];
        }

        #  track before moving
        if ($stop_on_all_swapped) {
            foreach my $i (0..$#swappable_from1) {
                my $lb1 = $swappable_from1[$i];
                if ($lb_hash{$group1}{$lb1} && !$lb_gp_moved{$lb1}{$group1}) {
                    $moved_pairs++;
                    $lb_gp_moved{$lb1}{$group1} = 1;
                }
                my $lb2 = $swappable_from2[$i];
                if ($lb_hash{$group2}{$lb2} && !$lb_gp_moved{$lb2}{$group2}) {
                    $moved_pairs++;
                    $lb_gp_moved{$lb2}{$group2} = 1;
                }
            }
        }

        @labels2{@swappable_from1} = delete @labels1{@swappable_from1};
        @labels1{@swappable_from2} = delete @labels2{@swappable_from2};

        $swap_count += $n_labels_to_swap;

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

