package Biodiverse::BaseData::ManageOutputs;

use strict;
use warnings;
use 5.022;

our $VERSION = '4.99_007';

use Carp;
use Scalar::Util qw /looks_like_number blessed reftype/;
use English qw /-no_match_vars/;
use Ref::Util qw { :all };
use Sort::Key::Natural qw /natkeysort/;


our $EMPTY_STRING = q{};

sub rename_output {
    my $self = shift;
    my %args = @_;

    my $object = $args{output};
    croak 'Argument "output" not defined'
      if !defined $object;

    my $new_name = $args{new_name};
    my $name     = $object->get_name;

    my $class = ( blessed $object) // $EMPTY_STRING;

    my $o_type =
        $class =~ /Spatial/                   ? 'SPATIAL_OUTPUTS'
      : $class =~ /Cluster|RegionGrower|Tree/ ? 'CLUSTER_OUTPUTS'
      : $class =~ /Matrix/                    ? 'MATRIX_OUTPUTS'
      : $class =~ /Randomise/                 ? 'RANDOMISATION_OUTPUTS'
      :                                         undef;

    croak "[BASEDATA] Cannot rename this type of output: $class\n"
      if !$o_type;

    my $hash_ref = $self->{$o_type};

    my $type = $class;
    $type =~ s/.*://;
    say "[BASEDATA] Renaming output $name to $new_name, type is $type";

    # only if it exists in this basedata
    if ( exists $hash_ref->{$name} ) {

        croak "Cannot rename $type output $name to $new_name.  "
            . "Name is already in use\n"
          if exists $hash_ref->{$new_name};

        $hash_ref->{$new_name} = $object;
        $hash_ref->{$name}     = undef;
        delete $hash_ref->{$name};

        $object->rename( new_name => $new_name );
    }
    else {
        warn "[BASEDATA] Cannot locate object with name $name\n"
          . 'Currently have '
          . join( ' ', sort keys %$hash_ref ) . "\n";
    }

    $object = undef;
    return;
}

#  deletion of randomisations is more complex than spatial and cluster outputs
sub do_rename_randomisation_lists {
    my $self = shift;
    my %args = @_;

    my $object   = $args{output};
    my $name     = $object->get_name;
    my $new_name = $args{new_name};

    croak "Argument new_name not defined\n"
      if !defined $new_name;

    #  loop over the spatial outputs and rename the lists
  BY_SPATIAL_OUTPUT:
    foreach my $sp_output ( $self->get_spatial_output_refs ) {
        my @lists =
          grep { $_ =~ /^$name>>/ } $sp_output->get_lists_across_elements;

        foreach my $list (@lists) {
            my $new_list_name = $list;
            $new_list_name =~ s/^$name>>/$new_name>>/;
            foreach my $element ( $sp_output->get_element_list ) {
                $sp_output->rename_list(
                    list     => $list,
                    element  => $element,
                    new_name => $new_list_name,
                );
            }
        }
        $sp_output->delete_cached_values;
    }

    #  and now the cluster outputs
    my @node_lists = ( $name, $name . '_ID_LDIFFS', $name . '_DATA', );

  BY_CLUSTER_OUTPUT:
    foreach my $cl_output ( $self->get_cluster_output_refs ) {
        my @lists = grep { $_ =~ /^$name>>/ } $cl_output->get_list_names_below;
        my @lists_to_rename = ( @node_lists, @lists );

        foreach my $list (@lists_to_rename) {
            my $new_list_name = $list;
            $new_list_name =~ s/^$name/$new_name/;

            foreach my $node_ref ( $cl_output->get_node_refs ) {
                $node_ref->rename_list(
                    list     => $list,
                    new_name => $new_list_name,
                );
            }
        }
        $cl_output->delete_cached_values;
    }

    return;
}

