package Biodiverse::Indices::PhyloCom;
use strict;
use warnings;
use 5.010;

use Carp;
use Biodiverse::Progress;

use List::Util qw /sum min max/;
use List::MoreUtils qw /any minmax pairwise/;
use Scalar::Util qw /blessed/;
use Sort::Key qw /nkeysort/;
use Math::BigInt ();

use feature 'refaliasing';
no warnings 'experimental::refaliasing';

our $VERSION = '4.0';

use Biodiverse::Matrix::LowMem;
my $mx_class_for_trees = 'Biodiverse::Matrix::LowMem';

use Math::Random::MT::Auto;
my $prng_class = 'Math::Random::MT::Auto';

my $metadata_class = 'Biodiverse::Metadata::Indices';

my $webb_et_al_ref = 'Webb et al. (2008) https://doi.org/10.1093/bioinformatics/btn358';
my $mpd_variance_ref = 'Warwick & Clarke (2001) https://dx.doi.org/10.3354/meps216265';
my $tsir_et_al_ref = 'Tsirogiannis et al. (2012) https://doi.org/10.1007/978-3-642-33122-0_3';

my $nri_nti_expl_text = <<'END_NRI_NTI_EXPL_TEXT'
NRI and NTI for the set of labels
on the tree in the sample. This
version is -1* the Phylocom implementation,
so values >0 have longer branches than expected.
END_NRI_NTI_EXPL_TEXT
  ;

my $nri_formula = ['NRI = \frac{MPD_{obs} - mean(MPD_{rand})}{sd(MPD_{rand})}'];
my $nti_formula = ['NTI = \frac{MNTD_{obs} - mean(MNTD_{rand})}{sd(MNTD_{rand})}'];
my $mpd_mntd_path_formula = [
    'where ',
    'd_{t_i \leftrightarrow t_j} = \sum_{b \in B_{t_i \leftrightarrow t_j}} L_b',
    'is the sum of the branch lengths along the path connecting ',
    't_i',
    'and',
    't_j',
    'such that ',
    'L_b',
    'is the length of each branch in the set of branches',
    'B',    
];
my $mpd_formula = [
    'MPD = \frac {\sum_{t_i = 1}^{n_t-1} \sum_{t_j = 1}^{n_t} d_{t_i \leftrightarrow t_j}}{(n_t-1)^2}, i \neq j',
    @$mpd_mntd_path_formula,
];
my $mntd_formula = [  
    'MNTD = \frac {\sum_{t_i = 1}^{n_t-1} \min_{t_j = 1}^{n_t} d_{t_i \leftrightarrow t_j}}{n_t-1}, i \neq j',
    @$mpd_mntd_path_formula,
];


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
        PNTD_VARIANCE => {
            description    => 'Variance of nearest taxon distances',
        },
        PNTD_MAX => {
            description    => 'Maximum of nearest taxon distances',
        },
        PNTD_MIN => {
            description    => 'Minimum of nearest taxon distances',
        },
        PNTD_RMSD => {
            description    => 'Root mean squared nearest taxon distances',
        },
        PNTD_N => {
            description    => 'Count of nearest taxon distances',
        },
        PMPD_MEAN => {
            description    => 'Mean of pairwise phylogenetic distances',
            formula        => $mpd_formula,
        },
        PMPD_VARIANCE => {
            description    => "Variance of pairwise phylogenetic distances,\n"
                . "similar to Clarke and Warwick (2001; http://dx.doi.org/10.3354/meps216265)"
                . " but uses tip-to-tip distances instead of tip to most recent common ancestor.",
            #formula        => $mpd_variance_formula,
        },
        PMPD_MAX => {
            description    => 'Maximum of pairwise phylogenetic distances',
        },
        PMPD_MIN => {
            description    => 'Minimum of pairwise phylogenetic distances',
        },
        PMPD_RMSD => {
            description    => 'Root mean squared pairwise phylogenetic distances',
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
        reference       => "$webb_et_al_ref\n$mpd_variance_ref",
        pre_calc        => $pre_calc,
        pre_calc_global =>
          [qw /
              get_phylo_mpd_mntd_matrix
              get_phylo_mpd_mntd_cum_path_length_cache
              get_phylo_LCA_matrix
            /],
        required_args   => 'tree_ref',
        uses_nbr_lists  => 1,
        indices         => $indices_filtered,
    );

    return wantarray ? %metadata : \%metadata;
}


