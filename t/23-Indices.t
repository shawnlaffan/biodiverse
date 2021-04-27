#!/usr/bin/perl -w
use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;

use Test2::V0;
use rlib;

local $| = 1;

use Biodiverse::BaseData;
use Biodiverse::Indices;
use Biodiverse::TestHelpers qw {:basedata :tree};

use Scalar::Util qw /blessed/;

#  ideally we shouldn't need to do this but the hierarchical subs need it
my @res = (10, 10);
my $bd = get_basedata_object(
    x_spacing  => $res[0],
    y_spacing  => $res[1],
    x_max      => $res[0],
    y_max      => $res[1],
    CELL_SIZES => \@res,
);


use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @subs = grep {$_ =~ 'main::test_'} $obj->functions();
#
#use Class::Inspector;
#my @subs = Class::Inspector->functions ('main::');

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

    foreach my $sub (@subs) {
        no strict 'refs';
        $sub->();
    }

    done_testing;
    return 0;
}



sub test_general {
    #  some helper vars
    my ($is_error, $e);

    my $indices = eval {Biodiverse::Indices->new(BASEDATA_REF => $bd)};
    is (blessed $indices, 'Biodiverse::Indices', 'Sub new works');

    my $checker = eval {$indices->get_metadata (sub => 'calc_frobnambulator_snartfingler')};
    $e = $EVAL_ERROR;
    #diag $e;
    ok ($e, 'Got an error when accessing metadata for non-existent calc sub');

    my %calculations = eval {$indices->get_calculations};
    $e = $EVAL_ERROR;
    ok (!$e, 'Get calculations without eval error');

    my %indices_to_calc = eval {$indices->get_indices};
    $e = $EVAL_ERROR;
    ok (!$e, 'Get indices without eval error');

    my %required_args = eval {$indices->get_required_args};
    $e = $EVAL_ERROR;
    ok (!$e, 'Get required args without eval error');

    my @calc_array =
        qw/calc_sorenson
            calc_elements_used
            calc_pe
            calc_endemism_central
            calc_endemism_whole
            calc_numeric_label_stats
        /;
    my %calc_hash;
    @calc_hash{@calc_array} = (0) x scalar @calc_array;
    $calc_hash{calc_sorenson} = 1;  #  1 if we should get an exception
    $calc_hash{calc_numeric_label_stats} = 1;

    my $calc_args = {
        tree_ref      => get_tree_object(),
        element_list1 => [],
    };

    foreach my $calc (sort keys %calc_hash) {
        my %dep_tree = eval {
            $indices->parse_dependencies_for_calc (
                calculation    => $calc,
                nbr_list_count => 1,
                calc_args      => $calc_args,
            )
        };
        $e = $EVAL_ERROR;
        my $with_or_without = $calc_hash{$calc} ? 'with' : 'without';
        $is_error = $e ? 1 : 0;
        my $expected_error = $calc_hash{$calc} ? 1 : 0;
        is ($is_error, $expected_error, "Parsed dependency tree $with_or_without error being raised ($calc)");
    }
    
    #$calc_args = {};
    my $valid_calcs = eval {
        $indices->get_valid_calculations (
            calculations   => \%calc_hash,
            nbr_list_count => 1,
            calc_args      => $calc_args,
        );
    };
    $e = $EVAL_ERROR;
    if ($e) {
        diag blessed $e ? $e->message : $e;
    }
    $is_error = $EVAL_ERROR ? 1 : 0;
    is ($is_error, 0, "Obtained valid calcs without error");

    my $calcs_to_run = $indices->get_valid_calculations_to_run;
    $e = $EVAL_ERROR;
    diag $e->message if blessed $e;
    $is_error = $EVAL_ERROR ? 1 : 0;
    is ($is_error, 0, "Obtained valid calcs to run without error");
    
    #  need to use the basedata object for these next few
    my @el_list1 = qw /15:15 15:25/;
    #my @el_list2 = qw /10_3 10_4/;
    my %elements = (
        element_list1 => \@el_list1,
        #element_list2 => \@el_list2,
    );

    #  run the global pre_calcs
    eval {$indices->run_precalc_globals(%$calc_args); print "\n"};
    $e = $EVAL_ERROR;
    ok (!$e, 'pre_calc_globals had no eval errors');

    my %sp_calc_values = eval {$indices->run_calculations(%$calc_args, %elements)};
    $e = $EVAL_ERROR;
    ok (!$e, 'run_calculations had no eval errors');
    diag $e if $e;

    eval {$indices->run_postcalc_globals (%$calc_args)};
    $e = $EVAL_ERROR;
    ok (!$e, 'run_postcalc_globals had no eval errors');
    
    #  this should throw an exception
    my %results = eval {
        $indices->run_calculations(
            calculations  => ['calc_abc'],
            element_list1 => ['1000:1000'],
        );
    };
    $e = $EVAL_ERROR;
    ok ($e, 'calc_abc with non-existent group throws error');
    
    $valid_calcs = eval {
        $indices->get_valid_calculations (
            calculations   => [qw /calc_richness calc_abc calc_abc2 calc_abc3/],
            nbr_list_count => 1,
        );
    };
    $e = $EVAL_ERROR;
    $valid_calcs = $indices->get_valid_calculations_to_run;
    is (scalar keys %$valid_calcs, 0, 'no valid calculations without required args');
    
}

