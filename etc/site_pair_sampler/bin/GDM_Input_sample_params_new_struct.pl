#!/usr/bin/perl -w

#  This script runs the phylo_sorenson index to comapre pairs of groups
#  The results are returned as a .csv file with 5 columns to define the two grid squares and
#  the phylo_sorenson distance between them.

#  It reads in a Biodiverse basedata object for the gridded species locations, a nexus
#  file with one of more trees, and a remap table to link the taxon names on the tree to
#  names in the spatial data

#  If the nexus file has multiple trees, multiple results files are generated.

use strict;
use warnings;
use Carp;  #  warnings and dropouts
use English qw { -no_match_vars };

#  add the lib folder if needed
use rlib;
use lib '../../../lib';  #  until we move the site pair sampler to the main bin/lib folders

use BdPD::GenerateDistanceTable qw /:all/;

#  load up the user defined libs and settings
use Biodiverse::Config;

#  don't buffer text output - output to screen as we go
local $OUTPUT_AUTOFLUSH = 1;

my $args_file = $ARGV[0];

my %dist_args = parse_args_file ($args_file);

print "\n\nStarting site pair process\n";

#BdPD::GDM_Input_standard::generate_distance_table(%dist_args);
generate_distance_table(%dist_args);

print "\n Script finished.\n";