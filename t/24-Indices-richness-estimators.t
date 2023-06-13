use strict;
use warnings;
use 5.016;

local $| = 1;

use rlib;
use Test2::V0;

use Readonly;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
};
use Data::Section::Simple qw(get_data_section);

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @subs = grep {$_ =~ 'main::test_'} $obj->functions();

#  a few package "constants"
my $bd = get_basedata();
Readonly my $focal_gp => 'Broad_Meadow_Brook';
Readonly my @nbr_set2 => grep {$_ ne $focal_gp} $bd->get_groups;
#  many of the expected vals are from external sources
#  and are only precise to 6dp
Readonly my $subtest_tolerance => 1e-6;

exit main( @ARGV );

sub main {
    my @args  = @_;

    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
                if not my $func = (__PACKAGE__->can( 'test_' . $name ) || __PACKAGE__->can( $name ));
            $func->($bd);
        }
        done_testing;
        return 0;
    }


    foreach my $sub (sort @subs) {
        no strict 'refs';
        $sub->($bd);
    }

    done_testing;
    return 0;
}


sub test_indices {
    my $bd = shift->clone;

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_chao1
            calc_chao2
            calc_ace
            calc_ice
            calc_hurlbert_es
        /],
        calc_topic_to_test => 'Richness estimators',
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        descr_suffix       => 'main tests',
        # generate_result_sets => 1,
    );

    return;
}

sub test_indices_1col {
    my $bd = shift->clone;

    $bd->delete_groups (groups => \@nbr_set2);
    
    my $results_overlay2 = {
        CHAO1_ESTIMATE => '15.5555555555556',
        CHAO1_CI_LOWER => '8.93051',
        CHAO1_CI_UPPER => '69.349636',
        CHAO1_F1_COUNT => 4,
        CHAO1_F2_COUNT => 1,
        CHAO1_META     => {
            CHAO_FORMULA     => 2,
            CI_FORMULA       => 13,
            VARIANCE_FORMULA => 6
        },
        CHAO1_UNDETECTED => '7.55555555555556',
        CHAO1_VARIANCE   => 121.728395,
        CHAO1_SE         => 11.033059,
        CHAO2_ESTIMATE   => 8,
        CHAO2_CI_LOWER   => undef,
        CHAO2_CI_UPPER   => undef,
        CHAO2_META       => {
            CHAO_FORMULA     => 4,
            CI_FORMULA       => 13,
            VARIANCE_FORMULA => 11
        },
        CHAO2_Q1_COUNT   => 8,
        CHAO2_Q2_COUNT   => 0,
        CHAO2_UNDETECTED => 0,
        CHAO2_VARIANCE   => 0,
        CHAO2_SE         => 0,
    };
    # identical to overlay2 since we have only one group in the basedata
    my $results_overlay1 = {%$results_overlay2}; 

    my %expected_results_overlay = (
        1 => $results_overlay1,
        2 => $results_overlay2,
    );

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_chao1
            calc_chao2
        /],
        #calc_topic_to_test => 'Richness estimators',
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => [],
        expected_results   => \%expected_results_overlay,
        descr_suffix       => 'one group',
        tolerance          => $subtest_tolerance,
    );

    return;
}


