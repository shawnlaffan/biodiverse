package Biodiverse::GUI::Canvas::Grid;

use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use experimental qw /refaliasing declared_refs for_list/;
use Glib qw/TRUE FALSE/;
use Gtk3;
use List::Util qw /min max/;
use List::MoreUtils qw /minmax/;
use Ref::Util qw /is_hashref is_arrayref is_blessed_ref/;
use POSIX qw /floor/;
use Carp qw /croak confess/;
use Tree::R;

use constant PI => 3.141592653589793238462643383279;

use constant COLOUR_BLACK => Gtk3::Gdk::RGBA::parse('black');
use constant COLOUR_WHITE => Gtk3::Gdk::RGBA::parse('white');
use constant COLOUR_GRAY  => Gtk3::Gdk::RGBA::parse('rgb(210,210,210)');
use constant COLOUR_RED   => Gtk3::Gdk::RGBA::parse('red');
use constant COLOUR_FAILED_DEF_QUERY => Gtk3::Gdk::RGBA::parse('white');
use constant CELL_OUTLINE_COLOUR => Gtk3::Gdk::RGBA::parse('black');

use parent 'Biodiverse::GUI::Canvas';
use Biodiverse::GUI::Canvas::Dims;

sub new {
    my ($class, %args) = @_;
    my $self = Biodiverse::GUI::Canvas->new (%args);

    #  rebless
    bless $self, $class;

    if (!exists $args{show_cell_outlines}) {
        $self->{show_cell_outlines} = 1;
    }

    $self->init_legend(%args, parent => $self);

    $self->{callbacks} = {
        map                 => sub {shift->draw_cells_cb(@_)},
        highlights          => sub {shift->plot_highlights(@_)},
        overlays            => sub {shift->_bounding_box_page_units(@_)},
        underlays           => sub {},
        legend              => sub {shift->get_legend->draw(@_)},
        sel_rect            => sub {shift->draw_selection_rect(@_)},
        range_convex_hulls  => undef,
        range_circumcircles => undef,
    };
    $self->{callback_order} = [qw /
        underlays
        map
        overlays
        legend
        range_convex_hulls
        range_concave_hulls
        range_convex_hull_union
        range_concave_hull_union
        range_circumcircles
        range_circumcircle_union
        highlights sel_rect
    /];

    return $self;
}

sub maintain_aspect_ratio {!!1};
sub plot_bottom_up {!!1};

sub callback_order {
    my $self = shift;
    return @{$self->{callback_order}};
}

#  bottom up plotting for maps
sub get_scale_factor {
    # my ($self, $axis1) = @_;
    # return ($axis1, -$axis1);
    return $_[1], -$_[1];
}

#  need a better name but this is called as a fallback from SUPER::on_motion
sub _on_motion {
    my ($self, $widget, $event) = @_;

    my ($x, $y) = $self->get_event_xy($event);

    #  do nothing if more than one cell off the grid - not needed now
    # \my @c = $self->get_cell_sizes;
    # return FALSE
    #     if ($x > $self->xmax + $c[0])
    #     || ($y > $self->ymax + $c[1])
    #     || ($x < $self->xmin - $c[0])
    #     || ($y < $self->ymin - $c[1]);

    my $key = $self->snap_coord_to_grid_id($x, $y);
    my $last_key = $self->{last_motion_key} //= '';
    my $current_cursor_name = $self->{motion_cursor_name} //= 'default';

    my $f = $self->{hover_func};

    #  only redraw if needed
    if (!exists $self->{data}{$key}) {
        $self->{last_motion_key} = undef;
        if ($self->in_select_mode) {
            $self->reset_cursor;
        }
        if (my $g = $self->{end_hover_func}) {
            $g->($key);
            $self->queue_draw;
        }
    }
    elsif ($last_key ne $key && $f) {
        #  these callbacks add to the highlights so any draw is done then
        $f->($key);
        $self->{last_motion_key} = $key;

        if ($self->in_select_mode) {
            $self->set_cursor_from_name('pointer');
            $self->{motion_cursor_name} = 'pointer';
        }
    }
    elsif ($self->in_select_mode) {
        $self->set_cursor_from_name($current_cursor_name);
    }

    return FALSE;
}

