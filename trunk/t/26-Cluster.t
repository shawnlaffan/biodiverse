#!/usr/bin/perl -w
#
#  tests for both normal and lowmem matrices, where they overlap in methods

require 5.010;
use strict;
use warnings;

use FindBin qw/$Bin/;
use rlib;

use Test::More;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Test::More; # tests => 2;
use Test::Exception;

use Biodiverse::TestHelpers qw /:basedata/;


use Biodiverse::Cluster;

#  make sure we get the same result with the same prng across two runs
{
    my $data = get_cluster_mini_data();
    my $bd = get_basedata_object (data => $data, CELL_SIZES => [1,1]);
    
    check_order_is_same_given_same_prng (basedata_ref => $bd);
    
    my $site_bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);
    check_order_is_same_given_same_prng (basedata_ref => $site_bd);
    
    
    print "";
}

sub check_order_is_same_given_same_prng {
    my %args = @_;
    my $bd = $args{basedata_ref};
    
    my $prng_seed = $args{prng_seed} || 2345;
    
    my $cl1 = $bd->add_cluster_output (name => 'cl1');
    my $cl2 = $bd->add_cluster_output (name => 'cl2');
    my $cl3 = $bd->add_cluster_output (name => 'cl3');
    
    $cl1->run_analysis (
        prng_seed => $prng_seed,
    );
    $cl2->run_analysis (
        prng_seed => $prng_seed,
    );
    $cl3->run_analysis (
        prng_seed => $prng_seed + 1,  #  different prng
    );
    
    my $newick1 = $cl1->to_newick;
    my $newick2 = $cl2->to_newick;
    my $newick3 = $cl3->to_newick;
    
    is   ($newick1, $newick2, 'trees are the same');
    isnt ($newick1, $newick3, 'trees are not the same');
}


done_testing();


######################################

sub get_cluster_mini_data {
    return get_data_section('CLUSTER_MINI_DATA');
}


1;

__DATA__

@@ CLUSTER_MINI_DATA
label,x,y,samples
a,1,1,1
b,1,1,1
c,1,1,1
a,1,2,1
b,1,2,1
c,1,2,1
a,2,1,1
b,2,1,1
a,2,2,1
b,2,2,1
c,2,2,1
a,3,1,1
b,3,1,1
a,3,2,1
b,3,2,1
