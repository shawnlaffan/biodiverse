#  package to abstract some of the functions out
#  of the main Biodiverse::Randomise package
package Biodiverse::Randomise::RandFunctions;

use strict;
use warnings;
use 5.022;
use Time::HiRes qw { time gettimeofday tv_interval };
use List::Unique::DeterministicOrder;
use Scalar::Util qw /blessed/;

sub get_metadata_rand_independent_swaps {
    my $self = shift;

    my @parameters;

    my %metadata = (
        parameters  => \@parameters,
        description => "Randomly swap labels across groups using an "
                     . "implementation of the independent swaps algorithm (REF)\n",
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
    my $swap_count = $args{swap_count} // 10;  # FIXME - set a sensible default

    my $progress_bar = Biodiverse::Progress->new();

    my $progress_text =<<"END_PROGRESS_TEXT"
$name
Independent swaps randomisation
END_PROGRESS_TEXT
;

    my @sorted_groups = sort $bd->get_groups;
    my @sorted_labels = sort $bd->get_labels;
    my $n_groups = scalar @sorted_groups;
    my $n_labels = scalar @sorted_labels;
    
    my (%gp_hash, %gp_list, %lb_list, %gp_shadow_list, %lb_shadow_list);
    foreach my $label (@sorted_labels) {
        my $group_hash = $bd->get_groups_with_label_as_hash_aa($label);
        $gp_hash{$label} = {%$group_hash};
        $gp_list{$label} = List::Unique::DeterministicOrder->new (
            data => [sort keys %$group_hash],
        );
        my $shadow_hash = $bd->get_groups_without_label_as_hash(label => $label);
        $gp_shadow_list{$label} = List::Unique::DeterministicOrder->new (
            data => [sort keys %$shadow_hash],
        );
        warn "We have group balance problems for $label"
          if (scalar $gp_list{$label}->keys + $gp_shadow_list{$label}->keys != scalar @sorted_groups);
    }
    foreach my $group (@sorted_groups) {
        my $label_hash = $bd->get_labels_in_group_as_hash_aa($group);
        $lb_list{$group} = List::Unique::DeterministicOrder->new (
            data => [sort keys %$label_hash],
        );
        my $shadow_list = $bd->get_labels_not_in_group(group => $group);
        $lb_shadow_list{$group} = List::Unique::DeterministicOrder->new (
            data => [sort @$shadow_list],
        );
        warn "We have label balance problems for $group"
          if (scalar $lb_list{$group}->keys + $lb_shadow_list{$group}->keys != scalar @sorted_labels);
    }

    printf "[RANDOMISE] Randomise using independent swaps for %s labels from %s groups\n",
       scalar @sorted_labels, scalar @sorted_groups;

    $progress_bar->reset;

    #  Basic algorithm:
    #  pick two groups at random
    #  pick two labels at random
    #  if label1 is already in group2, or label2 in group1, then try again
    #  else swap the labels between groups
    #  
    #  Nuanced algorithm:
    #  pick group1
    #  pick label1 from that group
    #  pick group2 from the set of groups that do not contain label1
    #  pick label2 from group2, where label2 cannot occur in group1
    #
#warn "Swap count is $swap_count";
  MAIN_ITER:
    for my $iter (1..$swap_count) {
        say "Running independent swap iteration $iter";
        my $label1 = $sorted_labels[int $rand->rand($n_labels)];
        my $group1 = $gp_list{$label1}->get_key_at_pos(
            int $rand->rand (scalar $gp_list{$label1}->keys)
        );
        my $group2 = $gp_shadow_list{$label1}->get_key_at_pos(
            int $rand->rand (scalar $gp_shadow_list{$label1}->keys)
        );
        my $key_count = $lb_list{$group2}->keys;
        my $label2 = $lb_list{$group2}->get_key_at_pos(
            int $rand->rand ($key_count)
        );
        my (%checked);
        while ($lb_list{$group1}->exists ($label2)) {
            $checked{$label2}++;
            next MAIN_ITER if keys %checked > $key_count;  #  no possible swap
            $label2 = $lb_list{$group2}->get_key_at_pos(
                int $rand->rand ($key_count)
            );
        }
        #  swap them and update the tracker lists
        #  group2 moves to label1, group1 moves to label2
        $gp_hash{$label1}->{$group2} = delete $gp_hash{$label2}->{$group2};
        $gp_hash{$label2}->{$group1} = delete $gp_hash{$label1}->{$group1};
        $gp_list{$label1}->push ($gp_list{$label2}->delete($group2));
        $gp_list{$label2}->push ($gp_list{$label1}->delete($group1));
        $lb_list{$group1}->push ($lb_list{$group2}->delete($label2));
        $lb_list{$group2}->push ($lb_list{$group1}->delete($label1));
        if (scalar $gp_list{$label1}->keys != keys %{$gp_hash{$label1}}) {
            warn "group probs with label1 $label1";
        }
        if (scalar $gp_list{$label2}->keys != keys %{$gp_hash{$label2}}) {
            warn "group probs with label2 $label2"; 
        }
        
        #  the shadows index the opposites
        $gp_shadow_list{$label1}->push ($gp_shadow_list{$label2}->delete($group1));
        $gp_shadow_list{$label2}->push ($gp_shadow_list{$label1}->delete($group2));
        $lb_shadow_list{$group1}->push ($lb_shadow_list{$group2}->delete($label1));
        $lb_shadow_list{$group2}->push ($lb_shadow_list{$group1}->delete($label2));

        my $i;
        foreach my $group ($group1, $group2) {
            $i++;
            warn "We have label balance problems for $group $i"
              if (scalar $lb_list{$group}->keys + $lb_shadow_list{$group}->keys != scalar @sorted_labels);
        }
        $i = 0;
        foreach my $label ($label1, $label2) {
            $i++;
            warn "We have group balance problems for $label $i"
              if (scalar $gp_list{$label}->keys + $gp_shadow_list{$label}->keys != scalar @sorted_groups);
        }
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

    foreach my $label (keys %gp_hash) {
        my $this_g_hash = $gp_hash{$label};
        foreach my $group (keys %$this_g_hash) {
            $new_bd->add_element (
                group => $group,
                label => $label,
                sample_count => $this_g_hash->{$group},
            );
        }
    }
    
    return $new_bd;
}


1;

