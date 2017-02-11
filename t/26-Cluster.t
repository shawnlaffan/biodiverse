#!/usr/bin/perl -w
#
#  tests for both normal and lowmem matrices, where they overlap in methods

use 5.010;
use strict;
use warnings;
use Carp;

use FindBin qw/$Bin/;
use Test::Lib;
use rlib;
use List::Util qw /first/;
use File::Temp qw /tempfile/;

use Test::More;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Test::More; # tests => 2;
use Test::Exception;

use Biodiverse::TestHelpers qw /:cluster :tree/;
use Biodiverse::Cluster;

my $default_prng_seed = 2345;
my @linkages = qw /
    link_average
    link_recalculate
    link_minimum
    link_maximum
    link_average_unweighted
/;


use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @subs = grep {$_ =~ 'main::test_'} $obj->functions();
#
#use Class::Inspector;
#my @subs = Class::Inspector->functions ('main::');

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


#  make sure we get the same result with the same prng across two runs
sub test_same_results_given_same_prng_seed {
    my $data = get_cluster_mini_data();
    my $bd = get_basedata_object (data => $data, CELL_SIZES => [1,1]);
    
    check_order_is_same_given_same_prng (basedata_ref => $bd);
    
    my $site_bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 300000]);
    check_order_is_same_given_same_prng (basedata_ref => $site_bd);
}

sub test_linkages_delete_outputs {
    _test_linkages (delete_outputs => 1);
}

sub test_linkages_no_delete_outputs {
    _test_linkages (delete_outputs => 0);
}

sub _test_linkages {
    my %args = @_;
    
    use Config;
    my $bits = $Config{archname} =~ /x(86_64|64)/ ? 64 : 32;

    local $TODO = 'These tests only pass on 64 bit architectures' if $bits != 64;

    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 300000]);

    my $fh;
    if ($ENV{BD_EXPORT_TEST_TREES_TO_NEXUS}) {
        #  generate results if needed (and when certain)
        my $file_name = $0 . '.results';
        $file_name =~ s/\.t\./\./;  #  remove the .t 
        open($fh, '>', $file_name) or die "Unable to open $file_name to write results sets to";
        say {$fh} '@@ SITE_DATA_NEWICK_TREE';
    }

    foreach my $linkage (@linkages) {
        my $cl = $bd->add_cluster_output (
            name => $linkage,
            #CLUSTER_TIE_BREAKER => [ENDW_WE => 'max'],  #  need to update expected values before using the tie breaker
            #MATRIX_INDEX_PRECISION => undef,  #  use old default for now
        );
        $cl->run_analysis (
            prng_seed        => $default_prng_seed,
            linkage_function => $linkage,
            cluster_tie_breaker => [ENDW_WE => 'max', ABC3_SUM_ALL => 'max'],
        );

        if ($fh) {
            say {$fh} "$linkage " . $cl->to_newick;
        }

        my $comparison_tree = get_site_data_as_tree ($linkage);

        my $suffix = $args{delete_outputs} ? ', no matrix recycle' : ', recycled matrix';

        my $are_same = $cl->trees_are_same (comparison => $comparison_tree);
        ok ($are_same, "Exact match using $linkage" . $suffix);

        #say join "\n", ('======') x 4;
        #say "=== $linkage " . $cl->to_newick;
        #say join "\n", ('======') x 4;

        my $nodes_have_matching_terminals = $cl->trees_are_same (
            comparison     => $comparison_tree,
            terminals_only => 1,
        );
        ok (
            $nodes_have_matching_terminals,
            "Nodes have matching terminals using $linkage" . $suffix,
        );

        if ($args{delete_outputs}) {
            $bd->delete_all_outputs;
        }
    }    
}

sub test_linkages_and_check_replication {
    cluster_test_linkages_and_check_replication (
        type          => 'Biodiverse::Cluster',
        linkage_funcs => \@linkages,
    );
}

sub test_tie_breaker_croak_on_missing_args  {
    my $data = get_cluster_mini_data();
    my $bd = get_basedata_object (data => $data, CELL_SIZES => [1,1]);
    my $tie_breaker = 'PD';

    my $cl1 = $bd->add_cluster_output (
        name => "should croak",
        CLUSTER_TIE_BREAKER => [$tie_breaker => 'max'],
    );
    my $success = eval {
        $cl1->run_analysis ();
    };
    my $e = $EVAL_ERROR;
    isnt ($e, '', 'Tie breaker croaked when missing an argument');
    #note $e;
}

sub test_linkages_and_check_mx_precision {
    cluster_test_linkages_and_check_mx_precision(type => 'Biodiverse::Cluster');
}


