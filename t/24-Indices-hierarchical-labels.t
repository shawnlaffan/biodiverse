use strict;
use warnings;

local $| = 1;

use rlib;
use Test2::V0;

use Biodiverse::TestHelpers qw{
    :runners
};

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_hierarchical_label_ratios
    /],
    calc_topic_to_test => 'Hierarchical Labels',
);

#ok(0, 'Is this enough data for this test?');
#  Yes, for now.
#  We could later expand to using more levels in the hierarchy though.

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'HIER_A' => {'0' => 2, '1' => 2},
  'HIER_ARAT' => {1 => '1'},
  'HIER_ASUM' => {'0' => 18, '1' => 18},
  'HIER_ASUMRAT' => {1 => 0},
  'HIER_B' => {'0' => 0, '1' => 0},
  'HIER_BRAT' => {1 => undef},
  'HIER_C' => {'0' => 12, '1' => 12},
  'HIER_CRAT' => {'1' => '1'}
}

@@ RESULTS_1_NBR_LISTS
{
}
