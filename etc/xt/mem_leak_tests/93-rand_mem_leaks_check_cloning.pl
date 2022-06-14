use strict;
use warnings;
use Clone qw (clone);
#use Clone::Fast qw( clone );
use Storable qw (dclone);
use Scalar::Util qw /weaken isweak/;

$| = 1;

my %hash;
my @array = 1 .. 10**6;
@hash{@array} = undef;

for my $i  (1 .. 1000) {
    $hash{$i} = \%hash;
    weaken $hash{$i};
}

my $max = 50;
for my $j (1 .. $max) {
    print "Clone $j\n";
    my $hash2 = clone (\%hash);
    print "Weak? " . (isweak ($hash2->{1}) ? 'yes' : 'no') . "\n";
}

sleep (5);
