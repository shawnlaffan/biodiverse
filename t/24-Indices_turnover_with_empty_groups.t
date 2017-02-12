#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;
use rlib;
use Test::Most;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
    :tree
    :utils
};

my $cb = sub {
    my %args = @_;
    my $bd   = $args{basedata_ref};
    my $el_list1 = $args{element_list1};
    #  add a new group which contains no labels
    $bd->add_element (
        group => '0:0',
    );
};

run_indices_test1 (
    element_list1  => ['3350000:850000', '0:0'],
    callbacks      => [$cb],
    calcs_to_test  => [qw/
        calc_beta_diversity
        calc_bray_curtis
        calc_jaccard
        calc_nestedness_resultant
        calc_s2
        calc_sorenson
        calc_phylo_sorenson
        calc_phylo_jaccard
        calc_phylo_s2
    /],
    #generate_result_sets => 1,
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   BC_A             => 6,
    BC_B             => 77,
    BC_W             => 6,
    BETA_2           => 0,
    BRAY_CURTIS      => '0.855421686746988',
    JACCARD          => '0.857142857142857',
    NEST_RESULTANT   => '0.75',
    PHYLO_JACCARD    => '0.84379791173084',
    PHYLO_S2         => 0,
    PHYLO_SORENSON   => '0.729801407809261',
    S2               => 0,
    SORENSON         => '0.75'
}


@@ RESULTS_1_NBR_LISTS
{}