sub delete_output {
    my $self = shift;
    my %args = @_;

    my $object = $args{output};
    my $name   = $object->get_param('NAME');

    my $class = blessed($object) || $EMPTY_STRING;
    my $type = $class;
    $type =~ s/.*://;    #  get the last part
    print "[BASEDATA] Deleting $type output $name\n";

    if ( $type =~ /Spatial/ ) {
        $self->{SPATIAL_OUTPUTS}{$name} = undef;
        delete $self->{SPATIAL_OUTPUTS}{$name};
    }
    elsif ( $type =~ /Cluster|Tree|RegionGrower/ ) {
        my $x = eval { $object->delete_all_cached_values };
        $self->{CLUSTER_OUTPUTS}{$name} = undef;
        delete $self->{CLUSTER_OUTPUTS}{$name};
    }
    elsif ( $type =~ /Matrix/ ) {
        $self->{MATRIX_OUTPUTS}{$name} = undef;
        delete $self->{MATRIX_OUTPUTS}{$name};
    }
    elsif ( $type =~ /Randomise/ ) {
        $self->do_delete_randomisation_lists(@_);
    }
    else {
        croak "[BASEDATA] Cannot delete this type of output: $class\n";
    }

    if ( $args{delete_basedata_ref} // 1 ) {
        $object->set_param( BASEDATA_REF => undef );    #  free its parent ref
    }
    $object = undef;                                    #  clear it

    return;
}

#  deletion of these is more complex than spatial and cluster outputs
sub do_delete_randomisation_lists {
    my $self = shift;
    my %args = @_;

    my $object = $args{output};
    my $name   = $object->get_name;

    say "[BASEDATA] Deleting randomisation output $name";

    #  loop over the spatial outputs and clear the lists
  BY_SPATIAL_OUTPUT:
    foreach my $sp_output ( $self->get_spatial_output_refs ) {
        my @lists =
          grep { $_ =~ /^$name>>/ } $sp_output->get_lists_across_elements;
        unshift @lists, $name;    #  for backwards compatibility

      BY_ELEMENT:
        foreach my $element ( $sp_output->get_element_list ) {
            $sp_output->delete_lists(
                lists   => \@lists,
                element => $element
            );
        }
    }

    #  and now the cluster outputs
    my @node_lists = (
        $name,
        $name . '_SPATIAL',    #  for backwards compat
        $name . '_ID_LDIFFS',
        $name . '_DATA',
    );

  BY_CLUSTER_OUTPUT:
    foreach my $cl_output ( $self->get_cluster_output_refs ) {
        my @lists = grep { $_ =~ /^$name>>/ } $cl_output->get_list_names_below;
        my @lists_to_delete = ( @node_lists, @lists );
        $cl_output->delete_lists_below( lists => \@lists_to_delete );
    }

    $self->{RANDOMISATION_OUTPUTS}{$name} = undef;
    delete $self->{RANDOMISATION_OUTPUTS}{$name};

    $object->set_param( BASEDATA_REF => undef );    #  free its parent ref

    return;
}

#  generic handler for adding outputs.
#  could eventually replace the specific forms
sub add_output {
    my $self = shift;
    my %args = @_;

    my $object =
         $args{object}
      || $args{type}
      || croak "[BASEDATA] No valid object or type arg specified, add_output\n";

    my $class = blessed($object) || $object;
    if ( $class =~ /spatial/i ) {
        return $self->add_spatial_output(@_);
    }
    elsif ( $class =~ /Cluster|RegionGrower/i ) {
        return $self->add_cluster_output(@_);
    }
    elsif ( $class =~ /randomisation/i ) {
        return $self->add_randomisation_output(@_);
    }
    elsif ( $class =~ /matrix/i ) {
        return $self->add_matrix_output(@_);
    }

    #  if we get this far then we have problems
    croak "[BASEDATA] No valid object or type arg specified, add_output\n";
}

#  get refs to the spatial and cluster objects
sub get_output_refs {
    my $self = shift;

    my @refs = (
        $self->get_spatial_output_refs,       $self->get_cluster_output_refs,
        $self->get_randomisation_output_refs, $self->get_matrix_output_refs,
    );

    return wantarray ? @refs : \@refs;
}

sub get_output_ref_count {
    my $self = shift;

    my $refs = $self->get_output_refs;

    return scalar @$refs;
}

sub get_output_refs_sorted_by_name {
    my $self = shift;

    my @sorted = natkeysort { $_->get_param('NAME') }
      $self->get_output_refs;

    return wantarray ? @sorted : \@sorted;
}

