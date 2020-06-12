#  Phylogenetic indices
#  A plugin for the biodiverse system and not to be used on its own.
package Biodiverse::Indices::Phylogenetic;
use 5.020;
use strict;
use warnings;

use English qw /-no_match_vars/;
use Carp;

use Biodiverse::Progress;

use List::Util 1.33 qw /any sum min max/;
use Scalar::Util qw /blessed/;

our $VERSION = '3.1';

use constant HAVE_BD_UTILS => eval 'require Biodiverse::Utils';

use constant HAVE_PANDA_LIB
  => !$ENV{BD_NO_USE_PANDA} && eval 'require Panda::Lib';

use constant HAVE_DATA_RECURSIVE
  => !$ENV{BD_NO_USE_PANDA} && eval 'require Data::Recursive';

  
#warn "Using Data::Recursive\n" if HAVE_DATA_RECURSIVE;
  
BEGIN {
    if ($PERL_VERSION lt 'v5.22.0') {
        eval 'use parent qw /Biodiverse::Indices::Phylogenetic::DataAlias/';
    }
    else {
        eval 'use parent qw /Biodiverse::Indices::Phylogenetic::RefAlias/';
    }
}

use Biodiverse::Statistics;
my $stats_package = 'Biodiverse::Statistics';

use Biodiverse::Matrix::LowMem;
my $mx_class_for_trees = 'Biodiverse::Matrix::LowMem';

my $metadata_class = 'Biodiverse::Metadata::Indices';

