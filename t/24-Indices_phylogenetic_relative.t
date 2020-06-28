#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

#  don't test plugins
BEGIN {
    $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;
    #  do test plugins
    #$ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 0;
}

use rlib;
use Test2::V0;

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
    calc_phylo_rpe_central
    calc_labels_on_trimmed_tree
    calc_labels_not_on_trimmed_tree
/;

my @calcs_for_debug = qw /
    calc_pe
    calc_pd
    calc_endemism_whole
/;

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @subs = grep {$_ =~ 'main::test_'} $obj->functions();

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

    foreach my $sub (sort @subs) {
        no strict 'refs';
        $sub->();
    }
    
    done_testing;
    return 0;
}


sub test_indices1 {
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

    my $results = run_indices_test1 (
        calcs_to_test   => [@calcs_to_test],
        #calcs_to_test   => [@calcs_to_test, @calcs_for_debug],
        callbacks       => [$cb],
        no_strict_match => 1,
        expected_results_overlay => \%expected_results_overlay,
    );
    
    check_rpd_rpe_diff_signs ($results, '(main tests)');
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
    my $overlay2 = {
        PHYLO_RPD1      => '0.984741731213716',
        PHYLO_RPD2      => '0.770261998089516',
        PHYLO_RPD_DIFF1 => '-0.148077392180729',
        PHYLO_RPD_DIFF2 => '-2.85036322888866',
        PHYLO_RPD_NULL1 => '0.4375',
        PHYLO_RPD_NULL2 => '0.559322033898305',
    };
    my $overlay1 = {
        PHYLO_RPD1      => '1.07673100373221',
        PHYLO_RPD2      => '0.397044557626251',
        PHYLO_RPD_DIFF1 => '0.10637910584951',
        PHYLO_RPD_DIFF2 => '-2.26693280291137',
        PHYLO_RPD_NULL1 => '0.0625',
        PHYLO_RPD_NULL2 => '0.169491525423729',
    };


    my %expected_results_overlay = (
        1 => $overlay1,
        2 => $overlay2,
    );

    my $results = run_indices_test1 (
        calcs_to_test   => [@calcs_to_test],
        #calcs_to_test   => [@calcs_to_test, @calcs_for_debug],
        callbacks       => [$cb],
        expected_results_overlay => \%expected_results_overlay,
        descr_suffix    => ' (test_extra_labels_on_tree)',
        #generate_result_sets => 1,
    );

    check_rpd_rpe_diff_signs ($results, '(extra labels on tree)');
}


