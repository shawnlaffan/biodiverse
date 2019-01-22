package BdPD::GenerateDistanceTable;

use 5.010;
use strict;
use warnings;

use Carp;  #  warnings and dropouts
use File::Spec;  #  for the cat_file sub 
use Scalar::Util qw /reftype/;

our $VERSION = '2.99_001';

use BdPD::GDM_Input;

use Math::Random::MT::Auto qw(rand irand shuffle gaussian);

use Exporter::Easy (
    TAGS => [all => [qw /generate_distance_table parse_args_file/]],
);


# the parameters for this sub are passed as a hash with the following items:
#
#   FILE PARAMETERS
#
#   dist_measure
#                   - the name of the distance measure to use.
#                   - the first listed item will be placed in the 'Response' column in the site-pair file
#                   Accepted options so far are single items or a list from:
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
#   bins_count      - number of bins to divide the 0 to 1 dissimilarity range into. Each bin will have as its target
#                     an equal proportion of the site pairs. 1 is treated as on of the classes.
#                     So if bins = 4, the classes will be: 0 - 0.3333, 0.3333 - 0.6667, 0.6667 - 0.9999, 1
#                     Each bin would have a quota of 0.25
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
#   dist_limit_max
#                   - set a maximum distance for the quota_dist_measure.  If this is geographic, it is a simple euclidean distance, with no adjustment for curvature etc
#                   - site pairs beyond the limit will not be used
#
#   dist_limit_min
#                   - set a minimum distance for the quota_dist_measure.  If this is geographic, it is a simple euclidean distance, with no adjustment for curvature etc
#                   - site pairs closer than the limit will not be used
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
#   weight_type     - defines the values used in the weight column to determine the weight given to each site pair in the GDM model
#                   - the default value in "one" which places a 1 as the weight for every site pair
#                   - if weight_type = "species_sum" then weight is the number sum of the number of species at the two sites, regardless of number shared.
#                   - optional - defaults to "one"
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

