#!/usr/bin/perl -w

#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use strict;
use warnings;
use English qw { -no_match_vars };

use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

#use Test::More tests => 5;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;
use Biodiverse::TestHelpers qw /:basedata/;

#  need to automate this, and extend the testing
EXCLUSIONS:
{
    my $bd = eval {
            get_basedata_object (
                x_spacing  => 1,
                y_spacing  => 1,
                CELL_SIZES => [1, 1],
                x_max      => 100,
                y_max      => 100,
                x_min      => 0,
                y_min      => 0,
            );
        };

    my $bd2 = $bd->clone;
    #print $bd2->describe;
    my $exclusion_hash = {
        GROUPS => {
            definition_query => '$x < 10 && $y < 10',
        },
    };
    my $tally = eval {
        $bd2->run_exclusions (exclusion_hash => $exclusion_hash);
    };
    is ($tally->{GROUPS_count}, 100, 'Deleted 100 groups using def query');
    is ($tally->{LABELS_count}, 100, 'Deleted 100 labels using def query');
    
}

done_testing();


1;
