
use Benchmark qw {:all};
use 5.016;
use Data::Dumper;
use Test::More;

use List::BinarySearch::XS qw /binsearch_pos/;

my %hashbase;
#@hash{1..1000} = (rand()) x 1000;
for my $i (1..1000) {
    $hashbase{$i} = rand() + 1;
}
my $hashref = \%hashbase;

my @keys = keys %$hashref;

my $l1 = insert_into_sorted_list_bulk();
my $l2 = insert_then_sort();
is_deeply $l1, $l2, 'lists match';

done_testing();

cmpthese (
    -5,
    {
        insert_into_sorted_list => sub {insert_into_sorted_list_bulk()},
        insert_then_sort        => sub {insert_then_sort()},
    }
);

sub insert_into_sorted_list_bulk {
    my $list = [];
    foreach my $key (@keys) {
        insert_into_sorted_list_aa($key, $list);
    }
    $list;
}

sub insert_into_sorted_list_aa {
    my $idx  = binsearch_pos { $a cmp $b } $_[0], @{$_[1]};
    splice @{$_[1]}, $idx, 0, $_[0];

    $idx;
}


sub insert_then_sort {
    my $list = [];
    foreach my $key (@keys) {
        push @$list, $key;
    }
    $list = [sort @$list];
}

