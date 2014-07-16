package Biodiverse::GUI::Tabs::Spatial;
use 5.010;
use strict;
use warnings;

use English ( -no_match_vars );

our $VERSION = '0.99_001';

use Gtk2;
use Carp;
use Scalar::Util qw /blessed looks_like_number/;
use Time::HiRes;

use Biodiverse::GUI::GUIManager;
#use Biodiverse::GUI::ProgressDialog;
use Biodiverse::GUI::Grid;
use Biodiverse::GUI::Overlays;
use Biodiverse::GUI::Project;
use Biodiverse::GUI::SpatialParams;
use Biodiverse::GUI::Tabs::CalculationsTree;

use Biodiverse::Spatial;
use Data::Dumper;

use parent qw {
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
    $self->{project} = $self->{gui}->get_project();
    bless $self, $class;

    # Load _new_ widgets from glade 
    # (we can have many Analysis tabs open, for example. These have a different object/widgets)
    $self->{xmlPage}  = Gtk2::GladeXML->new($self->{gui}->get_glade_file, 'vpaneSpatial');
    $self->{xmlLabel} = Gtk2::GladeXML->new($self->{gui}->get_glade_file, 'hboxSpatialLabel');

    my $page  = $self->{xmlPage}->get_widget('vpaneSpatial');
    my $label = $self->{xmlLabel}->get_widget('hboxSpatialLabel');
    my $label_text = $self->{xmlLabel}->get_widget('lblSpatialName')->get_text;
    my $label_widget = Gtk2::Label->new ($label_text);
    $self->{tab_menu_label} = $label_widget;

    # Add to notebook
    $self->add_to_notebook (
        page         => $page,
        label        => $label,
        label_widget => $label_widget,
    );

    my ($elt_count, $completed);  #  used to control display

    if (not defined $output_ref) {
        # We're being called as a NEW output
        # Generate a new output name
        my $bd = $self->{basedata_ref} = $self->{project}->get_selected_base_data;
        
        if (not blessed ($bd)) {  #  this should be fixed now
            $self->on_close;
            croak "Basedata ref undefined - click on the basedata object in "
                    . "the outputs tab to select it (this is a bug)\n";
        }
        
        #  check if it has rand outputs already and warn the user
        if (my @a = $bd->get_randomisation_output_refs) {
            my $response
                = $self->{gui}->warn_outputs_exist_if_randomisation_run(
                    $self->{basedata_ref}->get_param ('NAME')
                );
            if (not $response eq 'yes') {
                $self->on_close;
                croak "User cancelled operation\n";
            }
        }

        $self->{output_name} = $self->{project}->make_new_output_name(
            $self->{basedata_ref},
            'Spatial'
        );
        print "[Spatial tab] New spatial output " . $self->{output_name} . "\n";

        $self->queue_set_pane(1);
        $self->{existing} = 0;
    }
    else {
        # We're being called to show an EXISTING output

        # Register as a tab for this output
        $self->register_in_outputs_model($output_ref, $self);
        
        
        $elt_count = $output_ref->get_element_count;
        $completed = $output_ref->get_param ('COMPLETED');
        #  backwards compatibility - old versions did not have this flag
        $completed //= 1;

        $self->{output_name} = $output_ref->get_param('NAME');
        $self->{basedata_ref} = $output_ref->get_param('BASEDATA_REF');
        print "[Spatial tab] Existing spatial output - " . $self->{output_name}
              . ". Part of Basedata set - "
              . ($self->{basedata_ref}->get_param ('NAME') || "no name")
              . "\n";

        if ($elt_count and $completed) {
            $self->queue_set_pane(0.01);
        }
        else {
            $self->queue_set_pane(1);
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
        
        my $spatial_conditions = $output_ref->get_spatial_conditions;
        #  allow for empty conditions
        $initial_sp1
            = defined $spatial_conditions->[0]
            ? $spatial_conditions->[0]->get_conditions_unparsed()
            : $NULL_STRING;
        $initial_sp2
            = defined $spatial_conditions->[1]
            ? $spatial_conditions->[1]->get_conditions_unparsed()
            : $NULL_STRING;
        
        my $definition_query = $output_ref->get_param ('DEFINITION_QUERY');
        $initial_def1
            = defined $definition_query
            ? $definition_query->get_conditions_unparsed()
            : $NULL_STRING;
    }
    else {
        my $cell_sizes = $self->{basedata_ref}->get_param('CELL_SIZES');
        my $cell_x = $cell_sizes->[0];
        $initial_sp1 = 'sp_self_only ()';
        $initial_sp2 = "sp_circle (radius => $cell_x)";
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

    #  add the basedata ref
    foreach my $sp (qw /spatial1 spatial2 definition_query1/) {
        $self->{$sp}->set_param(BASEDATA_REF => $self->{basedata_ref});
    }

    $self->{hover_neighbours} = 'Both';
    $self->{xmlPage}->get_widget('comboNeighbours') ->set_active(3);
    $self->{xmlPage}->get_widget('comboSpatialStretch')->set_active(0);
    $self->{xmlPage}->get_widget('comboColours')    ->set_active(0);
    $self->{xmlPage}->get_widget('colourButton')    ->set_color(
        Gtk2::Gdk::Color->new(65535,0,0)  # red
    );
    

    $self->{calculations_model}
        = Biodiverse::GUI::Tabs::CalculationsTree::make_calculations_model (
            $self->{basedata_ref},
            $output_ref,
    );

    Biodiverse::GUI::Tabs::CalculationsTree::init_calculations_tree(
        $self->{xmlPage}->get_widget('treeCalculations'),
        $self->{calculations_model},
    );

    #  only set it up if it exists (we get errors otherwise)
    if ($completed and $elt_count) {
        eval {
            $self->init_grid();
        };
        if ($EVAL_ERROR) {
            $self->{gui}->report_error ($EVAL_ERROR);
            $self->on_close;
        }
    }
    $self->init_lists_combo();
    $self->init_output_indices_combo();
    

    #  NEED TO CONVERT THIS TO A HASH BASED LOOP, as per Clustering.pm
    # Connect signals
    $self->{xmlLabel}->get_widget('btnSpatialClose')->signal_connect_swapped(clicked   => \&on_close,                 $self);
    $self->{xmlPage} ->get_widget('btnSpatialRun')  ->signal_connect_swapped(clicked   => \&on_run,                   $self);
    $self->{xmlPage} ->get_widget('btnOverlays')    ->signal_connect_swapped(clicked   => \&on_overlays,              $self);
    #  btnAddParam gone for now - retrieve from glade file pre svn 1206
    #$self->{xmlPage} ->get_widget('btnAddParam')    ->signal_connect_swapped(clicked   => \&on_add_param,              $self);
    $self->{xmlPage} ->get_widget('txtSpatialName') ->signal_connect_swapped(changed   => \&on_name_changed,           $self);
    $self->{xmlPage} ->get_widget('comboIndices')->signal_connect_swapped(changed => \&on_active_index_changed, $self);
    $self->{xmlPage} ->get_widget('comboLists')     ->signal_connect_swapped(changed   => \&on_active_list_changed,     $self);
    $self->{xmlPage} ->get_widget('comboColours')   ->signal_connect_swapped(changed   => \&on_colours_changed,        $self);
    $self->{xmlPage} ->get_widget('comboNeighbours')->signal_connect_swapped(changed   => \&on_neighbours_changed,     $self);
    $self->{xmlPage} ->get_widget('comboSpatialStretch')->signal_connect_swapped(changed   => \&on_stretch_changed,     $self);

    $self->{xmlPage} ->get_widget('btnZoomIn')      ->signal_connect_swapped(clicked   => \&on_zoom_in,                $self);
    $self->{xmlPage} ->get_widget('btnZoomOut')     ->signal_connect_swapped(clicked   => \&on_zoom_out,               $self);
    $self->{xmlPage} ->get_widget('btnZoomFit')     ->signal_connect_swapped(clicked   => \&on_zoom_fit,               $self);
    $self->{xmlPage} ->get_widget('colourButton')   ->signal_connect_swapped(color_set => \&on_colour_set,             $self);
    

    $self->set_frame_label_widget;
    
    #my $options_menu = $self->{xmlPage}->get_widget('menu_spatial_grid_options');
    #$options_menu->set_menu ($self->get_options_menu);
    

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
    $widget->show;

    my $frame = $self->{xmlPage}->get_widget('frame_spatial_parameters');
    $frame->set_label_widget ($widget);

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
    my $widget = $frame->get_label_widget;
    my $active = $widget->get_active;

    my $table = $self->{xmlPage}->get_widget('tbl_spatial_parameters');

    if ($active) {
        $table->hide;
    }
    else {
        $table->show;
    }

    return;
}


sub init_grid {
    my $self = shift;
    my $frame   = $self->{xmlPage}->get_widget('gridFrame');
    my $hscroll = $self->{xmlPage}->get_widget('gridHScroll');
    my $vscroll = $self->{xmlPage}->get_widget('gridVScroll');

#print "Initialising grid\n";

    $self->{initialising_grid} = 1;

    # Use closure to automatically pass $self (which grid doesn't know)
    my $hover_closure = sub { $self->on_grid_hover(@_); };
    my $click_closure = sub {
        Biodiverse::GUI::CellPopup::cell_clicked(
            $_[0],
            $self->{grid}->get_base_struct,
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
        my $elt_count = $data->get_element_count;
        my $completed = $data->get_param ('COMPLETED');
        #  backwards compatibility - old versions did not have this flag
        $completed = 1 if not defined $completed;  
        
        if (defined $data and $elt_count and $completed) {
            $self->{grid}->set_base_struct ($data);
        }
    }

    $self->{initialising_grid} = 0;

    return;
}

sub init_lists_combo {
    my $self = shift;


    my $combo = $self->{xmlPage}->get_widget('comboLists');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, text => 0);

    # Only do this if we aren't a new spatial analysis...
    if ($self->{existing}) {
        $self->update_lists_combo();
    }
    
    return;
}

sub init_output_indices_combo {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_widget('comboIndices');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, text => 0);

    # Only do this if we aren't a new spatial analysis...
    if ($self->{existing}) {
        $self->update_output_indices_combo();
    }
    
    return;
}

sub update_lists_combo {
    my $self = shift;

    # Make the model
    $self->{output_lists_model} = $self->make_lists_model();
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
    $self->on_active_list_changed($combo);
    
    return;
}

sub update_output_indices_combo {
    my $self = shift;

    # Make the model
    $self->{output_indices_model} = $self->make_output_indices_model();
    my $combo = $self->{xmlPage}->get_widget('comboIndices');
    $combo->set_model($self->{output_indices_model});

    # Select the previous analysis (or the first one)
    my $iter = $self->{output_indices_model}->get_iter_first();
    my $selected = $iter;
    
    BY_ITER:
    while ($iter) {
        my ($analysis) = $self->{output_indices_model}->get($iter, 0);
        if ($self->{selected_index} && ($analysis eq $self->{selected_index}) ) {
            $selected = $iter;
            last BY_ITER; # break loop
        }
        $iter = $self->{output_indices_model}->iter_next($iter);
    }

    if ($selected) {
        $combo->set_active_iter($selected);
    }
    $self->on_active_index_changed($combo);
    
    return;
}


# Generates ComboBox model with analyses
# (Jaccard, Endemism, CMP_XXXX) that can be shown on the grid
sub make_output_indices_model {
    my $self = shift;
    my $list_name = $self->{selected_list};
    my $output_ref = $self->{output_ref};

    # SWL: Get possible analyses by sampling all elements - this allows for asymmetric lists
    #my $bd_ref = $output_ref->get_param ('BASEDATA_REF') || $output_ref;
    my $elements = $output_ref->get_element_hash() || {};
    
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
    my $model = Gtk2::ListStore->new('Glib::String');
    foreach my $x (@analyses) {
        my $iter = $model->append;
        #print ($model->get($iter, 0), "\n") if defined $model->get($iter, 0);    #debug
        $model->set($iter, 0, $x);
        #print ($model->get($iter, 0), "\n") if defined $model->get($iter, 0);      #debug
    }

    return $model;
}

# Generates ComboBox model with analyses
# (Jaccard, Endemism, CMP_XXXX) that can be shown on the grid
sub make_lists_model {
    my $self = shift;
    my $output_ref = $self->{output_ref};

    my $lists = $output_ref->get_lists_across_elements (
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
sub set_pane {
    my $self = shift;
    my $pos = shift;

    my $pane = $self->{xmlPage}->get_widget("vpaneSpatial");
    
    my $max_pos = $pane->get('max-position');
    $pane->set_position( $max_pos * $pos );
    #print "[Spatial tab] Updating pane: maxPos = $max_pos, pos = $pos\n";
    
    return;
}

# This will schedule set_pane to be called from a temporary signal handler
# Need when the pane hasn't got it's size yet and doesn't know its max position
sub queue_set_pane {
    my $self = shift;
    my $pos = shift;

    my $pane = $self->{xmlPage}->get_widget("vpaneSpatial");

    # remember id so can disconnect later
    my $id = $pane->signal_connect_swapped("size-allocate", \&Biodiverse::GUI::Tabs::Spatial::set_pane_signal, $self);
    $self->{set_pane_signalID} = $id;
    $self->{set_panePos} = $pos;
    
    return;
}

sub set_pane_signal {
    my $self = shift; shift;  #  FIXME FIXME - check why double shift, assign vars directly from list my ($self, undef, $pane) = @_;
    my $pane = shift;
    $self->set_pane( $self->{set_panePos} );
    $pane->signal_handler_disconnect( $self->{set_pane_signalID} );
    delete $self->{set_panePos};
    delete $self->{set_pane_signalID};
    
    return;
}
    
##################################################
# Misc interaction with rest of GUI
##################################################


sub get_type {
    return "spatial";
}


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
sub on_run {
    my $self = shift;

    # Load settings...
    my $output_name = $self->{xmlPage}->get_widget('txtSpatialName')->get_text();
    $self->{output_name} = $output_name;

    # Get calculations to run
    my @to_run
        = Biodiverse::GUI::Tabs::CalculationsTree::get_calculations_to_run( $self->{calculations_model} );

    if (scalar @to_run == 0) {
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
    return if $self->{spatial1}->syntax_check('no_ok') ne 'ok';
    return if $self->{spatial2}->syntax_check('no_ok') ne 'ok';
    return if $self->{definition_query1}->syntax_check('no_ok') ne 'ok';

    my $new_result = 1;
    my $overwrite  = 0;
    my $output_ref = $self->{output_ref};

    # Delete existing?
    if (defined $output_ref) {
        my $text = "$output_name exists.  Do you mean to overwrite it?";
        my $completed = $output_ref->get_param('COMPLETED') // 1;
        if ($self->{existing} && $completed) {

            #  drop out if we don't want to overwrite
            my $response = Biodiverse::GUI::YesNoCancel->run({
                header  => 'Overwrite? ',
                text    => $text,
                hide_no => 1,
            });
            return 0 if $response ne 'yes';
        }

        $overwrite    = 1;
        $new_result   = 0;
    }

    my $time = time();
    $output_name .= " (tmp$time)";  #  work under a temporary name

    # Add spatial output
    $output_ref = eval {
        $self->{basedata_ref}->add_spatial_output(
            name => $output_name,
        );
    };
    if ($EVAL_ERROR) {
        if ($output_ref) {  #  clean up
            $self->{basedata_ref}->delete_output (output => $output_ref);
        }
        $self->{gui}->report_error ($EVAL_ERROR);
        return;
    }

    my %args = (
        calculations       => \@to_run,
        matrix_ref         => $self->{project}->get_selected_matrix,
        tree_ref           => $self->{project}->get_selected_phylogeny,
        definition_query   => $self->{definition_query1}->get_text(),
        spatial_conditions => [
            $self->{spatial1}->get_text(),
            $self->{spatial2}->get_text(),
        ],
    );

    # Perform the analysis
    $self->{initialising_grid} = 1;  #  desensitise the grid if it is already displayed

    say "[Spatial tab] Running calculations @to_run";

    my $success = eval {
        $output_ref->run_analysis(%args)
    };
    if ($EVAL_ERROR) {
        $self->{gui}->report_error ($EVAL_ERROR);
    }

    #  only add to the project if successful
    if (!$success) {
        #if ($overwrite) {  #  remove the failed run
            $self->{basedata_ref}->delete_output(output => $output_ref);
        #}

        $self->{initialising_grid} = 0;
        $self->on_close;  #  close the tab to avoid horrible problems with multiple instances
        return;  # sp_calc dropped out for some reason, eg no valid calculations.
    }

    if ($overwrite) {  #  clear out the old ref and reinstate the user specified name
        say '[SPATIAL] Replacing old analysis with new version';
        my $old_ref = $self->{output_ref};
        $self->{basedata_ref}->delete_output(output => $old_ref);
        $self->{project}->delete_output($old_ref);
    }

    #  fix the temp name before we add it to the basedata
    $output_ref->rename (new_name => $self->{output_name});
    $self->{output_ref} = $output_ref;
    $self->{project}->add_output($self->{basedata_ref}, $output_ref);

    $self->register_in_outputs_model($output_ref, $self);
    $self->{project}->update_indices_rows($output_ref);

    my $isnew = 0;
    if (!$self->{existing}) {
        $isnew = 1;
        $self->{existing} = 1;
    }

    my $response = Biodiverse::GUI::YesNoCancel->run({
        title  => 'display?',
        header => 'display results?',
    });
    if ($response eq 'yes') {
        # If just ran a new analysis, pull up the pane
        $self->set_pane(0.01);

        # Update output display if we are a new result
        # or grid is not defined yet (this can happen)
        if ($new_result || !defined $self->{grid}) {
            eval {$self->init_grid()};
            if ($EVAL_ERROR) {
                $self->{gui}->report_error ($EVAL_ERROR);
            }
        }
        #  else reuse the grid and just reset the basestruct
        elsif (defined $output_ref) {
            $self->{grid}->set_base_struct($output_ref);
        }
        $self->update_lists_combo(); # will display first analysis as a side-effect...
    }

    #  make sure the grid is sensitive again
    $self->{initialising_grid} = 0;

    $self->{project}->set_dirty;

    return;
}

##################################################
# Misc dialog operations
##################################################

# Called by grid when user hovers over a cell
# and when mouse leaves a cell (element undef)
sub on_grid_hover {
    my $self    = shift;
    my $element = shift;

    #  drop out if we are initialising, otherwise we trigger events on incomplete data
    return if $self->{initialising_grid};

    my $output_ref = $self->{output_ref};
    my $text = $self->get_grid_text_pfx;

    my $bd_ref = $output_ref->get_param ('BASEDATA_REF') || $output_ref;

    if ($element) {
        no warnings 'uninitialized';  #  sometimes the selected_list or analysis is undefined
        # Update the Value label
        my $elts = $output_ref->get_element_hash();

        my $val = $elts->{$element}{ $self->{selected_list} }{$self->{selected_index}};

        $text .= sprintf '<b>%s, Output - %s: </b>',
            $element,
            $self->{selected_index};
        $text .= defined $val
            ? $self->format_number_for_display (number => $val)
            : 'value is undefined';

        $self->{xmlPage}->get_widget('lblOutput')->set_markup($text);

        # Mark out neighbours
        my $neighbours = $self->{hover_neighbours};
        
        #  take advantage of the caching now in use - let sp_calc handle these calcs
        my @nbr_list;
        $nbr_list[0] = $output_ref->get_list_values (
            element => $element,
            list    => '_NBR_SET1',
        );
        $nbr_list[1] = $output_ref->get_list_values (
            element => $element,
            list    => '_NBR_SET2',
        );

        my $nbrs_inner = $nbr_list[0] || [];
        my $nbrs_outer = $nbr_list[1] || [];  #  an empty list by default

        my (%nbrs_hash_inner, %nbrs_hash_outer);
        @nbrs_hash_inner{ @$nbrs_inner } = undef; # convert to hash using a hash slice (thanks google)
        @nbrs_hash_outer{ @$nbrs_outer } = undef; # convert to hash using a hash slice (thanks google)

        if ($neighbours eq 'Set1' || $neighbours eq 'Both') {
            $self->{grid}->mark_if_exists(\%nbrs_hash_inner, 'circle');
        }
        if ($neighbours eq 'Set2' || $neighbours eq 'Both') {
            $self->{grid}->mark_if_exists(\%nbrs_hash_outer, 'minus');
        }
    }
    else {
        $self->{grid}->mark_if_exists({}, 'circle');
        $self->{grid}->mark_if_exists({}, 'minus');
    }
    
    return;
}

# Keep name in sync with the tab label
# and do a rename if the object exists
sub on_name_changed {
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

    my $name_in_use = eval {$bd->get_spatial_output_ref (name => $name)};
    
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

        $self->{project}->update_output_name( $object );
        $self->{output_name} = $name;
    }
    
    return;
}


# Called by output tab to make us show an analysis result
sub show_analysis {
    my $self = shift;
    my $name = shift;

    # Reinitialising is a cheap way of showing 
    # the SPATIAL_RESULTS list (the default), and
    # selecting what we want

    $self->{selected_index} = $name;
    $self->update_lists_combo();
    $self->update_output_indices_combo();
    
    return;
}

sub on_active_list_changed {
    my $self = shift;
    my $combo = shift;

    my $iter = $combo->get_active_iter() || return;
    my ($list) = $self->{output_lists_model}->get($iter, 0);

    $self->{selected_list} = $list;
    $self->update_output_indices_combo();
    
    return;
}

#  should be called on_active_index_changed, but many such occurrences need to be edited
sub on_active_index_changed {
    my $self = shift;
    my $combo = shift
              ||  $self->{xmlPage}->get_widget('comboIndices');

    my $iter = $combo->get_active_iter() || return;
    my ($index) = $self->{output_indices_model}->get($iter, 0);
    $self->{selected_index} = $index;  #  should be called calculation

    $self->set_plot_min_max_values;

    $self->recolour();

    return;
}


sub set_plot_min_max_values {
    my $self = shift;
    
    my $output_ref = $self->{output_ref};

    my $list  = $self->{selected_list};
    my $index = $self->{selected_index};
    
    my $stats = $self->{stats}{$list}{$index};

    if (not $stats) {
        $stats = $output_ref->get_list_value_stats (
            list  => $list,
            index => $index,
        );
        $self->{stats}{$list}{$index} = $stats;  #  store it
    }

    $self->{plot_max_value} = $stats->{$self->{PLOT_STAT_MAX} || 'MAX'};
    $self->{plot_min_value} = $stats->{$self->{PLOT_STAT_MIN} || 'MIN'};    

    $self->set_legend_ltgt_flags ($stats);

    return;
}

#sub set_legend_ltgt_flags {
#    my $self = shift;
#    my $stats = shift;
#
#    my $flag = 0;
#    my $minstat = ($self->{PLOT_STAT_MIN} || 'MIN');
#    eval {
#        if ($stats->{$minstat} != $stats->{MIN}
#            and $minstat =~ /PCT/) {
#            $flag = 1;
#        }
#        $self->{grid}->set_legend_lt_flag ($flag);
#    };
#    $flag = 0;
#    my $maxstat = ($self->{PLOT_STAT_MAX} || 'MAX');
#    eval {
#        if ($stats->{$maxstat} != $stats->{MAX}
#            and $minstat =~ /PCT/) {
#            $flag = 1;
#        }
#        $self->{grid}->set_legend_gt_flag ($flag);
#    };
#    return;
#}

sub on_stretch_changed {
    my $self = shift;
    my $sel = $self->{xmlPage}->get_widget('comboSpatialStretch')->get_active_text();
    
    my ($min, $max) = split (/-/, uc $sel);
    
    my %stretch_codes = $self->get_display_stretch_codes;

    $self->{PLOT_STAT_MAX} = $stretch_codes{$max} || $max;
    $self->{PLOT_STAT_MIN} = $stretch_codes{$min} || $min;

    $self->on_active_index_changed;

    return;
}

sub recolour {
    my $self = shift;
    my ($max, $min) = ($self->{plot_max_value} || 0, $self->{plot_min_value} || 0);

    # callback function to get colour of each element
    my $grid = $self->{grid};
    return if not defined $grid;  #  if no grid then no need to colour.
    
    my $elements_hash = $self->{output_ref}->get_element_hash;
    my $list = $self->{selected_list};
    my $index = $self->{selected_index};

    my $colour_func = sub {
        my $elt = shift // return;
        my $val = $elements_hash->{$elt}{$list}{$index};
        return defined $val
            ? $grid->get_colour($val, $min, $max)
            : undef;
    };

    $grid->colour($colour_func);
    $grid->set_legend_min_max($min, $max);
    
    return;
}

sub on_zoom_in {
    my $self = shift;
    
    $self->{grid}->zoom_in();
    
    return;
}

sub on_zoom_out {
    my $self = shift;
    
    $self->{grid}->zoom_out();
    
    return;
}

sub on_zoom_fit {
    my $self = shift;
    $self->{grid}->zoom_fit();
    
    return;
}

sub on_colours_changed {
    my $self = shift;
    my $colours = $self->{xmlPage}->get_widget('comboColours')->get_active_text();
    $self->{grid}->set_legend_mode($colours);
    $self->recolour();
    
    return;
}

sub on_neighbours_changed {
    my $self = shift;
    my $sel = $self->{xmlPage}->get_widget('comboNeighbours')->get_active_text();
    $self->{hover_neighbours} = $sel;

    # Turn off markings if deselected
    if ($sel eq 'Set1' || $sel eq 'Off') {
        $self->{grid}->mark_if_exists({}, 'minus');
    }
    if ($sel eq 'Set2' || $sel eq 'Off') {
        $self->{grid}->mark_if_exists({}, 'circle');
    }
    
    ##  this is a dirty bodge for testing purposes
    #if ($sel =~ /colour/) {
    #    $self->{grid}->set_cell_outline_colour;
    #}
    
    return;
}

#  should be called onSatSet
sub on_colour_set {
    my $self = shift;
    my $button = shift;

    my $combo_colours_hue_choice = 1;

    my $widget = $self->{xmlPage}->get_widget('comboColours');
    
    #  a bodge to set the active colour mode to Hue
    my $active = $widget->get_active;
    
    $widget->set_active($combo_colours_hue_choice);
    $self->{grid}->set_legend_hue($button->get_color());
    $self->recolour();
    
    return;
}

sub on_overlays {
    my $self = shift;
    my $button = shift;

    Biodiverse::GUI::Overlays::show_dialog( $self->{grid} );
    
    return;
}

sub on_add_param {
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

sub get_options_menu {
    my $self = shift;

    my $menu = Gtk2::Menu->new();

    $menu->append(Gtk2::MenuItem->new('_Cut'));
    $menu->append(Gtk2::MenuItem->new('C_opy'));
    $menu->append(Gtk2::MenuItem->new('_Paste'));

    $menu->show_all();

    return $menu;
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
