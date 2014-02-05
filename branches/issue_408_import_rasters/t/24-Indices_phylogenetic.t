#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

#  don't test plugins
local $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;

use rlib;
use Test::Most;
use List::Util qw /sum/;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
    :tree
    :utils
};

my @calcs = qw/
    calc_phylo_aed
    calc_phylo_aed_t
    calc_phylo_aed_t_wtlists
    calc_phylo_corrected_weighted_rarity
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
    calc_phylo_corrected_weighted_endemism
    calc_taxonomic_distinctness
    calc_taxonomic_distinctness_binary
    calc_pe_single
    calc_count_labels_on_tree
    calc_pd_terminal_node_count
/;

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


    test_indices();
    #test_calc_phylo_aed();
    test_extra_labels_in_bd();
    test_sum_to_pd();

    
    done_testing;
    return 0;
}


sub test_calc_phylo_aed {
    note "LOCAL OVERRIDE TO ONLY DO AED CALCS - REMOVE BEFORE REINTEGRATION\n";

    my @calcs = qw/
        calc_phylo_aed
        calc_phylo_aed_t
        calc_phylo_aed_t_wtlists
    /;

    run_indices_test1 (
        calcs_to_test   => [@calcs],
        no_strict_match => 1,
        #generate_result_sets => 1,
    );
}

sub test_sum_to_pd {
    #  these indices should sum to PD when all groups are used in the analysis
    #  some lists should also sum to 1 - need to change the subroutine name

    my @calcs = qw/
        calc_pe
        calc_phylo_aed_t
        calc_phylo_aed_t_wtlists
        calc_phylo_corrected_weighted_rarity
        calc_phylo_corrected_weighted_endemism
        calc_pd
    /;

    my $cell_sizes   = [200000, 200000];
    my $bd = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
    my $tree = get_tree_object_from_sample_data();

    my $sp = $bd->add_spatial_output (name => 'should sum to PD, select_all');
    $sp->run_analysis (
        calculations       => [@calcs],
        spatial_conditions => ['sp_select_all()'],
        tree_ref           => $tree,
    );

    my $elts = $sp->get_element_list;
    my $elt_to_check = $elts->[0];  #  they will all be the same value
    my $results_list = $sp->get_list_ref (
        list    => 'SPATIAL_RESULTS',
        element => $elt_to_check,
    );

    my $pd = snap_to_precision (value => $results_list->{PD}, precision => '%.10f');
    
    my @indices_sum_to_pd = qw /PE_WE PHYLO_AED_T/;  #  add more
    #  these need to equal 1 for sp_select_all()
    my @indices_should_be_one = qw /PHYLO_RARITY_CWR PE_CWE/;
    #   these need to sum to 1 across nbrhoods
    my @lists_sum_to_one = qw /PHYLO_AED_T_WTLIST_P/;

    foreach my $index (@indices_sum_to_pd) {
        my $result = snap_to_precision (value => $results_list->{$index}, precision => '%.10f');
        is ($result, $pd, "$index equals PD, sp_select_all()");
    }
    foreach my $index (@indices_should_be_one) {
        my $result = snap_to_precision (value => $results_list->{$index}, precision => '%.10f');
        is ($result, 1, "$index is 1, sp_select_all()");
    }

    foreach my $list_name (@lists_sum_to_one) {
        my $list = $sp->get_list_ref (
            list    => $list_name,
            element => $elt_to_check,
        );
        my $sum  = sum values %$list;
        is ($sum, 1, "$list_name sums to 1, sp_select_all()");
    }
    

    #  should also do an sp_self_only and then sum the values across all elements
    $sp = $bd->add_spatial_output (name => 'should sum to PD, self_only');
    $sp->run_analysis (
        calculations       => [@calcs],
        spatial_conditions => ['sp_self_only()'],
        tree_ref           => $tree,
    );
    
    my %sums;
    foreach my $element (@$elts) {
        my $results_list = $sp->get_list_ref (
            list    => 'SPATIAL_RESULTS',
            element => $element,
        );
        foreach my $index (@indices_sum_to_pd) {
            $sums{$index} += $results_list->{$index};
        }
    }

    foreach my $index (@indices_sum_to_pd) {
        my $result = snap_to_precision (value => $sums{$index}, precision => '%.10f');
        is ($result, $pd, "$index sums to PD, sp_self_only()");
    }
    
    foreach my $list_name (@lists_sum_to_one) {
        subtest "$list_name sums to 1 or undef, sp_self_only()" => sub {
            foreach my $element (@$elts) {
                my $list = $sp->get_list_ref (
                    list    => $list_name,
                    element => $element,
                );
                my $sum = sum values %$list;
                $sum //= 1;  #  undef is valid for samples with no tree terminals
                my $result = snap_to_precision (value => $sum, precision => '%.10f');
                is ($result, 1, "$list_name sums to 1 for $element, sp_self_only()");
            }
        };
    }

}


