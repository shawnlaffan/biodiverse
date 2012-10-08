package BdPD::GDM_Input;
use strict;

#  This package generates a table of dissimilarity scores between pairs of groups (sites)
#  using either the sorenson or phylo_sorenson indices
#  The results are returned as a .csv file with 5 columns to define the two grid squares and
#  the sorenson or phylo_sorenson distance between them.

#  It reads in a Biodiverse basedata object for the gridded species locations, and optionally, a nexus
#  file with one of more trees, and a remap table to link the taxon names on the tree to
#  names in the spatial data

use strict;
use warnings;
use Carp;  #  warnings and dropouts
use File::Spec;  #  for the cat_file sub 
use Scalar::Util qw /reftype/;

our $VERSION = '0.15';

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;  #  for remaps
use Biodiverse::ReadNexus;
use Biodiverse::Tree;
use Biodiverse::Indices;
use BdPD::PD_Indices;
use Math::Random::MT::Auto qw(rand irand shuffle gaussian);


sub generate_distance_table {
    
# the parameters for this sub are passed as a hash with the following items:
#
#   FILE PARAMETERS
#
#   dist_measure
#                   - the name of the distance measure to use. Accepted options so far are:
#                       "phylo_sorenson"
#                       "sorenson"
#                       "sorenson and phylo_sorenson"
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
#   geographic_distance
#                   - if geographic_distance > 0, then an additional column for geographic distance between site pairs
#                     is added to the end of each output line
#                   - the distance is calcuted as a simple euclidean distance in the map units of the X and Y coordiantes
#                   - optional - defaults to 0
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
#   FEEDBACK PARAMETERS
#    
#   verbosity       - sets the amount of text output reporting progress to the text window or log file 
#                   - 0 give only global progress - % to completion, total numbers of site pair comparisons tried, stored to file
#                   - 1 list numbers of site pairs to do, done
#                   - 2 summarise sampling parameters and outcome for each region pair
#                   - 3 give full progress for each region pair - this could be appropriate for no regions ro a small number, or for debugging
#                   - optional - defaults to 1
#
#   feedback_table  - if > 0, then a table with a row of stats on sampling for each region pair, is produced
#
#   feedback_suffix
#                   - text to add to the filename for feedback

    my %args = @_;
    
    my $SPM = new(); # make a new Site Pair Maker object
            
    #############################################
    ######       SET PARAMETERS HERE       ######

    $SPM -> set_param(%args);    

    # Default values for optional parameters are set in the sub initalise

    ### FILE IMPORT & EXPORT PARAMETERS

    # for backwards compatability convert a text value of 'dist_measure to a hash element
    #which is the format now used, to allow for multiple distance measures
    my %dist_measures;
    if (!((ref $args{dist_measure}) =~ /HASH/)) {
        %dist_measures = ($args{dist_measure} => 1);
        $$SPM{dist_measure} = \%dist_measures;
        $args{dist_measure} = \%dist_measures;
    }

    if (exists($args{dist_measure}{phylo_sorenson})) {
        $SPM -> set_param("use_phylogeny", 1)
    };
    
    if ($$SPM{use_phylogeny}) { # get all the phylogeny related paramters if required
        if (exists $$SPM{nexus_remap}) {
            $$SPM{nexus_remap} = File::Spec -> catfile ($$SPM{directory}, $$SPM{nexus_remap});
        };
    };

    $SPM -> set_param("basedata_filename" => $$SPM{basedata_file}. $$SPM{basedata_suffix});
    $SPM -> set_param("basedata_filepath" => File::Spec -> catfile ($$SPM{directory}, $$SPM{basedata_filename}));
    
    # assign the default output prefix for the selected distance measure, if none was provided
    if (!exists $$SPM{output_file_prefix}) {
        if (exists($args{dist_measure}{phylo_sorenson})) {
            $SPM -> set_param ("output_file_prefix",'phylo_dist_');
        }
        elsif (exists($args{dist_measure}{sorenson}))  {
            $SPM -> set_param ("output_file_prefix",'dist_');
        };
    };
    
    ### SAMPLING PARAMETERS
    
    if ($$SPM{bins_count} > 0) {
        $SPM -> set_param(one_quota => 0);
    };
    
    if ($$SPM{subset_for_testing} >=1 or $$SPM{subset_for_testing} < 0) {
        $SPM -> set_param(subset_for_testing => 0);
    }
    
    if ($$SPM{test_sample_ratio} <=0) {
        $SPM -> set_param(test_sample_ratio => 1);
    }

    my $measures = $args{dist_measure};
    my @dist_measures = keys %$measures;
    my $measure_count = scalar @dist_measures;
    
    if (!exists($$SPM{quota_dist_measure})) {
        $SPM -> set_param(quota_dist_measure => $dist_measures[0]);
    }
    
    ### OUTPUT PARAMETERS

    #geographic distance
    my $geog_dist_output = "";
    if (exists $$SPM{geographic_distance}) {
        $SPM -> set_param("do_geog_dist",($$SPM{geographic_distance}>0));
    };
    
    #regions
    if (exists $$SPM{regions}) {
        $SPM -> set_param("do_output_regions",($$SPM{regions}>0))
    };
   
    ######        END OF PARAMETERS        ######
    #############################################

    
    # load basedata (and phylogeny) from file
    $SPM -> load_data();

    #############################################
    ######         RUN THE ANALYSES        ######
    
    
    ###### SITE PAIR ANALYSES
    ###  add a site pair analysis for each tree, using the same spatial params for each
    ###  if not using trees, create a single dummy to proceed with the loop
    my $start_time = time();
    
    my $bd = $$SPM{bd};
    my $groups_ref = $$SPM{groups_ref};
    
    my $trees = $$SPM{trees};
    my $tree_count = $$SPM{tree_count};
    $tree_count = 1 if !($tree_count);
    
    foreach my $tree_iterate (0 .. ($tree_count -1)) {
        my $tree_ref = $$trees[$tree_iterate];
        my $name_part;
        if ($$SPM{use_phylogeny}) {
            $name_part = $tree_ref -> get_param ('NAME') }
        else {
            $name_part = $$SPM{basedata_file};
        };
        
        if ($$SPM{use_phylogeny}) {
            my %trimmed_tree_ref = $bd -> get_trimmed_tree (tree_ref => $tree_ref);
            $SPM -> set_param(trimmed_tree => $trimmed_tree_ref {trimmed_tree});
        };
        
        # Get groups for analysis
        my @grouplist = $SPM -> get_grouplist(); # gets an array of the groups to use for the analysis, applying any sampling
        # rules that affect the group (site) selection
        $SPM -> set_param (grouplist => \@grouplist);
        
        #####################################################        
        # Set up training and test group lists as requested #
        #####################################################
        
        my %grouplists;
        
        
        if (!$$SPM{subset_for_testing}) {       # if no test dataset requested
            $grouplists{training} = \@grouplist;
        
        } else {                                # if training and test datasets requested
            
            shuffle @grouplist;
            my $group_count = (@grouplist + 0);
            my $test_count = int($group_count * $$SPM{subset_for_testing});
            my ($group, @temp_grouplist, $train_count);
            $train_count = $group_count-$test_count;
            for my $group_iter (1..$test_count) {
                $group = pop @grouplist;
                push @temp_grouplist, $group;
            }
            $grouplists{test} = \@temp_grouplist;
            $grouplists{training} = \@grouplist;
            print "\n$test_count groups allocated for testing\n";
            print "$train_count groups allocated for training\n";
        }
        
        ##############################################################################
        # Loop through for training, tests datasets - or just once for training only #
        ##############################################################################

        for my $group_sets (keys %grouplists) {
            
            #Loop for each group set to:
            #     define a file handle with the appropriate prefix
            #     do the whole site pair process for each groupset
            
            $SPM -> set_param(grouplist => $grouplists{$group_sets});
            
            my $file_suffix = "";
            if (exists ($grouplists{test})) {
                $file_suffix = "_".$group_sets;
            };
    
            # Open output file
            $SPM -> set_param(output_file_name => $$SPM{output_file_prefix} . $name_part.$file_suffix.'.csv');
            my $result_file_handle;
            open($result_file_handle, "> $$SPM{output_file_name} ") or die "Can't write $$SPM{directory}\\$$SPM{output_file_name}: $!";
            if ($result_file_handle) {
                $SPM -> set_param(result_file_handle => $result_file_handle);
            }
            
            # adjust the requested number of site pairs for training or test data
            # for approximately test_sample_ratio times frequency use of each group in the test data
            my $test_ratio = ($$SPM{subset_for_testing} / (1-$$SPM{subset_for_testing})) * ($$SPM{subset_for_testing} / (1-$$SPM{subset_for_testing})) * $$SPM{test_sample_ratio};
            my $test_sample_count = $$SPM{sample_count} * $test_ratio;
            if ($test_sample_count > $$SPM{sample_count}) {
                $test_sample_count = $$SPM{sample_count};
            };
                        
            if ($group_sets eq "test") {
                $SPM -> set_param (sample_count_current => $test_sample_count);   
            } else {
                $SPM -> set_param (sample_count_current => $$SPM{sample_count});  
            }            
    
            # prepare dissimilarity bins
            $SPM -> set_param (bins_min_val => 0,  #setting bin parameters - the remaining parameters are already in the object
                               bins_max_val => 1,
                               bins_max_class => 1,
                               bins_sample_count => $$SPM{sample_count_current});
            my @bins_all = $SPM -> make_bins("bins_all");
            
            if ($$SPM{bins_count} > 1) {
                print "\nNumber dissimilarity of bins: $$SPM{bins_count}\n";
                print "Oversample ratio to get enough samples to meet quotas: $$SPM{oversample_ratio}\n";
            };
    
            # get distance measure list as a text string
            my $dist_measure_text = "";
            foreach my $i (0..($measure_count-1)) {
                if ($i==0) {$dist_measure_text = $dist_measure_text . $dist_measures[$i];
                    } elsif ($i < $measure_count-1) {$dist_measure_text = $dist_measure_text . ", ". $dist_measures[$i];
                        } else {$dist_measure_text = $dist_measure_text." and ".$dist_measures[$i]}
            };
            
            print "\nAbout to send $dist_measure_text results to: $$SPM{directory}\\$$SPM{output_file_name} \n";

            # set up geographic distance output
            if ($$SPM{do_geog_dist}) {
                $geog_dist_output = ",geog_dist";    
                print "\nGeographic distance included in output.\n";
            };
            
            # set up regions
            $SPM -> prepare_regions();        
            my $regions_output = $$SPM{regions_output};
            print "\n";
            
            my $dist_header;
            if ($measure_count == 1) {
                $dist_header = "dist";
            } else {
                foreach my $i (0..($measure_count-1)) {
                if ($i==0) {$dist_header = $dist_measures[$i]
                    } else {$dist_header = $dist_header.",".$dist_measures[$i]}
                };
            };
            
            # print the header row to the site pair file
            print $result_file_handle "x0,y0,x1,y1,".$dist_header.$geog_dist_output.$regions_output."\n";
            
            # CALL THE MAIN SAMPLING LOOP #
            $SPM -> do_sampling();        #
            ###############################
    
            my $closed_ok = close($result_file_handle);
            
            print "\n\u$group_sets data created.";
            print "\n$$SPM{all_sitepairs_kept} result rows saved to $$SPM{directory}\\$$SPM{output_file_name} from $$SPM{all_sitepairs_done} sitepairs sampled.\n" if $closed_ok;
            my $elapsed_time = time()-$start_time;
            print "elapsed time: $elapsed_time seconds\n\n";
        };
        
    };
    
    print "\nBiodiverse  GDM module finished.\n";
    
};

