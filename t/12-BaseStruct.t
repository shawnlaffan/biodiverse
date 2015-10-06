#!/usr/bin/perl -w

#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use strict;
use warnings;
use 5.010;

use English qw { -no_match_vars };

use Test::Lib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

use Test::Most;

use Scalar::Util qw /looks_like_number/;

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
    test_export_shape_point();
    test_export_shape_3d();

    done_testing;
    return 0;
}


sub test_export_shape {
    my $bd = shift;
    $bd //= get_basedata_object_from_site_data(
        CELL_SIZES => [100000, 100000],
    );

    my $gp = $bd->get_groups_ref;

    my $tmp_folder = File::Temp->newdir (TEMPLATE => 'biodiverseXXXX', TMPDIR => 1);
    my $fname = $tmp_folder. '/export_basestruct_' . int (rand() * 1000);

    say "Exporting to $fname";

    my $success = eval {
        $gp->export (
            format => 'Shapefile',
            file   => $fname,
        );
    };
    my $e = $EVAL_ERROR;
    ok (!$e, 'No exceptions in export to shapefile');
    diag $e if $e;

    my $subtest_success =
      subtest 'polygon shapefile matches basestruct'
        => sub {subtest_for_polygon_shapefile_export ($gp, $fname)};

    #if ($subtest_success) {
    #    unlink $fname . '.shp', $fname . '.shx', $fname . '.dbf';
    #}

    #  now check labels can also be exported
    #  (a test of text axes)
    my $lb = $bd->get_labels_ref;
    $fname = $tmp_folder . '/export_basestruct_labels_' . int (rand() * 1000);

    say "Exporting to $fname";

    $success = eval {
        $lb->export (
            format => 'Shapefile',
            file   => $fname,
        );
    };
    $e = $EVAL_ERROR;
    ok (!$e, 'No exceptions in export labels to shapefile');
    diag $e if $e;

    $subtest_success =
      subtest 'polygon shapefile matches label basestruct'
        => sub {subtest_for_polygon_shapefile_export ($lb, $fname)};

    #if ($subtest_success) {
    #    unlink $fname . '.shp', $fname . '.shx', $fname . '.dbf';
    #}

}

sub subtest_for_polygon_shapefile_export {
    my ($basestruct, $fname) = @_;

    use Geo::ShapeFile;
    my $shapefile = Geo::ShapeFile->new($fname);

    my $shape_count  = $shapefile->shapes;
    my %element_hash = $basestruct->get_element_hash;
    
    my $cell_sizes = $basestruct->get_param ('CELL_SIZES');
    my @expected_axes;
    for my $i (0 .. $#$cell_sizes) {
        push @expected_axes, 'AXIS_' . $i;
    }

    is ($shape_count, $basestruct->get_element_count, 'correct number of shapes');

    for my $i (1 .. $shape_count) {
        my $shape = $shapefile->get_shp_record($i);

        my %db = $shapefile->get_dbf_record($i);
        my $element_name = $db{ELEMENT};

        ok (exists $element_hash{$element_name}, "$element_name exists");

        if ($i == 1) {
            foreach my $expected_axis_name (@expected_axes) {
                ok (exists $db{$expected_axis_name}, "Field $expected_axis_name exists");
            }
        }
        my @el_name_array = $basestruct->get_element_name_as_array (element => $element_name);
        my $i = 0;
        foreach my $expected_axis_name (@expected_axes) {
            my $db_axis_val = $db{$expected_axis_name};
            if (looks_like_number $db_axis_val) {
                $db_axis_val += 0;
            }

            is (
                $db_axis_val,
                $el_name_array[$i],
                "$expected_axis_name matches, $element_name",
            );
            $i ++;
        }

        my $centroid = $shape->area_centroid;
        my @el_coord_array = $basestruct->get_element_name_coord (element => $element_name);
        my @centroid_coords = @$centroid{qw /X Y/};
        is_deeply (\@centroid_coords, [@el_coord_array[0,1]], "Centroid matches for $element_name");
    }

    return;
}


# want the attribute table to match, as the polygons will be 2d
sub test_export_shape_3d {
    my $bd //= get_basedata_object_from_site_data (
        CELL_SIZES    => [100000, 100000, 100],
        group_columns => [3, 4, 0],
    );

    return test_export_shape ($bd);
}


sub test_export_shape_point {
    my $bd = shift;
    $bd //= get_basedata_object_from_site_data(
        CELL_SIZES => [0, 0],
    );

    my $gp = $bd->get_groups_ref;

    my $tmp_folder = File::Temp->newdir (TEMPLATE => 'biodiverseXXXX', TMPDIR => 1);
    my $fname = $tmp_folder . '/export_point_basestruct_' . int (rand() * 1000);

    say "Exporting to $fname";

    my $success = eval {
        $gp->export (
            format => 'Shapefile',
            file   => $fname,
            shapetype => 'point',
        );
    };
    my $e = $EVAL_ERROR;
    ok (!$e, 'No exceptions in export to point shapefile');
    diag $e if $e;

    my $subtest_success = subtest 'point shapefile matches basestruct' => sub {
        use Geo::ShapeFile;
        my $shapefile = Geo::ShapeFile->new ($fname);

        my $shape_count = $shapefile->shapes;
        my %element_hash = $gp->get_element_hash;

        is ($shape_count, $gp->get_element_count, 'correct number of shapes');

        for my $i (1 .. $shape_count) {
            my $shape = $shapefile->get_shp_record($i);
    
            my %db = $shapefile->get_dbf_record($i);
            my $element_name = $db{ELEMENT};

            ok (exists $element_hash{$element_name}, "$element_name exists");

            my $el_array = $gp->get_element_name_coord (element => $element_name);
            my $el_point = Geo::ShapeFile::Point->new (X => $el_array->[0], Y => $el_array->[1]);
            my $shape_points = $shape->points;
            my $shp_pnt = $shape_points->[0];

            is ($shp_pnt->distance_from ($el_point), 0, "Point coord matches for $element_name");
        }
    };

    #if ($subtest_success) {
    #    unlink $fname . '.shp', $fname . '.shx', $fname . '.dbf';
    #}

}
