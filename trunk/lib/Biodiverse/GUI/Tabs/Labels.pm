package Biodiverse::GUI::Tabs::Labels;
use strict;
use warnings;

use English ( -no_match_vars );

use Gtk2;
use Carp;
use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::MatrixGrid;
use Biodiverse::GUI::Grid;
use Biodiverse::GUI::Project;
use Biodiverse::GUI::Overlays;

our $VERSION = '0.16';

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
    
    my $self = {gui           => Biodiverse::GUI::GUIManager->instance(),
                selected_rows => [],
                selected_cols => [],
                };
    $self->{project} = $self->{gui}->getProject();
    bless $self, $class;
    
    $self -> set_default_params;


    # Load _new_ widgets from glade 
    # (we can have many Analysis tabs open, for example. These have a different object/widgets)
    $self->{xmlPage}  = Gtk2::GladeXML->new($self->{gui}->getGladeFile, 'vpaneLabels');
    $self->{xmlLabel} = Gtk2::GladeXML->new($self->{gui}->getGladeFile, 'hboxLabelsLabel');

    my $page  = $self->{xmlPage}->get_widget('vpaneLabels');
    my $label = $self->{xmlLabel}->get_widget('hboxLabelsLabel');

    # Add to notebook
    $self->{notebook} = $self->{gui}->getNotebook();
    $self->{page_index} = $self->{notebook}->append_page($page, $label);
    $self->{gui}->addTab($self);

    # Get basename
    # Something has to be selected - otherwise menu item is disabled
    $self->{base_ref} = $self->{project}->getSelectedBaseData();

    # Initialise widgets
    my $label_widget = $self->{xmlLabel}->get_widget('lblLabelsName');
    $label_widget->set_text("Labels - " . $self->{base_ref}->get_param('NAME'));
    $self->{label_widget} = $label_widget;
    

    $self->makeLabelsModel();
    $self->initList('listLabels1');
    $self->initList('listLabels2');

    if (! $self->initGrid()) {       #  close if user cancelled during display
        $self -> onClose;
        croak "User cancelled grid initialisation, closing\n";
    }  

    if (! $self->initMatrixGrid()) { #  close if user cancelled during display
        $self -> onClose;
        croak "User cancelled matrix initialisation, closing\n";
    }
    # Register callbacks when selected matrix is changed
    $self->{matrix_callback}    = sub { $self->onSelectedMatrixChanged();    };
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
    $self->{xmlLabel}->get_widget('btnLabelsClose')->signal_connect_swapped(clicked => \&onClose, $self);
    
    
    #  CONVERT THIS TO A HASH BASED LOOP, as per Clustering.pm
    $self->{xmlPage}->get_widget('btnZoomInVL')->signal_connect_swapped(clicked => \&onZoomIn, $self->{grid});
    $self->{xmlPage}->get_widget('btnZoomOutVL')->signal_connect_swapped(clicked => \&onZoomOut, $self->{grid});
    $self->{xmlPage}->get_widget('btnZoomFitVL')->signal_connect_swapped(clicked => \&onZoomFit, $self->{grid});
    $self->{xmlPage}->get_widget('btnMatrixZoomIn')->signal_connect_swapped(clicked => \&onZoomIn, $self->{matrix_grid});
    $self->{xmlPage}->get_widget('btnMatrixZoomOut')->signal_connect_swapped(clicked => \&onZoomOut, $self->{matrix_grid});
    $self->{xmlPage}->get_widget('btnMatrixZoomFit')->signal_connect_swapped(clicked => \&onZoomFit, $self->{matrix_grid});
    $self->{xmlPage}->get_widget('btnPhylogenyZoomIn')->signal_connect_swapped(clicked => \&onZoomIn, $self->{dendrogram});
    $self->{xmlPage}->get_widget('btnPhylogenyZoomOut')->signal_connect_swapped(clicked => \&onZoomOut, $self->{dendrogram});
    $self->{xmlPage}->get_widget('btnPhylogenyZoomFit')->signal_connect_swapped(clicked => \&onZoomFit, $self->{dendrogram});
    $self->{xmlPage}->get_widget('btnOverlaysVL')->signal_connect_swapped(clicked => \&onOverlays, $self);
    $self->{xmlPage}->get_widget('phylogeny_plot_length')->signal_connect_swapped('toggled' => \&onPhylogenyPlotModeChanged, $self);
    $self->{xmlPage}->get_widget('highlight_groups_on_map_labels_tab')->signal_connect_swapped('toggled' => \&on_highlight_groups_on_map_changed, $self);
    $self->{xmlPage}->get_widget('use_highlight_path_changed1')->signal_connect_swapped(toggled => \&on_use_highlight_path_changed, $self);
    
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
    
    $self->{grid} = Biodiverse::GUI::Grid->new(
        $frame,
        $hscroll,
        $vscroll,
        0,
        0,
        $hover_closure,
        $click_closure,
        $select_closure,
    );

    eval {$self->{grid}->setBaseStruct($self->{base_ref} -> get_groups_ref)};
    if ($EVAL_ERROR) {
        $self->{gui} -> report_error ($EVAL_ERROR);
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
        $click_closure
    );
    
    #  cannot colour more than one in a phylogeny
    $self->{dendrogram} -> setNumClusters (1);
    
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
    $self -> addColumn ($tree, 'Label', $i);
    foreach my $column (@$stats_metadata) {
        $i++;
        my ($key, $value) = %$column;
        my $column_name = Glib::Markup::escape_text (ucfirst lc $key);
        $self -> addColumn ($tree, $column_name, $i);
    }
    $self -> addColumn ($tree, $selected_list1_name, ++$i);
    $self -> addColumn ($tree, $selected_list2_name, ++$i);
    
    # Set model to a wrapper that lets this list have independent sorting
    my $wrapper_model = Gtk2::TreeModelSort->new( $self->{labels_model});
    $tree->set_model( $wrapper_model );

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

    #my $basestats_indices = $labels_ref -> get_base_stats (get_args => 1);
    my $basestats_indices = $labels_ref -> get_args (sub => 'get_base_stats');
    
    #my $properties = $base_ref->get_label_property_keys_as_args;

    my @column_order;
    
    #  the selection cols
    my @selection_cols = (
        {$selected_list1_name => 'Int'},
        {$selected_list2_name => 'Int'},
    );
    
    my @types = ('Glib::String');
    #my $i = 0;
    foreach my $column (@$basestats_indices, @selection_cols) {
        #my ($key, $value) = %{$basestats_indices->[$i]};
        my ($key, $value) = %{$column};
        #if ($value eq 'Int') {
        #    $value = 'Uint';  #  increase the precision for the display
        #}
        push @types, 'Glib::' . $value;
        push @column_order, $key;
        #$i++;
    }

    $self->{labels_model} = Gtk2::ListStore->new(@types);
    my $model = $self->{labels_model};

    my @labels = $base_ref -> get_labels();
    

    foreach my $label (sort @labels) {
        my $iter = $model->append();
        $model->set($iter, 0, $label);

        #  set the values - selection cols will be undef
        my %stats = $labels_ref -> get_base_stats (element => $label);
#print $label . " " . Data::Dumper::Dumper(\%stats) . "\n";
        my $i = 1;
        foreach my $column (@column_order) {
            $model -> set ($iter, $i, defined $stats{$column} ? $stats{$column} : -99999);
            $i++;
        }
    }
    
    $labels_model_list1_sel_col = scalar @column_order - 1;
    $labels_model_list2_sel_col = scalar @column_order;

    return;
}