sub make_bins {
    
# this sub takes an array containing:
#   the number of bins,
#   the minimum value
#   the maximum value
#   whether the maximum value is a separate class (0 = false, 1 = true) and
#   optionally the total target

#   as arguments, and returns an array populated with the classes as follows.
#
# array item 0 is a hash with the following items:
# minimum   0
# maximum   1
# classes   5
#
# array items 1 to x define each class with an array as follows:
# maximum value,    target count,   current count, full (0=false, 1=true), quota filled after n site pairs
#   0.3                 10000           4027        0                       0
#
    my $self = shift;
    my @args = @_;

    my $bin_count = $$self{bins_count};
    my $min_val = $$self{bins_min_val};
    my $max_val = $$self{bins_max_val};
    my $max_class = $$self{bins_max_class}; # if 1, the last class contains only the maximum value.
    my $total_target = $$self{bins_sample_count};
    my @bins;
    
    if ($bin_count < 1) {
        $bin_count = 1;
        $max_class = 0;
    }
    
    #create header
    my %bins_header = ("minimum" => $min_val,
                       "maximum" => $max_val,
                       "classes" => $bin_count);

    $bins[0] = \%bins_header;
    
    #create bins
    my $bin_max;
    for my $bin_number (1..($bin_count - $max_class)) {
        $bin_max = $min_val + ($bin_number * (($max_val - $min_val) / ($bin_count - $max_class)));

        $bins[$bin_number][0] = $bin_max;
        $bins[$bin_number][1] = int($total_target/$bin_count);
        $bins[$bin_number][2] = 0;
        $bins[$bin_number][3] = 0;
        $bins[$bin_number][4] = 0;
    };
    
    # create the top bin if required, which holds only the maximum value (eg 1)
    if ($max_class) {
        $bins[$bin_count][0] = $max_val;
        $bins[$bin_count][1] = int($total_target/$bin_count);
        $bins[$bin_count][2] = 0;
        $bins[$bin_count][3] = 0;
        $bins[$bin_count][4] = 0;
    };
    
    # if a name is provided as an argument for make_bins, then attach the bins array
    # to the object
    if ($args[0]) {
        $self -> set_param($args[0],\@bins);
    }
    
    return @bins;

};

