package Biodiverse::GUI::Overlays;

use 5.010;
use strict;
use warnings;
use Gtk2;
#use Data::Dumper;
use Geo::ShapeFile;
use Ref::Util qw/is_hashref/;

our $VERSION = '4.99_002';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;

my $default_colour       = Gtk2::Gdk::Color->parse('#001169');
my $last_selected_colour = $default_colour;

use constant COL_FNAME       => 0;
use constant COL_PLOT_POLY   => 1;
use constant COL_PLOT_COLOUR => 2;
use constant COL_PLOT_COLOUR_BK => 3;

sub show_dialog {
    my $grid = shift;

    # Create dialog
    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $overlay_components = $gui->get_overlay_components;
    my $project = $gui->get_project;

    if ($overlay_components) {
        my $dlg           = $overlay_components->{dialog};
        my $colour_button = $overlay_components->{colour_button};
        $colour_button->set_color($last_selected_colour);

        set_button_actions (
            project => $project,
            grid    => $grid,
            %$overlay_components,
        );

        $dlg->show_all;
        return;
    }

    my $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file($gui->get_gtk_ui_file('wndOverlays.ui'));
    my $dlg = $dlgxml->get_object('wndOverlays');
    my $colour_button = $dlgxml->get_object('colorbutton_overlays');
    $dlg->set_transient_for($gui->get_object('wndMain'));

    $colour_button->set_color($last_selected_colour);

    my $model = make_overlay_model($project);
    my $list = init_overlay_list($dlgxml, $model);

    my %buttons = map {$_ => $dlgxml->get_object($_)}
        (qw /btnAdd btnDelete btnClear btnSet btnOverlayCancel btn_overlay_set_default_colour/);
    my %components = (
        dialog        => $dlg,
        colour_button => $colour_button,
        list          => $list,
        buttons       => \%buttons,
    );

    my $signals = set_button_actions (
        %components,
        project       => $project,
        grid          => $grid,
    );

    #  store some but not all components we set actions for
    $gui->set_overlay_components ({
        %components,
        signals       => $signals,
    });

    $dlg->set_modal(1);
    $dlg->show_all();

    return;
}

sub set_button_actions {
    my %args = @_;
    my ($list, $project, $grid, $dlg, $colour_button)
        = @args{qw /list project grid dialog colour_button/};

    my $buttons = $args{buttons};
    my $signals = $args{signals} // {};
    # Connect buttons

    #  these are always the same
    $signals->{btnAdd} //= $buttons->{btnAdd}->signal_connect(
        clicked => \&on_add,
        [$list, $project],
    );
    $signals->{btnDelete} //= $buttons->{btnDelete}->signal_connect(
        clicked => \&on_delete,
        [$list, $project],
    );
    $signals->{btnOverlayCancel} //= $buttons->{btnOverlayCancel}->signal_connect(
        clicked => \&on_cancel,
        $dlg,
    );
    $signals->{btn_overlay_set_default_colour}
        //= $buttons->{btn_overlay_set_default_colour}->signal_connect(
        clicked => \&on_set_default_colour,
        $colour_button,
    );

    #  these vary by grid so need to be disconnected first or we mess up other plots
    foreach my $btn (qw/btnClear btnSet/) {
        my $id = $signals->{$btn} // next;
        $buttons->{$btn}->signal_handler_disconnect($id);
    }
    $signals->{btnClear} = $buttons->{btnClear}->signal_connect(
        clicked => \&on_clear,
        [$list, $project, $grid, $dlg],
    );
    $signals->{btnSet} = $buttons->{btnSet}->signal_connect(
        clicked => \&on_set,
        [$list, $project, $grid, $dlg, $colour_button],
    );
    return $signals;
}

