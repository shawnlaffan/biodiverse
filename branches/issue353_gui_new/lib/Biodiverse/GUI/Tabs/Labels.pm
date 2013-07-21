package Biodiverse::GUI::Tabs::Labels;
use strict;
use warnings;

use English ( -no_match_vars );

use Data::Dumper;

use Gtk2;
use Carp;
use List::Util qw/min max/;
use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::MatrixGrid;
use Biodiverse::GUI::Grid;
use Biodiverse::GUI::Project;
use Biodiverse::GUI::Overlays;

our $VERSION = '0.18_006';

use base qw {
    Biodiverse::GUI::Tabs::Tab
    Biodiverse::Common
};

use constant LABELS_MODEL_NAME          => 0;
use constant LABELS_MODEL_SAMPLE_COUNT  => 1;
use constant LABELS_MODEL_VARIETY       => 2;
use constant LABELS_MODEL_REDUNDANCY    => 3;
#use constant LABELS_MODEL_LIST1_SEL     => 4;
#use constant LABELS_MODEL_LIST2_SEL     => 5;
my $labels_model_list1_sel_col;  # these are set in sub makeLabelsModel
my $labels_model_list2_sel_col;

use constant CELL_WHITE => Gtk2::Gdk::Color->new(255*257, 255*257, 255*257);

my $selected_list1_name = 'Selected';
my $selected_list2_name = 'Col selected';

##################################################
# Initialisation
##################################################

sub new {
    my $class = shift;
    
    my $self = {
        gui           => Biodiverse::GUI::GUIManager->instance(),
        selected_rows => [],
        selected_cols => [],
    };
    $self->{project} = $self->{gui}->getProject();
    bless $self, $class;
    
    $self->set_default_params;


    # Load _new_ widgets from glade 
    # (we can have many Analysis tabs open, for example. These have a different object/widgets)
    $self->{xmlPage}  = Gtk2::GladeXML->new($self->{gui}->getGladeFile, 'hboxLabelsPage');
    $self->{xmlLabel} = Gtk2::GladeXML->new($self->{gui}->getGladeFile, 'hboxLabelsLabel');

    my $page  = $self->{xmlPage}->get_widget('hboxLabelsPage');
    my $label = $self->{xmlLabel}->get_widget('hboxLabelsLabel');
    my $tab_menu_label = Gtk2::Label->new('Labels tab');
    $self->{tab_menu_label} = $tab_menu_label;

    # Add to notebook
    $self->add_to_notebook (
        page         => $page,
        label        => $label,
        label_widget => $tab_menu_label,
    );

    # Get basename
    # Something has to be selected - otherwise menu item is disabled
    $self->{base_ref} = $self->{project}->getSelectedBaseData();

    # Initialise widgets
    my $label_widget = $self->{xmlLabel}->get_widget('lblLabelsName');
    my $text = 'Labels - ' . $self->{base_ref}->get_param('NAME');
    $label_widget->set_text($text);
    $self->{label_widget} = $label_widget;
    $self->{tab_menu_label}->set_text($text);

    $self->makeLabelsModel();
    $self->initList('listLabels1');
    $self->initList('listLabels2');

    if (! $self->initGrid()) {       #  close if user cancelled during display
        $self->onClose;
        croak "User cancelled grid initialisation, closing\n";
    }

    if (! $self->initMatrixGrid()) { #  close if user cancelled during display
        $self->onClose;
        croak "User cancelled matrix initialisation, closing\n";
    }
    # Register callbacks when selected matrix is changed
    $self->{matrix_callback}    = sub { $self->onSelectedMatrixChanged(); };
    $self->{project}->registerSelectionCallback(
        'matrix',
        $self->{matrix_callback},
    );
    $self->onSelectedMatrixChanged();

    #  this won't take long, so no cancel handler 
    $self->initDendrogram();
    # Register callbacks when selected phylogeny is changed
    $self->{phylogeny_callback} = sub { $self->onSelectedPhylogenyChanged(); };
    $self->{project}->registerSelectionCallback(
        'phylogeny',
        $self->{phylogeny_callback},
    );
    $self->onSelectedPhylogenyChanged();

    # "open up" the panes
    $self->queueSetPane(0.5, 'hpaneLabelsTop');
    $self->queueSetPane(0.5, 'hpaneLabelsBottom');
    $self->queueSetPane(0.5, 'vpaneLabels');
    # vpaneLists is done after hpaneLabelsTop, since this panel isn't able to get
    # its max size before hpaneLabelsTop is resized

    # Connect signals
    my $xml = $self->{xmlPage};

    $self->{xmlLabel}->get_widget('btnLabelsClose')->signal_connect_swapped(clicked => \&onClose, $self);

    # Connect signals for new side tool chooser
    my $sig_clicked = sub {
        my ($widget, $f) = @_;
        $self->{xmlPage}->get_widget($widget)->signal_connect_swapped(
            clicked => $f, $self);
    };

    $sig_clicked->('btnSelectTool', \&onSelectTool);
    $sig_clicked->('btnPanTool', \&onPanTool);
    $sig_clicked->('btnZoomTool', \&onZoomTool);
    $sig_clicked->('btnZoomOutTool', \&onZoomOutTool);
    $sig_clicked->('btnZoomFitTool', \&onZoomFitTool);

    $xml->get_widget('menuitem_labels_overlays')->signal_connect_swapped(activate => \&onOverlays, $self);

    $self->{xmlPage}->get_widget("btnSelectTool")->set_active(1);

    #  CONVERT THIS TO A HASH BASED LOOP, as per Clustering.pm
    #$xml->get_widget('btnZoomInVL')->signal_connect_swapped(clicked => \&onZoomIn, $self->{grid});
    #$xml->get_widget('btnZoomOutVL')->signal_connect_swapped(clicked => \&onZoomOut, $self->{grid});
    #$xml->get_widget('btnZoomFitVL')->signal_connect_swapped(clicked => \&onZoomFit, $self->{grid});
    $xml->get_widget('btnMatrixZoomIn')->signal_connect_swapped(clicked => \&onZoomIn, $self->{matrix_grid});
    $xml->get_widget('btnMatrixZoomOut')->signal_connect_swapped(clicked => \&onZoomOut, $self->{matrix_grid});
    $xml->get_widget('btnMatrixZoomFit')->signal_connect_swapped(clicked => \&onZoomFit, $self->{matrix_grid});
    $xml->get_widget('btnPhylogenyZoomIn')->signal_connect_swapped(clicked => \&onZoomIn, $self->{dendrogram});
    $xml->get_widget('btnPhylogenyZoomOut')->signal_connect_swapped(clicked => \&onZoomOut, $self->{dendrogram});
    $xml->get_widget('btnPhylogenyZoomFit')->signal_connect_swapped(clicked => \&onZoomFit, $self->{dendrogram});
    $xml->get_widget('phylogeny_plot_length')->signal_connect_swapped('toggled' => \&onPhylogenyPlotModeChanged, $self);
    #$xml->get_widget('phylogeny_plot_range_weighted')->signal_connect_swapped('toggled' => \&onPhylogenyPlotModeChanged, $self);
    $xml->get_widget('highlight_groups_on_map_labels_tab')->signal_connect_swapped('toggled' => \&on_highlight_groups_on_map_changed, $self);
    $xml->get_widget('use_highlight_path_changed1')->signal_connect_swapped(toggled => \&on_use_highlight_path_changed, $self);
    
    $self->{use_highlight_path} = 1;
    
    print "[GUI] - Loaded tab - Labels\n";
    
    
    return $self;
}

