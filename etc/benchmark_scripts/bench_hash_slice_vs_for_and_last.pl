#  Benchmark two approaches which could be used to get a total tree path length
#  It is actually to do with a hash slice vs for-last approach
use 5.016;

use Benchmark qw {:all};
use List::Util qw /max/;
use Test::More;
use Math::Random::MT::Auto;

use rlib;
use Biodiverse::Bencher qw/add_hash_keys_lastif copy_values_from/;

my $prng = Math::Random::MT::Auto->new;

local $| = 1;

#srand (2000);

my $n = 20;   #  depth of the paths
my $m = 1800;  #  number of paths
my $r = $n - 1;    #  how far to be the same until (irand)
my $subset_size = int ($m/4);
my %path_arrays;  #  ordered keys
my %path_hashes;  #  unordered key-value pairs
my %len_hash;

#$n = 5;
#$m = 8;
#$r = 0;
#$subset_size = $n;

#  generate a set of paths 
foreach my $i (0 .. $m) {
    my $same_to = max (1, int $prng->rand($r));
    my @a;
    #@a = map {((1+$m)*$i*$n+$_), 1} (0 .. $same_to);
    @a = map {$_ => $_} (0 .. $same_to);
    push @a, map {((1+$m)*$i*$n+$_) => $_} ($same_to+1 .. $n);
    #say join ' ', @a;
    my %hash = @a;
    $path_hashes{$i} = \%hash;
    $path_arrays{$i} = [reverse sort {$a <=> $b} keys %hash];
    
    @len_hash{keys %hash} = values %hash;
}

#use Test::LeakTrace;
#leaktrace {
#    my $x = inline_assign (\%path_arrays);
#    #say join ':', values %$x;
#} -verbose;


my $sliced = slice (\%path_hashes);
my $forled = for_last (\%path_arrays);
my $slice2 = slice_mk2 (\%path_hashes);
my $inline = inline_assign (\%path_arrays);

#foreach my $key (keys %len_hash) {
#    $len_hash{$key}++;
#}

is_deeply ($sliced, \%len_hash, 'slice results are the same');
is_deeply ($slice2, \%len_hash, 'slice2 results are the same');
is_deeply ($forled, \%len_hash, 'forled results are the same');
is_deeply ($inline, \%len_hash, 'inline results are the same');



done_testing;

#exit();

for (0..2) {
    say "Testing $subset_size of $m paths of length $n and overlap up to $r";
    
    my @subset = ($prng->shuffle (0..$m))[0..$subset_size];
    #say scalar @subset;
    #say join ' ', @subset[0..4];
    my (%path_hash_subset, %path_array_subset);
    @path_hash_subset{@subset}  = @path_hashes{@subset};
    @path_array_subset{@subset} = @path_arrays{@subset};
    
    cmpthese (
        -3,
        {
            #slice1 => sub {slice (\%path_hash_subset)},
            #slice2 => sub {slice_mk2 (\%path_hash_subset)},
            forled => sub {for_last (\%path_array_subset)},
            inline => sub {inline_assign (\%path_array_subset)},
            inline_s => sub {inline_assign_with_slice (\%path_array_subset)},
        }
    );
    say '';
}


sub slice {
    my $paths = shift;
    
    my %combined;
    
    foreach my $path (values %$paths) {
        @combined{keys %$path} = values %$path;
    }
    #  next line is necessary when the paths
    #  have different values from %combined,
    #  albeit the initial use case was the same
    @combined{keys %combined} = @len_hash{keys %combined};

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
    
    
    #  initialise
    my %combined;

  LIST:
    foreach my $list (values %$paths) {
        if (!scalar keys %combined) {
            @combined{@$list} = undef;
            next LIST;
        }
        
        foreach my $key (@$list) {
            last if exists $combined{$key};
            $combined{$key} = undef;
        }
    }
    @combined{keys %combined} = @len_hash{keys %combined};

    return \%combined;
}

sub inline_assign {
    my $paths = shift;

    my $combo = {};

    foreach my $path (values %$paths) {
        #print $path;
        add_hash_keys_lastif ($combo, $path);
    }

    copy_values_from ($combo, \%len_hash);

    return $combo;
}

sub inline_assign_with_slice {
    my $paths = shift;

    my %combined;

    foreach my $path (values %$paths) {
        add_hash_keys_lastif (\%combined, $path);
    }

    @combined{keys %combined} = @len_hash{keys %combined};

    return \%combined;
}




1;

__END__

Sample results below.
Removing the slice assign from slice1 makes it about as fast as inline,
but the relevant sub in Biodiverse uses an array so cannot do a
direct slice assign on hash values.
e.g. (@hash1(keys %hash2) = values %hash2)

Testing 450 of 1800 paths of length 20 and overlap up to 19
        Rate slice1 slice2 forled inline
slice1 224/s     --   -14%   -20%   -36%
slice2 261/s    17%     --    -7%   -25%
forled 280/s    25%     7%     --   -19%
inline 347/s    55%    33%    24%     --

Testing 450 of 1800 paths of length 20 and overlap up to 19
        Rate slice1 forled slice2 inline
slice1 231/s     --   -20%   -21%   -48%
forled 288/s    25%     --    -1%   -35%
slice2 292/s    26%     1%     --   -34%
inline 444/s    93%    54%    52%     --

Testing 450 of 1800 paths of length 20 and overlap up to 19
        Rate slice1 slice2 forled inline
slice1 213/s     --   -19%   -25%   -47%
slice2 263/s    24%     --    -7%   -35%
forled 283/s    33%     8%     --   -30%
inline 403/s    90%    53%    43%     --