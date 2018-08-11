#!/usr/bin/perl -w
use 5.010;
use strict;
use warnings;

use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;
use Scalar::Util qw /blessed/;

use Test::Lib;
use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

#use Test::More tests => 5;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::TestHelpers qw /:basedata/;

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

    foreach my $sub (sort @test_subs) {
        no strict 'refs';
        $sub->();
    }

    done_testing;
    return 0;
}



#  check the metadata
#  we just want no warnings raised here?
sub test_metadata {
    my $bd = Biodiverse::BaseData->new (CELL_SIZES => [1, 1]);
    $bd->add_element (group => '0.5:0.5', label => 'a');
    
    my $metadata = $bd->get_groups_ref->get_metadata (sub => 'export');
    #  not a very good test...
    ok (blessed ($metadata), 'basestruct export metadata is blessed');
}


# delimited text
sub test_delimited_text {
    my $e;  #  for eval errors;

    #  need to test array lists - need numeric labels data set for those
    my $num_bd = get_basedata_object (
        CELL_SIZES => [2, 2],
        x_spacing => 1,
        y_spacing => 1,
        x_max     => 10,
        y_max     => 10,
        x_min     => 0,
        y_min     => 1,
        numeric_labels => 1,
    );
    my $num_sp = $num_bd->add_spatial_output (name => 'Numeric blah blah');
    $num_sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => ['calc_numeric_label_data'],
    );
    
    my $gp = $num_bd->get_groups_ref;

    #  now make a basestruct with a symmetric list to export
    my $sp = $num_bd->add_spatial_output (name => 'Blahblah');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => ['calc_richness'],
    );
    
    
    my @arg_combinations;
    foreach my $symmetric (0, 1) {
        foreach my $one_value_per_line (0, 1) {
            foreach my $no_element_array (0, 1) {
                foreach my $quote_element_name (0, 1) {
                    push @arg_combinations,
                        {
                            symmetric           => $symmetric,
                            one_value_per_line  => $one_value_per_line,
                            no_element_array    => $no_element_array,
                            quote_element_names => $quote_element_name,
                        };
                }
            }
        }
    }
    
    foreach my $args_hash (@arg_combinations) {
        #  asymmetric list
        run_basestruct_export_to_table (
            basestruct => $gp,
            list       => 'SUBELEMENTS',
            %$args_hash,
        );
        #  symmetric list
        run_basestruct_export_to_table (
            basestruct => $sp,
            list       => 'SPATIAL_RESULTS',
            %$args_hash,
        );
        run_basestruct_export_to_table (
            basestruct => $num_sp,
            list       => 'NUM_DATA_ARRAY',
            %$args_hash,
        );
    }
}



sub test_quoting {
    my $bd = get_basedata_object (
        CELL_SIZES => [2, 2],
        x_spacing => 1,
        y_spacing => 1,
        x_max     => 10,
        y_max     => 10,
        x_min     => 0,
        y_min     => 1,
    );
    my $gps = $bd->get_groups_ref;

    #  now make a basestruct with a symmetric list to export
    my $sp = $bd->add_spatial_output (name => 'Blahblah');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => ['calc_richness'],
    );

    my $table;

    $table = $gps->to_table (
        list   => 'SUBELEMENTS',
        quote_element_names_and_headers => 1,
    );
    table_headers_and_elements_are_quoted($table, 'SUBELEMENTS');

    $table = $gps->to_table (
        list   => 'SUBELEMENTS',
        symmetric => 0,  #  export defaults to symmetric, so override to test
        quote_element_names_and_headers => 1,
    );
    table_headers_and_elements_are_quoted($table, 'SUBELEMENTS');

    $table = $sp->to_table (
        list   => 'SPATIAL_RESULTS',
        quote_element_names_and_headers => 1,
    );
    table_headers_and_elements_are_quoted($table, 'SPATIAL_RESULTS');

}


