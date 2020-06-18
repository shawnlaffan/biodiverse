#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

#  don't test plugins
local $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;

my $generate_result_sets = 0;

use Test::Lib;
use rlib;
use Test::Most;
use List::Util qw /sum/;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
    :tree
    :utils
};


use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @test_subs = grep {$_ =~ 'main::test_'} $obj->functions();


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

    foreach my $sub (@test_subs) {
        no strict 'refs';
        $sub->();
    }
    
    done_testing;
    return 0;
}


sub test_pd_local {
    
    my @calcs = qw/
        calc_pd_local
        calc_pd
    /;

    my $cell_sizes = [200000, 200000];
    my $bd   = get_basedata_object_from_site_data (CELL_SIZES => $cell_sizes);
    $bd->binarise_sample_counts;
    
    my $tree = get_tree_object_from_sample_data();
    #  set lengths to 1 to simplify tests
    $tree->delete_cached_values;
    foreach my $node ($tree->get_node_refs) {  
        $node->set_length (length => 1);
        $node->delete_cached_values;
    }
    #  reset all the total length values
    $tree->reset_total_length;
    $tree->reset_total_length_below;

    my $sp = $bd->add_spatial_output (name => 'local PD');
    $sp->run_analysis (
        calculations       => [@calcs],
        spatial_conditions => ['sp_self_only()'],
        tree_ref           => $tree,
    );

    my $elts = $sp->get_element_list;
    subtest 'local PD wrt PD' => sub {
        foreach my $elt (@$elts) {
            my $results_list = $sp->get_list_ref (
                list    => 'SPATIAL_RESULTS',
                element => $elt,
            );
            if ($bd->get_richness_aa($elt) == 1) {
                is (
                    $results_list->{PD_LOCAL}, $results_list->{PD},
                    "PD_LOCAL == PD for $elt, singular taxon"
                );
                is (
                    $results_list->{PD_LOCAL_P}, $results_list->{PD_P},
                    "PD_LOCAL_P == PD_P for $elt, singular taxon"
                );
            }
            else {
                cmp_ok (
                    $results_list->{PD_LOCAL}, '<=', $results_list->{PD},
                    "PD_LOCAL <= PD for $elt"
                );
                cmp_ok (
                    $results_list->{PD_LOCAL_P}, '<=', $results_list->{PD_P},
                    "PD_LOCAL_P <= PD_P for $elt"
                );
            }
        }
    };
    
    #  now check one cell
    my $target_elt = '2100000:1300000';
    my %expected = (
        PD         => 11,
        PD_P       => 0.180327868852459,
        PD_LOCAL   => 7,
        PD_LOCAL_P => 0.114754098360656,
        PD_P_per_taxon => 0.0901639344262295,
        PD_per_taxon   => 5.5,
    );
    my $results_list = $sp->get_list_ref (
        list    => 'SPATIAL_RESULTS',
        element => $target_elt,
    );
    is_deeply ($results_list, \%expected, "Got expected results for $target_elt");
}