sub initGrid {
    my $self = shift;

    my $frame   = $self->{xmlPage}->get_widget('gridFrameViewLabels');
    my $hscroll = $self->{xmlPage}->get_widget('gridHScrollViewLabels');
    my $vscroll = $self->{xmlPage}->get_widget('gridVScrollViewLabels');

    my $hover_closure  = sub { $self->onGridHover(@_); };
    my $click_closure  = sub { Biodiverse::GUI::CellPopup::cellClicked($_[0], $self->{base_ref}); };
    my $select_closure = sub { $self->onGridSelect(@_); };
    my $grid_click_closure = sub { $self->onGridClick(@_); };

    $self->{grid} = Biodiverse::GUI::Grid->new(
        $frame,
        $hscroll,
        $vscroll,
        0,
        0,
        $hover_closure,
        $click_closure,
        $select_closure,
        $grid_click_closure
    );

    eval {$self->{grid}->setBaseStruct($self->{base_ref}->get_groups_ref)};
    if ($EVAL_ERROR) {
        $self->{gui}->report_error ($EVAL_ERROR);
        return;
    }
    
    $self->{grid}->setLegendMode('Sat');
    
    return 1;
}

sub initMatrixGrid {
    my $self = shift;

    my $frame   = $self->{xmlPage}->get_widget('matrixFrame');
    my $hscroll = $self->{xmlPage}->get_widget('matrixHScroll');
    my $vscroll = $self->{xmlPage}->get_widget('matrixVScroll');

    my $click_closure = sub { $self->onMatrixClicked(@_); };
    my $hover_closure = sub { $self->onMatrixHover(@_); };

    $self->{matrix_grid} = Biodiverse::GUI::MatrixGrid->new(
        $frame,
        $hscroll,
        $vscroll,
        $hover_closure,
        $click_closure
    );

    $self->{matrix_drawn} = 0;
    
    return 1;
}

# For the phylogeny tree:
sub initDendrogram {
    my $self = shift;
    
    my $frame      = $self->{xmlPage}->get_widget('phylogenyFrame');
    my $graphFrame = $self->{xmlPage}->get_widget('phylogenyGraphFrame');
    my $hscroll    = $self->{xmlPage}->get_widget('phylogenyHScroll');
    my $vscroll    = $self->{xmlPage}->get_widget('phylogenyVScroll');

    my $list_combo  = $self->{xmlPage}->get_widget('comboPhylogenyLists');
    my $index_combo = $self->{xmlPage}->get_widget('comboPhylogenyShow');

    my $highlight_closure  = sub { $self->onPhylogenyHighlight(@_); };
    my $ctrl_click_closure = sub { $self->onPhylogenyPopup(@_); };
    my $click_closure      = sub { $self->onPhylogenyClick(@_); };
    
    $self->{dendrogram} = Biodiverse::GUI::Dendrogram->new(
        $frame,
        $graphFrame,
        $hscroll,
        $vscroll,
        undef,
        $list_combo,
        $index_combo,
        undef,
        $highlight_closure,
        $ctrl_click_closure,
        $click_closure,
        $self->{base_ref},
    );
    
    #  cannot colour more than one in a phylogeny
    $self->{dendrogram}->setNumClusters (1);
    
    return 1;
}


##################################################
# Labels list
##################################################

sub addColumn {
    my $self = shift;
    my $tree = shift;
    my $title = shift;
    my $model_id = shift;
    
    my $col = Gtk2::TreeViewColumn->new();
    my $renderer = Gtk2::CellRendererText->new();
    #$title = Glib::Markup::escape_text($title);
    #  Double the underscores so they display without acting as hints.
    #  Need to find out how to disable that hint setting.
    $title =~ s/_/__/g;  
    $col->set_title($title);
    my $a = $col->get_title;
    #$col->set_sizing('fixed');
    $col->pack_start($renderer, 0);
    $col->add_attribute($renderer,  text => $model_id);
    $col->set_sort_column_id($model_id);
    $col->signal_connect_swapped(clicked => \&onSorted, $self);
    #$col->set('autosize' => 'True');
    $col->set (resizable => 1);
    
    $tree->insert_column($col, -1);
    
    return;
}

