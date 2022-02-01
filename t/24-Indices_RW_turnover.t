use strict;
use warnings;

local $| = 1;

#  don't test plugins
local $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;

use rlib;
use Test2::V0;

use Biodiverse::Config;

use Biodiverse::TestHelpers qw{
    :runners
    :basedata
    :tree
    :utils
};

my $generate_result_sets = 0;

my @calcs_to_test = qw/
    calc_rw_turnover
    calc_phylo_rw_turnover
/;

my @calcs_for_debug = qw /
    calc_rw_turnover
    calc_phylo_rw_turnover
/;

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

    test_standard();
    test_extra_labels_in_basedata();
    test_extra_labels_on_tree();

    done_testing;
    return 0;
}

sub test_standard {
    run_indices_test1 (
        calcs_to_test      => [@calcs_to_test],
        #calc_topic_to_test => 'Phylogenetic Indices',
        generate_result_sets => $generate_result_sets,
    );
}

#  now try with extra labels that aren't on the tree
#  should be no difference in the phylo metrics - they should ignore the additional label
sub test_extra_labels_in_basedata {

    my $cb = sub {
        my %args = @_;
        my $bd = $args{basedata_ref};
        my $el_list1 = $args{element_list1};
        my $group = $el_list1->[0];

        $bd->add_element (
            group => $group,
            label => 'namenotontree:atall',
        );
    };

    my $overlay2 = {
        'PHYLO_RW_TURNOVER'   => '0.548854155622542',
        'PHYLO_RW_TURNOVER_A' => '0.714202952209455',
        'PHYLO_RW_TURNOVER_B' => 0,
        'PHYLO_RW_TURNOVER_C' => '0.868883672903968',
        'RW_TURNOVER'         => '0.680823682130818',
        'RW_TURNOVER_A'       => '1.11111111111111',
        'RW_TURNOVER_B'       => 1,
        'RW_TURNOVER_C'       => '1.37007169884446'
    };

    my %expected_results_overlay = (
        2 => $overlay2,
        #1 => {},
    );

    run_indices_test1 (
        calcs_to_test   => [@calcs_to_test],
        #calcs_to_test   => [@calcs_to_test, @calcs_for_debug],
        callbacks       => [$cb],
        no_strict_match => 0,
        expected_results_overlay => \%expected_results_overlay,
        generate_result_sets     => $generate_result_sets, 
    );
}

#  now try with extra labels that aren't in the basedata
#  These should be dropped in the trimming process, and so have no effct
sub test_extra_labels_on_tree {
    my $cb = sub {
        my %args = @_;
        my $tree = $args{tree_ref};

        my $root = $tree->get_root_node;
        
        use Biodiverse::TreeNode;
        my $node = Biodiverse::TreeNode-> new (
            name   => 'EXTRA_NODE',
            length => 1,
        );
        $root->add_children (children => [$node]);
    };

    run_indices_test1 (
        calcs_to_test   => [@calcs_to_test],
        #calcs_to_test   => [@calcs_to_test, @calcs_for_debug],
        callbacks       => [$cb],
        no_strict_match => 0,
        #expected_results_overlay => \%expected_results_overlay,
        generate_result_sets     => $generate_result_sets,
    );

}


done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'PHYLO_RW_TURNOVER'   => '0.548854155622542',
  'PHYLO_RW_TURNOVER_A' => '0.714202952209455',
  'PHYLO_RW_TURNOVER_B' => 0,
  'PHYLO_RW_TURNOVER_C' => '0.868883672903968',
  'RW_TURNOVER'   => '0.552184906870684',
  'RW_TURNOVER_A' => '1.11111111111111',
  'RW_TURNOVER_B' => 0,
  'RW_TURNOVER_C' => '1.37007169884446'
}

@@ RESULTS_1_NBR_LISTS
{
}
