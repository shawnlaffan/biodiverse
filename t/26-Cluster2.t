#  These tests were taking about 40% of the
#  run time when in 26-Cluster.pm.
#  Moving them will hopefully speed up the
#  test suite on parallel runs.

use 5.010;
use strict;
use warnings;
use Carp;

use FindBin qw/$Bin/;
use rlib;
use List::Util qw /first/;

use Test2::V0;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

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


sub test_cluster_single_cell {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'single cell',
        CELL_SIZES => [1],
    );
    $bd->add_element (
        group => '1.5',
        label => 'some_label',
    );
    like (
        dies {
            $bd->add_cluster_output (name => 'single cell cluster attempt')
        },
        qr/Cannot run a cluster type analysis with only a single group/,
        'Cluster dies when only single group',
    );
}


sub test_linkages_and_check_replication {
    cluster_test_linkages_and_check_replication (
        type          => 'Biodiverse::Cluster',
        linkage_funcs => \@linkages,
    );
}

sub test_linkages_and_check_mx_precision {
    cluster_test_linkages_and_check_mx_precision(type => 'Biodiverse::Cluster');
}

sub test_phylo_rw_turnover_mx {
    my $data = get_data_section('CLUSTER_MINI_DATA');
    $data =~ s/(?<!\w)\n+\z//m;  #  clear trailing newlines

    my $bd = Biodiverse::BaseData->new (
        CELL_SIZES => [1,1],
        NAME       => 'phylo_rw_turnover',
    );
    my @data = split "\n", $data;
    shift @data;
    foreach my $line (@data) {
        my @line = split ',', $line;
        last if !@line;
        my $gp = join ':', ($line[1] + 0.5, $line[2] + 0.5);
        $bd->add_element (
            group => $gp,
            label => $line[0],
        );
    }

    my $nwk = '((a:1,b:1),(c:1,d:1),e:1)';
    my $tree = Biodiverse::Tree->new;
    my %terminals;
    my $i = 1;
    foreach my $branch (qw /a b c d e f/) {
        $terminals{$branch}
            = $tree->add_node (name => $branch, length => $i);
        $i+=0.2;
    }
    my $internal1 = $tree->add_node (name => '1___', length => 1);
    $internal1->add_children (children => [@terminals{qw/a b/}]);
    my $internal2 = $tree->add_node (name => '2___', length => 1);
    $internal2->add_children (children => [@terminals{qw/c d/}]);
    my $internal3 = $tree->add_node (name => '3___', length => 1);
    $internal3->add_children (children => [@terminals{qw/e f/}]);
    my $internal4 = $tree->add_node (name => '4___', length => 1);
    $internal4->add_children (children => [$internal1, $internal2]);
    my $internal5 = $tree->add_node (name => '5___', length => 1);
    $internal5->add_children (children => [$internal3, $internal4]);

    my $cl = $bd->add_cluster_output (name => 'cl');
    $cl->run_analysis (
        prng_seed  => 12345,
        index      => 'PHYLO_RW_TURNOVER',
        tree_ref   => $tree,
        cluster_tie_breaker => [PE_WE => 'max'],
    );
    # say $cl->to_newick;
    my $mx_arr = $cl->get_orig_matrices;
    my $mx = $mx_arr->[0];

    my %expected = (
        PCT975 => 0.80597,
        PCT95  => 0.80597,
        MIN    => 0,
        PCT025 => 0,
        PCT05  => 0,
        MAX    => 0.80597,
        MEAN   => 0.3751808,
        SD     => 0.3047705823,
    );

    my $stats = $mx->get_summary_stats;
    #  avoid fp precision issues in the comparison
    foreach my $k (keys %$stats) {
        $stats->{$k} = $mx->round_to_precision_aa ($stats->{$k}, 10**10);
    }
    is ($stats, \%expected, 'got expected stats for phylo_rw_turnover mx');
}

