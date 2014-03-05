#!/usr/bin/perl -w
use strict;
use warnings;
use 5.010;

use rlib;

use Getopt::Long::Descriptive;
 
use Carp;
use English qw { -no_match_vars };

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;


my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'input_dir|i=s',     'The folder containing the input rasters', { required => 1 } ],
  [ 'output_prefix|o=s', 'The output prefix for exported files', { required => 1 }],
  [ 'cellsize|c=s',      'The folder containing the input rasters', { required => 1 } ],
  [ 'name|n=s',          'The name of the basedata file', {required => 0} ],
  #[ 'remap_file|rf=s',       'The text file containing label remap details', { required => 1 } ],  #  needed later
  [],
  [ 'help',       "print usage message and exit" ],
);
 
if ($opt->help) {
    print($usage->text);
    exit;
}

my $in_folder   = $opt->input_dir;
my $out_pfx     = $opt->output_prefix;
#my $remap_file  = $opt->remap_file;
my $cellsize    = $opt->cellsize;
my $name        = $opt->name || $out_pfx;

my $file_suffix = 'flt';  #  change this to tif etc as needed

my $bd = eval {Biodiverse::BaseData->new(
    CELL_SIZES => [$cellsize, $cellsize],
)};
croak $@ if $@;

#  add this later
#my $remap = Biodiverse::ElementProperties->new();
#$remap->import_data (
#    file                  => $remap_file,
#    input_element_cols    => \@input_cols,
#    remapped_element_cols => \@remapped_cols,
#    input_sep_char        => $input_sep_char,
#    input_quote_char      => $input_quote_char,
#);


#####################################
#  import the data

my @files = glob "$in_folder/*.$file_suffix";

my $success = eval {
    $bd->import_data_raster (
        input_files     => \@files,
        labels_as_bands => 1,  #  use the bands (files) as the label (species) names
    );
};

#####################################
#  analyse the data

#  add to as needed, possibly using args later on
my $calculations = [qw/calc_endemism_whole calc_redundancy/];

my $sp = $bd->add_spatial_output (NAME => 'spatial_analysis');
my $success = eval {
        $sp->run_analysis (
        calculations       => $calculations,
        spatial_conditions => ['sp_self_onloy()'],
    );
};
croak $@ if $@;


#  adds the .bds extension by default
$bd->save (filename => $out_pfx);


#  export the files
$sp->export (
    format => 'ArcInfo asciigrid files',
    file   => $out_pfx,
    list   => 'SPATIAL_RESULTS',
);

say 'Completed';
