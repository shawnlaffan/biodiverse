package Biodiverse::Spatial;

use 5.010;
use strict;
use warnings;

use Carp;
use English qw { -no_match_vars };

use Data::Dumper;
use Scalar::Util qw /weaken blessed/;
use List::MoreUtils qw /firstidx lastidx/;
use List::Util 1.45 qw /first uniq/;
use Time::HiRes qw /time/;
use Ref::Util qw { :all };

our $VERSION = '2.99_003';

use Biodiverse::SpatialConditions;
use Biodiverse::SpatialConditions::DefQuery;
use Biodiverse::Progress;
use Biodiverse::Indices;



use parent qw /Biodiverse::BaseStruct/;

my $EMPTY_STRING = q{};



########################################################
#  Compare one spatial output object against another
#  Works only with lists generated from Indices
#  Creates new lists in the base object containing
#  counts how many times the base value was greater,
#  the number of comparisons,
#  and the ratio of the two.
#  This is designed for the randomisation procedure, but has more
#  general applicability

sub compare {
    my $self = shift;
    my %args = @_;

    #  make all numeric warnings fatal to catch locale/sprintf issues
    use warnings FATAL => qw { numeric };
    
    my $comparison = $args{comparison};
    croak "Comparison not specified\n" if not defined $comparison;
    
    my $result_list_pfx = $args{result_list_name};
    croak qq{Argument 'result_list_pfx' not specified\n}
        if ! defined $result_list_pfx;

    my $progress = Biodiverse::Progress->new();
    my $progress_text = 'Comparing '
                        . $self->get_param ('NAME')
                        . ' with '
                        . $comparison->get_param ('NAME')
                        . "\n";
    $progress->update ($progress_text, 0);

    my $bd = $self->get_param ('BASEDATA_REF');

    #  drop out if no elements to compare with
    my $e_list = $self->get_element_list;
    return 1 if not scalar @$e_list;


    my %base_list_indices = $self->find_list_indices_across_elements;
    $base_list_indices{SPATIAL_RESULTS} = 'SPATIAL_RESULTS';

    #  now we need to calculate the appropriate result list name
    # for example RAND25>>SPATIAL_RESULTS
    foreach my $list_name (keys %base_list_indices) {
        $base_list_indices{$list_name} = $result_list_pfx . '>>' . $list_name;
    }

    
    my $to_do = $self->get_element_count;
    my $i = 0;

    #  easy way of handling recycled lists
    my %done_base; 
    my %done_comp;
    
    my $recycled_results
      =    $self->get_param ('RESULTS_ARE_RECYCLABLE')
        && $comparison->get_param ('RESULTS_ARE_RECYCLABLE');
    #if ($recycled_results && exists $args{no_recycle}) {  #  mostly for debug 
    #    $recycled_results = $args{no_recycle};
    #}

    if ($recycled_results) {  #  set up some lists
        foreach my $list_name (keys %base_list_indices) {
            $done_base{$list_name} = {};
            $done_comp{$list_name} = {};
        }
    }    

    COMP_BY_ELEMENT:
    foreach my $element ($self->get_element_list) {
        $i++;

        $progress->update (
            $progress_text . "(element $i / $to_do)",
            $i / $to_do,
        );

        #  now loop over the list indices
        BY_LIST:
        while (my ($list_name, $result_list_name) = each %base_list_indices) {

            next BY_LIST
                if    $recycled_results
                   && $done_base{$list_name}{$element}
                   && $done_comp{$list_name}{$element};

            my $base_ref = $self->get_list_ref (
                element     => $element,
                list        => $list_name,
                autovivify  => 0,
            );
            my $comp_ref = $comparison->get_list_ref (
                element     => $element,
                list        => $list_name,
                autovivify  => 0,
            );

            next BY_LIST if ! $base_ref || ! $comp_ref; #  nothing to compare with...

            next BY_LIST if (is_arrayref($base_ref));

            my $results_ref = $self->get_list_ref (
                element => $element,
                list    => $result_list_name,
            );
    
            $self->compare_lists_by_item (
                base_list_ref     => $base_ref,
                comp_list_ref     => $comp_ref,
                results_list_ref  => $results_ref,
            );

            #  if results from both base and comp
            #  are recycled then we can recycle the comparisons
            if ($recycled_results) {
                my $nbrs = $self->get_list_ref (
                    element => $element,
                    list    => 'RESULTS_SAME_AS',
                );

                my $results_ref = $self->get_list_ref (
                    element => $element,
                    list    => $result_list_name,
                );

                BY_RECYCLED_NBR:
                foreach my $nbr (keys %$nbrs) {
                    $self->add_to_lists (
                        element           => $nbr,
                        $result_list_name => $results_ref,
                        use_ref           => 1,
                    );
                }
                my $done_base_hash = $done_base{$list_name};
                my $done_comp_hash = $done_comp{$list_name};
                @{$done_base_hash}{keys %$nbrs}
                    = values %$nbrs;
                @{$done_comp_hash}{keys %$nbrs}
                    = values %$nbrs;
            }
        }

    }

    $self->set_last_update_time;

    return 1;
}

