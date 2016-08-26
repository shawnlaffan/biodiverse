#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;
use Test::More;

use Biodiverse::TestHelpers qw{
    :runners
};

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_lbprop_gistar_abc2
        calc_lbprop_hashes_abc2
        calc_lbprop_quantiles_abc2
        calc_lbprop_stats_abc2
    /],
    use_element_properties => 'label',
    sort_array_lists   => 1,
    #generate_result_sets => 1,
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'LBPROP_GISTAR_LIST_ABC2' => {
                                 'LBPROP1' => '-0.349578028582733',
                                 'LBPROP2' => '-0.349578028582733',
                                 'LBPROP3' => '-1.63510521754064',
                                 'LBPROP4' => '-1.63510521754064'
                               },
  'LBPROP_QUANTILES_ABC2' => {
                               'LBPROP1_Q05' => '0.571428571428571',
                               'LBPROP1_Q10' => '0.640625',
                               'LBPROP1_Q20' => '0.666666666666667',
                               'LBPROP1_Q30' => '0.709677419354839',
                               'LBPROP1_Q40' => '0.709677419354839',
                               'LBPROP1_Q50' => '0.736842105263158',
                               'LBPROP1_Q60' => '0.782608695652174',
                               'LBPROP1_Q70' => '0.80794701986755',
                               'LBPROP1_Q80' => '0.816993464052288',
                               'LBPROP1_Q90' => '0.850609756097561',
                               'LBPROP1_Q95' => '0.85632183908046',
                               'LBPROP2_Q05' => '0.571428571428571',
                               'LBPROP2_Q10' => '0.640625',
                               'LBPROP2_Q20' => '0.666666666666667',
                               'LBPROP2_Q30' => '0.709677419354839',
                               'LBPROP2_Q40' => '0.709677419354839',
                               'LBPROP2_Q50' => '0.736842105263158',
                               'LBPROP2_Q60' => '0.782608695652174',
                               'LBPROP2_Q70' => '0.80794701986755',
                               'LBPROP2_Q80' => '0.816993464052288',
                               'LBPROP2_Q90' => '0.850609756097561',
                               'LBPROP2_Q95' => '0.85632183908046',
                               'LBPROP3_Q05' => 3,
                               'LBPROP3_Q10' => 3,
                               'LBPROP3_Q20' => 5,
                               'LBPROP3_Q30' => 9,
                               'LBPROP3_Q40' => 9,
                               'LBPROP3_Q50' => 15,
                               'LBPROP3_Q60' => 21,
                               'LBPROP3_Q70' => 23,
                               'LBPROP3_Q80' => 28,
                               'LBPROP3_Q90' => 29,
                               'LBPROP3_Q95' => 49,
                               'LBPROP4_Q05' => 3,
                               'LBPROP4_Q10' => 3,
                               'LBPROP4_Q20' => 5,
                               'LBPROP4_Q30' => 9,
                               'LBPROP4_Q40' => 9,
                               'LBPROP4_Q50' => 15,
                               'LBPROP4_Q60' => 21,
                               'LBPROP4_Q70' => 23,
                               'LBPROP4_Q80' => 28,
                               'LBPROP4_Q90' => 29,
                               'LBPROP4_Q95' => 49
                             },
  'LBPROP_STATS_ABC2' => {
                           'LBPROP1_COUNT' => 22,
                           'LBPROP1_IQR' => '0.0982696005127111',
                           'LBPROP1_KURTOSIS' => '-0.577181134336484',
                           'LBPROP1_MAX' => '0.861111111111111',
                           'LBPROP1_MEAN' => '0.741573641317808',
                           'LBPROP1_MEDIAN' => '0.72953216374269',
                           'LBPROP1_MIN' => '0.571428571428571',
                           'LBPROP1_SD' => '0.087327638223653',
                           'LBPROP1_SKEWNESS' => '-0.423450332198013',
                           'LBPROP1_SUM' => '16.3146201089918',
                           'LBPROP2_COUNT' => 22,
                           'LBPROP2_IQR' => '0.0982696005127111',
                           'LBPROP2_KURTOSIS' => '-0.577181134336484',
                           'LBPROP2_MAX' => '0.861111111111111',
                           'LBPROP2_MEAN' => '0.741573641317808',
                           'LBPROP2_MEDIAN' => '0.72953216374269',
                           'LBPROP2_MIN' => '0.571428571428571',
                           'LBPROP2_SD' => '0.087327638223653',
                           'LBPROP2_SKEWNESS' => '-0.423450332198013',
                           'LBPROP2_SUM' => '16.3146201089918',
                           'LBPROP3_COUNT' => 22,
                           'LBPROP3_IQR' => 16,
                           'LBPROP3_KURTOSIS' => '0.825372517622891',
                           'LBPROP3_MAX' => 49,
                           'LBPROP3_MEAN' => '17.4090909090909',
                           'LBPROP3_MEDIAN' => '13.5',
                           'LBPROP3_MIN' => 3,
                           'LBPROP3_SD' => '13.4860036472001',
                           'LBPROP3_SKEWNESS' => '1.11953684337945',
                           'LBPROP3_SUM' => 383,
                           'LBPROP4_COUNT' => 22,
                           'LBPROP4_IQR' => 16,
                           'LBPROP4_KURTOSIS' => '0.825372517622891',
                           'LBPROP4_MAX' => 49,
                           'LBPROP4_MEAN' => '17.4090909090909',
                           'LBPROP4_MEDIAN' => '13.5',
                           'LBPROP4_MIN' => 3,
                           'LBPROP4_SD' => '13.4860036472001',
                           'LBPROP4_SKEWNESS' => '1.11953684337945',
                           'LBPROP4_SUM' => 383
                         },
  'LBPROP_STATS_LBPROP1_HASH2' => {
                                    '0.571428571428571' => 2,
                                    '0.640625' => 2,
                                    '0.666666666666667' => 1,
                                    '0.709677419354839' => 4,
                                    '0.722222222222222' => 2,
                                    '0.736842105263158' => 1,
                                    '0.773584905660377' => 1,
                                    '0.782608695652174' => 1,
                                    '0.796116504854369' => 1,
                                    '0.80794701986755' => 2,
                                    '0.816993464052288' => 1,
                                    '0.850609756097561' => 2,
                                    '0.85632183908046' => 1,
                                    '0.861111111111111' => 1
                                  },
  'LBPROP_STATS_LBPROP2_HASH2' => {
                                    '0.571428571428571' => 2,
                                    '0.640625' => 2,
                                    '0.666666666666667' => 1,
                                    '0.709677419354839' => 4,
                                    '0.722222222222222' => 2,
                                    '0.736842105263158' => 1,
                                    '0.773584905660377' => 1,
                                    '0.782608695652174' => 1,
                                    '0.796116504854369' => 1,
                                    '0.80794701986755' => 2,
                                    '0.816993464052288' => 1,
                                    '0.850609756097561' => 2,
                                    '0.85632183908046' => 1,
                                    '0.861111111111111' => 1
                                  },
  'LBPROP_STATS_LBPROP3_HASH2' => {
                                    '10' => 1,
                                    '12' => 1,
                                    '15' => 2,
                                    '21' => 1,
                                    '23' => 2,
                                    '25' => 1,
                                    '28' => 1,
                                    '29' => 2,
                                    '3' => 3,
                                    '49' => 2,
                                    '5' => 2,
                                    '9' => 4
                                  },
  'LBPROP_STATS_LBPROP4_HASH2' => {
                                    '10' => 1,
                                    '12' => 1,
                                    '15' => 2,
                                    '21' => 1,
                                    '23' => 2,
                                    '25' => 1,
                                    '28' => 1,
                                    '29' => 2,
                                    '3' => 3,
                                    '49' => 2,
                                    '5' => 2,
                                    '9' => 4
                                  }
}

