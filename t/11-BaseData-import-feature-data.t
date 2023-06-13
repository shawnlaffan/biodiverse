use 5.010;
use strict;
use warnings;

#  for yath
# HARNESS-DURATION-LONG

use English qw { -no_match_vars };
use Data::Dumper;
use Path::Class;
use Path::Tiny qw /path/;

use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

use Test2::V0;

use Biodiverse::TestHelpers qw /:basedata/;
use Biodiverse::BaseData;
use Biodiverse::ElementProperties;

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @test_subs = grep {$_ =~ 'main::test_'} $obj->functions();


exit main( @ARGV );

sub main {
    my @args  = @_;

    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
              if not my $func = (__PACKAGE__->can( 'test_' . $name )
                                 || __PACKAGE__->can( $name ));
            $func->();
        }
        done_testing;
        return 0;
    }

    foreach my $sub (sort @test_subs) {
        no strict 'refs';
        $sub->();
    }
    
    done_testing;
    return 0;
}


#can we reimport shapefiles after exporting and get the same answer
sub test_import_roundtrip_shapefile {
    use utf8;

    my %bd_args = (
        NAME => 'test include exclude',
        CELL_SIZES => [1,1],
    );

    my $fname = write_data_to_temp_file(get_import_data_small());
    note("testing filename $fname");
    my $e;

    #  get the original - should add some labels with special characters
    my $bd = Biodiverse::BaseData->new (%bd_args);
    ok (lives {
        $bd->import_data(
            input_files   => [$fname],
            group_columns => [3, 4],
            label_columns => [1, 2],
        )},
        'import vanilla with no exceptions raised'
    ) or note $@;
    
    # add some labels so we have multiple entries in some cells 
    # with different labels
    $bd->add_element (group => '1.5:1.5', label => 'bazungalah:smith', count => 25);
    $bd->add_element (group => '1.5:1.5', label => 'repeat:1', count => 14);
    $bd->add_element (group => '1.5:1.5', label => 'repeat:2', count => 12);

    my $lb = $bd->get_labels_ref;
    my $gp = $bd->get_groups_ref;

    #  export should return file names?  Or should we cache them on the object?

    my $format = 'export_shapefile';
    my @out_options = ( { data => $bd, shapetype => 'polygon' } );

    # assume export was in format labels_as_bands = 0
    my @cell_sizes   = @{$bd->get_param('CELL_SIZES')}; # probably not set anywhere, and is using the default
    my @cell_origins = @{$bd->get_cell_origins};    
    my @in_options = (
        {
            group_field_names => [':shape_x', ':shape_y'],
            label_field_names => ['KEY'],
            sample_count_col_names => ['VALUE'],
        },
    );

    my $tmp_dir = get_temp_file_path('');

    my $i = 0;
    foreach my $out_options_hash (@out_options) {
        #local $Data::Dumper::Sortkeys = 1;
        #local $Data::Dumper::Purity   = 1;
        #local $Data::Dumper::Terse    = 1;
        #say Dumper $out_options_hash;

        #  need to use a better approach for the name,
        #  but the unicode chars help test 
        my $fname_base = path($tmp_dir, 'shæþefile_' . $i)->stringify;

        my $suffix = ''; # leave off, .shp will be added (or similar)
        my $fname = $fname_base . $suffix;
        my @exported_files;
        my $success = eval {
            $gp->export (
                format    => $format,
                file      => $fname,
                list      => 'SUBELEMENTS',
                %$out_options_hash
            );
        };
        $e = $EVAL_ERROR;
        ok (!$e, "no exceptions exporting $format to $fname");
        diag $e if $e;
        ok (
            Biodiverse::Common->file_exists_aa ($fname . '.shp'),
            "$fname.shp exists",
        );

        #  Now we re-import and check we get the same numbers
        my $new_bd = Biodiverse::BaseData->new (
            name         => $fname,
            CELL_SIZES   => $bd->get_param ('CELL_SIZES'),
            CELL_ORIGINS => $bd->get_param ('CELL_ORIGINS'),
        );
        my $in_options_hash = $in_options[$i];

        use URI::Escape::XS qw/uri_unescape/;

        # import as shapefile
        $success = eval {
            $new_bd->import_data_shapefile (
                input_files => [$fname . '.shp'],
                %$in_options_hash,
            );
        };
        $e = $EVAL_ERROR;
        ok (!$e, "no exceptions importing $fname");
        diag $e if $e;
        if ($e) {
            diag "$fname:";
            foreach my $ext (qw /shp dbf shx/) {
                diag 'size: ' . Biodiverse::Common->get_file_size_aa ("${fname}.${ext}");
            }
        }

        my @new_labels  = sort $new_bd->get_labels;
        my @orig_labels = sort $bd->get_labels;
        is (\@new_labels, \@orig_labels, "label lists match for $fname");
        
        my @new_groups  = sort $new_bd->get_groups;
        my @orig_groups = sort $bd->get_groups;
        is (\@new_groups, \@orig_groups, "group lists match for $fname");
        

        my $new_lb = $new_bd->get_labels_ref;
        subtest "sample counts match for $fname" => sub {
            foreach my $label (sort $bd->get_labels) {
                my $new_list  = $new_lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                my $orig_list = $lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                
                #say "new list: " . join(',', keys %$new_list) . join(',', values %$new_list) if ($new_list);
                #say "orig list: " . join(',', keys %$orig_list) . join(',', values %$orig_list)if ($orig_list);
                is ($new_list, $orig_list, "SUBELEMENTS match for $label, $fname");
            }
        };

        $i++;
    }
    
}

