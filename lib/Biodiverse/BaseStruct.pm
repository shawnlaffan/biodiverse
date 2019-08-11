package Biodiverse::BaseStruct;

#  Package to provide generic methods for the
#  GROUPS and LABELS sub components of a Biodiverse object,
#  and also for the SPATIAL ones

#  Need a mergeElements method

use strict;
use warnings;
use Carp;
use 5.010;

use English ( -no_match_vars );

use Data::Dumper;
use Scalar::Util qw /looks_like_number reftype/;
use List::Util qw /min max sum any/;
use List::MoreUtils qw /first_index/;
use File::Basename;
use Path::Class;
use POSIX qw /fmod floor/;
use Time::localtime;
use Ref::Util qw { :all };
use Sort::Key::Natural qw /natsort rnatsort/;

our $VERSION = '2.99_005';

my $EMPTY_STRING = q{};

use parent qw /
    Biodiverse::Common
    Biodiverse::BaseStruct::Export
/;

use Biodiverse::Statistics;
my $stats_class = 'Biodiverse::Statistics';

my $metadata_class = 'Biodiverse::Metadata::BaseStruct';
use Biodiverse::Metadata::BaseStruct;

use Biodiverse::Metadata::Export;
my $export_metadata_class = 'Biodiverse::Metadata::Export';

use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';

