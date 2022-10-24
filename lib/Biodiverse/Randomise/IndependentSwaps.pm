#  package to abstract some of the functions out
#  of the main Biodiverse::Randomise package
package Biodiverse::Randomise::IndependentSwaps;

use strict;
use warnings;
use 5.022;

our $VERSION = '3.99_005';

use experimental 'refaliasing';
no warnings 'experimental::refaliasing';

use Time::HiRes qw { time gettimeofday tv_interval };
use List::Unique::DeterministicOrder 0.003;
use Scalar::Util qw /blessed looks_like_number/;
use List::Util qw /max/;
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

sub get_common_independent_swaps_metadata {
    my @parameters = (
        {name       => 'swap_count',
         type       => 'integer',
         default    => 0,
         increment  => 1,
         max        => 2**31-1,
         tooltip    => $tooltip_swap_count,
         box_group  => 'Independent swaps',
        },
        {name       => 'max_swap_attempts',
         type       => 'integer',
         default    => 0,
         increment  => 1,
         max        => 2**31-1,
         tooltip    => $tooltip_map_swap_attempts,
         box_group  => 'Independent swaps',
        },
        {name       => 'stop_on_all_swapped',
         type       => 'boolean',
         default    => 0,
         tooltip    => 'Stop swapping when each label/group pair '
                     . 'has been swapped at least once',
         box_group  => 'Independent swaps',
        },
    );
    return wantarray ? @parameters : \@parameters;
}
  
sub get_metadata_rand_independent_swaps_modified {
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
                     . "of the independent swaps algorithm "
                     . "(Gotelli 2000; Miklos & Podani, 2004) "
                     . "modified to reduce mis-hits\n",
    );

    return $self->metadata_class->new(\%metadata);
}


