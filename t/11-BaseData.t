#!/usr/bin/perl -w

#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };
use Data::Dumper;
use Path::Class;

use Test::Lib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

#use Test::More tests => 5;
use Test::Most;

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;
use Biodiverse::TestHelpers qw /:basedata/;

#  this needs work to loop around more of the expected variations
my @setup = (
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lat     => [1, 0],
            is_lon     => [0, 1],
        },
        expected => 'fail',
        message  => 'lat/lon out of bounds',
    },
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lat     => [1, 0],
        },
        expected => 'fail',
        message  => 'lat out of bounds',
    },
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lon     => [1, 0],
        },
        expected => 'fail',
        message  => 'lon out of bounds',
    },
    {
        args => {
            CELL_SIZES => [100000, 100000],
        },
        expected => 'pass',
    },
    {
        args => {
            CELL_SIZES => [100, 100],
        },
        expected => 'pass',
    },
);

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @test_subs = grep {$_ =~ 'main::test_'} $obj->functions();


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

    foreach my $sub (@test_subs) {
        no strict 'refs';
        $sub->();
    }
    
    done_testing;
    return 0;
}


sub test_remapped_labels_when_stringified_and_numeric {
    my $label_numeric1 = 10;
    my $label_numeric2 = 20;
    my $label_text1    = 'barry the wonder dog';
    my $label_text2    = 'barry the non-wonder dog';

    my $bd1 = Biodiverse::BaseData->new (CELL_SIZES => [2, 2]);
    $bd1->add_element (label => $label_numeric1, group => '5:5');
    $bd1->add_element (label => $label_numeric1, group => '55:1150');
    my $bd2 = $bd1->clone;

    ok ($bd1->labels_are_numeric, 'Labels are numeric');
    ok ($bd2->labels_are_numeric, 'Labels are numeric, cloned');

    my $remap = Biodiverse::ElementProperties->new ();
    $remap->add_element (element => $label_numeric1);
    my $remap_hash = {REMAP => $label_text1};
    $remap->add_lists (element => $label_numeric1, PROPERTIES => $remap_hash);

    $bd1->rename_labels (remap => $remap);
    ok (!$bd1->labels_are_numeric, 'Labels are no longer numeric after rename_labels');

    #  now we try with a single rename
    $bd2->rename_label (label => $label_numeric1, new_name => $label_text1);
    ok (!$bd2->labels_are_numeric, 'Labels are no longer numeric after rename_label');

    my $bd3 = Biodiverse::BaseData->new (CELL_SIZES => [2, 2]);
    $bd3->add_element (label => $label_text1,  group => '5:5');
    $bd3->add_element (label => $label_text2, group => '55:1150');
    my $bd4 = $bd3->clone;
    my $bd5 = $bd3->clone;

    ok (!$bd3->labels_are_numeric, 'Text labels are not numeric');

    my $remap_text2num = Biodiverse::ElementProperties->new ();
    $remap_text2num->add_element (element => $label_text1);
    $remap_text2num->add_lists   (element => $label_text1, PROPERTIES => {REMAP => $label_numeric1});

    $bd3->rename_labels (remap => $remap_text2num);
    ok (!$bd1->labels_are_numeric, 'Text labels still not numeric after one label renamed');

    $remap_text2num->add_element (element => $label_text2);
    $remap_text2num->add_lists   (element => $label_text2, PROPERTIES => {REMAP => $label_numeric2});

    $bd3->rename_labels (remap => $remap_text2num);
    ok ($bd3->labels_are_numeric, 'Text labels are now numeric, done one at a time');

    $bd4->rename_labels (remap => $remap_text2num);
    ok ($bd4->labels_are_numeric, 'Text labels are now numeric, all done at once');

    #  now we try with all text labels mapped to one numeric label
    $remap_text2num->add_lists   (element => $label_text2, PROPERTIES => {REMAP => $label_numeric1});
    $bd5->rename_labels (remap => $remap_text2num);
    ok ($bd5->labels_are_numeric, 'Text labels are now numeric, all remapped into one number');
}


#  Try a variety of cell and index sizes.
#  Should check the error messages to ensure we get the expected error.
#  Should also test the index behaves as expected,
#  but it is also exercised in the spatial conditions tests.
sub test_spatial_index_build_exceptions {
    my $label_name = 'blah';  #  only need one of these

    my $bd = Biodiverse::BaseData->new (CELL_SIZES => [10, 100]);
    $bd->add_element (label => $label_name, group => '5:150');
    $bd->add_element (label => $label_name, group => '55:1150');
    
    lives_ok (
        sub {$bd->build_spatial_index (resolutions => [10, 100])},
        'build index with resolution same as bd',
    );
    lives_ok (
        sub {$bd->build_spatial_index (resolutions => [20, 400])},
        'build index with resolution double bd',
    );
    lives_ok (
        sub {$bd->build_spatial_index (resolutions => [20, 100])},
        'build index with resolution double/same as bd',
    );
    
    dies_ok (
        sub {$bd->build_spatial_index (resolutions => [2, 10])},
        "won't build index with resolution smaller than bd",
    );
    dies_ok (
        sub {$bd->build_spatial_index (resolutions => [2, 0])},
        "won't build index with resolution smaller than bd, one zero",
    );
    dies_ok (
        sub {$bd->build_spatial_index (resolutions => [0, 100])},
        "won't build index with resolution smaller than bd, one zero",
    );
    dies_ok (
        sub {$bd->build_spatial_index (resolutions => [20, 10])},
        "won't build index with one axis resolution smaller than bd",
    );

    #  now check a basedata with a text axis    
    $bd = Biodiverse::BaseData->new (CELL_SIZES => [-1, 2, 2]);
    $bd->add_element (label => $label_name, group => 'x:5:151');
    $bd->add_element (label => $label_name, group => 'y:55:1151');
    
    lives_ok (
        sub {$bd->build_spatial_index (resolutions => [-1, 2, 2])},
        'build index with resolution same as bd (text axis)',
    );
    lives_ok (
        sub {$bd->build_spatial_index (resolutions => [-1, 4, 4])},
        'build index with resolution double bd (text axis)',
    );
    lives_ok (
        sub {$bd->build_spatial_index (resolutions => [-1, 4, 2])},
        'build index with resolution double/same as bd (text axis)',
    );
    
    dies_ok (
        sub {$bd->build_spatial_index (resolutions => [2, 10])},
        "won't build index with fewer axes than basedata (text axis)",
    );
    dies_ok (
        sub {$bd->build_spatial_index (resolutions => [-1, 2, 0])},
        "won't build index with resolution smaller than bd, one zero (text axis)",
    );
    dies_ok (
        sub {$bd->build_spatial_index (resolutions => [0, 0, 100])},
        "won't build index with resolution smaller than bd, one zero (text axis)",
    );
    dies_ok (
        sub {$bd->build_spatial_index (resolutions => [-1, 1, 10])},
        "won't build index with text axis resolution smaller than bd",
    );    
}

