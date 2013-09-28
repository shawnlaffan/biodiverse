#  script to profile the bray-curtis analyses. 

use 5.016;
use Time::HiRes;

use rlib;
use rlib '../t/lib';

use Biodiverse::Config;
use Biodiverse::BaseData;
use Biodiverse::TestHelpers qw /:basedata/;



my $cell_sizes   = [50000, 50000];
my $bd = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
$bd->build_spatial_index (resolutions => [@$cell_sizes]);

my $conditions   = ['sp_circle (radius => 100000)', 'sp_circle (radius => 200000)'];
#$conditions   = ['$d[0] > -100000 && $d[0] < 100000', 'sp_circle (radius => 200000)'];
my $calculations = [qw /calc_bray_curtis calc_bray_curtis_norm_by_gp_counts/];

for my $i (1..10) {
    my $sp = $bd->add_spatial_output (name => $i);
    $sp->run_analysis (
        spatial_conditions => $conditions,
        calculations       => $calculations,
    );
    $bd->delete_output (output => $sp);
}
