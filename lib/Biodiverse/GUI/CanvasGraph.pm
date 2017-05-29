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

use constant POINT_WIDTH   => 2;
use constant POINT_HEIGHT  => 2;
use constant CANVAS_WIDTH  => 200;
use constant CANVAS_HEIGHT => 200;
use constant NUMBER_OF_AXIS_LABELS => 3;
# gap from the bottom of the graph to the labels
use constant X_AXIS_LABEL_PADDING => 15;
# distance from the left of the graph to the start of the label
use constant Y_AXIS_LABEL_PADDING => 30;
use constant LABEL_FONT => 'Sans 9';
use constant COLOUR_BLACK        => Gtk2::Gdk::Color->new(0, 0, 0);
use constant COLOUR_GREY         => Gtk2::Gdk::Color->new(224, 224, 224);
use constant CELL_SIZE_X        => 10;    # Cell size (canvas units)
use constant COLOUR_WHITE        => Gtk2::Gdk::Color->new(255*257, 255*257, 255*257);
use constant INDEX_ELEMENT      => 1;  # BaseStruct element for this cell
use constant BORDER_SIZE        => 20;

sub new {
    my $class   = shift;
    my %args = @_;
    #my %graph_values = $args{graph_values};
    #my %graph_values = %{$args{graph_values}};

    my $self = {
    }; 
    bless $self, $class;

    my $canvas = $args{canvas};

    #  callback funcs
#    $self->{hover_func}      = $args{hover_func};      # move mouse over a cell
#    $self->{ctrl_click_func} = $args{ctrl_click_func}; # ctrl/middle click on a cell
#    $self->{click_func}      = $args{click_func};      # click on a cell
#    $self->{select_func}     = $args{select_func};     # select a set of elements
#    $self->{grid_click_func} = $args{grid_click_func}; # right click anywhere
#    $self->{end_hover_func}  = $args{end_hover_func};  # move mouse out of hovering over cells

    # Make the canvas and hook it up
    #my $root         = $self->{canvas}->root;
    #$frame->add($self->{canvas});
#    $self->{popup}        = $args{popup};
    $self->{canvas}       = $args{canvas};
    $self->{canvas}->signal_connect_swapped (size_allocate => \&on_size_allocate, $self);

    # Set up canvas
    $self->{canvas}->set_center_scroll_region(0);
    $self->{canvas}->show;
    $self->set_zoom_fit_flag(1);
    $self->{dragging} = 0;

    #if ($show_value) {
    #    $self->setup_value_label();
    #}

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
    $rect->lower_to_bottom();

    $self->{canvas}->root->signal_connect_swapped (
        event => \&on_background_event,
        $self,
    );
    #$rect->signal_connect (button_release_event => \&_do_popup_menu); 

    my $width           = CANVAS_WIDTH;
    my $height          = CANVAS_HEIGHT; 

    # draw the black box that outlines the graph
    my $border = Gnome2::Canvas::Item->new (
        $self->{canvas}->root, 'Gnome2::Canvas::Rect',
        x1 => 0.25*240-(POINT_WIDTH),
        y1 => -(POINT_HEIGHT),
        x2 => 300,   # 0.75*240+(POINT_WIDTH),
        y2 => $height+POINT_HEIGHT,
        fill_color_gdk => COLOUR_WHITE,
        outline_color_gdk => COLOUR_BLACK 
    );
    
    $self->{width_units}  = $width  + 2*BORDER_SIZE;
    $self->{height_units} = $height + 4*BORDER_SIZE;

    $self->{back_rect} = $rect;
    $self->{border_rect} = $border;

    # Create the Label legend
    #my $legend = Biodiverse::GUI::Legend->new(
    #    canvas       => $self->{canvas},
    #    legend_mode  => 'Hue',  #  by default
    #    width_px     => $self->{width_px},
    #    height_px    => $self->{height_px},
    #);
    #$self->set_legend ($legend);

    #$self->update_legend;

    $self->resize_border_rect();
    $self->resize_background_rect();

    return $self;
}

