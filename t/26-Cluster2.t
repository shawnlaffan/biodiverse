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
        PCT975 => 0.805970149253731,
        PCT95  => 0.805970149253731,
        MIN    => 0,
        PCT025 => 0,
        PCT05  => 0.32,
        MAX    => 0.805970149253731,
        MEAN   => 0.162,
    );

    my $stats = $mx->get_summary_stats;
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
        PCT975 => 0.833333333333333,
        PCT95  => 0.833333333333333,
        MIN    => 0,
        PCT025 => 0,
        PCT05  => 0.33,
        MAX    => 0.833333333333333,
        MEAN   => 0.167333333333333,
    );

    my $stats = $mx->get_summary_stats;
    is ($stats, \%expected, 'got expected stats for phylo_rw_turnover mx');
}

1;

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