#  convert the results of a compare run to significance thresholds
#  need a better sub name
sub convert_comparisons_to_significances {
    my $self = shift;
    my %args = @_;
    
    my $result_list_pfx = $args{result_list_name};
    croak qq{Argument 'result_list_name' not specified\n}
        if !defined $result_list_pfx;

    #  drop out if no elements to compare with
    my $e_list = $self->get_element_list;
    return 1 if not scalar @$e_list;

    my $progress = Biodiverse::Progress->new();
    my $progress_text = "Calculating significances";
    $progress->update ($progress_text, 0);

    # find all the relevant lists for this target name
    #my %base_list_indices = $self->find_list_indices_across_elements;
    my @target_list_names
      = grep {$_ =~ /^$result_list_pfx>>(?!p_rank>>)/}
        $self->get_hash_list_names_across_elements;

#  some more debugging
say "Prefix is $result_list_pfx";
say "Target list names are: " . join ' ', @target_list_names;

    my $to_do = $self->get_element_count;
    my $i = 0;
    
    #  maybe should make this an argument - recycle_if_possible -
    #  and let the caller do the checks, as we don't have $comparison in here
    my $recycled_results
      = $self->get_param ('RESULTS_ARE_RECYCLABLE');
    #if ($recycled_results && exists $args{no_recycle}) {  #  mostly for debug 
    #    $recycled_results = $args{no_recycle};
    #}

    my %done_base;
    if ($recycled_results) {  #  set up some lists
        foreach my $list_name (@target_list_names) {
            $done_base{$list_name} = {};
        }
    }

    COMP_BY_ELEMENT:
    foreach my $element ($self->get_element_list) {
        $i++;

        $progress->update (
            $progress_text . "(element $i / $to_do)",
            $i / $to_do,
        );

        #  now loop over the list indices
        BY_LIST:
        foreach my $list_name (@target_list_names) {

            next BY_LIST
                if    $recycled_results
                   && $done_base{$list_name}{$element};

            my $comp_ref = $self->get_list_ref (
                element     => $element,
                list        => $list_name,
                autovivify  => 0,
            );

            next BY_LIST if !$comp_ref; #  nothing to compare with...
            next BY_LIST if (is_arrayref($comp_ref));  #  skip arrays

            my $result_list_name = $list_name;
            $result_list_name =~ s/>>/>>p_rank>>/;

            my $result_list_ref = $self->get_list_ref (
                element => $element,
                list    => $result_list_name,
            );

            $self->get_sig_rank_from_comp_results (
                comp_list_ref    => $comp_ref,
                results_list_ref => $result_list_ref,  #  do it in-place
            );

            #  if results from both base and comp
            #  are recycled then we can recycle the comparisons
            if ($recycled_results) {
                my $nbrs = $self->get_list_ref (
                    element => $element,
                    list    => 'RESULTS_SAME_AS',
                );

                my $results_ref = $self->get_list_ref (
                    element => $element,
                    list    => $result_list_name,
                );

                BY_RECYCLED_NBR:
                foreach my $nbr (keys %$nbrs) {
                    $self->add_to_lists (
                        element           => $nbr,
                        $result_list_name => $results_ref,
                        use_ref           => 1,
                    );
                }
                my $done_base_hash = $done_base{$list_name};
                @{$done_base_hash}{keys %$nbrs}
                    = values %$nbrs;
            }
        }

    }

    $self->set_last_update_time;

    return 1;
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

    my $gp_list = $to->get_element_list;
    my @rand_lists =
        grep {$_ =~ $re_rand_list_names}
        $to->get_hash_list_names_across_elements;

    foreach my $list_name (@rand_lists) {
        foreach my $group (@$gp_list) {
            my $lr_to   = $to->get_list_ref (
                element => $group,
                list => $list_name,
            );
            my $lr_from = $from->get_list_ref (
                element => $group,
                list => $list_name,
            );
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
                my $index = substr $key, 1; # faster than s///;
                $lr_to->{$key} = $lr_to->{"C$index"} / $lr_to->{"Q$index"};
            }
        }
    }
    #  could do directly, but convert_comparisons_to_significances handles recycling 
    foreach my $rand_name (@randomisations_to_reintegrate) {
        $to->convert_comparisons_to_significances (
            result_list_name => $rand_name,
        );
    }
    return;
}

sub find_list_indices_across_elements {
    my $self = shift;
    my %args = @_;
    
    my @lists = $self->get_lists_across_elements;
    
    my $bd = $self->get_param ('BASEDATA_REF');
    my $indices_object = Biodiverse::Indices->new(BASEDATA_REF => $bd);

    my %calculations_by_index = $indices_object->get_index_source_hash;

    my %index_hash;

    #  loop over the lists and find those that are generated by a calculation
    #  This ensures we get all of them if subsets are used.
    foreach my $list_name (@lists) {
        if (exists $calculations_by_index{$list_name}) {
            $index_hash{$list_name} = $list_name;
        }
    }

    return wantarray ? %index_hash : \%index_hash;
}

my $INVALID_CALCS_ERROR_MESSAGE = <<'END_INVALID_CALCS_ERR_MSG'
[SPATIAL] No valid analyses, dropping out
Possible reasons:
There are insufficient neighbour conditions for the chosen calculations
(you specified one but turnover calculations, for example, require two).
Phylogenetic calculations were selected but there is no tree.
Numeric label calculations were selected but your labels are not numeric.
END_INVALID_CALCS_ERR_MSG
  ;


#
########################################################

########################################################
#  spatial calculation methods

sub run_analysis {
    my $self = shift;
    return $self->sp_calc(@_);
}

