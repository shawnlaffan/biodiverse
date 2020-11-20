use 5.010;
use strict;
use warnings;

# HARNESS-DURATION-LONG

local $| = 1;

use Carp;

use FindBin qw/$Bin/;
use rlib;
use List::Util qw /first sum0/;
use List::MoreUtils qw /any_u/;

use Test2::V0;
use Test::Deep::NoTest qw/eq_deeply/;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

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


sub test_mutable_parameters {
    my $target_arg = 'add_basedatas_to_project';
    my $metadata   = Biodiverse::Randomise->get_metadata (sub => 'rand_csr_by_group');
    my $params     = $metadata->get_parameters;
    my $has_target = any_u {$_->get_name eq $target_arg} @$params;

    SKIP: {
        skip "missing mutable target $target_arg", 2
          if !$has_target;

        my $c = 300000;
        my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);
    
        my $sp = $bd->add_spatial_output(name => 'sp_to_test_mutables');
        $sp->run_analysis (
            calculations => ['calc_richness'],
            spatial_conditions => ['sp_self_only()'],
        );
        my $rand = $bd->add_randomisation_output (name => 'test_mutable_params');
        
    
        my %analysis_args = (
            function => 'rand_csr_by_group',
            iterations => 1,
            $target_arg => 1,  #  need a better one to test
        );
    
        $rand->run_analysis(%analysis_args);
    
        my $args = $rand->get_param('ARGS');
    
        $rand->run_analysis(
            %analysis_args,
            $target_arg => 10,
        );
        is (
            $args->{add_basedatas_to_project},
            1,
            "mutable arg $target_arg set as expected on first iter",
        );
    
        $args = $rand->get_param('ARGS');
        
        is (
            $args->{add_basedatas_to_project},
            10,
            "mutable arg $target_arg changed as expected",
        );
    };
}

sub test_rand_independent_swaps {
    test_rand_structured_richness_same (
        'rand_independent_swaps', swap_count => 1000,
    );
}


sub test_rand_structured_richness_same {
    my ($rand_function, %args) = @_;
    $rand_function //= 'rand_structured';
    
    my $c = 100000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);

    #  add some empty groups - need enough to trigger issue #543
    foreach my $i (1 .. 20) {
        my $x = $i * -$c + $c / 2;
        my $y = -$c / 2;
        my $gp = "$x:$y";
        $bd->add_element (group => $gp, allow_empty_groups => 1);
    }

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [qw /calc_richness/],
    );

    my $prng_seed = 2345;

    my $rand_name = $rand_function;

    my $rand = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand->run_analysis (
        function   => $rand_function,
        iterations => 3,
        seed       => $prng_seed,
        return_rand_bd_array => 1,
        %args,
    );
    
    foreach my $rand_bd (@$rand_bd_array) {
        is ([sort $rand_bd->get_labels],
            [sort $bd->get_labels],
            'randomised basedata all the labels',
        );
        is ([sort $rand_bd->get_groups],
            [sort $bd->get_groups],
            'randomised basedata all the groups',
        );
    }

    subtest 'richness scores match' => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $group (sort $rand_bd->get_groups) {
                my $bd_richness = $bd->get_richness_aa ($group) // 0;
                is ($rand_bd->get_richness_aa ($group) // 0,
                    $bd_richness,
                    "richness for $group matches ($bd_richness)",
                );
            }
        }
    };
    subtest 'range scores match' => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $label ($rand_bd->get_labels) {
                is ($rand_bd->get_range (element => $label),
                    $bd->get_range (element => $label),
                    "range for $label matches",
                );
            }
        }
    };

    return;
}


#  Basic spatial structure approach
#  We find a neighbourhood and fill it up, then find another and fill it up, etc
sub test_rand_spatially_structured {
    my $c  = 1;
    my $c3 = $c * 1;
    my $c6 = $c * 2;
    my $c9 = $c * 3;
    my $bd_size = 21;

    my $prng_seed = 2345;
    
    #my $prng = Math::Random::MT::Auto->new;
    
    my $bd = Biodiverse::BaseData->new (
        NAME => 'test_rand_spatially_structured',
        CELL_SIZES => [$c, $c],
        CELL_ORIGINS => [$c/2, $c/2],
    );
    
    my @labels = qw /a b c/;
    my $k = 0;
    foreach my $i (0 .. $bd_size) {
        foreach my $j (0 .. $bd_size) {
            my $group = "$i:$j";
            $bd->add_element (group => $group);
            my $label = $labels[$i % 3];
            $bd->add_element (group => $group, label => $label, count => $k);
            $k++;
        }
    }
    
    $bd->build_spatial_index(resolutions => [$c, $c]);

    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_square (size => 3)'],
        calculations => [qw /calc_local_range_lists/],
    );

    my $rand_name = 'rand_spatially_structured';

    my $rand = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand->run_analysis (
        function   => 'rand_spatially_structured',
        spatial_allocation_order => 'random',
        iterations => 1,  #  reset to 3 later
        seed       => $prng_seed,
        richness_addition   => 30,  #  make sure we can put our three labels anywhere
        richness_multiplier => 1,
        spatial_conditions_for_label_allocation => [
            "sp_self_only()",
            "sp_circle(radius => $c3)",
            "sp_circle(radius => $c6)",
            "sp_circle(radius => $c9)",
        ],
        return_rand_bd_array => 1,
        retain_outputs => 1,
    );

    is ($rand->get_param('SWAP_OUT_COUNT'), 0,
        'Did not swap out in spatially structured rand',
    );
    is ($rand->get_param('SWAP_INSERT_COUNT'), 0,
        'Did not swap insert in spatially structured rand',
    );

    subtest 'range scores match' => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $label (sort $rand_bd->get_labels) {
                is ($rand_bd->get_range (element => $label),
                    $bd->get_range (element => $label),
                    "range for $label matches",
                );
            }
        }
    };

    #  check the local ranges
    subtest 'no isolated cases' => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            my $outputs = $rand_bd->get_output_refs;
            my $output  = $outputs->[0];  #  only one output
            foreach my $group (sort $output->get_element_list) {
                next if !$rand_bd->get_richness(element => $group);
                my $labels = $rand_bd->get_labels_in_group (group => $group);
                my $list = $output->get_list_ref (
                    element => $group,
                    list => 'ABC2_LABELS_SET1',
                );
                foreach my $label (sort @$labels) {
                    cmp_ok ($list->{$label}, '>', 1,
                        "local range for $label is > 1, group $group",
                    );
                }
            }
        }
    };

    return;
}


#  When the spatial constraint does
#  not span the whole basedata then
#  we need to handle the leftovers
sub test_rand_spatial_constraint_leftovers {
    my $c  = 1;
    my $bd_size = 11;

    my $prng_seed = 2345;
    
    #my $prng = Math::Random::MT::Auto->new;
    
    my $bd = Biodiverse::BaseData->new (
        NAME => 'test_rand_spatially_structured',
        CELL_SIZES => [$c, $c],
        CELL_ORIGINS => [$c/2, $c/2],
    );
    
    my @labels = qw /a b c/;
    my $k = 0;
    foreach my $i (0 .. $bd_size) {
        foreach my $j (0 .. $bd_size) {
            my $group = "$i:$j";
            $bd->add_element (group => $group);
            my $label = $labels[$i % 3];
            $bd->add_element (group => $group, label => $label, count => $k);
            $k++;
        }
    }
    
    $bd->build_spatial_index(resolutions => [$c, $c]);

    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_square (size => 3)'],
        calculations => [qw /calc_local_range_lists/],
    );

    my $rand_name = 'rand_spatially_structured_but_incomplete';

    my $sp_cond_for_subset = <<"EOSC"
sp_point_in_poly (
    polygon => [[5,5],[10,5],[10,0],[5,0],[5,5]],
)
EOSC
;
    my $rand = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand->run_analysis (
        function   => 'rand_structured',
        iterations => 1,  #  maybe reset to 3 later
        seed       => $prng_seed,
        spatial_conditions_for_subset => [$sp_cond_for_subset],
        richness_multiplier => 1,
        return_rand_bd_array => 1,
        retain_outputs => 1,
    );

    subtest 'range scores match' => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $label (sort $rand_bd->get_labels) {
                is ($rand_bd->get_range (element => $label),
                    $bd->get_range (element => $label),
                    "range for $label matches",
                );
            }
        }
    };

    subtest 'richness scores match' => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $group (sort $rand_bd->get_groups) {
                is ($rand_bd->get_richness_aa ($group),
                    $bd->get_richness_aa ($group),
                    "richness for $group matches",
                );
            }
        }
    };

    return;
}


sub test_random_propagation {
    my $c  = 1;
    my $c3 = $c * 1;
    my $c6 = $c * 2;
    my $c9 = $c * 3;
    my $bd_size = 21;

    my $prng_seed = 2345;
    
    my $bd = Biodiverse::BaseData->new (
        NAME => 'bd_test_random_propagation',
        CELL_SIZES => [$c, $c],
        CELL_ORIGINS => [$c/2, $c/2],
    );
    
    my @labels = qw /a b c/;
    my $k = 0;
    foreach my $i (0 .. $bd_size) {
        foreach my $j (0 .. $bd_size) {
            my $group = "$i:$j";
            $bd->add_element (group => $group);
            my $label = $labels[$i % 3];
            $bd->add_element (group => $group, label => $label, count => $k);
            $k++;
        }
    }

    $bd->build_spatial_index(resolutions => [$c, $c]);

    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_square (size => 3)'],
        calculations => [qw /calc_element_lists_used/],
    );

    my $rand_name = 'test_random_propagation';

    my $rand = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand->run_analysis (
        function   => 'rand_spatially_structured',
        iterations => 1,  #  reset to 3 later
        seed       => $prng_seed,
        richness_addition   => 30,  #  make sure we can put our three labels anywhere
        richness_multiplier => 1,
        spatial_conditions_for_label_allocation => [
            'sp_square (size => 3)',
        ],
        return_rand_bd_array => 1,
        retain_outputs => 1,
        spatial_allocation_order => 'random_walk',
        track_label_allocation_order => 1,
    );

    is ($rand->get_param('SWAP_OUT_COUNT'), 0,
        'Did not swap out in spatially structured random_propagation ',
    );
    is ($rand->get_param('SWAP_INSERT_COUNT'), 0,
        'Did not swap insert in spatially structured random_propagation ',
    );

    subtest 'range scores match' => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $label (sort $rand_bd->get_labels) {
                is ($rand_bd->get_range (element => $label),
                    $bd->get_range (element => $label),
                    "range for $label matches",
                );
            }
        }
    };

    my $sp_alloc_name = 'sp_to_track_allocations';
    #  check the local ranges
    subtest 'allocation order is sequential' => sub {
        no autovivification;
        my $i = 0;
        foreach my $rand_bd (@$rand_bd_array) {
            $i++;
            my $output
              = $rand_bd->get_spatial_output_ref(name => "sp Randomise $i");
            my $alloc_output
              = $rand_bd->get_spatial_output_ref(name => $sp_alloc_name);

            foreach my $group (sort $output->get_element_list) {
                next if !$rand_bd->get_richness(element => $group);
                my $labels = $rand_bd->get_labels_in_group (group => $group);
                my $el_list = $output->get_list_ref (
                    element => $group,
                    list    => 'EL_LIST_SET1',
                );
                my $alloc_list = $alloc_output->get_list_ref (
                    element => $group,
                    list    => 'ALLOCATION_ORDER',
                );
              LABEL:
                foreach my $label (sort @$labels) {
                    my $alloc_num = $alloc_list->{$label};
                    next LABEL if $alloc_num == $bd->get_range(element => $label);
                    my @alloc_nbrs;
                  NBR:
                    foreach my $nbr (keys %$el_list) {
                        next if $group eq $nbr;
                        my $nbr_alloc_list = $alloc_output->get_list_ref (
                            element => $nbr,
                            list    => 'ALLOCATION_ORDER',
                        );
                        my $nbr_alloc_num = $nbr_alloc_list->{$label} // -1;
                        push @alloc_nbrs, $nbr_alloc_num;
                    }
                    my $count_one_higher = grep {($_-1) == $alloc_num} @alloc_nbrs;
                    my $lt = grep {$_ < $alloc_num} @alloc_nbrs;
                    if ($lt != (scalar @alloc_nbrs)) {
                        is ($count_one_higher, 1,
                            "next allocation is one higher, $label, $alloc_num",
                        );
                    }
                    #  we could test that the preceding allocation is one less,
                    #  but that does not allow for backtracking
                }
            }
        }
    };

    return;
}