sub test_spatial_index_density {
    my $bd1 = Biodiverse::BaseData->new(CELL_SIZES => [1, 1]);    
    my $join_char = $bd1->get_param('JOIN_CHAR');
    #  completely filled;
    foreach my $x (0 .. 49) {
        foreach my $y (0 .. 49) {
            my $gp = join $join_char, $x+0.5, $y+0.5;
            $bd1->add_element (group => $gp, label => 'a');
        }
    }

    my ($index, $density);

    $index = $bd1->build_spatial_index(resolutions => [1, 1]);
    $density = $index->get_item_density_across_all_poss_index_elements;
    is ($density, 1, 'index density is 1');

    $index = $bd1->build_spatial_index(resolutions => [2, 2]);
    $density = $index->get_item_density_across_all_poss_index_elements;
    is ($density, 4, 'index density is 4');

    #  dirty, hackish cheat to get a text axis
    $bd1->set_param(CELL_SIZES => [1, -1]);
    $bd1->get_groups_ref->set_param(CELL_SIZES => [1, -1]);
    $index = $bd1->build_spatial_index(resolutions => [2, 0]);
    $density = $index->get_item_density_across_all_poss_index_elements;
    is ($density, 100, 'index density is 100, one text axis');    

    my $bd2 = Biodiverse::BaseData->new(CELL_SIZES => [1, 1]);    
    $join_char = $bd2->get_param('JOIN_CHAR');
    #  half filled;
    foreach my $x (0 .. 49) {
        next if $x % 2 == 0;
        foreach my $y (0 .. 49) {
            my $gp = join $join_char, $x+0.5, $y+0.5;
            $bd2->add_element (group => $gp, label => 'a');
        }
    }

    $index = $bd2->build_spatial_index(resolutions => [2, 2]);
    $density = $index->get_item_density_across_all_poss_index_elements;
    is ($density, 2, 'index density is 2 when only half the groups exist');
}

sub test_binarise_sample_counts {
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [300000, 300000]);

    $bd->binarise_sample_counts;
    
    foreach my $type (qw /label group/) {
        my $list_method = 'get_' . $type . 's';
        my $sc_method   = 'get_' . $type . '_sample_count';
        my $v_method    = $type eq 'label' ? 'get_range' : 'get_richness';
        #  successful binarise when richness or range equal sample count for a group or label
        subtest "${type}s are binarised" => sub {
            foreach my $element ($bd->$list_method) {
                is (
                    $bd->$sc_method(element => $element),
                    $bd->$v_method(element => $element),
                    $element,
                );
            }
        };
    }
    
}

sub test_labels_in_groups {
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);

    subtest 'No overlap between groups_with_label and groups_without_label' => sub {
        foreach my $label (sort $bd->get_labels) {
            my $groups_with_label    = $bd->get_groups_with_label_as_hash (label => $label);
            my $groups_without_label = $bd->get_groups_without_label_as_hash (label => $label);
            my $overlap = grep {exists $groups_with_label->{$_}} sort keys %$groups_without_label;
            is ($overlap, 0, "No overlap for $label");

            my $check1 = grep 
                {$bd->exists_label_in_group(label => $label, group => $_)}
                keys %$groups_without_label;
            is ($check1, 0, "No overlap for label using exists, $label");
            my $check2 = grep 
                {$bd->exists_label_in_group(label => $label, group => $_)}
                keys %$groups_with_label;
            is ($check2, scalar keys %$groups_with_label, "groups_with_label counts match using exists, $label");
            #my @checkers = map
            #    {$bd->exists_label_in_group(label => $label, group => $_)}
            #    keys %$groups_with_label;
            #say join ' ', sort @checkers;
        }        
    };
    
}

sub test_import {
    foreach my $this_run (@setup ) {
        my $expected = $this_run->{expected} || 'pass';  
        my $args     = $this_run->{args};

        my $string = Data::Dumper::Dumper $args;
        $string =~ s/[\s\n\r]//g;
        $string =~ s/^\$VAR1=//;
        $string =~ s/;$//;

        my $message  = $this_run->{message} || $string;

        my $bd = eval {
            get_basedata_object ( %$args, );
        };
        my $error = $EVAL_ERROR;

        if ($expected eq 'fail') {
            ok (defined $error, "Trapped error: $message");
        }
        else {
            ok (defined $bd,    "Imported: $message");
        }
    }
}


