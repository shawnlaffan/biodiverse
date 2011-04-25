package Biodiverse::GUI::Tabs::Spatial;
use strict;
use warnings;

use English ( -no_match_vars );

our $VERSION = '0.16';

use Gtk2;
use Carp;
use Scalar::Util qw /blessed looks_like_number/;

use Biodiverse::GUI::GUIManager;
#use Biodiverse::GUI::ProgressDialog;
use Biodiverse::GUI::Grid;
use Biodiverse::GUI::Overlays;
use Biodiverse::GUI::Project;
use Biodiverse::GUI::SpatialParams;
use Biodiverse::GUI::Tabs::AnalysisTree;

use Biodiverse::Spatial;
use Data::Dumper;

use base qw {
    Biodiverse::GUI::Tabs::Tab
    Biodiverse::GUI::Tabs::Labels
};


our $NULL_STRING = q{};

##################################################
# Initialisation
##################################################

sub new {
    my $class = shift;
    my $output_ref = shift; # will be undef if none specified
    
    my $self = {gui => Biodiverse::GUI::GUIManager->instance()};
    $self->{project} = $self->{gui}->getProject();
    bless $self, $class;

    # Load _new_ widgets from glade 
    # (we can have many Analysis tabs open, for example. These have a different object/widgets)
    $self->{xmlPage}  = Gtk2::GladeXML->new($self->{gui}->getGladeFile, 'vpaneSpatial');
    $self->{xmlLabel} = Gtk2::GladeXML->new($self->{gui}->getGladeFile, 'hboxSpatialLabel');

    my $page  = $self->{xmlPage}->get_widget('vpaneSpatial');
    my $label = $self->{xmlLabel}->get_widget('hboxSpatialLabel');
    my $label_text = $self->{xmlLabel}->get_widget('lblSpatialName')->get_text;
    my $label_widget = Gtk2::Label->new ($label_text);
    $self->{tab_menu_label} = $label_widget;

    # Add to notebook
    $self->{notebook} = $self->{gui}->getNotebook();
    $self->{page_index} = $self->{notebook}->append_page_menu($page, $label, $label_widget);
    $self->{gui}->addTab($self);

    $self->set_tab_reorderable($page);

    my ($elt_count, $completed);  #  used to control display

    if (not defined $output_ref) {
        # We're being called as a NEW output
        # Generate a new output name
        my $bd = $self->{basedata_ref} = $self->{project}->getSelectedBaseData;
        
        if (not blessed ($bd)) {  #  this should be fixed now
            $self -> onClose;
            croak "Basedata ref undefined - click on the basedata object in "
                    . "the outputs tab to select it (this is a bug)\n";
        }
        
        #  check if it has rand outputs already and warn the user
        if (my @a = $bd -> get_randomisation_output_refs) {
            my $response
                = $self->{gui} -> warn_outputs_exist_if_randomisation_run(
                    $self->{basedata_ref} -> get_param ('NAME')
                );
            if (not $response eq 'yes') {
                $self -> onClose;
                croak "User cancelled operation\n";
            }
        }

        $self->{output_name} = $self->{project}->makeNewOutputName(
            $self->{basedata_ref},
            'Spatial'
        );
        print "[Spatial tab] New spatial output " . $self->{output_name} . "\n";

        $self->queueSetPane(1);
        $self->{existing} = 0;
    }
    else {
        # We're being called to show an EXISTING output

        # Register as a tab for this output
        $self->registerInOutputsModel($output_ref, $self);
        
        
        $elt_count = $output_ref -> get_element_count;
        $completed = $output_ref -> get_param ('COMPLETED');
        $completed = 1 if not defined $completed;  #  backwards compatibility - old versions did not have this flag

        $self->{output_name} = $output_ref->get_param('NAME');
        $self->{basedata_ref} = $output_ref->get_param('BASEDATA_REF');
        print "[Spatial tab] Existing spatial output - " . $self->{output_name}
              . ". Part of Basedata set - "
              . ($self->{basedata_ref} -> get_param ('NAME') || "no name")
              . "\n";

        if ($elt_count and $completed) {
            $self->queueSetPane(0.01);
        }
        else {
            $self->queueSetPane(1);
        }
        $self->{existing} = 1;
    }
    $self->{output_ref} = $output_ref;

    # Initialise widgets
    $self->{title_widget} = $self->{xmlPage} ->get_widget('txtSpatialName');
    $self->{label_widget} = $self->{xmlLabel}->get_widget('lblSpatialName');

    $self->{title_widget}->set_text($self->{output_name} );
    $self->{label_widget}->set_text($self->{output_name} );
    $self->{tab_menu_label}->set_text($self->{output_name} );

    # Spatial parameters
    my ($initial_sp1, $initial_sp2);
    my $initial_def1 = $NULL_STRING;
    if ($self->{existing}) {
        #$initial_sp1 = $output_ref->get_param("SPATIAL_PARAMS1");
        #$initial_sp2 = $output_ref->get_param("SPATIAL_PARAMS2");
        
        my $spatial_params = $output_ref -> get_param ('SPATIAL_PARAMS');
        #  allow for empty conditions
        $initial_sp1
            = defined $spatial_params->[0]
            ? $spatial_params->[0] -> get_conditions_unparsed()
            : $NULL_STRING;
        $initial_sp2
            = defined $spatial_params->[1]
            ? $spatial_params->[1] -> get_conditions_unparsed()
            : $NULL_STRING;
        
        my $definition_query = $output_ref -> get_param ('DEFINITION_QUERY');
        $initial_def1
            = defined $definition_query
            ? $definition_query -> get_conditions_unparsed()
            : $NULL_STRING;
    }
    else {
        my $cell_sizes = $self->{basedata_ref}->get_param('CELL_SIZES');
        my $cellX = $cell_sizes->[0];
        $initial_sp1 = 'sp_self_only ()';
        $initial_sp2 = "sp_circle (radius => $cellX)";
    }

    $self->{spatial1} = Biodiverse::GUI::SpatialParams->new($initial_sp1);
    my $hide_flag = not (length $initial_sp2);
    $self->{spatial2} = Biodiverse::GUI::SpatialParams->new($initial_sp2, $hide_flag);

    $self->{xmlPage}->get_widget('frameSpatialParams1')->add(
        $self->{spatial1}->get_widget
    );
    $self->{xmlPage}->get_widget('frameSpatialParams2')->add(
        $self->{spatial2}->get_widget
    );
    
    $hide_flag = not (length $initial_def1);
    $self->{definition_query1}
        = Biodiverse::GUI::SpatialParams->new($initial_def1, $hide_flag, 'is_def_query');
    $self->{xmlPage}->get_widget('frameDefinitionQuery1')->add(
        $self->{definition_query1}->get_widget
    );


    $self->{hover_neighbours} = 'Both';
    $self->{xmlPage}->get_widget('comboNeighbours') ->set_active(3);
    $self->{xmlPage}->get_widget('comboColours')    ->set_active(0);
    $self->{xmlPage}->get_widget('colourButton')    ->set_color(
        Gtk2::Gdk::Color->new(65535,0,0)  # red
    ); 

    $self->{analyses_model}
        = Biodiverse::GUI::Tabs::AnalysisTree::makeAnalysesModel (
            $self->{basedata_ref},
            $output_ref,
    );

    Biodiverse::GUI::Tabs::AnalysisTree::initAnalysesTree(
        $self->{xmlPage}->get_widget('treeAnalyses'),
        $self->{analyses_model},
    );

    #  only set it up if it exists (we get errors otherwise)
    if ($completed and $elt_count) {
        eval {
            $self->initGrid();
        };
        if ($EVAL_ERROR) {
            $self->{gui}->report_error ($EVAL_ERROR);
            $self->onClose;
        }
    }
    $self->initListsCombo();
    $self->initOutputAnalysesCombo();
    

    #  CONVERT THIS TO A HASH BASED LOOP, as per Clustering.pm
    # Connect signals
    $self->{xmlLabel}->get_widget('btnSpatialClose')->signal_connect_swapped(clicked   => \&onClose,                 $self);
    $self->{xmlPage} ->get_widget('btnSpatialRun')  ->signal_connect_swapped(clicked   => \&onRun,                   $self);
    $self->{xmlPage} ->get_widget('btnOverlays')    ->signal_connect_swapped(clicked   => \&onOverlays,              $self);
    #  btnAddParam gone for now - retrieve from glade file pre svn 1206
    #$self->{xmlPage} ->get_widget('btnAddParam')    ->signal_connect_swapped(clicked   => \&onAddParam,              $self);
    $self->{xmlPage} ->get_widget('txtSpatialName') ->signal_connect_swapped(changed   => \&onNameChanged,           $self);
    $self->{xmlPage} ->get_widget('comboAnalyses')  ->signal_connect_swapped(changed   => \&onActiveAnalysisChanged, $self);
    $self->{xmlPage} ->get_widget('comboLists')     ->signal_connect_swapped(changed   => \&onActiveListChanged,     $self);
    $self->{xmlPage} ->get_widget('comboColours')   ->signal_connect_swapped(changed   => \&onColoursChanged,        $self);
    $self->{xmlPage} ->get_widget('comboNeighbours')->signal_connect_swapped(changed   => \&onNeighboursChanged,     $self);

    $self->{xmlPage} ->get_widget('btnZoomIn')      ->signal_connect_swapped(clicked   => \&onZoomIn,                $self);
    $self->{xmlPage} ->get_widget('btnZoomOut')     ->signal_connect_swapped(clicked   => \&onZoomOut,               $self);
    $self->{xmlPage} ->get_widget('btnZoomFit')     ->signal_connect_swapped(clicked   => \&onZoomFit,               $self);
    $self->{xmlPage} ->get_widget('colourButton')   ->signal_connect_swapped(color_set => \&onColourSet,             $self);
    

    $self -> set_frame_label_widget;

    print "[Spatial tab] - Loaded tab - Spatial Analysis\n";
    
    return $self;
}


