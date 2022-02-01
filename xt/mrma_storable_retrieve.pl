use strict;
use warnings;

use Storable;
use Config;
use Carp;

use Math::Random::MT::Auto;


my @poss_int_sizes = (4, 8);
my $int_size = $Config{'uvsize'};

#if ($int_size == 8) {
#    @poss_int_sizes = reverse @poss_int_sizes;  #  check own int size first
#}

foreach my $isize (@poss_int_sizes) {
    print "Checking storable with PRNG of int size $isize on perl with int size of $int_size\n";
    my $filename = 'MRMA_uvsize_' . $isize . '.storable';
    my $array = retrieve ($filename) or croak "Cannot open $filename\n";
    my $prng = $array->[1];
    my $state = $prng->get_state;
    print 'State starts with: ' . join (q{ }, $state->[0], $state->[1], $state->[2]) . "\n";
    print $prng->irand . "\n";
}