#  calculate one or more spatial indices based on
#  a set of neighbourhood parameters
sub sp_calc {  
    my $self = shift;
    my %args = @_;

    say "[SPATIAL] Running analysis " . $self->get_param('NAME');

    #  don't store this arg if specified
    my $use_nbrs_from = $args{use_nbrs_from};
    delete $args{use_nbrs_from};  

    #  flag for use if we drop out.  Set to 1 on completion.
    $self->set_param (COMPLETED => 0);

    #  load any predefined args - overriding user specified ones
    #  need to change this to be ANALYSIS_ARGS
    my $ref = $self->get_param ('SP_CALC_ARGS');
    if (defined $ref) {
        %args = %$ref;
    }

    # a little backwards compatibility since we've changed the nomenclature
    if (! exists $args{calculations} && exists $args{analyses}) {
        $args{calculations} = $args{analyses};
    }

    my $no_create_failed_def_query = $args{no_create_failed_def_query};
    my $calc_only_elements_to_calc = $args{calc_only_elements_to_calc};
    my $use_recycling              = !$args{no_recycling};
    my $ignore_spatial_index       = $args{ignore_spatial_index};
    #say "[SPATIAL] Using recycling: $use_recycling";

    my $spatial_conditions_arr  = $self->get_spatial_conditions_arr (%args);
    my $definition_query
      = $self->get_definition_query (definition_query => $args{definition_query});

    my $start_time = time;

    my $bd = $self->get_param ('BASEDATA_REF');
    my $gps_ref = $bd->get_groups_ref;

    my $indices_object = Biodiverse::Indices->new(
        BASEDATA_REF => $bd,
        NAME         => 'Indices for ' . $self->get_param('NAME'),
    );

    my $nbr_list_count = scalar @$spatial_conditions_arr;
    $indices_object->get_valid_calculations (
        %args,
        nbr_list_count => $nbr_list_count,
        element_list1  => [],  #  for validity checking only
        element_list2  => $nbr_list_count == 2 ? [] : undef,
        processing_element => 'x',
    );

    #  drop out if we have none to do and we don't have an override flag
    croak $INVALID_CALCS_ERROR_MESSAGE
        if (        $indices_object->get_valid_calculation_count == 0
            and not $args{override_valid_analysis_check});

    my $valid_calcs = scalar $indices_object->get_valid_calculations_to_run;
    my $indices_reqd_args = $indices_object->get_required_args_as_flat_array(calculations => $valid_calcs);

    my $recyclable_nbrhoods     = $use_recycling ? $self->get_recyclable_nbrhoods : [];
    my $results_are_recyclable  = $use_recycling && $self->get_param('RESULTS_ARE_RECYCLABLE');

    #  These need to be shifted into get_recyclable_nbrhoods:
    #  If we are using neighbours from another spatial object
    #  then we use its recycle setting, and store it for later
    if ($use_nbrs_from && $use_recycling) {
        $results_are_recyclable =
          $use_nbrs_from->get_param ('RESULTS_ARE_RECYCLABLE');
        $self->set_param (RESULTS_ARE_RECYCLABLE => $results_are_recyclable);
    }
    #  override any recycling setting if we use the processing_element in the calcs
    #  as many results will vary by location
    if (scalar grep {$_ eq 'processing_element'} @$indices_reqd_args) {
        $self->set_param(RESULTS_ARE_RECYCLABLE => 0);
        $results_are_recyclable = 0;
    }

    #  this is for the GUI
    $self->set_param (CALCULATIONS_REQUESTED => $args{calculations});
    #  save the args, but override the calcs so we only store the valid ones
    $self->set_param (
        SP_CALC_ARGS => {
            %args,
            calculations => [keys %$valid_calcs],
        }
    );

    #  don't pass these onwards when we call the calcs
    delete @args{qw /calculations analyses/};  

    say '[SPATIAL] running calculations '
          . join q{ }, sort keys %{$indices_object->get_valid_calculations_to_run};

    #  use whatever spatial index the parent is currently using if nothing already set
    #  if the basedata object has no index, then we won't either
    my $sp_index;
    if (!$ignore_spatial_index) {
        if (not $self->exists_param ('SPATIAL_INDEX')) {
            $self->set_param (SPATIAL_INDEX => $bd->get_param ('SPATIAL_INDEX'));
        }
        $sp_index = $self->get_param ('SPATIAL_INDEX');
    }

    #  use existing offsets if they exist
    #  (eg if this is a randomisation based on some original sp_calc)
    my $search_blocks_arr = $self->get_param ('INDEX_SEARCH_BLOCKS')
                            || [];
    $spatial_conditions_arr = $self->get_spatial_conditions || [];

    if (!$use_nbrs_from && $use_recycling) {
        #  first look for a sibling with the same spatial parameters
        my @comparable = eval {
            $bd->get_outputs_with_same_spatial_conditions (compare_with => $self);
        };
        $use_nbrs_from = $comparable[0];  #  empty if none are comparable
    }
    #  try again if we didn't get it before, 
    #  but this time check the index
    if (! $use_nbrs_from) {

      SPATIAL_PARAMS_LOOP:
        for my $i (0 .. $#$spatial_conditions_arr) {
            my $set_i = $i + 1;

            my $sp_cond_obj  = $spatial_conditions_arr->[$i];
            my $result_type  = $sp_cond_obj->get_result_type;
            my $ignore_index = $sp_cond_obj->get_ignore_spatial_index_flag;

            if ($result_type eq 'always_true') {
                #  no point using the index if we have to get them all
                say "[SPATIAL] All groups are neighbours.  Index will be ignored for neighbour set $set_i.";
                next SPATIAL_PARAMS_LOOP;
            }
            elsif ($result_type eq 'self_only') {
                say "[SPATIAL] No neighbours, processing group only.  Index will be ignored for neighbour set $set_i.";
                next SPATIAL_PARAMS_LOOP;
            }
            elsif ($ignore_index || $sp_cond_obj->get_param ('INDEX_NO_USE')) { #  or if the conditions won't cooperate with the index
                say "[SPATIAL] Index set to be ignored for neighbour set $set_i.";  #  put this feedback in the spatialparams?
                next SPATIAL_PARAMS_LOOP;
            }
            else {
                say "[SPATIAL] Result type for neighbour set $set_i is $result_type."
            }

            my $search_blocks = $search_blocks_arr->[$i];

            if (defined $sp_index && ! defined $search_blocks) {
                if ($i == 0) {
                    say '[SPATIAL] Using spatial index';
                }
                my $progress_text_pfx = 'Neighbour set ' . ($i+1);
                $search_blocks = $sp_index->predict_offsets (
                    spatial_conditions => $spatial_conditions_arr->[$i],
                    cellsizes          => scalar $bd->get_cell_sizes,
                    progress_text_pfx  => $progress_text_pfx,
                );
                $search_blocks_arr->[$i] = $search_blocks;
            }
        }
    }

    $self->set_param (INDEX_SEARCH_BLOCKS => $search_blocks_arr);
    
    #  maybe we only have a few we need to calculate?
    my %elements_to_use;
    #my $calc_element_subset;
    if (defined $args{elements_to_calc}) {
        #$calc_element_subset = 1;
        my $elts = $args{elements_to_calc}; 
        if (is_arrayref($elts)) {
            @elements_to_use{@$elts} = @$elts;
        }
        elsif (is_hashref($elts)) {
            %elements_to_use = %$elts;
        }
        else {
            $elements_to_use{$elts} = $elts;
        }
    }
    else {  #  this is a clunky way of doing all of them,
            # but we need the full set for GUI purposes for now
        my @gps = $bd->get_groups;
        @elements_to_use{@gps} = @gps;
    }

    my @elements_to_calc;
    my @elements_to_exclude;
    if ($args{calc_only_elements_to_calc}) { #  a bit messy but should save RAM 
        @elements_to_calc = keys %elements_to_use;
        my %elements_to_exclude_h;
        @elements_to_exclude_h{$bd->get_groups} = undef;
        delete @elements_to_exclude_h{@elements_to_calc};
        @elements_to_exclude = keys %elements_to_exclude_h;
    }
    else {
        @elements_to_calc = $bd->get_groups;
    }
    
    my $exclude_processed_elements = $args{exclude_processed_elements};
    
    #EL: Set our CELL_SIZES
    # SL: modified for new structure
    if (!defined $self->get_cell_sizes) {
        $self->set_param (CELL_SIZES => scalar $bd->get_cell_sizes);
    }
    my $name = $self->get_param ('NAME');
    my $progress_text_base = $args{progress_text} || $name;

    #  create all the elements and the SPATIAL_RESULTS list
    my $to_do = scalar @elements_to_calc;
    
    #  check the elements against the definition query
    my $pass_def_query = $self->get_groups_that_pass_def_query (
        def_query        => $definition_query,
        elements_to_calc => \@elements_to_calc,
    );

    #  get the global pre_calc results
    $indices_object->run_precalc_globals(%args);

    say "[SPATIAL] Creating target groups";
    
    my $progress_text_create
        = $progress_text_base . "\nCreating target groups";
    my $progress = Biodiverse::Progress->new(text => $progress_text_create);

    my $failed_def_query_sp_res_hash = {};
    my $elt_count = -1;
    my $csv_object = $self->get_csv_object (
        quote_char => $self->get_param ('QUOTES'),
        sep_char   => $self->get_param ('JOIN_CHAR'),
    );

    GET_ELEMENTS_TO_CALC:
    foreach my $element (@elements_to_calc) {
        $elt_count ++;

        my $progress_so_far = $elt_count / $to_do;
        my $progress_text   = "Spatial analysis $progress_text_create\n";
        $progress->update ($progress_text, $progress_so_far);

        my $sp_res_hash = {};
        if (        $definition_query
            and not exists $pass_def_query->{$element}) {

            if ($no_create_failed_def_query) {
                if ($calc_only_elements_to_calc) {
                    push @elements_to_exclude, $element;
                }
                next GET_ELEMENTS_TO_CALC;
            }

            $sp_res_hash = $failed_def_query_sp_res_hash;
        }


        $self->add_element (element => $element, csv_object => $csv_object);

        # initialise the spatial_results with an empty hash
        $self->add_to_lists (
            element         => $element,
            SPATIAL_RESULTS => $sp_res_hash,
        );

    }
    $progress->update ($EMPTY_STRING, 1);
    $progress->reset;
    $progress = undef;
    
    local $| = 1;  #  write to screen as we go
    my $using_index_text = defined $sp_index ? $EMPTY_STRING : "\nNot using spatial index";

    my $progress_text =
              "Spatial analysis\n$progress_text_base\n"
            . "(0 / $to_do)"
            . $using_index_text;
    $progress = Biodiverse::Progress->new(text => $progress_text);
    
    #$progress->update ($progress_text, 0);

    my ($count, $printed_progress) = (0, -1);
    print "[SPATIAL] Progress (% of $to_do elements):     ";
    #$timer = [gettimeofday];    # to use with progress bar
    my $recyc_count = 0;

    #  loop though the elements and calculate the outputs
    #  Currently we don't allow user specified coords not in the basedata
    #  - this is for GUI reasons such as nbr selection
    BY_ELEMENT:
    foreach my $element (sort @elements_to_calc) {
        #last if $count > 5;  #  FOR DEBUG
        $count ++;
        
        my $progress_so_far = $count / $to_do;
        my $progress_text =
              "Spatial analysis\n$progress_text_base\n"
            . "($count / $to_do)"
            . $using_index_text;
        $progress->update ($progress_text, $progress_so_far);

        #  don't calculate unless in the list
        next BY_ELEMENT if not $elements_to_use{$element};  

        #  check the definition query to decide if we should do this one
        if ($definition_query) {
            my $pass = exists $pass_def_query->{$element};
            next BY_ELEMENT if not $pass;
        }

        #  skip if we've already copied them across
        next if $results_are_recyclable
            && $self->exists_list (
                element => $element,
                list    => 'RESULTS_SAME_AS',
            );

        my @nbr_list = $self->get_nbrs_for_element (
            element       => $element,
            use_nbrs_from => $use_nbrs_from,
            elements_to_exclude => \@elements_to_exclude,
            search_blocks_arr   => $search_blocks_arr,
        );

        my %elements = (
            element_list1 => $nbr_list[0],
            element_list2 => $nbr_list[1],
        );

        #  this is the meat of it all
        my %sp_calc_values = $indices_object->run_calculations(
            %args,
            %elements,
            processing_element => $element,
        );

        my $recycle_lists = {};

        #  now add the results to the appropriate lists
        foreach my $key (keys %sp_calc_values) {
            my $list_ref = $sp_calc_values{$key};

            if (is_arrayref($list_ref) || is_hashref($list_ref)) {
                $self->add_to_lists (
                    element => $element,
                    $key    => $list_ref,
                );

                #  if we can recycle results, then store these results 
                if ($results_are_recyclable) {
                    $recycle_lists->{$key} = $list_ref;
                }

                delete $sp_calc_values{$key};
            }
        }
        #  everything else goes into this hash
        $self->add_to_lists (
            element         => $element,
            SPATIAL_RESULTS => \%sp_calc_values,
        );

        #  If the results can be recycled then assign them
        #  to the relevant groups now
        #  Note - only applies to groups in first nbr set
        my %nbrs_1;  #  the first nbr list as a hash
        if ($recyclable_nbrhoods->[0]) {
            #  Ignore those we aren't interested in
            #  - does not affect calcs, only recycled results.
            %nbrs_1 = map  {$_ => 1}
                      grep {exists $elements_to_use{$_}}
                      @{$nbr_list[0]};

          RECYC:
            foreach my $first_nbr (keys %nbrs_1) {
                next RECYC if $first_nbr eq $element;
                if (! $self->nbr_list_already_recycled(element => $first_nbr)) {
                    #  for each nbr in %nbrs_1,
                    #  copy the neighbour sets for those that are recyclable
                    $self->recycle_nbr_lists (
                        recyclable_nbrhoods => $recyclable_nbrhoods,
                        nbr_lists           => \@nbr_list,
                        nbrs_1              => \%nbrs_1,
                        definition_query    => $definition_query,
                        pass_def_query      => $pass_def_query,
                        element             => $element,
                    );
                    last RECYC;
                }
            }
        }
        if ($results_are_recyclable) {
            $recyc_count ++;
            $sp_calc_values{RECYCLED_SET} = $recyc_count;

            $recycle_lists->{SPATIAL_RESULTS} = \%sp_calc_values;
            $recycle_lists->{RESULTS_SAME_AS} = \%nbrs_1;

            $self->recycle_list_results (
                definition_query => $definition_query,
                pass_def_query   => $pass_def_query,
                list_hash        => $recycle_lists,
                nbrs_1           => \%nbrs_1,
            );
        }

        #  debug stuff
        #$self->_check_results_recycled_properly (
        #    element       => $element,
        #    use_nbrs_from => $use_nbrs_from,
        #    results_are_recyclable => $results_are_recyclable,
        #);

        if ($exclude_processed_elements) {
            push @elements_to_exclude, $element;
        }
        
    }  #  end BY_ELEMENT

    $progress->reset;

    #  run any global post_calcs
    my %post_calc_globals = $indices_object->run_postcalc_globals (%args);

    $self->clear_spatial_condition_caches;
    $self->clear_spatial_index_csv_object;
    #  need to also clear the args caches - sometimes the def query escapes
    my $sp_cond_args = $args{spatial_conditions};
    foreach my $obj ($args{definition_query}, @{$sp_cond_args || []}) {
        next if !$obj || !blessed $obj;
        $obj->delete_cached_values;
    }

    #  this will cache as well
    my $lists = $self->get_lists_across_elements();

    my $time_taken = time - $start_time;
    printf "\n[SPATIAL] Analysis took %.3f seconds.\n", $time_taken;
    $self->set_param (ANALYSIS_TIME_TAKEN => $time_taken);

    #  sometimes we crash out but the object still exists
    #  this setting allows checks of completion status
    $self->set_param (COMPLETED => 1);
    
    $self->set_last_update_time;

    return 1;
}

