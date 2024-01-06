package Biodiverse::GUI::Tabs::Tab;
use strict;
use warnings;
use 5.010;

our $VERSION = '4.99_001';

use List::Util qw/min max/;
use Scalar::Util qw /blessed/;
use List::MoreUtils qw /minmax/;
use Gtk2;
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
            
            $iter_output = $model->iter_next($iter_output);
        }
        
        last if $iter; # break if found it
        $iter_base = $model->iter_next($iter_base);
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

    my $dialog = Gtk2::MessageDialog->new (
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

my $snooper_id;
my $handler_entered = 0;

# Called when user switches to this tab
#   installs keyboard-shortcut handler
sub set_keyboard_handler {
    my $self = shift;
    # Make CTRL-G activate the "go!" button (on_run)
    if ($snooper_id) {
        ##print "[Tab] Removing keyboard snooper $snooper_id\n";
        Gtk2->key_snooper_remove($snooper_id);
        $snooper_id = undef;
    }


    $snooper_id = Gtk2->key_snooper_install(\&hotkey_handler, $self);
    ##print "[Tab] Installed keyboard snooper $snooper_id\n";
}

sub remove_keyboard_handler {
    my $self = shift;
    if ($snooper_id) {
        ##print "[Tab] Removing keyboard snooper $snooper_id\n";
        Gtk2->key_snooper_remove($snooper_id);
        $snooper_id = undef;
    }
}
    
# Processes keyboard shortcuts like CTRL-G = Go!
sub hotkey_handler {
    my ($widget, $event, $self) = @_;
    my $retval;

    # stop recursion into on_run if shortcut triggered during processing
    #   (this happens because progress-dialogs pump events..)

    return 1 if $handler_entered == 1;

    $handler_entered = 1;

    if ($event->type eq 'key-press' && Biodiverse::GUI::GUIManager::keyboard_snooper_active) {
        # if CTL- key is pressed
        if ($event->state >= ['control-mask']) {
            my $keyval = $event->keyval;
            #print $keyval . "\n";
            
            # Go!
            if ((uc chr $keyval) eq 'G') {
                $self->on_run();
                $retval = 1; # stop processing
            }

            # Close tab (CTRL-W)
            elsif ((uc chr $keyval) eq 'W') {
                if ($self->get_removable) {
                    $self->{gui}->remove_tab($self);
                    $retval = 1; # stop processing
                }
            }

            # Change to next tab
            elsif ($keyval eq Gtk2::Gdk->keyval_from_name ('Tab')) {
                #  switch tabs
                #print "keyval is $keyval (tab), state is " . $event->state . "\n";
                my $page_index = $self->get_page_index;
                $self->{gui}->switch_tab (undef, $page_index + 1); #  go right
            }
            elsif ($keyval eq Gtk2::Gdk->keyval_from_name ('ISO_Left_Tab')) {
                #  switch tabs
                #print "keyval is $keyval (left tab), state is " . $event->state . "\n";
                my $page_index = $self->get_page_index;
                $self->{gui}->switch_tab (undef, $page_index - 1); #  go left
            }
        }
        elsif ($event->state == []) {
            # Catch alphabetic keys only for now.
            my $keyval = $event->keyval;
            if (($keyval >= ord('a') && $keyval <= ord('z')) or (
                    $keyval >= ord('A') && $keyval <= ord('Z'))) {
                $self->on_bare_key(uc chr $event->keyval);
            }
        }
    }

    $handler_entered = 0;
    $retval = 0; # continue processing
    return $retval;
}

######################################
#  Other stuff


sub on_run {} # default for tabs that don't implement on_run

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
    my ($self, $keyval) = @_;
    # TODO: Add other tools
    my $tool = $key_tool_map{$keyval};

    return if not defined $tool;

    my $active_pane = $self->{active_pane};

    return if !defined $active_pane;

    if ($tool eq 'ZoomOut' and $active_pane ne '') {
        # Do an instant zoom out and keep the current tool.
        $self->{$self->{active_pane}}->zoom_out();
    }
    elsif ($tool eq 'ZoomFit' and $active_pane ne '') {
        $self->{$self->{active_pane}}->zoom_fit();
    }
    elsif ($active_pane) {
        $self->choose_tool($tool) if exists $key_tool_map{$keyval};
    }
}

