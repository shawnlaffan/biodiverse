#  example script for reading in a set of trees fromn a nexus file and then
#  linking them to an existing basedata object

use strict;
use warnings;
use Carp;  #  warnings and dropouts
use File::Spec;  #  for the cat_file sub 
use English qw ( -no_match_vars );

use Biodiverse::Config;
use Biodiverse::BaseData;


my $basedata_file = $ARGV[0];
my $basedata_out  = $ARGV[1];
my $radius = $ARGV[2] // 15000; 

my $spatial_conditions = ["sp_circle (radius => $radius)"];
my $analyses_to_run    = [qw /calc_numeric_label_stats calc_numeric_label_quantiles/];


###  read in the basedata object
my $bd = Biodiverse::BaseData->new (file => $basedata_file);

#  build the spatial index
$bd->build_spatial_index (
    resolutions => [$bd->get_cell_sizes],
);

my $sp = $bd->add_spatial_output (name => 'numeric_labels');
my $success = eval {
    $sp->run_analysis (
        spatial_conditions => $spatial_conditions,
        calculations       => $analyses_to_run,
    );
};
croak $EVAL_ERROR if $EVAL_ERROR;

if ($success) {  #  export to CSV using defaults
    $bd->save (filename => $basedata_out);
    $sp->export (
        file   => $basedata_file . "_${radius}.csv",
        format => 'Delimited text',
        list   => 'SPATIAL_RESULTS',
    );
    $sp->export (
        file   => $basedata_file . "_$radius",
        format => 'GeoTIFF',
        list   => 'SPATIAL_RESULTS',
    );
}
