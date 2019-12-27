package Biodiverse::Indices::Phylogenetic::RefAlias;
use strict;
use warnings;

our $VERSION = '3.00';

use constant HAVE_PANDA_LIB
  => !$ENV{BD_NO_USE_PANDA} && eval 'require Panda::Lib';

use feature 'refaliasing';
no warnings 'experimental::refaliasing';


sub _calc_pe {
    my $self = shift;
    my %args = @_;    

    my $tree_ref         = $args{trimmed_tree};
    my $results_cache    = $args{PE_RESULTS_CACHE};
    my $element_list_all = $args{element_list_all};
    \my %node_ranges = $args{node_range};

    my $bd = $args{basedata_ref} || $self->get_basedata_ref;

    #create a hash of terminal nodes for the taxa present
    my $all_nodes = $tree_ref->get_node_hash;

    my $root_node = $tree_ref->get_tree_ref;

    #  default these to undef - more meaningful than zero
    my ($PE_WE, $PE_WE_P);

    my (%ranges, %wts, %local_ranges, %results);

    foreach my $group (@$element_list_all) {
        my $results_this_gp;
        #  use the cached results for a group if present
        if (exists $results_cache->{$group}) {
            $results_this_gp = $results_cache->{$group};
        }
        #  else build them and cache them
        else {
            my $labels = $bd->get_labels_in_group_as_hash_aa ($group);
            my $nodes_in_path = $self->get_path_lengths_to_root_node (
                @_,
                labels  => $labels,
                el_list => [$group],
            );

            my ($gp_score, %gp_wts, %gp_ranges);

            #  slice assignment wasn't faster according to nytprof and benchmarking
            #@gp_ranges{keys %$nodes_in_path} = @$node_ranges{keys %$nodes_in_path};

            #  Data::Alias avoids hash deref overheads below
            \my %node_lengths = $nodes_in_path;

            #  loop over the nodes and run the calcs
          NODE:
            foreach my $node_name (keys %node_lengths) {
                # Not sure we even need to test for zero ranges.
                # We should never suffer this given the pre_calcs.
                my $range = $node_ranges{$node_name}
                  || next NODE;
                my $wt     = $node_lengths{$node_name} / $range;
                $gp_score += $wt;
                $gp_wts{$node_name}    = $wt;
                $gp_ranges{$node_name} = $range;
            }

            $results_this_gp = {
                PE_WE           => $gp_score,
                PE_WTLIST       => \%gp_wts,
                PE_RANGELIST    => \%gp_ranges,
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
            # ranges are invariant, so can be crashed together
            my $hash_ref = $results_this_gp->{PE_RANGELIST};
            if (HAVE_PANDA_LIB) {
                Panda::Lib::hash_merge (\%ranges, $hash_ref, Panda::Lib::MERGE_LAZY());
            }
            else {
                @ranges{keys %$hash_ref} = values %$hash_ref;
            }

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

    #  need the collated versions
    if (scalar @$element_list_all > 1) {
        $results{PE_WE}     = $PE_WE;
        $results{PE_WTLIST} = \%wts;
        $results{PE_RANGELIST} = \%ranges;
    }

    #  need to set these
    $results{PE_WE_P} = $PE_WE_P;
    $results{PE_LOCAL_RANGELIST} = \%local_ranges;

    return wantarray ? %results : \%results;
}



1;
