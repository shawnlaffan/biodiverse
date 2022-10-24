package Biodiverse::GUI::Tabs::Clustering;
use strict;
use warnings;
use 5.010;

use English qw( -no_match_vars );
use Time::HiRes qw /time/;

use Gtk2;
use Carp;
use Scalar::Util qw /blessed isweak weaken refaddr/;
use Ref::Util qw /is_ref is_arrayref is_hashref/;
use Sort::Key::Natural qw /natsort/;

use Biodiverse::GUI::GUIManager;
#use Biodiverse::GUI::ProgressDialog;
use Biodiverse::GUI::Grid;
use Biodiverse::GUI::Dendrogram;
use Biodiverse::GUI::Overlays;
use Biodiverse::GUI::Project;
use Biodiverse::GUI::CellPopup;
use Biodiverse::GUI::SpatialParams;
use Biodiverse::GUI::Tabs::CalculationsTree;

use Biodiverse::Indices;
use Biodiverse::Utilities qw/sort_list_with_tree_names_aa/;

our $VERSION = '3.99_005';

use Biodiverse::Cluster;
use Biodiverse::RegionGrower;

#use Data::Dumper;  

use parent qw {Biodiverse::GUI::Tabs::Tab};

use constant MODEL_NAME => 0;

my $empty_string = q{};
my $NULL_STRING  = q{};

##################################################
# Initialisation
##################################################

sub new {
    my $class = shift;
    my $cluster_ref = shift; # will be undef if none specified

    my $gui = Biodiverse::GUI::GUIManager->instance();

    my $self = {gui => $gui};
    $self->{project} = $gui->get_project();
    bless $self, $class;

    # (we can have many Analysis tabs open, for example.
    # These have different objects/widgets)
    my $xml_page = Gtk2::Builder->new();
    $xml_page->add_from_file($gui->get_gtk_ui_file('hboxClusteringPage.ui'));
    my $xml_label = Gtk2::Builder->new();
    $xml_label->add_from_file($gui->get_gtk_ui_file('hboxClusteringLabel.ui'));

    $self->{xmlPage}  = $xml_page;
    $self->{xmlLabel} = $xml_label;

    my $page  = $xml_page->get_object('hboxClusteringPage');
    my $label = $xml_label->get_object('hboxClusteringLabel');

    my $label_text = $self->{xmlLabel}->get_object('lblClusteringName')->get_text;
    my $label_widget = Gtk2::Label->new ($label_text);
    $self->{tab_menu_label} = $label_widget;

    # Add to notebook
    $self->add_to_notebook (
        page         => $page,
        label        => $label,
        label_widget => $label_widget,
    );

    my (@spatial_conditions, $defq_object);
    my $sp_initial1 = "sp_select_all ()\n"
                      . "#  This creates a complete matrix and is recommended "
                      . "as the last condition for clustering purposes";

    my $sp_initial2 = $empty_string;  #  initial spatial params text
    my $def_query_init1 = "sp_group_not_empty();\n# Condition is only needed if your BaseData has empty groups.";

    if (not defined $cluster_ref) {
        # We're being called as a NEW output
        # Generate a new output name

        my $bd = $self->{basedata_ref} = $self->{project}->get_selected_base_data;

        if (not blessed ($bd)) {  #  this should be fixed now
            $self->on_close;
            croak "Basedata ref undefined - click on the basedata object "
                  . "in the outputs tab to select it (this is a bug)\n";
        }

        #  check if it has rand outputs already and warn the user
        if (my @a = $self->{basedata_ref}->get_randomisation_output_refs) {
            my $response = $gui->warn_outputs_exist_if_randomisation_run(
                $self->{basedata_ref}->get_param ('NAME'),
            );
            if (not $response eq 'yes') {
                $self->on_close;
                croak "User cancelled operation\n";
            }
        }

        $self->{output_name} = $self->{project}->make_new_output_name(
            $self->{basedata_ref},
            $self->get_type,
        );
        if ($bd->get_group_count == 1) {
            $self->{output_name}
              .= ' =+=+='
               . ' Warning: single cell basedata -'
               . ' this analysis will not work'
               . ' =+=+=';
        }
        say "[Clustering tab] New cluster output " . $self->{output_name};

        if (!$bd->has_empty_groups) {
            $def_query_init1 = $empty_string;
        }

        $self->queue_set_pane(1, 'vpaneClustering');
        $self->{existing} = 0;
        $xml_page->get_object('toolbarClustering')->hide;
        $xml_page->get_object('toolbar_clustering_bottom')->hide;
    }
    else {  # We're being called to show an EXISTING output

        # Register as a tab for this output
        $self->register_in_outputs_model($cluster_ref, $self);

        $self->{output_name}  = $cluster_ref->get_param('NAME');
        $self->{basedata_ref} = $cluster_ref->get_param('BASEDATA_REF');
        say "[Clustering tab] Existing output - "
              . $self->{output_name}
              . " within Basedata set - "
              . $self->{basedata_ref}->get_param ('NAME');

        my $completed = $cluster_ref->get_param ('COMPLETED');
        $completed = 1 if not defined $completed;
        if ($completed == 1) {
            $self->queue_set_pane(0.01, 'vpaneClustering');
            $self->{existing} = 1;
        }
        else {
            $self->queue_set_pane(1, 'vpaneClustering');
            $self->{existing} = 0;
        }

        @spatial_conditions = @{$cluster_ref->get_spatial_conditions || []};
        $sp_initial1
            = defined $spatial_conditions[0]
            ? $spatial_conditions[0]->get_conditions_unparsed()
            : $NULL_STRING;
        $sp_initial2
            = defined $spatial_conditions[1]
            ? $spatial_conditions[1]->get_conditions_unparsed()
            : $NULL_STRING;

        $def_query_init1 = $cluster_ref->get_param ('DEFINITION_QUERY') //  $empty_string;
        if (blessed $def_query_init1) { #  get the text if already an object
            $def_query_init1 = $def_query_init1->get_conditions_unparsed();
            $defq_object     = $def_query_init1;
        }
        if (my $prng_seed = $cluster_ref->get_prng_seed_argument()) {
            my $spin_widget = $xml_page->get_object('spinbutton_cluster_prng_seed');
            $spin_widget->set_value ($prng_seed);
        }
    }

    $self->{output_ref} = $cluster_ref;

    $self->setup_tie_breaker_widgets($cluster_ref);

    # Initialise widgets
    $xml_page ->get_object('txtClusterName')->set_text( $self->{output_name} );
    $xml_label->get_object('lblClusteringName')->set_text($self->{output_name} );
    $self->{tab_menu_label}->set_text($self->{output_name});

    $self->{title_widget} = $xml_page ->get_object('txtClusterName');
    $self->{label_widget} = $xml_label->get_object('lblClusteringName');
    $self->set_label_widget_tooltip;


    $self->{spatialParams1} = Biodiverse::GUI::SpatialParams->new(
        initial_text => $sp_initial1,
        condition_object => $spatial_conditions[0],
    );
    $xml_page->get_object('frameClusterSpatialParams1')->add(
        $self->{spatialParams1}->get_object,
    );

    my $start_hidden = not (length $sp_initial2);
    $self->{spatialParams2} = Biodiverse::GUI::SpatialParams->new(
        initial_text => $sp_initial2,
        start_hidden => $start_hidden,
        condition_object => $spatial_conditions[1],
    );
    $xml_page->get_object('frameClusterSpatialParams2')->add(
        $self->{spatialParams2}->get_object
    );

    $start_hidden = not (length $def_query_init1);
    $self->{definition_query1} = Biodiverse::GUI::SpatialParams->new(
        initial_text => $def_query_init1,
        start_hidden => $start_hidden,
        is_def_query => 'is_def_query',
        condition_object => $defq_object,
    );
    $xml_page->get_object('frameClusterDefinitionQuery1')->add(
        $self->{definition_query1}->get_object
    );

    $xml_page->get_object('plot_length') ->set_active(1);
    $xml_page->get_object('group_length')->set_active(1);
    $self->{plot_mode}  = 'length';
    $self->{group_mode} = 'length';

    $self->{use_highlight_path} = 1;
    $self->{use_slider_to_select_nodes} = 1;

    $self->queue_set_pane(0.5, 'hpaneClustering');
    $self->queue_set_pane(1  , 'vpaneDendrogram');

    $self->make_indices_model($cluster_ref);
    $self->make_linkage_model($cluster_ref);
    $self->init_indices_combo();
    $self->init_linkage_combo();
    $self->init_map();
    eval {
        $self->init_dendrogram();
    };
    if (my $e = $EVAL_ERROR) {
        $self->{gui}->report_error($e);
        $self->on_close;
        return;
    }
    $self->init_map_show_combo();
    $self->init_map_list_combo();

    $self->{colour_mode} = 'Hue';
    $self->{hue} = Gtk2::Gdk::Color->new(65535, 0, 0); # For Sat mode

    $self->{calculations_model}
        = Biodiverse::GUI::Tabs::CalculationsTree::make_calculations_model(
            $self->{basedata_ref}, $cluster_ref
        );

    Biodiverse::GUI::Tabs::CalculationsTree::init_calculations_tree(
        $xml_page->get_object('treeSpatialCalculations'),
        $self->{calculations_model}
    );

    # Connect signals
    $xml_label->get_object('btnClose')->signal_connect_swapped(
        clicked => \&on_close,
        $self,
    );

    $self->{xmlPage}->get_object('chk_output_gdm_format')->set_sensitive (0);

    #$self->set_colour_stretch_widgets_and_signals;

    my %widgets_and_signals = (
        btnCluster          => {clicked => \&on_run},
        menuitem_cluster_overlays => {activate => \&on_overlays},
        spinClusters        => {'value-changed' => \&on_clusters_changed},

        btnSelectToolCL     => {clicked => \&on_select_tool},
        btnPanToolCL        => {clicked => \&on_pan_tool},
        btnZoomInToolCL     => {clicked => \&on_zoom_in_tool},
        btnZoomOutToolCL    => {clicked => \&on_zoom_out_tool},
        btnZoomFitToolCL    => {clicked => \&on_zoom_fit_tool},

        plot_length         => {toggled => \&on_plot_mode_changed},
        group_length        => {toggled => \&on_group_mode_changed},

        highlight_groups_on_map =>
            {toggled => \&on_highlight_groups_on_map_changed},
        use_highlight_path_changed =>
            {toggled => \&on_use_highlight_path_changed},
        menu_use_slider_to_select_nodes =>
            {toggled => \&on_menu_use_slider_to_select_nodes},

        menuitem_cluster_colour_mode_hue  => {toggled  => \&on_colour_mode_changed},
        menuitem_cluster_colour_mode_sat  => {activate => \&on_colour_mode_changed},
        menuitem_cluster_colour_mode_grey => {toggled  => \&on_colour_mode_changed},
        txtClusterName      => {changed => \&on_name_changed},

        comboLinkage        => {changed => \&on_combo_linkage_changed},
        comboMetric         => {changed => \&on_combo_metric_changed},
        comboMapList        => {changed => \&on_combo_map_list_changed},

        chk_output_to_file  => {clicked => \&on_chk_output_to_file_changed},

        menu_cluster_cell_outline_colour => {activate => \&on_set_cell_outline_colour},
        menu_cluster_cell_show_outline   => {toggled => \&on_set_cell_show_outline},
        menuitem_cluster_show_legend     => {toggled => \&on_show_hide_legend},
        #menuitem_cluster_data_tearoff => {activate => \&on_toolbar_data_menu_tearoff},
        menuitem_cluster_set_tree_line_widths => {activate => \&on_set_tree_line_widths},
        menuitem_cluster_excluded_cell_colour => {activate => \&on_set_excluded_cell_colour},
        menuitem_cluster_undef_cell_colour    => {activate => \&on_set_undef_cell_colour},
    );

    for my $n (0..6) {
        my $widget_name = "radio_dendro_colour_stretch$n";
        $widgets_and_signals{$widget_name} = {toggled => \&on_menu_stretch_changed};
    }


    foreach my $widget_name (sort keys %widgets_and_signals) {
        my $args = $widgets_and_signals{$widget_name};
        #say $widget_name;
        my $widget = $xml_page->get_object($widget_name);
        if (!defined $widget) {
            warn "$widget_name not found";
            next;
        };
        $widget->signal_connect_swapped(
            %$args,
            $self,
        );
    }

    $self->choose_tool('Select');

    $self->{menubar} = $self->{xmlPage}->get_object('menubar_clustering');
    $self->update_export_menu;
    $self->init_colour_clusters;

    say "[Clustering tab] - Loaded tab - Clustering Analysis";

    return $self;
}