sub get_output_refs_of_class {
    my $self = shift;
    my %args = @_;

    my $class = blessed $args{class} // $args{class}
      or croak "argument class not specified\n";

    my @outputs;
    foreach my $ref ( $self->get_output_refs ) {
        next if !( blessed($ref) eq $class );
        push @outputs, $ref;
    }

    return wantarray ? @outputs : \@outputs;
}

sub delete_all_outputs {
    my $self = shift;

    foreach my $output ( $self->get_output_refs ) {
        $self->delete_output( output => $output );
    }

    return;
}

########################################################
#  methods to set, create and select the cluster outputs

sub add_cluster_output {
    my $self = shift;
    my %args = @_;

    my $object = delete $args{object};    

    my $class = $args{type} || 'Biodiverse::Cluster';
    my $name = $object ? $object->get_param('NAME') : $args{name};
    delete $args{name};

    croak "[BASEDATA] argument 'name' not specified\n"
      if !defined $name;

    croak "Cannot run a cluster type analysis with only a single group\n"
      if $self->get_group_count == 1;

    croak "[BASEDATA] Cannot replace existing cluster "
        . "object $name. Use a different name.\n"
      if exists $self->{CLUSTER_OUTPUTS}{$name};

    #  add an existing output
    #  Check if it is the correct type, warn if not
    #  - caveat emptor if wrong type
    #  The check is a bit underhanded, as it does
    #  not allow abstraction - something to clean up later
    #  if needed
    if ($object) {
        my $obj_class = blessed($object);
        carp "[BASEDATA] Object is not of valid type ($class)"
          if not $class =~ /cluster|regiongrower/i;

        $object->set_param( BASEDATA_REF => $self );
        $object->weaken_basedata_ref;
    }
    else {    #  create a new object
        $object = $class->new(
            QUOTES    => $self->get_param('QUOTES'),
            JOIN_CHAR => $self->get_param('JOIN_CHAR'),
            %args,
            NAME => $name,         #  these two always override 
            BASEDATA_REF => $self, #  user args (NAME can be an arg)
        );
    }

    $self->{CLUSTER_OUTPUTS}{$name} = $object;

    return $object;
}

sub delete_cluster_output {
    my $self = shift;
    my %args = @_;
    croak "parameter 'name' not specified\n"
      if !defined $args{name};

    $self->delete_output(
        output => $self->{CLUSTER_OUTPUTS}{ $args{name} },
    );

    return;
}

#  return the reference for a specified output
sub get_cluster_output_ref {
    my $self = shift;
    my %args = @_;

    return if !exists $self->{CLUSTER_OUTPUTS}{ $args{name} };

    return $self->{CLUSTER_OUTPUTS}{ $args{name} };
}

sub get_cluster_output_refs {
    my $self = shift;
    return values %{ $self->{CLUSTER_OUTPUTS} } if wantarray;
    return [ values %{ $self->{CLUSTER_OUTPUTS} } ];
}

sub get_cluster_output_names {
    my $self = shift;
    return keys %{ $self->{CLUSTER_OUTPUTS} } if wantarray;
    return [ keys %{ $self->{CLUSTER_OUTPUTS} } ];
}

sub get_cluster_outputs {
    my $self = shift;
    return %{ $self->{CLUSTER_OUTPUTS} } if wantarray;
    return { %{ $self->{CLUSTER_OUTPUTS} } };
}

#  delete any cached values from the trees, eg _cluster_colour
#  allow more specific deletions by passing on the args
sub delete_cluster_output_cached_values {
    my $self = shift;
    print "[BASEDATA] Deleting cached values in cluster trees\n";
    foreach my $cluster ( $self->get_cluster_output_refs ) {
        $cluster->delete_all_cached_values(@_);
    }

    return;
}

########################################################
#  methods to set, create and select the current spatial object