sub onSelectedPhylogenyChanged {
    my $self = shift;

    # phylogenies
    my $phylogeny = $self->{project}->getSelectedPhylogeny;

    my $plot_menu = $self->{xmlPage}->get_widget('menubar_phylogeny_plot_mode');
    $self->{dendrogram} -> clear;
    if ($phylogeny) {
        $self->{dendrogram} -> setCluster($phylogeny, 'length');  #  now storing tree objects directly
        $plot_menu->set_sensitive(1);
    }
    else {
        #$self->{dendrogram} -> clear;
        $plot_menu->set_sensitive(0);
    }

    return;
}

sub on_highlight_groups_on_map_changed {
    my $self = shift;
    $self->{dendrogram} -> set_use_highlight_func;
    
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
    my $col  = $list -> get_column ($labels_model_list2_sel_col);
    
    if (! defined $matrix_ref) {
        $list_window -> hide;     #  hide the second list
        $col -> set_visible (0);  #  hide the list 2 selection
                                  #    col from list 1
    }
    else {
        $list_window -> show;
        $col -> set_visible (1);
    }

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
        $self -> set_selected_list_cols ($selection, $rowcol);
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
                my $node_ref = $tree -> get_node_ref (node => $label);
                if (defined $node_ref) {
                    push @phylogeny_colour_nodes, $node_ref;
                }
            }
        }
        
        #FIXME: This copies the hash (???recheck???) - not very fast...
        #my %hash = $self->{base_ref}->get_groups_with_label_as_hash(label => $label);
        #  SWL - just use a ref.  Unless Eugene was thinking of what the sub does...
        my $hash = $bd -> get_groups_with_label_as_hash (label => $label);

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
    $self -> set_selected_list_cols ($selection, $rowcol);
    
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
    
        my $value = $selection -> iter_is_selected ($iter) || 0;
        
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

    if ($matrix_ref) {
        if ($self->{matrix_drawn} == 0) {
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
        # clear matrix
        $self->{matrix_grid}->drawMatrix( 0 );
        $self->{matrix_drawn} = 0;

        $self->{matrix_grid}->setValues( sub { return undef; } );
        $self->{matrix_grid}->setColouring(0, 0);
        $self->{matrix_grid}->highlight(undef, undef);
    }
    
    return;
}

