package Biodiverse::GUI::Tabs::Randomise;

use strict;
use warnings;
use Carp;
use English ( -no_match_vars );

use Gtk2;
use Biodiverse::Randomise;

our $VERSION = '0.16';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;
use Biodiverse::GUI::ParametersTable;
use Biodiverse::GUI::YesNoCancel;

use Scalar::Util qw /looks_like_number/;

use base qw {Biodiverse::GUI::Tabs::Tab};

use constant OUTPUT_CHECKED => 0;
use constant OUTPUT_NAME    => 1;
use constant OUTPUT_REF     => 2;

######################################################
## Init
######################################################
sub getType {
    return 'randomisation';
}

sub new {
    my $class = shift;
    my $output_ref = shift; # will be undef if none specified
        
    my $self = {gui => Biodiverse::GUI::GUIManager->instance};
    $self->{project} = $self->{gui}->getProject();
    bless $self, $class;

    $self->{output_ref} = $output_ref;
    
    #  create one for the function combo to use
    if (not defined $output_ref) {  
        my $object = Biodiverse::Randomise -> new();
        $self->{output_placeholder_ref} = $object;
    }

    # Load _new_ widgets from glade 
    # (we can have many Analysis tabs open, for example.
    # These have a different object/widgets)
    $self->{xmlPage}  = Gtk2::GladeXML->new(
        $self->{gui}->getGladeFile,
        'vboxRandomisePage',
    );
    $self->{xmlLabel} = Gtk2::GladeXML->new(
        $self->{gui}->getGladeFile,
        'hboxRandomiseLabel',
    );

    my $xml_page  = $self->{xmlPage};
    my $xml_label = $self->{xmlLabel};

    my $page  = $xml_page ->get_widget('vboxRandomisePage');
    my $label = $xml_label->get_widget('hboxRandomiseLabel');

    # Add to notebook
    $self->{notebook} = $self->{gui}->getNotebook();
    $self->{page_index} = $self->{notebook}->append_page($page, $label);
    $self->{gui}->addTab($self);
        
    my $bd;
    my $function;
    if ($output_ref) {
        $bd = $output_ref -> get_param ('BASEDATA_REF');
        $function = $output_ref -> get_param ('FUNCTION');
    }

    # Initialise randomisation function combo
    $self->makeFunctionModel (selected_function => $function);
    $self->initFunctionCombo;

    # Make model for the outputs tree
    my $model = Gtk2::TreeStore->new(
        'Glib::Boolean',       # Checked?
        'Glib::String',        # Name
        'Glib::Scalar',        # Output ref
    );
    $self->{outputs_model} = $model;

    # Initialise the basedatas combo
    $self->initBasedataCombo (basedata_ref => $bd);
    
    #  and choose the basedata (this is set by the above call)
    #  and needed if it is undef
    $bd = $self->{selected_basedata_ref};
    
    # Initialise the tree
    # One column with a checkbox and the output name
    #my $tree = $self->{xmlPage}->get_widget("treeOutputs");
    #
    #my $colName = Gtk2::TreeViewColumn->new();
    #my $checkRenderer = Gtk2::CellRendererToggle->new();
    #my $nameRenderer = Gtk2::CellRendererText->new();
    #$checkRenderer->signal_connect_swapped(toggled => \&onOutputToggled, $self);
    #
    #$colName->pack_start($checkRenderer, 0);
    #$colName->pack_start($nameRenderer, 1);
    #$colName->add_attribute($checkRenderer, active => OUTPUT_CHECKED);
    #$colName->add_attribute($nameRenderer,  text => OUTPUT_NAME);

    #$tree->insert_column($colName, -1);
    #$tree->set_model( $model );

    $self->add_save_checkpoint_to_table ($output_ref);
    $self->add_iteration_count_to_table ($output_ref);

    my $name;
    my $seed_widget = $xml_page->get_widget('randomise_seed_value');
    if ($output_ref) {
        #$self->{project}->registerInOutputsModel ($output_ref, $self);
        $self->registerInOutputsModel ($output_ref, $self);
        $name = $output_ref -> get_param ('NAME');
        $self -> onFunctionChanged;
        $self->set_button_sensitivity (0); 
    }
    else {
        $name = $bd -> get_unique_randomisation_name;
        #$seed_widget->set_text (time);
    }
    
    $xml_label->get_widget('lblRandomiseName')->set_text($name);
    $xml_page ->get_widget('randomise_results_list_name') -> set_text ($name);

    # Connect signals
    $xml_label->get_widget('btnRandomiseClose')->signal_connect_swapped(
        clicked => \&onClose,
        $self,
    );
    $xml_page->get_widget('btnRandomise')->signal_connect_swapped(
        clicked => \&onRun,
        $self,
    );
    $xml_page->get_widget('randomise_results_list_name')->signal_connect_swapped(
        changed => \&onNameChanged,
        $self,
    );

    $self->updateRandomiseButton; # will disable button just in case have no basedatas

    print "[Randomise tab] Loaded tab - Randomise\n";
    return $self;
}

