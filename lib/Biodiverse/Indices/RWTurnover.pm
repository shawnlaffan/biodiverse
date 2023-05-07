package Biodiverse::Indices::RWTurnover;
use strict;
use warnings;
#use autovivification;

use 5.022;
use feature 'refaliasing';
no warnings 'experimental::refaliasing';

use Carp;

our $VERSION = '4.3';

my $metadata_class = 'Biodiverse::Metadata::Indices';

sub get_metadata_calc_rw_turnover {

    my %metadata = (
        description     => 'Range weighted Sorenson',
        name            => 'Range weighted Sorenson',
        reference       => 'Laffan et al. (2016) https://doi.org/10.1111/2041-210X.12513',
        type            => 'Taxonomic Dissimilarity and Comparison',
        pre_calc        => [qw /calc_endemism_whole_lists calc_abc/],
        uses_nbr_lists  => 2,  #  how many lists it must have
        indices         => {
            RW_TURNOVER   => {
                description => 'Range weighted turnover',
                cluster     => 'NO_CACHE_ABC',
            },
            RW_TURNOVER_A => {
                description => 'Range weighted turnover, shared component',
            },
            RW_TURNOVER_B => {
                description => 'Range weighted turnover, component found only in nbr set 1',
            },
            RW_TURNOVER_C => {
                description => 'Range weighted turnover, component found only in nbr set 2',
            },
            #RW_TURNOVER_P => {
            #    description => 'Range weighted turnover divided by the total number of species in the basedata',
            #    cluster     => 'NO_CACHE_ABC',
            #}
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_rw_turnover {
    my $self = shift;
    my %args = @_;

    my $label_hash1    = $args{label_hash1};
    my $label_hash2    = $args{label_hash2};

    my $weights     = $args{ENDW_WTLIST};
    my ($aa, $bb, $cc) = (0, 0, 0);

    foreach my $label (keys %$weights) {
        my $wt = $weights->{$label};
        if (exists $label_hash1->{$label}) {
            if (exists $label_hash2->{$label}) {
                $aa += $wt;
            }
            else {
                $bb += $wt;
            }
        }
        elsif (exists $label_hash2->{$label}) {
            $cc += $wt;
        }
    }

    my $dissim_is_valid = ($aa || $bb) && ($aa || $cc);
    my $rw_turnover = eval {$dissim_is_valid ? 1 - ($aa / ($aa + $bb + $cc)) : undef};

    #my $bd = $self->get_basedata_ref;
    #my $gamma_diversity = $bd->get_label_count;

    my %results = (
        RW_TURNOVER_A => $aa,
        RW_TURNOVER_B => $bb,
        RW_TURNOVER_C => $cc,
        RW_TURNOVER   => $rw_turnover,
        #RW_TURNOVER_P => $rw_turnover / $gamma_diversity,
    );

    return wantarray ? %results : \%results;    
}


sub get_metadata_calc_phylo_rw_turnover {

    my %metadata = (
        description     => 'Phylo Range weighted Turnover',
        name            => 'Phylo Range weighted Turnover',
        reference       => 'Laffan et al. (2016) https://doi.org/10.1111/2041-210X.12513',
        type            => 'Phylogenetic Turnover',
        pre_calc        => [qw /_calc_pe_lists_per_element_set/],
        # pre_calc_global => [qw /
        #     get_node_range_hash_as_lists
        #     get_trimmed_tree_parent_name_hash
        # /],
        #    get_trimmed_tree_child_name_hash
        #/],
        uses_nbr_lists  => 2,  #  how many lists it must have
        indices         => {
            PHYLO_RW_TURNOVER   => {
                description => 'Range weighted turnover',
                cluster     => 'NO_CACHE_ABC',
            },
            PHYLO_RW_TURNOVER_A => {
                description => 'Range weighted turnover, shared component',
            },
            PHYLO_RW_TURNOVER_B => {
                description => 'Range weighted turnover, component found only in nbr set 1',
            },
            PHYLO_RW_TURNOVER_C => {
                description => 'Range weighted turnover, component found only in nbr set 2',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_rw_turnover {
    my $self = shift;
    my %args = @_;

    # my @el_list1 = keys %{$args{element_list1}};
    # my @el_list2 = keys %{$args{element_list2}};

    # my $pairwise_mode
    #   = $self->get_pairwise_mode
    #   || (@el_list1 == 1 && @el_list2 == 1);

    # \my %node_ranges = $args{node_range_hash};
    # \my %weights     = $args{PE_WTLIST};
    # \my %parent_name_hash = $args{TRIMMED_TREE_PARENT_NAME_HASH};

    # my ($aa, $bb, $cc) = (0, 0, 0);
    # my %done;
    # my $done_marker = \1;  #  squeeze more speed by not creating new SVs
    # #  micro-optimisation to not recreate these each iter
    # #  Care needs to be taken if assignment code below is modified
    # my ($in_set1, $in_set2, $pnode);
    #
    # NODE:
    # foreach my $node (keys %weights) {
    #
    #     next NODE if $done{$node};
    #
    #     \my %range_hash = $node_ranges{$node};
    #
    #     #  Which neighbour sets does our node have terminals in?
    #     #  This is the "slow" bit of this sub...
    #     #  List::Util::any() takes twice as long as foreach
    #     #my ($in_set1, $in_set2);
    #     #  exists test is slower than boolean value, but range hash vals are undef
    #     if ($pairwise_mode) {  #  no loops needed
    #         $in_set1 = exists $range_hash{$el_list1[0]};
    #         $in_set2 = exists $range_hash{$el_list2[0]};
    #     }
    #     else {
    #         foreach my $el (@el_list1) {
    #             last if $in_set1 = exists $range_hash{$el};
    #         }
    #         foreach my $el (@el_list2) {
    #             last if $in_set2 = exists $range_hash{$el};
    #         }
    #     }
    #
    #     $done{$node} = $done_marker;  # set it once here instead of in each condition
    #     if ($in_set1) {
    #         if ($in_set2) {  #  we are in both nbr sets, therefore so are our ancestors
    #             $aa += $weights{$node};
    #             $pnode = $node;  #  initial parent node key
    #             while ($pnode = $parent_name_hash{$pnode}) {
    #                 last if $done{$pnode};
    #                 $aa += $weights{$pnode};  #  should perhaps add "// last" to allow for subsets which don't go all the way?
    #                 $done{$pnode} = $done_marker;
    #             }
    #         }
    #         else {
    #             $bb += $weights{$node};
    #         }
    #     }
    #     elsif ($in_set2) {
    #         $cc += $weights{$node};
    #     }
    # }

    \my %list1 = $args{PE_WTLIST_PER_ELEMENT_SET1};
    \my %list2 = $args{PE_WTLIST_PER_ELEMENT_SET2};
    my ($aa, $bb, $cc) = (0, 0, 0);
    foreach my $key (keys %list1) {
        exists $list2{$key}
            ? ($aa += ($list1{$key} + $list2{$key}))
            : ($bb += $list1{$key});
    }
    #  postfix for speed
    $cc += $list2{$_}
      foreach grep {!exists $list1{$_}} keys %list2;

    # my $dissim_is_valid = ($aa || $bb) && ($aa || $cc);

    my %results = (
        PHYLO_RW_TURNOVER_A => $aa,
        PHYLO_RW_TURNOVER_B => $bb,
        PHYLO_RW_TURNOVER_C => $cc,
        PHYLO_RW_TURNOVER   => eval {
            ($aa || $bb) && ($aa || $cc)  #  avoid divide by zero
            ? 1 - ($aa / ($aa + $bb + $cc))
            : undef
        },
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_get_trimmed_tree_parent_name_hash {
    my $self = shift;
    
    my %metadata = (
        name            => 'get_trimmed_tree_parent_name_hash',
        description     => q{Get a hash where the values are the name of a node's parent},
        pre_calc_global => [qw /get_trimmed_tree/],
        indices => {
            TRIMMED_TREE_PARENT_NAME_HASH => {
                description => 'hash of the parent node names, indexed by node name',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_trimmed_tree_parent_name_hash {
    my $self = shift;
    my %args = @_;
    
    my $tree = $args{trimmed_tree};
    
    my $node_hash = $tree->get_node_hash;
    
    my %parent_name_hash;
    while (my ($name, $ref) = each %$node_hash) {
        my $parent = $ref->get_parent;
        my $parent_name = $parent ? $parent->get_name : undef;
        $parent_name_hash{$name} = $parent_name;
    }

    my %results = (
        TRIMMED_TREE_PARENT_NAME_HASH => \%parent_name_hash,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_trimmed_tree_child_name_hash {
    my $self = shift;
    
    my %metadata = (
        name            => 'get_trimmed_tree_child_name_hash',
        description     => q{Get a hash where the values are arrays of the names of each node's children},
        pre_calc_global => [qw /get_trimmed_tree/],
        indices => {
            TRIMMED_TREE_CHILD_NAME_HASH => {
                description => 'hash of the descendant node names, indexed by node name',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_trimmed_tree_child_name_hash {
    my $self = shift;
    my %args = @_;

    my $tree = $args{trimmed_tree};

    my $node_hash = $tree->get_node_hash;

    my %name_hash;
    while (my ($name, $ref) = each %$node_hash) {
        my @names;
        foreach my $child ($ref->get_children) {    
            push @names, $child->get_name;
        }
        $name_hash{$name} = scalar @names ? \@names : undef;
    }

    my %results = (
        TRIMMED_TREE_CHILD_NAME_HASH => \%name_hash,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_pe_lists_per_element_set {

    my %metadata = (
        description     => 'Phylogenetic endemism (PE) base calcs per element set.',
        name            => 'Phylogenetic Endemism base calcs per element set',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Endemism Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc_global => [ qw /
            get_node_range_hash
            get_trimmed_tree
            get_pe_element_cache
            get_path_length_cache
            set_path_length_cache_by_group_flag
            get_inverse_range_weighted_path_lengths
        /],
        pre_calc        => ['calc_abc'],  #  don't need calc_abc2 as we don't use its counts
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => {'tree_ref' => 1},
    );

    return $metadata_class->new(\%metadata);
}

sub _calc_pe_lists_per_element_set {
    my ($self, %args) = @_;

    my $results1
        = $args{element_list1}
        ? $self->_calc_pe(%args, element_list_all => [keys %{$args{element_list1}}])
        : {};
    my $results2
        = $args{element_list2}
        ? $self->_calc_pe(%args, element_list_all => [keys %{$args{element_list2}}])
        : {};

    my %results;
    foreach my $key (keys %$results1) {
        $results{"${key}_PER_ELEMENT_SET1"} = $results1->{$key};
        next if !$args{element_list2};
        $results{"${key}_PER_ELEMENT_SET2"} = $results2->{$key};
    };
    return wantarray ? %results : \%results;
}


1;
