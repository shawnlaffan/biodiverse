package Biodiverse::TreeNode;

use strict;
use warnings;
no warnings 'recursion';

use English ( -no_match_vars );

use Carp;
use Scalar::Util qw /weaken isweak blessed/;
use Data::Dumper qw/Dumper/;
use List::Util qw /min/;

use Biodiverse::BaseStruct;

use base qw /Biodiverse::Common/;

our $VERSION = '0.18_007';

my $EMPTY_STRING = q{};
my $SPACE = q{ };

our $default_length = 0;

#  create and manipulate tree elements in a cluster object
#  structure was based on that used for the NEXUS library, but with some extra caching to help biodiverse methods
#  base structure was a hash with keys for:
#       PARENT    => ref to parent node.  Null if root.
#       LENGTH    => length to parent
#       DEPTH     => depth in tree from root
#       _CHILDREN => array of nodes below this in the tree
#       NAME      => name of the element - link event number in the case of non-leaf nodes

sub new {
    my $class = shift;
    my %args = @_;
    my %params = ( _CHILDREN => [] );
    my $self = \%params;

    bless $self, $class;

    #  now we loop through and add any specified arguments
    $self->set_length(%args);

    if (exists $args{parent}) {
        $self->set_parent(%args);
    }

    if (exists $args{children}) {
        $self->add_children(%args);
    }

    $self->set_name(%args);

    return $self;
}

#  set any value - allows user specified additions to the core stuff
sub set_value {
    my $self = shift;
    my %args = @_;
    @{$self->{NODE_VALUES}}{keys %args} = values %args;
    #foreach my $key (keys %args) {
    #    $self->{NODE_VALUES}{$key} = $args{$key};
    #}
    
    return;
}

sub get_value {
    my $self = shift;
    my $key = shift;
    
    return exists $self->{NODE_VALUES}{$key}
        ? $self->{NODE_VALUES}{$key}
        : undef;
}


sub delete_values {
    my $self = shift;
    my %args = @_;
    delete $self->{NODE_VALUES}{keys %args};
    #foreach my $key (@{$args{keys}}) {
    #    delete $self->{NODE_VALUES}{$key};
    #}
    
    return;
}

#sub get_value_keys {
#    my $self = shift;
#    return keys %{$self};
#}

#  set any value - allows user specified additions to the core stuff
sub set_cached_value {
    my $self = shift;
    my %args = @_;
    @{$self->{_cache}}{keys %args} = values %args;
    #foreach my $key (keys %args) {
    #    $self->{_cache}{$key} = $args{$key};
    #}
    
    return;
}

sub get_cached_value {
    my $self = shift;
    my $key = shift;
    return if ! exists $self->{_cache};
    return $self->{_cache}{$key} if exists $self->{_cache}{$key};
    return;
}

sub get_cached_value_keys {
    my $self = shift;
    
    return if ! exists $self->{_cache};
    
    return wantarray
        ? keys %{$self->{_cache}}
        : [keys %{$self->{_cache}}];
}

#  clear cached values at this node
#  argument keys is an array ref of keys to delete
sub delete_cached_values {
    my $self = shift;
    my %args = @_;
    
    return if ! exists $self->{_cache};
    
    #no warnings 'uninitialized';
    #if ((blessed $self->{_cache}{_cluster_colour}) =~ /Gtk2/) {
    #    print Data::Dumper::Dumper ($self->{_cache}{_cluster_colour});
    #}
    
    my $keys = $args{keys} || $self->get_cached_value_keys;
    return if not defined $keys or scalar @$keys == 0;

    delete @{$self->{_cache}}{@$keys};
    delete $self->{_cache} if scalar keys %{$self->{_cache}} == 0;
    
    #warn "Cache deletion problem at node " . $self->get_name . "\n$EVAL_ERROR\n"
    #  if $EVAL_ERROR;
    
    #warn "XXXXXXX "  . $self->get_name . "\n" if exists $self->{_cache};
    
    return;
}

#  was trying to avoid memory leaks, to no avail
#use Sub::Current;  
#use feature 'current_sub';

sub delete_cached_values_below {
    my $self = shift;
    my %args = @_;

    #  this approach seems to avoid memory leaks
    my %descendents = $self->get_all_descendents (cache => 0);
    foreach my $node (values %descendents) {
        $node->delete_cached_values (%args);
    }
    $self->delete_cached_values (%args);

    return;
}


sub set_name {
    my $self = shift;
    my %args = @_;
    croak "name argument missing\n" if not exists ($args{name});
    #$self->{0name_for_debug} = $args{name}; #  temporary
    $self->{NODE_VALUES}{NAME} = $args{name};
    
    return;
}

sub get_name {
    my $self = shift;
    #my %args = @_;
    croak "name parameter missing\n" if not exists ($self->{NODE_VALUES}{NAME});
    return $self->{NODE_VALUES}{NAME};
}

sub set_length {
    my $self = shift;
    my %args = @_;
    #croak 'length argument missing' if not exists ($args{length});
    $self->{NODE_VALUES}{LENGTH} = $args{length} // $default_length;

    return;
}

sub get_length {
    my $self = shift;
    return defined $self->{NODE_VALUES}{LENGTH} ? $self->{NODE_VALUES}{LENGTH} : $default_length;
}

#  loop through all the parent nodes and sum their lengths up to a target node (root by default)
#  should be renamed to get_length_to_root
sub get_length_above {  
    my $self = shift;
    
    my %args = @_;
    
    no warnings qw /uninitialized/;
    
    return $self->get_length
        if $self->is_root_node
            || $self eq $args{target_ref}
            || $self->get_name eq $args{target_node};    
    
    return $self->get_length
            + $self->get_parent->get_length_above (%args);
}

sub set_child_lengths {
    my $self = shift;
    my %args = @_;
    my $minValue = $args{total_length};
    defined $minValue || croak "[TREENODE] argument total_length not specified\n";
    
    foreach my $child ($self->get_children) {
        #if ($child->get_total_length != $minValue) {
        #    print "Length already defined, node ", $child->get_name, "\n";
        #}
        $child->set_value (TOTAL_LENGTH => $minValue);
        if ($child->is_terminal_node) {
            $child->set_length (length => $minValue);
        }
        else {
            my $grandChild = @{$child->get_children}[0];  #ERROR ERROR???
            $child->set_length (length => $minValue - $grandChild->get_total_length);
        }
    }

    return;
}

#  sometimes we need to reset the total length value, eg after cutting a tree
sub reset_total_length {
    my $self = shift;
    $self->set_value (TOTAL_LENGTH => undef);
}

sub reset_total_length_below {
    my $self = shift;
    
    $self->reset_total_length;
    foreach my $child ($self->get_children) {
        $child->reset_total_length;
    }

}


sub get_total_length {
    my $self = shift;
    
    #  use the stored value if exists
    my $tmp = $self->get_value ('TOTAL_LENGTH');
    return $tmp if defined $tmp;
    return $self->get_length_below;  #  calculate total length otherwise
}

