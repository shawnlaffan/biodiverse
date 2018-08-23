#  test the spatial outputs


### need to test for basedatas with empty groups

use 5.016;
use strict;
use warnings;
use Carp;

use FindBin qw/$Bin/;
use Test::Lib;
use rlib;

use Test::More;

use Scalar::Util qw /refaddr/;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Test::More;
#use Test::Exception;

use Biodiverse::TestHelpers qw /:basedata/;
use Biodiverse::Spatial;
use Biodiverse::SpatialConditions;

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


#  check the def queries
sub test_def_queries {
    my $cell_sizes   = [100000, 100000];
    my $bd = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);

    my %options = (
        basedata_ref => $bd,
        calculations => [qw/calc_elements_used calc_element_lists_used/],
    );

    my $group_count = $bd->get_group_count;

    my %def_query_hash = (
        ''                => {
            count => 0,  #  def query won't be used
            list  => [],
        },
        'sp_select_all()' => {
            count => $group_count,  #  def query won't be used
            list  => [$bd->get_groups],
        },
        '$y > 1550000'    => {
            count => 30,  #  def query won't be used
            list  => [get_expected_list_for_defq_y_gt_1550000()],
        },
    );
    

    foreach my $def_query (keys %def_query_hash) {
        my $def_query_text = $def_query || 'undef';
        my $expected = $def_query_hash{$def_query};
        my $count_expected_to_pass = $expected->{count};
        my @expected_element_list  = sort @{$expected->{list}};

        $options{definition_query} = $def_query;

        my $sp = run_analysis (%options);

        my $passed_defq = $sp->get_groups_that_pass_def_query;

        is (
            scalar keys %$passed_defq,
            $count_expected_to_pass,
            "Correct number of groups passed $def_query_text",
        );
        
        my @got_element_list = sort keys %$passed_defq;
        
        is_deeply (
            \@expected_element_list,
            \@got_element_list,
            "Got the same elements for $def_query_text",
        );
        
        #  cleanup
        $bd->delete_output(output => $sp);
    }
    
}



# copied from 22-SpatialConditions2.t, was called test_case given a
# spatial condition, basedata, element and expected neighbours, checks
# whether BaseData::get_neighbours with the spatial condition produces
# the expected result.
sub check_neighbours_are_as_expected {
    my %args = @_;

    my $bd            = $args{bd};       # basedata object
    my $cond          = $args{cond};     # spatial condition as string
    my $element       = $args{element};  # centre element
    my $expected      = $args{expected}; # array of expected cells as strings
    my $print_results = $args{print_results} || 0;

    my $spatial_params = Biodiverse::SpatialConditions->new (
        basedata_ref => $bd,
        conditions   => $cond,
    );

    my $neighbours = eval {
        $bd->get_neighbours (
            element        => $element,
            spatial_params => $spatial_params,
        );
    };

    if ($print_results) {
        use Data::Dumper;
        $Data::Dumper::Purity   = 1;
        $Data::Dumper::Terse    = 1;
        $Data::Dumper::Sortkeys = 1;
        print join "\n", sort keys %$neighbours;
        print "\n";
    }

    croak $EVAL_ERROR if $EVAL_ERROR;

    compare_arr_vals (
        arr_got => [keys %$neighbours],
        arr_exp => $expected,
    );
}



