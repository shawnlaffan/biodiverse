
use Benchmark qw {:all};
use 5.016;

$| = 1;


cmpthese (
    -3,
    {
        named => sub {named_arg_vars(1, 2, 3, 4)},
        anon  => sub {anon_arg_vars (1, 2, 3, 4)},
    }
);


sub named_arg_vars {
    my ($aa, $ab, $ac, $ad) = @_;
    my  @arr = ($aa, $ab, $ac, $ad);
    return 1;
}

sub anon_arg_vars {
    my  @arr = ($_[0], $_[1], $_[2], $_[3]);
    return 1;
}


__END__

#  results:
           Rate named  anon
named 1836037/s    --  -31%
anon  2654837/s   45%    --


