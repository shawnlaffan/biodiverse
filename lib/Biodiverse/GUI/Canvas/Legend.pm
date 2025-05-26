package Biodiverse::GUI::Canvas::Legend;
use strict;
use warnings;
use 5.036;

use Carp qw /croak/;
use List::MoreUtils qw/minmax/;
use Scalar::Util qw/weaken/;
use POSIX qw /ceil/;

#  we do not inherit from Biodiverse::GUI::Canvas as we are called by it
use parent qw /Biodiverse::GUI::Legend/;

##########################################################
# Constants
##########################################################
use constant BORDER_SIZE        => 20;
use constant LEGEND_WIDTH       => 20;
use constant MARK_X_LEGEND_OFFSET  => 0.01;
use constant MARK_Y_LEGEND_OFFSET  => 8;
use constant LEGEND_HEIGHT  => 380;
use constant INDEX_RECT         => 2;  # Canvas (square) rectangle for the cell

use constant COLOUR_BLACK        => Gtk3::Gdk::RGBA::parse('black');
use constant COLOUR_WHITE        => Gtk3::Gdk::RGBA::parse('white');
use constant DARKEST_GREY_FRAC   => 0.2;
use constant LIGHTEST_GREY_FRAC  => 0.8;


sub new {
    my $class        = shift;
    my %args         = @_;

    my $canvas       = $args{drawable};
    my $legend_marks = $args{legend_marks} // [qw/nw w w sw/];
    my $legend_mode  = $args{legend_mode}  // 'Hue';
    my $width_px     = $args{width_px}     // 0;
    my $height_px    = $args{height_px}    // 0;

    my $self = {
        drawable     => $canvas,
        legend_marks => $legend_marks,
        legend_mode  => $legend_mode,
        width_px     => $width_px,
        height_px    => $height_px,
        hue          => $args{hue} // 0,
        parent       => $args{parent},
    };
    #  we need to know about the parent to get things like the transform matrix
    weaken $self->{parent};

    bless $self, $class;

    return $self;
};

sub drawable {
    my ($self) = @_;
    $self->{drawable} //= $self->get_parent->drawable;
}

sub get_parent {
    my ($self) = @_;
    $self->{parent};
}

sub hide {
    $_[0]{show} = 0;
}

sub show {
    $_[0]{show} = 1;
}

sub set_visible {
    $_[0]{show} = !!$_[1];
}

sub is_visible {
    !!$_[0]{show};
}

sub get_width {
    my $self = shift;
    return $self->{width_px} //= LEGEND_WIDTH;
}

sub get_height {
    my $self = shift;
    return $self->{height_px} //= LEGEND_HEIGHT;
}

sub draw {
    my ($self, $cx) = @_;

    my $drawable = $self->drawable;

    my $data = $self->make_data;

    my $orig_mx = $cx->get_matrix;
    # my $mx = $self->get_tfm_mx;
    my $mx = $self->get_parent->get_orig_tfm_matrix;
    $cx->set_matrix($mx);

    #  should get from parent - what does it permit?
    my $draw_size = $drawable->get_allocation();
    my ($canvas_w, $canvas_h, $canvas_x, $canvas_y) = @$draw_size{qw/width height x y/};
    ($canvas_x, $canvas_y) = (0,0);
    my $width = 20;
    my $height = $canvas_h / 1.1;
    my $x_origin = $canvas_w - ($canvas_w - $canvas_w / 1.1) / 2 - $width;
    my $centre_y = $canvas_h / 2;
    my $y_origin = $centre_y - $height / 2;  # FIXME

    my $row_height = $height / @$data;
    my $y = $y_origin;
    $cx->set_line_width(1);
    foreach my $row (@$data) {
        my $colour = $row->[-1];
        $cx->set_source_rgb(@$colour);
        $cx->rectangle ($x_origin, $y, $width, ceil($row_height));
        $cx->fill;
        # $cx->stroke;
        $y += $row_height;
    }

    #  now the outline
    $cx->set_source_rgb((0.5)x3);
    $cx->set_line_width(2);
    my @rect = ($x_origin, $y_origin, $width, $height);
    $cx->rectangle(@rect);
    $cx->stroke;

    $cx->set_matrix($orig_mx);

    return;
}

