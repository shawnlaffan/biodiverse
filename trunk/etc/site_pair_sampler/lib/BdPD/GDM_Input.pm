package BdPD::GDM_Input;
#  This package generates a table of dissimilarity scores between pairs of groups (sites)
#  using either the sorenson or phylo_sorenson indices
#  The results are returned as a .csv file with 5 columns to define the two grid squares and
#  the sorenson or phylo_sorenson distance between them.

#  It reads in a Biodiverse basedata object for the gridded species locations, and optionally, a nexus
#  file with one of more trees, and a remap table to link the taxon names on the tree to
#  names in the spatial data

use strict;
use warnings;
use 5.010;
use Carp;  #  warnings and dropouts
use File::Spec;  #  for the cat_file sub 
use Scalar::Util qw /reftype/;
use List::Util qw[min max];

our $VERSION = '0.18003';

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;  #  for remaps
use Biodiverse::ReadNexus;
use Biodiverse::Tree;
use Biodiverse::Indices;
use Math::Random::MT::Auto qw(rand irand shuffle gaussian);

sub new {
    my $class = shift;

    my $self = {  #  initialise with default params - some may need to be added
        bins_count            => 0,
        basedata_suffix       => '.bds',
        min_group_samples     => 0,
        min_group_richness    => 0,
        use_phylogeny         => 0,
        frequency             => 0,
        sample_by_regions     => 1,
        region_quota_strategy => 'equal',
        within_region_ratio   => 1,
        do_output_regions     => 0,
        region_header         => 'region',
        verbosity             => 1,
        sample_count          => 100000,
        one_quota             => 0,
        subset_for_testing    => 0,
        test_sample_ratio     => 1,
        shared_species        => 0,
        bins_max_class        => 1,
        species_sum           => 0,  
    };

    bless $self, $class;

    return $self;
}

sub set_param {
    my $self = shift;
    my %args = @_;
    for my $param (keys %args) {
        $self->{$param} = $args{$param};    
    };
}

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

    my $bin_count    = $self->{bins_count};
    my $min_val      = $self->{bins_min_val};
    my $max_val      = $self->{bins_max_val};
    my $max_class    = $self->{bins_max_class}; # if 1, the last class contains only the maximum value.
    my $total_target = $self->{bins_sample_count};
    my @bins;

    if ($bin_count < 1) {
        $bin_count = 1;
        $max_class = 0;
    }

    # if a distance limit has been set for sampling (presumably for geographic distance)
    # don't have a top class of a single value (1).  Such a class only makes sense for compositional dissimilarity
    my $dist_limit;
    if(exists($self->{dist_limit})) {
        $dist_limit = $self->{dist_limit};
        if ($dist_limit > 1) {
            $max_class = 0;
        };
    };

    #create header
    my %bins_header = (
        minimum => $min_val,
        maximum => $max_val,
        classes => $bin_count,
    );

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
        $self->set_param ($args[0],\@bins);
    }

    $self->set_param (max_class => $max_class);

    return @bins;
};

