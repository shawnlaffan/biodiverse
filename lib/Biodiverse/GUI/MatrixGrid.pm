=head1 GRID

A component that displays a 2D matrix using GnomeCanvas

=cut

package Biodiverse::GUI::MatrixGrid;

use 5.010;

use strict;
use warnings;
use Data::Dumper;
use Carp;
use POSIX qw /floor/;
use List::Util qw /min max/;

our $VERSION = '1.99_006';

use Gtk2;
use Gnome2::Canvas;

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::CellPopup;
use Biodiverse::Progress;

##########################################################
# Rendering constants
##########################################################
use constant CELL_SIZE       => 10;    # Cell size (canvas units)
use constant CIRCLE_DIAMETER => 5;

use constant BORDER_SIZE   => 5;
use constant LEGEND_WIDTH  => 20;

use constant INDEX_VALUES  => 0;
use constant INDEX_ELEMENT => 1;
use constant INDEX_RECT    => 2;
use constant INDEX_CROSS   => 3;
use constant INDEX_CIRCLE  => 4;
use constant INDEX_MINUS   => 5;

use constant HOVER_CURSOR  => 'hand2';

use constant HIGHLIGHT_COLOUR => Gtk2::Gdk::Color->new(255*257, 0, 0); # red
use constant CELL_BLACK       => Gtk2::Gdk::Color->new(0, 0, 0);
use constant CELL_WHITE       => Gtk2::Gdk::Color->new(255*257, 255*257, 255*257);
#use constant CELL_COLOUR      => Gtk2::Gdk::Color->parse('#B3FFFF');
use constant CELL_COLOUR      => Gtk2::Gdk::Color->parse('#FFFFFF');
use constant OVERLAY_COLOUR   => Gtk2::Gdk::Color->parse('#001169');

# Stiple for the selection-masking shape
my $gray50_width  = 2;
my $gray50_height = 2;
my $gray50_bits   = pack "CC", 0x02, 0x01;

##########################################################
# Construction
##########################################################

sub new {
    my $class = shift;
    my %args  = @_;

    my $frame   = $args{frame};
    my $hscroll = $args{hscroll};
    my $vscroll = $args{vscroll};

    my $self = {
        colours => 'Hue',
        hue     => 0,      # default constant-hue red
    }; 
    bless $self, $class;

    #  callbacks
    $self->{hover_func}  = $args{hover_func};  # move mouse over a cell
    $self->{select_func} = $args{select_func}; # click on a cell
    $self->{grid_click_func} = $args{grid_click_func}; # click on a cell

    # Make the canvas and hook it up
    $self->{canvas} = Gnome2::Canvas->new();
    $frame->add($self->{canvas});

    $self->{canvas}->signal_connect_swapped (
        size_allocate => \&on_size_allocate,
        $self,
    );

    # Set up custom scrollbars due to flicker problems whilst panning..
    $self->{hadjust} = Gtk2::Adjustment->new(0, 0, 1, 1, 1, 1);
    $self->{vadjust} = Gtk2::Adjustment->new(0, 0, 1, 1, 1, 1);

    $hscroll->set_adjustment( $self->{hadjust} );
    $vscroll->set_adjustment( $self->{vadjust} );

    $self->{hadjust}->signal_connect_swapped(
        'value-changed',
        \&on_scrollbars_scroll,
        $self,
    );
    $self->{vadjust}->signal_connect_swapped(
        'value-changed',
        \&on_scrollbars_scroll,
        $self,
    );

    $self->{canvas}->get_vadjustment->signal_connect_swapped(
        'value-changed',
        \&on_scroll,
        $self,
    );
    $self->{canvas}->get_hadjustment->signal_connect_swapped(
        'value-changed',
        \&on_scroll,
        $self,
    );

    # Set up canvas
    $self->{canvas}->set_center_scroll_region(0);
    $self->{canvas}->show;
    #$self->{zoom_fit}  = 1;
    $self->set_zoom_fit_flag(1);
    $self->{dragging}  = 0;
    $self->{selecting} = 0;

    # Create background rectangle to receive mouse events for panning
    my $rect = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Rect',
        x1              => 0,
        y1              => 0,
        x2              => CELL_SIZE,
        fill_color_gdk  => CELL_WHITE,
        y2              => CELL_SIZE,
    );

    $rect->lower_to_bottom();
    $self->{canvas}->root->signal_connect_swapped (
        event => \&on_background_event,
        $self,
    );
    $self->{back_rect} = $rect;

    $self->show_legend;

    $self->{drag_mode} = 'select';

    return $self;
}

