package Biodiverse::GUI::Tabs::Tab;
use strict;
use warnings;
use 5.036;

our $VERSION = '4.99_008';

use List::Util qw/min max/;
use Scalar::Util qw /blessed/;
use List::MoreUtils qw /minmax/;
use Gtk3;
use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;
use Carp;
use Sort::Key::Natural qw /natsort/;
use Ref::Util qw /is_arrayref/;

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
        undef,
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
        (Time::HiRes::time - $self->get_last_hotkey_event_time) < 0.1;
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

my %key_tool_map = (
    Z => 'ZoomIn',
    X => 'ZoomOut',
    C => 'Pan',
    V => 'ZoomFit',
    B => 'Select',
    S => 'Select',
);

# Default for tabs that don't implement on_bare_key
sub on_bare_key {
    my ($self, $key, $event) = @_;

    my $active_pane = $self->{active_pane};
    return if !$active_pane;

    #  early return if key presses are too quick
    return if $self->check_hot_key_double_pump;

    $self->set_last_hotkey_event_time;

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
    );

    my $inst_meth  = $instant_key_methods{$key}
        // ($self->{tool} =~ /Zoom/ and $instant_zoom_methods{$key});

    if ($inst_meth) {
        $active_pane->$inst_meth;
    }
    else {
        # TODO: Add other tools and stop requiring upper case
        my $tool = $key_tool_map{uc $key};
        $self->choose_tool($tool) if defined $tool;
    }

    return;
}

#  a default list
sub get_canvas_list {
    qw /grid dendrogram/;
}

#  redraw all our canvases
sub queue_draw {
    my ($self) = @_;
    foreach my $canvas_name ($self->get_canvas_list) {
        $self->{$canvas_name}->queue_draw;
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

    my $old_tool = $self->{tool};

    if ($old_tool) {
        #  should really edit the ui files so they use the same names
        state %widget_suffixes = (
            'Biodiverse::GUI::Tabs::Labels'        => 'VL',
            'Biodiverse::GUI::Tabs::Clustering'    => 'CL',
            'Biodiverse::GUI::Tabs::Spatial'       => 'SP',
            'Biodiverse::GUI::Tabs::SpatialMatrix' => 'SP',
        );
        my $class = blessed $self;
        my $suffix = $widget_suffixes{$class} // die "Unknown tab class $class";

        $self->{ignore_tool_click} = 1;
        my $widget = $self->get_xmlpage_object("btn${old_tool}Tool${suffix}");
        $widget->set_active(0);
        my $new_widget = $self->get_xmlpage_object("btn${tool}Tool${suffix}");
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

    my $dialog = Gtk3::ColorSelectionDialog->new ('Select a colour');
    my $selector = $dialog->get_color_selection;

    if ($colour) {
        if ($colour->isa('Gtk3::Gdk::Color')) {
            $selector->set_current_color($colour);
        }
        else {
            $selector->set_current_rgba($colour);
        }
    }

    if ($dialog->run eq 'ok') {
        $colour = $selector->get_current_rgba;
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
        undef,
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
            $menu_item->set_active($item->{active});
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

sub get_tree_menu_item {
    my ($self, $wanted) = @_;

    state $tooltip_select_by = <<EOT
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
            self_key => 'checkbox_show_tree_legend',
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
    };

    my $item = $items->{$wanted};
    croak "Cannot find tree menu item item $wanted"
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


1;
