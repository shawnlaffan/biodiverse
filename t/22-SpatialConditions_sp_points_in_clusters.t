#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;

use rlib;
use Test2::V0;

local $| = 1;

use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;
use Biodiverse::TestHelpers qw {:spatial_conditions};


exit main( @ARGV );

sub main {
    my @args  = @_;

    test_point_in_cluster();
    test_points_in_same_cluster();

    done_testing();
    return 0;
}


sub test_points_in_same_cluster {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test_sp_get_spatial_output_list_value',
        CELL_SIZES => [1,1],
    );
    my %all_gps;
    foreach my $i (1..5) {
        foreach my $j (1..5) {
            my $gp = "$i:$j";
            foreach my $k (1..$i) {
                #  fully nested
                $bd->add_element (label => "$k", group => $gp);
            }
            $all_gps{$gp}++;
        }
    }

    my %expected_nbrs = (
        "1:1" => [qw /1:1 1:2 1:3 1:4 1:5/],
        "2:1" => [qw /2:1 2:2 2:3 2:4 2:5/],
        "3:1" => [qw /3:1 3:2 3:3 3:4 3:5
                      4:1 4:2 4:3 4:4 4:5
                      5:1 5:2 5:3 5:4 5:5
                     /
                 ],
    );

    my $cl1 = $bd->add_cluster_output (name => 'checker');
    $cl1->run_analysis ();

    my $sp_to_test1 = $bd->add_spatial_output (name => 'test_1');
    $sp_to_test1->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_points_in_same_cluster (output => "checker", num_clusters => 3)'],
    );    
    foreach my $el (keys %expected_nbrs) {
        my $list_ref = $sp_to_test1->get_list_ref (element => $el, list => '_NBR_SET1');
        is ([sort @$list_ref], $expected_nbrs{$el}, "sp_points_in_same_cluster correct nbrs for $el");
    }

    my $sp_to_test2 = $bd->add_spatial_output (name => 'test_2');
    $sp_to_test2->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_points_in_same_cluster (output => "checker", target_distance => 0.25)'],
    );
    foreach my $el (keys %expected_nbrs) {
        my $list_ref = $sp_to_test2->get_list_ref (element => $el, list => '_NBR_SET1');
        is ([sort @$list_ref], $expected_nbrs{$el}, "sp_points_in_same_cluster correct nbrs for $el");
    }
    
    my $sp_to_test12 = $bd->add_spatial_output (name => 'test_12');
    $sp_to_test12->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => [
            'sp_points_in_same_cluster (
              output          => "checker",
              target_distance => 0.025,     # should be overridden
              num_clusters    => 3,
            )'],
    );
    foreach my $el (keys %expected_nbrs) {
        my $list_ref = $sp_to_test12->get_list_ref (element => $el, list => '_NBR_SET1');
        is ([sort @$list_ref], $expected_nbrs{$el}, "num_clusters overrides target_distance (gp $el)");
    }

    my %expected_nbrs_for_depth;
    $expected_nbrs_for_depth{"1:1"} = $expected_nbrs{"1:1"};
    $expected_nbrs_for_depth{"2:1"} = [@{$expected_nbrs{"2:1"}}, @{$expected_nbrs{"3:1"}}];
    
    my $sp_to_test3 = $bd->add_spatial_output (name => 'test_3');
    $sp_to_test3->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => [
            'sp_points_in_same_cluster (
                output => "checker",
                target_distance => 2,
                group_by_depth  => 1,
             )'
        ],
    );
    foreach my $el (keys %expected_nbrs_for_depth) {
        my $list_ref = $sp_to_test3->get_list_ref (element => $el, list => '_NBR_SET1');
        is ([sort @$list_ref], $expected_nbrs_for_depth{$el}, "sp_points_in_same_cluster correct nbrs for $el");
    }

    my $sp_to_test_croaker= $bd->add_spatial_output (name => 'test_croaker');
    ok (dies {
        $sp_to_test_croaker->run_analysis (
          calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
          spatial_conditions => [
              'sp_points_in_same_cluster (
                  output => "checker",
                  target_distance => undef,
                  group_by_depth  => 1,
               )'
             ],
         );
       },
        'dies when target_distance and num_clusters are undef',
    );
    ok (dies {
        $sp_to_test_croaker->run_analysis (
          calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
          spatial_conditions => [
              'sp_points_in_same_cluster (
                  output => undef,
                  num_clusters => 3,
               )'
             ],
         );
       },
        'dies when output is undef',
    );


    %expected_nbrs = (
        #"1:1" => [qw /1:1 1:2 1:3 1:4 1:5/],
        "2:1" => [qw /2:1 2:2 2:3 2:4 2:5/],
        "3:1" => [qw /3:1 3:2 3:3 3:4 3:5/],
        "4:1" => [qw /4:1 4:2 4:3 4:4 4:5
                      5:1 5:2 5:3 5:4 5:5
                     /
                 ],
    );

    my $sp_to_test_from_node = $bd->add_spatial_output (name => 'test_from_node');
    $sp_to_test_from_node->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => [
            'sp_points_in_same_cluster (
              output          => "checker",
              num_clusters    => 3,
              from_node       => "22___",
            )'],
    );
    foreach my $el (keys %expected_nbrs) {
        my $list_ref = $sp_to_test_from_node->get_list_ref (element => $el, list => '_NBR_SET1');
        is ([sort @$list_ref], $expected_nbrs{$el}, "num_clusters overrides target_distance (gp $el)");
    }

    
    my $sp_to_test_from_node_dies = $bd->add_spatial_output (name => 'test_from_node_should_die');
    ok (dies {
        $sp_to_test_from_node_dies->run_analysis (
            calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
            spatial_conditions => [
                'sp_points_in_same_cluster (
                  output          => "checker",
                  num_clusters    => 3,
                  from_node       => "not in tree",
                )'],
            );
        },
        'dies when from_node is not in tree',
    );

}


