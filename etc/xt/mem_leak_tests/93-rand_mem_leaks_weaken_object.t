use strict;
use warnings;
use Carp;
use English qw ( -no_match_vars );

use Test::More;

use FindBin qw {$Bin};

use Devel::Leak::Object;
# maybe also try Devel::Leak::Guard
# Devel::Monitor
#  

local $| = 1;

require Biodiverse::BaseData;
require Biodiverse::Randomise;

my $data_dir = File::Spec->catfile( $Bin, q{..}, 'data' );
print "Data dir is $data_dir\n";

#  should use File::Temp (or whichever it is)
my $out_file = 'x1.bds';

#my $good_test = sub {

    my $in_file = File::Spec->catfile( $data_dir, 'Example_site_data.csv' );
    my $bd = Biodiverse::BaseData->new (
        NAME => 'test',
    );
    Devel::Leak::Object::track($bd);

do {
    $bd->set_param(CELL_SIZES => [500000, 500000]);
    $bd->import_data (
        input_files   => [$in_file],
        label_columns => [1, 2],
        group_columns => [3, 4],
    );

    my $r = $bd->add_randomisation_output (
        name     => 'csr',
        FUNCTION => 'rand_structured',
    );

Devel::Leak::Object::track($r);

    $r->run_analysis (iterations => 2);
    $bd->save (filename => $out_file);
    #$r->set_param(Blah => $bd);
};

#my $res = $good_test;
#is ($res, 0, "No leaks found");

if (-e $out_file) {
    unlink ($out_file);
}


done_testing();

