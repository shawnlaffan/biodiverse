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
        calc_iei_stats
        calc_iei_data
    /],
    calc_topic_to_test => 'Inter-event Interval Statistics',
);

ok(0, 'Test needs real data');

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
}

@@ RESULTS_1_NBR_LISTS
{
}
