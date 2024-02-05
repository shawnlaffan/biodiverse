package Biodiverse::Randomise::CurveBall;

use strict;
use warnings;
use 5.022;

our $VERSION = '4.99_002';

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

sub get_metadata_rand_curveball {
    my $self = shift;

    my @parameters = (
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

    my $progress_bar = Biodiverse::Progress->new();

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

    printf "[RANDOMISE] Randomise using curveball algorithm for %s labels from %s groups\n",
        scalar @sorted_labels, scalar @sorted_groups;

    $progress_bar->reset;

    #  Basic algorithm:
    #  pick two different groups at random
    #  pick two different labels at random
    #  if label1 is already in group2, or label2 in group1, then try again
    #  else swap the labels between groups

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

        my $group1 = $sorted_groups[int $rand->rand (scalar @sorted_groups)];
        my $group2 = $sorted_groups[int $rand->rand (scalar @sorted_groups)];
        while ($group1 eq $group2) {
            $group2 = $sorted_groups[int $rand->rand (scalar @sorted_groups)];
            #  need an escape here, or revert to brute force search
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

        #  is sort in-place optimised?
        @swappable_from1 = sort @swappable_from1;
        @swappable_from2 = sort @swappable_from2;

        #  in-place shuffle is apparently fastest (MRMA docs)
        $rand->shuffle (\@swappable_from1);
        $rand->shuffle (\@swappable_from2);

        #  curtail longer array
        if (@swappable_from1 > $n_labels_to_swap) {
            @swappable_from1 = @swappable_from1[0..$n_labels_to_swap-1];
        }
        elsif (@swappable_from2 > $n_labels_to_swap) {
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
        say "[RANDOMISE] rand_curveball: max attempts theshold "
            . "$max_swap_attempts reached.";
    }
    elsif ($moved_pairs >= $non_zero_mx_cells) {
        say "[RANDOMISE] rand_curveball: All "
            . "group/label elements swapped at least once";
    }
    say "[RANDOMISE] rand_curveball: ran $swap_count swaps across "
        . "$attempts attempts for basedata $name with $n_labels labels and "
        . "$n_groups groups.\n"
        . "[RANDOMISE]  Swapped $moved_pairs of the $non_zero_mx_cells group/label "
        . "elements at least once.\n";

    #  transpose
    my %gp_hash;
    foreach my $gp (keys %lb_hash) {
        foreach my $lb (keys %{$lb_hash{$gp}}) {
            #  should not need this check, but just in case
            next if !$lb_hash{$gp}{$lb};
            $gp_hash{$lb}{$gp} = $lb_hash{$gp}{$lb};
        }
    }

    #  now we populate a new basedata
    my $new_bd = $self->get_new_bd_from_gp_lb_hash (
        name => $name,
        source_basedata  => $bd,
        gp_hash          => \%gp_hash,
        empty_label_hash => \%empty_labels,
        empty_group_hash => \%empty_groups,
    );

    # say 'Done';
    return $new_bd;
}


1;