sub new {
    my $class = shift;

    my $self = bless {}, $class;

    my %args = @_;

    # do we have a file to load from?
    my $file_loaded;
    if ( defined $args{file} ) {
        $self->load_file( @_ );
    };
    return $file_loaded if defined $file_loaded;

    #  default parameters to load.  These will be overwritten if needed.
    my %params = (  
        OUTPFX              =>  'BIODIVERSE_BASESTRUCT',
        OUTSUFFIX           => 'bss',
        #OUTSUFFIX_XML      => "bsx",
        OUTSUFFIX_YAML      => 'bsy',
        TYPE                => undef,
        OUTPUT_QUOTE_CHAR   => q{"},
        OUTPUT_SEP_CHAR     => q{,},   #  used for output data strings
        QUOTES              => q{'},
        JOIN_CHAR           => q{:},   #  used for labels and groups
        #INDEX_CONTAINS     => 4,  #  average number of basestruct elements per index element
        PARAM_CHANGE_WARN   => undef,
    );

    #  load the defaults, with the rest of the args as params
    my @args_for = (%params, @_);
    $self->set_params (@args_for);

    # predeclare the ELEMENT subhash (don't strictly need to do it...)
    $self->{ELEMENTS} = {};  

    #  avoid memory leak probs with circular refs
    $self->weaken_basedata_ref;

    return $self;
}

sub metadata_class {
    return $metadata_class;
}

sub rename {
    my $self = shift;
    my %args = @_;

    my $name = $args{new_name};
    if (not defined $name) {
        croak "[Basestruct] Argument 'new_name' not defined\n";
    }

    $self->set_param (NAME => $name);

    return;
}

#  a bit fragile
sub get_axis_count {
    my $self = shift;

    my $elements = $self->get_element_list;
    my $el       = $elements->[0];
    my $axes     = $self->get_element_name_as_array (element => $el);

    return scalar @$axes;
}

sub get_reordered_element_names {
    my $self = shift;
    my %args = @_;

    my %reordered;

    my $axis_count = $self->get_axis_count;

    return wantarray ? %reordered : \%reordered
      if $axis_count == 1;

    my $csv_object = $args{csv_object};

    my @reorder_cols = @{$args{reordered_axes}};
    my $reorder_count = scalar @reorder_cols;
    croak "Attempting to reorder more axes ($reorder_count) "
        . "than are in the basestruct ($axis_count)\n"
      if scalar $reorder_count > $axis_count;

    my $i = 0;
    foreach my $col (@reorder_cols) {
        if (not defined $col) {  #  undef cols stay where they are
            $col = $i;
        }
        elsif ($col < 0) {  #  make negative subscripts positive for next check step
            $col += $axis_count;
        }
        $i++;
    }

    #  is the new order out of bounds?
    my $max_subscript = $axis_count - 1;
    my $min = List::Util::min(@reorder_cols);
    my $max = List::Util::max(@reorder_cols);
    croak "reordered axes are out of bounds ([$min..$max] does not match [0..$max_subscript])\n"
      if $min != 0 || $max != $max_subscript;  # out of bounds

    #  if we don't have all values assigned then we have issues
    my %tmp;
    @tmp{@reorder_cols} = undef;
    croak "incorrect or clashing axes\n"
      if scalar keys %tmp != scalar @reorder_cols;

    my $quote_char = $self->get_param('QUOTES');
    foreach my $element ($self->get_element_list) {
        my $el_array = $self->get_element_name_as_array (element => $element);
        my @new_el_array = @$el_array[@reorder_cols];

        my $new_element = $self->list2csv (
            list       => \@new_el_array,
            csv_object => $csv_object,
        );
        $self->dequote_element(element => $new_element, quote_char => $quote_char);

        $reordered{$element} = $new_element;
    }

    return wantarray ? %reordered : \%reordered;
}


#  convert the elements to a tree format, eg family - genus - species
#  won't make sense for many types of basedata, but oh well.  
sub to_tree {
    my $self = shift;
    my %args = @_;

    my $name = $args{name} // $self->get_param ('NAME') . "_AS_TREE";
    my $tree = Biodiverse::Tree->new (NAME => $name);

    my $elements = $self->get_element_hash;

    my $quotes = $self->get_param ('QUOTES');  #  for storage, not import
    my $el_sep = $self->get_param ('JOIN_CHAR');
    my $csv_obj = $self->get_csv_object (
        sep_char   => $el_sep,
        quote_char => $quotes,
    );

    foreach my $element (keys %$elements) {
        my @components = $self->get_element_name_as_array (element => $element);
        #my @so_far;
        my @prev_names = ();
        #for (my $i = 0; $i <= $#components; $i++) {
        foreach my $i (0 .. $#components) {
            #$so_far[$i] = $components[$i];
            my $node_name = $self->list2csv (
                csv_object  => $csv_obj,
                list        => [@components[0..$i]],
            );
            $node_name = $self->dequote_element (
                element    => $node_name,
                quote_char => $quotes,
            );

            my $parent_name = $i ? $prev_names[$i-1] : undef;  #  no parent if at highest level

            if (not $tree->node_is_in_tree (node => $node_name)) {
                my $node = $tree->add_node (
                    name   => $node_name,
                    length => 1,
                );

                if ($parent_name) {
                    my $parent_node = $tree->get_node_ref (node => $parent_name);
                    #  create the parent if need be - SHOULD NOT HAPPEN
                    #if (not defined $parent_node) {
                    #    $parent_node = $tree->add_node (name => $parent_name, length => 1);
                    #}
                    #  now add the child with the element as the name so we can link properly to the basedata in labels tab
                    $node->set_parent (parent => $parent_node);
                    $parent_node->add_children (children => [$node]);
                }
            }
            #push @so_far, $node_name;
            $prev_names[$i] = $node_name;
        }
    }

    #  set a master root node of length zero if we have more than one.
    #  All the current root nodes will be its children
    my $root_nodes = $tree->get_root_node_refs;
    my $root_node  = $tree->add_node (name => '0___', length => 0);
    $root_node->add_children (children => [@$root_nodes]);
    foreach my $node (@$root_nodes) {
        $node->set_parent (parent => $root_node);
    }

    $tree->set_parents_below;  #  run a clean up just in case
    return $tree;
}

sub get_element_count {
    my $self = shift;
    my $el_hash = $self->{ELEMENTS};
    return scalar keys %$el_hash;
}

sub get_element_list {
    my $self = shift;
    my $el_hash = $self->{ELEMENTS};
    return wantarray ? keys %$el_hash : [keys %$el_hash];
}

sub sort_by_axes {
    my $self = shift;
    my $item_a = shift;
    my $item_b = shift;

    my $axes = $self->get_cell_sizes;
    my $res = 0;
    my $a_array = $self->get_element_name_as_array (element => $item_a);
    my $b_array = $self->get_element_name_as_array (element => $item_b);
    foreach my $i (0 .. $#$axes) {
        $res = $axes->[$i] < 0
            ? $a_array->[$i] cmp $b_array->[$i]
            : $a_array->[$i] <=> $b_array->[$i];

        return $res if $res;
    }

    return $res;
};

#  get a list sorted by the axes
sub get_element_list_sorted {
    my $self = shift;
    my %args = @_;

    my @list = $args{list} ? @{$args{list}} : $self->get_element_list;
    my @array = sort {$self->sort_by_axes ($a, $b)} @list;

    return wantarray ? @array : \@array;
}

# pass in a string def query, this returns a list of all elements that
# pass the def query.
sub get_elements_that_pass_def_query {
    my ($self, %args) = @_;
    my $def_query = $args{defq};    
    
    my $elements_that_pass_hash = 
        $self->get_element_hash_that_pass_def_query( defq => $args{defq} );

    my @elements_that_pass = keys %$elements_that_pass_hash;
    
    return wantarray ? @elements_that_pass : \@elements_that_pass;
}

# gets the complete element hash and then weeds out elements that
# don't pass a given def query.
sub get_element_hash_that_pass_def_query {
    my ($self, %args) = @_;
    my $def_query = $args{defq};
     
    $def_query =
        Biodiverse::SpatialConditions::DefQuery->new(
            conditions => $def_query, );

    my $bd = $self->get_basedata_ref;
    if (Biodiverse::MissingBasedataRef->caught) {
        # What do we do here?
        say "[BaseStruct.pm]: Missing BaseStruct in 
                       get_elements_hash_that_pass_def_query";
        return;
    }
    
    my $groups        = $bd->get_groups;
    my $element       = $groups->[0];

    my $elements_that_pass_hash = $bd->get_neighbours(
        element            => $element,
        spatial_conditions => $def_query,
        is_def_query       => 1,
        );

    
    # at this stage we have a hash in the form "element_name" -> 1 to
    # indicate that it passed the def query. We want this in the form
    # "element_name" -> all the data about this element. This is the
    # format used by get_element_hash and so by a lot of the
    # basestruct functions.
    
    my %formatted_element_hash = $self->get_element_hash;

    my %formatted_elements_that_pass;
    foreach my $element (keys %formatted_element_hash) {
        if ($elements_that_pass_hash->{$element}) {
            $formatted_elements_that_pass{$element} 
                  = $formatted_element_hash{$element};
        }
    }
    
    return \%formatted_elements_that_pass;
}

sub get_element_hash {
    my $self = shift;

    my $elements = $self->{ELEMENTS};

    return wantarray ? %$elements : $elements;
}

sub get_element_name_as_array_aa {
    my ($self, $element) = @_;

    return $self->get_array_list_values_aa ($element, '_ELEMENT_ARRAY');
}

sub get_element_name_as_array {
    my $self = shift;
    my %args = @_;

    my $element = $args{element} //
      croak "element not specified\n";

    return $self->get_array_list_values (
        element => $element,
        list    => '_ELEMENT_ARRAY',
    );
}

#  get a list of the unique values for one axis
sub get_unique_element_axis_values {
    my $self = shift;
    my %args = @_;

    my $axis = $args{axis};
    croak "get_unique_element_axis_values: axis arg not defined\n"
      if !defined $axis;

    my %values;

    ELEMENT:
    foreach my $element ($self->get_element_list) {
        my $coord_array
          = $self->get_element_name_as_array (element => $element);

        croak "not enough axes\n" if !exists ($coord_array->[$axis]);

        $values{$coord_array->[$axis]} ++;
    }

    return wantarray ? keys %values : [keys %values];
}

#  get a coordinate for the element
#  allows us to handle text axes for display
sub get_element_name_coord {
    my $self = shift;
    my %args = @_;
    defined $args{element} || croak "element not specified\n";
    my $element = $args{element};

    my $values = eval {
        $self->get_array_list_values (element => $element, list => '_ELEMENT_COORD');
    };
    if (Biodiverse::BaseStruct::ListDoesNotExist->caught) {  #  doesn't exist, so generate it 
        $self->generate_element_coords;
        $values = $self->get_element_name_coord (element => $element);
    }
    #croak $EVAL_ERROR if $EVAL_ERROR;  #  need tests before putting this in.  

    return wantarray ? @$values : $values;
}

#  generate the coords
sub generate_element_coords {
    my $self = shift;

    $self->delete_param ('AXIS_LIST_ORDER');  #  force recalculation for first one

    #my @is_text;
    foreach my $element ($self->get_element_list) {
        my $element_coord = [];  #  make a copy
        my $cell_sizes = $self->get_cell_sizes;
        #my $element_array = $self->get_array_list_values (element => $element, list => '_ELEMENT_ARRAY');
        my $element_array = eval {$self->get_element_name_as_array (element => $element)};
        if ($EVAL_ERROR) {
            print "PRIBBLEMMS";
            say Data::Dumper::Dump $self->{ELEMENTS}{$element};
        }
        

        foreach my $i (0 .. $#$cell_sizes) {
            if ($cell_sizes->[$i] >= 0) {
                $element_coord->[$i] = $element_array->[$i];
            }
            else {
                $element_coord->[$i] = $self->get_text_axis_as_coord (
                    axis => $i,
                    text => $element_array->[$i] // '',
                );
            }
        }
        $self->{ELEMENTS}{$element}{_ELEMENT_COORD} = $element_coord;
    }

    return 1;
}

sub get_text_axis_as_coord {
    my $self = shift;
    my %args = @_;
    my $axis = $args{axis};
    my $text = $args{text};
    croak 'Argument "text" is undefined' if !defined $text;

    #  store the axes as an array of hashes with value being the coord
    my $lists = $self->get_param ('AXIS_LIST_ORDER') || [];

    if (! $args{recalculate} and defined $lists->[$axis]) {  #  we've already done it, so return what we have
        return $lists->[$axis]{$text};
    }

    my %this_axis;
    #  go through and get a list of all the axis text
    foreach my $element (sort $self->get_element_list) {
        my $axes = $self->get_element_name_as_array_aa ($element);
        $this_axis{$axes->[$axis] // ''}++;
    }
    #  assign a number based on the sort order.
    #  "z" will be lowest, "a" will be highest
    @this_axis{rnatsort keys %this_axis}
      = (0 .. scalar keys %this_axis);
    $lists->[$axis] = \%this_axis;

    $self->set_param (AXIS_LIST_ORDER => $lists);

    return $lists->[$axis]{$text};
}

sub get_sub_element_list {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element} // croak "argument 'element' not specified\n";

    my $el_hash = $self->{ELEMENTS}{$element}{SUBELEMENTS}
      // return;

    return wantarray ?  keys %$el_hash : [keys %$el_hash];
}

sub get_sub_element_hash {
    my $self = shift;
    my %args = @_;

    no autovivification;
    
    my $element = $args{element}
      // croak "argument 'element' not specified\n";

    #  Ideally we should throw an exception, but at the moment too many other
    #  things need a result and we aren't testing for them.
    my $hash = $self->{ELEMENTS}{$element}{SUBELEMENTS} // {};
      #// Biodiverse::NoSubElementHash->throw (
      #      message => "Element $element does not exist or has no SUBELEMENT hash\n",
      #  );

    #  No explicit return statement used here.  
    #  This is a hot path when called from Biodiverse::Indices::_calc_abc
    #  and perl versions pre 5.20 do not optimise the return.
    #  End result is ~30% faster for this line, although that might not
    #  translate to much in real terms when it works at millions of iterations per second
    #  (hence the lack of further optimisations on this front for now).
    wantarray ? %$hash : $hash;
}

sub get_sub_element_hash_aa {
    my ($self, $element) = @_;

    no autovivification;

    croak "argument 'element' not specified\n"
      if !defined $element;

    #  Ideally we should throw an exception, but at the moment too many other
    #  things need a result and we aren't testing for them.
    my $hash = $self->{ELEMENTS}{$element}{SUBELEMENTS} // {};

    wantarray ? %$hash : $hash;
}

sub get_subelement_count {
    my $self = shift;

    my %args = @_;
    my $element = $args{element};
    croak "argument 'element' not defined\n" if ! defined $element;

    my $sub_element = $args{sub_element};
    croak "argument 'sub_element' not defined\n" if ! defined $sub_element;

    if (exists $self->{ELEMENTS}{$element} && exists $self->{ELEMENTS}{$element}{SUBELEMENTS}{$sub_element}) {
        return $self->{ELEMENTS}{$element}{SUBELEMENTS}{$sub_element};
    }

    return;
}

#  pre-assign the hash buckets to avoid rehashing larger structures
sub _set_elements_hash_key_count {
    my $self = shift;
    my %args = @_;

    my $count = $args{count} // 'undef';

    #  do nothing if undef, zero or negative
    croak "Invalid count argument $count\n"
      if !looks_like_number $count || $count < 0;

    my $href = $self->{ELEMENTS};

    return if $count <= scalar keys %$href;  #  needed?

    return keys %$href = $count;
}


#  add an element to a baseStruct object
sub add_element {  
    my $self = shift;
    my %args = @_;

    my $element = $args{element} //
      croak "element not specified\n";

    #  don't re-create the element array
    return if $self->{ELEMENTS}{$element}{_ELEMENT_ARRAY};

    my $quote_char = $self->get_param('QUOTES');
    my $element_list_ref = $self->csv2list(
        string     => $element,
        sep_char   => $self->get_param('JOIN_CHAR'),
        quote_char => $quote_char,
        csv_object => $args{csv_object},
    );

    if (scalar @$element_list_ref == 1) {
        $element_list_ref->[0] //= ($quote_char . $quote_char)
    }
    else {
        for my $el (@$element_list_ref) {
            $el //= $EMPTY_STRING;
        }
    }

    $self->{ELEMENTS}{$element}{_ELEMENT_ARRAY} = $element_list_ref;

    return;
}

sub add_sub_element {  #  add a subelement to a BaseStruct element.  create the element if it does not exist
    my $self = shift;
    my %args = (count => 1, @_);

    no autovivification;

    my $element = $args{element} //
      croak "element not specified\n";

    my $sub_element = $args{subelement} //
      croak "subelement not specified\n";

    my $elts_ref = $self->{ELEMENTS};

    if (! exists $elts_ref->{$element}) {
        $self->add_element (
            element    => $element,
            csv_object => $args{csv_object},
        );
    }

    #  previous base_stats invalid - clear them if needed
    #if (exists $self->{ELEMENTS}{$element}{BASE_STATS}) {
        delete $elts_ref->{$element}{BASE_STATS};
    #}

    $elts_ref->{$element}{SUBELEMENTS}{$sub_element} += $args{count};

    return;
}

#  array args version for high frequency callers
sub add_sub_element_aa {
    my ($self, $element, $sub_element, $count, $csv_object) = @_;

    croak "element not specified\n"    if !defined $element;
    croak "subelement not specified\n" if !defined $sub_element;

    my $elts_ref = $self->{ELEMENTS};

    #  use ternary to avoid block overheads
    exists $elts_ref->{$element}
      ? delete $elts_ref->{$element}{BASE_STATS}
      : $self->add_element (
            element    => $element,
            csv_object => $csv_object,
        );

    $elts_ref->{$element}{SUBELEMENTS}{$sub_element} += ($count // 1);

    return;
}

sub rename_element {
    my $self = shift;
    my %args = @_;
    
    my $element  = $args{element};
    my $new_name = $args{new_name};

    croak "element does not exist\n"
      if !$self->exists_element (element => $element);
    croak "argument 'new_name' is undefined\n"
      if !defined $new_name;

    return if $element eq $new_name;

    my @sub_elements =
        $self->get_sub_element_list (element => $element);

    my $el_hash = $self->{ELEMENTS};
    
    my $did_something;
    #  increment the subelements
    if ($self->exists_element (element => $new_name)) {
        no autovivification;
        my $sub_el_hash_target = $el_hash->{$new_name}{SUBELEMENTS} // {};
        my $sub_el_hash_source = $el_hash->{$element}{SUBELEMENTS}  // {};
        foreach my $sub_element (keys %$sub_el_hash_source) {
            $sub_el_hash_target->{$sub_element} += $sub_el_hash_source->{$sub_element};
        }
        if (scalar keys %$sub_el_hash_source || scalar keys %$sub_el_hash_target) {
            $did_something = 1;
        }
    }
    else {
        $self->add_element (element => $new_name);
        my $el_array = $el_hash->{$new_name}{_ELEMENT_ARRAY};
        $el_hash->{$new_name} = $el_hash->{$element};
        #  reinstate the _EL_ARRAY since it will be overwritten by the previous line
        $el_hash->{$new_name}{_ELEMENT_ARRAY} = $el_array;
        #  the coord will need to be recalculated
        delete $el_hash->{$new_name}{_ELEMENT_COORD};
        $did_something = 1;
    }
    if ($did_something) {  #  don't delete if we did nothing
        delete $el_hash->{$element};
    }

    return wantarray ? @sub_elements : \@sub_elements;;
}

sub rename_subelement {
    my $self = shift;
    my %args = @_;
    
    my $element     = $args{element};
    my $sub_element = $args{sub_element};
    my $new_name    = $args{new_name};
    
    croak "element does not exist\n"
      if ! exists $self->{ELEMENTS}{$element};

    my $sub_el_hash = $self->{ELEMENTS}{$element}{SUBELEMENTS};

    croak "sub_element does not exist\n"
      if !exists $sub_el_hash->{$sub_element};

    $sub_el_hash->{$new_name} += $sub_el_hash->{$sub_element};
    delete $sub_el_hash->{$sub_element};

    return;
}

sub delete_all_elements {
    my ($self, %args) = @_;
    $self->{ELEMENTS} = ();
}

#  delete the element, return a list of fully cleansed elements
sub delete_element {  
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if ! defined $args{element};

    my $element = $args{element};

    my @deleted_sub_elements =
        $self->get_sub_element_list(element => $element);

    %{$self->{ELEMENTS}{$element}{SUBELEMENTS}} = ();
    %{$self->{ELEMENTS}{$element}} = ();
    delete $self->{ELEMENTS}{$element};

    return wantarray ? @deleted_sub_elements : \@deleted_sub_elements;
}

#  remove a sub element label or group from within
#  a group or label element.
#  Usually called when deleting a group or label element
#  in a related object.
sub delete_sub_element {  
    my $self = shift;
    my %args = (@_);

    #croak "element not specified\n" if ! defined $args{element};
    #croak "subelement not specified\n" if ! defined $args{subelement};
    my $element     = $args{element} // croak "element not specified\n";
    my $sub_element = $args{subelement} // croak "subelement not specified\n";

    return if ! exists $self->{ELEMENTS}{$element};

    my $href = $self->{ELEMENTS}{$element};

    if (exists $href->{BASE_STATS}) {
        delete $href->{BASE_STATS}{REDUNDANCY};  #  gets recalculated if needed
        delete $href->{BASE_STATS}{VARIETY};
        if (exists $href->{BASE_STATS}{SAMPLECOUNT}) {
            $href->{BASE_STATS}{SAMPLECOUNT} -= $href->{SUBELEMENTS}{$sub_element};
        }
    }
    if (exists $href->{SUBELEMENTS}) {
        delete $href->{SUBELEMENTS}{$sub_element};
    }

    #  We only need to know if there is anything left.
    #  This should also trigger some boolean optimisations on perl 5.26+
    #  https://rt.perl.org/Public/Bug/Display.html?id=78288
    !!%{$href->{SUBELEMENTS}};
}

#  array args version to avoid the args hash creation
#  (benchmarking indicates it takes a meaningful slab of time)
sub delete_sub_element_aa {
    my ($self, $element, $sub_element) = @_;
    
    croak "element not specified\n" if !defined $element;
    croak "subelement not specified\n" if !defined $sub_element;

    my $href = $self->{ELEMENTS}{$element}
     // return;

    if (exists $href->{BASE_STATS}) {
        delete $href->{BASE_STATS}{REDUNDANCY};  #  gets recalculated if needed
        delete $href->{BASE_STATS}{VARIETY};
        if (exists $href->{BASE_STATS}{SAMPLECOUNT}) {
            $href->{BASE_STATS}{SAMPLECOUNT} -= $href->{SUBELEMENTS}{$sub_element};
        }
    }
    delete $href->{SUBELEMENTS}{$sub_element};

    #  We only need to know if there is anything left.
    #  This should also trigger some boolean optimisations on perl 5.26+
    #  https://rt.perl.org/Public/Bug/Display.html?id=78288
    !!%{$href->{SUBELEMENTS}};
}

sub exists_element {
    my $self = shift;
    my %args = @_;

    my $el = $args{element}
      // croak "element not specified\n";

    #  no explicit return for speed under pre-5.20 perls
    exists $self->{ELEMENTS}{$el};
}

sub exists_element_aa {
    #my ($self, $el) = @_;

    croak "element not specified\n"
      if !defined $_[1];

    exists $_[0]->{ELEMENTS}{$_[1]};
}

sub exists_sub_element {
    my $self = shift;

    #return if ! $self->exists_element (@_);  #  no point going further if element doesn't exist

    my %args = @_;

    #defined $args{element} || croak "Argument 'element' not specified\n";
    #defined $args{subelement} || croak "Argument 'subelement' not specified\n";
    my $element = $args{element}
      // croak "Argument 'element' not specified\n";
    my $subelement = $args{subelement}
      // croak "Argument 'subelement' not specified\n";

    no autovivification;
    exists $self->{ELEMENTS}{$element}{SUBELEMENTS}{$subelement};
}

#  array args variant, with no testing of args - let perl warn as needed
sub exists_sub_element_aa {
    my ($self, $element, $subelement) = @_;

    no autovivification;
    exists $self->{ELEMENTS}{$element}{SUBELEMENTS}{$subelement};
}

sub add_values {  #  add a set of values and their keys to a list in $element
    my $self = shift;
    my %args = @_;

    my $element = $args{element}
      // croak "element not specified\n";
    delete $args{element};

    my $el_ref = $self->{ELEMENTS}{$element};
    #  we could assign it directly, but this ensures everything is uppercase
    #  {is uppercase necessary?}
    foreach my $key (keys %args) {
        $el_ref->{uc($key)} = $args{$key};
    }

    return;
}

#  increment a set of values and their keys to a list in $element
sub increment_values {
    my $self = shift;
    my %args = @_;

    my $element = $args{element}
      // croak "element not specified";
    delete $args{element};

    #  we could assign it directly, but this ensures everything is uppercase
    foreach my $key (keys %args) {  
        $self->{ELEMENTS}{$element}{uc($key)} += $args{$key};
    }

    return;
}

#  get a list from an element
#  returns a direct ref in scalar context
sub get_list_values {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element}
      // croak "element not specified\n";
    my $list = $args{list}
      // croak "List not defined\n";

    my $element_ref = $self->{ELEMENTS}{$element}
     // croak "Element $element does not exist in BaseStruct\n";

    return if ! exists $element_ref->{$list};
    return $element_ref->{$list} if ! wantarray;

    #  need to return correct type in list context
    return %{$element_ref->{$list}}
      if is_hashref($element_ref->{$list});

    return @{$element_ref->{$list}}
      if is_arrayref($element_ref->{$list});

    return;
}

sub get_hash_list_values {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};
    croak "element not specified\n" if not defined $element;

    my $list = $args{list};
    croak  "list not specified\n" if not defined $list;

    croak "element does not exist\n" if ! exists $self->{ELEMENTS}{$element};

    return if ! exists $self->{ELEMENTS}{$element}{$list};

    croak "list is not a hash\n"
        if !is_hashref($self->{ELEMENTS}{$element}{$list});

    return wantarray
        ? %{$self->{ELEMENTS}{$element}{$list}}
        : $self->{ELEMENTS}{$element}{$list};
}

#  array args version for speed
sub get_array_list_values_aa {
    my ($self, $element, $list) = @_;

    no autovivification;

    #$element // croak "Element not specified\n";
    #$list    // croak "List not specified\n";

    my $list_ref = $self->{ELEMENTS}{$element}{$list}
      // Biodiverse::BaseStruct::ListDoesNotExist->throw (
            message => "Element $element does not exist or does not have a list ref for $list\n",
        );

    #  does this need to be tested for?  Maybe caller beware is needed?
    croak "List is not an array\n"
        if !is_arrayref($list_ref);

    return wantarray ? @$list_ref : $list_ref;
}


