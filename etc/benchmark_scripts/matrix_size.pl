use strict;
use warnings;

local $| = 1;

use Biodiverse::Matrix;

use Devel::Size qw /total_size/;

my $rand = 1;
srand (23);

sub bytes_to_megabytes {
    my $val = shift;
    my $conv = 1024 * 1024;
    return $val / $conv;
}

my $use_bmx = 0;
my @use_rand = (0); #  or (0, 1)

#my $max = 1000;
foreach my $max (100, 1000, 3000, 5000) {
    print "max is $max\n";
    foreach my $rand (@use_rand) {
        my $bmx = $use_bmx && $max <= 1500 ? Biodiverse::Matrix->new (NAME => 'checker') : undef;
        my $mx_hash = {};
        my $valsub = $rand ? sub {return rand()} : sub {return shift};
    
        foreach my $i (1 .. $max) {
            #print "$i\n";
            foreach my $j (1 .. $max) {
                next if $j < $i;
                my $value = &$valsub($i);
                $mx_hash->{$i}{$j} = $i;
                eval {
                    $bmx->add_element(
                        element1 => $i,
                        element2 => $j,
                        value    => $value,
                    );
                };
            }
        }
        print "\tRand is $rand\n";
        my $sz_bmx  = total_size ($bmx);
        my $sz_hash = total_size ($mx_hash);
        printf "\tB::MX is %10.3f MiB\n", bytes_to_megabytes $sz_bmx;
        printf "\thash  is %10.3f MiB\n", bytes_to_megabytes $sz_hash;
        printf "\tratio is %10.3f\n", $sz_bmx / $sz_hash;
    }
}

