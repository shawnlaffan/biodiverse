use 5.010;
use Test::More;
use Benchmark qw {:all};
#use List::Util qw {:all};

my $a = 1;
my $b = rand();
my $c = rand();

for $a (0, rand(), 1, 2000) {
    my $result_or   = !!use_or();
    my $result_or2  = !!use_or2();
    my $result_plus = !!use_plus();
    my $result_factored = !!factored();
    
    is ($result_or, $result_or2,  'use_or2()');
    is ($result_or, $result_plus, 'use_plus()');
    is ($result_or, $result_factored, 'factored()');
    
    say "$a: $result_or, $result_or2, $result_plus, $result_factored";

    cmpthese (
        5000000,
        {
            or   => sub {use_or ()},
            or2  => sub {use_or2 ()},
            plus => sub {use_plus ()},
            factored => sub {factored ()},
        }
    );

}

done_testing();


sub use_or {
    my $x = $a || $b and $a || $c;
}

sub use_or2 {
    my $x = ($a || $b) && ($a || $c);
}

sub factored {
    my $x = $a || ($b && $c);
}

sub use_plus {
    my $x = $a + $b and $a + $c;
}

