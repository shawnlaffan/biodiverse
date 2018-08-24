#  These are randomisation tests that take longer,
#  so have been shifted into a separate test file 

local $| = 1;
use 5.010;
use strict;
use warnings;
use Carp;

use FindBin qw/$Bin/;
use Test::Lib;
use rlib;
use List::Util qw /first sum0/;
use List::MoreUtils qw /any_u/;

use Test::More;
use Test::Deep;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Test::More; # tests => 2;
use Test::Exception;

use Biodiverse::TestHelpers qw /:cluster :element_properties :tree/;
use Biodiverse::Cluster;

use Biodiverse::Randomise;

use Math::Random::MT::Auto;

my $default_prng_seed = 2345;

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
        #diag "Running $sub";
        $sub->();
    }

    done_testing;
    return 0;
}

sub test_same_results_given_same_prng_seed_subcheck {
    my $c = 200000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);
    $bd->build_spatial_index (resolutions => [$c, $c]);
    my $sp //= $bd->add_spatial_output (name => 'sp');
    
    my $r_spatially_structured_cond = "sp_circle (radius => $c)";
    
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [qw /calc_richness calc_element_lists_used calc_elements_used/],
    );

   
    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_structured',
    );
}

#  Should get the same result for two iterations run in one go
#  as we do for two run sequentially (first, pause, second)
sub test_same_results_given_same_prng_seed {
    my $c = 200000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);
    $bd->build_spatial_index (resolutions => [$c, $c]);
    my $sp //= $bd->add_spatial_output (name => 'sp');
    
    my $r_spatially_structured_cond = "sp_circle (radius => $c)";
    
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [qw /calc_richness calc_element_lists_used calc_elements_used/],
    );

    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_csr_by_group',
    );
    
    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_structured',
    );

    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_spatially_structured',
        spatial_conditions_for_label_allocation => [$r_spatially_structured_cond],
    );
    
    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_spatially_structured',
        spatial_allocation_order => 'proximity',
        prefix => 'rand_spatially_structured proximity',
        spatial_conditions_for_label_allocation => [$r_spatially_structured_cond],
    );

    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_spatially_structured',
        spatial_allocation_order => 'random_walk',
        spatial_conditions_for_label_allocation => [$r_spatially_structured_cond],
        prefix => 'rand_spatially_structured random_walk',
    );

    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_spatially_structured',
        spatial_allocation_order => 'random_walk',
        spatial_conditions_for_label_allocation => [$r_spatially_structured_cond],
        label_allocation_backtracking => 'from_end',
        prefix => 'rand_spatially_structured random_walk from_end',
    );

    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_spatially_structured',
        spatial_allocation_order => 'random_walk',
        spatial_conditions_for_label_allocation => [$r_spatially_structured_cond],
        label_allocation_backtracking => 'from_start',
        prefix => 'rand_spatially_structured random_walk from_start',
    );

    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_spatially_structured',
        spatial_allocation_order => 'random_walk',
        spatial_conditions_for_label_allocation => [$r_spatially_structured_cond],
        label_allocation_backtracking => 'random',
        prefix => 'rand_spatially_structured random_walk random',
    );

    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_spatially_structured',
        spatial_allocation_order => 'diffusion',
        spatial_conditions_for_label_allocation => [$r_spatially_structured_cond],
        prefix => 'rand_spatially_structured diffusion',
    );

    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_random_walk',
        spatial_conditions_for_label_allocation => [$r_spatially_structured_cond],
        prefix => 'rand_random_walk',
    );

    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_diffusion',
        spatial_conditions_for_label_allocation => [$r_spatially_structured_cond],
        prefix => 'rand_diffusion',
    );

    check_same_results_given_same_prng_seed (
        bd => $bd,
        function => 'rand_nochange',
    );

}



