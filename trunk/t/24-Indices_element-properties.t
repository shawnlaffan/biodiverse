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
        calc_gpprop_gistar
        calc_gpprop_lists
        calc_gpprop_hashes
        calc_gpprop_quantiles
        calc_gpprop_stats
        calc_lbprop_gistar
        calc_lbprop_data
        calc_lbprop_hashes
        calc_lbprop_quantiles
        calc_lbprop_stats
    /],
    calc_topic_to_test => 'Element Properties',
);

ok(0, 'This test needs real data!!!');

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'GPPROP_GISTAR_LIST' => {},
  'GPPROP_QUANTILES'   => {},
  'GPPROP_STATS'       => {},
  'LBPROP_GISTAR_LIST' => {},
  'LBPROP_QUANTILES'   => {},
  'LBPROP_STATS'       => {}
}

@@ RESULTS_1_NBR_LISTS
{
  'GPPROP_GISTAR_LIST' => {},
  'GPPROP_QUANTILES'   => {},
  'GPPROP_STATS'       => {},
  'LBPROP_GISTAR_LIST' => {},
  'LBPROP_QUANTILES'   => {},
  'LBPROP_STATS'       => {}
}
