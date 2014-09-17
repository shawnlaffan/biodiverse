
use Benchmark qw {:all};
use 5.016;

$| = 1;


cmpthese (
    -3,
    {
        er => sub {rand(); return},
        nr => sub {rand(); },
    }
);


__END__

#  results:
50_000_000
        Rate   er   nr
er 20517029/s   -- -45%
nr 37202381/s  81%   --

-3
         Rate   er   nr
er 18205338/s   -- -52%
nr 37690645/s 107%   --
