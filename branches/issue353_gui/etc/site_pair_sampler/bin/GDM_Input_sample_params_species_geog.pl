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

#use BdPD::GDM_Input_standard;
use BdPD::GDM_Input;

#  load up the user defined libs and settings
use Biodiverse::Config;

#  don't buffer text output - output to screen as we go
local $OUTPUT_AUTOFLUSH = 1;

# the parameters for this sub are passed as a hash with the following items:
#
#   FILE PARAMETERS
#
#   dist_measure
#                   - the name of the distance measure to use. Accepted options so far are single items or a list from:
#                       "phylo_sorenson"
#                       "sorenson"
#                       "geographic"
#                   - required
#
#   directory       - the working directory
#                   - required
#                   eg "C:\Working\Study_Taxa\Herps\Hylidae"
#
#   nexus_file      - the full name of a nexus file to use
#                   - required for phylo_sorenson
#                   eg "Hylid_tree_AustOct08.nex"
#
#   nexus_remap     - file name of a remap table to match tree names to taxon names in the basedata
#                   - optional
#                   eg "Translate_Hylid_Names_aug08.csv"
#
#   remap_input     - an array of column numbers in order needed, counting from 0 - to match names on tree
#                   - required if nexus_remap is given
#                   eg [3]
#
#   remap_output    - an array of column numbers in order needed, counting from 0 - to match taxon names in the basedata
#                   - required if nexus_remap is given
#                   eg [1]
#
#   basedata_file   - file name of the basedata object holding grouped taxon locations
#                   - required
#                   eg "Hylids_May09_001deg_5000"
#
#   basedata_suffix - basedata filename suffix
#                   - optional - defaults to .bds
#                   eg ".bds"
#
#   output_file_prefix
#                   - text to start the output file name - handy to organise files
#                   - optional - defaults to "phylo_dist_"
#                   eg "dist_table "
#
#   SAMPLING PARAMETERS
#
#   sample_count    - number of samples requested in output
#                   - optional - defaults to 100,000
#                   eg 50000
#
#   min_group_richness
#                   - minimum number of taxa is a group - groups with less than this number will not be used
#                   - optional - defaults to 0
#                   eg 3
#
#   min_group_samples
#                   - a minimum number of samples in a group, for it to be included even if it is below the minimum group richness
#                   - for example, a group has only 1 species, and the richness limit is set to 2.  But that single species has been
#                   - recorded there 5 times, so it may be appropriate not to dismiss it as simply undersampling.
#                   - if min_group_richness is 2 and min_group_samples is 3, this means exclude groups with only 1 species
#                   - unless they have 3 or more records.
#                   - unless the number of species in the group is below the min_group_richness threshold, min_group_samples is not considered
#                   - optional - defaults to 0
#                   eg 3
#
#   one_quota       - maximum proportion (range 0 to 1) of site pairs with a dissimilarity of one to be included.
#                     Once the quota is reached only site pairs with a lower dissimilarity are included in the output
#                   - optional - defaults to 1 (no quota)
#                   eg 0.15
#
#   bins_count      - number of bins to divide the 0 to 1 dissimilarity range into. Each bin will have as its target
#                     an equal proportion of the site pairs. 1 is treated as on of the classes.
#                     So if bins = 4, the classes will be: 0 - 0.3333, 0.3333 - 0.6667, 0.6667 - 0.9999, 1
#                     Each bin would have a quota of 0.25
#                   - optional - overrides one_quota if used, so no point giving both.
#                   eg 6
#
#   quota_dist_measure
#                   - if more than one distance measure is used, specify the one to be used for quotas the dissimilarity quotas
#                   - required if:
#                       - bins count > 0 or one quota is given a value < 1
#                         AND
#                       - more than one dist_measure is being used
#                       - defaults to the only, or first distance measure.  Because key order is unreliable, with multiple
#                           distance measures it is important to set this parameter explicitly
#
#   dist_limit
#                   - set a maximum distance for the quota_dist_measure.  If this is geographic, it is a simple diagonal, with no adjustment for curvature etc
#                   - site pairs beyond the limit will not be used
#
#   oversample_ratio
#                   - a multiplier to increase the total number of site pairs to sample, to find enough
#                     pairs to meet the conditions specified by one_quota and bins.
#                     may be estimated internally in the future
#                   - optional - defaults to 1
#
#   sample_by_regions
#                   - if 1 split sampling by regions, setting quotas for regions according to the parameter region_quota_strategy
#                   - if 0 ignore regions in sampling (but can still report the regions in the output)
#                   - optional - defaults to 1, meaning regions used in sampling if present
#
#   region_quota_strategy
#                   - chooses from different strategies to set the quota of site pairs to sample from each region pair
#                   - options available are:
#                       - 'equal' - divides the requested number of site pairs equally between all region pairs,
#                               allowing for a larger proportion of samples for within region site pairs, as set by
#                               the parameter within_region_ratio
#                       - 'log_richness' - divides the requested number of site pairs in proportion to sum of the logs of the
#                               species richness of the two regions + 1
#                   - optional - defaults to 'equal'
#
#   within_region_ratio
#                   - increases the site_pair quota for within regions, compared to between regions.  For example, if
#                       there are 80 regions, then a given region would have 1/80th of its comparison quota with each
#                       other region.  But if the within_region_ration is 8, then approximately 8/80th, or 1/10th of site 
#                       pairs would be within region.
#                   - optional - defaults to 1
#
#   subset_for_testing
#                   - a value between 0 and < 1 for a proportion of sites to be used for a separate set of site pairs for model testing
#                       a value of 1 would leave no sites left for the main (training) site pairs.
#                   - optional - defaults to 0 for no training data.
#
#   test_sample_ratio
#                   - by default, sites in the test set are used, on average, as frequently in the test site pairs, as sites in the training data
#                       are used in the training site pairs.
#                     This means, for example, that:
#                       if subset_for_testing is 0.2 there will be 1/4 times as many test sites as training sites, and 1/16 as many site pairs.
#                       if more test site pairs are required, a test_sample_ratio > 1 can be set, to increase the number of test site pairs.  This
#                       means that the frequency with which each site is sampled in the test site pairs is greater.
#                   - optional - defaults to 1
#
#   OUTPUT PARAMETERS
#
#   regions
#                   - if regions > 0, then two additional columns are added , giving the region for site 1 and site 2
#                   - the basedata must contain a 3rd parameter for each group, after X and Y, which defines the region.
#
#   region_header   - text to define the name of the regions columns - eg 'region', 'IBRA', 'vegtype', 'country'
#                   - only used if regions > 0
#                   - optional - defaults to 'region'
#
#   region_codes    - if region_codes = 1, then 2 columns give the region as an integer code from 1 to the number of regions
#                   - which have groups in them
#                   - optional - defaults to 0
#
#   species_sum     - if species_sum = 1 then an extra column contains the number sum of the number of species at the two sites, regardless of number shared.
#
#   FEEDBACK PARAMETERS
#    
#   verbosity       - sets the amount of text output reporting progress to the text window or log file 
#                   - 0 give only global progress - % to completion, total numbers of site pair comparisons tried, stored to file
#                   - 1 list numbers of site pairs to do, done
#                   - 2 summarise sampling parameters and outcome for each region pair
#                   - 3 give full progress for each region pair - this could be appropriate for no regions or a small number, or for debugging
#                   - optional - defaults to 1
#
#   feedback_table  - if > 0, then a table with a row of stats on sampling for each region pair, is produced
#
#   feedback_suffix
#                   - text to add to the filename for feedback

