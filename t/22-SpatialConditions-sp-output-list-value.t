use strict;
use warnings;
use Carp;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;

use rlib;
use Test2::V0;

local $| = 1;

use Biodiverse::TestHelpers qw {:spatial_conditions};
use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;


exit main( @ARGV );

sub main {
    my @args  = @_;

    test_sp_get_spatial_output_list_value();
    test_sp_richness_greater_than();
    test_sp_redundancy_greater_than();
    
    done_testing();
    return 0;
}


sub test_sp_get_spatial_output_list_value {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test_sp_get_spatial_output_list_value',
        CELL_SIZES => [1,1],
    );
    my %all_gps;
    foreach my $i (1..5) {
        foreach my $j (1..5) {
            my $gp = "$i:$j";
            $bd->add_element (label => "$i", group => $gp);
            $all_gps{$gp}++;
        }
    }

    my $sp1 = $bd->add_spatial_output (name => 'get_vals_from');
    $sp1->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_self_only()'],
    );
    
    my $expected = {
        ENDW_CWE     => 1, ENDW_RICHNESS => 5,
        ENDW_SINGLE  => 1, ENDW_WE => 5,
        RECYCLED_SET => 1,
    };

    my $sp_to_test1 = $bd->add_spatial_output (name => 'test_sp_get_spatial_output_list_value');
    $sp_to_test1->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_get_spatial_output_list_value (output => "get_vals_from", list => "SPATIAL_RESULTS", index => "ENDW_WE") > 0'],
    );

    my $list_ref = $sp_to_test1->get_list_ref (element => '1:1', list => 'SPATIAL_RESULTS');
    is ($list_ref, $expected, 'got expected SPATIAL_RESULTS list');

    my $sp_to_test1a = $bd->add_spatial_output (name => 'test_sp_get_spatial_output_list_value1a');
    $sp_to_test1a->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_get_spatial_output_list_value (output => "get_vals_from", index => "ENDW_WE") > 0'],
    );

    $list_ref = $sp_to_test1a->get_list_ref (element => '1:1', list => 'SPATIAL_RESULTS');
    is ($list_ref, $expected, 'defaulted to SPATIAL_RESULTS list');
    
    $list_ref = $sp_to_test1a->get_list_ref (element => '1:1', list => 'EL_LIST_SET1');
    is ($list_ref, \%all_gps, 'got expected element list');
    
    
    #  should work but have empty results    
    my $sp_to_test2 = $bd->add_spatial_output (name => 'test_sp_get_spatial_output_list_value2');
    $sp_to_test2->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_get_spatial_output_list_value (output => "get_vals_from", list => "SPATIAL_RESULTS", index => "NONEXISTENT", no_error_if_no_index => 1)'],
    );
    $expected = {
        ENDW_CWE    => undef, ENDW_RICHNESS => 0,
        ENDW_SINGLE => undef, ENDW_WE => undef,
    };
    $list_ref = $sp_to_test2->get_list_ref (element => '1:1', list => 'SPATIAL_RESULTS');
    is ($list_ref, $expected, 'got expected SPATIAL_RESULTS list when no_error_if_no_index is true');

    my $sp_to_test3 = $bd->add_spatial_output (name => 'test_sp_get_spatial_output_list_value3');
    ok (dies {
        $sp_to_test3->run_analysis (
            calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
            spatial_conditions => ['sp_get_spatial_output_list_value (output => "get_vals_from", list => "SPATIAL_RESULTS", index => "NONEXISTENT")'],
        )},
        'error thrown when non-existent index accessed'
    ) or note $@;
    
    my $sp_to_test4 = $bd->add_spatial_output (name => 'test_sp_get_spatial_output_list_value4');
    ok (dies {
        $sp_to_test4->run_analysis (
            calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
            spatial_conditions => ['sp_get_spatial_output_list_value (output => "snerble", list => "SPATIAL_RESULTS", index => "ENDW_WE")'],
        )},
        'error thrown when non-existent output accessed'
    );

    $sp1->add_to_hash_list (
        element => '5:5',
        list    => 'extra_list',
        key1    => 1,
    );
    my $sp_to_test5 = $bd->add_spatial_output (name => 'test_sp_get_spatial_output_list_value5');
    ok (lives {
        $sp_to_test5->run_analysis (
            calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
            spatial_conditions => ['sp_get_spatial_output_list_value (output => "get_vals_from", list => "extra_list", index => "key1")'],
        )},
        'no error thrown when index in subset of elements'
    );
}


