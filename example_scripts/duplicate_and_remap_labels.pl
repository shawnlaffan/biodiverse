#!/usr/bin/perl -w
use strict;
use warnings;
use 5.010;

#use Getopt::Long;
use Getopt::Long::Descriptive;
 
use Carp;
use English qw { -no_match_vars };

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'basedata|input_bd=s',  "the input basedata file", { required => 1 } ],
  [ 'out_file|output_bd=s', "the output basedata file", { required => 1 }],
  [ 'remap_file=s',         "the text file containing label remap details", { required => 1 } ],
  [ 'input_cols=s',         "the columns in the remap file that match the original labels", { default => '1' } ],
  [ 'remapped_cols=s',      "the columns in the remap file to generate the remapped labels", { default => '1,2' } ],
  [ 'input_sep_char=s',     "column separator character in the remap file", { default => q{,} } ],
  [ 'input_quote_char=s',   "quotes character in the remap file", { default => q{"} } ],
  [],
  [ 'help',       "print usage message and exit" ],
);
 
if ($opt->help) {
    print($usage->text);
    exit;
}

my $bd_file           = $opt->basedata;
my $out_file          = $opt->out_file;
my $remap_file        = $opt->remap_file;
my $input_cols_str    = $opt->input_cols;
my $remapped_cols_str = $opt->remapped_cols;
my $input_sep_char    = $opt->input_sep_char;
my $input_quote_char  = $opt->input_quote_char;



croak "no basedata file specified" if !defined $bd_file;
croak "no output file specified"   if !defined $out_file;
croak "no remap file specified"    if !defined $remap_file;

my $bd = Biodiverse::BaseData->new(file => $bd_file);

my @input_cols    = split ',', $input_cols_str;
my @remapped_cols = split ',', $remapped_cols_str;

my $remap = Biodiverse::ElementProperties->new();
$remap->import_data (
    file                  => $remap_file,
    input_element_cols    => \@input_cols,
    remapped_element_cols => \@remapped_cols,
    input_sep_char        => $input_sep_char,
    input_quote_char      => $input_quote_char,
);

