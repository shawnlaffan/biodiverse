use 5.022;
use strict;
use warnings;
use Carp;
use utf8;

use FindBin qw/$Bin/;
use rlib;
use List::Util qw /first sum all/;

use Test2::V0;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Biodiverse::TestHelpers qw /:cluster :basedata :tree/;
use Biodiverse::Cluster;
use Biodiverse::BaseData;

my $default_prng_seed = 2345;

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @test_subs = grep {$_ =~ 'main::test_'} $obj->functions();


exit main( @ARGV );

sub main {
    my @args  = @_;

    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
                if not my $func = (__PACKAGE__->can( 'test_' . $name ) || __PACKAGE__->can( $name ));
            $func->();
        }

        done_testing;
        return 0;
    }

    foreach my $sub (@test_subs) {
        no strict 'refs';
        $sub->();
    }

    done_testing;
    return 0;
}

#  check for leaks - does not need to be part of the standard testing
sub leakcheck_trim_tree {
    #use Test::LeakTrace;
    #if ($@) {
    #    warn 'Test::LeakTrace required for this check';
    #    return;
    #}

    #leaktrace {_chklk()} -verbose;
}

sub _chklk {
    my $tree1 = get_site_data_as_tree();
    my $node_count;
    my $start_node_count = $tree1->get_node_count;
    my @named_nodes    = sort keys %{$tree1->get_named_nodes};
    my @delete_targets = @named_nodes[0..10];
    my @remaining      = @named_nodes[11..$#named_nodes];
    my @keep_targets   = @delete_targets;
    
    #  run some methods which cache
    foreach my $node ($tree1->get_terminal_node_refs) {
        my $path = $node->get_path_to_root_node;
    }

    my %n;

    $tree1->trim (trim => \@delete_targets);

}

sub test_ancestor_by {
    my $tree = get_site_data_as_tree();
$tree->save;
    my $from_name   = '3450000:850000';
    my $target_name = '112___';
    my @terminals = qw /
        3450000:850000  3450000:950000  3450000:1150000
        3550000:950000  3550000:1050000 3550000:1150000
        3650000:1150000 3750000:1350000 3750000:1550000
        3850000:1650000
    /;
    my @internals = qw/
        46___  56___  65___  66___
        77___  94___ 103___ 110___
    /;

    #  check a terminal
    my $from_node = $tree->get_node_ref_aa ($from_name);
    my $d = 4;
    my $ancestor = $from_node->get_ancestor_by_depth_aa($d);
    is $ancestor->get_name,
       $target_name,
       "Got expected ancestor for $from_name at depth above of $d";
    $d = 0.7;
    $ancestor = $from_node->get_ancestor_by_length_aa($d);
    is $ancestor->get_name,
        $target_name,
        "Got expected ancestor for $from_name at length above of $d";

    my $ntips = 10;
    $ancestor = $from_node->get_ancestor_by_ntips_aa($ntips);
    is $ancestor->get_name,
        $target_name,
        "Got expected ancestor for $from_name when looking for $ntips tips";
    $ancestor = $from_node->get_ancestor_by_ntips_aa(-10);
    is $ancestor->get_name,
        $from_node->get_name,
        "Got caller node when ntips is <0";
    $ancestor = $from_node->get_ancestor_by_ntips_aa(10e6);
    is $ancestor->get_name,
        $from_node->get_root_node->get_name,
        "Got root node when ntips exceed the tree's";

    my $target_len_sum
        = List::Util::sum
          map {$tree->get_node_ref (node => $_)->get_length}
          (@terminals, @internals);
    #  set len to be half way along the target branch
    $target_len_sum += 0.5 * $tree->get_node_ref (node => $target_name)->get_length;

    $ancestor = $from_node->get_ancestor_by_sum_of_branch_lengths_aa($target_len_sum);
    is $ancestor->get_name,
        $target_name,
        "Got expected ancestor for $from_name when looking for sum of branch lengths $target_len_sum";
    $ancestor = $from_node->get_ancestor_by_sum_of_branch_lengths_aa(-$target_len_sum);
    is $ancestor->get_name,
        $from_node->get_name,
        "Got caller node when branch length sum target is <0";
    $ancestor = $from_node->get_ancestor_by_sum_of_branch_lengths_aa(10e6);
    is $ancestor->get_name,
        $from_node->get_root_node->get_name,
        "Got root node when branch length sum target exceeds the tree's length";


    #  numbers bigger than tree return the root
    $d = 27;
    my $root = $tree->get_root_node;
    $ancestor = $from_node->get_ancestor_by_depth_aa($d);
    is $ancestor->get_name,
        $root->get_name,
        "Got root node when ancestor depth exceeds tree";
    $ancestor = $from_node->get_ancestor_by_length_aa($d);
    is $ancestor->get_name,
        $root->get_name,
        "Got root node when ancestor length exceeds tree";

    #  now from an internal node (the immediate parent)
    $from_node = $from_node->get_parent;
    $from_name = $from_node->get_name;
    $d = 3;
    $ancestor = $from_node->get_ancestor_by_depth_aa($d);
    is $ancestor->get_name,
        $target_name,
        "Got expected ancestor for $from_name at depth above of $d";
    $d = 0.7 - 0.25;  #  subtract terminal's length
    $ancestor = $from_node->get_ancestor_by_length_aa($d);
    is $ancestor->get_name,
        $target_name,
        "Got expected ancestor for $from_name at length above of $d";

    #  exceptions
    is $from_node->get_ancestor_by_depth_aa(-1)->get_name, '126___', '-ve ancestor by depth call';
    is $from_node->get_ancestor_by_length_aa(-0.025)->get_name, '123___', '-ve ancestor by length call';
}


sub test_is_ultrametric {
    my $tree = Biodiverse::Tree->new (NAME => 'ultron');
    #  bifurcating number scheme
    my @nums = qw /1 2 3 4 5 6 7 14 15/;
    my %nodes;
    for my $num (@nums) {
        my $node = $tree->add_node(name => $num, length => 1);
        $nodes{$num} = $node;
    }
    $nodes{1}->add_children(children => [$nodes{2}, $nodes{3}]);
    $nodes{2}->add_children(children => [$nodes{4}, $nodes{5}]);
    $nodes{3}->add_children(children => [$nodes{6}, $nodes{7}]);
    $nodes{7}->add_children(children => [$nodes{14}, $nodes{15}]);

    is ($tree->is_ultrametric, 0, 'tree is not ultrametric');
    
    $tree->delete_node (node => 14);
    $tree->delete_node (node => 15);
    is ($tree->is_ultrametric, 1, 'tree is ultrametric');
    
}

sub test_get_siblings {
    my $tree = Biodiverse::Tree->new (NAME => 'siblonian');
    #  bifurcating number scheme
    my @nums = qw /1 2 3 4 5 6 7 14 15 16/;
    my %nodes;
    for my $num (@nums) {
        my $node = $tree->add_node(name => $num, length => 1);
        $nodes{$num} = $node;
    }
    $nodes{1}->add_children(children => [$nodes{2}, $nodes{3}]);
    $nodes{2}->add_children(children => [$nodes{4}, $nodes{5}]);
    $nodes{3}->add_children(children => [$nodes{6}, $nodes{7}]);
    $nodes{7}->add_children(children => [@nodes{14, 15, 16}]);

    is (scalar $nodes{1}->get_siblings, [], 'root has no sibs');
    is ([map {$_->get_name} $nodes{2}->get_siblings],
        [$nodes{3}->get_name],
        'node 2 has one sib',
    );
    is ([map {$_->get_name} $nodes{14}->get_siblings],
        [$nodes{15}->get_name, $nodes{16}->get_name],
        'node 14 has two sibs',
    );
    
}

#  should all be equal for 
sub test_max_path_length {
    my $tree1 = shift || get_site_data_as_tree();
    
    my $root_node = $tree1->get_root_node;
    my $max_path_length = $root_node->get_longest_path_length_to_terminals ();

    my $exp = 0.963138848558473;
    is ($max_path_length, $exp, 'max path length correct for ultrametric tree, root node');

    subtest 'inner node max path lengths correct for ultrametric tree' => sub {
        #  the length for the other nodes should be the difference
        my $node_hash = $tree1->get_node_hash;
        foreach my $node_name (sort keys %$node_hash) {
            my $node_ref = $node_hash->{$node_name};
            my $max_to_terminals = $node_ref->get_longest_path_length_to_terminals ();
            my $path_lengths_to_root = $node_ref->get_path_lengths_to_root_node;
            my $root_path_len    = sum (0, values %$path_lengths_to_root);
            my $exp_inner = $exp - $root_path_len;
            is ($max_path_length, $exp, 'node ' . $node_name);
        }
    };
}

sub test_get_multiple_trees_from_nexus {
    my @array = get_tree_array_from_sample_data();
    is (scalar @array, 2, 'Got two trees from the site data nexus file');
}

sub test_number_terminal_nodes {
    my $tree1 = get_site_data_as_tree();
    my $tree2 = $tree1->clone;
    $tree1->number_terminal_nodes;
    $tree2->_number_terminal_nodes_old_alg;
    my %t1_nodes = $tree1->get_node_hash;
    my %t2_nodes = $tree2->get_node_hash;

    subtest 'Terminal node nums match' => sub {
        foreach my $name (sort keys %t1_nodes) {
            my $node1 = $t1_nodes{$name};
            my $node2 = $t2_nodes{$name};
            foreach my $type (qw /TERMINAL_NODE_FIRST TERMINAL_NODE_LAST/) {
                is (
                    $node1->get_value($type),
                    $node2->get_value($type),
                    "$type matches for $name: "
                        . $node1->get_value($type)
                        . ' '
                        . $node2->get_value($type),
                )
            }
        }
    };
}

sub test_trim_tree {
    my $tree1 = shift || get_site_data_as_tree();
    my $tree2 = $tree1->clone;
    my $tree3 = $tree1->clone;
    my $tree4 = $tree1->clone;

    my $node_count;
    my $start_node_count = $tree1->get_node_count;
    my @named_nodes    = sort keys %{$tree1->get_named_nodes};
    my @delete_targets = @named_nodes[0..10];
    my @remaining      = @named_nodes[11..$#named_nodes];
    my @keep_targets   = @delete_targets;
    
    #  trigger some caching, as we were getting errors due to cached values getting in the way
    foreach my $tree ($tree1, $tree2, $tree3) {
        foreach my $node ($tree->get_node_refs) {
            $node->get_all_descendants;
        }
    }

    my %n;

    #  a litle paranoia
    is ($start_node_count, $tree2->get_node_count,
        'cloned node count is the same as original'
    );
    is ($start_node_count, $tree3->get_node_count,
        'cloned node count is the same as original'
    );
    
    $tree1->trim (trim => \@delete_targets);
    %n = $tree1->get_named_nodes;
    is (scalar keys %n, scalar @remaining, 'trimmers: correct number of named nodes');
    check_trimmings($tree1, \@delete_targets, \@remaining, 'trimmers');
    $node_count = $tree1->get_node_count;
    is ($node_count, $start_node_count - 14, 'trimmers: node count is as expected');

    $tree2->trim (keep => \@keep_targets);
    %n = $tree2->get_named_nodes;
    is (scalar keys %n, scalar @keep_targets, 'keepers: correct number of named nodes');
    check_trimmings($tree2, \@remaining, \@keep_targets, 'keepers');
    $node_count = $tree2->get_node_count;
    is ($node_count, $start_node_count - 204, 'keepers: node counts differ');

    @keep_targets = @delete_targets[0..5];
    $tree3->trim (trim => \@delete_targets, keep => \@keep_targets);
    %n = $tree3->get_named_nodes;
    my $exp_named_remaining = scalar @remaining + scalar @keep_targets;
    is (scalar keys %n, $exp_named_remaining, 'trim/keep: correct number of named nodes');
    my %tmp;
    @tmp{@keep_targets} = (1) x @keep_targets;
    my @exp_deleted = grep {!exists $tmp{$_}} @delete_targets;
    check_trimmings($tree3, \@exp_deleted, \@keep_targets, 'trim/keep');
    $node_count = $tree3->get_node_count;
    is ($node_count, $start_node_count - 5, 'trim/keep: node count is as expected');

    #  need an internal, named node
    #  we should delete some of its descendants but not it
    my $internal_node_to_name
      = $tree4->get_node_ref_aa($delete_targets[0])->get_parent->get_parent;
    $tree4->rename_node (
        old_name => $internal_node_to_name->get_name,
        new_name => 'named_node',
    );
    my %descendants = $internal_node_to_name->get_all_named_descendants;
    my @d    = sort keys %descendants;
    my @dsub = splice @d, 0, 2;
    #push @dsub, 'named_node';
    $tree4->trim (
        keep => \@dsub,
    );
    %n = $tree4->get_named_nodes;
    ok (exists $n{named_node}, 'still have named_node');
    foreach my $deleted (@d) {
        ok (!exists $n{$deleted}, "deleted $deleted");
    }
    foreach my $kept (@dsub) {
        ok (exists $n{$kept}, "kept $kept");
    }

}

sub test_trim_tree_after_adding_extras {
    my $tree1 = shift || get_tree_object_from_sample_data();
    my $bd    = shift || get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);

    my $tree2 = $tree1->clone;
    my $root = $tree2->get_root_node;
    use Biodiverse::TreeNode;
    my $node1 = Biodiverse::TreeNode-> new (
        name   => '00EXTRA_NODE 1',
        length => 1,
    );
    my $node2 = Biodiverse::TreeNode-> new (
        name   => '00EXTRA_NODE 2',
        length => 1,
    );
    $root->add_children (children => [$node1, $node2]);
    #  add it to the Biodiverse::Tree object as well so the trimming works
    $tree2->add_node (node_ref => $node1);
    $tree2->add_node (node_ref => $node2);

    $tree2->trim (keep => scalar $bd->get_labels);
    my $name = $tree2->get_param('NAME') // 'noname';
    $tree2->rename(new_name => $name . '_trimmed');

    ok (
        $tree1->trees_are_same (comparison => $tree2),
        'trimmed and original tree same after trimming extra added nodes'
    );

}

sub test_insert_into_lineage {
    my $tree = Biodiverse::Tree->new;
    #  bifurcating tree - each node has children n*2, n*2+1 
    my @names = qw /1 2 3 4 5 6 7 8 9 10 11/;
    foreach my $name (@names) {
        my $node = $tree->add_node (name => $name, length => 1);
    }
    foreach my $node ($tree->get_node_refs) {
        my $name = $node->get_name;
        my $c1 = $name * 2;
        my $c2 = $name * 2 + 1;
        foreach my $child_name ($c1, $c2) {
            if ($tree->exists_node (name => $child_name)) {
                my $child_node = $tree->get_node_ref_aa ($child_name);
                $node->add_children (children => [$child_node]);
            }
        }
    }
    
    my @sorted_terminal_node_refs = $tree->get_terminal_node_refs_sorted_by_name;
    my $target1 = $sorted_terminal_node_refs[0];
    my $target2 = $sorted_terminal_node_refs[5];
    my $target3 = $sorted_terminal_node_refs[2];
    
    my $insert_name1 = 'insert1';
    my $expected_name1 = '3 ancestral split';
    my $lineage = $target1->get_path_to_root_node;
    my @expected_names = map {$_->get_name} @$lineage;
    splice @expected_names, 2, 0, $expected_name1;
    my $new1 = Biodiverse::TreeNode->new (
        name   => $insert_name1,
        length => 1.5,
    );
    $tree->splice_into_lineage (
        new_node => $new1,
        target_node => $target1,
    );
    #$target1->delete_cached_values;
    ok $tree->exists_node (name => $insert_name1), 'tree contains new node';
    ok $tree->exists_node (node_ref => $new1->get_parent), 'tree contains new node parent';
    is ($target1->get_parent->get_length, 0.5, 'got expected length');
    $lineage = $target1->get_path_to_root_node;
    my @got_names = map {$_->get_name} @$lineage;
    
    is
      \@got_names,
      \@expected_names,
      'got expected names in lineage after first splice';

    $lineage = $new1->get_path_to_root_node;
    @got_names = map {$_->get_name} @$lineage;
    #diag join ' : ', @got_names;
    is
      \@got_names,
      ['insert1', '3 ancestral split', '1'],
      'got expected lineage names for newly inserted node';
    
    
    #  too long, so should become a child of the root node
    my $insert_name2 = '?? ancestral split';
    $lineage = $target2->get_path_to_root_node;
    @expected_names = map {$_->get_name} @$lineage;
    #splice @expected_names, -1, 0, $insert_name2;
    my $new2 = Biodiverse::TreeNode->new (
        name   => $insert_name2,
        length => 1001.5,
    );
    $tree->splice_into_lineage (
        new_node => $new2,
        target_node => $target2,
    );
    $lineage = $target2->get_path_to_root_node;
    @got_names = map {$_->get_name} @$lineage;
    
    is
      \@got_names,
      \@expected_names,
      'got expected names in lineage after splice of long branch';

    #  check lineages fail (until we implement them)
    my $new3 = Biodiverse::TreeNode->new (
        name   => 'lineage_root',
        length => 1.5,
    );
    my $new4 = Biodiverse::TreeNode->new (
        name   => 'lineage_child',
        length => 1.5,
    );
    $new3->add_children (children => [$new4]);
    eval {
        $tree->splice_into_lineage (
            target_node => $target3,
            new_node    => $new3,
        );
    };
    my $e = $@;
    ok ($e, 'got an error splicing a lineage into a tree');
    
    return;
}



sub test_trim_tree_to_lca {
    my $tree = Biodiverse::Tree->new;
    #  bifurcating tree - each node has children n*2, n*2+1 
    my @keepers = qw /1 2 3 4 5 6 7 8 9 10 11/;
    foreach my $name (@keepers) {
        my $node = $tree->add_node (name => $name, length => 1);
    }
    foreach my $node ($tree->get_node_refs) {
        my $name = $node->get_name;
        my $c1 = $name * 2;
        my $c2 = $name * 2 + 1;
        foreach my $child_name ($c1, $c2) {
            if ($tree->exists_node (name => $child_name)) {
                my $child_node = $tree->get_node_ref_aa ($child_name);
                $node->add_children (children => [$child_node]);
            }
        }
    }

    my $orig_root = $tree->get_root_node;
    is ($orig_root->get_depth, 0, 'orig root depth is zero');

    #  add some dangling parents
    my $root = $tree->get_root_node;
    for my $uppers (qw /a b c/) {
        my $node = $tree->add_node (name => $uppers, length => 1);
        $node->add_children(children => [$root]);
        $root = $node;
    }

    #  clear the depths
    foreach my $node ($tree->get_node_refs) {
        $node->set_depth_aa(undef);
    }
    #  recalculate depths - these will include the dangling parents
    foreach my $node ($tree->get_node_refs) {
        my $d = $node->get_depth;
        say $d;
    }

    is ($orig_root->get_depth, 3, 'orig root depth has changed');

    #  nasty test as it knows too much
    is ($tree->get_tree_ref->get_name, 'c', 'initial root node has correct name');

    $tree->trim_to_last_common_ancestor;

    is ($orig_root->get_depth, 0, 'orig root depth is back to zero');

    foreach my $should_not_exist (qw /a b c/) {
        ok (
            !$tree->exists_node (name => $should_not_exist),
            "LCA: branch $should_not_exist is not in tree",
        );
    }
    foreach my $should_exist (@keepers) {
        ok (
            $tree->exists_node (name => $should_exist),
            "LCA: branch $should_exist is still in tree",
        );
    }
    #  should be zeroed
    is ($tree->get_root_node->get_length, 0, 'root node has length zero');
    is ($tree->get_root_node->get_name, '1', 'root node has correct name');
    #  nasty test as it knows too much
    is ($tree->get_tree_ref->get_name, '1', 'trimmed root node has correct name');
    

    return;
}

sub test_get_terminal_node_ref_caching {
    my $tree = get_tree_object_from_sample_data();
    #  map to names or we get deep recursion crash with Test2
    my $tips1 = map {$_->get_name} $tree->get_terminal_node_refs;
    my $tips2 = map {$_->get_name} $tree->get_terminal_node_refs;
    is ($tips1, $tips2, 'get_terminal_node_ref_caching works');
}

sub test_ladderise {
    my $tree1 = shift || get_tree_object_from_sample_data();
    my $tree2 = $tree1->clone();
    $tree2->ladderise;
    
    ok (
        $tree1->trees_are_same(comparison => $tree2),
        'ladderised tree has same topology as original',
    );

    #  check node order is different and follows expected,
    #  as we might change the default sort one day and then we'd have "issues"
    my %nodes = $tree1->get_all_descendants_and_self;
    subtest "Ladderised node orders as expected" => sub {
      NODE_NAME:
        foreach my $node_name (keys %nodes) {
            my $node1 = $tree1->get_node_ref_aa ($node_name);
            my $node2 = $tree2->get_node_ref_aa ($node_name);

            my @children1 = $node1->get_children;
            my @children2 = $node2->get_children;

            is (scalar @children2, scalar @children1, "Child counts match for $node_name");

            next NODE_NAME if scalar @children1 <= 1;

            my @counts2 = map {$_->get_descendent_count} @children2;
            my @counts1 = map {$_->get_descendent_count} @children1;
            my $check1 = join ' ', @counts1;
            my $check2 = join ' ', @counts2;

            foreach my $i (1 .. $#children2) {
                my $j = $i-1;
                cmp_ok (
                    $counts2[$i],
                    '<=',
                    $counts2[$j],
                    "Child $i has fewer descendents than child $j, parent node "
                    . $node2->get_name
                    . "  in: $check1, out: $check2",
                );
            }
        }
    }
}

sub check_trimmings {
    return;
    my ($tree, $exp_deleted, $exp_remaining, $msg) = @_;
    $msg //= '';

    subtest 'trimmed correct nodes' => sub {
        foreach my $node_name (sort @$exp_deleted) {
            ok (
                !$tree->exists_node (name => $node_name),
                "$msg $node_name has been removed",
            );
        }
        foreach my $node_name (sort @$exp_remaining) {
            ok (
                $tree->exists_node (name => $node_name),
                "$msg $node_name has not been removed",
            );
        }
    };
}

sub test_collapse_tree {
    my $tree1 = get_site_data_as_tree();
    my $tree2 = $tree1->clone;
    
    $tree1->rename (new_name => 'absolute');
    $tree2->rename (new_name => 'relative');

    $tree1->collapse_tree(cutoff_absolute => 0.5, verbose => 0);
    #say Data::Dumper::Dumper [$tree1->describe];
    
    is ($tree1->get_total_tree_length, 29.8407270588888, 'trimmed sum of branch lengths is correct');
    is (
        $tree1->get_terminal_element_count,
        $tree2->get_terminal_element_count,
        'terminal node count is unchanged',
    );

    eval {$tree2->collapse_tree (cutoff_relative => -1)};
    my $e = $EVAL_ERROR;
    ok ($e, 'Got eval error when cutoff_relative is outside [0,1]');

    my $rel_cutoff = 0.5 / $tree2->get_tree_length;

    $tree2->collapse_tree (cutoff_relative => $rel_cutoff, verbose => 0);

    ok (
        $tree1->trees_are_same (
            comparison => $tree2,
        ),
        'Absolute and relative cutoffs give same result when scaled the same'
    );
    

}


sub test_shuffle_terminal_names {
    my $tree = get_site_data_as_tree();
    
    test_node_hash_keys_match_node_names ($tree);

    my $clone = $tree->clone;
    $clone->rename (new_name => 'shuffled_terminals');

    $clone->shuffle_terminal_names (seed => $default_prng_seed);

    test_node_hash_keys_match_node_names ($clone);
    
    ok (
        !$tree->trees_are_same (
            comparison => $clone,
        ),
        "Cloned tree with shuffled terminals differs from original"
    );

    #  Now check a shuffle of a sub-clade's terminals.
    #  Its terminals should change, but its sibling's termials should not.

    my $clone2 = $tree->clone;
    my $cloned_sibs = $clone2->get_children;
    my $orig_sibs   = $tree->get_children;

    #  we need more than one child
    if (scalar @$orig_sibs == 1) {
        $orig_sibs   = $orig_sibs->[0]->get_children;
        $cloned_sibs = $cloned_sibs->[0]->get_children;
    }

    $clone2->shuffle_terminal_names (
        seed => $default_prng_seed,
        target_node => $cloned_sibs->[0],
    );

    subtest "Cloned sub-tree with shuffled terminals differs from original"
     => sub {descendents_are_same ($cloned_sibs->[0], $orig_sibs->[0], 'get_name', 'terminals_only')};

    subtest "Cloned sub-tree without shuffled terminals same as original"
     => sub {descendents_are_same ($cloned_sibs->[1], $orig_sibs->[1])};

    test_node_hash_keys_match_node_names ($clone2);

    return;
}

sub test_node_hash_keys_match_node_names {
    my $tree = shift // get_site_data_as_tree();

    my $test = sub {
        my $node_hash = $tree->get_node_hash;
        while (my ($name, $node_ref) = each %$node_hash) {
            is ($name, $node_ref->get_name, "Name matches for $name");
        }
    };

    subtest 'Node hash keys match node names' => $test;

    return;
}


sub test_to_table_group_nodes {
    my $tree = shift // get_site_data_as_tree();
    my $list_name = 'some_list';
    
    foreach my $node ($tree->get_node_refs) {
        $node->add_to_lists (
            use_ref   => 1,
            #  values in natural sort order of keys
            $list_name => {a1 => 1, a2 => 2, a11 => 3},
        );
    }

    my $table = eval {
        $tree->to_table_group_nodes (
            num_clusters   => 5,
            sub_list       => $list_name,
            terminals_only => 0,
            symmetric      => 1,
            include_node_data => 1,
        );
    };
    is ($@, '', 'exported to grouped table without error');
    
    #  now do stuff with table
    my $header = $table->[0];
    is (
        [@{$header}[-3,-2,-1]],
        [qw /a1 a2 a11/],
        'last three header cols are from extra list',
    ) or diag join ',', @$header;

    for my $i (1..3) {
        my $row = $table->[$i]; 
        is (
            [@{$row}[-3,-2,-1]],
            [qw /1 2 3/],
            "last three cols of row $i are as expected",
        ) or diag join ',', @$row;;
    }
    #  check one of the internals
    my $internal_row = $table->[1];
    is (
        [@{$internal_row}[0,1,2]],
        ['100___', '100___', ''],
        'got blank second element col for internal node'
    );
    
    my $header_len = @$header;
    my $same_len   = all {scalar @{$_} == $header_len} @$table;
    ok (
        $same_len,
        "all rows are same length ($header_len)",
    );

    return;
}

sub test_export_tabular_tree {
    my $tree = shift // get_site_data_as_tree();

    state $tabular_tree_num;
    $tabular_tree_num++;
    my $xchar = "\N{LATIN SMALL LETTER X WITH DIAERESIS}";
    my $pchar = "\N{LATIN CAPITAL LETTER P WITH ACUTE}";
    my $fname = get_temp_file_path(
        "tabular_tree_e${xchar}${pchar}_${tabular_tree_num}.csv"
    );

    #note "File name is $fname";
    my $success = eval {
        $tree->export_tabular_tree (
            file => $fname,
        );
    };
    is ($@, '', 'exported to tabular without error');
    
    #  now reimport it
    my $column_map = {};
    my $nex = Biodiverse::ReadNexus->new();
    $nex->import_data (
        file => $fname,
        column_map => $column_map,
    );
    my @imported_trees = $nex->get_tree_array;
    my $imported_tree  = $imported_trees[0];

    #  check terminals
    ok (
        $tree->trees_are_same (
            comparison => $imported_tree,
        ),
        'Reimported tabular tree matches original',
    );

    my %nodes   = $tree->get_node_hash;
    my %nodes_i = $imported_tree->get_node_hash;

    subtest 'lengths and child counts match' => sub {
        foreach my $node_name (keys %nodes) {
            my $node   = $nodes{$node_name};
            my $node_i = $nodes_i{$node_name};
    
            is (
                $node->get_length,
                $node_i->get_length,
                'nodes are same length',
            );
            is (
                $node->get_child_count,
                $node_i->get_child_count,
                'nodes have same child count',
            );
            my (@child_names, @child_names_i);
            foreach my $child ($node->get_children) {
                push @child_names, $child->get_name;
            }
            foreach my $child ($node_i->get_children) {
                push @child_names_i, $child->get_name;
            }
            is (
                [sort @child_names_i],
                [sort @child_names],
                'child names are the same for node ' . $node->get_name,
            );
        };
    };


    return;
}

sub test_export_nexus {
    my $tree = shift // get_site_data_as_tree();
    
    _test_export_nexus (
        tree => $tree,
        no_translate_block => 0,
    );
    _test_export_nexus (
        tree => $tree,
        no_translate_block => 1,
        use_internal_names => 1,
    );
    _test_export_nexus (
        tree => $tree,
        no_translate_block => 0,
        check_bootstrap_values => 1,
    );

}

sub test_export_newick {
    my $tree = shift // get_site_data_as_tree();
    
    my %args = (
        tree => $tree,
        format => 'newick',
    );
    
    _test_export_nexus (
        %args,
        no_translate_block => 0,
    );
    _test_export_nexus (
        %args,
        no_translate_block => 1,
        use_internal_names => 1,
    );
    #  need to double check newick handles bootstrap blocks
    #_test_export_nexus (
    #    %args,
    #    no_translate_block => 0,
    #    check_bootstrap_values => 1,
    #);

}

sub _test_export_nexus {
    my %args = @_;
    my $tree = $args{tree};
    delete $args{tree};
    
    my $format = $args{format} // 'nexus';
    my $method = "export_$format";
    my $file_suffix = $format eq 'nexus' ? '.nex' : '.nwk';

    if ($args{check_bootstrap_values}) {
        # add some bootstrap values to export
        # get all the nodes
        my @tree_nodes = $tree->get_node_refs();
        foreach my $node (@tree_nodes) {
            my $booter = $node->get_bootstrap_block;
            $booter->set_value_aa(bootkey => "bootvalue");
            # $booter->set_colour_aa("red");
            my $some_list = {a => 1, b => 2, c => 3};
            $node->add_to_list (
                BOOTER_TEST_LIST => $some_list,
                use_ref => 1,
            );
        }
        $args{sub_list} = 'BOOTER_TEST_LIST';
        $args{export_colours} = 1;
    }
    
    my $test_suffix = ', args:';
    foreach my $key (sort keys %args) {
        my $val = $args{$key};
        $test_suffix .= " $key => $val,";
    }
    chop $test_suffix;
    
    state $tree_export_num = 0;
    $tree_export_num++;

    my $echar1 = "\N{LATIN CAPITAL LETTER E WITH CIRCUMFLEX}";
    my $echar2 = "\N{LATIN SMALL LETTER E WITH CIRCUMFLEX}";
    my $fname = get_temp_file_path (
        "tree_export_tr${echar1}${echar2}_$tree_export_num$file_suffix",
    );
    #note "File name is $fname";
    my $success = eval {
        $tree->$method (
            file => $fname,
            %args,
        );
    };
    my $e = $EVAL_ERROR;
    diag $e if $e;
    ok (!$e, "ran $method without error" . $test_suffix);

    #  now reimport it
    my $nex = Biodiverse::ReadNexus->new();
    $nex->import_data (
        file => $fname,
    );
    my @imported_trees = $nex->get_tree_array;
    my $imported_tree  = $imported_trees[0];

    #  check terminals
    ok (
        $tree->trees_are_same (
            comparison => $imported_tree,
        ),
        'Reimported nexus tree matches original' . $test_suffix,
    );

    
    my %nodes   = $tree->get_node_hash;
    my %nodes_i = $imported_tree->get_node_hash;

    subtest "lengths and child counts match$test_suffix" => sub {
        foreach my $node_name (keys %nodes) {
            my $node   = $nodes{$node_name};
            my $node_i = $nodes_i{$node_name};

            is (
                $node->get_length,
                $node_i->get_length,
                'nodes are same length',
            );
            is (
                $node->get_child_count,
                $node_i->get_child_count,
                'nodes have same child count',
            );
            my (@child_names, @child_names_i);
            foreach my $child ($node->get_children) {
                push @child_names, $child->get_name;
            }
            foreach my $child ($node_i->get_children) {
                push @child_names_i, $child->get_name;
            }
            is (
                [sort @child_names_i],
                [sort @child_names],
                'child names are the same for node ' . $node->get_name,
            );
        };
    };

    ## make sure the bootstrap values got through
    ## comment out since todo results in lots of newlines at the terminal
    if($args{check_bootstrap_values}) {
        #TODO: {
        #    local $TODO = 'round tripping is for issue #657';
            subtest "bootstrap roundtrip" => sub {
                my @tree_nodes = $imported_tree->get_node_refs();
                foreach my $node (@tree_nodes) {
                    my $node_name = $node->get_name;
                    my $booter = $node->get_bootstrap_block;
                    my %expected_list_items = (
                        bootkey => 'bootvalue',
                        BOOTER_TEST_LIST__a => 1,
                        BOOTER_TEST_LIST__b => 2,
                        BOOTER_TEST_LIST__c => 3,
                    );
                    foreach my $key (sort keys %expected_list_items) {
                        is ($booter->get_value ( key => $key ),
                           $expected_list_items{$key},
                           "Exported and then imported correct bootstrap value for $key in $node_name."
                        );
                    }
                    # is ($booter->get_colour,
                    #    "red",
                    #    "Exported and then imported correct colour for $node_name."
                    # );
                }
            };
        #}
    }

    return;
}


sub test_export_Rphylo {
    my $tree2 = shift // get_site_data_as_tree();

    my $nwk = '(((t1:0.1838405095,t3:0.7839861871):0.7242035018,t7:0.8255161436):0.9768610101,((t6:0.2164495632,t8:0.8440289358):0.7437079474,(t4:0.4462201281,(t5:0.1244694644,t2:0.3507230047):0.7634477804):0.06578667508):0.5001766474)';
    my $rn  = Biodiverse::ReadNexus->new;
    my $success = $rn->import_newick (data => $nwk);
    my @trees = $rn->get_tree_array;
    my $tree1 = shift @trees;

    #  another one
    $nwk = '(A:1, B:1):5.8';
    $rn  = Biodiverse::ReadNexus->new;
    $success = $rn->import_newick (data => $nwk);
    @trees = $rn->get_tree_array;
    my $tree3 = shift @trees;

    my $i;
    foreach my $tree ($tree1, $tree2, $tree3) {
        $i++;
        my $result = $tree->to_R_phylo;
        #  round trip it
        $rn = Biodiverse::ReadNexus->new;
        $rn->import_R_phylo(data => $result);
        @trees = $rn->get_tree_array;
        my $roundtripper = shift @trees;
        ok($tree->trees_are_same(comparison => $roundtripper),
            "roundtripped via Rphylo, tree $i"
        );
    }


}

sub test_roundtrip_names_with_quotes_in_newick {
    # need a basedata to get the quoting we need to test
    my $bd = Biodiverse::BaseData->new(name => 'blonk', CELL_SIZES => [1,1]);
    $bd->add_element (group => '1:1', label => q{'a b':});
    $bd->add_element (group => '1:1', label => q{'a c':});
    $bd->add_element (group => '1:1', label => q{a:b});

    my $tree1 = $bd->to_tree;

    foreach my $label ($bd->get_labels) {
        ok ($tree1->exists_node(name => $label), qq{terminal /$label/ is in tree});
    }

    my $nwk_str1 = $tree1->to_newick;

    my $read_nex = Biodiverse::ReadNexus->new;
    $read_nex->import_newick (data => $nwk_str1);
    my $tree_array = $read_nex->get_tree_array;

    my $tree2 = $tree_array->[0];
    
    #say $nwk_str1;
    #say $tree2->to_newick;
    

    ok ($tree1->trees_are_same(comparison => $tree2), 'trees are the same when roundtripped via newick and names have quotes');
}


sub test_equalise_branch_lengths {
    my $tree = shift // get_site_data_as_tree();

    my $eq_tree = $tree->clone_tree_with_equalised_branch_lengths;

    is ($tree->get_total_tree_length,
        $eq_tree->get_total_tree_length,
        'eq tree has same total length as orig',
    );

    is ($tree->get_node_count, $eq_tree->get_node_count, 'node counts match');
}


sub test_rescale_by_longest_path {
    my $tree = get_site_data_as_tree();

    my $longest_path = $tree->get_longest_path_length_to_terminals;
    my $total_length = $tree->get_total_length;

    my $target_name = '1950000:1350000';
    my $target_node = $tree->get_node_ref (node => $target_name);
    $target_node->set_length (length => 100);

    $tree->delete_all_cached_values;

    my $new_longest_path = $tree->get_longest_path_length_to_terminals;

    #  some sanity checks
    is (
        $new_longest_path,
        $longest_path + 100,
        'Longest path is 100 units longer',
    );
    is ($total_length + 100,
        $tree->get_total_length,
        'new tree is 100 units longer',
    );

    #  now we rescale things
    my $rescaled_tree
      = $tree->clone_tree_with_rescaled_branch_lengths (scale_factor => 0.01);
    is_numeric_within_tolerance_or_exact_text (
        got => $rescaled_tree->get_longest_path_length_to_terminals,
        expected => $new_longest_path / 100,
        message  => 'New longest path is 0.01 of the original',
    );
    is (
        $rescaled_tree->get_total_length,
        $tree->get_total_length / 100,
        'New total tree length is 0.01 of the original',
    );

    #  now check we can go back
    $rescaled_tree
      = $rescaled_tree->clone_tree_with_rescaled_branch_lengths (scale_factor => 100);
    is (
        $rescaled_tree->get_longest_path_length_to_terminals,
        $new_longest_path,
        'New longest path is same as the original after rescaling by 100',
    );
    is (
        $rescaled_tree->get_total_length,
        $tree->get_total_length,
        'New total tree length is same as the original after rescaling by 100',
    );
    
    #  now check new_length
    $rescaled_tree
      = $rescaled_tree->clone_tree_with_rescaled_branch_lengths (new_length => 5);
    is (
        $rescaled_tree->get_longest_path_length_to_terminals,
        5,
        'New length is 5 when arg new_length=>5',
    );
    
    #  now check new_length
    $rescaled_tree
      = $rescaled_tree->clone_tree_with_rescaled_branch_lengths (new_length => 0.25);
    is (
        $rescaled_tree->get_longest_path_length_to_terminals,
        0.25,
        'New length is 0.25 when arg new_length=>0.25',
    );
    
}

sub test_remap_labels_from_hash {
    my $tree1 = shift || get_tree_object_from_sample_data();

    my %remap;
    my @expected_new_labels;
    foreach my $label (sort $tree1->get_labels()) {
        $remap{$label} = uc( $label );
        push( @expected_new_labels, uc $label );
    }

    $tree1->remap_labels_from_hash(remap => \%remap);
       
    my @actual_new_labels = sort $tree1->get_labels();

    is( \@actual_new_labels,
               \@expected_new_labels,
               "Got expected labels" );
}

sub test_remap_mismatched_labels {
    my $tree1 = shift || get_tree_object_from_sample_data();

    my %remap;
    my @expected_new_labels;
    foreach my $label (sort $tree1->get_labels()) {
        $remap{$label} = uc( $label );
        push( @expected_new_labels, uc $label );
    }

    # now also add in some junk remap values (might come up say when
    # applying a multiple tree remap to a single tree)
    foreach my $number (0..10) {
        $remap{"junkkey$number"} = "junkvalue$number";
    }

    eval { $tree1->remap_labels_from_hash(remap => \%remap); };
    my $e = $EVAL_ERROR;
    ok (!$e, "got no exception from mismatched remap");

    my @actual_new_labels = sort $tree1->get_labels();

    is( \@actual_new_labels,
               \@expected_new_labels,
               "Got expected labels" );
}

sub test_get_terminal_counts_by_depth {
    my $tree = Biodiverse::Tree->new (NAME => 'test depth stats');
    
    #  bifurcating number scheme
    my @nums = qw /1 2 3 4 5 6 7 14 15/;
    my %nodes;
    for my $num (@nums) {
        my $node = $tree->add_node(name => $num);
        $nodes{$num} = $node;
    }
    $nodes{1}->add_children(children => [$nodes{2}, $nodes{3}]);
    $nodes{2}->add_children(children => [$nodes{4}, $nodes{5}]);
    $nodes{3}->add_children(children => [$nodes{6}, $nodes{7}]);
    $nodes{7}->add_children(children => [$nodes{14}, $nodes{15}]);
#diag $tree->to_newick;
    my $hash = $tree->get_terminal_counts_by_depth;

    # depth
    # 0 1 2  3
    # nodes
    # 1 2 4
    #     5
    #   3 6 
    #     7 14
    #     7 15

    my $expected = {
        0 => 5,
        1 => 5,
        2 => 2,
        3 => 0,
    };

    is $hash, $expected, 'got expected depth distribution';
}

sub test_depth {
    my $tree = Biodiverse::Tree->new (NAME => 'test depth');
    
    #  bifurcating number scheme
    my @nums = qw /1 2 3 4 5 6 7 14 15/;
    my %nodes;
    for my $num (@nums) {
        my $node = $tree->add_node(name => $num);
        $nodes{$num} = $node;
    }
    $nodes{1}->add_children(children => [$nodes{2}, $nodes{3}]);
    $nodes{2}->add_children(children => [$nodes{4}, $nodes{5}]);
    $nodes{3}->add_children(children => [$nodes{6}, $nodes{7}]);
    $nodes{7}->add_children(children => [$nodes{14}, $nodes{15}]);
    
    my %expected;
    @expected{@nums} = qw /0 1 1 2 2 2 2 3 3/;
    subtest 'Expected node depths' => sub {
        for my $num (@nums) {
            my $exp_depth = $expected{$num};
            is ($nodes{$num}->get_depth, $exp_depth, "Expected depth for node $num ($exp_depth)");
        }
    };
}

sub test_newick_with_trailing_comment {
    my $nwk = get_cluster_mini_data_newick();
    $nwk .= '[trailing comment]';
    
    my $read_nex = Biodiverse::ReadNexus->new();
    ok (lives  {
            $read_nex->import_newick (data => $nwk)
        },
        'can read newick with trailing comment'
    );
    
}

sub test_nti_expected_values {
    my $tree = get_tree_object_from_sample_data();
    my $fmt = "%d, %.10f, %.5f";  #  5dp for sd is when n is large
    my @got;
    foreach my $i (2, 5, 10, 15, 25, 31) {
        my $exp_mean = $tree->get_nti_expected_mean(sample_count => $i);
        my $exp_sd   = $tree->get_nti_expected_sd(sample_count => $i);
        push @got, sprintf $fmt, $i, $exp_mean, $exp_sd;
    }

    #  expectations are generaated using Math::AnyNum,
    #  which has very high precision
    my @expected = map {sprintf $fmt, @$_}
    (
        [2,  1.84720584828667, 0.2353571207],
        [5,  1.64932662894919, 0.2118374735],
        [10, 1.46155545940559, 0.1645045096],
        [15, 1.33256848608891, 0.1315366427],
        [25, 1.15086784106492, 0.0757050915],
        [31, 1.06179770753568, 0],
    );

    is (\@got, \@expected, 'Got expected NTI mean and sd');

}

sub test_nri_expected_values {
    my $tree = get_tree_object_from_sample_data();
    my $fmt = "%d, %.10f, %.10f";
    my @got;
    foreach my $i (2, 5, 10, 15, 25, 31) {
        my $exp_mean = $tree->get_nri_expected_mean(sample_count => $i);
        my $exp_sd   = $tree->get_nri_expected_sd(sample_count => $i);
        push @got, sprintf $fmt, $i, $exp_mean, $exp_sd;
    }

    my @expected = map {sprintf $fmt, @$_}
    (
        [2,  1.8472058483, 0.2353571207],
        [5,  1.8472058483, 0.0818464281],
        [10, 1.8472058483, 0.0414806703],
        [15, 1.8472058483, 0.0270385153],
        [25, 1.8472058483, 0.0118481780],
        [31, 1.8472058483, 0],
    );

    is (\@got, \@expected, 'Got expected NRI mean and sd');

}

######################################


sub descendents_are_same {
    my ($node1, $node2, $negation_method, $terminals_only) = @_;
    $negation_method //= 0;

    my @methods = qw /
        get_name
        get_length
        get_child_count
        get_child_count_below
        is_terminal_node
        is_internal_node
    /; # /
    
    my ($neg_count, $pos_count) = (0, 0);

    METHOD:
    foreach my $method (@methods) {
        my $message = "nodes match for $method";
        my $val1 = $node1->$method;
        my $val2 = $node2->$method;

        #  Only testing if names differ under negation for terminals
        #  Need to devise better rules as args as we develop more perturbations.
        #  BUT WE CAN HAVE RANDOMLY THE SAME (albeit rarely)
        #  ...better to just keep count and check if the matches don't sum - still not perfect, though
        if ($method eq $negation_method) {
            if (($terminals_only && $node1->is_terminal_node)) {
                if ($val1 ne $val2) {
                    $neg_count ++;
                }
                next METHOD;
            }
            $pos_count++;
        }
        is ($val1, $val2, $message);
    }

    my @children1 = $node1->get_children;
    my @children2 = $node2->get_children;

    for my $i (0 .. $#children1) {
        descendents_are_same ($children1[$i], $children2[$i], $negation_method, $terminals_only);
    }
    
    #  need to generalise this to work with any type of node, but cleanly
    if ($negation_method && !$node1->is_terminal_node) {
        my $result = isnt (scalar $node1->get_terminal_element_count, $pos_count, 'differing terminals for $negation_method');
        diag 'This test can intermittently fail due to randomness. '
             . 'If it fails consistently for different PRNG seeds '
             . 'then there is a problem'
          if !$result;
    }

    return;
}


sub get_cluster_mini_data_newick {
    return q{((('2.5:1.5':0,'3.5:1.5':0,'3.5:2.5':0)'3___':0.2,('1.5:1.5':0,'1.5:2.5':0,'2.5:2.5':0)'2___':0.2)'4___':0)'5___':0}
}

sub get_site_data_as_tree {
    my $comp_nwk = get_site_data_newick_tree(@_);

    my $read_nex = Biodiverse::ReadNexus->new();
    my $success = eval {$read_nex->import_data (data => $comp_nwk)};
    croak $@ if $@;

    my $tree_arr = $read_nex->get_tree_array;
    my $comparison_tree = $tree_arr->[0];

    return $comparison_tree;
}

sub get_site_data_newick_tree {
    my $label = shift // 'link_average';
    my $data = get_data_section('SITE_DATA_NEWICK_TREE');
    $data =~ s/\n+\z//m;  #  clear all trailing newlines
    my @data = split "\n", $data;
    while (my $line = shift @data) {
        next if not $line =~ /^$label/;
        my ($name, $newick) = split / /, $line;
        return $newick;
    }
    croak "should not get this far\n";
}


sub test_knuckle_nodes {
    my $nwk_with_knuckles = '(((t3:0.129,(t6:0.948,t2:0.866):0.673):0.671,t1:0.598):0.049,(t4:0.604,t5:0.857):0.202);';
    my $nwk_no_knuckles   = '((t3:0.129,t6:1.621):0.720,(t4:0.604,t5:0.857):0.202);';
    
    my $parser = Biodiverse::ReadNexus->new;
    ok $parser->import_data (data => "$nwk_with_knuckles\n$nwk_no_knuckles"), "Imported knuckle trees";
    my @trees = $parser->get_tree_array;
    is scalar @trees, 2, 'Imported two knuckle trees';
    my $tree_with_knuckles = shift @trees;
    my $tree_no_knuckles = shift @trees;
    
    $tree_with_knuckles->delete_node(node => 't1');
    $tree_with_knuckles->delete_node(node => 't2');
    
    my $delete_count = $tree_with_knuckles->merge_knuckle_nodes;
    is $delete_count, 2, 'deleted expected number of nodes';
    
    my $comp = $tree_with_knuckles->trees_are_same(comparison => $tree_no_knuckles);
    ok $comp, 'got expected tree topology after clearing knuckles';
    
    my $tree = get_tree_object_from_sample_data();
    foreach my $name_num (qw /18 21 25/) {
        $tree->delete_node(node => "Genus:sp$name_num");
    }
    foreach my $node ($tree->get_node_refs) {
        $node->get_depth;  #  trigger depth storage
    }
    $tree->merge_knuckle_nodes;
    foreach my $node ($tree->get_node_refs) {
        next if $node->is_root_node;
        my $parent = $node->get_parent;
        is ($node->get_depth, $parent->get_depth + 1, "correct depth for " . $node->get_name);
    }
}


1;

__DATA__


@@ SITE_DATA_NEWICK_TREE
link_average ((((((('3250000:950000':0.333333333333333,'3350000:950000':0.333333333333333)'75___':0.083333333333334,'3350000:850000':0.416666666666667)'93___':0.203703703703703,'3250000:750000':0.62037037037037)'109___':0.168342013736751,(((((('3350000:1150000':0,'3450000:1350000':0,'3550000:1550000':0,'3350000:1050000':0,'3350000:1250000':0,'3450000:1550000':0,'3350000:1350000':0,'3450000:1450000':0)'38___':0.333333333333333,'3550000:1450000':0.333333333333333)'84___':0.018518518518519,('3450000:1250000':0,'3550000:1250000':0)'4___':0.351851851851852)'85___':0.101178451178451,('3650000:1650000':0.2,'3650000:1750000':0.2)'60___':0.253030303030303)'97___':0.090559440559441,'3550000:1950000':0.543589743589744)'105___':0.025367172510029,((('3650000:1450000':0,'3650000:1550000':0)'31___':0.2,'3450000:1050000':0.2)'61___':0.22989417989418,('3650000:1350000':0.2,'3750000:1450000':0.2)'58___':0.22989417989418)'95___':0.139062736205593)'107___':0.219755468007348)'118___':0.139519699240052,((((('3350000:2050000':0,'3450000:2150000':0,'3250000:2850000':0,'3550000:2150000':0)'23___':0.333333333333333,'3750000:1750000':0.333333333333333)'74___':0.116666666666667,(('3550000:2050000':0.142857142857143,'3550000:2250000':0.142857142857143)'50___':0.123809523809524,('3350000:2150000':0,'3450000:2050000':0)'35___':0.266666666666667)'67___':0.183333333333333)'96___':0.24389770723104,(((('3650000:1950000':0.111111111111111,'3650000:2050000':0.111111111111111)'43___':0.044444444444445,'3750000:2050000':0.155555555555556)'52___':0.222222222222222,'3750000:1950000':0.377777777777778)'88___':0.026984126984127,'3650000:1850000':0.404761904761905)'91___':0.289135802469135)'113___':0.056669186192996,(('3150000:2950000':0,'3250000:2150000':0)'11___':0.333333333333333,'3250000:2950000':0.333333333333333)'73___':0.417233560090703)'116___':0.177665189923137)'124___':0.0349067652113,(((((((((('3550000:950000':0.25,'3650000:1150000':0.25)'65___':0.179292929292929,(('3450000:950000':0.125,'3550000:1050000':0.125)'46___':0.075,'3550000:1150000':0.2)'56___':0.229292929292929)'94___':0.088638028638029,('3450000:1150000':0.25,'3450000:850000':0.25)'66___':0.267930957930958)'103___':0.11516095016095,('3750000:1350000':0.333333333333333,'3850000:1650000':0.333333333333333)'77___':0.299758574758575)'110___':0.026499734833068,'3750000:1550000':0.659591642924976)'112___':0.0511392899791321,((((('3350000:750000':0.333333333333333,'3450000:750000':0.333333333333333)'76___':0.067969816131581,((('2950000:650000':0.0909090909090909,'3050000:650000':0.0909090909090909)'42___':0.107808857808858,'3050000:750000':0.198717948717949)'54___':0.06996891996892,('3150000:650000':0,'2850000:750000':0,'2950000:750000':0)'41___':0.268686868686869)'69___':0.132616280778045)'90___':0.09259184443008,'2750000:750000':0.493894993894994)'101___':0.018452781786115,(((((('3050000:150000':0,'2850000:650000':0,'3150000:50000':0,'3050000:350000':0,'3250000:150000':0)'27___':0.142857142857143,'3150000:350000':0.142857142857143)'49___':0.079365079365079,('3050000:50000':0,'3250000:450000':0)'12___':0.222222222222222)'62___':0.01765873015873,(('3150000:150000':0,'3150000:250000':0)'16___':0.142857142857143,'3250000:250000':0.142857142857143)'47___':0.097023809523809)'63___':0.087391774891775,'3250000:350000':0.327272727272727)'72___':0.051034151034151,(('2750000:650000':0,'3050000:550000':0)'32___':0.2,'2650000:650000':0.2)'57___':0.178306878306878)'89___':0.134040897374231)'102___':0.066874027647837,((('3250000:650000':0.142857142857143,'3350000:650000':0.142857142857143)'51___':0.123809523809524,'3450000:650000':0.266666666666667)'68___':0.211111111111111,('2950000:50000':0,'3150000:550000':0,'2550000:1050000':0,'2950000:350000':0)'33___':0.477777777777778)'98___':0.101444025551168)'108___':0.131509129575162)'115___':0.041036540814585,('2550000:750000':0,'2650000:750000':0)'34___':0.751767473718693)'117___':0.11152147677956,((('3050000:850000':0.2,'3250000:850000':0.2)'59___':0.208333333333333,('3150000:750000':0.2,'3150000:850000':0.2)'55___':0.208333333333333)'92___':0.3,('2950000:250000':0,'3050000:250000':0)'14___':0.708333333333333)'114___':0.15495561716492)'121___':0.028471207333334,(((((((('2450000:1050000':0.142857142857143,'2550000:950000':0.142857142857143)'48___':0.053571428571428,'2450000:1150000':0.196428571428571)'53___':0.048280423280424,(('2350000:950000':0,'2450000:950000':0)'1___':0.111111111111111,'2250000:950000':0.111111111111111)'45___':0.133597883597884)'64___':0.082275132275132,('2550000:850000':0,'2650000:950000':0,'2450000:1250000':0,'2150000:1150000':0,'2650000:850000':0)'40___':0.326984126984127)'71___':0.03015873015873,'2750000:850000':0.357142857142857)'86___':0.129563492063492,(('2250000:1050000':0,'2350000:1250000':0,'2750000:950000':0)'37___':0.333333333333333,'2350000:1050000':0.333333333333333)'79___':0.153373015873016)'100___':0.149305555555556,(('2150000:1050000':0,'2350000:1150000':0)'36___':0.333333333333333,'2250000:1250000':0.333333333333333)'81___':0.302678571428572)'111___':0.161080827067669,(('1950000:1450000':0,'1950000:1350000':0,'2050000:1350000':0)'39___':0.333333333333333,('2050000:1250000':0,'2150000:1250000':0)'7___':0.333333333333333)'78___':0.463759398496241)'119___':0.0946674260020131)'122___':0.033730189503183,((((((('3750000:1850000':0,'3850000:1350000':0,'3950000:1750000':0)'13___':0.333333333333333,'3650000:1250000':0.333333333333333)'82___':0.041666666666667,'3750000:1250000':0.375)'87___':0.105,('3850000:1850000':0.333333333333333,'3850000:1950000':0.333333333333333)'80___':0.146666666666667)'99___':0.05265306122449,'3750000:1650000':0.53265306122449)'104___':0.034840325018896,(('3850000:1450000':0.111111111111111,'3850000:1750000':0.111111111111111)'44___':0.180555555555556,'3850000:1550000':0.291666666666667)'70___':0.275826719576719)'106___':0.235392616642617,(('3250000:3050000':0,'3650000:2350000':0)'2___':0.333333333333333,'3750000:2150000':0.333333333333333)'83___':0.46955266955267)'120___':0.122604344448767)'123___':0.037648501223703)'125___':0)'126___':0
link_recalculate ((((((('2250000:1050000':0,'2350000:1250000':0,'2750000:950000':0)'37___':0.333333333333333,'2350000:1050000':0.333333333333333)'89___':0.166666666666667,('3450000:1250000':0,'3550000:1250000':0)'4___':0.5)'108___':0.166666666666667,((('1950000:1450000':0,'1950000:1350000':0,'2050000:1350000':0)'39___':0.333333333333333,('2050000:1250000':0,'2150000:1250000':0)'7___':0.333333333333333)'81___':0.166666666666667,'2250000:1250000':0.5)'104___':0.166666666666667)'123___':0.047619047619047,(((((((('3250000:3050000':0,'3650000:2350000':0)'2___':0.333333333333333,'3550000:1450000':0.333333333333333)'82___':0.266666666666667,('3650000:1650000':0.2,'3650000:1750000':0.2)'59___':0.4)'115___':-0.1,((((('3350000:1150000':0,'3450000:1350000':0,'3550000:1550000':0,'3350000:1050000':0,'3350000:1250000':0,'3450000:1550000':0,'3350000:1350000':0,'3450000:1450000':0)'38___':0.333333333333333,('3550000:2050000':0.142857142857143,'3550000:2250000':0.142857142857143)'50___':0.19047619047619,('3350000:2050000':0,'3450000:2150000':0,'3250000:2850000':0,'3550000:2150000':0)'23___':0.333333333333333,'3750000:1750000':0.333333333333333,('3350000:2150000':0,'3450000:2050000':0)'35___':0.333333333333333,('3150000:2950000':0,'3250000:2150000':0)'11___':0.333333333333333)'92___':0.066666666666667,(('3650000:1950000':0.111111111111111,'3650000:2050000':0.111111111111111)'43___':0.088888888888889,'3750000:2050000':0.2)'58___':0.2)'95___':-0.066666666666667,'3750000:1950000':0.333333333333333)'96___':0.121212121212122,'3550000:1950000':0.454545454545455)'101___':0.045454545454545)'116___':0.136363636363636,'3650000:1850000':0.636363636363636)'118___':0.0303030303030309,((('3750000:1850000':0,'3850000:1350000':0,'3950000:1750000':0)'13___':0.333333333333333,'3750000:1250000':0.333333333333333)'86___':0.166666666666667,'3250000:2950000':0.5)'107___':0.166666666666667)'120___':-0.095238095238096,('3750000:1650000':0.6,'3850000:1950000':0.6)'117___':-0.028571428571429)'121___':0.095238095238096,((((('3250000:950000':0.333333333333333,'3350000:850000':0.333333333333333)'77___':0.166666666666667,'3350000:950000':0.5)'105___':-0.1,'3250000:750000':0.4)'106___':0.138461538461538,(((((('2950000:50000':0,'3150000:550000':0,'2550000:1050000':0,'2950000:350000':0)'33___':0.333333333333333,'3450000:650000':0.333333333333333)'83___':0.095238095238096,('3550000:950000':0.25,'3650000:1150000':0.25)'64___':0.178571428571429,'3750000:2150000':0.428571428571429)'98___':0.025974025974026,(('3750000:1350000':0.333333333333333,'3850000:1650000':0.333333333333333)'74___':-0.133333333333333,'3850000:1850000':0.2)'75___':0.254545454545455)'99___':-0.025974025974026,(('3850000:1450000':0.111111111111111,'3850000:1750000':0.111111111111111)'44___':0.222222222222222,'3650000:1250000':0.333333333333333,'3850000:1550000':0.333333333333333)'93___':0.095238095238096)'100___':0.032967032967033,(((('3150000:650000':0,'2850000:750000':0,'2950000:750000':0)'41___':0.333333333333333,'3450000:750000':0.333333333333333)'78___':-0.033333333333333,(((('3250000:650000':0.142857142857143,'3350000:650000':0.142857142857143)'51___':0.057142857142857,('2950000:650000':0.0909090909090909,'3050000:650000':0.0909090909090909)'42___':0.109090909090909,'3150000:350000':0.2)'60___':0.030769230769231,'3050000:750000':0.230769230769231)'62___':0.032388663967611,'3350000:750000':0.263157894736842)'67___':0.036842105263158)'79___':0.033333333333333,((('3450000:1150000':0.25,'3450000:850000':0.25)'63___':0.022727272727273,(('3650000:1450000':0,'3650000:1550000':0)'31___':0.2,'3450000:1050000':0.2)'56___':0.072727272727273)'68___':0.02139037433155,(('3450000:950000':0.125,'3550000:1050000':0.125)'46___':0.125,'3550000:1150000':0.25)'65___':0.044117647058823)'69___':0.03921568627451)'84___':0.128205128205129)'102___':0.076923076923076)'113___':0.00992555831265596,((((('2950000:250000':0,'3050000:250000':0)'14___':0.333333333333333,('3050000:50000':0,'3250000:450000':0)'12___':0.333333333333333)'85___':0.166666666666667,'3250000:350000':0.5)'110___':-0.166666666666667,(('2550000:750000':0,'2650000:750000':0)'34___':0.2,('2750000:650000':0,'3050000:550000':0)'32___':0.2,'2650000:650000':0.2)'61___':0.133333333333333)'111___':0.133333333333334,(((('2350000:950000':0,'2450000:950000':0)'1___':0.111111111111111,'2250000:950000':0.111111111111111)'45___':0.222222222222222,'2750000:850000':0.333333333333333)'70___':0.051282051282052,'2750000:750000':0.384615384615385)'94___':0.082051282051282,((('2450000:1050000':0.142857142857143,'2550000:950000':0.142857142857143)'49___':0.107142857142857,(('3050000:150000':0,'2850000:650000':0,'3150000:50000':0,'3050000:350000':0,'3250000:150000':0)'27___':0.142857142857143,('3150000:150000':0,'3150000:250000':0)'16___':0.142857142857143,'3250000:250000':0.142857142857143)'48___':0.107142857142857)'66___':0.083333333333333,'2450000:1150000':0.333333333333333,('2550000:850000':0,'2650000:950000':0,'2450000:1250000':0,'2150000:1150000':0,'2650000:850000':0)'40___':0.333333333333333,('2150000:1050000':0,'2350000:1150000':0)'36___':0.333333333333333)'91___':0.133333333333334)'112___':0.0817204301075269)'114___':0.118279569892473,(('3650000:1350000':0.2,'3750000:1450000':0.2)'57___':0.3,'3750000:1550000':0.5)'109___':0.166666666666667)'122___':0.047619047619047)'124___':0.109243697478992,(('3050000:850000':0.2,'3250000:850000':0.2)'55___':0.133333333333333,('3150000:750000':0.2,'3150000:850000':0.2)'54___':0.133333333333333)'88___':0.490196078431373)'125___':0)'126___':0
link_average_unweighted ((((((((((('3650000:1450000':0,'3650000:1550000':0)'31___':0.2,'3450000:1050000':0.2)'61___':0.254365079365079,('3650000:1350000':0.2,'3750000:1450000':0.2)'58___':0.254365079365079)'96___':0.128230103230104,'3250000:750000':0.582595182595183)'107___':0.114602238039738,(((('3350000:1150000':0,'3450000:1350000':0,'3550000:1550000':0,'3350000:1050000':0,'3350000:1250000':0,'3450000:1550000':0,'3350000:1350000':0,'3450000:1450000':0)'38___':0.333333333333333,('3450000:1250000':0,'3550000:1250000':0)'4___':0.333333333333333)'77___':0.083333333333334,'3550000:1450000':0.416666666666667)'91___':0.1,('3650000:1650000':0.2,'3650000:1750000':0.2)'60___':0.316666666666667)'101___':0.180530753968254)'113___':0.100027619949495,((((('3650000:1950000':0.111111111111111,'3650000:2050000':0.111111111111111)'43___':0.044444444444445,'3750000:2050000':0.155555555555556)'52___':0.227777777777777,'3750000:1950000':0.383333333333333)'86___':0.033333333333334,'3650000:1850000':0.416666666666667)'90___':0.16235119047619,'3550000:1950000':0.579017857142857)'106___':0.218207183441559)'119___':0.0753940070346319,(('3250000:950000':0.333333333333333,'3350000:950000':0.333333333333333)'71___':0.083333333333334,'3350000:850000':0.416666666666667)'92___':0.455952380952381)'121___':0.0604032089871931,(((('3350000:2050000':0,'3450000:2150000':0,'3250000:2850000':0,'3550000:2150000':0)'23___':0.333333333333333,'3750000:1750000':0.333333333333333)'81___':0.129166666666667,(('3550000:2050000':0.142857142857143,'3550000:2250000':0.142857142857143)'50___':0.123809523809524,('3350000:2150000':0,'3450000:2050000':0)'35___':0.266666666666667)'65___':0.195833333333333)'99___':0.289583333333333,(('3150000:2950000':0,'3250000:2150000':0)'11___':0.333333333333333,'3250000:2950000':0.333333333333333)'79___':0.41875)'117___':0.180938923272908)'123___':0.028241492161188,(((((((('2750000:650000':0,'3050000:550000':0)'32___':0.2,'2650000:650000':0.2)'57___':0.15,('2550000:750000':0,'2650000:750000':0)'34___':0.35)'85___':0.166666666666667,'2750000:750000':0.516666666666667)'102___':0.092593517593517,((('3350000:750000':0.333333333333333,'3450000:750000':0.333333333333333)'83___':0.086675020885548,(('3450000:950000':0.125,'3550000:1050000':0.125)'46___':0.075,'3550000:1150000':0.2)'56___':0.220008354218881)'93___':0.03827190718638,('3450000:1150000':0.25,'3450000:850000':0.25)'62___':0.208280261405261)'97___':0.150979922854923)'110___':0.134788048514496,((((('2950000:650000':0.0909090909090909,'3050000:650000':0.0909090909090909)'42___':0.107808857808858,'3050000:750000':0.198717948717949)'54___':0.086130536130536,('3150000:650000':0,'2850000:750000':0,'2950000:750000':0)'41___':0.284848484848485)'69___':0.114273313492063,(((('3050000:150000':0,'2850000:650000':0,'3150000:50000':0,'3050000:350000':0,'3250000:150000':0)'27___':0.142857142857143,'3150000:350000':0.142857142857143)'49___':0.123809523809524,('3050000:50000':0,'3250000:450000':0)'12___':0.266666666666667)'64___':0.011011904761904,(('3150000:150000':0,'3150000:250000':0)'16___':0.142857142857143,'3250000:250000':0.142857142857143)'47___':0.134821428571428)'68___':0.121443226911977)'87___':0.157475423881674,(('2950000:250000':0,'3050000:250000':0)'14___':0.333333333333333,'3250000:350000':0.333333333333333)'75___':0.223263888888889)'104___':0.187451010552458)'116___':0.10677371003945,(('3050000:850000':0.2,'3250000:850000':0.2)'59___':0.208333333333333,('3150000:750000':0.2,'3150000:850000':0.2)'55___':0.208333333333333)'88___':0.442488609480797)'120___':0.076286087095414,((((('3750000:1250000':0.333333333333333,'3850000:1850000':0.333333333333333)'80___':0.136904761904762,('3750000:1350000':0.333333333333333,'3850000:1650000':0.333333333333333)'72___':0.136904761904762)'100___':0.123214285714286,(('3250000:3050000':0,'3650000:2350000':0)'2___':0.333333333333333,'3750000:2150000':0.333333333333333)'74___':0.260119047619048)'109___':0.115277777777778,(((('3750000:1850000':0,'3850000:1350000':0,'3950000:1750000':0)'13___':0.333333333333333,'3650000:1250000':0.333333333333333)'84___':0.083333333333334,'3850000:1950000':0.416666666666667)'89___':0.166071428571428,(('3850000:1450000':0.111111111111111,'3850000:1750000':0.111111111111111)'44___':0.180555555555556,'3850000:1550000':0.291666666666667)'70___':0.291071428571428)'108___':0.125992063492064)'114___':0.0437019469246031,((((('3250000:650000':0.142857142857143,'3350000:650000':0.142857142857143)'51___':0.123809523809524,'3450000:650000':0.266666666666667)'66___':0.175,('2950000:50000':0,'3150000:550000':0,'2550000:1050000':0,'2950000:350000':0)'33___':0.441666666666667)'95___':0.130952380952381,'3750000:1650000':0.572619047619048)'105___':0.11281001984127,(('3550000:950000':0.25,'3650000:1150000':0.25)'63___':0.305555555555556,'3750000:1550000':0.555555555555556)'103___':0.129873511904762)'112___':0.0670030381944441)'118___':0.174675924254782)'122___':0.034155718857885)'124___':0.0206081758641999,(((((('2550000:850000':0,'2650000:950000':0,'2450000:1250000':0,'2150000:1150000':0,'2650000:850000':0)'40___':0.333333333333333,('2250000:1050000':0,'2350000:1250000':0,'2750000:950000':0)'37___':0.333333333333333)'78___':0.108333333333334,('2350000:1050000':0.333333333333333,'2750000:850000':0.333333333333333)'76___':0.108333333333334)'94___':0.020089285714285,((('2450000:1050000':0.142857142857143,'2550000:950000':0.142857142857143)'48___':0.053571428571428,'2450000:1150000':0.196428571428571)'53___':0.071428571428572,(('2350000:950000':0,'2450000:950000':0)'1___':0.111111111111111,'2250000:950000':0.111111111111111)'45___':0.156746031746032)'67___':0.193898809523809)'98___':0.220238095238096,(('2150000:1050000':0,'2350000:1150000':0)'36___':0.333333333333333,'2250000:1250000':0.333333333333333)'82___':0.348660714285715)'111___':0.049107142857143,(('1950000:1450000':0,'1950000:1350000':0,'2050000:1350000':0)'39___':0.333333333333333,('2050000:1250000':0,'2150000:1250000':0)'7___':0.333333333333333)'73___':0.397767857142858)'115___':0.250770734155438)'125___':0)'126___':0
link_minimum (((('3750000:1650000':0.428571428571429,(('3850000:1950000':0.333333333333333,('2950000:50000':0,'3150000:550000':0,'2550000:1050000':0,'2950000:350000':0)'33___':0.333333333333333,'3850000:1850000':0.333333333333333,'3650000:1850000':0.333333333333333,'3350000:950000':0.333333333333333,'3750000:1350000':0.333333333333333,'3850000:1650000':0.333333333333333,'3250000:950000':0.333333333333333,'3350000:850000':0.333333333333333,('3150000:750000':0.2,'3150000:850000':0.2,'3050000:850000':0.2,'3250000:850000':0.2)'65___':0.133333333333333,('2950000:250000':0,'3050000:250000':0)'14___':0.333333333333333,('3450000:1250000':0,'3550000:1250000':0)'4___':0.333333333333333,'3450000:750000':0.333333333333333,('2150000:1050000':0,'2350000:1150000':0)'36___':0.333333333333333,('3650000:2050000':0.111111111111111,'3650000:1950000':0.111111111111111,'3750000:2050000':0.111111111111111)'47___':0.222222222222222,'3750000:1950000':0.333333333333333,((((('3450000:950000':0.125,'3550000:1050000':0.125)'48___':0.075,'3550000:1150000':0.2)'71___':0.030769230769231,'3450000:850000':0.230769230769231)'75___':0.019230769230769,'3450000:1150000':0.25)'78___':0.022727272727273,(('3650000:1450000':0,'3650000:1550000':0)'31___':0.2,'3450000:1050000':0.2)'69___':0.072727272727273)'81___':0.06060606060606,('3650000:1350000':0.2,'3750000:1450000':0.2)'73___':0.133333333333333,('1950000:1450000':0,'1950000:1350000':0,'2050000:1350000':0)'39___':0.333333333333333,'2250000:1250000':0.333333333333333,('3250000:3050000':0,'3650000:2350000':0)'2___':0.333333333333333,'3550000:1450000':0.333333333333333,('2050000:1250000':0,'2150000:1250000':0)'7___':0.333333333333333,('3650000:1650000':0.2,'3650000:1750000':0.2)'68___':0.133333333333333,('3350000:1150000':0,'3450000:1350000':0,'3550000:1550000':0,'3350000:1050000':0,'3350000:1250000':0,'3450000:1550000':0,'3350000:1350000':0,'3450000:1450000':0)'38___':0.333333333333333,'3650000:1250000':0.333333333333333,(('3850000:1450000':0.111111111111111,'3850000:1750000':0.111111111111111)'46___':0.138888888888889,'3850000:1550000':0.25)'79___':0.083333333333333,((('3250000:350000':0.2,('3150000:650000':0,'2850000:750000':0,'2950000:750000':0)'41___':0.2,('3050000:50000':0,'3250000:450000':0)'12___':0.2,('2550000:750000':0,'2650000:750000':0)'34___':0.2,((('3150000:150000':0,'3150000:250000':0)'16___':0.142857142857143,'3250000:250000':0.142857142857143,(('2950000:650000':0.0909090909090909,'3050000:650000':0.0909090909090909)'42___':0.0202020202020201,'3150000:350000':0.111111111111111)'45___':0.031746031746032,('3050000:150000':0,'2850000:650000':0,'3150000:50000':0,'3050000:350000':0,'3250000:150000':0)'27___':0.142857142857143)'55___':0.023809523809524,'3050000:750000':0.166666666666667)'57___':0.033333333333333,('2750000:650000':0,'3050000:550000':0)'32___':0.2,'2650000:650000':0.2,('3250000:650000':0.142857142857143,'3350000:650000':0.142857142857143)'52___':0.057142857142857,'3450000:650000':0.2)'74___':0.05,(((('2350000:950000':0,'2450000:950000':0)'1___':0.111111111111111,'2250000:950000':0.111111111111111)'43___':0.031746031746032,'2450000:1050000':0.142857142857143,'2450000:1150000':0.142857142857143,'2550000:950000':0.142857142857143)'54___':0.057142857142857,('2550000:850000':0,'2650000:950000':0,'2450000:1250000':0,'2150000:1150000':0,'2650000:850000':0)'40___':0.2)'58___':0.05,'2750000:850000':0.25)'80___':0.044117647058823,'3350000:750000':0.294117647058823)'82___':0.03921568627451,(('3550000:2050000':0.142857142857143,'3550000:2250000':0.142857142857143)'56___':0.057142857142857,('3350000:2150000':0,'3450000:2050000':0)'35___':0.2)'60___':0.133333333333333,('3150000:2950000':0,'3250000:2150000':0)'11___':0.333333333333333,'3250000:2950000':0.333333333333333,('3750000:1850000':0,'3850000:1350000':0,'3950000:1750000':0)'13___':0.333333333333333,'3750000:1250000':0.333333333333333,('3550000:950000':0.25,'3650000:1150000':0.25)'77___':0.083333333333333,'3750000:2150000':0.333333333333333,('2250000:1050000':0,'2350000:1250000':0,'2750000:950000':0)'37___':0.333333333333333,'2350000:1050000':0.333333333333333,('3350000:2050000':0,'3450000:2150000':0,'3250000:2850000':0,'3550000:2150000':0)'23___':0.333333333333333,'3750000:1750000':0.333333333333333)'120___':0.066666666666667,'2750000:750000':0.4)'121___':0.028571428571429,'3550000:1950000':0.428571428571429)'123___':0.015873015873015,'3250000:750000':0.444444444444444)'124___':0.055555555555556,'3750000:1550000':0.5)'125___':0)'126___':0
link_maximum (((((('3350000:750000':0.333333333333333,'3450000:750000':0.333333333333333)'78___':0.140350877192983,(('3450000:950000':0.125,'3550000:1050000':0.125)'46___':0.075,'3550000:1150000':0.2)'53___':0.273684210526316)'86___':0.16267942583732,('3450000:1150000':0.25,'3450000:850000':0.25)'63___':0.386363636363636)'101___':0.163636363636364,(((('2950000:650000':0.0909090909090909,'3050000:650000':0.0909090909090909)'42___':0.13986013986014,'3050000:750000':0.230769230769231)'60___':0.307692307692307,'2750000:750000':0.538461538461538)'91___':0.017094017094018,((('2750000:650000':0,'3050000:550000':0)'32___':0.2,'2650000:650000':0.2)'55___':0.3,('2550000:750000':0,'2650000:750000':0)'34___':0.5)'89___':0.055555555555556)'94___':0.244444444444444)'111___':0.2,(((('3250000:3050000':0,'3650000:2350000':0)'2___':0.333333333333333,'3750000:2150000':0.333333333333333)'81___':0.333333333333334,('3750000:1250000':0.333333333333333,'3750000:1350000':0.333333333333333)'71___':0.333333333333334)'103___':0.083333333333333,(('3850000:1650000':0.333333333333333,'3850000:1850000':0.333333333333333)'73___':0.222222222222223,('3250000:650000':0.142857142857143,'3350000:650000':0.142857142857143)'51___':0.412698412698413)'95___':0.194444444444444)'110___':0.25,(('2350000:1050000':0.333333333333333,'2750000:850000':0.333333333333333)'64___':0.333333333333334,(((('2450000:1050000':0.142857142857143,'2550000:950000':0.142857142857143)'48___':0.107142857142857,'2450000:1150000':0.25)'62___':0.083333333333333,(('2350000:950000':0,'2450000:950000':0)'1___':0.111111111111111,'2250000:950000':0.111111111111111)'45___':0.222222222222222)'80___':0.095238095238096,('2550000:850000':0,'2650000:950000':0,'2450000:1250000':0,'2150000:1150000':0,'2650000:850000':0)'40___':0.428571428571429)'84___':0.238095238095238,(('2250000:1050000':0,'2350000:1250000':0,'2750000:950000':0)'37___':0.333333333333333,('2050000:1250000':0,'2150000:1250000':0)'7___':0.333333333333333)'68___':0.333333333333334)'106___':0.333333333333333,(('3250000:950000':0.333333333333333,'3350000:950000':0.333333333333333)'75___':0.166666666666667,'3350000:850000':0.5)'90___':0.5,(((('2950000:50000':0,'3150000:550000':0,'2550000:1050000':0,'2950000:350000':0)'33___':0.333333333333333,'3450000:650000':0.333333333333333)'67___':0.266666666666667,'3750000:1650000':0.6)'98___':0.15,(('3550000:950000':0.25,'3650000:1150000':0.25)'61___':0.305555555555556,'3750000:1550000':0.555555555555556)'93___':0.194444444444444)'109___':0.25,(('3150000:750000':0.2,'3150000:850000':0.2)'59___':0.4,('3050000:850000':0.2,'3250000:850000':0.2)'54___':0.4)'96___':0.4,(((('3050000:150000':0,'2850000:650000':0,'3150000:50000':0,'3050000:350000':0,'3250000:150000':0)'27___':0.142857142857143,'3150000:350000':0.142857142857143)'49___':0.19047619047619,'3250000:350000':0.333333333333333)'69___':0.266666666666667,(('2950000:250000':0,'3050000:250000':0)'14___':0.333333333333333,('3050000:50000':0,'3250000:450000':0)'12___':0.333333333333333)'66___':0.266666666666667)'100___':0.4,('1950000:1450000':0,'1950000:1350000':0,'2050000:1350000':0)'39___':1,((('3650000:1250000':0.333333333333333,'3850000:1550000':0.333333333333333)'76___':0.095238095238096,('3850000:1450000':0.111111111111111,'3850000:1750000':0.111111111111111)'44___':0.317460317460318)'83___':0.285714285714285,(('3750000:1850000':0,'3850000:1350000':0,'3950000:1750000':0)'13___':0.333333333333333,'3850000:1950000':0.333333333333333)'74___':0.380952380952381)'108___':0.285714285714286,((('2150000:1050000':0,'2350000:1150000':0)'36___':0.333333333333333,'2250000:1250000':0.333333333333333)'72___':0.380952380952381,((('3150000:150000':0,'3150000:250000':0)'16___':0.142857142857143,'3250000:250000':0.142857142857143)'47___':0.19047619047619,('3150000:650000':0,'2850000:750000':0,'2950000:750000':0)'41___':0.333333333333333)'65___':0.380952380952381)'107___':0.285714285714286,(((('3550000:1450000':0.5,(('3350000:1150000':0,'3450000:1350000':0,'3550000:1550000':0,'3350000:1050000':0,'3350000:1250000':0,'3450000:1550000':0,'3350000:1350000':0,'3450000:1450000':0)'38___':0.333333333333333,'3750000:1750000':0.333333333333333)'79___':0.166666666666667,('3450000:1250000':0,'3550000:1250000':0)'4___':0.5)'88___':0.1,'3550000:1950000':0.6)'99___':0.066666666666667,('3650000:1650000':0.2,'3650000:1750000':0.2)'57___':0.466666666666667)'104___':0.133333333333333,((('3650000:1350000':0.2,'3750000:1450000':0.2)'56___':0.355555555555556,(('3650000:1450000':0,'3650000:1550000':0)'31___':0.2,'3450000:1050000':0.2)'52___':0.355555555555556)'92___':0.08080808080808,'3250000:750000':0.636363636363636)'102___':0.163636363636364)'112___':0.2,(('3150000:2950000':0,'3250000:2150000':0)'11___':0.333333333333333,'3250000:2950000':0.333333333333333)'77___':0.666666666666667,((('3350000:2150000':0,'3450000:2050000':0)'35___':0.333333333333333,('3350000:2050000':0,'3450000:2150000':0,'3250000:2850000':0,'3550000:2150000':0)'23___':0.333333333333333)'70___':0.266666666666667,('3550000:2050000':0.142857142857143,'3550000:2250000':0.142857142857143)'50___':0.457142857142857)'97___':0.4,(((('3650000:1950000':0.111111111111111,'3650000:2050000':0.111111111111111)'43___':0.088888888888889,'3750000:2050000':0.2)'58___':0.2,'3750000:1950000':0.4)'82___':0.028571428571429,'3650000:1850000':0.428571428571429)'85___':0.571428571428571)'125___':0)'126___':0