sub generate_distance_table {
    my %args = @_;
    
    my $SPM = BdPD::GDM_Input->new(); # make a new Site Pair Maker object

    #############################################
    ######       SET PARAMETERS HERE       ######

    $SPM->set_param(%args);    

    # Default values for optional parameters are set in the sub initalise

    ### FILE IMPORT & EXPORT PARAMETERS

    # for backwards compatability convert a text value of 'dist_measure to a hash element
    #which is the format now used, to allow for multiple distance measures
    my @dist_measure_array = @{$args{dist_measure}};
    my %dist_measures;
    @dist_measures{@dist_measure_array} = (1) x @dist_measure_array;
    
    $SPM->{dist_measure} = \@dist_measure_array;
    #$args{dist_measure}  = \%dist_measures;

    if (exists($dist_measures{phylo_sorenson})) {
        $SPM->set_param(use_phylogeny => 1)
    };
    
    if ($SPM->{use_phylogeny}) { # get all the phylogeny related paramters if required
        if (exists $SPM->{nexus_remap}) {
            $SPM->{nexus_remap} = File::Spec->catfile ($SPM->{directory}, $SPM->{nexus_remap});
        };
    };

    $SPM->set_param(basedata_filename => $SPM->{basedata_file} . $SPM->{basedata_suffix});
    $SPM->set_param(basedata_filepath => File::Spec->catfile ($SPM->{directory}, $SPM->{basedata_filename}));
    
    # assign the default output prefix for the selected distance measure, if none was provided
    if (!exists $SPM->{output_file_prefix}) {
        if (exists($dist_measures{phylo_sorenson})) {
            $SPM->set_param (output_file_prefix => 'phylo_dist_');
        }
        elsif (exists($dist_measures{sorenson}))  {
            $SPM->set_param (output_file_prefix => 'dist_');
        };
    };
    
    ### SAMPLING PARAMETERS
    
    if ($SPM->{subset_for_testing} < 0 || $SPM->{subset_for_testing} >= 1) {
        $SPM->set_param(subset_for_testing => 0);
    }
    
    if ($SPM->{test_sample_ratio} <= 0) {
        $SPM->set_param(test_sample_ratio => 1);
    }
    
    my $measure_count = scalar @dist_measure_array;
    $SPM->set_param(measure_count => $measure_count);

    if (!exists($SPM->{quota_dist_measure})) {
        $SPM->set_param(quota_dist_measure => $dist_measure_array[0]);
    }
    
    ### OUTPUT PARAMETERS
    
    #regions
    if (exists $SPM->{regions}) {
        $SPM->set_param(do_output_regions => ($SPM->{regions}>0))
    };

    ######        END OF PARAMETERS        ######
    #############################################
    
    # load basedata (and phylogeny) from file
    $SPM->load_data();

    #############################################
    ######         RUN THE ANALYSES        ######
    
    
    ###### SITE PAIR ANALYSES
    ###  add a site pair analysis for each tree, using the same spatial params for each
    ###  if not using trees, create a single dummy to proceed with the loop
    my $start_time = time();
    
    my $bd = $SPM->{bd};
    my $groups_ref = $SPM->{groups_ref};
    
    my $trees = $SPM->{trees};
    my $tree_count = $SPM->{tree_count} || 1;
    
    foreach my $tree_iterate (0 .. ($tree_count - 1)) {
        my $tree_ref = $trees->[$tree_iterate];
        my $name_part;
        if ($SPM->{use_phylogeny}) {
            $name_part = $tree_ref->get_param ('NAME');
        }
        else {
            $name_part = $SPM->{basedata_file};
        };

        if ($SPM->{use_phylogeny}) {
            my %trimmed_tree_ref = $SPM->{indices}->get_trimmed_tree (tree_ref => $tree_ref);
            $SPM->set_param(trimmed_tree => $trimmed_tree_ref{trimmed_tree});
        };

        # Get groups for analysis
        my @grouplist = $SPM->get_grouplist(); # gets an array of the groups to use for the analysis, applying any sampling
        # rules that affect the group (site) selection
        $SPM->set_param (grouplist => \@grouplist);

        #####################################################        
        # Set up training and test group lists as requested #
        #####################################################

        my %grouplists;

        if (!$SPM->{subset_for_testing}) {       # if no test dataset requested
            $grouplists{training} = \@grouplist;        
        }
        else {                                   # if training and test datasets requested
            shuffle @grouplist;

            my $group_count = (@grouplist + 0);
            my $test_count  = int($group_count * $SPM->{subset_for_testing});
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

            $SPM->set_param(grouplist => $grouplists{$group_sets});

            my $file_suffix = "";
            if (exists ($grouplists{test})) {
                $file_suffix = '_' . $group_sets;
            };

            # Open output file
            my $fname = $SPM->{output_file_prefix} . $name_part . $file_suffix . '.csv';
            $SPM->set_param(output_file_name => $fname);
            my $result_file_handle;
            open($result_file_handle, '>', $SPM->{output_file_name})
              or die "Can't write $SPM->{directory}/$SPM->{output_file_name}: $!";

            #  the if should be redundant - we die on prev line if it is undef
            if ($result_file_handle) {
                $SPM->set_param(result_file_handle => $result_file_handle);
            }

            # adjust the requested number of site pairs for training or test data
            # for approximately test_sample_ratio times frequency use of each group in the test data
            my $test_ratio =    ($SPM->{subset_for_testing} / (1 - $SPM->{subset_for_testing}))
                              * ($SPM->{subset_for_testing} / (1 - $SPM->{subset_for_testing}))
                              * $SPM->{test_sample_ratio};
            my $test_sample_count = $SPM->{sample_count} * $test_ratio;
            if ($test_sample_count > $SPM->{sample_count}) {
                $test_sample_count = $SPM->{sample_count};
            };

            if ($group_sets eq 'test') {
                $SPM->set_param (sample_count_current => $test_sample_count);   
            }
            else {
                $SPM->set_param (sample_count_current => $SPM->{sample_count});  
            }            

            my $bins_max_val = exists ($SPM->{dist_limit_max})
                    ? exists ($SPM->{dist_limit_max})
                    : 1;

            # prepare dissimilarity bins
            $SPM->set_param (bins_min_val => 0,  #setting bin parameters - the remaining parameters are already in the object
                               bins_max_val => $bins_max_val,
                               bins_max_class => 1,
                               bins_sample_count => $SPM->{sample_count_current});
            my @bins_all = $SPM->make_bins("bins_all");
    
            # get distance measure list as a text string
            my $dist_measure_text = q{};
            foreach my $i (0..($measure_count-1)) {
                if ($i == 0) {
                    $dist_measure_text .= $dist_measure_array[$i];
                }
                elsif ($i < $measure_count-1) {
                    $dist_measure_text .= ", $dist_measure_array[$i]";
                }
                else {
                    $dist_measure_text .= " and $dist_measure_array[$i]";
                }
            };
            
            print "\nAbout to send $dist_measure_text results to: "
                . "$SPM->{directory}/$SPM->{output_file_name} \n";
            
            # set up regions
            $SPM->prepare_regions();        
            my $regions_output = $SPM->{regions_output};
            print "\n";
            
            my $extra_dist_header = "";
            if ($measure_count > 1) {
                foreach my $i (1..($measure_count-1)) {
                    $extra_dist_header = "," . $extra_dist_header . $dist_measure_array[$i];
                };
            };
            
            # print the header row to the site pair file
            my $standard_header = "Response,Weights,x0,y0,x1,y1";
            say $result_file_handle "$standard_header" . $extra_dist_header . $regions_output;

            # CALL THE MAIN SAMPLING LOOP #
            $SPM->do_sampling();        #
            ###############################
    
            my $closed_ok = close($result_file_handle);
            
            print "\n\u$group_sets data created.";
            if ($closed_ok) {
                print "\n$SPM->{all_sitepairs_kept} result rows saved to "
                    . "$SPM->{directory}\\$SPM->{output_file_name} from "
                    . "$SPM->{all_sitepairs_done} sitepairs sampled.\n" ;
            }
            my $elapsed_time = time()-$start_time;
            print "elapsed time: $elapsed_time seconds\n\n";
            
            $SPM -> set_param (feedback_header_done => 0);
        };
        
    };

    print "\nBiodiverse GDM module completed.\n";
};

