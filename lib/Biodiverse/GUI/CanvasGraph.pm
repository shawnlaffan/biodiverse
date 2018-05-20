package Biodiverse::GUI::CanvasGraph;

use strict;
use warnings;
use 5.010;

use Data::Dumper;
use Carp;
use Gnome2::Canvas;
#require Biodiverse::GUI::Graphs;

use Gtk2;
use Glib qw/TRUE FALSE/;

use Scalar::Util qw(looks_like_number);
use List::Util qw(min max);

our $VERSION = '1.99_006';

use English qw { -no_match_vars };

use constant POINT_WIDTH   => 3;
use constant POINT_HEIGHT  => 3;
use constant CANVAS_WIDTH  => 200;
use constant CANVAS_HEIGHT => 200;
use constant NUMBER_OF_AXIS_LABELS => 4;
# gap from the bottom of the graph to the labels
use constant X_AXIS_LABEL_PADDING => 15;
# distance from the left of the graph to the start of the label
use constant Y_AXIS_LABEL_PADDING => 15;
use constant LABEL_FONT => 'Sans 11';
# distance from the left of the graph to the start of tick marks 
use constant Y_AXIS_TICK_PADDING => 5;
# distance from the bottom of the graph to the start of tick marks 
use constant X_AXIS_TICK_PADDING => 5;
use constant TICK_LENGTH => 5; # Length of the tick marks on the x and y axis.
use constant COLOUR_BLACK        => Gtk2::Gdk::Color->new(0, 0, 0);
use constant COLOUR_GREY         => Gtk2::Gdk::Color->new(224, 224, 224);
use constant COLOUR_RED          => Gtk2::Gdk::Color->new(65535, 0, 0); # red
use constant CELL_SIZE_X         => 10;    # Cell size (canvas units)
use constant COLOUR_WHITE        => Gtk2::Gdk::Color->new(255*257, 255*257, 255*257);
use constant COLOUR_LIGHT_GREY        => Gtk2::Gdk::Color->new(240, 240, 240);
use constant INDEX_ELEMENT       => 1;  # BaseStruct element for this cell
use constant BORDER_SIZE         => 20;


my @bounds_names = qw /y_max y_min x_max x_min/;

