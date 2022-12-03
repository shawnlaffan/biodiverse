use strict;
use warnings;
use Test::CheckManifest;
use Test::More;

plan skip_all => q{We don't have a manufest yet, and need to move the gtk stuff out of the way or add to the ignore list};

TODO: {
    local $TODO = q{We don't have a manufest yet, and need to move the gtk stuff out of the way or add to the ignore list};
    ok_manifest();
};
