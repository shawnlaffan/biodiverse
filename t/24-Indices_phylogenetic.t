#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

#  don't test plugins
local $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;

my $generate_result_sets = 0;

use Test::Lib;
use rlib;
use Test::Most;
use List::Util qw /sum/;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
    :tree
    :utils
};

my @calcs = qw/
    calc_pe_central_cwe
    calc_count_labels_on_tree
    calc_labels_not_on_tree
    calc_labels_on_tree
    calc_last_shared_ancestor
    calc_pd
    calc_pd_clade_contributions
    calc_pd_clade_loss
    calc_pd_clade_loss_ancestral
    calc_pd_endemism
    calc_pd_local
    calc_pd_node_list
    calc_pd_terminal_node_count
    calc_pd_terminal_node_list
    calc_pe
    calc_pe_central
    calc_pe_central_lists
    calc_pe_clade_contributions
    calc_pe_clade_loss
    calc_pe_clade_loss_ancestral
    calc_pe_lists
    calc_pe_single
    calc_phylo_aed
    calc_phylo_aed_t
    calc_phylo_aed_t_wtlists
    calc_phylo_corrected_weighted_endemism
    calc_phylo_corrected_weighted_rarity
    calc_phylo_abundance
/;

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @test_subs = grep {$_ =~ 'main::test_'} $obj->functions();


exit main( @ARGV );

sub main {
    my @args  = @_;

    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
                if not my $func = (__PACKAGE__->can( 'test_' . $name ) || __PACKAGE__->can( $name ));
            $func->();
        }
        done_testing;
        return 0;
    }

    foreach my $sub (@test_subs) {
        no strict 'refs';
        $sub->();
    }
    
    done_testing;
    return 0;
}

sub test_indices {
    run_indices_test1 (
        calcs_to_test      => [@calcs],
        calc_topic_to_test => ['Phylogenetic Indices', 'Phylogenetic Endemism Indices'],
        generate_result_sets => $generate_result_sets,
    );
}


sub test_phylo_abundance_binarised {
    
    my @calcs = qw/
        calc_phylo_abundance
        calc_labels_on_tree
    /;

    my $cell_sizes = [200000, 200000];
    my $bd   = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
    $bd->binarise_sample_counts;
    
    my $tree = get_tree_object_from_sample_data();
    #  binarise - need to also do the zero length nodes, hence we don't use the tree method
    $tree->delete_cached_values;
    foreach my $node ($tree->get_node_refs) {  
        $node->set_length (length => 1);
        $node->delete_cached_values;
    }
    #  reset all the total length values
    $tree->reset_total_length;
    $tree->reset_total_length_below;

    my $sp = $bd->add_spatial_output (name => 'abundances should equal branch counts');
    $sp->run_analysis (
        calculations       => [@calcs],
        spatial_conditions => ['sp_self_only()'],
        tree_ref           => $tree,
    );

    my $elts = $sp->get_element_list;
    subtest 'abundances should equal branch counts' => sub {
        foreach my $elt (@$elts) {
            my $results_list = $sp->get_list_ref (
                list    => 'SPATIAL_RESULTS',
                element => $elt,
            );
            my $abundance = $results_list->{PHYLO_ABUNDANCE};

            my $branch_list = $sp->get_list_ref (
                list    => 'PHYLO_ABUNDANCE_BRANCH_HASH',
                element => $elt,
            );
            my $b_sum = sum values %$branch_list;
            
            is ($abundance, $b_sum, "Got $abundance for $elt");

            #  should check all named descendants, but the test data only have named terminals
            subtest 'branch abundance matches terminal element count' => sub {
                foreach my $branch (keys %$branch_list) {
                    my $node_ref = $tree->get_node_ref(node => $branch);
                    my $descendants = $node_ref->get_terminal_elements;
                    my @descendants_in_sample = grep {exists $branch_list->{$_}} keys %$descendants;
                    is ($branch_list->{$branch}, scalar @descendants_in_sample, "$branch, $elt");
                }
            }
        }
    }
}

sub test_pe_central_and_whole {
    my @calcs = qw/
        calc_pe
        calc_pe_lists
        calc_pe_central
        calc_pe_central_lists
        calc_phylo_corrected_weighted_endemism
        calc_pe_central_cwe
        calc_pd
    /;

    #  should derive from metadata
    my %scalar_indices_to_check;
    foreach my $whole (qw /PE_WE PE_WE_P PE_CWE/) {
        my $central = $whole;
        $central =~ s/^PE/PEC/;
        $scalar_indices_to_check{$whole} = $central;
    }
    $scalar_indices_to_check{PD} = 'PEC_CWE_PD';
    my %list_indices_to_check;
    foreach my $whole (qw /PE_WTLIST PE_LOCAL_RANGELIST PE_RANGELIST/) {
        my $central = $whole;
        $central =~ s/^PE/PEC/;
        $list_indices_to_check{$whole} = $central;
    }

    my $cell_sizes = [200000, 200000];
    my $bd   = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
    my $tree = get_tree_object_from_sample_data();

    $bd->build_spatial_index(resolutions => [200000, 200000]);

    #  should ad a def query since we don't need the full set of results
    my $sp1 = $bd->add_spatial_output (name => 'PE should be the same');
    $sp1->run_analysis (
        calculations       => [@calcs],
        spatial_conditions => ['sp_circle(radius => 200000)'],
        tree_ref           => $tree,
    );

    my ($sp1_res_w, $sp1_res_c) = get_pe_check_hashes (
        $sp1,
        \%scalar_indices_to_check,
        \%list_indices_to_check,
    );

    is_deeply (
        $sp1_res_w,
        $sp1_res_c,
        'PE whole and central indices the same for one neighour set',
    );

    my $sp2 = $bd->add_spatial_output (name => 'PE should not be the same');
    $sp2->run_analysis (
        calculations       => [@calcs],
        spatial_conditions => ['sp_self_only()', 'sp_circle(radius => 400000)'],
        tree_ref           => $tree,
    );

    #  no guarantees that the phylo CWE scores will be smaller for the central variant
    delete @scalar_indices_to_check{qw/PEC_CWE PE_CWE PD/};

    my ($sp2_res_w, $sp2_res_c) = get_pe_check_hashes (
        $sp2,
        \%scalar_indices_to_check,
        \%list_indices_to_check,
    );

    isnt_deeply (
        $sp2_res_w,
        $sp2_res_c,
        'PE whole and central indices are not the same for two neighour sets',
    );

    #  need to check the central results are <= the whole results and ranges are the same
    subtest 'PE_C <= PE_W' => sub {
        foreach my $elt (sort keys %$sp2_res_w) {
            my $w_hash = $sp2_res_w->{$elt};
            my $c_hash = $sp2_res_c->{$elt};
            foreach my $index (sort keys %$w_hash) {
                my $reftype = ref ($w_hash->{$index});
                if (!$reftype) {
                    ok (
                        $c_hash->{$index} <= $w_hash->{$index},
                        "$index: central <= whole",
                    );
                }
                else {
                    my $w_h_ref = $w_hash->{$index};
                    my $c_h_ref = $c_hash->{$index};
                    ok (
                        scalar keys %$c_h_ref <= scalar keys %$w_h_ref,
                        "$index key count: central <= whole",
                    );
                    #  ranges should be ==, weights <=
                    if ($index =~ /RANGE/) {
                        foreach my $key (sort keys %$c_h_ref) {
                            ok (
                                $c_h_ref->{$key} == $w_h_ref->{$key},
                                "$index->\{$key}: central == whole",
                            );
                        }
                    }
                    else {
                        foreach my $key (sort keys %$c_h_ref) {
                            ok (
                                $c_h_ref->{$key} <= $w_h_ref->{$key},
                                "$index->\{$key}: central <= whole",
                            );
                        }
                    }
                }
            }

        }
    };

    #  now cross check that PEC_WE = sum (values PEC_WTLIST)
    subtest 'PEC_WE = sum (values PEC_WTLIST)' => sub {
        my $sp = $sp2;
        my $elts = $sp->get_element_list;

        foreach my $elt (@$elts) {
            my $sp_results_list = $sp->get_list_ref (
                list    => 'SPATIAL_RESULTS',
                element => $elt,
            );
            my $wt_list = $sp->get_list_ref (
                list    => 'PEC_WTLIST',
                element => $elt,
            );
            my $v1 = sprintf '%14f', $sp_results_list->{PEC_WE};
            my $v2 = sprintf '%14f', sum (values %$wt_list);
            is ($v1, $v2, $elt);
        }
    };

    return;
}


