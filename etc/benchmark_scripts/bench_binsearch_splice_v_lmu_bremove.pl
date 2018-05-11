
use Benchmark qw {:all};
use 5.016;
use Data::Dumper;
use Test::More;

use List::BinarySearch::XS qw /binsearch/;
use List::MoreUtils::XS 0.423 qw/bremove/;
use List::MoreUtils;# qw /bremove/;

my %hashbase;
#@hash{1..1000} = (rand()) x 1000;
for my $i (1..100) {
    $hashbase{$i} = rand() + 1;
}
my $hashref = \%hashbase;

my @sorted_keys = sort keys %$hashref;

my $l1 = lmu();
my $l2 = lbs();

say join ' ', @$l1;
say join ' ', @$l2;

is_deeply ($l1, $l2, 'same');

done_testing();

#exit;

cmpthese (
    -2,
    {
        lmu  => sub {lmu()},
        lbs  => sub {lbs()},
        baseline => sub {baseline()},
    }
);

sub lbs {
    my $list = [@sorted_keys];
    foreach my $key (keys %hashbase) {
        delete_from_sorted_list_aa($key, $list);
    }
    $list;
}

sub delete_from_sorted_list_aa {
    my $idx  = binsearch { $a cmp $b } $_[0], @{$_[1]};
    splice @{$_[1]}, $idx, 1;

    $idx;
}


sub lmu {
    my $list = [@sorted_keys];
    foreach my $key (keys %hashbase) {
        #$_ = $key;
        #  hack for initial dev version
        #if (scalar @$list == 1 and $key eq $list->[0]) {
        #    shift @$list;
        #}
        #else {
            bremove {$_ cmp $key} @$list;
        #}
        #say join ',', @$list;
    }
    $list;
}

sub baseline {
    my $list = [@sorted_keys];
    #while (@$list) {
    #    shift @$list;
    #}
    $list;
}

__END__

            Rate      lmu      lbs baseline
lmu        567/s       --     -27%     -97%
lbs        782/s      38%       --     -96%
baseline 20299/s    3478%    2497%       --