sub init_overlay_list {
    my $dlgxml = shift;
    my $model = shift;
    my $tree = $dlgxml->get_object('treeOverlays');

    my $col_name = Gtk2::TreeViewColumn->new();
    my $name_renderer = Gtk2::CellRendererText->new ();
    #$name_renderer->signal_connect('toggled' => \&_update_colour_for_selection, $model);
    $col_name->set_title('File name');
    $col_name->pack_start($name_renderer, 1);
    $col_name->add_attribute($name_renderer,  text => COL_FNAME);
    $tree->insert_column($col_name, -1);

    my $col_plot_poly = Gtk2::TreeViewColumn->new();
    $col_plot_poly->set_title('Plot as polygon');
    my $poly_renderer = Gtk2::CellRendererToggle->new();
    $col_plot_poly->pack_start($poly_renderer, 0);
    $poly_renderer->signal_connect('toggled' => \&_plot_poly_toggled, $model);
    $col_plot_poly->set_attributes($poly_renderer,
        'active' => 1,
    );
    $tree->insert_column($col_plot_poly, -1);

    # my $col_colour = Gtk2::TreeViewColumn->new();
    # my $colour_renderer_toggle = Gtk2::CellRendererToggle->new();
    # my $colour_renderer_text   = Gtk2::CellRendererText->new();
    # $col_colour->set_title('Colour');
    # $col_colour->pack_start($colour_renderer_toggle, 0);
    # $col_colour->pack_start($colour_renderer_text, 0);
    # $col_colour->add_attribute($colour_renderer_toggle, active => COL_PLOT_COLOUR);
    # $col_colour->set_attributes($colour_renderer_toggle, active => 1);
    # $col_colour->add_attribute($colour_renderer_text,
    #     'cell-background' => COL_PLOT_COLOUR_BK,
    # );
    # $col_colour->set_attributes($colour_renderer_text,
    #     'cell-background' => COL_PLOT_COLOUR_BK,
    # );
    # $colour_renderer_toggle->signal_connect(
    #     'toggled' => \&_update_colour_for_selection, $model
    # );
    # $tree->insert_column($col_colour, -1);

    $tree->set_headers_visible(1);
    $tree->set_model($model);

    return $tree;
}

sub _plot_poly_toggled {
    my ($cell, $path_str, $model) = @_;

    my $path = Gtk2::TreePath->new_from_string ($path_str);

    # get toggled iter
    my $iter = $model->get_iter ($path);
    my ($bool) = $model->get ($iter, COL_PLOT_POLY);

    # toggle the value
    $model->set ($iter, COL_PLOT_POLY, !$bool);
}

sub _update_colour_for_selection {
    my ($cell, $path_str, $model) = @_;

    my $path = Gtk2::TreePath->new_from_string ($path_str);

    # get toggled iter
    my $iter = $model->get_iter ($path);
    my ($bool) = $model->get ($iter, COL_PLOT_COLOUR);

    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $overlay_components = $gui->get_overlay_components;
    my $colour_button = $overlay_components->{colour_button};

    my $colour = $model->get ($iter, COL_PLOT_COLOUR_BK);
    if (!defined $colour or $colour eq 'undef') {
        $colour = $colour_button->get_colour; #$self->get_last_colour;
    }

    if (!Scalar::Util::blessed $colour) {
        $colour = Gtk2::Gdk::Color->parse($colour);
    }
    $colour_button->set_color($colour);

    $colour_button->clicked;
    $colour = $colour_button->get_color;

    say STDERR $bool, ' ', $colour->to_string;

    # toggle the value
    $model->set ($iter,
        COL_PLOT_COLOUR, !$bool,
    );
    $model->set ($iter,
        COL_PLOT_COLOUR_BK, $colour->to_string,
        # 'cell-background' => $colour->to_string,
    );
    say '--- ' .  $model->get ($iter, COL_PLOT_COLOUR);
    say '--- ' .  $model->get ($iter, COL_PLOT_COLOUR_BK);
}

# Make the object tree that appears on the left
sub make_overlay_model {
    my $project = shift;

    my $model = Gtk2::ListStore->new(
        'Glib::String',
        'Glib::Boolean',
        # 'Glib::Boolean',  #  next two are colour stuff
        # 'Glib::String',
    );

    my $overlays = $project->get_overlay_list();

    foreach my $entry (@{$overlays}) {
        my $iter = $model->append;
        if (!is_hashref $entry) {  # previous versions did not store these
            $entry = {
                name         => $entry,
                plot_as_poly => 0,
                # has_colour   => undef,
                # colour       => undef,
            };
        }
        # use DDP;
        # p $entry;
        $model->set(
            $iter,
            COL_FNAME,       $entry->{name},
            COL_PLOT_POLY,   $entry->{plot_as_poly},
            # COL_PLOT_COLOUR, !!$entry->{colour},
            # COL_PLOT_COLOUR_BK, ($entry->{colour} // 'white'),
        );
    }

    return $model;
}


