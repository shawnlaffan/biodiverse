#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;


use rlib;
use Test2::V0;

use Biodiverse::TestHelpers qw{
    :runners
};

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_gpprop_gistar
        calc_gpprop_lists
        calc_gpprop_hashes
        calc_gpprop_quantiles
        calc_gpprop_stats
    /],
    use_element_properties => 'group',
    sort_array_lists   => 1,
    generate_result_sets => 1,
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   GPPROP_GISTAR_LIST => {
        PROP1 => '0.550100727656521',
        PROP2 => '-0.0219908030260867',
        PROP3 => '1.50256200660814'
    },
    GPPROP_QUANTILE_LIST => {
        GPPROP_STATS_PROP1_Q05 => '796.11254',
        GPPROP_STATS_PROP1_Q10 => '820.40838',
        GPPROP_STATS_PROP1_Q20 => '869.00006',
        GPPROP_STATS_PROP1_Q30 => '893.9694',
        GPPROP_STATS_PROP1_Q40 => '895.3164',
        GPPROP_STATS_PROP1_Q50 => '896.6634',
        GPPROP_STATS_PROP1_Q60 => '938.391247403168',
        GPPROP_STATS_PROP1_Q70 => '980.119094806336',
        GPPROP_STATS_PROP1_Q80 => '1034.55399480634',
        GPPROP_STATS_PROP1_Q90 => '1101.69594740317',
        GPPROP_STATS_PROP1_Q95 => '1135.26692370158',
        GPPROP_STATS_PROP2_Q05 => '503',
        GPPROP_STATS_PROP2_Q10 => '511',
        GPPROP_STATS_PROP2_Q20 => '527',
        GPPROP_STATS_PROP2_Q30 => '548.8',
        GPPROP_STATS_PROP2_Q40 => '576.4',
        GPPROP_STATS_PROP2_Q50 => '604',
        GPPROP_STATS_PROP2_Q60 => '613.2',
        GPPROP_STATS_PROP2_Q70 => '622.4',
        GPPROP_STATS_PROP2_Q80 => '661.2',
        GPPROP_STATS_PROP2_Q90 => '729.6',
        GPPROP_STATS_PROP2_Q95 => '763.8',
        GPPROP_STATS_PROP3_Q05 => '626.4',
        GPPROP_STATS_PROP3_Q10 => '733.8',
        GPPROP_STATS_PROP3_Q20 => '948.6',
        GPPROP_STATS_PROP3_Q30 => '1087.2',
        GPPROP_STATS_PROP3_Q40 => '1149.6',
        GPPROP_STATS_PROP3_Q50 => '1212',
        GPPROP_STATS_PROP3_Q60 => '1253.2',
        GPPROP_STATS_PROP3_Q70 => '1294.4',
        GPPROP_STATS_PROP3_Q80 => '1459.2',
        GPPROP_STATS_PROP3_Q90 => '1747.6',
        GPPROP_STATS_PROP3_Q95 => '1891.8'
    },
    GPPROP_STATS_LIST => {
        PROP1_COUNT  => 5,
        PROP1_IQR    => '107.68711850792',
        PROP1_MAX    => '1168.8379',
        PROP1_MEAN   => '946.319383701584',
        PROP1_MEDIAN => '896.6634',
        PROP1_MIN    => '771.8167',
        PROP1_SD     => '148.518514187768',
        PROP1_SUM    => '4731.59691850792',
        PROP2_COUNT  => 5,
        PROP2_IQR    => 92,
        PROP2_MAX    => '798',
        PROP2_MEAN   => '611.8',
        PROP2_MEDIAN => '604',
        PROP2_MIN    => '495',
        PROP2_SD     => '116.729173731334',
        PROP2_SUM    => '3059',
        PROP3_COUNT  => 5,
        PROP3_IQR    => 259,
        PROP3_MAX    => '2036',
        PROP3_MEAN   => '1227.6',
        PROP3_MEDIAN => '1212',
        PROP3_MIN    => '519',
        PROP3_SD     => '546.111984852924',
        PROP3_SUM    => '6138'
    },
    GPPROP_STATS_PROP1_DATA => [
        '896.6634', '1000.98301850792', '1168.8379', '771.8167',
        '893.2959'
    ],
    GPPROP_STATS_PROP1_HASH => {
        '1000.98301850792' => 1,
        '1168.8379'        => 1,
        '771.8167'         => 1,
        '893.2959'         => 1,
        '896.6634'         => 1
    },
    GPPROP_STATS_PROP2_DATA => [ '535', '798', '627', '495', '604' ],
    GPPROP_STATS_PROP2_HASH => {
        495 => 1,
        535 => 1,
        604 => 1,
        627 => 1,
        798 => 1
    },
    GPPROP_STATS_PROP3_DATA => [ '1212', '519', '2036', '1315', '1056' ],
    GPPROP_STATS_PROP3_HASH => {
        1056 => 1,
        1212 => 1,
        1315 => 1,
        2036 => 1,
        519  => 1
    }
}


