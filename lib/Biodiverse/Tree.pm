package Biodiverse::Tree;

#  Package to build and store trees.
#  includes clustering methods
use 5.010;

use Carp;
use strict;
use warnings;
use Scalar::Util qw /looks_like_number/;
use List::MoreUtils qw /first_index/;
use List::Util qw /sum min max uniq/;
use Ref::Util qw { :all };

use English qw ( -no_match_vars );

our $VERSION = '1.99_006';

our $AUTOLOAD;

use Statistics::Descriptive;
my $stats_class = 'Biodiverse::Statistics';

use Biodiverse::Metadata::Export;
my $export_metadata_class = 'Biodiverse::Metadata::Export';

use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';

use Biodiverse::Matrix;
use Biodiverse::TreeNode;
use Biodiverse::BaseStruct;
use Biodiverse::Progress;
use Biodiverse::Exception;

use parent qw /
  Biodiverse::Common
  /;    #/

my $EMPTY_STRING = q{};

#  useful for analyses that are of type tree - could be too generic a name?
sub is_tree_object {
    return 1;
}

sub new {
    my $class = shift;

    my $self = bless {}, $class;

    my %args = @_;

    # do we have a file to load from?
    my $file_loaded;
    if ( defined $args{file} ) {
        $file_loaded = $self->load_file(@_);
    }

    return $file_loaded if defined $file_loaded;

    my %PARAMS = (    #  default params
        TYPE                 => 'TREE',
        OUTSUFFIX            => __PACKAGE__->get_file_suffix,
        OUTSUFFIX_YAML       => __PACKAGE__->get_file_suffix_yaml,
        CACHE_TREE_AS_MATRIX => 1,
    );
    $self->set_params( %PARAMS, %args );
    $self->set_default_params;    #  load any user overrides

    $self->{TREE_BY_NAME} = {};

    #  avoid memory leak probs with circular refs to parents
    #  ensures children are destroyed when parent is destroyed
    $self->weaken_basedata_ref;

    return $self;
}

sub get_file_suffix {
    return 'bts';
}

sub get_file_suffix_yaml {
    return 'bty';
}

sub rename {
    my $self = shift;
    my %args = @_;

    my $name = $args{new_name};
    if ( not defined $name ) {
        croak "[Tree] Argument 'new_name' not defined\n";
    }

    #  first tell the basedata object
    #my $bd = $self->get_param ('BASEDATA_REF');
    #$bd->rename_output (object => $self, new_name => $name);

    # and now change ourselves
    $self->set_param( NAME => $name );

}

#  need to flesh this out - total length, summary stats of lengths etc
sub _describe {
    my $self = shift;

    my @description = ( 'TYPE: ' . blessed $self, );

    my @keys = qw /
      NAME
      /;

    foreach my $key (@keys) {
        my $desc = $self->get_param ($key);
        if (is_arrayref($desc)) {
            $desc = join q{, }, @$desc;
        }
        push @description, "$key: $desc";
    }

    push @description, "Node count: " . scalar @{ $self->get_node_refs };
    push @description,
      "Terminal node count: " . scalar @{ $self->get_terminal_node_refs };
    push @description,
      "Root node count: " . scalar @{ $self->get_root_node_refs };

    push @description, "Sum of branch lengths: " . sprintf "%.6g",
      $self->get_total_tree_length;
    push @description, "Longest path: " . sprintf "%.6g",
      $self->get_longest_path_to_tip;

    my $description = join "\n", @description;

    return wantarray ? @description : $description;
}

#  sometimes we have to clean up the topology from the top down for each root node
#  this will ultimately give us a single root node where that should be the case
sub set_parents_below {
    my $self = shift;

#my @root_nodes = $self->get_root_node_refs;
#
#foreach my $root_node ($self->get_root_node_refs) {
#    next if ! $root_node->is_root_node;  #  may have been fixed on a previous iteration, so skip it
#    $root_node->set_parents_below;
#}

    foreach my $node ( $self->get_node_refs ) {
        foreach my $child ( $node->get_children ) {
            $child->set_parent( parent => $node );
        }
    }

    return;
}

#  If no_delete_cache is true then the caller promises to clean up later.
#  This can be used to avoid multiple passes over the tree across multiple deletions.
sub delete_node {
    my $self = shift;
    my %args = @_;

    #  get the node ref
    my $node_ref = $self->get_node_ref( node => $args{node} );
    return if !defined $node_ref;    #  node does not exist anyway

    #  get the names of all descendents
    my %node_hash = $node_ref->get_all_descendants( cache => 0 );
    $node_hash{ $node_ref->get_name } = $node_ref;  #  add node_ref to this list

    #  Now we delete it from the treenode structure.
    #  This cleans up any children in the tree.
    $node_ref->get_parent->delete_child(
        child           => $node_ref,
        no_delete_cache => 1
    );

    #  now we delete it and its descendents from the node hash
    $self->delete_from_node_hash( nodes => \%node_hash );

    #  Now we clear the caches from those deleted nodes and those remaining
    #  This circumvents circular refs from the caches.
    if ( !$args{no_delete_cache} ) {
        foreach my $n_ref ( values %node_hash ) {
            $n_ref->delete_cached_values;
        }
        $self->delete_cached_values_below;
    }

    #  return a list of the names of those deleted nodes
    return wantarray ? keys %node_hash : [ keys %node_hash ];
}

sub delete_from_node_hash {
    my $self = shift;
    my %args = @_;

    if ( $args{node} ) {
        #  $args{node} implies single deletion
        delete $self->{TREE_BY_NAME}{ $args{node} };
    }

    return if !$args{nodes};

    my @list;
    if (is_hashref($args{nodes})) {
        @list = keys %{$args{nodes}};
    }
    elsif (is_arrayref($args{nodes})) {
        @list = @{$args{nodes}};
    }
    else {
        @list = $args{nodes};
    }
    delete @{ $self->{TREE_BY_NAME} }{@list};

    return;
}

#  add a new TreeNode to the hash, return it
sub add_node {
    my $self = shift;
    my %args = @_;
    my $node = $args{node_ref} || Biodiverse::TreeNode->new(@_);
    $self->add_to_node_hash( node_ref => $node );

    return $node;
}

sub add_to_node_hash {
    my $self     = shift;
    my %args     = @_;
    my $node_ref = $args{node_ref};
    my $name     = $node_ref->get_name;

    if ( $self->exists_node( name => $name ) ) {
        Biodiverse::Tree::NodeAlreadyExists->throw(
            message => "Node $name already exists in this tree\n",
            name    => $name,
        );
    }

    $self->{TREE_BY_NAME}{$name} = $node_ref;
    return $node_ref if defined wantarray;
}

sub rename_node {
    my $self = shift;
    my %args = @_;

    my $new_name = $args{new_name}
      // croak "new_name arg not passed";
    my $node_ref = $args{node_ref};

    my $old_name;
    if (!$node_ref) {
        $old_name = $args{old_name} // $args{node_name} // $args{name}
          // croak "old_name or node_ref arg not passed\n";
        $node_ref = $self->get_node_ref_aa ($old_name);
    }
    else {
        $old_name = $node_ref->get_name;
    }

    croak "Cannot rename over an existing node"
      if $self->exists_node(name => $new_name);

    $node_ref->rename (new_name => $new_name);
    $self->add_to_node_hash (node_ref => $node_ref);
    $self->delete_from_node_hash(node => $old_name);
    return;
}

#  does this node exist already?
sub exists_node {
    my $self = shift;
    my %args = @_;
    my $name = $args{name};
    if ( not defined $name ) {
        if ( defined $args{node_ref} ) {
            $name = $args{node_ref}->get_name;
        }
        else {
            croak 'neither name nor node_ref argument passed';
        }
    }
    return exists $self->{TREE_BY_NAME}{$name};
}

#  get a single root node - assumes we only care about one if we use this approach.
#  the sort ensures we get the same one each time.
sub get_tree_ref {
    my $self = shift;
    if ( !defined $self->{TREE} ) {
        my %root_nodes = $self->get_root_nodes;
        my @keys       = sort keys %root_nodes;
        return undef if not defined $keys[0];    #  no tree ref yet
        $self->{TREE} = $root_nodes{ $keys[0] };
    }
    return $self->{TREE};
}

sub get_tree_depth {    #  traverse the tree and calculate the maximum depth
                        #  need ref to the root node
    my $self     = shift;
    my $tree_ref = $self->get_tree_ref;
    return if !defined $tree_ref;
    return $tree_ref->get_depth_below;
}

sub get_tree_length {    # need ref to the root node
    my $self     = shift;
    my $tree_ref = $self->get_tree_ref;
    return if !defined $tree_ref;
    return $tree_ref->get_length_below;
}

#  this is going to supersede get_tree_length because it is a better name
sub get_length_to_tip {
    my $self = shift;

    return $self->get_tree_length;
}

#  an even better name than get_length_to_tip given what this does
sub get_longest_path_to_tip {
    my $self = shift;

    return $self->get_tree_length;
}

#  Get the terminal elements below this node
#  If not a TreeNode reference, then return a
#  hash ref containing only this node
sub get_terminal_elements {
    my $self = shift;
    my %args = ( cache => 1, @_ );    #  cache by default

    my $node = $args{node}
      || croak "node not specified in call to get_terminal_elements\n";

    my $node_ref = $self->get_node_ref( node => $node );

    return $node_ref->get_terminal_elements( cache => $args{cache} )
      if defined $node_ref;

    my %hash = ( $node => $node_ref );
    return wantarray ? %hash : \%hash;
}

sub get_terminal_element_count {
    my $self = shift;
    my %args = ( cache => 1, @_ );    #  cache by default

    my $node_ref;
    if ( defined $args{node} ) {
        my $node = $args{node};
        $node_ref = $self->get_node_ref( node => $node );
    }
    else {
        $node_ref = $self->get_tree_ref;
    }

    #  follow logic of get_terminal_elements, which returns a hash of
    #  node if not a ref - good or bad idea?  Ever used?
    return 1 if !defined $node_ref;

    return $node_ref->get_terminal_element_count( cache => $args{cache} );
}