#  get the maximum tree node position from zero
sub get_max_total_length {
    my $self = shift;
    my %args = @_;

    return $self->get_total_length if $self->is_terminal_node;  # no children

    if ($args{cache}) {  #  lots of conditions, but should save a little number crunching overall.
        my $cached_length = $self->get_cached_value ('MAX_TOTAL_LENGTH');
        return $cached_length if defined $cached_length;
    }

    my $max_length = $self->get_total_length;
    foreach my $child (@{$self->get_children}) {
        my $child_length = $child->get_max_total_length (%args) || 0;  #  pass on the args

        $max_length = $child_length if $child_length > $max_length;
    }

    if ($args{cache}) {
        $self->set_cached_value (MAX_TOTAL_LENGTH => $max_length);
    }

    return $max_length;
}

#  includes the length of the current node, so totalLength = lengthBelow+lengthAbove-selfLength
sub get_length_below {  
    my $self = shift;
    my %args = (cache => 1, @_);  #  defaults to caching


    return $self->get_length if $self->is_terminal_node;  # no children

    if ($args{cache}) {  #  lots of conditions, but should save a little number crunching overall.
        my $cached_length = $self->get_cached_value ('LENGTH_BELOW');
        return $cached_length if defined $cached_length;
    }

    my $max_length_below = 0;
    foreach my $child ($self->get_children) {
        my $length_below_child = $child->get_length_below (%args) || 0;

        if ($length_below_child > $max_length_below) {
            $max_length_below = $length_below_child;
        }
    }

    my $length = $self->get_length + $max_length_below;

    if ($args{cache}) {
        $self->set_cached_value (LENGTH_BELOW => $length);
    }

    return $length;
}


sub set_depth {
    my $self = shift;
    my %args = @_;
    return if ! exists ($args{depth});
    $self->{NODE_VALUES}{DEPTH} = $args{depth};
}

sub get_depth {
    my $self = shift;

    #return $self->{DEPTH} if defined $self->{DEPTH}; # overwrite as needed - saves messing about with cached values
    
    if ($self->is_root_node) {
        $self->set_depth(depth => 0);
    }
    else {
        #  recursively search up the tree
        $self->set_depth(depth => ($self->get_parent->get_depth + 1));
    }
    
    return $self->{NODE_VALUES}{DEPTH};
}

sub get_depth_below {  #  gets the deepest depth below the caller in total tree units
    my $self = shift;
    my %args = (cache => 1, @_);
    return $self->get_depth if $self->is_terminal_node;  # no elements, return its depth
    
    if ($args{cache}) {  #  lots of conditions, but should save a little number crunching overall.
        my $cached_value = $self->get_cached_value ('DEPTH_BELOW');
        return $cached_value if defined $cached_value;
    }

    my $maxDepthBelow = 0;
    foreach my $child (@{$self->get_children}) {
        my $depthBelowChild = $child->get_depth_below;
        $maxDepthBelow = $depthBelowChild if $depthBelowChild > $maxDepthBelow;
    }
    
    $self->set_cached_value (DEPTH_BELOW => $maxDepthBelow) if $args{cache};
    
    return $maxDepthBelow;
}

sub add_children {
    my $self = shift;
    my %args = @_;
    
    return if ! exists ($args{children});  #  should croak
    
    croak "TreeNode WARNING: children argument not an array ref\n"
      if ref($args{children}) !~ /ARRAY/;

    CHILD:
    foreach my $child (@{$args{children}}) {
        next if $self->has_child (node_ref => $child);  #  don't re-add our own child
        if ($self->is_tree_node(node => $child)) {
            if (defined $child->get_parent) {  #  too many parents - this is a single parent system
                if ($args{warn}) {
                    print 'TreeNode WARNING: child '
                          . $self->get_name .
                          " already has parent, resetting\n";
                }
                $child->get_parent->delete_child (child => $child);
            }
        }
        #  not a tree node, and not a ref, so make it one
        my $tmp;
        if (! $self->is_tree_node(node => $child)) {
            if (! ref($child)) {
                $tmp = Biodiverse::TreeNode->new(name => $child);
                $child = $tmp;
            }
            else {
                croak "Warning: Cannot add $child as a child - already a blessed object\n";
                next CHILD;
            }
        }
        push @{$self->{_CHILDREN}}, $child;
        $child->set_parent(parent => $self);
    }
    
    return;
}

sub has_child {
    my $self = shift;
    my %args = @_;
    my $node_ref = $args{node_ref} || croak "missing node_ref argument\n";

    my @children = $self->get_children;

    foreach my $child (@children) {
        return 1 if $child eq $node_ref;
    }

    return;
}

sub delete_child {  #  remove a child from a list.
    my $self = shift;
    my %args = @_;
    my $i = 0;
    foreach my $child ($self->get_children) {
        if ($child eq $args{child}) {
            splice (@{$self->{_CHILDREN}}, $i, 1);
            $child->delete_cached_values_below;
            return 1;
        }
        $i++;
    }

    return;  #  return undefined if nothing removed
}

sub delete_children {
    my $self = shift;
    my %args = @_;
    croak "children argument not specified or not an array ref"
        if ! defined $args{children} || ! ref ($args{children}) =~ /ARRAY/;
    my $count = 0;
    foreach my $child (@{$args{children}}) {
        #  function returns 1 if it deletes something, undef otherwise
        $count ++ if (defined $self->delete_child (child => $child));
    }
    return $count;
}

sub get_children {
    my $self = shift;
    return if not defined $self->{_CHILDREN};
    my @children = @{$self->{_CHILDREN}}; #  messy, but seeing if we can avoid mem leaks
    return wantarray ? @children : \@children;
}

sub get_child_count {
    my $self = shift;
    return $#{$self->{_CHILDREN}} + 1;
}
    
# should be get_terminal_node_count
# same as get_terminal_element_count, so just pass it on
sub get_child_count_below {
    my $self = shift;
    return $self->get_terminal_element_count (@_);
}


