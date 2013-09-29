#  script to profile the bray-curtis analyses. 

use 5.016;
use Time::HiRes;

use rlib;
use rlib '../t/lib';

use Biodiverse::Config;
use Biodiverse::BaseData;
use Biodiverse::TestHelpers qw /:basedata/;

my $build_bd = 0;

my $cell_sizes   = [50000, 50000];
my $size = 100;
#my $bd = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
my $bd;
if ($build_bd) {
    $bd = get_basedata_object(
        x_spacing  => $cell_sizes->[0],
        y_spacing  => $cell_sizes->[1],
        CELL_SIZES => $cell_sizes,
        x_max      => $size,
        y_max      => $size,
        x_min      => 0,
        y_min      => 0,
    );
    $bd->build_spatial_index (resolutions => [@$cell_sizes]);
    
    $bd->save_to (filename => 'bd.bds');
    
}
else {
    $bd = Biodiverse::BaseData->new (file => 'bd.bds');
}

my $conditions   = ['sp_circle (radius => 200000)'];
#$conditions   = ['$d[0] > -100000 && $d[0] < 100000', 'sp_circle (radius => 200000)'];
my $calculations = [qw /calc_richness/];

for my $i (1..1) {
    my $sp = $bd->add_spatial_output (name => $i);
    $sp->run_analysis (
        spatial_conditions => $conditions,
        calculations       => $calculations,
    );
    $bd->delete_output (output => $sp);
}