sub test_metadata {
    my $indices = eval {Biodiverse::Indices->new(BASEDATA_REF => $bd)};
    #my %calculations = eval {$indices->get_calculations_as_flat_hash};

    my $pfx = 'get_metadata_';
    my $x = $indices->get_subs_with_prefix (prefix => $pfx);
    
    my %meta_keys;

    my (%names, %descr, %indices, %index_descr, %subs_with_no_indices);
    foreach my $meta_sub (keys %$x) {
        my $calc = $meta_sub;
        $calc =~ s/^$pfx//;

        my $metadata = $indices->get_metadata (sub => $calc);
        my $name = $metadata->get_name;
        $names{$name}{$meta_sub}++;

        $descr{$metadata->get_description}{$meta_sub}++;
        my $indices_this_sub = $metadata->get_indices // {};
        foreach my $index (keys %$indices_this_sub) {
            $indices{$index}{$meta_sub}++;
            #  duplicate index descriptions are OK
            #my $index_desc = $metadata->{indices}{$index}{description};
            #$index_descr{$index_desc}++;
        }
        if (!scalar keys %$indices_this_sub) {
            $subs_with_no_indices{$calc} ++;
        }
        
        @meta_keys{keys %$metadata} = (1) x scalar keys %$metadata;
    }

    subtest 'No duplicate names' => sub {
        check_duplicates (\%names);
    };
    subtest 'No duplicate descriptions' => sub {
        check_duplicates (\%descr);
    };
    subtest 'No duplicate index names' => sub {
        check_duplicates->(\%indices);
    };
#    Duplicate index descriptions are OK.  
#    subtest 'No duplicate index descriptions' => sub {
#        check_duplicates->(\%index_descr);
#    };

    TODO:
    {
        my $todo = todo 'Need to first sort out indices which are simply swiped '
        . 'from an inner sub, which vary depending on inputs, '
        . 'and which ones are post_calcs and post_calc_globals';
        #  group and label prop data and hashes depend on inputs => no props = no indices
        ok (
            not scalar keys %subs_with_no_indices,
            'All calc metadata subs specify their indices',
        );
        #if (scalar keys %subs_with_no_indices) {
        #    diag 'Indices with no subs are: ' . join ' ', sort keys %subs_with_no_indices;
        #}
    }

    #diag 'Metadata keys are ' . join ' ', sort keys %meta_keys;
}

