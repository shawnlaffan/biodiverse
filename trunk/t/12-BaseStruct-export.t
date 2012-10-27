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

# delimited text
{
    my $e;  #  for eval errors;
    #  a dirty way of getting a basestruct - the groups object from a basedata
    my $bd = get_basedata_object_from_site_data (
        CELL_SIZES => [100000, 100000],
    );

    my $gp = $bd->get_groups_ref;
    
    foreach my $symmetric (0, 1) {
        run_basestruct_export_to_table (
            basestruct => $gp,
            symmetric  => $symmetric,
            list       => 'SUBELEMENTS',
        );
    }

    #  now make a basestruct with a symmetric list to export
    my $sp = $bd->add_spatial_output (
        name => 'Blahblah',
    );
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => ['calc_richness'],
    );
    run_basestruct_export_to_table (
        basestruct => $sp,
        list       => 'SPATIAL_RESULTS',
        symmetric  => 1,
    );


}

sub run_basestruct_export_to_table {
    my %args = @_;

    my $gp = $args{basestruct};

    my $e;

    my $symmetric_feedback = $args{symmetric} ? "symmetric" : "non-symmetric";

    my %file_temp_args = (
        TEMPLATE => 'export_test_XXXXX',
        SUFFIX   => '.csv',
        UNLINK   => 0,
    );

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

    ok (!$e, "Exported to $symmetric_feedback file without raising exception, using file handle");
    
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

    ok (!$e, "Exported to $symmetric_feedback file without raising exception, not using file handle");

    #  now compare the two files
    {
        local $/ = undef;  #  slurp mode
        open my $fh1, '<', $filename1 or croak "Could not open $filename1";
        open my $fh2, '<', $filename2 or croak "Could not open $filename2";
        
        my $file1 = <$fh1>;
        my $file2 = <$fh2>;
        
        is ($file1, $file2, 'Exported files match');
    }
}

done_testing();

1;

__DATA__

