package Biodiverse::GUI::Overlays;

use 5.010;
use strict;
use warnings;
use Gtk3;
#use Data::Dumper;
use Geo::ShapeFile;
use Ref::Util qw/is_hashref/;
use Carp qw/croak/;
use Path::Tiny qw /path/;

use experimental qw /declared_refs refaliasing/;

our $VERSION = '4.99_009';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;

my $default_colour       = Gtk3::Gdk::RGBA::parse('#001169');
my $last_selected_colour = $default_colour;

use constant COL_FNAME       => 0;
use constant COL_FTYPE       => 1;
use constant COL_PLOT_ON_TOP => 2;
use constant COL_USE_ALPHA   => 3;

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
    $dlg->set_transient_for($gui->get_main_window);
    $dlg->set_position('center-on-parent');

    $colour_button->set_rgba($last_selected_colour);

    my $model = make_overlay_model($project);
    my $list = init_overlay_list($dlgxml, $model);

    my $vbox = $dlgxml->get_object('vbox21');
    my ($table, $extractors) = update_overlay_table ($project);
    my $table_window = Gtk3::ScrolledWindow->new;
    $table_window->add($table);
    $vbox->pack_start ($table_window, 1, 1, 1);
    $vbox->reorder_child($table_window, 1);

    my %buttons = map {$_ => $dlgxml->get_object($_)}
        (qw /btnAdd btnDelete btnClear btnSet btnOverlayCancel btn_overlay_set_default_colour/);
    my %components = (
        dialog        => $dlg,
        colour_button => $colour_button,
        list          => $list,
        buttons       => \%buttons,
        params_table  => $table,
        extractors    => $extractors,
    );

    my $signals = set_button_actions (
        %components,
        project       => $project,
        grid          => $grid,
    );

    #  store some but not all components we set actions for
    $gui->set_overlay_components ({
        %components,
        signals     => $signals,
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


    #  Does not display the spinners.  Not sure why.
    #  So use a boolean instead and hard code 0.5 if true.
    # my $alpha_renderer = Gtk3::CellRendererSpin->new();
    # my $adjustment = Gtk3::Adjustment->new(
    #     1, 0, 1, 0.05, 0.1, 0,
    # );
    # $alpha_renderer->set_property(adjustment => $adjustment);
    # use DDP; p $alpha_renderer;
    # my $attrs = $alpha_renderer->get_attributes;
    my $col_alpha = Gtk3::TreeViewColumn->new();
    $col_alpha->set_title('Transparent');
    my $alpha_renderer = Gtk3::CellRendererToggle->new();
    $col_alpha->pack_start($alpha_renderer, 0);
    $alpha_renderer->signal_connect('toggled' => \&_plot_alpha, $model);
    # say $col_alpha->get_attributes->to_string;
    $col_alpha->set_attributes($alpha_renderer,
        'active' => COL_USE_ALPHA,
    );
    $tree->insert_column($col_alpha, -1);


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

sub _plot_alpha {
    my ($cell, $path_str, $model) = @_;

    my $path = Gtk3::TreePath->new_from_string ($path_str);

    # get toggled iter
    my $iter = $model->get_iter ($path);
    my ($bool) = $model->get ($iter, COL_USE_ALPHA);

    # toggle the value
    $model->set($iter, COL_USE_ALPHA, !$bool);

    return;
}


# sub _update_colour_for_selection {
#     return;
#     my ($cell, $path_str, $model) = @_;
#
#     my $path = Gtk3::TreePath->new_from_string ($path_str);
#
#     # get toggled iter
#     my $iter = $model->get_iter ($path);
#     my ($bool) = $model->get ($iter, COL_PLOT_COLOUR);
#
#     my $gui = Biodiverse::GUI::GUIManager->instance;
#     my $overlay_components = $gui->get_overlay_components;
#     my $colour_button = $overlay_components->{colour_button};
#
#     my $colour = $model->get ($iter, COL_PLOT_COLOUR_BK);
#     if (!defined $colour or $colour eq 'undef') {
#         $colour = $colour_button->get_colour; #$self->get_last_colour;
#     }
#
#     if (!Scalar::Util::blessed $colour) {
#         $colour = Gtk3::Gdk::RGBA::parse($colour);
#     }
#     $colour_button->set_rgba($colour);
#
#     $colour_button->clicked;
#     $colour = $colour_button->get_color;
#
#     say STDERR $bool, ' ', $colour->to_string;
#
#     # toggle the value
#     $model->set ($iter,
#         COL_PLOT_COLOUR, !$bool,
#     );
#     $model->set ($iter,
#         COL_PLOT_COLOUR_BK, $colour->to_string,
#         # 'cell-background' => $colour->to_string,
#     );
#     say '--- ' .  $model->get ($iter, COL_PLOT_COLOUR);
#     say '--- ' .  $model->get ($iter, COL_PLOT_COLOUR_BK);
# }

# Make the object tree that appears on the left
sub make_overlay_model {
    my $project = shift;

    my $model = Gtk3::ListStore->new(
        'Glib::String',
        'Glib::String',
        'Glib::Boolean',
        'Glib::Boolean',
    );

    my $overlays = $project->get_overlay_list();

    foreach my $entry (@{$overlays}) {
        my $iter = $model->append;
        if (!is_hashref $entry) {  # previous versions did not store these
            $entry = {
                name        => $entry,
                type        => 'polyline',
                plot_on_top => !!1,
                use_alpha       => 1,  #  a boolean for partial transparency
            };
        }
        # use DDP;
        # p $entry;
        $model->set(
            $iter,
            COL_FNAME,       $entry->{name},
            COL_FTYPE,       $entry->{type} // 'polyline',
            COL_PLOT_ON_TOP, !!$entry->{plot_on_top},
            COL_USE_ALPHA,   !!$entry->{use_alpha},
        );
    }

    return $model;
}

sub update_overlay_table {
    my ($project) = @_;

    my $overlays = $project->get_overlay_list();
    my $components = Biodiverse::GUI::GUIManager->instance->get_overlay_components // {};
    my $extractors = $components->{extractors} // [];

    my $table = $components->{params_table};

    if (!$table) {
        $table = $components->{params_table} = Gtk3::Grid->new;
        $table->set_row_spacing(5);
        $table->set_column_spacing(5);

        $table->insert_row(0);
        my $i = -1;
        foreach my $label_text ('Plot?', 'Name', 'Type', 'Plot above cells', 'Transparency') {
            $i++;
            my $label = Gtk3::Label->new($label_text);
            $label->set_use_markup(1);
            $label->set_markup("<b>$label_text</b>");
            $label->set_halign('start');
            $table->insert_column($i);
            $table->attach($label, $i, 0, 1, 1);
        }
    }


    my $row = @$extractors;
    foreach my $entry (@{$overlays}[$row..$#$overlays]) {
        $row++;
        $table->insert_row ($row);

        if (!is_hashref $entry) {  # previous versions did not store these
            $entry = {
                name        => $entry,
                type        => 'polyline',
                plot_on_top => !!1,
                use_alpha   => 1,  #  a boolean for partial transparency
            };
        }

        my $name = $entry->{name};
        my $layer_name = path ($name)->basename;
        my $type = $entry->{type} // 'polyline';
        my $col = -1;

        my $use_check = Gtk3::CheckButton->new;
        $use_check->set_active (0);
        $use_check->set_halign('center');
        $table->attach ($use_check, ++$col, $row, 1, 1);

        my $name_label = Gtk3::Label->new ($layer_name);
        $name_label->set_tooltip_text (path ($name)->stringify);
        $name_label->set_halign ('start');
        $table->attach ($name_label, ++$col, $row, 1, 1);
        $table->attach (Gtk3::Label->new ($type), ++$col, $row, 1, 1);

        my $plot_on_top = Gtk3::CheckButton->new;
        $plot_on_top->set_active (!!$entry->{plot_on_top});
        $plot_on_top->set_halign('center');
        $table->attach ($plot_on_top, ++$col, $row, 1, 1);

        my $use_alpha = Gtk3::CheckButton->new;
        $use_alpha->set_active (!!$entry->{use_alpha});
        $use_alpha->set_halign('center');
        $table->attach ($use_alpha, ++$col, $row, 1, 1);

        push @$extractors, {
            name        => $name,
            type        => $type,
            plot_on_top => sub {$plot_on_top->get_active},
            use_alpha   => sub {$use_alpha->get_active},
            plot        => sub {$use_check->get_active},
        };

    }
    $table->show_all;

    #  dodgy
    eval {$dlgxml->get_object('scrolledwindow19')->hide};

    return ($table, $extractors);
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
            name        => $model->get($iter, COL_FNAME),
            type        => $model->get($iter, COL_FTYPE),
            plot_on_top => $model->get($iter, COL_PLOT_ON_TOP),
            use_alpha   => $model->get($iter, COL_USE_ALPHA),
        };
        last if !$model->iter_next($iter);
    }

    return wantarray ? @table : \@table;
}

sub get_settings_table_from_grid {
    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $overlay_components = $gui->get_overlay_components;

    my $extractors = $overlay_components->{extractors} // return;

    my @table;
    foreach my $entry (@$extractors) {
        push @table, {
            name        => $entry->{name},
            type        => $entry->{type} // 'polyline',
            plot_on_top => $entry->{plot_on_top}->(),
            use_alpha   => $entry->{use_alpha}->(),
            plot        => $entry->{plot}->(),
        };
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
    my $use_alpha   = $model->get($iter, COL_USE_ALPHA);
    # my $array_iter  = $path->to_string;  #  only works for a simple tree
    my $array_iter  = $path->get_string_from_iter($iter);

    return wantarray
        ? (iter        => $iter,        filename  => $name,      type       => $type,
           plot_on_top => $plot_on_top, use_alpha => $use_alpha, array_iter => $array_iter,
          )
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
        'Add overlay feature class',
        undef,
        'open',
        'gtk-cancel',
        'cancel',
        'gtk-ok',
        'ok'
    );
    my @filters = (
        'shapefiles'  => '*.shp',
        'geopackages' => '*.gpkg',
        'ESRI file geodatabases' => '*.gdbtable',
    );
    my $allfilter = Gtk3::FileFilter->new();
    $allfilter->set_name('All supported');
    use experimental qw /for_list/;
    foreach my ($label, $glob) (@filters) {
        my $filter = Gtk3::FileFilter->new();
        $filter->add_pattern($glob);
        $filter->set_name($label);
        $open->add_filter($filter);
        $allfilter->add_pattern($glob);
    }
    $open->add_filter($allfilter);
    $open->set_filter($allfilter);
    $open->set_modal(1);

    my $text = <<~'EOT'
        Note:
        1. Layers in database types (e.g. geopackages and geodatabases) can be
        selected in the next popup window, except if there is only one layer
        in which case it is used directly.
        2. A geodatabase is a folder so cannot be selected directly.  Instead,
        choose any gdbtable file inside it and click OK.
    EOT
    ;
    my $label = Gtk3::Label->new($text);
    my $box = $open->get_content_area;
    $box->pack_start ($label, 0, 1, 0);
    $box->show_all;


    my $filename;
    if ($open->run() eq 'ok') {
        $filename = $open->get_filename();
    }
    $open->destroy;

    return if !defined $filename;

    #  file geodatabase - we want the parent dir
    if ($filename =~ /\.gdbtable$/) {
        $filename = path($filename)->parent;
        croak "Invalid geodatabase $filename" if $filename !~ /\.gdb$/;
    }

    #  need to handle layers in geopackages and geodatabases
    my $layer;

    if ($filename !~ /.shp$/) {
        my @layers = get_layer_names_in_ogc_dataset($filename);
        return Biodiverse::GUI::GUIManager->instance->report_error (
            "Selected database does not contain any layers",
        ) if !@layers;
        $layer = @layers == 1 ? $layers[0] : get_choice (\@layers);
    }

    my $shapetype = _shp_type ($filename, $layer);
    if ($shapetype !~ /Poly/) {
        my $error = "Unable to display shapefiles of type $shapetype.";
        $error .= "\n\nBiodiverse currently only supports polygon and polyline overlays.\n";
        my $gui = Biodiverse::GUI::GUIManager->instance;
        $gui->report_error (
            $error,
            'Unsupported file type',
        );
        return;
    }

    my $fname = defined $layer ? "$filename/$layer" : $filename;

    #  load as a polyline
    my $iter = $list->get_model->append;
    $list->get_model->set($iter, COL_FNAME, $fname, COL_FTYPE, 'polyline', COL_PLOT_ON_TOP, 1, COL_USE_ALPHA, 1);
    my $sel = $list->get_selection;
    $sel->select_iter($iter);
    $project->add_overlay({name => $fname, layer => $layer, type => 'polyline', plot_on_top => 1, use_alpha => 1});

    #  also load as polygon
    if ($shapetype =~ /Polygon/i) {
        $iter = $list->get_model->append;
        $list->get_model->set($iter, COL_FNAME, $fname, COL_FTYPE, 'polygon', COL_PLOT_ON_TOP, 0, COL_USE_ALPHA, 0);
        $sel = $list->get_selection;
        $sel->select_iter($iter);
        $project->add_overlay({ name => $fname, layer => $layer, type => 'polygon', plot_on_top => 0, use_alpha => 0 });
    }

    update_overlay_table($project);

    return;
}

sub get_choice {
    my ($choices, $window_text) = @_;

    my $dlg = Gtk3::Dialog->new_with_buttons(
        $window_text // 'Layer selection',
        undef,
        'modal',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
    );
    my $box = $dlg->get_content_area;
    my $combo = Gtk3::ComboBoxText->new;
    foreach my $choice (@$choices) {
        $combo->append_text ($choice);
    }
    $combo->set_active(0);
    $box->pack_start ($combo, 0, 1, 0);
    $dlg->show_all;
    my $response = $dlg->run;
    my $choice;
    if ($response eq 'ok') {
        $choice = $combo->get_active_text;
    }
    $dlg->destroy;
    return $choice;
}

#  needed until we plot points
sub _shp_type_is_point {
    _shp_type(@_) =~/point/i;
}

sub _shp_type_is_polygon {
    _shp_type(@_) =~/polygon/i;
}

sub _shp_type {
    my ($dataset, $layer_name) = @_;
    my $layer = Geo::GDAL::FFI::Open($dataset)->GetLayer($layer_name || 0);
    return $layer->GetDefn->GetGeomFieldDefn->GetType;
}

sub get_layer_names_in_ogc_dataset {
    my ($dataset) = @_;
    my $ds = Geo::GDAL::FFI::Open($dataset);

    return $ds->GetLayerNames
        if $Geo::GDAL::FFI::VERSION ge '0.13_004';

    my @layers;
    for my $i (0 .. $ds->GetLayerCount-1) {
        # my $layer = $ds->GetLayer(int $i);
        # push @layers, $layer->GetName;
        #  work around a bug in Geo::GDAL::FFI when under the debugger
        #  https://github.com/ajolma/Geo-GDAL-FFI/issues/91
        push @layers, Geo::GDAL::FFI::OGR_L_GetName (Geo::GDAL::FFI::GDALDatasetGetLayer($$ds, $i));
    }
    return wantarray ? @layers : \@layers;
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

    my %results = get_selection($list);

    $grid->set_overlay(
        shapefile   => undef,
        plot_on_top => $results{plot_on_top},  #  are we clearing an overlay or underlay?
    );
    $dlg->hide();

    return;
}

sub on_set {
    my $button = shift;
    my $args = shift;
    my ($list, $project, $grid, $dlg, $colour_button) = @$args;

    # my ($iter, $filename, $plot_as_poly, $array_iter) = get_selection($list);
    my %results = get_selection($list);
    my ($filename, $type, $plot_on_top, $use_alpha)
        = @results{qw /filename type plot_on_top use_alpha/};

    my $colour = $colour_button->get_rgba;
    $last_selected_colour = $colour;

    my $settings = get_settings_table_from_grid();

    $dlg->hide;

    my %plot_count;
    foreach my \%layer (@$settings) {
        next if !$layer{plot};
        my $plot_position = $layer{plot_on_top} ? 'above' : 'below';
        next if $plot_count{$plot_position};
        $plot_count{$plot_position}++;
        my $name = $layer{name};
        say "[Overlay] Setting overlay to $name";
        $grid->set_overlay(
            shapefile   => $project->get_overlay_shape_object($name),
            colour      => $colour,
            %layer{qw /plot_on_top use_alpha type/},
        );
    }

    return;

    return if not $filename;

    print "[Overlay] Setting overlay to $filename\n";
    $grid->set_overlay(
        shapefile   => $project->get_overlay_shape_object($filename),
        colour      => $colour,
        plot_on_top => $plot_on_top,
        use_alpha   => $use_alpha,
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
