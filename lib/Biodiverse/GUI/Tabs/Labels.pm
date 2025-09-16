package Biodiverse::GUI::Tabs::Labels;
use 5.010;
use strict;
use warnings;

use English ( -no_match_vars );

use experimental qw/refaliasing declared_refs for_list/;

#use Data::Dumper;
use Sort::Key::Natural qw /natsort mkkey_natural/;

use List::MoreUtils qw /firstidx any minmax/;
use List::Util qw /max/;
use Scalar::Util qw /weaken looks_like_number/;
use Ref::Util qw /is_ref is_arrayref is_hashref/;
use POSIX qw /floor ceil/;
use Biodiverse::Utilities qw/sort_list_with_tree_names_aa/;

use HTML::QuickTable;

use Gtk3;
use Carp;
use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;
use Biodiverse::GUI::Overlays;
use Biodiverse::GUI::Canvas::Matrix;
use Biodiverse::GUI::Canvas::Grid;
use Biodiverse::GUI::Canvas::Tree;

use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';

our $VERSION = '4.99_012';

use parent qw {
    Biodiverse::GUI::Tabs::Tab
    Biodiverse::Common
};

use constant LABELS_MODEL_NAME          => 0;
use constant LABELS_MODEL_SAMPLE_COUNT  => 1;
use constant LABELS_MODEL_VARIETY       => 2;
use constant LABELS_MODEL_REDUNDANCY    => 3;
#use constant LABELS_MODEL_LIST1_SEL     => 4;
#use constant LABELS_MODEL_LIST2_SEL     => 5;
my $labels_model_list1_sel_col;  # these are set in sub make_labels_model
my $labels_model_list2_sel_col;

use constant CELL_WHITE   => Gtk3::Gdk::RGBA::parse('white');
use constant COLOUR_BLACK => Gtk3::Gdk::RGBA::parse('black');
use constant COLOUR_GREY  => Gtk3::Gdk::RGBA::parse('rgb(170,170,170)');

my $selected_list1_name = 'Selected';
my $selected_list2_name = 'Col selected';

use constant TYPE_TEXT => 1;
use constant TYPE_HTML => 2; # some programs want HTML tables

#  The row updates in set_selected_list_cols run quadratically
#  for later values in the list.
my $MAX_ROW_COUNT_FOR_SEL_UPDATES
    = looks_like_number($ENV{BD_MAX_ROW_COUNT_FOR_UPDATES})
    ? $ENV{BD_MAX_ROW_COUNT_FOR_UPDATES}
    : 10000;

##################################################
# Initialisation
##################################################

sub new {
    my $class = shift;

    my $gui = Biodiverse::GUI::GUIManager->instance;
    if (not $gui->get_project->get_selected_base_data()) {
        my $response = Biodiverse::GUI::YesNoCancel->run({
            header      => "There is no basedata to show",
            yes_is_ok   => 1,
            hide_cancel => 1,
            hide_no     => 1,
        });
        return;
    }
    
    my $self = {
        gui           => $gui,
        selected_rows => [],
        selected_cols => [],
    };
    $self->{project} = $self->{gui}->get_project();
    bless $self, $class;

    $self->set_default_params;


    # Load _new_ widgets from Gtk Builder
    # (we can have many Analysis tabs open, for example. These have a different object/widgets)
    $self->{xmlPage} = Gtk3::Builder->new();
    $self->{xmlPage}->add_from_file($self->{gui}->get_gtk_ui_file('hboxLabelsPage.ui'));
    $self->{xmlLabel} = Gtk3::Builder->new();
    $self->{xmlLabel}->add_from_file($self->{gui}->get_gtk_ui_file('hboxLabelsLabel.ui'));

    my $page  = $self->get_xmlpage_object('hboxLabelsPage');
    my $label = $self->{xmlLabel}->get_object('hboxLabelsLabel');
    my $tab_menu_label = Gtk3::Label->new('Labels tab');
    $self->{tab_menu_label} = $tab_menu_label;

    # Add to notebook
    $self->add_to_notebook (
        page         => $page,
        label        => $label,
        label_widget => $tab_menu_label,
    );

    # Get basename
    # Something has to be selected - otherwise menu item is disabled
    $self->{base_ref} = $self->{project}->get_selected_base_data();

    # Initialise widgets
    my $label_widget = $self->{xmlLabel}->get_object('lblLabelsName');
    my $text = 'Labels - ' . $self->{base_ref}->get_param('NAME');
    $label_widget->set_text($text);
    $self->{label_widget} = $label_widget;
    $self->{tab_menu_label}->set_text($text);

    $self->set_label_widget_tooltip;

    $self->make_labels_model();
    $self->init_list('listLabels1');
    $self->init_list('listLabels2');

    # "open up" the panes
    #  need to do this before displaying the dendrogram
    #  as a resize triggers a complete redraw
    #  (something to be fixed sometime)
    $self->queue_set_pane(0.5, 'hpaneLabelsTop');
    $self->queue_set_pane(0.5, 'hpaneLabelsBottom');
    $self->queue_set_pane(0.5, 'vpaneLabels');
    # vpaneLists is done after hpaneLabelsTop, since this panel isn't able to get
    # its max size before hpaneLabelsTop is resized
    
    if (! $self->init_grid()) {       #  close if user cancelled during display
        $self->on_close;
        croak "User cancelled grid initialisation, closing\n";
    }

    if (! $self->init_matrix_grid()) { #  close if user cancelled during display
        $self->on_close;
        croak "User cancelled matrix initialisation, closing\n";
    }
    # Register callbacks when selected matrix is changed
    $self->{matrix_callback}    = sub { $self->on_selected_matrix_changed(); };
    $self->{project}->register_selection_callback(
        'matrix',
        $self->{matrix_callback},
    );
    $self->on_selected_matrix_changed();

    #  this won't take long, so no cancel handler
    $self->init_dendrogram();
    # Register callbacks when selected phylogeny is changed
    $self->{phylogeny_callback} = sub { $self->on_selected_phylogeny_changed(); };
    $self->{project}->register_selection_callback(
        'phylogeny',
        $self->{phylogeny_callback},
    );
    $self->on_selected_phylogeny_changed();


    # Panes will modify this to keep track of which one the mouse is currently
    # over
    $self->{active_pane} = '';

    # Connect signals

    $self->{xmlLabel}->get_object('btnLabelsClose')->signal_connect_swapped(clicked => \&on_close, $self);

    # Connect signals for new side tool chooser
    my $sig_clicked = sub {
        my ($widget_name, $f) = @_;
        my $widget = $self->get_xmlpage_object($widget_name)
            // warn "Cannot find widget $widget_name";
        $widget->signal_connect_swapped(
            clicked => $f, $self
        );
    };

    $sig_clicked->('btnSelectToolVL',  \&on_select_tool);
    $sig_clicked->('btnPanToolVL',     \&on_pan_tool);
    $sig_clicked->('btnZoomInToolVL',  \&on_zoom_in_tool);
    $sig_clicked->('btnZoomOutToolVL', \&on_zoom_out_tool);
    $sig_clicked->('btnZoomFitToolVL', \&on_zoom_fit_tool);

    $self->get_xmlpage_object('menuitem_labels_overlays')->signal_connect_swapped(activate => \&on_overlays, $self);

    $self->get_xmlpage_object('btnSelectToolVL')->set_active(1);

    $self->get_xmlpage_object('menuitem_labels_show_legend')->signal_connect_swapped(
        toggled => \&on_show_hide_legend,
        $self
    );

    foreach my $type_option (qw /auto linear log/) {
        my $radio_item = 'radiomenuitem_grid_colouring_' . $type_option;
        $self->get_xmlpage_object($radio_item)->signal_connect_swapped(
            toggled => \&on_grid_colour_scaling_changed,
            $self,
        );
    }

    my %widgets_and_signals = (
        menuitem_labels_background_colour  => {activate => \&on_set_map_background_colour}
    );

    foreach my ($widget_name, $args) (%widgets_and_signals) {
        my $widget = $self->get_xmlpage_object($widget_name);
        warn "Cannot connect $widget_name\n" if !defined $widget;
        $widget->signal_connect_swapped(
            %$args,
            $self,
        );
    }


        $self->{use_highlight_path} = 1;

    $self->{menubar} = $self->get_xmlpage_object('menubarLabelsOptions');
    $self->update_selection_menu;
    $self->update_export_menu;
    $self->update_tree_menu (output_ref => $self->get_base_ref->get_groups_ref);

    #  trigger a display so the cells are not empty
    on_selected_labels_changed (undef, [$self]);

    say "[GUI] - Loaded tab - Labels";

    return $self;
}

sub get_canvas_list {
    qw /grid dendrogram matrix_grid/;
}