#  need to add tie breaker
sub check_order_is_same_given_same_prng {
    my %args = @_;
    my $bd = $args{basedata_ref};
    
    my $prng_seed = $args{prng_seed} || $default_prng_seed;
    
    my $cl1 = $bd->add_cluster_output (name => 'cl1');
    my $cl2 = $bd->add_cluster_output (name => 'cl2');
    my $cl3 = $bd->add_cluster_output (name => 'cl3');
    
    $cl1->run_analysis (
        prng_seed => $prng_seed,
    );
    $cl2->run_analysis (
        prng_seed => $prng_seed,
    );
    $cl3->run_analysis (
        prng_seed => $prng_seed + 1,  #  different prng
    );
    
    my $newick1 = $cl1->to_newick;
    my $newick2 = $cl2->to_newick;
    my $newick3 = $cl3->to_newick;
    
    is   ($newick1, $newick2, 'trees are the same');
    isnt ($newick1, $newick3, 'trees are not the same');
}


#  Need to use an index that needs arguments
#  so we exercise the whole shebang.
sub test_matrix_recycling {
    my %args = @_;
    cluster_test_matrix_recycling (
        %args,
        index => 'SORENSON',
        type => 'Biodiverse::Cluster',
    );

    
    #  need to test one with different phylogenetic trees
    
}

sub test_no_matrix_recycling_when_indices_differ {
    my %args = @_;
    
    cluster_test_no_matrix_recycling_when_indices_differ (
        %args,
        indices => [qw/SORENSON JACCARD/],
        type => 'Biodiverse::Cluster',
    );
}

#  shadow matrix should contain all pair combinations across both matrices?
#  No - let user do so explicitly using sp_select_all() as final condition.
sub test_two_spatial_conditions {
    my %args = @_;

    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);
    my $tie_breaker = [ENDW_WE => 'max'];

    my %analysis_args = (
        cache_abc          => 0,
        index              => 'SORENSON',
        linkage_function   => 'link_average',
    );

    my $cond1 = '$nbr_y > 1500000 && $y > 1500000';
    my $spatial_conditions1 = [$cond1];
    my $spatial_conditions2 = [
        $cond1,
        'sp_select_all()',
    ];

    #  run cl2 before cl1 for debugging purposes
    my $cl2 = $bd->add_cluster_output (name => 'cl2');
    $cl2->set_param (CLUSTER_TIE_BREAKER => $tie_breaker);
    $cl2->set_param (CACHE_ABC => 0);
    $cl2->run_analysis (
        %analysis_args,
        spatial_conditions => $spatial_conditions2,
    );


    my $cl1 = $bd->add_cluster_output (name => 'cl1');
    $cl1->set_param (CLUSTER_TIE_BREAKER => $tie_breaker);
    $cl1->set_param (CACHE_ABC => 0);
    $cl1->run_analysis (
        %analysis_args,
        spatial_conditions => $spatial_conditions1,
    );

    ok (
        $cl1->contains_tree (comparison => $cl1),
        'contains_tree works - cluster 1 contains itself'
    );

    #  Ignore the root node since it can have a different length
    #  and thus won't always match.
    ok (
        $cl2->contains_tree (comparison => $cl1, ignore_root => 1),
        'Cluster with two conditions contains cluster with one condition '
        . 'when first spatial condition is same'
    );

    my $block_cond = 'sp_block (size => 400000)';
    my $spatial_conditions3 = [$block_cond];
    my $spatial_conditions4 = [$block_cond, 'sp_select_all()'];
    
    my $cl3 = $bd->add_cluster_output (name => 'cl3');
    $cl3->set_param (CLUSTER_TIE_BREAKER => $tie_breaker);
    $cl3->set_param (CACHE_ABC => 0);
    $cl3->run_analysis (
        %analysis_args,
        spatial_conditions => $spatial_conditions3,
    );
    
    my $cl4 = $bd->add_cluster_output (name => 'cl4');
    $cl4->set_param (CLUSTER_TIE_BREAKER => $tie_breaker);
    $cl4->set_param (CACHE_ABC => 0);
    $cl4->run_analysis (
        %analysis_args,
        spatial_conditions => $spatial_conditions4,
    );
    
    ok (
        $cl3->contains_tree (comparison => $cl3),
        'contains_tree works for sp_block - cluster 3 contains itself'
    );
    my $cl3_root_child_count = $cl3->get_child_count;

    #  Ignore the root node and its immediate children
    #  since they can have different lengths
    #  and thus won't always match.
    ok (
        $cl4->contains_tree (
            comparison  => $cl3,
            ignore_root => 1,
            correction  => -$cl3_root_child_count,
        ),
        'Cluster with two conditions contains cluster with condition '
        . 'when first spatial condition is same (sp_block)'
    );


    my $spatial_conditions5 = [$block_cond, $cond1];
    my $spatial_conditions6 = [$block_cond, $cond1, 'sp_select_all()'];
    
    my $cl5 = $bd->add_cluster_output (name => 'cl5');
    $cl5->set_param (CLUSTER_TIE_BREAKER => $tie_breaker);
    $cl5->set_param (CACHE_ABC => 0);
    $cl5->run_analysis (
        %analysis_args,
        spatial_conditions => $spatial_conditions5,
    );

    my $cl6 = $bd->add_cluster_output (name => 'cl6');
    $cl6->set_param (CLUSTER_TIE_BREAKER => $tie_breaker);
    $cl6->set_param (CACHE_ABC => 0);
    $cl6->run_analysis (
        %analysis_args,
        spatial_conditions => $spatial_conditions6,
    );
    
    ok (
        $cl6->contains_tree (comparison => $cl6),
        'contains_tree works for triple conditions'
    );
    my $cl5_root_child_count = $cl5->get_child_count;

    #  Ignore the root node and its immediate children
    #  since they can have different lengths
    #  and thus won't always match.
    ok (
        $cl6->contains_tree (
            comparison  => $cl5,
            ignore_root => 1,
            correction  => -$cl5_root_child_count,
        ),
        'Cluster with three conditions contains cluster with two conditions'
    );
    
    
}


