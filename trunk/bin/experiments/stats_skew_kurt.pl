#!/usr/bin/perl -w
use strict;
use warnings;
use 5.010;
use Carp;

use Benchmark qw(:all :hireswallclock) ;

use List::Util;
use List::MoreUtils;

$| = 1;

#my $d_hash1 = get_data(100, 2);
#my $d_hash2 = get_data(50,  2);
#say join " ", old_school (label_hash1 => $d_hash1, label_hash2 => $d_hash2);
#say join " ", new_school (label_hash1 => $d_hash1, label_hash2 => $d_hash2);




my @data_size_and_reps = (
    [100   => -1],   #  short sequence, many benchmark reps
    [1000  => -1],   #  mid range sequence, many benchmark reps
    [100000 => -1],
);


foreach my $pair (@data_size_and_reps) {
    my $n    = $pair->[0];
    my $reps = $pair->[1];
    say '=' x 30;
    for my $iter (1 .. 5) {
        say '=' x 30;
        say "Data size: $n, reps: $reps, iter: $iter";

        my $d_hash1 = get_data($n, $iter);
    
        cmpthese($reps, {
            'Old School' => sub {old_school (data => $d_hash1)},
            'New School' => sub {new_school (data => $d_hash1)},
        });
    }
}

say '=' x 30;
say "Completed";

sub old_school {
    my %args = @_;
    
    my $data = $args{data};
    
    my $mean = 0.1;
    my $sd   = 0.1;

    my @tmp = List::MoreUtils::apply { $_ = (($_ - $mean) / $sd) ** 4 } @$data;
    my $sum_pow4 = List::Util::sum @tmp;

}

sub new_school {
    my %args = @_;

    my $mean = 0.1;
    my $sd   = 0.1;

    my $data = $args{data};

    my $sum_pow4 = List::Util::sum map { (($_ - $mean) / $sd) ** 4 } @$data;

}


sub get_data {
    my $n    = shift || 1000;
    my $seed = shift;

    if ($seed) {
        say "Seeding PRNG with $seed";
        srand $seed;
    };

    my @data;
    for my $i (1 .. $n) {
        push @data, rand();
    }
    
    #say "Generated $n records";

    return wantarray ? @data : \@data;
}
