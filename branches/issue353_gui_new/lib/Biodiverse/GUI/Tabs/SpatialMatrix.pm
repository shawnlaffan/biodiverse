package Biodiverse::GUI::Tabs::SpatialMatrix;
use strict;
use warnings;
use 5.010;

use English ( -no_match_vars );

our $VERSION = '0.99_001';

use Gtk2;
use Carp;
use Scalar::Util qw /blessed looks_like_number/;

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Grid;
use Biodiverse::GUI::Overlays;
use Biodiverse::GUI::Project;

use Biodiverse::Matrix;  #  needed?
use Data::Dumper;

use parent qw {
    Biodiverse::GUI::Tabs::Spatial
    Biodiverse::GUI::Tabs::Tab
};


my $NULL_STRING = q{};
my $elements_list_name = 'ELEMENTS';

##################################################
# Initialisation
##################################################

sub new {
    my $class = shift;
    my $matrix_ref = shift; # will be undef if none specified

    croak "argument matrix_ref not specified\n" if !$matrix_ref;
    croak "Unable to display.  Matrix has no elements\n" if !$matrix_ref->get_element_count;
    
    my $self = {gui => Biodiverse::GUI::GUIManager->instance()};
    $self->{project} = $self->{gui}->get_project();
    bless $self, $class;

    my $bd = $matrix_ref->get_param('BASEDATA_REF');
    my $groups_ref = $bd->get_groups_ref;
    $self->{basedata_ref} = $bd;
    $self->{output_ref}   = $matrix_ref;
    $self->{groups_ref}   = $groups_ref;
    $self->{output_name}  = $matrix_ref->get_param('NAME');
    
    # handle pre v0.16 basestructs that didn't have this ref
    if (! $groups_ref->get_param('BASEDATA_REF')) {
        $groups_ref->set_param(BASEDATA_REF => $bd);
        $groups_ref->weaken_basedata_ref;
    }

    # Load _new_ widgets from glade 
    # (we can have many Analysis tabs open, for example. These have a different object/widgets)
    $self->{xmlPage}  = Gtk2::GladeXML->new($self->{gui}->get_glade_file, 'hboxSpatialPage');
    $self->{xmlLabel} = Gtk2::GladeXML->new($self->{gui}->get_glade_file, 'hboxSpatialLabel');

    my $page  = $self->{xmlPage}->get_widget('hboxSpatialPage');
    my $label = $self->{xmlLabel}->get_widget('hboxSpatialLabel');
    my $label_text = $self->{xmlLabel}->get_widget('lblSpatialName')->get_text;
    my $label_widget = Gtk2::Label->new ($label_text);
    $self->{tab_menu_label} = $label_widget;

    # Set up options menu
    $self->{toolbar_menu} = $self->{xmlPage}->get_widget('menu_spatial_data');

    # Add to notebook
    $self->add_to_notebook (
        page         => $page,
        label        => $label,
        label_widget => $label_widget,
    );

    my ($elt_count, $completed);  #  used to control display

    croak "Only existing outputs can be displayed\n" if (not defined $groups_ref );

    #else {
        # We're being called to show an EXISTING output

        # Register as a tab for this output
        $self->register_in_outputs_model($matrix_ref, $self);
        
        $elt_count = $groups_ref->get_element_count;
        $completed = $groups_ref->get_param ('COMPLETED');
        $completed //= 1;  #  backwards compatibility - old versions did not have this flag

        my $elements = $groups_ref->get_element_list_sorted;
        $self->{selected_element} = $elements->[0];

        say "[SpatialMatrix tab] Existing matrix output - "
            . $self->{output_name}
            . ". Part of Basedata set - "
            . ($self->{basedata_ref}->get_param ('NAME') || "no name");

        $self->queue_set_pane(0.01);
        $self->{existing} = 1;
#}

        # Initialise widgets
        $self->{title_widget} = $self->{xmlPage} ->get_widget('txtSpatialName');
        $self->{label_widget} = $self->{xmlLabel}->get_widget('lblSpatialName');

        $self->{title_widget}->set_text($self->{output_name} );
        $self->{label_widget}->set_text($self->{output_name} );


        #$self->{hover_neighbours} = 'Both';
        #$self->{xmlPage}->get_widget('comboNeighbours') ->set_active(3);
        #$self->{xmlPage}->get_widget('comboSpatialStretch')->set_active(0);
        #$self->{xmlPage}->get_widget('comboNeighbours') ->hide;
        #$self->{xmlPage}->get_widget('comboColours')    ->set_active(0);
        #$self->{xmlPage}->get_widget('colourButton')    ->set_color(
        #        Gtk2::Gdk::Color->new(65535,0,0)  # red
        #        ); 

        $self->set_plot_min_max_values;


        eval {
            $self->init_grid();
        };
        if ($EVAL_ERROR) {
            $self->{gui}->report_error ($EVAL_ERROR);
            $self->on_close;
        }


        # Connect signals
        $self->{xmlLabel}->get_widget('btnSpatialClose')->signal_connect_swapped(
            clicked => \&on_close, $self
        );
        my %widgets_and_signals = (
            btnSpatialRun  => { clicked => \&on_run },
            #btnOverlays => { clicked => \&on_overlays },
            txtSpatialName => { changed => \&on_name_changed },
            #comboLists     => { changed => \&on_active_list_changed },
            comboIndices   => { changed   => \&on_active_index_changed },

            #comboColours => { changed => \&on_colours_changed},
            #comboSpatialStretch => { changed => \&on_stretch_changed},

            #  need to refactor common elements with Spatial.pm
            btnSelectToolSP  => {clicked => \&on_select_tool},
            btnPanToolSP     => {clicked => \&on_pan_tool},
            btnZoomToolSP    => {clicked => \&on_zoom_tool},
            btnZoomOutToolSP => {clicked => \&on_zoom_out_tool},
            btnZoomFitToolSP => {clicked => \&on_zoom_fit_tool},

            #colourButton => { color_set => \&on_colour_set},

            menuitem_spatial_overlays => {activate => \&on_overlays},

            menuitem_spatial_colour_mode_hue  => {toggled  => \&on_colour_mode_changed},
            menuitem_spatial_colour_mode_sat  => {activate => \&on_colour_mode_changed},
            menuitem_spatial_colour_mode_grey => {toggled  => \&on_colour_mode_changed},
        );

        for my $n (0..6) {
            my $widget_name = "radio_colour_stretch$n";
            $widgets_and_signals{$widget_name} = {toggled => \&on_menu_stretch_changed};
        }

      WIDGET:
        foreach my $widget_name (sort keys %widgets_and_signals) {
            my $args = $widgets_and_signals{$widget_name};
            my $widget = $self->{xmlPage}->get_widget($widget_name);
            if (!$widget) {
                warn "$widget_name cannot be found\n";
                next WIDGET;
            }

            $widget->signal_connect_swapped(
                %$args,
                $self,
            );
        }


#  do some hiding
        my @to_hide = qw /
            comboLists
            comboNeighbours
            label_spatial_neighbours_combo
            frame_spatial_analysis_tree
            separatortoolitem4
            btnSpatialRun
            labelNbrSet1
            labelNbrSet2
            labelDefQuery1
            menuitem_spatial_nbr_highlighting
        /;
        foreach my $w_name (@to_hide) {
            my $w = $self->{xmlPage}->get_widget($w_name);
            next if !defined $w;
            $w->hide;
        }

        $self->init_output_indices_combo();
        #$self->update_output_indices_menu();

        $self->set_frame_label_widget;

        $self->{drag_modes} = {
            Select  => 'select',
            Pan     => 'pan',
            Zoom    => 'select',
            ZoomOut => 'click',
            ZoomFit => 'click',
        };

        $self->choose_tool('Select');

        print "[SpatialMatrix tab] - Loaded tab \n";


        #  debug stuff
        $self->{selected_list} = 'SUBELEMENTS';

        return $self;
}