# Get what was selected..
sub get_selection {
    my $tree = shift;

    my $selection = $tree->get_selection();
    my $model = $tree->get_model();
    my $path = $selection->get_selected_rows();
    return if not $path;

    my $iter = $model->get_iter($path);
    my $name = $model->get($iter, COL_FNAME);
    my $plot_as_poly = $model->get($iter, COL_PLOT_POLY);
    my $array_iter = $path->to_string;  #  only works for a simple tree

    return wantarray
        ? (iter => $iter, filename => $name, plot_as_poly => $plot_as_poly, array_iter => $array_iter)
        : $name;
}


sub on_set_default_colour {
    my $button = shift;
    my $colour_button = shift;

    $colour_button->set_color ($default_colour);

    return;
}

sub on_add {
    my $button = shift;
    my $args = shift;
    my ($list, $project) = @$args;

    my $open = Gtk2::FileChooserDialog->new(
        'Add shapefile',
        undef,
        'open',
        'gtk-cancel',
        'cancel',
        'gtk-ok',
        'ok'
    );
    my $filter = Gtk2::FileFilter->new();

    $filter->add_pattern('*.shp');
    $filter->set_name('.shp files');
    $open->add_filter($filter);
    $open->set_modal(1);

    my $filename;
    if ($open->run() eq 'ok') {
        $filename = $open->get_filename();
    }
    $open->destroy;

    if (!_shp_type_is_point($filename)) {
        my $iter = $list->get_model->append;
        $list->get_model->set($iter, COL_FNAME, $filename, COL_PLOT_POLY, 0);
        my $sel = $list->get_selection;
        $sel->select_iter($iter);

        $project->add_overlay({name => $filename});
    }
    else {  #  warn about points - one day we will fix this
        my $error = "Selected shapefile is a point type.";
        $error .= "\n\nBiodiverse currently only supports polygon and polyline overlays.";
        my $gui = Biodiverse::GUI::GUIManager->instance;
        $gui->report_error (
            $error,
            'Unsupported file type',
        );
    }

    return;
}

#  needed until we plot points
sub _shp_type_is_point {
    my $name = shift;
    
    my $shpfile = Geo::ShapeFile->new ($name);
    my $type = $shpfile->shape_type_text;
    
    return $type =~/point/i;
}

sub _shp_type_is_polygon {
    my $name = shift;

    my $shpfile = Geo::ShapeFile->new ($name);
    my $type = $shpfile->shape_type_text;

    return $type =~/polygon/i;
}

sub on_delete {
    my $button = shift;
    my $args = shift;
    my ($list, $project) = @$args;

    # my ($iter, $filename, undef, $array_iter) = get_selection($list);
    my %results = get_selection($list);
    my ($iter, $filename, $array_iter) = @results{qw/iter filename array_iter/};
    return if not defined $filename;
    $project->delete_overlay($filename, $array_iter);
    $list->get_model->remove($iter);

    return;
}


sub on_clear {
    my $button = shift;
    my $args = shift;
    my ($list, $project, $grid, $dlg) = @$args;

    $grid->set_overlay();
    $dlg->hide();

    return;
}

sub on_set {
    my $button = shift;
    my $args = shift;
    my ($list, $project, $grid, $dlg, $colour_button) = @$args;

    # my ($iter, $filename, $plot_as_poly, $array_iter) = get_selection($list);
    my %results = get_selection($list);
    my ($iter, $filename, $plot_as_poly, $array_iter)
        = @results{qw /iter filename plot_as_poly array_iter/};

    my $colour = $colour_button->get_color;

    $dlg->hide;

    return if not $filename;

    print "[Overlay] Setting overlay to $filename\n";
    $grid->set_overlay(
        shapefile    => $project->get_overlay_shape_object($filename),
        colour       => $colour,
        plot_as_poly => $plot_as_poly,
    );
    #$dlg->destroy();

    $last_selected_colour = $colour;

    return;
}

sub on_cancel {
    my $button = shift;
    my $dlg    = shift;

    $dlg->hide;

    return;
}


1;
