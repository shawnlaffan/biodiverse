#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use 5.010;
use strict;
use warnings;
use utf8;

use constant ON_WINDOWS => ($^O eq 'MSWin32');
use if ON_WINDOWS, 'Win32';

use English qw { -no_match_vars };
use Data::Dumper;
use Path::Class;
use List::Util 1.45 qw /uniq/;
use POSIX qw /floor/;
use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

use Test2::V0;

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


sub test_import_unicode_name {
    use utf8;
    use FindBin;
    my $fname = 'años.txt';
    my $dir = "$FindBin::Bin/data";
    my $bd = Biodiverse::BaseData->new(
        NAME => 'años.txt',
        CELL_SIZES => [100000, 100000],
    );
    
    ok (lives {
        $bd->import_data (
                input_files   => ["$dir/años.txt"],
                group_columns => [3,4],
                label_columns => [1,2],
            )
        },
        'imported csv data in file with unicode name without an exception'
    ) or note $@;

    #  and a matrix
    use Biodiverse::Matrix;
    $fname = "$dir/años_mx_sparse.txt";
    my $mx = Biodiverse::Matrix->new (name => $fname);

    ok (lives
        {
            $mx->import_data_sparse (
                file => $fname,
                label_row_columns => [0],
                label_col_columns => [1],
                value_column      =>  2,
            );
        },
        'imported sparse matrix csv data in file with unicode name without an exception'
    ) or note $@;
    
    $fname = "$dir/años_mx.txt";
    $mx = Biodiverse::Matrix->new (name => $fname);

    ok (lives
        {
            $mx->import_data (
                file => $fname,
            );
        },
        'imported matrix csv data in file with unicode name without an exception'
    ) or note $@;

}


