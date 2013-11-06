#!perl

use strict;
use warnings;

use Biodiverse::BaseData;
use Biodiverse::Cluster;

use Benchmark;

my $bd_file = 'xx.bds';

my $bd = Biodiverse::BaseData->new(file => $bd_file);

my $tree_ref = Biodiverse::Tree->new(file => 'trimmed_tree.bts');

my $spatial_conditions = ['sp_self_only()', 'sp_circle (radius => 100000)'];
my $analyses_to_run    = [qw /calc_phylo_sorenson/];

use Time::HiRes;
my $starttime = time;
my $t = timeit (5, sub {run()});
my $endtime = time;

my $elapsed = $endtime - $starttime;
print "Time taken = $elapsed\n";


sub run {
    my $sp = $bd->add_spatial_output (name => 'xx');
    my $success = eval {
        $sp->run_analysis (
            spatial_conditions => $spatial_conditions,
            calculations       => $analyses_to_run,
            tree_ref           => $tree_ref,
        );
    };
    $bd->delete_output (output => $sp);
}
