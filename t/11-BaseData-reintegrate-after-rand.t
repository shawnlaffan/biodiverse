#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use 5.010;
use strict;
use warnings;

# HARNESS-DURATION-LONG

use English qw { -no_match_vars };
use Data::Dumper;
use List::Util 1.45 qw /uniq/;
use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

use Test2::V0;

use Biodiverse::TestHelpers qw /:basedata/;
use Biodiverse::BaseData;
use Biodiverse::ElementProperties;


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


sub test_reintegrate_after_separate_randomisations {
    #  use a small basedata for test speed purposes
    my %args = (
        x_spacing   => 1,
        y_spacing   => 1,
        CELL_SIZES  => [1, 1],
        x_max       => 5,
        y_max       => 5,
        x_min       => 1,
        y_min       => 1,
    );

    my $bd1 = get_basedata_object (%args);
    
    #  need some extra labels so the randomisations have something to do
    $bd1->add_element (group => '0.5:0.5', label => 'somelevel::extra1');
    $bd1->add_element (group => '1.5:0.5', label => 'somelevel::extra1');
    
    foreach my $label ($bd1->get_labels) {
        my $new_name = $label =~ s/_/::/r;
        $bd1->rename_label (
            label    => $label,
            new_name => $new_name,
        );
    }
    my $tree = $bd1->to_tree;

    my $sp = $bd1->add_spatial_output (name => 'sp1');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()', 'sp_circle(radius => 1)'],
        calculations => [
          qw /
            calc_endemism_central
            calc_endemism_central_lists
            calc_element_lists_used
            calc_pe
            calc_phylo_rpe2
          /
        ],
        tree_ref => $tree,
    );
    my $cl = $bd1->add_cluster_output (name => 'cl1');
    $cl->run_analysis (
        spatial_calculations => [
          qw /
            calc_endemism_central
            calc_endemism_central_lists
            calc_element_lists_used
            calc_pe
            calc_phylo_rpe2
          /
        ],
    );
    my $rg = $bd1->add_cluster_output (name => 'rg1', type => 'Biodiverse::RegionGrower');
    $rg->run_analysis (
        spatial_calculations => [
          qw /
            calc_endemism_central
            calc_endemism_central_lists
            calc_element_lists_used
          /
        ],
    );

    my $bd2 = $bd1->clone;
    my $bd3 = $bd1->clone;
    my $bd4 = $bd1->clone;  #  used lower down to check recursive reintegration
    my $bd5 = $bd1->clone;  #  used to check for different groups/labels
    
    $bd5->add_element (group => '0.5:0.5', label => 'blort');

    my $prng_seed = 2345;
    my $i = 0;
    foreach my $bd ($bd1, $bd2, $bd3, $bd4, $bd5) { 
        $i %= 3;  #  max out at 3
        $i++;

        my $rand1 = $bd->add_randomisation_output (name => 'random1');
        my $rand2 = $bd->add_randomisation_output (name => 'random2');
        $prng_seed++;
        my %run_args = (
            function   => 'rand_csr_by_group',
            seed       => $prng_seed,
            build_randomised_trees => 1,
        );
        $rand1->run_analysis (
            %run_args,
            iterations => $i,
        );
        $prng_seed++;
        $rand2->run_analysis (
            %run_args,
            iterations => $i,
        );
    }

    ref_is_not (
        $bd1->get_spatial_output_ref (name => 'sp1'),
        $bd2->get_spatial_output_ref (name => 'sp1'),
        'spatial results differ after randomisation, bd1 & bd2',
    );
    ref_is_not (
        $bd1->get_spatial_output_ref (name => 'sp1'),
        $bd3->get_spatial_output_ref (name => 'sp1'),
        'spatial results differ after randomisation, bd1 & bd3',
    );
    ref_is_not (
        $bd1->get_cluster_output_ref (name => 'cl1'),
        $bd2->get_cluster_output_ref (name => 'cl1'),
        'cluster results differ after randomisation, bd1 & bd2',
    );
    ref_is_not (
        $bd1->get_cluster_output_ref (name => 'cl1'),
        $bd3->get_cluster_output_ref (name => 'cl1'),
        'cluster results differ after randomisation, bd1 & bd3',
    );
    ref_is_not (
        $bd1->get_cluster_output_ref (name => 'rg1'),
        $bd2->get_cluster_output_ref (name => 'rg1'),
        'region grower differ after randomisation, bd1 & bd2',
    );
    ref_is_not (
        $bd1->get_cluster_output_ref (name => 'rg1'),
        $bd3->get_cluster_output_ref (name => 'rg1'),
        'region grower results differ after randomisation, bd1 & bd3',
    );
    

    my $bd_orig;
    my $RE_canape_or_zscore = qr />>(?:canape|z_scores)>>/i;

    for my $bd_from ($bd2, $bd3) {
        #  we need the pre-integration values for checking
        $bd_orig = $bd1->clone;
        
        #  clean up the canape and z_score lists
        my $sp = $bd1->get_spatial_output_ref (name => 'sp1');
        my @canape_and_z_list_names
          = sort grep {/$RE_canape_or_zscore/}
            $sp->get_hash_list_names_across_elements;
        foreach my $el ($sp->get_element_list) {
            $sp->delete_lists (element => $el, lists => \@canape_and_z_list_names);
        }
        my @canape_and_z_list_names_post_deletion
          = sort grep {/$RE_canape_or_zscore/}
            $sp->get_hash_list_names_across_elements;
        is \@canape_and_z_list_names_post_deletion,
           [],
           'canape and z lists removed from spatial output';
        
        my $cl = $bd1->get_cluster_output_ref (name => 'cl1');
        my @cl_canape_and_z_list_names
          = sort grep {/$RE_canape_or_zscore/}
            $cl->get_hash_list_names_across_nodes;
        $cl->delete_lists_below (lists => \@cl_canape_and_z_list_names);  #  should be the same lists?
        my @cl_canape_and_z_list_names_post_deletion
          = sort grep {/$RE_canape_or_zscore/}
            $cl->get_hash_list_names_across_nodes;
        is \@cl_canape_and_z_list_names_post_deletion,
           [],
           'canape and z lists removed from cluster output';
        
        
        $bd1->reintegrate_after_parallel_randomisations (
            from => $bd_from,
        );
        
        my @canape_and_z_list_names_post_integr
          = sort grep {/$RE_canape_or_zscore/}
            $sp->get_hash_list_names_across_elements;
        is \@canape_and_z_list_names_post_integr,
           \@canape_and_z_list_names,
           'canape and z lists reinstated to spatial output after reintegration';
        my @cl_canape_and_z_list_names_post_reintegr
          = sort grep {/$RE_canape_or_zscore/}
            $cl->get_hash_list_names_across_nodes;
        is \@cl_canape_and_z_list_names_post_reintegr,
           \@cl_canape_and_z_list_names,
           'canape and z lists reinstated to cluster output after reintegration';

        check_randomisation_lists_incremented_correctly_spatial (
            orig   => $bd_orig->get_spatial_output_ref (name => 'sp1'),
            integr => $bd1->get_spatial_output_ref     (name => 'sp1'),
            from   => $bd_from->get_spatial_output_ref (name => 'sp1')
        );
        check_randomisation_lists_incremented_correctly_cluster (
            orig   => $bd_orig->get_cluster_output_ref (name => 'cl1'),
            integr => $bd1->get_cluster_output_ref     (name => 'cl1'),
            from   => $bd_from->get_cluster_output_ref (name => 'cl1')
        );
        check_randomisation_lists_incremented_correctly_cluster (
            orig   => $bd_orig->get_cluster_output_ref (name => 'rg1'),
            integr => $bd1->get_cluster_output_ref     (name => 'rg1'),
            from   => $bd_from->get_cluster_output_ref (name => 'rg1')
        );
    }

    _test_reintegrated_basedata_unchanged ($bd1, 'reintegrated correctly');
    
    #  now check that we don't double reintegrate
    $bd_orig = $bd1->clone;
    for my $bd_from ($bd2, $bd3) {
        eval {
            $bd1->reintegrate_after_parallel_randomisations (
                from => $bd_from,
            );
        };
        ok ($@, 'we threw an error');
        check_randomisation_integration_skipped (
            orig   => $bd_orig->get_spatial_output_ref (name => 'sp1'),
            integr => $bd1->get_spatial_output_ref (name => 'sp1'),
        );
    }

    _test_reintegrated_basedata_unchanged (
        $bd1,
        'no integration when already done',
    );

    #  now check that we don't double reintegrate a case like a&b&c with d&b&c
    $bd_orig = $bd1->clone;
    $bd4->reintegrate_after_parallel_randomisations (from => $bd2);
    $bd4->reintegrate_after_parallel_randomisations (from => $bd3);

    eval {
        $bd1->reintegrate_after_parallel_randomisations (
            from => $bd4,
        );
    };
    ok ($@, 'we threw an error');
    check_randomisation_integration_skipped (
        orig   => $bd_orig->get_spatial_output_ref (name => 'sp1'),
        integr => $bd1->get_spatial_output_ref (name => 'sp1'),
    );

    _test_reintegrated_basedata_unchanged (
        $bd1,
        'no integration when already done (embedded double)',
    );

    eval {
        $bd1->reintegrate_after_parallel_randomisations (
            from => $bd5,
        );
    };
    ok ($@, 'we threw an error for label/group mismatch');
    _test_reintegrated_basedata_unchanged ($bd1, 'no integration for group/label mismatch');

    
    return;
}