sub test_rand_structured_richness_multiplier_and_addition {
    my $c = 100000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);

    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [qw /calc_richness/],
    );

    my $prng_seed = 2345;

    my $rand_name = 'rand_structured';

    my $rand = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand->run_analysis (
        function   => 'rand_structured',
        iterations => 3,
        seed       => $prng_seed,
        return_rand_bd_array => 1,
        richness_addition    => 1,
        richness_multiplier  => 2,
    );

    subtest 'richness scores do not match for richness_addition and multiplier' => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            my $same = 1;
            foreach my $group (sort $rand_bd->get_groups) {
                my $bd_richness = $bd->get_richness(element => $group) // 0;
                $same &&= ($bd_richness == $rand_bd->get_richness (element => $group));
                last if !$same;
            }
            ok (!$same, $rand_bd->get_name);
        }
    };
    subtest 'range scores match for richness_addition and multiplier' => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $label ($rand_bd->get_labels) {
                is ($rand_bd->get_range (element => $label),
                    $bd->get_range (element => $label),
                    "range for $label matches",
                );
            }
        }
    };

    return;
}

sub test_rand_structured_does_not_swap {
    my $c = 1;
    my $bd_size = 25;
    my $bd = Biodiverse::BaseData->new (
        NAME => 'test_rand_spatially_structured',
        CELL_SIZES => [$c, $c],
    );
    
    #my $prng_seed = 2345;
    my $prng = Math::Random::MT::Auto->new;

    
    foreach my $i (0 .. $bd_size) {
        foreach my $j (0 .. $bd_size) {
            my $group = "$i:$j";
            $bd->add_element (group => $group);
            foreach my $label (qw /a b c/) {
                if ($prng->rand < (1/3)) {
                    $bd->add_element (group => $group, label => $label);
                }
            }
        }
    }

    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [qw /calc_richness/],
    );

    my $prng_seed = 2345;

    my $rand_name = 'rand_structured';

    my $rand = $bd->add_randomisation_output (name => $rand_name);
    $rand->run_analysis (
        function   => 'rand_structured',
        iterations => 3,
        seed       => $prng_seed,
        #return_rand_bd_array => 1,
        richness_addition    => 10000,
        richness_multiplier  => 2,
    );

    is ($rand->get_param('SWAP_OUT_COUNT'), 0,
        'Did not swap out when richness targets are massive',
    );
    is ($rand->get_param('SWAP_INSERT_COUNT'), 0,
        'Did not swap insert when richness targets are massive',
    );

    return;
}


sub test_rand_structured_subset_richness_same_with_defq {
    my $defq = '$y > 1050000';

    my ($rand_object, $bd, $rand_bd_array) = test_rand_structured_subset_richness_same ($defq);

    my $sp = $rand_object->get_param ('SUBSET_SPATIAL_OUTPUT');
    my $failed_defq = $sp->get_groups_that_failed_def_query;

    subtest 'groups that failed def query are unchanged' => sub {
        my $i = -1;
        foreach my $rand_bd (@$rand_bd_array) {
            $i++;
            foreach my $gp (sort keys %$failed_defq) {
                my $expected = $bd->get_labels_in_group_as_hash(group => $gp);
                my $observed = $rand_bd->get_labels_in_group_as_hash(group => $gp);
                is (
                    $observed,
                    $expected,
                    "defq check: $gp labels are same for rand_bd $i",
                );
            }
        }
    };

    #  now try with a def query but no spatial condition
    #  - we should get the same result as condition sp_select_all()
    my $rand_object2 = $bd->add_randomisation_output (name => 'defq but no sp_cond');
    $rand_object2->run_analysis (
        function   => 'rand_structured',
        iterations => 1,
        seed       => 2345,
        definition_query => $defq,
    );
    my $sp2 = $rand_object2->get_param ('SUBSET_SPATIAL_OUTPUT');
    my $sp_conditions = $sp2->get_spatial_conditions_arr;
    ok (
        $sp_conditions->[0]->get_conditions_unparsed eq 'sp_select_all()',
        'got expected default condition when defq specified without spatial condition',
    );

    return;
}

sub test_rand_structured_subset_richness_same {
    my $def_query = shift;

    my $c = 100000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);

    #  add some empty groups - need enough to trigger issue #543
    foreach my $i (1 .. 20) {
        my $x = $i * -$c + $c / 2;
        my $y = -$c / 2;
        my $gp = "$x:$y";
        $bd->add_element (group => $gp, allow_empty_groups => 1);
    }

    $bd->build_spatial_index (resolutions => [100000, 100000]);

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => [qw /calc_richness/],
    );

    my $prng_seed = 2345;

    my $rand_name = 'rand_structured_subset';

    my $rand_object = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand_object->run_analysis (
        function   => 'rand_structured',
        iterations => 3,
        seed       => $prng_seed,
        return_rand_bd_array => 1,
        spatial_condition_for_subsets => 'sp_block(size => 1000000)',
        definition_query     => $def_query,
    );

    subtest "group and label sets match" => sub {
        my @obs_gps = sort $bd->get_groups;
        my @obs_lbs = sort $bd->get_labels;
        my $i = -1;
        foreach my $rand_bd (@$rand_bd_array) {
            $i++;
            my @rand_gps = sort $rand_bd->get_groups;
            my @rand_lbs = sort $rand_bd->get_labels;
            is (\@rand_gps, \@obs_gps, "group sets match for iteration $i");
            is (\@rand_lbs, \@obs_lbs, "label sets match for iteration $i");
        }
    };

    check_randomisation_results_differ ($rand_object, $bd, $rand_bd_array);

    return ($rand_object, $bd, $rand_bd_array);
}

sub test_rand_labels_all_constant {
    my $c  = 100000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);

    #  add a couple of empty groups
    foreach my $i (1 .. 2) {
        my $x = $i * -$c + $c / 2;
        my $y = -$c / 2;
        my $gp = "$x:$y";
        $bd->add_element (group => $gp, allow_empty_groups => 1);
    }

    $bd->build_spatial_index (resolutions => [$c, $c]);

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => [qw /calc_richness/],
    );

    my $prng_seed = 2345;

    my $rand_name = 'rand_labels_held_constant';

    my $labels_not_to_randomise = $bd->get_labels;

    my $rand_object = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand_object->run_analysis (
        function   => 'rand_structured',
        iterations => 2,
        seed       => $prng_seed,
        return_rand_bd_array => 1,
        #spatial_conditions_for_subset => 'sp_block(size => 1000000)',
        labels_not_to_randomise => $labels_not_to_randomise,
    );

    subtest 'Constant label ranges are unchanged when all are constant' => sub {
        my $i = -1;
        foreach my $rand_bd (@$rand_bd_array) {
            $i++;
            foreach my $label (@$labels_not_to_randomise) {
                no autovivification;
                my $old_range = $bd->get_groups_with_label_as_hash (label => $label);
                my $new_range = $rand_bd->get_groups_with_label_as_hash (label => $label);
                is ($new_range, $old_range, "Range matches for $label, randomisation $i");
            }
        }
    };
}

sub test_rand_labels_constant {

    my $c  = 100000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);

    #  add a couple of empty groups
    foreach my $i (1 .. 2) {
        my $x = $i * -$c + $c / 2;
        my $y = -$c / 2;
        my $gp = "$x:$y";
        $bd->add_element (group => $gp, allow_empty_groups => 1);
    }

    $bd->build_spatial_index (resolutions => [$c, $c]);

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => [qw /calc_richness/],
    );

    my $prng_seed = 2345;

    my $rand_name = 'rand_labels_held_constant';

    my $labels_not_to_randomise = [qw/Genus:sp22 Genus:sp28 Genus:sp31 Genus:sp16 Genus:sp18/];

    my $rand_object = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand_object->run_analysis (
        function   => 'rand_structured',
        iterations => 2,
        seed       => $prng_seed,
        return_rand_bd_array => 1,
        spatial_conditions_for_subset => 'sp_block(size => 1000000)',
        labels_not_to_randomise => $labels_not_to_randomise,
    );

    #  check ranges are identical for the constants
    subtest 'Constant label ranges are unchanged' => sub {
        my $i = -1;
        foreach my $rand_bd (@$rand_bd_array) {
            $i++;
            foreach my $label (@$labels_not_to_randomise) {
                no autovivification;
                my $old_range = $bd->get_groups_with_label_as_hash (label => $label);
                my $new_range = $rand_bd->get_groups_with_label_as_hash (label => $label);
                is ($new_range, $old_range, "Range matches for $label, randomisation $i");
            }
        }
    };

    check_randomisation_results_differ ($rand_object, $bd, $rand_bd_array);
    
    return ($rand_object, $bd, $rand_bd_array);
}


#  Are the differing input methods for constant labels stable?
sub test_rand_constant_labels_differing_input_methods {

    my $c  = 100000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);

    #  add a couple of empty groups
    foreach my $i (1 .. 2) {
        my $x = $i * -$c + $c / 2;
        my $y = -$c / 2;
        my $gp = "$x:$y";
        $bd->add_element (group => $gp, allow_empty_groups => 1);
    }

    $bd->build_spatial_index (resolutions => [$c, $c]);

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => [qw /calc_richness/],
    );

    my $prng_seed = 2345;

    my $rand_name = 'rand_labels_held_constant';

    my $labels_not_to_randomise_array = [qw/Genus:sp22 Genus:sp28 Genus:sp31 Genus:sp16 Genus:sp18/];
    my $labels_not_to_randomise_text = join "\n", @$labels_not_to_randomise_array;
    my %labels_not_to_randomise_hash;
    @labels_not_to_randomise_hash{@$labels_not_to_randomise_array}
      = (1) x scalar @$labels_not_to_randomise_array;
    my $labels_not_to_randomise_text_h = join "\n", %labels_not_to_randomise_hash;
    
    my %args = (
        function   => 'rand_structured',
        iterations => 1,
        seed       => $prng_seed,
        return_rand_bd_array => 1,
        spatial_conditions_for_subset => 'sp_block(size => 1000000)',
    );

    my $rand_object_a = $bd->add_randomisation_output (name => $rand_name . '_a');
    my $rand_bd_array_a = $rand_object_a->run_analysis (
        %args,
        labels_not_to_randomise => $labels_not_to_randomise_array,
    );

    my $rand_object_t = $bd->add_randomisation_output (name => $rand_name . '_t');
    my $rand_bd_array_t = $rand_object_t->run_analysis (
        %args,
        labels_not_to_randomise => $labels_not_to_randomise_text,
    );
    
    my $rand_object_th = $bd->add_randomisation_output (name => $rand_name . '_th');
    my $rand_bd_array_th = $rand_object_th->run_analysis (
        %args,
        labels_not_to_randomise => $labels_not_to_randomise_text_h,
    );

    subtest "array and text variants result in same labels held constant" => sub {
        my $bd_a  = $rand_bd_array_a->[0];
        my $bd_t  = $rand_bd_array_t->[0];
        my $bd_th = $rand_bd_array_th->[0];

        for my $gp ($bd->get_groups) {
            my $expected = scalar $bd_a->get_labels_in_group_as_hash (group => $gp);
            is (
                scalar $bd_t->get_labels_in_group_as_hash (group => $gp),
                $expected,
                $gp,
            );
            is (
                scalar $bd_th->get_labels_in_group_as_hash (group => $gp),
                $expected,
                $gp,
            );
        }
    }

}