sub test_indices {
    run_indices_test1 (
        calcs_to_test      => [@calcs],
        calc_topic_to_test => 'Phylogenetic Indices',
        #generate_result_sets => 1,
    );
}

#  now try with extra labels that aren't on the tree
sub test_extra_labels_in_bd {
    my $cb = sub {
        my %args = @_;
        my $bd = $args{basedata_ref};
        my $el_list1 = $args{element_list1};
        #  add a new label to all of the groups to be sure we get coverage
        foreach my $group ($bd->get_groups) {  
            $bd->add_element (
                group => $group,
                label => 'namenotontree:atall',
            );
        }
    };
    
    my $overlay1 = {
        'PHYLO_LABELS_NOT_ON_TREE_N' => 1,
        'PHYLO_LABELS_NOT_ON_TREE_P' => (1/3),
        'PHYLO_LABELS_NOT_ON_TREE' => {
            'namenotontree:atall' => 1,
        },
    };
    my $overlay2 = {
        'PHYLO_LABELS_NOT_ON_TREE_N' => 1,
        'PHYLO_LABELS_NOT_ON_TREE_P' => (1/15),
        'PHYLO_LABELS_NOT_ON_TREE' => {
            'namenotontree:atall' => 1,
        },
    };

    my %expected_results_overlay = (
        1 => $overlay1,
        2 => $overlay2,
    );

    my @calcs_to_test = qw/calc_phylo_aed calc_labels_not_on_tree/;
    run_indices_test1 (
        calcs_to_test   => \@calcs_to_test,
        callbacks       => [$cb],
        no_strict_match => 1,
        expected_results_overlay => \%expected_results_overlay,
    );
    
}

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'PD' => '9.55665348225732',
  'PD_ENDEMISM' => undef,
  'PD_ENDEMISM_WTS' => {},
  'PD_INCLUDED_NODE_LIST' => {
                               '30___' => '0.077662337662338',
                               '31___' => '0.098714969241285',
                               '32___' => '0.106700478344225',
                               '33___' => '0.05703610742759',
                               '34___' => '0.341398923434153',
                               '35___' => '0.03299436960061',
                               '36___' => '0.051317777404734',
                               '37___' => '0.11249075347436',
                               '38___' => '0.0272381982058111',
                               '39___' => '0.172696292660468',
                               '41___' => '0.075867662593738',
                               '42___' => '0.057495084175743',
                               '44___' => '0.265221710543839',
                               '45___' => '0.026396763298318',
                               '49___' => '0.020427284632173',
                               '50___' => '0.00121523842637206',
                               '51___' => '0.729927663567369',
                               '52___' => '0.00291112550535999',
                               '58___' => '0.00993044169650192',
                               '59___' => 0,
                               'Genus:sp1' => '0.578947368421053',
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
                               'Genus:sp5' => '0.6'
                             },
  'PD_INCLUDED_TERMINAL_NODE_LIST' => {
                                        'Genus:sp1' => '0.578947368421053',
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
                                        'Genus:sp5' => '0.6'
                                      },
  'PD_P' => '0.451163454880594',
  'PD_P_per_taxon' => '0.0322259610628996',
  'PD_per_taxon' => '0.682618105875523',
  'PE_CWE' => '0.165652822722154',
  'PE_LOCAL_RANGELIST' => {
                            '30___' => 1,
                            '31___' => 2,
                            '32___' => 2,
                            '33___' => 3,
                            '34___' => 4,
                            '35___' => 4,
                            '36___' => 1,
                            '37___' => 2,
                            '38___' => 2,
                            '39___' => 2,
                            '41___' => 2,
                            '42___' => 4,
                            '44___' => 1,
                            '45___' => 4,
                            '49___' => 4,
                            '50___' => 4,
                            '51___' => 1,
                            '52___' => 5,
                            '58___' => 5,
                            '59___' => 5,
                            'Genus:sp1' => 2,
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
                            'Genus:sp5' => 1
                          },
  'PE_RANGELIST' => {
                      '30___' => 12,
                      '31___' => 30,
                      '32___' => 33,
                      '33___' => 50,
                      '34___' => 9,
                      '35___' => 53,
                      '36___' => 33,
                      '37___' => 57,
                      '38___' => 57,
                      '39___' => 65,
                      '41___' => 78,
                      '42___' => 107,
                      '44___' => 5,
                      '45___' => 107,
                      '49___' => 112,
                      '50___' => 115,
                      '51___' => 5,
                      '52___' => 116,
                      '58___' => 127,
                      '59___' => 127,
                      'Genus:sp1' => 23,
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
                      'Genus:sp5' => 10
                    },
  'PE_WE' => '1.58308662511342',
  'PE_WE_P' => '0.0747364998100494',
  'PE_WE_SINGLE' => '1.02058686362188',
  'PE_WE_SINGLE_P' => '0.0481812484100488',
  'PE_WTLIST' => {
                   '30___' => '0.0064718614718615',
                   '31___' => '0.006580997949419',
                   '32___' => '0.00646669565722576',
                   '33___' => '0.0034221664456554',
                   '34___' => '0.151732854859624',
                   '35___' => '0.00249014110193283',
                   '36___' => '0.00155508416377982',
                   '37___' => '0.00394704398155649',
                   '38___' => '0.000955726252835477',
                   '39___' => '0.00531373208186055',
                   '41___' => '0.00194532468189072',
                   '42___' => '0.00214934894114927',
                   '44___' => '0.0530443421087678',
                   '45___' => '0.000986794889656748',
                   '49___' => '0.000729545879720464',
                   '50___' => '4.22691626564195e-005',
                   '51___' => '0.145985532713474',
                   '52___' => '0.000125479547644827',
                   '58___' => '0.000390962271515824',
                   '59___' => 0,
                   'Genus:sp1' => '0.0503432494279177',
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
                   'Genus:sp5' => '0.06'
                 },
  'PHYLO_A' => '1.4927692308',
  'PHYLO_ABC' => '9.5566534823',
  'PHYLO_AED_LIST' => {
                        'Genus:sp1' => '0.0107499482131097',
                        'Genus:sp10' => '0.00545225560494617',
                        'Genus:sp11' => '0.00207155382856306',
                        'Genus:sp12' => '0.00450677503945796',
                        'Genus:sp15' => '0.0124251431448835',
                        'Genus:sp20' => '0.0252759553987262',
                        'Genus:sp23' => '0.00327355381530656',
                        'Genus:sp24' => '0.0336871540660519',
                        'Genus:sp25' => '0.0505953666264384',
                        'Genus:sp26' => '0.0805754945692332',
                        'Genus:sp27' => '0.0230520172760593',
                        'Genus:sp29' => '0.0116977777714026',
                        'Genus:sp30' => '0.00499599356630484',
                        'Genus:sp5' => '0.0176398692951442'
                      },
  'PHYLO_AED_T' => '1.38006841833426',
  'PHYLO_AED_T_WTLIST' => {
                            'Genus:sp1' => '0.0859995857048772',
                            'Genus:sp10' => '0.0872360896791387',
                            'Genus:sp11' => '0.0186439844570675',
                            'Genus:sp12' => '0.0360542003156637',
                            'Genus:sp15' => '0.136676574593719',
                            'Genus:sp20' => '0.303311464784715',
                            'Genus:sp23' => '0.00654710763061312',
                            'Genus:sp24' => '0.0673743081321039',
                            'Genus:sp25' => '0.0505953666264384',
                            'Genus:sp26' => '0.483452967415399',
                            'Genus:sp27' => '0.0230520172760593',
                            'Genus:sp29' => '0.0584888888570131',
                            'Genus:sp30' => '0.00499599356630484',
                            'Genus:sp5' => '0.0176398692951442'
                          },
  'PHYLO_AED_T_WTLIST_P' => {
                              'Genus:sp1' => '0.0623154508590804',
                              'Genus:sp10' => '0.063211423810736',
                              'Genus:sp11' => '0.0135094638855448',
                              'Genus:sp12' => '0.0261249368775362',
                              'Genus:sp15' => '0.0990360860215086',
                              'Genus:sp20' => '0.219780020146256',
                              'Genus:sp23' => '0.00474404568906481',
                              'Genus:sp24' => '0.0488195420147536',
                              'Genus:sp25' => '0.0366614915277222',
                              'Genus:sp26' => '0.350310869369018',
                              'Genus:sp27' => '0.0167035322088474',
                              'Genus:sp29' => '0.0423811516008817',
                              'Genus:sp30' => '0.00362010571355224',
                              'Genus:sp5' => '0.0127818802754979'
                            },
  'PHYLO_B' => '0',
  'PHYLO_C' => '8.0638842515',
  'PHYLO_ED_LIST' => {
                       'Genus:sp1' => '0.678240495563069',
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
                       'Genus:sp5' => '0.688766811352542'
                     },
  'PHYLO_ES_LIST' => {
                       'Genus:sp1' => '0.66656052363853',
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
                       'Genus:sp5' => '0.677086839428004'
                     },
  'PHYLO_JACCARD' => '0.84379791173084',
  'PHYLO_LABELS_NOT_ON_TREE' => {},
  'PHYLO_LABELS_NOT_ON_TREE_N' => 0,
  'PHYLO_LABELS_NOT_ON_TREE_P' => 0,
  'PHYLO_LABELS_ON_TREE' => {
                              'Genus:sp1' => 1,
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
                              'Genus:sp5' => 1
                            },
    'PHYLO_LABELS_ON_TREE_COUNT' => 14,
    PD_INCLUDED_TERMINAL_NODE_COUNT => 14,
  'PHYLO_RARITY_CWR' => '0.144409172195734',
  'PHYLO_S2' => 0,
  'PHYLO_SORENSON' => '0.729801407809261',
  'TDB_DENOMINATOR' => 182,
  'TDB_DISTINCTNESS' => '0.385156952955119',
  'TDB_NUMERATOR' => '70.0985654378316',
  'TDB_VARIATION' => '0.0344846899770178',
  'TD_DENOMINATOR' => 6086,
  'TD_DISTINCTNESS' => '0.312902618192633',
  'TD_NUMERATOR' => '1904.32533432037',
  'TD_VARIATION' => '8.14607553623072'
}



