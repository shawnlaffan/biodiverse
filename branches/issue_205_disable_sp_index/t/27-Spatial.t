#  test the spatial outputs


### need to test for basedatas with empty groups

require 5.010;
use strict;
use warnings;
use Carp;

use FindBin qw/$Bin/;
use rlib;

use Test::More;

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


sub test_empty_groups {
    my $cell_sizes = [10, 10];
    my $bd = get_basedata_object (x_max => 10, y_max => 10, CELL_SIZES => $cell_sizes);
    

    my @coord = map {$_ * -1} @$cell_sizes;
    my $csv_object = $bd->get_csv_object (
        quote_char => $bd->get_param ('QUOTES'),
        sep_char   => $bd->get_param ('JOIN_CHAR')
    );
    my $group_name = $bd->list2csv (list => \@coord, csv_object => $csv_object);

    $bd->add_element (
        allow_empty_groups => 1,
        group => $group_name,
        count => 0,
    );
    
    my $calculations = [qw /calc_hierarchical_label_ratios calc_richness/];

    my $sp = $bd->add_spatial_output (name => 'sp_empty_groups');
    $sp->run_analysis (
        calculations       => $calculations,
        spatial_conditions => ['sp_self_only'],
    );
    
    #  NEED TO TEST THAT NO ERRORS HAPPENED
    TODO:
    {
        $TODO = 'Empty group test not implemented yet';
        is (1, 1, 'placeholder');
    }
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
        spatial_conditions => [$blessed_condition4, 'sp_circle(radius => 2)'],
        calculations => [@calculations],
    );

    ok ( $sp1->get_param ('RESULTS_ARE_RECYCLABLE'), 'Recycling flag set for sp1');
    ok (!$sp2->get_param ('RESULTS_ARE_RECYCLABLE'), 'Recycling flag not set for sp2');
    ok (!$sp3->get_param ('RESULTS_ARE_RECYCLABLE'), 'Recycling flag not set for sp3');
    ok (!$sp4->get_param ('RESULTS_ARE_RECYCLABLE'), 'Recycling flag not set for sp4');

    my %tbl_args = (symmetric => 1, list => 'EL_LIST_ALL');
    my $t1 = $sp1->to_table (%tbl_args);
    my $t2 = $sp2->to_table (%tbl_args);
    my $t3 = $sp3->to_table (%tbl_args);
    
    is_deeply ($t2, $t1, 'results match for recycling on and off');
    is_deeply ($t3, $t1, 'results match for recycling on and off (indices object control)');
    
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
            my $listref1 = $sp1->get_list_ref (list => '_NBR_SET1', element => $el);
            my $listref2 = $sp2->get_list_ref (list => '_NBR_SET1', element => $el);
            my $listref3 = $sp3->get_list_ref (list => '_NBR_SET1', element => $el);
            my $listref4 = $sp4->get_list_ref (list => '_NBR_SET1', element => $el);
            foreach my $nbr (@$listref1) {
                next if $el eq $nbr;
                my $listref1n = $sp1->get_list_ref (list => '_NBR_SET1', element => $nbr);
                my $listref2n = $sp2->get_list_ref (list => '_NBR_SET1', element => $nbr);
                my $listref3n = $sp3->get_list_ref (list => '_NBR_SET1', element => $nbr);
                my $listref4n = $sp4->get_list_ref (list => '_NBR_SET1', element => $nbr);
                is   ($listref1, $listref1n, "_NBR_SET1 recycled for sp1, $el v $nbr");
                isnt ($listref2, $listref2n, "_NBR_SET1 not recycled for sp2, $el v $nbr");
                isnt ($listref3, $listref3n, "_NBR_SET1 not recycled for sp3, $el v $nbr");
                is   ($listref4, $listref4n, "_NBR_SET1 recycled for sp4, $el v $nbr");
            }
        }
    };

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