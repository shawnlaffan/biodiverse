package BdPD::PD_Indices;

use strict;
use warnings;
use Carp;

our $VERSION = '0.18003';

sub get_metadata_calc_pe_cwe {
    my %arguments = (
        description    => 'Calculate Phylogenetic corrected weighted endemism',
        name           => 'PE Corrected Weighted Endemism',
        type           => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc       => [qw /calc_pe calc_pd/],
        uses_nbr_lists => 1,  #  how many lists it must have
        indices        => { 
            PE_CWE => {
                description => 'Phylogenetic corrected weighted endemism.  '
                                . "Average range restriction per unit branch length\n"
                                . 'PE_CWE = PE_WE / PD',
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

#  calculate corrected weighted endemism = PE / PD, equals endemism per unit branch length
sub calc_pe_cwe {
    my $self = shift;
    my %args = @_;

    #  don't tell me about divide by zero and unitialised values - they can happen
    no warnings qw /uninitialized numeric/;  
    my $PE_CWE = eval {$args{PE_WE} / $args{PD}};
    
    my %results = (PE_CWE => $PE_CWE);
    
    return wantarray ? %results : \%results;
}

sub get_metadata_calc_neo_endemism {
    
    my %arguments = (
        name            =>  'Neo Endemism',
        type            =>  'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        description     =>  "Neo endemism and related measures based on terminal branch lengths on a chronogram (dated or ultrametric phylogeny)",
        pre_calc        =>  [qw /calc_abc calc_abc2/],
        pre_calc_global =>  [qw /get_node_range_hash get_trimmed_tree get_pe_element_cache/],  # CHECK WHICH ARE NEEDED
        uses_nbr_lists  =>  1,  #  how many sets of lists it must have
        indices => {
            NEO_END => {
                description =>  "Neo endemism  = 1 / (terminal branch length x taxon range) summed for taxa present",
                reference   =>  "Derived from Davis et al. (2008) Mol. Ecol.  http://dx.doi.org/10.1111/j.1365-294X.2007.03469.x"},
            NEO_END_L => {
                description =>  "Neo endemism, weighted by local range of each species",
                reference   =>  "Derived from Davis et al. (2008) Mol. Ecol.  http://dx.doi.org/10.1111/j.1365-294X.2007.03469.x"},
            NEO_END_P => {
                description =>  "Neo endemism calculated in relation to the total tree length"},
            NEO_TAXA => {
                description =>  "1 / terminal branch length summed for taxa present.  Leaves out the endemism component"},
            NEO_TAXA_L => {
                description => "1 / terminal branch length summed for taxa present, weighted by local range of each species.\n"
                               . "Leaves out the endemism component"},
            MEAN_AGE =>  {
                description =>  "Mean of terminal branch length for taxa present"},
        },
        required_args => {'tree_ref' => 1}
    );
           
    return wantarray ? %arguments : \%arguments;   
}

sub calc_neo_endemism {
#  calculate the neo endemism of the species in the central elements only
#  this function expects a tree reference as an argument.
#  the software should run for any tree, but the results are meaningful for a chronogram
#  private method.

    my $self = shift;
    my %args = @_;

    my $label_list = $args{label_hash_all};
    my $tree_ref = $args{trimmed_tree};
    my $node_ranges =  $args{node_range};
    
    my $bd = $args{basedata_ref} || $self -> get_param ('BASEDATA_REF') || $self;
    
    #create a hash of terminal nodes for the taxa present
    my $all_nodes = $tree_ref -> get_node_hash;
    
    my ($NEO_END, $NEO_END_L, $NEO_END_P, $NEO_TAXA, $NEO_TAXA_L, $MEAN_AGE, $terminal_length, $node, $valid_taxon_count);
    ($NEO_END, $NEO_END_L, $NEO_END_P, $NEO_TAXA, $NEO_TAXA_L, $node, $valid_taxon_count) = (0,0,0,0,0,0,0);

    #  loop over the nodes and run the calcs
    foreach my $name (keys %$label_list) {
        my $range = $$node_ranges{$name};
        my $local_range = $$label_list{$name};
        if (exists($$all_nodes{$name})) {
            $node = $$all_nodes{$name};
            $terminal_length = $node -> get_length;
            $valid_taxon_count ++;
        }
        
        #my $range_length = $terminal_length * $range;
        if ($terminal_length and $range) {
            $NEO_END += eval {1 / ($terminal_length * $range)} || 0;
            $NEO_END_L += eval {$local_range / ($terminal_length * $range)} || 0;            
            $NEO_TAXA += eval{1 / $terminal_length} || 0;
            $NEO_TAXA_L += eval {$local_range / $terminal_length} || 0;
            $MEAN_AGE += eval{$terminal_length};
        }
    }
    
    $NEO_END_P = eval {$NEO_END * $args{trimmed_tree} -> get_total_tree_length};
    if ($valid_taxon_count) {
        $MEAN_AGE = eval{$MEAN_AGE / $valid_taxon_count};
    } else{ $MEAN_AGE = undef};
    
    #Neo endemism   = sum for all taxa of: 1 / (terminal branch length * taxon range size)
    #Neo endemism_P = sum for all taxa of: 1 / (terminal branch length * taxon range size)
    #                  where branch length is expressed as a proportion of the total tree length,
    #                  thus eliminating units of branch length from the index
    #Neo taxa       = sum for all taxa of: 1 / terminal branch length
    #                 in other words, the neo without the endemism
    #Mean age       = mean of terminal branch length
    
    my %results =   (NEO_END => $NEO_END,
                    NEO_END_L => $NEO_END_L,
                    NEO_END_P => $NEO_END_P,
                    NEO_TAXA => $NEO_TAXA,
                    NEO_TAXA_L => $NEO_TAXA_L,
                    MEAN_AGE => $MEAN_AGE
                    );

    return wantarray
            ? %results
            : \%results;
}


1;
