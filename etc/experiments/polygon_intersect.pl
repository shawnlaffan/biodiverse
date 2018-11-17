use 5.022;

use strict;
use warnings;
use Time::HiRes qw /time/;

use Geo::GDAL::FFI;

my ($polyfile, $fishnetfile) = @ARGV;

my $layer = Geo::GDAL::FFI::Open($polyfile)->GetLayer;
$layer->ResetReading;
my $fishnet = Geo::GDAL::FFI::Open($fishnetfile)->GetLayer;
#$fishnet->ResetReading;

my $last_p = time();
my $progress = sub {
    return if abs(time() - $last_p) < 0.5;
    my ($fraction, $msg, $data) = @_;
    local $| = 1;
    #say STDERR "$fraction $data";
    printf "%.3g ", $fraction;
    $last_p = time();
};

#  get the fishnet cells that intersect the polygons
my $identity  = $layer->Identity($fishnet, {Progress => $progress});


#my $defn_intersection = $identity->GetDefn;

my $feature_count = 0;
while (my $feature = $identity->GetNextFeature) {
    my $geom = $feature->GetGeomField;
    #my $area  = $geom->Area;
    #say $area;
    $feature_count++;
}

say "Processed $feature_count features";