sub init_colour_clusters {
    my $self = shift;
    my $cluster_ref = $self->{output_ref};

    return if !$cluster_ref || !$self->{dendrogram};

    my $root = eval {$cluster_ref->get_root_node};
    return if !$root;  #  we have too many root nodes

    $self->{dendrogram}->do_colour_nodes_below;
    $self->{dendrogram}->do_colour_nodes_below($root);

    return;
}

#  change sensitivity of the GDM output widget
sub on_chk_output_to_file_changed {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_object('chk_output_to_file');
    my $active = $widget->get_active;

    my $gdm_widget = $self->{xmlPage}->get_object('chk_output_gdm_format');
    $gdm_widget->set_sensitive($active);

    return;
}

sub setup_tie_breaker_widgets {
    my $self     = shift;
    my $existing = shift;

    my $xml_page = $self->{xmlPage};
    my $hbox_name = 'hbox_cluster_tie_breakers';
    my $breaker_hbox = $xml_page->get_object($hbox_name);

    my ($tie_breakers, $bd);
    if ($existing) {
        $tie_breakers = $existing->get_param ('CLUSTER_TIE_BREAKER');
        $bd = $existing->get_basedata_ref;
    }
    else {
        $bd = $self->{project}->get_selected_base_data;
    }
    $tie_breakers //= [];  #  param is not always set

    my $indices_object = Biodiverse::Indices->new (BASEDATA_REF => $bd);
    my %valid_indices = $indices_object->get_valid_region_grower_indices;
    my %tmp = $indices_object->get_valid_cluster_indices;
    @valid_indices{keys %tmp} = values %tmp;

    my $cb_tooltip_text
      = 'Turn the tie breakers off if you want the old clustering system.  '
      . 'It will return different results for different analyses, '
      . 'but is faster and uses less memory.';
    my $checkbox = Gtk2::CheckButton->new_with_label("Use tie\nbreakers");
    $checkbox->set_active(1);
    $checkbox->set_tooltip_text($cb_tooltip_text);
    $breaker_hbox->pack_start ($checkbox, 0, 0, 0);

    my @tie_breaker_widgets;

    foreach my $i (0, 1) {
        my $id = $i + 1;
        my $j = 2 * $i;
        my $k = $j + 1;
        my $label = Gtk2::Label->new("  $id: ");
        my $index_combo = Gtk2::ComboBox->new_text;
        my $l = 0;
        my $use_iter;
        foreach my $index (qw /none random/, natsort keys %valid_indices) {
            $index_combo->append_text ($index);
            if (defined $tie_breakers->[$j] && $tie_breakers->[$j] eq $index) {
                $use_iter = $l;
            }
            $l ++;
        }

        $index_combo->set_active($use_iter // 1);  #  random by default

        my $combo_minmax = Gtk2::ComboBox->new_text;
        $combo_minmax->append_text ('maximise');
        $combo_minmax->append_text ('minimise');
        $combo_minmax->set_active (0);

        my $use_iter_minmax = 0;
        if (defined (my $minmax = $tie_breakers->[$k])) {
            $use_iter_minmax = $minmax =~ /^max/ ? 0 : 1;
        }
        $combo_minmax->set_active ($use_iter_minmax || 0);

        my $hbox = Gtk2::HBox->new;
        $hbox->pack_start ($label, 0, 0, 0);
        $hbox->pack_start ($index_combo, 0, 0, 0);
        $hbox->pack_start ($combo_minmax, 0, 0, 0);
        $breaker_hbox->pack_start ($hbox, 0, 0, 0);
        push @tie_breaker_widgets, $index_combo, $combo_minmax;
    }
    $breaker_hbox->show_all();

    $self->{tie_breaker_widgets} = \@tie_breaker_widgets;
    $self->{tie_breaker_widget_use_check} = $checkbox;

    return;
}

#  clunky, but for some reason Gtk-perl cannot get the label from the activated widget
#  If it could then we could just use get_label on the active widget and pass that
#  thus avoiding the need to build the list.
sub set_colour_stretch_widgets_and_signals {
    my $self = shift;
    my $xml_page = $self->{xmlPage};

    #  lazy - should build from menu widget
    my $i = 0;
    foreach my $stretch (qw /min-max 5-95 2.5-97.5 min-95 min-97.5 5-max 2.5-max/) {
        my $widget_name = "radio_dendro_colour_stretch$i";
        my $widget = $xml_page->get_object($widget_name);

        my $sub = sub {
            my $self = shift;
            my $widget = shift;

            return if ! $widget->get_active;  #  don't trigger on the deselected one

            $self->on_stretch_changed ($stretch);

            return;
        };

        $widget->signal_connect_swapped(
            activate => $sub,
            $self,
        );
        $i++;
    }

    return
}



#  change the explanation text - does nothing yet
sub on_combo_linkage_changed {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_object('label_explain_linkage');

    my $linkage = $self->get_selected_linkage;

    return;
};

#  change the explanation text
sub on_combo_metric_changed {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_object('label_explain_metric');

    my $metric = $self->get_selected_metric;

    my $bd = $self->{basedata_ref} || $self->{project}->get_selected_base_data;

    my $indices_object = Biodiverse::Indices->new (BASEDATA_REF => $bd);

    my $source_sub = $indices_object->get_index_source (index => $metric);
    my $metadata   = $indices_object->get_metadata (sub => $source_sub);

    my $explanation = 'Description: ' . $metadata->get_index_description ($metric);

    $widget->set_text($explanation);

    return;
};


sub on_show_hide_parameters {
    my $self = shift;

    my $frame = $self->{xmlPage}->get_object('frame_cluster_parameters');
    my $widget = $frame->get_label_widget;
    my $active = $widget->get_active;

    my $table = $self->{xmlPage}->get_object('tbl_cluster_parameters');

    my $method = $active ? 'hide' : 'show';
    $table->$method;

    return;
}

sub init_map {
    my $self = shift;

    my $xml_page = $self->{xmlPage};

    my $frame   = $xml_page->get_object('mapFrame');
    my $hscroll = $xml_page->get_object('mapHScroll');
    my $vscroll = $xml_page->get_object('mapVScroll');

    my $click_closure      = sub { $self->on_grid_popup(@_); };
    my $hover_closure      = sub { $self->on_grid_hover(@_); };
    my $select_closure     = sub { $self->on_grid_select(@_); };
    my $grid_click_closure = sub { $self->on_grid_click(@_); };
    my $end_hover_closure  = sub { $self->on_end_grid_hover(@_); };

    $self->{grid} = Biodiverse::GUI::Grid->new(
        frame => $frame,
        hscroll => $hscroll,
        vscroll => $vscroll,
        show_legend => 1,
        show_value  => 0,
        hover_func  => $hover_closure,
        click_func  => $click_closure,
        select_func => $select_closure,
        grid_click_func => $grid_click_closure,
        end_hover_func  => $end_hover_closure
    );
    
    my $grid = $self->{grid};
    
    $grid->{page} = $self;

    $grid->set_base_struct($self->{basedata_ref}->get_groups_ref);

    my $menu_log_checkbox = $xml_page->get_object('menu_dendro_colour_stretch_log_mode');
    $menu_log_checkbox->signal_connect_swapped(
        toggled => \&on_grid_colour_scaling_changed,
        $self,
    );
    
    $self->warn_if_basedata_has_gt2_axes;

    return;
}

sub init_dendrogram {
    my $self = shift;

    my $frame       =  $self->{xmlPage}->get_object('clusterFrame');
    my $graph_frame =  $self->{xmlPage}->get_object('graphFrame');
    my $hscroll     =  $self->{xmlPage}->get_object('clusterHScroll');
    my $vscroll     =  $self->{xmlPage}->get_object('clusterVScroll');
    my $list_combo  =  $self->{xmlPage}->get_object('comboMapList');
    my $index_combo =  $self->{xmlPage}->get_object('comboMapShow');
    my $spinbutton  =  $self->{xmlPage}->get_object('spinClusters');

    my $hover_closure       = sub { $self->on_dendrogram_hover(@_); };
    my $highlight_closure   = sub { $self->on_dendrogram_highlight(@_); };
    my $popup_closure       = sub { $self->on_dendrogram_popup(@_); };
    my $click_closure       = sub { $self->on_dendrogram_click(@_); };
    my $select_closure      = sub { $self->on_dendrogram_select(@_); };

    $self->{dendrogram} = Biodiverse::GUI::Dendrogram->new(
        main_frame  => $frame,
        graph_frame => $graph_frame,
        hscroll     => $hscroll,
        vscroll     => $vscroll,
        grid        => $self->{grid},
        list_combo  => $list_combo,
        index_combo => $index_combo,
        hover_func      => $hover_closure,
        highlight_func  => $highlight_closure,
        ctrl_click_func => $popup_closure,
        click_func      => $click_closure, # click_func
        select_func     => $select_closure, # select_func
        parent_tab      => $self,
        basedata_ref    => undef, # basedata_ref
    );

    # TODO: Abstract this properly
    #$self->{dendrogram}->{map_lists_ready_cb} = sub { $self->on_map_lists_ready(@_) };

    $self->{dendrogram}{page} = $self;
    weaken $self->{dendrogram}{page};

    if ($self->{existing}) {
        my $cluster_ref = $self->{output_ref};

        my $completed = $cluster_ref->get_param ('COMPLETED');

        #  partial cluster analysis - don't try to plot it
        #  the defined test is for very backwards compatibility
        return if defined $completed && ! $completed;

        #print Data::Dumper::Dumper($cluster_ref);
        if (defined $cluster_ref) {
            $self->{dendrogram}->set_cluster($cluster_ref, $self->{plot_mode});
        }
        $self->{dendrogram}->set_group_mode($self->{group_mode});
    }

    #  set the number of clusters in the spinbutton
    $spinbutton->set_value( $self->{dendrogram}->get_num_clusters );

    return;
}

#  only show the legend if the menuitem says we can
sub show_legend {
    my $self = shift;
    my $widget = $self->{xmlPage}->get_object('menuitem_cluster_show_legend');

    if ($widget->get_active) {
        $self->{grid}->show_legend;
    }
}

#  for completeness with show_legend
#  simple wrapper
sub hide_legend {
    my $self = shift;
    $self->{grid}->hide_legend;
}

sub update_display_list_combos {
    my ($self, %args) = @_;
    
    my @methods = qw /
        update_map_lists_combo
    /;
    
    $self->SUPER::update_display_list_combos (
        %args,
        methods => \@methods,
    );
    
    return;
}

sub init_map_show_combo {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_object('comboMapShow');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, markup => 0);

    return;
}