sub get_array_list_values {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element} // croak "Element not specified\n";
    my $list    = $args{list}    // croak "List not specified\n";

    #croak "Element $element does not exist.  Do you need to rebuild the spatial index?\n"
    #  if ! exists $self->{ELEMENTS}{$element};

#if (!$self->{ELEMENTS}{$element}{$list}) {
#    print "PRIBLEMS with list $list in element $element";
#    say Data::Dumper::Dumper $self->{ELEMENTS}{$element};
#}

    my $list_ref = $self->{ELEMENTS}{$element}{$list}
      // Biodiverse::BaseStruct::ListDoesNotExist->throw (
            message => "Element $element does not exist or does not have a list ref for $list\n",
        );

    #  does this need to be tested for?  Maybe caller beware is needed?
    croak "List is not an array\n"
      if !is_arrayref($list_ref);

    return wantarray ? @$list_ref : $list_ref;
}

#  does a list exist in an element?
#  if so then return its type
sub exists_list {
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if not defined $args{element};
    croak "list not specified\n" if not defined $args{list};

    if (exists $self->{ELEMENTS}{$args{element}}{$args{list}}) {
        return ref $self->{ELEMENTS}{$args{element}}{$args{list}};
    }

    return;
}

sub add_lists {
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if not defined $args{element};

    my $element = $args{element};

    delete $args{element};
    @{$self->{ELEMENTS}{$element}}{keys %args} = values %args;

    return;
}