#  doesn't work yet 
sub screenshot {
    my $self = shift;
    return;
    
    
    my $mywidget = $self->{grid}{back_rect};
    my ($width, $height) = $mywidget->window->get_size;

    # create blank pixbuf to hold the image
    my $gdkpixbuf = Gtk2::Gdk::Pixbuf->new (
        'rgb',
        0,
        8,
        $width,
        $height,
    );
    
    $gdkpixbuf->get_from_drawable
        ($mywidget->window, undef, 0, 0, 0, 0, $width, $height);

    my $file = 'testtest.png';
    print "Saving screenshot to $file";
    $gdkpixbuf->save ($file, 'png');
    
    return;
}

sub set_frame_label_widget {
    my $self = shift;
    
    my $widget = Gtk2::ToggleButton->new_with_label('Parameters');
    $widget -> show;

    my $frame = $self->{xmlPage}->get_widget('frame_spatial_parameters');
    $frame -> set_label_widget ($widget);

    $widget->signal_connect_swapped (
        clicked => \&on_show_hide_parameters,
        $self,
    );
    $widget->set_active (0);
    $widget->set_has_tooltip (1);
    $widget->set_tooltip_text ('show/hide the parameters section');

    return;
}

sub on_show_hide_parameters {
    my $self = shift;
    
    my $frame = $self->{xmlPage}->get_widget('frame_spatial_parameters');
    my $widget = $frame -> get_label_widget;
    my $active = $widget -> get_active;

    my $table = $self->{xmlPage}->get_widget('tbl_spatial_parameters');

    if ($active) {
        $table -> hide;
    }
    else {
        $table -> show;
    }

    return;
}


