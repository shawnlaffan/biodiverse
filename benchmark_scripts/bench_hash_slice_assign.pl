
use Benchmark qw {:all};
use 5.016;

use Biodiverse::Config;
use Biodiverse::Tree;
use Math::Random::MT::Auto;

$| = 1;

my $tree_file = 'test_tree.bts';

my $tree = Biodiverse::Tree->new (file => $tree_file);
my $root = $tree->get_root_node;

my %label_hash = $root->get_terminal_elements;
my @labels = sort keys %label_hash;

my $prng1 = Math::Random::MT::Auto->new(seed => 222);
my $prng2 = Math::Random::MT::Auto->new(seed => 222);
my $prng3 = Math::Random::MT::Auto->new(seed => 222);

my $path_cache1 = {};
my $path_cache2 = {};
my $path_cache3 = {};
my $all_nodes  = $tree->get_node_hash;
my $cache = 1;


my $check_count = 1000;

setup();

if (1) {
    use Test::More;
    #  trigger the path caches for all terminals
    #  to take the cache out of the equation
    $check_count = scalar @labels - 1;  
    my $first_idx = first_idx();
    my $slice_assign = slice_assign();
    my $last_if = last_if();
    is_deeply ($first_idx, $slice_assign, 'outputs match, slice_assign & first_idx');
    is_deeply ($last_if, $slice_assign, 'outputs match, slice_assign & last_if');
    done_testing;
}


foreach my $count (10, 50, 100, 300, 500, 1000) {
    $check_count = $count;
    print "\nCheck count is $check_count\n";
    cmpthese (
        -5,
        {
            first_idx  => sub {first_idx()},
            slice_full => sub {slice_assign()},
            last_if    => sub {last_if()},
        }
    );
}


sub slice_assign {
    my %path;
    my $shuffled = $prng1->shuffle([@labels]);
    
    foreach my $label (@$shuffled[0..$check_count]) {
        #  Could assign to $current_node here, but profiling indicates it
        #  takes meaningful chunks of time for large data sets
        my $sub_path = $path_cache1->{$all_nodes->{$label}};

        if (!$sub_path) {
            my $current_node = $all_nodes->{$label};
            $sub_path = $current_node->get_path_lengths_to_root_node (cache => $cache);
            $path_cache1->{$current_node} = $sub_path;
        }

        #  This is a bottleneck for large data sets.
        #  A binary search to reduce the slice assignments did not speed things up,
        #  but possibly it was not well implemented.
        @path{keys %$sub_path} = undef;
    }
    
    return \%path;
}


sub first_idx {
    my %path;
    
    my $shuffled = $prng2->shuffle([@labels]);
    foreach my $label (@$shuffled[0..$check_count]) {
        #  Could assign to $current_node here, but profiling indicates it
        #  takes meaningful chunks of time for large data sets
        my $sub_path = $path_cache2->{$all_nodes->{$label}};
        if (!$sub_path) {
            my $current_node = $all_nodes->{$label};
            #$sub_path = $current_node->get_path_lengths_to_root_node (cache => $cache);
            $sub_path = $current_node->get_path_to_root_node (cache => $cache);
            my @p = map {$_->get_name} @$sub_path;
            $sub_path = \@p;
            $path_cache2->{$current_node} = $sub_path;
        }

        if (!scalar keys %path) {
            @path{@$sub_path} = ();
        }
        else {
            my $i = List::MoreUtils::firstidx {exists $path{$_}} @$sub_path;
            @path{@$sub_path[0..$i-1]} = ();
        }

    }
    
    return \%path;
}

sub last_if {
    my %path;
    
    my $shuffled = $prng3->shuffle([@labels]);
    foreach my $label (@$shuffled[0..$check_count]) {
        #  Could assign to $current_node here, but profiling indicates it
        #  takes meaningful chunks of time for large data sets
        my $sub_path = $path_cache3->{$all_nodes->{$label}};
        if (!$sub_path) {
            my $current_node = $all_nodes->{$label};
            #$sub_path = $current_node->get_path_lengths_to_root_node (cache => $cache);
            $sub_path = $current_node->get_path_to_root_node (cache => $cache);
            my @p = map {$_->get_name} @$sub_path;
            $sub_path = \@p;
            $path_cache3->{$current_node} = $sub_path;
        }

        if (!scalar keys %path) {
            @path{@$sub_path} = ();
        }
        else {
            foreach my $node_name (@$sub_path) {
                last if exists $path{$node_name};
                $path{$node_name} = undef;
            }
        }

    }
    
    return \%path;
}

#  pregenerate the caching on the tree
sub setup {
    foreach my $label (@labels) {
        my $current_node = $all_nodes->{$label};
        my $sub_path = $current_node->get_path_lengths_to_root_node (cache => $cache);
        $sub_path = $current_node->get_path_to_root_node (cache => $cache);
    }
}


__END__


ok 1 - outputs match, slice_assign & first_idx
ok 2 - outputs match, slice_assign & last_if
1..2

Check count is 10
             Rate  first_idx    last_if slice_full
first_idx  2137/s         --       -18%       -24%
last_if    2596/s        21%         --        -7%
slice_full 2804/s        31%         8%         --

Check count is 50
             Rate  first_idx slice_full    last_if
first_idx  1163/s         --       -33%       -39%
slice_full 1731/s        49%         --        -9%
last_if    1904/s        64%        10%         --

Check count is 100
             Rate  first_idx slice_full    last_if
first_idx   885/s         --       -11%       -37%
slice_full  992/s        12%         --       -29%
last_if    1406/s        59%        42%         --

Check count is 300
            Rate  first_idx slice_full    last_if
first_idx  364/s         --       -12%       -49%
slice_full 414/s        14%         --       -42%
last_if    713/s        96%        72%         --

Check count is 500
            Rate  first_idx slice_full    last_if
first_idx  238/s         --       -27%       -55%
slice_full 327/s        38%         --       -38%
last_if    531/s       123%        62%         --

Check count is 1000
            Rate  first_idx slice_full    last_if
first_idx  124/s         --       -27%       -46%
slice_full 171/s        38%         --       -26%
last_if    232/s        87%        36%         --