sub get_region_stats {
    my $self = shift;
    #my %args = $self->{region_stats};

    my $region_column = $self->{region_column};
    my $group_list = $self->{grouplist};
    my @group_list = @$group_list;
    my $groups_ref = $self->{groups_ref};
    #my $bd =  $self->{bd};
    my $sample_by_regions = $self->{sample_by_regions};   
    # the reason for the use_regions parameter is to allow the region sampling data structures and code
    # to work in the case where no regions were provided or the user does not want to sample by regions
    # in those cases, the whole dataset is defined as a single region.

    my $group_count = scalar @group_list;
    my (@element_columns, $current_region, %regions, $label_hash);

    if ($sample_by_regions) {
        print "\nNow calculating statistics for each region in preparation for sampling.\n";
    }
    else {
        print "\nNow calculating statistics for the whole dataset in preparation for sampling.\n";
    };

    #Loop through all the groups and create a list of regions and of groups, species in each region
    for my $i (0.. $group_count-1) {
        #@element_columns = split /:/,$group_list[$i];
        @element_columns = $groups_ref->get_element_name_as_array(element => $group_list[$i]);
        if ($sample_by_regions) {
            $current_region = $element_columns[$region_column-1];
        }
        else {
            $current_region = "whole dataset";
        }
        if ((!$current_region) or ($current_region eq '')) {
            $current_region = 'NO_REGION';
        };

        $regions{$current_region}{sample_count_current} ++;
        $label_hash = $groups_ref->get_sub_element_hash(element => $group_list[$i]);
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

    $self->set_param (region_stats => \%regions);    

    return %regions;

};

sub get_region_quotas {

    my $self = shift;
    #my %args = @_;

    my $indices = $self->{indices};

    my $region_stats = $self->{region_stats};
    my %region_stats = %$region_stats;
    my $region_quota_strategy = $self->{region_quota_strategy};
    my $within_region_ratio = $self->{within_region_ratio};

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
                }
                else {
                    $current_quota = (log($richness1) + log($richness2) + 1);
                };
            }
            else {

                # this option seeks equal quotas for each region pair.  It is set as the default catch-all,
                # but could be defined as with the name "equal" to match the parameter settings
                if ($region1 eq $region2) {
                    $current_quota = $within_region_ratio;
                }
                else {
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
            }
            else { #for between group comparisons
                $all_comparisons = $region_stats{$region1}{group_count} * $region_stats{$region2}{group_count};
            }
            $region_quotas{$region_pair}{all_pairs} = $all_comparisons;
            $region_quotas{$region_pair}{fully_used} = 0;

            #calculate the species shared between the 2 regions
            my %abc = $indices->calc_abc(
                label_hash1 => $region_stats{$region1}{label_list},
                label_hash2 => $region_stats{$region2}{label_list},
            );
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
    my $sample_ratio = ($self->{sample_count_current} / $total_rel_quota);
    for $region_pair (keys %region_quotas) {
        $current_quota = sprintf("%.0f",($region_quotas{$region_pair}{relative_quota} * $sample_ratio));

        if ($current_quota > $region_quotas{$region_pair}{all_pairs}) { # if the quota is more than the number of possible pairs
            $current_quota = $region_quotas{$region_pair}{all_pairs};
            $region_quotas{$region_pair}{fully_used} = 1;
            $fixed_total += $current_quota;
        }
        else {
            $unfixed_rel_quota += $region_quotas{$region_pair}{relative_quota};
            $region_quotas{$region_pair}{fully_used} = 0;
        }; $region_quotas{$region_pair}{quota} = $current_quota;
        $total_quota += $current_quota;
    };

    my $under_quota = 1;

    until ($under_quota == 0) {

        my $remaining_count = $self->{sample_count_current} - $fixed_total;
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
                }
                else {
                    $unfixed_rel_quota +=
                    $region_quotas{$region_pair}{relative_quota};
                    $region_quotas{$region_pair}{fully_used} = 0;
                };
                $current_quota = 1 if $current_quota == 0; 
                $region_quotas{$region_pair}{quota} = $current_quota;
                $total_quota += $current_quota;
            };
        };

        if ($self->{sample_by_regions}) {
            print "Regions under quota: $under_quota \n"; #remove once working
        }
    };

    $region_quotas{summary}{region_pair_count} = $region_pair_count;
    $region_quotas{summary}{total_quota} = $total_quota;

    $self->set_param (region_stats => \%region_stats);
    $self->set_param (region_quotas => \%region_quotas);

    return %region_quotas;
}

sub load_data {    

    #############################################
    ######          LOAD THE DATA          ######

    my $self = shift;

    chdir ($self->{directory});

    # load phylogeny related data if required
    my @trees = [""];

    if ($self->{use_phylogeny}) {

        ###  read in the trees from the nexus file

        #  but first specify the remap (element properties) table to use to match the tree names to the basedata object
        #  make sure we're using array refs for the columns
        if (not reftype $self->{remap_input}) {
            $self->{remap_input} = [$self->{remap_input}];
        }
        if (not reftype $self->{remap_output}) {
            $self->{remap_output} = [$self->{remap_output}];
        }
        
        my ($remap, $use_remap);

        if (!defined $self->{nexus_remap}) {
            warn "using phylogeny, but nexus_remap arg not specified\n"
        }
        else {
            $remap = Biodiverse::ElementProperties->new;
            $remap->import_data (
                file                  => $self->{nexus_remap},
                input_sep_char        => "guess",
                input_quote_char      => "guess",
                input_element_cols    => $self->{remap_input},
                remapped_element_cols => $self->{remap_output},
            );
            $use_remap = exists($remap->{ELEMENTS});
        }

        my $nex = Biodiverse::ReadNexus->new;

        my $nexus_file = File::Spec->catfile ($self->{directory}, $self->{nexus_file});
        $nex->import_data (
            file                   => $nexus_file,
            use_element_properties => $use_remap,
            element_properties     => $remap,
        );

        my @trees = $nex->get_tree_array;

        #my $use_remap = exists($remap->{ELEMENTS});
        ## read the nexus file
        #my $read_nex = Biodiverse::ReadNexus->new;
        #$read_nex->import_data (  file => $self->{nexus_file},
        #                            use_element_properties => $use_remap,
        #                            element_properties => $remap,
        #                            );
        #
        #  get an array of the trees contained in the nexus file
        #@trees = $read_nex->get_tree_array;
        
        #  just a little feedback
        my $tree_count = scalar @trees;
        if ($tree_count) {
            $self->set_param (
                tree_count => $tree_count,
                trees      => \@trees,
            );
        }
        
        print "\n$tree_count trees parsed from $self->{nexus_file}\nTree names are: ";
        my @names;
        foreach my $tree (@trees) {
                push @names, $tree->get_param ('NAME');
        }
        print "\n  " . join ("\n  ", @names), "\n";
    };
        
    ###  read in the basedata object
    my $bd = Biodiverse::BaseData->new (file => $self->{basedata_filepath});
    $self->set_param (bd => $bd);
    $self->set_param (groups_ref => $bd->get_groups_ref);
    
    my $indices = Biodiverse::Indices->new (BASEDATA_REF => $self->{bd});
    $self->{indices} = $indices;
};