sub initGrid {
    my $self = shift;
    my $frame   = $self->{xmlPage}->get_widget('gridFrame');
    my $hscroll = $self->{xmlPage}->get_widget('gridHScroll');
    my $vscroll = $self->{xmlPage}->get_widget('gridVScroll');

#print "Initialising grid\n";

    # Use closure to automatically pass $self (which grid doesn't know)
    my $hover_closure = sub { $self->onGridHover(@_); };
    my $click_closure = sub {
        Biodiverse::GUI::CellPopup::cellClicked(
            $_[0],
            $self->{grid}->getBaseStruct,
        );
    };

    $self->{grid} = Biodiverse::GUI::Grid->new(
        $frame,
        $hscroll,
        $vscroll,
        1,
        0,
        $hover_closure,
        $click_closure
    );

    if ($self->{existing}) {
        my $data = $self->{output_ref};
        my $elt_count = $data -> get_element_count;
        my $completed = $data -> get_param ('COMPLETED');
        #  backwards compatibility - old versions did not have this flag
        $completed = 1 if not defined $completed;  
        
        if (defined $data and $elt_count and $completed) {
            $self->{grid}->setBaseStruct ($data);
        }
    }

    
    return;
}

sub initListsCombo {
    my $self = shift;


    my $combo = $self->{xmlPage}->get_widget('comboLists');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, text => 0);

    # Only do this if we aren't a new spatial analysis...
    if ($self->{existing}) {
        $self->updateListsCombo();
    }
    
    return;
}