sub show_legend {
    my $self = shift;
    print "already have legend!\n" if $self->{legend};
    
    return if $self->{legend};

    # Create legend
    my $pixbuf = $self->make_legend_pixbuf;
    $self->{legend} = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Pixbuf',
        pixbuf              => $pixbuf,
        'width_in_pixels'   => 1,
        'height_in_pixels'  => 1,
        'height-set'        => 1,
        width               => LEGEND_WIDTH,
    );
    
    $self->{legend}->raise_to_top();
    $self->{back_rect}->lower_to_bottom();

    $self->{marks}[0] = $self->make_mark('ne');
    $self->{marks}[1] = $self->make_mark('e');
    $self->{marks}[2] = $self->make_mark('e');
    $self->{marks}[3] = $self->make_mark('se');
    
    return;
}

sub hide_legend {
    my $self = shift;

    if ($self->{legend}) {
        $self->{legend}->destroy();
        delete $self->{legend};

        foreach my $i (0..3) {
            $self->{marks}[$i]->destroy();
        }
    }
    delete $self->{marks};
    
    return;
}


sub destroy {
    my $self = shift;

    #$self->{canvas}->hide();
    print "[MatrixGrid] Trying to clean up canvas references\n";

    if ($self->{legend}) {
        $self->{legend}->destroy();
        delete $self->{legend};

        foreach my $i (0..3) {
            $self->{marks}[$i]->destroy();
        }
    }

    delete $self->{marks};

    # Destroy cell groups
    if ($self->{cells_group}) {
        $self->{cells_group}->destroy();
    }

    delete $self->{hover_func}; #??? not sure if helps
    delete $self->{select_func}; #??? not sure if helps
    delete $self->{click_func}; #??? not sure if helps
    
    delete $self->{cells_group}; #!!!! Without this, GnomeCanvas __crashes__
                                # Apparently, a reference cycle prevents it from being destroyed properly,
                                # and a bug makes it repaint in a half-dead state
    delete $self->{back_rect};
    delete $self->{cells};

    delete $self->{canvas};
    
    return;
}


##########################################################
# Setting up the canvas
##########################################################

sub make_mark {
    my $self = shift;
    my $anchor = shift;
    my $mark = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Text',
        text           => q{},
        anchor         => $anchor,
        fill_color_gdk => CELL_BLACK,
    );
    $mark->raise_to_top();
    return $mark;
}

sub make_legend_pixbuf {
    my $self = shift;
    my ($width, $height);
    my @pixels;

    # Make array of rgb values

    if ($self->{colours} eq 'Hue') {
        
        ($width, $height) = (LEGEND_WIDTH, 180);

        foreach my $row (0..($height - 1)) {
            my @rgb = hsv_to_rgb($row, 1, 1);
            push @pixels, (@rgb) x $width;
        }

    }
    elsif ($self->{colours} eq 'Sat') {
        
        ($width, $height) = (LEGEND_WIDTH, 100);

        foreach my $row (0..($height - 1)) {
            my @rgb = hsv_to_rgb($self->{hue}, 1 - $row / 100.0, 1);
            push @pixels, (@rgb) x $width;
        }

    }
    else {
        croak "Invalid colour system\n";
    }


    # Convert to low-level integers
    my $data = pack "C*", @pixels;

    my $pixbuf = Gtk2::Gdk::Pixbuf->new_from_data(
        $data,       # the data.  this will be copied.
        'rgb',       # only currently supported colorspace
        0,           # true, because we do have alpha channel data
        8,           # gdk-pixbuf currently allows only 8-bit samples
        $width,      # width in pixels
        $height,     # height in pixels
        $width * 3,  # rowstride -- we have RGBA data, so it's four
    );               #   bytes per pixel.

    return $pixbuf;
}

