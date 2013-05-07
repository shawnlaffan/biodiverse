#!/usr/bin/perl -w
use strict;
use warnings;
use 5.010;

use Getopt::Long;

use Carp;
use English qw { -no_match_vars };

use Biodiverse::BaseData;

my $bd_file;
my $out_file;
my $remap_file;
my $input_cols_str    = '1';
my $remapped_cols_str = '1,2';
my $input_sep_char    = q{,};
my $input_quote_char     = q{"};

GetOptions(
    'basedata|bd_file=s' => \$bd_file,
    'out_file=s'         => \$out_file,
    'remap_file=s'       => \$remap_file,
    'input_cols=s'       => \$input_cols_str,
    'remapped_cols=s'    => \$remapped_cols_str,
    'input_sep_char=s'   => \$input_sep_char,
    'input_quote_char=s' => \$input_quote_char,
);


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