sub initOutputAnalysesCombo {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_widget('comboAnalyses');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, text => 0);

    # Only do this if we aren't a new spatial analysis...
    if ($self->{existing}) {
        $self->updateOutputAnalysesCombo();
    }
    
    return;
}

sub updateListsCombo {
    my $self = shift;

    # Make the model
    $self->{output_lists_model} = $self->makeListsModel();
    my $combo = $self->{xmlPage}->get_widget('comboLists');
    $combo->set_model($self->{output_lists_model});

    # Select the SPATIAL_RESULTS list (or the first one)
    my $iter = $self->{output_lists_model}->get_iter_first();
    my $selected = $iter;
    
    while ($iter) {
        my ($list) = $self->{output_lists_model}->get($iter, 0);
        if ($list eq 'SPATIAL_RESULTS' ) {
            $selected = $iter;
            last; # break loop
        }
        $iter = $self->{output_lists_model}->iter_next($iter);
    }

    if ($selected) {
        $combo->set_active_iter($selected);
    }
    $self->onActiveListChanged($combo);
    
    return;
}

sub updateOutputAnalysesCombo {
    my $self = shift;

    # Make the model
    $self->{output_analysis_model} = $self->makeOutputAnalysisModel();
    my $combo = $self->{xmlPage}->get_widget('comboAnalyses');
    $combo->set_model($self->{output_analysis_model});

    # Select the previous analysis (or the first one)
    my $iter = $self->{output_analysis_model}->get_iter_first();
    my $selected = $iter;
    
    BY_ITER:
    while ($iter) {
        my ($analysis) = $self->{output_analysis_model}->get($iter, 0);
        if ($self->{selected_analysis} && ($analysis eq $self->{selected_analysis}) ) {
            $selected = $iter;
            last BY_ITER; # break loop
        }
        $iter = $self->{output_analysis_model}->iter_next($iter);
    }

    if ($selected) {
        $combo->set_active_iter($selected);
    }
    $self->onActiveAnalysisChanged($combo);
    
    return;
}


# Generates ComboBox model with analyses
# (Jaccard, Endemism, CMP_XXXX) that can be shown on the grid
sub makeOutputAnalysisModel {
    my $self = shift;
    my $list_name = $self->{selected_list};
    my $output_ref = $self->{output_ref};

    # SWL: Get possible analyses by sampling all elements - this allows for asymmetric lists
    #my $bd_ref = $output_ref -> get_param ('BASEDATA_REF') || $output_ref;
    my $elements = $output_ref -> get_element_hash() || {};
    
    my %analyses_tmp;
    foreach my $elt (keys %$elements) {
        #%analyses_tmp = (%analyses_tmp, %{$elements->{$elt}{$list_name}});
        next if ! exists $elements->{$elt}{$list_name};
        my $hash = $elements->{$elt}{$list_name};
        if (scalar keys %$hash) {
            @analyses_tmp{keys %$hash} = values %$hash;
        }
    }
    
    #  are they numeric?  if so then we sort differently.
    my $numeric = 1;
    
    CHECK_NUMERIC:
    foreach my $model (keys %analyses_tmp) {
        if (not looks_like_number ($model)) {
            $numeric = 0;
            last CHECK_NUMERIC;
        }
    }
    
    my @analyses;
    if (scalar keys %analyses_tmp) {
        @analyses = $numeric
            ? sort {$a <=> $b} keys %analyses_tmp   #  numeric
            : sort {$a cmp $b} keys %analyses_tmp;  #  text
    }
    
#print "Making ouput analysis model\n";
#print join (" ", @analyses) . "\n";
    
    # Make model for combobox
    my $model = Gtk2::ListStore->new("Glib::String");
    foreach my $x (@analyses) {
        my $iter = $model->append;
        #print ($model -> get($iter, 0), "\n") if defined $model -> get($iter, 0);    #debug
        $model->set($iter, 0, $x);
        #print ($model -> get($iter, 0), "\n") if defined $model -> get($iter, 0);      #debug
    }

    return $model;
}