sub get_node_ref {
    my $self = shift;
    my %args = @_;

    my $node = $args{node}
      // croak "node not specified in call to get_node_ref\n";

    if ( !exists $self->{TREE_BY_NAME}{$node} ) {

        #say "Couldn't find $node, the nodes actually in the tree are:";
        #foreach my $k (keys $self->{TREE_BY_NAME}) {
        #    say "key: $k";
        #}
        Biodiverse::Tree::NotExistsNode->throw("[Tree] $node does not exist");
    }

    return $self->{TREE_BY_NAME}{$node};
}

#  array args version of get_node_ref
sub get_node_ref_aa {
    my ( $self, $node ) = @_;

    croak "node not specified in call to get_node_ref\n"
      if !defined $node;

    no autovivification;

    return $self->{TREE_BY_NAME}{$node}
      // Biodiverse::Tree::NotExistsNode->throw("[Tree] $node does not exist");
}

#  used when importing from a BDX file, as they don't keep weakened refs weak.
#  not anymore - let the destroy method handle it
sub weaken_parent_refs {
    my $self      = shift;
    my $node_list = $self->get_node_hash;
    foreach my $node_ref ( values %$node_list ) {
        $node_ref->weaken_parent_ref;
    }
}

#  pre-allocate hash buckets for really large node hashes
#  and thus gain a minor speed improvement in such cases
sub set_node_hash_key_count {
    my $self  = shift;
    my $count = shift;

    croak "Count $count is not numeric" if !looks_like_number $count;

    my $node_hash = $self->get_node_hash;

    #  has no effect if $count is negative or
    #  smaller than current key count
    keys %$node_hash = $count;

    return;
}

sub get_node_count {
    my $self     = shift;
    my $hash_ref = $self->get_node_hash;
    return scalar keys %$hash_ref;
}

sub get_node_hash {
    my $self = shift;

    #  create an empty hash if needed
    $self->{TREE_BY_NAME} //= {};

    return wantarray ? %{ $self->{TREE_BY_NAME} } : $self->{TREE_BY_NAME};
}

sub get_node_refs {
    my $self = shift;
    my @refs = values %{ $self->get_node_hash };

    return wantarray ? @refs : \@refs;
}

#  get a hash on the node lengths indexed by name
sub get_node_length_hash {
    my $self = shift;
    my %args = ( cache => 1, @_ );

    my $use_cache = $args{cache};
    if ($use_cache) {
        my $cached_hash = $self->get_cached_value('NODE_LENGTH_HASH');
        return ( wantarray ? %$cached_hash : $cached_hash ) if $cached_hash;
    }

    my %len_hash;
    my $node_hash = $self->get_node_hash;
    foreach my $node_name ( keys %$node_hash ) {
        my $node_ref = $node_hash->{$node_name};
        $len_hash{$node_name} = $node_ref->get_length;
    }

    if ($use_cache) {
        $self->set_cached_value( NODE_LENGTH_HASH => \%len_hash );
    }

    return wantarray ? %len_hash : \%len_hash;
}

#  get a hash of node refs indexed by their total length
sub get_node_hash_by_total_length {
    my $self = shift;

    my %by_value;
    while ( ( my $node_name, my $node_ref ) =
        each( %{ $self->get_node_hash } ) )
    {
        #  uses total_length param if exists
        my $value = $node_ref->get_length_below;
        $by_value{$value}{$node_name} = $node_ref;
    }

    return wantarray ? %by_value : \%by_value;
}

#  get a hash of node refs indexed by their depth below (same order meaning as total length)
sub get_node_hash_by_depth_below {
    my $self = shift;

    my %by_value;
    while ( ( my $node_name, my $node_ref ) =
        each( %{ $self->get_node_hash } ) )
    {
        my $depth = $node_ref->get_depth_below;
        $by_value{$depth}{$node_name} = $node_ref;
    }
    return wantarray ? %by_value : \%by_value;
}

#  get a hash of node refs indexed by their depth
sub get_node_hash_by_depth {
    my $self = shift;

    my %by_value;
    while ( ( my $node_name, my $node_ref ) =
        each( %{ $self->get_node_hash } ) )
    {
        my $depth = $node_ref->get_depth;
        $by_value{$depth}{$node_name} = $node_ref;
    }

    return wantarray ? %by_value : \%by_value;
}

#  get a set of stats for one of the hash lists in the tree.
#  Should be called get_list_value_stats
#  should just return the stats object
#  Should also inherit from Biodiverse::BaseStruct::get_list_value_stats?
#  It is almost identical.
sub get_list_stats {
    my $self  = shift;
    my %args  = @_;
    my $list  = $args{list} || croak "List not specified\n";
    my $index = $args{index} || croak "Index not specified\n";

    my @data;
    foreach my $node ( values %{ $self->get_node_hash } ) {
        my $list_ref = $node->get_list_ref( list => $list );
        next if !defined $list_ref;
        next if !exists $list_ref->{$index};
        next if !defined $list_ref->{$index};    #  skip undef values

        push @data, $list_ref->{$index};
    }

    my %stats_hash = (
        MAX    => undef,
        MIN    => undef,
        MEAN   => undef,
        SD     => undef,
        PCT025 => undef,
        PCT975 => undef,
        PCT05  => undef,
        PCT95  => undef,
    );

    if ( scalar @data ) {    #  don't bother if they are all undef
        my $stats = $stats_class->new;
        $stats->add_data( \@data );

        %stats_hash = (
            MAX    => $stats->max,
            MIN    => $stats->min,
            MEAN   => $stats->mean,
            SD     => $stats->standard_deviation,
            PCT025 => scalar $stats->percentile(2.5),
            PCT975 => scalar $stats->percentile(97.5),
            PCT05  => scalar $stats->percentile(5),
            PCT95  => scalar $stats->percentile(95),
        );
    }

    return wantarray ? %stats_hash : \%stats_hash;
}

#  return 1 if the tree contains a node with the specified name
sub node_is_in_tree {
    my $self = shift;
    my %args = @_;

    my $node_name = $args{node};

    #  node cannot exist if it has no name...
    croak "node name undefined\n"
      if !defined $node_name;

    my $node_hash = $self->get_node_hash;
    return exists $node_hash->{$node_name};
}

sub get_terminal_nodes {
    my $self = shift;
    my %node_list;

    foreach my $node_ref ( values %{ $self->get_node_hash } ) {
        next if !$node_ref->is_terminal_node;
        $node_list{ $node_ref->get_name } = $node_ref;
    }

    return wantarray ? %node_list : \%node_list;
}

sub get_terminal_node_refs {
    my $self = shift;
    my @node_list;

    foreach my $node_ref ( values %{ $self->get_node_hash } ) {
        next if !$node_ref->is_terminal_node;
        push @node_list, $node_ref;
    }

    return wantarray ? @node_list : \@node_list;
}

#  don't cache these results as they can change as clusters are built
sub get_root_nodes {    #  if there are several root nodes
    my $self = shift;
    my %args = @_;

    my %node_list;
    my $node_hash = $self->get_node_hash;

    foreach my $node_ref ( values %$node_hash ) {
        next if !defined $node_ref;
        if ( $node_ref->is_root_node ) {
            $node_list{ $node_ref->get_name } = $node_ref;
        }
    }

    return wantarray ? %node_list : \%node_list;
}

sub get_root_node_refs {
    my $self = shift;

    my @refs = values %{ $self->get_root_nodes };

    return wantarray ? @refs : \@refs;
}

sub get_root_node {
    my $self = shift;

    my %root_nodes = $self->get_root_nodes;
    croak "More than one root node\n" if scalar keys %root_nodes > 1;

    my @refs          = values %root_nodes;
    my $root_node_ref = $refs[0];

    croak $root_node_ref->get_name . " is not a root node!\n"
      if !$root_node_ref->is_root_node;

    return wantarray ? %root_nodes : $root_node_ref;
}

#  get all nodes that aren't internal
sub get_named_nodes {
    my $self = shift;
    my %node_list;
    my $node_hash = $self->get_node_hash;
    foreach my $node_ref ( values %$node_hash ) {
        next if $node_ref->is_internal_node;
        $node_list{ $node_ref->get_name } = $node_ref;
    }
    return wantarray ? %node_list : \%node_list;
}

#  get all the nodes that aren't terminals
sub get_branch_nodes {
    my $self = shift;
    my %node_list;
    my $node_hash = $self->get_node_hash;
    foreach my $node_ref ( values %$node_hash ) {
        next if $node_ref->is_terminal_node;
        $node_list{ $node_ref->get_name } = $node_ref;
    }
    return wantarray ? %node_list : \%node_list;
}

sub get_branch_node_refs {
    my $self = shift;
    my @node_list;
    foreach my $node_ref ( values %{ $self->get_node_hash } ) {
        next if $node_ref->is_terminal_node;
        push @node_list, $node_ref;
    }
    return wantarray ? @node_list : \@node_list;
}

#  get an internal node name that is not currently used
sub get_free_internal_name {
    my $self = shift;
    my %args = @_;
    my $skip = $args{exclude} || {};

#  iterate over the existing nodes and get the highest internal name that isn't used
#  also check the whole translate table (keys and values) to ensure no
#    overlaps with valid user defined names
    my $node_hash    = $self->get_node_hash;
    my %reverse_skip = reverse %$skip;
    my $highest = $self->get_cached_value('HIGHEST_INTERNAL_NODE_NUMBER') // -1;
    my $name;

    while (1) {
        $highest++;
        $name = $highest . '___';
        last
          if !exists $node_hash->{$name}
          && !exists $skip->{$name}
          && !exists $reverse_skip{$name};
    }

    #foreach my $name (keys %$node_hash, %$skip) {
    #    if ($name =~ /^(\d+)___$/) {
    #        my $num = $1;
    #        next if not defined $num;
    #        $highest = $num if $num > $highest;
    #    }
    #}

    #$highest ++;
    $self->set_cached_value( HIGHEST_INTERNAL_NODE_NUMBER => $highest );

    #return $highest . '___';
    return $name;
}