sub update_map_lists_combo {
    my $self = shift;
    $self->{dendrogram}->update_map_list_model;
}

sub init_map_list_combo {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_object('comboMapList');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, markup => 0);

    #  trigger sensitivity
    $self->on_combo_map_list_changed;

    return;
}

#  if the list combo is "cluster" then desensitise several other widgets
sub on_combo_map_list_changed {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_object('comboMapList');

    my $iter = $combo->get_active_iter;
    return if ! defined $iter; # this can occur if we are a new cluster output
                                #  as there are no map lists

    my $model = $combo->get_model;
    my $list  = $model->get($iter, 0);

    my $sensitive = 1;
    if ($list eq '<i>Cluster</i>' || $list eq '<i>User defined</i>') {
        $sensitive = 0;
        $self->hide_legend;
        $self->{output_ref}->set_cached_value(LAST_SELECTED_LIST => undef);
    }
    else {
        $self->show_legend;
        $self->{output_ref}->set_cached_value(LAST_SELECTED_LIST => $list);
    }

    #  show/hide some widgets 
    my @cluster_widgets  = qw /label_cluster_spin_button spinClusters/;
    my @cloister_widgets = qw /label_selector_colour selector_colorbutton selector_toggle autoincrement_toggle/;
    my $m1 = $list eq '<i>User defined</i>' ? 'hide' : 'show';
    my $m2 = $list eq '<i>User defined</i>' ? 'show' : 'hide';
    foreach my $widget_name (@cluster_widgets) {
        my $widget = $self->{xmlPage}->get_object ($widget_name);
        $widget->$m1;
    }
    foreach my $widget_name (@cloister_widgets) {
        my $widget = $self->{xmlPage}->get_object ($widget_name);
        $widget->$m2;
    }
    
    my @widgets = qw {
        comboMapShow
        menuitem_cluster_colour_mode_hue
        menuitem_cluster_colour_mode_sat
        menuitem_cluster_colour_mode_grey
    };
    foreach my $widget_name (@widgets) {
        my $widget = $self->{xmlPage}->get_object($widget_name);
        if (!$widget) {
            warn "$widget_name not found\n";
            next;
        }

        $widget->set_sensitive($sensitive);
    }

    #  don't show the indices options if there is no list
    my $combo_widget = $self->{xmlPage}->get_object('comboMapShow');
    if ($sensitive) {
        $combo_widget->show;
    }
    else {
        $combo_widget->hide;
    }

    return;
}