#  get a hash of the nodes below this one based on length
#  accounts for recursion in the tree
sub group_nodes_below {
    my $self = shift;
    my %args = @_;
    my $groups_needed = $args{num_clusters} || $self->get_child_count_below;
    my %search_hash;
    my %final_hash;

    my $use_depth = $args{group_by_depth};  #  alternative is by length
    #  a second method by which it may be passed
    $use_depth = 1 if defined $args{type} && $args{type} eq 'depth';
    #print "[TREENODE] Grouping by ", $use_depth ? "depth" : "length", "\n";

    my $target_value = $args{target_value};
    #$target_value = 1 if defined $target_value;  #  for debugging
    #print "[TREENODE] Target is $target_value\n" if defined $target_value;

    $final_hash{$self->get_name} = $self;

    if ($self->is_terminal_node) {
        return wantarray ? %final_hash : \%final_hash;
    }

    #my @current_nodes = ($self);
    my @current_nodes;

    my $upper_value = $use_depth ? $self->get_depth : $self->get_length_below;
    my $lower_value = $use_depth ? $self->get_depth + 1 : $self->get_length_below - $self->get_length;
    ($lower_value, $upper_value) = sort numerically ($lower_value, $upper_value) if ! $use_depth; 
    $search_hash{$lower_value}{$upper_value}{$self->get_name} = $self;

    if (defined $target_value) {  #  check if we have all we need
        if ($use_depth && $target_value <= $lower_value && $target_value >= $upper_value) {
            return wantarray ? %final_hash : \%final_hash;
        }
        elsif ($target_value > $lower_value && $target_value <= $upper_value) {
            return wantarray ? %final_hash : \%final_hash;
        }
    }


    my $group_count = 1;
    NODE_SEARCH: while ($group_count < $groups_needed) {
        @current_nodes = values %{$search_hash{$lower_value}{$upper_value}};
        #print "check $i $upper_value\n"; 
        my $current_node_string = join ($EMPTY_STRING, sort @current_nodes);
        foreach my $current_node (@current_nodes) {
            my @children = $current_node->get_children;

            CNODE: foreach my $child (@children) {
                my $include_in_search = 1;  #  flag to include this child in further searching
                my ($upper_bound, $lower_bound);
                
                if ($child->is_terminal_node) {
                    $include_in_search = 0;
                }
                else {  #  only consider length if it has children
                    #  and that length is from its children
                    if ($use_depth) {
                        $upper_bound = $child->get_depth;
                        $lower_bound = $upper_bound + 1;
                    }
                    else {
                        $upper_bound = $child->get_cached_value ('UPPER_BOUND_LENGTH');
                        if (defined $upper_bound) {
                            $lower_bound = $child->get_cached_value ('LOWER_BOUND_LENGTH');
                        }
                        else {
                            my $length = $child->get_length;
                            if ($length < 0) {  # recursion
                                my $parent = $child->get_parent;
                                #  parent_pos is wherever its children begin
                                my $parent_pos = $parent->get_length_below - $parent->get_length;
                                $upper_bound = min ($parent_pos, $child->get_length_below);
                                $lower_bound = min ($parent_pos, $child->get_length_below - $length);
                            }
                            else {
                                $upper_bound = $child->get_length_below;
                                $lower_bound = $child->get_length_below - $length;
                            }
                            $child->set_cached_value (UPPER_BOUND_LENGTH => $upper_bound);
                            $child->set_cached_value (LOWER_BOUND_LENGTH => $lower_bound);

                            #  swap them if they are inverted (eg for depth)
                            ($lower_bound, $upper_bound) = sort numerically ($lower_bound, $upper_bound);
                        }
                    }

                    #  don't add to search hash if we're happy with this one
                    if (defined $target_value) {
                        if ($use_depth && $target_value <= $lower_bound && $target_value >= $upper_bound) {
                            $include_in_search = 0;
                        }
                        elsif ($target_value > $lower_bound && $target_value <= $upper_bound) {
                            $include_in_search = 0;
                        }
                    }
                }

                if ($include_in_search) {
                    #  add to the values hash if it bounds the target value or it is not specified
                    $search_hash{$lower_bound}{$upper_bound}{$child->get_name} = $child;
                }    

                $final_hash{$child->get_name} = $child;  #  add this child node to the tracking hashes        
                delete $final_hash{$child->get_parent->get_name};
                #  clear parent from length consideration
                delete $search_hash{$lower_value}{$upper_value}{$current_node->get_name};
            }
            delete $search_hash{$lower_value}{$upper_value} if ! scalar keys %{$search_hash{$lower_value}{$upper_value}};
            delete $search_hash{$lower_value} if ! scalar keys %{$search_hash{$lower_value}};
        }
        last if ! scalar keys %search_hash;  #  drop out - they must all be terminal nodes

        $lower_value = (reverse sort numerically keys %search_hash)[0];
        $upper_value = (reverse sort numerically keys %{$search_hash{$lower_value}})[0];

        #print scalar keys %final_hash, "\n";

        $group_count = scalar keys %final_hash;
    }

    #print scalar keys %final_hash, "\n";
    return wantarray ? %final_hash : \%final_hash;
}

#  reduce the number of tree nodes by promoting children with zero length difference
#  from their parents
# potentially inefficient, as it starts from the top several times, but does avoid
#  deep recursion this way (unless the tree really is that deep...)
sub flatten_tree {
    my $self = shift;
    my $iter = 0;
    my $count = 1;
    my @empty_nodes;
    print "[TREENODE] FLATTENING TREE.  ";
    while ($count > 0) {
        my %raised = $self->raise_zerolength_children;
        print " Raised $raised{raised_count},";
        $iter ++;
        push @empty_nodes, @{$raised{empty_node_names}};
        $count = $raised{raised_count};
    }
    print "\n";
    return wantarray ? @empty_nodes : \@empty_nodes;
}

#  raise any zero length children to be children of the parents (siblings of this node).
#  return a hash containing the count of the children raised and an array of any now empty nodes
sub raise_zerolength_children {
    my $self = shift;
    
    my %results = (empty_node_names => [],
                   raised_count => 0,
                  );
    
    if ($self->is_terminal_node) {
        return wantarray ? %results : \%results;
    };
    
    my $child_count = $#{$self->get_children} + 1;
    
    if (! $self->is_root_node) {
        #  raise all children with length zero to be children of the parent node
        #  no - make that those with the same total length as their parent
        foreach my $child ($self->get_children) {
            #$child_count ++;
            #next if $self->is_root_node;
            #if ($child->get_length == 0) {
            if ($child->get_total_length == $self->get_total_length) {
                #  add_children takes care of the parent refs
                $self->get_parent->add_children(children => [$child]);
                #  the length will be the same as this node - no it will not.  
                #$child->set_length('length' => $self->get_length);
                $results{raised_count} ++;
            }
        }
    }

    #  delete the node from the parent's list of children if all have been raised
    if ($results{raised_count} == $child_count) {
        $self->get_parent->delete_child (child => $self);
        push @{$results{empty_node_names}}, $self->get_name;  #  add to list of names deleted
        return wantarray ? %results : \%results;
    }
    #  one child left - raise it and recalculate the length.  It is not healthy to be an only child.
    elsif (! $self->is_root_node && $results{raised_count} == ($child_count - 1)) {
        
        my $child = shift @{$self->get_children};
        #print "Raising child " . $child->get_name . "from parent " . $self->get_name .
        #      " to " . $self->get_parent->get_name . "\n";
        $self->get_parent->add_children (children => [$child]);
        $child->set_length (length => $self->get_length + $child->get_length);
        $self->get_parent->delete_child (child => $self);
        $results{raised_count} ++;
        push @{$results{empty_node_names}}, $self->get_name;  #  add to list of names deleted
        return %results if wantarray;
        return \%results;
    }
    
    #  now loop through any children and flatten them
    foreach my $child ($self->get_children) {
        my %res = $child->raise_zerolength_children;
        $results{raised_count} += $res{raised_count};
        push @{$results{empty_node_names}}, @{$res{empty_node_names}};
    }
    
    return %results if wantarray;
    return \%results;
}

#  a bit inefficient, but should work
sub get_terminal_node_refs {
    my $self = shift;
    
    my %descendents = $self->get_all_descendents;

    my %terminals;
    while (my ($name, $node_ref) = each %descendents) {
        next if ! $node_ref->is_terminal_node;
        $terminals{$name} = $node_ref;
    }

    return wantarray ? %terminals : \%terminals;
}