sub get_unique_name {
    my $self   = shift;
    my %args   = @_;
    my $prefix = $args{prefix};
    my $suffix = $args{suffix} || q{__dup};
    my $skip   = $args{exclude} || {};

    #  iterate over the existing nodes and see if we can geberate a unique name
    #  also check the whole translate table (keys and values) to ensure no
    #    overlaps with valid user defined names
    my $node_hash = $self->get_node_hash;

    my $i           = 1;
    my $pfx         = $prefix . $suffix;
    my $unique_name = $pfx . $i;

    #my $exists = $skip ? {%$node_hash, %$skip} : $node_hash;

    while ( exists $node_hash->{$unique_name} || exists $skip->{$unique_name} )
    {
        $i++;
        $unique_name = $pfx . $i;
    }

    return $unique_name;
}

###########

sub export {
    my $self = shift;
    my %args = @_;
    
    croak "[TREE] Export:  Argument 'file' not specified or null\n"
      if not defined $args{file}
      || length( $args{file} ) == 0;

    #  get our own metadata...
    my $metadata = $self->get_metadata( sub => 'export' );

    my $sub_to_use = $metadata->get_sub_name_from_format(%args);

    #  remap the format name if needed - part of the matrices kludge
    my $component_map = $metadata->get_component_map;
    if ( $component_map->{ $args{format} } ) {
        $args{format} = $component_map->{ $args{format} };
    }

    eval { $self->$sub_to_use(%args) };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return;
}

sub get_metadata_export {
    my $self = shift;

    #  get the available lists
    #my @lists = $self->get_lists_for_export;

    #  need a list of export subs
    my %subs = $self->get_subs_with_prefix( prefix => 'export_' );

    #  (not anymore)
    my @formats;
    my %format_labels;    #  track sub names by format label

    #  loop through subs and get their metadata
    my %params_per_sub;
    my %component_map;

  LOOP_EXPORT_SUB:
    foreach my $sub ( sort keys %subs ) {
        my %sub_args = $self->get_args( sub => $sub );

        my $format = $sub_args{format};

        croak "Metadata item 'format' missing\n"
          if not defined $format;

        $format_labels{$format} = $sub;

        next LOOP_EXPORT_SUB
          if $sub_args{format} eq $EMPTY_STRING;

        my $params_array = $sub_args{parameters};

        #  Need to raise the matrices args
        #  This is extremely kludgy as it assumes there is only one
        #  output format for matrices
        if (is_hashref($params_array)) {
            my @values = values %$params_array;
            my @keys   = keys %$params_array;

            $component_map{$format} = shift @keys;
            $params_array = shift @values;
        }

        $params_per_sub{$format} = $params_array;

        push @formats, $format;
    }

    @formats = sort @formats;
    $self->move_to_front_of_list(
        list => \@formats,
        item => 'Nexus'
    );

    my %metadata = (
        parameters     => \%params_per_sub,
        format_choices => [
            bless(
                {
                    name       => 'format',
                    label_text => 'Format to use',
                    type       => 'choice',
                    choices    => \@formats,
                    default    => 0
                },
                $parameter_metadata_class
            ),
        ],
        format_labels => \%format_labels,
        component_map => \%component_map,
    );

    return $export_metadata_class->new( \%metadata );
}

sub get_lists_for_export {
    my $self = shift;

    my @sub_list
      ;    #  get a list of available sub_lists (these are actually hashes)
           #foreach my $list (sort $self->get_hash_lists) {
    foreach my $list ( sort $self->get_list_names_below ) {    #  get all lists
        if ( $list eq 'SPATIAL_RESULTS' ) {
            unshift @sub_list, $list;
        }
        else {
            push @sub_list, $list;
        }
    }
    unshift @sub_list, '(no list)';

    return wantarray ? @sub_list : \@sub_list;
}

sub get_metadata_export_nexus {
    my $self = shift;

    my @parameters = (
        {
            name       => 'use_internal_names',
            label_text => 'Label internal nodes',
            tooltip    => 'Should the internal node labels be included?',
            type       => 'boolean',
            default    => 1,
        },
        {
            name       => 'no_translate_block',
            label_text => 'Do not use a translate block',
            tooltip    => 'read.nexus in the R ape package mishandles '
              . 'named internal nodes if there is a translate block',
            type    => 'boolean',
            default => 0,
        },
        {
            name       => 'export_colours',
            label_text => 'Export colours',
            tooltip    => 'Include user defined colours (in the nexus comments blocks)',
            type       => 'boolean',
            default    => 0,
        },
    );
    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    my %args = (
        format     => 'Nexus',
        parameters => \@parameters,
    );

    return wantarray ? %args : \%args;
}

sub export_nexus {
    my $self = shift;
    my %args = @_;

    my $file = $args{file};
    say "[TREE] WRITING TO TREE TO NEXUS FILE $file";
    open( my $fh, '>', $file )
      || croak "Could not open file '$file' for writing\n";

    my $export_colours = $args{export_colours};
    my $sub_list_name  = $args{sub_list};
    my $comment_block_hash;
    if ($export_colours || defined $sub_list_name) {
        my %comments_block;
        my $node_refs = $self->get_node_refs;
        foreach my $node_ref (@$node_refs) {
            my $booter    = $node_ref->get_bootstrap_block;
            my $boot_text = $booter->encode_bootstrap_block(
                include_colour => $export_colours,
            );
            $comments_block{$node_ref->get_name} = $boot_text;
        }
        $comment_block_hash = \%comments_block;
    }
  
    print {$fh} $self->to_nexus(
        tree_name => $self->get_param('NAME'),
        %args,
        comment_block_hash => $comment_block_hash,
    );

    $fh->close;
    
    return 1;
}

sub get_metadata_export_newick {
    my $self = shift;

    my @parameters = (
            {
                name       => 'use_internal_names',
                label_text => 'Label internal nodes',
                tooltip    => 'Should the internal node labels be included?',
                type       => 'boolean',
                default    => 1,
            },
            #  Colours seem unsupported in figtree for newick files
            #{
            #    name       => 'export_colours',
            #    label_text => 'Export colours',
            #    tooltip    => 'Include the user defined colours (in the nexus bootstrap block)',
            #    type       => 'boolean',
            #    default    => 0,
            #},
        );

    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }  

    my %args = (
        format     => 'Newick',
        parameters => \@parameters,
    );

    return wantarray ? %args : \%args;
}

sub export_newick {
    my $self = shift;
    my %args = @_;

    my $file = $args{file};

    print "[TREE] WRITING TO TREE TO NEWICK FILE $file\n";

    open( my $fh, '>', $file )
      || croak "Could not open file '$file' for writing\n";

    print {$fh} $self->to_newick(%args);
    $fh->close;

    return 1;
}

sub get_metadata_export_shapefile {
    my $self = shift;

    my @parameters = (
        {
            name       => 'plot_left_to_right',
            label_text => 'Plot left to right',
            tooltip    => 'Should terminals be to the right of the root node? '
              . '(default is to the left, with the root node at the right).',
            type    => 'boolean',
            default => 0,
            tooltip => 'Should terminals be to the right of the root node? '
              . '(default is to the left, with the root node at the right).',
        },
        {
            name       => 'vertical_scale_factor',
            label_text => 'Vertical scale factor',
            type       => 'float',
            default    => 0,
            tooltip    => 'Control the tree plot height relative to its width '
              . '(longest path from root to tip).  '
              . 'A zero value will make the height equal the width.',
        },
        {
            type => 'comment',
            label_text =>
              'Note: To attach any lists you will need to run a second '
              . 'export to the delimited text format and then join them.  '
              . 'This is needed because shapefiles do not have an undefined value '
              . 'and field names can only be 11 characters long.',
        }
    );
    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    my %args = (
        format     => 'Shapefile',
        parameters => \@parameters,
    );

    return wantarray ? %args : \%args;
}

sub export_shapefile {
    my $self = shift;
    my %args = @_;

    my $file = $args{file};
    croak "file argument not passed\n"
      if !defined $file;

    print "[TREE] WRITING TO TREE TO SHAPEFILE $file\n";

    $file =~ s/\.shp$//;    #  the shp extension is added by the writer object

    $self->assign_plot_coords(
        plot_coords_left_to_right => $args{plot_left_to_right},
        plot_coords_scale_factor  => $args{vertical_scale_factor},
        scale_factor_is_relative  => 1,
    );

    use Geo::Shapefile::Writer;

    my $shp_writer = Geo::Shapefile::Writer->new(
        $file, 'POLYLINE',
        [ name      => 'C', 100 ],
        [ line_type => 'C', 20 ],
        [ length    => 'F', 16, 15 ],
        [ parent    => 'C', 100 ],
    );

  NODE:
    foreach my $node ( $self->get_node_refs ) {
        my $h_coords = $node->get_list_ref( list => 'PLOT_COORDS' );
        my $v_coords = $node->get_list_ref( list => 'PLOT_COORDS_VERT' );
        my $h_line   = [
            [ $h_coords->{plot_x1}, $h_coords->{plot_y1} ],
            [ $h_coords->{plot_x2}, $h_coords->{plot_y2} ],
        ];
        my $v_line = [
            [ $v_coords->{vplot_x1}, $v_coords->{vplot_y1} ],
            [ $v_coords->{vplot_x2}, $v_coords->{vplot_y2} ],
        ];
        my $type =
            $node->is_internal_node ? 'internal'
          : $node->is_terminal_node ? 'terminal'
          :                           'named internal';

        my $parent_name =
          $node->is_root_node ? q{} : $node->get_parent->get_name;

        $shp_writer->add_shape(
            [$h_line],
            {
                length    => $node->get_length,
                name      => $node->get_name,
                line_type => $type,
                parent    => $parent_name,
            },
        );

        next NODE
          if ( $v_coords->{vplot_y1} == $v_coords->{vplot_y2} );

        $shp_writer->add_shape(
            [$v_line],
            {
                length    => 0,
                name      => q{},
                line_type => 'vertical connector',
                parent    => q{},
            },
        );
    }

    $shp_writer->finalize();

    return 1;
}

