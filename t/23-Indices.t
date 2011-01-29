#!/usr/bin/perl -w
use strict;
use warnings;
use English qw { -no_match_vars };

use Test::More tests => 4;
use Test::Exception;

local $| = 1;

use mylib;

use Biodiverse::BaseData;
use Biodiverse::Indices;
use Biodiverse::TestHelpers qw {:basedata};

use Scalar::Util qw /blessed/;

{
    #  some helper vars
    my ($is_error, $e);
    
    #  ideally we shouldn't need to do this but the hierarchical subs need it
    my @res = (10, 10);
    my $bd = get_basedata_object(
	x_spacing  => $res[0],
	y_spacing  => $res[1],
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
    
}