sub test_exception_for_invalid_linkage {
    my $data = get_cluster_mini_data();
    my $bd = get_basedata_object (data => $data, CELL_SIZES => [1,1]);
    
    my $cl = $bd->add_cluster_output (name => 'test invalid linkage');
    my $success = eval {
        $cl->run_analysis (linkage_function => 'link_barry_the_wonder_dog');
        1;
    };
    my $e = $@;
    ok ($e, 'exception thrown when invalid linkage function passed');

    my $cl2 = $bd->add_cluster_output (name => 'test undef linkage');
    $success = eval {
        $cl2->run_analysis ();
        1;
    };
    $e = $@;
    ok (!$e, 'no exception thrown when no linkage function passed');
    
}


sub test_mx_direct_write_to_file {
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [500000, 500000]);
    #my $bd = get_basedata_object_from_site_data(CELL_SIZES => [700000, 700000]);

    my %analysis_args = (
        cache_abc          => 0,
        index              => 'SORENSON',
        linkage_function   => 'link_average',
    );

    my ($fh, $fname) = tempfile (TEMPLATE => 'bd_XXXX', TEMPDIR => 1);
    my $cl = $bd->add_cluster_output (name => 'write_mx_to_file');
    $cl->run_analysis (
        %analysis_args,
        file_handles => [$fh],
    );
    $fh->close;

    open($fh, '<', $fname) or die "test_mx_direct_write_to_file: Cannot open $fname\n";

    my $lines;
    {
        local $/ = undef;
        $lines = <$fh>;
    }

    my $expected = get_data_section ('test_mx_direct_write_to_file');

    #  avoid line ending problems
    $lines    =~ s/\r//gs;
    $expected =~ s/\r//gs;
    $lines    =~ s/\n\n//g;
    $expected =~ s/\n\n//g;

    is ($lines, $expected, 'got expected mx to file')
}

######################################


sub get_cluster_mini_data_newick {
    return q{((('2.5:1.5':0,'3.5:1.5':0,'3.5:2.5':0)'3___':0.2,('1.5:1.5':0,'1.5:2.5':0,'2.5:2.5':0)'2___':0.2)'4___':0)'5___':0}
}

sub get_site_data_as_tree {
    my $comp_nwk = get_site_data_newick_tree(@_);

    my $read_nex = Biodiverse::ReadNexus->new();
    my $success = eval {$read_nex->import_data (data => $comp_nwk)};
    croak $@ if $@;

    my $tree_arr = $read_nex->get_tree_array;
    my $comparison_tree = $tree_arr->[0];

    return $comparison_tree;
}

sub get_site_data_newick_tree {
    my $label = shift // 'link_average';
    my $data = get_data_section('SITE_DATA_NEWICK_TREE');
    $data =~ s/\n+\z//m;  #  clear all trailing newlines
    my @data = split "\n", $data;
    while (my $line = shift @data) {
        next if not $line =~ /^$label/;
        my ($name, $newick) = split / /, $line;
        return $newick;
    }
    croak "should not get this far\n";
}


