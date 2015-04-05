#  Import a file with a single label column
#  This is for profiling purposes.  


use strict;
use warnings;

use English qw { -no_match_vars };
use Carp;

use FindBin qw { $Bin };
use File::Spec;

use rlib File::Spec->catfile( $Bin, '..', '..');

use Biodiverse::BaseData;

local $| = 1;

my $data_file = 'x.csv';


my $bd = eval {
    Biodiverse::BaseData->new(
        name => 'experiment',
        CELL_SIZES    => [1,1],
    );
};
croak $EVAL_ERROR if $EVAL_ERROR;

$bd->import_data (
    input_files   => [$data_file],
    label_columns => [0],
    group_columns => [1,2],
);