sub add_to_array_lists {
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};

    my $element = $args{element};

    delete $args{element};
    foreach my $key (keys %args) {
        push @{$self->{ELEMENTS}{$element}{$key}}, @{$args{$key}};
    }

    return;
}

sub add_to_hash_list {
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};

    defined $args{list} || croak "List not specified\n"; 
    my $list = $args{list};

    delete @args{qw /list element/};
    #  create it if not already there
    my $listref = $self->{ELEMENTS}{$element}{$list} //= {};

    #  now add to it - should do a slice assign
    #$self->{ELEMENTS}{$element}{$list}
    #  = {%{$self->{ELEMENTS}{$element}{$list}}, %args};
    @$listref{keys %args} = values %args;

    return;
}

sub add_to_lists {  #  add to a list, create if not already there.
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};
    delete $args{element};
    
    croak "Cannot add list to non-existent element $element"
      if !exists $self->{ELEMENTS}{$element};

    my $use_ref = $args{use_ref};  #  set a direct ref?  currently overrides any previous values so take care
    delete $args{use_ref};  #  should it be in its own sub?

    foreach my $list_name (keys %args) {
        my $list_values = $args{$list_name};
        if ($use_ref) {
            $self->{ELEMENTS}{$element}{$list_name} = $list_values;
        }
        elsif (is_hashref($list_values)) {  #  slice assign
            my $listref = ($self->{ELEMENTS}{$element}{$list_name} //= {});
            @$listref{keys %$list_values} = values %$list_values;
        }
        elsif (is_arrayref($list_values)) {
            my $listref = ($self->{ELEMENTS}{$element}{$list_name} //= []);
            push @$listref, @$list_values;
        }
        else {
            croak "no valid list ref passed to add_to_lists, %args\n";
        }
    }

    return;
}

sub delete_lists {
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if not defined $args{element};
    croak "argument 'lists' not specified\n" if not defined $args{lists};

    my $element = $args{element};
    my $lists   = $args{lists};
    croak "argument 'lists' is not an array ref\n" if !is_arrayref($lists);

    foreach my $list (@$lists) {
        delete $self->{ELEMENTS}{$element}{$list};
    }

    return;
}



sub delete_properties_for_given_element {
    my ($self, %args) = @_;
    my $el = $args{ el };

    $self->{ELEMENTS}{$el}{PROPERTIES} = {};
}


# delete an element property for all elements
sub delete_element_property {
    my ($self, %args) = @_;
    my $prop = $args{ prop };

    foreach my $el ($self->get_element_list) {
        my %props = %{$self->{ELEMENTS}{$el}{PROPERTIES}};
        delete $props{ $prop };
        $self->{ELEMENTS}{$el}{PROPERTIES} = \%props;
    }
}

sub get_lists {
    my $self = shift;
    my %args = @_;

    croak "[BaseStruct] element not specified\n"
      if not defined $args{element};
    croak "[BaseStruct] element $args{element} does not exist\n"
      if !$self->exists_element (@_);

    my $element = $args{element};

    my @list;
    foreach my $tmp (keys %{$self->{ELEMENTS}{$element}}) {
        push @list, $tmp if (is_arrayref($self->{ELEMENTS}{$element}{$tmp}) 
                            || is_hashref($self->{ELEMENTS}{$element}{$tmp}));
    }

    return @list if wantarray;
    return \@list;
}

#  should just return the stats object
sub get_list_value_stats {
    my $self = shift;
    my %args = @_;
    my $list = $args{list};
    croak "List not specified\n" if not defined $list;
    my $index = $args{index};
    croak "Index not specified\n" if not defined $index ;

    my @data;
    foreach my $element ($self->get_element_list) {
        my $list_ref = $self->get_list_ref (
            element    => $element,
            list       => $list,
            autovivify => 0,
        );
        next if ! defined $list_ref;
        next if ! exists  $list_ref->{$index};
        next if ! defined $list_ref->{$index};  #  skip undef values

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

    if (scalar @data) {  #  don't bother if they are all undef
        my $stats = $stats_class->new;
        $stats->add_data (\@data);

        %stats_hash = (
            MAX    => $stats->max,
            MIN    => $stats->min,
            MEAN   => $stats->mean,
            SD     => $stats->standard_deviation,
            PCT025 => scalar $stats->percentile (2.5),
            PCT975 => scalar $stats->percentile (97.5),
            PCT05  => scalar $stats->percentile (5),
            PCT95  => scalar $stats->percentile (95),
        );
    }

    return wantarray ? %stats_hash : \%stats_hash;
}

sub clear_lists_across_elements_cache {
    my $self = shift;
    my $keys = $self->get_cached_value_keys;
    my @keys_to_delete = grep {$_ =~ /^LISTS_ACROSS_ELEMENTS/} @$keys;
    $self->delete_cached_values (keys => \@keys_to_delete);
    return;
}

sub get_array_lists_across_elements {
    my $self = shift;
    return $self->get_lists_across_elements (@_, list_method => 'get_array_lists');
}

sub get_hash_lists_across_elements {
    my $self = shift;
    return $self->get_lists_across_elements (@_, list_method => 'get_hash_lists');
}


#  get a list of all the lists in all the elements
#  up to $args{max_search}
sub get_lists_across_elements {
    my $self = shift;
    my %args = @_;
    my $max_search = $args{max_search} || $self->get_element_count;
    my $no_private = $args{no_private} // 0;
    my $rerun = $args{rerun};
    my $list_method = $args{list_method} || 'get_hash_lists';

    croak "max_search arg is negative\n" if $max_search < 0;

    #  get from cache
    my $cache_name_listnames   = "LISTS_ACROSS_ELEMENTS_${list_method}_${no_private}";
    my $cache_name_max_search  = "LISTS_ACROSS_ELEMENTS_MAX_SEARCH_${list_method}_${no_private}";
    my $cache_name_last_update = "LISTS_ACROSS_ELEMENTS_LAST_UPDATE_TIME_${list_method}_${no_private}";

    my $last_cache_time
        = $self->get_cached_value ($cache_name_last_update)
          || time;

    #  we were caching the wrong order, so reset if need be 
    if ($last_cache_time < 1472007422) {
        $self->delete_cached_values (
            keys => [$cache_name_last_update, $cache_name_last_update],
        );
    }

    my $cached_list = $self->get_cached_value ($cache_name_listnames);
    my $cached_list_max_search
        = $self->get_cached_value ($cache_name_max_search);

    my $last_update_time = $self->get_last_update_time;

    if (!defined $last_update_time) {  #  store for next time
        $self->set_last_update_time (time - 10); # ensure older given time precision
    }

    my $time_diff = defined $last_update_time
                    ? $last_cache_time - $last_update_time
                    : -1;

    if (1 
        && defined $cached_list                     #  return cache
        && ! $rerun
        && defined $cached_list_max_search          #  if it exists and
        && $time_diff > 0                           #  was updated after $self
        && $cached_list_max_search >= $max_search   #  the max search was
        ) {                                         #  the same or bigger

        #print "[BASESTRUCT] Using cached list items\n";
        return (wantarray ? @$cached_list : $cached_list);   
    }

    my $elements = $self->get_element_hash;

    my %tmp_hash;
    my $count = 0;

    SEARCH_FOR_LISTS:
    foreach my $elt (keys %$elements) {

        my $list = $self->$list_method (element => $elt);
        if (scalar @$list) {
            @tmp_hash{@$list} = undef;  #  we only care about the keys
        }
        $count++;
        last SEARCH_FOR_LISTS if $count > $max_search;
    }

    #  remove private lists if needed - should just use a grep
    if ($no_private) {
        foreach my $key (keys %tmp_hash) {
            if ($key =~ /^_/) {  #  not those starting with an underscore
                delete $tmp_hash{$key};
            }
        }
    }
    my @lists = keys %tmp_hash;

    #  cache
    $self->set_cached_values (
        $cache_name_listnames   => \@lists,
        $cache_name_max_search  => $max_search,
        $cache_name_last_update => $last_cache_time,
    );

    return wantarray ? @lists : \@lists;
}

sub get_hash_list_names_across_elements {
    my $self = shift;
    my %args = @_;

    my $no_private = $args{no_private};
    
    my $ref_types = $self->get_list_names_across_elements (%args);

    my @hash_lists;
    foreach my $key (keys %$ref_types) {
        next if $no_private && $key =~ /^_/;
        next if not $ref_types->{$key} =~ /HASH/;
        push @hash_lists, $key; 
    }

    return wantarray ? @hash_lists : \@hash_lists;
}

#  profiling shows get_hash_lists_across_elements is slow
#  as it checks the ref type of all lists, when they should
#  be constant across a basestruct.
#  see how we go with this approach (currently sans caching)
sub get_list_names_across_elements {
    my $self = shift;
    my %args = @_;

    no autovivification;

    #  turn off caching for now - we need to update it when we analyse the data
    #my $cache_name   = 'LIST_NAMES_AND_TYPES_ACROSS_ELEMENTS';
    #my $cached_lists = $self->get_cached_value ($cache_name);
    #
    #return wantarray ? %$cached_lists : $cached_lists
    #  if $cached_lists && !($args{no_cache} || $args{rebuild_cache});
    
    my %list_reftypes;
    my $elements_hash = $self->{ELEMENTS};

  SEARCH_FOR_LISTS:
    foreach my $elt (keys %$elements_hash) {
        my $elt_ref = $elements_hash->{$elt};

        #  dirty hack - we probably should not be looking inside these
        foreach my $list_name (keys %{$elt_ref}) {
            next if $list_reftypes{$list_name};
            next if !defined $elt_ref->{$list_name};
            $list_reftypes{$list_name}
              = reftype ($elt_ref->{$list_name}) // 'NOT A REF';
        }
    }

    #if (!$args{no_cache}) {
    #    $self->set_cached_value ($cache_name => \%list_reftypes);
    #}

    return wantarray ? %list_reftypes : \%list_reftypes;
}

#  get a list of hash lists with numeric values in them
#  ignores undef values
sub get_numeric_hash_lists {  
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};

    my %lists;
    LIST:
    foreach my $list ($self->get_hash_lists (element => $element)) {
        $lists{$list} = 1;
        foreach my $value (values %{$self->get_list_values(element => $element, list => $list)}) {
            next if ! defined $value ;
            if (! looks_like_number ($value)) {
                $lists{$list} = 0;
                next LIST;
            }
        }
    }

    return wantarray ? %lists : \%lists;
}

sub get_array_lists {
    my $self = shift;
    my %args = @_;

    my $element = $args{element}
      // croak "Element not specified, get_array_lists\n";

    no autovivification;

    my $el_ref = $self->{ELEMENTS}{$element}
      // croak "Element $element does not exist, cannot get hash list\n";

    my @list = grep {is_arrayref($el_ref->{$_})} keys %$el_ref;

    return wantarray ? @list : \@list;
}

sub get_hash_lists {
    my $self = shift;
    my %args = @_;

    my $element = $args{element}
      // croak "Element not specified, get_hash_lists\n";

    no autovivification;

    my $el_ref = $self->{ELEMENTS}{$element}
      // croak "Element $element does not exist, cannot get hash list\n";

    my @list = grep {is_hashref ($el_ref->{$_})} keys %$el_ref;

    return wantarray ? @list : \@list;
}

sub get_hash_list_keys_across_elements {
    my $self = shift;
    my %args = @_;

    my $list_name = $args{list};

    my $elements = $self->get_element_hash() || {};

    my %hash_keys;

    ELEMENT:
    foreach my $elt (keys %$elements) {
        my $hash = $self->get_list_ref (
            element    => $elt,
            list       => $list_name,
            autovivify => 0,
        );
        next ELEMENT if ! $hash;
        next ELEMENT if ! (is_hashref($hash));

        if (scalar keys %$hash) {
            @hash_keys{keys %$hash} = undef; #  no need for values and assigning undef is faster
        }
    }
    my @sorted_keys = sort keys %hash_keys;
    
    return wantarray ? @sorted_keys : [@sorted_keys];
}

#  return a reference to the specified list
#  - allows for direct operation on its values
sub get_list_ref {
    my $self = shift;
    my %args = (
        autovivify => 1,
        @_,
    );

    my $list    = $args{list}
      // croak "Argument 'list' not defined\n";
    my $element = $args{element}
      // croak "Argument 'element' not defined\n";

    #croak "Element $args{element} does not exist\n"
    #  if ! $self->exists_element (element => $element);

    no autovivification;

    my $el = $self->{ELEMENTS}{$element}
      // croak "Element $args{element} does not exist\n";

    if (! exists $el->{$list}) {
        return if ! $args{autovivify};  #  should croak?
        $el->{$list} = {};  #  should we default to a hash?
    }
    return $el->{$list};
}

sub rename_list {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $list = $args{list};
    my $new_name = $args{new_name};
    my $element  = $args{element};
    
    my $el = $self->{ELEMENTS}{$element}
      // croak "Element $args{element} does not exist\n";

    #croak "element $element does not contain a list called $list"
    return if !exists $el->{$list};

    $el->{$new_name} = $el->{$list};
    delete $el->{$list};

    return;
}

sub get_sample_count {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element}
      // croak "element not specified\n";

    my $href = $self->{ELEMENTS}{$element}{SUBELEMENTS}
      // return;  #  should croak? 

    my $count = sum (0, values %$href);

    return $count;
}

