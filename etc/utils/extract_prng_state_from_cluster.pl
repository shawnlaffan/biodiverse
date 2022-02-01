use strict;
use warnings;
use Carp;

use Biodiverse::BaseData;
use Biodiverse::Cluster;

use Data::Dumper;

my $file = $ARGV[0];
my $cl_name = $ARGV[1];

my $bd = Biodiverse::BaseData->new (file => $file);

my $cl = $bd->get_cluster_output_ref(name => $cl_name)
  or croak "Cannot find a cluster output called $cl_name\n";

my $prng_start_state = $cl->get_param ('RAND_INIT_STATE');

print Dumper($prng_start_state);