sub get_metadata_calc_pd {

    my %metadata = (
        description     => 'Phylogenetic diversity (PD) based on branch '
                           . "lengths back to the root of the tree.\n"
                           . 'Uses labels in both neighbourhoods.',
        name            => 'Phylogenetic Diversity',
        type            => 'Phylogenetic Indices',
        pre_calc        => '_calc_pd',
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            PD              => {
                cluster       => undef,
                description   => 'Phylogenetic diversity',
                reference     => 'Faith (1992) Biol. Cons. https://doi.org/10.1016/0006-3207(92)91201-3',
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

    return $metadata_class->new(\%metadata);
}

sub calc_pd {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /PD PD_P PD_per_taxon PD_P_per_taxon/;
    my %results = %args{@keys};
    
    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pd_node_list {

    my %metadata = (
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

    return $metadata_class->new(\%metadata);
}

sub calc_pd_node_list {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /PD_INCLUDED_NODE_LIST/;

    my %results = %args{@keys};

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pd_terminal_node_list {

    my %metadata = (
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

    return $metadata_class->new(\%metadata);
}

sub calc_pd_terminal_node_list {
    my $self = shift;
    my %args = @_;

    my $tree_ref = $args{tree_ref};

    #  loop over nodes and just keep terminals
    my $pd_included_node_list = $args{PD_INCLUDED_NODE_LIST};
    #  this is awkward - we should be able to use Tree::get_terminal_elements directly,
    #  but it does odd things.
    my $root_node      = $tree_ref->get_root_node(tree_has_one_root_node => 1);
    my $tree_terminals = $root_node->get_terminal_elements;

    #  we could just use the ABC lists  
    my @terminal_keys = grep {exists $tree_terminals->{$_}} keys %$pd_included_node_list;
    my %terminals = %$pd_included_node_list{@terminal_keys};

    my %results = (
        PD_INCLUDED_TERMINAL_NODE_LIST => \%terminals,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pd_terminal_node_count {

    my %metadata = (
        description     => 'Number of terminal nodes in neighbour sets 1 and 2.',
        name            => 'Phylogenetic Diversity terminal node count',
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc        => 'calc_pd_terminal_node_list',
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            PD_INCLUDED_TERMINAL_NODE_COUNT => {
                description   => 'Count of tree terminal nodes included in the PD calculations',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd_terminal_node_count {
    my $self = shift;
    my %args = @_;


    #  loop over nodes and just keep terminals
    my $node_list = $args{PD_INCLUDED_TERMINAL_NODE_LIST};
    
    my %results = (
        PD_INCLUDED_TERMINAL_NODE_COUNT => scalar keys %$node_list,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_pd {
    my %metadata = (
        description     => 'Phylogenetic diversity (PD) base calcs.',
        name            => 'Phylogenetic Diversity base calcs',
        type            => 'Phylogenetic Indices',
        pre_calc        => 'calc_labels_on_tree',
        pre_calc_global => [qw /get_path_length_cache set_path_length_cache_by_group_flag/],
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => {'tree_ref' => 1},
    );

    return $metadata_class->new(\%metadata);
}

#  calculate the phylogenetic diversity of the species in the central elements only
#  this function expects a tree reference as an argument.
sub _calc_pd {
    my $self = shift;
    my %args = @_;

    my $tree_ref   = $args{tree_ref};
    my $label_list = $args{PHYLO_LABELS_ON_TREE};
    my $richness   = scalar keys %$label_list;
    
    #  the el_list is used to trigger caching, and only if we have one element
    my $el_list = [];
    my $pass_el_list = scalar @{$args{element_list1} // []} + scalar @{$args{element_list2} // []};
    if ($pass_el_list == 1) {
        $el_list = [@{$args{element_list1} // []}, @{$args{element_list2} // []}];
    }

    my $nodes_in_path = $self->get_path_lengths_to_root_node (
        @_,
        labels  => $label_list,
        el_list => $el_list,
    );

    my $PD_score = sum values %$nodes_in_path;

    #  need to use node length instead of 1
    #my %included_nodes;
    #@included_nodes{keys %$nodes_in_path} = (1) x scalar keys %$nodes_in_path;
    #my %included_nodes = %$nodes_in_path;

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

        PD_INCLUDED_NODE_LIST => $nodes_in_path,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_set_path_length_cache_by_group_flag {
    my $self = shift;

    my %metadata = (
        name            => 'Path length cache use flag',
        description     => 'Should we use the path length cache? It does not always need to be used.',
        uses_nbr_lists  => 1,  #  how many lists it must have
    );

    return $metadata_class->new(\%metadata);
    
}

sub set_path_length_cache_by_group_flag {
    my $self = shift;

    my $flag;

    #  do we have a combination of _calc_pe with _calc_pd or _calc_phylo_abc_lists, or are we in pairwise mode?
    if ($self->get_pairwise_mode) {
        $flag = 1;
    }
    else {
        no autovivification;
        my $validated_calcs = $self->get_param ('VALID_CALCULATIONS');
        my $dep_list       = $validated_calcs->{calc_deps_by_type}{pre_calc};
        if ($dep_list->{_calc_pe} && ($dep_list->{_calc_pd} || $dep_list->{_calc_phylo_abc_lists})) {
            $flag = 1;
        }
    }

    #  We set a param to avoid having to pass it around,
    #  as some of the subs which need it are not called as dependencies
    $self->set_param(USE_PATH_LENGTH_CACHE_BY_GROUP => $flag);
    
    #  no need to return any contents, but we do need to return something to keep the dep calc process happy
    return wantarray ? () : {};
}


sub get_metadata_get_path_length_cache {
    my $self = shift;

    my %metadata = (
        name            => 'get_path_length_cache',
        description     => 'Cache for path lengths.',
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            path_length_cache => {
                description => 'Path length cache hash',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_path_length_cache {
    my $self = shift;
    my %args = @_;

    my %results = (path_length_cache => {});

    return wantarray ? %results : \%results;
}

sub get_metadata_get_path_lengths_to_root_node {

    my %metadata = (
        name            => 'get_path_lengths_to_root_node',
        description     => 'Get the path lengths to the root node of a tree for a set of labels.',
        uses_nbr_lists  => 1,  #  how many lists it must have
        pre_calc_global => 'get_path_length_cache',
    );

    return $metadata_class->new(\%metadata);
}

#  get the paths to the root node of a tree for a set of labels
#  saves duplication of code in PD and PE subs
sub get_path_lengths_to_root_node {
    my $self = shift;
    my %args = (return_lengths => 1, @_);

    my $cache = !$args{no_cache};
    #$cache = 0;  #  turn it off for debug
    my $el_list = $args{el_list} // [];
    
    #  have we cached it?
    #my $use_path_cache = $cache && $self->get_pairwise_mode();
    my $use_path_cache
        =  $cache
        && $self->get_param('USE_PATH_LENGTH_CACHE_BY_GROUP')
        && scalar @$el_list == 1;  #  caching makes sense only if we have
                                   #  only one element (group) containing labels

    if ($use_path_cache) {
        my $cache_h   = $args{path_length_cache};
        #if (scalar @$el_list == 1) {  #  caching makes sense only if we have only one element (group) containing labels
            my $path = $cache_h->{$el_list->[0]};
            return (wantarray ? %$path : $path) if $path;
        #}
        #else {
        #    $use_path_cache = undef;  #  skip caching below
        #}
    }

    my $label_list = $args{labels};
    my $tree_ref   = $args{tree_ref}
      or croak "argument tree_ref is not defined\n";

    #  Avoid millions of subroutine calls below.
    #  We could use a global precalc, but that won't scale well with
    #  massive trees where we only need a subset.
    my $path_cache_master
      = $self->get_cached_value_dor_set_default_aa ('PATH_LENGTH_CACHE_PER_TERMINAL', {});
    my $path_cache = do {$path_cache_master->{$tree_ref} //= {}};

    # get a hash of node refs
    my $all_nodes = $tree_ref->get_node_hash;

    #  now loop through the labels and get the path to the root node
    my $path_hash = {};
    foreach my $label (grep {exists $all_nodes->{$_}} keys %$label_list) {
        #  Could assign to $current_node here, but profiling indicates it
        #  takes meaningful chunks of time for large data sets
        my $current_node = $all_nodes->{$label};
        my $sub_path = $cache ? $path_cache->{$current_node} : undef;

        if (!$sub_path) {
            $sub_path = $current_node->get_path_to_root_node (cache => $cache);
            my @p = map {$_->get_name} @$sub_path;
            $sub_path = \@p;
            if ($cache) {
                $path_cache->{$current_node} = $sub_path;
            }
        }

        #  This is a bottleneck for large data sets,
        #  so use an XSUB if possible.
        if (HAVE_BD_UTILS) {
            Biodiverse::Utils::add_hash_keys_until_exists (
                $path_hash,
                $sub_path,
            );
        }
        else {
            #  The last-if approach is faster than a straight slice,
            #  but we should (might) be able to get even more speedup with XS code.  
            if (!scalar keys %$path_hash) {
                @$path_hash{@$sub_path} = ();
            }
            else {
                foreach my $node_name (@$sub_path) {
                    last if exists $path_hash->{$node_name};
                    $path_hash->{$node_name} = undef;
                }
            }
        }
    }

    #  Assign the lengths once each.
    #  ~15% faster than repeatedly assigning in the slice above
    my $len_hash = $tree_ref->get_node_length_hash;
    if (HAVE_BD_UTILS) {
        Biodiverse::Utils::copy_values_from ($path_hash, $len_hash);
    }
    else {
        @$path_hash{keys %$path_hash} = @$len_hash{keys %$path_hash};
    }

    if ($use_path_cache) {
        my $cache_h = $args{path_length_cache};
        #my @el_list = @$el_list;  #  can only have one item
        $cache_h->{$el_list->[0]} = $path_hash;
    }

    return wantarray ? %$path_hash : $path_hash;
}


sub get_metadata_calc_pe {

    my $formula = [
        'PE = \sum_{\lambda \in \Lambda } L_{\lambda}\frac{r_\lambda}{R_\lambda}',
        ' where ',
        '\Lambda', ' is the set of branches found across neighbour sets 1 and 2, ',
        'L_\lambda', ' is the length of branch ',       '\lambda', ', ',
        'r_\lambda', ' is the local range of branch ',  '\lambda',
            '(the number of groups in neighbour sets 1 and 2 containing it), and ',
        'R_\lambda', ' is the global range of branch ', '\lambda',
            ' (the number of groups across the entire data set containing it).',
    ];
    
    my %metadata = (
        description     => 'Phylogenetic endemism (PE). '
                            . 'Uses labels across both neighbourhoods and '
                            . 'trims the tree to exclude labels not in the '
                            . 'BaseData object.',
        name            => 'Phylogenetic Endemism',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x'
                         . '; Laity et al. (2015) https://doi.org/10.1016/j.scitotenv.2015.04.113'
                         . '; Laffan et al. (2016) https://doi.org/10.1111/2041-210X.12513',
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => ['_calc_pe'],  
        uses_nbr_lists  => 1,  #  how many lists it must have
        formula         => $formula,
        indices         => {
            PE_WE           => {
                description => 'Phylogenetic endemism'
            },
            PE_WE_P         => {
                description => 'Phylogenetic weighted endemism as a proportion of the total tree length',
                formula     => ['PE\_WE / L', ' where L is the sum of all branch lengths in the trimmed tree'],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pe {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /PE_WE PE_WE_P/;
    my %results = %args{@keys};
    
    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pe_lists {

    my %metadata = (
        description     => 'Lists used in the Phylogenetic endemism (PE) calculations.',
        name            => 'Phylogenetic Endemism lists',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Endemism Indices', 
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
            PE_LOCAL_RANGELIST => {
                description => 'Local node ranges used in PE calculations (number of groups in which a node is found)',
                type        => 'list',
            }
        },
    );
    
    return $metadata_class->new(\%metadata);
}

sub calc_pe_lists {
    my $self = shift;
    my %args = @_;

    my @keys = qw /PE_WTLIST PE_RANGELIST PE_LOCAL_RANGELIST/;
    my %results = %args{@keys};

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pe_central {

    my $desc = <<'END_PEC_DESC'
A variant of Phylogenetic endemism (PE) that uses labels
from neighbour set 1 but local ranges from across
both neighbour sets 1 and 2.  Identical to PE if only
one neighbour set is specified.
END_PEC_DESC
  ;

    my $formula = [
        'PEC = \sum_{\lambda \in \Lambda } L_{\lambda}\frac{r_\lambda}{R_\lambda}',
        ' where ',
        '\Lambda', ' is the set of branches found across neighbour set 1 only, ',
        'L_\lambda', ' is the length of branch ',       '\lambda', ', ',
        'r_\lambda', ' is the local range of branch ',  '\lambda',
            '(the number of groups in neighbour sets 1 and 2 containing it), and ',
        'R_\lambda', ' is the global range of branch ', '\lambda',
            ' (the number of groups across the entire data set containing it).',
    ];
    
    my %metadata = (
        description     => $desc,
        name            => 'Phylogenetic Endemism central',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => [qw /_calc_pe _calc_phylo_abc_lists/],
        pre_calc_global => [qw /get_trimmed_tree/],
        uses_nbr_lists  => 1,  #  how many lists it must have
        formula         => $formula,
        indices         => {
            PEC_WE           => {
                description => 'Phylogenetic endemism, central variant'
            },
            PEC_WE_P         => {
                description => 'Phylogenetic weighted endemism as a proportion of the total tree length, central variant'
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pe_central {
    my $self = shift;
    my %args = @_;

    my $tree_ref    = $args{trimmed_tree};

    my $pe      = $args{PE_WE};
    my $pe_p    = $args{PE_WE_P};
    my $wt_list = $args{PE_WTLIST};
    my $c_list  = $args{PHYLO_C_LIST};  #  those only in nbr set 2

    #  remove the PE component found only in nbr set 2
    #  (assuming c_list is shorter than a+b, so this will be the faster approach)
    $pe -= sum (0, @$wt_list{keys %$c_list});

    $pe_p = $pe ? $pe / $tree_ref->get_total_tree_length : undef;

    my %results = (
        PEC_WE     => $pe,
        PEC_WE_P   => $pe_p,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pe_central_lists {

    my $desc = <<'END_PEC_DESC'
Lists underlying the phylogenetic endemism central indices.
Uses labels from neighbour set one but local ranges from across
both neighbour sets.
END_PEC_DESC
  ;

    my %metadata = (
        description     => $desc,
        name            => 'Phylogenetic Endemism central lists',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => [qw /_calc_pe _calc_phylo_abc_lists/],
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            PEC_WTLIST           => {
                description => 'Phylogenetic endemism weights, central variant',
                type => 'list',
            },
            PEC_LOCAL_RANGELIST  => {
                description => 'Phylogenetic endemism local range lists, central variant',
                type => 'list',
            },
            PEC_RANGELIST => {
                description => 'Phylogenetic endemism global range lists, central variant',
                type => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pe_central_lists {
    my $self = shift;
    my %args = @_;

    my $base_wt_list = $args{PE_WTLIST};
    my $c_list  =   $args{PHYLO_C_LIST};  #  those only in nbr set 2
    my $a_list  =   $args{PHYLO_A_LIST};  #  those in both lists
    my $b_list  =   $args{PHYLO_B_LIST};  #  those only in nbr set 1

    my $local_range_list  = $args{PE_LOCAL_RANGELIST};
    my $global_range_list = $args{PE_RANGELIST};

    my %results;

    #  avoid copies and slices if there are no nodes found only in nbr set 2
    if (scalar keys %$c_list) {
        #  Keep any node found in nbr set 1
        my %wt_list = %{$base_wt_list}{(keys %$a_list, keys %$b_list)};
        my %local_range_list_c  = %{$local_range_list}{keys %wt_list};
        my %global_range_list_c = %{$global_range_list}{keys %wt_list};

        $results{PEC_WTLIST} = \%wt_list;
        $results{PEC_LOCAL_RANGELIST} = \%local_range_list_c;
        $results{PEC_RANGELIST}       = \%global_range_list_c;
    }
    else {
        $results{PEC_WTLIST} = $base_wt_list;
        $results{PEC_LOCAL_RANGELIST} = $local_range_list;
        $results{PEC_RANGELIST}       = $global_range_list;
    }


    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pe_central_cwe {

    my %metadata = (
        name            => 'Corrected weighted phylogenetic endemism, central variant',
        description     => 'What proportion of the PD in neighbour set 1 is '
                         . 'range-restricted to neighbour sets 1 and 2?',
        reference       => '',
        type            => 'Phylogenetic Endemism Indices', 
        pre_calc        => [qw /calc_pe_central calc_pe_central_lists calc_pd_node_list/],
        uses_nbr_lists  => 1,
        indices         => {
            PEC_CWE => {
                description => 'Corrected weighted phylogenetic endemism, central variant',
            },
            PEC_CWE_PD => {
                description => 'PD used in the PEC_CWE index.',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pe_central_cwe {
    my $self = shift;
    my %args = @_;

    my $pe      = $args{PEC_WE};
    my $wt_list = $args{PEC_WTLIST};

    my $pd_included_node_list = $args{PD_INCLUDED_NODE_LIST};

    my $pd = sum @$pd_included_node_list{keys %$wt_list};

    my $cwe = $pd ? $pe / $pd : undef;

    my %results = (
        PEC_CWE    => $cwe,
        PEC_CWE_PD => $pd,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pd_clade_contributions {

    my %metadata = (
        description     => 'Contribution of each node and its descendents to the Phylogenetic diversity (PD) calculation.',
        name            => 'PD clade contributions',
        reference       => '',
        type            => 'Phylogenetic Indices', 
        pre_calc        => [qw /calc_pd calc_pd_node_list get_sub_tree/],
        #pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => {
            PD_CLADE_SCORE  => {
                description => 'List of PD scores for each node (clade), being the sum of all descendent branch lengths',
                type        => 'list',
            },
            PD_CLADE_CONTR  => {
                description => 'List of node (clade) contributions to the PD calculation',
                type        => 'list',
            },
            PD_CLADE_CONTR_P => {
                description => 'List of node (clade) contributions to the PD calculation, proportional to the entire tree',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd_clade_contributions {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_contributions(
        %args,
        node_list => $args{PD_INCLUDED_NODE_LIST},
        p_score   => $args{PD},
        res_pfx   => 'PD_',
    );
}


sub _calc_pd_pe_clade_contributions {
    my $self = shift;
    my %args = @_;

    my $main_tree = $args{tree_ref};
    my $sub_tree  = $args{SUBTREE};
    my $wt_list   = $args{node_list};
    my $p_score   = $args{p_score};
    my $res_pfx   = $args{res_pfx};
    my $sum_of_branches = $main_tree->get_total_tree_length;

    my $contr   = {};
    my $contr_p = {};
    my $clade_score = {};

    #  depths are (should be) the same across main and sub trees
    my $depth_hash = $main_tree->get_node_name_depth_hash;
    my $node_hash  = $sub_tree->get_node_hash;

    my @names_by_depth
      = sort {$depth_hash->{$b} <=> $depth_hash->{$a}}
        keys %$node_hash;

  NODE_REF:
    foreach my $node_name (@names_by_depth) {

        my $wt_sum = $wt_list->{$node_name};
        foreach my $child_ref ($node_hash->{$node_name}->get_children) {
            $wt_sum += $clade_score->{$child_ref->get_name};
        }

        #  round off to avoid spurious spatial variation.
        $contr->{$node_name}
          = $p_score
          ? 0 + sprintf '%.11f', $wt_sum / $p_score
          : undef;
        $contr_p->{$node_name}
          = $sum_of_branches
          ? 0 + sprintf '%.11f', $wt_sum / $sum_of_branches
          : undef;
        $clade_score->{$node_name} = $wt_sum;
    }

    my %results = (
        "${res_pfx}CLADE_SCORE"   => $clade_score,
        "${res_pfx}CLADE_CONTR"   => $contr,
        "${res_pfx}CLADE_CONTR_P" => $contr_p,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pe_clade_contributions {

    my %metadata = (
        description     => 'Contribution of each node and its descendents to the Phylogenetic endemism (PE) calculation.',
        name            => 'PE clade contributions',
        reference       => '',
        type            => 'Phylogenetic Endemism Indices', 
        pre_calc        => ['_calc_pe', 'get_sub_tree'],
        pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => {
            PE_CLADE_SCORE  => {
                description => 'List of PE scores for each node (clade), being the sum of all descendent PE weights',
                type        => 'list',
            },
            PE_CLADE_CONTR  => {
                description => 'List of node (clade) contributions to the PE calculation',
                type        => 'list',
            },
            PE_CLADE_CONTR_P => {
                description => 'List of node (clade) contributions to the PE calculation, proportional to the entire tree',
                type        => 'list',
            },
        },
    );
    
    return $metadata_class->new(\%metadata);
}

sub calc_pe_clade_contributions {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_contributions(
        %args,
        node_list => $args{PE_WTLIST},
        p_score   => $args{PE_WE},
        res_pfx   => 'PE_',
        tree_ref  => $args{trimmed_tree},
    );
}


sub get_metadata_calc_pd_clade_loss {

    my %metadata = (
        description     => 'How much of the PD would be lost if a clade were to be removed? '
                         . 'Calculates the clade PD below the last ancestral node in the '
                         . 'neighbour set which would still be in the neighbour set.',
        name            => 'PD clade loss',
        reference       => '',
        type            => 'Phylogenetic Indices', 
        pre_calc        => [qw /calc_pd_clade_contributions get_sub_tree/],
        #pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => {
            PD_CLADE_LOSS_SCORE  => {
                description => 'List of how much PD would be lost if each clade were removed.',
                type        => 'list',
            },
            PD_CLADE_LOSS_CONTR  => {
                description => 'List of the proportion of the PD score which would be lost '
                             . 'if each clade were removed.',
                type        => 'list',
            },
            PD_CLADE_LOSS_CONTR_P => {
                description => 'As per PD_CLADE_LOSS but proportional to the entire tree',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd_clade_loss {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_loss (
        %args,
        res_pfx => 'PD_',
    );
}

sub get_metadata_calc_pe_clade_loss {

    my %metadata = (
        description     => 'How much of the PE would be lost if a clade were to be removed? '
                         . 'Calculates the clade PE below the last ancestral node in the '
                         . 'neighbour set which would still be in the neighbour set.',
        name            => 'PE clade loss',
        reference       => '',
        type            => 'Phylogenetic Endemism Indices', 
        pre_calc        => [qw /calc_pe_clade_contributions get_sub_tree/],
        #pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => {
            PE_CLADE_LOSS_SCORE  => {
                description => 'List of how much PE would be lost if each clade were removed.',
                type        => 'list',
            },
            PE_CLADE_LOSS_CONTR  => {
                description => 'List of the proportion of the PE score which would be lost '
                             . 'if each clade were removed.',
                type        => 'list',
            },
            PE_CLADE_LOSS_CONTR_P => {
                description => 'As per PE_CLADE_LOSS but proportional to the entire tree',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pe_clade_loss {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_loss (
        %args,
        res_pfx => 'PE_',
    );
}


sub _calc_pd_pe_clade_loss {
    my $self = shift;
    my %args = @_;

    my $main_tree = $args{trimmed_tree};
    my $sub_tree  = $args{SUBTREE};

    my $pfx = $args{res_pfx};
    my @score_names = map {$pfx . $_} qw /CLADE_SCORE CLADE_CONTR CLADE_CONTR_P/;

    my ($p_clade_score, $p_clade_contr, $p_clade_contr_p) =
      @args{@score_names};

    my (%loss_contr, %loss_contr_p, %loss_score, %loss_ancestral);
    my $node_name;  #  reuse to avoid repeated SV destruction
    my (%child_counts, %node_names);  #  avoid some method calls

  NODE:
    foreach my $node_ref ($sub_tree->get_node_refs) {
        $node_name = ($node_names{$node_ref} //= $node_ref->get_name);

        #  skip if we have already done this one
        next NODE if defined $loss_score{$node_name};

        my @ancestors = ($node_name);

        #  Find the ancestors with no children outside this clade
        #  We are using a subtree, so the node only needs one sibling
      PARENT:
        while (my $parent = $node_ref->get_parent) {
            last PARENT
              if ($child_counts{$parent} //= $parent->get_child_count) > 1;

            push @ancestors, ($node_names{$parent} //= $parent->get_name);
            $node_ref = $parent;
        }

        my $last_ancestor = $ancestors[-1];

        foreach my $node_name (@ancestors) {
            #  these all have the same loss
            $loss_contr{$node_name}   = $p_clade_contr->{$last_ancestor};
            $loss_score{$node_name}   = $p_clade_score->{$last_ancestor};
            $loss_contr_p{$node_name} = $p_clade_contr_p->{$last_ancestor};
        }
    }

    my %results = (
        "${pfx}CLADE_LOSS_SCORE"   => \%loss_score,
        "${pfx}CLADE_LOSS_CONTR"   => \%loss_contr,
        "${pfx}CLADE_LOSS_CONTR_P" => \%loss_contr_p,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pd_clade_loss_ancestral {

    my %metadata = (
        description     => 'How much of the PD clade loss is due to the ancestral branches? '
                         . 'The score is zero when there is no ancestral loss.',
        name            => 'PD clade loss (ancestral component)',
        reference       => '',
        type            => 'Phylogenetic Indices', 
        pre_calc        => [qw /calc_pd_clade_contributions calc_pd_clade_loss/],
        uses_nbr_lists  => 1,
        indices         => {
            PD_CLADE_LOSS_ANC => {
                description => 'List of how much ancestral PE would be lost '
                             . 'if each clade were removed.  '
                             . 'The value is 0 when no ancestral PD is lost.',
                type        => 'list',
            },
            PD_CLADE_LOSS_ANC_P  => {
                description => 'List of the proportion of the clade\'s PD loss '
                             . 'that is due to the ancestral branches.',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}


sub calc_pd_clade_loss_ancestral {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_loss_ancestral (
        %args,
        res_pfx => 'PD_',
    );
}


sub get_metadata_calc_pe_clade_loss_ancestral {

    my %metadata = (
        description     => 'How much of the PE clade loss is due to the ancestral branches? '
                         . 'The score is zero when there is no ancestral loss.',
        name            => 'PE clade loss (ancestral component)',
        reference       => '',
        type            => 'Phylogenetic Endemism Indices', 
        pre_calc        => [qw /calc_pe_clade_contributions calc_pe_clade_loss/],
        uses_nbr_lists  => 1,
        indices         => {
            PE_CLADE_LOSS_ANC => {
                description => 'List of how much ancestral PE would be lost '
                             . 'if each clade were removed.  '
                             . 'The value is 0 when no ancestral PE is lost.',
                type        => 'list',
            },
            PE_CLADE_LOSS_ANC_P  => {
                description => 'List of the proportion of the clade\'s PE loss '
                             . 'that is due to the ancestral branches.',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}


sub calc_pe_clade_loss_ancestral {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_loss_ancestral (
        %args,
        res_pfx => 'PE_',
    );
}

sub _calc_pd_pe_clade_loss_ancestral {
    my $self = shift;
    my %args = @_;

    my $pfx = $args{res_pfx};
    my @score_names = map {$pfx . $_} qw /CLADE_SCORE CLADE_LOSS_SCORE/;

    my ($p_clade_score, $p_clade_loss) =
      @args{@score_names};

    my (%loss_ancestral, %loss_ancestral_p);

    while (my ($node_name, $score) = each %$p_clade_score) {
        my $score = $p_clade_loss->{$node_name}
                  - $p_clade_score->{$node_name};
        $loss_ancestral{$node_name}   = $score;
        my $loss = $p_clade_loss->{$node_name};
        $loss_ancestral_p{$node_name} = $loss ? $score / $loss : 0;
    }

    my %results = (
        "${pfx}CLADE_LOSS_ANC"   => \%loss_ancestral,
        "${pfx}CLADE_LOSS_ANC_P" => \%loss_ancestral_p,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_pe_single {

    my $formula = [
        'PE\_SINGLE = \sum_{\lambda \in \Lambda } L_{\lambda}\frac{1}{R_\lambda}',
        ' where ',
        '\Lambda', ' is the set of branches found across neighbour sets 1 and 2, ',
        'L_\lambda', ' is the length of branch ',       '\lambda', ', ',
        'R_\lambda', ' is the global range of branch ', '\lambda',
            ' (the number of groups across the entire data set containing it).',
    ];
    
    my $description = <<'EOD'
PE scores, but not weighted by local ranges.
This is the strict interpretation of the formula given in
Rosauer et al. (2009), although the approach has always been
implemented as the fraction of each branch's geographic range
that is found in the sample window (see formula for PE_WE).
EOD
  ;

    my %metadata = (
        description     => $description,
        name            => 'Phylogenetic Endemism single',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => ['_calc_pe'],
        pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => {
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
    
    return $metadata_class->new(\%metadata);
}

sub calc_pe_single {
    my $self = shift;
    my %args = @_;
    
    my $node_ranges = $args{PE_RANGELIST};
    #my %wts;
    my $tree = $args{trimmed_tree};
    my $pe_single;

    foreach my $node_name (keys %$node_ranges) {
        my $range    = $node_ranges->{$node_name};
        my $node_ref = $tree->get_node_ref (node => $node_name);
        #$wts{$node_name} = $node_ref->get_length;
        $pe_single += $node_ref->get_length / $range;
    }
    
    my $tree_length = $tree->get_total_tree_length;
    my $pe_single_p = defined $pe_single ? ($pe_single / $tree_length) : undef;
    
    my %results = (
        PE_WE_SINGLE   => $pe_single,
        PE_WE_SINGLE_P => $pe_single_p,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_pd_endemism {

    my %metadata = (
        description     => 'Absolute endemism analogue of PE.  '
                        .  'It is the sum of the branch lengths restricted '
                        .  'to the neighbour sets.',
        name            => 'PD-Endemism',
        reference       => 'See Faith (2004) Cons Biol.  https://doi.org/10.1111/j.1523-1739.2004.00330.x',
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => ['calc_pe_lists'],
        pre_calc_global => [qw /get_trimmed_tree/],
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            PD_ENDEMISM => {
                description => 'Phylogenetic Diversity Endemism',
            },
            PD_ENDEMISM_WTS => {
                description => 'Phylogenetic Diversity Endemism weights per node found only in the neighbour set',
                type        => 'list',
            },
            PD_ENDEMISM_P => {
                description => 'Phylogenetic Diversity Endemism, as a proportion of the whole tree',
            },
            #PD_ENDEMISM_R => {  #  should put in its own calc as it needs an extra dependency
            #    description => 'Phylogenetic Diversity Endemism, as a proportion of the local PD',
            #},
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd_endemism {
    my $self = shift;
    my %args = @_;

    my $weights   = $args{PE_WTLIST};
    my $tree_ref  = $args{trimmed_tree};
    my $total_len = $tree_ref->get_total_tree_length;
    my $global_range_hash = $args{PE_RANGELIST};
    my $local_range_hash  = $args{PE_LOCAL_RANGELIST};

    my $pd_e;
    my %pd_e_wts;

  LABEL:
    foreach my $label (keys %$weights) {
        next LABEL if $global_range_hash->{$label} != $local_range_hash->{$label};

        my $wt = $weights->{$label};
        $pd_e += $wt;
        $pd_e_wts{$label} = $wt;
    }

    my $pd_e_p = (defined $pd_e && $total_len) ? ($pd_e / $total_len) : undef;

    my %results = (
        PD_ENDEMISM     => $pd_e,
        PD_ENDEMISM_P   => $pd_e_p,
        PD_ENDEMISM_WTS => \%pd_e_wts,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_pe {

    my %metadata = (
        description     => 'Phylogenetic endemism (PE) base calcs.',
        name            => 'Phylogenetic Endemism base calcs',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Endemism Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc_global => [ qw /
            get_node_range_hash
            get_trimmed_tree
            get_pe_element_cache
            get_path_length_cache
            set_path_length_cache_by_group_flag
        /],
        pre_calc        => ['calc_abc'],  #  don't need calc_abc2 as we don't use its counts
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => {'tree_ref' => 1},
    );
    
    return $metadata_class->new(\%metadata);
}


sub get_metadata_calc_count_labels_on_tree {
    my $self = shift;

    my %metadata = (
        description     => 'Count the number of labels that are on the tree',
        name            => 'Count labels on tree',
        indices         => {
            PHYLO_LABELS_ON_TREE_COUNT => {
                description => 'The number of labels that are found on the tree, across both neighbour sets',
            },
        },
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc        => ['calc_labels_on_tree'],
        uses_nbr_lists  => 1,  #  how many lists it must have
    );

    return $metadata_class->new(\%metadata);
}

sub calc_count_labels_on_tree {
    my $self = shift;
    my %args = @_;
    
    my $labels_on_tree = $args{PHYLO_LABELS_ON_TREE};
    
    my %results = (PHYLO_LABELS_ON_TREE_COUNT => scalar keys %$labels_on_tree);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_labels_on_tree {
    my $self = shift;

    my %metadata = (
        description     => 'Create a hash of the labels that are on the tree',
        name            => 'Labels on tree',
        indices         => {
            PHYLO_LABELS_ON_TREE => {
                description => 'A hash of labels that are found on the tree, across both neighbour sets',
                type        => 'list',
            },  #  should poss also do nbr sets 1 and 2
        },
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc_global => [qw /get_labels_not_on_tree/],
        pre_calc        => ['calc_abc'],
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => ['tree_ref'],
    );

    return $metadata_class->new(\%metadata);
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

    my %metadata = (
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

    return $metadata_class->new(\%metadata);
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
    
    my %metadata = (
        name        => 'get_pe_element_cache',
        description => 'Create a hash in which to cache the PE scores for each element',
        indices     => {
            PE_RESULTS_CACHE => {
                description => 'The hash in which to cache the PE scores for each element'
            },
        },
    );

    return $metadata_class->new(\%metadata);
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
    my %metadata = (
        name            => 'get_node_range_hash_as_lists',
        description     => 'Get a hash of the node range lists across the basedata',
        pre_calc_global => ['get_trimmed_tree'],
        indices => {
            node_range_hash => {
                description => 'Hash of node range lists',
            },
        },
    );

    return $metadata_class->new(\%metadata);
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
    my %metadata = (
        name            => 'get_node_range_hash',
        description     => 'Get a hash of the node ranges across the basedata',
        pre_calc_global => ['get_trimmed_tree'],
        indices => {
            node_range => {
                description => 'Hash of node ranges',
            },
        },
    );
    return $metadata_class->new(\%metadata);
}

#  needs a cleanup - see get_global_node_abundance_hash
# calculate the range occupied by each node/clade in a tree
# this function expects a tree reference as an argument
sub get_node_range_hash { 
    my $self = shift;
    my %args = @_;

    my $return_lists = $args{return_lists};

    my $progress_bar = Biodiverse::Progress->new();    

    say "[PD INDICES] Calculating range for each node in the tree";

    my $tree  = $args{trimmed_tree} || croak "Argument trimmed_tree missing\n";  
    my $nodes = $tree->get_node_hash;
    my %node_range;

    my $to_do = scalar keys %$nodes;
    my $count = 0;
    print "[PD INDICES] Progress (% of $to_do nodes): ";

    my $progress      = $count / $to_do;
    my $progress_text = int (100 * $progress);
    $progress_bar->update(
        "Calculating node ranges\n($progress_text %)",
        $progress,
    );

    #  sort by depth so we start from the terminals
    #  and avoid recursion in get_node_range
    my %d;
    foreach my $node (
      sort {($d{$b} //= $b->get_depth) <=> ($d{$a} //= $a->get_depth)}
      values %$nodes) {
        
        my $node_name = $node->get_name;
        if ($return_lists) {
            my $range = $self->get_node_range (
                %args,
                return_list => 1,
                node_ref    => $node,
            );
            my %range_hash;
            @range_hash{@$range} = ();
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
        $progress      = $count / $to_do;
        $progress_text = int (100 * $progress);
        $progress_bar->update(
            "Calculating node ranges\n($progress_text)",
            $progress,
        );
    }

    my %results = (node_range => \%node_range);

    return wantarray ? %results : \%results;
}


sub get_node_range {
    my $self = shift;
    my %args = @_;

    my $node_ref = $args{node_ref} || croak "node_ref arg not specified\n";
    my $bd = $args{basedata_ref} || $self->get_basedata_ref;
    
    #  sometimes a child node has the full set,
    #  so there is no need to keep collating
    my $max_poss_group_count = $bd->get_group_count;

    my $return_count = !wantarray && !$args{return_list};

    my $cache_name = 'NODE_RANGE_LISTS';
    my $cache      = $self->get_cached_value_dor_set_default_aa ($cache_name, {});

    if (my $groups = $cache->{$node_ref}) {
        return scalar keys %$groups if $return_count;
        return wantarray ? %$groups : [keys %$groups];
    }

    my $node_name = $node_ref->get_name;
    my %groups;

    my $children = $node_ref->get_children // [];

    if (  !$node_ref->is_internal_node && $bd->exists_label_aa($node_name)) {
        my $gp_list = $bd->get_groups_with_label_as_hash_aa ($node_name);
        if (HAVE_DATA_RECURSIVE) {
            Data::Recursive::hash_merge (\%groups, $gp_list, Data::Recursive::LAZY());
        }
        elsif (HAVE_PANDA_LIB) {
            Panda::Lib::hash_merge (\%groups, $gp_list, Panda::Lib::MERGE_LAZY());
        }
        else {
            @groups{keys %$gp_list} = undef;
        }
    }
    if (scalar @$children && $max_poss_group_count != keys %groups) {
      CHILD:
        foreach my $child (@$children) {
            my $cached_list = $cache->{$child};
            if (!defined $cached_list) {
                #  bodge to work around inconsistent returns
                #  (can be a key count, a hash, or an array ref of keys)
                my $c = $self->get_node_range (node_ref => $child, return_list => 1);
                if (HAVE_DATA_RECURSIVE) {
                    Data::Recursive::hash_merge (\%groups, $c, Data::Recursive::LAZY());
                }
                elsif (HAVE_PANDA_LIB) {
                    Panda::Lib::hash_merge (\%groups, $c, Panda::Lib::MERGE_LAZY());
                }
                else {
                    @groups{@$c} = undef;
                }
            }
            else {
                if (HAVE_DATA_RECURSIVE) {
                    Data::Recursive::hash_merge (\%groups, $cached_list, Data::Recursive::LAZY());
                }
                elsif (HAVE_PANDA_LIB) {
                    Panda::Lib::hash_merge (\%groups, $cached_list, Panda::Lib::MERGE_LAZY());
                }
                else {    
                    @groups{keys %$cached_list} = undef;
                }
            }
            last CHILD if $max_poss_group_count == keys %groups;
        }
    }

    #  Cache by ref because future cases might use the cache
    #  for multiple trees with overlapping name sets.
    $cache->{$node_ref} = \%groups;

    return scalar keys %groups if $return_count;
    return wantarray ? %groups : [keys %groups];
}


sub get_metadata_get_global_node_terminal_count_cache {
    my %metadata = (
        name            => 'get_global_node_terminal_count_cache',
        description     => 'Get a cache for all nodes and their terminal counts',
        pre_calc_global => [],
        indices         => {
            global_node_terminal_count_cache => {
                description => 'Global node terminal count cache',
            }
        }
    );

    return $metadata_class->new(\%metadata);
}

sub get_global_node_terminal_count_cache {
    my $self = shift;

    my %results = (
        global_node_terminal_count_cache => {},
    );
    
    return wantarray ? %results : \%results;
}


sub get_metadata_get_global_node_abundance_hash {
    my %metadata = (
        name            => 'get_global_node_abundance_hash',
        description     => 'Get a hash of all nodes and their corresponding abundances in the basedata',
        pre_calc_global => ['get_trimmed_tree', 'get_node_abundance_global_cache'],
        indices         => {
            global_node_abundance_hash => {
                description => 'Global node abundance hash',
            }
        }
    );

    return $metadata_class->new(\%metadata);
}


sub get_global_node_abundance_hash {
    my $self = shift;
    my %args = @_;

    my $progress_bar = Biodiverse::Progress->new();    

    say '[PD INDICES] Calculating abundance for each node in the tree';

    my $tree  = $args{trimmed_tree} || croak "Argument trimmed_tree missing\n";  
    my $nodes = $tree->get_node_hash;
    my %node_abundance_hash;

    my $to_do = scalar keys %$nodes;
    my $count = 0;

    my $progress = int (100 * $count / $to_do);
    $progress_bar->update(
        "Calculating node abundances\n($progress)",
        $progress,
    );

    #  should get terminals and then climb up the tree, adding as we go
    foreach my $node (values %$nodes) {
        #my $node  = $tree->get_node_ref (node => $node_name);
        my $abundance = $self->get_node_abundance_global (
            %args,
            node_ref => $node,
        );
        if (defined $abundance) {
            $node_abundance_hash{$node->get_name} = $abundance;
        }

        $count ++;
        my $progress = $count / $to_do;
        $progress_bar->update(
            "Calculating node abundances\n($progress)",
            $progress,
        );
    }

    my %results = (global_node_abundance_hash => \%node_abundance_hash);

    return wantarray ? %results : \%results;
}

sub get_metadata_get_node_abundance_global_cache {
    my %metadata = (
        name            => 'get_node_abundance_global',
        description     => 'Get a cache for the global node abundances',
        indices         => {
            node_abundance_global_cache => {
                description => 'Cache for global node abundances',
            },
        },
    );
    return $metadata_class->new(\%metadata);
}

sub get_node_abundance_global_cache {
    my $self = shift;
  
    my %results = (
        node_abundance_global_cache => {},
    );

    return wantarray ? %results : \%results;
}


sub get_node_abundance_global {
    my $self = shift;
    my %args = @_;

    my $node_ref = $args{node_ref} || croak "node_ref arg not specified\n";
    my $cache = $args{node_abundance_global_cache} // croak 'no node_abundance_global_cache';

    my $bd = $args{basedata_ref} || $self->get_basedata_ref;
    
    my $abundance = 0;
    if ($node_ref->is_terminal_node) {
        $abundance += ($cache->{$node_ref->get_name}
                       //= $bd->get_label_sample_count (element => $node_ref->get_name)
                       );
    }
    else {
        my $children =  $node_ref->get_terminal_elements;
        foreach my $name (keys %$children) {
            $abundance += ($cache->{$name}
                           //= $bd->get_label_sample_count (element => $name)
                          );
        }
    }

    return $abundance;
}


sub get_metadata_get_trimmed_tree {
    my %metadata = (
        name            => 'get_trimmed_tree',
        description     => 'Get a version of the tree trimmed to contain only labels in the basedata',
        required_args   => 'tree_ref',
        indices         => {
            trimmed_tree => {
                description => 'Trimmed tree',
            },
        },
    );
    return $metadata_class->new(\%metadata);
}

#  Create a copy of the current tree, including only those branches
#  which have records in the basedata.
#  This function expects a tree reference as an argument.
#  Returns the original tree ref if all its branches occur in the basedata.
sub get_trimmed_tree {
    my $self = shift;
    my %args = @_;                          

    my $tree = $args{tree_ref};

    my $bd = $self->get_basedata_ref;
    my $lb = $bd->get_labels_ref;
    
    my $terminals  = $tree->get_root_node->get_terminal_elements;  #  should use named nodes?
    my $label_hash = $lb->get_element_hash;

    my (%tmp_combo, %tmp1, %tmp2);
    my $b_score;
    @tmp1{keys %$terminals}  = (1) x scalar keys %$terminals;
    @tmp2{keys %$label_hash} = (1) x scalar keys %$label_hash;
    %tmp_combo = %tmp1;
    @tmp_combo{keys %tmp2}   = (1) x scalar keys %tmp2;

    #  a is common to tree and basedata
    #  b is unique to tree
    #  c is unique to basedata
    #  but we only need b here
    $b_score = scalar (keys %tmp_combo)
       - scalar (keys %tmp2);

    if (!$b_score) {
        say '[PD INDICES] Tree terminals are all basedata labels, no need to trim';
        my %results = (trimmed_tree => $tree);
        return wantarray ? %results : \%results;
    }

    #  keep only those that match the basedata object
    say '[PD INDICES] Creating a trimmed tree by removing clades not present in the basedata';
    my $trimmed_tree = $tree->clone;
    $trimmed_tree->trim (keep => scalar $bd->get_labels);
    my $name = $trimmed_tree->get_param('NAME') // 'noname';
    $trimmed_tree->rename(new_name => $name . ' trimmed');

    my %results = (trimmed_tree => $trimmed_tree);

    return wantarray ? %results : \%results;
}


sub get_metadata_get_sub_tree {
    my $self = shift;

    my %metadata = (
        name          => 'get_sub_tree',
        description   => 'get a tree that is a subset of the main tree, e.g. for the set of nodes in a neighbour set',
        required_args => 'tree_ref',
        pre_calc      => ['calc_labels_on_tree'],
    );

    return $metadata_class->new(\%metadata);
}


#  get a tree that is a subset of the main tree,
#  e.g. for the set of nodes in a neighbour set
sub get_sub_tree {
    my $self = shift;
    my %args = @_;

    my $tree       = $args{tree_ref};
    my $label_list = $args{labels} // $args{PHYLO_LABELS_ON_TREE};

    #  Could devise a better naming scheme,
    #  but element lists can be too long to be workable
    #  and abbreviations will be ambiguous in many cases
    my $subtree = blessed ($tree)->new (NAME => 'subtree');

  LABEL:
    foreach my $label (keys %$label_list) {
        my $node_ref = eval {$tree->get_node_ref (node => $label)};
        next LABEL if !defined $node_ref;  # not a tree node name

        my $child_name = $label;
        my $st_node_ref = $subtree->add_node (
            name   => $label,
            length => $node_ref->get_length,
        );

      NODE_IN_PATH:
        while (my $parent = $node_ref->get_parent()) {

            my $parent_name = $parent->get_name;
            my $st_parent;
            if ($subtree->exists_node_name_aa ($parent_name)) {
                $st_parent = eval {
                    $subtree->get_node_ref_aa ($parent_name);
                };
            }
            my $last = defined $st_parent;  #  we have the rest of the path in this case

            if (!$last) {
                $st_parent = $subtree->add_node (
                    name   => $parent_name,
                    length => $parent->get_length,
                );
            }
            $st_parent->add_children (
                children     => [$st_node_ref],
                is_treenodes => 1,
            );

            last NODE_IN_PATH if $last;

            $node_ref    = $parent;
            $st_node_ref = $st_parent;
        }
    }

    #  make sure the topology is correct - needed?
    #$subtree->set_parents_below;

    my %results = (SUBTREE => $subtree);

    return wantarray ? %results : \%results;
}

sub get_metadata_get_labels_not_on_tree {
    my $self = shift;

    my %metadata = (
        name          => 'get_labels_not_on_tree',
        description   => 'Hash of the basedata labels that are not on the tree',
        required_args => 'tree_ref',
        indices       => {
            labels_not_on_tree => {
                description => 'Hash of the basedata labels that are not on the tree',
            },
        },
    );

    return $metadata_class->new(\%metadata);
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
            . 'https://doi.org/10.3354/meps129301 ; '
            . 'Clarke & Warwick (2001) Mar Ecol Progr Ser. '
            . 'https://doi.org/10.3354/meps216265';
    
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

    return $metadata_class->new(\%metadata);
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
                '= \frac{\sum \sum_{i \neq j} \omega_{ij}}{s(s-1)}',
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
                '= \frac{\sum \sum_{i \neq j} \omega_{ij}^2}{s(s-1)} - \bar{\omega}^2',
                'where ',
                '\bar{\omega} = \frac{\sum \sum_{i \neq j} \omega_{ij}}{s(s-1)} \equiv TDB\_DISTINCTNESS',
            ],
        },
    };

    my $ref = 'Warwick & Clarke (1995) Mar Ecol Progr Ser. '
            . 'https://doi.org/10.3354/meps129301 ; '
            . 'Clarke & Warwick (2001) Mar Ecol Progr Ser. '
            . 'https://doi.org/10.3354/meps216265';

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

    return $metadata_class->new(\%metadata);
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

sub get_metadata_get_trimmed_tree_as_matrix {
    my $self = shift;

    my %metadata = (
        name            => 'get_trimmed_tree_as_matrix',
        description     => 'Get the trimmed tree as a matrix',
        pre_calc_global => ['get_trimmed_tree'],
    );

    return $metadata_class->new(\%metadata);
}

sub get_trimmed_tree_as_matrix {
    my $self = shift;
    my %args = @_;

    my $mx = $args{trimmed_tree}->to_matrix (class => $mx_class_for_trees);

    my %results = (TRIMMED_TREE_AS_MATRIX => $mx);

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_phylo_sorenson {
    
    my %metadata = (
        name           =>  'Phylo Sorenson',
        type           =>  'Phylogenetic Turnover',  #  keeps it clear of the other indices in the GUI
        description    =>  "Sorenson phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches\n",
        reference      => 'Bryant et al. (2008) https://doi.org/10.1073/pnas.0801920105',
        pre_calc       =>  'calc_phylo_abc',
        uses_nbr_lists =>  2,  #  how many sets of lists it must have
        indices        => {
            PHYLO_SORENSON => {
                cluster     =>  'NO_CACHE_ABC',
                bounds      =>  [0, 1],
                formula     =>  [
                    '1 - (2A / (2A + B + C))',
                    ' where A is the length of shared branches, '
                    . 'and B and C are the length of branches found only in neighbour sets 1 and 2'
                ],
                description => 'Phylo Sorenson score',
                cluster_can_lump_zeroes => 1,
            }
        },
        required_args => {'tree_ref' => 1}
    );

    return $metadata_class->new(\%metadata); 
}

# calculate the phylogenetic Sorenson dissimilarity index between two label lists.
sub calc_phylo_sorenson {

    my $self = shift;
    my %args = @_;

    my ($A, $B, $C, $ABC) = @args{qw /PHYLO_A PHYLO_B PHYLO_C PHYLO_ABC/};

    my $val;
    if ($A || ($B && $C)) {  #  sum of each side must be non-zero
        $val = eval {1 - (2 * $A / ($A + $ABC))};
    }

    my %results = (PHYLO_SORENSON => $val);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_jaccard {

    my %metadata = (
        name           =>  'Phylo Jaccard',
        type           =>  'Phylogenetic Turnover',
        description    =>  "Jaccard phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches\n",
        reference      => 'Lozupone and Knight (2005) https://doi.org/10.1128/AEM.71.12.8228-8235.2005',
        pre_calc       =>  'calc_phylo_abc',
        uses_nbr_lists =>  2,  #  how many sets of lists it must have
        indices        => {
            PHYLO_JACCARD => {
                cluster     =>  'NO_CACHE_ABC',
                bounds      =>  [0, 1],
                formula     =>  [
                    '= 1 - (A / (A + B + C))',
                    ' where A is the length of shared branches, '
                    . 'and B and C are the length of branches found only in neighbour sets 1 and 2',
                ],
                description => 'Phylo Jaccard score',
                cluster_can_lump_zeroes => 1,
            }
        },
        required_args => {'tree_ref' => 1}
    );

    return $metadata_class->new(\%metadata);
}

# calculate the phylogenetic Sorenson dissimilarity index between two label lists.
sub calc_phylo_jaccard {
    my $self = shift;
    my %args = @_;

    my ($A, $B, $C, $ABC) = @args{qw /PHYLO_A PHYLO_B PHYLO_C PHYLO_ABC/};  

    my $val;
    if ($A || ($B && $C)) {  #  sum of each side must be non-zero
        $val = eval {1 - ($A / $ABC)};
    }    

    my %results = (PHYLO_JACCARD => $val);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_s2 {

    my %metadata = (
        name           =>  'Phylo S2',
        type           =>  'Phylogenetic Turnover',
        description    =>  "S2 phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches\n",
        pre_calc       =>  'calc_phylo_abc',
        uses_nbr_lists =>  2,  #  how many sets of lists it must have
        indices        => {
            PHYLO_S2 => {
                cluster     =>  'NO_CACHE_ABC',
                formula     =>  [
                    '= 1 - (A / (A + min (B, C)))',
                    ' where A is the sum of shared branch lengths, '
                    . 'and B and C are the sum of branch lengths found'
                    . 'only in neighbour sets 1 and 2',
                ],
                description => 'Phylo S2 score',
                bounds      => [0, 1],
                #  min (B,C) in denominator means cluster order
                #  influences tie breaker results as different
                #  assemblages are merged
                cluster_can_lump_zeroes => 0,
            }
        },
        required_args => {'tree_ref' => 1}
    );

    return $metadata_class->new(\%metadata);
}

# calculate the phylogenetic S2 dissimilarity index between two label lists.
sub calc_phylo_s2 {
    my $self = shift;
    my %args = @_;

    my ($A, $B, $C) = @args{qw /PHYLO_A PHYLO_B PHYLO_C/};  

    my $val;
    if ($A || ($B && $C)) {  #  sum of each side must be non-zero
        $val = eval {1 - ($A / ($A + min ($B, $C)))};
    }

    my %results = (PHYLO_S2 => $val);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_abc {
    
    my %metadata = (
        name            =>  'Phylogenetic ABC',
        description     =>  'Calculate the shared and not shared branch lengths between two sets of labels',
        type            =>  'Phylogenetic Turnover',
        pre_calc        =>  '_calc_phylo_abc_lists',
        #pre_calc_global =>  [qw /get_trimmed_tree get_path_length_cache/],
        uses_nbr_lists  =>  2,  #  how many sets of lists it must have
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

    return $metadata_class->new(\%metadata);
}

my $_calc_phylo_abc_precision = 10 ** 10;

sub calc_phylo_abc {
    my $self = shift;
    my %args = @_;

    my $A = $args{PHYLO_A_LIST};
    my $B = $args{PHYLO_B_LIST};
    my $C = $args{PHYLO_C_LIST};

    my $phylo_A = sum (0, values %$A);
    my $phylo_B = sum (0, values %$B);
    my $phylo_C = sum (0, values %$C);

    my $phylo_ABC = $phylo_A + $phylo_B + $phylo_C;
    
    #  return the values but reduce the precision to avoid
    #  floating point problems later on

    $phylo_A   = $self->round_to_precision_aa ($phylo_A,   $_calc_phylo_abc_precision);
    $phylo_B   = $self->round_to_precision_aa ($phylo_B,   $_calc_phylo_abc_precision);
    $phylo_C   = $self->round_to_precision_aa ($phylo_C,   $_calc_phylo_abc_precision);
    $phylo_ABC = $self->round_to_precision_aa ($phylo_ABC, $_calc_phylo_abc_precision);

    my %results = (
        PHYLO_A   => $phylo_A,
        PHYLO_B   => $phylo_B,
        PHYLO_C   => $phylo_C,
        PHYLO_ABC => $phylo_ABC,
    );

    return wantarray ? %results : \%results;
}



sub get_metadata__calc_phylo_abc_lists {

    my %metadata = (
        name            =>  'Phylogenetic ABC lists',
        description     =>  'Calculate the sets of shared and not shared branches between two sets of labels',
        type            =>  'Phylogenetic Indices',
        pre_calc        =>  'calc_abc',
        pre_calc_global =>  [qw /get_trimmed_tree get_path_length_cache set_path_length_cache_by_group_flag/],
        uses_nbr_lists  =>  1,  #  how many sets of lists it must have
        required_args   => {tree_ref => 1},
    );

    return $metadata_class->new(\%metadata);
}

sub _calc_phylo_abc_lists {
    my $self = shift;
    my %args = @_;

    my $label_hash1 = $args{label_hash1};
    my $label_hash2 = $args{label_hash2};

    my $tree = $args{trimmed_tree};

    my $nodes_in_path1 = $self->get_path_lengths_to_root_node (
        %args,
        labels   => $label_hash1,
        tree_ref => $tree,
        el_list  => [keys %{$args{element_list1}}],
    );

    my $nodes_in_path2 = $self->get_path_lengths_to_root_node (
        %args,
        labels   => $label_hash2,
        tree_ref => $tree,
        el_list  => [keys %{$args{element_list2}}],
    );

    my %results;
    #  one day we can clean this all up
    if (HAVE_BD_UTILS) {
        my $res = Biodiverse::Utils::get_hash_shared_and_unique (
            $nodes_in_path1,
            $nodes_in_path2,
        );
        %results = (
            PHYLO_A_LIST => $res->{a},
            PHYLO_B_LIST => $res->{b},
            PHYLO_C_LIST => $res->{c},
        );
    }
    else {
        my %A;
        if (HAVE_DATA_RECURSIVE) {
            Data::Recursive::hash_merge (\%A, $nodes_in_path1, Data::Recursive::LAZY());
            Data::Recursive::hash_merge (\%A, $nodes_in_path2, Data::Recursive::LAZY());
        }
        elsif (HAVE_PANDA_LIB) {
            Panda::Lib::hash_merge (\%A, $nodes_in_path1, Panda::Lib::MERGE_LAZY());
            Panda::Lib::hash_merge (\%A, $nodes_in_path2, Panda::Lib::MERGE_LAZY());
        }
        else {
            %A = (%$nodes_in_path1, %$nodes_in_path2);
        }
    
        # create a new hash %B for nodes in label hash 1 but not 2
        # then get length of B
        my %B = %A;
        delete @B{keys %$nodes_in_path2};
    
        # create a new hash %C for nodes in label hash 2 but not 1
        # then get length of C
        my %C = %A;
        delete @C{keys %$nodes_in_path1};
    
        # get length of %A = branches not in %B or %C
        delete @A{keys %B, keys %C};
    
         %results = (
            PHYLO_A_LIST => \%A,
            PHYLO_B_LIST => \%B,
            PHYLO_C_LIST => \%C,
        );
    }

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_corrected_weighted_endemism{
    
    my $descr = 'Corrected weighted endemism.  '
              . 'This is the phylogenetic analogue of corrected '
              . 'weighted endemism.';

    my %metadata = (
        name            => 'Corrected weighted phylogenetic endemism',
        description     => q{What proportion of the PD is range-restricted to this neighbour set?},
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => [qw /calc_pe calc_pd/],
        uses_nbr_lists  =>  1,
        reference       => '',
        indices         => {
            PE_CWE => {
                description  => $descr,
                reference    => '',
                formula      => ['PE\_WE / PD'],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_corrected_weighted_endemism {
    my $self = shift;
    my %args = @_;

    my $pe = $args{PE_WE};
    my $pd = $args{PD};
    no warnings 'uninitialized';

    my %results = (
        PE_CWE => $pd ? $pe / $pd : undef,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_corrected_weighted_rarity {
    
    my $descr = 'Corrected weighted phylogenetic rarity.  '
              . 'This is the phylogenetic rarity analogue of corrected '
              . 'weighted endemism.';

    my %metadata = (
        name            =>  'Corrected weighted phylogenetic rarity',
        description     =>  q{What proportion of the PD is abundance-restricted to this neighbour set?},
        type            =>  'Phylogenetic Endemism Indices',
        pre_calc        => [qw /_calc_phylo_aed_t calc_pd/],
        uses_nbr_lists  =>  1,
        reference       => '',
        indices         => {
            PHYLO_RARITY_CWR => {
                description  => $descr,
                reference    => '',
                formula      => ['AED_T / PD'],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_corrected_weighted_rarity {
    my $self = shift;
    my %args = @_;

    my $aed_t = $args{PHYLO_AED_T};
    my $pd    = $args{PD};
    no warnings 'uninitialized';

    my %results = (
        PHYLO_RARITY_CWR => $pd ? $aed_t / $pd : undef,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_aed_t {
    
    my $descr = 'Abundance weighted ED_t '
              . '(sum of values in PHYLO_AED_LIST times their abundances).'
              . ' This is equivalent to a phylogenetic rarity score '
              . '(see phylogenetic endemism)';

    my %metadata = (
        name            =>  'Evolutionary distinctiveness per site',
        description     =>  'Site level evolutionary distinctiveness',
        type            =>  'Phylogenetic Indices',
        pre_calc        => [qw /_calc_phylo_aed_t/],
        uses_nbr_lists  =>  1,
        reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
        indices         => {
            PHYLO_AED_T => {
                description  => $descr,
                reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_aed_t {
    my $self = shift;
    my %args = @_;

    my %results = (PHYLO_AED_T => $args{PHYLO_AED_T});

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_aed_t_wtlists {
    my %metadata = (
        name            =>  'Evolutionary distinctiveness per terminal taxon per site',
        description     =>  'Site level evolutionary distinctiveness per terminal taxon',
        type            =>  'Phylogenetic Indices',
        pre_calc        => [qw /_calc_phylo_aed_t/],
        uses_nbr_lists  =>  1,
        reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
        indices         => {
            PHYLO_AED_T_WTLIST => {
                description  => 'Abundance weighted ED per terminal taxon '
                              . '(the AED score of each taxon multiplied by its '
                              . 'abundance in the sample)',
                reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
                type         => 'list',
            },
            PHYLO_AED_T_WTLIST_P => {
                description  => 'Proportional contribution of each terminal taxon to the AED_T score',
                reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
                type         => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_aed_t_wtlists {
    my $self = shift;
    my %args = @_;

    my $wt_list   = $args{PHYLO_AED_T_WTLIST};
    my $aed_t     = $args{PHYLO_AED_T};
    my $p_wt_list = {};

    foreach my $label (keys %$wt_list) {
        $p_wt_list->{$label} = $wt_list->{$label} / $aed_t;
    }

    my %results = (
        PHYLO_AED_T_WTLIST   => $wt_list,
        PHYLO_AED_T_WTLIST_P => $p_wt_list,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_phylo_aed_t {
    my %metadata = (
        name            => '_calc_phylo_aed_t',
        description     => 'Inner sub for AED_T calcs',
        pre_calc        => [qw /calc_abc3 calc_phylo_aed/],
        uses_nbr_lists  =>  1,
    );

    return $metadata_class->new(\%metadata);
}

sub _calc_phylo_aed_t {
    my $self = shift;
    my %args = @_;

    my $aed_hash   = $args{PHYLO_AED_LIST};
    my $label_hash = $args{label_hash_all};
    my $aed_t;
    my %scores;

  LABEL:
    foreach my $label (keys %$label_hash) {
        my $abundance = $label_hash->{$label};

        next LABEL if !exists $aed_hash->{$label};

        my $aed_score = $aed_hash->{$label};
        my $weight    = $abundance * $aed_score;

        $scores{$label} = $weight;
        $aed_t += $weight;
    }

    my %results = (
        PHYLO_AED_T        => $aed_t,
        PHYLO_AED_T_WTLIST => \%scores,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_phylo_aed {
    my $descr = "Evolutionary distinctiveness metrics (AED, ED, ES)\n"
                . 'Label values are constant for all '
                . 'neighbourhoods in which each label is found. ';

    my %metadata = (
        name            =>  'Evolutionary distinctiveness',
        description     =>  $descr,
        type            =>  'Phylogenetic Indices',
        pre_calc        => [qw /calc_abc/],
        pre_calc_global => [qw /get_aed_scores/],
        uses_nbr_lists  =>  1,
        reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
        indices         => {
            PHYLO_AED_LIST => {
                description  =>  'Abundance weighted ED per terminal label',
                type         => 'list',
                reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
            },
            PHYLO_ES_LIST => {
                description  =>  'Equal splits partitioning of PD per terminal label',
                type         => 'list',
                reference    => 'Redding & Mooers (2006) https://doi.org/10.1111%2Fj.1523-1739.2006.00555.x',
            },
            PHYLO_ED_LIST => {
                description  =>  q{"Fair proportion" partitioning of PD per terminal label},
                type         => 'list',
                reference    => 'Isaac et al. (2007) https://doi.org/10.1371/journal.pone.0000296',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}


sub calc_phylo_aed {
    my $self = shift;
    my %args = @_;

    my $label_hash = $args{label_hash_all};
    my $es_wts     = $args{ES_SCORES};
    my $ed_wts     = $args{ED_SCORES};
    my $aed_wts    = $args{AED_SCORES};

    my (%es, %ed, %aed);
    # now loop over the terminals and extract the weights (would slices be faster?)
    # Do we want the proportional values?  Divide by PD to get them.
  LABEL:
    foreach my $label (keys %$label_hash) {
        next LABEL if !exists $aed_wts->{$label};
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

sub get_metadata_get_aed_scores {

    my %metadata = (
        name            => 'get_aed_scores',
        description     => 'A hash of the ES, ED and BED scores for each label',
        pre_calc        => [qw /calc_abc/],
        pre_calc_global => [
            qw /get_trimmed_tree
                get_global_node_abundance_hash
                get_global_node_terminal_count_cache
              /],
        indices         => {
            ES_SCORES => {
                description => 'Hash of ES scores for each label'
            },
            ED_SCORES => {
                description => 'Hash of ED scores for each label'
            },
            AED_SCORES => {
                description => 'Hash of AED scores for each label'
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_aed_scores {
    my $self = shift;
    my %args = @_;

    my $tree = $args{trimmed_tree};
    my $node_abundances = $args{global_node_abundance_hash};
    my $terminal_count_cache = $args{global_node_terminal_count_cache};
    my (%es_wts, %ed_wts, %aed_wts);
    my $terminal_elements = $tree->get_root_node->get_terminal_elements;

    LABEL:
    foreach my $label (keys %$terminal_elements) {

        #  check if node exists - should use a pre_calc
        my $node_ref = eval {
            $tree->get_node_ref (node => $label);
        };
        if (my $e = $EVAL_ERROR) {  #  still needed? 
            next LABEL if Biodiverse::Tree::NotExistsNode->caught;
            croak $e;
        }

        my $length  = $node_ref->get_length;
        my $es_sum  = $length;
        my $ed_sum  = $length;
        my $aed_sum = eval {$length / $node_abundances->{$label}};
        my $es_wt  = 1;
        my ($ed_wt, $aed_wt);
        #my $aed_label_count = $node_abundances->{$label};

      TRAVERSE_TO_ROOT:
        while ($node_ref = $node_ref->get_parent) {
            my $node_len = $node_ref->get_length;
            my $name     = $node_ref->get_name;

            $es_wt  /= $node_ref->get_child_count;  #  es uses a cumulative scheme
            $ed_wt  =  1 / ($terminal_count_cache->{$name}
                            //= $node_ref->get_terminal_element_count
                            );
            $aed_wt =  1 / $node_abundances->{$name};

            $es_sum  += $node_len * $es_wt;
            $ed_sum  += $node_len * $ed_wt;
            $aed_sum += $node_len * $aed_wt;
        }

        $es_wts{$label}  = $es_sum;
        $ed_wts{$label}  = $ed_sum;
        $aed_wts{$label} = $aed_sum;
    }

    my %results = (
        ES_SCORES  => \%es_wts,
        ED_SCORES  => \%ed_wts,
        AED_SCORES => \%aed_wts,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_tree_node_length_hash {
    my %metadata = (
        name            => 'get_tree_node_length_hash',
        description     => 'A hash of the node lengths, indexed by node name',
        required_args   => qw /tree_ref/,
        indices         => {
            TREE_NODE_LENGTH_HASH => {
                description => 'Hash of node lengths, indexed by node name',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}


sub get_tree_node_length_hash {
    my $self = shift;
    my %args = @_;
    
    my $tree_ref = $args{tree_ref} // croak 'Missing tree_ref arg';
    my $node_hash = $tree_ref->get_node_hash;
    
    my %len_hash;
    foreach my $node_name (keys %$node_hash) {
        my $node_ref = $node_hash->{$node_name};
        my $length   = $node_ref->get_length;
        $len_hash{$node_name} = $length;
    }
    
    my %results = (TREE_NODE_LENGTH_HASH => \%len_hash);

    return wantarray ? %results : \%results;
}



sub get_metadata_calc_phylo_abundance {

    my %metadata = (
        description     => 'Phylogenetic abundance based on branch '
                           . "lengths back to the root of the tree.\n"
                           . 'Uses labels in both neighbourhoods.',
        name            => 'Phylogenetic Abundance',
        type            => 'Phylogenetic Indices',
        pre_calc        => [qw /_calc_pd calc_abc3 calc_labels_on_tree/],
        pre_calc_global => [qw /get_trimmed_tree get_global_node_abundance_hash/],
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            PHYLO_ABUNDANCE   => {
                cluster       => undef,
                description   => 'Phylogenetic abundance',
                reference     => '',
                formula       => [
                    '= \sum_{c \in C} A \times L_c',
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
                    ', and ',
                    'A',
                    ' is the abundance of that branch (the sum of its descendant label abundances).'
                ],
            },
            PHYLO_ABUNDANCE_BRANCH_HASH => {
                cluster       => undef,
                description   => 'Phylogenetic abundance per branch',
                reference     => '',
                type => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_abundance {
    my $self = shift;
    my %args = @_;
    
    my $named_labels   = $args{PHYLO_LABELS_ON_TREE};
    my $abundance_hash = $args{label_hash_all};
    my $tree           = $args{trimmed_tree};

    my %pd_abundance_hash;
    my $pd_abundance;

    LABEL:
    foreach my $label (keys %$named_labels) {

        #  check if node exists - should use a pre_calc
        my $node_ref = eval {
            $tree->get_node_ref (node => $label);
        };
        if (my $e = $EVAL_ERROR) {  #  still needed? 
            next LABEL if Biodiverse::Tree::NotExistsNode->caught;
            croak $e;
        }

        my $abundance    = $abundance_hash->{$label};
        my $path_lengths = $node_ref->get_path_lengths_to_root_node;
        
        foreach my $node_name (keys %$path_lengths) {
            my $node_len   = $path_lengths->{$node_name};
            $pd_abundance_hash{$node_name} += $node_len * $abundance;
            $pd_abundance += $node_len * $abundance;
        }
    }    

    my %results = (
        PHYLO_ABUNDANCE => $pd_abundance,
        PHYLO_ABUNDANCE_BRANCH_HASH => \%pd_abundance_hash,
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

See L<http://purl.org/biodiverse/wiki/Indices> for more details.

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
