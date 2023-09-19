use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;

use FindBin qw/$Bin/;
use rlib;

use Test2::V0;

use Data::Section::Simple qw(get_data_section);

use Biodiverse::TestHelpers qw /:tree/;

use List::Util qw /sum/;

local $| = 1;

use Biodiverse::ReadNexus;
use Biodiverse::Tree;

my $tol = 1E-10;



use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @subs = grep {$_ =~ 'main::test_'} $obj->functions();


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

    foreach my $sub (sort @subs) {
        no strict 'refs';
        $sub->();
    }
    
    done_testing;
    return 0;
}



#  clean read of 'neat' nexus file
sub test_neat_nexus_file {
    my $nex_tree = get_nexus_tree_data();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $nex_tree);
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    is ($result, 1, 'import nexus trees, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 2, 'two trees extracted');

    my $tree = $trees[0];

    run_tests ($tree);
}


#  clean read of working newick file
sub test_clean_read_of_working_newick_file {
    my $data = get_newick_tree_data();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $data);
    };

    is ($result, 1, 'import clean newick trees, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 1, 'one tree extracted');

    my $tree = $trees[0];

    run_tests ($tree);
}

sub test_tabular_tree {
    my $data = get_tabular_tree_data();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $data);
    };
    my $e = $EVAL_ERROR;
    note $e if $e;

    is ($result, 1, 'import clean tabular tree, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 1, 'one tree extracted from tabular tree data');

    my $tree = $trees[0];

    #local $tol = 1E-8;
    run_tests ($tree);
}

sub test_tabular_tree_unix_line_endings {
    my $data = get_tabular_tree_data_x2();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $data);
    };
    note $EVAL_ERROR if $EVAL_ERROR;

    is ($result, 1, 'import clean tabular trees, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 2, 'two trees extracted from tabular tree data');

    foreach my $tree (@trees) {
        run_tests ($tree);
    }
}

sub test_tabular_tree_file_no_exists {
    my $phylogeny_ref = Biodiverse::ReadNexus->new;

    my $temp_file = get_temp_file_path('bd_should_not_exist_XXXX.txt');

    # define map to read sample file
    my $column_map = {
        TREENAME_COL       => 6, 
        LENGTHTOPARENT_COL => 2,
        NODENUM_COL        => 4,
        NODENAME_COL       => 3,
        PARENT_COL         => 5,
    };

    # import tree from file
    
    my $result = eval {
        $phylogeny_ref->import_tabular_tree (
            file       => $temp_file,
            column_map => $column_map
        );
    };
    my $e = $EVAL_ERROR;
    #diag $e if $e;
    ok ($e, 'import tabular tree throws exception for non-existent file');
    ok (!$result, 'import tabular tree fails for non-existent file');
}

sub test_tabular_tree_empty_data {
    my $phylogeny_ref = Biodiverse::ReadNexus->new;
    my $read_file = get_temp_file_path('biodiverse_tabular_tree_export_XXXX.txt');

    # define map to read sample file
    my $column_map = {
        TREENAME_COL       => 6, 
        LENGTHTOPARENT_COL => 2,
        NODENUM_COL        => 4,
        NODENAME_COL       => 3,
        PARENT_COL         => 5,
    };

    # import tree from file
    
    my $result = eval {
        $phylogeny_ref->import_tabular_tree (
            file       => $read_file,
            column_map => $column_map
        );
    };
    my $e = $EVAL_ERROR;
    #diag $e if $e;
    ok ($e, 'import tabular tree throws exception for empty file');
    ok (!$result, 'import tabular tree fails for empty file');
    
    $result = eval {
        $phylogeny_ref->import_tabular_tree (
            data       => undef,
            column_map => $column_map
        );
    };
    $e = $EVAL_ERROR;
    #diag $e if $e;
    ok ($e, 'import tabular tree throws exception for empty data');
    ok (!$result, 'import tabular tree fails for empty data');
    
}

