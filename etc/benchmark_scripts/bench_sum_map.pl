use 5.010;
use strict;
use warnings;

use Benchmark qw {:all};
use List::Util ();
use List::Keywords;

my $n = $ARGV[0] || 5000;
my @data = 0..$n;

say sum_foreach();
say LU_sum_map();
say LU_reduce();
say LK_reduce();


cmpthese (
    -2,
    {
        foreach    => \&sum_foreach,
        LU_sum_map => \&LU_sum_map,
        LU_reduce  => \&LU_reduce,
        LK_reduce  => \&LK_reduce,
    }
);

sub sum_foreach {
    my $sum;
    $sum += ($_) foreach @data;
    $sum;
}

sub LU_sum_map {
    my $sum = List::Util::sum map {$_} @data;
    $sum;
}


sub LU_reduce {
    my $sum = List::Util::reduce  {$a + $b} @data;
    $sum;
}

sub LK_reduce {
    use List::Keywords qw/reduce/;
    my $sum = reduce  {$a + $b} @data;
    $sum;
}



1;