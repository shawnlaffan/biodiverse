package Biodiverse::GUI::Tabs::SpatialMatrix;
use strict;
use warnings;
use 5.010;

use English ( -no_match_vars );

our $VERSION = '5.0';

use Gtk3;
use Carp;
use Scalar::Util qw /blessed looks_like_number weaken/;

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Overlays;
use Biodiverse::GUI::Project;

use Biodiverse::Matrix;  #  needed?
#use Data::Dumper;

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

    # (we can have many Analysis tabs open, for example. These have a different object/widgets)
    $self->{xmlPage} = Gtk3::Builder->new();
    $self->{xmlPage}->add_from_file($self->{gui}->get_gtk_ui_file('hboxSpatialPage.ui'));
    $self->{xmlLabel} = Gtk3::Builder->new();
    $self->{xmlLabel}->add_from_file($self->{gui}->get_gtk_ui_file('hboxSpatialLabel.ui'));

    my $page  = $self->get_xmlpage_object('hboxSpatialPage');
    my $label = $self->{xmlLabel}->get_object('hboxSpatialLabel');
    my $label_text   = $self->{xmlLabel}->get_object('lblSpatialName')->get_text;
    my $label_widget = Gtk3::Label->new ($label_text);
    $self->{tab_menu_label} = $label_widget;

    # Set up options menu
    $self->{toolbar_menu} = $self->get_xmlpage_object('menu_spatial_data');

    # Add to notebook
    $self->add_to_notebook (
        page         => $page,
        label        => $label,
        label_widget => $label_widget,
    );

    my ($elt_count, $completed);  #  used to control display

    croak "Only existing outputs can be displayed\n"
      if not defined $groups_ref;

    # We're being called to show an EXISTING output

    # Register as a tab for this output
    $self->register_in_outputs_model($matrix_ref, $self);

    $elt_count = $groups_ref->get_element_count;
    $completed = $groups_ref->get_param ('COMPLETED');
    $completed //= 1;  #  backwards compatibility - old versions did not have this flag

    my $elements = $groups_ref->get_element_list_sorted;
    $self->set_cached_value (ELEMENT_LIST_SORTED => $elements);
    $self->{selected_element} = $elements->[-1];

    say "[SpatialMatrix tab] Existing matrix output - "
        . $self->{output_name}
        . ". Part of Basedata set - "
        . ($self->{basedata_ref}->get_param ('NAME') || "no name");

    $self->queue_set_pane(0.01, 'vpaneSpatial');
    $self->{existing} = 1;


    # Initialise widgets
    $self->{title_widget} = $self->get_xmlpage_object('txtSpatialName');
    $self->{label_widget} = $self->{xmlLabel}->get_object('lblSpatialName');

    $self->{title_widget}->set_text($self->{output_name} );
    $self->{label_widget}->set_text($self->{output_name} );
    $self->set_label_widget_tooltip;

    $self->set_plot_min_max_values;

    $self->queue_set_pane(0.5, 'spatial_hpaned');
    $self->queue_set_pane(1  , 'spatial_vpanePhylogeny');

    eval {
        $self->init_grid();
    };
    if ($EVAL_ERROR) {
        $self->{gui}->report_error ($EVAL_ERROR);
        $self->on_close;
    }

    # Connect signals
    $self->{xmlLabel}->get_object('btnSpatialClose')->signal_connect_swapped(
        clicked => \&on_close, $self
    );
    my %widgets_and_signals = (
        btnSpatialRun  => { clicked => \&on_run },
        txtSpatialName => { changed => \&on_name_changed },

        #  need to refactor common elements with Spatial.pm
        btnSelectTool    => {clicked => \&on_select_tool},
        btnPanTool       => {clicked => \&on_pan_tool},
        btnZoomInTool    => {clicked => \&on_zoom_in_tool},
        btnZoomOutTool   => {clicked => \&on_zoom_out_tool},
        btnZoomFitTool   => {clicked => \&on_zoom_fit_tool},

        menuitem_spatial_overlays => {activate => \&on_overlays},

        menuitem_spatial_colour_mode_hue  => {toggled  => \&on_colour_mode_changed},
        menuitem_spatial_colour_mode_sat  => {activate => \&on_colour_mode_changed},
        menuitem_spatial_colour_mode_grey => {toggled  => \&on_colour_mode_changed},

        menuitem_spatial_cell_outline_colour  => {activate => \&on_set_cell_outline_colour},
        menuitem_spatial_excluded_cell_colour => {activate => \&on_set_excluded_cell_colour},
        menuitem_spatial_undef_cell_colour    => {activate => \&on_set_undef_cell_colour},
        menuitem_spatial_cell_show_outline    => {toggled  => \&on_set_cell_show_outline},
        menuitem_spatial_show_legend          => {toggled  => \&on_show_hide_legend},
        menuitem_spatial_background_colour    => {activate => \&on_set_map_background_colour},
    );

    for my $n (0..6) {
        my $widget_name = "radio_colour_stretch$n";
        $widgets_and_signals{$widget_name} = {toggled => \&on_menu_stretch_changed};
    }

  WIDGET:
    foreach my $widget_name (sort keys %widgets_and_signals) {
        my $args = $widgets_and_signals{$widget_name};
        my $widget = $self->get_xmlpage_object($widget_name);
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
        comboIndices
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
        my $w = $self->get_xmlpage_object($w_name);
        next if !defined $w;
        $w->hide;
    }

    #  override a label
    my $combo_label_widget = $self->get_xmlpage_object('label_spatial_combos');
    $combo_label_widget->set_text ('Index group:  ');

    my $box = $self->get_xmlpage_object('hbox_spatial_tab_bottom');
    my $element_label = Gtk3::Label->new('label goes here');
    $element_label->set_use_markup(1);
    $box->pack_start($element_label, 0, 0, 10);
    $box->reorder_child($element_label, 2);  #  hard coded is flaky
    $self->{element_label} = $element_label;
    $element_label->show;

    # $self->init_output_indices_combo();

    $self->{drag_modes} = {
        Select  => 'select',
        Pan     => 'pan',
        ZoomIn  => 'select',
        ZoomOut => 'click',
        ZoomFit => 'click',
    };

    $self->choose_tool('Select');

    $self->setup_dendrogram;

    say '[SpatialMatrix tab] - Loaded tab';

    $self->{menubar} = $self->get_xmlpage_object('menubar_spatial');
    $self->update_export_menu;
    $self->update_tree_menu;

    #  debug stuff
    $self->{selected_list} = 'SUBELEMENTS';

    #  awkward but this gets the initial plot
    $self->on_cell_selected ([$self->{selected_element}], 'replot');

    return $self;
}

