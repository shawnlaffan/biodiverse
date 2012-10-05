package BdPD::PD_Indices;

use strict;
use warnings;
use Carp;

our $VERSION = '0.15';

#  sub calc_pd moved to Bioodiverse::Indices::Phylogenetic
#  the others can follow later
sub _calc_pd { #  calculate the phylogenetic diversity of the species in the central elements only
              #  this function expects a tree reference as an argument.
              #  private method.  
    my $self = shift;
    my %args = @_;
    
    if ($args{get_args}) {
        my %arguments = (description => "Calculate PD for species in both neighbourhoods",
                         name => 'Phylogenetic Diversity',
                         indices =>   {PD => {cluster => undef,
                                              RCOMP => ">",
                                              description => "Phylogenetic diversity"
                                              },
                                       PD_P => {cluster => undef,
                                                RCOMP => ">",
                                                description => "Phylogenetic diversity as a proportion of total tree length"
                                                },
                                       PD_per_Taxon => {cluster => undef,
                                                        RCOMP => ">",
                                                        description => "Phylogenetic diversity per taxon"
                                                        },
                                       PD_P_per_Taxon => {cluster => undef,
                                                          RCOMP => ">",
                                                          description => "Phylogenetic diversity per taxon as a proportion of total tree length"
                                                          }
                                       },
                         type => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
                         pre_calc => 'calc_abc',
                         uses_nbr_lists => 1,  #  how many lists it must have
                         required_args => {'tree_ref' => 1}
                        );  #  add to if needed

        return wantarray ? %arguments : \%arguments;
    }

    #my $labelList = $args{label_hash_all};
    
    my $tree_ref = $args{tree_ref};
    
    #create a hash of terminal nodes for the taxa present
    #my %all_nodes = $tree_ref -> get_node_hash;
    
    #my $current_node; my %included_nodes;
    #my $PD_score;
        
    #foreach my $subLabel (keys %{$labelList}) {
    #  
    #  $current_node = $all_nodes{$subLabel};
    #  
    #  next if not defined $current_node;
    #  
    #  until (exists $included_nodes{$current_node -> get_name}) {  
    #    $included_nodes{$current_node -> get_name} = $current_node -> get_length;
    #    last if ($current_node -> is_root_node);
    #    $current_node = $current_node -> get_parent;
    #  };
    #}
    
    my $nodes_in_path = $self -> get_paths_to_root_node (@_,
                                            labels => $args{label_hash_all},
                                            );
    
    my $PD_score;
    foreach my $node (values %$nodes_in_path) {
        $PD_score += $node -> get_length; 
    }
    
    my %included_nodes;
    @included_nodes{keys %$nodes_in_path} = (1) x scalar keys %$nodes_in_path;
    
    my ($PD_P, $PD_per_taxon, $PD_P_per_taxon);
    {
        no warnings 'uninitialized';
        $PD_P = $PD_score / $tree_ref -> get_total_tree_length;
    
        my $richness = $args{ABC};
        $PD_per_taxon = eval {$PD_score / $richness};
        $PD_P_per_taxon = eval {$PD_P / $richness};
    }
    
    my %results = (PD => $PD_score,
                   PD_P => $PD_P,
                   PD_per_taxon => $PD_per_taxon,
                   PD_P_per_taxon => $PD_P_per_taxon,
                   PD_INCLUDED_NODES => \%included_nodes
                   );

    return wantarray
            ? %results
            : \%results;
}


