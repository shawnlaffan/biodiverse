use strict;
use warnings;
use Carp;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;

use rlib;
use Test2::V0;

use Scalar::Util qw /looks_like_number/;
use Data::Dumper qw /Dumper/;


local $| = 1;

use Biodiverse::TestHelpers qw {:spatial_conditions};
use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;

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
    square => {
        'sp_square (size => ##1)'    => 1,
        'sp_square_cell (size => 1)' => 1,
        'sp_square (size => ##2)'    => 9,
        'sp_square_cell (size => 2)' => 9,
        'sp_square (size => ##3)'    => 9,
        'sp_square_cell (size => 3)' => 9,
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
        'sp_ellipse (major_radius => ##10, minor_radius => ##5, rotate_angle => Math::Trig::pip4); #radflag' => 153,
        #  degrees
        'sp_ellipse (major_radius => ##10, minor_radius => ##5, rotate_angle_deg => 45); #degflag' => 153,
    },
    block => {
        'sp_block (size => ##3)' => 9,
        'sp_block (size => [##3, ##3])' => 9,
    },
);


exit main( @ARGV );

sub main {
    my @args  = @_;

    test_overload();

    test_result_types();

    test_sp_square_with_array_ref ();

    my @res_pairs = get_sp_cond_res_pairs_to_use (@args);
    my %conditions_to_run = get_sp_conditions_to_run (\%conditions, @args);

    my %results;
    foreach my $key (sort keys %conditions_to_run) {
        #diag $key;
        $results{$key} = test_sp_cond_res_pairs ($conditions{$key}, \@res_pairs);
    }

    test_ellipse_angles_match(\%results);

    #  zero the resolution for a bit of paranoia
    foreach my $key (sort keys %conditions_to_run) {
        next if not $key =~ 'circle';
        $results{$key} = test_sp_cond_res_pairs ($conditions{$key}, \@res_pairs, 1);
    }

    done_testing;
    return 0;
}

sub test_overload {
    my $cond = 'sp_self_only()';
    my $obj = Biodiverse::SpatialConditions->new (conditions => $cond);
    is "$obj", $cond, 'String overloading returns expected string';
}

sub test_ellipse_angles_match {
    my $results = shift;
    my $ellipse_results = $results->{ellipse};
    foreach my $res_combo (sort keys %$ellipse_results) {
        my $sub_hash = $ellipse_results->{$res_combo};
        my @targets = grep {/flag$/} sort keys %$sub_hash;

        is (
            $sub_hash->{$targets[0]},
            $sub_hash->{$targets[1]},
            "ellipse nbr set matches for rotate_angle_deg and rotate_angle, $res_combo",
        );
    }
}

#  refs get converted to numbers so need to croak
#  when sp_square gets one
sub test_sp_square_with_array_ref {
    my $bd = Biodiverse::BaseData->new (
        CELL_SIZES => [1,1],
        NAME => 'test_sp_square_with_array_ref',
    );
    my $sp_cond = Biodiverse::SpatialConditions->new(
        basedata_ref => $bd,
        conditions   => 'sp_square (size => [100,100])',
    );
    
    my $res = eval {
        $sp_cond->evaluate (coord_array1 => [1,1], coord_array2 => [2,2]);
    };
    my $e = $@;
    ok $e, 'sp_square dies when passed a reference as the size arg';
    
}

sub test_result_types {
    #  Test a range of parsed types.
    #  We probably do not need to test all of them as many are only
    #  set by methods rather than extracted through parsing.
    my $bd = get_basedata_object(CELL_SIZES => [1,1]);

    my %types = (
        circle           => [
            'sp_circle (radius => 2)',
            '  sp_circle (radius => 2)   #  comment',
            'sp_circle_cell (radius => 2)',
            # '$D < 100000',
            '$D <= 100000',
            # '$C < 1',
            '$C <= 1',
            #  annulus subtypes
            '$D>=0 and $D<=5', '  $D>=0 and $D<=5  # comment',
            '$D>=0 && $D<=5', '  $D>=0 && $D<=5  # comment',
            'sp_annulus (inner_radius => 2, outer_radius => 4)'
        ],
        always_false     => [
            '', '0', '  0 ', '0.00', '  0 # comment', ' 0.0 ',
        ],
        always_true      => [
            '1', '  10 ', '0.001', '  01 # comment', ' 0.01 ',
            '$D >= 0', '$D >= 0 # comment',
            '  $D >= 0 ', '  $D >= 0 # comment',
            'sp_select_all()'
        ],
        self_only        => [
            'sp_self_only()', ' sp_self_only() # comment',
        ],
        always_same      => [],
        square           => [],
        non_overlapping  => [],
        ellipse          => [],
        text_match_exact => [],
        side             => [],
        subset           => [
            #  'sp_select_block...
        ],
        complex          => [
            '$C<5 && $D>3',
        ],
        'circle square' => [
            'sp_circle (radius => 5) || sp_square (size => 3)'
        ],
    );

    foreach my $type (sort keys %types) {
        my $conditions = $types{$type};
        foreach my $cond (@$conditions) {
            my $sp_cond = Biodiverse::SpatialConditions->new(conditions => $cond, basedata_ref => $bd);
            my $res_type = $sp_cond->get_result_type;
            is $res_type, $type, "results type: $type, condition: $cond";
        }
        if (!@$conditions) {
            my $todo = todo "need type tests for $type";
            ok(0, $type);
        }
    }


}
