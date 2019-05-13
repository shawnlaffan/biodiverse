#  tests for both normal and lowmem matrices, where they overlap in methods
use 5.010;
use strict;
use warnings;
use utf8;


use FindBin qw/$Bin/;
use Test::Lib;
use rlib;
use Scalar::Util qw /blessed/;
use File::Compare;

use Test::More;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Test::More; # tests => 2;
use Test::Exception;

use Biodiverse::TestHelpers qw /:matrix :basedata/;


use Biodiverse::Matrix;
use Biodiverse::Matrix::LowMem;

my @classes = qw /
    Biodiverse::Matrix
    Biodiverse::Matrix::LowMem
/;

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
        $sub->();
    }

    done_testing;
    return 0;
}

sub test_to_table {
    foreach my $class (@classes) {
        _test_to_table ($class);
    }
}


sub test_trim {
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);
    $bd->trim (keep => [qw /Genus:sp10 Genus:sp11 Genus:sp12/]);

    foreach my $class (@classes) {
        my $mx = get_matrix_object_from_sample_data($class);
        _test_trim($mx, $bd);
    }
}

sub _test_trim {
    my ($mx, $bd) = @_;

    my $mx_el_count = $mx->get_element_count;
    my $mx_element_pair_count = $mx->get_element_pair_count;

    #  use a basedata object, then a simple array
    foreach my $ref ($bd, [$bd->get_labels, 'name_not_in_mx']) {
        my $mx_trim = $mx->clone;
        my $mx_keep = $mx->clone;

        my %trim_results = $mx_trim->trim (trim => $bd);
        my %keep_results = $mx_keep->trim (keep => $bd);

        my $mx_trim_el_count = $mx_trim->get_element_count;
        my $mx_keep_el_count = $mx_keep->get_element_count;

        #  two different checks to do the same thing
        is (
            $trim_results{DELETE_COUNT} + $keep_results{DELETE_COUNT},
            $mx_el_count,
            'check 1: deleted correct number of elements for class ' . blessed ($mx),
        );
        is (
            $mx_trim_el_count + $mx_keep_el_count,
            $mx_el_count,
            'check 2: deleted correct number of elements for class ' . blessed ($mx),
        );

        #  we have lower-left matrices with values along the diagonal
        #  so can predict what we should see if correct element pairs are deleted
        foreach my $mx_to_check ($mx_keep, $mx_trim) {
            my $observed = $mx_to_check->get_element_pair_count;
            my $el_count = $mx_to_check->get_element_count;

            my $exp = $el_count * ($el_count - 1) / 2 + $el_count;
            is (
                $observed,
                $exp,
                'deleted correct number of element pairs for class ' . blessed ($mx),
            );
        }
    }

    return;
}

sub test_remap_labels_from_hash {
    my $mx_main = create_matrix_object();
    #  make sure we test symmetric pair existence, e.g. a:c and c:a
    $mx_main->add_element (element1 => 'a', element2 => 'c', value => 10);

    my $mx_lowmem = $mx_main->clone->to_lowmem;
    
    my (%remap, @expected_new_labels);
    foreach my $label ($mx_main->get_labels) {
        $remap{$label} = uc $label;
        push @expected_new_labels, uc $label;
    }
    #  add some excess keys to ensure they are ignored
    @remap{qw/bodge1 bodge2 bodge3/} = ('blert') x 3;

    foreach my $data (['normal', $mx_main], ['lowmem', $mx_lowmem]) {
        my ($label, $mx) = @$data;

        eval {
            $mx->remap_labels_from_hash(remap => \%remap);
        };
        my $e = $EVAL_ERROR;
        ok (!$e, "got no exception from hash remap including excess keys");

        my @actual_new_labels = $mx->get_labels;

        # make sure everything we expect is there
        is_deeply
          [sort @actual_new_labels],
          [sort @expected_new_labels],
          "Got expected labels for $label matrix using hash remap";
    }
}



sub test_main_tests {
    foreach my $class (@classes) {
        run_main_tests($class);
    }
}

foreach my $class (@classes) {
    run_with_site_data ($class);
}

#  now check with lower precision
sub test_lower_precision {
    my $class = 'Biodiverse::Matrix';
    my $precision = '%.1f';
    run_with_site_data ($class, VAL_INDEX_PRECISION => $precision);
}

#  can one class substitute for the other?
sub test_class_substitution {
    my $normal_class = 'Biodiverse::Matrix';
    my $lowmem_class = 'Biodiverse::Matrix::LowMem';

    my $mx = create_matrix_object ($normal_class);
    
    $mx->to_lowmem;

    is (blessed ($mx), $lowmem_class, "class is now $lowmem_class");

    run_main_tests (undef, $mx);

    $mx->to_normal;

    is (blessed ($mx), $normal_class, "class is now $normal_class");

    run_main_tests (undef, $mx);

}


