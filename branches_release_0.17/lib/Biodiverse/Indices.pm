package Biodiverse::Indices;

#  package containing the various indices calculated from a Biodiverse::BaseData object
#  generally they are called from a Biodiverse::Spatial or Biodiverse::Cluster object

use Carp;
use strict;
use warnings;
#use diagnostics;
use Devel::Symdump;
use Data::Dumper;
use Scalar::Util qw /blessed weaken/;
use English ( -no_match_vars );
#use Class::ISA;
use MRO::Compat;

#$Data::Dumper::Sortkeys = 1;  #  sort the keys dumped by get_args
#$Data::Dumper::Indent = 1;    #  reduce the indentation used by Dumper in get_args

our $VERSION = '0.17';

my $EMPTY_STRING = q{};

#  The Biodiverse::Indices::* modules are the indices themselves 
use base qw {
    Biodiverse::Indices::Indices
    Biodiverse::Indices::Numeric_Labels
    Biodiverse::Indices::IEI
    Biodiverse::Indices::Hierarchical_Labels
    Biodiverse::Indices::Phylogenetic
    Biodiverse::Indices::Matrix_Indices
    Biodiverse::Indices::Endemism
    Biodiverse::Indices::Rarity
    Biodiverse::Indices::LabelProperties
    Biodiverse::Indices::GroupProperties
    Biodiverse::Common
};


sub new {
    my $class = shift;
    my %args = @_;
    
    my $self = bless {}, $class;
    
    
    my %PARAMS = (  #  default params
        TYPE            => 'INDICES',
        OUTSUFFIX       => 'bis',
        OUTSUFFIX_YAML  => 'biy',
    );
    $self -> set_params (%PARAMS, %args);
    $self -> set_default_params;  #  load any user overrides

    $self->reset_results(global => 1);

    #  avoid memory leak probs with circular refs to parents
    #  ensures children are destroyed when parent is destroyed
    $self->weaken_basedata_ref;  
    
    return $self;
}

sub reset_results {
    my $self = shift;
    my %args = @_;
    
    if ($args{global}) {
        $self ->set_param (AS_RESULTS_FROM => {});
    }
    else {
        #  need to loop through the precalc hash and delete any locals in it
        my $valids = $self->get_param('VALID_CALCULATIONS');
        my $pre_calcs = $valids->{pre_calc_to_run};
        my $as_args_from = $self->get_param('AS_RESULTS_FROM');
        delete @{$as_args_from}{keys %$pre_calcs};
    }

    return;
}


###########################
#
#   Methods to get valid calculations depending on conditions

#  get a list of the all the publicly available calculations.
sub get_calculations {  
    my $self = shift;

    my $tree = mro::get_linear_isa(blessed ($self));

    my $syms = Devel::Symdump->rnew(@$tree);
    my %calculations;
    my @list = sort $syms -> functions;
    foreach my $calculations (@list) {
        next if $calculations !~ /^.*::calc_/;
        next if $calculations =~ /calc_abc\d?$/;
        my ($source_module, $sub_name) = $calculations =~ /((?:.*::)*)(.+)/;
        $source_module =~ s/::$//;
        #print "ANALYSIS IS $calculations\n";
        my $ref = $self -> get_args (sub => $sub_name);
        #$ref->{source_module} = $source_module;
        push @{$calculations{$ref->{type}}}, $sub_name;
        print Data::Dumper::Dump ($ref) if ! defined $ref->{type};
    }

    return wantarray ? %calculations : \%calculations;
}

sub get_calculations_as_flat_hash {
    my $self = shift;
    my $list = $self -> get_calculations;
    return $self -> get_list_as_flat_hash (list => $list);
}

