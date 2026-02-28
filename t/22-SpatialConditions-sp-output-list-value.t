use strict;
use warnings;
use Carp;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;

use rlib;
use Test2::V0;

local $| = 1;

use Biodiverse::TestHelpers qw {:spatial_conditions};
use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;


exit main( @ARGV );

sub main {
    my @args  = @_;

    test_sp_get_spatial_output_list_value();
    test_sp_richness_greater_than();
    test_sp_redundancy_greater_than();
    
    done_testing();
    return 0;
}


sub test_sp_get_spatial_output_list_value {
    use experimental qw /for_list/;
    my $bd = Biodiverse::BaseData->new (
        NAME         => 'test_sp_get_spatial_output_list_value',
        CELL_SIZES   => [1,  1  ],
        CELL_ORIGINS => [0.5,0.5],
    );
    my %all_gps;
    my $label = 'a';
    foreach my $i (1..3) {
        foreach my $j (1 .. $i) {
            my $gp = "$i:$j";
            $bd->add_element (label => $label, group => $gp);
            $all_gps{$gp}++;
        }
        $label++;
    }

    # each col is the same
    my %exp_base = (
        '3:' => {
            ENDW_CWE     => 1 / 3, ENDW_RICHNESS => 1,
            ENDW_SINGLE  => 1 / 3, ENDW_WE => 1 / 3,
        },
        '2:' => {
            ENDW_CWE     => 1 / 2, ENDW_RICHNESS => 1,
            ENDW_SINGLE  => 1 / 2, ENDW_WE => 0.5,
        },
        '1:' => {
            ENDW_CWE     => 1, ENDW_RICHNESS => 1,
            ENDW_SINGLE  => 1, ENDW_WE => 1,
        },
    );
    my %base_exp;
    for my ($i, $n) (1 => 1, 2 => 2, 3 => 3) {
        my $key = "${i}:";
        @base_exp{map {; $key . $_} (1 .. $n) } = ($exp_base{$key}) x $n;
    }

    my $sp_base_vals = $bd->add_spatial_output(name => 'get_vals_from');
    $sp_base_vals->run_analysis(
        calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
        spatial_conditions => [ 'sp_self_only()' ],
    );

    {
        my %got;
        foreach my $group ($bd->get_groups) {
            my $list_ref = $sp_base_vals->get_list_ref(element => $group, list => 'SPATIAL_RESULTS');
            $got{$group} = $list_ref;
        }
        is \%got, \%base_exp, 'base calcs as expected';
    }

    my %to_be_repeated = (
        '1:1' => 1,
        '2:1' => 1,
        '2:2' => 1,
    );
    my %exp = map {$_ => \%to_be_repeated} keys %base_exp;

    my $check;
    {
        $check++;
        my $sp = $bd->add_spatial_output(name => "test_sp_get_spatial_output_list_value${check}");
        my $cond=<<~'EOC'
            sp_get_spatial_output_list_value (
                output => "get_vals_from",
                list => "SPATIAL_RESULTS",
                index => "ENDW_WE"
            ) > 0.4
        EOC
        ;
        $sp->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ $cond ],
        );

        my %got;
        foreach my $group ($bd->get_groups) {
            my $list_ref = $sp->get_list_ref(element => $group, list => 'EL_LIST_SET1');
            $got{$group} = $list_ref;
        }

        is \%got, \%exp, 'always_same nbrs, SPATIAL_RESULTS list, END_WE>0.4';
    }

    {
        $check++;
        my $sp2 = $bd->add_spatial_output(name => "test_sp_get_spatial_output_list_value${check}");
        my $cond =<<~'EOC'
            sp_get_spatial_output_list_value (output => "get_vals_from", index => "ENDW_WE") > 0.4
        EOC
        ;
        $sp2->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ $cond ],
        );
        my %got;
        foreach my $group ($bd->get_groups) {
            my $list_ref = $sp2->get_list_ref(element => $group, list => 'EL_LIST_SET1');
            $got{$group} = $list_ref;
        }
        is \%got, \%exp, 'always_same nbrs, default list, END_WE>0.4';
    }

    {
        #  all results should be the ame when element is passed
        $check++;
        my $sp = $bd->add_spatial_output(name => "test_sp_get_spatial_output_list_value${check}");
        my $cond =<<~'EOC'
            sp_get_spatial_output_list_value (
                output  => "get_vals_from",
                list    => "SPATIAL_RESULTS",
                index   => "ENDW_WE",
                element => "1:1",
            ) > 0.4
        EOC
        ;

        $sp->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ $cond ],
        );
        my %got;
        my %exp;
        my $expected_subhash = {
            ENDW_CWE      => 1,
            ENDW_RICHNESS => 3,
            ENDW_SINGLE   => 11 / 6, #  1.83333...
            ENDW_WE       => 3,
            RECYCLED_SET  => 1,
        };
        foreach my $group ($bd->get_groups) {
            my $list_ref = $sp->get_list_ref(element => $group, list => 'SPATIAL_RESULTS');
            $got{$group} = $list_ref;
            $exp{$group} = $expected_subhash;
        }
        is(\%got, \%exp, 'got expected SPATIAL_RESULTS list when arg element is passed');

    }

    {
        $check++;
        #  should work but have empty results
        my $sp = $bd->add_spatial_output(name => "test_sp_get_spatial_output_list_value${check}");
        my $cond =<<~'EOC'
            sp_get_spatial_output_list_value (
                output => "get_vals_from",
                list   => "SPATIAL_RESULTS",
                index  => "NONEXISTENT",
                no_error_if_no_index => 1,
            )
            EOC
        ;

        $sp->run_analysis(
            calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
            spatial_conditions => [ $cond ],
        );
        my $to_be_repeated = {
            ENDW_CWE    => undef, ENDW_RICHNESS => 0,
            ENDW_SINGLE => undef, ENDW_WE => undef,
        };
        my %exp = map {$_ => $to_be_repeated} keys %base_exp;
        my %got;
        foreach my $group ($bd->get_groups) {
            my $list_ref = $sp->get_list_ref(element => $group, list => 'SPATIAL_RESULTS');
            $got{$group} = $list_ref;
        }
        is(\%got, \%exp, 'got expected SPATIAL_RESULTS list when no_error_if_no_index is true');
    }

    {
        $check++;
        my $sp = $bd->add_spatial_output(name => "test_sp_get_spatial_output_list_value${check}");
        my $cond =<<~'EOC'
            sp_get_spatial_output_list_value (
                output => "get_vals_from",
                list   => "SPATIAL_RESULTS",
                index  => "NONEXISTENT"
            )
        EOC
        ;
        ok(dies {
            $sp->run_analysis(
                calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
                spatial_conditions => [ $cond ],
            )},
            'error thrown when non-existent index accessed'
        ) or note $@;
    }

    {
        $check++;
        my $sp = $bd->add_spatial_output(name => "test_sp_get_spatial_output_list_value${check}");
        my $cond =<<~'EOC'
            sp_get_spatial_output_list_value (
                output => "snerble",
                list   => "SPATIAL_RESULTS",
                index  => "ENDW_WE"
            )
        EOC
        ;
        ok(dies {
            $sp->run_analysis(
                calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
                spatial_conditions => [ $cond ],
            )},
            'error thrown when non-existent output accessed'
        );
    }

    {
        $check++;
        $sp_base_vals->add_to_hash_list(
            element => '5:5',
            list    => 'extra_list',
            key1    => 1,
        );
        my $sp_to_test5 = $bd->add_spatial_output(name => "test_sp_get_spatial_output_list_value${check}");
        ok(lives {
            $sp_to_test5->run_analysis(
                calculations       => [ 'calc_endemism_whole', 'calc_element_lists_used' ],
                spatial_conditions => [ 'sp_get_spatial_output_list_value (output => "get_vals_from", list => "extra_list", index => "key1")' ],
            )},
            'no error thrown when index in subset of elements'
        );
    }
    # $bd->save;
}


