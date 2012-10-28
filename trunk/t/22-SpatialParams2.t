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

sub test_case_real {
    my %args = @_;

    my $bd            = $args{bd};       # basedata object
    my $cond          = $args{cond};     # spatial condition as string

    my $spatial_params = Biodiverse::SpatialParams->new (
        conditions => $cond,
    );

    my $gp = $bd->get_groups_ref;
    my @elements = $gp->get_element_list;
    my %neighbour_map;

    for my $element (@elements) {
        my $nbrs = eval {
            $bd->get_neighbours (
                element        => $element,
                spatial_params => $spatial_params,
            );
        };
        my $e = $EVAL_ERROR;

        ok !$EVAL_ERROR, "Got neighbours for $element without eval error";

        $neighbour_map{$element} = [sort keys %$nbrs];
    }

    my %checked;

    while (my ($element, $neighbours) = each %neighbour_map) {
        if (exists $checked{$element}) {
            next;
        }

        # Check that each array of neighbours is the same as the first array.
        is_deeply [($neighbours, ) x @$neighbours],
                  [@neighbour_map{@$neighbours}],
                  "$element has the correct neighbours";

        undef @checked{@$neighbours};
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
