package Biodiverse::SpatialConditions::LabelRanges;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use experimental qw /refaliasing for_list/;

use Carp;
use English qw /-no_match_vars/;

use Scalar::Util qw /looks_like_number blessed/;
use List::MoreUtils qw /uniq/;
use List::Util qw /min max any/;
use Ref::Util qw { :all };

use Biodiverse::Metadata::SpatialConditions;


#  sets the volatile flag if needed
sub _process_label_arg {
    my ($self, %args) = @_;

    my $label = $args{label};

    return $label if defined $label;

    $label = $self->get_current_label
        // croak "argument 'label' not defined and current label not set\n";
    #  if we get here then the label arg could change per call
    #  not sure it is still needed as we have a metadata process now
    $self->set_volatile_flag(1);

    return $label;
}

sub get_metadata_sp_in_label_range {
    my $self = shift;

    my $description = <<~'EOD'
        (Available from version 5.1)

        Is a group within a label's range?

        This is by default assessed as a check of whether the
        label is found in the processing group but can
        be generalised by using the `convex_hull`, `concave_hull`
        or `circumcircle` arguments.

        The `type` argument determines if the
        processing or neighbour group is assessed.
        Normally this can be left as the default.

        The `convex_hull` returns true if the processing group
        is within the convex hull defined by the groups that form
        the label range.

        The `circumcircle` returns true if the processing group
        is within the minimum circumscribing circle that
        includes all of the label range groups.

        The `concave_hull` returns true if the processing group
        is within the concave hull defined by the groups that form
        the label range.  The concavity can be controlled by the
        `hull_ratio` argument, and holes can be allowed by setting the
        boolean argument `allow_holes` to a true value.

        Both the latter two arguments use the first two axes by default
        and will return an error if there is only one group axis in the basedata.
        If you have more than two axes and wish to assess different ones
        then pass the axes argument. (This argument is ignored for the
        default case as it does a direct comparison of the group names).

        If more than one of `convex_hull`, `concave_hull` and `circumcircle`
        arguments are passed then only one i run.  The convex hull takes
        priority, followed by the circumcircle, and lastly the concave hull.

        An optional `buffer_dist` argument can be used to adjust the size
        of the convex/concave hull or circumcircle.  As is standard with
        GIS buffering, positive values increase the area while negative
        values shrink it.

        The `label` argument should normally be specified but in some
        circumstances a default is set (e.g. when a randomisation
        seed location is set).
        EOD
    ;

    my $example = <<~'EOEX'
        # Are we in the range of label called Genus:Sp1?
        sp_in_label_range(label => 'Genus:Sp1')

        #  Are we in the convex hull?
        sp_in_label_range(label => 'Genus:Sp1', convex_hull => 1)

        #  Are we in the maximally concave hull?
        sp_in_label_range(label => 'Genus:Sp1', concave_hull => 1)

        #  Are we in a slightly less concave hull?
        sp_in_label_range(label => 'Genus:Sp1', concave_hull => 1, hull_ratio => 0.3)

        #  Are we in a slightly less concave hull allowing for holes?
        sp_in_label_range(
            label        => 'Genus:Sp1',
            concave_hull => 1,
            hull_ratio   => 0.3,
            allow_holes  => 1,
        )

        #  Are we in the circumscribing circle?
        sp_in_label_range(label => 'Genus:Sp1', circumcircle => 1)

        #  Are we in the convex hull with a buffer of 100,000 units?
        sp_in_label_range(
            label       => 'Genus:Sp1',
            convex_hull => 1,
            buffer_dist => 100000,
        )

        #  Buffers can be negative, in which case the
        #  convex/concave hull or circumcircle is shrunk
        sp_in_label_range(
            label       => 'Genus:Sp1',
            convex_hull => 1,
            buffer_dist => -100000,
        )

        #  Are we in the convex hull defined using the
        #  coordinates from the third and first axes?
        sp_in_label_range(
            label       => 'Genus:Sp1',
            convex_hull => 1,
            axes        => [2,0],
        )

        #  A convex hull with holes and "half" concave.
        sp_in_label_range(
            label        => 'Genus:Sp1',
            concave_hull => 1,
            allow_holes  => 1,
            hull_ratio   => 0.5,
        )
        EOEX
    ;

    my $uses_current_label = $self->get_promise_current_label;
    my $bool = $self->is_def_query || $uses_current_label;

    my $is_volatile_cb = sub {
        my ($self, %args) = @_;
        $self->get_promise_current_label && !$args{label};
    };

    my %metadata = (
        description   => $description,
        example       => $example,
        required_args  => [
            $bool ? () : 'label',
        ],
        optional_args  => [
            $bool ? 'label' : (),
            'type', #  nbr or proc to control use of nbr or processing groups
            qw/
                axes         circumcircle convex_hull
                concave_hull hull_ratio   allow_holes
                buffer_dist
            /,
        ],
        result_type    => $uses_current_label ? 'always_same_current_label' : 'always_same',
        index_no_use   => 1, #  turn index off since this doesn't cooperate with the search method
        is_volatile_cb => $is_volatile_cb,
        aggregate_substitute_method => {
            re_name => 'in_label_range',
            method  => '_aggregate_get_groups_in_label_range',
        },
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_in_label_range {
    my ($self, %args) = @_;

    my $label = $args{label} // $self->_process_label_arg();

    state $cache_name_labels = 'sp_in_label_range_labels';
    my $cache_labels = $self->get_cached_value($cache_name_labels);
    if (!$cache_labels) {
        $self->set_cached_value($cache_name_labels, scalar $self->get_basedata_ref->get_labels_as_hash);
    };

    return 0 if !$cache_labels->{$label};

    my $group = $self->get_current_coord_id(%args);

    if ($args{convex_hull} || $args{circumcircle} || $args{concave_hull}) {
        my $in_polygon = $self->get_in_polygon_hash (%args);
        return $in_polygon->{$group};
    }

    state $cache_name = 'sp_in_label_range_by_group';
    my $cache = $self->get_cached_value_dor_set_default_href($cache_name);

    my $labels_in_group
        =   $cache->{$group}
        //= $self->get_basedata_ref->get_labels_in_group_as_hash_aa ($group);

    return exists $labels_in_group->{$label};
}

sub _aggregate_get_groups_in_label_range {
    my ($self) = @_;

    #  no point continuing if no basedata
    my $bd = $self->get_basedata_ref // return;

    my $conditions = $self->get_conditions_nws;

    my $re = $self->get_regex (name => 'in_label_range');

    return if not $conditions =~ /$re/ms;

    my $cur_label = $self->_dequote_string_literal($+{cur_label});

    my $method_args_hash = $self->get_param ('METHOD_ARG_HASHES');
    my $range_method = $+{range_method};
    my $range_args   = $+{range_args};
    my $method_args  = $method_args_hash->{$range_method . $range_args} // {};
    my $range_label  = delete local $method_args->{label};

    my $label = $range_label // $cur_label // $self->get_current_label;

    return if !defined $label;

    #  label not in basedata
    return wantarray ? () : {}
        if !$bd->exists_label_aa($label);

    if ($method_args->{convex_hull} || $method_args->{circumcircle} || $method_args->{concave_hull}) {
        #  these only work with axes [0,1].
        my $axes = $method_args->{axes};
        return if defined $axes && (!is_arrayref ($axes) || join (':', @$axes) ne '0:1');
        my $in_polygon = $self->get_in_polygon_hash (%$method_args, label => $label);
        return wantarray ? %$in_polygon : $in_polygon;
    }

    my $tmp = $bd->get_groups_with_label_as_hash_aa ($label);
    my %groups_with_label;
    @groups_with_label{keys %$tmp} = (1) x keys %$tmp;

    return wantarray ? %groups_with_label : \%groups_with_label;
}

use constant DEFAULT_CONVEX_HULL_RATIO => 0.00001;

sub _get_cache_key_for_in_polygon_check {
    my ($self, %args) = @_;

    my $key = $args{convex_hull} ? 'convex_hull'
        : $args{circumcircle} ? 'circumcircle'
        : 'concave_hull';

    if ($args{concave_hull}) {
        $key .= sprintf (
            '_ARGS_(%s:%s)',
            (max (min (1, $args{hull_ratio} // DEFAULT_CONVEX_HULL_RATIO), 0)),
            !!$args{allow_holes}
        );
    }
    if ($args{buffer_dist}) {
        $key .= "_buffered_$args{buffer_dist}";
    }

    return $key;
}

sub get_in_polygon_hash {
    my ($self, %args) = @_;

    my $bd    = $self->get_basedata_ref;

    my $poly_type
        = $args{convex_hull}  ? 'convex_hull'
        : $args{concave_hull} ? 'concave_hull'
        : 'circumcircle';

    croak "sp_in_label_range: Insufficient group axes for $poly_type"
        if scalar $bd->get_group_axis_count < 2;

    my $h = $self->get_current_args;
    my $axes = $args{axes} // $h->{axes} // [0,1];

    my $label = $args{label} // $self->_process_label_arg();

    return wantarray ? () : {}
        if !$bd->exists_label_aa($label);

    my $in_polygon;

    my %extra_args;
    if ($args{concave_hull}) {
        $extra_args{allow_holes} = !!$args{allow_holes};
        $extra_args{ratio}       = max (min (1, $args{hull_ratio} // DEFAULT_CONVEX_HULL_RATIO), 0);
    }

    if (my $buff_dist = $args{buffer_dist}) {  #  we have a buffer to work with
        my $cache_key = $self->_get_cache_key_for_in_polygon_check(%args);
        my $cache = $self->get_cached_value_dor_set_default_href('IN_LABEL_RANGE');
        $in_polygon
            = $cache->{$cache_key}{$label}
            //= do {
            my $method  = "get_label_range_${poly_type}";
            my $polygon = $bd->$method(label => $label, axes => $axes, %extra_args)->Buffer($buff_dist, 30);
            $bd->get_groups_in_polygon (polygon => $polygon, axes => $axes);
        };
    }
    else {  #  no buffer
        my $method = "get_groups_in_label_range_${poly_type}";
        $in_polygon = $bd->$method(
            label => $label,
            axes  => $axes,
            %extra_args,
        );
    }
    return wantarray ? %$in_polygon : $in_polygon;
}

sub get_metadata_sp_in_label_ancestor_range {
    my $self = shift;

    my $description = <<~'EOD'
        (Available from version 5.1)

        Is a group within the range of a label's ancestor?

        Returns true if the group falls within the range of
        any of the any of the ancestor's terminal descendant
        ranges.  The range is by default defined as the set of
        groups in the basedata containing that label.  Polygons
        can also be specified (see below).

        The ancestor is by default defined by length along the
        path to the root node. Setting the `by_depth` option to true
        uses the number of ancestors.  The `by_tip_count` option
        finds the first ancestor with at least the target number
        of tips while `by_desc_count` uses the number of descendants
        (tips and internals). The `by_len_sum` finds the first ancestor
        for which the sum of its descendant branch lengths plus
        its own length is greater than the target.

        Negative target values with `by_length` or `by_depth` search the path
        from the root to the specified node. However, if a `by_*_count`
        option is used then a negative `target` is treated as
        zero and returns the specified label range is returned.

        The `target` argument determines how far up or down the tree
        the ancestor is searched for.  When using length,
        the distance includes the tipwards extent
        of the branch. The depth is calculated as the number
        of ancestors.

        If the `target` value exceeds that to (or of) the root node
        then the root or label node is returned for positive or
        negative dist values, respectively.

        An internal branch can be specified as the label.
        Specifying a `target` of 0 for an internal node
        is one means to use the range of an internal node.

        Returns false if the label is not associated with
        a node on the tree.

        When the `as_frac` argument is true then target is
        treated as a fraction of the distance to the root
        node, the number of tips, or the sum of all branches,
        as appropriate.

        If the `eq` argument is true then the branch lengths are all
        treated as of equal length (the mean of the non-zero branch
        lengths), although zero length branches remain zero.
        This is the same as the alternate tree used in CANAPE.

        If the `rw` argument is true then the branches are range
        weighted.  This is the same as the range weighted
        tree in CANAPE.  When both `eq` and `rw` are true then
        this is the same as the range weighted alternate tree
        in CANAPE

        The underlying algorithm checks each of the terminal
        ranges using [sp_in_label_range()](#sp_in_label_range).
        This means the search can also use the convex/concave
        hull or circumcircle of each terminal, as well as
        setting other arguments such as the `buffer_dist`
        and using a default label in some circumstances.

        Note that the range of each of the ancestor's tips
        is assessed separately, i.e. the union of the
        hulls/circles is used.  The ranges are not aggregated
        before a hull or circumcircle is calculated.

        EOD
    ;

    my $example = <<~'EOEX'
        # Are we in the range of an ancestor of Genus:Sp1?
        sp_in_label_ancestor_range(label => 'Genus:Sp1', target => 0.5)

        # Are we in the range of the "grandmother" of Genus:Sp1?
        sp_in_label_ancestor_range(
          label    => 'Genus:Sp1',
          target   => 2,
          by_depth => 1,
        )

        # Are we in the range of the first ancestor with 6 or more tips?
        sp_in_label_ancestor_range(
          label        => 'Genus:Sp1',
          target       => 6,
          by_tip_count => 1,
        )

        #  Are we in any of the tips' convex hulls?
        sp_in_label_ancestor_range(
          label       => 'Genus:Sp1',
          target      => 0.5,
          convex_hull => 1,
        )

        #  Are we in any of the tips' concave hulls with a ratio parameter of 0.5?
        sp_in_label_ancestor_range(
          label        => 'Genus:Sp1',
          target       => 0.5,
          concave_hull => 1,
          hull_ratio   => 0.5,
        )

        #  Are we in any of the tips' circumscribing circles?
        sp_in_label_ancestor_range(
          label        => 'Genus:Sp1',
          target       => 0.5,
          circumcircle => 1,
        )

        #  Are we in the range of the ancestor for which the sum of
        #  branch lengths below and including it is 10,000?
        sp_in_label_ancestor_range(
          label      => 'Genus:Sp1',
          target     => 10000,
          by_len_sum => 1,
        )

        #  Are we in the range of the ancestor for which the sum of
        #  number of branches below is at least 10?
        sp_in_label_ancestor_range(
          label      => 'Genus:Sp1',
          target     => 10,
          by_desc_count => 1,
        )


        EOEX
    ;

    my $meta = $self->get_metadata_sp_in_label_range;
    push @{$meta->{required_args}}, 'target';
    push @{$meta->{optional_args}}, (qw /by_depth as_frac by_tip_count/);
    $meta->{description} = $description;
    $meta->{example}     = $example;
    $meta->{requires_tree_ref} = 1;
    $meta->{aggregate_substitute_method} = {
        #  If condition matches regex then we can generate a hash
        #  of all nbr results and skip any per-group search.
        re_name => 'in_label_ancestor_range',
        method  => '_aggregate_sp_in_label_ancestor_range',
    };
    return wantarray ? %$meta : $meta;
}

sub sp_in_label_ancestor_range {
    my ($self, %args) = @_;

    my $range = $self->get_tree_node_ancestral_range_hash(%args);
    my $coord = $self->get_current_coord_id (%args{type});

    return exists $range->{$coord};
}

#  a lot of duplicated code in here
sub _aggregate_sp_in_label_ancestor_range {
    my ($self) = @_;

    my $conditions = $self->get_conditions_nws;

    my $re = $self->get_regex (name => 'in_label_ancestor_range');
    return if not $conditions =~ /$re/ms;

    my $cur_label = $self->_dequote_string_literal($+{cur_label});

    my $method_args_hash = $self->get_param ('METHOD_ARG_HASHES');
    my $range_method = $+{range_method};
    my $range_args   = $+{range_args};
    my $method_args  = $method_args_hash->{$range_method . $range_args} // {};
    my $range_label  = delete local $method_args->{label};

    #  we only work with axes [0,1] for now.
    my $axes = $method_args->{axes};
    return if $axes && (!is_arrayref ($axes) || join (':', @$axes) ne '0:1');

    my $label = $range_label // $cur_label // $self->get_current_label;

    return if !defined $label;

    return $self->get_tree_node_ancestral_range_hash (%$method_args, label => $label);
}

sub get_tree_node_ancestral_range_hash {
    my ($self, %args) = @_;

    $args{tree_ref} //= $self->get_tree_for_ancestral_conditions (%args)
        // croak 'No tree ref available';

    $args{cache} //= $self->get_tree_node_ancestor_cache (%args);

    my $ancestor = $self->get_tree_node_ancestor (%args);
    return wantarray ? () : {}
        if !defined $ancestor;

    return $self->get_tree_node_range_hash (%args, node => $ancestor);
}

sub get_tree_node_ancestral_range_bbox {
    my ($self, %args) = @_;

    $args{tree_ref} //= $self->get_tree_for_ancestral_conditions (%args)
        // croak 'No tree ref available';
    my $cache = $args{cache} //= $self->get_tree_node_ancestor_cache (%args);

    my $bbox = $cache->{bbox}{$args{label}};
    if (!$bbox) {
        my $range_hash = $self->get_tree_node_ancestral_range_hash(%args);
        if (!%$range_hash) {
            $bbox = [];
        }
        else {
            my $bd = $args{basedata_ref} // $self->get_basedata_ref;
            $bbox = $bd->get_group_list_bbox_2d(groups => $range_hash);
        }
        $cache->{bbox}{$args{label}} = $bbox;
    }

    return wantarray ? @$bbox : $bbox;
}

sub get_tree_node_range_hash {
    my ($self, %args) = @_;

    my $node  = $args{node} // croak 'node argument not defined';
    my $cache = $args{cache} // $self->get_tree_node_ancestor_cache (%args);
    my $bd    = $args{basedata_ref} // $self->get_basedata_ref;

    my %range;
    if ($args{convex_hull} || $args{concave_hull} || $args{circumcircle}) {
        my $poly_cache_key = $self->_get_cache_key_for_in_polygon_check(%args);
        \%range = $cache->{polygon_ranges}{$bd->get_sha256}{$poly_cache_key}{$node->get_name} //= do {
            my %collated_range;
            foreach my $tip_label ($node->get_terminal_elements) {
                \my %tip_range = $self->get_in_polygon_hash(%args, label => $tip_label);
                @collated_range{keys %tip_range} = values %tip_range;
            }
            \%collated_range;
        }
    }
    else {
        \%range = $cache->{group_ranges}{$bd->get_sha256}{$node->get_name} //= do {
            $bd->get_range_union(
                return_hash => 1,
                labels      => scalar $node->get_terminal_elements,
            );
        };
    }

    return wantarray ? %range : \%range;
}

#  shared across several methods
sub get_tree_node_ancestor_cache {
    my ($self, %args) = @_;

    my $tree = $args{tree_ref} // croak 'tree_ref arg not passed';

    my $d = $args{target} // croak 'target arg not passed';

    #  a lot of setup but saves time for large data sets
    my $cache = $self->get_cached_value_dor_set_default_href('sp_in_label_ancestor_range');
    my $cache_key
        = "d=>$d,"
        . join ',', map {"$_=>". ($args{$_} // 0)}
        qw /by_depth by_len_sum by_tip_count by_desc_count as_frac/;
    $cache = $cache->{$tree}{$cache_key} //= {};

    return $cache;
}

sub get_tree_node_ancestor {
    my ($self, %args) = @_;

    my $label = $args{label} // $self->_process_label_arg();
    my $tree = $args{tree_ref} // $self->get_tree_for_ancestral_conditions (%args)
        // croak 'No tree ref available';

    my $node = $tree->get_node_ref_or_undef_aa($label);
    return if !defined $node;

    my $d = $args{target} // croak 'argument "target" not defined';

    my $cache = $args{cache} // $self->get_tree_node_ancestor_cache (%args, tree_ref => $tree);

    my $ancestor = $cache->{ancestors}{$label} //= do {
        if ($args{as_frac}) {
            $d = $args{by_depth} ? ($d <=> 0) * (1 - abs($d)) * $node->get_depth
                : $args{by_len_sum} ? $d * $tree->get_total_tree_length
                : $args{by_tip_count} ? POSIX::ceil($d * $tree->get_terminal_element_count)
                : $args{by_desc_count} ? POSIX::ceil($d * $tree->get_node_count)
                : $d * $node->get_distance_to_root_node;
        }

        my $anc = $args{by_depth} ? $node->get_ancestor_by_depth_aa($d)
            : $args{by_len_sum} ? $node->get_ancestor_by_sum_of_branch_lengths_aa($d)
            : $args{by_tip_count} ? $node->get_ancestor_by_ntips_aa($d)
            : $args{by_desc_count} ? $node->get_ancestor_by_ndescendants_aa($d)
            : $node->get_ancestor_by_length_aa($d);
        $anc;
    };

    return $ancestor;
}

sub get_tree_for_ancestral_conditions{
    my ($self, %args) = @_;

    my $tree  = $self->get_tree_ref // croak 'No tree ref available';

    #  no point weighting if it is a depth thing
    return $tree if $args{by_depth};

    if (delete $args{eq}) {
        #  equal branch lengths
        my $bd = $args{basedata_ref} // $self->get_basedata_ref;
        #  should cache by SHA256 or similar, and perhaps use the vcache
        state $cache_name = 'CLONED_TREE_EQ_B_LENS_' . $bd;
        if (my $cached = $self->get_cached_value($cache_name)) {
            $tree = $cached;
        }
        else {
            $tree = $tree->clone_with_equalised_branch_lengths(basedata_ref => $bd);
            $self->set_cached_value($cache_name => $tree);
        }
    }
    if (delete $args{rw}) {
        #  range weighting!
        my $bd = $args{basedata_ref} // $self->get_basedata_ref;
        #  should cache by SHA256 or similar, and perhaps use the vcache
        state $cache_name = 'CLONED_TREE_RANGE_WEIGHTED_' . $bd;
        if (my $cached = $self->get_cached_value($cache_name)) {
            $tree = $cached;
        }
        else {
            $tree = $tree->clone_with_range_weighted_branches(basedata_ref => $bd);
            $self->set_cached_value($cache_name => $tree);
        }
    }

    return $tree;
}


1;