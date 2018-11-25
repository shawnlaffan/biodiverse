use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };
use Data::Dumper;
use Path::Class;

use Test::Lib;
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

    foreach my $sub (@test_subs) {
        no strict 'refs';
        $sub->();
    }
    
    done_testing;
    return 0;
}


#can we reimport shapefiles after exporting and get the same answer
sub test_roundtrip_shapefile {
    my %bd_args = (
        NAME => 'test include exclude',
        CELL_SIZES => [1,1],
    );

    my $fname = write_data_to_temp_file(get_import_data_small());
    note("testing filename $fname");
    my $e;

    #  get the original - should add some labels with special characters
    my $bd = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd->import_data(
            input_files   => [$fname],
            group_columns => [3, 4],
            label_columns => [1, 2],
        );
    };
    $e = $EVAL_ERROR;
    ok (!$e, 'import vanilla with no exceptions raised');
    
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

        #  need to use a better approach for the name
        my $fname_base = $tmp_dir . 'shapefile_' . $i; 

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
        ok (-e $fname . '.shp', "$fname.shp exists");

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
                diag 'size: ' . -s ($fname . $ext);
            }
        }
        

        my @new_labels  = sort $new_bd->get_labels;
        my @orig_labels = sort $bd->get_labels;
        is_deeply (\@new_labels, \@orig_labels, "label lists match for $fname");

        my $new_lb = $new_bd->get_labels_ref;
        subtest "sample counts match for $fname" => sub {
            foreach my $label (sort $bd->get_labels) {
                my $new_list  = $new_lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                my $orig_list = $lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                
                #say "new list: " . join(',', keys %$new_list) . join(',', values %$new_list) if ($new_list);
                #say "orig list: " . join(',', keys %$orig_list) . join(',', values %$orig_list)if ($orig_list);
                is_deeply ($new_list, $orig_list, "SUBELEMENTS match for $label, $fname");
            }
        };

        $i++;
    }
    
}

sub test_import_shapefile_polygon {
    use FindBin qw /$Bin/;
    my $fname = $Bin . '/data/polygon_data.shp';

    my $in_options_hash = {
        group_field_names => [':shape_x', ':shape_y'],
        label_field_names => ['BINOMIAL'],
    };

    my $new_bd = Biodiverse::BaseData->new (
        NAME => 'test_import_shapefile polygon',
        CELL_SIZES => [100000, 100000],
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
        foreach my $ext (qw /shp dbf shx/) {
            diag 'size: ' . -s ($fname . $ext);
        }
    }

    my @new_labels  = sort $new_bd->get_labels;
    my @orig_labels = ('Dromornis_planei');
    is_deeply (\@new_labels, \@orig_labels, "label lists match for $fname");
    
    my $new_lb = $new_bd->get_labels_ref;
    my $got = $new_bd->get_label_sample_count (label => $orig_labels[0]);
    my $exp = 1794988604045.7;  #  prob too precise
    is ($got, $exp, "sample counts match for $orig_labels[0] in $fname");
    
}


sub get_import_data_small {
    return get_data_section('BASEDATA_IMPORT_SMALL');
}


__DATA__

@@ BASEDATA_IMPORT_SMALL
id,gen_name_in,sp_name_in,x,y,z,incl1,excl1,incl2,excl2,incl3,excl3
1,g1,sp1,1,1,1,1,1,,,1,0
2,g2,sp2,2,2,2,0,,1,1,1,0
3,g2,sp3,1,3,3,,,1,1,1,0