sub prepare_regions {
            
        ######################################################
        #  get region stats and quotas                       #
        ######################################################
    
    my $self = shift;
    
    my $bin_count      = $self->{bins_count};
    my $regions_output = q{};
    my $grouplist      = $self->{grouplist};
    my @grouplist      = @$grouplist;

    # check if regions for each group are available in the basedata
    if ($self->{do_output_regions} or $self->{sample_by_regions}) {
        my @element_test = split /:/, $grouplist[0];
        if (!$element_test[2]) { # if there is no 3rd component to define each group, after x,y
            $self->set_param (
                do_output_regions => 0,
                sample_by_regions => 0,
                region_codes      => 0,
            );
            print "\nCan't use regions (".$self->{region_header}.") because this information was not stored in the Biodiverse basedata.\n";
        }
        else {
            print "Regions (".$self->{region_header}.") included in output.\n";
        };
    };
    
    # add extra columns to the .csv file header for region names or codes if needed
    if ($self->{do_output_regions}) {
        $regions_output = "," . $self->{region_header} . "1," . $self->{region_header} . "2";
    };
    
    if ($self->{region_codes}) {
        $regions_output .= "," . $self->{region_header} . "_code1," . $self->{region_header} . "_code2";
    };

    # more detailed output is appropriate where not sampling by regions
    if (!$self->{sample_by_regions}) {
        $self->set_param (verbosity => 3);
    }

    #sets which column has the region code.  Set by parameter once working
    $self->set_param (region_column => 3); 

    my %region_stats  = $self->get_region_stats();
    my %region_quotas = $self->get_region_quotas;

    $self->set_param (
        region_pair_count => $region_quotas{summary}{region_pair_count},
        total_quota      => $region_quotas{summary}{total_quota},
        regions_output   => $regions_output,
    );

    if ($self->{sample_by_regions}) {
        printf "\nReady to sample %d region pairs and %d site pairs.\n",
                $self->{region_pair_count},
                $self->{total_quota};
    };
    
}

sub get_grouplist {
    my $self = shift;
    
    my @grouplist = $self->{bd}->get_groups;
    my $groups_ref = $self->{bd}->get_groups_ref;
    my $i; # $i is the pointer for the current group
    my $group1;
    my $group_count = scalar @grouplist;
    
    ###  apply site richness limit
    if ($self->{min_group_richness} > 1) {
        my $samples_message = $self->{min_group_samples} > 1
                            ? ' unless they have at least ' . $self->{min_group_samples} . ' records'
                            : q{};
        printf "\nRemoving sites with less than %d species %s\n", $self->{min_group_richness}, $samples_message;

        my (@label_list, @grouplist_new, $remove_count, $label_count);
        my $keep_count = 0;
        my %subelement_hash;

        foreach $i (0..$group_count-1) {
            $group1 = $grouplist[$i];
            %subelement_hash = $groups_ref->get_sub_element_hash(element => $group1);
            $label_count = keys %subelement_hash;
            if ($label_count >= $self->{min_group_richness}) {
                $grouplist_new[$keep_count] = $group1;
                $keep_count++;
            }
            elsif ($self->{min_group_samples} > 1) { # the number of species is less than min_group_richness
                # but do they have enough samples to include anyway
                my $sample_count=0;
                foreach my $samples (values %subelement_hash) {
                    $sample_count = $sample_count + $samples;
                };
                if ($sample_count >= $self->{min_group_samples}) {
                    $grouplist_new[$keep_count] = $group1;
                    $keep_count++;
                }
                else {
                    $remove_count++;
                }
            }
            else {
                $remove_count ++;
            };
        };
        
        @grouplist = @grouplist_new;
        print "\n$remove_count groups with less than $self->{min_group_richness} species were removed\n";
        $group_count = $#grouplist;
        print "$group_count groups remaining\n";
    };

    return @grouplist;
}

