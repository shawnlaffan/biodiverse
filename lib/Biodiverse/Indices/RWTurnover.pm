package Biodiverse::Indices::RWTurnover;
use strict;
use warnings;
#use autovivification;

use 5.022;
use feature 'refaliasing';
no warnings 'experimental::refaliasing';

use Carp;
use List::Util qw /sum reduce/;

our $VERSION = '4.99_001';

my $metadata_class = 'Biodiverse::Metadata::Indices';

sub get_metadata_calc_rw_turnover {

    my %metadata = (
        description     => 'Range weighted Sorenson',
        name            => 'Range weighted Sorenson',
        reference       => 'Laffan et al. (2016) https://doi.org/10.1111/2041-210X.12513',
        type            => 'Taxonomic Dissimilarity and Comparison',
        pre_calc        => [qw /calc_endemism_whole_lists calc_abc/],
        uses_nbr_lists  => 2,  #  how many lists it must have
        distribution    => 'nonnegative',  # for A, B and C
        indices         => {
            RW_TURNOVER   => {
                description  => 'Range weighted turnover',
                cluster      => 'NO_CACHE_ABC',
                distribution => 'unit_interval',
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

    \my %list1    = $args{label_hash1};
    \my %list2    = $args{label_hash2};

    \my %weights     = $args{ENDW_WTLIST};
    my ($aa, $bb, $cc) = (0, 0, 0);

    if ($self->get_pairwise_mode) {
        \my %ranges = $args{ENDW_RANGELIST};
        #  very similar to the phyloRW case but we need the values from %weights
        #  or inverse of ranges
        my $cache
            = $self->get_cached_value_dor_set_default_href ('_calc_phylo_rwt_pairwise_branch_sum_cache');
        #  Could use a reduce call to collapse the "sum map {} @list" idiom,
        #  thus avoiding a list generation.  These are only run once per group,
        #  though, so it might not matter.
        my $sum_i = $cache->{(keys %{$args{element_list1}})[0]}  # use postfix deref?
            //= (sum map {1 / $_} @ranges{keys %list1}) // 0;
        my $sum_j = $cache->{(keys %{$args{element_list2}})[0]}
            //= (sum map {1 / $_} @ranges{keys %list2}) // 0;
        #  save some looping, mainly when there are large differences in key counts
        if (keys %list1 <= keys %list2) {
            (exists $list2{$_} and $aa += $weights{$_}) 
              foreach keys %list1;
        }
        else {
            (exists $list1{$_} and $aa += $weights{$_})
              foreach keys %list2;
        }
        $aa ||= 0;  #  avoids precision issues later when $aa is essentially zero
        $bb = $sum_i - $aa / 2;  #  $aa is across both groups so needs to be corrected
        $cc = $sum_j - $aa / 2;
    }
    else {
        foreach my $key (keys %list1) {
            exists $list2{$key}
                ? ($aa += $weights{$key})
                : ($bb += $weights{$key});
        }
        #  postfix for speed
        (!exists $list1{$_} and $cc += $weights{$_})
          foreach keys %list2;
    }

    my $dissim_is_valid = ($aa || $bb) && ($aa || $cc);
    my $rw_turnover = eval {$dissim_is_valid ? 1 - ($aa / ($aa + $bb + $cc)) : undef};

    #my $bd = $self->get_basedata_ref;
    #my $gamma_diversity = $bd->get_label_count;

    my %results = (
        RW_TURNOVER_A => $aa || 0,
        RW_TURNOVER_B => $bb || 0,
        RW_TURNOVER_C => $cc || 0,
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
        pre_calc        => [qw /calc_abc _calc_pe_lists_per_element_set/],
        # pre_calc_global => [qw /
        #     get_node_range_hash_as_lists
        #     get_trimmed_tree_parent_name_hash
        # /],
        #    get_trimmed_tree_child_name_hash
        #/],
        uses_nbr_lists  => 2,  #  how many lists it must have
        distribution    => 'nonnegative',  # for A, B and C
        indices         => {
            PHYLO_RW_TURNOVER   => {
                description  => 'Range weighted turnover',
                cluster      => 'NO_CACHE_ABC',
                distribution => 'unit_interval',
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

    \my %list1 = $args{PE_WTLIST_PER_ELEMENT_SET1};
    \my %list2 = $args{PE_WTLIST_PER_ELEMENT_SET2};
    my ($aa, $bb, $cc) = (0, 0, 0);

    if ($self->get_pairwise_mode) {
        #  we can cache the sums of branch lengths and thus
        #  simplify the calcs as we only need to find $aa
        my $cache
            = $self->get_cached_value_dor_set_default_href ('_calc_phylo_rwt_pairwise_branch_sum_cache');
        my $sum_i = $cache->{(keys %{$args{element_list1}})[0]}  # use postfix deref?
            //= (sum values %list1) // 0;
        my $sum_j = $cache->{(keys %{$args{element_list2}})[0]}
            //= (sum values %list2) // 0;
        #  save some looping, mainly when there are large differences in key counts
        if (keys %list1 <= keys %list2) {
            (exists $list2{$_} and $aa += $list1{$_}) 
              foreach keys %list1;
        }
        else {
            (exists $list1{$_} and $aa += $list2{$_}) 
              foreach keys %list2;
        }
        #  Avoid precision issues later when $aa is
        #  essentially zero given numeric precision
        $aa ||= 0;
        $bb = $sum_i - $aa;
        $cc = $sum_j - $aa;
        $aa *= 2;  #  needs to be double counted now
    }
    else {
        foreach my $key (keys %list1) {
            exists $list2{$key}
                ? ($aa += ($list1{$key} + $list2{$key}))
                : ($bb += $list1{$key});
        }
        #  postfix for speed
        (!exists $list1{$_} and $cc += $list2{$_})
          foreach keys %list2;
        #  Avoid precision issues later when $aa is
        #  essentially zero given numeric precision
        $aa ||= 0;
    }

    #  precision as per $aa above
    $bb ||= 0;
    $cc ||= 0;

    # my $dissim_is_valid = ($aa || $bb) && ($aa || $cc);
    my %results = (
        PHYLO_RW_TURNOVER_A => $aa,
        PHYLO_RW_TURNOVER_B => $bb,
        PHYLO_RW_TURNOVER_C => $cc,
        PHYLO_RW_TURNOVER   => eval {
            ($aa || $bb) && ($aa || $cc)  #  avoid divide by zero
            ? 1 - (($aa / ($aa + $bb + $cc)) || 0)  #  more precision...
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

    #  We use caching to avoid redundant calcs when in pairwise mode.
    #  We check for single element lists to trigger
    #  but maybe we want to only check for pairwise as it is
    #  otherwise wasteful?
    state $cache_name = '_calc_pe_lists_per_element_set';
    my $cache = $self->get_cached_value_dor_set_default_href($cache_name);

    my @results;

    my $i = 0;
  BY_LIST:
    foreach my $list_name (qw /element_list1 element_list2/) {
        $i++;  #  start at 1 so we match the numbered names
        my $el_list = $args{$list_name} // next BY_LIST;
        my @elements = keys %$el_list;
        my $have_cache = (@elements == 1 && $cache->{$elements[0]});
        $results[$i]
            = $have_cache
            ? $cache->{$elements[0]}
            : $self->_calc_pe(
                %args,
                element_list_all => \@elements,
              );
          $cache->{$elements[0]} = $results[$i]
            if @elements == 1;
    }

    my %results;
    foreach my $key (keys %{$results[1]}) {
        $results{"${key}_PER_ELEMENT_SET1"} = $results[1]->{$key} //= {};
        next if !$args{element_list2};
        $results{"${key}_PER_ELEMENT_SET2"} = $results[2]->{$key} //= {};
    };
    return wantarray ? %results : \%results;
}


1;