#  assumes they have already been calculated
sub get_calculated_nbr_lists_for_element {
    my $self = shift;
    my %args = @_;

    my $element       = $args{element};
    my $use_nbrs_from = $args{use_nbrs_from};
    my $spatial_conditions_arr = $self->get_spatial_conditions;
    my $sort_lists    = $args{sort_lists};

    my @nbr_list;
    foreach my $i (0 .. $#$spatial_conditions_arr) {
        my $nbr_list_name = '_NBR_SET' . ($i+1);
        my $nbr_list = $self->get_list_ref (
            element => $element,
            list    => $nbr_list_name,
            autovivify => 0,
        );
        my $copy = $sort_lists ? [sort @$nbr_list] : [@$nbr_list];
        push @nbr_list, $copy;
    }
    
    return wantarray ? @nbr_list : \@nbr_list;
}

#  should probably be calculate_nbrs_for_element
sub get_nbrs_for_element {
    my $self = shift;
    my %args = @_;

    my $element       = $args{element};
    my $use_nbrs_from = $args{use_nbrs_from};
    my $elements_to_exclude = $args{elements_to_exclude};
    my $search_blocks_arr   = $args{search_blocks_arr};
    
    my $spatial_conditions_arr = $self->get_spatial_conditions;
    my $sp_index = $self->get_param ('SPATIAL_INDEX');
    my $bd = $self->get_basedata_ref;

    my @nbr_list;
    my @exclude;

    foreach my $i (0 .. $#$spatial_conditions_arr) {
        my $nbr_list_name = '_NBR_SET' . ($i+1);
        #  Useful since we can have non-overlapping neighbourhoods
        #  where we set all the results in one go.
        #  Should only be triggered when results recycling is off but we still recycle nbrs,
        #  as we don't double handle when recycling results
        if ($self->exists_list (
                element => $element,
                list    => $nbr_list_name
            )) {

            my $nbrs
              = $self->get_list_values (
                  element => $element,
                  list    => $nbr_list_name,
              )
              || [];
            $nbr_list[$i] = $nbrs;
            push @exclude, @$nbrs;
        }
        else {
            if ($use_nbrs_from) {
                $nbr_list[$i] = $use_nbrs_from->get_list_values (
                    element => $element,
                    list    => $nbr_list_name,
                );
                $nbr_list[$i] //= [];  #  use empty list if necessary
            }
            #  if $use_nbrs_from lacks the list, or we're finding the neighbours ourselves
            if (not defined $nbr_list[$i]) {  
                my $list;
                my $sp_cond_obj = $spatial_conditions_arr->[$i];
                my $result_type = $sp_cond_obj->get_result_type;
                #  get everything
                if ($result_type eq 'always_true') {  
                    $list = $bd->get_groups;
                }
                #  nothing to work with
                elsif ($result_type eq 'always_false') {  
                    $list = [];
                }
                #  no nbrs, just oneself
                elsif ($result_type eq 'self_only') {
                    $list = [$element];
                }
                #  if nbrs are always the same
                elsif ($result_type eq 'always_same') {
                    my $tmp = $self->get_cached_value('NBRS_FROM_ALWAYS_SAME');
                    if ($tmp && $tmp->[$i]) {
                        my $nbrs = $tmp->[$i];
                        $list = [keys %$nbrs];
                    }
                }

                if ($list) {
                    my %tmp;  #  remove any that should not be there
                    my $excl = [@exclude, @$elements_to_exclude];
                    @tmp{@$list} = (1) x @$list;
                    delete @tmp{@$excl};
                    $nbr_list[$i] = [keys %tmp];
                }
                else {    #  no nbr list thus far so go looking

                    #  don't use the index if there are no search blocks
                    #  (this setting is controlled above where the search blocks are processed)
                    my $sp_index_i;
                    if ($search_blocks_arr->[$i]) {
                        $sp_index_i = $sp_index;
                    }

                    my %args_for_nbr_list = (
                        element            => $element,
                        spatial_conditions => $sp_cond_obj,
                        index              => $sp_index_i,
                        index_offsets      => $search_blocks_arr->[$i],
                    );
                    my $exclude_list = [@exclude, @$elements_to_exclude];

                    if ($result_type eq 'always_same') {
                        my $progr = Biodiverse::Progress->new(text => 'Neighbour comparisons for first always_same condition');
                        my $tmp = $bd->get_neighbours (
                            %args_for_nbr_list,
                            progress => $progr,
                        );
                        $progr = undef;
                        my $cached_arr
                          = $self->get_cached_value_dor_set_default_aa(
                              'NBRS_FROM_ALWAYS_SAME', []
                            );

                        $cached_arr->[$i] = $tmp;
                        my %tmp2 = %$tmp;
                        delete @tmp2{@$exclude_list};
                        $nbr_list[$i] = [keys %tmp2];
                    }
                    else {
                        #  go search
                        $nbr_list[$i] = $bd->get_neighbours_as_array (
                            %args_for_nbr_list,
                            exclude_list => $exclude_list,
                        );
                    }
                }

                #  Add to the exclude list unless we are at the last spatial condition,
                #  in which case it is no longer needed.
                #  Hopefully this will save meaningful memory for large neighbour sets
                if ($i != $#$spatial_conditions_arr) {
                    push @exclude, @{$nbr_list[$i]};
                }
            }

            #  now save it 
            $self->add_to_lists (
                element        => $element,
                $nbr_list_name => $nbr_list[$i],
                use_ref        => 1,
            );
        }
    }

    return wantarray ? @nbr_list : \@nbr_list;
}

