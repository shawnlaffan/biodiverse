#!/usr/bin/perl -w
use strict;
use warnings;

local $| = 1;

use Carp;
use rlib;
use Test::More;
use Data::Dumper;
use Data::Section::Simple qw{
    get_data_section
};

use Biodiverse::BaseData;
use Biodiverse::Indices;
use Biodiverse::TestHelpers qw{
    :basedata
    :runners
    :tree
};

my $phylo_calcs_to_test = [qw/
    calc_phylo_mpd_mntd3
    calc_phylo_mpd_mntd2
    calc_phylo_mpd_mntd1
    calc_phylo_aed
    calc_phylo_aed_t
    calc_phylo_aed_proportional
    calc_labels_not_on_tree
    calc_labels_on_tree
    calc_pd_endemism
    calc_phylo_jaccard
    calc_phylo_s2
    calc_phylo_sorenson
    calc_phylo_abc
    calc_pd
    calc_pd_node_list
    calc_pd_terminal_node_list
    calc_pe
    calc_pe_lists
    calc_taxonomic_distinctness
    calc_taxonomic_distinctness_binary
/];

my $indices = Biodiverse::Indices->new(BASEDATA_REF => {});

is @$phylo_calcs_to_test, @{get_all_calculations()->{'Phylogenetic Indices'}}, 'Right number of phylogenetic calculations tested';

run_indices_phylogenetic (
    phylo_calcs_to_test  => $phylo_calcs_to_test,
    get_expected_results => \&get_expected_results
);

done_testing;

sub get_expected_results {
    my %args = @_;

    my $nbr_list_count = $args{nbr_list_count};
    
    croak "Invalid nbr list count\n"
      if $nbr_list_count != 1 && $nbr_list_count != 2;

    return \%{eval get_data_section("RESULTS_${nbr_list_count}_NBR_LISTS")};
}

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
'PD'              => '9.55665348225732',
'PD_ENDEMISM'     => undef,
'PD_ENDEMISM_WTS' => {},
'PD_INCLUDED_NODE_LIST' => {
                             '30___'      => '0.077662337662338',
                             '31___'      => '0.098714969241285',
                             '32___'      => '0.106700478344225',
                             '33___'      => '0.05703610742759',
                             '34___'      => '0.341398923434153',
                             '35___'      => '0.03299436960061',
                             '36___'      => '0.051317777404734',
                             '37___'      => '0.11249075347436',
                             '38___'      => '0.0272381982058111',
                             '39___'      => '0.172696292660468',
                             '41___'      => '0.075867662593738',
                             '42___'      => '0.057495084175743',
                             '44___'      => '0.265221710543839',
                             '45___'      => '0.026396763298318',
                             '49___'      => '0.020427284632173',
                             '50___'      => '0.00121523842637206',
                             '51___'      => '0.729927663567369',
                             '52___'      => '0.00291112550535999',
                             '58___'      => '0.00993044169650192',
                             '59___'      => 0,
                             'Genus:sp1'  => '0.578947368421053',
                             'Genus:sp10' => '0.784362816006563',
                             'Genus:sp11' => '0.486100386100386',
                             'Genus:sp12' => '0.625829337780557',
                             'Genus:sp15' => '0.578947368421053',
                             'Genus:sp20' => '0.5',
                             'Genus:sp23' => '0.434782608695652',
                             'Genus:sp24' => '0.25',
                             'Genus:sp25' => '0.25',
                             'Genus:sp26' => '0.5',
                             'Genus:sp27' => '0.666666666666667',
                             'Genus:sp29' => '0.598591139574746',
                             'Genus:sp30' => '0.434782608695652',
                             'Genus:sp5'  => '0.6'
                           },
'PD_INCLUDED_TERMINAL_NODE_LIST' => {
                                      'Genus:sp1'  => '0.578947368421053',
                                      'Genus:sp10' => '0.784362816006563',
                                      'Genus:sp11' => '0.486100386100386',
                                      'Genus:sp12' => '0.625829337780557',
                                      'Genus:sp15' => '0.578947368421053',
                                      'Genus:sp20' => '0.5',
                                      'Genus:sp23' => '0.434782608695652',
                                      'Genus:sp24' => '0.25',
                                      'Genus:sp25' => '0.25',
                                      'Genus:sp26' => '0.5',
                                      'Genus:sp27' => '0.666666666666667',
                                      'Genus:sp29' => '0.598591139574746',
                                      'Genus:sp30' => '0.434782608695652',
                                      'Genus:sp5'  => '0.6'
                                    },
