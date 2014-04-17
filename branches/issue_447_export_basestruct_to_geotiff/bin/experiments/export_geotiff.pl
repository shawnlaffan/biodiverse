
use 5.016;

use FindBin;
use Path::Class;
use rlib "../../lib";

use Biodiverse::Config;

use Geo::GDAL;
use Biodiverse::BaseData;



my $data_dir = Path::Class::Dir->new($FindBin::Bin, '..', '..', 'data')->stringify;

my $bd_file = Path::Class::File->new($data_dir, 'example_data_x64.bds')->stringify;

my $bd = Biodiverse::BaseData->new (file => $bd_file);

my $sp = $bd->add_spatial_output(name => 'blah');
$sp->run_analysis (
    calculations       => ['calc_richness'],
    spatial_conditions => ['sp_self_only()'],
);


#my $export_type = 'ArcInfo floatgrid files';
my $export_type = 'GeoTIFF';
my $filename    = 'xx.tiff';
my $list_name   = 'SPATIAL_RESULTS';

$sp->export (
    format => $export_type,
    file   => $filename,
    list   => $list_name,
);




#my $format = "GTiff";
#my $driver = Geo::GDAL::GetDriverByName( $format );
#
#my $metadata = $driver->GetMetadata();
#
#if (exists $metadata->{DCAP_CREATE} && $metadata->{DCAP_CREATE} eq 'YES') {
#    say "Driver for $metadata->{DMD_LONGNAME} supports Create() method.";
#}
#
#if (exists $metadata->{DCAP_CREATECOPY} && $metadata->{DCAP_CREATECOPY} eq 'YES') {
#    say "Driver $metadata->{DMD_LONGNAME} supports CreateCopy() method.";
#}
#
#my $n = 100;
#my @data;
#my $pdata;
#for my $i (reverse (0 .. $n)) {
#    for my $j (0 .. $n) {
#        my $value = $i * $n + $j;
#        $data[$i][$j] = $value;
#        $pdata .= pack ('f', $value);
#    }
#}
#
#
#my $f_name = 'test5.tif';
#my ($cols, $rows) = ($n+1, $n+1);
#
#my $out_raster = $driver->Create($f_name, $cols, $rows, 1, 'Float32');
#
#my $outband = $out_raster->GetRasterBand(1);
#$outband->WriteRaster(0, 0, $rows, $cols, $pdata);
#
#
#