sub get_table_widget {
    my $self = shift;
    
    my $xml_page = $self->{xmlPage};
    
    my $table = $xml_page->get_widget('table_randomise_setup');
    
    return $table;
}

sub add_row_to_table {
    my $self  = shift;
    my $table = shift || $self -> get_table_widget;

    my $row_count = $table->get('n-rows');
    $row_count ++;
    $table->set('n-rows' => $row_count + 1);
    
    return $row_count;
}

sub add_save_checkpoint_to_table {
    my $self = shift;
    
    my $table = $self -> get_table_widget;

    my $label = Gtk2::Label->new("Checkpoint save\niterations");
    
    
    my $default = 99;
    my $incr    = 900;
    
    my $adj = Gtk2::Adjustment->new($default, 0, 10000000, $incr, $incr * 10, 0);
    my $spin = Gtk2::SpinButton->new($adj, $incr, 0);
    
    my $tooltip_group = Gtk2::Tooltips->new;
    my $tip_text = "Save every nth iteration.\n"
                   . '(Useful for evaluating results as they are run.)';
    $tooltip_group->set_tip($label, $tip_text, undef);
    
    #  and now add the widgets
    my $row_count = $self -> add_row_to_table ($table);    
    $table -> attach ($label, 0, 1, $row_count, $row_count + 1, 'fill', [], 0, 0);
    $table -> attach ($spin,  1, 2, $row_count, $row_count + 1, 'fill', [], 0, 0);

    $label -> show;
    $spin -> show;

    $self->{save_checkpoint_button} = $spin;

    return;
}

sub add_iteration_count_to_table {
    my $self = shift;
    my $output_ref = shift;

    my $xml_page = $self->{xmlPage};
    
    my $table = $xml_page->get_widget('table_randomise_setup');
    
    my $row_count = $self -> add_row_to_table ($table); 
    
    my $count = defined $output_ref
                ? $output_ref->get_param ('TOTAL_ITERATIONS')
                : 'nil';
    #my $label1 = Gtk2::Label -> new ();
    #$label1 -> set_text ('Iterations so far: ');
    my $label2 = Gtk2::Label -> new ();
    #$label2->set_justify('GTK_JUSTIFY_LEFT');
    
    $self->{iterations_label} = $label2;
    $self -> update_iterations_count_label ($count);

    #$table -> attach ($label1, 0, 1, $row_count, $row_count + 1, 'fill', [], 0, 0);
    $table -> attach ($label2, 1, 2, $row_count, $row_count + 1, 'expand', [], 0, 0);
    #$label1->show;
    $label2->show;
    return;
}

sub update_iterations_count_label {
    my $self = shift;
    my $count = shift || 'nil';
    
    my $label = $self->{iterations_label};
    
    $label -> set_text ("Iterations so far: $count");
    
    return;
}

