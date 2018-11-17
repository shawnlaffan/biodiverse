use 5.022;

use strict;
use warnings;
use Time::HiRes qw /time/;
use POSIX qw /ceil/;

use Geo::GDAL::FFI;

my @resolutions = (50000, 50000);
my $extent = [0, 100000, 0, 100000];

my ($polyfile) = @ARGV;

#use Devel::Symdump;
#my $obj = Devel::Symdump->rnew(); 
#my @found = grep {$_ =~ /GetExtent/i} $obj->functions();
#print join ' ', @found;

my $layer  = Geo::GDAL::FFI::Open($polyfile)->GetLayer;
#my $extent = Geo::GDAL::FFI::OGR_L_GetExtent([$layer]);

#print $extent;

my $fname = 'fish_' . int (time()) . '.shp';
my $fishnet_l = fishnet ($fname, @$extent, @resolutions);

#  adapted from https://pcjericks.github.io/py-gdalogr-cookbook/vector_layers.html#create-fishnet-grid
sub fishnet {
    my ($out_fname, $xmin, $xmax, $ymin, $ymax, $grid_height, $grid_width) = @_;
    
    my $driver = 'ESRI Shapefile';
    $driver = 'Memory';
    my $outLayer
        = Geo::GDAL::FFI::GetDriver($driver)
            ->Create ($out_fname)
            ->CreateLayer({
                Name => 'Fishnet Layer',
                GeometryType => 'Polygon',
                Fields => [{
                    Name => 'name',
                    Type => 'String'
                }],
        });
    my $featureDefn = $outLayer->GetDefn();

    my $rows = ceil(($ymax - $ymin) / $grid_height);
    my $cols = ceil(($xmax - $xmin) / $grid_width);
    say "Generating fishnet of size $rows x $cols";

    # start grid cell envelope
    my $ring_X_left_origin   = $xmin;
    my $ring_X_right_origin  = $xmin + $grid_width;
    my $ring_Y_top_origin    = $ymax;
    my $ring_Y_bottom_origin = $ymax - $grid_height;

    # create grid cells;
    my $countcols = 0;
    foreach my $countcols (1 .. $cols) {
        # reset envelope for rows;
        my $ring_Y_top    = $ring_Y_top_origin;
        my $ring_Y_bottom = $ring_Y_bottom_origin;
        my $countrows = 0;

        foreach my $countrows (1 .. $rows) {
            my $poly = 'POLYGON (('
                . "$ring_X_left_origin  $ring_Y_top, "
                . "$ring_X_right_origin $ring_Y_top, "
                . "$ring_X_right_origin $ring_Y_bottom, "
                . "$ring_X_left_origin  $ring_Y_bottom, "
                . "$ring_X_left_origin  $ring_Y_top"
                . '))';
            #say $poly;
            my $f = Geo::GDAL::FFI::Feature->new($outLayer->GetDefn);
            $f->SetField(name => "$countrows x $countcols");
            $f->SetGeomField([WKT => $poly]);
            $outLayer->CreateFeature($f);
            # new envelope for next poly
            $ring_Y_top    = $ring_Y_top    - $grid_height;
            $ring_Y_bottom = $ring_Y_bottom - $grid_height;
        }
        # new envelope for next poly;
        $ring_X_left_origin  = $ring_X_left_origin  + $grid_width;
        $ring_X_right_origin = $ring_X_right_origin + $grid_width;
    }
}