##########################################################
# Drawing stuff on the grid (mostly public)
##########################################################

# Draws a square matrix of specified length
#
sub draw_matrix {
    my $self = shift;
    my $side_length = shift;

    $self->{cells} = {};

    my ($cell_x, $cell_y, $width_pixels) = (10, 10, 0);

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
    
    $self->{cells_group} = $cells_group;
    $cells_group->lower_to_bottom();

    my $progress_bar = Biodiverse::Progress->new(gui_only => 1);
    my $progress = 0;
    my $progress_count = 0;

    # Draw left to right, top to bottom
    for (my $y = 0; $y < $side_length; $y++) {
        $progress = min ($y / $side_length, 1);
        $progress = $self->set_precision (value => $progress, precision => '%.4f');
        $progress_count ++;
        my $progress_text = "Drawing matrix, $progress_count rows";

        for (my $x = 0; $x < $side_length; $x++) {

            $progress_bar->update ($progress_text, $progress);
 
            my $rect = Gnome2::Canvas::Item->new (
                $cells_group,
                'Gnome2::Canvas::Rect',
                x1 =>  $x      * CELL_SIZE,
                y1 =>  $y      * CELL_SIZE,
                x2 => ($x + 1) * CELL_SIZE,
                y2 => ($y + 1) * CELL_SIZE,

                fill_color_gdk    => CELL_COLOUR,
                outline_color_gdk => CELL_BLACK,
                width_pixels      => $width_pixels,
            );

            $rect->signal_connect_swapped (event => \&on_event, $self);

            $self->{cells}{$rect}[INDEX_ELEMENT] = [$x, $y];
            $self->{cells}{$rect}[INDEX_RECT]    = $rect;
        }
    }

    # Flip the y-axis (default has origin top-left with y going down)
    # Add border
    my $total_cells_X = $side_length;
    my $total_cells_Y = $side_length;
    my $width  = $total_cells_X * CELL_SIZE;
    my $height = $total_cells_Y * CELL_SIZE;
    $self->{width_units}  = $width  + 2 * BORDER_SIZE;
    $self->{height_units} = $height + 4 * BORDER_SIZE;

    $self->{total_x} = $side_length - 1;

    # $cells_group->affine_absolute( [1, 0, 0, -1, BORDER_SIZE, $height + 2*BORDER_SIZE] );
    
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
    
    return;
}


#  need to handle locale issues in string conversions using sprintf
sub set_precision {
    my $self = shift;
    my %args = @_;
    
    my $num = sprintf ($args{precision}, $args{value});
    $num =~ s{,}{\.};  #  replace any comma with a decimal
    
    return $num;
}


# Gives each rectangle a value determined by a callback
#
# value_func : (h , v ) -> value for colouring
sub set_values {
    my $self = shift;
    my $value_func = shift;

    my $progress_bar = Biodiverse::Progress->new(gui_only => 1);
    my $progress = 0;
    my $progress_count = 0;
    my $progress_text = 'Updating sorted matrix cell values';

    my $hash = $self->{cells};
    my $indices;

    my $total_count = scalar keys %$hash;

    foreach my $rect (keys %$hash) {
        $progress_count ++;
        $progress = $progress_count / $total_count;

        $progress_bar->update ($progress_text, $progress);

        my $data = $hash->{$rect};

        my $indices = $data->[INDEX_ELEMENT];
        # the first argument to values_func refers to the horizontal row (ie: the y coord)
        $data->[INDEX_VALUES] = $value_func->($indices->[1], $indices->[0]);
    }
    
    return;
}

