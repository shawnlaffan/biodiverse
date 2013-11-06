#!perl

use strict;
use warnings;
use Test::More;

#my $run_plan = $ENV{AUTHOR_TESTS};
#if (!$run_plan) {
#    plan skip_all => "Skipping POD tests - they are for development";
#}

# Ensure a recent version of Test::Pod
my $min_tp = 1.22;
eval "use Test::Pod $min_tp";
if ($@) {
    plan skip_all => "Test::Pod $min_tp required for testing POD";
}

all_pod_files_ok();
