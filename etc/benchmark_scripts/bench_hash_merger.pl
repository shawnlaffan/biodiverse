
use Benchmark qw {:all};
use 5.016;

use Math::Random::MT::Auto;

my $prng1 = Math::Random::MT::Auto->new(seed => 222);
my $prng2 = Math::Random::MT::Auto->new(seed => 222);
my $prng3 = Math::Random::MT::Auto->new(seed => 222);

$| = 1;

my @labels = (1 .. 100000);

my @idx_starts = grep {not $_ % 10} (1..1000);

my $check_count = 100;



foreach my $count (10, 50, 100, 300, 500, 1000) {
    $check_count = $count;
    print "\nCheck count is $check_count\n";
    cmpthese (
        -5,
        {
            hash_crash => sub {hash_crash()},
            grep_first => sub {grep_first()},
            next_if    => sub {next_if()},
        }
    );
}


sub hash_crash {
    my @shuffled_labels = $prng1->shuffle (@labels);
    
    my %path;

    for my $idx_start (@idx_starts) {
        my @sublist = @shuffled_labels[$idx_start .. ($idx_start + $check_count)];
        @path{@sublist} = undef;
    }
}


sub grep_first {
    my @shuffled_labels = $prng2->shuffle (@labels);

    my %path;

    for my $idx_start (@idx_starts) {
        my @sublist = grep {!exists $path{$_}} @shuffled_labels[$idx_start .. ($idx_start + $check_count)];
        @path{@sublist} = undef;
    }    
}

sub next_if {
    my @shuffled_labels = $prng3->shuffle (@labels);

    my %path;

    for my $idx_start (@idx_starts) {
        for my $label (@shuffled_labels[$idx_start .. ($idx_start + $check_count)]) {
            next if exists $path{$label};
            $path{$label} = undef;
        }
    }
}


__END__


Strawberry perl 5.16


Check count is 10
             Rate grep_first    next_if hash_crash
grep_first 73.5/s         --        -2%        -4%
next_if    75.0/s         2%         --        -2%
hash_crash 76.9/s         5%         3%         --

Check count is 50
             Rate hash_crash    next_if grep_first
hash_crash 70.8/s         --        -3%        -3%
next_if    73.1/s         3%         --        -0%
grep_first 73.3/s         4%         0%         --

Check count is 100
             Rate hash_crash    next_if grep_first
hash_crash 65.4/s         --        -6%        -8%
next_if    69.6/s         6%         --        -2%
grep_first 70.8/s         8%         2%         --

Check count is 300
             Rate hash_crash grep_first    next_if
hash_crash 47.3/s         --       -20%       -20%
grep_first 59.3/s        25%         --        -0%
next_if    59.5/s        26%         0%         --

Check count is 500
             Rate hash_crash    next_if grep_first
hash_crash 37.4/s         --       -26%       -28%
next_if    50.7/s        35%         --        -3%
grep_first 52.0/s        39%         3%         --

Check count is 1000
             Rate hash_crash    next_if grep_first
hash_crash 23.9/s         --       -36%       -38%
next_if    37.1/s        55%         --        -4%
grep_first 38.6/s        61%         4%         --



perlbrew 5.20.0 on a faster linux box


Check count is 10
            Rate grep_first    next_if hash_crash
grep_first 181/s         --        -2%        -3%
next_if    186/s         3%         --        -1%
hash_crash 187/s         3%         1%         --

Check count is 50
            Rate hash_crash grep_first    next_if
hash_crash 160/s         --        -3%        -3%
grep_first 165/s         3%         --        -0%
next_if    166/s         3%         0%         --

Check count is 100
            Rate hash_crash    next_if grep_first
hash_crash 136/s         --        -7%        -9%
next_if    145/s         7%         --        -2%
grep_first 149/s        10%         2%         --

Check count is 300
             Rate hash_crash    next_if grep_first
hash_crash 83.8/s         --       -13%       -20%
next_if    96.2/s        15%         --        -8%
grep_first  105/s        25%         9%         --

Check count is 500
             Rate hash_crash    next_if grep_first
hash_crash 60.0/s         --       -16%       -25%
next_if    71.1/s        19%         --       -11%
grep_first 79.9/s        33%        12%         --

Check count is 1000
             Rate hash_crash    next_if grep_first
hash_crash 34.4/s         --       -19%       -31%
next_if    42.6/s        24%         --       -14%
grep_first 49.5/s        44%        16%         --
