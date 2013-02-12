#  Phylogenetic indices
#  A plugin for the biodiverse system and not to be used on its own.

package Biodiverse::Indices::Phylogenetic;
use strict;
use warnings;
use English qw /-no_match_vars/;
use Carp;
use Biodiverse::Progress;

use List::Util qw /sum min/;
use Math::BigInt;

our $VERSION = '0.18003';

use Biodiverse::Statistics;
my $stats_package = 'Biodiverse::Statistics';

use Biodiverse::Matrix::LowMem;
my $mx_class_for_trees = 'Biodiverse::Matrix::LowMem';


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
                ],
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
                type          => 'list',
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

sub get_metadata_calc_pd_terminal_node_list {

    my %arguments = (
        description     => 'Phylogenetic diversity (PD) terminal nodes used.',
        name            => 'Phylogenetic Diversity terminal node list',
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc        => '_calc_pd',
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => {'tree_ref' => 1},
        indices         => {
            PD_INCLUDED_TERMINAL_NODE_LIST => {
                description   => 'List of tree terminal nodes included in the PD calculations',
                type          => 'list',
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_pd_terminal_node_list {
    my $self = shift;
    my %args = @_;

    my $tree_ref = $args{tree_ref};

    #  loop over nodes and just keep terminals
    my $pd_included_node_list = $args{PD_INCLUDED_NODE_LIST};
    my @keys = keys %$pd_included_node_list;
    my %node_hash = %{$tree_ref->get_node_hash};

    my %terminals;
    foreach my $node_name (@keys) {
        next if ! $tree_ref->get_node_ref(node => $node_name)->is_terminal_node;
        $terminals{$node_name} = $pd_included_node_list->{$node_name};
    }

    my %results = (
        PD_INCLUDED_TERMINAL_NODE_LIST => \%terminals,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_pd {
        my %arguments = (
        description     => 'Phylogenetic diversity (PD) base calcs.',
        name            => 'Phylogenetic Diversity base calcs',
        type            => 'Phylogenetic Indices',
        pre_calc        => 'calc_labels_on_tree',
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
    my $label_list = $args{PHYLO_LABELS_ON_TREE};
    my $richness = scalar keys %$label_list;

    my $nodes_in_path = $self->get_path_lengths_to_root_node (
        @_,
        labels => $label_list,
    );

    my $PD_score = sum values %$nodes_in_path;

    #  need to use node length instead of 1
    #my %included_nodes;
    #@included_nodes{keys %$nodes_in_path} = (1) x scalar keys %$nodes_in_path;
    my %included_nodes = %$nodes_in_path;

    my ($PD_P, $PD_per_taxon, $PD_P_per_taxon);
    {
        no warnings 'uninitialized';
        if ($PD_score) {  # only if we have some PD
            $PD_P = $PD_score / $tree_ref->get_total_tree_length;
        }

        $PD_per_taxon   = eval {$PD_score / $richness};
        $PD_P_per_taxon = eval {$PD_P / $richness};
    }
    
    my %results = (
        PD                => $PD_score,
        PD_P              => $PD_P,
        PD_per_taxon      => $PD_per_taxon,
        PD_P_per_taxon    => $PD_P_per_taxon,

        PD_INCLUDED_NODE_LIST => \%included_nodes,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_path_length_cache {
    my $self = shift;

    my %metadata = (
        description     => 'Cache for path lengths.',
        uses_nbr_lists  => 1,  #  how many lists it must have
    );

    return wantarray ? %metadata : \%metadata;
}

sub get_path_length_cache {
    my $self = shift;
    my %args = @_;

    my %results = (path_length_cache => {});

    return wantarray ? %results : \%results;
}

sub get_metadata_get_path_lengths_to_root_node {

    my %arguments = (
        description     => 'Get the path lengths to the root node of a tree for a set of labels.',
        uses_nbr_lists  => 1,  #  how many lists it must have
        pre_calc_global => 'get_path_length_cache',
    );

    return wantarray ? %arguments : \%arguments;
}

#  get the paths to the root node of a tree for a set of labels
#  saves duplication of code in PD and PE subs
sub get_path_lengths_to_root_node {
    my $self = shift;
    my %args = (return_lengths => 1, @_);

    my $cache = !$args{no_cache};
    #$cache = 0;  #  turn it off for debug
    
    #  have we cached it?
    my $use_path_cache = $cache && $self->get_param('BUILDING_MATRIX');
    if ($use_path_cache) {
        my $cache   = $args{path_length_cache};
        my @el_list = keys %{$args{el_list}};
        if (scalar @el_list == 1) {  #  caching makes sense only if we have only one element
            my $path = $cache->{$el_list[0]};
            return (wantarray ? %$path : $path) if ($path);
        }
        else {
            $use_path_cache = undef;  #  skip caching below
        }
    }

    my $label_list = $args{labels};
    my $tree_ref   = $args{tree_ref}
      or croak "argument tree_ref is not defined\n";

    #my $return_lengths = $args{return_lengths};

    #create a hash of terminal nodes for the taxa present
    my $all_nodes = $tree_ref->get_node_hash;
    
    #  now loop through the labels and get the path to the root node
    my %path;
    foreach my $label (sort keys %$label_list) {
        next if not exists $all_nodes->{$label};

        my $current_node = $all_nodes->{$label};

        my $sub_path = $current_node->get_path_lengths_to_root_node (cache => $cache);
        @path{keys %$sub_path} = values %$sub_path;
    }

    if ($use_path_cache) {
        my $cache_h = $args{path_length_cache};
        my @el_list = keys %{$args{el_list}};
        $cache_h->{$el_list[0]} = \%path;
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
        description     => 'Lists used in the Phylogenetic endemism (PE) calculations.',
        name            => 'Phylogenetic Endemism lists',
        reference       => 'Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Indices', 
        pre_calc        => ['_calc_pe'],  
        uses_nbr_lists  => 1,
        indices         => {
            PE_WTLIST       => {
                description => 'Node weights used in PE calculations',
                type        => 'list',
            },
            PE_RANGELIST    => {
                description => 'Node ranges used in PE calculations',
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

sub get_metadata_calc_pd_endemism {

    my %arguments = (
        description     => 'Absolute endemism analogue of PE.  '
                        .  'It is the sum of the branch lengths restricted '
                        .  'to the neighbour sets.',
        name            => 'PD-Endemism',
        reference       => 'See Faith (2004) Cons Biol.  http://dx.doi.org/10.1111/j.1523-1739.2004.00330.x',
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc        => ['calc_pe_lists'],
        pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            PD_ENDEMISM => {
                description => 'Phylogenetic Diversity Endemism',
            },
            PD_ENDEMISM_WTS => {
                description => 'Phylogenetic Diversity Endemism weights per node found only in the neighbour set',
            }
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_pd_endemism {
    my $self = shift;
    my %args = @_;
    
    my $weights = $args{PE_WTLIST};
    my $tree_ref = $args{trimmed_tree};
    
    my $pd_e;
    my %pd_e_wts;

    foreach my $label (keys %$weights) {
        my $wt = $weights->{$label};
        my $tree_node = $tree_ref->get_node_ref(node => $label);
        my $length = $tree_node->get_length;
        next if $wt != $length || $wt == 0;

        $pd_e += $wt;
        $pd_e_wts{$label} = $wt;
    }

    my %results = (
        PD_ENDEMISM     => $pd_e,
        PD_ENDEMISM_WTS => \%pd_e_wts,
    );
    
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
    my $all_nodes = $tree_ref->get_node_hash;

    my $root_node = $tree_ref->get_tree_ref;

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
            my $labels = $bd->get_labels_in_group_as_hash (group => $group);
            my $nodes_in_path = $self->get_path_lengths_to_root_node (
                @_,
                labels => $labels,
            );
     
            my ($gp_score, %gp_wts, %gp_ranges);
            
            #  loop over the nodes and run the calcs
            while (my ($name, $length) = each %$nodes_in_path) {
                my $range = $node_ranges->{$name};
                my $wt    = eval {$length / $range} || 0;
                $gp_score += $wt;
                $gp_wts{$name}    = $wt;
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

        if (defined $results->{PE_WE}) {
            $PE_WE += $results->{PE_WE};
        }

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
        my $total_tree_length = $tree_ref->get_total_tree_length;

        #Phylogenetic endemism = sum for all nodes of: (branch length/total tree length) / node range
        $PE_WE_P = eval {$PE_WE / $total_tree_length};

        #Phylogenetic corrected weighted endemism = (sum for all nodes of branch length / node range) / path length
        #where path length is actually PD
        #my $path_length;
        #foreach my $length (values %nodes_in_path) {  #  PE_CWE should be pulled out to its own sub, but need to fix the pre_calcs first
        #    $path_length += $length;
        #}

        #  NEED TO PULL THESE OUT TO THEIR OWN SUB - they are not needed for
        #  many of the calcs that depend on this sub and slow things down
        #  for large data sets with large trees
        $PE_WE_SINGLE = sum (values %unweighted_wts);
        $PE_WE_SINGLE_P = eval {$PE_WE_SINGLE / $total_tree_length};
    }

    my %results = (
        PE_WE          => $PE_WE,
        PE_WE_SINGLE   => $PE_WE_SINGLE,
        PE_WE_SINGLE_P => $PE_WE_SINGLE_P,
        PE_WE_P        => $PE_WE_P,
        PE_WTLIST      => \%wts,
        PE_RANGELIST   => \%ranges,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_labels_on_tree {
    my $self = shift;

    my %arguments = (
        description     => 'Create a hash of the labels that are on the tree',
        name            => 'Labels on tree',
        indices         => {
            PHYLO_LABELS_ON_TREE => {
                description => 'A hash of labels that are found on the tree, across both neighbour sets',
            },  #  should poss also do nbr sets 1 and 2
        },
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc_global => [qw /get_labels_not_on_tree/],
        pre_calc        => ['calc_abc'],
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => ['tree_ref'],
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_labels_on_tree {
    my $self = shift;
    my %args = @_;
    
    my %labels = %{$args{label_hash_all}};
    my $not_on_tree = $args{labels_not_on_tree};
    delete @labels{keys %$not_on_tree};
    
    my %results = (PHYLO_LABELS_ON_TREE => \%labels);
    
    return wantarray ? %results : \%results;
}

sub get_metadata_calc_labels_not_on_tree {
    my $self = shift;

    my %arguments = (
        description     => 'Create a hash of the labels that are not on the tree',
        name            => 'Labels not on tree',
        indices         => {
            PHYLO_LABELS_NOT_ON_TREE => {
                description => 'A hash of labels that are not found on the tree, across both neighbour sets',
                type        => 'list',
            },  #  should poss also do nbr sets 1 and 2
            PHYLO_LABELS_NOT_ON_TREE_N => {
                description => 'Number of labels not on the tree',
                
            },
            PHYLO_LABELS_NOT_ON_TREE_P => {
                description => 'Proportion of labels not on the tree',
                
            },
        },
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc_global => [qw /get_labels_not_on_tree/],
        pre_calc        => ['calc_abc'],
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => ['tree_ref'],
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_labels_not_on_tree {
    my $self = shift;
    my %args = @_;

    my $not_on_tree = $args{labels_not_on_tree};

    my %labels1 = %{$args{label_hash_all}};
    my $richness = scalar keys %labels1;
    delete @labels1{keys %$not_on_tree};

    my %labels2 = %{$args{label_hash_all}};
    delete @labels2{keys %labels1};

    my $count_not_on_tree = scalar keys %labels2;
    my $p_not_on_tree;
    {
        no warnings 'numeric';
        my $richness   = scalar keys %{$args{label_hash_all}};
        $p_not_on_tree = eval { $count_not_on_tree / $richness } || 0;
    }

    my %results = (
        PHYLO_LABELS_NOT_ON_TREE   => \%labels2,
        PHYLO_LABELS_NOT_ON_TREE_N => $count_not_on_tree,
        PHYLO_LABELS_NOT_ON_TREE_P => $p_not_on_tree,
    );

    return wantarray ? %results : \%results;
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


#  get the node ranges as lists
sub get_metadata_get_node_range_hash_as_lists {
    my %arguments = (pre_calc_global => ['get_trimmed_tree']);
    return wantarray ? %arguments : \%arguments;
}

sub get_node_range_hash_as_lists {
    my $self = shift;
    my %args = @_;

    my $res = $self->get_node_range_hash (@_, return_lists => 1);
    my %results = (
        node_range_hash => $res->{node_range},
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_node_range_hash {
    my %arguments = (pre_calc_global => ['get_trimmed_tree']);
    return wantarray ? %arguments : \%arguments;
}

#  needs a cleanup - see get_global_node_abundance_hash
sub get_node_range_hash { # calculate the range occupied by each node/clade in a tree
                          # this function expects a tree reference as an argument
    my $self = shift;
    my %args = @_;

    my $return_lists = $args{return_lists};

    my $progress_bar = Biodiverse::Progress->new();    

    print "[PD INDICES] Calculating range for each node in the tree\n";
    
    my $tree  = $args{trimmed_tree} || croak "Argument trimmed_tree missing\n";  
    my $nodes = $tree->get_node_hash;
    my %node_range;
  
    my $toDo = scalar keys %$nodes;
    my $count = 0;
    print "[PD INDICES] Progress (% of $toDo nodes): ";

    my $progress = int (100 * $count / $toDo);
    $progress_bar->update(
        "Calculating node ranges\n($progress)",
        $progress,
    );

    foreach my $node_name (keys %{$nodes}) {
        my $node  = $tree->get_node_ref (node => $node_name);
        if ($return_lists) {
            my @range = $self->get_node_range (
                %args,
                node_ref => $node,
            );
            my %range_hash;
            @range_hash{@range} = undef;
            $node_range{$node_name} = \%range_hash;
        }
        else {
            my $range = $self->get_node_range (
                %args,
                node_ref => $node,
            );
            if (defined $range) {
                $node_range{$node_name} = $range;
            }
        }
        $count ++;
        my $progress = $count / $toDo;
        $progress_bar->update(
            "Calculating node ranges\n($progress)",
            $progress,
        );
    }

    my %results = (node_range => \%node_range);

    return wantarray ? %results : \%results;
}

#  Shawn's approach using tree's caching
sub get_node_range {
    my $self = shift;
    my %args = @_;

    my $node_ref = $args{node_ref} || croak "node_ref arg not specified\n";

    my $bd = $args{basedata_ref} || $self->get_basedata_ref;

    my @labels   = ($node_ref->get_name);
    my $children =  $node_ref->get_all_descendents;

    #  collect the set of non-internal (named) nodes
    #  Possibly should only work with terminals
    #  which would simplify things.
    foreach my $name (keys %$children) {
        next if $children->{$name}->is_internal_node;
        push (@labels, $name);
    }

    my @range = $bd->get_range_union (labels => \@labels);

    return wantarray ? @range : scalar @range;
}


sub get_metadata_get_global_node_abundance_hash {
    my %arguments = (pre_calc_global => ['get_trimmed_tree']);
    return wantarray ? %arguments : \%arguments;
}


sub get_global_node_abundance_hash {
    my $self = shift;
    my %args = @_;

    my $progress_bar = Biodiverse::Progress->new();    

    print "[PD INDICES] Calculating abundance for each node in the tree\n";
    
    my $tree  = $args{trimmed_tree} || croak "Argument trimmed_tree missing\n";  
    my $nodes = $tree->get_node_hash;
    my %node_hash;

    my $toDo = scalar keys %$nodes;
    my $count = 0;

    my $progress = int (100 * $count / $toDo);
    $progress_bar->update(
        "Calculating node abundances\n($progress)",
        $progress,
    );

    foreach my $node_name (keys %$nodes) {
        my $node  = $tree->get_node_ref (node => $node_name);
        my $abundance = $self->get_node_abundance_global (
            %args,
            node_ref => $node,
        );
        if (defined $abundance) {
            $node_hash{$node_name} = $abundance;
        }

        $count ++;
        my $progress = $count / $toDo;
        $progress_bar->update(
            "Calculating node abundances\n($progress)",
            $progress,
        );
    }

    my %results = (node_abundance_hash => \%node_hash);

    return wantarray ? %results : \%results;
}

sub get_node_abundance_global {
    my $self = shift;
    my %args = @_;

    my $node_ref = $args{node_ref} || croak "node_ref arg not specified\n";

    my $bd = $args{basedata_ref} || $self->get_basedata_ref;
    
    my $abundance = $bd->get_label_sample_count (element => $node_ref->get_name);

    my $children =  $node_ref->get_all_descendents;
    foreach my $name (keys %$children) {  #  find all non-internal (named) nodes
        next if $children->{$name}->is_internal_node;
        $abundance += $bd->get_label_sample_count (element => $name);
    }

    return $abundance;
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
    my $trimmed_tree = $args{tree_ref}->clone;
    $trimmed_tree->trim (keep => scalar $bd->get_labels);
    my $name = $trimmed_tree->get_param('NAME');
    if (!defined $name) {$name = 'noname'};
    $trimmed_tree->rename(new_name => $name . ' trimmed');

    my %results = (trimmed_tree => $trimmed_tree);

    return wantarray ? %results : \%results;
}

sub get_metadata_get_labels_not_on_tree {
    my $self = shift;

    my %arguments = (required_args => 'tree_ref');

    return wantarray ? %arguments : \%arguments;
}

sub get_labels_not_on_tree {
    my $self = shift;
    my %args = @_;                          

    my $bd   = $self->get_basedata_ref;
    my $tree = $args{tree_ref};
    
    my $labels = $bd->get_labels;
    
    my @not_in_tree = grep { !$tree->exists_node (name => $_) } @$labels;

    my %hash;
    @hash{@not_in_tree} = (1) x scalar @not_in_tree;

    my %results = (labels_not_on_tree => \%hash);

    return wantarray ? %results : \%results;
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

    return wantarray ? %metadata : \%metadata;
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

    return wantarray ? %metadata : \%metadata;
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
    my $ssq_wtd_value;
    my @labels = sort keys %$label_hash;
    
    #  Need to loop over each label and get the weighted contribution
    #  for each level of the tree.
    #  The weight for each comparison is the distance along the tree to
    #  the shared ancestor.

    #  We should use the distance from node a to b to avoid doubled comparisons
    #  and use get_path_to_node for the full path length.
    #  We can pop from @labels as we go to achieve this
    #  (this is the i<j constraint from Warwick & Clarke, but used in reverse)
    
    #  Actually, it's simpler to loop over the list twice and get the lengths to shared ancestor


    BY_LABEL:
    foreach my $label (@labels) {
        my $label_count1 = $label_hash->{$label};

        #  save some calcs (if ever this happens)
        next BY_LABEL if $label_count1 == 0;

        my $node = $tree->get_node_ref (node => $label);

        LABEL2:
        foreach my $label2 (@labels) {

            #  skip same labels
            next LABEL2 if $label eq $label2;

            my $label_count2 = $label_hash->{$label2};
            next LABEL2 if $label_count2 == 0;

            my $node2 = $tree->get_node_ref (node => $label2);

            my $ancestor = $node->get_shared_ancestor (node => $node2);

            my $path_length = $ancestor->get_total_length
                            - $node2->get_total_length;

            my $weight = $label_count1 * $label_count2;

            my $wtd_value = $path_length * $weight;

            $numerator     += $wtd_value;
            $ssq_wtd_value += $wtd_value ** 2;
            $denominator   += $weight;
        }
    }

    my $distinctness;
    my $variance;

    {
        no warnings 'uninitialized';
        $distinctness  = eval {$numerator / $denominator};
        $variance = eval {$ssq_wtd_value / $denominator - $distinctness ** 2}
    }

    my %results = (
        TD_DISTINCTNESS => $distinctness,
        TD_DENOMINATOR  => $denominator,
        TD_NUMERATOR    => $numerator,
        TD_VARIATION    => $variance,
    );


    return wantarray ? %results : \%results;
}

my $webb_et_al_ref = 'Webb et al. (2008) http://dx.doi.org/10.1093/bioinformatics/btn358';

sub get_mpd_mntd_metadata {
    my $self = shift;
    my %args = @_;

    my $abc_sub = $args{abc_sub} || 'calc_abc';

    my $num = 1;
    if ($abc_sub =~ /(\d)$/) {
        $num = $1;
    }

    my $indices = {
        PNTD_MEAN => {
            description    => 'Mean of nearest taxon distances',
        },
        PNTD_MAX => {
            description    => 'Maximum of nearest taxon distances',
        },
        PNTD_MIN => {
            description    => 'Minimum of nearest taxon distances',
        },
        PNTD_SD => {
            description    => 'Standard deviation of nearest taxon distances',
        },
        PNTD_N => {
            description    => 'Count of nearest taxon distances',
        },
        PMPD_MEAN => {
            description    => 'Mean of pairwise phylogenetic distances',
        },
        PMPD_MAX => {
            description    => 'Maximum of pairwise phylogenetic distances',
        },
        PMPD_MIN => {
            description    => 'Minimum of pairwise phylogenetic distances',
        },
        PMPD_SD => {
            description    => 'Standard deviation of pairwise phylogenetic distances',
        },
        PMPD_N => {
            description    => 'Count of pairwise phylogenetic distances',
        },
    };

    my $pre_calc = [$abc_sub, 'calc_labels_on_tree'];
    
    my $indices_filtered = {};
    my $pfx_re = qr /(PNTD|PMPD)/;
    foreach my $key (keys %$indices) {
        next if not $key =~ /$pfx_re/;  #  next prob redundant, but need $1 from re
        my $pfx = $1;
        my $new_key = $key;
        $new_key =~ s/$pfx/$pfx$num/;
        $indices_filtered->{$new_key} = $indices->{$key};
    }

    my %metadata = (
        type            => 'PhyloCom Indices',
        reference       => $webb_et_al_ref,
        pre_calc        => $pre_calc,
        pre_calc_global => [qw /get_phylo_mpd_mntd_matrix/],
        required_args   => 'tree_ref',
        uses_nbr_lists  => 1,
        indices         => $indices_filtered,
    );

    return wantarray ? %metadata : \%metadata;    
}


sub get_metadata_calc_phylo_mpd_mntd1 {
    my $self = shift;
    my %args = @_;

    my %submeta = $self->get_mpd_mntd_metadata (
        abc_sub => 'calc_abc',
    );

    my %metadata = (
        description     => 'Distance stats from each label to the nearest label '
                         . 'along the tree.  Compares with '
                         . 'all other labels across both neighbour sets. ',
        name            => 'Phylogenetic and Nearest taxon distances, unweighted',
        %submeta,
    );

    return wantarray ? %metadata : \%metadata;
}

sub calc_phylo_mpd_mntd1 {
    my $self = shift;
    my %args = @_;

    my %results = $self->_calc_phylo_mpd_mntd (
        %args,
        label_hash1 => $args{label_hash_all},
        label_hash2 => $args{label_hash_all},
        abc_num     => 1,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_mpd_mntd2 {
    my $self = shift;
    my %args = @_;

    my %submeta = $self->get_mpd_mntd_metadata (
        abc_sub => 'calc_abc2',
    );

    my %metadata = (
        description     => 'Distance stats from each label to the nearest label '
                         . 'along the tree.  Compares with '
                         . 'all other labels across both neighbour sets. '
                         . 'Weighted by sample counts',
        name            => 'Phylogenetic and Nearest taxon distances, local range weighted',
        %submeta,
    );

    return wantarray ? %metadata : \%metadata;
}

sub calc_phylo_mpd_mntd2 {
    my $self = shift;
    my %args = @_;

    my %results = $self->_calc_phylo_mpd_mntd (
        %args,
        label_hash1 => $args{label_hash_all},
        label_hash2 => $args{label_hash_all},
        abc_num     => 2,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_mpd_mntd3 {
    my $self = shift;
    my %args = @_;

    my %submeta = $self->get_mpd_mntd_metadata (
        abc_sub => 'calc_abc3',
    );

    my %metadata = (
        description     => 'Distance stats from each label to the nearest label '
                         . 'along the tree.  Compares with '
                         . 'all other labels across both neighbour sets. '
                         . 'Weighted by sample counts',
        name            => 'Phylogenetic and Nearest taxon distances, abundance weighted',
        %submeta,
    );

    return wantarray ? %metadata : \%metadata;
}

sub calc_phylo_mpd_mntd3 {
    my $self = shift;
    my %args = @_;

    my %results = $self->_calc_phylo_mpd_mntd (
        %args,
        label_hash1 => $args{label_hash_all},
        label_hash2 => $args{label_hash_all},
        abc_num     => 3,
    );

    return wantarray ? %results : \%results;
}

#  mean nearest taxon distance and mean phylogenetic distance
sub _calc_phylo_mpd_mntd {
    my $self = shift;
    my %args = @_;

    my $label_hash1 = $args{label_hash1};
    my $label_hash2 = $args{label_hash2};
    my $mx         = $args{PHYLO_MPD_MNTD_MATRIX}
      || croak "Argument PHYLO_MPD_MNTD_MATRIX not defined\n";
    my $labels_on_tree = $args{PHYLO_LABELS_ON_TREE};
    my $tree_ref   = $args{tree_ref};
    #my $do_mpd    = $args{do_mpd};  #  are we doing MPD or MNTD?
    my $abc_num = $args{abc_num} || 1;

    my @labels1 = sort grep { exists $labels_on_tree->{$_} } keys %$label_hash1;
    my @labels2 = sort grep { exists $labels_on_tree->{$_} } keys %$label_hash2;

    my (@mpd_path_lengths, @mntd_path_lengths);

    #  Loop over all possible pairs, 
    BY_LABEL:
    foreach my $label1 (@labels1) {
        my $label_count1 = $label_hash1->{$label1};
        
        #  save some calcs (if ever this happens)
        next BY_LABEL if $label_count1 == 0;

        #my $min;
        my @mpd_path_lengths_this_node;
        my @mntd_path_lengths_this_node;
        my $i = 0;

        LABEL2:
        foreach my $label2 (@labels2) {

            #  skip same labels
            next LABEL2 if $label1 eq $label2;

            my $label_count2 = $label_hash2->{$label2};
            next LABEL2 if $label_count2 == 0;

            my $path_length = $mx->get_value(
                element1 => $label1,
                element2 => $label2,
            );
            if (!defined $path_length) {  #  need to calculate it
                my $last_ancestor = $tree_ref->get_last_shared_ancestor_for_nodes (
                    node_names => {$label1 => 1, $label2 => 1},
                );

                my %path;
                foreach my $node_name ($label1, $label2) {
                    my $node_ref = $tree_ref->get_node_ref (node => $node_name);
                    my $sub_path = $node_ref->get_path_lengths_to_ancestral_node (
                        ancestral_node => $last_ancestor,
                        %args,
                    );
                    @path{keys %$sub_path} = values %$sub_path;
                }
                delete $path{$last_ancestor->get_name()};
                $path_length = sum values %path;
                $mx->set_value(
                    element1 => $label1,
                    element2 => $label2,
                    value    => $path_length,
                );
            }
            #if ($do_mpd) {  #  mpd case needs to weight by labelcount2
                push @mpd_path_lengths_this_node, ($path_length) x $label_count2;
            #}
            #else {          #  mntd case takes the min, so don't bother weighting?
                push @mntd_path_lengths_this_node, $path_length;  
            #}

            $i ++;
        }
        if ($i) {  #  only if we added something
            #if ($do_mpd) {
                push @mpd_path_lengths, (@mpd_path_lengths_this_node) x $label_count1;
            #}
            #else {
                my $min = min (@mntd_path_lengths_this_node);
                push @mntd_path_lengths, ($min) x $label_count1;
            #}
        }
    }

    my %results;

    my @paths = (\@mntd_path_lengths, \@mpd_path_lengths);
    my @pfxs  = qw /PNTD PMPD/;
    my $i = 0;
    foreach my $path (@paths) {
        #  allows us to generalise later on
        my $stats = $stats_package->new();
        $stats->add_data($path);
        my $n = $stats->count;
        my $pfx = $pfxs[$i] . $abc_num;

        $results{$pfx . '_N'}    = $n;
        $results{$pfx . '_MEAN'} = $stats->mean;
        $results{$pfx . '_MIN'}  = $stats->min;
        $results{$pfx . '_MAX'}  = $stats->max;
        $results{$pfx . '_SD'}   = $stats->standard_deviation;
    
        $i++;
    }

    return wantarray ? %results : \%results;
}

sub get_metadata_get_phylo_mpd_mntd_matrix {
    my $self = shift;

    my %metadata = (
        #required_args => 'tree_ref',
        #pre_calc_global => ['get_trimmed_tree'],  #  need to work with whole tree, so comment out
    );

    return wantarray ? %metadata : \%metadata;
}


sub get_phylo_mpd_mntd_matrix {
    my $self = shift;

    my $mx = Biodiverse::Matrix::LowMem->new (NAME => 'mntd_matrix');
    
    my %results = (PHYLO_MPD_MNTD_MATRIX => $mx);
    
    return wantarray ? %results : \%results;
}

sub get_metadata_get_trimmed_tree_as_matrix {
    my $self = shift;

    my %metadata = (
        pre_calc_global => ['get_trimmed_tree'],
    );

    return wantarray ? %metadata : \%metadata;
}

sub get_trimmed_tree_as_matrix {
    my $self = shift;
    my %args = @_;

    my $mx = $args{trimmed_tree}->to_matrix (class => $mx_class_for_trees);

    my %results = (TRIMMED_TREE_AS_MATRIX => $mx);

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
                cluster     =>  'NO_CACHE_ABC',
                formula     =>  [
                    '1 - (2A / (2A + B + C))',
                    ' where A is the length of shared branches, '
                    . 'and B and C are the length of branches found only in neighbour sets 1 and 2'
                ],
                description => 'Phylo Sorenson score',
            }
        },
        required_args => {'tree_ref' => 1}
    );

    return wantarray ? %arguments : \%arguments;   
}

# calculate the phylogenetic Sorenson dissimilarity index between two label lists.
sub calc_phylo_sorenson {

    my $self = shift;
    my %args = @_;

    my ($A, $B, $C, $ABC) = @args{qw /PHYLO_A PHYLO_B PHYLO_C PHYLO_ABC/};

    my $val;
    if ($A + $B and $A + $C) {  #  sum of each side must be non-zero
        $val = eval {1 - (2 * $A / ($A + $ABC))};
    }

    my %results = (PHYLO_SORENSON => $val);

    return wantarray ? %results : \%results;
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
                cluster     =>  'NO_CACHE_ABC',
                formula     =>  [
                    '= 1 - (A / (A + B + C))',
                    ' where A is the length of shared branches, '
                    . 'and B and C are the length of branches found only in neighbour sets 1 and 2',
                ],
                description => 'Phylo Jaccard score',
            }
        },
        required_args => {'tree_ref' => 1}
    );

    return wantarray ? %arguments : \%arguments;   
}

# calculate the phylogenetic Sorenson dissimilarity index between two label lists.
sub calc_phylo_jaccard {
    my $self = shift;
    my %args = @_;

    my ($A, $B, $C, $ABC) = @args{qw /PHYLO_A PHYLO_B PHYLO_C PHYLO_ABC/};  

    my $val;
    if ($A + $B and $A + $C) {  #  sum of each side must be non-zero
        $val = eval {1 - ($A / $ABC)};
    }    

    my %results = (PHYLO_JACCARD => $val);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_s2 {

    my %arguments = (
        name           =>  'Phylo S2',
        type           =>  'Phylogenetic Indices',
        description    =>  "S2 phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches\n",
        pre_calc       =>  'calc_phylo_abc',
        uses_nbr_lists =>  2,  #  how many sets of lists it must have
        indices        => {
            PHYLO_S2 => {
                cluster     =>  'NO_CACHE_ABC',
                formula     =>  [
                    '= 1 - (A / (A + min (B, C)))',
                    ' where A is the length of shared branches, '
                    . 'and B and C are the length of branches found only in neighbour sets 1 and 2',
                ],
                description => 'Phylo S2 score',
            }
        },
        required_args => {'tree_ref' => 1}
    );

    return wantarray ? %arguments : \%arguments;   
}

# calculate the phylogenetic Sorenson dissimilarity index between two label lists.
sub calc_phylo_s2 {
    my $self = shift;
    my %args = @_;

    my ($A, $B, $C) = @args{qw /PHYLO_A PHYLO_B PHYLO_C/};  

    my $val;
    if ($A + $B and $A + $C) {  #  sum of each side must be non-zero
        $val = eval {1 - ($A / ($A + min ($B, $C)))};
    }    

    my %results = (PHYLO_S2 => $val);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_abc {
    
    my %arguments = (
        name            =>  'Phylogenetic ABC',
        description     =>  'Calculate the shared and not shared branch lengths between two sets of labels',
        type            =>  'Phylogenetic Indices',
        pre_calc        =>  'calc_abc',
        pre_calc_global =>  [qw /get_trimmed_tree get_path_length_cache/],
        uses_nbr_lists  =>  2,  #  how many sets of lists it must have
        required_args   => {tree_ref => 1},
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

    #  seems inefficient, but might clear a memory leak

    my %results = $self->_calc_phylo_abc(%args);
    return wantarray ? %results : \%results;
}

my $_calc_phylo_abc_precision = '%.10f';

#  Need to add a caching system for when it is building a matrix
#  - should really speed things up
sub _calc_phylo_abc {
    my $self = shift;
    my %args = @_;

    my $label_hash1 = $args{label_hash1};
    my $label_hash2 = $args{label_hash2};

    my ($phylo_A, $phylo_B, $phylo_C, $phylo_ABC)= (0, 0, 0, 0);    

    my $tree = $args{trimmed_tree};

    my $nodes_in_path1 = $self->get_path_lengths_to_root_node (
        %args,
        labels   => $label_hash1,
        tree_ref => $tree,
        el_list  => $args{element_list1},
    );

    my $nodes_in_path2 = $self->get_path_lengths_to_root_node (
        %args,
        labels   => $label_hash2,
        tree_ref => $tree,
        el_list  => $args{element_list2},
    );

    my %A = (%$nodes_in_path1, %$nodes_in_path2); 

    # create a new hash %B for nodes in label hash 1 but not 2
    # then get length of B
    my %B = %A;
    delete @B{keys %$nodes_in_path2};
    $phylo_B = sum (0, values %B);

    # create a new hash %C for nodes in label hash 2 but not 1
    # then get length of C
    my %C = %A;
    delete @C{keys %$nodes_in_path1};
    $phylo_C = sum (0, values %C);

    # get length of %A = branches not in %B or %C
    delete @A{keys %B, keys %C};
    $phylo_A = sum (0, values %A);

    $phylo_ABC = $phylo_A + $phylo_B + $phylo_C;
    
    $phylo_A = $self->set_precision (
        precision => $_calc_phylo_abc_precision,
        value     => $phylo_A,
    );
    $phylo_B = $self->set_precision (
        precision => $_calc_phylo_abc_precision,
        value     => $phylo_B,
    );
    $phylo_C = $self->set_precision (
        precision => $_calc_phylo_abc_precision,
        value     => $phylo_C,
    );
    $phylo_ABC = $self->set_precision (
        precision => $_calc_phylo_abc_precision,
        value     => $phylo_ABC,
    );

    #  return the values but reduce the precision to avoid
    #  floating point problems later on
    #my $precision = "%.10f";
    my %results = (
        PHYLO_A   => $phylo_A,
        PHYLO_B   => $phylo_B,
        PHYLO_C   => $phylo_C,
        PHYLO_ABC => $phylo_ABC,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_phylo_aed_t {
    my %arguments = (
        name            =>  'Evolutionary distinctiveness per site',
        description     =>  "Site level evolutionary distinctiveness",
        type            =>  'Phylogenetic Indices',
        pre_calc        => [qw /calc_phylo_aed/],
        uses_nbr_lists  =>  1,
        reference    => 'Cadotte & Davies (2010) dx.doi.org/10.1111/j.1472-4642.2010.00650.x',
        indices         => {
            PHYLO_ED_T => {
                description  =>  'Abundance weighted ED_t (sum of values in PHYLO_AED_LIST)',
                reference    => 'Cadotte & Davies (2010) dx.doi.org/10.1111/j.1472-4642.2010.00650.x',
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}

sub calc_phylo_aed_t {
    my $self = shift;
    my %args = @_;

    my $list = $args{PHYLO_AED_LIST};
    my $ed_t;
    foreach my $weight (values %$list) {
        $ed_t += $weight;
    }

    my %results = (PHYLO_AED_T => $ed_t);

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_phylo_aed {
    my $descr = "Evolutionary distinctiveness metrics (AED, ED, ES)\n"
                . 'Label values are constant for all '
                . 'neighbourhoods in which each label is found. '
                . 'Note that this is a beta level implementation.';

    my %arguments = (
        name            =>  'Evolutionary distinctiveness',
        description     =>  $descr,
        type            =>  'Phylogenetic Indices',
        pre_calc        => [qw /calc_abc3 get_aed_scores/],
        #pre_calc_global => [qw /get_trimmed_tree get_global_node_abundance_hash get_aed_scores/],
        #pre_calc_global => [qw /get_aed_scores/],
        uses_nbr_lists  =>  1,
        reference    => 'Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x',
        indices         => {
            PHYLO_AED_LIST => {
                description  =>  'Abundance weighted ED per terminal label',
                list         => 1,
                reference    => 'Cadotte & Davies (2010) dx.doi.org/10.1111/j.1472-4642.2010.00650.x',
            },
            PHYLO_ES_LIST => {
                description  =>  'Equal splits partitioning of PD per terminal label',
                list         => 1,
                reference    => 'Redding & Mooers (2006) http://dx.doi.org/10.1111%2Fj.1523-1739.2006.00555.x',
            },
            PHYLO_ED_LIST => {
                description  =>  '"Fair proportion" partitioning of PD per terminal label',
                list         => 1,
                reference    => 'Isaac et al. (2007) http://dx.doi.org/10.1371/journal.pone.0000296',
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}


sub calc_phylo_aed {
    my $self = shift;
    my %args = @_;

    my $label_hash = $args{label_hash_all};
    #my $global_abundance_hash = $args{node_abundance_hash};
    #my $local_abundance_hash  = $args{LOCAL_NODE_ABUNDANCE_HASH};
    my $es_wts   = $args{ES_SCORES};
    my $ed_wts   = $args{ED_SCORES};
    my $aed_wts  = $args{AED_SCORES};

    #my $tree = $args{trimmed_tree};

    my (%es, %ed, %aed);
    # now loop over the terminals and extract the weights (would slices be faster?)
    # Do we want the proportional values?  Divide by PD to get them.
    foreach my $label (keys %$label_hash) {
        $aed{$label} = $aed_wts->{$label};
        $ed{$label}  = $ed_wts->{$label};
        $es{$label}  = $es_wts->{$label};
    }

    my %results = (
        PHYLO_ES_LIST  => \%es,
        PHYLO_ED_LIST  => \%ed,
        PHYLO_AED_LIST => \%aed,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_aed_proportional {
    my %arguments = (
        name            =>  'Evolutionary distinctiveness, proportional',
        description     =>  'Evolutionary distinctiveness metrics (AED, ED, ES) '
                          . 'expressed as a proportion of PD. '
                          . 'Note that this is a beta level implementation.',
        type            =>  'Phylogenetic Indices',
        pre_calc        => 'calc_abc',
        pre_calc_global => [qw /get_phylo_aed_proportions/],
        uses_nbr_lists  =>  1,
        indices         => {
            PHYLO_AED_P_LIST => {
                description  =>  'Abundance weighted ED',
                list         => 1,
            },
            PHYLO_ES_P_LIST => {
                description  =>  'Equal splits partitioning of PD per terminal taxon. ',
                list         => 1,
            },
            PHYLO_ED_P_LIST => {
                description  =>  '"Fair proportion" partitioning of PD per terminal taxon, ',
                list         => 1,
            },
        },
    );

    return wantarray ? %arguments : \%arguments;
}


sub calc_phylo_aed_proportional {
    my $self = shift;
    my %args = @_;

    my $label_hash = $args{label_hash_all};
    my $es  = $args{ES_SCORES_P};
    my $ed  = $args{ED_SCORES_P};
    my $aed = $args{AED_SCORES_P};

    my (%es_p, %ed_p, %aed_p);

    foreach my $label (keys %$label_hash) {
        $es_p{$label}  = $es->{$label};
        $ed_p{$label}  = $ed->{$label};
        $aed_p{$label} = $aed->{$label};
    }
    
    my %results = (
        PHYLO_ES_P  => \%es_p,
        PHYLO_ED_P  => \%ed_p,
        PHYLO_AED_P => \%aed_p,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_get_phylo_aed_proportions {
    my %arguments = (
        name            =>  'Evolutionary distinctiveness, proportional',
        description     =>  "Evolutionary distinctiveness metrics (AED, ED, ES)\n"
                          . 'Label values are constant for all '
                          . 'neighbourhoods in which each label is found.  '
                          . 'These values are expressed as proportions of PD.',
        type            =>  'Phylogenetic Indices',
        pre_calc_global => [qw /get_aed_scores/],
        uses_nbr_lists  =>  1,
    );

    return wantarray ? %arguments : \%arguments;
}

sub get_phylo_aed_proportions {
    my $self = shift;
    my %args = @_;

    my $es  = $args{ES_SCORES};
    my $ed  = $args{ED_SCORES};
    my $aed = $args{AED_SCORES};

    #  Get the pd score.
    #  Cannot use calc_pd since that version is locally calculated
    my $pd = 0;
    foreach my $value (values %$ed) {
        $pd += $value;
    }

    my (%es_p, %ed_p, %aed_p);

    foreach my $label (keys %$ed) {
        $es_p{$label}  = $es->{$label}  / $pd;
        $ed_p{$label}  = $ed->{$label}  / $pd;
        $aed_p{$label} = $aed->{$label} / $pd;
    }
    
    my %results = (
        ES_SCORES_P  => \%es_p,
        ED_SCORES_P  => \%ed_p,
        AED_SCORES_P => \%aed_p,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_get_node_abundances_local {
    my $self = shift;

    my %args = (
        description     => 'A hash of the local abundance totals across terminal labels below each node',
        pre_calc        => 'calc_abc3',
        pre_calc_global => 'get_trimmed_tree',
        indices         => {
            LOCAL_NODE_ABUNDANCE_HASH => {
                description => 'Hash of local abundance totals for each node'
            },
        },
    );

    return wantarray ? %args : \%args;
}

sub get_node_abundances_local {
    my $self = shift;
    my %args = @_;
    
    my $label_hash = $args{label_hash_all};
    my $tree = $args{trimmed_tree};
    my %aed_hash = %$label_hash;
    my %ed_product_hash;
    
    while (my ($label, $count) = each %$label_hash) {
        my $nodes_in_path = $self->get_path_lengths_to_root_node (
            @_,
            labels => {$label => $count},
        );
        foreach my $node_name (keys %$nodes_in_path) {
            $aed_hash{$node_name} += $count;
        }
    }

    my %results = (
        LOCAL_NODE_ABUNDANCE_HASH   => \%aed_hash,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_aed_scores {

    my %args = (
        description     => 'A hash of the ES, ED and BED scores for each label',
        pre_calc        => [qw /calc_abc get_node_abundances_local/],
        #pre_calc_global => [qw /get_trimmed_tree get_global_node_abundance_hash/],
        pre_calc_global => [qw /get_trimmed_tree/],
        indices         => {
            ES_SCORES => {
                description => 'Hash of ES scores for each label'
            },
            ED_SCORES => {
                description => 'Hash of ED scores for each label'
            },
            AED_SCORES => {
                description => 'Hash of BED scores for each label'
            }
        },
    );
    
    return wantarray ? %args : \%args;
}

sub get_aed_scores {
    my $self = shift;
    my %args = @_;

    my $tree = $args{trimmed_tree};
    #my $node_abundances = $args{node_abundance_hash};
    my $node_abundances = $args{LOCAL_NODE_ABUNDANCE_HASH};
    my (%es_wts, %ed_wts, %aed_wts);
    my ($es_wt_sum, $ed_wt_sum, $aed_wt_sum);  #  should sum to 1
    #my $terminal_elements = $tree->get_root_node->get_terminal_elements;
    my $terminal_elements = $args{label_hash_all};

    LABEL:
    foreach my $label (keys %$terminal_elements) {

        #  check if node exists - should use a pre_calc
        my $node_ref = eval {
            $tree->get_node_ref (node => $label);
        };
        if (my $e = $EVAL_ERROR) {
            next LABEL if Biodiverse::Tree::NotExistsNode->caught;
            croak $e;
        }

        my $es_sum  = $node_ref->get_length;  #  set up the terminal
        my $ed_sum  = $node_ref->get_length;  #  set up the terminal
        my $aed_sum = $node_ref->get_length / $node_abundances->{$label};
        my $es_wt  = 1;
        my ($ed_wt, $aed_wt);
        #my $aed_label_count = $node_abundances->{$label};

        TRAVERSE_TO_ROOT:
        while ($node_ref = $node_ref->get_parent) {
            my $length = $node_ref->get_length;

            $es_wt  /= $node_ref->get_child_count;  #  es uses a cumulative scheme
            $ed_wt  =  1 / $node_ref->get_terminal_element_count;
            $aed_wt =  1 / $node_abundances->{$node_ref->get_name};

            $es_sum  += $length * $es_wt;
            $ed_sum  += $length * $ed_wt;
            $aed_sum += $length * $aed_wt;
        }

        $es_wts{$label} = $es_sum;
        $es_wt_sum += $es_wt;
        $ed_wts{$label} = $ed_sum;
        $ed_wt_sum += $ed_wt;
        $aed_wts{$label} = $aed_sum;
        $aed_wt_sum += $aed_wt;
    }

    my %results = (
        ES_SCORES  => \%es_wts,
        ED_SCORES  => \%ed_wts,
        AED_SCORES => \%aed_wts,
    );

    return wantarray ? %results : \%results;
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
