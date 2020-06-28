#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

#  don't test plugins
local $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;

my $generate_result_sets = 0;

use rlib;
use Test2::V0;

use List::Util qw /sum/;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
    :tree
    :utils
};

### dirty cheat
{
    package Biodiverse::Indices;
    use parent 'BiodiverseX::Indices::Phylogenetic';
}


my @calcs = qw/
    calc_taxonomic_distinctness
    calc_taxonomic_distinctness_binary
/;

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

sub test_indices {
    run_indices_test1 (
        calcs_to_test      => [@calcs],
        calc_topic_to_test => ['Taxonomic Distinctness Indices'],
        generate_result_sets => $generate_result_sets,
    );
}



done_testing();

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   TDB_DENOMINATOR            => 182,
    TDB_DISTINCTNESS           => '0.385156952955119',
    TDB_NUMERATOR              => '70.0985654378316',
    TDB_VARIATION              => '0.0344846899770178',
    TD_DENOMINATOR             => 6086,
    TD_DISTINCTNESS            => '0.312902618192633',
    TD_NUMERATOR               => '1904.32533432037',
    TD_VARIATION               => '8.14607553623072'
}


@@ RESULTS_1_NBR_LISTS
{   TDB_DENOMINATOR            => 2,
    TDB_DISTINCTNESS           => '0.341398923434153',
    TDB_NUMERATOR              => '0.682797846868306',
    TDB_VARIATION              => '0',
    TD_DENOMINATOR             => 16,
    TD_DISTINCTNESS            => '0.341398923434153',
    TD_NUMERATOR               => '5.46238277494645',
    TD_VARIATION               => '0.815872574453991'
}