##################################################
# Indices combo
##################################################

sub make_indices_model {
    my $self = shift;
    my $cluster_ref = shift;

    # Get index that should be selected
    my $index_used;
    if ($cluster_ref) {
        $index_used = $cluster_ref->get_param("CLUSTER_INDEX");
    }

    $self->{indices_model}
        = Gtk2::ListStore->new(
            'Glib::String',        # Name
            'Glib::String',        # Function - FIXME delete
        );

    my $model   = $self->{indices_model};
    #my $check_valid_sub = $self->get_output_type->get_valid_indices_sub;
    #my $indices_object
    #  = Biodiverse::Indices->new(BASEDATA_REF => $self->{basedata_ref});
    #my %indices = $indices_object->$check_valid_sub;
    my %indices = $self->get_output_type->get_valid_indices (BASEDATA_REF => $self->{basedata_ref});

    my $default_index = $self->get_output_type->get_default_cluster_index;
    my $default_iter;
    # Add each analysis-function (eg: Jaccard, Endemism) row
    foreach my $name (natsort keys %indices) {

        # Add to model
        my $iter = $model->append;
        #$model->set($iter, MODEL_NAME, "$name\t$description");
        $model->set($iter, MODEL_NAME, $name);

        if ($name eq $default_index) {
            $default_iter = $iter;
        }

        # Should it be selected? (yes, if it was on previous time)
        if( $index_used && $name eq $index_used ) {
            $self->{selected_index_iter} = $iter;
        }
    }

    # Select default if nothing else set
    if (not $self->{selected_index_iter}) {
        #$self->{selected_index_iter} = $model->get_iter_first;
        $self->{selected_index_iter} = $default_iter ;
    }

    return;
}

sub make_linkage_model {
    my $self = shift;
    my $cluster_ref = shift;

    # Get linkage that should be selected
    my $linkage_used;
    if ($cluster_ref) {
        $linkage_used = $cluster_ref->get_param('CLUSTER_LINKAGE');
    }

    $self->{linkage_model} = Gtk2::ListStore->new(
        'Glib::String',        # Name
        'Glib::String',        # Function - FIXME delete
    );

    my $model = $self->{linkage_model};

    my $class = $self->get_output_type;

    # Add each analysis-function (eg: Jaccard, Endemism) row
    foreach my $name (sort ($class->get_linkage_functions())) {

        # Add to model
        my $iter = $model->append;
        $model->set($iter, MODEL_NAME, $name);

        # Should it be selected? (yes, if it was on previous time)
        if( $linkage_used && $name eq $linkage_used ) {
            $self->{selected_linkage_iter} = $iter;
        }
    }

    # Select first one if nothing else
    if (not $self->{selected_linkage_iter}) {
        $self->{selected_linkage_iter} = $model->get_iter_first;
    }

    return;
}

sub init_indices_combo {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_object('comboMetric');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, text => MODEL_NAME);

    $combo->set_model($self->{indices_model});
    if ($self->{selected_index_iter}) {
        $combo->set_active_iter( $self->{selected_index_iter} );
    }

    $self->on_combo_metric_changed;

    return;
}

sub init_linkage_combo {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_object('comboLinkage');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, text => MODEL_NAME);

    $combo->set_model($self->{linkage_model});
    if ($self->{selected_linkage_iter}) {
        $combo->set_active_iter( $self->{selected_linkage_iter} );
    }

    return;
}

##################################################
# Managing that vertical pane
##################################################

# Sets the vertical pane's position (0 -> all the way down | 1 -> fully up)
sub set_pane {
    my $self = shift;
    my $pos  = shift;
    my $id   = shift;

    my $pane = $self->{xmlPage}->get_object($id);
    my $max_pos = $pane->get('max-position');
    $pane->set_position( $max_pos * $pos );
    #print "[Clustering tab] Updating pane $id: maxPos = $max_pos, pos = $pos\n";

    return;
}

# This will schedule set_pane to be called from a temporary signal handler
# Need when the pane hasn't got it's size yet and doesn't know its max position
sub queue_set_pane {
    my $self = shift;
    my $pos = shift;
    my $id = shift;

    my $pane = $self->{xmlPage}->get_object($id);

    # remember id so can disconnect later
    my $sig_id = $pane->signal_connect_swapped(
        'size-allocate',
        \&Biodiverse::GUI::Tabs::Clustering::set_pane_signal,
        [$self, $id]
    );
    $self->{"set_paneSignalID$id"} = $sig_id;  #  ISSUE 417 ISSUES????
    $self->{"set_panePos$id"} = $pos;

    return;
}

sub set_pane_signal {
    my $args = shift;
    shift;
    my $pane = shift;

    my ($self, $id) = ($args->[0], $args->[1]);

    $self->set_pane( $self->{"set_panePos$id"}, $id );
    $pane->signal_handler_disconnect( $self->{"set_paneSignalID$id"} );
    delete $self->{"set_panePos$id"};
    delete $self->{"set_paneSignalID$id"};

    return;
}

