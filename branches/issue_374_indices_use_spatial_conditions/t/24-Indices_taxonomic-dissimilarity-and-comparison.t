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
        calc_beta_diversity
        calc_bray_curtis
        calc_bray_curtis_norm_by_gp_counts
        calc_jaccard
        calc_nestedness_resultant
        calc_tx_rao_qe
        calc_s2
        calc_simpson_shannon
        calc_sorenson
        calc_overlap_tx
    /],
    calc_topic_to_test => 'Taxonomic Dissimilarity and Comparison',
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'BCN_A'            => 6,
  'BCN_B'            => '19.25',
  'BCN_W'            => 3,
  'BC_A'             => 6,
  'BC_B'             => 77,
  'BC_W'             => 6,
  'BETA_2'           => 0,
  'BRAY_CURTIS'      => '0.855421686746988',
  'BRAY_CURTIS_NORM' => '0.762376237623762',
  'JACCARD'          => '0.857142857142857',
  'NEST_RESULTANT'   => '0.75',
  'S2'               => 0,
  'SHANNON_E'        => '0.874674324962136',
  'SHANNON_H'        => '2.3083156883176',
  'SHANNON_HMAX'     => '2.63905732961526',
  'SIMPSON_D'        => '0.883437363913485',
  'SORENSON'         => '0.75',
  'TXO_LABELS'       => {
                    'Genus:sp1'  => 2,
                    'Genus:sp10' => 2,
                    'Genus:sp11' => 2,
                    'Genus:sp20' => 2,
                    'Genus:sp24' => 2,
                    'Genus:sp25' => 2,
                    'Genus:sp26' => 1,
                    'Genus:sp29' => 2,
                    'Genus:sp30' => 2
                  },
  'TXO_MEAN'    => '0.882352941176471',
  'TXO_M_RATIO' => '1.01809954751131',
  'TXO_N'       => 17,
  'TXO_TLABELS' => {
                     'Genus:sp1'  => 14,
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
  'TXO_TMEAN'      => '0.866666666666667',
  'TXO_TN'         => 105,
  'TXO_TVARIANCE'  => '0.866666666666667',
  'TXO_VARIANCE'   => '0.882352941176471',
  'TXO_V_RATIO'    => '1.01809954751131',
  'TXO_Z_RATIO'    => '1.00900919099447',
  'TXO_Z_SCORE'    => '0.0168497617421042',
  'TX_RAO_QE'      => '0.883437363913485',
  'TX_RAO_TLABELS' => {
                        'Genus:sp1'  => '0.0963855421686747',
                        'Genus:sp10' => '0.192771084337349',
                        'Genus:sp11' => '0.108433734939759',
                        'Genus:sp12' => '0.0963855421686747',
                        'Genus:sp15' => '0.132530120481928',
                        'Genus:sp20' => '0.144578313253012',
                        'Genus:sp23' => '0.0240963855421687',
                        'Genus:sp24' => '0.0240963855421687',
                        'Genus:sp25' => '0.0120481927710843',
                        'Genus:sp26' => '0.072289156626506',
                        'Genus:sp27' => '0.0120481927710843',
                        'Genus:sp29' => '0.0602409638554217',
                        'Genus:sp30' => '0.0120481927710843',
                        'Genus:sp5'  => '0.0120481927710843'
                      },
  'TX_RAO_TN' => 196
}

@@ RESULTS_1_NBR_LISTS
{
  'SHANNON_E'    => '0.918295834054489',
  'SHANNON_H'    => '0.636514168294813',
  'SHANNON_HMAX' => '0.693147180559945',
  'SIMPSON_D'    => '0.444444444444444',
  'TXO_LABELS'   => {},
  'TXO_MEAN'     => undef,
  'TXO_M_RATIO'  => '0',
  'TXO_N'        => 0,
  'TXO_TLABELS'  => {
                     'Genus:sp20' => 2,
                     'Genus:sp26' => 1
                   },
  'TXO_TMEAN'      => '0.333333333333333',
  'TXO_TN'         => 3,
  'TXO_TVARIANCE'  => '0.333333333333333',
  'TXO_VARIANCE'   => undef,
  'TXO_V_RATIO'    => '0',
  'TXO_Z_RATIO'    => undef,
  'TXO_Z_SCORE'    => '-0.577350269189626',
  'TX_RAO_QE'      => '0.444444444444444',
  'TX_RAO_TLABELS' => {
                        'Genus:sp20' => '0.666666666666667',
                        'Genus:sp26' => '0.333333333333333'
                      },
  'TX_RAO_TN' => '4'
}
