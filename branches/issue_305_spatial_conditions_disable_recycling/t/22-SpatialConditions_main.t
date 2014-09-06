#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;

use rlib;
use Scalar::Util qw /looks_like_number/;
use Data::Dumper qw /Dumper/;
#use Test::More tests => 255;
use Test::More;

local $| = 1;

use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;
use Biodiverse::TestHelpers qw {:spatial_conditions};

#  need to build these from tables
#  need to add more
#  the ##1 notation is odd, but is changed for each test using regexes
my %conditions = (
    circle => {
        'sp_circle (radius => ##1)' => 5,
        'sp_circle (radius => ##2)' => 13,
        'sp_circle (radius => ##3)' => 29,
        'sp_circle (radius => ##4)' => 49,
        '$D <= ##1' => 5,
        '$D <= ##4' => 49,
        #'$d[0] <= ##4 && $d[0] >= -##4 && $D <= ##4' => 49,  #  exercise the spatial index offset search
    },
    selectors => {
        'sp_select_all()' => 900,
        'sp_self_only()'  => 1,
    },
    combined => {
        'sp_select_all() && ! sp_circle (radius => ##1)' => 895,
        '! sp_circle (radius => ##1) && sp_select_all()' => 895,
    },
    ellipse => {
        'sp_ellipse (major_radius =>  ##4, minor_radius =>  ##2)' => 25,
        'sp_ellipse (major_radius =>  ##2, minor_radius =>  ##2)' => 13,
        'sp_ellipse (major_radius =>  ##4, minor_radius =>  ##2, rotate_angle => 1.308996939)' => 25,
    
        'sp_ellipse (major_radius => ##10, minor_radius => ##5)' => 159,
        'sp_ellipse (major_radius => ##10, minor_radius => ##5, rotate_angle => 0)'   => 159,
        'sp_ellipse (major_radius => ##10, minor_radius => ##5, rotate_angle => Math::Trig::pi)'   => 159,
        'sp_ellipse (major_radius => ##10, minor_radius => ##5, rotate_angle => Math::Trig::pip2)' => 159,
        'sp_ellipse (major_radius => ##10, minor_radius => ##5, rotate_angle => Math::Trig::pip4)' => 153,
    },
    block => {
        'sp_block (size => ##3)' => 9,
        'sp_block (size => [##3, ##3])' => 9,
    },
);


exit main( @ARGV );

sub main {
    my @args  = @_;

    my @res_pairs = get_sp_cond_res_pairs_to_use (@args);
    my %conditions_to_run = get_sp_conditions_to_run (\%conditions, @args);

    foreach my $key (sort keys %conditions_to_run) {
        #diag $key;
        test_sp_cond_res_pairs ($conditions{$key}, @res_pairs);
    }

    done_testing;
    return 0;
}