sub init_grid {
    my $self = shift;

    my $frame   = $self->get_xmlpage_object('gridFrameViewLabels');

    my $hover_closure  = sub { $self->on_grid_hover(@_); };
    my $click_closure  = sub {
        Biodiverse::GUI::CellPopup::cell_clicked($_[0], $self->{base_ref});
    };
    my $select_closure = sub { $self->on_grid_select(@_); };
    my $grid_click_closure = sub { $self->on_grid_click(@_); };
    my $end_hover_closure  = sub { $self->on_end_grid_hover(@_); };
    my $right_click_closure = sub {$self->toggle_do_canvas_hover_flag (@_)};

    my $grid = $self->{grid} = Biodiverse::GUI::Canvas::Grid->new(
        frame            => $frame,
        show_legend      => 0,
        show_value       => 0,
        hover_func       => $hover_closure,
        ctl_click_func   => $click_closure,
        select_func      => $select_closure,
        grid_click_func  => $grid_click_closure,
        end_hover_func   => $end_hover_closure,
        right_click_func => $right_click_closure,
    );
    $grid->set_parent_tab($self);

    eval {$grid->set_base_struct($self->{base_ref}->get_groups_ref)};
    if ($EVAL_ERROR) {
        $self->{gui}->report_error ($EVAL_ERROR);
        return;
    }

    $grid->set_legend_mode('Sat');

    $self->warn_if_basedata_has_gt2_axes;

    $frame->show_all;

    return 1;
}

sub init_matrix_grid {
    my $self = shift;

    my $frame   = $self->get_xmlpage_object('matrixFrame');
    my $project = $self->{project};

    my $hover_closure  = sub { $self->on_matrix_hover(@_); };
    my $select_closure = sub { $self->on_matrix_clicked(@_); };
    # my $grid_click_closure = sub { $self->on_matrix_grid_clicked(@_); };

    my $row_labels = $self->get_sorted_labels_from_list_pane(1);
    my $col_labels = $self->get_sorted_labels_from_list_pane(2);

    my $mg = $self->{matrix_grid} = Biodiverse::GUI::Canvas::Matrix->new(
        frame           => $frame,
        hover_func      => $hover_closure,
        select_func     => $select_closure,
        # grid_click_func => $grid_click_closure, #  not used now - was zooming
        row_labels      => $row_labels,
        col_labels      => $col_labels,
        show_legend     => 0,
    );
    $mg->set_parent_tab($self);

    $mg->set_current_matrix($project->get_selected_matrix);

    $frame->show_all;

    return 1;
}

sub get_sorted_labels_from_list_pane {
    my ($self, $list_num) = @_;

    $list_num //= 1;
    croak "Invalid list num $list_num"
        if !($list_num == 1 || $list_num == 2);

    my $list_name = "listLabels$list_num";
    my $model   = $self->get_xmlpage_object($list_name)->get_model();

    my @labels;
    my $iter = $model->get_iter_first;

    while ($iter) {
        my $label = $model->get($iter, 0);  #  first col is label
        push @labels, $label;
        last if !$model->iter_next($iter);
    }

    return wantarray ? @labels : \@labels;
}

# For the phylogeny tree:
sub init_dendrogram {
    my $self = shift;

    my $frame      = $self->get_xmlpage_object('phylogenyFrame');
    my $graph_frame = $self->get_xmlpage_object('phylogenyGraphFrame');

    my $list_combo  = $self->get_xmlpage_object('comboPhylogenyLists');
    my $index_combo = $self->get_xmlpage_object('comboPhylogenyShow');

    my $highlight_closure  = sub { $self->on_phylogeny_highlight(@_); };
    my $end_hover_closure  = sub { $self->on_end_phylogeny_hover(@_); };
    my $ctrl_click_closure = sub { $self->on_phylogeny_popup(@_); };
    my $click_closure      = sub { $self->on_phylogeny_click(@_); };
    # my $select_closure      = sub { $self->on_phylogeny_select(@_); };
    my $right_click_closure = sub {$self->toggle_do_canvas_hover_flag (@_)};

    my $dendro = $self->{dendrogram} = Biodiverse::GUI::Canvas::Tree->new(
        frame                => $frame,
        grid                 => undef,
        list_combo           => $list_combo,
        index_combo          => $index_combo,
        hover_func           => undef,
        end_hover_func       => $end_hover_closure,
        highlight_func       => $highlight_closure,
        ctrl_click_func      => $ctrl_click_closure,
        click_func           => $click_closure,
        # select_func     => $select_closure,
        right_click_func     => $right_click_closure,
        show_legend          => 0,
        max_colours          => 1,
    );
    $dendro->set_parent_tab($self);
    #  cannot colour more than one in a phylogeny
    $dendro->set_num_clusters (1);
    $dendro->init_scree_plot(frame => $graph_frame);

    $dendro->show_all;

    return 1;
}

sub get_current_tree {
    my $self = shift;
    return $self->{project}->get_selected_phylogeny;
}

sub get_tree_menu_items {
    my $self = shift;

    my @menu_items = (
        {
            type     => 'Gtk3::MenuItem',
            label    => 'Tree options:',
            tooltip  => "Options to work with the displayed tree "
                      . "(this is the same as the one selected at "
                      . "the project level)",
        },
        (   map {$self->get_tree_menu_item($_)}
               qw /plot_branches_by
                   highlight_groups_on_map
                   highlight_paths_on_tree
                   separator
                   background_colour
                   set_tree_branch_line_widths
                   separator
                   export_tree
               /
        ),
    );

    return wantarray ? @menu_items : \@menu_items;
}

##################################################
# Labels list
##################################################

sub add_column {
    my $self = shift;
    my %args = @_;

    my $tree     = $args{tree};
    my $title    = $args{title};
    my $model_id = $args{model_id};

    my $col = Gtk3::TreeViewColumn->new();
    my $renderer = Gtk3::CellRendererText->new();
#$title = Glib::Markup::escape_text($title);
#  Double the underscores so they display without acting as hints.
#  Need to find out how to disable that hint setting.
    $title =~ s/_/__/g;
    $col->set_title($title);
    # my $a = $col->get_title;
#$col->set_sizing('fixed');
    $col->pack_start($renderer, 0);
    $col->add_attribute($renderer,  text => $model_id);
    $col->set_sort_column_id($model_id);
    $col->signal_connect_swapped(clicked => \&on_sorted, $self);
#$col->set('autosize' => 'True');
    $col->set (resizable => 1);

    $tree->insert_column($col, -1);

    return;
}

sub init_list {
    my $self = shift;
    my $id   = shift;
    my $tree = $self->get_xmlpage_object($id);


    my @column_names;
    my $labels_ref = $self->{base_ref}->get_labels_ref;
    my $stats_metadata = $labels_ref->get_metadata (sub => 'get_base_stats');
    my $types = $stats_metadata->get_types;
    my @columns;
    my $i = 0;
    $self->add_column (
        tree  => $tree,
        title => 'Label',
        model_id => $i,
    );
    push @column_names, 'Label';
    foreach my $column (@$types) {
        $i++;
        my ($key, $value) = %$column;
        my $column_name = Glib::Markup::escape_text (ucfirst lc $key);
        $self->add_column (
            tree  => $tree,
            title => $column_name,
            model_id => $i,
        );
        push @column_names, $key;
    }
    $self->add_column (
        tree  => $tree,
        title => $selected_list1_name,
        model_id => ++$i,
    );
    $self->add_column (
        tree  => $tree,
        title => $selected_list2_name,
        model_id => ++$i,
    );
    push @column_names, ('Selected', 'Selected_Col');

    # Set model to a wrapper that lets this list have independent sorting
    my $wrapper_model = Gtk3::TreeModelSort->new_with_model ( $self->{labels_model});
    $tree->set_model( $wrapper_model );

    my $sort_func = \&sort_by_column;
    my $start_col = 1;
    if ($self->{base_ref}->labels_are_numeric) {
        $sort_func = \&sort_by_column_numeric_labels;
        $start_col = 0;
    }
    else {
        $wrapper_model->set_sort_func (0, \&sort_label_column);
    }

    #  set a special sort func for all cols (except the labels if not numeric)
    foreach my $col_id ($start_col .. $i) {
        $wrapper_model->set_sort_func ($col_id, $sort_func, [$col_id, $wrapper_model]);
    }

    # Monitor selections
    $tree->get_selection->set_mode('multiple');
    $tree->get_selection->signal_connect(
        changed => \&on_selected_labels_changed,
        [$self, $id],
    );

#$tree->signal_connect_swapped(
#    'start-interactive-search' => \&on_interactive_search,
#    [$self, $id],
#);

    $self->{tree_model_column_names} = \@column_names;

    return;
}

sub sort_label_column {
    my ($liststore, $itera, $iterb) = @_;
        
    return
      mkkey_natural ($liststore->get($itera, 0))
      cmp
      mkkey_natural ($liststore->get($iterb, 0));
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
        || $label_order
          *   (mkkey_natural ($liststore->get($itera, 0))
          cmp mkkey_natural ($liststore->get($iterb, 0)));
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
        || $label_order * ((0+$liststore->get($itera, 0) <=> 0+$liststore->get($iterb, 0)));
}

