
use Benchmark qw {:all};
use 5.016;


$| = 1;


my $check_count = 1000;

my $numerator = 5;
my $x;

no warnings 'uninitialized';

foreach my $denominator (undef, qw /0 1 3 1000/){
    
    cmpthese (
        -1,
        {
            eval    => sub {$x = eval {$denominator / $numerator} || 0},
            ternary => sub {$x = $denominator ? ($numerator / $denominator) : 0},
            ifelse  => sub {if ($denominator) {$x = $numerator / $denominator} else {$x = 0}},
        }
    );

}