sub test_rename_outputs {
    my $bd = get_basedata_object (
        CELL_SIZES => [1,1],
        x_max => 5,
        y_max => 2,
    );
    
    my $sp_calcs = [qw /calc_endemism_whole calc_endemism_whole_lists/];

    #  spatial
    my $sp = $bd->add_spatial_output (name => 'sp_n1');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => $sp_calcs,
    );
    my $spx = $bd->add_spatial_output (name => 'sp_n1x');
    $spx->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => $sp_calcs,
    );
    $bd->rename_output (new_name => 'sp_n2', output => $sp);
    is $sp->get_name,  'sp_n2',  'renamed spatial output';
    is $spx->get_name, 'sp_n1x', 'did not rename other spatial output';

    my @sp_names = $bd->get_spatial_output_names;
    is [sort @sp_names], [qw 'sp_n1x sp_n2'], 'basedata spatial names match';    

    #  cluster
    my $cl = $bd->add_cluster_output (name => 'cl_n1');
    $cl->run_analysis (
        spatial_calculations => $sp_calcs,
    );
    my $clx = $bd->add_cluster_output (name => 'cl_n1x');
    $clx->run_analysis (
        spatial_calculations => $sp_calcs,
    );
    $bd->rename_output (new_name => 'cl_n2', output => $cl);
    is $cl->get_name,  'cl_n2',  'renamed cluster output';
    is $clx->get_name, 'cl_n1x', 'did not rename other cluster output';

    my @cl_names = $bd->get_cluster_output_names;
    is [sort @cl_names], [qw 'cl_n1x cl_n2'], 'basedata cluster names match';

    my $mx = $cl->get_matrix_ref;
    $bd->rename_output (new_name => 'mx_n2', output => $mx);
    is $mx->get_name, 'mx_n2', 'renamed matrix output';

    my @mx_names = $bd->get_matrix_output_names;
    is [sort @mx_names], [qw 'mx_n2'], 'basedata matrix names match';

    my $rand = $bd->add_randomisation_output (name => 'rd_n1');
    eval {
        $rand->run_analysis (
            function   => 'rand_nochange',
            iterations => 1,
        );
    };
    diag $@ if $@;
    my $randx = $bd->add_randomisation_output (name => 'rd_n1x');
    $randx->run_analysis (
        function   => 'rand_nochange',
        iterations => 1,
    );

    my @sp_lists = $sp->get_lists_across_elements;
    my $sp_named_lists_orig = grep {$_ =~ '^rd_n1>>'} @sp_lists;
    my @cl_lists = $cl->get_list_names_below;
    my $cl_named_lists_orig = grep {$_ =~ '^rd_n1(?!x)'} @cl_lists;

    eval {
        $bd->rename_output (new_name => 'rd_n2', output => $rand);
    };
    diag $@ if $@;

    is $rand->get_name, 'rd_n2', 'renamed randomisation output';

    @sp_lists = $sp->get_lists_across_elements;
    my $sp_named_lists_new = grep {$_ =~ '^rd_n2>>'} @sp_lists;
    is $sp_named_lists_new, $sp_named_lists_orig, 'same number of new named lists as old, sp';
    $sp_named_lists_orig   = grep {$_ =~ '^rd_n1>>'} @sp_lists;
    is $sp_named_lists_orig, 0, 'no lists found with old name, sp';

    @cl_lists = $cl->get_list_names_below;
    my $cl_named_lists_new = grep {$_ =~ '^rd_n2'} @cl_lists;
    is $cl_named_lists_new, $cl_named_lists_orig, 'same number of new named lists as old, cl';
    $cl_named_lists_orig   = grep {$_ =~ '^rd_n1(?!x)'} @cl_lists;
    is $cl_named_lists_orig, 0, 'no lists found with old name, cl';

    my @rand_names = $bd->get_randomisation_output_names;
    is [sort @rand_names], [qw 'rd_n1x rd_n2'], 'basedata randomisation names match';

    return;
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
    
    ok (lives
        {$bd->build_spatial_index (resolutions => [10, 100])},
        'build index with resolution same as bd',
    ) or note $@;
    ok (lives
        {$bd->build_spatial_index (resolutions => [20, 400])},
        'build index with resolution double bd',
    ) or note $@;
    ok (lives 
        {$bd->build_spatial_index (resolutions => [20, 100])},
        'build index with resolution double/same as bd',
    ) or note $@;
    
    ok (dies 
        {$bd->build_spatial_index (resolutions => [2, 10])},
        "won't build index with resolution smaller than bd",
    );
    ok (dies
        {$bd->build_spatial_index (resolutions => [2, 0])},
        "won't build index with resolution smaller than bd, one zero",
    );
    ok (dies 
        {$bd->build_spatial_index (resolutions => [0, 100])},
        "won't build index with resolution smaller than bd, one zero",
    );
    ok (dies 
        {$bd->build_spatial_index (resolutions => [20, 10])},
        "won't build index with one axis resolution smaller than bd",
    );

    #  now check a basedata with a text axis    
    $bd = Biodiverse::BaseData->new (CELL_SIZES => [-1, 2, 2]);
    $bd->add_element (label => $label_name, group => 'x:5:151');
    $bd->add_element (label => $label_name, group => 'y:55:1151');
    
    ok (lives
        {$bd->build_spatial_index (resolutions => [-1, 2, 2])},
        'build index with resolution same as bd (text axis)',
    );
    ok (lives 
        {$bd->build_spatial_index (resolutions => [-1, 4, 4])},
        'build index with resolution double bd (text axis)',
    );
    ok (lives
        {$bd->build_spatial_index (resolutions => [-1, 4, 2])},
        'build index with resolution double/same as bd (text axis)',
    );
    
    ok (dies
        {$bd->build_spatial_index (resolutions => [2, 10])},
        "won't build index with fewer axes than basedata (text axis)",
    );
    ok (dies
        {$bd->build_spatial_index (resolutions => [-1, 2, 0])},
        "won't build index with resolution smaller than bd, one zero (text axis)",
    );
    ok (dies
        {$bd->build_spatial_index (resolutions => [0, 0, 100])},
        "won't build index with resolution smaller than bd, one zero (text axis)",
    );
    ok (dies
        {$bd->build_spatial_index (resolutions => [-1, 1, 10])},
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


sub test_reduce_resolution {
    my $bd1    = Biodiverse::BaseData->new(CELL_SIZES => [1, 1]);    
    my $bdc_22 = Biodiverse::BaseData->new(CELL_SIZES => [2, 2]);
    my $bdc_21 = Biodiverse::BaseData->new(CELL_SIZES => [2, 1]);
    my $bdc_21_11 = Biodiverse::BaseData->new(CELL_SIZES => [2, 1], CELL_ORIGINS => [1,1]);
    
    my $join_char = $bd1->get_param('JOIN_CHAR');
    my @labels = ('a' .. 'zzz');
    #  completely filled;
    foreach my $x (0 .. 19) {
        foreach my $y (0 .. 19) {
            my $label = $labels[$y];
            my $gp = join $join_char, $x+0.5, $y+0.5;
            $bd1->add_element (group => $gp, label => $label);
            my $gp2 = join $join_char, ($x - $x % 2) + 1, ($y - $y % 2) + 1;
            $bdc_22->add_element (group => $gp2, label => $label);
            my $gp3 = join $join_char, ($x - $x % 2) + 1, $y + 0.5;
            $bdc_21->add_element (group => $gp3, label => $label);
            #  really need to abstract the cell coord calcs into a sub
            my $gx_tmp = floor ( ( $x - 1 ) / 2 );
            my $gx = 1 + $gx_tmp * 2 + ( 2 / 2 );
            my $gp4 = join $join_char, $gx, $y + .5;
            $bdc_21_11->add_element (
                group => $gp4,
                label => $label,
                count => 1 + $y + $x * 20,
            );
        }
    }
    
    #  add some label props to the first ten or so
    my $lb_props = Biodiverse::ElementProperties->new();
    my %lb_prop_hash;
    my $i = -1;
    foreach my $label (@labels[0..10]) {
        $i++;
        $lb_prop_hash{$label} = {PROP1 => $i, PROP2 => $i+1};
        $lb_props->add_element(element => $label);
        $lb_props->add_to_lists (
            element    => $label,
            PROPERTIES => $lb_prop_hash{$label},
        );
    }
    $bd1->assign_element_properties (
        type              => 'labels',
        properties_object => $lb_props,
    );

    #  simple cases
    my %sizes = (
        22 => [$bdc_22, [2,2]],
        21 => [$bdc_21, [2,1]],
        '21_11' => [$bdc_21_11, [2,1], [1,1]],
    );

    for my $size_key (sort keys %sizes) {
        my $bd_c  = $sizes{$size_key}[0];
        my $sizes = $sizes{$size_key}[1];
        my $origins = $sizes{$size_key}[2];

        my $bd2 = $bd1->clone_with_reduced_resolution (
            cell_sizes   => $sizes,
            cell_origins => $origins,
        );
    
        is ([$bd2->get_cell_sizes], $sizes, "got expected cell sizes $size_key");
        is ($bd2->get_label_count, $bd1->get_label_count, "same number of labels $size_key");
        is ($bd2->get_group_count, $bd_c->get_group_count, "correct number of groups $size_key");
        is ([sort $bd2->get_groups], [sort $bd_c->get_groups], "got expected groups $size_key");
        is ([sort $bd2->get_labels], [sort $bd_c->get_labels], "got expected labels $size_key");
        
        my @expected_sample_counts = map {$bd1->get_label_sample_count (label => $_)} sort $bd1->get_labels;
        my @sample_counts          = map {$bd2->get_label_sample_count (label => $_)} sort $bd2->get_labels;
        is (
            \@sample_counts,
            \@expected_sample_counts,
            'Got expected sample counts',
        );
        
        #  check the label props
        my $lb1 = $bd1->get_labels_ref;
        my $lb2 = $bd2->get_labels_ref;
        foreach my $label (sort $bd1->get_labels) {
            my $list_exp = $lb1->get_list_ref (
                element => $label,
                list    => 'PROPERTIES',
            );
            my $list_got = $lb2->get_list_ref (
                element => $label,
                list    => 'PROPERTIES',
            );
            is (
                $list_got,
                $list_exp,
                'Got matching label props after resolution change',
            );
        }
    }
    
    
    my %die_calls = (
        'zero axis'         => [[0,1]],
        'smaller axes'      => [[0.5,0.5]],
        'no axes'           => [],
        'too many axes'     => [[2,2,2]],
        'insufficient axes' => [[2]],
        'bung axis origins' => [[2,2], [1.5,1]],
        #'unchanged axes' => [1,1],  #  no - user can just get a clone the hard way
    );
    foreach my $text (sort keys %die_calls) {
        my $cell_sizes   = $die_calls{$text}[0];
        my $cell_origins = $die_calls{$text}[1];

        ok (dies 
            {$bd1->clone_with_coarser_cell_sizes (
                cell_sizes   => $cell_sizes,
                cell_origins => $cell_origins,
            )},
            "dies on $text",
        );
    }
    
}

sub test_remap_labels_from_hash {
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);

    my %remap;
    my @expected_new_labels;
    foreach my $label (sort $bd->get_labels()) {
        $remap{$label} = uc( $label );
        push( @expected_new_labels, uc $label );
    }

    $bd->remap_labels_from_hash(remap => \%remap);
       
    my @actual_new_labels = sort $bd->get_labels();
    is (\@actual_new_labels,
        \@expected_new_labels,
        "Got expected labels"
    );
}

