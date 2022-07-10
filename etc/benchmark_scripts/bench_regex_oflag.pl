use 5.016;
use warnings;
use Benchmark qw {:all};

#use Data::Dumper;
use Regexp::Common qw /number delimited/;

use constant CONST_RE_NUMCAPTURE => qr /\G ($RE{num}{real})/xmso;

my $RE_NUMBER = qr /$RE{num}{real}/xmso;
my $RE_QUOTED = qr /$RE{delimited}{-delim=>"'"}{-esc=>"'"}/o;

my $RE_NUM_CAPTURE = qr /\G ( $RE_NUMBER ) /xs;

my $string = '12335567j';

cmpthese (
    -5,
    {
        orig  => sub {orig ()},
        oflag => sub {oflag()},
        qcapt => sub {qcapt()},
        qcapo => sub {qcapto()},
        ccapo => sub {ccapto()},
    },
);



sub orig {
    for (1..10000) {
        $string =~ m/\G ( $RE_NUMBER ) /xgcs;
    }
}

sub oflag {
    for (1..10000) {
        $string =~ m/\G ( $RE_NUMBER ) /xgcso;
    }
}

sub qcapt {
    for (1..10000) {
        $string =~ m/$RE_NUM_CAPTURE/gc;
    }
}

sub qcapto {
    for (1..10000) {
        $string =~ m/$RE_NUM_CAPTURE/gco;
    }
}

sub ccapto {
    for (1..10000) {
        $string =~ m/${\CONST_RE_NUMCAPTURE()}/gc;
    }
}
