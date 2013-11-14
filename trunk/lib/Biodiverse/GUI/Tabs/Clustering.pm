package Biodiverse::GUI::Tabs::Clustering;
use strict;
use warnings;
use 5.010;

use English qw( -no_match_vars );

use Gtk2;
use Carp;
use Scalar::Util qw /blessed isweak weaken/;
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

our $VERSION = '0.19';

use Biodiverse::Cluster;
use Biodiverse::RegionGrower;

use Data::Dumper;

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
    $self->{project} = $gui->getProject();
    bless $self, $class;

    # Load _new_ widgets from glade 
    # (we can have many Analysis tabs open, for example.
    # These have different objects/widgets)
    my $xml_page  = Gtk2::GladeXML->new($gui->getGladeFile, 'vpaneClustering');
    my $xml_label = Gtk2::GladeXML->new($gui->getGladeFile, 'hboxClusteringLabel');

    $self->{xmlPage}  = $xml_page;
    $self->{xmlLabel} = $xml_label;

    my $page  = $xml_page->get_widget('vpaneClustering');
    my $label = $xml_label->get_widget('hboxClusteringLabel');


    my $label_text = $self->{xmlLabel}->get_widget('lblClusteringName')->get_text;
    my $label_widget = Gtk2::Label->new ($label_text);
    $self->{tab_menu_label} = $label_widget;

    # Add to notebook
    $self->add_to_notebook (
        page         => $page,
        label        => $label,
        label_widget => $label_widget,
    );

    my $sp_initial1 = "sp_select_all ()\n"
                      . "#  This creates a complete matrix and is recommended "
                      . "as the last condition for clustering purposes";

    my $sp_initial2 = $empty_string;  #  initial spatial params text
    my $def_query_init1 = "sp_group_not_empty();\n# Condition is only needed if your BaseData has empty groups.";

    if (not defined $cluster_ref) {
        # We're being called as a NEW output
        # Generate a new output name

        my $bd = $self->{basedata_ref} = $self->{project}->getSelectedBaseData;

        if (not blessed ($bd)) {  #  this should be fixed now
            $self->onClose;
            croak "Basedata ref undefined - click on the basedata object "
                  . "in the outputs tab to select it (this is a bug)\n";
        }

        #  check if it has rand outputs already and warn the user
        if (my @a = $self->{basedata_ref}->get_randomisation_output_refs) {
            my $response = $gui->warn_outputs_exist_if_randomisation_run(
                $self->{basedata_ref}->get_param ('NAME'),
            );
            if (not $response eq 'yes') {
                $self->onClose;
                croak "User cancelled operation\n";
            }
        }

        $self->{output_name} = $self->{project}->makeNewOutputName(
            $self->{basedata_ref},
            $self->getType,
        );
        say "[Clustering tab] New cluster output " . $self->{output_name};

        if (!$bd->has_empty_groups) {
            $def_query_init1 = $empty_string;
        }

        $self->queueSetPane(1, 'vpaneClustering');
        $self->{existing} = 0;
    }
    else {  # We're being called to show an EXISTING output

        # Register as a tab for this output
        $self->registerInOutputsModel($cluster_ref, $self);

        $self->{output_name}  = $cluster_ref->get_param('NAME');
        $self->{basedata_ref} = $cluster_ref->get_param('BASEDATA_REF');
        print "[Clustering tab] Existing spatial output - "
              . $self->{output_name}
              . " within Basedata set - "
              . $self->{basedata_ref}->get_param ('NAME')
              . "\n";

        my $completed = $cluster_ref->get_param ('COMPLETED');
        $completed = 1 if not defined $completed;
        if ($completed == 1) {
            $self->queueSetPane(0.01, 'vpaneClustering');
            $self->{existing} = 1;
        }
        else {
            $self->queueSetPane(1, 'vpaneClustering');
            $self->{existing} = 0;
        }

        my $spatial_params = $cluster_ref->get_param ('SPATIAL_PARAMS') || [];
        $sp_initial1
            = defined $spatial_params->[0]
            ? $spatial_params->[0]->get_conditions_unparsed()
            : $NULL_STRING;
        $sp_initial2
            = defined $spatial_params->[1]
            ? $spatial_params->[1]->get_conditions_unparsed()
            : $NULL_STRING;

        $def_query_init1 = $cluster_ref->get_param ('DEFINITION_QUERY') //  $empty_string;
        if (blessed $def_query_init1) { #  get the text if already an object 
            $def_query_init1 = $def_query_init1->get_conditions_unparsed();
        }
        if (my $prng_seed = $cluster_ref->get_prng_seed_argument()) {
            my $spin_widget = $xml_page->get_widget('spinbutton_cluster_prng_seed');
            $spin_widget->set_value ($prng_seed);
        }
    }

    $self->{output_ref} = $cluster_ref;

    $self->setup_tie_breaker_widgets($cluster_ref);

    # Initialise widgets
    $xml_page ->get_widget('txtClusterName')->set_text( $self->{output_name} );
    $xml_label->get_widget('lblClusteringName')->set_text($self->{output_name} );
    $self->{tab_menu_label}->set_text($self->{output_name});

    $self->{title_widget} = $xml_page ->get_widget('txtClusterName');
    $self->{label_widget} = $xml_label->get_widget('lblClusteringName');

    $self->{spatialParams1}
        = Biodiverse::GUI::SpatialParams->new($sp_initial1);
    $xml_page->get_widget('frameClusterSpatialParams1')->add(
        $self->{spatialParams1}->get_widget,
    );

    my $hide_flag = not (length $sp_initial2);
    $self->{spatialParams2}
        = Biodiverse::GUI::SpatialParams->new($sp_initial2, $hide_flag);
    $xml_page->get_widget('frameClusterSpatialParams2')->add(
        $self->{spatialParams2}->get_widget
    );

    $hide_flag = not (length $def_query_init1);
    $self->{definition_query1}
        = Biodiverse::GUI::SpatialParams->new($def_query_init1, $hide_flag, 'is_def_query');
    $xml_page->get_widget('frameClusterDefinitionQuery1')->add(
        $self->{definition_query1}->get_widget
    );

    $xml_page->get_widget('plot_length') ->set_active(1);
    $xml_page->get_widget('group_length')->set_active(1);
    $self->{plot_mode}  = 'length';
    $self->{group_mode} = 'length';

    $self->{use_highlight_path} = 1;
    $self->{use_slider_to_select_nodes} = 1;

    $self->queueSetPane(0.5, 'hpaneClustering');
    $self->queueSetPane(1  , 'vpaneDendrogram');

    $self->makeIndicesModel($cluster_ref);
    $self->makeLinkageModel($cluster_ref);
    $self->initIndicesCombo();
    $self->initLinkageCombo();
    $self->initMap();
    eval {
        $self->initDendrogram();
    };
    if (my $e = $EVAL_ERROR) {
        $self->{gui}->report_error($e);
        $self->onClose;
        return;
    }
    $self->initMapShowCombo();
    $self->initMapListCombo();

    $self->{calculations_model}
        = Biodiverse::GUI::Tabs::CalculationsTree::makeCalculationsModel(
            $self->{basedata_ref}, $cluster_ref
        );

    Biodiverse::GUI::Tabs::CalculationsTree::initCalculationsTree(
        $xml_page->get_widget('treeSpatialCalculations'),
        $self->{calculations_model}
    );

    # select hue colour mode, red
    $xml_page->get_widget('comboClusterColours')->set_active(0);
    $xml_page->get_widget('clusterColourButton')->set_color(
        Gtk2::Gdk::Color->new(65535,0,0),  # red
    );

    # Connect signals
    $xml_label->get_widget('btnClose')->signal_connect_swapped(
        clicked => \&onClose,
        $self,
    );
    
    $self->{xmlPage}->get_widget('chk_output_gdm_format')->set_sensitive (0);

    $self->set_colour_stretch_widgets_and_signals;

    my %widgets_and_signals = (
        btnCluster          => {clicked => \&onRun},
        btnMapOverlays      => {clicked => \&onOverlays},
        btnMapZoomIn        => {clicked => \&onMapZoomIn},
        btnMapZoomOut       => {clicked => \&onMapZoomOut},
        btnMapZoomFit       => {clicked => \&onMapZoomFit},
        btnClusterZoomIn    => {clicked => \&onClusterZoomIn},
        btnClusterZoomOut   => {clicked => \&onClusterZoomOut},
        btnClusterZoomFit   => {clicked => \&onClusterZoomFit},
        spinClusters        => {'value-changed' => \&onClustersChanged},

        plot_length         => {toggled => \&onPlotModeChanged},
        group_length        => {toggled => \&onGroupModeChanged},

        highlight_groups_on_map =>
            {toggled => \&on_highlight_groups_on_map_changed},
        use_highlight_path_changed =>
            {toggled => \&on_use_highlight_path_changed},
        menu_use_slider_to_select_nodes =>
            {toggled => \&on_menu_use_slider_to_select_nodes},

        clusterColourButton => {color_set => \&onHueSet},
    
        comboClusterColours => {changed => \&onColourModeChanged},
        comboMapList        => {changed => \&onComboMapListChanged},
        txtClusterName      => {changed => \&onNameChanged},
        
        comboLinkage        => {changed => \&on_combo_linkage_changed},
        comboMetric         => {changed => \&on_combo_metric_changed},
        chk_output_to_file  => {clicked => \&on_chk_output_to_file_changed},

        menu_cluster_cell_outline_colour => {activate => \&on_set_cell_outline_colour},
    );

    while (my ($widget, $args) = each %widgets_and_signals) {
        $xml_page->get_widget($widget)->signal_connect_swapped(
            %$args, 
            $self,
        );
    }

    $self->set_frame_label_widget;
    
    print "[Clustering tab] - Loaded tab - Clustering Analysis\n";

    return $self;
}

