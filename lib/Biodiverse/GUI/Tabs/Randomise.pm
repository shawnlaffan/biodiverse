package Biodiverse::GUI::Tabs::Randomise;

use 5.016;
use strict;
use warnings;
use Carp;
use English ( -no_match_vars );

use Gtk2;
use Biodiverse::Randomise;

our $VERSION = '1.99_002';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;
use Biodiverse::GUI::ParametersTable;
use Biodiverse::GUI::YesNoCancel;

use Scalar::Util qw /looks_like_number reftype/;
use List::MoreUtils qw /first_index/;

use parent qw {Biodiverse::GUI::Tabs::Tab};

use constant OUTPUT_CHECKED => 0;
use constant OUTPUT_NAME    => 1;
use constant OUTPUT_REF     => 2;

######################################################
## Init
######################################################
sub get_type {
    return 'randomisation';
}

sub new {
    my $class = shift;
    my $output_ref = shift; # will be undef if none specified

    my $self = {gui => Biodiverse::GUI::GUIManager->instance};
    $self->{project} = $self->{gui}->get_project();
    bless $self, $class;

    $self->{output_ref} = $output_ref;

    #  create one for the function combo to use
    if (not defined $output_ref) {
        my $object = Biodiverse::Randomise->new();
        $self->{output_placeholder_ref} = $object;
    }

    # (we can have many Analysis tabs open, for example.
    # These have a different object/widgets)
    $self->{xmlPage} = Gtk2::Builder->new();
    $self->{xmlPage}->add_from_file($self->{gui}->get_gtk_ui_file('vboxRandomisePage.ui'));
    $self->{xmlLabel} = Gtk2::Builder->new();
    $self->{xmlLabel}->add_from_file($self->{gui}->get_gtk_ui_file('hboxRandomiseLabel.ui'));

    my $xml_page  = $self->{xmlPage};
    my $xml_label = $self->{xmlLabel};

    my $page  = $xml_page ->get_object('vboxRandomisePage');
    my $label = $xml_label->get_object('hboxRandomiseLabel');
    my $label_text = $xml_label->get_object('lblRandomiseName')->get_text;
    my $label_widget = Gtk2::Label->new ($label_text);
    $self->{tab_menu_label} = $label_widget;

    $self->{label_widget} = $xml_label->get_object('lblRandomiseName');
    #$self->set_label_widget_tooltip;  not yet

    # Add to notebook
    $self->add_to_notebook (
        page         => $page,
        label        => $label,
        label_widget => $label_widget,
    );

    my $bd;
    my $function;
    if ($output_ref) {
        $bd = $output_ref->get_param ('BASEDATA_REF');
        $function = $output_ref->get_param ('FUNCTION');
    }

    $self->init_parameters_table;

    # Initialise randomisation function combo
    $self->make_function_model (selected_function => $function);
    $self->init_function_combo;
    
    # Make model for the outputs tree
    my $model = Gtk2::TreeStore->new(
        'Glib::Boolean',       # Checked?
        'Glib::String',        # Name
        'Glib::Scalar',        # Output ref
    );
    $self->{outputs_model} = $model;

    # Initialise the basedatas combo
    $self->init_basedata_combo (basedata_ref => $bd);

    #  and choose the basedata (this is set by the above call)
    #  and needed if it is undef
    $bd = $self->{selected_basedata_ref};

    $self->add_iteration_count_to_table ($output_ref);

    my $name;
    my $seed_widget = $xml_page->get_object('randomise_seed_value');
    if ($output_ref) {
        #$self->{project}->register_in_outputs_model ($output_ref, $self);
        $self->register_in_outputs_model ($output_ref, $self);
        $name = $output_ref->get_param ('NAME');
        $self->on_function_changed;
        $self->set_button_sensitivity (0);
    }
    else {
        $name = $bd->get_unique_randomisation_name;
        #$seed_widget->set_text (time);
    }

    $xml_label->get_object('lblRandomiseName')->set_text($name);
    $xml_page ->get_object('randomise_results_list_name')->set_text ($name);
    $self->{tab_menu_label}->set_text($name );

    # Connect signals
    $xml_label->get_object('btnRandomiseClose')->signal_connect_swapped(
        clicked => \&on_close,
        $self,
    );
    $xml_page->get_object('btnRandomise')->signal_connect_swapped(
        clicked => \&on_run,
        $self,
    );
    $xml_page->get_object('randomise_results_list_name')->signal_connect_swapped(
        changed => \&on_name_changed,
        $self,
    );

    $self->update_randomise_button; # will disable button just in case have no basedatas

    print "[Randomise tab] Loaded tab - Randomise\n";
    return $self;
}

