#!/usr/bin/perl -w
use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;

#use FindBin qw/$Bin/;
#use lib "$Bin/lib";
use rlib;

use Test::More tests => 17;
use Test::Exception;

local $| = 1;

use Biodiverse::BaseData;
use Biodiverse::Indices;
use Biodiverse::TestHelpers qw {:basedata :tree};

use Scalar::Util qw /blessed/;

{
    #  some helper vars
    my ($is_error, $e);
    
    #  ideally we shouldn't need to do this but the hierarchical subs need it
    my @res = (10, 10);
    my $bd = get_basedata_object(
	x_spacing  => $res[0],
	y_spacing  => $res[1],
	x_max      => $res[0],
	y_max      => $res[1],
	CELL_SIZES => \@res,
    );


    my $indices = eval {Biodiverse::Indices->new(BASEDATA_REF => $bd)};
    is (blessed $indices, 'Biodiverse::Indices', 'Sub new works');

    my %calculations = eval {$indices->get_calculations};
    $e = $EVAL_ERROR;
    ok (!$e, 'Get calculations without eval error');

    my %indices_to_calc = eval {$indices->get_indices};
    $e = $EVAL_ERROR;
    ok (!$e, 'Get indices without eval error');

    my %required_args = eval {$indices->get_required_args};
    $e = $EVAL_ERROR;
    ok (!$e, 'Get required args without eval error');

    my @calc_array =
        qw/calc_sorenson
            calc_elements_used
            calc_pe
            calc_endemism_central
            calc_endemism_whole
	    calc_numeric_label_stats
        /;
    my %calc_hash;
    @calc_hash{@calc_array} = (0) x scalar @calc_array;
    $calc_hash{calc_sorenson} = 1;  #  1 if we should get an exception
    $calc_hash{calc_numeric_label_stats} = 1;

    my $calc_args = {
	tree_ref      => get_tree_object(),
	element_list1 => [],
    };

    foreach my $calc (sort keys %calc_hash) {
	my %dep_tree = eval {
	    $indices->parse_dependencies_for_calc (
		calculation    => $calc,
		nbr_list_count => 1,
		calc_args      => $calc_args,
	    )
	};
	$e = $EVAL_ERROR;
	my $with_or_without = $calc_hash{$calc} ? 'with' : 'without';
	$is_error = $e ? 1 : 0;
	my $expected_error = $calc_hash{$calc} ? 1 : 0;
	is ($is_error, $expected_error, "Parsed dependency tree $with_or_without error being raised ($calc)");
    }
    
    #$calc_args = {};
    my $valid_calcs = eval {
	$indices->get_valid_calculations (
	    calculations   => \%calc_hash,
	    nbr_list_count => 1,
            calc_args      => $calc_args,
	);
    };
    $e = $EVAL_ERROR;
    diag $e->message if blessed $e;
    $is_error = $EVAL_ERROR ? 1 : 0;
    is ($is_error, 0, "Obtained valid calcs without error");
    
    my $calcs_to_run = $indices->get_valid_calculations_to_run;
    $e = $EVAL_ERROR;
    diag $e->message if blessed $e;
    $is_error = $EVAL_ERROR ? 1 : 0;
    is ($is_error, 0, "Obtained valid calcs to run without error");
    
    #  need to use the basedata object for these next few
    my @el_list1 = qw /15:15 15:25/;
    #my @el_list2 = qw /10_3 10_4/;
    my %elements = (
        element_list1 => \@el_list1,
        #element_list2 => \@el_list2,
    );

    #  run the global pre_calcs
    eval {$indices->run_precalc_globals(%$calc_args); print "\n"};
    $e = $EVAL_ERROR;
    ok (!$e, 'pre_calc_globals had no eval errors');

    my %sp_calc_values = eval {$indices->run_calculations(%$calc_args, %elements)};
    $e = $EVAL_ERROR;
    ok (!$e, 'run_calculations had no eval errors');
    diag $e if $e;

    eval {$indices->run_postcalc_globals (%$calc_args)};
    $e = $EVAL_ERROR;
    ok (!$e, 'run_postcalc_globals had no eval errors');
    
    #  this should throw an exception
    my %results = eval {
	$indices->run_calculations(
	    calculations  => ['calc_abc'],
	    element_list1 => ['1000:1000'],
	);
    };
    $e = $EVAL_ERROR;
    ok ($e, 'calc_abc with non-existent group throws error');
    
    $valid_calcs = eval {
	$indices->get_valid_calculations (
	    calculations   => [qw /calc_richness calc_abc calc_abc2 calc_abc3/],
	    nbr_list_count => 1,
	);
    };
    $e = $EVAL_ERROR;
    $valid_calcs = $indices->get_valid_calculations_to_run;
    is (scalar keys %$valid_calcs, 0, 'no valid calculations without required args');
    
}

