#  Tests for basedata re-ordering of label axes

use strict;
use warnings;
use 5.010;

use English qw { -no_match_vars };
use Carp;

use Test::Lib;
use Test::Most;
use rlib;

local $| = 1;

#use Test::More tests => 5;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::TestHelpers qw /:basedata/;

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
    

    test_reorder_axes();
    test_drop_axis();

    done_testing;
    return 0;
}


sub test_drop_axis {
    my $bd_base = Biodiverse::BaseData->new (
        NAME       => 'bzork',
        CELL_SIZES => [1, 10, 100],
    );
    
    foreach my $i (1..10) {
        my $gp = join ':', $i-0.5, $i*10-5, $i*100-50;
        my $lb = join '_:', $i-0.5, $i*10-5, $i*100-50;
        $bd_base->add_element (
            group => $gp,
            label => $lb,
        );
    }
    
    my (@res, @origin, $gp, $lb);
    
    my $bd = $bd_base->clone;
    
    $lb = $bd->get_labels_ref;
    $gp = $bd->get_groups_ref;    
    is ($lb->get_axis_count, 3, 'got expected label axis count');
    is ($gp->get_axis_count, 3, 'got expected group axis count');

    #  some fails
    dies_ok (
        sub {$bd->drop_element_axis (axis => 20, type => 'label')},
        'axis too large',
    );
    dies_ok (
        sub {$bd->drop_element_axis (axis => -20, type => 'label')},
        'neg axis too large',
    );
    dies_ok (
        sub {$bd->drop_element_axis (axis => 'glert', type => 'label')},
        'non-numeric axis',
    );
    
    $bd->drop_element_axis (axis => 2, type => 'label');
    is ($lb->get_axis_count, 2, 'label axis count reduced');
    @res = $lb->get_cell_sizes;
    is ($#res, 1, 'label cell size array');
    @origin = $lb->get_cell_origins;
    is ($#origin, 1, 'label cell origins');
    
    $lb = $bd->get_labels_ref;
    $gp = $bd->get_groups_ref;    
    is ($lb->get_axis_count, 2, 'got expected label axis count after deletion');

    $bd = $bd_base->clone;
    $lb = $bd->get_labels_ref;
    $gp = $bd->get_groups_ref;
    
    $bd->drop_element_axis (axis => 1, type => 'group');
    is ($gp->get_axis_count, 2, 'group axis count reduced');
    @res = $gp->get_cell_sizes;
    is ($#res, 1, 'group cell size array');
    @origin = $gp->get_cell_origins;
    is ($#origin, 1, 'group cell origins');
    is ($gp->get_axis_count, 2, 'got expected group axis count after deletion');


    my $bd_with_outputs = $bd_base->clone;
    my $sp = $bd_with_outputs->add_spatial_output (name => 'spatialisationater');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => ['calc_richness'],
    );
    dies_ok (
        sub {$bd_with_outputs->drop_element_axis (axis => 1, type => 'label')},
        'dies with existing outputs',
    );
}



sub _repeat_test_reorder_axes {
    test_reorder_axes() for (1..1000);
}

#  reordering of axes
sub test_reorder_axes {
    my $bd = eval {
        get_basedata_object (
            x_spacing  => 1,
            y_spacing  => 1,
            CELL_SIZES => [1, 1],
            x_max      => 10,
            y_max      => 10,
            x_min      => 0,
            y_min      => 0,
            use_rand_counts => 1,
        );
    };
    croak $@ if $@;

    my $test_label = '0_0';
    my $lb_props = {blah => 25, blahblah => 10};
    my $lb = $bd->get_labels_ref;
    $lb->add_to_lists (
        element    => $test_label,
        PROPERTIES => $lb_props,
    );
    my $test_group_orig = '0.5:1.5';
    my $test_group_new  = '1.5:0.5';
    my $gp_props = {blah => 25, blahblah => 10};
    my $gp = $bd->get_groups_ref;
    $gp->add_to_lists (
        element    => $test_group_orig,
        PROPERTIES => $gp_props,
    );

    my $new_bd = eval {
        $bd->new_with_reordered_element_axes (
            GROUP_COLUMNS => [1,0],
            LABEL_COLUMNS => [0],
        );
    };
    my $error = $EVAL_ERROR;
    warn $error if $error;

    ok (defined $new_bd, 'Reordered axes');
    
    my (@got_groups, @orig_groups, @got_labels, @orig_labels);
    eval {
        @got_groups  = $new_bd->get_groups;
        @orig_groups = $bd->get_groups;
        @got_labels  = $new_bd->get_labels;
        @orig_labels = $bd->get_labels;
    };
    diag $@ if $@;

    is (scalar @got_groups, scalar @orig_groups, 'same group count');
    is (scalar @got_labels, scalar @orig_labels, 'same label count');

    my ($orig, $new);
    
    my $type = 'sample counts';
    $orig = $bd->get_group_sample_count (element => '0.5:1.5');
    eval {
        $new  = $new_bd->get_group_sample_count (element => '1.5:0.5');
    };
    diag $@ if $@;

    is ($new, $orig, "Group $type match");
    
    $orig = $bd->get_label_sample_count (element => $test_label);
    $new  = $new_bd->get_label_sample_count (element => $test_label);
    is ($new, $orig, "Label $type match");

    #  Need more tests of variety, range, properties etc.
    #  But first need to modify the basedata creation subs to give differing
    #  results per element.  This requires automating the elements used
    #  for comparison (i.e. not hard coded '0.5:1.5', '1.5:0.5')

    #  test label and group properties
    #  (should make more compact using a loop)
    my ($props, $el_ref);

    $el_ref = $new_bd->get_groups_ref;
    $props = $el_ref->get_list_values (
        element => $test_group_new,
        list    => 'PROPERTIES'
    );
    while (my ($key, $value) = each %$gp_props) {
        is ($value, $props->{$key}, "Group remapped $key == $value");
    }

    $el_ref = $new_bd->get_labels_ref;
    $props = $el_ref->get_list_values (
        element => $test_label,
        list    => 'PROPERTIES'
    );
    while (my ($key, $value) = each %$lb_props) {
        is ($value, $props->{$key}, "Label remapped $key == $value");
    }
    
}


done_testing();