sub new {
    my $class   = shift;
    my %args = @_;
    #my %graph_values = $args{graph_values};
    #my %graph_values = %{$args{graph_values}};

    my $self = {};
    bless $self, $class;

    my $canvas   = $args{canvas};
    my $popupobj = $args{popupobj};

    # Make the canvas and hook it up
    $self->{canvas} = $canvas;
    $self->{canvas}->signal_connect_swapped (size_allocate => \&on_size_allocate, $self);

    # Set up canvas
    $self->{canvas}->set_center_scroll_region(0);
    $self->{canvas}->show;
    $self->set_zoom_fit_flag(1);
    $self->{dragging} = 0;

    # Create background rectangle to receive mouse events for panning
    my $rect = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        y1 => 0,
        x2 => CELL_SIZE_X,
        y2 => CELL_SIZE_X,
        fill_color_gdk => COLOUR_WHITE,
    );

    $self->{canvas}->root->signal_connect_swapped (
        event => \&on_background_event,
        [$self, $popupobj],
    );
    #$rect->signal_connect (button_release_event => \&_do_popup_menu); 

    my $width  = CANVAS_WIDTH;
    my $height = CANVAS_HEIGHT; 

    # draw the black box that outlines the graph
    my $border = Gnome2::Canvas::Item->new (
        $self->{canvas}->root, 'Gnome2::Canvas::Rect',
        x1 => 0.25 * 240 - (POINT_WIDTH),
        y1 => -(POINT_HEIGHT),
        x2 => 300,   # 0.75*240+(POINT_WIDTH),
        y2 => $height + POINT_HEIGHT,
        fill_color_gdk    => COLOUR_WHITE,
        outline_color_gdk => COLOUR_WHITE
        #outline_color_gdk => COLOUR_BLACK
    );

    $border->lower_to_bottom;
    $rect->lower_to_bottom;

    $self->{width_units}  = $width  + 2 * BORDER_SIZE;
    $self->{height_units} = $height + 4 * BORDER_SIZE;

    $self->{back_rect}   = $rect;
    $self->{border_rect} = $border;

    # Make a group for the axes. 
    my $axes_group = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Group',
        x => 0,
        y => 0,
    );
    $self->{axes_group} = $axes_group;

    # add X axis line
    my $x_line = Gnome2::Canvas::Item->new (
        $self->{axes_group}, 'Gnome2::Canvas::Line',
        points => [0, $height + X_AXIS_TICK_PADDING, $width, $height + X_AXIS_TICK_PADDING],
        fill_color_gdk => COLOUR_LIGHT_GREY,
        width_units => 1
    );

    $self->{x_line} = $x_line;
    $x_line->raise_to_top();

    # add Y axis line
    my $y_line = Gnome2::Canvas::Item->new (
        $self->{axes_group}, 'Gnome2::Canvas::Line',
        points => [0 - Y_AXIS_TICK_PADDING, 0, 0 - Y_AXIS_TICK_PADDING, $height],
        fill_color_gdk => COLOUR_LIGHT_GREY,
        width_units    => 1
    );
    $self->{y_line} = $y_line;
    $y_line->raise_to_top();

    # Create the Label legend
    #my $legend = Biodiverse::GUI::Legend->new(
    #    canvas       => $self->{canvas},
    #    legend_mode  => 'Hue',  #  by default
    #    width_px     => $self->{width_px},
    #    height_px    => $self->{height_px},
    #);
    #$self->set_legend ($legend);

    #$self->update_legend;
    $self->show_ticks_marks;

    $self->resize_border_rect();
    $self->resize_background_rect();
    $self->resize_axes_group();
    #$self->resize_x_line();
    #$self->resize_y_line();
    return $self;
}

# Add the primary layer of plot values
sub add_primary_layer {
    my ($self, %args) = @_;

    my %graph_values = %{$args{graph_values}};
    return if ! %graph_values;

    my $canvas       = $args{canvas};
    my $point_colour = $args{colour} // Gtk2::Gdk::Color->new(200, 200, 255);
    
    my %bounds;
    @bounds{@bounds_names} = @args{@bounds_names};

    my ($canvas_width, $canvas_height) = (CANVAS_WIDTH, CANVAS_HEIGHT);

    # Make a group for the primary plot layer
    my $primary_group = Gnome2::Canvas::Item->new (
        $canvas->root,
        'Gnome2::Canvas::Group',
        x => 0,
        y => 0,
    );

    $self->set_primary($primary_group);

    # clean out non numeric hash entries
    foreach my $x (keys %graph_values) {
        my $y = $graph_values{$x};
        if(!looks_like_number($y) || !looks_like_number($x)) {
            delete $graph_values{$x};
        }
    }

    # scale the values so they fit nicely in the canvas space.
    my %scaled_graph_values = $self->rescale_graph_points(
        %bounds,
        old_values    => \%graph_values,
        canvas_width  => $canvas_width,
        canvas_height => $canvas_height,
    );

    # Plot the points
    $self->plot_points(
        graph_values => \%scaled_graph_values,
        canvas       => $primary_group,
        point_colour => $point_colour,
    );

    # add axis labels
    if (%graph_values){
        $self->add_axis_labels_to_graph_canvas(
            graph_values  => \%graph_values,
            canvas        => $primary_group,
            canvas_width  => $canvas_width,
            canvas_height => $canvas_height,
            %bounds,
        );
    }
    $self->set_primary($primary_group);

    $self->resize_primary_points();
    $primary_group->raise_to_top();
    $primary_group->show();
}

