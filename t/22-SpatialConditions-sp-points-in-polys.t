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

use Biodiverse::TestHelpers qw {get_basedata_object_from_site_data};
use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;

# BEGIN {$ENV{PERL_TEST_TEMPDIR_TINY_NOCLEANUP} = 1}

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__);
my @subs = grep {$_ =~ 'main::test_'} $obj->functions();

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

    foreach my $sub (@subs) {
        no strict 'refs';
        $sub->();
    }

    done_testing;
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

    my $bounds = [[0, 0, 2, 2.4], [2, 0, 5, 2.4], [0, 2.4, 4, 3.4], [4, 3.4, 10, 10]];
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


sub test_sp_in_label_range_convex_hull {
    my $bd = get_basedata_object_from_site_data (
        CELL_SIZES => [100000, 100000],
    );

    my $cond = <<~'EOC'
    $self->set_current_label('Genus:sp4');
    sp_in_label_range_convex_hull();
    EOC
    ;

    my $sp = $bd->add_spatial_output (name => 'test_1');
    $sp->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_self_only()'],
        definition_query   => $cond,
    );

    is (!!$sp->group_passed_def_query_aa('3550000:1950000'), !!1, 'Loc is in convex hull');
    is (!!$sp->group_passed_def_query_aa('2650000:850000'),  !!0, 'Loc is not in convex hull');
}

sub test_sp_in_label_range_circumcircle {
    my $bd = get_basedata_object_from_site_data (
        CELL_SIZES => [100000, 100000],
    );

    my $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range_circumcircle();
        EOC
    ;

    my $sp = $bd->add_spatial_output (name => 'test_1');
    $sp->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_self_only()'],
        definition_query   => $cond,
    );

    is (!!$sp->group_passed_def_query_aa('3550000:1950000'), !!1, 'Loc is in circumcircle');
    is (!!$sp->group_passed_def_query_aa('2650000:850000'),  !!0, 'Loc is not in circumcircle');
}


sub test_welzl_alg {
    use Biodiverse::Geometry::Circle;

    my $class = 'Biodiverse::Geometry::Circle';

    my $test_points = [[5, -2], [-3, -2], [-2, 5], [1, 6], [0, 2], [28,-33.2]];
    my $mec = $class->get_circumcircle($test_points);
    is ($mec->centre, [13, -14.1], 'got expected centroid');
    is ($mec->radius, 24.2860041999502, 'got expected radius');

    pop @$test_points;
    $mec = $class->get_circumcircle($test_points);
    is ($mec->centre, [1, 1], 'got expected centroid for subset');
    is ($mec->radius, 5,      'got expected radius for subset');

}

sub test_sp_volatile {
    my $bd = get_basedata_object_from_site_data (
        CELL_SIZES => [100000, 100000],
    );

    #  should not be volatile
    my $sp_cond = Biodiverse::SpatialConditions->new (
        conditions   => 'sp_in_label_range_circumcircle(label => "a")',
        basedata_ref => $bd,
    );

    $sp_cond->set_current_label ('a');
    my $res = $sp_cond->verify;
    is $res->{ret}, 'ok', 'Non-volatile condition verified';
    is !!$sp_cond->is_volatile, !!0, 'Non-volatile condition flagged as such';

    #  should be volatile
    $sp_cond = Biodiverse::SpatialConditions->new (
        conditions            => 'sp_in_label_range_circumcircle()',
        basedata_ref          => $bd,
        promise_current_label => 1,
    );

    $sp_cond->set_current_label ('a');
    is $sp_cond->get_current_label, 'a', 'Current label correct';
    $res = $sp_cond->verify;
    is $res->{ret}, 'ok', 'Volatile condition verified';
    is !!$sp_cond->is_volatile, !!1, 'Volatile condition flagged as such';

    $sp_cond->set_current_label ();
    is $sp_cond->get_current_label, undef, 'Current label undef';
    $sp_cond->set_promise_current_label(1);
    $res = $sp_cond->verify;
    is $res->{ret}, 'ok', 'Volatile condition verified';
    is !!$sp_cond->is_volatile, !!1, 'Volatile condition flagged as such';

}