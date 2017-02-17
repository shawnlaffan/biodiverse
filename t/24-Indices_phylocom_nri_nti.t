#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;
use rlib;
use Test::More;
use Biodiverse::Config;

use Biodiverse::TestHelpers qw{
    :runners
};

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_nri_nti_expected_values
        calc_nri_nti1
        calc_nri_nti2
        calc_nri_nti3
    /],
    prng_seed            => 123456,
    #generate_result_sets => 1,
    nri_nti_iterations   => 4999,
    #mpd_mntd_use_wts => 1,
);

done_testing;

1;


#  THESE RESULTS ARE FOR A 64 BIT PRNG - they will differ for a 32 bit PRNG
__DATA__


@@ RESULTS_2_NBR_LISTS
{   PHYLO_NRI1            => '-4.96393636727162',
    PHYLO_NRI2            => '-5.72006739158669',
    PHYLO_NRI3            => '-6.53689081540097',
    PHYLO_NRI_NTI_SAMPLE_N => 1724,
    PHYLO_NRI_SAMPLE_MEAN => '1.84783208015162',
    PHYLO_NRI_SAMPLE_SD   => '0.0292257368123035',
    PHYLO_NTI1            => '-1.9179336216108',
    PHYLO_NTI2            => '-1.97749295018477',
    PHYLO_NTI3            => '-1.33980371353548',
    PHYLO_NTI_SAMPLE_MEAN => '1.35742491318549',
    PHYLO_NTI_SAMPLE_SD   => '0.139292772675336'
}


@@ RESULTS_1_NBR_LISTS
{   PHYLO_NRI1            => '-3.59966099911513',
    PHYLO_NRI2            => '-3.59966099911513',
    PHYLO_NRI3            => '-3.59966099911513',
    PHYLO_NRI_NTI_SAMPLE_N => 465,
    PHYLO_NRI_SAMPLE_MEAN => '1.84720584828667',
    PHYLO_NRI_SAMPLE_SD   => '0.235357120710793',
    PHYLO_NTI1            => '-3.59966099911513',
    PHYLO_NTI2            => '-3.59966099911513',
    PHYLO_NTI3            => '-3.59966099911513',
    PHYLO_NTI_SAMPLE_MEAN => '1.84720584828667',
    PHYLO_NTI_SAMPLE_SD   => '0.235357120710793'
}