#  recycle any list results
sub recycle_list_results {
    my $self = shift;
    my %args = @_;
    
    my $nbrs_1           = $args{nbrs_1};
    my $definition_query = $args{definition_query};
    my $pass_def_query   = $args{pass_def_query};
    my $list_hash        = $args{list_hash};

    RECYC_INTO_NBRS1:
    foreach my $nbr (keys %$nbrs_1) {
        if ($definition_query) {
            my $pass = exists $pass_def_query->{$nbr};
            next RECYC_INTO_NBRS1 if not $pass;
        }

        while (my ($listname, $list_ref) = each %$list_hash) {
            $self->add_to_lists (
                element   => $nbr,
                $listname => $list_ref,
                use_ref   => 1,
            );
        }
    }

    
    return;
}

sub recycle_nbr_lists {
    my $self = shift;
    my %args = @_;

    my $recyclable_nbrhoods = $args{recyclable_nbrhoods};
    my $nbr_lists           = $args{nbr_lists};
    my $nbrs_1              = $args{nbrs_1};
    my $definition_query    = $args{definition_query};
    my $pass_def_query      = $args{pass_def_query};
    my $element             = $args{element};

    #  for each nbr in %nbrs_1,
    #  copy the neighbour sets for those that overlap
  LOOP_RECYC_NBRHOODS:
    foreach my $i (0 .. $#$recyclable_nbrhoods) {
        #  all preceding must be recyclable
        last LOOP_RECYC_NBRHOODS
            if !$recyclable_nbrhoods->[$i];  

        my $nbr_list_name = '_NBR_SET' . ($i+1);
        my $nbr_list_ref  = $nbr_lists->[$i];

        LOOP_RECYC_NBRS:
        foreach my $nbr (keys %$nbrs_1) {
            next LOOP_RECYC_NBRS if $nbr eq $element;

            if ($definition_query) {
                my $pass = exists $pass_def_query->{$nbr};
                next LOOP_RECYC_NBRS if not $pass;
            }

            #  recycle the array using a ref to save space
            $self->add_to_lists (
                element         => $nbr,
                $nbr_list_name  => $nbr_list_ref,
                use_ref         => 1,  
            );
        }
    }

    return;
}