sub initList {
    my $self = shift;
    my $id   = shift;
    my $tree = $self->{xmlPage}->get_widget($id);
    

    my $labels_ref = $self->{base_ref}->get_labels_ref;
    my $stats_metadata = $labels_ref->get_args (sub => 'get_base_stats');
    my @columns;
    my $i = 0;
    $self->addColumn ($tree, 'Label', $i);
    foreach my $column (@$stats_metadata) {
        $i++;
        my ($key, $value) = %$column;
        my $column_name = Glib::Markup::escape_text (ucfirst lc $key);
        $self->addColumn ($tree, $column_name, $i);
    }
    $self->addColumn ($tree, $selected_list1_name, ++$i);
    $self->addColumn ($tree, $selected_list2_name, ++$i);
    
    # Set model to a wrapper that lets this list have independent sorting
    my $wrapper_model = Gtk2::TreeModelSort->new( $self->{labels_model});
    $tree->set_model( $wrapper_model );

    my $sort_func = \&sort_by_column;
    my $start_col = 1;
    if ($self->{base_ref}->labels_are_numeric) {
        $sort_func = \&sort_by_column_numeric_labels;
        $start_col = 0;
    }
    
    #  set a special sort func for all cols (except the labels if not numeric)
    foreach my $col_id ($start_col .. $i) {
        $wrapper_model->set_sort_func ($col_id, $sort_func, [$col_id, $wrapper_model]);
    }

    # Monitor selections
    $tree->get_selection->set_mode('multiple');
    $tree->get_selection->signal_connect(
        changed => \&onSelectedLabelsChanged,
        [$self, $id],
    );
    
    #$tree->signal_connect_swapped(
    #    'start-interactive-search' => \&on_interactive_search,
    #    [$self, $id],
    #);
    
    return;
}


#  sort by this column, then by labels column (always ascending)
#  labels column should not be hardcoded if we allow re-ordering of columns
sub sort_by_column {
    my ($liststore, $itera, $iterb, $args) = @_;
    my $col_id = $args->[0];
    my $wrapper_model = $args->[1];
    
    my $label_order = 1;
    my ($sort_column_id, $order) = $wrapper_model->get_sort_column_id;
    if ($order eq 'descending') {
        $label_order = -1;  #  ensure ascending order
    }

    return
         $liststore->get($itera, $col_id) <=> $liststore->get($iterb, $col_id)
      || $label_order * ($liststore->get($itera, 0) cmp $liststore->get($iterb, 0));
}

sub sort_by_column_numeric_labels {
    my ($liststore, $itera, $iterb, $args) = @_;
    my $col_id = $args->[0];
    my $wrapper_model = $args->[1];
    
    my $label_order = 1;
    my ($sort_column_id, $order) = $wrapper_model->get_sort_column_id;
    if ($order eq 'descending') {
        $label_order = -1;  #  ensure ascending order
    }
    
    return
         $liststore->get($itera, $col_id) <=> $liststore->get($iterb, $col_id)
      || $label_order * (0+$liststore->get($itera, 0) <=> 0+$liststore->get($iterb, 0));    
}

#sub on_interactive_search {
#    my $self = shift;
#    my $id   = shift;
#    
#    print "Interactive searching $id";
#}

# Creates a TreeView model of all labels
sub makeLabelsModel {
    my $self = shift;
    my $params = shift;

    my $base_ref = $self->{base_ref};
    my $labels_ref = $base_ref->get_labels_ref();

    my $basestats_indices = $labels_ref->get_args (sub => 'get_base_stats');
    
    my @column_order;
    
    #  the selection cols
    my @selection_cols = (
        {$selected_list1_name => 'Int'},
        {$selected_list2_name => 'Int'},
    );
    
    #my $label_type = $base_ref->labels_are_numeric ? 'Glib::Float' : 'Glib::String';
    my $label_type = 'Glib::String';
    
    my @types = ($label_type);
    #my $i = 0;
    foreach my $column (@$basestats_indices, @selection_cols) {
        my ($key, $value) = %{$column};
        push @types, 'Glib::' . $value;
        push @column_order, $key;
    }

    $self->{labels_model} = Gtk2::ListStore->new(@types);
    my $model = $self->{labels_model};

    my @labels = $base_ref->get_labels();
    
    my $sort_func = $base_ref->labels_are_numeric ? sub {$a <=> $b} : sub {$a cmp $b};

    foreach my $label (sort $sort_func @labels) {
        my $iter = $model->append();
        $model->set($iter, 0, $label);

        #  set the values - selection cols will be undef
        my %stats = $labels_ref->get_base_stats (element => $label);

        my $i = 1;
        foreach my $column (@column_order) {
            $model->set ($iter, $i, defined $stats{$column} ? $stats{$column} : -99999);
            $i++;
        }
    }
    
    $labels_model_list1_sel_col = scalar @column_order - 1;
    $labels_model_list2_sel_col = scalar @column_order;

    return;
}

sub setPhylogenyOptionsSensitive {
    my $self = shift;
    my $enabled = shift;

    my $page = $self->{xmlPage};

    for my $widget (
            'phylogeny_plot_length',
            'phylogeny_plot_depth',
            'highlight_groups_on_map_labels_tab',
            'use_highlight_path_changed1') {
        $page->get_widget($widget)->set_sensitive($enabled);
    }
}

sub onSelectedPhylogenyChanged {
    my $self = shift;

    # phylogenies
    my $phylogeny = $self->{project}->getSelectedPhylogeny;

    $self->{dendrogram}->clear;
    if ($phylogeny) {
        $self->{dendrogram}->setCluster($phylogeny, 'length');  #  now storing tree objects directly
        $self->setPhylogenyOptionsSensitive(1);
    }
    else {
        #$self->{dendrogram}->clear;
        $self->setPhylogenyOptionsSensitive(0);
        my $str = '<i>No selected tree</i>';
        $self->{xmlPage}->get_widget('label_VL_tree')->set_markup($str);
    }

    return;
}

