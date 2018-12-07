use 5.022;

use strict;
use warnings;
use Time::HiRes qw /time/;
use POSIX qw /ceil floor/;
use Carp qw /confess croak/;

use Geo::GDAL::FFI;

my @resolutions = (50000, 50000);
my @origins     = (0, 0);
#my $extent = [0, 100000, 0, 100000];

my ($polyfile) = @ARGV;

#use Devel::Symdump;
#my $obj = Devel::Symdump->rnew(); 
#my @found = grep {$_ =~ /GetExtent/i} $obj->functions();
#say join ' ', @found;


my $layer  = Geo::GDAL::FFI::Open($polyfile)->GetLayer;

my $extent = get_extent ($layer);
say "Extent: " . join ' ', @$extent;

my $fname = 'fish_' . int (time()) . '.shp';
my $fishnet_l = generate_fishnet (
    fname  => $fname,
    extent => $extent,
    resolutions => \@resolutions,
    origins     => \@origins,
);


#  adapted from https://pcjericks.github.io/py-gdalogr-cookbook/vector_layers.html#create-fishnet-grid
sub generate_fishnet {
    my %args = @_;
    my $out_fname   = $args{fname};
    my $extent      = $args{extent};
    my $resolutions = $args{resolutions};
    my $origins     = $args{origins};

    my ($xmin, $xmax, $ymin, $ymax) = @$extent;
    my ($grid_height, $grid_width)  = @$resolutions;
    
    if ($origins) {    
        my @ll = ($xmin, $ymin);
        foreach my $i (0,1) {
            next if $resolutions[$i] <= 0;
            my $tmp_prec = $ll[$i] / $resolutions[$i];
            my $offset = floor ($tmp_prec);
            #  and shift back to index units
            $origins[$i] = $offset * $resolutions[$i];
        }
        ($xmin, $ymin) = @$origins;
    }

    my $driver = 'ESRI Shapefile';
    #$driver = 'Memory';
    my $fishnet_lyr
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
    my $featureDefn = $fishnet_lyr->GetDefn();

    my $rows = ceil(($ymax - $ymin) / $grid_height);
    my $cols = ceil(($xmax - $xmin) / $grid_width);
    say "Generating fishnet of size $rows x $cols";
    say "Origins are: " . join ' ', @$origins;

    # start grid cell envelope
    my $ring_X_left_origin   = $xmin;
    my $ring_X_right_origin  = $xmin + $grid_width;
    my $ring_Y_top_origin    = $ymax;
    my $ring_Y_bottom_origin = $ymax - $grid_height;

    # create grid cells
    foreach my $countcols (1 .. $cols) {
        # reset envelope for rows;
        my $ring_Y_top    = $ring_Y_top_origin;
        my $ring_Y_bottom = $ring_Y_bottom_origin;
        
        foreach my $countrows (1 .. $rows) {
            my $poly = 'POLYGON (('
                . "$ring_X_left_origin  $ring_Y_top, "
                . "$ring_X_right_origin $ring_Y_top, "
                . "$ring_X_right_origin $ring_Y_bottom, "
                . "$ring_X_left_origin  $ring_Y_bottom, "
                . "$ring_X_left_origin  $ring_Y_top"
                . '))';
            #say $poly;
            my $f = Geo::GDAL::FFI::Feature->new($fishnet_lyr->GetDefn);
            $f->SetField(name => "$countrows x $countcols");
            $f->SetGeomField([WKT => $poly]);
            $fishnet_lyr->CreateFeature($f);
            # new envelope for next poly
            $ring_Y_top    = $ring_Y_top    - $grid_height;
            $ring_Y_bottom = $ring_Y_bottom - $grid_height;
        }
        # new envelope for next poly;
        $ring_X_left_origin  = $ring_X_left_origin  + $grid_width;
        $ring_X_right_origin = $ring_X_right_origin + $grid_width;
    }

    return $fishnet_lyr;
}


sub get_extent {
    my ($layer, $extent, $force) = @_;
    $extent //= [0,0,0,0];
    my $e = Geo::GDAL::FFI::OGR_L_GetExtent ($$layer, $extent, $force ? 1 : 0);
    confess Geo::GDAL::FFI::error_msg({OGRError => $e})
      if $e;
    return $extent;
}
