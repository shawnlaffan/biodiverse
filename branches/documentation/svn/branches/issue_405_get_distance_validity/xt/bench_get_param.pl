#  benchmark direct repeated use of list2csv or using a hash structure with a cache

use 5.016;

use Carp;
use Scalar::Util qw /reftype/;
use rlib '../lib', '../t/lib';

use English qw / -no_match_vars /;
local $| = 1;


use Biodiverse::BaseData;

use Benchmark qw {:all};

my $bd = Biodiverse::BaseData->new (name => 'kk');
$bd->set_param (BARRY => 1);

cmpthese (
    -10,
    {
        mk1 => sub {mk1($bd, 'BARRY')},
        mk2 => sub {mk2($bd, 'BARRY')},
        mk3 => sub {mk3($bd, 'BARRY')},
        mk4 => sub {mk4($bd, 'BARRY')},
        mk5 => sub {mk5($bd, 'BARRY')},
    }
);


sub mk1 {
    my $self = shift;
    my $key = shift;
    return if ! exists $self->{_cache}{$key};
    return $self->{_cache}{$key};
}

sub mk2 {
    my ($self, $key) = @_;
    return if ! exists $self->{_cache}{$key};
    return $self->{_cache}{$key};
}

sub mk3 {
    return if ! exists $_[0]->{_cache}{$_[1]};
    return $_[0]->{_cache}{$_[1]};
}

sub mk4 {
    my $ref = $_[0]->{_cache};
    return if ! exists $ref->{$_[1]};
    return $ref->{$_[1]};
}

sub mk5 {
    my $ref = $_[0]->{_cache};
    if (exists $ref->{$_[1]}) {
        return $ref->{$_[1]};
    }
    else {
        return;
    }
}

