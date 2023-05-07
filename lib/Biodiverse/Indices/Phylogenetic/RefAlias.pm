package Biodiverse::Indices::Phylogenetic::RefAlias;
use strict;
use warnings;

our $VERSION = '4.99_001';

use feature 'refaliasing';
no warnings 'experimental::refaliasing';

use List::Util qw /sum/;

sub _calc_pe {
    my $self = shift;
    my %args = @_;    

    my $tree_ref         = $args{trimmed_tree};
    my $results_cache    = $args{PE_RESULTS_CACHE};
    my $element_list_all = $args{element_list_all};
    \my %node_ranges     = $args{node_range};
    \my %rw_node_lengths = $args{inverse_range_weighted_node_lengths};

    my $bd = $args{basedata_ref} || $self->get_basedata_ref;

    #  default these to undef - more meaningful than zero
    my ($PE_WE, $PE_WE_P);

    my (%wts, %local_ranges, %results);

    #  prob a micro-optimisation, but might avoid
    #  some looping below when collating weights
    #  and one group has many more labels than the other
    if (@$element_list_all == 2) {
        my $count0 = $bd->get_richness_aa ($element_list_all->[0]);
        my $count1 = $bd->get_richness_aa ($element_list_all->[1]);
        if ($count1 > $count0) {
            $element_list_all = [
                $element_list_all->[1],
                $element_list_all->[0],
            ];
        }
    }

    foreach my $group (@$element_list_all) {
        my $results_this_gp;
        #  use the cached results for a group if present
        if (exists $results_cache->{$group}) {
            $results_this_gp = $results_cache->{$group};
        }
        #  else build them and cache them
        else {
            my $labels = $bd->get_labels_in_group_as_hash_aa ($group);
            
            #  This is a slow point for many calcs but the innards are cached
            #  and the cost is amortised when PD is also calculated
            my $nodes_in_path = $self->get_path_lengths_to_root_node (
                @_,
                labels  => $labels,
                el_list => [$group],
            );

            my %gp_wts    = %rw_node_lengths{keys %$nodes_in_path};
            my $gp_score  = sum values %gp_wts;

          #  old approach - left here as notes for the
          #  non-equal area case in the future
          #  #  loop over the nodes and run the calcs
          #  refaliasing avoids hash deref overheads below in the loop
          #  albeit the loop is not used any more...
          #  \my %nodes = $nodes_in_path;
          #NODE:
          #  foreach my $node_name (keys %node_lengths) {
          #      # Not sure we even need to test for zero ranges.
          #      # We should never suffer this given the pre_calcs.
          #      #my $range = $node_ranges{$node_name}
          #      #  or next NODE;
          #      #my $wt     = $node_lengths{$node_name} / $range;
          #      my $wt = $rw_node_lengths{$node_name};
          #      #say STDERR (sprintf ('%s %f %f', $node_name, $wt, $wt2));
          #      $gp_score += $wt;
          #      #$gp_wts{$node_name}    = $wt;
          #      #$gp_ranges{$node_name} = $range;
          #  }

            $results_this_gp = {
                PE_WE           => $gp_score,
                PE_WTLIST       => \%gp_wts,
            };

            $results_cache->{$group} = $results_this_gp;
        }

        if (defined $results_this_gp->{PE_WE}) {
            $PE_WE += $results_this_gp->{PE_WE};
        }

        #  Avoid some redundant slicing and dicing when we have only one group
        #  Pays off when processing large data sets
        if (scalar @$element_list_all == 1) {
            #  no need to collate anything so make a shallow copy
            @results{keys %$results_this_gp} = values %$results_this_gp;
            #  but we do need to add to the local range hash
            my $hashref = $results_this_gp->{PE_WTLIST};
            @local_ranges{keys %$hashref} = (1) x scalar keys %$hashref;
        }
        else {
            # refalias might be a nano-optimisation here...
            \my %wt_hash = $results_this_gp->{PE_WTLIST};

            # weights need to be summed,
            # unless we are starting from a blank slate
            if (keys %wts) {
                foreach my $node (keys %wt_hash) {
                    $wts{$node} += $wt_hash{$node};
                    $local_ranges{$node}++;
                }
            }
            else {
                %wts = %wt_hash;
                @local_ranges{keys %wt_hash} = (1) x scalar keys %wt_hash;
            }
        }
    }

    {
        no warnings 'uninitialized';
        my $total_tree_length = $tree_ref->get_total_tree_length;

        #Phylogenetic endemism = sum for all nodes of: (branch length/total tree length) / node range
        $PE_WE_P = eval {$PE_WE / $total_tree_length};
    }

    #  need the collated versions for multiple elements
    if (scalar @$element_list_all > 1) {
        $results{PE_WE}     = $PE_WE;
        $results{PE_WTLIST} = \%wts;
        my %nranges = %node_ranges{keys %wts};
        $results{PE_RANGELIST} = \%nranges;
    }
    else {
        my %nranges = %node_ranges{keys %{$results{PE_WTLIST}}};
        $results{PE_RANGELIST} = \%nranges;
    }

    #  need to set these
    $results{PE_WE_P} = $PE_WE_P;
    $results{PE_LOCAL_RANGELIST} = \%local_ranges;

    return wantarray ? %results : \%results;
}



1;
