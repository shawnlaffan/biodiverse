#!/usr/bin/perl -w
#
#  tests for both normal and lowmem matrices, where they overlap in methods

use 5.010;
use strict;
use warnings;
use Carp;

use FindBin qw/$Bin/;
use rlib;
use List::Util qw /first sum0/;

use Test::More;
use Test::Deep;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Test::More; # tests => 2;
use Test::Exception;

use Biodiverse::TestHelpers qw /:cluster :element_properties :tree/;
use Biodiverse::Cluster;

my $default_prng_seed = 2345;

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

    test_same_results_given_same_prng_seed();

    test_rand_calc_per_node_uses_orig_bd();
    
    test_group_properties_reassigned();

    test_randomise_tree_ref_args();

    done_testing;
    return 0;
}


#  make sure we get the same result with the same prng across two runs
sub test_same_results_given_same_prng_seed {
    
    TODO: {
        local $TODO = 'Tests not implemented yet';
        is (1, 1, 'placeholder');    
        #my $data = get_cluster_mini_data();
        #my $bd = get_basedata_object (data => $data, CELL_SIZES => [1,1]);
        #
        #check_order_is_same_given_same_prng (basedata_ref => $bd);
        #
        #my $site_bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);
        #check_order_is_same_given_same_prng (basedata_ref => $site_bd);

    };

}

#  need to implement this for randomisations
sub check_order_is_same_given_same_prng {
    my %args = @_;
    my $bd = $args{basedata_ref};
    
    my $prng_seed = $args{prng_seed} || $default_prng_seed;
    
}


sub test_rand_calc_per_node_uses_orig_bd {
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $cl = $bd->add_cluster_output (name => 't_r_c_p_n_u_o_b');
    
    $cl->run_analysis (
        spatial_calculations => [qw /calc_richness calc_element_lists_used calc_elements_used/],
    );

    my $rand_name = 'xxx';

    my $rand = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand->run_analysis (
        function   => 'rand_csr_by_group',
        iterations => 1,
        retain_outputs => 1,
        return_rand_bd_array => 1,
    );

    my $rand_bd1 = $rand_bd_array->[0];
    my @refs = $rand_bd1->get_cluster_output_refs;
    my $rand_cl = first {$_->get_param ('NAME') =~ m/rand sp_calc/} @refs;  #  bodgy way of getting at it

    my $sub_ref = sub {
        node_calcs_used_same_element_sets (
            orig_tree => $cl,
            rand_tree => $rand_cl,
        );
    };
    subtest 'Calcs per node used the same element sets' => $sub_ref;
    
    my $sub_ref2 = sub {
        node_calcs_gave_expected_results (
            cluster_output => $cl,
            rand_name      => $rand_name,
        );
    };
    subtest 'Calcs per node used the same element sets' => $sub_ref2;

    return;
}

#  iterate over all the nodes and check they have the same
#  element lists and counts, but that the richness scores are not the same    
sub node_calcs_used_same_element_sets {
    my %args = @_;
    my $orig_tree = $args{orig_tree};
    my $rand_tree = $args{rand_tree};

    my %orig_nodes = $orig_tree->get_node_hash;
    my %rand_nodes = $rand_tree->get_node_hash;

    is (scalar keys %orig_nodes, scalar keys %rand_nodes, 'same number of nodes');

    my $count_richness_same = 0;

    foreach my $name (sort keys %orig_nodes) {  #  always test in same order for repeatability
        my $o_node_ref = $orig_nodes{$name};
        my $r_node_ref = $rand_nodes{$name};

        my $o_element_list = $o_node_ref->get_list_ref (list => 'EL_LIST_SET1');
        my $r_element_list = $r_node_ref->get_list_ref (list => 'EL_LIST_SET1');
        is_deeply ($o_element_list, $r_element_list, "$name used same element lists");
        
        my $o_sp_res = $o_node_ref->get_list_ref (list => 'SPATIAL_RESULTS');
        my $r_sp_res = $r_node_ref->get_list_ref (list => 'SPATIAL_RESULTS');
        if ($o_sp_res->{RICHNESS_ALL} == $r_sp_res->{RICHNESS_ALL}) {
            $count_richness_same ++;
        }
    }

    isnt ($count_richness_same, scalar keys %orig_nodes, 'richness scores differ between orig and rand nodes');

    return;
}