sub test_sp_richness_greater_than {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test_sp_richness_greater_than',
        CELL_SIZES => [1,1],
    );
    my %all_gps;
    my @labels = 'a' .. 'f';
    #  richness decreases to the right
    foreach my $i (1..5) {
        foreach my $j (1..2) {
            my $gp = "$i:$j";
            foreach my $label (@labels[0..$i]) {
                $bd->add_element (label => $label, group => $gp);
                $all_gps{$gp}++;
            }
        }
    }

    my $sp_to_test1 = $bd->add_spatial_output (name => 'defq');
    $sp_to_test1->run_analysis (
        calculations       => ['calc_element_lists_used'],
        spatial_conditions => ['sp_self_only()'],
        definition_query   => 'sp_richness_greater_than (threshold => 3)',
    );
    my $sp_to_test2 = $bd->add_spatial_output (name => 'sp_cond');
    $sp_to_test2->run_analysis (
        calculations       => ['calc_element_lists_used'],
        spatial_conditions => ['sp_richness_greater_than (threshold => 3)'],
    );

    #  now the tests
    my @expected;
    my $failed_defq = $sp_to_test1->get_groups_that_failed_def_query;
    @expected = qw /1:1 1:2 2:1 2:2/;
    is ([sort keys %$failed_defq], \@expected, 'got expected defq fails');

    my $passed_defq = $sp_to_test1->get_groups_that_pass_def_query;
    @expected = qw /3:1 3:2 4:1 4:2 5:1 5:2/;
    is ([sort keys %$passed_defq], \@expected, 'got expected defq passes');
    

    #  all neighbour sets should be the same    
    my $list_ref = $sp_to_test2->get_list_ref (
        element => '5:1',
        list    => 'EL_LIST_SET1',
    );
    is ([sort keys %$list_ref], \@expected, 'got expected EL_LIST_SET1 list');

    my $sp_to_test3 = $bd->add_spatial_output (name => 'sp_cond_to_fail_no_threshold');
    ok (dies {
        $sp_to_test3->run_analysis (
            calculations       => ['calc_element_lists_used'],
            spatial_conditions => ['sp_richness_greater_than ()'],
        )},
        'error thrown when no threshold arg passed'
    );
}


sub test_sp_redundancy_greater_than {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test_sp_richness_greater_than',
        CELL_SIZES => [1,1],
    );
    my %all_gps;
    my @labels = 'a' .. 'f';
    #  richness decreases to the right
    foreach my $i (1..5) {
        foreach my $j (1..2) {
            my $gp = "$i:$j";
            foreach my $label (@labels[0..$i]) {
                $bd->add_element (
                    label => $label,
                    group => $gp,
                    count => $i,
                );
                $all_gps{$gp}++;
            }
        }
    }
    
    #foreach my $gp (sort $bd->get_groups) {
    #    diag "$gp " . $bd->get_redundancy_aa($gp);
    #}

    my $sp_to_test1 = $bd->add_spatial_output (name => 'defq');
    $sp_to_test1->run_analysis (
        calculations       => ['calc_element_lists_used'],
        spatial_conditions => ['sp_self_only()'],
        definition_query   => 'sp_redundancy_greater_than (threshold => 0.5)',
    );
    my $sp_to_test2 = $bd->add_spatial_output (name => 'sp_cond');
    $sp_to_test2->run_analysis (
        calculations       => ['calc_element_lists_used'],
        spatial_conditions => ['sp_redundancy_greater_than (threshold => 0.5)'],
    );

    #  now the tests
    my @expected;
    my $failed_defq = $sp_to_test1->get_groups_that_failed_def_query;
    @expected = qw /1:1 1:2 2:1 2:2/;
    is ([sort keys %$failed_defq], \@expected, 'got expected defq fails');

    my $passed_defq = $sp_to_test1->get_groups_that_pass_def_query;
    @expected = qw /3:1 3:2 4:1 4:2 5:1 5:2/;
    is ([sort keys %$passed_defq], \@expected, 'got expected defq passes');
    

    #  all neighbour sets should be the same    
    my $list_ref = $sp_to_test2->get_list_ref (
        element => '5:1',
        list    => 'EL_LIST_SET1',
    );
    is ([sort keys %$list_ref], \@expected, 'got expected EL_LIST_SET1 list');

    my $sp_to_test3 = $bd->add_spatial_output (name => 'sp_cond_to_fail_no_threshold');
    ok (dies {
        $sp_to_test3->run_analysis (
            calculations       => ['calc_element_lists_used'],
            spatial_conditions => ['sp_redundancy_greater_than ()'],
        )},
        'error thrown when no threshold arg passed'
    );
}