sub set_frame_label_widget {
    my $self = shift;

    my $label = $self->{xmlPage}->get_widget('label_spatial_parameters');
    $label->hide;

    return;

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
    return;

}


sub init_grid {
    my $self = shift;
    my $frame   = $self->{xmlPage}->get_widget('gridFrame');
    my $hscroll = $self->{xmlPage}->get_widget('gridHScroll');
    my $vscroll = $self->{xmlPage}->get_widget('gridVScroll');

#print "Initialising grid\n";

# Use closure to automatically pass $self (which grid doesn't know)
    my $hover_closure = sub { $self->on_grid_hover(@_); };
    my $click_closure = sub {
        Biodiverse::GUI::CellPopup::cell_clicked(
            $_[0],
            $self->{groups_ref},
        );
    };
    my $grid_click_closure = sub { $self->on_grid_click(@_); };
    my $select_closure = sub { $self->on_grid_select(@_); };

    $self->{grid} = Biodiverse::GUI::Grid->new(
            $frame,
            $hscroll,
            $vscroll,
            1,
            0,
            $hover_closure,
            $click_closure, # Middle click
            $select_closure,
            $grid_click_closure, # Left click
            );

    my $data = $self->{groups_ref};  #  should be the groups?
        my $elt_count = $data->get_element_count;
    my $completed = $data->get_param ('COMPLETED');
#  backwards compatibility - old versions did not have this flag
    $completed = 1 if not defined $completed;  

    if (defined $data and $elt_count and $completed) {
        $self->{grid}->set_base_struct ($data);
    }

    $self->{grid}->{page} = $self; # Hacky

        return;
}