#  need to change the name
sub test_import_small {

    my %bd_args = (
        NAME => 'test include exclude',
        CELL_SIZES => [1,1,1],
    );

    my $tmp_file = write_data_to_temp_file (get_import_data_small());
    my $fname = $tmp_file->filename;

    my $e;

    #  vanilla import
    my $bd_vanilla = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd_vanilla->import_data(
            input_files   => [$fname],
            group_columns => [3, 4, 5],
            label_columns => [1, 2],
        );
    };
    $e = $EVAL_ERROR;
    ok (!$e, 'import vanilla with no exceptions raised');

    #  cell sizes don't match groups
    my $bd_x1 = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd_vanilla->import_data(
            input_files   => [$fname],
            group_columns => [3, 4],
            label_columns => [1, 2],
        );
        1;
    };
    $e = $EVAL_ERROR;
    ok ($e, q{Exception when group and cell_size col counts don't match});
    
    #  cell sizes don't match origins
    my $bd_x2 = eval {
        Biodiverse::BaseData->new (
            %bd_args,
            CELL_ORIGINS  => [0, 0, 0, 0, 0],
        );
    };
    $e = $EVAL_ERROR;
    ok ($e, q{Exception when cell_size and cell_origin col counts don't match});
    
    eval {
        $bd_vanilla->import_data(
            input_files   => [$fname],
            group_columns => [3, 4, 5],
            label_columns => [1, 2],
            cell_origins  => [0, 0, 0, 0, 0],
        );
        1;
    };
    $e = $EVAL_ERROR;
    ok (!$e, 'cell_origins argument ignored for second import');
    
    #  now check we can import zeros
    
    my $bd_disallow_zeroes = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd_disallow_zeroes->import_data(
            input_files     => [$fname],
            group_columns   => [3, 4, 5],
            label_columns   => [1, 2],
            sample_count_columns => [-1],
        );
        1;
    };
    $e = $EVAL_ERROR;
    ok (!$e, q{No exception when sample_count_columns specified (disallow empty groups)});

    #  need to check what was imported
    is ($bd_disallow_zeroes->get_group_count, 0, "0 groups when sample_count_cols specified");
    is ($bd_disallow_zeroes->get_label_count, 0, "0 labels when sample_count_cols specified");

    my $bd_allow_zeroes = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd_allow_zeroes->import_data(
            input_files     => [$fname],
            group_columns   => [3, 4, 5],
            label_columns   => [1, 2],
            sample_count_columns => [-1],
            allow_empty_groups   => 1,
        );
        1;
    };
    $e = $EVAL_ERROR;
    ok (!$e, q{No exception when sample_count_columns specified (allow empty groups)});

    #  need to check what was imported
    is ($bd_allow_zeroes->get_group_count, 3, "3 groups when sample_count_cols specified");
    is ($bd_allow_zeroes->get_label_count, 0, "0 labels when sample_count_cols specified");

    #  now add zeroes to an existing basedata
    eval {
        $bd_disallow_zeroes->import_data(
            input_files     => [$fname],
            group_columns   => [3, 4, 5],
            label_columns   => [1, 2],
            sample_count_columns => [-1],
            allow_empty_groups   => 1,
        );
        1;
    };
    $e = $EVAL_ERROR;
    ok (!$e, q{No exception when sample_count_columns specified (allow empty groups)});

    #  need to check what was imported
    is ($bd_disallow_zeroes->get_group_count, 3, "3 groups when sample_count_cols specified");
    is ($bd_disallow_zeroes->get_label_count, 0, "0 labels when sample_count_cols specified");

    
    #  using inclusions columns
    my @incl_cols_data = (
        [1, [6]],
        [2, [8]],
        [3, [6,8]],
        [3, [6,8,10]],
    );

    foreach my $params (@incl_cols_data) {
        my $expected_count = $params->[0];
        my $incl_cols      = $params->[1];

        my $bd = Biodiverse::BaseData->new (%bd_args);
        eval {
            $bd->import_data(
                input_files     => [$fname],
                group_columns   => [3, 4, 5],
                label_columns   => [1, 2],
                include_columns => $incl_cols,
            );
            1;
        };
        $e = $EVAL_ERROR;
        ok (!$e, q{No exception when include_columns specified});

        my $cols_text = join q{,}, @$incl_cols;
        #  need to check what was imported
        is ($bd->get_group_count, $expected_count, "$expected_count groups for include cols $cols_text");
        is ($bd->get_label_count, $expected_count, "$expected_count labels for include cols $cols_text");

        next if scalar @$incl_cols > 1 || $expected_count != 1;

        my $groups = $bd->get_groups;
        is ($groups->[0], '1.5:1.5:1.5', "Only remaining group is '1.5:1.5:1.5'");
        
        my $labels = $bd->get_labels;
        is ($labels->[0], 'g1:sp1', "Only remaining label is 'g1:sp1'");
    }

    #  using exclusions columns
    my @excl_cols_data = (
        [2, [7]],
        [1, [9]],
        [3, [11]],
        [0, [7,9]],
        [0, [7,9,11]],
        [1, [9,11]],
    );

    foreach my $params (@excl_cols_data) {
        my $expected_count = $params->[0];
        my $excl_cols      = $params->[1];

        my $bd = Biodiverse::BaseData->new (%bd_args);
        eval {
            $bd->import_data(
                input_files     => [$fname],
                group_columns   => [3, 4, 5],
                label_columns   => [1, 2],
                exclude_columns => $excl_cols,
            );
            1;
        };
        $e = $EVAL_ERROR;
        ok (!$e, q{No exception when exclude_columns specified});

        my $cols_text = join q{,}, @$excl_cols;
        #  need to check what was imported
        is ($bd->get_group_count, $expected_count, "$expected_count groups for exclude cols $cols_text");
        is ($bd->get_label_count, $expected_count, "$expected_count labels for exclude cols $cols_text");

        next if $excl_cols->[0] != 9;

        my $groups = $bd->get_groups;
        is ($groups->[0], '1.5:1.5:1.5', "Only remaining group is '1.5:1.5:1.5'");

        my $labels = $bd->get_labels;
        is ($labels->[0], 'g1:sp1', "Only remaining label is 'g1:sp1'");
    }

    #  now check some interactions between exclude and include cols
    #  exclude trumps include
    my @incl_excl_cols_data = (
        [0, [6], [7]],  #  expected, incl, excl
        [0, [6], [1]],
        [2, [8], [11]],
        [0, [8], [9]],
        [1, [6], [9]],
    );

    foreach my $params (@incl_excl_cols_data) {
        my $expected_count = $params->[0];
        my $incl_cols      = $params->[1];
        my $excl_cols      = $params->[2];

        my $bd = Biodiverse::BaseData->new (%bd_args);
        eval {
            $bd->import_data(
                input_files     => [$fname],
                group_columns   => [3, 4, 5],
                label_columns   => [1, 2],
                exclude_columns => $excl_cols,
                include_columns => $incl_cols,
            );
            1;
        };
        $e = $EVAL_ERROR;
        ok (!$e, q{No exception when include and exclude_columns specified});

        my $cols_text = join (q{,}, @$incl_cols) . '&' . join (q{,}, @$excl_cols);
        #  need to check what was imported
        is ($bd->get_group_count, $expected_count, "$expected_count groups for incl/excl cols $cols_text");
        is ($bd->get_label_count, $expected_count, "$expected_count labels for incl/excl cols $cols_text");

    }
    
}



sub test_import_null_labels {

    my %bd_args = (
        NAME => 'test null axes',
        CELL_SIZES => [1,1,1],
    );

    my $tmp_file = write_data_to_temp_file (get_import_data_null_label());
    my $fname = $tmp_file->filename;

    my $e;

    #  vanilla import
    my $bd = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd->import_data(
            input_files   => [$fname],
            group_columns => [3, 4, 5],
            label_columns => [1],
        );
    };
    $e = $EVAL_ERROR;
    ok (!$e, 'import vanilla with no exceptions raised');
    
    ok ($bd->exists_label (element => q{}), q{Null label exists});

}


sub test_import_cr_line_endings {
    my %bd_args = (
        NAME => 'test include exclude',
        CELL_SIZES => [1,1],
    );

    my $e;

    my $data = get_import_data_small();
    my $data_cr = $data;
    $data_cr =~ s/\R/\r/g;

    #my $d1 = ($data =~ /\R/sg);
    #my $dc = ($data_cr =~ /\n/sg);
    isnt ($data_cr =~ /\n/sg, 'stripped all newlines from input file data');

    my $tmp_file1 = write_data_to_temp_file ($data);
    my $fname1 = $tmp_file1->filename;

    my $tmp_file_cr = write_data_to_temp_file ($data_cr);
    my $fname_cr = $tmp_file_cr->filename;
    
    #  get the original - should add some labels with special characters
    my $bd = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd->import_data(
            input_files   => [$fname1],
            group_columns => [3, 4],
            label_columns => [1, 2],
        );
    };
    $e = $EVAL_ERROR;
    ok (!$e, 'import \n file endings with no exceptions raised');
    
    #  now the cr version
    my $bd_cr = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd_cr->import_data(
            input_files   => [$fname_cr],
            group_columns => [3, 4],
            label_columns => [1, 2],
        );
    };
    $e = $EVAL_ERROR;
    ok (!$e, 'import \r line endings with no exceptions raised');
    
    is ($bd_cr->get_group_count, $bd->get_group_count, 'group counts match');
    is ($bd_cr->get_label_count, $bd->get_label_count, 'label counts match');
    
}

