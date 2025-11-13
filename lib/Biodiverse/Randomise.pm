package Biodiverse::Randomise;

#  methods to randomise a BaseData subcomponent

use strict;
use warnings;
use 5.022;

use English qw / -no_match_vars /;

use experimental qw /refaliasing/;

use Sort::Key::Natural qw /natkeysort/;
use List::Unique::DeterministicOrder;


#use Devel::Symdump;
#use Data::Dumper qw { Dumper };
use Carp;
use POSIX qw { ceil floor };
use Time::HiRes qw { time gettimeofday tv_interval };
use Scalar::Util qw { blessed looks_like_number };
use List::Util qw /any all none minstr max pairmap/;
use List::MoreUtils::XS;  #  paranoia to ensure we have this loaded
use List::MoreUtils 0.425 qw /first_index uniq binsert bremove/;
use Ref::Util qw /is_ref is_arrayref is_hashref/;
#use List::BinarySearch::XS;  #  make sure we have the XS version available via PAR::Packer executables
#use List::BinarySearch qw /binsearch  binsearch_pos/;
#eval {use Data::Structure::Util qw /has_circular_ref get_refs/}; #  hunting for circular refs
#use MRO::Compat;
use Class::Inspector;

use Biodiverse::Metadata::Randomisation;
my $metadata_class = 'Biodiverse::Metadata::Randomisation';

use Biodiverse::Metadata::Export;
my $export_metadata_class = 'Biodiverse::Metadata::Export';

use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';

use Biodiverse::Metadata::Parameter;
my $parameter_rand_metadata_class = 'Biodiverse::Metadata::Parameter';


require Biodiverse::BaseData;
use Biodiverse::Progress;

our $VERSION = '5.0';

my $EMPTY_STRING = q{};

require Biodiverse::Config;
my $progress_update_interval = $Biodiverse::Config::progress_update_interval;

use parent qw {
    Biodiverse::Randomise::IndependentSwaps
    Biodiverse::Randomise::CurveBall
    Biodiverse::Common};

sub new {
    my $class = shift;
    my %args = @_;

    my $self = bless {}, $class;

    if (defined $args{file}) {
        my $file_loaded = $self->load_file (@_);
        return $file_loaded;
    }

    my %PARAMS = (  #  default parameters to load.  These will be overwritten as needed.
        OUTPFX              => 'BIODIVERSE_RANDOMISATION',  #  not really used anymore
        OUTSUFFIX           => 'brs',
        OUTSUFFIX_YAML      => 'bry',
        PARAM_CHANGE_WARN   => undef,
    );

    #  load the defaults, with the rest of the args as params
    my %args_for = (%PARAMS, %args);
    $self->set_params (%args_for);

    #  avoid memory leak probs with circular refs
    $self->weaken_basedata_ref;

    return $self;
}

sub rename {
    my $self = shift;
    my %args = @_;

    my $new_name = $args{new_name};

    croak "[Randomise] Argument 'new_name' not defined\n"
      if !defined $new_name;

    #  Handle the lists in other outputs first
    #  as that depends on our current name
    my $bd = $self->get_basedata_ref;
    $bd->do_rename_randomisation_lists (%args, output => $self);

    #  Now rename ourselves
    $self->set_param (NAME => $new_name);

    return;
}



sub metadata_class {
    return $metadata_class;
}


sub _get_metadata_export {
    my $self = shift;

    #  need a list of export subs
    my %subs = $self->get_subs_with_prefix (prefix => 'export_');

    #  hunt through the other export subs and collate their metadata
    my @export_sub_params;
    my @formats;
    my %format_labels;  #  track sub names by format label
    #  avoid double counting of options, and list is specified below
    my %done = (
        list    => 1,
        format  => 1,
        file    => 1,
    );

    foreach my $sub (sort keys %subs) {
        my %sub_args = $self->get_args (sub => $sub);
        croak "Metadata item 'format' missing\n" if not defined $sub_args{format};

        my $params_array = $sub_args{parameters};
        foreach my $param_hash (@$params_array) {
            my $name = $param_hash->{name};
            if (!exists $done{$name}) {  #  does not allow mixed options and defaults etc - first in, best dressed
                push @export_sub_params, $param_hash;
                $done{$name} ++;
            }
        }

        push @formats, $sub_args{format};
        $format_labels{$sub_args{format}} = $sub; 
    }
    @formats = sort @formats;
    $self->move_to_front_of_list (list => \@formats, item => 'Delimited text');

    my @parameters = (
        {
            name => 'file',
            type => 'file',
        },
        {
            name        => 'format',
            label_text  => 'What to export',
            type        => 'choice',
            choices     => \@formats,
            default     => 0,
        },
        @export_sub_params,
    );
    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    my %args = (
        parameters => \@parameters,
        format_labels => \%format_labels,
    );

    return wantarray ? %args : \%args;
}

#  same as Basestruct method - refactor needed
sub get_metadata_export {
    my $self = shift;

    #  need a list of export subs
    my %subs = $self->get_subs_with_prefix (prefix => 'export_');

    my @formats;
    my %format_labels;  #  track sub names by format label

    #  loop through subs and get their metadata
    my %params_per_sub;

    LOOP_EXPORT_SUB:
    foreach my $sub (sort keys %subs) {
        my %sub_args = $self->get_args (sub => $sub);

        my $format = $sub_args{format};

        croak "Metadata item 'format' missing\n"
            if not defined $format;

        $format_labels{$format} = $sub;

        next LOOP_EXPORT_SUB
            if $sub_args{format} eq $EMPTY_STRING;

        $params_per_sub{$format} = $sub_args{parameters};

        my $params_array = $sub_args{parameters};

        push @formats, $format;
    }

    @formats = sort @formats;
    $self->move_to_front_of_list (
        list => \@formats,
        item => 'Initial PRNG state'
    );

    my %metadata = (
        parameters     => \%params_per_sub,
        format_choices => [bless ({
                name        => 'format',
                label_text  => 'Format to use',
                type        => 'choice',
                choices     => \@formats,
                default     => 0
            }, $parameter_metadata_class),
        ],
        format_labels  => \%format_labels,
    ); 

    return $export_metadata_class->new(\%metadata);
}

sub export {
    my $self = shift;
    my %args = @_;

    #  get our own metadata...
    my $metadata = $self->get_metadata (sub => 'export');

    my $sub_to_use = $metadata->get_sub_name_from_format (%args);

    eval {$self->$sub_to_use (%args)};
    croak $EVAL_ERROR if $EVAL_ERROR;

    return;
}

sub get_metadata_export_prng_init_state {
    my $self = shift;

    my %args = (
        format => 'Initial PRNG state',
        parameters => [bless ({
                name       => 'file',
                type       => 'file'
            }, $parameter_metadata_class),
        ],
    );

    return wantarray ? %args : \%args;
}

sub export_prng_init_state {
    my $self = shift;
    my %args = @_;

    my $init_state = $self->get_param ('RAND_INIT_STATE');

    my $filename = $args{file};

    use Data::Dumper ();
    
    my $fh = $self->get_file_handle (file_name => $filename, mode => '>');
    print {$fh} Data::Dumper::Dumper ($init_state);
    $fh->close;

    say "[RANDOMISE] Dumped initial PRNG state to $filename";

    return;
}

sub get_metadata_export_prng_current_state {
    my $self = shift;

    my %args = (
        format => 'Current PRNG state',
        parameters => [bless ({
                name       => 'file',
                type       => 'file'
            }, $parameter_metadata_class),
        ],
    );

    return wantarray ? %args : \%args;
}

sub export_prng_current_state {
    my $self = shift;
    my %args = @_;

    my $init_state = $self->get_param ('RAND_LAST_STATE');

    my $filename = $args{file};

    use Data::Dumper ();
    my $fh = $self->get_file_handle (file_name => $filename, mode => '>');
    print {$fh} Data::Dumper::Dumper ($init_state);
    $fh->close;

    say "[RANDOMISE] Dumped current PRNG state to $filename";

    return;
}

sub get_default_rand_function {
    return 'rand_structured';
}

#  get a list of the all the publicly available randomisations.
sub get_randomisation_functions {
    my $self = shift || __PACKAGE__;

    my %analyses = $self->get_subs_with_prefix (
        prefix => 'rand_',
        class => __PACKAGE__,
    );
    
    return wantarray ? %analyses : \%analyses;
}

sub get_randomisation_functions_as_array {
    my $self = shift || __PACKAGE__;

    my @analyses = $self->get_subs_with_prefix_as_array (
        prefix => 'rand_',
        class => __PACKAGE__,
    );

    return wantarray ? @analyses : \@analyses;
}

sub check_rand_function_is_valid {
    my $self = shift;
    my %args = @_;
    
    my $function = $args{function} // '';

    my %rand_functions = $self->get_randomisation_functions;

    my $valid = exists $rand_functions{$function};

    croak "Randomisation function $function is not one of "
          . join (', ', sort keys %rand_functions)
          . "\n"
      if !$valid;

    return 1;
}

sub get_analysis_args {
    my $self = shift;
    return $self->get_param('ARGS');
}

sub set_analysis_args {
    my ($self, $args) = @_;
    $self->set_param (ARGS => $args);
}

#  set any defaults if the user has not specified them as arg hash keys
sub set_default_args {
    my ($self, %args) = @_;

    my $function  = $args{function} || $self->get_param('FUNCTION');
    my $args_hash = $args{args_hash} // {};
    
    my $metadata = $self->get_metadata(sub => $function);
    
    my $params = $metadata->get_parameters;
    foreach my $p (@$params) {
        my $p_name = $p->get_name;
        if (!exists $args_hash->{$p_name}) {
            my $default = $p->get_default_param_value;
            $args_hash->{$p_name} = $default;
        }
    }

    return $args_hash;
}

#####################################################################
#
#  run the randomisation analysis for a set number of iterations,
#  comparing a set of spatial and tree objects in the basedata object

sub run_analysis {  #  flick them straight through
    my $self = shift;

    my $success = eval {$self->run_randomisation  (@_)};
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $success;
}

