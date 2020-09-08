#  package to abstract some of the functions out
#  of the main Biodiverse::Randomise package
package Biodiverse::Randomise::RandFunctions;

use strict;
use warnings;
use 5.022;
use Time::HiRes qw { time gettimeofday tv_interval };
use List::Unique::DeterministicOrder;
use Scalar::Util qw /blessed looks_like_number/;
#use List::MoreUtils qw /bsearchidx/;

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
Default is twice the number of
non-zero matrix (basedata) entries.
TOOLTIP_SWAP_ATTEMPTS
  ;

sub get_metadata_rand_independent_swaps {
    my $self = shift;


    my @parameters = (
        {name       => 'swap_count',
         type       => 'integer',
         default    => 0,
         increment  => 1,
         tooltip    => $tooltip_swap_count,
         box_group  => 'Independent swaps',
        },
        {name       => 'max_swap_attempts',
         type       => 'integer',
         default    => 0,
         increment  => 1,
         tooltip    => $tooltip_map_swap_attempts,
         box_group  => 'Independent swaps',
         },
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
    
    my (%gp_hash, %gp_list, %lb_list,
        %gp_shadow_list, %lb_shadow_list,
        %has_max_range,  #  should filter these
    );
    my $non_zero_mx_cells = 0;  #  sum of richness and range scores
    foreach my $label (@sorted_labels) {
        my $group_hash = $bd->get_groups_with_label_as_hash_aa($label);
        $non_zero_mx_cells += scalar keys %$group_hash;
        $gp_hash{$label} = {%$group_hash};
        $gp_list{$label} = List::Unique::DeterministicOrder->new (
            data => [sort keys %$group_hash],
        );
        my $shadow_hash = $bd->get_groups_without_label_as_hash(label => $label);
        $gp_shadow_list{$label} = List::Unique::DeterministicOrder->new (
            data => [sort grep {!exists $empty_groups{$_}} keys %$shadow_hash],
        );
        if ($bd->get_range (element => $label) == @sorted_groups) {
            #  cannot be swapped around
            $has_max_range{$label}++;
            #my $idx = bsearchidx {$_ cmp $label} @sorted_labels;
            #splice @sorted_labels, $idx, 1;
            #  if we do this then we also need to filter from other lists
        }
        #warn "We have group balance problems for $label"
        #  if (scalar $gp_list{$label}->keys + $gp_shadow_list{$label}->keys != scalar @sorted_groups);
    }
    foreach my $group (@sorted_groups) {
        my $label_hash = $bd->get_labels_in_group_as_hash_aa($group);
        $lb_list{$group} = List::Unique::DeterministicOrder->new (
            data => [sort keys %$label_hash],
        );
        #  lb_shadow_lists are not used
        #my $shadow_list = $bd->get_labels_not_in_group(group => $group);
        #$lb_shadow_list{$group} = List::Unique::DeterministicOrder->new (
        #    data => [sort grep {!exists $empty_labels{$_}} @$shadow_list],
        #);
        #warn "We have label balance problems for $group"
        #  if (scalar $lb_list{$group}->keys + $lb_shadow_list{$group}->keys != scalar @sorted_labels);
    }

    printf "[RANDOMISE] Randomise using independent swaps for %s labels from %s groups\n",
       scalar @sorted_labels, scalar @sorted_groups;

    $progress_bar->reset;

    #  Basic algorithm:
    #  pick two different groups at random
    #  pick two different labels at random
    #  if label1 is already in group2, or label2 in group1, then try again
    #  else swap the labels between groups
    #  
    #  Nuanced algorithm to avoid excess searching:
    #  pick group1
    #  pick label1 from that group
    #  pick group2 from the set of groups that do not contain label1
    #  pick label2 from group2, where label2 cannot occur in group1
    #
    
    if (!looks_like_number $target_swap_count || $target_swap_count <= 0) {
        $target_swap_count = 2 * $non_zero_mx_cells;
    }
    if (!looks_like_number $max_swap_attempts || $max_swap_attempts <= 0) {
        $max_swap_attempts = 2 * $non_zero_mx_cells;
    }
    my $swap_count = 0;
    my $attempts   = 0;
    say "[RANDOMISE] Target swap count is $target_swap_count, max attempts is $max_swap_attempts";
  MAIN_ITER:
    while ($swap_count < $target_swap_count && $attempts < $max_swap_attempts) {
        $attempts++;
        my $label1 = $sorted_labels[int $rand->rand($n_labels)];
        
        #  is this label swappable?
        next MAIN_ITER if $has_max_range{$label1};

        my $group1 = $gp_list{$label1}->get_key_at_pos(
            int $rand->rand (scalar $gp_list{$label1}->keys)
        );
        #  select from groups not containing $label1
        my $group2 = $gp_shadow_list{$label1}->get_key_at_pos(
            int $rand->rand (scalar $gp_shadow_list{$label1}->keys)
        );

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

        #  swap the labels between groups and update the tracker lists
        #  group2 moves to label1, group1 moves to label2
        $gp_hash{$label1}->{$group2} = delete $gp_hash{$label2}->{$group2};
        $gp_hash{$label2}->{$group1} = delete $gp_hash{$label1}->{$group1};
        $gp_list{$label1}->push ($gp_list{$label2}->delete($group2));
        $gp_list{$label2}->push ($gp_list{$label1}->delete($group1));
        $lb_list{$group1}->push ($lb_list{$group2}->delete($label2));
        $lb_list{$group2}->push ($lb_list{$group1}->delete($label1));
        
        #  the shadows index the list-set complements
        $gp_shadow_list{$label1}->push ($gp_shadow_list{$label2}->delete($group1));
        $gp_shadow_list{$label2}->push ($gp_shadow_list{$label1}->delete($group2));
        #$lb_shadow_list{$group1}->push ($lb_shadow_list{$group2}->delete($label1));
        #$lb_shadow_list{$group2}->push ($lb_shadow_list{$group1}->delete($label2));
        
        $swap_count++;
    }

    if ($attempts == $max_swap_attempts) {
        my $nlabels = scalar @sorted_labels;
        my $ngroups = scalar @sorted_groups;
        say "[RANDOMISE] rand_independent_swaps: max attempts theshold "
          . "$max_swap_attempts reached after $swap_count swaps, for "
          . "basedata $name with $nlabels labels and $ngroups groups\n";
    }
    
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