sub check_randomisation_results_differ {
    my ($rand_object, $bd, $rand_bd_array) = @_;
    
    my $rand_name = $rand_object->get_name;
    
    #  need to refactor these subtests
    subtest "Labels in groups differ $rand_name" => sub {
        my $i = 0;
        foreach my $rand_bd (@$rand_bd_array) {
            my $match_count = 0;
            my $expected_count = 0;
            foreach my $group (sort $rand_bd->get_groups) {
                my $labels      = $bd->get_labels_in_group_as_hash (group => $group);
                my $rand_labels = $rand_bd->get_labels_in_group_as_hash (group => $group);
                $match_count    += grep {exists $labels->{$_}} keys %$rand_labels;
                $expected_count += scalar keys %$labels;
            }
            isnt ($match_count, $expected_count, "contents differ, rand_bd $i");
        }
        $i++;
    };

    subtest "richness scores match for $rand_name" => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $group (sort $rand_bd->get_groups) {
                my $bd_richness = $bd->get_richness(element => $group) // 0;
                is ($rand_bd->get_richness (element => $group) // 0,
                    $bd_richness,
                    "richness for $group matches",
                );
            }
        }
    };
    subtest "range scores match for $rand_name" => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $label ($rand_bd->get_labels) {
                is ($rand_bd->get_range (element => $label),
                    $bd->get_range (element => $label),
                    "range for $label matches",
                );
            }
        }
    };
    
}


#  obsolete now?
#  need to implement this for randomisations
sub check_order_is_same_given_same_prng {
    my %args = @_;
    my $bd = $args{basedata_ref};
    
    my $prng_seed = $args{prng_seed} || $default_prng_seed;
    
}



#  check that default args are assigned using the function metadata
sub test_default_args_assigned {
    my $bd = Biodiverse::BaseData->new(CELL_SIZES => [1,1], NAME => 'test_default_args_assigned');
    $bd->add_element (group => '0.5:0.5', label => 'fnort');
    
    my $sp = $bd->add_spatial_output (name => 'sp_placeholder');
    $sp->run_analysis (calculations => ['calc_richness'], spatial_conditions => ['sp_self_only()']);

    #  no need to do all of them
    foreach my $function (qw /rand_diffusion rand_nochange rand_csr_by_group/) {

        my $rand = $bd->add_randomisation_output (name => "$function check defaults assigned");
        $rand->run_analysis (function => $function, iterations => 1);

        my $args_hash = $rand->get_param('ARGS');

        my $metadata   = $rand->get_metadata(sub => $function);
        my $parameters = $metadata->get_parameters;

        subtest "Parameters for $function" => sub {
            foreach my $p (@$parameters) {
                my $p_name = $p->get_name;
                ok exists $args_hash->{$p_name}, "$p_name exists";
                my $default = $p->get_default_param_value;
                is $args_hash->{$p_name}, $default, "$p_name was set to default value";
            }
        }
    }
}


sub test_group_properties_reassigned_subset_rand {
    my %args = (
        spatial_conditions_for_subset => 'sp_block (size => 1000000)',
    );

    #  get a basedata aftr we have run some tests on it first
    my $bd = test_group_properties_reassigned(%args);

    my @sp_outputs = $bd->get_spatial_output_refs;
    my $sp = $sp_outputs[0];

    subtest 'Spatial analysis results are all tied for subset matching spatial condition' => sub {
        my @lists = grep {$_ =~ />>GP/} $sp->get_lists_across_elements;
        foreach my $element ($sp->get_element_list) {
            foreach my $list (@lists) {
                my $list_ref = $sp->get_list_ref (
                    element => $element,
                    list    => $list,
                    autovivify => 0,
                );
                my @keys = sort grep {$_ =~ /^T_/} keys %$list_ref;
                foreach my $key (@keys) {
                    is ($list_ref->{$key}, 1, "$list $element $key")
                }
            }
        }
    };

}

sub test_group_properties_reassigned {
    my %args = @_;

    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);

    my $rand_func   = 'rand_csr_by_group';
    my $object_name = 't_g_p_r';
    
    my $gp_props = get_group_properties_site_data_object();

    eval { $bd->assign_element_properties (
        type              => 'groups',
        properties_object => $gp_props,
    ) };
    my $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, 'Group properties assigned without eval error');

    #  name is short for sub name
    my $sp = $bd->add_spatial_output (name => 't_g_p_r');

    $sp->run_analysis (
        calculations => [qw /calc_gpprop_stats/],
        spatial_conditions => [
               $args{spatial_condition}
            // $args{spatial_conditions_for_subset}
            // 'sp_self_only()'
        ],
    );

    my %prop_handlers = (
        no_change => 0,
        by_set    => 1,
        by_item   => 1,
    );
    
    while (my ($props_func, $negate_expected) = each %prop_handlers) {

        my $rand_name   = 'r' . $object_name . $props_func;

        my $rand = $bd->add_randomisation_output (name => $rand_name);
        my $rand_bd_array = $rand->run_analysis (
            function   => $rand_func,
            iterations => 1,
            retain_outputs        => 1,
            return_rand_bd_array  => 1,
            randomise_group_props_by => $props_func,
        );
    
        my $rand_bd = $rand_bd_array->[0];
        my @refs = $rand_bd->get_spatial_output_refs;
        my $rand_sp = first {$_->get_param ('NAME') =~ m/^$object_name/} @refs;
    
        my $sub_same = sub {
            basedata_group_props_are_same (
                object1 => $bd,
                object2 => $rand_bd,
                negate  => $negate_expected,
            );
        };

        subtest "$props_func checks" => $sub_same;
    }

    return $bd;
}

sub test_label_properties_reassigned_with_condition {
    test_label_properties_reassigned (spatial_conditions_for_subset => 'sp_block (size => 300000)');
}

sub test_label_properties_reassigned {
    my %args = @_;

    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);

    my $rand_func   = 'rand_structured';
    my $object_name = 't_l_p_r';
    
    my $lb_props = get_label_properties_site_data_object();

    eval { $bd->assign_element_properties (
        type              => 'labels',
        properties_object => $lb_props,
    ) };
    my $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, 'Label properties assigned without eval error');
    
    my $prop_keys = $bd->get_labels_ref->get_element_property_keys;  #  trigger some caching which needs to be cleared
    #my $prop_keys = [];    

    #  name is short for sub name
    my $sp = $bd->add_spatial_output (name => 't_l_p_r');

    $sp->run_analysis (
        calculations => [qw /calc_lbprop_stats/],
        spatial_conditions => [
               $args{spatial_condition}
            // $args{spatial_conditions_for_subset}
            // 'sp_self_only()',
        ],
    );

    my %prop_handlers = (
        no_change => 0,
        #by_set    => 1,
        #by_item   => 1,
    );

    foreach my $props_func (sort keys %prop_handlers) {
        my $negate_expected = $prop_handlers{$props_func};

        my $rand_name   = 'r' . $object_name . $props_func;

        my $rand = $bd->add_randomisation_output (name => $rand_name);
        
        my $prng = $rand->initialise_rand;
        say "=====\n" . (join ' ', $prng->get_state) . "\n=====";
        
        my $rand_bd_array = $rand->run_analysis (
            %args,
            function   => $rand_func,
            iterations => 1,
            retain_outputs        => 1,
            return_rand_bd_array  => 1,
        );
    
        my $rand_bd = $rand_bd_array->[0];

        my $prop_keys_rand = $rand_bd->get_labels_ref->get_element_property_keys;
        is ($prop_keys_rand, $prop_keys, "Property keys match");
        
        my @refs = $rand_bd->get_spatial_output_refs;
        my $rand_sp = first {$_->get_param ('NAME') =~ m/^$object_name/} @refs;
    
        my $sub_same = sub {
            basedata_label_props_are_same (
                object1 => $bd,
                object2 => $rand_bd,
                negate  => $negate_expected,
            );
        };

        subtest "$props_func checks" => $sub_same;
    }

    return $bd;
}

