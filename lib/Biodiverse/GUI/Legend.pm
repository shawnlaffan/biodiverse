=head1 LEGEND

Component to display a legend. 

=cut

package Biodiverse::GUI::Legend;

use 5.010;
use strict;
use warnings;
#use Data::Dumper;
use Carp;
use Scalar::Util qw /blessed/;
use List::Util qw /min max/;

use Gtk2;
use Gnome2::Canvas;
use Tree::R;

#use Geo::ShapeFile;

our $VERSION = '3.99_002';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::CellPopup;
use Biodiverse::BaseStruct;
use Biodiverse::Progress;

require Biodiverse::Config;
my $progress_update_interval = $Biodiverse::Config::progress_update_interval;

##########################################################
# Constants
##########################################################
use constant BORDER_SIZE        => 20;
use constant LEGEND_WIDTH       => 20;
use constant MARK_X_LEGEND_OFFSET  => 0.01;
use constant MARK_Y_LEGEND_OFFSET  => 8;
use constant LEGEND_HEIGHT  => 380;
use constant INDEX_RECT         => 2;  # Canvas (square) rectangle for the cell

use constant COLOUR_BLACK        => Gtk2::Gdk::Color->new(0, 0, 0);
use constant COLOUR_WHITE        => Gtk2::Gdk::Color->new(255*257, 255*257, 255*257);
use constant DARKEST_GREY_FRAC   => 0.2;
use constant LIGHTEST_GREY_FRAC  => 0.8;

##########################################################
# Construction
##########################################################

=head2 Constructor

=over 5

=back

=cut

sub new {
    my $class        = shift;
    my %args         = @_;

    my $canvas       = $args{canvas};
    my $legend_marks = $args{legend_marks} // [qw/nw w w sw/];
    my $legend_mode  = $args{legend_mode}  // 'Hue';
    my $width_px     = $args{width_px}     // 0;
    my $height_px    = $args{height_px}    // 0;

    my $self = {
        canvas       => $canvas,
        legend_marks => $legend_marks,
        legend_mode  => $legend_mode,
        width_px     => $width_px,
        height_px    => $height_px,
        hue          => $args{hue} // 0,
    };
    bless $self, $class;
    # Get the width and height of the canvas.
    #my ($width, $height) = $self->{canvas}->c2w($width_px || 0, $height_px || 0);
    my ($width, $height) = $self->{canvas}->c2w($self->{width_px} || 0, $self->{height_px} || 0);

    # Make group so we can pack the coloured
    # rectangles into it.
    $self->{legend_group} = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Group',
        x => $width - $self->get_width,
        y => 0,
    );
    $self->{legend_group}->raise_to_top();

    # Create the legend rectangle.
    $self->{legend} = $self->make_rect();

    $self->{marks}[0] = $self->make_mark( $self->{legend_marks}[0] );
    $self->{marks}[1] = $self->make_mark( $self->{legend_marks}[1] );
    $self->{marks}[2] = $self->make_mark( $self->{legend_marks}[2] );
    $self->{marks}[3] = $self->make_mark( $self->{legend_marks}[3] );

    return $self;
};

# Hide the legend
sub hide {
    my $self = shift;

    return if !$self->{legend_group};

    # Hide the legend group.
    $self->{legend_group}->hide;

    return;
}

# Show the legend
sub show {
    my $self = shift;

    return if !$self->{legend_group};

    # Show the legend group.
    $self->{legend_group}->show;

    return;
}

# Makes a rectangle and fills it 
# with colours for the chosen legend
# mode.
sub make_rect {
    my $self = shift;
    my ($width, $height);

    # If legend_colours_group already exists then destroy it.
    # We do this because we are about to create it again
    # with a different colour scheme as defined by legend_mode.
    if ($self->{legend_colours_group}) {
        $self->{legend_colours_group}->destroy(); 
    }

    # Make a group so we can pack the coloured
    # rectangles into it to create the legend.
    $self->{legend_colours_group} = Gnome2::Canvas::Item->new (
        $self->{legend_group},
        'Gnome2::Canvas::Group',
        x => 0, 
        y => 0, 
    );   

    # Create and colour the legend according to the colouring
    # scheme specified by $self->{legend_mode}. Each colour
    # mode has a different range as specified by $height.
    # Once the legend is create it is scaled to the height
    # of the canvas in reposition and according to each
    # mode's scaling factor held in $self->{legend_scaling_factor}.

    if ($self->{legend_mode} eq 'Hue') {

        ($width, $height) = ($self->get_width, 180);
        $self->{legend_height} = $height;

        foreach my $row (0..($height - 1)) {
            my @rgb = hsv_to_rgb($row, 1, 1);
            my ($r,$g,$b) = ($rgb[0]*257, $rgb[1]*257, $rgb[2]*257);
            $self->add_row($self->{legend_colours_group},$row,$r,$g,$b);
        }

    }
    elsif ($self->{legend_mode} eq 'Sat') {

        ($width, $height) = ($self->get_width, 100);
        $self->{legend_height} = $height;

        foreach my $row (0..($height - 1)) {
            my @rgb = hsv_to_rgb(
                $self->{hue},
                1 - $row / $height,
                1,
            );
            my ($r,$g,$b) = ($rgb[0]*257, $rgb[1]*257, $rgb[2]*257);
            $self->add_row($self->{legend_colours_group},$row,$r,$g,$b);
        }

    }
    elsif ($self->{legend_mode} eq 'Grey') {

        ($width, $height) = ($self->get_width, 255);
        $self->{legend_height} = $height;

        foreach my $row (0..($height - 1)) {
            my $intensity = $self->rescale_grey(255 - $row);
            my @rgb = ($intensity * 257 ) x 3;
            my ($r,$g,$b) = ($rgb[0], $rgb[1], $rgb[2]);
            $self->add_row($self->{legend_colours_group},$row,$r,$g,$b);
        }
    }
    else {
        croak "Legend: Invalid colour system\n";
    }

    return $self->{legend_colours_group};
}

