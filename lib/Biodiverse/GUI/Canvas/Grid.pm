package Biodiverse::GUI::Canvas::Grid;

use strict;
use warnings;
use 5.036;

our $VERSION = '4.99_007';

use experimental qw /refaliasing declared_refs for_list/;
use Glib qw/TRUE FALSE/;
use Gtk3;
use List::Util qw /min max/;
use List::MoreUtils qw /minmax/;
use Ref::Util qw /is_hashref/;
use POSIX qw /floor/;
use Carp qw /croak confess/;
use Tree::R;

use constant PI => 3.1415927;

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
        map        => sub {shift->draw_cells_cb(@_)},
        highlights => sub {shift->plot_highlights(@_)},
        overlays   => sub {shift->_bounding_box_page_units(@_)},
        underlays  => sub {shift->underlay_cb(@_)},
        legend     => sub {shift->get_legend->draw(@_)},
    };
    $self->{callback_order} = [qw /underlays map overlays legend highlights/];

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
        my @rect = ($self->{sel_start_x}, $self->{sel_start_y}, $x, $y);
        if ($rect[0] > $rect[2]) {
            @rect[0,2] = @rect[2,0];
        }
        if ($rect[1] > $rect[3]) {
            @rect[3,1] = @rect[1,3];
        }

        my $elements = [];
        $self->{rtree}->query_partly_within_rect(@rect, $elements);

        # call callback, using original event coords
        $f->($elements, undef, \@rect);
    }

    return FALSE;
}

