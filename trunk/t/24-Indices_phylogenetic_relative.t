#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

#  don't test plugins
local $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;
#  do test plugins
#local $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 0;

use rlib;
use Test::More;
use Biodiverse::Config;
use List::Util qw /sum/;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
    :tree
    :utils
};

my $generate_result_sets = 0;

my @calcs_to_test = qw/
    calc_phylo_rpe1
    calc_phylo_rpd1
    calc_phylo_rpe2
    calc_phylo_rpd2
    calc_labels_on_trimmed_tree
    calc_labels_not_on_trimmed_tree
/;

my @calcs_for_debug = qw /
    calc_pe
    calc_pd
    calc_endemism_whole
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

    test_standard();
    test_extra_labels_in_basedata();
    test_extra_labels_on_tree();
    test_sum_to_pd();

    done_testing;
    return 0;
}

sub test_standard {
    run_indices_test1 (
        calcs_to_test      => [@calcs_to_test],
        calc_topic_to_test => 'Phylogenetic Indices (relative)',
        generate_result_sets => $generate_result_sets,
    );
}

#  now try with extra labels that aren't on the tree
#  should be no difference in RPD/RPE - they should ignore the additional label
sub test_extra_labels_in_basedata {

    my $cb = sub {
        my %args = @_;
        my $bd = $args{basedata_ref};
        my $el_list1 = $args{element_list1};
        my $group = $el_list1->[0];

        $bd->add_element (
            group => $group,
            label => 'namenotontree:atall',
        );
    };

    my $overlay1 = {
        'PHYLO_LABELS_NOT_ON_TRIMMED_TREE' => {
            'namenotontree:atall' => 1
        },
        'PHYLO_LABELS_NOT_ON_TRIMMED_TREE_N' => 1,
        'PHYLO_LABELS_NOT_ON_TRIMMED_TREE_P' => '0.333333333333333',
    };
    my $overlay2 = {
        'PHYLO_LABELS_NOT_ON_TRIMMED_TREE' => {
            'namenotontree:atall' => 1
        },
        'PHYLO_LABELS_NOT_ON_TRIMMED_TREE_N' => 1,
        'PHYLO_LABELS_NOT_ON_TRIMMED_TREE_P' => '0.0666666666666667',
    };

    my %expected_results_overlay = (
        1 => $overlay1,
        2 => $overlay2,
    );

    run_indices_test1 (
        calcs_to_test   => [@calcs_to_test],
        #calcs_to_test   => [@calcs_to_test, @calcs_for_debug],
        callbacks       => [$cb],
        no_strict_match => 1,
        expected_results_overlay => \%expected_results_overlay,
    );
    
}

#  now try with extra labels that aren't on the tree
sub test_extra_labels_on_tree {
    my $cb = sub {
        my %args = @_;
        my $tree = $args{tree_ref};

        my $root = $tree->get_root_node;
        
        use Biodiverse::TreeNode;
        my $node = Biodiverse::TreeNode-> new (
            name   => 'EXTRA_NODE',
            length => 1,
        );
        $root->add_children (children => [$node]);
        #  add it to the Biodiverse::Tree object as well so the trimming works
        $tree->add_node (node_ref => $node);    
    };

    #  Adjust the RPD scores
    #  The RPE scores will not be affected since they trim the tree
    my $overlay1 = {
        PHYLO_RPD1      =>  1.07673100373221,
        PHYLO_RPD2      =>  0.307637429637773,
        PHYLO_RPD_DIFF1 => -1.00943531599894,
        PHYLO_RPD_DIFF2 => -1.03353754157303,
        PHYLO_RPD_NULL1 =>  0.0625,
        PHYLO_RPD_NULL2 =>  0.21875,
    };
    my $overlay2 = {
        PHYLO_RPD1      =>  0.984741731213716,
        PHYLO_RPD2      =>  0.459546141233067,
        PHYLO_RPD_DIFF1 => -0.553917223807715,
        PHYLO_RPD_DIFF2 => -5.16493025138441,
        PHYLO_RPD_NULL1 =>  0.4375,
        PHYLO_RPD_NULL2 =>  0.9375,
    };

    my %expected_results_overlay = (
        1 => $overlay1,
        2 => $overlay2,
    );

    run_indices_test1 (
        calcs_to_test   => [@calcs_to_test],
        #calcs_to_test   => [@calcs_to_test, @calcs_for_debug],
        callbacks       => [$cb],
        expected_results_overlay => \%expected_results_overlay,
        #generate_result_sets => 1,
    );

}