sub get_terminal_elements { #  get all the elements in the terminal nodes
    #  need to add a cache option to reduce the amount of tree walking
    #  - use  hash for this, but return the keys
    my $self = shift;
    my %args = (cache => 1, @_);  #  cache unless told otherwise

    if ($self->is_terminal_node) {
        return wantarray ? ($self->get_name, 1) : {$self->get_name, 1};
    }
    
    #  we have cached values from a previous pass - return them unless told not to
    if ($args{cache}) {
        my $elRef = $self->get_cached_value ('TERMINAL_ELEMENTS');
        if (defined $elRef) {
            return wantarray ? %{$elRef} : $elRef;
        }
    }
    my @list;
    foreach my $child ($self->get_children) {
        push @list, $child->get_terminal_elements (%args);
    }
    #  the values are really a hash, and need to be coerced into one when used
    #  hashes save memory when using globally repeated keys and are more flexible
    my %list = @list;
    if ($args{cache}) {
        $self->set_cached_value (TERMINAL_ELEMENTS => \%list);
    }

    return wantarray ? %list : \%list;
}

sub get_terminal_element_count {
    my $self = shift;

    my $hash = $self->get_terminal_elements (@_);

    return scalar keys %$hash;
}

sub get_all_descendents_and_self {
    my $self = shift;

    my %descendents = $self->get_all_descendents(@_);
    my $name = $self->get_name;
    $descendents{$name} = $self;
    
    foreach my $node_name (keys %descendents) {
        if (! isweak $descendents{$node_name}) {
            weaken $descendents{$node_name};
        }
    }
    
    return wantarray ? %descendents : \%descendents;
}

#  a left over - here just in case 
sub get_all_children {
    my $self = shift;
    return $self->get_all_descendents (@_);
}


sub get_all_descendents { #  get all the nodes (whether terminal or not) which are descendants of a node
    my $self = shift;
    my %args = (
        cache => 1, #  cache unless told otherwise
        @_,
    );  

    if ($self->is_terminal_node) {
        return wantarray ? () : {};  #  empty hash by default
    }

    #  we have cached values from a previous pass - return them unless told not to
    if ($args{cache}) {
        my $cached_hash = $self->get_cached_value('DESCENDENTS');
        if ($cached_hash) {  # return copies to avoid later pollution
            return wantarray ? %$cached_hash : {%$cached_hash};
        }
    }

    my @list;
    push @list, $self->get_children;
    foreach my $child (@list) {
        push @list, $child->get_children;
    }
    #  the values are really a hash, and need to be coerced into one when used
    #  hashes save memory when using globally repeated keys and are more flexible
    #my @hash_list;
    my %list;
    foreach my $node (@list) {
        my $name = $node->get_name;
        $list{$name} = $node;
        weaken $list{$name};
    }

    if ($args{cache}) {
        $self->set_cached_value(DESCENDENTS => \%list);
    }

    #  make sure we return copies to avoid pollution by other subs
    return wantarray ? %list : {%list};
}

#  while loop cleaner than recursion
sub get_path_to_root_node {
    my $self = shift;
    my %args = (cache => 1, @_);  #  cache unless told not to

    return wantarray ? ($self) : [$self] if $self->is_root_node;

    #  don't cache internals 
    my $use_cache = $self->is_internal_node ? 0 : $args{cache};
    #my $use_cache = 1; # - override

    my $path;

    if ($use_cache) {
        $path = $self->get_cached_value('PATH_TO_ROOT_NODE');
        #print ("using cache for " . $self->get_name . "\n") if $path;
        return wantarray ? @$path : $path
          if $path;
    }

    #$path = $self->get_parent->get_path_to_root_node (@_);
    #unshift @$path, $self;  #  used when recursing - needed to unwind
    my $node = $self;
    while ($node) {  #  undef when root node
        push @$path, $node;
        $node = $node->get_parent;
    }

    if ($use_cache) {
        $self->set_cached_value (PATH_TO_ROOT_NODE => $path);
    }

    return wantarray ? @$path : $path;
}

sub get_path_lengths_to_root_node {
    my $self = shift;
    my %args = (cache => 1, @_);

    #if ($self->is_root_node) {
    #    my %result = ($self->get_name, $self->get_length);
    #    return wantarray ? %result : \%result;
    #}

    #  don't cache internals
    #my $use_cache = $self->is_internal_node ? 0 : $args{cache};
    my $use_cache = $args{cache};  #  cache internals

    if ($use_cache) {
        my $path = $self->get_cached_value('PATH_LENGTHS_TO_ROOT_NODE');
        return (wantarray ? %$path : $path) if $path;
    }

    my %path_lengths;
    $path_lengths{$self->get_name} = $self->get_length;

    my $node = $self->get_parent;
    while ($node) {  #  undef when root node
        $path_lengths{$node->get_name} = $node->get_length;
        $node = $node->get_parent;
    }

    if ($use_cache) {
        $self->set_cached_value (PATH_LENGTHS_TO_ROOT_NODE => \%path_lengths);
    }

    return wantarray ? %path_lengths : \%path_lengths;
}

#  get all the nodes along a path from self to another node,
#  including self and other, and the shared ancestor
sub get_path_to_node {
    my $self = shift;
    my %args = (
        cache => 1, #  cache unless told otherwise
        @_,
    );  
    
    my $target = $args{node};
    my $target_name = $target->get_name;
    my $from_name = $self->get_name;
    my $use_cache = $args{cache};
    ##  don't cache internals to reduce memory footprint
    #if ($self->is_internal_node) {
    #    $use_cache = 0;
    #}

    my $return_lengths = $args{return_lengths};  #  node refs or their lengths?

    my $cache_pfx = $return_lengths ? 'PATH_LENGTHS_FROM::' : 'PATH_FROM::';

    #  maybe should make this a little more complex as a nested data structure?  Maybe a matrix?
    my $cache_list_name = $cache_pfx . $from_name . '::TO::' . $target_name;  

    #  we have cached values from a previous pass - return them unless told not to
    if ($use_cache) {
        my $cached_path = $self->get_cached_value ($cache_list_name);
        if (not defined $cached_path ) {  #  try the reverse, as they are the same
            $cache_list_name = $cache_pfx . $target_name . '::TO::' . $from_name;
            $cached_path     = $self->get_cached_value ($cache_list_name);
        }
        if (defined $cached_path ) {
            return wantarray ? %$cached_path : $cached_path;
        }
    }

    my $path = {};

    #  add ourselves to the path
    $path->{$from_name} = $return_lengths ? $self->get_length : $self;  #  we weaken $self ref below

    #  THIS IS REALLY INEFFICIENT -
    #  need to get path to root node for each of self and target
    #  and then choose the section before and including the shared ancestor
    #  using List::MoreUtils::before_incl
    if ($target_name ne $from_name) {
        #  check if the target is one of our descendents
        #  if yes then get the path downwards
        #  else go up to the parent and try it from there
        my $descendents = $self->get_all_descendents;
        if (exists $descendents->{$target_name}) {
            foreach my $child ($self->get_children) {
                my $child_name = $child->get_name;

                #  use the child or the child that is an ancestor of the target 
                my $ch_descendents = $child->get_all_descendents;
                if ($child_name eq $target_name or exists $ch_descendents->{$target_name}) {  #  follow this one
                    my $sub_path = $child->get_path_to_node (@_);
                    @$path{keys %$sub_path} = values %$sub_path;
                    last;  #  and check no more children
                }
            }
        }
        else {
            my $sub_path = $self->get_parent->get_path_to_node (@_);
            @$path{keys %$sub_path} = values %$sub_path;
        }
    }
    #  make sure they are weak refs to ensure proper destruction when required
    if (not $return_lengths) {
        foreach my $value (values %$path) {
            weaken $value if ! isweak $value;
            #print "NOT WEAK $value\n" if ! isweak $value;
        }
    }

    if ($use_cache) {
        $self->set_cached_value ($cache_list_name => $path);
    }

    return wantarray ? %$path : $path;
}


