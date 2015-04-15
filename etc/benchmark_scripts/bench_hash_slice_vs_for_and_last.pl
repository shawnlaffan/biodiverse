#  Benchmark two approaches wihch could be used to get a total tree path length
#  It is actually to do with a hash slice vs for-last approach
use 5.016;

use Benchmark qw {:all};
use List::Util qw /pairs pairkeys pairvalues pairmap/;
use Test::More;

#srand (2000);

my $n = 200; #  depth of the paths
my $m = 80;  #  number of paths
my %path_arrays;  #  ordered key-value pairs
my %path_hashes;  #  unordered key-value pairs
my %len_hash;

#  generate a set of paths 
foreach my $i (0 .. $m) {
    my $same_to = int (rand() * $n/4);
    my @a;
    @a = map {(1+$m)*$i*$n+$_.'_', 1} (0 .. $same_to);
    push @a, map {$_, 1} ($same_to+1 .. $n);
    $path_arrays{$i} = \@a;
    #say join ' ', @a;
    my %hash = @a;
    $path_hashes{$i} = \%hash;
    
    @len_hash{keys %hash} = values %hash;
}


my $sliced = slice (\%path_hashes);
my $forled = for_last (\%path_arrays);
my $slice2 = slice_mk2 (\%path_hashes);

is_deeply ($forled, $sliced, 'slice results are the same');
is_deeply ($forled, $slice2, 'slice2 results are the same');


done_testing;

say "Testing $m paths of depth $n";
cmpthese (
    -2,
    {
        sliced => sub {slice (\%path_hashes)},
        slice2 => sub {slice_mk2 (\%path_hashes)},
        forled => sub {for_last (\%path_arrays)},
    }
);



sub slice {
    my $paths = shift;
    
    my %combined;
    
    foreach my $path (values %$paths) {
        @combined{keys %$path} = values %$path;
    }
    
    return \%combined;
}

#  assign values at end
sub slice_mk2 {
    my $paths = shift;
    
    my %combined;
    
    foreach my $path (values %$paths) {
        @combined{keys %$path} = undef;
    }
    
    @combined{keys %combined} = @len_hash{keys %combined};
    
    return \%combined;
}

sub for_last {
    my $paths = shift;
    

    my @keys = keys %$paths;
    my $first = shift @keys;
    my $first_list = $paths->{$first};
    
    #  initialise
    my %combined;
    @combined{pairkeys @$first_list} = pairvalues @$first_list;
    
    foreach my $list (values %$paths) {
        foreach my $pair (pairs @$list) {
            my ($key, $val) = @$pair;
            last if exists $combined{$key};
            $combined{$key} = $val;
        }
    }

    return \%combined;
}

1;

__END__

Sample results below.
Some runs have no meaningful difference from sliced to slice2,
but slice2 is always faster (even if only 2%).
Normally it is ~15% faster.  


Testing 800 paths of depth 20
         Rate forled sliced slice2
forled 59.2/s     --   -69%   -73%
sliced  192/s   225%     --   -13%
slice2  222/s   275%    15%     --

Testing 800 paths of depth 20
         Rate forled sliced slice2
forled 49.5/s     --   -74%   -77%
sliced  194/s   292%     --   -12%
slice2  219/s   342%    13%     --