sub init_lists_combo {
    my $self = shift;
    return;

}

sub update_lists_combo {
    my $self = shift;
    return;
}

# Generates array with analyses
# (Jaccard, Endemism, CMP_XXXX) that can be shown on the grid
sub make_output_indices_array {
    my $self = shift;

    my $matrix_ref = $self->{output_ref};
    my $element_array = $matrix_ref->get_elements_as_array;
    my $groups_ref = $self->{groups_ref};

# Make array
    my @array = ();
    foreach my $x (reverse $groups_ref->get_element_list_sorted(list => $element_array)) {
#print ($model->get($iter, 0), "\n") if defined $model->get($iter, 0);    #debug
        push(@array, $x);
#print ($model->get($iter, 0), "\n") if defined $model->get($iter, 0);      #debug
    }

    return [@array];
}

# Generates ComboBox model with analyses
# (Jaccard, Endemism, CMP_XXXX) that can be shown on the grid
sub make_output_indices_model {
    my $self = shift;

    my $matrix_ref = $self->{output_ref};
    my $element_array = $matrix_ref->get_elements_as_array;
    my $groups_ref = $self->{groups_ref};

    # Make model for combobox
    my $model = Gtk2::ListStore->new('Glib::String');
    foreach my $x (reverse $groups_ref->get_element_list_sorted(list => $element_array)) {
        my $iter = $model->append;
        #print ($model->get($iter, 0), "\n") if defined $model->get($iter, 0);    #debug
        $model->set($iter, 0, $x);
        #print ($model->get($iter, 0), "\n") if defined $model->get($iter, 0);      #debug
    }

    return $model;
}

# Generates ComboBox model with analyses
#  hidden 
sub make_lists_model {
    my $self = shift;
    my $output_ref = $self->{output_ref};

    my $lists = ('$elements_list_name');

# Make model for combobox
    my $model = Gtk2::ListStore->new('Glib::String');
    foreach my $x (sort @$lists) {
        my $iter = $model->append;
        $model->set($iter, 0, $x);
    }

    return $model;
}


##################################################
# Misc interaction with rest of GUI
##################################################

sub get_type {
    return "spatialmatrix";
}


##################################################
# Running analyses
##################################################
sub on_run {
    my $self = shift;

    print "[SpatialMatrix] Cannot run this analysis.  "
        . "Use a cluster analysis to generate the matrix\n";

    return;
}

##################################################
# Misc dialog operations
##################################################