sub on_highlight_groups_on_map_changed {
    my $self = shift;
    $self->{dendrogram}->set_use_highlight_func;
    
    return;
}

sub onSelectedMatrixChanged {
    my $self = shift;

    my $matrix_ref = $self->{project}->getSelectedMatrix;
    
    $self->{matrix_ref} = $matrix_ref;
    
    my $xml_page = $self->{xmlPage};

    #  hide the second list if no matrix selected
    my $list_window = $xml_page->get_widget('scrolledwindow_labels2');
    
    my $list = $xml_page->get_widget('listLabels1');
    my $col  = $list->get_column ($labels_model_list2_sel_col);
    
    if (! defined $matrix_ref) {
        $list_window->hide;     #  hide the second list
        $col->set_visible (0);  #  hide the list 2 selection
                                #    col from list 1
    }
    else {
        $list_window->show;
        $col->set_visible (1);
    }
    
    $self->{matrix_drawable} = $self->get_label_count_in_matrix;

    # matrix
    $self->onSorted(); # (this reloads the whole matrix anyway)    
    $self->{matrix_grid}->zoomFit();
    
    return;
}


# Called when user changes selection in one of the two labels lists
sub onSelectedLabelsChanged {
    my $selection = shift;
    my $args = shift;
    my ($self, $id) = @$args;

    # Ignore waste-of-time events fired on onPhylogenyClick as it
    # selects labels one-by-one
    return if (defined $self->{ignore_selected_change});

    # are we changing the row or col list?
    my $rowcol = $id eq 'listLabels1' ? 'rows' : 'cols';
    my $select_list_name = 'selected_' . $rowcol;

    # Select rows/cols in the matrix
    my @paths = $selection->get_selected_rows();
    my @selected = map { ($_->get_indices)[0] } @paths;
    $self->{$select_list_name} = \@selected;
    
    if ($self->{matrix_ref}) {
        $self->{matrix_grid}->highlight(
            $self->{selected_rows},
            $self->{selected_cols},
        );
    }
    
    #  need to avoid changing paths due to re-sorts
    #  the run for listLabels1 is at the end.
    if ($id eq 'listLabels2') {
        $self->set_selected_list_cols ($selection, $rowcol);
    }
    
    return if $id ne 'listLabels1';
    
    # Now, for the top list, colour the grid, based on how many labels occur in a given cell
    my %group_richness; # analysis list
    #my $max_value;
    my ($iter, $iter1, $label, $hash);

    my $sorted_model = $selection->get_tree_view()->get_model();
    my $global_model = $self->{labels_model};

    my $tree = $self->{project}->getSelectedPhylogeny;
    my @phylogeny_colour_nodes;

    my $bd = $self->{base_ref};

    foreach my $path (@paths) {

        # don't know why all this is needed (gtk bug?)
        $iter  = $sorted_model->get_iter($path);
        $iter1 = $sorted_model->convert_iter_to_child_iter($iter);
        $label = $global_model->get($iter1, LABELS_MODEL_NAME);

        # find phylogeny nodes to colour
        if (defined $tree) {
            #  not all will match
            eval {
                my $node_ref = $tree->get_node_ref (node => $label);
                if (defined $node_ref) {
                    push @phylogeny_colour_nodes, $node_ref;
                }
            }
        }
        
        #FIXME: This copies the hash (???recheck???) - not very fast...
        #my %hash = $self->{base_ref}->get_groups_with_label_as_hash(label => $label);
        #  SWL - just use a ref.  Unless Eugene was thinking of what the sub does...
        my $hash = $bd->get_groups_with_label_as_hash (label => $label);

        # groups contains count of how many different labels occur in it
        foreach my $group (keys %$hash) {
            $group_richness{$group}++;
        }
    }
    
    #  richness is the number of labels selected,
    #  which is the number of items in @paths
    my $max_value = scalar @paths;

    my $grid = $self->{grid};
    my $colour_func = sub {
        my $elt = shift;
        my $val = $group_richness{$elt};
        return if ! $val;
        return $grid->getColour($val, 0, $max_value);
    };

    $grid->colour($colour_func);
    $grid->setLegendMinMax(0, $max_value);

    if (defined $tree) {
        #print "[Labels] Recolouring cluster lines\n";
        $self->{dendrogram}->recolourClusterLines(\@phylogeny_colour_nodes);
    }

    # have to run this after everything else is updated
    # otherwise incorrect nodes are selected.
    $self->set_selected_list_cols ($selection, $rowcol);
    
    return;
}