sub test_remap_mismatched_labels {
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);

    my %remap;
    my @expected_new_labels;
    foreach my $label (sort $bd->get_labels()) {
        $remap{$label} = uc( $label );
        push( @expected_new_labels, uc $label );
    }

    # now also add in some junk remap values (might come up say when
    # applying a multiple tree remap to a single tree)
    foreach my $number (0..10) {
        $remap{"junkkey$number"} = "junkvalue$number";
    }
    
    
    eval { $bd->remap_labels_from_hash(remap => \%remap); };
    my $e = $EVAL_ERROR;
    ok (!$e, "got no exception from mismatched remap");
    
    my @actual_new_labels = sort $bd->get_labels();

    is ( \@actual_new_labels,
         \@expected_new_labels,
          "Got expected labels"
    );
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
            get_basedata_object ( x_max => 10, y_max => 10, %$args );
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

    my $fname = write_data_to_temp_file(get_import_data_small());
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

    my $fname = write_data_to_temp_file(get_import_data_null_label());
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

    my $fname1 = write_data_to_temp_file($data);
    my $fname_cr = write_data_to_temp_file($data_cr);
    
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

    my $fname = write_data_to_temp_file(get_import_data_small());

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
    
    my $tmp_folder = get_temp_file_path('');

    my $i = 0;
    foreach my $out_options_hash (@out_options) {
        #local $Data::Dumper::Sortkeys = 1;
        #local $Data::Dumper::Purity   = 1;
        #local $Data::Dumper::Terse    = 1;
        #say Dumper $out_options_hash;

        #  need to use a better approach for the name, but at least it goes into a temp folder
        my $fname = $tmp_folder . 'delimtxt' . $i
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
        is (\@new_labels, \@orig_labels, "label lists match for $fname");
        
        my $new_lb = $new_bd->get_labels_ref;
        subtest "sample counts match for $fname" => sub {
            foreach my $label (sort $bd->get_labels) {
                my $new_list  = $new_lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                my $orig_list = $lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                is ($new_list, $orig_list, "SUBELEMENTS match for $label, $fname");
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

    my $fname = write_data_to_temp_file(get_import_data_small());
    #note("testing filename $fname");
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
    is ($@, '', 'import vanilla with no exceptions raised');
    
    # not sure why this is used
    $bd->add_element (
        group => '1.5:1.5',
        label => 'bazungalah:smith',
        count => 25,
    );
    
    my $lb = $bd->get_labels_ref;
    my $gp = $bd->get_groups_ref;

    #  export should return file names?  Or should we cache them on the object?

    #my $format = 'export_asciigrid';
    my @out_options = (
        { format => 'export_asciigrid'},
        { format => 'export_floatgrid'},
        { format => 'export_geotiff'},
        { format => 'export_ers'},
    );

    # the raster data file won't specify the origin and cell size info, so pass as
    # parameters.
    my @cell_sizes      = $bd->get_cell_sizes; # probably not set anywhere, and is using the default
    my @cell_origins    = $bd->get_cell_origins;    
    my %in_options_hash = (
        labels_as_bands   => 1,
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
        #  but we want unicode in there
        my $tmp_dir = get_temp_dir();
        my $uni_a = "\N{LATIN SMALL LETTER A WITH BREVE}";
        my $uni_r = "\N{LATIN SMALL LETTER R WITH ACUTE}";
        my $uni_s = "\N{LATIN SMALL LETTER S WITH CARON}";
        my $fname_base = $format . "_r${uni_a}${uni_s}te${uni_r}";
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
        is ($@, '', "no exceptions exporting $format");

        #  Now we re-import and check we get the same numbers
        my $new_bd = Biodiverse::BaseData->new (
            name         => $fname,
            CELL_SIZES   => $bd->get_param ('CELL_SIZES'),
            CELL_ORIGINS => $bd->get_param ('CELL_ORIGINS'),
        );
        
        use URI::Escape::XS qw/uri_unescape/;

        # each band was written to a separate file,
        # load each in turn and add to the basedata object
        # Should import the lot at once and then rename
        # the labels to their unescaped form
        # albeit that would be just as contorted in the end.

        #  get the list of files, but use readdir as glob can be sensitive
        #  (although that issue might not have been glob's fault)
        #my @exported_files = glob "$tmp_dir/*";
        opendir(my $dh, $tmp_dir) or die "Unable to open $tmp_dir";
        #  no . or ..
        my @exported_files = grep {!/^[.]{1,2}$/} readdir($dh);
        closedir ($dh);
        ok (scalar @exported_files, 'got some files from the readdir');
        @exported_files = map {"$tmp_dir/$_"} @exported_files;
        if (ON_WINDOWS) {
            @exported_files = map {Win32::GetLongPathName($_)} @exported_files;
        }
        #  make sure we skip world and hdr files
        @exported_files = grep {$_ !~ /(?:(?:hdr)|w)$/} @exported_files;


        foreach my $this_file (@exported_files) {
            #  must have a file extension - er-mapper files do not by default
            next if $this_file !~ /\.\w\w\w\w?$/;
            
            # find label name from file name
            my $this_label = Path::Class::File->new($this_file)->basename();
            $this_label  =~ s/\.\w+$//;  #  hackish way of clearing suffix
            my $target_name = $this_label;
            $target_name =~ s/.*${fname_base}_//;
            $target_name = uri_unescape($target_name);
            #diag "\nWorking on $target_name, $this_label\n";

            $success = eval {
                $new_bd->import_data_raster (
                    input_files => [$this_file],
                    %in_options_hash,
                    labels_as_bands => 1,
                    #given_label => $this_label,
                );
            };
            is ($@, '', "no exceptions importing");

            #  cope with the export name including the format
            if (not $this_file =~ /ers$/) {
                my $new_name = $target_name;
                $new_name =~ s/^.+_//;
                $new_bd->rename_label (
                    label    => $this_label,
                    new_name => $new_name,
                ) or diag "Raster roundtripper: Could not rename label $this_label to $new_name";
            }
            else {
                #  Workaround until we handle band names
                #  in multiband rasters.
                #  It means we don't properly test imports,
                #  but it's a problem left for V3 when we
                #  shift to Geo::GDAL::FFI
                my $bi = 0;
                foreach my $label (sort $bd->get_labels) {
                    $bi++;
                    my $renamed = $new_bd->rename_label (
                        label    => 'band' . $bi,
                        new_name => $label,
                    );
                    #  canary test that will start failing when/if
                    #  we process band names properly
                    ok $renamed, "Renamed ers band band$bi to $label";
                }
            }
        }
        my @new_labels  = sort $new_bd->get_labels;
        my @orig_labels = sort $bd->get_labels;
        is (\@new_labels, \@orig_labels, "label lists match");

        my $new_lb = $new_bd->get_labels_ref;
        subtest "sample counts match for $format" => sub {
            foreach my $label (sort $bd->get_labels) {
                my $new_list  = $new_lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                my $orig_list = $lb->get_list_ref (list => 'SUBELEMENTS', element => $label);

                is (
                    $new_list,
                    $orig_list,
                    "SUBELEMENTS match for $label, $format"
                );
            }
        };
        
        is (
          scalar $bd->get_coord_bounds,
          scalar $new_bd->get_coord_bounds,
          "coord bounds match for $format"
        );

        $i++;
    }
    
}


#  very similar to test_roundtrip_raster,
#  but uses a zero cellsize for the basedata (so points)
#  and uses raster values as labels
sub test_raster_zero_cellsize {
    my %bd_args = (
        NAME => 'test include exclude',
        CELL_SIZES => [1,1],
    );

    my $fname = write_data_to_temp_file(get_import_data_small());
    note("testing filename $fname");
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
        my $tmp_dir = get_temp_dir();
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
        is ($@, '', "no exceptions exporting $format");
        
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

            my $this_label = Path::Class::File->new($this_file)->basename();
            $this_label =~ s/.*${fname_base}_//; 
            $this_label =~ s/\....$//;  #  hackish way of clearing suffix
            $this_label = uri_unescape($this_label);
            #note "got label $this_label\n";

            $success = eval {
                $new_bd->import_data_raster (
                    input_files => [$this_file],
                    %in_options_hash,
                    #labels_as_bands => 1,
                    given_label => $this_label,
                );
            };
            is ($@, '', "no exceptions importing");
        }
        my @new_labels  = sort $new_bd->get_labels;
        my @orig_labels = sort $bd->get_labels;
        is (\@new_labels, \@orig_labels, "label lists match");
        
        is (
            $new_bd->get_group_count,
            $bd->get_group_count,
            'got expected group count',
        );

        $i++;
    }
    
}

