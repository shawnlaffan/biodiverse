#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use rlib;
use Test::Most;

use Biodiverse::TestHelpers qw{
    :runners
};

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_rarity_central
        calc_rarity_central_lists
        calc_rarity_whole
        calc_rarity_whole_lists
    /],
    calc_topic_to_test => 'Rarity',
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'RAREC_CWE'       => '0.622119815668203',
  'RAREC_RANGELIST' => {
                         'Genus:sp20' => 31,
                         'Genus:sp26' => 7
                       },
  'RAREC_RICHNESS' => 2,
  'RAREC_WE'       => '1.24423963133641',
  'RAREC_WTLIST'   => {
                      'Genus:sp20' => '0.387096774193548',
                      'Genus:sp26' => '0.857142857142857'
                    },
  'RAREW_CWE'       => '0.151831533482874',
  'RAREW_RANGELIST' => {
                         'Genus:sp1'  => 64,
                         'Genus:sp10' => 153,
                         'Genus:sp11' => 328,
                         'Genus:sp12' => 151,
                         'Genus:sp15' => 54,
                         'Genus:sp20' => 31,
                         'Genus:sp23' => 174,
                         'Genus:sp24' => 23,
                         'Genus:sp25' => 9,
                         'Genus:sp26' => 7,
                         'Genus:sp27' => 36,
                         'Genus:sp29' => 53,
                         'Genus:sp30' => 103,
                         'Genus:sp5'  => 38
                       },
  'RAREW_RICHNESS' => 14,
  'RAREW_WE'       => '2.12564146876023',
  'RAREW_WTLIST'   => {
                      'Genus:sp1'  => '0.125',
                      'Genus:sp10' => '0.104575163398693',
                      'Genus:sp11' => '0.0274390243902439',
                      'Genus:sp12' => '0.0529801324503311',
                      'Genus:sp15' => '0.203703703703704',
                      'Genus:sp20' => '0.387096774193548',
                      'Genus:sp23' => '0.0114942528735632',
                      'Genus:sp24' => '0.0869565217391304',
                      'Genus:sp25' => '0.111111111111111',
                      'Genus:sp26' => '0.857142857142857',
                      'Genus:sp27' => '0.0277777777777778',
                      'Genus:sp29' => '0.0943396226415094',
                      'Genus:sp30' => '0.00970873786407767',
                      'Genus:sp5'  => '0.0263157894736842'
                    }
}

@@ RESULTS_1_NBR_LISTS
{
  'RAREC_CWE'       => '0.207373271889401',
  'RAREC_RANGELIST' => {
                         'Genus:sp20' => 31,
                         'Genus:sp26' => 7
                       },
  'RAREC_RICHNESS' => 2,
  'RAREC_WE'       => '0.414746543778802',
  'RAREC_WTLIST'   => {
                      'Genus:sp20' => '0.129032258064516',
                      'Genus:sp26' => '0.285714285714286'
                    },
  'RAREW_CWE'       => '0.207373271889401',
  'RAREW_RANGELIST' => {
                         'Genus:sp20' => 31,
                         'Genus:sp26' => 7
                       },
  'RAREW_RICHNESS' => 2,
  'RAREW_WE'       => '0.414746543778802',
  'RAREW_WTLIST'   => {
                      'Genus:sp20' => '0.129032258064516',
                      'Genus:sp26' => '0.285714285714286'
                    }
}