sub get_metadata_calc_phylo_mpd_mntd1 {
    my $self = shift;
    my %args = @_;

    my $submeta = $self->get_mpd_mntd_metadata (
        abc_sub => 'calc_abc',
    );

    my %metadata = (
        description     => 'Distance stats from each label to the nearest label '
                         . 'along the tree.  Compares with '
                         . 'all other labels across both neighbour sets. ',
        name            => 'Phylogenetic and Nearest taxon distances, unweighted',
        %$submeta,
    );

    return $metadata_class->new(\%metadata);
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

    my $submeta = $self->get_mpd_mntd_metadata (
        abc_sub => 'calc_abc2',
    );

    my %metadata = (
        description     => 'Distance stats from each label to the nearest label '
                         . 'along the tree.  Compares with '
                         . 'all other labels across both neighbour sets. '
                         . 'Weighted by sample counts',
        name            => 'Phylogenetic and Nearest taxon distances, local range weighted',
        %$submeta,
    );

    return $metadata_class->new(\%metadata);
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

    my $submeta = $self->get_mpd_mntd_metadata (
        abc_sub => 'calc_abc3',
    );

    my %metadata = (
        description     => 'Distance stats from each label to the nearest label '
                         . 'along the tree.  Compares with '
                         . 'all other labels across both neighbour sets. '
                         . 'Weighted by sample counts (which currently must be integers)',
        name            => 'Phylogenetic and Nearest taxon distances, abundance weighted',
        %$submeta,
    );

    return $metadata_class->new(\%metadata);
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

sub default_mpd_mntd_results {
    my $self = shift;
    my %args = @_;

    my $abcnum = $args{abcnum} || 1;
    
    my $mpd_pfx  = 'PMPD' . $abcnum;
    my $mntd_pfx = 'PNTD' . $abcnum;
    my %results;
    foreach my $pfx ($mpd_pfx, $mntd_pfx) {
        $results{$pfx . '_RMSD'}   = undef;
        $results{$pfx . '_N'}    = 0;
        $results{$pfx . '_MIN'}  = undef;
        $results{$pfx . '_MAX'}  = undef;
        #$results{$pfx . '_SUM'}  = undef;
        $results{$pfx . '_MEAN'} = undef;
    };
    
    return wantarray ? %results : \%results;
}

#  mean nearest taxon distance and mean phylogenetic distance
sub _calc_phylo_mpd_mntd {
    my $self = shift;
    my %args = @_;

    my $label_hash1 = $args{label_hash1};
    my $label_hash2 = $args{label_hash2};
    \my %mx         = $args{PHYLO_MPD_MNTD_MATRIX}
      || croak "Argument PHYLO_MPD_MNTD_MATRIX not defined\n";
    my $labels_on_tree = $args{PHYLO_LABELS_ON_TREE};
    my $tree_ref       = $args{tree_ref};
    my $abc_num        = $args{abc_num} || 1;
    my $use_wts        = $abc_num == 1 ? $args{mpd_mntd_use_wts} : 1;
    
    my $return_mean_and_variance_only
      = $args{mpd_mntd_mean_variance_only};
    my $return_means_only  = $args{mpd_mntd_means_only};
    my $nri_nti_generation = $args{nri_nti_generation};  #  changes some behaviour below

    my $label_hashrefs_are_same = $label_hash1 eq $label_hash2;
    
    return $self->default_mpd_mntd_results (@_)
        if $label_hashrefs_are_same
           && scalar keys %$labels_on_tree <= 1;

    #  Are we on the tree and have a non-zero count?
    #  Could be a needless slowdown under permutations using only labels on the tree.
    my @labels1
      = sort
        grep { exists $labels_on_tree->{$_} && $label_hash1->{$_}}
        keys %$label_hash1;
    my @labels2 = $label_hashrefs_are_same
        ? @labels1  #  needs to be a copy as we splice it below
        : sort
          grep { exists $labels_on_tree->{$_} && $label_hash2->{$_} }
          keys %$label_hash2;
    #  allows splicing inside the loop
    my %lb2_indices;
    @lb2_indices{@labels2} = (0..$#labels2);

    my $tree_is_ultrametric = $tree_ref->is_ultrametric;
  
    my (@mpd_path_lengths, @mntd_path_lengths, @mpd_wts, @mntd_wts);


    my $last_shared_ancestor_mx = $args{PHYLO_LCA_MX}
      || croak "Argument PHYLO_LCA_MX not defined";
    my $most_probable_lca_depths
      = $tree_ref->get_most_probable_lca_depths;
        
    #  make the code cleaner below
    my %common_args_for_path_call = (
        tree_ref    => $tree_ref,
        path_matrix => \%mx,
        path_cache
          => $args{MPD_MNTD_CUM_PATH_LENGTH_TO_ROOT_CACHE},
        last_shared_ancestor_mx
          => $last_shared_ancestor_mx,
        most_probable_lca_depths
          => $most_probable_lca_depths,
        nri_nti_generation  => $nri_nti_generation,
        tree_is_ultrametric => $tree_is_ultrametric,
    );

    #  Save some cycles if all the weights are the same.
    #  If we ever implement dissim then we can also check label_hash2.
    if ($use_wts && $label_hashrefs_are_same) {
        if (not List::Util::any {$_ != 1} values %$label_hash1) {
            $use_wts = undef;
        }
    }

    #  Loop over all possible pairs
    BY_LABEL:
    foreach my $label1 (@labels1) {
        #  Skip self-self comparisons.
        #  Avoids a skip condition inside the map.
        #  Need to conditionally disable for
        #  dissim measure if implemented.
        #  $label1 is reinstated below.
        splice @labels2, $lb2_indices{$label1}, 1;

        #  avoid some nested lookups in the map
        \my %mx_label1 = $mx{$label1} //= {};

        my @path_lengths_this_node
         = map {                   #  $_ is $label2
                $mx_label1{$_}
             // $mx{$_}{$label1}
             // $self->get_phylo_path_length_between_label_pair (
                   label1 => $label1,
                   label2 => $_,
                   %common_args_for_path_call,
               )
           } @labels2;

        my @mpd_wts_this_node;
        if ($use_wts) {
            push @mpd_wts_this_node, @$label_hash2{@labels2};
        }

        #  reinstate $label1 into @labels2
        #  make this conditional if dissim measure implemented
        splice @labels2, $lb2_indices{$label1}, 0, $label1;

        #  next steps only if we added something
        next BY_LABEL if !@path_lengths_this_node;

        #  weighting scheme won't work with non-integer wts - need to use weighted stats
        push @mpd_path_lengths, @path_lengths_this_node;
        push @mntd_path_lengths, min (@path_lengths_this_node);
        if ($use_wts) {
            my $label_count1 = $label_hash1->{$label1};
            push @mpd_wts, map $_ * $label_count1, @mpd_wts_this_node;
            push @mntd_wts, $label_count1;
        }
    }

    my %results;

    my @paths = (\@mntd_path_lengths, \@mpd_path_lengths);
    my @pfxs  = qw /PNTD PMPD/;
    my $i = -1;
    foreach my $path (@paths) {
        $i++;

        my $pfx  = $pfxs[$i] . $abc_num;
        my ($mean, $n, $wts);

        if ($use_wts) {
            $wts  = $pfx =~ /^PMPD/ ? \@mpd_wts : \@mntd_wts;
            $n    = sum @$wts;
            $mean = eval {sum (pairwise {$a * $b} @$path, @$wts) / $n};
        }
        else {
            $n    = scalar @$path;
            $mean = eval {sum (@$path) / $n};
        }

        $results{$pfx . '_MEAN'} = $mean;

        next if $return_means_only && !$return_mean_and_variance_only;

        my $rmsd;
        my $variance;
        if ($n) {
            my $sumsq = $use_wts
                ? sum (pairwise {$a ** 2 * $b} @$path, @$wts)
                : sum (map $_ ** 2, @$path);
            $rmsd = sqrt ($sumsq / $n);
            #  possible neg values close to 0
            $variance = max ($sumsq / $n - $mean ** 2, 0);
        }
        $results{$pfx . '_VARIANCE'}  = $variance;

        next if $return_mean_and_variance_only;

        $results{$pfx . '_RMSD'} = $rmsd;
        $results{$pfx . '_N'}   = $n;
        $results{$pfx . '_MIN'} = min @$path;
        $results{$pfx . '_MAX'} = max @$path;
    }

    return wantarray ? %results : \%results;
}


sub get_phylo_path_length_between_label_pair {
    my ($self, %args) = @_;

    my $label1   = $args{label1};
    my $label2   = $args{label2};
    my $tree_ref = $args{tree_ref};
    my $tree_is_ultrametric
      = exists $args{tree_is_ultrametric}
      ? $args{tree_is_ultrametric}
      : $tree_ref->is_ultrametric;

    my $nri_nti_generation = $args{nri_nti_generation};

    \my %mx         = $args{path_matrix};
    \my %path_cache = $args{path_cache};
    \my %last_shared_ancestor_mx
      = $args{last_shared_ancestor_mx};

    #  ancestor mx only really needed for non-ultrametric, non-NRI
    #  and is populated below
    my $last_ancestor
      =    $last_shared_ancestor_mx{$label1}{$label2}
        // $last_shared_ancestor_mx{$label2}{$label1};
    
    my $fill_last_ancestor_cache = !$last_ancestor;

    $last_ancestor
      //= $tree_ref->get_last_shared_ancestor_for_nodes (
        node_names => {$label1 => 1, $label2 => 1},
        most_probable_lca_depths => $args{most_probable_lca_depths},
      );

    #  target index is one below the last common ancestor
    #  last ancestor is one more than its depth from the end,
    #  so we subtract 2
    my $ancestor_idx = -$last_ancestor->get_depth - 2;

    my $path_lens1 = $path_cache{$label1}
      //= $self->_get_node_cum_path_sum_to_root(
        tree_ref => $tree_ref,
        label    => $label1,
      );

    my $path_length = $path_lens1->[$ancestor_idx];

    if ($tree_is_ultrametric) {
        $path_length *= 2;
        #  prepopulate the matrix for the LCA
        $self->_add_last_ancestor_um_path_lens_to_matrix (
            matrix        => \%mx,
            last_ancestor => $last_ancestor,
            path_length   => $path_length,
        );
    }
    elsif ($nri_nti_generation) {
        $self->_add_last_ancestor_path_lens_to_matrix (
            matrix        => \%mx,
            path_cache    => \%path_cache,
            last_ancestor => $last_ancestor,
            tree_ref      => $tree_ref,
            ancestor_idx  => $ancestor_idx,
        );
        #  now grab it
        $path_length = $mx{$label1}{$label2} // $mx{$label2}{$label1};
    }
    else {
        #  non-ultrametric MPD/MNTD, calc on-demand
        my $path_lens2 = $path_cache{$label2}
            //= $self->_get_node_cum_path_sum_to_root(
                tree_ref => $tree_ref,
                label    => $label2,
            );
        $path_length += $path_lens2->[$ancestor_idx];
        #  try to keep the matrix triangular
        #  and thus speed up accesses above
        if ($label1 le $label2) {
            $mx{$label1}{$label2} = $path_length;
        }
        else {
            $mx{$label2}{$label1} = $path_length;
        }

        if ($fill_last_ancestor_cache) {
            $self->_add_to_last_ancestor_cache(
                last_ancestor => $last_ancestor,
                last_ancestor_mx => \%last_shared_ancestor_mx,
            );
        }
    }

    return $path_length;
}

