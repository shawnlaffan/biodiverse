=head1 GRID

A component that displays a BaseStruct using GnomeCanvas

=cut

package Biodiverse::GUI::Grid;

use 5.010;
use strict;
use warnings;
use Data::Dumper;
use Carp;
use Scalar::Util qw /blessed/;
use List::Util qw /min max/;

use Gtk2;
use Gnome2::Canvas;
use Tree::R;

use Geo::ShapeFile;

our $VERSION = '1.99_006';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::CellPopup;
use Biodiverse::BaseStruct;
use Biodiverse::Progress;
use Biodiverse::GUI::Legend;

require Biodiverse::Config;
my $progress_update_interval = $Biodiverse::Config::progress_update_interval;

##########################################################
# Rendering constants
##########################################################
use constant CELL_SIZE_X        => 10;    # Cell size (canvas units)
use constant CIRCLE_DIAMETER    => 5;
use constant MARK_X_OFFSET      => 2;

use constant MARK_OFFSET_X      => 3;    # How far inside the cells, marks (cross,cricle) are drawn
use constant MARK_END_OFFSET_X  => CELL_SIZE_X - MARK_OFFSET_X;

use constant BORDER_SIZE        => 20;
use constant LEGEND_WIDTH       => 20;

# Lists for each cell container
use constant INDEX_COLOUR       => 0;  # current Gtk2::Gdk::Color
use constant INDEX_ELEMENT      => 1;  # BaseStruct element for this cell
use constant INDEX_RECT         => 2;  # Canvas (square) rectangle for the cell
use constant INDEX_CROSS        => 3;
use constant INDEX_CIRCLE       => 4;
use constant INDEX_MINUS        => 5;

#use constant INDEX_VALUES       => undef; # DELETE DELETE FIXME

use constant HOVER_CURSOR       => 'hand2';

use constant HIGHLIGHT_COLOUR    => Gtk2::Gdk::Color->new(255*257,0,0); # red
use constant COLOUR_BLACK        => Gtk2::Gdk::Color->new(0, 0, 0);
use constant COLOUR_WHITE        => Gtk2::Gdk::Color->new(255*257, 255*257, 255*257);
use constant CELL_OUTLINE_COLOUR => Gtk2::Gdk::Color->new(0, 0, 0);
use constant OVERLAY_COLOUR      => Gtk2::Gdk::Color->parse('#001169');
use constant DARKEST_GREY_FRAC   => 0.2;
use constant LIGHTEST_GREY_FRAC  => 0.8;

##########################################################
# Construction
##########################################################

=head2 Constructor

=over 5

=item frame

The GtkFrame to hold the canvas

=item hscroll

=item vscroll

The scrollbars for the canvas

=item show_legend

Whether to show the legend colour-bar on the right.
Used when spatial indices are plotted

=item show_value

Whether to show a label in the top-left corner.
It can be changed by calling set_value_label

=item hover_func

=item click_func

Closures that will be invoked with the grid cell's element name
whenever cell is hovered over or clicked

=item select_func

=item grid_click_func

Closure that will be called whenever the grid has been right clicked, but not
dragged

=item end_hover_func

=back

=cut


sub new {
    my $class   = shift;
    my %args = @_;
    my $frame   = $args{frame};
    my $hscroll = $args{hscroll};
    my $vscroll = $args{vscroll};
    
    my $show_legend = $args{show_legend} // 0;  #  this is irrelevant now, gets hidden as appropriate (but should allow user to show/hide)
    my $show_value  = $args{show_value}  // 0;

    my $self = {
        hue         => 0,     # default constant-hue red
    }; 
    bless $self, $class;

    #  callback funcs
    $self->{hover_func}      = $args{hover_func};      # move mouse over a cell
    $self->{click_func}      = $args{click_func};      # click on a cell
    $self->{select_func}     = $args{select_func};     # select a set of elements
    $self->{grid_click_func} = $args{grid_click_func}; # right click anywhere
    $self->{end_hover_func}  = $args{end_hover_func};  # move mouse out of hovering over cells

    $self->set_colour_for_undef;

    # Make the canvas and hook it up
    $self->{canvas} = Gnome2::Canvas->new();
    $frame->add($self->{canvas});
    $self->{canvas}->signal_connect_swapped (size_allocate => \&on_size_allocate, $self);

    # Set up custom scrollbars due to flicker problems whilst panning..
    $self->{hadjust} = Gtk2::Adjustment->new(0, 0, 1, 1, 1, 1);
    $self->{vadjust} = Gtk2::Adjustment->new(0, 0, 1, 1, 1, 1);

    $hscroll->set_adjustment( $self->{hadjust} );
    $vscroll->set_adjustment( $self->{vadjust} );
    
    $self->{hadjust}->signal_connect_swapped('value-changed', \&on_scrollbars_scroll, $self);
    $self->{vadjust}->signal_connect_swapped('value-changed', \&on_scrollbars_scroll, $self);

    $self->{canvas}->get_vadjustment->signal_connect_swapped('value-changed', \&on_scroll, $self);
    $self->{canvas}->get_hadjustment->signal_connect_swapped('value-changed', \&on_scroll, $self);

    # Set up canvas
    $self->{canvas}->set_center_scroll_region(0);
    $self->{canvas}->show;
    $self->set_zoom_fit_flag(1);
    $self->{dragging} = 0;

    if ($show_value) {
        $self->setup_value_label();
    }

    # Create background rectangle to receive mouse events for panning
    my $rect = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        y1 => 0,
        x2 => CELL_SIZE_X,
        fill_color_gdk => COLOUR_WHITE,
        #outline_color => "black",
        #width_pixels => 2,
        y2 => CELL_SIZE_X,
    );
    $rect->lower_to_bottom();

    $self->{canvas}->root->signal_connect_swapped (
        event => \&on_background_event,
        $self,
    );

    $self->{back_rect} = $rect;
    # Create the Label legend
    my $legend = Biodiverse::GUI::Legend->new(
        canvas       => $self->{canvas},
        legend_mode  => 'Hue',  #  by default
        width_px     => $self->{width_px},
        height_px    => $self->{height_px},
    );
    $self->set_legend ($legend);

    $self->update_legend;

    $self->{drag_mode} = 'select';

    # Labels::initGrid will set {page} (hacky)

    return $self;
}

sub get_legend {
    my $self = shift;
    return $self->{legend};
}

sub set_legend {
    my ($self, $legend) = @_;
    croak "legend arg not passed" if !defined $legend;
    $self->{legend} = $legend;
}

# Update the position and/or mode of the legend.
sub update_legend {
    my $self = shift;
    my $legend = $self->get_legend;
    if ($self->{width_px} && $self->{height_px}) {
        $legend->reposition($self->{width_px}, $self->{height_px});
    }
    return;
}