# Colours elements based on value in the given analysis (eg: Jaccard, REDUNDANCY,...)
sub set_colouring {
    my $self = shift;
    my $min_value = shift;
    my $max_value = shift;
    my $colour_none = shift;

    $self->{min} = $min_value;
    $self->{max} = $max_value;

    # Colour each cell
    $self->colour_cells($colour_none);

    # Set legend textbox markers
    if ($self->{marks} and defined $min_value) {
        my $marker_step = ($max_value - $min_value) / 3;
        foreach my $i (0..3) {
            my $text = sprintf ("%.4f", $min_value + $i * $marker_step); # round to 4 d.p.
            $self->{marks}[3 - $i]->set( text => $text );
        }
    }
    
    return;
}


##########################################################
# Highlighting rows/cols by masking the other ones
##########################################################

# PUBLIC #
#
sub highlight {
    my $self = shift;
    my $sel_rows = shift;
    my $sel_cols = shift;

    # Remove old mask
    if ($self->{mask}) {
        $self->{mask}->destroy;
        $self->{mask} = undef;
    }

    my @mask_rects = $self->get_mask_rects($sel_rows, $sel_cols);
    return if not @mask_rects; # if nothing to mask, return
    
    # Create a GnomeCanvasPathDef for all the regions we have to mask
    my @paths;
    my ($x, $y, $w, $h);

    foreach my $rect (@mask_rects) {
        my $pathdef = Gnome2::Canvas::PathDef->new;
        ($x, $y, $w, $h) = ($rect->x, $rect->y, $rect->width, $rect->height);
        #print "MASK RECT: ($x, $y) w=$w h=$h\n";

        $pathdef->moveto($x, $y);
        $pathdef->lineto($x + $w, $y);
        $pathdef->lineto($x + $w, $y + $h);
        $pathdef->lineto($x, $y + $h);
        $pathdef->closepath();

        push @paths, $pathdef;
    }

    # concatenate each region
    #  mask and stipple need to use Cairo
    #  - see issue 480 https://github.com/shawnlaffan/biodiverse/issues/480
    my $mask_path    = Gnome2::Canvas::PathDef->concat(@paths);
    my $mask_stipple = Gtk2::Gdk::Bitmap->create_from_data(
        undef,
        $gray50_bits,
        $gray50_width,
        $gray50_height,
    );

    $self->{mask} = Gnome2::Canvas::Item->new (
        $self->{cells_group},
        'Gnome2::Canvas::Shape',
        #fill_color    => 'white',
        #fill_stipple  => $mask_stipple,  #  off for now - issue 480
        #fill_color_rgba => 0xFFFFFFFF,
        outline_color => 'black',
        width_pixels  => 0,
    );

    $self->{mask}->signal_connect_swapped (event => \&on_event, $self);
    $self->{mask}->set_path_def($mask_path);

    return;
}

# {all regions} - {selected cells}
sub get_mask_rects {
    my $self = shift;
    my $sel_rows = shift;
    my $sel_cols = shift;

    my $total_lines = $self->{total_x} || 0;
    my $side_length = $total_lines * CELL_SIZE + CELL_SIZE;
    my $whole_matrix = Gtk2::Gdk::Rectangle->new(0, 0, $side_length, $side_length);

    # Create regions for all selected rows and columns
    my $row_reg = Gtk2::Gdk::Region->new;
    my $col_reg = Gtk2::Gdk::Region->new;
    my $rect;

    foreach my $sel (@$sel_rows) {
        $rect = Gtk2::Gdk::Rectangle->new(0, $sel * CELL_SIZE, $side_length, CELL_SIZE);
        $row_reg->union_with_rect($rect);
    }
    foreach my $sel (@$sel_cols) {
        $rect = Gtk2::Gdk::Rectangle->new($sel * CELL_SIZE, 0, CELL_SIZE, $side_length);
        $col_reg->union_with_rect($rect);
    }

    # If no row/col selected, act as though everything is
    if (not @$sel_rows) {
        $row_reg->union_with_rect($whole_matrix);
    }
    if (not @$sel_cols) {
        $col_reg->union_with_rect($whole_matrix);
    }

    # Intersect them - this makes the area we want highlighted
    my $intersect_reg = $col_reg;
    $intersect_reg->intersect($row_reg);

    # Subtract highlighted area from the whole area - giving us the mask region
    my $mask_reg = Gtk2::Gdk::Region->rectangle($whole_matrix);
    $mask_reg->subtract($intersect_reg);

    return $mask_reg->get_rectangles();
}