#  needed for GUI help and so forth
sub get_calculation_metadata_as_wiki {
    my $self = shift;

    my %calculations = $self -> get_calculations (@_);

    #  the html version
    my @header = (  
        #"Name",
        #"Analysis description",
        #"Subroutine",
        'Index #',
        'Index',
        'Index description',
        'Valid cluster metric?',
        'Minimum number of neighbour sets',
        'Formula',
        'Reference',
    );

    foreach my $text (@header) {
        $text = "*$text*";
    }

    my %hash;

    #my @place_holder = (undef, undef);

    my %indices;
    my %calculation_hash;
    foreach my $type (sort keys %calculations) {
        foreach my $calculations (@{$calculations{$type}}) {
            my $ref = $self -> get_args (sub => $calculations);
            $ref->{analysis} = $calculations;
            $calculation_hash{$type}{$calculations} = $ref;
        }
    }

    #my $sort_by_type_then_name = sub {   $a->{type} cmp $b->{type}
    #                                  || $a->{name} cmp $b->{name}
    #                                  };

    my $html;

    my %done;
    my $count = 1;
    my $SPACE = q{ };

    my $gadget_start_text
        #= q{<wiki:gadget url="http://mathml-gadget.googlecode.com/svn/trunk/mathml-gadget.xml" border="0" up_content="};
        = '<img src="http://latex.codecogs.com/png.latex?';
    my $gadget_end_text
        #= q{"/>};
        = ' />';

    #loop through the types
    BY_TYPE:
    foreach my $type (sort keys %calculation_hash) {
        $html .= "==$type==";

        my $type_ref = $calculation_hash{$type};

        BY_NAME:  #  loop through the names
        foreach my $ref (sort {$a->{name} cmp $b->{name}} values %$type_ref) {

            #my $starter = $ref->{name};
            #print $starter . "\n";

            $html .= "\n \n \n";
            $html .= "\n \n  ===$ref->{name}===\n \n";
            $html .= "*Description:*   $ref->{description}\n\n";
            $html .= "*Subroutine:*   $ref->{analysis}\n\n";
            #$html .= "<p><b>Module:</b>   $ref->{source_module}</p>\n";  #  not supported yet
            if ($ref->{reference}) {
                $html .= "*Reference:*   $ref->{reference}\n \n\n";
            }

            my $formula = $ref->{formula};
            croak 'Formula is not an array'
              if defined $formula and not (ref $formula) =~ /ARRAY/;

            if ($formula and (ref $formula) =~ /ARRAY/) {
                my $formula_url;
                my $iter = 0;

                FORMULA_ELEMENT_OVERVIEW:
                foreach my $element (@{$formula}) {
                    if (! defined $element
                        || $element eq q{}) {
                        $iter ++;
                        next FORMULA_ELEMENT_OVERVIEW;
                       }

                    if ($iter % 2) {
                        #$formula .= "\n";
                        if ($element =~ /^\s/) {
                            $formula_url .= $element;
                        }
                        else {
                            $formula_url .= " $element";
                        }
                    }
                    else {
                        #$formula .= "\n";
                        $formula_url .= $gadget_start_text;
                        $formula_url .= $element;
                        $formula_url .= qq{%.png" title="$element"};
                        $formula_url .= $gadget_end_text;
                    }
                    $iter++;
                }

                $html .= "*Formula:*\n   $formula_url\n\n";
            }

            my @table;
            push @table, [@header];

            my $i = 0;
            my $uses_reference = 0;
            my $uses_formula = 0;
            foreach my $index (sort keys %{$ref->{indices}}) {
                
                my $index_hash = $ref->{indices}{$index};
                
                #  repeated code from above - need to generalise to a sub
                my $formula_url;
                my $formula = $index_hash->{formula};
                croak "Formula for $index is not an array"
                  if defined $formula and not ((ref $formula) =~ /ARRAY/);

                if (1 and $formula and (ref $formula) =~ /ARRAY/) {
                    
                    $uses_formula = 1;
                    
                    my $iter = 0;
                    foreach my $element (@{$index_hash->{formula}}) {
                        if ($iter % 2) {
                            if ($element =~ /^\s/) {
                                $formula_url .= $element;
                            }
                            else {
                                $formula_url .= " $element";
                            }
                        }
                        else {
                            $formula_url .= $gadget_start_text;
                            $formula_url .= $element;
                            $formula_url .= qq{%.png" title="$element"};
                            $formula_url .= $gadget_end_text;
                        }
                        $iter++;
                    }
                }
                $formula_url .= $SPACE;
                
                my @line;
                
                push @line, $count;
                push @line, $index;
                
                my $description = $index_hash->{description} || $SPACE;
                $description =~ s{\n}{ }gmo;  # purge any newlines
                push @line, $description;
                
                push @line, $index_hash->{cluster} ? "cluster metric" : $SPACE;
                push @line, $index_hash->{uses_nbr_lists} || $ref->{uses_nbr_lists} || $SPACE;
                push @line, $formula_url;
                my $reference = $index_hash->{reference};
                if (defined $index_hash->{reference}) {
                    $uses_reference = 1;
                    $reference =~s{\n}{ }gmo;
                }
                push @line, $reference || $SPACE;

                push @table, \@line;

                $i++;
                $count ++;
            }

            #  remove the reference col if none given
            if (! $uses_reference) {
                foreach my $row (@table) {
                    pop @$row;
                }
                
            }

            #  and remove the formula also if need be
            if (! $uses_formula) {
                foreach my $row (@table) {
                    splice @$row, 5, 1;
                }
            }


            #$html .= $table;
            
            foreach my $line (@table) {
                my $line_text;
                $line_text .= q{|| };
                $line_text .= join (q{ || }, @$line);
                $line_text .= q{ ||};
                $line_text .= "\n";
                
                my $x = grep {! defined $_} @$line;
                
                $html .= $line_text;
            }

            $html .= "\n\n";
            
        }
    }

    return $html;
}

sub get_dependency_tree { 
    my $self = shift;
    my %args = @_;
    my $type = $args{type};
    croak "Argument 'type' not specified\n" if not defined $type;
    #croak "Argument 'calculations' not specified\n"
    #    if not defined $args{calculations};

    #  convert it to a hash as needed
    my %calculations;
    my $calcs = $args{calculations};
    if (defined $calcs) {
        my $ref = ref $calcs;
        if ($ref =~ /ARRAY/) {
            @calculations{@$calcs} = (1) x scalar @$calcs;
        }
        elsif ($ref =~ /HASH/) {
            %calculations = %$calcs;
        }
        else {
            $calculations{$calcs} = $calcs;
        }
    }


    my %pre_calc_hash;
    foreach my $calculations (keys %calculations) {
        my $got_args = $self->get_args (sub => $calculations);

        my $pc = $got_args->{$type};  # normally pre_calc or pre_calc_global
        next if ! defined $pc;

        my $ref = ref $pc;
        if (! $ref) {
            $pc = [$pc];
        }
        elsif ($ref =~ /HASH/) {
            $pc = [keys %$pc] ;
        }

        next if ! scalar @$pc;   #  skip if nothing there - redundant?

        foreach my $pre_c (@$pc) {
            next if ! defined $pre_c;

            my $next_level
                = $self->get_dependency_tree (%args, calculations => [$pre_c]);

            $pre_calc_hash{$calculations}{$pre_c}
                = defined $next_level->{$pre_c}
                    ? $next_level->{$pre_c}  #  flatten the next_level hash a little when assigning to this level
                    : 1;  #  default to a one
        }
    }

    return wantarray ? %pre_calc_hash : \%pre_calc_hash;
}

sub get_pre_calc_global_hash_by_calculation {  # redundant?
    my $self = shift;

    my $pre_calc = $self->get_dependency_tree (@_);
    my %calculations = $self->get_hash_inverted (list => $pre_calc);  #  NEED CHANGING
    return wantarray ? %calculations : \%calculations;
}

#  get a hash of which calculations require 1 or 2 sets of spatial paramaters or other lists
sub get_uses_nbr_lists_count {
    my $self = shift;
    my %list = $self->get_calculations_as_flat_hash;
    my %list2;

    while ((my $calculations, my $null) = each %list) {
        my $args = $self->get_args (sub => $calculations);
        next if ! exists $args->{uses_nbr_lists};
        $list2{$args->{uses_nbr_lists}}{$calculations}++;
    }

    return wantarray ? %list2 : \%list2;
}

sub get_indices_uses_lists_count {
    my $self = shift;
    my %args = @_;

    my $list = $args{calculations} || $self -> get_calculations;
    my %list = $self -> get_list_as_flat_hash (list => $list);

    my %indices;
    foreach my $calculations (keys %list) {
        my $ref = $self -> get_args (sub => $calculations);
        foreach my $index (keys %{$ref->{indices}}) {
            $indices{$index} = $ref->{indices}{$index}{uses_nbr_lists};
        }
    }

    return wantarray ? %indices : \%indices;
}

#  get a list of indices in a set of calculations
sub get_indices {
    my $self = shift;

    return $self -> get_index_source_hash (@_);    
}

sub get_index_source {  #  return the source sub for an index
    my $self = shift;
    my %args = @_;
    return undef if ! defined $args{index};

    my $source = $self -> get_index_source_hash;
    my @tmp = %{$source->{$args{index}}}; 
    return $tmp[0];  #  the hash key is the first value.  Messy, but it works.
}

#  get a hash of indices arising from these calculations (keys),
#   with the analysis as the value
sub get_index_source_hash { 
    my $self = shift;
    my %args = @_;
    my $list = $args{calculations} || $self -> get_calculations_as_flat_hash;
    my %list2;

    foreach my $calculations (keys %$list) {
        my $args = $self -> get_args (sub => $calculations);
        foreach my $index (keys %{$args->{indices}}) {
            $list2{$index}{$calculations}++;
        }
    }

    return wantarray ? %list2 : \%list2;
}

sub get_required_args {  #  return a hash of those methods that require a parameter be specified
    my $self = shift;
    my %args = @_;
    my $list = $args{calculations} || $self -> get_calculations_as_flat_hash;
    my %params;

    foreach my $calculations (keys %$list) {
        my $ref = $self -> get_args (sub => $calculations);
        if (exists $ref->{required_args}) {  #  make it a hash if it not already
            if ((ref $ref->{required_args}) =~ /ARRAY/) {
                $ref->{required_args} = $self -> array_to_hash_keys (
                    list => $ref->{required_args},
                );
            }
            elsif (not ref $ref->{required_args}) {
                $ref->{required_args} = {$ref->{required_args} => 1};
            }
            $params{$calculations} = $ref->{required_args};
        }
    }

    return wantarray ? %params : \%params;
}

sub get_valid_cluster_indices {
    my $self = shift;
    my %args = @_;
    my $list = $args{calculations} || $self -> get_calculations_as_flat_hash;

    my %indices;
    foreach my $calculations (keys %$list) {
        my $ref = $self -> get_args (sub => $calculations);
        foreach my $index (keys %{$ref->{indices}}) {
            if ($ref->{indices}{$index}{cluster}) {
                my $description = $ref->{indices}{$index}{description};
                $indices{$index} = $description;
            }
        }
    }

    return wantarray ? %indices : \%indices;
}

sub get_valid_region_grower_indices {
    my $self = shift;
    my %args = @_;
    my $list = $args{calculations} || $self -> get_calculations_as_flat_hash;

    my %indices;
    foreach my $calculations (keys %$list) {
        my $ref = $self -> get_args (sub => $calculations);
        INDEX:
        foreach my $index (keys %{$ref->{indices}}) {
            my $hash_ref = $ref->{indices}{$index};
            next INDEX
              if  exists $hash_ref->{lumper}
                 and not $hash_ref->{lumper};
            next INDEX if $hash_ref->{cluster};
            next INDEX
              if defined $hash_ref->{type}
                 and $hash_ref->{type} eq 'list';
            
            my $description = $ref->{indices}{$index}{description};
            $indices{$index} = $description;
        }
    }

    return wantarray ? %indices : \%indices;
}

#  collect all the pre-reqs and so forth for a selected set of calculations
sub get_valid_calculations {
    my $self = shift;
    my %args = @_;
    my $use_list_count = $args{use_list_count};

    croak "use_list_count argument not specified\n"
        if ! defined $use_list_count;

    #  get all the calculations
    my %all_poss_calculations = $self -> get_calculations_as_flat_hash;

    #  flatten the requested calculations - simplifies checks lower down
    my $calculations_to_run
        = $self->get_list_as_flat_hash (list => $args{calculations});
    my %calculations_to_check = %$calculations_to_run;

    my @types = qw /pre_calc pre_calc_global post_calc post_calc_global/;

    my %results;
    foreach my $type (@types) {  #  get the pre_calc stuff
        #  using %calculations_to_check in the dependency tree means
        #  we get the global precalcs for any local precalcs
        my $tree = $self->get_dependency_tree (
            calculations => \%calculations_to_check,
            type         => $type,
        );

        next if ! keys %$tree;

        my %pre_calc_hash;

        ANALYSIS_IN_TREE:
        foreach my $calculations (keys %$tree) {  #  need to keep the branches here

            next ANALYSIS_IN_TREE if ! scalar keys %{$tree->{$calculations}};

            my %hash = $self -> get_list_as_flat_hash (
                list          => $tree->{$calculations},
                keep_branches => 1,
            );
            @{$pre_calc_hash{$calculations}}{keys %hash} = values %hash;
        }
        $results{$type . '_tree'} = $tree;

        #  now we get rid of the 1st level branches
        #  - they are the calculations, not the pre_calcs
        my $flattened = $self -> get_list_as_flat_hash (
            list => \%pre_calc_hash,
        );
        $results{$type . '_to_run'} = $flattened;
        #  add these to the list to check
        @calculations_to_check{keys %$flattened} = values %$flattened;  
    }

    #  Now we go through the calc types and get any of their globals,
    #  adding them to the pre_calc_global checks.
    #  We only do pre_calc_global checks as 
    #  globals should not depend on locals
    #  and post_calcs should not depend on local pre_calcs.
    my $tree = {};
    foreach my $calc_type (@types) {
        #  skip the globals themselves
        next if $calc_type eq 'pre_calc_global';

        my $sub_tree = $self -> get_dependency_tree (
            calculations => $results{$calc_type . '_to_run'},
            type         => 'pre_calc_global'
        );
        @{$tree}{keys %$sub_tree} = values %$sub_tree;
    }

    if (keys %$tree) {
        my %pre_calc_hash;
        foreach my $pc (keys %$tree) {    #  need to keep the branches here
            next if ! scalar keys %{$tree->{$pc}};
            my %hash = $self -> get_list_as_flat_hash (
                list          => $tree->{$pc},
                keep_branches => 1,
            );
            @{$pre_calc_hash{$pc}}{keys %hash} = values %hash;
        }
        #  add these as a slice
        @{$results{pre_calc_global_tree}}{keys %$tree} = values %$tree;  
        #  now we get rid of the 1st level branches
        #  - they are the pre_calcs which are already registered
        #  in the pre_calc section
        my $flattened = $self -> get_list_as_flat_hash (
            list => \%pre_calc_hash,
        );
        @{$results{pre_calc_global_to_run}}{keys %$flattened}
            = values %$flattened;
        @calculations_to_check{keys %$flattened}
            = values %$flattened;  #  add these to the list to check
    }

    my %uses_lists_count  #  just check the ones to run
        = $self -> get_uses_nbr_lists_count (calculations => $calculations_to_run);  
    my %required_args     #  need to check all of them
        = $self -> get_required_args (calculations => \%calculations_to_check);  

    print "[INDICES] CHECKING ANALYSES\n";
    my %deleted;

    CHECK_ANALYSIS:
    foreach my $calculations (keys %calculations_to_check) {
        #  if $calculations has a required arg, check if it has been specified
        if (exists $required_args{$calculations}) {
            foreach my $rqdArg (keys %{$required_args{$calculations}}) {
                if (! defined $args{$rqdArg}) {
                    warn "[INDICES] WARNING: $calculations missing required "
                         . "parameter $rqdArg, "
                         . "dropping calculation and any dependencies\n";
                    delete $calculations_to_run->{$calculations};
                    $deleted{$calculations}++;
                    next CHECK_ANALYSIS;
                }
            }
        }

        #  check $calculations exists as a valid analysis,
        #  unless it is a pre_calc (catcher for non-GUI systems)
        if (exists ($calculations_to_run->{$calculations})
            and ! (exists $all_poss_calculations{$calculations})) {
                warn "[INDICES] WARNING: $calculations not in the valid list, dropping it\n";
                delete $calculations_to_run->{$calculations};
                $deleted{$calculations}++;
                next CHECK_ANALYSIS;
        }

        #  skip analysis if there are insufficient params specified ---CHEATING---
        if ($use_list_count == 1 && exists $uses_lists_count{2}{$calculations}) {
            warn "[INDICES] WARNING: insufficient spatial params for $calculations, dropping calculation\n";
            delete $calculations_to_run->{$calculations};
            $deleted{$calculations}++;
            next CHECK_ANALYSIS;
        }
    }

    #  now we go through and delete any calculations whose pre_calcs have been deleted
    foreach my $calculations (keys %$calculations_to_run) {
        foreach my $type (@types) {
            next if ! exists $results{$type . '_tree'}{$calculations};
            #  get the flattened list of pre_calcs for this analysis
            my %pre_c = $self -> get_list_as_flat_hash (
                list => $results{$type . '_tree'}{$calculations},
                keep_branches => 1,
            );

            my $length = scalar keys %pre_c;
            delete @pre_c{keys %deleted};

            #  next if none of the pre_calcs were deleted
            next if $length == scalar keys %pre_c;  

            #  we need to clean things up now
            print "[INDICES] WARNING: dependency/ies for $calculations invalid, dropping calculation\n";
            delete $calculations_to_run->{$calculations};
            $deleted{$calculations}++;
        }
    }

    #  cleanup the redundant calc hashes - these are still indexed by their calculations
    foreach my $type (@types) {
        delete @{$results{$type . '_to_run'}}{keys %deleted};
        delete @{$results{$type . '_tree'}}{keys %deleted};
    }

    #  now loop over the calcs (local pre&post, global post)
    #  and add their globals to their dependency tree
    foreach my $calc_type (@types) {
        #  skip the globals themselves
        next if $calc_type eq 'pre_calc_global';

        my $tree          = $results{$calc_type . '_tree'}     || {};
        my $to_run        = $results{$calc_type . '_to_run'}   || {};
        my $global_tree   = $results{'pre_calc_global_tree'}        || {};
        my $global_to_run = $results{'pre_calc_global_to_run'} ||{};
        my %locals  = (%$tree, %$to_run);
        my %globals = (%$global_to_run, %$global_tree);
        

        foreach my $calc (keys %locals) {
            next if not exists $globals{$calc};
            while (my ($dep_calc, $dep_hash) = each %{$global_tree->{$calc}}) {
                $self->add_to_sub_hashes(
                    hash   => $tree,
                    key    => $calc,
                    values => {$dep_calc, $dep_hash},
                );
            }
        }
        #print "";
    }

    my $indices_to_clear = $self -> get_indices_to_clear (
        %args,
        calculations => $calculations_to_run
    );

    if (scalar keys %$indices_to_clear) {
        print '[INDICES] The following indices will not appear in the '
              . 'results due to insufficient spatial parameters: ';
        print join (q{ }, sort keys %$indices_to_clear) . "\n";
    }

    $results{required_args}    = \%required_args;
    $results{calculations_to_run}  = $calculations_to_run;
    $results{indices_to_clear} = $indices_to_clear;
    
    $self->set_param(VALID_CALCULATIONS => \%results);

    return wantarray ? %results : \%results;
}

sub add_to_sub_hashes {
    my $self = shift;
    my %args = @_;
    
    my $hash   = $args{hash};
    my $key    = $args{key};
    my $values = $args{values};

    while (my ($this_key, $this_value) = each %$hash) {
        my $reftype = ref($this_value);
        next if not $reftype =~ /HASH/;
        
        if ($this_key eq $key) {    
            @$this_value{keys %$values} = values %$values;
        }
        else {  #  recurse
            $self->add_to_sub_hashes(
                %args,
                hash => $this_value,
            );
        }
    }

    return;
}

sub get_valid_calculations_to_run {
    my $self = shift;
    
    my $valid_calcs = $self->get_param('VALID_CALCULATIONS');
    my $calcs = $valid_calcs->{calculations_to_run};
    
    return wantarray ? %$calcs : $calcs;
}

sub get_valid_calculation_count {
    my $self = shift;
    my $calcs = $self->get_valid_calculations_to_run;
    return scalar keys %$calcs;
}

sub get_indices_to_clear_for_calcs {
    my $self = shift;

    my $valid_calcs = $self->get_param('VALID_CALCULATIONS');
    my $indices_to_clear = $valid_calcs->{indices_to_clear};

    return wantarray ? %$indices_to_clear : $indices_to_clear;
}

sub get_required_args_for_calcs {
    my $self = shift;
    
    my $valid_calcs = $self->get_param('VALID_CALCULATIONS');
    
    return $valid_calcs->{required_args};
}

sub get_pre_calc_global_tree {
    my $self = shift;
    
    my $valid_calcs = $self->get_param('VALID_CALCULATIONS');
    
    return $valid_calcs->{pre_calc_global_tree};
}

sub get_post_calc_global_tree {
    my $self = shift;
    
    my $valid_calcs = $self->get_param('VALID_CALCULATIONS');
    
    return $valid_calcs->{post_calc_global_tree};
}

sub get_pre_calc_local_tree {
    my $self = shift;
    
    my $valid_calcs = $self->get_param('VALID_CALCULATIONS');
    
    return $valid_calcs->{pre_calc_tree};
}

sub get_post_calc_local_tree {
    my $self = shift;
    
    my $valid_calcs = $self->get_param('VALID_CALCULATIONS');
    
    return $valid_calcs->{post_calc_tree};
}

#  indices where we don't have enough lists, but where the rest of the analysis can still run
#  these can be cleared from any results
#  need to rename sub
sub get_indices_to_clear {  #  should really accept a list of calculations as an arg
    my $self = shift;
    my %args = @_;
    my $use_list_count = $args{use_list_count} || croak "use_list_count argument not specified\n";

    my %hash = $self -> get_indices_uses_lists_count (%args);

    foreach my $index (keys %hash) {
        delete $hash{$index} if ! defined $hash{$index} || $hash{$index} <= $use_list_count;
    }

    return wantarray ? %hash : \%hash;
}

#  Run the dependency tree,
#  but don't do the top level as it's the local calc in all cases
sub run_dependency_tree {
    my $self = shift;
    my %args = @_;

    my $tree = $args{dependency_tree};

    my %results;

    foreach my $calc (keys %$tree) {
        my $sub_results = $self->_run_dependency_tree(
            %args,
            dependency_tree => $tree->{$calc},
        );
        @results{keys %$sub_results} = values %$sub_results; # do we need this?
    }

    return wantarray ? %results : \%results;
}

#  run a series of dependent calculations, starting from the bottom.
sub _run_dependency_tree {   
    my $self = shift;
    my %args = @_;

    my $tree = $args{dependency_tree} || {};
    delete $args{dependency_tree};
    my $as_results_from = $self->get_param('AS_RESULTS_FROM');

    #  Now we run the calculations at this level.
    #  We also keep track of what has been run
    #  to avoid repetition through multiple dependencies.
    my %results;
    foreach my $calc (keys %$tree) {
        my $sub_results = {};
        if (exists $as_results_from->{$calc}) {  #  already cached, so just grab it
            $sub_results = $as_results_from->{$calc};
        }
        else {
            my $run_deps = ref ($tree->{$calc}) =~ /HASH/;  #  will this avoid a mem leak?
            #my $dep_results = {};
            #if ($run_deps) {  #  run its dependencies if necessary
            #    $dep_results = $self->_run_dependency_tree (
            #        %args,
            #        dependency_tree => $tree->{$calc},
            #    );
            #}
            my $dep_results = $run_deps
                ? $self->_run_dependency_tree (
                      %args,
                      dependency_tree => $tree->{$calc},
                  )
                : {};

            $sub_results = eval {
                $self->$calc (  
                    %args,
                    %$dep_results,
                );
            };
            croak $EVAL_ERROR if $EVAL_ERROR;
            $as_results_from->{$calc} = $sub_results;
        }
        @results{keys %$sub_results} = values %$sub_results;
    }

    #  return results for this sub
    return wantarray ? %results : \%results;  
}

sub run_calculations {
    my $self = shift;
    my %args = @_;
    
    $self->reset_results;  #  clear any previous local results

    my $pre_calc_locals  = $self->run_precalc_locals (%args);
    
    my $pre_calc_local_tree  = $self->get_pre_calc_local_tree;
    my $pre_calc_global_tree = $self->get_pre_calc_global_tree;
    
    my $as_results_from  = $self->get_param('AS_RESULTS_FROM');
    
    my %calcs_to_run = $self->get_valid_calculations_to_run;
    
    my %results;  #  stores the results
    foreach my $calc (keys %calcs_to_run) {
        my %calc_results;
        #  Access any results done as a pre_calc.
        if (exists $as_results_from->{$calc}) {
            %calc_results = %{$as_results_from->{$calc}};
        }
        else {
            #print "ANALYSIS IS $analysis\n";
            my %pre_calc_local_args_to_use = 
                $self->get_args_for_calc_from_tree(
                    calculation => $calc,
                    dependency_tree => $pre_calc_local_tree,
                );
            my %pre_calc_global_args_to_use = 
                $self->get_args_for_calc_from_tree(
                    calculation => $calc,
                    dependency_tree => $pre_calc_global_tree,
                );

            %calc_results = $self->$calc (
                %args,
                %pre_calc_local_args_to_use,
                %pre_calc_global_args_to_use,
            );
        }
        @results{keys %calc_results} = values %calc_results;
    }

    $self->run_postcalc_locals (%args);

    #  remove those that are invalid
    my $indices_to_clear = $self->get_indices_to_clear_for_calcs;
    delete @results{keys %$indices_to_clear};

    return wantarray ? %results : \%results;
}

#  get the args for a calculation using its dependency tree
sub get_args_for_calc_from_tree {
    my $self = shift;
    my %args = @_;
    my $tree = $args{dependency_tree};
    my $calc = $args{calculation};
    my $as_results_from = $self->get_param('AS_RESULTS_FROM');

    return if    not exists $tree->{$calc}
              or not ref ($tree->{$calc}) =~ /HASH/;

    my $subs = $tree->{$calc};

    my %results;
    foreach my $sub_calc (keys %$subs) {
        my $sub_results = $as_results_from->{$sub_calc};
        @results{keys %$sub_results}
          = values %$sub_results;
    }

    return wantarray ? %results : \%results;
}

#  Run the global precalcs.
#  Should we use a caching system to call at first use of local?
#  Probably better to require an explicit call before running locals.
sub run_precalc_globals {
    my $self = shift;
    my %args = @_;

    my $results = $self->run_dependency_tree(
        %args,
        dependency_tree => $self->get_pre_calc_global_tree,
    );

    #$self->set_param(PRE_CALC_GLOBALS => $results);

    return wantarray ? %$results : $results;
}

#  run the local precalcs
sub run_precalc_locals {
    my $self = shift;
    my %args = @_;
    
    #my $pre_calc_globals = $self->get_param('PRE_CALC_GLOBALS');
    
    return $self->run_dependency_tree(
        %args,
        dependency_tree => $self->get_pre_calc_local_tree,
    );
}

#  run the local precalcs
sub run_postcalc_locals {
    my $self = shift;
    my %args = @_;
    
    return $self->run_dependency_tree(
        %args,
        dependency_tree => $self->get_post_calc_local_tree,
    );
}

#  run the local precalcs
sub run_postcalc_globals {
    my $self = shift;
    my %args = @_;
    
    return $self->run_dependency_tree(
        %args,
        dependency_tree => $self->get_post_calc_global_tree,
    );
}

#  for debugging purposes
#our $AUTOLOAD;
#sub AUTOLOAD {
#    return;
#}
#
#sub DESTROY {
#    my $self = shift;
#    #print "[INDICES] DESTROYING OBJECT " . ($self->get_param('NAME') || 'anonymous') . " $self \n";
#    #use Devel::Cycle;
#    
#    #my $cycle = find_cycle($self);
#    #if ($cycle) {
#    #    print STDERR "Cycle found: $cycle\n";
#    #}
#
#    #print $self->dump_to_yaml (data => $self);
#}


1;

__END__

=head1 NAME

Biodiverse::Indices

=head1 SYNOPSIS

  use Biodiverse::Indices;
  my $indices = Biodiverse::Indices->new;

=head1 DESCRIPTION

Indices handler for the Biodiverse system.
See L<http://code.google.com/p/biodiverse/wiki/Indices> for the list
of available indices.

=head1 METHODS

=over

=item NEED TO INSERT METHODS

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
