#!/usr/bin/perl -w

#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use strict;
use warnings;
use 5.010;

use English qw { -no_match_vars };

use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

#use Test::More tests => 5;
use Test::Most;

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;
use Biodiverse::TestHelpers qw /:basedata/;

exit main( @ARGV );

sub main {
    my @args  = @_;

    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
                if not my $func = (__PACKAGE__->can( 'test_' . $name ) || __PACKAGE__->can( $name ));
            $func->();
        }
        done_testing;
        return 0;
    }

    test_export_shape();

    done_testing;
    return 0;
}


sub test_export_shape {
    my $bd = shift;
    $bd //= get_basedata_object_from_site_data(
        CELL_SIZES => [100000, 100000],
    );
    
    my $gp = $bd->get_groups_ref;

    my $fname = 'export_basestruct_' . int (rand() * 1000);
    
    say "Exporting to $fname";

    my $success = eval {
        $gp->export (
            format => 'Shapefile',
            file   => $fname,
        );
    };
    my $e = $EVAL_ERROR;
    ok (!$e, 'No exceptions in export to shapefile');
    
    
    
}
