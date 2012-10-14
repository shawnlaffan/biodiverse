#!/usr/bin/perl -w
#
#  tests for both normal and lowmem matrices, where they overlap in methods

use strict;
use warnings;

use FindBin qw/$Bin/;
use rlib;

use Test::More;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Test::More; # tests => 2;
use Test::Exception;

use Biodiverse::TestHelpers qw /:matrix/;


use Biodiverse::Matrix;
use Biodiverse::Matrix::LowMem;

my @classes = qw /Biodiverse::Matrix Biodiverse::Matrix::LowMem/;

foreach my $class (@classes) {
    run_main_tests($class);
}

foreach my $class (@classes) {
    run_with_site_data ($class);
}

#  now check with lower precision
{
    my $class = 'Biodiverse::Matrix';
    my $precision = '%.1f';
    run_with_site_data ($class, VAL_INDEX_PRECISION => $precision);
}

#  NEED TO TEST EFFECT OF DELETIONS

sub run_main_tests {
    my $class = shift;

    note "\nUsing class $class\n\n";

    my $e;  #  for errors

    my $tmp_mx_file = write_data_to_temp_file (get_matrix_data());
    my $fname = $tmp_mx_file->filename;
    my $mx = eval {
        $class->new (
            NAME       => "test matrix $class",
            ELEMENT_COLUMNS => [0],
        );
     };    
    $e = $EVAL_ERROR;
    diag $e if $e;

    ok (!$e, "created $class object without error");

    eval {
        $mx->import_data (
            file => $fname,
        );
    };
    $e = $EVAL_ERROR;
    diag $e if $e;

    ok (!$e, 'imported data');
    
    eval {
        $mx->element_pair_exists();
    };
    $e = Exception::Class->caught;
    ok (defined $e, 'Raised exception for missing argument: ' . $e->error);

    my @elements_in_mx = qw /a b c d e f/;
    foreach my $element (@elements_in_mx) {
        my $in_mx = $mx->element_is_in_matrix (element => $element);
        ok ($in_mx, "element $element is in the matrix");
    }

    my @elements_not_in_mx = qw /x y z/;
    foreach my $element (@elements_not_in_mx) {
        my $in_mx = $mx->element_is_in_matrix (element => $element);
        ok (!$in_mx, "element $element is not in the matrix");
    }
    
    #  now we check some of the values
    my %expected = (
        a => {
            b => 1,
            d => 4,
            f => 1,
        },
        d => {
            f => undef,
            e => 4,
        },
    );

    while (my ($el1, $hash1) = each %expected) {
        while (my ($el2, $exp_val) = each %$hash1) {
            my $val;

            #  check the pair exists
            $val = $mx->element_pair_exists (element1 => $el1, element2 => $el2);
            if ($el1 eq 'd' && $el2 eq 'f') {
                $val = !$val;
            }
            ok ($val, "element pair existence: $el1 => $el2");

            my $exp_txt = defined $exp_val ? $exp_val : 'undef';
            $val = $mx->get_value (element1 => $el1, element2 => $el2);
            is ($val, $exp_val, "got $exp_txt for pair $el1 => $el2");
            
            #  now the reverse
            $val = $mx->get_value (element2 => $el1, element1 => $el2);
            is ($val, $exp_val, "got $exp_txt for pair $el2 => $el1");
        }
    }
    
    #  check the extreme values
    my $expected_min = 1;
    my $expected_max = 6;
    is ($mx->get_min_value, $expected_min, "Got correct min value, $class");
    is ($mx->get_max_value, $expected_max, "Got correct max value, $class");

    #  get the element count
    my $expected_el_count = 6;
    is ($mx->get_element_count, $expected_el_count, "Got correct element count");

    #  get the element count
    my $expected = 11;
    is ($mx->get_element_pair_count, $expected, "Got correct element pair count");
}


sub run_with_site_data {
    my ($class, %args) = @_;

    note "\nUsing class $class\n\n";

    my $e;  #  for errors

    my $mx = get_matrix_object_from_sample_data($class, %args);
    ok (defined $mx, "created $class object");
    
    #  get the element count
    my $expected = 68;
    is ($mx->get_element_count, $expected, "Got correct element count, $class");

    #  get the element pair count
    $expected = 2346;
    is ($mx->get_element_pair_count, $expected, "Got correct element pair count, $class");    
    
    #  check the extreme values
    my $expected_min = 0.00063;
    my $expected_max = 0.0762;
    
    is ($mx->get_min_value, $expected_min, "Got correct min value, $class");
    is ($mx->get_max_value, $expected_max, "Got correct max value, $class");
}

done_testing();


######################################

sub get_matrix_data {
    return get_data_section('MATRIX_DATA');
}


1;

__DATA__

@@ MATRIX_DATA
x -
a -
b 1 -
c 2 3 -
d 4 5 6 -
e 1 2 3 4 -
f 1

@@ placeholder
- a b c d e