sub get_region_stats {
    my $self = shift;
    #my %args = $$self{region_stats};
    
    my $region_column = $$self{region_column};
    my $group_list = $$self{grouplist};
    my @group_list = @$group_list;
    my $groups_ref = $$self{groups_ref};
    #my $bd =  $$self{bd};
    my $sample_by_regions = $$self{sample_by_regions};   
    # the reason for the use_regions parameter is to allow the region sampling data structures and code
    # to work in the case where no regions were provided or the user does not want to sample by regions
    # in those cases, the whole dataset is defined as a single region.
        
    my $group_count = scalar @group_list;
    my (@element_columns, $current_region, %regions, $label_hash);
    
    if ($sample_by_regions) {
        print "\nNow calculating statistics for each region in preparation for sampling.\n";
    } else {
        print "\nNow calculating statistics for the whole dataset in preparation for sampling.\n";
    };
    
    
    #Loop through all the groups and create a list of regions and of groups, species in each region
    for my $i (0.. $group_count-1) {
        #@element_columns = split /:/,$group_list[$i];
        @element_columns = $groups_ref -> get_element_name_as_array(element => $group_list[$i]);
        if ($sample_by_regions) {
            $current_region = $element_columns[$region_column-1];
        } else {
            $current_region = "whole dataset";
        }
        if ((!$current_region) or ($current_region eq '')) {
            $current_region = 'NO_REGION';
        };

        $regions{$current_region}{sample_count_current} ++;
        $label_hash = $groups_ref -> get_sub_element_hash(element => $group_list[$i]);
        for my $label (keys %$label_hash) {
            $regions{$current_region}{label_list}{$label} ++;
        };
            
        $regions{$current_region}{group_list}{$group_list[$i]} = 1;
        $regions{$current_region}{group_count} ++;

    };
    
    my $region_code;
    
    #Loop through each region to add up the list of species
    for $current_region (keys %regions) {
        my $label_hash_ref = $regions{$current_region}{label_list};
        my $label_count = scalar keys %$label_hash_ref;
        $regions{$current_region}{label_count} = $label_count;
        $region_code ++;
        $regions{$current_region}{code} = $region_code + 1;
        }
    
    if ($sample_by_regions) {print "Statistics generated for ". (scalar keys %regions) . " regions.\n";}
    
    $self -> set_param(region_stats => \%regions);    
    
    return %regions;
    
};

