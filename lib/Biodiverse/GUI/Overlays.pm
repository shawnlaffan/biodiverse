package Biodiverse::GUI::Overlays;

use 5.010;
use strict;
use warnings;
use Gtk3;
#use Data::Dumper;
use Geo::ShapeFile;
use Ref::Util qw/is_hashref/;

our $VERSION = '4.99_002';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;

my $default_colour       = Gtk3::Gdk::RGBA::parse('#001169');
my $last_selected_colour = $default_colour;

use constant COL_FNAME       => 0;
use constant COL_FTYPE       => 1;
use constant COL_PLOT_ON_TOP => 2;
use constant COL_PLOT_COLOUR => 3;
use constant COL_PLOT_COLOUR_BK => 4;

sub show_dialog {
    my $grid = shift;

    # Create dialog
    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $overlay_components = $gui->get_overlay_components;
    my $project = $gui->get_project;

    if ($overlay_components) {
        my $dlg           = $overlay_components->{dialog};
        my $colour_button = $overlay_components->{colour_button};
        $colour_button->set_rgba($last_selected_colour);

        set_button_actions (
            project => $project,
            grid    => $grid,
            %$overlay_components,
        );

        $dlg->show_all;
        return;
    }

    my $dlgxml = Gtk3::Builder->new();
    $dlgxml->add_from_file($gui->get_gtk_ui_file('wndOverlays.ui'));
    my $dlg = $dlgxml->get_object('wndOverlays');
    my $colour_button = $dlgxml->get_object('colorbutton_overlays');
    $dlg->set_transient_for($gui->get_object('wndMain'));

    $colour_button->set_rgba($last_selected_colour);

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

    my $col_name = Gtk3::TreeViewColumn->new();
    my $name_renderer = Gtk3::CellRendererText->new ();
    #$name_renderer->signal_connect('toggled' => \&_update_colour_for_selection, $model);
    $col_name->set_title('File name');
    $col_name->pack_start($name_renderer, 1);
    $col_name->add_attribute($name_renderer,  text => COL_FNAME);
    $tree->insert_column($col_name, -1);

    my $col_type = Gtk3::TreeViewColumn->new();
    my $type_renderer = Gtk3::CellRendererText->new ();
    $col_type->set_title('Type');
    $col_type->pack_start($type_renderer, 1);
    $col_type->add_attribute($type_renderer,  text => COL_FTYPE);
    $tree->insert_column($col_type, -1);

    my $col_plot_on_top = Gtk3::TreeViewColumn->new();
    $col_plot_on_top->set_title('Plot above cells');
    my $plot_on_top_renderer = Gtk3::CellRendererToggle->new();
    $col_plot_on_top->pack_start($plot_on_top_renderer, 0);
    $plot_on_top_renderer->signal_connect('toggled' => \&_plot_on_top, $model);
    $col_plot_on_top->set_attributes($plot_on_top_renderer,
        'active' => COL_PLOT_ON_TOP,
    );
    $tree->insert_column($col_plot_on_top, -1);

    # my $col_colour = Gtk3::TreeViewColumn->new();
    # my $colour_renderer_toggle = Gtk3::CellRendererToggle->new();
    # my $colour_renderer_text   = Gtk3::CellRendererText->new();
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

sub _plot_on_top {
    my ($cell, $path_str, $model) = @_;

    my $path = Gtk3::TreePath->new_from_string ($path_str);

    # get toggled iter
    my $iter = $model->get_iter ($path);
    my ($bool) = $model->get ($iter, COL_PLOT_ON_TOP);

    # toggle the value
    $model->set($iter, COL_PLOT_ON_TOP, !$bool);

    return;
}

sub _update_colour_for_selection {
    return;
    my ($cell, $path_str, $model) = @_;

    my $path = Gtk3::TreePath->new_from_string ($path_str);

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
        $colour = Gtk3::Gdk::RGBA::parse($colour);
    }
    $colour_button->set_rgba($colour);

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

    my $model = Gtk3::ListStore->new(
        'Glib::String',
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
                type         => 'polyline',
                plot_on_top  => !!1,
                # has_colour   => undef,
                # colour       => undef,
            };
        }
        # use DDP;
        # p $entry;
        $model->set(
            $iter,
            COL_FNAME,       $entry->{name},
            COL_FTYPE,       $entry->{type} // 'polyline',
            COL_PLOT_ON_TOP, !!$entry->{plot_on_top},
            # COL_PLOT_COLOUR, !!$entry->{colour},
            # COL_PLOT_COLOUR_BK, ($entry->{colour} // 'white'),
        );
    }

    return $model;
}