#  can we reimport delimited text files after exporting and get the same answer
sub test_roundtrip_delimited_text {
    my %bd_args = (
        NAME => 'test include exclude',
        CELL_SIZES => [1,1],
    );

    my $tmp_file = write_data_to_temp_file (get_import_data_small());
    my $fname = $tmp_file->filename;

    my $e;

    #  get the original - should add some labels with special characters
    my $bd = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd->import_data(
            input_files   => [$fname],
            group_columns => [3, 4],
            label_columns => [1, 2],
        );
    };
    $e = $EVAL_ERROR;
    ok (!$e, 'import vanilla with no exceptions raised');
    
    $bd->add_element (group => '1.5:1.5', label => 'bazungalah:smith', count => 25);
    
    my $lb = $bd->get_labels_ref;
    my $gp = $bd->get_groups_ref;

    #  export should return file names?  Or should we cache them on the object?

    my $format = 'export_table_delimited_text';
    my @out_options = (
        {symmetric => 0, one_value_per_line => 1},
        {symmetric => 1, one_value_per_line => 1},
        #{symmetric => 0, one_value_per_line => 0},  #  cannot import this format
        {symmetric => 1, one_value_per_line => 0},
    );
    my @in_options = (
        {label_columns   => [3], group_columns => [1,2], sample_count_columns => [4]},
        {label_columns   => [3], group_columns => [1,2], sample_count_columns => [4]},
        #{label_columns   => [3], group_columns => [1,2], sample_count_columns => [4]},
        {label_start_col => 3,   group_columns => [1,2], data_in_matrix_form  =>  1, },
    );
    
    my $tmp_folder = File::Temp->newdir (TEMPLATE => 'biodiverseXXXX', TMPDIR => 1);

    my $i = 0;
    foreach my $out_options_hash (@out_options) {
        #local $Data::Dumper::Sortkeys = 1;
        #local $Data::Dumper::Purity   = 1;
        #local $Data::Dumper::Terse    = 1;
        #say Dumper $out_options_hash;

        #  need to use a better approach for the name, but at least it goes into a temp folder
        my $fname = $tmp_folder . '/' . 'delimtxt' . $i
                   . ($out_options_hash->{symmetric} ? '_symm' : '_asym')
                   . ($out_options_hash->{one_value_per_line} ? '_notmx' : '_mx')
                   . '.txt';  
        my $success = eval {
            $gp->export (
                format    => $format,
                file      => $fname,
                list      => 'SUBELEMENTS',
                %$out_options_hash,
            );
        };
        $e = $EVAL_ERROR;
        ok (!$e, "no exceptions exporting $format to $fname");
        diag $e if $e;

        #  Now we re-import and check we get the same numbers
        #  We do not yet guarantee the labels will be the same due to the csv quoting rules.
        my $new_bd = Biodiverse::BaseData->new (
            name         => $fname,
            CELL_SIZES   => $bd->get_param ('CELL_SIZES'),
            CELL_ORIGINS => $bd->get_param ('CELL_ORIGINS'),
        );
        my $in_options_hash = $in_options[$i];
        $success = eval {
            $new_bd->import_data (input_files => [$fname], %$in_options_hash);
        };
        $e = $EVAL_ERROR;
        ok (!$e, "no exceptions importing $fname");
        diag $e if $e;

        my @new_labels  = sort $new_bd->get_labels;
        my @orig_labels = sort $bd->get_labels;
        is_deeply (\@new_labels, \@orig_labels, "label lists match for $fname");
        
        my $new_lb = $new_bd->get_labels_ref;
        subtest "sample counts match for $fname" => sub {
            foreach my $label (sort $bd->get_labels) {
                my $new_list  = $new_lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                my $orig_list = $lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                is_deeply ($new_list, $orig_list, "SUBELEMENTS match for $label, $fname");
            }
        };

        $i++;
    }
    
}

#  can we reimport raster files after exporting and get the same answer
sub test_roundtrip_raster {
    my %bd_args = (
        NAME => 'test include exclude',
        CELL_SIZES => [1,1],
    );

    my $tmp_file = write_data_to_temp_file (get_import_data_small());
    my $fname = $tmp_file->filename;
    say "testing filename $fname";
    my $e;

    #  get the original - should add some labels with special characters
    my $bd = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd->import_data(
            input_files   => [$fname],
            group_columns => [3, 4],
            label_columns => [1, 2],
        );
    };
    $e = $EVAL_ERROR;
    ok (!$e, 'import vanilla with no exceptions raised');
    
    # not sure why this is used
    $bd->add_element (group => '1.5:1.5', label => 'bazungalah:smith', count => 25);
    
    my $lb = $bd->get_labels_ref;
    my $gp = $bd->get_groups_ref;

    #  export should return file names?  Or should we cache them on the object?

    #my $format = 'export_asciigrid';
    my @out_options = (
        { format => 'export_asciigrid'},
        { format => 'export_floatgrid'},
        { format => 'export_geotiff'},
    );

    # the raster data file won't specify the origin and cell size info, so pass as
    # parameters.
    # assume export was in format labels_as_bands = 0
    my @cell_sizes      = $bd->get_cell_sizes; # probably not set anywhere, and is using the default
    my @cell_origins    = $bd->get_cell_origins;    
    my %in_options_hash = (
        labels_as_bands   => 0,
        raster_origin_e   => $cell_origins[0],
        raster_origin_n   => $cell_origins[1], 
        raster_cellsize_e => $cell_sizes[0],
        raster_cellsize_n => $cell_sizes[1],
    );

    my $i = 0;
    foreach my $out_options_hash (@out_options) {
        my $format = $out_options_hash->{format};

        #local $Data::Dumper::Sortkeys = 1;
        #local $Data::Dumper::Purity   = 1;
        #local $Data::Dumper::Terse    = 1;
        #say Dumper $out_options_hash;

        #  need to use a better approach for the name
        my $tmp_dir = File::Temp->newdir (TEMPLATE => 'biodiverseXXXX', TMPDIR => 1);
        my $fname_base = $format; 
        my $suffix = '';
        my $fname = $tmp_dir . '/' . $fname_base . $suffix;  
        #my @exported_files;
        my $success = eval {
            $gp->export (
                format    => $format,
                file      => $fname,
                list      => 'SUBELEMENTS',
            );
        };
        $e = $EVAL_ERROR;
        ok (!$e, "no exceptions exporting $format to $fname");
        diag $e if $e;

        #  Now we re-import and check we get the same numbers
        my $new_bd = Biodiverse::BaseData->new (
            name         => $fname,
            CELL_SIZES   => $bd->get_param ('CELL_SIZES'),
            CELL_ORIGINS => $bd->get_param ('CELL_ORIGINS'),
        );
        
        use URI::Escape::XS qw/uri_unescape/;

        # each band was written to a separate file, load each in turn and add to
        # the basedata object
        # Should import the lot at once and then rename the labels to their unescaped form
        # albeit that would be just as contorted in the end.

        #  make sure we skip world and hdr files 
        my @exported_files = grep {$_ !~ /(?:(?:hdr)|w)$/} glob "$tmp_dir/*";

        foreach my $this_file (@exported_files) {
            # find label name from file name
            my $this_label = Path::Class::File->new($this_file)->basename();
            $this_label =~ s/.*${fname_base}_//; 
            $this_label =~ s/\....$//;  #  hackish way of clearing suffix
            $this_label = uri_unescape($this_label);
            note "got label $this_label\n";

            $success = eval {
                $new_bd->import_data_raster (
                    input_files => [$this_file],
                    %in_options_hash,
                    #labels_as_bands => 1,
                    given_label => $this_label,
                );
            };
            $e = $EVAL_ERROR;
            ok (!$e, "no exceptions importing $fname");
            diag $e if $e;
        }
        my @new_labels  = sort $new_bd->get_labels;
        my @orig_labels = sort $bd->get_labels;
        is_deeply (\@new_labels, \@orig_labels, "label lists match for $fname");

        my $new_lb = $new_bd->get_labels_ref;
        subtest "sample counts match for $format" => sub {
            foreach my $label (sort $bd->get_labels) {
                my $new_list  = $new_lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                my $orig_list = $lb->get_list_ref (list => 'SUBELEMENTS', element => $label);

                is_deeply ($new_list, $orig_list, "SUBELEMENTS match for $label, $format");
            }
        };

        $i++;
    }
    
}