@@ RESULTS_1_NBR_LISTS
{
  'PD' => '1.49276923076923',
  'PD_ENDEMISM' => undef,
  'PD_ENDEMISM_WTS' => {},
  'PD_INCLUDED_NODE_LIST' => {
                               '34___' => '0.341398923434153',
                               '35___' => '0.03299436960061',
                               '42___' => '0.057495084175743',
                               '45___' => '0.026396763298318',
                               '49___' => '0.020427284632173',
                               '50___' => '0.00121523842637206',
                               '52___' => '0.00291112550535999',
                               '58___' => '0.00993044169650192',
                               '59___' => 0,
                               'Genus:sp20' => '0.5',
                               'Genus:sp26' => '0.5'
                             },
  'PD_INCLUDED_TERMINAL_NODE_LIST' => {
                                        'Genus:sp20' => '0.5',
                                        'Genus:sp26' => '0.5'
                                      },
  'PD_P' => '0.0704726738019399',
  'PD_P_per_taxon' => '0.0352363369009699',
  'PD_per_taxon' => '0.746384615384616',
  'PE_CWE' => '0.175417769804782',
  'PE_LOCAL_RANGELIST' => {
                            '34___' => 1,
                            '35___' => 1,
                            '42___' => 1,
                            '45___' => 1,
                            '49___' => 1,
                            '50___' => 1,
                            '52___' => 1,
                            '58___' => 1,
                            '59___' => 1,
                            'Genus:sp20' => 1,
                            'Genus:sp26' => 1
                          },
  'PE_RANGELIST' => {
                      '34___' => 9,
                      '35___' => 53,
                      '42___' => 107,
                      '45___' => 107,
                      '49___' => 112,
                      '50___' => 115,
                      '52___' => 116,
                      '58___' => 127,
                      '59___' => 127,
                      'Genus:sp20' => 9,
                      'Genus:sp26' => 3
                    },
  'PE_WE' => '0.261858249294739',
  'PE_WE_P' => '0.0123621592705162',
  'PE_WE_SINGLE' => '0.261858249294739',
  'PE_WE_SINGLE_P' => '0.0123621592705162',
  'PE_WTLIST' => {
                   '34___' => '0.0379332137149059',
                   '35___' => '0.000622535275483208',
                   '42___' => '0.000537337235287318',
                   '45___' => '0.000246698722414187',
                   '49___' => '0.000182386469930116',
                   '50___' => '1.05672906641049e-005',
                   '52___' => '2.50959095289654e-005',
                   '58___' => '7.81924543031647e-005',
                   '59___' => 0,
                   'Genus:sp20' => '0.0555555555555556',
                   'Genus:sp26' => '0.166666666666667'
                 },
  'PHYLO_AED_LIST' => {
                        'Genus:sp20' => '0.0252759553987262',
                        'Genus:sp26' => '0.0805754945692332'
                      },
  'PHYLO_AED_T' => '0.262254810733371',
  'PHYLO_AED_T_WTLIST' => {
                            'Genus:sp20' => '0.101103821594905',
                            'Genus:sp26' => '0.161150989138466'
                          },
  'PHYLO_AED_T_WTLIST_P' => {
                              'Genus:sp20' => '0.385517509906406',
                              'Genus:sp26' => '0.614482490093594'
                            },
  'PHYLO_ED_LIST' => {
                       'Genus:sp20' => '0.682552763166875',
                       'Genus:sp26' => '0.682552763166875'
                     },
  'PHYLO_ES_LIST' => {
                       'Genus:sp20' => '0.688503612046397',
                       'Genus:sp26' => '0.688503612046397'
                     },
  'PHYLO_LABELS_NOT_ON_TREE' => {},
  'PHYLO_LABELS_NOT_ON_TREE_N' => 0,
  'PHYLO_LABELS_NOT_ON_TREE_P' => 0,
  'PHYLO_LABELS_ON_TREE' => {
                              'Genus:sp20' => 1,
                              'Genus:sp26' => 1
                            },
    'PHYLO_LABELS_ON_TREE_COUNT' => 2,
    'PD_INCLUDED_TERMINAL_NODE_COUNT' => 2,
  'PHYLO_RARITY_CWR' => '0.175683424689984',
  'TDB_DENOMINATOR' => 2,
  'TDB_DISTINCTNESS' => '0.341398923434153',
  'TDB_NUMERATOR' => '0.682797846868306',
  'TDB_VARIATION' => '0',
  'TD_DENOMINATOR' => 16,
  'TD_DISTINCTNESS' => '0.341398923434153',
  'TD_NUMERATOR' => '5.46238277494645',
  'TD_VARIATION' => '0.815872574453991'
}