# Generates ComboBox model with analyses
# (Jaccard, Endemism, CMP_XXXX) that can be shown on the grid
sub makeListsModel {
    my $self = shift;
    my $output_ref = $self->{output_ref};

    my $lists = $output_ref -> get_lists_across_elements (
        no_private => 1,
        max_search => undef,
    );
 
    #print "Making lists model\n";
    #print join (" ", @lists) . "\n";

    # Make model for combobox
    my $model = Gtk2::ListStore->new('Glib::String');
    foreach my $x (sort @$lists) {
        my $iter = $model->append;
        $model->set($iter, 0, $x);
    }

    return $model;
}



##################################################
# Managing that vertical pane
##################################################

# Sets the vertical pane's position (0 -> all the way down | 1 -> fully up)
sub setPane {
    my $self = shift;
    my $pos = shift;

    my $pane = $self->{xmlPage}->get_widget("vpaneSpatial");
    
    my $maxPos = $pane->get("max-position");
    $pane->set_position( $maxPos * $pos );
    #print "[Spatial tab] Updating pane: maxPos = $maxPos, pos = $pos\n";
    
    return;
}

# This will schedule setPane to be called from a temporary signal handler
# Need when the pane hasn't got it's size yet and doesn't know its max position
sub queueSetPane {
    my $self = shift;
    my $pos = shift;

    my $pane = $self->{xmlPage}->get_widget("vpaneSpatial");

    # remember id so can disconnect later
    my $id = $pane->signal_connect_swapped("size-allocate", \&Biodiverse::GUI::Tabs::Spatial::setPaneSignal, $self);
    $self->{setPaneSignalID} = $id;
    $self->{setPanePos} = $pos;
    
    return;
}

sub setPaneSignal {
    my $self = shift; shift;
    my $pane = shift;
    $self->setPane( $self->{setPanePos} );
    $pane->signal_handler_disconnect( $self->{setPaneSignalID} );
    delete $self->{setPanePos};
    delete $self->{setPaneSignalID};
    
    return;
}
    
##################################################
# Misc interaction with rest of GUI
##################################################


# Make ourselves known to the Outputs tab to that it
# can switch to this tab if the user presses "Show"
#sub registerInOutputsModel {
#    my $self = shift;
#    my $output_ref = shift;
#    my $tabref = shift; # either $self, or undef to deregister
#    my $model = $self->{project}->getBaseDataOutputModel();
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

sub getType {
    return "spatial";
}

#sub onClose {
#    my $self = shift;
#    $self->{gui}->removeTab($self);
#    
#    return;
#}

sub remove {
    my $self = shift;

    eval {$self->{grid}->destroy()};
    $self->{grid} = undef;  #  convoluted, but we're getting reference cycles

    $self->SUPER::remove;
    
    return;
}



