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
        calc_beta_diversity
        calc_bray_curtis
        calc_bray_curtis_norm_by_gp_counts
        calc_jaccard
        calc_nestedness_resultant
        calc_tx_rao_qe
        calc_s2
        calc_simpson_shannon
        calc_sorenson
        calc_kulczynski2
        calc_rw_turnover
    /],
    calc_topic_to_test => 'Taxonomic Dissimilarity and Comparison',
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   BCN_A            => 6,
    BCN_B            => '19.25',
    BCN_W            => 3,
    BC_A             => 6,
    BC_B             => 77,
    BC_W             => 6,
    BETA_2           => 0,
    BRAY_CURTIS      => '0.855421686746988',
    BRAY_CURTIS_NORM => '0.762376237623762',
    JACCARD          => '0.857142857142857',
    KULCZYNSKI2      => '0.428571428571429',
    NEST_RESULTANT   => '0.75',
    S2               => 0,
    SHANNON_E        => '0.874674324962136',
    SHANNON_H        => '2.3083156883176',
    SHANNON_HMAX     => '2.63905732961526',
    SIMPSON_D        => '0.883437363913485',
    SORENSON         => '0.75',
    TX_RAO_QE        => '0.883437363913485',
    TX_RAO_TLABELS   => {
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
    TX_RAO_TN => 196,
    RW_TURNOVER   => '0.552184906870684',
    RW_TURNOVER_A => '1.11111111111111',
    RW_TURNOVER_B => 0,
    RW_TURNOVER_C => '1.37007169884446'
}


@@ RESULTS_1_NBR_LISTS
{   SHANNON_E      => '0.918295834054489',
    SHANNON_H      => '0.636514168294813',
    SHANNON_HMAX   => '0.693147180559945',
    SIMPSON_D      => '0.444444444444444',
    TX_RAO_QE      => '0.444444444444444',
    TX_RAO_TLABELS => {
        'Genus:sp20' => '0.666666666666667',
        'Genus:sp26' => '0.333333333333333'
    },
    TX_RAO_TN => '4'
}