sub test_randomise_tree_ref_args {
    my $rand_func   = 'rand_csr_by_group';
    my $object_name = 't_r_t_r_f';

    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);
    my $tree  = get_tree_object_from_sample_data();
    my $tree2 = $tree->clone;
    $tree2->shuffle_terminal_names;  # just to make it different
    $tree2->rename (new_name => 'tree2');
    
    #  name is short for sub name
    my $sp_self_only = $bd->add_spatial_output (name => 'self_only');
    $sp_self_only->run_analysis (
        calculations       => [qw /calc_pd/],
        spatial_conditions => ['sp_self_only()'],
        tree_ref           => $tree,
    );
    my $sp_select_all = $bd->add_spatial_output (name => 'select_all');
    $sp_select_all->run_analysis (
        calculations       => [qw /calc_pd/],
        spatial_conditions => ['sp_select_all()'],
        tree_ref           => $tree,
    );
    my $sp_tree2 = $bd->add_spatial_output (name => 'tree2');
    $sp_tree2->run_analysis (
        calculations       => [qw /calc_pd/],
        spatial_conditions => ['sp_self_only()'],
        tree_ref           => $tree2,
    );

    my $iter_count = 2;
    my %shuffle_method_hash = $tree->get_subs_with_prefix (prefix => 'shuffle');

    #  need to handle abbreviated forms
    my @tmp = sort keys %shuffle_method_hash;
    my @tmp2 = map {(my $x = $_) =~ s/^shuffle_//; $x} @tmp;
    my @shuffle_method_array = (@tmp, @tmp2);
    
    #diag 'testing tree shuffle methods: ' . join ' ', @shuffle_method_array;

    foreach my $shuffle_method (@shuffle_method_array) {
        my $use_is_or_isnt = ($shuffle_method !~ /no_change$/) ? 'isnt' : 'is';
        my $not_text = $use_is_or_isnt eq 'isnt' ? 'not' : '';
        my $notnot_text = $use_is_or_isnt eq 'isnt' ? '' : ' not';
        my $rand_name = 't_r_t_r_f_rand' . $shuffle_method;
        my $rand = $bd->add_randomisation_output (name => $rand_name);
        my $rand_bd_array = $rand->run_analysis (
            function             => 'rand_nochange',
            randomise_trees_by   => $shuffle_method,
            iterations           => $iter_count,
            retain_outputs       => 1,
            return_rand_bd_array => 1,
        );

        #  sp_self_only should be different, but sp_select_all should be the same
        my @groups = sort $sp_self_only->get_element_list;
        my $list_name = $rand_name . '>>SPATIAL_RESULTS';
        my %count_same;
        foreach my $gp (@groups) {
            my $list_ref_self_only = $sp_self_only->get_list_ref (
                element => $gp,
                list    => $list_name,
            );
            my $list_ref_select_all = $sp_select_all->get_list_ref (
                element => $gp,
                list    => $list_name,
            );
            my $list_ref_tree2 = $sp_tree2->get_list_ref (
                element => $gp,
                list    => $list_name,
            );

            $count_same{self_only}  += $list_ref_self_only->{T_PD} // 0;
            $count_same{select_all} += $list_ref_select_all->{T_PD} // 0;
            $count_same{tree2}      += $list_ref_tree2->{T_PD} // 0;
        }

        my $expected = $iter_count * scalar @groups;
        is ($count_same{select_all}, $expected, $shuffle_method . ': Global PD scores are same for orig and rand');
        my $check = is_or_isnt (
            $count_same{self_only},
            $expected,
            "$shuffle_method: Local PD scores $notnot_text same between orig and rand",
            $use_is_or_isnt,
        );
        $check = is_or_isnt (
            $count_same{tree2},
            $expected,
            "$shuffle_method: Local PD with tree2 scores $notnot_text same between orig and rand",
            $use_is_or_isnt,
        );

        my @analysis_args_array;

        #  and check we haven't overridden the original tree_ref
        for my $i (0 .. $#$rand_bd_array) {
            my $track_hash = {};
            push @analysis_args_array, $track_hash;
            my $rand_bd = $rand_bd_array->[$i];
            my @rand_sp_refs = $rand_bd->get_spatial_output_refs;
            for my $ref (@rand_sp_refs) {
                my $sp_name = $ref->get_param ('NAME');
                my @tmp = split ' ', $sp_name;  #  the first part of the name is the original
                my $sp_pfx = $tmp[0];

                my $analysis_args = $ref->get_param ('SP_CALC_ARGS');
                $track_hash->{$sp_pfx} = $analysis_args;

                my $rand_tree_ref = $analysis_args->{tree_ref};
                my $tree_ref_to_compare = $sp_pfx eq 'tree2' ? $tree2 : $tree;
                my $orig_tree_name = $tree_ref_to_compare->get_param ('NAME');

                if (($use_is_or_isnt // 'is') eq 'is') {
                    ref_is (
                        $tree_ref_to_compare,
                        $rand_tree_ref,
                        "$shuffle_method: Tree refs $not_text same, orig & " . $ref->get_param ('NAME'),
                    );
                }
                else {
                    ref_is_not (
                        $tree_ref_to_compare,
                        $rand_tree_ref,
                        "$shuffle_method: Tree refs $not_text same, orig & " . $ref->get_param ('NAME'),
                    );
                }
            }
        }
        #diag $tree . ' ' . $tree->get_param ('NAME');
        #diag $tree2 . ' ' . $tree2->get_param ('NAME');

        ref_is (
            $analysis_args_array[0]->{self_only}->{tree_ref},
            $analysis_args_array[0]->{select_all}->{tree_ref},
            "$shuffle_method: Shuffled tree refs $notnot_text same across randomisation iter 1",
        );
        ref_is (
            $analysis_args_array[1]->{self_only}->{tree_ref},
            $analysis_args_array[1]->{select_all}->{tree_ref},
            "$shuffle_method: Shuffled tree refs $notnot_text same across randomisation iter 2",
        );

        if (($use_is_or_isnt // 'is') eq 'is') {
            ref_is (
                $analysis_args_array[0]->{self_only}->{tree_ref},
                $analysis_args_array[1]->{self_only}->{tree_ref},
                "$shuffle_method: Shuffled tree refs $not_text same for different randomisation iter",
            );
        }
        else {
            ref_is_not (
                $analysis_args_array[0]->{self_only}->{tree_ref},
                $analysis_args_array[1]->{self_only}->{tree_ref},
                "$shuffle_method: Shuffled tree refs $not_text same for different randomisation iter",
            );
        }
    }

    return;
}


sub basedata_group_props_are_same {
    basedata_element_props_are_same (@_, type => 'groups');
}

sub basedata_label_props_are_same {
    basedata_element_props_are_same (@_, type => 'labels');
}

sub basedata_element_props_are_same {
    my %args = @_;
    my $bd1 = $args{object1};
    my $bd2 = $args{object2};
    my $negate_check = $args{negate};

    my ($el_ref1, $el_ref2);
    if ($args{type} eq 'labels') {
        $el_ref1 = $bd1->get_labels_ref;
        $el_ref2 = $bd2->get_labels_ref;
    }
    else {
        $el_ref1 = $bd1->get_groups_ref;
        $el_ref2 = $bd2->get_groups_ref;
    }

    my %elements1 = $el_ref1->get_element_hash;
    my %elements2 = $el_ref2->get_element_hash;

    is (scalar keys %elements1, scalar keys %elements2, 'objects have same number of elements');

    my $check_count;

    #  should also check we get the same number of defined values
    my $defined_count1 = my $defined_count2 = 0;
    my $sum1 = my $sum2 = 0;

    foreach my $el_name (sort keys %elements1) {
        my $list1 = $el_ref1->get_list_ref (element => $el_name, list => 'PROPERTIES');
        my $list2 = $el_ref2->get_list_ref (element => $el_name, list => 'PROPERTIES');

        my @tmp;
        @tmp = grep {defined $_} values %$list1;
        $defined_count1 += @tmp;
        $sum1 += sum0 @tmp;
        @tmp = grep {defined $_} values %$list2;
        $defined_count2 += @tmp;
        $sum2 += sum0 @tmp;

        if (eq_deeply ($list1, $list2)) {
            $check_count ++;
        }
    }

    my $text = ucfirst ($args{type}) . ' property sets ';
    $text .= $negate_check ? 'differ' : 'are the same';

    if ($negate_check) {
        isnt ($check_count, scalar keys %elements1, $text);
    }
    else {
        is ($check_count, scalar keys %elements1, $text);
    }

    #  useful so long as we guarantee randomised basedata will have the same groups as the orig
    is ($defined_count1, $defined_count2, 'Same number of properties with defined values');
    is ($sum1, $sum2, 'Sum of properties is the same');

    return;
}




#   Does the PRNG state vector work or throw a trapped exception
#  This is needed because Math::Random::MT::Auto uses state vectors with
#  differing bit sizes, depending on whether 32 or 64 bit ints are used by perl.
#  #  skip it for now
sub _test_prng_state_vector {
    use Config;

    #  will this work on non-windows systems? 
    my $bit_size = $Config{archname} =~ /x86/ ? 32 : 64;  #  will 128 bits ever be needed for this work?
    my $wrong_bit_size = $Config{archname} =~ /x86/ ? 64 : 32;
    my $bd = Biodiverse::BaseData->new(NAME => 'PRNG tester', CELL_SIZES => [1, 1]);

    my $data_section_name = "PRNG_STATE_${bit_size}BIT";
    my $state_vector = get_data_section ($data_section_name);
    $state_vector = eval $state_vector;
    diag "Problem with data section $data_section_name: $EVAL_ERROR" if $EVAL_ERROR;
    my ($err, $prng);

    eval {
        $prng = $bd->initialise_rand (state => $state_vector);
    };
    $err = $@ ? 0 : 1;
    ok ($err, "Initialise PRNG with $bit_size bit vector and did not received an error");
    
    my $other_data_section_name = "PRNG_STATE_${wrong_bit_size}BIT";
    my $wrong_state_vector = get_data_section ($other_data_section_name);
    $wrong_state_vector = eval $wrong_state_vector;

    eval {
        $prng = $bd->initialise_rand (state => $wrong_state_vector);
    };
    my $e = $EVAL_ERROR;
    $err = Biodiverse::PRNG::InvalidStateVector->caught ? 1 : 0;
    #diag $e;
    ok ($err, "Initialise PRNG with $wrong_bit_size bit vector and caught the error as expected");

}

######################################

sub test_metadata {
    my $bd = Biodiverse::BaseData->new(CELL_SIZES => [1,1]);
    my $object = eval {Biodiverse::Randomise->new(BASEDATA_REF => $bd)};

    my $pfx = 'get_metadata_rand_';  #  but avoid export subs
    my $x = $object->get_subs_with_prefix (prefix => $pfx);
    
    my %meta_keys;

    my (%descr, %parameters);
    foreach my $meta_sub (keys %$x) {
        my $calc = $meta_sub;
        $calc =~ s/^get_metadata_//;

        my $metadata = $object->get_metadata (sub => $calc);

        $descr{$metadata->get_description}{$meta_sub}++;
        
        @meta_keys{keys %$metadata} = (1) x scalar keys %$metadata;
    }

    subtest 'No duplicate descriptions' => sub {
        check_duplicates (\%descr);
    };
}

sub check_duplicates {
    my $hashref = shift;
    foreach my $key (sort keys %$hashref) {
        my $count = scalar keys %{$hashref->{$key}};
        my $res = is ($count, 1, "$key is unique");
        if (!$res) {
            diag "Source calcs for $key are: " . join ' ', sort keys %{$hashref->{$key}};
        }
    }
    foreach my $null_key (qw /no_name no_description/) {
        my $res = ok (!exists $hashref->{$null_key}, "hash does not contain $null_key");
        if (exists $hashref->{$null_key}) {
            diag "Source calcs for $null_key are: " . join ' ', sort keys %{$hashref->{$null_key}};
        }
    }    
    
}




#######
#  Do we get exact replicates given the default args and a set PRNG seed?
#  Initial version only checks defaults - should probably add some permutations
#  based on metadata.
sub test_function_stability {
    my $c  = 1;
    my $c2 = $c / 2;
    my $bd = Biodiverse::BaseData->new(
        CELL_SIZES => [$c, $c],
        NAME       => 'test_replicates',
    );

    #  we just need some groups and labels
    my %labels = (1 => 'a', 2 => 'b', 3 => 'c', 4 => 'd');
    foreach my $x (1 .. 4) {
        foreach my $y (1 .. 4) {
          LABEL_ID:
            foreach my $label_id (sort keys %labels) {
                next LABEL_ID if $label_id < $x;
                my $label = $labels{$label_id};
                my $gp = ($x + $c2 . ':' . ($y + $c2));
                $bd->add_element (
                    label => $label,
                    group => $gp,
                    count => $x * $y,
                );
            }
        }
    }
    #  and add a row of empties
    foreach my $x (1 .. 4) {
        my $y = 0;
        my $gp = ($x + $c2 . ':' . ($y + $c2));
        $bd->add_element (group => $gp, count => 0);
    }

    my $prng_seed = 2345;
    
    $bd->build_spatial_index (resolutions => [$c, $c]);
    my $sp //= $bd->add_spatial_output (name => 'sp');
    
    my $r_spatially_structured_cond = "sp_circle (radius => $c)";
    my $c3 = $c * 3;
    $r_spatially_structured_cond = "sp_block (size => $c3)";
    
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [qw /calc_richness calc_element_lists_used calc_elements_used/],
    );

    use Biodiverse::Randomise;
    my @functions = Biodiverse::Randomise->get_randomisation_functions_as_array;
    @functions = sort @functions;
    
    my %extra_args_per_func = (
        rand_independent_swaps => {swap_count => 1000},
    );
    
    foreach my $function (@functions) {
        my $rand = $bd->add_randomisation_output (name => $function);
        my $extra_args = $extra_args_per_func{$function};
        $extra_args //= {};
        
        my %rand_func_args = (
            function   => $function,
            iterations => 1,
            seed       => $prng_seed,
            return_rand_bd_array => 1,
            %$extra_args,
        );

        my $metadata = $rand->get_metadata (sub => $function);
        my $parameters = $metadata->get_parameters;
        my $uses_spatial_allocation
          = grep {$_->get_name eq 'spatial_conditions_for_label_allocation'}
            @$parameters;
        if ($uses_spatial_allocation) {
            $rand_func_args{spatial_conditions_for_label_allocation}
              = $r_spatially_structured_cond;
        }

        my $rand_bd_array = $rand->run_analysis (%rand_func_args);
        my $rand_bd = $rand_bd_array->[0];

        my %got;
        foreach my $gp_name ($rand_bd->get_groups) {
            $got{$gp_name} = $rand_bd->get_labels_in_group_as_hash(group => $gp_name);
        }

        my $generate_result_sets = 0;
        my $expected = {};  #  make sure we fail if generation is left on

        if ($generate_result_sets) {
            my $fh = get_randomisation_result_set_fh($function);
            print_randomisation_result_set_to_fh($fh, \%got, $function);
        }
        else {
            my $data_section_name = "RAND_RESULTS_$function";
            my $exp_data = get_data_section ($data_section_name);
            $expected = eval $exp_data;
        }

        is (\%got, $expected, "Stability check: Expected results for $function");
    }

    return;
}

#  a todo test until we resolve issue #588
sub test_spatial_allocation_order_fails {
    #  this needs refactoring
    my $c  = 1;
    my $c2 = $c / 2;
    my $bd = Biodiverse::BaseData->new(CELL_SIZES => [$c, $c], NAME => 'test_replicates');

    #  we just need some groups and labels
    my %labels = (1 => 'a', 2 => 'b', 3 => 'c', 4 => 'd');
    foreach my $x (1 .. 4) {
        foreach my $y (1 .. 4) {
          LABEL_ID:
            foreach my $label_id (keys %labels) {
                next LABEL_ID if $label_id < $x;
                my $label = $labels{$label_id};
                my $gp = ($x + $c2 . ':' . ($y + $c2));
                $bd->add_element (label => $label, group => $gp, count => $x * $y);
            }
        }
    }
    #  and add a row of empties
    foreach my $x (1 .. 4) {
        my $y = 0;
        my $gp = ($x + $c2 . ':' . ($y + $c2));
        $bd->add_element (group => $gp, count => 0);
    }
    
    my $prng_seed = 2345;
    
    #$bd->build_spatial_index (resolutions => [$c, $c]);
    my $sp //= $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [qw /calc_richness/],
    );

    use Biodiverse::Randomise;
    my $rand = $bd->add_randomisation_output (name => 'alloc_order_should_not_exist');

    my %rand_func_args = (
        function   => 'rand_spatially_structured',
        iterations => 1,
        seed       => $prng_seed,
        return_rand_bd_array => 1,
        retain_outputs       => 1,
        track_label_allocation_order => 1,
        spatial_conditions_for_label_allocation => 'sp_circle (radius => 1)',
    );

    my $rand_bd_array = $rand->run_analysis (
        %rand_func_args,
        spatial_conditions_for_subset => '$x == $nbr_x',
    );
    my $rand_bd = $rand_bd_array->[0];

    my $spatial_outputs = $rand_bd->get_spatial_output_names;
    my $has_label_alloc_sp = grep {$_ eq 'sp_to_track_allocations'} @$spatial_outputs;

    {
        my $todo = todo 'Issue #588';
        ok ($has_label_alloc_sp, 'We have a label allocation output when the randomisation involves mergers');
    }
    
    #  this one should have such an output
    $rand = $bd->add_randomisation_output (name => 'alloc_order_should_exist');
    $rand_bd_array = $rand->run_analysis (
        %rand_func_args,
    );
    $rand_bd = $rand_bd_array->[0];

    $spatial_outputs = $rand_bd->get_spatial_output_names;
    $has_label_alloc_sp = grep {$_ eq 'sp_to_track_allocations'} @$spatial_outputs;

    ok ($has_label_alloc_sp, 'We have a label allocation output when the randomisation does not involve mergers');
}


