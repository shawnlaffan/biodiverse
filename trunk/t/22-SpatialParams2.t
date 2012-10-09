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

    my ($x_min, $x_max) = map { $_ / $res->[0] }
                              ($bottom_left->[0], $top_right->[0]);
    my ($y_min, $y_max) = map { $_ / $res->[1] }
                              ($bottom_left->[1], $top_right->[1]);

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

=item transform_element

Takes in a colon or comma (or any punctuation) separated pair of x and y values
(element) and scales them by the array ref of
[x_translate, y_translate, x_scale, y_scale] passed in as transform.

Returns colon separated pair of x and y.

=cut

sub transform_element {
    my %args = @_;

    my $element = $args{element};

    if (not ($args{element} =~ m/^([-.0-9]+)([^-.0-9]+)([-.0-9]+)$/)) {
        croak "Invalid element '$element' given to transform_element.";
    }

    my ($x, $sep, $y)           = ($1, $2, $3);
    my ($x_t, $y_t, $x_s, $y_s) = @{$args{transform}};

    return join $sep, $x_s * ($x + $x_t),
                      $y_s * ($y + $y_t);
}

=item run_case_transformed

Takes in name of the test (name), the test data as a string (datastr) and a
transform as a 4 element array ref (transform).

The transform is in the order
[x_translate, y_translate, x_scale, y_scale]

It is applied to the base data coordinates, centre element, result elements
and numbers inside spatial conditions when prefixed by either XX or YY.

Translation is applied before scaling, and therefore should be specified in
terms of the original coordinates.

e.g.

sp_ellipse (major_radius => XX400000, minor_radius => YY200000)

=cut

my $re1 = join qr'\s+', ('([-0-9.,]+)',) x 3;

