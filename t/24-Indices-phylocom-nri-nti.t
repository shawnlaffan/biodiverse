use strict;
use warnings;

local $| = 1;

use rlib;
use Test2::V0;

use Biodiverse::Config;

use Biodiverse::TestHelpers qw{
    :runners :tree :basedata
};

#  used to be a subset of the other phylocom test,
#  but now it is for the non-ultrametric tree case

#modify one of the branch lengths so we are not ultrametric
my $tree_ref = get_tree_object_from_sample_data();
my $node = $tree_ref->get_node_ref_aa('Genus:sp19');
$node->set_length_aa (0.2);
my $root = $tree_ref->get_root_node;
my $tree_ref_ultrametric1 = $tree_ref->clone;  #  need this later
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
#  now add a redundant parent to root
my $redundant_parent = Biodiverse::TreeNode->new(
    name   => "redundant",
    length => 0.1,
);
$tree_ref->add_to_node_hash (node_ref => $redundant_parent);
$redundant_parent->add_children (children => [$root]);
$tree_ref->delete_cached_values;
$tree_ref->delete_cached_values_below;
$root->delete_cached_values;
$root->delete_cached_values_below;
$redundant_parent->delete_cached_values;
$redundant_parent->delete_cached_values_below;

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_nri_nti_expected_values
        calc_nri_nti1
        calc_nri_nti2
        calc_nri_nti3
        calc_net_vpd
        calc_vpd_expected_values
    /],
    tree_ref             => $tree_ref,
    prng_seed            => 123456,
    generate_result_sets => 0,
    nri_nti_iterations   => 4999,
    #mpd_mntd_use_wts => 1,
);

my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000,200000]);
my $overlay1 = {
    PHYLO_NTI_SAMPLE_SD    => 0,
    PHYLO_NTI_SAMPLE_MEAN  => 0.969045196864471,
    PHYLO_NRI_NTI_SAMPLE_N => 0,
    PHYLO_NRI_SAMPLE_MEAN  => 1.82139939667377,
    PHYLO_NRI_SAMPLE_SD    => 0,
};

my %expected_results = (
    1 => $overlay1,
    2 => $overlay1,
);

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_nri_nti_expected_values
    /],
    basedata_ref         => $bd,
    tree_ref             => $tree_ref_ultrametric1,
    prng_seed            => 123456,
    #generate_result_sets => 1,
    nri_nti_iterations   => 4999,
    element_list1        => [$bd->get_groups],
    expected_results     => \%expected_results,
    #mpd_mntd_use_wts => 1,
);


do {
    my $sp1 = $bd->add_spatial_output(name => 'NTI_max_N1');
    my $sp2 = $bd->add_spatial_output(name => 'NTI_max_N2');
    my $tree2 = $tree_ref_ultrametric1->clone;
    $tree2->delete_cached_values;
    $tree2->delete_cached_values_below;
    #srand 1234;
    #  modify the tree
    foreach my $node (sort {$a->get_name cmp $b->get_name} $tree2->get_node_refs) {
        my $len = $node->get_length;
        #$node->set_length_aa (rand() * 10);
        $node->set_length_aa(1);

        #diag $node->get_name . " $len " . $node->get_length;
    }
    #  add some single child parents to the root so we test such danglers
    my $root1 = $tree2->get_root_node;
    my $dangler1 = $tree2->add_node(name => 'dangletop1', length => 1);
    my $dangler2 = $tree2->add_node(name => 'dangletop2', length => 1);
    $dangler2->add_children(children => [ $dangler1 ]);
    $dangler1->add_children(children => [ $root1 ]);

    my $rooter = $tree2->get_root_node->get_name;

    $sp1->run_analysis(
        spatial_conditions => [ 'sp_select_all()' ],
        calculations       => [ 'calc_nri_nti1' ],
        tree_ref           => $tree2,
    );
    local $ENV{BD_NO_NTI_MAX_N_SHORTCUT} = 1;
    $sp2->run_analysis(
        spatial_conditions => [ 'sp_select_all()' ],
        calculations       => [ 'calc_nri_nti1' ],
        tree_ref           => $tree2,
    );
    my @groups = sort $bd->get_groups;
    my $tgt_gp = $groups[0];
    my $set1 = $sp1->get_list_ref(
        element => $tgt_gp,
        list    => 'SPATIAL_RESULTS',
    );
    my $set2 = $sp2->get_list_ref(
        element => $tgt_gp,
        list    => 'SPATIAL_RESULTS',
    );
    is $set1, $set2, 'get same NTI expectation with and without shortcut';
};