sub test_sp_richness_greater_than {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test_sp_richness_greater_than',
        CELL_SIZES => [1,1],
    );
    my %all_gps;
    my @labels = 'a' .. 'f';
    #  richness decreases to the right
    foreach my $i (1..5) {
        foreach my $j (1..2) {
            my $gp = "$i:$j";
            foreach my $label (@labels[0..$i]) {
                $bd->add_element (label => $label, group => $gp);
                $all_gps{$gp}++;
            }
        }
    }

    my $sp_to_test1 = $bd->add_spatial_output (name => 'defq');
    $sp_to_test1->run_analysis (
        calculations       => ['calc_element_lists_used'],
        spatial_conditions => ['sp_self_only()'],
        definition_query   => 'sp_richness_greater_than (threshold => 3)',
    );
    my $sp_to_test2 = $bd->add_spatial_output (name => 'sp_cond');
    $sp_to_test2->run_analysis (
        calculations       => ['calc_element_lists_used'],
        spatial_conditions => ['sp_richness_greater_than (threshold => 3)'],
    );

    #  now the tests
    my @expected;
    my $failed_defq = $sp_to_test1->get_groups_that_failed_def_query;
    @expected = qw /1:1 1:2 2:1 2:2/;
    is ([sort keys %$failed_defq], \@expected, 'got expected defq fails');

    my $passed_defq = $sp_to_test1->get_groups_that_pass_def_query;
    @expected = qw /3:1 3:2 4:1 4:2 5:1 5:2/;
    is ([sort keys %$passed_defq], \@expected, 'got expected defq passes');
    

    #  all neighbour sets should be the same    
    my $list_ref = $sp_to_test2->get_list_ref (
        element => '5:1',
        list    => 'EL_LIST_SET1',
    );
    is ([sort keys %$list_ref], \@expected, 'got expected EL_LIST_SET1 list');

    my $sp_to_test3 = $bd->add_spatial_output (name => 'sp_cond_to_fail_no_threshold');
    ok (dies {
        $sp_to_test3->run_analysis (
            calculations       => ['calc_element_lists_used'],
            spatial_conditions => ['sp_richness_greater_than ()'],
        )},
        'error thrown when no threshold arg passed'
    );
}