sub cluster_test_no_matrix_recycling_when_indices_differ {
    my %args = @_;
    my $type  = $args{type}  // 'Biodiverse::Cluster';
    my $indices = $args{indices} // [qw /JACCARD SORENSON/];
    my $tie_breaker = exists $args{tie_breaker}  #  use undef if the user passed the arg key
        ? $args{tie_breaker}
        : [
           ENDW_WE => 'maximise',
           PD      => 'maximise',
           ABC3_SUM_ALL => 'maximise',
           none         => 'maximise'
        ];


    my $bd1 = get_basedata_object_from_site_data(CELL_SIZES => [300000, 300000]);
    #my $bd2 = $bd1->clone;

    my $tree_ref1 = $args{tree_ref} // get_tree_object_from_sample_data();

    my $index1 = $indices->[0];
    my $index2 = $indices->[1];

    my %analysis_args = (
        %args,
        tree_ref => $tree_ref1,
        cluster_tie_breaker => $tie_breaker,
    );

    my $cl1a = $bd1->add_output (name => 'cl1a mx recyc', type => $type);
    $cl1a->run_analysis (%analysis_args, index => $index1);

    my $cl1b = $bd1->add_output (name => 'cl1b mx recyc', type => $type);
    $cl1b->run_analysis (%analysis_args, index => $index2);

    ok (
        !$cl1a->trees_are_same (comparison => $cl1b),
        'Clustering does not reycle matrices when index differs',
    );

    check_matrices_differ ($cl1a, $cl1b, 'JACCARD vs SORENSON');

    my $cl1c = $bd1->add_output (name => 'cl1c mx recyc', type => $type);
    $cl1c->run_analysis (%analysis_args, index => 'PHYLO_JACCARD');

    my $cl1d = $bd1->add_output (name => 'cl1d mx recyc', type => $type);
    $cl1d->run_analysis (%analysis_args, index => 'PHYLO_SORENSON');

    ok (
        !$cl1c->trees_are_same (comparison => $cl1d),
        'Clustering does not reycle matrices when index differs',
    );

    check_matrices_differ ($cl1c, $cl1d, 'PHYLO JACCARD vs SORENSON');

    #  now we need to check if we get differences when the arguments differ
    my $tree_ref2 = $tree_ref1->clone;
    foreach my $node (values %{$tree_ref2->get_node_hash}) {
        $node->set_length (length => ($node->get_length + rand()));
        $node->delete_cached_values;
    }
    $tree_ref2->delete_cached_values;
    $tree_ref2->delete_cached_values_below;

    ok (!$tree_ref1->trees_are_same(comparison => $tree_ref2), 'tree2 is not the same as tree1');

    my $cl1e = $bd1->add_output (name => 'cl1e mx recyc', type => $type);
    $cl1e->run_analysis (%analysis_args, tree_ref => $tree_ref2, index => 'PHYLO_JACCARD');

    ok (
        !$cl1c->trees_are_same (comparison => $cl1e),
        'Clustering does not reycle matrices when phylo index same but tree differs',
    );

    check_matrices_differ ($cl1c, $cl1e, 'PHYLO JACCARD vs PHYLO JACCARD different tree');

    #  now we try with a different basedata
    my $cl2c = $bd1->add_output (name => 'cl2c mx recyc', type => $type);
    $cl2c->run_analysis (%analysis_args, index => 'PHYLO_JACCARD');

    ok (
        $cl1c->trees_are_same (comparison => $cl2c),
        'Clustering same for different basedatas when tree_ref same',
    );

    check_matrices_differ ($cl1c, $cl2c, 'PHYLO JACCARD vs PHYLO JACCARD', 'use_is');

}

sub check_matrices_differ {
    my ($cl1a, $cl1b, $msg_suffix, $use_is) = @_;

    my @mx1a = $cl1a->get_orig_matrices;
    my @mx1b = $cl1b->get_orig_matrices;
    
    my @elements = $mx1a[0]->get_elements_as_array;

    my ($i, $same_count) = (0, 0);
    EL1:
    foreach my $el1 (@elements) {
        EL2:
        foreach my $el2 (@elements) {
            next EL2 if $el1 eq $el2;
            my $val1 = $mx1a[0]->get_defined_value_aa ($el1, $el2);
            my $val2 = $mx1b[0]->get_defined_value_aa ($el1, $el2);

            $i++;
            $same_count ++ if $val1 == $val2;
            last EL1 if $val1 != $val2;
        }
    }
    if ($use_is) {
        is ($i, $same_count, 'matrices same ' . $msg_suffix);
    }
    else {
        isnt ($i, $same_count, 'matrices do not match so therefore were not recycled ' . $msg_suffix);
    }
}


1;

__DATA__