sub test_point_in_cluster {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test_sp_get_spatial_output_list_value',
        CELL_SIZES => [1,1],
    );
    my %all_gps;
    foreach my $i (1..5) {
        foreach my $j (1..5) {
            my $gp = "$i:$j";
            foreach my $k (1..$i) {
                #  fully nested
                $bd->add_element (label => "$k", group => $gp);
            }
            $all_gps{$gp}++;
        }
    }

    my $cl1 = $bd->add_cluster_output (name => 'checker');
    $cl1->run_analysis ();

    my $sp_to_test1 = $bd->add_spatial_output (name => 'test_1');
    $sp_to_test1->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_point_in_cluster (output => "checker")'],
    );
    my $expected = [sort $bd->get_groups];
    foreach my $el (qw/1:1/) {
        my $list_ref = $sp_to_test1->get_list_ref (element => $el, list => '_NBR_SET1');
        is ([sort @$list_ref], $expected, "sp_points_in_same_cluster correct nbrs for $el");
    }

    my $sp_to_test2 = $bd->add_spatial_output (name => 'test_2');
    $sp_to_test2->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_point_in_cluster (output => "checker", from_node => "23___")'],
    );
    foreach my $el (qw/1:1/) {
        my $list_ref = $sp_to_test2->get_list_ref (element => $el, list => '_NBR_SET1');
        is ([sort @$list_ref], $expected, "sp_points_in_same_cluster correct nbrs for $el");
    }

    my $expected_nbrs = 
                [qw /2:1 2:2 2:3 2:4 2:5
                      3:1 3:2 3:3 3:4 3:5
                      4:1 4:2 4:3 4:4 4:5
                      5:1 5:2 5:3 5:4 5:5
                     /
                 ];
    #  a subnode - these will all be the same
    my $sp_to_test3 = $bd->add_spatial_output (name => 'test_3');
    $sp_to_test3->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_point_in_cluster (output => "checker", from_node => "22___")'],
    );
    foreach my $el ($bd->get_groups) {
        my $list_ref = $sp_to_test3->get_list_ref (element => $el, list => '_NBR_SET1');
        is ([sort @$list_ref], $expected_nbrs, "sp_points_in_cluster correct nbrs for $el");
    }

    #  now a def query
    my $sp_to_test4 = $bd->add_spatial_output (name => 'test_4_defq');
    $sp_to_test4->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_self_only()'],
        definition_query   => 
            'sp_point_in_cluster (
               output => "checker",
               from_node => "22___"
             )',
    );
    foreach my $el (@$expected_nbrs) {
        my $list_ref = $sp_to_test4->get_list_ref (element => $el, list => '_NBR_SET1');
        is ([@$list_ref], [$el], "defq sp_points_in_cluster correct nbrs for $el");
    }
    my @elts = qw /1:1 1:2 1:3 1:4 1:5/;
    @elts = ($elts[0]);
    foreach my $el (@elts) {
        my $list_ref = $sp_to_test4->get_list_ref (
            element    => $el,
            list       => '_NBR_SET1',
            autovivify => 0,
        );
        is ($list_ref, undef, "defq sp_points_in_cluster correct nbrs for $el");
    }
    

    #my $sp_to_test2 = $bd->add_spatial_output (name => 'test_2');
    #$sp_to_test2->run_analysis (
    #    calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
    #    spatial_conditions => ['sp_points_in_same_cluster (output => "checker", target_distance => 0.25)'],
    #);
    #foreach my $el (keys %expected_nbrs) {
    #    my $list_ref = $sp_to_test2->get_list_ref (element => $el, list => '_NBR_SET1');
    #    is ([sort @$list_ref], $expected_nbrs{$el}, "sp_points_in_same_cluster correct nbrs for $el");
    #}
    #
    #my $sp_to_test12 = $bd->add_spatial_output (name => 'test_12');
    #$sp_to_test12->run_analysis (
    #    calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
    #    spatial_conditions => [
    #        'sp_points_in_same_cluster (
    #          output          => "checker",
    #          target_distance => 0.025,     # should be overridden
    #          num_clusters    => 3,
    #        )'],
    #);
    #foreach my $el (keys %expected_nbrs) {
    #    my $list_ref = $sp_to_test12->get_list_ref (element => $el, list => '_NBR_SET1');
    #    is ([sort @$list_ref], $expected_nbrs{$el}, "num_clusters overrides target_distance (gp $el)");
    #}
    #
    #my %expected_nbrs_for_depth;
    #$expected_nbrs_for_depth{"1:1"} = $expected_nbrs{"1:1"};
    #$expected_nbrs_for_depth{"2:1"} = [@{$expected_nbrs{"2:1"}}, @{$expected_nbrs{"3:1"}}];
    #
    #my $sp_to_test3 = $bd->add_spatial_output (name => 'test_3');
    #$sp_to_test3->run_analysis (
    #    calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
    #    spatial_conditions => [
    #        'sp_points_in_same_cluster (
    #            output => "checker",
    #            target_distance => 2,
    #            group_by_depth  => 1,
    #         )'
    #    ],
    #);
    #foreach my $el (keys %expected_nbrs_for_depth) {
    #    my $list_ref = $sp_to_test3->get_list_ref (element => $el, list => '_NBR_SET1');
    #    is ([sort @$list_ref], $expected_nbrs_for_depth{$el}, "sp_points_in_same_cluster correct nbrs for $el");
    #}
    #
    #my $sp_to_test_croaker= $bd->add_spatial_output (name => 'test_croaker');
    #ok (dies {
    #    $sp_to_test_croaker->run_analysis (
    #      calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
    #      spatial_conditions => [
    #          'sp_points_in_same_cluster (
    #              output => "checker",
    #              target_distance => undef,
    #              group_by_depth  => 1,
    #           )'
    #         ],
    #     );
    #   },
    #    'dies when target_distance and num_clusters are undef',
    #);
    #ok (dies {
    #    $sp_to_test_croaker->run_analysis (
    #      calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
    #      spatial_conditions => [
    #          'sp_points_in_same_cluster (
    #              output => undef,
    #              num_clusters => 3,
    #           )'
    #         ],
    #     );
    #   },
    #    'dies when output is undef',
    #);
    #
    #
    #%expected_nbrs = (
    #    #"1:1" => [qw /1:1 1:2 1:3 1:4 1:5/],
    #    "2:1" => [qw /2:1 2:2 2:3 2:4 2:5/],
    #    "3:1" => [qw /3:1 3:2 3:3 3:4 3:5/],
    #    "4:1" => [qw /4:1 4:2 4:3 4:4 4:5
    #                  5:1 5:2 5:3 5:4 5:5
    #                 /
    #             ],
    #);
    #
    #my $sp_to_test_from_node = $bd->add_spatial_output (name => 'test_from_node');
    #$sp_to_test_from_node->run_analysis (
    #    calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
    #    spatial_conditions => [
    #        'sp_points_in_same_cluster (
    #          output          => "checker",
    #          num_clusters    => 3,
    #          from_node       => "22___",
    #        )'],
    #);
    #foreach my $el (keys %expected_nbrs) {
    #    my $list_ref = $sp_to_test_from_node->get_list_ref (element => $el, list => '_NBR_SET1');
    #    is ([sort @$list_ref], $expected_nbrs{$el}, "num_clusters overrides target_distance (gp $el)");
    #}
    #
    #
    #my $sp_to_test_from_node_dies = $bd->add_spatial_output (name => 'test_from_node_should_die');
    #ok (dies {
    #    $sp_to_test_from_node_dies->run_analysis (
    #        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
    #        spatial_conditions => [
    #            'sp_points_in_same_cluster (
    #              output          => "checker",
    #              num_clusters    => 3,
    #              from_node       => "not in tree",
    #            )'],
    #        );
    #    },
    #    'dies when from_node is not in tree',
    #);

}