sub set_legend_mode {
    my $self = shift;
    my $mode = shift;

    my $legend = $self->get_legend;
    $legend->set_legend_mode($mode);
    $self->colour_cells();
    
    return;
}

sub destroy {
    my $self = shift;

    # Destroy cell groups
    if ($self->{shapefile_group}) {
        $self->{shapefile_group}->destroy();
    }
    if ($self->{cells_group}) {
        $self->{cells_group}->destroy();
    }

#    if ($self->{legend}) {
#        $self->{legend}->destroy();
#        delete $self->{legend};
#
#        foreach my $i (0..3) {
#            $self->{marks}[$i]->destroy();
#        }
#    }

    # Destroy the legend group.
    if ($self->{legend_group}) {
        $self->{legend_group}->destroy();
    }


    $self->{value_group}->destroy if $self->{value_group};
    delete $self->{value_group};
    delete $self->{value_text};
    delete $self->{value_rect};

    delete $self->{marks};

    delete $self->{hover_func};  #??? not sure if helps
    delete $self->{click_func};  #??? not sure if helps
    delete $self->{select_func}; #??? not sure if helps
    delete $self->{grid_click_func};
    delete $self->{end_hover_func};  #??? not sure if helps
    
    delete $self->{cells_group}; #!!!! Without this, GnomeCanvas __crashes__
                                # Apparently, a reference cycle prevents it
                                #   from being destroyed properly,
                                # and a bug makes it repaint in a half-dead state
    delete $self->{shapefile_group};
    delete $self->{back_rect};
    delete $self->{cells};

    delete $self->{canvas};
    
    return;
}

##########################################################
# Setting up the canvas
##########################################################

sub setup_value_label {
    my $self = shift;
    my $group = shift;

    my $value_group = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Group',
        x => 0,
        y => 100,
    );

    my $text = Gnome2::Canvas::Item->new (
        $value_group,
        'Gnome2::Canvas::Text',
        x => 0, y => 0,
        markup => "<b>Value: </b>",
        anchor => 'nw',
        fill_color_gdk => COLOUR_BLACK,
    );

    my ($text_width, $text_height)
        = $text->get('text-width', 'text-height');

    my $rect = Gnome2::Canvas::Item->new (
        $value_group,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        y1 => 0,
        x2 => $text_width,
        y2 => $text_height,
        fill_color_gdk => COLOUR_WHITE,
    );

    $rect->lower(1);
    $self->{value_group} = $value_group;
    $self->{value_text} = $text;
    $self->{value_rect} = $rect;

    return;
}

sub set_value_label {
    my $self = shift;
    my $val = shift;

    $self->{value_text}->set(markup => "<b>Value: </b>$val");

    # Resize value background rectangle
    my ($text_width, $text_height)
        = $self->{value_text}->get('text-width', 'text-height');
    $self->{value_rect}->set(x2 => $text_width, y2 => $text_height);

    return;
}

##########################################################
# Drawing stuff on the grid (mostly public)
##########################################################

#  convert canvas world units to basestruct units
sub units_canvas2basestruct {
    my $self = shift;
    my ($x, $y) = @_;
    
    my $cellsizes = $self->{base_struct_cellsizes};
    my $bounds    = $self->{base_struct_bounds};
    
    my $cellsize_canvas_x = CELL_SIZE_X;
    my $cellsize_canvas_y = $self->{cell_size_y};
    
    my $x_cell_units = $x / $cellsize_canvas_x;
    my $x_base_units = ($x_cell_units * $cellsizes->[0]) + $bounds->[0];
    
    my $y_cell_units = $y / $cellsize_canvas_y;
    my $y_base_units = ($y_cell_units * $cellsizes->[1]) + ($bounds->[1] || 0);
    
    return wantarray
        ? ($x_base_units, $y_base_units)
        : [$x_base_units, $y_base_units];
}

sub get_rtree {
    my $self = shift;
    
    #  return if we have one
    return $self->{rtree} if ($self->{rtree});
    
    #  check basestruct
    $self->{rtree} = $self->{base_struct}->get_param('RTREE');
    return $self->{rtree} if ($self->{rtree});
    
    #  otherwise build it ourselves and cache it
    my $rtree = Tree::R->new();
    $self->{rtree} = $rtree;
    $self->{base_struct}->set_param (RTREE => $rtree);
    $self->{build_rtree} = 1;

    return $self->{rtree};
}

# Draw cells coming from elements in a BaseStruct
# This can come either from a BaseData or a Spatial Output
sub set_base_struct {
    my $self = shift;
    my $data = shift;

    $self->{base_struct} = $data;
    $self->{cells} = {};

    my @tmpcell_sizes = $data->get_cell_sizes;  #  work on a copy
    say "setBaseStruct data $data checking set cell sizes: ", join(',', @tmpcell_sizes);
    
    my ($min_x, $max_x, $min_y, $max_y) = $self->find_max_min($data);

    say join q{ }, $min_x, $max_x, $min_y // '', $max_y // '';

    my @res = $self->get_cell_sizes($data);  #  handles zero and text
    
    my $cell_x = shift @res;  #  just grab first two for now
    my $cell_y = shift @res || $cell_x;  #  default to a square if not defined or zero
    
    #  save some coords stuff for later transforms
    $self->{base_struct_cellsizes} = [$cell_x, $cell_y];
    $self->{base_struct_bounds}    = [$min_x, $min_y, $max_x, $max_y];

    my $sizes = $data->get_cell_sizes;
    my @sizes = @$sizes;
    my $width_pixels = 0;
    if (   $sizes[0] == 0
        || ! defined $sizes[1]
        || $sizes[1] == 0 ) {
        $width_pixels = 1
    }

    # Configure cell heights and y-offsets for the marks (circles, lines,...)
    my $ratio = eval {$cell_y / $cell_x} || 1;  #  trap divide by zero
    my $cell_size_y = CELL_SIZE_X * $ratio;
    $self->{cell_size_y} = $cell_size_y;
    
    #  setup the index if needed
    if (defined $self->{select_func}) {
        $self->get_rtree();
    }
    
    my $elts = $data->get_element_hash();

    my $count = scalar keys %$elts;
    
    croak "No groups to display - BaseData is empty\n"
      if $count == 0;

    my $progress_bar = Biodiverse::Progress->new(gui_only => 1);

    say "[Grid] Grid loading $count elements (cells)";
    $progress_bar->update ("Grid loading $count elements (cells)", 0);


    # Delete any old cells
    if ($self->{cells_group}) {
        $self->{cells_group}->destroy();
    }

    # Make group so we can transform everything together
    my $cells_group = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Group',
        x => 0,
        y => 0,
    );

