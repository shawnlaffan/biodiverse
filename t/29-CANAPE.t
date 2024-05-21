use 5.010;
use strict;
use warnings;

# HARNESS-DURATION-LONG

local $| = 1;

use Carp;

use FindBin qw/$Bin/;
use rlib;

use Test2::V0;
use Test::Deep::NoTest qw/eq_deeply/;

use English qw / -no_match_vars /;
local $| = 1;

use Biodiverse::TestHelpers qw /:cluster :element_properties :tree/;

use Biodiverse::Randomise;

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

sub test_rand_structured_richness_same {
    my ($rand_function, %args) = @_;
    $rand_function //= 'rand_structured';
    
    my $c = 100000;
    my $bd   = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);
    my $tree = get_tree_object_from_sample_data();

    #  add some empty groups
    foreach my $i (1 .. 20) {
        my $x = $i * -$c + $c / 2;
        my $y = -$c / 2;
        my $gp = "$x:$y";
        $bd->add_element (group => $gp, allow_empty_groups => 1);
    }

    my $sp_no_canape = $bd->add_spatial_output (name => 'sp_no_canape');
    $sp_no_canape->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => [qw /calc_richness/],
    );
    my $sp_has_canape = $bd->add_spatial_output (name => 'sp_has_canape');
    $sp_has_canape->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => [qw /calc_pe calc_phylo_rpe2/],
        tree_ref           => $tree,
    );

    my $prng_seed = 2345;

    my $rand_name = $rand_function;

    my $rand = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand->run_analysis (
        function   => $rand_function,
        iterations => 149,  #  enough to trigger one palaeo
        seed       => $prng_seed,
        %args,
    );

    
    my $lists_no_canape = $sp_no_canape->get_list_names_across_elements;
    is ((scalar grep {/>>CANAPE.*?>>/} keys %$lists_no_canape), 0, 'no unexpected CANAPE list');

    my $lists_has_canape = $sp_has_canape->get_list_names_across_elements;
    my @canape_list_names = grep {/>>CANAPE.*?>>/} keys %$lists_has_canape;
    is (scalar @canape_list_names, 2, 'has CANAPE list');
    
    my @index_keys = qw /CANAPE_CODE NEO PALAEO MIXED SUPER/;
    foreach my $list_name (@canape_list_names) {
        foreach my $element ($sp_has_canape->get_element_list_sorted) {
            my $listref = $sp_has_canape->get_list_ref(
                element    => $element,
                list       => $list_name,
                autovivify => 0,
            );

            if (!defined $listref->{CANAPE_CODE}) {
                is [ @$listref{@index_keys} ],
                    [ undef, undef, undef, undef, undef ],
                    "expected values undef, $element";
            }
            elsif ($listref->{CANAPE_CODE} == 0) {
                is [ @$listref{@index_keys} ],
                    [ 0, 0, 0, 0, 0 ],
                    "expected values non-sig, $element";
            }
            elsif ($listref->{CANAPE_CODE} == 1) {
                is [ @$listref{@index_keys} ],
                    [ 1, 1, 0, 0, 0 ],
                    "expected values neo, $element";
            }
            elsif ($listref->{CANAPE_CODE} == 2) {
                is [ @$listref{@index_keys} ],
                    [ 2, 0, 1, 0, 0 ],
                    "expected values palaeo, $element";
            }
            elsif ($listref->{CANAPE_CODE} == 3) {
                is [ @$listref{@index_keys} ],
                    [ 3, 0, 0, 1, 0 ],
                    "expected values mixed, $element";
            }
            elsif ($listref->{CANAPE_CODE} == 4) {
                is [ @$listref{@index_keys} ],
                    [ 4, 0, 0, 0, 1 ],
                    "expected values super, $element";
            }
        }
    }
    return;
}

sub test_canape_classification_method {
    #  directly test the sub
    my %canape_sets = (
        invalid => {
            p_rank_list_ref => {PHYLO_RPE2 => 0.01, PE_WE => undef, PHYLO_RPE_NULL2 => 0.94},
            base_list_ref   => {PE_WE => undef},
            expected => {
                CANAPE_CODE => undef, NEO => undef,
                PALAEO      => undef, MIXED => undef,
                SUPER       => undef,
            },
        },
        non_sig => {
            p_rank_list_ref => {PHYLO_RPE2 => 0.01, PE_WE => undef, PHYLO_RPE_NULL2 => 0.94},
            base_list_ref   => {PE_WE => 10},
            expected => {
                CANAPE_CODE => 0, NEO   => 0,
                PALAEO      => 0, MIXED => 0,
                SUPER       => 0,
            },
        },
        neo => {
            p_rank_list_ref => {PHYLO_RPE2 => 0.01, PE_WE => 0.976, PHYLO_RPE_NULL2 => 0.98},
            base_list_ref   => {PE_WE => 10},
            expected => {
                CANAPE_CODE => 1, NEO => 1,
                PALAEO      => 0, MIXED => 0,
                SUPER       => 0,
            },
        },
        palaeo => {
            p_rank_list_ref => {PHYLO_RPE2 => 0.978, PE_WE => 0.976, PHYLO_RPE_NULL2 => 0.94},
            base_list_ref   => {PE_WE => 10},
            expected => {
                CANAPE_CODE => 2, NEO => 0,
                PALAEO      => 1, MIXED => 0,
                SUPER       => 0,
            },
        },
        mixed => {
            p_rank_list_ref => {PHYLO_RPE2 => undef, PE_WE => 0.98, PHYLO_RPE_NULL2 => 0.984},
            base_list_ref   => {PE_WE => 10},
            expected => {
                CANAPE_CODE => 3, NEO => 0,
                PALAEO      => 0, MIXED => 1,
                SUPER       => 0,
            },
        },
        super => {
            p_rank_list_ref => {PHYLO_RPE2 => undef, PE_WE => 0.991, PHYLO_RPE_NULL2 => 0.991},
            base_list_ref   => {PE_WE => 10},
            expected => {
                CANAPE_CODE => 4, NEO => 0,
                PALAEO      => 0, MIXED => 0,
                SUPER       => 1,
            },
        },
    );
    
    
    my $sp = Biodiverse::Spatial->new (name => 'gorb');
    foreach my $key (sort keys %canape_sets) {
        my $components       = $canape_sets{$key};
        my $prank_list_ref   = $components->{p_rank_list_ref};
        my $base_list_ref    = $components->{base_list_ref};
        my $expected         = $components->{expected};
        my $results_list_ref = {};

        my $res = $sp->assign_canape_codes_from_p_rank_results(
            p_rank_list_ref  => $prank_list_ref,
            base_list_ref    => $base_list_ref,
            results_list_ref => $results_list_ref,
        );
        is $results_list_ref, $expected, "expected CANAPE vals for $key";
    }

}