sub do_sampling {
    
    my $self = shift;
    my $bd = $self->{bd};
    my $indices = $self->{indices};
    my $region_quotas = $self->{region_quotas};
    my %region_quotas = %$region_quotas;
    my $region_stats = $self->{region_stats};
    my %region_stats = %$region_stats;
    my $region_pair_count = $region_quotas{summary}{region_pair_count};
    my $n = $self->{sample_count_current};
    my ($group1, $group2, $label_hash1, $label_hash2, $group_count);
    my (%gl1,%gl2,%phylo_abc, $phylo_sorenson, %abc, $sorenson);
    my (@coords1,@coords2);
    my $bin_count = $self->{bins_count};
    my $groups_ref = $self->{groups_ref};
    my $dist_measure = $self->{dist_measure};
    my $quota_dist_measure = $self->{quota_dist_measure};
    my ($geog_dist, $geog_dist_output, $regions_output, $output_row, $all_sitepairs_done, $frequency, $proportion_needed);
# delete $frequency once code updated    
    my ($all_sitepairs_kept,$regions_done);
    my ($one_quota,$one_count, $skip) = ($self->{one_quota},0, 0);
    my $result_file_handle = $self->{result_file_handle};
    my ($printedProgress_all, $storedProgress_all) = (0,0);
    my $dist_output;
    my $measure_count = $self->{measure_count};
    my $dist_exceeded;
    my $dist_limit = $self->{dist_limit};
    
    my $single_dist_measure;
    if ($measure_count == 1) {
        $single_dist_measure = (keys($dist_measure))[0];
    };
    
    #set up to report the total sum of the number of species at both sites, optional extra to use as a weighting factor
    my $species_sum = 0;
    my $sum = 0;
    if (exists($self->{species_sum})) {
        $species_sum = $self->{species_sum};
    }
    
    # start a feedback table, if requested
    if ($self->{feedback_table}) {
        $self->feedback_table(open => 1);
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
        my $total_samples = $region_pair_quota;
        my $one_quota_region = int($one_quota * $region_pair_quota);
        $one_count = 0;
        
        # set bins for this region pair
        $self->set_param (bins_sample_count => $region_pair_quota);
        my @bins = $self->make_bins();
        my $bins_max = $bins[0]{maximum};
        my $max_class = $self->{max_class};
        
        ####  calculate sampling frequency for this region pair
        #my $all_comparisons = $region_pair{all_pairs};
        #
        #if ($all_comparisons > $total_samples) {
        #    $frequency = $all_comparisons / $total_samples;
        #}
        #else {    
        #    $frequency = 1;
        #};
        
        ###  calculate sampling PROPORTION for this region pair
        my $all_comparisons = $region_pair{all_pairs};
        if ($all_comparisons > $total_samples) {
            $proportion_needed = $total_samples / $all_comparisons;
        }
        else { $proportion_needed = 1; }

        #add proportion needed to the hash for feedback
        $region_pair{proportion_needed} = $proportion_needed;
        $toDo = min($total_samples,$all_comparisons);
        
 ### DECIDE HERE WHETHER TO (A) GENERATE ALL, SHUFFLE AND USE OR (B) GENERATE AS NEEDED, AND CHECK IF USED
 ### CALCULATE AS PROPORTION, NOT FREQUENCY AND DO ALL IF PROPORTION GREATER THAN A THRESHOLD
 ### FOR NOW SET THIS PROPORTION, BUT WILL USE A FUNCTION TO CALCULATE
        my $sampling_threshold = 0.1;
        my $sampling_strategy = "iterative";   # a default value
        my (%all_pairs, $pair_name, $i);
        my $same_sites = ($region1 eq $region2);
        my @site_pairs_random;
    
        if ($self->{verbosity} >=2) {
            if ($same_sites) {
                if ($self->{sample_by_regions}) {
                    print "\nSeeking ". $region_pair_quota . " site pairs within region " . $region1.".\n";
                    print "Groups in region: $groupcount1\n";
                }
                else {
                    print "\nSeeking ". $region_pair_quota . " site pairs\n";
                    print "Groups: $groupcount1\n";                        
                };
            }
            else {
                print "\nSeeking ". $region_pair_quota . " site pairs between region " . $region1. " and region " . $region2 . ".\n";
                print "Groups in region " . $region1 . ": " . $groupcount1 . ", in region " . $region2 . ": " . $groupcount2 . "\n";    
            }
            print "Possible comparisons: $all_comparisons \n";
            if ($one_quota) {print "Quota for samples where difference = 1: $one_quota_region\n";};
            if (@bins and ($bins[0]{classes}>1)) {
                print "Quota per bin:  $bins[1][1]\n";
            };

            my $round_prop = sprintf("%.3f",  $proportion_needed);
            print "Sampling proportion: $round_prop\n\n";
        }
        
        if ($proportion_needed > $sampling_threshold) {
            $sampling_strategy = "complete";

            # create a hash of all site-pairs - no randomization needed
            while (scalar @grouplist1) {
                $group1 = pop @grouplist1;
                if ($same_sites) {
                    foreach $group2 (@grouplist1) {                    
                        #print $group1,' ',$group2,"\n";
                        $pair_name = $group1." ".$group2;
                        $all_pairs{$pair_name} = 1;
                        $i++;
                    }
                } else {  # for sampling two different regions (and thus a full matrix, not a diagonal half)
                        foreach $group2 (@grouplist2) {                    
                        $pair_name = $group1." ".$group2;
                        %all_pairs = ($pair_name => 1);
                    }
                }
            print scalar @grouplist1,"\t";  #FOR FEEDBACK DELETE ONCE WORKING
            }
            
            # prepare to iterate randomly through the site pairs
            @site_pairs_random = shuffle(keys %all_pairs);
        }
        
        my (%dist_result,$j, @groups2);
        my $previous_j = 0;
        
        # create a hash of sampled site-pairs
        my (%sampled_pairs, $valid_sample);

        ###############################
        #  the main loop starts here  #  
        ###############################
        MAIN_LOOP:
        foreach my $n (0..$total_samples -1) {  ########## loop here on a while or until.  Then iterate n.
            
            if ($sampling_strategy eq "complete") {  #get the next site pair from a complete sample
                $pair_name = $site_pairs_random[$n];
                my @groups = split(" ",$pair_name);
                $group1 = $groups[0];
                $group2 = $groups[1];                
            }
            else {                                  #get the next site pair from a new iterative sample
                $valid_sample = 0;
                
                GET_VALID_SAMPLE:
                while ($valid_sample==0) {
                    my ($pair_name1, $pair_name2);
                    $group1 = @grouplist1[int(rand($groupcount1))];
                    $group2 = @grouplist2[int(rand($groupcount2))];
                    if ($group1 eq $group2) {
                        next GET_VALID_SAMPLE
                    }
                    $pair_name1 = $group1." ".$group2;
                    $pair_name2 = $group2." ".$group1;
                    if (exists $sampled_pairs{$pair_name1} or exists $sampled_pairs{$pair_name2}) {
                        next GET_VALID_SAMPLE
                    }
                    $valid_sample=1;
                }
            }
            
            # now we have a valid sample - add it to the sample list
            %gl1 = ($group1 => 0);    
            @coords1     = $groups_ref->get_element_name_as_array (element => $group1);
            $label_hash1 = $groups_ref->get_sub_element_hash (element => $group1);

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
                
                $group2  = $groups2[$j];
                @coords2 = split /:/, $group2;
                
                ####################################################################################
                # the following line is a more generic, higher level version of the preceding one  #
                # it is not being used as it alone adds 30% to program runtime                     #
                # however, it can be reverted to if changes to the basedata data structure result  #
                # in the preceding line not working                                                #
                #@coords2 = $groups_ref->get_element_name_as_array(element => $group2);          #
                ####################################################################################
                
                $label_hash2 = $groups_ref->get_sub_element_hash(element => $group2);
                
                %gl2 = ($group2 => 0);
                
                 # calculate the geographic distance
                if (exists($dist_measure->{geographic})) {  # geographic
                    $dist_result{geographic} = sprintf("%.3f", sqrt( ($coords1[0] - $coords2[0]) ** 2 + ($coords1[1] - $coords2[1]) ** 2 ));
                };
                
                # check for results beyond the distance threshold
                # NOTE this check is performed before the beta diversity measures are calculated so it only works for geographic distance.
                # This means no time is wasted on biological measures where the sites are too geographically distant
                # but if a limit was wanted where the quota_dist_measure was not geographic, this check would need to be placed after those
                # measures.
                if ($dist_limit) {
                    if (exists($dist_result{$quota_dist_measure})) {
                        if ($dist_result{$quota_dist_measure} > $dist_limit) {
                            $dist_exceeded = 1;
                        };
                    };
                };
                
                if (! $dist_exceeded) {    
                    # calculate the phylo S�rensen distance
                    if (exists($dist_measure->{phylo_sorenson})) {  # phylo_sorenson
                        $dist_result{phylo_sorenson} = -1;      # an undefined distance result is given as -1
                        %phylo_abc = $indices->calc_phylo_abc(
                            group_list1  => \%gl1,
                            group_list2  => \%gl2,
                            label_hash1  => $label_hash1,
                            label_hash2  => $label_hash2,
                            trimmed_tree => $self->{trimmed_tree},
                        );
            
                        if (($phylo_abc{PHYLO_A} + $phylo_abc{PHYLO_B}) and ($phylo_abc{PHYLO_A} + $phylo_abc{PHYLO_C})) {  #  sum of each side must be non-zero
                            $dist_result{phylo_sorenson} = sprintf ("%.6f", eval {1 - (2 * $phylo_abc{PHYLO_A} / ($phylo_abc{PHYLO_A} + $phylo_abc{PHYLO_ABC}))});
                        };
                    }

                    # calculate the S�rensen distance                                    
                    if (exists($dist_measure->{sorenson})) {  # sorenson
                        $dist_result{sorenson} = -1;      # an undefined distance result is given as -1
                        %abc = $indices->calc_abc(
                            group_list1 => \%gl1,
                            group_list2 => \%gl2,
                            label_hash1 => $label_hash1,
                            label_hash2 => $label_hash2,
                        );
        
                        if (($abc{A} + $abc{B}) and ($abc{A} + $abc{C})) {  #  sum of each side must be non-zero
                            $dist_result{sorenson} = sprintf("%.6f", eval {1 - (2 * $abc{A} / ($abc{A} + $abc{ABC}))});
                        };

                        # an optional extra feature, calculates the sum of species across the two sites (ignoring whether they are shared)
                        $sum = ",".$abc{ABC};
                    };
                    
                    # if any distance measure has a valid result
                    if (   (exists($dist_measure->{sorenson}) and ($dist_result{sorenson} != -1))
                        or (exists($dist_measure->{phylo_sorenson}) and ($dist_result{phylo_sorenson} != -1))
                        or (exists($dist_measure->{geographic}) and $dist_result{geographic} >= 0)) {
        
                        #format the distance result(s)
                        if ($measure_count > 1) {
                            foreach my $result (sort keys(%dist_result)) {
                                if ($dist_output) {
                                    $dist_output = $dist_output. "," .$dist_result{$result};
                                }
                                else {
                                    $dist_output = $dist_result{$result};
                                };
                            };
                        }
                        else {
                            $dist_output = $dist_result{$single_dist_measure};
                        };

                        # set the region names output
                        if ($self->{do_output_regions}) {
                            $regions_output = ",".$region1.",".$region2;
                        }
                        else {
                            $regions_output = "";
                        }

                        # set the region codes output
                        if ($self->{region_codes}) {
                            $regions_output .= ",".$region_stats{$region1}{code}.",".$region_stats{$region2}{code};
                        };

                        if ($one_quota_region) { #1st of two alternative methods for managing the spread of distance values
                            if ($dist_result{$quota_dist_measure} == 1) {
                                $one_count ++;
                                if ($one_count >= $one_quota_region) {
                                    $skip = 1;
                                    if ($one_count == $one_quota_region) {
                                        if ($self->{verbosity} >= 2) {
                                            print "Quota of $one_quota_region scores of 1 reached after $count iterations \n";
                                        };
                                    };
                                };
                            };
                        }
                        elsif (@bins and $bin_count > 1) { #2nd of two alternative methods for managing the spread of distance values
                            if ($max_class and $dist_result{$quota_dist_measure} == $bins_max){  #check if the distance value is within a separate single-value top bin (normally value 1)
                                if (!$bins[$bin_count][3]){ #if quota not previously reached
                                    $bins[$bin_count][2] ++;
                                    if ($bins[$bin_count][1] <= $bins[$bin_count][2]) {
                                        if ($self->{verbosity} >=2) {
                                            print "   Quota of $bins[$bin_count][2] scores of 1 reached from " . ($loops + 1) ." site pairs \n";
                                        };
                                        $bins[$bin_count][3] = 1; # quota reached so set full = true
                                        $bins[$bin_count][4] = $loops+1;  # record the number of site pairs needed to fill this bin
                                        $diss_quotas_reached ++;
                                    };
                                }
                                else {
                                    $skip = 1;
                                };
                            }
                            else { #for all values except a separate single-value top bin (normally value 1)
                                for my $bin_number (1..($bin_count-$max_class)) {
                                    if ($dist_result{$quota_dist_measure} < $bins[$bin_number][0]) {
                                        if (!$bins[$bin_number][3]){    #if quota not previously reached
                                            $bins[$bin_number][2] ++;
                                            if ($bins[$bin_number][1] <= $bins[$bin_number][2]) {
                                                my $bin_min = 0;
                                                if ($bin_number > 1) {
                                                    $bin_min = $bins[$bin_number-1][0];
                                                };
                                                if ($self->{verbosity} >=2) {
                                                    print "   Quota of $bins[$bin_number][2] scores of " . sprintf("%.3f", $bin_min) . " to < " . sprintf("%.3f",$bins[$bin_number][0]) . " reached from $loops site pairs \n";
                                                };
                                                $bins[$bin_number][3] = 1; #quota reached so set full = true
                                                $bins[$bin_number][4] = $loops+1;  # record the number of site pairs needed to fill this bin
                                                $diss_quotas_reached ++;
                                                
                                            };
                                        }
                                        else {
                                            $skip = 1;
                                        };
                                        last;  #  of MAIN_LOOP?? if so then need to use label for clarity
                                    };
                                };
                            };
                        };

                        if (($diss_quotas_reached > 0 and $diss_quotas_reached >= $bin_count) or ($count >= $region_pair_quota)) {
                            $region_completed = 1;
                        }
            
                        if (!$skip) { 
                            $output_row = "$coords1[0],$coords1[1],$coords2[0],$coords2[1],$dist_output".$regions_output.$sum."\n";
                            print $result_file_handle "$output_row";
                            $count++;
                        #}
                        #else {
                        #    print "undefined result for $coords1[0],$coords1[1] and $coords2[0],$coords2[1], $regions_output\n";;
                        };
                    };
                            
                };
                
                $j++;
                $skip = 0;
                $loops++;
                $dist_output = "";
                $dist_exceeded = 0;
                $sum = q{};
                
                if ($self->{verbosity} == 3) {
                    $progress = int (100 * $loops / $toDo);
                    if (($progress % 5 == 0) or (($diss_quotas_reached == $bin_count) and $bin_count>1)) {
                        if ($printedProgress != $progress) {
                            $storedProgress = int (100 * $count / $region_pair_quota);
                            print "Sampled: $progress%       $loops      Stored: $storedProgress%     $count\n";
                            $printedProgress = $progress;
                        };
                    };
                    print "\n" if $count == $toDo;    
                };
            };
        };

        #give feedback for bins where quota was not filled
        if ($self->{verbosity} >=2) {
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
            }
            else {
                print "\nAll quotas met after $loops site pairs.\n";
            };
        };

        # Update global progress stats after each region
        $all_sitepairs_done += $loops;
        $all_sitepairs_kept += $count;
        $regions_done += 1;
        $region_pair{sitepairs_done} = $loops;
        $region_pair{sitepairs_kept} = $count;

        my $bins_all = $self->{bins_all};
        my @bins_all = $bins_all;
        for my $class (1 .. (scalar @bins_all - 1)) {
            #add the total for each class in this region to create a global total
            $bins_all[$class][2] += $bins[$class][2];
            #add to a count if quota met for each class in this region to create a global count for each class
            $bins_all[$class][3] += $bins[$class][3]; 
        }

        my $progress_all;
        if ($self->{sample_by_regions}) {
            $progress_all = int (100 * $regions_done / $region_pair_count);
        }
        else {
            $progress_all = int (100 * $all_sitepairs_done / $toDo);
        }

        # Feedback on completed region after each region
        if ($self->{verbosity} == 1) {
            print "$progress_all%  Region";
            if ($region1 eq $region2) {
                print " $region1.  "
            }
            else {
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
        if ($self->{verbosity} == 0 or ($regions_done == $region_pair_count)) {
            if (($progress_all % 5 == 0) or ($regions_done == $region_pair_count)) {
                if ($printedProgress_all != $progress_all) {
                    $storedProgress_all = int (100 * $regions_done / $region_pair_count);
                    print "Done: $progress_all%      Sites pairs done: $all_sitepairs_done   Site pairs stored: $all_sitepairs_kept";
                    if ($self->{sample_by_regions}) {
                        print "     Region pairs: $regions_done\n";
                    }
                    else {
                        print "\n";
                    }
                    $printedProgress_all = $progress_all;
                };
            };
        };

        # send feedback for the completed region to the feedback table
        if ($self->{feedback_table}) {
            $self->feedback_table(
                one_region_pair  => 1,
                region1          => $region1,
                region2          => $region2,
                region_pair_hash => \%region_pair,
                region_bins      => \@bins,
            );
        }

        $region_quotas{$current_region_pair} = %region_pair;
    };

    # close the feedback table
    if ($self->{feedback_table}) {$self->feedback_table(close => 1);}

    $self->set_param (
        all_sitepairs_done => $all_sitepairs_done,
        all_sitepairs_kept => $all_sitepairs_kept,
    );

}