##  DEBUG add a background rect - should buffer the extents by 2 cells or more
## Make container group ("cell") for the rectangle and any marks
#my $xx = eval {($max_x - $min_x) / $cell_x};
#my $yy = eval {($max_y - $min_y) / $cell_y};
#my $container_xx = Gnome2::Canvas::Item->new (
#    $cells_group,
#    'Gnome2::Canvas::Group',
#    x => 0,
#    y => 0,
#);
#my $rect = Gnome2::Canvas::Item->new (
#    $container_xx,
#    'Gnome2::Canvas::Rect',
#    x1                  => 0,
#    y1                  => 0,
#    x2                  => $xx * CELL_SIZE_X,
#    y2                  => $yy * $cell_size_y,
#    fill_color_gdk      => COLOUR_WHITE,
#    outline_color_gdk   => COLOUR_BLACK,
#    width_pixels        => $width_pixels
#);

    $self->{cells_group} = $cells_group;
    $cells_group->lower_to_bottom();

    my $i = 0;
    foreach my $element (keys %$elts) {
        no warnings 'uninitialized';  #  suppress these warnings
        
        $progress_bar->update (
            "Grid loading $i of $count elements (cells)",
            $i / $count
        );
        $i++;

        #FIXME: ????:
        # NOTE: this will stuff things, since we store $element in INDEX_ELEMENT
        my ($x_bd, $y_bd) = $data->get_element_name_coord (element => $element);

        # Transform into number of cells in X and Y directions
        my $x = eval {($x_bd - $min_x) / $cell_x};
        my $y = eval {($y_bd - $min_y) / $cell_y};

        # We shift by half the cell size to make the coordinate hit the cell center
        my $xcoord = $x * CELL_SIZE_X  - CELL_SIZE_X  / 2;
        my $ycoord = $y * $cell_size_y - $cell_size_y / 2;

        # Make container group ("cell") for the rectangle and any marks
        my $container = Gnome2::Canvas::Item->new (
            $cells_group,
            'Gnome2::Canvas::Group',
            x => $xcoord,
            y => $ycoord
        );

        # (all coords now relative to the group)
        my $rect = Gnome2::Canvas::Item->new (
            $container,
            'Gnome2::Canvas::Rect',
            x1                  => 0,
            y1                  => 0,
            x2                  => CELL_SIZE_X,
            y2                  => $cell_size_y,
            fill_color_gdk      => COLOUR_WHITE,
            outline_color_gdk   => COLOUR_BLACK,
            width_pixels        => $width_pixels
        );

        $container->signal_connect_swapped (event => \&on_event, $self);

        $self->{cells}{$container}[INDEX_COLOUR]  = COLOUR_WHITE;
        $self->{cells}{$container}[INDEX_ELEMENT] = $element;
        $self->{cells}{$container}[INDEX_RECT]    = $rect;

        #  add to the r-tree
        #  (profiling indicates this takes most of the time in this sub)
        if (defined $self->{select_func} && $self->{build_rtree}) {
            $self->{rtree}->insert( #  Tree::R method
                $element,
                $x_bd - $cell_x / 2,  #  basestruct units
                $y_bd - $cell_y / 2,
                $x_bd + $cell_x / 2,
                $y_bd + $cell_y / 2,
            );
        }
    }


    $self->store_cell_outline_colour (COLOUR_BLACK);

    $progress_bar = undef;

    #  THIS SHOULD BE ABOVE THE init_grid CALL to display properly from first?
    # Flip the y-axis (default has origin top-left with y going down)
    # Add border
    my $total_cells_X   = eval {($max_x - $min_x) / $cell_x} || 1;  #  default to one cell if undef
    my $total_cells_Y   = defined $max_y
        ? eval {($max_y - $min_y) / $cell_y} || 1
        : 1;
    my $width           = $total_cells_X * CELL_SIZE_X;
    my $height          = $total_cells_Y * $cell_size_y;
    
    $self->{width_units}  = $width  + 2*BORDER_SIZE;
    $self->{height_units} = $height + 4*BORDER_SIZE;

    $cells_group->affine_absolute([
        1,
        0,
        0,
        -1,
        BORDER_SIZE,
        $height + 2*BORDER_SIZE,
    ]);
    
    # Set visible region
    $self->{canvas}->set_scroll_region(
        0,
        0,
        $self->{width_units},
        $self->{height_units},
    );

    # Update
    $self->setup_scrollbars();
    $self->resize_background_rect();
    #$self->update_legend();

    # show legend by default - gets hidden by caller if needed
    $self->get_legend->show;
    # Store info needed by load_shapefile
    $self->{dataset_info} = [$min_x, $min_y, $max_x, $max_y, $cell_x, $cell_y];

    return 1;
}

sub get_base_struct {
    my $self = shift;
    return $self->{base_struct};
}

# Draws a polygonal shapefile
sub set_overlay {
    my $self      = shift;
    my $shapefile = shift;
    my $colour    = shift || OVERLAY_COLOUR;

    # Delete any existing
    if ($self->{shapefile_group}) {
        $self->{shapefile_group}->destroy;
        delete $self->{shapefile_group};
    }
    
    if ($shapefile) {
        my @args = @{ $self->{dataset_info} };
        $self->load_shapefile(@args, $shapefile, $colour);
    }

    return;
}