sub on_cell_selected {
    my $self = shift;
    my $data = shift;

    my $element;
    if (scalar @$data == 1) {
        $element = $data->[0];
    }
    else {  #  get the first sorted element that is in the matrix
        my @sorted = $self->{groups_ref}->get_element_list_sorted (list => $data);
        CHECK_SORTED:
        while (defined ($element = shift @sorted)) {
            last CHECK_SORTED
              if $self->{output_ref}->element_is_in_matrix (element => $element);
        }
        
    }

    return if ! defined $element;
    return if $element eq $self->{selected_element};
    return if ! $self->{output_ref}->element_is_in_matrix (element => $element);

    #print "Element selected: $element\n";

    $self->{selected_element} = $element;

    my $combo = $self->{xmlPage}->get_widget('comboIndices');
    $combo->set_model($self->{output_indices_model});  #  already have this?

    # Select the previous analysis (or the first one)
    my $iter = $self->{output_indices_model}->get_iter_first();
    my $selected = $iter;
    
    BY_ITER:
    while ($iter) {
        my ($analysis) = $self->{output_indices_model}->get($iter, 0);
        if ($self->{selected_element} && ($analysis eq $self->{selected_element}) ) {
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

# Called by grid when user hovers over a cell
# and when mouse leaves a cell (element undef)
sub on_grid_hover {
    my $self = shift;
    my $element = shift;

    return if ! defined $element;

    my $matrix_ref = $self->{output_ref};
    my $output_ref = $self->{groups_ref};
    my $text = '';

    my $bd_ref = $output_ref->get_param ('BASEDATA_REF');

    if ($element) {
        no warnings 'uninitialized';  #  sometimes the selected_list or analysis is undefined
# Update the Value label
#my $elts = $output_ref->get_element_hash();

            my $val = $matrix_ref->get_value (
                    element1 => $element,
                    element2 => $self->{selected_element},
                    );

        $text = defined $val
            ? sprintf (
                    '<b>%s</b> v <b>%s</b>, value: %s',  #  should list the index used
                    $self->{selected_element},
                    $element,
                    $self->format_number_for_display (number => $val),
                    ) # round to 4 d.p.
            : '<b>Selected element: ' . $self->{selected_element} . '</b>'; 
        $self->{xmlPage}->get_widget('lblOutput')->set_markup($text);

    }

    return;
}


# Called by output tab to make us show some analysis
sub show_analysis {
    my $self = shift;
    my $name = shift;

    # Reinitialising is a cheap way of showing 
    # the SPATIAL_RESULTS list (the default), and
    # selecting what we want

    #$self->{selected_element} = $name;
    #$self->update_lists_combo();
    $self->update_output_calculations_combo();

    return;
}

sub on_active_index_changed {
    my $self  = shift;
    my $combo = shift
              ||  $self->{xmlPage}->get_widget('comboIndices');

    my $iter = $combo->get_active_iter() || return;
    my $element = $self->{output_indices_model}->get($iter, 0);

    $self->{selected_element} = $element;

    #  This is redundant when only changing the element,
    #  but doesn't take long and makes stretch changes easier.  
    $self->set_plot_min_max_values;  

    $self->recolour();

    return;
}

sub on_menu_colours_changed {
    my $args = shift;
    my ($self, $type) = @$args;

    $self->{grid}->set_legend_mode($type);
    $self->recolour();

    return;
}

sub set_plot_min_max_values {
    my $self = shift;

    my $matrix_ref = $self->{output_ref};

    my $stats = $self->{stats};

    if (not $stats) {
        $stats = $matrix_ref->get_summary_stats;
        $self->{stats} = $stats;  #  store it
    }

    $self->{plot_max_value} = $stats->{$self->{PLOT_STAT_MAX} || 'MAX'};
    $self->{plot_min_value} = $stats->{$self->{PLOT_STAT_MIN} || 'MIN'};

    $self->set_legend_ltgt_flags ($stats);

    return;
}

sub recolour {
    my $self = shift;
    my ($max, $min) = ($self->{plot_max_value} || 0, $self->{plot_min_value} || 0);

# callback function to get colour of each element
    my $grid = $self->{grid};
    return if not defined $grid;  #  if no grid then no need to colour.

#my $elements_hash = $self->{groups_ref}->get_element_hash;
    my $matrix_ref    = $self->{output_ref};
    my $sel_element   = $self->{selected_element};

    my $colour_func = sub {
        my $elt = shift;
        if ($elt eq $sel_element) {  #  mid grey
            return $grid->get_colour_grey (($min + $max + $max) / 3, $min, $max);
        }
        my $val = $matrix_ref->get_value (
            element1 => $elt,
            element2 => $sel_element,
        );
        return defined $val
            ? $grid->get_colour($val, $min, $max)
            : undef;
    };

    $grid->colour($colour_func);
    $grid->set_legend_min_max($min, $max);
    
    return;
}


sub on_neighbours_changed {
    my $self = shift;
    return;
}

# Override to add on_cell_selected
sub on_grid_select {
    my ($self, $groups, $ignore_change, $rect) = @_;
    if ($self->{tool} eq 'Select') {
        shift;
        $self->on_cell_selected(@_);
    }
    elsif ($self->{tool} eq 'Zoom') {
        my $grid = $self->{grid};
        handle_grid_drag_zoom($grid, $rect);
    }
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

    $method = 'SUPER::' . $method;
    #print $method, "\n";
    return $self->$method (@_);
}

sub DESTROY {}  #  let the system handle destruction - need this for AUTOLOADER

1;