#  do we correctly calculate significance?
#  issue #607
#  a bit clunky in the testing
sub test_p_ranks  {
    #  the basedata generation desperately needs refactoring - it is used in too many places
    my $c  = 1;
    my $c2 = $c / 2;
    my $bd = Biodiverse::BaseData->new(CELL_SIZES => [$c, $c], NAME => 'test_replicates');

    #  we just need some groups and labels
    my %labels = (1 => 'a', 2 => 'b', 3 => 'c', 4 => 'd');
    foreach my $x (1 .. 4) {
        foreach my $y (1 .. 4) {
          LABEL_ID:
            foreach my $label_id (keys %labels) {
                next LABEL_ID if $label_id < $x;
                my $label = $labels{$label_id};
                my $gp = ($x + $c2 . ':' . ($y + $c2));
                $bd->add_element (label => $label, group => $gp, count => $x * $y);
            }
        }
    }
    #  and add a row of empties
    foreach my $x (1 .. 4) {
        my $y = 0;
        my $gp = ($x + $c2 . ':' . ($y + $c2));
        $bd->add_element (group => $gp, count => 0);
    }
    
    my $prng_seed = 2345;
    
    #$bd->build_spatial_index (resolutions => [$c, $c]);
    my $sp //= $bd->add_spatial_output (name => 'sp');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [qw /calc_endemism_whole calc_endemism_whole_lists/],
    );
    #  we want a set of calcs per node
    my $cl //= $bd->add_cluster_output (name => 'cl');
    $cl->run_analysis (
        spatial_calculations => [qw /calc_endemism_whole/],
    );
    
    my $rand = $bd->add_randomisation_output (name => 'rr');

    my %rand_func_args = (
        function   => 'rand_csr_by_group',
        iterations => 8,
        seed       => $prng_seed,
        #return_rand_bd_array => 1,
        #retain_outputs       => 1,
    );
    $rand->run_analysis (%rand_func_args);
    # need one more iteration to be sure we don't add extra lists
    $rand->run_analysis (iterations => 1);  

    my @lists_across_elements = $sp->get_lists_across_elements;
    my $count = grep {$_ =~ /p_rank>>p_rank>>/} @lists_across_elements;
    is ($count, 0, 'no doubled p_rank lists');
    
    my @bounds = (0.05, 0.95);

    subtest 'sig_thresh results valid for spatial object' => sub {
        my $defined_count = 0;
        foreach my $gp ($sp->get_element_list) {
            my $sig_listref = $sp->get_list_ref (
                element    => $gp,
                list       => "rr>>p_rank>>SPATIAL_RESULTS",
                autovivify => 0,
            );
            my $rand_listref = $sp->get_list_ref (
                element    => $gp,
                list       => "rr>>SPATIAL_RESULTS",
                autovivify => 0,
            );
            my %expected_keys;
            foreach my $key (grep {/^Q_/} keys %$rand_listref) {
                $key =~ s/^Q_//;
                $expected_keys{$key}++;
            }
            is (
                [sort keys %$sig_listref],
                [sort keys %expected_keys],
                "got expected keys for $gp",
            );
            #  values are undef for non-sig, or the sig thresh passed (low is negated) 
            foreach my $key (sort keys %$sig_listref) {
                my $value = $sig_listref->{$key};
                if (defined $value) {
                    $defined_count++;
                    ok ($value < $bounds[0] || $value > $bounds[1], "$value in valid interval ($key), $gp");
                }
            }
        }
        ok ($defined_count, "At least some spatial sig values were defined (got $defined_count)");
    };

    subtest 'sig_thresh results valid for cluster object' => sub {
        my $defined_count = 0;
        foreach my $node ($cl->get_node_refs) {    
            my $node_name = $node->get_name;
            my $sig_listref = $node->get_list_ref (
                list       => "rr>>p_rank>>SPATIAL_RESULTS",
                autovivify => 0,
            );
            my $rand_listref = $node->get_list_ref (
                list       => "rr>>SPATIAL_RESULTS",
                autovivify => 0,
            );
            my %expected_keys;
            foreach my $key (grep {/^Q_/} keys %$rand_listref) {
                #  all indices should have a corresponding Q_ key
                $key =~ s/^Q_//;
                $expected_keys{$key}++;
            }
            is (
                [sort keys %$sig_listref],
                [sort keys %expected_keys],
                "got expected keys for $node_name",
            );
            #  values are undef for non-sig, or the sig thresh passed (low is negated) 
            foreach my $key (sort keys %$sig_listref) {
                my $value = $sig_listref->{$key};
                if (defined $value) {
                    $defined_count++;
                    #  use eq, not ==, due to floating point issues with 0.1
                    ok ($value < $bounds[0] || $value > $bounds[1], "$value in valid interval ($key), $node_name");
                }
            }
        }
        ok ($defined_count, "At least some cluster node sig values were defined (got $defined_count)");
    };
}



#  not used currently - still need to test?
sub test_p_rank_thresh_calcs {
    my $bd = Biodiverse::BaseData->new(NAME => 'test_p_ranks', CELL_SIZES => [1,1]);
    
    #  set things up in one go for clarity, then subdivide
    my %setup = (
        # these are middle of the field
        'fail2_0.95'  => undef,  'C_fail2_0.95'  =>  600,
        'fail2_0.05'  => undef,  'C_fail2_0.05'  =>  400,    
        #  these fail lower thresholds due to ties
        'failt1_0.05' => undef,  'C_failt1_0.05' =>   49, 'T_failt1_0.05' => 1,
        'failt2_0.05' => undef,  'C_failt2_0.05' =>   40, 'T_failt2_0.05' => 10,
        'failt3_0.05' => undef,  'C_failt3_0.05' =>   0,  'T_failt3_0.05' => 50,
    );

    #  create data for either side of boundaries
    my $prev_thresh = undef;
    foreach my $thresh (0.95, 0.975, 0.99, 0.995) {
        $setup{'pass_' . $thresh} = $thresh;
        $setup{'C_pass_' . $thresh} = $thresh * 1000 + 1;
        $setup{'fail_' . $thresh} = $prev_thresh;
        $setup{'C_fail_' . $thresh} = $thresh * 1000;        
        $prev_thresh = $thresh;
    }
    $prev_thresh = undef;
    foreach my $thresh (0.05, 0.025, 0.01, 0.005) {
        $setup{'pass_' . $thresh} = $thresh;
        $setup{'C_pass_' . $thresh} = $thresh * 1000 - 1;
        $setup{'fail_' . $thresh} = $prev_thresh;
        $setup{'C_fail_' . $thresh} = $thresh * 1000;        
        $prev_thresh = $thresh;
    }
    
    my %expected
        = map {$_ => $setup{$_}}
          grep {$_ =~ /^(pass|fail)/}
          keys %setup;

    my %check_hash = %setup;
    delete @check_hash{keys %expected};

    #  mind the P_ and Q_ scores    
    foreach my $key (grep {$_ =~ /^C_/} keys %check_hash) {
        my $Q_key = $key;
        $Q_key =~ s/^C/Q/;
        $check_hash{$Q_key} = 1000;
        my $P_key = $key;
        $P_key =~ s/^C/P/;
        $check_hash{$P_key} = $check_hash{$key} / 1000;
    }
    
    my $p_rank = $bd->get_sig_rank_threshold_from_comp_results (
        comp_list_ref => \%check_hash,
    );
    
    is ($p_rank, \%expected, 'got expected p-rank thresholds');
    
    #use Data::Dumper qw/Dumper/;
    #local $Data::Dumper::Sortkeys = 1;
    #say Dumper \%check_hash;
    #say Dumper $p_rank;
}