#  get the length of the path to another node
sub get_path_length_to_node {
    my $self = shift;
    my %args = (
        cache => 1, #  cache unless told otherwise
        @_,
    );

    my $target = $args{node};
    my $target_name = $target->get_name;
    my $from_name = $self->get_name;

    #  maybe should make this a little more complex as a nested data structure?  Maybe a matrix?
    my $cache_list = 'LENGTH_TO_' . $target_name;  

    my $length;

    #  we have cached values from a previous pass - return them unless told not to
    if ($args{cache}) {
        $length = $self->get_cached_value ($cache_list);
        return $length if defined $length;
    }

    my $path = $self->get_path_to_node (@_);

    foreach my $node (values %$path) {
        $length += $node->get_length;
    }

    if ($args{cache}) {
        $self->set_cached_value ($cache_list => $length);
    }

    return $length;
}

sub get_path_lengths_to_ancestral_node {
    my $self = shift;
    my %args = (cache => 1, @_);

    my $ancestor = $args{ancestral_node} or croak "ancestral_node not defined\n";
    
    if ($self->is_root_node) {
        my %result = ($self->get_name, $self->get_length);
        return wantarray ? %result : \%result;
    }

    #  don't cache internals
    my $use_cache = $self->is_internal_node ? 0 : $args{cache};

    my $cache_name;

    if ($use_cache) {
        $cache_name = 'PATH_LENGTHS_TO_ANCESTRAL_NODE:' . $ancestor->get_name;
        my $path = $self->get_cached_value($cache_name);
        return (wantarray ? %$path : $path) if $path;
    }

    my %path_lengths;
    my $node = $self;
    while ($node) {  #  undef when root node
        $path_lengths{$node->get_name} = $node->get_length;
        last if $node eq $ancestor;
        $node = $node->get_parent;
    }

    if ($use_cache) {
        $self->set_cached_value ($cache_name => \%path_lengths);
    }

    return wantarray ? %path_lengths : \%path_lengths;
}


#  find a shared ancestor for a node
#  it will be the first parent node that shares one or more terminal elements
#  Need to modify to use get_path_to_root_node and then get the segments that differ
sub get_shared_ancestor {
    my $self = shift;
    my %args = (
        cache => 1,
        @_,
    );

    my $compare = $args{node};
    
    my $cache_name = 'SHARED_ANCESTOR::' . $self . '::TO::' . $compare;
    if (1) {  #  always use the cache if it is available
        my $cached_ancestor = $self->get_cached_value ($cache_name);
        if (not defined $cached_ancestor) {  #  try the reverse, as they are the same
            my $cache_name2  = 'SHARED_ANCESTOR::' . $compare . '::TO::' . $self;
            $cached_ancestor = $self->get_cached_value ($cache_name2);
        }
        if (defined $cached_ancestor) {
            return wantarray ? %$cached_ancestor : $cached_ancestor;
        }
    }

    my %children = $self->get_terminal_elements;
    my $count = scalar keys %children;
    my %comp_children = $compare->get_terminal_elements;
    delete @children{keys %comp_children};  #  delete shared keys
    my $count2 = scalar keys %children;

    my $shared;
    if ($count != $count2) {
        $shared = $self;
    }
    else {
        $shared = $self->get_parent->get_shared_ancestor (@_);
    }

    if ($args{cache}) {
        $self->set_cached_value ($cache_name => $shared);
    }

    return $shared;
}

#  get the list of hashes in the nodes
sub get_hash_lists {
    my $self = shift;
    my %args = @_;
    
    my @list;
    foreach my $tmp (keys %{$self}) {
        next if $tmp =~ /^_/;  #  skip the internals
        push @list, $tmp if ref($self->{$tmp}) =~ /HASH/;
    }
    return @list if wantarray;
    return \@list;
}

sub get_hash_lists_below {
    my $self = shift;
    
    my @list = $self->get_hash_lists;
    my %hash_list;
    @hash_list{@list} = undef;

    foreach my $child (@{$self->get_children}) {
        my $list_below = $child->get_hash_lists_below;
        @hash_list{@$list_below} = undef;
    }
    
    return wantarray
        ? keys %hash_list
        : [keys %hash_list];
}

sub is_tree_node {  #  check if a node is a TreeNode - used to check children for terminal entries
    my $self = shift;
    my %args = @_;
    return if ! defined $args{node};
    return 1 if ref($args{node}) =~ /::TreeNode/;  #  should really use devel::symdump to allow abstraction
    return 0;
}

sub is_terminal_node {
    my $self = shift;
    return 1 if $#{$self->get_children} == -1;  #  no children - must be terminal
    return 0;
}

#  check if it is a "named" node, or internal (name ends in three underscores)
sub is_internal_node {
    my $self = shift;
    return ($self->get_name) =~ /___$/;
}

sub set_node_as_parent {  #  loop through the children and set this node as the parent
    my $self = shift;
    foreach my $child ($self->get_children) {
        if ($self->is_tree_node(node => $child)) {
            $child->set_parent(parent => $self);
        }
    }
}

sub set_parent {
    my $self = shift;
    my %args = @_;

    croak "argument 'parent' not specified\n"
      if ! exists ($args{parent});

    croak "Reference not type Biodiverse::TreeNode\n"
        if (defined $args{parent}
            && ! ref($args{parent}) =~ /Biodiverse::Treenode/
            );

    $self->{_PARENT} = $args{parent};
    #  avoid potential memory leakage caused by circular refs
    #weaken ($self->{_PARENT});  
    $self->weaken_parent_ref;
    
    return;
}

sub get_parent {
    my $self = shift;
    return $self->{_PARENT};
}

sub set_parents_below {  #  sometimes the parents aren't set properly by extension subs
    my $self = shift;
    
    foreach my $child ($self->get_children) {
        $child->set_parent (parent => $self);
        $child->set_parents_below;
    }
    
    return;
}

sub weaken_parent_ref {
    my $self = shift;
    
    if (! exists ($self->{_PARENT}) || ! defined ($self->{_PARENT})) {
        return;
    }
    elsif (not isweak ($self->{_PARENT})) {
        #print "Tree weakening parent ref\n";
        return weaken ($self->{_PARENT});
    }
    
    return 0;
}

sub is_root_node {
    my $self = shift;
    return defined $self->get_parent ? 0 : 1;  #  if it's undef then it's a root node
}

sub get_root_node {
    my $self = shift;
    
    return $self if $self->is_root_node;
    return $self->get_parent->get_root_node;
}