# Add the secondary layer of plot values
sub add_secondary_layer {
    my ($self, %args) = @_;
    my %graph_values = %{$args{graph_values}};
    my $point_colour = $args{point_colour} // COLOUR_RED;
    my $canvas       = $args{canvas};
    my %bounds;
    @bounds{@bounds_names} = @args{@bounds_names};

    my ($canvas_width, $canvas_height) = (CANVAS_WIDTH, CANVAS_HEIGHT);

    # Make a group for the secondary plot layer
    my $secondary_group = Gnome2::Canvas::Item->new (
        $canvas->root,
        'Gnome2::Canvas::Group',
        x => 0,
        y => 0,
    );

   $self->set_secondary($secondary_group);

   my $secondary = $self->get_secondary;

    # clean out non numeric hash entries
    foreach my $x (keys %graph_values) {
        my $y = $graph_values{$x};
        if(!looks_like_number($y) || !looks_like_number($x)) {
            delete $graph_values{$x};
        }
    }

    # scale the values so they fit nicely in the canvas space.
    my %scaled_graph_values = $self->rescale_graph_points(
        %bounds,
        old_values    => \%graph_values,
        canvas_width  => $canvas_width,
        canvas_height => $canvas_height,
    );

    $self->plot_points(
        graph_values => \%scaled_graph_values,
        canvas       => $secondary_group,
        point_colour => $point_colour,
    );
    

   $secondary_group->raise_to_top();
   $secondary_group->show();
   $self->resize_secondary_points();

   return $secondary_group;
}

sub plot_points {
    my ($self, %args) = @_;
    my %graph_values  = %{$args{graph_values}};
    my $point_colour  = $args{point_colour};
    my $canvas        = $args{canvas};
    my $root          = $canvas;

    my ($point_width, $point_height) = (POINT_WIDTH, POINT_HEIGHT);

    # plot the points
    foreach my $x (keys %graph_values) {
        my $y = $graph_values{$x};
        my $circle = Gnome2::Canvas::Item->new (
            $root,
            'Gnome2::Canvas::Ellipse',
            x1 => $x - $point_width,
            y1 => $y - $point_height,
            x2 => $x + $point_width,
            y2 => $y + $point_height,
            fill_color  => $point_colour,
            width_units => 1,
            outline_color => 'black',
        );
        
#        my $box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
#                                             x1 => $x-$point_width, 
#                                             y1 => $y-$point_height,
#                                             x2 => $x+$point_width,
#                                             y2 => $y+$point_height,
#                                             fill_color => $point_colour,
#                                             outline_color => $point_colour);
    }

}

sub rescale_graph_points {
    my ($self, %args) = @_;
    my $old_values    = $args{old_values};
    my $canvas_width  = $args{canvas_width};
    my $canvas_height = $args{canvas_height};

    my ($max_y, $min_y, $max_x, $min_x)
      = @args{qw /y_max y_min x_max x_min/};

    # find the max and min for the x and y axis.
    my @x_values = keys %$old_values;
    my @y_values = values %$old_values;

    return if !scalar @x_values || !scalar @y_values;

    #  this could be done better    
    $min_x //= min @x_values;
    $min_y //= min @y_values;
    my $max_x_vals = max @x_values;
    $max_x //= $max_x_vals;
    if ($max_x_vals > $max_x) {
        $max_x = $max_x_vals;
    }
    my $max_y_vals = max @y_values;
    $max_y //= $max_y_vals;
    if ($max_y_vals > $max_y) {
        $max_y = $max_y_vals;
    }

    if ($max_x == $min_x) {
        ($max_x, $min_x) = (1, 0); # stop division by 0 error
    }
    if ($max_y == $min_y) {
        ($max_y, $min_y) = (1, 0); # stop division by 0 error
    }
    
    my %new_values;
    
    # apply scaling formula
    foreach my $x (keys %$old_values) {
        my $y = $old_values->{$x};

        my $new_x = (($canvas_width)*($x-$min_x) / ($max_x-$min_x));
        my $new_y = $canvas_height - (($canvas_height)*($y-$min_y) / ($max_y-$min_y));

        $new_values{$new_x} = $new_y;
    }

    return wantarray? %new_values : \%new_values;
}