#  chao2 differs when q1 or q2 are zero
sub test_chao1_F2_no_F1 {
    my $bd = shift->clone;

    #  need to ensure there are no uniques - bump their sample counts
    foreach my $label ($bd->get_labels) {
        if ($bd->get_label_sample_count(element => $label) == 1) {
            $bd->add_element (group => $focal_gp, label => $label, count => 20);
        }
    }
    
    my $results2 = {
        CHAO1_ESTIMATE   => 26,        CHAO1_SE         => 0.8749986,
        CHAO1_F1_COUNT   => 0,         CHAO1_F2_COUNT   => 5,
        CHAO1_UNDETECTED => 0,         CHAO1_VARIANCE   => 0.7656226,
        CHAO1_CI_LOWER   => 26,        CHAO1_CI_UPPER   => 28.680536,
        CHAO1_META       => {
            CHAO_FORMULA     => 0,
            CI_FORMULA       => 14,
            VARIANCE_FORMULA => 8,
        },
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_chao1
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_chao1_F2_no_F1',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

sub test_chao1_F1_no_F2 {
    my $bd = shift->clone;

    #  need to ensure there are no doubles
    foreach my $label ($bd->get_labels) {
        if ($bd->get_label_sample_count(element => $label) == 2) {
            $bd->add_element (group => $focal_gp, label => $label, count => 20);
        }
    }

    my $results2 = {
        CHAO1_ESTIMATE   => 31.986014, CHAO1_SE         => 7.264041,
        CHAO1_F1_COUNT   => 4,         CHAO1_F2_COUNT   => 0,
        CHAO1_UNDETECTED => 5.986014,  CHAO1_VARIANCE   => 52.766285,
        CHAO1_CI_LOWER   => 26.927382, CHAO1_CI_UPPER  => 64.638212,
        CHAO1_META       => {
            CHAO_FORMULA     => 2,
            CI_FORMULA       => 13,
            VARIANCE_FORMULA => 7,
        },
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_chao1
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_chao1_F1_no_F2',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

sub test_chao1_no_F1_no_F2 {
    my $bd = shift->clone;

    #  need to ensure there are no uniques or doubles - make them all occur everywhere
    foreach my $label ($bd->get_labels) {
        my $sc = $bd->get_label_sample_count (element => $label);
        if ($sc == 1 || $sc == 2) {
            $bd->add_element (group => $focal_gp, label => $label, count => 20);
        }
    }

    my $results2 = {
        CHAO1_ESTIMATE   => 26,        CHAO1_SE         => 0.43544849,
        CHAO1_F1_COUNT   => 0,         CHAO1_F2_COUNT   => 0,
        CHAO1_UNDETECTED => 0,         CHAO1_VARIANCE   => 0.1896153894,
        CHAO1_CI_LOWER   => 26,        CHAO1_CI_UPPER   => 27.060214,
        CHAO1_META       => {
            CHAO_FORMULA     => 0,
            CI_FORMULA       => 14,
            VARIANCE_FORMULA => 8,
        },
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_chao1
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_chao1_no_F1_no_F2',
        tolerance          => $subtest_tolerance,
    );

    return;    
}
#  chao2 differs when q1 or q2 are zero
sub test_chao2_Q2_no_Q1 {
    my $bd = shift->clone;

    #  need to ensure there are no uniques - make them all occur everywhere
    foreach my $label ($bd->get_labels) {
        if ($bd->get_range(element => $label) == 1) {
            foreach my $group ($bd->get_groups) {
                $bd->add_element (group => $group, label => $label);
            }
        }
    }

    my $results2 = {
        CHAO2_ESTIMATE   => 26,        CHAO2_SE         => 0.629523,
        CHAO2_Q1_COUNT   => 0,         CHAO2_Q2_COUNT   => 8,
        CHAO2_UNDETECTED => 0,         CHAO2_VARIANCE   => 0.396299,
        CHAO2_CI_LOWER   => 26.030051, CHAO2_CI_UPPER   => 28.623668,
        CHAO2_META       => {
            CHAO_FORMULA     => 0,
            CI_FORMULA       => 14,
            VARIANCE_FORMULA => 12,
        },
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_chao2
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_chao2_Q2_no_Q1',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

sub test_chao2_Q1_no_Q2 {
    my $bd = shift->clone;

    #  need to ensure there are no uniques - make them all occur everywhere
    foreach my $label ($bd->get_labels) {
        if ($bd->get_range(element => $label) == 2) {
            foreach my $group ($bd->get_groups) {
                $bd->add_element (group => $group, label => $label);
            }
        }
    }
    
    my $results2 = {
        CHAO2_ESTIMATE   => 39.636364, CHAO2_SE         => 12.525204,
        CHAO2_Q1_COUNT   => 6,         CHAO2_Q2_COUNT   => 0,
        CHAO2_UNDETECTED => 13.636364, CHAO2_VARIANCE   => 156.880734,
        CHAO2_CI_LOWER   => 28.943958, CHAO2_CI_UPPER   => 89.163404,
        CHAO2_META       => {
            CHAO_FORMULA     => 4,
            CI_FORMULA       => 13,
            VARIANCE_FORMULA => 11,
        },
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_chao2
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_chao2_Q1_no_Q2',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

sub test_chao2_no_Q1_no_Q2 {
    my $bd = shift->clone;

    #  need to ensure there are no uniques or doubles - make them all occur everywhere
    foreach my $label ($bd->get_labels) {
        my $range = $bd->get_range(element => $label);
        if ($range == 1 || $range == 2) {
            foreach my $group ($bd->get_groups) {
                $bd->add_element (group => $group, label => $label);
            }
        }
    }
    
    my $results2 = {
        CHAO2_ESTIMATE   => 26,        CHAO2_SE         => 0.3696727,
        CHAO2_Q1_COUNT   => 0,         CHAO2_Q2_COUNT   => 0,
        CHAO2_UNDETECTED => 0,         CHAO2_VARIANCE   => 0.1366579,
        CHAO2_CI_LOWER   => 26,        CHAO2_CI_UPPER   => 26.910731,
        CHAO2_META       => {
            CHAO_FORMULA     => 0,
            CI_FORMULA       => 14,
            VARIANCE_FORMULA => 12,
        },
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_chao2
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_chao2_no_Q1_no_Q2',
        tolerance          => $subtest_tolerance,
    );

    return;    
}


sub test_ICE {
    my $bd = shift->clone;

    my $results2 = {
        ICE_ESTIMATE    => 29.606691,
        ICE_SE          => 3.130841,
        ICE_VARIANCE    => 9.8021639498,
        ICE_CI_LOWER    => 26.83023165,
        ICE_CI_UPPER    => 41.668186,
        ICE_UNDETECTED  => 3.606691,
        ICE_INFREQUENT_COUNT => 24,
        ICE_ESTIMATE_USED_CHAO => 0,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ice
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ICE base',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

sub test_ICE_no_singletons {
    my $bd = shift->clone;

    #  need to ensure there are no uniques - make them all occur everywhere
    foreach my $label ($bd->get_labels) {
        if ($bd->get_range(element => $label) == 1) {
            foreach my $group ($bd->get_groups) {
                $bd->add_element (group => $group, label => $label);
            }
        }
    }

    my $results2 = {
        ICE_ESTIMATE    => 26,
        ICE_SE          => 0.6295226,
        ICE_VARIANCE    => 0.3962987,
        ICE_CI_LOWER    => 26.0300513322865,
        ICE_CI_UPPER    => 28.623668086166,
        ICE_UNDETECTED  => 0,
        ICE_INFREQUENT_COUNT => 18,
        ICE_ESTIMATE_USED_CHAO => 1,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ice
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ICE_no_singletons',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

sub test_ICE_one_group {
    my $bd = shift->clone;

    my $results2 = {
        ICE_ESTIMATE    => 8,
        ICE_SE          => undef,
        ICE_VARIANCE    => undef,
        ICE_CI_LOWER    => undef,
        ICE_CI_UPPER    => undef,
        ICE_UNDETECTED  => undef,
        ICE_INFREQUENT_COUNT => 8,
        ICE_ESTIMATE_USED_CHAO => 0,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ice
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => [],
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ICE_one_group',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

#  should match the chao2 estimate in this case
sub test_ICE_no_infrequents {
    my $bd = shift->clone;

    foreach my $label ($bd->get_labels) {
        my $range = $bd->get_range(element => $label);
        if ($range && $range <= 10) {
            foreach my $group ($bd->get_groups) {
                $bd->add_element (group => $group, label => $label);
            }
        }
    }

    my $results2 = {
        ICE_ESTIMATE    => 26,
        ICE_SE          => 0.020789,
        ICE_VARIANCE    => 0.000432,
        ICE_CI_LOWER    => 26,
        ICE_CI_UPPER    => 26.04118,
        ICE_UNDETECTED  => 0,
        ICE_INFREQUENT_COUNT => 0,
        ICE_ESTIMATE_USED_CHAO => 1,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ice
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ICE_no_infrequents',
        tolerance          => $subtest_tolerance,
    );

    return;    
}


sub test_ACE {
    my $bd = shift->clone;

    my $results2 = {
        ACE_ESTIMATE    => 28.459957,
        ACE_SE       => 2.457292,
        ACE_VARIANCE => 6.03828211669945,
        ACE_CI_LOWER => 26.4817368287846,
        ACE_CI_UPPER => 38.561607,
        ACE_UNDETECTED => 2.459957,
        ACE_INFREQUENT_COUNT => 19,
        ACE_ESTIMATE_USED_CHAO => 0,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ace
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ACE base',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

sub test_ACE_no_rares {
    my $bd = shift->clone;

    #  need to ensure there are no rares
    foreach my $label ($bd->get_labels) {
        my $count = $bd->get_label_sample_count(element => $label);
        if ($count && $count <= 10) {
            $bd->add_element (group => $focal_gp, label => $label, count => 20);
        }
    }

    my $results2 = {
        ACE_ESTIMATE    => 26,
        ACE_SE          => 0.002129,
        ACE_VARIANCE    => 5e-006,
        ACE_CI_LOWER    => 26,
        ACE_CI_UPPER    => 26.004177,
        ACE_UNDETECTED  => 0,
        ACE_INFREQUENT_COUNT => 0,
        ACE_ESTIMATE_USED_CHAO => 1,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ace
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ACE_no_rares',
        tolerance          => $subtest_tolerance,
    );

    return;
}

sub test_ACE_no_singletons {
    my $bd = shift->clone;

    #  need to ensure there are no singletons
    foreach my $label ($bd->get_labels) {
        my $count = $bd->get_label_sample_count(element => $label);
        if ($count == 1) {
            $bd->add_element (group => $focal_gp, label => $label, count => 20);
        }
    }

    my $results2 = {
        ACE_ESTIMATE    => 26,
        ACE_SE       => 0.874999,
        ACE_VARIANCE => 0.765623,
        ACE_CI_LOWER => 26,
        ACE_CI_UPPER => 28.680536,
        ACE_UNDETECTED => 0,
        ACE_INFREQUENT_COUNT => 15,
        ACE_ESTIMATE_USED_CHAO => 1,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ace
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ACE_no_singletons',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

sub test_ACE_only_singletons {
    my $bd = shift->clone;

    #  need to ensure there are only singletons in $focal_gp
    foreach my $label ($bd->get_labels_in_group(group => $focal_gp)) {
        $bd->delete_sub_element (group => $focal_gp, label => $label);
        $bd->add_element (group => $focal_gp, label => $label, count => 1);
    }

    my $results2 = {
        ACE_ESTIMATE => 8,
        ACE_SE       => undef,
        ACE_VARIANCE => undef,
        ACE_CI_LOWER => undef,
        ACE_CI_UPPER => undef,
        ACE_UNDETECTED => undef,
        ACE_INFREQUENT_COUNT => 8,
        ACE_ESTIMATE_USED_CHAO => 0,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ace
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => [],
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ACE_only_singletons',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

sub test_ACE_all_rares_are_singletons {
    my $bd = shift->clone;

    foreach my $label ($bd->get_labels) {
        my $count = $bd->get_label_sample_count(element => $label);
        if ($count > 1 && $count <= 10) {
            $bd->add_element (group => $focal_gp, label => $label, count => 20);
        }
    }

    my $results2 = {
        ACE_ESTIMATE    => 31.990461,
        ACE_SE          => 7.26915,
        ACE_VARIANCE    => 52.840542,
        ACE_CI_LOWER    => 26.928115,
        ACE_CI_UPPER    => 64.665044,
        ACE_UNDETECTED  => 5.990461,
        ACE_INFREQUENT_COUNT => 4,
        ACE_ESTIMATE_USED_CHAO => 1,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ace
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ACE_all_rares_are_singletons',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

sub test_ACE_empty_group {
    my $bd = shift->clone;

    #  empty $focal_gp
    foreach my $label ($bd->get_labels_in_group(group => $focal_gp)) {
        $bd->delete_sub_element (group => $focal_gp, label => $label);
    }
    $bd->add_element (group => $focal_gp, count => 0);

    my $results2 = {
        ACE_ESTIMATE => 0,
        ACE_SE       => undef,
        ACE_VARIANCE => undef,
        ACE_CI_LOWER => undef,
        ACE_CI_UPPER => undef,
        ACE_UNDETECTED => undef,
        ACE_INFREQUENT_COUNT => 0,
        ACE_ESTIMATE_USED_CHAO => 0,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ace
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => [],
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ACE_empty_group',
        tolerance          => $subtest_tolerance,
    );

    return;    
}

sub test_ICE_all_groups_empty {
    my $bd = shift->clone;

    foreach my $group ($bd->get_groups ) {
        $bd->delete_group (group => $group);
        $bd->add_element (group => $group, count => 0);
    }

    my $results2 = {
        ICE_ESTIMATE => 0,
        ICE_SE       => undef,
        ICE_VARIANCE => undef,
        ICE_CI_LOWER => undef,
        ICE_CI_UPPER => undef,
        ICE_UNDETECTED => undef,
        ICE_INFREQUENT_COUNT => 0,
        EL_COUNT_NONEMPTY_ALL => 0,
        EL_COUNT_NONEMPTY_SET1 => 0,
        EL_COUNT_NONEMPTY_SET2 => 0,
        ICE_ESTIMATE_USED_CHAO => 0,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ice
            calc_nonempty_elements_used
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ICE_all_groups_empty',
        tolerance          => $subtest_tolerance,
    );

    return;    
}


sub test_ICE_additional_empty_group {
    my $bd = shift->clone;

    my $extra_gp_name = 'extra empty group';
    $bd->add_element (group => $extra_gp_name, count => 0);

    my $results2 = {
        ICE_ESTIMATE    => 29.606691,
        ICE_SE          => 3.130841,
        ICE_VARIANCE    => 9.8021639498,
        ICE_CI_LOWER    => 26.83023165,
        ICE_CI_UPPER    => 41.668186,
        ICE_UNDETECTED  => 3.606691,
        ICE_INFREQUENT_COUNT => 24,
        EL_COUNT_NONEMPTY_ALL => 11,
        EL_COUNT_NONEMPTY_SET1 => 1,
        EL_COUNT_NONEMPTY_SET2 => 10,
        ICE_ESTIMATE_USED_CHAO => 0,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_ice
            calc_nonempty_elements_used
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => [$focal_gp],
        element_list2      => [@nbr_set2, $extra_gp_name],
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_ICE_additional_empty_group',
        tolerance          => $subtest_tolerance,
    );

    return;    
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


#  check we match the results of the R entropart library
sub test_hurlbert_matches_entropart {
    my $indices = Biodiverse::Indices->new;
    my @vals = qw/38 68 90 59 27 74 30 55 55 49 57 63 35 12 22 43 73 91 87  9 72  8 62 18 80 23/;
    my %data;
    @data{'a'..'z'} = @vals;

    my $results = $indices->calc_hurlbert_es(
        label_hash_all => \%data,
    );
    my $got = $results->{HURLBERT_ES};

    my %exp = (
            5    => 4.54802350159,
            10   => 8.12951896478,
            20   => 13.2371759674,
            50   => 20.2756085056,
            100  => 23.6287536932,
            200  => 25.267765305,
            500  => 25.9642304379,
            1000 => 25.9999908099,
    );

    #  a little precision adjustment since tests are exact
    foreach my $val (values %{$got}) {
        $val = sprintf "%.10f", $val;
    }
    foreach my $val (values %exp) {
        $val = sprintf "%.10f", $val;
    }

    is $got, \%exp, "Hurlbert matches entropart";
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
{   ACE_CI_LOWER           => '26.4817368225888',
    ACE_CI_UPPER           => '38.5616065911166',
    ACE_ESTIMATE           => '28.4599570008062',
    ACE_ESTIMATE_USED_CHAO => 0,
    ACE_INFREQUENT_COUNT   => 19,
    ACE_SE                 => '2.4572916222336',
    ACE_UNDETECTED         => '2.45995700080623',
    ACE_VARIANCE           => '6.03828211669945',
    CHAO1_CI_LOWER         => '26.2163119159043',
    CHAO1_CI_UPPER         => '37.7629272999573',
    CHAO1_ESTIMATE         => '27.5951367781155',
    CHAO1_F1_COUNT         => 4,
    CHAO1_F2_COUNT         => 5,
    CHAO1_META             => {
        CHAO_FORMULA     => 2,
        CI_FORMULA       => 13,
        VARIANCE_FORMULA => 6
    },
    CHAO1_SE         => '2.15603580378238',
    CHAO1_UNDETECTED => '1.5951367781155',
    CHAO1_VARIANCE   => '4.64849038719155',
    CHAO2_CI_LOWER   => '26.3450800735193',
    CHAO2_CI_UPPER   => '38.1243868266594',
    CHAO2_ESTIMATE   => '28.0454545454545',
    CHAO2_META       => {
        CHAO_FORMULA     => 4,
        CI_FORMULA       => 13,
        VARIANCE_FORMULA => 10
    },
    CHAO2_Q1_COUNT   => 6,
    CHAO2_Q2_COUNT   => 8,
    CHAO2_SE         => '2.31466979955927',
    CHAO2_UNDETECTED => '2.04545454545455',
    CHAO2_VARIANCE   => '5.35769628099174',
    HURLBERT_ES      => {
        10  => '6.08673309367266',
        100 => '18.8200796757971',
        20  => '9.06575680090329',
        200 => '23.4253639706145',
        5   => '3.82996487293125',
        50  => '14.2043237650115'
    },
    ICE_CI_LOWER           => '26.8302316060467',
    ICE_CI_UPPER           => '41.6681855466098',
    ICE_ESTIMATE           => '29.6066913993576',
    ICE_ESTIMATE_USED_CHAO => 0,
    ICE_INFREQUENT_COUNT   => 24,
    ICE_SE                 => '3.13084077363682',
    ICE_UNDETECTED         => '3.60669139935755',
    ICE_VARIANCE           => '9.80216394986679'
}


@@ RESULTS_1_NBR_LISTS
{   ACE_CI_LOWER           => '8.5996888836216',
    ACE_CI_UPPER           => '30.9753940794084',
    ACE_ESTIMATE           => '11.7118847539016',
    ACE_ESTIMATE_USED_CHAO => 0,
    ACE_INFREQUENT_COUNT   => 8,
    ACE_SE                 => '4.35262370708667',
    ACE_UNDETECTED         => '3.71188475390156',
    ACE_VARIANCE           => '18.9453331354929',
    CHAO1_CI_LOWER         => '8.93050951620995',
    CHAO1_CI_UPPER         => '69.3496356121155',
    CHAO1_ESTIMATE         => '15.5555555555556',
    CHAO1_F1_COUNT         => 4,
    CHAO1_F2_COUNT         => 1,
    CHAO1_META             => {
        CHAO_FORMULA     => 2,
        CI_FORMULA       => 13,
        VARIANCE_FORMULA => 6
    },
    CHAO1_SE         => '11.0330591887168',
    CHAO1_UNDETECTED => '7.55555555555556',
    CHAO1_VARIANCE   => '121.728395061728',
    CHAO2_CI_LOWER   => undef,
    CHAO2_CI_UPPER   => undef,
    CHAO2_ESTIMATE   => 8,
    CHAO2_META       => {
        CHAO_FORMULA     => 4,
        CI_FORMULA       => 13,
        VARIANCE_FORMULA => 11
    },
    CHAO2_Q1_COUNT   => 8,
    CHAO2_Q2_COUNT   => 0,
    CHAO2_SE         => '0',
    CHAO2_UNDETECTED => 0,
    CHAO2_VARIANCE   => 0,
    HURLBERT_ES      => {
        10 => '5.97058823529411',
        5  => '3.90032679738561'
    },
    ICE_CI_LOWER           => undef,
    ICE_CI_UPPER           => undef,
    ICE_ESTIMATE           => 8,
    ICE_ESTIMATE_USED_CHAO => 0,
    ICE_INFREQUENT_COUNT   => 8,
    ICE_SE                 => undef,
    ICE_UNDETECTED         => undef,
    ICE_VARIANCE           => undef
}


