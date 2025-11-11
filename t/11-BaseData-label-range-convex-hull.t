#!/usr/bin/perl
use strict;
use warnings;

#  Tests for basedata re-ordering of label axes

use strict;
use warnings;
use 5.010;

use English qw { -no_match_vars };
use Carp;
use rlib;
use Biodiverse::TestHelpers qw /:basedata/;
use Biodiverse::BaseData;
use Geo::GDAL::FFI qw/GetDriver/;
use Test::TempDir::Tiny;


local $| = 1;

use Test2::V0;


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

    test_label_range_convex_hull();

    done_testing;
    return 0;
}


sub test_label_range_convex_hull {
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);

    #  a range of sizes, including a single cell
    my @target_labels = qw /Genus:sp28 Genus:sp21 Genus:sp4/;

    my @expected = (
        'POLYGON ((2600000 600000,2600000 800000,2800000 800000,2800000 600000,2600000 600000))',
        'POLYGON ((3000000 0,2000000 1000000,2000000 1200000,2200000 1400000,2600000 1400000,3600000 1200000,3600000 600000,3400000 200000,3200000 0,3000000 0))',
        'POLYGON ((3400000 1800000,3400000 2400000,3600000 2400000,3800000 2000000,3800000 1800000,3400000 1800000))',
    );

    # second pass uses cached version
    for my $cached (0, 1) {
        my $i = -1;
        foreach my $label (@target_labels) {
            $i++;
            my $hull = $bd->get_label_range_convex_hull(label => $label, as_wkt => 1);
            is $hull, $expected[$i], "convex hull for $label, " . ($cached ? '' : 'not ') . 'cached';
        }
    }

}