##################################################
# Misc interaction with rest of GUI
##################################################


sub get_type {
    return 'Cluster';
}

sub get_output_type {
    return 'Biodiverse::Cluster';
}

sub remove {
    my $self = shift;

    eval {$self->{grid}->destroy()};
    eval {$self->{dendrogram}->destroy()};

    $self->SUPER::remove;

    return;
}

##################################################
# Running the thing
##################################################

my @chk_flags = qw /
    no_cache_abc
    build_matrices_only
    output_gdm_format
    keep_sp_nbrs_output
    no_clone_matrices
    clear_singletons
/;

sub get_flag_widget_values {
    my $self = shift;

    my %flag_hash;

    foreach my $flag_name (@chk_flags) {
        my $widget_name = 'chk_' . $flag_name;
        my $widget = $self->{xmlPage}->get_object($widget_name);
        $flag_hash{$flag_name} = $widget->get_active;
    }

    return wantarray ? %flag_hash : \%flag_hash;
}

sub get_prng_seed {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_object('spinbutton_cluster_prng_seed');

    my $value = $widget->get_value;

    return $value;
}

sub get_tie_breakers {
    my $self = shift;

    my $widgets = $self->{tie_breaker_widgets};
    my @choices;
    foreach my $widget (@$widgets) {
        push @choices, $widget->get_active_text;
    }

    return wantarray ? @choices : \@choices;
}

sub get_use_tie_breakers {
    my $self = shift;

    my $widget = $self->{tie_breaker_widget_use_check};

    return if !$widget;
    return $widget->get_active;
}

sub get_output_file_handles {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_object('chk_output_to_file');

    return if not $widget->get_active;  #  undef if nothing set

    #  get a file prefix and create as many handles
    #  as there are matrices to be created
    my @handles;

    my $file_chooser = Gtk2::FileChooserDialog->new (
        'Choose file prefix',
        undef,
        'save',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok'
    );

    #  need to base on output name
    $file_chooser->set_current_name($self->{output_name} . '_matrix');

    my $file_pfx;

    if ('ok' eq $file_chooser->run){
       $file_pfx = $file_chooser->get_filename;
       print "file prefix $file_pfx\n";
    }
    else {
        $file_chooser->destroy;
        croak "No prefix selected, operation cancelled\n";
    }

    my $matrix_count = 0;
    for my $condition (qw /spatialParams1 spatialParams2/) {
        my $text = $self->{$condition}->get_text();
        $text =~ s/\s//g;
        if (length $text) {  #  increment if something is there
            $matrix_count ++;
        }
    }
    if (not $matrix_count) {
        $matrix_count = 1;  #  system defaults to one in all cases
    }

    $file_chooser->destroy;

    for my $i (1..$matrix_count) {
        my $filename = $file_pfx . '_' . $i . '.csv';
        open my $fh, '>', $filename or croak "Unable to open $filename to write to\n";
        push @handles, $fh;
    }

    return wantarray ? @handles : \@handles;
}

sub get_selected_metric {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_object('comboMetric');
    my $iter = $combo->get_active_iter;
    my $index = $self->{indices_model}->get($iter, MODEL_NAME);
    $index =~ s{\s.*}{};  #  remove anything after the first whitespace

    return $index;
}

sub get_selected_linkage {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_object('comboLinkage');
    my $iter = $combo->get_active_iter;
    return $self->{linkage_model}->get($iter, MODEL_NAME);
}

#  handle inheritance
sub on_run {
    my $self = shift;
    my $button = shift;

    return $self->on_run_analysis (@_);
}

sub get_overwrite_response {
    my ($self, $title, $text) = @_;

    my $rerun_spatial_value = -20;

    my $dlg = Gtk2::Dialog->new(
        $title,
        $self->{gui}->get_object('wndMain'),
        'modal',
        'gtk-yes' => 'ok',
        'gtk-no'  => 'no',
        "run/rerun\ncalculations\nper node" => $rerun_spatial_value,
    );
    my $label = Gtk2::Label->new($text);
    #$label->set_use_markup(1);
    $dlg->vbox->pack_start ($label, 0, 0, 0);
    $dlg->show_all();

    my $response = $dlg->run;
    $dlg->destroy;

    if ($response eq 'delete-event') {
        $response = 'cancel';
    }
    if ($response eq $rerun_spatial_value) {
        $response = 'run_spatial_calculations';
    }

    return $response;
}