sub get_region_quotas {
  
    my $self = shift;
    #my %args = @_;
    
    my $indices = Biodiverse::Indices->new (BASEDATA_REF => $self->{bd});
    
    my $region_stats = $$self{region_stats};
    my %region_stats = %$region_stats;
    my $region_quota_strategy = $$self{region_quota_strategy};
    my $within_region_ratio = $$self{within_region_ratio};
    
    delete $region_stats{NO_REGION}; #don't use sites with no region

    my @region_list = keys %region_stats;
    my @region_list2 = @region_list;
    
    my (%region_quotas, $region1, $region2, $region_pair, $total_rel_quota, $current_quota, $total_quota);

    #populate list of all region pairs
    for $region1 (@region_list) {
        
        for $region2 (@region_list2) {
            
            $region_pair = $region1 . ":" . $region2;
            $region_quotas{$region_pair}{region1} = $region1;
            $region_quotas{$region_pair}{region2} = $region2;
            $region_quotas{$region_pair}{richness1} = $region_stats{$region1}{label_count};
            $region_quotas{$region_pair}{richness2} = $region_stats{$region2}{label_count};
            $region_quotas{$region_pair}{quota} = 0;
            
            # define the region pair quota according to one of the following options
            if ($region_quota_strategy eq "log_richness") {
                # this option allocates quotas for each region pair based on the log of the number of species in each region
                my $richness1 = $region_quotas{$region_pair}{richness1};
                my $richness2 = $region_quotas{$region_pair}{richness2};
                
                if ($region1 eq $region2) {
                    $current_quota = (log($richness1) + 1) * $within_region_ratio;
                } else {
                    $current_quota = (log($richness1) + log($richness2) + 1);
                };
            } else {
                
                # this option seeks equal quotas for each region pair.  It is set as the default catch-all,
                # but could be defined as with the name "equal" to match the parameter settings
                if ($region1 eq $region2) {
                    $current_quota = $within_region_ratio;
                } else {
                    $current_quota = 1;
                };                
            };
            
            if ($current_quota < 1) {
                $current_quota = 1;
            }
            
            $region_quotas{$region_pair}{relative_quota} = $current_quota;
            $total_rel_quota += $current_quota;
            
            #calculate the total number of possible sites pairs for this region pair
            my $all_comparisons;
            if ($region1 eq $region2) { # for within group comparisons
                $all_comparisons = ($region_stats{$region1}{group_count}-1) * $region_stats{$region2}{group_count} / 2;
            } else { #for between group comparisons
                $all_comparisons = $region_stats{$region1}{group_count} * $region_stats{$region2}{group_count};
            }
            $region_quotas{$region_pair}{all_pairs} = $all_comparisons;
            $region_quotas{$region_pair}{fully_used} = 0;
            
            #calculate the species shared between the 2 regions
            my %abc = $indices -> calc_abc(
                                            label_hash1 => $region_stats{$region1}{label_list},
                                            label_hash2 => $region_stats{$region2}{label_list});
            $region_quotas{$region_pair}{labels_shared} = $abc{A};
        };
        
        my $trash = shift @region_list2;
    };
    
    # calculate quotas
    my $region_pair_count = scalar keys %region_quotas;
    
    # first divide the quotas equally between all regions, giving a larger
    # quota to within region samples as specified by $within_region_ratio
    # then allow for region pairs which don't have enough sites to meet the
    # quota by increasing the quota for the rest.
    my ($fixed_total, $unfixed_rel_quota) = (0,0);
    my $sample_ratio = ($$self{sample_count_current} / $total_rel_quota);
    for $region_pair (keys %region_quotas) {
        $current_quota = sprintf("%.0f",($region_quotas{$region_pair}{relative_quota} * $sample_ratio));
        
        if ($current_quota > $region_quotas{$region_pair}{all_pairs}) { # if the quota is more than the number of possible pairs
            $current_quota = $region_quotas{$region_pair}{all_pairs};
            $region_quotas{$region_pair}{fully_used} = 1;
            $fixed_total += $current_quota;
        } else {
            $unfixed_rel_quota += $region_quotas{$region_pair}{relative_quota};
            $region_quotas{$region_pair}{fully_used} = 0;
        }; $region_quotas{$region_pair}{quota} = $current_quota;
        $total_quota += $current_quota;
    };
    
    my $under_quota = 1;
    
    until ($under_quota == 0) {
    
        my $remaining_count = $$self{sample_count_current} - $fixed_total;
        my $unfixed_rel = $unfixed_rel_quota;
        $unfixed_rel_quota = 0;
        $total_quota = $fixed_total;
        $under_quota = 0;
            
        for $region_pair (keys %region_quotas) {
            if ($region_quotas{$region_pair}{fully_used} == 0) {
                $current_quota = sprintf("%.0f",
                ($region_quotas{$region_pair}{relative_quota} *
                ($remaining_count / $unfixed_rel)));
                
                if ($current_quota > $region_quotas{$region_pair}{all_pairs}) { # if the quota is more than the number of possible pairs
                    $current_quota = $region_quotas{$region_pair}{all_pairs};
                    $region_quotas{$region_pair}{fully_used} = 1;
                    $fixed_total += $current_quota; $under_quota ++;
                } else {
                    $unfixed_rel_quota +=
                    $region_quotas{$region_pair}{relative_quota};
                    $region_quotas{$region_pair}{fully_used} = 0;
                };
                $current_quota = 1 if $current_quota == 0; 
                $region_quotas{$region_pair}{quota} = $current_quota;
                $total_quota += $current_quota;
            };
        };
        
        print "Regions under quota: $under_quota \n"; #remove once working
    };

    $region_quotas{summary}{region_pair_count} = $region_pair_count;
    $region_quotas{summary}{total_quota} = $total_quota;
    
    $self -> set_param(region_stats => \%region_stats);
    $self -> set_param(region_quotas => \%region_quotas);
    
    return %region_quotas;
}

sub new {
    my $self = {};
    bless $self;
    
    $self -> initialise();
    
    return $self;
}

sub initialise {    # add essential parameters to the object hash and set defaults
                    # this is a work in progress, and is not guaranteed to include
                    # all required values
    my $self = shift;
    
    $$self{bins_count} = 0;
    $$self{basedata_suffix} = ".bds";
    $$self{min_group_samples} = 0;
    $$self{min_group_richness} = 0;
    $$self{use_phylogeny} = 0;
    $$self{frequency} = 0;
    $$self{oversample_ratio} = 1;
    $$self{sample_by_regions} = 1;
    $$self{region_quota_strategy} = 'equal';
    $$self{within_region_ratio} = 1;
    $$self{do_geog_dist}=1;
    $$self{do_output_regions}=0;
    $$self{region_header} = 'region';
    $$self{verbosity} = 1;
    $$self{sample_count} = 100000;
    $$self{one_quota} = 0;
    $$self{subset_for_testing} = 0;
    $$self{test_sample_ratio} = 1;
    
    return $self;
}

sub set_param {
    my $self = shift;
    my %args = @_;
    for my $param (keys %args) {
        $$self{$param} = $args{$param};    
    };
}
    
sub load_data {    
    
    #############################################
    ######          LOAD THE DATA          ######

    my $self = shift;
    
    chdir ($$self{directory});
   
    # load phylogeny related data if required
    my @trees = [""];
    
    if ($$self{use_phylogeny}) {
        
        ###  read in the trees from the nexus file
        
        #  but first specify the remap (element properties) table to use to match the tree names to the basedata object
        #  make sure we're using array refs for the columns
        if (not reftype $$self{remap_input}) {
            $$self{remap_input} = [$$self{remap_input}];
        }
        if (not reftype $$self{remap_output}) {
            $$self{remap_output} = [$$self{remap_output}];
        }
        
        my $remap = Biodiverse::ElementProperties -> new;
        $remap -> import_data (file => $$self{nexus_remap},
                    input_sep_char => "guess",
                    input_quote_char => "guess",
                    input_element_cols => $$self{remap_input},
                    remapped_element_cols => $$self{remap_output},
                    );
        my $use_remap = exists($$remap{ELEMENTS});
        my $nex = Biodiverse::ReadNexus -> new;

        my $nexus_file = File::Spec -> catfile ($$self{directory}, $$self{nexus_file});
        $nex -> import_data (file => $nexus_file,
                             use_element_properties => $use_remap,
                             element_properties => $remap);

        my @trees = $nex -> get_tree_array;
        
        #my $use_remap = exists($$remap{ELEMENTS});
        ## read the nexus file
        #my $read_nex = Biodiverse::ReadNexus -> new;
        #$read_nex -> import_data (  file => $$self{nexus_file},
        #                            use_element_properties => $use_remap,
        #                            element_properties => $remap,
        #                            );
        #
        #  get an array of the trees contained in the nexus file
        #@trees = $read_nex -> get_tree_array;
        
        #  just a little feedback
        my $tree_count = scalar @trees;
        if ($tree_count) {
            $self -> set_param(tree_count => $tree_count,
                              trees => \@trees);
        }
        
        print "\n$tree_count trees parsed from $$self{nexus_file}\nNames are: ";
        my @names;
        foreach my $tree (@trees) {
                push @names, $tree -> get_param ('NAME');
        }
        print "\n  " . join ("\n  ", @names), "\n";
    };
        
    ###  read in the basedata object
    my $bd = Biodiverse::BaseData -> new (file => $$self{basedata_filepath});
    $self -> set_param(bd => $bd);
    $self -> set_param(groups_ref => $bd -> get_groups_ref);
};

