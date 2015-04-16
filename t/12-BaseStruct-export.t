#!/usr/bin/perl -w
use strict;
use warnings;

use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;

use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

#use Test::More tests => 5;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::TestHelpers qw /:basedata/;


my %file_temp_args = (
    TEMPLATE => "biodiverse_export_test_XXXXX",
    SUFFIX   => '.csv',
    UNLINK   => 0,
);


# delimited text
{
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



{
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

    my $tmp_obj1  = File::Temp->new (%file_temp_args);
    my $filename1 = $tmp_obj1->filename;
    undef $tmp_obj1;  # we just wanted the name, and we'll overwrite it

    $gps->export_table_delimited_text (
        file   => $filename1,
        list   => 'SUBELEMENTS',
        quote_element_names_and_headers => 1,
    );
    headers_and_elements_are_quoted($filename1, 'SUBELEMENTS');

    $gps->export_table_delimited_text (
        file   => $filename1,
        list   => 'SUBELEMENTS',
        symmetric => 0,  #  export defaults to symmetric, so override to test
        quote_element_names_and_headers => 1,
    );
    headers_and_elements_are_quoted($filename1, 'SUBELEMENTS');

    $sp->export_table_delimited_text (
        file   => $filename1,
        list   => 'SPATIAL_RESULTS',
        quote_element_names_and_headers => 1,
    );
    headers_and_elements_are_quoted($filename1, 'SPATIAL_RESULTS');

    unlink $filename1;
}

sub headers_and_elements_are_quoted {
    my ($filename, $extra_feedback) = @_;
    $extra_feedback //= '';

    open(my $fh, '<', $filename) or die "Cannot open $filename";
    
    my $header = <$fh>;
    chomp $header;
    my @header = split ',', $header;

    my $re_is_quoted = qr /^'[^']+'$/;
    
    subtest 'Headers and element names are quoted' => sub { 
        foreach my $field_name (@header) {  #  first three are not quoted - should we?
            ok ($field_name =~ $re_is_quoted, "$field_name is quoted, $extra_feedback");
        }
        while (my $line = <$fh>) {
            chomp $line;
            my @line = split ',', $line;
            ok ($line[0] =~ $re_is_quoted, "element name $line[0] is quoted, $extra_feedback");
        }
    };

    $fh->close;
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
    


    my $tmp_obj1  = File::Temp->new (%file_temp_args);
    my $filename1 = $tmp_obj1->filename;
    undef $tmp_obj1;  # we just wanted the name, and we'll overwrite it

    eval {
        $gp->export_table_delimited_text (
            %args,
            file => $filename1,
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;

    ok (!$e, "Exported file without raising exception, using file handle, $feedback_text");
    
    my $tmp_obj2  = File::Temp->new (%file_temp_args);
    my $filename2 = $tmp_obj2->filename;
    undef $tmp_obj2;  # we just wanted the name, and we'll overwrite it

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

    #  now clean up
    eval {unlink $filename1};
    eval {unlink $filename2};
}

done_testing();

1;

__DATA__