sub load_shapefile {
    my ($self, $min_x, $min_y, $max_x, $max_y, $cell_x, $cell_y, $shapefile, $colour) = @_;

    my @rect = (
        $min_x - $cell_x,
        $min_y - $cell_y,
        $max_x + $cell_x,
        $max_y + $cell_y,
    );

    # Get shapes within visible region - allow for cell extents
    my @shapes;
    @shapes = $shapefile->shapes_in_area (@rect);
    #  issue #257
    #  try to get all, but canvas ignores those outside the area...
    #@shapes = $shapefile->shapes_in_area ($shapefile->bounds);
    
    my $shapes_in_plot_area = @shapes;
    say "[Grid] Shapes within plot area: $shapes_in_plot_area";
    
    my $gui = Biodiverse::GUI::GUIManager->instance;
    if (!$shapes_in_plot_area) {
        $gui->report_error (
            'No shapes overlap the plot area',
            'No shapes to plot',
        );
        return;
    }

    my $unit_multiplier_x = CELL_SIZE_X / $cell_x;
    my $unit_multiplier_y = $self->{cell_size_y} / $cell_y;
    #my $unit_multiplier2  = $unit_multiplier_x * $unit_multiplier_x; #FIXME: maybe take max of _x,_y
    
    my @bnd_extrema = (1e20, 1e20, -1e20, -1e20);

    # Put it into a group so that it can be deleted more easily
    my $shapefile_group = Gnome2::Canvas::Item->new (
        $self->{cells_group},
        'Gnome2::Canvas::Group',
        x => 0,
        y => 0,
    );

    $shapefile_group->raise_to_top();
    $self->{shapefile_group} = $shapefile_group;

    # Add all shapes
    foreach my $shapeid (@shapes) {
        my $shape = $shapefile->get_shp_record($shapeid);

        #  track the bound extents so we can warn if they will be tiny
        my @bnds = $shape->bounds;
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
                push @plot_points, (
                    ($vertex->[0]->{X} - $min_x) * $unit_multiplier_x,
                    ($vertex->[0]->{Y} - $min_y) * $unit_multiplier_y,
                );
            }

            #  Get the end of the line, otherwise we don't plot the last vertex.
            #  (Segments are stored as start-end pairs of vertices).
            my $current_vertex = $segments[-1];
            push @plot_points, (
                ($current_vertex->[1]->{X} - $min_x) * $unit_multiplier_x,
                ($current_vertex->[1]->{Y} - $min_y) * $unit_multiplier_y,
            );

            #print "@plot_points\n";
            if (@plot_points > 2) { # must have more than one point (two coords)
                my $poly = Gnome2::Canvas::Item->new (
                    $shapefile_group,
                    'Gnome2::Canvas::Line',
                    points          => \@plot_points,
                    fill_color_gdk  => $colour,
                );
            }
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

    return;
}

# Colours elements using a callback function
# The callback should return a Gtk2::Gdk::Color object,
# or undef to set the colour to a default colour
sub colour {
    my $self     = shift;
    my $callback = shift;

    my $colour_none = $self->get_colour_for_undef // COLOUR_WHITE;

  CELL:
    foreach my $cell (values %{$self->{cells}}) {

        #  sometimes we are called before all cells have contents
        next CELL if !defined $cell->[INDEX_RECT];

        my $colour_ref = $callback->($cell->[INDEX_ELEMENT]) // $colour_none;
        
        next CELL if $colour_ref eq '-1';
        
        $cell->[INDEX_COLOUR] = $colour_ref;

        eval {
            $cell->[INDEX_RECT]->set('fill-color-gdk' => $colour_ref);
        };
        warn $@ if $@;
    }

    return;
}

sub store_cell_outline_colour {
    my $self = shift;
    my $col  = shift;
    
    $self->{cell_outline_colour} = $col;
}

sub get_cell_outline_colour {
    my $self = shift;
    return $self->{cell_outline_colour};
}


sub set_cell_outline_colour {
    my $self = shift;
    my $colour = shift;
    
    if (! $colour) {
        $colour = $self->get_colour_from_chooser ($self->get_cell_outline_colour);
    }

    #  if still no colour chosen
    return if !$colour;

    foreach my $cell (values %{$self->{cells}}) {
        my $rect = $cell->[INDEX_RECT];
        $rect->set(outline_color_gdk => $colour);
    }

    $self->store_cell_outline_colour ($colour);  #  store for later re-use

    return;
}

sub set_cell_show_outline {
    my $self   = shift;
    my $active = shift;

    if ($active) {
        #  reinstate previous colouring
        $self->set_cell_outline_colour ($self->get_cell_outline_colour);
    }
    else {
        # clear outline settings
        foreach my $cell (values %{$self->{cells}}) {
            my $rect = $cell->[INDEX_RECT];
            $rect->set(outline_color => undef);
        }
    }

    return;
}

#  same code as in Tab.pm
sub get_colour_from_chooser {
    my ($self, $colour) = @_;

    my $dialog = Gtk2::ColorSelectionDialog->new ('Select a colour');
    my $selector = $dialog->colorsel;  #  get_color_selection?

    if ($colour) {
        $selector->set_current_color ($colour);
    }

    if ($dialog->run eq 'ok') {
        $colour = $selector->get_current_color;
    }
    $dialog->destroy;

    return $colour;
}

# Sets the values of the textboxes next to the legend */
sub set_legend_min_max {
    my ($self, $min, $max) = @_;
    my $legend = $self->get_legend;
    return if ! ($legend);
    $legend->set_legend_min_max($min,$max);
}

sub show_legend {
    my $self = shift;
    my $legend = $self->get_legend;
    $legend->show;
}

sub hide_legend {
    my $self = shift;
    my $legend = $self->get_legend;
    $legend->hide;
}

sub set_legend_hue {
    my $self = shift;
    my $rgb  = shift;
    my $legend = $self->get_legend;
    $self->colour_cells();
    $legend->set_legend_hue($rgb);
}

sub get_legend_hue {
    my $self = shift;
    my $legend = $self->get_legend;
    $legend->get_legend_hue;
}

#sub set_legend_min_max {
#    my ($self, $min, $max) = @_;
#
#    $min //= $self->{last_min};
#    $max //= $self->{last_max};
#
#    $self->{last_min} = $min;
#    $self->{last_max} = $max;
#
#    return if ! ($self->{marks}
#                 && defined $min
#                 && defined $max
#                );
#
#    # Set legend textbox markers
#    my $marker_step = ($max - $min) / 3;
#    foreach my $i (0..3) {
#        my $val = $min + $i * $marker_step;
#        my $text = $self->format_number_for_display (number => $val);
#        my $text_num = $text;  #  need to not have '<=' and '>=' in comparison lower down
#        if ($i == 0 and $self->{legend_lt_flag}) {
#            $text = '<=' . $text;
#        }
#        elsif ($i == 3 and $self->{legend_gt_flag}) {
#            $text = '>=' . $text;
#        }
#        elsif ($self->{legend_lt_flag} or $self->{legend_gt_flag}) {
#            $text = '  ' . $text;
#        }
#
#        my $mark = $self->{marks}[3 - $i];
#        $mark->set( text => $text );
#        #  move the mark to right align with the legend
#        my @bounds = $mark->get_bounds;
#        my @lbounds = $self->get_legend->get_bounds;
#        my $offset = $lbounds[0] - $bounds[2];
#        if (($text_num + 0) != 0) {
#            $mark->move ($offset - length ($text), 0);
#        }
#        else {
#            $mark->move ($offset - length ($text) - 0.5, 0);
#        }
#        $mark->raise_to_top;
#    }
#
#    return;
#}

#  dup from Tab.pm - need to inherit from single source
#sub format_number_for_display {
#    my $self = shift;
#    my %args = @_;
#    my $val = $args{number};
#
#    my $text = sprintf ('%.4f', $val); # round to 4 d.p.
#    if ($text == 0) {
#        $text = sprintf ('%.2e', $val);
#    }
#    if ($text == 0) {
#        $text = 0;  #  make sure it is 0 and not 0.00e+000
#    };
#    return $text;
#}

