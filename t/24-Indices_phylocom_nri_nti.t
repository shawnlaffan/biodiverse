#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use rlib;
use Test2::V0;

use Biodiverse::Config;

use Biodiverse::TestHelpers qw{
    :runners :tree
};

#  used to be a subset of the other phylocom test,
#  but now it is for the non-ultrametric tree case

#modify one of the branch lengths so we are not ultrametric
my $tree_ref = get_tree_object_from_sample_data();
my $node = $tree_ref->get_node_ref_aa('Genus:sp19');
$node->set_length_aa (0.2);
$tree_ref->delete_cached_values;
$tree_ref->delete_cached_values_below;

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_nri_nti_expected_values
        calc_nri_nti1
        calc_nri_nti2
        calc_nri_nti3
    /],
    tree_ref             => $tree_ref,
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
{   PHYLO_NRI1             => '-2.74640922043675',
    PHYLO_NRI2             => '-3.26056040943863',
    PHYLO_NRI3             => '-3.81598099271535',
    PHYLO_NRI_NTI_SAMPLE_N => 1308,
    PHYLO_NRI_SAMPLE_MEAN  => '1.82079948329804',
    PHYLO_NRI_SAMPLE_SD    => '0.0429805216538531',
    PHYLO_NTI1             => '-1.11767420070112',
    PHYLO_NTI2             => '-1.17081436997999',
    PHYLO_NTI3             => '-0.601853725288063',
    PHYLO_NTI_SAMPLE_MEAN  => '1.26476067205568',
    PHYLO_NTI_SAMPLE_SD    => '0.156118885738034'
}


@@ RESULTS_1_NBR_LISTS
{   PHYLO_NRI1             => '-3.16192872377052',
    PHYLO_NRI2             => '-3.16192872377052',
    PHYLO_NRI3             => '-3.16192872377052',
    PHYLO_NRI_NTI_SAMPLE_N => 465,
    PHYLO_NRI_SAMPLE_MEAN  => '1.82139939667377',
    PHYLO_NRI_SAMPLE_SD    => '0.259777960995362',
    PHYLO_NTI1             => '-3.16192872377052',
    PHYLO_NTI2             => '-3.16192872377052',
    PHYLO_NTI3             => '-3.16192872377052',
    PHYLO_NTI_SAMPLE_MEAN  => '1.82139939667377',
    PHYLO_NTI_SAMPLE_SD    => '0.259777960995362'
}