#  Test the effect of deletions
sub test_deletions {
    foreach my $class (@classes) {
        run_deletions($class);
    }
}

sub test_cluster_analysis {
    #  make sure we get the same cluster result using each type of matrix
    #my $data = get_cluster_mini_data();
    #my $bd   = get_basedata_object (data => $data, CELL_SIZES => [1,1]);
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);

    my $prng_seed = 123456;

    my $class1 = 'Biodiverse::Matrix';
    my $cl1 = $bd->add_cluster_output (
        name => $class1,
        CLUSTER_TIE_BREAKER => [ENDW_WE => 'max'],
        MATRIX_CLASS        => $class1,
    );
    $cl1->run_analysis (
        prng_seed => $prng_seed,
    );
    my $nwk1 = $cl1->to_newick;

    #  make sure we build a new matrix
    $bd->delete_all_outputs();

    my $class2 = 'Biodiverse::Matrix::LowMem';
    my $cl2 = $bd->add_cluster_output (
        name => $class2,
        CLUSTER_TIE_BREAKER => [ENDW_WE => 'max'],
        MATRIX_CLASS        => $class2,
    );
    $cl2->run_analysis (
        prng_seed => $prng_seed,
    );
    my $nwk2 = $cl2->to_newick;

    
    is (
        $nwk1,
        $nwk2,
        "Cluster analyses using matrices of classes $class1 and $class2 are the same"
    );
}


#  generate a matrix, export to sparse format, and then try to import it
sub test_import_sparse_format {
    my $mx = create_matrix_object();

    state $imp_sparse_fnum;
    $imp_sparse_fnum++;
    my $fname = "tmp_ḿx_sparse_${imp_sparse_fnum}.csv";

    $mx->export (
        format => 'Delimited text',
        file   => $fname,
        type   => 'sparse',
    );

    foreach my $class (@classes) {
        my $mx_from_sp = $class->new(
            name => $class,
        );
        $mx_from_sp->import_data_sparse (
            file => $fname,
            label_row_columns => [0],
            label_col_columns => [1],
            value_column      => 2,
        );
        run_main_tests ($class, $mx_from_sp);
    }
    
    unlink $fname;
}

sub run_deletions {
    my ($class, $mx) = @_;
    
    $class //= blessed $mx;

    note "\nUsing class $class\n\n";

    my $e;  #  for errors

    $mx //= create_matrix_object ($class);

    ok (!$e, 'imported data');
    
    my $element_pair_count = $mx->get_element_pair_count;
    
    my $success;
    
    $success = eval {
        $mx->delete_element (element1 => undef, element2 => undef);
    };
    ok (defined $@, "exception on attempted deletion of non-existant pair, $class");
    
    $success = eval {
        $mx->delete_element (element1 => 'barry', element2 => 'the wonder dog');
    };
    ok (!$success, "non-deletion of non-existant pair, $class");

    $success = eval {
        $mx->delete_element (element1 => 'b', element2 => 'c');
    };
    ok ($success, "successful deletion of element pair, $class");
    
    my $expected = $element_pair_count - 1;
    is ($mx->get_element_pair_count, $expected, 'matrix element pair count decreased by 1');
    
    my $min_val = $mx->get_min_value;
    
    #  now delete the lowest three values
    eval {
        $mx->delete_element (element1 => 'b', element2 => 'a');
        $mx->delete_element (element1 => 'e', element2 => 'a');
        $mx->delete_element (element1 => 'f', element2 => 'a');
    };

    $expected = $element_pair_count - 4;
    is ($mx->get_element_pair_count, $expected, 'matrix element pair count decreased by 3');
    my $new_min_val = $mx->get_min_value;
    isnt ($min_val, $new_min_val, 'min value changed');
    is ($new_min_val, 2, 'min value correct');
    
    #  now add a value that will be snapped
    my $new_val_with_zeroes = 1.0000000001;
    $mx->add_element (element1 => 'aa', element2 => 'bb', value => $new_val_with_zeroes);
    $new_min_val = $mx->get_min_value;
    is ($new_min_val, $new_val_with_zeroes, 'got expected new min value');
    $mx->delete_element (element1 => 'aa', element2 => 'bb');
    $new_min_val = $mx->get_min_value;
    is ($new_min_val, 2, 'got expected new min value');
}

