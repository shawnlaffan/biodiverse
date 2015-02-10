use 5.010;
use Benchmark qw {:all};
use List::Util qw /reduce/;
use Data::Dumper;

my $n = 1000;
my $min = -500;
my @a1 = ($min .. ($min + $n));

my @data;
for my $i (0 .. $#a1) {
    push @data, [$a1[$i], $a1[-($i+1)]];
}

say Dumper sub1(\@data);
say Dumper sub2(\@data);



cmpthese (
    -5,
    {
        reduce  => sub {sub2 ()},
        foreach => sub {sub1 ()},
    }
);


sub sub2 {
    my $pairs = shift;

    my $first = reduce { ($a->[0] cmp $b->[0] || $a->[1] cmp $b->[1]) < 0 ? $b : $a} @$pairs;
    
    return $first;
}

sub sub1 {
    my $pairs = shift;

    my $first = $pairs->[0];
    foreach my $pair (@$pairs) {
        if (($first->[0] cmp $pair->[0] || $first->[1] cmp $pair->[1]) < 0) {
            $first = $pair;
        }
    }
    
    return $first;
}
