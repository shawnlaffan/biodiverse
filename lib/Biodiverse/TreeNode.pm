package Biodiverse::TreeNode;
use 5.036;
use strict;
use warnings;
no warnings 'recursion';

use experimental qw /refaliasing for_list/;

use English qw ( -no_match_vars );
use Ref::Util qw { :all };


use Carp;
use Scalar::Util qw /weaken isweak blessed/;
#use Data::Dumper qw/Dumper/;
use List::Util 1.39 qw /min max pairgrep sum any/;
use List::MoreUtils qw /uniq/;
use Readonly;

use Biodiverse::BaseStruct;
use Biodiverse::TreeNode::BootstrapBlock;

use parent qw /Biodiverse::Common/;

our $VERSION = '4.99_009';

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

    my $self = {_CHILDREN => []};
    bless $self, $class;

    #  now we loop through and add any specified arguments
    $self->set_length_aa ( $args{length});
    $self->set_name_aa ( $args{name} );

    if (exists $args{parent}) {
        $self->set_parent_aa($args{parent});
    }

    if (exists $args{children}) {
        $self->add_children(%args);
    }

    if (exists $args{boot} && defined $args{boot} && length $args{boot}) {
        #say "We found the boot arg, it is $args{boot}";
        my $booter = $self->get_bootstrap_block;
        $booter->decode (raw_bootstrap => $args{boot});
        #  store the raw text somewhere that can be deleted with impunity
        #  handy for debugging
        $booter->set_cached_value (RAW_TEXT => $args{boot});
    }
    
    return $self;
}

#  get a duplicate with just the name and length
sub duplicate_minimal {
    #my ($self) = @_;
    my $dup = {
        NODE_VALUES => {
            LENGTH => $_[0]->{NODE_VALUES}{LENGTH},
            NAME   => $_[0]->{NODE_VALUES}{NAME},
        },
        #NODE_VALUES => {%{$self->{NODE_VALUES}}},
        _CHILDREN => [],
    };
    return bless $dup, blessed $_[0];
}

#  set any value - allows user specified additions to the core stuff
sub set_value {
    my $self = shift;
    my %args = @_;
    @{$self->{NODE_VALUES}}{keys %args} = values %args;
    
    return;
}

#  extremely heavy usage sub so make it as fast as we can
sub get_value {
    no autovivification;
    $_[0]->{NODE_VALUES}{$_[1]};
}


sub delete_values {
    my $self = shift;
    my %args = @_;

    delete $self->{NODE_VALUES}{keys %args};
    
    return;
}

#  set any value - allows user specified additions to the core stuff
sub set_cached_value {
    my $self = shift;
    my %args = @_;

    @{$self->{_cache}}{keys %args} = values %args;
    
    return;
}

sub get_cached_value {
    no autovivification;
    $_[0]->{_cache}{$_[1]};
    #my $self = shift;
    #my $key  = shift;
    #return $self->{_cache}{$key};
    #return if ! exists $self->{_cache};
    #return $self->{_cache}{$key} if exists $self->{_cache}{$key};
    #return;
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
    return if ! exists $self->{_cache};

    #  unpack out of order, as we often return early
    my %args = @_ ? @_ : ();

    if ($args{keys}) {
        my $keys = $args{keys};
        return if not defined $keys or not scalar @$keys;

        delete @{$self->{_cache}}{@$keys};
        delete $self->{_cache} if !scalar keys %{$self->{_cache}};
    }
    else {
        delete $self->{_cache};
    }

    return;
}

#  was trying to avoid memory leaks, to no avail
#use Sub::Current;  
#use feature 'current_sub';

sub delete_cached_values_below {
    my $self = shift;
    my %args = @_;

    #  this approach seems to avoid memory leaks
    my $descendents = $self->get_all_descendants (cache => 0);
    foreach my $node (values %$descendents) {
        $node->delete_cached_values (%args);
    }
    $self->delete_cached_values (%args);

    return;
}

#  almost the same as set_name
#  but the args differ
sub rename {
    my $self = shift;
    my %args = @_;

    croak "new_name argument missing\n"
      if not defined $args{new_name};

    $self->{NODE_VALUES}{NAME} = $args{new_name};
    return;
}

sub set_name {
    my $self = shift;
    my %args = @_;

    croak "name argument missing\n" if not defined $args{name};

    $self->{NODE_VALUES}{NAME} = $args{name};
    
    return;
}

sub set_name_aa {
    croak "name argument missing\n" if not defined $_[1];

    $_[0]->{NODE_VALUES}{NAME} = $_[1];
    
    return;
}


sub get_name {
    $_[0]->{NODE_VALUES}{NAME}
      // croak "name parameter missing or undefined\n";
}

sub get_node_values {
    wantarray ? %{$_[0]->{NODE_VALUES}} : $_[0]->{NODE_VALUES};
}