# test basic sp_spatial_output_passed_defq case: looking at the result
# of a def_query for a different spatial output in the same basedata.
sub test_sp_passed_defq_different_sp {
    my $cell_sizes = [100000, 100000];
    my $bd1 = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
    $bd1->build_spatial_index (resolutions => $cell_sizes);
    
    
    # run an analysis with simple def_query
    my $sp1 = $bd1->add_spatial_output(name => 'sp1');
    $sp1->run_analysis (
        calculations       => ['calc_richness'],
        spatial_conditions => [
            'sp_circle(radius => 150000)',
            'sp_circle(radius => 300000)',
        ],
        definition_query   => '$y>1550000',
    );

    my @expected_element_list = sort $sp1->get_groups_that_pass_def_query();
    
        
    # referencing the def_query of another spatial output in the same
    # basedata
    my $sp2 = $bd1->add_spatial_output(name => 'sp2');
    my $success = eval {
        $sp2->run_analysis (
            calculations       => ['calc_richness'],
            spatial_conditions => [
                'sp_circle(radius => 150000)',
                'sp_circle(radius => 300000)',
            ],
            definition_query   => "sp_spatial_output_passed_defq(output=>'sp1')",
        );
    };
    ok ($success, 'Reference def_query of another spatial output in same basedata.');

    # the groups that passed the definition query should be same as
    # those that passed the previous query.
    my @got_element_list = sort $sp2->get_groups_that_pass_def_query;
    
    is_deeply (
        \@expected_element_list,
        \@got_element_list,
        "Correct elements passed the def query when it references another def query",
    );
}


# test referencing own def_query from within a spatial_condition
sub test_sp_passed_defq_same_sp {
    my $cell_sizes = [100000, 100000];
    my $bd1 = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
    $bd1->build_spatial_index (resolutions => $cell_sizes);

    my $sp1 = $bd1->add_spatial_output(name => 'sp1');
    my $cond = "sp_spatial_output_passed_defq()";

    my $success = eval {
        $sp1->run_analysis (
            calculations       => ['calc_richness'],
            spatial_conditions => [$cond],
            definition_query   => '$y<100000', # picked this value so there is only a few matches
                                               # tests run faster that way.
        );
    };
    ok ($success, 'Reference own def_query from a spatial_condition.');


    # now make sure the neighbours are only those who passed the
    # definition query
    my @elements = $sp1->get_element_list();

    # build expected results
    my @expected = ();
    foreach my $el (@elements) {
        my $coord = $sp1->get_element_name_as_array_aa ($el);
        if ($coord->[1] < 100000) {
            push(@expected, $el);
        }
    }
    
    foreach my $el (@elements) {
        check_neighbours_are_as_expected (
            bd => $bd1,
            cond => "sp_spatial_output_passed_defq (output=>'sp1')",
            element => $el,
            expected => \@expected,
        );
    }
}


# test using sp_spatial_output_passed_defq with no arguments in a
# spatial_condition: should default to the 'caller' spatial output.
sub test_sp_output_passed_defq_default_name {
    my $cell_sizes = [100000, 100000];
    my $bd1 = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
    $bd1->build_spatial_index (resolutions => $cell_sizes);

    
    # should be able to reference its own def_query if named is not
    # passed in
    my $sp = $bd1->add_spatial_output(name => 'sp');

    my $success = eval {
        $sp->run_analysis (
            calculations       => ['calc_richness'],
            spatial_conditions => ["sp_spatial_output_passed_defq()"],
            definition_query   => '$x<2000000',
        );
    };
    ok ($success, 'Reference own def_query from a spatial_condition without passing in name.');

    # now make sure the neighbours are only those who passed the
    # definition query
    my @elements = $sp->get_element_list();


    # build expected results
    my @expected = ();
    foreach my $el (@elements) {
        my $coord = $sp->get_element_name_as_array_aa ($el);
        if ($coord->[0] < 2000000) {
            push(@expected, $el);
        }
    }

    say "expected: @expected";
    
    foreach my $el (@elements) {
        check_neighbours_are_as_expected (
            bd       => $bd1,
            cond     => "sp_spatial_output_passed_defq(output => 'sp')",
            element  => $el,
            expected => \@expected,
        );
    }
}