##################################################
# Running analyses
##################################################
sub onRun {
    my $self = shift;

    # Load settings...
    $self->{output_name} = $self->{xmlPage}->get_widget('txtSpatialName')->get_text();

    # Get calculations to run
    my @toRun
        = Biodiverse::GUI::Tabs::AnalysisTree::getAnalysesToRun( $self->{analyses_model} );

    if (scalar @toRun == 0) {
        my $dlg = Gtk2::MessageDialog->new(
            undef,
            'modal',
            'error',
            'close',
            'No calculations selected',
        );
        $dlg->run();
        $dlg->destroy();
        return;
    }
    # Check spatial syntax
    return if ($self->{spatial1}->syntax_check('no_ok') ne 'ok');
    return if ($self->{spatial2}->syntax_check('no_ok') ne 'ok');
    return if ($self->{definition_query1}->syntax_check('no_ok') ne 'ok');

    # Delete existing?
    my $new_result = 1;
    if (defined $self->{output_ref}) {
        my $text = "$self->{output_name} exists.  Do you mean to overwrite it?";
        my $completed = $self->{output_ref}->get_param('COMPLETED');
        if ($self->{existing} and defined $completed and $completed) {
            
            #  drop out if we don't want to overwrite
            my $response = Biodiverse::GUI::YesNoCancel->run({
                header => 'Overwrite?',
                text   => $text}
            );
            return 0 if $response ne 'yes';
        }
        
        #  remove original object, we are recreating it
        $self->{basedata_ref}->delete_output(output => $self->{output_ref});
        $self->{project}->deleteOutput($self->{output_ref});
        $self->{existing} = 0;
        $new_result = 0;
    }
    
    # Add spatial output
    my $output_ref = eval {
        $self->{basedata_ref}->add_spatial_output(
            name => $self->{output_name}
        );
    };
    if ($EVAL_ERROR) {
        $self->{gui} -> report_error ($EVAL_ERROR);
        return;
    }

    $self->{output_ref} = $output_ref;
    $self->{project}->addOutput($self->{basedata_ref}, $output_ref);
    
    #my $progress_bar = Biodiverse::GUI::ProgressDialog->new;

    my %args = (
        spatial_conditions  => [
            $self->{spatial1}->get_text(),
            $self->{spatial2}->get_text(),
        ],
        definition_query    => $self->{definition_query1}->get_text(),
        calculations        => \@toRun,
        matrix_ref          => $self->{project}->getSelectedMatrix,
        tree_ref            => $self->{project}->getSelectedPhylogeny,
        #progress            => $progress_bar,
    );

    # Perform the analysis
    print "[Spatial tab] Running @toRun\n";
    #$self->{output_ref}->sp_calc(%args);
    my $success = eval {
        $output_ref->sp_calc(%args)
    };  #  wrap it in an eval to trap any errors
    if ($EVAL_ERROR) {
        $self->{gui} -> report_error ($EVAL_ERROR);
    }

    #$progress_bar->destroy;
    
    if ($success) {
        $self->registerInOutputsModel($output_ref, $self);
    }

    $self->{project}->updateAnalysesRows($output_ref);

    if (not $success) {
        $self -> onClose;  #  close the tab to avoid horrible problems with multiple instances
        return;  # sp_calc dropped out for some reason, eg no valid calculations.
    }

    my $isnew = 0;
    if ($self->{existing} == 0) {
        $isnew = 1;
        $self->{existing} = 1;
    }

    my $response = Biodiverse::GUI::YesNoCancel->run({
        title  => 'display?',
        header => 'display results?',
    });

    if ($response eq 'yes') {
        # If just ran a new analysis, pull up the pane
        $self->setPane(0.01);
    
        # Update output display if we are a new result
        # or grid is not defined yet (this can happen)
        if ($new_result || !defined $self->{grid}) {
            $self->initGrid();
        }
        #  else reuse the grid and just reset the basestruct
        elsif (defined $output_ref) {
            $self->{grid}->setBaseStruct($output_ref);
        }
        $self->updateListsCombo(); # will display first analysis as a side-effect...
    }

    return;
}

##################################################
# Misc dialog operations
##################################################

# Called by grid when user hovers over a cell
# and when mouse leaves a cell (element undef)
sub onGridHover {
    my $self = shift;
    my $element = shift;

    my $output_ref = $self->{output_ref};
    my $text = '';
    
    my $bd_ref = $output_ref -> get_param ('BASEDATA_REF') || $output_ref;

    if ($element) {
        no warnings 'uninitialized';  #  sometimes the selected_list or analysis is undefined
        # Update the Value label
        my $elts = $output_ref -> get_element_hash();

        my $val = $elts->{$element}{ $self->{selected_list} }{$self->{selected_analysis}};

        $text = defined $val
            ? sprintf (
                '<b>%s, Output - %s: </b> %.4f',
                $element,
                $self->{selected_analysis},
                $val
            ) # round to 4 d.p.
            : '<b>Output</b>'; 
        $self->{xmlPage}->get_widget('lblOutput')->set_markup($text);

        # Mark out neighbours
        my $neighbours = $self->{hover_neighbours};
        
        #  take advantage of the caching now in use - let sp_calc handle these calcs
        my @nbr_list;
        $nbr_list[0] = $output_ref -> get_list_values (
            element => $element,
            list    => '_NBR_SET1',
        );
        $nbr_list[1] = $output_ref -> get_list_values (
            element => $element,
            list    => '_NBR_SET2',
        );

        my $nbrs_inner = $nbr_list[0] || [];
        my $nbrs_outer = $nbr_list[1] || [];  #  an empty list by default

        my (%nbrs_hash_inner, %nbrs_hash_outer);
        @nbrs_hash_inner{ @$nbrs_inner } = undef; # convert to hash using a hash slice (thanks google)
        @nbrs_hash_outer{ @$nbrs_outer } = undef; # convert to hash using a hash slice (thanks google)



        if ($neighbours eq 'Set1' || $neighbours eq 'Both') {
            $self->{grid}->markIfExists(\%nbrs_hash_inner, 'circle');
        }
        if ($neighbours eq 'Set2' || $neighbours eq 'Both') {
            $self->{grid}->markIfExists(\%nbrs_hash_outer, 'minus');
        }
    }
    else {
        $self->{grid}->markIfExists({}, 'circle');
        $self->{grid}->markIfExists({}, 'minus');
    }
    
    return;
}

