#!/usr/bin/perl -w
use strict;
use warnings;
use 5.010;

use rlib;

use Carp;
use English qw { -no_match_vars };

use Biodiverse::BaseData;

#  need to use GetOpt::Long or similar
my $glob        = $ARGV[0] // '*.bds';
my $out_prefix  = $ARGV[1];
my $out_suffix  = $ARGV[2];
my $list_name   = $ARGV[3] // 'SPATIAL_RESULTS';
my $export_type = $ARGV[4] // 'ArcInfo floatgrid files';

my $strip = qr /data_50km_w_props_(.+)_analysed/;
my $dots = qr /\.(?!bds)/;

my @bd_files = grep {/bds$/} glob $glob;
die 'No files satisfy glob condition' if !scalar @bd_files;

if (!length $out_prefix) {
    $out_prefix = undef;
}

if (!length $out_suffix) {
    $out_suffix = undef;
}

foreach my $bd_file (@bd_files) {

    my $bd = Biodiverse::BaseData->new(file => $bd_file);
    my $bd_name = $bd_file;
    $bd_name =~ s/\.bds$//;

    foreach my $sp ($bd->get_spatial_output_refs) {
        my $filename = ($out_prefix // $bd_name) . '_' . ($out_suffix // $sp->get_param('NAME')) . '_' . $list_name;
        $filename =~ s/$strip/$1/;
        $filename =~ s/$dots//;
        $sp->export (format => $export_type, file => $filename, list => $list_name);
    }

    print "";  #  for debugger
}