sub test_p_rank_calcs {
    my $bd = Biodiverse::BaseData->new(NAME => 'test_p_ranks', CELL_SIZES => [1,1]);
    
    #  set things up in one go for clarity, then subdivide
    my %setup = (
        # these are middle of the field
        'fail2_0.95'  => undef,  'C_fail2_0.95'  =>  600,
        'fail2_0.05'  => undef,  'C_fail2_0.05'  =>  400,    
        #  these fail lower thresholds due to ties
        'failt1_0.05' => undef,  'C_failt1_0.05' =>   49, 'T_failt1_0.05' => 1,
        'failt2_0.05' => undef,  'C_failt2_0.05' =>   40, 'T_failt2_0.05' => 10,
        'failt3_0.05' => undef,  'C_failt3_0.05' =>   0,  'T_failt3_0.05' => 50,
    );

    #  create data for either side of boundaries
    #  loop is a left-over from when it was testing multiple thresholds
    my $prev_thresh = undef;
    foreach my $thresh (0.95) {
        $setup{'pass_' . $thresh} = 0.951;
        $setup{'C_pass_' . $thresh} = $thresh * 1000 + 1;
        $setup{'fail_' . $thresh} = $prev_thresh;
        $setup{'C_fail_' . $thresh} = $thresh * 1000;        
        $prev_thresh = $thresh;
    }
    $prev_thresh = undef;
    foreach my $thresh (0.05) {
        $setup{'pass_' . $thresh} = 0.049;
        $setup{'C_pass_' . $thresh} = $thresh * 1000 - 1;
        $setup{'fail_' . $thresh} = $prev_thresh;
        $setup{'C_fail_' . $thresh} = $thresh * 1000;        
        $prev_thresh = $thresh;
    }
    
    my %expected
        = map {$_ => $setup{$_}}
          grep {$_ =~ /^(pass|fail)/}
          keys %setup;

    my %check_hash = %setup;
    delete @check_hash{keys %expected};

    #  mind the P_ and Q_ scores    
    foreach my $key (grep {$_ =~ /^C_/} keys %check_hash) {
        my $Q_key = $key;
        $Q_key =~ s/^C/Q/;
        $check_hash{$Q_key} = 1000;
        my $P_key = $key;
        $P_key =~ s/^C/P/;
        $check_hash{$P_key} = $check_hash{$key} / 1000;
    }
    
    my $p_rank = $bd->get_sig_rank_from_comp_results (
        comp_list_ref => \%check_hash,
    );
    
    is ($p_rank, \%expected, 'got expected p-ranks');
    
    #use Data::Dumper qw/Dumper/;
    #local $Data::Dumper::Sortkeys = 1;
    #say Dumper \%check_hash;
    #say Dumper $p_rank;
}

#  put the results sets into a file
#  returns null if not needed
sub get_randomisation_result_set_fh {
    return if !@_;

    my $function = shift;
    
    my $file_name = $0;
    $file_name =~ s/\.t$/\./;
    $file_name .= $function . '.results';
    open(my $fh, '>', $file_name) or die "Unable to open $file_name to write results sets to";
    
    return $fh;
}


# Used for acquiring randomisation results for stability checks
sub print_randomisation_result_set_to_fh {
    my ($fh, $results_hash, $function) = @_;

    return if !$fh;

    use Perl::Tidy;
    use Data::Dumper;

    local $Data::Dumper::Purity    = 1;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Quotekeys = 0;
    #say '#' x 20;

    my $source_string = Dumper($results_hash);
    my $dest_string;
    my $stderr_string;
    my $errorfile_string;
    my $argv = "-npro";   # Ignore any .perltidyrc at this site
    $argv .= " -pbp";     # Format according to perl best practices
    $argv .= " -nst";     # Must turn off -st in case -pbp is specified
    $argv .= " -se";      # -se appends the errorfile to stderr
    $argv .= " -no-log";  # Don't write the log file

    my $error = Perl::Tidy::perltidy(
        argv        => $argv,
        source      => \$source_string,
        destination => \$dest_string,
        stderr      => \$stderr_string,
        errorfile   => \$errorfile_string,    # ignored when -se flag is set
        ##phasers   => 'stun',                # uncomment to trigger an error
    );

    say   {$fh} "@@ RAND_RESULTS_${function}";
    say   {$fh} $dest_string;
    print {$fh} "\n";
    #say '#' x 20;

    return;   
}


1;

__DATA__

@@ PRNG_STATE_64BIT
[
    '9223372036854775808',  '4958489735850631625',
    '3619538152624353803',  '17619357754638794221',
    '3408623266403198899',  '3035490222614631823',
    '271946905883112210',   '16298790926339482536',
    '630676991166359904',   '14788619200023795801',
    '14177757664934255970', '13312478727237553858',
    '15476291270995261633', '5464336263206175489',
    '3143797466762002238',  '5582226352878082351',
    '9355217794169585449',  '14954185062673067088',
    '13522961949994510900', '14585430878973889682',
    '15924956595200372592', '12957488009475900218',
    '3752159734236408285',  '8369919639039867954',
    '10795054750735369199', '8642694099373695299',
    '11272165358781081802', '8095615318554781864',
    '16164398991258853417', '10214091818020347210',
    '13153307184336129803', '13714936695152479161',
    '14484154332356276242', '2577462502853318753',
    '10892102228724345544', '15649984586148205750',
    '1752911930694051119',  '14256522304070138671',
    '1152514005473346248',  '8878671455732451000',
    '4207011014252715669',  '13652367961887395862',
    '5611121218550033658',  '8410402991626261946',
    '8233552525575717271',  '6292412120693398487',
    '9947060654524186474',  '16452782021149028831',
    '1853809132293241168',  '15295782352943437746',
    '12182836555484474747', '3552537677350983349',
    '4772066490831483028',  '12530387288245283208',
    '2890677614665248002',  '2667778419916946144',
    '13498338834241598773', '3154952819132335662',
    '13136666044524597473', '892231094817090569',
    '6585118713301352248',  '4930807954933263060',
    '393610034222314258',   '9558892454914352311',
    '30391966624547120',    '5737918409669945728',
    '4721863252461715725',  '17822207361415571270',
    '9577190201430126402',  '1668742975331543542',
    '15098079975897000051', '9241685836129752967',
    '307391855222642978',   '3304579349183387324',
    '11536685329583252079', '5331993793107319461',
    '5113958467189033722',  '18047865119982959952',
    '6112450261981011688',  '10497757696563184785',
    '749432990441663821',   '10185360822522782666',
    '13454434027282212678', '8125745829336032455',
    '14578461652467528442', '9025987670267739720',
    '17704075490770296829', '10343467620534394694',
    '9867154291727482127',  '2573568889838705240',
    '496072485004533342',   '8499502629657380215',
    '1639931171450583369',  '13149339736314161754',
    '4509242601634876170',  '17086167746054763781',
    '1466208730962794210',  '12558159049585594774',
    '14228643326355589021', '16816774882560166758',
    '5362869153989396529',  '6649026195586597463',
    '2832638462722326548',  '15771554561130648152',
    '15182170535546589898', '1541713252841628024',
    '9744675815954163941',  '8180333156316991695',
    '2624783631851392728',  '6642975270114609940',
    '4972071798944670000',  '15841513508277459488',
    '588709670153485747',   '7085330046324581946',
    '16603019887526878011', '4801164143465887004',
    '3997253492253168259',  '17211327089365224247',
    '11793831301662350681', '8135626700252115563',
    '18173415094141338016', '5512542829692575457',
    '709091886933108421',   '7928604951070279249',
    '15240575422913751071', '18306141964501345053',
    '16334960027211470821', '3998691902608686113',
    '13299894194976580456', '6706267612186690863',
    '15163430571254651907', '16212811501888570899',
    '4278032876639688811',  '11967866805397329675',
    '8264417510725672387',  '14651307437899294260',
    '5647624225666950973',  '3957567384005933380',
    '9366323499722880371',  '3128213604362951206',
    '3741646501934840613',  '8714663898836549487',
    '14093434233595461889', '4367208835592170128',
    '11635918534111679335', '5521363475906617593',
    '3603525324242875832',  '6215692381355809233',
    '14905568142005052977', '11923988872476621110',
    '3839765323127405824',  '1726494672043031059',
    '1826046517924485331',  '949980670827882141',
    '16243826921596841486', '1854042729235477350',
    '13530891740661473592', '9644281674066925572',
    '14247280631769143765', '5626502556766574951',
    '1197448132108257968',  '15553409925595149925',
    '845565928621523794',   '15653846230542429524',
    '13430817514199604511', '18355820233222203385',
    '13326758935638574278', '3322902917203750159',
    '11058297162745705933', '13685287326600736054',
    '4975206220742183364',  '9272608019685092152',
    '4418791405556974337',  '18308885101215662544',
    '15033949912219345853', '15828581325838662108',
    '4360364515778590425',  '11702117311272622689',
    '8542874060716897202',  '5619994636706585426',
    '13524161066520536811', '1746470960343741172',
    '3531265041003896570',  '3995081388934980117',
    '6577196340494974021',  '15275042596192483519',
    '6827660007664537371',  '16359148473932034636',
    '4693269007065785862',  '2055942548310402289',
    '3306973392177435307',  '8885676876713467323',
    '123232717042594303',   '4502342331337891748',
    '796002772112309291',   '16989567407422764658',
    '14140202457285991249', '511126236207995051',
    '2231381755807086633',  '14759202368433450769',
    '14268630037802571672', '16127995917298181352',
    '4257094582362774157',  '13718937944161154150',
    '15574632344931054546', '17568296358285794238',
    '15814740056907455357', '2754381637012837762',
    '10971758354728748345', '17978722194350293215',
    '8789861672429286038',  '2439542666188438170',
    '8301466673235813057',  '3643512247605284412',
    '4436083969860293654',  '18371712049370376120',
    '10637949931237583118', '17893539985208907837',
    '1066237739928500862',  '14156708587432031543',
    '13615225987990216763', '7283247406530837402',
    '2111187868559797529',  '11549095055615633',
    '2752872151769161189',  '1378768029093311875',
    '14312716280922030608', '3472762984889093538',
    '15243871077328415303', '5552728439719826078',
    '9171008763536371397',  '13258436119504186596',
    '13935139201816073370', '11708466127754837424',
    '3530501252464415944',  '16405297613033794944',
    '9461323638638219051',  '17913179250313811241',
    '5522351720644862414',  '17939147238430738425',
    '7425254055749549770',  '2996817804278770640',
    '3639720715771962284',  '7342833789716583460',
    '3939692440815867923',  '5793177902942873760',
    '7889251406034625535',  '12027682794968924782',
    '7473162259413693557',  '5902766307954538646',
    '1054514130676152720',  '3526318720263317215',
    '4744409711556217067',  '15586453980780606424',
    '14099819196631825335', '12588916030955628229',
    '16999573623451727010', '14363959110907741881',
    '13912995043889359794', '1660320477576151633',
    '10498772740867116048', '8587782089193412281',
    '6330055719003701726',  '6106755009128474114',
    '15199192819216086862', '9428961975819435544',
    '11753192895609522086', '2254708887958278538',
    '8908622203162264336',  '16470497220365505546',
    '6859474912248889588',  '3729284384146531861',
    '17795814995734737903', '1739807018854509111',
    '141841629084657134',   '15799707411113924853',
    '16470050430558885352', '18313334590623953187',
    '10381849194204436741', '1662635747659353856',
    '233531108326825474',   '17321807425262294057',
    '11199633038658781350', '3705324290200321279',
    '8008402009107947927',  '3382650032952973365',
    '9458323089377501764',  '443933754741086859',
    '3731560780752305844',  '10750393312508752809',
    '4847718944411104861',  '7558201115683960412',
    '12961046778350711287', '5173640531882988475',
    '16982602287904553549', '3767654102597339454',
    '3292197666531931384',  '6146214751488526354',
    '12326423421046367389', '83606547911329582',
    '5298648767564049355',  '4929960039345324290',
    '725972229785092910',   '3461770916530250884',
    '6519175775616021953',  '13441797420822857380',
    '12609256409874483017', '14835947449239278156',
    '2988665059323180544',  '16688745117641562169',
    '6864698702038266417',  '18305469821403178820',
    1,                      0,
    '0',                    '-1',
    '0',                    '0',
    '0',                    -1,
    '0',                    '-1',
    '0',                    '0'
]

