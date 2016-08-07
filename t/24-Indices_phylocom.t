#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;
use Test::Most;

use Biodiverse::TestHelpers qw{
    :runners
};

#  need to add a skip for this
note 'THE NRI/NTI RESULTS ARE FOR A 64 BIT PRNG - they will differ for a 32 bit PRNG';

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_phylo_mpd_mntd3
        calc_phylo_mpd_mntd2
        calc_phylo_mpd_mntd1
        calc_nri_nti_expected_values
        calc_nri_nti1
        calc_nri_nti2
        calc_nri_nti3
    /],
    prng_seed            => 123456,
    nri_nti_iterations   => 4999,
    calc_topic_to_test => 'PhyloCom Indices',
    #generate_result_sets => 1,
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   PHYLO_NRI1             => '-4.96393636727162',
    PHYLO_NRI2             => '-5.72006739158669',
    PHYLO_NRI3             => '-6.53689081540097',
    PHYLO_NRI_NTI_SAMPLE_N => 1724,
    PHYLO_NRI_SAMPLE_MEAN  => '1.84783208015162',
    PHYLO_NRI_SAMPLE_SD    => '0.0292257368123035',
    PHYLO_NTI1             => '-1.9179336216108',
    PHYLO_NTI2             => '-1.97749295018477',
    PHYLO_NTI3             => '-1.33980371353548',
    PHYLO_NTI_SAMPLE_MEAN  => '1.35742491318549',
    PHYLO_NTI_SAMPLE_SD    => '0.139292772675336',
    PMPD1_MAX              => '1.95985532713474',
    PMPD1_MEAN             => '1.70275738232872',
    PMPD1_MIN              => '0.5',
    PMPD1_N                => 182,
    PMPD1_RMSD             => '1.72778602112414',
    PMPD2_MAX              => '1.95985532713474',
    PMPD2_MEAN             => '1.68065889601647',
    PMPD2_MIN              => '0.5',
    PMPD2_N                => 440,
    PMPD2_RMSD             => '1.70251249614779',
    PMPD3_MAX              => '1.95985532713474',
    PMPD3_MEAN             => '1.65678662960995',
    PMPD3_MIN              => '0.5',
    PMPD3_N                => 6086,
    PMPD3_RMSD             => '1.67120620763302',
    PNTD1_MAX              => '1.86377675442101',
    PNTD1_MEAN             => '1.09027062122407',
    PNTD1_MIN              => '0.5',
    PNTD1_N                => 14,
    PNTD1_RMSD             => '1.14674277360116',
    PNTD2_MAX              => '1.86377675442101',
    PNTD2_MEAN             => '1.08197443720832',
    PNTD2_MIN              => '0.5',
    PNTD2_N                => 22,
    PNTD2_RMSD             => '1.12013655961468',
    PNTD3_MAX              => '1.86377675442101',
    PNTD3_MEAN             => '1.17079993908642',
    PNTD3_MIN              => '0.5',
    PNTD3_N                => 83,
    PNTD3_RMSD             => '1.19931244035734'
}


@@ RESULTS_1_NBR_LISTS
{   PHYLO_NRI1             => '-3.59966099911513',
    PHYLO_NRI2             => '-3.59966099911513',
    PHYLO_NRI3             => '-3.59966099911513',
    PHYLO_NRI_NTI_SAMPLE_N => 465,
    PHYLO_NRI_SAMPLE_MEAN  => '1.84720584828667',
    PHYLO_NRI_SAMPLE_SD    => '0.235357120710793',
    PHYLO_NTI1             => '-3.59966099911513',
    PHYLO_NTI2             => '-3.59966099911513',
    PHYLO_NTI3             => '-3.59966099911513',
    PHYLO_NTI_SAMPLE_MEAN  => '1.84720584828667',
    PHYLO_NTI_SAMPLE_SD    => '0.235357120710793',
    PMPD1_MAX              => '1',
    PMPD1_MEAN             => '1',
    PMPD1_MIN              => '1',
    PMPD1_N                => 2,
    PMPD1_RMSD             => '1',
    PMPD2_MAX              => 1,
    PMPD2_MEAN             => '1',
    PMPD2_MIN              => 1,
    PMPD2_N                => 2,
    PMPD2_RMSD             => '1',
    PMPD3_MAX              => 1,
    PMPD3_MEAN             => '1',
    PMPD3_MIN              => 1,
    PMPD3_N                => 16,
    PMPD3_RMSD             => '1',
    PNTD1_MAX              => '1',
    PNTD1_MEAN             => '1',
    PNTD1_MIN              => '1',
    PNTD1_N                => 2,
    PNTD1_RMSD             => '1',
    PNTD2_MAX              => 1,
    PNTD2_MEAN             => '1',
    PNTD2_MIN              => 1,
    PNTD2_N                => 2,
    PNTD2_RMSD             => '1',
    PNTD3_MAX              => 1,
    PNTD3_MEAN             => '1',
    PNTD3_MIN              => 1,
    PNTD3_N                => 6,
    PNTD3_RMSD             => '1'
}


