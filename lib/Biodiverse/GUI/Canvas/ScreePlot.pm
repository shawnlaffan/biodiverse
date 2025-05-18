package Biodiverse::GUI::Canvas::ScreePlot;
use strict;
use warnings;
use 5.036;
use experimental qw /refaliasing declared_refs for_list/;
use Glib qw/TRUE FALSE/;
use List::Util qw /min max sum/;
use List::MoreUtils qw /minmax/;
use POSIX qw /floor ceil/;
use Data::Printer;
use Carp qw /croak confess/;

use Tree::R;

use Time::HiRes qw/time/;

use constant PI => 3.1415927;

use parent 'Biodiverse::GUI::Canvas::Tree';

sub new {
    my ($class, %args) = @_;

    my $self = Biodiverse::GUI::Canvas::Tree->new (%args);

    #  rebless
    bless $self, $class;

    return $self;
}

# sub callback_order {
#     my $self = shift;
#     return ('plot');
# }

#  no mouse or keyboard interaction
sub on_button_release {}
sub on_button_press {}
sub on_motion {}
sub on_key_press {}


sub draw_slider {
    my ($self, $cx) = @_;

    return if $self->{no_draw_slider};

    #  might only need the x coord  - ultimately will get from the tree
    my $slider_coords
      = $self->{slider_coords} //= {
          x  => 1,
          y0 => 0,
          y1 => 1,
      };

    my ($x, $y0, $y1) = @{$slider_coords}{qw/x y0 y1/};

    my $line_width = ($y1 - $y0) / 100;  #  need to work on this

    $cx->set_source_rgb(0, 0, 1);
    $cx->move_to($x, 0);
    $cx->line_to($x, 1);
    $cx->stroke;

    $slider_coords->{bounds} = [
        $x - $line_width / 2, $y0,
        $x + $line_width / 2, $y1,
    ];

    return;
}

sub draw {
    my ($self, $cx) = @_;


    $self->init_plot_coords;

    my $data = $self->{graph_data};

    $cx->set_source_rgb(0.8, 0.8, 0.8);
    $cx->rectangle (0, 0, 1, 1);
    $cx->fill;

    my $h_line_width = $self->get_line_width;
    $cx->set_line_width($h_line_width);

    foreach my $i (0 .. $#$data-1) {
        my $vertex_l = $data->[$i];
        my $vertex_r = $data->[$i+1];

        my $x_l = $vertex_l->[0];
        my $x_r = $vertex_r->[0];
        my $y_l = $vertex_l->[1];
        my $y_r = $vertex_r->[1];

        # say "$x_l, $y_l, $x_r, $y_r";

        $cx->set_source_rgb(0, 0, 0);
        $cx->move_to($x_l, 1 - $y_l);
        $cx->line_to($x_r, 1 - $y_r);
        $cx->stroke;
    }

    $self->draw_slider($cx);

    return;
}

sub init_plot_coords {
    my ($self) = @_;

    return if $self->{plot_coords_generated};

    $self->SUPER::init_plot_coords;

    #  now iterate over the branches and accumulate
    my $npoints = 50;
    my $ntips   = $self->{data}{ntips};

    # say join ' ', keys %{$self->{data}};

    my @histogram;

    #  use the rtree and get the sum of tips for intersected branches
    my $dims  = $self->{dims};
    my @xdims = ($dims->{xmin}, $dims->{xmax});
    my @ydims = ($dims->{ymin}, $dims->{ymax});

    my $increment = ($xdims[1] - $xdims[0]) / $npoints;
    my $rtree = $self->get_rtree;

    my $x = $xdims[0];
    while ($x < $xdims[1]) {
        my @branches;
        $rtree->query_partly_within_rect($x, $ydims[0], $x+$increment, $ydims[1], \@branches);

        #  only get parents
        my %res_hash = map {$_->{name} => $_} @branches;
        my @res2;
        for my $branch (@branches) {
            next if defined $branch->{parent} && exists $res_hash{$branch->{parent}};
            push @res2, $branch;
        }
        %res_hash = map {$_->{name} => $_} @res2;

        push @histogram, [$x, sum (map {$_->{ntips} / $ntips} @res2)];
        $x += $increment;
    }

    push @histogram, [$xdims[1], $self->{data}{ntips} / $ntips];

    $self->{graph_data} = \@histogram;

    return;
}

1;