sub set_length {
    my $self = shift;
    my %args = @_;
    #croak 'length argument missing' if not exists ($args{length});
    $self->{NODE_VALUES}{LENGTH} = 0 + ($args{length} // $default_length);

    return;
}

#sub set_length_aa {
#    my ($self, $length) = @_;
#    $self->{NODE_VALUES}{LENGTH} = 0 + ($length // $default_length);
#    return;
#}
sub set_length_aa {
    $_[0]->{NODE_VALUES}{LENGTH} = 0 + ($_[1] // $default_length);
}


sub get_length {
    return $_[0]->{NODE_VALUES}{LENGTH} // $default_length;
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
    my $min_value = $args{total_length};
    defined $min_value || croak "[TREENODE] argument total_length not specified\n";
    
    foreach my $child ($self->get_children) {
        #if ($child->get_total_length != $min_value) {
        #    print "Length already defined, node ", $child->get_name, "\n";
        #}
        $child->set_value (TOTAL_LENGTH => $min_value);
        if ($child->is_terminal_node) {
            $child->set_length (length => $min_value);
        }
        else {
            my $grand_child = @{$child->get_children}[0];  #ERROR ERROR???
            $child->set_length (length => $min_value - $grand_child->get_total_length);
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
    
    my %descendents = $self->get_all_descendants;
    foreach my $child (values %descendents) {
        $child->reset_total_length;
    }

}


sub get_total_length {
    #  use the stored value if exists
    #  calculate otherwise
    $_[0]->get_value ('TOTAL_LENGTH')
      // $_[0]->get_length_below;
}

sub get_sum_of_branch_lengths_below {
    my $self = shift;
    my %args = (cache => 1, @_);

    state $cache_key = 'SUM_OF_BRANCH_LENGTHS_BELOW';
    my $sum = $self->get_cached_value ($cache_key);
    
    return $sum if defined $sum;
    
    my %nodes = $self->get_all_descendants_and_self;
    foreach my $node (values %nodes) {
        $sum += $node->get_length;
    }

    $self->set_cached_value ($cache_key => $sum);

    return $sum;
}

sub get_longest_path_length_to_terminals {
    my $self = shift;
    my %args = (cache => 1, @_);

    state $cache_key = 'LONGEST_PATH_LENGTH_TO_TERMINALS';
    if ($args{cache}) {  #  lots of conditions, but should save a little number crunching overall.
        my $cached_length = $self->get_cached_value ($cache_key);
        return $cached_length if defined $cached_length;
    }

    my $terminal_node_hash = $self->get_terminal_node_refs;
    my $max_length = 0;
    my %cached_lens;
    foreach my $child (values %$terminal_node_hash) {
        my $path_length = $child->get_length;
        $cached_lens{$child} += $path_length;
        my $node = $child;
        while ($node = $node->get_parent) {
            $path_length += $cached_lens{$node} // $node->get_length;
            last if $node eq $self;
        }

        $max_length = max ($path_length, $max_length);
    }

    if ($args{cache}) {
        $self->set_cached_value ($cache_key => $max_length);
    }

    return $max_length;    
}

sub get_shortest_path_length_to_terminals {
    my $self = shift;
    my %args = (cache => 1, @_);
    return $self->get_shortest_path_length_to_terminals_aa (!$args{cache});
}

#  array args variant, uses no_cache to simplify cache flag logic
sub get_shortest_path_length_to_terminals_aa {
    my ($self, $no_cache) = @_;

    state $cache_key = 'SHORTEST_PATH_LENGTH_TO_TERMINALS';
    if (!$no_cache) {
        my $cached_length = $self->get_cached_value ($cache_key);
        return $cached_length if defined $cached_length;
    }

    my $min_length = $self->get_length;
    if (!$self->is_terminal_node) {
        $min_length += min
          map {$_->get_shortest_path_length_to_terminals}
          $self->get_children;
    }

    if (!$no_cache) {
        $self->set_cached_value ($cache_key => $min_length);
    }

    return $min_length;    
}

#  get the maximum tree node position from zero
sub get_max_total_length {
    my $self = shift;
    my %args = @_;

    #  comment next line as we might as well cache the total length on terminals as well
    #return $self->get_total_length if $self->is_terminal_node;  # no children

    state $cache_key = 'MAX_TOTAL_LENGTH';
    if ($args{cache}) {  #  lots of conditions, but should save a little number crunching overall.
        my $cached_length = $self->get_cached_value ($cache_key);
        return $cached_length if defined $cached_length;
    }

    my $max_length = $self->get_total_length;
    foreach my $child ($self->get_children) {
        my $child_length = $child->get_max_total_length (%args) || 0;  #  pass on the args

        $max_length = $child_length if $child_length > $max_length;
    }

    if ($args{cache}) {
        $self->set_cached_value ($cache_key => $max_length);
    }

    return $max_length;
}

#  includes the length of the current node, so totalLength = lengthBelow+lengthAbove-selfLength
sub get_length_below {  
    my $self = shift;
    my %args = (cache => 1, @_);  #  defaults to caching


    #return $self->get_length if $self->is_terminal_node;  # no children

    state $cache_key = 'LENGTH_BELOW';
    if ($args{cache}) {  #  lots of conditions, but should save a little number crunching overall.
        my $cached_length = $self->get_cached_value ($cache_key);
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
        $self->set_cached_value ($cache_key => $length);
    }

    return $length;
}


sub set_depth {
    my $self = shift;
    my %args = @_;
    return if ! exists ($args{depth});
    $self->{NODE_VALUES}{DEPTH} = $args{depth};
}

sub set_depth_aa {
    $_[0]->{NODE_VALUES}{DEPTH} = $_[1];
}

sub get_depth {
    my $self = shift;

    my $depth = $self->{NODE_VALUES}{DEPTH};

    return $depth if defined $depth;

    if ($self->is_root_node) {
        $self->set_depth(depth => 0);
        return 0;
    }

    #  search up the tree but avoid recursion
    my @parents = $self->get_parent;
    $depth      = $parents[0]->{NODE_VALUES}{DEPTH};
  PARENT:
    while (!defined $depth) {
        my $parent = $parents[0]->get_parent;
        last PARENT if !defined $parent;
        if ($parent->is_root_node) {
            $depth = 0;
        }
        else {
            $depth = $parent->{NODE_VALUES}{DEPTH};
        }
        unshift @parents, $parent;
        last PARENT if defined $depth;
    }
    shift @parents;
    $depth ++;
    foreach my $node (@parents) {
        $node->set_depth(depth => $depth);
        $depth++;
    }
    $self->set_depth(depth => $depth);
    #   old recursive approach - leaked memory
    #$self->set_depth(depth => ($self->get_parent->get_depth + 1));

    return $self->{NODE_VALUES}{DEPTH};
}

sub get_depth_below {  #  gets the deepest depth below the caller in total tree units
    my $self = shift;
    my %args = (cache => 1, @_);
    return $self->get_depth if $self->is_terminal_node;  # no elements, return its depth

    state $cache_key = 'DEPTH_BELOW';
    if ($args{cache}) {  #  lots of conditions, but should save a little number crunching overall.
        my $cached_value = $self->get_cached_value ($cache_key);
        return $cached_value if defined $cached_value;
    }

    my $max_depth_below = 0;
    foreach my $child ($self->get_children) {
        my $depth_below_child = $child->get_depth_below;
        $max_depth_below = $depth_below_child if $depth_below_child > $max_depth_below;
    }
    
    $self->set_cached_value ($cache_key => $max_depth_below) if $args{cache};
    
    return $max_depth_below;
}

sub add_children {
    my $self = shift;
    my %args = @_;
    \my @children = $args{children}
      // return;  #  should croak
    #  save some checking below (based on a promise)
    my $children_are_treenodes = $args{is_treenodes};
    my $check_parents          = !$args{are_orphans};

    #croak "TreeNode WARNING: children argument not an array ref\n"
    #  if !is_arrayref($children);
    
    #  Remove any duplicates.
    #  Could use a hash but we need to retain the insertion order
    if (@children > 1) {
        @children = uniq @children;
    }

    # need to skip any that already exist
    my $existing_children = $self->{_CHILDREN};
    my (%skip, $use_skip);
    if (scalar @$existing_children) {
        $use_skip = 1;
        @skip{@$existing_children} = (1) x @$existing_children;
    }


  CHILD:  #  use an array to retain the order in which they were passed
    foreach my $child (@children) {
        #  don't re-add our own child
        next CHILD if $use_skip && $skip{$child};

        if ($children_are_treenodes || $self->is_tree_node_aa($child)) {
            if ($check_parents && defined $child->get_parent) {
                #  too many parents - this is a single parent system
                if ($args{warn}) {
                    my $name = $self->get_name;
                    say "TreeNode WARNING: child $name already has a parent, resetting";
                }
                $child->get_parent->delete_child (child => $child);
            }
        }
        #  not a tree node, and not a ref, so make it one
        else {
            croak "Warning: Cannot add $child as a child - already a reference\n"
              if ref $child;

            $child = Biodiverse::TreeNode->new(name => $child);
        }
        push @$existing_children, $child;
        $child->set_parent_aa($self);
    }

    return;
}

sub has_child {
    my $self = shift;
    my %args = @_;

    my $node_ref = $args{node_ref} || croak "missing node_ref argument\n";

    my @children = $self->get_children;

    return any {$_ eq $node_ref} @children;
}

#  array args variant
sub has_child_aa {
    my ($self, $node_ref) = @_;

    my @children = $self->get_children;

    return any {$_ eq $node_ref} @children;
}


#  Remove a child from a list.
#  The no_delete_cache arg means the caller promises to
#  clean up the cache and any circular refs.
sub delete_child {  
    my $self = shift;
    my %args = @_;
    my $target_child = $args{child};

    my $i = 0;
    foreach my $child ($self->get_children) {
        if ($child eq $target_child) {
            splice @{$self->{_CHILDREN}}, $i, 1;
            if (!$args{no_delete_cache}) {
                $child->delete_cached_values_below;
            }
            return 1;
        }
        $i++;
    }

    return;  #  return undefined if nothing removed
}

sub delete_children {
    my $self = shift;
    my %args = @_;
    my $children = $args{children};

    croak "children argument not specified or not an array ref"
        if ! defined $children || !is_arrayref($children);

    my $count = 0;
    foreach my $child (@$children) {
        #  delete_child returns 1 if it deletes something, undef otherwise
        $count ++ if defined $self->delete_child (%args, child => $child);
    }
    return $count;
}

sub get_children {
    return if not defined $_[0]->{_CHILDREN};
    return wantarray ? @{$_[0]->{_CHILDREN}} : [@{$_[0]->{_CHILDREN}}];
}

sub get_child_count {
    scalar @{$_[0]->{_CHILDREN}};
}
    
# should be get_terminal_node_count
# same as get_terminal_element_count, so just pass it on
sub get_child_count_below {
    my $self = shift;
    return $self->get_terminal_element_count (@_);
}

sub splice_into_lineage {
    my ($self, %args) = @_;
    my $new_node = $args{new_node};
    my $dist_from_tip = $args{dist_from_tip}
      // $new_node->get_length
      // 0;
    my $name_suffix = $args{name_suffix} // ' ancestral split';
    my $no_cache_cleanup = $args{no_cache_cleanup};
    
    my $len = $self->get_length;
    #if ($len == $dist_from_tip) {
    #    $self->get_parent->add_children (children => [$new_node]);
    #    return $new_node;
    #}
    my $target = $self;
    my $cum_len = $len;
    while ($cum_len < $dist_from_tip && !$target->is_root_node) {
        $target = $target->get_parent;
        $cum_len += $target->get_length;
    }
    
    my $new_parent = $target;
    #  cut the branch
    if (!$target->is_root_node) {
        my $new_len = $cum_len - $dist_from_tip;
        $new_parent = Biodiverse::TreeNode->new (
            name   => $target->get_name . $name_suffix,
            length => $new_len,
        );
        my $grandparent = $target->get_parent;
        $new_parent->set_parent_aa ($grandparent);
        $grandparent->add_children (children => [$new_parent]);
        my $new_target_len = $target->get_length - $new_len;
        $target->set_length_aa ($new_target_len);
        $target->set_parent_aa ($new_parent);
        $new_node->set_parent_aa ($new_parent);
        $new_parent->add_children(children => [$target, $new_node]);
    }
    else {
        $target->add_children (children => [$new_node]);
    }
    if (!$no_cache_cleanup) {
        #  option allows one to avoid quadratic behaviour
        $self->get_root_node->delete_cached_values_below;
    }

    return $new_parent;
}


#  Get a hash of the nodes below this one based on length.
#  Algorithm is messy but accounts for reversals in the tree.
sub group_nodes_below {
    my $self = shift;
    my %args = @_;
    my $groups_needed = $args{num_clusters} || $self->get_child_count_below;
    my %search_hash;
    my %final_hash;

    my $use_depth = $args{group_by_depth};  #  alternative is by length
    #  a second method by which it may be passed - usually from the GUI
    $use_depth ||= ($args{type} // '') eq 'depth';

    #  override target value if $args{num_clusters} passed
    my $target_value
      = $args{num_clusters}
      ? undef
      : ($args{target_value} // $args{target_distance});

    my $cache_key  = 'group_nodes_below by ' . ($use_depth ? 'depth ' : 'length ');
    my $cache_hash = $self->get_cached_value_dor_set_default_aa ($cache_key, {});
    my $cache_val = $target_value // $groups_needed;
    if (my $cached_result = $cache_hash->{$cache_val}) {
        return wantarray ? %$cached_result : $cached_result;
    }
    
    $final_hash{$self->get_name} = $self;

    if ($self->is_terminal_node) {
        weaken $final_hash{$self->get_name};
        return wantarray ? %final_hash : \%final_hash;
    }
    
    my @current_nodes;

    my ($upper_value, $lower_value);
    if ($use_depth) {
        $upper_value = $self->get_depth;
        $lower_value = $self->get_depth + 1;
    }
    else {
        $upper_value = $self->get_length_below;
        $lower_value = $self->get_length_below - $self->get_length;
        if ($upper_value < $lower_value) {
            ($lower_value, $upper_value) = ($upper_value, $lower_value);
        }
    }

    #  check if we have all we need
    return wantarray ? %final_hash : \%final_hash
      if     defined $target_value
          && $target_value > $lower_value
          && $target_value <= $upper_value;

    $search_hash{$lower_value}{$upper_value}{$self->get_name} = $self;

    state $cache_key_ub = 'UPPER_BOUND_LENGTH';
    state $cache_key_lb = 'LOWER_BOUND_LENGTH';

  NODE_SEARCH:
    while (scalar keys %final_hash < $groups_needed) {
        @current_nodes = values %{$search_hash{$lower_value}{$upper_value}};
        foreach my $current_node (@current_nodes) {
          CNODE:
            foreach my $child ($current_node->get_children) {
                my ($upper_bound, $lower_bound);
                my $child_name = $child->get_name;
                
                if (!$child->is_terminal_node) {
                    #  only consider length if it has children
                    #  and that length is from its children
                    if ($use_depth) {
                        $upper_bound = $child->get_depth;
                        $lower_bound = $upper_bound + 1;
                    }
                    else {
                        $upper_bound = $child->get_cached_value ($cache_key_ub);
                        if (defined $upper_bound) {
                            $lower_bound = 0 + $child->get_cached_value ($cache_key_lb);
                        }
                        else {
                            my $length       = $child->get_length;
                            my $length_below = $child->get_length_below;
                            if ($length < 0) {  # reversal
                                my $parent = $child->get_parent;
                                #  parent_pos is wherever its children begin
                                my $parent_pos = $parent->get_length_below - $parent->get_length;
                                $upper_bound = min ($parent_pos, $length_below);
                                $lower_bound = min ($parent_pos, $length_below - $length);
                            }
                            else {
                                $upper_bound = $length_below;
                                $lower_bound = $length_below - $length;
                            }
                            $child->set_cached_value ($cache_key_ub => $upper_bound);
                            $child->set_cached_value ($cache_key_lb => $lower_bound);

                            #  swap them if they are inverted (eg for depth)
                            if ($upper_bound < $lower_bound) {
                                ($lower_bound, $upper_bound) = ($upper_bound, $lower_bound);
                            }
                        }
                    }

                    #  surely this can be simplified?
                    my $include_in_search = 1;  #  flag to include this child in further searching
                    #  don't add to search hash unless we need to keep looking
                    if (defined $target_value) {
                        if ($use_depth && $target_value <= $lower_bound && $target_value >= $upper_bound) {
                            $include_in_search = 0;
                        }
                        elsif ($target_value > $lower_bound && $target_value <= $upper_bound) {
                            $include_in_search = 0;
                        }
                    }
                    if ($include_in_search) {
                        #  add to the values hash if it bounds the target value or it is not specified
                        $search_hash{$lower_bound}{$upper_bound}{$child_name} = $child;
                    }
                }

                $final_hash{$child_name} = $child;  #  add this child node to the tracking hashes        
                delete $final_hash{$child->get_parent->get_name};
                #  clear parent from length consideration
                delete $search_hash{$lower_value}{$upper_value}{$current_node->get_name};
            }
            delete $search_hash{$lower_value}{$upper_value}
              if not scalar keys %{$search_hash{$lower_value}{$upper_value}};
            delete $search_hash{$lower_value}
              if not scalar keys %{$search_hash{$lower_value}};
        }
        last if not scalar keys %search_hash;  #  drop out - they must all be terminal nodes

        $lower_value = max (keys %search_hash);
        $upper_value = max (keys %{$search_hash{$lower_value}});

    }

    #  avoid some potential mem leaks when we cache these
    weaken $_ for values %final_hash;

    $cache_hash->{$cache_val} = \%final_hash;

    return wantarray ? %final_hash : \%final_hash;
}

#  reduce the number of tree nodes by promoting children with zero length difference
#  from their parents
# potentially inefficient, as it starts from the top several times, but does avoid
#  deep recursion this way (unless the tree really is that deep...)
sub flatten_tree {
    my $self = shift;
    #my $iter = 0;
    my $count = 1;
    my @empty_nodes;
    print "[TREENODE] FLATTENING TREE.  ";
    while ($count > 0) {
        my %raised = $self->raise_zerolength_children;
        print " Raised $raised{raised_count},";
        #$iter ++;
        push @empty_nodes, @{$raised{empty_node_names}};
        $count = $raised{raised_count};
    }
    print "\n";
    return wantarray ? @empty_nodes : \@empty_nodes;
}

sub ladderise {
    my ($self, %args) = @_;
    
    my %nodes = $self->get_all_descendants_and_self;
    foreach my $node (values %nodes) {
        $node->sort_children;
    }

    return;
}

sub sort_children {
    my ($self, %args) = @_;
    my $children = $self->{_CHILDREN};
    return if scalar @$children <= 1;

    #  could use Sort::Maker if this turns out to be slow
    my $sort_func = $args{sort_func}
      // sub {$b->get_descendent_count <=> $a->get_descendent_count || $a->get_name cmp $b->get_name};

    my @sorted = $args{reverse}
        ? reverse sort $sort_func @$children
        : sort $sort_func @$children;

    $self->{_CHILDREN} = \@sorted;

    return;
}

#  raise any zero length children to be children of the parents (siblings of this node).
#  return a hash containing the count of the children raised and an array of any now empty nodes
sub raise_zerolength_children {
    my $self = shift;
    
    my %results = (
        empty_node_names => [],
        raised_count     => 0,
    );

    if ($self->is_terminal_node) {
        return wantarray ? %results : \%results;
    };
    
    my $children    = $self->get_children;
    my $child_count = @$children;

    if (! $self->is_root_node) {
        #  raise children with the same total length as their parent
        foreach my $child (@$children) {
            if ($child->get_total_length == $self->get_total_length) {
                #  add_children takes care of the parent refs
                $self->get_parent->add_children(children => [$child]);
                $results{raised_count} ++;
            }
        }
    }

    #  delete the node from the parent's list of children if all have been raised
    if ($results{raised_count} == $child_count) {
        $self->get_parent->delete_child (child => $self);
        push @{$results{empty_node_names}}, $self->get_name;  #  add to list of names deleted
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
    }
    
    #  now loop through any children and flatten them
    foreach my $child (@$children) {
        my %res = $child->raise_zerolength_children;
        $results{raised_count} += $res{raised_count};
        push @{$results{empty_node_names}}, @{$res{empty_node_names}};
    }
    
    return wantarray ? %results : \%results;
}

#  not really a list of only the refs, as it is a hash
sub get_terminal_node_refs {
    my $self = shift;
    
    my %descendents = $self->get_all_descendants;

    my %terminals = pairgrep {$b->is_terminal_node} %descendents;

    return wantarray ? %terminals : \%terminals;
}

#  get all the elements in the terminal nodes
my Readonly $get_terminal_elements_cache_val = \1;
sub get_terminal_elements {
    my $self = shift;
    my %args = (cache => 1, @_);  #  cache unless told otherwise

    state $cache_key = 'TERMINAL_ELEMENTS';
    #  we have cached values from a previous pass - return them unless told not to
    if ($args{cache}) {
        my $cache_ref = $self->get_cached_value ($cache_key);

        return wantarray ? %$cache_ref : $cache_ref
          if defined $cache_ref;
    }

    my %list;

    if ($self->is_terminal_node) {
        #  save a smidge of memory for large trees
        $list{$self->get_name} = $get_terminal_elements_cache_val;
    }
    else {
        foreach my $child ($self->get_children) {
            my $terminals = $child->get_terminal_elements(%args);
            @list{keys %$terminals} = values %$terminals;            
        }
    }    

    #  the values are really a hash, and need to be coerced into one when used
    if ($args{cache}) {
        $self->set_cached_value ($cache_key => \%list);
    }

    return wantarray ? %list : \%list;
}

sub get_terminal_element_count {
    my $self = shift;

    my $hash = $self->get_terminal_elements (@_);

    return scalar keys %$hash;
}

sub get_all_named_descendants {
    my $self = shift;
    my %args = (cache => 1, @_);  #  cache unless told otherwise

    state $cache_key = 'NAMED_DESCENDANTS';
    #  we have cached values from a previous pass - return them unless told not to
    if ($args{cache}) {
        my $cache_ref = $self->get_cached_value ($cache_key);

        return wantarray ? %$cache_ref : $cache_ref
          if defined $cache_ref;
    }

    my @list;

    #if (!$self->is_internal_node) {
    #    push @list, ($self->get_name, $self);
    #}
    #else {
        foreach my $child ($self->get_children) {
            if ($child->is_terminal_node) {
                push @list, ($child->get_name, $child);
            }
            else {
                push @list, $child->get_all_named_descendants (%args);
            }
        }
    #}

    #  the values are really a hash, and need to be coerced into one when used
    #  why not use a hash directly?  cargo cult leftover?  
    my %list = @list;
    if ($args{cache}) {
        foreach my $node_ref (grep {!isweak ($_)} values %list) {
            weaken $node_ref;
        }
        $self->set_cached_value ($cache_key => \%list);
    }

    return wantarray ? %list : \%list;
}

sub get_all_descendants_and_self {
    my $self = shift;

    my %descendents = $self->get_all_descendants(@_);
    my $name = $self->get_name;
    $descendents{$name} = $self;
    
    foreach my $node_name (keys %descendents) {
        if (! isweak $descendents{$node_name}) {
            weaken $descendents{$node_name};
        }
    }
    
    return wantarray ? %descendents : \%descendents;
}

sub get_names_of_all_descendants_and_self {
    my $self = shift;

    my %descendents = $self->get_names_of_all_descendants(@_);
    my $name = $self->get_name;
    $descendents{$name} = $self->get_child_count;
    
    return wantarray ? %descendents : \%descendents;
}

#  a left over - here just in case 
sub get_all_children {
    my $self = shift;
    return $self->get_all_descendants (@_);
}

sub get_descendent_count {
    my $self = shift;
    my $descendents = $self->get_all_descendants(@_);
    return scalar keys %$descendents;
}

#  get all the nodes (whether terminal or not) which are descendants of a node
sub get_all_descendants {
    my $self = shift;
    my %args = (
        cache => 0, #  no cache unless told otherwise
        @_,
    );

    if ($self->is_terminal_node) {
        return wantarray ? () : {};  #  empty hash by default
    }

    state $cache_key = 'DESCENDENTS';

    #  we have cached values from a previous pass - return them unless told not to
    if ($args{cache}) {
        my $cached_hash = $self->get_cached_value($cache_key);
        if ($cached_hash) {  # return copies to avoid later pollution
            return wantarray ? %$cached_hash : {%$cached_hash};
        }
    }

    my %list;
    my @ch_list = $self->get_children;
    while (my $node = shift @ch_list) {
        my $name = $node->get_name;
        $list{$name} = $node;
        push @ch_list, $node->get_children;
    }

    if ($args{cache}) {
        $self->set_cached_value($cache_key => \%list);
        weaken $list{$_} foreach keys %list;  #  could do values directly?
    }

    #  make sure we return copies to avoid pollution by other subs
    return wantarray ? %list : {%list};
}


#  get all the nodes (whether terminal or not) which are descendants of a node
sub get_names_of_all_descendants {
    my $self = shift;
    my %args = (
        cache => 1, #  cache unless told otherwise
        @_,
    );

    #  empty hash by default
    return wantarray ? () : {} if ($self->is_terminal_node);

    state $cache_key = 'DESCENDANT_NAMES';
    #  we have cached values from a previous pass - return them unless told not to
    if ($args{cache}) {
        my $cached_hash = $self->get_cached_value($cache_key);
        # return copies to avoid any later pollution
        return wantarray ? %$cached_hash : {%$cached_hash}
          if $cached_hash;
    }

    my @a_list;
    push @a_list, $self->get_children;
    foreach my $child (@a_list) {
        push @a_list, $child->get_children;
    }

    my %list;
    foreach my $node (@a_list) {
        my $name = $node->get_name;
        $list{$name} = $node->get_child_count;
    }

    if ($args{cache}) {
        $self->set_cached_value($cache_key => \%list);
    }

    #  make sure we return copies to avoid pollution by other subs
    return wantarray ? %list : {%list};
}

#  while loop cleaner than recursion
sub get_path_to_root_node {
    my $self = shift;
    my %args = (cache => 1, @_);  #  cache unless told not to

    #return wantarray ? ($self) : [$self] if $self->is_root_node;

    #  don't cache internals 
    #my $use_cache = $self->is_internal_node ? 0 : $args{cache};
    #my $use_cache = 1; # - override
    my $use_cache = $args{cache};

    state $cache_key = 'PATH_TO_ROOT_NODE';

    my $path;

    if ($use_cache) {
        $path = $self->get_cached_value($cache_key);
        #print ("using cache for " . $self->get_name . "\n") if $path;
        return wantarray ? @$path : $path
          if $path;
    }

    #$path = $self->get_parent->get_path_to_root_node (@_);
    #unshift @$path, $self;  #  used when recursing - needed to unwind
    my $node = $self;
    while ($node) {  #  undef when root node
        push @$path, $node;
        weaken $path->[-1] if !isweak $path->[-1];  #  paranoia - should not be weak
        $node = $node->get_parent;
    }

    if ($use_cache) {
        $self->set_cached_value ($cache_key => $path);
    }

    return wantarray ? @$path : $path;
}

sub get_path_lengths_to_root_node {
    my $self = shift;
    my %args = (cache => 1, @_);

    my $use_cache = $args{cache};  #  cache internals

    state $cache_key = 'PATH_LENGTHS_TO_ROOT_NODE';

    if ($use_cache) {
        my $path = $self->get_cached_value($cache_key);
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
        $self->set_cached_value ($cache_key => \%path_lengths);
    }

    return wantarray ? %path_lengths : \%path_lengths;
}

#  inconsistent with the non-aa version, as cache is passed
#  as a 0 in that version to disable it
sub get_path_lengths_to_root_node_aa {
    my ($self, $no_cache) = @_;

    state $cache_key = 'PATH_LENGTHS_TO_ROOT_NODE';
    if (!$no_cache) {
        my $path = $self->get_cached_value($cache_key);
        return (wantarray ? %$path : $path) if $path;
    }

    my %path_lengths;
    $path_lengths{$self->get_name} = $self->get_length;

    my $node = $self->get_parent;
    while ($node) {  #  undef when root node
        $path_lengths{$node->get_name} = $node->get_length;
        $node = $node->get_parent;
    }

    if (!$no_cache) {
        $self->set_cached_value ($cache_key => \%path_lengths);
    }

    return wantarray ? %path_lengths : \%path_lengths;
}


#  just a wrapper
sub get_path_length_array_to_root_node {
    my ($self, %args) = @_;
    $self->get_path_length_array_to_root_node_aa($args{no_cache});
}

sub get_path_length_array_to_root_node_aa {
    my ($self, $no_cache) = @_;

    state $cache_key = 'PATH_LENGTH_ARRAY_TO_ROOT_NODE';
    if (!$no_cache) {
        my $path = $self->get_cached_value($cache_key);
        return (wantarray ? @$path : $path) if $path;
    }

    my @path_lengths;
    my $node = $self;
    while ($node) {  #  undef when root node
        push @path_lengths, $node->get_length;
        $node = $node->get_parent;
    }

    if (!$no_cache) {
        $self->set_cached_value ($cache_key => \@path_lengths);
    }

    return wantarray ? @path_lengths : \@path_lengths;
}

#  just a wrapper
sub get_path_name_array_to_root_node {
    my ($self, %args) = @_;
    $self->get_path_name_array_to_root_node_aa($args{no_cache});
}

sub get_path_name_array_to_root_node_aa {
    my ($self, $no_cache) = @_;

    state $cache_name = 'PATH_NAME_ARRAY_TO_ROOT_NODE';
    if (!$no_cache) {
        my $path = $self->get_cached_value($cache_name);
        return (wantarray ? @$path : $path) if $path;
    }

    my @path;
    my $node = $self;
    while ($node) {  #  undef when root node
        push @path, $node->get_name;
        $node = $node->get_parent;
    }

    if (!$no_cache) {
        $self->set_cached_value ($cache_name => \@path);
    }

    return wantarray ? @path : \@path;
}


sub get_distance_to_root_node {
    my $self = shift;
    my %args = (cache => 1, @_);
    state $cache_key = 'PATH_DISTANCE_TO_ROOT_NODE';
    
    if ($args{cache}) {
        my $dist = $self->get_cached_value ($cache_key);
        return $dist if defined $dist;
    }
    
    my $path = $self->get_path_lengths_to_root_node_aa;
    my $distance = sum values %$path;
    $self->set_cached_value ($cache_key => $distance);
    
    return $distance;
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
        my $descendents = $self->get_all_descendants;
        if (exists $descendents->{$target_name}) {
            foreach my $child ($self->get_children) {
                my $child_name = $child->get_name;

                #  use the child or the child that is an ancestor of the target 
                my $ch_descendents = $child->get_all_descendants;
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

    my $ancestor = $args{ancestral_node} // croak "ancestral_node not defined\n";
    
    if (!$args{is_terminal_node} && $self->is_root_node) {
        my %result = ($self->get_name, $self->get_length);
        return wantarray ? %result : \%result;
    }

    #  don't cache internals
    my $use_cache
      = !$args{is_terminal_node} && $self->is_internal_node ? 0
      : $args{cache};

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

    my @list
      = grep {$_ !~ /^_/ and is_hashref $self->{$_}}
        keys %$self;

    return wantarray ? @list : \@list;
}

sub get_hash_lists_below {
    my $self = shift;
    
    my @list = $self->get_hash_lists;
    my %hash_list;
    @hash_list{@list} = undef;

    my @children = $self->get_children;
    while (my $child = shift @children) {
        my $list_below = $child->get_hash_lists;
        @hash_list{@$list_below} = undef;
        push @children, $child->get_children;
    }
    
    return wantarray
        ? keys %hash_list
        : [keys %hash_list];
}

#  check if a node is a TreeNode - used to check children for terminal entries
sub is_tree_node {  
    my $self = shift;
    my %args = @_;
    my $class = blessed $args{node};
    return if !$class;
    return $class eq blessed ($self);
}

#  could use isa operator in 5.32 and later
sub is_tree_node_aa {
    #my ($self, $node) = @_;
    my $class = blessed $_[1];
    return if !$class;
    return $class eq blessed ($_[0]);
}

sub is_terminal_node {
    !$_[0]->get_child_count;  #  terminal if it has no children
}

#  check if it is a "named" node, or internal (name ends in three underscores)
sub is_internal_node {
    $_[0]->get_name =~ /___$/;
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

    my $parent = $args{parent}
      // croak "argument 'parent' not specified\n";

    return if $self->{_PARENT} && $parent eq $self->{_PARENT};

    croak 'parent Reference not same type as child (' . blessed ($self) . ")\n"
        if blessed($parent) ne blessed($self);

    $self->{_PARENT} = $parent;

    #  avoid potential memory leakage caused by circular refs
    $self->weaken_parent_ref;
    
    return;
}

#  bare metal for speed
sub set_parent_aa {
    #my ($self, $parent) = @_;

    return if $_[0]->{_PARENT} && $_[1] eq $_[0]->{_PARENT};

    weaken ($_[0]->{_PARENT} = $_[1]);

    return;
}


sub get_parent {
    return $_[0]->{_PARENT};
}

sub delete_parent {
    my $self = shift;
    $self->{_PARENT} = undef;
    $self->delete_cached_values;
    #  should clear cache below unless
    #  told otherwise
    #$self->delete_cached_values_below;
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
    return if !$_[0]->{_PARENT} or isweak ($_[0]->{_PARENT});
    return weaken ($_[0]->{_PARENT});
}

sub get_parent_name {
    my ($self) = @_;
    my $parent = $self->get_parent
      // return '';
    return $parent->get_name;
}

sub is_root_node {
    return !$_[0]->get_parent;  #  if it's false then it's a root node
}

sub get_root_node {
    my $self = shift;
    
    while (my $parent = $self->get_parent) {
        $self = $parent;
    }
    
    return $self;
}

sub get_siblings {
    my $self = shift;
    return wantarray ? () : [] if $self->is_root_node;
    my @sibs = grep $_ != $self, $self->get_parent->get_children;
    return wantarray ? @sibs : \@sibs;
}

#  assign some plot coords to the nodes to allow reconstruction of
#  the dendrogram from a table
#  need to assign terminal y-values in order, and the parents take the average of the terminal y values.  
sub assign_plot_coords {
    my $self = shift;
    my %args = @_;
    
    say '[TreeNode] Assigning plot coords.  This will take a while for large trees.';

    $self->get_root_node->number_terminal_nodes;

    my $y_len = $self->get_terminal_element_count;
    my $x_len = $self->get_max_total_length;
    my $scale_factor = $args{plot_coords_scale_factor};

    if ($scale_factor && $args{scale_factor_is_relative}) {
        #  Scale factor is user-interpretable when this is set, so 4 means 4 times higher than wide.
        #  We just need to adjust for the actual ratio.  
        $scale_factor *= $x_len / $y_len;  
    }
    if (!$scale_factor or $scale_factor < 0) {
        $scale_factor = $x_len / $y_len;
    }

    my $max_y = $self->get_value('TERMINAL_NODE_LAST');
    my $max_total_length = $self->get_root_node->get_max_total_length;

    $self->assign_plot_coords_inner (
        scale_factor => $scale_factor,
        max_y        => $max_y,
        plot_coords_left_to_right => $args{plot_coords_left_to_right},
        max_total_length => $max_total_length,
    );

    return;
}


sub assign_plot_coords_inner {
    my $self = shift;
    my %args = @_;
    my $scale_factor  = $args{scale_factor} || 1;
    my $max_y         = $args{max_y} || 0;
    my $left_to_right = $args{plot_coords_left_to_right};
    my $max_total_length
      =   $args{max_total_length}
      //= $self->get_root_node->get_max_total_length;

    my ($y1, $y2, $y_pos);

    if ($self->is_terminal_node) {
        $y1 = $max_y - $self->get_value('TERMINAL_NODE_FIRST');
        $y2 = $max_y - $self->get_value('TERMINAL_NODE_LAST');
        $y1 *= $scale_factor;
        $y2 *= $scale_factor;
        $y_pos = ($y1 + $y2) / 2;
    }
    else {
        my @ch_y_pos;
        foreach my $child ($self->get_children) {
            $child->assign_plot_coords_inner (%args);
            my $coords = $child->get_list_ref_aa ('PLOT_COORDS');
            push @ch_y_pos, $coords->{plot_y1};
        }

        $y1 = List::Util::max (@ch_y_pos);
        $y2 = List::Util::min (@ch_y_pos);
        $y_pos = ($y1 + $y2) / 2;
    }

    #  all dists relative to max length of the tree
    #  have to compensate for get_length_above including this node
    my $end_x   = $max_total_length - $self->get_length_above + $self->get_length;
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

sub get_terminal_node_first_number {
    my $self = shift;
    no autovivification;
    my $values = $self->get_node_values;
    return $values->{TERMINAL_NODE_FIRST};
}

sub get_terminal_node_last_number {
    my $self = shift;
    no autovivification;
    my $values = $self->get_node_values;
    return $values->{TERMINAL_NODE_LAST};
}

#  number the nodes below this one based on the terminal nodes
#  this allows us to export to CSV and retain some of the topology
sub number_terminal_nodes {
    my $self = shift;
    my %args = @_;
    
    #  new alg.
    #  Climb down the tree, taking the "leftmost" child path
    #  When we hit a terminal, give it a number and climb back up
    #  then climb down the next child, etc
    #  Keep track of number of terminals encountered 
    my $left  = $args{count_sofar} || 0;
    my $right = $left;

    foreach my $child ($self->get_children) {
        if ($child->is_terminal_node) {
            $right++;
            $child->set_value(TERMINAL_NODE_FIRST => $right);
            $child->set_value(TERMINAL_NODE_LAST  => $right);
        }
        else {
            $right = $child->number_terminal_nodes (count_sofar => $right);
        }
    }

    $left += 1;
    $self->set_value(TERMINAL_NODE_FIRST => $left);
    $self->set_value(TERMINAL_NODE_LAST  => $right);

    return $right;
}

sub _number_terminal_nodes_old_alg {
    my $self = shift;
    my %args = @_;
    
    #  get the number of terminal elements (this will also cache them)
    my @te = keys %{$self->get_terminal_elements};

    my $prev_child_elements = $args{count_sofar} || 1;
    $self->set_value (TERMINAL_NODE_FIRST => $prev_child_elements);
    $self->set_value (TERMINAL_NODE_LAST => $prev_child_elements + $#te);
    foreach my $child ($self->get_children) {
        my $count = $child->_number_terminal_nodes_old_alg ('count_sofar' => $prev_child_elements);
        $prev_child_elements += $count;
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


sub set_bootstrap_value {
    my ($self, %args) = @_;
    my $key   = $args{ key   };
    my $value = $args{ value };

    my $bootstrap_block = $self->get_bootstrap_block;
    $bootstrap_block->set_value_aa( $key => $value );

    return;
}

sub get_bootstrap_value {
    my ($self, %args) = @_;
    my $key   = $args{ key   };

    my $bootstrap_block = $self->get_bootstrap_block();
    return $bootstrap_block->get_value( key => $key );
}

sub set_bootstrap_colour_aa {
    my ($self, $colour) = @_;
    my $bootstrap_block = $self->get_bootstrap_block;
    $bootstrap_block->set_colour_aa ($colour);
    return;
}

sub get_bootstrap_colour {
    my ($self) = @_;
    my $bootstrap_block = $self->get_bootstrap_block;
    return $bootstrap_block->get_colour;
}

sub get_bootstrap_colour_8bit_rgb {
    my ($self) = @_;
    my $bootstrap_block = $self->get_bootstrap_block;
    return $bootstrap_block->get_colour_8bit_rgb;
}

# isolate dealings with the underlying object hash to one function
sub get_bootstrap_block {
    my ($self) = @_;
    return
      $self->{_bootstrap_block}
      ||=  Biodiverse::TreeNode::BootstrapBlock->new;
}


#  convert the entire tree to a table structure, using a basestruct
#  object as an intermediate
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

    # figure out if we're meant to be exporting colours or not
    my $export_colours
        = !$self->get_bootstrap_block->has_exclusion( key => 'color' );
    
    # create a BaseStruct object to contain the table
    my $bs = Biodiverse::BaseStruct->new (
        NAME => $treename,
    );  #  may need to specify some other params


    my @header = qw /TREENAME NODE_NUMBER PARENTNODE LENGTHTOPARENT NAME/;
    if ( $export_colours ) {
        push @header, "COLOUR";
    }
    

    my ($parent_num, $taxon_name);
    
    my $max_sublist_digits = defined $args{sub_list}
                            ? length ($self->get_max_list_length_below (list => $args{sub_list}) - 1)
                            : undef;


    my @nodes = ($self);

    while (my $node = shift @nodes) {  #  while loop is repeatable
        push @nodes, $node->get_children;

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
        if( $export_colours ) {
            my $colour = $node->get_bootstrap_value (key => 'color');
            @data{@header} = ($treename, $number, $parent_num, 
                              $node->get_length || 0, $taxon_name, $colour);
        }
        else {
            @data{@header} = ($treename, $number, $parent_num, 
                              $node->get_length || 0, $taxon_name);
        }
        
        #  get the additional list data if requested
        if (defined $args{sub_list} && $args{sub_list} !~ /(no list)/) {
            my $sub_list_ref = $node->get_list_ref (list => $args{sub_list});
            if (defined $sub_list_ref) {
                if (is_arrayref ($sub_list_ref)) {
                    $sub_list_ref = $self->array_to_hash_values (
                        list             => $sub_list_ref,
                        prefix           => $args{sub_list},
                        num_digits       => $max_sublist_digits,
                        sort_array_lists => $args{sort_array_lists},
                    );
                }
                if (is_hashref($sub_list_ref)) {
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

    my $list_names = [qw/node_data/];

    if (defined $args{sub_list} && $args{sub_list} !~ /(no list)/) {
        $list_names = [qw/node_data sub_list/];
    }

    return $bs->to_table (@_, list_names => $list_names);    
}

sub to_basestruct_group_nodes {
    my $self = shift;
    my %args = @_;

    delete $args{target_value} if !$args{use_target_value};

    #  assign unique labels to nodes if needed
    $self->number_nodes if ! defined $self->get_value ('NODE_NUMBER');

    my $num_classes = $args{use_target_value} ? q{} : $args{num_clusters};

    croak "One of args num_clusters or use_target_value must be specified\n"
        if ! ($num_classes || $args{use_target_value});

    my $sub_list = $args{sub_list} // '';

    # build a BaseStruct object and set it up to contain the terminal elements
    my $bs = Biodiverse::BaseStruct->new (
        NAME => 'TEMP',
    );

    my $get_node_method = $args{terminals_only}
        ? 'get_terminal_elements'
        : 'get_all_descendants_and_self';

    foreach my $element (sort keys %{$self->$get_node_method}) {
        $bs->add_element (element => $element);
    }

    if (defined $args{target_value}) {
        say "Target value is $args{target_value}.";
    }

    my %target_nodes = $self->group_nodes_below (
        %args,
        num_clusters => $num_classes
    );

    if (defined $args{sub_list} && $args{sub_list} !~ /(no list)/) {
        say "[TREE] Adding values from sub list $args{sub_list} to each node";
    } 

    say "[TREE] Actual number of groups identified is " . scalar (keys %target_nodes);

    my $want_sub_list = (defined $sub_list && $sub_list !~ /(no list)/);

    my $max_sublist_digits;
    if ($want_sub_list) {
        $max_sublist_digits
          = length
              $self->get_max_list_length_below (
                list => $args{sub_list}
              );
        --$max_sublist_digits;
    }

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
        my $sub_list_ref;
        if ($want_sub_list) {
            $sub_list_ref = $node->get_list_ref (list => $sub_list) // {};
            if (is_arrayref($sub_list_ref)) {
                $sub_list_ref = $self->array_to_hash_values (
                    list   => $sub_list_ref,
                    prefix => $sub_list,
                    num_digits => $max_sublist_digits,
                    sort_array_lists => $args{sort_array_lists},
                );
            }
            #if (is_hashref($sub_list_ref)) {
            #    @data{keys %$sub_list_ref} = (values %$sub_list_ref);
            #}
        }

        #  loop through all the terminal elements in this cluster and assign the values
        my @elements = keys %{$node->$get_node_method};
        foreach my $element (sort @elements) {
            $bs->add_to_hash_list (
                element => $element,
                list    => 'node_data',
                %data,
            );
            if ($want_sub_list) {
                $bs->add_to_hash_list (
                    element => $element,
                    list    => 'sub_list',
                    %$sub_list_ref,
                );
            }
        }
    }

    return $bs;
}


#  print the tree out to a nexus format file.
#  basically builds a taxon block and then passes that through to to_newick
sub to_nexus {
    my $self = shift;
    my %args = @_;

    my $string;
    my $tree_name = $args{tree_name} || $self->get_param ('NAME') || 'Biodiverse_tree';

    my $quote_char = q{'};
    my $csv_obj = $self->get_csv_object (
        quote_char  => $quote_char,
        escape_char => $quote_char,
        quote_space => 1,
    );

    my $translate_table_block = '';
    my %remap;

    if (not $args{no_translate_block}) {
        #  build a hash of the label names for the taxon block, unless told not to
        #  SWL 20140911: There is no support for external remaps now, so do we need th checks?   
        if (! defined $args{remap} && ! $args{no_remap}) {
            #  get a hash of all the nodes in the tree.
            my $nodes = $self->get_all_descendants;
    
            my $i = 0;
            foreach my $node ($self, values %$nodes) {
                #  no remap for internals - TreeView does not like it
                next if ! $args{use_internal_names} && $node->is_internal_node;  
                $remap{$node->get_name} = $i;
                $i++;
            }
        }

        my %reverse_remap;
        @reverse_remap{values %remap} = (keys %remap);

        my $j = 0;
        my $translate_table = '';
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
        $translate_table_block = "\tTranslate \n$translate_table\n";
    }

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
    
    #  need to ensure any names are quoted in the newick portion
    #  as colons wreak havoc otherwise
    $csv_obj->always_quote (1);

    $string .= "#NEXUS\n";
    $string .= "[ID: $tree_name]\n";
    $string .= "begin trees;\n";
    $string .= "\t[Export of a $type tree using Biodiverse::TreeNode version $VERSION]\n";
    $string .= $translate_table_block;
    $string .= "\tTree $tree_name = " . $self->to_newick (remap => \%remap, csv_object => $csv_obj, %args) . ";\n";
    $string .= "end;\n\n";

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
        my $csv_obj = $args{csv_object} ||
             $self->get_csv_object (
                quote_char   => $quote_char,
                escape_char  => $quote_char,
                always_quote => 1,
            );
        $name = $self->list2csv (csv_object => $csv_obj, list => [$name]);
        #$name = "'$name'";  #  quote otherwise
    }
    
    # build the bootstrap block if needed
    my $bootstrap_string = '';
    if (my $colour_hash = $args{colour_hash}) {
        my $bootstrap_block = $self->get_bootstrap_block();
        my $aref = $colour_hash->{$self->get_name};
        $bootstrap_string = $bootstrap_block->encode(
            colour => $aref,
        );
    }
    elsif ($args{sub_list} || $args{export_colours} || $args{include_colours}) {
        my $bootstrap_block = $self->get_bootstrap_block();
        $bootstrap_string = $bootstrap_block->encode (
            include_colour => $args{export_colours} || $args{include_colours},
        );
    }

    my $length = $self->get_length;
    $length =~ s/,/./;  #  hack for issue #775 (another comma radix char)
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
        $string .= $bootstrap_string;
        if (defined $length) {
            $string .= ":" . $length;
        }
    }
    # terminal nodes
    else {
        $string .= $name;
        $string .= $bootstrap_string;

        if (defined $length) { 
            $string .= ":" . $length;
        }
    }
    
    return $string;
}

#  convert the tree to the same structure as used by the R phylo system
#  this cannot be a recursive function
sub to_R_phylo {
    my $self = shift;
    my %args = (use_internal_names => 1, @_);
    my $remap = $args{remap} || {};
    my $use_int_names = $args{use_internal_names};

    use Sort::Key::Multi qw/iskeysort/;
    my $terminals = $self->get_terminal_node_refs;

    my @nodes = iskeysort {($_->get_depth, $_->get_name)} values %$terminals;

    # push @nodes, $self;  # no self in node array
    my (@length_arr, @parent_id_arr, @tip_labels, @internal_labels);
    my @node_id_arr = (1..@nodes);
    my %name_id_hash;
    @name_id_hash{map {$_->get_name} @nodes} = @node_id_arr;
    my $max_node_id = 1 + @node_id_arr;
    my $root_id     = $max_node_id;
    $name_id_hash{$self->get_name} =  $root_id;

    my $quote_char = q{'};
    my $csv_obj = $args{csv_object} ||
        $self->get_csv_object(
            quote_char   => $quote_char,
            escape_char  => $quote_char,
            always_quote => 1,
        );

  NODE:
    while (my $node = shift @nodes) {

        my $orig_name = $node->get_name;
        if (!$name_id_hash{$orig_name}) {
            $max_node_id++;
            $name_id_hash{$orig_name} =  $max_node_id;
        }

        my $name = defined $remap->{$orig_name}
            ? $remap->{$orig_name}
            : $orig_name;
                # : $self->list2csv(csv_object => $csv_obj, list => [ $orig_name ]);

        my $length = $node->get_length;
        $length =~ s/,/./; #  hack for issue #775 (another comma radix char)

        if ($node->is_terminal_node) {
            push @tip_labels, $name;
        }
        else {
            push @internal_labels, $name;
            push @node_id_arr,  $name_id_hash{$orig_name};
        }

        next NODE if $node->is_root_node;

        push @length_arr, $length;

        my $parent_id;
        my $parent = $node->get_parent;

        my $parent_name = $parent->get_name;
        $parent_id =$name_id_hash{$parent_name};
        if (!$parent_id) {
            $max_node_id++;
            $name_id_hash{$parent_name}
                = $parent_id
                =  $max_node_id;
            push @nodes, $parent;
        }

        push @parent_id_arr, $parent_id;
    }

    my %str = (
        'edge'        => [@parent_id_arr, @node_id_arr],
        'edge.length' => \@length_arr,
        'Nnode'       => (scalar @internal_labels + 1),
        'node.label'  => \@internal_labels,
        'tip.label'   => \@tip_labels,
        'root.edge'   => $self->get_length,
    );

    return wantarray ? %str :   \%str;
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
    
    #  set a direct ref?
    #  currently overrides any previous values so take care
    #  should it be in its own sub?
    my $use_ref = delete $args{use_ref};
    
    #  create the list if not already there and then add to it
    while (my ($list, $values) = each %args) {
        if ($use_ref) {
            $self->{$list} = $values;
        }
        elsif (is_hashref($values)) {
            if (!$self->{$list}) {
                $self->{$list} = {%$values};
            }
            else {
                next if !scalar keys %$values;
                @{$self->{$list}}{keys %$values} = values %$values;
            }
       }
        elsif (is_arrayref($values)) {
            if (!$self->{$list}) {
                $self->{$list} = [@$values];
            }
            else {
                next if !scalar @$values;
                push @{$self->{$list}}, @$values;
            }
        }
        else {
            croak "add_to_lists warning, no valid list ref passed\n";
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
        if not defined $lists or !is_arrayref($lists);
    
    foreach my $list (@$lists) {
        next if ! exists $self->{$list};
        $self->{$list} = undef;
        delete $self->{$list};
    }
    
    return;
}

#  rename a list in this node
sub rename_list {
    my $self = shift;
    my %args = @_;
    
    my $list = $args{list};
    my $new_name = $args{new_name};
    
    croak "Argument 'list' not defined"
      if !defined $list;
    croak "Argument 'new_name' is not defined"
      if !defined $new_name;

    #croak "element $element does not contain a list called $list"
    return if !exists $self->{$list};

    $self->{$new_name} = $self->{$list};
    delete $self->{$list};

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
    my ($self, %args) = @_;

    return wantarray ? keys %$self : [keys %$self]
      if !$args{no_array_lists};

    my @lists = grep {is_hashref $self->{$_}} keys %$self;
    return wantarray ? @lists : \@lists;
}

#  get a list of all the lists contained in the
#  tree below and including this node
#  Could linearise this
sub get_list_names_below {
    my $self = shift;
    my %args = @_;
    
    my %list_hash;
    my $lists = $self->get_list_names (
        no_array_lists => $args{no_array_lists},
    );
    @list_hash{@$lists} = 1 x scalar @$lists;
    
    my $descendants = $self->get_all_descendants;
    
    foreach my $child (values %$descendants) {
        $lists = $child->get_list_names (
            no_array_lists => $args{no_array_lists},
        );
        @list_hash{@$lists} = 1 x scalar @$lists;
    }
    
    # a bit of repeated cleanup, but we need to guarantee we get them if needed
    if (! $args{show_hidden_lists}) {
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
    if (is_arrayref($list_ref)) {
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
    defined $list ? $self->{$list} : undef;
}

sub get_list_ref_aa {
    my ($self, $list) = @_;
    defined $list ? $self->{$list} : undef;
}


sub get_node_range {
    my $self = shift;
    my %args = @_;

    my $bd = $args{basedata_ref} || croak "argument basedata_ref not provided\n";

    #  need to apply some caching using the $bd ref in the key
    my $cache_key = 'NODE_RANGE_' . $bd;
    my $cached_range = $self->get_cached_value ($cache_key);

    return $cached_range if defined $cached_range;

    my $children =  $self->get_all_named_descendants;
    my @labels   = ($self->get_name, keys %$children);

    ##  collect the set of non-internal (named) nodes
    ##  Possibly should only work with terminals
    ##  which would simplify things.
    #foreach my $name (keys %$children) {
    #    next if $children->{$name}->is_internal_node;
    #    push (@labels, $name);
    #}

    my $range = $bd->get_range_union (labels => \@labels, return_count => 1);

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
    
    $self->get_root_node->delete_cached_values_below;

    return wantarray ? %reordered : \%reordered;
}

sub get_nri_tce_score {
    my ($self, %args) = @_;
    state $cache_name = 'NRI_TCE_SCORE';
    my $value = $self->get_cached_value ($cache_name);
    if (!defined $value) {
        #  we need to do the whole tree
        my $root = $self->get_root_node;
        while ($root->get_child_count == 1) {
            my $child_arr = $root->get_children;
            $root = $child_arr->[0];
        }
        $root->_calc_nri_tce_score;
        #  now it will be cached
        $value = $self->get_cached_value ($cache_name);
    }
    return $value;
}

#  Algorithm from Tsirogiannis et al. (2012).
#  https://doi.org/10.1007/978-3-642-33122-0_3
#  Be sure to call from last common ancestor of all tips.
#  Normally this is the root, but sometimes there are
#  "spare" single-child nodes immediately below the root.
sub _calc_nri_tce_score {
    my ($self, %args) = @_;

    my $all_weights = $args{all_weights} // $self->get_nri_all_weights;

    my $sum_anc1 = $args{sum_anc1} // 0;
    my $sum_anc2 = $args{sum_anc2} // 0;
    my $length   = $self->get_length;
    my $se       = $self->get_terminal_element_count;
    my $s        = $args{s} // $self->get_root_node->get_terminal_element_count;
    my $sum_off  = 0;

    foreach my $child ($self->get_children) {
        my $ch_len = $child->get_length;
        my $sl     = $child->get_terminal_element_count;
        $sum_off += $child->_calc_nri_tce_score (
            s           => $s,
            sum_anc1    => $sum_anc1 + $ch_len * ($s - $sl),
            sum_anc2    => $sum_anc2 + $ch_len * $sl,
            all_weights => $all_weights,
        );
    }
    my $SO = ($s - $se) * $sum_off;
    my $SA = $se * $sum_anc1;
    my $SI = $se * ($all_weights - $sum_anc2 - $sum_off);

    $self->set_cached_value (NRI_TCE_COMPONENTS => [$SA, $SO, $SI]);
    
    my $value = $SO + $SA + $SI;
    
    
    state $cache_name = 'NRI_TCE_SCORE';
    $self->set_cached_value ($cache_name => $value);
    
    return $sum_off + $length * $se;
}


sub get_nri_all_weights {
    my ($self, %args) = @_;

    state $cache_name = 'NRI_ALL_WEIGHTS';

    my $root = $self->get_root_node;
    my $value = $root->get_cached_value ($cache_name);

    return $value if $value;

    #  handle single child roots, e.g. where a major clade was excised
    #  so the last shared ancestor for all terminals is not the root
    my $lca_node = $root;
    while ($lca_node->get_child_count == 1) {
        my $children = $lca_node->get_children;
        $lca_node = $children->[0];
    }

    my $nodes = $lca_node->get_all_descendants;
    $value
      = sum
        map {$_->get_length * $_->get_terminal_element_count}
        values %$nodes;

    $root->set_cached_value ($cache_name => $value);

    return $value;
}

sub _get_len_sum_by_tip_count_hash {
    my $self = shift;

    state $cache_key = 'LEN_SUM_BY_TIP_COUNT_HASH';
    my $hash = $self->get_cached_value ($cache_key);
    if ($hash) {
        return wantarray ? %$hash : $hash; 
    }

    $hash->{$self->get_terminal_element_count} += $self->get_length;
    foreach my $child ($self->get_children) {
        my $ch_hash = $child->_get_len_sum_by_tip_count_hash;
        foreach my ($tc, $val) (%$ch_hash) {
            $hash->{$tc} += $val;
        }
    }
    $self->set_cached_value($cache_key => $hash);

    return wantarray ? %$hash : $hash;
}


sub numerically {$a <=> $b}

1;

__END__

=head1 NAME

Biodiverse::????

=head1 SYNOPSIS

  use Biodiverse::????;
  $object = Biodiverse::TreeNode->new();

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
