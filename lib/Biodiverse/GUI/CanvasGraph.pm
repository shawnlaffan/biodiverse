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
                                         x1 => -$point_width,
                                         y1 => -$point_height,
                                         x2 => $canvas_width+$point_width,
                                         y2 => $canvas_height+$point_height,
                                         fill_color => 'white',
                                         outline_color => 'white');

    
    

    # we've got 400x400 pixels to display the graph, we need to scale
    # the values so they fit nicely in this space.
    %graph_values = $self->rescale_graph_points(
        old_values   => \%graph_values,
        canvas_width => $canvas_width,
        canvas_height => $canvas_height,
        );
    
    # start by just plotting the points

    foreach my $x (keys %graph_values) {
        my $y = $graph_values{$x};
        #print "Plotting ($x, $y)";
            
        my $box = Gnome2::Canvas::Item->new ($root, 'Gnome2::Canvas::Rect',
                                             x1 => $x-$point_width, 
                                             y1 => $y-$point_height,
                                             x2 => $x+$point_width,
                                             y2 => $y+$point_height,
                                             fill_color => 'green',
                                             outline_color => 'black');
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
        my $new_y = (($canvas_height)*($y-$min_y) / ($max_y-$min_y));

        $new_values{$new_x} = $new_y;
    }

    return wantarray? %new_values : \%new_values;
    
}
