package Biodiverse::GUI::Overlays;

use 5.010;
use strict;
use warnings;
use Gtk3;
#use Data::Dumper;
use Geo::ShapeFile;
use Ref::Util qw/is_hashref is_blessed_ref/;
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

    my ($table, $extractors) = update_overlay_table ($project);
    my $table_window = $dlgxml->get_object('scrolledwindow19');
    $table_window->add($table);

    my %buttons = map {$_ => $dlgxml->get_object($_)}
        (qw /btnAdd btnDelete btnClear btnSet btnOverlayCancel btn_overlay_set_default_colour/);
    my %components = (
        dialog        => $dlg,
        colour_button => $colour_button,
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
    $signals->{btnAdd} //= $buttons->{btnAdd}->signal_connect_swapped(
        clicked => \&on_add,
        $project,
    );
    $signals->{btnDelete} //= $buttons->{btnDelete}->signal_connect_swapped(
        clicked => \&on_delete,
        $project,
    );
    $signals->{btnOverlayCancel} //= $buttons->{btnOverlayCancel}->signal_connect_swapped(
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
    $signals->{btnClear} = $buttons->{btnClear}->signal_connect_swapped(
        clicked => \&on_clear,
        $project,
    );
    $signals->{btnSet} = $buttons->{btnSet}->signal_connect_swapped(
        clicked => \&on_set,
        [$project, $grid, $dlg, $colour_button],
    );
    return $signals;
}

sub update_overlay_table {
    my ($project) = @_;

    my $overlays = $project->get_overlay_list();
    my $components = Biodiverse::GUI::GUIManager->instance->get_overlay_components // {};
    my $extractors = $components->{extractors} // [];

    my $colour_button = $components->{colour_button};

    my $table = $components->{params_table};

    if (!$table) {
        $table = $components->{params_table} = Gtk3::Grid->new;
        $table->set_row_spacing(5);
        $table->set_column_spacing(5);

        $table->insert_row(0);
        my $i = -1;
        foreach my $label_text ('Layer', 'Colour', 'Type', 'Plot above cells', 'Line width', 'Opacity') {
            $i++;
            my $label = Gtk3::Label->new($label_text);
            $label->set_use_markup(1);
            $label->set_markup("<b>$label_text</b>");
            $label->set_halign($label_text =~ /Layer/ ? 'center' : 'start');
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
                alpha       => 1,  #  alpha channel
            };
        }

        my $name = $entry->{name};
        my $layer_name = path ($name)->basename;
        my $type = $entry->{type} // 'polyline';
        my $col = -1;

        my $name_chk = Gtk3::CheckButton->new_with_label ($layer_name);
        $name_chk->set_tooltip_text (path ($name)->stringify);
        $name_chk->set_active ($entry->{plot});
        $name_chk->set_halign('center');
        $table->attach ($name_chk, ++$col, $row, 1, 1);

        my $rgba = $entry->{rgba} // $colour_button->get_rgba;
        if (!is_blessed_ref $rgba) {
            $rgba = Gtk3::Gdk::RGBA::parse ($rgba);
        }
        my $colour_button = Gtk3::ColorButton->new_with_rgba($rgba);
        $colour_button->set_halign('center');
        $table->attach ($colour_button, ++$col, $row, 1, 1);

        $table->attach (Gtk3::Label->new ($type), ++$col, $row, 1, 1);

        my $plot_on_top = Gtk3::CheckButton->new;
        $plot_on_top->set_active (!!$entry->{plot_on_top});
        $plot_on_top->set_halign('center');
        $table->attach ($plot_on_top, ++$col, $row, 1, 1);

        my $linewidth = Gtk3::SpinButton->new_with_range (1, 20, 1);
        $linewidth->set_tooltip_text ("In pixel units.");
        $linewidth->set_value ($entry->{linewidth} || 1);
        $linewidth->set_halign('center');
        $table->attach ($linewidth, ++$col, $row, 1, 1);

        my $alpha = Gtk3::SpinButton->new_with_range (0, 1, 0.05);
        $alpha->set_tooltip_text ("Controls transparency/opacity.\n0 is fully transparent.");
        $alpha->set_value ($entry->{alpha} || !!$entry->{plot_on_top} ? 0.5 : 1);
        $alpha->set_halign('center');
        $table->attach ($alpha, ++$col, $row, 1, 1);

        push @$extractors, {
            name        => $name,
            type        => $type,
            plot_on_top => sub {$plot_on_top->get_active},
            alpha       => sub {$alpha->get_value},
            plot        => sub {$name_chk->get_active},
            rgba        => sub {$colour_button->get_rgba},
            linewidth   => sub {$linewidth->get_value},
            chkbox_plot => $name_chk,
        };

    }
    $table->show_all;

    return ($table, $extractors);
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
            alpha       => $entry->{alpha}->(),
            plot        => $entry->{plot}->(),
            rgba        => $entry->{rgba}->()->to_string,
            linewidth   => $entry->{linewidth}->(),
        };
    }

    return wantarray ? @table : \@table;
}


