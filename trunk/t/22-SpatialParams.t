#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;
use English qw { -no_match_vars };

#use Test::More tests => 255;
use Test::More;

local $| = 1;

use mylib;

use Biodiverse::BaseData;
use Biodiverse::SpatialParams;
use Biodiverse::TestHelpers qw {:basedata};

#  need to build these from tables
#  need to add more
#  the ##1 notation is odd, but is changed for each test using regexes
my %conditions = (
    'sp_circle (radius => ##1)' => 5,
    'sp_circle (radius => ##2)' => 13,
    'sp_circle (radius => ##3)' => 29,
    'sp_circle (radius => ##4)' => 49,
    
    'sp_select_all()' => 900,
    'sp_self_only()'  => 1,
    
    'sp_ellipse (major_radius =>  ##4, minor_radius =>  ##2)' => 25,
    'sp_ellipse (major_radius =>  ##2, minor_radius =>  ##2)' => 13,
    'sp_ellipse (major_radius =>  ##4, minor_radius =>  ##2, rotate_angle => 1.308996939)' => 25,
    
    'sp_ellipse (major_radius => ##10, minor_radius => ##5)' => 159,
    'sp_ellipse (major_radius => ##10, minor_radius => ##5, rotate_angle => 0)'   => 159,
    'sp_ellipse (major_radius => ##10, minor_radius => ##5, rotate_angle => Math::Trig::pi)'   => 159,
    'sp_ellipse (major_radius => ##10, minor_radius => ##5, rotate_angle => Math::Trig::pip2)' => 159,
    'sp_ellipse (major_radius => ##10, minor_radius => ##5, rotate_angle => Math::Trig::pip4)' => 153,

    'sp_select_all() && ! sp_circle (radius => ##1)' => 895,
    '! sp_circle (radius => ##1) && sp_select_all()' => 895,
    
    'sp_block (size => ##3)' => 9,
    'sp_block (size => [##3, ##3])' => 9,
    'sp_select_block (size => ##5, count => 2)' => 2,
    'sp_select_block (size => ##3, count => 3)' => 3,
    
    'sp_is_left_of()' => 420,
    'sp_is_left_of(vector_angle => 0)' => 420,
    'sp_is_left_of(vector_angle => Math::Trig::pip2)' => 450,
    'sp_is_left_of(vector_angle => Math::Trig::pip4)' => 435,
    'sp_is_left_of(vector_angle_deg => 0)'  => 420,
    'sp_is_left_of(vector_angle_deg => 45)' => 435,
    'sp_is_left_of(vector_angle_deg => 90)' => 450,

    'sp_is_right_of()' => 450,
    'sp_is_right_of(vector_angle => 0)' => 450,
    'sp_is_right_of(vector_angle => Math::Trig::pip2)' => 420,
    'sp_is_right_of(vector_angle => Math::Trig::pip4)' => 435,
    'sp_is_right_of(vector_angle_deg => 0)'  => 450,
    'sp_is_right_of(vector_angle_deg => 45)' => 435,
    'sp_is_right_of(vector_angle_deg => 90)' => 420,
);


SKIP:
{
    #skip ('because', 48);
    
    my @res = (10, 10);
    my @x   = (1, 30);
    my @y   = @x;
    my $bd = get_basedata_object(
        x_spacing  => $res[0],
        y_spacing  => $res[1],
        CELL_SIZES => \@res,
        x_max      => $x[1],
        y_max      => $y[1],
        x_min      => $x[0],
        y_min      => $y[0],
    );

    #  should sub this - get centre_group or something
    my $element_x = $res[0] * (($x[0] + $x[1]) / 2) + $res[0];
    my $element_y = $res[1] * (($y[0] + $y[1]) / 2) + $res[1];
    my $element = join ":", $element_x, $element_y;

    run_tests (
        basedata => $bd,
        element  => $element,
    );
}