sub get_variety {
    my ($self, %args) = @_;

    no autovivification;

    my $element = $args{element} //
      croak "element not specified\n";

    my $href = $self->{ELEMENTS}{$element}{SUBELEMENTS}
      // return;  #  should croak? 

    #  no explicit return - minor speedup prior to perl 5.20
    scalar keys %$href;
}

sub get_variety_aa {
    no autovivification;

    my $href = $_[0]->{ELEMENTS}{$_[1]}{SUBELEMENTS}
      // return;  #  should croak? 

    #  no explicit return - minor speedup prior to perl 5.20
    scalar keys %$href;
}

sub get_redundancy {
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};

    return if ! $self->exists_element (element => $args{element});

    my $redundancy = eval {
        1 - $self->get_variety (element => $element)
          / $self->get_sample_count (element => $element)
    };

    return $redundancy;
}

#  calculate basestats for all elements - poss redundant now there are indices that do this
sub get_base_stats_all {
    my $self = shift;

    foreach my $element ($self->get_element_list) {
        $self->add_lists (
            element    => $element,
            BASE_STATS => $self->calc_base_stats(element => $element)
        );
    }

    return;
}

sub binarise_subelement_sample_counts {
    my $self = shift;

    foreach my $element ($self->get_element_list) {
        my $list_ref = $self->get_list_ref (element => $element, list => 'SUBELEMENTS');
        foreach my $val (values %$list_ref) {
            $val = 1;
        }
        $self->delete_lists(element => $element, lists => ['BASE_STATS']);
    }

    $self->delete_cached_values;

    return;
}