#  desensitise buttons if already run
sub set_button_sensitivity {
    my $self = shift;
    my $sens = shift;
    
    my @widgets = qw /
        randomise_results_list_name
        randomise_seed_value
        comboBasedata
        comboFunction
    /;
    
    my $xml_page = $self->{xmlPage};
    foreach my $widget (@widgets) {
        $xml_page->get_widget($widget)->set_sensitive ($sens);
    }

    my $table = $self->{xmlPage}->get_widget('tableParams');
    $table -> set_sensitive ($sens);

    #  no - keep this modifiable
    #if (defined $self->{save_checkpoint_button}) {
    #    $self->{save_checkpoint_button}->set_sensitive ($sens);
    #}

    return;
}

sub initBasedataCombo {
    my $self = shift;
    my %args = @_;
        
    my $combo = $self->{xmlPage}->get_widget('comboBasedata');
    my $renderer = Gtk2::CellRendererText->new();

    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, text => 0);

    $combo->set_model($self->{gui}->getProject->getBasedataModel());
    $combo->signal_connect_swapped(
        changed => \&onBasedataChanged,
        $self,
    );

    my $selected = defined $args{basedata_ref}
        ? $self->{gui}->getProject->getBaseDataIter ($args{basedata_ref})
        : $self->{gui}->getProject->getSelectedBaseDataIter;

    if (defined $selected) {
        $combo -> set_active_iter($selected);
    }

    $self -> onBasedataChanged;  #  set a few things
    
    return;
}

#sub onClose {
#    my $self = shift;
#    $self->{gui}->removeTab($self);
#    return;
#}

#sub remove {
#    my $self = shift;
#    if (exists $self->{current_registration}) {  #  deregister if necessary
#        $self->{project}->registerInOutputsModel($self->{current_registration}, undef);
#    }
#    $self->{notebook}->remove_page( $self->{page_index} );
#    
#    return;
#}

######################################################
## Randomisation function combo
######################################################
sub makeFunctionModel {
    my $self = shift;
    my %args = @_;
        
    $self->{function_model} = Gtk2::ListStore->new( 'Glib::String' ); # NAME
    my $model = $self->{function_model};

    # Add each randomisation function
    my $functions = Biodiverse::Randomise::get_randomisations;
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
            @funcs = sort keys %{$functions};
        }
    foreach my $name (@funcs) {
        # Add to model
        my $iter = $model->append;
        $model->set($iter, 0, $name);
        
    }

    $self->{selected_function_iter} = $model->get_iter_first;
    
    return;
}

sub initFunctionCombo {
    my $self = shift;
    my %args = @_;
        
    my $combo = $self->{xmlPage}->get_widget('comboFunction');
    my $renderer = Gtk2::CellRendererText->new();
    $combo -> pack_start($renderer, 1);
    $combo -> add_attribute($renderer, text => 0);

    $combo -> signal_connect_swapped(changed => \&onFunctionChanged, $self);

    $combo -> set_model($self->{function_model});
    if ($self->{selected_function_iter}) {
        $combo->set_active_iter( $self->{selected_function_iter} );
    }
        
    if ($self->{output_ref}) {
        $combo -> set_sensitive (0);
    }
    
    return;
}

sub getSelectedFunction {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_widget("comboFunction");
    my $iter = $combo->get_active_iter;
    
    return $self->{function_model}->get($iter, 0);
}

sub onFunctionChanged {
    my $self = shift;

    # Get the Parameters metadata
    my $func = $self -> getSelectedFunction;
    
    my $object = $self->{output_ref}
                 || $self->{output_placeholder_ref};
    my %info = $object -> get_args (sub => $func);
    
    my $params = $info{parameters};

    return if not defined $params;
    
    #  set the parameter values if the output exists
    if ($self->{output_ref}) {
        my $args = $self->{output_ref} -> get_param ('ARGS') || {};
        foreach my $arg (keys %$args) {
            foreach my $param (@$params) {
                next if $param->{name} ne $arg;
                $param->{default} = $args->{$arg};
                $param->{sensitive} = 0;  #  cannot change the value
            }
        }
    }

    #  keep a track of what we've already added
    my @params_to_add;
    foreach my $p (@$params) {
        if (! exists $self->{param_extractors_added}{$p->{name}}) {
            push (@params_to_add, $p) ;
        }
        $self->{param_extractors_added}{$p->{name}} ++;
    }

    
    # Build widgets for parameters
    my $table = $self->{xmlPage}->get_widget('tableParams');
    my $new_extractors
        = Biodiverse::GUI::ParametersTable::fill(\@params_to_add, $table);
    if (! defined $self->{param_extractors}) {
        $self->{param_extractors} = [];
    }
    push @{$self->{param_extractors}}, @$new_extractors;
    
    return;
}



