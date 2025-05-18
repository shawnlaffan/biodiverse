package Biodiverse::GUI::Canvas::Grid;

use strict;
use warnings;
use 5.036;

our $VERSION = '4.99_002';

use experimental qw /refaliasing declared_refs for_list/;
use Glib qw/TRUE FALSE/;
use List::Util qw /min max/;
use List::MoreUtils qw /minmax/;
use POSIX qw /floor/;
use Carp qw /croak confess/;

use constant PI => 3.1415927;

use parent 'Biodiverse::GUI::Canvas';

sub new {
    my ($class, %args) = @_;
    my $self = Biodiverse::GUI::Canvas->new (%args);

    #  rebless
    bless $self, $class;

    $self->{callbacks} = {
        map        => sub {shift->draw_cells_cb (@_)},
        highlights => undef,
        overlays   => sub {shift->overlay_cb (@_)},
        underlays  => sub {shift->underlay_cb (@_)},
    };
    # $self->{callback_order} = [qw /underlays map overlays highlights/];
    $self->{callback_order} = [qw /map/];  #  temporary

    # $self->{data} = $self->get_data();

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

#  need a batter name but this is called as a fallback from SUPER::on_motion
sub _on_motion {
    my ($self, $widget, $event, $ref_status) = @_;

    my ($x, $y) = $self->get_event_xy($event);

    return FALSE if $x > $self->xmax || $y > $self->ymax;

    my $key = $self->map_to_cell_id($x, $y);
    my $last_key = $self->{last_key} //= '';;

    my $data = $self->{data};

    if (exists $data->{$last_key} && $last_key ne $key) {
        # say "LK: $last_key, K: $key";
        # if ($last_key ne '') {
        #     say join (' ', @{$data->{$last_key}{rgb}}) . ' : ' . join ' ', @{$data->{$last_key}{rgb_orig}};
        # }
        $data->{$last_key}{rgb} = $data->{$last_key}{rgb_orig};
    }

    if (exists $data->{$key} && $key ne $last_key) {
        # $context->set_line_width(1);
        if ($data->{$key}{bounds}) {

            # \my @rect = $data->{$key}{rect} // [];
            # say $key . " " . join ' ', @rect;
            # $context->set_source_rgb(0, 0, 0.9);
            $data->{$key}{rgb} = [ 0, 0, 0.9 ];
            # $context->rectangle(@rect);
            # $context->fill;
            # \my @b0 = $data->{$key}{bounds};
            # \my @b1 = $data->{$last_key}{bounds} // $data->{$key}{bounds};
            # my @area = (
            #     min($b0[0], $b1[0]),
            #     min($b0[1], $b1[1]),
            #     max($b0[2], $b1[2]),
            #     max($b0[3], $b1[3]),
            # );
            # say join ' ', @area;
            # say join ' ', @b0;
            # say join ' ', @b1;
            my $cellsizes = $self->{cellsizes};

            $self->{callbacks}{highlights} = sub {
                my ($self, $cx) = @_;
                \my @nbrs = $data->{$key}{nbrs} // [];
                foreach my $c (grep {defined} map {$data->{$_}{centroid}} @nbrs) {
                    # $cx->set_line_width(3);
                    $cx->set_line_width($cellsizes->[0] / 10);
                    $cx->set_source_rgb(0, 0, 0);
                    $cx->move_to($c->[0] - $cellsizes->[0] / 3, $c->[1]);
                    $cx->line_to($c->[0] + $cellsizes->[0] / 3, $c->[1]);
                    $cx->stroke;
                }
                #  centre circle
                my $c = $data->{$key}{centroid};
                $cx->arc(@$c, $cellsizes->[0] / 4, 0, 2.0 * PI);
                $cx->set_line_width($cellsizes->[0] / 10);
                $cx->stroke_preserve;
                $cx->set_source_rgb(0, 0, 0);
                $cx->fill;
            };


            #  need to get the whole region that was changed
            # $widget->queue_draw_area(@area);
            # $widget->queue_draw_area (@$coord, $STEP, $STEP);
            # $widget->queue_draw_area (@{$data->{$last_key}{coord}}, $STEP, $STEP);
            # $widget->queue_draw_region (Cairo::Region->create (@$coord, $STEP, $STEP));
            # $widget->queue_draw_region (@{$data->{$last_key}{coord}}, $STEP, $STEP);

            $widget->queue_draw;
        }
    }
    elsif (!$data->{$key}{bounds}) {
        #  only redraw if needed
        if (defined delete $self->{callbacks}{highlights}) {
            $widget->queue_draw;
        }
    }

    $self->{last_key} = $key;

    return FALSE;
}

#  also a bad name
sub _select_while_not_selecting {
    my ($self, $widget, $x, $y) = @_;

    my $key = $self->map_to_cell_id($x, $y);

    my $data = $self->{data};

    if (exists $data->{$key}{rect}) {
        # \my @rect = $data->{$key}{rect};
        # say "BPress: Dv: $x $y, Ev: $ex $ey, ID: $key, rect: " . join ' ', @rect;
        $data->{$key}{rgb_orig} = [ .99, 0, 0.9 ];
        $data->{$key}{rgb} = [ .99, 0, 0.9 ];

        $widget->queue_draw;
        # $last_key = $key;
    }

    return;
}

sub get_data {
    my $self = shift;
    my $dims = $self->{dims};
    my ($xmin, $xmax, $ymin, $ymax, $cellsizes) = (@$dims{qw/xmin xmax ymin ymax/}, $self->{cellsizes});

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

    # Solid box
    # my $mx = $context->get_matrix;
    # $context->set_matrix(Cairo::Matrix->init_identity);
    $context->set_line_width(max($self->{cellsizes}[0] / 100));
    # $context->set_matrix($mx);
    my $data = $self->{data};
    my $n = 0;
    foreach my $key (keys %$data) {
        \my @rgb = $data->{$key}{rgb} // next;
        # \my @coord = $data->{$key}{coord};
        # \my @bounds = $data->{$key}{bounds};
        \my @rect = $data->{$key}{rect};
        $context->set_source_rgb(@rgb);
        $context->rectangle(@rect);
        $context->fill;
        $context->set_source_rgb(0, 0, 0);
        $context->rectangle(@rect);
        $context->stroke;
        $n++;
    }
    # say "Updated $n";
    # $initialised = 1;

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
    $context->set_source_rgb(0.53, 0.53, 0.53);
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

sub set_base_struct {
    my ($self, $source) = @_;

    my $count = $source->get_element_count;
    croak "No groups to display - BaseData is empty\n"
        if $count == 0;

    $self->{data_source} = $source;

    my @res = $self->get_cell_sizes($source);  #  handles zero and text

    my ($cell_x, $cell_y) = @res[0,1];  #  just grab first two for now
    $cell_y ||= $cell_x;  #  default to a square if not defined or zero

    my $cell2x = $cell_x / 2;
    my $cell2y = $cell_y / 2;

    my %data;
    $self->{data} = \%data;

    say "[Grid] Grid loading $count elements (cells)";

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
    }

    my ($min_x, $max_x, $min_y, $max_y) = $self->get_data_extents();

    say 'Bounding box: ' . join q{ }, $min_x, $min_y // '', $max_x, $max_y // '';

    # Store info needed by load_shapefile
    $self->{dataset_info} = [$min_x, $min_y, $max_x, $max_y, $cell_x, $cell_y];

    #  save some coords stuff for later transforms
    $self->{base_struct_cellsizes} = [$cell_x, $cell_y];
    $self->{base_struct_bounds}    = [$min_x, $min_y, $max_x, $max_y];

    return 1;
}

sub get_cell_sizes {
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


1;  # end of package
