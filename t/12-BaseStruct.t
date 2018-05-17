#!/usr/bin/perl -w

#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use strict;
use warnings;
use 5.010;

use English qw { -no_match_vars };

use Test::Lib;
use rlib;

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
    test_text_axis_name_coords();
    test_get_elements_that_pass_def_query();
    
    done_testing;
    return 0;
}

sub test_get_elements_that_pass_def_query {
    my $bd = get_basedata_object_from_site_data(
        CELL_SIZES => [100000, 100000],
        );

    my $groups = $bd->get_groups_ref;
    my @passed = 
        sort $groups->get_elements_that_pass_def_query( defq => '$x < 2000000' );

    my @expected = ('1950000:1350000', '1950000:1450000');
    
    is_deeply (
        \@passed,
        \@expected,
        "Simple def query produced the correct elements"
        );
}


sub test_export_shape {
    my $bd = shift;
    $bd //= get_basedata_object_from_site_data(
        CELL_SIZES => [100000, 100000],
    );

    my $gp = $bd->get_groups_ref;

    my $fname = get_temp_file_path('export_basestruct_' . int (1000 * rand()));
    note("Exporting to $fname");

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

    #  now check labels can also be exported
    #  (a test of text axes)
    my $lb = $bd->get_labels_ref;
    $fname = get_temp_file_path('export_basestruct_labels_' . int (1000 * rand()));
    note("Exporting to $fname");

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

    my $fname = get_temp_file_path('export_point_basestruct_' . int (1000 * rand()));
    note("Exporting to $fname");

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

sub test_text_axis_name_coords {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test_text_axis_name_coords',
        CELL_SIZES => [-1],
    );
    #  natural sort order
    my @gp_name_arr = qw /clasp class1 class2 class10 class11 class100 class100x class100y/;
    foreach my $gp_name (@gp_name_arr) {
        $bd->add_element (group => $gp_name, label => 'default_label');
    }
    
    my $gp = $bd->get_groups_ref;
    my %expected;
    @expected{reverse @gp_name_arr} = (0..$#gp_name_arr);

    foreach my $gp_name (@gp_name_arr) {
        my $coord = $gp->get_element_name_coord (element => $gp_name);
        is ($coord->[0], $expected{$gp_name}, "Got correct coord for $gp_name");
    }
    
}


sub test_numerically_keyed_list_stats {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test_text_axis_name_coords',
        CELL_SIZES => [-1],
    );
    #  natural sort order
    my $start_i = 0;
    my @gp_name_arr = qw /clasp class1 class2 class10 class11 class100 class100x class100y/;
    foreach my $gp_name (@gp_name_arr) {
        $bd->add_element (group => $gp_name, label => 'default_label');
        my $gps = $bd->get_groups_ref;
        for my $i (1..3) {
            my %hash;
            @hash{$start_i .. $start_i+100} = ($start_i .. $start_i+100);
            if ($gp_name eq 'class100x') {
                if ($i == 2) {
                    $hash{a} = undef;  #  add one non-numeric key to a single hash
                }
                elsif ($i == 1) {
                    $hash{1000} = undef;  #  one large key so we get different stats
                }
            }
            $gps->add_to_hash_list (
                element => $gp_name,
                list    => "hash$i",
                %hash,
            );
        }
    }
    
    my $gp = $bd->get_groups_ref;
    my %expected;
    
    my $stats = $gp->get_numerically_keyed_hash_stats_across_elements;
    #use Data::Dump;
    #dd $stats;
    my $expected = {
        hash1 => {
            MAX    => 1000,
            MEAN   => 59.3137254901961,
            MIN    => 0,
            PCT025 => 3,
            PCT05  => 5,
            PCT95  => 96,
            PCT975 => 98,
            SD     => 98.4786231406912,
        },
        hash3 => {
            MAX    => 100,
            MEAN   => 50,
            MIN    => 0,
            PCT025 => 3,
            PCT05  => 5,
            PCT95  => 95,
            PCT975 => 98,
            SD     => 29.3001706479672,
        },
    };

    is_deeply $stats, $expected, 'got matching stats for numeric keys';
    
}
