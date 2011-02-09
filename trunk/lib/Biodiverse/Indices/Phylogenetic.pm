#  Phylogenetic indices
#  A plugin for the biodiverse system and not to be used on its own.

package Biodiverse::Indices::Phylogenetic;
use strict;
use warnings;

use Carp;
use Biodiverse::Progress;

our $VERSION = '0.16';


sub get_metadata_calc_pd {

    my %arguments = (
        description     => 'Phylogenetic diversity (PD) based on branch '
                           . "lengths back to the root of the tree.\n"
                           . 'Uses labels in both neighbourhoods.',
        name            => 'Phylogenetic Diversity',
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc        => '_calc_pd',
        uses_nbr_lists  => 1,  #  how many lists it must have
        #required_args   => {'tree_ref' => 1},
        indices         => {
            PD              => {
                cluster       => undef,
                description   => 'Phylogenetic diversity',
                reference     => 'Faith (1992) Biol. Cons. http://dx.doi.org/10.1016/0006-3207(92)91201-3',
                formula       => [
                    '= \sum_{c \in C} L_c',
                    ' where ',
                    'C',
                    'is the set of branches in the minimum spanning path '
                     . 'joining the labels in both neighbour sets to the root of the tree,',
                     'c',
                    ' is a branch (a single segment between two nodes) in the '
                    . 'spanning path ',
                    'C',
                    ', and ',
                    'L_c',
                    ' is the length of branch ',
                    'c',
                    '.',
                ],
            },
            PD_P            => {
                cluster       => undef,
                description   => 'Phylogenetic diversity as a proportion of total tree length',
                formula       => [
                    '= \frac { PD }{ \sum_{c \in C} L_c }',
                    ' where terms are the same as for PD, but ',
                    'c',
                    ', ',
                    'C',
                    ' and ',
                    'L_c',
                    ' are calculated for all nodes in the tree.',
                ],
            },
            PD_per_taxon    => {
                cluster       => undef,
                description   => 'Phylogenetic diversity per taxon',
                formula       => [
                    '= \frac { PD }{ RICHNESS\_ALL }',
                ],
            },
            PD_P_per_taxon  => {
                cluster       => undef,
                description   => 'Phylogenetic diversity per taxon as a proportion of total tree length',
                formula       => [
                    '= \frac { PD\_P }{ RICHNESS\_ALL }',
                ]
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_pd {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /PD PD_P PD_per_taxon PD_P_per_taxon/;
    my %results;
    @results{@keys} = @args{@keys};
    
    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pd_node_list {

    my %arguments = (
        description     => 'Phylogenetic diversity (PD) nodes used.',
        name            => 'Phylogenetic Diversity node list',
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc        => '_calc_pd',
        uses_nbr_lists  => 1,  #  how many lists it must have
        #required_args   => {'tree_ref' => 1},
        indices         => {
            PD_INCLUDED_NODE_LIST => {
                description   => 'List of tree nodes included in the PD calculations',
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_pd_node_list {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /PD_INCLUDED_NODE_LIST/;

    my %results;
    @results{@keys} = @args{@keys};

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_pd {
        my %arguments = (
        description     => 'Phylogenetic diversity (PD) base calcs.',
        name            => 'Phylogenetic Diversity base calcs',
        type            => 'Phylogenetic Indices',
        pre_calc        => 'calc_abc',
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => {'tree_ref' => 1},
    );

    return wantarray ? %arguments : \%arguments;
}

sub _calc_pd { #  calculate the phylogenetic diversity of the species in the central elements only
              #  this function expects a tree reference as an argument.
    my $self = shift;
    my %args = @_;

    my $tree_ref = $args{tree_ref};
    
    my $nodes_in_path = $self -> get_paths_to_root_node (
        @_,
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
    
    my %results = (
        PD                => $PD_score,
        PD_P              => $PD_P,
        PD_per_taxon      => $PD_per_taxon,
        PD_P_per_taxon    => $PD_P_per_taxon,
        
        PD_INCLUDED_NODE_LIST => \%included_nodes,
    );

    return wantarray
            ? %results
            : \%results;
}

#  get the paths to the root node of a tree for a set of labels
#  saves duplication of code in PD and PE subs
#  NEEDS TO BE MOVED INTO THE TREE PACKAGES?
sub get_paths_to_root_node {
    my $self = shift;
    my %args = @_;
    
    #  not currently designed as a precalc
    if ($args{get_args}) {
        my %arguments = (
            description    => 'Get the paths to the root node of a tree for a set of labels.',
            uses_nbr_lists => 1,  #  how many lists it must have
        );  #  add to if needed

        return wantarray ? %arguments : \%arguments;
    }
    
    my $label_list = $args{labels};
    my $tree_ref   = $args{tree_ref}
      or croak "argument tree_ref is not defined\n";
    
    #create a hash of terminal nodes for the taxa present
    my $all_nodes = $tree_ref -> get_node_hash;
    
    my $root_node = $tree_ref -> get_tree_ref;  # hmmm.  confusing mix of methods and vars
    #my $root_name = $root_node -> get_name;
    
    #  now loop through the labels and get the path to the root node
    my %path;
    foreach my $label (sort keys %$label_list) {
        next if not exists $all_nodes->{$label};
        
        my $current_node = $all_nodes->{$label};
        my $current_name = $current_node -> get_name;
        
        $path{$current_name} = $current_node;  #  include oneself
        
        my $sub_path = $current_node -> get_path_to_node (node => $root_node);
        @path{keys %$sub_path} = values %$sub_path;
    }
    
    return wantarray ? %path : \%path;
    
}


sub get_metadata_calc_pe {

    my %arguments = (
        description     => 'Phylogenetic endemism (PE).'
                            . 'Uses labels in both neighbourhoods and '
                            . 'trims the tree to exclude labels not in the '
                            . 'BaseData object.',
        name            => 'Phylogenetic Endemism',
        reference       => 'Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        #pre_calc_global => [qw /get_node_range_hash get_trimmed_tree get_pe_element_cache/],
        pre_calc        => ['_calc_pe'],  
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            PE_WE           => {
                description => 'Phylogenetic endemism'
            },
            PE_WE_P         => {
                description => 'Phylogenetic weighted endemism as a proportion of the total tree length'
            },
            PE_WE_SINGLE    => {
                description => "Phylogenetic endemism unweighted by the number of neighbours.\n"
                               . "Counts each label only once, regardless of how many groups in the neighbourhood it is found in.\n"
                               . 'Useful if your data have sampling biases. '
                               . 'Better with small sample windows.'
            },
            PE_WE_SINGLE_P  => {
                description => "Phylogenetic endemism unweighted by the number of neighbours as a proportion of the total tree length.\n"
                               . "Counts each label only once, regardless of how many groups in the neighbourhood it is found.\n"
                               . "Useful if your data have sampling biases."
            },
        },
    );
    
    return wantarray ? %arguments : \%arguments;
}

sub calc_pe {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /PE_WE PE_WE_P PE_WE_SINGLE PE_WE_SINGLE_P/;
    my %results;
    @results{@keys} = @args{@keys};
    
    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pe_lists {

    my %arguments = (
        description     => 'Lists used in the Phylogenetic endemism (PE) '
                            . 'calculations.',
        name            => 'Phylogenetic Endemism lists',
        reference       => 'Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Indices', 
        pre_calc        => ['_calc_pe'],  
        uses_nbr_lists  => 1,
        indices         => {
            PE_WTLIST       => {
                description => "Node weights used in PE calculations",
                type        => 'list',
            },
            PE_RANGELIST    => {
                description => "Node ranges used in PE calculations",
                type        => 'list',
            },
        },
    );
    
    return wantarray ? %arguments : \%arguments;
}

sub calc_pe_lists {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /PE_WTLIST PE_RANGELIST/;
    my %results;
    @results{@keys} = @args{@keys};
    
    return wantarray ? %results : \%results;
}

sub get_metadata__calc_pe {

    my %arguments = (
        description     => 'Phylogenetic endemism (PE) base calcs.',
        name            => 'Phylogenetic Endemism base calcs',
        reference       => 'Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc_global => [qw /get_node_range_hash get_trimmed_tree get_pe_element_cache/],
        pre_calc        => ['calc_abc'],  #  don't need calc_abc2 as we don't use its counts
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => {'tree_ref' => 1},
    );
    
    return wantarray ? %arguments : \%arguments;
}

sub _calc_pe { #  calculate the phylogenetic endemism of the species in the central elements only
              #  this function expects a tree reference as an argument.
              #  private method.  
    my $self = shift;
    my %args = @_;
    

    #my $label_list       = $args{label_hash1};
    my $tree_ref         = $args{trimmed_tree};
    my $node_ranges      = $args{node_range};
    my $results_cache    = $args{PE_RESULTS_CACHE};
    my $element_list_all = $args{element_list_all};
    
    my $bd = $args{basedata_ref} || $self->get_basedata_ref;

    #create a hash of terminal nodes for the taxa present
    my $all_nodes = $tree_ref -> get_node_hash;

    my $root_node = $tree_ref -> get_tree_ref;

    #  default these to undef - more meaningful than zero
    my ($PE_WE, $PE_WE_P, $PE_CWE, $PE_WE_SINGLE, $PE_WE_SINGLE_P);

    my %ranges;
    my %wts;
    my %unweighted_wts;  #  count once for each label, not weighted by group
    my %nodes_in_path;

    foreach my $group (@$element_list_all) {
        my $results;
        #  use the cached results for a group if present
        if (exists $results_cache->{$group}) {
            $results = $results_cache->{$group};
        }
        #  else build them and cache them
        else {
            my $labels = $bd -> get_labels_in_group_as_hash (group => $group);
            my $nodes_in_path = $self -> get_paths_to_root_node (
                @_,
                labels => $labels,
            );
     
            my ($gp_score, %gp_wts, %gp_ranges);
            
            #  loop over the nodes and run the calcs
            foreach my $node (values %$nodes_in_path) {
                my $name  = $node -> get_name;
                my $range = $node_ranges->{$name};
                my $wt    = eval {$node -> get_length / $range} || 0;
                $gp_score += $wt;
                $gp_wts{$name} = $wt;
                $gp_ranges{$name} = $range;
            }
            
            $results = {
                PE_WE           => $gp_score,
                wts             => \%gp_wts,
                ranges          => \%gp_ranges,
                nodes_in_path   => $nodes_in_path,
            };
            
            $results_cache->{$group} = $results;
        }
        
        $PE_WE += $$results{PE_WE} || 0;
        
        my $hash_ref;
        
        # ranges are invariant, so can be crashed together
        $hash_ref = $results->{ranges};
        @ranges{keys %$hash_ref} = values %$hash_ref;
        
        # nodes are also invariant
        $hash_ref = $results->{nodes_in_path};
        @nodes_in_path{keys %$hash_ref} =  values %$hash_ref;

        # unweighted weights are invariant
        $hash_ref = $results->{wts};
        @unweighted_wts{keys %$hash_ref} = values %$hash_ref;
        
        # weights need to be summed
        foreach my $node (keys %$hash_ref) {
            $wts{$node} += $hash_ref->{$node};
        }
    }

    {
        no warnings 'uninitialized';
        #Phylogenetic endemism = sum for all nodes of: (branch length/total tree length) / node range
        $PE_WE_P = eval {$PE_WE / $args{trimmed_tree} -> get_total_tree_length};
        
        #Phylogenetic corrected weighted endemism = (sum for all nodes of branch length / node range) / path length
        #where path length is actually PD
        my $path_length;
        foreach my $node (values %nodes_in_path) {  #  PE_CWE should be pulled out to its own sub, but need to fix the pre_calcs first
            $path_length += $node -> get_length;
        }

        foreach my $value (values %unweighted_wts) {
            $PE_WE_SINGLE += $value;
        }
        $PE_WE_SINGLE_P = eval {$PE_WE_SINGLE / $args{trimmed_tree} -> get_total_tree_length};
    }
    
    my %results = (
        PE_WE          => $PE_WE,
        PE_WE_SINGLE   => $PE_WE_SINGLE,
        PE_WE_SINGLE_P => $PE_WE_SINGLE_P,
        PE_WE_P        => $PE_WE_P,
        PE_WTLIST      => \%wts,
        PE_RANGELIST   => \%ranges,
    );

    return wantarray
        ? %results
        : \%results;
}


sub get_metadata_get_pe_element_cache {
    
    my %arguments = (
        description => 'Create a hash in which to cache the PE scores for each element',
        indices     => {
            PE_RESULTS_CACHE => {
                description => 'The hash in which to cache the PE scores for each element'
            },
        },
    );
    
    return wantarray ? %arguments : \%arguments;
}

#  create a hash in which to cache the PE scores for each element
#  this is called as a global precalc and then used or modified by each element as needed
sub get_pe_element_cache {
    my $self = shift;
    my %args = @_;

    my %results = (PE_RESULTS_CACHE => {});
    return wantarray ? %results : \%results;
}


sub get_metadata_get_node_range_hash {
    my %arguments = (pre_calc_global => ['get_trimmed_tree']);
    return wantarray ? %arguments : \%arguments;
}

sub get_node_range_hash { # calculate the range occupied by each node/clade in a tree
                          # this function expects a tree reference as an argument
    my $self = shift;
    my %args = @_;
    #my $progress_bar = $args{progress};
    my $progress_bar = Biodiverse::Progress->new();
    
    #if ($args{get_args}) {
    #  my %arguments = (pre_calc_global => ['get_trimmed_tree']);
    #  return wantarray ? %arguments : \%arguments;
    #}

    print "[PD INDICES] Calculating range for each node in the tree\n";
    
    my $tree = $args{trimmed_tree} || croak "Argument trimmed_tree missing\n";  
    my $nodes = $tree -> get_node_hash;
    #my $node;
    my %node_range;
  
    my $toDo = $tree ->get_node_count;
    my $count = 0; my $has_range_count = 0; my $printedProgress = -1;
    print "[PD INDICES] Progress (% of $toDo nodes): ";

        my $progress = int (100 * $count / $toDo);
        $progress_bar -> update(
            "Calculating node ranges for phylogenetic endemism analysis\n($progress)",
            $progress,
        );
        #if ($progress % 5 == 0) {
        #    if ($printedProgress != $progress) {
        #        print "$progress% ";
        #        print "\n" if $progress == 100;
        #        $printedProgress = $progress;
        #    }
        #}

    #my $range;

    foreach my $node_name (keys %{$nodes}) {
        my $node = $tree -> get_node_ref (node => $node_name);
        my $range = $self -> get_node_range (%args, tree_ref => $tree, node_ref => $node);
        if (defined $range) {
            $node_range{$node_name} = $range;
            $has_range_count +=1;
        }
      
        $count ++;
        my $progress = int (100 * $count / $toDo);
        if ($progress % 5 == 0) {
            if ($printedProgress != $progress) {
                print "$progress% ";
                print "\n" if $progress == 100;
                $printedProgress = $progress;
            }
        }
    }
    
    print "[PD INDICES] $has_range_count nodes have a range \n";
    
    my %results = (node_range => \%node_range);

    return wantarray ? %results : \%results;
}

#  Shawn's approach using tree's caching
sub get_node_range {
    my $self = shift;
    my %args = @_;
    
    my $tree     = $args{tree_ref} || croak "tree_ref arg not specified\n";
    my $node_ref = $args{node_ref} || croak "node_ref arg not specified\n";
    
    my $bd = $args{basedata_ref} || $self->get_basedata_ref;
    
    my @labels = ($node_ref -> get_name);
    my $children = $node_ref -> get_all_children;
    foreach my $name (keys %$children) {
        push (@labels, $name) if not $$children{$name} -> is_internal_node;
    }
    
    my @range = $bd -> get_range_union (labels => \@labels);
    
    return wantarray ? @range : scalar @range;
}


sub get_metadata_get_trimmed_tree {
    my %arguments = (required_args => 'tree_ref');
    return wantarray ? %arguments : \%arguments;
}

sub get_trimmed_tree { # create a copy of the current tree, including only those branches
                       # which have records in the base-data
                       # this function expects a tree reference as an argument
    my $self = shift;
    my %args = @_;                          

    print "[PD INDICES] Creating a trimmed tree by removing clades not present in the spatial data\n";

    my $bd = $self->get_basedata_ref;

    #  keep only those that match the basedata object
    my $trimmed_tree = $args{tree_ref} -> clone;
    $trimmed_tree -> trim (keep => scalar $bd -> get_labels);

    my %results = (trimmed_tree => $trimmed_tree);

    return wantarray
            ? %results
            : \%results;
}


sub get_metadata_calc_taxonomic_distinctness {
    my $self = shift;

    my $indices = {
        TD_DISTINCTNESS => {
            description    => 'Taxonomic distinctness',
            #formula        => [],
        },
        TD_DENOMINATOR  => {
            description    => 'Denominator from TD_DISTINCTNESS calcs',
        },
        TD_NUMERATOR    => {
            description    => 'Numerator from TD_DISTINCTNESS calcs',
        },
        TD_VARIATION    => {
            description    => 'Variation of the taxonomic distinctness',
            #formula        => [],
        },
    };
    
    my $ref = 'Warwick & Clarke (1995) Mar Ecol Progr Ser. '
            . 'http://dx.doi.org/10.3354/meps129301 ; '
            . 'Clarke & Warwick (2001) Mar Ecol Progr Ser. '
            . 'http://dx.doi.org/10.3354/meps216265';
    
    my %metadata = (
        description     => 'Taxonomic/phylogenetic distinctness and variation. '
                         . 'THIS IS A BETA LEVEL IMPLEMENTATION.',
        name            => 'Taxonomic/phylogenetic distinctness',
        type            => 'Phylogenetic Indices',
        reference       => $ref,
        pre_calc        => ['calc_abc3'],
        pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => $indices,
    );

    return wantarray
        ? %metadata
        : \%metadata;
}

#  sample count weighted version
sub calc_taxonomic_distinctness {
    my $self = shift;
    
    return $self->_calc_taxonomic_distinctness (@_);
}


sub get_metadata_calc_taxonomic_distinctness_binary {
    my $self = shift;

    my $indices = {
        TDB_DISTINCTNESS => {
            description    => 'Taxonomic distinctness, binary weighted',
            formula        => [
                '= \frac{\sum \sum_{i \neq j} \omega_{ij}}{s(s-1))}',
                'where ',
                '\omega_{ij}',
                'is the path length from label ',
                'i',
                'to the ancestor node shared with ',
                'j',
            ],
        },
        TDB_DENOMINATOR  => {
            description    => 'Denominator from TDB_DISTINCTNESS',
        },
        TDB_NUMERATOR    => {
            description    => 'Numerator from TDB_DISTINCTNESS',
        },
        TDB_VARIATION    => {
            description    => 'Variation of the binary taxonomic distinctness',
            formula        => [
                '= \frac{\sum \sum_{i \neq j} \omega_{ij}^2}{s(s-1))} - \bar{\omega}^2',
                'where ',
                '\bar{\omega} = \frac{\sum \sum_{i \neq j} \omega_{ij}}{s(s-1))} \equiv TDB\_DISTINCTNESS',
            ],
        },
    };

    my $ref = 'Warwick & Clarke (1995) Mar Ecol Progr Ser. '
            . 'http://dx.doi.org/10.3354/meps129301 ; '
            . 'Clarke & Warwick (2001) Mar Ecol Progr Ser. '
            . 'http://dx.doi.org/10.3354/meps216265';

    my %metadata = (
        description     => 'Taxonomic/phylogenetic distinctness and variation '
                         . 'using presence/absence weights.  '
                         . 'THIS IS A BETA LEVEL IMPLEMENTATION.',
        name            => 'Taxonomic/phylogenetic distinctness, binary weighted',
        type            => 'Phylogenetic Indices',
        reference       => $ref,
        pre_calc        => ['calc_abc'],
        pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => $indices,
    );

    return wantarray
        ? %metadata
        : \%metadata;
}

#  sample count weighted version
sub calc_taxonomic_distinctness_binary {
    my $self = shift;
    
    my %results = $self->_calc_taxonomic_distinctness (@_);
    my %results2;
    foreach my $key (keys %results) {
        my $key2 = $key;
        $key2 =~ s/^TD_/TDB_/;
        $results2{$key2} = $results{$key};
    }
    
    return wantarray ? %results2 : \%results2;
}

sub _calc_taxonomic_distinctness {
    my $self = shift;
    my %args = @_;

    my $label_hash = $args{label_hash_all};
    my $tree = $args{trimmed_tree};

    my $numerator;
    my $denominator = 0;
    my $sum_sqr_wts;
    my @labels = sort keys %$label_hash;
    
    #  Need to loop over each label and get the weighted contribution
    #  for each level of the tree.
    #  The weight for each comparison is the distance along the tree to
    #  the shared ancestor.

    #  We should use the distance from node a to b to avoid doubled comparisons
    #  and use get_path_to_node for the full path length.
    #  We can pop from @labels as we go to achieve this
    #  (this is the i<j constraint from Warwick & Clarke, but used in reverse)


    BY_LABEL:
    foreach my $label (@labels) {
        my $label_count = $label_hash->{$label};

        #  save some calcs (if ever this happens)
        next BY_LABEL if $label_count == 0;

        my $node = $tree -> get_node_ref (node => $label);

        LABEL2:
        foreach my $label2 (@labels) {

            #  skip same labels
            next LABEL2 if $label eq $label2;

            my $node2 = $tree->get_node_ref (node => $label2);

            my $ancestor = $node->get_shared_ancestor (node => $node2);

            my $path_length = $ancestor->get_total_length
                            - $node2->get_total_length;

            my $unweighted_value = $label_count * $label_hash->{$label2};

            my $wt = $path_length * $unweighted_value;

            $numerator   += $wt;
            $denominator += $unweighted_value;
            $sum_sqr_wts += $wt ** 2;
        }
    }

    my $distinctness;
    my $variance;

    {
        no warnings 'uninitialized';
        $distinctness  = eval {$numerator / $denominator};
        $variance = eval {$sum_sqr_wts / $denominator - $distinctness ** 2}
    }


    my %results = (
        TD_DISTINCTNESS => $distinctness,
        TD_DENOMINATOR  => $denominator,
        TD_NUMERATOR    => $numerator,
        TD_VARIATION    => $variance,
    );


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
        required_args   => {'tree_ref' => 1},
        indices         => {
            PHYLO_A => {
                description  =>  'Length of branches shared by labels in nbr sets 1 and 2',
                lumper       => 1,
            },
            PHYLO_B => {
                description  =>  'Length of branches unique to labels in nbr set 1',
                lumper       => 0,
            },
            PHYLO_C => {
                description  =>  'Length of branches unique to labels in nbr set 2',
                lumper       => 0,
            },
            PHYLO_ABC => {
                description  =>  'Length of all branches associated with labels in nbr sets 1 and 2',
                lumper       => 1,
            },
        },
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
    #my $bd = $self->get_basedata_ref;

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
        $phylo_ABC += $node->get_length;
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
            value     => $phylo_A,
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


1;


__END__

=head1 NAME

Biodiverse::Indices::Phylogenetic

=head1 SYNOPSIS

  use Biodiverse::Indices;

=head1 DESCRIPTION

Phylogenetic indices for the Biodiverse system.
It is inherited by Biodiverse::Indices and not to be used on it own.

See L<http://code.google.com/p/biodiverse/wiki/Indices> for more details.

=head1 METHODS

=over

=item INSERT METHODS

=back

=head1 REPORTING ERRORS

Use the issue tracker at http://www.purl.org/biodiverse

=head1 COPYRIGHT

Copyright (c) 2010 Shawn Laffan. All rights reserved.  

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut
