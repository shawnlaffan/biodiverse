#!/usr/bin/perl
use strict;
use warnings;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;

use rlib;

use Test::More;

local $| = 1;

use Biodiverse::Statistics;


{
    my $stat = Biodiverse::Statistics->new();

    $stat->add_data(1 .. 9);

    my %pctls = (
        0   => 1,
        1   => 1,
        30  => 3,
        42  => 4,
        49  => 5,
        50  => 5,
        100 => 9,
    );

    while (my ($key, $val) = each %pctls) {
        is ($stat->percentile ($key),
            $val,
            "Percentile $key is $val",
        );
    }
}

{
    my $stat = Biodiverse::Statistics->new();

    $stat->add_data (1 .. 9);

    my %pctls = (
        0   => undef,
        30  => 3,
        42  => 4,
        49  => 5,
        50  => 5,
        100 => 9,
    );

    while (my ($key, $val) = each %pctls) {
        my $text = $val // 'undef';
        is ($stat->percentile_RFC2330 ($key),
            $val,
            "Percentile RFC2330 $key is $text",
        );
    }
}

#  check sd and stdev are same as standard_deviation
{
    my $stat = Biodiverse::Statistics->new();

    $stat->add_data (1 .. 100);

    foreach my $shortname (qw /sd stdev/) {
        is ($stat->standard_deviation, $stat->$shortname, "$shortname is same as standard_deviation");
    }
    
}


done_testing();