sub add_axis_labels_to_graph_canvas {
    my ($self, %args) = @_;
    my %graph_values  = %{$args{graph_values}};
    my $canvas        = $args{canvas};
    my $canvas_width  = $args{canvas_width};
    my $canvas_height = $args{canvas_height};
    my $root          = $canvas;
    my %bounds;
    @bounds{@bounds_names} = @args{@bounds_names};

    my @x_values = keys %graph_values;
    my @y_values = values %graph_values;
    #my $min_x = min @x_values;
    #my $max_x = max @x_values;
    my $min_x = $bounds{x_min};
    my $max_x = $bounds{x_max};
    my $min_y = $bounds{y_min}; # min value for the plot
    my $max_y = $bounds{y_max}; # max value for the plot
    #my $min_y = min @y_values; # min value for cell
    #my $max_y = max @y_values; # max value for cell

    # add some axis labels
    my $number_of_axis_labels = NUMBER_OF_AXIS_LABELS;

    # x axis labels
    foreach my $axis_label (0..($number_of_axis_labels-1)) {
        my $x_position = ($axis_label/($number_of_axis_labels-1)) * $canvas_width;
        my $text = ($axis_label/($number_of_axis_labels-1)) * ($max_x - $min_x) 
            + $min_x;

        # TODO Add format choice
        $text = sprintf("%.4g", $text);
        my $x_label = Gnome2::Canvas::Item->new (
            $root, 'Gnome2::Canvas::Text',
            x => $x_position,
            y => $canvas_height+X_AXIS_LABEL_PADDING,
            fill_color => 'black',
            font => LABEL_FONT,,
            anchor => 'GTK_ANCHOR_N',
            justification =>  'center',
            text => $text,
        );

    }

    # y axis labels
    foreach my $axis_label (0..($number_of_axis_labels-1)) {
        my $y_position = ($axis_label/($number_of_axis_labels-1)) * $canvas_height;
        $y_position = $canvas_height - $y_position;

        my $text = ($axis_label/($number_of_axis_labels-1)) * ($max_y - $min_y) 
            + $min_y;

        # TODO Add format choice
        $text = sprintf("%.4f", $text);
        my $y_label = Gnome2::Canvas::Item->new (
            $root, 'Gnome2::Canvas::Text',
            x => - Y_AXIS_LABEL_PADDING,
            y => $y_position,
            fill_color => 'black',
            font => LABEL_FONT,
            anchor => 'GTK_ANCHOR_E',
            justification =>  'right',
            text => $text,
        );

    }
}

# Implements resizing
sub on_size_allocate {
    my ($self, $size, $canvas) = @_;
    $self->{width_px}  = $size->width;
    $self->{height_px} = $size->height;

    if (exists $self->{width_units}) {
        if ($self->get_zoom_fit_flag) {
            $self->fit_grid();
        }
        else {
            
        }
        $self->resize_border_rect();
        $self->resize_background_rect();
        $self->resize_primary_points();
        $self->resize_axes_group();
        $self->resize_secondary_points() if $self->get_secondary;;
    }
    
    return;
}