sub on_run_analysis {
    my $self   = shift;
    my %args = @_;

    # Check spatial syntax
    return if $self->{spatialParams1}->syntax_check('no_ok')    ne 'ok';
    return if $self->{spatialParams2}->syntax_check('no_ok')    ne 'ok';
    return if $self->{definition_query1}->syntax_check('no_ok') ne 'ok';

    # Load settings...
    my $output_name      = $self->{xmlPage}->get_object('txtClusterName')->get_text();
    $self->{output_name} = $output_name;
    my $output_ref       = $self->{output_ref};
    my $pre_existing     = $self->{output_ref};
    my $new_analysis     = 1;

    my $bd      = $self->{basedata_ref};
    my $project = $self->{project};

    my $selected_index      = $self->get_selected_metric;
    my $selected_linkage    = $self->get_selected_linkage;
    my $file_handles        = $self->get_output_file_handles;
    my $prng_seed           = $self->get_prng_seed;

    my %flag_values = $self->get_flag_widget_values;

    # Get spatial calculations to run
    my @calculations_to_run
      = Biodiverse::GUI::Tabs::CalculationsTree::get_calculations_to_run(
        $self->{calculations_model}
    );

    my $overwrite;
    # Delete existing?
    if (defined $output_ref) {
        my $completed = $self->{output_ref}->get_param('COMPLETED') // 1;

        if ($self->{existing} && $completed) {
            my $text = "  $output_name exists.  \nDo you mean to overwrite it?";
            my $response = $self->get_overwrite_response ('Overwrite?', $text);

            #  drop out if we don't want to overwrite
            return 0 if $response eq 'no' or $response eq 'cancel';

            if ($response eq 'run_spatial_calculations') {
                return 0 if not scalar @calculations_to_run;
                $new_analysis = 0;
            }
            #  Should really check if the analysis
            #  ran properly before setting this
            $self->set_project_dirty;
        }

        if ($new_analysis) {  #  we can simply rename it for now
            $overwrite = 1;
            my $tmp_name = $pre_existing->get_name . ' (preexisting ' . time() . ')';
            $bd->rename_output (output => $pre_existing, new_name => $tmp_name);
            $project->update_output_name ($pre_existing);
        }
    }

    if ($new_analysis) {
        # Add cluster output
        $output_ref = eval {
            $bd->add_cluster_output(
                name => $self->{output_name},
                type => $self->get_output_type,
            );
        };
        if ($EVAL_ERROR) {
            $self->{gui}->report_error ($EVAL_ERROR);
            return;
        }

        $self->{output_ref} = $output_ref;
        $project->add_output($self->{basedata_ref}, $output_ref);
    }

    my %analysis_args = (
        %args,
        %flag_values,
        matrix_ref           => $self->{project}->get_selected_matrix,
        tree_ref             => $self->{project}->get_selected_phylogeny,
        definition_query     => $self->{definition_query1}->get_validated_conditions,
        index                => $selected_index,
        linkage_function     => $selected_linkage,
        file_handles         => $file_handles,
        spatial_calculations => \@calculations_to_run,
        spatial_conditions   => [
            $self->{spatialParams1}->get_validated_conditions,
            $self->{spatialParams2}->get_validated_conditions,
        ],
        prng_seed           => $prng_seed,
    );

    if ($self->get_use_tie_breakers) {
        my $tie_breakers = $self->get_tie_breakers;
        $analysis_args{cluster_tie_breaker} = $tie_breakers;
    }

    # Perform the clustering
  RUN_CLUSTER:
    my $success = eval {
        $output_ref->run_analysis (
            %analysis_args,
            flatten_tree => 1,

        )
    };
    if (Biodiverse::Cluster::MatrixExists->caught) {
        my $e = $EVAL_ERROR;
        my $name = $e->name;
        #  do some handling then try again?
        #  drop out if we don't want to overwrite
        my $text = "\nMatrix output \n$name \nexists in the basedata.\nDelete it?\n(It will still be part of its cluster output).";
        if (Biodiverse::GUI::YesNoCancel->run({header => 'Overwrite?', text => $text}) ne 'yes') {
            if ($overwrite) {  #  put back the pre-existing cluster output
                $bd->delete_output(output => $output_ref);
                $project->delete_output($output_ref);
                $bd->rename_output (output => $pre_existing, new_name => $self->{output_name});
                $project->update_output_name ($pre_existing);
            }
            return 0;
        }
        $bd->delete_output(output => $e->object);
        $project->delete_output($e->object);
        goto RUN_CLUSTER;
    }
    elsif ($EVAL_ERROR) {
        $self->{gui}->report_error ($EVAL_ERROR);
    }

    if (not $success) {  # dropped out for some reason, eg no valid analyses.
        $self->on_close;  #  close the tab to avoid horrible problems with multiple instances
        if ($overwrite) {  #  reinstate the old output
            $bd->delete_output (output => $output_ref);
            $project->delete_output($output_ref);
            $bd->rename_output (output => $pre_existing, new_name => $self->{output_name});
            $project->update_output_name ($output_ref);
        }

        return;
    }
    elsif ($overwrite) {
        $bd->delete_output (output => $pre_existing);
        $project->delete_output($pre_existing);
        delete $self->{stats};
    }

    if ($flag_values{keep_sp_nbrs_output}) {
        my $sp_name = $output_ref->get_param('SP_NBRS_OUTPUT_NAME');
        if (defined $sp_name) {
            my $sp_ref  = $self->{basedata_ref}->get_spatial_output_ref(name => $sp_name);
            $project->add_output($self->{basedata_ref}, $sp_ref);
        }
        else {
            say '[CLUSTER] Unable to add spatial output, probably because a recycled '
                . 'matrix was used so no spatial output was needed.'
        }
    }

    #  add the matrices to the outputs tab
    if ($new_analysis) {
        foreach my $ref ($output_ref->get_orig_matrices) {
            next if not $ref->get_element_count;  #  don't add if empty
            $project->add_output($self->{basedata_ref}, $ref);
        }
    }

    $self->register_in_outputs_model($output_ref, $self);

    return if $success > 1;

    my $isnew = 0;
    if ($self->{existing} == 0) {
        $isnew = 1;
        $self->{existing} = 1;
    }

    if (Biodiverse::GUI::YesNoCancel->run({header => 'display results?'}) eq 'yes') {
        $self->{xmlPage}->get_object('toolbar_clustering_bottom')->show;
        $self->{xmlPage}->get_object('toolbarClustering')->show;

        if (defined $output_ref) {
            $self->{dendrogram}->set_cluster($output_ref, $self->{plot_mode});
        }

        $self->init_colour_clusters;

        # If just ran a new analysis, pull up the pane
        if ($isnew or not $new_analysis) {
            $self->set_pane(0.01, 'vpaneClustering');
            $self->set_pane(1,    'vpaneDendrogram');
        }

    }

    $self->update_export_menu;

    return;
}

##################################################
# Dendrogram
##################################################

# Called by dendrogram when user hovers over a node
# Updates those info labels
sub on_dendrogram_hover {
    my $self = shift;
    my $node = shift || return;

    no warnings 'uninitialized';  #  don't complain if nodes have not been numbered

    my $map_text = '<b>Node label: </b> ' . $node->get_name;
    my $dendro_text = sprintf (
        '<b>Node Length: </b> %.4f <b>Element numbers: First</b> %d <b>Last:</b> %d',
         $node->get_total_length, # round to 4 d.p.
         $node->get_value ('TERMINAL_NODE_FIRST'),
         $node->get_value ('TERMINAL_NODE_LAST'),
    );

    $self->{xmlPage}->get_object('lblMap')->set_markup($map_text);
    $self->{xmlPage}->get_object('lblDendrogram')->set_markup($dendro_text);

    return;
}

# Circles a node's terminal elements. Clear marks if $node undef
sub on_dendrogram_highlight {
    my $self = shift;
    my $node = shift;

    my $terminal_elements = (defined $node) ? $node->get_terminal_elements : {};
    $self->{grid}->mark_if_exists( $terminal_elements, 'circle' );

    #my @elts = keys %$terminal_elements;
    #print "marked: @elts\n";

    return;
}

sub on_dendrogram_select {
    my $self = shift;
    my $rect = shift; # [x1, y1, x2, y2]

    if ($self->{tool} eq 'ZoomIn') {
        my $grid = $self->{dendrogram};
        $self->handle_grid_drag_zoom ($grid, $rect);
    }

    return;
}

##################################################
# Popup dialogs
##################################################

# When hovering over grid element, will highlight a path from the root to that element
sub on_grid_hover {
    my $self = shift;
    my $element = shift;

    no warnings 'uninitialized';  #  saves getting sprintf warnings we don't care about

    my $string = $self->get_grid_text_pfx;

    if ($element) {
        my $cluster_ref = $self->{output_ref};
        $self->{dendrogram}->clear_highlights();

        my $node_ref = eval {$cluster_ref->get_node_ref (node => $element)};
        if ($self->{use_highlight_path} and $node_ref) {
            $self->{dendrogram}->highlight_path($node_ref);
        }

        my $analysis_name = $self->{grid}{analysis};
        my $coloured_node = $self->get_coloured_node_for_element($element);
        if (defined $coloured_node && defined $analysis_name) {
            #  need to get the displayed node, not the terminal node
            my $list_ref = $coloured_node->get_list_ref (list => 'SPATIAL_RESULTS');  #  will need changing when otehr lists can be selected
            my $value = $list_ref->{$analysis_name};
            $string .= sprintf ("<b>Node %s : %s:</b> %.4f", $coloured_node->get_name, $analysis_name, $value);
            $string .= ", <b>Element:</b> $element";
        }
        elsif (! defined $analysis_name && defined $coloured_node) {
            $string .= sprintf '<b>Node %s </b>', $coloured_node->get_name;  #  should really grab the node number?
            $string .= ", <b>Element:</b> $element";
        }
        else {
            $string .= '<b>Not a coloured group:</b> ' . $element;
        }

    }
    else {
        $self->{dendrogram}->clear_highlights();
        $string = '';  #  clear the markup
    }
    $self->{xmlPage}->get_object('lblMap')->set_markup($string);

    return;
}

sub on_end_grid_hover {
    my $self = shift;
    $self->{dendrogram}->clear_highlights;
}

sub on_grid_popup {
    my $self = shift;
    my $element = shift;
    my $basedata_ref = $self->{basedata_ref};

    my ($sources, $default_source);
    my $node_ref = $self->get_coloured_node_for_element($element);

    if ($node_ref) {
        # This will add the "whole cluster" sources
        ($sources, $default_source) = get_sources_for_node($node_ref, $basedata_ref);
    }
    else {
        # Node isn't part of any cluster - just labels then
        $sources = {};
    }

    # Add source for labels just in this cell
    $sources->{'Labels (this cell)'} = sub {
        Biodiverse::GUI::CellPopup::show_all_labels(@_, $element, $basedata_ref);
    };

    Biodiverse::GUI::Popup::show_popup($element, $sources, $default_source);

    return;
}

