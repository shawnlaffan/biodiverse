
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


cmpthese (
    -3,
    {
        wa => sub {use_wantarray()},
        hr => sub {return_hashref()},
        h  => sub {return_hash()},
        b  => sub {bare()},
    }
);


sub use_wantarray {
    return wantarray ? %$self : $self;
}

sub return_hashref {
    return $self;
}

sub return_hash {
    return %$self;
}

sub bare {
    wantarray ? %$self : $self;
}