sub get_tfm_mx {
    my ($self, $drawable, $noisy) = @_;

    $drawable //= $self->drawable;
    my $draw_size = $drawable->get_allocation();
    my ($canvas_w, $canvas_h, $canvas_x, $canvas_y) = @$draw_size{qw/width height x y/};

    my $dims_h = $self->{dims} //= {xcen => 0.5, ycen => 0.5, xwidth => 1, ywidth => 1};

    my $xcen = $dims_h->{xcen};
    my $ycen = $dims_h->{ycen};

    if ($noisy) {
        my $fmt = "%9.2f %9.2f %9.2f %9.2f";
        say sprintf $fmt, $xcen, $ycen, $dims_h->{xcen}, $dims_h->{ycen};
    }

    #  Always override in case the matrix has changed from when this was last set
    #  Seems to be needed to correct for offsets with mouse clicks.  These are
    #  offset as a function of the original Cairo matrix and whatever window
    #  contents are around the DrawingArea.
    my $orig_mx = $self->get_parent->get_orig_tfm_matrix;

    my $mx = $self->clone_tfm_mx($orig_mx);

    ($canvas_x, $canvas_y) = (0,0);  #  no longer needed below

    # centre on 0,0 allowing for window edges
    $mx->translate(
        $canvas_w / 2,
        $canvas_h / 2,
    );

    #  rescale, including zoom
    $mx->scale(1, 1);

    #  and shift to display centre
    $mx->translate(-$xcen, -$ycen);

    return $mx;
}

sub get_scale_factors {
    my ($self, $drawable) = @_;

    $drawable //= $self->drawable;

    my $draw_size = $drawable->get_allocation();
    my ($canvas_w, $canvas_h) = @$draw_size{qw/width height/};

    #  The buffer should be a 5% margin or similar of the scale factor
    #  but is used in the transforms so needs to be in map units
    my $buffer_frac = $self->{buffer_frac} //= 1;

    my $dims_h = $self->{dims};
    $dims_h->{xwidth};
    $dims_h->{yheight};

    my @scale_factors = (
        $canvas_w / ($dims_h->{xwidth}  * $buffer_frac),
        $canvas_h / ($dims_h->{yheight} * $buffer_frac)
    );

    #  rescale
    my $zoom_factor = $dims_h->{scale} //= .5;
    if ($zoom_factor) {
        @scale_factors = map {$zoom_factor * $_ } @scale_factors;
    }

    return @scale_factors;
}

sub clone_tfm_mx {
    my ($self, $mx) = @_;
    $mx //= $self->{matrix};
    return $mx->multiply (Cairo::Matrix->init_identity);
}

sub rgba_to_cairo {
    my ($self, $rgba) = @_;
    my @res = ($rgba->red, $rgba->green, $rgba->blue);
    return wantarray ? @res : \@res;
}

sub make_data {
    my $self = shift;

    my $mode_string = $self->get_mode;
    if ($mode_string ne 'categorical') {
        my $data = $self->{_cache}{$mode_string};
        return $data if $data;
    }
    #  Need to update this comment as it is from the old code.
    #  Now we generate rows that can be plotted later.
    # Create and colour the legend according to the colouring
    # scheme specified by $self->{legend_mode}. Each colour
    # mode has a different range as specified by $height.
    # Once the legend is create it is scaled to the height
    # of the canvas in reposition and according to each
    # mode's scaling factor held in $self->{legend_scaling_factor}.

    warn 'Legend: Remember to re-enable add_row';

    #  refactor as state var inside a sub
    state %canape_colour_hash = (
        0 => Gtk3::Gdk::RGBA::parse('lightgoldenrodyellow'),  #  non-sig, lightgoldenrodyellow
        1 => Gtk3::Gdk::RGBA::parse('red'),                   #  red, neo
        2 => Gtk3::Gdk::RGBA::parse('royalblue1'),            #  blue, palaeo
        3 => Gtk3::Gdk::RGBA::parse('#CB7FFF'),               #  purple, mixed
        4 => Gtk3::Gdk::RGBA::parse('darkorchid'),            #  deep purple, super ('#6A3d9A' is too dark)
    );
    state @canape_order = (4,3,2,0,1);  #  double check

    my @data;
    if ($self->get_canape_mode) {
        foreach my $row (0..$#canape_order) {
            my $class = $canape_order[$row];
            my $colour = $canape_colour_hash{$class};
            push @data, [$class, [$self->rgba_to_cairo($colour)]];
        }
    }
    elsif ($self->get_categorical_mode) {
        my $label_hash = $self->{categorical}{labels};
        my @classes = sort {$a <=> $b} keys %$label_hash;
        foreach my $i (0..$#classes) {  #  might need to reverse this
            my $colour = $self->get_colour_categorical ($classes[$i]);
            push @data, [$classes[$i], [$self->rgba_to_cairo($colour)]];
        }
    }
    elsif ($self->get_zscore_mode) {

        my @dummy_zvals = reverse (-2.6, -2, -1.7, 0, 1.7, 2, 2.6);
        warn 'z-score legend needs class names';
        foreach my $i (0..$#dummy_zvals) {
            my $colour = $self->get_colour_zscore ($dummy_zvals[$i]);
            push @data, [$dummy_zvals[$i], [$self->rgba_to_cairo($colour)]];
        }
    }
    elsif ($self->get_prank_mode) {
        my @dummy_vals = reverse (0.001, 0.02, 0.04, 0.5, 0.951, 0.978, 0.991);
        warn 'p-rank legend needs labels';
        foreach my $i (0..$#dummy_vals) {
            my $colour = $self->get_colour_prank ($dummy_vals[$i]);
            push @data, [$dummy_vals[$i], [$self->rgba_to_cairo($colour)]];
        }
    }
    elsif ($self->get_ratio_mode) {

        local $self->{log_mode} = 0; # hacky override

        my $height = 255;
        my $mid = ($height - 1) / 2;
        foreach my $row (reverse 0..($height - 1)) {
            my $val = $row < $mid ? 1 / ($mid - $row) : $row - $mid;
            #  invert again so colours match legend text
            my $colour = $self->get_colour_ratio (1/$val, 1/$mid, $mid);
            push @data, [$val, [$self->rgba_to_cairo($colour)]];
        }
    }
    elsif ($self->get_divergent_mode) {
        my $height = 180;

        local $self->{log_mode} = 0; # hacky override

        my $centre = ($height - 1) / 2;
        my $extreme = $height - $centre;

        #  ensure colours match plot since 0 is the top
        foreach my $row (reverse 0..($height - 1)) {
            my $colour = $self->get_colour_divergent ($centre - $row, -$extreme, $extreme);
            push @data, [$row, [$self->rgba_to_cairo($colour)]];
        }
    }
    elsif ($self->{legend_mode} eq 'Hue') {
        my $height = 180;

        local $self->{log_mode} = 0; # hacky override

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_hue ($height - $row, 0, $height-1);
            push @data, [$row, [$self->rgba_to_cairo($colour)]];
        }

    }
    elsif ($self->{legend_mode} eq 'Sat') {
        my $height = 100;

        local $self->{log_mode} = 0; # hacky override

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_saturation ($height - $row, 0, $height-1);
            push @data, [$row, [$self->rgba_to_cairo($colour)]];
        }
    }
    elsif ($self->{legend_mode} eq 'Grey') {
        my $height = 255;

        local $self->{log_mode} = 0; # hacky override

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_grey ($height - $row, 0, $height-1);
            push @data, [$row, [$self->rgba_to_cairo($colour)]];
        }
    }
    else {
        croak "Legend: Invalid colour system $self->{legend_mode}\n";
    }

    $self->{rows_to_plot} = \@data;
    $self->{_cache}{$mode_string} = \@data;

    return \@data;
}

