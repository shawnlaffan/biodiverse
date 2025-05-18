package Biodiverse::GUI::Canvas::Tree;
use strict;
use warnings;
use 5.036;
use experimental qw /refaliasing declared_refs for_list/;
use Glib qw/TRUE FALSE/;
use List::Util qw /min max/;
use List::MoreUtils qw /minmax/;
use POSIX qw /floor/;
# use Data::Printer;
use Carp qw /croak confess/;

use Tree::R;

use Time::HiRes qw/time/;

use Biodiverse::GUI::Canvas::Tree::Index;

use parent 'Biodiverse::GUI::Canvas';

sub new {
    my ($class, %args) = @_;
    my $size = 1;
    $args{dims} = {
        xmin    => 0,
        ymin    => 0,
        xmax    => $size,
        ymax    => $size,
        xwidth  => $size,
        yheight => $size,
        xcen    => $size / 2,
        ycen    => $size / 2,
    };

    my $self = Biodiverse::GUI::Canvas->new (%args);

    #  rebless
    bless $self, $class;

    $self->{data} = $self->get_data($args{ntips});
    $self->init_plot_coords;
    # say join ' ', $self->get_data_extents;

    $self->{callbacks} = {
        plot => sub {shift->draw (@_)},
    };

    return $self;
}

sub callback_order {
    my $self = shift;
    return ('plot');
}

sub _on_motion {
    my ($self, $widget, $event, $ref_status) = @_;

    return FALSE if $self->{mode} ne 'select';
    return FALSE if !$self->{plot_coords_generated};

    my ($x, $y) = $self->get_event_xy($event);

    my $current_cursor_name = $self->{motion_cursor_name} //= 'default';

    if (!$self->{no_draw_slider}) {
        my $slider = $self->{slider_coords};
        \my @b = $slider->{bounds};

        if ($self->{sliding}) {
            $slider->{x} = $x;
            my $w = ($b[2] - $b[0]) / 2;
            $b[0] = $x - $w;
            $b[2] = $x + $w;
            $slider->{x} = $x;

            #  get the overlapping branches
            my @bres = $self->get_index->intersects_slider(@b);

            $self->set_cursor_from_name ('pointer');
            $widget->queue_draw;
            return FALSE;
        }
        else {
            if ($x >= $b[0] && $x < $b[2] && $y >= $b[1] && $y < $b[3]) {
                $self->set_cursor_from_name ('pointer');
                $self->{motion_cursor_name} = 'pointer';
                return FALSE;
            }
            else {
                #  reset - needs to be in a conditional or we stop the slide
                $self->set_cursor_from_name ($current_cursor_name);
            }
        }

    }

    \my @results = $self->get_index->query_point ($x, $y);

    #  should get cursor name from mode
    my $new_cursor_name = @results ? 'pointer' : 'default';
    if ($current_cursor_name ne $new_cursor_name) {
        #  change mouse style
        $self->set_cursor_from_name ($new_cursor_name);
        $self->{motion_cursor_name} = $new_cursor_name;
    }

    return FALSE;
}

sub get_index {
    my $self = shift;
    my $index = $self->{data}{box_index};

    #  we don't have the x-coords until the first time we are drawn
    return $index if $index && $self->{plot_coords_generated};

    $index = $self->{data}{box_index} = Biodiverse::GUI::Canvas::Tree::Index->new;
    $index->populate_from_tree($self);

    return $index;
}

sub _on_button_release {
    my ($self, $x, $y) = @_;

    delete $self->{sliding};

    return FALSE;
}

sub _select_while_not_selecting {
    my ($self, $widget, $x, $y) = @_;

    if (!$self->{no_draw_slider} && $self->{selecting}) {
        my $slider = $self->{slider_coords};
        \my @b = $slider->{bounds};
        if ($x >= $b[0] && $x < $b[2] && $y >= $b[1] && $y < $b[3]) {
            $self->{sliding} = 1;
            # say 'SLIDER';

            $self->set_cursor_from_name ('pointer');

            $widget->queue_draw;
            return FALSE;
        }
    }

    return FALSE if $x > $self->xmax || $y > $self->ymax;

    my @branches = $self->get_index->query_point_nearest_y ($x, $y);
    foreach my $branch (@branches) {
        say 'BT: ' . $branch->{name} if $branch;
    }

    return;
}

sub draw_slider {
    my ($self, $cx) = @_;

    return if $self->{no_draw_slider};

    #  might only need the x coord
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

    if ($self->{sliding}) {
        my $text = 'ST';
        my $old_mx = $cx->get_matrix;
        #  needs to work in page units
        my @loc = $cx->user_to_device ($x, ($y1+$y0)/2);
        $cx->set_matrix($self->{orig_tfm_mx});
        $cx->set_source_rgb(0, 0, 1);
        $cx->select_font_face("Sans", "normal", "bold");
        $cx->set_font_size( 50 );
        $cx->move_to(@loc);
        $cx->show_text($text);
        $cx->stroke;
        $cx->set_matrix($old_mx);
    };

    return;
}

sub get_line_width {
    my ($self) = @_;

    #  need to work on this as non-aspect locked scaling makes things odd
    my @y_bounds = (0,1);
    my $line_width = ($y_bounds[1] - $y_bounds[0]) / 100;

    return $line_width;
}

#  ensure the vertical lines are the same as the horizontal ones
sub get_vertical_line_width {
    my ($self) = @_;

    my @scaling = $self->get_scale_factors;

    return $self->get_line_width * $scaling[1] / $scaling[0];
}