sub check_same_results_given_same_prng_seed {
    my %args = @_;

    my $rand_function = $args{function} // croak "function argument not passed";
    my $prefix = $args{prefix} // $rand_function;

    my $bd = $args{bd} // get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);
    my $sp = $bd->get_spatial_output_ref (name => 'sp');

    my $prng_seed = 2345;

    my $rand_name_2in1 = $prefix . "_2in1";
    my $rand_name_1x1  = $prefix . "_1x1";

    my $rand_2in1 = $bd->add_randomisation_output (name => $rand_name_2in1);
    $rand_2in1->run_analysis (
        %args,
        iterations => 3,
        seed       => $prng_seed,
    );

    my $rand_1x1 = $bd->add_randomisation_output (name => $rand_name_1x1);
    for my $i (0..2) {
        $rand_1x1->run_analysis (
            %args,
            iterations => 1,
            seed       => $prng_seed,
        );
    }

    #  these should be the same as the PRNG sequence will be maintained across iterations
    my $table_2in1 = $sp->to_table (list => $rand_name_2in1 . '>>SPATIAL_RESULTS');
    my $table_1x1  = $sp->to_table (list => $rand_name_1x1  . '>>SPATIAL_RESULTS');

    is_deeply (
        $table_2in1,
        $table_1x1,
        "$prefix: Results same when init PRNG seed same and iteration counts same"
    );

    #  now we should see a difference if we run another
    $rand_1x1->run_analysis (
        %args,
        iterations => 1,
        seed       => $prng_seed,
    );
    $table_1x1 = $sp->to_table (list => $rand_name_1x1  . '>>SPATIAL_RESULTS');
    isnt (
        eq_deeply (
            $table_2in1,
            $table_1x1,
        ),
        "$prefix: Results different when init PRNG seed same but iteration counts differ",
    );

    #  Now catch up the other one, but change some more args.
    #  Most should be ignored.
    $rand_2in1->run_analysis (
        %args,
        iterations => 1,
        seed       => $prng_seed,
    );
    $table_2in1 = $sp->to_table (list => $rand_name_2in1 . '>>SPATIAL_RESULTS');

    is_deeply (
        $table_2in1,
        $table_1x1,
        "$prefix: Changed function arg ignored in analysis with an iter completed"
    );
    
    return;
}


sub test_rand_calc_per_node_uses_orig_bd {
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $cl = $bd->add_cluster_output (name => 't_r_c_p_n_u_o_b');
    
    $cl->run_analysis (
        spatial_calculations => [qw /calc_richness calc_element_lists_used calc_elements_used/],
    );

    my $rand_name = 'xxx';

    my $rand = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand->run_analysis (
        function   => 'rand_csr_by_group',
        iterations => 1,
        retain_outputs => 1,
        return_rand_bd_array => 1,
    );

    my $rand_bd1 = $rand_bd_array->[0];
    my @refs = $rand_bd1->get_cluster_output_refs;
    my $rand_cl = first {$_->get_param ('NAME') =~ m/rand sp_calc/} @refs;  #  bodgy way of getting at it

    my $sub_ref = sub {
        node_calcs_used_same_element_sets (
            orig_tree => $cl,
            rand_tree => $rand_cl,
        );
    };
    subtest 'Calcs per node used the same element sets' => $sub_ref;
    
    my $sub_ref2 = sub {
        node_calcs_gave_expected_results (
            cluster_output => $cl,
            rand_name      => $rand_name,
        );
    };
    subtest 'Calcs per node used the same element sets' => $sub_ref2;

    return;
}


#  iterate over all the nodes and check they have the same
#  element lists and counts, but that the richness scores are not the same    
sub node_calcs_used_same_element_sets {
    my %args = @_;
    my $orig_tree = $args{orig_tree};
    my $rand_tree = $args{rand_tree};

    my %orig_nodes = $orig_tree->get_node_hash;
    my %rand_nodes = $rand_tree->get_node_hash;

    is (scalar keys %orig_nodes, scalar keys %rand_nodes, 'same number of nodes');

    my $count_richness_same = 0;

    foreach my $name (sort keys %orig_nodes) {  #  always test in same order for repeatability
        my $o_node_ref = $orig_nodes{$name};
        my $r_node_ref = $rand_nodes{$name};

        my $o_element_list = $o_node_ref->get_list_ref (list => 'EL_LIST_SET1');
        my $r_element_list = $r_node_ref->get_list_ref (list => 'EL_LIST_SET1');
        is_deeply ($o_element_list, $r_element_list, "$name used same element lists");
        
        my $o_sp_res = $o_node_ref->get_list_ref (list => 'SPATIAL_RESULTS');
        my $r_sp_res = $r_node_ref->get_list_ref (list => 'SPATIAL_RESULTS');
        if ($o_sp_res->{RICHNESS_ALL} == $r_sp_res->{RICHNESS_ALL}) {
            $count_richness_same ++;
        }
    }

    isnt ($count_richness_same, scalar keys %orig_nodes, 'richness scores differ between orig and rand nodes');

    return;
}


#  rand results should be zero for all el_list P and C results, 1 for Q
sub node_calcs_gave_expected_results {
    my %args = @_;
    my $cl          = $args{cluster_output};
    my $list_prefix = $args{rand_name};
    
    my $list_name = $list_prefix . '>>SPATIAL_RESULTS';
    
    my %nodes = $cl->get_node_hash;
    foreach my $node_ref (sort {$a->get_name cmp $b->get_name} values %nodes) {
        my $list_ref = $node_ref->get_list_ref (list => $list_name);
        my $node_name = $node_ref->get_name;

        KEY:
        while (my ($key, $value) = each %$list_ref) {
            my $expected
              = ($key =~ /^[TQ]_EL/) ? 1
              : ($key =~ /^[CP]_EL/) ? 0
              : next KEY;
            is ($value, $expected, "$key score for $node_name is $expected")
        }
        
    }
    
}


