package Biodiverse::GUI::Tabs::Tab;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.99_004';

use List::Util qw/min max all/;
use Scalar::Util qw /blessed/;
use List::MoreUtils qw /minmax/;
use Gtk3;
use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;
use Carp;
use Sort::Key::Natural qw /natsort/;
use Ref::Util qw /is_arrayref is_coderef/;

use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';

sub add_to_notebook {
    my $self = shift;
    my %args = @_;

    my $page  = $args{page};
    my $label = $args{label};
    my $label_widget = $args{label_widget};

    $self->{notebook}   = $self->{gui}->get_notebook();
    $self->{notebook}->append_page_menu($page, $label, $label_widget);
    $self->{page}       = $page;
    $self->{gui}->add_tab($self);
    $self->set_tab_reorderable($page);

    return;
}

sub get_page_index {
    my $self = shift;
    my $page = shift || $self->{page};
    my $index = $self->{notebook}->page_num($page);
    return $index >= 0 ? $index : undef;
}

sub set_page_index {
    my $self = shift;
    
    #  no-op now
    #$self->{page_index} = shift;
    
    return;
}

sub get_xmlpage_object {
    my ($self, $id) = @_;
    return $self->{xmlPage}->get_object($id);
}

sub get_base_ref {
    my $self = shift;

    #  check all possibilities
    #  should really just have one
    foreach my $key (qw /base_ref basedata_ref selected_basedata_ref/) {
        if (exists $self->{$key}) {
            return $self->{$key};
        }
    }

    croak "Unable to access the base ref\n";
}

sub get_current_registration {
    my $self = shift;
    return $self->{current_registration};
}

sub update_current_registration {
    my $self = shift;
    my $object = shift;
    $self->{current_registration} = $object;
}

sub set_label_widget_tooltip {
    my $self = shift;
    my $bd = $self->get_base_ref;
    
    my $text = "Part of basedata " . $bd->get_name;
    my $w = $self->{label_widget} || $self->{tab_menu_label};
    
    eval {$w->set_tooltip_text ($text)};

    return;
}

sub update_name {
    my $self = shift;
    my $new_name = shift;
    #$self->{current_registration} = $new_name;
    eval {$self->{label_widget}->set_text ($new_name)};
    eval {$self->{title_widget}->set_text ($new_name)};
    eval {$self->{tab_menu_label}->set_text ($new_name)};
    return;
}

sub remove {
    my $self = shift;

    if (exists $self->{current_registration}) {  #  deregister if necessary
        #$self->{project}->register_in_outputs_model($self->{current_registration}, undef);
        $self->register_in_outputs_model($self->{current_registration}, undef);
    }
    my $index = $self->get_page_index;
    if (defined $index && $index > -1) {
        $self->{notebook}->remove_page( $index );
    }

    return;
}

sub set_project_dirty {
    my $self = shift;
    if ($self->{project}) {
        $self->{project}->set_dirty;
    }
}

sub set_tab_reorderable {
    my $self = shift;
    my $page = shift || $self->{page};

    $self->{notebook}->set_tab_reorderable($page, 1);

    return;
}

sub on_close {
    my $self = shift;
    $self->{gui}->remove_tab($self);
    #print "[GUI] Closed tab - ", $self->get_page_index(), "\n";
    return;
}

# Make ourselves known to the Outputs tab to that it
# can switch to this tab if the user presses "Show"
sub register_in_outputs_model {
    my $self = shift;
    my $output_ref = shift;
    my $tabref = shift; # either $self, or undef to deregister
    my $model = $self->{project}->get_base_data_output_model();

    # Find iter
    my $iter;
    my $iter_base = $model->get_iter_first();

    while ($iter_base) {

        my $iter_output = $model->iter_children($iter_base);
        while ($iter_output) {
            if ($model->get($iter_output, MODEL_OBJECT) eq $output_ref) {
                $iter = $iter_output;
                last; #FIXME: do we have to look at other iter_bases, or does this iterate over entire level?
            }
            
            last if !$model->iter_next($iter_output);
        }
        
        last if $iter; # break if found it
        last if !$model->iter_next($iter_base);
    }

    if ($iter) {
        $model->set($iter, MODEL_TAB, $tabref);
        $self->{current_registration} = $output_ref;
    }
    
    return;
}

#  prepend some text to the grid hover text
sub get_grid_text_pfx {
    my $self = shift;

    return q{};
}


sub warn_if_basedata_has_gt2_axes {
    my $self = shift;

    my $bd = $self->get_base_ref;
    my @cellsizes = $bd->get_cell_sizes;
    my $col_count = scalar @cellsizes;
    
    return if $col_count <= 2;
    
    my $text = << "END_OF_GT2_AXIS_TEXT"
Note: Basedata has more than two axes
so some cells will be overplotted
and thus not visible.

Only the first two axes are used for plotting.
END_OF_GT2_AXIS_TEXT
  ;

    my $dialog = Gtk3::MessageDialog->new (
        Biodiverse::GUI::GUIManager->get_main_window,
        'destroy-with-parent',
        'warning',
        'ok',
        $text,
    );
    $dialog->run;
    $dialog->destroy;

    return;
}


##########################################################
# Keyboard shortcuts
##########################################################

# Called when user switches to this tab
#   installs keyboard-shortcut handler
sub set_keyboard_handler {
    my $self = shift;

    my $page = $self->{page};

    $page->add_events([ qw/key-press-event/ ]);  #  needed?
    $page->signal_connect (key_press_event => sub {
        $self->hotkey_handler (@_);
    });

}

#  a no-op now
sub remove_keyboard_handler {
    return;
}
    
# Processes keyboard shortcuts like CTRL-G = Go!
sub hotkey_handler {
    my ($self, $widget, $event) = @_;
    my $retval;

    state $handler_entered = 0;

    # stop recursion into on_run if shortcut triggered during processing
    #   (this happens because progress-dialogs pump events..)
    return 1 if $handler_entered;

    $handler_entered = 1;

    if ($event->type eq 'key-press') {
        my $keyval = $event->keyval;
        my $key_name = Gtk3::Gdk::keyval_name($keyval);

        # say "Key press $keyval $key_name";
        # say $event->state;

        # if CTL- key is pressed
        if ($event->state >= ['control-mask']) {
            $key_name = Gtk3::Gdk::keyval_name($keyval);

            # Go!
            if ((uc $key_name) eq 'G') {
                $self->on_run();
                $retval = 1; # stop processing
            }
            # Close tab (CTRL-W)
            elsif ((uc $key_name) eq 'W') {
                if ($self->get_removable) {
                    $self->{gui}->remove_tab($self);
                    $retval = 1; # stop processing
                }
            }
        }
        else {
            # Catch alphabetic keys and some non-alpha.
            state %valid_keys
                = map {$_ => 1} (
                    'a'..'z',
                    'A'..'Z',
                    qw /equal minus plus Left Right Up Down/
                );

            if ($valid_keys{$key_name}) {
                $retval = $self->on_bare_key($key_name, $event);
            }
        }
    }

    $handler_entered = 0;
    $retval ||= 0; # continue processing
    return !!$retval;
}

{
    state $bare_key_cache_key = 'last_bare_key_time';

    #  we are getting double-pumps from key events
    sub get_last_hotkey_event_time {
        my ($self) = @_;
        $self->get_cached_value($bare_key_cache_key) // 0;
    }

    sub set_last_hotkey_event_time {
        my ($self) = @_;
        $self->set_cached_value($bare_key_cache_key => Time::HiRes::time);
    }

    sub check_hot_key_double_pump {
        my ($self) = @_;
        (Time::HiRes::time - $self->get_last_hotkey_event_time) < 0.01;
    }

    state $last_hotkey_cache_key = 'last_hot_key_time';
    sub get_last_hot_key {
        my ($self) = @_;
        $self->{$last_hotkey_cache_key};
    }

    sub set_last_hot_key {
        my ($self, $key) = @_;
        $self->{$last_hotkey_cache_key} = $key;
    }
}

