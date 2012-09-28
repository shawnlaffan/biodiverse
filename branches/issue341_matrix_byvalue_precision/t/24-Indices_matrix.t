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
        calc_compare_dissim_matrix_values
        calc_overlap_mx
        calc_matrix_stats
        calc_mx_rao_qe
    /],
    calc_topic_to_test => 'Matrix',
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'MXD_COUNT' => 26,
  'MXD_LIST1' => {
                   'Genus:sp20' => 1,
                   'Genus:sp26' => 1
                 },
  'MXD_LIST2' => {
                   'Genus:sp10' => 2,
                   'Genus:sp11' => 2,
                   'Genus:sp12' => 2,
                   'Genus:sp15' => 2,
                   'Genus:sp20' => 2,
                   'Genus:sp23' => 2,
                   'Genus:sp24' => 2,
                   'Genus:sp25' => 2,
                   'Genus:sp26' => 2,
                   'Genus:sp27' => 2,
                   'Genus:sp29' => 2,
                   'Genus:sp30' => 2,
                   'Genus:sp5'  => 2
                 },
  'MXD_MEAN'     => '0.0473457692307692',
  'MXD_VARIANCE' => '0.00253374386538462',
  'MXO_LABELS'   => {
                    'Genus:sp10' => 2,
                    'Genus:sp11' => 2,
                    'Genus:sp20' => 2,
                    'Genus:sp24' => 2,
                    'Genus:sp25' => 2,
                    'Genus:sp26' => 1,
                    'Genus:sp29' => 2,
                    'Genus:sp30' => 2
                  },
  'MXO_MEAN'    => '0.0512613333333333',
  'MXO_M_RATIO' => '1.12102637799785',
  'MXO_N'       => 15,
  'MXO_TLABELS' => {
                     'Genus:sp10' => 13,
                     'Genus:sp11' => 12,
                     'Genus:sp12' => 2,
                     'Genus:sp15' => 3,
                     'Genus:sp20' => 7,
                     'Genus:sp23' => 4,
                     'Genus:sp24' => 9,
                     'Genus:sp25' => 11,
                     'Genus:sp26' => 6,
                     'Genus:sp27' => 1,
                     'Genus:sp29' => 8,
                     'Genus:sp30' => 10,
                     'Genus:sp5'  => 5
                   },
  'MXO_TMEAN'     => '0.0457271428571428',
  'MXO_TN'        => 91,
  'MXO_TVARIANCE' => '0.00227831727582418',
  'MXO_VARIANCE'  => '0.00267703065333333',
  'MXO_V_RATIO'   => '1.17500344738637',
  'MXO_Z_RATIO'   => '1.03418030161322',
  'MXO_Z_SCORE'   => '0.115943658756715',
  'MX_KURT'       => '0.271825741525032',
  'MX_LABELS'     => {
                   'Genus:sp10' => 1,
                   'Genus:sp11' => 1,
                   'Genus:sp12' => 1,
                   'Genus:sp15' => 1,
                   'Genus:sp20' => 1,
                   'Genus:sp23' => 1,
                   'Genus:sp24' => 1,
                   'Genus:sp25' => 1,
                   'Genus:sp26' => 1,
                   'Genus:sp27' => 1,
                   'Genus:sp29' => 1,
                   'Genus:sp30' => 1,
                   'Genus:sp5'  => 1
                 },
  'MX_MAXVALUE'    => '0.07301',
  'MX_MEAN'        => '0.0457271428571428',
  'MX_MEDIAN'      => '0.04642',
  'MX_MINVALUE'    => '0.00794',
  'MX_N'           => 91,
  'MX_PCT05'       => '0.01828',
  'MX_PCT25'       => '0.04046',
  'MX_PCT75'       => '0.05669',
  'MX_PCT95'       => '0.06481',
  'MX_RANGE'       => '0.06507',
  'MX_RAO_QE'      => '0.0492446153846154',
  'MX_RAO_TLABELS' => {
                        'Genus:sp10' => '0.0769230769230769',
                        'Genus:sp11' => '0.0769230769230769',
                        'Genus:sp12' => '0.0769230769230769',
                        'Genus:sp15' => '0.0769230769230769',
                        'Genus:sp20' => '0.0769230769230769',
                        'Genus:sp23' => '0.0769230769230769',
                        'Genus:sp24' => '0.0769230769230769',
                        'Genus:sp25' => '0.0769230769230769',
                        'Genus:sp26' => '0.0769230769230769',
                        'Genus:sp27' => '0.0769230769230769',
                        'Genus:sp29' => '0.0769230769230769',
                        'Genus:sp30' => '0.0769230769230769',
                        'Genus:sp5'  => '0.0769230769230769'
                      },
  'MX_RAO_TN' => 169,
  'MX_SD'     => '0.0137632590847852',
  'MX_SKEW'   => '-0.694760452738312',
  'MX_VALUES' => 91
}

@@ RESULTS_1_NBR_LISTS
{
  'MXO_LABELS'  => {},
  'MXO_MEAN'    => undef,
  'MXO_M_RATIO' => '0',
  'MXO_N'       => 0,
  'MXO_TLABELS' => {
                     'Genus:sp20' => 2,
                     'Genus:sp26' => 1
                   },
  'MXO_TMEAN'     => '0.05565',
  'MXO_TN'        => 3,
  'MXO_TVARIANCE' => '0.00313230136666667',
  'MXO_VARIANCE'  => undef,
  'MXO_V_RATIO'   => '0',
  'MXO_Z_RATIO'   => undef,
  'MXO_Z_SCORE'   => '-0.994336538788726',
  'MX_KURT'       => undef,
  'MX_LABELS'     => {
                   'Genus:sp20' => 1,
                   'Genus:sp26' => 1
                 },
  'MX_MAXVALUE'    => '0.06402',
  'MX_MEAN'        => '0.05565',
  'MX_MEDIAN'      => '0.05219',
  'MX_MINVALUE'    => '0.05074',
  'MX_N'           => 3,
  'MX_PCT05'       => '0.05074',
  'MX_PCT25'       => '0.05219',
  'MX_PCT75'       => '0.06402',
  'MX_PCT95'       => '0.06402',
  'MX_RANGE'       => '0.01328',
  'MX_RAO_QE'      => '0.083475',
  'MX_RAO_TLABELS' => {
                        'Genus:sp20' => '0.5',
                        'Genus:sp26' => '0.5'
                      },
  'MX_RAO_TN' => '4',
  'MX_SD'     => '0.00728479924225778',
  'MX_SKEW'   => '1.65517073625658',
  'MX_VALUES' => 3
}
