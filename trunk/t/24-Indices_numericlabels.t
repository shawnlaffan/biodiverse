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
        calc_numeric_label_data
        calc_numeric_label_dissimilarity
        calc_numeric_label_other_means
        calc_numeric_label_quantiles
        calc_numeric_label_stats
        calc_num_labels_gistar
    /],
    calc_topic_to_test => 'Numeric Labels',
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