sub test_raster_zero_cellsize {
    my %bd_args = (
        NAME => 'test include exclude',
        CELL_SIZES => [1,1],
    );

    my $tmp_file = write_data_to_temp_file (get_import_data_small());
    my $fname = $tmp_file->filename;
    say "testing filename $fname";
    my $e;

    my $bd = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd->import_data(
            input_files   => [$fname],
            group_columns => [3, 4],
            label_columns => [1, 2],
        );
    };
    $e = $EVAL_ERROR;
    ok (!$e, 'import vanilla with no exceptions raised');
    
    my $lb = $bd->get_labels_ref;
    my $gp = $bd->get_groups_ref;

    #my $format = 'export_asciigrid';
    my @out_options = (
        { format => 'export_asciigrid'},
        { format => 'export_floatgrid'},
        { format => 'export_geotiff'},
    );

    # the raster data file won't specify the origin and cell size info, so pass as
    # parameters.
    # assume export was in format labels_as_bands = 0
    my @cell_sizes      = $bd->get_cell_sizes; # probably not set anywhere, and is using the default
    my @cell_origins    = $bd->get_cell_origins;    
    my %in_options_hash = (
        labels_as_bands   => 0,
        raster_origin_e   => $cell_origins[0],
        raster_origin_n   => $cell_origins[1], 
        raster_cellsize_e => $cell_sizes[0],
        raster_cellsize_n => $cell_sizes[1],
    );

    my $i = 0;
    foreach my $out_options_hash (@out_options) {
        my $format = $out_options_hash->{format};

        #  need to use a better approach for the name
        my $tmp_dir = File::Temp->newdir (TEMPLATE => 'biodiverseXXXX', TMPDIR => 1);
        my $fname_base = $format; 
        my $suffix = '';
        my $fname = $tmp_dir . '/' . $fname_base . $suffix;  
        #my @exported_files;
        my $success = eval {
            $gp->export (
                format    => $format,
                file      => $fname,
                list      => 'SUBELEMENTS',
            );
        };
        $e = $EVAL_ERROR;
        ok (!$e, "no exceptions exporting $format to $fname");
        diag $e if $e;

        #  Now we re-import and check we get the same numbers
        my $new_bd = Biodiverse::BaseData->new (
            name         => $fname,
            CELL_SIZES   => [0, 0],
            CELL_ORIGINS => $bd->get_param ('CELL_ORIGINS'),
        );
        
        use URI::Escape::XS qw/uri_unescape/;

        # each band was written to a separate file, load each in turn and add to
        # the basedata object
        # Should import the lot at once and then rename the labels to their unescaped form
        # albeit that would be just as contorted in the end.

        #  make sure we skip world and hdr files 
        my @exported_files = grep {$_ !~ /(?:(?:hdr)|w)$/} glob "$tmp_dir/*";

        foreach my $this_file (@exported_files) {
            # find label name from file name
#say $this_file;
            my $this_label = Path::Class::File->new($this_file)->basename();
            $this_label =~ s/.*${fname_base}_//; 
            $this_label =~ s/\....$//;  #  hackish way of clearing suffix
            $this_label = uri_unescape($this_label);
            note "got label $this_label\n";

            $success = eval {
                $new_bd->import_data_raster (
                    input_files => [$this_file],
                    %in_options_hash,
                    #labels_as_bands => 1,
                    given_label => $this_label,
                );
            };
            $e = $EVAL_ERROR;
            ok (!$e, "no exceptions importing $fname");
            diag $e if $e;
        }
        my @new_labels  = sort $new_bd->get_labels;
        my @orig_labels = sort $bd->get_labels;
        is_deeply (\@new_labels, \@orig_labels, "label lists match for $fname");
        
        is_deeply ($new_bd->get_group_count, $bd->get_group_count, 'got expected group count');

        $i++;
    }
    
}

#can we reimport shapefiles after exporting and get the same answer
sub test_roundtrip_shapefile {
    my %bd_args = (
        NAME => 'test include exclude',
        CELL_SIZES => [1,1],
    );

    my $tmp_file = write_data_to_temp_file (get_import_data_small());
    my $fname = $tmp_file->filename;
    say "testing filename $fname";
    my $e;

    #  get the original - should add some labels with special characters
    my $bd = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd->import_data(
            input_files   => [$fname],
            group_columns => [3, 4],
            label_columns => [1, 2],
        );
    };
    $e = $EVAL_ERROR;
    ok (!$e, 'import vanilla with no exceptions raised');
    
    # add some labels so we have multiple entries in some cells 
    # with different labels
    $bd->add_element (group => '1.5:1.5', label => 'bazungalah:smith', count => 25);
    $bd->add_element (group => '1.5:1.5', label => 'repeat:1', count => 14);
    $bd->add_element (group => '1.5:1.5', label => 'repeat:2', count => 12);

    my $lb = $bd->get_labels_ref;
    my $gp = $bd->get_groups_ref;

    #  export should return file names?  Or should we cache them on the object?

    my $format = 'export_shapefile';
    my @out_options = ( { data => $bd, shapetype => 'point' } ); # not sure what parameters are needed for export

    # the raster data file won't specify the origin and cell size info, so pass as
    # parameters.
    # assume export was in format labels_as_bands = 0
    my @cell_sizes   = @{$bd->get_param('CELL_SIZES')}; # probably not set anywhere, and is using the default
    my @cell_origins = @{$bd->get_cell_origins};    
    my @in_options = (
        {
            group_field_names => [':shape_x', ':shape_y'],
            label_field_names => ['KEY'],
            sample_count_col_names => ['VALUE'],
        },
    );

    my $tmp_dir = File::Temp->newdir (TEMPLATE => 'biodiverseXXXX', TMPDIR => 1);

    my $i = 0;
    foreach my $out_options_hash (@out_options) {
        #local $Data::Dumper::Sortkeys = 1;
        #local $Data::Dumper::Purity   = 1;
        #local $Data::Dumper::Terse    = 1;
        #say Dumper $out_options_hash;

        #  need to use a better approach for the name
        my $fname_base = $tmp_dir . '/' . 'shapefile_' . $i; 
        my $suffix = ''; # leave off, .shp will be added (or similar)
        my $fname = $fname_base . $suffix;  
        my @exported_files;
        my $success = eval {
            $gp->export (
                format    => $format,
                file      => $fname,
                list      => 'SUBELEMENTS',
                %$out_options_hash
            );
        };
        $e = $EVAL_ERROR;
        ok (!$e, "no exceptions exporting $format to $fname");
        diag $e if $e;
        ok (-e $fname . '.shp', "$fname.shp exists");

        #  Now we re-import and check we get the same numbers
        my $new_bd = Biodiverse::BaseData->new (
            name         => $fname,
            CELL_SIZES   => $bd->get_param ('CELL_SIZES'),
            CELL_ORIGINS => $bd->get_param ('CELL_ORIGINS'),
        );
        my $in_options_hash = $in_options[$i];

        use URI::Escape::XS qw/uri_unescape/;

        # import as shapefile
        $success = eval {
            $new_bd->import_data_shapefile (input_files => [$fname], %$in_options_hash);
        };
        $e = $EVAL_ERROR;
        ok (!$e, "no exceptions importing $fname");
        diag $e if $e;
        if ($e) {
            diag "$fname:";
            foreach my $ext (qw /shp dbf shx/) {
                diag 'size: ' . -s ($fname . $ext);
            }
        }
        

        my @new_labels  = sort $new_bd->get_labels;
        my @orig_labels = sort $bd->get_labels;
        is_deeply (\@new_labels, \@orig_labels, "label lists match for $fname");

        my $new_lb = $new_bd->get_labels_ref;
        subtest "sample counts match for $fname" => sub {
            foreach my $label (sort $bd->get_labels) {
                my $new_list  = $new_lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                my $orig_list = $lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                
                #say "new list: " . join(',', keys %$new_list) . join(',', values %$new_list) if ($new_list);
                #say "orig list: " . join(',', keys %$orig_list) . join(',', values %$orig_list)if ($orig_list);
                is_deeply ($new_list, $orig_list, "SUBELEMENTS match for $label, $fname");
            }
        };

        $i++;
    }
    
}