# Add a coloured row to the legend.
sub add_row {
    my ($self, $group, $row, $r, $g, $b) = @_;

    my $width = $self->get_width;

    my $legend_colour_row = Gnome2::Canvas::Item->new (
        $group,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        x2 => $width,
        y1 => $row,
        y2 => $row+1,
        fill_color_gdk => Gtk2::Gdk::Color->new($r,$g,$b),
    );
}

##########################################################
# Setting up various components of the legend 
##########################################################

sub make_mark {
    my $self   = shift;
    my $anchor = shift;
    my $mark = Gnome2::Canvas::Item->new (
        $self->{legend_group}, 
        'Gnome2::Canvas::Text',
        text            => q{0},
        anchor          => $anchor,
        fill_color_gdk  => COLOUR_BLACK,
    );

    $mark->raise_to_top();

    return $mark;
}

sub set_gt_flag {
    my $self = shift;
    my $flag = shift;
    $self->{legend_gt_flag} = $flag;
    return;
}

sub set_lt_flag {
    my $self = shift;
    my $flag = shift;
    $self->{legend_lt_flag} = $flag;
    return;
}

sub set_width {
    my ($self, $width) = @_;
    $self->{back_rect_width} = $width;
}

sub get_width {
    my $self = shift;
    return $self->{back_rect_width} // LEGEND_WIDTH;
}

# Updates position of legend and value box
# when canvas is resized or scrolled
sub reposition {
    my $self = shift;
    my $width_px  = shift;
    my $height_px = shift;

    return if not defined $self->{legend};

    # Convert coordinates into world units
    # (this has been tricky to get working right...)
    my ($width, $height) = $self->{canvas}->c2w($width_px || 0, $height_px || 0);

    my ($scroll_x, $scroll_y) = $self->{canvas}->get_scroll_offsets();
       ($scroll_x, $scroll_y) = $self->{canvas}->c2w($scroll_x, $scroll_y);

    my ($border_width, $legend_width) = $self->{canvas}->c2w(BORDER_SIZE, $self->get_width);

    # Get the pixels per unit value from the canvas
    # to scale the legend with.
    my $ppu = $self->{canvas}->get_pixels_per_unit();

    # Reposition the legend group box
    $self->{legend_group}->set(
        x => $width  + $scroll_x - $legend_width,
        y => $scroll_y,
    );

    # Scale the legend's height and width to match the current size of the canvas. 
    my $matrix = [
        $legend_width * $ppu, # scale x
        0,
        0,
        $height / $self->{legend_height}, # scale y
        0,
        0
    ];
    $self->{legend_colours_group}->affine_absolute($matrix);

    # Reposition the "mark" textboxes
    foreach my $i (0..3) {
        my $mark = $self->{marks}[3 - $i];
        #  move the mark to right align with the legend
        my @bounds  = $mark->get_bounds;
        my @lbounds = $self->{legend}->get_bounds;
        my $offset  = $lbounds[0] - $bounds[2];
        $mark->move ($offset - ($width * MARK_X_LEGEND_OFFSET ), 0);

        # Set the location of the y of the marks
        # Has a vertical offset for the first and
        # last marks.
        my $y_offset = 0;
        if ($i == 0) {
            $y_offset =  MARK_Y_LEGEND_OFFSET;
        }
        elsif ($i == 3) {
            $y_offset = -MARK_Y_LEGEND_OFFSET;
        }
        $self->{marks}[$i]->set(
            y => $i * $height / 3 + $y_offset / $ppu,
        );

        $mark->raise_to_top;
    }

    # Reposition value box
    if ($self->{value_group}) {
        my ($value_x, $value_y) = $self->{value_group}->get('x', 'y');
        $self->{value_group}->move(
            $scroll_x - $value_x,
            $scroll_y - $value_y,
        );

        my ($text_width, $text_height)
            = $self->{value_text}->get('text-width', 'text-height');

        # Resize value background rectangle
        $self->{value_rect}->set(
            x2 => $text_width,
            y2 => $text_height,
        );
    }

    return;
}