# Sets list to use for colouring (eg: SPATIAL_RESULTS, RAND_COMPARE, ...)
# Is this ever called?
#sub set_calculation_list {
#    my $self = shift;
#    my $list_name = shift;
#    print "[Grid] Setting calculation list to $list_name\n";
#
#    my $elts = $self->{base_struct}->get_element_hash();
#
#    foreach my $element (sort keys %{$elts}) {
#        my $cell = $self->{element_group}{$element};
#        $cell->[INDEX_VALUES] = $elts->{$element}{$list_name};
#    }
#
#    return;
#}


##########################################################
# Marking out certain elements by colour, circles, etc...
##########################################################

sub grayout_elements {
    my $self = shift;

    # ed: actually just white works better - leaving this in just in case is handy elsewhere
    # This is from the GnomeCanvas demo
    #my $gray50_width = 4;
    #my $gray50_height = 4;
    #my $gray50_bits = pack "CC", 0x80, 0x01, 0x80, 0x01;
    #my $stipple = Gtk2::Gdk::Bitmap->create_from_data (undef, $gray50_bits, $gray50_width, $gray50_height);

    foreach my $cell (values %{$self->{cells}}) {
        my $rect = $cell->[INDEX_RECT];
        $rect->set('fill-color', '#FFFFFF'); # , 'fill-stipple', $stipple);

    }
    
    return;
}

# Places a circle/cross inside a cell if it exists in a hash
sub mark_if_exists {
    my $self  = shift;
    my $hash  = shift;
    my $shape = shift; # "circle" or "cross"

  CELL:
    foreach my $cell (values %{$self->{cells}}) {
        # sometimes we are called before the data are populated
        next CELL if !$cell || !$cell->[INDEX_RECT];

        if (exists $hash->{$cell->[INDEX_ELEMENT]}) {

            my $group = $cell->[INDEX_RECT]->parent;

            # Circle
            if ($shape eq 'circle' && not $cell->[INDEX_CIRCLE]) {
                $cell->[INDEX_CIRCLE] = $self->draw_circle($group);
                #$group->signal_handlers_disconnect_by_func(\&on_event);
            }

            # Cross
            #if ($shape eq 'cross' && not $cell->[INDEX_CROSS]) {
            #    $cell->[INDEX_CROSS] = $self->draw_cross($group);
            #} 

            # Minus
            if ($shape eq 'minus' && not $cell->[INDEX_MINUS]) {
                $cell->[INDEX_MINUS] = $self->draw_minus($group);
            } 

        }
        else {
            if ($shape eq 'circle' && $cell->[INDEX_CIRCLE]) {
                $cell->[INDEX_CIRCLE]->destroy;
                $cell->[INDEX_CIRCLE] = undef;
                #$group->signal_connect_swapped(event => \&on_event, $self);
            }
            #if ($shape eq 'cross' && $cell->[INDEX_CROSS]) {
            #    $cell->[INDEX_CROSS]->destroy;
            #    $cell->[INDEX_CROSS] = undef;
            #}    
            if ($shape eq 'minus' && $cell->[INDEX_MINUS]) {
                $cell->[INDEX_MINUS]->destroy;
                $cell->[INDEX_MINUS] = undef;
            }
        }
    }
    
    return;
}

sub draw_circle {
    my ($self, $group) = @_;
    my $offset_x = (CELL_SIZE_X - CIRCLE_DIAMETER) / 2;
    my $offset_y = ($self->{cell_size_y} - CIRCLE_DIAMETER) / 2;

    my $item = Gnome2::Canvas::Item->new (
        $group,
        'Gnome2::Canvas::Ellipse',
        x1                => $offset_x,
        y1                => $offset_y,
        x2                => $offset_x + CIRCLE_DIAMETER,
        y2                => $offset_y + CIRCLE_DIAMETER,
        fill_color_gdk    => COLOUR_BLACK,
        outline_color_gdk => COLOUR_BLACK,
    );
    #$item->signal_connect_swapped(event => \&on_marker_event, $self);
    return $item;
}

sub on_marker_event {
    # FIXME FIXME FIXME All this stuff has serious problems between Windows/Linux
    my ($self, $event, $cell) = @_;
    print "Marker event: " . $event->type .  "\n";
    $self->on_event($event, $cell->parent);
    return 1;
}

#sub draw_cross {
#    my ($self, $group) = @_;
#    # Use a group to hold the two lines
#    my $cross_group = Gnome2::Canvas::Item->new (
#        $group,
#        "Gnome2::Canvas::Group",
#        x => 0, y => 0,
#    );
#
#    Gnome2::Canvas::Item->new (
#        $cross_group,
#        "Gnome2::Canvas::Line",
#        points => [MARK_OFFSET_X, MARK_OFFSET_X, MARK_END_OFFSET_X, MARK_END_OFFSET_X],
#        fill_color_gdk => COLOUR_BLACK,
#        width_units => 1,
#    );
#    Gnome2::Canvas::Item->new (
#        $cross_group,
#        "Gnome2::Canvas::Line",
#        points => [MARK_END_OFFSET_X, MARK_OFFSET_X, MARK_OFFSET_X, MARK_END_OFFSET_X],
#        fill_color_gdk => COLOUR_BLACK,
#        width_units => 1,
#    );
#
#    return $cross_group;
#}

sub draw_minus {
    my ($self, $group) = @_;
    my $offset_y = ($self->{cell_size_y} - 1) / 2;

    return Gnome2::Canvas::Item->new (
        $group,
        'Gnome2::Canvas::Line',
        points => [
            MARK_X_OFFSET,
            $offset_y,
            CELL_SIZE_X - MARK_X_OFFSET,
            $offset_y,
        ],
        fill_color_gdk => COLOUR_BLACK,
        width_units => 1,
    );

}




##########################################################
# Colouring based on an analysis value
##########################################################

#  a mis-named sub - this merely sets the initial colours or clears existing colours
sub colour_cells {
    my $self = shift;

    my $colour_none = $self->get_colour_for_undef;

    foreach my $cell (values %{$self->{cells}}) {
        my $rect = $cell->[INDEX_RECT];
        $rect->set('fill-color-gdk' => $colour_none);
    }

    return;
}

sub get_colour_for_undef {
    my $self = shift;
    my $colour_none = shift;

    return $self->{colour_none} // $self->set_colour_for_undef ($colour_none);
}

sub set_colour_for_undef {
    my ($self, $colour) = @_;
    
    $colour //= COLOUR_WHITE;

    croak "Colour argument must be a Gtk2::Gdk::Color object\n"
      if not blessed ($colour) eq 'Gtk2::Gdk::Color';

    $self->{colour_none} = $colour;
}

