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

use Biodiverse::TestHelpers qw {get_basedata_object_from_site_data get_tree_object_from_sample_data};
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
    $bd->rename(new_name => 'test_sp_in_label_range_convex_hull');

    my $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(convex_hull => 1);
        EOC
    ;

    my $exp = {
        map {; $_ => 1}
            qw /3550000:1950000 3550000:2050000 3550000:2150000
                3550000:2250000 3650000:1950000 3650000:2050000
                3750000:1950000 3750000:2050000
            /};

    my $sp = $bd->add_spatial_output(name => "test_xx");
    $sp->run_analysis(
        calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
        spatial_conditions => [ 'sp_self_only()' ],
        definition_query   => $cond,
    );

    is(!!$sp->group_passed_def_query_aa('3550000:1950000'), !!1, 'Loc is in convex hull');
    is(!!$sp->group_passed_def_query_aa('2650000:850000'), !!0, 'Loc is not in convex hull');

    my $passed = $sp->get_groups_that_pass_def_query();
    is $passed, $exp, "Expected def query passes";

    #  check vanilla still works
    my $cond3 = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range();
        EOC
    ;

    my $sp3 = $bd->add_spatial_output (name => 'test_3');
    $sp3->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_self_only()'],
        definition_query   => $cond3,
    );

    is (!!$sp3->group_passed_def_query_aa('3550000:1950000'), !!1, 'Loc is in convex hull');
    is (!!$sp3->group_passed_def_query_aa('2650000:850000'),  !!0, 'Loc is not in convex hull');

    my $passed3 = $sp3->get_groups_that_pass_def_query();
    isnt $passed3, $exp, 'Expected def query not same as normal range check';

    my $cond_b0 = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(convex_hull => 1, buffer_dist => 0);
        EOC
    ;

    my $sp4 = $bd->add_spatial_output (name => 'test_bd0');
    $sp4->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_self_only()'],
        definition_query   => $cond_b0,
    );

    my $passed4 = $sp4->get_groups_that_pass_def_query();
    is $passed4, $exp, 'Expected def query passes, buff_dist = 0';

    my $cond_bnegbig = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(convex_hull => 1, buffer_dist => -1e9);
        EOC
    ;

    my $sp5 = $bd->add_spatial_output (name => 'test_bnegbig');
    eval {
        $sp5->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ 'sp_self_only()' ],
            definition_query   => $cond_bnegbig,
        );
    };

    my $passed5 = $sp5->get_groups_that_pass_def_query();
    is $passed5, {}, 'Expected def query passes, buff_dist large negative';

    my $cond_buffered = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(convex_hull => 1, buffer_dist => 100000);
        EOC
    ;

    my @exp_buf_pos_arr = qw /
        3450000:2050000 3450000:2150000 3550000:1950000 3550000:2050000 3550000:2150000
        3550000:2250000 3650000:1850000 3650000:1950000 3650000:2050000 3650000:2350000
        3750000:1850000 3750000:1950000 3750000:2050000 3750000:2150000 3850000:1850000
        3850000:1950000
    /;

    my $exp_buff_pos = {};
    foreach my $gp (@exp_buf_pos_arr) {
        $exp_buff_pos->{$gp} = 1;
    }
    my $sp6 = $bd->add_spatial_output (name => 'test_buff_pos');
    eval {
        $sp6->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ 'sp_self_only()' ],
            definition_query   => $cond_buffered,
        );
    };

    my $passed6 = $sp6->get_groups_that_pass_def_query();
    is $passed6, $exp_buff_pos, 'Expected def query passes, convex_hull buff_dist positive';

    $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(convex_hull => 1, circumcircle => 1);
        EOC
    ;
    $sp = $bd->add_spatial_output(name => "test_circumcircle_and_convex_hull_args");
    eval {
        $sp->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ 'sp_self_only()' ],
            definition_query   => $cond,
        );
    };

    $passed = $sp->get_groups_that_pass_def_query();
    is $passed, $exp, 'Expected def query, convex_hull overrides circumcircle arg';
}


