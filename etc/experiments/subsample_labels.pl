use 5.010;
use Biodiverse::BaseData;
use Math::Random::MT::Auto;


sub test_subsample_labels {
    my $c = 0;
    my $bd = Biodiverse::BaseData->new (
        NAME => 'subsample labels',
        CELL_SIZES => [$c],
    );
    my $mrma = Math::Random::MT::Auto->new (seed => 2345);
    my $csv = $bd->get_csv_object;
    my $cum_sum_orig;
    foreach my $label ('a' .. 'd') {
        foreach my $group (0..5) {
            my $smp_count = $mrma->rand() * 10;
            $cum_sum_orig += $smp_count;
            $bd->add_element (
                label => $label,
                group => $group,
                count => $smp_count,
                csv   => $csv,
            );
        }
    }
    
    my $cum_sum_new = 0;
    my @data;
    my @sums;
    foreach my $label (sort $bd->get_labels) {
        my $gp_hash = $bd->get_groups_with_label_as_hash (
            label => $label,
        );
        foreach my $group (sort keys %$gp_hash) {
            my $prev = $cum_sum_new;
            $cum_sum_new += $gp_hash->{$group};
            push @data, [$prev, $cum_sum_new, $label, $group];
            push @sums,  $cum_sum_new;
        }
    }
    
    my @sorted = sort {$a->[0] <=> $b->[0]} @data;
    
    is ($cum_sum_new, $cum_sum_orig, 'cumulative sums match');
    
    is_deeply (
        [sort {$a <=> $b} @sums],
        [map  {$_->[1]} @sorted],
        'sorted list is as expected',
    );
    
    foreach my $i (1..5) {
        my $target = $mrma->rand * $cum_sum_new;
        say "target: $target";
        my ($iter) = List::MoreUtils::bsearchidx
            {  $target <  $_->[0] ?  1
             : $target >= $_->[1] ? -1
             : 0
            }
            @data;
        ok (   $data[$iter][0] < $target
            && $data[$iter][1] > $target,
            "iter for $target falls in expected bounds"
        );
        #  need book keeping to recalculate the data array when we have a removal
        #  in which case a linear search with offsets might be simpler
        #  since we have to iterate over half of the array on average anyway
        #  (with splice on empty)
        #  Could also use a tombstone approach with multiple passes
        #  and a trigger to rebuild 
        #say "iter $iter";
        #say join ', ', @{$data[$iter]};
        #say ' ';
    }
}