# Add the secondary layer of plot values
sub add_primary_layer {
    my ($self, %args) = @_;
    my %graph_values = %{$args{graph_values}};
    my $canvas       = $args{canvas};
    my $point_colour = $args{colour} // Gtk2::Gdk::Color->new(200, 200, 255);


    say "[add_primary_layer] \$self: $self";
    say "[add_primary_layer] \$canvas: $canvas";

    my ($canvas_width, $canvas_height) = (CANVAS_WIDTH, CANVAS_HEIGHT);

    # Make a group for the secondary plot layer
    my $primary_group = Gnome2::Canvas::Item->new (
        $canvas->root,
        'Gnome2::Canvas::Group',
        x => 70,
        y => 40,
        #x => 0,
        #y => 0
    );

    #$point_layer_group->lower_to_bottom();
    $self->set_primary($primary_group);

    # clean out non numeric hash entries
    foreach my $x (keys %graph_values) {
        my $y = $graph_values{$x};
        if(!looks_like_number($y) || !looks_like_number($x)) {
            delete $graph_values{$x};
        }
    }
    #my $box1 = Gtk2::VBox->new(FALSE, 0);
    #$canvas->add($box1);
    #$box1->set_size_request ($canvas_width, $canvas_height);

    $canvas->signal_connect (button_press_event => \&_do_popup_menu);

    if($clear_canvas) {
        # clear the canvas (there must be a better way to do this?)
        # draw a white box over the whole canvas
        my $box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
                                             x1 => -$canvas_width,
                                             y1 => -$canvas_height,
                                             x2 => $canvas_width*2,
                                             y2 => $canvas_height*2,
                                             fill_color => 'white',
                                             outline_color => 'white');

        # draw the black box that outlines the graph
        $box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
                                          x1 => -(POINT_WIDTH),
                                          y1 => -(POINT_HEIGHT),
                                          x2 => $canvas_width+POINT_WIDTH,
                                          y2 => $canvas_height+POINT_HEIGHT,
                                          fill_color => 'white',
                                          outline_color => 'black');
    }

    if($clear_canvas) {
        # clear the canvas (there must be a better way to do this?)
        # draw a white box over the whole canvas
        my $box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
                                             x1 => -$canvas_width,
                                             y1 => -$canvas_height,
                                             x2 => $canvas_width*2,
                                             y2 => $canvas_height*2,
                                             fill_color => 'white',
                                             outline_color => 'white');

        # draw the black box that outlines the graph
        $box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
                                          x1 => -(POINT_WIDTH),
                                          y1 => -(POINT_HEIGHT),
                                          x2 => $canvas_width+POINT_WIDTH,
                                          y2 => $canvas_height+POINT_HEIGHT,
                                          fill_color => 'white',
                                          outline_color => 'black');
    }

    my $xlab = Gnome2::Canvas::Item->new (
        $root,
        'Gnome2::Canvas::Text',
        x => 88, y => 225,
        markup => "<b>Value</b>",
        anchor => 'nw',
        fill_color_gdk => COLOUR_BLACK,
    );

    # scale the values so they fit nicely in the canvas space.
    my %scaled_graph_values = $self->rescale_graph_points(
        old_values   => \%graph_values,
        canvas_width => $canvas_width,
        canvas_height => $canvas_height,
        );
    #say "\$canvas_width: $canvas_width, \$canvas_height: $canvas_height";

    while( my( $key, $value ) = each %scaled_graph_values ){
    #print "[add_primary_layer] $key: $value\n";
    }

    $self->plot_points(
        graph_values => \%scaled_graph_values,
        canvas       => $primary_group,
        point_colour => $point_colour,
        );

    # add axis labels
    if (%graph_values){
        $self->add_axis_labels_to_graph_canvas( graph_values => \%graph_values,
                                                canvas       => $primary_group,
                                                canvas_width => $canvas_width,
                                                canvas_height => $canvas_height,
            );
    }
}

