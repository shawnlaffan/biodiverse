#  helper functions for testing
package Biodiverse::TestHelpers;

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;

$| = 1;

our $VERSION = '0.18_007';

use Data::Section::Simple qw(get_data_section);

BEGIN {
    $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;
}

use Biodiverse::BaseData;
use Biodiverse::Tree;
use Biodiverse::TreeNode;
use Biodiverse::ReadNexus;
use Biodiverse::ElementProperties;


use File::Temp;
use Scalar::Util qw /looks_like_number/;
use Test::More;

use Exporter::Easy (
    TAGS => [
        utils  => [
            qw(
                write_data_to_temp_file
                snap_to_precision
                verify_set_contents
                compare_hash_vals
                compare_arr_vals
                get_all_calculations
                transform_element
                is_or_isnt
            ),
        ],
        basedata => [
            qw(
                get_basedata_import_data_file
                get_basedata_test_data
                get_basedata_object
                get_basedata_object_from_site_data
                get_numeric_labels_basedata_object_from_site_data
                :utils
            ),
        ],
        element_properties => [
            qw(
                get_element_properties_test_data
                get_group_properties_site_data_object
                :utils
            ),
        ],
        tree => [
            qw(
                get_tree_object
                get_nexus_tree_data
                get_newick_tree_data
                get_tabular_tree_data
                get_tabular_tree_data_x2
                get_tree_object_from_sample_data
                :utils
            ),
        ],
        matrix => [
            qw(
                get_matrix_object
                get_matrix_object_from_sample_data
                get_cluster_mini_data
                :basedata
                :utils
            ),
        ],
        cluster => [
            qw (
                get_cluster_mini_data
                :basedata
                :utils
            ),
        ],
        runners => [
            qw(
                run_indices_test1
                :utils
            ),
        ],
        all => [
            qw(
                :basedata :element_properties :runners :tree :matrix
            ),
        ],
    ],
);

=item transform_element

Takes in a colon or comma (or any punctuation) separated pair of x and y values
(element) and scales them by the array ref of
[x_translate, y_translate, x_scale, y_scale] passed in as transform.

Returns separated pair of x and y.

element   =>
transfrom =>

=cut

sub transform_element {
    my %args = @_;

    my $element   = $args{element};
    my $transform = $args{transform};

    if (not ($element =~ m/^([-.0-9]+)([^-.0-9]+)([-.0-9]+)$/)) {
        croak "Invalid element '$element' given to transform_element.";
    }

    my ($x, $sep, $y)           = ($1, $2, $3);
    my ($x_t, $y_t, $x_s, $y_s) = @$transform;

    return join $sep, $x_s * ($x + $x_t),
                      $y_s * ($y + $y_t);
}

=item snap_to_precision

value     => decimal value
precision => desired amount of digits after decimal point

=cut

sub snap_to_precision {
    my %args = @_;
    my $value = $args{value};
    my $precision = $args{precision} // '%.11f';

    return defined $value && looks_like_number $value
        ? 0 + sprintf ($precision, $value)
        : $value;
}

=item verify_set_contents

set      => hash reference whose keys make up the set
included => array reference of keys that should be in the set
excluded => array reference of keys that should not be in the set

=cut

sub verify_set_contents {
    my %args = @_;

    my $set      = $args{set};
    my $includes = $args{includes};
    my $excludes = $args{excludes};

    for my $elt (@$includes) {
        ok exists $set->{$elt}, "$elt exists in set";
    }

    for my $elt (@$excludes) {
        ok !(exists $set->{$elt}), "$elt does not exist in set";
    }

    return;
}

#  use is or isnt
sub is_or_isnt {
    my ($got, $expected, $msg, $isnt) = @_;

    $isnt //= 'is';

    my $result = $isnt eq 'isnt'
      ? isnt ($got, $expected, $msg)
      : is   ($got, $expected, $msg);

    return $result;
}

sub compare_hash_vals {
    my %args = @_;

    my $hash_got   = $args{hash_got};
    my $hash_exp   = $args{hash_exp};
    my $precision  = $args{precision};
    my $not_strict = $args{no_strict_match};
    my $descr_suffix = $args{descr_suffix} // q{};
    my $sort_array_lists = $args{sort_array_lists};

    #  check union of the two hashes
    my %targets = (%$hash_exp, %$hash_got);

    if (!$not_strict) {
        is (scalar keys %$hash_got, scalar keys %$hash_exp, 'Hashes are same size');

        my %h1 = %$hash_got;
        delete @h1{keys %$hash_exp};
        is (scalar keys %h1, 0, 'No extra keys');

        my %h2 = %$hash_exp;
        delete @h2{keys %$hash_got};
        is (scalar keys %h2, 0, 'No missing keys');
    }
    elsif (scalar keys %$hash_got == scalar keys %$hash_exp && scalar keys %$hash_exp == 0) {
        #  but if both are zero then we need to run at least one test to get a pass
        is (scalar keys %$hash_got, scalar keys %$hash_exp, 'Hashes are same size');
    }

    BY_KEY:
    foreach my $key (sort keys %targets) {
        next BY_KEY if $not_strict && !exists $hash_got->{$key};

        if (ref $hash_exp->{$key} eq 'HASH') {
            subtest "Got expected hash for $key" => sub {
                compare_hash_vals (
                    hash_got => $hash_got->{$key},
                    hash_exp => $hash_exp->{$key},
                    no_strict_match => $args{no_strict_match},
                    descr_suffix    => "in $key",
                );
            };
            #say join ' ', sort keys %$hash_got;
            #say join ' ', sort keys %$hash_exp;
        }
        elsif (ref $hash_exp->{$key} eq 'ARRAY') {
            if ($sort_array_lists) {
                subtest "Got expected array for $key" => sub {
                    compare_arr_sorted (
                        arr_got => $hash_got->{$key},
                        arr_exp => $hash_exp->{$key},
                        #  add no_strict_match option??
                    );
                };
            }
            else {
                subtest "Got expected array for $key" => sub {
                    compare_arr (
                        arr_got => $hash_got->{$key},
                        arr_exp => $hash_exp->{$key},
                        #  add no_strict_match option??
                    );
                };
            }
        }
        else {
            my $val_got = snap_to_precision (
                value     => $hash_got->{$key},
                precision => $precision,
            );
            my $val_exp = snap_to_precision (
                value     => $hash_exp->{$key},
                precision => $precision,
            );
            is ($val_got, $val_exp, "Got expected value for $key, $descr_suffix");
        }
    }

    return;
}

=item compare_arr_vals

Checks that arr_got and arr_exp contain the same elements.
Order or duplication is not important.

Currently doesn't use snap_to_precision because it is intended for strings.

=cut

sub compare_arr_vals {
    my %args = @_;

    my $arr_got = $args{arr_got};
    my $arr_exp = $args{arr_exp};

    my (%got, %exp);

    foreach my $keyg (@$arr_got) {
        undef $got{$keyg};
    }
    foreach my $keye (@$arr_exp) {
        undef $exp{$keye};
    }

    is (scalar keys %got, scalar keys %exp, 'Arrays are same size');

    foreach my $key (keys %exp) {
        ok (exists $got{$key}, "Contains $key");
    }

    return;
}

=item compare_arr

Checks that arr_got and arr_exp contain the same elements in the same order.

=cut

sub compare_arr {
    my %args = @_;

    my $arr_got = $args{arr_got};
    my $arr_exp = $args{arr_exp};
    my $precision = $args{precision};

    is (scalar @$arr_got, scalar @$arr_exp, 'Arrays are same size');

    for (my $i = 0; $i != @$arr_exp; ++$i) {
        my $val_got = snap_to_precision (value => $arr_got->[$i], precision => $precision);
        my $val_exp = snap_to_precision (value => $arr_exp->[$i], precision => $precision);
        is ($val_got, $val_exp, "Got expected value for [$i]");
    }

    return;
}

=item compare_arr

Checks that arr_got and arr_exp contain the same elements

=cut

sub compare_arr_sorted {
    my %args = @_;

    my @arr_got = sort @{$args{arr_got}};
    my @arr_exp = sort @{$args{arr_exp}};
    my $precision = $args{precision};

    is (scalar @arr_got, scalar @arr_exp, 'Arrays are same size');

    for (my $i = 0; $i != @arr_exp; ++$i) {
        my $val_got = snap_to_precision (value => $arr_got[$i], precision => $precision);
        my $val_exp = snap_to_precision (value => $arr_exp[$i], precision => $precision);
        is ($val_got, $val_exp, "Got expected value for [$i]");
    }

    return;
}

sub get_basedata_import_data_file {
    my %args = @_;

    my $tmp_obj = File::Temp->new;
    my $ep_f = $tmp_obj->filename;
    print $tmp_obj $args{data} || get_basedata_test_data(@_);
    $tmp_obj -> close;

    return $tmp_obj;
}

sub get_basedata_test_data {
    my %args = (
        x_spacing => 1,
        y_spacing => 1,
        x_max     => 100,
        y_max     => 100,
        x_min     => 1,
        y_min     => 1,
        count     => 1,
        @_,
    );

    my $count = $args{count} || 0;
    my $use_rand_counts = $args{use_rand_counts};
    my $numeric_labels  = $args{numeric_labels};

    my $data;
    $data .= "label,x,y,count\n";
    foreach my $i ($args{x_min} .. $args{x_max}) {
        my $ii = $i * $args{x_spacing};
        foreach my $j ($args{y_min} .. $args{y_max}) {
            my $jj = $j * $args{y_spacing};
            if ($use_rand_counts) {
                $count = int (rand() * 1000);
            }
            my $label = $numeric_labels ? $i : join '_', $i, $j;
            $data .= "$label,$ii,$jj,$count\n";
        }
    }

    return $data;
}

sub get_basedata_object {
    my %args = @_;

    my $bd_f = get_basedata_import_data_file(@_);

    print "Temp file is $bd_f\n";

    my $bd = Biodiverse::BaseData->new(
        CELL_SIZES => $args{CELL_SIZES},
        NAME       => 'Test basedata',
    );
    $bd->import_data(
        input_files   => [$bd_f],
        group_columns => [1, 2],
        label_columns => [0],
        sample_count_columns => [3],
    );

    return $bd;
}

sub get_basedata_object_from_site_data {
    my %args = @_;

    my $file = write_data_to_temp_file(get_basedata_site_data());

    print "Temp file is $file\n";

    my $bd = Biodiverse::BaseData->new(
        CELL_SIZES => $args{CELL_SIZES},
        NAME       => 'Test basedata site data',
    );
    $bd->import_data(
        input_files   => [$file],
        group_columns => [3, 4],
        label_columns => [1, 2],
        skip_lines_with_undef_groups => 1,
    );

    return $bd;
}

sub get_numeric_labels_basedata_object_from_site_data {
    my %args = @_;

    my $file = write_data_to_temp_file(get_numeric_labels_basedata_site_data());

    print "Temp file is $file\n";

    my $bd = Biodiverse::BaseData->new(
        CELL_SIZES => $args{CELL_SIZES},
        NAME       => 'Test basedata site data, numeric labels',
    );
    $bd->import_data(
        input_files                  => [$file],
        group_columns                => [0, 1],
        label_columns                => [2],
        sample_count_columns         => [3],
        skip_lines_with_undef_groups => 1,
    );

    return $bd;
}

sub get_element_properties_test_data {

    my $data = <<'END_DATA'
rec_num,genus,species,new_genus,new_species,range,sample_count,num
1,Genus,sp1,Genus,sp2,,1
10,Genus,sp18,Genus,sp2,,1
2000,Genus,sp2,,,200,1000,2
END_DATA
  ;

}

sub get_cluster_mini_data {
    my $data = get_data_section('CLUSTER_MINI_DATA');
    $data =~ s/(?<!\w)\n+\z//m;  #  clear trailing newlines
    return $data;
}

sub get_tree_object {
    my $self = shift;

    my $tree = Biodiverse::Tree->new;
    my $newick = '(((a,b),c),d)';
    my $read_nex = Biodiverse::ReadNexus->new;
    my $nodes = $read_nex->parse_newick(
        string => $newick,
        tree   => $tree,
    );

    return $tree;
}

sub get_tree_object_from_sample_data {
    my $self = shift;

    my $data = get_nexus_tree_data();
    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $data);
    };
    my @tree_array = $trees->get_tree_array;
    my $tree = $tree_array[0];

    return $tree;
}


sub get_matrix_object_from_sample_data {
    my $class = shift || 'Biodiverse::Matrix';
    my %args  = @_;

    my $matrix = $class->new (
        NAME => 'Matrix for testing purposes',
        %args,
    );

    my $file = write_data_to_temp_file(get_matrix_site_data());

    print "Temp file is $file\n";

    my $result = eval {
        $matrix->import_data (file => $file);
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $matrix;
}

sub write_data_to_temp_file {
    my $data = shift;

    my $tmp_obj = File::Temp->new;
    my $fname = $tmp_obj->filename;
    print $tmp_obj $data;
    $tmp_obj->close;

    return $tmp_obj;
}

sub get_nexus_tree_data {
    return get_data_section('NEXUS_TREE');
}

sub get_newick_tree_data {
    return get_data_section('NEWICK_TREE');
}

sub get_tabular_tree_data {
    return get_data_section('TABULAR_TREE');
}

sub get_tabular_tree_data_x2 {
    return get_data_section('TABULAR_TREE_x2');
}

sub get_basedata_site_data {
    return get_data_section('BASEDATA_SITE_DATA');
}

sub get_numeric_labels_basedata_site_data {
    return get_data_section('NUMERIC_LABEL_SITE_DATA');
}

sub get_matrix_site_data {
    return get_data_section('MATRIX_SITE_DATA');
}

sub get_label_properties_site_data {
    return get_data_section('LABEL_PROPERTIES_DATA');
}

sub get_label_properties_site_data_extra {
    return get_data_section('LABEL_PROPERTIES_DATA_EXTRA');
}

sub get_label_properties_site_data_binomial {
    return get_data_section('LABEL_PROPERTIES_DATA_BINOMIAL');
}

sub get_group_properties_site_data {
    return get_data_section('GROUP_PROPERTIES_DATA');
}

sub get_group_properties_site_data_object {
    my $data  = get_group_properties_site_data;
    my $props = element_properties_from_string($data);

    return $props;
}

sub element_properties_from_string {
    my ($data, ) = @_;
    my $file = write_data_to_temp_file($data);
    my $props = Biodiverse::ElementProperties->new;

    # Get property column names and positions. First is 3.
    # Results in something like:
    # (LBPROP1 => 3, LBPROP2 => 4, ...)
    my $i = 3;
    $data =~ m/^(.*)$/m;
    my @prop_names = split ',', $1;
    my %prop_cols = map { $_ => $i++; } @prop_names[3..$#prop_names];

    my $success = eval { $props->import_data (
        input_element_cols    => [1..2],
        file                  => $file,
        %prop_cols, # Tell import_data which columns contain which properties
    ) };
    my $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, 'Loaded element properties without eval error');
    ok ($success eq 1, 'Element properties successfully loaded');

    return $props;
}

sub run_indices_test1 {
    my %args = @_;
    my $calcs_to_test          = $args{calcs_to_test};
    my $calc_topic_to_test     = $args{calc_topic_to_test};
    my $cell_sizes             = $args{cell_sizes} || [100000, 100000];
    my $use_numeric_labels     = $args{use_numeric_labels};
    my $use_element_properties = $args{use_element_properties}; # 'group' or 'label'
    my $use_label_properties_extra = $args{use_label_properties_extra};  #  boolean
    my $use_label_properties_binomial = $args{use_label_properties_binomial};  # boolean
    my $callbacks              = $args{callbacks};
    my $expected_results_overlay = $args{expected_results_overlay};
    my $sort_array_lists       = $args{sort_array_lists};
    delete $args{callbacks};

    # Used for acquiring sample results
    my $generate_result_sets = $args{generate_result_sets};

    my $element_list1 = $args{element_list1} || ['3350000:850000'];
    my $element_list2
      = $args{element_list2}
        || [qw/
            3250000:850000
            3350000:750000
            3350000:950000
            3450000:850000
        /];

    my $dss = Data::Section::Simple->new(caller);

    my ($e, $is_error, %results);

    my %bd_args = (%args, CELL_SIZES => $cell_sizes);

    my $bd = $use_numeric_labels
      ? get_numeric_labels_basedata_object_from_site_data (
            %bd_args,
        )
      : get_basedata_object_from_site_data (
            %bd_args,
        );

    my $tree = get_tree_object_from_sample_data();

    my $matrix = get_matrix_object_from_sample_data();

    if ($use_element_properties) {
        my $data;

        if ($use_element_properties =~ /label/) {
            $data = get_label_properties_site_data();
        }
        elsif ($use_element_properties eq 'group') {
            $data = get_group_properties_site_data();
        }
        else {
            croak 'Invalid value for use_element_properties';
        }

        my $props = element_properties_from_string($data);

        eval { $bd->assign_element_properties (
            type              => $use_element_properties . q{s}, # plural
            properties_object => $props,
        ) };
        $e = $EVAL_ERROR;
        note $e if $e;
        ok (!$e, 'Element properties assigned without eval error');
    }

    if ($use_label_properties_extra) {
        my $data = get_label_properties_site_data_extra();

        my $props = element_properties_from_string($data);

        eval { $bd->assign_element_properties (
            type              => 'labels',
            properties_object => $props,
        ) };
        $e = $EVAL_ERROR;
        note $e if $e;
        ok (!$e, 'Extra label properties assigned without eval error');
    }
    
    if ($use_label_properties_binomial) {
        my $data = get_label_properties_site_data_binomial();

        my $props = element_properties_from_string($data);

        eval { $bd->assign_element_properties (
            type              => 'labels',
            properties_object => $props,
        ) };
        $e = $EVAL_ERROR;
        note $e if $e;
        ok (!$e, 'Binomial label properties assigned without eval error');
    }
    
    
    foreach my $callback (@$callbacks) {
        eval {
            &$callback(
                %args,
                element_list1 => $element_list1,
                element_list2 => $element_list2,
                basedata_ref  => $bd,
                tree_ref      => $tree,
            );
        };
        croak $EVAL_ERROR if $EVAL_ERROR;
    }

    my $indices = Biodiverse::Indices->new(BASEDATA_REF => $bd);

    if ($calc_topic_to_test) {
        my $expected_calcs_to_test = $indices->get_calculations->{$calc_topic_to_test};

        subtest 'Right calculations are being tested' => sub {
            compare_arr_vals (
                arr_got => $calcs_to_test,
                arr_exp => $expected_calcs_to_test
            )
        };
    }

    my %elements = (
        element_list1 => $element_list1,
        element_list2 => $element_list2,
    );

    my $calc_args = {
        tree_ref   => $tree,
        matrix_ref => $matrix,
        prng_seed  => $args{prng_seed},  #  FIXME: NEED TO PASS ANY NECESSARY ARGS
        nri_nti_iterations => $args{nri_nti_iterations},
        mpd_mntd_use_binomial => $args{mpd_mntd_use_binomial},
    };

    foreach my $nbr_list_count (2, 1) {
        if ($nbr_list_count == 1) {
            delete $elements{element_list2};
        }

        my %indices_args = (
            calcs_to_test  => $calcs_to_test,
            calc_args      => $calc_args,
            elements       => \%elements,
            nbr_list_count => $nbr_list_count,
            basedata_ref   => $bd,
        );

        my %results;
        #  sometimes we want to check for the effects of caching
        foreach my $repetition ($args{repetitions} // 1) {
            %results = run_indices_test1_inner (%indices_args);
        }

        # Used for acquiring sample results
        if ($generate_result_sets) {
            use Data::Dumper;
            local $Data::Dumper::Purity   = 1;
            local $Data::Dumper::Terse    = 1;
            local $Data::Dumper::Sortkeys = 1;
            say '#' x 20;
            say Dumper(\%results);
            say '#' x 20;
        }

        #  now we need to check the results
        my $subtest_name = "Result set matches for neighbour count $nbr_list_count";
        my $expected = eval $dss->get_data_section(
            "RESULTS_${nbr_list_count}_NBR_LISTS"
        );
        diag "Problem with data section: $EVAL_ERROR" if $EVAL_ERROR;
        if ($expected_results_overlay && $expected_results_overlay->{$nbr_list_count}) {
            my $hash = $expected_results_overlay->{$nbr_list_count};
            @$expected{keys %$hash} = values %$hash;
        }

        subtest $subtest_name => sub {
            compare_hash_vals (
                no_strict_match => $args{no_strict_match},
                hash_got => \%results,
                hash_exp => \%{$expected},
                descr_suffix => "$nbr_list_count nbr sets",
                sort_array_lists => $sort_array_lists,
            );
        };
    }
}

sub run_indices_test1_inner {
    my %args = @_;
    
    my $calcs_to_test  = $args{calcs_to_test};
    my $calc_args      = $args{calc_args};
    my %elements       = %{$args{elements}};
    my $nbr_list_count = $args{nbr_list_count};
    my $bd             = $args{basedata_ref};

    my $calc_args_for_validity_check = {
        %$calc_args,
        %elements,
    };
    
    my $indices = Biodiverse::Indices->new(BASEDATA_REF => $bd);
    my $e;

    my $valid_calcs = eval {
        $indices->get_valid_calculations(
            calculations   => $calcs_to_test,
            nbr_list_count => $nbr_list_count,
            calc_args      => $calc_args_for_validity_check,
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "Obtained valid calcs without eval error");

    eval {
        $indices->run_precalc_globals(%$calc_args);
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "Ran global precalcs without eval error");

    my %results = eval { $indices->run_calculations(%$calc_args) };
    $e = $EVAL_ERROR;
    #note $e if $e;

    # sometimes none are left to run
    if ($indices->get_valid_calculation_count) {
        ok ($e, "Ran calculations without elements and got eval error");
    }

    %results = eval {
        $indices->run_calculations(%$calc_args, %elements);
    };

    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "Ran calculations without eval error");

    eval {
        $indices->run_postcalc_globals(%$calc_args);
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "Ran global postcalcs without eval error");
    
    return wantarray ? %results : \%results;
}

1;

__DATA__

@@ CLUSTER_MINI_DATA
label,x,y,samples
a,1,1,1
b,1,1,1
c,1,1,1
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

@@ NEWICK_TREE
(((((((((((44:0.6,47:0.6):0.077662337662338,(18:0.578947368421053,58:0.578947368421053):0.098714969241285):0.106700478344225,31:0.784362816006563):0.05703610742759,(6:0.5,35:0.5):0.341398923434153):0.03299436960061,(((((1:0.434782608695652,52:0.434782608695652):0.051317777404734,57:0.486100386100386):0.11249075347436,22:0.598591139574746):0.0272381982058111,46:0.625829337780557):0.172696292660468,(7:0.454545454545455,9:0.454545454545455):0.34398017589557):0.075867662593738):0.057495084175743,((4:0,25:0):0.666666666666667,16:0.666666666666667):0.265221710543839):0.026396763298318,((0:0.789473684210526,12:0.789473684210526):0.111319966583125,(15:0.6,30:0.6):0.300793650793651):0.0574914897151729):0.020427284632173,48:0.978712425140997):0.00121523842637206,(24:0.25,55:0.25):0.729927663567369):0.00291112550535999,((((38:0.461538461538462,13:0.461538461538462):0.160310277957336,(50:0.166666666666667,59:0.166666666666667):0.455182072829131):0.075519681556834,32:0.697368421052632):0.258187134502923,2:0.955555555555555):0.027283233517174):0.00993044169650192,42:0.992769230769231):0;

@@ NEXUS_TREE
#NEXUS
[ID: blah blah]
begin trees;
	[this is a comment with a semicolon ; ]
	Translate
		0 'Genus:sp9',
		1 'Genus:sp23',
		2 'Genus:sp13',
		3 '18___',
		4 'Genus:sp28',
		5 '15___',
		6 'Genus:sp26',
		7 'Genus:sp21',
		8 '22___',
		9 'Genus:sp18',
		10 '17___',
		11 '26___',
		12 'Genus:sp8',
		13 'Genus:sp3',
		14 '1___',
		15 'Genus:sp14',
		16 'Genus:sp27',
		17 '13___',
		18 'Genus:sp15',
		19 '5___',
		20 '16___',
		21 '6___',
		22 'Genus:sp29',
		23 '23___',
		24 'Genus:sp24',
		25 'Genus:sp31',
		26 '8___',
		27 '0___',
		28 '29___',
		29 '25___',
		30 'Genus:sp16',
		31 'Genus:sp10',
		32 'Genus:sp4',
		33 '21___',
		34 '10___',
		35 'Genus:sp20',
		36 '27___',
		37 '20___',
		38 'Genus:sp2',
		39 '28___',
		40 '24___',
		41 '11___',
		42 'Genus:sp22',
		43 '4___',
		44 'Genus:sp19',
		45 '7___',
		46 'Genus:sp12',
		47 'Genus:sp5',
		48 'Genus:sp17',
		49 '3___',
		50 'Genus:sp6',
		51 '9___',
		52 'Genus:sp30',
		53 '19___',
		54 '2___',
		55 'Genus:sp25',
		56 '12___',
		57 'Genus:sp11',
		58 'Genus:sp1',
		59 'Genus:sp7',
		60 '14___'
		;
	Tree 'Example_tree1' = (((((((((((44:0.6,47:0.6):0.077662337662338,(18:0.578947368421053,58:0.578947368421053):0.098714969241285):0.106700478344225,31:0.784362816006563):0.05703610742759,(6:0.5,35:0.5):0.341398923434153):0.03299436960061,(((((1:0.434782608695652,52:0.434782608695652):0.051317777404734,57:0.486100386100386):0.11249075347436,22:0.598591139574746):0.0272381982058111,46:0.625829337780557):0.172696292660468,(7:0.454545454545455,9:0.454545454545455):0.34398017589557):0.075867662593738):0.057495084175743,((4:0,25:0):0.666666666666667,16:0.666666666666667):0.265221710543839):0.026396763298318,((0:0.789473684210526,12:0.789473684210526):0.111319966583125,(15:0.6,30:0.6):0.300793650793651):0.0574914897151729):0.020427284632173,48:0.978712425140997):0.00121523842637206,(24:0.25,55:0.25):0.729927663567369):0.00291112550535999,((((38:0.461538461538462,13:0.461538461538462):0.160310277957336,(50:0.166666666666667,59:0.166666666666667):0.455182072829131):0.075519681556834,32:0.697368421052632):0.258187134502923,2:0.955555555555555):0.027283233517174):0.00993044169650192,42:0.992769230769231):0;
        Tree 'Example_tree2' = (((((((((((44:0.6,47:0.6):0.077662337662338,(18:0.578947368421053,58:0.578947368421053):0.098714969241285):0.106700478344225,31:0.784362816006563):0.05703610742759,(6:0.5,35:0.5):0.341398923434153):0.03299436960061,(((((1:0.434782608695652,52:0.434782608695652):0.051317777404734,57:0.486100386100386):0.11249075347436,22:0.598591139574746):0.0272381982058111,46:0.625829337780557):0.172696292660468,(7:0.454545454545455,9:0.454545454545455):0.34398017589557):0.075867662593738):0.057495084175743,((4:0,25:0):0.666666666666667,16:0.666666666666667):0.265221710543839):0.026396763298318,((0:0.789473684210526,12:0.789473684210526):0.111319966583125,(15:0.6,30:0.6):0.300793650793651):0.0574914897151729):0.020427284632173,48:0.978712425140997):0.00121523842637206,(24:0.25,55:0.25):0.729927663567369):0.00291112550535999,((((38:0.461538461538462,13:0.461538461538462):0.160310277957336,(50:0.166666666666667,59:0.166666666666667):0.455182072829131):0.075519681556834,32:0.697368421052632):0.258187134502923,2:0.955555555555555):0.027283233517174):0.00993044169650192,42:0.992769230769231):0;
end;


@@ TABULAR_TREE
Element	Axis_0	LENGTHTOPARENT	NAME	NODE_NUMBER	PARENTNODE	TREENAME
1	1	0		1	0	'Example_tree'
10	10	0.106700478344225		10	9	'Example_tree'
11	11	0.077662337662338		11	10	'Example_tree'
12	12	0.6	Genus:sp19	12	11	'Example_tree'
13	13	0.6	Genus:sp5	13	11	'Example_tree'
14	14	0.098714969241285		14	10	'Example_tree'
15	15	0.578947368421053	Genus:sp15	15	14	'Example_tree'
16	16	0.578947368421053	Genus:sp1	16	14	'Example_tree'
17	17	0.784362816006563	Genus:sp10	17	9	'Example_tree'
18	18	0.341398923434153		18	8	'Example_tree'
19	19	0.5	Genus:sp26	19	18	'Example_tree'
2	2	0.00993044169650192		2	1	'Example_tree'
20	20	0.5	Genus:sp20	20	18	'Example_tree'
21	21	0.075867662593738		21	7	'Example_tree'
22	22	0.172696292660468		22	21	'Example_tree'
23	23	0.0272381982058111		23	22	'Example_tree'
24	24	0.11249075347436		24	23	'Example_tree'
25	25	0.051317777404734		25	24	'Example_tree'
26	26	0.434782608695652	Genus:sp23	26	25	'Example_tree'
27	27	0.434782608695652	Genus:sp30	27	25	'Example_tree'
28	28	0.486100386100386	Genus:sp11	28	24	'Example_tree'
29	29	0.598591139574746	Genus:sp29	29	23	'Example_tree'
3	3	0.00291112550535999		3	2	'Example_tree'
30	30	0.625829337780557	Genus:sp12	30	22	'Example_tree'
31	31	0.34398017589557		31	21	'Example_tree'
32	32	0.454545454545455	Genus:sp21	32	31	'Example_tree'
33	33	0.454545454545455	Genus:sp18	33	31	'Example_tree'
34	34	0.265221710543839		34	6	'Example_tree'
35	35	0.666666666666667		35	34	'Example_tree'
36	36	0	Genus:sp28	36	35	'Example_tree'
37	37	0	Genus:sp31	37	35	'Example_tree'
38	38	0.666666666666667	Genus:sp27	38	34	'Example_tree'
39	39	0.0574914897151729		39	5	'Example_tree'
4	4	0.00121523842637206		4	3	'Example_tree'
40	40	0.111319966583125		40	39	'Example_tree'
41	41	0.789473684210526	Genus:sp9	41	40	'Example_tree'
42	42	0.789473684210526	Genus:sp8	42	40	'Example_tree'
43	43	0.300793650793651		43	39	'Example_tree'
44	44	0.6	Genus:sp14	44	43	'Example_tree'
45	45	0.6	Genus:sp16	45	43	'Example_tree'
46	46	0.978712425140997	Genus:sp17	46	4	'Example_tree'
47	47	0.729927663567369		47	3	'Example_tree'
48	48	0.25	Genus:sp24	48	47	'Example_tree'
49	49	0.25	Genus:sp25	49	47	'Example_tree'
5	5	0.020427284632173		5	4	'Example_tree'
50	50	0.027283233517174		50	2	'Example_tree'
51	51	0.258187134502923		51	50	'Example_tree'
52	52	0.075519681556834		52	51	'Example_tree'
53	53	0.160310277957336		53	52	'Example_tree'
54	54	0.461538461538462	Genus:sp2	54	53	'Example_tree'
55	55	0.461538461538462	Genus:sp3	55	53	'Example_tree'
56	56	0.455182072829131		56	52	'Example_tree'
57	57	0.166666666666667	Genus:sp6	57	56	'Example_tree'
58	58	0.166666666666667	Genus:sp7	58	56	'Example_tree'
59	59	0.697368421052632	Genus:sp4	59	51	'Example_tree'
6	6	0.026396763298318		6	5	'Example_tree'
60	60	0.955555555555555	Genus:sp13	60	50	'Example_tree'
61	61	0.992769230769231	Genus:sp22	61	1	'Example_tree'
7	7	0.057495084175743		7	6	'Example_tree'
8	8	0.03299436960061		8	7	'Example_tree'
9	9	0.05703610742759		9	8	'Example_tree'

@@ TABULAR_TREE_x2
Element	Axis_0	LENGTHTOPARENT	NAME	NODE_NUMBER	PARENTNODE	TREENAME
1	1	0		1	0	'Example_tree'
10	10	0.106700478344225		10	9	'Example_tree'
11	11	0.077662337662338		11	10	'Example_tree'
12	12	0.6	Genus:sp19	12	11	'Example_tree'
13	13	0.6	Genus:sp5	13	11	'Example_tree'
14	14	0.098714969241285		14	10	'Example_tree'
15	15	0.578947368421053	Genus:sp15	15	14	'Example_tree'
16	16	0.578947368421053	Genus:sp1	16	14	'Example_tree'
17	17	0.784362816006563	Genus:sp10	17	9	'Example_tree'
18	18	0.341398923434153		18	8	'Example_tree'
19	19	0.5	Genus:sp26	19	18	'Example_tree'
2	2	0.00993044169650192		2	1	'Example_tree'
20	20	0.5	Genus:sp20	20	18	'Example_tree'
21	21	0.075867662593738		21	7	'Example_tree'
22	22	0.172696292660468		22	21	'Example_tree'
23	23	0.0272381982058111		23	22	'Example_tree'
24	24	0.11249075347436		24	23	'Example_tree'
25	25	0.051317777404734		25	24	'Example_tree'
26	26	0.434782608695652	Genus:sp23	26	25	'Example_tree'
27	27	0.434782608695652	Genus:sp30	27	25	'Example_tree'
28	28	0.486100386100386	Genus:sp11	28	24	'Example_tree'
29	29	0.598591139574746	Genus:sp29	29	23	'Example_tree'
3	3	0.00291112550535999		3	2	'Example_tree'
30	30	0.625829337780557	Genus:sp12	30	22	'Example_tree'
31	31	0.34398017589557		31	21	'Example_tree'
32	32	0.454545454545455	Genus:sp21	32	31	'Example_tree'
33	33	0.454545454545455	Genus:sp18	33	31	'Example_tree'
34	34	0.265221710543839		34	6	'Example_tree'
35	35	0.666666666666667		35	34	'Example_tree'
36	36	0	Genus:sp28	36	35	'Example_tree'
37	37	0	Genus:sp31	37	35	'Example_tree'
38	38	0.666666666666667	Genus:sp27	38	34	'Example_tree'
39	39	0.0574914897151729		39	5	'Example_tree'
4	4	0.00121523842637206		4	3	'Example_tree'
40	40	0.111319966583125		40	39	'Example_tree'
41	41	0.789473684210526	Genus:sp9	41	40	'Example_tree'
42	42	0.789473684210526	Genus:sp8	42	40	'Example_tree'
43	43	0.300793650793651		43	39	'Example_tree'
44	44	0.6	Genus:sp14	44	43	'Example_tree'
45	45	0.6	Genus:sp16	45	43	'Example_tree'
46	46	0.978712425140997	Genus:sp17	46	4	'Example_tree'
47	47	0.729927663567369		47	3	'Example_tree'
48	48	0.25	Genus:sp24	48	47	'Example_tree'
49	49	0.25	Genus:sp25	49	47	'Example_tree'
5	5	0.020427284632173		5	4	'Example_tree'
50	50	0.027283233517174		50	2	'Example_tree'
51	51	0.258187134502923		51	50	'Example_tree'
52	52	0.075519681556834		52	51	'Example_tree'
53	53	0.160310277957336		53	52	'Example_tree'
54	54	0.461538461538462	Genus:sp2	54	53	'Example_tree'
55	55	0.461538461538462	Genus:sp3	55	53	'Example_tree'
56	56	0.455182072829131		56	52	'Example_tree'
57	57	0.166666666666667	Genus:sp6	57	56	'Example_tree'
58	58	0.166666666666667	Genus:sp7	58	56	'Example_tree'
59	59	0.697368421052632	Genus:sp4	59	51	'Example_tree'
6	6	0.026396763298318		6	5	'Example_tree'
60	60	0.955555555555555	Genus:sp13	60	50	'Example_tree'
61	61	0.992769230769231	Genus:sp22	61	1	'Example_tree'
7	7	0.057495084175743		7	6	'Example_tree'
8	8	0.03299436960061		8	7	'Example_tree'
9	9	0.05703610742759		9	8	'Example_tree'
1	1	0		1	0	'Example_tree2'
10	10	0.106700478344225		10	9	'Example_tree2'
11	11	0.077662337662338		11	10	'Example_tree2'
12	12	0.6	Genus:sp19	12	11	'Example_tree2'
13	13	0.6	Genus:sp5	13	11	'Example_tree2'
14	14	0.098714969241285		14	10	'Example_tree2'
15	15	0.578947368421053	Genus:sp15	15	14	'Example_tree2'
16	16	0.578947368421053	Genus:sp1	16	14	'Example_tree2'
17	17	0.784362816006563	Genus:sp10	17	9	'Example_tree2'
18	18	0.341398923434153		18	8	'Example_tree2'
19	19	0.5	Genus:sp26	19	18	'Example_tree2'
2	2	0.00993044169650192		2	1	'Example_tree2'
20	20	0.5	Genus:sp20	20	18	'Example_tree2'
21	21	0.075867662593738		21	7	'Example_tree2'
22	22	0.172696292660468		22	21	'Example_tree2'
23	23	0.0272381982058111		23	22	'Example_tree2'
24	24	0.11249075347436		24	23	'Example_tree2'
25	25	0.051317777404734		25	24	'Example_tree2'
26	26	0.434782608695652	Genus:sp23	26	25	'Example_tree2'
27	27	0.434782608695652	Genus:sp30	27	25	'Example_tree2'
28	28	0.486100386100386	Genus:sp11	28	24	'Example_tree2'
29	29	0.598591139574746	Genus:sp29	29	23	'Example_tree2'
3	3	0.00291112550535999		3	2	'Example_tree2'
30	30	0.625829337780557	Genus:sp12	30	22	'Example_tree2'
31	31	0.34398017589557		31	21	'Example_tree2'
32	32	0.454545454545455	Genus:sp21	32	31	'Example_tree2'
33	33	0.454545454545455	Genus:sp18	33	31	'Example_tree2'
34	34	0.265221710543839		34	6	'Example_tree2'
35	35	0.666666666666667		35	34	'Example_tree2'
36	36	0	Genus:sp28	36	35	'Example_tree2'
37	37	0	Genus:sp31	37	35	'Example_tree2'
38	38	0.666666666666667	Genus:sp27	38	34	'Example_tree2'
39	39	0.0574914897151729		39	5	'Example_tree2'
4	4	0.00121523842637206		4	3	'Example_tree2'
40	40	0.111319966583125		40	39	'Example_tree2'
41	41	0.789473684210526	Genus:sp9	41	40	'Example_tree2'
42	42	0.789473684210526	Genus:sp8	42	40	'Example_tree2'
43	43	0.300793650793651		43	39	'Example_tree2'
44	44	0.6	Genus:sp14	44	43	'Example_tree2'
45	45	0.6	Genus:sp16	45	43	'Example_tree2'
46	46	0.978712425140997	Genus:sp17	46	4	'Example_tree2'
47	47	0.729927663567369		47	3	'Example_tree2'
48	48	0.25	Genus:sp24	48	47	'Example_tree2'
49	49	0.25	Genus:sp25	49	47	'Example_tree2'
5	5	0.020427284632173		5	4	'Example_tree2'
50	50	0.027283233517174		50	2	'Example_tree2'
51	51	0.258187134502923		51	50	'Example_tree2'
52	52	0.075519681556834		52	51	'Example_tree2'
53	53	0.160310277957336		53	52	'Example_tree2'
54	54	0.461538461538462	Genus:sp2	54	53	'Example_tree2'
55	55	0.461538461538462	Genus:sp3	55	53	'Example_tree2'
56	56	0.455182072829131		56	52	'Example_tree2'
57	57	0.166666666666667	Genus:sp6	57	56	'Example_tree2'
58	58	0.166666666666667	Genus:sp7	58	56	'Example_tree2'
59	59	0.697368421052632	Genus:sp4	59	51	'Example_tree2'
6	6	0.026396763298318		6	5	'Example_tree2'
60	60	0.955555555555555	Genus:sp13	60	50	'Example_tree2'
61	61	0.992769230769231	Genus:sp22	61	1	'Example_tree2'
7	7	0.057495084175743		7	6	'Example_tree2'
8	8	0.03299436960061		8	7	'Example_tree2'
9	9	0.05703610742759		9	8	'Example_tree2'


@@ BASEDATA_SITE_DATA
num,genus,species,x,y
1,Genus,sp1,3229628.144,3078197.708
2,Genus,sp1,3216986.364,2951192.309
3,Genus,sp1,3216038.331,2960749.322
4,Genus,sp2,3217265.071,2960874.379
5,Genus,sp2,3205745.731,2963059.801
6,Genus,sp2,3214891.41,2928147.063
7,Genus,sp2,3219317.279,2971029.526
8,Genus,sp2,3222862.015,2964370.214
10,Genus,sp2,3212458.146,2941450.158
11,Genus,sp2,3190927.597,2934733.879
13,Genus,sp1,3219062.392,2957000.395
14,Genus,sp2,3214927.972,2957598.276
17,Genus,sp2,3224316.252,2949812.85
18,Genus,sp2,3213747.029,2958541.561
19,Genus,sp3,3217002.785,2851990.43
20,Genus,sp3,3218154.45,2860837.224
21,Genus,sp3,3269737.444,2861722.441
22,Genus,sp3,3271211.081,2856803.277
27,Genus,sp1,3674506.462,2346302.09
32,Genus,sp4,3508293.759,2205062.899
33,Genus,sp2,3523328.817,2283708.702
34,Genus,sp2,3523458.292,2208871.474
35,Genus,sp2,3524561.355,2229936.613
36,Genus,sp2,3525733.138,2285682.192
38,Genus,sp2,3518610.278,2283207.832
39,Genus,sp3,3523628.836,2281900.096
40,Genus,sp2,3527155.402,2285608.841
42,Genus,sp2,3523328.772,2201927.977
43,Genus,sp3,3516010.914,2201544.528
45,Genus,sp4,3518978.909,2200562.809
47,Genus,sp3,3526275.942,2202700.182
51,Genus,sp2,3516577.816,2207202.714
52,Genus,sp2,3524430.085,2286931.125
53,Genus,sp2,3521141.742,2286008.379
54,Genus,sp4,3523918.218,2200378.103
55,Genus,sp3,3519116.975,2198589.788
56,Genus,sp2,3518619.124,2205617.171
61,Genus,sp3,3448948.667,2096729.067
62,Genus,sp3,3435630.374,2167379.695
63,Genus,sp2,3701073.878,2067642.445
64,Genus,sp5,3738299.071,2134690.221
67,Genus,sp3,3399302.77,2091881.723
68,Genus,sp1,3703011.061,2112487.047
69,Genus,sp2,3348498.96,2109001.603
75,Genus,sp2,3282984.599,2146228.769
78,Genus,sp3,3307852.031,2112888.668
80,Genus,sp2,3541744.796,2080101.838
81,Genus,sp2,3693807.508,2062672.34
83,Genus,sp2,3502990.109,2076107.639
85,Genus,sp2,3592219.937,2048978.321
91,Genus,sp2,3692848.359,1946458.744
92,Genus,sp6,3724498.523,1997992.472
93,Genus,sp6,3728074.566,2007559.748
94,Genus,sp7,3722882.903,1996018.249
95,Genus,sp7,3700955.253,2039871.525
96,Genus,sp2,3404947.383,2088150.415
98,Genus,sp6,3634106.161,2020075.733
99,Genus,sp2,3607492,2010520.485
103,Genus,sp8,3896355.268,1985669.819
109,Genus,sp9,3860105.804,1932518.081
111,Genus,sp10,3727333.9,2012165.212
112,Genus,sp3,3522931.453,2048712.927
113,Genus,sp3,3703018.719,2005968.15
117,Genus,sp2,3730325.639,1995214.703
118,Genus,sp3,3602484.141,2018688.018
119,Genus,sp3,3621173.38,2008643.105
126,Genus,sp3,3595520.106,2039944.653
128,Genus,sp2,3608883.648,2014341.061
129,Genus,sp8,3687787.377,2002608.802
132,Genus,sp6,3684722.515,2005598.513
134,Genus,sp1,3783987.181,1964001.296
135,Genus,sp10,3504899.949,2052753.225
137,Genus,sp7,3679649.801,2024276.781
139,Genus,sp4,3506585.809,2038566.636
141,Genus,sp6,3735190.164,1979521.991
147,Genus,sp8,3881987.429,1997072.76
151,Genus,sp3,3608325.103,1983411.313
152,Genus,sp10,3502546.091,2048610.834
153,Genus,sp6,3734127.591,1961745.897
154,Genus,sp2,3687056.725,1957609.81
155,Genus,sp4,3708959.604,1939052.958
158,Genus,sp3,3649693.216,1904350.65
159,Genus,sp6,3686458.332,1886009.175
160,Genus,sp9,3855924.843,1812563.947
161,Genus,sp4,3585209.976,1941450.077
162,Genus,sp6,3684425.566,1937229.155
163,Genus,sp1,3851024.065,1814172.873
164,Genus,sp1,3854208.166,1820894.056
167,Genus,sp6,3583348.527,1947479.248
168,Genus,sp10,3589035.907,1953826.337
170,Genus,sp1,3870450.646,1855052.312
171,Genus,sp6,3713913.092,1934887.444
173,Genus,sp1,3857106.291,1819103.41
174,Genus,sp7,3693271.595,1938101.8
176,Genus,sp11,3858681.528,1803900.475
179,Genus,sp9,3865211.354,1806867.807
180,Genus,sp9,3877824.687,1818138.625
181,Genus,sp9,3873105.347,1836307.459
182,Genus,sp9,3861272.273,1821775.978
183,Genus,sp8,3876144.065,1911673.589
186,Genus,sp7,3681818.771,1882973.233
188,Genus,sp9,3877204.668,1827422.235
190,Genus,sp9,3858596.938,1807176.552
191,Genus,sp1,3856437.94,1877957.527
192,Genus,sp1,3872455.41,1885391.726
197,Genus,sp8,3877846.222,1885627.432
198,Genus,sp11,3859531.469,1808924.757
199,Genus,sp7,3681556.034,1884526.61
200,Genus,sp9,3860465.444,1819753.845
203,Genus,sp6,3682214.728,1887637.004
204,Genus,sp7,3685112.092,1882006.541
205,Genus,sp9,3856329.78,1821713.867
206,Genus,sp9,3856105.449,1814465.866
207,Genus,sp9,3769943.781,1865393.041
208,Genus,sp9,3853273.939,1812601.016
209,Genus,sp9,3861903.648,1817035.853
210,Genus,sp9,3860173.156,1809645.645
211,Genus,sp8,3868714.79,1837927.902
212,Genus,sp8,3860620.621,1823189.973
213,Genus,sp8,3880411.049,1889314.403
214,Genus,sp8,3870057.633,1840931.078
215,Genus,sp11,3857779.24,1805586.727
217,Genus,sp11,3852920.766,1815723.456
218,Genus,sp9,3860021.131,1748877.548
224,Genus,sp10,3761201.402,1784915.358
226,Genus,sp10,3762472.334,1785265.884
227,Genus,sp9,3768235.093,1817875.38
228,Genus,sp9,3877149.277,1799116.687
229,Genus,sp9,3857910.569,1796157.922
230,Genus,sp1,3857716.638,1800276.34
231,Genus,sp3,3764602.341,1793484.089
232,Genus,sp3,3760082.698,1789925.787
236,Genus,sp9,3861023.37,1798819.841
247,Genus,sp9,3905375.821,1741045.151
248,Genus,sp9,3886047.186,1738250.488
249,Genus,sp9,3852663.812,1751012.149
250,Genus,sp3,3854598.388,1751520.399
251,Genus,sp3,3839693.109,1751118.489
252,Genus,sp3,3762505.663,1787614.092
253,Genus,sp1,3856693.385,1752729.225
254,Genus,sp1,3864469.381,1749541.444
255,Genus,sp12,3854281.863,1752664.177
262,Genus,sp3,3774664.388,1761682.436
267,Genus,sp3,3778395.449,1761767.542
271,Genus,sp10,3769921.204,1762866.965
272,Genus,sp10,3773209.731,1764966.295
273,Genus,sp5,3871774.228,1729076.497
274,Genus,sp1,3826116.573,1798046.974
284,Genus,sp9,3875437.176,1742942.405
285,Genus,sp9,3906056.755,1748342.059
287,Genus,sp3,3833105.942,1794765.919
288,Genus,sp3,3771861.685,1760946.72
307,Genus,sp10,3628612.307,1732111.665
310,Genus,sp13,3731928.662,1623498.297
313,Genus,sp14,3839937.496,1696904.713
314,Genus,sp11,3786822.189,1645247.66
316,Genus,sp13,3653328.716,1711721.553
317,Genus,sp13,3654261.92,1716119.646
318,Genus,sp13,3655397.491,1717544.872
319,Genus,sp13,3654948.344,1711678.991
320,Genus,sp13,3657023.658,1714816.593
321,Genus,sp10,3647235.073,1714762.645
324,Genus,sp11,3813338.446,1672475.894
325,Genus,sp13,3724548.955,1612654.37
326,Genus,sp11,3814899.554,1674418.275
333,Genus,sp13,3727532.724,1622034.848
334,Genus,sp13,3721281.22,1647663.998
335,Genus,sp13,3735759.618,1612767.999
336,Genus,sp14,3865382.508,1667468.76
337,Genus,sp1,3863585.409,1621157.32
338,Genus,sp1,3888242.183,1662794.84
339,Genus,sp1,3893312.94,1672969.403
348,Genus,sp11,3811770.63,1674540.728
350,Genus,sp13,3724587.192,1612123.407
351,Genus,sp13,3725360.17,1615503.683
352,Genus,sp10,3625725.626,1641126.827
353,Genus,sp14,3859754.208,1668134.275
354,Genus,sp1,3877941.136,1629483.825
355,Genus,sp11,3813596.591,1663343.33
356,Genus,sp1,3807070.497,1669888.692
357,Genus,sp10,3613941.846,1639031.229
358,Genus,sp14,3810856.143,1664836.54
360,Genus,sp11,3791424.367,1647994.504
361,Genus,sp15,3811478.569,1665183.637
362,Genus,sp7,3656408.058,1702297.586
364,Genus,sp15,3810093.053,1663300.674
383,Genus,sp13,3728988.388,1619398.803
388,Genus,sp8,3892407.103,1665829.512
395,Genus,sp13,3690555.67,1617716.422
398,Genus,sp13,3729921.196,1618498.087
399,Genus,sp13,3733869.916,1636092.023
400,Genus,sp13,3693117.393,1616599.332
401,Genus,sp13,3731308.89,1637307.489
402,Genus,sp13,3720321.817,1608067.676
403,Genus,sp13,3732293.698,1613655.126
404,Genus,sp13,3727241.574,1609462.964
405,Genus,sp13,3724328.674,1639007.558
406,Genus,sp13,3733514.018,1640236.495
407,Genus,sp13,3736442.418,1657047
408,Genus,sp13,3723874.086,1620011.831
409,Genus,sp13,3725478.052,1623478.375
410,Genus,sp13,3734896.449,1616547.925
411,Genus,sp9,3746974.175,1608672.509
414,Genus,sp3,3867746.455,1563722.286
416,Genus,sp9,3839486.604,1519720.333
418,Genus,sp5,3852991.327,1527277.122
419,Genus,sp10,3599695.632,1552622.004
425,Genus,sp14,3759198.893,1545278.775
426,Genus,sp10,3627895.887,1585180.697
427,Genus,sp10,3623568.334,1591802.459
428,Genus,sp10,3734081.936,1596070.331
429,Genus,sp5,3739183.844,1584446.202
430,Genus,sp5,3738160.255,1578108.899
431,Genus,sp16,3758822.693,1536474.958
432,Genus,sp10,3622212.627,1591391.119
437,Genus,sp10,3578800.345,1566603.528
438,Genus,sp10,3593214.442,1564631.533
439,Genus,sp11,3752912.814,1537234.18
440,Genus,sp16,3762053.613,1538405.375
441,Genus,sp16,3747272.19,1533907.707
442,Genus,sp16,3755515.987,1543378.652
453,Genus,sp16,3746970.512,1538938.745
460,Genus,sp5,3809967.713,1476584.057
462,Genus,sp15,3668993.11,1568860.696
463,Genus,sp11,3743087.086,1579127.563
473,Genus,sp12,3685947.451,1567692.795
476,Genus,sp16,3751301.005,1533608.447
477,Genus,sp16,3762552.877,1535973.713
478,Genus,sp15,3630066.147,1506654.86
480,Genus,sp16,3745474.494,1541674.003
482,Genus,sp10,3585172.407,1564592.321
483,Genus,sp10,3583580.172,1561402.287
485,Genus,sp10,3591066.23,1567481.91
486,Genus,sp10,3585105.765,1574641.005
506,Genus,sp10,3589863.752,1563191.544
507,Genus,sp9,3644212.224,1512567.981
508,Genus,sp9,3630154.794,1530063.334
509,Genus,sp9,3857888.175,1530191.361
510,Genus,sp9,3852997.265,1570763.857
511,Genus,sp9,3828191.41,1567401.584
513,Genus,sp9,3844059.641,1515325.737
548,Genus,sp16,3758742.998,1539528.464
549,Genus,sp16,3767400.844,1540259.594
551,Genus,sp16,3753756.503,1540052.398
552,Genus,sp16,3750363.103,1540473.907
554,Genus,sp16,3757953.119,1535372.891
555,Genus,sp15,3682457.421,1555605.734
556,Genus,sp15,3645111.652,1521855.064
557,Genus,sp15,3630765.792,1514640.587
558,Genus,sp15,3622653.929,1513005.256
559,Genus,sp15,3686958.656,1559155.201
560,Genus,sp15,3643110.855,1575745.955
561,Genus,sp15,3662733.984,1546853.985
588,Genus,sp11,3860105.347,1571664.657
589,Genus,sp14,3757791.927,1580902.88
594,Genus,sp16,3761184.25,1542055.061
596,Genus,sp16,3758999.049,1539490.967
597,Genus,sp16,3761976.05,1529278.08
598,Genus,sp10,3607895.422,1593794.425
599,Genus,sp10,3582141.749,1563724.026
600,Genus,sp10,3589099.243,1565543.414
601,Genus,sp10,3584787.252,1564191.235
603,Genus,sp5,3849732.682,1527749.808
606,Genus,sp16,3756464.464,1544450.815
607,Genus,sp16,3734182.75,1547071.205
609,Genus,sp5,3824207.939,1538605.095
610,Genus,sp16,3754608.217,1539522.694
611,Genus,sp9,3852215.337,1558263.168
612,Genus,sp9,3805577.079,1484451.983
613,Genus,sp9,3855198.482,1527949.112
614,Genus,sp9,3804841.869,1496998.141
615,Genus,sp9,3853225.33,1526351.232
616,Genus,sp10,3434493.786,1523683.457
617,Genus,sp3,3828445.494,1470676.888
618,Genus,sp1,3830182.052,1477683.693
622,Genus,sp12,3606745.137,1426111.49
623,Genus,sp15,3654195.993,1465360.577
624,Genus,sp15,3662713.783,1470375.227
632,Genus,sp10,3527746.371,1441794.476
634,Genus,sp10,3726031.712,1463931.725
635,Genus,sp10,3743519.441,1448885.903
636,Genus,sp10,3682587.656,1464045.942
637,Genus,sp10,3695519.484,1453610.944
639,Genus,sp1,3831204.61,1472958.036
646,Genus,sp10,3460276.443,1443124.173
659,Genus,sp10,3686313.09,1456603.945
660,Genus,sp10,3631042.665,1415412.614
661,Genus,sp10,3690064.635,1486201.661
683,Genus,sp9,3805940.444,1381723.894
696,Genus,sp10,3460726.758,1433684.275
697,Genus,sp10,3468228.68,1433628.709
698,Genus,sp10,3500471.216,1490022.981
699,Genus,sp10,3456020.293,1453829.647
700,Genus,sp10,3439087.304,1429428.637
701,Genus,sp10,3533450.83,1411047.195
702,Genus,sp10,3469103.381,1443559.889
703,Genus,sp10,3498318.942,1487496.932
704,Genus,sp10,3458015.467,1434171.404
706,Genus,sp10,3470344.901,1445265.951
707,Genus,sp10,3504458.073,1488719.808
735,Genus,sp16,3676868.682,1387141.874
736,Genus,sp15,3660127.685,1502820.275
737,Genus,sp15,3633797.197,1428364.441
738,Genus,sp15,3655073.256,1403520.464
739,Genus,sp15,3706422.467,1495235.061
768,Genus,sp10,3500975.303,1489803.144
771,Genus,sp10,3630924.997,1411767.304
780,Genus,sp10,3463908.925,1432072.015
781,Genus,sp10,3464026.509,1433110.153
782,Genus,sp10,3469837.492,1468449.836
783,Genus,sp10,3462546.791,1436992.25
784,Genus,sp10,3407453.953,1455282.703
787,Genus,sp9,3673093.941,1495037.573
789,Genus,sp1,3545200.71,1490006.512
791,Genus,sp10,3442770.611,1392401.258
792,Genus,sp10,3495621.16,1401675.317
801,Genus,sp15,3634918.971,1338386.547
802,Genus,sp1,3776561.637,1325219.616
804,Genus,sp9,3792425.953,1350071.115
805,Genus,sp9,3762544.244,1315403.477
807,Genus,sp1,3775107.08,1367511.175
810,Genus,sp10,3436829.988,1375716.705
814,Genus,sp15,3722190.113,1363309.644
815,Genus,sp10,3688604.897,1371519.464
816,Genus,sp10,3682983.891,1376521.245
821,Genus,sp10,3451791.976,1405609.102
823,Genus,sp10,3429352.59,1317327.569
824,Genus,sp10,3439948.657,1396066.423
859,Genus,sp10,3444386.905,1393746.312
863,Genus,sp10,3439521.172,1398761.488
865,Genus,sp10,3488968.637,1337518.329
866,Genus,sp10,3424858.984,1385794.28
867,Genus,sp10,3396600.954,1398405.888
868,Genus,sp10,3472289.957,1314941.923
869,Genus,sp10,3440962.386,1388475.925
870,Genus,sp10,3437596.263,1389582.863
873,Genus,sp10,3439547.801,1392242.709
874,Genus,sp10,3446878.645,1390148.318
875,Genus,sp10,3468354.125,1406215.521
876,Genus,sp10,3441674.275,1391717.541
877,Genus,sp10,3441949.146,1389342.232
878,Genus,sp10,3394647.314,1394141.299
879,Genus,sp10,3424008.047,1410415.446
880,Genus,sp10,3432943.483,1395014.837
895,Genus,sp9,3772422.947,1368116.46
897,Genus,sp9,3767569.024,1294567.926
898,Genus,sp9,3764056.449,1308129.657
915,Genus,sp14,3719846.119,1356568.07
917,Genus,sp10,3417942.405,1392891.674
922,Genus,sp10,3437903.663,1385516.779
923,Genus,sp10,3397640.894,1393841.937
924,Genus,sp10,3685983.406,1377007.498
925,Genus,sp10,3661062.444,1387879.653
926,Genus,sp10,3615923.09,1337347.703
927,Genus,sp10,3621688.333,1344873.688
929,Genus,sp10,3394270.032,1352084.449
930,Genus,sp17,1957145.443,1424097.107
932,Genus,sp9,3759734.087,1309782.696
956,Genus,sp10,3359987.501,1305783.859
957,Genus,sp9,3657916.786,1206763.628
964,Genus,sp1,3644458.05,1181974.626
965,Genus,sp1,3647986.126,1181083.667
966,Genus,sp1,3643526.714,1178931.628
983,Genus,sp10,3348398.222,1292272.502
984,Genus,sp10,3484196.858,1230156.062
985,Genus,sp9,3681718.617,1221760.563
986,Genus,sp1,3701698.956,1226228.216
987,Genus,sp12,3507008.3,1208036.041
988,Genus,sp12,3498248.862,1202594.224
992,Genus,sp12,3504280.895,1200036.026
994,Genus,sp10,3574784.419,1209404.667
999,Genus,sp5,3699147.568,1232396.983
1002,Genus,sp10,3343246.377,1275104.921
1003,Genus,sp10,3336491.575,1230465.243
1004,Genus,sp10,3505182.377,1203598.005
1005,Genus,sp10,3390799.243,1311534.293
1006,Genus,sp10,3495542.456,1264852.46
1007,Genus,sp10,3394687.955,1306176.45
1038,Genus,sp10,3502959.359,1261612.927
1039,Genus,sp10,3488255.556,1258365.78
1040,Genus,sp10,3504188.03,1264387.58
1041,Genus,sp10,3476394.339,1271846.017
1042,Genus,sp10,3345205.205,1223109.726
1084,Genus,sp9,3671813.642,1202306.95
1085,Genus,sp9,3671452.62,1202098.263
1086,Genus,sp9,3676659.661,1203638.201
1087,Genus,sp9,3670384.424,1202761.762
1088,Genus,sp9,3661629.883,1207183.408
1089,Genus,sp9,3676051.592,1212966.446
1090,Genus,sp9,3661490.443,1201618.091
1091,Genus,sp9,3656419.827,1204662.985
1092,Genus,sp5,3651442.593,1174773.059
1093,Genus,sp5,3647171.375,1208750.072
1094,Genus,sp5,3664733.699,1203229.444
1095,Genus,sp5,3633574.022,1184029.175
1096,Genus,sp5,3635391.491,1180926.94
1162,Genus,sp12,3505684.969,1206836.2
1163,Genus,sp18,2370751.65,1293413.309
1164,Genus,sp10,3332024.772,1228262.949
1166,Genus,sp17,1991688.077,1380621.676
1167,Genus,sp17,1977157.63,1371520.591
1168,Genus,sp17,2061748.118,1374297.364
1169,Genus,sp17,2038750.209,1365367.488
1170,Genus,sp17,1974297.435,1380737.942
1172,Genus,sp17,2071941.475,1308553.907
1173,Genus,sp17,2129831.135,1292156.42
1178,Genus,sp15,3569825.583,1105618.703
1179,Genus,sp17,2068097.203,1274078.427
1180,Genus,sp12,3495900.479,1116388.906
1181,Genus,sp12,3507674.75,1117491.241
1183,Genus,sp12,3523875.986,1105786.175
1184,Genus,sp15,3587790.172,1114566.234
1185,Genus,sp19,3585518.863,1092511.391
1201,Genus,sp20,3477669.122,1156368.413
1208,Genus,sp11,3587451.605,1069142.422
1209,Genus,sp11,3593709.408,1142947.967
1210,Genus,sp11,2442352.235,1191014.211
1211,Genus,sp11,3597290.712,1107500.434
1212,Genus,sp11,3571471.992,1103841.579
1213,Genus,sp11,3575844.166,1094311.339
1214,Genus,sp11,3587849.765,1085273.823
1215,Genus,sp11,3570641.629,1098689.948
1216,Genus,sp11,3589120.005,1090612.566
1217,Genus,sp11,3578036.118,1096975.538
1255,Genus,sp10,3562111.511,1085955.695
1268,Genus,sp5,3617108.263,1156744.21
1269,Genus,sp5,3576860.234,1093512.916
1271,Genus,sp21,2236530.525,1246090.04
1277,Genus,sp19,3581675.171,1075239.867
1281,Genus,sp1,3558515.523,1070652.753
1282,Genus,sp1,3556042.615,1077311.464
1283,Genus,sp1,3587105.525,1078853.229
1284,Genus,sp1,3570378.001,1088735.446
1289,Genus,sp12,3572493.257,1088575.233
1290,Genus,sp12,3507768.783,1113803.481
1291,Genus,sp12,3510701.154,1114465.817
1292,Genus,sp12,3527878.046,1133501.378
1293,Genus,sp12,3509029.09,1119459.561
1294,Genus,sp12,3566020.832,1086318.612
1295,Genus,sp12,3589222.508,1159889.028
1323,Genus,sp11,3571598.522,1111377.642
1363,Genus,sp11,3571570.569,1096850.269
1364,Genus,sp11,3600111.817,1133976.958
1365,Genus,sp11,3461734.509,1130611.003
1366,Genus,sp18,2177929.449,1230583.404
1382,Genus,sp15,3583583.513,1066381.297
1398,Genus,sp12,3505011.194,1120662.682
1399,Genus,sp12,3582576.621,1164768.198
1423,Genus,sp12,3545854.135,1180615.697
1425,Genus,sp19,3564266.076,1139873.137
1429,Genus,sp1,3537097.548,1115224.972
1441,Genus,sp12,3522369.871,1140573.525
1444,Genus,sp12,3499354.927,1125311.431
1453,Genus,sp12,3501886.949,1118211.74
1454,Genus,sp12,3508637.706,1135689.191
1457,Genus,sp10,3551320.61,1104966.948
1458,Genus,sp1,3579731.729,1090317.823
1459,Genus,sp11,3575462.572,1130332.321
1559,Genus,sp12,3565705.763,1140607.365
1560,Genus,sp12,3533997.261,1124740.08
1561,Genus,sp12,3535472.642,1114113.536
1562,Genus,sp12,3497355.712,1121620.66
1563,Genus,sp12,3511141.247,1110482.171
1564,Genus,sp12,3524673.845,1111028.515
1565,Genus,sp12,3527747.763,1101894.793
1566,Genus,sp12,3506085.533,1110869.885
1567,Genus,sp12,3516791.54,1130498.286
1568,Genus,sp12,3547338.369,1178765.311
1569,Genus,sp21,3562153.269,1089187.93
1584,Genus,sp21,2432480.277,1181058.191
1585,Genus,sp21,2456092.803,1224222.862
1648,Genus,sp20,3461141.766,1092491.563
1649,Genus,sp10,3399022.075,1198232.405
1650,Genus,sp10,3310626.648,1195299.587
1879,Genus,sp5,3572845.419,1090477.106
1880,Genus,sp5,3621632.265,1169787.668
1881,Genus,sp5,3632082.224,1162612.287
1882,Genus,sp5,3611607.09,1122326.35
1883,Genus,sp5,3553482.723,1082751.82
1884,Genus,sp5,3615080.343,1160586.574
1885,Genus,sp5,3569954.93,1094618.296
1887,Genus,sp5,3573344.503,1068401.445
1888,Genus,sp5,3573649.023,1074591.65
1889,Genus,sp5,3574805.305,1076201.827
1890,Genus,sp5,3568120.002,1074335.426
1891,Genus,sp5,3643157.188,1169685.035
1893,Genus,sp5,3579108.933,1081461.411
1894,Genus,sp5,3616844.723,1155369.176
1895,Genus,sp5,3619683.815,1159786.183
1896,Genus,sp5,3626635.088,1151115.201
1897,Genus,sp5,3624007.257,1146051.017
1899,Genus,sp5,3621465.05,1170921.901
1900,Genus,sp5,3617808.053,1155574.09
1952,Genus,sp19,3601711.097,1132361.882
1953,Genus,sp19,3571029.97,1130367.858
1954,Genus,sp19,3592508.646,1154987.188
1955,Genus,sp19,3587839.132,1128744.78
1956,Genus,sp19,3603403.568,1124232.849
1957,Genus,sp19,3599024.676,1134998.479
1958,Genus,sp19,3600002.646,1134402.342
1959,Genus,sp19,3607326.463,1133433.576
1960,Genus,sp19,3572362.145,1140402.806
1961,Genus,sp19,3586306.456,1130460.562
1962,Genus,sp19,3581877.736,1090253.206
1963,Genus,sp19,3603147.424,1128142.588
1964,Genus,sp19,3589656.115,1117623.487
1965,Genus,sp19,3598221.267,1121288.416
1966,Genus,sp19,3588573.997,1116248.894
1968,Genus,sp19,3606278.426,1128173.53
2059,Genus,sp11,3588343.508,1083517.083
2060,Genus,sp11,3585239.083,1087883.021
2061,Genus,sp11,3595181.015,1102808.252
2062,Genus,sp11,3578400.507,1102350.765
2063,Genus,sp11,3589402.002,1090882.655
2064,Genus,sp11,3578170.896,1076529.387
2102,Genus,sp5,3587673.51,1079598.558
2126,Genus,sp19,3602791.224,1119069.738
2127,Genus,sp19,3575099.256,1169829.868
2132,Genus,sp11,3576591.004,1129637.438
2136,Genus,sp18,2424958.181,1182866.797
2137,Genus,sp18,2424870.535,1192057.253
2138,Genus,sp18,2159847.502,1228117.146
2139,Genus,sp18,2064873.837,1269168.092
2140,Genus,sp18,2473716.481,1246139.459
2141,Genus,sp18,2173388.068,1182158.677
2142,Genus,sp18,2179787.014,1234916.873
2143,Genus,sp18,2064736.384,1267058.934
2144,Genus,sp18,2165111.618,1201486.655
2146,Genus,sp22,2458534.108,1171178.333
2147,Genus,sp22,2457864.601,1174192.013
2148,Genus,sp22,2460649.598,1169571.874
2149,Genus,sp22,2450403.001,1180382.959
2150,Genus,sp22,2463656.458,1175713.993
2151,Genus,sp22,2467271.944,1172640.885
2152,Genus,sp22,2455112.952,1173734.167
2153,Genus,sp22,2456492.692,1166858.898
2154,Genus,sp22,2463154.621,1173611.939
2155,Genus,sp22,2457317.426,1173947.748
2156,Genus,sp22,2457883.906,1171492.553
2157,Genus,sp22,2460992.06,1172150.889
2158,Genus,sp22,2459486.162,1168467.327
2162,Genus,sp12,3501418.651,1117473.25
2163,Genus,sp10,3576609.61,1082438.267
2164,Genus,sp1,3546867.572,1110652.39
2165,Genus,sp17,2062974.518,1265899.738
2170,Genus,sp17,2063355.424,1268662.903
2171,Genus,sp17,2065805.757,1268053.179
2175,Genus,sp17,2061924.799,1271014.406
2177,Genus,sp17,2202220.844,1249117.036
2178,Genus,sp17,2066955.436,1265308.152
2179,Genus,sp17,2061319.915,1273055.777
2180,Genus,sp22,2460474.949,1176173.24
2181,Genus,sp19,3587807.535,1122243.329
2183,Genus,sp12,3516476.893,1124990.492
2184,Genus,sp10,3346128.821,1184470.842
2186,Genus,sp30,3587448.222,1107948.15
2194,Genus,sp15,3506999.96,1006773.739
2196,Genus,sp11,3499806.349,1008071.735
2209,Genus,sp11,3505882.813,1024262.663
2210,Genus,sp11,2432106.932,1072162.783
2211,Genus,sp11,2432655.049,1054931.646
2231,Genus,sp15,3502803.756,1037872.28
2232,Genus,sp15,3518537.876,1014510.463
2233,Genus,sp10,3446909.14,1005286.217
2234,Genus,sp10,3458323.977,991303.6719
2235,Genus,sp10,3303273.913,1099993.193
2237,Genus,sp10,3442595.09,990526.5316
2238,Genus,sp10,3452679.067,1047179.648
2239,Genus,sp10,3451466.148,1049598.611
2240,Genus,sp10,3433095.215,1013921.326
2241,Genus,sp10,3375133.126,1063175.005
2248,Genus,sp21,2443719.278,1057132.561
2259,Genus,sp12,3457643.538,989677.5003
2260,Genus,sp12,3458173.689,996966.5496
2263,Genus,sp15,3557503.945,1060651.365
2300,Genus,sp11,2433059.678,1075333.978
2326,Genus,sp15,3486515.429,1001632.425
2327,Genus,sp10,3438146.878,997890.2753
2329,Genus,sp21,2170086.751,1121166.259
2330,Genus,sp21,2173773.514,1107174.162
2372,Genus,sp10,3362549.166,1059498.749
2373,Genus,sp10,3375544.632,1049625.692
2377,Genus,sp10,3441973.812,1067272.718
2390,Genus,sp10,3382706.869,1035469.212
2391,Genus,sp15,3574610.223,1051230.397
2423,Genus,sp21,2431554.16,1056389.033
2424,Genus,sp21,2437155.353,1071228.932
2425,Genus,sp21,2445670.723,1070927.515
2426,Genus,sp21,2451935.9,1082807.434
2427,Genus,sp21,2442328.045,1102853.453
2428,Genus,sp21,2429828.419,1063195.894
2429,Genus,sp21,2441002.15,1069875.945
2430,Genus,sp21,2450849.191,1091433.539
2432,Genus,sp21,2448759.224,1059709.01
2433,Genus,sp21,2432773.488,1067000.674
2434,Genus,sp21,2443388.92,1065272.484
2435,Genus,sp21,2437625.525,1079959.124
2436,Genus,sp21,2435361.601,1078232.284
2437,Genus,sp21,2443068.552,1063027.259
2438,Genus,sp21,2433638.509,1069588.153
2439,Genus,sp21,2441148.158,1070282.978
2440,Genus,sp21,2438284.27,1065666.182
2441,Genus,sp21,2456807.336,1082904.866
2442,Genus,sp21,2437382.543,1066556.278
2443,Genus,sp21,2433719.579,1074490.559
2444,Genus,sp21,2451401.703,1080619.894
2449,Genus,sp21,2458708.94,1109343.001
2451,Genus,sp21,2458266.472,1112465.449
2452,Genus,sp21,2396081.511,1133875.839
2453,Genus,sp21,2457204.619,1111597.224
2454,Genus,sp21,2170625.599,1121209.729
2456,Genus,sp21,2174514.964,1139393.856
2458,Genus,sp21,2180671.629,1121034.028
2459,Genus,sp21,2176954.238,1117917.351
2460,Genus,sp21,2151923.779,1114081.964
2461,Genus,sp21,2154463.755,1108639.316
2462,Genus,sp21,2170529.739,1119123.674
2463,Genus,sp21,2157788.345,1119456.015
2464,Genus,sp21,2173891.938,1126230.346
2465,Genus,sp21,2160323.789,1111378.274
2466,Genus,sp21,2169202.513,1121764.71
2467,Genus,sp21,2165656.908,1118177.565
2469,Genus,sp21,2159625.544,1120326.191
2470,Genus,sp21,2176764.988,1125003.617
2471,Genus,sp21,2172043.659,1123586.915
2472,Genus,sp21,2169313.585,1122997.378
2473,Genus,sp21,2165580.339,1110906.369
2474,Genus,sp21,2139991.341,1080810.19
2475,Genus,sp21,2457300.171,1090689.477
2476,Genus,sp21,2426402.734,1067902.907
2477,Genus,sp21,2445663.864,1074250.323
2478,Genus,sp21,2457973.3,1125398.233
2479,Genus,sp21,2433074.233,1057488.932
2631,Genus,sp20,3464023.759,1073065.188
2633,Genus,sp15,3480641.57,1063784.176
2634,Genus,sp20,3465498.568,1078241.357
2635,Genus,sp20,3463129.645,1072670.782
2699,Genus,sp5,3520937.828,970240.3102
2708,Genus,sp19,3567821.267,1065402.07
2709,Genus,sp19,3512599.915,986188.8776
2710,Genus,sp19,3506825.355,975609.261
2712,Genus,sp19,3503549.873,975396.9606
2830,Genus,sp11,2441292.13,1078533.315
2831,Genus,sp11,2430839.585,1060590.615
2832,Genus,sp11,2441922.253,1079114.755
2833,Genus,sp11,2442925.237,1061043.335
2834,Genus,sp11,2445687.253,1068935.339
2835,Genus,sp11,2432393.501,1068738.093
2836,Genus,sp11,2449979.6,1066097.633
2837,Genus,sp11,2441825.113,1069952.994
2838,Genus,sp11,2433536.968,1062566.167
2839,Genus,sp11,2434320.697,1061808.583
2841,Genus,sp11,2435922.901,1055297.473
2842,Genus,sp11,2438918.138,1060729.335
2843,Genus,sp11,2432632.198,1059983.378
2844,Genus,sp11,2427727.098,1060326.518
2845,Genus,sp11,2424961.964,1066970.943
2846,Genus,sp11,2432673.604,1059729.09
2847,Genus,sp11,2438728.927,1066563.945
2848,Genus,sp11,2443485.495,1066861.406
2849,Genus,sp11,2424066.988,1061105.862
2850,Genus,sp11,2430867.488,1057733.579
2851,Genus,sp11,2434599.774,1058887.865
2852,Genus,sp11,2432079.821,1056714.704
2853,Genus,sp11,2436109.776,1058136.561
2854,Genus,sp11,2436718.753,1067406.113
2855,Genus,sp11,2429358.951,1066842.84
2856,Genus,sp11,2442508.632,1079391.298
2857,Genus,sp11,2447128.151,1078361.72
2858,Genus,sp11,2428637.014,1064524.213
2859,Genus,sp11,2436854.408,1057420.044
2860,Genus,sp11,2437444.876,1068494.283
2861,Genus,sp11,2446364.283,1072557.36
2862,Genus,sp11,2434421.184,1057368.348
2863,Genus,sp11,2434553.366,1069144.75
2864,Genus,sp11,2433072.818,1077856.358
2865,Genus,sp11,2430428.269,1065617.162
2866,Genus,sp11,2453245.38,1059848.608
2867,Genus,sp11,2437099.362,1075997.851
2868,Genus,sp11,2443922.05,1072775.041
2869,Genus,sp11,2433782.541,1056895.957
2870,Genus,sp11,2435551.625,1054607.575
2871,Genus,sp11,2430826.202,1062605.158
2872,Genus,sp11,2436650.214,1057194.215
2873,Genus,sp11,2419104.898,1068881.4
2874,Genus,sp11,2439396.874,1076727.903
2875,Genus,sp11,2429378.596,1061681.587
2876,Genus,sp11,2431474.333,1058631.913
2877,Genus,sp11,2435615.13,1058007.287
2878,Genus,sp11,2427612.983,1063556.889
2879,Genus,sp11,2427219.017,1062574.801
2880,Genus,sp11,2433836.003,1064426.369
2881,Genus,sp11,2435681.653,1058693.813
2882,Genus,sp11,2433709.692,1061642.369
2883,Genus,sp11,2429719.353,1059215.519
2884,Genus,sp11,2433289.214,1063904.603
2886,Genus,sp11,2434585.319,1065362.904
2887,Genus,sp11,2469843.789,1108598.017
2888,Genus,sp11,2436866.532,1056635.204
2889,Genus,sp11,2435597.099,1056432.518
2890,Genus,sp11,2435784.708,1064254.7
2891,Genus,sp11,2437085.787,1055162.559
2892,Genus,sp11,2437215.401,1059384.283
2893,Genus,sp11,2519195.508,1051731.3
2894,Genus,sp11,2429026.742,1065625.082
2895,Genus,sp11,2438309.622,1070065.041
2896,Genus,sp11,2433441.168,1072344.204
2897,Genus,sp11,2438578.657,1070391.04
2898,Genus,sp11,2434025.518,1057990.244
2899,Genus,sp11,2440475.92,1063352.124
2900,Genus,sp11,2433814.482,1063392.218
2901,Genus,sp11,2435415.592,1055345.183
2902,Genus,sp11,2430024.403,1056016.326
2903,Genus,sp11,2433170.335,1062465.443
2904,Genus,sp11,2442907.355,1077424.007
2905,Genus,sp11,2436209.087,1070212.57
2906,Genus,sp11,2433985.503,1056229.537
2907,Genus,sp11,2432355.577,1058263.659
2908,Genus,sp11,2439872.543,1079256.928
2909,Genus,sp11,2434283.474,1065735.704
2910,Genus,sp11,2437142.064,1066744.455
2933,Genus,sp21,2175960.911,1088238.567
2934,Genus,sp21,2447478.114,1066701.849
2935,Genus,sp21,2458702.782,1084368.692
2936,Genus,sp21,2419300.829,1065040.026
2950,Genus,sp11,2434232.179,1059824.091
2951,Genus,sp11,2429827.062,1063927.074
2952,Genus,sp11,2431007.459,1070276.193
2978,Genus,sp12,3493273.8,1077513.749
3047,Genus,sp19,3499659.949,966041.3883
3059,Genus,sp18,2456648.384,1098738.576
3060,Genus,sp18,2166768.755,1164331.624
3062,Genus,sp21,2162410.349,1114870.518
3063,Genus,sp22,2462434.993,1163333.958
3064,Genus,sp22,2457257.002,1166757.311
3065,Genus,sp22,2462851.95,1163240.088
3066,Genus,sp22,2463181.97,1164343.222
3067,Genus,sp22,2460550.585,1170848.501
3068,Genus,sp22,2461731.885,1170233.532
3072,Genus,sp12,3512655.921,1070048.363
3076,Genus,sp12,3460052.406,1015718.24
3077,Genus,sp11,3566685.737,1054113.459
3078,Genus,sp11,2449506.391,1069626.993
3079,Genus,sp15,3486039.887,1005327.122
3085,Genus,sp15,3521911.674,1064484.253
3086,Genus,sp9,3484327.987,1005403.623
3094,Genus,sp11,2305342.345,995999.0701
3099,Genus,sp18,2327558.581,1045353.818
3110,Genus,sp10,3380998.558,900059.2946
3111,Genus,sp10,3378650.014,901872.5379
3114,Genus,sp11,3480482.842,908129.7951
3133,Genus,sp20,3433720.24,925853.311
3134,Genus,sp20,3344098.659,901691.7176
3135,Genus,sp20,3346597.983,903303.1685
3136,Genus,sp20,3453983.654,932134.1274
3138,Genus,sp15,3477084.08,916188.341
3139,Genus,sp11,3426726.183,877487.2272
3150,Genus,sp11,2299396.063,968336.5968
3151,Genus,sp11,2301637.425,970206.8605
3152,Genus,sp11,2408179.184,1015572.157
3153,Genus,sp11,3443856.253,915630.7471
3154,Genus,sp18,2467781.146,1037941.875
3155,Genus,sp18,2296050.866,956537.2199
3156,Genus,sp18,2535944.033,957630.9969
3157,Genus,sp18,2535888.447,953827.8202
3158,Genus,sp18,2700123.362,953503.3506
3161,Genus,sp18,2480565.216,1047057.888
3176,Genus,sp21,2324095.846,971151.6652
3177,Genus,sp21,2323069.636,974133.2623
3189,Genus,sp15,3536045.548,964800.7011
3190,Genus,sp10,3381154.768,939143.1174
3192,Genus,sp10,3444433.174,936017.2554
3193,Genus,sp10,3438786.184,962767.7857
3194,Genus,sp10,3377149.749,944371.208
3195,Genus,sp10,3384034.323,943584.4425
3197,Genus,sp10,3386008.687,941504.6966
3198,Genus,sp10,3388648.336,938417.873
3199,Genus,sp10,3400484.628,922768.6449
3200,Genus,sp10,3381000.626,945263.2428
3201,Genus,sp10,3425946.165,940785.4627
3202,Genus,sp10,3383783.05,944766.9156
3203,Genus,sp10,3443615.443,944276.4045
3204,Genus,sp10,3387945.03,947703.0204
3205,Genus,sp10,3382336.237,947580.9392
3208,Genus,sp21,2423615.101,1024254.654
3209,Genus,sp21,2434059.599,1022539.395
3258,Genus,sp1,3470236.869,904844.3773
3259,Genus,sp1,3449075.402,913529.1435
3260,Genus,sp1,3476819.525,916347.1126
3261,Genus,sp19,3520239.609,945153.3111
3262,Genus,sp12,2391599.493,993192.7348
3263,Genus,sp12,3448282.887,866085.5113
3265,Genus,sp12,3436113.205,920097.0477
3266,Genus,sp12,3430502.866,920460.0216
3315,Genus,sp19,3520757.799,956500.9853
3324,Genus,sp11,2432457.134,1048144.334
3325,Genus,sp11,2429424.846,1058836.006
3326,Genus,sp12,3456459.766,924138.431
3328,Genus,sp11,3492967.914,962978.2538
3330,Genus,sp11,3517004.048,943464.9816
3334,Genus,sp11,3526997.013,959097.8911
3335,Genus,sp12,3442829.24,868193.8048
3346,Genus,sp11,3520056.931,941626.7902
3347,Genus,sp18,2290189.856,959254.3824
3361,Genus,sp20,3359147.628,898422.8785
3364,Genus,sp11,3519442.91,949327.3201
3365,Genus,sp18,2466473.288,1031999.407
3366,Genus,sp18,2530177.89,958207.5068
3379,Genus,sp15,3493195.694,965449.4583
3389,Genus,sp1,3483493.025,903796.7111
3390,Genus,sp1,3487534.083,910669.0037
3391,Genus,sp1,3457441.36,902807.926
3393,Genus,sp19,3516705.086,950148.9441
3394,Genus,sp19,3514319.093,956989.1316
3395,Genus,sp12,2393517.718,989582.3573
3421,Genus,sp15,3511958.955,949597.602
3423,Genus,sp10,3486296.418,952838.1772
3426,Genus,sp19,3513163.423,944191.0366
3427,Genus,sp21,2329571.597,975941.9106
3428,Genus,sp15,3519774.954,946924.2794
3429,Genus,sp19,3526386.733,954954.5792
3437,Genus,sp10,3385534.26,936255.2737
3462,Genus,sp12,3434360.484,866402.8467
3464,Genus,sp10,3438499.19,962568.3914
3465,Genus,sp10,3452020.162,948516.1907
3466,Genus,sp10,3441859.085,942457.4371
3467,Genus,sp10,3380942.338,944612.2072
3468,Genus,sp10,3382242.488,942478.5565
3472,Genus,sp11,3451110.981,909560.3162
3502,Genus,sp12,2271281.849,978429.1271
3503,Genus,sp12,2265671.338,950034.8852
3504,Genus,sp12,2256858.472,966233.025
3505,Genus,sp12,2265741.186,972049.3526
3506,Genus,sp12,2260912.019,978416.4089
3507,Genus,sp12,2249866.412,984524.4837
3508,Genus,sp12,2339662.441,990888.2054
3509,Genus,sp12,2323424.45,970093.831
3510,Genus,sp12,2290015.087,950254.6322
3511,Genus,sp12,2251895.064,984381.894
3512,Genus,sp12,2262030.863,957629.697
3513,Genus,sp12,2396636.44,983630.5031
3514,Genus,sp12,2413379.7,993130.8738
3515,Genus,sp12,2386990.415,990845.0353
3516,Genus,sp12,2417129.945,994975.5355
3517,Genus,sp12,2395563.743,995400.0135
3518,Genus,sp12,2395711.931,1011706.039
3519,Genus,sp12,2384303.016,991433.7046
3520,Genus,sp12,2389963.628,997238.9718
3521,Genus,sp12,2415216.305,990670.6195
3522,Genus,sp12,2390442.239,995471.7322
3523,Genus,sp12,3458674.23,895953.0771
3524,Genus,sp12,3460816.719,893869.3164
3526,Genus,sp21,2415558.192,1028220.446
3527,Genus,sp21,2410450.625,995892.5038
3528,Genus,sp21,2438399.312,1040646.103
3529,Genus,sp21,2428072.717,1048762.744
3530,Genus,sp21,2440308.666,1010008.082
3531,Genus,sp21,2437172.913,992078.42
3532,Genus,sp21,2401279.838,985264.8804
3533,Genus,sp21,2438556.489,1014684.069
3534,Genus,sp21,2430680.322,1018572.254
3535,Genus,sp21,2443757.207,1014283.294
3536,Genus,sp21,2395684.748,996657.1908
3537,Genus,sp21,2433180.252,1019736.624
3538,Genus,sp21,2429941.41,1054772.872
3542,Genus,sp21,2432890.486,1012340.503
3543,Genus,sp21,2420659.654,1056331.833
3544,Genus,sp21,2395205.232,992766.1701
3545,Genus,sp21,2436479.784,1052251.298
3546,Genus,sp21,2439026.727,1053204.189
3547,Genus,sp21,2445578.999,1023381.003
3548,Genus,sp21,2413553.582,987010.6485
3549,Genus,sp21,2426327.099,1018454.935
3550,Genus,sp21,2407923.873,987418.5499
3551,Genus,sp21,2389657.751,992782.283
3552,Genus,sp21,2430199.65,1016278.931
3553,Genus,sp21,2410662.475,993300.1951
3554,Genus,sp21,2437835.944,1050811.03
3555,Genus,sp21,2424655.041,1056319.125
3556,Genus,sp21,2425313.796,1052673.005
3557,Genus,sp21,2439365.952,1021279.558
3558,Genus,sp21,2430350.243,1060441.292
3559,Genus,sp21,2423491.327,1052865.729
3560,Genus,sp21,2429704.778,1055741.33
3561,Genus,sp21,2423912.239,1059549.79
3562,Genus,sp21,2427294.827,1052930.627
3563,Genus,sp21,2431238.364,1055483.627
3564,Genus,sp21,2430869.095,1052119.194
3565,Genus,sp21,2430310.498,1052279.344
3566,Genus,sp21,2398562.866,989513.6898
3567,Genus,sp21,2422181.813,1028153.321
3568,Genus,sp21,2415513.211,990828.6807
3569,Genus,sp21,2438537.628,1006739.027
3570,Genus,sp21,2430653.854,1053690.235
3571,Genus,sp21,2432715.342,1059849.066
3572,Genus,sp21,2417478.034,1026455.43
3573,Genus,sp21,2424796.283,1025279.252
3574,Genus,sp21,2444906.073,1048044.334
3578,Genus,sp21,2441502.333,1056197.23
3580,Genus,sp21,2418328.453,992722.6186
3581,Genus,sp21,2415105.225,989853.093
3582,Genus,sp21,2418524.366,988063.6412
3583,Genus,sp21,2428466.751,1039085.799
3584,Genus,sp21,2434173.776,1017672.157
3585,Genus,sp21,2439047.684,1015566.189
3586,Genus,sp21,2428911.476,1016592.309
3769,Genus,sp20,3436301.127,916400.9018
3770,Genus,sp20,3451688.02,932159.4966
3771,Genus,sp20,3448392.466,926767.2743
3772,Genus,sp20,3431225.582,929730.2881
3773,Genus,sp20,3476447.416,953566.4891
3774,Genus,sp20,3303681.14,899339.8964
3775,Genus,sp20,3436125.969,915559.9068
3776,Genus,sp20,3439064.655,912479.9155
3777,Genus,sp20,3436774.315,920995.8742
3778,Genus,sp20,3443995.309,932345.2783
3779,Genus,sp20,3439507.953,909912.4525
3780,Genus,sp20,3288680.389,930642.5573
3805,Genus,sp19,3525643.794,961440.0177
3806,Genus,sp19,3518093.984,954684.19
3807,Genus,sp19,3520675.775,959580.4332
3808,Genus,sp19,3513068.047,944747.3073
3809,Genus,sp19,3511617.69,947077.5804
3810,Genus,sp19,3478134.261,934061.0551
3811,Genus,sp19,3487101.645,948501.4537
3813,Genus,sp19,3516819.967,954658.6233
4029,Genus,sp21,2325612.308,973715.561
4030,Genus,sp21,2329124.91,970451.8014
4032,Genus,sp21,2323919.629,977742.0162
4085,Genus,sp11,2405053.576,1011571.21
4086,Genus,sp11,2435338.66,1020759.98
4087,Genus,sp11,2426145.056,1012236.934
4088,Genus,sp11,2426041.497,1026548.11
4089,Genus,sp11,2432406.912,1046933.075
4090,Genus,sp11,2546444.239,957673.9842
4091,Genus,sp11,2429188.084,1060256.91
4092,Genus,sp11,2392683.664,995731.3394
4093,Genus,sp11,2430136.447,1061504.258
4094,Genus,sp11,2433400.595,1031198.072
4095,Genus,sp11,2428277.631,1023224.304
4096,Genus,sp11,2431998.799,1027657.131
4097,Genus,sp11,2435546.964,1024342.047
4098,Genus,sp11,2428442.673,1022430.903
4099,Genus,sp11,2433526.373,1029431.002
4100,Genus,sp11,2376618.421,987493.8834
4101,Genus,sp11,2429219.029,1060009.605
4102,Genus,sp11,2417860.049,991320.2548
4103,Genus,sp11,2401330.508,987127.3587
4104,Genus,sp11,2422699.752,1019081.788
4105,Genus,sp11,2417276.666,1029321.93
4106,Genus,sp11,2430808.89,1061968.803
4107,Genus,sp11,2432261.285,1055720.09
4109,Genus,sp11,2424364.174,1055507.388
4110,Genus,sp11,2409343.972,1015789.343
4111,Genus,sp11,2387788.423,990630.844
4113,Genus,sp11,2437065.641,1053792.685
4114,Genus,sp11,2437317.082,1051370.114
4115,Genus,sp11,2406756.362,1017135.059
4116,Genus,sp11,2424077.882,1001791.974
4117,Genus,sp11,2436943.213,1049228.612
4118,Genus,sp11,2415982.567,1007640.101
4119,Genus,sp11,2426480.444,1051201.135
4120,Genus,sp11,2428578.718,1060871.007
4121,Genus,sp11,2420900.823,1033571.092
4122,Genus,sp11,2438849.548,1060033.855
4123,Genus,sp11,2433465.292,1053776.711
4124,Genus,sp11,2408863.23,1014145.564
4125,Genus,sp11,2439828.25,1054885.884
4126,Genus,sp11,2432971.677,1049930.886
4127,Genus,sp11,2440966.158,1056299.906
4128,Genus,sp11,2431718.889,1061183.456
4129,Genus,sp11,2434850.909,1058619.157
4130,Genus,sp11,2427429.995,1016738.44
4131,Genus,sp11,2435935.958,1056057.251
4132,Genus,sp11,2384476.801,982021.9015
4133,Genus,sp11,2410665.718,1012129.069
4134,Genus,sp11,2431654.678,1029105.007
4135,Genus,sp11,2376143.755,995367.9011
4136,Genus,sp11,2488257.328,1036338.859
4138,Genus,sp11,2418046.913,1019625.112
4139,Genus,sp11,2427655.446,1059823.035
4140,Genus,sp11,2431046.549,1053693.243
4141,Genus,sp11,2399365.154,988722.6277
4142,Genus,sp11,2280698.018,980226.3454
4143,Genus,sp11,3480308.695,900331.2637
4145,Genus,sp11,2429465.566,1053804.386
4146,Genus,sp11,2431402.403,1037092.935
4147,Genus,sp11,2427181.649,1053003.059
4148,Genus,sp11,2436847.978,1058967.855
4149,Genus,sp11,2429733.707,1055385.6
4150,Genus,sp11,2435526.704,1056208.538
4152,Genus,sp11,2433132.249,1060026.237
4153,Genus,sp11,2428499.726,1061210.497
4154,Genus,sp11,2384848.126,991077.5507
4155,Genus,sp11,2419715.392,1023981.798
4156,Genus,sp11,2409753.712,1012937.649
4157,Genus,sp11,2392860.223,993209.9755
4158,Genus,sp11,2372379.967,969509.5568
4159,Genus,sp11,2373031.906,971985.9522
4160,Genus,sp11,2373332.345,963603.0051
4161,Genus,sp11,2342278.902,976526.6506
4162,Genus,sp11,2301337.397,976917.498
4163,Genus,sp11,2248349.917,962450.351
4164,Genus,sp11,2243258.895,966810.5503
4165,Genus,sp11,2436125.16,1052157.616
4166,Genus,sp11,2442873.172,1054451.631
4167,Genus,sp11,2445096.773,1049423.094
4168,Genus,sp11,2430127.781,1061524.616
4169,Genus,sp11,2375947.184,995050.6969
4170,Genus,sp11,2288539.572,981186.4229
4171,Genus,sp11,2270042.535,988434.6149
4172,Genus,sp11,2277726.724,987203.5491
4173,Genus,sp11,2248518.605,958521.9058
4174,Genus,sp11,2239571.067,976617.0619
4175,Genus,sp11,2367165.994,971485.739
4176,Genus,sp11,2312539.776,974808.0326
4177,Genus,sp11,2255211.32,991670.7787
4178,Genus,sp11,2248740.302,993856.1553
4179,Genus,sp11,2254188.635,965297.2076
4180,Genus,sp11,2282444.38,985679.506
4181,Genus,sp11,2263040.767,973427.4038
4182,Genus,sp11,2248715.69,958698.4881
4183,Genus,sp11,2255653.56,976786.8794
4184,Genus,sp11,2241955.73,956470.0756
4209,Genus,sp12,2368759.792,967860.4764
4210,Genus,sp12,2246140.351,961747.1281
4211,Genus,sp12,2392472.874,993791.2356
4212,Genus,sp12,2384062.987,988555.8625
4214,Genus,sp12,2269861.434,966555.911
4217,Genus,sp21,2422724.455,1033331.75
4218,Genus,sp21,2424725.891,1053475.054
4219,Genus,sp21,2445939.899,1053204.2
4250,Genus,sp11,2423063.073,1060270.24
4251,Genus,sp11,2434943.491,1050700.262
4252,Genus,sp11,2437563.466,1053074.906
4253,Genus,sp11,2434536.773,1026540.748
4254,Genus,sp11,2309922.317,979248.5994
4255,Genus,sp11,2264476.14,948918.103
4256,Genus,sp11,2312393.771,975161.5086
4258,Genus,sp11,2270131.854,955332.2934
4259,Genus,sp11,2434308.957,1058609.77
4260,Genus,sp11,2312115.09,995158.731
4261,Genus,sp11,2428866,1046662.726
4262,Genus,sp11,2418914.697,1024974.467
4263,Genus,sp11,2428804.585,1052017.86
4294,Genus,sp21,2441165.458,1044669.914
4467,Genus,sp18,2423350.28,1000858.023
4476,Genus,sp10,3441830.902,971007.8671
4483,Genus,sp11,2312229.704,968287.1283
4484,Genus,sp18,2530777.847,993974.7308
4525,Genus,sp18,2466221.059,1038235.857
4526,Genus,sp18,2527803.432,992315.4209
4527,Genus,sp18,2446099.336,1015930.941
4528,Genus,sp18,2440087.523,1004869.161
4529,Genus,sp18,2479545.003,1038434.408
4530,Genus,sp18,2479013.948,1041590.043
4531,Genus,sp18,2475705.835,1042182.726
4532,Genus,sp18,2483476.641,1038216.007
4535,Genus,sp18,2470527.603,1031433.678
4536,Genus,sp18,2330791.995,1052723.413
4537,Genus,sp18,2328300.553,1045119.564
4538,Genus,sp18,2334366.503,1043381.596
4539,Genus,sp18,2374001.716,990743.2348
4540,Genus,sp17,2294527.651,981774.9107
4541,Genus,sp17,2286471.451,986625.6694
4542,Genus,sp18,2410687.992,989938.7721
4543,Genus,sp18,2469049.722,1036514.55
4544,Genus,sp18,2330398.442,1048238.619
4545,Genus,sp18,2240363.057,980310.0145
4546,Genus,sp18,2259007.09,1051472.103
4547,Genus,sp18,2456856.97,1008574.757
4549,Genus,sp18,2470695.93,1030952.754
4550,Genus,sp18,2376971.221,995562.2018
4551,Genus,sp18,2286104.632,949303.2017
4553,Genus,sp18,2432040.837,1001207.803
4554,Genus,sp18,2472965.157,1048000.947
4555,Genus,sp18,2478385.729,1038195.489
4556,Genus,sp18,2281246.128,950977.143
4557,Genus,sp18,2531468.517,989037.3698
4558,Genus,sp18,2292774.092,951985.9313
4559,Genus,sp18,2291831.55,951516.6266
4560,Genus,sp18,2286071.024,958680.0788
4561,Genus,sp18,2527148.909,992293.3528
4562,Genus,sp18,2532312.57,954402.8414
4563,Genus,sp18,2472013.508,1038710.72
4564,Genus,sp18,2471828.45,1032423.499
4565,Genus,sp18,2292483.862,948884.8543
4566,Genus,sp21,2291821.738,983098.7745
4567,Genus,sp21,2324193.676,977820.3766
4568,Genus,sp21,2328895.09,973512.7772
4569,Genus,sp21,2334404.355,977520.674
4570,Genus,sp21,2326011.576,973881.2005
4571,Genus,sp21,2323413.245,964219.2235
4573,Genus,sp21,2435282.232,1014377.471
4574,Genus,sp18,2293503.548,950309.0139
4575,Genus,sp1,3450683.024,908859.0068
4576,Genus,sp21,2332196.667,968822.047
4577,Genus,sp21,2436187.372,1022252.693
4578,Genus,sp21,2325328.318,962222.4593
4579,Genus,sp30,2428398.757,1008907.068
4581,Genus,sp10,3387921.472,949708.187
4584,Genus,sp12,3437323.491,866223.624
4585,Genus,sp1,3456404.651,879901.9641
4591,Genus,sp10,3385570.586,941832.9164
4601,Genus,sp15,3435814.351,867957.3327
4612,Genus,sp11,2416510.694,1027670.438
4613,Genus,sp11,2433623.173,1058096.569
4614,Genus,sp11,2407636.84,1006753.986
4615,Genus,sp11,2252966.008,956372.297
4616,Genus,sp11,2309876.026,966869.6873
4617,Genus,sp11,2306620.345,996015.002
4618,Genus,sp11,3450297.028,909542.9958
4619,Genus,sp21,2328723.29,970356.5846
4621,Genus,sp12,3441204.089,870728.9916
4625,Genus,sp21,2434613.322,1020395.8
4626,Genus,sp10,3442303.692,967716.1331
4627,Genus,sp21,3436828.073,963120.6149
4630,Genus,sp10,3453272.827,956185.415
4631,Genus,sp10,3453530.893,962699.7916
4634,Genus,sp21,2548633.27,935660.7446
4635,Genus,sp21,2553565.855,940478.9875
4637,Genus,sp18,2551152.683,937952.2285
4649,Genus,sp23,3147509.88,821669.3882
4650,Genus,sp23,3135665.21,852149.9089
4730,Genus,sp24,3243010.257,872017.2811
4731,Genus,sp24,3207622.379,881545.8853
4732,Genus,sp24,3084682.755,804678.9363
4733,Genus,sp24,3090193.409,802766.799
4734,Genus,sp24,3047107.324,808882.1688
4735,Genus,sp24,3052931.4,808824.8068
4736,Genus,sp24,3045559.914,814230.5006
4737,Genus,sp24,3046579.726,806850.1116
4738,Genus,sp24,3049213.591,807882.0054
4739,Genus,sp24,3049346.48,806118.5098
4740,Genus,sp24,3059860.351,814310.4673
4749,Genus,sp20,3405000.489,858576.0615
4755,Genus,sp25,3140321.818,884397.2611
4756,Genus,sp11,3453588.766,841929.4977
4757,Genus,sp18,2576489.545,900871.6031
4786,Genus,sp24,3109266.676,813169.7297
4787,Genus,sp26,3396828.993,833317.2784
4789,Genus,sp25,3096650.813,870695.7299
4790,Genus,sp25,3144801.854,877664.3809
4801,Genus,sp1,3426580.126,764429.8463
4802,Genus,sp12,2705453.148,849247.9054
4835,Genus,sp25,3248624.852,883958.2382
4842,Genus,sp20,3381590.497,791936.3121
4843,Genus,sp20,3405352.926,863831.9419
4844,Genus,sp20,3400568.82,827729.0434
4845,Genus,sp11,3420843.834,768891.6139
4853,Genus,sp25,3091590.343,863978.9559
4857,Genus,sp15,3385557.413,760824.9696
4858,Genus,sp15,3414875.303,765544.5593
4859,Genus,sp15,3417244.166,755409.0051
4860,Genus,sp25,3103461.818,860761.5608
4861,Genus,sp25,3096465.965,872767.1656
4862,Genus,sp25,3098999.82,868727.0329
4863,Genus,sp1,3427997.31,766918.3066
4864,Genus,sp1,3382101.711,766058.8101
4870,Genus,sp11,3458426.435,853634.6167
4871,Genus,sp15,3445024.886,852986.9165
4872,Genus,sp11,3451904.93,849757.047
4873,Genus,sp1,3450077.575,853555.572
4876,Genus,sp15,3446252.728,853326.867
4883,Genus,sp20,3379532.769,830741.4576
4884,Genus,sp15,3384111.689,766205.4627
4906,Genus,sp12,2703796.311,848734.199
4907,Genus,sp21,2655530.086,882244.6694
4908,Genus,sp21,2623114.205,902845.1841
4909,Genus,sp21,2622933.313,910386.6884
4910,Genus,sp21,2596943.338,912794.0024
4911,Genus,sp21,2616460.261,902882.4439
4913,Genus,sp21,2612644.449,911598.6627
4914,Genus,sp21,2597329.35,923391.8328
4915,Genus,sp21,2592652.855,919750.2078
4916,Genus,sp21,2617711.464,905837.5644
4917,Genus,sp21,2568038.914,832672.2674
4918,Genus,sp21,2587835.897,890033.2258
4919,Genus,sp21,2614247.455,899335.4523
4934,Genus,sp27,3403977.473,762946.103
4937,Genus,sp20,3402263.098,870615.3474
4938,Genus,sp20,3400776.621,865578.8941
4946,Genus,sp24,3051934.49,814855.1576
4947,Genus,sp24,3047761.339,813977.4718
4948,Genus,sp24,3045634.553,808611.6211
4949,Genus,sp24,3053807.547,815536.1465
4950,Genus,sp26,3396592.73,832074.205
4988,Genus,sp21,2615162.212,904580.9299
4989,Genus,sp21,2611969.465,901239.1563
4990,Genus,sp21,2613264.797,904400.3318
5005,Genus,sp15,3359602.198,781375.1907
5007,Genus,sp24,3051914.9,806763.8996
5027,Genus,sp20,3395216.781,825352.8869
5043,Genus,sp18,2289430.767,947703.5777
5044,Genus,sp18,2277274.771,954919.3591
5045,Genus,sp18,2505066.646,938425.3101
5046,Genus,sp18,2621970.712,861010.0382
5047,Genus,sp21,2655981.205,868153.3433
5048,Genus,sp18,2291723.239,951391.1852
5049,Genus,sp18,2291497.311,951470.6976
5050,Genus,sp18,2278120.86,951820.6927
5051,Genus,sp18,2294854.526,948409.902
5052,Genus,sp18,2613328.459,903652.5381
5053,Genus,sp18,2588561.921,870126.4231
5054,Genus,sp21,2610224.327,898590.8794
5055,Genus,sp27,2757645.186,827136.6061
5056,Genus,sp27,3404251.367,756084.1058
5057,Genus,sp27,3403844.163,761756.1888
5061,Genus,sp15,3451488.232,848811.8127
5062,Genus,sp12,3079164.048,802849.2543
5075,Genus,sp25,3140874.834,878158.5355
5076,Genus,sp11,3425418.989,802937.9393
5077,Genus,sp12,2751426.605,829468.7685
5079,Genus,sp1,3429500.666,775644.348
5082,Genus,sp21,3428077.705,775253.399
5083,Genus,sp21,2718891.217,815725.5368
5085,Genus,sp20,3253655.662,763108.2626
5098,Genus,sp27,2773554.781,784541.5746
5155,Genus,sp23,2868931.14,718993.5256
5156,Genus,sp23,2875366.954,721563.1141
5157,Genus,sp23,3038099.951,715478.6162
5158,Genus,sp23,2854947.782,738403.6788
5159,Genus,sp23,2881435.745,738369.5288
5160,Genus,sp23,2875078.576,742422.7812
5161,Genus,sp23,2875997.608,744859.4141
5162,Genus,sp23,2873897.184,750847.3708
5163,Genus,sp23,2935614.151,741300.7471
5164,Genus,sp23,2945965.49,743566.0794
5165,Genus,sp23,2935787.608,745802.6937
5166,Genus,sp23,2937590.79,750405.1227
5167,Genus,sp23,2942262.776,749318.6674
5168,Genus,sp23,2986728.273,758409.6606
5169,Genus,sp23,2935544.239,761538.6165
5170,Genus,sp23,2830983.54,777225.0031
5171,Genus,sp23,2832017.609,778653.2718
5173,Genus,sp23,2990714.592,693136.4452
5174,Genus,sp23,2995475.065,695892.1898
5175,Genus,sp23,2992162.707,687139.0038
5176,Genus,sp23,2995902.376,696092.4469
5177,Genus,sp23,3045332.14,683249.9416
5178,Genus,sp23,3037071.083,684859.34
5179,Genus,sp23,3037812.353,690604.2264
5180,Genus,sp23,3112559.849,684993.4748
5181,Genus,sp23,3003347.205,690777.2539
5182,Genus,sp23,3032773.006,684061.3519
5183,Genus,sp23,3099150.092,685376.5832
5184,Genus,sp23,3099031.194,685725.5413
5185,Genus,sp23,3011010.291,693657.4582
5186,Genus,sp23,3016488.448,694774.0175
5187,Genus,sp23,3017184.775,690840.0101
5188,Genus,sp23,2996328.796,699936.3334
5189,Genus,sp23,3012543.975,698586.7709
5190,Genus,sp23,3037326.354,697673.2483
5191,Genus,sp23,2992987.584,707704.0373
5192,Genus,sp23,2996402.112,704880.2863
5193,Genus,sp23,2995294.057,709566.7378
5194,Genus,sp23,3085383.127,695269.0538
5195,Genus,sp23,2992830.79,710249.1646
5196,Genus,sp23,3000312.141,709234.2709
5197,Genus,sp23,2871914.501,724670.0223
5198,Genus,sp23,2994456.148,710814.5937
5199,Genus,sp23,3005187.242,711622.7837
5200,Genus,sp23,3012201.057,711270.5479
5201,Genus,sp23,3011285.568,712185.7365
5202,Genus,sp23,3018216.721,709814.1781
5203,Genus,sp23,3018308.18,710225.9848
5204,Genus,sp23,3039509.621,709470.4704
5205,Genus,sp23,2992585.182,714128.5774
5206,Genus,sp23,3353144.699,679607.254
5207,Genus,sp23,3357147.507,686699.0092
5208,Genus,sp23,2995709.527,722492.1223
5209,Genus,sp23,2831359.66,740135.0018
5210,Genus,sp23,2830628.329,735827.8487
5211,Genus,sp23,2831208.212,734011.5344
5212,Genus,sp23,3012517.101,724684.853
5213,Genus,sp23,2998671.411,730210.1359
5214,Genus,sp23,3268479.322,705605.0631
5215,Genus,sp23,3000167.258,731269.62
5216,Genus,sp23,3324037.86,702733.1826
5217,Genus,sp23,2873464.446,742161.7998
5218,Genus,sp23,3008853.094,736794.4124
5219,Genus,sp23,3021571.581,736156.9523
5220,Genus,sp23,3016624.496,729751.929
5221,Genus,sp23,3033734.142,729216.9824
5222,Genus,sp23,3199391.562,715470.4864
5223,Genus,sp23,3226024.526,721732.1988
5224,Genus,sp23,3012352.333,740203.5684
5225,Genus,sp23,3022391.404,745309.723
5226,Genus,sp23,3250898.205,717528.6119
5227,Genus,sp23,2997383.221,744369.961
5228,Genus,sp23,3003071.908,751782.6054
5229,Genus,sp23,2885011.115,760296.9785
5230,Genus,sp23,2888542.242,764798.7676
5231,Genus,sp23,2984878.283,751124.0409
5232,Genus,sp23,3251615.54,723717.9912
5233,Genus,sp23,3323034.887,718790.3297
5234,Genus,sp23,2871398.1,773807.0146
5235,Genus,sp23,2913795.146,707613.9288
5236,Genus,sp23,2908292.377,711293.1014
5237,Genus,sp23,2914709.264,712131.346
5238,Genus,sp23,2913432.559,712731.3283
5239,Genus,sp23,2907780.434,714500.5267
5240,Genus,sp23,2904044.455,722363.2757
5241,Genus,sp23,2920274.853,727625.7443
5242,Genus,sp23,2919664.295,725663.7947
5366,Genus,sp15,3418959.519,739772.4988
5367,Genus,sp15,3231791.616,712716.6177
5368,Genus,sp15,3368004.547,723136.0337
5386,Genus,sp28,2728936.751,767871.9677
5387,Genus,sp28,2736307.602,761313.5149
5388,Genus,sp28,2728064.68,777727.8575
5389,Genus,sp28,2735750.968,775988.7857
5548,Genus,sp5,3374240.369,742123.7712
5549,Genus,sp29,3002296.817,711137.8617
5558,Genus,sp30,3359372.002,716606.0158
5559,Genus,sp1,3358888.936,727280.7437
5560,Genus,sp29,3029448.744,684764.6631
5561,Genus,sp29,2973759.222,689842.3535
5562,Genus,sp29,2979744.265,696214.8842
5563,Genus,sp29,2977354.447,697664.7652
5564,Genus,sp29,2982135.464,691857.4717
5565,Genus,sp29,2980856.867,692774.3539
5566,Genus,sp29,2973521.47,690122.1013
5567,Genus,sp29,2977109.68,698596.3598
5569,Genus,sp29,2990453.357,697373.7995
5570,Genus,sp29,2975734.185,700223.0247
5571,Genus,sp29,3179806,680692.7913
5572,Genus,sp29,3176719.951,686553.3877
5573,Genus,sp29,2915573.607,715815.1422
5574,Genus,sp29,3307675.814,672789.188
5575,Genus,sp29,2893653.102,722864.5759
5576,Genus,sp29,3359162.389,681185.8661
5577,Genus,sp29,3364096.734,679180.6495
5578,Genus,sp29,3292141.831,687200.9564
5579,Genus,sp29,3295284.652,693101.2487
5580,Genus,sp29,3313662.759,696249.2027
5581,Genus,sp29,3337278.021,696954.4706
5582,Genus,sp29,3377037.474,695251.656
5583,Genus,sp29,3360030.479,701262.9144
5584,Genus,sp29,3374280.116,698006.352
5585,Genus,sp29,3383942.576,700603.7545
5586,Genus,sp29,2952014.09,755521.1017
5587,Genus,sp29,3260986.62,724810.8229
5588,Genus,sp29,3368459.63,732252.695
5632,Genus,sp31,2742927.773,776338.5679
5633,Genus,sp31,2741926.686,781559.0543
5634,Genus,sp31,2737077.467,778087.9372
5635,Genus,sp31,2745210.695,780920.1303
5636,Genus,sp31,2737488.832,776691.587
5637,Genus,sp31,2745386.76,778023.7447
5638,Genus,sp31,2743544.884,783314.2964
5639,Genus,sp31,2741335.418,788295.6707
5640,Genus,sp31,2753528.985,796792.3758
5641,Genus,sp31,2758375.68,789154.5284
5642,Genus,sp31,2753512.893,791127.6367
5681,Genus,sp24,3078637.861,748943.6125
5682,Genus,sp24,3126313.194,771557.3423
5683,Genus,sp24,3138691.102,763766.4364
5684,Genus,sp24,3139600.016,763019.4694
5685,Genus,sp24,3110140.878,783330.4244
5692,Genus,sp27,3407070.299,747058.1461
5693,Genus,sp27,2748390.534,792802.7381
5694,Genus,sp27,2757971.804,773847.0915
5695,Genus,sp27,2757608.349,803809.087
5696,Genus,sp27,2747146.89,771480.8021
5697,Genus,sp27,2731041.687,773227.8029
5698,Genus,sp27,2773431.283,787815.615
5699,Genus,sp27,2754470.276,771550.5707
5700,Genus,sp27,2753035.922,802393.6076
5707,Genus,sp11,3369954.813,748023.367
5708,Genus,sp11,3422505.102,730718.9126
5709,Genus,sp11,2946473.935,747550.8506
5710,Genus,sp11,2915077.09,729519.6129
5711,Genus,sp11,3030385.667,726189.4405
5712,Genus,sp11,2922155.595,735384.7934
5713,Genus,sp11,2898589.902,740325.929
5714,Genus,sp11,2923332.677,737049.4625
5715,Genus,sp11,3420055.296,727224.699
5716,Genus,sp11,2766231.825,768822.728
5717,Genus,sp11,2820637.302,782125.2425
5718,Genus,sp11,3207226.755,683014.4921
5726,Genus,sp23,2917129.567,719998.9441
5727,Genus,sp23,3000649.415,710554.661
5728,Genus,sp23,3363129.869,681203.0445
5729,Genus,sp23,3356873.695,685902.0323
5730,Genus,sp23,3261841.219,720436.7869
5749,Genus,sp30,2590180.176,787704.4957
5757,Genus,sp30,2742510.724,780050.7778
5758,Genus,sp30,2744450.485,794478.8512
5759,Genus,sp30,2749151.427,771733.5622
5760,Genus,sp30,2769667.873,778596.0057
5776,Genus,sp26,3295349.453,702888.8824
5777,Genus,sp29,3369380.452,683392.9862
5778,Genus,sp29,3302256.698,702693.9338
5779,Genus,sp29,2983003.452,695240.6098
5780,Genus,sp29,2975378.773,696498.7502
5781,Genus,sp29,2964626.928,689646.1146
5783,Genus,sp26,3356946.156,727000.0599
5784,Genus,sp26,3353833.268,727818.7486
5785,Genus,sp26,3356188.865,736902.886
5792,Genus,sp21,2923288.304,769903.3094
5793,Genus,sp21,2862143.243,798502.6872
5794,Genus,sp21,2919872.996,722116.0704
5803,Genus,sp1,3288844.232,679550.3533
5804,Genus,sp1,3333697.192,698064.1735
5805,Genus,sp1,3402976.992,699666.0453
5808,Genus,sp12,3425918.829,726248.4928
5809,Genus,sp12,2756363.796,807159.5565
5810,Genus,sp12,3390194.486,702659.6461
5811,Genus,sp12,3165824.68,698183.42
5812,Genus,sp12,2995056.778,712112.5265
5813,Genus,sp12,2621813.256,713557.0202
5814,Genus,sp12,2736778.027,771203.304
5815,Genus,sp12,3006811.056,697609.7598
5816,Genus,sp12,2999500.583,712584.9075
5817,Genus,sp12,2999418.125,709148.1247
5818,Genus,sp12,3001983.379,707961.4085
5819,Genus,sp12,2946513.572,764611.3708
5820,Genus,sp30,2589028.057,739365.8804
5821,Genus,sp30,2653403.065,733603.5867
5843,Genus,sp21,2985660.868,781846.2552
5844,Genus,sp27,3403924.392,752432.2645
5845,Genus,sp27,3408706.277,752723.7888
5846,Genus,sp27,3406053.345,756174.2737
5847,Genus,sp27,3405380.821,754245.9003
5848,Genus,sp1,3403403.52,752173.1303
5867,Genus,sp1,3409079.059,750624.3471
5868,Genus,sp27,3408505.708,756060.8789
5869,Genus,sp18,3242920.682,769315.9198
5872,Genus,sp27,3404195.277,749629.4437
5873,Genus,sp27,2766742.364,783587.9025
5874,Genus,sp27,2767789.984,792153.7778
5876,Genus,sp11,3418434.92,742119.3733
5877,Genus,sp11,3409914.398,746992.8681
5878,Genus,sp11,3366429.901,719532.9228
5879,Genus,sp11,3422088.683,737304.6715
5880,Genus,sp11,3422338.817,737859.7327
5881,Genus,sp11,3405523.469,737492.976
5882,Genus,sp11,3144309.998,693238.4816
5883,Genus,sp11,3396070.455,688837.1496
5884,Genus,sp11,3388665.999,701737.2093
5885,Genus,sp18,3238554.631,770367.9616
5889,Genus,sp23,2882050.828,742080.2279
5890,Genus,sp23,3122540.477,681200.3741
5902,Genus,sp15,3418436.425,713240.6316
5903,Genus,sp15,3421364.331,751500.0366
5906,Genus,sp15,3320757.893,726025.1216
5933,Genus,sp21,3130228.504,679705.9287
5935,Genus,sp1,3359063.266,733499.9046
5936,Genus,sp1,3417828.507,727116.6748
5937,Genus,sp1,3346301.966,707295.4682
5938,Genus,sp1,3413611.837,754980.2737
5939,Genus,sp1,3367053.429,727597.8487
5940,Genus,sp1,3362511.848,736549.1818
5941,Genus,sp12,2769915.264,788870.739
5942,Genus,sp12,2989473.002,755354.6462
5943,Genus,sp12,2745701.046,786594.1187
5944,Genus,sp12,2993916.654,748250.1776
5945,Genus,sp30,2661058.484,731054.0106
5946,Genus,sp30,2662656.603,720229.9216
5955,Genus,sp31,2737309.619,781086.4497
5962,Genus,sp12,2738084.756,778674.2858
5968,Genus,sp11,2818866.419,795538.7028
5969,Genus,sp11,3400563.157,692812.2864
5971,Genus,sp21,2918761.083,710112.6641
5974,Genus,sp12,2736042.011,786399.1153
5977,Genus,sp29,3422009.807,704232.9271
5983,Genus,sp23,2916514.743,720623.6461
5984,Genus,sp23,2915011.413,717418.9969
5985,Genus,sp31,2744031.216,786727.2034
5992,Genus,sp11,3398383.291,732936.0133
5995,Genus,sp23,2918035.792,720505.0667
5996,Genus,sp23,2891459.415,732969.0357
6004,Genus,sp10,3298046.831,755271.06
6008,Genus,sp30,2659306.04,734697.6152
6009,Genus,sp30,3069073.092,714701.3443
6010,Genus,sp30,2660863.174,741492.2606
6011,Genus,sp30,2650904.882,736476.4798
6012,Genus,sp30,2535135.55,788374.947
6013,Genus,sp30,2556383.256,770137.6026
6014,Genus,sp30,2564446.557,757541.88
6015,Genus,sp30,2572836.818,758533.3478
6016,Genus,sp30,2590078.705,730214.3248
6017,Genus,sp30,2577887.482,755153.3523
6018,Genus,sp30,2592128.459,728782.4946
6019,Genus,sp30,2589168.294,729731.5723
6020,Genus,sp30,2595102.234,730051.3482
6021,Genus,sp30,2580703.317,757526.8786
6022,Genus,sp30,2605573.637,749137.6742
6023,Genus,sp30,2589420.174,730404.9909
6024,Genus,sp30,2579721.54,751800.0293
6025,Genus,sp30,2574478.163,767860.9136
6026,Genus,sp30,2577748.324,763230.019
6027,Genus,sp30,2593135.466,748936.2279
6028,Genus,sp30,2579930.31,754364.9791
6029,Genus,sp30,2596285.303,748305.1591
6030,Genus,sp30,2581575.116,758857.9456
6031,Genus,sp30,2590359.168,744515.1694
6032,Genus,sp30,2594713.908,750810.7842
6033,Genus,sp30,2581330.974,759694.8128
6034,Genus,sp30,2579012.975,750800.0716
6035,Genus,sp30,2598601.479,748818.7195
6036,Genus,sp30,2581558.445,764327.3899
6037,Genus,sp30,2579264.658,773426.2024
6038,Genus,sp30,2590366.44,742133.3026
6039,Genus,sp30,2578490.764,760364.7186
6040,Genus,sp12,2621175.057,730567.2636
6041,Genus,sp12,2611422.069,726602.8487
6042,Genus,sp12,2618320.218,717805.2806
6043,Genus,sp12,2609240.989,728341.3886
6044,Genus,sp12,2618054.443,726689.8175
6045,Genus,sp12,2588084.782,736190.849
6046,Genus,sp12,2810269.312,778206.9049
6047,Genus,sp12,2738836.567,779007.7715
6048,Genus,sp12,2758039.115,779705.4724
6049,Genus,sp12,2762642.414,820086.4562
6050,Genus,sp12,2764409.757,775776.2707
6051,Genus,sp12,2733678.486,776564.0079
6052,Genus,sp12,3006069.562,693058.854
6053,Genus,sp12,2758583.437,817692.0601
6054,Genus,sp12,2754835.561,807454.1914
6055,Genus,sp12,2768051.804,789331.6571
6056,Genus,sp12,2760792.367,815507.5102
6057,Genus,sp12,2748390.261,785271.2962
6058,Genus,sp12,2763591.755,806740.8954
6059,Genus,sp12,2748659.994,817218.9553
6060,Genus,sp12,2752210.804,801798.2156
6061,Genus,sp12,3014652.809,694539.6589
6062,Genus,sp12,2738122.761,745040.9834
6063,Genus,sp12,2738003.288,784823.8599
6064,Genus,sp12,2757232.379,773877.6759
6065,Genus,sp12,3012955.15,707562.8958
6066,Genus,sp12,2760468.552,810165.9183
6067,Genus,sp12,2996142.83,707307.1998
6068,Genus,sp12,2998070.88,710846.2535
6069,Genus,sp12,2762455.895,775082.7304
6070,Genus,sp12,2755310.887,765670.7105
6071,Genus,sp21,2756406.488,779840.1961
6072,Genus,sp21,2921065.944,794265.8366
6073,Genus,sp21,2915272.84,794311.5149
6074,Genus,sp21,2812670.234,781971.0154
6106,Genus,sp21,2904140.318,709423.0918
6110,Genus,sp27,3410317.557,701953.2317
6111,Genus,sp27,3011398.282,711219.7229
6112,Genus,sp27,3355133.011,761434.7171
6113,Genus,sp27,2758347.491,806830.6907
6114,Genus,sp27,2762037.433,784522.2686
6115,Genus,sp27,2769727.43,782175.8323
6127,Genus,sp31,2746934.652,788465.1376
6129,Genus,sp31,2745501.731,785528.034
6133,Genus,sp29,2972712.609,709548.777
6134,Genus,sp29,2980155.374,695427.9365
6135,Genus,sp29,3365633.849,700361.5953
6136,Genus,sp26,3356953.885,735053.7474
6175,Genus,sp11,2815292.476,785436.1361
6176,Genus,sp11,2922251.544,727338.4105
6177,Genus,sp11,2907672.855,756414.2357
6211,Genus,sp30,2574868.349,758658.8222
6212,Genus,sp30,2593092.624,732848.7314
6213,Genus,sp12,2603923.668,732714.7586
6222,Genus,sp27,2765765.661,802294.732
6224,Genus,sp28,2715493.578,764406.1156
6226,Genus,sp21,2779386.1,740975.5384
6246,Genus,sp15,3310804.781,729901.8458
6255,Genus,sp23,2997258.772,701781.2638
6256,Genus,sp23,2916007.206,714685.9369
6257,Genus,sp23,2990639.114,689975.6607
6258,Genus,sp23,3006271.749,715821.3172
6267,Genus,sp18,2763518.191,802322.7674
6268,Genus,sp18,3239286.016,770317.1673
6269,Genus,sp15,3391542.858,702238.3479
6270,Genus,sp15,3282693.179,716778.753
6271,Genus,sp18,3241755.181,767648.7977
6272,Genus,sp27,3403268.686,749629.5497
6273,Genus,sp27,2759305.578,807645.643
6274,Genus,sp27,2761400.568,784724.3121
6275,Genus,sp27,2764775.543,785525.3126
6276,Genus,sp23,3001133.597,751386.0378
6277,Genus,sp23,3024334.621,712955.5054
6278,Genus,sp29,3297533.254,688246.0971
6280,Genus,sp24,3144406.659,764051.9565
6295,Genus,sp27,3411321.189,702742.8586
6302,Genus,sp12,2759100.539,797329.789
6303,Genus,sp12,2763595.671,787908.8971
6304,Genus,sp12,2758718.355,806619.5916
6306,Genus,sp12,2739795.244,784223.5866
6307,Genus,sp23,3012898.891,733782.7525
6310,Genus,sp18,3241774.948,765770.951
6312,Genus,sp27,2764397.695,781117.4505
6313,Genus,sp12,2743731.013,786483.4318
6314,Genus,sp11,3037869.195,696293.1796
6317,Genus,sp27,2770831.274,788210.0582
6319,Genus,sp31,2739274.852,787872.5299
6320,Genus,sp31,2743279.176,784234.5056
6321,Genus,sp31,2745940.442,779892.2441
6322,Genus,sp30,2767979.263,785793.668
6327,Genus,sp11,2677376.159,672928.072
6333,Genus,sp11,2826481.164,638938.1425
6334,Genus,sp11,2996421.181,648317.7443
6338,Genus,sp1,3003345.651,648895.9813
6339,Genus,sp23,2977718.707,654177.9124
6340,Genus,sp23,2898977.269,659703.186
6341,Genus,sp23,2962143.087,651015.313
6342,Genus,sp23,3025922.475,652045.9295
6343,Genus,sp23,3087172.578,661140.0875
6344,Genus,sp23,3081007.021,656409.0808
6345,Genus,sp23,3087285.982,668052.997
6346,Genus,sp23,3087846.135,664355.9412
6347,Genus,sp23,3000616.733,671896.2143
6348,Genus,sp23,3015724.062,676394.3714
6349,Genus,sp23,3063379.529,670384.9532
6350,Genus,sp23,3015041.454,675182.4473
6351,Genus,sp23,3063906.024,673854.6729
6352,Genus,sp23,3096666.206,670829.0608
6353,Genus,sp23,3087987.219,675521.4462
6354,Genus,sp23,3034511.541,686898.5625
6355,Genus,sp23,3011829.737,687361.8848
6356,Genus,sp23,3027147.471,685493.6359
6460,Genus,sp29,3128651.25,627560.7732
6461,Genus,sp29,3126897.619,624342.204
6462,Genus,sp29,2993446.515,669992.8036
6463,Genus,sp29,2991411.027,670215.9567
6464,Genus,sp29,2990255.028,670794.5158
6465,Genus,sp29,2988915.387,666829.4096
6466,Genus,sp29,3139000.484,665510.6736
6467,Genus,sp29,3024024.125,680214.5981
6468,Genus,sp29,3014773.247,682014.7184
6469,Genus,sp29,3028885.74,684689.0178
6470,Genus,sp30,2991708.586,665951.7446
6471,Genus,sp30,2735200.29,696384.5811
6477,Genus,sp11,3074824.1,601197.7427
6478,Genus,sp11,2781848.312,647078.2257
6488,Genus,sp29,2985954.704,673055.4478
6497,Genus,sp12,3031219.158,652160.192
6498,Genus,sp12,2643117.857,702085.1789
6499,Genus,sp12,2652533.868,700847.8814
6500,Genus,sp30,2812069.661,652551.2532
6501,Genus,sp30,3078414.135,606499.0822
6502,Genus,sp30,3015478.348,678318.3812
6503,Genus,sp30,2983650.029,671245.3063
6504,Genus,sp30,2793311.573,636246.2807
6505,Genus,sp30,2663289.384,685995.0776
6506,Genus,sp30,2659416.397,701778.2711
6507,Genus,sp30,2985236.524,670408.1196
6508,Genus,sp30,2984891.362,670416.4478
6509,Genus,sp30,2986891.784,675520.1253
6520,Genus,sp11,2847624.64,639190.0821
6527,Genus,sp30,2673766.717,668126.4631
6528,Genus,sp30,2860811.673,650236.4187
6529,Genus,sp30,2674358.996,664592.2286
6530,Genus,sp30,2677946.9,670911.3654
6534,Genus,sp30,2648098.46,698004.8476
6535,Genus,sp30,2621376.307,712987.0048
6536,Genus,sp30,2656149.728,717892.4739
6537,Genus,sp30,2865564.774,631037.9715
6538,Genus,sp30,2818816.064,659027.6982
6539,Genus,sp30,2678678.102,695081.7864
6540,Genus,sp30,2988415.677,674195.9601
6541,Genus,sp30,2988451.013,675378.0534
6542,Genus,sp30,2682116.701,685418.4693
6543,Genus,sp30,2611394.473,713770.6276
6544,Genus,sp30,2604697.27,707530.2806
6545,Genus,sp30,2600947.121,716064.7751
6546,Genus,sp30,2605164.074,712791.4504
6547,Genus,sp30,2592993.88,706544.3896
6548,Genus,sp30,2613834.425,712822.6993
6549,Genus,sp30,2596391.805,710527.0767
6550,Genus,sp30,2591718.787,707258.2995
6551,Genus,sp12,2619785.623,712806.4478
6552,Genus,sp12,2617469.31,709591.7946
6553,Genus,sp12,3128553.655,677366.6063
6554,Genus,sp12,2653975.719,701633.0702
6555,Genus,sp12,3027077.552,652556.1052
6556,Genus,sp12,2648493.162,690395.3091
6557,Genus,sp12,2629823.078,714461.2502
6558,Genus,sp12,2908528.22,657098.111
6559,Genus,sp12,2620731.306,712033.8101
6564,Genus,sp29,3106026.607,635902.4784
6573,Genus,sp11,2907272.816,655695.1983
6574,Genus,sp11,3057326.068,590524.0869
6575,Genus,sp11,3123115.076,669818.8173
6576,Genus,sp11,2833248.233,623747.7683
6585,Genus,sp30,2984436.97,673706.6655
6594,Genus,sp11,3102150.68,674135.9199
6595,Genus,sp11,3096014.998,673253.3354
6596,Genus,sp23,3097952.954,675297.6941
6597,Genus,sp23,3104649.489,673814.3133
6600,Genus,sp30,2981062.227,666068.8832
6601,Genus,sp12,2904118.52,653734.8267
6606,Genus,sp30,2849908.477,648889.9069
6607,Genus,sp30,2675977.535,662405.7381
6608,Genus,sp23,3208319.378,464112.7287
6615,Genus,sp23,3200377.987,461830.7701
6617,Genus,sp30,3080569.655,556359.0496
6624,Genus,sp11,3085443.945,566440.7746
6625,Genus,sp11,3157211.172,510743.2859
6627,Genus,sp11,3166491.805,508202.2981
6631,Genus,sp23,3232653.291,333626.1961
6632,Genus,sp23,3227114.661,326473.0272
6641,Genus,sp30,3208605.882,357797.2306
6644,Genus,sp11,3236936.971,437954.9547
6645,Genus,sp11,2918642.854,365880.6444
6648,Genus,sp23,3213778.693,440060.1054
6649,Genus,sp23,3231633.306,332680.0302
6650,Genus,sp30,3228738.03,390136.998
6651,Genus,sp30,3207590.887,355543.8724
6654,Genus,sp11,3191408.567,333144.8122
6655,Genus,sp11,2986100.771,352998.8226
6661,Genus,sp11,2994388.951,354048.6789
6662,Genus,sp30,3213178.622,391537.3391
6663,Genus,sp11,2994232.451,357235.479
6664,Genus,sp11,3231726.203,435481.8947
6665,Genus,sp23,3121189.05,285058.0681
6666,Genus,sp23,3098462.429,293955.7778
6667,Genus,sp23,3138539.016,296773.5912
6668,Genus,sp23,3223259.047,287669.5506
6669,Genus,sp23,3126380.755,309967.4264
6670,Genus,sp23,3086019.388,324167.436
6671,Genus,sp23,3083047.955,325408.5362
6672,Genus,sp23,3228275.169,322740.6639
6682,Genus,sp29,3152260.5,334194.5263
6683,Genus,sp11,3193670.072,306373.9048
6685,Genus,sp23,3056495.078,289280.1292
6699,Genus,sp21,3209492.575,222232.3008
6700,Genus,sp30,3099709.231,327980.8938
6701,Genus,sp30,3094857.629,328088.7366
6702,Genus,sp11,3082307.212,328102.7543
6707,Genus,sp23,3110716.3,323880.5577
6708,Genus,sp23,3215228.757,230603.0736
6709,Genus,sp30,3091330.728,311201.2048
6710,Genus,sp23,2951310.616,288656.0391
6711,Genus,sp30,3140780.23,300619.1828
6718,Genus,sp11,2994936.89,336651.8169
6719,Genus,sp11,3214371.66,226206.3196
6720,Genus,sp30,3169667.829,246781.7054
6721,Genus,sp30,3094278.132,326767.3425
6722,Genus,sp30,3139409.18,284835.0078
6725,Genus,sp23,3152129.003,234969.9523
6726,Genus,sp30,3094703.536,312251.0804
6727,Genus,sp29,3154386.497,331674.5173
6728,Genus,sp11,3212349.824,219518.1386
6731,Genus,sp23,3111807.103,118412.206
6732,Genus,sp23,3111322.26,123144.7929
6733,Genus,sp23,3113325.062,120155.4883
6734,Genus,sp23,3118973.95,119132.1112
6735,Genus,sp23,3122284.779,125497.0528
6736,Genus,sp23,3124664.863,126927.7064
6737,Genus,sp23,3214172.269,194437.6088
6738,Genus,sp30,3211801.216,197744.3747
6739,Genus,sp23,3168721.739,215077.9194
6750,Genus,sp21,3134741.192,210359.1253
6751,Genus,sp11,3171784.059,107032.8007
6752,Genus,sp11,3157282.84,124733.0717
6753,Genus,sp11,3163038.653,129672.4607
6754,Genus,sp11,3120367.736,131461.9584
6755,Genus,sp23,3021702.203,228189.3878
6756,Genus,sp23,3084242.741,154274.4518
6757,Genus,sp23,3082164.393,156533.046
6758,Genus,sp23,3191145.945,198271.4813
6759,Genus,sp23,3161082.63,128979.2208
6767,Genus,sp21,3116897.336,127730.9717
6768,Genus,sp21,3121005.229,129514.5359
6769,Genus,sp30,3160074.244,120577.5665
6772,Genus,sp11,3206855.244,189958.0146
6777,Genus,sp30,3210942.704,199795.9416
6778,Genus,sp21,3134598.889,107117.2984
6779,Genus,sp21,3131273.343,121865.7487
6781,Genus,sp11,3173448.916,103567.7645
6782,Genus,sp11,3170710.567,219239.1815
6783,Genus,sp11,3132979.948,112420.6494
6784,Genus,sp30,3034168.838,122701.3505
6786,Genus,sp21,3125857.353,128319.2978
6787,Genus,sp23,3123478.731,131438.6307
6788,Genus,sp23,3132156.535,115965.2731
6789,Genus,sp23,3122780.484,125130.0625
6790,Genus,sp11,3065329.005,152593.2413
6791,Genus,sp30,3208970.031,196803.5132
6797,Genus,sp23,3083351.704,63126.21857
6798,Genus,sp23,3082083.004,63982.23616
6799,Genus,sp23,3085636.917,66810.94521
6800,Genus,sp23,3089145.853,61878.42582
6801,Genus,sp23,3081121.896,59483.5448
6802,Genus,sp23,3162645.078,90634.38813
6803,Genus,sp23,3163801.888,84968.04777
6816,Genus,sp11,3161011.017,91930.26873
6817,Genus,sp11,2996188.307,88737.21139
6819,Genus,sp23,3160455.023,91713.31749
6820,Genus,sp23,3090993.059,77950.44446
6821,Genus,sp23,3093837.943,108447.2166
6822,Genus,sp23,3083607.57,61232.64767
6827,Genus,sp30,3171762.16,69014.47025
6828,Genus,sp21,3117459.609,112224.9934
6829,Genus,sp11,3080099.517,40614.47671
6830,Genus,sp23,3172193.117,92340.99534
6832,Genus,sp11,3170311.813,89598.31442

@@ LABEL_PROPERTIES_DATA
Element,Axis_0,Axis_1,LBPROP1,LBPROP2,LBPROP3,LBPROP4
Genus:sp1,Genus,sp1,0.640625,0.640625,23,23
Genus:sp10,Genus,sp10,0.816993464052288,0.816993464052288,28,28
Genus:sp11,Genus,sp11,0.850609756097561,0.850609756097561,49,49
Genus:sp12,Genus,sp12,0.80794701986755,0.80794701986755,29,29
Genus:sp13,Genus,sp13,0.888888888888889,0.888888888888889,3,3
Genus:sp14,Genus,sp14,0.571428571428571,0.571428571428571,3,3
Genus:sp15,Genus,sp15,0.722222222222222,0.722222222222222,15,15
Genus:sp16,Genus,sp16,0.9,0.9,2,2
Genus:sp17,Genus,sp17,0.611111111111111,0.611111111111111,7,7
Genus:sp18,Genus,sp18,0.759493670886076,0.759493670886076,19,19
Genus:sp19,Genus,sp19,0.878048780487805,0.878048780487805,5,5
Genus:sp2,Genus,sp2,0.676470588235294,0.676470588235294,11,11
Genus:sp20,Genus,sp20,0.709677419354839,0.709677419354839,9,9
Genus:sp21,Genus,sp21,0.861111111111111,0.861111111111111,25,25
Genus:sp22,Genus,sp22,0.95,0.95,1,1
Genus:sp23,Genus,sp23,0.85632183908046,0.85632183908046,25,25
Genus:sp24,Genus,sp24,0.782608695652174,0.782608695652174,5,5
Genus:sp25,Genus,sp25,0.666666666666667,0.666666666666667,3,3
Genus:sp26,Genus,sp26,0.571428571428571,0.571428571428571,3,3
Genus:sp27,Genus,sp27,0.861111111111111,0.861111111111111,5,5
Genus:sp28,Genus,sp28,0.8,0.8,1,1
Genus:sp29,Genus,sp29,0.773584905660377,0.773584905660377,12,12
Genus:sp3,Genus,sp3,0.5,0.5,15,15
Genus:sp30,Genus,sp30,0.796116504854369,0.796116504854369,21,21
Genus:sp31,Genus,sp31,0.944444444444444,0.944444444444444,1,1
Genus:sp4,Genus,sp4,0.333333333333333,0.333333333333333,4,4
Genus:sp5,Genus,sp5,0.736842105263158,0.736842105263158,10,10
Genus:sp6,Genus,sp6,0.454545454545455,0.454545454545455,6,6
Genus:sp7,Genus,sp7,0.25,0.25,6,6
Genus:sp8,Genus,sp8,0.6,0.6,4,4
Genus:sp9,Genus,sp9,0.736842105263158,0.736842105263158,15,15

@@ LABEL_PROPERTIES_DATA_EXTRA
Element,Axis_0,Axis_1,xLBPROP1,xLBPROP2,xLBPROP3,xLBPROP4
Genus:sp1,Genus,sp1,0.640625,0.640625,23,23
Genus:sp10,Genus,sp10,0.816993464052288,0.816993464052288,28,28
Genus:sp11,Genus,sp11,0.850609756097561,0.850609756097561,49,49
Genus:sp12,Genus,sp12,0.80794701986755,0.80794701986755,29,29
Genus:sp13,Genus,sp13,0.888888888888889,0.888888888888889,3,3
Genus:sp14,Genus,sp14,0.571428571428571,0.571428571428571,3,3
Genus:sp15,Genus,sp15,0.722222222222222,0.722222222222222,15,15
Genus:sp16,Genus,sp16,0.9,0.9,2,2
Genus:sp17,Genus,sp17,0.611111111111111,0.611111111111111,7,7
Genus:sp18,Genus,sp18,0.759493670886076,0.759493670886076,19,19
Genus:sp19,Genus,sp19,0.878048780487805,0.878048780487805,5,5
Genus:sp2,Genus,sp2,0.676470588235294,0.676470588235294,11,11
Genus:sp20,Genus,sp20,0.709677419354839,0.709677419354839,9,9
Genus:sp21,Genus,sp21,0.861111111111111,0.861111111111111,25,25
Genus:sp22,Genus,sp22,0.95,0.95,1,1

@@ LABEL_PROPERTIES_DATA_BINOMIAL
Element,Axis_0,Axis_1,bLBPROP1,bLBPROP2,bLBPROP3,bLBPROP4,bLBPROP5
Genus:sp1,Genus,sp1,0,10,1,10,1
Genus:sp10,Genus,sp10,1,12,1,10,1
Genus:sp11,Genus,sp11,1,12,1,10,1
Genus:sp12,Genus,sp12,1,12,1,10,1
Genus:sp13,Genus,sp13,1,12,0,12,1
Genus:sp14,Genus,sp14,0,10,0,12,1
Genus:sp15,Genus,sp15,1,12,1,10,1
Genus:sp16,Genus,sp16,1,12,0,12,1
Genus:sp17,Genus,sp17,0,10,0,12,1
Genus:sp18,Genus,sp18,1,12,1,10,1
Genus:sp19,Genus,sp19,1,12,0,12,1
Genus:sp2,Genus,sp2,0,10,1,10,1
Genus:sp20,Genus,sp20,1,12,0,12,1
Genus:sp21,Genus,sp21,1,12,1,10,1
Genus:sp22,Genus,sp22,1,12,0,12,1
Genus:sp23,Genus,sp23,1,12,1,10,1
Genus:sp24,Genus,sp24,1,12,0,12,1
Genus:sp25,Genus,sp25,0,10,0,12,1
Genus:sp26,Genus,sp26,0,10,0,12,1
Genus:sp27,Genus,sp27,1,12,0,12,1
Genus:sp28,Genus,sp28,1,12,0,12,1
Genus:sp29,Genus,sp29,1,12,1,10,1
Genus:sp3,Genus,sp3,0,10,1,10,1
Genus:sp30,Genus,sp30,1,12,1,10,1
Genus:sp31,Genus,sp31,1,12,0,12,1
Genus:sp4,Genus,sp4,0,10,0,12,1
Genus:sp5,Genus,sp5,1,12,0,12,1
Genus:sp6,Genus,sp6,0,10,0,12,1
Genus:sp7,Genus,sp7,0,10,0,12,1


@@ GROUP_PROPERTIES_DATA
Element,Axis_0,Axis_1,PROP1,PROP2,PROP3
1950000:1350000,1950000,1350000,305.458528951487,279,76
1950000:1450000,1950000,1450000,262.864,204,117
2050000:1250000,2050000,1250000,367.587438158744,328,118
2050000:1350000,2050000,1350000,295.385760869565,233,140
2150000:1050000,2150000,1050000,507.334341906203,404,173
2150000:1150000,2150000,1150000,428.160725532183,340,253
2150000:1250000,2150000,1250000,346.7868,288,143
2250000:1050000,2250000,1050000,461.523076923077,391,124
2250000:1250000,2250000,1250000,312.665088161209,228,195
2250000:950000,2250000,950000,691.305729984301,554,265
2350000:1050000,2350000,1050000,433.118717504333,371,413
2350000:1150000,2350000,1150000,386.180493983534,329,246
2350000:1250000,2350000,1250000,354.549557078389,225,421
2350000:950000,2350000,950000,586.853176272613,485,407
2450000:1050000,2450000,1050000,531.619406950792,285,785
2450000:1150000,2450000,1150000,410.9113,213,473
2450000:1250000,2450000,1250000,364.1505,205,401
2450000:950000,2450000,950000,481.44337735094,395,433
2550000:1050000,2550000,1050000,323.9524,259,153
2550000:750000,2550000,750000,725.784509046554,627,210
2550000:850000,2550000,850000,591.4786976519,499,206
2550000:950000,2550000,950000,469.107522485691,369,202
2650000:650000,2650000,650000,807.594871794872,735,175
2650000:750000,2650000,750000,704.070152417483,563,290
2650000:850000,2650000,850000,530.8264,395,252
2650000:950000,2650000,950000,383.4961,319,176
2750000:650000,2750000,650000,773.275552898984,615,424
2750000:750000,2750000,750000,657.9491,542,758
2750000:850000,2750000,850000,464.3711,365,625
2750000:950000,2750000,950000,344.1619,313,82
2850000:650000,2850000,650000,807.103004822555,509,1340
2850000:750000,2850000,750000,651.1892,490,660
2950000:250000,2950000,250000,2261.53066976127,1382,1976
2950000:350000,2950000,350000,1473.93450064851,868,1258
2950000:50000,2950000,50000,2251.50188679245,2140,566
2950000:650000,2950000,650000,692.807954235903,470,808
2950000:750000,2950000,750000,709.232024834769,464,804
3050000:150000,3050000,150000,1544.459,486,2488
3050000:250000,3050000,250000,1462.8129,655,2314
3050000:350000,3050000,350000,1132.39254385965,753,1467
3050000:50000,3050000,50000,1717.79539323511,756,1829
3050000:550000,3050000,550000,1019.15641609719,848,577
3050000:650000,3050000,650000,1062.74558604552,752,1082
3050000:750000,3050000,750000,1142.2566,626,1222
3050000:850000,3050000,850000,618.6471,416,929
3150000:150000,3150000,150000,664.696877590495,445,872
3150000:250000,3150000,250000,868.0972,451,1289
3150000:2950000,3150000,2950000,818.4245,737,662
3150000:350000,3150000,350000,959.791016159956,509,1301
3150000:50000,3150000,50000,957.274678111588,589,776
3150000:550000,3150000,550000,790.71144278607,704,314
3150000:650000,3150000,650000,728.362840710178,572,889
3150000:750000,3150000,750000,1193.0925,685,1811
3150000:850000,3150000,850000,952.8781,506,2075
3250000:150000,3250000,150000,718.461538461538,645,246
3250000:2150000,3250000,2150000,545.6689,489,145
3250000:250000,3250000,250000,908.404375441073,649,981
3250000:2850000,3250000,2850000,1887.28772852193,758,3033
3250000:2950000,3250000,2950000,2205.74605489988,823,5490
3250000:3050000,3250000,3050000,1991.3737280296,882,2715
3250000:350000,3250000,350000,836.946658097686,631,744
3250000:450000,3250000,450000,803.22351233672,689,498
3250000:650000,3250000,650000,802.786286112078,644,537
3250000:750000,3250000,750000,893.0139,603,1621
3250000:850000,3250000,850000,1168.8379,627,2036
3250000:950000,3250000,950000,815.0213,511,1156
3350000:1050000,3350000,1050000,690.0454,603,322
3350000:1150000,3350000,1150000,688.3304,536,491
3350000:1250000,3350000,1250000,580.6322,496,238
3350000:1350000,3350000,1350000,517.7449,445,396
3350000:2050000,3350000,2050000,619.497,546,313
3350000:2150000,3350000,2150000,612.0213,545,314
3350000:650000,3350000,650000,1038.1238238615,885,404
3350000:750000,3350000,750000,896.6634,535,1212
3350000:850000,3350000,850000,771.8167,495,1315
3350000:950000,3350000,950000,893.2959,604,1056
3450000:1050000,3450000,1050000,820.4313,654,653
3450000:1150000,3450000,1150000,777.8107,620,725
3450000:1250000,3450000,1250000,659.1251,567,279
3450000:1350000,3450000,1350000,655.4844,559,413
3450000:1450000,3450000,1450000,609.9983,517,255
3450000:1550000,3450000,1550000,525.1265,462,146
3450000:2050000,3450000,2050000,689.9861,601,272
3450000:2150000,3450000,2150000,645.3851,590,205
3450000:650000,3450000,650000,972.262820512821,901,264
3450000:750000,3450000,750000,926.914788097385,745,523
3450000:850000,3450000,850000,1000.98301850792,798,519
3450000:950000,3450000,950000,891.446663163426,636,754
3550000:1050000,3550000,1050000,1035.00418474892,731,1233
3550000:1150000,3550000,1150000,945.444827236802,623,791
3550000:1250000,3550000,1250000,681.1956,560,520
3550000:1450000,3550000,1450000,673.7934,563,668
3550000:1550000,3550000,1550000,652.0044,530,494
3550000:1950000,3550000,1950000,638.7822,585,111
3550000:2050000,3550000,2050000,702.8714,621,173
3550000:2150000,3550000,2150000,691.4374,605,237
3550000:2250000,3550000,2250000,648.6491,582,303
3550000:950000,3550000,950000,1336.23845108696,1037,968
3650000:1150000,3650000,1150000,1084.59012875536,735,754
3650000:1250000,3650000,1250000,1105.70090180361,667,1009
3650000:1350000,3650000,1350000,926.1888,673,820
3650000:1450000,3650000,1450000,787.0562,665,376
3650000:1550000,3650000,1550000,759.4725,633,403
3650000:1650000,3650000,1650000,638.4128,566,303
3650000:1750000,3650000,1750000,628.3115,565,115
3650000:1850000,3650000,1850000,644.8689,606,143
3650000:1950000,3650000,1950000,686.9691,636,135
3650000:2050000,3650000,2050000,682.8884,612,474
3650000:2350000,3650000,2350000,994.278147268409,782,710
3750000:1250000,3750000,1250000,1294.8046875,1050,896
3750000:1350000,3750000,1350000,1350.35778091208,874,1153
3750000:1450000,3750000,1450000,1227.79678714859,737,1594
3750000:1550000,3750000,1550000,1032.2248,693,792
3750000:1650000,3750000,1650000,880.0448,641,952
3750000:1750000,3750000,1750000,775.5409,622,658
3750000:1850000,3750000,1850000,792.4572,617,470
3750000:1950000,3750000,1950000,774.2368,697,393
3750000:2050000,3750000,2050000,933.379793731851,658,756
3750000:2150000,3750000,2150000,1005.10770767438,836,614
3850000:1350000,3850000,1350000,,,
3850000:1450000,3850000,1450000,1396.84166666667,1014,842
3850000:1550000,3850000,1550000,1260.3562414734,1012,807
3850000:1650000,3850000,1650000,1371.33847603345,816,2161
3850000:1750000,3850000,1750000,1112.5979518553,798,904
3850000:1850000,3850000,1850000,1348.12505069623,884,1108
3850000:1950000,3850000,1950000,1162.03694220922,881,734
3950000:1750000,3950000,1750000,1587.8,1527,96


@@ NUMERIC_LABEL_SITE_DATA
Axis_0	Axis_1	Key	Value
3150000	1050000	388	5
3150000	1050000	389	5
3150000	1050000	390	5
3150000	1050000	391	9
3150000	1050000	392	4
3150000	1050000	393	21
3150000	1050000	394	27
3150000	1050000	395	28
3150000	1050000	396	26
3150000	1050000	397	36
3150000	1050000	398	52
3150000	1050000	399	50
3150000	1050000	400	53
3150000	1050000	401	91
3150000	1050000	402	113
3150000	1050000	403	139
3150000	1050000	404	118
3150000	1050000	405	118
3150000	1050000	406	120
3150000	1050000	407	118
3150000	1050000	408	94
3150000	1050000	409	101
3150000	1050000	410	96
3150000	1050000	411	96
3150000	1050000	412	96
3150000	1050000	413	94
3150000	1050000	414	94
3150000	1050000	415	130
3150000	1050000	416	110
3150000	1050000	417	122
3150000	1050000	418	127
3150000	1050000	419	121
3150000	1050000	420	126
3150000	1050000	421	121
3150000	1050000	422	134
3150000	1050000	423	121
3150000	1050000	424	105
3150000	1050000	425	119
3150000	1050000	426	92
3150000	1050000	427	109
3150000	1050000	428	102
3150000	1050000	429	87
3150000	1050000	430	96
3150000	1050000	431	95
3150000	1050000	432	96
3150000	1050000	433	91
3150000	1050000	434	106
3150000	1050000	435	107
3150000	1050000	436	112
3150000	1050000	437	100
3150000	1050000	438	108
3150000	1050000	439	97
3150000	1050000	440	116
3150000	1050000	441	125
3150000	1050000	442	109
3150000	1050000	443	126
3150000	1050000	444	136
3150000	1050000	445	120
3150000	1050000	446	144
3150000	1050000	447	125
3150000	1050000	448	122
3150000	1050000	449	126
3150000	1050000	450	121
3150000	1050000	451	131
3150000	1050000	452	148
3150000	1050000	453	148
3150000	1050000	454	152
3150000	1050000	455	120
3150000	1050000	456	108
3150000	1050000	457	129
3150000	1050000	458	118
3150000	1050000	459	108
3150000	1050000	460	95
3150000	1050000	461	93
3150000	1050000	462	83
3150000	1050000	463	91
3150000	1050000	464	92
3150000	1050000	465	84
3150000	1050000	466	89
3150000	1050000	467	97
3150000	1050000	468	98
3150000	1050000	469	92
3150000	1050000	470	107
3150000	1050000	471	117
3150000	1050000	472	104
3150000	1050000	473	124
3150000	1050000	474	79
3150000	1050000	475	114
3150000	1050000	476	84
3150000	1050000	477	80
3150000	1050000	478	77
3150000	1050000	479	85
3150000	1050000	480	74
3150000	1050000	481	68
3150000	1050000	482	65
3150000	1050000	483	56
3150000	1050000	484	51
3150000	1050000	485	42
3150000	1050000	486	54
3150000	1050000	487	40
3150000	1050000	488	34
3150000	1050000	489	41
3150000	1050000	490	20
3150000	1050000	491	28
3150000	1050000	492	16
3150000	1050000	493	25
3150000	1050000	494	24
3150000	1050000	495	23
3150000	1050000	496	25
3150000	1050000	497	17
3150000	1050000	498	14
3150000	1050000	499	19
3150000	1050000	500	20
3150000	1050000	501	18
3150000	1050000	502	16
3150000	1050000	503	15
3150000	1050000	504	19
3150000	1050000	505	18
3150000	1050000	506	15
3150000	1050000	507	10
3150000	1050000	508	7
3150000	1050000	509	11
3150000	1050000	510	10
3150000	1050000	511	6
3150000	1050000	512	7
3150000	1050000	513	17
3150000	1050000	514	12
3150000	1050000	515	8
3150000	1050000	516	11
3150000	1050000	517	5
3150000	1050000	518	10
3150000	1050000	519	5
3150000	1050000	520	5
3150000	1050000	521	5
3150000	1050000	522	5
3150000	1050000	523	4
3150000	1050000	524	7
3150000	1050000	525	7
3150000	1050000	527	3
3150000	1050000	528	3
3150000	1050000	529	1
3150000	1050000	530	5
3150000	1050000	531	5
3150000	1050000	532	1
3150000	1050000	533	1
3150000	1050000	534	2
3150000	1050000	535	2
3150000	1050000	536	4
3150000	1050000	539	2
3150000	1050000	541	1
3150000	1050000	545	1
3150000	650000	1000	2
3150000	650000	1001	3
3150000	650000	1002	1
3150000	650000	1003	1
3150000	650000	1004	4
3150000	650000	1005	3
3150000	650000	1006	2
3150000	650000	1007	1
3150000	650000	1009	4
3150000	650000	1010	3
3150000	650000	1011	1
3150000	650000	1012	5
3150000	650000	1013	2
3150000	650000	1014	4
3150000	650000	1015	6
3150000	650000	1016	3
3150000	650000	1018	2
3150000	650000	1019	3
3150000	650000	1020	2
3150000	650000	1021	2
3150000	650000	1022	1
3150000	650000	1023	1
3150000	650000	1024	2
3150000	650000	1025	1
3150000	650000	1026	2
3150000	650000	1027	4
3150000	650000	1028	1
3150000	650000	1029	2
3150000	650000	1031	3
3150000	650000	1033	3
3150000	650000	1034	2
3150000	650000	1035	3
3150000	650000	1036	4
3150000	650000	1037	3
3150000	650000	1038	3
3150000	650000	1039	3
3150000	650000	1040	2
3150000	650000	1041	6
3150000	650000	1042	9
3150000	650000	1044	4
3150000	650000	1045	1
3150000	650000	1046	1
3150000	650000	1049	6
3150000	650000	1050	3
3150000	650000	1051	1
3150000	650000	1052	2
3150000	650000	1053	5
3150000	650000	1054	4
3150000	650000	1055	1
3150000	650000	1056	1
3150000	650000	1057	4
3150000	650000	1058	2
3150000	650000	1059	2
3150000	650000	1060	3
3150000	650000	1061	1
3150000	650000	1062	5
3150000	650000	1063	2
3150000	650000	1064	3
3150000	650000	1065	4
3150000	650000	1066	2
3150000	650000	1067	5
3150000	650000	1068	3
3150000	650000	1069	6
3150000	650000	1070	7
3150000	650000	1071	3
3150000	650000	1072	4
3150000	650000	1073	3
3150000	650000	1074	5
3150000	650000	1075	4
3150000	650000	1076	1
3150000	650000	1078	2
3150000	650000	1079	1
3150000	650000	1080	1
3150000	650000	1082	2
3150000	650000	1083	1
3150000	650000	1084	2
3150000	650000	1085	1
3150000	650000	1086	3
3150000	650000	1087	1
3150000	650000	1088	1
3150000	650000	1089	3
3150000	650000	1090	1
3150000	650000	1092	2
3150000	650000	1093	3
3150000	650000	1094	2
3150000	650000	1095	3
3150000	650000	1096	7
3150000	650000	1097	5
3150000	650000	1098	6
3150000	650000	1099	1
3150000	650000	1100	4
3150000	650000	1101	2
3150000	650000	1102	3
3150000	650000	1103	3
3150000	650000	1104	6
3150000	650000	1105	3
3150000	650000	1106	2
3150000	650000	1107	1
3150000	650000	1108	2
3150000	650000	1109	3
3150000	650000	1110	2
3150000	650000	1111	1
3150000	650000	1112	1
3150000	650000	1113	4
3150000	650000	1115	2
3150000	650000	1116	2
3150000	650000	1118	6
3150000	650000	1120	2
3150000	650000	1121	2
3150000	650000	1122	4
3150000	650000	1123	2
3150000	650000	1124	1
3150000	650000	1125	1
3150000	650000	1127	1
3150000	650000	1129	1
3150000	650000	1130	2
3150000	650000	1131	2
3150000	650000	1132	4
3150000	650000	1136	4
3150000	650000	1137	1
3150000	650000	1138	3
3150000	650000	1139	1
3150000	650000	1140	4
3150000	650000	1141	4
3150000	650000	1142	4
3150000	650000	1143	4
3150000	650000	1144	1
3150000	650000	1145	1
3150000	650000	1146	4
3150000	650000	1147	1
3150000	650000	1148	2
3150000	650000	1150	2
3150000	650000	1151	3
3150000	650000	1152	4
3150000	650000	1153	4
3150000	650000	1154	2
3150000	650000	1155	1
3150000	650000	1156	4
3150000	650000	1157	2
3150000	650000	1158	4
3150000	650000	1159	1
3150000	650000	1161	3
3150000	650000	1163	2
3150000	650000	1165	3
3150000	650000	1166	2
3150000	650000	1167	1
3150000	650000	1168	1
3150000	650000	1169	1
3150000	650000	1170	1
3150000	650000	1171	2
3150000	650000	1172	1
3150000	650000	1173	1
3150000	650000	1174	2
3150000	650000	1175	3
3150000	650000	1177	1
3150000	650000	1178	7
3150000	650000	1179	1
3150000	650000	1180	2
3150000	650000	1185	2
3150000	650000	1186	1
3150000	650000	1188	2
3150000	650000	1189	2
3150000	650000	1190	2
3150000	650000	1192	1
3150000	650000	1193	1
3150000	650000	1194	1
3150000	650000	1195	4
3150000	650000	1198	3
3150000	650000	1200	1
3150000	650000	1201	2
3150000	650000	1203	1
3150000	650000	1204	1
3150000	650000	1205	1
3150000	650000	1207	2
3150000	650000	1210	2
3150000	650000	1213	1
3150000	650000	1214	2
3150000	650000	1216	1
3150000	650000	1218	4
3150000	650000	1219	1
3150000	650000	1223	1
3150000	650000	1224	1
3150000	650000	1226	1
3150000	650000	1227	1
3150000	650000	1228	1
3150000	650000	1229	3
3150000	650000	1232	2
3150000	650000	1233	2
3150000	650000	1235	1
3150000	650000	1236	1
3150000	650000	1241	4
3150000	650000	1242	2
3150000	650000	1243	1
3150000	650000	1244	2
3150000	650000	1246	1
3150000	650000	1248	1
3150000	650000	1249	1
3150000	650000	1251	2
3150000	650000	1257	3
3150000	650000	1258	1
3150000	650000	1261	2
3150000	650000	1262	2
3150000	650000	1265	1
3150000	650000	1268	3
3150000	650000	1270	2
3150000	650000	1274	1
3150000	650000	1277	3
3150000	650000	1278	1
3150000	650000	1279	2
3150000	650000	1280	3
3150000	650000	1288	1
3150000	650000	1292	2
3150000	650000	1295	1
3150000	650000	1297	1
3150000	650000	1301	3
3150000	650000	1302	1
3150000	650000	1306	1
3150000	650000	1308	1
3150000	650000	1309	1
3150000	650000	1310	2
3150000	650000	1311	1
3150000	650000	1312	2
3150000	650000	1318	2
3150000	650000	1322	2
3150000	650000	1325	1
3150000	650000	1326	1
3150000	650000	1328	1
3150000	650000	1330	1
3150000	650000	1331	2
3150000	650000	1333	1
3150000	650000	1351	1
3150000	650000	1353	1
3150000	650000	1355	1
3150000	650000	1364	1
3150000	650000	1375	1
3150000	650000	1382	6
3150000	650000	1393	1
3150000	650000	1397	2
3150000	650000	1402	1
3150000	650000	1405	2
3150000	650000	1407	1
3150000	650000	1413	1
3150000	650000	1421	1
3150000	650000	1461	1
3150000	650000	572	3
3150000	650000	573	1
3150000	650000	574	6
3150000	650000	575	9
3150000	650000	576	12
3150000	650000	577	5
3150000	650000	578	10
3150000	650000	579	20
3150000	650000	580	20
3150000	650000	581	26
3150000	650000	582	29
3150000	650000	583	27
3150000	650000	584	20
3150000	650000	585	33
3150000	650000	586	38
3150000	650000	587	39
3150000	650000	588	32
3150000	650000	589	35
3150000	650000	590	36
3150000	650000	591	38
3150000	650000	592	49
3150000	650000	593	40
3150000	650000	594	50
3150000	650000	595	55
3150000	650000	596	43
3150000	650000	597	36
3150000	650000	598	45
3150000	650000	599	48
3150000	650000	600	48
3150000	650000	601	39
3150000	650000	602	44
3150000	650000	603	43
3150000	650000	604	34
3150000	650000	605	46
3150000	650000	606	34
3150000	650000	607	51
3150000	650000	608	47
3150000	650000	609	35
3150000	650000	610	47
3150000	650000	611	44
3150000	650000	612	47
3150000	650000	613	35
3150000	650000	614	49
3150000	650000	615	40
3150000	650000	616	39
3150000	650000	617	40
3150000	650000	618	43
3150000	650000	619	29
3150000	650000	620	31
3150000	650000	621	42
3150000	650000	622	41
3150000	650000	623	25
3150000	650000	624	40
3150000	650000	625	37
3150000	650000	626	41
3150000	650000	627	50
3150000	650000	628	51
3150000	650000	629	24
3150000	650000	630	46
3150000	650000	631	52
3150000	650000	632	38
3150000	650000	633	40
3150000	650000	634	37
3150000	650000	635	42
3150000	650000	636	35
3150000	650000	637	47
3150000	650000	638	38
3150000	650000	639	40
3150000	650000	640	24
3150000	650000	641	31
3150000	650000	642	38
3150000	650000	643	33
3150000	650000	644	28
3150000	650000	645	36
3150000	650000	646	33
3150000	650000	647	41
3150000	650000	648	39
3150000	650000	649	31
3150000	650000	650	32
3150000	650000	651	35
3150000	650000	652	34
3150000	650000	653	33
3150000	650000	654	37
3150000	650000	655	42
3150000	650000	656	37
3150000	650000	657	36
3150000	650000	658	33
3150000	650000	659	33
3150000	650000	660	25
3150000	650000	661	35
3150000	650000	662	30
3150000	650000	663	28
3150000	650000	664	38
3150000	650000	665	34
3150000	650000	666	28
3150000	650000	667	23
3150000	650000	668	27
3150000	650000	669	34
3150000	650000	670	30
3150000	650000	671	29
3150000	650000	672	30
3150000	650000	673	36
3150000	650000	674	34
3150000	650000	675	29
3150000	650000	676	26
3150000	650000	677	35
3150000	650000	678	32
3150000	650000	679	35
3150000	650000	680	24
3150000	650000	681	32
3150000	650000	682	29
3150000	650000	683	30
3150000	650000	684	23
3150000	650000	685	39
3150000	650000	686	21
3150000	650000	687	29
3150000	650000	688	34
3150000	650000	689	17
3150000	650000	690	40
3150000	650000	691	34
3150000	650000	692	31
3150000	650000	693	35
3150000	650000	694	21
3150000	650000	695	28
3150000	650000	696	27
3150000	650000	697	27
3150000	650000	698	27
3150000	650000	699	28
3150000	650000	700	24
3150000	650000	701	22
3150000	650000	702	31
3150000	650000	703	35
3150000	650000	704	30
3150000	650000	705	24
3150000	650000	706	36
3150000	650000	707	34
3150000	650000	708	23
3150000	650000	709	33
3150000	650000	710	40
3150000	650000	711	39
3150000	650000	712	33
3150000	650000	713	23
3150000	650000	714	28
3150000	650000	715	33
3150000	650000	716	32
3150000	650000	717	44
3150000	650000	718	30
3150000	650000	719	29
3150000	650000	720	26
3150000	650000	721	36
3150000	650000	722	28
3150000	650000	723	29
3150000	650000	724	22
3150000	650000	725	23
3150000	650000	726	27
3150000	650000	727	23
3150000	650000	728	21
3150000	650000	729	19
3150000	650000	730	28
3150000	650000	731	25
3150000	650000	732	19
3150000	650000	733	23
3150000	650000	734	21
3150000	650000	735	35
3150000	650000	736	21
3150000	650000	737	14
3150000	650000	738	31
3150000	650000	739	22
3150000	650000	740	18
3150000	650000	741	20
3150000	650000	742	20
3150000	650000	743	25
3150000	650000	744	22
3150000	650000	745	21
3150000	650000	746	30
3150000	650000	747	17
3150000	650000	748	24
3150000	650000	749	15
3150000	650000	750	20
3150000	650000	751	16
3150000	650000	752	15
3150000	650000	753	14
3150000	650000	754	26
3150000	650000	755	19
3150000	650000	756	20
3150000	650000	757	17
3150000	650000	758	5
3150000	650000	759	13
3150000	650000	760	19
3150000	650000	761	18
3150000	650000	762	17
3150000	650000	763	17
3150000	650000	764	15
3150000	650000	765	16
3150000	650000	766	21
3150000	650000	767	13
3150000	650000	768	16
3150000	650000	769	9
3150000	650000	770	12
3150000	650000	771	16
3150000	650000	772	6
3150000	650000	773	20
3150000	650000	774	10
3150000	650000	775	17
3150000	650000	776	19
3150000	650000	777	9
3150000	650000	778	7
3150000	650000	779	12
3150000	650000	780	13
3150000	650000	781	13
3150000	650000	782	7
3150000	650000	783	16
3150000	650000	784	15
3150000	650000	785	9
3150000	650000	786	13
3150000	650000	787	11
3150000	650000	788	11
3150000	650000	789	10
3150000	650000	790	10
3150000	650000	791	20
3150000	650000	792	17
3150000	650000	793	11
3150000	650000	794	8
3150000	650000	795	13
3150000	650000	796	18
3150000	650000	797	15
3150000	650000	798	19
3150000	650000	799	10
3150000	650000	800	14
3150000	650000	801	13
3150000	650000	802	15
3150000	650000	803	8
3150000	650000	804	12
3150000	650000	805	14
3150000	650000	806	15
3150000	650000	807	12
3150000	650000	808	8
3150000	650000	809	8
3150000	650000	810	14
3150000	650000	811	6
3150000	650000	812	10
3150000	650000	813	14
3150000	650000	814	14
3150000	650000	815	12
3150000	650000	816	14
3150000	650000	817	10
3150000	650000	818	13
3150000	650000	819	10
3150000	650000	820	10
3150000	650000	821	5
3150000	650000	822	15
3150000	650000	823	7
3150000	650000	824	12
3150000	650000	825	16
3150000	650000	826	10
3150000	650000	827	3
3150000	650000	828	6
3150000	650000	829	3
3150000	650000	830	5
3150000	650000	831	5
3150000	650000	832	16
3150000	650000	833	7
3150000	650000	834	6
3150000	650000	835	6
3150000	650000	836	6
3150000	650000	837	8
3150000	650000	838	10
3150000	650000	839	12
3150000	650000	840	10
3150000	650000	841	9
3150000	650000	842	10
3150000	650000	843	7
3150000	650000	844	5
3150000	650000	845	5
3150000	650000	846	9
3150000	650000	847	10
3150000	650000	848	8
3150000	650000	849	12
3150000	650000	850	7
3150000	650000	851	6
3150000	650000	852	5
3150000	650000	853	6
3150000	650000	854	9
3150000	650000	855	7
3150000	650000	856	14
3150000	650000	857	6
3150000	650000	858	4
3150000	650000	859	8
3150000	650000	860	4
3150000	650000	861	8
3150000	650000	862	9
3150000	650000	863	5
3150000	650000	864	7
3150000	650000	865	6
3150000	650000	866	3
3150000	650000	867	8
3150000	650000	868	1
3150000	650000	869	7
3150000	650000	870	10
3150000	650000	871	4
3150000	650000	872	10
3150000	650000	873	6
3150000	650000	874	4
3150000	650000	875	4
3150000	650000	876	7
3150000	650000	877	2
3150000	650000	878	7
3150000	650000	879	6
3150000	650000	880	5
3150000	650000	881	9
3150000	650000	882	7
3150000	650000	883	6
3150000	650000	884	5
3150000	650000	885	6
3150000	650000	886	5
3150000	650000	887	9
3150000	650000	888	3
3150000	650000	889	11
3150000	650000	890	6
3150000	650000	891	8
3150000	650000	892	2
3150000	650000	893	5
3150000	650000	894	2
3150000	650000	895	6
3150000	650000	896	2
3150000	650000	897	6
3150000	650000	898	3
3150000	650000	899	7
3150000	650000	900	1
3150000	650000	901	1
3150000	650000	902	1
3150000	650000	903	5
3150000	650000	904	3
3150000	650000	905	4
3150000	650000	906	3
3150000	650000	907	1
3150000	650000	908	1
3150000	650000	909	4
3150000	650000	910	2
3150000	650000	911	7
3150000	650000	912	5
3150000	650000	913	3
3150000	650000	914	6
3150000	650000	915	3
3150000	650000	916	4
3150000	650000	917	3
3150000	650000	918	2
3150000	650000	919	6
3150000	650000	920	7
3150000	650000	921	3
3150000	650000	922	5
3150000	650000	923	3
3150000	650000	924	2
3150000	650000	925	4
3150000	650000	926	2
3150000	650000	927	3
3150000	650000	930	2
3150000	650000	931	4
3150000	650000	932	4
3150000	650000	933	7
3150000	650000	934	2
3150000	650000	935	2
3150000	650000	936	10
3150000	650000	937	2
3150000	650000	938	3
3150000	650000	940	1
3150000	650000	941	3
3150000	650000	942	2
3150000	650000	943	2
3150000	650000	944	1
3150000	650000	945	4
3150000	650000	946	7
3150000	650000	947	6
3150000	650000	948	6
3150000	650000	949	7
3150000	650000	951	4
3150000	650000	952	2
3150000	650000	953	1
3150000	650000	954	2
3150000	650000	955	2
3150000	650000	956	5
3150000	650000	957	2
3150000	650000	958	3
3150000	650000	959	3
3150000	650000	961	4
3150000	650000	962	1
3150000	650000	963	1
3150000	650000	964	2
3150000	650000	965	7
3150000	650000	966	2
3150000	650000	967	4
3150000	650000	968	1
3150000	650000	969	2
3150000	650000	970	2
3150000	650000	972	1
3150000	650000	973	3
3150000	650000	974	2
3150000	650000	975	4
3150000	650000	976	1
3150000	650000	977	1
3150000	650000	978	1
3150000	650000	979	2
3150000	650000	980	5
3150000	650000	981	2
3150000	650000	982	2
3150000	650000	983	1
3150000	650000	984	7
3150000	650000	985	2
3150000	650000	986	1
3150000	650000	987	2
3150000	650000	988	1
3150000	650000	989	6
3150000	650000	990	1
3150000	650000	991	4
3150000	650000	992	7
3150000	650000	993	6
3150000	650000	994	1
3150000	650000	996	2
3150000	650000	997	1
3150000	650000	998	4
3150000	650000	999	2
3150000	750000	1000	8
3150000	750000	1001	7
3150000	750000	1002	3
3150000	750000	1003	3
3150000	750000	1004	7
3150000	750000	1005	10
3150000	750000	1006	3
3150000	750000	1007	5
3150000	750000	1008	9
3150000	750000	1009	6
3150000	750000	1010	5
3150000	750000	1011	9
3150000	750000	1012	3
3150000	750000	1013	3
3150000	750000	1014	4
3150000	750000	1015	9
3150000	750000	1016	5
3150000	750000	1017	7
3150000	750000	1018	3
3150000	750000	1019	12
3150000	750000	1020	7
3150000	750000	1021	4
3150000	750000	1022	5
3150000	750000	1023	2
3150000	750000	1024	5
3150000	750000	1025	3
3150000	750000	1026	4
3150000	750000	1027	7
3150000	750000	1028	9
3150000	750000	1029	2
3150000	750000	1030	9
3150000	750000	1031	6
3150000	750000	1032	1
3150000	750000	1033	6
3150000	750000	1034	4
3150000	750000	1035	2
3150000	750000	1036	1
3150000	750000	1037	11
3150000	750000	1038	1
3150000	750000	1039	1
3150000	750000	1040	9
3150000	750000	1041	7
3150000	750000	1042	2
3150000	750000	1043	7
3150000	750000	1044	4
3150000	750000	1045	3
3150000	750000	1046	6
3150000	750000	1047	7
3150000	750000	1048	10
3150000	750000	1049	8
3150000	750000	1050	4
3150000	750000	1051	4
3150000	750000	1052	2
3150000	750000	1053	10
3150000	750000	1054	7
3150000	750000	1055	3
3150000	750000	1056	9
3150000	750000	1057	8
3150000	750000	1058	4
3150000	750000	1059	4
3150000	750000	1060	8
3150000	750000	1061	2
3150000	750000	1062	1
3150000	750000	1063	3
3150000	750000	1064	5
3150000	750000	1065	4
3150000	750000	1066	2
3150000	750000	1067	6
3150000	750000	1068	5
3150000	750000	1069	6
3150000	750000	1070	2
3150000	750000	1071	4
3150000	750000	1072	5
3150000	750000	1073	9
3150000	750000	1074	7
3150000	750000	1075	6
3150000	750000	1076	4
3150000	750000	1077	6
3150000	750000	1078	5
3150000	750000	1079	2
3150000	750000	1080	10
3150000	750000	1081	10
3150000	750000	1082	7
3150000	750000	1083	10
3150000	750000	1084	4
3150000	750000	1085	3
3150000	750000	1086	9
3150000	750000	1087	11
3150000	750000	1088	4
3150000	750000	1089	11
3150000	750000	1090	4
3150000	750000	1091	7
3150000	750000	1092	8
3150000	750000	1093	4
3150000	750000	1094	8
3150000	750000	1095	2
3150000	750000	1096	10
3150000	750000	1097	9
3150000	750000	1098	7
3150000	750000	1099	6
3150000	750000	1100	6
3150000	750000	1101	3
3150000	750000	1102	6
3150000	750000	1103	5
3150000	750000	1104	6
3150000	750000	1105	2
3150000	750000	1106	10
3150000	750000	1107	7
3150000	750000	1108	6
3150000	750000	1109	11
3150000	750000	1110	5
3150000	750000	1111	6
3150000	750000	1112	5
3150000	750000	1113	6
3150000	750000	1114	1
3150000	750000	1115	13
3150000	750000	1116	5
3150000	750000	1117	10
3150000	750000	1118	4
3150000	750000	1119	5
3150000	750000	1120	5
3150000	750000	1121	1
3150000	750000	1122	3
3150000	750000	1123	3
3150000	750000	1124	7
3150000	750000	1125	2
3150000	750000	1126	8
3150000	750000	1127	6
3150000	750000	1128	10
3150000	750000	1129	5
3150000	750000	1130	3
3150000	750000	1131	10
3150000	750000	1132	6
3150000	750000	1133	7
3150000	750000	1134	3
3150000	750000	1135	17
3150000	750000	1136	4
3150000	750000	1137	5
3150000	750000	1138	6
3150000	750000	1139	7
3150000	750000	1140	9
3150000	750000	1141	9
3150000	750000	1142	3
3150000	750000	1143	7
3150000	750000	1144	11
3150000	750000	1145	10
3150000	750000	1146	6
3150000	750000	1147	7
3150000	750000	1148	8
3150000	750000	1149	10
3150000	750000	1150	9
3150000	750000	1151	10
3150000	750000	1152	3
3150000	750000	1153	7
3150000	750000	1154	6
3150000	750000	1155	5
3150000	750000	1156	11
3150000	750000	1157	3
3150000	750000	1158	9
3150000	750000	1159	8
3150000	750000	1160	7
3150000	750000	1161	11
3150000	750000	1162	8
3150000	750000	1163	7
3150000	750000	1164	8
3150000	750000	1165	2
3150000	750000	1166	7
3150000	750000	1167	10
3150000	750000	1168	11
3150000	750000	1169	8
3150000	750000	1170	8
3150000	750000	1171	6
3150000	750000	1172	8
3150000	750000	1173	8
3150000	750000	1174	7
3150000	750000	1175	8
3150000	750000	1176	10
3150000	750000	1177	11
3150000	750000	1178	11
3150000	750000	1179	16
3150000	750000	1180	6
3150000	750000	1181	7
3150000	750000	1182	6
3150000	750000	1183	7
3150000	750000	1184	11
3150000	750000	1185	9
3150000	750000	1186	9
3150000	750000	1187	7
3150000	750000	1188	7
3150000	750000	1189	16
3150000	750000	1190	10
3150000	750000	1191	8
3150000	750000	1192	4
3150000	750000	1193	8
3150000	750000	1194	13
3150000	750000	1195	9
3150000	750000	1196	11
3150000	750000	1197	3
3150000	750000	1198	8
3150000	750000	1199	6
3150000	750000	1200	12
3150000	750000	1201	16
3150000	750000	1202	9
3150000	750000	1203	14
3150000	750000	1204	6
3150000	750000	1205	16
3150000	750000	1206	11
3150000	750000	1207	8
3150000	750000	1208	15
3150000	750000	1209	10
3150000	750000	1210	12
3150000	750000	1211	5
3150000	750000	1212	5
3150000	750000	1213	18
3150000	750000	1214	8
3150000	750000	1215	10
3150000	750000	1216	8
3150000	750000	1217	14
3150000	750000	1218	13
3150000	750000	1219	4
3150000	750000	1220	13
3150000	750000	1221	8
3150000	750000	1222	12
3150000	750000	1223	10
3150000	750000	1224	10
3150000	750000	1225	11
3150000	750000	1226	7
3150000	750000	1227	14
3150000	750000	1228	10
3150000	750000	1229	6
3150000	750000	1230	7
3150000	750000	1231	19
3150000	750000	1232	6
3150000	750000	1233	9
3150000	750000	1234	9
3150000	750000	1235	4
3150000	750000	1236	11
3150000	750000	1237	10
3150000	750000	1238	13
3150000	750000	1239	6
3150000	750000	1240	11
3150000	750000	1241	16
3150000	750000	1242	10
3150000	750000	1243	19
3150000	750000	1244	11
3150000	750000	1245	16
3150000	750000	1246	8
3150000	750000	1247	12
3150000	750000	1248	9
3150000	750000	1249	15
3150000	750000	1250	12
3150000	750000	1251	11
3150000	750000	1252	11
3150000	750000	1253	9
3150000	750000	1254	9
3150000	750000	1255	10
3150000	750000	1256	14
3150000	750000	1257	9
3150000	750000	1258	14
3150000	750000	1259	18
3150000	750000	1260	14
3150000	750000	1261	12
3150000	750000	1262	16
3150000	750000	1263	12
3150000	750000	1264	12
3150000	750000	1265	12
3150000	750000	1266	11
3150000	750000	1267	18
3150000	750000	1268	11
3150000	750000	1269	12
3150000	750000	1270	24
3150000	750000	1271	11
3150000	750000	1272	13
3150000	750000	1273	19
3150000	750000	1274	9
3150000	750000	1275	13
3150000	750000	1276	17
3150000	750000	1277	13
3150000	750000	1278	17
3150000	750000	1279	21
3150000	750000	1280	17
3150000	750000	1281	20
3150000	750000	1282	19
3150000	750000	1283	10
3150000	750000	1284	15
3150000	750000	1285	25
3150000	750000	1286	17
3150000	750000	1287	22
3150000	750000	1288	17
3150000	750000	1289	23
3150000	750000	1290	17
3150000	750000	1291	18
3150000	750000	1292	13
3150000	750000	1293	8
3150000	750000	1294	26
3150000	750000	1295	19
3150000	750000	1296	13
3150000	750000	1297	18
3150000	750000	1298	16
3150000	750000	1299	8
3150000	750000	1300	17
3150000	750000	1301	13
3150000	750000	1302	9
3150000	750000	1303	14
3150000	750000	1304	7
3150000	750000	1305	16
3150000	750000	1306	15
3150000	750000	1307	22
3150000	750000	1308	15
3150000	750000	1309	2
3150000	750000	1310	14
3150000	750000	1311	15
3150000	750000	1312	17
3150000	750000	1313	11
3150000	750000	1314	13
3150000	750000	1315	15
3150000	750000	1316	13
3150000	750000	1317	11
3150000	750000	1318	19
3150000	750000	1319	11
3150000	750000	1320	8
3150000	750000	1321	10
3150000	750000	1322	13
3150000	750000	1323	5
3150000	750000	1324	14
3150000	750000	1325	12
3150000	750000	1326	16
3150000	750000	1327	7
3150000	750000	1328	14
3150000	750000	1329	11
3150000	750000	1330	10
3150000	750000	1331	12
3150000	750000	1332	11
3150000	750000	1333	12
3150000	750000	1334	14
3150000	750000	1335	21
3150000	750000	1336	19
3150000	750000	1337	15
3150000	750000	1338	13
3150000	750000	1339	15
3150000	750000	1340	12
3150000	750000	1341	11
3150000	750000	1342	17
3150000	750000	1343	6
3150000	750000	1344	16
3150000	750000	1345	16
3150000	750000	1346	13
3150000	750000	1347	10
3150000	750000	1348	13
3150000	750000	1349	7
3150000	750000	1350	14
3150000	750000	1351	10
3150000	750000	1352	15
3150000	750000	1353	14
3150000	750000	1354	9
3150000	750000	1355	7
3150000	750000	1356	10
3150000	750000	1357	16
3150000	750000	1358	9
3150000	750000	1359	16
3150000	750000	1360	11
3150000	750000	1361	16
3150000	750000	1362	17
3150000	750000	1363	11
3150000	750000	1364	10
3150000	750000	1365	14
3150000	750000	1366	10
3150000	750000	1367	6
3150000	750000	1368	19
3150000	750000	1369	12
3150000	750000	1370	12
3150000	750000	1371	7
3150000	750000	1372	14
3150000	750000	1373	9
3150000	750000	1374	15
3150000	750000	1375	13
3150000	750000	1376	10
3150000	750000	1377	10
3150000	750000	1378	13
3150000	750000	1379	12
3150000	750000	1380	8
3150000	750000	1381	13
3150000	750000	1382	16
3150000	750000	1383	12
3150000	750000	1384	11
3150000	750000	1385	12
3150000	750000	1386	12
3150000	750000	1387	16
3150000	750000	1388	10
3150000	750000	1389	17
3150000	750000	1390	18
3150000	750000	1391	9
3150000	750000	1392	11
3150000	750000	1393	13
3150000	750000	1394	16
3150000	750000	1395	7
3150000	750000	1396	9
3150000	750000	1397	17
3150000	750000	1398	9
3150000	750000	1399	12
3150000	750000	1400	19
3150000	750000	1401	15
3150000	750000	1402	8
3150000	750000	1403	22
3150000	750000	1404	10
3150000	750000	1405	9
3150000	750000	1406	12
3150000	750000	1407	7
3150000	750000	1408	3
3150000	750000	1409	13
3150000	750000	1410	13
3150000	750000	1411	12
3150000	750000	1412	17
3150000	750000	1413	14
3150000	750000	1414	17
3150000	750000	1415	10
3150000	750000	1416	20
3150000	750000	1417	11
3150000	750000	1418	14
3150000	750000	1419	10
3150000	750000	1420	14
3150000	750000	1421	4
3150000	750000	1422	8
3150000	750000	1423	12
3150000	750000	1424	9
3150000	750000	1425	19
3150000	750000	1426	10
3150000	750000	1427	11
3150000	750000	1428	11
3150000	750000	1429	17
3150000	750000	1430	19
3150000	750000	1431	16
3150000	750000	1432	8
3150000	750000	1433	13
3150000	750000	1434	11
3150000	750000	1435	7
3150000	750000	1436	20
3150000	750000	1437	13
3150000	750000	1438	9
3150000	750000	1439	15
3150000	750000	1440	12
3150000	750000	1441	10
3150000	750000	1442	8
3150000	750000	1443	9
3150000	750000	1444	7
3150000	750000	1445	18
3150000	750000	1446	11
3150000	750000	1447	11
3150000	750000	1448	12
3150000	750000	1449	10
3150000	750000	1450	9
3150000	750000	1451	9
3150000	750000	1452	15
3150000	750000	1453	13
3150000	750000	1454	10
3150000	750000	1455	8
3150000	750000	1456	13
3150000	750000	1457	8
3150000	750000	1458	11
3150000	750000	1459	4
3150000	750000	1460	11
3150000	750000	1461	9
3150000	750000	1462	9
3150000	750000	1463	8
3150000	750000	1464	11
3150000	750000	1465	11
3150000	750000	1466	7
3150000	750000	1467	8
3150000	750000	1468	15
3150000	750000	1469	11
3150000	750000	1470	17
3150000	750000	1471	12
3150000	750000	1472	14
3150000	750000	1473	12
3150000	750000	1474	8
3150000	750000	1475	7
3150000	750000	1476	14
3150000	750000	1477	7
3150000	750000	1478	10
3150000	750000	1479	10
3150000	750000	1480	3
3150000	750000	1481	9
3150000	750000	1482	17
3150000	750000	1483	15
3150000	750000	1484	6
3150000	750000	1485	9
3150000	750000	1486	11
3150000	750000	1487	7
3150000	750000	1488	5
3150000	750000	1489	11
3150000	750000	1490	11
3150000	750000	1491	10
3150000	750000	1492	13
3150000	750000	1493	5
3150000	750000	1494	9
3150000	750000	1495	9
3150000	750000	1496	13
3150000	750000	1497	6
3150000	750000	1498	10
3150000	750000	1499	8
3150000	750000	1500	10
3150000	750000	1501	8
3150000	750000	1502	7
3150000	750000	1503	11
3150000	750000	1504	11
3150000	750000	1505	14
3150000	750000	1506	12
3150000	750000	1507	13
3150000	750000	1508	7
3150000	750000	1509	8
3150000	750000	1510	9
3150000	750000	1511	6
3150000	750000	1512	10
3150000	750000	1513	14
3150000	750000	1514	15
3150000	750000	1515	13
3150000	750000	1516	8
3150000	750000	1517	5
3150000	750000	1518	5
3150000	750000	1519	6
3150000	750000	1520	8
3150000	750000	1521	12
3150000	750000	1522	6
3150000	750000	1523	5
3150000	750000	1524	5
3150000	750000	1525	5
3150000	750000	1526	12
3150000	750000	1527	5
3150000	750000	1528	6
3150000	750000	1529	14
3150000	750000	1530	10
3150000	750000	1531	14
3150000	750000	1532	3
3150000	750000	1533	8
3150000	750000	1534	9
3150000	750000	1535	12
3150000	750000	1536	12
3150000	750000	1537	10
3150000	750000	1538	7
3150000	750000	1539	5
3150000	750000	1540	11
3150000	750000	1541	6
3150000	750000	1542	8
3150000	750000	1543	11
3150000	750000	1544	8
3150000	750000	1545	9
3150000	750000	1546	8
3150000	750000	1547	5
3150000	750000	1548	4
3150000	750000	1549	7
3150000	750000	1550	7
3150000	750000	1551	10
3150000	750000	1552	9
3150000	750000	1553	4
3150000	750000	1554	8
3150000	750000	1555	8
3150000	750000	1556	6
3150000	750000	1557	4
3150000	750000	1558	5
3150000	750000	1559	10
3150000	750000	1560	8
3150000	750000	1561	8
3150000	750000	1562	8
3150000	750000	1563	6
3150000	750000	1564	4
3150000	750000	1565	11
3150000	750000	1566	10
3150000	750000	1567	3
3150000	750000	1568	7
3150000	750000	1569	7
3150000	750000	1570	1
3150000	750000	1571	7
3150000	750000	1572	7
3150000	750000	1573	5
3150000	750000	1574	11
3150000	750000	1575	10
3150000	750000	1576	10
3150000	750000	1577	7
3150000	750000	1578	7
3150000	750000	1579	5
3150000	750000	1580	2
3150000	750000	1581	7
3150000	750000	1582	7
3150000	750000	1583	4
3150000	750000	1584	1
3150000	750000	1585	4
3150000	750000	1586	4
3150000	750000	1587	4
3150000	750000	1588	3
3150000	750000	1589	3
3150000	750000	1590	8
3150000	750000	1591	5
3150000	750000	1592	4
3150000	750000	1593	2
3150000	750000	1594	7
3150000	750000	1595	5
3150000	750000	1596	8
3150000	750000	1597	3
3150000	750000	1598	3
3150000	750000	1599	7
3150000	750000	1600	3
3150000	750000	1601	8
3150000	750000	1602	5
3150000	750000	1603	2
3150000	750000	1604	2
3150000	750000	1605	2
3150000	750000	1606	8
3150000	750000	1607	10
3150000	750000	1608	7
3150000	750000	1609	4
3150000	750000	1610	7
3150000	750000	1611	1
3150000	750000	1612	3
3150000	750000	1613	3
3150000	750000	1614	6
3150000	750000	1615	6
3150000	750000	1616	4
3150000	750000	1617	3
3150000	750000	1619	4
3150000	750000	1620	7
3150000	750000	1621	5
3150000	750000	1622	6
3150000	750000	1623	9
3150000	750000	1624	3
3150000	750000	1625	2
3150000	750000	1626	1
3150000	750000	1627	3
3150000	750000	1628	2
3150000	750000	1629	6
3150000	750000	1630	3
3150000	750000	1631	7
3150000	750000	1632	7
3150000	750000	1633	3
3150000	750000	1634	4
3150000	750000	1635	2
3150000	750000	1636	3
3150000	750000	1637	2
3150000	750000	1638	1
3150000	750000	1639	2
3150000	750000	1640	7
3150000	750000	1641	4
3150000	750000	1642	2
3150000	750000	1643	2
3150000	750000	1644	4
3150000	750000	1645	1
3150000	750000	1646	5
3150000	750000	1647	1
3150000	750000	1648	5
3150000	750000	1649	4
3150000	750000	1650	2
3150000	750000	1651	2
3150000	750000	1652	1
3150000	750000	1653	5
3150000	750000	1654	2
3150000	750000	1655	4
3150000	750000	1656	1
3150000	750000	1657	3
3150000	750000	1658	1
3150000	750000	1660	1
3150000	750000	1661	1
3150000	750000	1662	4
3150000	750000	1663	2
3150000	750000	1664	1
3150000	750000	1665	1
3150000	750000	1666	4
3150000	750000	1667	4
3150000	750000	1669	2
3150000	750000	1671	5
3150000	750000	1672	5
3150000	750000	1673	4
3150000	750000	1674	2
3150000	750000	1675	1
3150000	750000	1676	1
3150000	750000	1677	1
3150000	750000	1678	4
3150000	750000	1679	3
3150000	750000	1680	2
3150000	750000	1682	1
3150000	750000	1683	2
3150000	750000	1684	2
3150000	750000	1685	8
3150000	750000	1686	1
3150000	750000	1687	3
3150000	750000	1688	3
3150000	750000	1689	1
3150000	750000	1692	3
3150000	750000	1693	3
3150000	750000	1694	2
3150000	750000	1695	2
3150000	750000	1697	2
3150000	750000	1698	2
3150000	750000	1700	3
3150000	750000	1701	2
3150000	750000	1702	2
3150000	750000	1703	1
3150000	750000	1704	1
3150000	750000	1705	5
3150000	750000	1706	1
3150000	750000	1707	1
3150000	750000	1708	2
3150000	750000	1709	3
3150000	750000	1711	2
3150000	750000	1712	3
3150000	750000	1713	1
3150000	750000	1714	3
3150000	750000	1715	1
3150000	750000	1716	3
3150000	750000	1717	3
3150000	750000	1718	1
3150000	750000	1720	5
3150000	750000	1721	2
3150000	750000	1722	4
3150000	750000	1723	1
3150000	750000	1724	1
3150000	750000	1725	1
3150000	750000	1726	1
3150000	750000	1727	2
3150000	750000	1728	2
3150000	750000	1729	3
3150000	750000	1730	1
3150000	750000	1731	2
3150000	750000	1732	1
3150000	750000	1734	2
3150000	750000	1735	3
3150000	750000	1736	2
3150000	750000	1739	1
3150000	750000	1740	3
3150000	750000	1741	1
3150000	750000	1742	1
3150000	750000	1744	2
3150000	750000	1745	1
3150000	750000	1746	2
3150000	750000	1747	1
3150000	750000	1749	1
3150000	750000	1751	4
3150000	750000	1752	1
3150000	750000	1755	1
3150000	750000	1756	1
3150000	750000	1757	2
3150000	750000	1762	1
3150000	750000	1765	2
3150000	750000	1766	2
3150000	750000	1770	1
3150000	750000	1772	1
3150000	750000	1773	2
3150000	750000	1776	1
3150000	750000	1778	4
3150000	750000	1780	3
3150000	750000	1781	1
3150000	750000	1782	1
3150000	750000	1783	1
3150000	750000	1785	1
3150000	750000	1787	1
3150000	750000	1789	1
3150000	750000	1791	1
3150000	750000	1793	2
3150000	750000	1794	3
3150000	750000	1796	1
3150000	750000	1798	5
3150000	750000	1799	3
3150000	750000	1801	1
3150000	750000	1802	1
3150000	750000	1804	1
3150000	750000	1805	1
3150000	750000	1813	1
3150000	750000	1814	2
3150000	750000	1818	1
3150000	750000	1819	4
3150000	750000	1820	6
3150000	750000	1822	4
3150000	750000	1823	1
3150000	750000	1824	1
3150000	750000	1827	1
3150000	750000	1828	3
3150000	750000	1830	2
3150000	750000	1831	3
3150000	750000	1832	1
3150000	750000	1840	4
3150000	750000	1842	1
3150000	750000	1843	1
3150000	750000	1846	2
3150000	750000	1849	2
3150000	750000	1850	1
3150000	750000	1851	1
3150000	750000	1852	2
3150000	750000	1855	2
3150000	750000	1856	1
3150000	750000	1857	2
3150000	750000	1860	1
3150000	750000	1862	1
3150000	750000	1863	2
3150000	750000	1864	2
3150000	750000	1868	2
3150000	750000	1869	1
3150000	750000	1870	1
3150000	750000	1871	1
3150000	750000	1872	1
3150000	750000	1874	1
3150000	750000	1875	2
3150000	750000	1877	1
3150000	750000	1878	1
3150000	750000	1881	2
3150000	750000	1885	2
3150000	750000	1891	1
3150000	750000	1893	1
3150000	750000	1894	1
3150000	750000	1898	1
3150000	750000	1899	2
3150000	750000	1900	1
3150000	750000	1903	1
3150000	750000	1907	4
3150000	750000	1914	3
3150000	750000	1915	2
3150000	750000	1917	1
3150000	750000	1922	1
3150000	750000	1926	1
3150000	750000	1928	1
3150000	750000	1929	1
3150000	750000	1935	1
3150000	750000	1936	1
3150000	750000	1937	1
3150000	750000	1938	2
3150000	750000	1940	1
3150000	750000	1943	2
3150000	750000	1944	1
3150000	750000	1947	1
3150000	750000	1954	1
3150000	750000	1958	3
3150000	750000	1963	1
3150000	750000	1966	1
3150000	750000	1968	1
3150000	750000	1974	2
3150000	750000	1977	1
3150000	750000	1981	1
3150000	750000	1983	2
3150000	750000	1986	1
3150000	750000	1987	2
3150000	750000	1988	1
3150000	750000	1990	1
3150000	750000	2001	1
3150000	750000	2003	2
3150000	750000	2008	2
3150000	750000	2009	2
3150000	750000	2017	3
3150000	750000	2019	1
3150000	750000	2022	3
3150000	750000	2023	1
3150000	750000	2029	1
3150000	750000	2032	1
3150000	750000	2033	2
3150000	750000	2038	1
3150000	750000	2039	1
3150000	750000	2042	2
3150000	750000	2043	1
3150000	750000	2046	2
3150000	750000	2047	1
3150000	750000	2049	1
3150000	750000	2050	1
3150000	750000	2054	1
3150000	750000	2058	1
3150000	750000	2065	1
3150000	750000	2068	2
3150000	750000	2069	1
3150000	750000	2070	2
3150000	750000	2072	1
3150000	750000	2075	2
3150000	750000	2076	1
3150000	750000	2077	1
3150000	750000	2078	1
3150000	750000	2087	1
3150000	750000	2088	1
3150000	750000	2094	1
3150000	750000	2098	3
3150000	750000	2100	1
3150000	750000	2107	1
3150000	750000	2110	2
3150000	750000	2112	1
3150000	750000	2113	2
3150000	750000	2116	1
3150000	750000	2119	1
3150000	750000	2123	2
3150000	750000	2126	1
3150000	750000	2132	1
3150000	750000	2133	1
3150000	750000	2136	1
3150000	750000	2142	2
3150000	750000	2143	1
3150000	750000	2144	1
3150000	750000	2145	1
3150000	750000	2146	3
3150000	750000	2148	1
3150000	750000	2150	2
3150000	750000	2152	1
3150000	750000	2157	1
3150000	750000	2161	1
3150000	750000	2162	1
3150000	750000	2164	1
3150000	750000	2167	1
3150000	750000	2171	2
3150000	750000	2172	1
3150000	750000	2173	1
3150000	750000	2174	1
3150000	750000	2178	1
3150000	750000	2182	1
3150000	750000	2183	1
3150000	750000	2186	1
3150000	750000	2190	1
3150000	750000	2196	1
3150000	750000	2199	3
3150000	750000	2200	1
3150000	750000	2203	1
3150000	750000	2204	1
3150000	750000	2206	1
3150000	750000	2207	1
3150000	750000	2208	1
3150000	750000	2209	1
3150000	750000	2210	1
3150000	750000	2212	3
3150000	750000	2213	1
3150000	750000	2216	2
3150000	750000	2219	1
3150000	750000	2222	1
3150000	750000	2230	1
3150000	750000	2231	2
3150000	750000	2234	1
3150000	750000	2235	1
3150000	750000	2236	1
3150000	750000	2237	2
3150000	750000	2239	2
3150000	750000	2241	1
3150000	750000	2242	1
3150000	750000	2246	2
3150000	750000	2247	2
3150000	750000	2248	1
3150000	750000	2249	5
3150000	750000	2251	1
3150000	750000	2261	1
3150000	750000	2262	3
3150000	750000	2263	2
3150000	750000	2265	2
3150000	750000	2267	1
3150000	750000	2270	1
3150000	750000	2275	3
3150000	750000	2276	2
3150000	750000	2277	1
3150000	750000	2280	1
3150000	750000	2282	1
3150000	750000	2287	2
3150000	750000	2289	2
3150000	750000	2290	2
3150000	750000	2291	2
3150000	750000	2292	1
3150000	750000	2294	1
3150000	750000	2298	3
3150000	750000	2299	1
3150000	750000	2301	3
3150000	750000	2302	2
3150000	750000	2306	3
3150000	750000	2307	1
3150000	750000	2308	2
3150000	750000	2309	1
3150000	750000	2310	1
3150000	750000	2311	1
3150000	750000	2312	1
3150000	750000	2314	2
3150000	750000	2316	4
3150000	750000	2319	1
3150000	750000	2321	5
3150000	750000	2324	1
3150000	750000	2326	2
3150000	750000	2327	1
3150000	750000	2329	2
3150000	750000	2332	1
3150000	750000	2333	1
3150000	750000	2339	3
3150000	750000	2340	1
3150000	750000	2342	1
3150000	750000	2352	1
3150000	750000	2354	2
3150000	750000	2355	3
3150000	750000	2360	1
3150000	750000	2363	1
3150000	750000	2364	1
3150000	750000	2365	3
3150000	750000	2366	1
3150000	750000	2367	1
3150000	750000	2368	1
3150000	750000	2369	1
3150000	750000	2374	1
3150000	750000	2375	2
3150000	750000	2377	1
3150000	750000	2379	2
3150000	750000	2381	1
3150000	750000	2382	1
3150000	750000	2388	2
3150000	750000	2392	2
3150000	750000	2393	1
3150000	750000	2394	2
3150000	750000	2395	1
3150000	750000	2397	1
3150000	750000	2400	1
3150000	750000	2406	2
3150000	750000	2415	1
3150000	750000	2422	1
3150000	750000	2423	3
3150000	750000	2431	1
3150000	750000	2435	1
3150000	750000	2437	1
3150000	750000	2440	1
3150000	750000	2444	1
3150000	750000	2450	2
3150000	750000	2453	1
3150000	750000	2483	1
3150000	750000	2496	1
3150000	750000	685	1
3150000	750000	693	1
3150000	750000	696	2
3150000	750000	697	1
3150000	750000	698	3
3150000	750000	700	2
3150000	750000	701	1
3150000	750000	702	4
3150000	750000	703	5
3150000	750000	704	2
3150000	750000	705	2
3150000	750000	706	2
3150000	750000	707	4
3150000	750000	708	3
3150000	750000	709	4
3150000	750000	710	4
3150000	750000	711	6
3150000	750000	712	14
3150000	750000	713	10
3150000	750000	714	6
3150000	750000	715	5
3150000	750000	716	4
3150000	750000	717	5
3150000	750000	718	5
3150000	750000	719	6
3150000	750000	720	8
3150000	750000	721	3
3150000	750000	722	2
3150000	750000	723	4
3150000	750000	724	5
3150000	750000	725	5
3150000	750000	726	12
3150000	750000	727	6
3150000	750000	728	6
3150000	750000	729	2
3150000	750000	730	3
3150000	750000	731	8
3150000	750000	732	5
3150000	750000	733	3
3150000	750000	734	5
3150000	750000	735	15
3150000	750000	736	10
3150000	750000	737	3
3150000	750000	738	11
3150000	750000	739	11
3150000	750000	740	10
3150000	750000	741	6
3150000	750000	742	7
3150000	750000	743	18
3150000	750000	744	5
3150000	750000	745	14
3150000	750000	746	8
3150000	750000	747	14
3150000	750000	748	12
3150000	750000	749	12
3150000	750000	750	17
3150000	750000	751	16
3150000	750000	752	10
3150000	750000	753	9
3150000	750000	754	14
3150000	750000	755	14
3150000	750000	756	19
3150000	750000	757	18
3150000	750000	758	25
3150000	750000	759	18
3150000	750000	760	15
3150000	750000	761	30
3150000	750000	762	21
3150000	750000	763	24
3150000	750000	764	21
3150000	750000	765	14
3150000	750000	766	18
3150000	750000	767	15
3150000	750000	768	14
3150000	750000	769	20
3150000	750000	770	18
3150000	750000	771	14
3150000	750000	772	25
3150000	750000	773	24
3150000	750000	774	26
3150000	750000	775	23
3150000	750000	776	17
3150000	750000	777	19
3150000	750000	778	11
3150000	750000	779	23
3150000	750000	780	18
3150000	750000	781	28
3150000	750000	782	13
3150000	750000	783	21
3150000	750000	784	18
3150000	750000	785	16
3150000	750000	786	19
3150000	750000	787	17
3150000	750000	788	39
3150000	750000	789	14
3150000	750000	790	32
3150000	750000	791	31
3150000	750000	792	28
3150000	750000	793	22
3150000	750000	794	13
3150000	750000	795	35
3150000	750000	796	21
3150000	750000	797	31
3150000	750000	798	18
3150000	750000	799	16
3150000	750000	800	21
3150000	750000	801	16
3150000	750000	802	25
3150000	750000	803	14
3150000	750000	804	18
3150000	750000	805	16
3150000	750000	806	27
3150000	750000	807	18
3150000	750000	808	29
3150000	750000	809	15
3150000	750000	810	24
3150000	750000	811	18
3150000	750000	812	34
3150000	750000	813	23
3150000	750000	814	24
3150000	750000	815	18
3150000	750000	816	25
3150000	750000	817	21
3150000	750000	818	21
3150000	750000	819	33
3150000	750000	820	17
3150000	750000	821	25
3150000	750000	822	14
3150000	750000	823	24
3150000	750000	824	24
3150000	750000	825	12
3150000	750000	826	23
3150000	750000	827	22
3150000	750000	828	18
3150000	750000	829	19
3150000	750000	830	10
3150000	750000	831	15
3150000	750000	832	18
3150000	750000	833	17
3150000	750000	834	23
3150000	750000	835	8
3150000	750000	836	20
3150000	750000	837	17
3150000	750000	838	17
3150000	750000	839	11
3150000	750000	840	21
3150000	750000	841	13
3150000	750000	842	16
3150000	750000	843	17
3150000	750000	844	11
3150000	750000	845	19
3150000	750000	846	15
3150000	750000	847	14
3150000	750000	848	10
3150000	750000	849	13
3150000	750000	850	10
3150000	750000	851	20
3150000	750000	852	14
3150000	750000	853	11
3150000	750000	854	23
3150000	750000	855	11
3150000	750000	856	15
3150000	750000	857	9
3150000	750000	858	8
3150000	750000	859	18
3150000	750000	860	11
3150000	750000	861	7
3150000	750000	862	6
3150000	750000	863	13
3150000	750000	864	9
3150000	750000	865	13
3150000	750000	866	12
3150000	750000	867	13
3150000	750000	868	17
3150000	750000	869	11
3150000	750000	870	11
3150000	750000	871	11
3150000	750000	872	13
3150000	750000	873	8
3150000	750000	874	9
3150000	750000	875	7
3150000	750000	876	12
3150000	750000	877	8
3150000	750000	878	21
3150000	750000	879	7
3150000	750000	880	14
3150000	750000	881	8
3150000	750000	882	8
3150000	750000	883	7
3150000	750000	884	6
3150000	750000	885	11
3150000	750000	886	16
3150000	750000	887	11
3150000	750000	888	13
3150000	750000	889	6
3150000	750000	890	5
3150000	750000	891	6
3150000	750000	892	10
3150000	750000	893	4
3150000	750000	894	9
3150000	750000	895	13
3150000	750000	896	9
3150000	750000	897	16
3150000	750000	898	17
3150000	750000	899	13
3150000	750000	900	9
3150000	750000	901	12
3150000	750000	902	10
3150000	750000	903	8
3150000	750000	904	3
3150000	750000	905	5
3150000	750000	906	10
3150000	750000	907	8
3150000	750000	908	5
3150000	750000	909	9
3150000	750000	910	3
3150000	750000	911	15
3150000	750000	912	6
3150000	750000	913	8
3150000	750000	914	4
3150000	750000	915	7
3150000	750000	916	5
3150000	750000	917	2
3150000	750000	918	2
3150000	750000	919	10
3150000	750000	920	6
3150000	750000	921	12
3150000	750000	922	10
3150000	750000	923	6
3150000	750000	924	8
3150000	750000	925	11
3150000	750000	926	9
3150000	750000	927	7
3150000	750000	928	4
3150000	750000	929	10
3150000	750000	930	2
3150000	750000	931	9
3150000	750000	932	2
3150000	750000	933	5
3150000	750000	934	7
3150000	750000	935	10
3150000	750000	936	4
3150000	750000	937	5
3150000	750000	938	6
3150000	750000	939	8
3150000	750000	940	6
3150000	750000	941	5
3150000	750000	942	7
3150000	750000	943	12
3150000	750000	944	5
3150000	750000	945	9
3150000	750000	946	4
3150000	750000	947	7
3150000	750000	948	6
3150000	750000	949	6
3150000	750000	950	2
3150000	750000	951	3
3150000	750000	952	11
3150000	750000	953	14
3150000	750000	954	4
3150000	750000	955	4
3150000	750000	956	11
3150000	750000	957	8
3150000	750000	958	3
3150000	750000	959	6
3150000	750000	960	3
3150000	750000	961	5
3150000	750000	962	9
3150000	750000	963	4
3150000	750000	964	2
3150000	750000	965	10
3150000	750000	966	7
3150000	750000	967	9
3150000	750000	968	3
3150000	750000	969	7
3150000	750000	970	5
3150000	750000	971	6
3150000	750000	972	8
3150000	750000	973	10
3150000	750000	974	11
3150000	750000	975	9
3150000	750000	976	6
3150000	750000	977	5
3150000	750000	978	6
3150000	750000	979	4
3150000	750000	980	8
3150000	750000	981	8
3150000	750000	982	7
3150000	750000	983	9
3150000	750000	984	1
3150000	750000	985	7
3150000	750000	986	3
3150000	750000	987	4
3150000	750000	988	8
3150000	750000	989	3
3150000	750000	990	6
3150000	750000	991	12
3150000	750000	992	9
3150000	750000	993	9
3150000	750000	994	4
3150000	750000	995	3
3150000	750000	996	6
3150000	750000	997	3
3150000	750000	998	8
3150000	750000	999	7
3150000	850000	1000	3
3150000	850000	1001	8
3150000	850000	1002	10
3150000	850000	1003	13
3150000	850000	1004	12
3150000	850000	1005	9
3150000	850000	1006	11
3150000	850000	1007	9
3150000	850000	1008	7
3150000	850000	1009	6
3150000	850000	1010	9
3150000	850000	1011	15
3150000	850000	1012	9
3150000	850000	1013	10
3150000	850000	1014	14
3150000	850000	1015	9
3150000	850000	1016	14
3150000	850000	1017	5
3150000	850000	1018	6
3150000	850000	1019	11
3150000	850000	1020	11
3150000	850000	1021	14
3150000	850000	1022	7
3150000	850000	1023	5
3150000	850000	1024	10
3150000	850000	1025	8
3150000	850000	1026	6
3150000	850000	1027	10
3150000	850000	1028	6
3150000	850000	1029	19
3150000	850000	1030	14
3150000	850000	1031	13
3150000	850000	1032	7
3150000	850000	1033	7
3150000	850000	1034	8
3150000	850000	1035	16
3150000	850000	1036	15
3150000	850000	1037	7
3150000	850000	1038	11
3150000	850000	1039	4
3150000	850000	1040	8
3150000	850000	1041	11
3150000	850000	1042	6
3150000	850000	1043	14
3150000	850000	1044	9
3150000	850000	1045	9
3150000	850000	1046	7
3150000	850000	1047	17
3150000	850000	1048	8
3150000	850000	1049	14
3150000	850000	1050	3
3150000	850000	1051	8
3150000	850000	1052	16
3150000	850000	1053	3
3150000	850000	1054	4
3150000	850000	1055	9
3150000	850000	1056	11
3150000	850000	1057	9
3150000	850000	1058	7
3150000	850000	1059	11
3150000	850000	1060	7
3150000	850000	1061	5
3150000	850000	1062	5
3150000	850000	1063	10
3150000	850000	1064	10
3150000	850000	1065	6
3150000	850000	1066	7
3150000	850000	1067	8
3150000	850000	1068	17
3150000	850000	1069	10
3150000	850000	1070	5
3150000	850000	1071	7
3150000	850000	1072	9
3150000	850000	1073	15
3150000	850000	1074	18
3150000	850000	1075	5
3150000	850000	1076	5
3150000	850000	1077	8
3150000	850000	1078	8
3150000	850000	1079	8
3150000	850000	1080	11
3150000	850000	1081	10
3150000	850000	1082	3
3150000	850000	1083	11
3150000	850000	1084	7
3150000	850000	1085	9
3150000	850000	1086	6
3150000	850000	1087	14
3150000	850000	1088	11
3150000	850000	1089	8
3150000	850000	1090	12
3150000	850000	1091	9
3150000	850000	1092	12
3150000	850000	1093	3
3150000	850000	1094	7
3150000	850000	1095	8
3150000	850000	1096	7
3150000	850000	1097	13
3150000	850000	1098	8
3150000	850000	1099	12
3150000	850000	1100	13
3150000	850000	1101	8
3150000	850000	1102	9
3150000	850000	1103	7
3150000	850000	1104	2
3150000	850000	1105	11
3150000	850000	1106	9
3150000	850000	1107	3
3150000	850000	1108	6
3150000	850000	1109	15
3150000	850000	1110	11
3150000	850000	1111	7
3150000	850000	1112	9
3150000	850000	1113	10
3150000	850000	1114	12
3150000	850000	1115	8
3150000	850000	1116	5
3150000	850000	1117	9
3150000	850000	1118	8
3150000	850000	1119	9
3150000	850000	1120	8
3150000	850000	1121	11
3150000	850000	1122	10
3150000	850000	1123	6
3150000	850000	1124	11
3150000	850000	1125	3
3150000	850000	1126	14
3150000	850000	1127	9
3150000	850000	1128	6
3150000	850000	1129	9
3150000	850000	1130	4
3150000	850000	1131	11
3150000	850000	1132	9
3150000	850000	1133	11
3150000	850000	1134	7
3150000	850000	1135	10
3150000	850000	1136	11
3150000	850000	1137	7
3150000	850000	1138	8
3150000	850000	1139	7
3150000	850000	1140	7
3150000	850000	1141	7
3150000	850000	1142	9
3150000	850000	1143	7
3150000	850000	1144	10
3150000	850000	1145	3
3150000	850000	1146	12
3150000	850000	1147	4
3150000	850000	1148	7
3150000	850000	1149	6
3150000	850000	1150	12
3150000	850000	1151	8
3150000	850000	1152	7
3150000	850000	1153	6
3150000	850000	1154	8
3150000	850000	1155	6
3150000	850000	1156	9
3150000	850000	1157	7
3150000	850000	1158	5
3150000	850000	1159	9
3150000	850000	1160	6
3150000	850000	1161	13
3150000	850000	1162	7
3150000	850000	1163	8
3150000	850000	1164	15
3150000	850000	1165	8
3150000	850000	1166	5
3150000	850000	1167	9
3150000	850000	1168	10
3150000	850000	1169	13
3150000	850000	1170	7
3150000	850000	1171	7
3150000	850000	1172	10
3150000	850000	1173	7
3150000	850000	1174	6
3150000	850000	1175	9
3150000	850000	1176	9
3150000	850000	1177	5
3150000	850000	1178	5
3150000	850000	1179	9
3150000	850000	1180	6
3150000	850000	1181	5
3150000	850000	1182	9
3150000	850000	1183	11
3150000	850000	1184	8
3150000	850000	1185	7
3150000	850000	1186	10
3150000	850000	1187	6
3150000	850000	1188	5
3150000	850000	1189	7
3150000	850000	1190	13
3150000	850000	1191	10
3150000	850000	1192	8
3150000	850000	1193	12
3150000	850000	1194	2
3150000	850000	1195	7
3150000	850000	1196	9
3150000	850000	1197	4
3150000	850000	1198	14
3150000	850000	1199	12
3150000	850000	1200	6
3150000	850000	1201	9
3150000	850000	1202	12
3150000	850000	1203	5
3150000	850000	1204	7
3150000	850000	1205	10
3150000	850000	1206	9
3150000	850000	1207	11
3150000	850000	1208	5
3150000	850000	1209	4
3150000	850000	1210	10
3150000	850000	1211	3
3150000	850000	1212	6
3150000	850000	1213	8
3150000	850000	1214	8
3150000	850000	1215	9
3150000	850000	1216	7
3150000	850000	1217	9
3150000	850000	1218	3
3150000	850000	1219	8
3150000	850000	1220	12
3150000	850000	1221	4
3150000	850000	1222	2
3150000	850000	1223	5
3150000	850000	1224	7
3150000	850000	1225	7
3150000	850000	1226	4
3150000	850000	1227	8
3150000	850000	1228	10
3150000	850000	1229	15
3150000	850000	1230	6
3150000	850000	1231	12
3150000	850000	1232	6
3150000	850000	1233	6
3150000	850000	1234	6
3150000	850000	1235	2
3150000	850000	1236	6
3150000	850000	1237	9
3150000	850000	1238	12
3150000	850000	1239	9
3150000	850000	1240	6
3150000	850000	1241	4
3150000	850000	1242	9
3150000	850000	1243	6
3150000	850000	1244	6
3150000	850000	1245	4
3150000	850000	1246	2
3150000	850000	1247	6
3150000	850000	1248	4
3150000	850000	1249	7
3150000	850000	1250	6
3150000	850000	1251	10
3150000	850000	1252	10
3150000	850000	1253	4
3150000	850000	1254	5
3150000	850000	1255	6
3150000	850000	1256	6
3150000	850000	1257	8
3150000	850000	1258	5
3150000	850000	1259	6
3150000	850000	1260	8
3150000	850000	1261	3
3150000	850000	1262	9
3150000	850000	1263	5
3150000	850000	1264	10
3150000	850000	1265	6
3150000	850000	1266	8
3150000	850000	1267	8
3150000	850000	1268	3
3150000	850000	1269	8
3150000	850000	1270	10
3150000	850000	1271	8
3150000	850000	1272	3
3150000	850000	1273	12
3150000	850000	1274	6
3150000	850000	1275	13
3150000	850000	1276	6
3150000	850000	1277	5
3150000	850000	1278	7
3150000	850000	1279	10
3150000	850000	1280	3
3150000	850000	1281	6
3150000	850000	1282	8
3150000	850000	1283	7
3150000	850000	1284	6
3150000	850000	1285	6
3150000	850000	1286	6
3150000	850000	1287	7
3150000	850000	1288	9
3150000	850000	1289	5
3150000	850000	1290	8
3150000	850000	1291	7
3150000	850000	1292	10
3150000	850000	1293	3
3150000	850000	1294	6
3150000	850000	1295	7
3150000	850000	1296	8
3150000	850000	1297	6
3150000	850000	1298	2
3150000	850000	1299	6
3150000	850000	1300	3
3150000	850000	1301	4
3150000	850000	1302	10
3150000	850000	1303	9
3150000	850000	1304	10
3150000	850000	1305	5
3150000	850000	1306	7
3150000	850000	1307	7
3150000	850000	1308	1
3150000	850000	1309	3
3150000	850000	1310	5
3150000	850000	1311	8
3150000	850000	1312	3
3150000	850000	1313	5
3150000	850000	1314	15
3150000	850000	1315	7
3150000	850000	1316	1
3150000	850000	1317	2
3150000	850000	1318	7
3150000	850000	1319	7
3150000	850000	1320	3
3150000	850000	1321	6
3150000	850000	1322	2
3150000	850000	1323	2
3150000	850000	1324	1
3150000	850000	1325	7
3150000	850000	1326	5
3150000	850000	1327	6
3150000	850000	1328	9
3150000	850000	1329	11
3150000	850000	1330	7
3150000	850000	1331	3
3150000	850000	1332	1
3150000	850000	1333	8
3150000	850000	1334	6
3150000	850000	1335	6
3150000	850000	1336	3
3150000	850000	1337	5
3150000	850000	1338	4
3150000	850000	1339	2
3150000	850000	1340	1
3150000	850000	1341	2
3150000	850000	1342	5
3150000	850000	1343	6
3150000	850000	1344	2
3150000	850000	1345	4
3150000	850000	1346	6
3150000	850000	1347	5
3150000	850000	1348	3
3150000	850000	1349	6
3150000	850000	1350	5
3150000	850000	1351	2
3150000	850000	1352	5
3150000	850000	1353	2
3150000	850000	1354	3
3150000	850000	1355	5
3150000	850000	1356	5
3150000	850000	1357	1
3150000	850000	1358	7
3150000	850000	1359	12
3150000	850000	1360	4
3150000	850000	1361	3
3150000	850000	1362	5
3150000	850000	1363	2
3150000	850000	1364	2
3150000	850000	1365	7
3150000	850000	1366	5
3150000	850000	1367	3
3150000	850000	1368	3
3150000	850000	1369	5
3150000	850000	1370	3
3150000	850000	1371	2
3150000	850000	1372	2
3150000	850000	1373	6
3150000	850000	1374	2
3150000	850000	1375	2
3150000	850000	1376	3
3150000	850000	1377	6
3150000	850000	1378	8
3150000	850000	1380	3
3150000	850000	1381	2
3150000	850000	1382	3
3150000	850000	1383	1
3150000	850000	1384	2
3150000	850000	1385	1
3150000	850000	1386	2
3150000	850000	1387	6
3150000	850000	1388	7
3150000	850000	1389	2
3150000	850000	1390	6
3150000	850000	1391	1
3150000	850000	1392	2
3150000	850000	1393	3
3150000	850000	1394	2
3150000	850000	1395	3
3150000	850000	1396	2
3150000	850000	1397	1
3150000	850000	1398	1
3150000	850000	1399	3
3150000	850000	1400	6
3150000	850000	1401	5
3150000	850000	1402	4
3150000	850000	1403	5
3150000	850000	1404	4
3150000	850000	1405	6
3150000	850000	1406	2
3150000	850000	1407	3
3150000	850000	1408	3
3150000	850000	1409	4
3150000	850000	1410	3
3150000	850000	1411	3
3150000	850000	1412	3
3150000	850000	1413	3
3150000	850000	1414	4
3150000	850000	1415	4
3150000	850000	1416	5
3150000	850000	1417	2
3150000	850000	1418	3
3150000	850000	1419	4
3150000	850000	1420	2
3150000	850000	1422	4
3150000	850000	1423	2
3150000	850000	1424	5
3150000	850000	1425	7
3150000	850000	1426	4
3150000	850000	1427	3
3150000	850000	1428	5
3150000	850000	1429	5
3150000	850000	1430	2
3150000	850000	1431	3
3150000	850000	1432	3
3150000	850000	1433	1
3150000	850000	1434	4
3150000	850000	1435	4
3150000	850000	1436	6
3150000	850000	1437	3
3150000	850000	1438	4
3150000	850000	1439	5
3150000	850000	1440	2
3150000	850000	1441	7
3150000	850000	1442	3
3150000	850000	1444	1
3150000	850000	1445	1
3150000	850000	1446	5
3150000	850000	1447	6
3150000	850000	1448	2
3150000	850000	1449	1
3150000	850000	1450	2
3150000	850000	1451	1
3150000	850000	1452	3
3150000	850000	1453	3
3150000	850000	1454	2
3150000	850000	1455	3
3150000	850000	1456	4
3150000	850000	1457	5
3150000	850000	1458	4
3150000	850000	1459	6
3150000	850000	1460	1
3150000	850000	1461	6
3150000	850000	1462	3
3150000	850000	1463	2
3150000	850000	1464	4
3150000	850000	1465	6
3150000	850000	1466	2
3150000	850000	1467	4
3150000	850000	1469	3
3150000	850000	1470	6
3150000	850000	1471	1
3150000	850000	1472	3
3150000	850000	1473	1
3150000	850000	1474	3
3150000	850000	1475	5
3150000	850000	1476	1
3150000	850000	1477	3
3150000	850000	1478	4
3150000	850000	1479	6
3150000	850000	1480	3
3150000	850000	1481	3
3150000	850000	1482	1
3150000	850000	1483	1
3150000	850000	1484	4
3150000	850000	1485	3
3150000	850000	1486	1
3150000	850000	1487	2
3150000	850000	1488	2
3150000	850000	1489	4
3150000	850000	1490	6
3150000	850000	1491	4
3150000	850000	1492	4
3150000	850000	1493	5
3150000	850000	1494	7
3150000	850000	1495	3
3150000	850000	1496	7
3150000	850000	1497	5
3150000	850000	1498	1
3150000	850000	1499	2
3150000	850000	1500	5
3150000	850000	1501	8
3150000	850000	1502	3
3150000	850000	1503	6
3150000	850000	1504	4
3150000	850000	1505	5
3150000	850000	1506	4
3150000	850000	1507	4
3150000	850000	1508	4
3150000	850000	1509	2
3150000	850000	1510	4
3150000	850000	1511	3
3150000	850000	1512	4
3150000	850000	1513	3
3150000	850000	1514	2
3150000	850000	1515	5
3150000	850000	1516	5
3150000	850000	1517	4
3150000	850000	1518	2
3150000	850000	1519	3
3150000	850000	1520	5
3150000	850000	1521	2
3150000	850000	1522	4
3150000	850000	1523	1
3150000	850000	1524	1
3150000	850000	1525	2
3150000	850000	1526	2
3150000	850000	1527	4
3150000	850000	1528	6
3150000	850000	1529	2
3150000	850000	1530	4
3150000	850000	1531	6
3150000	850000	1532	3
3150000	850000	1533	3
3150000	850000	1534	4
3150000	850000	1535	4
3150000	850000	1536	8
3150000	850000	1537	2
3150000	850000	1538	7
3150000	850000	1539	1
3150000	850000	1540	2
3150000	850000	1541	3
3150000	850000	1542	5
3150000	850000	1543	5
3150000	850000	1544	3
3150000	850000	1545	1
3150000	850000	1546	2
3150000	850000	1547	1
3150000	850000	1548	2
3150000	850000	1549	1
3150000	850000	1550	8
3150000	850000	1551	2
3150000	850000	1553	4
3150000	850000	1554	7
3150000	850000	1555	5
3150000	850000	1556	5
3150000	850000	1557	7
3150000	850000	1558	4
3150000	850000	1559	4
3150000	850000	1560	1
3150000	850000	1561	2
3150000	850000	1562	4
3150000	850000	1563	7
3150000	850000	1564	6
3150000	850000	1565	3
3150000	850000	1566	3
3150000	850000	1568	4
3150000	850000	1569	3
3150000	850000	1570	5
3150000	850000	1571	1
3150000	850000	1572	2
3150000	850000	1573	11
3150000	850000	1574	8
3150000	850000	1575	4
3150000	850000	1576	4
3150000	850000	1577	3
3150000	850000	1578	5
3150000	850000	1579	8
3150000	850000	1580	8
3150000	850000	1581	6
3150000	850000	1582	1
3150000	850000	1583	3
3150000	850000	1584	3
3150000	850000	1586	5
3150000	850000	1587	5
3150000	850000	1588	3
3150000	850000	1589	4
3150000	850000	1590	5
3150000	850000	1591	1
3150000	850000	1592	5
3150000	850000	1593	3
3150000	850000	1594	3
3150000	850000	1595	7
3150000	850000	1596	8
3150000	850000	1597	3
3150000	850000	1598	5
3150000	850000	1599	4
3150000	850000	1600	2
3150000	850000	1601	4
3150000	850000	1602	7
3150000	850000	1603	3
3150000	850000	1604	6
3150000	850000	1605	2
3150000	850000	1606	2
3150000	850000	1607	2
3150000	850000	1608	3
3150000	850000	1609	3
3150000	850000	1610	2
3150000	850000	1611	2
3150000	850000	1612	2
3150000	850000	1613	3
3150000	850000	1614	2
3150000	850000	1615	3
3150000	850000	1616	2
3150000	850000	1617	1
3150000	850000	1618	2
3150000	850000	1619	1
3150000	850000	1623	1
3150000	850000	1626	5
3150000	850000	1627	1
3150000	850000	1628	1
3150000	850000	1629	2
3150000	850000	1631	2
3150000	850000	1632	4
3150000	850000	1633	1
3150000	850000	1634	1
3150000	850000	1635	4
3150000	850000	1636	2
3150000	850000	1637	4
3150000	850000	1640	3
3150000	850000	1641	2
3150000	850000	1642	3
3150000	850000	1644	1
3150000	850000	1645	1
3150000	850000	1647	1
3150000	850000	1650	1
3150000	850000	1654	1
3150000	850000	1658	1
3150000	850000	1664	1
3150000	850000	1671	1
3150000	850000	1672	1
3150000	850000	1673	1
3150000	850000	1674	1
3150000	850000	1675	2
3150000	850000	1676	1
3150000	850000	1677	1
3150000	850000	1678	1
3150000	850000	1680	1
3150000	850000	1686	2
3150000	850000	1688	1
3150000	850000	1689	2
3150000	850000	1691	1
3150000	850000	1693	2
3150000	850000	1695	1
3150000	850000	1696	2
3150000	850000	1699	1
3150000	850000	1700	1
3150000	850000	1702	1
3150000	850000	1703	1
3150000	850000	1704	1
3150000	850000	1705	1
3150000	850000	1707	1
3150000	850000	1711	1
3150000	850000	1714	2
3150000	850000	1716	1
3150000	850000	1718	2
3150000	850000	1727	1
3150000	850000	1728	2
3150000	850000	1731	2
3150000	850000	1737	1
3150000	850000	1740	1
3150000	850000	1747	1
3150000	850000	1750	1
3150000	850000	1752	1
3150000	850000	1760	1
3150000	850000	1761	1
3150000	850000	1765	1
3150000	850000	1767	2
3150000	850000	1774	1
3150000	850000	1778	3
3150000	850000	1780	1
3150000	850000	1784	2
3150000	850000	1788	1
3150000	850000	1796	1
3150000	850000	1799	1
3150000	850000	1803	1
3150000	850000	1804	1
3150000	850000	1811	1
3150000	850000	1814	2
3150000	850000	1815	1
3150000	850000	1817	2
3150000	850000	1822	1
3150000	850000	1827	1
3150000	850000	1830	1
3150000	850000	1831	1
3150000	850000	1832	1
3150000	850000	1835	2
3150000	850000	1838	1
3150000	850000	1840	2
3150000	850000	1842	1
3150000	850000	1848	1
3150000	850000	1849	1
3150000	850000	1850	1
3150000	850000	1859	1
3150000	850000	1860	1
3150000	850000	1866	1
3150000	850000	1873	2
3150000	850000	1874	1
3150000	850000	1875	2
3150000	850000	1876	1
3150000	850000	1877	2
3150000	850000	1879	1
3150000	850000	1880	2
3150000	850000	1883	1
3150000	850000	1887	1
3150000	850000	1888	1
3150000	850000	1890	2
3150000	850000	1893	3
3150000	850000	1897	5
3150000	850000	1901	1
3150000	850000	1902	1
3150000	850000	1905	1
3150000	850000	1910	2
3150000	850000	1928	1
3150000	850000	1930	1
3150000	850000	1937	1
3150000	850000	1941	1
3150000	850000	1951	1
3150000	850000	1967	1
3150000	850000	1976	1
3150000	850000	1987	1
3150000	850000	2008	1
3150000	850000	2009	1
3150000	850000	2019	1
3150000	850000	2054	1
3150000	850000	2060	1
3150000	850000	2085	1
3150000	850000	2100	1
3150000	850000	2124	2
3150000	850000	2148	2
3150000	850000	2151	1
3150000	850000	2152	2
3150000	850000	2178	1
3150000	850000	2194	2
3150000	850000	2216	1
3150000	850000	2268	1
3150000	850000	2295	1
3150000	850000	2320	1
3150000	850000	2324	1
3150000	850000	2346	1
3150000	850000	2410	1
3150000	850000	2470	1
3150000	850000	2471	1
3150000	850000	2503	1
3150000	850000	2516	1
3150000	850000	2528	2
3150000	850000	2554	1
3150000	850000	2581	1
3150000	850000	506	3
3150000	850000	507	3
3150000	850000	509	8
3150000	850000	510	6
3150000	850000	511	5
3150000	850000	512	5
3150000	850000	513	3
3150000	850000	514	4
3150000	850000	515	1
3150000	850000	516	6
3150000	850000	517	9
3150000	850000	518	5
3150000	850000	519	7
3150000	850000	520	4
3150000	850000	521	11
3150000	850000	522	8
3150000	850000	523	9
3150000	850000	524	10
3150000	850000	525	7
3150000	850000	526	9
3150000	850000	527	7
3150000	850000	528	11
3150000	850000	529	9
3150000	850000	530	6
3150000	850000	531	8
3150000	850000	532	11
3150000	850000	533	11
3150000	850000	534	13
3150000	850000	535	4
3150000	850000	536	11
3150000	850000	537	12
3150000	850000	538	14
3150000	850000	539	7
3150000	850000	540	14
3150000	850000	541	11
3150000	850000	542	14
3150000	850000	543	17
3150000	850000	544	12
3150000	850000	545	11
3150000	850000	546	12
3150000	850000	547	13
3150000	850000	548	7
3150000	850000	549	8
3150000	850000	550	3
3150000	850000	551	4
3150000	850000	552	9
3150000	850000	553	5
3150000	850000	554	9
3150000	850000	555	15
3150000	850000	556	12
3150000	850000	557	13
3150000	850000	558	12
3150000	850000	559	12
3150000	850000	560	14
3150000	850000	561	14
3150000	850000	562	17
3150000	850000	563	11
3150000	850000	564	15
3150000	850000	565	8
3150000	850000	566	11
3150000	850000	567	17
3150000	850000	568	13
3150000	850000	569	12
3150000	850000	570	15
3150000	850000	571	18
3150000	850000	572	6
3150000	850000	573	16
3150000	850000	574	9
3150000	850000	575	10
3150000	850000	576	12
3150000	850000	577	9
3150000	850000	578	20
3150000	850000	579	12
3150000	850000	580	8
3150000	850000	581	17
3150000	850000	582	13
3150000	850000	583	16
3150000	850000	584	14
3150000	850000	585	17
3150000	850000	586	15
3150000	850000	587	16
3150000	850000	588	10
3150000	850000	589	20
3150000	850000	590	18
3150000	850000	591	9
3150000	850000	592	16
3150000	850000	593	10
3150000	850000	594	19
3150000	850000	595	12
3150000	850000	596	17
3150000	850000	597	6
3150000	850000	598	13
3150000	850000	599	13
3150000	850000	600	15
3150000	850000	601	15
3150000	850000	602	12
3150000	850000	603	14
3150000	850000	604	14
3150000	850000	605	11
3150000	850000	606	14
3150000	850000	607	11
3150000	850000	608	12
3150000	850000	609	16
3150000	850000	610	15
3150000	850000	611	11
3150000	850000	612	11
3150000	850000	613	19
3150000	850000	614	8
3150000	850000	615	9
3150000	850000	616	12
3150000	850000	617	12
3150000	850000	618	15
3150000	850000	619	10
3150000	850000	620	14
3150000	850000	621	17
3150000	850000	622	9
3150000	850000	623	14
3150000	850000	624	9
3150000	850000	625	8
3150000	850000	626	7
3150000	850000	627	17
3150000	850000	628	12
3150000	850000	629	12
3150000	850000	630	14
3150000	850000	631	9
3150000	850000	632	15
3150000	850000	633	10
3150000	850000	634	11
3150000	850000	635	11
3150000	850000	636	14
3150000	850000	637	13
3150000	850000	638	8
3150000	850000	639	14
3150000	850000	640	14
3150000	850000	641	20
3150000	850000	642	9
3150000	850000	643	12
3150000	850000	644	13
3150000	850000	645	12
3150000	850000	646	13
3150000	850000	647	8
3150000	850000	648	11
3150000	850000	649	9
3150000	850000	650	7
3150000	850000	651	11
3150000	850000	652	15
3150000	850000	653	18
3150000	850000	654	14
3150000	850000	655	4
3150000	850000	656	15
3150000	850000	657	15
3150000	850000	658	15
3150000	850000	659	10
3150000	850000	660	13
3150000	850000	661	20
3150000	850000	662	15
3150000	850000	663	9
3150000	850000	664	11
3150000	850000	665	13
3150000	850000	666	9
3150000	850000	667	16
3150000	850000	668	20
3150000	850000	669	14
3150000	850000	670	16
3150000	850000	671	16
3150000	850000	672	11
3150000	850000	673	19
3150000	850000	674	19
3150000	850000	675	14
3150000	850000	676	13
3150000	850000	677	6
3150000	850000	678	14
3150000	850000	679	17
3150000	850000	680	13
3150000	850000	681	14
3150000	850000	682	21
3150000	850000	683	17
3150000	850000	684	20
3150000	850000	685	15
3150000	850000	686	8
3150000	850000	687	12
3150000	850000	688	16
3150000	850000	689	19
3150000	850000	690	11
3150000	850000	691	9
3150000	850000	692	21
3150000	850000	693	11
3150000	850000	694	14
3150000	850000	695	16
3150000	850000	696	14
3150000	850000	697	18
3150000	850000	698	18
3150000	850000	699	23
3150000	850000	700	22
3150000	850000	701	18
3150000	850000	702	8
3150000	850000	703	16
3150000	850000	704	22
3150000	850000	705	22
3150000	850000	706	27
3150000	850000	707	14
3150000	850000	708	16
3150000	850000	709	32
3150000	850000	710	24
3150000	850000	711	10
3150000	850000	712	16
3150000	850000	713	19
3150000	850000	714	21
3150000	850000	715	22
3150000	850000	716	17
3150000	850000	717	19
3150000	850000	718	8
3150000	850000	719	16
3150000	850000	720	20
3150000	850000	721	17
3150000	850000	722	15
3150000	850000	723	9
3150000	850000	724	16
3150000	850000	725	15
3150000	850000	726	20
3150000	850000	727	14
3150000	850000	728	16
3150000	850000	729	14
3150000	850000	730	9
3150000	850000	731	16
3150000	850000	732	23
3150000	850000	733	12
3150000	850000	734	16
3150000	850000	735	18
3150000	850000	736	19
3150000	850000	737	10
3150000	850000	738	13
3150000	850000	739	20
3150000	850000	740	13
3150000	850000	741	14
3150000	850000	742	14
3150000	850000	743	17
3150000	850000	744	11
3150000	850000	745	12
3150000	850000	746	14
3150000	850000	747	17
3150000	850000	748	11
3150000	850000	749	13
3150000	850000	750	9
3150000	850000	751	16
3150000	850000	752	13
3150000	850000	753	10
3150000	850000	754	24
3150000	850000	755	12
3150000	850000	756	16
3150000	850000	757	9
3150000	850000	758	12
3150000	850000	759	9
3150000	850000	760	6
3150000	850000	761	9
3150000	850000	762	20
3150000	850000	763	11
3150000	850000	764	18
3150000	850000	765	9
3150000	850000	766	23
3150000	850000	767	15
3150000	850000	768	16
3150000	850000	769	19
3150000	850000	770	15
3150000	850000	771	7
3150000	850000	772	9
3150000	850000	773	16
3150000	850000	774	10
3150000	850000	775	11
3150000	850000	776	10
3150000	850000	777	15
3150000	850000	778	15
3150000	850000	779	11
3150000	850000	780	12
3150000	850000	781	18
3150000	850000	782	14
3150000	850000	783	13
3150000	850000	784	9
3150000	850000	785	8
3150000	850000	786	11
3150000	850000	787	9
3150000	850000	788	16
3150000	850000	789	18
3150000	850000	790	13
3150000	850000	791	16
3150000	850000	792	16
3150000	850000	793	19
3150000	850000	794	15
3150000	850000	795	15
3150000	850000	796	19
3150000	850000	797	8
3150000	850000	798	16
3150000	850000	799	14
3150000	850000	800	14
3150000	850000	801	10
3150000	850000	802	5
3150000	850000	803	13
3150000	850000	804	8
3150000	850000	805	10
3150000	850000	806	8
3150000	850000	807	14
3150000	850000	808	2
3150000	850000	809	17
3150000	850000	810	11
3150000	850000	811	11
3150000	850000	812	19
3150000	850000	813	18
3150000	850000	814	13
3150000	850000	815	13
3150000	850000	816	12
3150000	850000	817	13
3150000	850000	818	8
3150000	850000	819	15
3150000	850000	820	16
3150000	850000	821	13
3150000	850000	822	10
3150000	850000	823	8
3150000	850000	824	14
3150000	850000	825	5
3150000	850000	826	12
3150000	850000	827	13
3150000	850000	828	8
3150000	850000	829	13
3150000	850000	830	13
3150000	850000	831	22
3150000	850000	832	8
3150000	850000	833	9
3150000	850000	834	16
3150000	850000	835	15
3150000	850000	836	18
3150000	850000	837	8
3150000	850000	838	10
3150000	850000	839	7
3150000	850000	840	5
3150000	850000	841	10
3150000	850000	842	15
3150000	850000	843	11
3150000	850000	844	9
3150000	850000	845	15
3150000	850000	846	8
3150000	850000	847	15
3150000	850000	848	16
3150000	850000	849	6
3150000	850000	850	15
3150000	850000	851	19
3150000	850000	852	15
3150000	850000	853	23
3150000	850000	854	8
3150000	850000	855	13
3150000	850000	856	1
3150000	850000	857	15
3150000	850000	858	15
3150000	850000	859	14
3150000	850000	860	15
3150000	850000	861	8
3150000	850000	862	13
3150000	850000	863	10
3150000	850000	864	15
3150000	850000	865	13
3150000	850000	866	7
3150000	850000	867	16
3150000	850000	868	11
3150000	850000	869	17
3150000	850000	870	18
3150000	850000	871	11
3150000	850000	872	11
3150000	850000	873	15
3150000	850000	874	12
3150000	850000	875	9
3150000	850000	876	13
3150000	850000	877	10
3150000	850000	878	21
3150000	850000	879	12
3150000	850000	880	12
3150000	850000	881	13
3150000	850000	882	12
3150000	850000	883	16
3150000	850000	884	13
3150000	850000	885	14
3150000	850000	886	13
3150000	850000	887	11
3150000	850000	888	10
3150000	850000	889	11
3150000	850000	890	12
3150000	850000	891	13
3150000	850000	892	16
3150000	850000	893	11
3150000	850000	894	7
3150000	850000	895	8
3150000	850000	896	16
3150000	850000	897	10
3150000	850000	898	8
3150000	850000	899	9
3150000	850000	900	13
3150000	850000	901	9
3150000	850000	902	13
3150000	850000	903	13
3150000	850000	904	14
3150000	850000	905	11
3150000	850000	906	14
3150000	850000	907	10
3150000	850000	908	11
3150000	850000	909	13
3150000	850000	910	15
3150000	850000	911	15
3150000	850000	912	17
3150000	850000	913	6
3150000	850000	914	11
3150000	850000	915	12
3150000	850000	916	12
3150000	850000	917	14
3150000	850000	918	14
3150000	850000	919	8
3150000	850000	920	17
3150000	850000	921	14
3150000	850000	922	11
3150000	850000	923	18
3150000	850000	924	11
3150000	850000	925	7
3150000	850000	926	8
3150000	850000	927	7
3150000	850000	928	15
3150000	850000	929	12
3150000	850000	930	13
3150000	850000	931	7
3150000	850000	932	11
3150000	850000	933	10
3150000	850000	934	19
3150000	850000	935	13
3150000	850000	936	6
3150000	850000	937	10
3150000	850000	938	14
3150000	850000	939	11
3150000	850000	940	5
3150000	850000	941	5
3150000	850000	942	9
3150000	850000	943	8
3150000	850000	944	10
3150000	850000	945	18
3150000	850000	946	12
3150000	850000	947	14
3150000	850000	948	12
3150000	850000	949	12
3150000	850000	950	17
3150000	850000	951	6
3150000	850000	952	6
3150000	850000	953	14
3150000	850000	954	6
3150000	850000	955	14
3150000	850000	956	4
3150000	850000	957	8
3150000	850000	958	8
3150000	850000	959	12
3150000	850000	960	13
3150000	850000	961	13
3150000	850000	962	7
3150000	850000	963	24
3150000	850000	964	7
3150000	850000	965	15
3150000	850000	966	14
3150000	850000	967	8
3150000	850000	968	4
3150000	850000	969	9
3150000	850000	970	12
3150000	850000	971	6
3150000	850000	972	10
3150000	850000	973	13
3150000	850000	974	17
3150000	850000	975	9
3150000	850000	976	7
3150000	850000	977	7
3150000	850000	978	10
3150000	850000	979	12
3150000	850000	980	10
3150000	850000	981	7
3150000	850000	982	9
3150000	850000	983	7
3150000	850000	984	16
3150000	850000	985	11
3150000	850000	986	13
3150000	850000	987	10
3150000	850000	988	11
3150000	850000	989	6
3150000	850000	990	17
3150000	850000	991	11
3150000	850000	992	11
3150000	850000	993	15
3150000	850000	994	15
3150000	850000	995	10
3150000	850000	996	13
3150000	850000	997	8
3150000	850000	998	10
3150000	850000	999	9
3150000	950000	404	1
3150000	950000	405	2
3150000	950000	406	5
3150000	950000	407	3
3150000	950000	408	7
3150000	950000	409	11
3150000	950000	410	14
3150000	950000	411	19
3150000	950000	412	16
3150000	950000	413	21
3150000	950000	414	22
3150000	950000	415	24
3150000	950000	416	22
3150000	950000	417	32
3150000	950000	418	35
3150000	950000	419	38
3150000	950000	420	45
3150000	950000	421	48
3150000	950000	422	43
3150000	950000	423	45
3150000	950000	424	54
3150000	950000	425	48
3150000	950000	426	47
3150000	950000	427	37
3150000	950000	428	33
3150000	950000	429	37
3150000	950000	430	34
3150000	950000	431	29
3150000	950000	432	28
3150000	950000	433	39
3150000	950000	434	44
3150000	950000	435	37
3150000	950000	436	40
3150000	950000	437	43
3150000	950000	438	65
3150000	950000	439	71
3150000	950000	440	63
3150000	950000	441	63
3150000	950000	442	70
3150000	950000	443	79
3150000	950000	444	63
3150000	950000	445	51
3150000	950000	446	47
3150000	950000	447	46
3150000	950000	448	54
3150000	950000	449	60
3150000	950000	450	41
3150000	950000	451	50
3150000	950000	452	50
3150000	950000	453	63
3150000	950000	454	69
3150000	950000	455	56
3150000	950000	456	40
3150000	950000	457	57
3150000	950000	458	62
3150000	950000	459	58
3150000	950000	460	76
3150000	950000	461	50
3150000	950000	462	53
3150000	950000	463	57
3150000	950000	464	57
3150000	950000	465	65
3150000	950000	466	59
3150000	950000	467	61
3150000	950000	468	77
3150000	950000	469	38
3150000	950000	470	45
3150000	950000	471	49
3150000	950000	472	48
3150000	950000	473	42
3150000	950000	474	43
3150000	950000	475	60
3150000	950000	476	69
3150000	950000	477	54
3150000	950000	478	62
3150000	950000	479	54
3150000	950000	480	52
3150000	950000	481	53
3150000	950000	482	50
3150000	950000	483	49
3150000	950000	484	56
3150000	950000	485	50
3150000	950000	486	60
3150000	950000	487	63
3150000	950000	488	44
3150000	950000	489	78
3150000	950000	490	72
3150000	950000	491	69
3150000	950000	492	58
3150000	950000	493	56
3150000	950000	494	56
3150000	950000	495	66
3150000	950000	496	51
3150000	950000	497	53
3150000	950000	498	58
3150000	950000	499	64
3150000	950000	500	72
3150000	950000	501	57
3150000	950000	502	60
3150000	950000	503	61
3150000	950000	504	75
3150000	950000	505	50
3150000	950000	506	71
3150000	950000	507	70
3150000	950000	508	53
3150000	950000	509	63
3150000	950000	510	47
3150000	950000	511	53
3150000	950000	512	39
3150000	950000	513	46
3150000	950000	514	51
3150000	950000	515	41
3150000	950000	516	44
3150000	950000	517	43
3150000	950000	518	39
3150000	950000	519	40
3150000	950000	520	44
3150000	950000	521	31
3150000	950000	522	50
3150000	950000	523	51
3150000	950000	524	34
3150000	950000	525	32
3150000	950000	526	34
3150000	950000	527	36
3150000	950000	528	26
3150000	950000	529	34
3150000	950000	530	48
3150000	950000	531	43
3150000	950000	532	48
3150000	950000	533	48
3150000	950000	534	34
3150000	950000	535	43
3150000	950000	536	48
3150000	950000	537	34
3150000	950000	538	34
3150000	950000	539	40
3150000	950000	540	33
3150000	950000	541	31
3150000	950000	542	41
3150000	950000	543	43
3150000	950000	544	34
3150000	950000	545	25
3150000	950000	546	39
3150000	950000	547	30
3150000	950000	548	35
3150000	950000	549	29
3150000	950000	550	36
3150000	950000	551	33
3150000	950000	552	29
3150000	950000	553	24
3150000	950000	554	38
3150000	950000	555	35
3150000	950000	556	31
3150000	950000	557	35
3150000	950000	558	29
3150000	950000	559	32
3150000	950000	560	32
3150000	950000	561	30
3150000	950000	562	30
3150000	950000	563	24
3150000	950000	564	22
3150000	950000	565	29
3150000	950000	566	29
3150000	950000	567	22
3150000	950000	568	23
3150000	950000	569	29
3150000	950000	570	23
3150000	950000	571	22
3150000	950000	572	24
3150000	950000	573	24
3150000	950000	574	21
3150000	950000	575	19
3150000	950000	576	25
3150000	950000	577	20
3150000	950000	578	16
3150000	950000	579	21
3150000	950000	580	17
3150000	950000	581	24
3150000	950000	582	19
3150000	950000	583	21
3150000	950000	584	24
3150000	950000	585	33
3150000	950000	586	25
3150000	950000	587	25
3150000	950000	588	20
3150000	950000	589	28
3150000	950000	590	36
3150000	950000	591	30
3150000	950000	592	32
3150000	950000	593	25
3150000	950000	594	29
3150000	950000	595	23
3150000	950000	596	31
3150000	950000	597	33
3150000	950000	598	17
3150000	950000	599	24
3150000	950000	600	26
3150000	950000	601	31
3150000	950000	602	18
3150000	950000	603	24
3150000	950000	604	30
3150000	950000	605	23
3150000	950000	606	30
3150000	950000	607	33
3150000	950000	608	30
3150000	950000	609	19
3150000	950000	610	24
3150000	950000	611	25
3150000	950000	612	20
3150000	950000	613	14
3150000	950000	614	29
3150000	950000	615	22
3150000	950000	616	12
3150000	950000	617	22
3150000	950000	618	19
3150000	950000	619	11
3150000	950000	620	15
3150000	950000	621	18
3150000	950000	622	26
3150000	950000	623	13
3150000	950000	624	21
3150000	950000	625	16
3150000	950000	626	16
3150000	950000	627	20
3150000	950000	628	22
3150000	950000	629	15
3150000	950000	630	22
3150000	950000	631	27
3150000	950000	632	24
3150000	950000	633	23
3150000	950000	634	29
3150000	950000	635	16
3150000	950000	636	34
3150000	950000	637	25
3150000	950000	638	24
3150000	950000	639	25
3150000	950000	640	31
3150000	950000	641	20
3150000	950000	642	20
3150000	950000	643	18
3150000	950000	644	14
3150000	950000	645	25
3150000	950000	646	14
3150000	950000	647	22
3150000	950000	648	14
3150000	950000	649	20
3150000	950000	650	18
3150000	950000	651	19
3150000	950000	652	13
3150000	950000	653	17
3150000	950000	654	14
3150000	950000	655	22
3150000	950000	656	13
3150000	950000	657	9
3150000	950000	658	18
3150000	950000	659	6
3150000	950000	660	12
3150000	950000	661	22
3150000	950000	662	12
3150000	950000	663	16
3150000	950000	664	16
3150000	950000	665	12
3150000	950000	666	12
3150000	950000	667	10
3150000	950000	668	9
3150000	950000	669	16
3150000	950000	670	11
3150000	950000	671	12
3150000	950000	672	8
3150000	950000	673	11
3150000	950000	674	10
3150000	950000	675	6
3150000	950000	676	2
3150000	950000	677	11
3150000	950000	678	9
3150000	950000	679	6
3150000	950000	680	7
3150000	950000	681	7
3150000	950000	682	6
3150000	950000	683	4
3150000	950000	684	7
3150000	950000	685	3
3150000	950000	686	3
3150000	950000	687	13
3150000	950000	688	8
3150000	950000	689	6
3150000	950000	690	4
3150000	950000	691	4
3150000	950000	692	5
3150000	950000	693	9
3150000	950000	694	4
3150000	950000	695	4
3150000	950000	696	1
3150000	950000	697	4
3150000	950000	698	2
3150000	950000	699	4
3150000	950000	700	7
3150000	950000	701	10
3150000	950000	702	2
3150000	950000	703	4
3150000	950000	704	8
3150000	950000	705	2
3150000	950000	706	6
3150000	950000	707	6
3150000	950000	708	10
3150000	950000	709	8
3150000	950000	710	5
3150000	950000	711	3
3150000	950000	712	7
3150000	950000	713	4
3150000	950000	714	6
3150000	950000	715	2
3150000	950000	716	5
3150000	950000	717	5
3150000	950000	718	4
3150000	950000	719	7
3150000	950000	720	4
3150000	950000	721	4
3150000	950000	722	7
3150000	950000	723	9
3150000	950000	724	8
3150000	950000	725	7
3150000	950000	726	1
3150000	950000	727	5
3150000	950000	728	1
3150000	950000	729	6
3150000	950000	730	6
3150000	950000	732	3
3150000	950000	733	4
3150000	950000	734	2
3150000	950000	735	7
3150000	950000	736	5
3150000	950000	737	8
3150000	950000	738	4
3150000	950000	739	3
3150000	950000	740	3
3150000	950000	741	3
3150000	950000	742	5
3150000	950000	743	5
3150000	950000	744	8
3150000	950000	745	3
3150000	950000	746	4
3150000	950000	747	2
3150000	950000	748	1
3150000	950000	749	3
3150000	950000	750	1
3150000	950000	751	1
3150000	950000	752	7
3150000	950000	753	2
3150000	950000	754	2
3150000	950000	755	5
3150000	950000	756	2
3150000	950000	757	3
3150000	950000	758	2
3150000	950000	759	2
3150000	950000	760	3
3150000	950000	761	10
3150000	950000	762	2
3150000	950000	763	2
3150000	950000	764	1
3150000	950000	765	3
3150000	950000	766	1
3150000	950000	768	2
3150000	950000	770	3
3150000	950000	773	3
3150000	950000	774	1
3150000	950000	775	1
3150000	950000	776	1
3150000	950000	777	4
3150000	950000	778	2
3150000	950000	779	1
3150000	950000	780	1
3150000	950000	781	1
3150000	950000	782	2
3150000	950000	783	1
3150000	950000	784	1
3150000	950000	785	1
3150000	950000	790	1
3150000	950000	791	1
3150000	950000	793	1
3150000	950000	795	2
3150000	950000	796	2
3150000	950000	799	1
3150000	950000	800	1
3150000	950000	803	1
3150000	950000	804	1
3150000	950000	805	1
3150000	950000	811	2
3150000	950000	813	1
3150000	950000	814	1
3150000	950000	816	2
3150000	950000	821	1
3150000	950000	823	1
3150000	950000	827	1
3150000	950000	828	2
3150000	950000	835	1
3150000	950000	841	1
3150000	950000	857	1
3150000	950000	880	1
3150000	950000	912	1
3250000	1050000	453	8
3250000	1050000	454	17
3250000	1050000	455	12
3250000	1050000	456	12
3250000	1050000	457	10
3250000	1050000	458	7
3250000	1050000	459	14
3250000	1050000	460	10
3250000	1050000	461	18
3250000	1050000	462	9
3250000	1050000	463	13
3250000	1050000	464	19
3250000	1050000	465	16
3250000	1050000	466	25
3250000	1050000	467	27
3250000	1050000	468	12
3250000	1050000	469	17
3250000	1050000	470	24
3250000	1050000	471	20
3250000	1050000	472	23
3250000	1050000	473	24
3250000	1050000	474	21
3250000	1050000	475	28
3250000	1050000	476	41
3250000	1050000	477	55
3250000	1050000	478	59
3250000	1050000	479	63
3250000	1050000	480	71
3250000	1050000	481	80
3250000	1050000	482	67
3250000	1050000	483	65
3250000	1050000	484	60
3250000	1050000	485	57
3250000	1050000	486	57
3250000	1050000	487	63
3250000	1050000	488	62
3250000	1050000	489	52
3250000	1050000	490	53
3250000	1050000	491	54
3250000	1050000	492	47
3250000	1050000	493	63
3250000	1050000	494	50
3250000	1050000	495	46
3250000	1050000	496	44
3250000	1050000	497	59
3250000	1050000	498	49
3250000	1050000	499	37
3250000	1050000	500	40
3250000	1050000	501	51
3250000	1050000	502	41
3250000	1050000	503	33
3250000	1050000	504	57
3250000	1050000	505	43
3250000	1050000	506	50
3250000	1050000	507	51
3250000	1050000	508	41
3250000	1050000	509	37
3250000	1050000	510	48
3250000	1050000	511	40
3250000	1050000	512	32
3250000	1050000	513	43
3250000	1050000	514	53
3250000	1050000	515	44
3250000	1050000	516	58
3250000	1050000	517	60
3250000	1050000	518	62
3250000	1050000	519	59
3250000	1050000	520	68
3250000	1050000	521	70
3250000	1050000	522	100
3250000	1050000	523	100
3250000	1050000	524	72
3250000	1050000	525	73
3250000	1050000	526	90
3250000	1050000	527	75
3250000	1050000	528	94
3250000	1050000	529	99
3250000	1050000	530	101
3250000	1050000	531	93
3250000	1050000	532	93
3250000	1050000	533	88
3250000	1050000	534	98
3250000	1050000	535	104
3250000	1050000	536	114
3250000	1050000	537	89
3250000	1050000	538	109
3250000	1050000	539	89
3250000	1050000	540	94
3250000	1050000	541	91
3250000	1050000	542	108
3250000	1050000	543	91
3250000	1050000	544	66
3250000	1050000	545	93
3250000	1050000	546	57
3250000	1050000	547	56
3250000	1050000	548	62
3250000	1050000	549	71
3250000	1050000	550	51
3250000	1050000	551	56
3250000	1050000	552	61
3250000	1050000	553	59
3250000	1050000	554	81
3250000	1050000	555	73
3250000	1050000	556	96
3250000	1050000	557	69
3250000	1050000	558	59
3250000	1050000	559	69
3250000	1050000	560	67
3250000	1050000	561	68
3250000	1050000	562	63
3250000	1050000	563	41
3250000	1050000	564	53
3250000	1050000	565	61
3250000	1050000	566	52
3250000	1050000	567	53
3250000	1050000	568	47
3250000	1050000	569	52
3250000	1050000	570	47
3250000	1050000	571	53
3250000	1050000	572	59
3250000	1050000	573	57
3250000	1050000	574	41
3250000	1050000	575	45
3250000	1050000	576	54
3250000	1050000	577	47
3250000	1050000	578	43
3250000	1050000	579	48
3250000	1050000	580	37
3250000	1050000	581	48
3250000	1050000	582	36
3250000	1050000	583	43
3250000	1050000	584	47
3250000	1050000	585	37
3250000	1050000	586	36
3250000	1050000	587	38
3250000	1050000	588	32
3250000	1050000	589	33
3250000	1050000	590	30
3250000	1050000	591	26
3250000	1050000	592	34
3250000	1050000	593	26
3250000	1050000	594	32
3250000	1050000	595	29
3250000	1050000	596	28
3250000	1050000	597	27
3250000	1050000	598	21
3250000	1050000	599	19
3250000	1050000	600	25
3250000	1050000	601	19
3250000	1050000	602	25
3250000	1050000	603	18
3250000	1050000	604	25
3250000	1050000	605	22
3250000	1050000	606	33
3250000	1050000	607	27
3250000	1050000	608	20
3250000	1050000	609	22
3250000	1050000	610	20
3250000	1050000	611	21
3250000	1050000	612	24
3250000	1050000	613	26
3250000	1050000	614	28
3250000	1050000	615	27
3250000	1050000	616	24
3250000	1050000	617	33
3250000	1050000	618	26
3250000	1050000	619	28
3250000	1050000	620	26
3250000	1050000	621	22
3250000	1050000	622	17
3250000	1050000	623	20
3250000	1050000	624	26
3250000	1050000	625	19
3250000	1050000	626	17
3250000	1050000	627	22
3250000	1050000	628	24
3250000	1050000	629	19
3250000	1050000	630	29
3250000	1050000	631	18
3250000	1050000	632	24
3250000	1050000	633	21
3250000	1050000	634	34
3250000	1050000	635	17
3250000	1050000	636	22
3250000	1050000	637	17
3250000	1050000	638	19
3250000	1050000	639	18
3250000	1050000	640	17
3250000	1050000	641	18
3250000	1050000	642	20
3250000	1050000	643	16
3250000	1050000	644	23
3250000	1050000	645	18
3250000	1050000	646	17
3250000	1050000	647	23
3250000	1050000	648	20
3250000	1050000	649	17
3250000	1050000	650	17
3250000	1050000	651	25
3250000	1050000	652	18
3250000	1050000	653	13
3250000	1050000	654	15
3250000	1050000	655	17
3250000	1050000	656	17
3250000	1050000	657	19
3250000	1050000	658	13
3250000	1050000	659	10
3250000	1050000	660	31
3250000	1050000	661	17
3250000	1050000	662	17
3250000	1050000	663	17
3250000	1050000	664	25
3250000	1050000	665	20
3250000	1050000	666	15
3250000	1050000	667	18
3250000	1050000	668	16
3250000	1050000	669	19
3250000	1050000	670	15
3250000	1050000	671	33
3250000	1050000	672	20
3250000	1050000	673	23
3250000	1050000	674	17
3250000	1050000	675	21
3250000	1050000	676	13
3250000	1050000	677	18
3250000	1050000	678	15
3250000	1050000	679	13
3250000	1050000	680	12
3250000	1050000	681	23
3250000	1050000	682	26
3250000	1050000	683	14
3250000	1050000	684	14
3250000	1050000	685	21
3250000	1050000	686	17
3250000	1050000	687	10
3250000	1050000	688	13
3250000	1050000	689	13
3250000	1050000	690	15
3250000	1050000	691	21
3250000	1050000	692	16
3250000	1050000	693	15
3250000	1050000	694	6
3250000	1050000	695	8
3250000	1050000	696	13
3250000	1050000	697	18
3250000	1050000	698	18
3250000	1050000	699	10
3250000	1050000	700	9
3250000	1050000	701	16
3250000	1050000	702	13
3250000	1050000	703	9
3250000	1050000	704	12
3250000	1050000	705	11
3250000	1050000	706	12
3250000	1050000	707	6
3250000	1050000	708	8
3250000	1050000	709	10
3250000	1050000	710	4
3250000	1050000	711	15
3250000	1050000	712	5
3250000	1050000	713	12
3250000	1050000	714	7
3250000	1050000	715	8
3250000	1050000	716	2
3250000	1050000	717	11
3250000	1050000	718	3
3250000	1050000	719	3
3250000	1050000	720	4
3250000	1050000	721	1
3250000	1050000	722	11
3250000	1050000	723	3
3250000	1050000	724	8
3250000	1050000	725	3
3250000	1050000	726	8
3250000	1050000	727	7
3250000	1050000	728	6
3250000	1050000	729	1
3250000	1050000	730	10
3250000	1050000	731	4
3250000	1050000	732	2
3250000	1050000	733	4
3250000	1050000	734	6
3250000	1050000	735	2
3250000	1050000	736	2
3250000	1050000	737	4
3250000	1050000	738	1
3250000	1050000	739	3
3250000	1050000	740	4
3250000	1050000	741	7
3250000	1050000	742	5
3250000	1050000	743	6
3250000	1050000	744	4
3250000	1050000	745	4
3250000	1050000	746	5
3250000	1050000	747	3
3250000	1050000	748	1
3250000	1050000	749	1
3250000	1050000	750	1
3250000	1050000	751	4
3250000	1050000	752	1
3250000	1050000	753	1
3250000	1050000	754	4
3250000	1050000	755	2
3250000	1050000	757	2
3250000	1050000	758	3
3250000	1050000	759	2
3250000	1050000	760	2
3250000	1050000	761	4
3250000	1050000	763	1
3250000	1050000	764	2
3250000	1050000	765	1
3250000	1050000	766	1
3250000	1050000	768	1
3250000	1050000	769	1
3250000	1050000	770	2
3250000	1050000	771	1
3250000	1050000	775	1
3250000	1050000	778	1
3250000	1050000	779	2
3250000	1050000	780	1
3250000	1050000	782	1
3250000	1050000	783	2
3250000	1050000	784	1
3250000	1050000	785	1
3250000	1050000	786	1
3250000	1050000	788	2
3250000	1050000	791	1
3250000	1050000	793	1
3250000	1050000	794	2
3250000	1050000	801	1
3250000	1050000	823	1
3250000	1050000	836	1
3250000	650000	1000	3
3250000	650000	1001	3
3250000	650000	1002	1
3250000	650000	1004	2
3250000	650000	1005	2
3250000	650000	1006	1
3250000	650000	1007	2
3250000	650000	1008	2
3250000	650000	1009	1
3250000	650000	1010	2
3250000	650000	1011	1
3250000	650000	1012	1
3250000	650000	1013	4
3250000	650000	1014	2
3250000	650000	1015	2
3250000	650000	1016	2
3250000	650000	1017	1
3250000	650000	1018	2
3250000	650000	1020	1
3250000	650000	1021	3
3250000	650000	1022	2
3250000	650000	1024	2
3250000	650000	1025	2
3250000	650000	1026	3
3250000	650000	1029	1
3250000	650000	1030	2
3250000	650000	1031	1
3250000	650000	1033	1
3250000	650000	1034	2
3250000	650000	1035	2
3250000	650000	1036	5
3250000	650000	1037	1
3250000	650000	1040	2
3250000	650000	1041	1
3250000	650000	1042	2
3250000	650000	1043	3
3250000	650000	1044	1
3250000	650000	1045	1
3250000	650000	1048	1
3250000	650000	1049	1
3250000	650000	1050	4
3250000	650000	1053	1
3250000	650000	1054	1
3250000	650000	1062	1
3250000	650000	1063	2
3250000	650000	1065	2
3250000	650000	1067	1
3250000	650000	1071	1
3250000	650000	1074	1
3250000	650000	1076	1
3250000	650000	1077	2
3250000	650000	1080	1
3250000	650000	1082	1
3250000	650000	1083	1
3250000	650000	1084	2
3250000	650000	1085	1
3250000	650000	1086	1
3250000	650000	1087	1
3250000	650000	1091	1
3250000	650000	1095	1
3250000	650000	1096	1
3250000	650000	1100	1
3250000	650000	1102	1
3250000	650000	1115	2
3250000	650000	1117	2
3250000	650000	1118	1
3250000	650000	1129	1
3250000	650000	1131	1
3250000	650000	1132	1
3250000	650000	1133	1
3250000	650000	1134	2
3250000	650000	1135	1
3250000	650000	1136	1
3250000	650000	1137	1
3250000	650000	1139	1
3250000	650000	1141	1
3250000	650000	1142	2
3250000	650000	1146	1
3250000	650000	1153	1
3250000	650000	1154	1
3250000	650000	1157	1
3250000	650000	1163	2
3250000	650000	1164	2
3250000	650000	1166	1
3250000	650000	1171	1
3250000	650000	1172	1
3250000	650000	1174	1
3250000	650000	1176	2
3250000	650000	1181	1
3250000	650000	644	6
3250000	650000	645	2
3250000	650000	646	4
3250000	650000	647	3
3250000	650000	648	5
3250000	650000	649	6
3250000	650000	650	3
3250000	650000	651	4
3250000	650000	652	5
3250000	650000	653	6
3250000	650000	654	6
3250000	650000	655	13
3250000	650000	656	8
3250000	650000	657	12
3250000	650000	658	13
3250000	650000	659	12
3250000	650000	660	16
3250000	650000	661	9
3250000	650000	662	12
3250000	650000	663	29
3250000	650000	664	14
3250000	650000	665	27
3250000	650000	666	21
3250000	650000	667	16
3250000	650000	668	15
3250000	650000	669	17
3250000	650000	670	8
3250000	650000	671	11
3250000	650000	672	11
3250000	650000	673	10
3250000	650000	674	9
3250000	650000	675	7
3250000	650000	676	15
3250000	650000	677	7
3250000	650000	678	9
3250000	650000	679	8
3250000	650000	680	8
3250000	650000	681	12
3250000	650000	682	6
3250000	650000	683	12
3250000	650000	684	9
3250000	650000	685	6
3250000	650000	686	9
3250000	650000	687	3
3250000	650000	688	8
3250000	650000	689	6
3250000	650000	690	4
3250000	650000	691	7
3250000	650000	692	9
3250000	650000	693	4
3250000	650000	694	7
3250000	650000	695	5
3250000	650000	696	5
3250000	650000	697	2
3250000	650000	698	6
3250000	650000	699	9
3250000	650000	700	7
3250000	650000	701	12
3250000	650000	702	8
3250000	650000	703	7
3250000	650000	704	3
3250000	650000	705	9
3250000	650000	706	7
3250000	650000	707	4
3250000	650000	708	7
3250000	650000	709	6
3250000	650000	710	6
3250000	650000	711	3
3250000	650000	712	10
3250000	650000	713	5
3250000	650000	714	8
3250000	650000	715	7
3250000	650000	716	8
3250000	650000	717	10
3250000	650000	718	6
3250000	650000	719	7
3250000	650000	720	3
3250000	650000	721	7
3250000	650000	722	8
3250000	650000	723	4
3250000	650000	724	11
3250000	650000	725	7
3250000	650000	726	5
3250000	650000	727	5
3250000	650000	728	9
3250000	650000	729	11
3250000	650000	730	9
3250000	650000	731	7
3250000	650000	732	6
3250000	650000	733	13
3250000	650000	734	13
3250000	650000	735	6
3250000	650000	736	9
3250000	650000	737	8
3250000	650000	738	9
3250000	650000	739	5
3250000	650000	740	5
3250000	650000	741	6
3250000	650000	742	7
3250000	650000	743	4
3250000	650000	744	6
3250000	650000	745	14
3250000	650000	746	4
3250000	650000	747	8
3250000	650000	748	13
3250000	650000	749	5
3250000	650000	750	7
3250000	650000	751	5
3250000	650000	752	3
3250000	650000	753	9
3250000	650000	754	8
3250000	650000	755	5
3250000	650000	756	8
3250000	650000	757	13
3250000	650000	758	9
3250000	650000	759	12
3250000	650000	760	10
3250000	650000	761	5
3250000	650000	762	8
3250000	650000	763	9
3250000	650000	764	10
3250000	650000	765	13
3250000	650000	766	8
3250000	650000	767	13
3250000	650000	768	9
3250000	650000	769	7
3250000	650000	770	7
3250000	650000	771	16
3250000	650000	772	9
3250000	650000	773	9
3250000	650000	774	10
3250000	650000	775	11
3250000	650000	776	11
3250000	650000	777	15
3250000	650000	778	9
3250000	650000	779	12
3250000	650000	780	13
3250000	650000	781	8
3250000	650000	782	7
3250000	650000	783	15
3250000	650000	784	16
3250000	650000	785	8
3250000	650000	786	6
3250000	650000	787	9
3250000	650000	788	15
3250000	650000	789	7
3250000	650000	790	9
3250000	650000	791	13
3250000	650000	792	11
3250000	650000	793	13
3250000	650000	794	13
3250000	650000	795	19
3250000	650000	796	15
3250000	650000	797	14
3250000	650000	798	16
3250000	650000	799	14
3250000	650000	800	17
3250000	650000	801	15
3250000	650000	802	12
3250000	650000	803	14
3250000	650000	804	17
3250000	650000	805	21
3250000	650000	806	16
3250000	650000	807	19
3250000	650000	808	15
3250000	650000	809	12
3250000	650000	810	16
3250000	650000	811	19
3250000	650000	812	11
3250000	650000	813	17
3250000	650000	814	16
3250000	650000	815	18
3250000	650000	816	10
3250000	650000	817	9
3250000	650000	818	10
3250000	650000	819	14
3250000	650000	820	18
3250000	650000	821	14
3250000	650000	822	16
3250000	650000	823	19
3250000	650000	824	14
3250000	650000	825	19
3250000	650000	826	15
3250000	650000	827	17
3250000	650000	828	21
3250000	650000	829	14
3250000	650000	830	13
3250000	650000	831	15
3250000	650000	832	17
3250000	650000	833	7
3250000	650000	834	10
3250000	650000	835	16
3250000	650000	836	9
3250000	650000	837	10
3250000	650000	838	13
3250000	650000	839	10
3250000	650000	840	16
3250000	650000	841	11
3250000	650000	842	15
3250000	650000	843	8
3250000	650000	844	11
3250000	650000	845	10
3250000	650000	846	12
3250000	650000	847	5
3250000	650000	848	16
3250000	650000	849	11
3250000	650000	850	8
3250000	650000	851	10
3250000	650000	852	11
3250000	650000	853	9
3250000	650000	854	7
3250000	650000	855	12
3250000	650000	856	7
3250000	650000	857	6
3250000	650000	858	5
3250000	650000	859	11
3250000	650000	860	11
3250000	650000	861	13
3250000	650000	862	14
3250000	650000	863	11
3250000	650000	864	7
3250000	650000	865	6
3250000	650000	866	14
3250000	650000	867	3
3250000	650000	868	13
3250000	650000	869	11
3250000	650000	870	10
3250000	650000	871	5
3250000	650000	872	7
3250000	650000	873	8
3250000	650000	874	14
3250000	650000	875	5
3250000	650000	876	12
3250000	650000	877	8
3250000	650000	878	6
3250000	650000	879	7
3250000	650000	880	2
3250000	650000	881	11
3250000	650000	882	6
3250000	650000	883	8
3250000	650000	884	10
3250000	650000	885	4
3250000	650000	886	7
3250000	650000	887	3
3250000	650000	888	4
3250000	650000	889	4
3250000	650000	890	5
3250000	650000	891	5
3250000	650000	892	4
3250000	650000	893	5
3250000	650000	894	7
3250000	650000	895	8
3250000	650000	896	6
3250000	650000	897	7
3250000	650000	898	3
3250000	650000	899	2
3250000	650000	900	6
3250000	650000	901	4
3250000	650000	902	4
3250000	650000	903	6
3250000	650000	904	2
3250000	650000	905	5
3250000	650000	906	5
3250000	650000	907	7
3250000	650000	908	4
3250000	650000	909	1
3250000	650000	910	4
3250000	650000	911	6
3250000	650000	912	6
3250000	650000	913	6
3250000	650000	914	3
3250000	650000	915	2
3250000	650000	916	5
3250000	650000	917	4
3250000	650000	918	4
3250000	650000	919	6
3250000	650000	920	2
3250000	650000	921	2
3250000	650000	922	5
3250000	650000	923	3
3250000	650000	924	1
3250000	650000	925	3
3250000	650000	926	5
3250000	650000	927	1
3250000	650000	928	3
3250000	650000	929	1
3250000	650000	930	1
3250000	650000	931	4
3250000	650000	933	1
3250000	650000	934	2
3250000	650000	935	1
3250000	650000	936	2
3250000	650000	937	4
3250000	650000	938	2
3250000	650000	939	5
3250000	650000	940	2
3250000	650000	941	1
3250000	650000	942	5
3250000	650000	943	2
3250000	650000	945	4
3250000	650000	946	1
3250000	650000	947	3
3250000	650000	949	1
3250000	650000	950	3
3250000	650000	951	1
3250000	650000	952	2
3250000	650000	954	2
3250000	650000	955	3
3250000	650000	956	1
3250000	650000	957	2
3250000	650000	958	2
3250000	650000	959	1
3250000	650000	960	4
3250000	650000	961	1
3250000	650000	962	1
3250000	650000	963	4
3250000	650000	964	1
3250000	650000	965	5
3250000	650000	966	1
3250000	650000	967	3
3250000	650000	968	2
3250000	650000	969	2
3250000	650000	970	5
3250000	650000	971	1
3250000	650000	972	2
3250000	650000	973	1
3250000	650000	974	1
3250000	650000	975	3
3250000	650000	976	2
3250000	650000	977	2
3250000	650000	978	1
3250000	650000	979	2
3250000	650000	980	2
3250000	650000	981	1
3250000	650000	982	5
3250000	650000	984	2
3250000	650000	987	3
3250000	650000	989	1
3250000	650000	990	3
3250000	650000	991	3
3250000	650000	992	1
3250000	650000	993	2
3250000	650000	994	3
3250000	650000	995	1
3250000	650000	998	2
3250000	650000	999	3
3250000	750000	1000	12
3250000	750000	1001	17
3250000	750000	1002	11
3250000	750000	1003	11
3250000	750000	1004	8
3250000	750000	1005	10
3250000	750000	1006	10
3250000	750000	1007	15
3250000	750000	1008	9
3250000	750000	1009	7
3250000	750000	1010	18
3250000	750000	1011	13
3250000	750000	1012	12
3250000	750000	1013	14
3250000	750000	1014	15
3250000	750000	1015	11
3250000	750000	1016	9
3250000	750000	1017	20
3250000	750000	1018	13
3250000	750000	1019	15
3250000	750000	1020	19
3250000	750000	1021	6
3250000	750000	1022	16
3250000	750000	1023	11
3250000	750000	1024	13
3250000	750000	1025	19
3250000	750000	1026	18
3250000	750000	1027	10
3250000	750000	1028	8
3250000	750000	1029	12
3250000	750000	1030	9
3250000	750000	1031	14
3250000	750000	1032	8
3250000	750000	1033	11
3250000	750000	1034	11
3250000	750000	1035	8
3250000	750000	1036	10
3250000	750000	1037	9
3250000	750000	1038	9
3250000	750000	1039	18
3250000	750000	1040	14
3250000	750000	1041	7
3250000	750000	1042	9
3250000	750000	1043	13
3250000	750000	1044	9
3250000	750000	1045	9
3250000	750000	1046	12
3250000	750000	1047	6
3250000	750000	1048	15
3250000	750000	1049	10
3250000	750000	1050	12
3250000	750000	1051	8
3250000	750000	1052	6
3250000	750000	1053	7
3250000	750000	1054	7
3250000	750000	1055	13
3250000	750000	1056	9
3250000	750000	1057	15
3250000	750000	1058	17
3250000	750000	1059	8
3250000	750000	1060	13
3250000	750000	1061	7
3250000	750000	1062	8
3250000	750000	1063	8
3250000	750000	1064	8
3250000	750000	1065	13
3250000	750000	1066	5
3250000	750000	1067	10
3250000	750000	1068	14
3250000	750000	1069	7
3250000	750000	1070	6
3250000	750000	1071	12
3250000	750000	1072	9
3250000	750000	1073	8
3250000	750000	1074	5
3250000	750000	1075	13
3250000	750000	1076	6
3250000	750000	1077	10
3250000	750000	1078	8
3250000	750000	1079	8
3250000	750000	1080	8
3250000	750000	1081	4
3250000	750000	1082	9
3250000	750000	1083	7
3250000	750000	1084	10
3250000	750000	1085	4
3250000	750000	1086	6
3250000	750000	1087	11
3250000	750000	1088	6
3250000	750000	1089	11
3250000	750000	1090	6
3250000	750000	1091	5
3250000	750000	1092	9
3250000	750000	1093	9
3250000	750000	1094	5
3250000	750000	1095	8
3250000	750000	1096	9
3250000	750000	1097	14
3250000	750000	1098	6
3250000	750000	1099	7
3250000	750000	1100	5
3250000	750000	1101	8
3250000	750000	1102	6
3250000	750000	1103	9
3250000	750000	1104	4
3250000	750000	1105	6
3250000	750000	1106	4
3250000	750000	1107	10
3250000	750000	1108	7
3250000	750000	1109	4
3250000	750000	1110	1
3250000	750000	1111	9
3250000	750000	1112	10
3250000	750000	1113	6
3250000	750000	1114	6
3250000	750000	1115	8
3250000	750000	1116	8
3250000	750000	1117	8
3250000	750000	1118	7
3250000	750000	1119	2
3250000	750000	1120	5
3250000	750000	1121	4
3250000	750000	1122	5
3250000	750000	1123	6
3250000	750000	1124	2
3250000	750000	1125	5
3250000	750000	1126	3
3250000	750000	1127	6
3250000	750000	1128	9
3250000	750000	1129	7
3250000	750000	1130	4
3250000	750000	1131	4
3250000	750000	1132	6
3250000	750000	1133	7
3250000	750000	1134	4
3250000	750000	1135	6
3250000	750000	1136	3
3250000	750000	1137	1
3250000	750000	1138	8
3250000	750000	1139	4
3250000	750000	1140	6
3250000	750000	1141	5
3250000	750000	1142	3
3250000	750000	1143	4
3250000	750000	1144	4
3250000	750000	1145	3
3250000	750000	1146	6
3250000	750000	1147	2
3250000	750000	1148	4
3250000	750000	1150	7
3250000	750000	1151	5
3250000	750000	1152	4
3250000	750000	1153	9
3250000	750000	1154	2
3250000	750000	1155	5
3250000	750000	1156	1
3250000	750000	1157	2
3250000	750000	1158	6
3250000	750000	1159	3
3250000	750000	1160	5
3250000	750000	1161	3
3250000	750000	1162	3
3250000	750000	1163	4
3250000	750000	1164	5
3250000	750000	1165	2
3250000	750000	1166	4
3250000	750000	1167	2
3250000	750000	1168	3
3250000	750000	1169	2
3250000	750000	1170	3
3250000	750000	1171	3
3250000	750000	1172	2
3250000	750000	1173	3
3250000	750000	1174	3
3250000	750000	1175	5
3250000	750000	1176	5
3250000	750000	1177	5
3250000	750000	1178	2
3250000	750000	1179	4
3250000	750000	1180	2
3250000	750000	1182	5
3250000	750000	1183	2
3250000	750000	1184	4
3250000	750000	1185	3
3250000	750000	1186	5
3250000	750000	1187	2
3250000	750000	1188	6
3250000	750000	1189	4
3250000	750000	1191	2
3250000	750000	1192	5
3250000	750000	1193	3
3250000	750000	1194	3
3250000	750000	1196	3
3250000	750000	1197	2
3250000	750000	1200	3
3250000	750000	1201	6
3250000	750000	1202	2
3250000	750000	1203	2
3250000	750000	1205	5
3250000	750000	1206	2
3250000	750000	1207	1
3250000	750000	1209	7
3250000	750000	1210	3
3250000	750000	1211	1
3250000	750000	1212	1
3250000	750000	1213	5
3250000	750000	1214	2
3250000	750000	1215	7
3250000	750000	1216	6
3250000	750000	1217	4
3250000	750000	1218	3
3250000	750000	1220	4
3250000	750000	1221	4
3250000	750000	1222	2
3250000	750000	1223	2
3250000	750000	1224	1
3250000	750000	1225	1
3250000	750000	1226	1
3250000	750000	1227	2
3250000	750000	1229	4
3250000	750000	1230	3
3250000	750000	1231	5
3250000	750000	1232	4
3250000	750000	1233	2
3250000	750000	1234	3
3250000	750000	1235	4
3250000	750000	1236	9
3250000	750000	1238	2
3250000	750000	1239	1
3250000	750000	1240	5
3250000	750000	1241	5
3250000	750000	1242	1
3250000	750000	1243	4
3250000	750000	1244	3
3250000	750000	1245	1
3250000	750000	1247	5
3250000	750000	1248	4
3250000	750000	1249	3
3250000	750000	1250	3
3250000	750000	1251	4
3250000	750000	1252	1
3250000	750000	1254	1
3250000	750000	1255	2
3250000	750000	1257	4
3250000	750000	1258	2
3250000	750000	1259	2
3250000	750000	1260	3
3250000	750000	1261	2
3250000	750000	1262	3
3250000	750000	1263	1
3250000	750000	1265	3
3250000	750000	1266	2
3250000	750000	1267	3
3250000	750000	1268	6
3250000	750000	1270	2
3250000	750000	1271	2
3250000	750000	1272	5
3250000	750000	1275	3
3250000	750000	1276	3
3250000	750000	1277	2
3250000	750000	1278	1
3250000	750000	1279	1
3250000	750000	1281	4
3250000	750000	1282	3
3250000	750000	1283	3
3250000	750000	1284	1
3250000	750000	1285	2
3250000	750000	1286	1
3250000	750000	1287	2
3250000	750000	1288	2
3250000	750000	1289	1
3250000	750000	1290	1
3250000	750000	1291	4
3250000	750000	1292	1
3250000	750000	1293	1
3250000	750000	1294	2
3250000	750000	1295	2
3250000	750000	1296	1
3250000	750000	1297	1
3250000	750000	1298	3
3250000	750000	1299	2
3250000	750000	1300	4
3250000	750000	1301	2
3250000	750000	1302	2
3250000	750000	1303	3
3250000	750000	1304	1
3250000	750000	1305	3
3250000	750000	1307	2
3250000	750000	1309	1
3250000	750000	1310	2
3250000	750000	1311	2
3250000	750000	1312	3
3250000	750000	1314	3
3250000	750000	1315	2
3250000	750000	1316	3
3250000	750000	1317	3
3250000	750000	1318	4
3250000	750000	1319	4
3250000	750000	1320	7
3250000	750000	1321	3
3250000	750000	1322	1
3250000	750000	1323	2
3250000	750000	1324	1
3250000	750000	1325	7
3250000	750000	1326	5
3250000	750000	1327	1
3250000	750000	1328	6
3250000	750000	1329	3
3250000	750000	1330	2
3250000	750000	1331	1
3250000	750000	1332	2
3250000	750000	1333	3
3250000	750000	1335	2
3250000	750000	1336	1
3250000	750000	1339	3
3250000	750000	1340	5
3250000	750000	1341	4
3250000	750000	1342	2
3250000	750000	1343	3
3250000	750000	1345	2
3250000	750000	1346	2
3250000	750000	1347	2
3250000	750000	1348	3
3250000	750000	1349	2
3250000	750000	1350	5
3250000	750000	1351	2
3250000	750000	1352	1
3250000	750000	1353	1
3250000	750000	1354	5
3250000	750000	1355	1
3250000	750000	1356	2
3250000	750000	1358	1
3250000	750000	1359	3
3250000	750000	1360	3
3250000	750000	1361	3
3250000	750000	1362	2
3250000	750000	1363	4
3250000	750000	1364	1
3250000	750000	1365	1
3250000	750000	1366	1
3250000	750000	1368	3
3250000	750000	1369	1
3250000	750000	1370	3
3250000	750000	1371	1
3250000	750000	1373	1
3250000	750000	1375	1
3250000	750000	1376	3
3250000	750000	1378	1
3250000	750000	1379	1
3250000	750000	1380	4
3250000	750000	1383	1
3250000	750000	1384	4
3250000	750000	1385	1
3250000	750000	1386	6
3250000	750000	1388	2
3250000	750000	1389	2
3250000	750000	1390	1
3250000	750000	1391	1
3250000	750000	1395	2
3250000	750000	1396	1
3250000	750000	1398	2
3250000	750000	1399	1
3250000	750000	1400	2
3250000	750000	1401	1
3250000	750000	1402	2
3250000	750000	1403	1
3250000	750000	1404	3
3250000	750000	1405	1
3250000	750000	1407	1
3250000	750000	1409	3
3250000	750000	1410	4
3250000	750000	1411	2
3250000	750000	1414	2
3250000	750000	1415	1
3250000	750000	1417	2
3250000	750000	1419	1
3250000	750000	1420	1
3250000	750000	1421	2
3250000	750000	1423	4
3250000	750000	1426	1
3250000	750000	1427	2
3250000	750000	1428	3
3250000	750000	1430	1
3250000	750000	1431	2
3250000	750000	1433	1
3250000	750000	1434	1
3250000	750000	1436	2
3250000	750000	1438	1
3250000	750000	1439	1
3250000	750000	1440	3
3250000	750000	1442	1
3250000	750000	1443	2
3250000	750000	1445	1
3250000	750000	1446	3
3250000	750000	1447	4
3250000	750000	1448	2
3250000	750000	1450	3
3250000	750000	1453	2
3250000	750000	1455	1
3250000	750000	1457	3
3250000	750000	1459	2
3250000	750000	1460	1
3250000	750000	1461	1
3250000	750000	1463	2
3250000	750000	1465	2
3250000	750000	1466	2
3250000	750000	1468	2
3250000	750000	1470	2
3250000	750000	1472	2
3250000	750000	1473	4
3250000	750000	1474	3
3250000	750000	1475	1
3250000	750000	1476	3
3250000	750000	1477	1
3250000	750000	1478	1
3250000	750000	1480	2
3250000	750000	1482	3
3250000	750000	1483	1
3250000	750000	1484	1
3250000	750000	1485	1
3250000	750000	1486	1
3250000	750000	1487	2
3250000	750000	1489	2
3250000	750000	1491	1
3250000	750000	1495	4
3250000	750000	1496	4
3250000	750000	1498	3
3250000	750000	1500	2
3250000	750000	1502	1
3250000	750000	1504	1
3250000	750000	1505	2
3250000	750000	1509	3
3250000	750000	1510	1
3250000	750000	1511	1
3250000	750000	1512	2
3250000	750000	1514	2
3250000	750000	1515	2
3250000	750000	1517	1
3250000	750000	1518	1
3250000	750000	1519	2
3250000	750000	1521	1
3250000	750000	1523	1
3250000	750000	1526	1
3250000	750000	1527	1
3250000	750000	1529	3
3250000	750000	1530	1
3250000	750000	1531	1
3250000	750000	1532	2
3250000	750000	1534	3
3250000	750000	1535	1
3250000	750000	1536	2
3250000	750000	1537	2
3250000	750000	1540	1
3250000	750000	1541	1
3250000	750000	1544	1
3250000	750000	1547	3
3250000	750000	1548	1
3250000	750000	1549	1
3250000	750000	1551	1
3250000	750000	1554	2
3250000	750000	1558	1
3250000	750000	1559	1
3250000	750000	1560	2
3250000	750000	1563	2
3250000	750000	1564	1
3250000	750000	1568	1
3250000	750000	1569	1
3250000	750000	1570	4
3250000	750000	1571	1
3250000	750000	1572	1
3250000	750000	1576	1
3250000	750000	1581	2
3250000	750000	1582	2
3250000	750000	1583	3
3250000	750000	1591	1
3250000	750000	1593	1
3250000	750000	1594	1
3250000	750000	1595	1
3250000	750000	1596	2
3250000	750000	1597	2
3250000	750000	1600	1
3250000	750000	1601	2
3250000	750000	1604	1
3250000	750000	1605	1
3250000	750000	1606	1
3250000	750000	1607	1
3250000	750000	1608	2
3250000	750000	1609	1
3250000	750000	1611	1
3250000	750000	1612	1
3250000	750000	1614	2
3250000	750000	1617	1
3250000	750000	1620	1
3250000	750000	1621	1
3250000	750000	1623	1
3250000	750000	1626	2
3250000	750000	1627	2
3250000	750000	1629	1
3250000	750000	1631	1
3250000	750000	1635	1
3250000	750000	1637	2
3250000	750000	1638	1
3250000	750000	1641	1
3250000	750000	1642	2
3250000	750000	1643	1
3250000	750000	1651	1
3250000	750000	1656	1
3250000	750000	1658	1
3250000	750000	1660	1
3250000	750000	1664	1
3250000	750000	1667	1
3250000	750000	1669	2
3250000	750000	1670	1
3250000	750000	1671	2
3250000	750000	1675	1
3250000	750000	1683	3
3250000	750000	1686	1
3250000	750000	1687	1
3250000	750000	1690	1
3250000	750000	1691	1
3250000	750000	1697	1
3250000	750000	1698	1
3250000	750000	1700	3
3250000	750000	1702	1
3250000	750000	1704	2
3250000	750000	1707	1
3250000	750000	1710	1
3250000	750000	1711	1
3250000	750000	1719	2
3250000	750000	1728	2
3250000	750000	1731	1
3250000	750000	1735	2
3250000	750000	1736	1
3250000	750000	1738	1
3250000	750000	1740	3
3250000	750000	1744	1
3250000	750000	1745	1
3250000	750000	1746	2
3250000	750000	1748	2
3250000	750000	1749	1
3250000	750000	1753	1
3250000	750000	1754	1
3250000	750000	1755	1
3250000	750000	1757	1
3250000	750000	1774	1
3250000	750000	1780	1
3250000	750000	1790	1
3250000	750000	1792	2
3250000	750000	1795	3
3250000	750000	1799	1
3250000	750000	1803	1
3250000	750000	1806	1
3250000	750000	1809	1
3250000	750000	1814	3
3250000	750000	1817	1
3250000	750000	1828	1
3250000	750000	1836	1
3250000	750000	1837	1
3250000	750000	1841	2
3250000	750000	1870	1
3250000	750000	1882	1
3250000	750000	1909	1
3250000	750000	1919	3
3250000	750000	1921	2
3250000	750000	1923	1
3250000	750000	1934	1
3250000	750000	1981	1
3250000	750000	2000	1
3250000	750000	2002	1
3250000	750000	2010	1
3250000	750000	2017	2
3250000	750000	2032	1
3250000	750000	2124	1
3250000	750000	2196	1
3250000	750000	2203	1
3250000	750000	2224	1
3250000	750000	603	1
3250000	750000	606	1
3250000	750000	610	1
3250000	750000	612	1
3250000	750000	613	1
3250000	750000	615	1
3250000	750000	616	2
3250000	750000	617	3
3250000	750000	618	7
3250000	750000	619	5
3250000	750000	620	6
3250000	750000	621	4
3250000	750000	622	6
3250000	750000	623	5
3250000	750000	624	5
3250000	750000	625	4
3250000	750000	626	4
3250000	750000	627	10
3250000	750000	628	4
3250000	750000	629	6
3250000	750000	630	13
3250000	750000	631	5
3250000	750000	632	6
3250000	750000	633	5
3250000	750000	634	5
3250000	750000	635	3
3250000	750000	636	7
3250000	750000	637	8
3250000	750000	638	9
3250000	750000	639	8
3250000	750000	640	13
3250000	750000	641	8
3250000	750000	642	17
3250000	750000	643	16
3250000	750000	644	12
3250000	750000	645	15
3250000	750000	646	19
3250000	750000	647	15
3250000	750000	648	11
3250000	750000	649	23
3250000	750000	650	19
3250000	750000	651	21
3250000	750000	652	15
3250000	750000	653	14
3250000	750000	654	23
3250000	750000	655	20
3250000	750000	656	26
3250000	750000	657	17
3250000	750000	658	19
3250000	750000	659	16
3250000	750000	660	16
3250000	750000	661	18
3250000	750000	662	17
3250000	750000	663	24
3250000	750000	664	17
3250000	750000	665	16
3250000	750000	666	11
3250000	750000	667	19
3250000	750000	668	22
3250000	750000	669	30
3250000	750000	670	15
3250000	750000	671	17
3250000	750000	672	32
3250000	750000	673	22
3250000	750000	674	31
3250000	750000	675	16
3250000	750000	676	24
3250000	750000	677	18
3250000	750000	678	27
3250000	750000	679	29
3250000	750000	680	22
3250000	750000	681	33
3250000	750000	682	32
3250000	750000	683	25
3250000	750000	684	15
3250000	750000	685	21
3250000	750000	686	33
3250000	750000	687	24
3250000	750000	688	27
3250000	750000	689	32
3250000	750000	690	26
3250000	750000	691	20
3250000	750000	692	20
3250000	750000	693	30
3250000	750000	694	19
3250000	750000	695	18
3250000	750000	696	20
3250000	750000	697	29
3250000	750000	698	32
3250000	750000	699	30
3250000	750000	700	28
3250000	750000	701	31
3250000	750000	702	23
3250000	750000	703	32
3250000	750000	704	24
3250000	750000	705	18
3250000	750000	706	16
3250000	750000	707	25
3250000	750000	708	20
3250000	750000	709	28
3250000	750000	710	32
3250000	750000	711	21
3250000	750000	712	24
3250000	750000	713	18
3250000	750000	714	27
3250000	750000	715	22
3250000	750000	716	11
3250000	750000	717	15
3250000	750000	718	23
3250000	750000	719	19
3250000	750000	720	12
3250000	750000	721	26
3250000	750000	722	21
3250000	750000	723	21
3250000	750000	724	24
3250000	750000	725	16
3250000	750000	726	19
3250000	750000	727	28
3250000	750000	728	19
3250000	750000	729	17
3250000	750000	730	11
3250000	750000	731	15
3250000	750000	732	10
3250000	750000	733	19
3250000	750000	734	16
3250000	750000	735	25
3250000	750000	736	22
3250000	750000	737	12
3250000	750000	738	18
3250000	750000	739	25
3250000	750000	740	19
3250000	750000	741	15
3250000	750000	742	17
3250000	750000	743	14
3250000	750000	744	13
3250000	750000	745	26
3250000	750000	746	13
3250000	750000	747	15
3250000	750000	748	23
3250000	750000	749	18
3250000	750000	750	13
3250000	750000	751	10
3250000	750000	752	17
3250000	750000	753	24
3250000	750000	754	21
3250000	750000	755	20
3250000	750000	756	19
3250000	750000	757	26
3250000	750000	758	16
3250000	750000	759	11
3250000	750000	760	19
3250000	750000	761	14
3250000	750000	762	18
3250000	750000	763	13
3250000	750000	764	12
3250000	750000	765	10
3250000	750000	766	8
3250000	750000	767	13
3250000	750000	768	18
3250000	750000	769	25
3250000	750000	770	17
3250000	750000	771	18
3250000	750000	772	15
3250000	750000	773	12
3250000	750000	774	20
3250000	750000	775	23
3250000	750000	776	32
3250000	750000	777	20
3250000	750000	778	25
3250000	750000	779	11
3250000	750000	780	22
3250000	750000	781	21
3250000	750000	782	16
3250000	750000	783	15
3250000	750000	784	25
3250000	750000	785	25
3250000	750000	786	18
3250000	750000	787	14
3250000	750000	788	25
3250000	750000	789	21
3250000	750000	790	24
3250000	750000	791	22
3250000	750000	792	17
3250000	750000	793	22
3250000	750000	794	19
3250000	750000	795	21
3250000	750000	796	21
3250000	750000	797	30
3250000	750000	798	33
3250000	750000	799	33
3250000	750000	800	41
3250000	750000	801	30
3250000	750000	802	28
3250000	750000	803	25
3250000	750000	804	36
3250000	750000	805	26
3250000	750000	806	29
3250000	750000	807	33
3250000	750000	808	21
3250000	750000	809	34
3250000	750000	810	10
3250000	750000	811	36
3250000	750000	812	26
3250000	750000	813	36
3250000	750000	814	32
3250000	750000	815	35
3250000	750000	816	40
3250000	750000	817	42
3250000	750000	818	35
3250000	750000	819	34
3250000	750000	820	41
3250000	750000	821	30
3250000	750000	822	46
3250000	750000	823	41
3250000	750000	824	55
3250000	750000	825	33
3250000	750000	826	37
3250000	750000	827	45
3250000	750000	828	42
3250000	750000	829	37
3250000	750000	830	34
3250000	750000	831	46
3250000	750000	832	35
3250000	750000	833	27
3250000	750000	834	33
3250000	750000	835	50
3250000	750000	836	29
3250000	750000	837	27
3250000	750000	838	27
3250000	750000	839	45
3250000	750000	840	39
3250000	750000	841	42
3250000	750000	842	50
3250000	750000	843	38
3250000	750000	844	42
3250000	750000	845	37
3250000	750000	846	28
3250000	750000	847	27
3250000	750000	848	35
3250000	750000	849	36
3250000	750000	850	32
3250000	750000	851	34
3250000	750000	852	27
3250000	750000	853	20
3250000	750000	854	32
3250000	750000	855	28
3250000	750000	856	29
3250000	750000	857	28
3250000	750000	858	29
3250000	750000	859	30
3250000	750000	860	28
3250000	750000	861	20
3250000	750000	862	25
3250000	750000	863	27
3250000	750000	864	23
3250000	750000	865	35
3250000	750000	866	26
3250000	750000	867	24
3250000	750000	868	19
3250000	750000	869	17
3250000	750000	870	24
3250000	750000	871	24
3250000	750000	872	29
3250000	750000	873	29
3250000	750000	874	19
3250000	750000	875	26
3250000	750000	876	23
3250000	750000	877	21
3250000	750000	878	28
3250000	750000	879	22
3250000	750000	880	21
3250000	750000	881	11
3250000	750000	882	17
3250000	750000	883	25
3250000	750000	884	23
3250000	750000	885	24
3250000	750000	886	21
3250000	750000	887	20
3250000	750000	888	23
3250000	750000	889	24
3250000	750000	890	17
3250000	750000	891	13
3250000	750000	892	16
3250000	750000	893	22
3250000	750000	894	23
3250000	750000	895	20
3250000	750000	896	22
3250000	750000	897	19
3250000	750000	898	20
3250000	750000	899	13
3250000	750000	900	20
3250000	750000	901	18
3250000	750000	902	18
3250000	750000	903	28
3250000	750000	904	22
3250000	750000	905	12
3250000	750000	906	22
3250000	750000	907	15
3250000	750000	908	15
3250000	750000	909	18
3250000	750000	910	15
3250000	750000	911	20
3250000	750000	912	14
3250000	750000	913	15
3250000	750000	914	11
3250000	750000	915	18
3250000	750000	916	21
3250000	750000	917	15
3250000	750000	918	15
3250000	750000	919	23
3250000	750000	920	14
3250000	750000	921	13
3250000	750000	922	18
3250000	750000	923	14
3250000	750000	924	11
3250000	750000	925	16
3250000	750000	926	23
3250000	750000	927	21
3250000	750000	928	22
3250000	750000	929	14
3250000	750000	930	14
3250000	750000	931	14
3250000	750000	932	17
3250000	750000	933	16
3250000	750000	934	6
3250000	750000	935	9
3250000	750000	936	16
3250000	750000	937	11
3250000	750000	938	17
3250000	750000	939	14
3250000	750000	940	12
3250000	750000	941	22
3250000	750000	942	21
3250000	750000	943	26
3250000	750000	944	14
3250000	750000	945	14
3250000	750000	946	12
3250000	750000	947	11
3250000	750000	948	17
3250000	750000	949	10
3250000	750000	950	13
3250000	750000	951	21
3250000	750000	952	14
3250000	750000	953	12
3250000	750000	954	14
3250000	750000	955	17
3250000	750000	956	11
3250000	750000	957	13
3250000	750000	958	13
3250000	750000	959	18
3250000	750000	960	9
3250000	750000	961	13
3250000	750000	962	16
3250000	750000	963	11
3250000	750000	964	12
3250000	750000	965	10
3250000	750000	966	9
3250000	750000	967	13
3250000	750000	968	14
3250000	750000	969	18
3250000	750000	970	15
3250000	750000	971	11
3250000	750000	972	10
3250000	750000	973	12
3250000	750000	974	14
3250000	750000	975	10
3250000	750000	976	13
3250000	750000	977	15
3250000	750000	978	5
3250000	750000	979	10
3250000	750000	980	19
3250000	750000	981	16
3250000	750000	982	7
3250000	750000	983	14
3250000	750000	984	20
3250000	750000	985	12
3250000	750000	986	8
3250000	750000	987	8
3250000	750000	988	10
3250000	750000	989	12
3250000	750000	990	11
3250000	750000	991	8
3250000	750000	992	14
3250000	750000	993	8
3250000	750000	994	14
3250000	750000	995	13
3250000	750000	996	18
3250000	750000	997	13
3250000	750000	998	17
3250000	750000	999	8
3250000	850000	1000	15
3250000	850000	1001	12
3250000	850000	1002	13
3250000	850000	1003	12
3250000	850000	1004	15
3250000	850000	1005	17
3250000	850000	1006	14
3250000	850000	1007	15
3250000	850000	1008	16
3250000	850000	1009	13
3250000	850000	1010	14
3250000	850000	1011	15
3250000	850000	1012	15
3250000	850000	1013	17
3250000	850000	1014	21
3250000	850000	1015	16
3250000	850000	1016	22
3250000	850000	1017	20
3250000	850000	1018	21
3250000	850000	1019	18
3250000	850000	1020	17
3250000	850000	1021	15
3250000	850000	1022	13
3250000	850000	1023	8
3250000	850000	1024	9
3250000	850000	1025	16
3250000	850000	1026	8
3250000	850000	1027	15
3250000	850000	1028	16
3250000	850000	1029	12
3250000	850000	1030	12
3250000	850000	1031	14
3250000	850000	1032	11
3250000	850000	1033	10
3250000	850000	1034	16
3250000	850000	1035	13
3250000	850000	1036	17
3250000	850000	1037	12
3250000	850000	1038	8
3250000	850000	1039	21
3250000	850000	1040	7
3250000	850000	1041	20
3250000	850000	1042	8
3250000	850000	1043	12
3250000	850000	1044	14
3250000	850000	1045	11
3250000	850000	1046	10
3250000	850000	1047	11
3250000	850000	1048	12
3250000	850000	1049	16
3250000	850000	1050	10
3250000	850000	1051	12
3250000	850000	1052	30
3250000	850000	1053	17
3250000	850000	1054	9
3250000	850000	1055	16
3250000	850000	1056	15
3250000	850000	1057	16
3250000	850000	1058	11
3250000	850000	1059	14
3250000	850000	1060	9
3250000	850000	1061	13
3250000	850000	1062	20
3250000	850000	1063	14
3250000	850000	1064	18
3250000	850000	1065	13
3250000	850000	1066	10
3250000	850000	1067	13
3250000	850000	1068	17
3250000	850000	1069	14
3250000	850000	1070	12
3250000	850000	1071	17
3250000	850000	1072	8
3250000	850000	1073	8
3250000	850000	1074	10
3250000	850000	1075	9
3250000	850000	1076	15
3250000	850000	1077	13
3250000	850000	1078	13
3250000	850000	1079	16
3250000	850000	1080	8
3250000	850000	1081	15
3250000	850000	1082	18
3250000	850000	1083	10
3250000	850000	1084	16
3250000	850000	1085	15
3250000	850000	1086	15
3250000	850000	1087	16
3250000	850000	1088	9
3250000	850000	1089	24
3250000	850000	1090	9
3250000	850000	1091	17
3250000	850000	1092	10
3250000	850000	1093	13
3250000	850000	1094	17
3250000	850000	1095	11
3250000	850000	1096	10
3250000	850000	1097	18
3250000	850000	1098	14
3250000	850000	1099	17
3250000	850000	1100	10
3250000	850000	1101	21
3250000	850000	1102	12
3250000	850000	1103	11
3250000	850000	1104	10
3250000	850000	1105	12
3250000	850000	1106	9
3250000	850000	1107	15
3250000	850000	1108	19
3250000	850000	1109	15
3250000	850000	1110	20
3250000	850000	1111	16
3250000	850000	1112	9
3250000	850000	1113	14
3250000	850000	1114	11
3250000	850000	1115	17
3250000	850000	1116	18
3250000	850000	1117	10
3250000	850000	1118	20
3250000	850000	1119	11
3250000	850000	1120	10
3250000	850000	1121	16
3250000	850000	1122	9
3250000	850000	1123	9
3250000	850000	1124	13
3250000	850000	1125	15
3250000	850000	1126	9
3250000	850000	1127	11
3250000	850000	1128	9
3250000	850000	1129	7
3250000	850000	1130	20
3250000	850000	1131	11
3250000	850000	1132	13
3250000	850000	1133	11
3250000	850000	1134	10
3250000	850000	1135	10
3250000	850000	1136	13
3250000	850000	1137	15
3250000	850000	1138	9
3250000	850000	1139	13
3250000	850000	1140	11
3250000	850000	1141	18
3250000	850000	1142	4
3250000	850000	1143	13
3250000	850000	1144	22
3250000	850000	1145	7
3250000	850000	1146	17
3250000	850000	1147	10
3250000	850000	1148	12
3250000	850000	1149	2
3250000	850000	1150	8
3250000	850000	1151	12
3250000	850000	1152	16
3250000	850000	1153	16
3250000	850000	1154	6
3250000	850000	1155	9
3250000	850000	1156	20
3250000	850000	1157	15
3250000	850000	1158	9
3250000	850000	1159	20
3250000	850000	1160	11
3250000	850000	1161	12
3250000	850000	1162	10
3250000	850000	1163	10
3250000	850000	1164	16
3250000	850000	1165	18
3250000	850000	1166	12
3250000	850000	1167	11
3250000	850000	1168	12
3250000	850000	1169	12
3250000	850000	1170	14
3250000	850000	1171	13
3250000	850000	1172	11
3250000	850000	1173	11
3250000	850000	1174	14
3250000	850000	1175	12
3250000	850000	1176	16
3250000	850000	1177	9
3250000	850000	1178	12
3250000	850000	1179	14
3250000	850000	1180	17
3250000	850000	1181	11
3250000	850000	1182	12
3250000	850000	1183	17
3250000	850000	1184	18
3250000	850000	1185	13
3250000	850000	1186	9
3250000	850000	1187	19
3250000	850000	1188	6
3250000	850000	1189	16
3250000	850000	1190	7
3250000	850000	1191	9
3250000	850000	1192	12
3250000	850000	1193	16
3250000	850000	1194	9
3250000	850000	1195	16
3250000	850000	1196	4
3250000	850000	1197	12
3250000	850000	1198	17
3250000	850000	1199	8
3250000	850000	1200	9
3250000	850000	1201	9
3250000	850000	1202	10
3250000	850000	1203	13
3250000	850000	1204	12
3250000	850000	1205	10
3250000	850000	1206	10
3250000	850000	1207	18
3250000	850000	1208	11
3250000	850000	1209	9
3250000	850000	1210	10
3250000	850000	1211	15
3250000	850000	1212	7
3250000	850000	1213	9
3250000	850000	1214	17
3250000	850000	1215	18
3250000	850000	1216	11
3250000	850000	1217	11
3250000	850000	1218	9
3250000	850000	1219	17
3250000	850000	1220	15
3250000	850000	1221	9
3250000	850000	1222	10
3250000	850000	1223	7
3250000	850000	1224	12
3250000	850000	1225	15
3250000	850000	1226	9
3250000	850000	1227	11
3250000	850000	1228	10
3250000	850000	1229	9
3250000	850000	1230	15
3250000	850000	1231	12
3250000	850000	1232	11
3250000	850000	1233	4
3250000	850000	1234	17
3250000	850000	1235	8
3250000	850000	1236	12
3250000	850000	1237	8
3250000	850000	1238	11
3250000	850000	1239	7
3250000	850000	1240	13
3250000	850000	1241	14
3250000	850000	1242	11
3250000	850000	1243	13
3250000	850000	1244	11
3250000	850000	1245	13
3250000	850000	1246	11
3250000	850000	1247	8
3250000	850000	1248	5
3250000	850000	1249	8
3250000	850000	1250	11
3250000	850000	1251	13
3250000	850000	1252	6
3250000	850000	1253	11
3250000	850000	1254	10
3250000	850000	1255	1
3250000	850000	1256	15
3250000	850000	1257	8
3250000	850000	1258	11
3250000	850000	1259	5
3250000	850000	1260	8
3250000	850000	1261	16
3250000	850000	1262	6
3250000	850000	1263	5
3250000	850000	1264	11
3250000	850000	1265	4
3250000	850000	1266	6
3250000	850000	1267	7
3250000	850000	1268	8
3250000	850000	1269	5
3250000	850000	1270	9
3250000	850000	1271	12
3250000	850000	1272	11
3250000	850000	1273	10
3250000	850000	1274	14
3250000	850000	1275	8
3250000	850000	1276	10
3250000	850000	1277	8
3250000	850000	1278	8
3250000	850000	1279	7
3250000	850000	1280	11
3250000	850000	1281	4
3250000	850000	1282	10
3250000	850000	1283	5
3250000	850000	1284	10
3250000	850000	1285	11
3250000	850000	1286	6
3250000	850000	1287	5
3250000	850000	1288	8
3250000	850000	1289	3
3250000	850000	1290	8
3250000	850000	1291	9
3250000	850000	1292	7
3250000	850000	1293	8
3250000	850000	1294	12
3250000	850000	1295	7
3250000	850000	1296	9
3250000	850000	1297	8
3250000	850000	1298	11
3250000	850000	1299	6
3250000	850000	1300	9
3250000	850000	1301	10
3250000	850000	1302	5
3250000	850000	1303	8
3250000	850000	1304	8
3250000	850000	1305	7
3250000	850000	1306	21
3250000	850000	1307	3
3250000	850000	1308	4
3250000	850000	1309	6
3250000	850000	1310	8
3250000	850000	1311	5
3250000	850000	1312	6
3250000	850000	1313	4
3250000	850000	1314	7
3250000	850000	1315	5
3250000	850000	1316	5
3250000	850000	1317	5
3250000	850000	1318	8
3250000	850000	1319	13
3250000	850000	1320	5
3250000	850000	1321	13
3250000	850000	1322	9
3250000	850000	1323	9
3250000	850000	1324	3
3250000	850000	1325	8
3250000	850000	1326	7
3250000	850000	1327	3
3250000	850000	1328	3
3250000	850000	1329	3
3250000	850000	1330	4
3250000	850000	1331	6
3250000	850000	1332	2
3250000	850000	1333	2
3250000	850000	1334	10
3250000	850000	1335	7
3250000	850000	1336	5
3250000	850000	1337	9
3250000	850000	1338	6
3250000	850000	1339	3
3250000	850000	1340	7
3250000	850000	1341	3
3250000	850000	1342	5
3250000	850000	1343	7
3250000	850000	1344	6
3250000	850000	1345	5
3250000	850000	1346	3
3250000	850000	1347	4
3250000	850000	1348	3
3250000	850000	1349	3
3250000	850000	1350	6
3250000	850000	1352	5
3250000	850000	1353	4
3250000	850000	1354	3
3250000	850000	1355	5
3250000	850000	1356	7
3250000	850000	1357	3
3250000	850000	1358	8
3250000	850000	1359	2
3250000	850000	1360	4
3250000	850000	1361	9
3250000	850000	1362	4
3250000	850000	1363	4
3250000	850000	1364	4
3250000	850000	1365	8
3250000	850000	1366	5
3250000	850000	1367	4
3250000	850000	1368	4
3250000	850000	1369	2
3250000	850000	1370	5
3250000	850000	1371	6
3250000	850000	1372	6
3250000	850000	1373	4
3250000	850000	1374	2
3250000	850000	1375	4
3250000	850000	1376	4
3250000	850000	1377	1
3250000	850000	1378	4
3250000	850000	1379	8
3250000	850000	1380	2
3250000	850000	1381	6
3250000	850000	1382	4
3250000	850000	1383	4
3250000	850000	1384	4
3250000	850000	1385	10
3250000	850000	1386	2
3250000	850000	1387	3
3250000	850000	1388	6
3250000	850000	1389	3
3250000	850000	1390	3
3250000	850000	1392	2
3250000	850000	1393	8
3250000	850000	1394	1
3250000	850000	1395	3
3250000	850000	1396	5
3250000	850000	1397	6
3250000	850000	1398	5
3250000	850000	1399	2
3250000	850000	1400	6
3250000	850000	1401	2
3250000	850000	1402	3
3250000	850000	1403	3
3250000	850000	1404	3
3250000	850000	1405	8
3250000	850000	1406	3
3250000	850000	1407	5
3250000	850000	1408	6
3250000	850000	1409	4
3250000	850000	1410	1
3250000	850000	1411	2
3250000	850000	1412	5
3250000	850000	1413	5
3250000	850000	1414	3
3250000	850000	1415	4
3250000	850000	1416	5
3250000	850000	1417	3
3250000	850000	1418	5
3250000	850000	1419	1
3250000	850000	1420	2
3250000	850000	1421	2
3250000	850000	1422	2
3250000	850000	1423	4
3250000	850000	1424	5
3250000	850000	1425	5
3250000	850000	1426	6
3250000	850000	1427	3
3250000	850000	1428	1
3250000	850000	1429	3
3250000	850000	1430	9
3250000	850000	1431	6
3250000	850000	1432	2
3250000	850000	1433	5
3250000	850000	1434	5
3250000	850000	1435	4
3250000	850000	1436	7
3250000	850000	1437	3
3250000	850000	1438	4
3250000	850000	1439	5
3250000	850000	1440	2
3250000	850000	1441	4
3250000	850000	1442	2
3250000	850000	1443	7
3250000	850000	1444	5
3250000	850000	1445	5
3250000	850000	1446	4
3250000	850000	1447	5
3250000	850000	1448	3
3250000	850000	1449	2
3250000	850000	1450	2
3250000	850000	1451	3
3250000	850000	1452	3
3250000	850000	1453	2
3250000	850000	1454	6
3250000	850000	1455	3
3250000	850000	1456	2
3250000	850000	1457	2
3250000	850000	1458	5
3250000	850000	1459	5
3250000	850000	1460	3
3250000	850000	1461	4
3250000	850000	1462	3
3250000	850000	1463	2
3250000	850000	1464	2
3250000	850000	1465	2
3250000	850000	1466	6
3250000	850000	1467	5
3250000	850000	1468	10
3250000	850000	1469	2
3250000	850000	1470	2
3250000	850000	1471	1
3250000	850000	1472	5
3250000	850000	1473	6
3250000	850000	1474	2
3250000	850000	1475	4
3250000	850000	1476	5
3250000	850000	1477	2
3250000	850000	1478	2
3250000	850000	1479	4
3250000	850000	1480	1
3250000	850000	1481	1
3250000	850000	1482	4
3250000	850000	1483	6
3250000	850000	1484	5
3250000	850000	1485	5
3250000	850000	1486	3
3250000	850000	1487	4
3250000	850000	1488	2
3250000	850000	1489	2
3250000	850000	1490	7
3250000	850000	1491	2
3250000	850000	1492	6
3250000	850000	1493	10
3250000	850000	1494	8
3250000	850000	1495	6
3250000	850000	1496	7
3250000	850000	1497	2
3250000	850000	1498	7
3250000	850000	1499	3
3250000	850000	1500	4
3250000	850000	1501	3
3250000	850000	1502	1
3250000	850000	1503	3
3250000	850000	1504	5
3250000	850000	1505	1
3250000	850000	1506	3
3250000	850000	1507	5
3250000	850000	1508	2
3250000	850000	1509	5
3250000	850000	1511	2
3250000	850000	1512	3
3250000	850000	1513	1
3250000	850000	1515	3
3250000	850000	1517	1
3250000	850000	1518	2
3250000	850000	1519	4
3250000	850000	1520	4
3250000	850000	1521	7
3250000	850000	1522	3
3250000	850000	1523	4
3250000	850000	1524	4
3250000	850000	1525	5
3250000	850000	1526	2
3250000	850000	1527	1
3250000	850000	1528	2
3250000	850000	1529	2
3250000	850000	1530	1
3250000	850000	1531	4
3250000	850000	1532	4
3250000	850000	1533	3
3250000	850000	1535	4
3250000	850000	1537	1
3250000	850000	1538	3
3250000	850000	1539	6
3250000	850000	1540	3
3250000	850000	1542	5
3250000	850000	1543	2
3250000	850000	1544	3
3250000	850000	1545	2
3250000	850000	1547	2
3250000	850000	1548	2
3250000	850000	1549	3
3250000	850000	1550	1
3250000	850000	1551	1
3250000	850000	1552	3
3250000	850000	1553	3
3250000	850000	1554	4
3250000	850000	1555	2
3250000	850000	1556	9
3250000	850000	1557	6
3250000	850000	1558	4
3250000	850000	1559	4
3250000	850000	1560	2
3250000	850000	1561	1
3250000	850000	1562	6
3250000	850000	1563	4
3250000	850000	1565	2
3250000	850000	1566	3
3250000	850000	1567	4
3250000	850000	1568	4
3250000	850000	1569	4
3250000	850000	1570	5
3250000	850000	1571	1
3250000	850000	1572	3
3250000	850000	1573	3
3250000	850000	1574	3
3250000	850000	1575	3
3250000	850000	1576	2
3250000	850000	1577	3
3250000	850000	1578	2
3250000	850000	1579	3
3250000	850000	1580	1
3250000	850000	1581	2
3250000	850000	1582	6
3250000	850000	1583	2
3250000	850000	1584	5
3250000	850000	1585	3
3250000	850000	1586	7
3250000	850000	1587	4
3250000	850000	1588	3
3250000	850000	1589	3
3250000	850000	1590	5
3250000	850000	1591	1
3250000	850000	1592	6
3250000	850000	1593	2
3250000	850000	1594	5
3250000	850000	1595	5
3250000	850000	1596	4
3250000	850000	1597	2
3250000	850000	1598	1
3250000	850000	1599	3
3250000	850000	1600	2
3250000	850000	1601	2
3250000	850000	1602	2
3250000	850000	1603	5
3250000	850000	1604	5
3250000	850000	1605	4
3250000	850000	1606	2
3250000	850000	1607	2
3250000	850000	1608	3
3250000	850000	1609	5
3250000	850000	1610	7
3250000	850000	1612	3
3250000	850000	1613	3
3250000	850000	1614	5
3250000	850000	1615	3
3250000	850000	1616	3
3250000	850000	1617	3
3250000	850000	1618	4
3250000	850000	1619	3
3250000	850000	1621	5
3250000	850000	1622	5
3250000	850000	1623	6
3250000	850000	1624	3
3250000	850000	1625	2
3250000	850000	1626	5
3250000	850000	1628	5
3250000	850000	1629	2
3250000	850000	1630	5
3250000	850000	1631	5
3250000	850000	1632	1
3250000	850000	1633	6
3250000	850000	1634	4
3250000	850000	1635	2
3250000	850000	1636	6
3250000	850000	1637	1
3250000	850000	1639	1
3250000	850000	1640	5
3250000	850000	1641	5
3250000	850000	1642	2
3250000	850000	1643	5
3250000	850000	1644	4
3250000	850000	1645	2
3250000	850000	1646	5
3250000	850000	1647	1
3250000	850000	1648	4
3250000	850000	1649	2
3250000	850000	1650	1
3250000	850000	1651	2
3250000	850000	1652	5
3250000	850000	1653	4
3250000	850000	1654	1
3250000	850000	1656	1
3250000	850000	1657	1
3250000	850000	1658	1
3250000	850000	1659	1
3250000	850000	1660	2
3250000	850000	1661	1
3250000	850000	1662	3
3250000	850000	1663	2
3250000	850000	1664	3
3250000	850000	1665	4
3250000	850000	1667	2
3250000	850000	1668	2
3250000	850000	1669	5
3250000	850000	1670	4
3250000	850000	1671	6
3250000	850000	1672	1
3250000	850000	1673	1
3250000	850000	1674	2
3250000	850000	1675	1
3250000	850000	1676	1
3250000	850000	1677	1
3250000	850000	1678	2
3250000	850000	1679	5
3250000	850000	1680	3
3250000	850000	1682	2
3250000	850000	1683	2
3250000	850000	1684	1
3250000	850000	1685	4
3250000	850000	1686	3
3250000	850000	1687	2
3250000	850000	1688	4
3250000	850000	1689	2
3250000	850000	1690	2
3250000	850000	1691	4
3250000	850000	1692	1
3250000	850000	1693	6
3250000	850000	1694	3
3250000	850000	1695	3
3250000	850000	1696	1
3250000	850000	1697	3
3250000	850000	1698	1
3250000	850000	1699	2
3250000	850000	1700	1
3250000	850000	1701	2
3250000	850000	1702	2
3250000	850000	1703	3
3250000	850000	1704	4
3250000	850000	1705	4
3250000	850000	1706	2
3250000	850000	1707	4
3250000	850000	1708	3
3250000	850000	1709	6
3250000	850000	1710	4
3250000	850000	1711	3
3250000	850000	1712	4
3250000	850000	1713	3
3250000	850000	1714	6
3250000	850000	1715	2
3250000	850000	1716	7
3250000	850000	1717	1
3250000	850000	1718	7
3250000	850000	1719	1
3250000	850000	1720	4
3250000	850000	1721	3
3250000	850000	1722	2
3250000	850000	1723	2
3250000	850000	1724	7
3250000	850000	1725	1
3250000	850000	1726	5
3250000	850000	1727	5
3250000	850000	1729	2
3250000	850000	1730	2
3250000	850000	1731	7
3250000	850000	1732	1
3250000	850000	1733	3
3250000	850000	1734	4
3250000	850000	1735	2
3250000	850000	1736	1
3250000	850000	1739	3
3250000	850000	1740	4
3250000	850000	1742	4
3250000	850000	1745	3
3250000	850000	1746	7
3250000	850000	1747	3
3250000	850000	1748	2
3250000	850000	1749	2
3250000	850000	1750	4
3250000	850000	1751	3
3250000	850000	1752	1
3250000	850000	1753	1
3250000	850000	1754	5
3250000	850000	1755	4
3250000	850000	1756	3
3250000	850000	1757	1
3250000	850000	1758	2
3250000	850000	1759	5
3250000	850000	1760	1
3250000	850000	1761	1
3250000	850000	1762	1
3250000	850000	1763	4
3250000	850000	1764	4
3250000	850000	1766	3
3250000	850000	1767	2
3250000	850000	1768	5
3250000	850000	1769	1
3250000	850000	1770	9
3250000	850000	1771	2
3250000	850000	1772	2
3250000	850000	1773	3
3250000	850000	1774	2
3250000	850000	1775	4
3250000	850000	1776	3
3250000	850000	1778	4
3250000	850000	1779	4
3250000	850000	1780	3
3250000	850000	1781	3
3250000	850000	1782	3
3250000	850000	1783	3
3250000	850000	1784	3
3250000	850000	1785	2
3250000	850000	1786	1
3250000	850000	1787	3
3250000	850000	1789	5
3250000	850000	1790	2
3250000	850000	1791	3
3250000	850000	1792	10
3250000	850000	1793	3
3250000	850000	1794	2
3250000	850000	1795	2
3250000	850000	1796	4
3250000	850000	1797	1
3250000	850000	1798	4
3250000	850000	1799	1
3250000	850000	1800	2
3250000	850000	1801	1
3250000	850000	1802	1
3250000	850000	1803	1
3250000	850000	1804	1
3250000	850000	1806	3
3250000	850000	1807	2
3250000	850000	1808	1
3250000	850000	1810	1
3250000	850000	1811	1
3250000	850000	1812	1
3250000	850000	1813	2
3250000	850000	1814	1
3250000	850000	1815	2
3250000	850000	1816	4
3250000	850000	1817	4
3250000	850000	1818	8
3250000	850000	1820	5
3250000	850000	1821	1
3250000	850000	1822	1
3250000	850000	1823	1
3250000	850000	1824	4
3250000	850000	1826	3
3250000	850000	1827	3
3250000	850000	1828	1
3250000	850000	1829	2
3250000	850000	1831	2
3250000	850000	1832	4
3250000	850000	1833	2
3250000	850000	1834	2
3250000	850000	1835	3
3250000	850000	1836	2
3250000	850000	1837	4
3250000	850000	1838	2
3250000	850000	1839	2
3250000	850000	1840	2
3250000	850000	1841	2
3250000	850000	1842	3
3250000	850000	1843	1
3250000	850000	1844	3
3250000	850000	1845	4
3250000	850000	1846	4
3250000	850000	1847	2
3250000	850000	1848	3
3250000	850000	1849	1
3250000	850000	1851	5
3250000	850000	1852	3
3250000	850000	1853	1
3250000	850000	1854	1
3250000	850000	1855	5
3250000	850000	1856	1
3250000	850000	1857	1
3250000	850000	1858	1
3250000	850000	1859	1
3250000	850000	1860	4
3250000	850000	1861	1
3250000	850000	1862	3
3250000	850000	1864	1
3250000	850000	1865	2
3250000	850000	1866	2
3250000	850000	1867	1
3250000	850000	1868	7
3250000	850000	1869	1
3250000	850000	1870	2
3250000	850000	1872	4
3250000	850000	1875	2
3250000	850000	1876	2
3250000	850000	1877	3
3250000	850000	1878	2
3250000	850000	1879	2
3250000	850000	1880	1
3250000	850000	1881	5
3250000	850000	1882	2
3250000	850000	1883	1
3250000	850000	1884	2
3250000	850000	1885	1
3250000	850000	1886	3
3250000	850000	1887	3
3250000	850000	1890	2
3250000	850000	1891	3
3250000	850000	1892	1
3250000	850000	1893	1
3250000	850000	1894	1
3250000	850000	1896	1
3250000	850000	1897	5
3250000	850000	1898	2
3250000	850000	1899	1
3250000	850000	1900	4
3250000	850000	1901	1
3250000	850000	1902	2
3250000	850000	1903	3
3250000	850000	1905	2
3250000	850000	1906	1
3250000	850000	1907	2
3250000	850000	1908	1
3250000	850000	1909	3
3250000	850000	1910	1
3250000	850000	1911	1
3250000	850000	1912	1
3250000	850000	1913	2
3250000	850000	1914	4
3250000	850000	1915	2
3250000	850000	1916	2
3250000	850000	1917	1
3250000	850000	1918	1
3250000	850000	1919	1
3250000	850000	1920	1
3250000	850000	1921	3
3250000	850000	1922	1
3250000	850000	1923	2
3250000	850000	1924	2
3250000	850000	1925	4
3250000	850000	1926	1
3250000	850000	1927	1
3250000	850000	1928	1
3250000	850000	1929	1
3250000	850000	1931	3
3250000	850000	1932	2
3250000	850000	1935	2
3250000	850000	1937	4
3250000	850000	1938	4
3250000	850000	1940	2
3250000	850000	1941	1
3250000	850000	1942	3
3250000	850000	1943	2
3250000	850000	1944	1
3250000	850000	1945	4
3250000	850000	1946	3
3250000	850000	1947	1
3250000	850000	1948	4
3250000	850000	1949	4
3250000	850000	1950	2
3250000	850000	1952	3
3250000	850000	1953	2
3250000	850000	1955	4
3250000	850000	1957	2
3250000	850000	1959	4
3250000	850000	1960	1
3250000	850000	1962	1
3250000	850000	1963	2
3250000	850000	1965	1
3250000	850000	1966	1
3250000	850000	1967	1
3250000	850000	1968	1
3250000	850000	1969	2
3250000	850000	1970	2
3250000	850000	1971	3
3250000	850000	1973	6
3250000	850000	1975	1
3250000	850000	1977	4
3250000	850000	1978	1
3250000	850000	1982	3
3250000	850000	1983	2
3250000	850000	1986	1
3250000	850000	1987	2
3250000	850000	1988	2
3250000	850000	1990	2
3250000	850000	1991	2
3250000	850000	1993	1
3250000	850000	1997	1
3250000	850000	1998	1
3250000	850000	1999	4
3250000	850000	2000	1
3250000	850000	2002	1
3250000	850000	2003	3
3250000	850000	2004	2
3250000	850000	2005	1
3250000	850000	2006	1
3250000	850000	2008	1
3250000	850000	2009	1
3250000	850000	2013	1
3250000	850000	2014	3
3250000	850000	2016	2
3250000	850000	2017	1
3250000	850000	2018	1
3250000	850000	2019	1
3250000	850000	2020	1
3250000	850000	2021	1
3250000	850000	2023	3
3250000	850000	2025	1
3250000	850000	2027	1
3250000	850000	2029	1
3250000	850000	2030	1
3250000	850000	2032	1
3250000	850000	2033	2
3250000	850000	2034	3
3250000	850000	2036	1
3250000	850000	2039	3
3250000	850000	2042	3
3250000	850000	2044	1
3250000	850000	2045	3
3250000	850000	2047	1
3250000	850000	2049	3
3250000	850000	2050	3
3250000	850000	2051	3
3250000	850000	2054	1
3250000	850000	2056	1
3250000	850000	2057	1
3250000	850000	2058	1
3250000	850000	2059	3
3250000	850000	2060	2
3250000	850000	2063	2
3250000	850000	2066	2
3250000	850000	2068	3
3250000	850000	2070	1
3250000	850000	2071	1
3250000	850000	2074	1
3250000	850000	2075	2
3250000	850000	2081	2
3250000	850000	2082	2
3250000	850000	2083	1
3250000	850000	2084	3
3250000	850000	2086	1
3250000	850000	2087	1
3250000	850000	2088	1
3250000	850000	2089	1
3250000	850000	2091	1
3250000	850000	2094	1
3250000	850000	2095	1
3250000	850000	2096	1
3250000	850000	2102	2
3250000	850000	2103	1
3250000	850000	2104	1
3250000	850000	2105	2
3250000	850000	2107	2
3250000	850000	2109	1
3250000	850000	2113	1
3250000	850000	2114	2
3250000	850000	2115	2
3250000	850000	2117	1
3250000	850000	2120	1
3250000	850000	2121	1
3250000	850000	2124	2
3250000	850000	2125	1
3250000	850000	2127	1
3250000	850000	2129	2
3250000	850000	2132	2
3250000	850000	2133	2
3250000	850000	2134	1
3250000	850000	2135	1
3250000	850000	2136	1
3250000	850000	2140	1
3250000	850000	2145	1
3250000	850000	2148	1
3250000	850000	2149	1
3250000	850000	2153	2
3250000	850000	2157	1
3250000	850000	2159	1
3250000	850000	2161	1
3250000	850000	2162	2
3250000	850000	2164	1
3250000	850000	2165	3
3250000	850000	2167	1
3250000	850000	2169	1
3250000	850000	2171	1
3250000	850000	2172	1
3250000	850000	2173	1
3250000	850000	2174	3
3250000	850000	2175	1
3250000	850000	2176	1
3250000	850000	2177	1
3250000	850000	2178	1
3250000	850000	2181	1
3250000	850000	2183	1
3250000	850000	2184	2
3250000	850000	2186	1
3250000	850000	2188	1
3250000	850000	2191	1
3250000	850000	2193	1
3250000	850000	2195	1
3250000	850000	2196	4
3250000	850000	2197	2
3250000	850000	2198	1
3250000	850000	2199	3
3250000	850000	2200	1
3250000	850000	2207	1
3250000	850000	2210	1
3250000	850000	2212	1
3250000	850000	2213	1
3250000	850000	2214	1
3250000	850000	2217	2
3250000	850000	2218	3
3250000	850000	2223	2
3250000	850000	2224	1
3250000	850000	2226	1
3250000	850000	2227	1
3250000	850000	2233	1
3250000	850000	2234	2
3250000	850000	2236	2
3250000	850000	2237	1
3250000	850000	2241	2
3250000	850000	2245	1
3250000	850000	2246	1
3250000	850000	2253	2
3250000	850000	2254	2
3250000	850000	2259	1
3250000	850000	2260	3
3250000	850000	2261	1
3250000	850000	2263	2
3250000	850000	2265	1
3250000	850000	2266	2
3250000	850000	2270	2
3250000	850000	2271	1
3250000	850000	2276	2
3250000	850000	2279	2
3250000	850000	2281	1
3250000	850000	2285	1
3250000	850000	2288	1
3250000	850000	2300	2
3250000	850000	2301	1
3250000	850000	2303	2
3250000	850000	2305	2
3250000	850000	2306	2
3250000	850000	2310	1
3250000	850000	2311	1
3250000	850000	2313	2
3250000	850000	2314	1
3250000	850000	2317	2
3250000	850000	2320	1
3250000	850000	2323	1
3250000	850000	2325	2
3250000	850000	2328	1
3250000	850000	2335	1
3250000	850000	2338	1
3250000	850000	2342	1
3250000	850000	2345	1
3250000	850000	2346	1
3250000	850000	2348	1
3250000	850000	2350	1
3250000	850000	2353	1
3250000	850000	2358	1
3250000	850000	2362	1
3250000	850000	2364	1
3250000	850000	2372	1
3250000	850000	2373	1
3250000	850000	2374	1
3250000	850000	2375	1
3250000	850000	2379	1
3250000	850000	2380	1
3250000	850000	2394	1
3250000	850000	2396	1
3250000	850000	2397	1
3250000	850000	2401	2
3250000	850000	2408	1
3250000	850000	2413	1
3250000	850000	2418	1
3250000	850000	2419	1
3250000	850000	2420	1
3250000	850000	2421	1
3250000	850000	2422	1
3250000	850000	2427	1
3250000	850000	2430	1
3250000	850000	2431	2
3250000	850000	2433	1
3250000	850000	2442	1
3250000	850000	2443	1
3250000	850000	2447	1
3250000	850000	2448	1
3250000	850000	2455	1
3250000	850000	2458	1
3250000	850000	2464	1
3250000	850000	2473	1
3250000	850000	2481	1
3250000	850000	2487	1
3250000	850000	2493	1
3250000	850000	2496	1
3250000	850000	2497	1
3250000	850000	2504	1
3250000	850000	2508	1
3250000	850000	2516	1
3250000	850000	2525	1
3250000	850000	2536	1
3250000	850000	2548	2
3250000	850000	2561	1
3250000	850000	2588	2
3250000	850000	2591	1
3250000	850000	2611	1
3250000	850000	2612	1
3250000	850000	2663	1
3250000	850000	627	1
3250000	850000	645	1
3250000	850000	647	1
3250000	850000	649	1
3250000	850000	653	1
3250000	850000	659	3
3250000	850000	660	1
3250000	850000	671	1
3250000	850000	672	1
3250000	850000	676	1
3250000	850000	677	3
3250000	850000	679	3
3250000	850000	681	3
3250000	850000	685	1
3250000	850000	689	1
3250000	850000	690	1
3250000	850000	693	2
3250000	850000	695	1
3250000	850000	697	2
3250000	850000	700	1
3250000	850000	703	1
3250000	850000	706	1
3250000	850000	708	2
3250000	850000	711	3
3250000	850000	712	2
3250000	850000	713	2
3250000	850000	714	1
3250000	850000	715	1
3250000	850000	717	1
3250000	850000	718	2
3250000	850000	720	1
3250000	850000	725	2
3250000	850000	728	2
3250000	850000	729	1
3250000	850000	731	1
3250000	850000	733	3
3250000	850000	744	1
3250000	850000	745	1
3250000	850000	747	1
3250000	850000	750	1
3250000	850000	752	1
3250000	850000	753	1
3250000	850000	755	2
3250000	850000	757	1
3250000	850000	758	1
3250000	850000	760	4
3250000	850000	762	1
3250000	850000	764	1
3250000	850000	766	5
3250000	850000	767	3
3250000	850000	768	4
3250000	850000	769	2
3250000	850000	770	4
3250000	850000	771	5
3250000	850000	772	5
3250000	850000	773	5
3250000	850000	774	3
3250000	850000	775	2
3250000	850000	776	8
3250000	850000	777	3
3250000	850000	778	4
3250000	850000	779	2
3250000	850000	780	9
3250000	850000	781	3
3250000	850000	782	4
3250000	850000	783	4
3250000	850000	784	5
3250000	850000	785	6
3250000	850000	786	5
3250000	850000	787	4
3250000	850000	788	9
3250000	850000	789	10
3250000	850000	790	9
3250000	850000	791	10
3250000	850000	792	16
3250000	850000	793	9
3250000	850000	794	8
3250000	850000	795	9
3250000	850000	796	8
3250000	850000	797	17
3250000	850000	798	6
3250000	850000	799	13
3250000	850000	800	12
3250000	850000	801	13
3250000	850000	802	5
3250000	850000	803	3
3250000	850000	804	7
3250000	850000	805	13
3250000	850000	806	7
3250000	850000	807	4
3250000	850000	808	6
3250000	850000	809	11
3250000	850000	810	12
3250000	850000	811	14
3250000	850000	812	7
3250000	850000	813	11
3250000	850000	814	6
3250000	850000	815	8
3250000	850000	816	10
3250000	850000	817	9
3250000	850000	818	7
3250000	850000	819	13
3250000	850000	820	19
3250000	850000	821	11
3250000	850000	822	11
3250000	850000	823	4
3250000	850000	824	10
3250000	850000	825	13
3250000	850000	826	12
3250000	850000	827	13
3250000	850000	828	18
3250000	850000	829	19
3250000	850000	830	17
3250000	850000	831	5
3250000	850000	832	15
3250000	850000	833	18
3250000	850000	834	15
3250000	850000	835	11
3250000	850000	836	21
3250000	850000	837	16
3250000	850000	838	12
3250000	850000	839	17
3250000	850000	840	15
3250000	850000	841	18
3250000	850000	842	15
3250000	850000	843	11
3250000	850000	844	12
3250000	850000	845	12
3250000	850000	846	7
3250000	850000	847	5
3250000	850000	848	20
3250000	850000	849	17
3250000	850000	850	12
3250000	850000	851	10
3250000	850000	852	13
3250000	850000	853	15
3250000	850000	854	30
3250000	850000	855	13
3250000	850000	856	18
3250000	850000	857	27
3250000	850000	858	10
3250000	850000	859	28
3250000	850000	860	16
3250000	850000	861	19
3250000	850000	862	16
3250000	850000	863	17
3250000	850000	864	12
3250000	850000	865	23
3250000	850000	866	18
3250000	850000	867	14
3250000	850000	868	13
3250000	850000	869	12
3250000	850000	870	12
3250000	850000	871	36
3250000	850000	872	23
3250000	850000	873	20
3250000	850000	874	22
3250000	850000	875	24
3250000	850000	876	19
3250000	850000	877	15
3250000	850000	878	22
3250000	850000	879	23
3250000	850000	880	22
3250000	850000	881	15
3250000	850000	882	27
3250000	850000	883	15
3250000	850000	884	25
3250000	850000	885	23
3250000	850000	886	17
3250000	850000	887	13
3250000	850000	888	24
3250000	850000	889	19
3250000	850000	890	19
3250000	850000	891	12
3250000	850000	892	12
3250000	850000	893	25
3250000	850000	894	22
3250000	850000	895	19
3250000	850000	896	13
3250000	850000	897	25
3250000	850000	898	27
3250000	850000	899	27
3250000	850000	900	12
3250000	850000	901	15
3250000	850000	902	16
3250000	850000	903	19
3250000	850000	904	29
3250000	850000	905	17
3250000	850000	906	20
3250000	850000	907	21
3250000	850000	908	31
3250000	850000	909	38
3250000	850000	910	28
3250000	850000	911	27
3250000	850000	912	23
3250000	850000	913	21
3250000	850000	914	21
3250000	850000	915	23
3250000	850000	916	17
3250000	850000	917	31
3250000	850000	918	32
3250000	850000	919	29
3250000	850000	920	28
3250000	850000	921	23
3250000	850000	922	34
3250000	850000	923	27
3250000	850000	924	36
3250000	850000	925	21
3250000	850000	926	28
3250000	850000	927	32
3250000	850000	928	25
3250000	850000	929	34
3250000	850000	930	24
3250000	850000	931	27
3250000	850000	932	25
3250000	850000	933	20
3250000	850000	934	24
3250000	850000	935	24
3250000	850000	936	24
3250000	850000	937	28
3250000	850000	938	15
3250000	850000	939	30
3250000	850000	940	18
3250000	850000	941	20
3250000	850000	942	21
3250000	850000	943	24
3250000	850000	944	22
3250000	850000	945	17
3250000	850000	946	18
3250000	850000	947	21
3250000	850000	948	18
3250000	850000	949	23
3250000	850000	950	33
3250000	850000	951	20
3250000	850000	952	24
3250000	850000	953	23
3250000	850000	954	24
3250000	850000	955	23
3250000	850000	956	30
3250000	850000	957	17
3250000	850000	958	11
3250000	850000	959	14
3250000	850000	960	23
3250000	850000	961	22
3250000	850000	962	18
3250000	850000	963	16
3250000	850000	964	20
3250000	850000	965	15
3250000	850000	966	17
3250000	850000	967	16
3250000	850000	968	20
3250000	850000	969	25
3250000	850000	970	17
3250000	850000	971	15
3250000	850000	972	11
3250000	850000	973	22
3250000	850000	974	14
3250000	850000	975	26
3250000	850000	976	18
3250000	850000	977	23
3250000	850000	978	18
3250000	850000	979	16
3250000	850000	980	21
3250000	850000	981	18
3250000	850000	982	21
3250000	850000	983	15
3250000	850000	984	13
3250000	850000	985	12
3250000	850000	986	20
3250000	850000	987	15
3250000	850000	988	14
3250000	850000	989	19
3250000	850000	990	6
3250000	850000	991	18
3250000	850000	992	13
3250000	850000	993	12
3250000	850000	994	18
3250000	850000	995	16
3250000	850000	996	13
3250000	850000	997	17
3250000	850000	998	13
3250000	850000	999	11
3250000	950000	1000	6
3250000	950000	1001	8
3250000	950000	1002	9
3250000	950000	1003	6
3250000	950000	1004	6
3250000	950000	1005	9
3250000	950000	1006	15
3250000	950000	1007	8
3250000	950000	1008	11
3250000	950000	1009	10
3250000	950000	1010	5
3250000	950000	1011	8
3250000	950000	1012	10
3250000	950000	1013	8
3250000	950000	1014	5
3250000	950000	1015	7
3250000	950000	1016	12
3250000	950000	1017	11
3250000	950000	1018	11
3250000	950000	1019	3
3250000	950000	1020	8
3250000	950000	1021	10
3250000	950000	1022	9
3250000	950000	1023	13
3250000	950000	1024	7
3250000	950000	1025	15
3250000	950000	1026	8
3250000	950000	1027	4
3250000	950000	1028	4
3250000	950000	1029	3
3250000	950000	1030	8
3250000	950000	1031	8
3250000	950000	1032	6
3250000	950000	1033	6
3250000	950000	1034	4
3250000	950000	1035	16
3250000	950000	1036	7
3250000	950000	1037	6
3250000	950000	1038	7
3250000	950000	1039	5
3250000	950000	1040	6
3250000	950000	1041	3
3250000	950000	1042	4
3250000	950000	1043	8
3250000	950000	1044	10
3250000	950000	1045	5
3250000	950000	1046	5
3250000	950000	1047	5
3250000	950000	1048	4
3250000	950000	1049	8
3250000	950000	1050	2
3250000	950000	1051	10
3250000	950000	1052	3
3250000	950000	1053	5
3250000	950000	1054	2
3250000	950000	1055	4
3250000	950000	1056	7
3250000	950000	1057	3
3250000	950000	1058	5
3250000	950000	1059	8
3250000	950000	1060	7
3250000	950000	1061	8
3250000	950000	1062	2
3250000	950000	1063	3
3250000	950000	1064	5
3250000	950000	1065	7
3250000	950000	1066	4
3250000	950000	1067	5
3250000	950000	1068	4
3250000	950000	1069	6
3250000	950000	1070	8
3250000	950000	1071	8
3250000	950000	1072	4
3250000	950000	1073	4
3250000	950000	1074	5
3250000	950000	1075	2
3250000	950000	1076	3
3250000	950000	1077	3
3250000	950000	1078	6
3250000	950000	1079	1
3250000	950000	1080	2
3250000	950000	1081	11
3250000	950000	1082	4
3250000	950000	1083	5
3250000	950000	1084	5
3250000	950000	1085	3
3250000	950000	1086	1
3250000	950000	1087	5
3250000	950000	1088	3
3250000	950000	1089	2
3250000	950000	1090	1
3250000	950000	1091	3
3250000	950000	1092	5
3250000	950000	1093	7
3250000	950000	1094	7
3250000	950000	1095	3
3250000	950000	1097	5
3250000	950000	1099	1
3250000	950000	1100	1
3250000	950000	1101	5
3250000	950000	1102	1
3250000	950000	1103	8
3250000	950000	1104	2
3250000	950000	1105	4
3250000	950000	1106	4
3250000	950000	1107	1
3250000	950000	1108	4
3250000	950000	1109	9
3250000	950000	1110	8
3250000	950000	1111	4
3250000	950000	1112	8
3250000	950000	1113	3
3250000	950000	1114	4
3250000	950000	1115	6
3250000	950000	1116	3
3250000	950000	1117	4
3250000	950000	1118	2
3250000	950000	1119	5
3250000	950000	1120	3
3250000	950000	1121	11
3250000	950000	1122	2
3250000	950000	1123	8
3250000	950000	1124	3
3250000	950000	1125	4
3250000	950000	1126	3
3250000	950000	1127	3
3250000	950000	1128	3
3250000	950000	1129	3
3250000	950000	1130	5
3250000	950000	1131	1
3250000	950000	1132	2
3250000	950000	1133	3
3250000	950000	1134	4
3250000	950000	1135	3
3250000	950000	1136	6
3250000	950000	1137	3
3250000	950000	1138	2
3250000	950000	1139	2
3250000	950000	1140	1
3250000	950000	1141	6
3250000	950000	1142	4
3250000	950000	1143	1
3250000	950000	1144	3
3250000	950000	1145	6
3250000	950000	1146	9
3250000	950000	1147	6
3250000	950000	1148	3
3250000	950000	1149	1
3250000	950000	1151	3
3250000	950000	1152	3
3250000	950000	1153	1
3250000	950000	1154	5
3250000	950000	1155	2
3250000	950000	1156	2
3250000	950000	1157	7
3250000	950000	1158	3
3250000	950000	1159	7
3250000	950000	1160	2
3250000	950000	1161	6
3250000	950000	1162	2
3250000	950000	1163	2
3250000	950000	1164	7
3250000	950000	1165	3
3250000	950000	1166	7
3250000	950000	1167	1
3250000	950000	1168	2
3250000	950000	1169	2
3250000	950000	1170	5
3250000	950000	1171	7
3250000	950000	1172	4
3250000	950000	1173	3
3250000	950000	1174	4
3250000	950000	1175	1
3250000	950000	1176	4
3250000	950000	1177	4
3250000	950000	1178	5
3250000	950000	1179	2
3250000	950000	1180	5
3250000	950000	1181	1
3250000	950000	1182	2
3250000	950000	1183	2
3250000	950000	1184	2
3250000	950000	1185	3
3250000	950000	1186	5
3250000	950000	1187	5
3250000	950000	1188	5
3250000	950000	1189	2
3250000	950000	1190	1
3250000	950000	1191	5
3250000	950000	1192	7
3250000	950000	1193	1
3250000	950000	1194	7
3250000	950000	1195	2
3250000	950000	1196	3
3250000	950000	1197	1
3250000	950000	1198	2
3250000	950000	1199	3
3250000	950000	1200	2
3250000	950000	1201	3
3250000	950000	1202	4
3250000	950000	1203	1
3250000	950000	1204	6
3250000	950000	1206	1
3250000	950000	1207	2
3250000	950000	1208	7
3250000	950000	1209	2
3250000	950000	1210	1
3250000	950000	1211	3
3250000	950000	1212	4
3250000	950000	1213	5
3250000	950000	1214	3
3250000	950000	1215	5
3250000	950000	1216	3
3250000	950000	1217	3
3250000	950000	1218	4
3250000	950000	1219	12
3250000	950000	1220	4
3250000	950000	1221	3
3250000	950000	1222	2
3250000	950000	1223	3
3250000	950000	1224	2
3250000	950000	1225	2
3250000	950000	1226	2
3250000	950000	1227	3
3250000	950000	1228	1
3250000	950000	1229	2
3250000	950000	1231	3
3250000	950000	1232	4
3250000	950000	1233	3
3250000	950000	1234	4
3250000	950000	1235	5
3250000	950000	1236	3
3250000	950000	1237	3
3250000	950000	1238	7
3250000	950000	1239	6
3250000	950000	1240	1
3250000	950000	1241	1
3250000	950000	1242	4
3250000	950000	1243	4
3250000	950000	1244	3
3250000	950000	1245	3
3250000	950000	1246	5
3250000	950000	1247	7
3250000	950000	1248	4
3250000	950000	1249	1
3250000	950000	1250	3
3250000	950000	1251	6
3250000	950000	1252	6
3250000	950000	1253	3
3250000	950000	1254	4
3250000	950000	1255	2
3250000	950000	1256	3
3250000	950000	1257	2
3250000	950000	1258	1
3250000	950000	1259	4
3250000	950000	1260	4
3250000	950000	1261	3
3250000	950000	1262	2
3250000	950000	1263	3
3250000	950000	1264	3
3250000	950000	1265	1
3250000	950000	1267	1
3250000	950000	1268	3
3250000	950000	1269	1
3250000	950000	1270	5
3250000	950000	1272	3
3250000	950000	1273	8
3250000	950000	1274	2
3250000	950000	1275	7
3250000	950000	1276	2
3250000	950000	1277	2
3250000	950000	1278	5
3250000	950000	1279	2
3250000	950000	1280	3
3250000	950000	1281	2
3250000	950000	1282	3
3250000	950000	1284	3
3250000	950000	1285	1
3250000	950000	1286	2
3250000	950000	1287	4
3250000	950000	1288	7
3250000	950000	1289	3
3250000	950000	1290	2
3250000	950000	1291	1
3250000	950000	1292	1
3250000	950000	1293	5
3250000	950000	1294	3
3250000	950000	1295	4
3250000	950000	1296	3
3250000	950000	1297	2
3250000	950000	1298	2
3250000	950000	1299	6
3250000	950000	1300	1
3250000	950000	1301	4
3250000	950000	1302	3
3250000	950000	1303	6
3250000	950000	1304	3
3250000	950000	1307	3
3250000	950000	1309	6
3250000	950000	1310	1
3250000	950000	1311	5
3250000	950000	1312	1
3250000	950000	1313	5
3250000	950000	1314	2
3250000	950000	1315	2
3250000	950000	1316	2
3250000	950000	1317	2
3250000	950000	1318	5
3250000	950000	1319	4
3250000	950000	1320	5
3250000	950000	1321	4
3250000	950000	1322	2
3250000	950000	1323	2
3250000	950000	1324	3
3250000	950000	1325	1
3250000	950000	1326	3
3250000	950000	1327	1
3250000	950000	1328	1
3250000	950000	1329	3
3250000	950000	1330	5
3250000	950000	1331	1
3250000	950000	1332	6
3250000	950000	1333	1
3250000	950000	1334	2
3250000	950000	1335	1
3250000	950000	1336	3
3250000	950000	1337	2
3250000	950000	1338	3
3250000	950000	1339	2
3250000	950000	1342	2
3250000	950000	1343	2
3250000	950000	1344	3
3250000	950000	1345	2
3250000	950000	1346	4
3250000	950000	1347	2
3250000	950000	1348	1
3250000	950000	1349	3
3250000	950000	1350	5
3250000	950000	1351	2
3250000	950000	1352	1
3250000	950000	1353	1
3250000	950000	1354	1
3250000	950000	1356	3
3250000	950000	1357	4
3250000	950000	1358	1
3250000	950000	1360	5
3250000	950000	1361	1
3250000	950000	1362	1
3250000	950000	1363	3
3250000	950000	1364	4
3250000	950000	1365	2
3250000	950000	1366	4
3250000	950000	1367	1
3250000	950000	1368	1
3250000	950000	1369	3
3250000	950000	1370	5
3250000	950000	1371	1
3250000	950000	1372	1
3250000	950000	1373	3
3250000	950000	1374	8
3250000	950000	1375	3
3250000	950000	1376	2
3250000	950000	1377	1
3250000	950000	1378	1
3250000	950000	1379	4
3250000	950000	1380	1
3250000	950000	1381	5
3250000	950000	1384	4
3250000	950000	1385	2
3250000	950000	1386	2
3250000	950000	1388	1
3250000	950000	1389	2
3250000	950000	1392	1
3250000	950000	1394	1
3250000	950000	1396	2
3250000	950000	1397	1
3250000	950000	1398	5
3250000	950000	1399	3
3250000	950000	1400	3
3250000	950000	1401	2
3250000	950000	1403	1
3250000	950000	1405	2
3250000	950000	1406	1
3250000	950000	1409	3
3250000	950000	1410	1
3250000	950000	1412	1
3250000	950000	1413	2
3250000	950000	1414	3
3250000	950000	1415	1
3250000	950000	1416	2
3250000	950000	1417	2
3250000	950000	1418	1
3250000	950000	1420	2
3250000	950000	1421	2
3250000	950000	1422	3
3250000	950000	1424	1
3250000	950000	1425	1
3250000	950000	1426	2
3250000	950000	1427	1
3250000	950000	1428	2
3250000	950000	1429	2
3250000	950000	1431	2
3250000	950000	1432	2
3250000	950000	1433	2
3250000	950000	1435	1
3250000	950000	1438	2
3250000	950000	1440	1
3250000	950000	1441	1
3250000	950000	1442	3
3250000	950000	1443	2
3250000	950000	1445	2
3250000	950000	1446	1
3250000	950000	1447	1
3250000	950000	1448	3
3250000	950000	1450	1
3250000	950000	1451	1
3250000	950000	1453	2
3250000	950000	1454	2
3250000	950000	1457	1
3250000	950000	1459	1
3250000	950000	1460	1
3250000	950000	1461	1
3250000	950000	1463	1
3250000	950000	1464	2
3250000	950000	1466	1
3250000	950000	1467	1
3250000	950000	1468	3
3250000	950000	1469	2
3250000	950000	1471	1
3250000	950000	1472	1
3250000	950000	1475	2
3250000	950000	1476	1
3250000	950000	1477	2
3250000	950000	1478	1
3250000	950000	1480	1
3250000	950000	1481	1
3250000	950000	1482	1
3250000	950000	1485	2
3250000	950000	1486	2
3250000	950000	1487	2
3250000	950000	1488	1
3250000	950000	1490	2
3250000	950000	1494	3
3250000	950000	1495	1
3250000	950000	1496	1
3250000	950000	1497	1
3250000	950000	1498	2
3250000	950000	1499	3
3250000	950000	1500	2
3250000	950000	1502	2
3250000	950000	1503	1
3250000	950000	1505	2
3250000	950000	1508	1
3250000	950000	1510	1
3250000	950000	1512	3
3250000	950000	1515	1
3250000	950000	1516	2
3250000	950000	1517	1
3250000	950000	1520	2
3250000	950000	1524	1
3250000	950000	1525	2
3250000	950000	1532	3
3250000	950000	1533	1
3250000	950000	1534	1
3250000	950000	1535	1
3250000	950000	1537	5
3250000	950000	1538	1
3250000	950000	1541	2
3250000	950000	1545	2
3250000	950000	1550	1
3250000	950000	1553	2
3250000	950000	1555	1
3250000	950000	1563	1
3250000	950000	1564	1
3250000	950000	1570	2
3250000	950000	1667	1
3250000	950000	511	1
3250000	950000	512	1
3250000	950000	513	5
3250000	950000	514	1
3250000	950000	515	4
3250000	950000	516	2
3250000	950000	517	4
3250000	950000	518	7
3250000	950000	519	5
3250000	950000	520	5
3250000	950000	521	10
3250000	950000	522	11
3250000	950000	523	13
3250000	950000	524	15
3250000	950000	525	16
3250000	950000	526	10
3250000	950000	527	14
3250000	950000	528	13
3250000	950000	529	13
3250000	950000	530	8
3250000	950000	531	13
3250000	950000	532	9
3250000	950000	533	12
3250000	950000	534	9
3250000	950000	535	9
3250000	950000	536	4
3250000	950000	537	16
3250000	950000	538	8
3250000	950000	539	8
3250000	950000	540	11
3250000	950000	541	10
3250000	950000	542	11
3250000	950000	543	15
3250000	950000	544	14
3250000	950000	545	10
3250000	950000	546	16
3250000	950000	547	18
3250000	950000	548	8
3250000	950000	549	12
3250000	950000	550	11
3250000	950000	551	16
3250000	950000	552	10
3250000	950000	553	22
3250000	950000	554	10
3250000	950000	555	17
3250000	950000	556	7
3250000	950000	557	15
3250000	950000	558	20
3250000	950000	559	15
3250000	950000	560	9
3250000	950000	561	8
3250000	950000	562	11
3250000	950000	563	13
3250000	950000	564	17
3250000	950000	565	14
3250000	950000	566	14
3250000	950000	567	9
3250000	950000	568	21
3250000	950000	569	15
3250000	950000	570	11
3250000	950000	571	12
3250000	950000	572	16
3250000	950000	573	16
3250000	950000	574	18
3250000	950000	575	8
3250000	950000	576	12
3250000	950000	577	18
3250000	950000	578	20
3250000	950000	579	14
3250000	950000	580	12
3250000	950000	581	15
3250000	950000	582	20
3250000	950000	583	16
3250000	950000	584	18
3250000	950000	585	20
3250000	950000	586	14
3250000	950000	587	13
3250000	950000	588	16
3250000	950000	589	22
3250000	950000	590	21
3250000	950000	591	21
3250000	950000	592	26
3250000	950000	593	15
3250000	950000	594	26
3250000	950000	595	17
3250000	950000	596	18
3250000	950000	597	18
3250000	950000	598	20
3250000	950000	599	21
3250000	950000	600	24
3250000	950000	601	23
3250000	950000	602	30
3250000	950000	603	21
3250000	950000	604	27
3250000	950000	605	28
3250000	950000	606	32
3250000	950000	607	31
3250000	950000	608	21
3250000	950000	609	28
3250000	950000	610	30
3250000	950000	611	22
3250000	950000	612	31
3250000	950000	613	27
3250000	950000	614	28
3250000	950000	615	31
3250000	950000	616	22
3250000	950000	617	19
3250000	950000	618	28
3250000	950000	619	21
3250000	950000	620	18
3250000	950000	621	29
3250000	950000	622	20
3250000	950000	623	22
3250000	950000	624	29
3250000	950000	625	23
3250000	950000	626	31
3250000	950000	627	25
3250000	950000	628	22
3250000	950000	629	25
3250000	950000	630	17
3250000	950000	631	28
3250000	950000	632	16
3250000	950000	633	29
3250000	950000	634	26
3250000	950000	635	32
3250000	950000	636	20
3250000	950000	637	25
3250000	950000	638	30
3250000	950000	639	27
3250000	950000	640	23
3250000	950000	641	26
3250000	950000	642	25
3250000	950000	643	32
3250000	950000	644	26
3250000	950000	645	24
3250000	950000	646	28
3250000	950000	647	22
3250000	950000	648	20
3250000	950000	649	16
3250000	950000	650	33
3250000	950000	651	42
3250000	950000	652	19
3250000	950000	653	23
3250000	950000	654	31
3250000	950000	655	18
3250000	950000	656	29
3250000	950000	657	35
3250000	950000	658	26
3250000	950000	659	31
3250000	950000	660	31
3250000	950000	661	24
3250000	950000	662	29
3250000	950000	663	16
3250000	950000	664	37
3250000	950000	665	29
3250000	950000	666	39
3250000	950000	667	19
3250000	950000	668	31
3250000	950000	669	24
3250000	950000	670	27
3250000	950000	671	33
3250000	950000	672	22
3250000	950000	673	28
3250000	950000	674	39
3250000	950000	675	36
3250000	950000	676	48
3250000	950000	677	30
3250000	950000	678	35
3250000	950000	679	21
3250000	950000	680	31
3250000	950000	681	27
3250000	950000	682	33
3250000	950000	683	28
3250000	950000	684	28
3250000	950000	685	32
3250000	950000	686	38
3250000	950000	687	25
3250000	950000	688	17
3250000	950000	689	26
3250000	950000	690	17
3250000	950000	691	27
3250000	950000	692	24
3250000	950000	693	25
3250000	950000	694	20
3250000	950000	695	30
3250000	950000	696	29
3250000	950000	697	20
3250000	950000	698	19
3250000	950000	699	25
3250000	950000	700	28
3250000	950000	701	19
3250000	950000	702	18
3250000	950000	703	20
3250000	950000	704	23
3250000	950000	705	16
3250000	950000	706	26
3250000	950000	707	20
3250000	950000	708	15
3250000	950000	709	19
3250000	950000	710	17
3250000	950000	711	23
3250000	950000	712	17
3250000	950000	713	26
3250000	950000	714	15
3250000	950000	715	19
3250000	950000	716	16
3250000	950000	717	23
3250000	950000	718	28
3250000	950000	719	27
3250000	950000	720	21
3250000	950000	721	21
3250000	950000	722	19
3250000	950000	723	16
3250000	950000	724	23
3250000	950000	725	15
3250000	950000	726	19
3250000	950000	727	16
3250000	950000	728	15
3250000	950000	729	16
3250000	950000	730	20
3250000	950000	731	21
3250000	950000	732	10
3250000	950000	733	20
3250000	950000	734	15
3250000	950000	735	20
3250000	950000	736	17
3250000	950000	737	13
3250000	950000	738	12
3250000	950000	739	22
3250000	950000	740	14
3250000	950000	741	21
3250000	950000	742	15
3250000	950000	743	19
3250000	950000	744	22
3250000	950000	745	13
3250000	950000	746	16
3250000	950000	747	17
3250000	950000	748	23
3250000	950000	749	15
3250000	950000	750	23
3250000	950000	751	21
3250000	950000	752	7
3250000	950000	753	11
3250000	950000	754	14
3250000	950000	755	19
3250000	950000	756	13
3250000	950000	757	17
3250000	950000	758	15
3250000	950000	759	13
3250000	950000	760	19
3250000	950000	761	19
3250000	950000	762	14
3250000	950000	763	13
3250000	950000	764	18
3250000	950000	765	15
3250000	950000	766	9
3250000	950000	767	16
3250000	950000	768	18
3250000	950000	769	14
3250000	950000	770	16
3250000	950000	771	26
3250000	950000	772	11
3250000	950000	773	16
3250000	950000	774	21
3250000	950000	775	27
3250000	950000	776	10
3250000	950000	777	20
3250000	950000	778	13
3250000	950000	779	15
3250000	950000	780	14
3250000	950000	781	13
3250000	950000	782	16
3250000	950000	783	15
3250000	950000	784	20
3250000	950000	785	16
3250000	950000	786	11
3250000	950000	787	21
3250000	950000	788	21
3250000	950000	789	17
3250000	950000	790	11
3250000	950000	791	20
3250000	950000	792	12
3250000	950000	793	15
3250000	950000	794	12
3250000	950000	795	18
3250000	950000	796	15
3250000	950000	797	7
3250000	950000	798	17
3250000	950000	799	10
3250000	950000	800	16
3250000	950000	801	6
3250000	950000	802	16
3250000	950000	803	8
3250000	950000	804	9
3250000	950000	805	9
3250000	950000	806	15
3250000	950000	807	12
3250000	950000	808	13
3250000	950000	809	10
3250000	950000	810	9
3250000	950000	811	15
3250000	950000	812	5
3250000	950000	813	14
3250000	950000	814	7
3250000	950000	815	15
3250000	950000	816	10
3250000	950000	817	14
3250000	950000	818	19
3250000	950000	819	9
3250000	950000	820	13
3250000	950000	821	13
3250000	950000	822	12
3250000	950000	823	9
3250000	950000	824	17
3250000	950000	825	18
3250000	950000	826	18
3250000	950000	827	15
3250000	950000	828	12
3250000	950000	829	20
3250000	950000	830	19
3250000	950000	831	11
3250000	950000	832	17
3250000	950000	833	15
3250000	950000	834	23
3250000	950000	835	20
3250000	950000	836	14
3250000	950000	837	15
3250000	950000	838	13
3250000	950000	839	16
3250000	950000	840	18
3250000	950000	841	20
3250000	950000	842	10
3250000	950000	843	18
3250000	950000	844	18
3250000	950000	845	15
3250000	950000	846	15
3250000	950000	847	9
3250000	950000	848	5
3250000	950000	849	13
3250000	950000	850	13
3250000	950000	851	14
3250000	950000	852	13
3250000	950000	853	17
3250000	950000	854	10
3250000	950000	855	17
3250000	950000	856	16
3250000	950000	857	9
3250000	950000	858	22
3250000	950000	859	16
3250000	950000	860	17
3250000	950000	861	23
3250000	950000	862	22
3250000	950000	863	11
3250000	950000	864	12
3250000	950000	865	18
3250000	950000	866	23
3250000	950000	867	17
3250000	950000	868	11
3250000	950000	869	22
3250000	950000	870	12
3250000	950000	871	17
3250000	950000	872	12
3250000	950000	873	19
3250000	950000	874	21
3250000	950000	875	6
3250000	950000	876	15
3250000	950000	877	8
3250000	950000	878	14
3250000	950000	879	20
3250000	950000	880	10
3250000	950000	881	16
3250000	950000	882	18
3250000	950000	883	10
3250000	950000	884	16
3250000	950000	885	20
3250000	950000	886	17
3250000	950000	887	15
3250000	950000	888	16
3250000	950000	889	13
3250000	950000	890	19
3250000	950000	891	24
3250000	950000	892	12
3250000	950000	893	15
3250000	950000	894	9
3250000	950000	895	20
3250000	950000	896	15
3250000	950000	897	17
3250000	950000	898	19
3250000	950000	899	23
3250000	950000	900	13
3250000	950000	901	16
3250000	950000	902	18
3250000	950000	903	6
3250000	950000	904	9
3250000	950000	905	11
3250000	950000	906	13
3250000	950000	907	16
3250000	950000	908	8
3250000	950000	909	8
3250000	950000	910	21
3250000	950000	911	10
3250000	950000	912	20
3250000	950000	913	19
3250000	950000	914	8
3250000	950000	915	13
3250000	950000	916	16
3250000	950000	917	11
3250000	950000	918	13
3250000	950000	919	15
3250000	950000	920	7
3250000	950000	921	13
3250000	950000	922	16
3250000	950000	923	14
3250000	950000	924	15
3250000	950000	925	13
3250000	950000	926	15
3250000	950000	927	18
3250000	950000	928	8
3250000	950000	929	7
3250000	950000	930	14
3250000	950000	931	8
3250000	950000	932	14
3250000	950000	933	9
3250000	950000	934	15
3250000	950000	935	15
3250000	950000	936	15
3250000	950000	937	11
3250000	950000	938	10
3250000	950000	939	13
3250000	950000	940	11
3250000	950000	941	15
3250000	950000	942	12
3250000	950000	943	11
3250000	950000	944	15
3250000	950000	945	10
3250000	950000	946	16
3250000	950000	947	14
3250000	950000	948	17
3250000	950000	949	17
3250000	950000	950	14
3250000	950000	951	13
3250000	950000	952	15
3250000	950000	953	15
3250000	950000	954	13
3250000	950000	955	16
3250000	950000	956	13
3250000	950000	957	12
3250000	950000	958	12
3250000	950000	959	11
3250000	950000	960	8
3250000	950000	961	20
3250000	950000	962	22
3250000	950000	963	13
3250000	950000	964	12
3250000	950000	965	8
3250000	950000	966	22
3250000	950000	967	14
3250000	950000	968	22
3250000	950000	969	16
3250000	950000	970	10
3250000	950000	971	13
3250000	950000	972	10
3250000	950000	973	16
3250000	950000	974	17
3250000	950000	975	14
3250000	950000	976	12
3250000	950000	977	11
3250000	950000	978	9
3250000	950000	979	11
3250000	950000	980	12
3250000	950000	981	20
3250000	950000	982	13
3250000	950000	983	9
3250000	950000	984	10
3250000	950000	985	16
3250000	950000	986	13
3250000	950000	987	23
3250000	950000	988	10
3250000	950000	989	9
3250000	950000	990	13
3250000	950000	991	11
3250000	950000	992	12
3250000	950000	993	13
3250000	950000	994	11
3250000	950000	995	15
3250000	950000	996	6
3250000	950000	997	6
3250000	950000	998	9
3250000	950000	999	11
3350000	1050000	603	1
3350000	1050000	605	1
3350000	1050000	606	4
3350000	1050000	607	7
3350000	1050000	608	10
3350000	1050000	609	6
3350000	1050000	610	13
3350000	1050000	611	18
3350000	1050000	612	13
3350000	1050000	613	14
3350000	1050000	614	11
3350000	1050000	615	13
3350000	1050000	616	22
3350000	1050000	617	21
3350000	1050000	618	23
3350000	1050000	619	18
3350000	1050000	620	29
3350000	1050000	621	26
3350000	1050000	622	21
3350000	1050000	623	30
3350000	1050000	624	32
3350000	1050000	625	36
3350000	1050000	626	45
3350000	1050000	627	43
3350000	1050000	628	67
3350000	1050000	629	62
3350000	1050000	630	55
3350000	1050000	631	60
3350000	1050000	632	56
3350000	1050000	633	77
3350000	1050000	634	69
3350000	1050000	635	60
3350000	1050000	636	72
3350000	1050000	637	82
3350000	1050000	638	77
3350000	1050000	639	65
3350000	1050000	640	80
3350000	1050000	641	81
3350000	1050000	642	90
3350000	1050000	643	77
3350000	1050000	644	92
3350000	1050000	645	85
3350000	1050000	646	91
3350000	1050000	647	79
3350000	1050000	648	79
3350000	1050000	649	91
3350000	1050000	650	90
3350000	1050000	651	95
3350000	1050000	652	93
3350000	1050000	653	73
3350000	1050000	654	86
3350000	1050000	655	97
3350000	1050000	656	110
3350000	1050000	657	72
3350000	1050000	658	113
3350000	1050000	659	87
3350000	1050000	660	113
3350000	1050000	661	99
3350000	1050000	662	92
3350000	1050000	663	109
3350000	1050000	664	79
3350000	1050000	665	104
3350000	1050000	666	101
3350000	1050000	667	90
3350000	1050000	668	104
3350000	1050000	669	107
3350000	1050000	670	90
3350000	1050000	671	89
3350000	1050000	672	107
3350000	1050000	673	87
3350000	1050000	674	97
3350000	1050000	675	105
3350000	1050000	676	86
3350000	1050000	677	76
3350000	1050000	678	107
3350000	1050000	679	97
3350000	1050000	680	99
3350000	1050000	681	86
3350000	1050000	682	83
3350000	1050000	683	84
3350000	1050000	684	89
3350000	1050000	685	84
3350000	1050000	686	78
3350000	1050000	687	91
3350000	1050000	688	69
3350000	1050000	689	86
3350000	1050000	690	73
3350000	1050000	691	88
3350000	1050000	692	73
3350000	1050000	693	91
3350000	1050000	694	82
3350000	1050000	695	68
3350000	1050000	696	79
3350000	1050000	697	82
3350000	1050000	698	69
3350000	1050000	699	68
3350000	1050000	700	60
3350000	1050000	701	73
3350000	1050000	702	70
3350000	1050000	703	55
3350000	1050000	704	57
3350000	1050000	705	53
3350000	1050000	706	71
3350000	1050000	707	63
3350000	1050000	708	63
3350000	1050000	709	55
3350000	1050000	710	47
3350000	1050000	711	64
3350000	1050000	712	54
3350000	1050000	713	62
3350000	1050000	714	58
3350000	1050000	715	49
3350000	1050000	716	57
3350000	1050000	717	39
3350000	1050000	718	51
3350000	1050000	719	61
3350000	1050000	720	52
3350000	1050000	721	44
3350000	1050000	722	45
3350000	1050000	723	43
3350000	1050000	724	45
3350000	1050000	725	32
3350000	1050000	726	38
3350000	1050000	727	41
3350000	1050000	728	35
3350000	1050000	729	42
3350000	1050000	730	39
3350000	1050000	731	22
3350000	1050000	732	30
3350000	1050000	733	30
3350000	1050000	734	32
3350000	1050000	735	33
3350000	1050000	736	29
3350000	1050000	737	28
3350000	1050000	738	21
3350000	1050000	739	26
3350000	1050000	740	24
3350000	1050000	741	23
3350000	1050000	742	34
3350000	1050000	743	21
3350000	1050000	744	37
3350000	1050000	745	31
3350000	1050000	746	30
3350000	1050000	747	25
3350000	1050000	748	34
3350000	1050000	749	21
3350000	1050000	750	22
3350000	1050000	751	26
3350000	1050000	752	20
3350000	1050000	753	25
3350000	1050000	754	19
3350000	1050000	755	13
3350000	1050000	756	18
3350000	1050000	757	19
3350000	1050000	758	25
3350000	1050000	759	24
3350000	1050000	760	19
3350000	1050000	761	16
3350000	1050000	762	16
3350000	1050000	763	10
3350000	1050000	764	14
3350000	1050000	765	20
3350000	1050000	766	22
3350000	1050000	767	15
3350000	1050000	768	19
3350000	1050000	769	28
3350000	1050000	770	22
3350000	1050000	771	16
3350000	1050000	772	11
3350000	1050000	773	7
3350000	1050000	774	12
3350000	1050000	775	17
3350000	1050000	776	23
3350000	1050000	777	15
3350000	1050000	778	19
3350000	1050000	779	12
3350000	1050000	780	11
3350000	1050000	781	14
3350000	1050000	782	18
3350000	1050000	783	14
3350000	1050000	784	17
3350000	1050000	785	15
3350000	1050000	786	20
3350000	1050000	787	26
3350000	1050000	788	17
3350000	1050000	789	10
3350000	1050000	790	9
3350000	1050000	791	11
3350000	1050000	792	15
3350000	1050000	793	10
3350000	1050000	794	13
3350000	1050000	795	21
3350000	1050000	796	17
3350000	1050000	797	9
3350000	1050000	798	18
3350000	1050000	799	12
3350000	1050000	800	8
3350000	1050000	801	19
3350000	1050000	802	14
3350000	1050000	803	18
3350000	1050000	804	11
3350000	1050000	805	16
3350000	1050000	806	10
3350000	1050000	807	19
3350000	1050000	808	14
3350000	1050000	809	23
3350000	1050000	810	13
3350000	1050000	811	13
3350000	1050000	812	14
3350000	1050000	813	12
3350000	1050000	814	11
3350000	1050000	815	7
3350000	1050000	816	6
3350000	1050000	817	9
3350000	1050000	818	6
3350000	1050000	819	7
3350000	1050000	820	4
3350000	1050000	821	7
3350000	1050000	822	6
3350000	1050000	823	6
3350000	1050000	824	12
3350000	1050000	825	6
3350000	1050000	826	5
3350000	1050000	827	8
3350000	1050000	828	6
3350000	1050000	829	10
3350000	1050000	830	9
3350000	1050000	831	7
3350000	1050000	832	9
3350000	1050000	833	7
3350000	1050000	834	5
3350000	1050000	835	2
3350000	1050000	836	1
3350000	1050000	837	2
3350000	1050000	838	2
3350000	1050000	839	4
3350000	1050000	840	3
3350000	1050000	841	3
3350000	1050000	842	3
3350000	1050000	843	2
3350000	1050000	844	5
3350000	1050000	845	6
3350000	1050000	846	4
3350000	1050000	847	1
3350000	1050000	848	2
3350000	1050000	849	1
3350000	1050000	850	3
3350000	1050000	852	1
3350000	1050000	853	4
3350000	1050000	854	1
3350000	1050000	855	1
3350000	1050000	856	3
3350000	1050000	857	1
3350000	1050000	858	1
3350000	1050000	859	2
3350000	1050000	862	2
3350000	1050000	863	1
3350000	1050000	867	1
3350000	1050000	868	1
3350000	1050000	873	2
3350000	1050000	876	1
3350000	1050000	877	1
3350000	1050000	879	1
3350000	1050000	886	1
3350000	1050000	888	1
3350000	1050000	907	1
3350000	1050000	925	1
3350000	650000	1000	16
3350000	650000	1001	18
3350000	650000	1002	14
3350000	650000	1003	23
3350000	650000	1004	27
3350000	650000	1005	16
3350000	650000	1006	20
3350000	650000	1007	20
3350000	650000	1008	17
3350000	650000	1009	20
3350000	650000	1010	22
3350000	650000	1011	26
3350000	650000	1012	16
3350000	650000	1013	18
3350000	650000	1014	12
3350000	650000	1015	28
3350000	650000	1016	28
3350000	650000	1017	21
3350000	650000	1018	20
3350000	650000	1019	24
3350000	650000	1020	14
3350000	650000	1021	19
3350000	650000	1022	19
3350000	650000	1023	28
3350000	650000	1024	26
3350000	650000	1025	30
3350000	650000	1026	20
3350000	650000	1027	26
3350000	650000	1028	29
3350000	650000	1029	25
3350000	650000	1030	23
3350000	650000	1031	14
3350000	650000	1032	23
3350000	650000	1033	17
3350000	650000	1034	13
3350000	650000	1035	25
3350000	650000	1036	19
3350000	650000	1037	22
3350000	650000	1038	21
3350000	650000	1039	25
3350000	650000	1040	15
3350000	650000	1041	19
3350000	650000	1042	27
3350000	650000	1043	24
3350000	650000	1044	15
3350000	650000	1045	15
3350000	650000	1046	21
3350000	650000	1047	18
3350000	650000	1048	22
3350000	650000	1049	14
3350000	650000	1050	19
3350000	650000	1051	15
3350000	650000	1052	13
3350000	650000	1053	23
3350000	650000	1054	11
3350000	650000	1055	10
3350000	650000	1056	16
3350000	650000	1057	14
3350000	650000	1058	15
3350000	650000	1059	11
3350000	650000	1060	20
3350000	650000	1061	15
3350000	650000	1062	16
3350000	650000	1063	10
3350000	650000	1064	5
3350000	650000	1065	11
3350000	650000	1066	6
3350000	650000	1067	14
3350000	650000	1068	14
3350000	650000	1069	13
3350000	650000	1070	14
3350000	650000	1071	6
3350000	650000	1072	7
3350000	650000	1073	7
3350000	650000	1074	9
3350000	650000	1075	16
3350000	650000	1076	8
3350000	650000	1077	9
3350000	650000	1078	5
3350000	650000	1079	9
3350000	650000	1080	12
3350000	650000	1081	18
3350000	650000	1082	9
3350000	650000	1083	8
3350000	650000	1084	6
3350000	650000	1085	5
3350000	650000	1086	8
3350000	650000	1087	13
3350000	650000	1088	8
3350000	650000	1089	10
3350000	650000	1090	6
3350000	650000	1091	4
3350000	650000	1092	5
3350000	650000	1093	12
3350000	650000	1094	5
3350000	650000	1095	9
3350000	650000	1096	9
3350000	650000	1097	9
3350000	650000	1098	7
3350000	650000	1099	7
3350000	650000	1100	6
3350000	650000	1101	6
3350000	650000	1102	3
3350000	650000	1103	4
3350000	650000	1104	5
3350000	650000	1105	3
3350000	650000	1106	3
3350000	650000	1107	11
3350000	650000	1108	8
3350000	650000	1109	6
3350000	650000	1110	5
3350000	650000	1111	1
3350000	650000	1112	8
3350000	650000	1113	5
3350000	650000	1114	3
3350000	650000	1115	3
3350000	650000	1116	2
3350000	650000	1117	4
3350000	650000	1118	2
3350000	650000	1119	2
3350000	650000	1120	5
3350000	650000	1121	3
3350000	650000	1122	3
3350000	650000	1123	4
3350000	650000	1124	6
3350000	650000	1125	1
3350000	650000	1126	4
3350000	650000	1127	4
3350000	650000	1128	3
3350000	650000	1129	3
3350000	650000	1130	5
3350000	650000	1132	3
3350000	650000	1133	4
3350000	650000	1134	2
3350000	650000	1135	4
3350000	650000	1137	4
3350000	650000	1138	1
3350000	650000	1139	1
3350000	650000	1140	4
3350000	650000	1141	1
3350000	650000	1142	3
3350000	650000	1143	2
3350000	650000	1144	1
3350000	650000	1145	3
3350000	650000	1147	1
3350000	650000	1148	2
3350000	650000	1149	3
3350000	650000	1150	1
3350000	650000	1151	8
3350000	650000	1152	1
3350000	650000	1154	5
3350000	650000	1155	2
3350000	650000	1156	1
3350000	650000	1158	1
3350000	650000	1160	3
3350000	650000	1161	1
3350000	650000	1162	1
3350000	650000	1163	1
3350000	650000	1164	5
3350000	650000	1165	3
3350000	650000	1166	1
3350000	650000	1167	2
3350000	650000	1169	1
3350000	650000	1170	3
3350000	650000	1171	1
3350000	650000	1172	2
3350000	650000	1173	4
3350000	650000	1174	5
3350000	650000	1175	3
3350000	650000	1176	4
3350000	650000	1177	1
3350000	650000	1178	2
3350000	650000	1179	1
3350000	650000	1180	3
3350000	650000	1183	5
3350000	650000	1184	2
3350000	650000	1185	1
3350000	650000	1186	2
3350000	650000	1187	2
3350000	650000	1188	3
3350000	650000	1189	4
3350000	650000	1190	3
3350000	650000	1191	2
3350000	650000	1192	3
3350000	650000	1193	1
3350000	650000	1194	6
3350000	650000	1195	3
3350000	650000	1196	1
3350000	650000	1197	3
3350000	650000	1198	4
3350000	650000	1199	1
3350000	650000	1203	5
3350000	650000	1204	1
3350000	650000	1205	2
3350000	650000	1207	3
3350000	650000	1209	3
3350000	650000	1210	2
3350000	650000	1211	3
3350000	650000	1212	2
3350000	650000	1214	1
3350000	650000	1215	4
3350000	650000	1217	2
3350000	650000	1219	3
3350000	650000	1220	1
3350000	650000	1221	1
3350000	650000	1223	3
3350000	650000	1226	5
3350000	650000	1227	2
3350000	650000	1228	3
3350000	650000	1229	1
3350000	650000	1230	3
3350000	650000	1231	1
3350000	650000	1232	3
3350000	650000	1233	3
3350000	650000	1235	1
3350000	650000	1238	2
3350000	650000	1239	3
3350000	650000	1240	1
3350000	650000	1242	2
3350000	650000	1243	1
3350000	650000	1244	1
3350000	650000	1249	1
3350000	650000	1257	1
3350000	650000	1289	1
3350000	650000	885	1
3350000	650000	887	1
3350000	650000	895	1
3350000	650000	908	1
3350000	650000	909	2
3350000	650000	910	1
3350000	650000	911	2
3350000	650000	913	1
3350000	650000	916	1
3350000	650000	917	1
3350000	650000	920	2
3350000	650000	923	2
3350000	650000	924	1
3350000	650000	927	1
3350000	650000	928	3
3350000	650000	929	4
3350000	650000	931	1
3350000	650000	936	1
3350000	650000	937	1
3350000	650000	938	1
3350000	650000	939	1
3350000	650000	940	1
3350000	650000	941	6
3350000	650000	942	2
3350000	650000	943	1
3350000	650000	944	1
3350000	650000	945	3
3350000	650000	946	2
3350000	650000	947	4
3350000	650000	948	2
3350000	650000	949	1
3350000	650000	950	2
3350000	650000	951	2
3350000	650000	952	3
3350000	650000	953	1
3350000	650000	954	6
3350000	650000	955	8
3350000	650000	956	11
3350000	650000	957	8
3350000	650000	958	6
3350000	650000	959	11
3350000	650000	960	10
3350000	650000	961	8
3350000	650000	962	11
3350000	650000	963	12
3350000	650000	964	9
3350000	650000	965	14
3350000	650000	966	9
3350000	650000	967	18
3350000	650000	968	16
3350000	650000	969	12
3350000	650000	970	11
3350000	650000	971	22
3350000	650000	972	15
3350000	650000	973	18
3350000	650000	974	6
3350000	650000	975	14
3350000	650000	976	13
3350000	650000	977	15
3350000	650000	978	13
3350000	650000	979	14
3350000	650000	980	24
3350000	650000	981	17
3350000	650000	982	6
3350000	650000	983	15
3350000	650000	984	15
3350000	650000	985	13
3350000	650000	986	20
3350000	650000	987	21
3350000	650000	988	10
3350000	650000	989	19
3350000	650000	990	25
3350000	650000	991	19
3350000	650000	992	25
3350000	650000	993	15
3350000	650000	994	19
3350000	650000	995	11
3350000	650000	996	21
3350000	650000	997	16
3350000	650000	998	31
3350000	650000	999	26
3350000	750000	1000	43
3350000	750000	1001	31
3350000	750000	1002	29
3350000	750000	1003	22
3350000	750000	1004	28
3350000	750000	1005	37
3350000	750000	1006	36
3350000	750000	1007	27
3350000	750000	1008	33
3350000	750000	1009	24
3350000	750000	1010	23
3350000	750000	1011	22
3350000	750000	1012	25
3350000	750000	1013	25
3350000	750000	1014	31
3350000	750000	1015	21
3350000	750000	1016	29
3350000	750000	1017	27
3350000	750000	1018	21
3350000	750000	1019	25
3350000	750000	1020	18
3350000	750000	1021	26
3350000	750000	1022	27
3350000	750000	1023	29
3350000	750000	1024	22
3350000	750000	1025	26
3350000	750000	1026	32
3350000	750000	1027	31
3350000	750000	1028	37
3350000	750000	1029	19
3350000	750000	1030	27
3350000	750000	1031	29
3350000	750000	1032	19
3350000	750000	1033	24
3350000	750000	1034	16
3350000	750000	1035	15
3350000	750000	1036	26
3350000	750000	1037	14
3350000	750000	1038	20
3350000	750000	1039	26
3350000	750000	1040	25
3350000	750000	1041	22
3350000	750000	1042	27
3350000	750000	1043	29
3350000	750000	1044	25
3350000	750000	1045	23
3350000	750000	1046	31
3350000	750000	1047	15
3350000	750000	1048	20
3350000	750000	1049	21
3350000	750000	1050	24
3350000	750000	1051	25
3350000	750000	1052	22
3350000	750000	1053	28
3350000	750000	1054	15
3350000	750000	1055	12
3350000	750000	1056	28
3350000	750000	1057	14
3350000	750000	1058	28
3350000	750000	1059	22
3350000	750000	1060	31
3350000	750000	1061	24
3350000	750000	1062	23
3350000	750000	1063	27
3350000	750000	1064	24
3350000	750000	1065	20
3350000	750000	1066	21
3350000	750000	1067	21
3350000	750000	1068	13
3350000	750000	1069	17
3350000	750000	1070	13
3350000	750000	1071	20
3350000	750000	1072	12
3350000	750000	1073	26
3350000	750000	1074	16
3350000	750000	1075	13
3350000	750000	1076	18
3350000	750000	1077	14
3350000	750000	1078	20
3350000	750000	1079	21
3350000	750000	1080	27
3350000	750000	1081	12
3350000	750000	1082	16
3350000	750000	1083	15
3350000	750000	1084	14
3350000	750000	1085	7
3350000	750000	1086	28
3350000	750000	1087	17
3350000	750000	1088	11
3350000	750000	1089	26
3350000	750000	1090	25
3350000	750000	1091	16
3350000	750000	1092	16
3350000	750000	1093	13
3350000	750000	1094	16
3350000	750000	1095	16
3350000	750000	1096	20
3350000	750000	1097	11
3350000	750000	1098	9
3350000	750000	1099	13
3350000	750000	1100	9
3350000	750000	1101	16
3350000	750000	1102	13
3350000	750000	1103	17
3350000	750000	1104	15
3350000	750000	1105	17
3350000	750000	1106	8
3350000	750000	1107	20
3350000	750000	1108	11
3350000	750000	1109	19
3350000	750000	1110	10
3350000	750000	1111	9
3350000	750000	1112	12
3350000	750000	1113	12
3350000	750000	1114	15
3350000	750000	1115	18
3350000	750000	1116	9
3350000	750000	1117	15
3350000	750000	1118	15
3350000	750000	1119	14
3350000	750000	1120	10
3350000	750000	1121	7
3350000	750000	1122	8
3350000	750000	1123	7
3350000	750000	1124	11
3350000	750000	1125	13
3350000	750000	1126	12
3350000	750000	1127	14
3350000	750000	1128	10
3350000	750000	1129	5
3350000	750000	1130	11
3350000	750000	1131	11
3350000	750000	1132	8
3350000	750000	1133	13
3350000	750000	1134	2
3350000	750000	1135	17
3350000	750000	1136	7
3350000	750000	1137	6
3350000	750000	1138	11
3350000	750000	1139	8
3350000	750000	1140	8
3350000	750000	1141	7
3350000	750000	1142	8
3350000	750000	1143	7
3350000	750000	1144	8
3350000	750000	1145	10
3350000	750000	1146	3
3350000	750000	1147	13
3350000	750000	1148	16
3350000	750000	1149	10
3350000	750000	1150	7
3350000	750000	1151	14
3350000	750000	1152	12
3350000	750000	1153	8
3350000	750000	1154	15
3350000	750000	1155	9
3350000	750000	1156	5
3350000	750000	1157	10
3350000	750000	1158	5
3350000	750000	1159	6
3350000	750000	1160	7
3350000	750000	1161	9
3350000	750000	1162	12
3350000	750000	1163	8
3350000	750000	1164	6
3350000	750000	1165	3
3350000	750000	1166	7
3350000	750000	1167	5
3350000	750000	1168	5
3350000	750000	1169	5
3350000	750000	1170	5
3350000	750000	1171	4
3350000	750000	1172	7
3350000	750000	1173	6
3350000	750000	1174	5
3350000	750000	1175	5
3350000	750000	1176	3
3350000	750000	1177	9
3350000	750000	1178	9
3350000	750000	1179	1
3350000	750000	1180	9
3350000	750000	1181	5
3350000	750000	1182	9
3350000	750000	1183	2
3350000	750000	1184	9
3350000	750000	1185	4
3350000	750000	1186	5
3350000	750000	1187	4
3350000	750000	1188	5
3350000	750000	1189	2
3350000	750000	1190	3
3350000	750000	1191	5
3350000	750000	1192	4
3350000	750000	1193	3
3350000	750000	1194	4
3350000	750000	1195	4
3350000	750000	1197	3
3350000	750000	1198	5
3350000	750000	1199	2
3350000	750000	1200	3
3350000	750000	1201	3
3350000	750000	1202	5
3350000	750000	1203	2
3350000	750000	1204	4
3350000	750000	1205	4
3350000	750000	1206	10
3350000	750000	1207	2
3350000	750000	1208	3
3350000	750000	1209	1
3350000	750000	1210	2
3350000	750000	1211	4
3350000	750000	1212	4
3350000	750000	1214	3
3350000	750000	1215	4
3350000	750000	1216	3
3350000	750000	1217	3
3350000	750000	1218	4
3350000	750000	1219	1
3350000	750000	1221	1
3350000	750000	1222	2
3350000	750000	1223	2
3350000	750000	1224	1
3350000	750000	1226	2
3350000	750000	1227	4
3350000	750000	1228	5
3350000	750000	1229	3
3350000	750000	1230	2
3350000	750000	1231	1
3350000	750000	1232	3
3350000	750000	1233	2
3350000	750000	1234	2
3350000	750000	1236	3
3350000	750000	1237	1
3350000	750000	1238	1
3350000	750000	1239	3
3350000	750000	1240	3
3350000	750000	1241	1
3350000	750000	1243	1
3350000	750000	1244	2
3350000	750000	1245	1
3350000	750000	1246	1
3350000	750000	1247	5
3350000	750000	1248	2
3350000	750000	1249	1
3350000	750000	1250	1
3350000	750000	1251	2
3350000	750000	1252	4
3350000	750000	1253	1
3350000	750000	1254	6
3350000	750000	1255	1
3350000	750000	1256	4
3350000	750000	1258	5
3350000	750000	1260	2
3350000	750000	1261	1
3350000	750000	1262	1
3350000	750000	1263	3
3350000	750000	1264	1
3350000	750000	1265	2
3350000	750000	1266	1
3350000	750000	1267	1
3350000	750000	1268	1
3350000	750000	1269	2
3350000	750000	1270	1
3350000	750000	1272	2
3350000	750000	1273	2
3350000	750000	1274	1
3350000	750000	1275	3
3350000	750000	1277	1
3350000	750000	1278	1
3350000	750000	1279	5
3350000	750000	1280	1
3350000	750000	1281	2
3350000	750000	1282	2
3350000	750000	1284	1
3350000	750000	1286	2
3350000	750000	1287	1
3350000	750000	1288	2
3350000	750000	1291	2
3350000	750000	1292	1
3350000	750000	1293	2
3350000	750000	1294	1
3350000	750000	1300	2
3350000	750000	1301	1
3350000	750000	1304	1
3350000	750000	1305	1
3350000	750000	1306	1
3350000	750000	1307	1
3350000	750000	1309	1
3350000	750000	1310	2
3350000	750000	1311	1
3350000	750000	1313	2
3350000	750000	1315	4
3350000	750000	1316	1
3350000	750000	1317	3
3350000	750000	1318	2
3350000	750000	1320	1
3350000	750000	1321	1
3350000	750000	1323	1
3350000	750000	1325	1
3350000	750000	1328	1
3350000	750000	1329	1
3350000	750000	1330	2
3350000	750000	1331	2
3350000	750000	1333	3
3350000	750000	1334	1
3350000	750000	1336	1
3350000	750000	1337	2
3350000	750000	1338	1
3350000	750000	1342	2
3350000	750000	1343	2
3350000	750000	1344	1
3350000	750000	1345	1
3350000	750000	1346	3
3350000	750000	1348	1
3350000	750000	1349	1
3350000	750000	1356	2
3350000	750000	1358	2
3350000	750000	1359	1
3350000	750000	1360	1
3350000	750000	1361	1
3350000	750000	1369	1
3350000	750000	1370	2
3350000	750000	1371	1
3350000	750000	1372	1
3350000	750000	1380	1
3350000	750000	1385	2
3350000	750000	1386	2
3350000	750000	1392	3
3350000	750000	1395	1
3350000	750000	1401	1
3350000	750000	1407	2
3350000	750000	1408	1
3350000	750000	1409	1
3350000	750000	1411	1
3350000	750000	1415	2
3350000	750000	1418	2
3350000	750000	1421	1
3350000	750000	1423	3
3350000	750000	1425	1
3350000	750000	1430	1
3350000	750000	1432	1
3350000	750000	1433	1
3350000	750000	1435	2
3350000	750000	1437	1
3350000	750000	1438	1
3350000	750000	1445	1
3350000	750000	1446	2
3350000	750000	1447	2
3350000	750000	1448	1
3350000	750000	1450	1
3350000	750000	1451	1
3350000	750000	1452	2
3350000	750000	1461	1
3350000	750000	1462	1
3350000	750000	1463	1
3350000	750000	1465	1
3350000	750000	1467	1
3350000	750000	1472	3
3350000	750000	1473	1
3350000	750000	1475	1
3350000	750000	1479	1
3350000	750000	1480	1
3350000	750000	1482	1
3350000	750000	1483	2
3350000	750000	1499	2
3350000	750000	1500	1
3350000	750000	1508	3
3350000	750000	1509	2
3350000	750000	1513	1
3350000	750000	1514	1
3350000	750000	1519	1
3350000	750000	1522	2
3350000	750000	1523	1
3350000	750000	1524	1
3350000	750000	1525	1
3350000	750000	1530	1
3350000	750000	1536	1
3350000	750000	1541	2
3350000	750000	1542	1
3350000	750000	1543	1
3350000	750000	1544	1
3350000	750000	1545	3
3350000	750000	1552	1
3350000	750000	1558	1
3350000	750000	1560	1
3350000	750000	1562	1
3350000	750000	1565	2
3350000	750000	1566	1
3350000	750000	1577	1
3350000	750000	1580	2
3350000	750000	1583	1
3350000	750000	1584	1
3350000	750000	1588	1
3350000	750000	1592	1
3350000	750000	1594	1
3350000	750000	1597	1
3350000	750000	1605	1
3350000	750000	1613	1
3350000	750000	1614	1
3350000	750000	1620	2
3350000	750000	1622	1
3350000	750000	1625	1
3350000	750000	1627	1
3350000	750000	1630	1
3350000	750000	1632	1
3350000	750000	1633	1
3350000	750000	1638	1
3350000	750000	1645	1
3350000	750000	1651	1
3350000	750000	1652	1
3350000	750000	1653	1
3350000	750000	1655	1
3350000	750000	1657	1
3350000	750000	1664	1
3350000	750000	1689	1
3350000	750000	1712	1
3350000	750000	1717	1
3350000	750000	1723	1
3350000	750000	1725	1
3350000	750000	1726	1
3350000	750000	1732	1
3350000	750000	1733	1
3350000	750000	1736	1
3350000	750000	1737	1
3350000	750000	1742	1
3350000	750000	1747	1
3350000	750000	535	1
3350000	750000	538	1
3350000	750000	539	5
3350000	750000	540	1
3350000	750000	541	2
3350000	750000	542	1
3350000	750000	543	10
3350000	750000	544	4
3350000	750000	545	1
3350000	750000	546	9
3350000	750000	547	3
3350000	750000	548	5
3350000	750000	549	6
3350000	750000	550	11
3350000	750000	551	14
3350000	750000	552	14
3350000	750000	553	10
3350000	750000	554	10
3350000	750000	555	8
3350000	750000	556	7
3350000	750000	557	5
3350000	750000	558	7
3350000	750000	559	5
3350000	750000	560	8
3350000	750000	561	7
3350000	750000	562	8
3350000	750000	563	6
3350000	750000	564	5
3350000	750000	565	5
3350000	750000	566	11
3350000	750000	567	8
3350000	750000	568	11
3350000	750000	569	12
3350000	750000	570	10
3350000	750000	571	17
3350000	750000	572	12
3350000	750000	573	13
3350000	750000	574	14
3350000	750000	575	11
3350000	750000	576	23
3350000	750000	577	19
3350000	750000	578	12
3350000	750000	579	26
3350000	750000	580	17
3350000	750000	581	18
3350000	750000	582	19
3350000	750000	583	19
3350000	750000	584	14
3350000	750000	585	18
3350000	750000	586	20
3350000	750000	587	20
3350000	750000	588	28
3350000	750000	589	18
3350000	750000	590	20
3350000	750000	591	29
3350000	750000	592	30
3350000	750000	593	25
3350000	750000	594	33
3350000	750000	595	36
3350000	750000	596	43
3350000	750000	597	29
3350000	750000	598	39
3350000	750000	599	49
3350000	750000	600	34
3350000	750000	601	30
3350000	750000	602	31
3350000	750000	603	27
3350000	750000	604	21
3350000	750000	605	19
3350000	750000	606	27
3350000	750000	607	19
3350000	750000	608	22
3350000	750000	609	20
3350000	750000	610	17
3350000	750000	611	31
3350000	750000	612	20
3350000	750000	613	23
3350000	750000	614	17
3350000	750000	615	14
3350000	750000	616	25
3350000	750000	617	18
3350000	750000	618	13
3350000	750000	619	26
3350000	750000	620	17
3350000	750000	621	15
3350000	750000	622	14
3350000	750000	623	23
3350000	750000	624	11
3350000	750000	625	15
3350000	750000	626	13
3350000	750000	627	21
3350000	750000	628	16
3350000	750000	629	11
3350000	750000	630	12
3350000	750000	631	11
3350000	750000	632	14
3350000	750000	633	18
3350000	750000	634	19
3350000	750000	635	9
3350000	750000	636	7
3350000	750000	637	20
3350000	750000	638	12
3350000	750000	639	15
3350000	750000	640	9
3350000	750000	641	11
3350000	750000	642	9
3350000	750000	643	14
3350000	750000	644	10
3350000	750000	645	14
3350000	750000	646	6
3350000	750000	647	10
3350000	750000	648	16
3350000	750000	649	13
3350000	750000	650	8
3350000	750000	651	10
3350000	750000	652	13
3350000	750000	653	12
3350000	750000	654	9
3350000	750000	655	11
3350000	750000	656	13
3350000	750000	657	11
3350000	750000	658	7
3350000	750000	659	21
3350000	750000	660	12
3350000	750000	661	11
3350000	750000	662	12
3350000	750000	663	8
3350000	750000	664	11
3350000	750000	665	6
3350000	750000	666	13
3350000	750000	667	12
3350000	750000	668	18
3350000	750000	669	11
3350000	750000	670	13
3350000	750000	671	8
3350000	750000	672	8
3350000	750000	673	16
3350000	750000	674	8
3350000	750000	675	10
3350000	750000	676	9
3350000	750000	677	11
3350000	750000	678	8
3350000	750000	679	8
3350000	750000	680	12
3350000	750000	681	13
3350000	750000	682	10
3350000	750000	683	5
3350000	750000	684	13
3350000	750000	685	7
3350000	750000	686	13
3350000	750000	687	21
3350000	750000	688	8
3350000	750000	689	7
3350000	750000	690	10
3350000	750000	691	8
3350000	750000	692	8
3350000	750000	693	8
3350000	750000	694	7
3350000	750000	695	11
3350000	750000	696	9
3350000	750000	697	9
3350000	750000	698	12
3350000	750000	699	13
3350000	750000	700	8
3350000	750000	701	6
3350000	750000	702	14
3350000	750000	703	13
3350000	750000	704	5
3350000	750000	705	14
3350000	750000	706	7
3350000	750000	707	7
3350000	750000	708	12
3350000	750000	709	16
3350000	750000	710	8
3350000	750000	711	9
3350000	750000	712	6
3350000	750000	713	4
3350000	750000	714	12
3350000	750000	715	9
3350000	750000	716	11
3350000	750000	717	18
3350000	750000	718	8
3350000	750000	719	9
3350000	750000	720	10
3350000	750000	721	6
3350000	750000	722	4
3350000	750000	723	7
3350000	750000	724	9
3350000	750000	725	16
3350000	750000	726	10
3350000	750000	727	13
3350000	750000	728	10
3350000	750000	729	7
3350000	750000	730	6
3350000	750000	731	6
3350000	750000	732	11
3350000	750000	733	8
3350000	750000	734	12
3350000	750000	736	9
3350000	750000	737	10
3350000	750000	738	4
3350000	750000	739	5
3350000	750000	740	14
3350000	750000	741	6
3350000	750000	742	9
3350000	750000	743	7
3350000	750000	744	16
3350000	750000	745	9
3350000	750000	746	9
3350000	750000	747	10
3350000	750000	748	5
3350000	750000	749	11
3350000	750000	750	11
3350000	750000	751	2
3350000	750000	752	10
3350000	750000	753	11
3350000	750000	754	6
3350000	750000	755	3
3350000	750000	756	7
3350000	750000	757	10
3350000	750000	758	8
3350000	750000	759	8
3350000	750000	760	10
3350000	750000	761	12
3350000	750000	762	11
3350000	750000	763	8
3350000	750000	764	5
3350000	750000	765	6
3350000	750000	766	15
3350000	750000	767	11
3350000	750000	768	12
3350000	750000	769	7
3350000	750000	770	8
3350000	750000	771	4
3350000	750000	772	10
3350000	750000	773	13
3350000	750000	774	9
3350000	750000	775	9
3350000	750000	776	14
3350000	750000	777	14
3350000	750000	778	8
3350000	750000	779	7
3350000	750000	780	12
3350000	750000	781	10
3350000	750000	782	8
3350000	750000	783	15
3350000	750000	784	9
3350000	750000	785	8
3350000	750000	786	15
3350000	750000	787	8
3350000	750000	788	18
3350000	750000	789	9
3350000	750000	790	5
3350000	750000	791	6
3350000	750000	792	15
3350000	750000	793	13
3350000	750000	794	10
3350000	750000	795	20
3350000	750000	796	13
3350000	750000	797	8
3350000	750000	798	17
3350000	750000	799	18
3350000	750000	800	14
3350000	750000	801	13
3350000	750000	802	13
3350000	750000	803	11
3350000	750000	804	13
3350000	750000	805	13
3350000	750000	806	8
3350000	750000	807	14
3350000	750000	808	16
3350000	750000	809	7
3350000	750000	810	10
3350000	750000	811	8
3350000	750000	812	16
3350000	750000	813	12
3350000	750000	814	16
3350000	750000	815	10
3350000	750000	816	10
3350000	750000	817	20
3350000	750000	818	9
3350000	750000	819	21
3350000	750000	820	16
3350000	750000	821	14
3350000	750000	822	12
3350000	750000	823	12
3350000	750000	824	12
3350000	750000	825	19
3350000	750000	826	19
3350000	750000	827	8
3350000	750000	828	12
3350000	750000	829	13
3350000	750000	830	20
3350000	750000	831	5
3350000	750000	832	8
3350000	750000	833	12
3350000	750000	834	16
3350000	750000	835	14
3350000	750000	836	10
3350000	750000	837	16
3350000	750000	838	4
3350000	750000	839	13
3350000	750000	840	10
3350000	750000	841	9
3350000	750000	842	18
3350000	750000	843	11
3350000	750000	844	6
3350000	750000	845	10
3350000	750000	846	11
3350000	750000	847	13
3350000	750000	848	14
3350000	750000	849	9
3350000	750000	850	12
3350000	750000	851	7
3350000	750000	852	10
3350000	750000	853	13
3350000	750000	854	14
3350000	750000	855	9
3350000	750000	856	5
3350000	750000	857	13
3350000	750000	858	11
3350000	750000	859	8
3350000	750000	860	8
3350000	750000	861	11
3350000	750000	862	7
3350000	750000	863	10
3350000	750000	864	7
3350000	750000	865	5
3350000	750000	866	7
3350000	750000	867	13
3350000	750000	868	6
3350000	750000	869	11
3350000	750000	870	16
3350000	750000	871	12
3350000	750000	872	10
3350000	750000	873	17
3350000	750000	874	6
3350000	750000	875	11
3350000	750000	876	12
3350000	750000	877	18
3350000	750000	878	12
3350000	750000	879	10
3350000	750000	880	10
3350000	750000	881	13
3350000	750000	882	11
3350000	750000	883	14
3350000	750000	884	15
3350000	750000	885	8
3350000	750000	886	16
3350000	750000	887	7
3350000	750000	888	10
3350000	750000	889	8
3350000	750000	890	11
3350000	750000	891	12
3350000	750000	892	9
3350000	750000	893	9
3350000	750000	894	15
3350000	750000	895	9
3350000	750000	896	11
3350000	750000	897	10
3350000	750000	898	27
3350000	750000	899	8
3350000	750000	900	17
3350000	750000	901	11
3350000	750000	902	16
3350000	750000	903	10
3350000	750000	904	14
3350000	750000	905	16
3350000	750000	906	15
3350000	750000	907	15
3350000	750000	908	14
3350000	750000	909	10
3350000	750000	910	19
3350000	750000	911	19
3350000	750000	912	16
3350000	750000	913	10
3350000	750000	914	14
3350000	750000	915	12
3350000	750000	916	11
3350000	750000	917	8
3350000	750000	918	16
3350000	750000	919	12
3350000	750000	920	16
3350000	750000	921	13
3350000	750000	922	14
3350000	750000	923	15
3350000	750000	924	18
3350000	750000	925	7
3350000	750000	926	12
3350000	750000	927	18
3350000	750000	928	17
3350000	750000	929	12
3350000	750000	930	16
3350000	750000	931	13
3350000	750000	932	12
3350000	750000	933	17
3350000	750000	934	21
3350000	750000	935	19
3350000	750000	936	20
3350000	750000	937	19
3350000	750000	938	25
3350000	750000	939	27
3350000	750000	940	16
3350000	750000	941	21
3350000	750000	942	16
3350000	750000	943	21
3350000	750000	944	19
3350000	750000	945	22
3350000	750000	946	17
3350000	750000	947	29
3350000	750000	948	26
3350000	750000	949	23
3350000	750000	950	20
3350000	750000	951	30
3350000	750000	952	24
3350000	750000	953	24
3350000	750000	954	21
3350000	750000	955	20
3350000	750000	956	15
3350000	750000	957	26
3350000	750000	958	25
3350000	750000	959	18
3350000	750000	960	20
3350000	750000	961	21
3350000	750000	962	33
3350000	750000	963	19
3350000	750000	964	30
3350000	750000	965	22
3350000	750000	966	27
3350000	750000	967	17
3350000	750000	968	18
3350000	750000	969	25
3350000	750000	970	17
3350000	750000	971	22
3350000	750000	972	33
3350000	750000	973	26
3350000	750000	974	28
3350000	750000	975	29
3350000	750000	976	30
3350000	750000	977	19
3350000	750000	978	27
3350000	750000	979	13
3350000	750000	980	21
3350000	750000	981	33
3350000	750000	982	34
3350000	750000	983	29
3350000	750000	984	18
3350000	750000	985	39
3350000	750000	986	31
3350000	750000	987	29
3350000	750000	988	31
3350000	750000	989	26
3350000	750000	990	33
3350000	750000	991	38
3350000	750000	992	28
3350000	750000	993	32
3350000	750000	994	26
3350000	750000	995	35
3350000	750000	996	41
3350000	750000	997	25
3350000	750000	998	27
3350000	750000	999	32
3350000	850000	1000	5
3350000	850000	1001	7
3350000	850000	1002	5
3350000	850000	1003	3
3350000	850000	1004	7
3350000	850000	1006	2
3350000	850000	1007	4
3350000	850000	1008	7
3350000	850000	1009	5
3350000	850000	1010	3
3350000	850000	1011	8
3350000	850000	1012	8
3350000	850000	1013	4
3350000	850000	1014	8
3350000	850000	1015	9
3350000	850000	1016	7
3350000	850000	1017	7
3350000	850000	1018	9
3350000	850000	1019	1
3350000	850000	1020	8
3350000	850000	1021	6
3350000	850000	1022	6
3350000	850000	1023	2
3350000	850000	1024	4
3350000	850000	1025	6
3350000	850000	1026	9
3350000	850000	1027	8
3350000	850000	1028	4
3350000	850000	1029	7
3350000	850000	1030	2
3350000	850000	1031	3
3350000	850000	1032	7
3350000	850000	1033	10
3350000	850000	1034	2
3350000	850000	1035	6
3350000	850000	1036	9
3350000	850000	1037	5
3350000	850000	1038	10
3350000	850000	1039	9
3350000	850000	1040	11
3350000	850000	1041	7
3350000	850000	1042	6
3350000	850000	1043	10
3350000	850000	1044	6
3350000	850000	1045	3
3350000	850000	1046	5
3350000	850000	1047	5
3350000	850000	1048	4
3350000	850000	1050	5
3350000	850000	1051	9
3350000	850000	1052	4
3350000	850000	1053	6
3350000	850000	1054	5
3350000	850000	1055	7
3350000	850000	1056	9
3350000	850000	1057	4
3350000	850000	1058	2
3350000	850000	1059	4
3350000	850000	1060	3
3350000	850000	1061	5
3350000	850000	1062	5
3350000	850000	1063	1
3350000	850000	1064	4
3350000	850000	1065	3
3350000	850000	1066	3
3350000	850000	1067	5
3350000	850000	1068	6
3350000	850000	1069	7
3350000	850000	1070	4
3350000	850000	1071	7
3350000	850000	1072	6
3350000	850000	1073	3
3350000	850000	1074	4
3350000	850000	1075	5
3350000	850000	1076	5
3350000	850000	1078	4
3350000	850000	1079	2
3350000	850000	1080	7
3350000	850000	1081	4
3350000	850000	1082	4
3350000	850000	1083	5
3350000	850000	1084	3
3350000	850000	1085	6
3350000	850000	1086	1
3350000	850000	1087	9
3350000	850000	1088	3
3350000	850000	1089	8
3350000	850000	1090	2
3350000	850000	1091	2
3350000	850000	1092	3
3350000	850000	1093	4
3350000	850000	1094	3
3350000	850000	1095	1
3350000	850000	1096	3
3350000	850000	1097	3
3350000	850000	1098	4
3350000	850000	1099	1
3350000	850000	1100	4
3350000	850000	1101	1
3350000	850000	1102	5
3350000	850000	1103	4
3350000	850000	1104	8
3350000	850000	1105	3
3350000	850000	1106	8
3350000	850000	1107	6
3350000	850000	1108	3
3350000	850000	1109	4
3350000	850000	1110	4
3350000	850000	1111	1
3350000	850000	1112	4
3350000	850000	1113	4
3350000	850000	1114	4
3350000	850000	1115	2
3350000	850000	1116	3
3350000	850000	1117	1
3350000	850000	1118	4
3350000	850000	1119	4
3350000	850000	1120	2
3350000	850000	1121	2
3350000	850000	1122	3
3350000	850000	1123	3
3350000	850000	1124	1
3350000	850000	1125	1
3350000	850000	1126	4
3350000	850000	1128	4
3350000	850000	1129	2
3350000	850000	1130	3
3350000	850000	1131	5
3350000	850000	1132	1
3350000	850000	1133	1
3350000	850000	1134	3
3350000	850000	1135	4
3350000	850000	1136	1
3350000	850000	1137	2
3350000	850000	1139	1
3350000	850000	1140	4
3350000	850000	1142	2
3350000	850000	1143	3
3350000	850000	1144	4
3350000	850000	1145	4
3350000	850000	1147	2
3350000	850000	1148	3
3350000	850000	1149	4
3350000	850000	1150	5
3350000	850000	1151	5
3350000	850000	1152	3
3350000	850000	1153	1
3350000	850000	1154	6
3350000	850000	1155	1
3350000	850000	1156	1
3350000	850000	1157	2
3350000	850000	1158	2
3350000	850000	1159	5
3350000	850000	1161	3
3350000	850000	1162	2
3350000	850000	1163	3
3350000	850000	1164	4
3350000	850000	1165	1
3350000	850000	1166	2
3350000	850000	1167	2
3350000	850000	1168	2
3350000	850000	1169	1
3350000	850000	1170	1
3350000	850000	1171	1
3350000	850000	1172	3
3350000	850000	1173	3
3350000	850000	1174	2
3350000	850000	1175	1
3350000	850000	1176	4
3350000	850000	1177	3
3350000	850000	1178	1
3350000	850000	1179	2
3350000	850000	1180	4
3350000	850000	1182	4
3350000	850000	1183	3
3350000	850000	1186	3
3350000	850000	1188	1
3350000	850000	1191	3
3350000	850000	1192	4
3350000	850000	1193	1
3350000	850000	1194	1
3350000	850000	1195	3
3350000	850000	1197	1
3350000	850000	1198	3
3350000	850000	1199	4
3350000	850000	1200	2
3350000	850000	1201	4
3350000	850000	1202	1
3350000	850000	1204	2
3350000	850000	1205	1
3350000	850000	1206	3
3350000	850000	1207	2
3350000	850000	1208	2
3350000	850000	1209	3
3350000	850000	1210	3
3350000	850000	1213	2
3350000	850000	1214	1
3350000	850000	1215	6
3350000	850000	1216	1
3350000	850000	1218	1
3350000	850000	1220	3
3350000	850000	1221	3
3350000	850000	1222	6
3350000	850000	1223	3
3350000	850000	1224	5
3350000	850000	1225	1
3350000	850000	1226	3
3350000	850000	1227	2
3350000	850000	1229	2
3350000	850000	1231	2
3350000	850000	1232	1
3350000	850000	1233	2
3350000	850000	1234	2
3350000	850000	1235	4
3350000	850000	1236	5
3350000	850000	1237	2
3350000	850000	1238	2
3350000	850000	1239	1
3350000	850000	1240	1
3350000	850000	1241	2
3350000	850000	1242	5
3350000	850000	1243	4
3350000	850000	1244	2
3350000	850000	1245	2
3350000	850000	1246	1
3350000	850000	1248	6
3350000	850000	1249	2
3350000	850000	1251	2
3350000	850000	1252	2
3350000	850000	1253	2
3350000	850000	1257	1
3350000	850000	1259	1
3350000	850000	1260	3
3350000	850000	1261	3
3350000	850000	1262	2
3350000	850000	1263	2
3350000	850000	1264	1
3350000	850000	1265	4
3350000	850000	1266	1
3350000	850000	1267	2
3350000	850000	1268	3
3350000	850000	1269	1
3350000	850000	1270	1
3350000	850000	1271	3
3350000	850000	1272	2
3350000	850000	1273	2
3350000	850000	1275	1
3350000	850000	1276	2
3350000	850000	1277	2
3350000	850000	1278	1
3350000	850000	1279	3
3350000	850000	1280	4
3350000	850000	1282	1
3350000	850000	1283	1
3350000	850000	1284	2
3350000	850000	1287	4
3350000	850000	1288	3
3350000	850000	1289	1
3350000	850000	1291	3
3350000	850000	1292	1
3350000	850000	1293	3
3350000	850000	1294	2
3350000	850000	1295	1
3350000	850000	1296	1
3350000	850000	1297	5
3350000	850000	1299	2
3350000	850000	1300	3
3350000	850000	1301	4
3350000	850000	1302	2
3350000	850000	1303	2
3350000	850000	1304	1
3350000	850000	1305	3
3350000	850000	1306	1
3350000	850000	1307	1
3350000	850000	1308	3
3350000	850000	1309	3
3350000	850000	1311	3
3350000	850000	1312	1
3350000	850000	1313	1
3350000	850000	1314	1
3350000	850000	1316	1
3350000	850000	1318	4
3350000	850000	1319	1
3350000	850000	1320	3
3350000	850000	1322	5
3350000	850000	1323	1
3350000	850000	1324	1
3350000	850000	1325	2
3350000	850000	1327	1
3350000	850000	1328	1
3350000	850000	1329	1
3350000	850000	1330	1
3350000	850000	1331	5
3350000	850000	1332	6
3350000	850000	1333	1
3350000	850000	1334	4
3350000	850000	1335	2
3350000	850000	1337	1
3350000	850000	1339	4
3350000	850000	1343	2
3350000	850000	1344	1
3350000	850000	1345	1
3350000	850000	1346	2
3350000	850000	1347	1
3350000	850000	1348	2
3350000	850000	1349	2
3350000	850000	1350	1
3350000	850000	1351	1
3350000	850000	1352	1
3350000	850000	1354	3
3350000	850000	1355	2
3350000	850000	1356	5
3350000	850000	1357	1
3350000	850000	1358	1
3350000	850000	1359	3
3350000	850000	1360	1
3350000	850000	1361	3
3350000	850000	1362	1
3350000	850000	1363	3
3350000	850000	1364	1
3350000	850000	1365	2
3350000	850000	1366	1
3350000	850000	1367	1
3350000	850000	1368	6
3350000	850000	1369	2
3350000	850000	1370	1
3350000	850000	1371	3
3350000	850000	1372	1
3350000	850000	1373	1
3350000	850000	1374	2
3350000	850000	1377	1
3350000	850000	1379	2
3350000	850000	1380	2
3350000	850000	1384	3
3350000	850000	1386	1
3350000	850000	1387	1
3350000	850000	1388	2
3350000	850000	1389	2
3350000	850000	1390	1
3350000	850000	1391	1
3350000	850000	1392	1
3350000	850000	1393	3
3350000	850000	1394	1
3350000	850000	1396	3
3350000	850000	1397	1
3350000	850000	1399	2
3350000	850000	1400	3
3350000	850000	1401	4
3350000	850000	1402	2
3350000	850000	1404	1
3350000	850000	1406	4
3350000	850000	1407	1
3350000	850000	1408	1
3350000	850000	1409	4
3350000	850000	1412	1
3350000	850000	1413	2
3350000	850000	1414	2
3350000	850000	1415	3
3350000	850000	1416	2
3350000	850000	1417	1
3350000	850000	1418	2
3350000	850000	1421	3
3350000	850000	1422	3
3350000	850000	1423	3
3350000	850000	1424	2
3350000	850000	1425	1
3350000	850000	1426	1
3350000	850000	1427	2
3350000	850000	1428	2
3350000	850000	1429	3
3350000	850000	1430	2
3350000	850000	1431	1
3350000	850000	1432	1
3350000	850000	1433	2
3350000	850000	1434	6
3350000	850000	1435	2
3350000	850000	1436	1
3350000	850000	1437	3
3350000	850000	1438	3
3350000	850000	1439	2
3350000	850000	1440	5
3350000	850000	1441	3
3350000	850000	1442	3
3350000	850000	1443	6
3350000	850000	1444	1
3350000	850000	1445	2
3350000	850000	1446	2
3350000	850000	1447	6
3350000	850000	1448	2
3350000	850000	1449	4
3350000	850000	1450	1
3350000	850000	1451	2
3350000	850000	1452	2
3350000	850000	1453	4
3350000	850000	1454	1
3350000	850000	1455	3
3350000	850000	1457	3
3350000	850000	1458	3
3350000	850000	1459	2
3350000	850000	1460	3
3350000	850000	1461	2
3350000	850000	1462	3
3350000	850000	1463	3
3350000	850000	1467	4
3350000	850000	1468	2
3350000	850000	1469	1
3350000	850000	1470	4
3350000	850000	1471	1
3350000	850000	1472	1
3350000	850000	1473	2
3350000	850000	1474	2
3350000	850000	1475	3
3350000	850000	1476	1
3350000	850000	1477	4
3350000	850000	1479	2
3350000	850000	1480	2
3350000	850000	1481	3
3350000	850000	1482	1
3350000	850000	1484	2
3350000	850000	1485	3
3350000	850000	1486	2
3350000	850000	1487	2
3350000	850000	1488	1
3350000	850000	1489	1
3350000	850000	1490	4
3350000	850000	1491	1
3350000	850000	1492	2
3350000	850000	1493	3
3350000	850000	1494	3
3350000	850000	1497	2
3350000	850000	1498	2
3350000	850000	1500	3
3350000	850000	1502	2
3350000	850000	1503	1
3350000	850000	1504	2
3350000	850000	1505	4
3350000	850000	1506	1
3350000	850000	1508	1
3350000	850000	1509	1
3350000	850000	1511	5
3350000	850000	1512	1
3350000	850000	1513	1
3350000	850000	1514	1
3350000	850000	1515	2
3350000	850000	1516	4
3350000	850000	1517	4
3350000	850000	1518	1
3350000	850000	1519	4
3350000	850000	1520	1
3350000	850000	1521	2
3350000	850000	1522	1
3350000	850000	1523	1
3350000	850000	1524	2
3350000	850000	1525	1
3350000	850000	1526	4
3350000	850000	1529	1
3350000	850000	1531	1
3350000	850000	1533	4
3350000	850000	1534	2
3350000	850000	1535	2
3350000	850000	1536	1
3350000	850000	1537	1
3350000	850000	1538	3
3350000	850000	1541	2
3350000	850000	1542	1
3350000	850000	1543	4
3350000	850000	1544	2
3350000	850000	1546	1
3350000	850000	1548	3
3350000	850000	1549	4
3350000	850000	1550	1
3350000	850000	1551	1
3350000	850000	1552	1
3350000	850000	1553	2
3350000	850000	1554	1
3350000	850000	1560	3
3350000	850000	1563	4
3350000	850000	1564	3
3350000	850000	1565	2
3350000	850000	1566	3
3350000	850000	1568	3
3350000	850000	1569	4
3350000	850000	1570	1
3350000	850000	1572	3
3350000	850000	1573	4
3350000	850000	1575	2
3350000	850000	1577	1
3350000	850000	1578	1
3350000	850000	1579	1
3350000	850000	1580	3
3350000	850000	1582	5
3350000	850000	1583	4
3350000	850000	1584	2
3350000	850000	1585	2
3350000	850000	1586	1
3350000	850000	1589	1
3350000	850000	1594	2
3350000	850000	1596	2
3350000	850000	1599	1
3350000	850000	1600	1
3350000	850000	1601	1
3350000	850000	1602	3
3350000	850000	1603	1
3350000	850000	1605	1
3350000	850000	1609	2
3350000	850000	1610	1
3350000	850000	1611	1
3350000	850000	1612	1
3350000	850000	1615	2
3350000	850000	1616	1
3350000	850000	1618	1
3350000	850000	1619	1
3350000	850000	1620	1
3350000	850000	1622	2
3350000	850000	1624	1
3350000	850000	1627	1
3350000	850000	1631	1
3350000	850000	1635	1
3350000	850000	1636	1
3350000	850000	1637	1
3350000	850000	1639	1
3350000	850000	1643	1
3350000	850000	1646	3
3350000	850000	1648	1
3350000	850000	1649	2
3350000	850000	1651	1
3350000	850000	1660	1
3350000	850000	1661	1
3350000	850000	1663	2
3350000	850000	1664	1
3350000	850000	1675	2
3350000	850000	1687	1
3350000	850000	1697	2
3350000	850000	1698	1
3350000	850000	1699	1
3350000	850000	1708	1
3350000	850000	1714	2
3350000	850000	1726	1
3350000	850000	1748	1
3350000	850000	1810	1
3350000	850000	495	3
3350000	850000	496	1
3350000	850000	497	2
3350000	850000	498	6
3350000	850000	499	2
3350000	850000	500	7
3350000	850000	501	5
3350000	850000	502	3
3350000	850000	503	12
3350000	850000	504	10
3350000	850000	505	17
3350000	850000	506	8
3350000	850000	507	7
3350000	850000	508	32
3350000	850000	509	27
3350000	850000	510	17
3350000	850000	511	32
3350000	850000	512	34
3350000	850000	513	35
3350000	850000	514	33
3350000	850000	515	32
3350000	850000	516	34
3350000	850000	517	27
3350000	850000	518	30
3350000	850000	519	39
3350000	850000	520	36
3350000	850000	521	33
3350000	850000	522	47
3350000	850000	523	58
3350000	850000	524	52
3350000	850000	525	44
3350000	850000	526	53
3350000	850000	527	51
3350000	850000	528	40
3350000	850000	529	48
3350000	850000	530	61
3350000	850000	531	35
3350000	850000	532	43
3350000	850000	533	50
3350000	850000	534	37
3350000	850000	535	36
3350000	850000	536	38
3350000	850000	537	30
3350000	850000	538	37
3350000	850000	539	37
3350000	850000	540	40
3350000	850000	541	40
3350000	850000	542	17
3350000	850000	543	35
3350000	850000	544	32
3350000	850000	545	35
3350000	850000	546	29
3350000	850000	547	30
3350000	850000	548	31
3350000	850000	549	31
3350000	850000	550	45
3350000	850000	551	32
3350000	850000	552	31
3350000	850000	553	29
3350000	850000	554	30
3350000	850000	555	28
3350000	850000	556	23
3350000	850000	557	30
3350000	850000	558	37
3350000	850000	559	38
3350000	850000	560	29
3350000	850000	561	36
3350000	850000	562	26
3350000	850000	563	38
3350000	850000	564	32
3350000	850000	565	31
3350000	850000	566	36
3350000	850000	567	25
3350000	850000	568	17
3350000	850000	569	25
3350000	850000	570	33
3350000	850000	571	27
3350000	850000	572	24
3350000	850000	573	28
3350000	850000	574	28
3350000	850000	575	31
3350000	850000	576	38
3350000	850000	577	22
3350000	850000	578	24
3350000	850000	579	15
3350000	850000	580	27
3350000	850000	581	22
3350000	850000	582	32
3350000	850000	583	28
3350000	850000	584	36
3350000	850000	585	32
3350000	850000	586	23
3350000	850000	587	29
3350000	850000	588	26
3350000	850000	589	26
3350000	850000	590	20
3350000	850000	591	30
3350000	850000	592	23
3350000	850000	593	24
3350000	850000	594	24
3350000	850000	595	26
3350000	850000	596	22
3350000	850000	597	24
3350000	850000	598	18
3350000	850000	599	23
3350000	850000	600	19
3350000	850000	601	22
3350000	850000	602	28
3350000	850000	603	25
3350000	850000	604	31
3350000	850000	605	25
3350000	850000	606	27
3350000	850000	607	30
3350000	850000	608	30
3350000	850000	609	23
3350000	850000	610	20
3350000	850000	611	28
3350000	850000	612	33
3350000	850000	613	27
3350000	850000	614	37
3350000	850000	615	22
3350000	850000	616	29
3350000	850000	617	18
3350000	850000	618	33
3350000	850000	619	31
3350000	850000	620	22
3350000	850000	621	26
3350000	850000	622	27
3350000	850000	623	16
3350000	850000	624	24
3350000	850000	625	27
3350000	850000	626	22
3350000	850000	627	17
3350000	850000	628	20
3350000	850000	629	17
3350000	850000	630	18
3350000	850000	631	16
3350000	850000	632	23
3350000	850000	633	13
3350000	850000	634	22
3350000	850000	635	18
3350000	850000	636	17
3350000	850000	637	24
3350000	850000	638	13
3350000	850000	639	23
3350000	850000	640	32
3350000	850000	641	17
3350000	850000	642	16
3350000	850000	643	14
3350000	850000	644	14
3350000	850000	645	18
3350000	850000	646	24
3350000	850000	647	24
3350000	850000	648	18
3350000	850000	649	20
3350000	850000	650	16
3350000	850000	651	19
3350000	850000	652	24
3350000	850000	653	21
3350000	850000	654	17
3350000	850000	655	15
3350000	850000	656	19
3350000	850000	657	22
3350000	850000	658	14
3350000	850000	659	25
3350000	850000	660	10
3350000	850000	661	19
3350000	850000	662	13
3350000	850000	663	16
3350000	850000	664	20
3350000	850000	665	18
3350000	850000	666	15
3350000	850000	667	20
3350000	850000	668	18
3350000	850000	669	17
3350000	850000	670	16
3350000	850000	671	15
3350000	850000	672	19
3350000	850000	673	13
3350000	850000	674	16
3350000	850000	675	7
3350000	850000	676	14
3350000	850000	677	25
3350000	850000	678	13
3350000	850000	679	22
3350000	850000	680	11
3350000	850000	681	17
3350000	850000	682	15
3350000	850000	683	15
3350000	850000	684	22
3350000	850000	685	26
3350000	850000	686	17
3350000	850000	687	12
3350000	850000	688	24
3350000	850000	689	6
3350000	850000	690	4
3350000	850000	691	18
3350000	850000	692	13
3350000	850000	693	10
3350000	850000	694	13
3350000	850000	695	17
3350000	850000	696	15
3350000	850000	697	26
3350000	850000	698	14
3350000	850000	699	8
3350000	850000	700	12
3350000	850000	701	12
3350000	850000	702	17
3350000	850000	703	14
3350000	850000	704	13
3350000	850000	705	13
3350000	850000	706	11
3350000	850000	707	12
3350000	850000	708	20
3350000	850000	709	8
3350000	850000	710	13
3350000	850000	711	19
3350000	850000	712	14
3350000	850000	713	11
3350000	850000	714	16
3350000	850000	715	15
3350000	850000	716	15
3350000	850000	717	19
3350000	850000	718	11
3350000	850000	719	18
3350000	850000	720	17
3350000	850000	721	17
3350000	850000	722	21
3350000	850000	723	9
3350000	850000	724	10
3350000	850000	725	16
3350000	850000	726	13
3350000	850000	727	11
3350000	850000	728	13
3350000	850000	729	19
3350000	850000	730	19
3350000	850000	731	8
3350000	850000	732	17
3350000	850000	733	23
3350000	850000	734	13
3350000	850000	735	15
3350000	850000	736	15
3350000	850000	737	8
3350000	850000	738	15
3350000	850000	739	22
3350000	850000	740	8
3350000	850000	741	14
3350000	850000	742	11
3350000	850000	743	18
3350000	850000	744	13
3350000	850000	745	18
3350000	850000	746	14
3350000	850000	747	21
3350000	850000	748	12
3350000	850000	749	14
3350000	850000	750	10
3350000	850000	751	12
3350000	850000	752	15
3350000	850000	753	19
3350000	850000	754	12
3350000	850000	755	10
3350000	850000	756	20
3350000	850000	757	15
3350000	850000	758	14
3350000	850000	759	14
3350000	850000	760	7
3350000	850000	761	12
3350000	850000	762	17
3350000	850000	763	22
3350000	850000	764	14
3350000	850000	765	12
3350000	850000	766	14
3350000	850000	767	17
3350000	850000	768	14
3350000	850000	769	12
3350000	850000	770	9
3350000	850000	771	16
3350000	850000	772	10
3350000	850000	773	11
3350000	850000	774	15
3350000	850000	775	16
3350000	850000	776	9
3350000	850000	777	17
3350000	850000	778	8
3350000	850000	779	14
3350000	850000	780	7
3350000	850000	781	22
3350000	850000	782	7
3350000	850000	783	18
3350000	850000	784	13
3350000	850000	785	14
3350000	850000	786	18
3350000	850000	787	13
3350000	850000	788	8
3350000	850000	789	16
3350000	850000	790	13
3350000	850000	791	23
3350000	850000	792	12
3350000	850000	793	7
3350000	850000	794	8
3350000	850000	795	16
3350000	850000	796	10
3350000	850000	797	16
3350000	850000	798	7
3350000	850000	799	16
3350000	850000	800	14
3350000	850000	801	14
3350000	850000	802	5
3350000	850000	803	12
3350000	850000	804	13
3350000	850000	805	15
3350000	850000	806	13
3350000	850000	807	13
3350000	850000	808	14
3350000	850000	809	12
3350000	850000	810	8
3350000	850000	811	11
3350000	850000	812	14
3350000	850000	813	12
3350000	850000	814	15
3350000	850000	815	8
3350000	850000	816	15
3350000	850000	817	12
3350000	850000	818	12
3350000	850000	819	11
3350000	850000	820	11
3350000	850000	821	12
3350000	850000	822	12
3350000	850000	823	10
3350000	850000	824	3
3350000	850000	825	10
3350000	850000	826	22
3350000	850000	827	6
3350000	850000	828	6
3350000	850000	829	15
3350000	850000	830	11
3350000	850000	831	4
3350000	850000	832	13
3350000	850000	833	12
3350000	850000	834	13
3350000	850000	835	12
3350000	850000	836	9
3350000	850000	837	10
3350000	850000	838	12
3350000	850000	839	20
3350000	850000	840	10
3350000	850000	841	17
3350000	850000	842	10
3350000	850000	843	13
3350000	850000	844	7
3350000	850000	845	9
3350000	850000	846	16
3350000	850000	847	6
3350000	850000	848	6
3350000	850000	849	12
3350000	850000	850	11
3350000	850000	851	17
3350000	850000	852	12
3350000	850000	853	6
3350000	850000	854	10
3350000	850000	855	12
3350000	850000	856	9
3350000	850000	857	13
3350000	850000	858	5
3350000	850000	859	6
3350000	850000	860	10
3350000	850000	861	15
3350000	850000	862	11
3350000	850000	863	9
3350000	850000	864	10
3350000	850000	865	4
3350000	850000	866	7
3350000	850000	867	17
3350000	850000	868	11
3350000	850000	869	12
3350000	850000	870	14
3350000	850000	871	14
3350000	850000	872	9
3350000	850000	873	20
3350000	850000	874	20
3350000	850000	875	3
3350000	850000	876	12
3350000	850000	877	16
3350000	850000	878	11
3350000	850000	879	8
3350000	850000	880	11
3350000	850000	881	8
3350000	850000	882	11
3350000	850000	883	6
3350000	850000	884	10
3350000	850000	885	13
3350000	850000	886	16
3350000	850000	887	13
3350000	850000	888	14
3350000	850000	889	11
3350000	850000	890	7
3350000	850000	891	10
3350000	850000	892	8
3350000	850000	893	4
3350000	850000	894	10
3350000	850000	895	11
3350000	850000	896	15
3350000	850000	897	6
3350000	850000	898	4
3350000	850000	899	10
3350000	850000	900	11
3350000	850000	901	17
3350000	850000	902	9
3350000	850000	903	11
3350000	850000	904	13
3350000	850000	905	11
3350000	850000	906	9
3350000	850000	907	9
3350000	850000	908	15
3350000	850000	909	15
3350000	850000	910	11
3350000	850000	911	6
3350000	850000	912	12
3350000	850000	913	11
3350000	850000	914	13
3350000	850000	915	11
3350000	850000	916	12
3350000	850000	917	10
3350000	850000	918	17
3350000	850000	919	16
3350000	850000	920	11
3350000	850000	921	14
3350000	850000	922	5
3350000	850000	923	15
3350000	850000	924	11
3350000	850000	925	11
3350000	850000	926	12
3350000	850000	927	10
3350000	850000	928	17
3350000	850000	929	12
3350000	850000	930	12
3350000	850000	931	11
3350000	850000	932	7
3350000	850000	933	6
3350000	850000	934	18
3350000	850000	935	10
3350000	850000	936	10
3350000	850000	937	9
3350000	850000	938	12
3350000	850000	939	11
3350000	850000	940	6
3350000	850000	941	7
3350000	850000	942	15
3350000	850000	943	12
3350000	850000	944	13
3350000	850000	945	12
3350000	850000	946	10
3350000	850000	947	11
3350000	850000	948	7
3350000	850000	949	16
3350000	850000	950	9
3350000	850000	951	6
3350000	850000	952	12
3350000	850000	953	9
3350000	850000	954	10
3350000	850000	955	13
3350000	850000	956	8
3350000	850000	957	16
3350000	850000	958	6
3350000	850000	959	10
3350000	850000	960	10
3350000	850000	961	7
3350000	850000	962	8
3350000	850000	963	13
3350000	850000	964	5
3350000	850000	965	13
3350000	850000	966	8
3350000	850000	967	10
3350000	850000	968	6
3350000	850000	969	14
3350000	850000	970	8
3350000	850000	971	11
3350000	850000	972	6
3350000	850000	973	6
3350000	850000	974	8
3350000	850000	975	7
3350000	850000	976	6
3350000	850000	977	7
3350000	850000	978	10
3350000	850000	979	12
3350000	850000	980	7
3350000	850000	981	9
3350000	850000	982	8
3350000	850000	983	10
3350000	850000	984	7
3350000	850000	985	10
3350000	850000	986	4
3350000	850000	987	1
3350000	850000	988	3
3350000	850000	989	7
3350000	850000	990	4
3350000	850000	991	3
3350000	850000	992	5
3350000	850000	993	9
3350000	850000	994	6
3350000	850000	995	9
3350000	850000	996	9
3350000	850000	997	11
3350000	850000	998	9
3350000	850000	999	11
3350000	950000	1000	7
3350000	950000	1001	3
3350000	950000	1002	7
3350000	950000	1003	12
3350000	950000	1004	9
3350000	950000	1005	6
3350000	950000	1006	4
3350000	950000	1007	12
3350000	950000	1008	8
3350000	950000	1009	5
3350000	950000	1010	2
3350000	950000	1011	10
3350000	950000	1012	4
3350000	950000	1013	5
3350000	950000	1014	7
3350000	950000	1015	9
3350000	950000	1016	10
3350000	950000	1017	3
3350000	950000	1018	6
3350000	950000	1019	10
3350000	950000	1020	10
3350000	950000	1021	12
3350000	950000	1022	10
3350000	950000	1023	6
3350000	950000	1024	8
3350000	950000	1025	5
3350000	950000	1026	12
3350000	950000	1027	7
3350000	950000	1028	7
3350000	950000	1029	7
3350000	950000	1030	8
3350000	950000	1031	4
3350000	950000	1032	7
3350000	950000	1033	6
3350000	950000	1034	6
3350000	950000	1035	6
3350000	950000	1036	8
3350000	950000	1037	11
3350000	950000	1038	6
3350000	950000	1039	9
3350000	950000	1040	2
3350000	950000	1041	9
3350000	950000	1042	8
3350000	950000	1043	7
3350000	950000	1044	6
3350000	950000	1045	6
3350000	950000	1046	12
3350000	950000	1047	3
3350000	950000	1048	11
3350000	950000	1049	6
3350000	950000	1050	16
3350000	950000	1051	6
3350000	950000	1052	9
3350000	950000	1053	4
3350000	950000	1054	4
3350000	950000	1055	6
3350000	950000	1056	3
3350000	950000	1057	10
3350000	950000	1058	10
3350000	950000	1059	12
3350000	950000	1060	10
3350000	950000	1061	4
3350000	950000	1062	9
3350000	950000	1063	9
3350000	950000	1064	11
3350000	950000	1065	4
3350000	950000	1066	12
3350000	950000	1067	6
3350000	950000	1068	6
3350000	950000	1069	9
3350000	950000	1070	5
3350000	950000	1071	8
3350000	950000	1072	12
3350000	950000	1073	9
3350000	950000	1074	3
3350000	950000	1075	15
3350000	950000	1076	7
3350000	950000	1077	9
3350000	950000	1078	5
3350000	950000	1079	10
3350000	950000	1080	5
3350000	950000	1081	4
3350000	950000	1082	10
3350000	950000	1083	12
3350000	950000	1084	6
3350000	950000	1085	11
3350000	950000	1086	10
3350000	950000	1087	4
3350000	950000	1088	8
3350000	950000	1089	9
3350000	950000	1090	8
3350000	950000	1091	11
3350000	950000	1092	9
3350000	950000	1093	6
3350000	950000	1094	4
3350000	950000	1095	5
3350000	950000	1096	6
3350000	950000	1097	10
3350000	950000	1098	12
3350000	950000	1099	4
3350000	950000	1100	9
3350000	950000	1101	7
3350000	950000	1102	9
3350000	950000	1103	11
3350000	950000	1104	8
3350000	950000	1105	8
3350000	950000	1106	10
3350000	950000	1107	12
3350000	950000	1108	6
3350000	950000	1109	7
3350000	950000	1110	12
3350000	950000	1111	7
3350000	950000	1112	17
3350000	950000	1113	12
3350000	950000	1114	6
3350000	950000	1115	13
3350000	950000	1116	6
3350000	950000	1117	7
3350000	950000	1118	8
3350000	950000	1119	6
3350000	950000	1120	9
3350000	950000	1121	9
3350000	950000	1122	10
3350000	950000	1123	10
3350000	950000	1124	7
3350000	950000	1125	8
3350000	950000	1126	11
3350000	950000	1127	5
3350000	950000	1128	10
3350000	950000	1129	4
3350000	950000	1130	10
3350000	950000	1131	13
3350000	950000	1132	18
3350000	950000	1133	15
3350000	950000	1134	8
3350000	950000	1135	11
3350000	950000	1136	12
3350000	950000	1137	15
3350000	950000	1138	10
3350000	950000	1139	8
3350000	950000	1140	8
3350000	950000	1141	12
3350000	950000	1142	13
3350000	950000	1143	10
3350000	950000	1144	15
3350000	950000	1145	11
3350000	950000	1146	8
3350000	950000	1147	6
3350000	950000	1148	8
3350000	950000	1149	16
3350000	950000	1150	5
3350000	950000	1151	9
3350000	950000	1152	8
3350000	950000	1153	10
3350000	950000	1154	10
3350000	950000	1155	12
3350000	950000	1156	11
3350000	950000	1157	5
3350000	950000	1158	8
3350000	950000	1159	8
3350000	950000	1160	7
3350000	950000	1161	11
3350000	950000	1162	13
3350000	950000	1163	9
3350000	950000	1164	12
3350000	950000	1165	12
3350000	950000	1166	14
3350000	950000	1167	5
3350000	950000	1168	11
3350000	950000	1169	12
3350000	950000	1170	20
3350000	950000	1171	14
3350000	950000	1172	11
3350000	950000	1173	6
3350000	950000	1174	8
3350000	950000	1175	10
3350000	950000	1176	8
3350000	950000	1177	10
3350000	950000	1178	6
3350000	950000	1179	14
3350000	950000	1180	22
3350000	950000	1181	15
3350000	950000	1182	16
3350000	950000	1183	14
3350000	950000	1184	21
3350000	950000	1185	8
3350000	950000	1186	11
3350000	950000	1187	11
3350000	950000	1188	13
3350000	950000	1189	7
3350000	950000	1190	14
3350000	950000	1191	14
3350000	950000	1192	7
3350000	950000	1193	7
3350000	950000	1194	12
3350000	950000	1195	14
3350000	950000	1196	3
3350000	950000	1197	14
3350000	950000	1198	13
3350000	950000	1199	12
3350000	950000	1200	10
3350000	950000	1201	16
3350000	950000	1202	10
3350000	950000	1203	10
3350000	950000	1204	11
3350000	950000	1205	10
3350000	950000	1206	12
3350000	950000	1207	8
3350000	950000	1208	10
3350000	950000	1209	6
3350000	950000	1210	14
3350000	950000	1211	12
3350000	950000	1212	7
3350000	950000	1213	13
3350000	950000	1214	9
3350000	950000	1215	9
3350000	950000	1216	10
3350000	950000	1217	9
3350000	950000	1218	13
3350000	950000	1219	17
3350000	950000	1220	15
3350000	950000	1221	10
3350000	950000	1222	11
3350000	950000	1223	14
3350000	950000	1224	21
3350000	950000	1225	13
3350000	950000	1226	12
3350000	950000	1227	16
3350000	950000	1228	6
3350000	950000	1229	10
3350000	950000	1230	13
3350000	950000	1231	5
3350000	950000	1232	9
3350000	950000	1233	10
3350000	950000	1234	12
3350000	950000	1235	9
3350000	950000	1236	11
3350000	950000	1237	5
3350000	950000	1238	12
3350000	950000	1239	14
3350000	950000	1240	8
3350000	950000	1241	18
3350000	950000	1242	17
3350000	950000	1243	9
3350000	950000	1244	13
3350000	950000	1245	16
3350000	950000	1246	15
3350000	950000	1247	3
3350000	950000	1248	12
3350000	950000	1249	24
3350000	950000	1250	6
3350000	950000	1251	6
3350000	950000	1252	18
3350000	950000	1253	8
3350000	950000	1254	14
3350000	950000	1255	15
3350000	950000	1256	8
3350000	950000	1257	17
3350000	950000	1258	17
3350000	950000	1259	9
3350000	950000	1260	16
3350000	950000	1261	17
3350000	950000	1262	11
3350000	950000	1263	14
3350000	950000	1264	15
3350000	950000	1265	14
3350000	950000	1266	10
3350000	950000	1267	13
3350000	950000	1268	9
3350000	950000	1269	24
3350000	950000	1270	15
3350000	950000	1271	17
3350000	950000	1272	20
3350000	950000	1273	15
3350000	950000	1274	15
3350000	950000	1275	13
3350000	950000	1276	14
3350000	950000	1277	14
3350000	950000	1278	23
3350000	950000	1279	15
3350000	950000	1280	19
3350000	950000	1281	14
3350000	950000	1282	17
3350000	950000	1283	15
3350000	950000	1284	13
3350000	950000	1285	16
3350000	950000	1286	13
3350000	950000	1287	16
3350000	950000	1288	13
3350000	950000	1289	11
3350000	950000	1290	14
3350000	950000	1291	18
3350000	950000	1292	10
3350000	950000	1293	12
3350000	950000	1294	10
3350000	950000	1295	10
3350000	950000	1296	15
3350000	950000	1297	14
3350000	950000	1298	12
3350000	950000	1299	14
3350000	950000	1300	14
3350000	950000	1301	12
3350000	950000	1302	20
3350000	950000	1303	8
3350000	950000	1304	14
3350000	950000	1305	7
3350000	950000	1306	8
3350000	950000	1307	13
3350000	950000	1308	13
3350000	950000	1309	9
3350000	950000	1310	7
3350000	950000	1311	15
3350000	950000	1312	4
3350000	950000	1313	4
3350000	950000	1314	7
3350000	950000	1315	3
3350000	950000	1316	4
3350000	950000	1317	5
3350000	950000	1318	3
3350000	950000	1319	1
3350000	950000	1320	2
3350000	950000	1321	2
3350000	950000	1322	4
3350000	950000	1323	3
3350000	950000	1324	7
3350000	950000	1325	3
3350000	950000	1326	3
3350000	950000	1327	4
3350000	950000	1328	4
3350000	950000	1329	3
3350000	950000	1330	2
3350000	950000	1331	3
3350000	950000	1332	1
3350000	950000	1333	1
3350000	950000	1334	1
3350000	950000	1335	3
3350000	950000	1336	5
3350000	950000	1337	1
3350000	950000	1338	1
3350000	950000	1339	3
3350000	950000	1340	5
3350000	950000	1341	3
3350000	950000	1342	1
3350000	950000	1343	4
3350000	950000	1344	1
3350000	950000	1345	1
3350000	950000	1346	2
3350000	950000	1347	2
3350000	950000	1348	2
3350000	950000	1349	4
3350000	950000	1351	2
3350000	950000	1352	1
3350000	950000	1353	1
3350000	950000	1354	2
3350000	950000	1356	2
3350000	950000	1357	1
3350000	950000	1358	1
3350000	950000	1359	2
3350000	950000	1360	1
3350000	950000	1362	2
3350000	950000	1363	4
3350000	950000	1364	1
3350000	950000	1366	3
3350000	950000	1367	1
3350000	950000	1369	1
3350000	950000	1372	5
3350000	950000	1373	2
3350000	950000	1374	2
3350000	950000	1376	1
3350000	950000	1378	1
3350000	950000	1379	1
3350000	950000	1380	2
3350000	950000	1382	5
3350000	950000	1383	5
3350000	950000	1384	1
3350000	950000	1387	2
3350000	950000	1388	2
3350000	950000	1390	1
3350000	950000	1393	1
3350000	950000	1394	1
3350000	950000	1395	2
3350000	950000	1402	1
3350000	950000	1405	1
3350000	950000	1406	1
3350000	950000	1408	1
3350000	950000	1409	2
3350000	950000	1410	3
3350000	950000	1411	2
3350000	950000	1412	1
3350000	950000	1413	1
3350000	950000	1414	1
3350000	950000	1415	2
3350000	950000	1416	1
3350000	950000	1417	2
3350000	950000	1418	1
3350000	950000	1419	3
3350000	950000	1422	1
3350000	950000	1423	1
3350000	950000	1424	2
3350000	950000	1427	1
3350000	950000	1428	2
3350000	950000	1430	1
3350000	950000	1431	1
3350000	950000	1433	2
3350000	950000	1435	2
3350000	950000	1436	1
3350000	950000	1443	2
3350000	950000	1446	1
3350000	950000	1447	2
3350000	950000	1450	1
3350000	950000	1451	1
3350000	950000	1452	2
3350000	950000	1458	2
3350000	950000	1459	1
3350000	950000	1460	1
3350000	950000	1474	3
3350000	950000	1488	1
3350000	950000	1489	2
3350000	950000	1503	1
3350000	950000	1505	1
3350000	950000	1507	1
3350000	950000	1509	1
3350000	950000	1510	1
3350000	950000	1521	1
3350000	950000	1523	1
3350000	950000	1527	1
3350000	950000	1548	1
3350000	950000	1555	1
3350000	950000	1562	1
3350000	950000	1569	1
3350000	950000	1572	1
3350000	950000	1585	1
3350000	950000	1660	1
3350000	950000	604	5
3350000	950000	605	1
3350000	950000	606	4
3350000	950000	607	3
3350000	950000	608	2
3350000	950000	609	3
3350000	950000	610	1
3350000	950000	611	3
3350000	950000	612	6
3350000	950000	613	6
3350000	950000	614	4
3350000	950000	615	6
3350000	950000	616	7
3350000	950000	617	17
3350000	950000	618	6
3350000	950000	619	8
3350000	950000	620	14
3350000	950000	621	8
3350000	950000	622	11
3350000	950000	623	8
3350000	950000	624	13
3350000	950000	625	10
3350000	950000	626	12
3350000	950000	627	7
3350000	950000	628	9
3350000	950000	629	17
3350000	950000	630	13
3350000	950000	631	15
3350000	950000	632	11
3350000	950000	633	16
3350000	950000	634	13
3350000	950000	635	18
3350000	950000	636	19
3350000	950000	637	10
3350000	950000	638	12
3350000	950000	639	21
3350000	950000	640	27
3350000	950000	641	21
3350000	950000	642	19
3350000	950000	643	31
3350000	950000	644	45
3350000	950000	645	32
3350000	950000	646	31
3350000	950000	647	35
3350000	950000	648	37
3350000	950000	649	37
3350000	950000	650	45
3350000	950000	651	40
3350000	950000	652	38
3350000	950000	653	49
3350000	950000	654	51
3350000	950000	655	49
3350000	950000	656	53
3350000	950000	657	66
3350000	950000	658	50
3350000	950000	659	54
3350000	950000	660	66
3350000	950000	661	59
3350000	950000	662	49
3350000	950000	663	65
3350000	950000	664	44
3350000	950000	665	59
3350000	950000	666	42
3350000	950000	667	63
3350000	950000	668	51
3350000	950000	669	61
3350000	950000	670	50
3350000	950000	671	52
3350000	950000	672	48
3350000	950000	673	51
3350000	950000	674	48
3350000	950000	675	62
3350000	950000	676	65
3350000	950000	677	29
3350000	950000	678	46
3350000	950000	679	45
3350000	950000	680	38
3350000	950000	681	33
3350000	950000	682	48
3350000	950000	683	32
3350000	950000	684	41
3350000	950000	685	50
3350000	950000	686	41
3350000	950000	687	45
3350000	950000	688	48
3350000	950000	689	33
3350000	950000	690	42
3350000	950000	691	38
3350000	950000	692	32
3350000	950000	693	43
3350000	950000	694	32
3350000	950000	695	41
3350000	950000	696	54
3350000	950000	697	37
3350000	950000	698	48
3350000	950000	699	43
3350000	950000	700	59
3350000	950000	701	46
3350000	950000	702	53
3350000	950000	703	49
3350000	950000	704	49
3350000	950000	705	43
3350000	950000	706	43
3350000	950000	707	47
3350000	950000	708	48
3350000	950000	709	41
3350000	950000	710	39
3350000	950000	711	51
3350000	950000	712	29
3350000	950000	713	51
3350000	950000	714	33
3350000	950000	715	39
3350000	950000	716	38
3350000	950000	717	41
3350000	950000	718	29
3350000	950000	719	35
3350000	950000	720	18
3350000	950000	721	35
3350000	950000	722	23
3350000	950000	723	29
3350000	950000	724	26
3350000	950000	725	26
3350000	950000	726	24
3350000	950000	727	22
3350000	950000	728	27
3350000	950000	729	36
3350000	950000	730	24
3350000	950000	731	23
3350000	950000	732	12
3350000	950000	733	18
3350000	950000	734	31
3350000	950000	735	24
3350000	950000	736	17
3350000	950000	737	26
3350000	950000	738	22
3350000	950000	739	11
3350000	950000	740	17
3350000	950000	741	18
3350000	950000	742	20
3350000	950000	743	17
3350000	950000	744	15
3350000	950000	745	17
3350000	950000	746	10
3350000	950000	747	11
3350000	950000	748	14
3350000	950000	749	22
3350000	950000	750	17
3350000	950000	751	18
3350000	950000	752	24
3350000	950000	753	10
3350000	950000	754	11
3350000	950000	755	12
3350000	950000	756	12
3350000	950000	757	13
3350000	950000	758	8
3350000	950000	759	11
3350000	950000	760	9
3350000	950000	761	17
3350000	950000	762	13
3350000	950000	763	7
3350000	950000	764	13
3350000	950000	765	11
3350000	950000	766	11
3350000	950000	767	11
3350000	950000	768	12
3350000	950000	769	21
3350000	950000	770	6
3350000	950000	771	8
3350000	950000	772	8
3350000	950000	773	14
3350000	950000	774	7
3350000	950000	775	10
3350000	950000	776	10
3350000	950000	777	12
3350000	950000	778	8
3350000	950000	779	8
3350000	950000	780	8
3350000	950000	781	5
3350000	950000	782	9
3350000	950000	783	14
3350000	950000	784	11
3350000	950000	785	14
3350000	950000	786	7
3350000	950000	787	12
3350000	950000	788	10
3350000	950000	789	10
3350000	950000	790	14
3350000	950000	791	8
3350000	950000	792	11
3350000	950000	793	6
3350000	950000	794	10
3350000	950000	795	5
3350000	950000	796	9
3350000	950000	797	12
3350000	950000	798	4
3350000	950000	799	13
3350000	950000	800	11
3350000	950000	801	6
3350000	950000	802	15
3350000	950000	803	11
3350000	950000	804	10
3350000	950000	805	8
3350000	950000	806	8
3350000	950000	807	13
3350000	950000	808	10
3350000	950000	809	10
3350000	950000	810	10
3350000	950000	811	7
3350000	950000	812	11
3350000	950000	813	12
3350000	950000	814	11
3350000	950000	815	10
3350000	950000	816	14
3350000	950000	817	9
3350000	950000	818	5
3350000	950000	819	13
3350000	950000	820	9
3350000	950000	821	6
3350000	950000	822	8
3350000	950000	823	10
3350000	950000	824	7
3350000	950000	825	9
3350000	950000	826	10
3350000	950000	827	7
3350000	950000	828	10
3350000	950000	829	5
3350000	950000	830	12
3350000	950000	831	10
3350000	950000	832	6
3350000	950000	833	15
3350000	950000	834	7
3350000	950000	835	16
3350000	950000	836	5
3350000	950000	837	8
3350000	950000	838	13
3350000	950000	839	4
3350000	950000	840	7
3350000	950000	841	8
3350000	950000	842	17
3350000	950000	843	6
3350000	950000	844	10
3350000	950000	845	12
3350000	950000	846	7
3350000	950000	847	11
3350000	950000	848	5
3350000	950000	849	5
3350000	950000	850	6
3350000	950000	851	14
3350000	950000	852	6
3350000	950000	853	14
3350000	950000	854	5
3350000	950000	855	10
3350000	950000	856	8
3350000	950000	857	4
3350000	950000	858	9
3350000	950000	859	5
3350000	950000	860	5
3350000	950000	861	2
3350000	950000	862	7
3350000	950000	863	3
3350000	950000	864	7
3350000	950000	865	12
3350000	950000	866	7
3350000	950000	867	16
3350000	950000	868	8
3350000	950000	869	7
3350000	950000	870	5
3350000	950000	871	10
3350000	950000	872	10
3350000	950000	873	10
3350000	950000	874	9
3350000	950000	875	13
3350000	950000	876	7
3350000	950000	877	10
3350000	950000	878	9
3350000	950000	879	4
3350000	950000	880	8
3350000	950000	881	6
3350000	950000	882	6
3350000	950000	883	6
3350000	950000	884	6
3350000	950000	885	8
3350000	950000	886	9
3350000	950000	887	4
3350000	950000	888	7
3350000	950000	889	10
3350000	950000	890	9
3350000	950000	891	7
3350000	950000	892	10
3350000	950000	893	5
3350000	950000	894	10
3350000	950000	895	7
3350000	950000	896	8
3350000	950000	897	6
3350000	950000	898	10
3350000	950000	899	5
3350000	950000	900	9
3350000	950000	901	6
3350000	950000	902	8
3350000	950000	903	5
3350000	950000	904	7
3350000	950000	905	6
3350000	950000	906	2
3350000	950000	907	6
3350000	950000	909	6
3350000	950000	910	4
3350000	950000	911	2
3350000	950000	912	6
3350000	950000	913	3
3350000	950000	914	6
3350000	950000	915	9
3350000	950000	916	9
3350000	950000	917	5
3350000	950000	918	5
3350000	950000	919	9
3350000	950000	920	6
3350000	950000	921	5
3350000	950000	922	3
3350000	950000	923	5
3350000	950000	924	5
3350000	950000	925	5
3350000	950000	926	11
3350000	950000	927	7
3350000	950000	928	2
3350000	950000	929	6
3350000	950000	930	6
3350000	950000	931	8
3350000	950000	932	8
3350000	950000	933	3
3350000	950000	934	9
3350000	950000	935	6
3350000	950000	936	9
3350000	950000	937	5
3350000	950000	938	7
3350000	950000	939	7
3350000	950000	940	3
3350000	950000	941	9
3350000	950000	942	2
3350000	950000	943	10
3350000	950000	944	3
3350000	950000	945	6
3350000	950000	946	4
3350000	950000	947	6
3350000	950000	948	7
3350000	950000	949	5
3350000	950000	950	5
3350000	950000	951	9
3350000	950000	952	5
3350000	950000	953	6
3350000	950000	954	5
3350000	950000	955	8
3350000	950000	956	5
3350000	950000	957	7
3350000	950000	958	11
3350000	950000	959	6
3350000	950000	960	3
3350000	950000	961	12
3350000	950000	962	6
3350000	950000	963	3
3350000	950000	964	7
3350000	950000	965	6
3350000	950000	966	2
3350000	950000	967	6
3350000	950000	968	7
3350000	950000	969	7
3350000	950000	970	8
3350000	950000	971	8
3350000	950000	972	4
3350000	950000	973	6
3350000	950000	974	4
3350000	950000	975	12
3350000	950000	976	6
3350000	950000	977	9
3350000	950000	978	6
3350000	950000	979	6
3350000	950000	980	18
3350000	950000	981	5
3350000	950000	982	8
3350000	950000	983	12
3350000	950000	984	3
3350000	950000	985	3
3350000	950000	986	9
3350000	950000	987	3
3350000	950000	988	11
3350000	950000	989	6
3350000	950000	990	7
3350000	950000	991	8
3350000	950000	992	5
3350000	950000	993	3
3350000	950000	994	9
3350000	950000	995	6
3350000	950000	996	6
3350000	950000	997	2
3350000	950000	998	5
3350000	950000	999	4
3450000	1050000	1000	6
3450000	1050000	1001	6
3450000	1050000	1002	5
3450000	1050000	1003	6
3450000	1050000	1004	4
3450000	1050000	1005	3
3450000	1050000	1006	6
3450000	1050000	1007	5
3450000	1050000	1008	4
3450000	1050000	1009	8
3450000	1050000	1010	3
3450000	1050000	1011	6
3450000	1050000	1012	2
3450000	1050000	1013	2
3450000	1050000	1014	4
3450000	1050000	1015	3
3450000	1050000	1016	1
3450000	1050000	1017	6
3450000	1050000	1018	8
3450000	1050000	1019	2
3450000	1050000	1020	6
3450000	1050000	1021	6
3450000	1050000	1022	1
3450000	1050000	1024	4
3450000	1050000	1025	5
3450000	1050000	1026	7
3450000	1050000	1027	4
3450000	1050000	1028	5
3450000	1050000	1029	8
3450000	1050000	1030	7
3450000	1050000	1031	3
3450000	1050000	1032	6
3450000	1050000	1033	8
3450000	1050000	1034	3
3450000	1050000	1035	5
3450000	1050000	1036	3
3450000	1050000	1037	5
3450000	1050000	1038	4
3450000	1050000	1039	5
3450000	1050000	1040	2
3450000	1050000	1041	7
3450000	1050000	1042	6
3450000	1050000	1043	3
3450000	1050000	1044	2
3450000	1050000	1045	3
3450000	1050000	1046	2
3450000	1050000	1047	4
3450000	1050000	1049	6
3450000	1050000	1050	2
3450000	1050000	1051	4
3450000	1050000	1052	5
3450000	1050000	1053	7
3450000	1050000	1054	6
3450000	1050000	1056	5
3450000	1050000	1057	2
3450000	1050000	1058	2
3450000	1050000	1060	1
3450000	1050000	1061	6
3450000	1050000	1062	4
3450000	1050000	1063	2
3450000	1050000	1064	2
3450000	1050000	1065	5
3450000	1050000	1066	7
3450000	1050000	1067	1
3450000	1050000	1068	3
3450000	1050000	1069	2
3450000	1050000	1070	4
3450000	1050000	1071	2
3450000	1050000	1072	3
3450000	1050000	1073	4
3450000	1050000	1074	2
3450000	1050000	1075	7
3450000	1050000	1076	2
3450000	1050000	1077	2
3450000	1050000	1078	4
3450000	1050000	1079	3
3450000	1050000	1081	2
3450000	1050000	1082	3
3450000	1050000	1083	5
3450000	1050000	1084	1
3450000	1050000	1085	7
3450000	1050000	1086	2
3450000	1050000	1087	2
3450000	1050000	1088	3
3450000	1050000	1089	3
3450000	1050000	1090	5
3450000	1050000	1091	3
3450000	1050000	1092	3
3450000	1050000	1093	5
3450000	1050000	1094	3
3450000	1050000	1095	3
3450000	1050000	1096	2
3450000	1050000	1097	2
3450000	1050000	1098	2
3450000	1050000	1099	7
3450000	1050000	1100	3
3450000	1050000	1101	2
3450000	1050000	1102	5
3450000	1050000	1103	3
3450000	1050000	1104	2
3450000	1050000	1105	3
3450000	1050000	1106	1
3450000	1050000	1107	3
3450000	1050000	1108	1
3450000	1050000	1109	2
3450000	1050000	1110	4
3450000	1050000	1111	1
3450000	1050000	1112	1
3450000	1050000	1113	1
3450000	1050000	1114	1
3450000	1050000	1115	2
3450000	1050000	1116	4
3450000	1050000	1117	1
3450000	1050000	1118	1
3450000	1050000	1119	3
3450000	1050000	1120	5
3450000	1050000	1121	1
3450000	1050000	1122	1
3450000	1050000	1123	2
3450000	1050000	1124	6
3450000	1050000	1125	2
3450000	1050000	1126	3
3450000	1050000	1127	3
3450000	1050000	1128	1
3450000	1050000	1129	1
3450000	1050000	1131	2
3450000	1050000	1134	1
3450000	1050000	1135	1
3450000	1050000	1136	1
3450000	1050000	1137	3
3450000	1050000	1138	1
3450000	1050000	1139	1
3450000	1050000	1142	1
3450000	1050000	1143	1
3450000	1050000	1146	5
3450000	1050000	1147	1
3450000	1050000	1150	1
3450000	1050000	1153	1
3450000	1050000	1157	2
3450000	1050000	1158	2
3450000	1050000	1159	1
3450000	1050000	1160	1
3450000	1050000	1161	1
3450000	1050000	1164	1
3450000	1050000	1169	1
3450000	1050000	1171	1
3450000	1050000	1172	2
3450000	1050000	1176	1
3450000	1050000	1180	1
3450000	1050000	1186	1
3450000	1050000	1191	1
3450000	1050000	1192	3
3450000	1050000	1197	1
3450000	1050000	1205	2
3450000	1050000	1209	1
3450000	1050000	1213	1
3450000	1050000	1216	1
3450000	1050000	1218	1
3450000	1050000	1219	2
3450000	1050000	1221	1
3450000	1050000	1224	1
3450000	1050000	1228	3
3450000	1050000	1230	1
3450000	1050000	1236	1
3450000	1050000	1239	2
3450000	1050000	1244	1
3450000	1050000	1248	3
3450000	1050000	1249	2
3450000	1050000	1255	2
3450000	1050000	1256	1
3450000	1050000	1259	1
3450000	1050000	1262	1
3450000	1050000	1263	1
3450000	1050000	1267	1
3450000	1050000	1272	2
3450000	1050000	1273	1
3450000	1050000	1274	1
3450000	1050000	1275	1
3450000	1050000	1281	1
3450000	1050000	1285	1
3450000	1050000	1294	1
3450000	1050000	1296	1
3450000	1050000	1297	1
3450000	1050000	1307	1
3450000	1050000	654	1
3450000	1050000	655	2
3450000	1050000	656	5
3450000	1050000	657	3
3450000	1050000	658	4
3450000	1050000	659	4
3450000	1050000	660	4
3450000	1050000	661	2
3450000	1050000	662	4
3450000	1050000	663	10
3450000	1050000	664	5
3450000	1050000	665	2
3450000	1050000	666	10
3450000	1050000	667	7
3450000	1050000	668	7
3450000	1050000	669	7
3450000	1050000	670	6
3450000	1050000	671	12
3450000	1050000	672	5
3450000	1050000	673	8
3450000	1050000	674	6
3450000	1050000	675	5
3450000	1050000	676	9
3450000	1050000	677	12
3450000	1050000	678	10
3450000	1050000	679	4
3450000	1050000	680	13
3450000	1050000	681	9
3450000	1050000	682	14
3450000	1050000	683	8
3450000	1050000	684	13
3450000	1050000	685	6
3450000	1050000	686	11
3450000	1050000	687	20
3450000	1050000	688	19
3450000	1050000	689	18
3450000	1050000	690	12
3450000	1050000	691	17
3450000	1050000	692	19
3450000	1050000	693	17
3450000	1050000	694	17
3450000	1050000	695	23
3450000	1050000	696	20
3450000	1050000	697	12
3450000	1050000	698	16
3450000	1050000	699	22
3450000	1050000	700	27
3450000	1050000	701	11
3450000	1050000	702	17
3450000	1050000	703	25
3450000	1050000	704	20
3450000	1050000	705	25
3450000	1050000	706	20
3450000	1050000	707	26
3450000	1050000	708	26
3450000	1050000	709	34
3450000	1050000	710	21
3450000	1050000	711	29
3450000	1050000	712	24
3450000	1050000	713	32
3450000	1050000	714	31
3450000	1050000	715	23
3450000	1050000	716	29
3450000	1050000	717	30
3450000	1050000	718	37
3450000	1050000	719	34
3450000	1050000	720	31
3450000	1050000	721	35
3450000	1050000	722	33
3450000	1050000	723	44
3450000	1050000	724	35
3450000	1050000	725	47
3450000	1050000	726	43
3450000	1050000	727	47
3450000	1050000	728	46
3450000	1050000	729	36
3450000	1050000	730	39
3450000	1050000	731	34
3450000	1050000	732	51
3450000	1050000	733	36
3450000	1050000	734	34
3450000	1050000	735	45
3450000	1050000	736	43
3450000	1050000	737	51
3450000	1050000	738	34
3450000	1050000	739	46
3450000	1050000	740	47
3450000	1050000	741	43
3450000	1050000	742	46
3450000	1050000	743	38
3450000	1050000	744	54
3450000	1050000	745	44
3450000	1050000	746	37
3450000	1050000	747	45
3450000	1050000	748	49
3450000	1050000	749	42
3450000	1050000	750	46
3450000	1050000	751	49
3450000	1050000	752	37
3450000	1050000	753	61
3450000	1050000	754	45
3450000	1050000	755	41
3450000	1050000	756	50
3450000	1050000	757	52
3450000	1050000	758	58
3450000	1050000	759	70
3450000	1050000	760	42
3450000	1050000	761	53
3450000	1050000	762	53
3450000	1050000	763	60
3450000	1050000	764	62
3450000	1050000	765	54
3450000	1050000	766	55
3450000	1050000	767	58
3450000	1050000	768	53
3450000	1050000	769	40
3450000	1050000	770	51
3450000	1050000	771	59
3450000	1050000	772	50
3450000	1050000	773	59
3450000	1050000	774	55
3450000	1050000	775	57
3450000	1050000	776	53
3450000	1050000	777	46
3450000	1050000	778	54
3450000	1050000	779	59
3450000	1050000	780	54
3450000	1050000	781	72
3450000	1050000	782	55
3450000	1050000	783	60
3450000	1050000	784	50
3450000	1050000	785	46
3450000	1050000	786	49
3450000	1050000	787	52
3450000	1050000	788	49
3450000	1050000	789	60
3450000	1050000	790	50
3450000	1050000	791	38
3450000	1050000	792	57
3450000	1050000	793	50
3450000	1050000	794	50
3450000	1050000	795	35
3450000	1050000	796	58
3450000	1050000	797	55
3450000	1050000	798	58
3450000	1050000	799	53
3450000	1050000	800	51
3450000	1050000	801	50
3450000	1050000	802	49
3450000	1050000	803	53
3450000	1050000	804	55
3450000	1050000	805	43
3450000	1050000	806	45
3450000	1050000	807	49
3450000	1050000	808	51
3450000	1050000	809	51
3450000	1050000	810	64
3450000	1050000	811	38
3450000	1050000	812	49
3450000	1050000	813	44
3450000	1050000	814	41
3450000	1050000	815	63
3450000	1050000	816	47
3450000	1050000	817	55
3450000	1050000	818	58
3450000	1050000	819	53
3450000	1050000	820	40
3450000	1050000	821	46
3450000	1050000	822	47
3450000	1050000	823	33
3450000	1050000	824	43
3450000	1050000	825	52
3450000	1050000	826	43
3450000	1050000	827	36
3450000	1050000	828	42
3450000	1050000	829	45
3450000	1050000	830	50
3450000	1050000	831	42
3450000	1050000	832	31
3450000	1050000	833	37
3450000	1050000	834	35
3450000	1050000	835	48
3450000	1050000	836	45
3450000	1050000	837	38
3450000	1050000	838	40
3450000	1050000	839	33
3450000	1050000	840	37
3450000	1050000	841	18
3450000	1050000	842	30
3450000	1050000	843	41
3450000	1050000	844	39
3450000	1050000	845	27
3450000	1050000	846	40
3450000	1050000	847	35
3450000	1050000	848	25
3450000	1050000	849	29
3450000	1050000	850	27
3450000	1050000	851	29
3450000	1050000	852	41
3450000	1050000	853	32
3450000	1050000	854	34
3450000	1050000	855	39
3450000	1050000	856	20
3450000	1050000	857	23
3450000	1050000	858	32
3450000	1050000	859	31
3450000	1050000	860	33
3450000	1050000	861	22
3450000	1050000	862	29
3450000	1050000	863	37
3450000	1050000	864	31
3450000	1050000	865	36
3450000	1050000	866	31
3450000	1050000	867	27
3450000	1050000	868	22
3450000	1050000	869	27
3450000	1050000	870	19
3450000	1050000	871	28
3450000	1050000	872	29
3450000	1050000	873	32
3450000	1050000	874	29
3450000	1050000	875	25
3450000	1050000	876	27
3450000	1050000	877	18
3450000	1050000	878	28
3450000	1050000	879	26
3450000	1050000	880	29
3450000	1050000	881	33
3450000	1050000	882	27
3450000	1050000	883	21
3450000	1050000	884	24
3450000	1050000	885	17
3450000	1050000	886	26
3450000	1050000	887	18
3450000	1050000	888	12
3450000	1050000	889	17
3450000	1050000	890	11
3450000	1050000	891	22
3450000	1050000	892	17
3450000	1050000	893	13
3450000	1050000	894	9
3450000	1050000	895	22
3450000	1050000	896	17
3450000	1050000	897	10
3450000	1050000	898	14
3450000	1050000	899	15
3450000	1050000	900	16
3450000	1050000	901	7
3450000	1050000	902	11
3450000	1050000	903	21
3450000	1050000	904	12
3450000	1050000	905	16
3450000	1050000	906	25
3450000	1050000	907	17
3450000	1050000	908	11
3450000	1050000	909	15
3450000	1050000	910	14
3450000	1050000	911	14
3450000	1050000	912	21
3450000	1050000	913	13
3450000	1050000	914	15
3450000	1050000	915	16
3450000	1050000	916	28
3450000	1050000	917	14
3450000	1050000	918	17
3450000	1050000	919	15
3450000	1050000	920	26
3450000	1050000	921	7
3450000	1050000	922	17
3450000	1050000	923	16
3450000	1050000	924	13
3450000	1050000	925	13
3450000	1050000	926	22
3450000	1050000	927	14
3450000	1050000	928	16
3450000	1050000	929	20
3450000	1050000	930	19
3450000	1050000	931	15
3450000	1050000	932	28
3450000	1050000	933	20
3450000	1050000	934	10
3450000	1050000	935	16
3450000	1050000	936	6
3450000	1050000	937	17
3450000	1050000	938	17
3450000	1050000	939	13
3450000	1050000	940	17
3450000	1050000	941	13
3450000	1050000	942	10
3450000	1050000	943	17
3450000	1050000	944	14
3450000	1050000	945	18
3450000	1050000	946	13
3450000	1050000	947	12
3450000	1050000	948	20
3450000	1050000	949	15
3450000	1050000	950	9
3450000	1050000	951	13
3450000	1050000	952	9
3450000	1050000	953	11
3450000	1050000	954	11
3450000	1050000	955	11
3450000	1050000	956	15
3450000	1050000	957	14
3450000	1050000	958	8
3450000	1050000	959	11
3450000	1050000	960	12
3450000	1050000	961	9
3450000	1050000	962	14
3450000	1050000	963	12
3450000	1050000	964	7
3450000	1050000	965	16
3450000	1050000	966	6
3450000	1050000	967	12
3450000	1050000	968	11
3450000	1050000	969	3
3450000	1050000	970	11
3450000	1050000	971	5
3450000	1050000	972	7
3450000	1050000	973	9
3450000	1050000	974	10
3450000	1050000	975	8
3450000	1050000	976	9
3450000	1050000	977	9
3450000	1050000	978	6
3450000	1050000	979	10
3450000	1050000	980	8
3450000	1050000	981	6
3450000	1050000	982	5
3450000	1050000	983	5
3450000	1050000	984	5
3450000	1050000	985	9
3450000	1050000	986	10
3450000	1050000	987	7
3450000	1050000	988	6
3450000	1050000	989	5
3450000	1050000	990	4
3450000	1050000	991	6
3450000	1050000	992	5
3450000	1050000	993	5
3450000	1050000	994	4
3450000	1050000	995	8
3450000	1050000	996	5
3450000	1050000	997	3
3450000	1050000	998	4
3450000	1050000	999	5
3450000	650000	1000	1
3450000	650000	1004	3
3450000	650000	1008	2
3450000	650000	1012	2
3450000	650000	1016	1
3450000	650000	1017	3
3450000	650000	1022	1
3450000	650000	1027	1
3450000	650000	1028	1
3450000	650000	1039	1
3450000	650000	1043	2
3450000	650000	1044	1
3450000	650000	1053	1
3450000	650000	1054	1
3450000	650000	1056	1
3450000	650000	1058	1
3450000	650000	1065	1
3450000	650000	1075	1
3450000	650000	1095	2
3450000	650000	1100	1
3450000	650000	1105	1
3450000	650000	1119	1
3450000	650000	1123	1
3450000	650000	1159	1
3450000	650000	1165	1
3450000	650000	901	1
3450000	650000	907	3
3450000	650000	908	1
3450000	650000	911	1
3450000	650000	914	1
3450000	650000	915	1
3450000	650000	916	2
3450000	650000	918	2
3450000	650000	919	1
3450000	650000	920	1
3450000	650000	921	2
3450000	650000	922	1
3450000	650000	924	2
3450000	650000	926	1
3450000	650000	927	2
3450000	650000	928	2
3450000	650000	930	1
3450000	650000	931	2
3450000	650000	932	2
3450000	650000	933	3
3450000	650000	934	3
3450000	650000	935	2
3450000	650000	936	3
3450000	650000	937	1
3450000	650000	938	2
3450000	650000	940	2
3450000	650000	941	1
3450000	650000	942	5
3450000	650000	943	1
3450000	650000	945	4
3450000	650000	946	1
3450000	650000	947	2
3450000	650000	948	2
3450000	650000	949	3
3450000	650000	951	1
3450000	650000	952	1
3450000	650000	953	2
3450000	650000	954	3
3450000	650000	956	1
3450000	650000	957	4
3450000	650000	958	2
3450000	650000	959	3
3450000	650000	960	1
3450000	650000	961	1
3450000	650000	963	2
3450000	650000	965	1
3450000	650000	966	3
3450000	650000	967	2
3450000	650000	968	1
3450000	650000	969	2
3450000	650000	971	1
3450000	650000	972	1
3450000	650000	976	2
3450000	650000	977	1
3450000	650000	978	1
3450000	650000	980	4
3450000	650000	981	3
3450000	650000	983	1
3450000	650000	984	1
3450000	650000	985	1
3450000	650000	987	3
3450000	650000	991	2
3450000	650000	994	2
3450000	650000	995	2
3450000	650000	996	1
3450000	650000	998	1
3450000	650000	999	2
3450000	750000	1000	8
3450000	750000	1001	4
3450000	750000	1002	8
3450000	750000	1003	7
3450000	750000	1004	9
3450000	750000	1005	7
3450000	750000	1006	7
3450000	750000	1007	8
3450000	750000	1009	7
3450000	750000	1010	4
3450000	750000	1011	7
3450000	750000	1012	12
3450000	750000	1013	4
3450000	750000	1014	7
3450000	750000	1015	3
3450000	750000	1016	10
3450000	750000	1017	8
3450000	750000	1018	2
3450000	750000	1019	2
3450000	750000	1020	3
3450000	750000	1021	5
3450000	750000	1022	3
3450000	750000	1023	8
3450000	750000	1024	1
3450000	750000	1025	4
3450000	750000	1026	5
3450000	750000	1027	4
3450000	750000	1028	4
3450000	750000	1029	3
3450000	750000	1030	1
3450000	750000	1031	2
3450000	750000	1032	2
3450000	750000	1033	3
3450000	750000	1035	5
3450000	750000	1036	2
3450000	750000	1037	4
3450000	750000	1038	6
3450000	750000	1039	4
3450000	750000	1040	2
3450000	750000	1041	2
3450000	750000	1042	4
3450000	750000	1043	3
3450000	750000	1044	5
3450000	750000	1045	1
3450000	750000	1046	4
3450000	750000	1047	2
3450000	750000	1048	4
3450000	750000	1049	5
3450000	750000	1050	3
3450000	750000	1051	5
3450000	750000	1052	3
3450000	750000	1053	3
3450000	750000	1054	1
3450000	750000	1056	1
3450000	750000	1057	2
3450000	750000	1058	3
3450000	750000	1059	3
3450000	750000	1060	1
3450000	750000	1061	2
3450000	750000	1062	1
3450000	750000	1063	2
3450000	750000	1065	3
3450000	750000	1067	2
3450000	750000	1068	4
3450000	750000	1069	7
3450000	750000	1070	1
3450000	750000	1072	1
3450000	750000	1073	2
3450000	750000	1074	4
3450000	750000	1075	2
3450000	750000	1076	2
3450000	750000	1078	3
3450000	750000	1083	1
3450000	750000	1084	2
3450000	750000	1085	1
3450000	750000	1086	1
3450000	750000	1088	2
3450000	750000	1089	1
3450000	750000	1093	1
3450000	750000	1095	2
3450000	750000	1096	1
3450000	750000	1098	1
3450000	750000	1101	2
3450000	750000	1105	1
3450000	750000	1106	2
3450000	750000	1108	2
3450000	750000	1109	2
3450000	750000	1110	2
3450000	750000	1114	1
3450000	750000	1115	1
3450000	750000	1117	1
3450000	750000	1119	1
3450000	750000	1120	1
3450000	750000	1121	1
3450000	750000	1122	1
3450000	750000	1123	2
3450000	750000	1125	1
3450000	750000	1126	2
3450000	750000	1132	2
3450000	750000	1136	1
3450000	750000	1138	1
3450000	750000	1139	2
3450000	750000	1141	1
3450000	750000	1142	2
3450000	750000	1148	1
3450000	750000	1151	1
3450000	750000	1153	1
3450000	750000	1154	1
3450000	750000	1157	2
3450000	750000	1163	2
3450000	750000	1164	1
3450000	750000	1170	1
3450000	750000	1173	1
3450000	750000	1185	1
3450000	750000	1195	1
3450000	750000	1197	1
3450000	750000	1210	1
3450000	750000	1211	1
3450000	750000	1232	1
3450000	750000	1255	1
3450000	750000	1268	1
3450000	750000	745	1
3450000	750000	746	1
3450000	750000	747	1
3450000	750000	748	2
3450000	750000	750	1
3450000	750000	751	1
3450000	750000	752	1
3450000	750000	754	2
3450000	750000	755	1
3450000	750000	756	1
3450000	750000	758	1
3450000	750000	759	1
3450000	750000	760	3
3450000	750000	761	1
3450000	750000	762	1
3450000	750000	763	2
3450000	750000	764	2
3450000	750000	765	1
3450000	750000	767	1
3450000	750000	768	1
3450000	750000	769	1
3450000	750000	770	5
3450000	750000	771	2
3450000	750000	772	1
3450000	750000	773	4
3450000	750000	774	1
3450000	750000	775	3
3450000	750000	776	1
3450000	750000	777	4
3450000	750000	778	3
3450000	750000	779	1
3450000	750000	780	1
3450000	750000	781	1
3450000	750000	782	3
3450000	750000	783	1
3450000	750000	785	4
3450000	750000	787	4
3450000	750000	788	2
3450000	750000	789	2
3450000	750000	790	1
3450000	750000	791	1
3450000	750000	792	2
3450000	750000	793	2
3450000	750000	794	2
3450000	750000	795	3
3450000	750000	796	1
3450000	750000	797	4
3450000	750000	800	6
3450000	750000	801	1
3450000	750000	802	2
3450000	750000	803	6
3450000	750000	804	2
3450000	750000	805	4
3450000	750000	806	3
3450000	750000	807	1
3450000	750000	809	2
3450000	750000	810	3
3450000	750000	811	3
3450000	750000	812	2
3450000	750000	814	3
3450000	750000	815	2
3450000	750000	816	2
3450000	750000	818	1
3450000	750000	819	1
3450000	750000	821	3
3450000	750000	822	2
3450000	750000	823	3
3450000	750000	824	5
3450000	750000	825	3
3450000	750000	826	5
3450000	750000	827	6
3450000	750000	828	1
3450000	750000	829	2
3450000	750000	830	3
3450000	750000	832	2
3450000	750000	833	2
3450000	750000	835	3
3450000	750000	836	3
3450000	750000	837	4
3450000	750000	838	5
3450000	750000	839	4
3450000	750000	840	2
3450000	750000	841	12
3450000	750000	842	7
3450000	750000	843	6
3450000	750000	844	2
3450000	750000	845	6
3450000	750000	846	10
3450000	750000	847	7
3450000	750000	848	11
3450000	750000	849	6
3450000	750000	850	7
3450000	750000	851	15
3450000	750000	852	8
3450000	750000	853	9
3450000	750000	854	10
3450000	750000	855	11
3450000	750000	856	8
3450000	750000	857	6
3450000	750000	858	8
3450000	750000	859	20
3450000	750000	860	20
3450000	750000	861	9
3450000	750000	862	15
3450000	750000	863	3
3450000	750000	864	15
3450000	750000	865	15
3450000	750000	866	12
3450000	750000	867	8
3450000	750000	868	16
3450000	750000	869	12
3450000	750000	870	20
3450000	750000	871	16
3450000	750000	872	10
3450000	750000	873	12
3450000	750000	874	10
3450000	750000	875	10
3450000	750000	876	10
3450000	750000	877	20
3450000	750000	878	24
3450000	750000	879	8
3450000	750000	880	17
3450000	750000	881	19
3450000	750000	882	17
3450000	750000	883	9
3450000	750000	884	12
3450000	750000	885	8
3450000	750000	886	14
3450000	750000	887	8
3450000	750000	888	14
3450000	750000	889	9
3450000	750000	890	17
3450000	750000	891	13
3450000	750000	892	13
3450000	750000	893	15
3450000	750000	894	11
3450000	750000	895	9
3450000	750000	896	17
3450000	750000	897	10
3450000	750000	898	15
3450000	750000	899	12
3450000	750000	900	8
3450000	750000	901	14
3450000	750000	902	10
3450000	750000	903	12
3450000	750000	904	10
3450000	750000	905	10
3450000	750000	906	10
3450000	750000	907	16
3450000	750000	908	12
3450000	750000	909	12
3450000	750000	910	11
3450000	750000	911	8
3450000	750000	912	5
3450000	750000	913	14
3450000	750000	914	15
3450000	750000	915	8
3450000	750000	916	18
3450000	750000	917	11
3450000	750000	918	11
3450000	750000	919	5
3450000	750000	920	7
3450000	750000	921	10
3450000	750000	922	9
3450000	750000	923	13
3450000	750000	924	10
3450000	750000	925	13
3450000	750000	926	12
3450000	750000	927	8
3450000	750000	928	11
3450000	750000	929	7
3450000	750000	930	10
3450000	750000	931	11
3450000	750000	932	9
3450000	750000	933	9
3450000	750000	934	13
3450000	750000	935	12
3450000	750000	936	4
3450000	750000	937	14
3450000	750000	938	11
3450000	750000	939	10
3450000	750000	940	10
3450000	750000	941	13
3450000	750000	942	16
3450000	750000	943	12
3450000	750000	944	11
3450000	750000	945	6
3450000	750000	946	12
3450000	750000	947	9
3450000	750000	948	13
3450000	750000	949	12
3450000	750000	950	10
3450000	750000	951	12
3450000	750000	952	5
3450000	750000	953	15
3450000	750000	954	8
3450000	750000	955	15
3450000	750000	956	15
3450000	750000	957	12
3450000	750000	958	13
3450000	750000	959	11
3450000	750000	960	12
3450000	750000	961	4
3450000	750000	962	12
3450000	750000	963	8
3450000	750000	964	9
3450000	750000	965	10
3450000	750000	966	9
3450000	750000	967	8
3450000	750000	968	10
3450000	750000	969	5
3450000	750000	970	9
3450000	750000	971	9
3450000	750000	972	10
3450000	750000	973	8
3450000	750000	974	10
3450000	750000	975	17
3450000	750000	976	8
3450000	750000	977	9
3450000	750000	978	8
3450000	750000	979	8
3450000	750000	980	10
3450000	750000	981	5
3450000	750000	982	6
3450000	750000	983	11
3450000	750000	984	8
3450000	750000	985	6
3450000	750000	986	9
3450000	750000	987	4
3450000	750000	988	8
3450000	750000	989	7
3450000	750000	990	8
3450000	750000	991	5
3450000	750000	992	5
3450000	750000	993	11
3450000	750000	994	12
3450000	750000	995	8
3450000	750000	996	12
3450000	750000	997	5
3450000	750000	998	8
3450000	750000	999	3
3450000	850000	1000	38
3450000	850000	1001	26
3450000	850000	1002	18
3450000	850000	1003	31
3450000	850000	1004	27
3450000	850000	1005	30
3450000	850000	1006	30
3450000	850000	1007	15
3450000	850000	1008	31
3450000	850000	1009	22
3450000	850000	1010	27
3450000	850000	1011	32
3450000	850000	1012	26
3450000	850000	1013	29
3450000	850000	1014	30
3450000	850000	1015	36
3450000	850000	1016	26
3450000	850000	1017	26
3450000	850000	1018	36
3450000	850000	1019	41
3450000	850000	1020	38
3450000	850000	1021	23
3450000	850000	1022	25
3450000	850000	1023	30
3450000	850000	1024	31
3450000	850000	1025	31
3450000	850000	1026	39
3450000	850000	1027	38
3450000	850000	1028	22
3450000	850000	1029	36
3450000	850000	1030	30
3450000	850000	1031	40
3450000	850000	1032	32
3450000	850000	1033	34
3450000	850000	1034	28
3450000	850000	1035	34
3450000	850000	1036	40
3450000	850000	1037	28
3450000	850000	1038	28
3450000	850000	1039	25
3450000	850000	1040	31
3450000	850000	1041	31
3450000	850000	1042	24
3450000	850000	1043	26
3450000	850000	1044	26
3450000	850000	1045	29
3450000	850000	1046	20
3450000	850000	1047	21
3450000	850000	1048	19
3450000	850000	1049	20
3450000	850000	1050	23
3450000	850000	1051	22
3450000	850000	1052	23
3450000	850000	1053	28
3450000	850000	1054	22
3450000	850000	1055	14
3450000	850000	1056	17
3450000	850000	1057	20
3450000	850000	1058	15
3450000	850000	1059	20
3450000	850000	1060	20
3450000	850000	1061	24
3450000	850000	1062	21
3450000	850000	1063	15
3450000	850000	1064	24
3450000	850000	1065	21
3450000	850000	1066	18
3450000	850000	1067	15
3450000	850000	1068	18
3450000	850000	1069	12
3450000	850000	1070	17
3450000	850000	1071	18
3450000	850000	1072	16
3450000	850000	1073	17
3450000	850000	1074	19
3450000	850000	1075	14
3450000	850000	1076	17
3450000	850000	1077	16
3450000	850000	1078	13
3450000	850000	1079	16
3450000	850000	1080	18
3450000	850000	1081	18
3450000	850000	1082	9
3450000	850000	1083	17
3450000	850000	1084	13
3450000	850000	1085	11
3450000	850000	1086	10
3450000	850000	1087	13
3450000	850000	1088	9
3450000	850000	1089	14
3450000	850000	1090	13
3450000	850000	1091	12
3450000	850000	1092	19
3450000	850000	1093	11
3450000	850000	1094	8
3450000	850000	1095	9
3450000	850000	1096	7
3450000	850000	1097	10
3450000	850000	1098	10
3450000	850000	1099	11
3450000	850000	1100	13
3450000	850000	1101	12
3450000	850000	1102	8
3450000	850000	1103	7
3450000	850000	1104	13
3450000	850000	1105	13
3450000	850000	1106	8
3450000	850000	1107	8
3450000	850000	1108	11
3450000	850000	1109	2
3450000	850000	1110	8
3450000	850000	1111	13
3450000	850000	1112	9
3450000	850000	1113	5
3450000	850000	1114	7
3450000	850000	1115	7
3450000	850000	1116	7
3450000	850000	1117	7
3450000	850000	1118	9
3450000	850000	1119	13
3450000	850000	1120	13
3450000	850000	1121	6
3450000	850000	1122	6
3450000	850000	1123	13
3450000	850000	1124	4
3450000	850000	1125	5
3450000	850000	1126	1
3450000	850000	1127	5
3450000	850000	1128	6
3450000	850000	1129	8
3450000	850000	1130	2
3450000	850000	1131	2
3450000	850000	1132	5
3450000	850000	1133	5
3450000	850000	1134	1
3450000	850000	1135	3
3450000	850000	1136	3
3450000	850000	1137	1
3450000	850000	1139	4
3450000	850000	1140	5
3450000	850000	1141	1
3450000	850000	1142	5
3450000	850000	1143	1
3450000	850000	1144	3
3450000	850000	1145	1
3450000	850000	1146	4
3450000	850000	1147	1
3450000	850000	1148	3
3450000	850000	1151	2
3450000	850000	1152	2
3450000	850000	1153	2
3450000	850000	1154	2
3450000	850000	1155	2
3450000	850000	1156	1
3450000	850000	1157	3
3450000	850000	1158	3
3450000	850000	1159	1
3450000	850000	1160	2
3450000	850000	1161	2
3450000	850000	1162	1
3450000	850000	1163	1
3450000	850000	1166	2
3450000	850000	1167	1
3450000	850000	1168	1
3450000	850000	1169	2
3450000	850000	1170	1
3450000	850000	1171	1
3450000	850000	1173	5
3450000	850000	1175	1
3450000	850000	1177	1
3450000	850000	1178	1
3450000	850000	1180	2
3450000	850000	1181	3
3450000	850000	1182	1
3450000	850000	1184	2
3450000	850000	1186	1
3450000	850000	1187	4
3450000	850000	1192	1
3450000	850000	1196	3
3450000	850000	1197	1
3450000	850000	1199	3
3450000	850000	1200	2
3450000	850000	1201	2
3450000	850000	1204	1
3450000	850000	1206	2
3450000	850000	1207	1
3450000	850000	1210	2
3450000	850000	1211	2
3450000	850000	1213	2
3450000	850000	1215	2
3450000	850000	1216	3
3450000	850000	1217	1
3450000	850000	1218	1
3450000	850000	1219	1
3450000	850000	1220	4
3450000	850000	1221	3
3450000	850000	1222	3
3450000	850000	1223	2
3450000	850000	1225	2
3450000	850000	1226	1
3450000	850000	1227	3
3450000	850000	1228	4
3450000	850000	1229	1
3450000	850000	1230	4
3450000	850000	1231	3
3450000	850000	1232	1
3450000	850000	1233	3
3450000	850000	1234	5
3450000	850000	1235	8
3450000	850000	1237	7
3450000	850000	1239	1
3450000	850000	1240	3
3450000	850000	1241	3
3450000	850000	1242	1
3450000	850000	1243	1
3450000	850000	1244	1
3450000	850000	1246	1
3450000	850000	1248	1
3450000	850000	1251	1
3450000	850000	1255	1
3450000	850000	1256	2
3450000	850000	1260	3
3450000	850000	1261	2
3450000	850000	1262	3
3450000	850000	1263	2
3450000	850000	1264	1
3450000	850000	1265	3
3450000	850000	1266	1
3450000	850000	1272	3
3450000	850000	1274	1
3450000	850000	1285	1
3450000	850000	1286	1
3450000	850000	1292	2
3450000	850000	1295	1
3450000	850000	1309	1
3450000	850000	1317	1
3450000	850000	798	1
3450000	850000	801	1
3450000	850000	804	3
3450000	850000	805	1
3450000	850000	806	1
3450000	850000	807	1
3450000	850000	808	1
3450000	850000	809	2
3450000	850000	810	3
3450000	850000	811	1
3450000	850000	812	6
3450000	850000	813	1
3450000	850000	814	1
3450000	850000	815	4
3450000	850000	816	2
3450000	850000	817	4
3450000	850000	818	1
3450000	850000	819	2
3450000	850000	820	1
3450000	850000	822	2
3450000	850000	823	1
3450000	850000	824	1
3450000	850000	825	4
3450000	850000	826	3
3450000	850000	827	7
3450000	850000	828	1
3450000	850000	829	3
3450000	850000	830	1
3450000	850000	831	3
3450000	850000	832	1
3450000	850000	833	5
3450000	850000	834	7
3450000	850000	835	1
3450000	850000	836	9
3450000	850000	837	2
3450000	850000	838	7
3450000	850000	839	6
3450000	850000	840	5
3450000	850000	841	3
3450000	850000	842	5
3450000	850000	843	8
3450000	850000	844	12
3450000	850000	845	7
3450000	850000	846	5
3450000	850000	847	5
3450000	850000	849	4
3450000	850000	850	5
3450000	850000	851	8
3450000	850000	852	3
3450000	850000	853	6
3450000	850000	854	6
3450000	850000	855	11
3450000	850000	856	11
3450000	850000	857	9
3450000	850000	858	9
3450000	850000	859	7
3450000	850000	860	5
3450000	850000	861	6
3450000	850000	862	10
3450000	850000	863	5
3450000	850000	864	11
3450000	850000	865	6
3450000	850000	866	8
3450000	850000	867	6
3450000	850000	868	7
3450000	850000	869	9
3450000	850000	870	8
3450000	850000	871	8
3450000	850000	872	6
3450000	850000	873	8
3450000	850000	874	6
3450000	850000	875	10
3450000	850000	876	8
3450000	850000	877	11
3450000	850000	878	11
3450000	850000	879	6
3450000	850000	880	8
3450000	850000	881	6
3450000	850000	882	13
3450000	850000	883	7
3450000	850000	884	5
3450000	850000	885	10
3450000	850000	886	9
3450000	850000	887	7
3450000	850000	888	10
3450000	850000	889	8
3450000	850000	890	14
3450000	850000	891	10
3450000	850000	892	11
3450000	850000	893	9
3450000	850000	894	8
3450000	850000	895	12
3450000	850000	896	11
3450000	850000	897	9
3450000	850000	898	10
3450000	850000	899	9
3450000	850000	900	15
3450000	850000	901	11
3450000	850000	902	17
3450000	850000	903	14
3450000	850000	904	13
3450000	850000	905	19
3450000	850000	906	9
3450000	850000	907	10
3450000	850000	908	12
3450000	850000	909	17
3450000	850000	910	12
3450000	850000	911	15
3450000	850000	912	24
3450000	850000	913	16
3450000	850000	914	16
3450000	850000	915	13
3450000	850000	916	14
3450000	850000	917	13
3450000	850000	918	17
3450000	850000	919	13
3450000	850000	920	8
3450000	850000	921	16
3450000	850000	922	21
3450000	850000	923	12
3450000	850000	924	17
3450000	850000	925	8
3450000	850000	926	9
3450000	850000	927	15
3450000	850000	928	17
3450000	850000	929	12
3450000	850000	930	11
3450000	850000	931	10
3450000	850000	932	10
3450000	850000	933	16
3450000	850000	934	16
3450000	850000	935	11
3450000	850000	936	9
3450000	850000	937	4
3450000	850000	938	10
3450000	850000	939	18
3450000	850000	940	21
3450000	850000	941	9
3450000	850000	942	12
3450000	850000	943	14
3450000	850000	944	16
3450000	850000	945	16
3450000	850000	946	11
3450000	850000	947	9
3450000	850000	948	14
3450000	850000	949	14
3450000	850000	950	24
3450000	850000	951	20
3450000	850000	952	27
3450000	850000	953	20
3450000	850000	954	22
3450000	850000	955	20
3450000	850000	956	14
3450000	850000	957	32
3450000	850000	958	21
3450000	850000	959	24
3450000	850000	960	27
3450000	850000	961	19
3450000	850000	962	27
3450000	850000	963	24
3450000	850000	964	22
3450000	850000	965	32
3450000	850000	966	18
3450000	850000	967	24
3450000	850000	968	23
3450000	850000	969	24
3450000	850000	970	28
3450000	850000	971	26
3450000	850000	972	21
3450000	850000	973	16
3450000	850000	974	29
3450000	850000	975	36
3450000	850000	976	25
3450000	850000	977	17
3450000	850000	978	32
3450000	850000	979	28
3450000	850000	980	32
3450000	850000	981	21
3450000	850000	982	44
3450000	850000	983	28
3450000	850000	984	22
3450000	850000	985	19
3450000	850000	986	25
3450000	850000	987	28
3450000	850000	988	36
3450000	850000	989	23
3450000	850000	990	24
3450000	850000	991	25
3450000	850000	992	28
3450000	850000	993	18
3450000	850000	994	29
3450000	850000	995	23
3450000	850000	996	33
3450000	850000	997	26
3450000	850000	998	25
3450000	850000	999	34
3450000	950000	1000	9
3450000	950000	1001	9
3450000	950000	1002	12
3450000	950000	1003	11
3450000	950000	1004	8
3450000	950000	1005	6
3450000	950000	1006	14
3450000	950000	1007	8
3450000	950000	1008	5
3450000	950000	1009	14
3450000	950000	1010	13
3450000	950000	1011	14
3450000	950000	1012	11
3450000	950000	1013	9
3450000	950000	1014	8
3450000	950000	1015	11
3450000	950000	1016	12
3450000	950000	1017	17
3450000	950000	1018	18
3450000	950000	1019	7
3450000	950000	1020	14
3450000	950000	1021	14
3450000	950000	1022	10
3450000	950000	1023	13
3450000	950000	1024	12
3450000	950000	1025	9
3450000	950000	1026	17
3450000	950000	1027	8
3450000	950000	1028	11
3450000	950000	1029	14
3450000	950000	1030	17
3450000	950000	1031	14
3450000	950000	1032	15
3450000	950000	1033	18
3450000	950000	1034	16
3450000	950000	1035	14
3450000	950000	1036	16
3450000	950000	1037	5
3450000	950000	1038	15
3450000	950000	1039	14
3450000	950000	1040	9
3450000	950000	1041	15
3450000	950000	1042	11
3450000	950000	1043	6
3450000	950000	1044	11
3450000	950000	1045	10
3450000	950000	1046	15
3450000	950000	1047	14
3450000	950000	1048	12
3450000	950000	1049	9
3450000	950000	1050	18
3450000	950000	1051	10
3450000	950000	1052	9
3450000	950000	1053	19
3450000	950000	1054	15
3450000	950000	1055	17
3450000	950000	1056	13
3450000	950000	1057	17
3450000	950000	1058	15
3450000	950000	1059	14
3450000	950000	1060	16
3450000	950000	1061	17
3450000	950000	1062	17
3450000	950000	1063	12
3450000	950000	1064	10
3450000	950000	1065	11
3450000	950000	1066	13
3450000	950000	1067	11
3450000	950000	1068	6
3450000	950000	1069	13
3450000	950000	1070	12
3450000	950000	1071	10
3450000	950000	1072	11
3450000	950000	1073	16
3450000	950000	1074	14
3450000	950000	1075	11
3450000	950000	1076	11
3450000	950000	1077	13
3450000	950000	1078	16
3450000	950000	1079	10
3450000	950000	1080	9
3450000	950000	1081	19
3450000	950000	1082	16
3450000	950000	1083	20
3450000	950000	1084	6
3450000	950000	1085	14
3450000	950000	1086	18
3450000	950000	1087	19
3450000	950000	1088	11
3450000	950000	1089	11
3450000	950000	1090	9
3450000	950000	1091	6
3450000	950000	1092	18
3450000	950000	1093	17
3450000	950000	1094	9
3450000	950000	1095	11
3450000	950000	1096	14
3450000	950000	1097	11
3450000	950000	1098	11
3450000	950000	1099	21
3450000	950000	1100	15
3450000	950000	1101	8
3450000	950000	1102	18
3450000	950000	1103	8
3450000	950000	1104	10
3450000	950000	1105	2
3450000	950000	1106	16
3450000	950000	1107	14
3450000	950000	1108	14
3450000	950000	1109	6
3450000	950000	1110	11
3450000	950000	1111	15
3450000	950000	1112	11
3450000	950000	1113	12
3450000	950000	1114	14
3450000	950000	1115	10
3450000	950000	1116	14
3450000	950000	1117	15
3450000	950000	1118	9
3450000	950000	1119	16
3450000	950000	1120	10
3450000	950000	1121	8
3450000	950000	1122	22
3450000	950000	1123	9
3450000	950000	1124	16
3450000	950000	1125	17
3450000	950000	1126	14
3450000	950000	1127	14
3450000	950000	1128	14
3450000	950000	1129	6
3450000	950000	1130	11
3450000	950000	1131	15
3450000	950000	1132	11
3450000	950000	1133	9
3450000	950000	1134	15
3450000	950000	1135	11
3450000	950000	1136	20
3450000	950000	1137	4
3450000	950000	1138	12
3450000	950000	1139	6
3450000	950000	1140	13
3450000	950000	1141	7
3450000	950000	1142	14
3450000	950000	1143	14
3450000	950000	1144	19
3450000	950000	1145	14
3450000	950000	1146	16
3450000	950000	1147	12
3450000	950000	1148	11
3450000	950000	1149	14
3450000	950000	1150	11
3450000	950000	1151	15
3450000	950000	1152	11
3450000	950000	1153	15
3450000	950000	1154	11
3450000	950000	1155	16
3450000	950000	1156	10
3450000	950000	1157	19
3450000	950000	1158	14
3450000	950000	1159	12
3450000	950000	1160	12
3450000	950000	1161	10
3450000	950000	1162	16
3450000	950000	1163	11
3450000	950000	1164	10
3450000	950000	1165	15
3450000	950000	1166	5
3450000	950000	1167	6
3450000	950000	1168	10
3450000	950000	1169	11
3450000	950000	1170	19
3450000	950000	1171	6
3450000	950000	1172	10
3450000	950000	1173	14
3450000	950000	1174	14
3450000	950000	1175	14
3450000	950000	1176	10
3450000	950000	1177	6
3450000	950000	1178	16
3450000	950000	1179	8
3450000	950000	1180	12
3450000	950000	1181	10
3450000	950000	1182	8
3450000	950000	1183	4
3450000	950000	1184	6
3450000	950000	1185	20
3450000	950000	1186	18
3450000	950000	1187	11
3450000	950000	1188	14
3450000	950000	1189	12
3450000	950000	1190	10
3450000	950000	1191	6
3450000	950000	1192	7
3450000	950000	1193	9
3450000	950000	1194	14
3450000	950000	1195	16
3450000	950000	1196	3
3450000	950000	1197	10
3450000	950000	1198	6
3450000	950000	1199	10
3450000	950000	1200	12
3450000	950000	1201	9
3450000	950000	1202	10
3450000	950000	1203	7
3450000	950000	1204	11
3450000	950000	1205	12
3450000	950000	1206	11
3450000	950000	1207	4
3450000	950000	1208	2
3450000	950000	1209	8
3450000	950000	1210	21
3450000	950000	1211	12
3450000	950000	1212	9
3450000	950000	1213	12
3450000	950000	1214	14
3450000	950000	1215	7
3450000	950000	1216	19
3450000	950000	1217	7
3450000	950000	1218	10
3450000	950000	1219	8
3450000	950000	1220	8
3450000	950000	1221	13
3450000	950000	1222	10
3450000	950000	1223	7
3450000	950000	1224	10
3450000	950000	1225	8
3450000	950000	1226	6
3450000	950000	1227	7
3450000	950000	1228	12
3450000	950000	1229	6
3450000	950000	1230	8
3450000	950000	1231	12
3450000	950000	1232	11
3450000	950000	1233	10
3450000	950000	1234	8
3450000	950000	1235	7
3450000	950000	1236	5
3450000	950000	1237	10
3450000	950000	1238	4
3450000	950000	1239	9
3450000	950000	1240	4
3450000	950000	1241	11
3450000	950000	1242	7
3450000	950000	1243	5
3450000	950000	1244	7
3450000	950000	1245	8
3450000	950000	1246	10
3450000	950000	1247	8
3450000	950000	1248	4
3450000	950000	1249	7
3450000	950000	1250	15
3450000	950000	1251	10
3450000	950000	1252	5
3450000	950000	1253	5
3450000	950000	1254	8
3450000	950000	1255	13
3450000	950000	1256	2
3450000	950000	1257	7
3450000	950000	1258	2
3450000	950000	1259	6
3450000	950000	1260	6
3450000	950000	1261	1
3450000	950000	1262	7
3450000	950000	1263	6
3450000	950000	1264	4
3450000	950000	1265	1
3450000	950000	1266	3
3450000	950000	1267	4
3450000	950000	1268	4
3450000	950000	1269	2
3450000	950000	1270	2
3450000	950000	1271	1
3450000	950000	1272	4
3450000	950000	1273	3
3450000	950000	1274	2
3450000	950000	1275	2
3450000	950000	1276	5
3450000	950000	1277	5
3450000	950000	1278	2
3450000	950000	1279	1
3450000	950000	1280	3
3450000	950000	1281	1
3450000	950000	1282	1
3450000	950000	1283	4
3450000	950000	1284	3
3450000	950000	1285	1
3450000	950000	1287	1
3450000	950000	1288	1
3450000	950000	1290	2
3450000	950000	1293	1
3450000	950000	1295	1
3450000	950000	1297	1
3450000	950000	1299	1
3450000	950000	1301	1
3450000	950000	1303	1
3450000	950000	1340	1
3450000	950000	1351	1
3450000	950000	1354	1
3450000	950000	1370	1
3450000	950000	1371	1
3450000	950000	1373	1
3450000	950000	1388	1
3450000	950000	1390	1
3450000	950000	636	1
3450000	950000	637	1
3450000	950000	638	2
3450000	950000	639	1
3450000	950000	640	2
3450000	950000	641	1
3450000	950000	642	7
3450000	950000	643	3
3450000	950000	644	6
3450000	950000	645	6
3450000	950000	646	3
3450000	950000	647	5
3450000	950000	648	5
3450000	950000	649	5
3450000	950000	650	13
3450000	950000	651	11
3450000	950000	652	6
3450000	950000	653	2
3450000	950000	654	15
3450000	950000	655	12
3450000	950000	656	13
3450000	950000	657	12
3450000	950000	658	14
3450000	950000	659	21
3450000	950000	660	22
3450000	950000	661	21
3450000	950000	662	17
3450000	950000	663	22
3450000	950000	664	13
3450000	950000	665	27
3450000	950000	666	25
3450000	950000	667	29
3450000	950000	668	18
3450000	950000	669	28
3450000	950000	670	38
3450000	950000	671	33
3450000	950000	672	21
3450000	950000	673	28
3450000	950000	674	41
3450000	950000	675	26
3450000	950000	676	32
3450000	950000	677	40
3450000	950000	678	40
3450000	950000	679	35
3450000	950000	680	25
3450000	950000	681	42
3450000	950000	682	33
3450000	950000	683	39
3450000	950000	684	52
3450000	950000	685	38
3450000	950000	686	33
3450000	950000	687	27
3450000	950000	688	39
3450000	950000	689	38
3450000	950000	690	31
3450000	950000	691	33
3450000	950000	692	36
3450000	950000	693	53
3450000	950000	694	30
3450000	950000	695	42
3450000	950000	696	34
3450000	950000	697	51
3450000	950000	698	59
3450000	950000	699	60
3450000	950000	700	61
3450000	950000	701	60
3450000	950000	702	54
3450000	950000	703	64
3450000	950000	704	62
3450000	950000	705	56
3450000	950000	706	58
3450000	950000	707	52
3450000	950000	708	45
3450000	950000	709	43
3450000	950000	710	54
3450000	950000	711	56
3450000	950000	712	48
3450000	950000	713	33
3450000	950000	714	35
3450000	950000	715	46
3450000	950000	716	41
3450000	950000	717	45
3450000	950000	718	40
3450000	950000	719	50
3450000	950000	720	37
3450000	950000	721	46
3450000	950000	722	63
3450000	950000	723	42
3450000	950000	724	43
3450000	950000	725	32
3450000	950000	726	38
3450000	950000	727	43
3450000	950000	728	29
3450000	950000	729	30
3450000	950000	730	32
3450000	950000	731	45
3450000	950000	732	42
3450000	950000	733	30
3450000	950000	734	36
3450000	950000	735	36
3450000	950000	736	23
3450000	950000	737	34
3450000	950000	738	32
3450000	950000	739	26
3450000	950000	740	18
3450000	950000	741	23
3450000	950000	742	25
3450000	950000	743	30
3450000	950000	744	21
3450000	950000	745	29
3450000	950000	746	28
3450000	950000	747	17
3450000	950000	748	23
3450000	950000	749	17
3450000	950000	750	20
3450000	950000	751	15
3450000	950000	752	17
3450000	950000	753	20
3450000	950000	754	19
3450000	950000	755	15
3450000	950000	756	16
3450000	950000	757	20
3450000	950000	758	13
3450000	950000	759	24
3450000	950000	760	13
3450000	950000	761	17
3450000	950000	762	12
3450000	950000	763	5
3450000	950000	764	8
3450000	950000	765	14
3450000	950000	766	18
3450000	950000	767	10
3450000	950000	768	10
3450000	950000	769	14
3450000	950000	770	11
3450000	950000	771	10
3450000	950000	772	11
3450000	950000	773	11
3450000	950000	774	15
3450000	950000	775	14
3450000	950000	776	11
3450000	950000	777	17
3450000	950000	778	9
3450000	950000	779	14
3450000	950000	780	10
3450000	950000	781	10
3450000	950000	782	6
3450000	950000	783	5
3450000	950000	784	13
3450000	950000	785	9
3450000	950000	786	10
3450000	950000	787	8
3450000	950000	788	9
3450000	950000	789	8
3450000	950000	790	12
3450000	950000	791	13
3450000	950000	792	10
3450000	950000	793	10
3450000	950000	794	15
3450000	950000	795	7
3450000	950000	796	10
3450000	950000	797	12
3450000	950000	798	7
3450000	950000	799	11
3450000	950000	800	12
3450000	950000	801	15
3450000	950000	802	12
3450000	950000	803	9
3450000	950000	804	13
3450000	950000	805	8
3450000	950000	806	7
3450000	950000	807	19
3450000	950000	808	16
3450000	950000	809	13
3450000	950000	810	13
3450000	950000	811	15
3450000	950000	812	11
3450000	950000	813	13
3450000	950000	814	15
3450000	950000	815	11
3450000	950000	816	13
3450000	950000	817	12
3450000	950000	818	16
3450000	950000	819	19
3450000	950000	820	15
3450000	950000	821	13
3450000	950000	822	10
3450000	950000	823	14
3450000	950000	824	15
3450000	950000	825	18
3450000	950000	826	18
3450000	950000	827	13
3450000	950000	828	15
3450000	950000	829	12
3450000	950000	830	15
3450000	950000	831	8
3450000	950000	832	11
3450000	950000	833	6
3450000	950000	834	9
3450000	950000	835	12
3450000	950000	836	14
3450000	950000	837	10
3450000	950000	838	12
3450000	950000	839	11
3450000	950000	840	11
3450000	950000	841	6
3450000	950000	842	6
3450000	950000	843	18
3450000	950000	844	11
3450000	950000	845	8
3450000	950000	846	7
3450000	950000	847	11
3450000	950000	848	13
3450000	950000	849	8
3450000	950000	850	15
3450000	950000	851	6
3450000	950000	852	14
3450000	950000	853	13
3450000	950000	854	6
3450000	950000	855	10
3450000	950000	856	6
3450000	950000	857	12
3450000	950000	858	8
3450000	950000	859	8
3450000	950000	860	8
3450000	950000	861	8
3450000	950000	862	12
3450000	950000	863	11
3450000	950000	864	10
3450000	950000	865	15
3450000	950000	866	10
3450000	950000	867	5
3450000	950000	868	15
3450000	950000	869	13
3450000	950000	870	9
3450000	950000	871	8
3450000	950000	872	9
3450000	950000	873	11
3450000	950000	874	14
3450000	950000	875	13
3450000	950000	876	13
3450000	950000	877	8
3450000	950000	878	13
3450000	950000	879	9
3450000	950000	880	12
3450000	950000	881	15
3450000	950000	882	10
3450000	950000	883	12
3450000	950000	884	11
3450000	950000	885	9
3450000	950000	886	13
3450000	950000	887	13
3450000	950000	888	15
3450000	950000	889	9
3450000	950000	890	15
3450000	950000	891	8
3450000	950000	892	19
3450000	950000	893	13
3450000	950000	894	11
3450000	950000	895	9
3450000	950000	896	13
3450000	950000	897	16
3450000	950000	898	13
3450000	950000	899	10
3450000	950000	900	11
3450000	950000	901	6
3450000	950000	902	11
3450000	950000	903	4
3450000	950000	904	21
3450000	950000	905	9
3450000	950000	906	10
3450000	950000	907	16
3450000	950000	908	8
3450000	950000	909	10
3450000	950000	910	19
3450000	950000	911	11
3450000	950000	912	14
3450000	950000	913	18
3450000	950000	914	5
3450000	950000	915	19
3450000	950000	916	9
3450000	950000	917	8
3450000	950000	918	13
3450000	950000	919	8
3450000	950000	920	12
3450000	950000	921	18
3450000	950000	922	19
3450000	950000	923	5
3450000	950000	924	7
3450000	950000	925	14
3450000	950000	926	17
3450000	950000	927	4
3450000	950000	928	8
3450000	950000	929	7
3450000	950000	930	10
3450000	950000	931	12
3450000	950000	932	11
3450000	950000	933	10
3450000	950000	934	10
3450000	950000	935	14
3450000	950000	936	8
3450000	950000	937	11
3450000	950000	938	10
3450000	950000	939	10
3450000	950000	940	15
3450000	950000	941	15
3450000	950000	942	12
3450000	950000	943	17
3450000	950000	944	9
3450000	950000	945	10
3450000	950000	946	18
3450000	950000	947	8
3450000	950000	948	9
3450000	950000	949	18
3450000	950000	950	15
3450000	950000	951	18
3450000	950000	952	8
3450000	950000	953	15
3450000	950000	954	21
3450000	950000	955	16
3450000	950000	956	14
3450000	950000	957	16
3450000	950000	958	11
3450000	950000	959	10
3450000	950000	960	13
3450000	950000	961	11
3450000	950000	962	14
3450000	950000	963	11
3450000	950000	964	12
3450000	950000	965	10
3450000	950000	966	15
3450000	950000	967	7
3450000	950000	968	6
3450000	950000	969	13
3450000	950000	970	8
3450000	950000	971	13
3450000	950000	972	12
3450000	950000	973	9
3450000	950000	974	8
3450000	950000	975	14
3450000	950000	976	11
3450000	950000	977	13
3450000	950000	978	15
3450000	950000	979	10
3450000	950000	980	8
3450000	950000	981	7
3450000	950000	982	15
3450000	950000	983	11
3450000	950000	984	5
3450000	950000	985	13
3450000	950000	986	6
3450000	950000	987	14
3450000	950000	988	12
3450000	950000	989	14
3450000	950000	990	11
3450000	950000	991	15
3450000	950000	992	14
3450000	950000	993	8
3450000	950000	994	14
3450000	950000	995	15
3450000	950000	996	10
3450000	950000	997	13
3450000	950000	998	17
3450000	950000	999	11


@@ MATRIX_SITE_DATA
35	Genus	sp1	-															
36	Genus	sp2	0.05151	-														
38	Genus	sp3	0.0395	0.04872	-													
39	Genus	sp4	0.05135	0.06856	0.05923	-												
40	Genus	sp5	0.04528	0.0505	0.04442	0.05604	-											
42	Genus	sp6	0.04168	0.04967	0.0407	0.05786	0.0179	-										
43	Genus	sp7	0.03464	0.06297	0.05219	0.05622	0.0606	0.05401	-									
44	Genus	sp8	0.03654	0.05261	0.04282	0.05675	0.05245	0.04726	0.0495	-								
45	Genus	sp9	0.04128	0.05172	0.01511	0.06077	0.04843	0.04533	0.05722	0.04421	-							
46	Genus	sp10	0.04184	0.03716	0.03968	0.05046	0.03914	0.03643	0.0499	0.04416	0.04014	-						
47	Genus	sp11	0.0396	0.04757	0.00605	0.05669	0.04325	0.04076	0.05243	0.04098	0.01152	0.03705	-					
48	Genus	sp12	0.04046	0.05273	0.04521	0.05679	0.02194	0.01795	0.05524	0.04985	0.0478	0.04061	0.04642	-				
49	Genus	sp13	0.04603	0.0414	0.04121	0.05969	0.04329	0.04111	0.05565	0.04742	0.0429	0.02089	0.03963	0.04302	-			
51	Genus	sp14	0.05958	0.06901	0.05792	0.07602	0.03506	0.03169	0.07215	0.06868	0.06331	0.05679	0.05959	0.03437	0.06004	-		
52	Genus	sp15	0.04924	0.0115	0.04241	0.0644	0.04728	0.04688	0.06177	0.05044	0.04745	0.03182	0.04106	0.05065	0.03882	0.06595	-	
53	Genus	sp16	0.04221	0.05195	0.01086	0.06141	0.04793	0.04406	0.05476	0.04433	0.01696	0.04248	0.00995	0.04778	0.04393	0.06143	0.04666	-
54	Genus	sp17	0.03016	0.05809	0.04485	0.05096	0.04969	0.04615	0.02362	0.04285	0.04714	0.04803	0.0444	0.04902	0.05331	0.06138	0.05766	0.04796	-															
56	Genus	sp18	0.04031	0.06477	0.05807	0.0584	0.05752	0.05929	0.03368	0.05293	0.05819	0.04997	0.05297	0.05816	0.05845	0.0762	0.06161	0.06009	0.03152	-														
57	Genus	sp19	0.05208	0.00566	0.04755	0.0716	0.05171	0.05049	0.06177	0.0548	0.05267	0.03931	0.04849	0.05136	0.04344	0.06852	0.01359	0.0507	0.05842	0.06446	-													
58	Genus	sp20	0.04137	0.04985	0.042	0.05736	0.01746	0.01498	0.05399	0.05066	0.04668	0.03703	0.04211	0.019	0.04055	0.03106	0.04827	0.04585	0.04671	0.05654	0.05074	-												
59	Genus	sp21	0.05208	0.0152	0.04539	0.0691	0.05073	0.04966	0.06505	0.05248	0.04888	0.0382	0.04415	0.05328	0.04252	0.06764	0.0115	0.04878	0.06	0.06378	0.01589	0.05006	-											
60	Genus	sp22	0.05205	0.01743	0.04794	0.07058	0.05185	0.05147	0.06527	0.05474	0.05249	0.04112	0.04776	0.05395	0.04518	0.06788	0.01495	0.05049	0.06162	0.06832	0.01794	0.05035	0.00571	-										
61	Genus	sp23	0.04464	0.0402	0.04204	0.05898	0.04256	0.03909	0.05449	0.04539	0.04422	0.01598	0.03957	0.04316	0.02423	0.06025	0.03669	0.04487	0.05195	0.05823	0.04298	0.04006	0.04022	0.04222	-									
62	Genus	sp24	0.04311	0.04991	0.04552	0.05982	0.02116	0.0175	0.06053	0.05091	0.049	0.03983	0.04445	0.02126	0.04308	0.03636	0.04789	0.04903	0.05206	0.05935	0.05201	0.01842	0.05112	0.05192	0.04046	-								
63	Genus	sp25	0.04498	0.04135	0.04173	0.06123	0.04584	0.04055	0.04937	0.04656	0.04612	0.01662	0.04203	0.04494	0.02486	0.0599	0.0378	0.04495	0.04771	0.05942	0.04226	0.04174	0.04135	0.04383	0.00794	0.04433	-							
64	Genus	sp26	0.03954	0.06382	0.05605	0.05809	0.06319	0.0548	0.00204	0.05162	0.05775	0.05237	0.05334	0.05976	0.05709	0.07301	0.06208	0.05787	0.02788	0.03531	0.06402	0.05692	0.06602	0.06672	0.05617	0.06115	0.05219	-						
65	Genus	sp27	0.0504	0.04403	0.04392	0.06481	0.04862	0.0463	0.06027	0.05228	0.04845	0.02575	0.04325	0.05121	0.01875	0.06771	0.04109	0.0481	0.0582	0.06351	0.04631	0.04766	0.04507	0.04808	0.02795	0.04913	0.03	0.06206	-					
66	Genus	sp28	0.04355	0.05024	0.0467	0.06069	0.0207	0.0176	0.06173	0.05235	0.05061	0.04077	0.04595	0.01429	0.04359	0.03791	0.0491	0.05024	0.05023	0.06336	0.0509	0.0196	0.05159	0.05405	0.04376	0.01899	0.04517	0.06316	0.04942	-				
67	Genus	sp29	0.04389	0.05217	0.04552	0.05985	0.02079	0.01813	0.05839	0.05057	0.04857	0.04262	0.04533	0.01652	0.04358	0.03497	0.051	0.04688	0.04923	0.05867	0.05447	0.01767	0.05328	0.05213	0.04511	0.02118	0.0474	0.06114	0.0508	0.01846	-			
68	Genus	sp30	0.04324	0.05223	0.04223	0.05874	0.01742	0.01519	0.05501	0.05086	0.04628	0.0382	0.04301	0.01733	0.04231	0.03271	0.04925	0.04566	0.04537	0.05821	0.05231	0.01514	0.05155	0.05269	0.04192	0.01828	0.04237	0.05768	0.04822	0.01834	0.01761	-		
69	Genus	sp31	0.04117	0.05307	0.0426	0.06061	0.0193	0.01564	0.05523	0.05124	0.04675	0.04051	0.04348	0.01797	0.04321	0.03287	0.0497	0.04598	0.04418	0.05876	0.05308	0.01626	0.05109	0.05223	0.0425	0.01952	0.04301	0.05813	0.04841	0.0189	0.01877	0.00822	-	
70	Genus	sp32	0.03689	0.06388	0.05712	0.05807	0.0612	0.05664	0.00207	0.05392	0.05948	0.05159	0.05509	0.05847	0.0565	0.07313	0.06489	0.05874	0.02753	0.03628	0.06388	0.05657	0.0673	0.06664	0.05643	0.0615	0.0526	0.00515	0.06335	0.06485	0.05957	0.05822	0.05866	-
71	Genus	sp33	0.049	0.04049	0.04346	0.06037	0.04506	0.04272	0.05512	0.05099	0.0458	0.02308	0.04219	0.04724	0.01567	0.06238	0.03933	0.04491	0.05393	0.06204	0.04108	0.04316	0.04315	0.04412	0.02602	0.0435	0.02571	0.05748	0.01148	0.04412	0.04702	0.04536	0.0462	0.05513	-															
72	Genus	sp34	0.04303	0.0562	0.04496	0.06021	0.02261	0.01913	0.0581	0.05175	0.04795	0.0426	0.04401	0.02459	0.04607	0.03708	0.05299	0.04833	0.05116	0.05977	0.05754	0.01815	0.05631	0.0567	0.04441	0.02151	0.04806	0.06149	0.05135	0.02281	0.02277	0.01999	0.02112	0.06057	0.04693	-														
73	Genus	sp35	0.03327	0.05026	0.04024	0.05015	0.04566	0.04365	0.04613	0.03863	0.04538	0.04289	0.04013	0.04257	0.04691	0.0608	0.0501	0.04424	0.0414	0.04724	0.05255	0.04456	0.05208	0.05396	0.04753	0.04532	0.04817	0.05142	0.04981	0.04571	0.04672	0.04528	0.04637	0.04978	0.04782	0.04716	-													
74	Genus	sp36	0.05168	0.06898	0.05517	0.02529	0.061	0.06116	0.0598	0.06142	0.05827	0.05573	0.05591	0.05664	0.06187	0.07315	0.06753	0.05814	0.05513	0.06394	0.07003	0.06022	0.07113	0.07033	0.06308	0.06344	0.06293	0.06419	0.06998	0.06462	0.06148	0.05862	0.06119	0.06028	0.06331	0.06439	0.05425	-												
75	Genus	sp37	0.05394	0.00764	0.05009	0.07053	0.05161	0.0507	0.06441	0.05375	0.05226	0.03831	0.0487	0.05273	0.04333	0.0702	0.01217	0.05278	0.06039	0.0644	0.0096	0.05161	0.01656	0.01857	0.04203	0.05065	0.04372	0.06518	0.04541	0.05166	0.05424	0.05359	0.05415	0.06652	0.04345	0.05724	0.05203	0.07275	-											
76	Genus	sp38	0.04215	0.03764	0.04018	0.05137	0.0413	0.0377	0.04997	0.04494	0.04103	0.00188	0.03778	0.04255	0.02131	0.0579	0.03266	0.04283	0.04814	0.05238	0.03975	0.03948	0.03883	0.04206	0.01656	0.04179	0.01778	0.05241	0.02656	0.04242	0.04498	0.04005	0.04221	0.05161	0.024	0.04493	0.04573	0.05702	0.03897	-										
77	Genus	sp39	0.04255	0.06705	0.05333	0.02754	0.05786	0.05631	0.05071	0.05557	0.05819	0.05306	0.05405	0.05373	0.05992	0.07274	0.06397	0.05632	0.04714	0.05782	0.06644	0.05615	0.06644	0.06865	0.06093	0.0598	0.05802	0.05429	0.06523	0.06023	0.06053	0.05666	0.05757	0.05598	0.06107	0.05956	0.04671	0.0311	0.06845	0.05178	-									
78	Genus	sp40	0.04397	0.03982	0.03981	0.05735	0.04281	0.04114	0.05418	0.04625	0.0417	0.01963	0.03843	0.04302	0.00375	0.05936	0.03756	0.04252	0.05198	0.05592	0.04195	0.04022	0.04136	0.04337	0.02303	0.04302	0.0222	0.05572	0.01751	0.04368	0.04294	0.04232	0.0432	0.05431	0.01428	0.04586	0.04489	0.05966	0.0422	0.02001	0.0586	-								
79	Genus	sp41	0.04203	0.05146	0.04354	0.0566	0.01917	0.01616	0.05773	0.04978	0.0472	0.03941	0.04197	0.01981	0.03985	0.03435	0.04881	0.04694	0.04868	0.05702	0.05387	0.01517	0.05186	0.05275	0.04184	0.01838	0.04485	0.0598	0.04746	0.01964	0.01841	0.017	0.01753	0.05828	0.04466	0.02026	0.04232	0.06151	0.0534	0.04112	0.05845	0.04068	-							
80	Genus	sp42	0.04259	0.06314	0.05259	0.02588	0.05331	0.05365	0.05182	0.05528	0.05594	0.04976	0.05377	0.05157	0.05585	0.06874	0.06173	0.05569	0.04884	0.05561	0.06339	0.05299	0.06393	0.06458	0.05895	0.05626	0.05662	0.05679	0.06246	0.05658	0.05622	0.05301	0.05432	0.05441	0.05772	0.05665	0.04385	0.02924	0.06618	0.04991	0.00669	0.05368	0.05374	-						
81	Genus	sp43	0.04317	0.05491	0.01376	0.06092	0.04918	0.04562	0.05181	0.04434	0.01899	0.04322	0.01206	0.04936	0.04482	0.06273	0.04865	0.016	0.04705	0.05845	0.05269	0.04676	0.05068	0.05315	0.04571	0.05089	0.04244	0.05497	0.04997	0.05073	0.04933	0.04727	0.04686	0.05591	0.04738	0.04874	0.04381	0.05929	0.05644	0.04361	0.05617	0.04256	0.04598	0.05667	-					
83	Genus	sp44	0.03957	0.0635	0.0581	0.05769	0.05725	0.05812	0.03287	0.05132	0.05762	0.05043	0.05243	0.0569	0.05873	0.07459	0.06034	0.06014	0.03089	0.00206	0.06455	0.0562	0.06255	0.06706	0.05785	0.05824	0.05902	0.03459	0.06223	0.06216	0.05757	0.05707	0.05763	0.03555	0.06152	0.05864	0.04572	0.06471	0.06378	0.0528	0.05712	0.05625	0.05524	0.05521	0.05924	-				
84	Genus	sp45	0.03266	0.05847	0.05042	0.05147	0.05166	0.05319	0.0285	0.04729	0.05133	0.04893	0.04818	0.05033	0.05314	0.06957	0.05752	0.05222	0.02311	0.01603	0.05937	0.05068	0.05912	0.06066	0.05439	0.05346	0.05391	0.0323	0.05893	0.05724	0.05224	0.05213	0.05202	0.03112	0.0556	0.05329	0.03983	0.05589	0.061	0.04987	0.05065	0.04976	0.05036	0.04915	0.05232	0.01501	-			
85	Genus	sp46	0.04617	0.06443	0.05315	0.01405	0.05314	0.05345	0.05353	0.05255	0.05518	0.0475	0.05161	0.05165	0.05525	0.06736	0.06153	0.05645	0.04938	0.05503	0.06649	0.05414	0.06426	0.06555	0.05617	0.05658	0.05805	0.05574	0.06281	0.05713	0.05539	0.05281	0.05488	0.05676	0.05814	0.05704	0.04904	0.01444	0.06581	0.04926	0.02317	0.05403	0.054	0.02193	0.05597	0.05466	0.0509	-		
86	Genus	sp47	0.04694	0.0562	0.04612	0.06194	0.02268	0.02129	0.06051	0.05349	0.05033	0.0441	0.04572	0.02293	0.04656	0.03687	0.05264	0.05036	0.05249	0.06286	0.05832	0.01986	0.05552	0.05756	0.045	0.02424	0.04811	0.06385	0.05097	0.02417	0.02078	0.02089	0.02268	0.06372	0.04798	0.02048	0.0471	0.06741	0.05642	0.04604	0.06334	0.04667	0.01921	0.06082	0.05161	0.06095	0.05738	0.05929	-	
87	Genus	sp48	0.04855	0.05441	0.02003	0.06	0.05199	0.04946	0.05931	0.0504	0.02411	0.04346	0.01698	0.0523	0.049	0.06914	0.04858	0.02187	0.05332	0.0613	0.05665	0.05014	0.05231	0.05594	0.04828	0.05181	0.04954	0.06056	0.05273	0.05421	0.05353	0.05107	0.05227	0.06379	0.05091	0.05284	0.04825	0.06165	0.05494	0.04572	0.05924	0.04782	0.05139	0.05967	0.02292	0.06085	0.05636	0.05735	0.05321	-
88	Genus	sp49	0.03898	0.04977	0.04097	0.05577	0.01832	0.01527	0.05271	0.04714	0.04515	0.03797	0.04065	0.01819	0.04068	0.03237	0.04673	0.04443	0.04532	0.05568	0.05119	0.01454	0.04924	0.05043	0.0393	0.0173	0.0422	0.05565	0.0474	0.01826	0.01793	0.01547	0.01597	0.05617	0.04422	0.01956	0.04259	0.06065	0.05079	0.03978	0.05365	0.04065	0.01535	0.05222	0.0433	0.05462	0.04822	0.05209	0.01983	0.04866	-															
89	Genus	sp50	0.04343	0.05459	0.04406	0.06295	0.02376	0.02058	0.05824	0.05287	0.05037	0.04341	0.04509	0.02535	0.04607	0.03761	0.05062	0.04726	0.05058	0.0617	0.05446	0.02099	0.05348	0.05435	0.04545	0.02392	0.04626	0.06213	0.0543	0.02365	0.02056	0.02088	0.02127	0.06131	0.05107	0.01966	0.04534	0.06303	0.05441	0.04491	0.05755	0.04601	0.02189	0.0557	0.04828	0.0605	0.05544	0.05767	0.02133	0.05324	0.02032	-														
90	Genus	sp51	0.05046	0.00964	0.0484	0.07088	0.05231	0.04977	0.0645	0.05367	0.05323	0.03965	0.05055	0.05205	0.04389	0.06815	0.01391	0.05272	0.05781	0.06698	0.01115	0.05005	0.0189	0.01963	0.04313	0.05059	0.04265	0.06507	0.04605	0.05161	0.05385	0.05195	0.05182	0.06538	0.04347	0.05631	0.05107	0.06989	0.01107	0.04072	0.06771	0.04239	0.0532	0.06365	0.05484	0.06611	0.06139	0.06622	0.05774	0.05673	0.04984	0.05384	-													
91	Genus	sp52	0.0509	0.07091	0.05953	0.03005	0.05961	0.05852	0.05776	0.06056	0.06305	0.05721	0.05912	0.05712	0.06388	0.07495	0.06896	0.06235	0.05723	0.06482	0.07076	0.05911	0.07133	0.07314	0.0657	0.06087	0.06412	0.06438	0.06754	0.06278	0.06299	0.05886	0.05998	0.0647	0.06517	0.06195	0.05225	0.03608	0.07303	0.0565	0.01579	0.06328	0.06022	0.01741	0.0605	0.06467	0.06009	0.02922	0.06509	0.06229	0.05759	0.05922	0.07277	-												
92	Genus	sp53	0.05444	0.00972	0.04742	0.07199	0.05567	0.05191	0.06224	0.0558	0.05375	0.04141	0.04882	0.05298	0.04619	0.0694	0.01506	0.05039	0.05838	0.06723	0.0113	0.0531	0.01881	0.02053	0.04449	0.05394	0.04355	0.06594	0.0484	0.05322	0.05654	0.05414	0.05436	0.06725	0.04535	0.05963	0.05489	0.07057	0.00323	0.04184	0.06609	0.04485	0.0566	0.06572	0.05373	0.0659	0.06204	0.06835	0.05912	0.05571	0.0525	0.05513	0.0115	0.07142	-											
93	Genus	sp54	0.05014	0.05801	0.01795	0.06621	0.05503	0.04873	0.05898	0.05039	0.02107	0.04875	0.01674	0.05131	0.05077	0.06592	0.05145	0.0215	0.0533	0.06539	0.05649	0.05254	0.05476	0.05707	0.05077	0.05331	0.0504	0.06154	0.05558	0.0562	0.05578	0.0512	0.05178	0.06347	0.05396	0.0544	0.05068	0.06355	0.05841	0.04884	0.06105	0.04942	0.0539	0.06286	0.02158	0.06413	0.05693	0.06173	0.05778	0.02601	0.05053	0.05446	0.05526	0.06777	0.05721	-										
94	Genus	sp55	0.05169	0.01673	0.04609	0.06977	0.05159	0.04984	0.06395	0.05103	0.05041	0.03782	0.04553	0.0518	0.04438	0.06849	0.01158	0.0494	0.05788	0.06539	0.01749	0.05047	0.00139	0.0062	0.0407	0.05072	0.03917	0.06486	0.04732	0.05249	0.05403	0.05222	0.05114	0.06822	0.04656	0.05597	0.05056	0.07321	0.01744	0.03871	0.0672	0.04376	0.05177	0.06534	0.05116	0.06433	0.06191	0.06495	0.05554	0.05184	0.04748	0.05365	0.01899	0.06969	0.01875	0.05372	-									
96	Genus	sp56	0.0438	0.05157	0.04169	0.06007	0.03519	0.02937	0.05549	0.0504	0.04806	0.03968	0.04131	0.03432	0.04374	0.04706	0.04928	0.04434	0.04815	0.06122	0.05279	0.03122	0.05285	0.05266	0.04231	0.03452	0.0427	0.05846	0.05038	0.03598	0.03502	0.03163	0.03183	0.05898	0.04664	0.03527	0.04626	0.062	0.05391	0.04015	0.05437	0.04303	0.03379	0.05401	0.04155	0.06011	0.05243	0.0559	0.03768	0.04991	0.03138	0.03316	0.05273	0.06052	0.0539	0.04963	0.05205	-								
97	Genus	sp57	0.05557	0.00898	0.05033	0.07216	0.05288	0.05086	0.06686	0.05505	0.0529	0.03957	0.05008	0.05601	0.04475	0.07048	0.01283	0.05496	0.06259	0.06643	0.01097	0.05312	0.0179	0.0206	0.04281	0.05202	0.04329	0.06744	0.04601	0.05184	0.0564	0.05511	0.05498	0.06887	0.0429	0.05744	0.05413	0.07506	0.01016	0.04108	0.07075	0.04237	0.05489	0.06843	0.05666	0.06511	0.06257	0.06798	0.05839	0.05623	0.05225	0.05723	0.00457	0.07464	0.01244	0.05993	0.01883	0.05543	-							
98	Genus	sp58	0.0423	0.05156	0.0415	0.05499	0.01834	0.01495	0.05193	0.04774	0.04438	0.03817	0.04034	0.01874	0.03942	0.03167	0.04957	0.04376	0.04609	0.05519	0.05243	0.01549	0.05143	0.05296	0.04032	0.01669	0.04222	0.05587	0.04527	0.01711	0.01834	0.01509	0.01635	0.0557	0.04294	0.01944	0.04259	0.05987	0.05371	0.04021	0.05715	0.03885	0.01542	0.0543	0.04319	0.05479	0.0506	0.05199	0.02134	0.04809	0.01341	0.02164	0.0531	0.05777	0.05654	0.05373	0.0504	0.03267	0.05307	-						
99	Genus	sp59	0.04621	0.04025	0.04248	0.05892	0.04454	0.03914	0.0558	0.04773	0.04422	0.01821	0.04191	0.04317	0.02506	0.05894	0.03495	0.04447	0.05125	0.05868	0.03991	0.041	0.04023	0.04292	0.01885	0.04493	0.01834	0.05971	0.03165	0.04339	0.04546	0.04085	0.04129	0.06018	0.02752	0.04632	0.0474	0.05973	0.04136	0.0209	0.05823	0.02427	0.04343	0.05547	0.04482	0.05898	0.05667	0.05481	0.04569	0.04772	0.04266	0.04508	0.04033	0.06233	0.04167	0.05048	0.03787	0.04042	0.04303	0.04353	-					
101	Genus	sp60	0.04532	0.03806	0.04394	0.05689	0.0431	0.04045	0.05737	0.04772	0.0439	0.01539	0.04	0.04631	0.02354	0.0603	0.03354	0.04655	0.05348	0.0581	0.04181	0.04159	0.03929	0.0425	0.01605	0.04159	0.01859	0.05751	0.02767	0.04451	0.04603	0.04445	0.04503	0.05856	0.02502	0.04543	0.0472	0.06233	0.04044	0.01546	0.05881	0.0222	0.04157	0.05709	0.0475	0.05835	0.05439	0.0556	0.04599	0.04783	0.04152	0.04772	0.04184	0.0628	0.04433	0.05224	0.0381	0.04478	0.04129	0.04202	0.02034	-				
102	Genus	sp61	0.04543	0.04099	0.04408	0.05829	0.04468	0.04262	0.05558	0.04672	0.04605	0.01611	0.03874	0.04692	0.02528	0.06449	0.03708	0.04607	0.05396	0.05819	0.04409	0.04286	0.04177	0.04423	0.00851	0.04406	0.00874	0.05775	0.03045	0.04646	0.04764	0.04515	0.04608	0.05501	0.02764	0.04621	0.04758	0.06303	0.04332	0.0168	0.06091	0.02368	0.04378	0.05653	0.04637	0.05806	0.05306	0.05804	0.04782	0.04948	0.0434	0.04897	0.0433	0.06509	0.0472	0.05396	0.04046	0.04524	0.04395	0.04398	0.01999	0.01501	-			
105	Genus	sp62	0.03769	0.06376	0.05237	0.05507	0.05562	0.055	0.02722	0.05085	0.05614	0.05172	0.05182	0.05307	0.05939	0.06803	0.06172	0.05509	0.02611	0.01629	0.06193	0.05358	0.06369	0.06535	0.05961	0.05799	0.05627	0.03097	0.06397	0.06051	0.05592	0.05258	0.05356	0.03188	0.06107	0.05841	0.04481	0.06047	0.06442	0.05308	0.05145	0.0566	0.05317	0.05296	0.05327	0.01396	0.01224	0.05453	0.05995	0.05908	0.05246	0.05628	0.06342	0.05901	0.06282	0.05923	0.06333	0.05642	0.06682	0.05436	0.05907	0.06028	0.06012	-		
106	Genus	sp63	0.04473	0.04268	0.03911	0.06072	0.04469	0.04067	0.05284	0.04705	0.04254	0.02162	0.03925	0.04233	0.00257	0.05834	0.03843	0.04183	0.05159	0.05831	0.0429	0.0407	0.04337	0.04577	0.02405	0.0437	0.02405	0.05506	0.01908	0.04376	0.04421	0.04101	0.04194	0.05556	0.01598	0.04612	0.0473	0.06114	0.04346	0.02257	0.05716	0.00386	0.0423	0.05476	0.04309	0.05859	0.05292	0.05679	0.04753	0.04868	0.04101	0.04512	0.04246	0.06173	0.04395	0.0479	0.04466	0.04236	0.04492	0.04096	0.02372	0.02511	0.02614	0.05652	-	
107	Genus	sp64	0.04561	0.05336	0.04493	0.06069	0.02091	0.0176	0.06204	0.05213	0.04835	0.04117	0.04374	0.02172	0.04175	0.03586	0.04926	0.04847	0.05092	0.06143	0.05552	0.01814	0.05269	0.05477	0.04366	0.02055	0.04658	0.06384	0.04807	0.02096	0.02033	0.01439	0.01508	0.06372	0.04505	0.02259	0.04722	0.06536	0.05445	0.04317	0.06264	0.04187	0.01937	0.05876	0.04971	0.06089	0.05612	0.05655	0.02372	0.05253	0.01744	0.02349	0.05515	0.06374	0.05787	0.05431	0.0536	0.03604	0.05582	0.01617	0.04539	0.0453	0.04684	0.05999	0.04245	-
109	Genus	sp65	0.0426	0.03912	0.04148	0.05928	0.04414	0.04018	0.0513	0.04564	0.04575	0.01549	0.03965	0.0432	0.02353	0.05993	0.03674	0.04346	0.05001	0.05803	0.04038	0.03992	0.03998	0.04156	0.00712	0.04293	0.00693	0.05497	0.02898	0.04483	0.04569	0.04195	0.04278	0.05313	0.02557	0.04413	0.04631	0.06084	0.0422	0.01671	0.05643	0.02199	0.04253	0.05458	0.04355	0.05766	0.05251	0.0568	0.04665	0.04841	0.04144	0.04553	0.04014	0.06235	0.04316	0.05072	0.03931	0.04198	0.04306	0.04275	0.01806	0.0162	0.00127	0.0564	0.02319	0.04569	-				
110	Genus	sp66	0.04377	0.0393	0.03914	0.05344	0.04237	0.03671	0.04874	0.0458	0.04181	0.00131	0.03845	0.04216	0.02185	0.05583	0.03325	0.04241	0.04592	0.05382	0.04039	0.03925	0.03991	0.04325	0.0167	0.04298	0.01658	0.04967	0.02632	0.04249	0.04554	0.03909	0.04111	0.05027	0.02397	0.04553	0.04704	0.05691	0.04018	0.00131	0.05018	0.02054	0.04225	0.04921	0.04318	0.05424	0.05152	0.04899	0.04606	0.04663	0.03958	0.04442	0.04133	0.05642	0.04098	0.04736	0.03887	0.03957	0.04244	0.04071	0.01956	0.01761	0.01716	0.05141	0.02187	0.0438	0.01618	-			
111	Genus	sp67	0.05008	0.00689	0.0468	0.06635	0.04979	0.04789	0.06142	0.05005	0.05112	0.03548	0.04631	0.05002	0.04076	0.0656	0.01088	0.05006	0.05734	0.06203	0.0087	0.04836	0.01462	0.01678	0.03959	0.04947	0.04025	0.0624	0.04348	0.04884	0.05151	0.05033	0.05123	0.06307	0.04042	0.0545	0.04828	0.06831	0.00831	0.03674	0.06477	0.03943	0.0507	0.06177	0.05139	0.06082	0.05643	0.06058	0.05501	0.05315	0.04801	0.05275	0.0102	0.06929	0.01025	0.05609	0.01541	0.0504	0.00965	0.05094	0.03694	0.03773	0.04084	0.06158	0.0415	0.05209	0.03845	0.0375	-		
112	Genus	sp68	0.04171	0.03644	0.0389	0.05101	0.03982	0.03698	0.04903	0.04344	0.03946	0.00063	0.03626	0.04124	0.02018	0.0573	0.03114	0.04168	0.04724	0.05069	0.0386	0.03759	0.03744	0.04038	0.01527	0.04037	0.0159	0.05156	0.02513	0.04131	0.04317	0.03876	0.04104	0.0508	0.02235	0.04313	0.04339	0.05626	0.03756	0.00126	0.05287	0.01893	0.03997	0.05029	0.0424	0.05115	0.04815	0.048	0.04461	0.04417	0.03785	0.04393	0.03956	0.05836	0.04065	0.04797	0.03711	0.03894	0.03955	0.03872	0.01888	0.01471	0.01546	0.05226	0.02088	0.04169	0.01481	0.00065	0.03474	-	
113	Genus	sp69	0.04366	0.05217	0.01714	0.05855	0.04977	0.04684	0.05522	0.04877	0.02232	0.04253	0.01482	0.04778	0.04674	0.06487	0.04711	0.01988	0.04989	0.06005	0.05186	0.04699	0.05071	0.05259	0.04663	0.04948	0.04678	0.05862	0.05187	0.05265	0.05029	0.0477	0.0489	0.058	0.0491	0.04954	0.04493	0.05632	0.05393	0.04421	0.0561	0.04536	0.04906	0.0557	0.0203	0.06007	0.05211	0.05578	0.0515	0.00185	0.04618	0.04903	0.05255	0.05944	0.05224	0.02267	0.05099	0.04659	0.0555	0.0472	0.04537	0.04775	0.04618	0.05523	0.04528	0.0509	0.04441	0.04494	0.05011	0.04311	-


__END__


=head1 NAME

Biodiverse::TestHelpers - helper functions for Biodiverse tests.

=head1 SYNOPSIS

  use Biodiverse::TestHelpers;

=head1 DESCRIPTION

Helper functions for Biodiverse tests.

=head1 METHODS

=over 4

=item get_element_properties_test_data();

Element properties table data.

=back

=head1 AUTHOR

Shawn Laffan

=head1 LICENSE

LGPL

=head1 SEE ALSO

See http://www.purl.org/biodiverse for more details.


