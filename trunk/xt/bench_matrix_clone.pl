use strict;
use warnings;

use 5.010;
use strict;
use warnings;
use Carp;

use FindBin qw/$Bin/;
use rlib '../lib', '../t/lib';
use List::Util qw /first/;


use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Test::More; # tests => 2;
use Test::Exception;

use Biodiverse::TestHelpers qw /:cluster :tree/;
use Biodiverse::Cluster;

use Benchmark qw {:all};

my $cellsize = 10000;
my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$cellsize, $cellsize]);
my $cl = $bd->add_cluster_output (
    name => 'clus',
);
$cl->run_analysis (
    #prng_seed        => 2345,
    build_matrices_only => 1,
);

my $matrices_ref = $cl->get_orig_matrices;
my $mx = $matrices_ref->[0];

#my $cx = use_clone($mx);
#my $dx = use_copy($mx);

#$cx->export (format => 'Delimited text', type => 'sparse', file => 'cx.csv');
#$dx->export (format => 'Delimited text', type => 'sparse', file => 'dx.csv');


cmpthese (
    -10,
    {
        use_clone => sub {use_clone($mx)},
        use_copy  => sub {use_copy($mx)},
    }
);



sub use_clone {
    my $mx = shift;
    
    my $success = $mx->clone;
}

sub use_copy {
    my $mx = shift;
    
    my $success = $mx->_duplicate;
}