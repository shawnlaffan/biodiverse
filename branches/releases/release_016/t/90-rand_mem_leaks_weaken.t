#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;
use English qw ( -no_match_vars );

use mylib;

use Test::More;

use Test::Weaken qw( leaks );

local $| = 1;

use FindBin qw { $Bin };

require Biodiverse::BaseData;
require Biodiverse::Randomise;

my $data_dir = File::Spec->catfile( $Bin, q{..}, 'data' );
print "Data dir is $data_dir\n";

my $out_file = 'x1.bds';

my $good_test = sub {

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

    my $r = $bd -> add_randomisation_output (
        name     => 'csr',
        FUNCTION => 'rand_structured',
    );

    $r -> run_analysis (iterations => 1);
    $bd->save (filename => $out_file);

    $bd->delete_output (output => $r);
    
    #  now override the object
    $bd = Biodiverse::BaseData->new (
        file => 'x1.bds',
    );
    my $r2 = $bd -> get_randomisation_output_ref (
        name     => 'csr',
    );
    $r2->run_analysis (iterations => 1);

    #undef $r;
    return $bd;
};

my $res = leaks($good_test) ? 1 : 0;
is ($res, 0, "No leaks found");

if (-e $out_file) {
    unlink ($out_file);
}
#if ( !leaks($good_test) ) {
#    warn "No leaks in test 1\n"
#        or croak("Cannot print to STDOUT: $ERRNO");
#}
#else {
#    warn "There were memory leaks from test 1!\n"
#        or croak("Cannot print to STDOUT: $ERRNO");
#}
#
#my $tester = Test::Weaken::leaks(
#        {   constructor => $good_test,
#        }
#    );
#if ($tester) {
#    my $unfreed_proberefs = $tester->unfreed_proberefs();
#    my $unfreed_count     = @{$unfreed_proberefs};
#    printf "Test 2: %d of %d original references were not freed\n",
#        $tester->unfreed_count(), $tester->probe_count()
#        or Carp::croak("Cannot print to STDOUT: $ERRNO");
#    print "These are the probe references to the unfreed objects:\n"
#        or Carp::croak("Cannot print to STDOUT: $ERRNO");
#    for my $ix ( 0 .. $#{$unfreed_proberefs} ) {
#        print Data::Dumper->Dump( [ $unfreed_proberefs->[$ix] ],
#            ["unfreed_$ix"] )
#            or Carp::croak("Cannot print to STDOUT: $ERRNO");
#    }
#}
#else {
#    warn "Nowt found\n";
#}

done_testing();