package Biodiverse::GUI::Canvas;

use strict;
use warnings;
use 5.036;

our $VERSION = '4.99_002';

use experimental qw /refaliasing declared_refs for_list/;
use Glib qw/TRUE FALSE/;
use List::Util qw /min max/;
use List::MoreUtils qw /minmax/;
use Scalar::Util qw/weaken blessed/;
use Ref::Util qw /is_arrayref/;
use POSIX qw /floor/;
use Carp qw /croak confess/;

use Time::HiRes qw/time/;

use constant COLOUR_WHITE => Gtk3::Gdk::RGBA::parse('white');


sub new {
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;

    $self->{mode} = 'select';
    $self->{dims}{scale} //= 1;

    #############################
    ##
    ## Add some signals and connect the drawing area to the window
    ##
    my $drawable = $self->{drawable} // die 'Need a GtkDrawable to attach to';

say STDERR "SETTING EVENTS on $drawable";
    $drawable->add_events(
        [ qw/
            exposure-mask
            leave-notify-mask
            button-press-mask
            button-release-mask
            pointer-motion-mask
            pointer-motion-hint-mask
        / ]
    );

    $drawable->signal_connect(draw => sub {$self->cairo_draw (@_)});
    $drawable->signal_connect(motion_notify_event => sub {$self->on_motion (@_)});
    $drawable->signal_connect(button_press_event => sub {$self->on_button_press (@_)});
    $drawable->signal_connect(button_release_event => sub {$self->on_button_release (@_)});
    # $drawable->signal_connect(key_press_event => sub {$self->on_key_press (@_)});
    # $drawable->signal_connect(
    #     event => sub {
    #         my ($widget, $event) = @_; say "Got event " . $event; return FALSE
    #     }
    # );

    $self->{callbacks} = {};

    #  Dodgy but cannot get drawing area to work with key press events.
    #  Might not matter in the end as Biodiverse handles this for all panes
    #  so it will be set for a parent tab.
    # say STDERR "Window is $self->{window}";
    # $self->{window}->add_events(
    #     [ qw/
    #         key-press-event
    #     / ]
    # );
    # $self->{window}->signal_connect (key_press_event => sub {
    #     # my ($widget, $event) = @_;
    #     # say $event->type, ' ', $event->keyval, ' ', $event->state;
    #     $self->on_key_press (@_);
    # });

    $self->init_legend(%args);

    return $self;
}

sub set_parent_tab {
    my ($self, $tab) = @_;
    #  store under {page} for now as many places access this directly
    $self->{page} = $tab;
    weaken $self->{page};
    return;
}

sub dump_self {
    my $self = shift;
    use DDP;
    delete local $self->{data};
    p $self;
}

sub xmax {
    $_[0]->{dims}{xmax};
}
sub ymax {
    $_[0]->{dims}{ymax};
}
sub xmin {
    $_[0]->{dims}{xmin};
}
sub ymin {
    $_[0]->{dims}{ymin};
}

sub drawable {
    $_[0]->{drawable};
}

sub set_legend_mode {}

sub init_legend {
    my $self = shift;
    use Biodiverse::GUI::Canvas::Legend;
    return $self->{legend} = Biodiverse::GUI::Canvas::Legend->new(@_);
}

sub get_legend {
    my $self = shift;
    return $self->{legend} // die 'Legend not initialised';
}

sub show_legend {
    my $self = shift;
    say STDERR "$self->show_legend not implemented yet";
    return;
}

sub update_legend {
    my $self = shift;
    say STDERR "$self->update_legend not implemented yet";
    return;
}



sub get_colour_for_undef {
    my $self = shift;
    my $colour_none = shift;

    return $self->{colour_none} // $self->set_colour_for_undef ($colour_none);
}

sub set_colour_for_undef {
    my ($self, $colour) = @_;

    $colour //= COLOUR_WHITE;

    croak "Colour argument must be a Gtk3::Gdk::Color or Gtk3::Gdk::Color::RGBA object\n"
        if not blessed ($colour) =~ /Gtk3::Gdk::(Color|RGBA)/;

    $self->{colour_none} = $colour;
}