sub nbr_list_already_recycled {
    my $self = shift;
    my %args = @_;

    #  we only work on the first nbr set
    my $nbr_list_name = '_NBR_SET1';

    return $self->exists_list (
        element => $args{element},
        list    => $nbr_list_name
    );    
}

#  internal sub to check results are recycled properly
#  Note - only valid for randomisations when nbrhood is
#  sp_self_only() or sp_select_all()
#  as other neighbourhoods result in varied results per cell
sub _check_results_recycled_properly {
    my $self = shift;
    my %args = @_;
    
    my $element = $args{element};
    my $use_nbrs_from = $args{use_nbrs_from};
    
    my $results_are_recyclable = $args{results_are_recyclable};

    if ($use_nbrs_from && $results_are_recyclable) {
        my $list1_ref = $self->get_list_ref (
            element => $element,
            list    => 'SPATIAL_RESULTS',
        );
        
        my $list2_ref = $use_nbrs_from->get_list_ref (
            element => $element,
            list    => 'SPATIAL_RESULTS',
        );
        
        while (my ($key, $value1) = each %$list1_ref) {
            my $value2 = $list2_ref->{$key};
            croak "$value1 != $value2, $element\n" if $value1 != $value2;
        }
    }
    
    return;
}


#
########################################################


sub get_embedded_tree {
    my $self = shift;
    
    my $args = $self->get_param ('SP_CALC_ARGS');

    return $args->{tree_ref} if exists $args->{tree_ref};

    return;
}

sub get_embedded_matrix {
    my $self = shift;
    
    my $args = $self->get_param ('SP_CALC_ARGS');

    return $args->{matrix_ref} if exists $args->{matrix_ref};

    return;
}