sub choose_tool {}

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
    my $self = shift;
    my $menu_item = shift;

    my $grid = $self->{grid};

    return if !$grid;

    my $active = $menu_item->get_active;

    if ($active) {
        $grid->show_legend;
        $grid->set_legend_min_max;
        $grid->update_legend;
    }
    else {
        $grid->hide_legend;
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

sub index_is_zscore {
    my $self = shift;
    my %args = @_;

    #  check list and then check index

    my $list = $args{list} // '';

    return 1
        if $list =~ />>z_scores>>/;

    state $bd_obj = Biodiverse::BaseData->new (
        NAME         => 'zscorage',
        CELL_SIZES   => [1],
        CELL_ORIGINS => [0]
    );
    state $indices_object = Biodiverse::Indices->new (
        BASEDATA_REF => $bd_obj,
    );

    my $index = $args{index} // '';

    return 1
        if $indices_object->index_is_list (index => $list)
            && $indices_object->index_is_zscore (index => $list);

    return $indices_object->index_is_scalar (index => $index)
        && $indices_object->index_is_zscore (index => $index);
}

sub index_is_ratio {
    my $self = shift;
    my %args = @_;

    #  check list and then check index
    my $list  = $args{list} // '';
    my $index = $args{index} // '';

    state $bd_obj = Biodiverse::BaseData->new (
        NAME         => 'rationing',
        CELL_SIZES   => [1],
        CELL_ORIGINS => [0]
    );
    state $indices_object = Biodiverse::Indices->new (
        BASEDATA_REF => $bd_obj,
    );

    return 1
        if $indices_object->index_is_list (index => $list)
            && $indices_object->index_is_ratio (index => $list);

    return $indices_object->index_is_ratio (index => $index);
}

sub index_is_divergent {
    my $self = shift;
    my %args = @_;

    #  check list and then check index
    my $list  = $args{list} // '';
    my $index = $args{index} // '';

    state $bd_obj = Biodiverse::BaseData->new (
        NAME         => 'divergency',
        CELL_SIZES   => [1],
        CELL_ORIGINS => [0]
    );
    state $indices_object = Biodiverse::Indices->new (
        BASEDATA_REF => $bd_obj,
    );

    return 1
        if $indices_object->index_is_list (index => $list)
            && $indices_object->index_is_divergent (index => $list);

    return $indices_object->index_is_divergent (index => $index);
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
            my $colour_dialog = Gtk2::ColorSelectionDialog->new('Pick Hue');
            my $colour_select = $colour_dialog->get_color_selection();
            if (my $col = $self->{hue}) {
                $colour_select->set_previous_color($col);
                $colour_select->set_current_color($col);
            }
            $colour_dialog->show_all();
            my $response = $colour_dialog->run;
            if ($response eq 'ok') {
                $self->{hue} = $colour_select->get_current_color();
                $self->{grid}->set_legend_hue($self->{hue});
                eval {$self->{dendrogram}->recolour(all_elements => 1)};  #  only clusters have dendrograms - needed here?  recolour below does this
            }
            $colour_dialog->destroy();
        }

        $self->set_colour_mode($mode);
    }

    $self->{grid}->set_legend_mode($self->get_colour_mode);
    $self->recolour(all_elements => 1);
    $self->{grid}->update_legend;

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

sub rect_canonicalise {
    my ($self, $rect) = @_;
    ($rect->[0], $rect->[2]) = minmax ($rect->[2], $rect->[0]);
    ($rect->[1], $rect->[3]) = minmax ($rect->[3], $rect->[1]);
}

