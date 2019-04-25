#  Tests for basedata re-ordering of label axes

use strict;
use warnings;
use 5.010;

use English qw { -no_match_vars };
use Carp;

use Test::Lib;
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
    
    done_testing;
    return 0;
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
