#  all the clustering stuff over the top of a Biodiverse::Tree object

package Biodiverse::Cluster;

use Carp;
use strict;
use warnings;
use English ( -no_match_vars );

use Data::Dumper;
use Devel::Symdump;
use Scalar::Util qw/blessed/;
use Time::HiRes qw /gettimeofday tv_interval/;
use List::Util;
#use Math::Random::MT::Auto qw /rand shuffle get_state/;

our $VERSION = '0.16';

#use Biodiverse::Common;
use Biodiverse::Matrix;
use Biodiverse::TreeNode;
use Biodiverse::SpatialParams;
use Biodiverse::Progress;
use Biodiverse::Indices;
use Biodiverse::Exception;

use base qw /
    Biodiverse::Tree
    Biodiverse::Common
/;

our %PARAMS = (  #  most of these are not used
    DEFAULT_CLUSTER_INDEX => 'SORENSON',
    DEFAULT_LINKAGE       => 'link_average',
    TYPE                  => 'Cluster',
    OUTSUFFIX             => 'bts',
    OUTSUFFIX_YAML        => 'bty',
    OUTPUT_QUOTE_CHAR     => q{"},
    OUTPUT_SEP_CHAR       => q{,},
    COMPLETED             => 0,
);

my $EMPTY_STRING = q{};

our $last_state_debug;


#use Exception::Class (
#    'Biodiverse::Cluster::MatrixExists' => {
#        description => 'A matrix of this name is already in the BaseData object',
#        fields      => [ 'name', 'object' ],
#    },
#);


#  use the "new" sub from Tree.

sub get_default_cluster_index {
    return $PARAMS{DEFAULT_CLUSTER_INDEX};
}

sub get_type {
    return $PARAMS{TYPE};
}

sub get_valid_indices {
    my $self = shift;
    my %args = @_;

    my $bd = $args{BASEDATA_REF} || $self->get_param('BASEDATA_REF');
    my $indices = Biodiverse::Indices->new(BASEDATA_REF => $bd);

    my $method = $self->get_valid_indices_sub;
    return $indices->$method (@_);
}

sub get_valid_indices_sub {
    return 'get_valid_cluster_indices';
}

#  the master export sub is in Biodiverse::Tree
#  this is just to handle the matrices used in clustering
sub get_metadata_export_matrices {
    my $self = shift;

    my %args;

    my $matrices = $self->get_param ('ORIGINAL_MATRICES');
    eval {
        %args = $matrices->[0]->get_args (sub => 'export')
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    #  override matrix setting
    #  could casue grief if matrices allow more than delimited text
    if (! defined $args{format} || $args{format} ne 'Matrices') {
        $args{format} = 'Matrices';
    }

    return wantarray ? %args : \%args;
}

#  export the matrices used in any clustering
sub export_matrices {
    my $self = shift;
    my %args = @_;

    my $matrices      = $self->get_param ('ORIGINAL_MATRICES');
    my $shadow_matrix = $self->get_param ('ORIGINAL_SHADOW_MATRIX');

    #  rebuild if needed
    if (scalar @$matrices == 0) {
        $matrices = $self->build_matrices (@_);
        $shadow_matrix = $self->get_shadow_matrix;
    }

    my $file = $args{file};

    my $i = 0;

    use File::Basename;

    my ($name, $path, $suffix) = File::Basename::fileparse($file);
    if ($suffix ne $EMPTY_STRING) {
        $suffix = ".$suffix";
    }
    $file = File::Spec->catfile ($path, $name);

    foreach my $matrix (@$matrices) {
        next if ! defined $matrix;  #  allow for absent shadow matrix
        my $filename = $file;
        if (scalar @$matrices > 1) {
            #  insert the matrix number before the suffix
            $filename .= "_$i$suffix";
        }
        $matrix->export (
            @_,
            file => $filename,
        );
        $i ++;
    }
    if (scalar @$matrices > 1) {  #  only need the shadow (combined) matrix if more than one was used
        my $filename = $file;
        #$filename =~ s/(\.\S+$)/_shadowmatrix$1/;
        $filename .= "_shadowmatrix$suffix";
        $shadow_matrix->export (
            @_,
            file => $filename
        );
    }

    return;
}

#  build the matrices required
#  need to use $bd->get_cluster_outputs_with_same_index_and_nbrs to allow shortcuts
sub build_matrices {  
    my $self = shift;
    my %args = @_;

    #  any file handles to output
    my $file_handles = $args{file_handles} ? $args{file_handles} : [];
    delete $args{file_handles};

    #  override any args if we are a re-run
    if (defined $self->get_param('ANALYSIS_ARGS')) {  
        %args = %{$self->get_param ('ANALYSIS_ARGS')};
    }
    else {  #  store them for future use
        my %args_sub = %args;
        $self->set_param (ANALYSIS_ARGS => \%args_sub);
    }
    
    my $output_gdm_format = $args{output_gdm_format};  #  need to make all the fle stuff a hashref

    #my $bd = $self->get_param ('BASEDATA_REF') || $self;
    my $bd = $self->get_param ('BASEDATA_REF');

    my $indices_object = Biodiverse::Indices->new(BASEDATA_REF => $bd);
    $self->set_param (INDICES_OBJECT => $indices_object);

    my $index = $args{index} || $self->get_default_cluster_index;
    $self->set_param (CLUSTER_INDEX => $index);
    delete $args{index};  # saves passing it on in the index function args
    croak "[CLUSTER] $index not a valid clustering similarity index\n"
        if ! exists ${$self->get_valid_indices}{$index};

    my $index_function = $indices_object->get_index_source (index => $index);
    croak "[CLUSTER] INDEX function not valid\n"
        if ! exists ${$indices_object->get_calculations_as_flat_hash}{$index_function};
    #  needed for recalculation linkages
    $self->set_param (CLUSTER_INDEX_SUB => $index_function);  

    my $index_params = $indices_object->get_args (sub => $index_function);
    my $index_order  = $index_params->{indices}{$index}{cluster};
    # cache unless told otherwise
    my $cache_abc = 1;
    if (defined $args{no_cache_abc}) {
        $cache_abc = not $args{no_cache_abc};
    }
    else {
        $cache_abc = ($index_order ne 'NO_CACHE_ABC');
    }
    $self->set_param (CACHE_ABC => $cache_abc);

    if ($args{objective_function}) {
        $self->set_param (CLUSTER_MOST_SIMILAR_SUB => $args{objective_function});
    }
    if (ref ($index_order) =~ /ARRAY/) {  #  redundant now?
        $self->set_param (CLUSTER_MOST_SIMILAR_SUB =>
            ($index_order->[1] > $index_order->[0]
             ? 'get_min_value'
             : 'get_max_value'
             )
        );
    }  # determines if we cluster on higher or lower values

    $indices_object->get_valid_calculations (
        %args,
        calculations    => [$index_function],
        use_list_count  => 2,
    );

    #  run the global pre_calcs
    $indices_object->run_precalc_globals(%args);

    my $name = $args{name} || $self->get_param ('NAME') || "CLUSTERMATRIX_$index";

    #  we work with any number of spatial conditions, but default to consider everything
    if (! defined $args{spatial_conditions}) {
        $args{spatial_conditions} = ['sp_select_all ()'];
    }

    my @spatial_conditions = @{$args{spatial_conditions}};
    #  and we remove any undefined or empty conditions
    for my $i (reverse 0 .. $#spatial_conditions) {

        if (    defined $spatial_conditions[$i]
            and length $spatial_conditions[$i] == 0) {
            $spatial_conditions[$i] = undef;
        }
        if (not defined $spatial_conditions[$i]) {
            splice (@spatial_conditions, $i);
            next;
        }
    }

    #  now generate the spatial_params
    my $spatial_params_array = [];
    my $i = 0;
    foreach my $condition (@spatial_conditions) {
        if (! defined $spatial_params_array->[$i]) {
            $spatial_params_array->[$i]
              = Biodiverse::SpatialParams->new (conditions => $spatial_conditions[$i]);
        }
        $i++;
    }
    #  add true condition if needed, and always add it if user doesn't specify
    if (scalar @$spatial_params_array == 0) {  
        push (@$spatial_params_array, Biodiverse::SpatialParams->new (conditions => 1));
        push (@spatial_conditions, 1);
    }

    #  now we loop over the conditions and initialise the matrices
    #  kept separate frpom previous loop for cleaner default matrix generation
    my @matrices;
    $i = 0;
    foreach my $condition (@spatial_conditions) {
        my $mx_name = $name . " Matrix_$i";

        my $already_there = $bd->get_matrix_outputs;
        if (exists $already_there->{$mx_name}) {
            Biodiverse::Cluster::MatrixExists->throw(
                message => "Matrix $name already exists\n",
                name    => $mx_name,
                object  => $already_there->{$mx_name},
            );
        }

        $matrices[$i] = Biodiverse::Matrix->new(
            JOIN_CHAR => $bd->get_param('JOIN_CHAR'),
            NAME      => $mx_name,
        );
        $i ++;
    }

    my $shadow_matrix;
    if (scalar @matrices > 1) {
        $shadow_matrix = Biodiverse::Matrix->new (
            name => $name . '_SHADOW_MATRIX'
        );
    }
    $self->set_shadow_matrix (matrix => $shadow_matrix);

    #  store for later
    if (not defined $self->get_param ('SPATIAL_PARAMS')) {
        $self->set_param (SPATIAL_PARAMS => $spatial_params_array)
    }

    #  let the spatial object to handle the object stuff
    my $definition_query
        = $self->get_param ('DEFINITION_QUERY')
          || $args{definition_query};
    #if (defined $definition_query) {  #  parse it if defined
    #    if (length ($definition_query) == 0) {
    #        $definition_query = undef ;
    #    }
    #    elsif (not blessed $definition_query) {
    #        $definition_query = Biodiverse::SpatialParams::DefQuery->new (
    #            conditions => $definition_query,
    #        );
    #    }
    #}
    if (not defined $self->get_param ('DEFINITION_QUERY')) {
        $self->set_param (DEFINITION_QUERY => $definition_query);
    }

    print "[CLUSTER] BUILDING ", scalar @matrices, " MATRICES FOR $index CLUSTERING\n";

    #  print headers to file handles (if such are present)
    foreach my $fh (@$file_handles) {
        print {$fh} $output_gdm_format
        ? "x1,y1,x2,y2,$index\n"
        : "Element1,Element2,$index\n";
    }

    #  we use a spatial object as it handles all the spatial checks.
    print "[CLUSTER] Generating neighbour lists\n";
    my $sp = $bd->add_spatial_output (name => $name . "_to_get_nbrs_for_clustering_" . time());
    my $sp_success = eval {
        $sp->run_analysis (
            %args,
            calculations                  => [],
            override_valid_analysis_check => 1,
            spatial_conditions            => \@spatial_conditions,
            definition_query              => $definition_query,
            no_create_failed_def_query    => 1,  #  only want those that pass the def query
            calc_only_elements_to_calc    => 1,
            exclude_processed_elements    => 1,
        );
    };
    my $e = $EVAL_ERROR;                #  Did we complete properly?
    #$bd->delete_output (output => $sp); #  Clear it from the basedata object.
    croak $e if $e;                     #  Throw a hissy fit if we didn't complete properly

    my %cache;  #  cache the label hashes
                # - makes a small amount of difference
                # which will count for randomisations
    $self->set_param (MATRIX_ELEMENT_LABEL_CACHE => \%cache);

    my %done;
    #my @nbr_matrices;  #  cache of each set of neighbours
    my $valid_count = 0;

    # only those that passed the def query (if set) will be considered
    # sort to ensure consistent order - easier for debug
    my @elements_to_calc = sort keys %{$sp->get_element_hash};

    my $toDo = scalar @elements_to_calc;

    croak "No elements to cluster, check your spatial conditions and def query\n"
      if not scalar $toDo;

    my $progress_bar = Biodiverse::Progress->new();
    my $count = 0;
    my $printedProgress = -1;
    my $target_element_count = $toDo * ($toDo - 1) / 2; # n(n-1)/2
    my $progress_pfx = "Building matrix\n"
                        . "$name\n"
                        . "Target is $target_element_count matrix elements\n";
    #print "[CLUSTER] Progress (% of $toDo elements):     ";
    my @processed_elements;

    #  Use $sp for the groups so any def query will have an effect
    BY_ELEMENT:
    foreach my $element1 (sort @elements_to_calc) {

        $count ++;
        my $progress = $count / $toDo;
        $progress_bar->update(
            $progress_pfx . "(row $count / $toDo)",
            $progress,
        );

        my @neighbours;  #  store the neighbours of this element
        my %all_nbrs_this_element;
        foreach my $i (0 .. $#matrices) {
            my $nbr_list_name = '_NBR_SET' . ($i+1);
            my $neighours = $sp->get_list_values (
                element => $element1,
                list    => $nbr_list_name,
            );
            my %neighbour_hash;
            @neighbour_hash{@$neighours} = (1) x scalar @$neighours;
            delete $neighbour_hash{$element1};  #  exclude ourselves
            $neighbours[$i] = \%neighbour_hash;

            @all_nbrs_this_element{@$neighours} = (1) x scalar @$neighours;
            #if ($i) {  #  matrices should not be exclusive?
            #    #  merge $i-1
            #}
            #$nbr_matrices[$i]{$element1} = $neighbours[$i];
        }

        #  loop over the neighbours and add them to the appropriate matrix
        foreach my $i (0 .. $#matrices) {
            my $matrix = $matrices[$i];

            my %nbrs = %{$neighbours[$i]};  #  save a few calcs

            my $matrices_array = defined $shadow_matrix
                                ? [$matrix, $shadow_matrix]
                                : [$matrix];

            #  this actually takes most of the args from params,
            #  but setting explicitly might save micro-seconds of time
            my $x = $self->build_matrix_elements (
                %args,  
                matrices           => $matrices_array,
                element            => $element1,
                element_list       => [keys %nbrs],
                index_function     => $index_function,
                index              => $index,
                cache_abc          => $cache_abc,
                file_handle        => $file_handles->[$i],
                spatial_object     => $sp,
                indices_object     => $indices_object,
                processed_elements => \@processed_elements,
            );

            $valid_count += $x;
        }

        push @processed_elements, $element1;
    }

    my $element_check = $self->get_param ('ELEMENT_CHECK');

    $progress_bar->update(
        "Building matrix\n$name\n(row $count / $toDo)",
        $count / $toDo
    );
    $progress_bar->reset;
    print "[CLUSTER] Completed $count of $toDo groups\n";

    print "[CLUSTER] Valid value count is $valid_count\n";
    if (! $valid_count) {
        croak "No valid results - matrix is empty\n";
    }

    $self->set_matrix_ref(matrices => \@matrices);

    #  Clear the cache unless we're using link_recalculate
    #  Is this already set or not?
    my $analysis_args = $self->get_param ('ANALYSIS_ARGS');
    my $linkage_function = $analysis_args->{linkage_function};
    if (defined $linkage_function and not $linkage_function =~ /recalculate/) {
        $self->set_param (MATRIX_ELEMENT_LABEL_CACHE => undef);
    }

    return wantarray ? @matrices : \@matrices;
}

sub build_matrix_elements {
    my $self = shift;
    my %args = @_;

    my $element1 = $args{element};
    my $element_list2 = $args{element_list};
    if ((ref $element_list2) =~ /HASH/) {
        $element_list2 = [keys %$element_list2];
    }

    my $cache = $args{element_label_cache} || $self->get_param ('MATRIX_ELEMENT_LABEL_CACHE');
    my $matrices = $args{matrices};  #  two items, second is shadow matrix

    my $index_function   = $args{index_function}
                           || $self->get_param ('CLUSTER_INDEX_SUB');
    my $index            = $args{index}
                           || $self->get_param ('CLUSTER_INDEX');
    my $cache_abc        = $args{cache_abc}
                           || $self->get_param ('CACHE_ABC');
    my $indices_object   = $args{indices_object}
                           || $self->get_param ('INDICES_OBJECT');

    my $processed_elements = $args{processed_elements};

    my $ofh = $args{file_handle};
    delete $args{file_handle};
    my $output_gdm_format = $args{output_gdm_format};

    my $bd = $self->get_param ('BASEDATA_REF');

    my $sp = $args{spatial_object};
    my $pass_def_query = $sp->get_param ('PASS_DEF_QUERY');
    #my $pass_def_query = {};

    my %already_calculated;

    my $csv_out;
    #  take care of closed file handles
    if ( defined $ofh ) {
        if ( not defined fileno $ofh ) {
            warn "[CLUSTER] Output file handle for matrix "
                . $matrices->[0]->get_param('NAME')
                . " is unusable, setting it to undef";
            $ofh = undef;
        }
        $csv_out = $self->get_csv_object;

        %already_calculated = $self->infer_if_already_calculated (
            spatial_object => $sp,
            element => $element1,
            processed_elements => $processed_elements,
        );
    }

    my $valid_count = 0;
    
    #print "Elements to calc: ", (scalar @$element_list2), "\n";

    ELEMENTS:
    foreach my $element2 (sort @$element_list2) {
        next ELEMENTS if $element1 eq $element2;
        next ELEMENTS if $already_calculated{$element2};

        if ($pass_def_query) {  #  poss redundant check now
            my $null = undef;  #  debug
            next ELEMENTS
              if (not exists $pass_def_query->{$element2});
        }

        #  If we already have this value then get it and assign it.
        #  Some of these contortions appear to be due to an old approach
        #  where all matrices were built in one loop.
        #  Could probably drop out sooner now. 
        my $exists = 0;
        my $iter = 0;
        my %not_exists_iter;
        my $value;
        MX:
        foreach my $mx (@$matrices) {  #  second is shadow matrix, if given
            #last MX if $ofh;
            
            my $x = $mx->element_pair_exists (
                element1 => $element1,
                element2 => $element2
            );
            if  ($x) {  #  don't redo them...
                $value = $mx->get_value (
                    element1 => $element1,
                    element2 => $element2,
                );
                $exists ++;
            }
            else {
                $not_exists_iter{$iter} = 1;
            }
            $iter ++;
        }

        next ELEMENTS if $exists == scalar @$matrices;  #  it is in all of them already

        if ($exists) {  #  if it is in one then we use it
            foreach my $iter (keys %not_exists_iter) {
                $matrices->[$iter]->add_element (
                    element1 => $element1,
                    element2 => $element2,
                    value    => $value,
                )
            }
        }
        next ELEMENTS if $exists;

        #  use elements if no cached labels
        #  set to undef if we have a cached label_hash
        my ($el1_ref, $el2_ref, $label_hash1, $label_hash2);
        if ($cache_abc) {
            $el1_ref = defined $cache->{$element1} ? undef : [$element1];
            $el2_ref = defined $cache->{$element2} ? undef : [$element2];

            #  use cached labels if they exist (gets undef otherwise)
            $label_hash1 = exists $cache->{$element1} ? $cache->{$element1} : undef;
            $label_hash2 = exists $cache->{$element2} ? $cache->{$element2} : undef;
        }
        else {
            $el1_ref = [$element1];
            $el2_ref = [$element2];            
        }

        my %elements = (
            element_list1   => $el1_ref,
            element_list2   => $el2_ref,
            label_hash1     => $label_hash1,
            label_hash2     => $label_hash2,
        );

        my $values = $indices_object->run_calculations(%args, %elements);

        # useful for debugging  (comment out otherwise?)
        if ($EVAL_ERROR && ! defined $values->{$index}) {
            croak "PROBLEMS WITH $element1 $element2\n"
                  . $EVAL_ERROR;
        }

        #  caching - a bit dodgy
        #  what if we have calc_abc and calc_abc3 as deps?
        if ($cache_abc) {
            my $abc = {};
            my $as_results_from = $indices_object->get_param('AS_RESULTS_FROM');
            foreach my $calc_abc_type (qw /calc_abc3 calc_abc2 calc_abc/) {
                if (exists $as_results_from->{$calc_abc_type}) {
                    $abc = $as_results_from->{$calc_abc_type};
                    last;
                }
            }

            #  use cache unless told not to
            if (defined $abc->{label_hash1} and ! defined $cache->{$element1}) {
                $cache->{$element1} = $abc->{label_hash1};
            }
            if (defined $abc->{label_hash2} and ! defined $cache->{$element2}) {
                $cache->{$element2} = $abc->{label_hash2}
            }
        }

        next if ! defined $values->{$index};  #  don't add it if it is undefined

        # write results to file handles if supplied, otherwise store them
        if (defined $ofh) {
            my $res_list = $output_gdm_format
                ? [
                   @{[$bd->get_group_element_as_array(element => $element1)]}[0,1],  #  need to generalise these
                   @{[$bd->get_group_element_as_array(element => $element2)]}[0,1],
                   $values->{$index}
                   ]
                : [$element1, $element2, $values->{$index}];
            my $text = $self->list2csv(
                list       => $res_list,
                csv_object => $csv_out,
            );
            print {$ofh} ($text . "\n");
        }
        else {
            foreach my $mx (@$matrices) {
                $mx->add_element (
                    element1 => $element1,
                    element2 => $element2,
                    value    => $values->{$index}
                );
            }
        }

        $valid_count ++;
    }
    
    my $cache_size = scalar keys %$cache;

    return $valid_count;
}

#  We have been calculated
#  if el2 is a neighbour of el1,
#  and el1 has been processed.
sub infer_if_already_calculated {
    my $self = shift;
    my %args = @_;

    my $sp = $args{spatial_object};
    my $element = $args{element};
    my $processed_elements = $args{processed_elements};

    my %already_calculated;
    
    return wantarray ? %already_calculated : \%already_calculated
      if scalar @$processed_elements == 0;
    
    my $nbr_list_name = '_NBR_SET1';  #  need to generalise this, or pass as an arg (and make a method)
    my $nbrs
          = $sp->get_list_values (
              element => $element,
              list    => $nbr_list_name,
              autovivify => 0,
          )
          || [];

    NBR:
    foreach my $nbr (sort @$nbrs) {
        next NBR if ! defined (List::Util::first {$_ eq $nbr} @$processed_elements);
        $already_calculated{$nbr} = 1;
    }

    return wantarray ? %already_calculated : \%already_calculated;
}

#  add the matrices to the basedata object
sub add_matrices_to_basedata {
    my $self = shift;

    my $bd = $self->get_param ('BASEDATA_REF');
    my $orig_matrices = $self->get_param ('ORIGINAL_MATRICES');
    foreach my $mx (@$orig_matrices) {
        $bd->add_output(object => $mx);
    }
    return;
}

sub get_orig_matrices {
    my $self = shift;
    my $matrices = $self->get_param ('ORIGINAL_MATRICES');

    return wantarray ? @$matrices : $matrices;
}

sub get_matrices_ref {
    my $self = shift;
    #my %args = @_;
    return $self->{MATRICES};
}

#  get a reference to the matrix object within this cluster object
sub get_matrix_ref {  
    my $self = shift;
    my %args = @_;

    return if not exists $self->{MATRICES};  #  avoid autovivification

    my $i = $args{iter} || 0;  #  need to implement an index of which to use 
    return $self->{MATRICES}[$i];
}

sub get_matrix_count {
    my $self = shift;
    return if not exists $self->{MATRICES};  #  avoid autovivification

    return scalar @{$self->{MATRICES}};
}

#  Set the matrix reference,
#  for example if the user has a matrix they have already calculated.
sub set_matrix_ref {
    my $self = shift;
    my %args = @_;
    
    if ($args{cluster_matrix}) {
        $self->{MATRICES} = [$args{cluster_matrix}];
    }
    else {
        croak "Argument 'matrices' not provided\n"
          if ! exists $args{matrices};
        croak "Argument 'matrices' is not an array\n"
          if ! (ref $args{matrices}) =~ /ARRAY/;

        $self->{MATRICES} = $args{matrices};
    }

    return;
}

sub set_shadow_matrix {
    my $self = shift;
    my %args = @_;
    $self->{SHADOW_MATRIX} = $args{matrix};  #  defaults to undef
    return;
}

#  get a reference to the shadow matrix object within this cluster object - this is the combination of all the matrices
sub get_shadow_matrix {
    my $self = shift;
    return $self->{SHADOW_MATRIX};
}

#  get a reference to the spatial matrix object within this cluster object
sub delete_shadow_matrix {
    my $self = shift;
    return if not exists $self->{SHADOW_MATRIX}; #  avoid autovivification
    $self->{SHADOW_MATRIX} = undef;
    delete $self->{SHADOW_MATRIX};
    return;
}

#  redundant? 
sub get_nbr_matrix_ref {
    my $self = shift;
    return if not exists $self->{NBR_MATRICES}; #  avoid autovivification
    my %args = @_;
    my $i = $args{iter};
    return $self->{NBR_MATRICES}[$i];
}

#  redundant? 
sub delete_nbr_matrices {
    my $self = shift;
    return if not exists $self->{NBR_MATRIX}; #  avoid autovivification
    delete $self->{NBR_MATRICES};
    return;
}

sub get_most_similar_matrix_value {
    my $self = shift;
    my %args = @_;
    my $matrix = $args{matrix} || croak "matrix arg not specified\n";
    my $sub = $self->get_param ('CLUSTER_MOST_SIMILAR_SUB') || 'get_min_value';
    return $matrix->$sub;
}

sub get_default_linkage {
    my $self = shift;

    return $PARAMS{DEFAULT_LINKAGE};
}

sub cluster_matrix_elements {
    my $self = shift;
    my %args = @_;

    my $progress_bar = Biodiverse::Progress->new();

    if (defined $self->get_param('ANALYSIS_ARGS')) {
        %args = %{$self->get_param ('ANALYSIS_ARGS')};
    }
    else {  #  store them for future use
        my %args_sub = %args;
        delete $args_sub{file_handles};  #  don't store these as Storable no like them
        $self->set_param (ANALYSIS_ARGS => \%args_sub);
    }

    #  set the option for the linkage rule - default is specified in the object params
    my $linkage_function = $self->get_param ('LINKAGE_FUNCTION')
                            || $args{linkage_function}
                            || $self->get_default_linkage;
    $self->set_param (LINKAGE_FUNCTION => $linkage_function);

    my $rand = $self->initialise_rand;
    my @state = $rand->get_state;
    print join " ", @state[0..9];
    #do {  #  a bit of debug
    #    my $different = 0;
    #    my $state = $rand->get_state;
    #    if ($last_state_debug) {
    #        foreach my $i (0 .. $#$last_state_debug) {
    #            if ($last_state_debug->[$i] != $state->[$i]) {
    #                $different ++;
    #            }
    #        }
    #    }
    #    warn "State is not different\n" if $different == 0;
    #    $last_state_debug = $state;
    #};
    #for (0 .. 9) {print $rand->irand . ' '};
    #print "\n";
    

    my $mx_iter = $self->get_param ('CURRENT_MATRIX_ITER');
    my $sim_matrix = $self->get_matrix_ref (iter => $mx_iter);
    croak "No matrix reference available\n" if not defined $sim_matrix;

    my $matrix_count = $self->get_matrix_count;

    print "[CLUSTER] CLUSTERING USING $linkage_function, matrix iter $mx_iter of ",
            ($self->get_matrix_count - 1),
            "\n";

    my $new_node;
    my $minValue;
    #  track the number of joins - use as element name for merged nodes
    my $join_number = $self->get_param ('JOIN_NUMBER') || -1;  
    my $total = $sim_matrix->get_element_count;
    croak "Matrix has no elements\n" if not $total;

    my $remaining;

    local $| = 1;  #  write to screen as we go

    my $count = 0;
    my $printedProgress = -1;
    my $name = $self->get_param ('NAME') || 'no_name';
    my $progress_text = "Matrix iter $mx_iter of " . ($matrix_count - 1) . "\n";
    $progress_text .= $args{progress_text} || $name;
    print "[CLUSTER] Progress (% of $total elements):     ";
    my $last_update_time = [gettimeofday];

    while ( ($remaining = $sim_matrix->get_element_count) > 0) {
        #print "Remaining $remaining\n";

        #  get the most similar two candidates
        $minValue = $self->get_most_similar_matrix_value (matrix => $sim_matrix);

        $join_number ++;

        my $text = "Clustering\n"
                 . "$progress_text\n("
                 . ($remaining - 1)
                 . " remaining)\nMost similar value is "
                 . sprintf ("%.3f", $minValue);

        $progress_bar->update ($text, 1 - $remaining / $total);

        $count ++;

        my $keysRef = $sim_matrix->get_elements_with_value (value => $minValue);
        my $count1  = scalar keys %{$keysRef};
        my $keys    = $rand->shuffle ([sort keys %{$keysRef}]);
        #my $keys    = [sort keys %{$keysRef}];
        my $node1   = $keys->[0];  # grab the first shuffled key
        my $count2  = scalar keys %{$keysRef};
        $keys       = $rand->shuffle ([sort keys %{$keysRef->{$node1}}]);
        #$keys       = [sort keys %{$keysRef->{$node1}}];
        my $node2   = $keys->[0];  #  grab the first shuffled sub key

        #print "$join_number $count1, $count2\n" if $count1 > 1 and $count2 > 1;

        #  use node refs for children that are nodes
        #  use original name if not a node
        #  - this is where the name for $el1 comes from (a historical leftover)
        my ($el1, $el2);
        my $lengthBelow = 0;
        my $nodeNames = $self->get_node_hash;
        if (defined $nodeNames->{$node1}) {
            $el1 = $nodeNames->{$node1};
        }
        else {
            $el1 = $node1;
        }
        if (defined $nodeNames->{$node2}) {
            $el2 = $nodeNames->{$node2};
        }
        else {
            $el2 = $node2;
        }

        #print "cluster $join_number $minValue $el1 $el2\n";
        #print "Cluster $join_number :: $minValue :: $node1 :: $node2\n";

        my $new_node_name = $join_number . "___";

        #  create a new node using the elements - creates children as TreeNodes if needed
        $new_node = $self->add_node (
            name => $new_node_name,
            children => [$el1, $el2],
        );

        $new_node->set_value (
            MATRIX_ITER_USED => $mx_iter,
            JOIN_NUMBER      => $join_number,
        );
        $new_node->set_child_lengths (total_length => $minValue);

        #  add children to the node hash if they are terminals
        foreach my $child ($new_node->get_children) {
            if ($child->is_terminal_node) {
                if (not $self->exists_node (node_ref => $child)) {
                    $self->add_to_node_hash (node_ref => $child);
                }

                $child->set_value (
                    MATRIX_ITER_USED => $mx_iter,
                    JOIN_NUMBER      => $join_number,
                );
            }
        }

        ###  now we rebuild the similarity matrix to include the new linkages and destroy the old ones
        #  possibly we should return a list of other matrix elements where the length
        #  difference is 0 and which therefore could be merged now rather than next iteration
        $self->run_linkage (
            node1            => $node1,
            node2            => $node2,
            new_node_name    => $new_node_name,
            linkage_function => $linkage_function,
            #merge_track_matrix => $merged_mx,
        );
    }

    #  finish off the progress
    $progress_bar->update (undef, 1);

    $self->set_param(JOIN_NUMBER => $join_number);
    $self->set_param(MIN_VALUE   => $minValue);

    $self->store_rand_state (rand_object => $rand);

    return;
}

sub run_analysis {
    my $self = shift;
    return $self->cluster(@_);
}

sub cluster {
    my $self = shift;
    my %args = (
        clear_cached_values => 1,
        flatten_tree        => 1,
        @_,
    );

    my $start_time = time;

    $self->set_param (COMPLETED => 0);
    $self->set_param (JOIN_NUMBER => -1);  #  ensure they start counting from 0
    
    my $file_handles = $args{file_handles};

    #  override most of the arguments if the system has values set
    if (defined $self->get_param('ANALYSIS_ARGS')) {
        %args = %{$self->get_param ('ANALYSIS_ARGS')};
    }
    else {  #  store them for future use
        my %args_sub = %args;
        delete $args_sub{file_handles};  #  but don't store file handles
        $self->set_param (ANALYSIS_ARGS => \%args_sub);
    }

    #  a little backwards compatibility
    if (exists $args{spatial_analyses}
        && ! exists $args{spatial_calculations}) {
        $args{spatial_calculations} = $args{spatial_analyses};
    }
    $self->set_param (CALCULATIONS_REQUESTED => $args{spatial_calculations});

    my @matrices;
    #  if we were passed a matrix in the args  
    if ($args{cluster_matrix}) {  #  THIS PROCESS NEEDS FIXING
        my $clust_mx = $args{cluster_matrix}->clone;  #  make a copy so we don't destroy the original
        $self->set_matrix_ref (%args, cluster_matrix => $clust_mx);
        #$self->set_shadow_matrix (matrix => $clust_mx);
        @matrices = ($clust_mx);
        #  save the matrices for later export
        #$self->set_param (ORIGINAL_SHADOW_MATRIX => $args{matrix});
        $self->set_param (ORIGINAL_MATRICES => [$args{matrix}]);
    }
    else {
        #  try to build the matrices.
        if (not $self->get_matrix_count) {
            #  Can we get them from the originals?
            #  Need to generalise to get them from another
            #  cluster/regiongrower output if available.
            my $original_matrices = $self->get_param('ORIGINAL_MATRICES');
            if ($original_matrices) {
                foreach my $mx (@$original_matrices) {
                    push @matrices, $mx->clone;
                }
                my $orig_shadow_mx = $self->get_param('ORIGINAL_SHADOW_MATRIX');
                eval {
                    $self->set_shadow_matrix (matrix => $orig_shadow_mx->clone);
                }
            }
            else {  #  build them
                @matrices = eval {
                    $self->build_matrices (file_handles => $file_handles);
                };
                croak $EVAL_ERROR if $EVAL_ERROR;
            }
            $self->set_matrix_ref(matrices => \@matrices);
        }
        #  bail if first matrix could not be built (are we trapping this with prev croak now?)
        croak "[CLUSTER] Matrix could not be built\n"
            if not defined $self->get_matrix_ref;  

        #  save clones of the matrices for later export
        print "[CLUSTER] Creating and storing matrix clones\n";

        my $clone = eval {$self->get_shadow_matrix->clone};
        $self->set_param (ORIGINAL_SHADOW_MATRIX => $clone);
        my $original_matrices = $self->clone (data => \@matrices);
        $self->set_param (ORIGINAL_MATRICES => $original_matrices);

        print "[CLUSTER] Done\n";

        #  should probably use matrix refs instead of cloning if this is set
        if ($args{file_handles}) {
            $self->set_param(COMPLETED => 3);
            return 3;  #  don't try to cluster and don't add anything to the basedata
        }
        elsif ($args{build_matrices_only}) {
            $self->add_matrices_to_basedata;
            #  clear the other matrices
            $self->set_matrix_ref (matrices => []);
            $self->set_shadow_matrix(matrix => undef);
            $self->set_param(COMPLETED => 2);
            return 2;
        }
    }

    #  no shadow matrix if only one matrix
    my $matrix_for_nodes = $self->get_shadow_matrix || $matrices[0];

    #  loop over the shadow matrix and create nodes for each matrix element
    print "[CLUSTER] Creating terminal nodes\n";
    foreach my $element (sort $matrix_for_nodes->get_elements_as_array) {
        next if not defined $element;
        $self->add_node (name => $element);
    }

    MATRIX:
    foreach my $i (0 .. $#matrices) {  #  or maybe we should destructively sample this as well?
        print "[CLUSTER] Using matrix $i\n";
        $self->set_param (CURRENT_MATRIX_ITER => $i);

        #  no elements left, so we've used this one up.  Move to the next
        next MATRIX if $matrices[$i]->get_element_count == 0;  

        eval {
            $self->cluster_matrix_elements (%args);
        };
        croak $EVAL_ERROR if $EVAL_ERROR;
    }

    #  run some cleanup on the indices object
    my $indices_object = $self->get_param('INDICES_OBJECT');
    if ($indices_object) {
        eval {
            $indices_object->run_postcalc_globals;
            $indices_object->reset_results(global => 1);
        };
    }
    $self->set_param(INDICES_OBJECT => undef);

    my %root_nodes = $self->get_root_nodes;

    if (scalar keys %root_nodes > 1) {
        print "[CLUSTER] CLUSTER TREE HAS MULTIPLE ROOT NODES\n"
            . "Count is "
            . (scalar keys %root_nodes)
            . "\n"
            . 'MinValue is '
            . $self->get_param('MIN_VALUE')
            . "\n";
    }

    #  loop over the one or more root nodes and remove zero length nodes
    if (1 && $args{flatten_tree}) {
        my $i = 1;
        foreach my $root_node (values %root_nodes) {
            print "[CLUSTER] Root node $i" . $root_node->get_name . "\n";
            my @now_empty = $root_node->flatten_tree;
            #  now we clean up all the empty nodes in the other indexes
            if (scalar @now_empty) {

                print '[CLUSTER] Deleting '
                      . scalar @now_empty
                      . " empty nodes\n";

                $self->delete_from_node_hash (nodes => \@now_empty);
            }
            $i++;
        }
    }

    #  now stitch the root nodes together into one
    #  (needs to be after flattening or nodes get pulled up too far)
    $self->join_root_nodes (%args);

    my $root_node_name = [keys %{$self->get_root_nodes}]->[0];
    my $root_node = $self->get_node_ref (node => $root_node_name);

    my $tot_length = $self->get_param('MIN_VALUE');   #  GET THE FIRST CHILD AND THE LENGTH FROM IT?
    $root_node->set_length(length => 0);
    $root_node->set_value (
        TOTAL_LENGTH => $self->get_param('MIN_VALUE'),
        JOIN_NUMBER  => $self->get_param('JOIN_NUMBER'),
    );

    if (! $args{retain_nbr_matrix}) {
        $self->delete_nbr_matrices;
    }
    if ($args{clear_cached_values}) {
        $root_node->delete_cached_values_below;
    }
    $root_node->number_terminal_nodes;

    #  set the TREE value to be the root TreeNode - the nested structure takes care of the rest
    #  the root node is the last one we created
    $self->{TREE} = $root_node;

    #  clear all our refs to the matrix
    #  it should be empty anyway, since we don't do partial (yet)
    $self->set_param(MATRIX_REF => undef);
    $self->{MATRIX} = undef;
    delete $self->{MATRIX};

    if ($args{spatial_calculations}) {
        my $success = eval {
            $self->sp_calc (
                %args,
                calculations => $args{spatial_calculations},
            )
        };
        croak $EVAL_ERROR if $EVAL_ERROR;
    }

    $self->add_matrices_to_basedata;

    my $time_taken = time - $start_time;
    print "[CLUSTER] Analysis took $time_taken seconds.\n";
    $self->set_param (ANALYSIS_TIME_TAKEN => $time_taken);
    $self->set_param (COMPLETED => 1);

    $self->set_last_update_time;

    #  returns undef if in void context (probably unecessary complexity?)
    #return defined wantarray ? $root_node : undef;
    $self->set_param(COMPLETED => 1);
    return 1;
}

#  just stick the root nodes together
#  if we have many left from clustering
sub join_root_nodes {
    my $self = shift;

    my $nodes = $self->get_root_nodes;

    #  drop out if only 1 root node
    return if scalar keys %$nodes == 0;

    my $target_len;

    #  find the longest path
    foreach my $node (values %$nodes) {
        my $len = $node->get_length_below;

        #  check allows for clusters with any min value
        if (!defined $target_len) {
            $target_len = $len;
        }

        if ($len > $target_len) {
            $target_len = $len;
        }
    }

    #print "Target length is $target_len\n";

    my $root_node = $self->add_node(
        length => 0,
        name   => $self->get_free_internal_name,
    );
    $root_node->set_value(JOIN_NOT_METRIC => 1);

    #  need to add a flag to say these are artificial

    #  set the length of each former root node
    foreach my $node (values %$nodes) {
        my $current_len = $node->get_length;
        my $len = $target_len - $node->get_length_below;

        #print "$target_len, $current_len, $len\n";

        $node->set_length(length => $len);
        $node->set_value(JOIN_NOT_METRIC => 1);
    }

    $root_node->add_children(children => [values %$nodes]);

    return;
}

#  return the average similarity between a set of nodes
sub link_average_unweighted {  
    my $self = shift;

    my ($tmp1, $tmp2) = $self->get_values_for_linkage(@_);

    my $value = ($tmp1 + $tmp2) / 2;

    return wantarray ? (value => $value) : {value => $value};
}

#  calculate the average of the previous similarities,
#  accounting for the number of nodes they contain
sub link_average {  
    my $self = shift;
    my %args = @_;

    croak "one of the nodes not specified in linkage function call\n"
      if ! defined $args{node1} || ! defined $args{node2};

    my $node1 = $args{node1};
    my $node2 = $args{node2};

    my $el1_count = scalar keys %{$self->get_terminal_elements (node => $node1)};
    my $el2_count = scalar keys %{$self->get_terminal_elements (node => $node2)};

    my ($tmp1, $tmp2) = $self->get_values_for_linkage (%args);

    my $value  =  ($el1_count * $tmp1 + $el2_count * $tmp2)
                / ($el1_count + $el2_count);

    return wantarray ? (value => $value) : {value => $value};
}

sub link_minimum {
    my $self = shift;

    my $value = min ($self->get_values_for_linkage (@_));

    return wantarray ? (value => $value) : {value => $value};
}

sub link_maximum {
    my $self = shift;

    my $value = max ($self->get_values_for_linkage (@_));

    return wantarray ? (value => $value) : {value => $value};
}

sub _link_centroid {
    my $self = shift;
    #  calculate the centroid of the similarities below this
    #  requires that we traverse the tree - or at least cache the values
    return;
}

sub get_values_for_linkage {
    my $self = shift;
    my %args = @_;

    croak "one of the nodes not specified in linkage function call\n"
      if ! defined $args{node1} || ! defined $args{node2};

    my $node1 = $args{node1};
    my $node2 = $args{node2};
    my $check_node = $args{compare_node};

    my $sim_matrix = $args{matrix}
        || croak "argument 'matrix' not specified\n";
    my ($tmp1, $tmp2);

    if (defined $check_node) {
        $tmp1 = $sim_matrix->get_value (element1 => $check_node, element2 => $node1);
        $tmp2 = $sim_matrix->get_value (element1 => $check_node, element2 => $node2);
    }
    else {
        warn "two node linkage case\n";
        my $nodeRef1 = $self->get_node_ref (node => $node1);
        my $nodeRef2 = $self->get_node_ref (node => $node2);
        $tmp1 = $nodeRef1->get_length_below;
        $tmp2 = $nodeRef2->get_length_below;
    }

    return wantarray ? ($tmp1, $tmp2) : [$tmp1, $tmp2];
}

#  calculate the linkages fom the ground up
sub link_recalculate {
    my $self = shift;
    my %args = @_;
    croak "one of the nodes not specified\n"
        if ! defined $args{node1} || ! defined $args{node2};

    my $node1 = $args{node1};
    my $node2 = $args{node2};
    my $check_node = $args{compare_node};

    my $node1_ref = $self->get_node_ref (node => $node1);
    my $node2_ref = $self->get_node_ref (node => $node2);
    my $check_node_ref = $self->get_node_ref (node => $check_node);

    my $sim_matrix = $args{matrix}
                    || $self->get_shadow_matrix
                    || $self->get_matrix_ref(iter => 0);

    my $index_function
        = $args{index_function}
        || $self->get_param ('CLUSTER_INDEX_SUB');

    my $index
        = $args{index}
        || $self->get_param ('CLUSTER_INDEX');

    my $cache_abc
        = $args{cache_abc}
        || $self->get_param ('CACHE_ABC');

    my $indices_object
        = $args{indices_object}
        || $self->get_param('INDICES_OBJECT');

    #  for the dependency analyses,
    #  we treat node1 and node2 as one element set,
    #  and check_node as the other

    #  stage some of the cached lists
    #  - these are filled in as needed and possible
    my ($el1_list, $el2_list, $label_hash1, $label_hash2);

    my $node1_2_cache_name = 'LABEL_HASH_' . $node1 . '__' . $node2;
    my $node2_1_cache_name = 'LABEL_HASH_' . $node2 . '__' . $node1;

    #  get the element or label lists as needed
    if ($node1_ref) {
        $label_hash1 = $node1_ref->get_cached_value ($node1_2_cache_name) ;
    }
    elsif ($node2_ref) {
        $label_hash1 = $node1_ref->get_cached_value ($node1_2_cache_name);
    }
    #  if no cahced value then merge the lists of terminal elements
    if (not $label_hash1) {
        $el1_list = [];
        #  only need to do the check until all terminal nodes
        #  are created before clustering
        #  -- is that the case now? --
        push @$el1_list,
            $node1_ref ? keys %{$node1_ref->get_terminal_elements} : $node1;  
        push @$el1_list,
            $node2_ref ? keys %{$node2_ref->get_terminal_elements} : $node2;
    }

    if ($check_node_ref) {
        $label_hash2 = $check_node_ref->get_cached_value ('LABEL_HASH') ;
    }
    if (not $label_hash2) {
        $el2_list = [];
        push @$el2_list,
            $check_node_ref
            ? keys %{$check_node_ref->get_terminal_elements}
            : $check_node;
    }

    my $analysis_args = $self->get_param('ANALYSIS_ARGS');
    my $results = $indices_object->run_calculations(
        %args,
        %$analysis_args,
        element_list1   => $el1_list,
        element_list2   => $el2_list,
        label_hash1     => $label_hash1,
        label_hash2     => $label_hash2,
    );

    if ($cache_abc) {
        #  dodgy way of getting at them - what if we have calc_abc and calc_abc3 as deps?
        my $abc = {};
        my $as_results_from = $indices_object->get_param('AS_RESULTS_FROM');
        foreach my $calc_abc_type (qw /calc_abc3 calc_abc2 calc_abc/) {
            if (exists $as_results_from->{$calc_abc_type}) {
                $abc = $as_results_from->{$calc_abc_type};
                last;
            }
        }

        #  use cache unless told not to
        if (not defined $label_hash2 and defined $check_node_ref) {
            $check_node_ref->set_cached_value (
                LABEL_HASH => $abc->{label_hash2}
            );
        }
        if (not defined $label_hash1) {
            if (defined $node1_ref) {
                $node1_ref->set_cached_value (
                    $node1_2_cache_name => $abc->{label_hash1}
                );
            }
            if (defined $node2_ref) {
                $node2_ref->set_cached_value (
                    $node2_1_cache_name => $abc->{label_hash1});
            }
        }
    }

    my %r = (value => $results->{$index});

    #  run any local post_calcs - no these are done in run_calculations
    #$indices_object->run_postcalc_locals;

    return wantarray ? %r : \%r;
}

sub run_linkage {  #  rebuild the similarity matrices using the linkage function
    my $self = shift;
    my %args = @_;
    croak "one of the nodes not specified\n"
        if ! (defined $args{node1} and defined $args{node2} and defined $args{new_node_name});
    my $node1 = $args{node1};
    my $node2 = $args{node2};
    my $new_node = $args{new_node_name};  #  don't calculate linkages to new node

    my $linkage_function = $args{linkage_function} || $PARAMS{DEFAULT_LINKAGE};

    my $shadow_matrix   = $self->get_shadow_matrix;
    my $matrix_array    = $self->get_matrices_ref;
    my $current_mx_iter = $self->get_param ('CURRENT_MATRIX_ITER');

    my $new_node_ref = $self->get_node_ref (node => $new_node);
    my $nodes_under_new = $new_node_ref->get_all_descendents;

    #  generate the neighbour set for the new node
    foreach my $mx_iter ($current_mx_iter .. $#$matrix_array) {
        my $nbr_matrix = $self->get_nbr_matrix_ref (iter => $mx_iter);  #  hash of neighbours

        #  skip if this pair isn't in this matrix
        my $nbrs_node1 = $nbr_matrix->{$node1} || {};
        #next if ! defined $nbrs_node1;
        my $nbrs_node2 = $nbr_matrix->{$node2} || {};
        #next if ! defined $nbrs_node2;

        my %joint_nbrs = (%$nbrs_node1, %$nbrs_node2);
        next if ! scalar keys %joint_nbrs;  #  there were no neighbours

        #  don't consider those that are already merged under us
        delete @joint_nbrs{keys %$nodes_under_new};

        $nbr_matrix->{$new_node} = \%joint_nbrs;
    }

    my $matrix_with_elements = $shadow_matrix || $matrix_array->[0];

    #  Now we need to loop over the respective nodes across
    #  the matrices and merge as appropriate.
    #  The sort guarantees same order each time.
    CHECK_NODE:         
    foreach my $check_node (sort $matrix_with_elements->get_elements_as_array) {  

        #  skip the mergees
        next if $check_node eq $node1 || $check_node eq $node2;

        #  skip if we don't have both pairs check node with node1 and node2
        next if !(
            $matrix_with_elements->element_pair_exists (
                element1 => $check_node,
                element2 => $node1,
            )
            &&
            $matrix_with_elements->element_pair_exists (
                element1 => $check_node,
                element2 => $node2,
            )
        );  

        my %values = $self->$linkage_function (
            node1           => $node1,
            node2           => $node2,
            compare_node    => $check_node,
            matrix          => $matrix_with_elements,
        );
        if ($shadow_matrix) {
            $shadow_matrix->add_element  (
                element1    => $new_node,
                element2    => $check_node,
                value       => $values{value},
            );
        }

        #  add those values that are now nbrs
        my $check_node_ref
            = $self->get_node_ref (node => $check_node);

        my $check_node_elements
            = defined $check_node_ref
                ? $check_node_ref->get_terminal_elements
                : {$check_node => 1};

        #  work from the current mx forwards
        MX_ITER:
        foreach my $mx_iter ($current_mx_iter .. $#$matrix_array) {
            my $mx = $matrix_array->[$mx_iter];

            #  If $check_node is a neighbour of the new node then we need to
            #       add it to the current matrix if it is not already there.
            #  We get the value from the shadow matrix.

            my $nbr_mx  #  hash of neighbours
                = $self->get_nbr_matrix_ref (iter => $mx_iter);  

            my $count;
            my %nbrs;

            if ($nbr_mx) {
                %nbrs = %{$nbr_mx->{$new_node}};  #  make a dereferenced copy
                $count = scalar keys %nbrs;
                delete @nbrs{keys %$check_node_elements};
            }

            #  if no nbr_mx or we are a neighbour
            if (!defined $nbr_mx || $count != scalar keys %nbrs) {  
                #  we had a deletion so check_node is a neighbour of new_node

                my $exists = $mx->element_pair_exists (
                    element1 => $new_node,
                    element2 => $check_node
                );
                #  get it from the shadow matrix, which we calculated above
                if (! $exists) {
                    $mx->add_element (
                        element1    => $new_node,
                        element2    => $check_node,
                        value       => $values{value},
                    );
                }
            }
        }
    }

    #  forget these nodes ever existed
    #  currently inefficient as we just looped over them all
    #  and should be able to do it there
    if ($shadow_matrix) {
        $self->delete_links_from_matrix (
            %args,
            matrix => $shadow_matrix,
        );
    }

    foreach my $mx (@$matrix_array) {
        #  forget this pair ever existed
        $self->delete_links_from_matrix (
            %args,
            matrix => $mx,
        );
    }

    return 1;
}

sub delete_links_from_matrix {
    my $self = shift;
    my %args = @_;
    croak "one of the elements not specified\n"
        if ! defined $args{node1} || ! defined $args{node2};
    my $element1 = $args{node1};
    my $element2 = $args{node2};

    #  remove elements1&2 entries from the matrix
    my $matrix = $args{matrix} || $self->get_matrix_ref;

    my $compare_nodes = $args{compare_nodes} || $matrix->get_elements_as_array;
    my $expected = 2 * scalar @$compare_nodes;  #  we expect two deletions per comparison
    #print "\n";  #  for debug

    #  clean up links from compare_nodes to elements1&2
    my $deletion_count = 0;
    foreach my $check_element (sort @$compare_nodes) {
        $deletion_count += $matrix->delete_element (element1 => $check_element, element2 => $element1);
            #|| print "element1 => $check_element, element2 => $element1\n";
        $deletion_count += $matrix->delete_element (element1 => $check_element, element2 => $element2);
            #|| print "element1 => $check_element, element2 => $element1\n";
    }

    return $expected - $deletion_count;
}

#  get a list of the all the publicly available linkages.
sub get_linkage_functions {
    my $self = shift;

    my $tree = mro::get_linear_isa(blessed ($self) || __PACKAGE__);
    my $syms = Devel::Symdump->rnew(@$tree);

    my @linkages;

    foreach my $linkage (sort $syms->functions) {
        next if $linkage !~ /^.*::link_/;
        $linkage =~ s/(.*::)*//;  #  get the function name without package context -these are called using inheritance
        #print "LINKAGE IS $linkage\n";
        push @linkages, $linkage;
    }

    return wantarray ? @linkages : \@linkages;
}

#  calculate one or more spatial indices for the terminal elements in this node
sub sp_calc {  
    my $self = shift;
    my %args = @_;

    my $bd = $self->get_param('BASEDATA_REF');
    croak "No BaseData ref\n" if not defined $bd;

    my $indices_object = Biodiverse::Indices->new(BASEDATA_REF => $bd);

    if (! exists $args{calculations}) {
        if (defined $args{analyses}) {
            warn "Use of argument 'analyses' is deprecated from version 0.13\n"
                 . "Use argument 'calculations' instead.";
            $args{calculations} = $args{analyses};
        }
        else {
            $args{calculations} = $indices_object->get_calculations;
        }
    }

    # run some checks and get the valid analyses
    my $use_list_count = 1;
    $indices_object->get_valid_calculations (
        %args,
        use_list_count => $use_list_count,
    );

    #  drop out if we have none to do
    return if $indices_object->get_valid_calculation_count == 0;  

    delete $args{calculations};  #  saves passing it onwards when we call the calculations
    delete $args{analyses};      #  for backwards compat

    #  NEED TO STORE A PARAMETER WITH ALL THE ARGS ETC for repeatability?

    print "[CLUSTER] sp_calc Running "
        . (join (q{ }, sort keys %{$indices_object->get_valid_calculations_to_run}))
        . "\n";

    $indices_object->run_precalc_globals(%args);

    local $| = 1;  #  write to screen as we go
    my $toDo = $self->get_node_count;
    my ($count, $printedProgress) = (0, -1);
    my $tree_name = $self->get_param ('NAME');

    print "[CLUSTER] Progress (% of $toDo nodes):     ";
    my $progress_bar = Biodiverse::Progress->new();

    #  loop though the nodes and calculate the outputs
    while ((my $name, my $node) = each %{$self->get_node_hash}) {
        $count ++;

        $progress_bar->update (
            "Cluster spatial analysis\n"
            . "$tree_name\n(node $count / $toDo)",
            $count / $toDo,
        );

        my %elements = (element_list1 => [keys %{$node->get_terminal_elements}]);

        my %sp_calc_values = $indices_object->run_calculations(%args, %elements);

        foreach my $key (keys %sp_calc_values) {
            if (ref($sp_calc_values{$key}) =~ /ARRAY|HASH/) {
                $node->add_to_lists ($key => $sp_calc_values{$key});
                delete $sp_calc_values{$key};
            }
        }
        $node->add_to_lists (SPATIAL_RESULTS => \%sp_calc_values);

        #  run any local post_calcs - no these are done in run_calculations
        #$indices_object->run_postcalc_locals (%args);
    }

    #  run any global post_calcs
    $indices_object->run_postcalc_globals (%args);

    return 1;
}

sub get_embedded_tree {
    my $self = shift;

    my $args = $self->get_param ('ANALYSIS_ARGS');

    return $args->{tree_ref} if exists $args->{tree_ref};

    return;
}

sub get_embedded_matrix {
    my $self = shift;

    my $args = $self->get_param ('ANALYSIS_ARGS');

    return $args->{matrix_ref} if exists $args->{matrix_ref};

    return;
}

sub max {
    return $_[0] > $_[1] ? $_[0] : $_[1];
}

sub min {
    return $_[0] < $_[1] ? $_[0] : $_[1];
}

1;

__END__

=head1 NAME

Biodiverse::Cluster

=head1 SYNOPSIS

  use Biodiverse::Cluster;
  $object = Biodiverse::Cluster->new();

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
