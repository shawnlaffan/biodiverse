#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;
use Test::Most;

use Biodiverse::TestHelpers qw{
    :runners
};

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_lbprop_gistar
        calc_lbprop_data
        calc_lbprop_hashes
        calc_lbprop_quantiles
        calc_lbprop_stats
        calc_lbprop_lists
    /],
    use_element_properties => 'label',
    sort_array_lists       => 1,
    #generate_result_sets   => 1,
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   LBPROP_GISTAR_LIST => {
        LBPROP1 => '1.07756057803133',
        LBPROP2 => '1.07756057803133',
        LBPROP3 => '2.30649714125927',
        LBPROP4 => '2.30649714125927'
    },
    LBPROP_LIST_LBPROP1 => {
        'Genus:sp1'  => '0.640625',
        'Genus:sp10' => '0.816993464052288',
        'Genus:sp11' => '0.850609756097561',
        'Genus:sp12' => '0.80794701986755',
        'Genus:sp15' => '0.722222222222222',
        'Genus:sp20' => '0.709677419354839',
        'Genus:sp23' => '0.85632183908046',
        'Genus:sp24' => '0.782608695652174',
        'Genus:sp25' => '0.666666666666667',
        'Genus:sp26' => '0.571428571428571',
        'Genus:sp27' => '0.861111111111111',
        'Genus:sp29' => '0.773584905660377',
        'Genus:sp30' => '0.796116504854369',
        'Genus:sp5'  => '0.736842105263158'
    },
    LBPROP_LIST_LBPROP2 => {
        'Genus:sp1'  => '0.640625',
        'Genus:sp10' => '0.816993464052288',
        'Genus:sp11' => '0.850609756097561',
        'Genus:sp12' => '0.80794701986755',
        'Genus:sp15' => '0.722222222222222',
        'Genus:sp20' => '0.709677419354839',
        'Genus:sp23' => '0.85632183908046',
        'Genus:sp24' => '0.782608695652174',
        'Genus:sp25' => '0.666666666666667',
        'Genus:sp26' => '0.571428571428571',
        'Genus:sp27' => '0.861111111111111',
        'Genus:sp29' => '0.773584905660377',
        'Genus:sp30' => '0.796116504854369',
        'Genus:sp5'  => '0.736842105263158'
    },
    LBPROP_LIST_LBPROP3 => {
        'Genus:sp1'  => '23',
        'Genus:sp10' => '28',
        'Genus:sp11' => '49',
        'Genus:sp12' => '29',
        'Genus:sp15' => '15',
        'Genus:sp20' => '9',
        'Genus:sp23' => '25',
        'Genus:sp24' => '5',
        'Genus:sp25' => '3',
        'Genus:sp26' => '3',
        'Genus:sp27' => '5',
        'Genus:sp29' => '12',
        'Genus:sp30' => '21',
        'Genus:sp5'  => '10'
    },
    LBPROP_LIST_LBPROP4 => {
        'Genus:sp1'  => '23',
        'Genus:sp10' => '28',
        'Genus:sp11' => '49',
        'Genus:sp12' => '29',
        'Genus:sp15' => '15',
        'Genus:sp20' => '9',
        'Genus:sp23' => '25',
        'Genus:sp24' => '5',
        'Genus:sp25' => '3',
        'Genus:sp26' => '3',
        'Genus:sp27' => '5',
        'Genus:sp29' => '12',
        'Genus:sp30' => '21',
        'Genus:sp5'  => '10'
    },
    LBPROP_QUANTILES => {
        LBPROP1_Q05 => '0.640625',
        LBPROP1_Q10 => '0.640625',
        LBPROP1_Q20 => '0.709677419354839',
        LBPROP1_Q30 => '0.722222222222222',
        LBPROP1_Q40 => '0.736842105263158',
        LBPROP1_Q50 => '0.782608695652174',
        LBPROP1_Q60 => '0.796116504854369',
        LBPROP1_Q70 => '0.80794701986755',
        LBPROP1_Q80 => '0.816993464052288',
        LBPROP1_Q90 => '0.85632183908046',
        LBPROP1_Q95 => '0.85632183908046',
        LBPROP2_Q05 => '0.640625',
        LBPROP2_Q10 => '0.640625',
        LBPROP2_Q20 => '0.709677419354839',
        LBPROP2_Q30 => '0.722222222222222',
        LBPROP2_Q40 => '0.736842105263158',
        LBPROP2_Q50 => '0.782608695652174',
        LBPROP2_Q60 => '0.796116504854369',
        LBPROP2_Q70 => '0.80794701986755',
        LBPROP2_Q80 => '0.816993464052288',
        LBPROP2_Q90 => '0.85632183908046',
        LBPROP2_Q95 => '0.85632183908046',
        LBPROP3_Q05 => 3,
        LBPROP3_Q10 => 3,
        LBPROP3_Q20 => 5,
        LBPROP3_Q30 => 9,
        LBPROP3_Q40 => 10,
        LBPROP3_Q50 => 15,
        LBPROP3_Q60 => 21,
        LBPROP3_Q70 => 23,
        LBPROP3_Q80 => 25,
        LBPROP3_Q90 => 29,
        LBPROP3_Q95 => 29,
        LBPROP4_Q05 => 3,
        LBPROP4_Q10 => 3,
        LBPROP4_Q20 => 5,
        LBPROP4_Q30 => 9,
        LBPROP4_Q40 => 10,
        LBPROP4_Q50 => 15,
        LBPROP4_Q60 => 21,
        LBPROP4_Q70 => 23,
        LBPROP4_Q80 => 25,
        LBPROP4_Q90 => 29,
        LBPROP4_Q95 => 29
    },
    LBPROP_STATS => {
        LBPROP1_COUNT    => 14,
        LBPROP1_IQR      => '0.107316044697449',
        LBPROP1_KURTOSIS => '-0.0844676863889156',
        LBPROP1_MAX      => '0.861111111111111',
        LBPROP1_MEAN     => '0.756625377236525',
        LBPROP1_MEDIAN   => '0.778096800656275',
        LBPROP1_MIN      => '0.571428571428571',
        LBPROP1_SD       => '0.0868756054758619',
        LBPROP1_SKEWNESS => '-0.737968413124927',
        LBPROP1_SUM      => '10.5927552813113',
        LBPROP2_COUNT    => 14,
        LBPROP2_IQR      => '0.107316044697449',
        LBPROP2_KURTOSIS => '-0.0844676863889156',
        LBPROP2_MAX      => '0.861111111111111',
        LBPROP2_MEAN     => '0.756625377236525',
        LBPROP2_MEDIAN   => '0.778096800656275',
        LBPROP2_MIN      => '0.571428571428571',
        LBPROP2_SD       => '0.0868756054758619',
        LBPROP2_SKEWNESS => '-0.737968413124927',
        LBPROP2_SUM      => '10.5927552813113',
        LBPROP3_COUNT    => 14,
        LBPROP3_IQR      => 20,
        LBPROP3_KURTOSIS => '1.25837080448576',
        LBPROP3_MAX      => 49,
        LBPROP3_MEAN     => '16.9285714285714',
        LBPROP3_MEDIAN   => '13.5',
        LBPROP3_MIN      => 3,
        LBPROP3_SD       => '13.088246551857',
        LBPROP3_SKEWNESS => '1.08731660256672',
        LBPROP3_SUM      => 237,
        LBPROP4_COUNT    => 14,
        LBPROP4_IQR      => 20,
        LBPROP4_KURTOSIS => '1.25837080448576',
        LBPROP4_MAX      => 49,
        LBPROP4_MEAN     => '16.9285714285714',
        LBPROP4_MEDIAN   => '13.5',
        LBPROP4_MIN      => 3,
        LBPROP4_SD       => '13.088246551857',
        LBPROP4_SKEWNESS => '1.08731660256672',
        LBPROP4_SUM      => 237
    },
    LBPROP_STATS_LBPROP1_DATA => [
        '0.861111111111111', '0.80794701986755',
        '0.722222222222222', '0.85632183908046',
        '0.736842105263158', '0.571428571428571',
        '0.709677419354839', '0.773584905660377',
        '0.782608695652174', '0.796116504854369',
        '0.666666666666667', '0.850609756097561',
        '0.816993464052288', '0.640625'
    ],
    LBPROP_STATS_LBPROP1_HASH => {
        '0.571428571428571' => 1,
        '0.640625'          => 1,
        '0.666666666666667' => 1,
        '0.709677419354839' => 1,
        '0.722222222222222' => 1,
        '0.736842105263158' => 1,
        '0.773584905660377' => 1,
        '0.782608695652174' => 1,
        '0.796116504854369' => 1,
        '0.80794701986755'  => 1,
        '0.816993464052288' => 1,
        '0.850609756097561' => 1,
        '0.85632183908046'  => 1,
        '0.861111111111111' => 1
    },
    LBPROP_STATS_LBPROP2_DATA => [
        '0.861111111111111', '0.80794701986755',
        '0.722222222222222', '0.85632183908046',
        '0.736842105263158', '0.571428571428571',
        '0.709677419354839', '0.773584905660377',
        '0.782608695652174', '0.796116504854369',
        '0.666666666666667', '0.850609756097561',
        '0.816993464052288', '0.640625'
    ],
    LBPROP_STATS_LBPROP2_HASH => {
        '0.571428571428571' => 1,
        '0.640625'          => 1,
        '0.666666666666667' => 1,
        '0.709677419354839' => 1,
        '0.722222222222222' => 1,
        '0.736842105263158' => 1,
        '0.773584905660377' => 1,
        '0.782608695652174' => 1,
        '0.796116504854369' => 1,
        '0.80794701986755'  => 1,
        '0.816993464052288' => 1,
        '0.850609756097561' => 1,
        '0.85632183908046'  => 1,
        '0.861111111111111' => 1
    },
    LBPROP_STATS_LBPROP3_DATA =>
        [ 5, 29, 15, 25, 10, 3, 9, 12, 5, 21, 3, 49, 28, 23 ],
    LBPROP_STATS_LBPROP3_HASH => {
        '10' => 1,
        '12' => 1,
        '15' => 1,
        '21' => 1,
        '23' => 1,
        '25' => 1,
        '28' => 1,
        '29' => 1,
        '3'  => 2,
        '49' => 1,
        '5'  => 2,
        '9'  => 1
    },
    LBPROP_STATS_LBPROP4_DATA =>
        [ 5, 29, 15, 25, 10, 3, 9, 12, 5, 21, 3, 49, 28, 23 ],
    LBPROP_STATS_LBPROP4_HASH => {
        '10' => 1,
        '12' => 1,
        '15' => 1,
        '21' => 1,
        '23' => 1,
        '25' => 1,
        '28' => 1,
        '29' => 1,
        '3'  => 2,
        '49' => 1,
        '5'  => 2,
        '9'  => 1
    }
}


