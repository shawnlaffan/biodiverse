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

    my $bd      = $self->get_basedata_ref;
    my $sp_name = $args{output};
    my $sp;
    if (defined $sp_name) {
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

        return 1
            if !$self->is_def_query && $self->get_param('VERIFYING');
    }

    croak "output argument not defined "
        . "or we are not being used for a spatial analysis\n"
        if !defined $sp;

    croak "element $element is not in spatial output\n"
        if not $sp->exists_element_aa ($element);

    my $passed_defq = $sp->get_pass_def_query;
    return 1 if !$passed_defq;

    return exists $passed_defq->{$element};
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

    return wantarray ? %intersects : \%intersects;
}

1;