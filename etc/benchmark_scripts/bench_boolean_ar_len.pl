
use Benchmark qw {:all};
use 5.016;

my @arr  = (1,2,3);
my $aref = [1,2,3];
my $aa   = 1;

$| = 1;


cmpthese (
    -1,
    {
        scr  => sub {if (scalar @$aref) {my $x = 1}},
        sc   => sub {if (scalar @arr) {my $x = 1}},
        bcr  => sub {if (@$aref) {my $x = 1}},
        base => sub {if ($aa) {my $x = 1}},
        bc   => sub {if (@arr) {my $x = 1}},
    }
);


__END__