sub get_metadata_export_tabular_tree {
    my $self = shift;

    my @parameters = (
        $self->get_lists_export_metadata(),
        $self->get_table_export_metadata(),
        {
            name       => 'include_plot_coords',
            label_text => 'Add plot coords',
            tooltip =>
'Allows the subsequent creation of, for example, shapefile versions of the dendrogram',
            type    => 'boolean',
            default => 1,
        },
        {
            name       => 'plot_coords_scale_factor',
            label_text => 'Plot coords scale factor',
            tooltip =>
'Scales the y-axis to fit the x-axis.  Leave as 0 for default (equalises axes)',
            type    => 'float',
            default => 0,
        },
        {
            name       => 'plot_coords_left_to_right',
            label_text => 'Plot tree from left to right',
            tooltip =>
'Leave off for default (plots as per labels and cluster tabs, root node at right, tips at left)',
            type    => 'boolean',
            default => 0,
        },
        {
            name       => 'export_colours',
            label_text => 'Export colours',
            tooltip    => 'Include the user defined colours (in the nexus bootstrap block)',
            type       => 'boolean',
            default    => 0,
        },
    );

    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    my %args = (
        format     => 'Tabular tree',
        parameters => \@parameters,
    );

    return wantarray ? %args : \%args;
}

#  generic - should be factored out
sub export_tabular_tree {
    my $self = shift;
    my %args = @_;

    my $name = $args{name};
    if ( !defined $name ) {
        $name = $self->get_param('NAME');
    }

    $args{use_internal_names} //=
      1;    #  we need this to be set for the round trip

    # show the type of what is being exported

    my $table = $self->to_table(
        symmetric          => 1,
        name               => $name,
        use_internal_names => 1,
        %args,
    );

    $self->write_table_csv( %args, data => $table );

    return 1;
}

sub get_metadata_export_table_grouped {
    my $self = shift;

    my @parameters = (
        $self->get_lists_export_metadata(),
        {
            name       => 'num_clusters',
            label_text => 'Number of groups',
            type       => 'integer',
            default    => 5
        },
        {
            name       => 'use_target_value',
            label_text => "Set number of groups\nusing a cutoff value",
            tooltip =>
'Overrides the "Number of groups" setting.  Uses length by default.',
            type    => 'boolean',
            default => 0,
        },
        {
            name       => 'target_value',
            label_text => 'Value for cutoff',
            tooltip    => 'Group the nodes using some threshold value.  '
              . 'This is analogous to the grouping when using '
              . 'the slider bar on the dendrogram plots.',
            type    => 'float',
            default => 0,
        },
        {
            name       => 'group_by_depth',
            label_text => "Group clusters by depth\n(default is by length)",
            tooltip =>
'Use depth to define the groupings.  When a cutoff is used, it will be in units of node depth.',
            type    => 'boolean',
            default => 0,
        },
        {
            name       => 'symmetric',
            label_text => 'Force output table to be symmetric',
            type       => 'boolean',
            default    => 1,
        },
        {
            name       => 'one_value_per_line',
            label_text => 'One value per line',
            tooltip    => 'Sparse matrix format',
            type       => 'boolean',
            default    => 0,
        },
        {
            name       => 'include_node_data',
            label_text => "Include node data\n(child counts etc)",
            type       => 'boolean',
            default    => 1,
        },
        {
            name       => 'sort_array_lists',
            label_text => 'Sort array lists',
            tooltip =>
'Should any array list results be sorted before exprting?  Turn this off if the original order is important.',
            type    => 'boolean',
            default => 1,
        },
        {
            name       => 'terminals_only',
            label_text => 'Export data for terminal nodes only',
            type       => 'boolean',
            default    => 1,
        },
        $self->get_table_export_metadata(),
    );

    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    my %args = (
        format     => 'Table grouped',
        parameters => \@parameters,
    );

    return wantarray ? %args : \%args;
}

sub export_table_grouped {
    my $self = shift;
    my %args = @_;

    my $file = $args{file};

    print
"[TREE] WRITING TO TREE TO TABLE STRUCTURE USING TERMINAL ELEMENTS, FILE $file\n";

    my $data = $self->to_table_group_nodes(@_);

    $self->write_table(
        %args,
        file => $file,
        data => $data
    );

    return 1;
}

#  Superseded by PE_RANGELIST index.
sub get_metadata_export_range_table {
    my $self = shift;
    my %args = @_;

    my $bd = $args{basedata_ref} || $self->get_param('BASEDATA_REF');

    #  hide from GUI if no $bd
    my $format = defined $bd ? 'Range table' : $EMPTY_STRING;
    $format = $EMPTY_STRING;    # no, just hide from GUI for now

    my @parameters = $self->get_table_export_metadata();
    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    my %metadata = (
        format     => $format,
        parameters => \@parameters,
    );

    return wantarray ? %metadata : \%metadata;
}

sub export_range_table {
    my $self = shift;
    my %args = @_;

    my $file = $args{file};

    print "[TREE] WRITING TREE RANGE TABLE, FILE $file\n";

    my $data =
      eval { $self->get_range_table( name => $self->get_param('NAME'), @_, ) };
    croak $EVAL_ERROR if $EVAL_ERROR;

    $self->write_table(
        %args,
        file => $file,
        data => $data,
    );

    return 1;
}

#  Grab all the basestruct export methods and add them here.
#  The key difference is that we now add "grouped" to the front of the methods.
#  We also then need to add the grouping metadata to the extracted metadata.
#  Override the additional list option to ensure we get the available lists in
#  the object being exported.
#  Hold that - might be simpler to create a temp basestruct and emulate the matrix kludge
#__PACKAGE__->_make_grouped_export_accessors();
#
#sub _make_grouped_export_accessors {
#    my ($pkg) = @_;
#
#    my $bs = Biodiverse::BaseStruct->new(
#        NAME => 'getting_export_methods',
#    );
#    my $metadata = $bs->get_metadata_export;
#
#    #use Data::Dump qw /pp/;
#    #pp $metadata;
#
#    no strict 'refs';
#    #while (my ($sub, $url) = each %$methods) {
#    #    *{$pkg. '::' .$sub} =
#    #        do {
#    #            sub {
#    #                my $gui = shift;
#    #                my $link = $url;
#    #                open_browser_and_show_url ($gui, $url);
#    #                return;
#    #            };
#    #        };
#    #}
#
#    return;
#}

sub get_lists_export_metadata {
    my $self = shift;

    my @lists = $self->get_lists_for_export;

    my $default_idx = 0;
    if ( my $last_used_list = $self->get_cached_value('LAST_SELECTED_LIST') ) {
        $default_idx = first_index { $last_used_list eq $_ } @lists;
    }

    my $metadata = [
        {
            name       => 'sub_list',
            label_text => 'List to export',
            type       => 'choice',
            choices    => \@lists,
            default    => $default_idx,
        }
    ];
    for (@$metadata) {
        bless $_, $parameter_metadata_class;
    }

    return wantarray ? @$metadata : $metadata;
}

sub get_table_export_metadata {
    my $self = shift;

    my @sep_chars =
      defined $ENV{BIODIVERSE_FIELD_SEPARATORS}
      ? @$ENV{BIODIVERSE_FIELD_SEPARATORS}
      : ( ',', 'tab', ';', 'space', ':' );

    my @quote_chars = qw /" ' + $/;    #"

    my $table_metadata_defaults = [
        {
            name => 'file',
            type => 'file'
        },
        {
            name       => 'sep_char',
            label_text => 'Field separator',
            tooltip =>
              'Suggested options are comma for .csv files, tab for .txt files',
            type    => 'choice',
            choices => \@sep_chars,
            default => 0
        },
        {
            name       => 'quote_char',
            label_text => 'Quote character',

            #tooltip    => 'For delimited text exports only',
            type    => 'choice',
            choices => \@quote_chars,
            default => 0
        },
    ];
    for (@$table_metadata_defaults) {
        bless $_, $parameter_metadata_class;
    }

    return wantarray ? @$table_metadata_defaults : $table_metadata_defaults;
}

#  get the maximum tree node position from zero
sub get_max_total_length {
    my $self = shift;

    my @lengths =
      reverse sort numerically keys %{ $self->get_node_hash_by_total_length };
    return $lengths[0];
}

sub get_total_tree_length {    #  calculate the total length of the tree
    my $self = shift;

    my $length;
    my $node_length;

    #check if length is already stored in tree object
    $length = $self->get_cached_value('TOTAL_LENGTH');
    return $length if defined $length;

    foreach my $node_ref ( values %{ $self->get_node_hash } ) {
        $node_length = $node_ref->get_length;
        $length += $node_length;
    }

    #  cache the result
    if ( defined $length ) {
        $self->set_cached_value( TOTAL_LENGTH => $length );
    }

    return $length;
}