#  For an ultrametric tree, 
#  populate the matrix for all pairs
#  that share this common ancestor,
#  thus obviating any need to find it again.
#  Sort by terminal count to minimise for-looping
#  around slice assigns below.
sub _add_last_ancestor_um_path_lens_to_matrix {
    my ($self, %args) = @_;
    my $last_ancestor = $args{last_ancestor};
    my $path_length   = $args{path_length};
    \my %mx           = $args{matrix};
    
    my @sibs
      = nkeysort {$_->get_terminal_element_count}
        $last_ancestor->get_children;  #  use a copy
    my $progress
      = $last_ancestor->get_terminal_element_count > 100
      ? Biodiverse::Progress->new (gui_only => 1)
      : undef;
    my $progress_text
      = 'Precaching ultrametric paths for '
      . $last_ancestor->get_name;
    my $node = shift @sibs;
    my $terminals = $node->get_terminal_elements;
    my $s = 0;
    my $n_sibs = @sibs;
    while (my $sib = shift @sibs) { #  handle multifurcation
        if ($progress) {
            $s++;
            $progress->update (
                $progress_text,
                $s / $n_sibs,
            );
        }
        
        my $sib_terminals = $sib->get_terminal_elements;
        foreach my $lb1 (keys %$terminals) {
            @{$mx{$lb1}}{keys %$sib_terminals}
              = ($path_length) x keys %$sib_terminals;
        }
        $terminals = $sib_terminals;
    }

    return;
}