# Add the secondary layer of plot values
sub add_secondary_layer {
    my ($self, %args) = @_;
    my %graph_values = %{$args{graph_values}};
    my $canvas       = $args{canvas};
    my $point_colour = $args{colour} // Gtk2::Gdk::Color->new(200, 200, 255);

    $point_colour = Gtk2::Gdk::Color->new(255*257,0,0);

    my ($canvas_width, $canvas_height) = (CANVAS_WIDTH, CANVAS_HEIGHT);

    #say "[add_secondary_layer] \$canvas_width: $canvas_width, \$canvas_height: $canvas_height";
    #say "[add_secondary_layer] \$self: $self";
    #say "[add_secondary_layer] \$canvas: $canvas";

    # Make a group for the secondary plot layer
    my $secondary_group = Gnome2::Canvas::Item->new (
        $canvas->root,
        'Gnome2::Canvas::Group',
        x => 70,
        y => 40,
        #x => 0,
        #y => 0
    );

   $self->set_secondary($secondary_group);

   my $secondary = $self->get_secondary;
   #say "[add_secondary_layer] \$secondary: $secondary";
   #say "[add_secondary_layer] \$canvas: $canvas";


    # clean out non numeric hash entries
    foreach my $x (keys %graph_values) {
        my $y = $graph_values{$x};
        if(!looks_like_number($y) || !looks_like_number($x)) {
            delete $graph_values{$x};
        }
    }

    # scale the values so they fit nicely in the canvas space.
    my %scaled_graph_values = $self->rescale_graph_points(
        old_values   => \%graph_values,
        canvas_width => $canvas_width,
        canvas_height => $canvas_height,
        );
    #say "[add_secondary_layer] \$canvas_width: $canvas_width, \$canvas_height: $canvas_height";

    while( my( $key, $value ) = each %scaled_graph_values ){
    #print "[add_secondary_layer] $key: $value\n";
    }

    $self->plot_points(
        graph_values => \%scaled_graph_values,
        canvas       => $secondary_group,
        point_colour => $point_colour,
        );
    
    # add axis labels
    if (%graph_values){
        $self->add_axis_labels_to_graph_canvas( graph_values => \%graph_values,
                                                canvas       => $secondary_group,
                                                canvas_width => $canvas_width,
                                                canvas_height => $canvas_height,
            );
   }

   say "[add_secondary_layer] about to show \$secondary_group: $secondary_group";
   $secondary_group->raise_to_top();
   $secondary_group->show();

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
        
        my $box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
                                             x1 => $x-$point_width, 
                                             y1 => $y-$point_height,
                                             x2 => $x+$point_width,
                                             y2 => $y+$point_height,
                                             fill_color => $point_colour,
                                             outline_color => $point_colour);
    }

}

