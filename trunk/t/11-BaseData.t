#!/usr/bin/perl -w

#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use strict;
use warnings;

use English qw { -no_match_vars };

local $| = 1;

use mylib;

#use Test::More tests => 5;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::TestHelpers qw /:basedata/;

#  this needs work to loop around more of the expected variations
my @setup = (
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lat     => [1, 0],
            is_lon     => [0, 1],
        },
        expected => 'fail',
        message  => 'lat/lon out of bounds',
    },
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lat     => [1, 0],
        },
        expected => 'fail',
        message  => 'lat out of bounds',
    },
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lon     => [1, 0],
        },
        expected => 'fail',
        message  => 'lon out of bounds',
    },
    {
        args => {
            CELL_SIZES => [100000, 100000],
        },
        expected => 'pass',
    },
    {
        args => {
            CELL_SIZES => [100, 100],
        },
        expected => 'pass',
    },
);


{
    foreach my $this_run (@setup ) {
        my $expected = $this_run->{expected} || 'pass';  
        my $args     = $this_run->{args};

        my $string = Data::Dumper::Dumper $args;
        $string =~ s/[\s\n\r]//g;
        $string =~ s/^\$VAR1=//;
        $string =~ s/;$//;

        my $message  = $this_run->{message} || $string;
        
        my $bd = eval {
            get_basedata_object ( %$args, );
        };
        my $error = $EVAL_ERROR;
        if ($expected eq 'fail') {
            ok (defined $error, "Trapped error: $message");
        }
        else {
            ok (defined $bd,    "Imported: $message");
        }
    }
}

{

    my $bd = eval {
        get_basedata_object (
            x_spacing  => 1,
            y_spacing  => 1,
            CELL_SIZES => [1, 1],
            x_max      =>  50,
            y_max      =>  50,
            x_min      => -49,
            y_min      => -49,
        );
    };
    
    $bd->save (filename => 'bd_test1.bds');

    #  clunky...
    my @groups = ('0.5:0.5', '-1.5:0.5', '0.5:-1.5', '-1.5:-1.5', '1.5:1.5');
    foreach my $group (@groups) {
        ok ($bd->exists_group(group => $group), "Group $group exists");
    }

    
}


done_testing();