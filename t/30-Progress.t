use strict;
use warnings;
use English qw / -no_match_vars /;

use FindBin qw/$Bin/;
use rlib;

#  don't test plugins
BEGIN {
    $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;
}

use Test2::V0;

local $| = 1;


use Biodiverse::TestHelpers qw //;
use Biodiverse::Progress;

{
    my $progress = Biodiverse::Progress->new();
    my $success = (defined $progress) ? 1 : 0;
    is ($success, 1, "created progress object");

    my $max = 100;
    for my $i (1 .. $max) {
        $progress->update ('stuff' , $i / $max);
    }
    $progress->close_off;
}

done_testing();