sub check_rpd_rpe_diff_signs {
    my ($results, $suffix) = @_;
    
    #  we expect any RPE/RPD < 1 to have a negative diff as in such cases observed < null

    my %indices;
    foreach my $pfx (qw /PHYLO_RPD PHYLO_RPE/) {
        foreach my $i (1, 2) {
            $indices{$pfx . $i} = $pfx . '_DIFF' . $i;
        }
    }

    subtest "Expected RPE/RPD diff signs $suffix" => sub {
        foreach my $nbr_count (sort keys %$results) {
            my $res_hash = $results->{$nbr_count};
            foreach my $rpde_idx (sort keys %indices) {
                my $diff_idx  = $indices{$rpde_idx};
                my $sign_idx  = $res_hash->{$rpde_idx} <=> 1;
                my $sign_diff = $res_hash->{$diff_idx} <=> 0;
                is ($sign_idx, $sign_diff, "Sign of $diff_idx $nbr_count nbrs $suffix");
            }
        }
    };
    
    return;
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


sub test_rpe_central {

    my @calcs = qw/
        calc_phylo_rpe2
        calc_phylo_rpe_central
    /;

    my %list_indices_to_check;

    foreach my $key (qw /PHYLO_RPEC PHYLO_RPE_NULLC PHYLO_RPE_DIFFC/) {
        my $comp = $key;
        $comp =~ s/C$/2/;
        $list_indices_to_check{$comp} = $key;
    }

    my $cell_sizes = [200000, 200000];
    my $bd   = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
    my $tree = get_tree_object_from_sample_data();

    $bd->build_spatial_index(resolutions => $cell_sizes);

    #  should add a def query since we don't need the full set of results
    my $sp1 = $bd->add_spatial_output (name => 'RPE2');
    $sp1->run_analysis (
        calculations       => ['calc_phylo_rpe2'],
        spatial_conditions => ['sp_self_only()'],
        tree_ref           => $tree,
    );
    my $sp1c = $bd->add_spatial_output (name => 'RPEC');
    $sp1c->run_analysis (
        calculations       => ['calc_phylo_rpe_central'],
        spatial_conditions => ['sp_self_only()'],
        tree_ref           => $tree,
    );


    subtest 'RPE2 and RPEC' => sub {
        foreach my $elt (sort $sp1->get_element_list) {
            my $rpe2 = $sp1->get_list_ref(element => $elt, list => 'SPATIAL_RESULTS');
            my $rpec = $sp1c->get_list_ref(element => $elt, list => 'SPATIAL_RESULTS');
            my @arr_exp = map {sprintf '%.12f', $_}  @$rpe2{keys %list_indices_to_check};
            my @arr_obs = map {sprintf '%.12f', $_}  @$rpec{values %list_indices_to_check};

            is (
                \@arr_obs,
                \@arr_exp,
                "RPE2 and RPEC same for $elt",
            );
        }
    };

    my $sp2 = $bd->add_spatial_output (name => 'RPE2 2nbrs');
    $sp2->run_analysis (
        calculations       => ['calc_phylo_rpe2', 'calc_local_range_lists'],
        spatial_conditions => ['sp_self_only()', 'sp_circle (radius => 400000)'],
        tree_ref           => $tree,
    );
    my $sp2c = $bd->add_spatial_output (name => 'RPEC 2nbrs');
    $sp2c->run_analysis (
        calculations       => ['calc_phylo_rpe_central', 'calc_local_range_lists'],
        spatial_conditions => ['sp_self_only()', 'sp_circle (radius => 400000)'],
        tree_ref           => $tree,
    );


    subtest 'RPE2 and RPEC for two nbr sets' => sub {
        foreach my $elt (sort $sp2->get_element_list) {
            my $rpe2 = $sp2->get_list_ref(element => $elt, list => 'SPATIAL_RESULTS');
            my $rpec = $sp2c->get_list_ref(element => $elt, list => 'SPATIAL_RESULTS');
            my @exp = map {sprintf '%.12f', $_}  @$rpe2{keys %list_indices_to_check};
            my @obs = map {sprintf '%.12f', $_}  @$rpec{values %list_indices_to_check};

            my $labels_set1 = $sp2->get_list_ref (element => $elt, list => 'ABC2_LABELS_SET1');
            my $labels_all  = $sp2->get_list_ref (element => $elt, list => 'ABC2_LABELS_ALL');

            #  expectation differs if no additional labels in set 2
            my $key_count = scalar (keys %$labels_set1);
            my $no_new_labels
                = $key_count == scalar (keys %$labels_all)
                    && $key_count == scalar grep {exists $labels_all->{$_}} keys %$labels_set1;

            if ($no_new_labels) {
                is (
                    \@exp,
                    \@obs,
                    "RPE2 and RPEC when nbr set 2 has no additional labels, $elt",
                );
            }
            else {
                isnt (
                    \@exp,
                    \@obs,
                    "RPE2 and RPEC not same when additional labels in nbr set 2, $elt",
                );
            }
        }
    };

    return;
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
    PHYLO_RPD2      => '0.792953951002256',
    PHYLO_RPD_DIFF1 => '-0.00952032361421317',
    PHYLO_RPD_DIFF2 => '-2.49531179287393',
    PHYLO_RPD_NULL1 => '0.451612903225806',
    PHYLO_RPD_NULL2 => '0.568965517241379',
    PHYLO_RPE1      => '0.93376090017044',
    PHYLO_RPE2      => '1.0686301259127',
    PHYLO_RPE_DIFF1 => '-0.11230094661341',
    PHYLO_RPE_DIFF2 => '0.10166982174441',
    PHYLO_RPE_NULL1 => '0.080038155159857',
    PHYLO_RPE_NULL2 => '0.0699367330171586',
    PHYLO_RPEC      => '1.05209134904813',
    PHYLO_RPE_DIFFC => '0.0353617538138754',
    PHYLO_RPE_NULLC => '0.0320476556937053',
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
    PHYLO_RPD2      => '0.408741508051251',
    PHYLO_RPD_DIFF1 => '0.126172972787584',
    PHYLO_RPD_DIFF2 => '-2.15934145866448',
    PHYLO_RPD_NULL1 => '0.0645161290322581',
    PHYLO_RPD_NULL2 => '0.172413793103448',
    PHYLO_RPE1      => '0.862260609118506',
    PHYLO_RPE2      => '1.14312240745805',
    PHYLO_RPE_DIFF1 => '-0.0418298080345157',
    PHYLO_RPE_DIFF2 => '0.0327854504533351',
    PHYLO_RPE_NULL1 => '0.014336917562724',
    PHYLO_RPE_NULL2 => '0.0108143792736999',
    PHYLO_RPEC      => '1.14312240745805',
    PHYLO_RPE_DIFFC => '0.0327854504533351',
    PHYLO_RPE_NULLC => '0.0108143792736999',
}


