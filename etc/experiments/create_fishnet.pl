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
    my ($outputGridfn, $xmin, $xmax, $ymin, $ymax, $gridHeight, $gridWidth) = @_;
    
    #my $outDriver = Geo::GDAL::FFI::GetDriverByName('ESRI Shapefile');
    #if (-e $outputGridfn) {
    #    unlink ($outputGridfn);
    #}
    #my $outDataSource = $outDriver->CreateDataSource($outputGridfn);
    #my $outLayer = $outDataSource->CreateLayer($outputGridfn,{geom_type => 'Polygon'});
    my $driver = 'ESRI Shapefile';
    #$driver = 'Memory';
    my $outLayer
      #= Geo::GDAL::FFI::GetDriver('Memory')->Create->CreateLayer({
        = Geo::GDAL::FFI::GetDriver($driver)
            ->Create ($outputGridfn)
            ->CreateLayer({
                Name => $outputGridfn,
                GeometryType => 'Polygon',
                Fields => [{
                    Name => 'name',
                    Type => 'String'
                }],
        });
    my $featureDefn = $outLayer->GetDefn();
    
    my $rows = ceil(($ymax - $ymin) / $gridHeight);
    my $cols = ceil(($xmax - $xmin) / $gridWidth);
    say "Generating fishnet of size $rows x $cols";
    # start grid cell envelope
    my $ringXleftOrigin   = $xmin;
    my $ringXrightOrigin  = $xmin + $gridWidth;
    my $ringYtopOrigin    = $ymax;
    my $ringYbottomOrigin = $ymax - $gridHeight;

    # create grid cells;
    my $countcols = 0;
    while ($countcols < $cols) {
        $countcols ++;
        # reset envelope for rows;
        my $ringYtop    = $ringYtopOrigin;
        my $ringYbottom = $ringYbottomOrigin;
        my $countrows = 0;

        while ($countrows < $rows) {
            $countrows ++;
            my $poly = 'POLYGON (('
                . "$ringXleftOrigin  $ringYtop, "
                . "$ringXrightOrigin $ringYtop, "
                . "$ringXrightOrigin $ringYbottom, "
                . "$ringXleftOrigin  $ringYbottom, "
                . "$ringXleftOrigin  $ringYtop"
                . '))';
            #say $poly;
            my $f = Geo::GDAL::FFI::Feature->new($outLayer->GetDefn);
            $f->SetField(name => "$countrows x $countcols");
            $f->SetGeomField([WKT => $poly]);
            $outLayer->CreateFeature($f);
            # new envelope for next poly
            $ringYtop    = $ringYtop    - $gridHeight;
            $ringYbottom = $ringYbottom - $gridHeight;
        }
        # new envelope for next poly;
        $ringXleftOrigin  = $ringXleftOrigin  + $gridWidth;
        $ringXrightOrigin = $ringXrightOrigin + $gridWidth;
    }
}