#  get all the settings as an array of hashes
sub get_settings_table {
    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $overlay_components = $gui->get_overlay_components;

    my $tree = $overlay_components->{list} // return;

    my @table;
    my $model = $tree->get_model();
    my $iter  = $model->get_iter_first();
    while ($iter) {
        push @table, {
            name => $model->get($iter, COL_FNAME),
            type => $model->get($iter, COL_FTYPE),
            plot_on_top => $model->get($iter, COL_PLOT_ON_TOP),
        };
        last if !$model->iter_next($iter);
    }
    return wantarray ? @table : \@table;
}

# Get what was selected..
sub get_selection {
    my $tree = shift;

    my $selection = $tree->get_selection();
    my $path = $selection->get_selected_rows();
    my $iter = $selection->get_selected();
    return if not $iter;

    my $model = $tree->get_model();
    # my $iter  = $model->get_iter($path);
    my $name  = $model->get($iter, COL_FNAME);
    my $type  = $model->get($iter, COL_FTYPE);
    my $plot_on_top = $model->get($iter, COL_PLOT_ON_TOP);
    # my $array_iter  = $path->to_string;  #  only works for a simple tree
    my $array_iter  = $path->get_string_from_iter($iter);

    return wantarray
        ? (iter => $iter, filename => $name, type => $type, plot_on_top => $plot_on_top, array_iter => $array_iter)
        : $name;
}


sub on_set_default_colour {
    my ($button, $colour_button) = @_;

    $colour_button->set_rgba ($default_colour);

    return;
}

sub on_add {
    my $button = shift;
    my $args = shift;
    my ($list, $project) = @$args;

    my $open = Gtk3::FileChooserDialog->new(
        'Add shapefile',
        undef,
        'open',
        'gtk-cancel',
        'cancel',
        'gtk-ok',
        'ok'
    );
    my $filter = Gtk3::FileFilter->new();

    $filter->add_pattern('*.shp');
    $filter->set_name('.shp files');
    $open->add_filter($filter);
    $open->set_modal(1);

    my $filename;
    if ($open->run() eq 'ok') {
        $filename = $open->get_filename();
    }
    $open->destroy;

    return if !defined $filename;

    if (_shp_type_is_point($filename)) {
        my $error = "Unable to display shapefiles of type point.";
        $error .= "\n\nBiodiverse currently only supports polygon and polyline overlays.\n";
        my $gui = Biodiverse::GUI::GUIManager->instance;
        $gui->report_error (
            $error,
            'Unsupported file type',
        );
        return;
    }

    #  load as a polyline
    my $iter = $list->get_model->append;
    $list->get_model->set($iter, COL_FNAME, $filename, COL_FTYPE, 'polyline', COL_PLOT_ON_TOP, 1);
    my $sel = $list->get_selection;
    $sel->select_iter($iter);
    $project->add_overlay({name => $filename, type => 'polyline', plot_on_top => 1});

    #  also load as polygon
    if (_shp_type_is_polygon($filename)) {
        $iter = $list->get_model->append;
        $list->get_model->set($iter, COL_FNAME, $filename, COL_FTYPE, 'polygon', COL_PLOT_ON_TOP, 0);
        $sel = $list->get_selection;
        $sel->select_iter($iter);
        $project->add_overlay({ name => $filename, type => 'polygon', plot_on_top => 0 });
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
    my ($iter, $filename, $type, $plot_on_top, $array_iter)
        = @results{qw /iter filename type plot_on_top array_iter/};

    my $colour = $colour_button->get_rgba;

    $dlg->hide;

    return if not $filename;

    print "[Overlay] Setting overlay to $filename\n";
    $grid->set_overlay(
        shapefile   => $project->get_overlay_shape_object($filename),
        colour      => $colour,
        plot_on_top => $plot_on_top,
        type        => $type,
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
