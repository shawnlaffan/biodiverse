
use Benchmark qw {:all};
#use List::Util qw {:all};

my $self = {PARAMS => {}};

my $n = 1000;
my @a1 = (0 .. $n);

my (%hash1);

@hash1{@a1} = @a1;
my %hargs = (label_hash1 => \%hash1);

cmpthese (
    3000000,
    {
        old1 => sub {old1 ($self, %hargs)},
        old2 => sub {old2 ($self, %hargs)},
        new  => sub {new1 ($self, %hargs)},
    }
);


sub old1 {
    my $self = shift;
    my %args = @_;
    
    while (my ($key, $value) = each %args) {
        $self->{PARAMS}{$key} = $value;
    }
    
    return scalar %args;
}

sub old2 {
    my $self = shift;
    my %args = @_;
    
    while (my ($key, $value) = each %args) {
        $self->{PARAMS}{$key} = $value;
    }
    
    return 1;
}

sub new1 {
    my $self = shift;
    
    $self->{PARAMS}{$_[0]} = $_[1];

    return 1;
}