#  change sensitivity of the GDM output widget
sub on_chk_output_to_file_changed {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_widget('chk_output_to_file');
    my $active = $widget->get_active;
    
    my $gdm_widget = $self->{xmlPage}->get_widget('chk_output_gdm_format');
    $gdm_widget->set_sensitive($active);

    return;
}

sub setup_tie_breaker_widgets {
    my $self     = shift;
    my $existing = shift;

    my $xml_page = $self->{xmlPage};
    my $hbox_name = 'hbox_cluster_tie_breakers';
    my $breaker_hbox = $xml_page->get_widget($hbox_name);

    my ($tie_breakers, $bd);
    if ($existing) {
        $tie_breakers = $existing->get_param ('CLUSTER_TIE_BREAKER');
        $bd = $existing->get_basedata_ref;
    }
    else {
        $bd = $self->{project}->getSelectedBaseData;
    }
    $tie_breakers //= [];  #  param is not always set

    my $indices_object = Biodiverse::Indices->new (BASEDATA_REF => $bd);
    my %valid_indices = $indices_object->get_valid_region_grower_indices;
    my %tmp = $indices_object->get_valid_cluster_indices;
    @valid_indices{keys %tmp} = values %tmp;
    
    my @tie_breaker_widgets;
    
    foreach my $i (0, 1) {
        my $id = $i + 1;
        my $j = 2 * $i;
        my $k = $j + 1;
        my $label = Gtk2::Label->new("  $id: ");
        my $index_combo = Gtk2::ComboBox->new_text;
        my $l = 0;
        my $use_iter;
        foreach my $index (qw /none random/, sort keys %valid_indices) {
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
            $use_iter_minmax = $minmax =~ /^min/ ? 0 : 1;
        }
        $combo_minmax->set_active ($use_iter_minmax || 0);

        my $hbox = Gtk2::HBox->new;
        $hbox->pack_start ($label, 0, 1, 0);
        $hbox->pack_start ($index_combo, 0, 1, 0);
        $hbox->pack_start ($combo_minmax, 0, 1, 0);
        $breaker_hbox->pack_start ($hbox, 0, 1, 0);
        push @tie_breaker_widgets, $index_combo, $combo_minmax;
    }
    $breaker_hbox->show_all();

    $self->{tie_breaker_widgets} = \@tie_breaker_widgets;

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
        my $widget = $xml_page->get_widget($widget_name);

        my $sub = sub {
            my $self = shift;
            my $widget = shift;

            return if ! $widget->get_active;  #  don't trigger on the deselected one

            $self->onStretchChanged ($stretch);

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
    
    my $widget = $self->{xmlPage}->get_widget('label_explain_linkage');
    
    my $linkage = $self->getSelectedLinkage;
    
    return;
};

#  change the explanation text
sub on_combo_metric_changed {
    my $self = shift;
    
    my $widget = $self->{xmlPage}->get_widget('label_explain_metric');
    
    my $metric = $self->getSelectedMetric;
    
    my $bd = $self->{basedata_ref} || $self->{project}->getSelectedBaseData;
    
    my $indices_object = Biodiverse::Indices->new (BASEDATA_REF => $bd);
    
    my $source_sub = $indices_object->get_index_source (index => $metric);
    my $metadata   = $indices_object->get_args (sub => $source_sub);

    my $explanation = 'Description: ' . $metadata->{indices}{$metric}{description};

    $widget->set_text($explanation);

    return;
};


sub set_frame_label_widget {
    my $self = shift;
    
    my $widget = Gtk2::ToggleButton->new_with_label('Parameters');
    $widget->show;

    my $frame = $self->{xmlPage}->get_widget('frame_cluster_parameters');
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
    
    my $frame = $self->{xmlPage}->get_widget('frame_cluster_parameters');
    my $widget = $frame->get_label_widget;
    my $active = $widget->get_active;

    my $table = $self->{xmlPage}->get_widget('tbl_cluster_parameters');

    if ($active) {
        $table->hide;
    }
    else {
        $table->show;
    }

    return;
}

sub initMap {
    my $self = shift;

    my $frame   = $self->{xmlPage}->get_widget('mapFrame');
    my $hscroll = $self->{xmlPage}->get_widget('mapHScroll');
    my $vscroll = $self->{xmlPage}->get_widget('mapVScroll');

    my $click_closure = sub { $self->onGridPopup(@_); };
    my $hover_closure = sub { $self->onGridHover(@_); };

    $self->{grid} = Biodiverse::GUI::Grid->new(
        $frame,
        $hscroll,
        $vscroll,
        1,
        0,
        $hover_closure,
        $click_closure
    );

    $self->{grid}->setBaseStruct($self->{basedata_ref}->get_groups_ref);

    return;
}

sub initDendrogram {
    my $self = shift;

    my $frame       =  $self->{xmlPage}->get_widget('clusterFrame');
    my $graphFrame  =  $self->{xmlPage}->get_widget('graphFrame');
    my $hscroll     =  $self->{xmlPage}->get_widget('clusterHScroll');
    my $vscroll     =  $self->{xmlPage}->get_widget('clusterVScroll');
    my $list_combo  =  $self->{xmlPage}->get_widget('comboMapList');
    my $index_combo =  $self->{xmlPage}->get_widget('comboMapShow');
    my $spinbutton  =  $self->{xmlPage}->get_widget('spinClusters');

    my $hover_closure       = sub { $self->onDendrogramHover(@_); };
    my $highlight_closure   = sub { $self->onDendrogramHighlight(@_); };
    my $click_closure       = sub { $self->onDendrogramPopup(@_); };

    $self->{dendrogram} = Biodiverse::GUI::Dendrogram->new(
        $frame,
        $graphFrame,
        $hscroll,
        $vscroll,
        $self->{grid},
        $list_combo,
        $index_combo,
        $hover_closure,
        $highlight_closure,
        $click_closure,
        undef,
        $self,
    );

    if ($self->{existing}) {
        my $cluster_ref = $self->{output_ref};

        my $completed = $cluster_ref->get_param ('COMPLETED');

        #  partial cluster analysis - don't try to plot it
        #  the defined test is for very backwards compatibility
        return if defined $completed && ! $completed;

        #print Data::Dumper::Dumper($cluster_ref);
        if (defined $cluster_ref) {
            $self->{dendrogram}->setCluster($cluster_ref, $self->{plot_mode});
        }
        $self->{dendrogram}->setGroupMode($self->{group_mode});
    }

    #  set the number of clusters in the spinbutton
    $spinbutton->set_value( $self->{dendrogram}->getNumClusters );

    return;
}

sub initMapShowCombo {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_widget('comboMapShow');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, markup => 0);

    return;
}

