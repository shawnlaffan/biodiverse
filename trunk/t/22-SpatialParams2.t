#!/usr/bin/perl -w

use strict;
use warnings;
use Carp;
use English qw{
    -no_match_vars
};

use rlib;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::SpatialParams;
use Biodiverse::TestHelpers qw{
    :basedata
    compare_arr_vals
};

use Data::Dumper;
$Data::Dumper::Purity   = 1;
$Data::Dumper::Terse    = 1;
$Data::Dumper::Sortkeys = 1;

sub test_case {
    my %args = @_;

    my $res         = $args{res};         # [x, y] size of each cell
    my $bottom_left = $args{bottom_left}; # [x, y] bottom left corner
    my $top_right   = $args{top_right};   # [x, y] top right corner
    my $cond        = $args{cond};        # spatial condition as string
    my $expected    = $args{expected};    # array of expected cells as strings

    my ($x_min, $x_max) = map { $_ / $res->[0] } ($bottom_left->[0], $top_right->[0]);
    my ($y_min, $y_max) = map { $_ / $res->[1] } ($bottom_left->[1], $top_right->[1]);

    my $bd = get_basedata_object (
        CELL_SIZES => $res,
        x_spacing  => $res->[0],
        y_spacing  => $res->[1],
        x_min      => $x_min,
        x_max      => $x_max,
        y_min      => $y_min,
        y_max      => $y_max,
        count      => 1,
    );

    my $spatial_params = Biodiverse::SpatialParams->new (
        conditions => 'sp_circle (radius => 100000)'
    );

    my $neighbours = eval {
        $bd->get_neighbours (
            element        => '50000:50000',
            spatial_params => $spatial_params,
        );
    };

    croak $EVAL_ERROR if $EVAL_ERROR;

    compare_arr_vals (
        arr_got => [keys %$neighbours],
        arr_exp => $expected,
    );
}

test_case (
    res         => [100000, 100000],
    bottom_left => [-200000, -200000],
    top_right   => [200000, 200000],
    cond        => 'sp_circle (radius => 100000)',
    expected    => [qw/-50000:50000 150000:50000 50000:-50000 50000:150000 50000:50000/],
);

done_testing;

1;
