use strict;
use warnings;
use 5.010;
use Carp;

use Benchmark qw(:all :hireswallclock) ;

use List::Util;
use List::MoreUtils;

$| = 1;

my $d_hash1 = get_data(100, 2);
my $d_hash2 = get_data(50,  2);
say join " ", old_school (label_hash1 => $d_hash1, label_hash2 => $d_hash2);
say join " ", new_school (label_hash1 => $d_hash1, label_hash2 => $d_hash2);




my @data_size_and_reps = (
    [100   => 1000],   #  short sequence, many benchmark reps
    #[1000  => 100],   #  mid range sequence, many benchmark reps
    #[10000 => 10],
);


foreach my $pair (@data_size_and_reps) {
    my $n    = $pair->[0];
    my $reps = $pair->[1];
    say '=' x 30;
    for my $iter (1 .. 5) {
        say '=' x 30;
        say "Data size: $n, reps: $reps, iter: $iter";

        my $d_hash1 = get_data($n, $iter);
        my $d_hash2 = get_data($n / 2, $iter);
    
        cmpthese($reps, {
            'Old School' => sub {old_school (label_hash1 => $d_hash1, label_hash2 => $d_hash2)},
            'New School' => sub {new_school (label_hash1 => $d_hash1, label_hash2 => $d_hash2)},
        });
    }
}

say '=' x 30;
say "Completed";

sub old_school {
    my %args = @_;
    
    my %label_list1     = %{$args{label_hash1}};
    my %label_list2     = %{$args{label_hash2}};

     my ($sum_X, $sum_abs_X, $sum_X_sqr, $count) = (undef, undef, undef, 0);
    my $i = 0;
    
    BY_LABEL1:
    while (my ($label1, $count1) = each %label_list1) {

        #$i ++;
        #say $i;

        BY_LABEL2:
        while (my ($label2, $count2) = each %label_list2) {

            my $value = $label1 - $label2;
            my $joint_count = $count1 * $count2;

            #  tally the stats
            my $x      = $value * $joint_count;
            #$sum_X     += $x;
            $sum_abs_X += abs($x);
            $sum_X_sqr  += $value ** 2 * $joint_count;
            $count    += $joint_count;
        }
    }
    
    return (sum_absX => $sum_abs_X, sumXsqr => $sum_X_sqr, count => $count);
}

sub new_school {
    my %args = @_;

    my $list1 = $args{label_hash1};
    my $list2 = $args{label_hash2};
    #  make %$l1 the shorter, as it is used in the while loop
    if (scalar keys %$list1 > scalar keys %$list2) {  
        $list1 = $args{label_hash2};
        $list2 = $args{label_hash1};
    }

    my %label_list1 = %$list1;
    my %label_list2 = %$list2;

    my ($sum_abs_X, $sum_X_sqr, $count) = (undef, undef, 0);


    BY_LABEL1:
    while (my ($label1, $count1) = each %label_list1) {

        my @abs_diff_list  = List::MoreUtils::apply { $_ = abs($_ - $label1) } keys %label_list2;
        my @ssq_list       = List::MoreUtils::apply { $_ **= 2 } @abs_diff_list;
        my @joint_count    = List::MoreUtils::apply { $_ *= $count1 } values %label_list2;
        my @wtd_adiff_list = List::MoreUtils::pairwise {$a * $b} @abs_diff_list, @joint_count;
        my @wtd_ssq_list   = List::MoreUtils::pairwise {$a * $b} @ssq_list, @joint_count;

        $sum_abs_X += List::Util::sum @wtd_adiff_list;
        $sum_X_sqr  += List::Util::sum @wtd_ssq_list;
        $count    += List::Util::sum @joint_count;
    }
    
    return (sum_absX => $sum_abs_X, sumXsqr => $sum_X_sqr, count => $count);
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
    #@data = 1 .. $n;
    my %hash;
    @hash{@data} = (1 .. scalar @data);
    
    #say "Generated $n records";

    return wantarray ? %hash : \%hash;
}