do {
    $bd->delete_all_outputs;
    my $spx1 = $bd->add_spatial_output (name => 'Just an NRI/NTI run');
    my $spx2 = $bd->add_spatial_output (name => 'VPD after NRI/NTI');
    my $spy = $bd->add_spatial_output (name => 'VPD clean tree');
    my $spz = $bd->add_spatial_output (name => 'NRI, NTI and VPD clean tree');

    my $treex = $tree_ref_ultrametric1->clone;
    $treex->delete_all_cached_values;
    my $treey = $tree_ref_ultrametric1->clone;
    $treey->delete_all_cached_values;
    my $treez = $tree_ref_ultrametric1->clone;
    $treez->delete_cached_values;

    # faster running on single group
    my $tgt_gp = '3300000:900000';  #  arbitrary group in nbr set
    my %sp_cond = (
        spatial_conditions => ["sp_select_element (element => '$tgt_gp')"]
    );

    $spx1->run_analysis(
        %sp_cond,
        calculations       => [ 'calc_nri_nti1' ],
        tree_ref           => $treex,
    );
    $spx2->run_analysis(
        %sp_cond,
        calculations       => [ 'calc_net_vpd', 'calc_vpd_expected_values' ],
        tree_ref           => $treex,
    );
    $spy->run_analysis(
        %sp_cond,
        calculations       => [ 'calc_net_vpd', 'calc_vpd_expected_values' ],
        tree_ref           => $treey,
    );
    $spz->run_analysis(
        %sp_cond,
        calculations       => [ 'calc_net_vpd', 'calc_vpd_expected_values', 'calc_nri_nti1' ],
        tree_ref           => $treez,
    );
    my $results_x2 = $spx2->get_list_ref(
        element => $tgt_gp,
        list    => 'SPATIAL_RESULTS',
    );
    ok $results_x2->{PHYLO_NET_VPD}, 'Net VPD is not false when tree used for NRI/NTI beforehand'
      or diag join ' ', map {"$_ => " . ($results_x2->{$_} // 'undef')} sort keys %$results_x2;

    my $results_y = $spy->get_list_ref(
        element => $tgt_gp,
        list    => 'SPATIAL_RESULTS',
    );
    ok $results_y->{PHYLO_NET_VPD}, 'Net VPD is not false when tree not used for NRI/NTI beforehand'
      or diag join ' ', map {"$_ => " . ($results_y->{$_} // 'undef')} sort keys %$results_y;
# $bd->save (filename => 'bb.bds');

    is $results_x2, $results_y, 'results with previous NRI/NTI same as clean tree';
    # $treex->dump_to_yaml (data => $treex, filename => 'treex.yml');
    # $treey->dump_to_yaml (data => $treey, filename => 'treey.yml');
    # $treez->dump_to_yaml (data => $treez, filename => 'treez.yml');
};


done_testing;

1;


#  THESE RESULTS ARE FOR A 64 BIT PRNG - they will differ for a 32 bit PRNG
__DATA__


@@ RESULTS_2_NBR_LISTS
{   PHYLO_NRI1             => '0.759172357411792',
    PHYLO_NRI2             => '0.571798535505455',
    PHYLO_NRI3             => '0.369384771460602',
    PHYLO_NRI_NTI_SAMPLE_N => 2016,
    PHYLO_NRI_SAMPLE_MEAN  => '1.61322214321037',
    PHYLO_NRI_SAMPLE_SD    => '0.117937959995799',
    PHYLO_NTI1             => '1.21944984997561',
    PHYLO_NTI2             => '1.16129313030261',
    PHYLO_NTI3             => '1.78396492768937',
    PHYLO_NTI_SAMPLE_MEAN  => '0.916313417133818',
    PHYLO_NTI_SAMPLE_SD    => '0.142652200165291',
    PHYLO_NET_VPD_SAMPLE_MEAN  => '0.172035887951395',
    PHYLO_NET_VPD_SAMPLE_N     => 2016,
    PHYLO_NET_VPD_SAMPLE_SD    => '0.0539733870966747',
    PHYLO_NET_VPD              => '-1.59660271237015'
}


@@ RESULTS_1_NBR_LISTS
{   PHYLO_NRI1             => '-1.4268072721664',
    PHYLO_NRI2             => '-1.4268072721664',
    PHYLO_NRI3             => '-1.4268072721664',
    PHYLO_NRI_NTI_SAMPLE_N => 630,
    PHYLO_NRI_SAMPLE_MEAN  => '1.61322214321037',
    PHYLO_NRI_SAMPLE_SD    => '0.42978624736001',
    PHYLO_NTI1             => '-1.42680727216652',
    PHYLO_NTI2             => '-1.42680727216652',
    PHYLO_NTI3             => '-1.42680727216652',
    PHYLO_NTI_SAMPLE_MEAN  => '1.61322214321038',
    PHYLO_NTI_SAMPLE_SD    => '0.429786247359979',
    PHYLO_NET_VPD_SAMPLE_MEAN  => undef,
    PHYLO_NET_VPD_SAMPLE_N     => 0,
    PHYLO_NET_VPD_SAMPLE_SD    => undef,
    PHYLO_NET_VPD              => undef
}


