#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;
use Test::Most;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
};

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

sub test_main {
    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_nonempty_elements_used
            calc_elements_used
            calc_element_lists_used
            calc_abc_counts
            calc_d
            calc_local_range_lists
            calc_local_range_stats
            calc_redundancy
            calc_richness
            calc_local_sample_count_lists
            calc_local_sample_count_stats
            calc_label_count_quantile_position
            calc_local_sample_count_quantiles
        /],
        calc_topic_to_test => 'Lists and Counts',
        sort_array_lists   => 1,
        #generate_result_sets => 1,
    );
}


sub test_el_counts_with_empty_groups {
    my $bd = get_basedata_object_from_site_data (CELL_SIZES => [200000, 200000]);

    my $gp_count = $bd->get_group_count;
    my @nbr_set2 = $bd->get_groups;

    #  add four empty groups
    my $empty_gp_count = 4;
    my @nbr_set1;
    for my $i (1..$empty_gp_count) {
        #  should really insert using coords
        my $coord = -$i * 200000 + 100000;
        my $gp_name = "$coord:$coord";
        $bd->add_element (group => $gp_name);
        push @nbr_set1, $gp_name;
    }

    my $results2 = {
        EL_COUNT_NONEMPTY_ALL  => $gp_count,
        EL_COUNT_NONEMPTY_SET1 => 0,
        EL_COUNT_NONEMPTY_SET2 => $gp_count,
        EL_COUNT_ALL  => $gp_count + $empty_gp_count,
        EL_COUNT_SET1 => $empty_gp_count,
        EL_COUNT_SET2 => $gp_count,
    };

    my %expected_results = (2 => $results2);

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_nonempty_elements_used
            calc_elements_used
        /],
        sort_array_lists   => 1,
        basedata_ref       => $bd,
        element_list1      => \@nbr_set1,
        element_list2      => \@nbr_set2,
        expected_results   => \%expected_results,
        skip_nbr_counts    => {1 => 1},
        descr_suffix       => 'test_el_counts_with_empty_groups',
    );

    return;
}

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   ABC2_LABELS_ALL => {
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
    ABC2_LABELS_SET1 => {
        'Genus:sp20' => 1,
        'Genus:sp26' => 1
    },
    ABC2_LABELS_SET2 => {
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
    ABC2_MEAN_ALL   => '1.57142857142857',
    ABC2_MEAN_SET1  => '1',
    ABC2_MEAN_SET2  => '1.42857142857143',
    ABC2_SD_ALL     => '0.85163062725264',
    ABC2_SD_SET1    => '0',
    ABC2_SD_SET2    => '0.646206172658864',
    ABC3_LABELS_ALL => {
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
    ABC3_LABELS_SET1 => {
        'Genus:sp20' => 4,
        'Genus:sp26' => 2
    },
    ABC3_LABELS_SET2 => {
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
    ABC3_MEAN_ALL      => '5.92857142857143',
    ABC3_MEAN_SET1     => '3',
    ABC3_MEAN_SET2     => '5.5',
    ABC3_QUANTILES_ALL => {
        Q000 => 1,
        Q005 => 1,
        Q010 => 1,
        Q015 => 1,
        Q020 => 1,
        Q025 => 1,
        Q030 => 2,
        Q035 => 2,
        Q040 => 2,
        Q045 => 5,
        Q050 => 6,
        Q055 => 6,
        Q060 => 8,
        Q065 => 8,
        Q070 => 8,
        Q075 => 9,
        Q080 => 9,
        Q085 => 11,
        Q090 => 12,
        Q095 => 12,
        Q100 => 16
    },
    ABC3_QUANTILES_SET1 => {
        Q000 => 2,
        Q005 => 2,
        Q010 => 2,
        Q015 => 2,
        Q020 => 2,
        Q025 => 2,
        Q030 => 2,
        Q035 => 2,
        Q040 => 2,
        Q045 => 2,
        Q050 => 4,
        Q055 => 4,
        Q060 => 4,
        Q065 => 4,
        Q070 => 4,
        Q075 => 4,
        Q080 => 4,
        Q085 => 4,
        Q090 => 4,
        Q095 => 4,
        Q100 => 4
    },
    ABC3_QUANTILES_SET2 => {
        Q000 => 1,
        Q005 => 1,
        Q010 => 1,
        Q015 => 1,
        Q020 => 1,
        Q025 => 1,
        Q030 => 2,
        Q035 => 2,
        Q040 => 2,
        Q045 => 4,
        Q050 => 5,
        Q055 => 5,
        Q060 => 8,
        Q065 => 8,
        Q070 => 8,
        Q075 => 8,
        Q080 => 8,
        Q085 => 9,
        Q090 => 11,
        Q095 => 11,
        Q100 => 16
    },
    ABC3_SD_ALL   => '4.89056054226736',
    ABC3_SD_SET1  => '1.4142135623731',
    ABC3_SD_SET2  => '4.63680924774785',
    ABC3_SUM_ALL  => 83,
    ABC3_SUM_SET1 => 6,
    ABC3_SUM_SET2 => 77,
    ABC_A         => 2,
    ABC_ABC       => 14,
    ABC_B         => 0,
    ABC_C         => 12,
    ABC_D         => 17,
    EL_COUNT_ALL  => 5,
    EL_COUNT_SET1 => 1,
    EL_COUNT_SET2 => 4,
    EL_COUNT_NONEMPTY_ALL  => 5,
    EL_COUNT_NONEMPTY_SET1 => 1,
    EL_COUNT_NONEMPTY_SET2 => 4,
    EL_LIST_ALL   => [
        '3250000:850000', '3350000:850000',
        '3350000:750000', '3350000:950000',
        '3450000:850000'
    ],
    EL_LIST_SET1 => { '3350000:850000' => 1 },
    EL_LIST_SET2 => {
        '3250000:850000' => 1,
        '3350000:750000' => 1,
        '3350000:950000' => 1,
        '3450000:850000' => 1
    },
    LABEL_COUNT_RANK_PCT => {
        'Genus:sp1'  => '0',
        'Genus:sp10' => '0',
        'Genus:sp11' => '0',
        'Genus:sp12' => '0',
        'Genus:sp15' => '0',
        'Genus:sp20' => '75',
        'Genus:sp23' => '0',
        'Genus:sp24' => '0',
        'Genus:sp25' => '0',
        'Genus:sp26' => '75',
        'Genus:sp27' => '0',
        'Genus:sp29' => '0',
        'Genus:sp30' => '0',
        'Genus:sp5'  => '0'
    },
    REDUNDANCY_ALL  => '0.831325301204819',
    REDUNDANCY_SET1 => '0.666666666666667',
    REDUNDANCY_SET2 => '0.818181818181818',
    RICHNESS_ALL    => 14,
    RICHNESS_SET1   => 2,
    RICHNESS_SET2   => 14
}


@@ RESULTS_1_NBR_LISTS
{   ABC2_LABELS_SET1 => {
        'Genus:sp20' => 1,
        'Genus:sp26' => 1
    },
    ABC2_MEAN_ALL    => '1',
    ABC2_MEAN_SET1   => '1',
    ABC2_SD_SET1     => '0',
    ABC3_LABELS_SET1 => {
        'Genus:sp20' => 4,
        'Genus:sp26' => 2
    },
    ABC3_MEAN_SET1      => '3',
    ABC3_QUANTILES_SET1 => {
        Q000 => 2,
        Q005 => 2,
        Q010 => 2,
        Q015 => 2,
        Q020 => 2,
        Q025 => 2,
        Q030 => 2,
        Q035 => 2,
        Q040 => 2,
        Q045 => 2,
        Q050 => 4,
        Q055 => 4,
        Q060 => 4,
        Q065 => 4,
        Q070 => 4,
        Q075 => 4,
        Q080 => 4,
        Q085 => 4,
        Q090 => 4,
        Q095 => 4,
        Q100 => 4
    },
    ABC3_SD_SET1         => '1.4142135623731',
    ABC3_SUM_SET1        => 6,
    ABC_D                => 29,
    EL_COUNT_SET1        => 1,
    EL_COUNT_ALL         => 1,
    EL_COUNT_NONEMPTY_ALL  => 1,
    EL_COUNT_NONEMPTY_SET1 => 1,
    EL_LIST_SET1         => { '3350000:850000' => 1 },
    LABEL_COUNT_RANK_PCT => {
        'Genus:sp20' => undef,
        'Genus:sp26' => undef
    },
    REDUNDANCY_ALL  => '0.666666666666667',
    REDUNDANCY_SET1 => '0.666666666666667',
    RICHNESS_ALL    => 2,
    RICHNESS_SET1   => 2
}


