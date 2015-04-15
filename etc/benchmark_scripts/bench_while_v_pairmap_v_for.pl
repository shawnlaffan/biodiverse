
use Benchmark qw {:all};
use 5.016;

use List::Util qw /pairs/;

$| = 1;

my %path_h;
@path_h{'a'..'z'} = (1..26);
my $path = \%path_h;  #  need to bench a hashref

my $check_count = 1000;

my $numerator = 5;
my $x;

no warnings 'uninitialized';

    
cmpthese (
    -1,
    {
        while => sub {use_while()},
        pairs => sub {use_pairs()},
    }
);



sub use_while {
    while (my ($name, $length) = each %$path) {
        #my $x = "$name $length";
        my $x = 0;
    }
}

sub use_pairs {
    foreach my $pair (pairs %$path) {
        #my $x = "$pair->[0], $pair->[1]";
        my $x = 0;
    }
}