#  are the sample counts floats or ints?
#  Could use Scalar::Util::Numeric::isfloat here if speed becomes an issue
sub sample_counts_are_floats {
    my $self = shift;

    my $cached_val = $self->get_cached_value('SAMPLE_COUNTS_ARE_FLOATS');
    return $cached_val if defined $cached_val;
    
    foreach my $element ($self->get_element_list) {
        my $count = $self->get_sample_count (element => $element);

        next if !(fmod ($count, 1));

        $cached_val = 1;
        $self->set_cached_value(SAMPLE_COUNTS_ARE_FLOATS => 1);

        return $cached_val;
    }

    $self->set_cached_value(SAMPLE_COUNTS_ARE_FLOATS => 0);

    return $cached_val;
}


sub get_metadata_get_base_stats {
    my $self = shift;

    #  types are for GUI's benefit - should really add a guessing routine instead
    my $sample_type = eval {$self->sample_counts_are_floats} 
        ? 'Double'
        : 'Uint';

    my $types = [
        {VARIETY    => 'Int'},
        {SAMPLES    => $sample_type},
        {REDUNDANCY => 'Double'},
    ];

    my $property_keys = $self->get_element_property_keys;
    foreach my $property (sort @$property_keys) {
        push @$types, {$property => 'Double'};
    }

    return $self->metadata_class->new({types => $types});
}