sub feedback_table {
# this sub produces a .csv file with statistics on sampling for each region pair
# or if not sampling by regions, then as a single row for the whole sample.

    my $self = shift;
    my %args = @_;
    my $feedback_file_handle = $self->{feedback_file_handle};

    if ($args{open}) {
        my @filename = split /.csv/,$self->{output_file_name};
        my $feedback_filename = $filename[0] . $self->{feedback_suffix} . ".csv";
        $self->set_param (feedback_file_name => $feedback_filename);
        open($feedback_file_handle, "> $feedback_filename ") or die "Can't write $self->{directory}\\$feedback_filename: $!";
        if ($feedback_file_handle) {
            $self->set_param (feedback_file_handle => $feedback_file_handle);
            print "\nFeedback table will be written to $feedback_filename\n";
        }
    }
    elsif ($args{close}) {
        my $success = close($feedback_file_handle);
        if ($success) {
            print "\nFinished writing feedback table $self->{feedback_file_name}\n";
        }
        else {
            print "\nNote: feedback table $self->{feedback_file_name} was not closed successfully\n";
        }
        
    }
    elsif ($args{one_region_pair}) {
        my $feedback_header_done = $self->{feedback_header_done};

        # write the header line if not yet written
        if (! $feedback_header_done) {
            my $header_text = "Region1,Region2,GroupCount1,GroupCount2,Species count1,Species count2,Species shared,AllPairs,Region pair quota,Frequency,Site pairs searched,Site pair output,Bins quota";
            for my $bindex (1..$self->{bins_count}) {
                $header_text .= ",Bin".$bindex.",Quota $bindex reached after";
            }
            print $feedback_file_handle "$header_text\n";
            $self->set_param (feedback_header_done => 1);
        }

        # collect all of the values to be reported
        my ($region1, $region2) = ($args{region1}, $args{region2});
        my $region_pair = $args{region_pair_hash};

        my $region1_stats = $self->{region_stats}{$region1};
        my $region2_stats = $self->{region_stats}{$region2};
        my $bins = $args{region_bins};

        my $shared = $region_pair->{labels_shared};

        # build the row of output for this region pair as a string
        my $round_freq = sprintf("%.3f",  $region_pair->{frequency});
        my $row_text = "$region1,$region2,$region1_stats->{group_count},$region2_stats->{group_count},$region1_stats->{label_count},$region2_stats->{label_count},";
        $row_text .= "$shared,$region_pair->{all_pairs},$region_pair->{quota},$round_freq,$region_pair->{sitepairs_done},$region_pair->{sitepairs_kept},$$bins[1][1]";

        for my $bindex (1..$self->{bins_count}) {
            $row_text .= ",$$bins[$bindex][2],$$bins[$bindex][4]";
        }

        $row_text .= "\n";

        # write the row to file
        print $feedback_file_handle "$row_text";

    }
    elsif ($args{all}) {
    };
};

sub DESTROY {
    my $self = shift;

    foreach my $key (keys %$self) {  #  clear all the top level stuff

        delete $self->{$key};        
    }
}

1;
