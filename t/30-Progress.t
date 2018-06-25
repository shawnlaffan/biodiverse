#!/usr/bin/perl -w
use strict;
use warnings;
use English qw / -no_match_vars /;

use FindBin qw/$Bin/;
use Test::Lib;
use rlib;

#  don't test plugins
BEGIN {
    $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;
}

use Test::More tests => 2;
use Test::NoWarnings;

local $| = 1;

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