#  convert a tree object to a matrix
#  values are the total length value of the lowest parent node that contains both nodes
#  generally excludes internal nodes
sub to_matrix {
    my $self         = shift;
    my %args         = @_;
    my $class        = $args{class} || 'Biodiverse::Matrix';
    my $use_internal = $args{use_internal};
    my $progress_bar = Biodiverse::Progress->new();

    my $name = $self->get_param('NAME');

    say "[TREE] Converting tree $name to matrix";

    my $matrix = $class->new( NAME => ( $args{name} || ( $name . "_AS_MX" ) ) );

    my %nodes = $self->get_node_hash;    #  make sure we work on a copy

    if ( !$use_internal ) {              #  strip out the internal nodes
        foreach my $node_name ( keys %nodes ) {
            if ( $nodes{$node_name}->is_internal_node ) {
                delete $nodes{$node_name};
            }
        }
    }

    my $progress;
    my $to_do = scalar keys %nodes;
    foreach my $node1 ( values %nodes ) {
        my $name1 = $node1->get_name;

        $progress++;

      NODE2:
        foreach my $node2 ( values %nodes ) {
            my $name2 = $node2->get_name;
            $progress_bar->update(
                "Converting tree $name to matrix\n($progress / $to_do)",
                $progress / $to_do,
            );

            next NODE2 if $node1 eq $node2;
            next NODE2
              if $matrix->element_pair_exists(
                element1 => $name1,
                element2 => $name2,
              );

            #my $shared_ancestor = $node1->get_shared_ancestor (node => $node2);
            #my $total_length = $shared_ancestor->get_total_length;
            #
            ##  should allow user to choose whether to just get length to shared ancestor?
            #my $path_length1 = $total_length - $node1->get_total_length;
            #my $path_length2 = $total_length - $node2->get_total_length;
            #my $path_length_total = $path_length1 + $path_length2;
            #
            #$matrix->add_element (
            #    element1 => $name1,
            #    element2 => $name2,
            #    value    => $path_length_total,
            #);

            my $last_ancestor = $self->get_last_shared_ancestor_for_nodes(
                node_names => { $name1 => 1, $name2 => 1 }, );

            my %path;
            foreach my $node_name ( $name1, $name2 ) {
                my $node_ref = $self->get_node_ref( node => $node_name );
                my $sub_path = $node_ref->get_path_lengths_to_ancestral_node(
                    ancestral_node => $last_ancestor,
                    %args,
                );
                @path{ keys %$sub_path } = values %$sub_path;
            }
            delete $path{ $last_ancestor->get_name() };
            my $path_length = sum values %path;
            $matrix->set_value(
                element1 => $name1,
                element2 => $name2,
                value    => $path_length,
            );
        }
    }

    return $matrix;
}

#  get table of the distances, range sizes and range overlaps between each pair of nodes
#  returns a table of values as an array
sub get_range_table {
    my $self = shift;
    my %args = @_;

    #my $progress_bar = $args{progress};
    my $progress_bar = Biodiverse::Progress->new();

    my $use_internal = $args{use_internal};    #  ignores them by default

    my $name = $self->get_param('NAME');

    #  gets the ranges from the basedata
    my $bd = $args{basedata_ref} || $self->get_param('BASEDATA_REF');

    croak "Tree has no attached BaseData object, cannot generate range table\n"
      if not defined $bd;

    my %nodes = $self->get_node_hash;          #  make sure we work on a copy

    if ( !$use_internal ) {                    #  strip out the internal nodes
        while ( my ( $name1, $node1 ) = each %nodes ) {
            if ( $node1->is_internal_node ) {
                delete $nodes{$name1};
            }
        }
    }

    my @results = [
        qw /Node1
          Node2
          Length1
          Length2
          P_dist
          Range1
          Range2
          Rel_range
          Range_shared
          Rel_shared
          /
    ];

    #declare progress tracking variables
    my ( %done, $progress, $progress_percent );
    my $to_do            = scalar keys %nodes;
    my $printed_progress = 0;

    # progress feedback to text window
    print "[TREE] CREATING NODE RANGE TABLE FOR TREE: $name  ";

    foreach my $node1 ( values %nodes ) {
        my $name1   = $node1->get_name;
        my $length1 = $node1->get_total_length;

        my $range_elements1 = $bd->get_range_union(
            labels => scalar $node1->get_terminal_elements );
        my $range1 =
            $node1->is_terminal_node
          ? $bd->get_range( element => $name1 )
          : scalar @$range_elements1
          ;    #  need to allow for labels positioned higher on the tree

        # progress feedback for text window and GUI
        $progress++;
        $progress_bar->update(
            "Converting tree $name to matrix\n" . "($progress / $to_do)",
            $progress / $to_do,
        );     #"

      LOOP_NODE2:
        foreach my $node2 ( values %nodes ) {
            my $name2 = $node2->get_name;

            next LOOP_NODE2 if $done{$name1}{$name2} || $done{$name2}{$name1};

            my $length2         = $node2->get_total_length;
            my $range_elements2 = $bd->get_range_union(
                labels => scalar $node2->get_terminal_elements );
            my $range2 =
                $node1->is_terminal_node
              ? $bd->get_range( element => $name2 )
              : scalar @$range_elements2;

            my $shared_ancestor = $node1->get_shared_ancestor( node => $node2 );
            my $length_ancestor = $shared_ancestor
              ->get_length;    #  need to exclude length of ancestor itself
            my $length1_to_ancestor =
              $node1->get_length_above( target_ref => $shared_ancestor ) -
              $length_ancestor;
            my $length2_to_ancestor =
              $node2->get_length_above( target_ref => $shared_ancestor ) -
              $length_ancestor;
            my $length_sum = $length1_to_ancestor + $length2_to_ancestor;

            my ( $range_shared, $range_rel, $shared_rel );

            if ( $range1 and $range2 )
            {  # only calculate range comparisons if both nodes have a range > 0
                if ( $name1 eq $name2 )
                { # if the names are the same, the shared range is the whole range
                    $range_shared = $range1;
                    $range_rel    = 1;
                    $shared_rel   = 1;
                }
                else {
                    #calculate shared range
                    my ( %tmp1, %tmp2 );

                    #@tmp1{@$range_elements1} = @$range_elements1;
                    @tmp2{@$range_elements2} = @$range_elements2;
                    delete @tmp2{@$range_elements1};
                    $range_shared = $range2 - scalar keys %tmp2;

                    #calculate relative range
                    my $greater_range =
                        $range1 > $range2
                      ? $range1
                      : $range2;
                    my $lesser_range =
                        $range1 > $range2
                      ? $range2
                      : $range1;
                    $range_rel = $lesser_range / $greater_range;

                    #calculate relative shared range
                    $shared_rel = $range_shared / $lesser_range;
                }
            }

            push @results,
              [
                $name1,               $name2,
                $length1_to_ancestor, $length2_to_ancestor,
                $length_sum,          $range1,
                $range2,              $range_rel,
                $range_shared,        $shared_rel
              ];
        }
    }

    return wantarray ? @results : \@results;
}

sub find_list_indices_across_nodes {
    my $self = shift;
    my %args = @_;

    my @lists = $self->get_hash_lists_below;

    my $bd = $self->get_param('BASEDATA_REF');
    my $indices_object = Biodiverse::Indices->new( BASEDATA_REF => $bd );

    my %calculations_by_index = $indices_object->get_index_source_hash;

    my %index_hash;

    #  loop over the lists and find those that are generated by a calculation
    #  This ensures we get all of them if subsets are used.
    foreach my $list_name (@lists) {
        if ( exists $calculations_by_index{$list_name} ) {
            $index_hash{$list_name} = $list_name;
        }
    }

    return wantarray ? %index_hash : \%index_hash;
}

