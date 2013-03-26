#  test the spatial outputs


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


#  check the def queries
{
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
        
        my @got_element_list = sort keys $passed_defq;
        
        is_deeply (
            \@expected_element_list,
            \@got_element_list,
            "Got the same elements for $def_query_text",
        );
        
        #  cleanup
        $bd->delete_output(output => $sp);
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