'PD_P'           => '0.451163454880594',
'PD_P_per_taxon' => '0.0322259610628996',
'PD_per_taxon'   => '0.682618105875523',
'PE_RANGELIST' => {
                    '30___'      => 12,
                    '31___'      => 30,
                    '32___'      => 33,
                    '33___'      => 50,
                    '34___'      => 9,
                    '35___'      => 53,
                    '36___'      => 33,
                    '37___'      => 57,
                    '38___'      => 57,
                    '39___'      => 65,
                    '41___'      => 78,
                    '42___'      => 107,
                    '44___'      => 5,
                    '45___'      => 107,
                    '49___'      => 112,
                    '50___'      => 115,
                    '51___'      => 5,
                    '52___'      => 116,
                    '58___'      => 127,
                    '59___'      => 127,
                    'Genus:sp1'  => 23,
                    'Genus:sp10' => 28,
                    'Genus:sp11' => 49,
                    'Genus:sp12' => 29,
                    'Genus:sp15' => 15,
                    'Genus:sp20' => 9,
                    'Genus:sp23' => 25,
                    'Genus:sp24' => 5,
                    'Genus:sp25' => 3,
                    'Genus:sp26' => 3,
                    'Genus:sp27' => 5,
                    'Genus:sp29' => 12,
                    'Genus:sp30' => 21,
                    'Genus:sp5'  => 10
                  },
'PE_WE'          => '1.58308662511342',
'PE_WE_P'        => '0.0747364998100494',
'PE_WE_SINGLE'   => '1.02058686362188',
'PE_WE_SINGLE_P' => '0.0481812484100488',
'PE_WTLIST' => {
                 '30___'      => '0.0064718614718615',
                 '31___'      => '0.006580997949419',
                 '32___'      => '0.00646669565722576',
                 '33___'      => '0.0034221664456554',
                 '34___'      => '0.151732854859624',
                 '35___'      => '0.00249014110193283',
                 '36___'      => '0.00155508416377982',
                 '37___'      => '0.00394704398155649',
                 '38___'      => '0.000955726252835477',
                 '39___'      => '0.00531373208186055',
                 '41___'      => '0.00194532468189072',
                 '42___'      => '0.00214934894114927',
                 '44___'      => '0.0530443421087678',
                 '45___'      => '0.000986794889656748',
                 '49___'      => '0.000729545879720464',
                 '50___'      => '4.22691626564195e-05',
                 '51___'      => '0.145985532713474',
                 '52___'      => '0.000125479547644827',
                 '58___'      => '0.000390962271515824',
                 '59___'      => 0,
                 'Genus:sp1'  => '0.0503432494279177',
                 'Genus:sp10' => '0.0280129577145201',
                 'Genus:sp11' => '0.01984083208573',
                 'Genus:sp12' => '0.043160643984866',
                 'Genus:sp15' => '0.0771929824561404',
                 'Genus:sp20' => '0.222222222222222',
                 'Genus:sp23' => '0.0173913043478261',
                 'Genus:sp24' => '0.05',
                 'Genus:sp25' => '0.0833333333333333',
                 'Genus:sp26' => '0.333333333333333',
                 'Genus:sp27' => '0.133333333333333',
                 'Genus:sp29' => '0.0498825949645622',
                 'Genus:sp30' => '0.020703933747412',
                 'Genus:sp5'  => '0.06'
               },
