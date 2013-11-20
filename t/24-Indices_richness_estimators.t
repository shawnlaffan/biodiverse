#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use rlib;
use Test::Most;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
};
use Data::Section::Simple qw(get_data_section);

exit main( @ARGV );

sub main {
    my @args  = @_;

    my $bd = get_basedata();


    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
                if not my $func = (__PACKAGE__->can( 'test_' . $name ) || __PACKAGE__->can( $name ));
            $func->($bd);
        }
        done_testing;
        return 0;
    }

    test_indices($bd);
    test_indices_1col($bd);
    
    done_testing;
    return 0;
}


sub test_indices {
    my $bd = shift;
    
    my $focal_gp = 'Broad_Meadow_Brook';
    my @groups = grep {$_ ne $focal_gp} $bd->get_groups;

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_chao1
            calc_chao2
        /],
        calc_topic_to_test => 'Richness estimators',
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => ['Broad_Meadow_Brook'],
        element_list2      => \@groups,
    );

}

sub test_indices_1col {
    my $bd = shift;

    my $focal_gp = 'Broad_Meadow_Brook';
    my @groups = grep {$_ ne $focal_gp} $bd->get_groups;
    $bd->delete_groups (groups => \@groups);
    
    #  NEED CALCULATION
    my $results_overlay2 = {
        CHAO1          => 10.83,
        CHAO1_F1_COUNT => 4,
        CHAO1_F2_COUNT => 1,
        CHAO1_VARIANCE => 3.97 ** 2,
        CHAO2          => 10.83,
        CHAO2_Q1_COUNT => 4,
        CHAO2_Q2_COUNT => 1,
        CHAO2_VARIANCE => 3.97 ** 2,
    };
    my $results_overlay1 = {
        CHAO1          => undef,
        CHAO1_F1_COUNT => undef,
        CHAO1_F2_COUNT => undef,
        CHAO1_VARIANCE => undef,
        CHAO2          => undef,
        CHAO2_Q1_COUNT => undef,
        CHAO2_Q2_COUNT => undef,
        CHAO2_VARIANCE => undef,
    };
    
    my %expected_results_overlay = (
        1 => $results_overlay1,
        2 => $results_overlay2,
    );


    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_chao1
            calc_chao2
        /],
        calc_topic_to_test => 'Richness estimators',
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => ['Broad_Meadow_Brook'],
        element_list2      => [],
        expected_results_overlay => \%expected_results_overlay,
    );

}


sub get_basedata {

    my $data = get_data_section ('SAMPLE_DATA');
    
    my $bd = get_basedata_object_from_mx_format (
        name       => 'EstimateS',
        CELL_SIZES => [-1],
        data => $data,
        data_in_matrix_form => 1,
        label_start_col     => 1,
        input_sep_char      => "\t",
    );

    return $bd->transpose;
}


1;

__DATA__


@@ SAMPLE_DATA
sp	Broad_Meadow_Brook	Cold_Brook	Doyle_Center	Drumlin_Farm	Graves_Farm	Ipswich_River	Laughing_Brook	Lowell_Holly	Moose_Hill	Nashoba_Brook	Old_Town_Hill
aphful	0	0	0	0	0	0	0	1	0	0	1
aphrud	4	13	5	4	7	7	10	16	8	12	13
bradep	0	0	0	0	0	0	0	0	0	0	0
camchr	0	0	0	0	0	0	4	0	1	0	0
camher	0	1	0	0	0	0	0	0	0	0	0
camnea	0	1	0	0	0	0	0	1	0	0	0
camnov	0	0	0	0	0	0	0	0	0	0	0
campen	4	2	1	6	1	9	6	5	7	10	6
crelin	0	0	0	0	0	0	0	0	0	0	0
dolpla	0	0	0	0	0	0	0	0	0	0	0
forinc	0	0	0	0	0	0	0	0	0	0	0
forlas	0	0	0	0	0	0	0	0	0	0	0
forneo1	0	0	0	2	0	0	0	0	0	0	2
forneo2	0	0	0	0	0	0	0	0	0	0	0
fornep	0	0	0	0	0	0	0	0	0	0	0
forper	0	0	0	0	0	0	0	0	2	0	0
forsub1	0	0	0	0	0	2	0	0	1	0	0
forsub3	2	0	0	0	0	9	1	2	4	1	0
lasali	4	10	0	0	7	2	4	0	0	2	9
lascla	1	0	0	1	0	0	0	0	2	2	0
lasfla	0	0	0	0	0	0	0	0	0	0	0
laslat	0	0	0	0	0	0	2	0	0	0	1
lasnea	1	0	4	2	4	2	0	0	6	6	0
lasneo	0	0	0	0	0	0	0	0	0	0	0
lasspe	1	0	0	0	0	0	0	0	0	0	0
lasumb	0	0	2	0	0	0	3	0	1	0	0
myrame1	0	0	0	0	0	0	2	0	0	0	0
myrame2	0	0	0	0	0	0	0	0	0	0	0
myrdet	0	0	0	3	0	2	0	0	0	2	6
myrinc	0	0	0	0	0	0	1	0	0	0	0
myrnea	0	0	0	0	0	0	0	0	0	0	1
myrpun	1	0	0	2	0	2	5	0	1	2	0
myrrub	0	0	0	0	0	0	0	0	0	0	0
ponpen	0	0	0	0	0	0	0	0	0	0	0
preimp	0	0	0	0	0	0	0	0	0	0	0
proame	0	0	0	0	0	0	0	1	0	0	1
solmol	0	0	0	0	0	0	0	0	0	0	0
stebre	0	0	0	0	0	0	0	0	0	0	0
steimp	0	0	0	1	0	0	1	1	0	0	1
tapses	0	0	0	0	0	0	2	0	3	0	2
temamb	0	0	0	0	0	0	0	0	0	0	0
temcur	0	0	0	2	0	0	0	0	0	1	0
temlon	0	1	0	4	0	0	1	4	0	0	0



@@ RESULTS_2_NBR_LISTS
{
    CHAO1          => 26.99,
    CHAO1_F1_COUNT => 4,
    CHAO1_F2_COUNT => 5,
    CHAO1_VARIANCE => 2.4649,
    CHAO2          => 26.99,
    CHAO2_Q1_COUNT => 4,
    CHAO2_Q2_COUNT => 5,
    CHAO2_VARIANCE => 2.4649,
}

@@ RESULTS_1_NBR_LISTS
{
    CHAO1          => undef,
    CHAO1_F1_COUNT => undef,
    CHAO1_F2_COUNT => undef,
    CHAO1_VARIANCE => undef,
    CHAO2          => undef,
    CHAO2_Q1_COUNT => undef,
    CHAO2_Q2_COUNT => undef,
    CHAO2_VARIANCE => undef,
}
