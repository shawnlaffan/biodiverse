use strict;
use warnings;

use Math::Random::MT::Auto;
use Storable qw /nstore/;

use Config;

print("Integers are $Config{'uvsize'} bytes in length\n");

my $int_size = $Config{'uvsize'};
my $prng = Math::Random::MT::Auto->new (seed => 23);

my @array = ($int_size, $prng);

my $filename = 'MRMA_uvsize_' . $int_size . '.storable';

print $filename;

nstore(\@array, $filename) or die "Cannot store @array in $filename.\n";