sub rand_independent_swaps_modified {
    my ($self, %args) = @_;
    
    my $start_time = [gettimeofday];

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');
    my $lb = $bd->get_labels_ref;

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
Independent swaps randomisation
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
    
    my @sorted_label_ranges 
      = map {$lb->get_variety_aa($_)} 
        @sorted_labels;
    #  cloning is slower than direct generation
    my $label_sampler = $multinomial_class->new(
        data => \@sorted_label_ranges,
        prng => $rand,
    );
    
    my %richness_hash 
      = map {$_ => $bd->get_richness_aa ($_)} 
        @sorted_groups;

    my (%gp_hash, %gp_list, %lb_list,
        %gp_shadow_list, %lb_shadow_list,
        %gp_shadow_sampler,
        %has_max_range,  #  should filter these
        %lb_gp_moved,
    );
    my $gp_shadow_list_cache
      = $self->get_cached_value_dor_set_default_aa (GP_SHADOW_LIST_CACHE => {});
    my $gp_shadow_sampler_cache
      = $self->get_cached_value_dor_set_default_aa (GP_SHADOW_SAMPLER_CACHE => {});
    my $non_zero_mx_cells = 0;  #  sum of richness and range scores
    my $done_count = 0;
    foreach my $label (@sorted_labels) {
        $done_count++;
        $progress_bar->update (
            "Running rand_independent_swaps_modified setup",
            $done_count / @sorted_labels,
        );
        my $group_hash = $bd->get_groups_with_label_as_hash_aa($label);
        $non_zero_mx_cells += scalar keys %$group_hash;
        $gp_hash{$label} = {%$group_hash};
        $gp_list{$label} = List::Unique::DeterministicOrder->new (
            data => [sort keys %$group_hash],
        );
        my $gp_shadow_data
          = $self->get_cached_value_dor_set_default_aa (GP_SHADOW_DATA => {});
        $gp_shadow_data->{$label}
          //= do {
            my $shadow_hash
              = $bd->get_groups_without_label_as_hash(label => $label);
              [ #  disable range sort - it biases S::M::S::draw1 
                sort # {$richness_hash{$b} <=> $richness_hash{$a}}
                grep !exists $empty_groups{$_},
                keys %$shadow_hash
              ];
          };
        my $cached_list = $gp_shadow_list_cache->{$label}
          //= List::Unique::DeterministicOrder->new (
                data => [@{$gp_shadow_data->{$label}}],
              );
        $gp_shadow_list{$label} = $cached_list->clone;
        if (@{$gp_shadow_data->{$label}}) {
            my $cached_object = $gp_shadow_sampler_cache->{$label}
              //= $multinomial_class->new (
                  prng => $rand,
                  data => [@richness_hash{$gp_shadow_list{$label}->keys}],
                );
            my $cloned = $cached_object->clone;
            #  update the prng otherwise we get a stale cached version
            $cloned->set_prng ($rand);  
            $gp_shadow_sampler{$label} = $cloned;
        }
        if ($bd->get_range (element => $label) == @sorted_groups) {
            #  cannot be swapped around
            $has_max_range{$label}++;
        }
    }
    foreach my $group (@sorted_groups) {
        my $label_hash = $bd->get_labels_in_group_as_hash_aa($group);
        $lb_list{$group} = List::Unique::DeterministicOrder->new (
            data => [sort keys %$label_hash],
        );
    }

    printf "[RANDOMISE] Randomise using modified independent swaps for %s labels from %s groups\n",
       scalar @sorted_labels, scalar @sorted_groups;

    $progress_bar->reset;

    #  Basic algorithm:
    #  pick two different groups at random
    #  pick two different labels at random
    #  if label1 is already in group2, or label2 in group1, then try again
    #  else swap the labels between groups
    #  
    #  Nuanced algorithm to avoid excess searching across sparsely populated data:
    #  pick group1
    #  pick label1 from that group
    #  pick group2 from the set of groups that do not contain label1
    #  pick label2 from group2, where label2 cannot occur in group1
    #
    
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
        
        $progress_bar->update (
              "Swap count: $swap_count\n(target: $target_swap_count)\n"
            . "Swap attempts: $attempts\n(max: $max_swap_attempts)\n"
            . ($moved_pairs ? "Pairs moved: $moved_pairs\n(target: $non_zero_mx_cells)" : ''),
            $swap_count / $target_swap_count,
        );

        #  weight by ranges
        my $label1 = $sorted_labels[$label_sampler->draw];

        #  is this label swappable?
        next MAIN_ITER if $has_max_range{$label1};

        my $group1 = $gp_list{$label1}->get_key_at_pos(
            int $rand->rand (scalar $gp_list{$label1}->keys)
        );
        #  select from groups not containing $label1
        my $iter   = $gp_shadow_sampler{$label1}->draw;
        my $group2 = $gp_shadow_list{$label1}->get_key_at_pos($iter);

        #  select a random label from group2
        my $key_count = $lb_list{$group2}->keys;
        my $label2 = $lb_list{$group2}->get_key_at_pos(
            int $rand->rand ($key_count)
        );
        
        my (%checked);
        while ($lb_list{$group1}->exists ($label2) || $has_max_range{$label2}) {
            $checked{$label2}++;
            #  no possible swap if we have tried all of them
            next MAIN_ITER if keys %checked >= $key_count;  
            #  Try another one at random.
            #  Approach is inefficient when the ratio of
            #  swappable to non-swappable is low.
            $label2 = $lb_list{$group2}->get_key_at_pos(
                int $rand->rand ($key_count)
            );
        }

        #  track before moving
        if ($stop_on_all_swapped) {
            foreach my $pair ([$label1, $group1], [$label2, $group2]) {
                my ($lb, $gp) = @$pair;
                if ($gp_hash{$lb}{$gp} && !$lb_gp_moved{$lb}{$gp}) {
                    $moved_pairs++;
                    $lb_gp_moved{$lb}{$gp} = 1;
                }
            }
        }

        #  swap the labels between groups and update the tracker lists
        #  group2 moves to label1, group1 moves to label2
        $gp_hash{$label1}->{$group2} = delete $gp_hash{$label2}->{$group2};
        $gp_hash{$label2}->{$group1} = delete $gp_hash{$label1}->{$group1};
        $gp_list{$label1}->push ($gp_list{$label2}->delete($group2));
        $gp_list{$label2}->push ($gp_list{$label1}->delete($group1));
        $lb_list{$group1}->push ($lb_list{$group2}->delete($label2));
        $lb_list{$group2}->push ($lb_list{$group1}->delete($label1));

        #  The shadows index the list-set complements
        #  so the samplers need to be kept in synch.
        #  Group1 is now in the label1 shadow list,
        #    as it is no longer with label1.
        #  Ditto for group2 and label2.
        #  Sequence depends on push/delete implementation
        #    which will cause problems if that changes. 
        $gp_shadow_list{$label1}->push ($group1);
        $gp_shadow_list{$label2}->push ($group2);
        $gp_shadow_list{$label1}->delete($group2);  #  $group1 will move from end to where $group2 was
        $gp_shadow_list{$label2}->delete($group1);  #  $group2 will move from end to where $group1 was

        my $l1g1_iter = $gp_shadow_list{$label1}->get_key_pos($group1); #  should be where group2 was
        my $l2g2_iter = $gp_shadow_list{$label2}->get_key_pos($group2); #  should be where group1 was
        $gp_shadow_sampler{$label1}->update_values ($l1g1_iter => $richness_hash{$group1});
        $gp_shadow_sampler{$label2}->update_values ($l2g2_iter => $richness_hash{$group2});

        $swap_count++;
    }


    if ($attempts == $max_swap_attempts) {
        say "[RANDOMISE] rand_independent_swaps_modified: max attempts theshold "
          . "$max_swap_attempts reached.";
    }
    elsif ($moved_pairs >= $non_zero_mx_cells) {
        say "[RANDOMISE] rand_independent_swaps_modified: All "
          . "group/label elements swapped at least once";
    }
    say "[RANDOMISE] rand_independent_swaps: ran $swap_count swaps across "
      . "$attempts attempts for basedata $name with $n_labels labels and "
      . "$n_groups groups.\n"
      . $stop_on_all_swapped
        ?
          ("[RANDOMISE] Swapped $moved_pairs of the $non_zero_mx_cells group/label "
          . "elements at least once.\n")
        : q{};

    #  now we populate a new basedata
    my $new_bd = $self->get_new_bd_from_gp_lb_hash (
        name => $name,
        source_basedata  => $bd,
        gp_hash          => \%gp_hash,
        empty_label_hash => \%empty_labels,
        empty_group_hash => \%empty_groups,
    );
    
    return $new_bd;
}