######################################################
## The basedata/outputs selection
######################################################
sub onBasedataChanged {
    my $self = shift;
    my $combo = $self->{xmlPage}->get_widget('comboBasedata');
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
    #print "[Randomise page] Basedata ref is $basedata_ref\n";

    # Set up the tree with outputs
    my $outputs_model = $self->{outputs_model};
    $outputs_model->clear;

    my $outputs_list = $self->{gui}->getProject->getBasedataOutputs($basedata_ref);
    if (not @{$outputs_list}) {
        #print "[Randomise page] output_list empty\n";
    }
    else {

        foreach my $output_ref (@{$outputs_list}) {
            my $iter = $outputs_model->append(undef);
            $outputs_model->set(
                $iter,
                OUTPUT_CHECKED, 1,
                OUTPUT_REF,     $output_ref,
                OUTPUT_NAME,    $output_ref->get_param('NAME')
            );
        }

    }

    $self->updateRandomiseButton;
    
    return;
}


# Called when the user clicks on a checkbox
sub onOutputToggled {
    my $self = shift;
    my $model = $self->{outputs_model};
    my $path = shift;
    
    my $iter = $model->get_iter_from_string($path);

    # Flip state
    my ($state) = $model->get($iter, OUTPUT_CHECKED);
    $state = not $state;
    $model->set($iter, OUTPUT_CHECKED, $state);

    $self->updateRandomiseButton;
    
    return;
}

# Get list of outputs that have been checked
sub getSelectedOutputs {
    my $self = shift;
    my $model = $self->{outputs_model};
    my $iter = $model->get_iter_first;
    my @array;

    while ($iter) {
        my ($checked, $ref) = $model->get($iter, OUTPUT_CHECKED, OUTPUT_REF);
        if ($checked) {
            unshift @array, $ref;
        }
        $iter = $model->iter_next($iter);
    }
    return \@array;
}

# Disables "Randomise" button if no outputs selected
sub updateRandomiseButton {
    my $self = shift;
    my $selected = $self->getSelectedOutputs;

    if (@{$selected}) {
        $self->{xmlPage}->get_widget('btnRandomise')->set_sensitive(1);
    }
    else {
        $self->{xmlPage}->get_widget('btnRandomise')->set_sensitive(0);
    }
    
    return;
}