sub set_selected_list_cols {
    my $self   = shift;
    my $selection = shift;
    my $rowcol = shift;

    my $widget_name = $rowcol eq 'rows'
        ? 'listLabels1'
        : 'listLabels2';

    # Select all terminal labels
    #my $model      = $self->{labels_model};
    #my $widget     = $self->{xmlPage}->get_widget($widget_name);
    
    my $sorted_model = $selection->get_tree_view()->get_model();
    my $global_model = $self->{labels_model};

    my $change_col
        = $rowcol eq 'rows'
          ? $labels_model_list1_sel_col
          : $labels_model_list2_sel_col;

    #my $selection_array
    #    = $rowcol eq 'rows'
    #        ? $self->{selected_rows}
    #        : $self->{selected_cols};

    #my %selection_hash;
    #@selection_hash{@$selection_array} = (1) x scalar @$selection_array;

    my $max_iter = $self->{base_ref}-> get_label_count() - 1;
    
    #  get the selection changes
    my @changed_iters;
    foreach my $cell_iter (0..$max_iter) {

        my $iter = $sorted_model->iter_nth_child(undef,$cell_iter);
        
        my $iter1 = $sorted_model->convert_iter_to_child_iter($iter);
        my $orig_label = $global_model->get($iter1, LABELS_MODEL_NAME);
        my $orig_value = $global_model->get($iter1, $change_col);
    
        my $value = $selection->iter_is_selected ($iter) || 0;
        
        if ($value != $orig_value) {
            #print "[Labels] $rowcol : ",
            #      "Changing $orig_label to $value, ",
            #      "Cell iter $cell_iter\n"
            #      #$iter . ' ' . $sorted_iter,
            #      ;
            push (@changed_iters, [$iter1, $value]);
            #$global_model->set($iter1, $change_col, $value);
        }
    }
    
    $self->{ignore_selected_change} = 'listLabels1';
    
    #  and now loop over the iters and change the selection values
    foreach my $array_ref (@changed_iters) {
        $global_model->set($array_ref->[0], $change_col, $array_ref->[1]);
    }

    delete $self->{ignore_selected_change};
    
    #print "[Labels] \n";
    
    return;    
}
    
    
sub onSorted {
    my $self = shift;

    my $xml_page = $self->{xmlPage};
    my $hmodel = $xml_page->get_widget('listLabels1')->get_model();
    my $vmodel = $xml_page->get_widget('listLabels2')->get_model();
    my $model  = $self->{labels_model};
    my $matrix_ref = $self->{matrix_ref};


    my $values_func = sub {
        my ($h, $v) = @_; # integer indices

        my $hiter = $hmodel->iter_nth_child(undef,$h);
        my $viter = $vmodel->iter_nth_child(undef,$v);

        # some bug in gtk2-perl stops me from just doing
        # $hlabel = $hmodel->get($hiter, 0)
        #
        my $hi = $hmodel->convert_iter_to_child_iter($hiter);
        my $vi = $vmodel->convert_iter_to_child_iter($viter);

        my $hlabel = $model->get($hi, 0);
        my $vlabel = $model->get($vi, 0);

        return $matrix_ref->get_value(
            element1 => $hlabel,
            element2 => $vlabel,
        );
    };

    my $label_widget = $self->{xmlPage}->get_widget('lblMatrix');
    my $drawable = $self->{matrix_drawable};
    if ($matrix_ref) {
        if ($drawable) {
            if (! $self->{matrix_drawn}) {
                my $num_values
                    = $self->{base_ref}->get_labels_ref->get_element_count;
                $self->{matrix_grid}->drawMatrix( $num_values );
                $self->{matrix_drawn} = 1;
            }
            $self->{matrix_grid}->setValues($values_func);
            $self->{matrix_grid}->setColouring(
                $matrix_ref->get_min_value,
                $matrix_ref->get_max_value,
            );
        }
        else {
            my $str = '<i>No matrix elements in basedata</i>';
            $label_widget->set_markup($str);
        }
    }
    else {
        # clear matrix
        $self->{matrix_grid}->drawMatrix( 0 );
        $self->{matrix_drawn} = 0;
        $self->{matrix_drawable} = 0;
        my $str = '<i>No selected matrix</i>';
        $label_widget->set_markup($str);
    }

    if (!$drawable) {
        $self->{matrix_grid}->setValues( sub { return undef; } );
        $self->{matrix_grid}->setColouring(0, 0);
        $self->{matrix_grid}->highlight(undef, undef);
    }
    
    return;
}

#  how many labels are in the matrix?  We don't draw it if there are none.
sub get_label_count_in_matrix {
    my $self = shift;
    
    return if !$self->{matrix_ref};
    
    #  should probably use List::MoreUtils::any 
    my %labels      = $self->{base_ref}->get_labels_ref->get_element_hash;
    my %mx_elements = $self->{matrix_ref}->get_elements;
    my $mx_count    = scalar keys %mx_elements;
    delete @mx_elements{keys %labels};
    
    #  if the counts differ then we have commonality
    return $mx_count != scalar keys %mx_elements;
}

##################################################
# Grid events
##################################################

sub onGridHover {
    my $self = shift;
    my $group = shift;

    my $text = defined $group? "Group: $group" : '<b>Groups</b>';
    $self->{xmlPage}->get_widget('label_VL_grid')->set_markup($text);

    my $tree = $self->{project}->getSelectedPhylogeny;
    return if ! defined $tree;

    $self->{dendrogram}->clearHighlights;

    return if ! defined $group;

    # get labels in the group
    my $bd = $self->{base_ref};
    my $labels = $bd->get_labels_in_group_as_hash(group => $group);

    # highlight in the tree
    foreach my $label (keys %$labels) {
        # Might not match some or all nodes
        eval {
            my $node_ref = $tree->get_node_ref (node => $label);
            if ($self->{use_highlight_path}) {
                $self->{dendrogram}->highlightPath($node_ref) ;
            }
        }
    }
    
    return;
}

sub rectCanonicalise {
    my ($rect, ) = @_;
    if ($rect->[0] > $rect->[2]) {
        ($rect->[0], $rect->[2]) = ($rect->[2], $rect->[0]);
    }
    if ($rect->[1] > $rect->[3]) {
        ($rect->[1], $rect->[3]) = ($rect->[3], $rect->[1]);
    }
}

sub rectCentre {
    my ($rect, ) = @_;
    return (($rect->[0] + $rect->[2]) / 2, ($rect->[1] + $rect->[3]) / 2);
}

