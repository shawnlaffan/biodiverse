
use Benchmark qw {:all};
use 5.016;
use Data::Dumper;

#use List::Util qw {:all};

my @vals = 1 .. 20;
my $self = {PARAMS => {label_hash1 => 5, @vals}};

#my $n = 1000;
#my @a1 = (0 .. $n);

my $param = 'label_hash1';

cmpthese (
    3000000,
    {
        old1 => sub {old1 ($self, $param)},
        new1 => sub {new1 ($self, $param)},
        new2 => sub {new2 ($self, $param)},
        new3 => sub {new3 ($self, $param)},
    }
);


#say Dumper $self;

sub old1 {
    return if ! exists $_[0]->{PARAMS}{$_[1]};
    return $_[0]->{PARAMS}{$_[1]};
}


sub new1 {
    no autovivification;
    return $_[0]->{PARAMS}{$_[1]};
}

sub new2 {
    no autovivification;
    $_[0]->{PARAMS}{$_[1]};
}

sub new3 {
    exists $_[0]->{PARAMS}{$_[1]} && $_[0]->{PARAMS}{$_[1]};
}