sub onNameChanged {
    my $self = shift;
    
    my $widget = $self->{xmlPage}->get_widget('randomise_results_list_name');
    my $name = $widget->get_text();
    
    $self->{xmlLabel}->get_widget('lblRandomiseName')->set_text($name);
    
    my $label_widget = $self->{xmlPage}->get_widget('label_rand_list_name');
    my $label = $label_widget -> get_label;
    
    #  colour the label red if the list exists
    my $span_leader = '<span foreground="red">';
    my $span_ender  = ' <b>exists</b></span>';
    if ($self -> get_rand_output_exists ($name)) {
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
sub onRun {
    my $self = shift;

    my $basedata_ref = $self->{selected_basedata_ref};
    my $basedata_name = $basedata_ref->get_param('NAME');
    my $targets = $self->getSelectedOutputs;

    if (not @{$targets}) {
        croak "[Randomise page] ERROR - button shouldn't be clicked "
              . "when no targets selected!!\n";
    }

    $self->set_button_sensitivity (0);

    print "[Randomise page] Targets: @{$targets}\n";

    # Fill in parameters
    my %args;
    $args{function} = $self -> getSelectedFunction;
    $args{iterations}
        = $self->{xmlPage}->get_widget('spinIterations')->get_value_as_int;
    #$args{targets} = $targets;
    
    $args{save_checkpoint} = $self->{save_checkpoint_button}->get_value;
    
    my $xml_page = $self->{xmlPage};
    my $name = $xml_page->get_widget('randomise_results_list_name')-> get_text;
    my $seed = $xml_page->get_widget('randomise_seed_value')->get_text;
    $seed =~ s/\s//g;  #  strip any whitespace
    if (not defined $seed or length ($seed) == 0) {
        warn "[GUI Randomise] PRNG seed is not defined, using system default\n";
        $seed = undef;
    }
    elsif (not looks_like_number ($seed)) {
        warn "[GUI Randomise] PRNG seed is not numeric, using system default instead\n";
        $seed = undef;
    }

    my $param_hash = Biodiverse::GUI::ParametersTable::extract(
        $self->{param_extractors}
    );
    %args = (
        %args,
        seed => $seed,
        @$param_hash,
    );

    my $str_args;  #  for user feedback
    while (my ($arg, $value) = each %args) {
        if (! ref $value) {
            $value = "undef" if not defined $value;
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
    my $output_ref = $basedata_ref -> get_randomisation_output_ref (name => $name);
    if (defined $output_ref) {  #  warn it is an existing output, quit if user specifies
        my $text =
            "Randomisation $name already exists.\n\n"
            . "Running more iterations will add to the existing results.\n"
            . "The PRNG sequence will also continue on from the last iteration.\n\n"
            . "If you have typed an existing list name then any "
            . "newly set parameters will be ignored.\n\n"
            . "Continue?";
        my $response = Biodiverse::GUI::YesNoCancel -> run ({header => $text});

        return if $response ne 'yes';

        $args{seed} = undef;  #  override any seed setting so we don't repeat sequences
    }
    else {
        #  eval is prob not needed, as we trap pre-existing above
        $output_ref = eval {  
            $basedata_ref -> add_randomisation_output (name => $name);
        };
        if ($EVAL_ERROR) {
            $self->{gui}-> report_error ($EVAL_ERROR);
        }
        #  need to add it to the GUI outputs
        $self->{output_ref} = $output_ref;
        $self->{project}->addOutput($basedata_ref, $output_ref);
    }
    
    #my $progress = Biodiverse::GUI::ProgressDialog -> new;

    my $success = eval {
        $output_ref -> run_analysis (
            %args,
            #progress => $progress
        )
    };
    if ($EVAL_ERROR) {
        $self->{gui} -> report_error ($EVAL_ERROR);
    }

    #$progress->destroy;
    
    if ($success) {
        $self->{project}->registerInOutputsModel ($output_ref, $self);
    }
    
    $self->update_iterations_count_label (
        $output_ref -> get_param ('TOTAL_ITERATIONS')
    );
    
    $self->{project} -> setDirty;

    return;
}

## Make ourselves known to the Outputs tab to that it
## can switch to this tab if the user presses "Show"
#sub registerInOutputsModel {
#    my $self = shift;
#    my $output_ref = shift;
#    my $tabref = shift; # either $self, or undef to deregister
#    my $model = $self->{project} -> getBaseDataOutputModel();
#
#    # Find iter
#    my $iter;
#    my $iter_base = $model->get_iter_first();
#
#    while ($iter_base) {
#        
#        my $iter_output = $model->iter_children($iter_base);
#        while ($iter_output) {
#            if ($model->get($iter_output, MODEL_OBJECT) eq $output_ref) {
#                $iter = $iter_output;
#                last; #FIXME: do we have to look at other iter_bases, or does this iterate over entire level?
#            }
#            
#            $iter_output = $model->iter_next($iter_output);
#        }
#        
#        last if $iter; # break if found it
#        $iter_base = $model->iter_next($iter_base);
#    }
#
#    if ($iter) {
#        $model->set($iter, MODEL_TAB, $tabref);
#        $self->{current_registration} = $output_ref;
#    }
#    
#    return;
#}

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

sub DESTROY {}  #  let the system handle destruction - need this for AUTOLOADER


1;