sub on_dendrogram_popup {
    my $self = shift;
    my $node_ref = shift;
    my $basedata_ref = $self->{basedata_ref};
    my ($sources, $default_source) = get_sources_for_node($node_ref, $basedata_ref);
    Biodiverse::GUI::Popup::show_popup($node_ref->get_name, $sources, $default_source);

    return;
}

sub on_dendrogram_click {
    my ($self, $node) = @_;
    if ($self->{tool} eq 'Select') {
        $self->{dendrogram}->do_colour_nodes_below($node);
    }
    elsif ($self->{tool} eq 'ZoomOut') {
        $self->{dendrogram}->zoom_out();
    }
    elsif ($self->{tool} eq 'ZoomFit') {
        $self->{dendrogram}->zoom_fit();
    }
}

# Returns which coloured node the given element is under
#    works up the parent chain until it finds or match, undef otherwise
sub get_coloured_node_for_element {
    my $self = shift;
    my $element = shift;

    return $self->{dendrogram}->get_cluster_node_for_element($element);
}

sub get_sources_for_node {
    my $node_ref = shift;
    my $basedata_ref = shift;
    my %sources;
    #print Data::Dumper::Dumper($node_ref->get_value_keys);
    $sources{'Labels (cluster) calc_abc2'} = sub { show_cluster_labelsABC2(@_, $node_ref, $basedata_ref); };
    $sources{'Labels (cluster) calc_abc3'} = sub { show_cluster_labelsABC3(@_, $node_ref, $basedata_ref); };
    $sources{'Labels (cluster)'} = sub { show_cluster_labels(@_, $node_ref, $basedata_ref); };
    $sources{'Elements (cluster)'} = sub { show_cluster_elements(@_, $node_ref); };
    $sources{Descendants} = sub { show_cluster_descendents(@_, $node_ref); };

    # Custom lists - getValues() - all lists in node's $self
    # FIXME: try to merge with CellPopup::showOutputList
    my @lists = $node_ref->get_list_names;
    foreach my $name (@lists) {
        next if not defined $name;
        next if $name =~ /^_/; # leading underscore marks internal list

        #print "[Clustering] Adding custom list $name\n";
        $sources{$name} = sub { show_list(@_, $node_ref, $name); };
    }

    return (\%sources, 'Labels (cluster)'); # return a default too
}

# Called by popup dialog
# Shows a custom list
sub show_list {
    my $popup = shift;
    my $node_ref = shift;
    my $name = shift;

    #my $ref = $node_ref->get_value($name);
    my $ref = $node_ref->get_list_ref (list => $name);

    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::String');
    my $iter;

    if (is_hashref($ref)) {
        foreach my $key (sort_list_with_tree_names_aa ([keys %$ref])) {
            my $val = $ref->{$key};
            #print "[Dendrogram] Adding output hash entry $key\t\t$val\n";
            $iter = $model->append;
            $model->set($iter,    0,$key ,  1,$val);
        }
    }
    elsif (is_arrayref($ref)) {
        foreach my $elt (sort_list_with_tree_names_aa ([@$ref])) {
            #print "[Dendrogram] Adding output array entry $elt\n";
            $iter = $model->append;
            $model->set($iter, 0, $elt, 1, q{});
        }
    }
    elsif (not is_ref($ref)) {
        $iter = $model->append;
        $model->set($iter, 0, $ref, 1, q{});
    }

    $popup->set_value_column(1);
    $popup->set_list_model($model);
}

# Called by popup dialog
# Shows the labels for all elements under given node
sub show_cluster_labelsABC2 {
    my $popup = shift;
    my $node_ref = shift;
    my $basedata_ref = shift;

    #print "[Clustering tab] Making cluster labels model\n";
    # Get terminal elements
    my $elements = $node_ref->get_terminal_elements;

    # Use calc_abc2 to get the labels
    my @elements = keys %{$elements};
    #my %ABC = $basedata_ref->calc_abc2('element_list1'=> \@elements);
    my $indices_object = Biodiverse::Indices->new(BASEDATA_REF => $basedata_ref);
    my %ABC = $indices_object->calc_abc2(element_list1 => \@elements);
    my $total_labels = $ABC{label_hash_all};

    # Add each label into the model
    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::Int');
    foreach my $label (natsort keys %{$total_labels}) {
        my $iter = $model->append;
        $model->set($iter, 0, $label, 1, $total_labels->{$label});
    }

    $popup->set_list_model($model);
    $popup->set_value_column(1);
}

#  this is inefficient, as it is a near duplicate of show_cluster_labelsABC2 -
#   should really have an argument to select the ABC function
sub show_cluster_labelsABC3 {
    my $popup = shift;
    my $node_ref = shift;
    my $basedata_ref = shift;

    #print "[Clustering tab] Making cluster labels model\n";
    # Get terminal elements
    my $elements = $node_ref->get_terminal_elements;

    # Use calc_abc2 to get the labels
    my @elements = keys %{$elements};
    #my %ABC = $basedata_ref->calc_abc2('element_list1'=> \@elements);
    my $indices_object = Biodiverse::Indices->new(BASEDATA_REF => $basedata_ref);
    my %ABC = $indices_object->calc_abc3(element_list1 => \@elements);
    my $total_labels = $ABC{label_hash_all};

    # Add each label into the model
    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::Int');
    foreach my $label (natsort keys %{$total_labels}) {
        my $iter = $model->append;
        $model->set($iter,    0,$label ,  1,$total_labels->{$label});
    }

    $popup->set_list_model($model);
    $popup->set_value_column(1);
}

# Called by popup dialog
# Shows the labels for all elements under given node
sub show_cluster_labels {
    my $popup = shift;
    my $node_ref = shift;
    my $basedata_ref = shift;

    #print "[Clustering tab] Making cluster labels model\n";
    # Get terminal elements
    my $elements = $node_ref->get_terminal_elements;

    # For each element, get its labels and put into %total_labels
    my %total_labels;
    foreach my $element (keys %{$elements}) {
        my $labels = $basedata_ref->get_labels_in_group_as_hash_aa($element);
        #print Data::Dumper::Dumper(\%labels);
        @total_labels{keys %$labels} = undef;
    }

    # Add each label into the model
    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::String');
    foreach my $label (natsort keys %total_labels) {
        my $iter = $model->append;
        $model->set($iter, 0, $label, 1, q{});
    }

    $popup->set_list_model($model);
    $popup->set_value_column(1);
}

# Called by popup dialog
# Shows all elements under given node
sub show_cluster_elements {
    my $popup = shift;
    my $node_ref = shift;

    print "[Clustering tab] Making cluster elements model\n";
    my $elements = $node_ref->get_terminal_elements;
    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::Int');

    foreach my $element (natsort keys %{$elements}) {
        my $count = $elements->{$element};
        my $iter = $model->append;
        $model->set($iter,    0,$element ,  1,$count);
    }

    $popup->set_list_model($model);
    $popup->set_value_column(1);

    return;
}

# Called by popup dialog
# Shows all descendent nodes under given node
sub show_cluster_descendents {
    my $popup    = shift;
    my $node_ref = shift;

    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::Int');

    my $node_hash = $node_ref->get_names_of_all_descendants_and_self;

    foreach my $element (sort_list_with_tree_names_aa ([keys %$node_hash])) {
        my $count = $node_hash->{$element};
        my $iter  = $model->append;
        $model->set($iter, 0, $element, 1, $count);
    }

    $popup->set_list_model($model);
    $popup->set_value_column(1);

    return;
}

##################################################
# Misc dialog operations
##################################################