sub test_sum_to_pd {
    #  these indices should sum to PD_P when all groups are used in the analysis
    #  adapted from test_sum_to_pd() in 24-Indices_Phylogenetic.t

    my @calcs = qw/
        calc_phylo_rpe1
        calc_phylo_rpe2
        calc_pd
    /;

    my $cell_sizes = [200000, 200000];
    my $bd   = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
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

    my $pd = snap_to_precision (value => $results_list->{PD_P}, precision => '%.10f');
    
    my @indices_sum_to_pd = qw /PHYLO_RPE_NULL1 PHYLO_RPE_NULL2/;  #  add more

    foreach my $index (@indices_sum_to_pd) {
        my $result = snap_to_precision (value => $results_list->{$index}, precision => '%.10f');
        is ($result, $pd, "$index equals PD_P, sp_select_all()");
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
        is ($result, $pd, "$index sums to PD_P, sp_self_only()");
    }

}

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   PHYLO_LABELS_NOT_ON_TRIMMED_TREE   => {},
    PHYLO_LABELS_NOT_ON_TRIMMED_TREE_N => 0,
    PHYLO_LABELS_NOT_ON_TRIMMED_TREE_P => 0,
    PHYLO_LABELS_ON_TRIMMED_TREE       => {
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
    PHYLO_RPD1      => '0.999004792949887',
    PHYLO_RPD2      => '0.466202236709947',
    PHYLO_RPD_DIFF1 => '-0.547841338069293',
    PHYLO_RPD_DIFF2 => '-5.10132025336705',
    PHYLO_RPD_NULL1 => '0.451612903225806',
    PHYLO_RPD_NULL2 => '0.967741935483871',
    PHYLO_RPE1      => '0.93376090017044',
    PHYLO_RPE2      => '1.0686301259127',
    PHYLO_RPE_DIFF1 => '-0.10486223299973',
    PHYLO_RPE_DIFF2 => '0.108647434412251',
    PHYLO_RPE_NULL1 => '0.080038155159857',
    PHYLO_RPE_NULL2 => '0.0699367330171586'
}


@@ RESULTS_1_NBR_LISTS
{   PHYLO_LABELS_NOT_ON_TRIMMED_TREE   => {},
    PHYLO_LABELS_NOT_ON_TRIMMED_TREE_N => 0,
    PHYLO_LABELS_NOT_ON_TRIMMED_TREE_P => 0,
    PHYLO_LABELS_ON_TRIMMED_TREE       => {
        'Genus:sp20' => 1,
        'Genus:sp26' => 1
    },
    PHYLO_RPD1      => '1.09232644393007',
    PHYLO_RPD2      => '0.312093269694305',
    PHYLO_RPD_DIFF1 => '-1.02185377012813',
    PHYLO_RPD_DIFF2 => '-1.02688600063941',
    PHYLO_RPD_NULL1 => '0.0645161290322581',
    PHYLO_RPD_NULL2 => '0.225806451612903',
    PHYLO_RPE1      => '0.862260609118506',
    PHYLO_RPE2      => '1.14312240745805',
    PHYLO_RPE_DIFF1 => '-0.0360681957551517',
    PHYLO_RPE_DIFF2 => '0.0374777830518129',
    PHYLO_RPE_NULL1 => '0.014336917562724',
    PHYLO_RPE_NULL2 => '0.0108143792736999'
}


