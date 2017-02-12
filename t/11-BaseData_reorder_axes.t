#!/usr/bin/perl -w

#  Tests for basedata re-ordering of label axes

use strict;
use warnings;
use English qw { -no_match_vars };

use Test::Lib;
use rlib;

local $| = 1;

#use Test::More tests => 5;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::TestHelpers qw /:basedata/;


#  reordering of axes
REORDER:
{
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

    my ($orig, $new);
    
    my $type = 'sample counts';
    $orig = $bd->get_group_sample_count (element => '0.5:1.5');
    $new  = $new_bd->get_group_sample_count (element => '1.5:0.5');
    ok ($orig == $new, "Group $type match");
    
    $orig = $bd->get_label_sample_count (element => $test_label);
    $new  = $new_bd->get_label_sample_count (element => $test_label);
    ok ($orig == $new, "Label $type match");

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
        ok ($props->{$key} == $value, "Group remapped $key == $value");
    }

    $el_ref = $new_bd->get_labels_ref;
    $props = $el_ref->get_list_values (
        element => $test_label,
        list    => 'PROPERTIES'
    );
    while (my ($key, $value) = each %$lb_props) {
        ok ($props->{$key} == $value, "Label remapped $key == $value");
    }
    
}


done_testing();