sub prepare_regions {
            
        ######################################################
        #  get region stats and quotas                       #
        ######################################################
    
    my $self = shift;
    
    my $bin_count = $$self{bins_count};
    my $regions_output="";
    my $grouplist = $$self{grouplist};
    my @grouplist = @$grouplist;

    # check if regions for each group are available in the basedata
    if ($$self{do_output_regions} or $$self{sample_by_regions}) {
        my @element_test = split /:/, $grouplist[0];
        if (!$element_test[2]) { # if there is no 3rd component to define each group, after x,y
            $self -> set_param(do_output_regions => 0,
                              sample_by_regions => 0,
                              region_codes => 0);
            print "\nCan't use regions (".$$self{region_header}.") because this information was not stored in the Biodiverse basedata.\n";
        } else {
            print "Regions (".$$self{region_header}.") included in output.\n";
        };
    };
    
    # add extra columns to the .csv file header for region names or codes if needed
    if ($$self{do_output_regions}) {
        $regions_output = ",".$$self{region_header}."1,".$$self{region_header}."2";    
    };
    
    if ($$self{region_codes}) {
        $regions_output .= ",".$$self{region_header}."_code1,".$$self{region_header}."_code2";    
    };

    # more detailed output is appropriate where not sampling by regions
    if (!$$self{sample_by_regions}) {$self -> set_param(verbosity => 3);}
        
    $self -> set_param(region_column => 3); #sets which column has the region code.  Set by parameter once working
            
    my %region_stats = $self -> get_region_stats();
    my %region_quotas = $self -> get_region_quotas;
        
    $self -> set_param (region_pair_count => $region_quotas{summary}{region_pair_count});
    $self -> set_param (total_quota => $region_quotas{summary}{total_quota});
    $self -> set_param(regions_output => $regions_output);
     
    if ($$self{sample_by_regions}) {print "\nReady to sample $$self{region_pair_count}" . " region pairs and ". $$self{total_quota} . " site pairs.\n";};
    
}

sub get_grouplist {
    my $self = shift;
    
    my @grouplist = $$self{bd} -> get_groups;
    my $groups_ref = $$self{bd} -> get_groups_ref;
    my $i; # $i is the pointer for the current group
    my $group1;
    my $group_count = scalar @grouplist;
    
    ###  apply site richness limit
    if ($$self{min_group_richness} > 1) {
        my $samples_message;
        if ($$self{min_group_samples} > 1) {
            $samples_message = ' unless they have at least '.$$self{min_group_samples}.' records';
        }
        print "\nRemoving sites with less than $$self{min_group_richness} species".$samples_message."\n";
        my (@label_list, @grouplist_new, $remove_count, $label_count);
        my $keep_count = 0;
        my %subelement_hash;
        
        foreach $i (0..$group_count-1) {
            $group1 = $grouplist[$i];
            %subelement_hash = $groups_ref -> get_sub_element_hash(element => $group1);
            $label_count = keys %subelement_hash;
            if ($label_count >= $$self{min_group_richness}) {
                $grouplist_new[$keep_count] = $group1;
                $keep_count++;
            }
            elsif ($$self{min_group_samples} > 1) { # the number of species is less than min_group_richness
                # but do they have enough samples to include anyway
                my $sample_count=0;
                foreach my $samples (values %subelement_hash) {
                    $sample_count = $sample_count + $samples;
                };
                if ($sample_count >= $$self{min_group_samples}) {
                    $grouplist_new[$keep_count] = $group1;
                    $keep_count++;
                } else {
                    $remove_count++;
                }
            }
            else {
                $remove_count ++;
            };
        };
        
        @grouplist = @grouplist_new;
        print "\n$remove_count groups with less than $$self{min_group_richness} species were removed\n";
        $group_count = $#grouplist;
        print "$group_count groups remaining\n";
    };

    return @grouplist;
}
  
