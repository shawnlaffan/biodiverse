use strict;
use warnings;
use 5.010;
use Carp;

use Benchmark qw(:all :hireswallclock) ;

use List::Util;
use List::MoreUtils;

$| = 1;

#my $data = get_data(100, 2);
#my $d_hash2 = get_data(50,  2);
#say join " ", old_school (label_hash1 => $data, label_hash2 => $d_hash2);
#say join " ", new_school (label_hash1 => $data, label_hash2 => $d_hash2);

use constant POWER => 3;
my $mean = 1 / 3;
my $sd = 1 / 7;


my @data_size_and_reps = (
    [100   => -1],   #  short sequence
    [1000  => -1],   #  mid range sequence
    #[100000 => -1],
);


foreach my $pair (@data_size_and_reps) {
    my $n    = $pair->[0];
    my $reps = $pair->[1];
    say '=' x 30;
    for my $iter (1 .. 5) {
        say '=' x 30;
        say "Data size: $n, reps: $reps, iter: $iter";

        my $data = get_data($n, $iter);
    
        cmpthese($reps, {
            'Pre School' => sub {pre_school (data => $data)},
            #'Old School' => sub {old_school (data => $data)},
            #'New School' => sub {new_school (data => $data)},
            'Day Care'   => sub {day_care   (data => $data)},
        });
    }
}

say '=' x 30;
say "Completed";

sub day_care {
    my %args = @_;
    
    my $data = $args{data};

    my $sum_pow4;
    foreach my $rec ( @$data ) {
        my $val = (($rec - $mean) / $sd) ** POWER;
        $sum_pow4 += $val;
    }

}


sub pre_school {
    my %args = @_;
    
    my $data = $args{data};
    
    my $sum_pow4;
    foreach my $rec ( @$data ) {
        $sum_pow4 +=  (($rec - $mean) / $sd) ** POWER;
    }

}


sub old_school {
    my %args = @_;
    
    my $data = $args{data};

    my @tmp = List::MoreUtils::apply { $_ = (($_ - $mean) / $sd) ** POWER } @$data;
    my $sum_pow4 = List::Util::sum @tmp;

}

sub new_school {
    my %args = @_;

    my $data = $args{data};

    my $sum_pow4 = List::Util::sum map { (($_ - $mean) / $sd) ** POWER } @$data;

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