sub test_reintegrate {
    #  use a small basedata for test speed purposes
    #  cargo culted setup code - should be abstracted
    my %args = (
        x_spacing   => 1,
        y_spacing   => 1,
        CELL_SIZES  => [1, 1],
        x_max       => 5,
        y_max       => 5,
        x_min       => 1,
        y_min       => 1,
    );

    my $bd1 = get_basedata_object (%args);
    
    #  need some extra labels so the randomisations have something to do
    $bd1->add_element (group => '0.5:0.5', label => 'extra1');
    $bd1->add_element (group => '1.5:0.5', label => 'extra1');

    my $sp = $bd1->add_spatial_output (name => 'sp1');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()', 'sp_circle(radius => 1)'],
        calculations => [
          qw /
            calc_endemism_central
            calc_endemism_central_lists
            calc_element_lists_used
          /
        ],
    );
    my $cl = $bd1->add_cluster_output (name => 'cl1');
    $cl->run_analysis (
        spatial_calculations => [
          qw /
            calc_endemism_central
            calc_endemism_central_lists
            calc_element_lists_used
          /
        ],
    );
    my $rg = $bd1->add_cluster_output (name => 'rg1', type => 'Biodiverse::RegionGrower');
    $rg->run_analysis (
        spatial_calculations => [
          qw /
            calc_endemism_central
            calc_endemism_central_lists
            calc_element_lists_used
          /
        ],
    );

    my $bd2 = $bd1->clone;
    my $bd3 = $bd1->clone;
    
    my $prng_seed = 2345;
    my $rand1 = $bd1->add_randomisation_output (name => 'random1');
    my %run_args = (
        function   => 'rand_structured',
        seed       => $prng_seed,
    );
    $rand1->run_analysis (
        %run_args,
        iterations => 2,
    );
    my $partial_state = $rand1->get_prng_end_states_array;
    my $prng_state_after_2iters = $partial_state->[0];
    my $bd1_iters2 = $bd1->clone;
    #  another 2 iters
    $rand1->run_analysis (
        %run_args,
        iterations => 2,
    );
    
    my $rand2 = $bd2->add_randomisation_output (name => 'random1');
    $rand2->run_analysis (
        %run_args,
        iterations => 2,
    );
    
    #say STDERR "Checking match at 2 iters";
    check_integrated_matches_single_run_spatial (
        orig   => $bd1_iters2->get_spatial_output_ref (name => 'sp1'),
        integr => $bd2->get_spatial_output_ref (name => 'sp1'),
    );
    check_integrated_matches_single_run_cluster (
        orig   => $bd1_iters2->get_cluster_output_ref (name => 'cl1'),
        integr => $bd2->get_cluster_output_ref (name => 'cl1'),
    );
    check_integrated_matches_single_run_cluster (
        orig   => $bd1_iters2->get_cluster_output_ref (name => 'rg1'),
        integr => $bd2->get_cluster_output_ref (name => 'rg1'),
    );
    
    my $rand3 = $bd3->add_randomisation_output (name => 'random1');
    $rand3->run_analysis (
        %run_args,
        state => $prng_state_after_2iters,
        iterations => 2,
    );

    # say STDERR 'reintegrating';    
    $bd2->reintegrate_after_parallel_randomisations (
        from => $bd3,
    );
    
    #$bd1->save_to (filename => 'bd1.bds');
    #$bd2->save_to (filename => 'bd2.bds');
    
    # say STDERR "Checking match at 4 iters";
    check_integrated_matches_single_run_spatial (
        orig   => $bd1->get_spatial_output_ref (name => 'sp1'),
        integr => $bd2->get_spatial_output_ref (name => 'sp1'),
    );
    check_integrated_matches_single_run_cluster (
        orig   => $bd1->get_cluster_output_ref (name => 'cl1'),
        integr => $bd2->get_cluster_output_ref (name => 'cl1'),
    );
    check_integrated_matches_single_run_cluster (
        orig   => $bd1->get_cluster_output_ref (name => 'rg1'),
        integr => $bd2->get_cluster_output_ref (name => 'rg1'),
    );

}

