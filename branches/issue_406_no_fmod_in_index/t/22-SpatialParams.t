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
use Biodiverse::SpatialParams;
use Biodiverse::TestHelpers qw {:basedata};

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
    block_select => {
        'sp_select_block (size => ##5, count => 2)' => 2,
        'sp_select_block (size => ##3, count => 3)' => 3,
    },
    sides => {
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
        
        'sp_in_line_with()' => 30,
        'sp_in_line_with(vector_angle => 0)' => 30,
        'sp_in_line_with(vector_angle => Math::Trig::pip2)' => 30,
        'sp_in_line_with(vector_angle => Math::Trig::pip4)' => 30,
        'sp_in_line_with(vector_angle_deg => 0)'  => 30,
        'sp_in_line_with(vector_angle_deg => 45)' => 30,
        'sp_in_line_with(vector_angle_deg => 90)' => 30,
    },
);


my @res_pairs = (
    ##  now try for a mix of +ve and -ve coords
    ##  but with cell sizes < 1
    {
        res =>   [10, 10],
        min_x => 1,
    },
    ##  now try for negative coords
    {
        res =>   [10, 10],
        min_x => -30,
    },
    ##  now try for a mix of +ve and -ve coords
    {
        res =>   [10, 10],
        min_x => -14,
    },
    ##  now try for +ve coords
    ##  but with cell sizes < 1
    {
        res =>   [.1, .1],
        min_x => 1,
    },
    #  cellsize < 1 and +ve and -ve coords
    {
        res =>   [.1, .1],
        min_x => -14,
    },
);

exit main( @ARGV );

sub main {
    my @args  = @_;

    my %conditions_to_run = %conditions;

    if (@args) {
        my @res_sub;
        my %cond_sub;
        for my $res (@args) {
            if (looks_like_number $res && $res < $#res_pairs) {
                push @res_sub, $res;
            }
            elsif (exists $conditions{$res} && exists $conditions{$res}) {
                $cond_sub{$res}++;
            }
            else {
                die "Invalid argument $res";
            }
        }
        if (scalar @res_sub) {
            diag 'Using res pair subset: ' . join ", ", @res_sub;
            @res_pairs = @res_pairs[@res_sub];

            local $Data::Dumper::Purity   = 1;
            local $Data::Dumper::Terse    = 1;
            local $Data::Dumper::Sortkeys = 1;
            diag Dumper \@res_pairs;
        }
        if (scalar keys %cond_sub) {
            %conditions_to_run = ();
            @conditions_to_run{keys %cond_sub} = @conditions{keys %cond_sub};
            diag 'Using conditions subset: ' . join ", ", sort keys %cond_sub;
        }
    }

    #my $condition_count = sum map {scalar keys $conditions{$_}} keys %conditions;
    #plan tests =>  3 * @res_pairs * $condition_count;

    foreach my $key (sort keys %conditions_to_run) {
        #diag $key;
        test_res_pairs($conditions{$key}, @res_pairs);
    }

    done_testing;
    return 0;
}



sub test_res_pairs {
    my $conditions = shift;
    my @res_pairs  = @_;

    SKIP:
    {
        while (my $cond = shift @res_pairs) {
            my $res = $cond->{res};
            my @x   = ($cond->{min_x}, $cond->{min_x} + 29);
            my @y   = @x;
            my $bd = get_basedata_object(
                x_spacing  => $res->[0],
                y_spacing  => $res->[1],
                CELL_SIZES => $res,
                x_max      => $x[1],
                y_max      => $y[1],
                x_min      => $x[0],
                y_min      => $y[0],
            );
#$bd->save_to (filename => 'ghgh.bds');
            #  should sub this - get centre_group or something
            my $element_x = $res->[0] * (($x[0] + $x[1]) / 2) + $res->[0];
            my $element_y = $res->[1] * (($y[0] + $y[1]) / 2) + $res->[1];
            my $element = join ":", $element_x, $element_y;
    
            run_tests (
                basedata   => $bd,
                element    => $element,
                conditions => $conditions,
            );
        }
    }
}


sub run_tests {
    my %args = @_;
    my $bd      = $args{basedata};
    my $element = $args{element};
    my $conditions = $args{conditions};

    my $res = $bd->get_param('CELL_SIZES');
    my ($index, $index_offsets);
    my $index_text = q{};

#$SIG{__WARN__}=sub{die};

    foreach my $i (1 .. 3) {

        foreach my $condition (sort keys %$conditions) {
            my $expected = $conditions->{$condition};

            my $cond = $condition;

            while ($condition =~ /##(\d+)/gc) {
                my $from = $1;
                my $to = $from * $res->[0];  #  assuming square groups
                $cond =~ s/##$from/$to/;
                #print "Matched $from to $to\n";
                #print $cond . "\n";
            }

            #diag $cond;

            my $sp_params = Biodiverse::SpatialParams->new (
                conditions => $cond,
            );
            
            if ($index) {
                $index_offsets = $index->predict_offsets (
                    spatial_params    => $sp_params,
                    cellsizes         => $bd->get_param ('CELL_SIZES'),
                    #progress_text_pfx => $progress_text_pfx,
                );
            }

            my $nbrs = eval {
                $bd->get_neighbours (
                    element        => $element,
                    spatial_params => $sp_params,
                    index          => $index,
                    index_offsets  => $index_offsets,
                );
            };
            croak $EVAL_ERROR if $EVAL_ERROR;

            is (keys %$nbrs, $expected, $cond . $index_text);
        }

        my @index_res;
        foreach my $r (@$res) {
            push @index_res, $r * $i;
        }
        $index = $bd->build_spatial_index (resolutions => [@index_res]);
        $index_text = ' (Index res is ' . join (q{ }, @index_res) . ')';
    }

    return;
}