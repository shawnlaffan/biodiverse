package Biodiverse::SpatialConditions::CalculatedOutputs;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use experimental qw /refaliasing for_list/;

use Carp;
use English qw /-no_match_vars/;

sub get_example_sp_get_spatial_output_list_value {

    state $ex = <<~'END_EXAMPLE_GSOLV'
        #  Get the spatial results value for the current neighbour group
        # (or processing group if used as a def query)
        sp_get_spatial_output_list_value (
            output  => 'sp1',              #  using spatial output called sp1
            list    => 'SPATIAL_RESULTS',  #  from the SPATIAL_RESULTS list
            index   => 'PE_WE_P',          #  get index value for PE_WE_P
        )

        #  Get the spatial results value for group 128:254
        #  Note that the SPATIAL_OUTPUTS list is assumed if
        #  no 'list' arg is passed.
        sp_get_spatial_output_list_value (
            output  => 'sp1',
            element => '128:254',
            index   => 'PE_WE_P',
        )
        END_EXAMPLE_GSOLV
    ;

    return $ex;
}


sub get_metadata_sp_get_spatial_output_list_value {
    my $self = shift;

    my $description =
        q{Obtain a value from a list in a previously calculated spatial output.};

    my $example = $self->get_example_sp_get_spatial_output_list_value;

    my %metadata = (
        description => $description,
        index_no_use   => 1,  #  turn index off since this doesn't cooperate with the search method
        required_args  => [qw /output index/],
        optional_args  => [qw /list element no_error_if_no_index/],
        result_type    => 'always_same',
        example        => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  get the value from another spatial output
sub sp_get_spatial_output_list_value {
    my $self = shift;
    my %args = @_;

    my $list_name = $args{list} // 'SPATIAL_RESULTS';
    my $index     = $args{index};
    my $no_die_if_not_exists = $args{no_error_if_no_index};

    my $element = $args{element} // $self->get_current_coord_id;

    my $bd      = $self->get_basedata_ref;
    my $sp_name = $args{output};
    croak "Spatial output name not defined\n" if not defined $sp_name;

    my $sp = $bd->get_spatial_output_ref (name => $sp_name)
        or croak 'Spatial output $sp_name does not exist in basedata '
        . $bd->get_param ('NAME')
        . "\n";

    croak "element $element is not in spatial output $sp_name\n"
        if not $sp->exists_element (element => $element);

    my $list = $sp->get_list_ref (
        list    => $list_name,
        element => $element,
    );

    state $idx_ex_cache_name
        = 'sp_get_spatial_output_list_value_list_exists';

    if (   !exists $list->{$index}
        && !$no_die_if_not_exists
        && !$self->get_cached_value ($idx_ex_cache_name)
    ) {
        #  See if the index exists in another element.
        #  Croak if it is in none, as that is
        #  probably a typo.
        my $found_index;
        foreach my $el ($sp->get_element_list) {
            my $el_list = $sp->get_list_ref (
                list    => $list_name,
                element => $el,
            );
            $found_index ||= exists $el_list->{$index};
            last if $found_index;
        }

        croak "Index $index does not exist across "
            . "elements of spatial output $sp_name\n"
            if !$found_index;
    };

    #  in the event of a missing list in another element
    $self->set_cached_value (
        $idx_ex_cache_name => 1,
    );

    #no autovivification;

    return $list->{$index};
}

sub vec_sp_get_spatial_output_list_value {
    my ($self, %args) = @_;

    my $list_name = $args{list} // 'SPATIAL_RESULTS';
    my $index     = $args{index};

    my $bd      = $self->get_basedata_ref;
    my $sp_name = $args{output};
    croak "Spatial output name not defined\n" if not defined $sp_name;

    my $sp = $bd->get_spatial_output_ref (name => $sp_name)
        or croak 'Spatial output $sp_name does not exist in basedata '
        . $bd->get_param ('NAME')
        . "\n";

    my @operators = qw /lt le gt ge eq spaceship/;
    my $op = List::Util::first {defined $args{$_}} (@operators);

    my $vcache = $self->get_volatile_cache;
    my $cache  = $vcache->get_cached_href ('vec_sp_get_spatial_output_list_value');
    my $cache_key = join "\034", $sp_name, $list_name, $index;

    #  "operated" ndarray
    my $cache_op_key = defined $op ? join ("\034", $op, $args{$op}) : 'undef';
    my $ndarray = $cache->{$cache_key}{$cache_op_key};

    return $ndarray if defined $ndarray;

    #  cache the main list grab
    $ndarray = $cache->{$cache_key}{ndarray};

    if (!defined $ndarray) {
        my ($min, $has_undef);
        my %results;
        foreach my $element (sort $bd->get_groups) {
            my $list = $sp->get_list_ref_aa($element, $list_name) // {};
            # say STDERR "$list, $element";
            my $val = $list->{$index}; #  need to handle array refs
            $results{$element} = $val;
            if (defined $val) {
                $min //= $val;
                $min = $val if $val < $min;
            }
            else {
                $has_undef ||= 1;
            }
        };

        my $badval;
        if ($has_undef) {
            $min //= 1;
            $badval = $min - 1;
            $_ = $badval for values %results;
        }

        $ndarray = $self->_aggregate_hash_to_pdl(\%results, $badval);
        $cache->{$cache_key}{ndarray} = $ndarray;
    }

    #  messy but avoids string evals
    if ($op) {
        $ndarray
            = $op eq 'lt'  ? $ndarray  <  $args{$op}
            : $op eq 'gt'  ? $ndarray  >  $args{$op}
            : $op eq 'le'  ? $ndarray <=  $args{$op}
            : $op eq 'ge'  ? $ndarray >=  $args{$op}
            : $op eq 'eq'  ? $ndarray ==  $args{$op}
            : $op eq 'spaceship' ? $ndarray <=> $args{$op}
            : $ndarray;
        $cache->{$cache_key}{$cache_op_key} = $ndarray;
    }
    return $ndarray;
}

sub get_metadata_sp_spatial_output_passed_defq {
    my $self = shift;

    my $description =
        "Returns 1 if an element passed the definition query "
            . "for a previously calculated spatial output";

    #my $example = $self->get_example_sp_get_spatial_output_list_value;
    my $examples = <<~'END_EX'
        #  Used for spatial or cluster type analyses:
        #  The simplest case is where the current
        #  analysis includes a def query and you
        #  want to use it in a spatial condition.
        sp_spatial_output_passed_defq();

        #  Using another output in this basedata
        #  In this case the output is called 'analysis1'
        sp_spatial_output_passed_defq(
            output => 'analysis1',
        );

        #  Return true if a specific element passed the def query
        sp_spatial_output_passed_defq(
            element => '153.5:-32.5',
        );
        END_EX
    ;

    my %metadata = (
        description => $description,
        index_no_use   => 1,  #  turn index off since this doesn't cooperate with the search method
        #required_args  => [qw /output/],
        optional_args  => [qw /element output/],
        result_type    => 'always_same',
        example        => $examples,
    );

    return $self->metadata_class->new (\%metadata);
}


#  get the value from another spatial output
sub sp_spatial_output_passed_defq {
    my $self = shift;
    my %args = @_;

    my $element = $args{element} // $self->get_current_coord_id;

    my $sp = $self->_get_sp_ref_for_defq_check(%args{output});

    return 1
        if !$self->is_def_query && $self->get_param('VERIFYING');

    croak "output argument not defined "
        . "or we are not being used for a spatial analysis\n"
        if !defined $sp;

    croak "element $element is not in spatial output\n"
        if not $sp->exists_element_aa ($element);

    my $passed_defq = $sp->get_pass_def_query;
    return 1 if !$passed_defq;

    return exists $passed_defq->{$element};
}

sub vec_sp_spatial_output_passed_defq {
    my ($self, %args) = @_;

    my $element = $args{element};

    my $bd      = $self->get_basedata_ref;
    my $sp_name = $args{output};

    my $cache = $self->get_cached_href('vec_sp_spatial_output_passed_defq');
    my $cache_key = join ':', (($sp_name // ''), ($element // "no\034element"));
    my $cached_ndarray = $cache->{$cache_key};

    return $cached_ndarray if $cached_ndarray;

    my $sp = $self->_get_sp_ref_for_defq_check(%args{output});

    croak "output argument not defined "
        . "or we are not being used for a spatial analysis\n"
        if !defined $sp;

    croak "element $element is not in spatial output\n"
        if defined $element && !$sp->exists_element_aa ($element);

    my $ndarray;

    my $passed_defq = $sp->get_pass_def_query;
    if (!$passed_defq) {
        say STDERR 'no def q';
        #  no defq so everything passes
        my $n = $bd->get_group_count;
        $ndarray = PDL->ones($n)->transpose;
    }
    elsif (defined $element) {
        my $n = $bd->get_group_count;
        $ndarray = ($passed_defq->{$element} ? PDL->ones($n) : PDL->zeroes($n))->transpose;
    }
    else {
        $ndarray = $self->_aggregate_hash_to_pdl($passed_defq);
    }

    $cache->{$cache_key} = $ndarray;
    return $ndarray;
}

sub _get_sp_ref_for_defq_check {
    my ($self, %args) = @_;

    my $sp_name = $args{output};

    my $sp;

    if (defined $sp_name) {
        my $bd = $self->get_basedata_ref;
        $sp = $bd->get_spatial_output_ref (name => $sp_name)
            or croak 'Spatial output $sp_name does not exist in basedata '
            . $bd->get_name
            . "\n";

        # make sure we aren't trying to access ourself
        my $my_name = $self->get_name;
        croak "def_query can't reference itself"
            if defined $my_name
                && $my_name eq $sp_name
                && $self->is_def_query;
    }
    else {
        # default to the caller spatial output
        $sp = $self->get_caller_spatial_output_ref;

        # make sure we aren't trying to access ourself
        croak "def_query can't reference itself"
            if $self->is_def_query;

    }

    return $sp;
}

sub set_caller_spatial_output_ref {
    my ($self, $ref) = @_;
    $self->set_param (SPATIAL_OUTPUT_CALLER_REF => $ref);
    $self->weaken_param ('SPATIAL_OUTPUT_CALLER_REF');
}

sub get_caller_spatial_output_ref {
    my $self = shift;
    return $self->get_param ('SPATIAL_OUTPUT_CALLER_REF');
}

sub get_metadata_sp_points_in_same_cluster {
    my $self = shift;

    my $examples = <<~'END_EXAMPLES'
        #  Try to use the highest four clusters from the root.
        #  Note that the next highest number will be used
        #  if four is not possible, e.g. there are five
        #  siblings below the root.  Fewer will be returned
        #  if the tree has insufficient tips.
        sp_points_in_same_cluster (
          output       => "some_cluster_output",
          num_clusters => 4,
        )

        #  Cut the tree at a distance of 0.25 from the tips
        sp_points_in_same_cluster (
          output          => "some_cluster_output",
          target_distance => 0.25,
        )

        #  Cut the tree at a depth of 3.
        #  The root is depth 1.
        sp_points_in_same_cluster (
          output          => "some_cluster_output",
          target_distance => 3,
          group_by_depth  => 1,
        )

        #  work from an arbitrary node
        sp_points_in_same_cluster (
          output       => "some_cluster_output",
          num_clusters => 4,
          from_node    => '118___',  #  use the node's name
        )

        #  target_distance is ignored if num_clusters is set
        sp_points_in_same_cluster (
          output          => "some_cluster_output",
          num_clusters    => 4,
          target_distance => 0.25,
        )

        END_EXAMPLES
    ;

    my %metadata = (
        description =>
            'Returns true when two points are within the same '
                . ' cluster or region grower group, or if '
                . ' neither point is in the selected clusters/groups.',
        required_args => [
            qw /output/,
        ],
        optional_args => [
            qw /
                num_clusters
                group_by_depth
                target_distance
                from_node
            /
        ],
        index_no_use => 1,
        result_type  => 'non_overlapping',
        example => $examples,
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_points_in_same_cluster {
    my $self = shift;
    my %args = @_;

    croak 'One of "num_clusters" or "target_distance" arguments must be defined'
        if !defined ($args{num_clusters} // $args{target_distance});

    my $cl_name = $args{output}
        // croak "Cluster output name not defined\n";

    my $h = $self->get_current_args;

    my $bd = $self->get_basedata_ref;

    my $element1 = $args{element1};
    my $element2 = $args{element2};
    #  only need to check existence if user passed the element names
    croak "element $element1 is not in basedata\n"
        if defined $element1 and not $bd->exists_group_aa ($element1);
    croak "element $element2 is not in basedata\n"
        if defined $element2 and not $bd->exists_group_aa ($element2);
    $element1 //= $h->{coord_id1};
    $element2 //= $h->{coord_id2};

    my $cl = $bd->get_cluster_output_ref (name => $cl_name)
        or croak "Spatial output $cl_name does not exist in basedata "
        . $bd->get_name
        . "\n";

    state $cache_name = 'sp_points_in_same_cluster_output_group';
    $cache_name   .= join $SUBSEP, %args{sort keys %args}; # $SUBSEP is \034 by default
    my $by_element = $self->get_cached_value ($cache_name);
    if (!$by_element) {
        my $root = defined $args{from_node}
            ? $cl->get_node_ref_aa($args{from_node})
            : $cl;
        #  tree object also caches
        my $target_nodes
            = $root->group_nodes_below (%args);
        foreach my ($node_name, $node) (%$target_nodes) {
            my $terminals = $node->get_terminal_elements;
            @$by_element{keys %$terminals} = ($node_name) x keys %$terminals;
        }
        $self->set_cached_value($cache_name => $by_element);
    }

    return ($by_element->{$element1} // $SUBSEP) eq ($by_element->{$element2} // $SUBSEP);
}

sub vec_sp_points_in_same_cluster {
    my $self = shift;
    my %args = @_;

    croak 'One of "num_clusters" or "target_distance" arguments must be defined'
        if !defined ($args{num_clusters} // $args{target_distance});

    my $cl_name = $args{output}
        // croak "Cluster output name not defined\n";

    my $h = $self->get_current_args;

    my $bd = $self->get_basedata_ref;

    my $element1 = $args{element1};
    #  only need to check existence if user passed the element name
    croak "element $element1 is not in basedata\n"
        if defined $element1 and not $bd->exists_group_aa ($element1);
    $element1 //= $h->{coord_id1};

    my $cl = $bd->get_cluster_output_ref (name => $cl_name)
        or croak "Spatial output $cl_name does not exist in basedata "
        . $bd->get_name
        . "\n";

    #  very similar to sp_points_in_same_cluster_output_group but we cache numbers not names
    state $cache_name = 'vec_sp_points_in_same_cluster_output_group';
    $cache_name   .= join $SUBSEP, %args{sort keys %args}; # $SUBSEP is \034 by default
    my $by_element = $self->get_cached_value ($cache_name);
    if (!$by_element) {
        my $root = defined $args{from_node}
            ? $cl->get_node_ref_aa($args{from_node})
            : $cl;
        #  tree object also caches
        my $target_nodes
            = $root->group_nodes_below (%args);
        foreach my ($node) (values %$target_nodes) {
            my $num = $node->get_node_number;
            my $terminals = $node->get_terminal_elements;
            @$by_element{keys %$terminals} = ($num) x keys %$terminals;
        }
        $self->set_cached_value($cache_name => $by_element);
    }

    my $cache_key_ndarray = "${cache_name} ndarray";
    my $ndarray = $self->get_cached_value($cache_key_ndarray) // do {
        #  elements outside clustered set will get a zero
        my $x = $self->_aggregate_hash_to_pdl($by_element);
        $self->set_cached_value ($cache_key_ndarray => $x);
        $x;
    };

    my $target = $by_element->{$element1};

    return $ndarray == $target;
}


sub get_metadata_sp_point_in_cluster {
    my $self = shift;

    my $examples = <<~'END_EXAMPLES';
    #  Use any element that is a terminal in the cluster output.
    #  This is useful if the cluster analysis was run under
    #  a definition query and you want the same set of groups.
    sp_point_in_cluster (
      output       => "some_cluster_output",
    )

    #  Now specify a cluster within the output
    sp_point_in_cluster (
      output       => "some_cluster_output",
      from_node    => '118___',  #  use the node's name
    )

    #  Specify an element to check instead of the current
    #  processing element.
    sp_point_in_cluster (
      output       => "some_cluster_output",
      from_node    => '118___',  #  use the node's name
      element      => '123:456', #  specify an element to check
    )

    END_EXAMPLES

    my %metadata = (
        description =>
            'Returns true when the group is in a '
                . ' cluster or region grower output cluster.',
        required_args => [
            qw /output/,
        ],
        optional_args => [qw /element from_node/],
        index_no_use => 1,
        result_type  => 'always_same',
        example => $examples,
        aggregate_substitute_method => {
            re_name => 'point_in_cluster',
            method  => '_aggregate_points_in_cluster',
        },
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_point_in_cluster {
    my $self = shift;
    my %args = @_;

    my $cl_name = $args{output}
        // croak "Cluster output name not defined\n";

    my $bd = $self->get_basedata_ref;

    croak "element $args{element} is not in basedata\n"
        if defined $args{element} and not $bd->exists_group_aa ($args{element});

    my $element = $self->get_current_coord_id;

    my $cl = $bd->get_cluster_output_ref (name => $cl_name)
        or croak "Spatial output $cl_name does not exist in basedata "
        . $bd->get_name
        . "\n";

    state $cache_name = 'sp_points_in_cluster_output_group';
    $cache_name   .= join $SUBSEP, %args{sort keys %args}; # $SUBSEP is \034 by default
    my $terminal_elements = $self->get_cached_value ($cache_name);
    if (!$terminal_elements) {
        my $root = defined $args{from_node}
            ? $cl->get_node_ref_aa($args{from_node})
            : $cl->get_root_node;
        #  tree object also caches
        $terminal_elements = $root->get_terminal_elements;
        $self->set_cached_value($cache_name => $terminal_elements);
    }

    return !!$terminal_elements->{$element};
}

sub _aggregate_points_in_cluster {
    my ($self, %args) = @_;

    #  no point continuing if no basedata
    my $bd = $self->get_basedata_ref // return;

    my $conditions = $self->get_conditions_nws;

    my $re = $self->get_regex (name => 'point_in_cluster');

    return if not $conditions =~ /$re/ms;

    my $negated = !!$+{negated};

    my $method_args_hash = $self->get_param ('METHOD_ARG_HASHES');
    my $method_name      = $+{method};
    my $method_args_text = $+{args};
    my $method_args  = $method_args_hash->{$method_name . $method_args_text} // {};

    my $cl_name = $method_args->{output}
        // croak "Cluster output name not defined\n";
    my $cl = $bd->get_cluster_output_ref (name => $cl_name)
        or croak "Spatial output $cl_name does not exist in basedata "
        . $bd->get_name
        . "\n";

    my $root = defined $method_args->{from_node}
        ? $cl->get_node_ref_aa($method_args->{from_node})
        : $cl->get_root_node;
    #  tree object caches
    my $terminal_elements = $root->get_terminal_elements;

    #  ensure values of 1
    my %intersects;
    @intersects{keys %$terminal_elements} = (1) x keys %$terminal_elements;

    $self->_return_aggregate_hash (\%intersects, $negated)
}


sub vec_sp_point_in_cluster {
    my ($self, %args) = @_;

    my $bd = $self->get_basedata_ref;

    my $cl_name = $args{output}
        // croak "Cluster output name not defined\n";
    my $cl = $bd->get_cluster_output_ref (name => $cl_name)
        or croak "Spatial output $cl_name does not exist in basedata "
        . $bd->get_name
        . "\n";

    my $cache = $self->get_cached_href ('vec_sp_points_in_cluster');
    my $cache_key = "$cl_name\034:\034" . ($args{from_node} // '');

    my $cached = $cache->{$cache_key};

    return $cached if defined $cached;

    my $root = defined $args{from_node}
        ? $cl->get_node_ref_aa($args{from_node})
        : $cl->get_root_node;
    #  tree object caches
    my $terminal_elements = $root->get_terminal_elements;

    #  ensure values of 1
    my %intersects;
    @intersects{keys %$terminal_elements} = (1) x keys %$terminal_elements;

    return $cache->{$cache_key} = $self->_aggregate_hash_to_pdl(\%intersects);
}

1;