sub add_spatial_output {
    my $self = shift;
    my %args = @_;

    croak "[BASEDATA] argument 'name' not specified\n"
      if !defined $args{name};

    my $class = 'Biodiverse::Spatial';
    my $name  = delete $args{name};

    croak  "[BASEDATA] Cannot replace existing spatial"
         . " object $name.  Use a different name.\n"
      if defined $self->{SPATIAL_OUTPUTS}{$name};

    my $object = delete $args{object};

    #  we add an existing output if one is passed
    if ($object) {

        #  check if it is the correct type, warn if not
        #  - caveat emptor if wrong type
        #  check is a bit underhanded, as it does not
        #  allow abstraction - clean up later if needed
        my $obj_class = blessed($object);
        carp "[BASEDATA] Object is not of type $class"
          if $class ne $obj_class;

        $object->set_param( BASEDATA_REF => $self );
    }
    else {    #  create a new object
        $object = $class->new(
            QUOTES    => $self->get_param('QUOTES'),
            JOIN_CHAR => $self->get_param('JOIN_CHAR'),
            %args,
            NAME => $name,         #  these two always override 
            BASEDATA_REF => $self, #  user args (NAME can be an arg)
        );
    }
    $object->weaken_basedata_ref;

    #  add or replace (take care with the replace)
    $self->{SPATIAL_OUTPUTS}{$name} =  $object; 

    return $object;
}

#  return the reference for a specified output
sub get_spatial_output_ref {
    my $self = shift;
    my %args = @_;

    my $name = $args{name};

    croak "Spatial output $name does not exist in the basedata\n"
      if !exists $self->{SPATIAL_OUTPUTS}{$name};

    return $self->{SPATIAL_OUTPUTS}{$name};
}

sub get_spatial_output_list {
    my $self = shift;

    my @result = sort keys %{ $self->{SPATIAL_OUTPUTS} };
    return wantarray ? @result : \@result;
}

sub delete_spatial_output {
    my $self = shift;
    my %args = @_;

    croak "parameter name not specified\n" if !defined $args{name};

    $self->delete_output(
        output => $self->{SPATIAL_OUTPUTS}{ $args{name} }
    );

    return;
}

sub get_spatial_output_refs {
    my $self = shift;
    return wantarray
      ? values %{ $self->{SPATIAL_OUTPUTS} }
      : [ values %{ $self->{SPATIAL_OUTPUTS} } ];
}

sub get_spatial_output_names {
    my $self = shift;
    return wantarray
      ? keys %{ $self->{SPATIAL_OUTPUTS} }
      : [ keys %{ $self->{SPATIAL_OUTPUTS} } ];
}

sub get_spatial_outputs {
    my $self = shift;
    return wantarray
      ? %{ $self->{SPATIAL_OUTPUTS} }
      : { %{ $self->{SPATIAL_OUTPUTS} } };
}

########################################################
#  methods to set, create and select the current matrix output object

sub add_matrix_output {
    my $self = shift;
    my %args = @_;

    my $class = 'Biodiverse::Matrix';

    my $object = delete $args{object};
    
    my $name;


    if ($object) {
        #  Add an existing output, but check if
        #  it is the correct type, warn if not
        #  - caveat emptor if wrong type
        #  Check is a bit underhanded, as it does not
        #  allow abstraction - clean up later if needed
        my $obj_class = blessed($object);
        carp "[BASEDATA] Object is not of type $class"
          if not $class =~ /^$class/;

        $name = $object->get_param('NAME');

        croak "[BASEDATA] Cannot replace existing matrix "
            . "object $name.  Use a different name.\n"
          if defined $self->{MATRIX_OUTPUTS}{$name};

        $object->set_param( BASEDATA_REF => $self );
        $object->weaken_basedata_ref;
    }
    else {    #  create a new object
        croak 'Creation of matrix new objects is not supported - '
          . "they are added by the clustering system\n";
    }

    #  add or replace (take care with the replace)
    $self->{MATRIX_OUTPUTS}{$name} = $object;

    return $object;
}

#  return the reference for a specified output
sub get_matrix_output_ref {
    my $self = shift;
    my %args = @_;

    return if !exists $self->{MATRIX_OUTPUTS}{ $args{name} };

    return $self->{MATRIX_OUTPUTS}{ $args{name} };
}

sub get_matrix_output_list {
    my $self   = shift;
    my @result = sort keys %{ $self->{MATRIX_OUTPUTS} };
    return wantarray ? @result : \@result;
}

sub delete_matrix_output {
    my $self = shift;
    my %args = @_;

    croak "parameter name not specified\n" if !defined $args{name};

    $self->delete_output( output => $self->{MATRIX_OUTPUTS}{ $args{name} } );

    return;
}

sub get_matrix_output_refs {
    my $self = shift;
    $self->_set_matrix_ouputs_hash;
    return wantarray
      ? values %{ $self->{MATRIX_OUTPUTS} }
      : [ values %{ $self->{MATRIX_OUTPUTS} } ];
}