sub run_main_tests {
    my ($class, $mx) = @_;
    
    $class //= blessed $mx;

    note "\nUsing class $class\n\n";

    my $e;  #  for errors

    $mx //= create_matrix_object ($class);

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

            my $exp_txt = $exp_val // 'undef';
            $val = $mx->get_value (element1 => $el1, element2 => $el2);
            is ($val, $exp_val, "got $exp_txt for pair $el1 => $el2");
            $val = $mx->get_defined_value (element1 => $el1, element2 => $el2);
            is ($val, $exp_val, "got $exp_txt for pair $el1 => $el2 (get_defined_value)");


            #  now the reverse
            $val = $mx->get_value (element2 => $el1, element1 => $el2);
            is ($val, $exp_val, "got $exp_txt for pair $el2 => $el1");
            $val = $mx->get_defined_value (element1 => $el2, element2 => $el1);
            is ($val, $exp_val, "got $exp_txt for pair $el2 => $el1 (get_defined_value)");
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
    
    my $check_val = 3;
    my %expected_pairs = (
        c => {
            b => 1,
        },
        e => {
            c => 1,
        },
    );

    foreach my $method (qw /get_element_pairs_with_value get_elements_with_value/) {
        my %pairs = $mx->get_element_pairs_with_value (value => $check_val);
        is_deeply (
            \%pairs,
            \%expected_pairs,
            "Got expected element pairs with value $check_val, $class"
        );
    }

    my @expected_element_array = qw /a b c d e f/;
    my @array = sort @{$mx->get_elements_as_array};
    is_deeply (\@array, \@expected_element_array, 'Got correct element array');
    
    $mx = $class->new (name => 'check get_defined_value');
    
    #  now run some extra checks on get_defined_value
    foreach my $el1 (keys %expected) {
        my $href = $expected{$el1};
        foreach my $el2 (keys %$href) {
            my $val = $href->{$el2};
            next if !defined $val;  #  avoid some warnings
            $mx->add_element (element1 => $el1, element2 => $el2, value => $val);
            my $alt_val = defined $val ? $val + 100 : undef;
            $mx->add_element (element1 => $el2, element2 => $el1, value => $alt_val);
        }
    }
    subtest 'get_defined_value works' => sub {
        foreach my $el1 (keys %expected) {
            my $href = $expected{$el1};
            foreach my $el2 (keys %$href) {
                next if !defined $href->{$el2};

                my $val = $mx->get_defined_value (
                    element1 => $el1,
                    element2 => $el2,
                );
                is ($val, $href->{$el2}, "$el1 => $el2");

                my $val_alt = $mx->get_defined_value (
                    element1 => $el2,
                    element2 => $el1,
                );
                my $exp_alt = defined $href->{$el2} ? $href->{$el2} + 100 : undef;
                is ($val_alt, $exp_alt, "$el2 => $el1");
            }
        }
    };

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
    
    my %expected_pairs = (
        'Genus:sp68' => {
            'Genus:sp11' => 1,
        },
    );

    foreach my $method (qw /get_element_pairs_with_value get_elements_with_value/) {
        my %pairs = $mx->$method (value => $expected_min);
        is_deeply (
            \%pairs,
            \%expected_pairs,
            "$method returned expected element pairs with value $expected_min, $class"
        );
    }
    
    $mx->delete_element (element1 => 'Genus:sp68', element2 => 'Genus:sp11');

    $expected_min = 0.00065;
    is ($mx->get_min_value, $expected_min, "Got correct min value, $class");
    
    #$mx->save_to_yaml (filename => $mx =~ /LowMem/ ? 'xx_LowMem.bmy' : 'xx_normal.bmy');
}



sub create_matrix_object {
    my $class = shift // 'Biodiverse::Matrix';

    my $e;

    my $tmp_mx_file = write_data_to_temp_file(get_matrix_data());

    my $mx = eval {
        $class->new (
            NAME            => "test matrix $class",
            ELEMENT_COLUMNS => [0],
        );
     };    
    $e = $EVAL_ERROR;
    diag $e if $e;

    ok (!$e, "created $class object without error");
    
    eval {
        $mx->import_data (
            file => $tmp_mx_file,
        );
    };
    $e = $EVAL_ERROR;
    diag $e if $e;

    return $mx;
}

sub _test_to_table {
    my ($class, $expected) = @_;

    my $mx = create_matrix_object($class);
    $expected //= get_exported_matrix_data();

    my @types = qw /normal sparse gdm/;
    my %tables;

    foreach my $type (@types) {
        my $table = $mx->to_table (type => $type);
        $tables{$type} = $table;
        
        is_deeply ($table, $expected->{$type}, "export to $type is as expected for " . blessed ($mx));
    }
    
    #  now check the exports are the same with and without file handles
    foreach my $type (@types) {
        my $pfx = get_temp_file_path('bd_XXXXXX');

        my $fname_use_fh = $pfx . '_use_fh.csv';
        my $fname_no_fh  = $pfx . '_no_fh.csv';

        $mx->export_delimited_text (type => $type, filename => $fname_use_fh);
        $mx->export_delimited_text (type => $type, filename => $fname_no_fh, _no_fh => 1);

        my $comp = File::Compare::compare ($fname_use_fh, $fname_no_fh);
        ok (!$comp, "Exported files with and without file handles in to_table are identical for $type, " . blessed ($mx));
    }
}