##########################################################
# Colouring based on an analysis value
##########################################################

sub colour_cells {
    my $self = shift;
    my $colour_none = shift || CELL_WHITE;

    my $progress_bar = Biodiverse::Progress->new(gui_only => 1);
    my $progress = 0;
    my $progress_count = 0;
    my $progress_text = 'Colouring matrix cells';

    my $hashref = $self->{cells};
    my $total_count = scalar keys %$hashref;

    foreach my $cell (values %$hashref) {
        $progress_count ++;
        $progress = $progress_count / $total_count;

        $progress_bar->update ($progress_text, $progress);

        my $val    = $cell->[INDEX_VALUES];
        my $rect   = $cell->[INDEX_RECT];
        my $colour = defined $val ? $self->get_colour($val, $self->{min}, $self->{max}) : $colour_none;
        my $fill_colour = defined $val ? $colour : CELL_BLACK;

        $rect->set('fill-color-gdk' => $colour, 'outline-color-gdk' => $fill_colour);
    }

    return;
}

sub get_colour {
    my $self = shift;
    
    if ($self->{colours} eq "Hue") {
        return $self->get_colour_hue(@_);
    }
    elsif ($self->{colours} eq "Sat") {
        return $self->get_colour_saturation(@_);
    }
    else {
        confess "Unknown colour system: " . $self->{colours} . "\n";
    }
    
    return;
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
    }
    elsif ($max != $min) {
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
    }
    elsif ($max != $min) {
        $sat = ($val - $min) / ($max - $min);
    }
    else {
        $sat = 1;
    }
    
    my ($r, $g, $b) = hsv_to_rgb($self->{hue}, $sat, 1);
    
    return Gtk2::Gdk::Color->new($r*257, $g*257, $b*257);
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

  if($i == 0) { return($v, $t, $p); }
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

sub maxmin {
  my($min, $max) = @_;
  for(my $i=0; $i<@_; $i++) {
    $max = $_[$i] if($max < $_[$i]);
    $min = $_[$i] if($min > $_[$i]);
  }
  return($max,$min);
}

##########################################################
# Event handling
##########################################################

