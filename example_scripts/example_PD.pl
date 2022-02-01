#  example script for reading in a set of trees fromn a nexus file and then
#  linking them to an existing basedata object

use strict;
use warnings;
use Carp;  #  warnings and dropouts
use File::Spec;  #  for the cat_file sub 
use English qw ( -no_match_vars );

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;  #  for remaps
use Biodiverse::ReadNexus;
use Biodiverse::Tree;


#############################################
######       SET PARAMETERS HERE       ######

### FILE IMPORT & EXPORT PARAMETERS
my $dir = 'C:\Working\Study_Taxa\Herps\Hylidae';  #  working directory
chdir ($dir);
my $nexus_file = File::Spec->catfile ($dir, "Hylid_tree_AustOct08.nex");
my $nex_remap  = File::Spec->catfile ($dir, "Translate_Hylid_Names_aug08.csv");

# columns in the order they are needed, start counting from zero
my @remap_input_element_cols = [3];  
#  columns in the order they are needed, use as many columns as the basedata has
my @remapped_element_cols = [1];  

my $basedata_file = File::Spec->catfile ($dir, "Hylids_6Apr09_1deg.bds");
my $basedata_out  = File::Spec->catfile ($dir, "bd_temp.bds");  #  bodgy

#  set to 1 to retain outputs after calculation
my $retain_outputs = 0; 

#  Set to 1 to save basedata after analysis.
#  This makes sense primarily if the outputs are retained,
#  and can thus be saved with the basedata
my $save_basedata = 0;

### ANALYSIS PARAMETERS
my $do_spatial = 0;  # (do the spatial analysis: 1 for yes, 0 for no)
my $spatial_output_prefix = 'sp_';

# Define neighbour sets 1 and 2
my $spatial_conditions = ['sp_self_only()', 'sp_circle (radius => 1)'];
my $analyses_to_run    = [qw /calc_pd calc_pe/];

# (do the matrix (and cluster) analyses: 1 for yes, 0 for no)
my $do_matrix_cluster = 1;  
my $matrix_cluster_output_prexif = 'matrix_';

# Define spatial conditions or subsampling for the cluster analysis
#my $spatial_conditions_clust = ['sp_select_all ()']; # this one samples all group pairs
#  sample every second group
my $spatial_conditions_clust =
    ['sp_select_sequence (frequency => 2, cycle_offset => 0)'];

# (create a spatial index: 1 for yes, 0 for no)
#       this is reccomended for spatial analyses
#       and for cluster analyses with spatial conditions
#       but must not be used with matrix subsampling
my $do_build_index = 0;


######        END OF PARAMETERS        ######
#############################################



#############################################
######          LOAD THE DATA          ######

###  read in the trees from the nexus file

#  but first specify the remap (element properties) table to use to match the tree names to the basedata object
my $remap = Biodiverse::ElementProperties->new;
$remap->import_data (
    file => $nex_remap,
    input_sep_char        => 'guess',   #  or specify yourself, eg ',' for a comma
    input_quote_char      => 'guess', #  or specify yourself, eg:'"' or "'" (for double or single quotes)
    input_element_cols    => @remap_input_element_cols,  # defined above
    remapped_element_cols => @remapped_element_cols,  #  defined above
    include_cols          => undef,  #  undef or empty array [] if none are to be solely included
    exclude_cols          => undef,  #  undef or empty array [] if none are to be excluded
);


#  read the nexus file
my $read_nex = Biodiverse::ReadNexus->new;
$read_nex->import_data (
    file                   => $nexus_file,
    use_element_properties => 1,  #  set to zero or undef if you don't have a remap
    element_properties     => $remap,
);

#  get an array of the trees contained in the nexus file
my @trees = $read_nex->get_tree_array;

#  just a little feedback
my $tree_count = scalar @trees;
print "$tree_count trees parsed from $nexus_file\nNames are: ";
my @names;
foreach my $tree (@trees) {
        push @names, $tree->get_param ('NAME');
}
print join (q{, }, @names), "\n";

###  read in the basedata object
my $bd = Biodiverse::BaseData->new (file => $basedata_file);


#############################################
######         RUN THE ANALYSES        ######

if ($do_build_index) {
    #  build the spatial index
    $bd->build_spatial_index (
        resolutions => $bd->get_groups_ref->get_param ('CELL_SIZES')
    );
};

###### SPATIAL ANALYSIS
if ($do_spatial) {
    #  loop over the trees and add a spatial analysis to the basedata for each of the trees
    #  assuming the trees have unique names, which I think is reasonable
    
    ###  add a spatial analysis for each tree but use the same spatial params for each
    #  the first will take longer then the rest as they can recycle the neighbourhoods
    #  and thus save search times
    
    foreach my $tree_ref (@trees) {
        my $name = $spatial_output_prefix . $tree_ref->get_param ('NAME');
        my $output = $bd->add_spatial_output (name => $name);
        my $success = eval {
            $output->run_analysis (
                spatial_conditions => $spatial_conditions,
                calculations       => $analyses_to_run,
                tree_ref           => $tree_ref,
            );
        };
        croak $EVAL_ERROR if $EVAL_ERROR;

        if ($success) {  #  export to CSV using defaults
            $output->export (
                file   => $name . '.csv',
                format => 'Delimited text',
                list   => 'SPATIAL_RESULTS',
            );  
        }
      
        if (not $retain_outputs) {
            $bd->delete_output (output => $output);
        }
    }
};

###### MATRIX AND CLUSTER ANALYSES
###  add a cluster analysis for each tree, using the same spatial params for each

if ($do_matrix_cluster) {

    foreach my $tree_ref (@trees) {
        my $name_clust = $matrix_cluster_output_prexif . $tree_ref->get_param ('NAME');
        my $output = $bd->add_cluster_output (name => $name_clust);
        my $success = eval {
            $output->run_analysis (
                spatial_conditions   => $spatial_conditions_clust,
                spatial_calculations => $analyses_to_run,  #  run these analyses for each node on the tree - comment out if not needed
                tree_ref             => $tree_ref,
                index                => 'PHYLO_SORENSON',  #  this isn't publicly available yet (2011-01-30)
                linkage_function     => 'link_average',
            );
        };

        if ($success) {
            # to export the cluster tree
            #$output->export (file => $output->get_param ('NAME') . '.nex',
            #                  format => 'Nexus');  #  export cluster tree to Nexus using defaults
            
            #  export sparse matrix format to CSV
            $output->export (
                file   => $output->get_param ('NAME') . '.csv',
                format => 'Matrices', type => 'sparse',
            );  
            
        }
        if (not $retain_outputs) {
            $bd->delete_output (output => $output);
        }
    }
};

if ($save_basedata) {
    $bd->save (file => $basedata_out);
};