sub run_case_transformed {
    my %args = @_;

    my $k  = $args{name};
    my $v  = $args{datastr};
    my $tf = $args{transform};

    if (not ($v =~ s/^\s*$re1//m)) {
        croak "Malformed first line in test case $k";
    }
    my $res = [split ',', transform_element (
        element   => $1,
        transform => [0, 0, @$tf[2,3]], # Don't translate the resolution
    )];
    my ($bottom_left, $top_right) = map {[split ',', transform_element (
        element   => $_,
        transform => $tf
    )]} ($2, $3);

    my $bd = artifical_base_data (
        res           => $res,
        bottom_left   => $bottom_left,
        top_right     => $top_right,
    );

    if (not ($v =~ s/^\s*([-0-9.,:]+)//)) {
        croak "Malformed centre element in test case $k";
    }

    my $element = transform_element (
        element   => $1,
        transform => $tf,
    );

    my $i = 0;
    while (++$i) {
        if (not ($v =~ s/^\s*(.*?)^\s*,\s*$//ms)) {
            last;
        }

        my $cond = $1;

        while ($cond =~ /XX([-.0-9]+)/g) {
            my $from = $1;
            my $to   = $tf->[2] * $from;
            $cond =~ s/XX$from/$to/;
        }
        while ($cond =~ /YY([-.0-9]+)/g) {
            my $from = $1;
            my $to   = $tf->[3] * $from;
            $cond =~ s/YY$from/$to/;
        }

        print "Condition is $cond\n";

        if (not ($v =~ s/^\s*(.*?)^\s*;\s*$//ms)) {
            croak "Malformed expected in test case $k.$i";
        }

        my $expected = [map { transform_element (
            element   => $_,
            transform => $tf,
        ) } split /\s+/, $1];

        subtest "Passed test case $k.$i" => sub { test_case (
            bd            => $bd,
            element       => $element,
            cond          => $cond,
            expected      => $expected,
            print_results => 1,
        ) };
    }

    ok ($i != 1, "Test case $k actually contained conditions");
}

my $data = get_data_section;

my @transforms = (
    [0,0 , 1,1], # [x_translate,y_translate , x_scale,y_scale]
    [0,0 , .0000001,.0000001],
    [-200000,-200000 , 1,1],
);

for my $k (sort keys %$data) {
    for my $transform (@transforms) {
        run_case_transformed (
            name      => $k,
            datastr   => $data->{$k},
            transform => $transform,
        );
    }
}

done_testing;

1;

# res_x,res_y bottom_left_x,bottom_left_y top_right_x,top_right_y centre_x:centre_y
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
100000,100000 -500000,-500000 500000,500000 50000:50000

sp_circle (radius => XX0)
,
50000:50000
;

sp_circle (radius => XX100000)
,
-50000:50000
150000:50000
50000:-50000
50000:150000
50000:50000
;

sp_circle (radius => XX200000)
,
-150000:50000
-50000:-50000
-50000:150000
-50000:50000
150000:-50000
150000:150000
150000:50000
250000:50000
50000:-150000
50000:-50000
50000:150000
50000:250000
50000:50000
;

sp_circle (radius => XX300000)
,
-150000:-150000
-150000:-50000
-150000:150000
-150000:250000
-150000:50000
-250000:50000
-50000:-150000
-50000:-50000
-50000:150000
-50000:250000
-50000:50000
150000:-150000
150000:-50000
150000:150000
150000:250000
150000:50000
250000:-150000
250000:-50000
250000:150000
250000:250000
250000:50000
350000:50000
50000:-150000
50000:-250000
50000:-50000
50000:150000
50000:250000
50000:350000
50000:50000
;

sp_circle (radius => XX400000)
,
-150000:-150000
-150000:-250000
-150000:-50000
-150000:150000
-150000:250000
-150000:350000
-150000:50000
-250000:-150000
-250000:-50000
-250000:150000
-250000:250000
-250000:50000
-350000:50000
-50000:-150000
-50000:-250000
-50000:-50000
-50000:150000
-50000:250000
-50000:350000
-50000:50000
150000:-150000
150000:-250000
150000:-50000
150000:150000
150000:250000
150000:350000
150000:50000
250000:-150000
250000:-250000
250000:-50000
250000:150000
250000:250000
250000:350000
250000:50000
350000:-150000
350000:-50000
350000:150000
350000:250000
350000:50000
450000:50000
50000:-150000
50000:-250000
50000:-350000
50000:-50000
50000:150000
50000:250000
50000:350000
50000:450000
50000:50000
;

sp_circle (radius => XX500000)
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

sp_select_all ()
,
-150000:-150000
-150000:-250000
-150000:-350000
-150000:-450000
-150000:-50000
-150000:150000
-150000:250000
-150000:350000
-150000:450000
-150000:50000
-150000:550000
-250000:-150000
-250000:-250000
-250000:-350000
-250000:-450000
-250000:-50000
-250000:150000
-250000:250000
-250000:350000
-250000:450000
-250000:50000
-250000:550000
-350000:-150000
-350000:-250000
-350000:-350000
-350000:-450000
-350000:-50000
-350000:150000
-350000:250000
-350000:350000
-350000:450000
-350000:50000
-350000:550000
-450000:-150000
-450000:-250000
-450000:-350000
-450000:-450000
-450000:-50000
-450000:150000
-450000:250000
-450000:350000
-450000:450000
-450000:50000
-450000:550000
-50000:-150000
-50000:-250000
-50000:-350000
-50000:-450000
-50000:-50000
-50000:150000
-50000:250000
-50000:350000
-50000:450000
-50000:50000
-50000:550000
150000:-150000
150000:-250000
150000:-350000
150000:-450000
150000:-50000
150000:150000
150000:250000
150000:350000
150000:450000
150000:50000
150000:550000
250000:-150000
250000:-250000
250000:-350000
250000:-450000
250000:-50000
250000:150000
250000:250000
250000:350000
250000:450000
250000:50000
250000:550000
350000:-150000
350000:-250000
350000:-350000
350000:-450000
350000:-50000
350000:150000
350000:250000
350000:350000
350000:450000
350000:50000
350000:550000
450000:-150000
450000:-250000
450000:-350000
450000:-450000
450000:-50000
450000:150000
450000:250000
450000:350000
450000:450000
450000:50000
450000:550000
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
550000:-150000
550000:-250000
550000:-350000
550000:-450000
550000:-50000
550000:150000
550000:250000
550000:350000
550000:450000
550000:50000
550000:550000
;

sp_self_only ()
,
50000:50000
;

sp_ellipse (major_radius => XX400000, minor_radius => YY200000)
,
-150000:50000
-50000:-150000
-50000:-250000
-50000:-50000
-50000:150000
-50000:250000
-50000:350000
-50000:50000
150000:-150000
150000:-250000
150000:-50000
150000:150000
150000:250000
150000:350000
150000:50000
250000:50000
50000:-150000
50000:-250000
50000:-350000
50000:-50000
50000:150000
50000:250000
50000:350000
50000:450000
50000:50000
;

sp_ellipse (major_radius => XX200000, minor_radius => YY200000)
,
-150000:50000
-50000:-50000
-50000:150000
-50000:50000
150000:-50000
150000:150000
150000:50000
250000:50000
50000:-150000
50000:-50000
50000:150000
50000:250000
50000:50000
;

sp_ellipse (
    major_radius => XX400000,
    minor_radius => YY400000,
    rotate_angle => 1.308996939,
)
# TODO: This won't work with x and y scaled by different amounts.
# Probably needs some trigonometry.
,
-150000:-150000
-150000:-250000
-150000:-50000
-150000:150000
-150000:250000
-150000:350000
-150000:50000
-250000:-150000
-250000:-50000
-250000:150000
-250000:250000
-250000:50000
-350000:50000
-50000:-150000
-50000:-250000
-50000:-50000
-50000:150000
-50000:250000
-50000:350000
-50000:50000
150000:-150000
150000:-250000
150000:-50000
150000:150000
150000:250000
150000:350000
150000:50000
250000:-150000
250000:-250000
250000:-50000
250000:150000
250000:250000
250000:350000
250000:50000
350000:-150000
350000:-50000
350000:150000
350000:250000
350000:50000
450000:50000
50000:-150000
50000:-250000
50000:-350000
50000:-50000
50000:150000
50000:250000
50000:350000
50000:450000
50000:50000
;