#  now try for negative coords
SKIP:
{
    #skip ('because', 48);
    
    my @res = (10, 10);
    my @x   = (-30, -1);
    my @y   = @x;
    my $bd = get_basedata_object(
        x_spacing  => $res[0],
        y_spacing  => $res[1],
        CELL_SIZES => \@res,
        x_max      => $x[1],
        y_max      => $y[1],
        x_min      => $x[0],
        y_min      => $y[0],
    );

    my $element_x = $res[0] * (($x[0] + $x[1]) / 2) + $res[0];
    my $element_y = $res[1] * (($y[0] + $y[1]) / 2) + $res[1];
    my $element = join ":", $element_x, $element_y;

    run_tests (
        basedata => $bd,
        element  => $element,
    );
}

#  now try for a mix of +ve and -ve coords
SKIP:
{
    #skip ('because', 48);
    
    my @res = (10, 10);
    my @x = (-14, 15);
    my @y = @x;
    my $bd = get_basedata_object(
        x_spacing  => $res[0],
        y_spacing  => $res[1],
        CELL_SIZES => \@res,
        x_max      => $x[1],
        y_max      => $y[1],
        x_min      => $x[0],
        y_min      => $y[0],
    );

    my $element_x = $res[0] * (($x[0] + $x[1]) / 2) + $res[0];
    my $element_y = $res[1] * (($y[0] + $y[1]) / 2) + $res[1];
    my $element = join ":", $element_x, $element_y;

    run_tests (
        basedata => $bd,
        element  => $element,
    );
}

#  now try for +ve coords
#  but with cell sizes < 1
SKIP:
{
    #skip 'because', 48;
    
    my @res = (0.1, 0.1);
    my @x = (1, 30);
    my @y = @x;
    my $bd = get_basedata_object(
        x_spacing  => $res[0],
        y_spacing  => $res[1],
        CELL_SIZES => \@res,
        x_max      => $x[1],
        y_max      => $y[1],
        x_min      => $x[0],
        y_min      => $y[0],
    );

    my $element_x = $res[0] * (($x[0] + $x[1]) / 2) + $res[0];
    my $element_y = $res[1] * (($y[0] + $y[1]) / 2) + $res[1];
    my $element = join ":", $element_x, $element_y;

    run_tests (
        basedata => $bd,
        element  => $element,
    );
}


#  now try for a mix of +ve and -ve coords
#  but with cell sizes < 1
{
    my @res = (0.1, 0.1);
    my @x = (-14, 15);
    my @y = @x;
    my $bd = get_basedata_object(
        x_spacing  => $res[0],
        y_spacing  => $res[1],
        CELL_SIZES => \@res,
        x_max      => $x[1],
        y_max      => $y[1],
        x_min      => $x[0],
        y_min      => $y[0],
    );

    my $element_x = $res[0] * (($x[0] + $x[1]) / 2) + $res[0];
    my $element_y = $res[1] * (($y[0] + $y[1]) / 2) + $res[1];
    my $element = join ":", $element_x, $element_y;

    run_tests (
        basedata => $bd,
        element  => $element,
    );
}


done_testing();


sub run_tests {
    my %args = @_;
    my $bd      = $args{basedata};
    my $element = $args{element};

    my $res = $bd->get_param('CELL_SIZES');

    foreach my $i (1 .. 3) {

        foreach my $condition (sort keys %conditions) {
            my $expected = $conditions{$condition};

            my $cond = $condition;
            #print $cond . "\n";
            while ($condition =~ /##(\d+)/gc) {
                my $from = $1;
                my $to = $from * $res->[0];  #  assuming square groups
                $cond =~ s/##$from/$to/;
                #print "Matched $from to $to\n";
                #print $cond . "\n";
            }

            my $sp_params = Biodiverse::SpatialParams->new (
                conditions => $cond,
            );

            my $nbrs = eval {
                $bd->get_neighbours (
                    element        => $element,
                    spatial_params => $sp_params,
                );
            };
            croak $EVAL_ERROR if $EVAL_ERROR;

            is (keys %$nbrs, $expected, $cond);
        }

        my @index_res;
        foreach my $r (@$res) {
            push @index_res, $r * $i;
        }
        $bd->build_spatial_index (resolutions => [@index_res]);
    }

    return;
}