# Set colouring mode - 'Hue' or 'Sat'
sub set_mode {
    my $self = shift;
    my $mode = shift;

    $mode = ucfirst lc $mode;

    croak "Invalid display mode '$mode'\n"
        if not $mode =~ /^Hue|Sat|Grey$/;

    $self->{legend_mode} = $mode;

    #$self->colour_cells();

    # Update legend
    if ($self->{legend}) { # && $self->{width_px} && $self->{height_px}) {
        $self->{legend} = $self->make_rect();
        $self->reposition($self->{width_px}, $self->{height_px});  #  trigger a redisplay of the legend
    }

    return;
}

sub get_mode {
    my $self = shift;
    return $self->{legend_mode};
}


=head2 setHue

Sets the hue for the saturation (constant-hue) colouring mode

=cut

sub set_hue {
    my $self = shift;
    my $rgb = shift;

    my @x = (rgb_to_hsv($rgb->red / 257, $rgb->green /257, $rgb->blue / 257));

    my $hue = (rgb_to_hsv($rgb->red / 257, $rgb->green /257, $rgb->blue / 257))[0];
    my $last_hue_used = $self->get_hue;
    return if defined $last_hue_used && $hue == $last_hue_used;

    $self->{hue} = $hue;

    # Update legend
    if ($self->{legend}) {
        $self->{legend} = $self->make_rect();
        $self->reposition($self->{width_px}, $self->{height_px})  #  trigger a redisplay of the legend
    }

    return;
}

sub get_hue {
    my $self = shift;
    return $self->{hue};
}

##########################################################
# Colouring based on an analysis value
##########################################################

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
    if ($self->get_log_mode) {
        if ($max != $min) {
            $val = log (1 + 100 * ($val - $min) / ($max - $min)) / log (101);
        }
        else {
            $val = 0;
        }
        $min = 0;
        $max = 1;
    }
    my @args = ($val, $min, $max);

    my $method = $colour_methods{$self->{legend_mode}};

    croak "Unknown colour system: $self->{legend_mode}\n"
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
    
    return if !defined $h;
    
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

# Sets the values of the textboxes next to the legend */
sub set_min_max {
    my ($self, $min, $max) = @_;

    $min //= $self->{last_min};
    $max //= $self->{last_max};

    $self->{last_min} = $min;
    $self->{last_max} = $max;

    return if ! ($self->{marks}
                 && defined $min
                 && defined $max
                );

    # Set legend textbox markers
    my $marker_step = ($max - $min) / 3;
    foreach my $i (0..3) {
        my $val = $min + $i * $marker_step;
        if ($self->get_log_mode) {
            my $log_step = log (101) * $i / 3;
            #  should use a method for each transform
            #  (log and antilog)
            #  orig:
            #  $val = log (1 + 100 * ($val - $min) / ($max - $min)) / log (101);
            $val = (exp ($log_step) - 1) / 100 * ($max - $min) + $min;
        }
        my $text = $self->format_number_for_display (number => $val);
        my $text_num = $text;  #  need to not have '<=' and '>=' in comparison lower down
        if ($i == 0 and $self->{legend_lt_flag}) {
            $text = '<=' . $text;
        }
        elsif ($i == 3 and $self->{legend_gt_flag}) {
            $text = '>=' . $text;
        }
        elsif ($self->{legend_lt_flag} or $self->{legend_gt_flag}) {
            $text = '  ' . $text;
        }

        my $mark = $self->{marks}[3 - $i];
        $mark->set( text => $text );
        #  move the mark to right align with the legend
        my @bounds = $mark->get_bounds;
        my @lbounds = $self->{legend}->get_bounds;
        my $offset = $lbounds[0] - $bounds[2];
        if (($text_num + 0) != 0) {
            $mark->move ($offset - length ($text), 0);
        }
        else {
            $mark->move ($offset - length ($text) - 0.5, 0);
        }
        $mark->raise_to_top;
    }

    return;
}

sub set_log_mode_on {
    my ($self) = @_;
    return $self->{log_mode} = 1;
}

sub set_log_mode_off {
    my ($self) = @_;
    return $self->{log_mode} = 0;
}

sub get_log_mode {
    $_[0]->{log_mode};
}

#  dup from Tab.pm - need to inherit from single source
sub format_number_for_display {
    my $self = shift;
    my %args = @_;
    my $val = $args{number};

    my $text = sprintf ('%.4f', $val); # round to 4 d.p.
    if ($text == 0) {
        $text = sprintf ('%.2e', $val);
    }
    if ($text == 0) {
        $text = 0;  #  make sure it is 0 and not 0.00e+000
    };
    return $text;
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

#  should replace with List::MoreUtils::minmax
sub maxmin {
    my($min, $max) = @_;
    
    for(my $i=0; $i<@_; $i++) {
        $max = $_[$i] if($max < $_[$i]);
        $min = $_[$i] if($min > $_[$i]);
    }
    
    return($max,$min);
}

1;
