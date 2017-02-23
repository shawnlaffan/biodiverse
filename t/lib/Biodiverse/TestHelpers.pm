#  helper functions for testing
package Biodiverse::TestHelpers;

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;
use Scalar::Util::Numeric qw/isfloat/;

$| = 1;

our $VERSION = '1.99_006';


use Data::Section::Simple qw(get_data_section);

BEGIN {
    if (!exists $ENV{BIODIVERSE_EXTENSIONS_IGNORE}) {
        $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;
    }
}

use Biodiverse::BaseData;
use Biodiverse::Tree;
use Biodiverse::TreeNode;
use Biodiverse::ReadNexus;
use Biodiverse::ElementProperties;

use Scalar::Util qw /looks_like_number reftype/;
use Test::More;
use Test::TempDir::Tiny;
use File::Spec::Functions 'catfile';

my $default_prng_seed = 2345;

use Exporter::Easy (
    TAGS => [
        utils  => [
            qw(
                compare_arr_vals
                compare_hash_vals
                get_all_calculations
                get_temp_dir
                get_temp_file_path
                is_or_isnt
                isnt_deeply
                snap_to_precision
                transform_element
                verify_set_contents
                write_data_to_temp_file
                is_numeric_within_tolerance_or_exact_text
            ),
        ],
        basedata => [
            qw(
                get_basedata_import_data_file
                get_basedata_test_data
                get_basedata_object
                get_basedata_object_from_site_data
                get_numeric_labels_basedata_object_from_site_data
                get_basedata_object_from_mx_format
                :utils
            ),
        ],
        element_properties => [
            qw(
                get_element_properties_test_data
                get_group_properties_site_data_object
                get_label_properties_site_data_object
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
                get_tree_array_from_sample_data
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
                cluster_test_matrix_recycling
                check_cluster_order_is_same_given_same_prng
                cluster_test_linkages_and_check_replication
                cluster_test_linkages_and_check_mx_precision
                :basedata
                :utils
            ),
        ],
        spatial_conditions => [
            qw (
                get_sp_cond_res_pairs_to_use
                run_sp_cond_tests
                test_sp_cond_res_pairs
                get_sp_conditions_to_run
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

=item isnt_deeply

Same as is_deeply except it returns false if the two structurees are the same. 

Stolen from https://github.com/coryb/perl-test-trivial/blob/master/lib/Test/Trivial.pm

=cut

# Test::More does not have an isnt_deeply
# so hacking one in here.
sub isnt_deeply {
    my ($got, $expected, $name) = @_;
    my $tb = Test::More->builder;

    $tb->_unoverload_str(\$expected, \$got);

    my $ok;
    if ( !ref $got and !ref $expected ) {
        # no references, simple comparison
        $ok = $tb->isnt_eq($got, $expected, $name);
    }
    elsif ( !ref $got xor !ref $expected ) {
        # not same type, so they are definitely different
        $ok = $tb->ok(1, $name);
    }
    else { # both references
        local @Test::More::Data_Stack = ();
        if ( Test::More::_deep_check($got, $expected) ) {
            # deep check passed, so they are the same
            $ok = $tb->ok(0, $name);
        }
        else {
            $ok = $tb->ok(1, $name);
        }
    }

    return $ok;
}

sub is_numeric_within_tolerance_or_exact_text {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my %args = @_;
    my ($got, $expected) = @args{qw /got expected/};

    if (looks_like_number ($expected) && looks_like_number ($got)) {
        my $result = ($args{tolerance} // 1e-10) > abs ($expected - $got);
        if (!$result) {
            #  sometimes we get diffs above the default due to floating point issues
            #  even when the two numbers are identical but only have 9dp
            $result = $expected eq $got;
        }
        ok ($result, $args{message});
    }
    else {
        is ($got, $expected, $args{message});
    }
}



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
    my $tolerance  = $args{tolerance};
    my $not_strict = $args{no_strict_match};
    my $descr_suffix = $args{descr_suffix} // q{};
    my $sort_array_lists = $args{sort_array_lists};

    #  check union of the two hashes
    my %targets = (%$hash_exp, %$hash_got);

    if (!$not_strict) {
        is (scalar keys %$hash_got, scalar keys %$hash_exp, "Hashes are same size $descr_suffix");

        my %h1 = %$hash_got;
        delete @h1{keys %$hash_exp};
        is (scalar keys %h1, 0, "No extra keys $descr_suffix");
        if (scalar keys %h1) {
            diag 'Extra keys: ', join q{ }, sort keys %h1;
        };

        my %h2 = %$hash_exp;
        delete @h2{keys %$hash_got};
        is (scalar keys %h2, 0, "No missing keys $descr_suffix");
        if (scalar keys %h2) {
            diag 'Missing keys: ', join q{ }, sort keys %h2;
        }
    }
    elsif (scalar keys %$hash_got == scalar keys %$hash_exp && scalar keys %$hash_exp == 0) {
        #  but if both are zero then we need to run at least one test to get a pass
        is (scalar keys %$hash_got, scalar keys %$hash_exp, "Hashes are same size $descr_suffix");
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
                    tolerance       => $tolerance,
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
                        tolerance => $tolerance,
                        #  add no_strict_match option??
                    );
                };
            }
            else {
                subtest "Got expected array for $key" => sub {
                    compare_arr (
                        arr_got => $hash_got->{$key},
                        arr_exp => $hash_exp->{$key},
                        tolerance => $tolerance,
                        #  add no_strict_match option??
                    );
                };
            }
        }
        else {
            is_numeric_within_tolerance_or_exact_text (
                got       => $hash_got->{$key},
                expected  => $hash_exp->{$key},
                message   => "Got expected value for $key, $descr_suffix",
                tolerance => $tolerance,
            );
            #my $val_got = snap_to_precision (
            #    value     => $hash_got->{$key},
            #    precision => $precision,
            #);
            #my $val_exp = snap_to_precision (
            #    value     => $hash_exp->{$key},
            #    precision => $precision,
            #);
            #is ($val_got, $val_exp, "Got expected value for $key, $descr_suffix");
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
    #my $precision = $args{precision};
    my $tolerance = $args{tolerance};

    is (scalar @$arr_got, scalar @$arr_exp, 'Arrays are same size');

    for my $i (0 .. $#$arr_exp) {
        #my $val_got = snap_to_precision (value => $arr_got->[$i], precision => $precision);
        #my $val_exp = snap_to_precision (value => $arr_exp->[$i], precision => $precision);
        #is ($val_got, $val_exp, "Got expected value for [$i]");
        is_numeric_within_tolerance_or_exact_text (
            got       => $arr_got->[$i],
            expected  => $arr_exp->[$i],
            message   => "Got expected value for [$i]",
            tolerance => $tolerance,
        );
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
    #my $precision = $args{precision};
    my $tolerance = $args{tolerance};

    is (scalar @arr_got, scalar @arr_exp, 'Arrays are same size');

    for (my $i = 0; $i != @arr_exp; ++$i) {
        #my $val_got = snap_to_precision (value => $arr_got[$i], precision => $precision);
        #my $val_exp = snap_to_precision (value => $arr_exp[$i], precision => $precision);
        #is ($val_got, $val_exp, "Got expected value for [$i]");
        is_numeric_within_tolerance_or_exact_text (
            got       => $arr_got[$i],
            expected  => $arr_exp[$i],
            message   => "Got expected value for [$i]",
            tolerance => $tolerance,
        );
    }

    return;
}

sub get_basedata_import_data_file {
    my %args = @_;

    my $data = $args{data} || get_basedata_test_data(@_);
    return write_data_to_temp_file($data);
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
    my $label_callback  = $args{label_generator} || sub {join '_', @_};

    my $data;
    $data .= "label,x,y,count\n";
    foreach my $i ($args{x_min} .. $args{x_max}) {
        my $ii = $i * $args{x_spacing};
        foreach my $j ($args{y_min} .. $args{y_max}) {
            my $jj = $j * $args{y_spacing};
            if ($use_rand_counts) {
                $count = int (rand() * 1000);
            }
            my $label = $numeric_labels ? $i : $label_callback->($i, $j);
            $data .= "$label,$ii,$jj,$count\n";
        }
    }

    return $data;
}


sub get_stringified_args_hash {
    my %args = @_;
    use Data::Dumper;

    local $Data::Dumper::Purity    = 1;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Quotekeys = 0;

    return Dumper \%args;
}

my %bd_cache;

sub get_basedata_object {
    my %args = @_;

    my $args_str = get_stringified_args_hash (%args);

    #  caching proved not to work well since all calls were different.  
    #{
    #    no autovivification;
    #    return $bd_cache{$args_str}->clone
    #      if $bd_cache{$args_str};
    #}

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

    #$bd_cache{$args_str} = $bd->clone;

    return $bd;
}

sub get_basedata_object_from_mx_format {
    my %args = @_;

    my $bd_f = get_basedata_import_data_file(@_);

    print "Temp file is $bd_f\n";

    my $bd = Biodiverse::BaseData->new(
        CELL_SIZES => $args{CELL_SIZES},
        NAME       => 'Test basedata',
    );
    $bd->import_data(
        input_files   => [$bd_f],
        label_columns => [],
        group_columns => [0],
        %args,
    );

    return $bd;
}

sub get_basedata_object_from_site_data {
    my %args = @_;

    my $file = write_data_to_temp_file(get_basedata_site_data());

    my $group_columns = $args{group_columns} // [3, 4];

    note("Temp file is $file\n");

    my $bd = Biodiverse::BaseData->new(
        CELL_SIZES => $args{CELL_SIZES},
        NAME       => 'Test basedata site data',
    );
    $bd->import_data(
        input_files   => [$file],
        group_columns => $group_columns,
        label_columns => [1, 2],
        skip_lines_with_undef_groups => 1,
    );

    return $bd;
}

sub get_numeric_labels_basedata_object_from_site_data {
    my %args = @_;
    my $sample_count_columns = exists $args{sample_count_columns} ? $args{sample_count_columns} : [3];

    my $file = write_data_to_temp_file(get_numeric_labels_basedata_site_data());

    note("Temp file is $file\n");

    my $bd = Biodiverse::BaseData->new(
        CELL_SIZES => $args{CELL_SIZES},
        NAME       => 'Test basedata site data, numeric labels',
    );
    $bd->import_data(
        input_files                  => [$file],
        group_columns                => [0, 1],
        label_columns                => [2],
        sample_count_columns         => $sample_count_columns,
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
    my $node_count = 0;
    my $read_nex = Biodiverse::ReadNexus->new;
    my $nodes = $read_nex->parse_newick(
        string => $newick,
        tree   => $tree,
        node_count => \$node_count,
    );

    return $tree;
}

sub get_tree_array_from_sample_data {
    my $self = shift;

    my $data = get_nexus_tree_data();
    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $data);
    };
    my @tree_array = $trees->get_tree_array;

    return wantarray ? @tree_array : \@tree_array;
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

sub get_temp_dir {
    return tempdir();
}

sub get_temp_file_path {
    my $fname = shift;
    my $dir = tempdir();
    return catfile($dir, $fname);
}

sub write_data_to_file {
    my ($fname, $data) = @_;
    open(my $fh, '>', $fname) or die "write_data_file: Cannot open $fname\n";
    print $fh $data;
    $fh->close;
}

sub write_data_to_temp_file {
    my $data = shift;
    my $file = get_temp_file_path('biodiverse.tmp');
    write_data_to_file($file, $data);
    return $file;
}

sub get_nexus_tree_data {
    return get_data_section('NEXUS_TREE');
}

sub get_newick_tree_data {
    return get_data_section('NEWICK_TREE');
}

sub get_tabular_tree_data {
    return get_data_section_with_unix_line_endings('TABULAR_TREE');
}

sub get_tabular_tree_data_x2 {
    return get_data_section_with_unix_line_endings('TABULAR_TREE_x2');
}

# Sometimes we get failing tests due to line ending problems
# This avoids it.
sub get_data_section_with_unix_line_endings {
    my $section = shift;

    my $data = get_data_section($section);

    if ($data =~ /\r/) {
        $data =~ s/\r//gs;
    }

    return $data;
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

sub get_label_properties_site_data_object {
    my $data  = get_label_properties_site_data;
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
    my $tmp = $1;
    $tmp =~ s/[\r\n]+$//;  #  clear any lurking \n or \r chars due to mixed line endings
    my @prop_names = split ',', $tmp;
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
    my $expected_results       = $args{expected_results} // {};
    my $expected_results_overlay = $args{expected_results_overlay};
    my $sort_array_lists       = $args{sort_array_lists};
    my $precision              = $args{precision} // '%.10f';  #  compare numeric values to 10 dp.
    my $tolerance              = $args{tolerance} // 1e-10;
    my $descr_suffix           = $args{descr_suffix} // '';
    my $processing_element     = $args{processing_element} // '3350000:850000';
    my $skip_nbr_counts        = $args{skip_nbr_counts} // {};
    delete $args{callbacks};

    # Used for acquiring sample results
    my $generate_result_sets = get_indices_result_set_fh ($args{generate_result_sets});

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

    my $bd = $args{basedata_ref};
    $bd ||= $use_numeric_labels
          ? get_numeric_labels_basedata_object_from_site_data (
                %bd_args,
            )
          : get_basedata_object_from_site_data (
                %bd_args,
            );

    if ($args{nbr_set2_sp_select_all}) {
        #  get all groups, but ensure no overlap with NS1
        my $gps = $bd->get_groups;
        my %el_hash;
        @el_hash{@$element_list1} = (1) x @$element_list1;
        say scalar @$gps;
        $element_list2 = [grep {!$el_hash{$_}} @$gps];
        say scalar @$element_list2;
    }
    
    my $tree = $args{tree_ref} || get_tree_object_from_sample_data();

    my $matrix = $args{matrix_ref} || get_matrix_object_from_sample_data();

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
        if (!ref $calc_topic_to_test) {
            $calc_topic_to_test = [$calc_topic_to_test];
        }
        my @expected_calcs_to_test;
        foreach my $topic (@$calc_topic_to_test) {
            my $calcs = $indices->get_calculations->{$topic};
            push @expected_calcs_to_test, @$calcs;
        }

        subtest 'Correct calculations are being tested' => sub {
            compare_arr_vals (
                arr_got => $calcs_to_test,
                arr_exp => \@expected_calcs_to_test,
            );
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
        processing_element    => $processing_element,
    };

    my %results_by_nbr_list;

  NBR_COUNT:
    foreach my $nbr_list_count (2, 1) {
        if ($nbr_list_count == 1) {
            delete $elements{element_list2};
        }

        next NBR_COUNT if $skip_nbr_counts->{$nbr_list_count};

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

        #  now we need to check the results
        my $subtest_name = "Result set matches for neighbour count $nbr_list_count";
        my $expected = $expected_results->{$nbr_list_count}
                     // eval $dss->get_data_section(
                            "RESULTS_${nbr_list_count}_NBR_LISTS"
                        );
        diag "Problem with data section: $EVAL_ERROR" if $EVAL_ERROR;
        if ($expected_results_overlay && $expected_results_overlay->{$nbr_list_count}) {
            my $hash = $expected_results_overlay->{$nbr_list_count};
            @$expected{keys %$hash} = values %$hash;
        }

        subtest $subtest_name => sub {
            compare_hash_vals (
                hash_got => \%results,
                hash_exp => \%{$expected},
                no_strict_match  => $args{no_strict_match},
                descr_suffix     => "$nbr_list_count nbr sets " . $descr_suffix,
                sort_array_lists => $sort_array_lists,
                precision        => $precision,
                tolerance        => $tolerance,
            );
        };

        print_indices_result_set_to_fh ($generate_result_sets, \%results, $nbr_list_count);

        $results_by_nbr_list{$nbr_list_count} = \%results;
    }
    
    return \%results_by_nbr_list;
}

#  put the results sets into a file
#  returns null if not needed
sub get_indices_result_set_fh {
    return if !shift;
    
    my $file_name = $0 . '.results';
    $file_name =~ s/\.t\./\./;  #  remove the .t 
    open(my $fh, '>', $file_name) or die "Unable to open $file_name to write results sets to";
    
    return $fh;
}


# Used for acquiring indices results
sub print_indices_result_set_to_fh {
    my ($fh, $results_hash, $nbr_list_count) = @_;

    return if !$fh;

    use Perl::Tidy;
    use Data::Dumper;

    local $Data::Dumper::Purity    = 1;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Quotekeys = 0;
    #say '#' x 20;

    my $source_string = Dumper($results_hash);
    my $dest_string;
    my $stderr_string;
    my $errorfile_string;
    my $argv = "-npro";   # Ignore any .perltidyrc at this site
    $argv .= " -pbp";     # Format according to perl best practices
    $argv .= " -nst";     # Must turn off -st in case -pbp is specified
    $argv .= " -se";      # -se appends the errorfile to stderr
    $argv .= " -no-log";  # Don't write the log file

    my $error = Perl::Tidy::perltidy(
        argv        => $argv,
        source      => \$source_string,
        destination => \$dest_string,
        stderr      => \$stderr_string,
        errorfile   => \$errorfile_string,    # ignored when -se flag is set
        ##phasers   => 'stun',                # uncomment to trigger an error
    );

    say   {$fh} "@@ RESULTS_${nbr_list_count}_NBR_LISTS";
    say   {$fh} $dest_string;
    print {$fh} "\n";
    #say '#' x 20;

    return;   
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

    my %tmp_hash;
    @tmp_hash{@$calcs_to_test} = 1 x @$calcs_to_test;
    my $expected_indices = $indices->get_indices (
        calculations   => \%tmp_hash,
        uses_nbr_lists => $nbr_list_count,
    );

    if ($nbr_list_count != 1) {
        #  skip if nbrs == 1 as otherwise we throw errors when calcs have been validly removed
        #  due to insufficient nbrs
        my $valid_calc_list = $indices->get_valid_calculations_to_run;
        is_deeply (
            [sort @$calcs_to_test],
            [sort keys %$valid_calc_list],
            "Requested calculations are all valid, nbr list count = $nbr_list_count",
        );
    }
    

    eval {
        $indices->run_precalc_globals(%$calc_args);
    };
    $e = $EVAL_ERROR;
    diag $e if $e;
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
    ok (!$e, "Ran calculations without eval error, $nbr_list_count nbrs");

    eval {
        $indices->run_postcalc_globals(%$calc_args);
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "Ran global postcalcs without eval error, $nbr_list_count nbrs");


    my $pass = is_deeply (
        [sort keys %results],
        [sort keys %$expected_indices],
        "Obtained indices as per metadata, nbr list count = $nbr_list_count",
    );
    if (!$pass) {
        local $Data::Dumper::Purity    = 1;
        local $Data::Dumper::Terse     = 1;
        local $Data::Dumper::Sortkeys  = 1;
        local $Data::Dumper::Indent    = 1;
        local $Data::Dumper::Quotekeys = 0;
        diag 'Got:';
        diag Data::Dumper::Dumper [sort keys %results];
        diag 'Expected from metadata:';
        diag Data::Dumper::Dumper [sort keys %$expected_indices];
    }
    

    
    if ($nbr_list_count != 1) {  #  only need to check when we have >1 nbr set
        #  does the metadata flag list indices correctly?
        subtest "List indices correctly marked in metadata" => sub {
            my $list_indices = $indices->get_list_indices (calculations => scalar $indices->get_valid_calculations_to_run);
            foreach my $index (sort keys %results) {
                my $reftype = reftype ($results{$index}) // 'scalar';
                my $is_list = ($reftype =~ /HASH|ARRAY/);
                if ($list_indices->{$index}) {
                    ok ($is_list, "index $index is a list");
                }
                else {
                    ok (!$is_list, "index $index is not a list");
                }
            }
        };
    }

    return wantarray ? %results : \%results;
}



###  spatial conditions stuff

sub get_sp_cond_res_pairs {
    my @res_pairs = (
        {
            res   => [10, 10],
            min_x => 1,
        },
        ##  now try for negative coords
        {
            res   => [10, 10],
            min_x => -30,
        },
        ##  now try for a mix of +ve and -ve coords
        {
            res   => [10, 10],
            min_x => -14,
        },
        ##  now try for +ve coords
        ##  but with cell sizes < 1
        {
            res   => [.1, .1],
            min_x => 1,
        },
        #  cellsize < 1 and +ve and -ve coords
        {
            res   => [.1, .1],
            min_x => -14,
        },
    );

    return wantarray ? @res_pairs : \@res_pairs;
}

sub get_sp_cond_res_pairs_to_use {
    my @args = @_;

    my @res_pairs = get_sp_cond_res_pairs();

    if (@args) {
        my @res_sub;
        for my $res (@args) {
            if (looks_like_number $res && $res < $#res_pairs) {
                push @res_sub, $res;
            }
        }
        if (scalar @res_sub) {
            diag 'Using res pair subset: ' . join ", ", @res_sub;
            @res_pairs = @res_pairs[@res_sub];

            local $Data::Dumper::Purity   = 1;
            local $Data::Dumper::Terse    = 1;
            local $Data::Dumper::Sortkeys = 1;
            diag Dumper \@res_pairs;
        }
    }
    else {  #  run a subset by default
        @res_pairs = @res_pairs[2, 4];
    }

    return wantarray ? @res_pairs : \@res_pairs;
}


sub run_sp_cond_tests {
    my %args = @_;
    my $bd      = $args{basedata};
    my $element = $args{element};
    my $conditions = $args{conditions};
    my $index_version = $args{index_version};

    my $res = $args{resolution} || $bd->get_param('CELL_SIZES');

    my ($index, $index_offsets);
    my $index_text = ' (no spatial index)';
    
    my %results;

    my $nbrs_from_no_index;
    my @index_res_multipliers = (0, 1, 2);

    foreach my $i (sort {$a <=> $b} @index_res_multipliers) {

        if ($i) {
            my @index_res = map {$_ * $i} @$res;
            $index = $bd->build_spatial_index (
                resolutions => [@index_res],
                version     => $index_version,
            );
            $index_text = ' (Index res is ' . join (q{ }, @index_res) . ')';
        }

        foreach my $condition (sort keys %$conditions) {
            my $expected = $conditions->{$condition};

            my $cond = $condition;

            while ($condition =~ /##(\d+)/gc) {
                my $from = $1;
                my $to = $from * $res->[0];  #  assuming square groups
                $cond =~ s/##$from/$to/;
                #print "Matched $from to $to\n";
                #print $cond . "\n";
            }

            #diag $cond;

            my $sp_conditions = Biodiverse::SpatialConditions->new (
                conditions   => $cond,
                basedata_ref => $bd,
            );

            if ($index) {
                $index_offsets = $index->predict_offsets (
                    spatial_conditions => $sp_conditions,
                    cellsizes          => $bd->get_param ('CELL_SIZES'),
                );
            }

            my $nbrs = eval {
                $bd->get_neighbours (
                    element            => $element,
                    spatial_conditions => $sp_conditions,
                    index              => $index,
                    index_offsets      => $index_offsets,
                );
            };
            croak $EVAL_ERROR if $EVAL_ERROR;

            is (keys %$nbrs, $expected, "Nbr count: $cond$index_text");
            if ($nbrs_from_no_index->{$condition}) {
                is_deeply ($nbrs, $nbrs_from_no_index->{$condition}, "Nbr hash: $cond$index_text")
            }
            else {
                $nbrs_from_no_index->{$condition} = $nbrs;
                $results{$cond} = $nbrs;
            }
        }
    }

    return wantarray ? %results : \%results;
}


sub test_sp_cond_res_pairs {
    my ($conditions, $res_pairs, $zero_cell_sizes) = @_;
    my @res_pairs  = @$res_pairs;
    
    my %results;

    SKIP:
    {
        while (my $cond = shift @res_pairs) {
            my $res = $cond->{res};
            my @x   = ($cond->{min_x}, $cond->{min_x} + 29);  #  max is 29+min
            my @y   = @x;
            my $bd = get_basedata_object(
                x_spacing  => $res->[0],
                y_spacing  => $res->[1],
                CELL_SIZES => $res,
                x_max      => $x[1],
                y_max      => $y[1],
                x_min      => $x[0],
                y_min      => $y[0],
            );
            my $key = join (':', @$res, @x);

            #  should sub this - get centre_group or something
            my $element_x = $res->[0] * (($x[0] + $x[1]) / 2) + $res->[0];
            my $element_y = $res->[1] * (($y[0] + $y[1]) / 2) + $res->[1];
            my $element = join ":", $element_x, $element_y;
            
            if ($zero_cell_sizes) {
                $bd->set_param(CELL_SIZES => [0,0]);
            }
    
            $results{$key} = run_sp_cond_tests (
                basedata   => $bd,
                element    => $element,
                conditions => $conditions,
                index_version => undef,  #  this arg is for debug
                resolution => $res,
            );
        }
    }
    return wantarray ? %results : \%results;
}

sub get_sp_conditions_to_run {
    my ($conditions, @args) = @_;

    my $conditions_to_run = $conditions;

    if (@args) {
        my %cond_sub;
        for my $cond (@args) {
            if (exists $conditions->{$cond} && exists $conditions->{$cond}) {
                $cond_sub{$cond} = $conditions->{$cond};
            }
        }

        if (scalar keys %cond_sub) {
            diag 'Using conditions subset: ' . join ', ', sort keys %cond_sub;
        }
        $conditions_to_run = \%cond_sub;
    }

    return wantarray ? %$conditions_to_run : $conditions_to_run;
}


#  need to add tie breaker
sub check_cluster_order_is_same_given_same_prng {
    my %args = @_;
    my $bd = $args{basedata_ref};
    my $type = $args{type} // 'Biodiverse::Cluster';
    my $prng_seed = $args{prng_seed} || $default_prng_seed;
    
    my $cl1 = $bd->add_output (name => 'cl1 with prng seed', type => $type);
    my $cl2 = $bd->add_output (name => 'cl2 with prng seed', type => $type);
    my $cl3 = $bd->add_output (name => 'cl3 with prng seed+1', type => $type);
    
    $cl1->run_analysis (
        prng_seed => $prng_seed,
    );
    $cl2->run_analysis (
        prng_seed => $prng_seed,
    );
    $cl3->run_analysis (
        prng_seed => $prng_seed + 1,  #  different prng
    );
    
    #my $newick1 = $cl1->to_newick;
    #my $newick2 = $cl2->to_newick;
    #my $newick3 = $cl3->to_newick;
    #is   ($newick1, $newick2, 'trees are the same');
    #isnt ($newick1, $newick3, 'trees are not the same');
    
    my $cmp2 = $cl1->trees_are_same (comparison => $cl2);
    my $cmp3 = $cl1->trees_are_same (comparison => $cl3);

    ok ($cmp2,  'trees are the same given same PRNG seed');
    ok (!$cmp3, 'trees are not the same given different PRNG seed');
}

#  Need to use an index that needs arguments
#  so we exercise the whole shebang.
sub cluster_test_matrix_recycling {
    my %args = @_;
    my $type  = $args{type}  // 'Biodiverse::Cluster';
    my $index = $args{index} // 'SORENSON';
    my $tie_breaker = exists $args{tie_breaker}  #  use undef if the user passed the arg key
        ? $args{tie_breaker}
        : [ENDW_WE => 'maximise', PD => 'maximise', ABC3_SUM_ALL => 'maximise', none => 'maximise'];  #  we will fail if random tiebreaker is use
        #: [ENDW_WE => 'max', PD => 'max'];
        #: [RICHNESS_ALL => 'max', PD => 'max'];
        #: [random => 'max', PD => 'max'];

    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [300000, 300000]);
    my $tree_ref  = get_tree_object_from_sample_data();

    my %analysis_args = (
        %args,
        tree_ref    => $tree_ref,
        index       => $index,
        cluster_tie_breaker => $tie_breaker,
        #prng_seed   => $default_prng_seed,  #  should not need this when using appropriate tie breakers
    );
    
    my $cl1 = $bd->add_output (name => 'cl1 mx recyc', type => $type);
    $cl1->run_analysis (%analysis_args);

    my $cl2 = $bd->add_output (name => 'cl2 mx recyc', type => $type);
    $cl2->run_analysis (%analysis_args);

    if ($cl1->get_type eq 'RegionGrower') {
        #  we should have no negative branch lengths
        my %nodes = $cl1->get_node_hash;
        my $neg_count = grep {$_->get_length < 0} values %nodes;
        is ($neg_count, 0, 'No negative branch lengths');
    }
    
    ok (
        $cl1->trees_are_same (comparison => $cl2),
        'Clustering using reycled matrices'
    );

    my $cl3 = $bd->add_output (name => 'cl3 mx recyc', type => $type);
    $cl3->run_analysis (%analysis_args);

    ok (
        $cl1->trees_are_same (comparison => $cl3),
        'Clustering using reycled matrices, 2nd time round'
    );

#$bd->save (filename => 'check.bds');
    
    my $mx_ref1 = $cl1->get_orig_matrices;
    my $mx_ref2 = $cl2->get_orig_matrices;
    my $mx_ref3 = $cl3->get_orig_matrices;

    is ($mx_ref1, $mx_ref2, 'recycled matrices correctly, 1&2');
    is ($mx_ref1, $mx_ref3, 'recycled matrices correctly, 1&3');

    #  now check what happens when we destroy the matrix in the clustering
    $bd->delete_all_outputs;

    my $cl4 = $bd->add_output (name => 'cl4 mx recyc', type => $type);
    $cl4->run_analysis (%analysis_args, no_clone_matrices => 1);

    my $cl5 = $bd->add_output (name => 'cl5 mx recyc', type => $type);
    $cl5->run_analysis (%analysis_args);

    ok (
        $cl4->trees_are_same (comparison => $cl5),
        'Clustering using reycled matrices when matrix is destroyed in clustering'
    );

    my $mx_ref4 = $cl4->get_orig_matrices;
    my $mx_ref5 = $cl5->get_orig_matrices;
    isnt ($mx_ref1, $mx_ref4, 'did not recycle matrices, 1 v 4');
    isnt ($mx_ref1, $mx_ref5, 'did not recycle matrices, 1 v 5');
    isnt ($mx_ref4, $mx_ref5, 'did not recycle matrices, 4 v 5');
    
    #  now we try with a combination of spatial condition and def query
    $bd->delete_all_outputs;

    my $cl6 = $bd->add_output (name => 'cl6 mx recyc', type => $type);
    $cl6->run_analysis (%analysis_args, spatial_conditions => ['sp_select_all()']);

    my $cl7 = $bd->add_output (name => 'cl7 mx recyc', type => $type);
    $cl7->run_analysis (%analysis_args, def_query => 'sp_select_all()');

    my $mx_ref6 = $cl6->get_orig_matrices;
    my $mx_ref7 = $cl7->get_orig_matrices;
    isnt ($mx_ref6, $mx_ref7, 'did not recycle matrices, 6 v 7');
    
    my $cl8 = $bd->add_output (name => 'cl8 mx recyc', type => $type);
    $cl8->run_analysis (%analysis_args, spatial_conditions => ['sp_select_all()']);
    my $mx_ref8 = $cl8->get_orig_matrices;
    is ($mx_ref6, $mx_ref8, 'did recycle matrices, 6 v 8');

    my $cl9 = $bd->add_output (name => 'cl9 mx recyc', type => $type);
    $cl9->run_analysis (%analysis_args, def_query => 'sp_select_all()');
    my $mx_ref9 = $cl9->get_orig_matrices;
    is ($mx_ref7, $mx_ref9, 'did recycle matrices, 7 v 8');

}

sub cluster_test_linkages_and_check_mx_precision {
    my %args = @_;
    #  make sure we get the same cluster result using different matrix precisions
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);
    my $tie_breaker = 'random';
    my $type = $args{type} // 'Biodiverse::Cluster';
    
    my $linkage_funcs = $args{linkage_funcs} // get_cluster_linkages();

    foreach my $linkage (@$linkage_funcs) {
        my $prng_seed = 123456;
        $bd->delete_all_outputs();

        my $class1 = 'Biodiverse::Matrix';
        my $cl1 = $bd->add_output (
            name => "$class1 $linkage 1",
            type => $type,
            MATRIX_CLASS        => $class1,
        );
        $cl1->run_analysis (
            prng_seed        => $prng_seed,
            linkage_function => $linkage,
            cluster_tie_breaker => [$tie_breaker => 'max'],
        );
        my $nwk1 = $cl1->to_newick;

        #  make sure we build a new matrix
        $bd->delete_all_outputs();

        my $cl2 = $bd->add_output (
            name => "$class1 $linkage 2",
            type => $type,
            MATRIX_CLASS           => $class1,
            MATRIX_INDEX_PRECISION => undef,
        );
        $cl2->run_analysis (
            prng_seed        => $prng_seed,
            linkage_function => $linkage,
            cluster_tie_breaker => [$tie_breaker => 'max'],
        );
        my $nwk2 = $cl2->to_newick;

        #  getting cache deletion issues - need to look into them before using this test
        ok (
            $cl1->trees_are_same (
                comparison => $cl2,
            ),
            "Clustering using matrices with differing index precisions, linkage $linkage"
        );

        #  this test will likely have issues with v5.18 and hash randomisation
        SKIP:
        {
            skip 'this test will likely have issues with v5.18 and hash randomisation', 1;
            is (
                $nwk1,
                $nwk2,
                "nwk: Clustering using matrices with differing index precisions, linkage $linkage"
            );
        }
        #print join "\n", ('======') x 4;
        #say "$linkage $nwk1";
        #print join "\n", ('======') x 4;
    }
}


sub get_cluster_linkages {
    my @linkages = qw /
        link_average
        link_recalculate
        link_minimum
        link_maximum
        link_average_unweighted
    /;

    return wantarray ? @linkages : \@linkages;
}

sub cluster_test_linkages_and_check_replication {
    my %args = (delete_outputs => 1, @_);

    my $type = $args{type} // 'Biodiverse::Cluster';
    my $linkage_funcs = $args{linkage_funcs} // get_cluster_linkages();
    my @tie_breaker   = (ENDW_WE => 'max', ABC3_SUM_ALL => 'max');

    my $bd1 = get_basedata_object_from_site_data(CELL_SIZES => [200000, 300000]);
    my $bd2 = $bd1->clone;

    foreach my $linkage (@$linkage_funcs) {
        my $cl1 = $bd1->add_output (name => $linkage, type => $type);
        $cl1->run_analysis (
            prng_seed        => $default_prng_seed,
            linkage_function => $linkage,
            cluster_tie_breaker => [@tie_breaker],
        );
        my $cl2 = $bd2->add_output (name => $linkage, type => $type);
        $cl2->run_analysis (
            prng_seed        => $default_prng_seed,
            linkage_function => $linkage,
            cluster_tie_breaker => [@tie_breaker],
        );

        my $suffix = $args{delete_outputs} ? ', no matrix recycle' : 'recycled matrix';
        my $are_same = $cl1->trees_are_same (comparison => $cl2);
        ok ($are_same, "Check Rep: Exact match using $linkage" . $suffix);

        my $nodes_have_matching_terminals = $cl1->trees_are_same (
            comparison     => $cl2,
            terminals_only => 1,
        );
        ok (
            $nodes_have_matching_terminals,
            "Check Rep: Nodes have matching terminals using $linkage" . $suffix,
        );

        if ($args{delete_outputs}) {
            $bd1->delete_all_outputs;
            $bd2->delete_all_outputs;
        }
    }
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

@@ NEWICK_TREE
(((((((((((44:0.6,47:0.6):0.077662337662338,(18:0.578947368421053,58:0.578947368421053):0.098714969241285):0.106700478344225,31:0.784362816006563):0.05703610742759,(6:0.5,35:0.5):0.341398923434153):0.03299436960061,(((((1:0.434782608695652,52:0.434782608695652):0.051317777404734,57:0.486100386100386):0.11249075347436,22:0.598591139574746):0.0272381982058111,46:0.625829337780557):0.172696292660468,(7:0.454545454545455,9:0.454545454545455):0.34398017589557):0.075867662593738):0.057495084175743,((4:0,25:0):0.666666666666667,16:0.666666666666667):0.265221710543839):0.026396763298318,((0:0.789473684210526,12:0.789473684210526):0.111319966583125,(15:0.6,30:0.6):0.300793650793651):0.0574914897151729):0.020427284632173,48:0.978712425140997):0.00121523842637206,(24:0.25,55:0.25):0.729927663567369):0.00291112550535999,((((38:0.461538461538462,13:0.461538461538462):0.160310277957336,(50:0.166666666666667,59:0.166666666666667):0.455182072829131):0.075519681556834,32:0.697368421052632):0.258187134502923,2:0.955555555555555):0.027283233517174):0.00993044169650192,42:0.992769230769231):0;

@@ NEXUS_TREE
#NEXUS
[ID: Example_tree2]
begin trees;
	[Export of a Biodiverse::TreeNode tree using Biodiverse::TreeNode version 0.17]
	Translate 
		0 Genus:sp9,
		1 Genus:sp23,
		2 Genus:sp13,
		3 Genus:sp28,
		4 50___,
		5 Genus:sp26,
		6 54___,
		7 42___,
		8 30___,
		9 55___,
		10 Genus:sp21,
		11 45___,
		12 40___,
		13 Genus:sp18,
		14 38___,
		15 37___,
		16 Genus:sp8,
		17 31___,
		18 Genus:sp3,
		19 Genus:sp14,
		20 Genus:sp27,
		21 Genus:sp15,
		22 34___,
		23 Genus:sp29,
		24 Genus:sp24,
		25 44___,
		26 Genus:sp31,
		27 36___,
		28 Genus:sp16,
		29 Genus:sp10,
		30 Genus:sp4,
		31 58___,
		32 49___,
		33 56___,
		34 39___,
		35 Genus:sp20,
		36 32___,
		37 Genus:sp2,
		38 46___,
		39 59___,
		40 47___,
		41 Genus:sp22,
		42 Genus:sp19,
		43 53___,
		44 Genus:sp12,
		45 Genus:sp5,
		46 43___,
		47 Genus:sp17,
		48 48___,
		49 33___,
		50 Genus:sp6,
		51 51___,
		52 35___,
		53 Genus:sp30,
		54 57___,
		55 Genus:sp25,
		56 41___,
		57 Genus:sp11,
		58 Genus:sp1,
		59 Genus:sp7,
		60 52___
		;
	Tree Example_tree1 = (((((((((((42:0.6,45:0.6)8:0.077662337662338,(21:0.578947368421053,58:0.578947368421053)17:0.098714969241285)36:0.106700478344225,29:0.784362816006563)49:0.05703610742759,(5:0.5,35:0.5)22:0.341398923434153)52:0.03299436960061,(((((1:0.434782608695652,53:0.434782608695652)27:0.051317777404734,57:0.486100386100386)15:0.11249075347436,23:0.598591139574746)14:0.0272381982058111,44:0.625829337780557)34:0.172696292660468,(10:0.454545454545455,13:0.454545454545455)12:0.34398017589557)56:0.075867662593738)7:0.057495084175743,((3:0,26:0)46:0.666666666666667,20:0.666666666666667)25:0.265221710543839)11:0.026396763298318,((0:0.789473684210526,16:0.789473684210526)38:0.111319966583125,(19:0.6,28:0.6)40:0.300793650793651)48:0.0574914897151729)32:0.020427284632173,47:0.978712425140997)4:0.00121523842637206,(24:0.25,55:0.25)51:0.729927663567369)60:0.00291112550535999,((((37:0.461538461538462,18:0.461538461538462)43:0.160310277957336,(50:0.166666666666667,59:0.166666666666667)6:0.455182072829131)9:0.075519681556834,30:0.697368421052632)33:0.258187134502923,2:0.955555555555555)54:0.027283233517174)31:0.00993044169650192,41:0.992769230769231)39:0;
	Tree Example_tree2 = (((((((((((42:0.6,45:0.6)8:0.077662337662338,(21:0.578947368421053,58:0.578947368421053)17:0.098714969241285)36:0.106700478344225,29:0.784362816006563)49:0.05703610742759,(5:0.5,35:0.5)22:0.341398923434153)52:0.03299436960061,(((((1:0.434782608695652,53:0.434782608695652)27:0.051317777404734,57:0.486100386100386)15:0.11249075347436,23:0.598591139574746)14:0.0272381982058111,44:0.625829337780557)34:0.172696292660468,(10:0.454545454545455,13:0.454545454545455)12:0.34398017589557)56:0.075867662593738)7:0.057495084175743,((3:0,26:0)46:0.666666666666667,20:0.666666666666667)25:0.265221710543839)11:0.026396763298318,((0:0.789473684210526,16:0.789473684210526)38:0.111319966583125,(19:0.6,28:0.6)40:0.300793650793651)48:0.0574914897151729)32:0.020427284632173,47:0.978712425140997)4:0.00121523842637206,(24:0.25,55:0.25)51:0.729927663567369)60:0.00291112550535999,((((37:0.461538461538462,18:0.461538461538462)43:0.160310277957336,(50:0.166666666666667,59:0.166666666666667)6:0.455182072829131)9:0.075519681556834,30:0.697368421052632)33:0.258187134502923,2:0.955555555555555)54:0.027283233517174)31:0.00993044169650192,41:0.992769230769231)39:0;
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
3150000	1050000	393	21
3150000	1050000	399	50
3150000	1050000	405	118
3150000	1050000	411	96
3150000	1050000	417	122
3150000	1050000	423	121
3150000	1050000	429	87
3150000	1050000	435	107
3150000	1050000	441	125
3150000	1050000	447	125
3150000	1050000	453	148
3150000	1050000	459	108
3150000	1050000	465	84
3150000	1050000	471	117
3150000	1050000	477	80
3150000	1050000	483	56
3150000	1050000	489	41
3150000	1050000	495	23
3150000	1050000	501	18
3150000	1050000	507	10
3150000	1050000	513	17
3150000	1050000	519	5
3150000	1050000	525	7
3150000	1050000	532	1
3150000	1050000	541	1
3150000	650000	1004	4
3150000	650000	1011	1
3150000	650000	1018	2
3150000	650000	1024	2
3150000	650000	1031	3
3150000	650000	1038	3
3150000	650000	1045	1
3150000	650000	1053	5
3150000	650000	1059	2
3150000	650000	1065	4
3150000	650000	1071	3
3150000	650000	1078	2
3150000	650000	1085	1
3150000	650000	1092	2
3150000	650000	1098	6
3150000	650000	1104	6
3150000	650000	1110	2
3150000	650000	1118	6
3150000	650000	1125	1
3150000	650000	1136	4
3150000	650000	1142	4
3150000	650000	1148	2
3150000	650000	1155	1
3150000	650000	1163	2
3150000	650000	1170	1
3150000	650000	1177	1
3150000	650000	1188	2
3150000	650000	1195	4
3150000	650000	1205	1
3150000	650000	1218	4
3150000	650000	1228	1
3150000	650000	1241	4
3150000	650000	1249	1
3150000	650000	1265	1
3150000	650000	1279	2
3150000	650000	1301	3
3150000	650000	1311	1
3150000	650000	1328	1
3150000	650000	1355	1
3150000	650000	1402	1
3150000	650000	572	3
3150000	650000	578	10
3150000	650000	584	20
3150000	650000	590	36
3150000	650000	596	43
3150000	650000	602	44
3150000	650000	608	47
3150000	650000	614	49
3150000	650000	620	31
3150000	650000	626	41
3150000	650000	632	38
3150000	650000	638	38
3150000	650000	644	28
3150000	650000	650	32
3150000	650000	656	37
3150000	650000	662	30
3150000	650000	668	27
3150000	650000	674	34
3150000	650000	680	24
3150000	650000	686	21
3150000	650000	692	31
3150000	650000	698	27
3150000	650000	704	30
3150000	650000	710	40
3150000	650000	716	32
3150000	650000	722	28
3150000	650000	728	21
3150000	650000	734	21
3150000	650000	740	18
3150000	650000	746	30
3150000	650000	752	15
3150000	650000	758	5
3150000	650000	764	15
3150000	650000	770	12
3150000	650000	776	19
3150000	650000	782	7
3150000	650000	788	11
3150000	650000	794	8
3150000	650000	800	14
3150000	650000	806	15
3150000	650000	812	10
3150000	650000	818	13
3150000	650000	824	12
3150000	650000	830	5
3150000	650000	836	6
3150000	650000	842	10
3150000	650000	848	8
3150000	650000	854	9
3150000	650000	860	4
3150000	650000	866	3
3150000	650000	872	10
3150000	650000	878	7
3150000	650000	884	5
3150000	650000	890	6
3150000	650000	896	2
3150000	650000	902	1
3150000	650000	908	1
3150000	650000	914	6
3150000	650000	920	7
3150000	650000	926	2
3150000	650000	934	2
3150000	650000	941	3
3150000	650000	947	6
3150000	650000	954	2
3150000	650000	961	4
3150000	650000	967	4
3150000	650000	974	2
3150000	650000	980	5
3150000	650000	986	1
3150000	650000	992	7
3150000	650000	999	2
3150000	750000	1005	10
3150000	750000	1011	9
3150000	750000	1017	7
3150000	750000	1023	2
3150000	750000	1029	2
3150000	750000	1035	2
3150000	750000	1041	7
3150000	750000	1047	7
3150000	750000	1053	10
3150000	750000	1059	4
3150000	750000	1065	4
3150000	750000	1071	4
3150000	750000	1077	6
3150000	750000	1083	10
3150000	750000	1089	11
3150000	750000	1095	2
3150000	750000	1101	3
3150000	750000	1107	7
3150000	750000	1113	6
3150000	750000	1119	5
3150000	750000	1125	2
3150000	750000	1131	10
3150000	750000	1137	5
3150000	750000	1143	7
3150000	750000	1149	10
3150000	750000	1155	5
3150000	750000	1161	11
3150000	750000	1167	10
3150000	750000	1173	8
3150000	750000	1179	16
3150000	750000	1185	9
3150000	750000	1191	8
3150000	750000	1197	3
3150000	750000	1203	14
3150000	750000	1209	10
3150000	750000	1215	10
3150000	750000	1221	8
3150000	750000	1227	14
3150000	750000	1233	9
3150000	750000	1239	6
3150000	750000	1245	16
3150000	750000	1251	11
3150000	750000	1257	9
3150000	750000	1263	12
3150000	750000	1269	12
3150000	750000	1275	13
3150000	750000	1281	20
3150000	750000	1287	22
3150000	750000	1293	8
3150000	750000	1299	8
3150000	750000	1305	16
3150000	750000	1311	15
3150000	750000	1317	11
3150000	750000	1323	5
3150000	750000	1329	11
3150000	750000	1335	21
3150000	750000	1341	11
3150000	750000	1347	10
3150000	750000	1353	14
3150000	750000	1359	16
3150000	750000	1365	14
3150000	750000	1371	7
3150000	750000	1377	10
3150000	750000	1383	12
3150000	750000	1389	17
3150000	750000	1395	7
3150000	750000	1401	15
3150000	750000	1407	7
3150000	750000	1413	14
3150000	750000	1419	10
3150000	750000	1425	19
3150000	750000	1431	16
3150000	750000	1437	13
3150000	750000	1443	9
3150000	750000	1449	10
3150000	750000	1455	8
3150000	750000	1461	9
3150000	750000	1467	8
3150000	750000	1473	12
3150000	750000	1479	10
3150000	750000	1485	9
3150000	750000	1491	10
3150000	750000	1497	6
3150000	750000	1503	11
3150000	750000	1509	8
3150000	750000	1515	13
3150000	750000	1521	12
3150000	750000	1527	5
3150000	750000	1533	8
3150000	750000	1539	5
3150000	750000	1545	9
3150000	750000	1551	10
3150000	750000	1557	4
3150000	750000	1563	6
3150000	750000	1569	7
3150000	750000	1575	10
3150000	750000	1581	7
3150000	750000	1587	4
3150000	750000	1593	2
3150000	750000	1599	7
3150000	750000	1605	2
3150000	750000	1611	1
3150000	750000	1617	3
3150000	750000	1624	3
3150000	750000	1630	3
3150000	750000	1636	3
3150000	750000	1642	2
3150000	750000	1648	5
3150000	750000	1654	2
3150000	750000	1661	1
3150000	750000	1667	4
3150000	750000	1675	1
3150000	750000	1682	1
3150000	750000	1688	3
3150000	750000	1697	2
3150000	750000	1704	1
3150000	750000	1711	2
3150000	750000	1717	3
3150000	750000	1724	1
3150000	750000	1730	1
3150000	750000	1739	1
3150000	750000	1746	2
3150000	750000	1756	1
3150000	750000	1772	1
3150000	750000	1782	1
3150000	750000	1793	2
3150000	750000	1802	1
3150000	750000	1819	4
3150000	750000	1828	3
3150000	750000	1843	1
3150000	750000	1855	2
3150000	750000	1864	2
3150000	750000	1874	1
3150000	750000	1891	1
3150000	750000	1903	1
3150000	750000	1926	1
3150000	750000	1938	2
3150000	750000	1958	3
3150000	750000	1981	1
3150000	750000	2001	1
3150000	750000	2022	3
3150000	750000	2039	1
3150000	750000	2050	1
3150000	750000	2070	2
3150000	750000	2087	1
3150000	750000	2110	2
3150000	750000	2126	1
3150000	750000	2144	1
3150000	750000	2157	1
3150000	750000	2172	1
3150000	750000	2186	1
3150000	750000	2204	1
3150000	750000	2212	3
3150000	750000	2231	2
3150000	750000	2241	1
3150000	750000	2251	1
3150000	750000	2270	1
3150000	750000	2287	2
3150000	750000	2298	3
3150000	750000	2308	2
3150000	750000	2316	4
3150000	750000	2329	2
3150000	750000	2352	1
3150000	750000	2365	3
3150000	750000	2375	2
3150000	750000	2392	2
3150000	750000	2406	2
3150000	750000	2437	1
3150000	750000	2496	1
3150000	750000	700	2
3150000	750000	706	2
3150000	750000	712	14
3150000	750000	718	5
3150000	750000	724	5
3150000	750000	730	3
3150000	750000	736	10
3150000	750000	742	7
3150000	750000	748	12
3150000	750000	754	14
3150000	750000	760	15
3150000	750000	766	18
3150000	750000	772	25
3150000	750000	778	11
3150000	750000	784	18
3150000	750000	790	32
3150000	750000	796	21
3150000	750000	802	25
3150000	750000	808	29
3150000	750000	814	24
3150000	750000	820	17
3150000	750000	826	23
3150000	750000	832	18
3150000	750000	838	17
3150000	750000	844	11
3150000	750000	850	10
3150000	750000	856	15
3150000	750000	862	6
3150000	750000	868	17
3150000	750000	874	9
3150000	750000	880	14
3150000	750000	886	16
3150000	750000	892	10
3150000	750000	898	17
3150000	750000	904	3
3150000	750000	910	3
3150000	750000	916	5
3150000	750000	922	10
3150000	750000	928	4
3150000	750000	934	7
3150000	750000	940	6
3150000	750000	946	4
3150000	750000	952	11
3150000	750000	958	3
3150000	750000	964	2
3150000	750000	970	5
3150000	750000	976	6
3150000	750000	982	7
3150000	750000	988	8
3150000	750000	994	4
3150000	850000	1000	3
3150000	850000	1006	11
3150000	850000	1012	9
3150000	850000	1018	6
3150000	850000	1024	10
3150000	850000	1030	14
3150000	850000	1036	15
3150000	850000	1042	6
3150000	850000	1048	8
3150000	850000	1054	4
3150000	850000	1060	7
3150000	850000	1066	7
3150000	850000	1072	9
3150000	850000	1078	8
3150000	850000	1084	7
3150000	850000	1090	12
3150000	850000	1096	7
3150000	850000	1102	9
3150000	850000	1108	6
3150000	850000	1114	12
3150000	850000	1120	8
3150000	850000	1126	14
3150000	850000	1132	9
3150000	850000	1138	8
3150000	850000	1144	10
3150000	850000	1150	12
3150000	850000	1156	9
3150000	850000	1162	7
3150000	850000	1168	10
3150000	850000	1174	6
3150000	850000	1180	6
3150000	850000	1186	10
3150000	850000	1192	8
3150000	850000	1198	14
3150000	850000	1204	7
3150000	850000	1210	10
3150000	850000	1216	7
3150000	850000	1222	2
3150000	850000	1228	10
3150000	850000	1234	6
3150000	850000	1240	6
3150000	850000	1246	2
3150000	850000	1252	10
3150000	850000	1258	5
3150000	850000	1264	10
3150000	850000	1270	10
3150000	850000	1276	6
3150000	850000	1282	8
3150000	850000	1288	9
3150000	850000	1294	6
3150000	850000	1300	3
3150000	850000	1306	7
3150000	850000	1312	3
3150000	850000	1318	7
3150000	850000	1324	1
3150000	850000	1330	7
3150000	850000	1336	3
3150000	850000	1342	5
3150000	850000	1348	3
3150000	850000	1354	3
3150000	850000	1360	4
3150000	850000	1366	5
3150000	850000	1372	2
3150000	850000	1378	8
3150000	850000	1385	1
3150000	850000	1391	1
3150000	850000	1397	1
3150000	850000	1403	5
3150000	850000	1409	4
3150000	850000	1415	4
3150000	850000	1422	4
3150000	850000	1428	5
3150000	850000	1434	4
3150000	850000	1440	2
3150000	850000	1447	6
3150000	850000	1453	3
3150000	850000	1459	6
3150000	850000	1465	6
3150000	850000	1472	3
3150000	850000	1478	4
3150000	850000	1484	4
3150000	850000	1490	6
3150000	850000	1496	7
3150000	850000	1502	3
3150000	850000	1508	4
3150000	850000	1514	2
3150000	850000	1520	5
3150000	850000	1526	2
3150000	850000	1532	3
3150000	850000	1538	7
3150000	850000	1544	3
3150000	850000	1550	8
3150000	850000	1557	7
3150000	850000	1563	7
3150000	850000	1570	5
3150000	850000	1576	4
3150000	850000	1582	1
3150000	850000	1589	4
3150000	850000	1595	7
3150000	850000	1601	4
3150000	850000	1607	2
3150000	850000	1613	3
3150000	850000	1619	1
3150000	850000	1631	2
3150000	850000	1637	4
3150000	850000	1647	1
3150000	850000	1672	1
3150000	850000	1678	1
3150000	850000	1693	2
3150000	850000	1703	1
3150000	850000	1716	1
3150000	850000	1740	1
3150000	850000	1765	1
3150000	850000	1788	1
3150000	850000	1814	2
3150000	850000	1831	1
3150000	850000	1848	1
3150000	850000	1873	2
3150000	850000	1880	2
3150000	850000	1897	5
3150000	850000	1930	1
3150000	850000	1987	1
3150000	850000	2085	1
3150000	850000	2178	1
3150000	850000	2324	1
3150000	850000	2516	1
3150000	850000	509	8
3150000	850000	515	1
3150000	850000	521	11
3150000	850000	527	7
3150000	850000	533	11
3150000	850000	539	7
3150000	850000	545	11
3150000	850000	551	4
3150000	850000	557	13
3150000	850000	563	11
3150000	850000	569	12
3150000	850000	575	10
3150000	850000	581	17
3150000	850000	587	16
3150000	850000	593	10
3150000	850000	599	13
3150000	850000	605	11
3150000	850000	611	11
3150000	850000	617	12
3150000	850000	623	14
3150000	850000	629	12
3150000	850000	635	11
3150000	850000	641	20
3150000	850000	647	8
3150000	850000	653	18
3150000	850000	659	10
3150000	850000	665	13
3150000	850000	671	16
3150000	850000	677	6
3150000	850000	683	17
3150000	850000	689	19
3150000	850000	695	16
3150000	850000	701	18
3150000	850000	707	14
3150000	850000	713	19
3150000	850000	719	16
3150000	850000	725	15
3150000	850000	731	16
3150000	850000	737	10
3150000	850000	743	17
3150000	850000	749	13
3150000	850000	755	12
3150000	850000	761	9
3150000	850000	767	15
3150000	850000	773	16
3150000	850000	779	11
3150000	850000	785	8
3150000	850000	791	16
3150000	850000	797	8
3150000	850000	803	13
3150000	850000	809	17
3150000	850000	815	13
3150000	850000	821	13
3150000	850000	827	13
3150000	850000	833	9
3150000	850000	839	7
3150000	850000	845	15
3150000	850000	851	19
3150000	850000	857	15
3150000	850000	863	10
3150000	850000	869	17
3150000	850000	875	9
3150000	850000	881	13
3150000	850000	887	11
3150000	850000	893	11
3150000	850000	899	9
3150000	850000	905	11
3150000	850000	911	15
3150000	850000	917	14
3150000	850000	923	18
3150000	850000	929	12
3150000	850000	935	13
3150000	850000	941	5
3150000	850000	947	14
3150000	850000	953	14
3150000	850000	959	12
3150000	850000	965	15
3150000	850000	971	6
3150000	850000	977	7
3150000	850000	983	7
3150000	850000	989	6
3150000	850000	995	10
3150000	950000	405	2
3150000	950000	411	19
3150000	950000	417	32
3150000	950000	423	45
3150000	950000	429	37
3150000	950000	435	37
3150000	950000	441	63
3150000	950000	447	46
3150000	950000	453	63
3150000	950000	459	58
3150000	950000	465	65
3150000	950000	471	49
3150000	950000	477	54
3150000	950000	483	49
3150000	950000	489	78
3150000	950000	495	66
3150000	950000	501	57
3150000	950000	507	70
3150000	950000	513	46
3150000	950000	519	40
3150000	950000	525	32
3150000	950000	531	43
3150000	950000	537	34
3150000	950000	543	43
3150000	950000	549	29
3150000	950000	555	35
3150000	950000	561	30
3150000	950000	567	22
3150000	950000	573	24
3150000	950000	579	21
3150000	950000	585	33
3150000	950000	591	30
3150000	950000	597	33
3150000	950000	603	24
3150000	950000	609	19
3150000	950000	615	22
3150000	950000	621	18
3150000	950000	627	20
3150000	950000	633	23
3150000	950000	639	25
3150000	950000	645	25
3150000	950000	651	19
3150000	950000	657	9
3150000	950000	663	16
3150000	950000	669	16
3150000	950000	675	6
3150000	950000	681	7
3150000	950000	687	13
3150000	950000	693	9
3150000	950000	699	4
3150000	950000	705	2
3150000	950000	711	3
3150000	950000	717	5
3150000	950000	723	9
3150000	950000	729	6
3150000	950000	736	5
3150000	950000	742	5
3150000	950000	748	1
3150000	950000	754	2
3150000	950000	760	3
3150000	950000	766	1
3150000	950000	776	1
3150000	950000	782	2
3150000	950000	793	1
3150000	950000	804	1
3150000	950000	821	1
3150000	950000	857	1
3250000	1050000	456	12
3250000	1050000	462	9
3250000	1050000	468	12
3250000	1050000	474	21
3250000	1050000	480	71
3250000	1050000	486	57
3250000	1050000	492	47
3250000	1050000	498	49
3250000	1050000	504	57
3250000	1050000	510	48
3250000	1050000	516	58
3250000	1050000	522	100
3250000	1050000	528	94
3250000	1050000	534	98
3250000	1050000	540	94
3250000	1050000	546	57
3250000	1050000	552	61
3250000	1050000	558	59
3250000	1050000	564	53
3250000	1050000	570	47
3250000	1050000	576	54
3250000	1050000	582	36
3250000	1050000	588	32
3250000	1050000	594	32
3250000	1050000	600	25
3250000	1050000	606	33
3250000	1050000	612	24
3250000	1050000	618	26
3250000	1050000	624	26
3250000	1050000	630	29
3250000	1050000	636	22
3250000	1050000	642	20
3250000	1050000	648	20
3250000	1050000	654	15
3250000	1050000	660	31
3250000	1050000	666	15
3250000	1050000	672	20
3250000	1050000	678	15
3250000	1050000	684	14
3250000	1050000	690	15
3250000	1050000	696	13
3250000	1050000	702	13
3250000	1050000	708	8
3250000	1050000	714	7
3250000	1050000	720	4
3250000	1050000	726	8
3250000	1050000	732	2
3250000	1050000	738	1
3250000	1050000	744	4
3250000	1050000	750	1
3250000	1050000	757	2
3250000	1050000	764	2
3250000	1050000	771	1
3250000	1050000	783	2
3250000	1050000	793	1
3250000	650000	1001	3
3250000	650000	1008	2
3250000	650000	1014	2
3250000	650000	1021	3
3250000	650000	1030	2
3250000	650000	1037	1
3250000	650000	1045	1
3250000	650000	1062	1
3250000	650000	1076	1
3250000	650000	1085	1
3250000	650000	1100	1
3250000	650000	1131	1
3250000	650000	1137	1
3250000	650000	1154	1
3250000	650000	1172	1
3250000	650000	646	4
3250000	650000	652	5
3250000	650000	658	13
3250000	650000	664	14
3250000	650000	670	8
3250000	650000	676	15
3250000	650000	682	6
3250000	650000	688	8
3250000	650000	694	7
3250000	650000	700	7
3250000	650000	706	7
3250000	650000	712	10
3250000	650000	718	6
3250000	650000	724	11
3250000	650000	730	9
3250000	650000	736	9
3250000	650000	742	7
3250000	650000	748	13
3250000	650000	754	8
3250000	650000	760	10
3250000	650000	766	8
3250000	650000	772	9
3250000	650000	778	9
3250000	650000	784	16
3250000	650000	790	9
3250000	650000	796	15
3250000	650000	802	12
3250000	650000	808	15
3250000	650000	814	16
3250000	650000	820	18
3250000	650000	826	15
3250000	650000	832	17
3250000	650000	838	13
3250000	650000	844	11
3250000	650000	850	8
3250000	650000	856	7
3250000	650000	862	14
3250000	650000	868	13
3250000	650000	874	14
3250000	650000	880	2
3250000	650000	886	7
3250000	650000	892	4
3250000	650000	898	3
3250000	650000	904	2
3250000	650000	910	4
3250000	650000	916	5
3250000	650000	922	5
3250000	650000	928	3
3250000	650000	935	1
3250000	650000	941	1
3250000	650000	949	1
3250000	650000	956	1
3250000	650000	962	1
3250000	650000	968	2
3250000	650000	974	1
3250000	650000	980	2
3250000	650000	990	3
3250000	650000	998	2
3250000	750000	1004	8
3250000	750000	1010	18
3250000	750000	1016	9
3250000	750000	1022	16
3250000	750000	1028	8
3250000	750000	1034	11
3250000	750000	1040	14
3250000	750000	1046	12
3250000	750000	1052	6
3250000	750000	1058	17
3250000	750000	1064	8
3250000	750000	1070	6
3250000	750000	1076	6
3250000	750000	1082	9
3250000	750000	1088	6
3250000	750000	1094	5
3250000	750000	1100	5
3250000	750000	1106	4
3250000	750000	1112	10
3250000	750000	1118	7
3250000	750000	1124	2
3250000	750000	1130	4
3250000	750000	1136	3
3250000	750000	1142	3
3250000	750000	1148	4
3250000	750000	1155	5
3250000	750000	1161	3
3250000	750000	1167	2
3250000	750000	1173	3
3250000	750000	1179	4
3250000	750000	1186	5
3250000	750000	1193	3
3250000	750000	1202	2
3250000	750000	1210	3
3250000	750000	1216	6
3250000	750000	1223	2
3250000	750000	1230	3
3250000	750000	1236	9
3250000	750000	1243	4
3250000	750000	1250	3
3250000	750000	1258	2
3250000	750000	1265	3
3250000	750000	1272	5
3250000	750000	1281	4
3250000	750000	1287	2
3250000	750000	1293	1
3250000	750000	1299	2
3250000	750000	1305	3
3250000	750000	1314	3
3250000	750000	1320	7
3250000	750000	1326	5
3250000	750000	1332	2
3250000	750000	1341	4
3250000	750000	1348	3
3250000	750000	1354	5
3250000	750000	1361	3
3250000	750000	1368	3
3250000	750000	1376	3
3250000	750000	1385	1
3250000	750000	1395	2
3250000	750000	1402	2
3250000	750000	1410	4
3250000	750000	1420	1
3250000	750000	1430	1
3250000	750000	1439	1
3250000	750000	1447	4
3250000	750000	1459	2
3250000	750000	1468	2
3250000	750000	1476	3
3250000	750000	1484	1
3250000	750000	1495	4
3250000	750000	1505	2
3250000	750000	1515	2
3250000	750000	1526	1
3250000	750000	1534	3
3250000	750000	1544	1
3250000	750000	1558	1
3250000	750000	1569	1
3250000	750000	1582	2
3250000	750000	1596	2
3250000	750000	1606	1
3250000	750000	1614	2
3250000	750000	1627	2
3250000	750000	1641	1
3250000	750000	1660	1
3250000	750000	1675	1
3250000	750000	1697	1
3250000	750000	1710	1
3250000	750000	1736	1
3250000	750000	1748	2
3250000	750000	1774	1
3250000	750000	1803	1
3250000	750000	1836	1
3250000	750000	1919	3
3250000	750000	2002	1
3250000	750000	2203	1
3250000	750000	613	1
3250000	750000	620	6
3250000	750000	626	4
3250000	750000	632	6
3250000	750000	638	9
3250000	750000	644	12
3250000	750000	650	19
3250000	750000	656	26
3250000	750000	662	17
3250000	750000	668	22
3250000	750000	674	31
3250000	750000	680	22
3250000	750000	686	33
3250000	750000	692	20
3250000	750000	698	32
3250000	750000	704	24
3250000	750000	710	32
3250000	750000	716	11
3250000	750000	722	21
3250000	750000	728	19
3250000	750000	734	16
3250000	750000	740	19
3250000	750000	746	13
3250000	750000	752	17
3250000	750000	758	16
3250000	750000	764	12
3250000	750000	770	17
3250000	750000	776	32
3250000	750000	782	16
3250000	750000	788	25
3250000	750000	794	19
3250000	750000	800	41
3250000	750000	806	29
3250000	750000	812	26
3250000	750000	818	35
3250000	750000	824	55
3250000	750000	830	34
3250000	750000	836	29
3250000	750000	842	50
3250000	750000	848	35
3250000	750000	854	32
3250000	750000	860	28
3250000	750000	866	26
3250000	750000	872	29
3250000	750000	878	28
3250000	750000	884	23
3250000	750000	890	17
3250000	750000	896	22
3250000	750000	902	18
3250000	750000	908	15
3250000	750000	914	11
3250000	750000	920	14
3250000	750000	926	23
3250000	750000	932	17
3250000	750000	938	17
3250000	750000	944	14
3250000	750000	950	13
3250000	750000	956	11
3250000	750000	962	16
3250000	750000	968	14
3250000	750000	974	14
3250000	750000	980	19
3250000	750000	986	8
3250000	750000	992	14
3250000	750000	998	17
3250000	850000	1004	15
3250000	850000	1010	14
3250000	850000	1016	22
3250000	850000	1022	13
3250000	850000	1028	16
3250000	850000	1034	16
3250000	850000	1040	7
3250000	850000	1046	10
3250000	850000	1052	30
3250000	850000	1058	11
3250000	850000	1064	18
3250000	850000	1070	12
3250000	850000	1076	15
3250000	850000	1082	18
3250000	850000	1088	9
3250000	850000	1094	17
3250000	850000	1100	10
3250000	850000	1106	9
3250000	850000	1112	9
3250000	850000	1118	20
3250000	850000	1124	13
3250000	850000	1130	20
3250000	850000	1136	13
3250000	850000	1142	4
3250000	850000	1148	12
3250000	850000	1154	6
3250000	850000	1160	11
3250000	850000	1166	12
3250000	850000	1172	11
3250000	850000	1178	12
3250000	850000	1184	18
3250000	850000	1190	7
3250000	850000	1196	4
3250000	850000	1202	10
3250000	850000	1208	11
3250000	850000	1214	17
3250000	850000	1220	15
3250000	850000	1226	9
3250000	850000	1232	11
3250000	850000	1238	11
3250000	850000	1244	11
3250000	850000	1250	11
3250000	850000	1256	15
3250000	850000	1262	6
3250000	850000	1268	8
3250000	850000	1274	14
3250000	850000	1280	11
3250000	850000	1286	6
3250000	850000	1292	7
3250000	850000	1298	11
3250000	850000	1304	8
3250000	850000	1310	8
3250000	850000	1316	5
3250000	850000	1322	9
3250000	850000	1328	3
3250000	850000	1334	10
3250000	850000	1340	7
3250000	850000	1346	3
3250000	850000	1353	4
3250000	850000	1359	2
3250000	850000	1365	8
3250000	850000	1371	6
3250000	850000	1377	1
3250000	850000	1383	4
3250000	850000	1389	3
3250000	850000	1396	5
3250000	850000	1402	3
3250000	850000	1408	6
3250000	850000	1414	3
3250000	850000	1420	2
3250000	850000	1426	6
3250000	850000	1432	2
3250000	850000	1438	4
3250000	850000	1444	5
3250000	850000	1450	2
3250000	850000	1456	2
3250000	850000	1462	3
3250000	850000	1468	10
3250000	850000	1474	2
3250000	850000	1480	1
3250000	850000	1486	3
3250000	850000	1492	6
3250000	850000	1498	7
3250000	850000	1504	5
3250000	850000	1511	2
3250000	850000	1519	4
3250000	850000	1525	5
3250000	850000	1531	4
3250000	850000	1539	6
3250000	850000	1547	2
3250000	850000	1553	3
3250000	850000	1559	4
3250000	850000	1566	3
3250000	850000	1572	3
3250000	850000	1578	2
3250000	850000	1584	5
3250000	850000	1590	5
3250000	850000	1596	4
3250000	850000	1602	2
3250000	850000	1608	3
3250000	850000	1615	3
3250000	850000	1622	5
3250000	850000	1629	2
3250000	850000	1635	2
3250000	850000	1642	2
3250000	850000	1648	4
3250000	850000	1654	1
3250000	850000	1661	1
3250000	850000	1668	2
3250000	850000	1674	2
3250000	850000	1680	3
3250000	850000	1687	2
3250000	850000	1693	6
3250000	850000	1699	2
3250000	850000	1705	4
3250000	850000	1711	3
3250000	850000	1717	1
3250000	850000	1723	2
3250000	850000	1730	2
3250000	850000	1736	1
3250000	850000	1747	3
3250000	850000	1753	1
3250000	850000	1759	5
3250000	850000	1766	3
3250000	850000	1772	2
3250000	850000	1779	4
3250000	850000	1785	2
3250000	850000	1792	10
3250000	850000	1798	4
3250000	850000	1804	1
3250000	850000	1812	1
3250000	850000	1818	8
3250000	850000	1826	3
3250000	850000	1833	2
3250000	850000	1839	2
3250000	850000	1845	4
3250000	850000	1852	3
3250000	850000	1858	1
3250000	850000	1865	2
3250000	850000	1872	4
3250000	850000	1880	1
3250000	850000	1886	3
3250000	850000	1894	1
3250000	850000	1901	1
3250000	850000	1908	1
3250000	850000	1914	4
3250000	850000	1920	1
3250000	850000	1926	1
3250000	850000	1935	2
3250000	850000	1943	2
3250000	850000	1949	4
3250000	850000	1959	4
3250000	850000	1967	1
3250000	850000	1975	1
3250000	850000	1987	2
3250000	850000	1998	1
3250000	850000	2005	1
3250000	850000	2016	2
3250000	850000	2023	3
3250000	850000	2033	2
3250000	850000	2045	3
3250000	850000	2056	1
3250000	850000	2066	2
3250000	850000	2081	2
3250000	850000	2088	1
3250000	850000	2102	2
3250000	850000	2113	1
3250000	850000	2124	2
3250000	850000	2134	1
3250000	850000	2149	1
3250000	850000	2164	1
3250000	850000	2173	1
3250000	850000	2181	1
3250000	850000	2193	1
3250000	850000	2200	1
3250000	850000	2217	2
3250000	850000	2233	1
3250000	850000	2246	1
3250000	850000	2263	2
3250000	850000	2279	2
3250000	850000	2303	2
3250000	850000	2314	1
3250000	850000	2335	1
3250000	850000	2350	1
3250000	850000	2373	1
3250000	850000	2396	1
3250000	850000	2419	1
3250000	850000	2431	2
3250000	850000	2455	1
3250000	850000	2493	1
3250000	850000	2525	1
3250000	850000	2611	1
3250000	850000	649	1
3250000	850000	676	1
3250000	850000	690	1
3250000	850000	706	1
3250000	850000	715	1
3250000	850000	729	1
3250000	850000	750	1
3250000	850000	760	4
3250000	850000	769	2
3250000	850000	775	2
3250000	850000	781	3
3250000	850000	787	4
3250000	850000	793	9
3250000	850000	799	13
3250000	850000	805	13
3250000	850000	811	14
3250000	850000	817	9
3250000	850000	823	4
3250000	850000	829	19
3250000	850000	835	11
3250000	850000	841	18
3250000	850000	847	5
3250000	850000	853	15
3250000	850000	859	28
3250000	850000	865	23
3250000	850000	871	36
3250000	850000	877	15
3250000	850000	883	15
3250000	850000	889	19
3250000	850000	895	19
3250000	850000	901	15
3250000	850000	907	21
3250000	850000	913	21
3250000	850000	919	29
3250000	850000	925	21
3250000	850000	931	27
3250000	850000	937	28
3250000	850000	943	24
3250000	850000	949	23
3250000	850000	955	23
3250000	850000	961	22
3250000	850000	967	16
3250000	850000	973	22
3250000	850000	979	16
3250000	850000	985	12
3250000	850000	991	18
3250000	850000	997	17
3250000	950000	1003	6
3250000	950000	1009	10
3250000	950000	1015	7
3250000	950000	1021	10
3250000	950000	1027	4
3250000	950000	1033	6
3250000	950000	1039	5
3250000	950000	1045	5
3250000	950000	1051	10
3250000	950000	1057	3
3250000	950000	1063	3
3250000	950000	1069	6
3250000	950000	1075	2
3250000	950000	1081	11
3250000	950000	1087	5
3250000	950000	1093	7
3250000	950000	1101	5
3250000	950000	1107	1
3250000	950000	1113	3
3250000	950000	1119	5
3250000	950000	1125	4
3250000	950000	1131	1
3250000	950000	1137	3
3250000	950000	1143	1
3250000	950000	1149	1
3250000	950000	1156	2
3250000	950000	1162	2
3250000	950000	1168	2
3250000	950000	1174	4
3250000	950000	1180	5
3250000	950000	1186	5
3250000	950000	1192	7
3250000	950000	1198	2
3250000	950000	1204	6
3250000	950000	1211	3
3250000	950000	1217	3
3250000	950000	1223	3
3250000	950000	1229	2
3250000	950000	1236	3
3250000	950000	1242	4
3250000	950000	1248	4
3250000	950000	1254	4
3250000	950000	1260	4
3250000	950000	1267	1
3250000	950000	1274	2
3250000	950000	1280	3
3250000	950000	1287	4
3250000	950000	1293	5
3250000	950000	1299	6
3250000	950000	1307	3
3250000	950000	1314	2
3250000	950000	1320	5
3250000	950000	1326	3
3250000	950000	1332	6
3250000	950000	1338	3
3250000	950000	1346	4
3250000	950000	1352	1
3250000	950000	1360	5
3250000	950000	1366	4
3250000	950000	1372	1
3250000	950000	1378	1
3250000	950000	1386	2
3250000	950000	1397	1
3250000	950000	1405	2
3250000	950000	1414	3
3250000	950000	1421	2
3250000	950000	1428	2
3250000	950000	1438	2
3250000	950000	1446	1
3250000	950000	1454	2
3250000	950000	1464	2
3250000	950000	1472	1
3250000	950000	1481	1
3250000	950000	1490	2
3250000	950000	1499	3
3250000	950000	1510	1
3250000	950000	1524	1
3250000	950000	1537	5
3250000	950000	1555	1
3250000	950000	512	1
3250000	950000	518	7
3250000	950000	524	15
3250000	950000	530	8
3250000	950000	536	4
3250000	950000	542	11
3250000	950000	548	8
3250000	950000	554	10
3250000	950000	560	9
3250000	950000	566	14
3250000	950000	572	16
3250000	950000	578	20
3250000	950000	584	18
3250000	950000	590	21
3250000	950000	596	18
3250000	950000	602	30
3250000	950000	608	21
3250000	950000	614	28
3250000	950000	620	18
3250000	950000	626	31
3250000	950000	632	16
3250000	950000	638	30
3250000	950000	644	26
3250000	950000	650	33
3250000	950000	656	29
3250000	950000	662	29
3250000	950000	668	31
3250000	950000	674	39
3250000	950000	680	31
3250000	950000	686	38
3250000	950000	692	24
3250000	950000	698	19
3250000	950000	704	23
3250000	950000	710	17
3250000	950000	716	16
3250000	950000	722	19
3250000	950000	728	15
3250000	950000	734	15
3250000	950000	740	14
3250000	950000	746	16
3250000	950000	752	7
3250000	950000	758	15
3250000	950000	764	18
3250000	950000	770	16
3250000	950000	776	10
3250000	950000	782	16
3250000	950000	788	21
3250000	950000	794	12
3250000	950000	800	16
3250000	950000	806	15
3250000	950000	812	5
3250000	950000	818	19
3250000	950000	824	17
3250000	950000	830	19
3250000	950000	836	14
3250000	950000	842	10
3250000	950000	848	5
3250000	950000	854	10
3250000	950000	860	17
3250000	950000	866	23
3250000	950000	872	12
3250000	950000	878	14
3250000	950000	884	16
3250000	950000	890	19
3250000	950000	896	15
3250000	950000	902	18
3250000	950000	908	8
3250000	950000	914	8
3250000	950000	920	7
3250000	950000	926	15
3250000	950000	932	14
3250000	950000	938	10
3250000	950000	944	15
3250000	950000	950	14
3250000	950000	956	13
3250000	950000	962	22
3250000	950000	968	22
3250000	950000	974	17
3250000	950000	980	12
3250000	950000	986	13
3250000	950000	992	12
3250000	950000	998	9
3350000	1050000	608	10
3350000	1050000	614	11
3350000	1050000	620	29
3350000	1050000	626	45
3350000	1050000	632	56
3350000	1050000	638	77
3350000	1050000	644	92
3350000	1050000	650	90
3350000	1050000	656	110
3350000	1050000	662	92
3350000	1050000	668	104
3350000	1050000	674	97
3350000	1050000	680	99
3350000	1050000	686	78
3350000	1050000	692	73
3350000	1050000	698	69
3350000	1050000	704	57
3350000	1050000	710	47
3350000	1050000	716	57
3350000	1050000	722	45
3350000	1050000	728	35
3350000	1050000	734	32
3350000	1050000	740	24
3350000	1050000	746	30
3350000	1050000	752	20
3350000	1050000	758	25
3350000	1050000	764	14
3350000	1050000	770	22
3350000	1050000	776	23
3350000	1050000	782	18
3350000	1050000	788	17
3350000	1050000	794	13
3350000	1050000	800	8
3350000	1050000	806	10
3350000	1050000	812	14
3350000	1050000	818	6
3350000	1050000	824	12
3350000	1050000	830	9
3350000	1050000	836	1
3350000	1050000	842	3
3350000	1050000	848	2
3350000	1050000	855	1
3350000	1050000	863	1
3350000	1050000	879	1
3350000	650000	1001	18
3350000	650000	1007	20
3350000	650000	1013	18
3350000	650000	1019	24
3350000	650000	1025	30
3350000	650000	1031	14
3350000	650000	1037	22
3350000	650000	1043	24
3350000	650000	1049	14
3350000	650000	1055	10
3350000	650000	1061	15
3350000	650000	1067	14
3350000	650000	1073	7
3350000	650000	1079	9
3350000	650000	1085	5
3350000	650000	1091	4
3350000	650000	1097	9
3350000	650000	1103	4
3350000	650000	1109	6
3350000	650000	1115	3
3350000	650000	1121	3
3350000	650000	1127	4
3350000	650000	1134	2
3350000	650000	1141	1
3350000	650000	1148	2
3350000	650000	1155	2
3350000	650000	1163	1
3350000	650000	1170	3
3350000	650000	1176	4
3350000	650000	1184	2
3350000	650000	1190	3
3350000	650000	1196	1
3350000	650000	1205	2
3350000	650000	1214	1
3350000	650000	1223	3
3350000	650000	1231	1
3350000	650000	1240	1
3350000	650000	1289	1
3350000	650000	910	1
3350000	650000	923	2
3350000	650000	936	1
3350000	650000	942	2
3350000	650000	948	2
3350000	650000	954	6
3350000	650000	960	10
3350000	650000	966	9
3350000	650000	972	15
3350000	650000	978	13
3350000	650000	984	15
3350000	650000	990	25
3350000	650000	996	21
3350000	750000	1002	29
3350000	750000	1008	33
3350000	750000	1014	31
3350000	750000	1020	18
3350000	750000	1026	32
3350000	750000	1032	19
3350000	750000	1038	20
3350000	750000	1044	25
3350000	750000	1050	24
3350000	750000	1056	28
3350000	750000	1062	23
3350000	750000	1068	13
3350000	750000	1074	16
3350000	750000	1080	27
3350000	750000	1086	28
3350000	750000	1092	16
3350000	750000	1098	9
3350000	750000	1104	15
3350000	750000	1110	10
3350000	750000	1116	9
3350000	750000	1122	8
3350000	750000	1128	10
3350000	750000	1134	2
3350000	750000	1140	8
3350000	750000	1146	3
3350000	750000	1152	12
3350000	750000	1158	5
3350000	750000	1164	6
3350000	750000	1170	5
3350000	750000	1176	3
3350000	750000	1182	9
3350000	750000	1188	5
3350000	750000	1194	4
3350000	750000	1201	3
3350000	750000	1207	2
3350000	750000	1214	3
3350000	750000	1221	1
3350000	750000	1228	5
3350000	750000	1234	2
3350000	750000	1241	1
3350000	750000	1248	2
3350000	750000	1254	6
3350000	750000	1262	1
3350000	750000	1268	1
3350000	750000	1275	3
3350000	750000	1282	2
3350000	750000	1292	1
3350000	750000	1305	1
3350000	750000	1313	2
3350000	750000	1321	1
3350000	750000	1331	2
3350000	750000	1342	2
3350000	750000	1349	1
3350000	750000	1369	1
3350000	750000	1386	2
3350000	750000	1409	1
3350000	750000	1425	1
3350000	750000	1438	1
3350000	750000	1451	1
3350000	750000	1467	1
3350000	750000	1482	1
3350000	750000	1513	1
3350000	750000	1525	1
3350000	750000	1544	1
3350000	750000	1565	2
3350000	750000	1588	1
3350000	750000	1614	1
3350000	750000	1632	1
3350000	750000	1653	1
3350000	750000	1717	1
3350000	750000	1736	1
3350000	750000	539	5
3350000	750000	545	1
3350000	750000	551	14
3350000	750000	557	5
3350000	750000	563	6
3350000	750000	569	12
3350000	750000	575	11
3350000	750000	581	18
3350000	750000	587	20
3350000	750000	593	25
3350000	750000	599	49
3350000	750000	605	19
3350000	750000	611	31
3350000	750000	617	18
3350000	750000	623	23
3350000	750000	629	11
3350000	750000	635	9
3350000	750000	641	11
3350000	750000	647	10
3350000	750000	653	12
3350000	750000	659	21
3350000	750000	665	6
3350000	750000	671	8
3350000	750000	677	11
3350000	750000	683	5
3350000	750000	689	7
3350000	750000	695	11
3350000	750000	701	6
3350000	750000	707	7
3350000	750000	713	4
3350000	750000	719	9
3350000	750000	725	16
3350000	750000	731	6
3350000	750000	738	4
3350000	750000	744	16
3350000	750000	750	11
3350000	750000	756	7
3350000	750000	762	11
3350000	750000	768	12
3350000	750000	774	9
3350000	750000	780	12
3350000	750000	786	15
3350000	750000	792	15
3350000	750000	798	17
3350000	750000	804	13
3350000	750000	810	10
3350000	750000	816	10
3350000	750000	822	12
3350000	750000	828	12
3350000	750000	834	16
3350000	750000	840	10
3350000	750000	846	11
3350000	750000	852	10
3350000	750000	858	11
3350000	750000	864	7
3350000	750000	870	16
3350000	750000	876	12
3350000	750000	882	11
3350000	750000	888	10
3350000	750000	894	15
3350000	750000	900	17
3350000	750000	906	15
3350000	750000	912	16
3350000	750000	918	16
3350000	750000	924	18
3350000	750000	930	16
3350000	750000	936	20
3350000	750000	942	16
3350000	750000	948	26
3350000	750000	954	21
3350000	750000	960	20
3350000	750000	966	27
3350000	750000	972	33
3350000	750000	978	27
3350000	750000	984	18
3350000	750000	990	33
3350000	750000	996	41
3350000	850000	1002	5
3350000	850000	1009	5
3350000	850000	1015	9
3350000	850000	1021	6
3350000	850000	1027	8
3350000	850000	1033	10
3350000	850000	1039	9
3350000	850000	1045	3
3350000	850000	1052	4
3350000	850000	1058	2
3350000	850000	1064	4
3350000	850000	1070	4
3350000	850000	1076	5
3350000	850000	1083	5
3350000	850000	1089	8
3350000	850000	1095	1
3350000	850000	1101	1
3350000	850000	1107	6
3350000	850000	1113	4
3350000	850000	1119	4
3350000	850000	1125	1
3350000	850000	1132	1
3350000	850000	1139	1
3350000	850000	1147	2
3350000	850000	1153	1
3350000	850000	1159	5
3350000	850000	1166	2
3350000	850000	1172	3
3350000	850000	1178	1
3350000	850000	1188	1
3350000	850000	1197	1
3350000	850000	1204	2
3350000	850000	1210	3
3350000	850000	1220	3
3350000	850000	1226	3
3350000	850000	1234	2
3350000	850000	1240	1
3350000	850000	1246	1
3350000	850000	1257	1
3350000	850000	1264	1
3350000	850000	1270	1
3350000	850000	1277	2
3350000	850000	1284	2
3350000	850000	1293	3
3350000	850000	1300	3
3350000	850000	1306	1
3350000	850000	1313	1
3350000	850000	1322	5
3350000	850000	1329	1
3350000	850000	1335	2
3350000	850000	1346	2
3350000	850000	1352	1
3350000	850000	1359	3
3350000	850000	1365	2
3350000	850000	1371	3
3350000	850000	1380	2
3350000	850000	1390	1
3350000	850000	1397	1
3350000	850000	1406	4
3350000	850000	1414	2
3350000	850000	1422	3
3350000	850000	1428	2
3350000	850000	1434	6
3350000	850000	1440	5
3350000	850000	1446	2
3350000	850000	1452	2
3350000	850000	1459	2
3350000	850000	1468	2
3350000	850000	1474	2
3350000	850000	1481	3
3350000	850000	1488	1
3350000	850000	1494	3
3350000	850000	1504	2
3350000	850000	1512	1
3350000	850000	1518	1
3350000	850000	1524	2
3350000	850000	1534	2
3350000	850000	1542	1
3350000	850000	1550	1
3350000	850000	1563	4
3350000	850000	1570	1
3350000	850000	1579	1
3350000	850000	1586	1
3350000	850000	1601	1
3350000	850000	1611	1
3350000	850000	1620	1
3350000	850000	1636	1
3350000	850000	1649	2
3350000	850000	1675	2
3350000	850000	1714	2
3350000	850000	497	2
3350000	850000	503	12
3350000	850000	509	27
3350000	850000	515	32
3350000	850000	521	33
3350000	850000	527	51
3350000	850000	533	50
3350000	850000	539	37
3350000	850000	545	35
3350000	850000	551	32
3350000	850000	557	30
3350000	850000	563	38
3350000	850000	569	25
3350000	850000	575	31
3350000	850000	581	22
3350000	850000	587	29
3350000	850000	593	24
3350000	850000	599	23
3350000	850000	605	25
3350000	850000	611	28
3350000	850000	617	18
3350000	850000	623	16
3350000	850000	629	17
3350000	850000	635	18
3350000	850000	641	17
3350000	850000	647	24
3350000	850000	653	21
3350000	850000	659	25
3350000	850000	665	18
3350000	850000	671	15
3350000	850000	677	25
3350000	850000	683	15
3350000	850000	689	6
3350000	850000	695	17
3350000	850000	701	12
3350000	850000	707	12
3350000	850000	713	11
3350000	850000	719	18
3350000	850000	725	16
3350000	850000	731	8
3350000	850000	737	8
3350000	850000	743	18
3350000	850000	749	14
3350000	850000	755	10
3350000	850000	761	12
3350000	850000	767	17
3350000	850000	773	11
3350000	850000	779	14
3350000	850000	785	14
3350000	850000	791	23
3350000	850000	797	16
3350000	850000	803	12
3350000	850000	809	12
3350000	850000	815	8
3350000	850000	821	12
3350000	850000	827	6
3350000	850000	833	12
3350000	850000	839	20
3350000	850000	845	9
3350000	850000	851	17
3350000	850000	857	13
3350000	850000	863	9
3350000	850000	869	12
3350000	850000	875	3
3350000	850000	881	8
3350000	850000	887	13
3350000	850000	893	4
3350000	850000	899	10
3350000	850000	905	11
3350000	850000	911	6
3350000	850000	917	10
3350000	850000	923	15
3350000	850000	929	12
3350000	850000	935	10
3350000	850000	941	7
3350000	850000	947	11
3350000	850000	953	9
3350000	850000	959	10
3350000	850000	965	13
3350000	850000	971	11
3350000	850000	977	7
3350000	850000	983	10
3350000	850000	989	7
3350000	850000	995	9
3350000	950000	1001	3
3350000	950000	1007	12
3350000	950000	1013	5
3350000	950000	1019	10
3350000	950000	1025	5
3350000	950000	1031	4
3350000	950000	1037	11
3350000	950000	1043	7
3350000	950000	1049	6
3350000	950000	1055	6
3350000	950000	1061	4
3350000	950000	1067	6
3350000	950000	1073	9
3350000	950000	1079	10
3350000	950000	1085	11
3350000	950000	1091	11
3350000	950000	1097	10
3350000	950000	1103	11
3350000	950000	1109	7
3350000	950000	1115	13
3350000	950000	1121	9
3350000	950000	1127	5
3350000	950000	1133	15
3350000	950000	1139	8
3350000	950000	1145	11
3350000	950000	1151	9
3350000	950000	1157	5
3350000	950000	1163	9
3350000	950000	1169	12
3350000	950000	1175	10
3350000	950000	1181	15
3350000	950000	1187	11
3350000	950000	1193	7
3350000	950000	1199	12
3350000	950000	1205	10
3350000	950000	1211	12
3350000	950000	1217	9
3350000	950000	1223	14
3350000	950000	1229	10
3350000	950000	1235	9
3350000	950000	1241	18
3350000	950000	1247	3
3350000	950000	1253	8
3350000	950000	1259	9
3350000	950000	1265	14
3350000	950000	1271	17
3350000	950000	1277	14
3350000	950000	1283	15
3350000	950000	1289	11
3350000	950000	1295	10
3350000	950000	1301	12
3350000	950000	1307	13
3350000	950000	1313	4
3350000	950000	1319	1
3350000	950000	1325	3
3350000	950000	1331	3
3350000	950000	1337	1
3350000	950000	1343	4
3350000	950000	1349	4
3350000	950000	1357	1
3350000	950000	1364	1
3350000	950000	1374	2
3350000	950000	1383	5
3350000	950000	1394	1
3350000	950000	1409	2
3350000	950000	1415	2
3350000	950000	1423	1
3350000	950000	1433	2
3350000	950000	1450	1
3350000	950000	1474	3
3350000	950000	1509	1
3350000	950000	1555	1
3350000	950000	604	5
3350000	950000	610	1
3350000	950000	616	7
3350000	950000	622	11
3350000	950000	628	9
3350000	950000	634	13
3350000	950000	640	27
3350000	950000	646	31
3350000	950000	652	38
3350000	950000	658	50
3350000	950000	664	44
3350000	950000	670	50
3350000	950000	676	65
3350000	950000	682	48
3350000	950000	688	48
3350000	950000	694	32
3350000	950000	700	59
3350000	950000	706	43
3350000	950000	712	29
3350000	950000	718	29
3350000	950000	724	26
3350000	950000	730	24
3350000	950000	736	17
3350000	950000	742	20
3350000	950000	748	14
3350000	950000	754	11
3350000	950000	760	9
3350000	950000	766	11
3350000	950000	772	8
3350000	950000	778	8
3350000	950000	784	11
3350000	950000	790	14
3350000	950000	796	9
3350000	950000	802	15
3350000	950000	808	10
3350000	950000	814	11
3350000	950000	820	9
3350000	950000	826	10
3350000	950000	832	6
3350000	950000	838	13
3350000	950000	844	10
3350000	950000	850	6
3350000	950000	856	8
3350000	950000	862	7
3350000	950000	868	8
3350000	950000	874	9
3350000	950000	880	8
3350000	950000	886	9
3350000	950000	892	10
3350000	950000	898	10
3350000	950000	904	7
3350000	950000	911	2
3350000	950000	917	5
3350000	950000	923	5
3350000	950000	929	6
3350000	950000	935	6
3350000	950000	941	9
3350000	950000	947	6
3350000	950000	953	6
3350000	950000	959	6
3350000	950000	965	6
3350000	950000	971	8
3350000	950000	977	9
3350000	950000	983	12
3350000	950000	989	6
3350000	950000	995	6
3450000	1050000	1001	6
3450000	1050000	1007	5
3450000	1050000	1013	2
3450000	1050000	1019	2
3450000	1050000	1026	7
3450000	1050000	1032	6
3450000	1050000	1038	4
3450000	1050000	1044	2
3450000	1050000	1051	4
3450000	1050000	1058	2
3450000	1050000	1065	5
3450000	1050000	1071	2
3450000	1050000	1077	2
3450000	1050000	1084	1
3450000	1050000	1090	5
3450000	1050000	1096	2
3450000	1050000	1102	5
3450000	1050000	1108	1
3450000	1050000	1114	1
3450000	1050000	1120	5
3450000	1050000	1126	3
3450000	1050000	1135	1
3450000	1050000	1143	1
3450000	1050000	1158	2
3450000	1050000	1171	1
3450000	1050000	1192	3
3450000	1050000	1218	1
3450000	1050000	1236	1
3450000	1050000	1256	1
3450000	1050000	1273	1
3450000	1050000	1296	1
3450000	1050000	657	3
3450000	1050000	663	10
3450000	1050000	669	7
3450000	1050000	675	5
3450000	1050000	681	9
3450000	1050000	687	20
3450000	1050000	693	17
3450000	1050000	699	22
3450000	1050000	705	25
3450000	1050000	711	29
3450000	1050000	717	30
3450000	1050000	723	44
3450000	1050000	729	36
3450000	1050000	735	45
3450000	1050000	741	43
3450000	1050000	747	45
3450000	1050000	753	61
3450000	1050000	759	70
3450000	1050000	765	54
3450000	1050000	771	59
3450000	1050000	777	46
3450000	1050000	783	60
3450000	1050000	789	60
3450000	1050000	795	35
3450000	1050000	801	50
3450000	1050000	807	49
3450000	1050000	813	44
3450000	1050000	819	53
3450000	1050000	825	52
3450000	1050000	831	42
3450000	1050000	837	38
3450000	1050000	843	41
3450000	1050000	849	29
3450000	1050000	855	39
3450000	1050000	861	22
3450000	1050000	867	27
3450000	1050000	873	32
3450000	1050000	879	26
3450000	1050000	885	17
3450000	1050000	891	22
3450000	1050000	897	10
3450000	1050000	903	21
3450000	1050000	909	15
3450000	1050000	915	16
3450000	1050000	921	7
3450000	1050000	927	14
3450000	1050000	933	20
3450000	1050000	939	13
3450000	1050000	945	18
3450000	1050000	951	13
3450000	1050000	957	14
3450000	1050000	963	12
3450000	1050000	969	3
3450000	1050000	975	8
3450000	1050000	981	6
3450000	1050000	987	7
3450000	1050000	993	5
3450000	1050000	999	5
3450000	650000	1017	3
3450000	650000	1044	1
3450000	650000	1075	1
3450000	650000	1159	1
3450000	650000	914	1
3450000	650000	921	2
3450000	650000	930	1
3450000	650000	936	3
3450000	650000	943	1
3450000	650000	951	1
3450000	650000	958	2
3450000	650000	966	3
3450000	650000	976	2
3450000	650000	984	1
3450000	650000	996	1
3450000	750000	1003	7
3450000	750000	1010	4
3450000	750000	1016	10
3450000	750000	1022	3
3450000	750000	1028	4
3450000	750000	1035	5
3450000	750000	1041	2
3450000	750000	1047	2
3450000	750000	1053	3
3450000	750000	1060	1
3450000	750000	1068	4
3450000	750000	1075	2
3450000	750000	1086	1
3450000	750000	1098	1
3450000	750000	1110	2
3450000	750000	1121	1
3450000	750000	1136	1
3450000	750000	1151	1
3450000	750000	1170	1
3450000	750000	1211	1
3450000	750000	747	1
3450000	750000	755	1
3450000	750000	762	1
3450000	750000	769	1
3450000	750000	775	3
3450000	750000	781	1
3450000	750000	789	2
3450000	750000	795	3
3450000	750000	803	6
3450000	750000	810	3
3450000	750000	818	1
3450000	750000	825	3
3450000	750000	832	2
3450000	750000	839	4
3450000	750000	845	6
3450000	750000	851	15
3450000	750000	857	6
3450000	750000	863	3
3450000	750000	869	12
3450000	750000	875	10
3450000	750000	881	19
3450000	750000	887	8
3450000	750000	893	15
3450000	750000	899	12
3450000	750000	905	10
3450000	750000	911	8
3450000	750000	917	11
3450000	750000	923	13
3450000	750000	929	7
3450000	750000	935	12
3450000	750000	941	13
3450000	750000	947	9
3450000	750000	953	15
3450000	750000	959	11
3450000	750000	965	10
3450000	750000	971	9
3450000	750000	977	9
3450000	750000	983	11
3450000	750000	989	7
3450000	750000	995	8
3450000	850000	1001	26
3450000	850000	1007	15
3450000	850000	1013	29
3450000	850000	1019	41
3450000	850000	1025	31
3450000	850000	1031	40
3450000	850000	1037	28
3450000	850000	1043	26
3450000	850000	1049	20
3450000	850000	1055	14
3450000	850000	1061	24
3450000	850000	1067	15
3450000	850000	1073	17
3450000	850000	1079	16
3450000	850000	1085	11
3450000	850000	1091	12
3450000	850000	1097	10
3450000	850000	1103	7
3450000	850000	1109	2
3450000	850000	1115	7
3450000	850000	1121	6
3450000	850000	1127	5
3450000	850000	1133	5
3450000	850000	1140	5
3450000	850000	1146	4
3450000	850000	1154	2
3450000	850000	1160	2
3450000	850000	1168	1
3450000	850000	1177	1
3450000	850000	1186	1
3450000	850000	1200	2
3450000	850000	1211	2
3450000	850000	1219	1
3450000	850000	1226	1
3450000	850000	1232	1
3450000	850000	1240	3
3450000	850000	1248	1
3450000	850000	1262	3
3450000	850000	1274	1
3450000	850000	1317	1
3450000	850000	807	1
3450000	850000	813	1
3450000	850000	819	2
3450000	850000	826	3
3450000	850000	832	1
3450000	850000	838	7
3450000	850000	844	12
3450000	850000	851	8
3450000	850000	857	9
3450000	850000	863	5
3450000	850000	869	9
3450000	850000	875	10
3450000	850000	881	6
3450000	850000	887	7
3450000	850000	893	9
3450000	850000	899	9
3450000	850000	905	19
3450000	850000	911	15
3450000	850000	917	13
3450000	850000	923	12
3450000	850000	929	12
3450000	850000	935	11
3450000	850000	941	9
3450000	850000	947	9
3450000	850000	953	20
3450000	850000	959	24
3450000	850000	965	32
3450000	850000	971	26
3450000	850000	977	17
3450000	850000	983	28
3450000	850000	989	23
3450000	850000	995	23
3450000	950000	1001	9
3450000	950000	1007	8
3450000	950000	1013	9
3450000	950000	1019	7
3450000	950000	1025	9
3450000	950000	1031	14
3450000	950000	1037	5
3450000	950000	1043	6
3450000	950000	1049	9
3450000	950000	1055	17
3450000	950000	1061	17
3450000	950000	1067	11
3450000	950000	1073	16
3450000	950000	1079	10
3450000	950000	1085	14
3450000	950000	1091	6
3450000	950000	1097	11
3450000	950000	1103	8
3450000	950000	1109	6
3450000	950000	1115	10
3450000	950000	1121	8
3450000	950000	1127	14
3450000	950000	1133	9
3450000	950000	1139	6
3450000	950000	1145	14
3450000	950000	1151	15
3450000	950000	1157	19
3450000	950000	1163	11
3450000	950000	1169	11
3450000	950000	1175	14
3450000	950000	1181	10
3450000	950000	1187	11
3450000	950000	1193	9
3450000	950000	1199	10
3450000	950000	1205	12
3450000	950000	1211	12
3450000	950000	1217	7
3450000	950000	1223	7
3450000	950000	1229	6
3450000	950000	1235	7
3450000	950000	1241	11
3450000	950000	1247	8
3450000	950000	1253	5
3450000	950000	1259	6
3450000	950000	1265	1
3450000	950000	1271	1
3450000	950000	1277	5
3450000	950000	1283	4
3450000	950000	1293	1
3450000	950000	1340	1
3450000	950000	1388	1
3450000	950000	640	2
3450000	950000	646	3
3450000	950000	652	6
3450000	950000	658	14
3450000	950000	664	13
3450000	950000	670	38
3450000	950000	676	32
3450000	950000	682	33
3450000	950000	688	39
3450000	950000	694	30
3450000	950000	700	61
3450000	950000	706	58
3450000	950000	712	48
3450000	950000	718	40
3450000	950000	724	43
3450000	950000	730	32
3450000	950000	736	23
3450000	950000	742	25
3450000	950000	748	23
3450000	950000	754	19
3450000	950000	760	13
3450000	950000	766	18
3450000	950000	772	11
3450000	950000	778	9
3450000	950000	784	13
3450000	950000	790	12
3450000	950000	796	10
3450000	950000	802	12
3450000	950000	808	16
3450000	950000	814	15
3450000	950000	820	15
3450000	950000	826	18
3450000	950000	832	11
3450000	950000	838	12
3450000	950000	844	11
3450000	950000	850	15
3450000	950000	856	6
3450000	950000	862	12
3450000	950000	868	15
3450000	950000	874	14
3450000	950000	880	12
3450000	950000	886	13
3450000	950000	892	19
3450000	950000	898	13
3450000	950000	904	21
3450000	950000	910	19
3450000	950000	916	9
3450000	950000	922	19
3450000	950000	928	8
3450000	950000	934	10
3450000	950000	940	15
3450000	950000	946	18
3450000	950000	952	8
3450000	950000	958	11
3450000	950000	964	12
3450000	950000	970	8
3450000	950000	976	11
3450000	950000	982	15
3450000	950000	988	12
3450000	950000	994	14




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