#  calculate corrected weighted endemism = PE / PD, equals endemism per unit branch length
sub calc_pe_cwe {
    my $self = shift;
    my %args = @_;
    
    if ($args{get_args}) {
        my %arguments = (description    => 'Calculate Phylogenetic corrected weighted endemism',
                         name           => 'PE Corrected Weighted Endemism',
                         indices        => { 
                                            PE_CWE => { RCOMP => ">",
                                                        description => 'Phylogenetic corrected weighted endemism.  '
                                                       . "Average range restriction per unit branch length\n"
                                                       . 'PE_CWE = PE_WE / PD',
                                        },
                                      },
                         type           => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
                         pre_calc       => [qw /calc_pe calc_pd/],
                         uses_nbr_lists     => 1,  #  how many lists it must have
                        );
        
        return wantarray ? %arguments : \%arguments;
    }
    
    #print join (" ", %args), "\n";
    #  don't tell me about divide by zero and unitialised values - they can happen
    no warnings qw /uninitialized numeric/;  
    my $PE_CWE = eval {$args{PE_WE} / $args{PD}};
    
    my %results = (PE_CWE => $PE_CWE);
    
    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_sorenson {
    
    my %arguments = (
        name           =>  'Phylo Sorenson',
        type           =>  'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        description    =>  "Sorenson phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches\n",
        pre_calc       =>  'calc_phylo_abc',
        uses_nbr_lists =>  2,  #  how many sets of lists it must have
        indices        => {
            PHYLO_SORENSON => {
                cluster     =>  1,
                formula     =>  '1 - (2A / (2A + B + C))',
                description => 'Phylo Sorenson score',
            }
        },
        required_args => {'tree_ref' => 1}
    );
           
    return wantarray ? %arguments : \%arguments;   
}

sub calc_phylo_sorenson {  # calculate the phylogenetic Sorenson dissimilarity index between two label lists.

    my $self = shift;
    my %args = @_;
    
    #i assume following lines are redundant
    #my $el1 = $self -> array_to_hash_keys (list => $args{element_list1});
    #my $el2 = $self -> array_to_hash_keys (list => $args{element_list2});
    
    my ($A, $B, $C, $ABC) = @args{qw /PHYLO_A PHYLO_B PHYLO_C PHYLO_ABC/};
    
    my $val;
    if ($A + $B and $A + $C) {  #  sum of each side must be non-zero
        $val = eval {1 - (2 * $A / ($A + $ABC))};
    }
    
    my %results = (PHYLO_SORENSON => $val);

    return wantarray
            ? %results
            : \%results;
}

sub get_metadata_calc_phylo_jaccard {
    
    my %arguments = (
        name           =>  'Phylo Jaccard',
        type           =>  'Phylogenetic Indices',
        description    =>  "Jaccard phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches\n",
        pre_calc       =>  'calc_phylo_abc',
        uses_nbr_lists =>  2,  #  how many sets of lists it must have
        indices        => {
            PHYLO_JACCARD => {
                cluster     =>  1,
                RCOMP       =>  ">",
                formula     =>  "= 1 - (A / (A + B + C))",
                description => 'Phylo Jaccard score',
            }
        },
        required_args => {'tree_ref' => 1}
    );
           
    return wantarray ? %arguments : \%arguments;   
}

sub calc_phylo_jaccard {  # calculate the phylogenetic Sorenson dissimilarity index between two label lists.
    my $self = shift;
    my %args = @_;

    my ($A, $B, $C, $ABC) = @args{qw /PHYLO_A PHYLO_B PHYLO_C PHYLO_ABC/};  
    
    my $val;
    if ($A + $B and $A + $C) {  #  sum of each side must be non-zero
        $val = eval {1 - ($A / $ABC)};
    }    

    my %results = (PHYLO_JACCARD => $val);

    return wantarray
            ? %results
            : \%results;
}

sub get_metadata_calc_phylo_abc {
    
    my %arguments = (
        name            =>  'Phylogenetic ABC',
        description     =>  'Calculate the shared and not shared branch lengths between two sets of labels',
        type            =>  'Phylogenetic Indices',
        pre_calc        =>  'calc_abc',
        pre_calc_global =>  'get_trimmed_tree',
        uses_nbr_lists  =>  2,  #  how many sets of lists it must have
        indices         => {
            PHYLO_A => {
                description     =>  'Length of branches shared by labels in nbr sets 1 and 2'},
            PHYLO_B => {
                description     =>  'Length of branches unique to labels in nbr set 1'},
            PHYLO_C => {
                description     =>  'Length of branches unique to labels in nbr set 2'},
            PHYLO_ABC => {
                description     =>  'Length of all branches associated with labels in nbr sets 1 and 2'},
        }
    );
           
    return wantarray ? %arguments : \%arguments;   
}

sub calc_phylo_abc {
    my $self = shift;
        my %args = @_;

    return $self -> _calc_phylo_abc(@_);
}

sub _calc_phylo_abc {
    my $self = shift;
    my %args = @_;

    #  assume we are in a spatial or tree object first, or a basedata object otherwise
    my $bd = $self -> get_param ('BASEDATA_REF') || $self;

    croak "none of refs element_list1, element_list2, label_list1, label_list2, label_hash1, label_hash2 specified\n"
        if (! defined $args{element_list1} && ! defined $args{element_list2} &&
            ! defined $args{label_list1} && ! defined $args{label_list2} &&
            ! defined $args{label_hash1} && ! defined $args{label_hash2} &&
            !defined $args{tree_ref});

    #  make copies of the label hashes so we don't mess things up with auto-vivification
    my %l1 = %{$args{label_hash1}};
    my %l2 = %{$args{label_hash2}};
    my %labels = (%l1, %l2);

    my ($phylo_A, $phylo_B, $phylo_C, $phylo_ABC)= (0, 0, 0, 0);    

    my $tree = $args{trimmed_tree};
    
    my $nodes_in_path1 = $self -> get_paths_to_root_node (
        @_,
        labels => \%l1,
        tree_ref => $tree
    );
    
    my $nodes_in_path2 = $self -> get_paths_to_root_node (
        @_,
        labels => \%l2,
        tree_ref => $tree
    );
    
    my %ABC = (%$nodes_in_path1, %$nodes_in_path2); 
    
    # get length of %ABC
    foreach my $node (values %ABC) {
        $phylo_ABC += $node ->get_length;
    };
        
    # create a new hash %B for nodes in label hash 1 but not 2
    my %B = %ABC;
    delete @B{keys %$nodes_in_path2};
    
    # get length of B = branches in label hash 1 but not 2
    foreach my $node (values %B) {
        $phylo_B += $node ->get_length;
    };
    
    # create a new hash %C for nodes in label hash 2 but not 1
    my %C = %ABC;
    delete @C{keys %$nodes_in_path1};
    
    # get length of C = branches in label hash 2 but not 1
    foreach my $node (values %C) {
        $phylo_C += $node ->get_length;
    };
    
    # get length A = shared branches
    $phylo_A = $phylo_ABC - ($phylo_B + $phylo_C);

    #  return the values but reduce the precision to avoid floating point problems later on
    my $precision = "%.10f";
    my %results = (
        PHYLO_A   => $self -> set_precision (
            precision => $precision,
            value     => $phylo_A
        ),
        PHYLO_B   => $self -> set_precision (
            precision => $precision,
            value     => $phylo_B,
        ),
        PHYLO_C   => $self -> set_precision (
            precision => $precision,
            value     => $phylo_C,
        ),
        PHYLO_ABC => $self -> set_precision (
            precision => $precision,
            value     => $phylo_ABC,
        ),
    );

    return wantarray
            ? %results
            : \%results;
}

sub get_metadata_calc_neo_endemism {
    
    my %arguments = (
        name            =>  'Neo Endemism',
        type            =>  'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        description     =>  "Neo endemism and related measures based on terminal branch lengths on a chronogram (dated or ultrametric phylogeny)",
        pre_calc        =>  [qw /calc_abc calc_abc2/],
        pre_calc_global =>  [qw /get_node_range_hash get_trimmed_tree get_pe_element_cache/],  # CHECK WHICH ARE NEEDED
        uses_nbr_lists =>  1,  #  how many sets of lists it must have
        indices => {
            NEO_END => {
                RCOMP       =>  ">",
                description =>  "Neo endemism  = 1 / (terminal branch length x taxon range) summed for taxa present",
                reference   =>  "Derived from Davis et al. (2008) Mol. Ecol.  http://dx.doi.org/10.1111/j.1365-294X.2007.03469.x"},
            NEO_END_L => {
                RCOMP       =>  ">",
                description =>  "Neo endemism, weighted by local range of each species",
                reference   =>  "Derived from Davis et al. (2008) Mol. Ecol.  http://dx.doi.org/10.1111/j.1365-294X.2007.03469.x"},
            NEO_END_P => {
                RCOMP       =>  ">",
                description =>  "Neo endemism calculated in relation to the total tree length"},
            NEO_TAXA => {
                RCOMP       =>  ">",
                description =>  "1 / terminal branch length summed for taxa present.  Leaves out the endemism component"},
            NEO_TAXA_L => {
                RCOMP       =>  ">",
                description => "1 / terminal branch length summed for taxa present, weighted by local range of each species.\n"
                . "Leaves out the endemism component"},
            MEAN_AGE =>  {
                RCOMP       =>  ">",
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