sub onGridSelect {
    my $self = shift;
    my $groups = shift;
    my $ignore_change = shift;
    my $rect = shift; # [x1, y1, x2, y2]

    print 'Rect: ';
    print Dumper $rect;

    if ($self->{tool} eq 'Select') {
        # convert groups into a hash of labels that are in them
        my %hash;
        my $bd = $self->{base_ref};
        foreach my $group (@$groups) {
            my $hashref = $bd->get_labels_in_group_as_hash(group => $group);
            @hash{ keys %$hashref } = ();
        }

        # Select all terminal labels
        my $xml_page = $self->{xmlPage};
        my $model = $self->{labels_model};
        my $hmodel = $xml_page->get_widget('listLabels1')->get_model();
        my $hselection = $xml_page ->get_widget('listLabels1')->get_selection();

        $hselection->unselect_all();
        my $iter = $hmodel->get_iter_first();
        my $elt;


        $self->{ignore_selected_change} = 'listLabels1';
        while ($iter) {
            my $hi = $hmodel->convert_iter_to_child_iter($iter);
            $elt = $model->get($hi, 0);

            if (exists $hash{ $elt } ) {
                $hselection->select_iter($iter);
            }

            $iter = $hmodel->iter_next($iter);
        }
        if (not $ignore_change) {
            delete $self->{ignore_selected_change};
        }
        onSelectedLabelsChanged($hselection, [$self, 'listLabels1']);
    }
    elsif ($self->{tool} eq 'Zoom') {
        my $grid = $self->{grid};
        my $canvas = $grid->{canvas};
        rectCanonicalise ($rect);

        # Scale
        my $width_px  = $grid->{width_px}; # Viewport/window size
        my $height_px = $grid->{height_px};
        my ($xc, $yc) = $canvas->world_to_window(rectCentre ($rect));
        print "Centre: $xc $yc\n";
        my ($x1, $y1) = $canvas->world_to_window($rect->[0], $rect->[1]);
        my ($x2, $y2) = $canvas->world_to_window($rect->[2], $rect->[3]);
        print "Window Rect: $x1 $x2 $y1 $y2\n";
        my $width_s   = max ($x2 - $x1, 1); # Selected box width
        my $height_s  = max ($y2 - $y1, 1); # Avoid div by 0

        # Special case: If the rect is tiny, the user probably just clicked
        # and released. Do something sensible, like just double the zoom level.
        if ($width_s <= 2 || $height_s <= 2) {
            $width_s = $width_px / 2;
            $height_s = $height_px / 2;
            ($rect->[0], $rect->[1]) = $canvas->window_to_world(
                    $xc - $width_s / 2, $yc - $height_s / 2);
            ($rect->[2], $rect->[3]) = $canvas->window_to_world(
                    $xc + $width_s / 2, $yc + $height_s / 2);
        }

        my $oppu = $canvas->get_pixels_per_unit;
        print "Old PPU: $oppu\n";
        my $ratio = min ($width_px / $width_s, $height_px / $height_s);
        my $ppu = $oppu * $ratio;
        print "New PPU: $ppu\n";
        $canvas->set_pixels_per_unit($ppu);


        # Now pan so that the selection is centered. There are two cases.
        # +------------------------------------------+
        # |                +-----+                   |
        # |                |     |                   |
        # |                |     |                   |
        # |                +-----+                   |
        # +------------------------------------------+
        # or
        # +------------------------------------------+
        # |                                          |
        # |                                          |
        # |+----------------------------------------+|
        # ||                                        ||
        # |+----------------------------------------+|
        # |                                          |
        # |                                          |
        # +------------------------------------------+
        # We can cover both if we expand rect along both axes until it is
        # the same aspect ratio as the window. (One axis will not change).
        my $window_aspect = $width_px / $height_px;
        my $rect_aspect = ($rect->[2] - $rect->[0]) / ($rect->[3] - $rect->[1]);
        if ($rect_aspect > $window_aspect) {
            # 2nd case illustrated above. We need to change the height.
            my $mid = ($rect->[1] + $rect->[3]) / 2;
            my $width = $rect->[2] - $rect->[0];
            $rect->[1] = $mid - 0.5 * $width / $window_aspect;
            $rect->[3] = $mid + 0.5 * $width / $window_aspect;
        }
        else {
            # 1st case illustracted above. We need to change the width.
            my $mid = ($rect->[0] + $rect->[2]) / 2;
            my $height = $rect->[3] - $rect->[1];
            $rect->[0] = $mid - 0.5 * $height * $window_aspect;
            $rect->[2] = $mid + 0.5 * $height * $window_aspect;
        }

        # Apply and pan
        $grid->postZoom;
        $canvas->scroll_to($canvas->w2c(
                $rect->[0], $rect->[1]));
        $grid->updateScrollbars;
    }

    return;
}

sub onGridClick {
    my $self = shift;

    if ($self->{tool} eq 'ZoomOut') {
        $self->{grid}->zoomOut();
    }
    elsif ($self->{tool} eq 'ZoomFit') {
        $self->{grid}->zoomFit();
    }
}

##################################################
# Phylogeny events
##################################################

sub onPhylogenyPlotModeChanged {
    my ($self, $combo) = @_;

    my $xml_page = $self->{xmlPage};

    my %names_and_strings = (
        phylogeny_plot_depth          => 'depth',
        phylogeny_plot_length         => 'length',
        #phylogeny_plot_range_weighted => 'range_weighted',
    );

    my $mode_string;
    while (my ($name, $string) = each %names_and_strings) {
        my $widget = $xml_page->get_widget($name);
        if ($widget->get_active) {
            $mode_string = $string;
            last;
        }
    }

    die "[Labels tab] - onPhylogenyPlotModeChanged - undefined mode"
      if !defined $mode_string;

    print "[Labels tab] Changing mode to $mode_string\n";
    $self->{plot_mode} = $mode_string;
    $self->{dendrogram}->setPlotMode($mode_string); # the menubar should be disabled if no tree is loaded

    return;
}

# Called by dendrogram when user hovers over a node
sub onPhylogenyHighlight {
    my $self = shift;
    my $node = shift;

    my $terminal_elements = (defined $node) ? $node->get_terminal_elements : {};

    # Hash of groups that have the selected labels
    my %groups;
    my ($iter, $label, $hash);

    my $bd = $self->{base_ref};
    foreach my $label (keys %$terminal_elements) {
        my $containing = $bd->get_groups_with_label_as_hash(label => $label);
        if ($containing) {
            @groups{keys %$containing} = values %$containing;
        }
    }

    $self->{grid}->markIfExists( \%groups, 'circle' );
    
    if (defined $node) {
        my $text = 'Node: ' . $node->get_name;
        $self->{xmlPage}->get_widget('label_VL_tree')->set_markup($text);
    }
    
    return;
}