#  rand results should be zero for all el_list P and C results, 1 for Q
sub node_calcs_gave_expected_results {
    my %args = @_;
    my $cl          = $args{cluster_output};
    my $list_prefix = $args{rand_name};
    
    my $list_name = $list_prefix . '>>SPATIAL_RESULTS';
    
    my %nodes = $cl->get_node_hash;
    foreach my $node_ref (sort {$a->get_name cmp $b->get_name} values %nodes) {
        my $list_ref = $node_ref->get_list_ref (list => $list_name);
        my $node_name = $node_ref->get_name;

        KEY:
        while (my ($key, $value) = each %$list_ref) {
            my $expected
              = ($key =~ /^[TQ]_EL/) ? 1
              : ($key =~ /^[CP]_EL/) ? 0
              : next KEY;
            is ($value, $expected, "$key score for $node_name is $expected")
        }
        
    }
    
}


sub test_group_properties_reassigned {

    my $rand_func   = 'rand_csr_by_group';
    my $object_name = 't_g_p_r';
    
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);
    my $gp_props = get_group_properties_site_data_object();

    eval { $bd->assign_element_properties (
        type              => 'groups',
        properties_object => $gp_props,
    ) };
    my $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, 'Group properties assigned without eval error');

    #  name is short for sub name
    my $sp = $bd->add_spatial_output (name => 't_g_p_r');

    $sp->run_analysis (
        calculations => [qw /calc_gpprop_stats/],
        spatial_conditions => ['sp_self_only()'],
    );

    my %prop_handlers = (
        no_change => 0,
        by_set    => 1,
        by_item   => 1,
    );
    
    while (my ($props_func, $negate_expected) = each %prop_handlers) {

        my $rand_name   = 'r' . $object_name . $props_func;

        my $rand = $bd->add_randomisation_output (name => $rand_name);
        my $rand_bd_array = $rand->run_analysis (
            function   => $rand_func,
            iterations => 1,
            retain_outputs        => 1,
            return_rand_bd_array  => 1,
            randomise_group_props_by => $props_func,
        );
    
        my $rand_bd = $rand_bd_array->[0];
        my @refs = $rand_bd->get_spatial_output_refs;
        my $rand_sp = first {$_->get_param ('NAME') =~ m/^$object_name/} @refs;
    
        my $sub_same = sub {
            basedata_group_props_are_same (
                object1 => $bd,
                object2 => $rand_bd,
                negate  => $negate_expected,
            );
        };

        subtest "$props_func checks" => $sub_same;
    }

    return;
}

