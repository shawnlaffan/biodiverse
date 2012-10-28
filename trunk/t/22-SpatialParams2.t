#!/usr/bin/perl -w

=head1
This tests the property that sp_block for each element in a block returns the
same elements and that the blocks do not overlap.
=cut

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
};

use Data::Section::Simple qw{
    get_data_section
};

sub artificial_base_data {
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

=item sorted_arrays_eq
Checks that all given sorted arrays contain the same elements.

Takes in a list of array references.
=cut

sub sorted_arrays_eq {
    if (!@_) {
        return undef;
    }

    my $len = @{$_[0]};

    for my $a (@_) {
        if (@$a != $len) {
            return undef;
        }
    }

    for (my $i = 0; $i != $len; ++$i) {
        my $val = $_[0]->[$i];
        for my $a (@_) {
            if ($a->[$i] ne $val) {
                return undef;
            }
        }
    }

    return 1;
}

sub test_case_real {
    my %args = @_;

    my $bd            = $args{bd};       # basedata object
    my $cond          = $args{cond};     # spatial condition as string

    my $spatial_params = Biodiverse::SpatialParams->new (
        conditions => $cond,
    );

    my @elements = keys $bd->{GROUPS}->{ELEMENTS};
    my %neighbour_map;

    for my $element (@elements) {
        $neighbour_map{$element} = [sort keys eval {
            $bd->get_neighbours (
                element        => $element,
                spatial_params => $spatial_params,
            );
        }];

        ok !$EVAL_ERROR, "Got neighbours for $element without eval error";
    }

    while (my ($element, $neighbours) = each %neighbour_map) {
        ok (sorted_arrays_eq (@neighbour_map{@$neighbours}),
            "$element has the correct neighbours");

        delete @neighbour_map{@$neighbours};
    }
}

sub test_case {
    my %args = @_;
    subtest "$args{cond} passed" => sub {
        test_case_real %args;
    }
}

my $bd = artificial_base_data (
    res         => [100000, 100000],
    bottom_left => [-1000000, -1000000],
    top_right   => [600000, 600000],
);

test_case (bd => $bd, cond => 'sp_block (size => 1)');
test_case (bd => $bd, cond => 'sp_block (size => 100000)');
test_case (bd => $bd, cond => 'sp_block (size => 200000)');
test_case (bd => $bd, cond => 'sp_block (size => 300000)');
test_case (bd => $bd, cond => 'sp_block (size => 400000)');
test_case (bd => $bd, cond => 'sp_block (size => 500000)');

done_testing;

1;