sub get_base_stats {  #  calculate basestats for a single element
    my $self = shift;
    my %args = @_;

    defined $args{element} || croak "element not specified\n";

    my $element = $args{element};

    my %stats = (
        VARIETY    => $self->get_variety      (element => $element),
        SAMPLES    => $self->get_sample_count (element => $element),
        REDUNDANCY => $self->get_redundancy   (element => $element),
    );

    #  get all the user defined properties
    my $props = $self->get_list_ref (
        element    => $element,
        list       => 'PROPERTIES',
        autovivify => 0,
    );

    PROP:
    foreach my $prop (keys %$props) {
        $stats{$prop} = $props->{$prop};
    }

    return wantarray ? %stats : \%stats;
}

sub get_element_property_keys {
    my $self = shift;

    my $keys = $self->get_cached_value ('ELEMENT_PROPERTY_KEYS');

    return wantarray ? @$keys : $keys if $keys;

    my @keys = $self->get_hash_list_keys_across_elements (list => 'PROPERTIES');

    $self->set_cached_value ('ELEMENT_PROPERTY_KEYS' => \@keys);

    return wantarray ? @keys : \@keys;
}

# returns a hash mapping from elements to element property hashes.
sub get_all_element_properties {
    my ($self, %args) = @_;
    my %element_to_props_hash;
    
    foreach my $element ($self->get_element_list) {
        my $props_hash = $self->get_element_properties(element => $element);
        $element_to_props_hash{ $element } = $props_hash;
    }

    return wantarray ? %element_to_props_hash : \%element_to_props_hash;
}

