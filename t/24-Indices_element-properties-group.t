#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;
use rlib;
use Test::Most;

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
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'GPPROP_GISTAR_LIST' => {
                            'PROP1' => '0.550100727656519',
                            'PROP2' => '-0.0219908030260867',
                            'PROP3' => '1.50256200660814'
                          },
  'GPPROP_QUANTILE_LIST' => {
                          'GPPROP_STATS_PROP1_Q05' => '771.8167',
                          'GPPROP_STATS_PROP1_Q10' => '771.8167',
                          'GPPROP_STATS_PROP1_Q20' => '893.2959',
                          'GPPROP_STATS_PROP1_Q30' => '893.2959',
                          'GPPROP_STATS_PROP1_Q40' => '896.6634',
                          'GPPROP_STATS_PROP1_Q50' => '896.6634',
                          'GPPROP_STATS_PROP1_Q60' => '896.6634',
                          'GPPROP_STATS_PROP1_Q70' => '1000.98301850792',
                          'GPPROP_STATS_PROP1_Q80' => '1000.98301850792',
                          'GPPROP_STATS_PROP1_Q90' => '1168.8379',
                          'GPPROP_STATS_PROP1_Q95' => '1168.8379',
                          'GPPROP_STATS_PROP2_Q05' => 495,
                          'GPPROP_STATS_PROP2_Q10' => 495,
                          'GPPROP_STATS_PROP2_Q20' => 535,
                          'GPPROP_STATS_PROP2_Q30' => 535,
                          'GPPROP_STATS_PROP2_Q40' => 604,
                          'GPPROP_STATS_PROP2_Q50' => 604,
                          'GPPROP_STATS_PROP2_Q60' => 604,
                          'GPPROP_STATS_PROP2_Q70' => 627,
                          'GPPROP_STATS_PROP2_Q80' => 627,
                          'GPPROP_STATS_PROP2_Q90' => 798,
                          'GPPROP_STATS_PROP2_Q95' => 798,
                          'GPPROP_STATS_PROP3_Q05' => 519,
                          'GPPROP_STATS_PROP3_Q10' => 519,
                          'GPPROP_STATS_PROP3_Q20' => 1056,
                          'GPPROP_STATS_PROP3_Q30' => 1056,
                          'GPPROP_STATS_PROP3_Q40' => 1212,
                          'GPPROP_STATS_PROP3_Q50' => 1212,
                          'GPPROP_STATS_PROP3_Q60' => 1212,
                          'GPPROP_STATS_PROP3_Q70' => 1315,
                          'GPPROP_STATS_PROP3_Q80' => 1315,
                          'GPPROP_STATS_PROP3_Q90' => 2036,
                          'GPPROP_STATS_PROP3_Q95' => 2036
                        },
  'GPPROP_STATS_LIST' => {
                      'PROP1_COUNT'  => 5,
                      'PROP1_IQR'    => '107.68711850792',
                      'PROP1_MAX'    => '1168.8379',
                      'PROP1_MEAN'   => '946.319383701584',
                      'PROP1_MEDIAN' => '896.6634',
                      'PROP1_MIN'    => '771.8167',
                      'PROP1_SD'     => '148.518514187768',
                      'PROP1_SUM'    => '4731.59691850792',
                      'PROP2_COUNT'  => 5,
                      'PROP2_IQR'    => 92,
                      'PROP2_MAX'    => 798,
                      'PROP2_MEAN'   => '611.8',
                      'PROP2_MEDIAN' => 604,
                      'PROP2_MIN'    => 495,
                      'PROP2_SD'     => '116.729173731334',
                      'PROP2_SUM'    => 3059,
                      'PROP3_COUNT'  => 5,
                      'PROP3_IQR'    => 259,
                      'PROP3_MAX'    => 2036,
                      'PROP3_MEAN'   => '1227.6',
                      'PROP3_MEDIAN' => 1212,
                      'PROP3_MIN'    => 519,
                      'PROP3_SD'     => '546.111984852924',
                      'PROP3_SUM'    => 6138
                    },
  'GPPROP_STATS_PROP1_DATA' => [
                                 '771.8167',
                                 '893.2959',
                                 '896.6634',
                                 '1000.98301850792',
                                 '1168.8379'
                               ],
  'GPPROP_STATS_PROP1_HASH' => {
                                 '1000.98301850792' => 1,
                                 '1168.8379'        => 1,
                                 '771.8167'         => 1,
                                 '893.2959'         => 1,
                                 '896.6634'         => 1
                               },
  'GPPROP_STATS_PROP2_DATA' => [
                                 495,
                                 535,
                                 604,
                                 627,
                                 798
                               ],
  'GPPROP_STATS_PROP2_HASH' => {
                                 '495' => 1,
                                 '535' => 1,
                                 '604' => 1,
                                 '627' => 1,
                                 '798' => 1
                               },
  'GPPROP_STATS_PROP3_DATA' => [
                                 519,
                                 1056,
                                 1212,
                                 1315,
                                 2036
                               ],
  'GPPROP_STATS_PROP3_HASH' => {
                                 '1056' => 1,
                                 '1212' => 1,
                                 '1315' => 1,
                                 '2036' => 1,
                                 '519'  => 1
                               }
}

