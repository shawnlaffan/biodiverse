
use Benchmark qw {:all};
#use List::Util qw {:all};

my $n = 1000;
my $min = -500;
my @a1 = ($min .. ($min + $n));
my @a2 = (0 .. $n);

my (%hash1, %hash2);

@hash1{@a1} = (@a2);
@hash2{@a1} = (@a2);

my %args = (label_hash1 => \%hash1, label_hash2 => \%hash2);

cmpthese (
    200,
    {
        a => sub {sub2 (%args)},
        b => sub {sub1 (%args)},
    }
);




sub sub2 {
    my %args = @_;
    
    my $label_list1     = $args{label_hash1};
    my $label_list2     = $args{label_hash2};

    my ($sumX, $sum_absX, $sumXsqr, $count) = (undef, undef, undef, 0);

    #  should look into using PDL to handle this, as it will be much, much faster
    #  (but it will use more memory, which will be bad for large label lists)
    BY_LABEL1:
    while (my ($label1, $count1) = each %{$label_list1}) {

        BY_LABEL2:
        while (my ($label2, $count2) = each %{$label_list2}) {

            my $value = $label1 - $label2;
            my $joint_count = $count1 * $count2;

            #  tally the stats
            $sumX     += $value * $joint_count;
            $sum_absX += abs($value) * $joint_count;
            $sumXsqr  += $value ** 2 * $joint_count;
            $count    += $joint_count;
        }
    }
}

sub sub1 {
    my %args = @_;
    
    my $label_list1     = $args{label_hash1};
    my $label_list2     = $args{label_hash2};

    my ($sumX, $sum_absX, $sumXsqr, $count) = (undef, undef, undef, 0);

    #  should look into using PDL to handle this, as it will be much, much faster
    #  (but it will use more memory, which will be bad for large label lists)
    BY_LABEL1:
    while (my ($label1, $count1) = each %{$label_list1}) {

        BY_LABEL2:
        while (my ($label2, $count2) = each %{$label_list2}) {

            my $value = $label1 - $label2;
            my $joint_count = $count1 * $count2;

            #  tally the stats
            my $x = $value * $joint_count;
            $sumX     += $x;
            $sum_absX += abs($x);
            $sumXsqr  += $value ** 2 * $joint_count;
            $count    += $joint_count;
        }
    }
}