sub test_randomise_tree_ref_args {
    my $rand_func   = 'rand_csr_by_group';
    my $object_name = 't_r_t_r_f';

    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);
    my $tree = get_tree_object_from_sample_data();
    #diag $tree;

    #  name is short for sub name
    my $sp_self_only = $bd->add_spatial_output (name => 't_r_t_r_f_self_only');
    $sp_self_only->run_analysis (
        calculations       => [qw /calc_pd/],
        spatial_conditions => ['sp_self_only()'],
        tree_ref           => $tree,
    );
    my $sp_select_all = $bd->add_spatial_output (name => 't_r_t_r_f_select_all');
    $sp_select_all->run_analysis (
        calculations       => [qw /calc_pd/],
        spatial_conditions => ['sp_select_all()'],
        tree_ref           => $tree,
    );
    
    my $rand_name = 't_r_t_r_f_rand';
    my $rand = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand->run_analysis (
        function           => 'rand_nochange',
        randomise_trees_by => 'shuffle_terminal_names',
        retain_outputs     => 1,
        return_rand_bd_array => 1,
    );

    #  sp_self_only should be different, but sp_select_all should be the same
    my @groups = sort $sp_self_only->get_element_list;
    my $list_name = $rand_name . '>>SPATIAL_RESULTS';
    my %count_same;
    foreach my $gp (@groups) {
        my $list_ref_self_only = $sp_self_only->get_list_ref (
            element => $gp,
            list    => $list_name,
        );
        my $list_ref_select_all = $sp_select_all->get_list_ref (
            element => $gp,
            list    => $list_name,
        );

        $count_same{self_only}  += $list_ref_self_only->{T_PD} // 0;
        $count_same{select_all} += $list_ref_select_all->{T_PD} // 0;
    }

    isnt ($count_same{self_only},  scalar @groups, 'local PD scores differ between orig and rand');
    is   ($count_same{select_all}, scalar @groups, 'global PD scores are same for orig and rand');

    #  and check we haven't overridden the original tree_ref
    my $rand_bd = $rand_bd_array->[0];
    my @rand_sp_refs = $rand_bd->get_spatial_output_refs;
    my @analysis_args_array;
    for my $ref (@rand_sp_refs) {
        my $analysis_args = $ref->get_param ('SP_CALC_ARGS');
        my $rand_tree_ref = $analysis_args->{tree_ref};
        #diag $rand_tree_ref . ' ' . $rand_tree_ref->get_param ('NAME');
        isnt (
            $tree,
            $rand_tree_ref,
            'Tree refs differ, orig & ' . $ref->get_param ('NAME'),
        );
        push @analysis_args_array, $analysis_args;
    }
    #diag $tree . ' ' . $tree->get_param ('NAME');

    is (
        $analysis_args_array[0]->{tree_ref},
        $analysis_args_array[1]->{tree_ref},
        'Tree refs same across randomised analyses',
    );

    #  need to check that another iteration does not re-use the same shuffled tree
    
    return;
}


sub basedata_group_props_are_same {
    my %args = @_;
    my $bd1 = $args{object1};
    my $bd2 = $args{object2};
    my $negate_check = $args{negate};

    my $gp1 = $bd1->get_groups_ref;
    my $gp2 = $bd2->get_groups_ref;

    my %groups1 = $gp1->get_element_hash;
    my %groups2 = $gp2->get_element_hash;

    is (scalar keys %groups1, scalar keys %groups2, 'basedata objects have same number of groups');

    my $check_count;

    #  should also check we get the same number of defined values
    my $defined_count1 = my $defined_count2 = 0;
    my $sum1 = my $sum2 = 0;

    foreach my $gp_name (sort keys %groups1) {
        my $list1 = $gp1->get_list_ref (element => $gp_name, list => 'PROPERTIES');
        my $list2 = $gp2->get_list_ref (element => $gp_name, list => 'PROPERTIES');

        my @tmp;
        @tmp = grep {defined $_} values %$list1;
        $defined_count1 += @tmp;
        $sum1 += sum0 @tmp;
        @tmp = grep {defined $_} values %$list2;
        $defined_count2 += @tmp;
        $sum2 += sum0 @tmp;

        if (eq_deeply ($list1, $list2)) {
            $check_count ++;
        }
    }

    my $text = 'Group property sets ';
    $text .= $negate_check ? 'differ' : 'are the same';

    if ($negate_check) {
        isnt ($check_count, scalar keys %groups1, $text);
    }
    else {
        is ($check_count, scalar keys %groups1, $text);
    }

    #  useful so long as we guarantee randomised basedata will have the same groups as the orig
    is ($defined_count1, $defined_count2, 'Same number of properties with defined values');
    is ($sum1, $sum2, 'Sum of properties is the same');

    return;
}


######################################




1;

__DATA__

