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
my $root = $tree_ref->get_root_node;
#  and add a multifurcating terminal
my @extras;
for my $i (1..5) {
    my $node = Biodiverse::TreeNode->new(
        name   => "extra:$i",
        length => 0.1,
    );
    $tree_ref->add_to_node_hash (node_ref => $node);
    push @extras, $node;
}
$root->add_children (children => \@extras);
$tree_ref->delete_cached_values;
$tree_ref->delete_cached_values_below;
$root->delete_cached_values;
$root->delete_cached_values_below;

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_nri_nti_expected_values
        calc_nri_nti1
        calc_nri_nti2
        calc_nri_nti3
    /],
    tree_ref             => $tree_ref,
    prng_seed            => 123456,
    generate_result_sets => 1,
    nri_nti_iterations   => 4999,
    #mpd_mntd_use_wts => 1,
);

done_testing;

1;


#  THESE RESULTS ARE FOR A 64 BIT PRNG - they will differ for a 32 bit PRNG
__DATA__


@@ RESULTS_2_NBR_LISTS
{   PHYLO_NRI1             => '0.769316981381632',
    PHYLO_NRI2             => '0.58434551363915',
    PHYLO_NRI3             => '0.38452693361695',
    PHYLO_NRI_NTI_SAMPLE_N => 2010,
    PHYLO_NRI_SAMPLE_MEAN  => '1.61084731106026',
    PHYLO_NRI_SAMPLE_SD    => '0.119469702986923',
    PHYLO_NTI1             => '1.21707869438799',
    PHYLO_NTI2             => '1.15900274662951',
    PHYLO_NTI3             => '1.78080973607196',
    PHYLO_NTI_SAMPLE_MEAN  => '0.916410198794455',
    PHYLO_NTI_SAMPLE_SD    => '0.142850600566172'
}


@@ RESULTS_1_NBR_LISTS
{   PHYLO_NRI1             => '-1.42680727216652',
    PHYLO_NRI2             => '-1.42680727216652',
    PHYLO_NRI3             => '-1.42680727216652',
    PHYLO_NRI_NTI_SAMPLE_N => 630,
    PHYLO_NRI_SAMPLE_MEAN  => '1.61322214321038',
    PHYLO_NRI_SAMPLE_SD    => '0.429786247359979',
    PHYLO_NTI1             => '-1.42680727216652',
    PHYLO_NTI2             => '-1.42680727216652',
    PHYLO_NTI3             => '-1.42680727216652',
    PHYLO_NTI_SAMPLE_MEAN  => '1.61322214321038',
    PHYLO_NTI_SAMPLE_SD    => '0.429786247359979'
}