sub _on_ctl_click {
    my ($self, $widget, $event) = @_;

    my ($x, $y) = $self->get_event_xy($event);

    return FALSE if $x > $self->xmax || $y > $self->ymax || $x < $self->xmin || $y < $self->ymin;

    my $key = $self->snap_coord_to_grid_id($x, $y);

    my $f = $self->{ctl_click_func};

    #  only redraw if needed
    if ($f && exists $self->{data}{$key}) {
        $f->($key);
    }

    return FALSE;
}

#  also a bad name but now does nothing
sub _select_while_not_selecting {
    return;
}

sub _on_selection_release {
    my ($self, $x, $y) = @_;

    my $f = $self->{select_func};
    if ($f && $self->{selecting}) {
        #  @rect is passed on to the callback
        my @rect = ($self->{sel_start_x}, $self->{sel_start_y}, $x, $y);
        @rect[0,2] = minmax (@rect[0,2]);
        @rect[1,3] = minmax (@rect[1,3]);

        my ($x1, $y1) = $self->snap_coord_to_grid(@rect[0, 1]);
        my ($x2, $y2) = $self->snap_coord_to_grid(@rect[2, 3]);

        #  save some looping if clicks are outside the bounds
        $x1 = $x2 if $x2 < $self->xmin;
        $y1 = $y2 if $y2 < $self->ymin;
        $x2 = $x1 if $x1 > $self->xmax;
        $y2 = $y1 if $y1 > $self->ymax;

        #  Grab the intersecting elements directly from the grid.
        #  This might get slow for large and sparse grids,
        #  in which event we can look at a spatial index again.
        my @elements;

        #  does the rectangle span the extent?
        if ($x1 < $self->xmin && $x2 > $self->xmax && $y1 < $self->ymin && $y2 > $self->ymax) {
            @elements = map {$_->{element}} values %{$self->{data}};
        }
        #  must have one edge of the rectangle on the grid
        elsif (($x1 <= $self->xmax && $x2 >= $self->xmin) || ($y1 <= $self->ymax && $y2 >= $self->ymin)) {
            my ($cx, $cy) = @{$self->get_cell_sizes};

            #  more snapping to save looping
            $x1 = max ($x1, $self->xmin + $cx/2);
            $y1 = max ($y1, $self->ymin + $cy/2);
            $x2 = min ($x2, $self->xmax - $cx/2);
            $y2 = min ($y2, $self->ymax - $cy/2);

            for (my $xx = $x1; $xx <= $x2; $xx += $cx) {
                for (my $yy = $y1; $yy <= $y2; $yy += $cy) {
                    my $id = "$xx:$yy";
                    my $ref = $self->{data}{$id}
                        // next;
                    push @elements, $ref->{element};
                }
            }
        }

        # my $elements = [];
        # $self->{rtree}->query_partly_within_rect(@rect, $elements);

        # call callback, using original event coords
        $f->(\@elements, undef, \@rect);
    }

    return FALSE;
}

