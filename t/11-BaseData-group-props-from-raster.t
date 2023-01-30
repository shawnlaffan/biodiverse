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
    
    test_group_props_from_rasters();

    done_testing;
    return 0;
}

sub test_group_props_from_rasters {
    #  too much hard coding going on here
    
    my $cellx = 10;
    my $celly = 10;
    my $halfx = $cellx / 2;
    my $halfy = $celly / 2;
    
    my $bd = Biodiverse::BaseData->new (
        NAME => 'blognorg',
        CELL_SIZES => [$cellx, $celly],
        CELL_ORIGINS => [0,0],
    );
    foreach my $x (0 .. 5) {
        foreach my $y (0 .. 5) {
            my $gp
              = join ':',
                ($cellx * $x + $halfx,
                 $celly * $y + $halfy);
            $bd->add_element_simple_aa('a', $gp, 1);
        }
    }
    my $bd2 = $bd->clone;
    my $bd3 = $bd->clone;
    my $bd_multi_stat = $bd->clone;

    #  need to generate some raster data
    my @raster_params = (
        {
            ncols => 50,
            nrows => 50,
        },
        {
            ncols => 30,
            nrows => 30,
        },
        {
            ncols => 3,
            nrows => 3,
            xorigin => 100,
            yorigin => 100,
        },
    );
    my @rasters;
    my $dir = tempdir('gp_property_rasters');
    foreach my $n (0..$#raster_params) {
        my $tiff_name = sprintf "propdata.%03i.tif", $n;
        my $local_params = $raster_params[$n];
        my $tiff = get_raster(
            name    => "$dir/$tiff_name",
            xorigin => 1,  #  slightly offset from main basedata
            yorigin => 1,
            xres    => 1,
            yres    => 1,
            %$local_params,
        );
        push @rasters, $tiff;
    }

    my @prop_bds
      = $bd->assign_group_properties_from_rasters (
        rasters => \@rasters,
        return_basedatas => 1,
        die_if_no_overlap => 0,
    );

    is scalar @prop_bds, scalar @rasters, 'Got expected number of property basedatas';
    ok $prop_bds[0]->labels_are_numeric,
      'labels are numeric for first property raster';
    ok $prop_bds[1]->labels_are_numeric,
      'labels are numeric for second property raster';
    ok $prop_bds[2]->labels_are_numeric,
      'labels are numeric for third property raster';

    my $gp_ref = $bd->get_groups_ref;
    my %samplers = (
        '45:15' => {
            'propdata.000_mean' => 43.5,
        },
        '35:5' => {
            'propdata.000_mean' => 33.5,
            'propdata.001_mean' => 29,
        },
        '15:25' => {
            'propdata.000_mean' => 13.5,
            'propdata.001_mean' => 13.5,
        },
    );
    foreach my $gp (sort keys %samplers) {
        my $props_list = $gp_ref->get_list_ref (
            list       => 'PROPERTIES',
            element    => $gp,
            autovivify => 0,
        );
        is $props_list,
           $samplers{$gp},
           "got expected group properties for $gp";
        #diag "$gp: " . join ' ', (%{$props_list || {}});
    }

    #  add some more expected values
    $samplers{'45:15'}{'propdata.000_min'} = 39;
    $samplers{'35:5'}{'propdata.000_min'}  = 29;
    $samplers{'35:5'}{'propdata.001_min'}  = 29;
    $samplers{'15:25'}{'propdata.000_min'} =  9;
    $samplers{'15:25'}{'propdata.001_min'} =  9;

    $bd_multi_stat->assign_group_properties_from_rasters (
        rasters => \@rasters,
        stats   => [qw /mean min/],
        return_basedatas => 0,
        die_if_no_overlap => 0,
    );
    my $gp_ref_multi_stat = $bd_multi_stat->get_groups_ref;
    foreach my $gp (sort keys %samplers) {
        my $props_list = $gp_ref_multi_stat->get_list_ref (
            list       => 'PROPERTIES',
            element    => $gp,
            autovivify => 0,
        );
        is $props_list,
           $samplers{$gp},
           "got expected multistat group properties for $gp";
        #diag "$gp: " . join ' ', (%{$props_list || {}});
    }

    
    like (
      dies {
        @prop_bds
            = $bd2->assign_group_properties_from_rasters (
              rasters => 'some_scalar',
              return_basedatas => 1,
              die_if_no_overlap => 0,
        );
      },
      qr//,
      "Dies when rasters arg is not an array ref"
    );

    
    like(
      dies {
        my @prop_bds2
            = $bd2->assign_group_properties_from_rasters (
              rasters => \@rasters,
              return_basedatas => 1,
              die_if_no_overlap => 1,
        );
      },
      qr/Raster .+ does not overlap/,
      "Dies when no overlap and die_if_no_overlap set"
    );


    my $bd_3axis = Biodiverse::BaseData->new (
        NAME => 'blognorg',
        CELL_SIZES => [10,10,1],
        CELL_ORIGINS => [0,0,0],
    );
    foreach my $x (0 .. 5) {
        foreach my $y (0 .. 5) {
            my $gp
              = join ':',
                ($cellx * $x + $halfx,
                 $celly * $y + $halfy,
                 1);
            $bd_3axis->add_element_simple_aa('a', $gp, 1);
        }
    }
    like(
      dies {
        my @prop_bds3axis
            = $bd_3axis->assign_group_properties_from_rasters (
              rasters => \@rasters,
              return_basedatas => 1,
              die_if_no_overlap => 0,
        );
      },
      qr/Target basedata must have 2 axes/,
      "Dies when basedata has other than two axes"
    );
    
    my $bd_1axis = Biodiverse::BaseData->new (
        NAME => 'blognorg',
        CELL_SIZES => [10],
        CELL_ORIGINS => [0],
    );
    foreach my $x (0 .. 5) {
        my $gp
          = $cellx * $x + $halfx;
        $bd_1axis->add_element_simple_aa('a', $gp, 1);
    }
    like(
      dies {
        my @prop_bds1axis
            = $bd_1axis->assign_group_properties_from_rasters (
              rasters => \@rasters,
              return_basedatas => 1,
              die_if_no_overlap => 0,
        );
      },
      qr/Target basedata must have 2 axes/,
      "Dies when basedata has other than two axes"
    );

    my $fname = "$dir/some_csv_file.zog";
    open my $fh, '>', $fname or die $!;
    print {$fh} "not a raster file at all";
    $fh->close;
    like(
      dies {
        my @prop_bd3
            = $bd3->assign_group_properties_from_rasters (
              rasters => [$fname, @rasters],
              return_basedatas => 1,
              die_if_no_overlap => 0,
        );
      },
      qr/Open failed/,
      "Dies when non-raster data are passed"
    );
    
}


sub get_raster {
    my %args = @_;
    my $tiff_name = $args{name};
    my $ncols = $args{ncols} // 5;
    my $nrows = $args{nrows} // 5;
    my $xres  = $args{xres}  // 1;
    my $yres  = $args{yres}  // 1;
    my $xorigin = $args{xorigin} // 0;
    my $yorigin = $args{yorigin} // 0;

    my $tiff = GetDriver('GTiff')->Create($tiff_name, $ncols, $nrows);
    my $transform = [$xorigin,$xres,0,$yorigin,0,$yres];
    $tiff->SetGeoTransform($transform);
    my @data;
    foreach my $col (0..$ncols-1) {
        push @data, [0 .. $nrows-1];
    }
    $tiff->GetBand->Write(\@data);
    return $tiff_name;
}

done_testing();
