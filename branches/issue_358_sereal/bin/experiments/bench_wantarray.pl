
use Benchmark qw {:all};
use 5.016;
use Data::Dumper;
use Scalar::Util qw /reftype/;

#use List::Util qw {:all};

my @vals = 1 .. 200;
my $self = {PARAMS => {label_hash1 => 5, @vals}};

#my $n = 1000;
#my @a1 = (0 .. $n);

my $param = 'label_hash1';

$| = 1;


cmpthese (
    -3,
    {
        wa => sub {scalar use_wantarray()},
        hr => sub {scalar return_hashref()},
        #h  => sub {scalar return_hash()},
        b  => sub {scalar bare()},
        bh => sub {scalar bare_hashref()},
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

sub bare_hashref {
    $self;
}