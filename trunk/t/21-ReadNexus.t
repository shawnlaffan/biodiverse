#!/usr/bin/perl -w
use strict;
use warnings;

use FindBin qw/$Bin/;
use lib "$Bin/lib";

use Test::More tests => 23;

use Data::Section::Simple qw(get_data_section);

use Biodiverse::TestHelpers qw /:tree/;


local $| = 1;

use Biodiverse::ReadNexus;
use Biodiverse::Tree;

#  from Statistics::Descriptive
sub is_between
{
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    
    my ($have, $want_bottom, $want_top, $blurb) = @_;

    ok (
        (($have >= $want_bottom) &&
        ($want_top >= $have)),
        $blurb
    );
}


my $tol = 1E-13;

#  clean read of 'neat' nexus file
{
    my $nex_tree = get_nexus_tree_data();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $nex_tree);
    };

    is ($result, 1, 'import nexus trees, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 2, 'two trees extracted');

    my $tree = $trees[0];

    run_tests ($tree);
}


#  clean read of working newick file
{
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

{
    my $data = get_tabular_tree_data();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $data);
    };

    is ($result, 1, 'import clean tabular tree, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 1, 'one tree extracted');

    my $tree = $trees[0];

    run_tests ($tree);
}



#  read of a 'messy' nexus file with no newlines
SKIP:
{
    skip 'No system parses nexus trees with no newlines', 2;
    my $data = get_nexus_tree_data();

    #  eradicate newlines
    $data =~ s/[\r\n]+//gs;
    #print $data;
  TODO:
    {
        local $TODO = 'issue 149';

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
        my $upper = $test->{ex} + $tol;
        my $lower = $test->{ex} - $tol;
        my $msg = "$sub expected $test->{ex}";

        #my $val = $tree->$sub;
        #warn "$msg, $val\n";

        is_between (eval {$tree->$sub}, $lower, $upper, $msg);
    }

    return;    
}