@@ PRNG_STATE_32BIT
[
    '2147483648', 1677077075,   1758109997,   2012160848,
    541988062,    1491988274,   861106406,    1566399065,
    8399150,      '3653577899', 643613788,    '3190612274',
    1968445455,   '3597414494', 27366164,     '3807984804',
    '2961650050', 1095935393,   2057921854,   '3844081538',
    '3808215560', '3665327674', '3154689857', '4074052117',
    264797845,    '3444667108', '2457594059', '2543739205',
    '4047572148', '3913095671', 359469328,    '4044373318',
    '4260334795', '3870111269', 1380853497,   '3409740945',
    834981438,    '3851028554', '3708093871', '2419194234',
    1838010339,   1218711391,   2143585409,   810295178,
    775538859,    619166428,    1721351432,   '2853170012',
    '2823038809', 1200346205,   '2571814779', '2695584565',
    1943042846,   125318786,    474996257,    '4273536737',
    '3297986018', '2847578188', '4016719928', 310222596,
    1772343889,   651342332,    659919392,    879798211,
    '4242066878', '3336056086', 974561553,    '2360829145',
    '3332093856', 1690614989,   1574718338,   '3898599013',
    310740436,    '2837563447', '4253968177', 123043939,
    '4265883017', 1429754345,   1077543482,   2022472232,
    '3914348998', '2456980012', 1849573422,   318324867,
    '2497574290', '2453249265', 1956598125,   '3354332622',
    '2369709084', 196343112,    '3817402382', '2454585865',
    711011270,    1278169532,   '3743942819', 315959216,
    13745920,     '3869711192', 94072664,     '2543114506',
    1713177570,   1302295864,   1147649475,   '3160148454',
    '2532903929', '2179620859', 1791008302,   '2522372456',
    '3234395645', 517360176,    357143889,    '2551663970',
    173404412,    '4176235229', 720910917,    1033360796,
    '3977741845', 238565813,    '4269084290', 1207925072,
    '2306853653', '2787468199', 1362176947,   '3846242617',
    1119378922,   '2760292638', '3482959318', 453733715,
    '3771139002', 383625843,    '3190936523', 911865079,
    '3305494017', 221775475,    41190502,     1701676081,
    94894038,     1428337978,   990520943,    '2883026377',
    1688032536,   '2378241773', 1352550018,   '3552786783',
    181781467,    2023661600,   '2809034476', 704505374,
    '2966742551', 156498589,    2064531489,   888468256,
    1357347558,   554690418,    1636078621,   '3369268327',
    '3664945445', 19648325,     82799825,     1771068982,
    511091015,    '3571123319', '3438126311', '3661938871',
    1706789258,   '2956788664', '4245670276', '3237385365',
    370667213,    '3709283992', '2370742082', 1950669983,
    '2655238100', 400553867,    186980899,    1728139078,
    '2736486759', 872117973,    '3405136580', '3332402259',
    1513563402,   '3619941441', '3114457879', '4280622303',
    '3520408390', '2218505367', 1428631288,   176881348,
    '3861027368', '3040966652', 1207471436,   2050843637,
    1235960653,   1635977073,   '3372261755', 1563409159,
    1057153661,   '3959746947', 407100025,    2112376632,
    1852250762,   '3033945476', 1930484162,   '2911947295',
    291129345,    215710207,    '3229187417', '3608885029',
    '4024745543', '3481631602', 1240125151,   '2542300655',
    '2303768742', '3970585528', '3235791980', 2124107529,
    2127809371,   '3980895990', 658478289,    1985483584,
    2125518148,   1755314322,   '3608173197', '3307764668',
    1001125987,   1663888474,   '3379980706', 510066840,
    '2261081708', 845846249,    '2372234061', '3813873977',
    '4162013056', '3583925722', '3681369617', '2473245255',
    '2914355745', '3245714238', 1461543414,   '2222432154',
    299657994,    '2760697132', 2144521010,   '3576174561',
    624078225,    1179789139,   751450160,    '2430910709',
    996660321,    1726350207,   681167225,    '3404354175',
    '3541298993', 1527151717,   215196658,    2058309805,
    367288306,    482191886,    '2719738481', '3687879469',
    2011658176,   '3673421311', 256687523,    1321402152,
    500434563,    '3084733401', '3777007962', 1832729659,
    170561099,    1291094876,   '3285509430', '2330805488',
    '4190545328', '3572323711', '2990731708', '2783759473',
    '3228789738', '3337887961', '3209478371', 453056885,
    '3656621525', 1674735023,   '3852531767', '2303553300',
    461261806,    '3810216323', '3891950745', '3944349790',
    '2981723146', 558261335,    '2193851585', 1728978049,
    1439780019,   '2692247461', 153662856,    1682927135,
    768019756,    1071298666,   390094931,    1324671548,
    679944036,    '2951799623', 307080840,    1989915016,
    '3355360669', '2190742070', '4001648064', '2946737490',
    1175363852,   '4120422185', '3551353241', 703421331,
    1982847225,   1049041361,   '3113602733', 90905874,
    '2384387870', '3571219233', '2568318801', 1809317448,
    1604586371,   1289359819,   '3418104240', '2327541803',
    '4211251087', 958119447,    '2420788922', 210884563,
    551488406,    '2981006692', 1670189473,   698564066,
    1275767274,   '3447279485', '2491362403', 1892880956,
    '2553644149', 1467286560,   1789712716,   567231049,
    209672888,    691269149,    857522438,    1204934600,
    '4193584119', 2112095742,   '2233081135', '3703960613',
    '3019546719', '3130901579', 283861596,    '2522212414',
    361344581,    '3767118053', 90269672,     '3458230827',
    '3315884714', '3055923814', '2939326823', 1191182474,
    1598592619,   '2558724810', 1379433533,   340036856,
    675121704,    '2363109837', '2599147383', 1757057248,
    189932069,    1772256814,   81139113,     '3393178502',
    '2628697401', '2243846625', 1059753573,   1141264240,
    '3786795514', '2537499270', '4131123762', 1889202801,
    1928010468,   '2678221564', '4285514789', '3388106141',
    1181529161,   '3477052321', '3167813135', '2731612244',
    '3502032657', '3024269639', '4293497130', 178873438,
    '2306558312', '2681635899', 1409631267,   '3730008093',
    1539667032,   469103802,    '3714414244', 1256496507,
    49726331,     1196496278,   '2254673486', '2616194588',
    '2913676193', '3771315025', 831600480,    856036283,
    931089289,    1067488796,   621127148,    '4186773930',
    79200085,     1224577464,   1448613087,   265939919,
    '2734764249', 1322332244,   '2258199796', '4043886394',
    '3250361079', 652506151,    '4050119269', 1121013754,
    1487690368,   174910517,    2080699189,   500182609,
    1907929587,   '2336982549', 1848029343,   1720305830,
    '3352718148', 2017870985,   '4119152966', 98874327,
    '2275154281', '2728836238', '2739221183', '4208634290',
    839469737,    '2204035092', 861779247,    '3020117410',
    '3811586227', 1083752271,   '2632500877', 2064464734,
    1223489974,   '4231271968', '2161457305', '4033289528',
    '2725981375', '3880033764', 1584244498,   77169859,
    '3710211721', 1753652476,   '2371711264', 552327740,
    620234649,    '3782113180', 7094471,      1178275216,
    314159994,    1855575460,   '3418731089', 1993903680,
    1375702040,   569055171,    312801413,    1328683220,
    1859267194,   '4155738754', '3725584127', '2791098181',
    '2202738539', '2430518177', '3002223855', '3056626238',
    1296446562,   '3143183546', 403521171,    5574345,
    1272499576,   '3612999707', 862605819,    '3902668435',
    1976242083,   '3421909576', '4072205345', 1101089483,
    '3634645108', '3593435097', '4214862138', '2945197444',
    1905071366,   '2886243662', '2666574082', 1328849297,
    1591296963,   '2404594922', 184651244,    1292408003,
    '3387572634', '4033574830', '2459339412', 1664014900,
    1374308289,   1468475088,   1573852822,   922667999,
    1280923547,   '3021619528', 1488029181,   '2425321602',
    '3640227055', '4178174582', 1984264796,   '4051218800',
    '3026504657', 1168036688,   911499036,    '3169769690',
    135707006,    1732743467,   '3783981500', '3385068710',
    626307059,    796196419,    1782343302,   2144987656,
    '3879301279', '3771447229', '2737189808', '3098115217',
    998624938,    1134611930,   2116635688,   '2976675899',
    '2796507349', 1703329175,   '3476461418', '3986021453',
    '4253525679', '3816617809', 837546434,    1024083870,
    873615206,    1878513390,   967949642,    '3331131437',
    1143453313,   1882383991,   '2812888243', 620101474,
    '3945532232', '2761244178', 811678387,    '2628806911',
    2126948101,   '2937581680', '3123037283', 1020209609,
    790939510,    1811696483,   1567435215,   929198790,
    '2526351098', '3433986147', 86188443,     '3111795319',
    236939197,    '4220147808', 1491830407,   1265865222,
    '4172245229', 1567930920,   '3748438821', '2253672863',
    '2752088551', 1152037285,   156239109,    2063958262,
    221698901,    '2757702229', '3396008522', '3430512944',
    298160590,    '2597277585', 332914467,    '2206710419',
    '3232972895', '2194860009', '2639109027', 1479300577,
    1474228869,   325255300,    2030350608,   '2898382680',
    955802572,    '3191949399', '2816630605', '2392252636',
    1108976688,   '2896064359', '2281008697', '3761712436',
    1457704355,   1371617016,   '3806379767', 1868430205,
    '4245349427', 1300725116,   1141939922,   '3783835862',
    2086057536,   213198119,    611329641,    '2346418543',
    551304162,    362542212,    48666851,     344974075,
    1,            0,            0,            -1,
    0,            0,            0,            -1,
    0,            -1,           0,            0
]