sub on_show_hide_parameters {
    return;
}

sub get_tree_menu_items {
    my $self = shift;
    my @items = $self->SUPER::get_tree_menu_items;
    my $re_wanted = qr/Set tree branch line widths|Plot branches by|Export|Set background colour|Highlight groups/;
    @items = grep {$_->{type} =~ /Separator/ or $_->{label} =~ /$re_wanted/} @items;
    return wantarray ? @items : \@items;
}


sub init_grid {
    my $self = shift;
    my $frame   = $self->get_xmlpage_object('gridFrame');

    # Use closure to automatically pass $self (which grid doesn't know)
    my $hover_closure = sub { $self->on_grid_hover(@_); };
    my $click_closure = sub {
        Biodiverse::GUI::CellPopup::cell_clicked(
            $_[0],
            $self->{groups_ref},
        );
    };
    # my $grid_click_closure = sub { $self->on_grid_click(@_); };
    my $select_closure     = sub { $self->on_cell_selected(@_); };
    my $right_click_closure = sub {$self->toggle_do_canvas_hover_flag (@_)};

    my $grid = $self->{grid} = Biodiverse::GUI::Canvas::Grid->new(
        frame            => $frame,
        show_legend      => 1,
        show_value       => 0,
        hover_func       => $hover_closure,
        end_hover_func   => sub {$self->on_end_grid_hover(@_)},
        ctl_click_func   => $click_closure, # Middle click or ctl left-click
        select_func      => $select_closure,
        # grid_click_func  => $grid_click_closure, # Left click
        right_click_func => $right_click_closure,
    );
    $grid->set_parent_tab($self);

    my $data = $self->{groups_ref};  #  should be the groups?
    my $elt_count = $data->get_element_count;
    my $completed = $data->get_param ('COMPLETED') // 1; #  old versions did not have this flag

    if (defined $data and $elt_count and $completed) {
        $grid->set_base_struct ($data);
    }

    my $menu_log_checkbox = $self->get_xmlpage_object('menu_colour_stretch_log_mode');
    $menu_log_checkbox->signal_connect_swapped(
        toggled => \&on_grid_colour_scaling_changed,
        $self,
    );
    my $menu_flip_checkbox = $self->get_xmlpage_object('menu_colour_stretch_flip_mode');
    $menu_flip_checkbox->signal_connect_swapped(
        toggled => \&on_grid_colour_flip_changed,
        $self,
    );

    $self->warn_if_basedata_has_gt2_axes;

    $grid->show_all;

    return;
}

sub init_lists_combo {
    return;
}