sub test_import_shapefile_dms_coords {
    my %bd_args = (
        NAME => 'test import shapefile DMS',
        CELL_SIZES => [0,0],
    );

    my $bd1 = Biodiverse::BaseData->new (%bd_args);
    my $e;

    my $fname = Path::Class::File->new (
        Path::Class::File->new($0)->dir,
        "dms_latlon.shp",
    );
    $fname = $fname->stringify;
    say "testing filename $fname";
    
    eval {
        $bd1->import_data_shapefile(
            input_files   => [$fname],
            group_field_names => [qw /dms_lon dms_lat/],
            label_field_names => [qw /KEY/],
            is_lat_field => {dms_lat => 1},
            is_lon_field => {dms_lon => 1},
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, 'import spreadsheet with DMS coords produced no error');

    my @gp_names = $bd1->get_groups;
    is (\@gp_names,
               ['134.506111111111:-23.5436111111111'],
               'got correct group names',
    );
    
}

#can we reimport shapefiles after exporting and get the same answer
sub test_roundtrip_shapefile {
    my %bd_args = (
        NAME => 'test include exclude',
        CELL_SIZES => [1,1],
    );

    my $fname = write_data_to_temp_file(get_import_data_small());
    note("testing filename $fname");
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

    my $tmp_dir = get_temp_file_path('');

    my $i = 0;
    foreach my $out_options_hash (@out_options) {
        #local $Data::Dumper::Sortkeys = 1;
        #local $Data::Dumper::Purity   = 1;
        #local $Data::Dumper::Terse    = 1;
        #say Dumper $out_options_hash;

        #  need to use a better approach for the name
        my $fname_base = $tmp_dir . 'shapefile_' . $i; 

        my $suffix = '.shp';
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
        ok (-e $fname, "$fname exists");

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
        is (\@new_labels, \@orig_labels, "label lists match for $fname");

        my $new_lb = $new_bd->get_labels_ref;
        subtest "sample counts match for $fname" => sub {
            foreach my $label (sort $bd->get_labels) {
                my $new_list  = $new_lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                my $orig_list = $lb->get_list_ref (list => 'SUBELEMENTS', element => $label);
                
                #say "new list: " . join(',', keys %$new_list) . join(',', values %$new_list) if ($new_list);
                #say "orig list: " . join(',', keys %$orig_list) . join(',', values %$orig_list)if ($orig_list);
                is ($new_list, $orig_list, "SUBELEMENTS match for $label, $fname");
            }
        };

        $i++;
    }
    
}


sub test_delete_labels_and_numeric_flag {
    my $bd = Biodiverse::BaseData->new (
        NAME => 'numericish labels',
        CELL_SIZES => [1,1],
    );
    
    $bd->add_element (group => '0:0', label => 'NA');
    foreach my $label (1..5) {
        $bd->add_element (group => '0:0', label => 'NA');
    }
    
    ok (!$bd->labels_are_numeric, 'labels are not numeric when NA included');
    $bd->delete_labels (labels => ['NA']);
    ok ($bd->labels_are_numeric, 'labels are not numeric when NA deleted using delete_labels');
    
    #  put it back in
    $bd->add_element (group => '0:0', label => 'NA');
    ok (!$bd->labels_are_numeric, 'labels are not numeric when NA reinserted');
    $bd->delete_label (label => 'NA');
    ok ($bd->labels_are_numeric, 'labels are not numeric when NA deleted using delete_label');
    # TODO: add_element_simple_aa, but maybe it can be left to the caller as it is simple
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

    my $fname = write_data_to_temp_file(get_import_data_small());

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
            x_max       => 10,
            y_max       => 10,
            x_min       => 1,
            y_min       => 1,
        );
    };

    #$bd->save (filename => "bd_test_1.bds");

    my $bounds = $bd->get_coord_bounds;
    my $min_bounds = $bounds->{MIN};
    my $max_bounds = $bounds->{MAX};

    is (@$min_bounds[0], @$min_bounds[1], "min x and y are the same");
    is (@$min_bounds[0], 1.5, "min is correctly 1.5");
    is (@$max_bounds[0], @$max_bounds[1], "max bounds for x and y are the same");
    is (@$max_bounds[0], 10.5, "max is correctly 10.5");
}