# make sure a def_query can't reference itself through
# sp_spatial_output_passed_defq.
sub test_sp_passed_defq_illegal_self_reference {  
    my $cell_sizes = [100000, 100000];
    my $bd1 = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
    $bd1->build_spatial_index (resolutions => $cell_sizes);

    # should not work: referencing own def_query from within def_query
    my $sp1 = $bd1->add_spatial_output(name => 'sp1');

    my $success = eval {
        $sp1->run_analysis (
            calculations       => ['calc_richness'],
            spatial_conditions => [
                'sp_circle(radius => 150000)',
                'sp_circle(radius => 300000)',
            ],
            definition_query   => "sp_spatial_output_passed_defq(output=>'sp1')",
        );
    };
    my $e = $@;
    ok ($e, 'Get error when trying to self reference in def_query.');

    # also shouldn't be able to run a sp_spatial_output_passed_defq
    # with no args in a def_query
    $success = eval {
        $sp1->run_analysis (
            calculations       => ['calc_richness'],
            spatial_conditions => [
                'sp_circle(radius => 150000)',
                'sp_circle(radius => 300000)',
            ],
            definition_query   => "sp_spatial_output_passed_defq()",
        );
    };
    $e = $@;
    ok ($e, 'Get error when trying to self reference in def_query without passing in name.');
}





sub test_empty_groups {
    my $cell_sizes = [10, 10];
    my $bd = get_basedata_object (x_max => 10, y_max => 10, CELL_SIZES => $cell_sizes);
    

    my @coord = map {$_ * -1} @$cell_sizes;
    my $csv_object = $bd->get_csv_object (
        quote_char => $bd->get_param ('QUOTES'),
        sep_char   => $bd->get_param ('JOIN_CHAR')
    );
    my $empty_group_name = $bd->list2csv (list => \@coord, csv_object => $csv_object);

    $bd->add_element (
        allow_empty_groups => 1,
        group => $empty_group_name,
        count => 0,
    );
    
    my $calculations = [qw /calc_richness/];

    my $sp = $bd->add_spatial_output (name => 'sp_empty_groups');
    $sp->run_analysis (
        calculations       => $calculations,
        spatial_conditions => ['sp_self_only'],
    );

    my $result_list = $sp->get_list_ref (element => $empty_group_name, list => 'SPATIAL_RESULTS');
    my $expected = {
        RICHNESS_ALL  => 0,
        RICHNESS_SET1 => 0,
    };
    is_deeply ($result_list, $expected, 'empty group has expected results');
}


sub test_pass_blessed_conditions {
    my $cell_sizes = [10, 10];
    my $bd1 = get_basedata_object (x_max => 10, y_max => 10, CELL_SIZES => $cell_sizes);
    my $bd2 = $bd1->clone;  #  need separate bds to avoid optimisations where nbrs are copied

    my @calculations = qw /calc_element_lists_used/;

    my $sp1 = $bd1->add_spatial_output (name => 'sp1');
    $sp1->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [@calculations],
    );

    my $blessed_condition = Biodiverse::SpatialConditions->new (conditions => 'sp_self_only()');    
    my $sp2 = $bd2->add_spatial_output (name => 'sp2');
    $sp2->run_analysis (
        spatial_conditions => [$blessed_condition],
        calculations => [@calculations],
    );
    
    my %tbl_args = (symmetric => 1, list => 'EL_LIST_ALL');
    my $t1 = $sp1->to_table (%tbl_args);
    my $t2 = $sp2->to_table (%tbl_args);
    
    is_deeply ($t2, $t1, 'results match when a blessed spatial condition is passed');
}