sub test_multiple_lists {
    my $bd = get_basedata_object (
        CELL_SIZES => [2, 2],
        x_spacing => 1,
        y_spacing => 1,
        x_max     => 6,
        y_max     => 6,
        x_min     => 0,
        y_min     => 1,
    );
    my $gps = $bd->get_groups_ref;

    #  now make a basestruct with a symmetric and asymmetric list to export
    my $sp = $bd->add_spatial_output (name => 'Blahblah');
    $sp->run_analysis (
        spatial_conditions => ['sp_square_cell(size => 3)'],
        calculations       => [qw /calc_richness calc_element_lists_used/],
    );
    
    #  set up some additional lists
    foreach my $element ($sp->get_element_list) {
        my $list_ref = $sp->get_list_ref (
            element => $element,
            list    => 'SPATIAL_RESULTS',
            autovivify => 0,
        );
        my %dup_hash  = map {($_.'_DUP') => $list_ref->{$_}} keys %$list_ref;
        $sp->add_to_hash_list (
            element => $element,
            list    => 'SPATIAL_RESULTS_NO_DUP_KEYS',
            %dup_hash,
        );
        my %dup_hash2 = map {$_ => $list_ref->{$_}} keys %$list_ref;
        $sp->add_to_hash_list (
            element => $element,
            list    => 'SPATIAL_RESULTS_DUP_KEYS',
            %dup_hash2,
        );
        my $el_list_ref = $sp->get_list_ref (
            element => $element,
            list    => 'EL_LIST_SET1',
            autovivify => 0,
        );
        $sp->add_to_hash_list (
            element => $element,
            list    => 'EL_LIST_SET1_DUP_KEYS',
            %$el_list_ref,
        );
    }

    my (@expected, $table);
    $table = $sp->to_table (
        list_names => [qw /EL_LIST_SET1 SPATIAL_RESULTS/],
    );
    @expected
      = map {[split ',', $_]}
        split "[\r\n]+",
        get_data_section ('asym_table_two_lists');
    is_deeply($table, \@expected, 'asymmetric table matches for two lists');

    $table = $sp->to_table (
        list_names => [qw /EL_LIST_SET1 SPATIAL_RESULTS/],
        symmetric  => 1,
    );
    @expected
      = map {[split ',', $_]}
        split "[\r\n]+",
        get_data_section ('asym_to_sym_table_two_lists');
    #  clean up the undefs
    foreach my $i (0 .. $#expected) {
        @{$expected[$i]} = map {$_ eq '' ? undef : $_} @{$expected[$i]};
    }
    is_deeply($table, \@expected, 'asymmetric table matches for two lists');
    
    #  now the symmetric lists
    $table = $sp->to_table (
        list_names => [qw /SPATIAL_RESULTS SPATIAL_RESULTS_NO_DUP_KEYS/],
        symmetric  => 1,
    );
    @expected
      = map {[split ',', $_]}
        split "[\r\n]+",
        get_data_section ('sym_table_two_lists');
    is_deeply($table, \@expected, 'symmetric table matches for two lists');

    $table = eval {
        $sp->to_table (
            list_names => [qw /SPATIAL_RESULTS SPATIAL_RESULTS_DUP_KEYS/],
            symmetric  => 1,
        );
    };
    my $e = $EVAL_ERROR;
    ok ($e, 'errored when duplicate keys passed to to_table under symmetric mode');

    $table = eval {
        $sp->to_table (
            list_names => [qw /EL_LIST_SET1 EL_LIST_SET1_DUP_KEYS/],
            symmetric  => 1,
        );
    };
    $e = $EVAL_ERROR;
    ok ($e, 'errored when duplicate keys passed to to_table under asym to symmetric mode');

    ##  for test data generation
    #foreach my $line (@$table) {
    #    say join ',', map {$_ // ''} @$line;
    #}
}

