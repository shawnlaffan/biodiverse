#!/usr/bin/perl -w
use strict;
use warnings;

use English qw { -no_match_vars };
use Carp;

use FindBin qw { $Bin };
use File::Spec;

use File::Basename;

use lib File::Spec->catfile( $Bin, '..', '..', 'lib');

use Biodiverse::BaseData;
use Biodiverse::Common;
use Biodiverse::Cluster;

#  load up the user defined libs
use Biodiverse::Config qw /use_base add_lib_paths/;
BEGIN {
    add_lib_paths();
    use_base();
}

local $| = 1;



#  Add a matrix to a basedata file
#
#  perl add_existing_matrices_to_basedata.pl input.bds

my $bd_file = $ARGV[0];


die ("BaseData file not specified\n" . usage())
  if not defined $bd_file;

my $bd = eval {
    Biodiverse::BaseData->new(file => $bd_file);
};
croak $EVAL_ERROR if $EVAL_ERROR;

foreach my $cl ($bd->get_cluster_output_refs) {  #  should also do region grower outputs
    $cl->add_matrices_to_basedata(matrices => $cl->get_matrices_ref);  #  should check if they are already outputs
}

$bd->save (filename => $bd_file);



sub usage {
    my($filename, $directories, $suffix) = File::Basename::fileparse($0);

    my $usage = << "END_OF_USAGE";
Biodiverse - A spatial analysis tool for species (and other) diversity.

usage: \n
    $filename <basedata file> 

END_OF_USAGE

    return $usage;
}
 