sub _test_import_shapefile_polygon {
    my %args = @_;
    my $fname   = $args{fname};
    my $is_line = $args{is_line};
    my $sample_count_fields = $args{sample_count_fields};
    my $cell_sizes = $args{cell_sizes} || [100000,100000];

    use FindBin qw /$Bin/;
    $fname //= $Bin . '/data/polygon data.shp';

    my $in_options_hash = {
        group_field_names => [':shape_x', ':shape_y'],
        label_field_names => ['BINOMIAL'],
        binarise_counts   => $args{binarise_counts},
        sample_count_col_names => $sample_count_fields,
    };

    my $new_bd = Biodiverse::BaseData->new (
        NAME => 'test_import_shapefile feature data',
        CELL_SIZES => $cell_sizes,
    );
    # import as shapefile
    my $success = eval {
        $new_bd->import_data_shapefile (
            input_files => [$fname],
            %$in_options_hash,
        );
    };
    my $e = $EVAL_ERROR;
    ok (!$e, "no exceptions importing $fname");
    diag $e if $e;
    if ($e) {
        diag "$fname:";
        #foreach my $ext (qw /shp dbf shx/) {
        #    diag 'size: ' . -s ($fname . $ext);
        #}
    }

    my $info = ($args{binarise_counts} ? '(binarised)' : '');
    $info .= $args{is_line} ? '(polyline)' : '';

    my @new_labels  = sort $new_bd->get_labels;
    my @orig_labels = ('Dromornis_planei');
    is (\@new_labels, \@orig_labels, "label lists match for $fname");

    my @new_groups  = sort $new_bd->get_groups;
    my $exp_gp = $args{expected_gp_count} // ($is_line ? 140 : 240);
    is (scalar @new_groups, $exp_gp, "got expected number of groups $orig_labels[0] in $fname, $info");
    
    
    my $new_lb = $new_bd->get_labels_ref;
    my $got = $new_bd->get_label_sample_count (label => $orig_labels[0]);
    my $exp = $args{expected_total_count};
    if (defined $exp) {
        is (int $got, int $exp, "total sample counts match for $orig_labels[0] in $fname, $info");
        #if ($got ne $exp) {
            #$new_bd->save_to (filename => './failure2.bds');
        #}
        
    }
    else {
        $exp //= $is_line #  dodgy and fragile type check
            ? 15338541  
            : 1794988604045;  #  prob too precise
    
        ok (
            ($got - $exp) <= 1,
            "total sample counts $got within tolerance from $exp for $orig_labels[0] in $fname, $info",
        );
    }    
}

sub test_import_shapefile_polygon_default {
    use FindBin qw /$Bin/;
    my $fname = $Bin . '/data/polygon data.shp';
    _test_import_shapefile_polygon (
        fname   => $fname,
        expected_total_count => 261,
    );
}

sub test_import_shapefile_polygon_area {
    use FindBin qw /$Bin/;
    my $fname = $Bin . '/data/polygon data.shp';
    _test_import_shapefile_polygon (
        fname   => $fname,
        sample_count_fields => [':shape_area'],
    );
}

#  trigger the hierarchical fishnet
sub test_import_shapefile_polygon_area_hierarchical {
    use FindBin qw /$Bin/;
    my $fname = $Bin . '/data/polygon data.shp';
    _test_import_shapefile_polygon (
        fname   => $fname,
        sample_count_fields => [':shape_area'],
        cell_sizes => [10000, 12000],
        expected_gp_count => 14886,
    );
}