sub _get_data {
    my $self = shift;
    my $dims = $self->{dims};
    my ($xmin, $xmax, $ymin, $ymax) = map {$dims->$_} (qw/xmin xmax ymin ymax/);
    my $cellsizes = $self->{cellsizes};

    # say join ' ', ($xmin, $xmax, $ymin, $ymax, $cellsizes);

    my %data;
    my $nx = floor(($xmax - $xmin) / $cellsizes->[0]);
    my $ny = floor(($ymax - $ymin) / $cellsizes->[1]);
    my $cell2x = $cellsizes->[0] / 2;
    my $cell2y = $cellsizes->[1] / 2;

    srand(12345);
    for my $col (0 .. $nx - 1) {

        for my $row (0 .. $ny - 1) {
            next if rand() < 0.15;
            my $key = "$col:$row";
            my ($x, $y) = $self->cell_to_map_centroid($col, $row);
            # say "$key $x $y $col $row";
            my $coord = [ $x, $y ];
            my $bounds = [ $x - $cell2x, $y - $cell2y, $x + $cell2x, $y + $cell2y ];
            my $val = $x + $y;
            $data{$key}{val} = $val;
            $data{$key}{coord} = $coord;
            $data{$key}{bounds} = $bounds;
            $data{$key}{rect} = [ @$bounds[0, 1], $cellsizes->[0], $cellsizes->[1] ];
            $data{$key}{centroid} = [ @$coord ];

            my $rgb = [ $col / $nx, $row / $ny, 0 ];
            $data{$key}{rgb} = $rgb;
            $data{$key}{rgb_orig} = [ @$rgb ];
            $data{$key}{nbrs} = [
                map
                  {join ':', @$_}
                  ([ $col - 1, $row ], [ $col, $row + 1 ], [ $col + 1, $row ], [ $col, $row - 1 ])
            ];

        }

    }

    return \%data;
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

    my $data = $self->{data};

    my $default_rgb = [1,1,1];

    my (%by_colour, %colours, %colours_rgba);
    #  avoid rebuilding the colours if they have not changed
    if (my $cache = $self->get_colours_last_used_for_plotting) {
        \%by_colour    = $cache->{by_colour};
        \%colours      = $cache->{colours};
        \%colours_rgba = $cache->{colours_rgba};
    }
    else {
        for my \%elt_hash (values %$data) {
            my $colour = $elt_hash{rgba};
            if (defined $colour) {
                $colours_rgba{$colour} = $colour
            }
            else {
                $colour = $elt_hash{rgb} // $default_rgb;
                $colours{$colour} = $colour;
            };
            my $aref = $by_colour{$colour} //= [];
            push @$aref, $elt_hash{rect};
        }
        $self->set_colours_last_used_for_plotting (
            {
                by_colour    => \%by_colour,
                colours      => \%colours,
                colours_rgba => \%colours_rgba,
            }
        );
    }

    foreach my ($colour_key, $aref) (%by_colour) {
        if (my $rgba = $colours_rgba{$colour_key}) {
            $context->set_source_rgba(@$rgba);
        }
        else {
            my $rgb = $colours{$colour_key};
            $context->set_source_rgb(@$rgb);
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

sub overlay_cb {
    my ($self, $context) = @_;

    my ($ncells_x, $ncells_y) = @$self{qw/ncells_x ncells_y/};

    state @vertices = (
        [ $self->cell_to_map_coord($ncells_x * 0.15, $ncells_y * 0.15) ],
        [ $self->cell_to_map_coord($ncells_x * 0.5,  $ncells_y * 0.5) ],
        [ $self->cell_to_map_coord($ncells_x * 0.85, $ncells_y * 0.15) ],
        [ $self->cell_to_map_coord($ncells_x * 0.85, $ncells_y * 0.85) ],
        [ $self->cell_to_map_coord($ncells_x * 0.15, $ncells_y * 0.85) ],
        [ $self->cell_to_map_coord($ncells_x * 0.15, $ncells_y * 0.15) ],
    );
    state $path = [
        { type => 'move_to', points => $vertices[0] },
        map {{ type => 'line_to', points => $_ }} @vertices[1 .. $#vertices],
        # { type => 'close_path', points => [] },
    ];

    $context->set_line_width($self->{cellsizes}[0] / 10);
    $context->set_source_rgb(0, 0.5, 0);
    # say "Setting path";
    #  should be able to use the path structure directly as a Cairo::Path?
    foreach my $elt (@$path) {
        my $method = $elt->{type};
        # say "$method (" . join (' ', @{$elt{points}}) . ")";
        $context->$method(@{$elt->{points}});
    }
    $context->stroke;
    return;
}

sub underlay_cb {
    my ($self, $context) = @_;
return;
    
    state @vertices = (
        [ $self->cell_to_map_coord(-0.2, -0.2) ],
        [ $self->cell_to_map_coord($self->{ncells_x} + 0.2, -0.2) ],
        [ $self->cell_to_map_coord($self->{ncells_x} + 0.2, $self->{ncells_y} + 0.2) ],
        [ $self->cell_to_map_coord(-0.2, $self->{ncells_y} + 0.2) ],
        [ $self->cell_to_map_coord(-0.2, -0.2) ],
    );
    state $path = [
        { type => 'move_to', points => $vertices[0] },
        map {{ type => 'line_to', points => $_ }} @vertices[1 .. $#vertices],
        # { type => 'close_path', points => [] },
    ];

    $context->set_line_width(3);
    # $context->set_source_rgb(0.53, 0.53, 0.53);
    $context->set_source_rgb(0.8, 0.8, 0.8);

    # say "Setting path";
    #  should be able to use the path structure directly as a Cairo::Path?
    foreach my $elt (@$path) {
        my $method = $elt->{type};
        # say "$method (" . join (' ', @{$elt{points}}) . ")";
        $context->$method(@{$elt->{points}});
    }
    $context->close_path;
    $context->fill;
    # $context->queue_draw;

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

sub set_base_struct {
    my ($self, $source) = @_;

    my $count = $source->get_element_count;
    croak "No groups to display - BaseData is empty\n"
        if $count == 0;

    $self->{data_source} = $source;

    my @res = $self->calculate_cell_sizes($source);  #  handles zero and text

    my ($cell_x, $cell_y) = @res[0,1];  #  just grab first two for now
    $cell_y ||= $cell_x;  #  default to a square if not defined or zero

    my $cell2x = $cell_x / 2;
    my $cell2y = $cell_y / 2;

    my %data;
    $self->{data} = \%data;

    my %elements;
    $self->{element_data_map} = \%elements;

    say "[Grid] Grid loading $count elements (cells)";

    #  sorted list for consistency when there are >2 axes
    foreach my $element ($source->get_element_list_sorted) {
        my ($x, $y) = $source->get_element_name_coord(element => $element);
        $y //= $res[1];

        my $key = "$x:$y";
        next if exists $data{$key};

        my $coord = [ $x, $y ];
        my $bounds = [ $x - $cell2x, $y - $cell2y, $x + $cell2x, $y + $cell2y ];

        $data{$key}{coord}  = $coord;
        $data{$key}{bounds} = $bounds;
        $data{$key}{rect}   = [ @$bounds[0, 1], $res[0], $res[1] ];
        $data{$key}{centroid} = [ @$coord ];
        $data{$key}{element}  = $element;
        $elements{$element}   = $key;
    }

    $self->{border_rects} = [map {$_->{rect}} values %data];

    my ($min_x, $max_x, $min_y, $max_y) = $self->get_data_extents();

    $self->init_dims (
        xmin    => $min_x,
        xmax    => $max_x,
        ymin    => $min_y,
        ymax    => $max_y,
    );

    $self->{cellsizes} = [$cell_x, $cell_y];
    $self->{ncells_x} = ($max_x - $min_x) / $cell_x;
    $self->{ncells_y} = ($max_y - $min_y) / $cell_y;

    # say 'Bounding box: ' . join q{ }, $min_x, $min_y // '', $max_x, $max_y // '';

    # Store info needed by load_shapefile
    $self->{dataset_info} = [$min_x, $min_y, $max_x, $max_y, $cell_x, $cell_y];

    #  now build an rtree - random order is faster so it is outside the initial allocation
    my $rtree = $self->{rtree} = Tree::R->new;
    foreach my $key (keys %data) {
        $rtree->insert($data{$key}{element}, @{ $data{$key}{bounds} });
    }

    #  save some coords stuff for later transforms - poss no longer needed
    $self->{base_struct_cellsizes} = [$cell_x, $cell_y];
    $self->{base_struct_bounds}    = [$min_x, $min_y, $max_x, $max_y];

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

    my $colour_none = $self->get_colour_for_undef // COLOUR_WHITE;

    CELL:
    foreach my $cell (values %{$self->{data}}) {

        #  sometimes we are called before all cells have contents - should be a loop exit?
        next CELL if !defined $cell->{coord};

        #  one day we will just pass a hash
        my $elt = $cell->{element};
        my $colour_ref
            = $is_hash
            ? $colours->{$elt}
            : $colours->($elt);
        $colour_ref //= $colour_none;

        next CELL if $colour_ref eq '-1';

        #  Cairo does not like Gtk3::Gdk::RGBA objects
        $cell->{rgb} = [$self->rgb_to_array($colour_ref)];
    }

    #  clear this
    $self->set_colours_last_used_for_plotting (undef);

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

    if (my $elements = $self->{highlights}{circles}) {
        no autovivification;
        $cx->set_source_rgb(0, 0, 0);
        $cx->set_line_width($cellsizes->[0] / 10);
        foreach my $c (grep {defined} map {$self->{data}{$_}{centroid}} @$elements) {
            $cx->arc(@$c, $cellsizes->[0] / 4, 0, 2.0 * PI);
            $cx->stroke_preserve;
            $cx->fill;
        };
    };
    if (my $elements = $self->{highlights}{dashes}) {
        no autovivification;
        $cx->set_source_rgb(0, 0, 0);
        $cx->set_line_width($cellsizes->[0] / 10);
        foreach my $c (grep {defined} map {$self->{data}{$_}{centroid}} @$elements) {
            $cx->move_to($c->[0] - $cellsizes->[0] / 3, $c->[1]);
            $cx->line_to($c->[0] + $cellsizes->[0] / 3, $c->[1]);
        }
        $cx->stroke;
    }

    return FALSE;
}

sub set_overlay {
    my ($self, %args) = @_;
    my ($shapefile, $colour, $plot_on_top, $use_alpha, $type)
      = @args{qw /shapefile colour plot_on_top use_alpha type/};

    my $cb_target_name = $plot_on_top ? 'overlays' : 'underlays';

    if (!defined $shapefile) {
        #  clear it
        $self->{callbacks}{$cb_target_name} = undef;
        $self->drawable->queue_draw;
        return;
    }

    my $data = $self->load_shapefile($shapefile);

    my @rgba = (
        $self->rgb_to_array($colour),
        $use_alpha ? 0.5 : 1,
    );
    my $stroke_or_fill = $type eq 'polygon' ? 'fill' : 'stroke';

    my $cb = sub {
        my ($self, $cx) = @_;

        $cx->set_matrix($self->{matrix});
        $cx->set_source_rgba(@rgba);
        #  line width should be an option in the GUI
        $cx->set_line_width(max($cx->device_to_user_distance (1, 1)));

        foreach \my @segment (@$data) {
            $cx->move_to(@{$segment[0]});
            $cx->line_to (@$_) foreach @segment;
        }
        $cx->$stroke_or_fill;
    };

    $self->{callbacks}{$cb_target_name} = $cb;

    $self->queue_draw;

    return;
}

sub _error_msg_no_shapes_in_plot_area {
    state $txt = <<~'EOL'
        No shapes overlap the plot area.

        A common cause is that the shapefile coordinate system does
        not match that of the BaseData, for example your BaseData
        is in a UTM coordinate system but the shapefile is in
        decimal degrees.  If this is the case then your shapefile
        can be reprojected to match your spatial data using GIS software.
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
    my @shapes;
    @shapes = $shapefile->shapes_in_area (@rect);

    my $shapes_in_plot_area = @shapes;
    say "[Grid] Shapes within plot area: $shapes_in_plot_area";

    my $gui = Biodiverse::GUI::GUIManager->instance;
    if (!$shapes_in_plot_area) {
        $gui->report_error (
            $self->_error_msg_no_shapes_in_plot_area,
            'No shapes overlap the plot area',
        );
        return;
    }

    my @features;
    my @bnd_extrema;
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

    my $x_extent = $max_x - $min_x;
    my $y_extent = $max_y - $min_y;
    my $x_ratio = ($bnd_extrema[2] - $bnd_extrema[0]) / $x_extent;
    my $y_ratio = ($bnd_extrema[3] - $bnd_extrema[1]) / $y_extent;
    if ($x_ratio < 0.005 && $y_ratio < 0.005) {
        my $bd_bnds  = "($min_x, $min_y), ($max_x, $max_y)";
        my $shp_bnds = "($bnd_extrema[0], $bnd_extrema[1]), ($bnd_extrema[2], $bnd_extrema[3])";

        my $error = <<"END_OF_ERROR"
Warning: Shapes might not be visible.

The extent of the $shapes_in_plot_area shapes overlapping the
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