sub check_duplicates {
    my $hashref = shift;
    foreach my $key (sort keys %$hashref) {
        my $count = scalar keys %{$hashref->{$key}};
        my $res = is ($count, 1, "$key is unique");
        if (!$res) {
            diag "Source calcs for $key are: " . join ' ', sort keys %{$hashref->{$key}};
        }
    }
    foreach my $null_key (qw /no_name no_description/) {
        my $res = ok (!exists $hashref->{$null_key}, "hash does not contain $null_key");
        if (exists $hashref->{$null_key}) {
            diag "Source calcs for $null_key are: " . join ' ', sort keys %{$hashref->{$null_key}};
        }
    }    
    
}



sub test_non_numeric_returns_no_results {
    my @calcs_to_test = qw /
        calc_numeric_label_data
        calc_numeric_label_dissimilarity
        calc_numeric_label_other_means
        calc_numeric_label_quantiles
        calc_numeric_label_stats
        calc_num_labels_gistar
    /;

    my %bd_args = (
        x_spacing   => 1,
        y_spacing   => 1,
        CELL_SIZES  => [1, 1],
        x_max       => 3,
        y_max       => 3,
        x_min       => 1,
        y_min       => 1,
    );

    my $bd = get_basedata_object (%bd_args);
    my $sp = $bd->add_spatial_output (name => 'sp_non_numeric');
    my $success = eval {
        $sp->run_analysis (
            spatial_conditions => ['sp_self_only'],
            calculations => \@calcs_to_test,
        );
    };
    my $e = $@;
    
    ok (!$success, "No numeric labels calculations run when given non-numeric data");

    ok ($e =~ 'No valid analyses, dropping out', 'Analysis threw no valid calculations error');
}

#  ensure we can run indices with label_lists
#  and label_hashes instead of element_lists
sub test_calc_abc_with_label_lists {
    my @labels = ('a'..'d');
    my %label_hash;
    @label_hash{@labels} = (1) x @labels;
    my $target_richness = @labels;

    my $bd   = Biodiverse::BaseData->new (
        NAME       => 'indices using label lsts',
        CELL_SIZES => [1],
    );
    
    foreach my $gp (1..3) {
        foreach my $lb (@labels) {
            $bd->add_element (group => $gp, label => $lb);
        }
    }
    
    my $indices_object = Biodiverse::Indices->new(
        BASEDATA_REF => $bd,
        NAME         => 'Indices for calc_abc with label lists check',
    );
    
    my %args = (
        calculations   => ['calc_richness'],
    );
    $indices_object->get_valid_calculations (
        %args,
        nbr_list_count => 1,
        element_list1  => [],  #  for validity checking only
        element_list2  => undef,
        processing_element => 'x',
    );
    my $valid_calcs = scalar $indices_object->get_valid_calculations_to_run;
    my $indices_reqd_args = $indices_object->get_required_args_as_flat_array(calculations => $valid_calcs);
    
    my %res;
    ok(
       lives {
            %res = $indices_object->run_calculations(
                label_list1 => [@labels],
                processing_element => $labels[0],
            )
       },
       "did not die"
    ) or note($@);
    
    is ($res{RICHNESS_ALL},
        $target_richness,
        'got correct richness score using label_list1',
    );

    undef %res;
    ok(
       lives {
            %res = $indices_object->run_calculations(
                label_hash1 => \%label_hash,
                processing_element => $labels[0],
            )
       },
       "did not die"
    ) or note($@);
    is ($res{RICHNESS_ALL},
        $target_richness,
        'got correct richness score using label_hash1',
    );
    
    undef %res;
    ok(
       dies {
            %res = $indices_object->run_calculations(
                label_list1 => \%label_hash,
                processing_element => $labels[0],
            )
       },
       "died on incorrect ref type for label_list1 argument"
    ) or note($@);
    
    ok (!exists $res{RICHNESS_ALL},
        'no richness score when using incorrect ref type',
    );

}