# Keep name in sync with the tab label
# and do a rename if the object exists
sub onNameChanged {
    my $self = shift;
    
    my $xml_page = $self->{xmlPage};
    my $name = $xml_page->get_widget('txtSpatialName')->get_text();

    my $label_widget = $self->{xmlLabel}->get_widget('lblSpatialName');
    $label_widget->set_text($name);

    my $tab_menu_label = $self->{tab_menu_label};
    $tab_menu_label->set_text($name);

    my $param_widget
        = $xml_page->get_widget('lbl_parameter_spatial_name');
    $param_widget->set_markup("<b>Name</b>");

    my $bd = $self->{basedata_ref};

    my $name_in_use = $bd -> get_spatial_output_ref (name => $name);
    
    #  make things go red
    if ($name_in_use) {
        #  colour the label red if the list exists
        my $label = $name;
        my $span_leader = '<span foreground="red">';
        my $span_ender  = ' <b>Name exists</b></span>';

        $label =  $span_leader . $label . $span_ender;
        $label_widget->set_markup ($label);
        
        $param_widget->set_markup ("$span_leader <b>Name </b>$span_ender");

        return;
    }

    # rename
    if ($self->{existing}) {
        my $object = $self->{output_ref};
        eval {
            $bd->rename_output(
                output   => $object,
                new_name => $name
            );
        };
        if ($EVAL_ERROR) {
            $self->{gui}->report_error ($EVAL_ERROR);
            return;
        }

        $self->{project}->updateOutputName( $object );
        $self->{output_name} = $name;
    }
    
    return;
}


# Called by output tab to make us show some analysis
sub showAnalysis {
    my $self = shift;
    my $name = shift;

    # Reinitialising is a cheap way of showing 
    # the SPATIAL_RESULTS list (the default), and
    # selecting what we want

    $self->{selected_analysis} = $name;
    $self->updateListsCombo();
    $self->updateOutputAnalysesCombo();
    
    return;
}

sub onActiveListChanged {
    my $self = shift;
    my $combo = shift;

    my $iter = $combo->get_active_iter() || return;
    my ($list) = $self->{output_lists_model}->get($iter, 0);

    $self->{selected_list} = $list;
    $self->updateOutputAnalysesCombo();
    
    return;
}

sub onActiveAnalysisChanged {
    my $self = shift;
    my $combo = shift;

    my $iter = $combo->get_active_iter() || return;
    my ($analysis) = $self->{output_analysis_model}->get($iter, 0);

    $self->{selected_analysis} = $analysis;  #  should be called calculation
    my $list = $self->{selected_list};
    my $elements_hash = $self->{output_ref}->get_element_hash;
    my $output_ref = $self->{output_ref};
    
    # need to work out min/max for all elements over this analysis
    my ($min, $max);
    #foreach my $lists (values %$elements_hash) {
    #    my $val = $lists->{$list} if defined $lists;
    #    $val = $val->{$analysis} if defined $val;
    #    if (defined $val) {
    #        $min = $val if ((not defined $min) || $val < $min);
    #        $max = $val if ((not defined $max) || $val > $max);
    #    }
    #}
    
    ELEMENT:
    foreach my $element ($output_ref->get_element_list) {
        my $list_ref = $output_ref->get_list_ref(
            element    => $element,
            list       => $list,
            autovivify => 0,
        );
        next ELEMENT if ! defined $list_ref;
        next ELEMENT if ! exists $list_ref->{$analysis};
        
        my $val = $list_ref->{$analysis};
        next ELEMENT if ! defined $val;
        if ((!defined $min) || $val < $min) {
            $min = $val;
        }
        if ((!defined $max) || $val > $max) {
            $max = $val;
        }
    }
    
    $self->{max} = $max;
    $self->{min} = $min;

    $self->recolour();

    return;
}

