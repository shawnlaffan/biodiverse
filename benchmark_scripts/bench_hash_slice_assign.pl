
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

my $path_cache1 = {};
my $path_cache2 = {};
my $all_nodes  = $tree->get_node_hash;
my $cache = 1;


my $check_count = 1000;

setup();

if (0) {
    use Test::More;
    my $fst = fst();
    my $slice_assign = slice_assign();
    is_deeply ($fst, $slice_assign, 'outputs match');
    done_testing;
}


cmpthese (
    -5,
    {
        first_idx  => sub {fst()},
        slice_full => sub {slice_assign()},
    }
);


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


sub fst {
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
            @path{@$sub_path} = undef;
        }
        else {
            my $i = List::MoreUtils::firstidx {exists $path{$_}} @$sub_path;
            @path{@$sub_path[0..$i-1]} = undef;
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
