package Biodiverse::Indices::RWTurnover;
use strict;
use warnings;
use autovivification;

use 5.022;
use feature 'refaliasing';
no warnings 'experimental::refaliasing';

use Carp;

our $VERSION = '2.99_001';

my $metadata_class = 'Biodiverse::Metadata::Indices';

sub get_metadata_calc_rw_turnover {

    my %metadata = (
        description     => 'Range weighted Sorenson',
        name            => 'Range weighted Sorenson',
        reference       => 'TBA',
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
    my ($a, $b, $c) = (0, 0, 0);

    foreach my $label (keys %$weights) {
        my $wt = $weights->{$label};
        if (exists $label_hash1->{$label}) {
            if (exists $label_hash2->{$label}) {
                $a += $wt;
            }
            else {
                $b += $wt;
            }
        }
        elsif (exists $label_hash2->{$label}) {
            $c += $wt;
        }
    }

    my $dissim_is_valid = ($a || $b) && ($a || $c);
    my $rw_turnover = eval {$dissim_is_valid ? 1 - ($a / ($a + $b + $c)) : undef};

    #my $bd = $self->get_basedata_ref;
    #my $gamma_diversity = $bd->get_label_count;

    my %results = (
        RW_TURNOVER_A => $a,
        RW_TURNOVER_B => $b,
        RW_TURNOVER_C => $c,
        RW_TURNOVER   => $rw_turnover,
        #RW_TURNOVER_P => $rw_turnover / $gamma_diversity,
    );

    return wantarray ? %results : \%results;    
}


sub get_metadata_calc_phylo_rw_turnover {

    my %metadata = (
        description     => 'Phylo Range weighted Turnover',
        name            => 'Phylo Range weighted Turnover',
        reference       => 'TBA',
        type            => 'Phylogenetic Turnover',
        pre_calc        => [qw /calc_pe_lists calc_abc/],
        pre_calc_global => [qw /
            get_node_range_hash_as_lists
            get_trimmed_tree_parent_name_hash
        /],
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

    my @el_list1 = keys %{$args{element_list1}};
    my @el_list2 = keys %{$args{element_list2}};

    \my %node_ranges = $args{node_range_hash};
    \my %weights     = $args{PE_WTLIST};
    \my %parent_name_hash = $args{TRIMMED_TREE_PARENT_NAME_HASH};

    my ($a, $b, $c) = (0, 0, 0);    
    my %done;

    NODE:
    foreach my $node (keys %weights) {

        next NODE if exists $done{$node};

        my $wt = $weights{$node};

        \my %range_hash = $node_ranges{$node};

        #  Which neighbour sets does our node have terminals in?
        #  This is the "slow" bit of this sub...
        #  List::Util::any() takes twice as long as foreach
        my ($in_set1, $in_set2);
        foreach my $el (@el_list1) {
            last if $in_set1 = exists $range_hash{$el};
        }
        foreach my $el (@el_list2) {
            last if $in_set2 = exists $range_hash{$el};
        }

        if ($in_set1) {
            if ($in_set2) {  #  we are in both nbr sets, therefore so are our ancestors
                $a += $wt;
                $done{$node}++;
                my $pnode = $node;  #  initial parent node key
                while ($pnode = $parent_name_hash{$pnode}) {
                    last if exists $done{$pnode};
                    $a += $weights{$pnode};  #  should perhaps add "// last" to allow for subsets which don't go all the way?
                    $done{$pnode}++;
                }
            }
            else {
                $b += $wt;
                $done{$node}++;
            }
        }
        elsif ($in_set2) {
            $c += $wt;
            $done{$node}++;
        }
    }

    my $dissim_is_valid = ($a || $b) && ($a || $c);

    my %results = (
        PHYLO_RW_TURNOVER_A => $a,
        PHYLO_RW_TURNOVER_B => $b,
        PHYLO_RW_TURNOVER_C => $c,
        PHYLO_RW_TURNOVER   => eval {$dissim_is_valid ? 1 - ($a / ($a + $b + $c)) : undef},
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


1;
