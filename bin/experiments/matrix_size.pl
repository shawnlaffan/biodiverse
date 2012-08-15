#!/usr/bin/perl -w
use strict;
use warnings;

local $| = 1;

use Biodiverse::Matrix;

use Devel::Size qw /total_size/;

my $rand = 1;
srand (23);


#my $max = 1000;
foreach my $max (100, 1000, 1500) {
    print "max is $max\n";
    foreach my $rand (0, 1) {
        my $bmx = Biodiverse::Matrix->new (NAME => 'checker');
        my $mx_hash = {};
        my $valsub = $rand ? sub {return rand()} : sub {return shift};
    
        foreach my $i (1 .. $max) {
            #print "$i\n";
            foreach my $j (1 .. $max) {
                next if $j < $i;
                my $value = &$valsub($i);
                $mx_hash->{$i}{$j} = $i;
                $bmx->add_element(
                    element1 => $i,
                    element2 => $j,
                    value    => $value);
            }
        }
        print "\tRand is $rand\n";
        my $sz_bmx  = total_size ($bmx);
        my $sz_hash = total_size ($mx_hash);
        printf "\tB::MX is %10i\n", $sz_bmx;
        printf "\thash is  %10i\n", $sz_hash;
        printf "\tratio is %f\n", $sz_bmx / $sz_hash;
    }
}