sub _test_reintegrated_basedata_unchanged {
    my ($bd1, $sub_name) = @_;

    $sub_name //= 'test_reintegrated_basedata_unchanged';

    my @names = sort {$a->get_name cmp $b->get_name} $bd1->get_randomisation_output_refs;
    
    subtest $sub_name => sub {
        foreach my $rand_ref (@names) {
            my $name = $rand_ref->get_name;
            is ($rand_ref->get_param('TOTAL_ITERATIONS'),
                6,
                "Total iterations is correct after reintegration ignored, $name",
            );
            my $prng_init_states = $rand_ref->get_prng_init_states_array;
            is (scalar @$prng_init_states,
                3,
                "Got 3 init states when reintegrations ignored, $name",
            );
            my $prng_end_states = $rand_ref->get_prng_end_states_array;
            is (scalar @$prng_end_states,
                3,
                "Got 3 end states when reintegrations ignored, $name",
            );
            my $a_ref = $rand_ref->get_prng_total_counts_array;
            is (
                $a_ref,
                [1, 2, 3],
                "got expected total iteration counts array when reintegrations ignored, $name",
            );
        }
    };

    return;
}

sub test_reintegration_updates_p_indices {
    #  use a small basedata for test speed purposes
    my %args = (
        x_spacing   => 1,
        y_spacing   => 1,
        CELL_SIZES  => [1, 1],
        x_max       => 5,
        y_max       => 5,
        x_min       => 1,
        y_min       => 1,
    );

    my $bd_base = get_basedata_object (%args);
    
    #  need some extra labels so the randomisations have something to do
    $bd_base->add_element (group => '0.5:0.5', label => 'extra1');
    $bd_base->add_element (group => '1.5:0.5', label => 'extra1');

    my $sp = $bd_base->add_spatial_output (name => 'analysis1');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [qw /calc_endemism_central/],
    );

    my $prng_seed = 234587654;
    
    my $check_name = 'rand_check_p';
    my @basedatas;
    for my $i (1 .. 5) {
        my $bdx = $bd_base->clone;
        my $randx = $bdx->add_randomisation_output (name => $check_name);
        $prng_seed++;
        $randx->run_analysis (
            function   => 'rand_structured',
            iterations => 9,
            seed       => $prng_seed,
        );
        push @basedatas, $bdx;
    }
    
    my $list_name = $check_name . '>>SPATIAL_RESULTS';


    my $bd_into = shift @basedatas;
    my $sp_integr = $bd_into->get_spatial_output_ref (name => 'analysis1');

    #  make sure some of the p scores are wrong so they get overridden 
    foreach my $group ($sp_integr->get_element_list) {
        my %l_args = (element => $group, list => $list_name);
        my $lr_integr = $sp_integr->get_list_ref (%l_args);
        foreach my $key (grep {$_ =~ /^P_/} keys %$lr_integr) {
            #say $lr_integr->{$key};
            $lr_integr->{$key} /= 2;
            #say $lr_integr->{$key};
        }
    }

    #  now integrate them
    foreach my $bdx (@basedatas) {
        $bd_into->reintegrate_after_parallel_randomisations (
            from => $bdx,
        );
    }
    
    
    subtest 'P_ scores updated after reintegration' => sub {
        my $gp_list = $bd_into->get_groups;
        foreach my $group (@$gp_list) {
            my %l_args = (element => $group, list => $list_name);
            my $lr_integr = $sp_integr->get_list_ref (%l_args);
            
            foreach my $key (sort grep {$_ =~ /P_/} keys %$lr_integr) {
                #no autovivification;
                my $index = substr $key, 1;
                is ($lr_integr->{$key},
                    $lr_integr->{"C$index"} / $lr_integr->{"Q$index"},
                    "Integrated = orig+from, $lr_integr->{$key}, $group, $list_name, $key",
                );
            }
        }
    };
}

