
use Benchmark qw {:all};
use 5.016;
use Data::Dumper;

my @keys;
for (0..16000) {
    push @keys, rand();
}

my @keys_outer = @keys[0..257];


$| = 1;

cmpthese (
    30,
    {
        none       => sub {no_set_keys()},
        outer      => sub {set_keys_outer()},
        outer_init => sub {set_keys_outer_init()},
        inner      => sub {set_keys_inner()},
    }
);


sub no_set_keys {
    state $run_count;
    $run_count ++;
    say 'nsk ' . $run_count if !($run_count % 5);
    my %hash;
    foreach my $key1 (@keys_outer) {
        foreach my $key2 (@keys) {
            $hash{$key1}{$key2}++;
        }
    }
    
}

sub set_keys_outer {
    state $run_count;
    $run_count ++;
    say 'sko ' . $run_count if !($run_count % 5);

    my %hash;
    keys %hash = scalar @keys_outer;
    foreach my $key1 (@keys_outer) {
        foreach my $key2 (@keys) {
            $hash{$key1}{$key2}++;
        }
    }
}

sub set_keys_outer_init {
    state $run_count;
    $run_count ++;
    say 'skoi ' . $run_count if !($run_count % 5);

    my %hash;
    keys %hash = scalar @keys_outer;
    foreach my $key1 (@keys_outer) {
        $hash{$key1} //= {};
        foreach my $key2 (@keys) {
            $hash{$key1}{$key2}++;
        }
    }
}

sub set_keys_inner {
    state $run_count;
    $run_count ++;
    say 'ski ' . $run_count if !($run_count % 5);

    my %hash;
    keys %hash = scalar @keys_outer;
    foreach my $key1 (@keys_outer) {
        $hash{$key1} //= {};
        keys %{$hash{$key1}} = scalar @keys;
        foreach my $key2 (@keys) {
            $hash{$key1}{$key2}++;
        }
    }
}

__END__

The differences are all in the noise.

results on HPC with 5.20.0:

           s/iter outer_init      outer       none      inner
outer_init   5.17         --        -0%        -0%        -2%
outer        5.17         0%         --        -0%        -2%
none         5.17         0%         0%         --        -2%
inner        5.07         2%         2%         2%         --