sub get_table_widget {
    my $self = shift;

    my $xml_page = $self->{xmlPage};

    my $table = $xml_page->get_object('table_randomise_setup');

    return $table;
}

sub add_row_to_table {
    my $self  = shift;
    my $table = shift || $self->get_table_widget;

    my $row_count = $table->get('n-rows');
    $row_count ++;
    $table->set('n-rows' => $row_count + 1);

    return $row_count;
}

sub add_iteration_count_to_table {
    my $self = shift;
    my $output_ref = shift;

    my $xml_page = $self->{xmlPage};

    my $table = $xml_page->get_object('table_randomise_setup');

    my $row_count = $self->add_row_to_table ($table);

    my $count = defined $output_ref
                ? $output_ref->get_param ('TOTAL_ITERATIONS')
                : 'nil';
    #my $label1 = Gtk2::Label->new ();
    #$label1->set_text ('Iterations so far: ');
    my $label2 = Gtk2::Label->new ();
    #$label2->set_justify('GTK_JUSTIFY_LEFT');

    $self->{iterations_label} = $label2;
    $self->update_iterations_count_label ($count);

    #$table->attach ($label1, 0, 1, $row_count, $row_count + 1, 'fill', [], 0, 0);
    $table->attach ($label2, 1, 2, $row_count, $row_count + 1, 'expand', [], 0, 0);
    #$label1->show;
    $label2->show;
    return;
}

sub update_iterations_count_label {
    my $self = shift;
    my $count = shift || 'nil';

    my $label = $self->{iterations_label};

    $label->set_text ("Iterations so far: $count");

    return;
}

#  desensitise buttons if already run
sub set_button_sensitivity {
    my $self = shift;
    my $sens = shift;

    my @widgets = qw /
        randomise_results_list_name
        randomise_seed_value
        comboRandomiseBasedata
        comboFunction
    /;

    my $xml_page = $self->{xmlPage};
    foreach my $widget (@widgets) {
        $xml_page->get_object($widget)->set_sensitive ($sens);
    }

    my $table = $self->{xmlPage}->get_object('tableParams');

    return;
}

sub init_basedata_combo {
    my $self = shift;
    my %args = @_;

    my $combo = $self->{xmlPage}->get_object('comboRandomiseBasedata');
    my $renderer = Gtk2::CellRendererText->new();

    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, text => 0);

    $combo->set_model($self->{gui}->get_project->get_basedata_model());
    $combo->signal_connect_swapped(
        changed => \&on_randomise_basedata_changed,
        $self,
    );

    my $selected = defined $args{basedata_ref}
        ? $self->{gui}->get_project->get_base_data_iter ($args{basedata_ref})
        : $self->{gui}->get_project->get_selected_base_data_iter;

    if (defined $selected) {
        $combo->set_active_iter($selected);
    }

    $combo->set_sensitive (0); # if 1 then re-enable signal connect above

    $self->on_randomise_basedata_changed;  #  set a few things

    return;
}


######################################################
## Randomisation function combo
######################################################
sub make_function_model {
    my $self = shift;
    my %args = @_;

    $self->{function_model} = Gtk2::ListStore->new( 'Glib::String' ); # NAME
    my $model = $self->{function_model};

    # Add each randomisation function
    my $functions = Biodiverse::Randomise->get_randomisation_functions;
    my %functions = %$functions;
    my @funcs;
    #  SWL: put the selected one first
    #  - should really manipulate GTK iters to just select it
    if (defined $args{selected_function}) {
        #delete $functions{$args{selected_function}};
        #@funcs = ($args{selected_function}, sort keys %functions);
        @funcs = ($args{selected_function});  #  only allow the previously used function
    }
    else {
        my $default = Biodiverse::Randomise->get_default_rand_function;
        if (exists $functions->{$default}) {
            push @funcs, $default;
            push @funcs, grep {$_ ne $default} sort keys %{$functions};
        }
        else {
            push @funcs, sort keys %{$functions};
        }
    }
    foreach my $name (@funcs) {
        # Add to model
        my $iter = $model->append;
        $model->set($iter, 0, $name);
    }

    $self->{selected_function_iter} = $model->get_iter_first;

    return;
}