sub test_rw_turnover_mx {
    my $data = get_data_section('CLUSTER_MINI_DATA');
    $data =~ s/(?<!\w)\n+\z//m;  #  clear trailing newlines

    my $bd = Biodiverse::BaseData->new (
        CELL_SIZES => [1,1],
        NAME       => 'rw_turnover',
    );
    my @data = split "\n", $data;
    shift @data;
    foreach my $line (@data) {
        my @line = split ',', $line;
        last if !@line;
        my $gp = join ':', ($line[1] + 0.5, $line[2] + 0.5);
        $bd->add_element (
            group => $gp,
            label => $line[0],
        );
    }


    my $cl = $bd->add_cluster_output (name => 'cl');
    $cl->run_analysis (
        prng_seed  => 12345,
        index      => 'RW_TURNOVER',
        cluster_tie_breaker => [ENDW_WE => 'max'],
    );
    # say $cl->to_newick;
    my $mx_arr = $cl->get_orig_matrices;
    my $mx = $mx_arr->[0];

    my %expected = (
        PCT975 => 0.833333,
        PCT95  => 0.833333,
        MIN    => 0,
        PCT025 => 0,
        PCT05  => 0,
        MAX    => 0.833333,
        MEAN   => 0.3923075333,
        SD     => 0.3162277347,
    );

    my $stats = $mx->get_summary_stats;
    #  avoid fp precision issues in the comparison
    foreach my $k (keys %$stats) {
        $stats->{$k} = $mx->round_to_precision_aa ($stats->{$k}, 10**10);
    }
    is ($stats, \%expected, 'got expected stats for rw_turnover mx');
}


sub test_cluster_node_calcs {

    my %args = @_;
    my $bd = $args{basedata_ref} || get_basedata_object_from_site_data(CELL_SIZES => [400000, 400000]);

    my $prng_seed = $args{prng_seed} || $default_prng_seed;
    my $tree_ref  = $args{tree_ref} || get_tree_object_from_sample_data();

    my $calcs = [qw/calc_pe calc_pe_lists calc_phylo_rpe2 calc_pe_central_lists calc_pd/];

    my $cl1 = $bd->add_cluster_output (name => 'cl1');
    $cl1->run_analysis (
        prng_seed => $prng_seed,
    );
    $cl1->run_spatial_calculations (
        tree_ref             => $tree_ref,
        spatial_calculations => $calcs,
        no_hierarchical_mode => 1,
    );
    my $cl2 = $bd->add_cluster_output (name => 'cl2');
    $cl2->run_analysis (
        prng_seed => $prng_seed,
    );
    $cl2->run_spatial_calculations (
        tree_ref             => $tree_ref,
        spatial_calculations => $calcs,
        no_hierarchical_mode => 0,
    );

    my $node_hash1 = $cl1->get_node_hash;
    my $node_hash2 = $cl2->get_node_hash;

    is [sort keys %$node_hash1], [sort keys %$node_hash2], 'paranoia check: same node names';

    my $prec = "%.10f";
    my (%aggregate1, %aggregate2);
    foreach my $node_name (sort keys %$node_hash1) {
        my $node1 = $node_hash1->{$node_name};
        my $node2 = $node_hash2->{$node_name};

        foreach my $list_name (sort grep {$_ !~ /NODE_VALUES/}$node1->get_hash_lists) {
            my $ref1 = $node1->get_list_ref_aa($list_name);
            my $ref2 = $node2->get_list_ref_aa($list_name);
            my $snapped1 = {map {$_ => snap_to_precision ($ref1->{$_}, $prec)} keys %$ref1};
            my $snapped2 = {map {$_ => snap_to_precision ($ref2->{$_}, $prec)} keys %$ref2};
            $aggregate1{$node_name}{$list_name} = $snapped1;
            $aggregate2{$node_name}{$list_name} = $snapped2;
        }
    }
    is \%aggregate2, \%aggregate1, 'same per-node index results with and without hierarchical mode';
}

__DATA__

@@ CLUSTER_MINI_DATA
label,x,y,samples
a,1,1,1
b,1,1,1
c,1,1,1
d,1,1,1
e,1,1,1
f,1,1,1
a,1,2,1
b,1,2,1
c,1,2,1
a,2,1,1
b,2,1,1
a,2,2,1
b,2,2,1
c,2,2,1
a,3,1,1
b,3,1,1
a,3,2,1
b,3,2,1
