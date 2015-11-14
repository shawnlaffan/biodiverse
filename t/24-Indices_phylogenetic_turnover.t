#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

#  don't test plugins
local $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;

my $generate_result_sets = 0;

use Test::Lib;
use Test::Most;
use List::Util qw /sum/;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
    :tree
    :utils
};

my @calcs = qw/
    calc_phylo_abc
    calc_phylo_jaccard
    calc_phylo_s2
    calc_phylo_sorenson
    calc_phylo_rw_turnover
/;


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

    test_indices();

    done_testing;
    return 0;
}

sub test_indices {
    run_indices_test1 (
        calcs_to_test      => [@calcs],
        calc_topic_to_test => 'Phylogenetic Turnover',
        generate_result_sets => $generate_result_sets,
    );
}


done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   
    PHYLO_A        => '1.4927692308',
    PHYLO_ABC      => '9.5566534823',
    PHYLO_B       => '0',
    PHYLO_C       => '8.0638842515',
    PHYLO_JACCARD              => '0.84379791173084',
    PHYLO_S2                   => 0,
    PHYLO_SORENSON             => '0.729801407809261',
    PHYLO_RW_TURNOVER          => '0.548854155622542',
    PHYLO_RW_TURNOVER_A        => '0.714202952209455',
    PHYLO_RW_TURNOVER_B        => 0,
    PHYLO_RW_TURNOVER_C        => '0.868883672903968',
}


@@ RESULTS_1_NBR_LISTS
{   
}