sub check_randomisation_integration_skipped {
    my %args = @_;
    my ($sp_orig, $sp_integr) = @args{qw /orig integr/};

    my $test_name = 'randomisation lists incremented correctly when integration '
                  . 'should be skipped (i.e. no integration was done)';
    subtest $test_name => sub {
        my $gp_list = $sp_integr->get_element_list;
        my $list_names = $sp_integr->get_lists (element => $gp_list->[0]);
        my @rand_lists = grep {$_ !~ />>p_rank>>/ and $_ =~ />>/} @$list_names;
        foreach my $group (@$gp_list) {
            foreach my $list_name (@rand_lists) {
                my %l_args = (element => $group, list => $list_name);
                my $lr_orig   = $sp_orig->get_list_ref (%l_args);
                my $lr_integr = $sp_integr->get_list_ref (%l_args);
                is ($lr_integr, $lr_orig, "$group, $list_name");
            }
        }
    };
}

sub check_integrated_matches_single_run_spatial {
    my %args = @_;
    my ($sp_orig, $sp_integr) = @args{qw /orig integr/};

    my $object_name = $sp_integr->get_name;

    subtest "randomisation spatial lists incremented correctly, $object_name" => sub {
        my $gp_list = $sp_integr->get_element_list;
        my $list_names = $sp_integr->get_lists (element => $gp_list->[0]);
        my @lists = sort grep {$_ =~ />>/} @$list_names;
        
        foreach my $group (sort @$gp_list) {
            foreach my $list_name (@lists) {
                my %l_args = (element => $group, list => $list_name);
                my $lr_orig   = $sp_orig->get_list_ref (%l_args);
                my $lr_integr = $sp_integr->get_list_ref (%l_args);
                is (
                    $lr_integr,
                    $lr_orig,
                    "integrated matches single run, $group, $list_name"
                );
            }
        }
    };
}