sub run_randomisation {
    my $self = shift;
    my %args = @_;

    my $start_time = time();

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');

    my $function = $self->get_param ('FUNCTION')
                   // $args{function}
                   // croak "Randomisation function not specified\n";
    $self->check_rand_function_is_valid (function => $function);

    delete $args{function};  #  don't want to pass unnecessary args on to the function
    $self->set_param (FUNCTION => $function);  #  store it

    my $iterations = delete $args{iterations} || 1;
    my $max_iters  = delete $args{max_iters};

    #print "\n\n\nMAXITERS IS $max_iters\n\n\n";
    my $generate_tree_analyses = !!$args{build_randomised_trees};

    #  load any predefined args, overriding user specified ones
    #  unless they are flagged as mutable.
    if (my $ref = $self->get_analysis_args) {
        my $metadata = $self->get_metadata (sub => $function);
        my $params = $metadata->get_parameters;
        my %mutables;
        foreach my $p (@$params) {
            next if !$p->get_mutable;
            my $name = $p->get_name;
            $mutables{$name} = $args{$name};
        }
        %args = %$ref;
        @args{keys %mutables} = values %mutables;
    }
    else {
        $self->set_default_args (function => $function, args_hash => \%args);
    }
    $self->set_analysis_args (\%args);
    
    #  dirty hack for short term back compat
    #$args{spatial_conditions_for_subset} //= $args{spatial_condition};
    croak "spatial_condition argument is deprecated - use spatial_conditions_for_subset\n"
      if defined $args{spatial_condition};
      
    if (defined $args{save_checkpoint}) {
        $self->verify_cwd_is_writeable_for_checkpoints (
            save_checkpoint => $args{save_checkpoint},
        );
    }

    my $rand_object = $self->initialise_rand (%args);

    #  get a list of refs for objects that are to be compared
    #  get the lot by default
    my @targets = defined $args{targets}
                ? @{$args{targets}}
                : ($bd->get_cluster_output_refs,
                   $bd->get_spatial_output_refs,
                   );
    delete $args{targets};
    @targets = natkeysort {$_->get_name} @targets;

    #  loop through and get all the key/value pairs that are not refs.
    #  Assume these are arguments to the randomisation
    my $scalar_args = $EMPTY_STRING;
    foreach my $key (sort keys %args) {
        my $val = $args{$key};
        $val //= 'undef';
        if (not ref ($val)) {
            $scalar_args .= "$key=>$val,";
        }
    }
    $scalar_args =~ s/,$//;  #  remove any trailing comma
    #say "\n\n++++++++++++++++++++++++";
    #say '[RANDOMISE] Scalar arguments are ' . $scalar_args;
    #say "++++++++++++++++++++++++\n\n";

    my $results_list_name
        = $self->get_param ('NAME')
        || $args{results_list_name}
        || uc (
            $function   #  add the args to the list name
            . (length $scalar_args
                ? "_$scalar_args"
                : $EMPTY_STRING)
            );


    #  counts are stored on the outputs, as they can be different if
    #    an output is created after some randomisations have been run
    my $rand_iter_param_name = "RAND_ITER_$results_list_name";

    my $total_iterations = $self->get_param_as_ref ('TOTAL_ITERATIONS');
    if (! defined $total_iterations) {
        $self->set_param (TOTAL_ITERATIONS => 0);
        $total_iterations = $self->get_param_as_ref ('TOTAL_ITERATIONS');
    }

    my $return_success_code = 1;
    my $add_basedatas_to_project = $args{add_basedatas_to_project};
    my $return_rand_bd_array = $args{return_rand_bd_array} || $add_basedatas_to_project;
    my @rand_bd_array;  #  populated if return_rand_bd_array is true
    my $retain_outputs = $args{retain_outputs} || $add_basedatas_to_project;

    my $progress_bar = Biodiverse::Progress->new(text => 'Randomisation');

    my %progress_timers;
    #  arbitrary threshold but should be OK
    my $no_gui_progress_thresh = 1;

    #  do stuff here
    ITERATION:
    foreach my $i (1 .. $iterations) {

        if ($max_iters && $$total_iterations >= $max_iters) {
            say "[RANDOMISE] Maximum iteration count reached: $max_iters";
            $return_success_code = 2;
            last ITERATION;
        }

        $$total_iterations++;

        say "[RANDOMISE] $results_list_name iteration $$total_iterations "
            . "($i of $iterations this run)";

        $progress_bar->update (
            "Randomisation iteration $i of $iterations this run",
            ($i / $iterations),
        );

        my $start_time_get_rand_bd = [gettimeofday];

        my $rand_bd = eval {
            $self->get_randomised_basedata (
                %args,
                rand_object     => $rand_object,
                rand_iter       => $$total_iterations,
                rand_function   => $function,
                no_gui_progress => (($progress_timers{gen_bd} // 1000) / $i < $no_gui_progress_thresh),
            );
        };
        croak $EVAL_ERROR if $EVAL_ERROR || ! defined $rand_bd;

        my $t_diff = tv_interval ($start_time_get_rand_bd);
        my $time_taken = sprintf "%.3f", $t_diff;
        say "[RANDOMISE] Time taken to randomise basedata: $time_taken seconds";

        $progress_timers{gen_bd} += $t_diff;

        $rand_bd->rename (
            name => join ('_', $bd->get_param ('NAME'), $function, $$total_iterations),
        );

        my %randomised_arg_object_cache;

        TARGET:
        foreach my $target (@targets) {
            my $rand_analysis;
            say "target: ", $target->get_param ('NAME') || $target;

            next TARGET if ! defined $target;
            if (! $target->can('run_analysis')) {
                #if (! $args{retain_outputs}) {
                #    $rand_bd->delete_output (output => $rand_analysis);
                #}
                next TARGET;
            }
            #  allow for older versions that did not flag this
            my $completed = $target->get_param ('COMPLETED') // 1;

            next TARGET if not $completed;  # skip this one, no analyses that worked

            my $name
                = $target->get_param ('NAME') . " Randomise $$total_iterations";
            my $progress_text
                = $target->get_param ('NAME') . "\nRandomise $$total_iterations";

            #  create a new object of the same class
            my %params = $target->get_params_hash;

            #  create the object and add it
            $rand_analysis = ref ($target)->new (
                %params,
                NAME => $name,
            );

            my $check = $rand_bd->add_output (
                #%params,
                name    => $name,
                object  => $rand_analysis,
            );

            #  ensure we use the same PRNG sequence and recreate cluster matrices
            #  HACK...
            my $rand_state = $target->get_param('RAND_INIT_STATE') || [];
            $rand_analysis->set_param(RAND_LAST_STATE => [@$rand_state]);
            my $generate_rand_analysis = 1;
            my $is_tree_object = eval {$rand_analysis->is_tree_object};
            if ($is_tree_object) {
                $rand_analysis->delete_params (qw/ORIGINAL_MATRICES ORIGINAL_SHADOW_MATRIX/);
                eval {$rand_analysis->override_cached_spatial_calculations_arg};  #  override cluster calcs per node
                $rand_analysis->set_param(NO_ADD_MATRICES_TO_BASEDATA => 1);  #  Avoid adding cluster matrices
                $generate_rand_analysis = !!($generate_tree_analyses // 0);
            }

            if ($generate_rand_analysis) {
                my $start_time_analysis = [gettimeofday()];
                my %prog_args = (
                    no_gui_progress => (($progress_timers{$target} // 1000) / $i < $no_gui_progress_thresh)
                );

                eval {
                    $self->override_object_analysis_args (
                        %args,
                        randomised_arg_object_cache => \%randomised_arg_object_cache,
                        object      => $rand_analysis,
                        rand_object => $rand_object,
                        iteration   => $$total_iterations,
                        %prog_args,
                    );
                };
                croak $EVAL_ERROR if $EVAL_ERROR;

                eval {
                    $rand_analysis->run_analysis (
                        progress_text   => $progress_text,
                        use_nbrs_from   => $target,
                        %prog_args,
                    );
                };
                croak $EVAL_ERROR if $EVAL_ERROR;

                eval {
                    $target->compare (
                        comparison       => $rand_analysis,
                        result_list_name => $results_list_name,
                        %prog_args,
                    )
                };
                croak $EVAL_ERROR if $EVAL_ERROR;

                $progress_timers{$target} += tv_interval ($start_time_analysis);
            }

            #  Does nothing if not a cluster type analysis
            eval {
                $self->compare_cluster_calcs_per_node (
                    orig_analysis  => $target,
                    rand_bd        => $rand_bd,
                    rand_iter      => $$total_iterations,
                    retain_outputs => $retain_outputs,
                    result_list_name => $results_list_name,
                );
            };
            croak $EVAL_ERROR if $EVAL_ERROR;

            #  and now remove this output to save a bit of memory
            #  unless we've been told to keep it
            #  (this has not been exposed to the GUI yet)
            if (!$retain_outputs) {
                #$rand_bd->delete_output (output => $rand_analysis);
                $rand_bd->delete_all_outputs();
            }
        }

        #  this argument is not yet exposed to the GUI
        if ($args{save_rand_bd}) {
            say "[Randomise] Saving randomised basedata";
            $rand_bd->save;
        }
        if ($return_rand_bd_array) {
            if ($add_basedatas_to_project) {
                if (scalar @rand_bd_array <= $add_basedatas_to_project) {
                    push @rand_bd_array, $rand_bd;
                }
            }
            else {
                push @rand_bd_array, $rand_bd;
            }
        }
        
        #  save incremental basedata file
        if (   defined $args{save_checkpoint}
            && $$total_iterations =~ /$args{save_checkpoint}$/
            ) {

            say "[Randomise] Saving incremental basedata";
            my $file_name = $bd->get_param ('NAME');
            $file_name .= '_' . $function . '_iter_' . $$total_iterations;
            eval {
                $bd->save (filename => $file_name);
            };
            croak $EVAL_ERROR if $EVAL_ERROR;
        }
    }

    #  now we're done, increment the randomisation counts
    #  Not sure why - possibly a left-over from when we allowed subsets to be checked
    foreach my $target (@targets) {
        my $count = $target->get_param ($rand_iter_param_name) || 0;
        $count += $iterations;
        $target->set_param ($rand_iter_param_name => $count);
        if ($target->can ('clear_lists_across_elements_cache')) {
            $target->clear_lists_across_elements_cache;
        }
        $target->delete_cached_value ('METADATA_CACHE');  #  avoid export issues in the GUI
    }
    
    #  now update the sig thresholds
    my @methods = qw /
      convert_comparisons_to_significances
      convert_comparisons_to_zscores
      calculate_canape
    /;

    foreach my $target (@targets) {
        foreach my $method (@methods) {
            if ($target->can($method)) {
                $target->$method (result_list_name => $results_list_name);
            }
        }
    }

    #  and keep a track of the randomisation state,
    #  even though we are storing the object
    #  this is just in case YAML will not work with MT::Auto
    $self->store_rand_state (rand_object => $rand_object);

    say sprintf
        "[RANDOMISATION] Time taken for %i iterations: %f seconds",
        $iterations, time - $start_time;

    #  return the rand_bd's if told to
    return (wantarray ? @rand_bd_array : \@rand_bd_array)
      if $return_rand_bd_array;
    
    #  return 1 if successful and ran some iterations
    #  return 2 if successful but did not need to run anything
    return $return_success_code;
}


sub verify_cwd_is_writeable_for_checkpoints {
    my ($self, %args) = @_;
    
    if (   defined $args{save_checkpoint}
        && $args{save_checkpoint} >= 0) {
        use Cwd;
        my $cwd = getcwd() // '';
        my $file_name
          = $self->get_basedata_ref->get_param ('NAME')
          . '.bds.tmp';
        my $fh = eval {
            $self->get_file_handle (
                file_name => $file_name,
                mode      => '>',
            );
        };
        if (my $e = $@) {
            croak "Unable to save checkpoint files to current working directory\n"
                . "(Currently in $cwd)\n"
                . "Are you sure you need these files?\n"
                . $e;
        }
        $fh->close;
        $self->unlink_file(file_name => $file_name)
          or croak "unable to delete test file $file_name";
    }
    return 1;
}

sub _parse_labels_not_to_randomise {
    my ($self, %args) = @_;

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');
    my $constant_labels = $args{labels_not_to_randomise};

    return if !$constant_labels;

    state $cache_key = 'CONSTANT_LABELS_ARRAY';
    if (my $cache = $self->get_cached_value ($cache_key)) {
        $constant_labels = $cache;
    }
    elsif (!is_ref $constant_labels) {
        $constant_labels = [split /[\r\n]+/, $constant_labels];
        #  Maybe we were passed a list of key value pairs
        #  This can happen with pasting from GUI popups
        my $label1 = $constant_labels->[0];
        #  copy-pasted from a GUI cell popup
        if (!$bd->exists_label(label => $label1) && $label1 =~ /(.+)\t+\d+$/) {
            if ($bd->exists_label(label => $1)) {
                for my $label (@$constant_labels) {
                    $label =~ s/\s+\d+$//;
                }
            }
        }
        my $n = max (4, $#$constant_labels);
        say "[Randomise] Constant labels, first 0..$n are "
            . join ' ', @$constant_labels[0 .. $n];
    }

    $self->set_cached_value ($cache_key => $constant_labels);

    return wantarray ? @$constant_labels : $constant_labels;
}

sub get_randomised_basedata {
    my $self = shift;
    my %args = @_;

    #  no need to generate a separate set if no labels to hold constant
    return $self->_get_randomised_basedata (%args)
      if !$args{labels_not_to_randomise};

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');
    my $constant_labels = $self->_parse_labels_not_to_randomise(%args);

    state $cache_key_const_bd = 'CONSTANT_LABELS_CONST_BASEDATA';
    state $cache_key_rand_bd  = 'CONSTANT_LABELS_RAND_BASEDATA';

    my $const_bd     = $self->get_cached_value ($cache_key_const_bd);
    my $non_const_bd = $self->get_cached_value ($cache_key_rand_bd);

    if (!$const_bd && !$non_const_bd) {
        $const_bd     = Biodiverse::BaseData->new($bd->get_params_hash);
        $non_const_bd = Biodiverse::BaseData->new($bd->get_params_hash);

        $const_bd->rename(new_name => $const_bd->get_name . ' constant label subset');
        $non_const_bd->rename(new_name => $non_const_bd->get_name . ' random label subset');

        my $csv_object = $bd->get_csv_object(
            sep_char   => $bd->get_param('JOIN_CHAR'),
            quote_char => $bd->get_param('QUOTES'),
        );

        my %const_label_hash;
        @const_label_hash{@$constant_labels} = undef;
        for my $label ($bd->get_labels) {
            my $groups = $bd->get_groups_with_label_as_hash_aa($label);

            #  we should cache the constant BD
            my $target_bd = exists $const_label_hash{$label} ? $const_bd : $non_const_bd;
            $target_bd->add_elements_collated_by_label(
                data       => { $label => $groups },
                csv_object => $csv_object,
            );
        }
        foreach my $empty_gp ($bd->get_empty_groups) {
            $const_bd->add_element(
                group              => $empty_gp,
                count              => 0,
                allow_empty_groups => 1,
            );
        }

        $const_bd->rebuild_spatial_index;
        $non_const_bd->rebuild_spatial_index; #  sometimes the non_const basedata is "missing" groups

        $self->set_cached_value ($cache_key_const_bd => $const_bd);
        $self->set_cached_value ($cache_key_rand_bd  => $non_const_bd);
    }

    #  randomise the "randomisable" one
    my $new_rand_bd = $self->_get_randomised_basedata (%args, basedata_ref => $non_const_bd);

    #  add the constant labels
    $new_rand_bd->merge (from => $const_bd);

    return $new_rand_bd;
}


#  need to rename this
sub _get_randomised_basedata {
    my $self = shift;
    my %args = @_;
    
    my $rand_bd;
    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');

    #  do we have one or more valid conditions which imply a subset is needed?
    my $using_subsets
      = join '',
        map {$_ // ''}
        @args{qw /spatial_conditions_for_subset definition_query/};
    $using_subsets =~ s/\s//g;

    if (length $using_subsets) {
        $rand_bd = $self->get_rand_structured_subset(%args);
        $bd->transfer_label_properties (
            %args,
            receiver => $rand_bd,
        );
    }
    else {
        my $function = $args{rand_function};
        $rand_bd = $self->$function(%args);
        $self->process_group_props (
            orig_bd  => $bd,
            rand_bd  => $rand_bd,
            function => $args{randomise_group_props_by},
            rand_object => $args{rand_object},
        );
    }

    return $rand_bd;
}

#  here is where we can hack into the args and override any trees etc
#  (but just trees for now)
sub override_object_analysis_args {
    my $self = shift;
    my %args = @_;

    my $object = $args{object};
    my $cache  = $args{randomised_arg_object_cache};
    my $iter   = $args{iteration};

    #  get a shallow clone
    my ($p_key, $new_analysis_args) = $self->get_analysis_args_from_object (
        object => $object,
    );

    my $made_changes;

    #  The following process could be generalised to handle any of the object types

    my $tree_shuffle_method = $args{randomise_trees_by} // q{};
    if ($tree_shuffle_method && $tree_shuffle_method !~ /^shuffle_/) {  #  add the shuffle prefix if needed
        $tree_shuffle_method = 'shuffle_' . $tree_shuffle_method;
    }

    my $tree_ref_used = $new_analysis_args->{tree_ref};

    if ($tree_ref_used && $tree_shuffle_method && $tree_shuffle_method !~ /no_change$/) {
        my $shuffled_tree = $cache->{$tree_ref_used};
        if (!$shuffled_tree) {  # shuffle and cache if we don't already have it
            $shuffled_tree = $tree_ref_used->clone;
            $shuffled_tree->$tree_shuffle_method (%args);
            $shuffled_tree->rename (
                new_name => $shuffled_tree->get_param ('NAME') . ' ' . $iter,
            );
            $cache->{$tree_ref_used} = $shuffled_tree;
        }
        $new_analysis_args->{tree_ref} = $shuffled_tree;
        $made_changes++;
    }

    return 1 if ! $made_changes;

    $object->set_param ($p_key => $new_analysis_args);

    return 1;
}

#  should be in Biodiverse::Common, or have a method per class  
sub get_analysis_args_from_object {
    my $self = shift;
    my %args = @_;
    
    my $object = $args{object};

    my $get_copy = $args{get_copy} // 1;

    my $analysis_args;
    my $p_key;
  ARGS_PARAM:
    for my $key (qw/ANALYSIS_ARGS SP_CALC_ARGS/) {
        $analysis_args = $object->get_param ($key);
        $p_key = $key;
        last ARGS_PARAM if defined $analysis_args;
    }

    croak 'Unable to find analysis args for output ' . $object->get_name
      if !$analysis_args;

    my $return_hash = $get_copy ? {%$analysis_args} : $analysis_args;

    my @results = (
        $p_key,
        $return_hash,
    );

    return wantarray ? @results : \@results;
}

#  need to ensure we re-use the original nodes for the randomisation test
sub compare_cluster_calcs_per_node {
    my $self = shift;
    my %args = @_;

    my $orig_analysis = $args{orig_analysis};
    my $analysis_args = $orig_analysis->get_param ('ANALYSIS_ARGS');

    return if ! eval {$orig_analysis->is_tree_object};
    return if !defined $analysis_args->{spatial_calculations};

    my $bd      = $orig_analysis->get_basedata_ref;
    my $rand_bd = $args{rand_bd};

    #  Get a clone of the cluster tree and attach it to the randomised basedata
    #  Cloning via newick format clears all the params,
    #  so avoids lingering basedata refs and the like
    require Biodiverse::ReadNexus;

    my $read_nexus = Biodiverse::ReadNexus->new;
    $read_nexus->import_newick (data => $orig_analysis->to_newick);
    my @tree_array = $read_nexus->get_tree_array;
    my $clone = $tree_array[0];
    bless $clone, blessed ($orig_analysis);
    #  This is more direct but actually takes longer under profiling.
    #  Also does not clean out the previous lists.
    # my $clone = $orig_analysis->clone_without_caches;

    $clone->rename (new_name => $orig_analysis->get_param ('NAME') . ' rand sp_calc' . $args{rand_iter});
    my %clone_analysis_args = %$analysis_args;
    #$clone_analysis_args{spatial_calculations} = $args{spatial_calculations};
    if (exists $clone_analysis_args{basedata_ref}) {
        $clone_analysis_args{basedata_ref} = $rand_bd;  #  just in case
    }
    $clone->set_basedata_ref (BASEDATA_REF => $rand_bd);
    $clone->set_param (ANALYSIS_ARGS => \%clone_analysis_args);

    $clone->run_spatial_calculations (%clone_analysis_args);

    if ($args{retain_outputs}) {
        $rand_bd->add_output (object => $clone);
    }

    #  now we need to compare the orig and the rand
    my $result_list_name = $args{result_list_name};
    eval {
        $orig_analysis->compare (
            comparison       => $clone,
            result_list_name => $result_list_name,
            no_track_node_stats => 1,
        )
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $clone;
}


#####################################################################
#
#  a set of functions to return a randomised basedata object

sub get_common_rand_metadata {
    my $self = shift;

    my $subset_parameters = $self->get_metadata_get_rand_structured_subset;
    my $group_props_parameters  = $self->get_group_prop_metadata;
    my $tree_shuffle_parameters = $self->get_tree_shuffle_metadata;

    my @common = (
         bless ({
            name       => 'save_checkpoint',
            label_text => 'Save checkpoints',
            type       => 'integer',
            default    => -1,
            min        => -1,
            increment  =>  1,
            tooltip    => 'Any iteration ending in this number will be saved to disk as a bds file.  '
                        . 'Useful to check convergence if the randomisations are very slow or '
                        . 'to restart from a known point if the system crashes due to lack of memory. '
                        . 'Set to -1 to not use it.',
            mutable    => 1,
            box_group  => 'Debug',
        }, $parameter_metadata_class),
        bless ({
            name       => 'add_basedatas_to_project',
            label_text => 'Add basedatas to project',
            type       => 'integer',
            default    => 0,
            increment  => 1,
            tooltip    => 'Add the first "n" randomised basedatas and their outputs to the project',
            mutable    => 1,
            box_group  => 'Debug',
        }, $parameter_metadata_class),    
    );

    #@common = ();  #  override until we allow some args to be overridden on subsequent runs.
    push @common, (
        @$subset_parameters,
        {
            name       => 'labels_not_to_randomise',
            label_text => 'Labels to not randomise',
            type       => 'text',
            default    => '',
            tooltip    => 'List of labels to not randomise, one per line',
        },
        {
            name       => 'build_randomised_trees',
            label_text => 'Build randomised tree outputs',
            type       => 'boolean',
            default    => 0,
            box_group  => 'Miscellaneous',
            tooltip
              => 'Rebuild any tree structures such as '
               . 'cluster and region grower analyses. '
               . 'These can be slow, so this is off by default.',
        },
        $group_props_parameters,
        $tree_shuffle_parameters,
    );
    for (@common) {
        next if blessed $_;
        bless $_, $parameter_rand_metadata_class;
    }

    return wantarray ? @common : \@common;
}


sub get_common_rand_structured_metadata {
    my $self = shift;

    my $tooltip_mult =<<'END_TOOLTIP_MULT'
The target richness of each group in the randomised
basedata will be its original richness multiplied
by this value.
END_TOOLTIP_MULT
;

    my $tooltip_addn =<<'END_TOOLTIP_ADDN'
The target richness of each group in the randomised
basedata will be its original richness plus this value.

This is applied after the multiplier parameter so you have:
    target_richness = orig_richness * multiplier + addition.
END_TOOLTIP_ADDN
;

    # my $subset_parameters = $self->get_metadata_get_rand_structured_subset;
    # my $group_props_parameters  = $self->get_group_prop_metadata;
    # my $tree_shuffle_parameters = $self->get_tree_shuffle_metadata;
    my $common_metadata  = $self->get_common_rand_metadata;
    
    my @parameters = (
        # @$subset_parameters,
        {name       => 'richness_multiplier',
         type       => 'float',
         default    => 1,
         increment  => 1,
         tooltip    => $tooltip_mult,
         box_group  => 'Richness constraints',
        },
        {name       => 'richness_addition',
         type       => 'float',
         default    => 0,
         increment  => 1,
         tooltip    => $tooltip_addn,
         box_group  => 'Richness constraints',
         },
        # $group_props_parameters,
        # $tree_shuffle_parameters,
        @$common_metadata,
    );
    for (@parameters) {
        next if blessed $_;
        bless $_, $parameter_rand_metadata_class;
    }
    
    
    my $track_label_allocation_order = bless {
        name       => 'track_label_allocation_order',
        label_text => "Track label allocation order?",
        default    => 0,
        type       => 'boolean',
        tooltip    => 'Allows one to see the order in which labels were assigned to groups. '
                    . 'Negative values were swapped out after allocation, '
                    . "zero values were assigned via the swapping process used to reach the richness targets.\n"
                    . 'Has no effect if a subset spatial condition is used (see issue #588 for details).',
        mutable    => 1,
        box_group  => 'Debug',
    }, $parameter_rand_metadata_class;
    push @parameters, $track_label_allocation_order;

    return wantarray ? @parameters : \@parameters;
}

sub get_spatial_allocation_sp_condition_metadata {
    my $self = shift;

    my $spatial_condition_param = bless {
        name       => 'spatial_conditions_for_label_allocation',
        label_text => "Spatial condition\nto define target groups\naround a seed location",
        default    => 'sp_square_cell (size => 3)',
        #default    => 'sp_circle(radius => 300000)',
        type       => 'spatial_conditions',
        tooltip    => 'Labels will be assigned to groups within the specified '
                    . 'neighbourhood around a random seed location.  '
                    . 'A new seed location is selected when there are no more '
                    . 'neighbours to select from.',
    }, $parameter_rand_metadata_class;

    return $spatial_condition_param;
}

sub get_seed_location_sp_condition_metadata {
    my $self = shift;

    my $tooltip = <<~EOT
    Label allocation will start from a group that satisfies the condition.
    Leave blank to allow any group.
    EOT
    ;

    my $spatial_condition_param = bless {
        name       => 'spatial_conditions_for_seed_location',
        label_text => "Spatial condition\nto define seed locations",
        default    => '',
        type       => 'spatial_conditions',
        tooltip    => $tooltip,
    }, $parameter_rand_metadata_class;

    return $spatial_condition_param;
}

sub get_random_walk_backtracking_metadata {
    my $self = shift;

    my $bk_text = <<'EOB'
The spatially structured models will go back to a previously
assigned group when no neighbours of the current group can be assigned to. 
"from_end" goes back in reverse order of assignment, 
"from_start" goes back to the start of the sequence and works
forward, while "random" selects randomly from the previously assigned groups.
Has no effect on the proximity allocation model.
EOB
  ;

    my $backtracking = bless {
        name       => 'label_allocation_backtracking',
        label_text => "Backtracking",
        default    => 0,
        type       => 'choice',
        choices    => [qw /from_end from_start random/],
        tooltip    => $bk_text,
        box_group  => 'Spatial allocations',
    }, $parameter_rand_metadata_class;

    return $backtracking;
}

sub get_spatial_allocation_reseed_metadata {
    
    my $reseed = bless {
        name       => 'spatial_allocation_reseed_prob',
        label_text => "Reseed probability",
        default    => 0,
        type       => 'float',
        min        => 0,
        max        => 1,
        increment  => 0.001,
        digits     => 4,
        tooltip    => 'Probability of restarting the allocation process from a new seed location. '
                    . 'Evaluated after each label occurrence allocation, '
                    . 'with values drawn from a uniform random distribution. '
                    . 'Leave as 0 for it to have no effect.',
        box_group  => 'Spatial allocations',        
    }, $parameter_rand_metadata_class;

    return $reseed;
}

sub get_metadata_rand_nochange {
    my $self = shift;
    
    my $subset_parameters = $self->get_metadata_get_rand_structured_subset;
    my $group_props_parameters  = $self->get_group_prop_metadata;
    my $tree_shuffle_parameters = $self->get_tree_shuffle_metadata;
    my $common_metadata = $self->get_common_rand_metadata;

    my %metadata = (
        description => 'No change - just a cloned data set',
        parameters  => [
            @$subset_parameters,
            $group_props_parameters,
            $tree_shuffle_parameters,
            @$common_metadata,
        ],
    );

    return $self->metadata_class->new(\%metadata);
}

#  does not actually change anything - handy for cluster trees to try different selections
sub rand_nochange {
    my $self = shift;
    my %args = @_;

    say "[RANDOMISE] Running 'no change' randomisation";

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');

    #  create a clone with no outputs
    my $new_bd = $bd->clone (no_outputs => 1);

    return $new_bd;
}

sub get_metadata_rand_csr_by_group {
    my $self = shift;

    my $subset_parameters = $self->get_metadata_get_rand_structured_subset;
    my $group_props_parameters  = $self->get_group_prop_metadata;
    my $tree_shuffle_parameters = $self->get_tree_shuffle_metadata;
    my $common_metadata = $self->get_common_rand_metadata;


    my %metadata = (
        description => 'Complete spatial randomisation by group (currently ignores labels without a group)',
        parameters  => [
            @$subset_parameters,
            $group_props_parameters,
            $tree_shuffle_parameters,
            @$common_metadata,
        ],
    ); 

    return $self->metadata_class->new(\%metadata);
}

#  complete spatial randomness by group - just shuffles the subelement lists between elements
sub rand_csr_by_group {
    my $self = shift;
    my %args = @_;

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');

    my $progress_bar = Biodiverse::Progress->new(
        no_gui_progress => $args{no_gui_progress},
    );

    #  can't store MRMA objects to all output formats and then recreate
    my $rand = delete $args{rand_object};

    my $progress_text = "rand_csr_by_group: complete spatial randomisation\n";

    my $new_bd = blessed($bd)->new ($bd->get_params_hash);
    $new_bd->get_groups_ref->set_param ($bd->get_groups_ref->get_params_hash);
    $new_bd->get_labels_ref->set_param ($bd->get_labels_ref->get_params_hash);

    #  pre-assign the hash buckets to avoid rehashing larger structures
    $new_bd->set_group_hash_key_count (count => $bd->get_group_count);
    $new_bd->set_label_hash_key_count (count => $bd->get_label_count);

    my @orig_groups = sort $bd->get_groups;
    #  make sure shuffle does not work on the original data
    my $rand_order = $rand->shuffle ([@orig_groups]);

    say "[RANDOMISE] CSR Shuffling " . (scalar @orig_groups) . " groups";

    #print join ("\n", @candidates) . "\n";

    my $total_to_do = $#orig_groups;

    my $csv_object = $bd->get_csv_object (
        sep_char   => $bd->get_param('JOIN_CHAR'),
        quote_char => $bd->get_param('QUOTES'),
    );

    foreach my $i (0 .. $#orig_groups) {

        my $progress = $total_to_do <= 0 ? 0 : $i / $total_to_do;

        my $p_text
            = "$progress_text\n"
            . "Shuffling labels from\n"
            . "\t$orig_groups[$i]\n"
            . "to\n"
            . "\t$rand_order->[$i]\n"
            . "(element $i of $total_to_do)";

        $progress_bar->update (
            $p_text,
            $progress,
        );

        #  create the group (this allows for empty groups with no labels)
        $new_bd->add_element(
            group => $rand_order->[$i],
            csv_object => $csv_object,
        );

        #  get the labels from the original group and assign them to the random group
        my $labels = $bd->get_labels_in_group_as_hash_aa ($orig_groups[$i]);
        pairmap {$new_bd->add_element_simple_aa ($a, $rand_order->[$i], $b, $csv_object)} %$labels;
    }

    $bd->transfer_label_properties (
        %args,
        receiver => $new_bd,
    );

    return $new_bd;
}


sub get_spatial_output_to_track_allocations {
    my ($self, %args) = @_;

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');

    my $sp = $self->get_param('SPATIAL_OUTPUT_TO_TRACK_ALLOCATIONS');

    return $sp if $sp;

    my $time = sprintf "%.3f", time();
    $sp = $bd->add_spatial_output(name => 'spatial_output_to_track_allocations_' . $time);

    #  we need a "blank canvas"
    eval {
        $sp->run_analysis (
            spatial_conditions => ['sp_self_only()'],
            #calculations       => ['calc_richness'],  #  dummy run to avoid grief later
            calculations       => [],
            override_valid_analysis_check => 1,
            #calc_only_elements_to_calc    => 1,  #  really need to rename this undocumented arg
        );
    };
    my $e = $EVAL_ERROR;
    
    $bd->delete_output (output => $sp);
    
    croak $e if $e;

    $self->set_param(SPATIAL_OUTPUT_TO_TRACK_ALLOCATIONS => $sp);

    return $sp;
}

sub get_spatial_output_for_label_allocation {
    my ($self, %args) = @_;
    
    my $sp_conditions = $args{spatial_conditions_for_label_allocation};
    my $param_name = $args{param_name} // 'SPATIAL_OUTPUT_FOR_LABEL_ALLOCATION';
    
    return if !defined $sp_conditions;

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');
    
    #  GUI only handles one until we can generate a compound widget
    if (!ref $sp_conditions || blessed $sp_conditions) {
        $sp_conditions = [$sp_conditions];
    }

    #  Check the sp conditions
    #  If we get only whitespace and comments then default to selecting all groups
    my $sp_check_text = $sp_conditions->[0];
    $sp_check_text //= '';
    if (blessed ($sp_check_text)) {
        $sp_check_text = $sp_check_text->get_conditions_unparsed;
    }
    $sp_check_text =~ s/[\s\r\n]//g;  #  clear any whitespace
    $sp_check_text =~ s/^\s*#.*$//g;     #  and any comments

    return if !length $sp_check_text; #  all we had was whitespace and comments

    my $sp = $self->get_param($param_name);
    
    return $sp if $sp;

    my $time = sprintf "%.3f", time;
    $sp = $bd->add_spatial_output(name => 'spatial_output_for_label_allocation_' . $time);

    #  we only want the neighbour sets
    eval {
        $sp->run_analysis (
            spatial_conditions => $sp_conditions,
            #definition_query   => $def_query,  #  do we want a def query for this?  Prob not.  
            calculations       => [],
            override_valid_analysis_check => 1,
            elements_to_calc              => $args{elements_to_calc},
            calc_only_elements_to_calc    => 1,  #  really need to rename this undocumented arg
        );
    };
    my $e = $EVAL_ERROR;

    $bd->delete_output (output => $sp);
    
    croak $e if $e;

    $self->set_param($param_name => $sp);

    return $sp;
}

sub get_metadata_rand_random_walk {
    my $self = shift;

    my @parameters = $self->get_common_rand_structured_metadata;
    push @parameters, $self->get_spatial_allocation_sp_condition_metadata;
    push @parameters, $self->get_random_walk_backtracking_metadata;
    push @parameters, $self->get_spatial_allocation_reseed_metadata;

    my %metadata = (
        parameters  => \@parameters,
        description => "Randomly allocate labels to groups, using a "
                     . "random walk model from a seed location\n"
                     . 'but keep the richness of each group the same within '
                     . "some tolerance.\n"
                     . "Actually just a special case of the rand_spatially_structured "
                     . "model that always uses the random_walk allocation method.",
    );

    return $self->metadata_class->new(\%metadata);
}

#  just a wrapper method to simplify the metadata for rand_structured, and thus the GUI
sub rand_random_walk {
    my $self = shift;
    my %args = @_;
    $args{spatial_allocation_order} = 'random_walk';  #  override
    $args{backtracking} //= 'from_end';
    return $self->rand_structured (%args);
}

sub get_metadata_rand_diffusion {
    my $self = shift;

    my @parameters = $self->get_common_rand_structured_metadata;
    push @parameters, $self->get_spatial_allocation_sp_condition_metadata;
    push @parameters, $self->get_spatial_allocation_reseed_metadata;

    my %metadata = (
        parameters  => \@parameters,
        description => "Randomly allocate labels to groups, using a "
                     . "diffusion model from a seed location\n"
                     . 'but keep the richness of each group the same within '
                     . "some tolerance.\n"
                     . "Actually just a special case of the rand_spatially_structured "
                     . "model that always uses the diffusion allocation method.",
    );

    return $self->metadata_class->new(\%metadata);
}

#  just a wrapper method to simplify the metadata for rand_structured, and thus the GUI
sub rand_diffusion {
    my $self = shift;
    my %args = @_;
    $args{spatial_allocation_order} = 'diffusion';  #  override
    return $self->rand_structured (%args);
}

sub get_metadata_rand_spatially_structured {
    my $self = shift;

    my @parameters = $self->get_common_rand_structured_metadata;

    push @parameters, $self->get_spatial_allocation_sp_condition_metadata;

    my $spatial_allocation_order = bless {
        name       => 'spatial_allocation_order',
        label_text => "Spatial allocation order",
        default    => 0,
        type       => 'choice',
        choices    => [qw /diffusion random_walk random proximity/],
        tooltip    => 'The order label occurrences will be allocated within the neighbourhoods '
                    . 'after first being allocated to the seed group.',
        box_group  => 'Spatial allocations',
    }, $parameter_rand_metadata_class;

    my $backtracking = $self->get_random_walk_backtracking_metadata;
    my $reseed       = $self->get_spatial_allocation_reseed_metadata;

    my $seed_condition = $self->get_seed_location_sp_condition_metadata;

    push @parameters, ($spatial_allocation_order, $backtracking, $seed_condition, $reseed);

    my %metadata = (
        parameters  => \@parameters,
        description => "Randomly allocate labels to groups, selecting "
                     . "new locations as a function of one or more spatial conditions\n"
                     . 'but keep the richness of each group the same within '
                     . 'some tolerance.',
    );

    return $self->metadata_class->new(\%metadata);
}

#  just a wrapper method to simplify the metadata for rand_structured, and thus the GUI
sub rand_spatially_structured {
    my $self = shift;
    my %args = @_;
    return $self->rand_structured (%args);
}

sub get_metadata_rand_structured {
    my $self = shift;

    my @parameters = $self->get_common_rand_structured_metadata;

    my %metadata = (
        parameters  => \@parameters,
        description => "Randomly allocate labels to groups,\n"
                     . 'but keep the richness the same or within '
                     . 'some multiplier factor.',
    );

    return $self->metadata_class->new(\%metadata);
}

sub sort_nbr_lists_by_proximity {
    my $self = shift;
    my %args = @_;
    
    my $target_element = $args{target_element};
    my $nbr_lists      = $args{nbr_lists};
    my $rand_object    = $args{rand_object};
    my $bd = $args{basedata_ref};

    my @proximity_sorted;
    
    foreach my $i (0 .. $#$nbr_lists) {
        @{$proximity_sorted[$i]} =
          map  { $_->[0] }
          sort { $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] || $a->[0] cmp $b->[0]}
          map  { [$_,
                  $self->get_element_proximity(
                    element1     => $_,
                    basedata_ref => $bd,
                    element2     => $target_element,
                  ),
                  $rand_object->rand,  #  fall back to random
                ]
               }
               @{$nbr_lists->[$i]};
    }

    return wantarray ? @proximity_sorted : \@proximity_sorted;
}

#  needs a lot more thought, and control over the axes to use
#  should also shift into Spatial.pm
sub get_element_proximity {
    my $self = shift;
    my %args = @_;

    my $gp = $args{basedata_ref}->get_groups_ref;
    my $el_array1 = $gp->get_element_name_as_array_aa($args{element1});
    my $el_array2 = $gp->get_element_name_as_array_aa($args{element2});

    my $dist = 0;
    foreach my $i (0 .. $#$el_array2) {
        #  skip non-numeric?
        #next if !(looks_like_number $el_array1->[$i]) || !(looks_like_number $el_array2->[$i]);
        $dist += ($el_array1->[$i] - $el_array2->[$i]) ** 2;
    }

    return sqrt $dist;
}

#  randomly allocate labels to groups, but keep the richness the same or within some multiplier
sub rand_structured {
    my $self = shift;
    my %args = @_;

    my $start_time = [gettimeofday];

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');

    #  can't store MRMA objects to all output formats and then recreate
    my $rand = delete $args{rand_object};  

    my $sp_for_label_allocation = $self->get_spatial_output_for_label_allocation (%args);

    my $spatial_allocation_order = $args{spatial_allocation_order} // '';
    my $label_alloc_backtracking = $args{label_allocation_backtracking} // '';
    #  currently only for debugging as basedata merging does not support outputs
    my $track_label_allocation_order = $args{track_label_allocation_order};

    my $reseed_prob;
    if ($sp_for_label_allocation) {
        $reseed_prob = $args{spatial_allocation_reseed_prob} || 0;
    }

    my $sp_alloc_nbr_list_cache = $self->get_cached_value ('sp_alloc_nbr_list_cache');
    if (!$sp_alloc_nbr_list_cache) {
        $sp_alloc_nbr_list_cache = {};
        $self->set_cached_value (sp_alloc_nbr_list_cache => $sp_alloc_nbr_list_cache);
    }
    #  avoid some duplication below when used
    my %sp_alloc_nbr_list_args = (
        cache          => $sp_alloc_nbr_list_cache,
        basedata_ref   => $bd,
        rand_object    => $rand,
        spatial_allocation_order  => $spatial_allocation_order,
        sp_for_label_allocation => $sp_for_label_allocation,
    );
    

    my $progress_bar = Biodiverse::Progress->new(no_gui_progress => $args{no_gui_progress});

    #  need to get these from the ARGS param if available
    #  - should also croak if negative
    my $multiplier = $args{richness_multiplier} // 1;
    my $addition = $args{richness_addition} || 0;
    my $name = $self->get_param ('NAME');

    my $progress_text =<<"END_PROGRESS_TEXT"
$name
rand_structured:
\trichness multiplier = $multiplier,
\trichness addition = $addition
END_PROGRESS_TEXT
;

    my $new_bd = blessed($bd)->new ($bd->get_params_hash);
    $new_bd->get_groups_ref->set_params ($bd->get_groups_ref->get_params_hash);
    $new_bd->get_labels_ref->set_params ($bd->get_labels_ref->get_params_hash);
    my $new_bd_name = $new_bd->get_param ('NAME');
    $new_bd->rename (name => $new_bd_name . "_" . $name);

    #  pre-assign the hash buckets to avoid rehashing larger structures
    $new_bd->set_group_hash_key_count (count => $bd->get_group_count);
    $new_bd->set_label_hash_key_count (count => $bd->get_label_count);

    #  populate a hash so we can use add_elements_collated
    my %new_bd_gp_lb_hash;

    #  for debug - create using $bd but we override later and set it to $new_bd
    my $sp_to_track_label_allocation_order
        = $track_label_allocation_order
            ? $self->get_spatial_output_to_track_allocations (%args)
            : undef;

    say '[RANDOMISE] Creating clone for destructive sampling';
    $progress_bar->update (
        "$progress_text\n"
        . "Creating clone for destructive sampling\n",
        0.1,
    );

    #  create a "clone" for destructive sampling
    #  (we used to use a cloned basedata object)
    \my %cloned_bd_as_lb_hash = $bd->get_labels_object_as_hash;
    my %cloned_bd_gps_remaining;

    $progress_bar->reset;

    #  make sure we randomly select from the same set of groups each time
    my @sorted_groups = sort $bd->get_groups;
    #  make sure shuffle does not work on the original data
    my $rand_gp_order = $rand->shuffle ([@sorted_groups]);

    my @sorted_labels = sort $bd->get_labels;
    #  make sure shuffle does not work on the original data
    my $rand_label_order = $rand->shuffle ([@sorted_labels]);

    printf "[RANDOMISE] Spatially structured shuffling %s labels from %s groups\n",
       scalar @sorted_labels, scalar @sorted_groups;

    #  generate a hash with the target richness values
    my %target_richness;
    my $i = 0;
    my $total_to_do = scalar @sorted_groups;

    #  %filled_groups is used to track richness targets
    #  Any zero richness targets can be treated as filled immediately
    my (%filled_groups, %unfilled_groups);
    my $bd_has_empty_groups;

    foreach my $group (@sorted_groups) {

        my $progress = $i / $total_to_do;

        my $gp_richness = $bd->get_richness_aa ($group) // 0;
        $cloned_bd_gps_remaining{$group} = $gp_richness;
        $bd_has_empty_groups ||= !$gp_richness;

        $progress_bar->update (
            "$progress_text\n"
            . "Assigning richness targets\n"
            . int (100 * $i / $total_to_do)
            . '%',
              $progress,
        );

        #  round down - could make this an option
        my $target_val = floor (
            $gp_richness
            * $multiplier
            + $addition
        );
        $target_richness{$group} = $target_val;
        if ($target_val) {
            $unfilled_groups{$group}++;
        }
        else {  #  handle empty groups without extra tracking hashes
            $filled_groups{$group} = 0;
            delete $cloned_bd_gps_remaining{$group};
        }
        $i++;
    }

    $progress_bar->reset;
    #  algorithm:
    #  pick a label at random and then scatter its occurrences across
    #  other groups that don't already contain it
    #  and which do not exceed the richness threshold
    #  (can be constrained by a spatial condition)

    my $tg = $bd->get_groups;
    my @target_groups = sort @$tg;  #  sort is prob redundant, as we overwrite @target_groups below
    my %all_target_groups;
    @all_target_groups{@target_groups} = ();
    my @unfilled_groups_sorted_arr = sort keys %unfilled_groups;
    my %new_bd_richness;
    my $last_filled     = $EMPTY_STRING;
    $i = 0;
    $total_to_do = scalar @$rand_label_order;
    say "[RANDOMISE] Target is $total_to_do.  Running.";

    my $csv_object = $bd->get_csv_object (
        sep_char   => $bd->get_param ('JOIN_CHAR'),
        quote_char => $bd->get_param ('QUOTES'),
    );

    BY_LABEL:
    foreach my $label (@$rand_label_order) {

        my $progress = $i / $total_to_do;
        $progress_bar->update (
            "Allocating labels to groups\n"
            . "$progress_text\n"
            . "($i / $total_to_do)",
            $progress,
        );

        $i++;

        @target_groups = @unfilled_groups_sorted_arr;
        my %cleared_target_gps;
        
        ###  get the remaining original groups containing the original label.
        ###  Make sure it's a copy
        \my %tmp_gp_hash = $cloned_bd_as_lb_hash{$label} // {};
        my $tmp_rand_order = $rand->shuffle ([sort keys %tmp_gp_hash]);

        my (
            %new_bd_additions,    %cloned_bd_deletions, @sp_alloc_nbr_list,
            $last_group_assigned, %assigned,
            %valid_nbrs,          @to_groups,
        );

        #  needed for when spatial allocations fill a nbrhood
        #  and we need to start from new nbrhood
        my $use_new_seed_group = 0;

        my %alloc_iter_hash = ();
        #  could generalise this name as it could be used for other cases 
        my $using_random_propagation = ($spatial_allocation_order =~ /^(?:random_walk|diffusion)$/);
        my %to_groups_hash;  #  used in the spatial allocations

      BY_GROUP:
        while (scalar @$tmp_rand_order && scalar @target_groups) {

            #  Should we always assign to the seed group?
            #  What if the seed group is not part of the nbr set?
            #  Issue is that the algorithm might never land on a valid target
            #  group given the selection process is only unfilled groups without the label
            #  For now we always assign to the seed group.

            if (!scalar @to_groups || $use_new_seed_group) {
                @to_groups = ();  #  clear any existing
                $use_new_seed_group = 0;  #  reset

                #  select a group at random to assign to
                my $j = int ($rand->rand (scalar @target_groups));
                push @to_groups, $target_groups[$j];

                #  make sure we don't select this group again
                #  for this label this time round
                splice (@target_groups, $j, 1);
                $cleared_target_gps{$to_groups[-1]}++;

                if ($sp_for_label_allocation) {
                    my $sp_alloc_nbr_list
                      = $sp_alloc_nbr_list_cache->{$to_groups[0]}
                        // $self->get_sp_alloc_nbr_list (
                            target_element => $to_groups[0],
                            %sp_alloc_nbr_list_args,
                        );

                    #  We currently concatenate all lists into one.
                    #  This won't work for the 'fill one, then the next' approaches
                    #  with multiple nbr sets
                  NBR_LIST_REF:
                    foreach my $list_ref (@{$sp_alloc_nbr_list}) {
                        my @sublist = grep
                          {   # exists $target_groups_hash{$_} &&
                              !exists $filled_groups{$_}
                           && !exists $assigned{$_}
                           && $_ ne $to_groups[0]
                          } @$list_ref;

                        if ($spatial_allocation_order eq 'diffusion') {
                            #  need uniques only for uniform random selection
                            @sublist = grep !exists $to_groups_hash{$_}, @sublist;
                        }

                        next NBR_LIST_REF if !scalar @sublist;

                        @to_groups_hash{@sublist} = undef;
                        push @to_groups,
                            $spatial_allocation_order =~ /^random/
                                ? @{$rand->shuffle (\@sublist)}
                                : @sublist;
                    }
                }
            }

            #  drop out criterion, occurs when $richness_multiplier < 1
            #  and we run out of groups to assign to
            last BY_GROUP if !scalar @to_groups;

          TO_GROUP_ITERATION:
            while (defined (my $to_group = shift @to_groups)) {

                last BY_GROUP if !scalar @$tmp_rand_order;
                #last BY_GROUP if not defined $to_group;  #  likely now?
                
                #  avoid double allocations
                next BY_GROUP if $using_random_propagation && exists $assigned{$to_group};

                my $from_group = shift @$tmp_rand_order;
                # my $count = $tmp_gp_hash{$from_group};
                my $count = delete $tmp_gp_hash{$from_group};

#say "Grabbing $label from $from_group with count $count";

                #  profiling suggests we get many $to_groups that
                #  are not in the array list so avoid some sub calls
                #  to save time.
                #  This is prob because the non-spatial allocations
                #  have already removed it when they are run.
                if (!exists $cleared_target_gps{$to_group}) {
                    bremove {$_ cmp $to_group} @target_groups;
                    $cleared_target_gps{$to_group}++;
                }

                warn "SELECTING GROUP THAT IS ALREADY FULL $to_group,"
                     . "$filled_groups{$to_group}, $target_richness{$to_group}, "
                     . "$i\n"
                        if defined $to_group and exists $filled_groups{$to_group};
                
                # Store the group/label count
                $new_bd_gp_lb_hash{$to_group}{$label} = $count;

                # book-keeping for debug, also an optional output
                if ($track_label_allocation_order) {
                    $alloc_iter_hash{$label}++;
                    $sp_to_track_label_allocation_order->add_to_lists (
                        element          =>  $to_group,
                        ALLOCATION_ORDER => {$label => $alloc_iter_hash{$label}},
                    );
                }

                $assigned{$to_group}++;

                #  now delete it from the list of candidates
                delete $cloned_bd_as_lb_hash{$label}{$from_group};
                delete $cloned_bd_as_lb_hash{$label}
                  if !keys %{$cloned_bd_as_lb_hash{$label}};
                #  decrement tracker and delete if now empty
                $cloned_bd_gps_remaining{$from_group}--;
                delete $cloned_bd_gps_remaining{$from_group}
                  if !$cloned_bd_gps_remaining{$from_group};

                #  increment richness and then check if we've filled this group.
                my $richness = ++$new_bd_richness{$to_group};

                if ($richness >= $target_richness{$to_group}) {

                    warn "ISSUES $to_group $richness > $target_richness{$to_group}\n"
                      if ($richness > $target_richness{$to_group});

                    $filled_groups{$to_group} = $richness;
                    delete $unfilled_groups{$to_group};
                    bremove {$_ cmp $to_group} @unfilled_groups_sorted_arr;
                    $last_filled = $to_group;
                };

                #  should we start from a new seed group?
                if ($reseed_prob && $rand->rand < $reseed_prob) {
                    $use_new_seed_group = 1;
                    last TO_GROUP_ITERATION;
                }

                #  should we find more local neighbours? 
                if ($using_random_propagation) {
                    #  unshift or push the neighbours of $to_group onto the targets
                    #  need to refactor this as there is duplication of code from above
                    my $sp_alloc_nbr_list
                      = $sp_alloc_nbr_list_cache->{$to_group}
                        // $self->get_sp_alloc_nbr_list (
                            target_element => $to_group,
                            %sp_alloc_nbr_list_args,
                        );

                    #  same concatenation probs as above
                    my $valid_nbr_count = 0;
                    my @nbr_sets = @{$sp_alloc_nbr_list};
                    if ($label_alloc_backtracking ne 'from_start') {
                        @nbr_sets = reverse @nbr_sets;
                    }
                  NBR_LIST_REF:
                    foreach my $list_ref (@nbr_sets) {
                        my @sublist = grep
                          {   # exists $target_groups_hash{$_} &&
                              !exists $filled_groups{$_}
                           && !exists $assigned{$_}
                           && $_ ne $to_group
                          } @$list_ref;

                        if ($spatial_allocation_order eq 'diffusion') {
                            #  need to ensure one entry for each group
                            #  for uniform random selection
                            @sublist = grep !exists $to_groups_hash{$_}, @sublist;
                        }

                        next NBR_LIST_REF if !scalar @sublist;

                        $valid_nbr_count += scalar @sublist;
                        @to_groups_hash{@sublist} = undef;

                        if ($spatial_allocation_order =~ /^random/) {
                            $rand->shuffle (\@sublist);
                        }
                        if ($label_alloc_backtracking eq 'from_start') {
                            push @to_groups, @sublist;          
                        }
                        else {
                            unshift @to_groups, @sublist;
                        }
                    }
                    #  We found no valid nbrs so we need to backtrack.
                    #  By default we will work backwards,
                    #  but if we are using random backtracking then we
                    #  need to select one and push it to the front.
                    if (    $spatial_allocation_order eq 'diffusion'
                        || (!$valid_nbr_count && $label_alloc_backtracking eq 'random')) {

                        if ($spatial_allocation_order ne 'diffusion') {
                        #  uniq ensures it is equal probability for each group
                        #  Needs to be faster, but we need to retain the order
                        #  for the random walk
                            @to_groups = uniq @to_groups;
                        }

                        my $k = int $rand->rand(scalar @to_groups);
                        my $target = $to_groups[$k];
                        splice @to_groups, $k, 1;
                        unshift @to_groups, $target;
                    }
                }

                #  move to next label if no more targets for this label
                last BY_GROUP if !scalar @target_groups;
            }
        }
    }

    #  now add the data to the basedata object
    $new_bd->add_elements_collated_simple_aa (
        \%new_bd_gp_lb_hash,
        $csv_object,
        $bd_has_empty_groups,  #  not sure there should be any at this point?
    );

    my $target_label_count = keys %cloned_bd_as_lb_hash;
    my $target_group_count = keys %cloned_bd_gps_remaining;

    my $format
        = "[RANDOMISE] \n"
          . "New: gps filled, gps unfilled. Old: labels to assign, gps not emptied\n"
          ."\t%d\t\t%d\t\t%d\t\t%d\n";

    printf $format,
           (scalar keys %filled_groups),
           (scalar keys %unfilled_groups),
           $target_label_count,
           $target_group_count;

    #  need to fill in the missing groups with empties
    if ($bd->get_group_count != $new_bd->get_group_count) {
        my %target_gps;
        @target_gps{$bd->get_groups} = ((undef) x $bd->get_group_count);
        delete @target_gps{$new_bd->get_groups};

        my $count = scalar keys %target_gps;
        say '[Randomise structured] '
              . "Creating $count empty groups in new basedata";

        foreach my $gp (keys %target_gps) {
            $new_bd->add_element (group => $gp, csv_object => $csv_object);
        }
    }


    $self->swap_to_reach_richness_targets (
        basedata_ref    => $bd,
        cloned_bd_as_lb_hash    => \%cloned_bd_as_lb_hash,
        cloned_bd_gps_remaining => \%cloned_bd_gps_remaining,
        new_bd          => $new_bd,
        filled_groups   => \%filled_groups,
        unfilled_groups => \%unfilled_groups,
        rand_object     => $rand,
        target_richness => \%target_richness,
        progress_text   => $progress_text,
        progress_bar    => $progress_bar,
    );

    $bd->transfer_label_properties (
        %args,
        receiver => $new_bd
    );

    my $time_taken = sprintf "%.3f", tv_interval ($start_time);
    my $function_name = $self->get_param('FUNCTION') // 'rand_structured';
    say "[RANDOMISE] Time taken for $function_name: $time_taken seconds";

    if ($track_label_allocation_order) {
        #  negate any swapped out labels and set any swapped in labels to 0
        no autovivification;
        my $sp = $sp_to_track_label_allocation_order;  #  shorthand
        EL:
        foreach my $el ($sp->get_element_list) {
            #next;  #  debug
            my $list_ref   = $sp->get_list_ref(
                list => 'ALLOCATION_ORDER',
                element => $el,
            );
            my $label_hash = $new_bd->get_labels_in_group_as_hash_aa($el);
            my %combined = (%$list_ref, %$label_hash);
            next EL if scalar (keys %combined) == scalar (keys %$list_ref)
                    && scalar (keys %combined) == scalar (keys %$label_hash); 
            foreach my $label (keys %combined) {
                if (exists $list_ref->{$label} && !exists $label_hash->{$label}) {
                    $list_ref->{$label} *= -1;  #  negate - we were swapped out
                }
                elsif (!exists $list_ref->{$label} && exists $label_hash->{$label}) {
                    $list_ref->{$label} = 0;    #  set to zero
                }
            }
        }
        #  now add it to the basedata
        $new_bd->add_spatial_output (
            name => 'sp_to_track_allocations',
            object => $sp_to_track_label_allocation_order,
        );
    }
    $self->delete_param('SPATIAL_OUTPUT_TO_TRACK_ALLOCATIONS');


    return $new_bd;
}

sub get_sp_alloc_nbr_list {
    my $self = shift;
    my %args = @_;

    my $target_element = $args{target_element}
      // croak "target_element argument is undefined\n";
    my $sp_alloc_nbr_list_cache  = $args{cache};
    my $spatial_allocation_order = $args{spatial_allocation_order};
    my $sp_for_label_allocation  = $args{sp_for_label_allocation}
      // croak "sp_for_label_allocation is undefined\n";

    #  we need a copy
    #  should cache and clone these to avoid re-sorting the same data
    my $sp_alloc_nbr_list = $sp_alloc_nbr_list_cache->{$target_element};
    
    return $sp_alloc_nbr_list if $sp_alloc_nbr_list;
    
    #  avoid double sorting as proximity does its own
    my $sort_lists = $spatial_allocation_order ne 'proximity';
    $sp_alloc_nbr_list
      = $sp_for_label_allocation->get_calculated_nbr_lists_for_element (
        element    => $target_element,
        sort_lists => $sort_lists,
    );
    if ($spatial_allocation_order eq 'proximity') {
        $sp_alloc_nbr_list = $self->sort_nbr_lists_by_proximity (
            %args,
            target_element => $target_element,
            nbr_lists      => $sp_alloc_nbr_list,
        );
    }
    $sp_alloc_nbr_list_cache->{$target_element} = $sp_alloc_nbr_list;                        

    return $sp_alloc_nbr_list;
}


sub get_metadata_get_rand_structured_subset {
    my $self = shift;

    my $parameters = [];

    my $spatial_condition_param = bless {
        name       => 'spatial_conditions_for_subset',
        label_text => "Spatial condition\nto define subsets",
        default    => '', #' ' x 30,  #  add spaces to get some widget width
        type       => 'spatial_conditions',
        tooltip    => 'Controls the spatial subsets used in the randomisation.  '
                    . 'Each subset is randomised independently, with the results '
                    . 'stitched back together before the analyses are run.'
                    . 'Subsets are forced to be non-overlapping, so conditions '
                    . 'such as sp_circle() will probably not work as desired.',
    }, $parameter_rand_metadata_class;
    push @$parameters, $spatial_condition_param;

    my $def_query_param = bless {
        name       => 'definition_query',
        label_text => "Definition query",
        default    => '',
        type       => 'spatial_conditions',
        tooltip    => 'Only groups that pass the definition query will have their labels randomised.',
    }, $parameter_rand_metadata_class;
    push @$parameters, $def_query_param;

    return wantarray ? @$parameters : $parameters;
}

sub get_rand_structured_subset {
    my $self = shift;
    my %args = @_;

    my $time = time;

    my $rand_function = $args{rand_function};

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');
    my $new_bd = Biodiverse::BaseData->new($bd->get_params_hash);
    
    my $def_query = $args{definition_query};

    my $progress_bar = Biodiverse::Progress->new();

    #  can't store MRMA objects to all output formats and then recreate
    my $rand_object = delete $args{rand_object};  

    my $sp = $self->get_param('SUBSET_SPATIAL_OUTPUT');
    #  build one if we don't have it cached
    if (!$sp) {
        my $name = "get nbrs for rand_structured_subset, $time" . $self->get_name;
        $sp = $bd->add_spatial_output (name => $name);

        my $sp_conditions = $args{spatial_conditions_for_subset};
        if (!is_arrayref ($sp_conditions)) {
            $sp_conditions = [$sp_conditions];
        }

        #  Check the sp conditions
        #  If we get only whitespace and comments then default to selecting all groups
        my $sp_check_text = $sp_conditions->[0];
        $sp_check_text //= '';
        if (blessed ($sp_check_text)) {
            $sp_check_text = $sp_check_text->get_conditions_unparsed;
        }
        $sp_check_text =~ s/[\s\r\n]//g;  #  clear any whitespace
        $sp_check_text =~ s/^#.*$//g;     #  and any comments
        if (!length $sp_check_text) {     #  all we had was whitespace and comments
            $sp_conditions->[0] = 'sp_select_all()';
        }

        #  truncate the spatial conditions, as we only use nbr set 1
        $sp_conditions = [$sp_conditions->[0]];

        #  we only want the neighbour sets
        $sp->run_analysis (
            spatial_conditions => $sp_conditions,
            definition_query   => $def_query,
            calculations       => [],
            override_valid_analysis_check => 1,
            calc_only_elements_to_calc    => 1,  #  really need to rename this undocumented arg
            #no_create_failed_def_query    => 1,
            #exclude_processed_elements    => 1,  #  has no effect on recycling?
        );

        $bd->delete_output (output => $sp);
        $self->set_param(SUBSET_SPATIAL_OUTPUT => $sp);
    }

    my $csv_object = $bd->get_csv_object (
        sep_char   => $bd->get_param('JOIN_CHAR'),
        quote_char => $bd->get_param('QUOTES'),
    );

    my $progress_text = 'Processing groups for structured subset randomisation';
    my $progress = Biodiverse::Progress->new (text => $progress_text);

    my %done;
    my @subset_basedatas;
    my $to_do = $bd->get_group_count;

    my $cached_subset_basedatas
      = $self->get_cached_value_dor_set_default_aa ('SUBSET_BASEDATAS', {});

    my $failed_def_query = $sp->get_groups_that_failed_def_query;
    my $bd_failed_def_query = $cached_subset_basedatas->{failed_def_query};

    if (!$bd_failed_def_query && $failed_def_query) {
        $bd_failed_def_query = Biodiverse::BaseData->new ($bd->get_params_hash);

        foreach my $nbr_group (keys %$failed_def_query) {
            my $tmp = $bd->get_labels_in_group_as_hash_aa ($nbr_group);
            $bd_failed_def_query->add_elements_collated (
                data => {$nbr_group => $tmp},
                csv_object => $csv_object,
                allow_empty_groups => 1,
            );
        }
        $bd_failed_def_query->rebuild_spatial_index;
        $cached_subset_basedatas->{failed_def_query} = $bd_failed_def_query;
    }
    if ($bd_failed_def_query) {
        my $gps = $bd_failed_def_query->get_groups;
        @done{@$gps} = (1) x scalar @$gps;

        push @subset_basedatas, $bd_failed_def_query;
        $self->process_group_props (
            orig_bd  => $bd,
            rand_bd  => $bd_failed_def_query,
            function => $args{randomise_group_props_by},
            rand_object => $rand_object,
        );
    }


  SUBSET_BD:
    foreach my $group (sort $bd->get_groups) {
        no autovivification;

        last SUBSET_BD if $to_do == scalar keys %done;
        next SUBSET_BD if exists $failed_def_query->{$group};

        my $subset_bd = $cached_subset_basedatas->{$group};

        if (!$subset_bd) {
            #  we need to build one
            my $nbrs = $sp->get_list_ref (
                element => $group,
                list    => '_NBR_SET1',
                autovivify => 0,
            ) // [];

            my @nbrs_to_check = grep !$done{$_}, @$nbrs;

            next SUBSET_BD if !scalar @nbrs_to_check;

            $progress->update ($progress_text, (scalar keys %done) / $to_do);

            $subset_bd = Biodiverse::BaseData->new ($bd->get_params_hash);
            $subset_bd->rename (new_name => "subset $group");

            for my $nbr_group (@nbrs_to_check) {
                my $tmp = $bd->get_labels_in_group_as_hash_aa ($nbr_group);
                $subset_bd->add_elements_collated (
                    data => {$nbr_group => $tmp},
                    csv_object => $csv_object,
                    allow_empty_groups => 1,
                );
            }
            $bd->transfer_group_properties (
                receiver => $subset_bd,
            );
            #  tests dont trigger index-related errors,
            #  but we need to play safe nonetheless
            $subset_bd->rebuild_spatial_index;
            $cached_subset_basedatas->{$group} = $subset_bd;
        }
        
        # say STDERR "Adding rand ", $self->get_name, " to basedata ", $subset_bd->get_name;
        my $subset_rand = $subset_bd->add_randomisation_output (name => $self->get_name);
        my $subset_rand_bd = $subset_rand->$rand_function (
            %args,
            rand_object  => $rand_object,
            basedata_ref => $subset_bd,
        );
        $self->process_group_props (
            orig_bd  => $subset_bd,
            rand_bd  => $subset_rand_bd,
            function => $args{randomise_group_props_by},
            rand_object => $rand_object,
        );

        my $gps = $subset_bd->get_groups;
        @done{@$gps} = (1) x scalar @$gps;

        push @subset_basedatas, $subset_rand_bd;

        #  Merge as we go - looks clunky but is useful for debug purposes
        #  Also shifts off the def query if one exists
        while (scalar @subset_basedatas) {
            my $subset = shift @subset_basedatas;
            say 'Merging basedata ' . $subset->get_name . ' into ' . $new_bd->get_name;
            $new_bd->merge (from => $subset);
        }

        #  keep the cached version clean of outputs
        $subset_bd->delete_all_outputs;
    }
    #  any left overs, i.e. where the spatial condition
    #  and def queires did not get all groups
    if ($to_do != scalar keys %done) {
        my $group = '__leftovers__';
        while ($bd->exists_group_aa($group)) {
            #  do not clash with pre-existing group name
            $group .= '!';
        }
        my $subset_bd = $cached_subset_basedatas->{$group};

        if (!$subset_bd) {
            my @nbrs_to_check = grep !exists $done{$_}, $bd->get_groups;
            $subset_bd = Biodiverse::BaseData->new ($bd->get_params_hash);
            $subset_bd->rename (new_name => "subset $group");

            for my $nbr_group (@nbrs_to_check) {
                my $tmp = $bd->get_labels_in_group_as_hash_aa ($nbr_group);
                $subset_bd->add_elements_collated (
                    data => {$nbr_group => $tmp},
                    csv_object => $csv_object,
                    allow_empty_groups => 1,
                );
            }
            $bd->transfer_group_properties (
                receiver => $subset_bd,
            );
            #  tests don't trigger index-related errors,
            #  but we need to play safe nonetheless
            $subset_bd->rebuild_spatial_index;
            $cached_subset_basedatas->{$group} = $subset_bd;
        }
        
        my $subset_rand = $subset_bd->add_randomisation_output (name => $self->get_name);
        my $subset_rand_bd = $subset_rand->$rand_function (
            %args,
            rand_object  => $rand_object,
            basedata_ref => $subset_bd,
        );
        $self->process_group_props (
            orig_bd  => $subset_bd,
            rand_bd  => $subset_rand_bd,
            function => $args{randomise_group_props_by},
            rand_object => $rand_object,
        );

        say 'Merging basedata ' . $subset_rand_bd->get_name . ' into ' . $new_bd->get_name;
        $new_bd->merge (from => $subset_rand_bd);

        #  keep the cached version clean of outputs
        $subset_bd->delete_all_outputs;
    }

    return $new_bd;
}

sub swap_to_reach_richness_targets {
    my $self = shift;
    my %args = @_;

    \my %cloned_bd_as_label_hash = $args{cloned_bd_as_lb_hash};
    \my %cloned_bd_gps_remaining = $args{cloned_bd_gps_remaining};

    #  avoid needless looping below.
    if (!keys %cloned_bd_as_label_hash) {
        $self->increment_param (SWAP_OUT_COUNT    => 0);
        $self->increment_param (SWAP_INSERT_COUNT => 0);
        return;
    }
    
    my $new_bd          = $args{new_bd};
    my %filled_groups   = %{$args{filled_groups}};  #  values are the richnesses - we use them to track empties
    my %unfilled_groups = %{$args{unfilled_groups}};
    my %target_richness = %{$args{target_richness}};
    my $rand            = $args{rand_object};
    my $progress_text   = $args{progress_text};
    my $progress_bar    = $args{progress_bar} // Biodiverse::Progress->new();

    my $bd = $args{basedata_ref} || $self->get_param ('BASEDATA_REF');
    

    my $csv_object = $bd->get_csv_object (
        sep_char   => $bd->get_param ('JOIN_CHAR'),
        quote_char => $bd->get_param ('QUOTES'),
    );

    #  and now we do some amazing cell swapping work to
    #  shunt labels in and out of groups until we're happy

    #  algorithm:
    #   Select an unassigned label.
    #   Find a group that does not contain it.
    #   Swap this label with one of the labels in the group if it is full.
    #   Repeat until we have no more to assign or all groups are full

    my $total_to_do =   (scalar keys %filled_groups)
                      + (scalar keys %unfilled_groups);

    if ($total_to_do) {
        say "[RANDOMISE] Swapping labels to reach richness targets";
    }

    my $swap_out_count = 0;
    my $swap_insert_count = 0;
    my $last_filled = $EMPTY_STRING;

    #  Track the labels in the unfilled groups.
    #  This avoids collating them every iteration.
    my (%labels_in_unfilled_gps,
        %unfilled_gps_without_label_lu,
        %unfilled_gps_without_label_by_gp,
    );

    my @sorted_bd_labels = sort $bd->get_labels; 
    foreach my $gp (sort keys %unfilled_groups) {
        \my %list = $new_bd->get_labels_in_group_as_hash_aa ($gp);
        foreach my $label (@sorted_bd_labels) {
            if (exists $list{$label}) {
                $labels_in_unfilled_gps{$label}++;
            }
            else {
                #  autovivs the arrays
                push @{$unfilled_gps_without_label_lu{$label}}, $gp;
                $unfilled_gps_without_label_by_gp{$gp}{$label}++;
            }
        }
    }
    #  avoid a heap of push calls by building the objects
    #  once the arrays are populated
    foreach my $label (keys %unfilled_gps_without_label_lu) {
        $unfilled_gps_without_label_lu{$label}
          = List::Unique::DeterministicOrder->new (
                data => $unfilled_gps_without_label_lu{$label},
            );
    }
    my $target_has_empty_gps = any {!$_} values %filled_groups;
    

    #  Track which groups do and don't have labels to avoid repeated and
    # expensive method calls to get_groups_with(out)_label_as_hash
    my %groups_without_labels_a;       #  store sorted arrays
    my %cloned_bd_groups_with_label_a;
    my %orig_bd_groups_with_label_a;
    my %new_bd_labels_in_gps_as_hash;
    my %new_bd_labels_in_gps_as_array;
    my $cloned_bd_label_arr = [sort keys %cloned_bd_as_label_hash];
    my %cloned_bd_label_hash;
    @cloned_bd_label_hash{@$cloned_bd_label_arr} = undef;

    #  keep refs of tracker hashes for debug purposes
    my %tracker_hashes = (
        labels_in_unfilled_gps           => \%labels_in_unfilled_gps,
        unfilled_gps_without_label_lu    => \%unfilled_gps_without_label_lu,
        unfilled_gps_without_label_by_gp => \%unfilled_gps_without_label_by_gp,
        groups_without_labels_a          => \%groups_without_labels_a,
        cloned_bd_groups_with_label_a    => \%cloned_bd_groups_with_label_a,
        orig_bd_groups_with_label_a      => \%orig_bd_groups_with_label_a,
        new_bd_labels_in_gps_as_hash     => \%new_bd_labels_in_gps_as_hash,
        new_bd_labels_in_gps_as_array    => \%new_bd_labels_in_gps_as_array,
        cloned_bd_label_hash             => \%cloned_bd_label_hash,
    );

    #  keep going until we've reached the fill threshold for each group
  BY_UNFILLED_GP:
    while (scalar keys %unfilled_groups) {

        my $target_label_count = keys %cloned_bd_as_label_hash;
        my $target_group_count = keys %cloned_bd_gps_remaining;

        my $p = '%8d';
        my $fmt = "Total gps:\t\t\t$p\n"
                . "Unfilled groups:\t\t$p\n"
                . "Filled groups:\t\t$p\n"
                . "Labels to assign:\t\t$p\n"
                . "Old gps to empty:\t$p\n"
                . "Swap count:\t\t\t$p\n";
        my $check_text
            = sprintf $fmt,
                $total_to_do,
                (scalar keys %unfilled_groups),
                (scalar keys %filled_groups),
                $target_label_count,
                $target_group_count,
                $swap_out_count;

        my $progress_i = scalar keys %filled_groups;
        my $progress = $progress_i / $total_to_do;
        $progress_bar->update (
            "Swapping labels to reach richness targets\n"
            . "$progress_text\n"
            . $check_text,
            $progress,
        );

        if (!$target_label_count) {
            #  we ran out of labels before richness criterion is met,
            #  eg if multiplier is >1.
            say "[Randomise structured] No more labels to assign";
            last BY_UNFILLED_GP;
        }

        #  select an unassigned label and group pair
        my $i = int $rand->rand (scalar @$cloned_bd_label_arr);
        my $add_label = $cloned_bd_label_arr->[$i];

        my $from_groups_hash
            = $cloned_bd_as_label_hash{$add_label};
        my $from_cloned_groups_tmp_a = $cloned_bd_groups_with_label_a{$add_label};
        if (!$from_cloned_groups_tmp_a  || !scalar @$from_cloned_groups_tmp_a) {
            my $gps_tmp = $cloned_bd_as_label_hash{$add_label};
            $from_cloned_groups_tmp_a
              = $cloned_bd_groups_with_label_a{$add_label}
              = [sort keys %$gps_tmp];
        };

        $i = int ($rand->rand (scalar @$from_cloned_groups_tmp_a));
        my $from_group = $from_cloned_groups_tmp_a->[$i];
        my $add_count  = $from_groups_hash->{$from_group};

        #  clear the pair out of cloned_self
        delete $cloned_bd_as_label_hash{$add_label}{$from_group};
        delete $cloned_bd_as_label_hash{$add_label}
          if !keys %{$cloned_bd_as_label_hash{$add_label}};
        $cloned_bd_gps_remaining{$from_group}--;
        delete $cloned_bd_gps_remaining{$from_group}
          if !$cloned_bd_gps_remaining{$from_group};
        bremove {$_ cmp $from_group} @$from_cloned_groups_tmp_a;
        if (!scalar @$from_cloned_groups_tmp_a) {
            delete $cloned_bd_groups_with_label_a{$add_label};
        }
        if (!exists $cloned_bd_as_label_hash{$add_label}) {
            bremove {$_ cmp $add_label} @$cloned_bd_label_arr;
            delete $cloned_bd_label_hash{$add_label};
        }

        #  Now add this label to a group that does not already contain it.
        #  Ideally we want to find a group that has not yet
        #  hit its richness target, but that is unlikely so we don't look anymore.
        #  Instead we select one at random.
        #  This also avoids the overhead of sorting and
        #  shuffling lists many times.

        my $target_groups_tmp_a = $groups_without_labels_a{$add_label};
        if (!$target_groups_tmp_a) {
            my $target_groups_tmp
              = $new_bd->get_groups_without_label_as_hash (label => $add_label);
            #  only use non-empty groups ($filled_groups{$_} != 0)
            my $tmp = $target_has_empty_gps
                ? [sort grep $filled_groups{$_}, keys %$target_groups_tmp]
                : [sort keys %$target_groups_tmp];
            $target_groups_tmp_a
              = $groups_without_labels_a{$add_label}
              = List::Unique::DeterministicOrder->new(data => $tmp);
        };
        #  cache maintains a sorted list, so no need to re-sort.  
        $i = int $rand->rand(scalar $target_groups_tmp_a->keys);
        my $target_group = $target_groups_tmp_a->get_key_at_pos ($i);

        my $target_gp_richness
          = $new_bd->get_richness_aa ($target_group) // 0;

        #  If the target group is at its richness threshold then
        #  we must first remove one label.
        #  Get a list of labels in this group and select one to remove.
        #  Preferably remove one that can be put into the unfilled groups.
        #  (Should move this to its own sub).
        if ($target_gp_richness >= $target_richness{$target_group})  {
            #  candidates to swap out are ideally
            #  those not in the unfilled groups

            #  we will remove one of these labels
            my $loser_labels
              = $new_bd->get_labels_in_group_as_hash_aa ($target_group);
            my $loser_labels_arr
                = $new_bd_labels_in_gps_as_array{$target_group}
                //= [sort keys %$loser_labels];
            #  debug code
            #my $loser_labels_arr2 = [sort keys %$loser_labels];
            #is_deeply ($loser_labels_arr, $loser_labels_arr2, 'gah!')
            # or <STDIN>;

            #  get those labels not in the unfilled groups
            my @loser_labels_filtered
              = sort grep !exists $labels_in_unfilled_gps{$_},
                @$loser_labels_arr;

            #  but select from all labels if all are in the unfilled groups
            #  (i.e. the filtered list is empty)
            my $loser_labels_array_to_use = scalar @loser_labels_filtered
                ? \@loser_labels_filtered
                : [@$loser_labels_arr];  #  could use directly if we modified use of shuffle below

            my $loser_labels_array_shuffled
                = $rand->shuffle ($loser_labels_array_to_use);

            #  now we loop over the labels and choose the first one that
            #  can be placed in an unfilled group,
            #  otherwise just take the first one

            #  set some defaults
            my $remove_label  = $loser_labels_array_shuffled->[0];
            my $removed_count = $loser_labels->{$remove_label};
            my $swap_to_unfilled = 0;

          BY_LOSER_LABEL:
            foreach my $label (@$loser_labels_array_shuffled) {
                #  Do we have any unfilled groups without this label?
                my $x_lu = $unfilled_gps_without_label_lu{$label};

                next BY_LOSER_LABEL if !$x_lu;

                $remove_label  = $label;
                $removed_count = $loser_labels->{$remove_label};
                $swap_to_unfilled = 1;
                last BY_LOSER_LABEL;
            }

            #  Remove it from $target_group in new_bd
            $new_bd->delete_sub_element_aa ($remove_label, $target_group);
            bremove {$_ cmp $remove_label}
              @{$new_bd_labels_in_gps_as_array{$target_group}};

            #  track the removal only if the tracker hash includes $remove_label
            #  else it will get it next time it needs it
            if (exists $groups_without_labels_a{$remove_label}) {
                #  need to insert into $groups_without_labels_a in sort order
                # binsert {$_ cmp $target_group} $target_group,
                #   @{$groups_without_labels_a{$remove_label}};
                $groups_without_labels_a{$remove_label}->push ($target_group);
            }
            #   unfilled_groups condition will never trigger in this if-branch
            #if (exists $unfilled_groups{$target_group}) {  
            #    $unfilled_gps_without_label{$remove_label}{$target_group}++;  #  breakage if ever it
            #}

            if (! $swap_to_unfilled) {
                #say ":: Swap to unfilled $remove_label";
                #  We can't swap it, so put it back into the
                #  unallocated lists.
                #  Use one of its old locations.
                #  (Just use the first one).
                my $old_gps_with_remove_label = $orig_bd_groups_with_label_a{$remove_label};
                if (!$old_gps_with_remove_label) {  #  These do not change so access and cache.  Sort is for repeatability.
                    my $gps = $bd->get_groups_with_label_as_hash_aa ($remove_label);
                    my @gps = sort keys %$gps;
                    $old_gps_with_remove_label = \@gps;
                    $orig_bd_groups_with_label_a{$remove_label} = $old_gps_with_remove_label;
                }

                \my %cloned_self_gps_with_label
                  = $cloned_bd_as_label_hash{$remove_label} // {};

                #  make sure it does not add to an existing case
                #delete @old_groups{keys %$cloned_self_gps_with_label};
                #my $old_gp = minstr keys %old_groups;
                #my $old_gp = minstr grep {!exists $cloned_self_gps_with_label->{$_}} keys %$old_gps_with_remove_label;
                my $old_gp;
              BY_GP:
                for my $gp (@$old_gps_with_remove_label) {
                    if (!exists $cloned_self_gps_with_label{$gp}) {
                        $old_gp = $gp;
                        last BY_GP;
                    }
                }
                $cloned_bd_as_label_hash{$remove_label}{$old_gp} = $removed_count;
                $cloned_bd_gps_remaining{$old_gp}++;
                binsert {$_ cmp $old_gp} $old_gp,
                  @{$cloned_bd_groups_with_label_a{$remove_label}};
                
                if (!exists $cloned_bd_label_hash{$remove_label}) {
                    binsert {$_ cmp $remove_label} $remove_label,
                      @$cloned_bd_label_arr;
                    $cloned_bd_label_hash{$remove_label}++;
                }
            }
            else {
                #  get a list of unfilled candidates to move it to
                #  do this by removing those that have the label
                #  from the list of unfilled groups

                my $unfilled_list = $unfilled_gps_without_label_lu{$remove_label}
                  // croak "ISSUES WITH RETURN GROUPS LIST DET\n";

                my $key_count = $unfilled_list->keys;

                croak "ISSUES WITH RETURN GROUP KEY COUNT\n$key_count\n"
                  if !$key_count;

                #  get one of the unfilled groups at random
                $i = int $rand->rand ($key_count);
                my $return_gp = $unfilled_list->delete_key_at_pos ($i);

                $new_bd->add_element_simple_aa (
                    $remove_label,  $return_gp,
                    $removed_count, $csv_object,
                );
                $swap_insert_count++;
                #  don't create the list here, and use postfix if to avoid scope creation
                binsert {$_ cmp $remove_label} $remove_label,
                  @{$new_bd_labels_in_gps_as_array{$return_gp}}
                    if exists $new_bd_labels_in_gps_as_array{$return_gp};

                my $new_richness = $new_bd->get_richness_aa ($return_gp);

                warn "ISSUES WITH RETURN $return_gp\n"
                  if $new_richness > $target_richness{$return_gp};

                $labels_in_unfilled_gps{$remove_label}++;

                delete $unfilled_gps_without_label_by_gp{$return_gp}{$remove_label};

                if (my $aref = $groups_without_labels_a{$remove_label}) {
                    # bremove {$_ cmp $return_gp} @$aref;
                    $aref->delete($remove_label);
                    delete $groups_without_labels_a{$remove_label}
                      if !scalar @$aref;
                }

                #  if we are now filled then update the tracking hashes
                if ($new_richness >= $target_richness{$return_gp}) {
                    $last_filled = $return_gp;
                    #  clean up the tracker hashes
                    $filled_groups{$last_filled} = $new_richness;
                    delete $unfilled_groups{$last_filled};
                    #  THIS NEXT LOOP IS A BOTTLENECK
                    #  when working with large data sets
                    #  List::Unique::DeterministicOrder is fastest so far,
                    #  but could we avoid indexing in the first place?
                    $unfilled_gps_without_label_lu{$_}->delete ($last_filled)
                      foreach keys %{$unfilled_gps_without_label_by_gp{$last_filled}};
                    delete $unfilled_gps_without_label_by_gp{$last_filled};
                  LB:
                    foreach my $label ($new_bd->get_labels_in_group (group => $last_filled)) {
                        #  don't decrement empties or about-to-be-empties
                        $labels_in_unfilled_gps{$label} <= 1
                            ? delete $labels_in_unfilled_gps{$label}
                            : $labels_in_unfilled_gps{$label}--;
                    }
                }
            }

            $swap_out_count ++;

            if (!($swap_out_count % 10000)) {
                say "Swap count $swap_out_count";
                #use Data::Dumper;
                #use Test::More;
                #local $Data::Dumper::Indent = 1;
                #local $Data::Dumper::Sortkeys = 1;
                #diag '=====';
                #diag Data::Dumper::Dumper \%tracker_hashes;
                #diag '=====';
                #my $x = <STDIN>;
            }
        }

        #  add the new label to new_bd
        $new_bd->add_element_simple_aa (
            $add_label, $target_group,
            $add_count, $csv_object,
        );
        $swap_insert_count++;
        if (exists $new_bd_labels_in_gps_as_array{$target_group}) {
            #  don't create the list here
            binsert {$_ cmp $add_label} $add_label,
              @{$new_bd_labels_in_gps_as_array{$target_group}};
        }
        if (my $aref = $groups_without_labels_a{$add_label}) {
            # bremove {$_ cmp $target_group} @$aref;
            $aref->delete ($target_group);
            delete $groups_without_labels_a{$add_label}
              if !scalar @$aref;  #  postfix to avoid scope creation
        }
        if (exists $unfilled_groups{$target_group}) {
            delete $unfilled_gps_without_label_by_gp{$target_group}{$add_label};
            $unfilled_gps_without_label_lu{$add_label}->delete ($target_group);
        }

        #  check if we've filled this group, if nothing was swapped out
        my $new_richness = $new_bd->get_richness_aa ($target_group) // 0;

        warn "ISSUES WITH TARGET $target_group\n"
          if $new_richness > $target_richness{$target_group};

        if (    $new_richness != $target_gp_richness 
            and $new_richness >= $target_richness{$target_group}) {

            $filled_groups{$target_group} = $new_richness;
            delete $unfilled_groups{$target_group};  #  no effect if it's not in the list
            $unfilled_gps_without_label_lu{$_}->delete ($target_group)
              foreach keys %{$unfilled_gps_without_label_by_gp{$target_group}};
            delete $unfilled_gps_without_label_by_gp{$target_group};
            $last_filled = $target_group;
        }
    }

    $self->increment_param (SWAP_OUT_COUNT    => $swap_out_count);
    $self->increment_param (SWAP_INSERT_COUNT => $swap_insert_count);

    say "[Randomise structured] Final swap count is $swap_out_count";

    return;
}


sub process_group_props {
    my $self = shift;
    my %args = @_;

    my $orig_bd = $args{orig_bd};
    my $rand_bd = $args{rand_bd};

    my @keys = $orig_bd->get_groups_ref->get_element_property_keys;

    return if !scalar @keys;

    my $function = $args{function};
    if (not $function =~ /^process_group_props_/) {
        $function = 'process_group_props_' . $function;
    }
    
    my $success = eval {$self->$function (%args)};
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $success;
}

sub process_group_props_no_change {
    my $self = shift;
    my %args = @_;

    my $orig_bd = $args{orig_bd};
    my $rand_bd = $args{rand_bd};

    $orig_bd->transfer_group_properties (
        %args,
        receiver => $rand_bd,
    );

    return;
}

#  move them around as a set of values, so the
#  receiving group gets all of the providing groups props
sub process_group_props_by_set {
    my $self = shift;
    my %args = @_;

    my $orig_bd = $args{orig_bd} || croak "Missing orig_bd argument\n";
    my $rand_bd = $args{rand_bd} || croak "Missing rand_bd argument\n";

    my $rand  = $args{rand_object};

    my $progress_bar = Biodiverse::Progress->new();

    my $elements_ref    = $orig_bd->get_groups_ref;
    my $to_elements_ref = $rand_bd->get_groups_ref;

    my $name        = $self->get_param ('NAME');
    my $to_name     = $rand_bd->get_param ('NAME');
    my $text        = "Transferring group properties from $name to $to_name";

    my $total_to_do = $elements_ref->get_element_count;
    say "[BASEDATA] Transferring properties for $total_to_do groups";

    my $count = 0;
    my $i = -1;

    my @to_element_list = sort $to_elements_ref->get_element_list;
    my $shuffled_to_elements = $rand->shuffle (\@to_element_list);

    BY_ELEMENT:
    foreach my $element (sort $to_elements_ref->get_element_list) {
        $i++;
        my $progress = $i / $total_to_do;
        $progress_bar->update (
            "$text\n"
            . "(label $i of $total_to_do)",
            $progress
        );

        my $to_element = shift @$shuffled_to_elements;

        my $props = $elements_ref->get_list_values (
            element => $element,
            list => 'PROPERTIES'
        );

        next BY_ELEMENT if ! defined $props;  #  none there

        #  delete any existing lists - cleaner and safer than adding to them
        $to_elements_ref->delete_lists (
            element => $to_element,
            lists => ['PROPERTIES'],
        );

        $to_elements_ref->add_to_lists (
            element    => $to_element,
            PROPERTIES => {%$props},  #  make sure it's a copy so bad things don't happen
        );
        $count ++;
    }

    return $count; 
}

#  move them around as a set of values, so the
#  receiving group gets all of the providing groups props
sub process_group_props_by_item {
    my $self = shift;
    my %args = @_;

    my $orig_bd = $args{orig_bd} || croak "Missing orig_bd argument\n";
    my $rand_bd = $args{rand_bd} || croak "Missing rand_bd argument\n";

    my $rand  = $args{rand_object};

    my $progress_bar = Biodiverse::Progress->new();

    my $elements_ref    = $orig_bd->get_groups_ref;
    my $to_elements_ref = $rand_bd->get_groups_ref;

    foreach my $to_element ($to_elements_ref->get_element_list) {
        #  delete any existing lists - cleaner and safer than adding to them
        $to_elements_ref->delete_lists (
            element => $to_element,
            lists => ['PROPERTIES'],
        );
    }

    my $name        = $self->get_param ('NAME');
    my $to_name     = $rand_bd->get_param ('NAME');
    my $text        = "Transferring group properties from $name to $to_name";

    my $total_to_do = $to_elements_ref->get_element_count;
    say "[BASEDATA] Transferring group properties for $total_to_do";

    my $count = 0;
    my $i = -1;

    my @to_element_list = sort $to_elements_ref->get_element_list;

    for my $prop_key ($elements_ref->get_element_property_keys) {

        my $shuffled_to_elements = $rand->shuffle ([@to_element_list]);  #  need a shuffled copy

        BY_ELEMENT:
        foreach my $element (sort $to_elements_ref->get_element_list) {
            $i++;
            my $progress = $i / $total_to_do;
            $progress_bar->update (
                "$text\n"
                . "(label $i of $total_to_do)",
                $progress
            );

            my $to_element = shift @$shuffled_to_elements;

            my $props = $elements_ref->get_list_values (
                element => $element,
                list => 'PROPERTIES'
            );

            next BY_ELEMENT if ! defined $props;  #  none there
            next BY_ELEMENT if ! exists $props->{$prop_key};

            #  now add the value for this property
            $to_elements_ref->add_to_lists (
                element    => $to_element,
                PROPERTIES => {$prop_key => $props->{$prop_key}},
            );

            $count ++;
        }
    }

    return $count; 
}

my $process_group_props_tooltip = <<'END_OF_GPPROP_TOOLTIP'
Group properties in the randomised basedata will be assigned in these ways:
no_change:  The same as in the original basedata. 
by_set:     All of a group's properties are assigned to a random group as a set.
by_item:    A group's properties are randomly allocated to random groups individually.  
END_OF_GPPROP_TOOLTIP
  ;

sub get_group_prop_metadata {
    my $self = shift;

    my $metadata = {
        name => 'randomise_group_props_by',
        type => 'choice',
        choices => [qw /no_change by_set by_item/],
        default => 0,
        tooltip => $process_group_props_tooltip,
        box_group => 'Trees and groups',
    };
    bless $metadata, $parameter_rand_metadata_class;

    return $metadata;
}

#  should build this from metadata
my $randomise_trees_tooltip = <<"END_RANDOMISE_TREES_TOOLTIP"
Trees used as arguments in the analyses will be randomised in these ways:
shuffle_no_change:  Trees will be unchanged. 
shuffle_terminal_names:  Terminal node names will be randomly re-assigned within each tree.
END_RANDOMISE_TREES_TOOLTIP
  ;

sub get_tree_shuffle_metadata {
    my $self = shift;

    require Biodiverse::Tree;
    my $tree = Biodiverse::Tree->new;
    my @choices = sort keys %{$tree->get_subs_with_prefix (prefix => 'shuffle')};
    my $default = first_index {$_ =~ 'no_change$'} @choices;
    @choices = map {(my $x = $_) =~ s/^shuffle_//; $x} @choices;  #  strip the shuffle_ off the front

    my $metadata = {
        name => 'randomise_trees_by',
        type => 'choice',
        choices => \@choices,
        default => $default,
        tooltip => $randomise_trees_tooltip,
        box_group => 'Trees and groups',
    };
    bless $metadata, $parameter_rand_metadata_class;

    return $metadata;
}


sub get_prng_init_states_array {
    my $self = shift;
    my $state_data = $self->get_prng_state_data;
    my $states = ($state_data->{INIT_STATES} //= []);
    # should perhaps do this in the main code,
    # but we only need it for basedata reintegration
    if (!scalar @$states) {
        if (my $init_state = $self->get_param('RAND_INIT_STATE')) {
            push @$states, $init_state;
        }
    }
    return wantarray ? @$states : $states;
}

sub get_prng_end_states_array {
    my $self = shift;
    my $state_data = $self->get_prng_state_data;
    my $states = ($state_data->{END_STATES} //= []);
    # should perhaps do this in the main code,
    # but we only need it for basedata reintegration
    if (!scalar @$states) {
        if (my $state = $self->get_param('RAND_LAST_STATE')) {
            push @$states, $state;
        }
    }
    return wantarray ? @$states : $states;
}

sub get_prng_total_counts_array {
    my $self = shift;
    my $state_data = $self->get_prng_state_data;
    my $counts = ($state_data->{TOTAL_ITERATIONS} //= []);
    if (!scalar @$counts) {
        if (my $iters = $self->get_param('TOTAL_ITERATIONS')) {
            push @$counts, $iters;
        }
    }
    return wantarray ? @$counts : $counts;
}

sub get_prng_state_data {
    my $self = shift;
    my $state_data = $self->get_param ('RAND_STATE_DATA');
    if (!defined $state_data) {
        $state_data = {
            INIT_STATES      => [],
            END_STATES       => [],
            TOTAL_ITERATIONS => [],
        };
        $self->set_param (RAND_STATE_DATA => $state_data);
    }

    return $state_data;
}




1;

__END__

=head1 NAME

Biodiverse::Randomise

=head1 SYNOPSIS

  use Biodiverse::Randomise;
  $object = Biodiverse::Randomise->new();

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