sub draw_cells_cb {
    my ($self, $context) = @_;

    #  somewhat clunky but we otherwise cannot see the boundaries for large data sets
    my $c = $self->{cellsizes}[0] / 100;
    if (!$self->isa('Biodiverse::GUI::Canvas::Matrix')) {
        my @d2 = $context->device_to_user_distance (0.15,0.15);
        $c = max($d2[0], $c);
    }

    $context->set_line_width($c);

    my (%by_colour, %colours_rgb, %colours_rgba);
    my $colour_data = $self->get_colours_last_used_for_plotting;
    \%by_colour    = $colour_data->{rect_by_colour} // {};
    \%colours_rgb  = $colour_data->{colours_rgb} // {};
    \%colours_rgba = $colour_data->{colours_rgba} // {};

    state $default_rgb  = [1,1,1];

    foreach my ($colour_key, $aref) (%by_colour) {
        if (my $rgba = $colours_rgba{$colour_key}) {
            $context->set_source_rgba(@$rgba);
        }
        else {
            $context->set_source_rgb(@{$colours_rgb{$colour_key} // $default_rgb});
        }
        $context->rectangle(@$_) foreach @$aref;
        $context->fill;
    }

    if ($self->get_cell_show_outline) {
        my @outline_colour = $self->rgba_to_cairo ($self->get_cell_outline_colour);
        $context->set_source_rgb(@outline_colour);
        \my @borders = $self->{border_rects} // $self->rebuild_border_rects;
        $context->rectangle(@$_) foreach @borders;
        $context->stroke;
    }

    return;
}


#  for debug
sub _bounding_box_page_units {
    my ($self, $cx) = @_;
return;
#     $cx->set_matrix($self->{orig_tfm_mx});
    # $cx->set_matrix();

    my $drawable = $self->drawable;

    my $draw_size = $drawable->get_allocation();
    my ($canvas_w, $canvas_h, $canvas_x, $canvas_y) = @$draw_size{qw/width height x y/};
    ($canvas_x, $canvas_y) = (0,0);
    my $centre_x = $canvas_w / 2 + $canvas_x;
    my $centre_y = $canvas_h / 2 + $canvas_y;
    my $size     = ($canvas_w - $canvas_x) / 8;
# $size = .1;
    state $printed = 0;
    if (!$printed) {
        say "rectangle($centre_x - $size, $centre_y - $size, 2 * $size, 2 * $size)";
        say join ' ', @$draw_size{qw/width height x y/};
        $printed++;
    }

    $cx->set_source_rgb(0.5, 0.5, 0.5);
    $cx->rectangle($centre_x - $size, $centre_y - $size, 2 * $size, 2 * $size);
    $cx->stroke;

    # $cx->set_matrix($self->{matrix});

    return;
}

sub snap_coord_to_grid {
    my ($self, $x, $y) = @_;
    my $c = $self->{cellsizes};
    my $grid_x = $self->xmin + $c->[0] * floor (($x - $self->xmin) / $c->[0]) + $c->[0] / 2;
    my $grid_y = $self->ymin + $c->[1] * floor (($y - $self->ymin) / $c->[1]) + $c->[1] / 2;
    return ($grid_x, $grid_y);
}

sub snap_coord_to_grid_id {
    my ($self, $x, $y) = @_;
    return join ':', $self->snap_coord_to_grid($x, $y);
}


sub map_to_cell_coord {
    my ($self, $x, $y) = @_;
    my $cell_x = $self->{ncells_x} * ($x - $self->xmin) / ($self->xmax - $self->xmin);
    my $cell_y = $self->{ncells_y} * ($y - $self->ymin) / ($self->ymax - $self->ymin);
    return ($cell_x, $cell_y);
}

sub map_to_cell_id {
    my ($self, $x, $y) = @_;
    return join ':', map {floor $_} $self->map_to_cell_coord($x, $y);
}

sub cell_to_map_coord {
    my ($self, $x, $y) = @_;
    my $map_x = $self->xmin + $x * $self->{cellsizes}[0];
    my $map_y = $self->ymin + $y * $self->{cellsizes}[1];
    return ($map_x, $map_y);
}

#  snap coord to cells then scale
sub cell_to_map_centroid {
    my ($self, $x, $y) = @_;
    confess 'undef xmin' if !defined ($self->xmin);
    confess 'undef ymin' if !defined ($self->ymin);
    my $map_x = $self->xmin + floor($x) * $self->{cellsizes}[0] + $self->{cellsizes}[0] / 2;
    my $map_y = $self->ymin + floor($y) * $self->{cellsizes}[1] + $self->{cellsizes}[1] / 2;
    return ($map_x, $map_y);
}

sub get_data_extents {
    my ($self, $data) = @_;
    $data //= $self->{data};
    my (@xmin, @xmax, @ymin, @ymax);
    foreach my $cell (values %$data) {
        my $bound = $cell->{bounds};
        push @xmin, $bound->[0];
        push @ymin, $bound->[1];
        push @xmax, $bound->[2];
        push @ymax, $bound->[3];
    }
    return (min(@xmin), max(@xmax), min(@ymin), max(@ymax));
}

sub rect_canonicalise {
    my ($self, $rect) = @_;
    ($rect->[0], $rect->[2]) = minmax($rect->[2], $rect->[0]);
    ($rect->[1], $rect->[3]) = minmax($rect->[3], $rect->[1]);
}

sub get_base_struct {
    my $self = shift;
    return $self->{data_source};
}

sub have_data {
    my ($self) = @_;
    defined $self->{data};
}

sub set_base_struct {
    my ($self, $source) = @_;

    my $count = $source->get_element_count;
    croak "No groups to display - BaseData is empty\n"
        if $count == 0;

    say "[Grid] Grid loading $count elements (cells)";

    $self->{data_source} = $source;

    my $bd = $source->get_basedata_ref;

    state $cache_name = 'GUI_2D_PLOT_DATA';
    my $cached_data = $bd->get_cached_value_dor_set_default_href ($cache_name);

    my @res = $self->calculate_cell_sizes($source); #  handles zero and text

    my ($cell_x, $cell_y) = @res[0, 1]; #  just grab first two for now - update the caching if we ever change
    $cell_y ||= $cell_x;                #  default to a square if not defined or zero

    if (%$cached_data) {
        # say 'Cache hit';
        $self->{data}  = $cached_data->{data};
        $self->{rtree} = $cached_data->{rtree};
    }
    else {
        my $cell2x = $cell_x / 2;
        my $cell2y = $cell_y / 2;

        my %data;
        #  sorted list for consistency when there are >2 axes
        foreach my $element ($source->get_element_list_sorted) {
            my ($x, $y) = $source->get_element_name_coord(element => $element);
            $y //= $res[1];

            my $key = "$x:$y";
            next if exists $data{$key};

            my $coord = [ $x, $y ];
            my $bounds = [ $x - $cell2x, $y - $cell2y, $x + $cell2x, $y + $cell2y ];

            $data{$key}{coord} = $coord;
            $data{$key}{bounds} = $bounds;
            $data{$key}{rect} = [ @$bounds[0, 1], $res[0], $res[1] ];
            $data{$key}{centroid} = [ @$coord ];
            $data{$key}{element} = $element;
        }

        #  Now build an rtree - random order is faster, hence it is outside the initial allocation
        #  (An STR Tree would be faster to build)
        #  Actually, we do not really need it for grids.
        #  We can look at an STR tree for non-gridded data.
        # my $rtree = $self->{rtree} = Tree::R->new;
        # foreach my $key (keys %data) {
        #     $rtree->insert($data{$key}{element}, @{$data{$key}{bounds}});
        # }

        $cached_data->{data} = $self->{data} = \%data;
        # $cached_data->{rtree} = $self->{rtree};
    }

    #  the rest could also be cached but does not take long

    $self->rebuild_border_rects;

    my ($min_x, $max_x, $min_y, $max_y) = $self->get_data_extents();

    $self->init_dims(
        xmin => $min_x,
        xmax => $max_x,
        ymin => $min_y,
        ymax => $max_y,
    );

    $self->{cellsizes} = [ $cell_x, $cell_y ];
    $self->{ncells_x} = ($max_x - $min_x) / $cell_x;
    $self->{ncells_y} = ($max_y - $min_y) / $cell_y;

    # say 'Bounding box: ' . join q{ }, $min_x, $min_y // '', $max_x, $max_y // '';

    # Store info needed by load_shapefile
    $self->{dataset_info} = [ $min_x, $min_y, $max_x, $max_y, $cell_x, $cell_y ];

    return 1;
}

sub rebuild_border_rects {
    my $self = shift;

    my $data = $self->{data};
    return if !$data;

    $self->{border_rects} = [map {$_->{rect}} values %$data];
}

sub calculate_cell_sizes {
    my ($self, $data) = @_;

    #  handle text groups here
    my @cell_sizes = map {$_ < 0 ? 1 : $_} $data->get_cell_sizes;

    say 'Warning: only the first two axes are used for plotting'
        if (@cell_sizes > 2);

    my @zero_axes = List::MoreUtils::indexes { $_ == 0 } @cell_sizes;

    AXIS:
    foreach my $i (@zero_axes) {
        my $axis = $cell_sizes[$i];

        # If zero size, we want to display every point
        # Fast dodgy method for computing cell size
        #
        # 1. Sort coordinates
        # 2. Find successive differences
        # 3. Sort differences
        # 4. Make cells square with median distances

        say "[Grid] Calculating median separation distance for axis $i cell size";

        #  Store a list of all the unique coords on this axis
        #  Should be able to cache by indexing via @zero_axes
        my %axis_coords;
        my $elts = $data->get_element_hash();
        foreach my $element (keys %$elts) {
            my @axes = $data->get_element_name_as_array(element => $element);
            $axis_coords{$axes[$i]}++;
        }

        my @array = sort {$a <=> $b} keys %axis_coords;

        my %diffs;
        foreach my $i (1 .. $#array) {
            my $d = abs( $array[$i] - $array[$i-1]);
            $diffs{$d} = undef;
        }

        my @diffs = sort {$a <=> $b} keys %diffs;
        $cell_sizes[$i] = ($diffs[int ($#diffs / 2)] || 1);
    }

    say '[Grid] Using cellsizes ', join (', ', @cell_sizes);

    return wantarray ? @cell_sizes : \@cell_sizes;
}

sub get_cell_sizes {
    $_[0]{cellsizes};
}

sub colour {
    my ($self, $colours) = @_;

    my $is_hash = is_hashref($colours);

    #  clear the previous colours
    $self->set_colours_last_used_for_plotting (undef);

    my $colour_none = $self->get_colour_for_undef // COLOUR_WHITE;

    my $data = $self->{data};
    my (%rect_by_colour, %colours_rgb, %colours_rgba);

    my %as_array;

    CELL:
    for my \%cell (values %$data) {
        #  sometimes we are called before all cells have contents
        last CELL if !defined $cell{coord};

        #  one day we will just pass a hash
        my $elt = $cell{element};
        my $colour_ref
            = $is_hash
            ? $colours->{$elt}
            : $colours->($elt);
        $colour_ref //= $colour_none;

        next CELL if $colour_ref eq '-1';

        #  Cairo does not like Gtk3::Gdk::RGBA objects
        $colours_rgb{$colour_ref} = $as_array{$colour_ref} //= [$self->rgb_to_array($colour_ref)];

        my $aref = $rect_by_colour{$colour_ref} //= [];
        push @$aref, $cell{rect};
    }

    $self->set_colours_last_used_for_plotting (
        {
            rect_by_colour => \%rect_by_colour,
            colours_rgb    => \%colours_rgb,
            colours_rgba   => \%colours_rgba,  #  not used for spatial grids yet
        }
    );

    return;
}

{
    state $cache_name = 'last_colours_used_for_colouring';
    sub set_colours_last_used_for_plotting {
        my ($self, $val) = @_;
        return $self->set_cached_value ($cache_name => $val);
    }

    sub get_colours_last_used_for_plotting {
        my ($self) = @_;
        return $self->get_cached_value ($cache_name);
    }
}

sub get_legend_hue {
    my $self = shift;
    my $legend = $self->get_legend;
    $legend->get_hue;
}

sub show_legend {
    my $self = shift;
    $self->get_legend->show;
}

sub hide_legend {
    my $self = shift;
    $self->get_legend->hide;
}

sub mark_with_circles {
    my ($self, $elements) = @_;

    $self->{highlights}{circles} = $elements;

    return;
}

sub mark_with_dashes {
    my ($self, $elements) = @_;

    $self->{highlights}{dashes} = $elements;

    return;
}

sub clear_marks {
    my ($self, $elements) = @_;
    $self->{highlights} = undef;
}

sub plot_highlights {
    my ($self, $cx) = @_;

    my $cellsizes = $self->{cellsizes};

    $cx->save;
    $cx->set_source_rgba(0, 0, 0, 0.6);

    if (my $elements = $self->{highlights}{circles}) {
        no autovivification;
        $cx->set_line_width($cellsizes->[0] / 10);
        foreach my $c (grep {defined} map {$self->{data}{$_}{centroid}} @$elements) {
            $cx->arc(@$c, $cellsizes->[0] / 4, 0, 2.0 * PI);
            $cx->close_path;
        };
        $cx->fill;
    };
    if (my $elements = $self->{highlights}{dashes}) {
        no autovivification;
        $cx->set_line_width($cellsizes->[0] / 10);
        foreach my $c (grep {defined} map {$self->{data}{$_}{centroid}} @$elements) {
            $cx->move_to($c->[0] - $cellsizes->[0] / 3, $c->[1]);
            $cx->line_to($c->[0] + $cellsizes->[0] / 3, $c->[1]);
        }
        $cx->stroke;
    }

    $cx->restore;

    return FALSE;
}

sub clear_range_convex_hulls {
    my $self = shift;
    $self->set_overlay(
        cb_target   => 'range_convex_hulls',
        plot_on_top => 1,
        data        => undef,
    );
}

sub clear_range_concave_hulls {
    my $self = shift;
    $self->set_overlay(
        cb_target   => 'range_concave_hulls',
        plot_on_top => 1,
        data        => undef,
    );
}

sub clear_range_convex_hull_union {
    my $self = shift;
    $self->set_overlay(
        cb_target   => 'range_convex_hull_union',
        plot_on_top => 1,
        data        => undef,
    );
}

sub clear_range_concave_hull_union {
    my $self = shift;
    $self->set_overlay(
        cb_target   => 'range_concave_hull_union',
        plot_on_top => 1,
        data        => undef,
    );
}

sub clear_range_circumcircles {
    my $self = shift;
    $self->set_overlay(
        cb_target   => 'range_circumcircles',
        plot_on_top => 1,
        data        => undef,
    );
}

sub clear_range_circumcircle_union {
    my $self = shift;
    $self->set_overlay(
        cb_target   => 'range_circumcircle_union',
        plot_on_top => 1,
        data        => undef,
    );
}

sub set_overlay {
    my ($self, %args) = @_;
    my ($shapefile, $colour, $plot_on_top, $alpha, $type, $linewidth)
      = @args{qw /shapefile colour plot_on_top alpha type linewidth/};

    my $cb_target_name = $args{cb_target} // ($plot_on_top ? 'overlays' : 'underlays');

    if (!defined $shapefile && ! defined $args{data}) {
        #  clear it
        $self->{callbacks}{$cb_target_name} = undef;
        $self->drawable->queue_draw;
        return;
    }

    my $data = $args{data} // $self->load_shapefile($shapefile);

    my @rgba = (
        $self->rgb_to_array($colour),
        $alpha // 1,
    );
    my $stroke_or_fill = $type eq 'polygon' ? 'fill' : 'stroke';

    $linewidth ||= 1;

    my $cb;
    if (is_blessed_ref ($data) && $data->isa('Biodiverse::Geometry::Circle')) {
        $cb = sub {
            my ($self, $cx) = @_;
            $cx->set_matrix($self->{matrix});
            $cx->set_source_rgba(@rgba);
            #  line width should be an option in the GUI
            $cx->set_line_width(max($cx->device_to_user_distance($linewidth, $linewidth)));
            $cx->arc(@{$data->centre}, $data->radius, 0, 2.0 * PI);
            $cx->close_path;
            $cx->$stroke_or_fill;
        }
    }
    elsif (is_arrayref ($data) && is_blessed_ref ($data->[0])) {
        $cb = sub {
            my ($self, $cx) = @_;
            $cx->set_matrix($self->{matrix});
            $cx->set_source_rgba(@rgba);
            #  line width should be an option in the GUI
            $cx->set_line_width(max($cx->device_to_user_distance($linewidth, $linewidth)));

            foreach my $shape (@$data) {
                my $g = $shape->get_geometry;
                foreach my \@part (@$g) {
                    foreach my \@vertices (@part) {
                        $cx->move_to(@{$vertices[0]});
                        $cx->line_to(@$_) foreach @vertices;
                    }
                }
            }
            $cx->$stroke_or_fill;
        };
    }
    else {  #  label range convex hulls etc
        $cb = sub {
            my ($self, $cx) = @_;

            $cx->set_matrix($self->{matrix});
            $cx->set_source_rgba(@rgba);
            #  line width should be an option in the GUI
            $cx->set_line_width(max($cx->device_to_user_distance(1, 1)));

            foreach \my @segment (@$data)
            {
                $cx->move_to(@{$segment[0]});
                $cx->line_to(@$_) foreach @segment;
            }
            $cx->$stroke_or_fill;
        };
    }

    my $aref = $self->{callbacks}{$cb_target_name} //= [];
    push @$aref, $cb;

    $self->queue_draw;

    return;
}

sub _error_msg_no_shapes_in_plot_area {
    state $txt = <<~'EOL'
        No shapes overlap the plot area, file will be ignored.

        A common cause is that the shapefile coordinate system does
        not match that of the BaseData, for example your BaseData
        is in a UTM coordinate system but the shapefile is in
        decimal degrees.  If this is the case then your shapefile
        can be reprojected to match your spatial data using GIS software.

        This message will be shown only once.
        EOL
    ;
    return $txt;
}

sub load_shapefile {
    my ($self, $shapefile) = @_;

    my $fname = $shapefile->{filebase};
    my $shape_cache = $self->get_cached_value_dor_set_default_href ('shapefiles');
    return $shape_cache->{$fname}
        if $shape_cache->{$fname};

    my $dims = $self->{dims};
    my ($min_x, $min_y, $max_x, $max_y) = map {$dims->$_} (qw/xmin ymin xmax ymax/);
    my ($cell_x, $cell_y) = @{$self->{cellsizes}};

    my @rect = (
        $min_x - $cell_x,
        $min_y - $cell_y,
        $max_x + $cell_x,
        $max_y + $cell_y,
    );

    # Get shapes within visible region - allow for cell extents
    my @shapes = $shapefile->shapes_in_area (@rect);

    my $shape_count_in_plot_area = @shapes;
    say "[Grid] Shapes within plot area: $shape_count_in_plot_area";

    my $gui = Biodiverse::GUI::GUIManager->instance;
    if (!$shape_count_in_plot_area) {
        use Path::Tiny qw /path/;
        my $msg = $self->_error_msg_no_shapes_in_plot_area;
        $msg = path($fname)->basename . ": $msg\n\nFull file path:\n$fname";
        $gui->report_error (
            $msg,
            'No shapes overlap the plot area',
        );
        $shape_cache->{$fname} = [];
        return;
    }

    my @features;
    my @bnd_extrema;

    if ($shapefile->isa('Geo::Shapefile')) {
        # Add all shapes
        foreach my $shapeid (@shapes) {
            my $shape = $shapefile->get_shp_record($shapeid);

            #  track the bound extents so we can warn if they will be tiny
            my @bnds = $shape->bounds;
            @bnd_extrema = @bnds if !@bnd_extrema;
            $bnd_extrema[0] = min ($bnd_extrema[0], $bnds[0]);
            $bnd_extrema[1] = min ($bnd_extrema[1], $bnds[1]);
            $bnd_extrema[2] = max ($bnd_extrema[2], $bnds[2]);
            $bnd_extrema[3] = max ($bnd_extrema[3], $bnds[3]);

            # Make polygon from each "part"
            BY_PART:
            foreach my $part (1 .. $shape->num_parts) {

                my @plot_points;    # x,y coordinates that will be given to canvas
                my @segments = $shape->get_segments($part);

                #  add the points from all of the vertices
                #  Geo::ShapeFile gives them to us as vertex pairs
                #  so extract the first point from each
                POINT_TO_ADD:
                foreach my $vertex (@segments) {
                    push @plot_points, [
                        $vertex->[0]->{X},
                        $vertex->[0]->{Y},
                    ];
                }

                #  Get the end of the line, otherwise we don't plot the last vertex.
                #  (Segments are stored as start-end pairs of vertices).
                my $current_vertex = $segments[-1];
                push @plot_points, [
                    $current_vertex->[1]->{X},
                    $current_vertex->[1]->{Y},
                ];

                # must have more than one point (two coords)
                next if @plot_points < 2;

                push @features, \@plot_points;
            }
        }
    }
    else {  #  we are the newer structure
        @features = @shapes;
        my @load_ids;  #  not yet loaded due to lazy loading
        foreach my $shape (@features) {
            my @bnds = $shape->get_extent;
            @bnd_extrema = @bnds if !@bnd_extrema;
            $bnd_extrema[0] = min ($bnd_extrema[0], $bnds[0]);
            $bnd_extrema[1] = min ($bnd_extrema[1], $bnds[1]);
            $bnd_extrema[2] = max ($bnd_extrema[2], $bnds[2]);
            $bnd_extrema[3] = max ($bnd_extrema[3], $bnds[3]);
            if (!$shape->get_geometry) {
                push @load_ids, $shape->get_id;
            }
        }
        if (@load_ids) {
            $shapefile->reload_geometries(\@load_ids);
        }
    }

    my $x_extent = $max_x - $min_x;
    my $y_extent = $max_y - $min_y;
    my $x_ratio = ($bnd_extrema[2] - $bnd_extrema[0]) / $x_extent;
    my $y_ratio = ($bnd_extrema[3] - $bnd_extrema[1]) / $y_extent;
    if ($x_ratio < 0.005 && $y_ratio < 0.005) {
        my $bd_bnds  = "($min_x, $min_y), ($max_x, $max_y)";
        my $shp_bnds = "($bnd_extrema[0], $bnd_extrema[1]), ($bnd_extrema[2], $bnd_extrema[3])";

        my $error = <<"END_OF_ERROR"
Warning: Shapes might not be visible.

The extent of the $shape_count_in_plot_area shapes overlapping the
plot area is very small.  They might not be visible as a result.

One possible cause is that the shapefile coordinate system does
not match that of the BaseData, for example your BaseData
is in a UTM coordinate system but the shapefile is in
decimal degrees.  If this is the case then your shapefile
can be reprojected to match your spatial data using GIS software.

Respective bounds are (minx, miny), (maxx, maxy):
BaseData: $bd_bnds
Shapefile: $shp_bnds
END_OF_ERROR
        ;

        $gui->report_error (
            $error,
            'Small extent',
        );
    }

    $shape_cache->{$fname} = \@features;

    return \@features;
}


sub get_cell_outline_colour {
    $_[0]->{cell_outline_colour} //= CELL_OUTLINE_COLOUR;
}


sub set_cell_outline_colour {
    my ($self, $colour) = @_;

    #  should not be calling out to parent here
    $colour //= $self->get_parent_tab->get_colour_from_chooser ($self->get_cell_outline_colour);

    #  if still no colour chosen
    return if !$colour;

    $self->{cell_outline_colour} = $colour;  #  store for later re-use

    return;
}

sub set_cell_show_outline {
    my ($self, $active) = @_;

    $self->{show_cell_outlines} = $active;

    return;
}

sub get_cell_show_outline {
    my ($self) = @_;
    return $self->{show_cell_outlines};
}

1;  # end of package