# Resize background rectangle which is dragged for panning
sub resize_background_rect {
    my $self = shift;
    if ($self->{width_px}) {
        # Make it the full visible area
        my ($width, $height) = $self->{canvas}->c2w($self->{width_px}, $self->{height_px});
        if (not $self->{dragging}) {
            $self->{back_rect}->set(
                x2 => max($width,  $self->{width_units} // 1),
                y2 => max($height, $self->{height_units} // 1),
            );
            $self->{back_rect}->lower_to_bottom();
        }
    }
    return;
}

# Resize border rectangle
sub resize_border_rect {
    my $self = shift;
    if ($self->{width_px}) {
        # Make it centered on the visible area
        my ($width, $height) = $self->{canvas}->c2w($self->{width_px}, $self->{height_px});
        if (not $self->{dragging}) {
            $self->{border_rect}->set(
                x1 => ((max($width,  $self->{width_units})/2)  - 100 - POINT_WIDTH // 1),
                y1 => ((max($height, $self->{height_units})/2) - 100 - POINT_WIDTH // 1),
                x2 => ((max($width,  $self->{width_units})/2)  + 100 + POINT_WIDTH // 1),
                y2 => ((max($height, $self->{height_units})/2) + 100 + POINT_WIDTH // 1),
            );
            $self->{border_rect}->raise_to_top();
        }
    }
    return;
}

# Resize axes group
sub resize_axes_group {
    my $self = shift;
    if ($self->{width_px}) {
        # Make it centered on the visible area
        my ($width, $height) = $self->{canvas}->c2w($self->{width_px}, $self->{height_px});
        if (not $self->{dragging}) {
            my $axis_x = (max($width,  $self->{width_units})/2) - 100 - POINT_WIDTH;
            my $axis_y = (max($height,  $self->{height_units})/2) - 100 - POINT_WIDTH;
         
            $self->{axes_group}->set(
                x => $axis_x,
                y => $axis_y,
            );
            $self->{axes_group}->raise_to_top();
        }
    }
    return;
}

# Resize the graph primary points
sub resize_primary_points {
    my $self = shift;

    my ($x12, $y12) = $self->{border_rect}->get('x1','y1');
    $self->{primary}->set(
        x => $x12,
        y => $y12
    );
    $self->{primary}->raise_to_top();
}

# Resize the graph secondary points
sub resize_secondary_points {
    my $self = shift;

    my ($x12, $y12) = $self->{border_rect}->get('x1','y1');
    $self->{secondary}->set(
        x => $x12,
        y => $y12,
    );

    $self->{secondary}->raise_to_top();
}

sub get_zoom_fit_flag {
    my ($self) = @_;
    
    return $self->{zoom_fit};
}

sub set_zoom_fit_flag {
    my ($self, $zoom_fit) = @_;
    
    $self->{zoom_fit} = $zoom_fit;
}

sub show_ticks_marks {
    my $self = shift;

    #my ($width, $height) = $self->{canvas}->c2w($self->{width_px}, $self->{height_px});
    my ($canvas_width, $canvas_height) = (CANVAS_WIDTH, CANVAS_HEIGHT);
    my $number_of_axis_labels = NUMBER_OF_AXIS_LABELS;

    foreach my $axis_label (0..($number_of_axis_labels-1)) {
        my $x_position = ($axis_label/($number_of_axis_labels-1)) * $canvas_width;
        my $y_position = ($axis_label/($number_of_axis_labels-1)) * $canvas_height;
        $y_position = $canvas_height - $y_position;

        # Y axis tick marks
        my $y_line = Gnome2::Canvas::Item->new (
            $self->{axes_group}, 'Gnome2::Canvas::Line',
            points => [-Y_AXIS_TICK_PADDING, $y_position, -X_AXIS_TICK_PADDING - TICK_LENGTH, $y_position],
            fill_color_gdk => COLOUR_BLACK,
            width_units => 1,
        );

        # X axis tick marks
        my $x_line = Gnome2::Canvas::Item->new (
            $self->{axes_group}, 'Gnome2::Canvas::Line',
            points => [$x_position, $canvas_height+Y_AXIS_TICK_PADDING, $x_position, $canvas_height+Y_AXIS_TICK_PADDING+TICK_LENGTH],
            fill_color_gdk => COLOUR_BLACK,
            width_units => 1
      );

    }
}
# Implements panning
sub on_background_event {
    my ($array_ref, $event, $cell) = @_;
    my $self = $array_ref->[0];
    my $popupobj = $array_ref->[1];

    # Do everything with right click now.
    return if $event->type =~ m/^button-/ && $event->button != 3;
    if ($event->type eq 'button-press') {
        my $button_nr = $event->button;
        ($button_nr == 3)&& (_do_popup_menu([$self->{canvas}->root,$popupobj]));
    }
    return 0;
}


# Calculate pixels-per-unit to make image fit
sub fit_grid {
    my $self = shift;

    my $ppu_width = $self->{width_px} / $self->{width_units};
    my $ppu_height = $self->{height_px} / $self->{height_units};
    my $min_ppu = $ppu_width < $ppu_height ? $ppu_width : $ppu_height;
    $self->{canvas}->set_pixels_per_unit( $min_ppu );
    #print "[Grid] Setting grid zoom (pixels per unit) to $min_ppu\n";
    
    return;
}


sub clear_graph {
    my $self = shift;
    my $popupobj = shift;


    my $primary = $popupobj->get_primary;
    my $secondary = $popupobj->get_secondary;

    if ($popupobj->get_primary) {
        $popupobj->clear_primary($primary);
    }
    if ($popupobj->get_secondary) {
        $popupobj->clear_secondary($secondary);
    }
    return;
}

# Popup menu for the graph.
# Buggy. Does not clear properly after item selection under OSX.
sub _do_popup_menu {
    #my ($self, $event,$popupobj) = @_;
    my $array = shift;
    my $event = shift;

    my $self = $array->[0];
    my $popupobj = $array->[1];

    # Create the menu items
    my $menu = Gtk2::Menu->new;
    my $logX_item = Gtk2::CheckMenuItem->new('_log X');
    my $logY_item = Gtk2::CheckMenuItem->new('_log Y');
    my $clear_item = Gtk2::MenuItem->new ("Clear");
    my $sep_item = Gtk2::SeparatorMenuItem->new();
    my $sep2_item = Gtk2::SeparatorMenuItem->new();

    #my $display_item = Gtk2::RadioMenuItem->new(undef,'Refresh with selection');
    #connect to the toggled signal to catch the changes
    #$display_item->signal_connect('toggled' => \&toggle,"Refresh with selection");
    #my $group = $display_item->get_group;
    #my $display2_item = Gtk2::RadioMenuItem->new($group, 'Add selection');
    #connect to the toggled signal to catch the changes
    #$display2_item->signal_connect('toggled' => \&toggle,"Add selection");


    # Add them to the menu
    #$menu->append($display_item);
    #$menu->append($display2_item);
    $menu->append($sep2_item);
    $menu->append($logX_item);
    $menu->append($logY_item);
    $menu->append($sep_item);
    $menu->append($clear_item);

    # Attach the callback functions to the activate signal
    $logX_item->signal_connect('toggled' => \&toggle,"log X");
    $logY_item->signal_connect('toggled' => \&toggle,"log Y");
    $clear_item->signal_connect( 'activate' =>  \&clear_graph,$popupobj);

    #$display_item->show;
    #$display2_item->show;
    #$sep2_item->show;
    $logX_item->show;
    $logY_item->show;
    $sep_item->show;
    $clear_item->show;
    $menu->popup (undef, undef, undef, undef, 0, 0);
    return 0;
}

sub toggle {
    my ($menu_item,$text) = @_;
    my $val = $menu_item->get_active;
    say "\$val: $val";
    ($val)&&(print "$text active\n");
    ($val)||(print "$text not active\n");
}


# set the parmary plot group
sub set_primary {
    my $self = shift;
    my $primary = shift;

    $self->{primary} = $primary;
}

# return the primary plot group
sub get_primary {
    my $self = shift;
    my $primary = shift;

    return $self->{primary};
}


# set the secondary plot group
sub set_secondary {
    my $self = shift;
    my $secondary = shift;

    $self->{secondary} = $secondary;
}

# return the secondary plot group
sub get_secondary {
    my $self = shift;
    my $secondary = shift;

    return $self->{secondary};
}