sub get_matrix_output_names {
    my $self = shift;
    $self->_set_matrix_ouputs_hash;
    return wantarray
      ? keys %{ $self->{MATRIX_OUTPUTS} }
      : [ keys %{ $self->{MATRIX_OUTPUTS} } ];
}

sub get_matrix_outputs {
    my $self = shift;
    $self->_set_matrix_ouputs_hash;
    return wantarray
      ? %{ $self->{MATRIX_OUTPUTS} }
      : { %{ $self->{MATRIX_OUTPUTS} } };
}

sub _set_matrix_ouputs_hash {
    my $self = shift;
    if ( !$self->{MATRIX_OUTPUTS} ) {
        $self->{MATRIX_OUTPUTS} = {};
    }
}

########################################################
#  methods to set, create and select randomisation objects

sub add_randomisation_output {
    my $self = shift;
    my %args = @_;
    if ( !defined $args{name} ) {
        croak "[BASEDATA] argument name not specified\n";

        #return undef;
    }
    my $class = 'Biodiverse::Randomise';

    my $name = delete $args{name};

    croak "[BASEDATA] Cannot replace existing randomisation"
        . "object $name.  Use a different name.\n"
      if exists $self->{RANDOMISATION_OUTPUTS}{$name};

    my $object = delete $args{object};

    if ($object) {
        #  add an existing output
        #  check if it is the correct type, warn
        #  if not - caveat emptor if wrong type
        #  check is a bit underhanded, as it
        #  does not allow abstraction - clean
        #  up later if needed
        my $obj_class = blessed($object);

        carp "[BASEDATA] Object is not of type $class"
          if $class ne $obj_class;

        $object->set_param( BASEDATA_REF => $self );
        $object->weaken_basedata_ref;
    }
    else {    #  create a new object
        $object = eval {
            $class->new(
                %args,
                NAME => $name,         #  these two always override user
                BASEDATA_REF => $self, #  args (NAME can be an arg)
            );
        };
        croak $EVAL_ERROR if $EVAL_ERROR;
    }

    $self->{RANDOMISATION_OUTPUTS}{$name} = $object;
    undef $object;
    return $self->{RANDOMISATION_OUTPUTS}{$name};

    #  fiddling to avoid SV leaks, possibly pointless
    #my $object2 = $object;
    #undef $object;
    #return $object2;
}

sub get_randomisation_output_ref
{    #  return the reference for a specified output
    my $self = shift;
    my %args = @_;
    return $self->{RANDOMISATION_OUTPUTS}{ $args{name} };
}

sub get_randomisation_output_list {
    my $self = shift;
    my @list = sort keys %{ $self->{RANDOMISATION_OUTPUTS} };
    return wantarray ? @list : \@list;
}

sub delete_randomisation_output {
    my $self = shift;
    my %args = @_;
    croak "parameter name not specified\n" if !defined $args{name};

    $self->delete_output(
        output => $self->{RANDOMISATION_OUTPUTS}{ $args{name} }
    );

    return;
}

sub get_randomisation_output_refs {
    my $self = shift;
    return values %{ $self->{RANDOMISATION_OUTPUTS} } if wantarray;
    return [ values %{ $self->{RANDOMISATION_OUTPUTS} } ];
}

sub get_randomisation_output_names {
    my $self = shift;
    return keys %{ $self->{RANDOMISATION_OUTPUTS} } if wantarray;
    return [ keys %{ $self->{RANDOMISATION_OUTPUTS} } ];
}

sub get_randomisation_outputs {
    my $self = shift;
    return %{ $self->{RANDOMISATION_OUTPUTS} } if wantarray;
    return { %{ $self->{RANDOMISATION_OUTPUTS} } };
}

sub get_unique_randomisation_name {
    my $self = shift;

    my @names  = $self->get_randomisation_output_names;
    my $prefix = 'Rand';

    my $max = 0;
    foreach my $name (@names) {
        if ( $name =~ /^$prefix(\d+)$/ ) {
            my $num = $1;
            $max = $num if $num > $max;
        }
    }

    my $unique_name = $prefix . ( $max + 1 );

    return $unique_name;
}


1;