sub get_pe_check_hashes {
    my ($sp, $scalar_indices_to_check, $list_indices_to_check) = @_;

    my (%sp_res_w, %sp_res_c);

    my $elts = $sp->get_element_list;

    foreach my $elt (@$elts) {
        my $results_list = $sp->get_list_ref (
            list    => 'SPATIAL_RESULTS',
            element => $elt,
        );
        foreach my $idx_whole (sort keys %$scalar_indices_to_check) {
            my $idx_central = $scalar_indices_to_check->{$idx_whole};
            $sp_res_w{$elt}{$idx_whole} = 0 + sprintf '%.12f', $results_list->{$idx_whole};
            $sp_res_c{$elt}{$idx_whole} = 0 + sprintf '%.12f', $results_list->{$idx_central};
        }

        foreach my $idx_whole (sort keys %$list_indices_to_check) {
            my $idx_central = $list_indices_to_check->{$idx_whole};
            my $results_list_w = $sp->get_list_ref (
                list    => $idx_whole,
                element => $elt,
            );
            my $results_list_c = $sp->get_list_ref (
                list    => $idx_central,
                element => $elt,
            );
            #  don't sprintf these - they are lists
            $sp_res_w{$elt}{$idx_whole} = $results_list_w;
            $sp_res_c{$elt}{$idx_whole} = $results_list_c;
        }
    }

    return \%sp_res_w, \%sp_res_c;
}


sub test_sum_to_pd {
    #  these indices should sum to PD when all groups are used in the analysis
    #  some lists should also sum to 1 - need to change the subroutine name

    my @calcs = qw/
        calc_pe
        calc_phylo_aed_t
        calc_phylo_aed_t_wtlists
        calc_phylo_corrected_weighted_rarity
        calc_phylo_corrected_weighted_endemism
        calc_pd
    /;

    my $cell_sizes = [200000, 200000];
    my $bd   = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
    my $tree = get_tree_object_from_sample_data();

    my $sp = $bd->add_spatial_output (name => 'should sum to PD, select_all');
    $sp->run_analysis (
        calculations       => [@calcs],
        spatial_conditions => ['sp_select_all()'],
        tree_ref           => $tree,
    );

    my $elts = $sp->get_element_list;
    my $elt_to_check = $elts->[0];  #  they will all be the same value
    my $results_list = $sp->get_list_ref (
        list    => 'SPATIAL_RESULTS',
        element => $elt_to_check,
    );

    my $pd = snap_to_precision (value => $results_list->{PD}, precision => '%.10f');
    
    my @indices_sum_to_pd = qw /PE_WE PHYLO_AED_T/;  #  add more
    #  these need to equal 1 for sp_select_all()
    my @indices_should_be_one = qw /PHYLO_RARITY_CWR PE_CWE/;
    #   these need to sum to 1 across nbrhoods
    my @lists_sum_to_one = qw /PHYLO_AED_T_WTLIST_P/;

    foreach my $index (@indices_sum_to_pd) {
        my $result = snap_to_precision (value => $results_list->{$index}, precision => '%.10f');
        is ($result, $pd, "$index equals PD, sp_select_all()");
    }
    foreach my $index (@indices_should_be_one) {
        my $result = snap_to_precision (value => $results_list->{$index}, precision => '%.10f');
        is ($result, 1, "$index is 1, sp_select_all()");
    }

    foreach my $list_name (@lists_sum_to_one) {
        my $list = $sp->get_list_ref (
            list    => $list_name,
            element => $elt_to_check,
        );
        my $sum  = sum values %$list;
        $sum = snap_to_precision (value => $sum, precision => '%.10f');
        is ($sum, 1, "$list_name sums to 1, sp_select_all()");
    }

    #  should also do an sp_self_only and then sum the values across all elements
    $sp = $bd->add_spatial_output (name => 'should sum to PD, self_only');
    $sp->run_analysis (
        calculations       => [@calcs],
        spatial_conditions => ['sp_self_only()'],
        tree_ref           => $tree,
    );

    my %sums;
    foreach my $element (@$elts) {
        my $results_list = $sp->get_list_ref (
            list    => 'SPATIAL_RESULTS',
            element => $element,
        );
        foreach my $index (@indices_sum_to_pd) {
            $sums{$index} += $results_list->{$index};
        }
    }

    foreach my $index (@indices_sum_to_pd) {
        my $result = snap_to_precision (value => $sums{$index}, precision => '%.10f');
        is ($result, $pd, "$index sums to PD, sp_self_only()");
    }
    
    foreach my $list_name (@lists_sum_to_one) {
        subtest "$list_name sums to 1 or undef, sp_self_only()" => sub {
            foreach my $element (@$elts) {
                my $list = $sp->get_list_ref (
                    list    => $list_name,
                    element => $element,
                );
                my $sum = sum values %$list;
                $sum //= 1;  #  undef is valid for samples with no tree terminals
                my $result = snap_to_precision (value => $sum, precision => '%.10f');
                is ($result, 1, "$list_name sums to 1 for $element, sp_self_only()");
            }
        };
    }

}

#  now try with extra labels that aren't on the tree
sub test_extra_labels_in_bd {
    my $cb = sub {
        my %args = @_;
        my $bd = $args{basedata_ref};
        my $el_list1 = $args{element_list1};
        #  add a new label to all of the groups to be sure we get coverage
        foreach my $group ($bd->get_groups) {  
            $bd->add_element (
                group => $group,
                label => 'namenotontree:atall',
            );
        }
    };
    
    my $overlay1 = {
        'PHYLO_LABELS_NOT_ON_TREE_N' => 1,
        'PHYLO_LABELS_NOT_ON_TREE_P' => (1/3),
        'PHYLO_LABELS_NOT_ON_TREE' => {
            'namenotontree:atall' => 1,
        },
    };
    my $overlay2 = {
        'PHYLO_LABELS_NOT_ON_TREE_N' => 1,
        'PHYLO_LABELS_NOT_ON_TREE_P' => (1/15),
        'PHYLO_LABELS_NOT_ON_TREE' => {
            'namenotontree:atall' => 1,
        },
    };

    my %expected_results_overlay = (
        1 => $overlay1,
        2 => $overlay2,
    );

    my @calcs_to_test = qw/calc_phylo_aed calc_labels_not_on_tree/;
    run_indices_test1 (
        calcs_to_test   => \@calcs_to_test,
        callbacks       => [$cb],
        no_strict_match => 1,
        expected_results_overlay => \%expected_results_overlay,
    );
    
}