sub test_coords_near_zero {
    #  check values near zero are imported correctly
    #    - was getting issues with negative values one cell left/lower than
    #    they should have been for coords on the cell edge

    foreach my $min (-4, -4.5) {
        my $bd = eval {
            get_basedata_object (
                x_spacing  => 1,
                y_spacing  => 1,
                CELL_SIZES => [1, 1],
                x_max      => $min + 10,
                y_max      => $min + 10,
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
        # the centroids of the x and y min will be -3.5

        # for -4, the max will be 5.5 
        # but for -4.5, the max will be 50

        my $correct_min = -3.5;
        my $correct_max = int($min+10)+0.5;

        is (@$min_bounds[0], $correct_min, "x_min is $correct_min");
        is (@$min_bounds[1], $correct_min, "y_min is $correct_min");

        is (@$max_bounds[0], $correct_max, "x_max is $correct_max");
        is (@$max_bounds[1], $correct_max, "y_max is $correct_max");
    }
    
}


#  need to test multidimensional data import, including text axes
sub test_multidimensional_import {
    todo
      'need to test multidimensional data import, including text axes'
      => sub {
       is (0, 1, 'need to test multidimensional data import, including text axes')
      };
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
    
    my $fname = write_data_to_temp_file(get_label_remap_data());

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
            is ($hash, \%observed_hash, $label);
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
                x_max      => 10,
                y_max      => 10,
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
