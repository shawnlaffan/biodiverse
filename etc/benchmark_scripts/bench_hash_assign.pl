use 5.022;
use Benchmark qw {:all};
use Data::Dumper;

use experimental qw/refaliasing/;

my %hashbase;
#@hash{1..1000} = (rand()) x 1000;
for my $i (1..1000) {
    $hashbase{$i} = rand() + 1;
}

our @all_keys = sort keys %hashbase;
my @keys = @all_keys[0..50];

#use Test::More;
#my %ls;
#@ls{@keys} = @hashbase{@keys};
#my %hs     = %hashbase{@keys};
#is_deeply (\%hs, \%ls, 'got matching results');
#done_testing;


foreach \my @bounds ([0..100], [50..250], [50..500], [50..900], [0..999]) {
    @keys = @all_keys[@bounds];

    say "Testing bounds [$bounds[0]..$bounds[-1]]";
    cmpthese (
        -3,
        {
            #hash_deref_once => sub {hash_deref_once ()},
            list_slice => sub {list_slice()},
            hash_slice   => sub {hash_slice()},
        }
    );
}

sub list_slice {
    my %subhash;
    @subhash{@keys} = @hashbase{@keys};
}

sub hash_slice {
    my %subhash = %hashbase{@keys};
}

__END__

Testing bounds [0..100]
               Rate list_slice hash_slice
list_slice  97759/s         --       -10%
hash_slice 108541/s        11%         --
Testing bounds [50..250]
              Rate list_slice hash_slice
list_slice 46455/s         --       -10%
hash_slice 51808/s        12%         --
Testing bounds [50..500]
              Rate list_slice hash_slice
list_slice 19278/s         --        -9%
hash_slice 21137/s        10%         --
Testing bounds [50..900]
              Rate list_slice hash_slice
list_slice 10145/s         --        -9%
hash_slice 11191/s        10%         --
Testing bounds [0..999]
             Rate list_slice hash_slice
list_slice 8403/s         --       -10%
hash_slice 9297/s        11%         --