sub get_definition_query {
    my $self = shift;
    my %args = @_;
    
    my $definition_query = $self->get_def_query
                           || $args{definition_query};

    return if ! defined $definition_query;

    if (length ($definition_query) == 0) {
        $definition_query = undef;
    }
    #  now parse the query into an object if needed
    elsif (not blessed $definition_query) {
        $definition_query = Biodiverse::SpatialConditions::DefQuery->new (
            conditions   => $definition_query,
            basedata_ref => $self->get_basedata_ref,
        );
    }
    else {
        my $dq = $definition_query->get_conditions_unparsed;
        if (length ($dq) == 0) {
            $definition_query = undef;
        }
    }

    $self->set_param (DEFINITION_QUERY => $definition_query);

    if ($definition_query) {
        $definition_query->set_caller_spatial_output_ref ($self);
        $definition_query->set_param(NAME => $self->get_name);
    }
    
    return $definition_query;
}

sub get_spatial_conditions_arr {
    my $self = shift;
    my %args  = @_;

    my $spatial_conditions_arr = $self->get_spatial_conditions;

    return $spatial_conditions_arr if defined $spatial_conditions_arr;
    
    #  if we don't already have spatial conditions then check the arguments

    $args{spatial_conditions} //= $args{spatial_params};  #  for back compat
    croak "spatial_conditions not an array ref or not defined\n"
      if !is_arrayref($args{spatial_conditions});

    $spatial_conditions_arr = $args{spatial_conditions};
    my $check = 1;

  CHECK:
    while ($check) {  #  clean up undef or empty params at the end

        if (scalar @$spatial_conditions_arr == 0) {
            warn "[Spatial] No valid spatial conditions specified\n";
            #  put an empty string as the only entry,
            #  saves problems down the line
            $spatial_conditions_arr->[0] = $EMPTY_STRING;
            return;
        }

        my $param = $spatial_conditions_arr->[-1] // $EMPTY_STRING;
        if (blessed $param) {
            $param = $param->get_conditions_unparsed;
        }

        $param =~ s/^\s*//;  #  strip leading and trailing whitespace
        $param =~ s/\s*$//;

        last CHECK if length $param;

        say '[SPATIAL] Deleting undefined or empty spatial condition at end of conditions array';
        pop @$spatial_conditions_arr;    
    }

    #  Now loop over them and parse the spatial params into objects if needed
    for my $i (0 .. $#$spatial_conditions_arr) {
        if (! blessed $spatial_conditions_arr->[$i]) {
            $spatial_conditions_arr->[$i]
                = Biodiverse::SpatialConditions->new (
                    conditions   => $spatial_conditions_arr->[$i],
                    basedata_ref => $self->get_basedata_ref,
                );
        }
    }
    $self->set_param (SPATIAL_CONDITIONS => $spatial_conditions_arr);

    #  and let them know about ourselves
    foreach my $sp (@$spatial_conditions_arr) {
        $sp->set_caller_spatial_output_ref ($self);
    }

    return $spatial_conditions_arr;
}


#  a nbrhood can be recycled if it nbrhood is non-overlapping
#  (is constant for all nbrs in nbrhood)
#  and so are all its predecessors
sub get_recyclable_nbrhoods {
    my $self = shift;
    my %args = @_;

    my $spatial_conditions_ref = $self->get_spatial_conditions_arr;

    my @recyclable_nbrhoods;
    my $results_are_recyclable = 0;

    my %recyc_candidates = (
        non_overlapping  => 0,     # only index 0
        always_true      => undef, # any index
        text_match_exact => undef, # any index
        #always_same      => undef, # any index
    );

    for my $i (0 .. $#$spatial_conditions_ref) {
        my $sp_cond     = $spatial_conditions_ref->[$i];
        my $result_type = $sp_cond->get_result_type;
        
        my $prev_nbr_is_recyclable = 1;  #  always check first one
        if ($i > 0) {  #  only check $i if $i-1 is true
            $prev_nbr_is_recyclable = $recyclable_nbrhoods[$i-1];
        }

        next if !(    $prev_nbr_is_recyclable
             && exists $recyc_candidates{$result_type}
             && !$sp_cond->get_no_recycling_flag );

        # only those in the first nbrhood,
        # or if the previous nbrhood is recyclable
        # and we allow recyc beyond first index
        my $is_valid_recyc_index =
          defined $recyc_candidates{$result_type}
            ? $i <= $recyc_candidates{$result_type}
            : 1;

        if ( $is_valid_recyc_index ) { 
            $recyclable_nbrhoods[$i] = 1;
            $results_are_recyclable ++;
        }

    }

    #  we can only recycle the results if all nbr sets are recyclable 
    if ($results_are_recyclable != scalar @$spatial_conditions_ref) {
        $results_are_recyclable = 0;
    }

    if (1 and $results_are_recyclable) {
        say '[SPATIAL] Results are recyclable.  '
              . 'This will save some processing';
    }

    #  need a better name - unique to nbrhood? same_for_whole_nbrhood?
    $self->set_param( RESULTS_ARE_RECYCLABLE => $results_are_recyclable );

    return wantarray ? @recyclable_nbrhoods : \@recyclable_nbrhoods;
}

sub group_passed_def_query {
    my $self = shift;
    my %args = @_;

    my $group = $args{group};

    croak "Argument 'group' not passed\n"
      if !defined $group;

    my $passed = $self->get_param('PASS_DEF_QUERY');

    no autovivification;

    #  return true if no def query was run
    return $passed ? $passed->{$group} : 1;  
}


sub get_groups_that_pass_def_query {
    my $self = shift;
    my %args = @_;

    my $definition_query = $self->get_definition_query (%args);
    my $passed = $self->get_param('PASS_DEF_QUERY') || {};
    
    return wantarray ? %$passed : $passed
      if $self->exists_param('PASS_DEF_QUERY') || !$definition_query;

    my $bd = $self->get_basedata_ref;

    print "Running definition query\n";
    my $elements_to_calc = $args{elements_to_calc};
    my $element = $elements_to_calc->[0];
    my $defq_progress = Biodiverse::Progress->new(text => 'def query');

    $passed
      = $bd->get_neighbours(
            element            => $element,
            spatial_conditions => $definition_query,
            is_def_query       => 1,
            progress           => $defq_progress,
        );
    $self->set_param (PASS_DEF_QUERY => $passed);

    if (! scalar keys %$passed) {
        $self->clear_spatial_condition_caches;
        croak "Nothing passed the definition query\n";
    }

    my $pass_count = scalar keys %$passed;
    print "$pass_count groups passed the definition query\n";

    return wantarray ? %$passed : $passed;
}