sub test_sp_in_label_range_concave_hull {
    my $bd = get_basedata_object_from_site_data (
        CELL_SIZES => [100000, 100000],
    );

    my $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(concave_hull => 1, hull_ratio => 0.3);
        EOC
    ;

    my $exp = { map {$_ => 1} qw/
        3550000:1950000 3550000:2050000 3550000:2150000
        3550000:2250000 3650000:1950000 3650000:2050000
        3750000:1950000
    / };

    my $sp = $bd->add_spatial_output(name => "test_1");
    $sp->run_analysis(
        calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
        spatial_conditions => [ 'sp_self_only()' ],
        definition_query   => $cond,
    );

    is(!!$sp->group_passed_def_query_aa('3550000:1950000'), !!1, 'Loc is in concave hull');
    is(!!$sp->group_passed_def_query_aa('2650000:850000'), !!0, 'Loc is not in concave hull');

    my $passed = $sp->get_groups_that_pass_def_query();
    is $passed, $exp, 'Expected def query not same as normal range check';

    #  check buffer of zero
    $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(concave_hull => 1, hull_ratio => 0.3, buffer_dist => 0);
        EOC
    ;

    $sp = $bd->add_spatial_output(name => "test_buff_dist_0");
    $sp->run_analysis(
        calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
        spatial_conditions => [ 'sp_self_only()' ],
        definition_query   => $cond,
    );

    $passed = $sp->get_groups_that_pass_def_query();
    is $passed, $exp, 'Expected def query not same as normal range check, buffer_dist = 0';

    #  check large neg buffer
    $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(concave_hull => 1, hull_ratio => 0.3, buffer_dist => -1e9);
        EOC
    ;

    $sp = $bd->add_spatial_output(name => "test_buff_dist_bigneg");
    eval {
        $sp->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ 'sp_self_only()' ],
            definition_query   => $cond,
        );
    };

    $passed = $sp->get_groups_that_pass_def_query();
    is $passed, {}, 'Expected def query, buffer_dist is big neg';

    #  check pos buffer
    $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(concave_hull => 1, hull_ratio => 0.3, buffer_dist => 100000);
        EOC
    ;

    $sp = $bd->add_spatial_output(name => "test_buff_dist");
    eval {
        $sp->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ 'sp_self_only()' ],
            definition_query   => $cond,
        );
    };

    my @exp_buf_pos_arr = qw /
        3450000:2050000 3450000:2150000 3550000:1950000 3550000:2050000 3550000:2150000
        3550000:2250000 3650000:1850000 3650000:1950000 3650000:2050000 3650000:2350000
        3750000:1850000 3750000:1950000 3750000:2050000 3850000:1850000 3850000:1950000
    /;

    my $exp_buf_pos = {map {$_ => 1} @exp_buf_pos_arr};

    $passed = $sp->get_groups_that_pass_def_query();
    is $passed, $exp_buf_pos, 'Expected def query, buffer_dist is positive';

    #  check maximally concave hull should be the same as the convex hull
    $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(concave_hull => 1, hull_ratio => 200000);
        EOC
    ;

    $sp = $bd->add_spatial_output(name => "test_max_concave_hull_ratio");
    eval {
        $sp->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ 'sp_self_only()' ],
            definition_query   => $cond,
        );
    };

    my $exp_convex_hull = {
        map {; $_ => 1}
            qw /3550000:1950000 3550000:2050000 3550000:2150000
                3550000:2250000 3650000:1950000 3650000:2050000
                3750000:1950000 3750000:2050000
            /};

    $passed = $sp->get_groups_that_pass_def_query();
    is $passed, $exp_convex_hull, 'Expected def query, concave_hull ratio is >1';
}

