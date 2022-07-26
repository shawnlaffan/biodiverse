package Biodiverse::Indices::Endemism;
use strict;
use warnings;
use Carp;
use 5.020;

our $VERSION = '3.99_004';

my $metadata_class = 'Biodiverse::Metadata::Indices';

sub get_metadata_calc_endemism_central_normalised {

    my $desc = "Normalise the WE and CWE scores by the neighbourhood size.\n"
             . "(The number of groups used to determine the local ranges).\n";

    my %metadata = (
        description     => $desc,
        name            => 'Endemism central normalised',
        type            => 'Endemism',
        pre_calc        => [qw {
            _calc_endemism_central
            calc_elements_used
        }],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            ENDC_CWE_NORM => {
                description => 'Corrected weighted endemism normalised by groups',
                formula     => [
                    '= \frac{ENDC\_CWE}{EL\_COUNT\_ALL}',
                ],
                lumper      => 0,
            },
            ENDC_WE_NORM  => {
                description => 'Weighted endemism normalised by groups',
                formula     => [
                    '= \frac{ENDC\_WE}{EL\_COUNT\_ALL}',
                ],
                lumper      => 0,
            },
        },
    );  #  add to if needed

    return $metadata_class->new(\%metadata);
}

sub calc_endemism_central_normalised {
    my $self = shift;
    my %args = @_;

    my $count = $args{EL_COUNT_ALL} || 0;
    my %results = (
        ENDC_CWE_NORM => eval { $args{END_CWE} / $count },
        ENDC_WE_NORM  => eval { $args{END_WE}  / $count },
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_endemism_whole_normalised {

    my $desc = "Normalise the WE and CWE scores by the neighbourhood size.\n"
                . "(The number of groups used to determine the local ranges). \n";

    my %metadata = (
        description     => $desc,
        name            => 'Endemism whole normalised',
        type            => 'Endemism',
        pre_calc        => [qw {
            _calc_endemism_whole
            calc_elements_used
        }],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            ENDW_CWE_NORM => {
                description => 'Corrected weighted endemism normalised by groups',
                formula     => [
                    '= \frac{ENDW\_CWE}{EL\_COUNT\_ALL}',
                ],
            },
            ENDW_WE_NORM  => {
                description => 'Weighted endemism normalised by groups',
                formula     => [
                    '= \frac{ENDW\_WE}{EL\_COUNT\_ALL}',
                ],
            },
        },
    );  #  add to if needed

    return $metadata_class->new(\%metadata);
}

sub calc_endemism_whole_normalised {
    my $self = shift;
    my %args = @_;

    my $count = $args{EL_COUNT_ALL} || 0;
    my %results = (
        ENDW_CWE_NORM => eval { ($args{END_CWE} || 0) / $count },
        ENDW_WE_NORM  => eval { ($args{END_WE}  || 0) / $count },
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_label_range_hash {
    my $self = shift;

    my %metadata = (
        name            => 'Label range hash',
        description     => 'Hash of label ranges across the basedata',
        type            => 'Endemism',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            label_range_hash => {
                type => 'list',
            },
        }
    );

    return $metadata_class->new(\%metadata);
}

sub get_label_range_hash {
    my $self = shift;

    my $bd = $self->get_basedata_ref;

    my %range_hash;

    foreach my $label ($bd->get_labels) {
        $range_hash{$label} = $bd->get_range (element => $label);
    }

    my %results = (label_range_hash => \%range_hash);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_endemism_central {

    my $desc = "Calculate endemism for labels only in neighbour set 1, "
                . "but with local ranges calculated using both neighbour sets";

    my $ref = 'Crisp et al. (2001) J Biogeog. '
              . 'https://doi.org/10.1046/j.1365-2699.2001.00524.x ; '
              . 'Laffan and Crisp (2003) J Biogeog. '
              . 'http://www3.interscience.wiley.com/journal/118882020/abstract';

    my %metadata = (
        description     => $desc,
        name            => 'Endemism central',
        type            => 'Endemism',
        pre_calc        => [qw /_calc_endemism_central/],
        reference       => $ref,
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            ENDC_CWE      => {
                description => 'Corrected weighted endemism',
                lumper      => 0,
                formula     => [
                    '= \frac{ENDC\_WE}{ENDC\_RICHNESS}',
                ],
            },
            ENDC_WE       => {
                description => 'Weighted endemism',
                lumper      => 0,
                formula     => [
                    '= \sum_{t \in T} \frac {r_t} {R_t}',
                    ' where ',
                    't',
                    ' is a label (taxon) in the set of labels (taxa) ',
                    'T',
                    ' in neighbour set 1, ',
                    'r_t',
                    ' is the local range (the number of elements containing label ',
                    't',
                    ' within neighbour sets 1 & 2, this is also its value in list ABC2_LABELS_ALL), and ',
                    'R_t',
                    ' is the global range of label ',
                    't',
                    ' across the data set (the number of groups it is found in, '
                    . 'unless the range is specified at import).'
                ],
            },
            ENDC_RICHNESS => {
                description => 'Richness used in ENDC_CWE (same as index RICHNESS_SET1)',
                lumper      => 0,
            },
            ENDC_SINGLE   => {
                description => 'Endemism unweighted by the number of neighbours. '
                               . 'Counts each label only once, regardless of how many '
                               . "groups in the neighbourhood it is found in.  \n"
                               . 'Useful if your data have sampling biases and '
                               . 'best applied with a small window.',
                lumper      => 0,
                reference   => 'Slatyer et al. (2007) J. Biogeog '
                               . 'https://doi.org/10.1111/j.1365-2699.2006.01647.x',
                formula     => [
                    '= \sum_{t \in T} \frac {1} {R_t}',
                    ' where ',
                    't',
                    ' is a label (taxon) in the set of labels (taxa) ',
                    'T',
                    ' in neighbour set 1, and ',
                    'R_t',
                    ' is the global range of label ',
                    't',
                    ' across the data set (the number of groups it is found in, '
                    . 'unless the range is specified at import).'
                ],
            },
        },
    );  #  add to if needed

    return $metadata_class->new(\%metadata);
}

sub calc_endemism_central {
    my $self = shift;
    my %args = @_;

    my %results = (
        ENDC_CWE        => $args{END_CWE},
        ENDC_WE         => $args{END_WE},
        ENDC_RICHNESS   => $args{END_RICHNESS},
        ENDC_SINGLE     => $args{END_SINGLE},
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_endemism_central_lists {

    my %metadata = (
        description     => 'Lists used in endemism central calculations',
        name            => 'Endemism central lists',
        type            => 'Endemism',
        pre_calc        => qw /_calc_endemism_central/,
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            ENDC_WTLIST      => {
                description => 'List of weights for each label used in the '
                                . 'endemism central calculations',
                type => 'list',
                },
            ENDC_RANGELIST   => {
                description => 'List of ranges for each label used in the '
                                . 'endemism central calculations',
                type        => 'list',
                items_invariant => 1,
            },
        },

    );

    return $metadata_class->new(\%metadata);
}

sub calc_endemism_central_lists {
    my $self = shift;
    my %args = @_;

    #my $hashRef = $self->_calc_endemism(%args, end_central => 1);

    my %results = (
        ENDC_WTLIST     => $args{END_WTLIST},
        ENDC_RANGELIST  => $args{END_RANGELIST},
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_endemism_central_hier_part {
    my $self = shift;

    return $self->metadata_for_calc_endemism_hier_part (
        @_,
        prefix        => 'ENDC_HPART_',
        endemism_type => 'central',
    );
}

sub calc_endemism_central_hier_part {
    my $self = shift;

    return $self->_calc_endemism_hier_part (
        @_,
        prefix        => 'ENDC_HPART_',
    );
}

sub get_metadata_calc_endemism_whole_hier_part {
    my $self = shift;

    return $self->metadata_for_calc_endemism_hier_part (
        @_,
        prefix        => 'ENDW_HPART_',
        endemism_type => 'whole',
    );
}

sub calc_endemism_whole_hier_part {
    my $self = shift;

    return $self->_calc_endemism_hier_part (
        @_,
        prefix        => 'ENDW_HPART_',
    );
}

#  generic metadata for the hierarchical stuff
sub metadata_for_calc_endemism_hier_part {
    my $self = shift;
    my %args = @_;
    
    my $prefix = $args{prefix};
    my $endemism_type = $args{endemism_type};
    croak "Invalid argument $endemism_type\n"
        if $endemism_type ne 'central' && $endemism_type ne 'whole';
    
    #  how many levels in the hierarchy?
    my $bd         = $self->get_basedata_ref;
    my $labels_ref = $bd->get_labels_ref;
    my $axes       = $labels_ref->get_cell_sizes;
    my $hier_max   = scalar @$axes - 1;
    
    my $indices = {};
    foreach my $i (0 .. $hier_max) {
        my $index_name          = $prefix . $i;
        my $index_count_name    = $prefix . 'C_' . $i;
        my $index_expected_name = $prefix . 'E_' . $i;
        my $index_ome_name      = $prefix . 'OME_' . $i;

        my $descr = 'List of the proportional contribution of labels to the '
                    . "endemism $endemism_type calculations, hierarchical level "
                    . $i;

        $indices->{$index_name} = {
            description => $descr,
            type        => 'list',
            #formula     => ,
        };

        $descr = 'List of the proportional count of labels to the '
                    . "endemism $endemism_type calculations "
                    . "(equivalent to richness per hierarchical grouping)"
                    . ", hierarchical level "
                    . $i;
                    
        $indices->{$index_count_name} = {
            description => $descr,
            type        => 'list',
        };
        
        $descr = 'List of the expected proportional contribution of labels to the '
                    . "endemism $endemism_type calculations "
                    . "(richness per hierarchical grouping divided by overall richness)"
                    . ", hierarchical level "
                    . $i;
                    
        $indices->{$index_expected_name} = {
            description => $descr,
            type        => 'list',
        };

        $descr = 'List of the observed minus expected proportional contribution of labels to the '
                    . "endemism $endemism_type calculations "
                    . ", hierarchical level "
                    . $i;
                    
        $indices->{$index_ome_name} = {
            description => $descr,
            type        => 'list',
        };
    }

    my $descr = "Partition the endemism $endemism_type results "
                . "based on the taxonomic hierarchy "
                . 'inferred from the label axes. (Level 0 is the highest).';

    my $formula;    #  skip for now
    #my $formula = $self->get_formula_end_hpart;
    

    my %metadata = (
        description     => $descr,
        name            => "Endemism $endemism_type hierarchical partition",
        type            => 'Endemism',
        reference       => 'Laffan et al. (2013) J Biogeog. https://doi.org/10.1111/jbi.12001',
        formula         => $formula,
        pre_calc        => [
            "_calc_endemism_$endemism_type",
        ],
        pre_calc_global => 'get_basedata_labels_as_tree',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => $indices,
    );

    return $metadata_class->new(\%metadata);
}

#  generic to allow both central and whole
sub _calc_endemism_hier_part {
    my $self = shift;
    my %args = @_;
    
    
    my $wt_list = $args{END_WTLIST} || croak "Argument END_WTLIST missing\n";
    my $we      = $args{END_WE};
    my $tree    = $args{BASEDATA_LABEL_TREE};
    my $prefix  = $args{prefix};
    
    #  get depth excluding the root node
    my $depth = $tree->get_depth_below - 1;

    my @hash_ref_array = ();
    my @count_array    = ();
    my $total_count    = 0;
    while (my ($label, $wt) = each %$wt_list) {
        my $contribution = $wt / $we;
        $total_count ++;
        my $node_ref = $tree->get_node_ref (node => $label);
        my $node_name = $label;

        #  climb the tree and add the contributions
        my $i = $depth;
        while (! $node_ref->is_root_node) {
            $hash_ref_array[$i]{$node_name} += $contribution;
            $count_array[$i]{$node_name} ++;
            $i--;
            $node_ref  = $node_ref->get_parent;
            $node_name = $node_ref->get_name;
        }
    }

    my %results;

    foreach my $i (0 .. $#hash_ref_array) {
        my $observed_hash = $hash_ref_array[$i];
        my $count_hash    = $count_array[$i];
        my $expected_hash = {};
        my $ome_hash      = {};
        while (my ($key, $value) = each %$count_hash) {
            my $expected = $value / $total_count;
            $expected_hash->{$key} = $expected;
            $ome_hash->{$key}      = $expected - $observed_hash->{$key};
        }

        $results{$prefix . $i}          = $observed_hash;
        $results{$prefix . 'C_' . $i}   = $count_hash;
        $results{$prefix . 'E_' . $i}   = $expected_hash;
        $results{$prefix . 'OME_' . $i} = $ome_hash;
    };

    return wantarray ? %results : \%results;
}

sub get_formula_end_hpart {
    my $self = shift;
    
    my $main_formula = <<'END_FORMULA'
\begin{array}{rcl}
WE_i               & = & \sum_{t_i \in T_i}\frac{r_t_i}{R_t_i} \\ 
&& \\
CWE_i              & = & \frac{WE}{n_i}                        \\
&& \\ 
WEP_{t_i}          & = & \frac{\frac{r_t_i}{R_t_i}}{n_i}       \\
&& \\ 
E(WEP_{t_i})       & = & \frac{1}{n_i}                         \\
&& \\ 
E(WEP_{t_{i-j}})   & = & \sum_{t_i \in T_{i-j}} E(WEP_{t_i})   \\
&& \\
OME(WEP_{t_{i-j}}) & = & WEP_{t_{i-j}} - E(WEP_{t_{i-j}})      \\
\end{array}
END_FORMULA
  ;
    $main_formula =~ s/\n/ /g;
    #$main_formula =~ s/\s+/ /g;
    $main_formula =~ s/\s+$//g;
    #$main_formula = 'equation\ is\ in\ progress';
    #$main_formula = q{};  #  place holder

    my @formula = (
      $main_formula,
      'In the following, ',
      #'WE_i = \sum_{t_i \in T_i}\frac{r_t_i}{R_t_i}',
      #', ',
      #'WEP_{t_i} = \frac{\frac{r_t_i}{R_t_i}}{n_i}',
      #', ',
      'i',
      ' is the lowest hierarchical level (0 is the root), ',
      't_i',
      ' is taxon ',
      'i',
      ' in the set of taxa ',
      'T_i',
      ', ',
      'WEP_{t_i}',
      ' is the proportion of the WE score at level ',
      'i',
      ' contributed by taxon ',
      't_i',
      ', ',
      'E(WEP_{t_i})',
      ' is the expected contribution of taxon ',
      'T_i',
      ' to ',
      'WEP_{t_i}',
      ', ',
      'OME(WEP_{t_{i-j}})',
      ' is the observed contribution minus the expected contribution, and ',
      'j \leq i',
      );
    

    return wantarray ? @formula : \@formula;
}


sub get_metadata__calc_endemism_central {
    my $self = shift;

    my %metadata = (
        name            => '_calc_endemism_central ',
        description     => 'Internal calc for calc_endemism_central',
        pre_calc_global => [qw/get_label_range_hash/],
        pre_calc        => 'calc_abc2',
    );

    return $metadata_class->new(\%metadata);
}

#  wrapper sub
sub _calc_endemism_central {
    my $self = shift;
    my %args = @_;

    return $self->_calc_endemism(%args, end_central => 1);
}


sub get_metadata_calc_endemism_whole {

    my %metadata = (
        description     => 'Calculate endemism using all labels found in both neighbour sets',
        name            => 'Endemism whole',
        type            => 'Endemism',
        pre_calc        => '_calc_endemism_whole',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            ENDW_CWE        => {
                description => 'Corrected weighted endemism',
                formula     => [
                    '= \frac{ENDW\_WE}{ENDW\_RICHNESS}',
                ],
            },
            ENDW_WE         => {
                description => 'Weighted endemism',
                formula     => [
                    '= \sum_{t \in T} \frac {r_t} {R_t}',
                    ' where ',
                    't',
                    ' is a label (taxon) in the set of labels (taxa) ',
                    'T',
                    ' across both neighbour sets, ',
                    'r_t',
                    ' is the local range (the number of elements containing label ',
                    't',
                    ' within neighbour sets 1 & 2, this is also its value in list ABC2_LABELS_ALL), and ',
                    'R_t',
                    ' is the global range of label ',
                    't',
                    ' across the data set (the number of groups it is found in, '
                    . 'unless the range is specified at import).'
                ],
            },
            ENDW_RICHNESS   => {
                description => 'Richness used in ENDW_CWE (same as index RICHNESS_ALL)',
            },
            ENDW_SINGLE     => {
                description => 'Endemism unweighted by the number of neighbours. '
                               . 'Counts each label only once, regardless of how many '
                               . "groups in the neighbourhood it is found in.  \n"
                               . 'Useful if your data have sampling biases and '
                               . 'best applied with a small window.',
                reference   => 'Slatyer et al. (2007) J. Biogeog '
                               . 'https://doi.org/10.1111/j.1365-2699.2006.01647.x',
                formula     => [
                    '= \sum_{t \in T} \frac {1} {R_t}',
                    ' where ',
                    't',
                    ' is a label (taxon) in the set of labels (taxa) ',
                    'T',
                    ' across neighbour sets 1 & 2, and ',
                    'R_t',
                    ' is the global range of label ',
                    't',
                    ' across the data set (the number of groups it is found in, '
                    . 'unless the range is specified at import).'
                ]
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_endemism_whole {
    my $self = shift;
    my %args = @_;

    my %results = (
        ENDW_CWE        => $args{END_CWE},
        ENDW_WE         => $args{END_WE},
        ENDW_RICHNESS   => $args{END_RICHNESS},
        ENDW_SINGLE     => $args{END_SINGLE},
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_endemism_whole_lists {

    my %metadata = (
        description     => 'Lists used in the endemism whole calculations',
        name            => 'Endemism whole lists',
        type            => 'Endemism',
        pre_calc        => '_calc_endemism_whole',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices         => {
            ENDW_WTLIST     => {
                description => 'List of weights for each label used in the '
                                . 'endemism whole calculations',
                type => 'list',
            },
            ENDW_RANGELIST  => {
                description => 'List of ranges for each label used in the '
                                . 'endemism whole calculations',
                type        => 'list',
                items_invariant => 1,
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_endemism_whole_lists {
    my $self = shift;
    my %args = @_;

    my %results = ( 
        ENDW_WTLIST     => $args{END_WTLIST},
        ENDW_RANGELIST  => $args{END_RANGELIST},
    );

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_endemism_whole {
    my $self = shift;

    my %metadata = (
        name            => '_calc_endemism_whole',
        description     => 'Internal calc for calc_endemism_whole',
        pre_calc_global => [qw/get_label_range_hash/],
        pre_calc        => 'calc_abc2',
    );

    return $metadata_class->new(\%metadata);
}

#  wrapper sub
sub _calc_endemism_whole {
    my $self = shift;
    return $self->_calc_endemism(@_, end_central => 0);
}

#  Calculate endemism.  Private method called by others
sub _calc_endemism {
    my $self = shift;
    #  end_central is a default flag, gets overridden if user specifies
    my %args = (end_central => 1, @_);

    my $bd = $self->get_basedata_ref;

    #  if element_list2 is specified and end_central == 1,
    #  then it will consider those elements in the local range calculations,
    #  but only use those labels that occur in the element_list1

    my $local_ranges = $args{label_hash_all};
    my $label_list   = $args{end_central}
        ? $args{label_hash1}
        : $args{label_hash_all};

    #  allows us to use this for any other basedata get_* function
    my $function   = $args{function} || 'get_range';
    my $range_hash = $args{label_range_hash} || {};

    my (%wts, %ranges, $endemism, $rosauer);
    my $label_count = scalar keys %$label_list;

    foreach my $label (keys %$label_list) {
        my $range       = $range_hash->{$label}  // $bd->$function (element => $label);
        my $wt          = $local_ranges->{$label} / $range;
        $endemism      += $wt;
        $wts{$label}    = $wt;
        $ranges{$label} = $range;
        $rosauer       += 1 / $range;
    }

    #  returns undef if no elements specified
    my $CWE = eval {
        no warnings 'uninitialized';
        $endemism / $label_count;
    };

    my %results = (
        END_CWE       => $CWE,
        END_WE        => $endemism,
        END_RICHNESS  => $label_count,
        END_SINGLE    => $rosauer,
        END_WTLIST    => \%wts,
        END_RANGELIST => \%ranges,
    );

    #  these get remapped by the calling functions
    return wantarray ? %results : \%results;
}


sub get_metadata_get_basedata_labels_as_tree {
    my $self = shift;
    
    my %metadata = (
        name            => 'get_basedata_labels_as_tree',
        description     => 'Convert the labels in a basedata object into a '
                           . 'tree using the implicit hierarchy in the labels',
        indices => {
            BASEDATA_LABEL_TREE  => {
                description => 'basedata as tree',
            },
        },
    );
    
    return $metadata_class->new(\%metadata);
}

#  get a hierarchical tree of the current basedata
sub get_basedata_labels_as_tree {
    my $self = shift;
    my %args = @_;

    my $bd   = $self->get_basedata_ref;
    my $tree = $bd->to_tree;

    my %results = (
        BASEDATA_LABEL_TREE => $tree,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_endemism_absolute_lists {

    my $desc = "Lists underlying the absolute endemism scores.\n";

    my %metadata = (
        description     => $desc,
        name            => 'Absolute endemism lists',
        type            => 'Endemism',
        pre_calc        => ['_calc_endemism_absolute'],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            END_ABS1_LIST => {
                description => 'List of labels entirely endemic to neighbour set 1',
                type        => 'list',
            },
            END_ABS2_LIST => {
                description => 'List of labels entirely endemic to neighbour set 1',
                type        => 'list',
            },
            END_ABS_ALL_LIST => {
                description => 'List of labels entirely endemic to neighbour sets 1 and 2 combined',
                type        => 'list',
            },
        },
    );  #  add to if needed

    return $metadata_class->new(\%metadata);
}

sub calc_endemism_absolute_lists {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /END_ABS1_LIST END_ABS2_LIST END_ABS_ALL_LIST/;
    my %results = %args{@keys};

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_endemism_absolute {

    my $desc = "Absolute endemism scores.\n";

    my %metadata = (
        description     => $desc,
        name            => 'Absolute endemism',
        type            => 'Endemism',
        pre_calc        => ['_calc_endemism_absolute'],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            END_ABS1 => {
                description => 'Count of labels entirely endemic to neighbour set 1',
            },
            END_ABS2  => {
                description => 'Count of labels entirely endemic to neighbour set 2',
            },
            END_ABS_ALL => {
                description => 'Count of labels entirely endemic to neighbour sets 1 and 2 combined',
            },
            END_ABS1_P => {
                description => 'Proportion of labels entirely endemic to neighbour set 1',
            },
            END_ABS2_P => {
                description => 'Proportion of labels entirely endemic to neighbour set 2',
            },
            END_ABS_ALL_P => {
                description => 'Proportion of labels entirely endemic to neighbour sets 1 and 2 combined',
            },
        },
    );  #  add to if needed

    return $metadata_class->new(\%metadata);
}

sub calc_endemism_absolute {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /END_ABS1 END_ABS2 END_ABS_ALL END_ABS1_P END_ABS2_P END_ABS_ALL_P/;
    my %results = %args{@keys};

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_endemism_absolute {

    my $desc = "Internal calcs for absolute endemism.\n";

    my %metadata = (
        description     => $desc,
        name            => 'Absolute endemism, internals',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        pre_calc        => ['calc_abc2'],
    );  #  add to if needed

    return $metadata_class->new(\%metadata);
}



sub _calc_endemism_absolute {
    my $self = shift;
    my %args = @_;

    my $bd = $self->get_basedata_ref;

    my $local_ranges = $args{label_hash_all};
    my $l_hash1 = $args{label_hash1};
    my $l_hash2 = $args{label_hash2};
    
    #  allows us to use this for any other basedata get_* function
    my $function = 'get_range';

    my ($end1, $end2, $end_all) = (0, 0, 0);
    my (%eh1, %eh2, %eh_all);

    while (my ($sub_label, $local_range) = each %{$local_ranges}) {
        my $range = $bd->$function (element => $sub_label);

        next if $range > $local_range;  #  cannot be absolutely endemic

        $end_all++;
        $eh_all{$sub_label} = $local_range;

        if (exists $l_hash1->{$sub_label} and $range <= $l_hash1->{$sub_label}) {
            $end1++;
            $eh1{$sub_label} = $local_range;
        }
        if (exists $l_hash2->{$sub_label} and $range <= $l_hash2->{$sub_label})  {
            $end2++;
            $eh2{$sub_label} = $local_range;
        }
    }

    my $end1_p = eval {$end1 / scalar keys %$l_hash1};
    my $end2_p = eval {$end2 / scalar keys %$l_hash2};
    my $end_all_p = eval {$end_all / scalar keys %$local_ranges};

    my %results = (
        END_ABS1         => $end1,
        END_ABS2         => $end2,
        END_ABS_ALL      => $end_all,
        END_ABS1_LIST    => \%eh1,
        END_ABS2_LIST    => \%eh2,
        END_ABS_ALL_LIST => \%eh_all,
        END_ABS1_P       => $end1_p,
        END_ABS2_P       => $end2_p,
        END_ABS_ALL_P    => $end_all_p,
    );

    return wantarray ? %results : \%results;
}


1;

__END__

=head1 NAME

Biodiverse::Indices::Endemism

=head1 SYNOPSIS

  use Biodiverse::Indices;

=head1 DESCRIPTION

Endemism indices for the Biodiverse system.
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