@@ RESULTS_1_NBR_LISTS
{   GPPROP_GISTAR_LIST => {
        PROP1 => '-0.196251534324138',
        PROP2 => '-0.470216283178489',
        PROP3 => '0.781087839068424'
    },
    GPPROP_QUANTILE_LIST => {
        GPPROP_STATS_PROP1_Q05 => '771.8167',
        GPPROP_STATS_PROP1_Q10 => '771.8167',
        GPPROP_STATS_PROP1_Q20 => '771.8167',
        GPPROP_STATS_PROP1_Q30 => '771.8167',
        GPPROP_STATS_PROP1_Q40 => '771.8167',
        GPPROP_STATS_PROP1_Q50 => '771.8167',
        GPPROP_STATS_PROP1_Q60 => '771.8167',
        GPPROP_STATS_PROP1_Q70 => '771.8167',
        GPPROP_STATS_PROP1_Q80 => '771.8167',
        GPPROP_STATS_PROP1_Q90 => '771.8167',
        GPPROP_STATS_PROP1_Q95 => '771.8167',
        GPPROP_STATS_PROP2_Q05 => '495',
        GPPROP_STATS_PROP2_Q10 => '495',
        GPPROP_STATS_PROP2_Q20 => '495',
        GPPROP_STATS_PROP2_Q30 => '495',
        GPPROP_STATS_PROP2_Q40 => '495',
        GPPROP_STATS_PROP2_Q50 => '495',
        GPPROP_STATS_PROP2_Q60 => '495',
        GPPROP_STATS_PROP2_Q70 => '495',
        GPPROP_STATS_PROP2_Q80 => '495',
        GPPROP_STATS_PROP2_Q90 => '495',
        GPPROP_STATS_PROP2_Q95 => '495',
        GPPROP_STATS_PROP3_Q05 => '1315',
        GPPROP_STATS_PROP3_Q10 => '1315',
        GPPROP_STATS_PROP3_Q20 => '1315',
        GPPROP_STATS_PROP3_Q30 => '1315',
        GPPROP_STATS_PROP3_Q40 => '1315',
        GPPROP_STATS_PROP3_Q50 => '1315',
        GPPROP_STATS_PROP3_Q60 => '1315',
        GPPROP_STATS_PROP3_Q70 => '1315',
        GPPROP_STATS_PROP3_Q80 => '1315',
        GPPROP_STATS_PROP3_Q90 => '1315',
        GPPROP_STATS_PROP3_Q95 => '1315'
    },
    GPPROP_STATS_LIST => {
        PROP1_COUNT  => 1,
        PROP1_IQR    => '0',
        PROP1_MAX    => '771.8167',
        PROP1_MEAN   => '771.8167',
        PROP1_MEDIAN => '771.8167',
        PROP1_MIN    => '771.8167',
        PROP1_SD     => 0,
        PROP1_SUM    => '771.8167',
        PROP2_COUNT  => 1,
        PROP2_IQR    => 0,
        PROP2_MAX    => '495',
        PROP2_MEAN   => '495',
        PROP2_MEDIAN => '495',
        PROP2_MIN    => '495',
        PROP2_SD     => 0,
        PROP2_SUM    => '495',
        PROP3_COUNT  => 1,
        PROP3_IQR    => 0,
        PROP3_MAX    => '1315',
        PROP3_MEAN   => '1315',
        PROP3_MEDIAN => '1315',
        PROP3_MIN    => '1315',
        PROP3_SD     => 0,
        PROP3_SUM    => '1315'
    },
    GPPROP_STATS_PROP1_DATA => ['771.8167'],
    GPPROP_STATS_PROP1_HASH => { '771.8167' => 1 },
    GPPROP_STATS_PROP2_DATA => ['495'],
    GPPROP_STATS_PROP2_HASH => { 495 => 1 },
    GPPROP_STATS_PROP3_DATA => ['1315'],
    GPPROP_STATS_PROP3_HASH => { 1315 => 1 }
}