# Creates a TreeView model of all labels
sub make_labels_model {
    my $self = shift;
    my $params = shift;

    my $base_ref = $self->{base_ref};
    my $labels_ref = $base_ref->get_labels_ref();

    my $basestats_metadata = $labels_ref->get_metadata (sub => 'get_base_stats');

    my @column_order;
    my $label_count = $base_ref->get_label_count;

    say "[Labels tab] Setting up lists for $label_count labels";
    if ($label_count > $MAX_ROW_COUNT_FOR_SEL_UPDATES) {
        my $header = "Number of labels ($label_count) exceeds limit ($MAX_ROW_COUNT_FOR_SEL_UPDATES).\n";
        my $msg    = 'Selection flag column updates have been disabled to avoid slowdowns.';
        say "[Labels] ${header}${msg}";
        #  Tried a popup but it caused errors
        #  Set tooltip instead
        my $widget = $self->get_xmlpage_object('scrolledwindow_labels1');
        my $tt = $widget->get_tooltip_text;
        $widget->set_tooltip_text ("${tt}\n\nNote: ${header}${msg}");
    }

    my @selection_cols = (
        {$selected_list1_name => 'Int'},
        {$selected_list2_name => 'Int'},
    );


    my $label_type = 'Glib::String';

    my @types = ($label_type);
    my $bs_types = $basestats_metadata->get_types;

    foreach my $column (@$bs_types, @selection_cols) {
        my ($key, $value) = %{$column};
        push @types, 'Glib::' . $value;
        push @column_order, $key;
    }

    $self->{labels_model} = Gtk3::ListStore->new(@types);
    my $model = $self->{labels_model};

    my $labels = $base_ref->get_labels();

    my @sorted_labels = $base_ref->labels_are_numeric
        ? sort {$a <=> $b} @$labels
        : natsort @$labels;

    foreach my $label (@sorted_labels) {
        my $iter = $model->append();
        $model->set($iter, 0, $label);

        #  set the values - selection cols will be undef
        my %stats = $labels_ref->get_base_stats (element => $label);

        my $i = 1;
        foreach my $column (@column_order[0..($#column_order-2)]) {
            $model->set ($iter, $i, $stats{$column} // -99999);
            $i++;
        }
        #  now the selection columns (last two)
        $model->set ($iter, $i, $stats{$column_order[-2]} // 0);
        $i++;
        $model->set ($iter, $i, $stats{$column_order[-1]} // 0);
    }

    $labels_model_list1_sel_col = scalar @column_order - 1;
    $labels_model_list2_sel_col = scalar @column_order;

    return;
}

#  variation on
#  http://gtk.10911.n7.nabble.com/Remove-Multiple-Rows-from-Gtk3-ListStore-td66092.html
sub remove_selected_labels_from_list {
    my $self = shift;

    my $treeview1 = $self->get_xmlpage_object('listLabels1');
    my $treeview2 = $self->get_xmlpage_object('listLabels2');

    my $selection = $treeview1->get_selection;
    my ($p, $model) = $selection->get_selected_rows();
    my @paths = $p ? @$p : [];

    my $global_model = $self->{labels_model};

    my $model1 = $treeview1->get_model;
    my $model2 = $treeview2->get_model;

    local $self->{ignore_selection_change} = 1;

    $treeview1->set_model(undef);
    $treeview2->set_model(undef);

    # Convert paths to row references first
    my @rowrefs;
    foreach my $path (@paths) {
        my $treerowreference = Gtk3::TreeRowReference->new ($model1, $path);
        push @rowrefs, $treerowreference;
    }
    
    #  now we delete them
    #  (cannot delete as we go as the paths and iters
    #   are affected by the deletions)
    foreach my $rowref (@rowrefs) {
        my $path = $rowref->get_path;
        next if !defined $path;
        my $iter  = $model1->get_iter($path);
        my $iter1 = $model1->convert_iter_to_child_iter($iter);
        $global_model->remove($iter1);
    }

    $treeview1->set_model ($model1);
    $treeview2->set_model ($model2);

    #  need to update the matrix if it is displayed
    $self->on_selected_matrix_changed (redraw => 1);

    return;
}


sub get_selected_labels {
    my ($self, $list_num) = @_;
    $list_num ||= 1;

    # Get the current selection
    my $selection = $self->get_xmlpage_object("listLabels$list_num")->get_selection();
    my ($p, $model) = $selection->get_selected_rows();
    my @paths = $p ? @$p : [];
    #my @selected = map { ($_->get_indices)[0] } @paths;
    my $sorted_model = $selection->get_tree_view()->get_model();
    my $global_model = $self->{labels_model};

    my @selected_labels;
    foreach my $path (@paths) {
        # don't know why all this is needed (gtk bug?)
        my $iter  = $sorted_model->get_iter($path);
        my $iter1 = $sorted_model->convert_iter_to_child_iter($iter);
        my $label = $global_model->get($iter1, LABELS_MODEL_NAME);
        push @selected_labels, $label;
    }

    return wantarray ? @selected_labels : \@selected_labels;
}

sub get_selected_records {
    my $self = shift;

    # Get the current selection
    my $selection = $self->get_xmlpage_object('listLabels1')->get_selection();
    my ($p, $model) = $selection->get_selected_rows();
    my @paths = $p ? @$p : [];
    #my @selected = map { ($_->get_indices)[0] } @paths;
    my $sorted_model = $selection->get_tree_view()->get_model();
    my $global_model = $self->{labels_model};

    my @selected_records;
    foreach my $path (@paths) {
        # don't know why all this is needed (gtk bug?)
        my $iter  = $sorted_model->get_iter($path);
        my $iter1 = $sorted_model->convert_iter_to_child_iter($iter);
        my @values = map {$_ eq '-99999' ? undef : $_} $global_model->get($iter1);
        push @selected_records, \@values;
    }

    return wantarray ? @selected_records : \@selected_records;
}

sub switch_selection {
    my $self = shift;

    my $treeview1 = $self->get_xmlpage_object('listLabels1');

    my $selection = $treeview1->get_selection;
    my $model1    = $treeview1->get_model;

    $self->{ignore_selection_change} = 1;

    my @p_unselected;
    $model1->foreach (
        sub {
            my ($model, $path, $iter) = @_;
            #we want rows where the list1 selected column is not 1
            my $selected = $model->get($iter, $labels_model_list1_sel_col);
            my $treerowreference = Gtk3::TreeRowReference->new ($model, $path);

            if ($selected != 1) {  #  -99999 is also not selected
                push @p_unselected, $treerowreference;
            }

            return;
        }
    );

    $selection->unselect_all;
    foreach my $rowref (@p_unselected) {
        my $path = $rowref->get_path;
        $selection->select_path($path);
    }

    delete $self->{ignore_selection_change};

    #  now we trigger the re-selection
    on_selected_labels_changed ($selection, [$self, 'listLabels1']);

    return;
}

sub select_using_regex {
    my $self = shift;
    my %args = @_;

    my $regex  = $args{regex};
    my $exact  = $args{exact};
    my $negate = $args{negate};

    my $selection_mode = $args{selection_mode} | $self->get_selection_mode || 'new';

    if ($exact) {
        $regex = qr/\A$regex\z/;
    }

    my $treeview1 = $self->get_xmlpage_object('listLabels1');

    my $selection = $treeview1->get_selection;
    my $model1    = $treeview1->get_model;

    $self->{ignore_selection_change} = 1;

    my @p_targets;
    $model1->foreach (
        sub {
            my ($model, $path, $iter) = @_;
            #we want rows where the list1 selected column is not 1
            my $value = $model->get($iter, 0);
            my $treerowreference = Gtk3::TreeRowReference->new ($model, $path);

            my $match = $value =~ $regex;
            if ($negate) {
                $match = !$match;
            }

            if ($match) {
                push @p_targets, $treerowreference;
            }

            return;
        }
    );

    if ($selection_mode eq 'new') {
        $selection->unselect_all;
    }

    my $method = 'select_path';
    if ($selection_mode eq 'remove_from') {
        $method = 'unselect_path';
    }
    foreach my $rowref (@p_targets) {
        my $path = $rowref->get_path;
        $selection->$method($path);
    }

    delete $self->{ignore_selection_change};

    #  now we trigger the re-selection
    on_selected_labels_changed ($selection, [$self, 'listLabels1']);

    return;
}


sub set_phylogeny_options_sensitive {
    my $self = shift;
    my $enabled = shift;

    #  These are handled differently now.
    #  Leaving code as a reminder, but returning early.
    return;

    my $page = $self->{xmlPage};

    for my $widget (
        qw /
            phylogeny_plot_length
            phylogeny_plot_depth
            highlight_groups_on_map_labels_tab
            use_highlight_path_changed1
            menuitem_labels_set_tree_line_widths
        /) { #/
        $page->get_object($widget)->set_sensitive($enabled);
    }
}

sub on_selected_phylogeny_changed {
    my $self = shift;

    my $phylogeny = $self->{project}->get_selected_phylogeny;

    # $self->{dendrogram}->clear;
    if ($phylogeny) {
        #  now storing tree objects directly
        $self->{dendrogram}->set_current_tree($phylogeny);
        $self->set_phylogeny_options_sensitive(1);
    }
    else {
        $self->{dendrogram}->set_current_tree(undef);
        $self->set_phylogeny_options_sensitive(0);
        my $str = '<i>No selected tree</i>';
        $self->get_xmlpage_object('label_VL_tree')->set_markup($str);
    }

    return;
}

sub on_highlight_groups_on_map_changed {
    my $self = shift;
    $self->{dendrogram}->set_use_highlight_func;

    return;
}

sub on_selected_matrix_changed {
    my ($self, %args) = @_;

    my $matrix_ref = $self->{project}->get_selected_matrix;

    $self->{matrix_ref} = $matrix_ref;

    my $mg = $self->{matrix_grid};
    $mg->set_current_matrix ($matrix_ref);
    $mg->recolour;

    my $labels_are_in_mx = $mg->current_matrix_overlaps;

    #  hide the second list if no matrix selected
    my $list_window = $self->get_xmlpage_object('scrolledwindow_labels2');
    my $list = $self->get_xmlpage_object('listLabels1');
    my $col  = $list->get_column ($labels_model_list2_sel_col);

    my $visible = $labels_are_in_mx && defined $matrix_ref;

    $col->set_visible ($visible);

    my $vpane = $self->get_xmlpage_object('vpaneLists');
    #  avoid draw errors when we have not been rendered yet
    my $max_pos = $vpane->get('max-position');
    if ($max_pos < 2**30) {
        $list_window->set_visible($visible);
        if ($visible) {
            #  use the allocation as sometimes we get tiny max_pos values
            my $alloc = $vpane->get_allocation;
            my $pos = List::Util::max ($max_pos, $alloc->{height}) * 0.5;
            $vpane->set_position($pos);
        }
    }
    elsif (!$self->{_callback_for_empty_mx_has_been_set}) {
        #  trigger an update when we finally have a useful max-position
        $vpane->signal_connect (
            'size-allocate' => sub {
                my ($widget) = @_;

                state $done;
                #  we only do things once
                return if $done;

                return if $widget->get('max-position') == 2**31-1;  #  not rendered yet
                return if !$self->{matrix_grid};

                $list_window->set_visible($self->{matrix_grid}->current_matrix_overlaps);

                $done++;

                return 0;
            }
        );
        $self->{_callback_for_empty_mx_has_been_set} = 1;
    }

    return;
}

#  should use the group-changed signal to trigger this
sub on_grid_colour_scaling_changed {
    my ($self, $radio_widget) = @_;

    #  avoid triggering twice - we only care about which one is active
    return if !$radio_widget->get_active;

    my %names_and_strings;
    foreach my $opt (qw /auto linear log/) {
        $names_and_strings{"radiomenuitem_grid_colouring_$opt"} = $opt;
    }

    my $mode_string;
    foreach my $name (keys %names_and_strings) {
        my $string = $names_and_strings{$name};
        my $widget = $self->get_xmlpage_object($name);
        if ($widget->get_active) {
            $mode_string = $string;
            last;
        }
    }

    die "[Labels tab] - on_grid_colour_scaling_changed - undefined mode"
      if !defined $mode_string;

    say "[Labels tab] Changing grid colour scaling to $mode_string";

    if ($mode_string eq 'log') {
        $self->set_legend_log_mode ('on');
    }
    elsif ($mode_string eq 'linear') {
        $self->set_legend_log_mode ('off');
    }
    else {
        $self->set_legend_log_mode ('auto');
    }
    on_selected_labels_changed(undef, [$self]);
    
    return;   
}

sub set_legend_log_mode {
    my ($self, $mode) = @_;
    die 'invalid mode' if $mode !~ /^(auto|off|on)$/;
    $self->{legend_log_mode} = $mode;
}

sub get_legend_log_mode {
    my ($self) = @_;
    $self->{legend_log_mode} //= 'auto';
}


# Called when user changes selection in one of the two labels lists
sub on_selected_labels_changed {
    my ($selection, $args) = @_;
    my ($self, $id) = @$args;

    # Ignore waste-of-time events fired on on_phylogeny_click as it
    # selects labels one-by-one
    return if defined $self->{ignore_selection_change};

    #  convoluted, but allows caller subs to not know these details
    $id ||= 'listLabels1';
    if (!$selection) {
        my $treeview1 = $self->get_xmlpage_object($id);
        $selection = $treeview1->get_selection;
    }

    # are we changing the row or col list?
    my $rowcol = $id eq 'listLabels1' ? 'rows' : 'cols';
    my $select_list_name = 'selected_' . $rowcol;

    # Select rows/cols in the matrix
    my ($p, $model) = $selection->get_selected_rows();
    my @paths = @{$p // []};  #  $p is undef for no selection
    my @selected = map { ($_->get_indices)[0] } @paths;
    $self->{$select_list_name} = \@selected;

    if ($self->{matrix_ref}) {
        my $x = undef;
        $self->{matrix_grid}->highlight (
            $self->{selected_rows},
            $self->{selected_cols},
        );
        $self->{matrix_grid}->recolour;
        $self->{matrix_grid}->queue_draw;
    }

    #  need to avoid changing paths due to re-sorts
    #  the run for listLabels1 is at the end.
    if ($id eq 'listLabels2') {
        $self->set_selected_list_cols ($selection, $rowcol);
    }

    return if $id ne 'listLabels1';

    my $bd = $self->{base_ref};

    # Now, for the top list, colour the grid, based on how many labels occur in a given cell
    my %group_richness; # analysis list
    my $gp_list = $bd->get_groups;
    @group_richness{$bd->get_groups} = (0) x scalar @$gp_list;
    #my $max_value;
    my ($iter, $iter1, $label, $hash);

    my $sorted_model = $selection->get_tree_view()->get_model();
    my $global_model = $self->{labels_model};

    my $tree = $self->{project}->get_selected_phylogeny;
    my @phylogeny_colour_nodes;


    my %checked_nodes;
    foreach my $path (@paths) {

        # don't know why all this is needed (gtk bug?)
        $iter  = $sorted_model->get_iter($path);
        $iter1 = $sorted_model->convert_iter_to_child_iter($iter);
        $label = $global_model->get($iter1, LABELS_MODEL_NAME);

        # find phylogeny nodes to colour
        #  not all will match
        if (defined $tree && $tree->exists_node(name => $label)) {            
            eval {
                my $node_ref = $tree->get_node_ref_aa ($label);
                #  this will cache the path if not already done
                my $path = $node_ref->get_path_to_root_node;
                foreach $node_ref (@$path) {
                    last if exists $checked_nodes{$node_ref};
                    push @phylogeny_colour_nodes, $node_ref;
                    $checked_nodes{$node_ref}++;
                }
            }
        }

        #FIXME: This copies the hash (???recheck???) - not very fast...
        #my %hash = $self->{base_ref}->get_groups_with_label_as_hash(label => $label);
        #  SWL - just use a ref.  Unless Eugene was thinking of what the sub does...
        \my %hash = $bd->get_groups_with_label_as_hash_aa ($label);

        # groups contains count of how many different labels occur in it
        #  postfix-if for speed
        $group_richness{$_}++
          foreach keys %hash;
    }

    my $grid = $self->{grid};
    my $max_group_richness = max (values %group_richness);

    #  richness is the number of labels selected,
    #  which is the number of items in @paths
    my $max_value = scalar @paths;
    my $display_max_value = $max_value;
    my $use_log;
    if ($max_value) {
        my $mode = $self->get_legend_log_mode;
        if ($mode eq 'on') {
            $use_log = 1;
        }
        #  some arbitrary thresholds here - should let the user decide
        elsif ($mode eq 'auto' && ($max_value > 20 || ($max_group_richness / $max_value < 0.8))) {
            $use_log = 1;
        }
    }

    if ($use_log) {
        #$display_max_value = log ($max_value + 1);
        $grid->set_legend_log_mode_on;
    }
    else {
        $grid->set_legend_log_mode_off;
    }

    my $legend = $grid->get_legend;
    $legend->set_min_max(0, $display_max_value);

    my $colour_func = sub {
        my $elt = shift;
        my $val = $group_richness{$elt};
        return COLOUR_GREY if !defined $val;
        return if !$val;
        return $legend->get_colour($val, 0, $display_max_value);
    };

    $grid->colour($colour_func);

    #  messy - should store on $self
    $legend->set_visible(
        $self->get_xmlpage_object('menuitem_labels_show_legend')->get_active
    );

    if (defined $tree) {
        #print "[Labels] Recolouring cluster lines\n";
        $self->{dendrogram}->recolour_cluster_lines(
            \@phylogeny_colour_nodes,
            'no_colour_descendants',
        );
    }

    # have to run this after everything else is updated
    # otherwise incorrect nodes are selected.
    $self->set_selected_list_cols ($selection, $rowcol);

    $grid->queue_draw;

    return;
}

sub set_selected_list_cols {
    my ($self, $selection, $rowcol) = @_;

    my $label_count = $self->{base_ref}->get_label_count;

    #  we get quadratic behaviour in the set methods as iters are further along the tree
    return if $label_count > $MAX_ROW_COUNT_FOR_SEL_UPDATES;

    my $widget_name = $rowcol eq 'rows'
        ? 'listLabels1'
        : 'listLabels2';

    my $sorted_model = $selection->get_tree_view()->get_model();
    my $global_model = $self->{labels_model};

    my $change_col
        = $rowcol eq 'rows'
        ? $labels_model_list1_sel_col
        : $labels_model_list2_sel_col;

    my $selected_rows = ($selection->get_selected_rows)[0];

    #  the global model iters are persistent so we can cache
    my $iter_cache = $self->{iter_cache} //= {};

    $self->{ignore_selection_change} = 'listLabels1';

    \my %prev_selected_labels = $self->{selected_labels}{$widget_name} //= {};
    my %selected_labels;

    foreach my $path (@$selected_rows) {
        my $iter = $sorted_model->get_iter($path);
        my $label = $sorted_model->get($iter, LABELS_MODEL_NAME);
        my $iter1 = $iter_cache->{$label} //= $sorted_model->convert_iter_to_child_iter($iter);
        #  delete in case we overlap
        if (!delete $prev_selected_labels{$label}) {
            $global_model->set($iter1, $change_col, 1);
        }
        $selected_labels{$label} = $iter1;
    }

    $self->{selected_labels}{$widget_name} = \%selected_labels;

    foreach my $label (keys %prev_selected_labels) {
        my $iter1 = $prev_selected_labels{$label} // $iter_cache->{$label};
        $global_model->set($iter1, $change_col, 0);
        delete $prev_selected_labels{$label};
    }

    #  linear scan is inefficient but we need to work with the selections
    #  ...but we should have nothing left by now if all has worked
    my $change_count = 0;
    foreach my $cell_iter (0..$label_count-1) {
        last if $change_count >= keys %prev_selected_labels;  #  all found
        last if $label_count == @$selected_rows;  #  all selected

        my $iter  = $sorted_model->iter_nth_child(undef, $cell_iter);
        my $label = $sorted_model->get($iter, LABELS_MODEL_NAME);

        #  skip anything we have already set or which does not need to be unset
        next if $selected_labels{$label} || !$prev_selected_labels{$label};

        $change_count++;

        my $iter1 = $iter_cache->{$label} //= $sorted_model->convert_iter_to_child_iter($iter);
        $global_model->set($iter1, $change_col, 0);

    }

    delete $self->{ignore_selection_change};

    return;
}


sub on_sorted {
    my $self = shift;
    my %args;
    #  a massive bodge since we can be called as a
    #  gtk callback and it then has only one arg
    if ((@_ % 2) == 0) {
        %args = @_;
    }

    my $mx       = $self->{matrix_ref};
    my $mg       = $self->{matrix_grid};

    my $label_widget = $self->get_xmlpage_object('lblMatrix');
    if ($mx) {
        if ($mg->current_matrix_overlaps) {
            my $row_labels = $self->get_sorted_labels_from_list_pane(1);
            my $col_labels = $self->get_sorted_labels_from_list_pane(2);
            $mg->set_row_labels($row_labels);
            $mg->set_col_labels($col_labels);
            $mg->recolour;
        }
        else {
            my $str = '<i>No matrix elements in basedata</i>';
            $label_widget->set_markup($str);
        }
    }
    else {
        # clear matrix
        my $str = '<i>No selected matrix</i>';
        $label_widget->set_markup($str);
        $mg->set_visible(0);
    }
    $mg->queue_draw;

    return;
}

sub some_labels_are_in_matrix {
    my $self = shift;

    return if !$self->{matrix_ref};

    my $l1 = $self->{base_ref}->get_labels_ref->get_element_hash;
    my $l2 = $self->{matrix_ref}->get_elements;
    #  iterate through the shorter of the two key sets
    if (scalar keys %$l1 > scalar keys %$l2) {
        ($l1, $l2) = ($l2, $l1);
    };
    
    return any {exists $l2->{$_}} keys %$l1;
}

##################################################
# Grid events
##################################################

sub on_grid_hover {
    my ($self, $group) = @_;

    return if !$self->do_canvas_hover_flag;

    my $pfx = $self->get_grid_text_pfx;

    my $text = $pfx . (defined $group ? "Group: $group" : '<b>Groups</b>');
    $self->get_xmlpage_object('label_VL_grid')->set_markup($text);

    my $tree = $self->{project}->get_selected_phylogeny;
    return if ! defined $tree;

    $self->{dendrogram}->clear_highlights;

    return if ! defined $group;

    return if !$self->{use_highlight_path};

    # get labels in the group
    my $bd = $self->get_base_ref;
    my $labels = $bd->get_labels_in_group_as_hash_aa ($group);

    #  don't pollute the original hash
    my %highlights;
    @highlights{keys %$labels} = (1) x keys %$labels;

    my $node_ref;

    LABEL:
    foreach my $label (keys %$labels) {
        # Might not match some or all nodes
        my $success = eval {
            $node_ref = $tree->get_node_ref_aa ($label);
        };
        next LABEL if !$success;
        # set path to highlighted colour
        NODE:
        while ($node_ref = $node_ref->get_parent) {
            my $node_name = $node_ref->get_name;
            last NODE if $highlights{$node_name};
            $highlights{$node_name} ++;
        }
    }

    $self->{dendrogram}->set_branch_highlights (\%highlights);

    return;
}

sub on_end_grid_hover {
    my $self = shift;

    return if !$self->do_canvas_hover_flag;

    $self->{dendrogram}->clear_highlights;
}

sub on_grid_select {
    my ($self, $groups , $ignore_change, $rect) = @_;
    # $rect = [x1, y1, x2, y2]

    #say 'Rect: ' . Dumper ($rect);

    return if $self->{tool} ne 'Select';

    # convert groups into a hash of labels that are in them
    my %hash;
    my $bd = $self->{base_ref};
    foreach my $group (@$groups) {
        my $hashref = $bd->get_labels_in_group_as_hash_aa($group);
        @hash{ keys %$hashref } = ();
    }

    # Select all terminal labels
    my $model  = $self->{labels_model};
    my $hmodel = $self->get_xmlpage_object('listLabels1')->get_model();
    my $hselection = $self->get_xmlpage_object('listLabels1')->get_selection();

    my $sel_mode = $self->get_selection_mode;

    if ($sel_mode eq 'new') {
        $hselection->unselect_all();
    }
    my $sel_method = $sel_mode eq 'remove_from' ? 'unselect_iter' : 'select_iter';

    my $iter = $hmodel->get_iter_first();
    my $elt;

    $self->{ignore_selection_change} = 'listLabels1';
    while ($iter) {
        my $hi = $hmodel->convert_iter_to_child_iter($iter);
        $elt = $model->get($hi, 0);

        if (exists $hash{ $elt } ) {
            $hselection->$sel_method($iter);
        }

        last if !$hmodel->iter_next($iter);
    }
    if (not $ignore_change) {
        delete $self->{ignore_selection_change};
    }
    on_selected_labels_changed($hselection, [$self, 'listLabels1']);

    return;
}


##################################################
# Phylogeny events
##################################################

sub on_phylogeny_plot_mode_changed {
    my ($self, $combo) = @_;

    my %names_and_strings = (
        phylogeny_plot_depth          => 'depth',
        phylogeny_plot_length         => 'length',
        #phylogeny_plot_range_weighted => 'range_weighted',
    );

    my $mode_string;
    while (my ($name, $string) = each %names_and_strings) {
        my $widget = $self->get_xmlpage_object($name);
        if ($widget->get_active) {
            $mode_string = $string;
            last;
        }
    }

    die "[Labels tab] - on_phylogeny_plot_mode_changed - undefined mode"
      if !defined $mode_string;

    print "[Labels tab] Changing mode to $mode_string\n";
    $self->{plot_mode} = $mode_string;
    $self->{dendrogram}->set_plot_mode($mode_string); # the menubar should be disabled if no tree is loaded

    return;
}

sub on_end_phylogeny_hover {
    my ($self) = @_;

    return if !$self->do_canvas_hover_flag;

    $self->{grid}->mark_with_circles;
}

# Called by dendrogram when user hovers over a node
#  should be a hover func
sub on_phylogeny_highlight {
    my ($self, $node) = @_;

    return if !$self->do_canvas_hover_flag;

    my $terminal_elements = (defined $node) ? $node->get_terminal_elements : {};

    # Hash of groups that have the selected labels
    my %groups;
    my ($iter, $label, $hash);

    my $bd = $self->{base_ref};
    my $label_hash = $bd->get_labels_ref->get_element_hash;

  LABEL:
    foreach my $label (keys %$terminal_elements) {
        next LABEL if !exists $label_hash->{$label};

        my $containing = eval {$bd->get_groups_with_label_as_hash(label => $label)};
        next LABEL if !$containing;

        @groups{keys %$containing} = ();
    }

    $self->{grid}->mark_with_circles ( [keys %groups] );

    if (defined $node) {
        my $text = 'Node: ' . $node->get_name;
        $self->get_xmlpage_object('label_VL_tree')->set_markup($text);
    }

    return;
}

sub on_phylogeny_click {
    my $self = shift;

    return if $self->{tool} ne 'Select';

    my $node_ref = shift;
    $self->{dendrogram}->do_colour_nodes_below($node_ref);
    my $terminal_elements = (defined $node_ref) ? $node_ref->get_terminal_elements : {};

    # Select terminal labels as per the selection mode
    my $model      = $self->{labels_model};
    my $hmodel     = $self->get_xmlpage_object('listLabels1')->get_model();
    my $hselection = $self->get_xmlpage_object('listLabels1')->get_selection();

    my $sel_mode = $self->get_selection_mode;

    if ($sel_mode eq 'new') {
        $hselection->unselect_all();
    }
    my $sel_method = $sel_mode eq 'remove_from' ? 'unselect_iter' : 'select_iter';

    my $iter = $hmodel->get_iter_first();
    my $elt;

    $self->{ignore_selection_change} = 'listLabels1';
    while ($iter) {
        my $hi = $hmodel->convert_iter_to_child_iter($iter);
        $elt = $model->get($hi, 0);
        #print "[onPhylogenyClick] selected: $elt\n";

        if (exists $terminal_elements->{ $elt } ) {
            $hselection->$sel_method($iter);
        }

        last if !$hmodel->iter_next($iter);
    }
    delete $self->{ignore_selection_change};
    on_selected_labels_changed($hselection, [$self, 'listLabels1']);

    # Remove the hover marks
    $self->{grid}->mark_with_circles ( [] );


    return;
}

sub on_phylogeny_popup {
    my $self = shift;
    my $node_ref = shift;
    my $basedata_ref = $self->{base_ref};
    my ($sources, $default_source) = get_sources_for_node($node_ref, $basedata_ref);
    Biodiverse::GUI::Popup::show_popup($node_ref->get_name, $sources, $default_source);

    return;
}

sub on_use_highlight_path_changed {
    my $self = shift;

    #  set to the complement
    $self->{use_highlight_path} = not $self->{use_highlight_path};

    #  clear any highlights
    if ($self->{dendrogram} and not $self->{use_highlight_path}) {
        $self->{dendrogram}->clear_highlights;
    }

    return;
}

sub get_sources_for_node {
    my $node_ref     = shift;
    my $basedata_ref = shift;

    my %sources;

    #print Data::Dumper::Dumper($node_ref->get_value_keys);
    $sources{Labels} = sub { show_phylogeny_labels(@_, $node_ref); };
    $sources{Groups} = sub { show_phylogeny_groups(@_, $node_ref, $basedata_ref); };
    $sources{Descendants} = sub { show_phylogeny_descendents(@_, $node_ref); };

    # Custom lists - getValues() - all lists in node's $self
    # FIXME: try to merge with CellPopup::showOutputList
    #my @lists = $node_ref->get_value_keys;
    my @lists = $node_ref->get_list_names;
    foreach my $name (@lists) {
        next if not defined $name;
        next if $name =~ /^_/; # leading underscore marks internal list

        #print "[Labels] Phylogenies: adding custom list $name\n";
        $sources{$name} = sub { show_list(@_, $node_ref, $name); };
    }

    return (\%sources, 'Labels (cluster)'); # return a default too
}

# Called by popup dialog
# Shows a custom list
# FIXME: duplicates function in Clustering.pm
sub show_list {
    my $popup = shift;
    my $node_ref = shift;
    my $name = shift;

    #my $ref = $node_ref->get_value($name);
    my $ref = $node_ref->get_list_ref (list => $name);

    my $model = Gtk3::ListStore->new('Glib::String', 'Glib::String');
    my $iter;

    if (is_hashref($ref)) {
        foreach my $key (sort keys %$ref) {
            my $val = $ref->{$key};
            #print "[Dendrogram] Adding output hash entry $key\t\t$val\n";
            $iter = $model->append;
            $model->set($iter,    0,$key ,  1,$val);
        }
    }
    elsif (is_arrayref($ref)) {
        foreach my $elt (sort @$ref) {
            #print "[Dendrogram] Adding output array entry $elt\n";
            $iter = $model->append;
            $model->set($iter,    0,$elt ,  1,'');
        }
    }
    elsif (not is_ref($ref)) {
        $iter = $model->append;
        $model->set($iter,    0, $ref,  1,'');
    }

    $popup->set_value_column(1);
    $popup->set_list_model($model);

    return;
}

# Called by popup dialog
# Shows the labels for all elements under given node
sub show_phylogeny_groups {
    my $popup        = shift;
    my $node_ref     = shift;
    my $basedata_ref = shift;

    # Get terminal elements
    my $elements = $node_ref->get_terminal_elements;

    # For each element, get its groups and put into %total_groups
    my %total_groups;
    foreach my $element (natsort keys %{$elements}) {
        my $ref = eval {$basedata_ref->get_groups_with_label_as_hash(label => $element)};

        next if !$ref || !scalar keys %$ref;

        @total_groups{keys %$ref} = undef;
    }

    # Add each label into the model
    my $model = Gtk3::ListStore->new('Glib::String', 'Glib::String');
    foreach my $label (sort keys %total_groups) {
        my $iter = $model->append;
        $model->set($iter, 0, $label, 1, q{});
    }

    $popup->set_list_model($model);
    $popup->set_value_column(1);

    return;
}

# Called by popup dialog
# Shows all elements under given node
sub show_phylogeny_labels {
    my $popup = shift;
    my $node_ref = shift;

    my $elements = $node_ref->get_terminal_elements;
    my $model = Gtk3::ListStore->new('Glib::String', 'Glib::Int');

    foreach my $element (natsort keys %{$elements}) {
        my $count = $elements->{$element};
        my $iter = $model->append;
        $model->set($iter, 0,$element,  1, $count);
    }

    $popup->set_list_model($model);
    $popup->set_value_column(1);

    return;
}

# Called by popup dialog
# Shows all descendent nodes under given node
sub show_phylogeny_descendents {
    my $popup    = shift;
    my $node_ref = shift;

    my $model = Gtk3::ListStore->new('Glib::String', 'Glib::Int');

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
# Matrix Events (hover, click)
##################################################

sub on_matrix_hover {
    my ($self, $key) = @_;

    my $mg = $self->{matrix_grid};
    my ($col_label, $row_label) = $mg->get_labels_from_coord_id ($key);

    my $str;

    if (defined $row_label && defined $col_label) {

        my $matrix_ref = $self->{matrix_ref};

        if (not $matrix_ref) {
            $str = "<b>Matrix</b>: none selected";
        }
        elsif (!$matrix_ref->element_pair_exists_aa($col_label, $row_label)) {
            $str = "<b>Matrix</b> ($col_label, $row_label): not in matrix";
        }
        else {
            my $value = $matrix_ref->get_defined_value_aa($col_label, $row_label);
            $str = "<b>Matrix</b> ($col_label, $row_label): ";
            $str .= defined $value ? sprintf ("%.4f", $value) : 'undef';
        }
    }
    else {
        $str = "<b>Matrix</b>: not in matrix";
    }

    $self->get_xmlpage_object('lblMatrix')->set_markup($str);

    return;
}

sub on_matrix_clicked {
    my ($self, $cells, undef, $rect) = @_;

    return if !$self->{matrix_grid}->current_matrix_overlaps;

    return if $self->{tool} ne 'Select';

    #  list1 is the y-axis
    my $vlist = $self->get_xmlpage_object('listLabels1');
    my $hlist = $self->get_xmlpage_object('listLabels2');

    my $hsel = $hlist->get_selection;
    my $vsel = $vlist->get_selection;

    my $sel_mode = $self->get_selection_mode;

    if ($sel_mode eq 'new') {
        $hsel->unselect_all;
        $vsel->unselect_all;
    }

    return if !@$cells;

    #  We could use $rect but there were off-by-one issues,
    #  possibly because it needs to round to the nearest mid-point.
    #  It can be looked into if profiling flags this as a bottleneck.
    my ($h_start, $h_end) = minmax map {$_->{coord}[0]} @$cells;
    my ($v_start, $v_end) = minmax map {$_->{coord}[1]} @$cells;

    $h_start = Gtk3::TreePath->new_from_indices($h_start);
    $h_end   = Gtk3::TreePath->new_from_indices($h_end);
    $v_start = Gtk3::TreePath->new_from_indices($v_start);
    $v_end   = Gtk3::TreePath->new_from_indices($v_end);

    my $sel_method = $sel_mode eq 'remove_from' ? 'unselect_range' : 'select_range';

    eval {
        $hsel->$sel_method($h_start, $h_end);
    };
    warn $EVAL_ERROR if $EVAL_ERROR;
    eval {
        $vsel->$sel_method($v_start, $v_end);
    };
    warn $EVAL_ERROR if $EVAL_ERROR;

    #  scroll_to_cell now needs six params, so this needs updating.
    #  The sticking point is that if the list is sorted by selection then
    #  Those are already moved to the top or bottom of the list.
    #  So disable for now.
    # $hlist->scroll_to_cell( $h_start );
    # $vlist->scroll_to_cell( $v_start );

    return;
}

sub on_matrix_grid_clicked {}

##################################################
# Misc
##################################################

sub get_type {
    return 'labels';
}

sub remove {
    my $self = shift;
    $self->{notebook}->remove_page( $self->get_page_index );
    $self->{project}->delete_selection_callback('matrix', $self->{matrix_callback});
    $self->{project}->delete_selection_callback('phylogeny', $self->{phylogeny_callback});

    return;
}

my %drag_modes = (
    Select  => 'select',
    Pan     => 'pan',
    ZoomIn    => 'select',
    ZoomOut => 'click',
    ZoomFit => 'click',
);

my %dendrogram_drag_modes = (
    %drag_modes,
    Select  => 'click',
);


#  no longer used?
sub on_zoom_in {
    my $grid = shift;
    $grid->zoom_in();
say 'LB: Called on_zoom_in';
    return;
}

sub on_zoom_out {
    my $grid = shift;
    $grid->zoom_out();
say 'LB: Called on_zoom_out';

    return;
}

sub on_zoom_fit {
    my $grid = shift;
    $grid->zoom_fit();
say 'LB: Called on_zoom_fit';

    return;
}

#   should be inherited from Tab.pm,
# sub on_overlays {
#     my $self = shift;
#     my $button = shift;
#
#     Biodiverse::GUI::Overlays::show_dialog( $self->{grid} );
#
#     return;
# }

##################################################
# Managing that vertical pane
##################################################

# Sets the vertical pane's position (0->all the way down | 1->fully up)
sub set_pane {
    my $self = shift;
    my $pos  = shift;
    my $id   = shift;

    my $pane = $self->get_xmlpage_object($id);
    my $max_pos = $pane->get('max-position');
    $pane->set_position( $max_pos * $pos );
    #print "[Labels tab] Updating pane $id: maxPos = $max_pos, pos = $pos\n";

    return;
}

# This will schedule set_pane to be called from a temporary signal handler
# Need when the pane hasn't got it's size yet and doesn't know its max position
sub queue_set_pane {
    my ($self, $pos, $id) = @_;

    my $pane = $self->get_xmlpage_object($id);

    # remember id so can disconnect later
    my $sig_id = $pane->signal_connect_swapped(
        'size-allocate',
        \&Biodiverse::GUI::Tabs::Labels::set_pane_signal,
        [$self, $id],
    );

    $self->{"set_pane_signalID$id"} = $sig_id;
    $self->{"set_panePos$id"} = $pos;

    return;
}

sub set_pane_signal {
    my ($args, undef, $pane) = @_;

    my ($self, $id) = @{$args}[0, 1];

    # Queue resize of other panes that depend on this one to get their maximum size
    if ($id eq 'hpaneLabelsTop') {
        $self->queue_set_pane(0.5, 'vpaneLists');
    }
    elsif ($id eq 'hpaneLabelsBottom') {
        $self->queue_set_pane(1, 'vpaneLists');
    }

    $self->set_pane( $self->{"set_panePos$id"}, $id );
    $pane->signal_handler_disconnect( $self->{"set_pane_signalID$id"} );
    delete $self->{"set_panePos$id"};
    delete $self->{"set_pane_signalID$id"};

    return;
}



sub update_export_menu {
    my $self = shift;

    my $menubar = $self->{menubar};
    my $output_ref = $self->{base_ref};

    # Clear out old entries from menu so we can rebuild it.
    # This will be useful when we add checks for which export methods are valid.
    my $export_menu = $self->{export_menu};
    if (!$export_menu) {
        $export_menu  = Gtk3::MenuItem->new_with_label('Export');
        $menubar->append($export_menu);
        $self->{export_menu} = $export_menu;
    }

    my %type_hash = (
        Labels => $output_ref->get_labels_ref,
        Groups => $output_ref->get_groups_ref,
    );

    my $submenu = Gtk3::Menu->new;

    foreach my $type (keys %type_hash) {
        my $ref = $type_hash{$type};
        my $submenu_item = Gtk3::MenuItem->new_with_label($type);

        my $bs_submenu = Gtk3::Menu->new;

        # Get the Parameters metadata
        my $metadata = $ref->get_metadata (sub => 'export');
        my $format_labels = $metadata->get_format_labels;
        foreach my $label (sort keys %$format_labels) {
            next if !$label;
            my $menu_item = Gtk3::MenuItem->new($label);
            $bs_submenu->append($menu_item);
            $menu_item->signal_connect_swapped(
                activate => \&do_export, [$self, $ref, $label],
            );
        }
        $submenu_item->set_submenu($bs_submenu);
        $submenu_item->set_sensitive(1);
        $submenu->append($submenu_item);
    }

    $export_menu->set_submenu($submenu);
    $export_menu->set_sensitive(1);

    $menubar->show_all();
}

sub do_export {
    my $args = shift;
    my $self = $args->[0];
    my $ref  = $args->[1];
    my @rest_of_args;
    if (scalar @$args > 2) {
        @rest_of_args = @$args[2..$#$args];
    }

    Biodiverse::GUI::Export::Run($ref, @rest_of_args);
}


sub update_selection_menu {
    my $self = shift;

    my $menubar    = $self->{menubar};
    my $base_ref = $self->{base_ref};

    # Clear out old entries from menu so we can rebuild it.
    # This will be useful when we add checks for which export methods are valid.
    my $selection_menu_item = $self->{selection_menu};
    if (!$selection_menu_item) {
        $selection_menu_item  = Gtk3::MenuItem->new_with_label('Selection');
        $menubar->append($selection_menu_item);
        $self->{selection_menu} = $selection_menu_item;
    }
    my $selection_menu = Gtk3::Menu->new;
    $selection_menu_item->set_submenu($selection_menu);

    my %type_hash = (
        Labels => $base_ref->get_labels_ref,
        Groups => $base_ref->get_groups_ref,
    );

    #  export submenu
    my $export_menu_item = Gtk3::MenuItem->new_with_label('Export');
    my $export_submenu = Gtk3::Menu->new;

    foreach my $type (keys %type_hash) {
        my $ref = $type_hash{$type};

        my $submenu_item = Gtk3::MenuItem->new_with_label($type);
        my $submenu = Gtk3::Menu->new;

        # Get the Parameters metadata
        my $metadata = $ref->get_metadata (sub => 'export');
        my $format_labels = $metadata->get_format_labels;
        foreach my $label (sort keys %$format_labels) {
            next if !$label;
            my $menu_item = Gtk3::MenuItem->new($label);
            $submenu->append($menu_item);
            $menu_item->signal_connect_swapped(
                activate => \&do_selection_export, [$self, $ref, selected_format => $label],
            );
        }
        $submenu_item->set_submenu($submenu);
        $export_submenu->append($submenu_item);
    }
    $export_menu_item->set_submenu($export_submenu);
    $export_menu_item->set_tooltip_text('Export selected labels across all groups in which they occur');

    ####  now some options to delete selected labels
    my $delete_menu_item = Gtk3::MenuItem->new_with_label('Delete');
    my $delete_submenu = Gtk3::Menu->new;

    foreach my $option ('Selected labels', 'Selected labels, retaining empty groups') {
        my $submenu_item = Gtk3::MenuItem->new_with_label($option);
        $delete_submenu->append ($submenu_item);
        $submenu_item->signal_connect_swapped(
            activate => \&do_delete_selected_basedata_records, [$self, $base_ref, $option],
        );
    }
    $delete_menu_item->set_submenu($delete_submenu);

    ####  now some options to create new basedatas
    my $new_bd_menu_item = Gtk3::MenuItem->new_with_label('New BaseData from');
    my $new_bd_submenu = Gtk3::Menu->new;

    foreach my $option ('Selected labels', 'Non-selected labels') {
        my $submenu_item = Gtk3::MenuItem->new_with_label($option);
        $new_bd_submenu->append ($submenu_item);
        $submenu_item->signal_connect_swapped(
            activate => \&do_new_basedata_from_selection, [$self, $base_ref, $option],
        );
    }
    $new_bd_menu_item->set_submenu($new_bd_submenu);
    $new_bd_menu_item->set_tooltip_text(
          'Create a subset of the basedata comprising '
        . 'all groups containing selected labels. '
        . 'Optionally retains empty groups.'
    );

    my $select_regex_item = Gtk3::MenuItem->new_with_label('Select labels by text matching');
    $select_regex_item->signal_connect_swapped (
        activate => \&do_select_labels_regex, [$self, $base_ref],
    );
    $select_regex_item->set_tooltip_text ('Select by text matching.  Uses regular expressions so you can use all relevant modifiers.');

    my $switch_selection_item = Gtk3::MenuItem->new_with_label('Switch selection');
    $switch_selection_item->signal_connect_swapped (
        activate => \&do_switch_selection, [$self, $base_ref],
    );
    $switch_selection_item->set_tooltip_text ('Switch selection to all currently non-selected labels');

    my $selection_mode_item = Gtk3::MenuItem->new_with_label('Selection mode');
    my $sel_mode_submenu    = Gtk3::Menu->new;
    my $sel_group = [];

    foreach my $option (qw /new add_to remove_from/) {
        my $submenu_item = Gtk3::RadioMenuItem->new_with_label($sel_group, $option);
        $sel_mode_submenu->append ($submenu_item);
        $submenu_item->signal_connect_swapped(
            activate => \&do_set_selection_mode, [$self, $option],
        );
        push @$sel_group, $submenu_item;  #  first one is default
    }
    $selection_mode_item->set_submenu($sel_mode_submenu);
    $selection_mode_item->set_tooltip_text(
          'Set the selection mode for grid, tree and matrix selections. '
        . 'List selections can be added and removed control clicking '
        . '(shift clicking adds ranges of labels).',
    );


    my $selected_labels_to_clipboard = Gtk3::MenuItem->new_with_label('Copy selected labels to clipboard');
    $selected_labels_to_clipboard->signal_connect_swapped(
        activate => \&do_copy_selected_to_clipboard, [$self],
    );
    $selected_labels_to_clipboard->set_tooltip_text(
          'Copy the selected label names to the clipboard',
    );
    my $selected_records_to_clipboard = Gtk3::MenuItem->new_with_label('Copy selected records to clipboard');
    $selected_records_to_clipboard->signal_connect_swapped(
        activate => \&do_copy_selected_to_clipboard, [$self, 'full_recs'],
    );
    $selected_records_to_clipboard->set_tooltip_text(
          'Copy the selected records to the clipboard (labels and data)',
    );

    $selection_menu->append($selected_labels_to_clipboard);
    $selection_menu->append($selected_records_to_clipboard);
    $selection_menu->append($selection_mode_item);
    $selection_menu->append($switch_selection_item);
    $selection_menu->append($select_regex_item);
    $selection_menu->append($export_menu_item);
    $selection_menu->append($delete_menu_item);
    $selection_menu->append($new_bd_menu_item);

    $menubar->show_all();
}

sub do_switch_selection {
    my $args = shift;
    my $self = $args->[0];
    my $ref  = $args->[1];

    $self->switch_selection;

    return;
}

sub do_copy_selected_to_clipboard {
    my $args = shift;
    my ($self, $do_full_recs) = @$args;

    my $clipboard = Gtk3::Clipboard::get(
        Gtk3::Gdk::Atom::intern('CLIPBOARD', Glib::FALSE)
    );

    my $text = $self->get_text_for_clipboard ($do_full_recs);
    $clipboard->set_text($text);

    return;
}

sub get_text_for_clipboard {
    my ($self, $do_full_recs) = @_;

    my $text = '';

    # Generate the text
    if ($do_full_recs) {
        #  could iterate over $tree_view->get_columns
        #  but we would then need to unescape the names
        my $header = $self->{tree_model_column_names};
        my $selected_records = $self->get_selected_records;
        my @recs = map {[@$_[0..($#$_)-2]]} ($header, @$selected_records);
        foreach my $rec (@recs) {
            #  skip the selection cols
            $text .= join "\t", (map {$_ // ''} @$rec);
            $text .= "\n";
        }

    }
    else {
        my $selected_labels = $self->get_selected_labels;
        $text .= join "\n", @$selected_labels;
    }

    # Give the data..
    print "[Labels] Sending data for selection to clipboard\n";

    return $text;
}

sub do_selection_export {
    my $args = shift;
    my ($self, $ref, @rest_of_args) = @$args;

    my $selected_labels = $self->get_selected_labels;

    #  lazy method - clone the whole basedata then trim it
    #  we can make it more efficient later
    my $bd = $self->{base_ref};
    my $new_bd = $bd->clone (no_outputs => 1);
    $new_bd->trim (
        keep => $selected_labels,
        delete_empty_groups => 1,
    );

    my $new_ref = $new_bd->get_groups_ref;
    if ($ref->get_param('TYPE') eq 'LABELS') {
        $new_ref = $new_bd->get_labels_ref;
    }

    Biodiverse::GUI::Export::Run($new_ref, @rest_of_args);
}

sub do_new_basedata_from_selection {
    my $args = shift;

    my $self = $args->[0];  #  don't shift these - it wrecks the callback
    my $bd   = $args->[1];
    my $type = $args->[2];

    my $trim_keyword = ($type =~ /Sel/) ? 'keep' : 'trim';

    my $selected_labels = $self->get_selected_labels;

    # Show the Get Name dialog
    my $gui = $self->{gui};

    my $dlgxml = Gtk3::Builder->new();
    $dlgxml->add_from_file($self->{gui}->get_gtk_ui_file('dlgDuplicate.ui'));
    my $dlg = $dlgxml->get_object('dlgDuplicate');
    $dlg->set_title ('Basedata object name');
    $dlg->set_transient_for( $gui->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name = $bd->get_param('NAME') . ' SUBSET';
    $txt_name->set_text($name);

    #  now pack in the options
    my $vbox = $dlg->get_content_area();
    my $hbox = Gtk3::HBox->new;
    my $label = Gtk3::Label->new('Delete empty groups?');
    my $chk   = Gtk3::CheckButton->new;
    $chk->set_active(1);
    my $tip_text = 'Set to off if you wish to retain all the current groups, even if they are empty.';
    $label->set_tooltip_text($tip_text);
    $chk->set_tooltip_text($tip_text);
    $hbox->pack_start($label, 0, 0, 0);
    $hbox->pack_start($chk, 0, 0, 0);
    $vbox->pack_start($hbox, 0, 0, 0);
    $vbox->show_all;

    my $response = $dlg->run();

    if (lc($response) ne 'ok') {
        $dlg->destroy;
        return;
    }

    #  lazy method - clone the whole basedata then trim it
    #  we can make it more efficient later
    my $new_bd = $bd->clone (no_outputs => 1);
    $new_bd->trim (
        $trim_keyword => $selected_labels,
        delete_empty_groups => $chk->get_active,
    );

    my $chosen_name = $txt_name->get_text;
    $new_bd->rename (new_name => $chosen_name);

    $dlg->destroy;

    $gui->{project}->add_base_data($new_bd);

    return;
}

sub do_delete_selected_basedata_records {
    my $args = shift;

    my $self = $args->[0];  #  don't shift these - it wrecks the callback
    my $bd   = $args->[1];
    my $type = $args->[2];

    #  need to handle non-selections if we allow the keep option
    #my $trim_keyword = ($type =~ /Sel/) ? 'trim' : 'keep';
    my $trim_keyword = 'trim';

    #  fragile approach
    my $delete_empty_groups = not $type =~ /retaining empty groups/;

    my $selected = $self->get_selected_labels;
    my $count = scalar @$selected;

    return if !$count;

    my $response = Biodiverse::GUI::YesNoCancel->run({
        header => "Delete $count selected labels?",
        hide_cancel => 1,
    });

    return if $response ne 'yes';

    my $gui = $self->{gui};

    eval {
        $bd->trim (
            $trim_keyword => $selected,
            delete_empty_groups => $delete_empty_groups,
        );
    };
    if (my $e = $EVAL_ERROR) {
        $gui->report_error ($e);
        return;
    }

    $self->remove_selected_labels_from_list;
    on_selected_labels_changed (undef, [$self]);

    $gui->{project}->set_dirty;

    return;
}

sub do_select_labels_regex {
    my $args = shift;

    my $self = $args->[0];  #  don't shift these - it wrecks the callback
    my $bd   = $args->[1];

    my $mode  = $self->get_selection_mode;
    my @modes = qw /new add_to remove_from/;
    my $mode_idx = firstidx {$_ eq $mode} @modes;

    my $gui = $self->{gui};
    #  Hijack the import daligue.  (We should really build our own).
    my $dlgxml = Gtk3::Builder->new();
    $dlgxml->add_from_file($self->{gui}->get_gtk_ui_file('dlgImportParameters.ui'));
    my $dlg = $dlgxml->get_object('dlgImportParameters');
    $dlg->set_title('Text selection');
    my $table  = $dlgxml->get_object ('tableImportParameters');
    my $table_params = [
        {
            name       => 'text',
            type       => 'text_one_line',
            default    => '',
            label_text => 'Text to match',
            tooltip    => '',
        },
        {
            name       => 'selection_mode',
            type       => 'choice',
            default    => $mode_idx,
            label_text => 'Selection type',
            choices    => [@modes],
            tooltip    => 'Use this to define a new selection, add to the current selection, or remove from selection',
        },
        {
            name       => 'exact',
            type       => 'boolean',
            default    => 0,
            label_text => 'Full match?',
            tooltip    => 'The default is to select partial matches '
                        . '(i.e. "cac" will match "cac", "cactus" and "cacaphony").  '
                        . 'Set to on if you want to use only a full match.',
        },
        {
            name       => 'negate',
            type       => 'boolean',
            default    => 0,
            label_text => 'Negate the selection?',
            tooltip    => 'Negate the condition?  i.e. "cac" will match anything not containing "cac"',
        },
        {
            name       => 'case_insensitive',
            type       => 'boolean',
            default    => 0,
            label_text => 'Use case insensitive matching?',
            tooltip    => 'i.e. "cac" will match "Cac", "CAC", and "cac"',
        },
    ];
    for (@$table_params) {
        bless $_, $parameter_metadata_class;
    }

    my $parameters_table = Biodiverse::GUI::ParametersTable->new;
    my $extractors = $parameters_table->fill ($table_params, $table, $dlgxml);

    $dlg->show_all;
    my $response = $dlg->run;

    if (lc($response) ne 'ok') {
        $dlg->destroy;
        return;
    }

    my $parameters = $parameters_table->extract ($extractors);
    $dlg->destroy;

    my %params = @$parameters;
    my $regex = $params{case_insensitive}
      ? qr/$params{text}/i
      : qr/$params{text}/;
    $self->select_using_regex (%params, regex => $regex);

    return;
}

sub set_selection_mode {
    my ($self, $mode) = @_;
    $self->{selection_mode} = $mode;
}

sub get_selection_mode {
    my $self = shift;
    return $self->{selection_mode} // 'new';
}

sub do_set_selection_mode {
    my ($args, $widget) = @_;
    my ($self, $mode) = @$args;

    $self->set_selection_mode ($mode);
}

sub numerically {$a <=> $b};

#  dummy subs
sub index_is_zscore {}
sub index_is_ratio {}
sub set_invert_colours {}

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