sub on_set_default_colour {
    my ($button, $colour_button) = @_;

    $colour_button->set_rgba ($default_colour);

    return;
}

sub on_add {
    my ($project) = @_;

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
    $project->add_overlay({name => $fname, layer => $layer, type => 'polyline', plot_on_top => 1, alpha => 0.5});

    #  also load as polygon
    if ($shapetype =~ /Polygon/i) {
        $project->add_overlay({ name => $fname, layer => $layer, type => 'polygon', plot_on_top => 0, alpha => 1 });
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
    my ($choice, $iter);
    if ($response eq 'ok') {
        $choice = $combo->get_active_text;
        $iter   = $combo->get_active;
    }
    $dlg->destroy;
    return wantarray ? ($choice, $iter) : $choice;
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
    my ($project) = @_;

    #  clunky
    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $overlay_components = $gui->get_overlay_components;
    my $extractors = $overlay_components->{extractors} // [];

    return if !@$extractors;

    my @choices = map {"$_->{name} ($_->{type})"} @$extractors;

    my ($choice, $i) = get_choice(\@choices);

    my $entry = $extractors->[$i];

    my ($filename) = $entry->{name};
    return if not defined $filename;
    $project->delete_overlay($filename, $i);

    my $table = $overlay_components->{params_table};
    $table->remove_row($i+1);  #  allow for header
    $table->show_all;

    return;
}


sub on_clear {
    my ($project) = @_;

    #  clunky
    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $overlay_components = $gui->get_overlay_components;
    my $extractors = $overlay_components->{extractors} // [];

    foreach my $entry (@$extractors) {
        $entry->{chkbox_plot}->set_active(0);
    }

    update_overlay_table($project);

    return;
}

sub on_set {
    my $args = shift;
    my ($project, $grid, $dlg, $colour_button) = @$args;

    my $settings = get_settings_table_from_grid();

    $dlg->hide;

    #  clear existing
    foreach my $i (0,1) {
        $grid->set_overlay(
            shapefile   => undef,
            plot_on_top => $i,
        );
    }

    my %plot_count;
    foreach my \%layer (@$settings) {
        next if !$layer{plot};
        my $plot_position = $layer{plot_on_top} ? 'overlay' : 'underlay';
        $plot_count{$plot_position}++;
        my $name = $layer{name};
        say qq{[Overlay] Plotting "$name" as an $plot_position};
        my $colour = $layer{rgba};
        if (!is_blessed_ref $colour) {
            $colour = Gtk3::Gdk::RGBA::parse ($colour);
        }
        $grid->set_overlay(
            shapefile   => $project->get_overlay_shape_object($name),
            colour      => $colour,
            %layer{qw /plot_on_top alpha type linewidth/},
        );
    }

    return;
}

sub on_cancel {
    my $dlg = shift;
    $dlg->hide;
    return;
}


1;