sub test_sp_in_label_range_circumcircle {
    my $bd = get_basedata_object_from_site_data (
        CELL_SIZES => [100000, 100000],
    );

    my $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(circumcircle => 1);
        EOC
    ;

    my $exp = { map {$_ => 1} qw/
        3450000:2050000 3450000:2150000 3550000:1950000
        3550000:2050000 3550000:2150000 3550000:2250000
        3650000:1850000 3650000:1950000 3650000:2050000
        3650000:2350000 3750000:1950000 3750000:2050000
        3750000:2150000 3850000:1950000
    / };

    my $sp = $bd->add_spatial_output(name => "test_1");
    $sp->run_analysis(
        calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
        spatial_conditions => [ 'sp_self_only()' ],
        definition_query   => $cond,
    );

    is(!!$sp->group_passed_def_query_aa('3550000:1950000'), !!1, 'Loc is in circumcircle');
    is(!!$sp->group_passed_def_query_aa('2650000:850000'), !!0, 'Loc is not in circumcircle');

    my $passed = $sp->get_groups_that_pass_def_query();
    is $passed, $exp, 'Expected def query not same as normal range check';

    #  check buffer of zero
    $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(circumcircle => 1, buffer_dist => 0);
        EOC
    ;

    $sp = $bd->add_spatial_output(name => "test_buff_dist_0");
    $sp->run_analysis(
        calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
        spatial_conditions => [ 'sp_self_only()' ],
        definition_query   => $cond,
    );

    $passed = $sp->get_groups_that_pass_def_query();
    is $passed, $exp, 'Expected def query not same as normal range check, buffer_dist = 0';

    #  check large neg buffer
    $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(circumcircle => 1, buffer_dist => -1e9);
        EOC
    ;

    $sp = $bd->add_spatial_output(name => "test_buff_dist_bigneg");
    eval {
        $sp->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ 'sp_self_only()' ],
            definition_query   => $cond,
        );
    };

    $passed = $sp->get_groups_that_pass_def_query();
    is $passed, {}, 'Expected def query, buffer_dist is big neg';

    #  check pos buffer
    $cond = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_range(circumcircle => 1, buffer_dist => 100000);
        EOC
    ;

    $sp = $bd->add_spatial_output(name => "test_buff_dist");
    eval {
        $sp->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ 'sp_self_only()' ],
            definition_query   => $cond,
        );
    };

    my @exp_buf_pos_arr = qw /
        3350000:2050000 3350000:2150000 3450000:2050000 3450000:2150000 3550000:1950000
        3550000:2050000 3550000:2150000 3550000:2250000 3650000:1750000 3650000:1850000
        3650000:1950000 3650000:2050000 3650000:2350000 3750000:1850000 3750000:1950000
        3750000:2050000 3750000:2150000 3850000:1850000 3850000:1950000
    /;

    my $exp_buf_pos = {map {$_ => 1} @exp_buf_pos_arr};

    $passed = $sp->get_groups_that_pass_def_query();
    is $passed, $exp_buf_pos, 'Expected def query, buffer_dist is positive';
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
        conditions   => 'sp_in_label_range(circumcircle => 1, label => "a")',
        basedata_ref => $bd,
    );

    $sp_cond->set_current_label ('a');
    my $res = $sp_cond->verify;
    is $res->{ret}, 'ok', 'Non-volatile condition verified';
    is !!$sp_cond->is_volatile, !!0, 'Non-volatile condition flagged as such';

    #  should be volatile
    $sp_cond = Biodiverse::SpatialConditions->new (
        conditions            => 'sp_in_label_range(circumcircle => 1)',
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

sub test_sp_in_tree_ancestor_range {
    my $bd = get_basedata_object_from_site_data (
        CELL_SIZES => [100000, 100000],
    );
    my $tree = get_tree_object_from_sample_data();
    my $target_node = $tree->get_node_ref_aa('57___');
    # my $desc = $target_node->get_all_descendants;
    # say STDERR "++++ " . scalar keys %$desc;
    # my $target_node = $tree->get_node_ref_aa('Genus:sp4')->get_ancestor_by_length_aa (0.97);
    # say STDERR '++++++' . $target_node->get_name;

    my %common_sp_args = (
        calculations       => [ 'calc_element_lists_used' ],
        spatial_conditions => [ 'sp_self_only()' ],
    );
    my %common_cond_args = (
        basedata_ref => $bd,
        tree_ref     => $tree,
        promise_current_label => 1,
    );

    my $exp = {
        map {; $_ => 1} qw /
            3150000:2950000 3250000:2150000 3250000:2850000
            3250000:2950000 3350000:2050000 3350000:2150000
            3450000:2050000 3450000:2150000 3550000:1950000
            3550000:2050000 3550000:2150000 3550000:2250000
            3650000:1650000 3650000:1750000 3650000:1850000
            3650000:1950000 3650000:2050000 3750000:1650000
            3750000:1750000 3750000:1950000 3750000:2050000
            3850000:1450000 3850000:1550000 3850000:1750000
            /};

    my $exp_convex_hull = { %$exp };
    $exp_convex_hull->{$_}++ foreach qw/
        3650000:2350000 3750000:1550000 3750000:1850000
        3750000:2150000 3850000:1650000 3850000:1850000
        3850000:1950000
    /;
    my $exp_circumcircle = { %$exp_convex_hull };
    $exp_circumcircle->{$_}++ foreach qw/
        3250000:3050000 3350000:1350000 3450000:1350000
        3450000:1450000 3450000:1550000 3550000:1450000
        3550000:1550000 3650000:1350000 3650000:1450000
        3650000:1550000 3750000:1350000 3750000:1450000
        3950000:1750000
    /;

    my $target_len_node = $tree->get_node_ref_aa('Genus:sp4')->get_ancestor_by_depth_aa(2);
    my $target_len_sum  = $target_len_node->get_sum_of_branch_lengths_below - 0.5 * $target_len_node->get_length;
    my $target_len_sumf = $target_len_sum / $tree->get_total_tree_length;
    #  these should all find the same node
    my @cond_args = (
        'by_depth => 1, target => 2',
        'by_depth => 1, target => 0.5, as_frac => 1',
        'by_depth => 0, target => 0.97',
        'target => 0.97, as_frac => 1',
        'target => 6, by_tip_count => 1',
        'target => 0.1935483870, by_tip_count => 1, as_frac => 1',  #  target = 6/31
        'target => 10, by_desc_count => 1',
        'target => 10/61, by_desc_count => 1, as_frac => 1',
        "target => $target_len_sum, by_len_sum => 1",
        "target => $target_len_sumf, by_len_sum => 1, as_frac => 1",
    );
    my $cond_base = <<~'EOC'
        $self->set_current_label('Genus:sp4');
        sp_in_label_ancestor_range(%{CONDITION}%);
        EOC
    ;

    foreach my $args (@cond_args) {
        my $cond = $cond_base =~ s/\Q%{CONDITION}%\E/$args/r;

        my $defq = Biodiverse::SpatialConditions::DefQuery->new(
            conditions => $cond,
            %common_cond_args,
        );
        my $sp = $bd->add_spatial_output(name => "test_ancestor_range_($args)");
        $sp->run_analysis(
            %common_sp_args,
            definition_query => $defq,
        );

        is ref $defq->get_tree_ref, ref $tree, 'Tree ref unchanged';

        my $passed = $sp->get_groups_that_pass_def_query();
        is $passed, $exp, "Expected def query passes (depth)";
    }

    {
        #  nothing should pass for not in tree
        my $cond = <<~'EOC'
            $self->set_current_label('somelabelnotintree');
            sp_in_label_ancestor_range(by_depth => 2, target => 2);
            EOC
        ;
        my $defq = Biodiverse::SpatialConditions::DefQuery->new(
            conditions => $cond,
            %common_cond_args,
        );
        my $spx = $bd->add_spatial_output(name => "test_xx_to_fail");
        eval {
            $spx->run_analysis(
                %common_sp_args,
                definition_query => $defq,
            );
        };
        is scalar $spx->get_groups_that_pass_def_query,
            {},
            "Nothing passes when label not in tree";
    }

    {
        #  Now the convex hull case.  We only need to check one of depth or length.
        my $cond = <<~'EOC'
            $self->set_current_label('Genus:sp4');
            sp_in_label_ancestor_range(by_depth => 2, target => 2, convex_hull => 1);
            EOC
        ;
        my $defq_depth_ch = Biodiverse::SpatialConditions::DefQuery->new(
            conditions => $cond,
            %common_cond_args,
        );
        my $sp_depth_ch = $bd->add_spatial_output(name => "test_ancestor_range_depth_ch");
        $sp_depth_ch->run_analysis(
            %common_sp_args,
            definition_query => $defq_depth_ch,
        );
        is scalar $sp_depth_ch->get_groups_that_pass_def_query(),
            $exp_convex_hull,
            "Expected def query passes";
    }

    {
        #  Now the circumcircle case.  As with the convex hull,
        #  we only need to check one of depth or length.
        my $cond = <<~'EOC'
            $self->set_current_label('Genus:sp4');
            sp_in_label_ancestor_range(by_depth => 2, target => 2, circumcircle => 1);
            EOC
        ;
        my $defq = Biodiverse::SpatialConditions::DefQuery->new(
            conditions => $cond,
            %common_cond_args,
        );
        my $sp_depth_cc = $bd->add_spatial_output(
            name => "test_ancestor_range_depth_cc"
        );
        $sp_depth_cc->run_analysis(
            %common_sp_args,
            definition_query => $defq,
        );
        is scalar $sp_depth_cc->get_groups_that_pass_def_query(),
            $exp_circumcircle,
            "Expected def query passes";
    }

    {
        #  terminals should be the same as a call to in_label_range
        my $cond = <<~'EOC'
            $self->set_current_label('Genus:sp4');
            sp_in_label_ancestor_range(target => 0);
            EOC
        ;
        my $defq_d0 = Biodiverse::SpatialConditions::DefQuery->new(
            conditions => $cond,
            %common_cond_args,
        );

        my $sp_d0 = $bd->add_spatial_output(name => "test_ancestor_range_length_d0");
        $sp_d0->run_analysis(
            %common_sp_args,
            definition_query => $defq_d0,
        );

        $cond = <<~'EOC'
            $self->set_current_label('Genus:sp4');
            sp_in_label_range();
            EOC
        ;
        my $defq_lr = Biodiverse::SpatialConditions::DefQuery->new(
            conditions => $cond,
            %common_cond_args,
        );

        my $sp_lr = $bd->add_spatial_output(name => "test_label_range");
        $sp_lr->run_analysis(
            %common_sp_args,
            definition_query => $defq_lr,
        );

        is scalar $sp_d0->get_groups_that_pass_def_query,
            scalar $sp_lr->get_groups_that_pass_def_query,
            'target => 0 is same as call to sp_in_label_range';
    }

}