sub rescale_graph_points {
    my ($self, %args) = @_;
    my %old_values = %{$args{old_values}};
    my $canvas_width = $args{canvas_width};
    my $canvas_height = $args{canvas_height};

    # find the max and min for the x and y axis.
    my @x_values = keys %old_values;
    my @y_values = values %old_values;

    return if(scalar @x_values == 0 || scalar @y_values == 0);
    
    my $min_x = min @x_values;
    my $max_x = max @x_values;
    my $min_y = min @y_values;
    my $max_y = max @y_values;

    #say "x, y min max is ($min_x, $max_x), ($min_y, $max_y)";

    if($max_x == $min_x) {
        ($max_x, $min_x) = (1, 0); # stop division by 0 error
    }
    if($max_y == $min_y) {
        ($max_y, $min_y) = (1, 0); # stop division by 0 error
    }
    
    my %new_values;
    
    # apply scaling formula
    foreach my $x (keys %old_values) {
        my $y = $old_values{$x};

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
    
    my @x_values = keys %graph_values;
    my @y_values = values %graph_values;
    my $min_x = min @x_values;
    my $max_x = max @x_values;
    my $min_y = min @y_values;
    my $max_y = max @y_values;

    # add some axis labels
    my $number_of_axis_labels = NUMBER_OF_AXIS_LABELS;

    # x axis labels
    foreach my $axis_label (0..($number_of_axis_labels-1)) {
        my $x_position = ($axis_label/($number_of_axis_labels-1)) * $canvas_width;
        my $text = ($axis_label/($number_of_axis_labels-1)) * ($max_x - $min_x) 
            + $min_x;

        # TODO Add format choice
        $text = sprintf("%.2g", $text);
        my $x_label = Gnome2::Canvas::Item->new (
            $root, 'Gnome2::Canvas::Text',
            x => $x_position,
            y => $canvas_height+X_AXIS_LABEL_PADDING,
            fill_color => 'black',
            font => 'Sans 9',
            anchor => 'GTK_ANCHOR_NW',
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
        $text = sprintf("%.2g", $text);
        my $x_label = Gnome2::Canvas::Item->new (
            $root, 'Gnome2::Canvas::Text',
            x => - Y_AXIS_LABEL_PADDING,
            y => $y_position,
            fill_color => 'black',
            font => LABEL_FONT,
            anchor => 'GTK_ANCHOR_NW',
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
            my $border_x1 = (max($width,  $self->{width_units})/2) - 100 - POINT_WIDTH;
            my $border_y1 = (max($height,  $self->{height_units})/2) - 100 - POINT_WIDTH;
            my $border_x2 = (max($width,  $self->{width_units})/2) + 100 + POINT_WIDTH;
            my $border_y2 = (max($height,  $self->{height_units})/2) + 100 + POINT_WIDTH;
         
            #say "[[resize_border_rect]] \$border_x1: $border_x1 \$border_x2: $border_x2";
            #say "[[resize_border_rect]] \$border_y1: $border_y1 \$border_y2: $border_y2";
            $self->{border_rect}->set(
                x1 => ((max($width,  $self->{width_units})/2) - 100 - POINT_WIDTH // 1),
                y1 => ((max($height, $self->{height_units})/2) - 100 - POINT_WIDTH // 1),
                x2 => ((max($width,  $self->{width_units})/2) + 100 + POINT_WIDTH // 1),
                y2 => ((max($height, $self->{height_units})/2) + 100 + POINT_WIDTH // 1),
            );
            $self->{border_rect}->raise_to_top();
        }
    }
    return;
}

sub get_zoom_fit_flag {
    my ($self) = @_;
    
    return $self->{zoom_fit};
}

sub set_zoom_fit_flag {
    my ($self, $zoom_fit) = @_;
    
    $self->{zoom_fit} = $zoom_fit;
}


# Implements panning
sub on_background_event {
    my ($self, $event, $cell) = @_;

    # Do everything with right click now.
    return if $event->type =~ m/^button-/ && $event->button != 3;
    if ($event->type eq 'button-press') {
        my $button_nr = $event->button;
        ($button_nr == 3)&& (_do_popup_menu($self->{canvas}->root));
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
    print "[Grid] Setting grid zoom (pixels per unit) to $min_ppu\n";
    
    return wantarray ? %graph : \%graph;
    
}

sub add_axis_labels_to_graph_canvas {
    my ($self, %args) = @_;
    my %graph_values  = %{$args{graph_values}};
    my $canvas        = $args{canvas};
    my $canvas_width  = $args{canvas_width};
    my $canvas_height = $args{canvas_height};
    my $root          = $canvas->root;
    
    my @x_values = keys %graph_values;
    my @y_values = values %graph_values;
    my $min_x = min @x_values;
    my $max_x = max @x_values;
    my $min_y = min @y_values;
    my $max_y = max @y_values;

    # add some axis labels
    my $number_of_axis_labels = NUMBER_OF_AXIS_LABELS;

    # x axis labels
    foreach my $axis_label (0..($number_of_axis_labels-1)) {
        my $x_position = ($axis_label/($number_of_axis_labels-1)) * $canvas_width;
        my $text = ($axis_label/($number_of_axis_labels-1)) * ($max_x - $min_x) 
            + $min_x;

        # TODO Add format choice
        $text = sprintf("%.2e", $text);
        my $x_label = Gnome2::Canvas::Item->new (
            $root, 'Gnome2::Canvas::Text',
            x => $x_position,
            y => $canvas_height+X_AXIS_LABEL_PADDING,
            fill_color => 'black',
            font => 'Sans 9',
            anchor => 'GTK_ANCHOR_NW',
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
        $text = sprintf("%.2e", $text);
        my $x_label = Gnome2::Canvas::Item->new (
            $root, 'Gnome2::Canvas::Text',
            x => - Y_AXIS_LABEL_PADDING,
            y => $y_position,
            fill_color => 'black',
            font => LABEL_FONT,
            anchor => 'GTK_ANCHOR_NW',
            text => $text,
            );
    }
}


# make a random polynomial hash
# lots of magic numbers but this is really a test function.
sub generate_fake_graph {
    my ($self, %args) = @_;

    my ($minimum, $maximum) = (2, 5);
    my $exponent = $minimum + int(rand($maximum - $minimum));
    
    my %graph;

    my %coeff;
    foreach my $exp (0..$exponent) {
        my $coefficient = -20 + int(rand(40));
        $coeff{$exp} = $coefficient;
    }
    
    # generate a nice polynomial graph with some noise
    ($minimum, $maximum) = (-20, 20);
    foreach my $x (-100..100) {
        my $random_noise_percent = $minimum + int(rand($maximum - $minimum));
        my $y = 0;
        foreach my $exp (0..$exponent) {
            my $coefficient = int(rand(40));
            $y += $coeff{$exp} * ($x**$exp);
        }
        $y += ($random_noise_percent/100) * $y;
        $graph{$x} = $y;
    }
    
    return wantarray ? %graph : \%graph;
}


sub clear_graph {
    my $self = shift;
    my $canvas = shift;
    my $root         = $canvas;
    my ($canvas_width, $canvas_height) = (CANVAS_WIDTH, CANVAS_HEIGHT);
    my $width           = CANVAS_WIDTH;
    my $height          = CANVAS_HEIGHT; 

    say "clear_graph";
    print Dumper($self);

    if ($self->{secondary}) {
        say "[[clear_graph]] \$self->{secondary}->destroy";
        $self->{secondary}->destroy();
    }
    return;
    # Create background rectangle to receive mouse events for panning
    my $rect = Gnome2::Canvas::Item->new (
        $root,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        y1 => 0,
        x2 => CELL_SIZE_X,
        y2 => CELL_SIZE_X,
        fill_color_gdk => COLOUR_WHITE,
    );
    $rect->lower_to_bottom();
    # Draw a white box over the whole canvas
    #my $box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
    #                                  x1 => -$canvas_width,
    #                                  y1 => -$canvas_height,
    #                                  x2 => $canvas_width*2,
    #                                  y2 => $canvas_height*2,
    #                                  fill_color => 'white',
    #                                  outline_color => 'white');

    # draw the black box that outlines the graph
    my $border = Gnome2::Canvas::Item->new (
        $root, 'Gnome2::Canvas::Rect',
        x1 => 0.25*240-(POINT_WIDTH),
        y1 => -(POINT_HEIGHT),
        x2 => 300,   # 0.75*240+(POINT_WIDTH),
        y2 => $height+POINT_HEIGHT,
        fill_color_gdk => COLOUR_WHITE,
        outline_color_gdk => COLOUR_BLACK 
    );
    # Draw the black box that outlines the graph
    #$box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
    #                                 x1 => -(POINT_WIDTH),
    #                                  y1 => -(POINT_HEIGHT),
    #                                  x2 => $canvas_width+POINT_WIDTH,
    #                                  y2 => $canvas_height+POINT_HEIGHT,
    #                                  fill_color => 'white',
    #                                  outline_color => 'black');
    # add axis labels
    my %zero_data = ( 1 => 0, 2 => 0, 3 => 0, 4 => 0, 5 => 0 );
    #add_axis_labels_to_graph_canvas( graph_values => %zero_data,
    #                                        canvas       => $canvas,
    #                                        canvas_width => $canvas_width,
    #                                        canvas_height => $canvas_height,
    #                                       );
    resize_border_rect();
}

# Popup menu for the graph.
# Buggy. Does not clear properly after item selection under OSX.
sub _do_popup_menu {
    # Just clean the graph at the moment.
    my ($self, $event) = @_;
    #return if $event->type =~ m/^button-/ && $event->button != 3;
    #if ($event->button != 3) {  # ignore other than button3
    #    return 0;  # propagate event
    #}

    # Create the menu items
    my $menu = Gtk2::Menu->new;
    my $logX_item = Gtk2::CheckMenuItem->new('_log X');
    my $logY_item = Gtk2::CheckMenuItem->new('_log Y');
    my $clear_item = Gtk2::MenuItem->new ("Clear");
    my $sep_item = Gtk2::SeparatorMenuItem->new();
    my $sep2_item = Gtk2::SeparatorMenuItem->new();

    my $display_item = Gtk2::RadioMenuItem->new(undef,'Refresh with selection');
    #connect to the toggled signal to catch the changes
    $display_item->signal_connect('toggled' => \&toggle,"Refresh with selection");
    my $group = $display_item->get_group;
    my $display2_item = Gtk2::RadioMenuItem->new($group, 'Add selection');
    #connect to the toggled signal to catch the changes
    $display2_item->signal_connect('toggled' => \&toggle,"Add selection");


    # Add them to the menu
    $menu->append($display_item);
    $menu->append($display2_item);
    $menu->append($sep2_item);
    $menu->append($logX_item);
    $menu->append($logY_item);
    $menu->append($sep_item);
    $menu->append($clear_item);

    # Attach the callback functions to the activate signal
    $logX_item->signal_connect('toggled' => \&toggle,"log X");
    $logY_item->signal_connect('toggled' => \&toggle,"log Y");
    $clear_item->signal_connect( 'activate' =>  \&clear_graph, $self);

    $display_item->show;
    $display2_item->show;
    $sep2_item->show;
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

# return the parmary plot group
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