sub make_mark {
    my $self = shift;
    say 'make_mark yet to be implemented';
    $self->{marks}{current} //= [];
    return;
}

sub hide_current_marks {
    return;
}

sub show_current_marks {
    return;
}

# Set colouring mode - 'Hue' or 'Sat'
sub set_mode {
    my ($self, $mode) = @_;
    $mode //= $self->get_mode;

    $mode = ucfirst lc $mode;

    croak "Invalid display mode '$mode'\n"
        if not $mode =~ /^Hue|Sat|Grey$/;

    $self->{legend_mode} = $mode;

    return;
}

sub get_mode {
    my $self = shift;
    return $self->{legend_mode} //= 'Hue';
}

#  The GUI::Legend version sets the text marks but we do not need to
sub set_min_max {
    #  val1 and val2 could be min/max or mid/extent
    my ($self, $val1, $val2) = @_;

    return if
           $self->get_zscore_mode
        || $self->get_prank_mode
        || $self->get_canape_mode
        || $self->get_categorical_mode;

    if ($self->get_divergent_mode) {
        my $abs_extreme = max(abs $val1, abs $val2);
        $val1 = 0;
        $val2 = $abs_extreme;
    }
    elsif ($self->get_ratio_mode) {
        my $abs_extreme = exp (max (abs log $val1, log $val2));
        $val1 = 1 / $abs_extreme;
        $val2 = $abs_extreme;
    }

    my $min = $val1 //= $self->{last_min};
    my $max = $val2 //= $self->{last_max};

    $self->{last_min} = $min;
    $self->{last_max} = $max;

    return;
}


# Sets the hue for the saturation (constant-hue) colouring mode
sub set_hue {
    my ($self, $rgb) = @_;

    my $hue = ($self->rgb_to_hsv(map {$_ * 255} ($rgb->red, $rgb->green, $rgb->blue)))[0];
    my $last_hue_used = $self->get_hue;
    return if defined $last_hue_used && $hue == $last_hue_used;

    $self->{hue} = $hue;

    return;
}

sub get_hue {
    my $self = shift;
    return $self->{hue};
}

sub rgb_to_hsv {
    my ($self, $var_r, $var_g, $var_b) = @_;

    my($var_min, $var_max) = minmax($var_r, $var_g, $var_b);
    my $del_max = $var_max - $var_min;

    if ($del_max) {
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

our $AUTOLOAD;

#  temporary
sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self)
        or croak "$self is not an object\n";

    my $method = $AUTOLOAD;
    $method =~ s/.*://;   # strip fully-qualified portion

    say "$method not implemented";
    return;
}

sub DESTROY {}  #  let the system handle destruction - need this for AUTOLOADER


1;