sub onPhylogenyClick {
    my $self = shift;
    my $node_ref = shift;
    my $terminal_elements = (defined $node_ref) ? $node_ref->get_terminal_elements : {};

    # Select all terminal labels
    my $model      = $self->{labels_model};
    my $hmodel     = $self->{xmlPage}->get_widget('listLabels1')->get_model();
    my $hselection = $self->{xmlPage}->get_widget('listLabels1')->get_selection();

    $hselection->unselect_all();
    my $iter = $hmodel->get_iter_first();
    my $elt;

    $self->{ignore_selected_change} = 'listLabels1';
    while ($iter) {
        my $hi = $hmodel->convert_iter_to_child_iter($iter);
        $elt = $model->get($hi, 0);
        #print "[onPhylogenyClick] selected: $elt\n";

        if (exists $terminal_elements->{ $elt } ) {
            $hselection->select_iter($iter);
        }

        $iter = $hmodel->iter_next($iter);
    }
    delete $self->{ignore_selected_change};
    onSelectedLabelsChanged($hselection, [$self, 'listLabels1']);

    # Remove the hover marks
    $self->{grid}->markIfExists( {}, 'circle' );
    
    return;
}

sub onPhylogenyPopup {
    my $self = shift;
    my $node_ref = shift;
    my $basedata_ref = $self->{base_ref};
    my ($sources, $default_source) = getSourcesForNode($node_ref, $basedata_ref);
    Biodiverse::GUI::Popup::showPopup($node_ref->get_name, $sources, $default_source);
    
    return;
}

sub on_use_highlight_path_changed {
    my $self = shift;
    
    #  set to the complement
    $self->{use_highlight_path} = not $self->{use_highlight_path};  
    
    #  clear any highlights
    if ($self->{dendrogram} and not $self->{use_highlight_path}) {
        $self->{dendrogram}->clearHighlights;
    }
    
    return;
}

sub getSourcesForNode {
    my $node_ref = shift;
    my $basedata_ref = shift;
    my %sources;
    #print Data::Dumper::Dumper($node_ref->get_value_keys);
    $sources{'Labels'} = sub { showPhylogenyLabels(@_, $node_ref); };
    $sources{'Groups'} = sub { showPhylogenyGroups(@_, $node_ref, $basedata_ref); };

    # Custom lists - getValues() - all lists in node's $self
    # FIXME: try to merge with CellPopup::showOutputList
    #my @lists = $node_ref->get_value_keys;
    my @lists = $node_ref->get_list_names;
    foreach my $name (@lists) {
        next if not defined $name;
        next if $name =~ /^_/; # leading underscore marks internal list

        #print "[Labels] Phylogenies: adding custom list $name\n";
        $sources{$name} = sub { showList(@_, $node_ref, $name); };
    }

    return (\%sources, 'Labels (cluster)'); # return a default too
}

# Called by popup dialog
# Shows a custom list
# FIXME: duplicates function in Clustering.pm
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
            $model->set($iter,    0,$elt ,  1,'');
        }
    }
    elsif (not ref($ref)) {
        $iter = $model->append;
        $model->set($iter,    0, $ref,  1,'');
    }

    $popup->setValueColumn(1);
    $popup->setListModel($model);
    
    return;
}

# Called by popup dialog
# Shows the labels for all elements under given node
sub showPhylogenyGroups {
    my $popup = shift;
    my $node_ref = shift;
    my $basedata_ref = shift;

    # Get terminal elements
    my $elements = $node_ref->get_terminal_elements;

    # For each element, get its groups and put into %total_groups
    my %total_groups;
    foreach my $element (sort keys %{$elements}) {
        my @groups = $basedata_ref->get_groups_with_label_as_hash(label => $element);
        if ($#groups > 0) {
            my %groups = @groups;
            @total_groups{keys %groups} = undef;
        }
    }

    # Add each label into the model
    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::String');
    foreach my $label (sort keys %total_groups) {
        my $iter = $model->append;
        $model->set($iter, 0, $label, 1, "");
    }

    $popup->setListModel($model);
    $popup->setValueColumn(1);
    
    return;
}

# Called by popup dialog
# Shows all elements under given node
sub showPhylogenyLabels {
    my $popup = shift;
    my $node_ref = shift;

    my $elements = $node_ref->get_terminal_elements;
    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::Int');

    foreach my $element (sort keys %{$elements}) {
        my $count = $elements->{$element};
        my $iter = $model->append;
        $model->set($iter, 0,$element,  1, $count);
    }

    $popup->setListModel($model);
    $popup->setValueColumn(1);
    
    return;
}

##################################################
# Matrix Events (hover, click)
##################################################

sub onMatrixHover {
    my $self = shift;
    my ($h, $v) = @_; # integer indices

    my $hmodel = $self->{xmlPage}->get_widget('listLabels1')->get_model();
    my $vmodel = $self->{xmlPage}->get_widget('listLabels2')->get_model();

    my ($hiter, $viter) = ($hmodel->iter_nth_child(undef,$h), $vmodel->iter_nth_child(undef,$v));

    # some bug in gtk2-perl stops me from just doing $hlabel = $hmodel->get($hiter, 0)
    #
    my ($hi, $vi) = ($hmodel->convert_iter_to_child_iter($hiter), $vmodel->convert_iter_to_child_iter($viter));

    my $model = $self->{labels_model};
    my $hlabel = $model->get($hi, 0);
    my $vlabel = $model->get($vi, 0);

    my $str;
    my $matrix_ref = $self->{matrix_ref};

    if (not $matrix_ref) {
        $str = "<b>Matrix</b>: none selected";
    }
    elsif ($matrix_ref->element_pair_exists(element1 => $hlabel, element2 => $vlabel) == 0) {
        $str = "<b>Matrix</b> ($hlabel, $vlabel): not in matrix";
    }
    else {
        my $value = $matrix_ref->get_value(element1 => $hlabel, element2 => $vlabel);
        $str = sprintf ("<b>Matrix</b> ($hlabel, $vlabel): %.4f", $value);
    }

    $self->{xmlPage}->get_widget('lblMatrix')->set_markup($str);

    return;
}