@@ SITE_DATA_NEWICK_TREE
link_average ((((((('3300000:2250000':0.2,'3500000:2250000':0.2)'8___':0.0666666666666667,'3300000:2850000':0.266666666666667)'11___':0.177777777777778,'3100000:2850000':0.444444444444444)'24___':0.090755772005772,('3500000:1950000':0.285714285714286,'3700000:1950000':0.285714285714286)'13___':0.249485930735931)'28___':0.098133116883117,'3300000:1950000':0.633333333333333)'32___':0.293609565038136,(('3300000:1350000':0,'3500000:1650000':0)'3___':0.333333333333333,'3300000:1050000':0.333333333333333)'18___':0.593609565038136)'37___':0.024938300094094,((((((('2500000:1050000':0.2,'2500000:750000':0.2)'5___':0.103030303030303,'2300000:1050000':0.303030303030303)'15___':0.0315240315240315,'2700000:750000':0.334554334554335)'20___':0.131458472083472,(('2500000:1350000':0,'2100000:1050000':0,'2700000:1050000':0)'2___':0.2,'2300000:1350000':0.2)'7___':0.266012806637807)'25___':0.253481240981241,('1900000:1350000':0.333333333333333,'2100000:1350000':0.333333333333333)'17___':0.386160714285714)'34___':0.0784713203463203,(('2900000:150000':0.333333333333333,'2900000:450000':0.333333333333333)'19___':0.138095238095238,(('2900000:750000':0.2,'3100000:450000':0.2)'6___':0.0293650793650794,(('3100000:150000':0,'3300000:150000':0)'0___':0.142857142857143,'3300000:450000':0.142857142857143)'4___':0.0865079365079365)'9___':0.242063492063492)'26___':0.326536796536797)'35___':0.064184056978435,((((('3700000:1050000':0.333333333333333,'3700000:2250000':0.333333333333333)'16___':0.0833333333333333,'3900000:1350000':0.416666666666667)'23___':0.138888888888889,'3900000:1950000':0.555555555555556)'29___':0.0539682539682539,('3300000:3150000':0.5,'3500000:1350000':0.5)'27___':0.109523809523809)'31___':0.0820737457457936,(((('3700000:1350000':0.263157894736842,'3700000:1650000':0.263157894736842)'10___':0.0339009287925696,'3900000:1650000':0.297058823529412)'14___':0.110596678862933,'3500000:1050000':0.407655502392345)'22___':0.188254139750808,(('3100000:750000':0.28,'3300000:750000':0.28)'12___':0.0823188405797101,'3500000:750000':0.36231884057971)'21___':0.233590801563443)'30___':0.0956879131264504)'33___':0.1705518696742)'36___':0.0897317735217609)'38___':0
link_recalculate ('3300000:1950000':0.9375,'3100000:2850000':0.9375,((((((('3700000:1050000':0.333333333333333,'3700000:2250000':0.333333333333333)'21___':0.166666666666667,'3900000:1950000':0.5)'28___':0.0454545454545454,((((('3300000:2250000':0.2,'3500000:2250000':0.2)'10___':0.05,'3500000:1950000':0.25)'12___':0.0357142857142857,'3700000:1950000':0.285714285714286)'18___':0.142857142857143,'3300000:2850000':0.428571428571429,'3900000:1350000':0.428571428571429)'26___':-0.0372670807453417,(('3700000:1350000':0.263157894736842,'3700000:1650000':0.263157894736842)'14___':-0.025062656641604,'3900000:1650000':0.238095238095238)'15___':0.153209109730849)'27___':0.154150197628459)'30___':-0.00259740259740249,((((('3100000:450000':0.2,(('3100000:150000':0,'3300000:150000':0)'0___':0.142857142857143,'3300000:450000':0.142857142857143)'4___':0.0571428571428571,'2900000:750000':0.2)'7___':0.05,'3100000:750000':0.25)'11___':0.03,'3300000:750000':0.28)'17___':0.0533333333333333,'3500000:1050000':0.333333333333333)'19___':0.0512820512820512,'3500000:750000':0.384615384615385)'24___':0.158241758241758)'31___':0.132818532818533,(((('2100000:1350000':0.2,('2500000:1350000':0,'2100000:1050000':0,'2700000:1050000':0)'2___':0.2,'2300000:1350000':0.2)'9___':0.05,'2300000:1050000':0.25)'13___':0.0227272727272727,('2500000:1050000':0.2,'2500000:750000':0.2)'5___':0.0727272727272728)'16___':0.0606060606060607,'2700000:750000':0.333333333333333)'20___':0.342342342342342)'33___':0.0957528957528958,(('3300000:3150000':0.5,'3500000:1350000':0.5)'29___':0.1,(('3300000:1350000':0,'3500000:1650000':0)'3___':0.333333333333333,'3300000:1050000':0.333333333333333)'22___':0.266666666666667)'32___':0.171428571428571)'34___':0.107359307359307,('2900000:150000':0.333333333333333,'2900000:450000':0.333333333333333)'23___':0.545454545454545)'35___':0.0587121212121212,'1900000:1350000':0.9375)'38___':0
link_minimum (((('3900000:1950000':0.384615384615385,((('3700000:1350000':0.263157894736842,'3700000:1650000':0.263157894736842)'16___':0.0309597523219813,'3900000:1650000':0.294117647058823)'21___':0.0743034055727555,('2900000:450000':0.333333333333333,'1900000:1350000':0.333333333333333,'3500000:750000':0.333333333333333,(((('2100000:1350000':0.2,('2500000:1350000':0,'2100000:1050000':0,'2700000:1050000':0)'2___':0.2,'2300000:1350000':0.2)'10___':0.05,'2300000:1050000':0.25)'15___':0.0227272727272727,('2500000:1050000':0.2,'2500000:750000':0.2)'8___':0.0727272727272728)'17___':0.012987012987013,'2700000:750000':0.285714285714286)'19___':0.0476190476190477,((('2900000:150000':0.2,('3100000:450000':0.142857142857143,('3100000:150000':0,'3300000:150000':0)'0___':0.142857142857143,'3300000:450000':0.142857142857143)'5___':0.0571428571428571,'2900000:750000':0.2)'7___':0.05,'3100000:750000':0.25)'13___':0.03,'3300000:750000':0.28)'18___':0.0533333333333333)'25___':0.0350877192982456,'3500000:1050000':0.368421052631579)'33___':0.0161943319838056,('3300000:3150000':0.333333333333333,'3900000:1350000':0.333333333333333,'3700000:1050000':0.333333333333333,'3700000:2250000':0.333333333333333)'30___':0.0512820512820512)'35___':0.043956043956044,('3300000:1950000':0.333333333333333,((('3300000:2850000':0.2,'3300000:2250000':0.2,'3500000:2250000':0.2)'12___':0.05,'3500000:1950000':0.25)'14___':0.0357142857142857,'3700000:1950000':0.285714285714286)'20___':0.0476190476190477,'3100000:2850000':0.333333333333333)'27___':0.0952380952380952)'36___':0.025974025974026,'3500000:1350000':0.454545454545455)'37___':0.0454545454545454,(('3300000:1350000':0,'3500000:1650000':0)'3___':0.333333333333333,'3300000:1050000':0.333333333333333)'31___':0.166666666666667)'38___':0
link_maximum ('3300000:1950000':1,(('3300000:1350000':0,'3500000:1650000':0)'3___':0.333333333333333,'3300000:1050000':0.333333333333333)'18___':0.666666666666667,('1900000:1350000':0.333333333333333,'2100000:1350000':0.333333333333333)'17___':0.666666666666667,(('2900000:150000':0.333333333333333,'2900000:450000':0.333333333333333)'19___':0.380952380952381,(('2900000:750000':0.2,'3100000:450000':0.2)'6___':0.133333333333333,(('3100000:150000':0,'3300000:150000':0)'0___':0.142857142857143,'3300000:450000':0.142857142857143)'4___':0.19047619047619)'14___':0.380952380952381)'29___':0.285714285714286,(((('3700000:1050000':0.333333333333333,'3700000:2250000':0.333333333333333)'16___':0.166666666666667,'3900000:1350000':0.5)'23___':0.166666666666667,'3900000:1950000':0.666666666666667)'27___':0.0476190476190476,('3300000:3150000':0.5,'3500000:1350000':0.5)'24___':0.214285714285714)'28___':0.285714285714286,(((('3300000:2250000':0.2,'3500000:2250000':0.2)'8___':0.133333333333333,'3300000:2850000':0.333333333333333)'15___':0.166666666666667,'3100000:2850000':0.5)'22___':0.3,('3500000:1950000':0.285714285714286,'3700000:1950000':0.285714285714286)'11___':0.514285714285714)'30___':0.2,((('3500000:1050000':0.368421052631579,'3500000:750000':0.368421052631579)'20___':0.155388471177945,('3100000:750000':0.28,'3300000:750000':0.28)'10___':0.243809523809524)'25___':0.285714285714286,(('3700000:1350000':0.263157894736842,'3700000:1650000':0.263157894736842)'9___':0.0368421052631579,'3900000:1650000':0.3)'12___':0.509523809523809)'31___':0.19047619047619,(((('2500000:1050000':0.2,'2500000:750000':0.2)'5___':0.133333333333333,'2700000:750000':0.333333333333333)'13___':0.0512820512820512,'2300000:1050000':0.384615384615385)'21___':0.251748251748252,(('2500000:1350000':0,'2100000:1050000':0,'2700000:1050000':0)'2___':0.2,'2300000:1350000':0.2)'7___':0.436363636363636)'26___':0.363636363636364)'38___':0
link_average_unweighted ((((((((('3700000:1050000':0.333333333333333,'3700000:2250000':0.333333333333333)'16___':0.0833333333333333,'3900000:1350000':0.416666666666667)'23___':0.125,'3900000:1950000':0.541666666666667)'28___':0.0309440559440558,((('3700000:1350000':0.263157894736842,'3700000:1650000':0.263157894736842)'10___':0.0339009287925696,'3900000:1650000':0.297058823529412)'14___':0.108682803264847,'3500000:1050000':0.405741626794258)'22___':0.166869095816464)'29___':0.103399378399378,('3300000:3150000':0.5,'3500000:1350000':0.5)'25___':0.176010101010101)'33___':0.164549922128417,(((('3100000:750000':0.28,'3300000:750000':0.28)'12___':0.0823188405797101,'3500000:750000':0.36231884057971)'21___':0.153091187988213,(((('3100000:150000':0,'3300000:150000':0)'0___':0.142857142857143,'3300000:450000':0.142857142857143)'4___':0.0535714285714285,'3100000:450000':0.196428571428571)'5___':0.0369047619047619,'2900000:750000':0.233333333333333)'9___':0.28207669523459)'27___':0.138257555890102,('2900000:150000':0.333333333333333,'2900000:450000':0.333333333333333)'19___':0.320334251124692)'31___':0.186892438680492)'35___':0.0706840458031618,(('3300000:1350000':0,'3500000:1650000':0)'3___':0.333333333333333,'3300000:1050000':0.333333333333333)'18___':0.577910735608346)'36___':0.0308036014814809,((((('3300000:2250000':0.2,'3500000:2250000':0.2)'8___':0.0666666666666667,'3300000:2850000':0.266666666666667)'11___':0.191666666666667,'3100000:2850000':0.458333333333333)'24___':0.146766774891775,('3500000:1950000':0.285714285714286,'3700000:1950000':0.285714285714286)'13___':0.319385822510822)'30___':0.126149891774892,'3300000:1950000':0.73125)'34___':0.21079767042316)'37___':0.039149549508825,((((('2500000:1050000':0.2,'2500000:750000':0.2)'6___':0.103030303030303,'2300000:1050000':0.303030303030303)'15___':0.044039294039294,'2700000:750000':0.347069597069597)'20___':0.16043401043401,(('2500000:1350000':0,'2100000:1050000':0,'2700000:1050000':0)'2___':0.2,'2300000:1350000':0.2)'7___':0.307503607503608)'26___':0.167719606782107,('1900000:1350000':0.333333333333333,'2100000:1350000':0.333333333333333)'17___':0.341889880952381)'32___':0.305974005646271)'38___':0