@@ RESULTS_1_NBR_LISTS
{   LBPROP_GISTAR_LIST => {
        LBPROP1 => '-0.666483486166473',
        LBPROP2 => '-0.666483486166473',
        LBPROP3 => '-0.747729379232734',
        LBPROP4 => '-0.747729379232734'
    },
    LBPROP_LIST_LBPROP1 => {
        'Genus:sp20' => '0.709677419354839',
        'Genus:sp26' => '0.571428571428571'
    },
    LBPROP_LIST_LBPROP2 => {
        'Genus:sp20' => '0.709677419354839',
        'Genus:sp26' => '0.571428571428571'
    },
    LBPROP_LIST_LBPROP3 => {
        'Genus:sp20' => '9',
        'Genus:sp26' => '3'
    },
    LBPROP_LIST_LBPROP4 => {
        'Genus:sp20' => '9',
        'Genus:sp26' => '3'
    },
    LBPROP_QUANTILES => {
        LBPROP1_Q05 => '0.571428571428571',
        LBPROP1_Q10 => '0.571428571428571',
        LBPROP1_Q20 => '0.571428571428571',
        LBPROP1_Q30 => '0.571428571428571',
        LBPROP1_Q40 => '0.571428571428571',
        LBPROP1_Q50 => '0.709677419354839',
        LBPROP1_Q60 => '0.709677419354839',
        LBPROP1_Q70 => '0.709677419354839',
        LBPROP1_Q80 => '0.709677419354839',
        LBPROP1_Q90 => '0.709677419354839',
        LBPROP1_Q95 => '0.709677419354839',
        LBPROP2_Q05 => '0.571428571428571',
        LBPROP2_Q10 => '0.571428571428571',
        LBPROP2_Q20 => '0.571428571428571',
        LBPROP2_Q30 => '0.571428571428571',
        LBPROP2_Q40 => '0.571428571428571',
        LBPROP2_Q50 => '0.709677419354839',
        LBPROP2_Q60 => '0.709677419354839',
        LBPROP2_Q70 => '0.709677419354839',
        LBPROP2_Q80 => '0.709677419354839',
        LBPROP2_Q90 => '0.709677419354839',
        LBPROP2_Q95 => '0.709677419354839',
        LBPROP3_Q05 => 3,
        LBPROP3_Q10 => 3,
        LBPROP3_Q20 => 3,
        LBPROP3_Q30 => 3,
        LBPROP3_Q40 => 3,
        LBPROP3_Q50 => 9,
        LBPROP3_Q60 => 9,
        LBPROP3_Q70 => 9,
        LBPROP3_Q80 => 9,
        LBPROP3_Q90 => 9,
        LBPROP3_Q95 => 9,
        LBPROP4_Q05 => 3,
        LBPROP4_Q10 => 3,
        LBPROP4_Q20 => 3,
        LBPROP4_Q30 => 3,
        LBPROP4_Q40 => 3,
        LBPROP4_Q50 => 9,
        LBPROP4_Q60 => 9,
        LBPROP4_Q70 => 9,
        LBPROP4_Q80 => 9,
        LBPROP4_Q90 => 9,
        LBPROP4_Q95 => 9
    },
    LBPROP_STATS => {
        LBPROP1_COUNT    => 2,
        LBPROP1_IQR      => '0.138248847926268',
        LBPROP1_KURTOSIS => undef,
        LBPROP1_MAX      => '0.709677419354839',
        LBPROP1_MEAN     => '0.640552995391705',
        LBPROP1_MEDIAN   => '0.640552995391705',
        LBPROP1_MIN      => '0.571428571428571',
        LBPROP1_SD       => '0.0977566978598919',
        LBPROP1_SKEWNESS => undef,
        LBPROP1_SUM      => '1.28110599078341',
        LBPROP2_COUNT    => 2,
        LBPROP2_IQR      => '0.138248847926268',
        LBPROP2_KURTOSIS => undef,
        LBPROP2_MAX      => '0.709677419354839',
        LBPROP2_MEAN     => '0.640552995391705',
        LBPROP2_MEDIAN   => '0.640552995391705',
        LBPROP2_MIN      => '0.571428571428571',
        LBPROP2_SD       => '0.0977566978598919',
        LBPROP2_SKEWNESS => undef,
        LBPROP2_SUM      => '1.28110599078341',
        LBPROP3_COUNT    => 2,
        LBPROP3_IQR      => 6,
        LBPROP3_KURTOSIS => undef,
        LBPROP3_MAX      => 9,
        LBPROP3_MEAN     => '6',
        LBPROP3_MEDIAN   => '6',
        LBPROP3_MIN      => '3',
        LBPROP3_SD       => '4.24264068711928',
        LBPROP3_SKEWNESS => undef,
        LBPROP3_SUM      => 12,
        LBPROP4_COUNT    => 2,
        LBPROP4_IQR      => 6,
        LBPROP4_KURTOSIS => undef,
        LBPROP4_MAX      => 9,
        LBPROP4_MEAN     => '6',
        LBPROP4_MEDIAN   => '6',
        LBPROP4_MIN      => '3',
        LBPROP4_SD       => '4.24264068711928',
        LBPROP4_SKEWNESS => undef,
        LBPROP4_SUM      => 12
    },
    LBPROP_STATS_LBPROP1_DATA => [ '0.571428571428571', '0.709677419354839' ],
    LBPROP_STATS_LBPROP1_HASH => {
        '0.571428571428571' => 1,
        '0.709677419354839' => 1
    },
    LBPROP_STATS_LBPROP2_DATA => [ '0.571428571428571', '0.709677419354839' ],
    LBPROP_STATS_LBPROP2_HASH => {
        '0.571428571428571' => 1,
        '0.709677419354839' => 1
    },
    LBPROP_STATS_LBPROP3_DATA => [ 3, 9 ],
    LBPROP_STATS_LBPROP3_HASH => {
        '3' => 1,
        '9' => 1
    },
    LBPROP_STATS_LBPROP4_DATA => [ 3, 9 ],
    LBPROP_STATS_LBPROP4_HASH => {
        '3' => 1,
        '9' => 1
    }
}