sub init_function_combo {
    my $self = shift;
    my %args = @_;

    my $combo = $self->{xmlPage}->get_object('comboFunction');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, text => 0);

    $combo->signal_connect_swapped(changed => \&on_function_changed, $self);

    $combo->set_model($self->{function_model});
    if ($self->{selected_function_iter}) {
        $combo->set_active_iter( $self->{selected_function_iter} );
    }

    if ($self->{output_ref}) {
        $combo->set_sensitive (0);
    }

    return;
}

sub get_selected_function {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_object('comboFunction');
    my $iter = $combo->get_active_iter;

    return $self->{function_model}->get($iter, 0);
}

sub on_function_changed {
    my $self = shift;

    my $widget_hash = ($self->{widget_hash} //= {});
    my $params_hash = ($self->{params_hash} //= {});
    my $metadata_cache = $self->get_metadata_cache;

    # Get the Parameters metadata
    my $func = $self->get_selected_function;

    my $object = $self->{output_ref}
                 || $self->{output_placeholder_ref};

    my $metadata = $metadata_cache->{$func};
    my $params   = $metadata->get_parameters;

    #  needed?
    return if not defined $params;

    #  need to set the parameter values if the output exists
    my $args_hash = {};
    my $use_args_hash = 0;
    my $sensitise = 1;
    if ($self->{output_ref}) {
        $args_hash = $self->{output_ref}->get_param ('ARGS') // {};
        $use_args_hash = scalar keys %$args_hash;
        $sensitise = 0;
    }
    my %func_p_hash = map {$_->get_name => $_} @$params;

    P_NAME:
    foreach my $p_name (keys %$widget_hash) {

        my $parameter = $params_hash->{$p_name};

        if (exists $func_p_hash{$p_name}) {
            #  desensitise by default, but mutable params can always be changed
            my $sens = $parameter->get_mutable // $sensitise;
            $parameter->set_sensitive ($sens);  #  needed now?
            $widget_hash->{$p_name}->set_sensitive($sens);
        }
        else {
            $widget_hash->{$p_name}->set_sensitive(0);
        }
    }

    return;
}

sub get_parameters_table {
    my $self = shift;
    $self->{parameters_table} //= Biodiverse::GUI::ParametersTable->new;
    return $self->{parameters_table};
}

#  if we have an existing output then we need to use its values
sub update_default_parameter_values {
    my $self = shift;
    
    my $params_hash = ($self->{params_hash} //= {});
    my $metadata_cache = $self->get_metadata_cache;

    return if not $self->{output_ref};

    #  need to set the parameter values if the output exists
    my $args_hash = $self->{output_ref}->get_param ('ARGS') // {};

    P_NAME:
    foreach my $p_name (keys %$params_hash) {

        my $parameter = $params_hash->{$p_name};

        if (exists $args_hash->{$p_name}) {
            my $val = $args_hash->{$p_name};
            if ($parameter->get_type eq 'choice') {
                my $choices = $parameter->get_choices;
                my $arg_name = $args_hash->{$p_name};
                $val = first_index {$_ eq $arg_name} @$choices;
                #  if no full match then get the first suffix match - allows for shorthand options
                if ($val < 0) {
                    $val = first_index {$_ =~ /$arg_name$/} @$choices;
                }
            }
            $parameter->set_default ($val);
        }
    }

    return;
}

#  need to extract the params hash stuff into its own sub
sub get_metadata_cache {
    my $self = shift;

    return $self->{metadata_cache}
      if $self->{metadata_cache};

    my $functions = Biodiverse::Randomise->get_randomisation_functions_as_array;
    my @metadata;
    my (@params_list, %params_hash, %metadata_cache);
    foreach my $func (sort @$functions) {
        my $metadata = Biodiverse::Randomise->get_metadata (sub => $func);
        $metadata_cache{$func} = $metadata;
        my $params = $metadata->get_parameters;
        foreach my $p (@$params) {
            my $name = $p->get_name;
            next if exists $params_hash{$name};
            push @params_list, $p;
            $params_hash{$name} = $p;
        }
    }

    $self->{params_list}    = \@params_list;
    $self->{params_hash}    = \%params_hash;
    $self->{metadata_cache} = \%metadata_cache;    
}

sub init_parameters_table {
    my $self = shift;

    $self->get_metadata_cache;
    $self->update_default_parameter_values;
    
    my $params_list = $self->{params_list};

    # Build widgets for parameters
    my $table = $self->{xmlPage}->get_object('tableParams');
    my $parameters_table = $self->get_parameters_table;
    my $new_extractors
        = $parameters_table->fill($params_list, $table);

    $self->{param_extractors} //= [];
    push @{$self->{param_extractors}}, @$new_extractors;

    $self->{widgets} //= [];
    my $widget_array = $self->{widgets};
    my $new_widgets = $parameters_table->{widgets};
    push @$widget_array, @$new_widgets;

    my $widget_hash = ($self->{widget_hash} //= {});
    foreach my $i (0..$#$params_list) {
        my $name = $params_list->[$i]->get_name;
        $widget_hash->{$name} = $widget_array->[$i];
    }

    return;    
}

######################################################
## The basedata/outputs selection
######################################################
sub on_randomise_basedata_changed {
    my $self = shift;
    my $combo = $self->{xmlPage}->get_object('comboRandomiseBasedata');
    my $basedata_iter = $combo->get_active_iter();

    # Get basedata object
    my $basedata_ref;
    if ($basedata_iter) {
        $basedata_ref = $combo->get_model->get(
            $basedata_iter,
            Biodiverse::GUI::Project::MODEL_OBJECT,
        );
    }
    $self->{selected_basedata_ref} = $basedata_ref;

    $self->update_randomise_button;

    return;
}


# Called when the user clicks on a checkbox
sub on_output_toggled {
    my $self = shift;
    my $model = $self->{outputs_model};
    my $path = shift;

    my $iter = $model->get_iter_from_string($path);

    # Flip state
    my ($state) = $model->get($iter, OUTPUT_CHECKED);
    $state = not $state;
    $model->set($iter, OUTPUT_CHECKED, $state);

    $self->update_randomise_button;

    return;
}


# Disables "Randomise" button if no outputs selected
sub update_randomise_button {
    my $self = shift;

    my $project = $self->{gui}->get_project;
    return if not $project;

    my $outputs_list = $project->get_basedata_outputs($self->{selected_basedata_ref});
    my $selected     = $outputs_list;

    if (@{$selected}) {
        $self->{xmlPage}->get_object('btnRandomise')->set_sensitive(1);
    }
    else {
        $self->{xmlPage}->get_object('btnRandomise')->set_sensitive(0);
    }

    return;
}


sub on_name_changed {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_object('randomise_results_list_name');
    my $name = $widget->get_text();

    $self->{xmlLabel}->get_object('lblRandomiseName')->set_text($name);

    my $label_widget = $self->{xmlPage}->get_object('label_rand_list_name');
    my $label = $label_widget->get_label;

    my $tab_menu_label = $self->{tab_menu_label};
    $tab_menu_label->set_text($name);

    #  colour the label red if the list exists
    my $span_leader = '<span foreground="red">';
    my $span_ender  = ' <b>exists</b></span>';
    if ($self->get_rand_output_exists ($name)) {
        $label =  $span_leader . $label . $span_ender;
        $label_widget->set_markup ($label);
    }
    else {
        $label =~ s/$span_leader//;
        $label =~ s/$span_ender//;
        $label_widget->set_markup ($label);
    }

    return;
}

#  does this rand output already exist in the basedata?
sub get_rand_output_exists {
    my $self = shift;
    my $name = shift;

    croak "argument 'name' not specified\n"
        if ! defined $name;

    my $bd = $self->{selected_basedata_ref};

    return defined $bd->get_randomisation_output_ref (name => $name);
}

######################################################
## Running the randomisation
######################################################

# Button clicked
sub on_run {
    my $self = shift;

    my $basedata_ref = $self->{selected_basedata_ref};
    my $basedata_name = $basedata_ref->get_param('NAME');

    $self->set_button_sensitivity (0);

    # Fill in parameters
    my %args;
    $args{function} = $self->get_selected_function;
    $args{iterations}
        = $self->{xmlPage}->get_object('spinIterations')->get_value_as_int;

    my $xml_page = $self->{xmlPage};
    my $name = $xml_page->get_object('randomise_results_list_name')->get_text;
    my $seed = $xml_page->get_object('randomise_seed_value')->get_text;
    $seed =~ s/\s//g;  #  strip any whitespace
    if (not defined $seed or length ($seed) == 0) {
        warn "[GUI Randomise] PRNG seed is not defined, using system default\n";
        $seed = undef;
    }
    elsif (not looks_like_number ($seed)) {
        warn "[GUI Randomise] PRNG seed is not numeric, using system default instead\n";
        $seed = undef;
    }

    #  need to get the parameters for this function given the metadata
    #my $parameters_table = $self->get_parameters_table;
    #my $param_hash = $parameters_table->extract (
    #    $self->{param_extractors}
    #);
    my $param_hash = $self->get_parameter_settings_for_func ($args{function});
    
    %args = (
        %args,
        seed => $seed,
        %$param_hash,
    );

    #  is this still needed?
    my $str_args;  #  for user feedback
    foreach my $arg (sort keys %args) {
        my $value = $args{$arg};
        if (! ref $value) {
            $value //= "undef";
            $str_args .= "\t$arg\t= $value\n" ;
        }
        elsif ((ref $value) =~ /ARRAY/) {
            $str_args .= "\t$arg\t= " . (scalar @$value) . "\n";
        }
    }

    # G O
    print "[Randomise page] Running randomisation on $basedata_name\n";
    print "[Randomise page]    args = \n$str_args\n";


    #  get it if it exists, create otherwise
    my $output_ref = $basedata_ref->get_randomisation_output_ref (name => $name);
    if (defined $output_ref) {  #  warn it is an existing output, quit if user specifies
        my $text =
            "Randomisation $name already exists in this BaseData.\n\n"
            . "Running more iterations will add to the existing results.\n"
            . "The PRNG sequence will also continue on from the last iteration.\n\n"
            . "If you have typed an existing list name then any "
            . "newly set parameters will be ignored.\n\n"
            . "Continue?";
        my $response = Biodiverse::GUI::YesNoCancel->run ({header => $text});

        return if $response ne 'yes';

        $args{seed} = undef;  #  override any seed setting so we don't repeat sequences
    }
    else {
        #  eval is prob not needed, as we trap pre-existing above
        $output_ref = eval {
            $basedata_ref->add_randomisation_output (name => $name);
        };
        if ($EVAL_ERROR) {
            $self->{gui}->report_error ($EVAL_ERROR);
        }
        #  need to add it to the GUI outputs
        $self->{output_ref} = $output_ref;
        $self->{project}->add_output($basedata_ref, $output_ref);
    }

    my $success = eval {
        $output_ref->run_analysis (
            %args,
        )
    };
    if ($EVAL_ERROR) {
        $self->{gui}->report_error ($EVAL_ERROR);
    }

    #if ($success) {
        #$self->{project}->register_in_outputs_model ($output_ref, $self);
        $self->register_in_outputs_model ($output_ref, $self);
        $self->on_function_changed;  #  disable some widgets
    #}
    if (not $success) {  # dropped out for some reason, eg no valid analyses.
        $self->on_close;  #  close the tab to avoid horrible problems with multiple instances
        return;
    }

    if ((reftype ($success) // 1) eq 'ARRAY') {
        #  we were passed an array of basedatas
        foreach my $bd (@$success) {
            $self->{gui}->get_project->add_base_data($bd);
        }
    }

    $self->update_iterations_count_label (
        $output_ref->get_param ('TOTAL_ITERATIONS')
    );

    $self->{project}->set_dirty;

    return;
}

#  get the current parameter values for a function
sub get_parameter_settings_for_func {
    my ($self, $func) = @_;

    defined $func or croak "function argument not specified\n";

    my $parameters_table = $self->get_parameters_table;
    my %param_hash = $parameters_table->extract (
        $self->{param_extractors}
    );

    my $metadata = $self->{metadata_cache}->{$func};
    croak "Metadata cache not filled\n"
      if !defined $metadata;

    my @needed_params = map {$_->get_name} @{$metadata->get_parameters};

    #say join ' ', @needed_params;

    my %p_subset;
    @p_subset{@needed_params} = @param_hash{@needed_params};

    return wantarray ? %p_subset : \%p_subset;
}

#  methods aren't inherited when called as GTK callbacks
#  so we have to manually inherit them using SUPER::
our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self)
                or croak "$self is not an object\n";

    my $method = $AUTOLOAD;
    $method =~ s/.*://;   # strip fully-qualified portion

    $method = "SUPER::" . $method;
    return $self->$method(@_);
}

sub DESTROY {
    #my $self = shift;
    #eval {
    #    $self->{xmlPage}->get_object('comboRandomiseBasedata')->destroy;
    #}
}  #  let the system handle destruction - need this for AUTOLOADER


1;