@@ RESULTS_1_NBR_LISTS
{
  'GPPROP_GISTAR_LIST' => {
                            'PROP1' => '-0.19625153432414',
                            'PROP2' => '-0.470216283178489',
                            'PROP3' => '0.781087839068424'
                          },
  'GPPROP_QUANTILE_LIST' => {
                          'GPPROP_STATS_PROP1_Q05' => '771.8167',
                          'GPPROP_STATS_PROP1_Q10' => '771.8167',
                          'GPPROP_STATS_PROP1_Q20' => '771.8167',
                          'GPPROP_STATS_PROP1_Q30' => '771.8167',
                          'GPPROP_STATS_PROP1_Q40' => '771.8167',
                          'GPPROP_STATS_PROP1_Q50' => '771.8167',
                          'GPPROP_STATS_PROP1_Q60' => '771.8167',
                          'GPPROP_STATS_PROP1_Q70' => '771.8167',
                          'GPPROP_STATS_PROP1_Q80' => '771.8167',
                          'GPPROP_STATS_PROP1_Q90' => '771.8167',
                          'GPPROP_STATS_PROP1_Q95' => '771.8167',
                          'GPPROP_STATS_PROP2_Q05' => 495,
                          'GPPROP_STATS_PROP2_Q10' => 495,
                          'GPPROP_STATS_PROP2_Q20' => 495,
                          'GPPROP_STATS_PROP2_Q30' => 495,
                          'GPPROP_STATS_PROP2_Q40' => 495,
                          'GPPROP_STATS_PROP2_Q50' => 495,
                          'GPPROP_STATS_PROP2_Q60' => 495,
                          'GPPROP_STATS_PROP2_Q70' => 495,
                          'GPPROP_STATS_PROP2_Q80' => 495,
                          'GPPROP_STATS_PROP2_Q90' => 495,
                          'GPPROP_STATS_PROP2_Q95' => 495,
                          'GPPROP_STATS_PROP3_Q05' => 1315,
                          'GPPROP_STATS_PROP3_Q10' => 1315,
                          'GPPROP_STATS_PROP3_Q20' => 1315,
                          'GPPROP_STATS_PROP3_Q30' => 1315,
                          'GPPROP_STATS_PROP3_Q40' => 1315,
                          'GPPROP_STATS_PROP3_Q50' => 1315,
                          'GPPROP_STATS_PROP3_Q60' => 1315,
                          'GPPROP_STATS_PROP3_Q70' => 1315,
                          'GPPROP_STATS_PROP3_Q80' => 1315,
                          'GPPROP_STATS_PROP3_Q90' => 1315,
                          'GPPROP_STATS_PROP3_Q95' => 1315
                        },
  'GPPROP_STATS_LIST' => {
                      'PROP1_COUNT'  => 1,
                      'PROP1_IQR'    => '0',
                      'PROP1_MAX'    => '771.8167',
                      'PROP1_MEAN'   => '771.8167',
                      'PROP1_MEDIAN' => '771.8167',
                      'PROP1_MIN'    => '771.8167',
                      'PROP1_SD'     => '0',
                      'PROP1_SUM'    => '771.8167',
                      'PROP2_COUNT'  => 1,
                      'PROP2_IQR'    => 0,
                      'PROP2_MAX'    => 495,
                      'PROP2_MEAN'   => '495',
                      'PROP2_MEDIAN' => 495,
                      'PROP2_MIN'    => 495,
                      'PROP2_SD'     => '0',
                      'PROP2_SUM'    => 495,
                      'PROP3_COUNT'  => 1,
                      'PROP3_IQR'    => 0,
                      'PROP3_MAX'    => 1315,
                      'PROP3_MEAN'   => '1315',
                      'PROP3_MEDIAN' => 1315,
                      'PROP3_MIN'    => 1315,
                      'PROP3_SD'     => '0',
                      'PROP3_SUM'    => 1315
                    },
  'GPPROP_STATS_PROP1_DATA' => [
                                 '771.8167'
                               ],
  'GPPROP_STATS_PROP1_HASH' => {
                                 '771.8167' => 1
                               },
  'GPPROP_STATS_PROP2_DATA' => [
                                 495
                               ],
  'GPPROP_STATS_PROP2_HASH' => {
                                 '495' => 1
                               },
  'GPPROP_STATS_PROP3_DATA' => [
                                 1315
                               ],
  'GPPROP_STATS_PROP3_HASH' => {
                                 '1315' => 1
                               }
}
