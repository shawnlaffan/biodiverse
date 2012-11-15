#!/usr/bin/perl -w
use strict;
use warnings;
use 5.010;

use Carp;
use English qw { -no_match_vars };

use Biodiverse::BaseData;

my $bd_file  = shift @ARGV;
my $out_file = shift @ARGV;
my $runs     = shift @ARGV // 100;
my $index    = shift @ARGV // 'S2';
my $prng_starting_seed = shift @ARGV // time;
my $prng_seed_offset = shift @ARGV // 100;

croak "no basedata file specified" if !defined $bd_file;

my $bd = Biodiverse::BaseData->new(file => $bd_file);

my $prng_seed = int $prng_starting_seed;

$bd_file =~ /(.+)(\.bd.$)/;
my $prefix = "${1}_clusters_${runs}";
my $suffix = $2;

my $out_bd = $prefix . $suffix;

my $fname = $out_file // $prefix . '.tre';
open my $fh, '>', $fname or croak "cannot open $fname";

for my $i (1 .. $runs) {
    my $name = sprintf "cluster_%04i", $i;
    my $cl = $bd->add_cluster_output(name => $name);
    $cl->run_analysis (
        index     => $index,
        prng_seed => $prng_seed,
    );
    #$bd->save (filename => $out_bd);
    
    my $nwk = $cl->to_newick();
    say { $fh } $nwk;
    
    $bd->delete_all_outputs (output => $cl);
    $prng_seed += $prng_seed_offset;
}

