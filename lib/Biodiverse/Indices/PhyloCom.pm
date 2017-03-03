package Biodiverse::Indices::PhyloCom;
use strict;
use warnings;
use 5.010;

use Carp;
use Biodiverse::Progress;

use List::Util qw /sum min max/;
use List::MoreUtils qw /any minmax pairwise/;
use Scalar::Util qw /blessed/;
use Math::BigInt ();

use constant HAVE_PANDA_LIB
  => !$ENV{BD_NO_USE_PANDA} && eval 'require Panda::Lib';


our $VERSION = '1.99_007';

use Biodiverse::Statistics;
my $stats_package = 'Biodiverse::Statistics';

use Biodiverse::Matrix::LowMem;
my $mx_class_for_trees = 'Biodiverse::Matrix::LowMem';

use Math::Random::MT::Auto;
my $prng_class = 'Math::Random::MT::Auto';

my $metadata_class = 'Biodiverse::Metadata::Indices';

my $webb_et_al_ref = 'Webb et al. (2008) http://dx.doi.org/10.1093/bioinformatics/btn358';


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
    my $mx          = $args{PHYLO_MPD_MNTD_MATRIX}
      || croak "Argument PHYLO_MPD_MNTD_MATRIX not defined\n";
    my $labels_on_tree = $args{PHYLO_LABELS_ON_TREE};
    my $tree_ref       = $args{tree_ref};
    my $abc_num        = $args{abc_num} || 1;
    my $use_wts        = $abc_num == 1 ? $args{mpd_mntd_use_wts} : 1;
    my $return_means_only       = $args{mpd_mntd_means_only};
    my $label_hashrefs_are_same = $label_hash1 eq $label_hash2;
    
    return $self->default_mpd_mntd_results (@_)
        if $label_hashrefs_are_same
           && scalar keys %$labels_on_tree <= 1;

    #  Are we on the tree and have a non-zero count?
    #  Could be a needless slowdown under permutations using only labels on the tree.
    my @labels1 = sort grep { exists $labels_on_tree->{$_} && $label_hash1->{$_}} keys %$label_hash1;
    my @labels2 = $label_hashrefs_are_same
        ? @labels1
        : sort grep { exists $labels_on_tree->{$_} && $label_hash2->{$_} } keys %$label_hash2;

    my (@mpd_path_lengths, @mntd_path_lengths, @mpd_wts, @mntd_wts);

    #  Loop over all possible pairs
    my $i = 0;
    BY_LABEL:
    foreach my $label1 (@labels1) {
        my $label_count1 = $label_hash1->{$label1};

        my (
            @mpd_path_lengths_this_node,
            @mntd_path_lengths_this_node,
            @mpd_wts_this_node,
        );
        my $j = 0;

      BY_LABEL2:
        foreach my $label2 (@labels2) {  #  could work on i..n instead of 1..n, but mntd needs minima

            #  skip same labels (FIXME: but not if used as dissim measure)
            next BY_LABEL2 if $label1 eq $label2;

            my $path_length = $mx->get_defined_value_aa ($label1, $label2);

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
                    if (HAVE_PANDA_LIB) {
                        Panda::Lib::hash_merge (\%path, $sub_path, Panda::Lib::MERGE_LAZY());
                    }
                    else {
                        @path{keys %$sub_path} = values %$sub_path;
                    }
                }
                delete $path{$last_ancestor->get_name()};
                $path_length = sum values %path;
                $mx->set_value(
                    element1 => $label1,
                    element2 => $label2,
                    value    => $path_length,
                );
            }

            push @mpd_path_lengths_this_node, $path_length;
            push @mntd_path_lengths_this_node, $path_length;
            if ($use_wts) {
                push @mpd_wts_this_node, $label_hash2->{$label2};
            }

            $j ++;
        }

        #  next steps only if we added something
        next BY_LABEL if !$j;

            #  weighting scheme won't work with non-integer wts - need to use weighted stats
            push @mpd_path_lengths, @mpd_path_lengths_this_node;
            my $min = min (@mntd_path_lengths_this_node);
            push @mntd_path_lengths, $min;
            if ($use_wts) {
                push @mpd_wts, map {$_ * $label_count1} @mpd_wts_this_node;
                push @mntd_wts, $label_count1;
            }
        }

    my %results;

    my @paths = (\@mntd_path_lengths, \@mpd_path_lengths);
    my @pfxs  = qw /PNTD PMPD/;
    $i = -1;
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

        next if $return_means_only;

        $results{$pfx . '_N'}   = $n;
        $results{$pfx . '_MIN'} = min @$path;
        $results{$pfx . '_MAX'} = max @$path;

        my $rmsd;
        if ($n) {
            my $sumsq = $use_wts
                ? sum (pairwise {$a ** 2 * $b} @$path, @$wts)
                : sum (map {$_ ** 2} @$path);
            $rmsd = sqrt ($sumsq / $n);
        }
        $results{$pfx . '_RMSD'} = $rmsd;
    }

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

    my $mx = Biodiverse::Matrix::LowMem->new (NAME => 'mntd_matrix');
    
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
                description => 'Sample cache for the NRI/NTI calcs, ordered by label counts',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_phylo_nri_nti_cache {
    my $self = shift;

    my %results = (PHYLO_NRI_NTI_SAMPLE_CACHE => {});

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
            },
            PHYLO_NTI1 => {
                description    => 'Nearest Taxon Index, unweighted',
                formula        => $nti_formula,
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
                description    => 'Net Relatedness Index, local range weighted',
                formula        => [],
            },
            PHYLO_NTI2 => {
                description    => 'Nearest Taxon Index, local range weighted',
                formula        => [],
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
                description    => 'Net Relatedness Index, abundance weighted',
                formula        => [],
            },
            PHYLO_NTI3 => {
                description    => 'Nearest Taxon Index, abundance weighted',
                formula        => [],
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

    my $pre_calc_global = [qw /
        get_phylo_mpd_mntd_matrix
        get_prng_object
        get_phylo_nri_nti_cache
    /];
    
    my $description = $self->get_description_calc_nri_nti_expected_values;

    my %metadata = (
        type            => 'PhyloCom Indices',
        name            => 'NRI and NTI expected values',
        description     => $description,
        reference       => $webb_et_al_ref,
        #pre_calc        => [qw /calc_labels_on_tree calc_abc/],
        pre_calc        => [qw /calc_labels_on_tree/],
        pre_calc_global => $pre_calc_global,  
        required_args   => 'tree_ref',
        uses_nbr_lists  => 1,
        indices         => $indices,
    );
    
    return $metadata_class->new(\%metadata);
}