#  assign some plot coords to the nodes to allow reconstruction of
#  the dendrogram from a table
#  need to assign terminal y-values in order, and the parents take the average of the terminal y values.  
sub assign_plot_coords {
    my $self = shift;
    my %args = @_;
    
    $self->get_root_node->number_terminal_nodes;

    my $y_len = $self->get_terminal_element_count;
    my $x_len = $self->get_max_total_length;
    my $scale_factor = $args{plot_coords_scale_factor};
    if (not $scale_factor or $scale_factor < 0) {
        #$scale_factor =
        #    $y_len < $x_len
        #  ? $y_len / $x_len
        #  : $x_len / $y_len;
        $scale_factor = $x_len / $y_len;
    }

    my $max_y = $self->get_value('TERMINAL_NODE_LAST');

    $self->assign_plot_coords_inner (
        scale_factor => $scale_factor,
        max_y        => $max_y,
        plot_coords_left_to_right => $args{plot_coords_left_to_right},
    );

    return;
}

sub assign_plot_coords_inner {
    my $self = shift;
    my %args = @_;
    my $scale_factor  = $args{scale_factor} || 1;
    my $max_y         = $args{max_y} || 0;
    my $left_to_right = $args{plot_coords_left_to_right};

    my ($y1, $y2, $y_pos);

    if ($self->is_terminal_node) {
        $y1 = $max_y - $self->get_value('TERMINAL_NODE_FIRST');
        $y2 = $max_y - $self->get_value('TERMINAL_NODE_LAST');
        $y_pos = $scale_factor * ($y1 + $y2) / 2;
    }
    else {
        my @ch_y_pos;
        foreach my $child (@{$self->get_children}) {
            $child->assign_plot_coords_inner (%args);
            my $coords = $child->get_list_ref (list => 'PLOT_COORDS');
            push @ch_y_pos, $coords->{plot_y1};
        }

        $y1 = List::Util::max (@ch_y_pos);
        $y2 = List::Util::min (@ch_y_pos);
        $y_pos = ($y1 + $y2) / 2;
    }

    #  all dists relative to max length of the tree
    #  have to compensate for get_length_above including this node
    my $end_x   = $self->get_root_node->get_max_total_length - $self->get_length_above + $self->get_length;
    my $start_x = $end_x - $self->get_length;

    #my $vx = $start_x < $end_x  #  need this before the correction, but looks overcomplicated to be honest
    #  ? $start_x  #  monotonic case
    #  : $end_x;   #  reversal case
    my $vx = $start_x;
    # kludge - need to clean up total_length calcs?
    # Or create abs_pos subs to account for negative node lengths
    #if ($self->get_length < 0) {
    #    $end_x   += $self->get_length;
    #    $start_x += $self->get_length;
    #}
    if ($left_to_right) {
        $vx      *= -1;
        $end_x   *= -1;
        $start_x *= -1;
    }

    my %coords = (
        plot_y1 => $y_pos,
        plot_y2 => $y_pos,
        plot_x1 => $start_x,
        plot_x2 => $end_x,
    );

    my %vert_coords = (
        vplot_y1 => $y1,
        vplot_y2 => $y2,
        vplot_x1 => $vx,
        vplot_x2 => $vx,
    );

    $self->add_to_lists(
        PLOT_COORDS      => \%coords,
        PLOT_COORDS_VERT => \%vert_coords,
    );

    return;    
}