sub test_tabular_tree_from_file {
    my $data = get_tabular_tree_data();

    my $phylogeny_ref = Biodiverse::ReadNexus->new;

    my $initial_tabular_file =  write_data_to_temp_file($data);

    # define map to read sample file
    my $column_map = {
        TREENAME_COL       => 6, 
        LENGTHTOPARENT_COL => 2,
        NODENUM_COL        => 4,
        NODENAME_COL       => 3,
        PARENT_COL         => 5,
    };

    # import tree from file
    
    my $result = eval {
        $phylogeny_ref->import_tabular_tree (
            file       => $initial_tabular_file,
            column_map => $column_map
        );
    };
    diag $EVAL_ERROR if $EVAL_ERROR;
    is ($result, 1, 'import tabular tree');

    # check some properties of imported tree(s)
    
    my $phylogeny_array = $phylogeny_ref->get_tree_array;
    
    my $tree_count = scalar @$phylogeny_array;
    is ($tree_count, 1, 'import tabular tree, count trees');

    foreach my $tree (@$phylogeny_array) {
        is ($tree->get_param ('NAME'), 'Example_tree', 'Check tree name');
    }

    # perform export
    my $exported_tabular_file = get_temp_file_path('biodiverse_tabular_tree_export_XXXX.txt');
    my $export_tree = $phylogeny_array->[0]; 
    $result = eval {
        $export_tree->export_tabular_tree(file => $exported_tabular_file);
    };
    my $e = $EVAL_ERROR;
    diag $e if $e;
    ok (!$e, 'export tabular tree without an exception');

    # re-import
    my $reimport_ref = Biodiverse::ReadNexus->new;
    my $reimport_map = {
        TREENAME_COL       => 7, 
        LENGTHTOPARENT_COL => 3,
        NODENUM_COL        => 5,
        NODENAME_COL       => 4,
        PARENT_COL         => 6,
    };


    $result = eval {
        $reimport_ref->import_tabular_tree (
            file       => $exported_tabular_file,
            column_map => $reimport_map,
        );
    };
    $e = $EVAL_ERROR;
    diag $e if $e;
    ok (!$e, 're-import tabular tree without an exception');

    # check re-import properties    
    my $reimport_array = $reimport_ref->get_tree_array;    
    $tree_count = scalar @$reimport_array;
    is ($tree_count, 1, 're-import tabular tree, tree count');

    foreach my $tree (@$reimport_array) {
        is ($tree->get_name, 'Example_tree', 'Check tree name');
    }

    # compare re-imported tree with exported one
    my $reimport_tree = $reimport_array->[0];

    my $trees_compare;
    $result = eval {
        $trees_compare = $export_tree->trees_are_same(
            comparison => $reimport_tree
        );
    };
    if ($EVAL_ERROR) { print "error $EVAL_ERROR\n"; }
    is ($result, 1, 'perform tree compare');
    is ($trees_compare, 1, 'tabular trip round-trip comparison');
}




#  read of a 'messy' nexus file with no newlines
sub test_nexus_with_no_newlines  {
    SKIP:
    {
        skip 'No system parses nexus trees with no newlines', 2;
        my $data = get_nexus_tree_data();
    
        #  eradicate newlines
        $data =~ s/[\r\n]+//gs;
        #print $data;
      TODO:
        {
            my $todo = todo 'issue 149 - http://code.google.com/p/biodiverse/issues/detail?id=149';
    
            my $trees = Biodiverse::ReadNexus->new;
            my $result = eval {
                $trees->import_data (data => $data);
            };
        
            is ($result, 1, 'import nexus trees, no newlines, no remap');
        
            my @trees = $trees->get_tree_array;
        
            is (scalar @trees, 2, 'two trees extracted');
        
            my $tree = $trees[0];
    
            #run_tests ($tree);
        }
    }
}