#  fill the path matrix with this LCA's paths
#  if we are running NRI/NTI.
#  Speed penalty is prob too great otherwise.
sub _add_last_ancestor_path_lens_to_matrix {
    my ($self, %args) = @_;
    my $last_ancestor = $args{last_ancestor};
    my $tree_ref      = $args{tree_ref};
    my $ancestor_idx  = $args{ancestor_idx};
    \my %mx           = $args{matrix};
    \my %path_cache   = $args{path_cache};
    
    my $progress
      = $last_ancestor->get_terminal_element_count > 100
      ? Biodiverse::Progress->new (gui_only => 1)
      : undef;
    my $lca_name = $last_ancestor->get_name;
    my $progress_text
      = "Precalculating path lengths for terminals of $lca_name";

    my @sibs = $last_ancestor->get_children;  #  use a copy
    my $s = 0;
    my $n_sibs = @sibs;
    #  Deeply nested loops...
    while (my $node = shift @sibs) { #  handle multifurcation
        $s++;
        my $terminals = $node->get_terminal_elements;
        foreach my $sib (@sibs) {
            if ($progress) {
                $progress->update (
                    $progress_text,
                    $s / $n_sibs,
                );
            }
            
            my $sib_terminals = $sib->get_terminal_elements;
            foreach my $lb1 (keys %$terminals) {
                my $path_lens1 = $path_cache{$lb1}
                  //= $self->_get_node_cum_path_sum_to_root(
                      tree_ref => $tree_ref,
                      label    => $lb1,
                  );
                my $len1 = $path_lens1->[$ancestor_idx];
                foreach my $lb2 (keys %$sib_terminals) {
                    my $path_lens2 = $path_cache{$lb2}
                      //= $self->_get_node_cum_path_sum_to_root(
                          tree_ref => $tree_ref,
                          label    => $lb2,
                      );
                    if ($lb1 le $lb2) {
                        $mx{$lb1}{$lb2}
                          = $len1 + $path_lens2->[$ancestor_idx];
                    }
                    else {
                        $mx{$lb2}{$lb1}
                          = $len1 + $path_lens2->[$ancestor_idx];
                    }
                }
            }
        }
    }

    return;
}


#  Cache the common ancestor for the terminals
#  of the sibling nodes
#  Slice assign is faster than nested for-loops
sub _add_to_last_ancestor_cache {
    my ($self, %args) = @_;
    my $last_ancestor = $args{last_ancestor};
    \my %last_shared_ancestor_mx = $args{last_ancestor_mx};

    my @sibs
      = nkeysort {$_->get_terminal_element_count}
        $last_ancestor->get_children;  #  use a copy
    my $progress
      = $last_ancestor->get_terminal_element_count > 300
      ? Biodiverse::Progress->new (gui_only => 1)
      : undef;
    my $progress_text
      = "Caching last common ancestors for "
      . $last_ancestor->get_name,
    my $s = 0;
    my $n_sibs = @sibs;
    while (my $node = shift @sibs) { #  handle multifurcation
        $s++;
        my $terminals = $node->get_terminal_elements;
        
        foreach my $sib (@sibs) {
            if ($progress) {
                $progress->update (
                    $progress_text,
                    $s / $n_sibs,
                );
            }
            my $sib_terminals = $sib->get_terminal_elements;
            foreach my $lb1 (keys %$terminals) {
                @{$last_shared_ancestor_mx{$lb1}}{keys %$sib_terminals}
                  = ($last_ancestor) x keys %$sib_terminals;
            }
        }
    }

    return;
}

sub _get_node_cum_path_sum_to_root {
    my ($self, %args) = @_;
    my $sum = 0;  #  get a cum sum
    my $lens = $args{tree_ref}
      ->get_node_ref_aa ($args{label})
      ->get_path_length_array_to_root_node_aa;
    return [map $sum += $_, @$lens];
}