'PHYLO_A'   => '1.4927692308',
'PHYLO_ABC' => '9.5566534823',
'PHYLO_AED_LIST' => {
                      'Genus:sp1'  => '0.0503930969345596',
                      'Genus:sp10' => '0.0281896757943279',
                      'Genus:sp11' => '0.0494076062574589',
                      'Genus:sp12' => '0.050539886453687',
                      'Genus:sp15' => '0.040524675881928',
                      'Genus:sp20' => '0.041893941667476',
                      'Genus:sp23' => '0.148203607227373',
                      'Genus:sp24' => '0.305963938866254',
                      'Genus:sp25' => '0.368463938866254',
                      'Genus:sp26' => '0.0627272750008093',
                      'Genus:sp27' => '0.599310252633764',
                      'Genus:sp29' => '0.0728869137531598',
                      'Genus:sp30' => '0.256899259401286',
                      'Genus:sp5'  => '0.386675699373672'
                    },
'PHYLO_AED_P' => {
                   'Genus:sp1'  => undef,
                   'Genus:sp10' => undef,
                   'Genus:sp11' => undef,
                   'Genus:sp12' => undef,
                   'Genus:sp15' => undef,
                   'Genus:sp20' => undef,
                   'Genus:sp23' => undef,
                   'Genus:sp24' => undef,
                   'Genus:sp25' => undef,
                   'Genus:sp26' => undef,
                   'Genus:sp27' => undef,
                   'Genus:sp29' => undef,
                   'Genus:sp30' => undef,
                   'Genus:sp5'  => undef
                 },
'PHYLO_AED_T' => '2.46207976811201',
'PHYLO_B'     => '0.0000000000',
'PHYLO_C'     => '8.0638842515',
'PHYLO_ED_LIST' => {
                     'Genus:sp1'  => '0.678240495563069',
                     'Genus:sp10' => '0.80762333894188',
                     'Genus:sp11' => '0.582924169600393',
                     'Genus:sp12' => '0.678346653904325',
                     'Genus:sp15' => '0.678240495563069',
                     'Genus:sp20' => '0.682552763166875',
                     'Genus:sp23' => '0.557265280898026',
                     'Genus:sp24' => '0.615416143402958',
                     'Genus:sp25' => '0.615416143402958',
                     'Genus:sp26' => '0.682552763166875',
                     'Genus:sp27' => '0.758106931866058',
                     'Genus:sp29' => '0.657918005249967',
                     'Genus:sp30' => '0.557265280898026',
                     'Genus:sp5'  => '0.688766811352542'
                   },
'PHYLO_ED_P' => {
                  'Genus:sp1'  => undef,
                  'Genus:sp10' => undef,
                  'Genus:sp11' => undef,
                  'Genus:sp12' => undef,
                  'Genus:sp15' => undef,
                  'Genus:sp20' => undef,
                  'Genus:sp23' => undef,
                  'Genus:sp24' => undef,
                  'Genus:sp25' => undef,
                  'Genus:sp26' => undef,
                  'Genus:sp27' => undef,
                  'Genus:sp29' => undef,
                  'Genus:sp30' => undef,
                  'Genus:sp5'  => undef
                },
'PHYLO_ES_LIST' => {
                     'Genus:sp1'  => '0.66656052363853',
                     'Genus:sp10' => '0.830685020049678',
                     'Genus:sp11' => '0.577872967365978',
                     'Genus:sp12' => '0.740699957688393',
                     'Genus:sp15' => '0.66656052363853',
                     'Genus:sp20' => '0.688503612046397',
                     'Genus:sp23' => '0.506327788030815',
                     'Genus:sp24' => '0.616932918372087',
                     'Genus:sp25' => '0.616932918372087',
                     'Genus:sp26' => '0.688503612046397',
                     'Genus:sp27' => '0.808752211567386',
                     'Genus:sp29' => '0.66964554863157',
                     'Genus:sp30' => '0.506327788030815',
                     'Genus:sp5'  => '0.677086839428004'
                   },
'PHYLO_ES_P' => {
                  'Genus:sp1'  => undef,
                  'Genus:sp10' => undef,
                  'Genus:sp11' => undef,
                  'Genus:sp12' => undef,
                  'Genus:sp15' => undef,
                  'Genus:sp20' => undef,
                  'Genus:sp23' => undef,
                  'Genus:sp24' => undef,
                  'Genus:sp25' => undef,
                  'Genus:sp26' => undef,
                  'Genus:sp27' => undef,
                  'Genus:sp29' => undef,
                  'Genus:sp30' => undef,
                  'Genus:sp5'  => undef
                },