######################################

sub get_matrix_data {
    return get_data_section('MATRIX_DATA');
}

sub get_exported_matrix_data {
    my $data = get_data_section('EXPORTED_MATRIX_DATA');
    my $hash = eval $data;
    return $hash;
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


@@ EXPORTED_MATRIX_DATA
{
  gdm => [
    [
      'x1',
      'y1',
      'x2',
      'y2',
      'Value'
    ],
    [
      'a',
      undef,
      'b',
      undef,
      '1'
    ],
    [
      'a',
      undef,
      'c',
      undef,
      '2'
    ],
    [
      'a',
      undef,
      'd',
      undef,
      '4'
    ],
    [
      'a',
      undef,
      'e',
      undef,
      '1'
    ],
    [
      'a',
      undef,
      'f',
      undef,
      '1'
    ],
    [
      'b',
      undef,
      'a',
      undef,
      '1'
    ],
    [
      'b',
      undef,
      'c',
      undef,
      '3'
    ],
    [
      'b',
      undef,
      'd',
      undef,
      '5'
    ],
    [
      'b',
      undef,
      'e',
      undef,
      '2'
    ],
    [
      'c',
      undef,
      'a',
      undef,
      '2'
    ],
    [
      'c',
      undef,
      'b',
      undef,
      '3'
    ],
    [
      'c',
      undef,
      'd',
      undef,
      '6'
    ],
    [
      'c',
      undef,
      'e',
      undef,
      '3'
    ],
    [
      'd',
      undef,
      'a',
      undef,
      '4'
    ],
    [
      'd',
      undef,
      'b',
      undef,
      '5'
    ],
    [
      'd',
      undef,
      'c',
      undef,
      '6'
    ],
    [
      'd',
      undef,
      'e',
      undef,
      '4'
    ],
    [
      'e',
      undef,
      'a',
      undef,
      '1'
    ],
    [
      'e',
      undef,
      'b',
      undef,
      '2'
    ],
    [
      'e',
      undef,
      'c',
      undef,
      '3'
    ],
    [
      'e',
      undef,
      'd',
      undef,
      '4'
    ],
    [
      'f',
      undef,
      'a',
      undef,
      '1'
    ]
  ],
  normal => [
    [
      '',
      'a',
      'b',
      'c',
      'd',
      'e',
      'f'
    ],
    [
      'a',
      undef,
      '1',
      '2',
      '4',
      '1',
      '1'
    ],
    [
      'b',
      '1',
      undef,
      '3',
      '5',
      '2',
      undef
    ],
    [
      'c',
      '2',
      '3',
      undef,
      '6',
      '3',
      undef
    ],
    [
      'd',
      '4',
      '5',
      '6',
      undef,
      '4',
      undef
    ],
    [
      'e',
      '1',
      '2',
      '3',
      '4',
      undef,
      undef
    ],
    [
      'f',
      '1',
      undef,
      undef,
      undef,
      undef,
      undef
    ]
  ],
  sparse => [
    [
      'Row',
      'Column',
      'Value'
    ],
    [
      'a',
      'b',
      '1'
    ],
    [
      'a',
      'c',
      '2'
    ],
    [
      'a',
      'd',
      '4'
    ],
    [
      'a',
      'e',
      '1'
    ],
    [
      'a',
      'f',
      '1'
    ],
    [
      'b',
      'a',
      '1'
    ],
    [
      'b',
      'c',
      '3'
    ],
    [
      'b',
      'd',
      '5'
    ],
    [
      'b',
      'e',
      '2'
    ],
    [
      'c',
      'a',
      '2'
    ],
    [
      'c',
      'b',
      '3'
    ],
    [
      'c',
      'd',
      '6'
    ],
    [
      'c',
      'e',
      '3'
    ],
    [
      'd',
      'a',
      '4'
    ],
    [
      'd',
      'b',
      '5'
    ],
    [
      'd',
      'c',
      '6'
    ],
    [
      'd',
      'e',
      '4'
    ],
    [
      'e',
      'a',
      '1'
    ],
    [
      'e',
      'b',
      '2'
    ],
    [
      'e',
      'c',
      '3'
    ],
    [
      'e',
      'd',
      '4'
    ],
    [
      'f',
      'a',
      '1'
    ]
  ]
}

