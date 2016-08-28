#  Convert a biodiverse storable file to sereal.
#  We want to see how it handles large files.  

use 5.016;

use Biodiverse::BaseData;

my $file = $ARGV[0];

my $bd = Biodiverse::BaseData->new (file => $file);

$bd->save_to_sereal (filename => 'blort.bds');