##################################################
# Grid events
##################################################

sub onGridHover {
    my $self = shift;
    my $group = shift;

    my $tree = $self->{project}->getSelectedPhylogeny;
    return if not defined $tree;

    $self->{dendrogram}->clearHighlights;
    
    return undef if ! defined $group;
    
    # get labels in the group
    my $bd = $self->{base_ref};
    my $labels = $bd->get_labels_in_group_as_hash(group => $group);

    # highlight in the tree
    foreach my $label (keys %$labels) {
        # Might not match some or all nodes
        eval {
            my $node_ref = $tree -> get_node_ref (node => $label);
            if ($self->{use_highlight_path}) {
                $self->{dendrogram}->highlightPath($node_ref) ;
            }
        }
    }
    my $text = "Group: $group";
    $self->{xmlPage}->get_widget('label_VL_grid')->set_markup($text);
    
    return;
}

sub onGridSelect {
    my $self = shift;
    my $groups = shift;
    my $ignore_change = shift;
    

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
    
    return;
}

##################################################
# Phylogeny events
##################################################

sub onPhylogenyPlotModeChanged {
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
        die "[Labels tab] - onPhylogenyPlotModeChanged - invalid mode $mode";
    }

    print "[Labels tab] Changing mode to $mode\n";
    $self->{plot_mode} = $mode;
    $self->{dendrogram}->setPlotMode($mode); # the menubar should be disabled if no tree is loaded
    
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
    my $ref = $node_ref->get_list_ref ('list' => $name);

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

#sub onClose {
#    my $self = shift;
#    $self->{gui}->removeTab($self);
#    
#    return;
#}

sub remove {
    my $self = shift;
    $self->{grid}->destroy();
    $self->{notebook}->remove_page( $self->{page_index} );
    $self->{project}->deleteSelectionCallback('matrix', $self->{matrix_callback});
    $self->{project}->deleteSelectionCallback('phylogeny', $self->{phylogeny_callback});
    
    return;
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

# Sets the vertical pane's position (0 -> all the way down | 1 -> fully up)
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