sub table_headers_and_elements_are_quoted {
    my ($table, $extra_feedback) = @_;
    $extra_feedback //= '';

    my $re_is_quoted = qr /^'[^']+'$/;
    
    subtest 'Headers and element names are quoted' => sub {
        my $header = $table->[0];
        foreach my $field_name (@$header) {  #  first three are not quoted - should we?
            ok ($field_name =~ $re_is_quoted, "$field_name is quoted, $extra_feedback");
        }
        foreach my $line (@$table[1..$#$table]) {
            ok ($line->[0] =~ $re_is_quoted, "element name $line->[0] is quoted, $extra_feedback");
        }
    };

    return;
}


sub run_basestruct_export_to_table {
    my %args = @_;

    my $gp = $args{basestruct};

    my $e;

    my $symmetric_feedback = $args{symmetric} ? 'symmetric' : 'non-symmetric';
    my %feedback = %args;
    delete @feedback{qw /basestruct/};
    my $feedback_text;
    foreach my $key (sort keys %feedback) {
        my $val = $feedback{$key};
        $feedback_text .= "$key => $val, ";
    }
    $feedback_text =~ s/, $//;
    
    my $filename1 = get_temp_file_path('biodiverse_export_test_XXXXX.csv');

    eval {
        $gp->export_table_delimited_text (
            %args,
            file => $filename1,
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;

    ok (!$e, "Exported file without raising exception, using file handle, $feedback_text");
    
    my $filename2 = get_temp_file_path('biodiverse_export_test_XXXXX.csv');

    eval {
        $gp->export_table_delimited_text (
            %args,
            file   => $filename2,
            _no_fh => 1,
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;

    ok (!$e, "Exported to file without raising exception, not using file handle, $feedback_text");

    #  Now compare the two files.  They should be identical.  
    {
        local $/ = undef;  #  slurp mode
        open my $fh1, '<', $filename1 or croak "Could not open $filename1";
        open my $fh2, '<', $filename2 or croak "Could not open $filename2";
        
        my $file1 = <$fh1>;
        my $file2 = <$fh2>;
        
        is ($file1, $file2, 'Exported files match');
        
        if (0) {
            print STDERR "\n\n$feedback_text\n";
            foreach my $string ($file1, $file2) {
                my @array = split "\n", $file2, 4;
                pop @array;
                print STDERR "\n\n---\n" . join ("\n", @array) . "\n\n---\n";
            }
        }
    }
}

done_testing();

1;

__DATA__

@@ sym_table_two_lists
ELEMENT,Axis_0,Axis_1,RICHNESS_ALL,RICHNESS_SET1,RICHNESS_ALL_DUP,RICHNESS_SET1_DUP
1:1,1,1,12,12,12,12
1:3,1,3,20,20,20,20
1:5,1,5,20,20,20,20
1:7,1,7,12,12,12,12
3:1,3,1,18,18,18,18
3:3,3,3,30,30,30,30
3:5,3,5,30,30,30,30
3:7,3,7,18,18,18,18
5:1,5,1,15,15,15,15
5:3,5,3,25,25,25,25
5:5,5,5,25,25,25,25
5:7,5,7,15,15,15,15
7:1,7,1,9,9,9,9
7:3,7,3,15,15,15,15
7:5,7,5,15,15,15,15
7:7,7,7,9,9,9,9

@@ asym_to_sym_table_two_lists
ELEMENT,Axis_0,Axis_1,1:1,1:3,1:5,1:7,3:1,3:3,3:5,3:7,5:1,5:3,5:5,5:7,7:1,7:3,7:5,7:7,RICHNESS_ALL,RICHNESS_SET1
'1:1',1,1,1,1,,,1,1,,,,,,,,,,,12,12
'1:3',1,3,1,1,1,,1,1,1,,,,,,,,,,20,20
'1:5',1,5,,1,1,1,,1,1,1,,,,,,,,,20,20
'1:7',1,7,,,1,1,,,1,1,,,,,,,,,12,12
'3:1',3,1,1,1,,,1,1,,,1,1,,,,,,,18,18
'3:3',3,3,1,1,1,,1,1,1,,1,1,1,,,,,,30,30
'3:5',3,5,,1,1,1,,1,1,1,,1,1,1,,,,,30,30
'3:7',3,7,,,1,1,,,1,1,,,1,1,,,,,18,18
'5:1',5,1,,,,,1,1,,,1,1,,,1,1,,,15,15
'5:3',5,3,,,,,1,1,1,,1,1,1,,1,1,1,,25,25
'5:5',5,5,,,,,,1,1,1,,1,1,1,,1,1,1,25,25
'5:7',5,7,,,,,,,1,1,,,1,1,,,1,1,15,15
'7:1',7,1,,,,,,,,,1,1,,,1,1,,,9,9
'7:3',7,3,,,,,,,,,1,1,1,,1,1,1,,15,15
'7:5',7,5,,,,,,,,,,1,1,1,,1,1,1,15,15
'7:7',7,7,,,,,,,,,,,1,1,,,1,1,9,9

@@ asym_table_two_lists
ELEMENT,Axis_0,Axis_1,Value
1:1,1,1,1:1,1,1:3,1,3:1,1,3:3,1,RICHNESS_ALL,12,RICHNESS_SET1,12
1:3,1,3,1:1,1,1:3,1,1:5,1,3:1,1,3:3,1,3:5,1,RICHNESS_ALL,20,RICHNESS_SET1,20
1:5,1,5,1:3,1,1:5,1,1:7,1,3:3,1,3:5,1,3:7,1,RICHNESS_ALL,20,RICHNESS_SET1,20
1:7,1,7,1:5,1,1:7,1,3:5,1,3:7,1,RICHNESS_ALL,12,RICHNESS_SET1,12
3:1,3,1,1:1,1,1:3,1,3:1,1,3:3,1,5:1,1,5:3,1,RICHNESS_ALL,18,RICHNESS_SET1,18
3:3,3,3,1:1,1,1:3,1,1:5,1,3:1,1,3:3,1,3:5,1,5:1,1,5:3,1,5:5,1,RICHNESS_ALL,30,RICHNESS_SET1,30
3:5,3,5,1:3,1,1:5,1,1:7,1,3:3,1,3:5,1,3:7,1,5:3,1,5:5,1,5:7,1,RICHNESS_ALL,30,RICHNESS_SET1,30
3:7,3,7,1:5,1,1:7,1,3:5,1,3:7,1,5:5,1,5:7,1,RICHNESS_ALL,18,RICHNESS_SET1,18
5:1,5,1,3:1,1,3:3,1,5:1,1,5:3,1,7:1,1,7:3,1,RICHNESS_ALL,15,RICHNESS_SET1,15
5:3,5,3,3:1,1,3:3,1,3:5,1,5:1,1,5:3,1,5:5,1,7:1,1,7:3,1,7:5,1,RICHNESS_ALL,25,RICHNESS_SET1,25
5:5,5,5,3:3,1,3:5,1,3:7,1,5:3,1,5:5,1,5:7,1,7:3,1,7:5,1,7:7,1,RICHNESS_ALL,25,RICHNESS_SET1,25
5:7,5,7,3:5,1,3:7,1,5:5,1,5:7,1,7:5,1,7:7,1,RICHNESS_ALL,15,RICHNESS_SET1,15
7:1,7,1,5:1,1,5:3,1,7:1,1,7:3,1,RICHNESS_ALL,9,RICHNESS_SET1,9
7:3,7,3,5:1,1,5:3,1,5:5,1,7:1,1,7:3,1,7:5,1,RICHNESS_ALL,15,RICHNESS_SET1,15
7:5,7,5,5:3,1,5:5,1,5:7,1,7:3,1,7:5,1,7:7,1,RICHNESS_ALL,15,RICHNESS_SET1,15
7:7,7,7,5:5,1,5:7,1,7:5,1,7:7,1,RICHNESS_ALL,9,RICHNESS_SET1,9