sub test_recycling {
    my $cell_sizes = [1, 1];
    my $bd1 = get_basedata_object (x_max => 6, y_max => 6, CELL_SIZES => $cell_sizes);
    my $bd2 = $bd1->clone;  #  need separate bds to avoid optimisations where nbrs are copied
    my $bd3 = $bd1->clone;  #  need separate bds to avoid optimisations where nbrs are copied
    my $bd4 = $bd1->clone;  #  need separate bds to avoid optimisations where nbrs are copied

    my @calculations = qw /calc_element_lists_used/;
    my $spatial_condition_text = 'sp_block(size => 2)';

    my $sp1 = $bd1->add_spatial_output (name => 'sp1');
    my $blessed_condition1 = Biodiverse::SpatialConditions->new (conditions => $spatial_condition_text);
    $sp1->run_analysis (
        spatial_conditions => [$blessed_condition1],
        calculations => [@calculations],
    );

    my $blessed_condition2 = Biodiverse::SpatialConditions->new (conditions => $spatial_condition_text);
    my $sp2 = $bd2->add_spatial_output (name => 'sp2');
    $sp2->run_analysis (
        spatial_conditions => [$blessed_condition2],
        calculations => [@calculations],
        no_recycling => 1,
    );
    
    my $blessed_condition3 = Biodiverse::SpatialConditions->new (conditions => $spatial_condition_text);
    $blessed_condition3->set_no_recycling_flag (1);
    my $sp3 = $bd3->add_spatial_output (name => 'sp3');
    $sp3->run_analysis (
        spatial_conditions => [$blessed_condition3],
        calculations => [@calculations],
    );
    
    #  should only recycle nbr set 1
    my $blessed_condition4 = Biodiverse::SpatialConditions->new (conditions => $spatial_condition_text);
    my $sp4 = $bd4->add_spatial_output (name => 'sp4');
    $sp4->run_analysis (
        spatial_conditions => [$blessed_condition4, 'sp_block(size => 3)'],
        calculations => [@calculations],
    );

    ok ( $sp1->get_param ('RESULTS_ARE_RECYCLABLE'), 'Recycling flag on for sp1');
    ok (!$sp2->get_param ('RESULTS_ARE_RECYCLABLE'), 'Recycling flag off for sp2');
    ok (!$sp3->get_param ('RESULTS_ARE_RECYCLABLE'), 'Recycling flag off for sp3');
    ok (!$sp4->get_param ('RESULTS_ARE_RECYCLABLE'), 'Recycling flag off for sp4');

    my %tbl_args = (symmetric => 1, list => 'EL_LIST1');
    my $t1 = $sp1->to_table (%tbl_args);
    my $t2 = $sp2->to_table (%tbl_args);
    my $t3 = $sp3->to_table (%tbl_args);
    my $t4 = $sp4->to_table (%tbl_args);
    
    is_deeply ($t2, $t1, 'nbr set 1 match for recycling on and off');
    is_deeply ($t3, $t1, 'nbr set 1 match for recycling on and off (indices object control)');
    is_deeply ($t4, $t1, 'nbr set 1 match for recycling on and off (two nbr sets)');

    #  now check they were not recycled
    subtest 'results recycling per element' => sub {
        my $el_list = $sp1->get_element_list;
        for my $el (@$el_list) {
            ok ( $sp1->exists_list (list => 'RESULTS_SAME_AS', element => $el), "sp1 has RESULTS_SAME_AS list for el $el");
            ok (!$sp2->exists_list (list => 'RESULTS_SAME_AS', element => $el), "sp2 has no RESULTS_SAME_AS list for el $el");
            ok (!$sp3->exists_list (list => 'RESULTS_SAME_AS', element => $el), "sp3 has no RESULTS_SAME_AS list for el $el");
            ok (!$sp4->exists_list (list => 'RESULTS_SAME_AS', element => $el), "sp4 has no RESULTS_SAME_AS list for el $el");
        }
    };

    #  now check the list refs
    subtest 'nbr recycling per element' => sub {
        my $el_list = $sp1->get_element_list;
        for my $el (sort @$el_list) {
            my %n_args = (list => '_NBR_SET1', element => $el);
            my $listref1 = $sp1->get_list_ref (%n_args);
            my $listref2 = $sp2->get_list_ref (%n_args);
            my $listref3 = $sp3->get_list_ref (%n_args);
            my $listref4 = $sp4->get_list_ref (%n_args);
            foreach my $nbr (@$listref1) {
                next if $el eq $nbr;
                #  make sure we check the neighbour
                my %n_args_n = (list => '_NBR_SET1', element => $nbr);
                my $listref1n = $sp1->get_list_ref (%n_args_n);
                my $listref2n = $sp2->get_list_ref (%n_args_n);
                my $listref3n = $sp3->get_list_ref (%n_args_n);
                my $listref4n = $sp4->get_list_ref (%n_args_n);
                is   (refaddr $listref1, refaddr $listref1n, "_NBR_SET1 recycled for sp1, $el v $nbr");
                isnt (refaddr $listref2, refaddr $listref2n, "_NBR_SET1 not recycled for sp2, $el v $nbr");
                isnt (refaddr $listref3, refaddr $listref3n, "_NBR_SET1 not recycled for sp3, $el v $nbr");
                is   (refaddr $listref4, refaddr $listref4n, "_NBR_SET1 recycled for sp4, $el v $nbr");
            }
        }
    };

    subtest '_NBR_SET2 is not recycled' => sub {
        my $el_list = $sp4->get_element_list;
        for my $el (sort @$el_list) {
            my $listref4 = $sp4->get_list_ref (list => '_NBR_SET2', element => $el);
            foreach my $nbr (@$listref4) {
                my $listref4n = $sp4->get_list_ref (list => '_NBR_SET2', element => $nbr);
                isnt (refaddr $listref4, refaddr $listref4n, "_NBR_SET2 not recycled for sp4, $el v $nbr");
            }
        }
    };

}