#  should probably find a module on CPAN for this
sub parse_args_file {
    my $file = shift // croak "file arg is undefined";
    
    open my $fh, '<', $file or croak "Unable to open $file";
    
    my %args = (dist_measure => []);
    
    LINE:
    while (defined (my $line = <$fh>)) {
        next LINE if $line =~ /^\s*#/;
        $line =~ s/^\s+//;
        chomp $line;
        $line =~ s/\s$//;
        
        my @parts   = split /\s+/, $line, 2;
        my $keyword = $parts[0];
        my $value   = $parts[1] // q{};
        if ($value =~ /^(['"])/) {
            my $quotes = $1;
            my $val2 = $value;
            $val2 =~ /^$quotes(.+)$quotes/;
            $value = $1
              // croak "Unbalanced parentheses in value for $keyword: $val2" ;
        }
        #$value =~ s/#.*$//;
        $value  =~ s/^\s+|\s+$//g;  # replaced previous line with this to strip both leading and trailing whitespace

        next LINE if !length $keyword;  #  skip empties
        
        if (not $keyword =~ /^dist_measure$/) {
            $args{$keyword} = $value;
        }
        else {  #  special handling
            #$args{dist_measure} //= [];  # initialise with an empty array if needed
            my $array_ref = $args{dist_measure};
            push @$array_ref, $value;
        }
    }

    return wantarray ? %args : \%args;
}

1;