my %colour_methods = (
    Hue  => 'get_colour_hue',
    Sat  => 'get_colour_saturation',
    Grey => 'get_colour_grey',
);

sub get_colour {
    my ($self, $val, $min, $max) = @_;

    if (defined $min and $val < $min) {
        $val = $min;
    }
    if (defined $max and $val > $max) {
        $val = $max;
    }
    my @args = ($val, $min, $max);

    my $mode = $self->get_legend->get_legend_mode;
    my $method = $colour_methods{$mode};

    croak "Unknown colour system: $mode\n"
      if !$method;

    return $self->$method(@args);
}

sub get_colour_hue {
    my ($self, $val, $min, $max) = @_;
    # We use the following system:
    #   Linear interpolation between min...max
    #   HUE goes from 180 to 0 as val goes from min to max
    #   Saturation, Brightness are 1
    #
    my $hue;
    if (! defined $max || ! defined $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0);
        #return COLOUR_BLACK;
    }
    elsif ($max != $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0) if ! defined $val;
        $hue = ($val - $min) / ($max - $min) * 180;
    }
    else {
        $hue = 0;
    }
    
    $hue = int(180 - $hue); # reverse 0..180 to 180..0 (this makes high values red)
    
    my ($r, $g, $b) = hsv_to_rgb($hue, 1, 1);
    
    return Gtk2::Gdk::Color->new($r*257, $g*257, $b*257);
}

sub get_colour_saturation {
    my ($self, $val, $min, $max) = @_;
    #   Linear interpolation between min...max
    #   SATURATION goes from 0 to 1 as val goes from min to max
    #   Hue is variable, Brightness 1
    my $sat;
    if (! defined $max || ! defined $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0);
        #return COLOUR_BLACK;
    }
    elsif ($max != $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0) if ! defined $val;
        $sat = ($val - $min) / ($max - $min);
    }
    else {
        $sat = 1;
    }
    
    my ($r, $g, $b) = hsv_to_rgb($self->{hue}, $sat, 1);
    
    return Gtk2::Gdk::Color->new($r*257, $g*257, $b*257);
}

sub get_colour_grey {
    my ($self, $val, $min, $max) = @_;
    
    my $sat;
    if (! defined $max || ! defined $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0);
        #return COLOUR_BLACK;
    }
    elsif ($max != $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0)
          if ! defined $val;
        
        $sat = ($val - $min) / ($max - $min);
    }
    else {
        $sat = 1;
    }
    $sat *= 255;
    $sat = $self->rescale_grey($sat);  #  don't use all the shades
    $sat *= 257;
    
    return Gtk2::Gdk::Color->new($sat, $sat, $sat);
}

# FROM http://blog.webkist.com/archives/000052.html
# by Jacob Ehnmark
sub hsv_to_rgb {
    my($h, $s, $v) = @_;
    $v = $v >= 1.0 ? 255 : $v * 256;

    # Grey image.
    return((int($v)) x 3) if ($s == 0);

    $h /= 60;
    my $i = int($h);
    my $f = $h - int($i);
    my $p = int($v * (1 - $s));
    my $q = int($v * (1 - $s * $f));
    my $t = int($v * (1 - $s * (1 - $f)));
    $v = int($v);

    if   ($i == 0) { return($v, $t, $p); }
    elsif($i == 1) { return($q, $v, $p); }
    elsif($i == 2) { return($p, $v, $t); }
    elsif($i == 3) { return($p, $q, $v); }
    elsif($i == 4) { return($t, $p, $v); }
    else           { return($v, $p, $q); }
}

sub rgb_to_hsv {
    my $var_r = $_[0] / 255;
    my $var_g = $_[1] / 255;
    my $var_b = $_[2] / 255;
    my($var_max, $var_min) = maxmin($var_r, $var_g, $var_b);
    my $del_max = $var_max - $var_min;

    if($del_max) {
        my $del_r = ((($var_max - $var_r) / 6) + ($del_max / 2)) / $del_max;
        my $del_g = ((($var_max - $var_g) / 6) + ($del_max / 2)) / $del_max;
        my $del_b = ((($var_max - $var_b) / 6) + ($del_max / 2)) / $del_max;
    
        my $h;
        if($var_r == $var_max) { $h = $del_b - $del_g; }
        elsif($var_g == $var_max) { $h = 1/3 + $del_r - $del_b; }
        elsif($var_b == $var_max) { $h = 2/3 + $del_g - $del_r; }
    
        if($h < 0) { $h += 1 }
        if($h > 1) { $h -= 1 }
    
        return($h * 360, $del_max / $var_max, $var_max);
    }
    else {
        return(0, 0, $var_max);
    }
}

#  rescale the grey values into lighter shades
sub rescale_grey {
    my $self  = shift;
    my $value = shift;
    my $max   = shift;
    defined $max or $max = 255;
    
    $value /= $max;
    $value *= (LIGHTEST_GREY_FRAC - DARKEST_GREY_FRAC);
    $value += DARKEST_GREY_FRAC;
    $value *= $max;
    
    return $value;
}

sub maxmin {
    my($min, $max) = @_;
    
    for(my $i=0; $i<@_; $i++) {
        $max = $_[$i] if($max < $_[$i]);
        $min = $_[$i] if($min > $_[$i]);
    }
    
    return($max,$min);
}

##########################################################
# Data extraction utilities
##########################################################

sub find_max_min {
    my $self = shift;
    my $data = shift;
    my ($min_x, $max_x, $min_y, $max_y);

    foreach my $element ($data->get_element_list) {

        my ($x, $y) = $data->get_element_name_coord (element => $element);

        $min_x = $x if ( (not defined $min_x) || $x < $min_x);
        $min_y = $y if ( (not defined $min_y) || $y < $min_y);

        $max_x = $x if ( (not defined $max_x) || $x > $max_x);
        $max_y = $y if ( (not defined $max_y) || $y > $max_y);
    }

    $max_x //= $min_x;
    $max_y //= $min_y;

    return ($min_x, $max_x, $min_y, $max_y);
}

