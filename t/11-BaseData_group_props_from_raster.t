#  Tests for basedata re-ordering of label axes

use strict;
use warnings;
use 5.010;

use English qw { -no_match_vars };
use Carp;
use Geo::GDAL::FFI qw/GetDriver/;
use Test::TempDir::Tiny;

use rlib;

local $| = 1;

use Test2::V0;

use Biodiverse::BaseData;
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
        CELL_SIZES => [10,10],
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
    );
    my @rasters;
    my $dir = tempdir('gp_property_rasters');
    foreach my $n (0..1) {
        my $tiff_name = sprintf "propdata%03i.tif", $n;
        my $local_params = $raster_params[$n];
        my $tiff = get_raster(
            name    => "$dir/$tiff_name",
            xorigin => 0,
            yorigin => 0,
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
    );

    is scalar @prop_bds, 2, 'Got expected number of property basedatas';
    ok $prop_bds[0]->labels_are_numeric,
      'labels are numeric for first property raster';
    ok $prop_bds[1]->labels_are_numeric,
      'labels are numeric for second property raster';

    my $gp_ref = $bd->get_groups_ref;
    my %samplers = (
        '45:15' => {
            propdata000_mean => 43.5,
        },
        '35:5' => {
            propdata000_mean => 33.5,
            propdata001_mean => 29,
        },
        '15:25' => {
            propdata000_mean => 13.5,
            propdata001_mean => 13.5,
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
    
    #say @prop_bds;
    
}

sub get_raster {
    my %args = @_;
    my $tiff_name = $args{name};
    my $ncols = $args{ncols} // 5;
    my $nrows = $args{nrows} // 5;
    my $xres  = $args{xres}  // 1;
    my $yres  = $args{yres}  // 1;

    my $tiff = GetDriver('GTiff')->Create($tiff_name, $ncols, $nrows);
    my $transform = [1,1,0,1,0,1];
    $tiff->SetGeoTransform($transform);
    my @data;
    foreach my $col (0..$ncols-1) {
        my @vals;
        foreach my $row (0 ..$nrows-1) {
            push @vals, $row;
        }
        push @data, \@vals;
    }
    $tiff->GetBand->Write(\@data);
    return $tiff_name;
}

done_testing();