'PHYLO_JACCARD'            => '0.84379791173084',
'PHYLO_LABELS_NOT_ON_TREE' => {},
'PHYLO_LABELS_ON_TREE' => {
                            'Genus:sp1'  => 1,
                            'Genus:sp10' => 1,
                            'Genus:sp11' => 1,
                            'Genus:sp12' => 1,
                            'Genus:sp15' => 1,
                            'Genus:sp20' => 1,
                            'Genus:sp23' => 1,
                            'Genus:sp24' => 1,
                            'Genus:sp25' => 1,
                            'Genus:sp26' => 1,
                            'Genus:sp27' => 1,
                            'Genus:sp29' => 1,
                            'Genus:sp30' => 1,
                            'Genus:sp5'  => 1
                          },
'PHYLO_S2'         => 0,
'PHYLO_SORENSON'   => '0.729801407809261',
'PMPD1_MAX'        => '1.95985532713474',
'PMPD1_MEAN'       => '1.70275738232872',
'PMPD1_MIN'        => '0.5',
'PMPD1_N'          => 182,
'PMPD1_SD'         => '0.293830234111311',
'PMPD2_MAX'        => '1.95985532713474',
'PMPD2_MEAN'       => '1.68065889601647',
'PMPD2_MIN'        => '0.5',
'PMPD2_N'          => 440,
'PMPD2_SD'         => '0.272218460873199',
'PMPD3_MAX'        => '1.95985532713474',
'PMPD3_MEAN'       => '1.65678662960988',
'PMPD3_MIN'        => '0.5',
'PMPD3_N'          => 6086,
'PMPD3_SD'         => '0.219080210645172',
'PNTD1_MAX'        => '1.86377675442101',
'PNTD1_MEAN'       => '1.09027062122407',
'PNTD1_MIN'        => '0.5',
'PNTD1_N'          => 14,
'PNTD1_SD'         => '0.368844918238016',
'PNTD2_MAX'        => '1.86377675442101',
'PNTD2_MEAN'       => '1.08197443720832',
'PNTD2_MIN'        => '0.5',
'PNTD2_N'          => 22,
'PNTD2_SD'         => '0.296713670467583',
'PNTD3_MAX'        => '1.86377675442101',
'PNTD3_MEAN'       => '1.17079993908642',
'PNTD3_MIN'        => '0.5',
'PNTD3_N'          => 83,
'PNTD3_SD'         => '0.261537668675783',
'TDB_DENOMINATOR'  => 182,
'TDB_DISTINCTNESS' => '0.385156952955119',
'TDB_NUMERATOR'    => '70.0985654378316',
'TDB_VARIATION'    => '0.0344846899770178',
'TD_DENOMINATOR'   => 6086,
'TD_DISTINCTNESS'  => '0.312902618192633',
'TD_NUMERATOR'     => '1904.3253343203655',
'TD_VARIATION'     => '8.14607553623072'
}