sub rect_centre {
    my ($self, $rect) = @_;
    return (($rect->[0] + $rect->[2]) / 2, ($rect->[1] + $rect->[3]) / 2);
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

my %cursor_icons = (
    Select  => undef,
    ZoomIn  => 'zoom-in',
    ZoomOut => 'zoom-out',
    ZoomFit => 'zoom-fit-best',
    Pan     => 'fleur',
);

sub set_display_cursors {
    my $self = shift;
    my $type = shift;

    my $icon = $cursor_icons{$type};
    
    foreach my $widget (qw /grid matrix_grid dendrogram/) {
        no autovivification;
        my $wref = $self->{$widget};
        next if !$wref || !$wref->{canvas};

        my $window = $wref->{canvas}->window;
        my $cursor;
        if ($icon) {
            #  check if it's a real cursor
            $cursor = eval {Gtk2::Gdk::Cursor->new ($icon)};
            if ($@) {  #  might need to come from an icon
                my $cache_name = "ICON: $icon";
                $cursor = $self->get_cached_value ($cache_name);
                if (!$cursor) {
                    my $ic = Gtk2::IconTheme->new();
                    my $pixbuf = eval {$ic->load_icon($icon, 16, 'no-svg')};
                    if ($@) {
                        warn $@;
                    }
                    else {
                        my $display = $window->get_display;
                        $cursor = Gtk2::Gdk::Cursor->new_from_pixbuf($display, $pixbuf, 0, 0);
                        $self->set_cached_value ($cache_name => $cursor);
                    }
                }
            }
        }
        $window->set_cursor($cursor);
        $wref->{cursor} = $cursor;
    }
    
}


sub on_grid_select {
    my ($self, $groups, $ignore_change, $rect) = @_;
    if ($self->{tool} eq 'ZoomIn') {
        my $grid = $self->{grid};
        $self->handle_grid_drag_zoom($grid, $rect);
    }
}

sub on_grid_click {
    my $self = shift;
    if ($self->{tool} eq 'ZoomOut') {
        $self->{grid}->zoom_out();
    }
    elsif ($self->{tool} eq 'ZoomFit') {
        $self->{grid}->zoom_fit();
    }
}


sub handle_grid_drag_zoom {
    my ($self, $grid, $rect) = @_;
    my $canvas = $grid->{canvas};

    $self->rect_canonicalise ($rect);

    # Scale
    my $width_px  = $grid->{width_px}; # Viewport/window size
    my $height_px = $grid->{height_px};
    my ($xc, $yc) = $canvas->world_to_window($self->rect_centre ($rect));
    #print "Centre: $xc $yc\n";
    my ($x1, $y1) = $canvas->world_to_window($rect->[0], $rect->[1]);
    my ($x2, $y2) = $canvas->world_to_window($rect->[2], $rect->[3]);
    #say "Window Rect: $x1 $x2 $y1 $y2";
    my $width_s   = max ($x2 - $x1, 1); # Selected box width
    my $height_s  = max ($y2 - $y1, 1); # Avoid div by 0

    # Special case: If the rect is tiny, the user probably just clicked
    # and released. Do something sensible, like just double the zoom level.
    if ($width_s <= 2 || $height_s <= 2) {
        $width_s  = $width_px  / 2;
        $height_s = $height_px / 2;
        ($rect->[0], $rect->[1])
            = $canvas->window_to_world ($xc - $width_s / 2, $yc - $height_s / 2);
        ($rect->[2], $rect->[3])
            = $canvas->window_to_world ($xc + $width_s / 2, $yc + $height_s / 2);
    }

    my $ratio = min ($width_px / $width_s, $height_px / $height_s);

    if (exists $grid->{render_width}) {  #  should shift this into a method in Dendrogram.pm

        my @plot_centre = ($width_px  / 2, $height_px  / 2);
        my @rect_centre = $self->rect_centre ($rect);

        my ($dx, $dy) = ($plot_centre[0] - $rect_centre[0], $plot_centre[1] - $rect_centre[1]);

        # Convert into scaled coords
        $grid->{centre_x} *= $grid->{length_scale};
        $grid->{centre_y} *= $grid->{height_scale};
        
        # Pan across
        $grid->{centre_x} = $grid->clamp (
            $grid->{centre_x} - $dx,
            0,
            $grid->{render_width},
        ) ;
        $grid->{centre_y} = $grid->clamp (
            $grid->{centre_y} - $dy,
            0,
            $grid->{render_height},
        );

        # Convert into world coords
        $grid->{centre_x} /= $grid->{length_scale};
        $grid->{centre_y} /= $grid->{height_scale};

        #  now adjust the zoom level
        $grid->{render_width}  *= $ratio;
        $grid->{render_height} *= $ratio;

        $grid->set_zoom_fit_flag(0);  #  don't zoom to all when the window gets resized
        $grid->post_zoom;
        return;
    }


    my $oppu = $canvas->get_pixels_per_unit;
    #say "Old PPU: $oppu";
    my $ppu = $oppu * $ratio;
    #say "New PPU: $ppu";
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
    my $window_aspect =  $width_px / $height_px;
    my $rect_aspect   = ($rect->[2] - $rect->[0]) / ($rect->[3] - $rect->[1]);
    #say "WA: $window_aspect, RA: $rect_aspect";
    #say "R: " . join ' ', @$rect;
    if ($rect_aspect > $window_aspect) {
        # 2nd case illustrated above. We need to change the height.
        my $mid    = ($rect->[1] + $rect->[3]) / 2;
        my $width  =  $rect->[2] - $rect->[0];
        $rect->[1] = $mid - 0.5 * $width / $window_aspect;
        $rect->[3] = $mid + 0.5 * $width / $window_aspect;
    }
    else {
        # 1st case illustrated above. We need to change the width.
        my $mid    = ($rect->[0] + $rect->[2]) / 2;
        my $height =  $rect->[3] - $rect->[1];
        $rect->[0] = $mid - 0.5 * $height * $window_aspect;
        $rect->[2] = $mid + 0.5 * $height * $window_aspect;
    }

    my $midx = ($rect->[0] + $rect->[2]) / 2;
    my $midy = ($rect->[1] + $rect->[3]) / 2;
    #$midx = $rect->[0];
    #$midy = $rect->[1];

    # Apply and pan
    $grid->set_zoom_fit_flag(0);  #  don't zoom to all when the window gets resized - poss should set some params to maintain the extent
    $grid->post_zoom;
    my @target = $canvas->w2c($rect->[0], $rect->[1]);
    #say "Scrolling to " . join ' ', @target;
    $canvas->scroll_to(@target);
    $grid->update_scrollbars ($midx, $midy);

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
    $colour //= Gtk2::Gdk::Color->new($g, $g, $g);

    croak "Colour argument must be a Gtk2::Gdk::Color object\n"
      if not blessed ($colour) eq 'Gtk2::Gdk::Color';

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

    my $dialog = Gtk2::ColorSelectionDialog->new ('Select a colour');
    my $selector = $dialog->colorsel;  #  get_color_selection?

    if ($colour) {
        $selector->set_current_color ($colour);
    }

    if ($dialog->run eq 'ok') {
        $colour = $selector->get_current_color;
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
        label_text => "Branch line thickness in pixels\n"
                    . 'Does not affect the vertical connectors',
        tooltip    => 'Set to zero to let the system calculate a default',
    };
    bless $props, $parameter_metadata_class;

    my $parameters_table = Biodiverse::GUI::ParametersTable->new;
    my ($spinner, $extractor) = $parameters_table->generate_integer ($props);

    my $dlg = Gtk2::Dialog->new_with_buttons (
        'Set branch width',
        undef,
        'destroy-with-parent',
        'gtk-ok' => 'ok',
        'gtk-cancel' => 'cancel',
    );

    my $hbox  = Gtk2::HBox->new;
    my $label = Gtk2::Label->new($props->{label_text});
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
        $export_menu  = Gtk2::MenuItem->new_with_label('Export');
        $menubar->append($export_menu);
        $self->{export_menu} = $export_menu;
    }

    if (!$output_ref || ($output_ref->get_param('COMPLETED') // 1) != 1) {
        #  completed == 2 for clusters analyses with matrices only
        $export_menu->set_sensitive(0);
    }
    else {
        my $submenu = Gtk2::Menu->new;
        # Get the Parameters metadata
        my $metadata = $output_ref->get_metadata (sub => 'export');
        my $format_labels = $metadata->get_format_labels;
        foreach my $label (sort keys %$format_labels) {
            next if !$label;
            my $menu_item = Gtk2::MenuItem->new($label);
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
        my $sep = Gtk2::SeparatorMenuItem->new;
        $menubar->append($sep);
        $tree_menu = Gtk2::MenuItem->new_with_label('Tree');
        $menubar->append($tree_menu);
        $self->{tree_menu} = $tree_menu;
    }

    if (($output_ref->get_param('COMPLETED') // 1) != 1) {
        #  completed == 2 for clusters analyses with matrices only
        $tree_menu->set_sensitive(0);
    }
    else {
        my $submenu = Gtk2::Menu->new;

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
        my $type = $item->{type} // 'Gtk2::MenuItem';

        if ($type eq 'submenu_radio_group') {
            #  a bit messy
            my $menu_item = Gtk2::MenuItem->new($item->{label} // ());
            if (my $tooltip = $item->{tooltip}) {
                $menu_item->set_has_tooltip(1);
                $menu_item->set_tooltip_text($tooltip);
            }
            $menu->append($menu_item);
            my $radio_submenu = Gtk2::Menu->new;
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
            $menu_item = $type->new($radio_group, $item->{label} // ());
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
                    type     => 'Gtk2::RadioMenuItem',
                    label    => 'Length',
                    event    => 'activate',
                    callback => sub {
                        my $self = shift;
                        $self->set_dendrogram_plot_mode('length'),
                    },
                },
                {
                    type     => 'Gtk2::RadioMenuItem',
                    label    => 'Depth',
                    event    => 'activate',
                    callback => sub {
                        my $self = shift;
                        $self->set_dendrogram_plot_mode('depth');
                    },
                },
            ],
        },
        group_branches_by           => {
            type    => 'submenu_radio_group',
            label   => 'Select branches by',
            tooltip => $tooltip_select_by,
            items   => [
                {
                    type     => 'Gtk2::RadioMenuItem',
                    label    => 'Length',
                    event    => 'activate',
                    callback => sub {
                        my $self = shift;
                        $self->set_dendrogram_group_by_mode('length');
                    },
                },
                {
                    type     => 'Gtk2::RadioMenuItem',
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
            type     => 'Gtk2::MenuItem',
            label    => 'Set tree branch line widths',
            tooltip  => "Set the width of the tree branches.\n"
                . "Does not affect the vertical connectors.",
            event    => 'activate',
            callback => \&on_set_tree_line_widths,
        },
        highlight_groups_on_map => {
            type     => 'Gtk2::CheckMenuItem',
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
            type     => 'Gtk2::CheckMenuItem',
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
            type     => 'Gtk2::MenuItem',
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
            type  => 'Gtk2::SeparatorMenuItem',
        },
    };

    my $item = $items->{$wanted};
    croak "Cannot find tree menu item item $wanted"
      if !$item;

    return $item;
}


1;
