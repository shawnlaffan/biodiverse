use 5.016;

use List::BinarySearch qw { :all };


my @array = 1..10;
my %hash  = 6..11;

say join ' ', sort {$a <=> $b} keys %hash;
say join ' ', @array;

my $last_idx = binsearch_pos
    {
        #say "$a, $b, " . exists $hash{$b};
        exists $hash{$b} ? 1 : 0
    } 'blurg', @array;

#if (!exists $hash{$array[$last_idx]}) {
    $last_idx -= 3;
#}

say $last_idx;

