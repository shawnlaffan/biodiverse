package Biodiverse::GUI::CanvasGraph;

use strict;
use warnings;
use 5.010;

use Data::Dumper;
use Carp;
use Gnome2::Canvas;

use Gtk2;

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
use constant X_AXIS_LABEL_PADDING => 5;
# distance from the left of the graph to the start of the label
use constant Y_AXIS_LABEL_PADDING => 80;
use constant LABEL_FONT => 'Sans 9';

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

# given a hash mapping from x axis values to y axis values, and a
# Gnome2::Canvas. Updates this same canvas with the graph on it.
sub generate_canvas_graph {
    my ($self, %args) = @_;
    my %graph_values = %{$args{graph_values}};
    #my @graphs = $self->generate_fake_graph();
    
    my $canvas       = $args{canvas};
    my $root         = $canvas->root;
    my $point_colour = $args{colour} // Gtk2::Gdk::Color->new(200, 200, 255);
    
    # whether or not we should clear the canvas. We don't want to
    # clear it if we're plotting multiple graphs at the same time.
    my $clear_canvas = $args{clear_canvas};
    
    my ($canvas_width, $canvas_height) = (CANVAS_WIDTH, CANVAS_HEIGHT);
    
    # clean out non numeric hash entries
    foreach my $x (keys %graph_values) {
        my $y = $graph_values{$x};
        if(!looks_like_number($y) || !looks_like_number($x)) {
            delete $graph_values{$x};
        }
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

    # scale the values so they fit nicely in the canvas space.
    my %scaled_graph_values = $self->rescale_graph_points(
        old_values   => \%graph_values,
        canvas_width => $canvas_width,
        canvas_height => $canvas_height,
        );
    
    $self->plot_points(
        graph_values => \%scaled_graph_values,
        canvas       => $canvas,
        point_colour => $point_colour,
        );
    
    # add axis labels
    $self->add_axis_labels_to_graph_canvas( graph_values => \%graph_values,
                                            canvas       => $canvas,
                                            canvas_width => $canvas_width,
                                            canvas_height => $canvas_height,
        );
}


sub plot_points {
    my ($self, %args) = @_;
    my %graph_values  = %{$args{graph_values}};
    my $point_colour  = $args{point_colour};
    my $canvas        = $args{canvas};
    my $root          = $canvas->root;

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
    foreach my $x (-30..30) {
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
