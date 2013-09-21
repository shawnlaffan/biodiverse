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


my $bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);
my $cl = $bd->add_cluster_output (
    name => 'clus',
);
$cl->run_analysis (
    prng_seed        => 2345,
);

my $matrices_ref = $cl->get_matrices_ref;
my $mx = $matrices_ref->[0];

my $xx = use_copy($mx);

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
    
    my $success = $mx->duplicate;
}