sub test_import_shapefile_polygon_binarised {
    use FindBin qw /$Bin/;
    my $fname = $Bin . '/data/polygon data.shp';
    _test_import_shapefile_polygon (
        fname   => $fname,
        binarise_counts => 1,
        expected_total_count => 240,
    );
}


sub test_import_shapefile_polyline_default {
    use FindBin qw /$Bin/;
    my $fname = $Bin . '/data/polyline data.shp';
    _test_import_shapefile_polygon (
        fname   => $fname,
        is_line => 1,
        expected_total_count => 369,
    );
}

sub test_import_shapefile_polyline_length {
    use FindBin qw /$Bin/;
    my $fname = $Bin . '/data/polyline data.shp';
    _test_import_shapefile_polygon (
        fname   => $fname,
        is_line => 1,
        sample_count_fields => [':shape_length'],
    );
}

#  trigger the hierarchical fishnet
sub test_import_shapefile_polyline_length_hierarchical {
    use FindBin qw /$Bin/;
    my $fname = $Bin . '/data/polyline data.shp';
    _test_import_shapefile_polygon (
        fname   => $fname,
        is_line => 1,
        sample_count_fields => [':shape_length'],
        cell_sizes => [10000, 12000],
        expected_gp_count => 1593,
    );
}

sub test_import_shapefile_polyline_binarised {
    use FindBin qw /$Bin/;
    my $fname = $Bin . '/data/polyline data.shp';
    _test_import_shapefile_polygon (
        fname   => $fname,
        is_line => 1,
        binarise_counts => 1,
        expected_total_count => 140,
    );
}


sub test_import_shapefile_polygon_odd_axes {
    my %args = @_;
    my $fname   = $args{fname};

    use FindBin qw /$Bin/;
    $fname //= $Bin . '/data/polygon data.shp';

    my $in_options_hash = {
        group_field_names => [':shape_x'],
        label_field_names => ['BINOMIAL'],
    };

    my $new_bd = Biodiverse::BaseData->new (
        NAME => 'test_import_shapefile feature data one axis',
        CELL_SIZES => [100000],
    );
    # import as shapefile
    my $success = eval {
        $new_bd->import_data_shapefile (
            input_files => [$fname],
            %$in_options_hash,
        );
    };
    my $e = $EVAL_ERROR;
    #diag $e;
    ok ($e, "exception raised importing $fname with a single axis");

    $in_options_hash = {
        group_field_names => [':shape_x', ':shape_y'],
        label_field_names => ['BINOMIAL'],
    };

    $new_bd = Biodiverse::BaseData->new (
        NAME => 'test_import_shapefile feature data one axis',
        CELL_SIZES => [100000,-1],
    );
    # import as shapefile
    $success = eval {
        $new_bd->import_data_shapefile (
            input_files => [$fname],
            %$in_options_hash,
        );
    };
    $e = $EVAL_ERROR;
    #diag $e;
    ok ($e, "exception raised importing $fname with a negative axis");

    $new_bd = Biodiverse::BaseData->new (
        NAME => 'test_import_shapefile feature data one axis',
        CELL_SIZES => [100000,0],
    );
    # import as shapefile
    $success = eval {
        $new_bd->import_data_shapefile (
            input_files => [$fname],
            %$in_options_hash,
        );
    };
    $e = $EVAL_ERROR;
    #diag $e;
    ok ($e, "exception raised importing $fname with a zero axis");
}


sub test_import_shapefile_polygon_reversed_axes {
    my %args = @_;
    my $fname   = $args{fname};

    use FindBin qw /$Bin/;
    $fname //= $Bin . '/data/polygon data.shp';

    my $bd1 = Biodiverse::BaseData->new (
        NAME => 'test_import_shapefile feature reversed axes',
        CELL_SIZES => [100000, 50000],
    );
    my $bd2 = Biodiverse::BaseData->new (
        NAME => 'test_import_shapefile feature reversed axes',
        CELL_SIZES => [50000, 100000],
    );

    # import as shapefile
    my $success = eval {
        $bd1->import_data_shapefile (
            input_files => [$fname],
            group_field_names => [':shape_y', ':shape_x'],
            label_field_names => ['BINOMIAL'],
        );
    };
    my $e = $EVAL_ERROR;
    ok (!$e, "no exception raised importing $fname with reversed axes");

    # import as shapefile
    $success = eval {
        $bd2->import_data_shapefile (
            input_files => [$fname],
            group_field_names => [':shape_x', ':shape_y'],
            label_field_names => ['BINOMIAL'],
        );
    };
    
    is ($bd1->get_label_sample_count(label => 'Dromornis_planei'),
        $bd2->get_label_sample_count(label => 'Dromornis_planei'),
        'got same sample counts for non-square axes',
    );
    
}