#  number the nodes below this one based on the terminal nodes
#  this allows us to export to CSV and retain some of the topology
sub number_terminal_nodes {
    my $self = shift;
    my %args = @_;

    #  get an array of the terminal elements (this will also cache them)
    my @te = keys %{$self->get_terminal_elements};

    my $prevChildElements = $args{count_sofar} || 1;
    $self->set_value (TERMINAL_NODE_FIRST => $prevChildElements);
    $self->set_value (TERMINAL_NODE_LAST => $prevChildElements + $#te);
    foreach my $child ($self->get_children) {
        my $count = $child->number_terminal_nodes ('count_sofar' => $prevChildElements);
        $prevChildElements += $count;
    }

    return $#te + 1;  #  return the number of terminal elements below this node
}

#  Assign a unique number to all nodes below this one.  It does not matter who gets what.
sub number_nodes {
    my $self = shift;
    my %args = @_;
    my $number = ($args{number} || 0) + 1;  #  increment the number to ensure it is different
    
    $self->set_value (NODE_NUMBER => $number);
    
    foreach my $child ($self->get_children) {
        $number = $child->number_nodes (number => $number);
    }
    return $number;
}

#  convert the entire tree to a table structure, using a basestruct object as an intermediate
sub to_table {
    my $self = shift;
    my %args = @_;
    my $treename = $args{name} || "TREE";
    
    #  assign unique ID numbers if not already done
    defined ($self->get_value ('NODE_NUMBER')) || $self->number_nodes;
    
    #  create the plot coords if requested
    if ($args{include_plot_coords}) {
        $self->assign_plot_coords (
            plot_coords_scale_factor  => $args{plot_coords_scale_factor},
            plot_coords_left_to_right => $args{plot_coords_left_to_right},
        );
    }
    
    # create a BaseStruct object to contain the table
    my $bs = Biodiverse::BaseStruct->new (
        NAME => $treename,
    );  #  may need to specify some other params


    my @header = qw /TREENAME NODE_NUMBER PARENTNODE LENGTHTOPARENT NAME/;
#    push @$data, \@header;

    my ($parent_num, $taxon_name);
    
    my $max_sublist_digits = defined $args{sub_list}
                            ? length ($self->get_max_list_length_below (list => $args{sub_list}) - 1)
                            : undef;


    my %children = $self->get_all_descendents;  #   all descendents below this node
    foreach my $node ($self, values %children) {  # maybe sort by child depth?
        $parent_num = $node->is_root_node
                        ? 0
                        : $node->get_parent->get_value ('NODE_NUMBER');
        if (!$node->is_internal_node || $args{use_internal_names}) {
            $taxon_name = $node->get_name;
        }
        else {
            $taxon_name = $EMPTY_STRING;
        }
        my $number = $node->get_value ('NODE_NUMBER');
        my %data;
        #  add to the basestruct object
        @data{@header} = ($treename, $number, $parent_num, $node->get_length || 0, $taxon_name);

        #  get the additional list data if requested
        if (defined $args{sub_list} && $args{sub_list} !~ /(no list)/) {
            my $sub_list_ref = $node->get_list_ref (list => $args{sub_list});
            if (defined $sub_list_ref) {
                if ((ref $sub_list_ref) =~ /ARRAY/) {
                    $sub_list_ref = $self->array_to_hash_values (
                        list             => $sub_list_ref,
                        prefix           => $args{sub_list},
                        num_digits       => $max_sublist_digits,
                        sort_array_lists => $args{sort_array_lists},
                    );
                }
                if ((ref $sub_list_ref) =~ /HASH/) {
                    @data{keys %$sub_list_ref} = (values %$sub_list_ref);
                }
            }
        }
        if ($args{include_plot_coords}) {
            my $plot_coords_ref = $node->get_list_ref (list => 'PLOT_COORDS');
            @data{keys %$plot_coords_ref} = (values %$plot_coords_ref);
            my $vert_plot_coords_ref = $node->get_list_ref (list => 'PLOT_COORDS_VERT');
            @data{keys %$vert_plot_coords_ref} = (values %$vert_plot_coords_ref);
        }

        $bs->add_element (element => $number);
        $bs->add_to_hash_list (
            element => $number,
            list    => 'data',
            %data,
        );
    }

    return $bs->to_table (%args, list => 'data');
}


#  print the tree out as a table structure
sub to_table_group_nodes {  #  export to table by grouping the nodes
    my $self = shift;
    my %args = @_;

    #  Marginally inefficient, as we loop over the data three times this way (once here, twice in write_table).
    #  However, write_table takes care of the output and list types (symmetric/asymmetric) and saves code duplication

    my $bs = $self->to_basestruct_group_nodes(%args);

    return $bs->to_table (@_, list => 'data');
}

sub to_basestruct_group_nodes {
    my $self = shift;
    my %args = @_;
    
    delete $args{target_value} if ! $args{use_target_value};
    
    $self->number_nodes if ! defined $self->get_value ('NODE_NUMBER');  #  assign unique labels to nodes if needed
    
    my $num_classes = $args{use_target_value} ? q{} : $args{num_clusters};

    croak "One of args num_classes or use_target_value must be specified\n"
        if ! ($num_classes || $args{use_target_value});

    # build a BaseStruct object and set it up to contain the terminal elements
    my $bs = Biodiverse::BaseStruct->new (
        NAME => 'TEMP',
    );

    my $get_node_method = $args{terminals_only} ? 'get_terminal_elements' : 'get_all_descendents_and_self';

    foreach my $element (sort keys %{$self->$get_node_method}) {
        $bs->add_element (element => $element);
    }

    #print "[TREE] Writing $num_classes clusters, grouped by "
    #      . $args{group_by_depth} ? "depth." : "length.";

    if (defined $args{target_value}) {
        print "  Target value is $args{target_value}.  " ;
    }
    print "\n";

    my %target_nodes = $self->group_nodes_below (
        %args,
        num_clusters => $num_classes
    );
    
    if (defined $args{sub_list} && $args{sub_list} !~ /(no list)/) {
        print "[TREE] Adding values from sub list $args{sub_list} to each node\n";
    } 

    print "[TREE] Actual number of groups identified is " . scalar (keys %target_nodes) . "\n";

    my $max_sublist_digits
        = defined $args{sub_list}
            ? length (
                $self->get_max_list_length_below (
                    list => $args{sub_list}
                ) - 1
            )
            : undef;

    # we have what we need, so flesh out the BaseStruct object
    foreach my $node (values %target_nodes) {
        my %data = (NAME => $node->get_name);
        if ($args{include_node_data}) {
            my %node_data = (
                LENGTH             => $node->get_length,
                LENGTH_TOTAL       => $node->get_length_below,
                DEPTH              => $node->get_depth,
                CHILD_COUNT        => $node->get_child_count,
                CHILD_COUNT_TOTAL  => $node->get_child_count_below,
                TNODE_FIRST        => $node->get_value('TERMINAL_NODE_FIRST'),
                TNODE_LAST         => $node->get_value('TERMINAL_NODE_LAST'),
            );
            @data{keys %node_data} = values %node_data;
        }

        #  get the additional list data if requested
        #  should really allow arrays here - convert to hashes?
        if (defined $args{sub_list} && $args{sub_list} !~ /(no list)/) {
            my $sub_list_ref = $node->get_list_ref (list => $args{sub_list});
            if (defined $sub_list_ref) {
                if ((ref $sub_list_ref) =~ /ARRAY/) {
                    $sub_list_ref = $self->array_to_hash_values (
                        list => $sub_list_ref,
                        prefix => $args{sub_list},
                        num_digits => $max_sublist_digits,
                        sort_array_lists => $args{sort_array_lists},
                    );
                }
                if ((ref $sub_list_ref) =~ /HASH/) {
                    @data{keys %$sub_list_ref} = (values %$sub_list_ref);
                }
                
            }
        }

        #  loop through all the terminal elements in this cluster and assign the values
        my @elements = keys %{$node->$get_node_method};
        foreach my $element (sort @elements) {
            $bs->add_to_hash_list (
                element => $element,
                list    => 'data',
                %data,
            );
        }
    }

    return $bs;
}


#  print the tree out to a nexus format file.
#  basically builds a taxon block and then passes that through to to_newick
sub to_nexus {
    my $self = shift;
    my %args = (@_);
    my $string;
    my $tree_name = $args{tree_name} || $self->get_param ('NAME') || 'Biodiverse_tree';
    
    #  first, build a hash of the label names for the taxon block, unless told not to
    my %remap;  #  create a remap table unless one is already specified in the args
    if (! defined $args{remap} && ! $args{no_remap}) {
        #  get a hash of all the nodes in the tree.
        my %nodes = ($self->get_name() => $self, $self->get_all_descendents);

        my $i = 0;
        foreach my $node (values %nodes) {
            #  no remap for internals - TreeView does not like it
            next if ! $args{use_internal_names} && $node->is_internal_node;  
            $remap{$node->get_name} = $i;
            $i++;
        }
    }
    my %reverse_remap;
    @reverse_remap{values %remap} = (keys %remap);

    my $translate_table;
    my $quote_char = q{'};
    my $csv_obj = $self->get_csv_object (
        quote_char  => $quote_char,
        escape_char => $quote_char,
        quote_space => 1,
    );
    my $j = 0;
    foreach my $mapped_key (sort numerically keys %reverse_remap) {
        my $remapped = $self->list2csv (
            csv_object => $csv_obj,
            list       => [$reverse_remap{$mapped_key}],
        );
        $translate_table .= "\t\t$mapped_key $remapped,\n";
        $j++;
    }
    chop $translate_table;  #  strip the last two characters - cheaper than checking for them in the loop
    chop $translate_table;
    $translate_table .= "\n\t\t;";

    my $type = blessed $self;

    #  clean up quoting
    if ($tree_name =~ /^'/ and $tree_name =~ /'$/) {
        $tree_name =~ s/^'//;
        $tree_name =~ s/'$//;
    }
    $tree_name = $self->list2csv(  #  quote tree name if needed
        csv_object => $csv_obj,
        list       => [$tree_name],
    );

    $string .= "#NEXUS\n";
    $string .= "[ID: $tree_name]\n";
    $string .= "begin trees;\n";
    $string .= "\t[Export of a $type tree using Biodiverse::TreeNode version $VERSION]\n";
    $string .= "\tTranslate \n$translate_table\n";
    $string .= "\tTree $tree_name = " . $self->to_newick (remap => \%remap, %args) . ";\n";
    $string .= "end;\n\n";

    #print $EMPTY_STRING;

    return $string;
}

sub to_newick {   #  convert the tree to a newick format.  Based on the NEXUS library
    my $self = shift;
    my %args = (use_internal_names => 1, @_);

    my $use_int_names = $args{use_internal_names};
    my $boot_name = $args{boot} || 'boot';
    #my $string = $self->is_terminal_node ? $EMPTY_STRING : '(';  #  no brackets around terminals
    my $string = $EMPTY_STRING;

    my $remap = $args{remap} || {};
    my $name = $self->get_name;
    my $remapped = 0;
    if (defined $remap->{$name}) {
        $name = $remap->{$name}; #  use remap if present
    }
    else {
        my $quote_char = q{'};
        my $csv_obj = $self->get_csv_object (
            quote_char   => $quote_char,
            escape_char  => $quote_char,
            always_quote => 1,
        );
        $name = $self->list2csv (csv_object => $csv_obj, list => [$name]);
        #$name = "'$name'";  #  quote otherwise
    }
    

    if (! $self->is_terminal_node) {   #  not a terminal node
        $string .= "(";
        foreach my $child ($self->get_children) { # internal nodes
            $string .= $child->to_newick(%args);
            #$string .= ')' if ! $child->is_internal_node;
            $string .= ',';
        }
        chop $string;  # remove trailing comma
        $string .= ")";
        
        if (defined ($name) && $use_int_names ) {
            $string .= $name;  
        }
        if (defined $self->get_length) {
            $string .= ":" . $self->get_length;
        }
        if (defined $self->get_value($boot_name)) {
            $string .= "[" . $self->get_value($boot_name) . "]";
        }
        
    }
    else { # terminal nodes
        #$string .= "'" . $name . "'";
        $string .= $name;
        if (defined $self->get_length) { 
            $string .= ":" . $self->get_length;
        }
        if (defined $self->get_value($boot_name)) { # state at nodes sometimes put as bootstrap values
            $string .= "[" . $self->get_value($boot_name) . "]";
        }
        #$string .= ",";
    }

    return $string;
}

sub print { # prints out the tree (for debugging)
    my $self = shift;
    my $space = shift || $EMPTY_STRING;

    print "$space " . $self->get_name() . "\t\t\t" . $self->get_length . "\n";
    foreach my $child ($self->get_children) {
            $child->print($space . $SPACE);
    }
    return;
}

*add_to_list = \&add_to_lists;

sub add_to_lists {
    my $self = shift;
    my %args = @_;
    
    #  create the list if not already there and then add to it
    while (my ($list, $values) = each %args) {    
        if ((ref $values) =~ /HASH/) {
            $self->{$list} = {} if ! exists $self->{$list};
            next if ! scalar keys %$values;
            @{$self->{$list}}{keys %$values} = values %$values;  #  add using a slice
        }
        elsif ((ref $values) =~ /ARRAY/) {
            $self->{$list} = [] if ! exists $self->{$list};
            next if ! scalar @$values;
            push @{$self->{$list}}, @$values;
        }
        else {
            carp "add_to_lists warning, no valid list ref passed\n";
            return;
        }
    }
    
    return;
}

#  delete a set of lists at this node
sub delete_lists {
    my $self = shift;
    my %args = @_;
    
    my $lists = $args{lists};
    croak "argument 'lists' not defined or not an array\n"
        if not defined $lists or (ref $lists) !~ /ARRAY/;
    
    foreach my $list (@$lists) {
        next if ! exists $self->{$list};
        $self->{$list} = undef;
        delete $self->{$list};
    }
    
    return;
}

#  delete a set of lists at this node, and all its descendents
sub delete_lists_below {
    my $self = shift;
    
    $self->delete_lists (@_);
    
    foreach my $child ($self->get_children) {
        $child->delete_lists_below (@_);
    }
    
    return;
}

sub get_lists {
    my $self = shift;
    return wantarray ? values %$self : [values %$self];
}

sub get_list_names {
    my $self = shift;
    return wantarray ? keys %$self : [keys %$self];
}

#  get a list of all the lists contained in the tree below and including this node
sub get_list_names_below {
    my $self = shift;
    my %args = @_;
    
    my %list_hash;
    my $lists = $self->get_list_names;
    @list_hash{@$lists} = 1 x scalar @$lists;
    
    foreach my $child ($self->get_children) {
        $lists = $child->get_list_names_below (%args);
        @list_hash{@$lists} = 1 x scalar @$lists;
    }
    
    if (! $args{show_hidden_lists}) {  # a bit of repeated cleanup, but we need to guarantee we get them if needed
        foreach my $key (keys %list_hash) {
            delete $list_hash{$key} if $key =~ /^_/;
        }
    }
    
    return wantarray ? keys %list_hash : [keys %list_hash];
}

#  how long are the lists below?
sub get_max_list_length_below {
    my $self = shift;
    my %args = @_;
    my $list_name = $args{list};
    
    my $length;
    
    my $list_ref = $self->get_list_ref (%args);
    if ((ref $list_ref) =~ /ARRAY/) {
        $length = scalar @$list_ref;
    }
    else {  #  must be a hash
        $length = scalar keys %$list_ref;
    }
    
    foreach my $child ($self->get_children) {
        my $ch_length = $child->get_max_list_length_below (%args);
        $length = $ch_length if $ch_length > $length;
    }
    
    return $length;
}


sub get_list_ref {
    my $self = shift;
    my %args = @_;
    my $list = $args{list};
    exists $self->{$list} ? $self->{$list} : undef;
}

sub get_node_range {
    my $self = shift;
    my %args = @_;

    my $bd = $args{basedata_ref} || croak "argument basedata_ref not provided\n";

    #  need to apply some caching using the $bd ref in the key
    my $cache_key = 'NODE_RANGE_' . $bd;
    my $cached_range = $self->get_cached_value ($cache_key);

    return $cached_range if defined $cached_range;

    my @labels   = ($self->get_name);
    my $children =  $self->get_all_descendents;

    #  collect the set of non-internal (named) nodes
    #  Possibly should only work with terminals
    #  which would simplify things.
    foreach my $name (keys %$children) {
        next if $children->{$name}->is_internal_node;
        push (@labels, $name);
    }

    my @range = $bd->get_range_union (labels => \@labels);

    my $range = scalar @range;

    $self->set_cached_value ($cache_key => $range);

    return $range;
}


#  Could do as a Biodiverse::Tree method, but this allows us to work
#  with clades within the tree.  B::Tree just has to modify its node hash.
sub shuffle_terminal_names {
    my $self = shift;
    my %args = @_;

    my $prng = $args{rand_object} // $self->initialise_rand (%args);

    my %terminals = $self->get_terminal_node_refs;

    #  Get names in consistent order for replication purposes
    my @names = sort keys %terminals;
    my @shuffled_names = @names;
    $prng->shuffle(\@shuffled_names);  #  in-place re-ordering

    my %reordered;
    @reordered{@names} = @shuffled_names;
    
    foreach my $node_ref (values %terminals) {
        my $name = $node_ref->get_name;
        $node_ref->set_name (name => $reordered{$name});
    }

    return wantarray ? %reordered : \%reordered;
}


sub numerically {$a <=> $b}

#sub DESTROY {
#    my $self = shift;
#    #my $name = $self->get_name;
#    #print "DESTROYING $name\n";
#    $self->{_PARENT} = undef;  #  free the parent
#    #  destroy the children
#    foreach my $child ($self->get_children) {
#        $child->DESTROY if defined $child;
#    }
#    $self->{_CHILDREN} = undef;  
#    
#    #print "DESTROYED $name\n";
#    #  perl can handle the rest
#}

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