sub do_sampling {
    
    my $self = shift;
    my $bd = $$self{bd};
    my $indices = Biodiverse::Indices->new (BASEDATA_REF => $self->{bd});
    my $region_quotas = $$self{region_quotas};
    my %region_quotas = %$region_quotas;
    my $region_stats = $$self{region_stats};
    my %region_stats = %$region_stats;
    my $region_pair_count = $region_quotas{summary}{region_pair_count};
    my $n = $$self{sample_count_current};
    my ($group1, $group2, $label_hash1, $label_hash2, $group_count);
    my (%gl1,%gl2,%phylo_abc, $phylo_sorenson, %abc, $sorenson);
    my (@coords1,@coords2);
    my $bin_count = $$self{bins_count};
    my $groups_ref = $$self{groups_ref};
    my $dist_measure = $$self{dist_measure};
    my $quota_dist_measure = $$self{quota_dist_measure};
    my ($geog_dist, $geog_dist_output, $regions_output, $output_row, $all_sitepairs_done, $frequency);
    my ($all_sitepairs_kept,$regions_done);
    my ($one_quota,$one_count, $skip) = ($$self{one_quota},0, 0);
    my $result_file_handle = $$self{result_file_handle};
    my ($printedProgress_all, $storedProgress_all) = (0,0);
    my $dist_output;
    
    my $single_dist_measure;
    my $calc_two = (exists($$dist_measure{sorenson}) and exists($$dist_measure{phylo_sorenson}));
    if (! $calc_two) {
        $single_dist_measure = (keys($dist_measure))[0];
    }
    
    
    # start a feedback table, if requested
    if ($$self{feedback_table}) {
        $self -> feedback_table(open => 1);
    }
    
    #######################################################
    #  start the regions loop here                        #
    #######################################################
        
    for my $current_region_pair (keys %region_quotas) {
        
        if ($current_region_pair eq "summary") {next}
        
        my $region_pair = $region_quotas{$current_region_pair};
        my %region_pair = %$region_pair;
        my $region1 = $region_pair{region1};
        my $region2 = $region_pair{region2};
        
        my $grouplist1 = $region_stats{$region1}{group_list};
        my @grouplist1 = keys %$grouplist1;
        my $grouplist2 = $region_stats{$region2}{group_list};
        my @grouplist2 = keys %$grouplist2;
        my $groupcount1 = $region_stats{$region1}{group_count};
        my $groupcount2 = $region_stats{$region2}{group_count};

        my ($count, $loops, $toDo, $progress, $printedProgress, $storedProgress, $diss_quotas_reached) = (0,0,0,0,0,0,0);
        my $region_completed =0;
        
        shuffle (\@grouplist1);
        
        my $region_pair_quota = $region_pair{quota};
        my $total_samples = $region_pair_quota * $$self{oversample_ratio};
        my $one_quota_region = int($one_quota * $region_pair_quota);
        $one_count = 0;
        
        # set bins for this region pair
        $self -> set_param(bins_sample_count => $region_pair_quota);
        my @bins = $self -> make_bins();
        
        ###  calculate sampling frequency for this region pair
        my $all_comparisons = $region_pair{all_pairs};;
        
        if ($all_comparisons > $total_samples) {
            $frequency = $all_comparisons / $total_samples;
        }
        else {    
            $frequency = 1;
        };
        
        #add frequency to the hash for feedback
        $region_pair{frequency} = $frequency;

        $toDo = int($all_comparisons / $frequency);
        
        if ($$self{verbosity} >=2) {
            if ($region1 eq $region2) {
                if ($$self{sample_by_regions}) {
                    print "\nSeeking ". $region_pair_quota . " site pairs within region " . $region1.".\n";
                    print "Groups in region: $groupcount1\n";
                } else {
                    print "\nSeeking ". $region_pair_quota . " site pairs\n";
                    print "Groups: $groupcount1\n";                        
                };
            } else {
                print "\nSeeking ". $region_pair_quota . " site pairs between region " . $region1. " and region " . $region2 . ".\n";
                print "Groups in region " . $region1 . ": " . $groupcount1 . ", in region " . $region2 . ": " . $groupcount2 . "\n";    
            }
            print "Possible comparisons: $all_comparisons \n";
            if ($one_quota) {print "Quota for samples where difference = 1: $one_quota_region\n";};
            if (@bins and ($bins[0]{classes}>1)) {
                print "Quota per bin:  $bins[1][1]\n";
            };

            my $round_freq = sprintf("%.3f",  $frequency);
            print "Sampling frequency: $round_freq, Estimated samples to do: $toDo\n\n";
        }

        my (%dist_result,$j, @groups2);
        my $previous_j = 0;
        
        ###############################
        #  the main loop starts here  #  
        ###############################
        foreach my $i (0..$groupcount1 -1) {
         
            if ($region_completed) {
                next;
            };
            
            $group1 = pop @grouplist1;
            %gl1 = ($group1 => 0);    
            #@coords1 = split /:/, $group1;
            @coords1 = $groups_ref -> get_element_name_as_array(element => $group1);
            $label_hash1 = $groups_ref -> get_sub_element_hash(element => $group1);
                
            if ($region1 eq $region2) {@grouplist2 = @grouplist1};
            # for a within region sample, this ensures that only half the matrix is sampled
            
            # create a list of groups.  Only shuffled if frequency > 1.  Otherwise all groups are used so no need to shuffle.
            # calculate how many values are required, and simply shift that many from the start of the list
            
            @groups2 = @grouplist2;
            if ($frequency > 1) {shuffle (\@groups2);}
            
            my $j_count = (scalar @groups2 / $frequency) + $previous_j;
            $previous_j = $j_count - int($j_count); # keep the non-integer component to add next time, so the total is not rounded down for each row
            $j_count = int($j_count);
            $j = 0;
            
            # add previous j, so that the frequency is applied over the whole run, with gaps flowing from
            #one row to the next, rather than taking the first record of each row with no gaps
            
            while (($j < $j_count) and (! $region_completed)) {
                
                $group2 = $groups2[$j];
                @coords2 = split /:/, $group2;
                
                ####################################################################################
                # the following line is a more generic, higher level version of the preceding one  #
                # it is not being used as it alone adds 30% to program runtime                     #
                # however, it can be reverted to if changes to the basedata data structure result  #
                # in the preceding line not working                                                #
                #@coords2 = $groups_ref -> get_element_name_as_array(element => $group2);          #
                ####################################################################################
                
                 $label_hash2 = $groups_ref -> get_sub_element_hash(element => $group2);
                
                %gl2 = ($group2 => 0);
                
                # calculate the phylo Sørensen distance
                if (exists($$dist_measure{phylo_sorenson})) {  # phylo_sorenson
                    $dist_result{phylo_sorenson} = -1;      # an undefined distance result is given as -1
                    %phylo_abc = $indices -> calc_phylo_abc(group_list1 => \%gl1,
                                                    group_list2 => \%gl2,
                                                    label_hash1 => $label_hash1,
                                                    label_hash2 => $label_hash2,
                                                    trimmed_tree => $$self{trimmed_tree});
        
                    if (($phylo_abc{PHYLO_A} + $phylo_abc{PHYLO_B}) and ($phylo_abc{PHYLO_A} + $phylo_abc{PHYLO_C})) {  #  sum of each side must be non-zero
                        $dist_result{phylo_sorenson} = sprintf("%.6f", eval {1 - (2 * $phylo_abc{PHYLO_A} / ($phylo_abc{PHYLO_A} + $phylo_abc{PHYLO_ABC}))});
                    };
                }
                
                # calculate the Sørensen distance                                    
                if (exists($$dist_measure{sorenson})) {  # sorenson
                    $dist_result{sorenson} = -1;      # an undefined distance result is given as -1
                    %abc = $indices -> calc_abc(group_list1 => \%gl1,
                                        group_list2 => \%gl2,
                                        label_hash1 => $label_hash1,
                                        label_hash2 => $label_hash2);

                    if (($abc{A} + $abc{B}) and ($abc{A} + $abc{C})) {  #  sum of each side must be non-zero
                        $dist_result{sorenson} = sprintf("%.6f", eval {1 - (2 * $abc{A} / ($abc{A} + $abc{ABC}))});
                    };   
                };
                
                # if either distance measure has a valid result
                if ( (exists($$dist_measure{sorenson}) and ($dist_result{sorenson} != -1)) or (exists($$dist_measure{phylo_sorenson}) and ($dist_result{phylo_sorenson} != -1)) ) {
                    
                    # format the distance result(s)
                    if ($calc_two) {
                        $dist_output = $dist_result{phylo_sorenson}.",".$dist_result{sorenson};
                    } else {
                        $dist_output = $dist_result{$single_dist_measure};
                    };
                    #if ($$self{do_geog_dist} or $$self{do_output_regions}) {$dist_output = $dist_output.",";}
                    
                    # calculate the geographic distance
                    if ($$self{do_geog_dist}) {
                        $geog_dist = sprintf("%.3f", sqrt( ($coords1[0]-$coords2[0]) ** 2 + ($coords1[1]-$coords2[1]) ** 2 ));
                        $geog_dist_output = ",$geog_dist";
                    };
                    
                    # set the region names output
                    if ($$self{do_output_regions}) {
                        $regions_output = ",".$region1.",".$region2;
                    };
                    
                    # set the region codes output
                    if ($$self{region_codes}) {
                        $regions_output .= ",".$region_stats{$region1}{code}.",".$region_stats{$region2}{code};
                    };
      
                    if ($one_quota_region) { #1st of two alternative methods for managing the spread of distance values
                        if ($dist_result{$quota_dist_measure} == 1){
                            $one_count ++;
                            if ($one_count >= $one_quota_region) {
                                $skip =1;
                                if ($one_count == $one_quota_region) {
                                    if ($$self{verbosity} >= 2) {
                                        print "Quota of $one_quota_region scores of 1 reached after $count iterations \n";
                                    };
                                };
                            };
                        };
                    } elsif (@bins and $bin_count > 1) { #2nd of two alternative methods for managing the spread of distance values
                        
                        #1st check if the distance value is 1 (the top bin)
                        if ($dist_result{$quota_dist_measure} == 1){    
                            if (!$bins[$bin_count][3]){ #if quota not previously reached
                                $bins[$bin_count][2] ++;
                                if ($bins[$bin_count][1] <= $bins[$bin_count][2]) {
                                    if ($$self{verbosity} >=2) {
                                        print "   Quota of $bins[$bin_count][2] scores of 1 reached from " . ($loops + 1) ." site pairs \n";
                                    };
                                    $bins[$bin_count][3] = 1; # quota reached so set full = true
                                    $bins[$bin_count][4] = $loops+1;  # record the number of site pairs needed to fill this bin
                                    $diss_quotas_reached ++;
                                };
                            } else {
                                $skip = 1;
                            };
                        } else { #for all values < 1
                            for my $bin_number (1..($bin_count-1)) {
                                if ($dist_result{$quota_dist_measure} < $bins[$bin_number][0]) {
                                    if (!$bins[$bin_number][3]){    #if quota not previously reached
                                        $bins[$bin_number][2] ++;
                                        if ($bins[$bin_number][1] <= $bins[$bin_number][2]) {
                                            my $bin_min = 0;
                                            if ($bin_number > 1) {$bin_min = $bins[$bin_number-1][0]};
                                            if ($$self{verbosity} >=2) {
                                                print "   Quota of $bins[$bin_number][2] scores of " . sprintf("%.3f", $bin_min) . " to < " . sprintf("%.3f",$bins[$bin_number][0]) . " reached from $loops site pairs \n";
                                            };
                                            $bins[$bin_number][3] = 1; #quota reached so set full = true
                                            $bins[$bin_number][4] = $loops+1;  # record the number of site pairs needed to fill this bin
                                            $diss_quotas_reached ++;
                                            
                                        };
                                    } else {
                                        $skip = 1;
                                    };
                                    last;
                                };
                            };
                        };
                    };
                    
                    if (($diss_quotas_reached > 0 and $diss_quotas_reached >= $bin_count) or ($count >= $region_pair_quota)) {
                        $region_completed = 1;
                    }
        
                    if (!$skip) { 
                        $output_row = "$coords1[0],$coords1[1],$coords2[0],$coords2[1],$dist_output".$geog_dist_output.$regions_output."\n";
                        print $result_file_handle "$output_row";
                        $count++;
                    };

                } else {
                    print "undefined result for $coords1[0],$coords1[1] and $coords2[0],$coords2[1], $regions_output\n";
                };
                
                $j++;
                $skip = 0;
                $loops++;
                
                if ($$self{verbosity} ==3) {
                    $progress = int (100 * $loops / $toDo);
                    if (($progress % 10 == 0) or (($diss_quotas_reached == $bin_count) and $bin_count>1)) {
                        if ($printedProgress != $progress) {
                            $storedProgress = int (100 * $count / $region_pair_quota);
                            print "Done: $progress%       $loops      Stored: $storedProgress%     $count\n";
                            $printedProgress = $progress;
                        };
                    };
                print "\n" if $count == $toDo;    
                };
            };
        };

        #give feedback for bins where quota was not filled
        if ($$self{verbosity} >=2) {
            if ($diss_quotas_reached < $bin_count) {
                print "\nQuotas not met after $loops site pairs:\n";                
                for my $bin_number (1..($bin_count)) {
                    if (!$bins[$bin_number][3]) {
                        my $bin_min = 0;
                        $bin_min = $bins[$bin_number-1][0] unless ($bin_number <= 1);
                        print "   $bins[$bin_number][2] scores of " . sprintf("%.3f", $bin_min) . " to < " . sprintf("%.3f",$bins[$bin_number][0]) . " found.\n";
                    };
                };
                print "\n";
            } else {
                print "\nAll quotas met after $loops site pairs.\n";
            };
        };
        
        # Update global progress stats after each region
        $all_sitepairs_done += $loops;
        $all_sitepairs_kept += $count;
        $regions_done += 1;
        $region_pair{sitepairs_done} = $loops;
        $region_pair{sitepairs_kept} = $count;
        
        my $bins_all = $$self{bins_all};
        my @bins_all = $bins_all;
        for my $class (1 .. (scalar @bins_all - 1)) {
            #add the total for each class in this region to create a global total
            $bins_all[$class][2] += $bins[$class][2];
            #add to a count if quota met for each class in this region to create a global count for each class
            $bins_all[$class][3] += $bins[$class][3]; 
        }
             
        my $progress_all;
        if ($$self{sample_by_regions}) {
            $progress_all = int (100 * $regions_done / $region_pair_count);
        } else {
            $progress_all = int (100 * $all_sitepairs_done / $toDo);
        }
                    
        # Feedback on completed region after each region
        if ($$self{verbosity} == 1) {
            print "$progress_all%  Region";
            if ($region1 eq $region2) {
                print " $region1.  "
            } else {
                print "s $region1 and $region2.  ";
            }
            print "Quota: $region_pair_quota  Site pairs done: $loops  kept: $count  ";
            if ($bin_count > 1) {
                print "Distance quotas met: $diss_quotas_reached"."/"."$bin_count";
            }

            if ($frequency > 1) {
                my $round_freq = sprintf("%.2f",  $frequency);               
                print " Freq $round_freq";
            }
            
            if ($region_completed) {
                print "*";
            }
            print "\n";

        }

        # Feedback on global progress after each region
        if ($$self{verbosity} ==0 or ($regions_done == $region_pair_count)) {
            if (($progress_all % 5 == 0) or ($regions_done == $region_pair_count)) {
                if ($printedProgress_all != $progress_all) {
                    $storedProgress_all = int (100 * $regions_done / $region_pair_count);
                    print "Done: $progress_all%      Sites pairs done: $all_sitepairs_done   Site pairs stored: $all_sitepairs_kept";
                    if ($$self{sample_by_regions}) {
                        print "     Region pairs: $regions_done\n";
                    } else {
                        print "\n";
                    }
                    $printedProgress_all = $progress_all;
                };
            };
        };
        
        # send feedback for the completed region to the feedback table
        if ($$self{feedback_table}) {
            $self -> feedback_table(one_region_pair => 1,
                                    region1 => $region1,
                                    region2 => $region2,
                                    region_pair_hash => \%region_pair,
                                    region_bins => \@bins);
        }
        
        $region_quotas{$current_region_pair} = %region_pair;
    };
    
    # close the feedback table
    if ($$self{feedback_table}) {$self -> feedback_table(close => 1);}
    
    $self -> set_param(all_sitepairs_done => $all_sitepairs_done);
    $self -> set_param(all_sitepairs_kept => $all_sitepairs_kept);
};

