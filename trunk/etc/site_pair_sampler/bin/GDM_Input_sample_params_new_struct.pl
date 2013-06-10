#!/usr/bin/perl -w

#  This script runs the phylo_sorenson index to comapre pairs of groups
#  The results are returned as a .csv file with 5 columns to define the two grid squares and
#  the phylo_sorenson distance between them.

#  It reads in a Biodiverse basedata object for the gridded species locations, a nexus
#  file with one of more trees, and a remap table to link the taxon names on the tree to
#  names in the spatial data

#  If the nexus file has multiple trees, multiple results files are generated.

use 5.010;
use strict;
use warnings;
use Carp;  #  warnings and dropouts
use English qw { -no_match_vars };

#  add the lib folder if needed
use rlib;
use lib '../../../lib';  #  until we move the site pair sampler to the main bin/lib folders

#  need this for the pp build to work
if ($ENV{BDV_PP_BUILDING}) {
    use FindBin qw ( $Bin );
    say 'Building pp file';
    use File::BOM qw / :subs /;          #  we need File::BOM.
    open my $fh, '<:via(File::BOM)', $0  #  just read ourselves
      or croak "Cannot open $Bin via File::BOM\n";
    $fh->close;
    exit ;
}

use BdPD::GenerateDistanceTable qw /:all/;

#  load up the user defined libs and settings
use Biodiverse::Config;

#  don't buffer text output - output to screen as we go
local $OUTPUT_AUTOFLUSH = 1;

my $args_file = $ARGV[0];

my %dist_args = parse_args_file ($args_file);

print "\n\nStarting site pair process\n";

generate_distance_table(%dist_args);

print "\n Script finished.\n";