sub get_cell_sizes {
    my $data = $_[1];

    #  handle text groups here
    my @cell_sizes = map {$_ < 0 ? 1 : $_} $data->get_cell_sizes;

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
            $axis_coords{$axes[$i]} = undef;
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


##########################################################
# Event handling
##########################################################

# Implements pop-ups and hover-markers
# FIXME FIXME FIXME Horrible problems between windows / linux due to the markers being on top...
# SWL 20140823. Is this still the case?
sub on_event {
    my ($self, $event, $cell) = @_;

    if ($event->type eq '2button_press') {
        say "Double click does nothing";
    }
    elsif ($event->type eq 'enter-notify') {

        # Call client-defined callback function
        if (defined $self->{hover_func} and not $self->{clicked_cell}) {
            my $f = $self->{hover_func};
            $f->($self->{cells}{$cell}[INDEX_ELEMENT]);
        }

        # Change the cursor if we are in select mode
        if (!$self->{cursor}) {
            my $cursor = Gtk2::Gdk::Cursor->new(HOVER_CURSOR);
            $self->{canvas}->window->set_cursor($cursor);
        }
    }
    elsif ($event->type eq 'leave-notify') {

        # Call client-defined callback function
        #if (defined $self->{hover_func} and not $self->{clicked_cell}) {
        #    my $f = $self->{hover_func};
        #    # FIXME: Disabling hiding of markers since this stuffs up
        #    # the popups on win32 - we receive leave-notify on button click!
        #    #$f->(undef);
        #}
        
        # call to end hovering
        if (defined $self->{end_hover_func} and not $self->{clicked_cell}) {
            $self->{end_hover_func}->();
        }

        # Change cursor back to default
        $self->{canvas}->window->set_cursor($self->{cursor});

    }
    elsif ($event->type eq 'button-press') {
        $self->{clicked_cell} = undef unless $event->button == 2;  #  clear any clicked cell
        
        # If middle-click or control-click
        if (        $event->button == 2
            || (    $event->button == 1
                and not $self->{selecting}
                and $event->state >= [ 'control-mask' ])
            ) {
            #print "===========Cell popup\n";
            # Show/Hide the labels popup dialog
            my $element = $self->{cells}{$cell}[INDEX_ELEMENT];
            my $f = $self->{click_func};
            $f->($element);
            
            return 1;  #  Don't propagate the events
        }
        
        elsif ($self->{drag_mode} eq 'select' and $event->button == 1) { # left click and drag
            
            if (defined $self->{select_func}
                and not $self->{selecting}
                and not ($event->state >= [ 'control-mask' ])
                ) {
                ($self->{sel_start_x}, $self->{sel_start_y}) = ($event->x, $event->y);
                
                # Grab mouse
                $cell->grab (
                    [qw/pointer-motion-mask button-release-mask/],
                    Gtk2::Gdk::Cursor->new ('fleur'),
                    $event->time,
                );
                $self->{selecting} = 1;
                $self->{grabbed_cell} = $cell;
                
                $self->{sel_rect} = Gnome2::Canvas::Item->new (
                    $self->{canvas}->root,
                    'Gnome2::Canvas::Rect',
                    x1 => $event->x,
                    y1 => $event->y,
                    x2 => $event->x,
                    y2 => $event->y,
                    fill_color_gdk => undef,
                    outline_color_gdk => COLOUR_BLACK,
                    #outline_color_gdk => HIGHLIGHT_COLOUR,
                    width_pixels => 0,
                );
            }
        }
        elsif ($event->button == 3) { # right click - use hover function but fix it in place
            # Call client-defined callback function
            if (defined $self->{hover_func}) {
                my $f = $self->{hover_func};
                $f->($self->{cells}{$cell}[INDEX_ELEMENT]);
            }
            $self->{clicked_cell} = $cell;
            
        }

    }
    elsif ($event->type eq 'button-release') {
        $cell->ungrab ($event->time);
        if ($self->{selecting} and defined $self->{select_func}) {

            $cell->ungrab ($event->time);
            
            $self->{selecting} = 0;
            
            # Establish the selection
            my ($x_start, $y_start) = ($self->{sel_start_x}, $self->{sel_start_y});
            my ($x_end,   $y_end)   = ($event->x, $event->y);

            $self->end_selection($x_start, $y_start, $x_end, $y_end);

            #  Try to get rid of the dot that appears when selecting.
            #  Lowering at least stops it getting in the way.
            my $sel_rect = $self->{sel_rect};
            delete $self->{sel_rect};
            $sel_rect->lower_to_bottom();
            $sel_rect->hide();
            $sel_rect->destroy;
            
        }

    }
    if ($event->type eq 'motion-notify') {

        if ($self->{selecting}) {
            # Resize selection rectangle
            $self->{sel_rect}->set(x2 => $event->x, y2 => $event->y);
        }
    }

    return 0;    
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

        # I'm not sure if this need to be here.
        $self->get_legend->reposition($self->{width_px}, $self->{height_px});

        $self->setup_scrollbars();
        $self->resize_background_rect();

    }
    
    return;
}

# Implements panning
sub on_background_event {
    my ($self, $event, $cell) = @_;

    # Do everything with left click now.
    return if $event->type =~ m/^button-/ && $event->button != 1;

    if ($event->type eq 'enter-notify') {
        $self->{page}->set_active_pane('grid');
    }
    elsif ($event->type eq 'leave-notify') {
        $self->{page}->set_active_pane('');
    }
    elsif ($event->type eq 'button-press') {
        if ($self->{drag_mode} eq 'select' and not $self->{selecting} and defined $self->{select_func}) {
            ($self->{sel_start_x}, $self->{sel_start_y}) = ($event->x, $event->y);

            # Grab mouse
            $cell->grab (
                [qw/pointer-motion-mask button-release-mask/],
                Gtk2::Gdk::Cursor->new ('fleur'),
                $event->time,
            );
            $self->{selecting} = 1;
            $self->{grabbed_cell} = $cell;

            $self->{sel_rect} = Gnome2::Canvas::Item->new (
                $self->{canvas}->root,
                'Gnome2::Canvas::Rect',
                x1 => $event->x,
                y1 => $event->y,
                x2 => $event->x + 1,
                y2 => $event->y + 1,
                fill_color_gdk => undef,
                outline_color_gdk => COLOUR_BLACK,
                width_pixels => 0,
            );
        }
        elsif ($self->{drag_mode} eq 'pan') {
            ($self->{pan_start_x}, $self->{pan_start_y}) = $event->coords;

            # Grab mouse
            $cell->grab (
                [qw/pointer-motion-mask button-release-mask/],
                Gtk2::Gdk::Cursor->new ('fleur'),
                $event->time,
            );
            $self->{dragging} = 1;
        }
        elsif ($self->{drag_mode} eq 'click') {
            if (defined $self->{grid_click_func}) {
                $self->{grid_click_func}->();
            }
        }
    }
    elsif ($event->type eq 'button-release') {
        if ($self->{selecting}) {
            # Establish the selection
            my ($x_start, $y_start) = ($self->{sel_start_x}, $self->{sel_start_y});
            my ($x_end, $y_end)     = ($event->x, $event->y);

            if (defined $self->{select_func}) {
                
                $cell->ungrab ($event->time);
                $self->{selecting} = 0;
                
                #  Try to get rid of the dot that appears when selecting.
                #  Lowering at least stops it getting in the way.
                my $sel_rect = $self->{sel_rect};
                delete $self->{sel_rect};
                #$sel_rect->lower_to_bottom();
                #$sel_rect->hide();
                $sel_rect->destroy;
                
                #if (! $event->state >= ["control-mask" ]) {  #  not if control key is pressed
                    $self->end_selection($x_start, $y_start, $x_end, $y_end);
                #}
            }

        }
        elsif ($self->{dragging}) {
            $cell->ungrab ($event->time);
            $self->{dragging} = 0;
            $self->update_scrollbars(); #FIXME: If we do this for motion-notify - get great flicker!?!?
        }

    }
    elsif ( $event->type eq 'motion-notify') {
#        print "Background Event\tMotion\n";
        
        if ($self->{selecting}) {
            # Resize selection rectangle
            $self->{sel_rect}->set(x2 => $event->x, y2 => $event->y);

        }
        elsif ($self->{dragging}) {
            # Work out how much we've moved away from pan_start (world coords)
            my ($x, $y) = $event->coords;
            my ($dx, $dy) = ($x - $self->{pan_start_x}, $y - $self->{pan_start_y});

            # Scroll to get back to pan_start
            my ($scrollx, $scrolly) = $self->{canvas}->get_scroll_offsets();
            my ($cx, $cy) =  $self->{canvas}->w2c($dx, $dy);
            $self->{canvas}->scroll_to(-1 * $cx + $scrollx, -1 * $cy + $scrolly);
        }
    }

    return 0;
}