sub get_metadata_rand_independent_swaps {
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
        description => "Randomly swap labels across groups using an "
                     . "implementation of the independent swaps algorithm "
                     . "(Gotelli 2000; Miklos & Podani, 2004)\n",
    );

    return $self->metadata_class->new(\%metadata);
}


sub rand_independent_swaps {
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
Independent swaps randomisation
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
    
    my $lb = $bd->get_labels_ref;
    my @sorted_label_ranges 
      = map {$lb->get_variety_aa($_)} 
        @sorted_labels;

    my %richness_hash 
      = map {$_ => $bd->get_richness_aa ($_)} 
        @sorted_groups;

    my (%gp_hash, %has_max_range, %lb_gp_moved);
    my $non_zero_mx_cells = 0;  #  sum of richness and range scores
    foreach my $label (@sorted_labels) {
        my $group_hash = $bd->get_groups_with_label_as_hash_aa($label);
        $non_zero_mx_cells += scalar keys %$group_hash;
        $gp_hash{$label} = {%$group_hash};
        if ($bd->get_range (element => $label) == @sorted_groups) {
            #  cannot be swapped around
            $has_max_range{$label}++;
        }
    }

    printf "[RANDOMISE] Randomise using independent swaps for %s labels from %s groups\n",
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

        my $label1 = $sorted_labels[int $rand->rand (scalar @sorted_labels)];
        next MAIN_ITER if $has_max_range{$label1};

        my $label2 = $sorted_labels[int $rand->rand (scalar @sorted_labels)];
        while ($label1 eq $label2) {
            $label2 = $sorted_labels[int $rand->rand (scalar @sorted_labels)];
            #  need an escape here, or revert to brute force search
        }
        next MAIN_ITER if $has_max_range{$label2};

        my $group1 = $sorted_groups[int $rand->rand (scalar @sorted_groups)];
        my $group2 = $sorted_groups[int $rand->rand (scalar @sorted_groups)];
        while ($group1 eq $group2) {
            $group2 = $sorted_groups[int $rand->rand (scalar @sorted_groups)];
            #  need an escape here, or revert to brute force search
        }

        # swap labels if one of the group/label pairs is empty
        # as they cannot be swapped into or from
        # (i.e. try the mirror sample on the matrix)
        if (! ($gp_hash{$label1}->{$group1} && $gp_hash{$label2}->{$group2})) {
            ($label1, $label2) = ($label2, $label1);
            #  and restart the loop if one of the new pairs is also empty
            next MAIN_ITER
              if (! ($gp_hash{$label1}->{$group1} && $gp_hash{$label2}->{$group2}));
        }
        
        #  must swap to empty slots
        next MAIN_ITER
          if $gp_hash{$label1}->{$group2} || $gp_hash{$label2}->{$group1};

        #  track before moving
        if ($stop_on_all_swapped) {
            foreach my $pair ([$label1, $group1], [$label2, $group2]) {
                my ($lb, $gp) = @$pair;
                if ($gp_hash{$lb}{$gp} && !$lb_gp_moved{$lb}{$gp}) {
                    $moved_pairs++;
                    $lb_gp_moved{$lb}{$gp} = 1;
                }
            }
        }

        #  swap the labels between groups and update the tracker lists
        #  group2 moves to label1, group1 moves to label2
        $gp_hash{$label1}->{$group2} = delete $gp_hash{$label2}->{$group2};
        $gp_hash{$label2}->{$group1} = delete $gp_hash{$label1}->{$group1};

        $swap_count++;

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
        say "[RANDOMISE] rand_independent_swaps: max attempts theshold "
          . "$max_swap_attempts reached.";
    }
    elsif ($moved_pairs >= $non_zero_mx_cells) {
        say "[RANDOMISE] rand_independent_swaps_modified: All "
          . "group/label elements swapped at least once";
    }
    say "[RANDOMISE] rand_independent_swaps: ran $swap_count swaps across "
      . "$attempts attempts for basedata $name with $n_labels labels and "
      . "$n_groups groups.\n"
      . "[RANDOMISE]  Swapped $moved_pairs the $non_zero_mx_cells group/label "
      . "elements at least once.\n";
    
    #  now we populate a new basedata
    my $new_bd = $self->get_new_bd_from_gp_lb_hash (
        name => $name,
        source_basedata  => $bd,
        gp_hash          => \%gp_hash,
        empty_label_hash => \%empty_labels,
        empty_group_hash => \%empty_groups,
    );
    
    return $new_bd;
}