sub test_attach_ranges_and_sample_counts {
    my $bd = get_small_bd();
    
    #  add a new label to all groups
    my $last_group;
    foreach my $group ($bd->get_groups) {
        $bd->add_element (
            group => $group,
            label => 'new_label',
            count => 25,
        );
        $last_group = $group;
    }

    $bd->attach_label_ranges_as_properties;
    $bd->attach_label_abundances_as_properties;

    #  now delete the new label from one of the groups
    $bd->delete_sub_element (label => 'new_label', group => $last_group);

    #  ...and the label ranges and sample counts should not be affected
    is ($bd->get_range (element => 'new_label'), 3, 'range is correct');
    is ($bd->get_label_abundance (element => 'new_label'), 75, 'sample count is correct');
    
    #  the others should be values of 1
    foreach my $label ($bd->get_labels) {
        next if $label eq 'new_label';

        is ($bd->get_range (element => $label), 1, 'range is correct');
        is ($bd->get_label_sample_count (element => $label), 1, 'sample count is correct');    
    }

    #  and the variety and sample_counts should be different for new_label
    my $lb = $bd->get_labels_ref;
    is ($lb->get_variety (element => 'new_label'), 2, 'new_label variety is 2');
    is ($bd->get_label_sample_count (element => 'new_label'), 50, 'new_label sample count is 50');

    return;
}


sub get_small_bd {
    
    my %bd_args = (
        NAME => 'test include exclude',
        CELL_SIZES => [1,1],
    );

    my $tmp_file = write_data_to_temp_file (get_import_data_small());
    my $fname = $tmp_file->filename;

    my $e;

    #  vanilla import
    my $bd = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd->import_data(
            input_files   => [$fname],
            group_columns => [3, 4],
            label_columns => [1, 2],
        );
    };
    $e = $EVAL_ERROR;
    diag $e if $e;
    
    return $bd;
}

sub test_bounds {
    # testing mins and maxes

    # the cells are indexed using their centroids,
    # so the min bound for x_min being 1 will be 1.5

    my $bd = eval {
        get_basedata_object (
            x_spacing   => 1,
            y_spacing   => 1,
            CELL_SIZES  => [1, 1],
            x_max       => 100,
            y_max       => 100,
            x_min       => 1,
            y_min       => 1,
        );
    };

    #$bd->save (filename => "bd_test_1.bds");

    my $bounds = $bd->get_coord_bounds;
    my $min_bounds = $bounds->{MIN};
    my $max_bounds = $bounds->{MAX};

    ok (@$min_bounds[0] == @$min_bounds[1], "min x and y are the same");
    ok (@$min_bounds[0] == 1.5, "min is correctly 1.5");
    ok (@$max_bounds[0] == @$max_bounds[1], "max bounds for x and y are the same");
    ok (@$max_bounds[0] == 100.5, "max is correctly 100.5");
}

sub test_coords_near_zero {
    #  check values near zero are imported correctly
    #    - was getting issues with negative values one cell left/lower than
    #    they should have been for coords on the cell edge

    foreach my $min (-49, -49.5) {
        my $bd = eval {
            get_basedata_object (
                x_spacing  => 1,
                y_spacing  => 1,
                CELL_SIZES => [1, 1],
                x_max      => $min + 100,
                y_max      => $min + 100,
                x_min      => $min,
                y_min      => $min,
            );
        };
        
        #$bd->save (filename => "bd_test_$min.bds");
    
        #  clunky...
        #my @groups = ('0.5:0.5', '-0.5:0.5', '0.5:-0.5', '-0.5:-0.5', '-1.5:-1.5');
        my @groups;
        my @axis_coords = (-1.5, -0.5, 0.5, 1.5);
        foreach my $i (@axis_coords) {
            foreach my $j (@axis_coords) {
                push @groups, "$i:$j";
            }
        }
        subtest 'Requisite groups exist' => sub {
            foreach my $group (@groups) {
                ok ($bd->exists_group(group => $group), "Group $group exists");
            }
        };

        #  should also text the extents of the data set, min & max on each axis

        my $bounds = $bd->get_coord_bounds;
        my $min_bounds = $bounds->{MIN};
        my $max_bounds = $bounds->{MAX};

        # the cells are indexed by their centroids, so for both of these cases
        # the centroids of the x and y min will be -48.5

        # for -49, the max will be 51.5 
        # but for -49.5, the max will be 50.5

        my $correct_min = -48.5;
        my $correct_max = int($min+100)+0.5;

        ok (@$min_bounds[0] == $correct_min, "x_min is $correct_min");
        ok (@$min_bounds[1] == $correct_min, "y_min is $correct_min");

        ok (@$max_bounds[0] == $correct_max, "x_max is $correct_max");
        ok (@$max_bounds[1] == $correct_max, "y_max is $correct_max");
    }
    
}


#  need to test multidimensional data import, including text axes
sub test_multidimensional_import {
    local $TODO = 'need to test multidimensional data import, including text axes';

    is (0, 1, 'need to test multidimensional data import, including text axes');
}

sub test_rename_groups {
    my $bd = get_basedata_object_from_site_data(
        CELL_SIZES => [100000, 100000],
    );
    $bd = $bd->transpose;
    
    _test_rename_labels_or_groups('groups', $bd);
}

sub test_rename_labels {
    my $bd = get_basedata_object_from_site_data(
        CELL_SIZES => [100000, 100000],
    );
    
    _test_rename_labels_or_groups('labels', $bd);
}

#  rename labels
sub _test_rename_labels_or_groups {
    my ($type, $bd) = @_;

    $bd //= get_basedata_object_from_site_data(
        CELL_SIZES => [100000, 100000],
    );
    
    my $tmp_remap_file = write_data_to_temp_file (get_label_remap_data());
    my $fname = $tmp_remap_file->filename;
    my %rename_props_args = (
        input_element_cols    => [1,2],
        remapped_element_cols => [3,4],
    );

    my $rename_props = Biodiverse::ElementProperties->new;
    my $success = eval { $rename_props->import_data(%rename_props_args, file => $fname) };    
    diag $EVAL_ERROR if $EVAL_ERROR;
    
    ok ($success == 1, "import $type remap without error");

    my $other_type_method = $type eq 'labels'
        ? 'get_groups_ref'
        : 'get_labels_ref'; # /

    my $type_method = "get_${type}_ref";
    my $lbgp = $bd->$type_method;
    my %lb_expected_counts = (
        'Genus:sp1' => undef,
        'nominal_new_name:' => $lbgp->get_sample_count (element => 'Genus:sp11'),
    );

    my $hash_method = $type eq 'labels'
        ? 'get_groups_with_label_as_hash'
        : 'get_labels_in_group_as_hash';
    my $el_type = $type eq 'labels' ? 'label' : 'group';

    my %expected_groups_with_labels = (
        'Genus:sp2' => {},
        'nominal_new_name:' => {$bd->$hash_method ($el_type => 'Genus:sp11')},
    );

    foreach my $label (qw /Genus:sp1 Genus:sp2 Genus:sp18/) {
        $lb_expected_counts{'Genus:sp2'} += $lbgp->get_sample_count (element => $label);

        my %gps_with_label = $bd->$hash_method ($el_type => $label);
        my $hashref = $expected_groups_with_labels{'Genus:sp2'};
        while (my ($gp, $count) = each %gps_with_label) {
            $hashref->{$gp} += $count;
        }
    }

    my $gp = $bd->$other_type_method;
    my %gp_expected;
    foreach my $group ($gp->get_element_list) {
        $gp_expected{$group} = $gp->get_sample_count (element => $group);
    }
    
    my $rename_method = "rename_$type";
    eval {
        $bd->$rename_method (
            remap => $rename_props,
        );
    };
    my $e = $EVAL_ERROR;
    diag $e if $e;
    ok (!$e, 'no eval errors assigning label properties');


    foreach my $label (sort keys %lb_expected_counts) {
        my $count = $lbgp->get_sample_count (element => $label);
        is ($count, $lb_expected_counts{$label}, "Got expected count for $label");
    }

    subtest 'Group counts are not affected by label rename' => sub {
        foreach my $group (keys %gp_expected) {
            is ($gp_expected{$group}, $gp->get_sample_count (element => $group), $group);
        }
    };
    
    subtest 'Renamed labels are in expected groups' => sub {
        while (my ($label, $hash) = each %expected_groups_with_labels) {
            my %observed_hash = $bd->$hash_method($el_type => $label);
            is_deeply ($hash, \%observed_hash, $label);
        }
    };
    
    subtest 'Rename label element arrays are updated' => sub {
        my $lbgp = $bd->get_labels_ref;
        foreach my $label (reverse sort $bd->get_labels) {
            my $el_array = $lbgp->get_element_name_as_array (element => $label);
            foreach my $el (@$el_array) {
                ok ($label =~ /$el/, "Label $label contains $el");
            }
        }
    }
    
}