sub test_sp_redundancy_greater_than {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test_sp_richness_greater_than',
        CELL_SIZES => [1,1],
    );
    my %all_gps;
    my @labels = 'a' .. 'f';
    #  richness decreases to the right
    foreach my $i (1..5) {
        foreach my $j (1..2) {
            my $gp = "$i:$j";
            foreach my $label (@labels[0..$i]) {
                $bd->add_element (
                    label => $label,
                    group => $gp,
                    count => $i,
                );
                $all_gps{$gp}++;
            }
        }
    }
    
    #foreach my $gp (sort $bd->get_groups) {
    #    diag "$gp " . $bd->get_redundancy_aa($gp);
    #}

    my $sp_to_test1 = $bd->add_spatial_output (name => 'defq');
    $sp_to_test1->run_analysis (
        calculations       => ['calc_element_lists_used'],
        spatial_conditions => ['sp_self_only()'],
        definition_query   => 'sp_redundancy_greater_than (threshold => 0.5)',
    );
    my $sp_to_test2 = $bd->add_spatial_output (name => 'sp_cond');
    $sp_to_test2->run_analysis (
        calculations       => ['calc_element_lists_used'],
        spatial_conditions => ['sp_redundancy_greater_than (threshold => 0.5)'],
    );

    #  now the tests
    my @expected;
    my $failed_defq = $sp_to_test1->get_groups_that_failed_def_query;
    @expected = qw /1:1 1:2 2:1 2:2/;
    is ([sort keys %$failed_defq], \@expected, 'got expected defq fails');

    my $passed_defq = $sp_to_test1->get_groups_that_pass_def_query;
    @expected = qw /3:1 3:2 4:1 4:2 5:1 5:2/;
    is ([sort keys %$passed_defq], \@expected, 'got expected defq passes');
    

    #  all neighbour sets should be the same    
    my $list_ref = $sp_to_test2->get_list_ref (
        element => '5:1',
        list    => 'EL_LIST_SET1',
    );
    is ([sort keys %$list_ref], \@expected, 'got expected EL_LIST_SET1 list');

    my $sp_to_test3 = $bd->add_spatial_output (name => 'sp_cond_to_fail_no_threshold');
    ok (dies {
        $sp_to_test3->run_analysis (
            calculations       => ['calc_element_lists_used'],
            spatial_conditions => ['sp_redundancy_greater_than ()'],
        )},
        'error thrown when no threshold arg passed'
    );
}