sub initMapListCombo {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_widget('comboMapList');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, markup => 0);

    #  trigger sensitivity
    $self->onComboMapListChanged;

    return;
}

#  if the list combo is "cluster" then desensitise several other widgets
sub onComboMapListChanged {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_widget('comboMapList');

    my $iter = $combo->get_active_iter;
    return if ! defined $iter; # this can occur if we are a new cluster output
                                #  as there are no map lists

    my $model = $combo->get_model;
    my $list = $model->get($iter, 0);

    my $sensitive = 1;
    if ($list eq '<i>Cluster</i>') {
        $sensitive = 0;
        $self->{grid}->hideLegend;
    }
    else {
        $self->{grid}->showLegend;
    }

    my @widgets = qw {
        comboMapShow
        comboClusterColours
        clusterColourButton
    };
    foreach my $widget (@widgets) {
        $self->{xmlPage}->get_widget($widget)->set_sensitive($sensitive);
    }

    return;
}

##################################################
# Indices combo
##################################################

sub makeIndicesModel {
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
    foreach my $name (sort keys %indices) {
    #while (my ($name, $description) = each %indices) {

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

sub makeLinkageModel {
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

sub initIndicesCombo {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_widget('comboMetric');
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

sub initLinkageCombo {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_widget('comboLinkage');
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
sub setPane {
    my $self = shift;
    my $pos  = shift;
    my $id   = shift;

    my $pane = $self->{xmlPage}->get_widget($id);
    my $maxPos = $pane->get('max-position');
    $pane->set_position( $maxPos * $pos );
    #print "[Clustering tab] Updating pane $id: maxPos = $maxPos, pos = $pos\n";
    
    return;
}

# This will schedule setPane to be called from a temporary signal handler
# Need when the pane hasn't got it's size yet and doesn't know its max position
sub queueSetPane {
    my $self = shift;
    my $pos = shift;
    my $id = shift;

    my $pane = $self->{xmlPage}->get_widget($id);

    # remember id so can disconnect later
    my $sig_id = $pane->signal_connect_swapped(
        'size-allocate',
        \&Biodiverse::GUI::Tabs::Clustering::setPaneSignal,
        [$self, $id]
    );
    $self->{"setPaneSignalID$id"} = $sig_id;
    $self->{"setPanePos$id"} = $pos;
    
    return;
}

sub setPaneSignal {
    my $args = shift;
    shift;
    my $pane = shift;

    my ($self, $id) = ($args->[0], $args->[1]);

    $self->setPane( $self->{"setPanePos$id"}, $id );
    $pane->signal_handler_disconnect( $self->{"setPaneSignalID$id"} );
    delete $self->{"setPanePos$id"};
    delete $self->{"setPaneSignalID$id"};
    
    return;
}

##################################################
# Misc interaction with rest of GUI
##################################################


sub getType {
    return 'Cluster';
}

sub get_output_type {
    return 'Biodiverse::Cluster';
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
    eval {$self->{dendrogram}->destroy()};

    $self->SUPER::remove;
    
    return;
}

##################################################
# Running the thing
##################################################

sub get_no_cache_abc_value {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_widget('chk_no_cache_abc');
    
    my $value = $widget->get_active;
    
    return $value;
}

sub get_build_matrices_only {
    my $self = shift;
    
    my $widget = $self->{xmlPage}->get_widget('chk_build_matrices_only');
    
    my $value = $widget->get_active;
    
    return $value;
}

sub get_output_gdm_format {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_widget('chk_output_gdm_format');
    
    my $value = $widget->get_active;
    
    return $value;
}

sub get_keep_spatial_nbrs_output {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_widget('chk_keep_spatial_nbrs_output');
    
    my $value = $widget->get_active;
    
    return $value;
}

sub get_no_clone_matrices {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_widget('chk_no_clone_matrices');

    my $value = $widget->get_active;

    return $value;
}

sub get_prng_seed {
    my $self = shift;

    my $widget = $self->{xmlPage}->get_widget('spinbutton_cluster_prng_seed');

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

sub get_output_file_handles {
    my $self = shift;
    
    my $widget = $self->{xmlPage}->get_widget('chk_output_to_file');
    
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

#sub close_output_file_handles {
#    my $self = shift;
#    my %args = @_;
#    
#    my $handles = $args{file_handles};
#    
#    foreach my $fh ()
#}

sub getSelectedMetric {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_widget('comboMetric');
    my $iter = $combo->get_active_iter;
    my $index = $self->{indices_model}->get($iter, MODEL_NAME);
    $index =~ s{\s.*}{};  #  remove anything after the first whitespace

    return $index;
}

sub getSelectedLinkage {
    my $self = shift;

    my $combo = $self->{xmlPage}->get_widget('comboLinkage');
    my $iter = $combo->get_active_iter;
    return $self->{linkage_model}->get($iter, MODEL_NAME);
}

#  handle inheritance
sub onRun {
    my $self = shift;
    my $button = shift;
    
    return $self->onRunAnalysis (@_);
}

sub get_overwrite_response {
    my ($self, $title, $text) = @_;
    
    my $rerun_spatial_value = -20;

    my $dlg = Gtk2::Dialog->new(
        $title,
        $self->{gui}->getWidget('wndMain'),
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

sub onRunAnalysis {
    my $self   = shift;
    my %args = @_;

    # Check spatial syntax
    return if ($self->{spatialParams1}->syntax_check('no_ok')    ne 'ok');
    return if ($self->{spatialParams2}->syntax_check('no_ok')    ne 'ok');
    return if ($self->{definition_query1}->syntax_check('no_ok') ne 'ok');

    # Load settings...
    $self->{output_name}    = $self->{xmlPage}->get_widget('txtClusterName')->get_text();
    my $selected_index      = $self->getSelectedMetric;
    my $selected_linkage    = $self->getSelectedLinkage;
    my $no_cache_abc        = $self->get_no_cache_abc_value;
    my $build_matrices_only = $self->get_build_matrices_only;
    my $file_handles        = $self->get_output_file_handles;
    my $output_gdm_format   = $self->get_output_gdm_format;
    my $keep_sp_nbrs_output = $self->get_keep_spatial_nbrs_output;
    my $no_clone_matrices   = $self->get_no_clone_matrices;
    my $prng_seed           = $self->get_prng_seed;

    # Get spatial calculations to run
    my @calculations_to_run = Biodiverse::GUI::Tabs::CalculationsTree::getCalculationsToRun(
        $self->{calculations_model}
    );

    my $pre_existing = $self->{output_ref};
    my $new_analysis = 1;

    # Delete existing?
    if (defined $self->{output_ref}) {
        my $completed = $self->{output_ref}->get_param('COMPLETED');

        if ($self->{existing} and defined $completed and $completed) {
            my $text = "$self->{output_name} exists.  \nDo you mean to overwrite it?";
            my $response = $self->get_overwrite_response ('Overwrite?', $text);
            #  drop out if we don't want to overwrite
            #my $response = Biodiverse::GUI::YesNoCancel->run({header => 'Overwrite?', text => $text});
            return 0 if ($response eq 'no' or $response eq 'cancel');
            if ($response eq 'run_spatial_calculations') {
                return 0 if not scalar @calculations_to_run;
                $new_analysis = 0;
            }
            #  Should really check if the analysis
            #  ran properly before setting this
            $self->{project}->setDirty;  
        }

        if ($new_analysis) {
            $self->{basedata_ref}->delete_output(output => $self->{output_ref});
            $self->{project}->deleteOutput($self->{output_ref});
            $self->{existing} = 0;
            $self->{output_ref} = undef;
        }
    }

    my $output_ref = $self->{output_ref};

    if ($new_analysis) {
        # Add cluster output
        $output_ref = eval {
            $self->{basedata_ref}->add_cluster_output(
                name => $self->{output_name},
                type => $self->get_output_type,
            );
        };
        if ($EVAL_ERROR) {
            $self->{gui}->report_error ($EVAL_ERROR);
            return;
        }
    
        $self->{output_ref} = $output_ref;
        $self->{project}->addOutput($self->{basedata_ref}, $output_ref);
    }

    my %analysis_args = (
        %args,
        matrix_ref           => $self->{project}->getSelectedMatrix,
        tree_ref             => $self->{project}->getSelectedPhylogeny,
        definition_query     => $self->{definition_query1}->get_text(),
        index                => $selected_index,
        linkage_function     => $selected_linkage,
        no_cache_abc         => $no_cache_abc,
        build_matrices_only  => $build_matrices_only,
        file_handles         => $file_handles,
        output_gdm_format    => $output_gdm_format,
        keep_sp_nbrs_output  => $keep_sp_nbrs_output,
        spatial_calculations => \@calculations_to_run,
        spatial_conditions   => [
            $self->{spatialParams1}->get_text(),
            $self->{spatialParams2}->get_text(),
        ],
        no_clone_matrices   => $no_clone_matrices,
        prng_seed           => $prng_seed,
    );

    my $tie_breakers  = $self->get_tie_breakers;
    $output_ref->set_param (CLUSTER_TIE_BREAKER => $tie_breakers);

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
        my $text = "Matrix output $name exists in the basedata.\nDelete it?";
        if (Biodiverse::GUI::YesNoCancel->run({header => 'Overwrite?', text => $text}) ne 'yes') {
            #  put back the pre-existing cluster output - not quite working yet
            $self->{basedata_ref}->delete_output(output => $output_ref);
            $self->{project}->deleteOutput($output_ref);
            $self->{basedata_ref}->add_output (object => $pre_existing);
            $self->{project}->addOutput($self->{basedata_ref}, $pre_existing);
            return 0;
        }
        $self->{basedata_ref}->delete_output(output => $e->object);
        $self->{project}->deleteOutput($e->object);
        goto RUN_CLUSTER;
    }
    elsif ($EVAL_ERROR) {
        $self->{gui}->report_error ($EVAL_ERROR);
    }

    if (not $success) {  # dropped out for some reason, eg no valid analyses.
        $self->onClose;  #  close the tab to avoid horrible problems with multiple instances
        return;
    }

    if ($keep_sp_nbrs_output) {
        my $sp_name = $output_ref->get_param('SP_NBRS_OUTPUT_NAME');
        my $sp_ref  = $self->{basedata_ref}->get_spatial_output_ref(name => $sp_name);
        $self->{project}->addOutput($self->{basedata_ref}, $sp_ref);
    }

    #  add the matrices to the outputs tab
    if ($new_analysis) {
        foreach my $ref ($output_ref->get_orig_matrices) {
            next if not $ref->get_element_count;  #  don't add if empty
            $self->{project}->addOutput($self->{basedata_ref}, $ref);
        }
    }

    $self->registerInOutputsModel($output_ref, $self);

    return if $success > 1;

    my $isnew = 0;
    if ($self->{existing} == 0) {
        $isnew = 1;
        $self->{existing} = 1;
    }

    if (Biodiverse::GUI::YesNoCancel->run({header => 'display results?'}) eq 'yes') {
        # If just ran a new analysis, pull up the pane
        if ($isnew or not $new_analysis) {
            $self->setPane(0.01, 'vpaneClustering');
            $self->setPane(1,    'vpaneDendrogram');
        }

        if (defined $output_ref) {
            $self->{dendrogram}->setCluster($output_ref, $self->{plot_mode});
        }
    }

    return;
}

##################################################
# Dendrogram
##################################################

# Called by dendrogram when user hovers over a node
# Updates those info labels
sub onDendrogramHover {
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

    $self->{xmlPage}->get_widget('lblMap')->set_markup($map_text);
    $self->{xmlPage}->get_widget('lblDendrogram')->set_markup($dendro_text);

    return;
}

# Circles a node's terminal elements. Clear marks if $node undef
sub onDendrogramHighlight {
    my $self = shift;
    my $node = shift;

    my $terminal_elements = (defined $node) ? $node->get_terminal_elements : {};
    $self->{grid}->markIfExists( $terminal_elements, 'circle' );

    #my @elts = keys %$terminal_elements;
    #print "marked: @elts\n";

    return;
}

##################################################
# Popup dialogs
##################################################

# When hovering over grid element, will highlight a path from the root to that element
sub onGridHover {
    my $self = shift;
    my $element = shift;

    no warnings 'uninitialized';  #  saves getting sprintf warnings we don't care about

    my $string;
    if ($element) {
        my $cluster_ref = $self->{output_ref};
        $self->{dendrogram}->clearHighlights();
        
        my $node_ref = eval {$cluster_ref->get_node_ref (node => $element)};
        if ($self->{use_highlight_path} and $node_ref) {
            $self->{dendrogram}->highlightPath($node_ref);
        }
        
        my $analysis_name = $self->{grid}{analysis};
        my $coloured_node = $self->getColouredNodeForElement($element);
        if (defined $coloured_node && defined $analysis_name) {
            #  need to get the displayed node, not the terminal node
            my $list_ref = $coloured_node->get_list_ref (list => 'SPATIAL_RESULTS');  #  will need changing when otehr lists can be selected
            my $value = $list_ref->{$analysis_name};
            $string = sprintf ("<b>Node %s : %s:</b> %.4f", $coloured_node->get_name, $analysis_name, $value);
            $string .= ", <b>Element:</b> $element";
        }
        elsif (! defined $analysis_name && defined $coloured_node) {
            $string = sprintf '<b>Node %s </b>', $coloured_node->get_name;  #  should really grab the node number?
            $string .= ", <b>Element:</b> $element";
        }
        else {
            $string = '<b>Not a coloured group:</b> ' . $element;
        }

    }
    else {
        $self->{dendrogram}->clearHighlights();
        $string = '';  #  clear the markup
    }
    $self->{xmlPage}->get_widget('lblMap')->set_markup($string);
    
    return;
}

sub onGridPopup {
    my $self = shift;
    my $element = shift;
    my $basedata_ref = $self->{basedata_ref};

    my ($sources, $default_source);
    my $node_ref = $self->getColouredNodeForElement($element);

    if ($node_ref) {
        # This will add the "whole cluster" sources
        ($sources, $default_source) = getSourcesForNode($node_ref, $basedata_ref);
    }
    else {
        # Node isn't part of any cluster - just labels then
        $sources = {};
    }

    # Add source for labels just in this cell
    $sources->{'Labels (this cell)'} = sub {
        Biodiverse::GUI::CellPopup::showAllLabels(@_, $element, $basedata_ref);
    };

    Biodiverse::GUI::Popup::showPopup($element, $sources, $default_source);
    
    return;
}

sub onDendrogramPopup {
    my $self = shift;
    my $node_ref = shift;
    my $basedata_ref = $self->{basedata_ref};
    my ($sources, $default_source) = getSourcesForNode($node_ref, $basedata_ref);
    Biodiverse::GUI::Popup::showPopup($node_ref->get_name, $sources, $default_source);
    
    return;
}

# Returns which coloured node the given element is under
#    works up the parent chain until it finds or match, undef otherwise
sub getColouredNodeForElement {
    my $self = shift;
    my $element = shift;

    return $self->{dendrogram}->getClusterNodeForElement($element);
}

sub getSourcesForNode {
    my $node_ref = shift;
    my $basedata_ref = shift;
    my %sources;
    #print Data::Dumper::Dumper($node_ref->get_value_keys);
    $sources{'Labels (cluster) calc_abc2'} = sub { showClusterLabelsABC2(@_, $node_ref, $basedata_ref); };
    $sources{'Labels (cluster) calc_abc3'} = sub { showClusterLabelsABC3(@_, $node_ref, $basedata_ref); };
    $sources{'Labels (cluster)'} = sub { showClusterLabels(@_, $node_ref, $basedata_ref); };
    $sources{'Elements (cluster)'} = sub { showClusterElements(@_, $node_ref); };

    # Custom lists - getValues() - all lists in node's $self
    # FIXME: try to merge with CellPopup::showOutputList
    my @lists = $node_ref->get_list_names;
    foreach my $name (@lists) {
        next if not defined $name;
        next if $name =~ /^_/; # leading underscore marks internal list

        #print "[Clustering] Adding custom list $name\n";
        $sources{$name} = sub { showList(@_, $node_ref, $name); };
    }

    return (\%sources, 'Labels (cluster)'); # return a default too
}

# Called by popup dialog
# Shows a custom list
sub showList {
    my $popup = shift;
    my $node_ref = shift;
    my $name = shift;

    #my $ref = $node_ref->get_value($name);
    my $ref = $node_ref->get_list_ref (list => $name);

    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::String');
    my $iter;

    if (ref($ref) eq 'HASH') {
        foreach my $key (sort keys %$ref) {
            my $val = $ref->{$key};
            #print "[Dendrogram] Adding output hash entry $key\t\t$val\n";
            $iter = $model->append;
            $model->set($iter,    0,$key ,  1,$val);
        }
    }
    elsif (ref($ref) eq 'ARRAY') {
        foreach my $elt (sort @$ref) {
            #print "[Dendrogram] Adding output array entry $elt\n";
            $iter = $model->append;
            $model->set($iter, 0, $elt, 1, q{});
        }
    }
    elsif (not ref($ref)) {
        $iter = $model->append;
        $model->set($iter, 0, $ref, 1, q{});
    }

    $popup->setValueColumn(1);
    $popup->setListModel($model);
}

# Called by popup dialog
# Shows the labels for all elements under given node
sub showClusterLabelsABC2 {
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
    foreach my $label (sort keys %{$total_labels}) {
        my $iter = $model->append;
        $model->set($iter, 0, $label, 1, $total_labels->{$label});
    }

    $popup->setListModel($model);
    $popup->setValueColumn(1);
}

#  this is inefficient, as it is a near duplicate of showClusterLabelsABC2 -
#   should really have an argument to select the ABC function
sub showClusterLabelsABC3 {
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
    foreach my $label (sort keys %{$total_labels}) {
        my $iter = $model->append;
        $model->set($iter,    0,$label ,  1,$total_labels->{$label});
    }

    $popup->setListModel($model);
    $popup->setValueColumn(1);
}

# Called by popup dialog
# Shows the labels for all elements under given node
sub showClusterLabels {
    my $popup = shift;
    my $node_ref = shift;
    my $basedata_ref = shift;

    #print "[Clustering tab] Making cluster labels model\n";
    # Get terminal elements
    my $elements = $node_ref->get_terminal_elements;

    # For each element, get its labels and put into %total_labels
    my %total_labels;
    foreach my $element (sort keys %{$elements}) {
        my %labels = $basedata_ref->get_labels_in_group_as_hash(group => $element);
        #print Data::Dumper::Dumper(\%labels);
        @total_labels{keys %labels} = undef;
    }

    # Add each label into the model
    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::String');
    foreach my $label (sort keys %total_labels) {
        my $iter = $model->append;
        $model->set($iter, 0, $label, 1, q{});
    }

    $popup->setListModel($model);
    $popup->setValueColumn(1);
}

# Called by popup dialog
# Shows all elements under given node
sub showClusterElements {
    my $popup = shift;
    my $node_ref = shift;

    print "[Clustering tab] Making cluster elements model\n";
    my $elements = $node_ref->get_terminal_elements;
    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::Int');

    foreach my $element (sort keys %{$elements}) {
        my $count = $elements->{$element};
        my $iter = $model->append;
        $model->set($iter,    0,$element ,  1,$count);
    }

    $popup->setListModel($model);
    $popup->setValueColumn(1);
    
    return;
}

##################################################
# Misc dialog operations
##################################################

# Keep name in sync with the tab label
# and do a rename if the object exists
#  THIS IS almost the same as Biodiverse::GUI::Spatial::onNameChanged
#  all that differs is the widgets and some function calls
#  like get_cluster_output_ref
sub onNameChanged {
    my $self = shift;
    
    my $xml_page = $self->{xmlPage};
    my $name = $xml_page->get_widget('txtClusterName')->get_text();
    
    my $label_widget = $self->{xmlLabel}->get_widget('lblClusteringName');
    $label_widget->set_text($name);
    
    my $tab_menu_label = $self->{tab_menu_label};
    $tab_menu_label->set_text($name);

    
    my $param_widget
            = $xml_page->get_widget('lbl_parameter_clustering_name');
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

        $self->{project}->updateOutputName( $object );
        $self->{output_name} = $name;
    }
    
    return;
}

sub onMapZoomIn {
    my $self = shift;
    $self->{grid}->zoomIn();
}

sub onMapZoomOut {
    my $self = shift;
    $self->{grid}->zoomOut();
}

sub onMapZoomFit {
    my $self = shift;
    $self->{grid}->zoomFit();
}

sub onClusterZoomIn {
    my $self = shift;
    $self->{dendrogram}->zoomIn();
}

sub onClusterZoomOut {
    my $self = shift;
    $self->{dendrogram}->zoomOut();
}

sub onClusterZoomFit {
    my $self = shift;
    $self->{dendrogram}->zoomFit();
}

sub onClustersChanged {
    my $self = shift;
    my $spinbutton = $self->{xmlPage}->get_widget('spinClusters');
    $self->{dendrogram}->setNumClusters($spinbutton->get_value_as_int);
}

sub onPlotModeChanged {
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
        die "[Clustering tab] - onPlotModeChanged - invalid mode $mode";
    }

    print "[Clustering tab] Changing mode to $mode\n";
    $self->{plot_mode} = $mode;
    $self->{dendrogram}->setPlotMode($mode) if defined $self->{output_ref};
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
        $self->{dendrogram}->clearHighlights;
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

sub on_set_cell_outline_colour {
    my $self = shift;
    my $menu_item = shift;
    $self->{grid}->set_cell_outline_colour (@_);
    return;
}

sub onGroupModeChanged {
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
        die "[Clustering tab] - onGroupModeChanged - invalid mode $mode";
    }

    print "[Clustering tab] Changing mode to $mode\n";
    $self->{group_mode} = $mode;
    $self->{dendrogram}->setGroupMode($mode);
}

sub onColourModeChanged {
    my $self = shift;
    
    $self->set_plot_min_max_values;

    my $colours = $self->{xmlPage}->get_widget('comboClusterColours')->get_active_text();

    $self->{grid}->setLegendMode($colours);
    $self->{dendrogram}->recolour();

    return;
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



sub onStretchChanged {
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

    $self->onColourModeChanged;

    return;
}

#  should be onSatSet?
sub onHueSet {
    my $self = shift;
    my $button = shift;

    my $combo_colours_hue_choice = 1;

    my $widget = $self->{xmlPage}->get_widget('comboClusterColours');

    #  a bodge to set the active colour mode to Hue
    my $active = $widget->get_active;

    $widget->set_active($combo_colours_hue_choice);
    $self->{grid}->setLegendHue($button->get_color());
    $self->{dendrogram}->recolour();

    return;
}

sub onOverlays {
    my $self = shift;
    my $button = shift;

    Biodiverse::GUI::Overlays::showDialog( $self->{grid} );

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