sub get_metadata_get_phylo_mpd_mntd_cum_path_length_cache {
    my $self = shift;

    my %metadata = (
        name        => 'get_phylo_mpd_mntd_cum_path_length_cache',
        description => 'Cumulative path length cache for MPD and MNTD calculations',
        indices     => {
            MPD_MNTD_CUM_PATH_LENGTH_TO_ROOT_CACHE => {
                description => 'MPD/MNTD cumulative path length cache',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}


sub get_phylo_mpd_mntd_cum_path_length_cache {
    my $self = shift;
    
    my %results = (MPD_MNTD_CUM_PATH_LENGTH_TO_ROOT_CACHE => {});
    
    return wantarray ? %results : \%results;
}

sub get_metadata_get_phylo_LCA_matrix {
    my $self = shift;

    my %metadata = (
        name        => 'get_phylo_LCA_matrix',
        description => 'LCA matrix used for caching in MPD and MNTD calculations',
        indices     => {
            PHYLO_LCA_MX => {
                description => 'Last common ancestor matrix',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}


sub get_phylo_LCA_matrix {
    my $self = shift;

    my %results = (PHYLO_LCA_MX => {});
    
    return wantarray ? %results : \%results;
}



sub get_metadata_get_phylo_mpd_mntd_matrix {
    my $self = shift;

    my %metadata = (
        name        => 'get_phylo_mpd_mntd_matrix',
        description => 'Matrix used for caching in MPD and MNTD calculations',
        indices     => {
            PHYLO_MPD_MNTD_MATRIX => {
                description => 'MPD/MNTD path length cache matrix',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}


sub get_phylo_mpd_mntd_matrix {
    my $self = shift;

    #my $mx = Biodiverse::Matrix::LowMem->new (NAME => 'mntd_matrix');
    my $mx = {};
    
    my %results = (PHYLO_MPD_MNTD_MATRIX => $mx);
    
    return wantarray ? %results : \%results;
}

#  currently only one cache across all NRI/NTI methods (respectively)
#  Need to determine if one per method is needed (e.g. type 1, 2 & 3
#  for the different weighting schemes).
sub get_metadata_get_phylo_nri_nti_cache {
    my $self = shift;

    my %metadata = (
        name            => 'get_phylo_nri_nti_cache',
        description     => 'Cache used in the MPD/MNTD calculations',
        required_args   => 'tree_ref',
        indices         => {
            PHYLO_NRI_NTI_SAMPLE_CACHE => {
                description => 'Sample cache for the NRI/NTI calcs, indexed by label counts',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_phylo_nri_nti_cache {
    my $self = shift;
    my %args = @_;

    #  Caching it on the tree means we benefit from
    #  prior calculations if they used the same tree.
    #  Very helpful for randomisations.
    my $tree_ref = $args{tree_ref};
    my $cache    = $tree_ref->get_cached_value_dor_set_default_aa (
      PHYLO_NRI_NTI_SAMPLE_CACHE => {},
    );

    my %results = (PHYLO_NRI_NTI_SAMPLE_CACHE => $cache);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_nri_nti1 {
    my $self = shift;

    my %metadata = (
        type        => 'PhyloCom Indices',
        name        => 'NRI and NTI, unweighted',
        description => $nri_nti_expl_text
                     . ' Not weighted by sample counts, '
                     . 'so each label counts once only.',
        pre_calc    => [qw /calc_nri_nti_expected_values calc_phylo_mpd_mntd1/],
        indices     => {
            PHYLO_NRI1 => {
                description    => 'Net Relatedness Index, unweighted',
                formula        => $nri_formula,
                is_zscore      => 1,
            },
            PHYLO_NTI1 => {
                description    => 'Nearest Taxon Index, unweighted',
                formula        => $nti_formula,
                is_zscore      => 1,
            },
        },
        uses_nbr_lists => 1,
    );

    return $metadata_class->new(\%metadata);
}

sub calc_nri_nti1 {
    my $self = shift;
    my %args = @_;

    no warnings 'uninitialized';
    my $nri_score = eval {
        ( $args{PMPD1_MEAN} - $args{PHYLO_NRI_SAMPLE_MEAN} )
        / $args{PHYLO_NRI_SAMPLE_SD};
    };
    my $nti_score = eval {
        ( $args{PNTD1_MEAN} - $args{PHYLO_NTI_SAMPLE_MEAN} )
        / $args{PHYLO_NTI_SAMPLE_SD};
    };
 
    my %results = (
        PHYLO_NRI1 => $nri_score,
        PHYLO_NTI1 => $nti_score,
    );

    return wantarray ? %results :\%results;
}

sub get_metadata_calc_nri_nti2 {
    my $self = shift;

    my %metadata = (
        type        => 'PhyloCom Indices',
        name        => 'NRI and NTI, local range weighted',
        description => $nri_nti_expl_text
                     . ' Local range weighted.',
        pre_calc    => [qw /calc_nri_nti_expected_values calc_phylo_mpd_mntd2/],
        indices     => {
            PHYLO_NRI2 => {
                description => 'Net Relatedness Index, local range weighted',
                formula     => [],
                is_zscore   => 1,
            },
            PHYLO_NTI2 => {
                description => 'Nearest Taxon Index, local range weighted',
                formula     => [],
                is_zscore   => 1,
            },
        },
        uses_nbr_lists => 1,
    );

    return $metadata_class->new(\%metadata);
}

sub calc_nri_nti2 {
    my $self = shift;
    my %args = @_;

    no warnings 'uninitialized';
    my $nri_score = eval {
        ( $args{PMPD2_MEAN} - $args{PHYLO_NRI_SAMPLE_MEAN} )
        / $args{PHYLO_NRI_SAMPLE_SD};
    };
    my $nti_score = eval {
        ( $args{PNTD2_MEAN} - $args{PHYLO_NTI_SAMPLE_MEAN} )
        / $args{PHYLO_NTI_SAMPLE_SD};
    };

    my %results = (
        PHYLO_NRI2 => $nri_score,
        PHYLO_NTI2 => $nti_score,
    );

    return wantarray ? %results :\%results;
}

sub get_metadata_calc_nri_nti3 {
    my $self = shift;

    my %metadata = (
        type        => 'PhyloCom Indices',
        name        => 'NRI and NTI, abundance weighted',
        description => $nri_nti_expl_text
                     . ' Abundance weighted.',
        pre_calc    => [qw /calc_nri_nti_expected_values calc_phylo_mpd_mntd3/],
        indices     => {
            PHYLO_NRI3 => {
                description => 'Net Relatedness Index, abundance weighted',
                formula     => [],
                is_zscore   => 1,
            },
            PHYLO_NTI3 => {
                description => 'Nearest Taxon Index, abundance weighted',
                formula     => [],
                is_zscore   => 1,
            },
        },
        uses_nbr_lists => 1,
    );

    return $metadata_class->new(\%metadata);
}

sub calc_nri_nti3 {
    my $self = shift;
    my %args = @_;

    no warnings 'uninitialized';
    my $nri_score = eval {
        ( $args{PMPD3_MEAN} - $args{PHYLO_NRI_SAMPLE_MEAN} )
        / $args{PHYLO_NRI_SAMPLE_SD};
    };
    my $nti_score = eval {
        ( $args{PNTD3_MEAN} - $args{PHYLO_NTI_SAMPLE_MEAN} )
        / $args{PHYLO_NTI_SAMPLE_SD};
    };

    my %results = (
        PHYLO_NRI3 => $nri_score,
        PHYLO_NTI3 => $nti_score,
    );

    return wantarray ? %results :\%results;
}

sub get_description_calc_nri_nti_expected_values {
    my $desc = <<'END_DESCR'
Expected values used in the NRI and NTI calculations. 
Derived using a null model without resampling where 
each label has an equal probability of being selected
(a null model of even distrbution).
The expected mean and SD are the same for each unique number
of labels across all neighbour sets.  This means if you have
three neighbour sets, each with three labels, then the expected
values will be identical for each, even if the labels are
completely different.
END_DESCR
  ;

    return $desc;
}

sub get_metadata_calc_nri_nti_expected_values {
    my $self = shift;
    
    my $indices = {
        PHYLO_NRI_SAMPLE_MEAN => {
            description    => 'Expected mean of pair-wise distances',
            formula        => [],
        },
        PHYLO_NRI_SAMPLE_SD => {
            description    => 'Expected standard deviation of pair-wise distances',
            formula        => [],
        },
        PHYLO_NTI_SAMPLE_MEAN => {
            description    => 'Expected mean of nearest taxon distances',
            formula        => [],
        },
        PHYLO_NTI_SAMPLE_SD => {
            description    => 'Expected standard deviation of nearest taxon distances',
            formula        => [],
        },
        PHYLO_NRI_NTI_SAMPLE_N => {
            description    => 'Number of random resamples used',
            formula        => [],
        },
    };

    #my $pre_calc_global = [qw /
    #    get_phylo_mpd_mntd_cum_path_length_cache
    #    get_phylo_mpd_mntd_matrix
    #    get_phylo_LCA_matrix
    #    get_prng_object
    #    get_phylo_nri_nti_cache
    #/];
    
    my $description = $self->get_description_calc_nri_nti_expected_values;
    my $reference = "$webb_et_al_ref, $tsir_et_al_ref";

    my %metadata = (
        type            => 'PhyloCom Indices',
        name            => 'NRI and NTI expected values',
        description     => $description,
        reference       => $reference,
        #pre_calc        => [qw /calc_labels_on_tree calc_abc/],
        pre_calc        => [qw /_calc_nri_nti_expected_values/],
        #pre_calc_global => $pre_calc_global,  
        required_args   => 'tree_ref',
        uses_nbr_lists  => 1,
        indices         => $indices,
    );
    
    return $metadata_class->new(\%metadata);
}


sub calc_nri_nti_expected_values {
    my $self = shift;
    my %args = @_;

    my %results = %args{
        qw /PHYLO_NRI_SAMPLE_MEAN PHYLO_NRI_SAMPLE_SD
            PHYLO_NTI_SAMPLE_MEAN PHYLO_NTI_SAMPLE_SD 
            PHYLO_NRI_NTI_SAMPLE_N
        /};
    
    return wantarray ? %results : \%results;
}

sub get_metadata__calc_nri_nti_expected_values {
    my $self = shift;
    
    my $pre_calc_global = [qw /
        get_phylo_mpd_mntd_cum_path_length_cache
        get_phylo_mpd_mntd_matrix
        get_phylo_LCA_matrix
        get_prng_object
        get_phylo_nri_nti_cache
    /];

    my %metadata = (
        type            => 'PhyloCom Indices',
        name            => 'NRI and NTI expected values, inner sub',
        description     => 'NRI and NTI expected values, inner sub',
        pre_calc        => [qw /calc_labels_on_tree/],
        pre_calc_global => $pre_calc_global,  
        required_args   => 'tree_ref',
        uses_nbr_lists  => 1,
    );
    
    return $metadata_class->new(\%metadata);
}


sub _calc_nri_nti_expected_values {
    my $self = shift;
    my %args = @_;

    my $labels_on_tree = $args{PHYLO_LABELS_ON_TREE};
    my $label_count    = scalar keys %$labels_on_tree;

    #my ($mean, $sd, $n, $score);
    my %results;

    if ($label_count > 1) {  #  skip if < 2 labels on tree
        my $cache_name = 'PHYLO_NRI_NTI_SAMPLE_CACHE';
        my $cache      = $args{$cache_name};
        my $cached_scores = $cache->{$label_count};

        if ($ENV{BD_IGNORE_NTI_CACHE} || !$cached_scores) {  #  need to calculate the scores
            $cached_scores = $self->get_nri_nti_expected_values (
                %args,
                label_count => $label_count,
            );
            $cache->{$label_count} = $cached_scores;
        }
        
        @results{keys %$cached_scores} = values %$cached_scores;
    }
    
    return wantarray ? %results : \%results;
}

sub get_nri_nti_expected_values {
    my $self = shift;
    my %args = @_;
    
    my $tree = $args{tree_ref};
    my $label_count = $args{label_count};
    my $iterations = $args{nri_nti_iterations} ||  4999;

    return if ! $label_count;

    my $prng = $args{PRNG_OBJECT};
    
    my $mpd_mntd_method = $args{mpd_mntd_method} || '_calc_phylo_mpd_mntd';
    my $mpd_index_name  = $args{mpd_index_name}  || 'PMPD1_MEAN';
    my $mntd_index_name = $args{mntd_index_name} || 'PNTD1_MEAN';
    my $vpd_index_name  = $args{vpd_index_name}  || 'PMPD1_VARIANCE';
    my $results_pfx     = $args{results_pfx} || 'PHYLO_';

    #  we used to get all named nodes from a tree,
    #  but that caused problems with named inner nodes
    my $get_name_meth       = $args{tree_get_names_method} || 'get_terminal_nodes';
    my $named_nodes         = $args{labels_to_select_from} || $tree->$get_name_meth;
    my @named_node_array    = sort keys %$named_nodes;
    my $label_count_max_idx = $label_count - 1;

    my ($mpd_mean, $mpd_sd, $mntd_mean, $mntd_sd, $vpd_mean, $vpd_sd);
    $mpd_mean  = $tree->get_nri_expected_mean;
    $mpd_sd    = $tree->get_nri_expected_sd (sample_count => $label_count);
    my $do_sample_mpd  = 0;
    my $do_sample_mntd = 1;
    my $do_sample_vpd
      = $label_count > 2
        && $self->get_param('CALCULATE_NRI_VARIANCE_SAMPLE');

    my %results = (
        $results_pfx . 'NRI_SAMPLE_MEAN'  => $mpd_mean,
        $results_pfx . 'NRI_SAMPLE_SD'    => $mpd_sd,
    );
    
    if ($tree->is_ultrametric) {
        #  we can use the exact forms for mntd
        $mntd_mean = $tree->get_nti_expected_mean (sample_count => $label_count);
        $mntd_sd   = $tree->get_nti_expected_sd (sample_count => $label_count);

        $results{$results_pfx . 'NTI_SAMPLE_MEAN'}  = $mntd_mean;
        $results{$results_pfx . 'NTI_SAMPLE_SD'}    = $mntd_sd;
        $results{$results_pfx . 'NRI_NTI_SAMPLE_N'} = 0;

        return wantarray ? %results : \%results
          if !$do_sample_vpd;

        $do_sample_mntd = 0;
    }
    if ($do_sample_mntd && $label_count == $tree->get_terminal_element_count && !$ENV{BD_NO_NTI_MAX_N_SHORTCUT}) {
        $mntd_mean = $tree->get_mean_nearest_neighbour_distance;
        $mntd_sd   = 0;

        $results{$results_pfx . 'NTI_SAMPLE_MEAN'}  = $mntd_mean;
        $results{$results_pfx . 'NTI_SAMPLE_SD'}    = $mntd_sd;
        $results{$results_pfx . 'NRI_NTI_SAMPLE_N'} = 0;

        return wantarray ? %results : \%results
          if !$do_sample_vpd;

        $do_sample_mntd = 0;
    }

    my ($mpd_sum_x, $mpd_sum_x_sqr, $mntd_sum_x, $mntd_sum_x_sqr,
        $vpd_sum_x, $vpd_sum_x_sqr);
    my $n       = 0;
    my $skipped = 0;
    my $bigint  = Math::BigInt->new(scalar keys %$named_nodes);
    my $max_poss_iter = $bigint->bnok($label_count);
    $iterations = min ($iterations, $max_poss_iter);
    if (blessed $iterations) {
        $iterations = $iterations->numify;  #  back to normal number from a bigint
    }

    my %seen;  #  hash of key sets already processed
    my $csv = Text::CSV_XS->new;  #  generate the keys for %seen

    my ($progress, $progress_pfx);
    if (scalar keys %$named_nodes > 25) {
        $progress_pfx = "\nGetting $results_pfx "
                      . ($do_sample_mpd  ? 'NRI and ' : '')
                      . ($do_sample_mntd ? "NTI " : '')
                      . "expected values\n"
                      . "for $label_count labels.\n";   
        $progress = Biodiverse::Progress->new(
            #gui_only => 1,
            text     => $progress_pfx,
        );
    }

    my %convergence = (
        $do_sample_mpd  ? (mpd_mean  => [], mpd_sd  => []) : (),
        $do_sample_mntd ? (mntd_mean => [], mntd_sd => []) : (),
        $do_sample_vpd  ? (vpd_mean  => [], vpd_sd  => []) : (),
    );
    
  ITER:
    while ($n < $iterations) {  
        if ($progress) {
            my $p = $n + 1;
            $progress->update (
                $progress_pfx . "$p of $iterations",
                ($p / $iterations),
            );
        };

        my $shuffled = $prng->shuffle(@named_node_array);
        my @target_labels = @$shuffled[0 .. $label_count_max_idx];
        my $success = $csv->combine (sort @target_labels);
        my $seen_key = $csv->string;

        if ($seen{$seen_key}) {  #  don't repeat ourselves
            $skipped ++;
            next ITER;
        };

        $seen{$seen_key} ++;

        $n ++;

        my %target_label_hash;
        @target_label_hash{@target_labels} = (1) x scalar @target_labels;
        my $lb_hash_ref = \%target_label_hash;

        my %results_this_iter = $self->$mpd_mntd_method (
            %args,
            label_hash1 => $lb_hash_ref,
            label_hash2 => $lb_hash_ref,
            PHYLO_LABELS_ON_TREE => $named_nodes,  #  override
            mpd_mntd_means_only  => 1,  #  overridden if variance is needed
            mpd_mntd_mean_variance_only => $do_sample_vpd,
            nri_nti_generation   => 1,
            no_mpd               => !($do_sample_mpd || $do_sample_vpd),
        );

        my $val;
        
        if ($do_sample_mpd) {
            $val = $results_this_iter{$mpd_index_name};
            $mpd_sum_x += $val;
            $mpd_sum_x_sqr += $val ** 2;
            $mpd_mean  = $mpd_sum_x / $n;
            #  avoid sqrt of negs due to precision
            $mpd_sd    = sqrt max(($mpd_sum_x_sqr / $n) - ($mpd_mean ** 2), 0);

            push @{$convergence{mpd_mean}},  $mpd_mean;
            push @{$convergence{mpd_sd}},    $mpd_sd;
        }
        if ($do_sample_mntd) {
            $val = $results_this_iter{$mntd_index_name};
            $mntd_sum_x += $val;
            $mntd_sum_x_sqr += $val ** 2;
            $mntd_mean = $mntd_sum_x / $n;
            #  avoid sqrt of negs due to precision
            $mntd_sd   = sqrt max (($mntd_sum_x_sqr / $n) - ($mntd_mean ** 2), 0);

            push @{$convergence{mntd_mean}}, $mntd_mean;
            push @{$convergence{mntd_sd}},   $mntd_sd;
        }
        if ($do_sample_vpd) {
            $val = $results_this_iter{$vpd_index_name};
            $vpd_sum_x += $val;
            $vpd_sum_x_sqr += $val ** 2;
            $vpd_mean = $vpd_sum_x / $n;
            #  avoid sqrt of negs due to precision
            $vpd_sd   = sqrt max (($vpd_sum_x_sqr / $n) - ($vpd_mean ** 2), 0);

            push @{$convergence{vpd_mean}}, $vpd_mean;
            push @{$convergence{vpd_sd}},   $vpd_sd;
        }

        #say "\nfnarb,$label_count,$n,$mpd_mean,$mpd_sd,$mntd_mean,$mntd_sd"
        #  if $ENV{BD_NRI_NTI_CUM_STATS};

        if ($n > 100) {  #  just work with the last so many
            foreach my $array (values %convergence) {
                shift @$array;
            }
            #last ITER
            if ($self->get_convergence_nri_nti_expected_values (scores => \%convergence)) {
                #print  "score converged at $n iterations\n";
                last ITER;
            };
        }
    }

    if ($do_sample_mntd) {
        $results{$results_pfx . 'NTI_SAMPLE_MEAN'}  = $mntd_mean;
        $results{$results_pfx . 'NTI_SAMPLE_SD'}    = $mntd_sd;
        $results{$results_pfx . 'NRI_NTI_SAMPLE_N'} = $n;
    }
    if ($do_sample_vpd) {
        $results{$results_pfx . 'NET_VPD_SAMPLE_MEAN'} = $vpd_mean;
        $results{$results_pfx . 'NET_VPD_SAMPLE_SD'}   = $vpd_sd;
        $results{$results_pfx . 'NET_VPD_SAMPLE_N'}    = $n;  
    }

    return wantarray ? %results : \%results;
}


sub get_convergence_nri_nti_expected_values {
    my $self = shift;
    my %args = @_;

    my $scores = $args{scores};


    foreach my $array (values %$scores) {
        my ($min, $max) = minmax (@$array);
        #  handle $max == 0
        my $ratio = $max ? (1 - $min / $max) : 0;
        return 0 if $ratio > 0.005;
    }


    #  if we get this far then we have converged
    return 1;
}


sub get_metadata_get_prng_object {
    my $self = shift;
    my %args = @_;

    my %metadata = (
        name        => 'get_prng_object',
        description => 'Get a PRNG object for the indices object to use',
        indices => {
            PRNG_OBJECT => {

                description => 'The PRNG object',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_prng_object {

    my $self = shift;
    my %args = @_;

    my $prng = $prng_class->new (
        seed  => $args{prng_seed},
        state => $args{prng_state},
    );

    my %results = (PRNG_OBJECT => $prng);

    return wantarray ? %results : \%results;
}

sub reinitialise_prng_object {
    my $self = shift;
    my %args = @_;

    my $globals = $self->get_param('AS_RESULTS_FROM_GLOBAL') || {};

    my $prng = $globals->{get_prng_object}{PRNG_OBJECT};

    if ($args{seed}) {
        $prng->set_seed ($args{seed});
    }
    elsif ($args{state}) {
        $prng->set_seed ($args{state});
    }

    return;
}

sub get_metadata_calc_net_vpd {
    my $self = shift;

    my %metadata = (
        type        => 'PhyloCom Indices',
        name        => 'Net variance of pair-wise phylogenetic distances, unweighted',
        description => 'Z-score of VPD calculated using NRI/NTI resampling'
                     . ' Not weighted by sample counts, '
                     . 'so each label counts once only.',
        pre_calc    => [qw /calc_vpd_expected_values calc_phylo_mpd_mntd1/],
        pre_calc_global => ['set_mpd_mntd_sample_variance_flag'],
        indices     => {
            PHYLO_NET_VPD => {
                description => 'Net variance of pair-wise phylogenetic distances, unweighted',
                #formula        => $nri_formula,
                is_zscore   => 1,
            },
        },
        uses_nbr_lists => 1,
    );

    return $metadata_class->new(\%metadata);
}

sub calc_net_vpd {
    my $self = shift;
    my %args = @_;

    no warnings 'uninitialized';
    my $z_score = eval {
        ( $args{PMPD1_VARIANCE} - $args{PHYLO_NET_VPD_SAMPLE_MEAN} )
        / $args{PHYLO_NET_VPD_SAMPLE_SD};
    };
 
    my %results = (
        PHYLO_NET_VPD => $z_score,
    );

    return wantarray ? %results :\%results;
}

sub get_metadata_set_mpd_mntd_sample_variance_flag {
    my %metadata = (
        type            => 'PhyloCom Indices',
        name            => 'flag to also calculate MPD variance when running NRI/NTI',
        description     => 'flag to also calculate MPD variance when running NRI/NTI',
        required_args   => 'tree_ref',
        uses_nbr_lists  => 1,
        indices         => undef,
    );

    return $metadata_class->new(\%metadata);    
}

sub set_mpd_mntd_sample_variance_flag {
    my $self = shift;
    $self->set_param(CALCULATE_NRI_VARIANCE_SAMPLE => 1);
    #  precalcs need to return hash or hashref
    return wantarray ? () : {};
}

sub get_metadata_calc_vpd_expected_values {
    my $self = shift;
    
    my $indices = {
        PHYLO_NET_VPD_SAMPLE_MEAN => {
            description    => 'Expected mean of pair-wise variance (VPD)',
            formula        => [],
        },
        PHYLO_NET_VPD_SAMPLE_SD => {
            description    => 'Expected standard deviation of pair-wise variance (VPD)',
            formula        => [],
        },
        PHYLO_NET_VPD_SAMPLE_N => {
            description    => 'Number of random resamples used to calculate '
                            . 'expected pair-wise variance scores'
                            . '(will equal PHYLO_NRI_NTI_SAMPLE_N for non-ultrametric trees)',
            formula        => [],
        },
    };
    
    my $description = 'Expected values for VPD, analogous to the NRI/NTI results';
    my $reference   = $mpd_variance_ref;

    my %metadata = (
        type            => 'PhyloCom Indices',
        name            => 'Net VPD expected values',
        description     => $description,
        reference       => $reference,
        pre_calc        => [qw /_calc_nri_nti_expected_values/],
        pre_calc_global => [qw /set_mpd_mntd_sample_variance_flag/],  
        required_args   => 'tree_ref',
        uses_nbr_lists  => 1,
        indices         => $indices,
    );
    
    return $metadata_class->new(\%metadata);
}


sub calc_vpd_expected_values {
    my $self = shift;
    my %args = @_;

    my %results = %args{
      qw /PHYLO_NET_VPD_SAMPLE_MEAN PHYLO_NET_VPD_SAMPLE_SD PHYLO_NET_VPD_SAMPLE_N/
    };
    $results{PHYLO_NET_VPD_SAMPLE_N} //= 0;

    return wantarray ? %results : \%results;
}


1;


__END__

=head1 NAME

Biodiverse::Indices::PhyloCom

=head1 SYNOPSIS

  use Biodiverse::Indices;

=head1 DESCRIPTION

Phylogenetic indices for the Biodiverse system, based on
those available in the PhyloCom system (L<http://phylodiversity.net/phylocom/>).

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