sub get_element_proximity {
    my ($el1, $el2) = @_;
    #  cheating with the split
    my @e1 = split ':', $el1;
    my @e2 = split ':', $el2;
    
    sqrt (($e1[0] - $e2[0]) ** 2 + ($e1[1] - $e2[1]) ** 2);
}

sub test_get_calculated_nbr_lists_for_element {
    my $cell_sizes = [1, 1];
    my $bd1 = get_basedata_object (x_max => 15, y_max => 15, CELL_SIZES => $cell_sizes);
    $bd1->build_spatial_index (resolutions => $cell_sizes);
    
    my $target_element = '8.5:8.5';

    my $sp = $bd1->add_spatial_output(name => 'blongk');
    $sp->run_analysis (
        calculations       => ['calc_richness'],
        spatial_conditions => ['sp_circle(radius => 1.5)', 'sp_circle(radius => 3)'],
        definition_query   => "sp_select_element (element => '$target_element')",
    );

    #  no sort option
    my $lists_unsorted = $sp->get_calculated_nbr_lists_for_element (
        element => $target_element,
    );

    my $lists_sorted = $sp->get_calculated_nbr_lists_for_element (
        element    => $target_element,
        sort_lists => 1,
    );
    
    foreach my $i (0 .. $#$lists_sorted) {
        is_deeply (
            [sort @{$lists_unsorted->[$i]}],
            $lists_sorted->[$i],
            "sorted and unsorted lists have same elements, nbr list $i",
        );
    }

    #  now try with a more complex sort to do proximity in first two dimensions
    my $lists_sorted_proximity = [];
    foreach my $i (0 .. $#$lists_sorted) {
        @{$lists_sorted_proximity->[$i]} =
          map  { $_->[0] }
          sort { $a->[1] <=> $b->[1] || $a->[0] cmp $b->[0]}
          map  { [$_, get_element_proximity($target_element, $_)] }
               @{$lists_sorted->[$i]};
    }

    foreach my $i (0 .. $#$lists_sorted) {
        is_deeply (
            [sort @{$lists_sorted->[$i]}],
            [sort @{$lists_sorted_proximity->[$i]}],
            "text and proximity sorted lists have same elements, nbr list $i",
        );
        isnt_deeply (
            $lists_sorted->[$i],
            $lists_sorted_proximity->[$i],
            "text and proximity sorted lists have different orders, nbr list $i",
        );
    }
    
    is_deeply (
        get_expected_proximity_sorted_nbr_lists(),
        $lists_sorted_proximity,
        'Got expected proximity sorted nbr lists',
    );

    #  and now with a random tie breaker
    srand(2345);
    my $lists_sorted_proximity_rand = [];
    foreach my $i (0 .. $#$lists_sorted) {
        @{$lists_sorted_proximity_rand->[$i]} =
          map  { $_->[0] }
          sort { $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] || $a->[0] cmp $b->[0]}
          map  { [$_, get_element_proximity($target_element, $_), rand()] }
               @{$lists_sorted->[$i]};
    }

    foreach my $i (0 .. $#$lists_sorted) {
        is_deeply (
            [sort @{$lists_sorted_proximity->[$i]}],
            [sort @{$lists_sorted_proximity_rand->[$i]}],
            "proximity and proximity/rand sorted lists have same elements, nbr list $i",
        );
        isnt_deeply (
            $lists_sorted_proximity->[$i],
            $lists_sorted_proximity_rand->[$i],
            "proximity and proximity/rand sorted lists have different orders, nbr list $i",
        );
    }

}