sub x_scale {
    1 / $_[0]->{data}{longest_path}
}

sub y_scale {
    1 / $_[0]->{data}{root}{ntips};
}

sub draw {
    my ($self, $cx) = @_;

    #  need to handle negative branches - these can push the rhs out past the root
    #  (or really the root inwards relative to the branches)

    my $data = $self->{data};
    my $root = $data->{root};
    my $node_hash = $data->{by_node};

    $self->init_plot_coords;

    $cx->set_source_rgb(0.8, 0.8, 0.8);
    $cx->rectangle (0, 0, 1, 1);
    $cx->fill;

    my $h_line_width = $self->get_line_width;
    my $v_line_width = $self->get_vertical_line_width;

    foreach my $branch (values %$node_hash) {

        my ($x_r, $x_l, $y) = @{$branch}{qw/x_r x_l y/};

        $cx->set_line_width($h_line_width);

        #  mid-grey
        $cx->set_source_rgb(0.4, 0.4, 0.4);
        $cx->move_to($x_r, $y);
        $cx->line_to($x_l, $y);
        $cx->stroke;

        #  vertical connectors - will be more direct in biodiverse as they are objects already
        my @children = map {$node_hash->{$_}} @{$branch->{children}};
        if (@children) {
            $cx->set_line_width($v_line_width);
            $cx->move_to($x_l, $children[0]{y});  #  first child
            $cx->line_to($x_l, $children[-1]{y});  #  last child
            $cx->stroke;
        }
    }

    $self->draw_slider($cx);

    return;
}

sub init_plot_coords {
    my ($self) = @_;

    return if $self->{plot_coords_generated};

    $self->init_y_coords;

    my $data = $self->{data};
    my $root = $data->{root};
    my @branches = ($root);
    my $node_hash = $data->{by_node};

    my $x_scale  = $self->x_scale;
    my $y_scale  = $self->y_scale;

    $root->{x_r} //= 1;

    while (my $branch = shift @branches) {
        $branch->{y} = $branch->{_y} * $y_scale;

        my $length = $branch->{length} * $x_scale;
        my $x_r = $branch->{x_r};
        my $x_l = $branch->{x_l} //= $x_r - $length;

        my @children = map {$node_hash->{$_}} @{$branch->{children}};
        foreach my $child (@children) {
            $child->{x_r} = $x_l;
        }
        push @branches, @children;
    }

    $self->{plot_coords_generated} = 1;

    #  trigger index generation
    my $box_index = $self->get_index;

    return;
}

sub init_y_coords {
    my ($self, $node, $current_y_ref) = @_;

    use constant LEAF_SPACING => 1;
    use constant BORDER_HT    => 0.025;

    my $data = $self->{data};
    $node //= $data->{root};
    if (!defined $current_y_ref) {
        #  ensure we centre, otherwise we are off-by-one
        my $x = 0.5 * LEAF_SPACING;
        $current_y_ref = \$x;
    }
    #  zero border ht now as we centre the tree vertically
    # $self->{border_ht} //= $data->{ntips} * BORDER_HT;
    $self->{border_ht} //= 0;


    if (!$node->{ntips}) {
        $node->{_y} = $$current_y_ref + $self->{border_ht};
        ${$current_y_ref} = $$current_y_ref + LEAF_SPACING;
    }
    else {
        my $y_sum = 0;
        my $count = 0;

        foreach my $child (map {$data->{by_node}{$_}} @{$node->{children}}) {
            $self->init_y_coords($child, $current_y_ref);
            $y_sum += $child->{_y};
            $count++;
        }
        $node->{_y} = $y_sum / $count; # y-value is average of children's y values
    }

    return;
}


sub get_data {
    my ($self, $ntips) = @_;

    $ntips //= 8;
    #  round up to next power of two for simplicity
    my $power = 1;
    while ($power < $ntips) {
        $power *= 2;
    }
    $ntips = $power;
    my $nbranches = $ntips * ($ntips - 1) / 2;
use DDP; p $nbranches;
    srand (2345);

    #  generate some branches
    my @branches = (1);
    foreach my $i (@branches) {
        push @branches, (2*$i, 2*$i+1);
        last if scalar @branches >= $nbranches;
    }

    my %branch_hash;
    foreach my $branch (@branches) {
        my $parent = int ($branch / 2) || undef;
        $branch_hash{$branch} = {
            length   => rand(),
            parent   => $parent,
            children => [],
            name     => $branch,
        };
        if (defined $parent) {
            my $c = $branch_hash{$parent}{children} //= [];
            push @$c, $branch;
        }
    }
    my @tips = sort {$a<=>$b} grep {!scalar @{$branch_hash{$_}{children}}} keys %branch_hash;

    my $longest_path = 0;
    foreach my $tip (@tips) {
        $branch_hash{$tip}{ntips} = 0;
        my $len  = $branch_hash{$tip}{length};
        my $path = $branch_hash{$tip}{path_to_root} = [$len];
        my $parent = $tip;
        while ($parent = $branch_hash{$parent}{parent}) {
            my $this_len = $branch_hash{$parent}{length};
            $len += $this_len;
            push @$path, $this_len;
            $branch_hash{$parent}{ntips}++;
            # say "Parent is $parent, len is $len";
        }
        $longest_path = $len if $len > $longest_path;
    }

    my %tree = (
        root         => $branch_hash{1},
        by_node      => \%branch_hash,
        tips         => \@tips,
        ntips        => scalar @tips,
        longest_path => $longest_path,
    );

    return \%tree;
}

1;