#  reordering of axes
sub test_reorder_axes {
    my $bd = eval {
            get_basedata_object (
                x_spacing  => 1,
                y_spacing  => 1,
                CELL_SIZES => [1, 1],
                x_max      => 100,
                y_max      => 100,
                x_min      => 0,
                y_min      => 0,
            );
        };
    
    my $new_bd = eval {
        $bd->new_with_reordered_element_axes (
            GROUP_COLUMNS => [1,0],
            LABEL_COLUMNS => [1,0],
        );
    };
    my $error = $EVAL_ERROR;

    ok (defined $new_bd,    "Reordered axes");

}


sub test_reintegrate_after_separate_randomisations {
    #  use a small basedata for test speed purposes
    my %args = (
        x_spacing   => 1,
        y_spacing   => 1,
        CELL_SIZES  => [1, 1],
        x_max       => 5,
        y_max       => 5,
        x_min       => 1,
        y_min       => 1,
    );

    my $bd1 = get_basedata_object (%args);
    
    #  need some extra labels so the randomisations have something to do
    $bd1->add_element (group => '0.5:0.5', label => 'extra1');
    $bd1->add_element (group => '1.5:0.5', label => 'extra1');


    my $sp = $bd1->add_spatial_output (name => 'analysis1');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()', 'sp_circle(radius => 1)'],
        calculations => [qw /calc_endemism_central calc_element_lists_used/],
    );

    my $bd2 = $bd1->clone;
    my $bd3 = $bd1->clone;

    my $prng_seed = 2345;
    foreach my $bd ($bd1, $bd2, $bd3) { 
        my $rand1 = $bd->add_randomisation_output (name => 'random1');
        my $rand2 = $bd->add_randomisation_output (name => 'random2');
        $prng_seed++;
        $rand1->run_analysis (
            function   => 'rand_csr_by_group',
            iterations => 2,
            seed       => $prng_seed,
        );
        $prng_seed++;
        $rand2->run_analysis (
            function   => 'rand_csr_by_group',
            iterations => 2,
            seed       => $prng_seed,
        );
    }

    isnt_deeply (
        $bd1->get_spatial_output_ref (name => 'analysis1'),
        $bd2->get_spatial_output_ref (name => 'analysis1'),
        'spatial results differ after randomisation, bd1 & bd2',
    );
    isnt_deeply (
        $bd1->get_spatial_output_ref (name => 'analysis1'),
        $bd3->get_spatial_output_ref (name => 'analysis1'),
        'spatial results differ after randomisation, bd1 & bd3',
    );

    my $bd_orig;

    for my $bd_from ($bd2, $bd3) {
        #  we need the pre-integration values for checking
        $bd_orig = $bd1->clone;
        $bd1->reintegrate_after_parallel_randomisations (
            from => $bd_from,
        );
        check_randomisation_lists_incremented_correctly (
            orig   => $bd_orig->get_spatial_output_ref (name => 'analysis1'),
            integr => $bd1->get_spatial_output_ref (name => 'analysis1'),
            from   => $bd_from->get_spatial_output_ref (name => 'analysis1')
        );
    }

    foreach my $rand_ref (sort {$a->get_name cmp $b->get_name} $bd1->get_randomisation_output_refs ) {
        my $name = $rand_ref->get_name;
        is ($rand_ref->get_param('TOTAL_ITERATIONS'),
            6,
            "Total iterations is correct after reintegration, $name",
        );
        my $prng_init_states = $rand_ref->get_prng_init_states_array;
        is (scalar @$prng_init_states,
            2,
            "Got 2 init states from reintegrations, $name",
        );
        my $a = $rand_ref->get_prng_init_total_counts_array;
        is_deeply ($a, [2, 2], "got expected total iteration counts array, $name");
    }
    
    #  now check that we don't double reintegrate
    $bd_orig = $bd1->clone;
    for my $bd_from ($bd2, $bd3) {
        #  we need the pre-integration values for checking
        $bd1->reintegrate_after_parallel_randomisations (
            from => $bd_from,
        );
        check_randomisation_integration_skipped (
            orig   => $bd_orig->get_spatial_output_ref (name => 'analysis1'),
            integr => $bd1->get_spatial_output_ref (name => 'analysis1'),
        );
    }
    
    foreach my $rand_ref (sort {$a->get_name cmp $b->get_name} $bd1->get_randomisation_output_refs ) {
        my $name = $rand_ref->get_name;
        is ($rand_ref->get_param('TOTAL_ITERATIONS'),
            6,
            "Total iterations is correct after reintegration ignored, $name",
        );
        my $prng_init_states = $rand_ref->get_prng_init_states_array;
        is (scalar @$prng_init_states,
            2,
            "Got 2 init states when reintegrations ignored, $name",
        );
        my $a = $rand_ref->get_prng_init_total_counts_array;
        is_deeply ($a, [2, 2], "got expected total iteration counts array when reintegrations ignored, $name");
    }
    
    return;
}

sub check_randomisation_integration_skipped {
    my %args = @_;
    my ($sp_orig, $sp_integr) = @args{qw /orig integr/};

    subtest 'randomisation lists incremented correctly when integration should be skipped (i.e. no integration was done)' => sub {
        my $gp_list = $sp_integr->get_element_list;
        my $list_names = $sp_integr->get_lists (element => $gp_list->[0]);
        my @rand_lists = grep {$_ !~ />>sig>>/ and $_ =~ />>/} @$list_names;
        foreach my $group (@$gp_list) {
            foreach my $list_name (@rand_lists) {
                my %l_args = (element => $group, list => $list_name);
                my $lr_orig   = $sp_orig->get_list_ref (%l_args);
                my $lr_integr = $sp_integr->get_list_ref (%l_args);
                is_deeply ($lr_integr, $lr_orig, "$group, $list_name");
            }
        }
    };
}