#############################################
######       SET PARAMETERS HERE       ######

my %dist_args;

%dist_args = (
    dist_measure => {
            sorenson        =>  1,   # the value (eg 1) can be anything, as long as the item exists
            geographic      =>  1,
    },
    directory               =>  'C:\Users\u3579238\Work\Study_Taxa\Herps\Hylidae',  # working directory
    basedata_file           =>  "Hylids_Feb10_001deg_5000_IBRA", # don't include suffix (eg .bds)
    output_file_prefix      =>  q{},
    sample_count            =>  100000,
    min_group_richness      =>  2,
    min_group_samples       =>  5,
    bins_count              =>  5,
    one_quota               =>  0,
    oversample_ratio        =>  10,
    quota_dist_measure      =>  "geographic",
    dist_limit              =>  5,
    regions                 =>  0,
    region_header           =>  "IBRA",
    sample_by_regions       =>  0,
    region_quota_strategy   =>  "log_richness",
    within_region_ratio     =>  10,
    region_codes            =>  0,
    species_sum             =>  1,
    subset_for_testing      =>  0,
    verbosity               =>  3,
    feedback_table          =>  1,
    feedback_suffix         =>  "_fb"
);

print "\n\nStarting site pair process\n";

#BdPD::GDM_Input_standard::generate_distance_table(%dist_args);
BdPD::GDM_Input::generate_distance_table(%dist_args);

print "\n Script finished.\n";