######################################
#  Other stuff


sub on_run {} # default for tabs that don't implement on_run

sub on_overlays {
    my $self = shift;
    my $button = shift;

    Biodiverse::GUI::Overlays::show_dialog( $self->{grid} );

    return;
}

# Default for tabs that don't implement on_bare_key
sub on_bare_key {
    my ($self, $key, $event) = @_;

    my $active_pane = $self->{active_pane};
    return if !$active_pane;

    #  early return if key presses are too quick
    return if $self->check_hot_key_double_pump;

    my $last_hotkey = $self->get_last_hot_key;
    $self->set_last_hot_key ($key);
    my $double_key
        = (Time::HiRes::time - $self->get_last_hotkey_event_time)
        < 0.3;

    $self->set_last_hotkey_event_time;

    state %key_tool_map = (
        z => 'ZoomIn',
        x => 'ZoomOut',
        c => 'Pan',
        v => 'ZoomFit',
        b => 'Select',
        s => 'Select',
    );

    # Immediate actions without changing the current tool.
    #  these only apply in zoom mode, and are redundant now we use the +/-/= keys
    state %instant_zoom_methods = (
        # i => 'do_zoom_in_centre',
        # o => 'do_zoom_out_centre',
    );
    #  these apply at any time
    state %instant_key_methods = (
        plus  => 'do_zoom_in_centre',
        equal => 'do_zoom_in_centre',
        minus => 'do_zoom_out_centre',
        Left  => 'do_pan_left',
        Right => 'do_pan_right',
        Up    => 'do_pan_up',
        Down  => 'do_pan_down',
        V     => 'do_zoom_fit',
        Z     => 'do_zoom_in_centre',
        X     => 'do_zoom_out_centre',
    );
    state %double_key_methods = (
        v     => 'do_zoom_fit',
        z     => 'do_zoom_in_centre',
        x     => 'do_zoom_out_centre',
    );

    my $inst_meth  = $instant_key_methods{$key}
        // ($self->{tool} =~ /Zoom/ and $instant_zoom_methods{$key});

    if ($inst_meth) {
        $active_pane->$inst_meth;
    }
    elsif (   $double_key
           && $key eq $last_hotkey
           && $double_key_methods{$key}
        ) {
        #  user double tapped on the key
        my $meth = $double_key_methods{$key};
        $active_pane->$meth;
        #  leave tool as it was before double tap
        $self->choose_tool($self->{previous_tool} //= 'Select');
    }
    elsif (my $tool = $key_tool_map{$key}) {
        $self->choose_tool($tool);
    }

    return 1;
}

#  a default list
sub get_canvas_list {
    qw /grid dendrogram/;
}

#  redraw all our canvases
sub queue_draw {
    my ($self) = @_;
    foreach my $canvas_name ($self->get_canvas_list) {
        $self->{$canvas_name}->queue_draw
          if defined $self->{$canvas_name};
    }
}

{
    state $flagname = 'do_canvas_hover_flag';
    sub toggle_do_canvas_hover_flag {
        my $self = shift;
        $self->{$flagname} //= 1;
        $self->{$flagname} = !$self->{$flagname};
    }

    sub do_canvas_hover_flag {
        my $self = shift;
        $self->{$flagname} //= 1;
    }
}

sub choose_tool {
    my ($self, $tool) = @_;

    return if !$tool;

    my $old_tool = $self->{tool} //= 'Select';
    $self->{previous_tool} = $old_tool;

    if ($old_tool) {
        $self->{ignore_tool_click} = 1;
        my $widget = $self->get_xmlpage_object("btn${old_tool}Tool");
        $widget->set_active(0);
        my $new_widget = $self->get_xmlpage_object("btn${tool}Tool");
        $new_widget->set_active(1);
        $self->{ignore_tool_click} = 0;
    }

    $self->{tool} = $tool;

    foreach my $canvas ($self->get_canvas_list) {
        next if ! blessed ($self->{$canvas} // '');  # might not be initialised yet
        $self->{$canvas}->set_mode ($tool);
    }
}

sub get_removable { return 1; } # default - tabs removable

#  codes to define percentiles etc
sub get_display_stretch_codes {
    my $self = shift;
    
    my %codes = (
        '2.5'  => 'PCT025',
        '97.5' => 'PCT975',
        '5'    => 'PCT05',
        '95'   => 'PCT95',
    );

    return wantarray ? %codes : \%codes;
}

sub get_plot_min_max_values {
    my $self = shift;

    my @minmax = ($self->{plot_min_value}, $self->{plot_max_value});

    return wantarray ? @minmax : \@minmax;
}

sub format_number_for_display {
    my $self = shift;
    my %args = @_;
    my $val = $args{number};

    my $text = sprintf ('%.4f', $val); # round to 4 d.p.
    if ($text == 0) {
        $text = sprintf ('%.2e', $val);
    }
    if ($text == 0) {
        $text = 0;  #  make sure it is 0 and not 0.00e+000
    };
    return $text;
}

#  this should be auto-detected by the legend given min-max vals and stats
sub set_legend_ltgt_flags {
    my $self = shift;
    my $stats = shift;

    my $flag = 0;
    my $stat_name = ($self->{PLOT_STAT_MIN} || 'MIN');
    eval {
        if (defined $stats->{$stat_name}
            and $stats->{$stat_name} != $stats->{MIN}
            and $stat_name =~ /PCT/) {
            $flag = 1;
        }
        $self->{grid}->set_legend_lt_flag ($flag);
    };
    $flag = 0;
    $stat_name = ($self->{PLOT_STAT_MAX} || 'MAX');
    eval {
        if (defined $stats->{$stat_name}
            and $stats->{$stat_name} != $stats->{MAX}
            and $stat_name =~ /PCT/) {
            $flag = 1;
        }
        $self->{grid}->set_legend_gt_flag ($flag);
    };
    return;
}

sub on_show_hide_legend {
    my ($self, $menu_item) = @_;

    my $grid = $self->{grid};

    return if !$grid;

    my $legend = $grid->get_legend;
    return if !$legend;

    my $active = $menu_item->get_active;
    my $current_status= $legend->is_visible;
    if (!!$active != !!$current_status) {
        $legend->set_visible ($active);
        $grid->queue_draw;
    }

}

sub on_set_legend_font_size {
    my ($self, $menu_item) = @_;

    my @legends = map {eval {$self->{$_}->get_legend} || ()} $self->get_canvas_list;

    return if !@legends;

    my $legend = $legends[0];

    my $current_size = $legend->get_font_size;
    my $dlg = Gtk3::Dialog->new_with_buttons (
        'Set legend font size',
        Biodiverse::GUI::GUIManager->get_main_window,
        'destroy-with-parent',
        'gtk-ok' => 'ok',
        'gtk-cancel' => 'cancel',
    );

    my $main_box = $dlg->get_content_area;

    my $adjustment = Gtk3::Adjustment->new( $current_size, 1, 200, 1, 10, 0 );
    my $spinner    = Gtk3::SpinButton->new( $adjustment, 1, 0 );

    my $label = Gtk3::Label->new('Font size');
    my $hbox = Gtk3::Box->new('GTK_ORIENTATION_HORIZONTAL', 10);
    $hbox->pack_start ($label, 1, 1, 0);
    $hbox->pack_start ($spinner, 1, 1, 0);

    my $chk_default = Gtk3::CheckButton->new_with_label('Set this as the default');

    $main_box->pack_start ($hbox, 1, 1, 0);
    $main_box->pack_start ($chk_default, 1, 1, 0);


    $dlg->show_all;

    if ($dlg->run eq 'ok') {
        my $val = $spinner->get_value;
        foreach my $leg (@legends) {
            $leg->set_font_size($val);
        }
        $self->queue_draw;
        if ($chk_default->get_active) {
            $legend->set_default_font_size ($val);
        }
    }

    $dlg->destroy;
}

sub on_grid_colour_flip_changed {
    my ($self, $checkbox) = @_;

    my $grid = $self->{grid};

    return if !$grid;

    my $active    = !!$checkbox->get_active;
    my $prev_mode = !!$grid->get_legend->get_invert_colours;

    $grid->get_legend->set_invert_colours ($active);

    #  trigger a redisplay if needed
    if ($prev_mode != $active) {
        $self->recolour;
        $grid->update_legend;
    }

    return;
}


sub on_grid_colour_scaling_changed {
    my ($self, $checkbox) = @_;
    
    my $active = $checkbox->get_active;

    if ($active) {
        #say "[Cluster tab] Grid: Turning on log scaling mode";
        $self->set_legend_log_mode ('on');
    }
    else {
        #say "[Cluster tab] Grid: Turning off log scaling mode";
        $self->set_legend_log_mode ('off');
    }
    
    return;   
}

sub set_legend_log_mode {
    my ($self, $mode) = @_;
    die 'invalid mode' if $mode !~ /^(off|on)$/;
    my $prev_mode = $self->get_legend_log_mode;
    $self->{legend_log_mode} = $mode;
    if ($mode eq 'on') {
        $self->{grid}->set_legend_log_mode_on;
    }
    else {
        $self->{grid}->set_legend_log_mode_off;
    }
    #  trigger a redisplay if needed
    if ($prev_mode ne $mode) {
        $self->recolour;
        $self->{grid}->update_legend;
    }
}

sub get_legend_log_mode {
    my ($self) = @_;
    $self->{legend_log_mode} //= 'off';
}

sub on_colour_mode_changed {
    my ($self, $menu_item) = @_;

    if ($menu_item) {
        # Just got the signal for the deselected option.
        # Wait for signal for selected one.
        return if !$menu_item->get_active();

        my $mode = $menu_item->get_label();
    
        if ($mode eq 'Sat...') {
            $mode = 'Sat';

            # Pop up dialog for choosing the hue to use in saturation mode
            my $colour_dialog = Gtk3::ColorSelectionDialog->new('Pick Hue');
            my $colour_select = $colour_dialog->get_color_selection();
            if (my $col = $self->{hue}) {
                $colour_select->set_previous_rgba($col);
                $colour_select->set_current_rgba($col);
            }
            $colour_dialog->show_all();
            Biodiverse::GUI::GUIManager->instance->move_dlg_to_same_monitor_as_other ($colour_dialog);
            my $response = $colour_dialog->run;
            if ($response eq 'ok') {
                $self->{hue} = $colour_select->get_current_rgba();
                $self->{grid}->set_legend_hue($self->{hue});
                eval {$self->{dendrogram}->recolour(all_elements => 1)};  #  only clusters have dendrograms - needed here?  recolour below does this
            }
            $colour_dialog->destroy();
        }

        $self->set_colour_mode($mode);
    }

    $self->{grid}->set_legend_mode($self->get_colour_mode);
    # $self->recolour(all_elements => 1);
    $self->recolour();
    $self->queue_draw;

    return;
}

sub set_colour_mode {
    my ($self, $mode) = @_;
    croak "Invalid colour mode"
      if not $mode =~ /^Hue|Sat|Grey|Canape/i; 
    $self->{colour_mode} = $mode;
}

sub get_colour_mode {
    my $self = shift;
    return $self->{colour_mode};
}

sub set_active_pane {
    my ($self, $active_pane) = @_;
    $self->{active_pane} = $active_pane;
}

sub on_select_tool {
    my $self = shift;
    return if $self->{ignore_tool_click};
    $self->choose_tool('Select');
}

sub on_pan_tool {
    my $self = shift;
    return if $self->{ignore_tool_click};
    $self->choose_tool('Pan');
}

sub on_zoom_in_tool {
    my $self = shift;
    return if $self->{ignore_tool_click};
    $self->choose_tool('ZoomIn');
}

sub on_zoom_out_tool {
    my $self = shift;
    return if $self->{ignore_tool_click};
    $self->choose_tool('ZoomOut');
}

sub on_zoom_fit_tool {
    my $self = shift;
    return if $self->{ignore_tool_click};
    $self->choose_tool('ZoomFit');
}

sub on_set_map_background_colour {
    my ($self) = @_;

    my $grid = $self->{grid} // return;

    my $colour = $self->get_colour_from_chooser ($self->{map_background_colour} // Gtk3::Gdk::RGBA::parse('white'));

    #  if still no colour chosen
    return if !$colour;

    $grid->set_background_colour($colour);

    #  spatial does, labels does not
    if ($self->can('recolour')) {
        $self->recolour(all_elements => 1);
    }

    return;
}

sub on_set_cell_outline_colour {
    my $self = shift;
    my $menu_item = shift;
    $self->{grid}->set_cell_outline_colour (@_);

    # set menu item for show outline as active if not currently
    $self->set_cell_outline_menuitem_active (1);

    return;
}

sub on_set_cell_show_outline {
    my $self = shift;
    my $menu_item = shift;
    $self->{grid}->set_cell_show_outline($menu_item->get_active);
    return;
}


sub get_undef_cell_colour {
    my $self   = shift;

    my $grid = $self->{grid} // return;

    return $grid->get_colour_for_undef // $grid->set_colour_for_undef;
}

sub set_undef_cell_colour {
    my ($self, $colour) = @_;
    
    my $grid = $self->{grid} // return;

    $grid->set_colour_for_undef($colour);
}

sub on_set_undef_cell_colour {
    my ($self, $widget, $colour) = @_;

    if (! $colour) {  #  fire up a colour selector
        $colour = $self->get_colour_from_chooser ($self->get_undef_cell_colour);
    }

    #  if still no colour chosen
    return if !$colour;

    $self->set_undef_cell_colour ($colour);

    $self->recolour (all_elements => 1);

    return;
}

sub get_excluded_cell_colour {
    my $self   = shift;

    return $self->{colour_excluded_cell} // $self->set_excluded_cell_colour;
}

sub set_excluded_cell_colour {
    my ($self, $colour) = @_;
    
    my $g = my $grey = 0.9 * 255 * 257;;
    $colour //= Gtk3::Gdk::RGBA::parse("rgb($g,$g,$g)");

    croak "Colour argument must be a Gtk3::Gdk::RGBA object\n"
      if not $colour->isa('Gtk3::Gdk::RGBA');

    $self->{colour_excluded_cell} = $colour;
}

sub on_set_excluded_cell_colour {
    my ($self, $widget, $colour) = @_;

    if (! $colour) {  #  fire up a colour selector
        $colour = $self->get_colour_from_chooser ($self->get_excluded_cell_colour);
    }

    #  if still no colour chosen
    return if !$colour;

    $self->set_excluded_cell_colour ($colour);

    $self->recolour (all_elements => 1);

    return;
}

sub get_colour_from_chooser {
    my ($self, $colour) = @_;

    my $dialog = Gtk3::ColorChooserDialog->new ('Select a colour');
    Biodiverse::GUI::GUIManager->instance->move_dlg_to_same_monitor_as_other ($dialog);

    if ($colour) {
        if ($colour->isa('Gtk3::Gdk::Color')) {
            $colour = sprintf "rgb(%d,%d,%d)", map {$_ / 257} ($colour->red, $colour->green, $colour->blue);
            $dialog->set_rgba( Gtk3::Gdk::RGBA::parse $colour);
        }
        else {
            $dialog->set_rgba($colour);
        }
    }

    if ($dialog->run eq 'ok') {
        $colour = $dialog->get_rgba;
    }
    $dialog->destroy;

    return $colour;
}

sub set_dendrogram_plot_mode {
    my ($self, $mode_string) = @_;
    $mode_string ||= 'length';
    return if ($self->{plot_mode} // '') eq $mode_string;
    my $tab_type = (blessed $self) =~ s/.+:://r;
    say "[$tab_type tab] Changing tree plot mode to $mode_string";
    $self->{plot_mode} = $mode_string;
    return if !$self->get_current_tree;
    if (my $dendrogram = $self->{dendrogram}) {
        $dendrogram->set_plot_mode($mode_string)
    };
};

#  only used by Clustering at the moment
sub set_dendrogram_group_by_mode {
    my ($self, $mode_string) = @_;
    $mode_string ||= 'length';
    return if $self->{group_mode} eq $mode_string;
    my $tab_type = (blessed $self) =~ s/.+:://r;
    say "[$tab_type tab] Changing selection grouping mode to $mode_string";
    $self->{group_mode} = $mode_string;
    return if !$self->get_current_tree;
    if (my $dendrogram = $self->{dendrogram}) {
        $dendrogram->set_group_mode($mode_string)
    };
};


sub on_set_tree_line_widths {
    my $self = shift;

    return if !$self->{dendrogram};

    my $props = {
        name       => 'branch_width',
        type       => 'integer',
        default    => $self->{dendrogram}->{branch_line_width} // 0,
        min        => 0,
        max        => 15,
        label_text => "Branch line thickness in pixels",
        tooltip    => 'Set to zero to let the system calculate a default',
    };
    bless $props, $parameter_metadata_class;

    my $parameters_table = Biodiverse::GUI::ParametersTable->new;
    my ($spinner, $extractor) = $parameters_table->generate_integer ($props);

    my $dlg = Gtk3::Dialog->new_with_buttons (
        'Set branch width',
        Biodiverse::GUI::GUIManager->get_main_window,
        'destroy-with-parent',
        'gtk-ok' => 'ok',
        'gtk-cancel' => 'cancel',
    );

    my $hbox  = Gtk3::HBox->new;
    my $label = Gtk3::Label->new($props->{label_text});
    $hbox->pack_start($label,   0, 0, 1);
    $hbox->pack_start($spinner, 0, 0, 1);
    $spinner->set_tooltip_text ($props->get_tooltip);

    my $vbox = $dlg->get_content_area;
    $vbox->pack_start($hbox, 0, 0, 10);

    $dlg->show_all;
    my $response = $dlg->run;

    my $val;
    if ($response eq 'ok') {
        $val = $extractor->();
    }
    
    $dlg->destroy;

    $self->{dendrogram}->set_branch_line_width ($val);

    return $val;
    
}

sub on_tree_background_colour_changed {
    my ($self, $menu_item) = @_;

    return if !$menu_item;

    # Pop up dialog for choosing the hue to use in saturation mode
    my $colour_dialog = Gtk3::ColorChooserDialog->new('Select colour');
    # my $colour_select = $colour_dialog->get_rgba();
    if (my $current_colour = $self->get_dendrogram_background_colour) {
        $colour_dialog->set_rgba ($current_colour);
    }
    $colour_dialog->show_all();
    Biodiverse::GUI::GUIManager->instance->move_dlg_to_same_monitor_as_other ($colour_dialog);
    my $response = $colour_dialog->run;
    if ($response eq 'ok') {
        my $hue = $colour_dialog->get_rgba();
        $self->set_dendrogram_background_colour ($hue);
    }
    $colour_dialog->destroy();

    return;
}

sub set_dendrogram_background_colour {
    my ($self, $colour) = @_;
    my $dendrogram = $self->{dendrogram};
    return if !$dendrogram;
    use constant COLOUR_WHITE => Gtk3::Gdk::RGBA::parse('white');
    $dendrogram->set_background_colour($colour // COLOUR_WHITE);
}

sub get_dendrogram_background_colour {
    my $self = shift;
    my $dendrogram = $self->{dendrogram};
    return if !$dendrogram;
    my $aref = $dendrogram->get_background_colour // [0,0,0];
    my $colour = Gtk3::Gdk::RGBA::parse (sprintf "rgb(%d,%d,%d)", @$aref);
    return $colour;
}

########
##
##  Some cache methods which have been copied across from Biodiverse::Common
##  since we don't want all the methods.
##  Need to refactor Biodiverse::Common.


#  set any value - allows user specified additions to the core stuff
sub set_cached_value {
    my $self = shift;
    my %args = @_;
    @{$self->{_cache}}{keys %args} = values %args;

    return;
}

sub set_cached_values {
    my $self = shift;
    $self->set_cached_value (@_);
}

#  hot path, so needs to be lean and mean, even if less readable
sub get_cached_value {
    return if ! exists $_[0]->{_cache}{$_[1]};
    return $_[0]->{_cache}{$_[1]};
}

sub get_cached_value_keys {
    my $self = shift;
    
    return if ! exists $self->{_cache};
    
    return wantarray
        ? keys %{$self->{_cache}}
        : [keys %{$self->{_cache}}];
}

sub delete_cached_values {
    my $self = shift;
    my %args = @_;
    
    return if ! exists $self->{_cache};

    my $keys = $args{keys} || $self->get_cached_value_keys;
    return if not defined $keys or scalar @$keys == 0;

    delete @{$self->{_cache}}{@$keys};
    delete $self->{_cache} if scalar keys %{$self->{_cache}} == 0;

    return;
}

sub update_export_menu {
    my $self = shift;

    my $menubar = $self->{menubar};
    my $output_ref = $self->{output_ref};  

    # Clear out old entries from menu so we can rebuild it.
    # This will be useful when we add checks for which export methods are valid.  
    my $export_menu = $self->{export_menu};

    if (!$export_menu) {
        $export_menu  = Gtk3::MenuItem->new_with_label('Export');
        $menubar->append($export_menu);
        $self->{export_menu} = $export_menu;
    }

    if (!$output_ref || ($output_ref->get_param('COMPLETED') // 1) != 1) {
        #  completed == 2 for clusters analyses with matrices only
        $export_menu->set_sensitive(0);
    }
    else {
        my $submenu = Gtk3::Menu->new;
        # Get the Parameters metadata
        my $metadata = $output_ref->get_metadata (sub => 'export');
        my $format_labels = $metadata->get_format_labels;
        foreach my $label (sort keys %$format_labels) {
            next if !$label;
            my $menu_item = Gtk3::MenuItem->new($label);
            $submenu->append($menu_item);
            $menu_item->signal_connect_swapped(
                activate => \&do_export, [$self, $label],
            );
        }

        $export_menu->set_submenu($submenu);
        $export_menu->set_sensitive(1);
    }

    $menubar->show_all();
}

sub do_export {
    my $args = shift;
    my $self = $args->[0];

    my %args_hash;

    my $selected_format = $args->[1] // '';
    
    $args_hash{ selected_format } = $selected_format;    
    Biodiverse::GUI::Export::Run($self->{output_ref}, %args_hash);
}

sub update_display_list_combos {
    my ($self, %args) = @_;
    my $list_prefix = $args{list_prefix};
    my $methods     = $args{methods} // [];

    foreach my $method (@$methods) {
        next if !$self->can($method);
        $self->$method;
    }

    if (defined $list_prefix) {
        my @keys = grep {m/^$list_prefix\b/} keys %{$self->{stats}};
        foreach my $key (@keys) {
            delete $self->{stats}{$key};
        }
    }
    
    return;
}

sub update_map_menu {
    my ($self, %args) = @_;

    my $menubar = $self->{menubar};
    my $output_ref = $args{output_ref} || $self->{output_ref};
    return if !$output_ref;

    my $menu_items = $args{menu_items} || $self->get_map_menu_items;

    #  clunk
    my $menu = $self->{map_menu}
        //= $self->get_xmlpage_object('menu_map_options');

    if (!$menu) {
        my $sep = Gtk3::SeparatorMenuItem->new;
        $menubar->append($sep);
        $menu = Gtk3::MenuItem->new_with_label('Maplaplap');
        $menubar->append($menu);
        $self->{map_menu} = $menu;
    }

    if (($output_ref->get_param('COMPLETED') // 1) != 1) {
        #  completed == 2 for clusters analyses with matrices only
        $menu->set_sensitive(0);
    }
    else {
        my $submenu = $menu->get_submenu;
        if (!$submenu) {
            $submenu = Gtk3::Menu->new;
            $menu->set_submenu($submenu);
        }

        $self->_add_items_to_menu (
            menu  => $submenu,
            items => $menu_items,
        );

        $menu->set_sensitive(1);
    }

    $menubar->show_all();
}

sub update_tree_menu {
    my ($self, %args) = @_;

    my $menubar = $self->{menubar};
    my $output_ref = $args{output_ref} || $self->{output_ref};
    return if !$output_ref;

    my $menu_items = $args{menu_items} || $self->get_tree_menu_items;

    my $tree_menu = $self->{tree_menu};

    if (!$tree_menu) {
        my $sep = Gtk3::SeparatorMenuItem->new;
        $menubar->append($sep);
        $tree_menu = Gtk3::MenuItem->new_with_label('Tree');
        $menubar->append($tree_menu);
        $self->{tree_menu} = $tree_menu;
    }

    if (($output_ref->get_param('COMPLETED') // 1) != 1) {
        #  completed == 2 for clusters analyses with matrices only
        $tree_menu->set_sensitive(0);
    }
    else {
        my $submenu = Gtk3::Menu->new;

        $self->_add_items_to_menu (
            menu  => $submenu,
            items => $menu_items,
        );

        $tree_menu->set_submenu($submenu);
        $tree_menu->set_sensitive(1);
    }

    $menubar->show_all();
}

sub _add_items_to_menu {
    my ($self, %args) = @_;
    my @menu_items = @{$args{items}};
    my $menu = $args{menu};
    my $radio_group = $args{radio_group};

    ITEM:
    foreach my $item (@menu_items) {
        my $type = $item->{type} // 'Gtk3::MenuItem';

        if ($type eq 'submenu_radio_group') {
            #  a bit messy
            my $menu_item = Gtk3::MenuItem->new($item->{label} // ());
            if (my $tooltip = $item->{tooltip}) {
                $menu_item->set_has_tooltip(1);
                $menu_item->set_tooltip_text($tooltip);
            }
            $menu->append($menu_item);
            my $radio_submenu = Gtk3::Menu->new;
            $self->_add_items_to_menu(
                items       => $item->{items},
                menu        => $radio_submenu, #  temp
                radio_group => [],
            );
            $menu_item->set_submenu($radio_submenu);
            next ITEM;
        }

        my $menu_item;
        if ($type =~ /Radio/) {
            # warn 'FIXME RADIO STUFF';
            $menu_item = $type->new_with_label($radio_group, $item->{label} // '');
            push @$radio_group, $menu_item;
        }
        else {
            $menu_item = $type->new($item->{label} // ());
        }
        $menu->append($menu_item);

        next ITEM if $type =~ /Separator/;

        if (my $key = $item->{self_key}) {
            $self->{$key} = $menu_item,
        }
        if (my $tooltip = $item->{tooltip}) {
            $menu_item->set_has_tooltip(1);
            $menu_item->set_tooltip_text($tooltip);
        }
        if (($type =~ 'Check') && exists $item->{active}) {
            my $val = $item->{active};
            $menu_item->set_active(is_coderef $val ? $self->$val : $val);
        }
        if (my $callback = $item->{callback}) {
            my $args = $item->{callback_args};
            $menu_item->signal_connect_swapped(
                $item->{event} => $callback,
                $args // $self
            );
        }
    }

}

sub get_map_menu_item {
    my ($self, $wanted) = @_;

    state $items = {
        highlight_assemblage_ranges_on_map => {
            type     => 'Gtk3::CheckMenuItem',
            label    => 'Highlight assemblage range on map',
            tooltip  => 'When hovering the mouse over a group, '
                . 'highlight the groups on the map containing '
                . 'one or more of the labels in its assemblage.',
            event    => 'toggled',
            callback => sub {
                my $self = shift;
                #  yet to be done
                # $self->on_highlight_assemblage_groups_on_map_changed;
            },
            active   => 0,
        },
        highlight_assemblage_ranges_on_map_as_polygons => {
            type     => 'Gtk3::MenuItem',
            label    => 'Highlight assemblage ranges on map with polygons',
            tooltip  => 'When hovering the mouse over a group, '
                . 'plot a polygon of the range of each label in the assemblage. '
                . 'This can be a convex/concave hull or circumcircle.',
            event    => 'activate',
            callback => sub {
                my ($self, $widget) = @_;
                $self->run_highlight_label_range_polygons_dlg ('assemblage');
            },
        },
        separator => {
            type  => 'Gtk3::SeparatorMenuItem',
        },
    };

    my $item = $items->{$wanted};
    croak "Cannot find menu item item $wanted"
        if !$item;

    return $item;
}

sub get_tree_menu_item {
    my ($self, $wanted) = @_;

    state $tooltip_select_by =<<~'EOT'
        Should the grouping be done by length or depth?

        This allows decoupling of node selection from the tree
        display. For example, trees with many reversals are more
        easily visualised when plotted by depth, but selections
        should normally use the branch lengths.  The same
        applies to range weighted trees where many branch
        lengths are very short.

        This setting has no effect on the slider bar.
        It always groups using the current plot method,
        selecting whichever branches it crosses.
        EOT
    ;

    state $items = {
        plot_branches_by            => {
            type  => 'submenu_radio_group',
            label => 'Plot branches by',
            items => [
                {
                    type     => 'Gtk3::RadioMenuItem',
                    label    => 'Length',
                    event    => 'activate',
                    callback => sub {
                        my $self = shift;
                        $self->set_dendrogram_plot_mode('length'),
                    },
                },
                {
                    type     => 'Gtk3::RadioMenuItem',
                    label    => 'Depth',
                    event    => 'activate',
                    callback => sub {
                        my $self = shift;
                        $self->set_dendrogram_plot_mode('depth');
                    },
                    tooltip  => 'All branches are plotted with a length of 1. '
                              . 'This includes those with zero length.'
                },
                {
                    type     => 'Gtk3::RadioMenuItem',
                    label    => 'Equal branch lengths',
                    event    => 'activate',
                    callback => sub {
                        my $self = shift;
                        $self->set_dendrogram_plot_mode('equal_length');
                    },
                    tooltip  => 'All non-zero length branches are assigned '
                        . "the average branch length.  \n"
                        . 'This is the same as the alternate tree in CANAPE '
                        . 'except that all branches are retained here whereas '
                        . 'the tree is trimmed to matching branches in the PE '
                        . 'calculations.'
                },
                {
                    type     => 'Gtk3::RadioMenuItem',
                    label    => 'Range weighted branch lengths',
                    event    => 'activate',
                    callback => sub {
                        my $self = shift;
                        $self->set_dendrogram_plot_mode('range_weighted');
                    },
                    tooltip  => 'All branches are down-weighted proportional '
                        . "to their range in the current basedata. \n"
                        . "This is the same as the range weighted tree in CANAPE "
                        . "except that all branches are retained here whereas "
                        . "the tree is trimmed to matching branches in the PE "
                        . "calculations."
                },
                {
                    type     => 'Gtk3::RadioMenuItem',
                    label    => 'Range weighted equal branch lengths',
                    event    => 'activate',
                    callback => sub {
                        my $self = shift;
                        $self->set_dendrogram_plot_mode('equal_length_range_weighted');
                    },
                    tooltip  => 'All non-zero length branches are set to the same '
                        . 'length and then down-weighted proportional '
                        . "to their range in the current basedata.\n "
                        . "This is the same as the range weighted alternate tree in CANAPE"
                        . "except that all branches are retained here whereas "
                        . "the tree is trimmed to matching branches in the PE "
                        . "calculations."
                },
            ],
        },
        group_branches_by           => {
            type    => 'submenu_radio_group',
            label   => 'Select branches by',
            tooltip => $tooltip_select_by,
            items   => [
                {
                    type     => 'Gtk3::RadioMenuItem',
                    label    => 'Length',
                    event    => 'activate',
                    callback => sub {
                        my $self = shift;
                        $self->set_dendrogram_group_by_mode('length');
                    },
                },
                {
                    type     => 'Gtk3::RadioMenuItem',
                    label    => 'Depth',
                    event    => 'activate',
                    callback => sub {
                        my $self = shift;
                        $self->set_dendrogram_group_by_mode('depth');
                    },
                },
            ],
        },
        set_tree_branch_line_widths => {
            type     => 'Gtk3::MenuItem',
            label    => 'Set tree branch line widths',
            tooltip  => "Set the width of the tree branches in pixels.",
            event    => 'activate',
            callback => \&on_set_tree_line_widths,
        },
        highlight_groups_on_map => {
            type     => 'Gtk3::CheckMenuItem',
            label    => 'Highlight groups on map',
            tooltip  => 'When hovering the mouse over a tree branch, '
                . 'highlight the groups on the map in which it is found.',
            event    => 'toggled',
            callback => sub {
                my $self = shift;
                $self->on_highlight_groups_on_map_changed;
            },
            active   => 1,
        },
        highlight_groups_on_map_as_polygons => {
            type     => 'Gtk3::MenuItem',
            label    => 'Highlight groups on map with range polygons',
            tooltip  => 'When hovering the mouse over a tree branch, '
                . 'plot a polygon of the range of each subtending label. '
                . 'This can be a convex/concave hull or circumcircle.',
            event    => 'activate',
            callback => sub {
                my ($self, $widget) = @_;
                $self->run_highlight_label_range_polygons_dlg;
            },
        },
        highlight_paths_on_tree => {
            type     => 'Gtk3::CheckMenuItem',
            label    => 'Highlight paths on tree',
            tooltip  => "When hovering over a group on the map, highlight the paths "
                . "connecting the tips of the tree (that match labels in the group) "
                . "to the root.",
            event    => 'toggled',
            callback => sub {
                my $self = shift;
                $self->on_use_highlight_path_changed;
            },
            active   => 1,
        },
        export_tree => {
            type     => 'Gtk3::MenuItem',
            label    => 'Export tree',
            tooltip  => 'Export the currently displayed tree',
            event    => 'activate',
            callback => sub {
                my $self = shift;
                my $tree_ref = $self->get_current_tree;
                return if !$tree_ref;
                return Biodiverse::GUI::Export::Run($tree_ref);
            },
        },
        separator => {
            type  => 'Gtk3::SeparatorMenuItem',
        },
        background_colour => {
            type     => 'Gtk3::MenuItem',
            label    => 'Set background colour for the tree pane',
            tooltip  => 'Set the background colour the tree pane.',
            event    => 'activate',
            callback => \&on_tree_background_colour_changed,
        },
    };

    my $item = $items->{$wanted};
    croak "Cannot find menu item item $wanted"
      if !$item;

    return $item;
}

sub get_phylogeny_hover_text {
    my ($self, $branch) = @_;

    my $map_text = '<b>Node: </b> ' . $branch->get_name;
    my $dendro_text = sprintf (
        '<b>Length: </b>%.4f<b> Elt number range: </b>%d<b> - </b>%d',
        $branch->get_length, # round to 4 d.p.
        $branch->get_terminal_node_first_number // '',
        $branch->get_terminal_node_last_number // '',
    );

    return ($map_text, $dendro_text);
}



#  All of this extra calc args handling should move into its own class,
#  possibly as a superclass of CalculationsTree.
#  It could then perhaps be built from index metadata.
sub run_dlg_extra_calc_options {
    my ($self, %args) = @_;

    my $calcs = $args{calcs};

    return wantarray ? (): {}
        if !$calcs;

    my $calc_options_cb = $self->{calc_options_cb};
    my $calc_options = $calc_options_cb->();

    my %results;

    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $project = $gui->get_project;

    my $runs_get_node_hash = $calc_options->{get_node_range_hash} && grep { $_ eq 'get_node_range_hash' } @$calcs;

    #  bodgy - need to generalise
    if ($runs_get_node_hash) {

        my $dlg = Gtk3::Dialog->new_with_buttons (
            'Tree node ranges',
            Biodiverse::GUI::GUIManager->get_main_window,
            'destroy-with-parent',
            'gtk-ok' => 'ok',
            'gtk-cancel' => 'cancel',
        );

        my $cancel_widget = $dlg->get_widget_for_response ('cancel');
        $cancel_widget->set_tooltip_text('Cancelling will go back to the analysis options window');

        #  filter out trees with no bootstrap block
        #  should check for prop lists also
        my sub tree_has_prop_data {
            my $tree = shift;
            return () if !$tree;

            my $keys = $tree->get_bootstrap_keys;

            return keys %$keys;
        }

        my sub update_prop_combo {
            my ($tree_combo, $args) = @_;
            my ($prop_combo, $props_hash) = @$args;

            my $iter = $tree_combo->get_active_iter;
            my $tree = $tree_combo->get_model->get($iter, 1);

            #  Refresh the combo contents.
            #  Could keep a liststore for each tree and
            #  set that but this will do for now.
            $prop_combo->remove_all;
            my $keys = $props_hash->{$tree};
            foreach my $key (@$keys) {
                $prop_combo->append_text ($key);
            }
            #  Maybe one day we will remember per-tree selections.
            $prop_combo->set_active (0);
        }

        my $skip_check_button   = Gtk3::RadioButton->new_with_label(undef, "Union of tree tip ranges");
        my $tree_check_button   = Gtk3::RadioButton->new_with_label($skip_check_button, "Load from tree");
        my $file_check_button   = Gtk3::RadioButton->new_with_label($skip_check_button, "Load from file");
        my $output_check_button = Gtk3::RadioButton->new_with_label($skip_check_button, "Load from other output");

        my $trees = $project->get_phylogeny_list;
        my @trees = grep {tree_has_prop_data($_)} @$trees;

        my $tree_combo = Gtk3::ComboBox->new;
        my $prop_combo = Gtk3::ComboBoxText->new;

        if (@trees) {

            my $renderer_text = Gtk3::CellRendererText->new();
            $tree_combo->pack_start($renderer_text, 1);
            $tree_combo->add_attribute($renderer_text, "text", 0);

            my $model = Gtk3::ListStore->new('Glib::String', 'Glib::Scalar');

            my $default_iter = 0;
            my %props_by_tree = (none => []);

            my $project_tree = $project->get_selected_phylogeny;

            my $i = -1;
            foreach my $tree (@trees) {
                my @keys = tree_has_prop_data($tree);
                my $name = $tree->get_name;
                my $iter = $model->append();
                $model->set( $iter, 0 => $name, 1 => $tree );
                $props_by_tree{$tree} = [sort @keys];
                $i++;
                if ($tree == $project_tree) {
                    $default_iter = $i;
                }
            }

            $tree_combo->set_model ($model);
            $tree_combo->set_active($default_iter);

            $tree_combo->signal_connect(
                changed => \&update_prop_combo, [ $prop_combo, \%props_by_tree ]
            );
            $tree_combo->signal_connect (
                changed => sub {$tree_check_button->set_active(1)}
            );

            # initialise
            update_prop_combo($tree_combo, [ $prop_combo, \%props_by_tree ]);
        }
        my $tree_label = Gtk3::Label->new('Tree to use');
        my $prop_label = Gtk3::Label->new('Prop to use');

        my %range_hash_seen;
        my @range_hashes_from_outputs;
        my $basedatas = $project->get_base_data_list // [];
        foreach my $bd (@$basedatas) {
            my $bd_name = $bd->get_name;
            use experimental qw /for_list/;
            my @orefs = ($bd->get_spatial_output_refs, $bd->get_cluster_output_refs);
            foreach my $output (sort {$a->get_param('NAME') cmp $b->get_param('NAME')} @orefs) {
                #  messy
                next if $output eq ($self->{output_ref} // '');
                next if !$output->get_param ('COMPLETED');
                #  should be simplified as an output method to just get the args
                my ($p_key, $analysis_args) = $output->get_analysis_args_from_object (
                    object => $output
                );
                next if !$analysis_args;
                my $range_hash = $analysis_args->{node_range_hash};
                next if !$range_hash;
                next if $range_hash_seen{$range_hash};
                my $name = $output->get_name;
                push @range_hashes_from_outputs, ["$bd_name: $name", $range_hash];
                $range_hash_seen{$range_hash}++;
            }
        }

        my $from_outputs_combo = Gtk3::ComboBox->new;

        if (@range_hashes_from_outputs) {
            my $renderer_text = Gtk3::CellRendererText->new();
            $from_outputs_combo->pack_start($renderer_text, 1);
            $from_outputs_combo->add_attribute($renderer_text, "text", 0);

            my $model = Gtk3::ListStore->new('Glib::String', 'Glib::Scalar');

            foreach my $aref (@range_hashes_from_outputs) {
                my $name = $aref->[0];
                my $iter = $model->append();
                $model->set( $iter, 0 => $name, 1 => $aref->[1] );
            }

            $from_outputs_combo->set_model ($model);
            $from_outputs_combo->set_active(0);
            $from_outputs_combo->signal_connect (
                changed => sub {$output_check_button->set_active(1)}
            );
        }

        my $range_hash_from_file = {};
        my $file_chooser_button = Gtk3::Button->new_from_icon_name ('folder', 4);
        my $file_chooser_label   = Gtk3::Label->new(' (choose file)');
        $file_chooser_button->set_hexpand(0);
        $file_chooser_button->signal_connect (clicked => sub {
            my %res = $self->load_range_table_as_hash;
            my ($filename, $data) = @res{qw /filename data/};
            if (!!$data) {
                $file_chooser_button->set_tooltip_text("Sourced from $filename");
                $file_chooser_label->set_tooltip_text("Sourced from $filename");
                $range_hash_from_file = $data;
                use Path::Tiny qw /path/;
                $file_chooser_label->set_text(sprintf (" (.../%s)", path ($filename)->basename));
                $file_check_button->set_active (1);
            }
        });


        foreach my $widget ($skip_check_button, $tree_check_button, $file_check_button, $output_check_button) {
            $widget->set_valign('start');
        }
        $skip_check_button->set_tooltip_text(
            'Ranges are estimated using the union of the tip ranges. '
            . 'A tip\'s range is the set of groups containing that tip label.  '
            . 'This is the default.'
        );
        $tree_check_button->set_tooltip_text(
            'Trees are listed only if they were imported from Newick format and contained annotations'
        );
        $output_check_button->set_tooltip_text(
            "This is listed only when one or more other analyses used a node range table. "
            . "If a table was used for more than one analysis then only the first is shown.\n"
            . 'Naming scheme is "basedata name: output name".',
        );
        $file_check_button->set_tooltip_text (
            'Load ranges from a delimited text file. There must be a range value for each tree node.'
        );


        my $grid = Gtk3::Grid->new;
        my $row = 0;
        $grid->attach($skip_check_button, 0, $row, 1, 1);
        if (@trees) {  #  don't pack them if there are no trees to work with
            $row++;
            $grid->attach($tree_check_button, 0, $row, 1, 1);
            $grid->attach($tree_label, 1, $row, 1, 1);
            $grid->attach($tree_combo, 2, $row, 1, 1);
            $row++;
            $grid->attach($prop_label, 1, $row, 1, 1);
            $grid->attach($prop_combo, 2, $row, 1, 1);
        }
        $row++;
        $grid->attach($file_check_button,   0, $row, 1, 1);
        $grid->attach($file_chooser_label,  1, $row, 1, 1);
        $grid->attach($file_chooser_button, 2, $row, 1, 1);
        if (@range_hashes_from_outputs) {
            $row++;
            $grid->attach($output_check_button, 0, $row, 1, 1);
            $grid->attach($from_outputs_combo,  1, $row, 2, 1);  #  full span
        }

        my $box = $dlg->get_content_area;
        $box->pack_start($grid, 0, 0, 0);
        $box->show_all;

        #  toggle button to trigger callbacks
        $tree_check_button->set_active(1);
        $tree_check_button->set_active(0);
        $skip_check_button->set_active(1);


        my $response = $dlg->run;
        if ($response ne 'ok') {
            $dlg->destroy;
            croak 'User cancelled operation';
        }

        if ($tree_check_button->get_active) {
            my $iter = $tree_combo->get_active_iter;
            my $selected_tree = $tree_combo->get_model->get($iter, 1);
            if (defined $selected_tree) {
                my $tree_prop = $prop_combo->get_active_text;
                my %range_hash;
                my $warn_count = 0;
              NODE_REF:
                foreach my $node_ref ($selected_tree->get_node_refs) {
                    my $booter = $node_ref->get_bootstrap_block_or_undef;
                    if (!defined $booter) {
                        #  We could croak but tree trimming might
                        #  take care of the missing ones.
                        if ($warn_count < 11) {
                            my $node_name = $node_ref->get_name;
                            say STDERR "Tree node $node_name does not have a value for $tree_prop "
                                . "(only the first ten cases will be listed)";
                            $warn_count++;
                        }
                        next NODE_REF;
                    }
                    $range_hash{$node_ref->get_name} = $booter->get_value_aa($tree_prop);
                }
                $results{node_range_hash} = \%range_hash;
            }
        }
        elsif ($file_check_button->get_active) {
            $results{node_range_hash} = $range_hash_from_file;
        }
        elsif ($output_check_button->get_active) {
            my $iter = $from_outputs_combo->get_active_iter;
            my $selection = $from_outputs_combo->get_model->get($iter, 1);
            $results{node_range_hash} = $selection;
        }


        $dlg->destroy;
    }


    return wantarray ? %results : \%results;
}

#  ideally we would check required nbrs etc as well
sub get_extra_calc_options {
    my ($self, %args) = @_;

    $args{calculations} //= $args{spatial_calculations};

    my $indices_object = Biodiverse::Indices->new(
        BASEDATA_REF => $self->{basedata_ref},
        NAME         => 'Indices for checking options',
    );

    #  step is needed here?
    $indices_object->get_valid_calculations(
        %args,
        nbr_list_count     => 2,
        element_list1      => [], #  for validity checking only
        element_list2      => [],
        processing_element => 'x',
    );

    my $pre_calc_globals = $indices_object->get_pre_calc_global_list;

    my $extra_calc_options = $self->run_dlg_extra_calc_options (calcs => $pre_calc_globals);

    return wantarray ? %$extra_calc_options : $extra_calc_options;
}

sub load_range_table_as_hash {
    my ($self, %args) = @_;

    my $max_cols_to_show = $args{max_cols_to_show} || 100;

    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $project = $gui->get_project;

    # Get filename for the name-translation file
    my $filename //= $gui->show_open_dialog(
        title       => "Select file",
        suffix      => '*',
    );

    return wantarray ? () : {} if !defined $filename;

    my $remap = Biodiverse::ElementProperties->new;
    my $csv   = $remap->get_csv_object_using_guesswork(fname => $filename);
    my $remap_args = $remap->get_args (
        sub              => 'import_data',
        input_sep_char   => $csv->sep_char,
        input_quote_char => $csv->quote_char,
    );
    my $params     = $remap_args->{parameters};

    #  much of the following is used elsewhere to get file options, almost verbatim.  Should move to a sub.
    my $dlgxml = Gtk3::Builder->new();
    $dlgxml->add_from_file( $gui->get_gtk_ui_file('dlgImportParameters.ui') );
    my $dlg = $dlgxml->get_object('dlgImportParameters');
    $dlg->set_title( "File options" );

    # Build widgets for parameters
    my $table_name = 'tableImportParameters';
    my $table      = $dlgxml->get_object($table_name);

    # (passing $dlgxml because generateFile uses existing widget on the dialog)
    my $parameters_table = Biodiverse::GUI::ParametersTable->new;
    my $extractors = $parameters_table->fill( $params, $table, $dlgxml );

    $dlg->show_all;
    $gui->move_dlg_to_same_monitor_as_other($dlg);

    my $response = $dlg->run;
    $dlg->destroy;

    return wantarray ? () : {} if $response ne 'ok';

    my $properties_params = $parameters_table->extract($extractors);
    my %properties_params = @$properties_params;

    # Get header columns
    say "[GUI] Discovering columns from $filename";

    my $input_fh = Biodiverse::Common->get_file_handle (
        file_name => $filename,
        use_bom   => 1,
    );

    my ( $line, $line_unchomped );
    while (<$input_fh>) {    # get first non-blank line
        $line           = $_;
        $line_unchomped = $line;
        $line =~ s/[\r\n]+$//;
        last if $line;
    }
    close($input_fh);

    #  we should inherit from Biodiverse::Common, but not until that has been subdivided into smaller units.
    my $csv_obj = $project->get_csv_object_using_guesswork(
        fname      => $filename,
        quote_char => $properties_params{input_quote_char},
        sep_char   => $properties_params{input_sep_char},
    );

    my @headers_full = $project->csv2list(
        string     => $line_unchomped,
        csv_object => $csv_obj,
    );

    my @headers = map { $_ // '{null}' }
        @headers_full[ 0 .. min( $#headers_full, $max_cols_to_show - 1 ) ];


    my $required_cols = [qw/node_name range/];

    state %explain = (
        Ignore    => 'There is no setting for this column.  It will be ignored.',
        node_name => 'Name of the node',
        range     => 'Range value',
    );


    ( $dlg, my $col_widgets ) = Biodiverse::GUI::BasedataImport::make_remap_columns_dialog(
        header           => \@headers,
        wnd_main         => $gui->get_main_window,
        # other_props      => $other_properties,
        column_overrides => $required_cols,
    );

    my $column_settings = {};
    $dlg->set_title( "Specify columns" );

    RUN_DLG:
    while (1) {
        $response = $dlg->run();
        if ( $response eq 'ok' ) {
            $column_settings =
                Biodiverse::GUI::BasedataImport::get_remap_column_settings( $col_widgets, \@headers );
        }
        elsif ( $response eq 'help' ) {
            Biodiverse::GUI::BasedataImport::show_expl_dialog( \%explain, $dlg );
            next RUN_DLG;
        }
        else {
            $dlg->destroy();
            return wantarray ? () : {};
        }

        #  drop out
        last RUN_DLG if all { $column_settings->{$_} && @{$column_settings->{$_}} == 1 } @$required_cols;

        #  need to check we have the right number...
        my $text = 'Invalid columns chosen.  Must have one (and only one) of each of: '
                . join ' ', @$required_cols;
        my $msg = Gtk3::MessageDialog->new(
            $gui->get_main_window,
            'modal',
            'error', 'ok', $text
        );

        $msg->run();
        $msg->destroy();
    }

    $dlg->destroy();

    #  column settings should be an object
    my $node_name_col = $column_settings->{node_name}[0]{name};
    my $range_col     = $column_settings->{range}[0]{name};

    my %range_data;
    my $fh = Biodiverse::Common->get_file_handle (
        file_name => $filename,
        use_bom   => 1,
    );
    $csv_obj->column_names (@headers_full);
    my $data = $csv_obj->getline_hr_all ($fh);
    shift @$data;  #  header
    foreach my $row (@$data) {
        $range_data{$row->{$node_name_col}} = $row->{$range_col};
    }

    my %results = (filename => $filename, data => \%range_data);

    return wantarray ? %results : \%results;
}


sub setup_calc_options_widgets {
    my ($self) = @_;

    my $options_label = Gtk3::Label->new('Options:');
    $options_label->set_xalign(0);
    my $chk_range = Gtk3::CheckButton->new_with_label ('Specify node range sizes');
    my $tooltip_text =<<~EOT
        Use node range sizes from another source instead of calculating the union of tip ranges.
        If a calculation that requires node ranges is selected then a popup window will allow
        selection of the source when the analysis is run.
        EOT
    ;
    $chk_range->set_tooltip_text ($tooltip_text);

    my $opt_box = Gtk3::Box->new('horizontal', 10);
    $opt_box->pack_start ($options_label, 0, 0, 0);
    $opt_box->pack_start($chk_range, 0, 0, 0);
    $opt_box->set_halign ('start');
    $opt_box->show_all;

    my $calc_tree
        = $self->get_xmlpage_object('treeCalculations')
        || $self->get_xmlpage_object('treeSpatialCalculations');
    my $scrolled_window = $calc_tree->get_parent;
    $scrolled_window->remove($calc_tree);
    my $vbox = Gtk3::Box->new ('vertical', 0);
    $vbox->pack_start ($opt_box, 0, 0, 0);
    my $lbl_calcs = Gtk3::Label->new('Calcs:');
    $lbl_calcs->set_halign('start');
    $vbox->pack_start ($lbl_calcs, 0, 0, 0);
    $vbox->pack_start ($calc_tree, 1, 1, 0);
    $scrolled_window->add($vbox);
    $scrolled_window->show_all;

    my $extractor_cb = sub {
        my %res = (
            get_node_range_hash => $chk_range->get_active,
        );
        return wantarray ? %res : \%res;
    };

    $self->{calc_options_cb} = $extractor_cb
}


sub on_show_hide_parameters_table {
    my ($self, $expander) = @_;

    #  This is triggered immediately before the expansion state is changed,
    #  so use negated value.
    my $active = !$expander->get_expanded;

    my $table = $self->get_table_widget;

    $table->set_visible ($active);

    return;
}

1;