# Keep name in sync with the tab label
# and do a rename if the object exists
#  THIS IS almost the same as Biodiverse::GUI::Spatial::on_name_changed
#  all that differs is the widgets and some function calls
#  like get_cluster_output_ref
sub on_name_changed {
    my $self = shift;

    my $xml_page = $self->{xmlPage};
    my $name = $xml_page->get_object('txtClusterName')->get_text();

    my $label_widget = $self->{xmlLabel}->get_object('lblClusteringName');
    $label_widget->set_text($name);

    my $tab_menu_label = $self->{tab_menu_label};
    $tab_menu_label->set_text($name);


    my $param_widget
            = $xml_page->get_object('lbl_parameter_clustering_name');
    $param_widget->set_markup("<b>Name</b>");

    my $bd = $self->{basedata_ref};

    my $name_in_use = $bd->get_cluster_output_ref (name => $name);

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

sub on_clusters_changed {
    my $self = shift;
    my $spinbutton = $self->{xmlPage}->get_object('spinClusters');
    $self->{dendrogram}->set_num_clusters($spinbutton->get_value_as_int);
}

sub on_plot_mode_changed {
    my $self = shift;
    my $combo = shift;
    my $mode = $combo->get_active;
    if ($mode == 0) {
        $mode = 'depth';
    }
    elsif ($mode == 1) {
        $mode = 'length';
    }
    else {
        die "[Clustering tab] - on_plot_mode_changed - invalid mode $mode";
    }

    print "[Clustering tab] Changing mode to $mode\n";
    $self->{plot_mode} = $mode;
    $self->{dendrogram}->set_plot_mode($mode) if defined $self->{output_ref};
}

####
# TODO: This whole section needs to be deduplicated between Labels.pm
####
my %drag_modes = (
    Select  => 'click',
    Pan     => 'pan',
    ZoomIn  => 'select',
    ZoomOut => 'click',
    ZoomFit => 'click',
);

sub choose_tool {
    my $self = shift;
    my ($tool, ) = @_;

    my $old_tool = $self->{tool};

    if ($old_tool) {
        $self->{ignore_tool_click} = 1;
        my $widget = $self->{xmlPage}->get_object("btn${old_tool}ToolCL");
        $widget->set_active(0);
        my $new_widget = $self->{xmlPage}->get_object("btn${tool}ToolCL");
        $new_widget->set_active(1);
        $self->{ignore_tool_click} = 0;
    }

    $self->{tool} = $tool;

    $self->{grid}->{drag_mode}       = $drag_modes{$tool};
    $self->{dendrogram}->{drag_mode} = $drag_modes{$tool};

    $self->set_display_cursors ($tool);
}


sub on_highlight_groups_on_map_changed {
    my $self = shift;
    $self->{dendrogram}->set_use_highlight_func;

    return;
}


sub on_use_highlight_path_changed {
    my $self = shift;

    #  set to complement - should get widget check value
    $self->{use_highlight_path} = not $self->{use_highlight_path};

    #  clear any highlights
    if ($self->{dendrogram} && ! $self->{use_highlight_path}) {
        $self->{dendrogram}->clear_highlights;
    }

    return;
}

sub on_menu_use_slider_to_select_nodes {
    my $self = shift;

    #  set to complement - should get widget check value
    #  should also really register as a dendrogram callback
    $self->{dendrogram}->toggle_use_slider_to_select_nodes;

    return;
}


sub set_cell_outline_menuitem_active {
    my ($self, $active) = @_;
    $self->{xmlPage}->get_object('menu_cluster_cell_show_outline')->set_active($active);
}


sub on_group_mode_changed {
    my $self = shift;
    my $combo = shift;
    my $mode = $combo->get_active;
    if ($mode == 0) {
        $mode = 'depth';
    }
    elsif ($mode == 1) {
        $mode = 'length';
    }
    else {
        die "[Clustering tab] - on_group_mode_changed - invalid mode $mode";
    }

    print "[Clustering tab] Changing mode to $mode\n";
    $self->{group_mode} = $mode;
    $self->{dendrogram}->set_group_mode($mode);
}

sub recolour {
    my $self = shift;
    my %args = @_;

    #  need to update the grid before the tree else the grid is not changed properly
    $self->set_plot_min_max_values;
    $self->{grid}->set_legend_mode($self->{colour_mode});

    $self->{dendrogram}->recolour();
    if ($args{all_elements}) {
        $self->{dendrogram}->recolour_cluster_elements;
    }
}

sub set_plot_min_max_values {
    my $self = shift;

    #  nasty - should handle everything via this tab, not the dendrogram
    my $list  = $self->{dendrogram}->{analysis_list_name};
    my $index = $self->{dendrogram}->{analysis_list_index};

    return if ! defined $list || ! defined $index;

    my $stats = $self->{stats}{$list}{$index};
    if (not $stats) {
        $stats = $self->{output_ref}->get_list_stats (
            list  => $list,
            index => $index,
        );
    }

    $self->{plot_min_value} = $stats->{$self->{PLOT_STAT_MIN} || 'MIN'};
    $self->{plot_max_value} = $stats->{$self->{PLOT_STAT_MAX} || 'MAX'};

    $self->set_legend_ltgt_flags ($stats);

    $self->{dendrogram}->set_plot_min_max_values ($self->get_plot_min_max_values);

    return;
}

#  Same as the version in Spatial.pm except it calls
#  recolour instead of on_active_index_changed
sub on_menu_stretch_changed {
    my ($self, $menu_item) = @_;

    # Just got the signal for the deselected option. Wait for signal for
    # selected one.
    return if !$menu_item->get_active();

    my $sel = $menu_item->get_label();

    my ($min, $max) = split (/-/, uc $sel);

    my %stretch_codes = $self->get_display_stretch_codes;

    $self->{PLOT_STAT_MAX} = $stretch_codes{$max} || $max;
    $self->{PLOT_STAT_MIN} = $stretch_codes{$min} || $min;

    $self->recolour;
    #  not properly redisplaying map
    #  poss need to call on_map_index_changed, grabbing the current index

    return;
}



sub on_stretch_changed {
    my $self = shift;
    my $sel  = shift || 'min-max';

    if (blessed $sel) {
        #$sel = $sel->get_label;
        my $choice = $sel->get_active;
        print $choice;
        print;
    }

    my ($min, $max) = split (/-/, uc $sel);

    my %stretch_codes = $self->get_display_stretch_codes;

    $self->{PLOT_STAT_MAX} = $stretch_codes{$max} || $max;
    $self->{PLOT_STAT_MIN} = $stretch_codes{$min} || $min;

    $self->recolour;
    $self->{grid}->update_legend;

    return;
}

sub on_overlays {
    my $self = shift;
    my $button = shift;

    Biodiverse::GUI::Overlays::show_dialog( $self->{grid} );

    return;
}

sub undo_multiselect_click {
    my $self = shift;
    my $dendrogram = $self->{dendrogram};
    return $dendrogram->undo_multiselect_click;
}

sub redo_multiselect_click {
    my $self = shift;
    my $dendrogram = $self->{dendrogram};
    return $dendrogram->redo_multiselect_click;
}

my %key_tool_map = (
    U => 'undo_multiselect_click',
    R => 'redo_multiselect_click',
);

sub on_bare_key {
    my ($self, $keyval) = @_;

    no autovivification;

    my $tool = $key_tool_map{$keyval};

    return $self->SUPER::on_bare_key ($keyval)
      if not defined $tool;

    my $active_pane = $self->{active_pane};

    return if !defined $active_pane;

    $self->$tool;
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
    #say "Calling $method via autoload";
    return $self->$method(@_);
}

sub DESTROY {}  #  let the system handle destruction - need this for AUTOLOADER

1;