sub test_read_R_phylo_json_data {
    use JSON::MaybeXS qw //;
    my $data_no_internals   = get_R_phylo_json_tree_data();
    my $data_with_internals = get_R_phylo_json_tree_data_internal_labels();
    my $data_parsed_to_hash = JSON::MaybeXS::decode_json ($data_no_internals);

    my %json_tree_hash = (
        with_internal_labels => $data_with_internals,
        no_internal_labels   => $data_no_internals,
        as_hash_struct       => $data_parsed_to_hash,
    );

    #  compare with nexus import - other tests will fail if it has issues
    my $nexus_data = get_nexus_tree_data();
    my $comp_trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $comp_trees->import_data (data => $nexus_data);
    };
    croak $@ if $@;
    my @comp_trees = $comp_trees->get_tree_array;
    my $comp_tree  = $comp_trees[0];

    foreach my $tree_type (sort keys %json_tree_hash) {
        my $data = $json_tree_hash{$tree_type};
        my $trees = Biodiverse::ReadNexus->new;
        my $result = eval {
            $trees->import_data (data => $data);
        };

        is ($result, 1, "import R phylo data from JSON, $tree_type");

        my @trees = $trees->get_tree_array;

        is (scalar @trees, 1, "one tree extracted, $tree_type");

        my $tree = $trees[0];

        #  compare trees
        my $comparison = $tree->compare (
            comparison => $comp_tree,
            result_list_name => '_comp',
        );
        #diag "GOT $comparison EXACT MATCHES";
        is $comparison, 61, 'got expected number of matching nodes';

        #  needed in the event the previous test fails
        foreach my $node ($tree->get_terminal_node_refs) {
            my $name  = $node->get_name;
            my $comp_node = $comp_tree->get_node_ref_aa($name);
            my $path  = $node->get_path_length_array_to_root_node_aa;
            my $cpath = $comp_node->get_path_length_array_to_root_node_aa;
            my $sum  = sum @$path;
            my $csum = sum @$cpath;
            ok abs ($sum - $csum) <= $tol, "path sum within tolerance, $sum, $csum, $name";
        }

        if ($tree_type eq 'with_internal_labels') {
            my %nodes      = $tree->get_node_hash;
            my %comp_nodes = $comp_tree->get_node_hash;
            #  clean up non-named internals, first is the root
            my @deleted = delete @comp_nodes{qw /59___ 30___/};
            foreach my $del (@deleted) {
                #  find the equivalent parent in the json-sourced tree
                my @children = $del->get_children;
                my $node_ref = $tree->get_node_ref_aa($children[0]->get_name);
                my $anon_internal_name = $node_ref->get_parent->get_name;
                delete $nodes{$anon_internal_name};
            }
            is [sort keys %nodes],
               [sort keys %comp_nodes],
               'tree with internal labels has correct node names';
        }
        else {
            my %terminals      = $tree->get_terminal_nodes;
            my %comp_terminals = $comp_tree->get_terminal_nodes;
            is [sort keys %terminals],
               [sort keys %comp_terminals],
               'tree with no internal labels has correct tip names';
        }
        
        run_tests ($tree);
    }
    
    #  these should all throw exceptions as they are missing keys, except the commented one which is the base variant
    #  tree struct from R phylo example
    my @bung_data = (
        #'{"edge":[4,5,5,4,5,1,2,3],"edge.length":[2,5,5,7],"Nnode":2,"tip.label":["Pan","Homo","Gorilla"]}',
        '{"edge.length":[2,5,5,7],"Nnode":2,"tip.label":["Pan","Homo","Gorilla"]}',
        '{"edge":[4,5,5,4,5,1,2,3],"edge.length":[2,5,5,7],"tip.label":["Pan","Homo","Gorilla"]}',
        '{"edge":[4,5,5,4,5,1,2,3],"edge.length":[2,5,5,7],"Nnode":2}',
        '{"edge":[4,5,5,4,5,1,2,3],"Nnode":2}',
    );
    foreach my $baddata (@bung_data) {
        my $readnex = Biodiverse::ReadNexus->new;
        #diag $baddata;
        $result = eval {
            $readnex->import_R_phylo (data => $baddata);
        };
        is $@,
          'JSON data is not an R phylo structure',
          'got exception for incorrect JSON data';
    }    
}

#done_testing();


sub run_tests {
    my $tree = shift;

    my @tests = (
        {sub => 'get_node_count',    ex => 61,},
        {sub => 'get_tree_depth',    ex => 12,},
        {sub => 'get_tree_length',   ex => 0.992769230769231,},
        {sub => 'get_length_to_tip', ex => 0.992769230769231,},

        {sub => 'get_total_tree_length',  ex => 21.1822419987155,},    
    );

    foreach my $test (@tests) {
        my $sub   = $test->{sub};
        my $val = $tree->$sub;
        my $expected = $test->{ex};
        my $msg = "$sub, got $val, expected $expected +/- $tol";

        #diag "$msg, $val\n";

        ok (abs ($val - $expected) <= $tol, $msg);
    }

    return;    
}

