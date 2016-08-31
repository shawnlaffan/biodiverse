#  Convert a biodiverse storable file to sereal.
#  We want to see how it handles large files.  

use 5.016;
use Biodiverse::BaseData;
use Time::HiRes qw /time/;

local $| = 1;

my $file = $ARGV[0];
my $bd;
my $time;

if (0) {
    $time = time();
    $bd = Biodiverse::BaseData->new (file => 'blort_storable.bds');
    printf "time to load from storable format %.3f\n", time() - $time;

    $time = time();
    $bd->save_to_storable (filename => 'blort_storable.bds');
    printf "time to write storable format %.3f\n", time() - $time;
}

if (1) {
    $time = time();
    $bd = Biodiverse::BaseData->new(file => 'blort.bds');
    printf "time to read sereal version %.3f\n", time() - $time;
 

    $time = time();
    $bd->save_to_sereal (filename => 'blort.bds');
    printf "time to write sereal format %.3f\n", time() - $time;
}