sub check_integrated_matches_single_run_cluster {
    my %args = @_;
    my ($cl_orig, $cl_integr) = @args{qw /orig integr/};

    my $object_name = $cl_integr->get_name;

    subtest "randomisation cluster lists incremented correctly, $object_name" => sub {
        my $to_nodes   = $cl_integr->get_node_refs;
        my $list_names = $cl_integr->get_hash_list_names_across_nodes;
        my @lists = sort grep {$_ =~ />>/} @$list_names;

        foreach my $to_node (sort {$a->get_name cmp $b->get_name} @$to_nodes) {
            my $node_name = $to_node->get_name;
            my $orig_node = $cl_orig->get_node_ref (node => $node_name);
            foreach my $list_name (@lists) {
                my %l_args = (list => $list_name);
                my $lr_orig   = $orig_node->get_list_ref (%l_args);
                my $lr_integr = $to_node->get_list_ref (%l_args);
                #is (  #  needed for debug, disable once completed
                #    join (' ', sort keys %$lr_integr),
                #    join (' ', sort keys %$lr_orig),
                #    "keys match for $list_name, node $node_name",
                #);
                compare_hash_vals (
                    hash_got => $lr_integr,
                    hash_exp => $lr_orig,
                    tolerance => 1e-10,
                    descr_suffix
                      => "integrated matches single run, "
                       . "$object_name, $node_name, $list_name"
                );
            }
        }
    };
}

