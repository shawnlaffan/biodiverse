#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;

use Test::Lib;
use rlib;

use Test::Most;

local $| = 1;

use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;
use Biodiverse::TestHelpers qw {:spatial_conditions};


exit main( @ARGV );

sub main {
    my @args  = @_;

    test_sp_get_spatial_output_list_value();
    
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
        ENDW_CWE    => 1, ENDW_RICHNESS => 5,
        ENDW_SINGLE => 1, ENDW_WE => 5,
    };

    my $sp_to_test1 = $bd->add_spatial_output (name => 'test_sp_get_spatial_output_list_value');
    $sp_to_test1->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_get_spatial_output_list_value (output => "get_vals_from", list => "SPATIAL_RESULTS", index => "ENDW_WE") > 0'],
    );

    my $list_ref = $sp_to_test1->get_list_ref (element => '1:1', list => 'SPATIAL_RESULTS');
    is_deeply ($list_ref, $expected, 'got expected SPATIAL_RESULTS list');

    my $sp_to_test1a = $bd->add_spatial_output (name => 'test_sp_get_spatial_output_list_value1a');
    $sp_to_test1a->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_get_spatial_output_list_value (output => "get_vals_from", index => "ENDW_WE") > 0'],
    );

    $list_ref = $sp_to_test1a->get_list_ref (element => '1:1', list => 'SPATIAL_RESULTS');
    is_deeply ($list_ref, $expected, 'defaulted to SPATIAL_RESULTS list');
    
    $list_ref = $sp_to_test1a->get_list_ref (element => '1:1', list => 'EL_LIST_SET1');
    is_deeply ($list_ref, \%all_gps, 'got expected element list');
    
    
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
    is_deeply ($list_ref, $expected, 'got expected SPATIAL_RESULTS list when no_error_if_no_index is true');

    my $sp_to_test3 = $bd->add_spatial_output (name => 'test_sp_get_spatial_output_list_value3');
    dies_ok {
        $sp_to_test3->run_analysis (
            calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
            spatial_conditions => ['sp_get_spatial_output_list_value (output => "get_vals_from", list => "SPATIAL_RESULTS", index => "NONEXISTENT")'],
        )
    } 'error thrown when non-existent index accessed';
    
    my $sp_to_test4 = $bd->add_spatial_output (name => 'test_sp_get_spatial_output_list_value4');
    dies_ok {
        $sp_to_test4->run_analysis (
            calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
            spatial_conditions => ['sp_get_spatial_output_list_value (output => "snerble", list => "SPATIAL_RESULTS", index => "ENDW_WE")'],
        )
    } 'error thrown when non-existent output accessed';

}