#  check we trim the tree properly
sub test_pe_with_extra_nodes_in_tree {
    my $cb = sub {
        my %args = @_;
        my $tree = $args{tree_ref};
        my $root = $tree->get_root_node;
        use Biodiverse::TreeNode;
        my $node1 = Biodiverse::TreeNode-> new (
            name   => 'EXTRA_NODE 1',
            length => 1,
        );
        my $node2 = Biodiverse::TreeNode-> new (
            name   => 'EXTRA_NODE 2',
            length => 1,
        );
        $root->add_children (children => [$node1, $node2]);
        #  add it to the Biodiverse::Tree object as well so the trimming works
        $tree->add_node (node_ref => $node1);
        $tree->add_node (node_ref => $node2);
    };

    my @calcs_to_test = qw/
        calc_pe_clade_contributions
        calc_pe_lists
        calc_pe_single
        calc_pe
    /;

    run_indices_test1 (
        calcs_to_test   => \@calcs_to_test,
        callbacks       => [$cb],
        no_strict_match => 1,
    );
    
}

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   LAST_SHARED_ANCESTOR_DEPTH        => 2,
    LAST_SHARED_ANCESTOR_DIST_TO_ROOT => '0.0128415672018619',
    LAST_SHARED_ANCESTOR_DIST_TO_TIP  => '0.979927663567369',
    LAST_SHARED_ANCESTOR_LENGTH       => '0.00291112550535999',
    LAST_SHARED_ANCESTOR_POS_REL      => '0.0129350979098253',
    PD             => '9.55665348225732',
    PD_CLADE_CONTR => {
        '30___'      => '0.07091000411',
        '31___'      => '0.13149055874',
        '32___'      => '0.21356560912',
        '33___'      => '0.30160886872',
        '34___'      => '0.14036282951',
        '35___'      => '0.44542420069',
        '36___'      => '0.09636040446',
        '37___'      => '0.15899646641',
        '38___'      => '0.22448270999',
        '39___'      => '0.30803974509',
        '41___'      => '0.31597847204',
        '42___'      => '0.76741890888',
        '44___'      => '0.09751199821',
        '45___'      => '0.86769304169',
        '49___'      => '0.86983053519',
        '50___'      => '0.86995769669',
        '51___'      => '0.12869857276',
        '52___'      => '0.99896088712',
        '58___'      => '1',
        '59___'      => '1',
        'Genus:sp1'  => '0.06058055464',
        'Genus:sp10' => '0.08207505038',
        'Genus:sp11' => '0.05086512627',
        'Genus:sp12' => '0.06548624358',
        'Genus:sp15' => '0.06058055464',
        'Genus:sp20' => '0.05231956991',
        'Genus:sp23' => '0.04549527819',
        'Genus:sp24' => '0.02615978496',
        'Genus:sp25' => '0.02615978496',
        'Genus:sp26' => '0.05231956991',
        'Genus:sp27' => '0.06975942655',
        'Genus:sp29' => '0.06263606195',
        'Genus:sp30' => '0.04549527819',
        'Genus:sp5'  => '0.0627834839'
    },
    PD_CLADE_CONTR_P => {
        '30___'      => '0.03199200244',
        '31___'      => '0.05932373477',
        '32___'      => '0.09635299805',
        '33___'      => '0.13607489923',
        '34___'      => '0.0633265791',
        '35___'      => '0.20095912127',
        '36___'      => '0.04347429299',
        '37___'      => '0.0717333951',
        '38___'      => '0.101278395',
        '39___'      => '0.13897627564',
        '41___'      => '0.14255793912',
        '42___'      => '0.34623136627',
        '44___'      => '0.04399385',
        '45___'      => '0.39147139047',
        '49___'      => '0.39243574942',
        '50___'      => '0.39249312004',
        '51___'      => '0.05806409273',
        '52___'      => '0.45069464512',
        '58___'      => '0.45116345488',
        '59___'      => '0.45116345488',
        'Genus:sp1'  => '0.02733173233',
        'Genus:sp10' => '0.03702926329',
        'Genus:sp11' => '0.0229484861',
        'Genus:sp12' => '0.0295449999',
        'Genus:sp15' => '0.02733173233',
        'Genus:sp20' => '0.02360467792',
        'Genus:sp23' => '0.02052580689',
        'Genus:sp24' => '0.01180233896',
        'Genus:sp25' => '0.01180233896',
        'Genus:sp26' => '0.02360467792',
        'Genus:sp27' => '0.03147290389',
        'Genus:sp29' => '0.02825910211',
        'Genus:sp30' => '0.02052580689',
        'Genus:sp5'  => '0.0283256135'
    },
    PD_CLADE_LOSS_ANC => {
        '30___'      => '0',
        '31___'      => '0',
        '32___'      => '0',
        '33___'      => '0',
        '34___'      => '0',
        '35___'      => '0',
        '36___'      => '0',
        '37___'      => '0',
        '38___'      => '0',
        '39___'      => '0.0758676625937378',
        '41___'      => '0',
        '42___'      => '0',
        '44___'      => '0',
        '45___'      => '0.021642523058544',
        '49___'      => '0.00121523842637217',
        '50___'      => '0',
        '51___'      => '0',
        '52___'      => '0.00993044169650226',
        '58___'      => '0',
        '59___'      => '0',
        'Genus:sp1'  => '0',
        'Genus:sp10' => '0',
        'Genus:sp11' => '0',
        'Genus:sp12' => '0',
        'Genus:sp15' => '0',
        'Genus:sp20' => '0',
        'Genus:sp23' => '0',
        'Genus:sp24' => '0',
        'Genus:sp25' => '0',
        'Genus:sp26' => '0',
        'Genus:sp27' => '0.265221710543839',
        'Genus:sp29' => '0',
        'Genus:sp30' => '0',
        'Genus:sp5'  => '0.077662337662338'
    },
    PD_CLADE_LOSS_ANC_P => {
        '30___'      => '0',
        '31___'      => '0',
        '32___'      => '0',
        '33___'      => '0',
        '34___'      => '0',
        '35___'      => '0',
        '36___'      => '0',
        '37___'      => '0',
        '38___'      => '0',
        '39___'      => '0.0251242652800147',
        '41___'      => '0',
        '42___'      => '0',
        '44___'      => '0',
        '45___'      => '0.00260317829835918',
        '49___'      => '0.000146169755268683',
        '50___'      => '0',
        '51___'      => '0',
        '52___'      => '0.00103911287721574',
        '58___'      => '0',
        '59___'      => '0',
        'Genus:sp1'  => '0',
        'Genus:sp10' => '0',
        'Genus:sp11' => '0',
        'Genus:sp12' => '0',
        'Genus:sp15' => '0',
        'Genus:sp20' => '0',
        'Genus:sp23' => '0',
        'Genus:sp24' => '0',
        'Genus:sp25' => '0',
        'Genus:sp26' => '0',
        'Genus:sp27' => '0.284606737276569',
        'Genus:sp29' => '0',
        'Genus:sp30' => '0',
        'Genus:sp5'  => '0.114603296282101'
    },
    PD_CLADE_LOSS_CONTR => {
        '30___'      => '0.07091000411',
        '31___'      => '0.13149055874',
        '32___'      => '0.21356560912',
        '33___'      => '0.30160886872',
        '34___'      => '0.14036282951',
        '35___'      => '0.44542420069',
        '36___'      => '0.09636040446',
        '37___'      => '0.15899646641',
        '38___'      => '0.22448270999',
        '39___'      => '0.31597847204',
        '41___'      => '0.31597847204',
        '42___'      => '0.76741890888',
        '44___'      => '0.09751199821',
        '45___'      => '0.86995769669',
        '49___'      => '0.86995769669',
        '50___'      => '0.86995769669',
        '51___'      => '0.12869857276',
        '52___'      => '1',
        '58___'      => '1',
        '59___'      => '1',
        'Genus:sp1'  => '0.06058055464',
        'Genus:sp10' => '0.08207505038',
        'Genus:sp11' => '0.05086512627',
        'Genus:sp12' => '0.06548624358',
        'Genus:sp15' => '0.06058055464',
        'Genus:sp20' => '0.05231956991',
        'Genus:sp23' => '0.04549527819',
        'Genus:sp24' => '0.02615978496',
        'Genus:sp25' => '0.02615978496',
        'Genus:sp26' => '0.05231956991',
        'Genus:sp27' => '0.09751199821',
        'Genus:sp29' => '0.06263606195',
        'Genus:sp30' => '0.04549527819',
        'Genus:sp5'  => '0.07091000411'
    },
    PD_CLADE_LOSS_CONTR_P => {
        '30___'      => '0.03199200244',
        '31___'      => '0.05932373477',
        '32___'      => '0.09635299805',
        '33___'      => '0.13607489923',
        '34___'      => '0.0633265791',
        '35___'      => '0.20095912127',
        '36___'      => '0.04347429299',
        '37___'      => '0.0717333951',
        '38___'      => '0.101278395',
        '39___'      => '0.14255793912',
        '41___'      => '0.14255793912',
        '42___'      => '0.34623136627',
        '44___'      => '0.04399385',
        '45___'      => '0.39249312004',
        '49___'      => '0.39249312004',
        '50___'      => '0.39249312004',
        '51___'      => '0.05806409273',
        '52___'      => '0.45116345488',
        '58___'      => '0.45116345488',
        '59___'      => '0.45116345488',
        'Genus:sp1'  => '0.02733173233',
        'Genus:sp10' => '0.03702926329',
        'Genus:sp11' => '0.0229484861',
        'Genus:sp12' => '0.0295449999',
        'Genus:sp15' => '0.02733173233',
        'Genus:sp20' => '0.02360467792',
        'Genus:sp23' => '0.02052580689',
        'Genus:sp24' => '0.01180233896',
        'Genus:sp25' => '0.01180233896',
        'Genus:sp26' => '0.02360467792',
        'Genus:sp27' => '0.04399385',
        'Genus:sp29' => '0.02825910211',
        'Genus:sp30' => '0.02052580689',
        'Genus:sp5'  => '0.03199200244'
    },
    PD_CLADE_LOSS_SCORE => {
        '30___'      => '0.677662337662338',
        '31___'      => '1.25660970608339',
        '32___'      => '2.04097252208995',
        '33___'      => '2.88237144552411',
        '34___'      => '1.34139892343415',
        '35___'      => '4.25676473855887',
        '36___'      => '0.920882994796038',
        '37___'      => '1.51947413437078',
        '38___'      => '2.14530347215134',
        '39___'      => '3.0196967651861',
        '41___'      => '3.0196967651861',
        '42___'      => '7.33395658792072',
        '44___'      => '0.931888377210506',
        '45___'      => '8.31388425148809',
        '49___'      => '8.31388425148809',
        '50___'      => '8.31388425148809',
        '51___'      => '1.22992766356737',
        '52___'      => '9.55665348225732',
        '58___'      => '9.55665348225732',
        '59___'      => '9.55665348225732',
        'Genus:sp1'  => '0.578947368421053',
        'Genus:sp10' => '0.784362816006563',
        'Genus:sp11' => '0.486100386100386',
        'Genus:sp12' => '0.625829337780557',
        'Genus:sp15' => '0.578947368421053',
        'Genus:sp20' => '0.5',
        'Genus:sp23' => '0.434782608695652',
        'Genus:sp24' => '0.25',
        'Genus:sp25' => '0.25',
        'Genus:sp26' => '0.5',
        'Genus:sp27' => '0.931888377210506',
        'Genus:sp29' => '0.598591139574746',
        'Genus:sp30' => '0.434782608695652',
        'Genus:sp5'  => '0.677662337662338'
    },
    PD_CLADE_SCORE => {
        '30___'      => '0.677662337662338',
        '31___'      => '1.25660970608339',
        '32___'      => '2.04097252208995',
        '33___'      => '2.88237144552411',
        '34___'      => '1.34139892343415',
        '35___'      => '4.25676473855887',
        '36___'      => '0.920882994796038',
        '37___'      => '1.51947413437078',
        '38___'      => '2.14530347215134',
        '39___'      => '2.94382910259237',
        '41___'      => '3.0196967651861',
        '42___'      => '7.33395658792072',
        '44___'      => '0.931888377210506',
        '45___'      => '8.29224172842954',
        '49___'      => '8.31266901306171',
        '50___'      => '8.31388425148809',
        '51___'      => '1.22992766356737',
        '52___'      => '9.54672304056082',
        '58___'      => '9.55665348225732',
        '59___'      => '9.55665348225732',
        'Genus:sp1'  => '0.578947368421053',
        'Genus:sp10' => '0.784362816006563',
        'Genus:sp11' => '0.486100386100386',
        'Genus:sp12' => '0.625829337780557',
        'Genus:sp15' => '0.578947368421053',
        'Genus:sp20' => '0.5',
        'Genus:sp23' => '0.434782608695652',
        'Genus:sp24' => '0.25',
        'Genus:sp25' => '0.25',
        'Genus:sp26' => '0.5',
        'Genus:sp27' => '0.666666666666667',
        'Genus:sp29' => '0.598591139574746',
        'Genus:sp30' => '0.434782608695652',
        'Genus:sp5'  => '0.6'
    },
    PD_ENDEMISM           => undef,
    PD_ENDEMISM_P         => undef,
    PD_ENDEMISM_WTS       => {},
    PD_INCLUDED_NODE_LIST => {
        '30___'      => '0.077662337662338',
        '31___'      => '0.098714969241285',
        '32___'      => '0.106700478344225',
        '33___'      => '0.05703610742759',
        '34___'      => '0.341398923434153',
        '35___'      => '0.03299436960061',
        '36___'      => '0.051317777404734',
        '37___'      => '0.11249075347436',
        '38___'      => '0.0272381982058111',
        '39___'      => '0.172696292660468',
        '41___'      => '0.075867662593738',
        '42___'      => '0.057495084175743',
        '44___'      => '0.265221710543839',
        '45___'      => '0.026396763298318',
        '49___'      => '0.020427284632173',
        '50___'      => '0.00121523842637206',
        '51___'      => '0.729927663567369',
        '52___'      => '0.00291112550535999',
        '58___'      => '0.00993044169650192',
        '59___'      => 0,
        'Genus:sp1'  => '0.578947368421053',
        'Genus:sp10' => '0.784362816006563',
        'Genus:sp11' => '0.486100386100386',
        'Genus:sp12' => '0.625829337780557',
        'Genus:sp15' => '0.578947368421053',
        'Genus:sp20' => '0.5',
        'Genus:sp23' => '0.434782608695652',
        'Genus:sp24' => '0.25',
        'Genus:sp25' => '0.25',
        'Genus:sp26' => '0.5',
        'Genus:sp27' => '0.666666666666667',
        'Genus:sp29' => '0.598591139574746',
        'Genus:sp30' => '0.434782608695652',
        'Genus:sp5'  => '0.6'
    },
    PD_INCLUDED_TERMINAL_NODE_COUNT => 14,
    PD_INCLUDED_TERMINAL_NODE_LIST  => {
        'Genus:sp1'  => '0.578947368421053',
        'Genus:sp10' => '0.784362816006563',
        'Genus:sp11' => '0.486100386100386',
        'Genus:sp12' => '0.625829337780557',
        'Genus:sp15' => '0.578947368421053',
        'Genus:sp20' => '0.5',
        'Genus:sp23' => '0.434782608695652',
        'Genus:sp24' => '0.25',
        'Genus:sp25' => '0.25',
        'Genus:sp26' => '0.5',
        'Genus:sp27' => '0.666666666666667',
        'Genus:sp29' => '0.598591139574746',
        'Genus:sp30' => '0.434782608695652',
        'Genus:sp5'  => '0.6'
    },
    PD_LOCAL            => '9.54381191505546',
    PD_LOCAL_P          => '0.450557212765022',
    PD_P                => '0.451163454880594',
    PD_P_per_taxon      => '0.0322259610628996',
    PD_per_taxon        => '0.682618105875523',
    PEC_CWE             => '0.478441635510817',
    PEC_CWE_PD          => '1.49276923076923',
    PEC_LOCAL_RANGELIST => {
        '34___'      => 4,
        '35___'      => 4,
        '42___'      => 4,
        '45___'      => 4,
        '49___'      => 4,
        '50___'      => 4,
        '52___'      => 5,
        '58___'      => 5,
        '59___'      => 5,
        'Genus:sp20' => 4,
        'Genus:sp26' => 2
    },
    PEC_RANGELIST => {
        '34___'      => 9,
        '35___'      => 53,
        '42___'      => 107,
        '45___'      => 107,
        '49___'      => 112,
        '50___'      => 115,
        '52___'      => 116,
        '58___'      => 127,
        '59___'      => 127,
        'Genus:sp20' => 9,
        'Genus:sp26' => 3
    },
    PEC_WE     => '0.714202952209456',
    PEC_WE_P   => '0.0337170613126205',
    PEC_WTLIST => {
        '34___'      => '0.151732854859624',
        '35___'      => '0.00249014110193283',
        '42___'      => '0.00214934894114927',
        '45___'      => '0.000986794889656748',
        '49___'      => '0.000729545879720464',
        '50___'      => '4.22691626564195e-005',
        '52___'      => '0.000125479547644827',
        '58___'      => '0.000390962271515824',
        '59___'      => 0,
        'Genus:sp20' => '0.222222222222222',
        'Genus:sp26' => '0.333333333333333'
    },
    PE_CLADE_CONTR => {
        '30___'      => '0.04198877081',
        '31___'      => '0.08471881937',
        '32___'      => '0.1307924555',
        '33___'      => '0.15064931213',
        '34___'      => '0.44677808478',
        '35___'      => '0.59900036271',
        '36___'      => '0.02504621139',
        '37___'      => '0.04007247444',
        '38___'      => '0.07218589162',
        '39___'      => '0.10280605813',
        '41___'      => '0.10403487572',
        '42___'      => '0.70439293352',
        '44___'      => '0.11773056034',
        '45___'      => '0.82274682986',
        '49___'      => '0.82320766748',
        '50___'      => '0.82323436796',
        '51___'      => '0.17643940743',
        '52___'      => '0.99975303798',
        '58___'      => '1',
        '59___'      => '1',
        'Genus:sp1'  => '0.03180069153',
        'Genus:sp10' => '0.01769515153',
        'Genus:sp11' => '0.01253300468',
        'Genus:sp12' => '0.02726360219',
        'Genus:sp15' => '0.04876106034',
        'Genus:sp20' => '0.14037274947',
        'Genus:sp23' => '0.01098569344',
        'Genus:sp24' => '0.03158386863',
        'Genus:sp25' => '0.05263978105',
        'Genus:sp26' => '0.21055912421',
        'Genus:sp27' => '0.08422364968',
        'Genus:sp29' => '0.03150970653',
        'Genus:sp30' => '0.01307820647',
        'Genus:sp5'  => '0.03790064236'
    },
    PE_CLADE_CONTR_P => {
        '30___'      => '0.00313809376',
        '31___'      => '0.00633158803',
        '32___'      => '0.00977497033',
        '33___'      => '0.01125900229',
        '34___'      => '0.03339063025',
        '35___'      => '0.04476719049',
        '36___'      => '0.00187186617',
        '37___'      => '0.00299487648',
        '38___'      => '0.00539492088',
        '39___'      => '0.00768336494',
        '41___'      => '0.00777520247',
        '42___'      => '0.05264386234',
        '44___'      => '0.00879877',
        '45___'      => '0.06148921829',
        '49___'      => '0.06152365968',
        '50___'      => '0.06152565518',
        '51___'      => '0.01318646374',
        '52___'      => '0.07471804273',
        '58___'      => '0.07473649981',
        '59___'      => '0.07473649981',
        'Genus:sp1'  => '0.00237667238',
        'Genus:sp10' => '0.00132247369',
        'Genus:sp11' => '0.0009366729',
        'Genus:sp12' => '0.0020375862',
        'Genus:sp15' => '0.00364423098',
        'Genus:sp20' => '0.01049096796',
        'Genus:sp23' => '0.00082103228',
        'Genus:sp24' => '0.00236046779',
        'Genus:sp25' => '0.00393411299',
        'Genus:sp26' => '0.01573645195',
        'Genus:sp27' => '0.00629458078',
        'Genus:sp29' => '0.00235492518',
        'Genus:sp30' => '0.00097741938',
        'Genus:sp5'  => '0.00283256135'
    },
    PE_CLADE_LOSS_ANC => {
        '30___'      => '0',
        '31___'      => '0',
        '32___'      => '0',
        '33___'      => '0',
        '34___'      => '0',
        '35___'      => '0',
        '36___'      => '0',
        '37___'      => '0',
        '38___'      => '0',
        '39___'      => '0.00194532468189068',
        '41___'      => '0',
        '42___'      => '0',
        '44___'      => '0',
        '45___'      => '0.000771815042377',
        '49___'      => '4.22691626564831e-005',
        '50___'      => '0',
        '51___'      => '0',
        '52___'      => '0.000390962271515916',
        '58___'      => '0',
        '59___'      => '0',
        'Genus:sp1'  => '0',
        'Genus:sp10' => '0',
        'Genus:sp11' => '0',
        'Genus:sp12' => '0',
        'Genus:sp15' => '0',
        'Genus:sp20' => '0',
        'Genus:sp23' => '0',
        'Genus:sp24' => '0',
        'Genus:sp25' => '0',
        'Genus:sp26' => '0',
        'Genus:sp27' => '0.0530443421087678',
        'Genus:sp29' => '0',
        'Genus:sp30' => '0',
        'Genus:sp5'  => '0.0064718614718615'
    },
    PE_CLADE_LOSS_ANC_P => {
        '30___'      => '0',
        '31___'      => '0',
        '32___'      => '0',
        '33___'      => '0',
        '34___'      => '0',
        '35___'      => '0',
        '36___'      => '0',
        '37___'      => '0',
        '38___'      => '0',
        '39___'      => '0.0118115927520251',
        '41___'      => '0',
        '42___'      => '0',
        '44___'      => '0',
        '45___'      => '0.000592222721866968',
        '49___'      => '3.24336235821024e-005',
        '50___'      => '0',
        '51___'      => '0',
        '52___'      => '0.000246962020469287',
        '58___'      => '0',
        '59___'      => '0',
        'Genus:sp1'  => '0',
        'Genus:sp10' => '0',
        'Genus:sp11' => '0',
        'Genus:sp12' => '0',
        'Genus:sp15' => '0',
        'Genus:sp20' => '0',
        'Genus:sp23' => '0',
        'Genus:sp24' => '0',
        'Genus:sp25' => '0',
        'Genus:sp26' => '0',
        'Genus:sp27' => '0.284606737276569',
        'Genus:sp29' => '0',
        'Genus:sp30' => '0',
        'Genus:sp5'  => '0.0973624226636279'
    },
    PE_CLADE_LOSS_CONTR => {
        '30___'      => '0.04198877081',
        '31___'      => '0.08471881937',
        '32___'      => '0.1307924555',
        '33___'      => '0.15064931213',
        '34___'      => '0.44677808478',
        '35___'      => '0.59900036271',
        '36___'      => '0.02504621139',
        '37___'      => '0.04007247444',
        '38___'      => '0.07218589162',
        '39___'      => '0.10403487572',
        '41___'      => '0.10403487572',
        '42___'      => '0.70439293352',
        '44___'      => '0.11773056034',
        '45___'      => '0.82323436796',
        '49___'      => '0.82323436796',
        '50___'      => '0.82323436796',
        '51___'      => '0.17643940743',
        '52___'      => '1',
        '58___'      => '1',
        '59___'      => '1',
        'Genus:sp1'  => '0.03180069153',
        'Genus:sp10' => '0.01769515153',
        'Genus:sp11' => '0.01253300468',
        'Genus:sp12' => '0.02726360219',
        'Genus:sp15' => '0.04876106034',
        'Genus:sp20' => '0.14037274947',
        'Genus:sp23' => '0.01098569344',
        'Genus:sp24' => '0.03158386863',
        'Genus:sp25' => '0.05263978105',
        'Genus:sp26' => '0.21055912421',
        'Genus:sp27' => '0.11773056034',
        'Genus:sp29' => '0.03150970653',
        'Genus:sp30' => '0.01307820647',
        'Genus:sp5'  => '0.04198877081'
    },
    PE_CLADE_LOSS_CONTR_P => {
        '30___'      => '0.00313809376',
        '31___'      => '0.00633158803',
        '32___'      => '0.00977497033',
        '33___'      => '0.01125900229',
        '34___'      => '0.03339063025',
        '35___'      => '0.04476719049',
        '36___'      => '0.00187186617',
        '37___'      => '0.00299487648',
        '38___'      => '0.00539492088',
        '39___'      => '0.00777520247',
        '41___'      => '0.00777520247',
        '42___'      => '0.05264386234',
        '44___'      => '0.00879877',
        '45___'      => '0.06152565518',
        '49___'      => '0.06152565518',
        '50___'      => '0.06152565518',
        '51___'      => '0.01318646374',
        '52___'      => '0.07473649981',
        '58___'      => '0.07473649981',
        '59___'      => '0.07473649981',
        'Genus:sp1'  => '0.00237667238',
        'Genus:sp10' => '0.00132247369',
        'Genus:sp11' => '0.0009366729',
        'Genus:sp12' => '0.0020375862',
        'Genus:sp15' => '0.00364423098',
        'Genus:sp20' => '0.01049096796',
        'Genus:sp23' => '0.00082103228',
        'Genus:sp24' => '0.00236046779',
        'Genus:sp25' => '0.00393411299',
        'Genus:sp26' => '0.01573645195',
        'Genus:sp27' => '0.00879877',
        'Genus:sp29' => '0.00235492518',
        'Genus:sp30' => '0.00097741938',
        'Genus:sp5'  => '0.00313809376'
    },
    PE_CLADE_LOSS_SCORE => {
        '30___'      => '0.0664718614718615',
        '31___'      => '0.134117229833477',
        '32___'      => '0.207055786962564',
        '33___'      => '0.23849091112274',
        '34___'      => '0.707288410415179',
        '35___'      => '0.948269462639852',
        '36___'      => '0.0396503222590179',
        '37___'      => '0.0634381983263044',
        '38___'      => '0.114276519543702',
        '39___'      => '0.164696220292319',
        '41___'      => '0.164696220292319',
        '42___'      => '1.11511503187332',
        '44___'      => '0.186377675442101',
        '45___'      => '1.30325131724746',
        '49___'      => '1.30325131724746',
        '50___'      => '1.30325131724746',
        '51___'      => '0.279318866046807',
        '52___'      => '1.58308662511342',
        '58___'      => '1.58308662511342',
        '59___'      => '1.58308662511342',
        'Genus:sp1'  => '0.0503432494279177',
        'Genus:sp10' => '0.0280129577145201',
        'Genus:sp11' => '0.01984083208573',
        'Genus:sp12' => '0.043160643984866',
        'Genus:sp15' => '0.0771929824561404',
        'Genus:sp20' => '0.222222222222222',
        'Genus:sp23' => '0.0173913043478261',
        'Genus:sp24' => '0.05',
        'Genus:sp25' => '0.0833333333333333',
        'Genus:sp26' => '0.333333333333333',
        'Genus:sp27' => '0.186377675442101',
        'Genus:sp29' => '0.0498825949645622',
        'Genus:sp30' => '0.020703933747412',
        'Genus:sp5'  => '0.0664718614718615'
    },
    PE_CLADE_SCORE => {
        '30___'      => '0.0664718614718615',
        '31___'      => '0.134117229833477',
        '32___'      => '0.207055786962564',
        '33___'      => '0.23849091112274',
        '34___'      => '0.707288410415179',
        '35___'      => '0.948269462639852',
        '36___'      => '0.0396503222590179',
        '37___'      => '0.0634381983263044',
        '38___'      => '0.114276519543702',
        '39___'      => '0.162750895610429',
        '41___'      => '0.164696220292319',
        '42___'      => '1.11511503187332',
        '44___'      => '0.186377675442101',
        '45___'      => '1.30247950220508',
        '49___'      => '1.3032090480848',
        '50___'      => '1.30325131724746',
        '51___'      => '0.279318866046807',
        '52___'      => '1.58269566284191',
        '58___'      => '1.58308662511342',
        '59___'      => '1.58308662511342',
        'Genus:sp1'  => '0.0503432494279177',
        'Genus:sp10' => '0.0280129577145201',
        'Genus:sp11' => '0.01984083208573',
        'Genus:sp12' => '0.043160643984866',
        'Genus:sp15' => '0.0771929824561404',
        'Genus:sp20' => '0.222222222222222',
        'Genus:sp23' => '0.0173913043478261',
        'Genus:sp24' => '0.05',
        'Genus:sp25' => '0.0833333333333333',
        'Genus:sp26' => '0.333333333333333',
        'Genus:sp27' => '0.133333333333333',
        'Genus:sp29' => '0.0498825949645622',
        'Genus:sp30' => '0.020703933747412',
        'Genus:sp5'  => '0.06'
    },
    PE_CWE             => '0.165652822722154',
    PE_LOCAL_RANGELIST => {
        '30___'      => 1,
        '31___'      => 2,
        '32___'      => 2,
        '33___'      => 3,
        '34___'      => 4,
        '35___'      => 4,
        '36___'      => 1,
        '37___'      => 2,
        '38___'      => 2,
        '39___'      => 2,
        '41___'      => 2,
        '42___'      => 4,
        '44___'      => 1,
        '45___'      => 4,
        '49___'      => 4,
        '50___'      => 4,
        '51___'      => 1,
        '52___'      => 5,
        '58___'      => 5,
        '59___'      => 5,
        'Genus:sp1'  => 2,
        'Genus:sp10' => 1,
        'Genus:sp11' => 2,
        'Genus:sp12' => 2,
        'Genus:sp15' => 2,
        'Genus:sp20' => 4,
        'Genus:sp23' => 1,
        'Genus:sp24' => 1,
        'Genus:sp25' => 1,
        'Genus:sp26' => 2,
        'Genus:sp27' => 1,
        'Genus:sp29' => 1,
        'Genus:sp30' => 1,
        'Genus:sp5'  => 1
    },
    PE_RANGELIST => {
        '30___'      => 12,
        '31___'      => 30,
        '32___'      => 33,
        '33___'      => 50,
        '34___'      => 9,
        '35___'      => 53,
        '36___'      => 33,
        '37___'      => 57,
        '38___'      => 57,
        '39___'      => 65,
        '41___'      => 78,
        '42___'      => 107,
        '44___'      => 5,
        '45___'      => 107,
        '49___'      => 112,
        '50___'      => 115,
        '51___'      => 5,
        '52___'      => 116,
        '58___'      => 127,
        '59___'      => 127,
        'Genus:sp1'  => 23,
        'Genus:sp10' => 28,
        'Genus:sp11' => 49,
        'Genus:sp12' => 29,
        'Genus:sp15' => 15,
        'Genus:sp20' => 9,
        'Genus:sp23' => 25,
        'Genus:sp24' => 5,
        'Genus:sp25' => 3,
        'Genus:sp26' => 3,
        'Genus:sp27' => 5,
        'Genus:sp29' => 12,
        'Genus:sp30' => 21,
        'Genus:sp5'  => 10
    },
    PE_WE          => '1.58308662511342',
    PE_WE_P        => '0.0747364998100494',
    PE_WE_SINGLE   => '1.02058686362188',
    PE_WE_SINGLE_P => '0.0481812484100488',
    PE_WTLIST      => {
        '30___'      => '0.0064718614718615',
        '31___'      => '0.006580997949419',
        '32___'      => '0.00646669565722576',
        '33___'      => '0.0034221664456554',
        '34___'      => '0.151732854859624',
        '35___'      => '0.00249014110193283',
        '36___'      => '0.00155508416377982',
        '37___'      => '0.00394704398155649',
        '38___'      => '0.000955726252835477',
        '39___'      => '0.00531373208186055',
        '41___'      => '0.00194532468189072',
        '42___'      => '0.00214934894114927',
        '44___'      => '0.0530443421087678',
        '45___'      => '0.000986794889656748',
        '49___'      => '0.000729545879720464',
        '50___'      => '4.22691626564195e-005',
        '51___'      => '0.145985532713474',
        '52___'      => '0.000125479547644827',
        '58___'      => '0.000390962271515824',
        '59___'      => 0,
        'Genus:sp1'  => '0.0503432494279177',
        'Genus:sp10' => '0.0280129577145201',
        'Genus:sp11' => '0.01984083208573',
        'Genus:sp12' => '0.043160643984866',
        'Genus:sp15' => '0.0771929824561404',
        'Genus:sp20' => '0.222222222222222',
        'Genus:sp23' => '0.0173913043478261',
        'Genus:sp24' => '0.05',
        'Genus:sp25' => '0.0833333333333333',
        'Genus:sp26' => '0.333333333333333',
        'Genus:sp27' => '0.133333333333333',
        'Genus:sp29' => '0.0498825949645622',
        'Genus:sp30' => '0.020703933747412',
        'Genus:sp5'  => '0.06'
    },
    PHYLO_ABUNDANCE      => '82.3998461538462',
    PHYLO_ABUNDANCE_BRANCH_HASH => {
        '30___'      => '0.077662337662338',
        '31___'      => '1.87558441558442',
        '32___'      => '2.1340095668845',
        '33___'      => '2.05329986739324',
        '34___'      => '6.14518062181475',
        '35___'      => '1.78169595843294',
        '36___'      => '0.153953332214202',
        '37___'      => '1.34988904169232',
        '38___'      => '0.463049369498789',
        '39___'      => '4.3174073165117',
        '41___'      => '1.89669156484345',
        '42___'      => '4.5421116498837',
        '44___'      => '0.265221710543839',
        '45___'      => '2.11174106386544',
        '49___'      => '1.63418277057384',
        '50___'      => '0.0972190741097648',
        '51___'      => '2.18978299070211',
        '52___'      => '0.241623416944879',
        '58___'      => '0.824226660809659',
        '59___'      => 0,
        'Genus:sp1'  => '4.63157894736842',
        'Genus:sp10' => '12.549805056105',
        'Genus:sp11' => '4.37490347490347',
        'Genus:sp12' => '5.00663470224446',
        'Genus:sp15' => '6.36842105263158',
        'Genus:sp20' => 6,
        'Genus:sp23' => '0.869565217391304',
        'Genus:sp24' => '0.5',
        'Genus:sp25' => '0.25',
        'Genus:sp26' => 3,
        'Genus:sp27' => '0.666666666666667',
        'Genus:sp29' => '2.99295569787373',
        'Genus:sp30' => '0.434782608695652',
        'Genus:sp5'  => '0.6'
    },
    PHYLO_AED_LIST => {
        'Genus:sp1'  => '0.0107499482131097',
        'Genus:sp10' => '0.00545225560494617',
        'Genus:sp11' => '0.00207155382856306',
        'Genus:sp12' => '0.00450677503945796',
        'Genus:sp15' => '0.0124251431448835',
        'Genus:sp20' => '0.0252759553987262',
        'Genus:sp23' => '0.00327355381530656',
        'Genus:sp24' => '0.0336871540660519',
        'Genus:sp25' => '0.0505953666264384',
        'Genus:sp26' => '0.0805754945692332',
        'Genus:sp27' => '0.0230520172760593',
        'Genus:sp29' => '0.0116977777714026',
        'Genus:sp30' => '0.00499599356630484',
        'Genus:sp5'  => '0.0176398692951442'
    },
    PHYLO_AED_T        => '1.38006841833426',
    PHYLO_AED_T_WTLIST => {
        'Genus:sp1'  => '0.0859995857048772',
        'Genus:sp10' => '0.0872360896791387',
        'Genus:sp11' => '0.0186439844570675',
        'Genus:sp12' => '0.0360542003156637',
        'Genus:sp15' => '0.136676574593719',
        'Genus:sp20' => '0.303311464784715',
        'Genus:sp23' => '0.00654710763061312',
        'Genus:sp24' => '0.0673743081321039',
        'Genus:sp25' => '0.0505953666264384',
        'Genus:sp26' => '0.483452967415399',
        'Genus:sp27' => '0.0230520172760593',
        'Genus:sp29' => '0.0584888888570131',
        'Genus:sp30' => '0.00499599356630484',
        'Genus:sp5'  => '0.0176398692951442'
    },
    PHYLO_AED_T_WTLIST_P => {
        'Genus:sp1'  => '0.0623154508590804',
        'Genus:sp10' => '0.063211423810736',
        'Genus:sp11' => '0.0135094638855448',
        'Genus:sp12' => '0.0261249368775362',
        'Genus:sp15' => '0.0990360860215086',
        'Genus:sp20' => '0.219780020146256',
        'Genus:sp23' => '0.00474404568906481',
        'Genus:sp24' => '0.0488195420147536',
        'Genus:sp25' => '0.0366614915277222',
        'Genus:sp26' => '0.350310869369018',
        'Genus:sp27' => '0.0167035322088474',
        'Genus:sp29' => '0.0423811516008817',
        'Genus:sp30' => '0.00362010571355224',
        'Genus:sp5'  => '0.0127818802754979'
    },
    PHYLO_ED_LIST => {
        'Genus:sp1'  => '0.678240495563069',
        'Genus:sp10' => '0.80762333894188',
        'Genus:sp11' => '0.582924169600393',
        'Genus:sp12' => '0.678346653904325',
        'Genus:sp15' => '0.678240495563069',
        'Genus:sp20' => '0.682552763166875',
        'Genus:sp23' => '0.557265280898026',
        'Genus:sp24' => '0.615416143402958',
        'Genus:sp25' => '0.615416143402958',
        'Genus:sp26' => '0.682552763166875',
        'Genus:sp27' => '0.758106931866058',
        'Genus:sp29' => '0.657918005249967',
        'Genus:sp30' => '0.557265280898026',
        'Genus:sp5'  => '0.688766811352542'
    },
    PHYLO_ES_LIST => {
        'Genus:sp1'  => '0.66656052363853',
        'Genus:sp10' => '0.830685020049678',
        'Genus:sp11' => '0.577872967365978',
        'Genus:sp12' => '0.740699957688393',
        'Genus:sp15' => '0.66656052363853',
        'Genus:sp20' => '0.688503612046397',
        'Genus:sp23' => '0.506327788030815',
        'Genus:sp24' => '0.616932918372087',
        'Genus:sp25' => '0.616932918372087',
        'Genus:sp26' => '0.688503612046397',
        'Genus:sp27' => '0.808752211567386',
        'Genus:sp29' => '0.66964554863157',
        'Genus:sp30' => '0.506327788030815',
        'Genus:sp5'  => '0.677086839428004'
    },
    PHYLO_LABELS_NOT_ON_TREE   => {},
    PHYLO_LABELS_NOT_ON_TREE_N => 0,
    PHYLO_LABELS_NOT_ON_TREE_P => 0,
    PHYLO_LABELS_ON_TREE       => {
        'Genus:sp1'  => 1,
        'Genus:sp10' => 1,
        'Genus:sp11' => 1,
        'Genus:sp12' => 1,
        'Genus:sp15' => 1,
        'Genus:sp20' => 1,
        'Genus:sp23' => 1,
        'Genus:sp24' => 1,
        'Genus:sp25' => 1,
        'Genus:sp26' => 1,
        'Genus:sp27' => 1,
        'Genus:sp29' => 1,
        'Genus:sp30' => 1,
        'Genus:sp5'  => 1
    },
    PHYLO_LABELS_ON_TREE_COUNT => 14,
    PHYLO_RARITY_CWR           => '0.144409172195734',
}


