use Benchmark qw {:all};
use 5.016;
use Data::Dumper;

use List::Util qw {sum};

my @keys = 'a' .. 'zzm';
my %base_hash;
@base_hash{@keys} = map {rand() + $_} (1..@keys);

say sum_foreach();
say lu_sum();
say lu_sum0();
say lu_reduce();
say pf_values();


cmpthese (
    -2,
    {
        foreach   => \&sum_foreach,
        lu_sum    => \&lu_sum,
        lu_sum0   => \&lu_sum0,
        lu_reduce => \&lu_reduce,
        pf_values => \&pf_values,
    }
);

sub sum_foreach {
    my $sum;
    foreach (values %base_hash) {
        $sum += $_;
    }
    $sum;
}

sub lu_sum {
    my $sum = sum values %base_hash;
    $sum;
}

sub lu_sum0 {
    my $sum = sum 0, values %base_hash;
    $sum;
}

sub lu_reduce {
    my $sum = List::Util::reduce {$a + $b} values %base_hash;
    $sum;
}

sub pf_values {
    my $sum;
    $sum += $_ for values %base_hash;
    $sum;
}

