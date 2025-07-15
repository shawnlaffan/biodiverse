package Biodiverse::Indices::PhylogeneticRelative;
use 5.022;
use strict;
use warnings;

use experimental qw/refaliasing for_list/;

use English qw /-no_match_vars/;

use List::Util qw /sum first/;

use constant HAVE_BD_UTILS => eval 'require Biodiverse::Utils';

use parent qw /Biodiverse::Indices::PhylogeneticRelative::RefAlias/;

use Carp;

our $VERSION = '4.99_007';

my $metadata_class = 'Biodiverse::Metadata::Indices';

sub get_metadata_calc_phylo_rpd1 {

    my %metadata = (
        description     => 'Relative Phylogenetic Diversity type 1 (RPD1).  '
                         . "The ratio of the tree's PD to a null model of "
                         . 'PD evenly distributed across terminals and where '
                         . 'ancestral nodes are collapsed to zero length.'
                         . 'You probably want to use RPD2 instead as it uses '
                         . "the tree's topology.",
        name            => 'Relative Phylogenetic Diversity, type 1',
        type            => 'Phylogenetic Indices (relative)',
        pre_calc        => [qw /calc_pd calc_labels_on_tree/],
        required_args   => ['tree_ref'],
        uses_nbr_lists  => 1,
        indices         => {
            PHYLO_RPD1      => {
                description => 'RPD1',
                distribution => 'nonnegative_ratio',
            },
            PHYLO_RPD_NULL1 => {
                description => 'Null model score used as the denominator in the RPD1 calculations',
            },
            PHYLO_RPD_DIFF1 => {
                description => 'How much more or less PD is there than expected, in original tree units.',
                formula     => ['= tree\_length \times (PD\_P - PHYLO\_RPD\_NULL1)'],
                distribution => 'divergent',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_rpd1 {
    my $self = shift;
    my %args = @_;

    my $tree = $args{tree_ref};
    my $total_tree_length = $tree->get_total_tree_length;

    my $pd_p_score = $args{PD_P};
    my $label_hash = $args{PHYLO_LABELS_ON_TREE};
    my $richness   = scalar keys %$label_hash;

    my %results;
    {
        no warnings qw /numeric uninitialized/;

        #  Null is the number of terminals in the sample divided
        #  by the number of terminals on the tree, since the null
        #  is a rake/star tree with no internals
        my $n    = $tree->get_terminal_element_count;  #  should this be a pre_calc_global?  The value is cached, though.
        my $null = eval {$richness / $n};
        my $phylo_rpd1 = eval {$pd_p_score / $null};

        $results{PHYLO_RPD1}      = $phylo_rpd1;
        $results{PHYLO_RPD_NULL1} = $null;
        $results{PHYLO_RPD_DIFF1} = $total_tree_length * ($pd_p_score - $null);
    }

    return wantarray ? %results : \%results;
}



sub get_metadata_calc_phylo_rpe1 {

    my %metadata = (
        description     => 'Relative Phylogenetic Endemism, type 1 (RPE1).  '
                         . "The ratio of the tree's PE to a null model of "
                         . 'PD evenly distributed across terminals, '
                         . 'but with the same range per terminal and where '
                         . 'ancestral nodes are of zero length (as per RPD1).'
                         . 'You probably want to use RPE2 instead as it uses '
                         . "the tree's topology.",
        name            => 'Relative Phylogenetic Endemism, type 1',
        type            => 'Phylogenetic Indices (relative)',
        pre_calc        => [qw /calc_pe calc_endemism_whole_lists calc_labels_on_trimmed_tree/],
        pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => {
            PHYLO_RPE1           => {
                description => 'Relative Phylogenetic Endemism score',
                distribution => 'nonnegative_ratio',
            },
            PHYLO_RPE_NULL1        => {
                description => 'Null score used as the denominator in the RPE calculations',
            },
            PHYLO_RPE_DIFF1 => {
                description => 'How much more or less PE is there than expected, in original tree units.',
                formula     => ['= tree\_length \times (PE\_WE\_P - PHYLO\_RPE\_NULL1)'],
                distribution => 'divergent',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_rpe1 {
    my $self = shift;
    my %args = @_;

    my $tree = $args{trimmed_tree};
    my $total_tree_length = $tree->get_total_tree_length;

    my $pe_p_score = $args{PE_WE_P};
    my $pe_score   = $args{PE_WE};

    my $we = $self->_calc_phylo_rpe1_inner (
        ENDW_WTLIST => $args{ENDW_WTLIST},
        PHYLO_LABELS_ON_TRIMMED_TREE => $args{PHYLO_LABELS_ON_TRIMMED_TREE},
    );

    my %results;
    {
        no warnings qw /numeric uninitialized/;

        #  should this be a pre_calc_global?  The value is cached, though.
        my $n = $tree->get_terminal_element_count;

        my $null       = eval {$we / $n};
        my $phylo_rpe1 = eval {$pe_p_score / $null};

        $results{PHYLO_RPE1}      = $phylo_rpe1;
        $results{PHYLO_RPE_NULL1} = $null;
        $results{PHYLO_RPE_DIFF1} = $total_tree_length * ($pe_p_score - $null);
    }

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_rpd2 {

    my %metadata = (
        description     => 'Relative Phylogenetic Diversity (RPD), type 2.  '
                         . 'The ratio of the tree\'s PD to a null model of '
                         . 'PD evenly distributed across all nodes '
                         . '(all branches are of equal length).',
        name            => 'Relative Phylogenetic Diversity, type 2',
        reference       => 'Mishler et al. (2014) https://doi.org/10.1038/ncomms5473',
        type            => 'Phylogenetic Indices (relative)',
        pre_calc        => [qw /calc_pd calc_pd_node_list/],
        pre_calc_global => [qw/
            get_tree_with_equalised_branch_lengths
            get_tree_zero_length_branch_count
        /],
        required_args   => ['tree_ref'],
        uses_nbr_lists  => 1,
        indices         => {
            PHYLO_RPD2      => {
                description => 'RPD2',
                distribution => 'nonnegative_ratio',
            },
            PHYLO_RPD_NULL2 => {
                description => 'Null model score used as the denominator in the RPD2 calculations',
            },
            PHYLO_RPD_DIFF2 => {
                description => 'How much more or less PD is there than expected, in original tree units.',
                formula     => ['= tree\_length \times (PD\_P - PHYLO\_RPD\_NULL2)'],
                distribution => 'divergent',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_rpd2 {
    my $self = shift;
    my %args = @_;

    my $orig_tree_ref = $args{tree_ref};
    my $orig_total_tree_length = $orig_tree_ref->get_total_tree_length;
    my $null_tree_ref = $args{TREE_REF_EQUALISED_BRANCHES};
    my $null_total_tree_length = $null_tree_ref->get_total_tree_length;

    my $pd_p_score     = $args{PD_P};
    my $pd_score       = $args{PD};
    my $included_nodes = $args{PD_INCLUDED_NODE_LIST};  #  stores branch lengths

    #  Allow for zero length nodes, as we keep them as zero.
    #  The grep in scalar context is a fast way of counting the number of non-zero branches.
    #  %$included_nodes is for the original tree
    my $pd_score_eq_branch_lengths;
    if ($args{TREE_ZERO_LENGTH_BRANCH_COUNT}) {
        $pd_score_eq_branch_lengths = grep $_, values %$included_nodes;
    }
    else {
        $pd_score_eq_branch_lengths = scalar keys %$included_nodes;
    }

    my %results;
    {
        no warnings qw /numeric uninitialized/;

        my $null = eval {$pd_score_eq_branch_lengths / $null_total_tree_length};
        my $phylo_rpd2 = eval {$pd_p_score / $null};

        $results{PHYLO_RPD2}      = $phylo_rpd2;
        $results{PHYLO_RPD_NULL2} = $null;
        $results{PHYLO_RPD_DIFF2} = eval {$orig_total_tree_length * ($pd_p_score - $null)};
    }

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_rpe_central {

    my %metadata = (
        description     => 'Relative Phylogenetic Endemism (RPE).  '
                         . 'The ratio of the tree\'s PE to a null model where '
                         . 'PE is calculated using a tree where all branches '
                         . 'are of equal length.  '
                         . 'Same as RPE2 except it only uses the branches in the '
                         . 'first neighbour set when more than one is set.',
        name            => 'Relative Phylogenetic Endemism, central',
        reference       => 'Mishler et al. (2014) https://doi.org/10.1038/ncomms5473',
        type            => 'Phylogenetic Indices (relative)',
        pre_calc        => [qw /calc_pe_central calc_pe_central_lists calc_elements_used _calc_abc_any/],
        pre_calc_global => [qw /
            get_trimmed_tree
            get_trimmed_tree_with_equalised_branch_lengths
            get_trimmed_tree_eq_branch_lengths_node_length_hash
            get_trimmed_tree_range_inverse_hash_nonzero_len
            get_pe_element_cache
            get_rpe_element_cache
        /],
        uses_nbr_lists  => 1,
        indices         => {
            PHYLO_RPEC       => {
                description => 'Relative Phylogenetic Endemism score, central',
                distribution => 'nonnegative_ratio',
            },
            PHYLO_RPE_NULLC  => {
                description => 'Null score used as the denominator in the PHYLO_RPEC calculations',
            },
            PHYLO_RPE_DIFFC  => {
                description => 'How much more or less PE is there than expected, in original tree units.',
                formula     => ['= tree\_length \times (PE\_WEC\_P - PHYLO\_RPE\_NULLC)'],
                distribution => 'divergent',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_rpe_central {
    my $self = shift;
    my %args = @_;

    if (!@{$args{element_list2} // []} || !($args{C} // 1)) {
        #  We just copy the calc_phylo_rpe2 results
        #  if there are no nbrs in set2 or all the
        #  labels are common
        my $cache_hash = $self->get_param('AS_RESULTS_FROM_LOCAL');
        my $results = $cache_hash->{calc_phylo_rpe2}
            // $self->calc_phylo_rpe2(
                %args,
                PE_WE_P            => $args{PEC_WE_P},
                PE_WE              => $args{PEC_WE},
                PE_LOCAL_RANGELIST => $args{PEC_LOCAL_RANGELIST},
            );

        my %results2;
        foreach my $key (keys %$results) {
            #  will need to be changed if we rename the RPE indices
            my $new_key = ($key =~ s/2$/C/r);
            $results2{$new_key} = $results->{$key};
        }

        return wantarray ? %results2 : \%results2;
    }

    my $pe_p_score = $args{PEC_WE_P};

    my $orig_tree_ref = $args{trimmed_tree};
    my $orig_total_tree_length = $orig_tree_ref->get_total_tree_length;

    my $null_tree_ref = $args{TREE_REF_EQUALISED_BRANCHES_TRIMMED};
    my $null_total_tree_length = $null_tree_ref->get_total_tree_length;

    my $default_eq_len = $args{TREE_REF_EQUALISED_BRANCHES_TRIMMED_NODE_LENGTH};
    \my %range_inverse = $args{trimmed_tree_range_inverse_hash_nonzero_len};

    #  Get the PE score assuming equal branch lengths
    my ($pe_null, $null, $phylo_rpe2, $diff);

    #  need to work over the lists
    \my %node_ranges_local  = $args{PEC_LOCAL_RANGELIST};

    #  First condition optimises for the common case where all local ranges are 1
    if (($args{EL_COUNT_ALL} // $args{EL_COUNT_SET1} // 0) == 1) {
        $pe_null += $_ foreach @range_inverse{keys %node_ranges_local};
    }
    else {
        #  postfix for speed
        $pe_null
            += $range_inverse{$_}
            * $node_ranges_local{$_}
            foreach keys %node_ranges_local;
    }
    $pe_null *= $default_eq_len if $pe_null;

    {
        no warnings qw /numeric uninitialized/;
        #  null is equiv to PE_WE_P for the equalised tree
        $null       = eval {$pe_null / $null_total_tree_length};
        $phylo_rpe2 = eval {$pe_p_score / $null};
        $diff       = eval {$orig_total_tree_length * ($pe_p_score - $null)};
    }

    my $results = {
        PHYLO_RPEC      => $phylo_rpe2,
        PHYLO_RPE_NULLC => $null,
        PHYLO_RPE_DIFFC => $diff,
    };

    return wantarray ? %$results : $results;
}


sub get_metadata_calc_phylo_rpe2 {

    my %metadata = (
        description     => 'Relative Phylogenetic Endemism (RPE).  '
                         . 'The ratio of the tree\'s PE to a null model where '
                         . 'PE is calculated using a tree where all non-zero branches '
                         . 'are of equal length.',
        name            => 'Relative Phylogenetic Endemism, type 2',
        reference       => 'Mishler et al. (2014) https://doi.org/10.1038/ncomms5473',
        type            => 'Phylogenetic Indices (relative)',
        pre_calc        => [qw /_calc_pe calc_elements_used _calc_abc_any/],
        pre_calc_global => [qw /
            get_trimmed_tree
            get_trimmed_tree_with_equalised_branch_lengths
            get_trimmed_tree_eq_branch_lengths_node_length_hash
            get_trimmed_tree_range_inverse_hash_nonzero_len
            get_pe_element_cache
            get_rpe_element_cache
        /],
        uses_nbr_lists  => 1,
        indices         => {
            PHYLO_RPE2       => {
                description => 'Relative Phylogenetic Endemism score, type 2',
                distribution => 'nonnegative_ratio',
            },
            PHYLO_RPE_NULL2  => {
                description => 'Null score used as the denominator in the RPE2 calculations',
            },
            PHYLO_RPE_DIFF2  => {
                description => 'How much more or less PE is there than expected, in original tree units.',
                formula     => ['= tree\_length \times (PE\_WE\_P - PHYLO\_RPE\_NULL2)'],
                distribution => 'divergent',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_rpe2 {
    my $self = shift;
    my %args = @_;

    my $pe_p_score = $args{PE_WE_P};

    #  no point calculating anything if PE is undef
    if (!defined $pe_p_score) {
        my %results = (
            PHYLO_RPE2      => undef,
            PHYLO_RPE_NULL2 => undef,
            PHYLO_RPE_DIFF2 => undef,
        );
        return wantarray ? %results : \%results;
    }

    if (!@{$args{element_list2} // []} || !($args{C} // 1) ) {
        #  We just copy the calc_phylo_rpe_central results
        #  if there are no nbrs or no different labels in set2
        my $cache_hash = $self->get_param('AS_RESULTS_FROM_LOCAL');
        if (my $cached = $cache_hash->{calc_phylo_rpe_central}) {
            my %results;
            foreach my $key (keys %$cached) {
                #  will need to be changed if we rename the RPE indices
                my $new_key = ($key =~ s/C$/2/r);
                $results{$new_key} = $cached->{$key};
            }
            return wantarray ? %results : \%results;
        }
    }

    my $orig_tree_ref = $args{trimmed_tree};
    my $orig_total_tree_length = $orig_tree_ref->get_total_tree_length;

    my $null_tree_ref = $args{TREE_REF_EQUALISED_BRANCHES_TRIMMED};
    my $null_total_tree_length = $null_tree_ref->get_total_tree_length;

    my $default_eq_len = $args{TREE_REF_EQUALISED_BRANCHES_TRIMMED_NODE_LENGTH};
    \my %range_inverse = $args{trimmed_tree_range_inverse_hash_nonzero_len};

    my $element_list_all = $args{element_list_all};

    #  Get the PE score assuming equal branch lengths
    my ($pe_null, $null, $phylo_rpe2, $diff);

    my $results_cache    = $args{RPE_RESULTS_CACHE};
    my $pe_results_cache = $args{PE_RESULTS_CACHE};

    foreach my $group (@$element_list_all) {
        my $results_this_gp;
        #  use the cached results for a group if present
        if (exists $results_cache->{$group}) {
            $results_this_gp = $results_cache->{$group};
        }
        #  else build them and cache them
        else {
            #  precalcs mean this should exist
            my $pe_cached = $pe_results_cache->{$group}
                // croak "PE cache entry for $group not yet calculated";
            my $nodes_in_path = $pe_cached->{PE_WTLIST};

            my $gp_score;
            $gp_score += $_ foreach @range_inverse{keys %$nodes_in_path};
            $gp_score *= $default_eq_len if $gp_score;

            $results_this_gp = { RPE_WE => $gp_score };

            $results_cache->{$group} = $results_this_gp;
        }

        if (defined $results_this_gp->{RPE_WE}) {
            $pe_null += $results_this_gp->{RPE_WE};
        }

    }

    {
        no warnings qw /numeric uninitialized/;
        #  null is equiv to PE_WE_P for the equalised tree
        $null       = eval {$pe_null / $null_total_tree_length};
        $phylo_rpe2 = eval {$pe_p_score / $null};
        $diff       = eval {$orig_total_tree_length * ($pe_p_score - $null)};
    }
#if (defined $pe_nullx) {
#say STDERR "$pe_null $pe_nullx";
#}
    my %results = (
        PHYLO_RPE2      => $phylo_rpe2,
        PHYLO_RPE_NULL2 => $null,
        PHYLO_RPE_DIFF2 => $diff,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_labels_on_trimmed_tree {
    my $self = shift;

    my %metadata = (
        description     => 'Create a hash of the labels that are on the trimmed tree',
        name            => 'Labels on trimmed tree',
        indices         => {
            PHYLO_LABELS_ON_TRIMMED_TREE => {
                description => 'A hash of labels that are found on the tree after it has been trimmed to match the basedata, across both neighbour sets',
                type        => 'list',
            },  #  should poss also do nbr sets 1 and 2
        },
        type            => 'Phylogenetic Indices (relative)',  #  keeps it clear of the other indices in the GUI
        pre_calc_global => [qw /get_trimmed_tree get_labels_not_on_trimmed_tree/],
        pre_calc        => ['calc_abc'],
        uses_nbr_lists  => 1,  #  how many lists it must have
    );

    return $metadata_class->new(\%metadata);
}

sub calc_labels_on_trimmed_tree {
    my $self = shift;
    my %args = @_;
    
    my %labels = %{$args{label_hash_all}};
    my $not_on_tree = $args{labels_not_on_trimmed_tree};
    delete @labels{keys %$not_on_tree};

    my %results = (PHYLO_LABELS_ON_TRIMMED_TREE => \%labels);
    
    return wantarray ? %results : \%results;
}


sub get_metadata_calc_labels_not_on_trimmed_tree {
    my $self = shift;

    my %metadata = (
        description     => 'Create a hash of the labels that are not on the trimmed tree',
        name            => 'Labels not on trimmed tree',
        indices         => {
            PHYLO_LABELS_NOT_ON_TRIMMED_TREE => {
                description => 'A hash of labels that are not found on the tree after it has been trimmed to the basedata, across both neighbour sets',
                type        => 'list',
            },  #  should poss also do nbr sets 1 and 2
            PHYLO_LABELS_NOT_ON_TRIMMED_TREE_N => {
                description => 'Number of labels not on the trimmed tree',
                
            },
            PHYLO_LABELS_NOT_ON_TRIMMED_TREE_P => {
                description => 'Proportion of labels not on the trimmed tree',
                
            },
        },
        type            => 'Phylogenetic Indices (relative)',  #  keeps it clear of the other indices in the GUI
        pre_calc_global => [qw /get_labels_not_on_trimmed_tree/],
        pre_calc        => ['_calc_abc_any'],
        uses_nbr_lists  => 1,  #  how many lists it must have
    );

    return $metadata_class->new(\%metadata);
}

sub calc_labels_not_on_trimmed_tree {
    my $self = shift;
    my %args = @_;

    my $not_on_tree = $args{labels_not_on_trimmed_tree};

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
        PHYLO_LABELS_NOT_ON_TRIMMED_TREE   => \%labels2,
        PHYLO_LABELS_NOT_ON_TRIMMED_TREE_N => $count_not_on_tree,
        PHYLO_LABELS_NOT_ON_TRIMMED_TREE_P => $p_not_on_tree,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_labels_not_on_trimmed_tree {
    my $self = shift;

    my %metadata = (
        name            => 'get_labels_not_on_trimmed_tree',
        description     => 'List of labels not on the trimmed tree',
        pre_calc_global => [qw /get_trimmed_tree/],
        indices => {
            labels_not_on_trimmed_tree => {
                description => 'List of labels not on the trimmed tree',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_labels_not_on_trimmed_tree {
    my $self = shift;
    my %args = @_;                          

    my $bd   = $self->get_basedata_ref;
    my $tree = $args{trimmed_tree};
    
    my $labels = $bd->get_labels;
    
    my @not_in_tree = grep { !$tree->exists_node_name_aa ($_) } @$labels;

    my %hash;
    @hash{@not_in_tree} = (1) x scalar @not_in_tree;

    my %results = (labels_not_on_trimmed_tree => \%hash);

    return wantarray ? %results : \%results;
}

sub get_metadata_get_tree_zero_length_branch_count {
    my $self = shift;

    my %metadata = (
        name            => 'get_tree_zero_length_branch_count',
        description     => 'Flag for if the tree has zero length branches',
        required_args   => ['tree_ref'],
        indices         => {
            TREE_ZERO_LENGTH_BRANCH_COUNT => {
                description => 'Zero length branch flag',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_tree_zero_length_branch_count {
    my $self = shift;
    my %args = @_;
    
    my $tree = $args{tree_ref};
    
    my $count = grep !$_->get_length, $tree->get_node_refs;
    
    my %results = (TREE_ZERO_LENGTH_BRANCH_COUNT => $count);
    
    return wantarray ? %results : \%results;
}

sub get_metadata_get_tree_with_equalised_branch_lengths {
    my $self = shift;

    my %metadata = (
        name            => 'get_tree_with_equalised_branch_lengths',
        description     => 'Get a version of the tree where all non-zero length branches are of length 1',
        required_args   => ['tree_ref'],
        indices         => {
            TREE_REF_EQUALISED_BRANCHES => {
                description => 'Tree with equalised branch lengths',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_tree_with_equalised_branch_lengths {
    my $self = shift;
    my %args = @_;
    
    my $tree_ref = $args{tree_ref} // croak "missing tree_ref argument\n";

    #  should let the sub calculate the length, but everything is set up for 1 or 0 lengths
    my $new_tree = $tree_ref->clone_tree_with_equalised_branch_lengths (node_length => 1);

    my %results = (
        TREE_REF_EQUALISED_BRANCHES => $new_tree,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_trimmed_tree_with_equalised_branch_lengths {
    my $self = shift;

    my %metadata = (
        name            => 'get_trimmed_tree_with_equalised_branch_lengths',
        description     => 'Get a version of the trimmed tree where all non-zero length branches are of length 1',
        pre_calc_global => ['get_trimmed_tree'],
        indices         => {
            TREE_REF_EQUALISED_BRANCHES_TRIMMED => {
                description => 'Trimmed tree with equalised branch lengths',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_trimmed_tree_with_equalised_branch_lengths {
    my $self = shift;
    my %args = @_;

    my $tree_ref = $args{trimmed_tree} // croak "missing trimmed_tree argument\n";

    #  lengths will be non-zero, but not 1
    my $new_tree = $tree_ref->clone_tree_with_equalised_branch_lengths;

    my %results = (
        TREE_REF_EQUALISED_BRANCHES_TRIMMED => $new_tree,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_trimmed_tree_eq_branch_lengths_node_length_hash {
    my %metadata = (
        name            => 'get_tree_node_length_hash_for_trimmed_tree_eq_branch_lengths',
        description     => 'A hash of the trimmed eq branch length tree node lengths, indexed by node name',
        pre_calc_global => qw /get_trimmed_tree_with_equalised_branch_lengths/,
        indices         => {
            TREE_REF_EQUALISED_BRANCHES_TRIMMED_NODE_LENGTH_HASH => {
                description => 'Hash of node lengths for the equalised branch length tree, indexed by node name',
                type        => 'list',
            },
            TREE_REF_EQUALISED_BRANCHES_TRIMMED_NODE_LENGTH => {
                description => 'Default non-zero node length for the equalised branch length tree',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_trimmed_tree_eq_branch_lengths_node_length_hash {
    my $self = shift;
    my %args = @_;
    
    my $tree_ref = $args{TREE_REF_EQUALISED_BRANCHES_TRIMMED}
      // croak 'Missing TREE_REF_EQUALISED_BRANCHES_TRIMMED arg';

    \my %len_hash = $tree_ref->get_node_length_hash;

    my $nonzero_length;

    foreach my $len (values %len_hash) {
        $nonzero_length ||= $len;
        last if $len;
    }
    
    my %results = (
        TREE_REF_EQUALISED_BRANCHES_TRIMMED_NODE_LENGTH_HASH => \%len_hash,
        TREE_REF_EQUALISED_BRANCHES_TRIMMED_NODE_LENGTH      => $nonzero_length,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_trimmed_tree_range_inverse_hash {
    my %metadata = (
        name  => 'get_trimmed_tree_range_inverse_hash',
        description
              => "Get a hash of the node range inverse values\n"
            . "Forms the basis of the RPE calcs for equal area cells",
        pre_calc_global => ['get_node_range_hash'],
        indices => {
            trimmed_tree_range_inverse_hash => {
                description => 'Hash of trimmed tree range inverse values',
            },
        },
    );
    return $metadata_class->new(\%metadata);
}

sub get_trimmed_tree_range_inverse_hash {
    my $self = shift;
    my %args = @_;

    # my $tree = $args{TRIMMED_TREE};
    my $node_ranges = $args{node_range};

    my %range_weighted;

    foreach my ($name, $range) (%$node_ranges) {
        next if !$range;
        $range_weighted{$name} = 1 / $range;
    }

    my %results = (trimmed_tree_range_inverse_hash => \%range_weighted);

    return wantarray ? %results : \%results;
}

sub get_metadata_get_trimmed_tree_range_inverse_hash_nonzero_len {
    my %metadata = (
        name  => 'get_trimmed_tree_range_inverses_nonzero_len',
        description
              => "Get a hash of the node range inverse values for non-zero lengths\n"
            . "Forms the basis of the RPE calcs for equal area cells",
        pre_calc_global => ['get_node_range_hash', 'get_trimmed_tree'],
        indices => {
            trimmed_tree_range_inverse_hash_nonzero_len => {
                description => 'Hash of trimmed tree range inverse values for nodes with non-zero length',
            },
        },
    );
    return $metadata_class->new(\%metadata);
}

sub get_trimmed_tree_range_inverse_hash_nonzero_len {
    my $self = shift;
    my %args = @_;

    my $tree        = $args{trimmed_tree};
    \my %node_ranges = $args{node_range};
    \my %length_hash = $tree->get_node_length_hash;

    my %range_weighted;

    foreach my $name (keys %node_ranges) {
        my $range = $node_ranges{$name} || next;
        $range_weighted{$name} = ($length_hash{$name} ? 1 : 0) / $range;
    }

    my %results = (trimmed_tree_range_inverse_hash_nonzero_len => \%range_weighted);

    return wantarray ? %results : \%results;
}



sub get_metadata_get_rpe_element_cache {

    my %metadata = (
        name        => 'get_rpe_element_cache',
        description => 'Create a hash in which to cache the PE_alt scores for each element',
        indices     => {
            RPE_RESULTS_CACHE => {
                description => 'The hash in which to cache the PE_alt scores for each element'
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

#  create a hash in which to cache the PE scores for each element
#  this is called as a global precalc and then used or modified by each element as needed
sub get_rpe_element_cache {
    my $self = shift;
    my %args = @_;

    my %results = (RPE_RESULTS_CACHE => {});
    return wantarray ? %results : \%results;
}

1;