sub get_element_properties {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};
    croak "element argument not given\n" if ! defined $element;

    my $props = $self->get_list_ref (
        element    => $element,
        list       => 'PROPERTIES',
        autovivify => 0,
    )
    || {};  # or a blank hash

    my %p = %$props;  #  make a copy;
    delete @p{qw /INCLUDE EXCLUDE/};  #  don't want these

    return wantarray ? %p : \%p;
}

sub get_element_properties_summary_stats {
    my $self = shift;
    my %args = @_;

    my $bd = $self->get_basedata_ref;
    if (Biodiverse::MissingBasedataRef->caught) {
        $bd = undef;
    }

    my $range_weighted = defined $bd ? $args{range_weighted} : undef;

    my %results;

    my %stats_data;
    foreach my $prop_name ($self->get_element_property_keys) {
        $stats_data{$prop_name} = [];
    }

    foreach my $element ($self->get_element_list) {    
        my %p = $self->get_element_properties(element => $element);
        while (my ($prop, $data) = each %stats_data) {
            next if ! defined $p{$prop};
            my $weight = $range_weighted ? $bd->get_range (element => $element) : 1;
            push @$data, ($p{$prop}) x $weight;
        }
    }

    while (my ($prop, $data) = each %stats_data) {
        next if not scalar @$data;

        my $stats_object = $stats_class->new;
        $stats_object->add_data($data);
        foreach my $stat (qw /mean sum standard_deviation count/) { 
            $results{$prop}{$stat} = $stats_object->$stat;
        }
    }

    return wantarray ? %results : \%results;
}

sub has_element_properties {
    my $self = shift;
    
    my @keys = $self->get_element_property_keys;
    
    return scalar @keys;
}

#  return true if the labels are all numeric
sub elements_are_numeric {
    my $self = shift;
    foreach my $element ($self->get_element_list) {
        return 0 if ! looks_like_number($element);
    }
    return 1;  # if we get this far then they must all be numbers
}

#  like elements_are_numeric, but checks each axis
#  this is all or nothing
sub element_arrays_are_numeric {
    my $self = shift;
    foreach my $element ($self->get_element_list) {
        my $array = $self->get_element_name_as_array (element => $element);
        foreach my $iter (@$array) {
            return 0 if ! looks_like_number($iter);
        }
    }
    return 1;  # if we get this far then they must all be numbers
}


sub DESTROY {
    my $self = shift;
    #my $name = $self->get_param ('NAME');
    #print "DESTROYING BASESTRUCT $name\n";
    #undef $name;
    my $success = $self->set_param (BASEDATA_REF => undef);

    #$self->_delete_params_all;

    foreach my $key (sort keys %$self) {  #  clear all the top level stuff
        #print "Deleting BS $key\n";
        #$self->{$key} = undef;
        delete $self->{$key};
    }
    undef %$self;

    #  let perl handle the rest
    return;
}

1;

__END__

=head1 NAME

Biodiverse::BaseStruct

=head1 SYNOPSIS

  use Biodiverse::BaseStruct;
  $object = Biodiverse::BaseStruct->new();

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

