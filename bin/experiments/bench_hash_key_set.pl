
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
    my %hash;
    foreach my $key1 (@keys_outer) {
        foreach my $key2 (@keys) {
            $hash{$key1}{$key2}++;
        }
        #say 'nsk ' . scalar keys %hash if !(scalar (keys %hash) % 100);
    }
    
}

sub set_keys_outer {
    my %hash;
    keys %hash = scalar @keys_outer;
    foreach my $key1 (@keys_outer) {
        foreach my $key2 (@keys) {
            $hash{$key1}{$key2}++;
        }
        #say 'sko ' . scalar keys %hash if !(scalar (keys %hash) % 100);
    }
}

sub set_keys_outer_init {
    my %hash;
    keys %hash = scalar @keys_outer;
    foreach my $key1 (@keys_outer) {
        $hash{$key1} //= {};
        foreach my $key2 (@keys) {
            $hash{$key1}{$key2}++;
        }
        #say 'skoi ' . scalar keys %hash if !(scalar (keys %hash) % 100);
    }
}

sub set_keys_inner {
    my %hash;
    keys %hash = scalar @keys_outer;
    foreach my $key1 (@keys_outer) {
        $hash{$key1} //= {};
        keys %{$hash{$key1}} = scalar @keys;
        foreach my $key2 (@keys) {
            $hash{$key1}{$key2}++;
        }
        #say 'ski ' . scalar keys %hash if !(scalar (keys %hash) % 100);
    }
}