#  assumes the def query has already been run
sub get_groups_that_failed_def_query {
    my $self = shift;
    my %args = @_;

    my $passed = $self->get_param('PASS_DEF_QUERY');
    
    return if !$passed;  #  empty if not run

    my $groups = $self->get_element_list;

    no autovivification;

    my @failed = grep {!exists $passed->{$_}} @$groups;
    my %failed_hash;
    @failed_hash{@failed} = (1) x @failed;

    return wantarray ? %failed_hash : \%failed_hash;
}



1;


__END__

=head1 NAME

Biodiverse::Spatial - a set of spatial functions for a
Biodiverse::BaseStruct object.  POD IS MASSIVELY OUT OF DATE

=head1 SYNOPSIS

  use Biodiverse::Spatial;

=head1 DESCRIPTION

These functions should be inherited by higher level objects through their @ISA
list.

MANY OF THESE HAVE BEEN MOVED BACK TO Biodiverse::BaseData.

=head2 Assumptions

Assumes C<Biodiverse::Common> is in the @ISA list.

Almost all methods in the Biodiverse library use {keyword => value} pairs as a policy.
This means some of the methods may appear to contain unnecessary arguments,
but it makes everything else more consistent.

List methods return a list in list context, and a reference to that list
in scalar context.

=head1 Methods

These assume you have declared an object called $self of a type that
inherits these methods, normally:

=over 4

=item  $self = Biodiverse::BaseData->new;

=back

=head2 Function Calls

=over 5

=item $self->add_spatial_output;

Adds a spatial output object to the list of spatial outputs.  This is of
type C<Biodiverse::BaseStruct>.

=item $self->get_spatial_outputs;

Returns the hash containing the Spatial Output names and their references.

=item $self->delete_spatial_output (name => 'somename');

Deletes the spatial output referred to as name C<somename>.  

=item $self->get_spatial_output_ref (name => $name);

Gets the reference to the named spatial output object.

=item $self->get_spatial_output_list;

Gets an array of the spatial output objects in this BaseData object.

=item $self->get_spatial_output_refs;

Gets an array of references to the spatial output objects in this
Biodiverse::BaseData object.  These are of type C<Biodiverse::BaseStruct>.

=item $self->get_spatial_output_names (name => 'somename');

Returns the reference to the named spatial output.
Returns C<undef> if it does not exist or if argument
C<name> is not specified.

=item $self->predict_offsets (spatial_paramshashref => $hash_ref);

OUT OF DATE.....
 
Predict the maximum spatial distances needed to search based on an indexed
Groups object within the Basedata object.

The input hash can be generated using C<Biodiverse::Common::parse_spatial_params>,
and the index using C<Biodiverse::BaseData::build_index>.

=item $self->get_neighbours (element => $element, parsed_spatial_params => \%spatialParams, exclude_list => \@list);

Gets a hash of the neighbours around $element that satisfy the conditions
in %spatialParams.  Calls C<parse_spatial_params> if not specified.
The exclusion list is the set of elements not to be added.  This makes it
easy to avoid double counting of neighbours and simplifies spatial parameters
settings.

=item $self->get_neighbours_as_array (element => $element, parsed_spatial_params => \%spatialParams, exclude_list = \@list);

Returns an array instead of a hash.  Just calls get_neighbours and sorts the keys.

=item $self->get_distances (coord_array1 => $element1, coord_array2 => $element2);

ALL THIS IS OUT OF DATE.

Calculate the distances between the coords in two sets of elements using
parameters derived from C<Biodiverse::Common::parse_spatial_params>.

As of version 1 we only use Euclidean distance
denoted by $D, $D[0], $D[1], $d[0], $d[1] etc.  The actual values are
determined using C<Biodiverse::Spatial::get_distances>.

$D is the absolute euclidean distance across all dimensions.

$D[0], $D[1] and so forth are the absolute distance in dimension 0, 1 etc.
In most cases this $D[0] will be the X dimension, $D[1] will be the y dimension.

$d[0], $d[1] and so forth are the signed distance in dimension 0, 1 etc.
This allows us to extract all groups within some distance in some direction.
As with standard cartesion plots, negative values are to the left or below (west or south),
positive values to the right or above (east or north).
As with $D[0], $d[0] will normally be the X dimension,
$d[1] will be the y dimension.

=item $sp->sp_calc(calculations => \%calculations);

Calculate one or more spatial indices specified in %calculations using 
neighbourhood parameters stored in the objects's parameters.

The results are stored in spatial object $sp.

%calculations must have the same structure as that returned by
C<Biodiverse::Indices::get_calculations>.

Runs all available calculations if none are specified.

Any other arguments are passed straight through to the indices.

The C<cache_*> options allow the user to cache the element, label and ABC lists
for direct export,
although we will be adding methods to do this to save on storage space when it
is exported (perl stores hash keys in a global list, so there is
little overhead when using hash keys multiple times).

The ABC lists are stored by default, as it is useful to display them and all
the indices depend on them.

Scalar results are added to the Spatial Output object's SPATIAL_OUTPUT hash.
Any lists are added as separate lists in the object, rather than pollute
the SPATIAL_OUTPUT hash with additional lists.


=back

=head1 REPORTING ERRORS

I read my email frequently, so use that.  It should be pretty stable, though.

=head1 AUTHOR

Shawn Laffan

Shawn.Laffan@unsw.edu.au


=head1 COPYRIGHT

Copyright (c) 2006 Shawn Laffan. All rights reserved.  This
program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REVISION HISTORY

=over 5

=item Version ???

May 2006.  Source libraries developed to the point where they can be
distributed.

=back

=cut
