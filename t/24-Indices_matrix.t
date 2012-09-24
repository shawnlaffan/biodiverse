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

ok(0, 'Needs real data');

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
}

@@ RESULTS_1_NBR_LISTS
{
}
