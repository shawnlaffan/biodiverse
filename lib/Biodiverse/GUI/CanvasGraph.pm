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
    #my %graph_values = $self->generate_fake_graph();

    
    my $canvas       = $args{canvas};
    my $root         = $canvas->root;
    my ($canvas_width, $canvas_height) = (300, 300);
    my ($point_width, $point_height) = (2, 2);
    
    # clean out non numeric hash entries
    foreach my $x (keys %graph_values) {
        my $y = $graph_values{$x};
        if(!looks_like_number($y) || !looks_like_number($x)) {
            delete $graph_values{$x};
        }
    }
    # clear the canvas (there must be a better way to do this?)
    my $box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
                                         x1 => -$canvas_width,
                                         y1 => -$canvas_height,
                                         x2 => $canvas_width*2,
                                         y2 => $canvas_height*2,
                                         fill_color => 'white',
                                         outline_color => 'white');
    $box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
                                         x1 => -$point_width,
                                         y1 => -$point_height,
                                         x2 => $canvas_width+$point_width,
                                         y2 => $canvas_height+$point_height,
                                         fill_color => 'white',
                                         outline_color => 'black');


    # we've got 400x400 pixels to display the graph, we need to scale
    # the values so they fit nicely in this space.
    my %scaled_graph_values = $self->rescale_graph_points(
        old_values   => \%graph_values,
        canvas_width => $canvas_width,
        canvas_height => $canvas_height,
        );
    
    # plot the points
    foreach my $x (keys %scaled_graph_values) {
        my $y = $scaled_graph_values{$x};
        #print "Plotting ($x, $y)";
            
        my $box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
                                             x1 => $x-$point_width, 
                                             y1 => $y-$point_height,
                                             x2 => $x+$point_width,
                                             y2 => $y+$point_height,
                                             fill_color => 'green',
                                             outline_color => 'black');
    }

    $self->add_axis_labels_to_graph_canvas( graph_values => \%graph_values,
                                            scaled_graph_values => \%scaled_graph_values,
                                            canvas       => $canvas,
                                            canvas_width => $canvas_width,
                                            canvas_height => $canvas_height,
        );
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
    my $number_of_axis_labels = 4;

    # x axis labels
    foreach my $axis_label (0..($number_of_axis_labels-1)) {
        my $x_position = ($axis_label/($number_of_axis_labels-1)) * $canvas_width;
        my $text = ($axis_label/($number_of_axis_labels-1)) * ($max_x - $min_x) 
            + $min_x;
        $text = sprintf("%.2e", $text);
        my $x_label = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Text',
                                                 x => $x_position,
                                                 y => $canvas_height+5,
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
        $text = sprintf("%.2e", $text);
        my $x_label = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Text',
                                                 x => -80,
                                                 y => $y_position,
                                                 fill_color => 'black',
                                                 font => 'Sans 9',
                                                 anchor => 'GTK_ANCHOR_NW',
                                                 text => $text,
            );
    }
}


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
