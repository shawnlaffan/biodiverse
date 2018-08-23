#!/usr/bin/perl -w
use strict;
use warnings;
use 5.010;

use rlib;

use Getopt::Long::Descriptive;
 
use Carp;
use English qw { -no_match_vars };

use Text::CSV_XS;
use Scalar::Util qw /looks_like_number/;
use Biodiverse::BaseData;

#  need this for the exe building process to work
exit 0 if $ENV{BDV_PP_BUILDING};


my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'input_file|i=s',    'The input file (sites by values matrix', { required => 1 } ],
  [ 'output_prefix|o=s', 'The output prefix for exported files (name will contain prefix and column)', { required => 1 }],
  [ 'cellsize|c=s',      'The cellsize of the basedata object', { required => 1 } ],
  [ 'nodata|n=s',        'Nodata value' ],
  [],
  [ 'help',       "print usage message and exit" ],
);

if ($opt->help) {
    print($usage->text);
    exit;
}

my $in_file     = $opt->input_file;
my $out_pfx     = $opt->output_prefix;
my $cellsize    = $opt->cellsize;
my $no_data_value = $opt->nodata;

#####################################
#  import the data

my $temp_bd = Biodiverse::BaseData->new(
    CELL_SIZES => [1,1],
);

open my $fh, '<', $in_file or die $!;
my $check_str;
for (1..10) {
    $check_str .= <$fh>;
}
$fh->seek (0, 0);

my $sep_char = $temp_bd->guess_field_separator (
    string => $check_str,  
);
my $quote_char = $temp_bd->guess_quote_char (
    string => $check_str,
);
my $csv = Text::CSV_XS->new ({
    sep_char   => $sep_char,
    quote_char => $quote_char,
});
my $header = $csv->getline($fh);
$fh->close;

say join ' ', @$header;

my $agg_bd = Biodiverse::BaseData->new (
    CELL_SIZES => [$cellsize, $cellsize],
    NAME => 'Aggregator bd',
);
my $agg_bs = Biodiverse::BaseStruct->new (
    NAME => 'Aggregator bs',
    CELL_SIZES => [$cellsize, $cellsize],
    BASEDATA_REF => $agg_bd,
);
my %lists_to_export;

my $start_col  = 4;
my $group_cols = [1,2];
my $sample_count_cols = [3];

foreach my $col_num ($start_col .. $#$header) {
    my $col_name = $header->[$col_num];
    
    my $bd = Biodiverse::BaseData->new(
        CELL_SIZES => [$cellsize, $cellsize],
    );
    my $success = eval {
        $bd->import_data (
            input_files => [$in_file],
            label_columns => [$col_num],
            group_columns => [@$group_cols],
            sample_count_columns => $sample_count_cols,
            quotes   => $quote_char,
            sep_char => $sep_char,
        );
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    #  we could strip any non-numeric label
    my $labels = $bd->get_labels;
    my @to_delete = grep {!looks_like_number $_} @$labels;
    if (defined $no_data_value && looks_like_number $no_data_value) {
        push @to_delete, $no_data_value;
    }
    $bd->delete_labels (labels => \@to_delete);
    
    
    #####################################
    #  analyse the data
    
    #  need to build a spatial index if we do anything more complex than single cell analyses
    #  $bd->build_spatial_index (resolutions => [$bd->get_cell_sizes]);
    
    #  add to as needed, possibly using args later on
    my $calculations = [qw/
        calc_numeric_label_stats
    /];
    
    my $sp = $bd->add_spatial_output (name => 'spatial_analysis');
    $success = eval {
        $sp->run_analysis (
            calculations       => $calculations,
            spatial_conditions => ['sp_self_only()'],
        );
    };
    croak $EVAL_ERROR if $EVAL_ERROR;
    
    #  adds the .bds extension by default
    $bd->save (
        filename => $out_pfx . '_' . $col_name,
        method   => 'save_to_storable',  #  avoid sereal version issues
    );
    
    foreach my $group ($sp->get_element_list) {
        my $list = $sp->get_list_ref (
            element => $group,
            list    => 'SPATIAL_RESULTS',
        );
        $agg_bs->add_element (element => $group);
        foreach my $stats_col_name (keys %$list) {
            $agg_bs->add_to_hash_list (
                element => $group,
                list    => $stats_col_name,
                $col_name => $list->{$stats_col_name},
            );
            $lists_to_export{$stats_col_name} //= 1;
        }
    }
    #  export the files
    #$sp->export (
    #    format => 'Delimited text',
    #    file   => $out_pfx . '_' . $col_name . '.csv',
    #    list   => 'SPATIAL_RESULTS',
    #);

}


foreach my $list_name (keys %lists_to_export) {
    $agg_bs->export (
        format => 'Delimited text',
        file   => $out_pfx . '_' . $list_name . '.csv',
        list   => $list_name,
        no_data_value => $no_data_value,
    );
}


say 'Completed';