sub feedback_table {
# this sub produces a .csv file with statistics on sampling for each region pair
# or if not sampling by regions, then as a single row for the whole sample.

    my $self = shift;
    my %args = @_;
    my $feedback_file_handle = $$self{feedback_file_handle};
    
    if ($args{open}) {
        my @filename = split /.csv/,$$self{output_file_name};
        my $feedback_filename = $filename[0] . $$self{feedback_suffix} . ".csv";
        $self -> set_param(feedback_file_name => $feedback_filename);
        open($feedback_file_handle, "> $feedback_filename ") or die "Can't write $$self{directory}\\$feedback_filename: $!";
        if ($feedback_file_handle) {
            $self -> set_param(feedback_file_handle => $feedback_file_handle);
            print "\nFeedback table will be written to $feedback_filename\n";
        }
    } elsif ($args{close}) {
        my $success = close($feedback_file_handle);
        if ($success) {
            print "\nFinished writing feedback table $$self{feedback_file_name}\n";
        } else {
            print "\nNote: feedback table $$self{feedback_file_name} was not closed successfully\n";
        }
        
    } elsif ($args{one_region_pair}) {
        my $feedback_header_done = $$self{feedback_header_done};
        
        # write the header line if not yet written
        if (! $feedback_header_done) {
            my $header_text = "Region1,Region2,GroupCount1,GroupCount2,Species count1,Species count2,Species shared,AllPairs,Region pair quota,Frequency,Site pairs searched,Site pair output,Bins quota";
            for my $bindex (1..$$self{bins_count}) {
                $header_text .= ",Bin".$bindex.",Quota $bindex reached after";
            }
            print $feedback_file_handle "$header_text\n";
            $self -> set_param(feedback_header_done => 1);
        }
        
        # collect all of the values to be reported
        my ($region1, $region2) = ($args{region1},$args{region2});
        my $region_pair = $args{region_pair_hash};
        
        my $region1_stats = $$self{region_stats}{$region1};
        my $region2_stats = $$self{region_stats}{$region2};
        my $bins = $args{region_bins};
        
        my $shared = $$region_pair{labels_shared};
        
        # build the row of output for this region pair as a string
        my $round_freq = sprintf("%.3f",  $$region_pair{frequency});
        my $row_text = "$region1,$region2,$$region1_stats{group_count},$$region2_stats{group_count},$$region1_stats{label_count},$$region2_stats{label_count},";
        $row_text .= "$shared,$$region_pair{all_pairs},$$region_pair{quota},$round_freq,$$region_pair{sitepairs_done},$$region_pair{sitepairs_kept},$$bins[1][1]";
        
        for my $bindex (1..$$self{bins_count}) {
            $row_text .= ",$$bins[$bindex][2],$$bins[$bindex][4]";
        }
        
        $row_text .= "\n";
        
        # write the row to file
        print $feedback_file_handle "$row_text";
        
    } elsif ($args{all}) {
        
    };
};

sub DESTROY {
    my $self = shift;
    
    foreach my $key (keys %$self) {  #  clear all the top level stuff

        delete $$self{$key};        
    }
}

1;