sub check_randomisation_lists_incremented_correctly_spatial {
    my %args = @_;
    my ($sp_orig, $sp_from, $sp_integr) = @args{qw /orig from integr/};

    my $object_name = $sp_integr->get_name;

    my (%collated_got, %collated_exp);
    my (%collated_sig_list_got);

    my $gp_list = $sp_integr->get_element_list;
    my $list_names = $sp_integr->get_lists (element => $gp_list->[0]);
    my @rand_lists = grep {$_ =~ />>/ and $_ !~ />>\w+>>/} @$list_names;
    my @sig_lists  = grep {$_ =~ />>p_rank>>/}  @$list_names;
    #  we will check the z lists elsewhere
    #my @z_lists    = grep {$_ =~ />>z_scores>>/} @$list_names;

    foreach my $group (sort @$gp_list) {
        foreach my $list_name (sort @rand_lists) {
            my %l_args = (element => $group, list => $list_name);
            my $lr_orig   = $sp_orig->get_list_ref (%l_args);
            my $lr_integr = $sp_integr->get_list_ref (%l_args);
            my $lr_from   = $sp_from->get_list_ref (%l_args);

            foreach my $key (keys %$lr_integr) {
                #diag $key if $key =~ /SUMX/;
                #no autovivification;
                if ($key =~ /^P_/) {
                    my $index = substr $key, 1;
                    my $msg = "Integrated = orig+from, $lr_integr->{$key}, $group, $list_name, $key";
                    $collated_exp{$msg} = $lr_integr->{$key};
                    $collated_got{$msg} = $lr_integr->{"C$index"} / $lr_integr->{"Q$index"};
                }
                else {
                    my $msg = "Integrated = orig+from, $lr_integr->{$key}, $group, $list_name, $key";
                    $collated_exp{$msg} = $lr_integr->{$key};
                    $collated_got{$msg} = ($lr_orig->{$key} // 0) + ($lr_from->{$key} // 0);
                }
            }
        }

        foreach my $sig_list_name (sort @sig_lists) {
            #  we only care if they are in the valid set
            my $orig_list_name = $sig_list_name =~ s/>>p_rank//r;
            my $lr_integr = $sp_integr->get_list_ref (element => $group, list => $sig_list_name);
            my $rand_list = $sp_integr->get_list_ref (element => $group, list => $orig_list_name);
            foreach my $key (sort keys %$lr_integr) {
                rand_p_rank_is_valid ($lr_integr, $rand_list, $key, $group);
            }
        }
    }

    is \%collated_got, \%collated_exp, "randomisation spatial lists incremented correctly, $object_name";
    my %collated_sig_list_exp;
    @collated_sig_list_exp{keys %collated_sig_list_got} = (1) x keys %collated_sig_list_got;
    is \%collated_sig_list_got, \%collated_sig_list_exp, 'Collated significance lists in correct range';
}


sub check_randomisation_lists_incremented_correctly_cluster {
    my %args = @_;
    my ($cl_orig, $cl_from, $cl_integr) = @args{qw /orig from integr/};
    
    my $object_name = $cl_integr->get_name;

    subtest "randomisation cluster lists incremented correctly, $object_name" => sub {
        my $to_nodes   = $cl_integr->get_node_refs;
        my $list_names = $cl_integr->get_hash_list_names_across_nodes;
        my @rand_lists = grep {$_ =~ />>/ and $_ !~ />>\w+>>/} @$list_names;
        my @sig_lists  = grep {$_ =~ />>p_rank>>/} @$list_names;
        my @z_lists    = grep {$_ =~ />>z_scores>>/} @$list_names;

        my @rand_names = uniq (map {my $xx = $_; $xx =~ s/>>.+$//; $xx} @sig_lists);
        foreach my $to_node (sort {$a->get_name cmp $b->get_name} @$to_nodes) {
            my $node_name = $to_node->get_name;
            my $from_node = $cl_from->get_node_ref (node => $node_name);
            my $orig_node = $cl_orig->get_node_ref (node => $node_name);
            foreach my $list_name (sort @rand_lists) {
                my %l_args = (list => $list_name);
                my $lr_orig   = $orig_node->get_list_ref (%l_args);
                my $lr_integr = $to_node->get_list_ref (%l_args);
                my $lr_from   = $from_node->get_list_ref (%l_args);

                my $fail_msg = '';
                #  should refactor this - it duplicates the spatial variant
              BY_KEY:
                foreach my $key (sort keys %$lr_integr) {
                    #no autovivification;
                    my $exp;
                    if ($key =~ /^P_/) {
                        my $index = substr $key, 1;
                        $exp = $lr_integr->{"C$index"} / $lr_integr->{"Q$index"};
                    }
                    else {
                        $exp = ($lr_orig->{$key} // 0) + ($lr_from->{$key} // 0);
                    }
                    if ($lr_integr->{$key} ne $exp) {
                        $fail_msg = "FAILED: Integrated = orig+from, "
                          . "$lr_integr->{$key}, $node_name, $list_name, $key";
                        last BY_KEY;
                    }
                }
                ok (!$fail_msg, "reintegrated $list_name for $node_name");
            }

            foreach my $sig_list_name (sort @sig_lists) {
                #  We only care if they are in the valid set.
                #  Replication is handled under test_reintegrate.
                my $orig_list_name = $sig_list_name =~ s/>>p_rank//r;
                my $lr_integr = $to_node->get_list_ref (list => $sig_list_name);
                my $rand_list = $to_node->get_list_ref (list => $orig_list_name);
                # diag $orig_list_name;
                foreach my $key (sort keys %$lr_integr) {
                    rand_p_rank_is_valid ($lr_integr, $rand_list, $key, $node_name);
                }
            }


            #  now the data and stats
            foreach my $rand_name (sort @rand_names) {
                foreach my $suffix (qw/_DATA _ID_LDIFFS/) {
                    my $data_list_name = $rand_name . $suffix;
                    my $to_data_list   = $to_node->get_list_ref (list => $data_list_name);
                    my $from_data_list = $from_node->get_list_ref (list => $data_list_name);
                    my $orig_data_list = $orig_node->get_list_ref (list => $data_list_name);
                    is (
                        $to_data_list,
                        [@$orig_data_list, @$from_data_list],
                        "expected data list for $node_name, $data_list_name",
                    );
                }
                #  stats are more difficult - check the mean for now
                my $stats_list_name = $rand_name;
                my $to_stats   = $to_node->get_list_ref (list => $stats_list_name);
                my $from_stats = $from_node->get_list_ref (list => $stats_list_name);
                my $orig_stats = $orig_node->get_list_ref (list => $stats_list_name);
                #  avoid precision issues
                my $got = sprintf "%.10f", $to_stats->{MEAN};
                my $sum = $from_stats->{MEAN} * $from_stats->{COMPARISONS}
                        + $orig_stats->{MEAN} * $orig_stats->{COMPARISONS};
                my $expected = sprintf "%.10f", $sum / ($orig_stats->{COMPARISONS} + $from_stats->{COMPARISONS});
                is ($got, $expected, "got expected mean for $object_name: $node_name, $stats_list_name");
            }
        }
    };
}

