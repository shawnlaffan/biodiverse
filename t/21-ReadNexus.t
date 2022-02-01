use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;

use FindBin qw/$Bin/;
use rlib;

use Test2::V0;

use Data::Section::Simple qw(get_data_section);

use Biodiverse::TestHelpers qw /:tree/;


local $| = 1;

use Biodiverse::ReadNexus;
use Biodiverse::Tree;

our $tol = 1E-13;



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
        my $msg = "$sub expected $test->{ex} +/- $tol";

        my $val = $tree->$sub;
        my $expected = $test->{ex};
        #diag "$msg, $val\n";

        ok (abs ($val - $expected) <= $tol, $msg);
    }

    return;    
}