sub get_event_xy_from_mx {
    my ($self, $event, $mx, $offsets) = @_;

    $mx //= $self->{matrix};

    $offsets //= $self->{px_offsets} // [0, 0];

    my $draw_size = $self->{drawable}->get_allocation();

    #  invert a copy so we get the same coords as from $cx
    #  but why must it be inverted?
    $mx = $self->clone_tfm_mx($mx); # work on a copy
    $mx->invert;

    my ($ex, $ey);
    if (blessed $event) {
        $ex = $event->x;
        $ey = $event->y;
    }
    elsif (is_arrayref ($event)) {
        ($ex, $ey) = @$event;
    }
    else {
        croak "Cannot handle the event argument, neither an object nor an array ref";
    }

    #  account for window margins and canvas offsets
    my ($x, $y) = $mx->transform_point(
        $ex + $draw_size->{x} - $offsets->[0],
        $ey + $draw_size->{y} - $offsets->[1],
    );

    return ($x, $y);
}

#  from a cairo context
sub get_event_xy {
    my ($self, $event, $cx) = @_;
    $cx //= $self->{cairo_context};

    my $draw_size = $self->{drawable}->get_allocation();

    $cx->set_matrix($self->{matrix});

    #  This will have been set when get_tfm_mx was called.
    #  See get_tfm_mx for why it is sometimes needed.
    my ($off_x, $off_y) = @{$self->{px_offsets} // [0,0]};

    my ($x, $y) = $cx->device_to_user(
        $event->x + $draw_size->{x} - $off_x, #  account for window margins
        $event->y + $draw_size->{y} - $off_y,
    );

    return ($x, $y);
}

sub set_cursor_from_name {
    my ($self, $name) = @_;
    my $window = $self->{window}->get_window;
    my $display = $window->get_display;

    my $cursor = Gtk3::Gdk::Cursor->new_from_name ($display, $name // 'pointer');
    return $window->set_cursor($cursor);
}

sub set_mode_from_char {
    my ($self, $mode_char) = @_;

    return if !defined $mode_char;

    state %modes = (
        z => 'zoom_in',
        x => 'zoom_out',
        c => 'pan',
        s => 'select',
        v => 'zoom_fit',
    );

    my $mode = $modes{$mode_char};

    return if !defined $mode || $self->get_mode eq $mode;

    return $self->set_mode ($mode);
}

sub get_mode {
    my ($self) = @_;
    return $self->{mode};
}

sub set_mode {
    my ($self, $mode) = @_;

    state %cursor_names = (
        select     => 'default',
        zoom_in    => 'zoom-in',
        zoom_out   => 'zoom-out',
        zoom_fit   => 'zoom-fit-best',
        pan        => 'fleur',
    );

    $mode //= 'undef';
    $mode = lc $mode;
    $mode =~ s/zoom([a-z])/zoom_$1/;  #  ZoomIn -> zoom_in etc
    warn "Unsupported Canvas mode $mode" if !defined $cursor_names{$mode};

    return if !defined $mode || $self->get_mode eq $mode || !$cursor_names{$mode};

    $self->{mode} = $mode;
    $self->update_cursor($cursor_names{$mode});

    say "Mode is now $self->{mode}";

    return;
}

sub update_cursor {
    my ($self, $new_cursor_name, $cursor_key) = @_;
    $cursor_key //= 'current_cursor';

    my $current_cursor_name = $self->{$cursor_key} //= 'default';

    if ($current_cursor_name ne $new_cursor_name) {
        #  change mouse style
        $self->set_cursor_from_name ($new_cursor_name);
        $self->{$cursor_key} = $new_cursor_name;
    }

    return;
}

sub callback_order {
    my $self = shift;
    #  default to sorting lexically
    return sort keys %{$self->{callbacks}};
}


sub in_select_mode {
    my $self = shift;
    return $self->{mode} eq 'select'
}
sub in_pan_mode {
    my $self = shift;
    return $self->{mode} eq 'pan'
}
sub in_zoom_in_mode {
    my $self = shift;
    return $self->{mode} eq 'zoom_in'
}
sub in_zoom_out_mode {
    my $self = shift;
    return $self->{mode} eq 'zoom_out'
}
sub in_zoom_mode {
    my $self = shift;
    return $self->in_zoom_in_mode || $self->in_zoom_out_mode;
}
sub in_zoom_fit_mode {
    my $self = shift;
    return $self->{mode} eq 'zoom_fit'
}
#  uses box but is not panning
sub in_selectable_mode {
    my $self = shift;
    return $self->in_select_mode || $self->in_zoom_mode;
}

sub selecting {
    my $self = shift;
    $self->{selecting};
}
sub panning {
    my $self = shift;
    $self->{panning};
}

sub pan {
    my ($self, $widget, $event) = @_;

    return if !$self->{panning};

    my ($x1, $y1) = $self->get_event_xy_from_mx ($event, $self->{pan_start}{matrix});
    # say "Panning $x, $y, $x1, $y1";

    my $time = $event->time;  #  milliseconds
    $self->{last_pan_update} //= $time;
    #  disable for now due to flicker - need scrollbars again as in Biodiverse?
    #  although mouse is offset so possibly it's a matrix update issue interacting with lagged events
    #  or grab mouse pos from a parent widget? - nope
    #  https://stackoverflow.com/questions/30034714/gtk3-gtk2hs-panning-in-a-scrolledwindow-flickers
    if (1 || ($time - $self->{last_pan_update}) > 3) {
        #  need to update the display relative to start
        #  calc offset from mouse click, then adjust the display centre accordingly
        $self->{pan_start}{xcen} //= $self->{dims}{xcen};
        $self->{pan_start}{ycen} //= $self->{dims}{ycen};
        $self->{disp}{xcen} = $self->{pan_start}{xcen} + $self->{pan_start}{x} - $x1;
        $self->{disp}{ycen} = $self->{pan_start}{ycen} + $self->{pan_start}{y} - $y1;
        $self->{last_pan_update} = $time;

        $self->{matrix} = $self->get_tfm_mx;
        $widget->queue_draw;
    }

    return;
}

sub on_key_press {
    my ($self, $widget, $event, $ref_status) = @_;

    # my $char = chr $event->keyval;
    my $char = Gtk3::Gdk::keyval_name($event->keyval);
    # say "Got key event $char: " . $event->keyval;
    # say $event->state;

    # return FALSE if $event->state => [ 'control-mask' ] || $event->state >= [ 'shift-mask' ];

    # say 'Setting mode';
    $self->set_mode_from_char ($char);

    return FALSE;
}

sub on_motion {
    my ($self, $widget, $event, $ref_status) = @_;

    return FALSE if not defined $self->{cairo_context};

    if ($self->selecting) {
        #  update display if there was a function
        #  should we be deleting?
        if (defined delete $self->{highlights}) {
            $widget->queue_draw;
            return FALSE;
        }
    }
    elsif ($self->panning) {
        $self->pan ($widget, $event);
        return FALSE;
    }

    return $self->_on_motion ($widget, $event);
}

sub on_button_release {
    my ($self, $widget, $event) = @_;

    return FALSE if not defined $self->{cairo_context};

    my ($x, $y) = $self->get_event_xy($event);
    say "BR: $x, $y, ", $event->x, " ", $event->y;
    my $draw_size = $self->drawable->get_allocation();
    say "    " . join ' ', @$draw_size{qw/width height x y/};
    # say "$self->{ncells_x} $self->{ncells_y}";

    # say $event->type;
    say 'Selecting' if $self->selecting;

    if ($self->selecting) {
        $self->{selecting} = 0;
        say "BUTTON RELEASE $x, $y";
        my @rect = ($self->{sel_start_x}, $self->{sel_start_y}, $x, $y);

        delete $self->{sel_start_x};
        delete $self->{sel_start_y};
        if ($self->in_zoom_mode) {
            my $xwidth  = abs($rect[2] - $rect[0]);
            my $yheight = abs($rect[3] - $rect[1]);
            my $xcen    = ($rect[2] + $rect[0]) / 2;
            my $ycen    = ($rect[3] + $rect[1]) / 2;

            #  avoid divide by zero
            if ($xwidth && $yheight && $self->in_zoom_in_mode) {
                #  update display, clear non-specified fields
                $self->{disp} = {
                    xwidth  => $xwidth,
                    yheight => $yheight,
                    xcen    => $xcen,
                    ycen    => $ycen,
                    scale   => 1,
                };
            }
            else {
                #  point-based zoom, zoom-out is from centre of box or mouse-click
                $self->{disp}{scale} //= 1;
                $self->{disp}{scale} *= $self->in_zoom_in_mode ? 1.5 : 1 / 1.5;
                $self->{disp}{xcen} = $xcen;
                $self->{disp}{ycen} = $ycen;
            }
            $self->{matrix} = $self->get_tfm_mx;
            $widget->queue_draw;
        }
        $self->_on_button_release ($x, $y) if $self->can('_on_button_release');
    }
    elsif ($self->panning) {

        $self->pan ($widget, $event);  #  update final position

        delete $self->{pan_start};

        $self->{panning} = 0;
        say 'Pan release';
    }

    return FALSE;
}


sub on_button_press {
    my ($self, $widget, $event) = @_;

    return FALSE if not defined $self->{cairo_context};

    return 1 if $self->{selecting};

    my ($x, $y) = $self->get_event_xy($event);
    say "BP: $x, $y, ", $event->x, " ", $event->y;

    my $e_state = $event->state;
    if ($e_state >= [ 'control-mask' ] && $e_state >= [ 'shift-mask' ]) {  #  for debug until we get things hooked up properly
        if ($self->in_pan_mode) {
            say 'EXITING PAN MODE';
            $self->set_mode_from_char('s');
        }
        else {
            say 'GOING INTO PAN MODE';
            $self->set_mode_from_char('c');
        }
    }
    elsif ($e_state >= [ 'control-mask' ] || $e_state >= [ 'shift-mask' ]) {
        # say "Event: $x, $y";
        $self->{disp}{xcen} = $x;
        $self->{disp}{ycen} = $y;
        $self->{disp}{scale} *= $e_state >= [ 'control-mask' ] ? 1 / 1.5 : 1.5;
        $self->{matrix} = $self->get_tfm_mx;
        $widget->queue_draw;
        return FALSE;
    }
    elsif ($self->in_zoom_fit_mode || $event->button == 3) {
        #  reset
        $self->reset_disp;
        $self->{matrix} = $self->get_tfm_mx;
        $widget->queue_draw;
        return FALSE;
    }
    elsif ($self->in_pan_mode && !$self->panning) {
        # ($self->{sel_start_x}, $self->{sel_start_y}) = ($event->x, $event->y);
        $self->{panning} = 1;
        say "Pan started, $x $y";
        my $ps = $self->{pan_start} = {};
        $ps->{x} = $x;
        $ps->{y} = $y;
        $ps->{xcen}   = $self->{disp}{xcen};
        $ps->{ycen}   = $self->{disp}{ycen};
        $ps->{matrix} = $self->{matrix};
        return FALSE;
    }
    elsif (not $self->selecting and $self->in_selectable_mode) {
        ($self->{sel_start_x}, $self->{sel_start_y}) = ($event->x, $event->y);
        $self->{selecting} = 1;
        say "selection started, $x $y";
        $self->{sel_start_x} = $x;
        $self->{sel_start_y} = $y;

        if ($self->in_select_mode) {
            $self->_select_while_not_selecting ($widget, $x, $y);
        }

        return FALSE;
    }


    return FALSE;
}



sub cairo_draw {
    my ($self, $widget, $context) = @_;

    #  we often need this in deeper methods and it changes each redraw
    $self->{cairo_context} = $context;
    $self->{orig_tfm_mx}   = $context->get_matrix;

    $context->set_source_rgb(0.9, 0.9, 0.7);
    $context->paint;

    #  we autosize to the drawing area when this is set each call
    $self->{matrix} = $self->get_tfm_mx($widget);
    $context->set_matrix($self->{matrix});

    my $callbacks = $self->{callbacks};
    # $self->_bounding_box_page_units($context);
    foreach my $cb (grep {defined} @{$callbacks}{$self->callback_order}) {
        if (is_arrayref $cb) {
            foreach my $_cb (@$cb) {
                $self->$_cb($context);
            }
        }
        else {
            $self->$cb($context);
        }
    }

    return FALSE;
}

sub get_tfm_mx {
    my ($self, $drawable, $noisy) = @_;

    $drawable //= $self->drawable;
    my $draw_size = $drawable->get_allocation();
    my ($canvas_w, $canvas_h, $canvas_x, $canvas_y) = @$draw_size{qw/width height x y/};

    my $disp_h = $self->{disp} //= {};
    my $dims_h = $self->{dims};

    my $xcen = $disp_h->{xcen} //= $dims_h->{xcen};
    my $ycen = $disp_h->{ycen} //= $dims_h->{ycen};

    if ($noisy) {
        my $fmt = "%9.2f %9.2f %9.2f %9.2f";
        say sprintf $fmt, $xcen, $ycen, $dims_h->{xcen}, $dims_h->{ycen};
    }

    #  Always override in case the matrix has changed from when this was last set
    #  Seems to be needed to correct for offsets with mouse clicks.  These are
    #  offset as a function of the original Cairo matrix and whatever window
    #  contents are around the DrawingArea.
    delete $self->{px_offsets};
    $self->{px_offsets} = [$self->get_event_xy_from_mx ([0, 0], $self->{orig_tfm_mx}), [0,0]];

    my $mx = $self->clone_tfm_mx($self->{orig_tfm_mx});

    ($canvas_x, $canvas_y) = (0,0);  #  no longer needed below
    my ($off_x, $off_y)    = (0,0);

    # centre on 0,0 allowing for window edges
    $mx->translate(
        $canvas_x + $canvas_w / 2 - $off_x,
        $canvas_y + $canvas_h / 2 - $off_y,
    );

    #  rescale, including zoom
    $mx->scale($self->get_scale_factors);

    #  and shift to display centre
    $mx->translate(-$xcen, -$ycen);

    return $mx;
}

sub get_identity_tfm_mx {
    Cairo::Matrix->init_identity;
}

sub clone_tfm_mx {
    my ($self, $mx) = @_;
    $mx //= $self->{matrix};
    return $mx->multiply (Cairo::Matrix->init_identity);
}

sub get_scale_factors {
    my ($self, $drawable) = @_;

    $drawable //= $self->drawable;

    my $draw_size = $drawable->get_allocation();
    my ($canvas_w, $canvas_h) = @$draw_size{qw/width height/};

    #  The buffer should be a 5% margin or similar of the scale factor
    #  but is used in the transforms so needs to be in map units
    my $buffer_frac = $self->{buffer_frac} //= 1.1;

    my $disp_h = $self->{disp} //= $self->{dims};
    my $dims_h = $self->{dims};
    $disp_h->{xwidth}  //= $dims_h->{xwidth};
    $disp_h->{yheight} //= $dims_h->{yheight};

    my @scale_factors = (
        $canvas_w / ($disp_h->{xwidth}  * $buffer_frac),
        $canvas_h / ($disp_h->{yheight} * $buffer_frac)
    );
    if ($self->maintain_aspect_ratio) {
        my $sc = min (@scale_factors);
        @scale_factors = ($sc, $sc);
    }
    if ($self->plot_bottom_up) {
        $scale_factors[1] *= -1;
    }

    #  rescale
    my $zoom_factor = $disp_h->{scale} //= 1;
    if ($zoom_factor) {
        @scale_factors = map {$zoom_factor * $_ } @scale_factors;
    }

    return @scale_factors;
}

#  no aspect ratio by default
sub maintain_aspect_ratio {!!0};

#  plot top-down by default
sub plot_bottom_up {!!0};

sub reset_disp {
    my $self = shift;
    $self->{disp} = { %{$self->{dims}} };
}

sub rgb_to_array {
    my ($self, $colour) = @_;
    if (!defined $colour) {
        warn '$colour is undef';
        warn caller();
        return (0,0,0);
    }
    elsif (!blessed $colour) {
        warn '$colour is not an object: ' . $colour;
        return (0,0,0);
    }
    my $col = $colour->to_string;
    if ($col =~ /rgb\((.+)\)/) {
        my @rgb = split ',', $1;
        return map {$_ / 255} @rgb;
    }
    return $colour;  #  do nothing
}

1;