sub test_import_shapefile_polygon_text_axis {
    my %args = @_;
    my $fname   = $args{fname};

    use FindBin qw /$Bin/;
    $fname //= $Bin . '/data/polygon data.shp';

    my $bd1 = Biodiverse::BaseData->new (
        NAME => 'test_import_shapefile feature reversed axes',
        CELL_SIZES => [-1, 100000, 50000],
    );

    # import as shapefile
    my $success = eval {
        $bd1->import_data_shapefile (
            input_files => [$fname],
            group_field_names => ['BINOMIAL', ':shape_y', ':shape_x'],
            label_field_names => ['BINOMIAL'],
        );
    };
    my $e = $EVAL_ERROR;
    ok (!$e, "no exception raised importing $fname with text axis in first pos");

    my @groups = sort $bd1->get_groups;
    is ($groups[0], 'Dromornis_planei:-1750000:425000', 'got expected group name');
}

sub test_import_polygon_non_spatial {
    my %args = @_;
    my $fname   = $args{fname};

    use FindBin qw /$Bin/;
    $fname //= $Bin . '/data/polygon data.shp';

    my $bd1 = Biodiverse::BaseData->new (
        NAME => 'test_import_shapefile feature reversed axes',
        CELL_SIZES => [-1],
    );

    # import as shapefile
    my $success = eval {
        $bd1->import_data_shapefile (
            input_files => [$fname],
            group_field_names => ['BINOMIAL'],
            label_field_names => ['BINOMIAL'],
        );
    };
    my $e = $EVAL_ERROR;
    ok (!$e, "no exception raised importing $fname when not using :shape_x or :shape_y");

    my @groups = sort $bd1->get_groups;
    is ($groups[0], 'Dromornis_planei', 'got expected group name');    
}

sub get_import_data_small {
    return get_data_section('BASEDATA_IMPORT_SMALL');
}

sub test_import_shapefile_polygon_many_files {
    use FindBin qw /$Bin/;
    my $fname = $Bin . '/data/polygon data.shp';
    my $cell_sizes = [100000,100000];
    die if !-e $fname;
    my $in_options_hash = {
        group_field_names => [':shape_x', ':shape_y'],
        label_field_names => ['BINOMIAL'],
        binarise_counts   => 0,
        # sample_count_col_names => ['VALUE'],
    };

    my $bd1 = Biodiverse::BaseData->new (
        NAME => 'two sequential imports',
        CELL_SIZES => $cell_sizes,
    );
    # import as shapefile
    my $success = eval {
        $bd1->import_data_shapefile (
            input_files => [$fname],
            %$in_options_hash,
        );
        $bd1->import_data_shapefile (
            input_files => [$fname],
            %$in_options_hash,
        );
    };
    my $e = $EVAL_ERROR;
    ok (!$e, "no exceptions importing $fname");
    diag $e if $e;
    if ($e) {
        diag "$fname:";
        #foreach my $ext (qw /shp dbf shx/) {
        #    diag 'size: ' . -s ($fname . $ext);
        #}
    }


    my $bd2 = Biodiverse::BaseData->new (
        NAME => 'two at a time imports',
        CELL_SIZES => $cell_sizes,
    );
    # import as shapefile
    $success = eval {
        $bd2->import_data_shapefile (
            input_files => [$fname, $fname],
            %$in_options_hash,
        );
    };
    $e = $EVAL_ERROR;
    ok (!$e, "no exceptions importing $fname");
    diag $e if $e;
    if ($e) {
        diag "$fname:";
        #foreach my $ext (qw /shp dbf shx/) {
        #    diag 'size: ' . -s ($fname . $ext);
        #}
    }

    use List::Util;
    my @labels = List::Util::uniq ($bd1->get_labels, $bd2->get_labels);
    # diag join ' ', @labels;
    my (%lb_counts1, %lb_counts2);
    foreach my $lb (@labels) {
        $lb_counts1{$lb} = $bd1->get_label_sample_count (label => $lb);
        $lb_counts2{$lb} = $bd2->get_label_sample_count (label => $lb);
    }
    is \%lb_counts1, \%lb_counts2, 'got matching label counts';
}


__DATA__

@@ BASEDATA_IMPORT_SMALL
id,gen_name_in,sp_name_in,x,y,z,incl1,excl1,incl2,excl2,incl3,excl3
1,g1,sp1,1,1,1,1,1,,,1,0
2,g2,sp2,2,2,2,0,,1,1,1,0
3,g2,sp3,1,3,3,,,1,1,1,0