@@ RESULTS_1_NBR_LISTS
{
  'LBPROP_GISTAR_LIST_ABC2' => {
                                 'LBPROP1' => '-1.20278239101758',
                                 'LBPROP2' => '-1.20278239101758',
                                 'LBPROP3' => '-1.69263218409887',
                                 'LBPROP4' => '-1.69263218409887'
                               },
  'LBPROP_QUANTILES_ABC2' => {
                               'LBPROP1_Q05' => '0.571428571428571',
                               'LBPROP1_Q10' => '0.571428571428571',
                               'LBPROP1_Q20' => '0.571428571428571',
                               'LBPROP1_Q30' => '0.571428571428571',
                               'LBPROP1_Q40' => '0.571428571428571',
                               'LBPROP1_Q50' => '0.709677419354839',
                               'LBPROP1_Q60' => '0.709677419354839',
                               'LBPROP1_Q70' => '0.709677419354839',
                               'LBPROP1_Q80' => '0.709677419354839',
                               'LBPROP1_Q90' => '0.709677419354839',
                               'LBPROP1_Q95' => '0.709677419354839',
                               'LBPROP2_Q05' => '0.571428571428571',
                               'LBPROP2_Q10' => '0.571428571428571',
                               'LBPROP2_Q20' => '0.571428571428571',
                               'LBPROP2_Q30' => '0.571428571428571',
                               'LBPROP2_Q40' => '0.571428571428571',
                               'LBPROP2_Q50' => '0.709677419354839',
                               'LBPROP2_Q60' => '0.709677419354839',
                               'LBPROP2_Q70' => '0.709677419354839',
                               'LBPROP2_Q80' => '0.709677419354839',
                               'LBPROP2_Q90' => '0.709677419354839',
                               'LBPROP2_Q95' => '0.709677419354839',
                               'LBPROP3_Q05' => 3,
                               'LBPROP3_Q10' => 3,
                               'LBPROP3_Q20' => 3,
                               'LBPROP3_Q30' => 3,
                               'LBPROP3_Q40' => 3,
                               'LBPROP3_Q50' => 9,
                               'LBPROP3_Q60' => 9,
                               'LBPROP3_Q70' => 9,
                               'LBPROP3_Q80' => 9,
                               'LBPROP3_Q90' => 9,
                               'LBPROP3_Q95' => 9,
                               'LBPROP4_Q05' => 3,
                               'LBPROP4_Q10' => 3,
                               'LBPROP4_Q20' => 3,
                               'LBPROP4_Q30' => 3,
                               'LBPROP4_Q40' => 3,
                               'LBPROP4_Q50' => 9,
                               'LBPROP4_Q60' => 9,
                               'LBPROP4_Q70' => 9,
                               'LBPROP4_Q80' => 9,
                               'LBPROP4_Q90' => 9,
                               'LBPROP4_Q95' => 9
                             },
  'LBPROP_STATS_ABC2' => {
                           'LBPROP1_COUNT' => 2,
                           'LBPROP1_IQR' => '0.138248847926268',
                           'LBPROP1_KURTOSIS' => undef,
                           'LBPROP1_MAX' => '0.709677419354839',
                           'LBPROP1_MEAN' => '0.640552995391705',
                           'LBPROP1_MEDIAN' => '0.640552995391705',
                           'LBPROP1_MIN' => '0.571428571428571',
                           'LBPROP1_SD' => '0.0977566978598919',
                           'LBPROP1_SKEWNESS' => undef,
                           'LBPROP1_SUM' => '1.28110599078341',
                           'LBPROP2_COUNT' => 2,
                           'LBPROP2_IQR' => '0.138248847926268',
                           'LBPROP2_KURTOSIS' => undef,
                           'LBPROP2_MAX' => '0.709677419354839',
                           'LBPROP2_MEAN' => '0.640552995391705',
                           'LBPROP2_MEDIAN' => '0.640552995391705',
                           'LBPROP2_MIN' => '0.571428571428571',
                           'LBPROP2_SD' => '0.0977566978598919',
                           'LBPROP2_SKEWNESS' => undef,
                           'LBPROP2_SUM' => '1.28110599078341',
                           'LBPROP3_COUNT' => 2,
                           'LBPROP3_IQR' => 6,
                           'LBPROP3_KURTOSIS' => undef,
                           'LBPROP3_MAX' => 9,
                           'LBPROP3_MEAN' => '6',
                           'LBPROP3_MEDIAN' => '6',
                           'LBPROP3_MIN' => 3,
                           'LBPROP3_SD' => '4.24264068711928',
                           'LBPROP3_SKEWNESS' => undef,
                           'LBPROP3_SUM' => 12,
                           'LBPROP4_COUNT' => 2,
                           'LBPROP4_IQR' => 6,
                           'LBPROP4_KURTOSIS' => undef,
                           'LBPROP4_MAX' => 9,
                           'LBPROP4_MEAN' => '6',
                           'LBPROP4_MEDIAN' => '6',
                           'LBPROP4_MIN' => 3,
                           'LBPROP4_SD' => '4.24264068711928',
                           'LBPROP4_SKEWNESS' => undef,
                           'LBPROP4_SUM' => 12
                         },
  'LBPROP_STATS_LBPROP1_HASH2' => {
                                    '0.571428571428571' => 1,
                                    '0.709677419354839' => 1
                                  },
  'LBPROP_STATS_LBPROP2_HASH2' => {
                                    '0.571428571428571' => 1,
                                    '0.709677419354839' => 1
                                  },
  'LBPROP_STATS_LBPROP3_HASH2' => {
                                    '3' => 1,
                                    '9' => 1
                                  },
  'LBPROP_STATS_LBPROP4_HASH2' => {
                                    '3' => 1,
                                    '9' => 1
                                  }
}