#  Will return the root node if any nodes are not on the tree
sub get_last_shared_ancestor_for_nodes {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my @node_names = keys %{ $args{node_names} };

    return if !scalar @node_names;

    #my $node = $self->get_root_node;
    my $first_name = shift @node_names;
    my $first_node = $self->get_node_ref( node => $first_name );

    return $first_node if !scalar @node_names;

    my @reference_path = $first_node->get_path_to_root_node;
    my %ref_path_hash;
    @ref_path_hash{@reference_path} = ( 0 .. $#reference_path );

    my $common_anc_idx = 0;

  PATH:
    while ( my $node_name = shift @node_names ) {

        #  Must be just the root node left, so drop out.
        #  One day we will need to check for existence across all paths,
        #  as undefined ancestors can occur if we have multiple root nodes.
        last PATH if $common_anc_idx == $#reference_path;

        my $node_ref = $self->get_node_ref( node => $node_name );
        my @path = $node_ref->get_path_to_root_node;

        #  Start from an equivalent relative depth to avoid needless
        #  comparisons near terminals which cannot be ancestral.
        #  i.e. if the current common ancestor is at depth 3
        #  then anything deeper cannot be an ancestor.
        #  The pay-off is for larger trees.
        my $min = max( 0, $#path - $#reference_path + $common_anc_idx );
        my $max = $#path;
        my $found_idx;

        # run a binary search to find the lowest shared node
      PATH_NODE_REF_BISECT:
        while ( $max > $min ) {
            my $mid = int( ( $min + $max ) / 2 );

            my $idx = $ref_path_hash{ $path[$mid] };

            if ( defined $idx )
            {    #  we are in the path, try a node nearer the tips
                $max       = $mid;
                $found_idx = $idx;    #  track the index
            }
            else {    #  we are not in the path, try a node nearer the root
                $min = $mid + 1;
            }
        }

        #  Sometimes $max == $min and that's the one we want to use
        if ( $max == $min && !defined $found_idx ) {
            $found_idx = $ref_path_hash{ $path[$min] };
        }

        if ( defined $found_idx ) {
            $common_anc_idx = $found_idx;
        }
    }

    my $node = $reference_path[$common_anc_idx];

    return $node;
}

########################################################
#  Compare one tree object against another
#  Compares the similarity of the terminal elements using the Sorenson metric
#  Creates a new list in the tree object containing values based on the rand_compare
#  argument in the relevant indices
#  This is really designed for the randomisation procedure, but has more
#  general applicability.
#  As of issue #284, we optionally skip tracking the stats,
#  thus avoiding double counting since we compare the calculations per
#  node using a cloned tree
sub compare {
    my $self = shift;
    my %args = @_;

    #  make all numeric warnings fatal to catch locale/sprintf issues
    use warnings FATAL => qw { numeric };

    my $comparison = $args{comparison}
      || croak "Comparison not specified\n";

    my $track_matches    = !$args{no_track_matches};
    my $track_node_stats = !$args{no_track_node_stats};
    my $terminals_only   = $args{terminals_only};
    my $comp_precision   = $args{comp_precision} // '%.10f';

    my $result_list_pfx = $args{result_list_name};
    if ( !$track_matches ) {    #  avoid some warnings lower down
        $result_list_pfx //= q{};
    }

    croak "Comparison list name not specified\n"
      if !defined $result_list_pfx;

    my $result_data_list                  = $result_list_pfx . "_DATA";
    my $result_identical_node_length_list = $result_list_pfx . "_ID_LDIFFS";

    my $progress = Biodiverse::Progress->new();
    my $progress_text
      = sprintf "Comparing %s with %s\n",
      $self->get_param('NAME'),
      $comparison->get_param('NAME');
    $progress->update( $progress_text, 0 );

    #print "\n[TREE] " . $progress_text;

    #  set up the comparison operators if it has spatial results
    my $has_spatial_results =
      defined $self->get_list_ref( list => 'SPATIAL_RESULTS', );
    my %base_list_indices;

    if ( $track_matches && $has_spatial_results ) {

        %base_list_indices = $self->find_list_indices_across_nodes;
        $base_list_indices{SPATIAL_RESULTS} = 'SPATIAL_RESULTS';

        foreach my $list_name ( keys %base_list_indices ) {
            $base_list_indices{$list_name} =
              $result_list_pfx . '>>' . $list_name;
        }

    }

#  now we chug through each node, finding its most similar comparator node in the other tree
#  we store the similarity value as a measure of cluster reliability and
#  we then use that node to assess how goodthe spatial results are
    my $min_poss_value = 0;
    my $max_poss_value = 1;
    my %compare_nodes  = $comparison->get_node_hash;    #  make sure it's a copy
    my %done;
    my %found_perfect_match;

    my $to_do = max( $self->get_node_count, $comparison->get_node_count );
    my $i = 0;

    #my $last_update = [gettimeofday];

  BASE_NODE:
    foreach my $base_node ( $self->get_node_refs ) {
        $i++;
        $progress->update( $progress_text . "(node $i / $to_do)", $i / $to_do );

        my %base_elements  = $base_node->get_terminal_elements;
        my $base_node_name = $base_node->get_name;
        my $min_val        = $max_poss_value;
        my $most_similar_node;

        #  A small optimisation - if they have the same name then
        #  they can often have the same terminals so this will
        #  reduce the search times
        my @compare_name_list = keys %compare_nodes;
        if ( exists $compare_nodes{$base_node_name} ) {
            unshift @compare_name_list, $base_node_name;
        }

      COMP:
        foreach my $compare_node_name (@compare_name_list) {
            next if exists $found_perfect_match{$compare_node_name};
            my $sorenson = $done{$compare_node_name}{$base_node_name}
              // $done{$base_node_name}{$compare_node_name};

            if ( !defined $sorenson )
            {    #  if still not defined then it needs to be calculated
                my %comp_elements =
                  $compare_nodes{$compare_node_name}->get_terminal_elements;
                my %union_elements = ( %comp_elements, %base_elements );
                my $abc = scalar keys %union_elements;
                my $a =
                  ( scalar keys %base_elements ) +
                  ( scalar keys %comp_elements ) -
                  $abc;
                $sorenson = 1 - ( ( 2 * $a ) / ( $a + $abc ) );
                $done{$compare_node_name}{$base_node_name} = $sorenson;
            }

            if ( $sorenson <= $min_val ) {
                $min_val           = $sorenson;
                $most_similar_node = $compare_nodes{$compare_node_name};
                carp $compare_node_name if !defined $most_similar_node;
                if ( $sorenson == $min_poss_value ) {

                    #  cannot be related to another node
                    if ($terminals_only) {
                        $found_perfect_match{$compare_node_name} = 1;
                    }
                    else {
                        #  If its length is same then we have perfect match
                        my $len_comp =
                          $self->set_precision_aa(
                            $compare_nodes{$compare_node_name}->get_length,
                            $comp_precision, );
                        my $len_base =
                          $self->set_precision_aa( $base_node->get_length,
                            $comp_precision, );
                        if ( $len_comp eq $len_base ) {
                            $found_perfect_match{$compare_node_name} =
                              $len_base;
                        }

                        #else {say "$compare_node_name, $len_comp, $len_base"}
                    }
                    last COMP;
                }
            }
            carp "$compare_node_name $sorenson $min_val"
              if !defined $most_similar_node;
        }

        next BASE_NODE if !$track_matches;

        if ($track_node_stats) {
            $base_node->add_to_lists( $result_data_list => [$min_val] );
            my $stats = $stats_class->new;

            $stats->add_data(
                $base_node->get_list_ref( list => $result_data_list ) );
            my $prev_stat =
              $base_node->get_list_ref( list => $result_list_pfx );
            my %stats = (
                MEAN            => $stats->mean,
                SD              => $stats->standard_deviation,
                MEDIAN          => $stats->median,
                Q25             => scalar $stats->percentile(25),
                Q05             => scalar $stats->percentile(5),
                Q01             => scalar $stats->percentile(1),
                COUNT_IDENTICAL => ( $prev_stat->{COUNT_IDENTICAL} || 0 ) +
                  ( $min_val == $min_poss_value ? 1 : 0 ),
                COMPARISONS => ( $prev_stat->{COMPARISONS} || 0 ) + 1,
            );
            $stats{PCT_IDENTICAL} =
              100 * $stats{COUNT_IDENTICAL} / $stats{COMPARISONS};

            my $length_diff =
              ( $min_val == $min_poss_value )
              ? [ $base_node->get_total_length -
                  $most_similar_node->get_total_length ]
              : [];    #  empty array by default

            $base_node->add_to_lists(
                $result_identical_node_length_list => $length_diff );

            $base_node->add_to_lists( $result_list_pfx => \%stats );
        }

        if ($has_spatial_results) {
          BY_INDEX_LIST:
            while ( my ( $list_name, $result_list_name ) =
                each %base_list_indices )
            {

                my $base_ref = $base_node->get_list_ref( list => $list_name, );

                my $comp_ref =
                  $most_similar_node->get_list_ref( list => $list_name, );
                next BY_INDEX_LIST if !defined $comp_ref;

                my $results =
                  $base_node->get_list_ref( list => $result_list_name, )
                  || {};

                $self->compare_lists_by_item(
                    base_list_ref    => $base_ref,
                    comp_list_ref    => $comp_ref,
                    results_list_ref => $results,
                );

                #  add list to the base_node if it's not already there
                if (
                    !defined $base_node->get_list_ref(
                        list => $result_list_name ) )
                {
                    $base_node->add_to_lists( $result_list_name => $results );
                }
            }
        }
    }

    $self->set_last_update_time;

    return scalar keys %found_perfect_match;
}

sub convert_comparisons_to_significances {
    my $self = shift;
    my %args = @_;

    my $result_list_pfx = $args{result_list_name};
    croak qq{Argument 'result_list_name' not specified\n}
      if !defined $result_list_pfx;

    my $progress      = Biodiverse::Progress->new();
    my $progress_text = "Calculating significances";
    $progress->update( $progress_text, 0 );

    # find all the relevant lists for this target name
    my @target_list_names = grep { $_ =~ /^$result_list_pfx>>(?!p_rank>>)/ }
      $self->get_hash_list_names_across_nodes;

    my $i = 0;
  BASE_NODE:
    foreach my $base_node ( $self->get_node_refs ) {

        $i++;

        #$progress->update ($progress_text . "(node $i / $to_do)", $i / $to_do);

      BY_INDEX_LIST:
        foreach my $list_name (@target_list_names) {
            my $result_list_name = $list_name;
            $result_list_name =~ s/>>/>>p_rank>>/;

            my $comp_ref = $base_node->get_list_ref( list => $list_name, );
            next BY_INDEX_LIST if !defined $comp_ref;

            #  this will autovivify it
            my $result_list_ref =
              $base_node->get_list_ref( list => $result_list_name, );
            if ( !$result_list_ref ) {
                $result_list_ref = {};
                $base_node->add_to_lists(
                    $result_list_name => $result_list_ref,
                    use_ref           => 1,
                );
            }

            $self->get_sig_rank_from_comp_results(
                comp_list_ref    => $comp_ref,
                results_list_ref => $result_list_ref,    #  do it in-place
            );
        }
    }
}

sub reintegrate_after_parallel_randomisations {
    my $self = shift;
    my %args = @_;

    my $to = $self;  #  save some editing below, as this used to be in BaseData.pm
    my $from = $args{from}
      // croak "'from' argument not defined";

    my $r = $args{randomisations_to_reintegrate}
      // croak "'randomisations_to_reintegrate' argument undefined";
    
    #  should add some sanity checks here?
    #  currently they are handled by the caller,
    #  assuming it is a Basedata reintegrate call
    
    #  messy
    my @randomisations_to_reintegrate = uniq @{$args{randomisations_to_reintegrate}};
    my $rand_list_re_text
      = '^(?:'
      . join ('|', @randomisations_to_reintegrate)
      . ')>>(?!p_rank>>)';
    my $re_rand_list_names = qr /$rand_list_re_text/;

    my $node_list = $to->get_node_refs;
    my @rand_lists =
        grep {$_ =~ $re_rand_list_names}
        $to->get_hash_list_names_across_nodes;

    foreach my $list_name (@rand_lists) {
        foreach my $to_node (@$node_list) {
            my $node_name = $to_node->get_name;
            my $from_node = $from->get_node_ref(node => $node_name);
            my %l_args = (list => $list_name);
            my $lr_to   = $to_node->get_list_ref (%l_args);
            my $lr_from = $from_node->get_list_ref (%l_args);
            my %all_keys;
            #  get all the keys due to ties not being tracked in all cases
            @all_keys{keys %$lr_from, keys %$lr_to} = undef;
            my %p_keys;
            @p_keys{grep {$_ =~ /^P_/} keys %all_keys} = undef;

            #  we need to update the C_ and Q_ keys first,
            #  then recalculate the P_ keys
            foreach my $key (grep {not exists $p_keys{$_}} keys %all_keys) {
                no autovivification;  #  don't pollute the from data set
                $lr_to->{$key} += ($lr_from->{$key} // 0),
            }
            foreach my $key (keys %p_keys) {
                no autovivification;  #  don't pollute the from data set
                my $index = $key;
                $index =~ s/^P_//;
                $lr_to->{$key} = $lr_to->{"C_$index"} / $lr_to->{"Q_$index"};
            }            
        }
        $to->convert_comparisons_to_significances (
            result_list_name => $list_name,
        );
    }

    foreach my $to_node (@$node_list) {
        my $from_node = $from->get_node_ref (node => $to_node->get_name);

        foreach my $rand_name (@randomisations_to_reintegrate) {
            #  need to handle the data lists
            my $data_list_name = $rand_name . '_DATA';
            my $data = $from_node->get_list_ref (list => $data_list_name, autovivify => 0);
            $to_node->add_to_lists ($data_list_name => $data);

            my $stats = $stats_class->new;

            my $stats_list_name = $rand_name;
            my $to_stats_prev   = $to_node->get_list_ref (list => $stats_list_name);
            my $from_stats_prev = $from_node->get_list_ref (list => $stats_list_name);

            $stats->add_data ($to_node->get_list_ref (list => $data_list_name));
            my %stats_hash = (
                MEAN   => $stats->mean,
                SD     => $stats->standard_deviation,
                MEDIAN => $stats->median,
                Q25    => scalar $stats->percentile (25),
                Q05    => scalar $stats->percentile (5),
                Q01    => scalar $stats->percentile (1),
                COUNT_IDENTICAL
                       => (($to_stats_prev->{COUNT_IDENTICAL}   // 0)
                         + ($from_stats_prev->{COUNT_IDENTICAL} // 0)),
                COMPARISONS
                       => (($to_stats_prev->{COMPARISONS}   // 0)
                         + ($from_stats_prev->{COMPARISONS} // 0)),
            );
            $stats_hash{PCT_IDENTICAL}
              = 100 * $stats_hash{COUNT_IDENTICAL} / $stats_hash{COMPARISONS};

            #  use_ref to override existing
            $to_node->add_to_lists ($stats_list_name => \%stats_hash, use_ref => 1);  
    
            my $list_name = $rand_name . '_ID_LDIFFS';
            my $from_id_ldiffs = $from_node->get_list_ref (list => $list_name);
            $to_node->add_to_lists (
                $list_name => $from_id_ldiffs,
            );
        }
    }

    return;
}


sub get_hash_list_names_across_nodes {
    my $self = shift;

    my %list_names;
    foreach my $node ( $self->get_node_refs ) {
        my $lists = $node->get_hash_lists;
        @list_names{@$lists} = ();
    }

    my @names = sort keys %list_names;

    return wantarray ? @names : \@names;
}

sub trees_are_same {
    my $self = shift;
    my %args = @_;

    my $exact_match_count = $self->compare( %args, no_track_matches => 1 );

    my $comparison = $args{comparison}
      || croak "Comparison not specified\n";

    my $node_count_self = $self->get_node_count;
    my $node_count_comp = $comparison->get_node_count;
    my $trees_match     = $node_count_self == $node_count_comp
      && $exact_match_count == $node_count_self;

    return $trees_match;
}

#  does this tree contain a second tree as a sub-tree
sub contains_tree {
    my $self = shift;
    my %args = @_;

    my $exact_match_count = $self->compare( %args, no_track_matches => 1 );

    my $comparison = $args{comparison}
      || croak "Comparison not specified\n";

    my $node_count_comp = $comparison->get_node_count;
    if ( $args{ignore_root} ) {
        $node_count_comp--;
    }
    my $correction += $args{correction} // 0;
    $node_count_comp += $correction;

    my $contains = $exact_match_count == $node_count_comp;

    return $contains;
}

#  trim a tree to remove nodes from a set of names, or those not in a set of names
sub trim {
    my $self = shift;
    my %args = (
        delete_internals => 1,    #  delete internals by default
        @_,                       #  if they have no named children to keep
    );

    say '[TREE] Trimming';

    my $delete_internals = $args{delete_internals};

    my %tree_node_hash = $self->get_node_hash;

    #  Get keep and trim lists and convert to hashes as needs dictate
    #  those to keep
    my $keep = $self->array_to_hash_keys( list => $args{keep} || {} );
    my $trim = $args{trim};    #  those to delete

 #  If the keep list is defined, and the trim list is not defined,
 #    then we work with all named nodes that don't have children we want to keep
    if ( !defined $args{trim} && defined $args{keep} ) {

      NAME:
        foreach my $name ( keys %tree_node_hash ) {
            next NAME if exists $keep->{$name};

            my $node = $tree_node_hash{$name};

            next NAME if $node->is_internal_node;
            next NAME if $node->is_root_node;      #  never delete the root node

            my %children =
              $node->get_names_of_all_descendants;    #  make sure we use a copy
            my $child_count = scalar keys %children;
            delete @children{ keys %$keep };

  #  If none of the descendents are in the keep list then we can trim this node.
  #  Otherwise add this node and all of its ancestors to the keep list.
            if ( $child_count == scalar keys %children ) {
                $trim->{$name} = $node;
            }
            else {
                my $ancestors = $node->get_path_to_root_node;
                foreach my $ancestor (@$ancestors) {
                    $keep->{ $ancestor->get_name }++;
                }
            }
        }
    }
    $trim //= {};
    my %trim_hash = $self->array_to_hash_keys( list => $trim );  #  makes a copy

    #  we only want to consider those not being explicitly kept (included)
    my %candidate_node_hash = %tree_node_hash;
    delete @candidate_node_hash{ keys %$keep };

    my %deleted_h;
    my $i        = 0;
    my $to_do    = scalar keys %candidate_node_hash;
    my $progress = Biodiverse::Progress->new( text => 'Deletions' );

  DELETION:
    foreach my $name ( keys %candidate_node_hash ) {
        $i++;

        #  we might have deleted a named parent,
        #  so this node no longer exists in the tree
        next DELETION if $deleted_h{$name} || !exists $trim_hash{$name};

        $progress->update( "Checking nodes ($i / $to_do)", $i / $to_do, );

        #  delete if it is in the list to exclude
        my @deleted_nodes =
          $self->delete_node( node => $name, no_delete_cache => 1 );
        @deleted_h{@deleted_nodes} = (1) x scalar @deleted_nodes;
    }

    $progress->close_off;
    my $deleted_count = scalar keys %deleted_h;
    say "[TREE] Deleted $deleted_count nodes ", join ' ', sort keys %deleted_h;

    #  delete any internal nodes with no named descendents
    my $deleted_internal_count = 0;
    if ( $delete_internals and scalar keys %deleted_h ) {
        say '[TREE] Cleaning up internal nodes';

        my %node_hash = $self->get_node_hash;
        $to_do = scalar keys %node_hash;
        my %deleted_hash;
        my $i;

      NODE:
        foreach my $name ( keys %node_hash ) {
            $i++;

            my $node = $node_hash{$name};
            next NODE if $deleted_hash{$node};       #  already deleted
            next NODE if !$node->is_internal_node;
            next NODE if $node->is_root_node;

            $progress->update( "Checking nodes ($i / $to_do)", $i / $to_do, );

  #  need to ignore any cached descendants (and we cleanup the cache lower down)
            my $children = $node->get_all_descendants( cache => 0 );
          DESCENDANT:
            foreach my $child ( keys %$children ) {
                my $child_node = $children->{$child};
                next NODE if !$child_node->is_internal_node;
            }

            #  might have already been deleted, so wrap in an eval
            my @deleted_names = eval {
                $self->delete_node( node => $name, no_delete_cache => 1 ) };
            @deleted_hash{@deleted_names} = (1) x @deleted_names;
        }
        $progress->close_off;

        $deleted_internal_count = scalar keys %deleted_hash;
        say
"[TREE] Deleted $deleted_internal_count internal nodes with no named descendents";
    }

    #  now some cleanup
    if ( $deleted_internal_count || $deleted_count ) {
        $self->delete_param('TOTAL_LENGTH')
          ;    #  need to clear this up in old trees
        $self->delete_cached_values;

        #  This avoids circular refs in the ones that were deleted
        foreach my $node ( values %tree_node_hash ) {
            $node->delete_cached_values;
        }
        $self
          ->delete_cached_values_below;   #  and clear the remaining node caches
    }
    $keep = undef;    #  was leaking - not sure it matters, though

    say '[TREE] Trimming completed';

    $progress = undef;

    return $self;
}

sub numerically { $a <=> $b }

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self) || $self;

    #or croak "$self is not an object\n";

    my $method = $AUTOLOAD;
    $method =~ s/.*://;    # strip fully-qualified portion

    #  seem to be getting destroy issues - let the system take care of it.
    #    return if $method eq 'DESTROY';

    my $root_node = $self->get_tree_ref;

    croak 'No root node' if !$root_node;

    if ( defined $root_node and $root_node->can($method) ) {

        #print "[TREE] Using AUTOLOADER method $method\n";
        return $root_node->$method(@_);
    }
    else {
        Biodiverse::NoMethod->throw(
            method  => $method,
            message => "$self cannot call method $method"
        );

      #croak "[$type (TREE)] No root node and/or cannot access method $method, "
      #    . "tried AUTOLOADER and failed\n";
    }

    return;
}

#  collapse tree to a polytomy a set distance above the tips
#  assumes ultrametric tree
# the only args are:
#   cutoff_absolute - the depth from the tips of the tree at which to cut in units of branch length
#   or cutoff_relative - the depth from the tips of the tree at which to cut as a proportion
#   of the total tree depth.
#   if both parameters are given, cutoff_relative overrides cutoff_absolute

sub collapse_tree {
    my $self = shift;    # expects a Tree object
    my %args = @_;

    my $cutoff = $args{cutoff_absolute};
    my $verbose = $args{verbose} // 1;

    my $total_tree_length = $self->get_tree_length;

    if ( defined $args{cutoff_relative} ) {
        my $cutoff_relative = $args{cutoff_relative};
        croak 'cutoff_relative argument must be between 0 and 1'
          if $cutoff_relative < 0 || $cutoff_relative > 1;

        $cutoff = $cutoff_relative * $total_tree_length;
    }

    my ( $zero_count, $shorter_count );

    my %node_hash = $self->get_node_hash;

    if ($verbose) {
        say "[TREE] Total length: $total_tree_length";
        say '[TREE] Node count: ' . ( scalar keys %node_hash );
    }

    my $node;

    my %new_node_lengths;

    #  first pass - calculate the new lengths
  NODE_NAME:
    foreach my $name ( sort keys %node_hash ) {
        $node = $node_hash{$name};

        #my $new_branch_length;

        my $node_length   = $node->get_length;
        my $length_to_tip = $node->get_length_below; #  includes length of $node
        my $upper_bound   = $length_to_tip;
        my $lower_bound = $length_to_tip - $node_length;

        my $type;

        # whole branch is inside the limit - no change
        next NODE_NAME if $upper_bound < $cutoff;

        # whole of branch is outside limit - set branch length to 0
        if ( $lower_bound >= $cutoff ) {
            $new_node_lengths{$name} = 0;
            $zero_count++;
            $type = 1;
        }

        # part of branch is outside limit - shorten branch
        else {
            $new_node_lengths{$name} = $cutoff - $lower_bound;
            $shorter_count++;
            $type = 2;
        }
    }

    #  second pass - apply the new lengths
    foreach my $name ( keys %new_node_lengths ) {
        $node = $node_hash{$name};

        my $new_length;

        if ( $new_node_lengths{$name} == 0 ) {
            $new_length =
              $node->is_terminal_node ? ( $total_tree_length / 10000 ) : 0;
        }
        else {
            $new_length = $new_node_lengths{$name};
        }

        $node->set_length( length => $new_length );

        if ($verbose) {
            say "$name: new length is $new_length";
        }
    }

    $self->delete_cached_values;
    $self->delete_cached_values_below;

    #  reset all the total length values
    $self->reset_total_length;
    $self->get_total_tree_length;

    my @now_empty = $self->flatten_tree;

    #  now we clean up all the empty nodes in the other indexes
    if ($verbose) {
        say "[TREE] Deleting " . scalar @now_empty . ' empty nodes';
    }

    #foreach my $now_empty (@now_empty) {
    $self->delete_from_node_hash( nodes => \@now_empty ) if scalar @now_empty;

    #  rerun the resets - prob overkill
    $self->delete_cached_values;
    $self->delete_cached_values_below;
    $self->reset_total_length;
    $self->get_total_tree_length;

    if ($verbose) {
        say '[TREE] Total length: ' . $self->get_tree_length;
        say '[TREE] Node count: ' . $self->get_node_count;
    }

    return $self;
}

sub reset_total_length {
    my $self = shift;

    #  older versions had this as a param
    $self->delete_param('TOTAL_LENGTH');
    $self->delete_cached_value('TOTAL_LENGTH');

    #  avoid recursive recursion and its quadratic nastiness
    #$self->reset_total_length_below;
    foreach my $node ( $self->get_node_refs ) {
        $node->reset_total_length;
    }

    return;
}

#  collapse all nodes below a cutoff so they form a set of polytomies
sub collapse_tree_below {
    my $self = shift;
    my %args = @_;

    my $target_hash = $self->group_nodes_below(%args);

    foreach my $node ( values %$target_hash ) {
        my %terminals = $node->get_terminal_node_refs;
        my @children  = $node->get_children;
      CHILD_NODE:
        foreach my $desc_node (@children) {
            next CHILD_NODE if $desc_node->is_terminal_node;
            eval { $self->delete_node( node => $desc_node->get_name ); };
        }

        #  still need to ensure they are in the node hash
        $node->add_children( children => [ sort values %terminals ] );

        #print "";
    }

    return 1;
}

#  root an unrooted tree using a zero length node.
sub root_unrooted_tree {
    my $self = shift;

    my @root_nodes = $self->get_root_node_refs;

    return if scalar @root_nodes <= 1;

    my $name = $self->get_free_internal_name;
    my $new_root_node = $self->add_node( length => 0, name => $name );

    $new_root_node->add_children( children => \@root_nodes );

    @root_nodes = $self->get_root_node_refs;
    croak "failure\n" if scalar @root_nodes > 1;

    return;
}

sub shuffle_no_change {
    my $self = shift;
    return $self;
}

#  users should make a clone before doing this...
sub shuffle_terminal_names {
    my $self = shift;
    my %args = @_;

    my $target_node = $args{target_node} // $self->get_root_node;

    my $node_hash = $self->get_node_hash;
    my %reordered = $target_node->shuffle_terminal_names(%args);

    #  place holder for nodes that will change
    my %tmp;
    while ( my ( $old, $new ) = each %reordered ) {
        $tmp{$new} = $node_hash->{$old};
    }

    #  and now we override the old with the new
    @{$node_hash}{ keys %tmp } = values %tmp;

    $self->delete_cached_values;
    $self->delete_cached_values_below;

    return if !defined wantarray;
    return wantarray ? %reordered : \%reordered;
}

sub clone_tree_with_equalised_branch_lengths {
    my $self = shift;
    my %args = @_;

    my $name = $args{name} // ( $self->get_param('NAME') . ' EQ' );

    my $non_zero_len = $args{node_length};

    if ( !defined $non_zero_len ) {
        my $non_zero_node_count = grep { $_->get_length } $self->get_node_refs;
        $non_zero_len =
          $self->get_total_tree_length / ( $non_zero_node_count || 1 );
    }

    my $new_tree = $self->clone;
    $new_tree->delete_cached_values;

    #  reset all the total length values
    $new_tree->reset_total_length;

    #$new_tree->reset_total_length_below;

    foreach my $node ( $new_tree->get_node_refs ) {
        my $len = $node->get_length ? $non_zero_len : 0;
        $node->set_length( length => $len );
        $node->delete_cached_values;
        my $sub_list_ref = $node->get_list_ref( list => 'NODE_VALUES' );
        delete $sub_list_ref->{_y};    #  the GUI adds these - should fix there
        delete $sub_list_ref->{total_length_gui};
        my $null;
    }
    $new_tree->rename( new_name => $name );

    return $new_tree;
}

sub clone_tree_with_rescaled_branch_lengths {
    my $self = shift;
    my %args = @_;

    my $name = $args{name} // ( $self->get_param('NAME') . ' RS' );

    my $new_length = $args{new_length} || 1;

    my $scale_factor = $args{scale_factor};
    $scale_factor //=
      $new_length / ( $self->get_longest_path_length_to_terminals || 1 );

    my $new_tree = $self->clone;
    $new_tree->delete_cached_values;

    #  reset all the total length values
    $new_tree->reset_total_length;
    $new_tree->reset_total_length_below;

    foreach my $node ( $new_tree->get_node_refs ) {
        my $len = $node->get_length * $scale_factor;
        $node->set_length( length => $len );
        $node->delete_cached_values;
        my $sub_list_ref = $node->get_list_ref( list => 'NODE_VALUES' );
        delete $sub_list_ref->{_y};    #  the GUI adds these - should fix there
        delete $sub_list_ref->{total_length_gui};

        #my $null;
    }
    $new_tree->rename( new_name => $name );

    return $new_tree;
}

#  Let the system take care of most of the memory stuff.
sub DESTROY {
    my $self = shift;

    $self->delete_cached_values;    #  clear the cache
    if ( $self->{TREE_BY_NAME} ) {
        foreach my $node ( $self->get_node_refs ) {
            next if !defined $node;
            $node->delete_cached_values;
        }
    }

    #my $name = $self->get_param ('NAME');
    #print "DELETING $name\n";
    $self->set_param( BASEDATA_REF => undef )
      ;    #  clear the ref to the parent basedata object

    $self->{TREE}         = undef;    # empty the ref to the tree
    $self->{TREE_BY_NAME} = undef;    #  empty the list of nodes
                                      #print "DELETED $name\n";
    return;
}

# takes a hash mapping names of nodes currently in this tree to
# desired names, renames nodes accordingly.
sub remap_labels_from_hash {
    my $self       = shift;
    my %args       = @_;
    my $remap_hash = $args{remap};
    no autovivification;

    foreach my $r ( keys %$remap_hash ) {
        next if !$self->exists_node (name => $r);

        my $new_name = $remap_hash->{$r};
        $self->rename_node (
            old_name => $r,
            new_name => $new_name,
        );

        #my $this_node = $self->{TREE_BY_NAME}{$r};
        ##  we might have already remapped it or it does not exist
        ##  (can happen for multiple tree imports)
        #next if !$this_node;
        #
        #$this_node->set_name( name => $new_name );
        #
        #if ( !$self->exists_node( name => $new_name ) ) {
        #    $self->add_to_node_hash( node_ref => $this_node );
        #}
    }

    # clear all cached values
    foreach my $node ( $self->get_node_refs ) {
        $node->delete_cached_values;
    }
    $self->delete_cached_values;
    $self->delete_cached_values_below;

}

# wrapper around get_named_nodes for the purpose of polymorphism in
# the auto-remap logic.
sub get_labels {
    my $self = shift;
    my $named_nodes = $self->get_named_nodes;
    return wantarray ? keys %$named_nodes : [keys %$named_nodes];
}

1;

__END__

=head1 NAME

Biodiverse::????

=head1 SYNOPSIS

  use Biodiverse::????;
  $object = Biodiverse::Statistics->new();

=head1 DESCRIPTION

TO BE FILLED IN

=head1 METHODS

=over

=item remap_labels_from_hash

Given a hash mapping from names of labels currently in this tree to
desired new names, renames the labels accordingly.

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
