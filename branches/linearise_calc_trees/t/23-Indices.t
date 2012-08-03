#!/usr/bin/perl -w
use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;

use Test::More tests => 11;
use Test::Exception;

local $| = 1;

use mylib;

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
    diag $e->message if blessed $e;
    $is_error = $EVAL_ERROR ? 1 : 0;
    is ($is_error, 0, 'Get calculations without error');

    my %indices_to_calc = eval {$indices->get_indices};
    $e = $EVAL_ERROR;
    diag $e->message if blessed $e;
    $is_error = $EVAL_ERROR ? 1 : 0;
    is ($is_error, 0, 'Get indices without error');

    my %required_args = eval {$indices->get_required_args};
    $e = $EVAL_ERROR;
    diag $e->message if blessed $e;
    $is_error = $EVAL_ERROR ? 1 : 0;
    is ($is_error, 0, 'Get required args without error');

    my @calc_array =
        qw /calc_sorenson
            calc_elements_used
            calc_pe
            calc_endemism_central
            calc_endemism_whole
        /;
    my %calc_hash;
    @calc_hash{@calc_array} = (0) x scalar @calc_array;
    $calc_hash{calc_sorenson} = 1;  #  1 if we should get an exception

    my $calc_args = {tree_ref => get_tree_object};

    foreach my $calc (sort keys %calc_hash) {
	my %dep_tree = eval {
	    $indices->parse_dependencies_for_calc (
		calculation    => $calc,
		nbr_list_count => 1,
		calc_args      => $calc_args,
	    )
	};
	$e = $EVAL_ERROR;
	#diag $e->message if blessed $e;
	$is_error = $EVAL_ERROR ? 1 : 0;
	my $with_or_without = $calc_hash{$calc} ? 'with' : 'without';
	is ($is_error, $calc_hash{$calc}, "Parsed dependency tree for $with_or_without error ($calc)");
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
    
    #  need a basedata object for these next few
    my %elements;
    #  run the global pre_calcs
    eval {$indices->run_precalc_globals(%$calc_args)};
    croak $EVAL_ERROR if $EVAL_ERROR;
    
    my %sp_calc_values = eval {$indices->run_calculations(%$calc_args, %elements)};
    croak $EVAL_ERROR if $EVAL_ERROR;
    
    eval {$indices->run_postcalc_globals (%$calc_args)};
    croak $EVAL_ERROR if $EVAL_ERROR;
    

}