sub recolour {
    my $self = shift;
    my ($max, $min) = ($self->{max} || 0, $self->{min} || 0);

    # callback function to get colour of each element
    my $grid = $self->{grid};
    return if not defined $grid;  #  if no grid then no need to colour.
    
    my $elements_hash = $self->{output_ref}->get_element_hash;
    my $list = $self->{selected_list};
    my $analysis = $self->{selected_analysis};

    my $colour_func = sub {
        my $elt = shift;
        my $val = $elements_hash->{$elt}->{$list}->{$analysis};
        return defined $val
            ? $grid->getColour($val, $min, $max)
            : undef;
    };

    $grid->colour($colour_func);
    $grid->setLegendMinMax($min, $max);
    
    return;
}

sub onZoomIn {
    my $self = shift;
    
    $self->{grid}->zoomIn();
    
    return;
}

sub onZoomOut {
    my $self = shift;
    
    $self->{grid}->zoomOut();
    
    return;
}

sub onZoomFit {
    my $self = shift;
    $self->{grid}->zoomFit();
    
    return;
}

sub onColoursChanged {
    my $self = shift;
    my $colours = $self->{xmlPage}->get_widget('comboColours')->get_active_text();
    $self->{grid}->setLegendMode($colours);
    $self->recolour();
    
    return;
}

sub onNeighboursChanged {
    my $self = shift;
    my $sel = $self->{xmlPage}->get_widget('comboNeighbours')->get_active_text();
    $self->{hover_neighbours} = $sel;

    # Turn off markings if deselected
    if ($sel eq 'Set1' || $sel eq 'Off') {
        $self->{grid}->markIfExists({}, 'minus');
    }
    if ($sel eq 'Set2' || $sel eq 'Off') {
        $self->{grid}->markIfExists({}, 'circle');
    }
    
    return;
}

#  should be called onSatSet
sub onColourSet {
    my $self = shift;
    my $button = shift;

    my $combo_colours_hue_choice = 1;

    my $widget = $self->{xmlPage}->get_widget('comboColours');
    
    #  a bodge to set the active colour mode to Hue
    my $active = $widget->get_active;
    
    $widget->set_active($combo_colours_hue_choice);
    $self->{grid}->setLegendHue($button->get_color());
    $self->recolour();
    
    return;
}

sub onOverlays {
    my $self = shift;
    my $button = shift;

    Biodiverse::GUI::Overlays::showDialog( $self->{grid} );
    
    return;
}

sub onAddParam {
    my $self = shift;
    my $button = shift; # the "add param" button

    my $table = $self->{xmlPage}->get_widget('tblParams');

    # Add an extra row
    my ($rows) = $table->get('n-rows');
    print "currently has $rows rows. ";
    $rows++;
    $table->set('n-rows' => $rows);
    print "now has $rows rows\n";

    # Move the button to the last row
    $table->remove($button);
    $table->attach($button, 0, 1, $rows, $rows + 1, [], [], 0, 0);

    # Make a combobox and a label to set the parameter
    my $combo = Gtk2::ComboBox->new_text;
    my $entry = Gtk2::Entry->new;

    $table->attach($combo, 0, 1, $rows - 1, $rows, 'fill', [], 0, 0);
    $table->attach($entry, 1, 2, $rows - 1, $rows, 'fill', [], 0, 0);

    $combo->show; $entry->show;

    # Add the optional parameters
    $combo->prepend_text("..these are not yet heeded..");
    $combo->prepend_text("Use Matrix");
    $combo->prepend_text("Max Richness");

    return;
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

sub DESTROY {}  #  let the system handle destruction - need this for AUTOLOADER


1;