sub check_randomisation_lists_incremented_correctly {
    my %args = @_;
    my ($sp_orig, $sp_from, $sp_integr) = @args{qw /orig from integr/};

    my @valid_sig_vals = (-0.05, -0.01, 0.01, 0.05);

    subtest 'randomisation lists incremented correctly' => sub {
        my $gp_list = $sp_integr->get_element_list;
        my $list_names = $sp_integr->get_lists (element => $gp_list->[0]);
        my @rand_lists = grep {$_ =~ />>/ and $_ !~ />>sig>>/} @$list_names;
        my @sig_lists  = grep {$_ =~ />>sig>>/} @$list_names;
        foreach my $group (@$gp_list) {
            foreach my $list_name (@rand_lists) {
                my %l_args = (element => $group, list => $list_name);
                my $lr_orig   = $sp_orig->get_list_ref (%l_args);
                my $lr_integr = $sp_integr->get_list_ref (%l_args);
                my $lr_from   = $sp_from->get_list_ref (%l_args);

                foreach my $key (sort keys %$lr_integr) {
                    no autovivification;
                    if ($key =~ /^P_/) {
                        my $index = $key;
                        $index =~ s/^P_//;
                        is ($lr_integr->{$key},
                            $lr_integr->{"C_$index"} / $lr_integr->{"Q_$index"},
                            "Integrated = orig+from, $lr_integr->{$key}, $group, $list_name, $key",
                        );
                    }
                    else {
                        is ($lr_integr->{$key},
                            ($lr_orig->{$key} // 0) + ($lr_from->{$key} // 0),
                            "Integrated = orig+from, $lr_integr->{$key}, $group, $list_name, $key",
                        );
                    }
                }
            }

            foreach my $sig_list_name (@sig_lists) {
                #  we only care if they are in the valid set
                my %l_args = (element => $group, list => $sig_list_name);
                my $lr_integr = $sp_integr->get_list_ref (%l_args);
                foreach my $key (sort keys %$lr_integr) {
                    use List::MoreUtils qw /firstidx/;
                    my $value = $lr_integr->{$key};
                    if (defined $value) {
                        #  use eq, not ==, due to floating point issues with 0.1
                        my $idx = firstidx {$_ eq $value} @valid_sig_vals;
                        ok ($idx != -1, "sig cat $value in valid set ($key, $idx), $group");
                    }
                }
            }
        }
    };
}


sub test_merge {
    my $e;
    my %args = (
        x_spacing   => 1,
        y_spacing   => 1,
        CELL_SIZES  => [1, 1],
        x_max       => 10,
        y_max       => 10,
        x_min       => 1,
        y_min       => 1,
    );

    my $bd1 = get_basedata_object (%args);

    my $bd2 = $bd1->clone;

    $bd1->merge (from => $bd2);

    is ($bd1->get_group_count, $bd2->get_group_count, 'merged group count constant');
    is ($bd1->get_label_count, $bd2->get_label_count, 'merged label count constant');

    #  now we check the sample counts - they should have doubled
    subtest 'merge: sample counts have doubled' => sub {
        foreach my $label ($bd1->get_labels) {
            my $c1 = $bd1->get_label_sample_count (label => $label);
            my $c2 = $bd2->get_label_sample_count (label => $label);
            is ($c1, 2 * $c2, "expected sample count, $label");
        }
    };

    #  now run an analysis and croak when the merge is called
    my $sp = $bd1->add_spatial_output (name => 'bongo');

    eval {$bd1->merge (from => $bd2)};
    $e = $EVAL_ERROR;
    ok ($e, 'tried merging into basedata with outputs and got exception');

    my $bd3 = get_basedata_object (%args, CELL_SIZES => [2, 2]);
    eval {$bd1->merge (from => $bd3)};
    $e = $EVAL_ERROR;
    ok ($e, 'tried merging into basedata with different cell sizes and got exception');

    $bd3 = get_basedata_object (%args, CELL_ORIGINS => [2, 2]);
    eval {$bd1->merge (from => $bd3)};
    $e = $EVAL_ERROR;
    ok ($e, 'tried merging into basedata with different cell origins and got exception');

    #  now one with no overlap so we get double the groups and labels
    my $bd_x0 = get_basedata_object (%args);
    my $bd_x1 = $bd_x0->clone;
    my $bd_x2 = get_basedata_object (
        %args,
        x_max       => 30,
        y_max       => 30,
        x_min       => 21,
        y_min       => 21,
    );

    $bd_x1->merge (from => $bd_x2);

    is (
        $bd_x0->get_group_count * 2,
        $bd_x1->get_group_count,
        'merge: group count has doubled when no overlap',
    );
    is (
        $bd_x0->get_label_count * 2,
        $bd_x1->get_label_count,
        'merge: label count has doubled when no overlap',
    );

    #  now we check the sample counts
    subtest 'merge: sample counts are unchanged when no overlap' => sub {
        foreach my $bd_xx ($bd_x0, $bd_x2) {
            foreach my $label ($bd_xx->get_labels) {
                my $c1 = $bd_x1->get_label_sample_count (label => $label);
                my $c2 = $bd_xx->get_label_sample_count (label => $label);
                is ($c1, $c2, "expected sample count, $label");
            }
        }
    };

    #  need to check the element arrays
    #  - we were getting issues with groups not having correct _ELEMENT_ARRAYS
    #  due to an incorrectly specified csv object
    subtest 'merge: group element arrays are valid when no overlap' => sub {
        my $gp = $bd_x1->get_groups_ref;
        foreach my $group ($bd_x1->get_groups) {
            my $c1 = $gp->get_element_name_as_array (element => $group);
            is (scalar @$c1, 2, "element array has 2 axes, $group");
        }
    };
    subtest 'merge: label element arrays are valid when no overlap' => sub {
        my $lb = $bd_x1->get_labels_ref;
        foreach my $label ($bd_x1->get_labels) {
            my $c1 = $lb->get_element_name_as_array (element => $label);
            is (scalar @$c1, 1, "element array has 1 axis, $label");
        }
    };


    $bd_x1 = $bd_x0->clone;
    $bd_x2 = $bd_x0->clone;
    $bd_x2->add_element (label => 'bongo_dog_band');
    $bd_x2->add_element (group => '100:100');

    $bd_x1->merge (from => $bd_x2);
    ok ($bd_x1->exists_label (label => 'bongo_dog_band'), 'label with no groups exists');
    ok ($bd_x1->exists_group (group => '100:100'),        'group without labels exists');

    #  we cannot merge into ourselves
    eval {$bd_x0->merge (from => $bd_x0)};
    $e = $EVAL_ERROR;
    ok ($e, 'exception raised when merging into self');

    return;
}



sub get_label_remap_data {
    return get_data_section('LABEL_REMAP');
}

sub get_import_data_small {
    return get_data_section('BASEDATA_IMPORT_SMALL');
}

sub get_import_data_null_label {
    return get_data_section('BASEDATA_IMPORT_NULL_LABEL');
}

1;

__DATA__

@@ LABEL_REMAP
id,gen_name_in,sp_name_in,gen_name_out,sp_name_out
1,Genus,sp1,Genus,sp2
10,Genus,sp18,Genus,sp2
2000,Genus,sp2,,
1,Genus,sp11,nominal_new_name,

@@ BASEDATA_IMPORT_SMALL
id,gen_name_in,sp_name_in,x,y,z,incl1,excl1,incl2,excl2,incl3,excl3
1,g1,sp1,1,1,1,1,1,,,1,0
2,g2,sp2,2,2,2,0,,1,1,1,0
3,g2,sp3,1,3,3,,,1,1,1,0

@@ BASEDATA_IMPORT_NULL_LABEL
id,gen_name_in,sp_name_in,x,y,z,incl1,excl1,incl2,excl2,incl3,excl3
1,g1,sp1,1,1,1,1,1,,,1,0
2,g2,sp2,2,2,2,0,,1,1,1,0
3,g2,sp3,1,3,3,,,1,1,1,0
4,,sp3,1,3,3,,,1,1,1,0
