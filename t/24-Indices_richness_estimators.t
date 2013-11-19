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

    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
                if not my $func = (__PACKAGE__->can( 'test_' . $name ) || __PACKAGE__->can( $name ));
            $func->();
        }
        done_testing;
        return 0;
    }


    my $bd = get_basedata();

    test_indices($bd);
    
    done_testing;
    return 0;
}


sub test_indices {
    my $bd = shift;

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_chao1
        /],
        calc_topic_to_test => 'Richness estimators',
        sort_array_lists   => 1,
        basedata_ref       => $bd,
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
sp	Broad Meadow Brook	Cold Brook	Doyle Center	Drumlin Farm	Graves Farm	Ipswich River	Laughing Brook	Lowell Holly	Moose Hill	Nashoba Brook	Old Town Hill
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
  'ABC2_LABELS_ALL' => {
                         'Genus:sp1'  => 2,
                         'Genus:sp10' => 1,
                         'Genus:sp11' => 2,
                         'Genus:sp12' => 2,
                         'Genus:sp15' => 2,
                         'Genus:sp20' => 4,
                         'Genus:sp23' => 1,
                         'Genus:sp24' => 1,
                         'Genus:sp25' => 1,
                         'Genus:sp26' => 2,
                         'Genus:sp27' => 1,
                         'Genus:sp29' => 1,
                         'Genus:sp30' => 1,
                         'Genus:sp5'  => 1
                       },
  'ABC2_LABELS_SET1' => {
                          'Genus:sp20' => 1,
                          'Genus:sp26' => 1
                        },
  'ABC2_LABELS_SET2' => {
                          'Genus:sp1'  => 2,
                          'Genus:sp10' => 1,
                          'Genus:sp11' => 2,
                          'Genus:sp12' => 2,
                          'Genus:sp15' => 2,
                          'Genus:sp20' => 3,
                          'Genus:sp23' => 1,
                          'Genus:sp24' => 1,
                          'Genus:sp25' => 1,
                          'Genus:sp26' => 1,
                          'Genus:sp27' => 1,
                          'Genus:sp29' => 1,
                          'Genus:sp30' => 1,
                          'Genus:sp5'  => 1
                        },
  'ABC2_MEAN_ALL'   => '1.57142857142857',
  'ABC2_MEAN_SET1'  => '1',
  'ABC2_MEAN_SET2'  => '1.42857142857143',
  'ABC2_SD_ALL'     => '0.85163062725264',
  'ABC2_SD_SET1'    => '0',
  'ABC2_SD_SET2'    => '0.646206172658864',
  'ABC3_LABELS_ALL' => {
                         'Genus:sp1'  => 8,
                         'Genus:sp10' => 16,
                         'Genus:sp11' => 9,
                         'Genus:sp12' => 8,
                         'Genus:sp15' => 11,
                         'Genus:sp20' => 12,
                         'Genus:sp23' => 2,
                         'Genus:sp24' => 2,
                         'Genus:sp25' => 1,
                         'Genus:sp26' => 6,
                         'Genus:sp27' => 1,
                         'Genus:sp29' => 5,
                         'Genus:sp30' => 1,
                         'Genus:sp5'  => 1
                       },
  'ABC3_LABELS_SET1' => {
                          'Genus:sp20' => 4,
                          'Genus:sp26' => 2
                        },
  'ABC3_LABELS_SET2' => {
                          'Genus:sp1'  => 8,
                          'Genus:sp10' => 16,
                          'Genus:sp11' => 9,
                          'Genus:sp12' => 8,
                          'Genus:sp15' => 11,
                          'Genus:sp20' => 8,
                          'Genus:sp23' => 2,
                          'Genus:sp24' => 2,
                          'Genus:sp25' => 1,
                          'Genus:sp26' => 4,
                          'Genus:sp27' => 1,
                          'Genus:sp29' => 5,
                          'Genus:sp30' => 1,
                          'Genus:sp5'  => 1
                        },
  'ABC3_MEAN_ALL'  => '5.92857142857143',
  'ABC3_MEAN_SET1' => '3',
  'ABC3_MEAN_SET2' => '5.5',
  'ABC3_SD_ALL'    => '4.89056054226736',
  'ABC3_SD_SET1'   => '1.4142135623731',
  'ABC3_SD_SET2'   => '4.63680924774785',
  'ABC3_SUM_ALL'   => 83,
  'ABC3_SUM_SET1'  => 6,
  'ABC3_SUM_SET2'  => 77,
  'ABC_A'          => 2,
  'ABC_ABC'        => 14,
  'ABC_B'          => 0,
  'ABC_C'          => 12,
  'ABC_D'          => 17,
  #'COMPL'          => 14,
  'EL_COUNT_ALL'   => 5,
  'EL_COUNT_SET1'  => 1,
  'EL_COUNT_SET2'  => 4,
  'EL_LIST_ALL'    => [
                     '3250000:850000',
                     '3350000:850000',
                     '3350000:750000',
                     '3350000:950000',
                     '3450000:850000'
                   ],
  'EL_LIST_SET1' => {
                      '3350000:850000' => 1
                    },
  'EL_LIST_SET2' => {
                      '3250000:850000' => 1,
                      '3350000:750000' => 1,
                      '3350000:950000' => 1,
                      '3450000:850000' => 1
                    },
  'REDUNDANCY_ALL'  => '0.831325301204819',
  'REDUNDANCY_SET1' => '0.666666666666667',
  'REDUNDANCY_SET2' => '0.818181818181818',
  'RICHNESS_ALL'    => 14,
  'RICHNESS_SET1'   => 2,
  'RICHNESS_SET2'   => 14
}

@@ RESULTS_1_NBR_LISTS
{
  'ABC2_LABELS_SET1' => {
                          'Genus:sp20' => 1,
                          'Genus:sp26' => 1
                        },
  'ABC2_MEAN_ALL'    => '1',
  'ABC2_MEAN_SET1'   => '1',
  'ABC2_SD_SET1'     => '0',
  'ABC3_LABELS_SET1' => {
                          'Genus:sp20' => 4,
                          'Genus:sp26' => 2
                        },
  'ABC3_MEAN_SET1' => '3',
  'ABC3_SD_SET1'   => '1.4142135623731',
  'ABC3_SUM_SET1'  => 6,
  'ABC_D'          => 29,
  'EL_COUNT_SET1'  => 1,
  'EL_LIST_SET1'   => {
                      '3350000:850000' => 1
                    },
  'REDUNDANCY_ALL'  => '0.666666666666667',
  'REDUNDANCY_SET1' => '0.666666666666667',
  'RICHNESS_ALL'    => 2,
  'RICHNESS_SET1'   => 2
}
