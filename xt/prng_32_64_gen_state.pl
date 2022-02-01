use strict;
use warnings;
use autodie;

use Math::Random::MT::Auto qw /rand/;
use Data::Dumper;

my $seed = 23;

my $prng = Math::Random::MT::Auto->new(seed => $seed);

my $state = $prng->get_state;

#print Dumper $state;

my $file = 'state.txt';

open my $fh, '>', $file;

print $fh Dumper $state;

close $fh;

