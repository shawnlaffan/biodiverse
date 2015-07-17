
use Benchmark qw {:all};
use 5.016;

use Panda::Lib qw /hash_merge/;
use Test::More;

use Math::Random::MT::Auto;

my $prng4 = Math::Random::MT::Auto->new(seed => 222);


$| = 1;

my @labels = (1 .. 100000);




my $check_count = 100;


foreach my $count (10, 50, 100, 300, 500, 1000) {
    $check_count = $count;
    print "\nCheck count is $check_count\n";

    my @key_lists;
    my @key_hashes;
    my @idx_starts = grep {not $_ % 10} (1..1000);;
    my @shuffled_labels = $prng4->shuffle (@labels);
    
    for my $idx_start (@idx_starts) {
        my @sublist = @shuffled_labels[$idx_start .. ($idx_start + $check_count)];
        push @key_lists, \@sublist;
        my %sub_hash;
        @sub_hash{@sublist} = undef;
        push @key_hashes, \%sub_hash;
    }

    my $panda      = panda (\@key_hashes);
    my $grep_first = grep_first (\@key_hashes);
    my $hash_crash = hash_crash (\@key_hashes);
    my $next_if    = next_if (\@key_hashes);

    is_deeply ($panda, $grep_first, "panda and grep_first match");
    is_deeply ($panda, $next_if, "panda and next_if match");
    is_deeply ($panda, $hash_crash, "panda and hash_crash match");
    printf "%12s%8d\n", "panda:", scalar keys %$panda;
    printf "%12s%8d\n", "grep_first:", scalar keys %$grep_first;
    printf "%12s%8d\n", "hash_crash:", scalar keys %$grep_first;
    printf "%12s%8d\n", "next_if:", scalar keys %$grep_first;

    cmpthese (
        -5,
        {
            hash_crash => sub {hash_crash(\@key_hashes)},
            grep_first => sub {grep_first(\@key_hashes)},
            next_if    => sub {next_if(\@key_hashes)},
            panda      => sub {panda(\@key_hashes)},
        }
    );
}

done_testing();

sub panda {
    my $key_hashes = shift;

    my %path;

    for my $sub_list (@$key_hashes) {
        hash_merge (\%path, $sub_list, "MERGE_LAZY");
    }
    
    return \%path;
}

sub hash_crash {
    my $key_lists = shift;
    
    my %path;

    for my $sub_list (@$key_lists) {
        @path{keys %$sub_list} = undef;
    }
    
    return \%path;
}


sub grep_first {
    my $key_lists = shift;

    my %path;

    for my $sub_list (@$key_lists) {
        @path{grep {!exists $path{$_}} keys %$sub_list} = undef;
    }
    
    return \%path;
}

sub next_if {
    my $key_lists = shift;

    my %path;

    for my $sub_list (@$key_lists) {
        for my $label (keys %$sub_list) {
            next if exists $path{$label};
            $path{$label} = undef;
        }
    }
    
    return \%path;
}


__END__

perl 5.20.0, centos linux box

perl bench_hash_merger_panda.pl

Check count is 10
ok 1 - panda and grep_first match
ok 2 - panda and next_if match
ok 3 - panda and hash_crash match
      panda:    1001
 grep_first:    1001
 hash_crash:    1001
    next_if:    1001
             Rate    next_if grep_first hash_crash      panda
next_if    2574/s         --        -6%       -31%       -59%
grep_first 2749/s         7%         --       -27%       -56%
hash_crash 3751/s        46%        36%         --       -40%
panda      6208/s       141%       126%        65%         --

Check count is 50
ok 4 - panda and grep_first match
ok 5 - panda and next_if match
ok 6 - panda and hash_crash match
      panda:    1041
 grep_first:    1041
 hash_crash:    1041
    next_if:    1041
             Rate    next_if grep_first hash_crash      panda
next_if     797/s         --       -16%       -34%       -59%
grep_first  954/s        20%         --       -21%       -51%
hash_crash 1206/s        51%        26%         --       -38%
panda      1934/s       143%       103%        60%         --

Check count is 100
ok 7 - panda and grep_first match
ok 8 - panda and next_if match
ok 9 - panda and hash_crash match
      panda:    1091
 grep_first:    1091
 hash_crash:    1091
    next_if:    1091
             Rate    next_if grep_first hash_crash      panda
next_if     439/s         --       -18%       -34%       -60%
grep_first  534/s        22%         --       -20%       -51%
hash_crash  666/s        52%        25%         --       -39%
panda      1101/s       150%       106%        65%         --

Check count is 300
ok 10 - panda and grep_first match
ok 11 - panda and next_if match
ok 12 - panda and hash_crash match
      panda:    1291
 grep_first:    1291
 hash_crash:    1291
    next_if:    1291
            Rate    next_if grep_first hash_crash      panda
next_if    155/s         --       -21%       -35%       -61%
grep_first 195/s        26%         --       -18%       -51%
hash_crash 238/s        53%        22%         --       -41%
panda      402/s       159%       106%        69%         --

Check count is 500
ok 13 - panda and grep_first match
ok 14 - panda and next_if match
ok 15 - panda and hash_crash match
      panda:    1491
 grep_first:    1491
 hash_crash:    1491
    next_if:    1491
             Rate    next_if grep_first hash_crash      panda
next_if    94.4/s         --       -20%       -34%       -62%
grep_first  118/s        25%         --       -18%       -52%
hash_crash  143/s        51%        22%         --       -42%
panda       246/s       160%       109%        72%         --

Check count is 1000
ok 16 - panda and grep_first match
ok 17 - panda and next_if match
ok 18 - panda and hash_crash match
      panda:    1991
 grep_first:    1991
 hash_crash:    1991
    next_if:    1991
             Rate    next_if grep_first hash_crash      panda
next_if    44.9/s         --       -18%       -31%       -59%
grep_first 55.0/s        23%         --       -16%       -49%
hash_crash 65.5/s        46%        19%         --       -40%
panda       109/s       142%        98%        66%         --
