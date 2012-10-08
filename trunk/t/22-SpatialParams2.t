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

use Data::Section::Simple qw{
    get_data_section
};

sub artifical_base_data {
    my %args = @_;

    my $res         = $args{res};         # [x, y] size of each cell
    my $bottom_left = $args{bottom_left}; # [x, y] bottom left corner
    my $top_right   = $args{top_right};   # [x, y] top right corner

    my $print_results = $args{print_results} || 0;

    my ($x_min, $x_max) = map { $_ / $res->[0] } ($bottom_left->[0], $top_right->[0]);
    my ($y_min, $y_max) = map { $_ / $res->[1] } ($bottom_left->[1], $top_right->[1]);

    return get_basedata_object (
        CELL_SIZES => $res,
        x_spacing  => $res->[0],
        y_spacing  => $res->[1],
        x_min      => $x_min,
        x_max      => $x_max,
        y_min      => $y_min,
        y_max      => $y_max,
        count      => 1,
    );
}

sub test_case {
    my %args = @_;

    my $bd            = $args{bd};       # basedata object
    my $cond          = $args{cond};     # spatial condition as string
    my $element       = $args{element};  # centre element
    my $expected      = $args{expected}; # array of expected cells as strings
    my $print_results = $args{print_results} || 0;

    my $spatial_params = Biodiverse::SpatialParams->new (
        conditions => $cond,
    );

    my $neighbours = eval {
        $bd->get_neighbours (
            element        => $element,
            spatial_params => $spatial_params,
        );
    };

    if ($print_results) {
        use Data::Dumper;
        $Data::Dumper::Purity   = 1;
        $Data::Dumper::Terse    = 1;
        $Data::Dumper::Sortkeys = 1;
        print join "\n", sort keys %$neighbours;
        print "\n";
    }

    croak $EVAL_ERROR if $EVAL_ERROR;

    compare_arr_vals (
        arr_got => [keys %$neighbours],
        arr_exp => $expected,
    );
}

my $data = get_data_section;

my $re1 = join qr'\s+', ('([-0-9.,]+)',) x 3;

for my $k (sort keys %$data) {
    my $v = $data->{$k};

    if (not ($v =~ s/^\s*$re1//m)) {
        croak "Malformed first line in test case $k";
    }
    my ($res, $bottom_left, $top_right) = map {[split ',', $_]} ($1, $2, $3);

    my $bd = artifical_base_data (
        res           => $res,
        bottom_left   => $bottom_left,
        top_right     => $top_right,
    );

    if (not ($v =~ s/^\s*([-0-9.,:]+)//)) {
        croak "Malformed centre element in test case $k";
    }

    my $element = $1;

    my $i = 0;
    while (++$i) {
        if (not ($v =~ s/^\s*(.*?)^\s*,\s*$//ms)) {
            last;
        }

        my $cond = $1;

        if (not ($v =~ s/^\s*(.*?)^\s*;\s*$//ms)) {
            croak "Malformed expected in test case $k.$i";
        }

        my $expected = [split /\s+/, $1];

        subtest "Passed test case $k.$i" => sub { test_case (
            bd            => $bd,
            element       => $element,
            cond          => $cond,
            expected      => $expected,
            #print_results => 1,
        ) };
    }

    ok ($i != 1, "Test case $k actually contained conditions");
}

done_testing;

1;

# res_x,res_y bottom_left_x,bottom_left_y top_right_x,top_right_y
# centre_x:centre_y
# cond
# ,
# expected
# ;
# cond
# ,
# expected
# ;
# ...
__DATA__

@@ CASE1
100000,100000 -500000,-500000 500000,500000
50000:50000

sp_circle (
    radius => 100000
)
,
-50000:50000
150000:50000
50000:-50000
50000:150000
50000:50000
;

sp_circle (
    radius => 0
)
,
50000:50000
;

sp_circle (
    radius => 500000
)
,
-150000:-150000
-150000:-250000
-150000:-350000
-150000:-50000
-150000:150000
-150000:250000
-150000:350000
-150000:450000
-150000:50000
-250000:-150000
-250000:-250000
-250000:-350000
-250000:-50000
-250000:150000
-250000:250000
-250000:350000
-250000:450000
-250000:50000
-350000:-150000
-350000:-250000
-350000:-50000
-350000:150000
-350000:250000
-350000:350000
-350000:50000
-450000:50000
-50000:-150000
-50000:-250000
-50000:-350000
-50000:-50000
-50000:150000
-50000:250000
-50000:350000
-50000:450000
-50000:50000
150000:-150000
150000:-250000
150000:-350000
150000:-50000
150000:150000
150000:250000
150000:350000
150000:450000
150000:50000
250000:-150000
250000:-250000
250000:-350000
250000:-50000
250000:150000
250000:250000
250000:350000
250000:450000
250000:50000
350000:-150000
350000:-250000
350000:-350000
350000:-50000
350000:150000
350000:250000
350000:350000
350000:450000
350000:50000
450000:-150000
450000:-250000
450000:-50000
450000:150000
450000:250000
450000:350000
450000:50000
50000:-150000
50000:-250000
50000:-350000
50000:-450000
50000:-50000
50000:150000
50000:250000
50000:350000
50000:450000
50000:50000
50000:550000
550000:50000
;
