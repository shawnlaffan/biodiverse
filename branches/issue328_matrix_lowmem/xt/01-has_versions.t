
use strict;
use warnings;

use Test::More;

eval "use Test::HasVersion";

if ($@) {
    plan skip_all =>  'Test::HasVersion required for testing for version numbers';
}

all_pm_version_ok();

#done_testing ();