# Called to complete selection. Finds selected elements and calls callback
sub end_selection {
    my $self = shift;
    my ($x_start, $y_start, $x_end, $y_end) = @_;

    # Find selected elements
    my $yoffset = $self->{height_units} - 2 * BORDER_SIZE;

    my @rect = (
        $x_start - BORDER_SIZE,
        $yoffset - $y_start,
        $x_end - BORDER_SIZE,
        $yoffset - $y_end,
    );

    # Make sure end distances are greater than start distances
    my $tmp;
    if ($rect[0] > $rect[2]) {
        $tmp = $rect[0];
        $rect[0] = $rect[2];
        $rect[2] = $tmp;
    }
    if ($rect[1] > $rect[3]) {
        $tmp = $rect[1];
        $rect[1] = $rect[3];
        $rect[3] = $tmp;
    }

    my @rect_baseunits = (
        $self->units_canvas2basestruct ($rect[0], $rect[1]),
        $self->units_canvas2basestruct ($rect[2], $rect[3]),
    );

    my $elements = [];
    #$self->{rtree}->query_partly_within_rect(@rect, $elements);
    $self->{rtree}->query_partly_within_rect(@rect_baseunits, $elements);
    #my $elements = $self->{rtree}->get_enclosed_objects (@rect);
    if (0) {
        print "[Grid] selection rect: @rect\n";
        for my $element (@$elements) {
            print "[Grid]\tselected: $element\n";
        }
    }

    # call callback, using original event coords
    # TODO: the call with rect info could be a separate callback.
    my $f = $self->{select_func};
    $f->($elements, undef, [$x_start, $y_start, $x_end, $y_end]);

    return;
}

##########################################################
# Scrolling
##########################################################

sub setup_scrollbars {
    my $self = shift;
    my ($total_width, $total_height) = $self->{canvas}->w2c($self->{width_units}, $self->{height_units});

    $self->{hadjust}->upper( $total_width );
    $self->{vadjust}->upper( $total_height );

    if ($self->{width_px}) {
        $self->{hadjust}->page_size( $self->{width_px} );
        $self->{vadjust}->page_size( $self->{height_px} );

        $self->{hadjust}->page_increment( $self->{width_px} / 2 );
        $self->{vadjust}->page_increment( $self->{height_px} / 2 );
    }

    $self->{hadjust}->changed;
    $self->{vadjust}->changed;
    
    return;
}

sub update_scrollbars {
    my $self = shift;

    my ($scrollx, $scrolly) = $self->{canvas}->get_scroll_offsets();
    $self->{hadjust}->set_value($scrollx);
    $self->{vadjust}->set_value($scrolly);
    
    return;
}

sub on_scrollbars_scroll {
    my $self = shift;

    if (not $self->{dragging}) {
        my ($x, $y) = ($self->{hadjust}->get_value, $self->{vadjust}->get_value);
        $self->{canvas}->scroll_to($x, $y);
        $self->update_legend();
    }
    
    return;
}


##########################################################
# Zoom and Resizing
##########################################################

# Calculate pixels-per-unit to make image fit
sub fit_grid {
    my $self = shift;

    my $ppu_width = $self->{width_px} / $self->{width_units};
    my $ppu_height = $self->{height_px} / $self->{height_units};
    my $min_ppu = $ppu_width < $ppu_height ? $ppu_width : $ppu_height;
    $self->{canvas}->set_pixels_per_unit( $min_ppu );
    #print "[Grid] Setting grid zoom (pixels per unit) to $min_ppu\n";
    
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
                x2 => max($width,  $self->{width_units}),
                y2 => max($height, $self->{height_units}),
            );
            $self->{back_rect}->lower_to_bottom();
        }
    }
    return;
}

#sub max {
#    return ($_[0] > $_[1]) ? $_[0] : $_[1];
#}

sub on_scroll {
    my $self = shift;
    #FIXME: check if this helps reduce flicker
    $self->update_legend();
    
    return;
}

##########################################################
# More public functions (zoom/colours)
##########################################################

sub zoom_in {
    my $self = shift;
    my $ppu = $self->{canvas}->get_pixels_per_unit();
    $self->{canvas}->set_pixels_per_unit( $ppu * 1.5 );
    $self->set_zoom_fit_flag(0);
    $self->post_zoom();
    
    return;
}

sub zoom_out {
    my $self = shift;
    my $ppu = $self->{canvas}->get_pixels_per_unit();
    $self->{canvas}->set_pixels_per_unit( $ppu / 1.5 );
    $self->set_zoom_fit_flag (0);
    $self->post_zoom();
    
    return;
}

sub zoom_fit {
    my $self = shift;
    $self->set_zoom_fit_flag (1);
    $self->fit_grid();
    $self->post_zoom();
    
    return;
}

sub set_zoom_fit_flag {
    my ($self, $zoom_fit) = @_;
    
    $self->{zoom_fit} = $zoom_fit;
}

sub get_zoom_fit_flag {
    my ($self) = @_;
    
    return $self->{zoom_fit};
}

sub post_zoom {
    my $self = shift;
    $self->setup_scrollbars();

    $self->update_legend();
    $self->resize_background_rect();
    
    return;
}



1;