sub onMatrixClicked {
    my $self = shift;
    my ($h_start, $h_end, $v_start, $v_end) = @_;

    #print "horez=$h_start-$h_end vert=$v_start-$v_end\n";

    $h_start = Gtk2::TreePath->new_from_indices($h_start);
    $h_end   = Gtk2::TreePath->new_from_indices($h_end);
    $v_start = Gtk2::TreePath->new_from_indices($v_start);
    $v_end   = Gtk2::TreePath->new_from_indices($v_end);

    my $hlist = $self->{xmlPage}->get_widget('listLabels1');
    my $vlist = $self->{xmlPage}->get_widget('listLabels2');

    my $hsel = $hlist->get_selection;
    my $vsel = $vlist->get_selection;

    $hsel->unselect_all;
    $vsel->unselect_all;

    $hsel->select_range($h_start, $h_end);
    $vsel->select_range($v_start, $v_end);

    $hlist->scroll_to_cell( $h_start );
    $vlist->scroll_to_cell( $v_start );
    
    return;
}

##################################################
# Misc
##################################################

sub getType {
    return 'labels';
}

sub remove {
    my $self = shift;
    $self->{grid}->destroy();
    $self->{notebook}->remove_page( $self->getPageIndex );
    $self->{project}->deleteSelectionCallback('matrix', $self->{matrix_callback});
    $self->{project}->deleteSelectionCallback('phylogeny', $self->{phylogeny_callback});
    
    return;
}

my %drag_modes = (
    Select  => 'select',
    Pan     => 'pan',
    Zoom    => 'select',
    ZoomOut => 'click',
    ZoomFit => 'click',
);

sub choose_tool {
    my $self = shift;
    my ($tool, ) = @_;

    my $old_tool = $self->{tool};

    if ($old_tool) {
        my $widget = $self->{xmlPage}->get_widget("btn${old_tool}Tool");
        $self->{ignore_tool_click} = 1;
        $widget->set_active($old_tool eq $tool);
        $self->{ignore_tool_click} = 0;
    }

    $self->{tool} = $tool;

    $self->{grid}->{drag_mode} = $drag_modes{$tool};
}

# Called from GTK
sub onSelectTool {
    my $self = shift;
    return if $self->{ignore_tool_click};
    $self->choose_tool('Select');
}

sub onPanTool {
    my $self = shift;
    return if $self->{ignore_tool_click};
    $self->choose_tool('Pan');
}

sub onZoomTool {
    my $self = shift;
    return if $self->{ignore_tool_click};
    $self->choose_tool('Zoom');
}

sub onZoomOutTool {
    my $self = shift;
    return if $self->{ignore_tool_click};
    $self->choose_tool('ZoomOut');
}

sub onZoomFitTool {
    my $self = shift;
    return if $self->{ignore_tool_click};
    $self->choose_tool('ZoomFit');
}

sub onOptionsTool {
    my $self = shift;
    # Not really a tool, but a popup menu.

    my $grid_dummy_item = Gtk2::MenuItem->new('Grid');
    $grid_dummy_item->set_sensitive(0);

    my $overlays_item = Gtk2::MenuItem->new('_Overlays');
    $overlays_item->signal_connect_swapped(activate => \&onOverlays, $self);

    my $popup_menu = Gtk2::Menu->new();
    $popup_menu->append($grid_dummy_item);
    $popup_menu->append($overlays_item);
    $popup_menu->show_all();
    $popup_menu->popup(undef, undef, undef, undef, 0, 0);
}

sub onZoomIn {
    my $grid = shift;
    $grid->zoomIn();
    
    return;
}

sub onZoomOut {
    my $grid = shift;
    $grid->zoomOut();
    
    return;
}

sub onZoomFit {
    my $grid = shift;
    $grid->zoomFit();
    
    return;
}

sub onOverlays {
    my $self = shift;
    my $button = shift;

    Biodiverse::GUI::Overlays::showDialog( $self->{grid} );
    
    return;
}

##################################################
# Managing that vertical pane
##################################################

# Sets the vertical pane's position (0->all the way down | 1->fully up)
sub setPane {
    my $self = shift;
    my $pos = shift;
    my $id = shift;

    my $pane = $self->{xmlPage}->get_widget($id);
    my $maxPos = $pane->get('max-position');
    $pane->set_position( $maxPos * $pos );
    #print "[Labels tab] Updating pane $id: maxPos = $maxPos, pos = $pos\n";
    
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
        \&Biodiverse::GUI::Tabs::Labels::setPaneSignal,
        [$self, $id],
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

    # Queue resize of other panes that depend on this one to get their maximum size
    if ($id eq 'hpaneLabelsTop') {
        $self->queueSetPane(0.5, 'vpaneLists');
    }
    elsif ($id eq 'hpaneLabelsBottom') {
        $self->queueSetPane(1, 'vpanePhylogeny');
    }

    $self->setPane( $self->{"setPanePos$id"}, $id );
    $pane->signal_handler_disconnect( $self->{"setPaneSignalID$id"} );
    delete $self->{"setPanePos$id"};
    delete $self->{"setPaneSignalID$id"};
    
    return;
}

sub numerically {$a <=> $b};


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
