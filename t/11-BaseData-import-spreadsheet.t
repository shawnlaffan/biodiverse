#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };
use Data::Dumper;
use Path::Tiny qw /path/;

use Test2::V0;

use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;


use Biodiverse::TestHelpers qw /:basedata/;
use Biodiverse::BaseData;
use Biodiverse::ElementProperties;

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


sub test_import_spreadsheet_dms_coords {
    my %bd_args = (
        NAME => 'test import spreadsheet DMS',
        CELL_SIZES => [0,0],
    );

    my $bd1 = Biodiverse::BaseData->new (%bd_args);
    my $e;

    my $fname = path (
        path($0)->parent,
        "test_spreadsheet_import_dms_coords.xlsx",
    );
    $fname = $fname->stringify;
    say "testing filename $fname";
    
    eval {
        $bd1->import_data_spreadsheet(
            input_files   => [$fname],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
            is_lat_field => {y => 1},
            is_lon_field => {x => 1},
        );
    };
    $e = $EVAL_ERROR;
    diag $e if $e;
    ok (!$e, 'import spreadsheet with DMS coords produced no error');

    my @gp_names = $bd1->get_groups;
    is (\@gp_names,
               ['134.506111111111:-23.5436111111111'],
               'got correct group names',
    );
    
}

sub test_import_spreadsheet {
    my %bd_args = (
        NAME => 'test import spreadsheet',
        CELL_SIZES => [10000,100000],
    );

    my $bd1 = Biodiverse::BaseData->new (%bd_args);
    my $e;

    #  an empty input_files array
    eval {
        $bd1->import_data_spreadsheet(
            input_files   => [undef],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok ($e, 'import spreadsheet failed when no or undef file passed');
    
    #  a non-existent file
    eval {
        $bd1->import_data_spreadsheet(
            input_files   => ['blongordia.xlsx'],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok ($e, 'import spreadsheet failed when no or undef file passed');
    
    foreach my $extension (qw /xlsx ods xls/) {
        my $tmp_file = path (
            path($0)->parent,
            "test_spreadsheet_import.$extension",
        );
        my $fname = $tmp_file->stringify;
        say "testing filename $fname";
        _test_import_spreadsheet($fname, "filetype $extension");
    }

    _test_import_spreadsheet_matrix_form ();
}


sub _test_import_spreadsheet {
    my ($fname, $feedback) = @_;

    #my $todo = todo 'ParseODS does not handle test files'
    #  if $fname =~ /ods$/ && $Spreadsheet::ParseODS::VERSION <= 0.25;

    my %bd_args = (
        NAME => 'test import spreadsheet' . $fname,
        CELL_SIZES => [100000,100000],
    );

    my $bd1 = Biodiverse::BaseData->new (%bd_args);
    my $e;

    eval {
        $bd1->import_data_spreadsheet(
            input_files   => [$fname],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "import spreadsheet with no exceptions raised, $feedback");
    
    
    my $bd2 = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd2->import_data_spreadsheet(
            input_files   => [$fname],
            sheet_ids     => [1],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "no errors for import spreadsheet with sheet id specified, $feedback");

    is ([sort $bd2->get_groups],
        [sort $bd1->get_groups],
        "same groups when sheet_id specified as default, $feedback",
    );
    is ([sort $bd2->get_labels],
        [sort $bd1->get_labels],
        "same labels when sheet_id specified as default, $feedback",
    );
    is ($bd1->get_group_count, 19, "Group count is correct, $feedback");

    eval {
        $bd2->import_data_spreadsheet(
            input_files   => [$fname, $fname],
            sheet_ids     => [1, 2],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "no errors for import spreadsheet with two sheet ids specified, $feedback");
    
    #  label counts in $bd2 should be double that of $bd1
    #  $bd2 should also have Genus2:sp1 etc
    subtest "Label counts are doubled, $feedback" => sub {
        foreach my $lb ($bd1->get_labels) {
            is (
                $bd2->get_label_sample_count (element => $lb),
                $bd1->get_label_sample_count (element => $lb) * 2,
                "Label sample count doubled: $lb",
            );
        }
    };
    subtest "Additional labels imported, $feedback" => sub {
        foreach my $lb ($bd1->get_labels) {
            #  second label set should be Genus2:Sp1 etc
            my $alt_label = $lb;
            $alt_label =~ s/Genus:/Genus2:/;
            ok ($bd2->exists_label (label => $alt_label), "bd2 contains $alt_label");
        }
    };
    
    my $bd3 = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd3->import_data_spreadsheet(
            input_files   => [$fname],
            sheet_ids     => ['Example_site_data'],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "no errors for import spreadsheet with sheet id specified as name, $feedback");
    
    #is ($bd3, $bd1, "data matches for sheet id as name and number, $feedback");
    is ([sort $bd3->get_groups],
        [sort $bd1->get_groups],
        "groups match for sheet id as name and number, $feedback",
    );
    is ([sort $bd3->get_labels],
        [sort $bd1->get_labels],
        "labels match for sheet id as name and number, $feedback",
    );

    my $bd_text = Biodiverse::BaseData->new (%bd_args, CELL_SIZES => [100000, 100000, -1]);
    eval {
        $bd_text->import_data_spreadsheet(
            input_files   => [$fname],
            sheet_ids     => [1],
            group_field_names => [qw /x y genus/],
            label_field_names => [qw /species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "no errors for import spreadsheet with text group, $feedback");
    
    is ($bd_text->get_group_count, 19, "Group count is correct, $feedback");

    subtest 'text group axis' => sub {
        my $gp_text = $bd_text->get_groups_ref;
        foreach my $gp_name ($gp_text->get_element_list) {
            my $el_arr = $gp_text->get_element_name_as_array (element => $gp_name);
            is ($el_arr->[2], 'Genus', "got correct coord val for text group, $gp_name");
        }
    };

    my $bd_arg_order = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd_arg_order->import_data_spreadsheet(
            input_files   => [$fname],
            #sheet_ids     => ['Example_site_data'],
            group_field_names => [qw /y x/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    #ok (!$e, "no errors for import spreadsheet with sheet id specified as name, $feedback");

    subtest 'imported transposed basedata correctly, col names' => sub {
        my $gp_ref_arg_order = $bd_arg_order->get_groups_ref;
        # my $gp_ref_bd1 = $bd1->get_groups_ref;
        my $join_char  = $bd1->get_param ('JOIN_CHAR');

        foreach my $gp_name ($bd_arg_order->get_groups) {
            my $gp_arr = $gp_ref_arg_order->get_element_name_as_array (element => $gp_name);
            my $bd1_gp_name = join $join_char, reverse @$gp_arr;
            ok ($bd1->exists_group (group => $bd1_gp_name), "Got reverse of $gp_name");
        }
    };

    #$bd_arg_order = Biodiverse::BaseData->new (%bd_args);
    #eval {
    #    $bd_arg_order->import_data_spreadsheet(
    #        input_files   => [$fname],
    #        #sheet_ids     => ['Example_site_data'],
    #        #group_field_names => [qw /y x/],
    #        group_field_names
    #        label_field_names => [qw /genus species/],
    #    );
    #};
    #$e = $EVAL_ERROR;
    #note $e if $e;
    ##ok (!$e, "no errors for import spreadsheet with sheet id specified as name, $feedback");
    #
    #subtest 'imported transposed basedata correctly, col nums' => sub {
    #    my $gp_ref_arg_order = $bd_arg_order->get_groups_ref;
    #    my $gp_ref_bd1 = $bd1->get_groups_ref;
    #    my $join_char  = $bd1->get_param ('JOIN_CHAR');
    #
    #    foreach my $gp_name ($bd_arg_order->get_groups) {
    #        my $gp_arr = $gp_ref_arg_order->get_element_name_as_array (element => $gp_name);
    #        my $bd1_gp_name = join $join_char, reverse @$gp_arr;
    #        ok ($bd1->exists_group (group => $bd1_gp_name), "Got reverse of $gp_name");
    #    }
    #};
}

sub _test_import_spreadsheet_matrix_form {
    #my ($fname, $feedback) = @_;
    my $feedback = 'matrix form';
    
    my $fname_mx   = 'test_spreadsheet_import_matrix_form.xlsx';
    my $fname_norm = 'test_spreadsheet_import.xlsx';

    $fname_mx = path (
        path($0)->parent,
        $fname_mx,
    );
    $fname_norm = path (
        path ($0)->parent,
        $fname_norm,
    );
    
    my %bd_args = (
        NAME => 'test import spreadsheet',
        CELL_SIZES => [100000,100000],
    );

    my $bd1 = Biodiverse::BaseData->new (%bd_args);
    my $e;

    eval {
        $bd1->import_data_spreadsheet(
            input_files   => [$fname_mx],
            group_field_names => [qw /x y/],
            label_start_col   => [3],
            data_in_matrix_form => 1,
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "import spreadsheet with no exceptions raised, $feedback");
    
    my $bd2 = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd2->import_data_spreadsheet(
            input_files   => [$fname_norm],
            sheet_ids     => [1],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    
    is ($bd1->get_group_count, $bd2->get_group_count, 'group counts match');
    is ($bd1->get_label_count, $bd2->get_label_count, 'label counts match');

    #is ($bd1, $bd2, "same contents matrix form and non-matrix form, $feedback");
    is ([sort $bd2->get_groups],
        [sort $bd1->get_groups],
        "same groups matrix form and non-matrix form, $feedback",
    );
    is ([sort $bd2->get_labels],
        [sort $bd1->get_labels],
        "same labels matrix form and non-matrix form, $feedback",
    );
    
}

1;