@@ test_mx_direct_write_to_file
Element1,Element2,SORENSON
1750000:1250000,2250000:1250000,0.75
1750000:1250000,2250000:750000,0.666666666666667
1750000:1250000,2750000:1250000,1
1750000:1250000,2750000:250000,1
1750000:1250000,2750000:750000,1
1750000:1250000,3250000:1250000,1
1750000:1250000,3250000:1750000,1
1750000:1250000,3250000:2250000,1
1750000:1250000,3250000:250000,1
1750000:1250000,3250000:2750000,1
1750000:1250000,3250000:3250000,1
1750000:1250000,3250000:750000,1
1750000:1250000,3750000:1250000,1
1750000:1250000,3750000:1750000,1
1750000:1250000,3750000:2250000,1
1750000:1250000,3750000:750000,1
2250000:1250000,2250000:750000,0.166666666666667
2250000:1250000,2750000:1250000,0.75
2250000:1250000,2750000:250000,0.777777777777778
2250000:1250000,2750000:750000,0.411764705882353
2250000:1250000,3250000:1250000,0.692307692307692
2250000:1250000,3250000:1750000,1
2250000:1250000,3250000:2250000,1
2250000:1250000,3250000:250000,0.5
2250000:1250000,3250000:2750000,1
2250000:1250000,3250000:3250000,1
2250000:1250000,3250000:750000,0.583333333333333
2250000:1250000,3750000:1250000,0.6
2250000:1250000,3750000:1750000,0.826086956521739
2250000:1250000,3750000:2250000,1
2250000:1250000,3750000:750000,0.818181818181818
2250000:750000,2750000:1250000,0.666666666666667
2250000:750000,2750000:250000,0.714285714285714
2250000:750000,2750000:750000,0.466666666666667
2250000:750000,3250000:1250000,0.636363636363636
2250000:750000,3250000:1750000,1
2250000:750000,3250000:2250000,1
2250000:750000,3250000:250000,0.6
2250000:750000,3250000:2750000,1
2250000:750000,3250000:3250000,1
2250000:750000,3250000:750000,0.636363636363636
2250000:750000,3750000:1250000,0.666666666666667
2250000:750000,3750000:1750000,0.80952380952381
2250000:750000,3750000:2250000,1
2250000:750000,3750000:750000,0.777777777777778
2750000:1250000,2750000:250000,0.333333333333333
2750000:1250000,2750000:750000,0.818181818181818
2750000:1250000,3250000:1250000,0.714285714285714
2750000:1250000,3250000:1750000,1
2750000:1250000,3250000:2250000,1
2750000:1250000,3250000:250000,0.666666666666667
2750000:1250000,3250000:2750000,1
2750000:1250000,3250000:3250000,1
2750000:1250000,3250000:750000,0.888888888888889
2750000:1250000,3750000:1250000,0.857142857142857
2750000:1250000,3750000:1750000,0.882352941176471
2750000:1250000,3750000:2250000,1
2750000:1250000,3750000:750000,0.6
2750000:250000,2750000:750000,0.666666666666667
2750000:250000,3250000:1250000,0.75
2750000:250000,3250000:1750000,1
2750000:250000,3250000:2250000,1
2750000:250000,3250000:250000,0.428571428571429
2750000:250000,3250000:2750000,1
2750000:250000,3250000:3250000,1
2750000:250000,3250000:750000,0.789473684210526
2750000:250000,3750000:1250000,0.866666666666667
2750000:250000,3750000:1750000,0.888888888888889
2750000:250000,3750000:2250000,1
2750000:250000,3750000:750000,0.666666666666667
2750000:750000,3250000:1250000,0.75
2750000:750000,3250000:1750000,1
2750000:750000,3250000:2250000,1
2750000:750000,3250000:250000,0.333333333333333
2750000:750000,3250000:2750000,1
2750000:750000,3250000:3250000,1
2750000:750000,3250000:750000,0.407407407407407
2750000:750000,3750000:1250000,0.652173913043478
2750000:750000,3750000:1750000,0.846153846153846
2750000:750000,3750000:2250000,1
2750000:750000,3750000:750000,0.857142857142857
3250000:1250000,3250000:1750000,0.714285714285714
3250000:1250000,3250000:2250000,1
3250000:1250000,3250000:250000,0.818181818181818
3250000:1250000,3250000:2750000,1
3250000:1250000,3250000:3250000,1
3250000:1250000,3250000:750000,0.565217391304348
3250000:1250000,3750000:1250000,0.473684210526316
3250000:1250000,3750000:1750000,0.545454545454545
3250000:1250000,3750000:2250000,0.866666666666667
3250000:1250000,3750000:750000,0.6
3250000:1750000,3250000:2250000,1
3250000:1750000,3250000:250000,1
3250000:1750000,3250000:2750000,1
3250000:1750000,3250000:3250000,1
3250000:1750000,3250000:750000,0.888888888888889
3250000:1750000,3750000:1250000,0.857142857142857
3250000:1750000,3750000:1750000,0.882352941176471
3250000:1750000,3750000:2250000,0.8
3250000:1750000,3750000:750000,1
3250000:2250000,3250000:250000,1
3250000:2250000,3250000:2750000,0.2
3250000:2250000,3250000:3250000,1
3250000:2250000,3250000:750000,1
3250000:2250000,3750000:1250000,0.866666666666667
3250000:2250000,3750000:1750000,0.777777777777778
3250000:2250000,3750000:2250000,0.636363636363636
3250000:2250000,3750000:750000,1
3250000:250000,3250000:2750000,1
3250000:250000,3250000:3250000,1
3250000:250000,3250000:750000,0.545454545454545
3250000:250000,3750000:1250000,0.666666666666667
3250000:250000,3750000:1750000,0.904761904761905
3250000:250000,3750000:2250000,1
3250000:250000,3750000:750000,0.777777777777778
3250000:2750000,3250000:3250000,0.5
3250000:2750000,3250000:750000,0.9
3250000:2750000,3750000:1250000,0.75
3250000:2750000,3750000:1750000,0.684210526315789
3250000:2750000,3750000:2250000,0.5
3250000:2750000,3750000:750000,1
3250000:3250000,3250000:750000,0.888888888888889
3250000:3250000,3750000:1250000,0.857142857142857
3250000:3250000,3750000:1750000,0.882352941176471
3250000:3250000,3750000:2250000,0.8
3250000:3250000,3750000:750000,1
3250000:750000,3750000:1250000,0.4
3250000:750000,3750000:1750000,0.636363636363636
3250000:750000,3750000:2250000,0.769230769230769
3250000:750000,3750000:750000,0.619047619047619
3750000:1250000,3750000:1750000,0.310344827586207
3750000:1250000,3750000:2250000,0.636363636363636
3750000:1250000,3750000:750000,0.529411764705882
3750000:1750000,3750000:2250000,0.28
3750000:1750000,3750000:750000,0.7
3750000:2250000,3750000:750000,0.846153846153846