@@ RESULTS_1_NBR_LISTS
{
'PD'              => '1.49276923076923',
'PD_ENDEMISM'     => undef,
'PD_ENDEMISM_WTS' => {},
'PD_INCLUDED_NODE_LIST' => {
                             '34___'      => '0.341398923434153',
                             '35___'      => '0.03299436960061',
                             '42___'      => '0.057495084175743',
                             '45___'      => '0.026396763298318',
                             '49___'      => '0.020427284632173',
                             '50___'      => '0.00121523842637206',
                             '52___'      => '0.00291112550535999',
                             '58___'      => '0.00993044169650192',
                             '59___'      => 0,
                             'Genus:sp20' => '0.5',
                             'Genus:sp26' => '0.5'
                           },
'PD_INCLUDED_TERMINAL_NODE_LIST' => {
                                      'Genus:sp20' => '0.5',
                                      'Genus:sp26' => '0.5'
                                    },
'PD_P'           => '0.0704726738019399',
'PD_P_per_taxon' => '0.0352363369009699',
'PD_per_taxon'   => '0.746384615384616',
'PE_RANGELIST' => {
                    '34___'      => 9,
                    '35___'      => 53,
                    '42___'      => 107,
                    '45___'      => 107,
                    '49___'      => 112,
                    '50___'      => 115,
                    '52___'      => 116,
                    '58___'      => 127,
                    '59___'      => 127,
                    'Genus:sp20' => 9,
                    'Genus:sp26' => 3
                  },
'PE_WE'          => '0.261858249294739',
'PE_WE_P'        => '0.0123621592705162',
'PE_WE_SINGLE'   => '0.261858249294739',
'PE_WE_SINGLE_P' => '0.0123621592705162',
'PE_WTLIST' => {
                 '34___'      => '0.0379332137149059',
                 '35___'      => '0.000622535275483208',
                 '42___'      => '0.000537337235287318',
                 '45___'      => '0.000246698722414187',
                 '49___'      => '0.000182386469930116',
                 '50___'      => '1.05672906641049e-05',
                 '52___'      => '2.50959095289654e-05',
                 '58___'      => '7.81924543031647e-05',
                 '59___'      => 0,
                 'Genus:sp20' => '0.0555555555555556',
                 'Genus:sp26' => '0.166666666666667'
               },
'PHYLO_AED_LIST' => {
                      'Genus:sp20' => '0.144628205128205',
                      'Genus:sp26' => '0.207128205128205'
                    },
'PHYLO_AED_P' => {
                   'Genus:sp20' => undef,
                   'Genus:sp26' => undef
                 },
'PHYLO_AED_T' => '0.35175641025641',
'PHYLO_ED_LIST' => {
                     'Genus:sp20' => '0.682552763166875',
                     'Genus:sp26' => '0.682552763166875'
                   },
'PHYLO_ED_P' => {
                  'Genus:sp20' => undef,
                  'Genus:sp26' => undef
                },
'PHYLO_ES_LIST' => {
                     'Genus:sp20' => '0.688503612046397',
                     'Genus:sp26' => '0.688503612046397'
                   },
'PHYLO_ES_P' => {
                  'Genus:sp20' => undef,
                  'Genus:sp26' => undef
                },
'PHYLO_LABELS_NOT_ON_TREE' => {},
'PHYLO_LABELS_ON_TREE' => {
                            'Genus:sp20' => 1,
                            'Genus:sp26' => 1
                          },
'PMPD1_MAX'        => 1,
'PMPD1_MEAN'       => '1',
'PMPD1_MIN'        => 1,
'PMPD1_N'          => 2,
'PMPD1_SD'         => '0',
'PMPD2_MAX'        => 1,
'PMPD2_MEAN'       => '1',
'PMPD2_MIN'        => 1,
'PMPD2_N'          => 2,
'PMPD2_SD'         => '0',
'PMPD3_MAX'        => 1,
'PMPD3_MEAN'       => '1',
'PMPD3_MIN'        => 1,
'PMPD3_N'          => 16,
'PMPD3_SD'         => '0',
'PNTD1_MAX'        => 1,
'PNTD1_MEAN'       => '1',
'PNTD1_MIN'        => 1,
'PNTD1_N'          => 2,
'PNTD1_SD'         => '0',
'PNTD2_MAX'        => 1,
'PNTD2_MEAN'       => '1',
'PNTD2_MIN'        => 1,
'PNTD2_N'          => 2,
'PNTD2_SD'         => '0',
'PNTD3_MAX'        => 1,
'PNTD3_MEAN'       => '1',
'PNTD3_MIN'        => 1,
'PNTD3_N'          => 6,
'PNTD3_SD'         => '0',
'TDB_DENOMINATOR'  => 2,
'TDB_DISTINCTNESS' => '0.341398923434153',
'TDB_NUMERATOR'    => '0.682797846868306',
'TDB_VARIATION'    => '0',
'TD_DENOMINATOR'   => 16,
'TD_DISTINCTNESS'  => '0.341398923434153',
'TD_NUMERATOR'     => '5.46238277494645',
'TD_VARIATION'     => '0.815872574453991'
}