sub get_new_bd_from_gp_lb_hash {
    my ($self, %args) = @_;
    
    my $bd   = $args{source_basedata};
    my $name = $args{name};
    \my %gp_hash = $args{gp_hash};
    \my %empty_groups = $args{empty_group_hash};
    \my %empty_labels = $args{empty_label_hash};

    #  now we populate a new basedata
    my $new_bd = blessed($bd)->new ($bd->get_params_hash);
    $new_bd->get_groups_ref->set_params ($bd->get_groups_ref->get_params_hash);
    $new_bd->get_labels_ref->set_params ($bd->get_labels_ref->get_params_hash);
    my $new_bd_name = $new_bd->get_param ('NAME');
    $new_bd->rename (name => $new_bd_name . "_" . $name);

    #  pre-assign the hash buckets to avoid rehashing larger structures
    $new_bd->set_group_hash_key_count (count => $bd->get_group_count);
    $new_bd->set_label_hash_key_count (count => $bd->get_label_count);

    #  re-use a csv object
    my $csv = $bd->get_csv_object(
        sep_char   => $bd->get_param('JOIN_CHAR'),
        quote_char => $bd->get_param('QUOTES'),
    );

    foreach my $label (keys %gp_hash) {
        my $this_g_hash = $gp_hash{$label};
        foreach my $group (keys %$this_g_hash) {
            $new_bd->add_element_simple_aa (
                $label, $group, $this_g_hash->{$group}, $csv,
            );
        }
    }
    foreach my $label (keys %empty_labels) {
        $new_bd->add_element (
            label => $label,
            allow_empty_labels => 1,
            csv_object   => $csv,
        );
    }
    foreach my $group (keys %empty_groups) {
        $new_bd->add_element (
            group => $group,
            allow_empty_groups => 1,
            csv_object   => $csv,
        );
    }

    return $new_bd;
}

1;