sub update_lists_combo {
    return;
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
    my ($self, $data, $replot) = @_;

    my $element;
    if (scalar @$data == 1) {
        $element = $data->[0];
    }
    elsif (@$data) {  #  User drew a box - get the first sorted element that is in the matrix
        my $sorted = $self->{groups_ref}->get_element_list_sorted (list => $data);
      CHECK_SORTED:
        while (defined ($element = shift @$sorted)) {
            last CHECK_SORTED
              if $self->{output_ref}->element_is_in_matrix_aa ($element);
        }
    }

    #  clicked on the background area, don't change anything
    if (!defined $element) {
        # $self->{element_label}->set_markup('<i>_none_</i>');
        #  clear any highlights
        $self->{grid}->clear_marks;
        $self->{dendrogram}->clear_highlights;
        $self->queue_draw;
        return;
    }

    return if !$replot && $element eq $self->{selected_element};

    $self->{selected_element} = $element;

    $self->{element_label}->set_text($element);
    $self->set_plot_min_max_values;
    $self->recolour();
    $self->queue_draw;
    return;
}



# Called by grid when user hovers over a cell
# and when mouse leaves a cell (element undef)
sub on_grid_hover {
    my $self = shift;
    my $element = shift;

    return if ! defined $element;

    return if !$self->do_canvas_hover_flag;

    my $matrix_ref = $self->{output_ref};
    my $output_ref = $self->{groups_ref};
    my $text = '';

    my $bd_ref = $output_ref->get_param ('BASEDATA_REF');

    if (defined $element) {
        #no warnings 'uninitialized';  #  sometimes the selected_list or analysis is undefined

        my $val = $matrix_ref->get_defined_value_aa ($element, $self->{selected_element});

        my $selected_el = $self->{selected_element} // '';
        $text = defined $val
            ? sprintf (
                '<b>%s</b> v <b>%s</b>, value: %s',  #  should list the index used
                $selected_el,
                $element,
                $self->format_number_for_display (number => $val),
              ) # round to 4 d.p.
            : "<b>Selected element: $selected_el</b>";
        $self->get_xmlpage_object('lblOutput')->set_markup($text);

        $self->{dendrogram}->clear_highlights();

        my $group = $element; # is this the same?
        return if ! defined $group;

        # get labels in the hovered and selected groups
        my ($labels1, $labels2);

        # hovered group
        $labels2 = $bd_ref->get_labels_in_group_as_hash_aa ($group);

        #  index group
        if (defined $self->{selected_element}) {
            #push @nbr_gps, $self->{selected_element};
            $labels1 = $bd_ref->get_labels_in_group_as_hash_aa ($self->{selected_element});
        }

        $self->highlight_paths_on_dendrogram ([$labels1, $labels2]);
    }
    else {
        $self->{dendrogram}->clear_highlights();
    }

    return;
}


# Called by output tab to make us show some analysis
sub show_analysis {
    return;
}

sub on_active_index_changed {
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

    my $stats = $self->{stats} //= $matrix_ref->get_summary_stats;

    $self->{plot_max_value} = $stats->{$self->{PLOT_STAT_MAX} || 'MAX'};
    $self->{plot_min_value} = $stats->{$self->{PLOT_STAT_MIN} || 'MIN'};

    return;
}

sub get_index_cell_colour {
    my $self = shift;

    return $self->{index_cell_colour} // $self->set_index_cell_colour;
}

sub set_index_cell_colour {
    my ($self, $colour) = @_;

    $colour //= Gtk3::Gdk::RGBA::parse('rgb(150,150,150)');
    $self->{index_cell_colour} = $colour;

    return $colour;
}

sub recolour {
    my $self = shift;
    my ($max, $min) = ($self->{plot_max_value} || 0, $self->{plot_min_value} || 0);

    # callback function to get colour of each element
    my $grid = $self->{grid};
    return if not defined $grid;  #  if no grid then no need to colour.

    my $matrix_ref  = $self->{output_ref};
    my $sel_element = $self->{selected_element};

    $grid->get_legend->set_stats ($self->{stats});

    my $legend = $grid->get_legend;

    my $colour_func = sub {
        my $elt = shift;

        return $self->get_index_cell_colour
          if $elt eq $sel_element; #  mid grey by default

        return $self->get_excluded_cell_colour
          if !$matrix_ref->element_is_in_matrix_aa ($elt);

        my $val = $matrix_ref->get_defined_value_aa ($elt, $sel_element);

        return defined $val
            ? $legend->get_colour($val, $min, $max)
            : undef;
    };

    $grid->colour($colour_func);
    $grid->set_legend_min_max($min, $max);

    return;
}


sub on_neighbours_changed {
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

    $method = 'SUPER::' . $method;
    #print $method, "\n";
    return $self->$method (@_);
}

sub DESTROY {}  #  let the system handle destruction - need this for AUTOLOADER

1;
