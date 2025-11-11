use strict;
use warnings;
use 5.036;

use Carp;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;

use rlib;
use Test2::V0;

use Geo::GDAL::FFI;
use Path::Tiny qw /path/;
use Test::TempDir::Tiny qw /tempdir/;

local $| = 1;

use Biodiverse::TestHelpers qw {:spatial_conditions};
use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;

BEGIN {$ENV{PERL_TEST_TEMPDIR_TINY_NOCLEANUP} = 1}


exit main( @ARGV );

sub main {
    my @args  = @_;

    test_points_in_same_poly();

    done_testing();
    return 0;
}

sub _create_polygon_file {
    my ($type, $bounds, $file) = @_;

    state %drivers = (
        shp  => 'ESRI Shapefile',
        gpkg => 'GPKG',
        gdb  => 'OpenFileGDB',
    );
    state %extensions = (
        shp  => 'shp',
        gpkg => 'gpkg',
        gdb  => 'gdb',
    );

    my $driver = $drivers{$type} // croak "invalid type $type";
    $file //= (path (tempdir(), 'sp_points_in_poly_shape_tester') . time() . '.' . $extensions{$type});
diag $file;
    my $layer = Geo::GDAL::FFI::GetDriver($driver)
        ->Create($file)
        ->CreateLayer({
        Name => 'for_testing_' . time(),
        GeometryType => 'Polygon',
        Fields => [],
    });

    foreach my $b (@$bounds) {
        my $x1 = $b->[0] + 0.5;
        my $x2 = $b->[2] + 0.5;
        my $y1 = $b->[1] + 0.5;
        my $y2 = $b->[3] + 0.5;

        my $wkt = "POLYGON (($x1 $y1, $x1 $y2, $x2 $y2, $x2 $y1, $x1 $y1))";

        my $f = Geo::GDAL::FFI::Feature->new($layer->GetDefn);
        my $g = Geo::GDAL::FFI::Geometry->new(WKT => $wkt);
        $f->SetGeomField($g);
        $layer->CreateFeature($f);
    }

    return $file;
}


sub test_points_in_same_poly {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test_points_in_same_poly_shape',
        CELL_SIZES => [1,1],
    );
    my %all_gps;
    foreach my $i (1..5) {
        foreach my $j (1..5) {
            my $gp = "$i:$j";
            foreach my $k (1..$i) {
                #  fully nested
                $bd->add_element (label => "$k", group => $gp);
            }
            $all_gps{$gp}++;
        }
    }

    my $bounds = [[0, 0, 2, 2], [2, 0, 5, 2], [0, 2, 4, 3], [4, 3, 10, 10]];
    my $polygon_file = _create_polygon_file('shp', $bounds);

    my %expected_nbrs = (
        "1:1" => [ qw/1:1 1:2 2:1 2:2/ ],
        "1:3" => [ qw/1:3 2:3 3:3 4:3/ ],
        "3:1" => [ qw/3:1 3:2 4:1 4:2 5:1 5:2/ ],
        "1:4" => [ qw /1:4 1:5 2:4 2:5 3:4 3:5 4:4 4:5 5:3/ ],
    );

    my $sp_to_test1 = $bd->add_spatial_output (name => 'test_1');
    $sp_to_test1->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ["sp_points_in_same_poly_shape (file => '$polygon_file')"],
    );

    # $bd->save ();

    foreach my $el (keys %expected_nbrs) {
        my $list_ref = $sp_to_test1->get_list_ref (element => $el, list => '_NBR_SET1');
        is ([sort @$list_ref], $expected_nbrs{$el}, "sp_points_in_same_poly_shape correct nbrs for $el");
    }


}

