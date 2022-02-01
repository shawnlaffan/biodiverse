use strict;
use warnings;

use File::Temp;

use Devel::Leak;
use Devel::FindRef;

local $| = 1;

#use constant HAS_LEAKTRACE => eval{ require Test::LeakTrace };

use Test::More;

plan (tests => 2);

use Test::LeakTrace;

#use Data::Structure::Util qw /has_circular_ref get_refs/;
use FindBin qw { $Bin };

require Biodiverse::BaseData;
require Biodiverse::Randomise;

my $data_dir = File::Spec->catfile( $Bin, q{..}, 'data' );
print "Data dir is $data_dir\n";


my $in_file = File::Spec->catfile( $data_dir, 'Example_site_data.csv' );
my $bd = Biodiverse::BaseData -> new (
    NAME => 'test',
);
$bd->set_param(CELL_SIZES => [500000, 500000]);
$bd->import_data (
    input_files   => [$in_file],
    label_columns => [1, 2],
    group_columns => [3, 4],
);
undef $in_file;


my $descr = 'load, run, delete';
diag ($descr);

my $handle;
#my $count = Devel::Leak::NoteSV($handle);

{
    my $r = $bd->add_randomisation_output (
        name     => 'csr',
        FUNCTION => 'rand_nochange',
    );

    $r->run_analysis (iterations => 1);

    $bd->delete_output (output => $r);

    #print Devel::FindRef::track \$bd;

    undef $r;
    undef $bd;
};


#Devel::Leak::CheckSV($handle);

ok (1);
ok (1);