done_testing;



sub run_analysis {
    my %args = @_;

    my $cell_sizes   = $args{cell_sizes} || [100000, 100000];
    my $conditions   = $args{spatial_conditions} || ['sp_self_only()'];
    my $def_query    = $args{definition_query};
    my $calculations = $args{calculations} || ['calc_endemism_central'];

    my $bd = $args{basedata_ref}
      || get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);

    my $name = 'Spatial output for testing ' . time();
    my $sp = $bd->add_spatial_output (name => $name);
    my $success = eval {
        $sp->run_analysis (
            spatial_conditions => $conditions,
            definition_query   => $def_query,
            calculations       => $calculations,
        );
    };
    diag $@ if $@;

    ok ($success, 'Ran an analysis without error');

    return $sp;
}

sub get_expected_list_for_defq_y_gt_1550000 {
    my @data_for_defq = (
        qw /
            3150000:2950000
            3250000:2150000
            3250000:2850000
            3250000:2950000
            3250000:3050000
            3350000:2050000
            3350000:2150000
            3450000:2050000
            3450000:2150000
            3550000:1950000
            3550000:2050000
            3550000:2150000
            3550000:2250000
            3650000:1650000
            3650000:1750000
            3650000:1850000
            3650000:1950000
            3650000:2050000
            3650000:2350000
            3750000:1650000
            3750000:1750000
            3750000:1850000
            3750000:1950000
            3750000:2050000
            3750000:2150000
            3850000:1650000
            3850000:1750000
            3850000:1850000
            3850000:1950000
            3950000:1750000
    /);
    return wantarray ? @data_for_defq : \@data_for_defq;
}

sub get_expected_proximity_sorted_nbr_lists {
    [
        [
            '8.5:8.5',
            '7.5:8.5',
            '8.5:7.5',
            '8.5:9.5',
            '9.5:8.5',
            '7.5:7.5',
            '7.5:9.5',
            '9.5:7.5',
            '9.5:9.5'
          ],
          [
            '10.5:8.5',
            '6.5:8.5',
            '8.5:10.5',
            '8.5:6.5',
            '10.5:7.5',
            '10.5:9.5',
            '6.5:7.5',
            '6.5:9.5',
            '7.5:10.5',
            '7.5:6.5',
            '9.5:10.5',
            '9.5:6.5',
            '10.5:10.5',
            '10.5:6.5',
            '6.5:10.5',
            '6.5:6.5',
            '11.5:8.5',
            '5.5:8.5',
            '8.5:11.5',
            '8.5:5.5'
          ]
    ];
}
