
use Benchmark qw {:all};
use 5.016;
use Data::Dumper;
use Scalar::Util qw /reftype/;

#use List::Util qw {:all};

my @vals = 1 .. 20;
my $self = {PARAMS => {label_hash1 => 5, @vals}};

#my $n = 1000;
#my @a1 = (0 .. $n);

my $param = 'label_hash1';

$| = 1;

#$self = [];

say (((ref $self) =~ /HASH/) ? 1 : 0);
say (reftype ($self) eq 'HASH' ? 1 : 0);


cmpthese (
    -3,
    {
        old1 => sub {(ref $self) =~ /HASH/},
        new1 => sub {reftype ($self) eq 'HASH'},
    }
);
