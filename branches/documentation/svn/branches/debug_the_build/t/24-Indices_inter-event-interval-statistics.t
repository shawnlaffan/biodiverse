#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use rlib;
use Test::More;

use Biodiverse::TestHelpers qw{
    :runners
};

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_iei_stats
        calc_iei_data
    /],
    calc_topic_to_test => 'Inter-event Interval Statistics',
    use_numeric_labels => 1,
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'IEI_CV'         => '5.75933438764195',
  'IEI_DATA_ARRAY' => 45236,
  'IEI_DATA_HASH'  => {
                       '0'  => 40613,
                       '1'  => 4135,
                       '10' => 1,
                       '11' => 7,
                       '12' => 4,
                       '13' => 2,
                       '14' => 5,
                       '16' => 1,
                       '18' => 1,
                       '2'  => 255,
                       '20' => 1,
                       '21' => 1,
                       '22' => 1,
                       '23' => 1,
                       '25' => 1,
                       '27' => 1,
                       '3'  => 89,
                       '4'  => 40,
                       '5'  => 21,
                       '51' => 1,
                       '6'  => 22,
                       '62' => 1,
                       '7'  => 16,
                       '75' => 1,
                       '8'  => 9,
                       '9'  => 6
                     },
  'IEI_GMEAN' => '0',
  'IEI_KURT'  => '3272.882339710666',
  'IEI_MAX'   => 75,
  'IEI_MEAN'  => '0.135688389778053',
  'IEI_MIN'   => 0,
  'IEI_N'     => 45236,
  'IEI_RANGE' => 75,
  'IEI_SD'    => '0.781474809252504',
  'IEI_SKEW'  => '43.31859090127'
}

@@ RESULTS_1_NBR_LISTS
{
  'IEI_CV'         => '6.07892414811224',
  'IEI_DATA_ARRAY' => 9999,
  'IEI_DATA_HASH'  => {
                       '0'  => 8955,
                       '1'  => 947,
                       '10' => 1,
                       '11' => 1,
                       '12' => 2,
                       '2'  => 62,
                       '22' => 1,
                       '3'  => 16,
                       '4'  => 8,
                       '5'  => 1,
                       '6'  => 2,
                       '62' => 1,
                       '9'  => 2
                     },
  'IEI_GMEAN' => '0',
  'IEI_KURT'  => '3662.833178991929',
  'IEI_MAX'   => 62,
  'IEI_MEAN'  => '0.131513151315132',
  'IEI_MIN'   => 0,
  'IEI_N'     => 9999,
  'IEI_RANGE' => 62,
  'IEI_SD'    => '0.799458471323892',
  'IEI_SKEW'  => '50.243330792007'
}
