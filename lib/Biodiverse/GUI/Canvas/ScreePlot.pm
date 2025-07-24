package Biodiverse::GUI::Canvas::ScreePlot;
use strict;
use warnings;
use 5.036;

our $VERSION = '4.99_009';

use experimental qw /refaliasing declared_refs for_list/;
use Glib qw/TRUE FALSE/;
use Gtk3;
use Scalar::Util qw /weaken/;
use List::Util qw /min max sum/;
use List::MoreUtils qw /minmax/;
use POSIX qw /floor ceil/;
use Carp qw /croak confess/;

use parent 'Biodiverse::GUI::Canvas';

sub new {
    my ($class, %args) = @_;

    my $self = $class->SUPER::new (%args);

    #  rebless
    bless $self, $class;

    $self->{callbacks} = {draw => sub {shift->draw (@_)}};

    return $self;
}

sub callback_order {
    my $self = shift;
    return (qw /draw/);
}

sub cairo_draw {
    my $self = shift;
    return if !$self->get_tree_canvas->get_current_tree;

    return $self->SUPER::cairo_draw(@_);
}

sub set_tree_canvas {
    my ($self, $tree_canvas) = @_;
    $self->{tree_canvas} = $tree_canvas;
    weaken $self->{tree_canvas};
    # $self->init_plot_coords;
    return $tree_canvas;
}

sub get_tree_canvas {
    my ($self) = @_;
    return $self->{tree_canvas};
}

sub get_parent_tab {
    my ($self) = @_;
    $self->get_tree_canvas->get_parent_tab;
}

sub get_show_slider {
    my ($self) = @_;
    $self->get_tree_canvas->get_show_slider;
}

sub get_slider_coords {
    my ($self) = @_;
    $self->get_tree_canvas->get_slider_coords;
}


#  no mouse or keyboard interaction
sub on_button_release {}
sub on_button_press {}
sub on_motion {}
sub on_key_press {}

sub do_zoom_in_centre{
    my ($self) = @_;
    $self->get_tree_canvas->do_zoom_in_centre;
}
sub do_zoom_out_centre{
    my ($self) = @_;
    $self->get_tree_canvas->do_zoom_out_centre;
}

sub do_pan_up {
    my ($self) = @_;
    $self->get_tree_canvas->do_pan_up;
}
sub do_pan_down {
    my ($self) = @_;
    $self->get_tree_canvas->do_pan_down;
}
sub do_pan_left {
    my ($self) = @_;
    $self->get_tree_canvas->do_pan_left;
}
sub do_pan_right {
    my ($self) = @_;
    $self->get_tree_canvas->do_pan_right;
}



sub draw_slider {
    my ($self, $cx) = @_;

    return if !$self->get_show_slider;

    #  might only need the x coord
    my $slider_coords = $self->get_slider_coords;

    $cx->save;
    $cx->set_source_rgba(0, 0, 1, 0.5);
    my $bounds = $slider_coords->{bounds};

    if (1 && $bounds) {
        #  never less than one px, never more than the tree's slider_width_px
        my $width = min (
            ($cx->device_to_user_distance($self->get_tree_canvas->slider_width_px,0))[0],
            max (
                $bounds->[2] - $bounds->[0],
                ($cx->device_to_user_distance(1,0))[0],
            )
        );
        $cx->rectangle(
            $bounds->[0],
            0,
            $width,
            1,
        );
        $cx->fill;
    }
    else {
        #  we should not hit this
        my $x = $slider_coords->{x};
        $cx->move_to($x, 0);
        $cx->line_to($x, 1);
        $cx->stroke;
    }
    $cx->restore;

    return;
}

sub draw {
    my ($self, $cx) = @_;


    $self->init_plot_coords;

    my $data = $self->{data};

    #  displayed extent from the tree
    my @de = $self->get_tree_canvas->get_displayed_extent;
    my $left  = max (0, $de[0]);
    my $width = min (1, $de[2]) - $left;

    #  a rectangle showing the tree plot extent
    $cx->set_source_rgb(0.8, 0.8, 0.8);
    $cx->rectangle ($left, 0, $width, 1);
    $cx->fill;

    # my $h_line_width = $self->get_line_width;
    my ($v_line_width, $h_line_width) = $cx->device_to_user_distance(1,1);

    $cx->set_source_rgb(0, 0, 0);
    foreach my $i (0 .. $#$data-1) {
        my $vertex_l = $data->[$i];
        my $vertex_r = $data->[$i+1];

        my ($x_l, $y_l) = @$vertex_l[0,1];
        my ($x_r, $y_r) = @$vertex_r[0,1];

        $cx->set_line_width($y_l == $y_r ? $h_line_width : $v_line_width);

        $cx->move_to($x_l, 1 - $y_l);
        $cx->line_to($x_r, 1 - $y_r);
        $cx->stroke;
    }

    $self->draw_slider($cx);

    return;
}

#  branch line width in canvas units
sub get_line_width {
    my ($self) = @_;

    return 0.01;
}

#  Requires the data match expectations
sub set_plot_coords {
    my ($self, $data) = @_;

    my $tree_canvas = $self->get_tree_canvas;

    my $dims = $tree_canvas->{dims};

    $self->init_dims (
        xmin => $dims->xmin,
        xmax => $dims->xmax,
        ymin => 0,
        ymax => 1,
    );
    $self->{data} = $data;

    return;
}

#  requires the tree to have generated its data
sub init_plot_coords {
    my ($self) = @_;

    return if $self->{plot_coords_generated};

    my $tree_canvas = $self->get_tree_canvas;

    my $tree_data = $tree_canvas->get_data;

    #  now iterate over the branches and accumulate
    my $npoints = 200;
    my $branches = $tree_data->{by_node};
    my $nbranches = scalar keys %$branches;

    return if !$nbranches;

    #  use the rtree and get the sum of tips for intersected branches
    my $dims  = $tree_canvas->{dims};
    my @xdims = ($dims->xmin, $dims->xmax);

    my $increment = ($xdims[1] - $xdims[0]) / $npoints;

    my @histo;
    my $branch_hash = $tree_canvas->{data}{by_node};
    foreach my ($name, $branch) (%$branch_hash) {
        my ($x_l, $x_r) = minmax @$branch{qw/x_l x_r/};  #  handle negative lengths
        my $left  = floor (($x_l - $xdims[0]) / $increment);
        my $right = floor (($x_r - $xdims[0]) / $increment);
        $histo[$_]{$name}++ for (max (0, $left) .. $right);
    }
    my (@histo2, %collated);
    my $prev_frac = 0;
    my $x = 0;
    foreach my ($i) (0 .. $#histo) {
        my $href = $histo[$i];
        @collated{keys %$href} = ();
        my $frac = (scalar keys %collated) / $nbranches;
        if ($frac != $prev_frac) {
            push @histo2, ([ $x, $prev_frac ], [ $x, $frac ]);
            $prev_frac = $frac;
        }
        $x += $increment;
    }
    push @histo2, ([$xdims[1], $prev_frac], [$xdims[1], 1]);

    $self->init_dims (
        xmin => $xdims[0],
        xmax => $xdims[1],
        ymin => 0,
        ymax => 1,
    );
    $self->{data} = \@histo2;

    $self->{plot_coords_generated} = 1;

    return;
}


1;
