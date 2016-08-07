#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;
use Test::Most;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
};


test_rank_abundances();
test_no_recycling();


sub test_rank_abundances {
    
    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_label_count_quantile_position
            calc_local_sample_count_quantiles
        /],
        #calc_topic_to_test => 'Lists and Counts',
        sort_array_lists   => 1,
        nbr_set2_sp_select_all => 1,
        #generate_result_sets => 1,
    );
}

#  make sure we don't recycle 
sub test_no_recycling {
    my $bd = get_basedata_object_from_site_data (CELL_SIZES => [300000, 300000]);
    
    my $sp = $bd->add_spatial_output (name => 'test_no_recycling');
    $sp->run_analysis (
        calculations => ['calc_label_count_quantile_position'],
        spatial_conditions => ['sp_select_all()'],
    );

    ok (!$sp->get_param ('RESULTS_ARE_RECYCLABLE'), 'recycling flag not set');
    
    no autovivification;

    subtest 'results not recycled' => sub {
        my @gp_list = $sp->get_element_list;
        my $first = shift @gp_list;
        my $sp_results1 = $sp->get_list_ref (
            element => $first,
            list    => 'LABEL_COUNT_RANK_PCT',
        );

        foreach my $gp (@gp_list) {
            my $sp_results = $sp->get_list_ref (
                element => $gp,
                list    => 'LABEL_COUNT_RANK_PCT',
            );
            isnt_deeply ($sp_results, $sp_results1, "lists not the same $gp");
        }
    }
}

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   ABC3_QUANTILES_ALL => {
        Q000 => 5,
        Q005 => 7,
        Q010 => 7,
        Q015 => 9,
        Q020 => 10,
        Q025 => 18,
        Q030 => 18,
        Q035 => 20,
        Q040 => 23,
        Q045 => 30,
        Q050 => 31,
        Q055 => 36,
        Q060 => 38,
        Q065 => 53,
        Q070 => 54,
        Q075 => 64,
        Q080 => 79,
        Q085 => 151,
        Q090 => 153,
        Q095 => 180,
        Q100 => 328
    },
    ABC3_QUANTILES_SET1 => {
        Q000 => 2,
        Q005 => 2,
        Q010 => 2,
        Q015 => 2,
        Q020 => 2,
        Q025 => 2,
        Q030 => 2,
        Q035 => 2,
        Q040 => 2,
        Q045 => 2,
        Q050 => 4,
        Q055 => 4,
        Q060 => 4,
        Q065 => 4,
        Q070 => 4,
        Q075 => 4,
        Q080 => 4,
        Q085 => 4,
        Q090 => 4,
        Q095 => 4,
        Q100 => 4
    },
    ABC3_QUANTILES_SET2 => {
        Q000 => 5,
        Q005 => 6,
        Q010 => 7,
        Q015 => 9,
        Q020 => 10,
        Q025 => 18,
        Q030 => 18,
        Q035 => 20,
        Q040 => 23,
        Q045 => 27,
        Q050 => 30,
        Q055 => 36,
        Q060 => 38,
        Q065 => 53,
        Q070 => 54,
        Q075 => 64,
        Q080 => 79,
        Q085 => 151,
        Q090 => 153,
        Q095 => 180,
        Q100 => 328
    },
    LABEL_COUNT_RANK_PCT => {
        'Genus:sp1'  => '0',
        'Genus:sp10' => '0',
        'Genus:sp11' => '0',
        'Genus:sp12' => '0',
        'Genus:sp13' => '0',
        'Genus:sp14' => '0',
        'Genus:sp15' => '0',
        'Genus:sp16' => '0',
        'Genus:sp17' => '0',
        'Genus:sp18' => '0',
        'Genus:sp19' => '0',
        'Genus:sp2'  => '0',
        'Genus:sp20' => '97.6190476190476',
        'Genus:sp21' => '0',
        'Genus:sp22' => '0',
        'Genus:sp23' => '0',
        'Genus:sp24' => '0',
        'Genus:sp25' => '0',
        'Genus:sp26' => '99.2063492063492',
        'Genus:sp27' => '0',
        'Genus:sp28' => '0',
        'Genus:sp29' => '0',
        'Genus:sp3'  => '0',
        'Genus:sp30' => '0',
        'Genus:sp31' => '0',
        'Genus:sp4'  => '0',
        'Genus:sp5'  => '0',
        'Genus:sp6'  => '0',
        'Genus:sp7'  => '0',
        'Genus:sp8'  => '0',
        'Genus:sp9'  => '0'
    }
}


@@ RESULTS_1_NBR_LISTS
{   ABC3_QUANTILES_SET1 => {
        Q000 => 2,
        Q005 => 2,
        Q010 => 2,
        Q015 => 2,
        Q020 => 2,
        Q025 => 2,
        Q030 => 2,
        Q035 => 2,
        Q040 => 2,
        Q045 => 2,
        Q050 => 4,
        Q055 => 4,
        Q060 => 4,
        Q065 => 4,
        Q070 => 4,
        Q075 => 4,
        Q080 => 4,
        Q085 => 4,
        Q090 => 4,
        Q095 => 4,
        Q100 => 4
    },
    LABEL_COUNT_RANK_PCT => {
        'Genus:sp20' => undef,
        'Genus:sp26' => undef
    }
}