@@ RAND_RESULTS_rand_csr_by_group
{   '1.5:0.5' => {},
    '1.5:1.5' => { d => 8 },
    '1.5:2.5' => {},
    '1.5:3.5' => {
        c => 3,
        d => 3
    },
    '1.5:4.5' => {},
    '2.5:0.5' => {},
    '2.5:1.5' => {
        c => 9,
        d => 9
    },
    '2.5:2.5' => {
        c => 6,
        d => 6
    },
    '2.5:3.5' => {
        a => 3,
        b => 3,
        c => 3,
        d => 3
    },
    '2.5:4.5' => {
        c => 12,
        d => 12
    },
    '3.5:0.5' => {
        b => 8,
        c => 8,
        d => 8
    },
    '3.5:1.5' => {
        a => 4,
        b => 4,
        c => 4,
        d => 4
    },
    '3.5:2.5' => {
        a => 2,
        b => 2,
        c => 2,
        d => 2
    },
    '3.5:3.5' => { d => 12 },
    '3.5:4.5' => {
        b => 4,
        c => 4,
        d => 4
    },
    '4.5:0.5' => {
        a => 1,
        b => 1,
        c => 1,
        d => 1
    },
    '4.5:1.5' => { d => 16 },
    '4.5:2.5' => {
        b => 2,
        c => 2,
        d => 2
    },
    '4.5:3.5' => { d => 4 },
    '4.5:4.5' => {
        b => 6,
        c => 6,
        d => 6
    }
}


@@ RAND_RESULTS_rand_diffusion
{   '1.5:0.5' => {},
    '1.5:1.5' => {
        a => 3,
        b => 1,
        c => 4,
        d => 12
    },
    '1.5:2.5' => {
        a => 2,
        b => 2,
        c => 3,
        d => 4
    },
    '1.5:3.5' => {
        a => 4,
        b => 4,
        c => 2,
        d => 16
    },
    '1.5:4.5' => {
        a => 1,
        b => 8,
        c => 2,
        d => 12
    },
    '2.5:0.5' => {},
    '2.5:1.5' => {
        b => 6,
        c => 9,
        d => 4
    },
    '2.5:2.5' => {
        b => 2,
        c => 6,
        d => 6
    },
    '2.5:3.5' => {
        b => 3,
        c => 12,
        d => 4
    },
    '2.5:4.5' => {
        b => 4,
        c => 4,
        d => 3
    },
    '3.5:0.5' => {},
    '3.5:1.5' => {
        c => 8,
        d => 3
    },
    '3.5:2.5' => {
        c => 1,
        d => 1
    },
    '3.5:3.5' => {
        c => 6,
        d => 8
    },
    '3.5:4.5' => {
        c => 3,
        d => 8
    },
    '4.5:0.5' => {},
    '4.5:1.5' => { d => 2 },
    '4.5:2.5' => { d => 2 },
    '4.5:3.5' => { d => 9 },
    '4.5:4.5' => { d => 6 }
}


@@ RAND_RESULTS_rand_nochange
{   '1.5:0.5' => {},
    '1.5:1.5' => {
        a => 1,
        b => 1,
        c => 1,
        d => 1
    },
    '1.5:2.5' => {
        a => 2,
        b => 2,
        c => 2,
        d => 2
    },
    '1.5:3.5' => {
        a => 3,
        b => 3,
        c => 3,
        d => 3
    },
    '1.5:4.5' => {
        a => 4,
        b => 4,
        c => 4,
        d => 4
    },
    '2.5:0.5' => {},
    '2.5:1.5' => {
        b => 2,
        c => 2,
        d => 2
    },
    '2.5:2.5' => {
        b => 4,
        c => 4,
        d => 4
    },
    '2.5:3.5' => {
        b => 6,
        c => 6,
        d => 6
    },
    '2.5:4.5' => {
        b => 8,
        c => 8,
        d => 8
    },
    '3.5:0.5' => {},
    '3.5:1.5' => {
        c => 3,
        d => 3
    },
    '3.5:2.5' => {
        c => 6,
        d => 6
    },
    '3.5:3.5' => {
        c => 9,
        d => 9
    },
    '3.5:4.5' => {
        c => 12,
        d => 12
    },
    '4.5:0.5' => {},
    '4.5:1.5' => { d => 4 },
    '4.5:2.5' => { d => 8 },
    '4.5:3.5' => { d => 12 },
    '4.5:4.5' => { d => 16 }
}


@@ RAND_RESULTS_rand_random_walk
{   '1.5:0.5' => {},
    '1.5:1.5' => {
        a => 2,
        b => 4,
        c => 4,
        d => 6
    },
    '1.5:2.5' => {
        a => 4,
        b => 2,
        c => 3,
        d => 3
    },
    '1.5:3.5' => {
        a => 3,
        b => 8,
        c => 1,
        d => 4
    },
    '1.5:4.5' => {
        a => 1,
        b => 4,
        c => 8,
        d => 4
    },
    '2.5:0.5' => {},
    '2.5:1.5' => {
        b => 1,
        c => 3,
        d => 9
    },
    '2.5:2.5' => {
        b => 6,
        c => 12,
        d => 2
    },
    '2.5:3.5' => {
        b => 3,
        c => 2,
        d => 6
    },
    '2.5:4.5' => {
        b => 2,
        c => 4,
        d => 12
    },
    '3.5:0.5' => {},
    '3.5:1.5' => {
        c => 2,
        d => 16
    },
    '3.5:2.5' => {
        c => 6,
        d => 4
    },
    '3.5:3.5' => {
        c => 9,
        d => 8
    },
    '3.5:4.5' => {
        c => 6,
        d => 8
    },
    '4.5:0.5' => {},
    '4.5:1.5' => { d => 2 },
    '4.5:2.5' => { d => 3 },
    '4.5:3.5' => { d => 12 },
    '4.5:4.5' => { d => 1 }
}

@@ RAND_RESULTS_rand_spatially_structured
{   '1.5:0.5' => {},
    '1.5:1.5' => {
        a => 3,
        b => 1,
        c => 4,
        d => 12
    },
    '1.5:2.5' => {
        a => 2,
        b => 2,
        c => 3,
        d => 4
    },
    '1.5:3.5' => {
        a => 4,
        b => 4,
        c => 2,
        d => 16
    },
    '1.5:4.5' => {
        a => 1,
        b => 8,
        c => 2,
        d => 12
    },
    '2.5:0.5' => {},
    '2.5:1.5' => {
        b => 6,
        c => 9,
        d => 4
    },
    '2.5:2.5' => {
        b => 2,
        c => 6,
        d => 6
    },
    '2.5:3.5' => {
        b => 3,
        c => 12,
        d => 4
    },
    '2.5:4.5' => {
        b => 4,
        c => 4,
        d => 3
    },
    '3.5:0.5' => {},
    '3.5:1.5' => {
        c => 8,
        d => 3
    },
    '3.5:2.5' => {
        c => 1,
        d => 1
    },
    '3.5:3.5' => {
        c => 6,
        d => 8
    },
    '3.5:4.5' => {
        c => 3,
        d => 8
    },
    '4.5:0.5' => {},
    '4.5:1.5' => { d => 2 },
    '4.5:2.5' => { d => 2 },
    '4.5:3.5' => { d => 9 },
    '4.5:4.5' => { d => 6 }
}


@@ RAND_RESULTS_rand_structured
{   '1.5:0.5' => {},
    '1.5:1.5' => {
        a => 3,
        b => 2,
        c => 3,
        d => 3
    },
    '1.5:2.5' => {
        a => 4,
        b => 8,
        c => 4,
        d => 8
    },
    '1.5:3.5' => {
        a => 2,
        b => 1,
        c => 6,
        d => 6
    },
    '1.5:4.5' => {
        a => 1,
        b => 3,
        c => 2,
        d => 4
    },
    '2.5:0.5' => {},
    '2.5:1.5' => {
        b => 2,
        c => 12,
        d => 4
    },
    '2.5:2.5' => {
        b => 6,
        c => 8,
        d => 12
    },
    '2.5:3.5' => {
        b => 4,
        c => 6,
        d => 4
    },
    '2.5:4.5' => {
        b => 4,
        c => 3,
        d => 16
    },
    '3.5:0.5' => {},
    '3.5:1.5' => {
        c => 9,
        d => 6
    },
    '3.5:2.5' => {
        c => 4,
        d => 2
    },
    '3.5:3.5' => {
        c => 2,
        d => 1
    },
    '3.5:4.5' => {
        c => 1,
        d => 8
    },
    '4.5:0.5' => {},
    '4.5:1.5' => { d => 9 },
    '4.5:2.5' => { d => 3 },
    '4.5:3.5' => { d => 2 },
    '4.5:4.5' => { d => 12 }
}


@@ RAND_RESULTS_rand_independent_swaps
{   '1.5:0.5' => {},
    '1.5:1.5' => {
        a => 1,
        b => 1,
        c => 1,
        d => 1
    },
    '1.5:2.5' => {
        a => 2,
        b => 2,
        c => 2,
        d => 2
    },
    '1.5:3.5' => {
        a => 3,
        b => 3,
        c => 3,
        d => 3
    },
    '1.5:4.5' => {
        a => 4,
        b => 4,
        c => 4,
        d => 4
    },
    '2.5:0.5' => {},
    '2.5:1.5' => {
        b => 2,
        c => 2,
        d => 2
    },
    '2.5:2.5' => {
        b => 4,
        c => 4,
        d => 4
    },
    '2.5:3.5' => {
        b => 6,
        c => 6,
        d => 6
    },
    '2.5:4.5' => {
        b => 8,
        c => 8,
        d => 8
    },
    '3.5:0.5' => {},
    '3.5:1.5' => {
        c => 3,
        d => 3
    },
    '3.5:2.5' => {
        c => 6,
        d => 6
    },
    '3.5:3.5' => {
        c => 9,
        d => 9
    },
    '3.5:4.5' => {
        c => 12,
        d => 12
    },
    '4.5:0.5' => {},
    '4.5:1.5' => { d => 4 },
    '4.5:2.5' => { d => 8 },
    '4.5:3.5' => { d => 12 },
    '4.5:4.5' => { d => 16 }
}

@@ RAND_RESULTS_rand_independent_swaps_modified
{   '1.5:0.5' => {},
    '1.5:1.5' => {
        a => 1,
        b => 1,
        c => 1,
        d => 1
    },
    '1.5:2.5' => {
        a => 2,
        b => 2,
        c => 2,
        d => 2
    },
    '1.5:3.5' => {
        a => 3,
        b => 3,
        c => 3,
        d => 3
    },
    '1.5:4.5' => {
        a => 4,
        b => 4,
        c => 4,
        d => 4
    },
    '2.5:0.5' => {},
    '2.5:1.5' => {
        b => 2,
        c => 2,
        d => 2
    },
    '2.5:2.5' => {
        b => 4,
        c => 4,
        d => 4
    },
    '2.5:3.5' => {
        b => 6,
        c => 6,
        d => 6
    },
    '2.5:4.5' => {
        b => 8,
        c => 8,
        d => 8
    },
    '3.5:0.5' => {},
    '3.5:1.5' => {
        c => 3,
        d => 3
    },
    '3.5:2.5' => {
        c => 6,
        d => 6
    },
    '3.5:3.5' => {
        c => 9,
        d => 9
    },
    '3.5:4.5' => {
        c => 12,
        d => 12
    },
    '4.5:0.5' => {},
    '4.5:1.5' => { d => 4 },
    '4.5:2.5' => { d => 8 },
    '4.5:3.5' => { d => 12 },
    '4.5:4.5' => { d => 16 }
}