@@ RESULTS_1_NBR_LISTS
{   LAST_SHARED_ANCESTOR_DEPTH        => 8,
    LAST_SHARED_ANCESTOR_DIST_TO_ROOT => '0.492769230769231',
    LAST_SHARED_ANCESTOR_DIST_TO_TIP  => '0.5',
    LAST_SHARED_ANCESTOR_LENGTH       => '0.341398923434153',
    LAST_SHARED_ANCESTOR_POS_REL      => '0.496358282969162',
    PD             => '1.49276923076923',
    PD_CLADE_CONTR => {
        '34___'      => '0.89859765045',
        '35___'      => '0.92070044365',
        '42___'      => '0.9592161653',
        '45___'      => '0.97689924903',
        '49___'      => '0.99058340342',
        '50___'      => '0.99139748667',
        '52___'      => '0.99334763774',
        '58___'      => '1',
        '59___'      => '1',
        'Genus:sp20' => '0.33494795424',
        'Genus:sp26' => '0.33494795424'
    },
    PD_CLADE_CONTR_P => {
        '34___'      => '0.0633265791',
        '35___'      => '0.06488422203',
        '42___'      => '0.06759852792',
        '45___'      => '0.06884470211',
        '49___'      => '0.06980906106',
        '50___'      => '0.06986643169',
        '52___'      => '0.07000386405',
        '58___'      => '0.0704726738',
        '59___'      => '0.0704726738',
        'Genus:sp20' => '0.02360467792',
        'Genus:sp26' => '0.02360467792'
    },
    PD_CLADE_LOSS_ANC => {
        '34___'      => '0.151370307335078',
        '35___'      => '0.118375937734468',
        '42___'      => '0.0608808535587249',
        '45___'      => '0.0344840902604069',
        '49___'      => '0.014056805628234',
        '50___'      => '0.0128415672018618',
        '52___'      => '0.00993044169650181',
        '58___'      => '0',
        '59___'      => '0',
        'Genus:sp20' => '0',
        'Genus:sp26' => '0'
    },
    PD_CLADE_LOSS_ANC_P => {
        '34___'      => '0.101402349549418',
        '35___'      => '0.0792995563510296',
        '42___'      => '0.0407838347038763',
        '45___'      => '0.0231007509731676',
        '49___'      => '0.00941659657667946',
        '50___'      => '0.00860251332702275',
        '52___'      => '0.00665236226190475',
        '58___'      => '0',
        '59___'      => '0',
        'Genus:sp20' => '0',
        'Genus:sp26' => '0'
    },
    PD_CLADE_LOSS_CONTR => {
        '34___'      => '1',
        '35___'      => '1',
        '42___'      => '1',
        '45___'      => '1',
        '49___'      => '1',
        '50___'      => '1',
        '52___'      => '1',
        '58___'      => '1',
        '59___'      => '1',
        'Genus:sp20' => '0.33494795424',
        'Genus:sp26' => '0.33494795424'
    },
    PD_CLADE_LOSS_CONTR_P => {
        '34___'      => '0.0704726738',
        '35___'      => '0.0704726738',
        '42___'      => '0.0704726738',
        '45___'      => '0.0704726738',
        '49___'      => '0.0704726738',
        '50___'      => '0.0704726738',
        '52___'      => '0.0704726738',
        '58___'      => '0.0704726738',
        '59___'      => '0.0704726738',
        'Genus:sp20' => '0.02360467792',
        'Genus:sp26' => '0.02360467792'
    },
    PD_CLADE_LOSS_SCORE => {
        '34___'      => '1.49276923076923',
        '35___'      => '1.49276923076923',
        '42___'      => '1.49276923076923',
        '45___'      => '1.49276923076923',
        '49___'      => '1.49276923076923',
        '50___'      => '1.49276923076923',
        '52___'      => '1.49276923076923',
        '58___'      => '1.49276923076923',
        '59___'      => '1.49276923076923',
        'Genus:sp20' => '0.5',
        'Genus:sp26' => '0.5'
    },
    PD_CLADE_SCORE => {
        '34___'      => '1.34139892343415',
        '35___'      => '1.37439329303476',
        '42___'      => '1.43188837721051',
        '45___'      => '1.45828514050882',
        '49___'      => '1.478712425141',
        '50___'      => '1.47992766356737',
        '52___'      => '1.48283878907273',
        '58___'      => '1.49276923076923',
        '59___'      => '1.49276923076923',
        'Genus:sp20' => '0.5',
        'Genus:sp26' => '0.5'
    },
    PD_ENDEMISM           => undef,
    PD_ENDEMISM_P         => undef,
    PD_ENDEMISM_WTS       => {},
    PD_INCLUDED_NODE_LIST => {
        '34___'      => '0.341398923434153',
        '35___'      => '0.03299436960061',
        '42___'      => '0.057495084175743',
        '45___'      => '0.026396763298318',
        '49___'      => '0.020427284632173',
        '50___'      => '0.00121523842637206',
        '52___'      => '0.00291112550535999',
        '58___'      => '0.00993044169650192',
        '59___'      => 0,
        'Genus:sp20' => '0.5',
        'Genus:sp26' => '0.5'
    },
    PD_INCLUDED_TERMINAL_NODE_COUNT => 2,
    PD_INCLUDED_TERMINAL_NODE_LIST  => {
        'Genus:sp20' => '0.5',
        'Genus:sp26' => '0.5'
    },
    PD_LOCAL            => '1',
    PD_LOCAL_P          => '0.0472093558397',
    PD_P                => '0.0704726738019399',
    PD_P_per_taxon      => '0.0352363369009699',
    PD_per_taxon        => '0.746384615384615',
    PEC_CWE             => '0.175417769804783',
    PEC_CWE_PD          => '1.49276923076923',
    PEC_LOCAL_RANGELIST => {
        '34___'      => 1,
        '35___'      => 1,
        '42___'      => 1,
        '45___'      => 1,
        '49___'      => 1,
        '50___'      => 1,
        '52___'      => 1,
        '58___'      => 1,
        '59___'      => 1,
        'Genus:sp20' => 1,
        'Genus:sp26' => 1
    },
    PEC_RANGELIST => {
        '34___'      => 9,
        '35___'      => 53,
        '42___'      => 107,
        '45___'      => 107,
        '49___'      => 112,
        '50___'      => 115,
        '52___'      => 116,
        '58___'      => 127,
        '59___'      => 127,
        'Genus:sp20' => 9,
        'Genus:sp26' => 3
    },
    PEC_WE     => '0.261858249294739',
    PEC_WE_P   => '0.0123621592705162',
    PEC_WTLIST => {
        '34___'      => '0.0379332137149059',
        '35___'      => '0.000622535275483208',
        '42___'      => '0.000537337235287318',
        '45___'      => '0.000246698722414187',
        '49___'      => '0.000182386469930116',
        '50___'      => '1.05672906641049e-005',
        '52___'      => '2.50959095289654e-005',
        '58___'      => '7.81924543031647e-005',
        '59___'      => 0,
        'Genus:sp20' => '0.0555555555555556',
        'Genus:sp26' => '0.166666666666667'
    },
    PE_CLADE_CONTR => {
        '34___'      => '0.99349719414',
        '35___'      => '0.99587456922',
        '42___'      => '0.9979265849',
        '45___'      => '0.99886869279',
        '49___'      => '0.99956520119',
        '50___'      => '0.9996055562',
        '52___'      => '0.99970139396',
        '58___'      => '1',
        '59___'      => '1',
        'Genus:sp20' => '0.21215889018',
        'Genus:sp26' => '0.63647667055'
    },
    PE_CLADE_CONTR_P => {
        '34___'      => '0.01228177055',
        '35___'      => '0.01231116004',
        '42___'      => '0.01233652738',
        '45___'      => '0.01234817387',
        '49___'      => '0.01235678422',
        '50___'      => '0.01235728309',
        '52___'      => '0.01235846786',
        '58___'      => '0.01236215927',
        '59___'      => '0.01236215927',
        'Genus:sp20' => '0.00262274199',
        'Genus:sp26' => '0.00786822597'
    },
    PE_CLADE_LOSS_ANC => {
        '34___'      => '0.00170281335761113',
        '35___'      => '0.00108027808212791',
        '42___'      => '0.000542940846840589',
        '45___'      => '0.000296242124426416',
        '49___'      => '0.000113855654496287',
        '50___'      => '0.000103288363832166',
        '52___'      => '7.81924543031831e-005',
        '58___'      => '0',
        '59___'      => '0',
        'Genus:sp20' => '0',
        'Genus:sp26' => '0'
    },
    PE_CLADE_LOSS_ANC_P => {
        '34___'      => '0.00650280585850286',
        '35___'      => '0.00412543078187306',
        '42___'      => '0.00207341509500994',
        '45___'      => '0.0011313072061861',
        '49___'      => '0.000434798807381219',
        '50___'      => '0.000394443803509538',
        '52___'      => '0.000298606037861241',
        '58___'      => '0',
        '59___'      => '0',
        'Genus:sp20' => '0',
        'Genus:sp26' => '0'
    },
    PE_CLADE_LOSS_CONTR => {
        '34___'      => '1',
        '35___'      => '1',
        '42___'      => '1',
        '45___'      => '1',
        '49___'      => '1',
        '50___'      => '1',
        '52___'      => '1',
        '58___'      => '1',
        '59___'      => '1',
        'Genus:sp20' => '0.21215889018',
        'Genus:sp26' => '0.63647667055'
    },
    PE_CLADE_LOSS_CONTR_P => {
        '34___'      => '0.01236215927',
        '35___'      => '0.01236215927',
        '42___'      => '0.01236215927',
        '45___'      => '0.01236215927',
        '49___'      => '0.01236215927',
        '50___'      => '0.01236215927',
        '52___'      => '0.01236215927',
        '58___'      => '0.01236215927',
        '59___'      => '0.01236215927',
        'Genus:sp20' => '0.00262274199',
        'Genus:sp26' => '0.00786822597'
    },
    PE_CLADE_LOSS_SCORE => {
        '34___'      => '0.261858249294739',
        '35___'      => '0.261858249294739',
        '42___'      => '0.261858249294739',
        '45___'      => '0.261858249294739',
        '49___'      => '0.261858249294739',
        '50___'      => '0.261858249294739',
        '52___'      => '0.261858249294739',
        '58___'      => '0.261858249294739',
        '59___'      => '0.261858249294739',
        'Genus:sp20' => '0.0555555555555556',
        'Genus:sp26' => '0.166666666666667'
    },
    PE_CLADE_SCORE => {
        '34___'      => '0.260155435937128',
        '35___'      => '0.260777971212611',
        '42___'      => '0.261315308447899',
        '45___'      => '0.261562007170313',
        '49___'      => '0.261744393640243',
        '50___'      => '0.261754960930907',
        '52___'      => '0.261780056840436',
        '58___'      => '0.261858249294739',
        '59___'      => '0.261858249294739',
        'Genus:sp20' => '0.0555555555555556',
        'Genus:sp26' => '0.166666666666667'
    },
    PE_CWE             => '0.175417769804783',
    PE_LOCAL_RANGELIST => {
        '34___'      => 1,
        '35___'      => 1,
        '42___'      => 1,
        '45___'      => 1,
        '49___'      => 1,
        '50___'      => 1,
        '52___'      => 1,
        '58___'      => 1,
        '59___'      => 1,
        'Genus:sp20' => 1,
        'Genus:sp26' => 1
    },
    PE_RANGELIST => {
        '34___'      => 9,
        '35___'      => 53,
        '42___'      => 107,
        '45___'      => 107,
        '49___'      => 112,
        '50___'      => 115,
        '52___'      => 116,
        '58___'      => 127,
        '59___'      => 127,
        'Genus:sp20' => 9,
        'Genus:sp26' => 3
    },
    PE_WE          => '0.261858249294739',
    PE_WE_P        => '0.0123621592705162',
    PE_WE_SINGLE   => '0.261858249294739',
    PE_WE_SINGLE_P => '0.0123621592705162',
    PE_WTLIST      => {
        '34___'      => '0.0379332137149059',
        '35___'      => '0.000622535275483208',
        '42___'      => '0.000537337235287318',
        '45___'      => '0.000246698722414187',
        '49___'      => '0.000182386469930116',
        '50___'      => '1.05672906641049e-005',
        '52___'      => '2.50959095289654e-005',
        '58___'      => '7.81924543031647e-005',
        '59___'      => 0,
        'Genus:sp20' => '0.0555555555555556',
        'Genus:sp26' => '0.166666666666667'
    },
    PHYLO_ABUNDANCE      => '5.95661538461539',
    PHYLO_ABUNDANCE_BRANCH_HASH => {
        '34___'      => '2.04839354060492',
        '35___'      => '0.19796621760366',
        '42___'      => '0.344970505054458',
        '45___'      => '0.158380579789908',
        '49___'      => '0.122563707793038',
        '50___'      => '0.00729143055823236',
        '52___'      => '0.0174667530321599',
        '58___'      => '0.0595826501790115',
        '59___'      => 0,
        'Genus:sp20' => 2,
        'Genus:sp26' => 1
    },
    PHYLO_AED_LIST => {
        'Genus:sp20' => '0.0252759553987262',
        'Genus:sp26' => '0.0805754945692332'
    },
    PHYLO_AED_T        => '0.262254810733371',
    PHYLO_AED_T_WTLIST => {
        'Genus:sp20' => '0.101103821594905',
        'Genus:sp26' => '0.161150989138466'
    },
    PHYLO_AED_T_WTLIST_P => {
        'Genus:sp20' => '0.385517509906406',
        'Genus:sp26' => '0.614482490093594'
    },
    PHYLO_ED_LIST => {
        'Genus:sp20' => '0.682552763166875',
        'Genus:sp26' => '0.682552763166875'
    },
    PHYLO_ES_LIST => {
        'Genus:sp20' => '0.688503612046397',
        'Genus:sp26' => '0.688503612046397'
    },
    PHYLO_LABELS_NOT_ON_TREE   => {},
    PHYLO_LABELS_NOT_ON_TREE_N => 0,
    PHYLO_LABELS_NOT_ON_TREE_P => 0,
    PHYLO_LABELS_ON_TREE       => {
        'Genus:sp20' => 1,
        'Genus:sp26' => 1
    },
    PHYLO_LABELS_ON_TREE_COUNT => 2,
    PHYLO_RARITY_CWR           => '0.175683424689984',
}