# Events raised by little squares or the mask rect
# Works out the target by the mouse coords (easy since have a square matrix)
sub on_event {
    my ($self, $event, $cell) = @_;

    # Do everything with left clck now.
    if ($event->type =~ m/^button-/ && $event->button != 1) {
        return;
    }

    my ($x, $y) = ($event->x, $event->y);

    #print $event->x . "\n";
    #print $event->y . "\n";
    #print "\n\n";
    
    # normalize coordinates
    my $max_coord = $self->{total_x} * CELL_SIZE + CELL_SIZE;
    $x = min($max_coord, max (0, $x));
    $y = min($max_coord, max (0, $y));

    # By "horizontal element" we refer to the one whose values are on the row of the matrix running
    # horizontally. It is determined by the y-value
    my ($horz_elt, $vert_elt) = (floor($y / CELL_SIZE), floor($x / CELL_SIZE) );

    # If moved right onto the edge, we end up at the "next" row/col which doesn't exist
    $horz_elt-- if $y == $max_coord;
    $vert_elt-- if $x == $max_coord;

    #say "x=$x y=$y max=$max_coord horz=$horz_elt vert=$vert_elt";

    if ($event->type eq 'enter-notify') {

        # Call client-defined callback function
        if (my $f = $self->{hover_func}) {
            $f->($horz_elt, $vert_elt);
        }

        # Change the cursor if we are in select mode
        if (!$self->{cursor}) {
            my $cursor = Gtk2::Gdk::Cursor->new(HOVER_CURSOR);
            $self->{canvas}->window->set_cursor($cursor);
        }
    }
    elsif ($event->type eq 'leave-notify') {

        # Change cursor back to default
        $self->{canvas}->window->set_cursor($self->{cursor});

    }
    elsif ($event->type eq 'button-press') {

        if ($self->{drag_mode} eq 'select') {

            ($self->{sel_start_horez_elt}, $self->{sel_start_vert_elt}) = ($horz_elt, $vert_elt);
            ($self->{sel_start_x}, $self->{sel_start_y}) = ($x, $y);

            # Grab mouse
            $cell->grab (
                [qw/pointer-motion-mask button-release-mask/],
                Gtk2::Gdk::Cursor->new ('fleur'),
                $event->time,
            );
            $self->{selecting} = 1;
            $self->{sel_rect} = Gnome2::Canvas::Item->new (
                $self->{canvas}->root,
                'Gnome2::Canvas::Rect',
                x1 => $x,
                y1 => $y,
                x2 => $x,
                y2 => $y,
                fill_color_gdk    => undef,
                outline_color_gdk => CELL_BLACK,
                width_pixels      => 0,
            );

            return 0;
        }
        elsif ($self->{drag_mode} eq 'click') {
            if (defined $self->{grid_click_func}) {
                $self->{grid_click_func}->();
            }
        }
    }
    elsif ($event->type eq 'button-release') {
        if ($self->{selecting} and $event->button == 1) {
            $self->{sel_rect}->destroy;
            delete $self->{sel_rect};
            $cell->ungrab ($event->time);
            $self->{selecting} = 0;

            # Establish the selection
            my ($horz_start, $vert_start) = ($self->{sel_start_horez_elt}, $self->{sel_start_vert_elt});
            my ($horz_end,   $vert_end)   = ($horz_elt, $vert_elt);

            if ($horz_start > $horz_end) {
                ($horz_start, $horz_end) = ($horz_end, $horz_start);
            }
            if ($vert_start > $vert_end) {
                ($vert_start, $vert_end) = ($vert_end, $vert_start);
            }

            if (my $f = $self->{select_func}) {
                my $cell_coords = [$horz_start, $horz_end, $vert_start, $vert_end];
                my $pixel_coords = [$x, $y, $self->{sel_start_x}, $self->{sel_start_y}];
                $f->(cell_coords => $cell_coords, pixel_coords => $pixel_coords);
                delete $self->{sel_start_x};  #  clean up
                delete $self->{sel_start_y};
            }
        }
    }
    elsif ($event->type eq 'motion-notify') {
        # Call client-defined callback function
        if (my $f = $self->{hover_func}) {
            $f->($horz_elt, $vert_elt);
        }

        if ($self->{selecting}) {
            # Resize selection rectangle
            $self->{sel_rect}->set(x2 => $x, y2 => $y);
        }

        return 0;
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

        $self->reposition();
        $self->setup_scrollbars();
        $self->resize_background_rect();

    }
    
    return;
}