sub calc_nri_nti_expected_values {
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

        if (!$cached_scores) {  #  need to calculate the scores
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
    my $results_pfx     = $args{results_pfx} || 'PHYLO_';

    #  we used to get all named nodes from a tree,
    #  but that caused problems with named inner nodes
    my $get_name_meth       = $args{tree_get_names_method} || 'get_terminal_nodes';
    my $named_nodes         = $args{labels_to_select_from} || $tree->$get_name_meth;
    my @named_node_array    = sort keys %$named_nodes;
    my $label_count_max_idx = $label_count - 1;

    my ($mpd_sum_x, $mpd_sum_x_sqr, $mntd_sum_x, $mntd_sum_x_sqr);
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
        $progress_pfx = "\nGetting $results_pfx NRI and NTI expected values\n"
                      . "for $label_count labels.\n";   
        $progress = Biodiverse::Progress->new(
            #gui_only => 1,
            text     => $progress_pfx,
        );
    }

    my %convergence = (
        mpd_mean  => [],
        mpd_sd    => [],
        mntd_mean => [],
        mntd_sd   => [],
    );
    my ($mpd_mean, $mpd_sd, $mntd_mean, $mntd_sd);
    
    
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

        my %results_this_iter = $self->$mpd_mntd_method (
            %args,
            label_hash1 => \%target_label_hash,
            label_hash2 => \%target_label_hash,
            PHYLO_LABELS_ON_TREE => $named_nodes,  #  override
            mpd_mntd_means_only  => 1,
        );

        my $val = $results_this_iter{$mpd_index_name};
        $mpd_sum_x += $val;
        $mpd_sum_x_sqr += $val ** 2;
        $val = $results_this_iter{$mntd_index_name};
        $mntd_sum_x += $val;
        $mntd_sum_x_sqr += $val ** 2;

        $mpd_mean  = $mpd_sum_x / $n;
        $mntd_mean = $mntd_sum_x / $n;
        {
            #  handle negatives which can occur occasionally
            no warnings qw /numeric/;
            $mpd_sd    = eval {sqrt (($mpd_sum_x_sqr / $n) - ($mpd_mean ** 2))} // 0;
            $mntd_sd   = eval {sqrt (($mntd_sum_x_sqr / $n) - ($mntd_mean ** 2))} // 0;
        }

        #say "\nfnarb,$label_count,$n,$mpd_mean,$mpd_sd,$mntd_mean,$mntd_sd"
        #  if $ENV{BD_NRI_NTI_CUM_STATS};

        push @{$convergence{mpd_mean}},  $mpd_mean;
        push @{$convergence{mpd_sd}},    $mpd_sd;
        push @{$convergence{mntd_mean}}, $mntd_mean;
        push @{$convergence{mntd_sd}},   $mntd_sd;
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

    my %results = (
        $results_pfx . 'NRI_SAMPLE_MEAN'  => $mpd_mean,
        $results_pfx . 'NRI_SAMPLE_SD'    => $mpd_sd,
        $results_pfx . 'NTI_SAMPLE_MEAN'  => $mntd_mean,
        $results_pfx . 'NTI_SAMPLE_SD'    => $mntd_sd,
        $results_pfx . 'NRI_NTI_SAMPLE_N' => $n,
    );

    return wantarray ? %results : \%results;
}


sub get_convergence_nri_nti_expected_values {
    my $self = shift;
    my %args = @_;

    my $scores = $args{scores};

    foreach my $array (values %$scores) {
        my ($min, $max) = minmax (@$array);
        my $ratio = 1 - $min / $max;
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
