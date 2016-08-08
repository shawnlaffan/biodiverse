#!/usr/bin/perl -w
use strict;
use warnings;
use 5.010;

local $| = 1;

use rlib;

use Carp;
use English qw { -no_match_vars };

use Biodiverse::BaseData;

use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'basedata|bd=s',     'Input basedata file', { required => 1 } ],
  [ 'output_prefix|opfx=s', 'The output prefix for exported files', {default => undef}],
  [ 'format|f:s', 'Export format', { default => 'Delimited text'}],
  [ 'suffix|s:s', 'Suffix to use', { default => '' } ],
  [],
  [ 'help',       "print usage message and exit" ],
);

if ($opt->help) {
    print($usage->text);
    exit;
}

#  need to use GetOpt::Long or similar
my $bd_file     = $opt->basedata;
my $out_prefix  = $opt->output_prefix;
my $out_suffix  = $opt->suffix;
my $export_type = $opt->format;

my $dots = qr /\.(?!bds)/;

die 'No basedata files satisfy glob condition'
  if !-e $bd_file;

my $bd = Biodiverse::BaseData->new(file => $bd_file);
my $bd_name = $bd_file;
$bd_name =~ s/\.bds$//;

if (!defined $out_prefix) {
    $out_prefix = $bd_name;
    $out_prefix =~ s/\.bds$//;
}

foreach my $sp ($bd->get_spatial_output_refs) {
    my @lists = $sp->get_lists_across_elements;
    foreach my $list_name (@lists) {
        my $filename = join '_', $sp->get_name, $list_name;
        if (length $out_prefix) {
            $filename = $out_prefix . '_' . $filename;
        }
        if (length $out_suffix) {
            $filename .= ".$out_suffix";
        }

        $filename =~ s/_$//;
        $filename =~ s/>>/--/g;   # handle invalid chars from randomisations

        $sp->export (
            format => $export_type,
            file => $filename,
            list => $list_name,
        );
    }
}

print "";  #  for debugger