# Implements panning
sub on_background_event {
    my ($self, $event, $item) = @_;

    # Do everything with left clck now.
    if ($event->type =~ m/^button-/ && $event->button != 1) {
        return;
    }

    if ($event->type eq 'enter-notify') {
        $self->{page}->set_active_pane('matrix_grid');
    }
    elsif ($event->type eq 'leave-notify') {
        $self->{page}->set_active_pane('');
    }
    elsif ( $event->type eq 'button-press') {
#        print "Background Event\tPress\n";

        if ($self->{drag_mode} eq 'pan') {
            ($self->{pan_start_x}, $self->{pan_start_y}) = $event->coords;

            # Grab mouse
            $item->grab ([qw/pointer-motion-mask button-release-mask/],
                         Gtk2::Gdk::Cursor->new ('fleur'),
                        $event->time);
            $self->{dragging} = 1;
        }

    }
    elsif ( $event->type eq 'button-release') {
#        print "Background Event\tRelease\n";

        if ($self->{dragging}) {
            $item->ungrab ($event->time);
            $self->{dragging} = 0;
            $self->update_scrollbars(); #FIXME: If we do this for motion-notify - get great flicker!?!?
        }

    }
    elsif ( $event->type eq 'motion-notify') {
#        print "Background Event\tMotion\n";
        
        #if ($self->{dragging} && $event->state >= 'button1-mask' ) {
        if ($self->{dragging}) {
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

##########################################################
# Scrolling
##########################################################

sub setup_scrollbars {
    my $self = shift;
    return if !defined $self->{width_units} || !defined $self->{height_units};

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
        $self->reposition();
    }

    return;
}


##########################################################
# Zoom and Resizing
##########################################################

# Calculate pixels-per-unit to make image fit
sub fit_grid {
    my $self = shift;
    if (!$self->{width_px} or !$self->{height_px}) {
        #carp "width_px and/or height_px not defined\n";
        return;
    }
    if ($self->{width_units} == 0) {
        $self->{width_units} = 0.00001;
    }
    if ($self->{height_units} == 0) {
        $self->{height_units} = 0.00001;
    }
    my $ppu_width = $self->{width_px} / ($self->{width_units} // 1);
    my $ppu_height = $self->{height_px} / ($self->{height_units} // 1);
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
                x2 => max($width,  $self->{width_units} // 1),
                y2 => max($height, $self->{height_units} // 1),
            );
            $self->{back_rect}->lower_to_bottom();
        }
    }
    
    return;
}

# Updates position of legend and value box when canvas is resized or scrolled
sub reposition {
    my $self = shift;
    return if not defined $self->{legend};

    # Convert coordinates into world units
    # (this has been tricky to get working right...)
    #  SWL - use zero if these are not defined.  this is a total hack and not a solution
    my ($width, $height) = $self->{canvas}->c2w($self->{width_px} || 0, $self->{height_px} || 0);

    my ($scroll_x, $scroll_y) = $self->{canvas}->get_scroll_offsets();
    ($scroll_x, $scroll_y) = $self->{canvas}->c2w($scroll_x, $scroll_y);

    my ($border_width, $legend_width)
        = $self->{canvas}->c2w(BORDER_SIZE, LEGEND_WIDTH);

    $self->{legend}->set(
        x      => $width + $scroll_x - $legend_width, # world units
        y      => $scroll_y,                          # world units
        width  => LEGEND_WIDTH,                       # pixels
        height => $self->{height_px}                  # pixels
    );
    
    # Reposition the "mark" textboxes
    my $mark_x = $scroll_x + $width - $legend_width - 2 * $border_width; # world units
    foreach my $i (0..3) {
        $self->{marks}[$i]->set( x => $mark_x , y => $scroll_y + $i * $height / 3);
    }
    
    # Reposition value box
    if ($self->{value_group}) {
        my ($value_x, $value_y) = $self->{value_group}->get('x', 'y');
        $self->{value_group}->move( $scroll_x - $value_x,$scroll_y - $value_y);

        my ($text_width, $text_height) = $self->{value_text}->get("text-width", "text-height");

        # Resize value background rectangle
        $self->{value_rect}->set(x2 => $text_width, y2 => $text_height);
    }
    
    return;
}



sub on_scroll {
    my $self = shift;
    #FIXME: check if this helps reduce flicker
    $self->reposition();
    
    return;
}

##########################################################
# More public functions (zoom/colours)
##########################################################

sub zoom_in {
    my $self = shift;
    my $ppu = $self->{canvas}->get_pixels_per_unit();
    $self->{canvas}->set_pixels_per_unit( $ppu * 1.5 );
    $self->set_zoom_fit_flag (0);
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
    $self->resize_background_rect();
    $self->reposition();
    
    return;
}


sub set_colours {
    my $self = shift;
    $self->{colours} = shift;

    $self->colour_cells();

    # Update legend
    if ($self->{legend}) { 
        $self->{legend}->set(pixbuf => $self->make_legend_pixbuf() );
    }
    
    return;
}

=head2 set_hue

Sets the hue for the saturation (constant-hue) colouring mode

=cut

sub set_hue {
    my $self = shift;
    my $rgb = shift;

    $self->{hue} = (rgb_to_hsv($rgb->red / 257, $rgb->green /257, $rgb->blue / 257))[0];

    $self->colour_cells();

    # Update legend
    if ($self->{legend}) { 
        $self->{legend}->set(pixbuf => $self->make_legend_pixbuf() );
    }
    
    return;
}

1;
