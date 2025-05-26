package Biodiverse::GUI::Canvas::Legend;
use strict;
use warnings;
use 5.036;

use experimental qw/refaliasing declared_refs/;

use Carp qw /croak/;
use List::MoreUtils qw/minmax/;
use Scalar::Util qw/weaken blessed/;
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

    #  cache all but categorical for now
    my $mode_string = $self->get_mode_as_string;
    if ($mode_string ne 'categorical') {
        my $data = $self->{_cache}{data}{$mode_string};
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

    my @data;
    if ($self->get_canape_mode) {
        state @canape_order = (4,3,2,0,1);  #  double check
        \my %canape_colour_hash = $self->get_canape_colour_hash;
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

        local $self->{log_mode} = 0; # hacky override - still needed?

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

        local $self->{log_mode} = 0; # hacky override - still needed?

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

        local $self->{log_mode} = 0; # hacky override - still needed?

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
    $self->{_cache}{data}{$mode_string} = \@data;

    return \@data;
}

sub get_canape_colour_hash {
    #  refactor as state var inside a sub
    state %canape_colour_hash = (
        0 => Gtk3::Gdk::RGBA::parse('lightgoldenrodyellow'),  #  non-sig, lightgoldenrodyellow
        1 => Gtk3::Gdk::RGBA::parse('red'),                   #  red, neo
        2 => Gtk3::Gdk::RGBA::parse('royalblue1'),            #  blue, palaeo
        3 => Gtk3::Gdk::RGBA::parse('#CB7FFF'),               #  purple, mixed
        4 => Gtk3::Gdk::RGBA::parse('darkorchid'),            #  deep purple, super ('#6A3d9A' is too dark)
    );
    return wantarray ? %canape_colour_hash : \%canape_colour_hash;
}

sub set_colour_mode_from_list_and_index {
    my ($self, %args) = @_;
    my $index = $args{index} // '';
    my $list  = $args{list}  // '';

    state $bd_obj = Biodiverse::BaseData->new (
        NAME         => 'colour-mode',
        CELL_SIZES   => [1],
        CELL_ORIGINS => [0]
    );
    state $indices_object = Biodiverse::Indices->new (
        BASEDATA_REF => $bd_obj,
    );

    my $is_list = $list && $list !~ />>/ && $indices_object->index_is_list (index => $list);
    if ($is_list) {
        $index = $list
    }

    #  check list name then index name
    my %h = (index => $index);
    my $mode
        = $list =~ />>z_scores>>/                      ? 'zscore'
        : $list =~ />>p_rank>>/                        ? 'prank'
        : $list =~ />>CANAPE.*?>>/ && $index =~ /^CANAPE/ ? 'canape'
        : $indices_object->index_is_zscore (%h)        ? 'zscore'
        : $indices_object->index_is_ratio (%h)         ? 'ratio'
        : $indices_object->index_is_divergent (%h)     ? 'divergent'
        : $indices_object->index_is_categorical (%h)   ? 'categorical'
        : '';

    #  clunky to have to iterate over these but they trigger things turning off
    #  Update - might not be the case now but process does not take long
    foreach my $possmode ($self->_get_nonbasic_plot_modes) {
        my $method = "set_${possmode}_mode";
        $self->$method ($mode eq $possmode);
    }

    if ($mode eq 'categorical') {
        my $labels  = $indices_object->get_index_category_labels (index => $index) // {};
        my $colours = $indices_object->get_index_category_colours (index => $index) // {};
        $self->{categorical}{labels}  = $labels;
        #  don't mess with the cached object
        foreach my $key (keys %$colours) {
            my $colour = $colours->{$key};
            next if blessed $colour;  #  sometimes they are already colour objects
            $self->{categorical}{colours}{$key} = Gtk3::Gdk::RGBA::parse($colour);
        }
    }
    elsif (!$mode && $list =~ />>CANAPE>>/) {
        #  special handling for CANAPE indices
        my %codes = (
            NEO => 1, PALAEO => 2, MIXED => 3, SUPER => 4,
        );
        #  special handling
        \my %canape_colour_hash = $self->get_canape_colour_hash;
        my $colour = $canape_colour_hash{$codes{$index} // 0};
        $self->{categorical}{colours} = {
            0 => $canape_colour_hash{0},
            1 => $colour,
        };
        $self->{categorical}{labels} = {
            0 => 'other',
            1 => lc $index,
        };
        $self->set_categorical_mode(1);
    }

    return;
}

sub get_colour_method {
    my $self = shift;

    my $method = 'get_colour';

    #  clunky to have to iterate over these,
    #  even if we use a lookup table
    foreach my $mode ($self->_get_nonbasic_plot_modes()) {
        my $check_method = "get_${mode}_mode";
        if ($self->$check_method) {
            $method = "get_colour_${mode}";
        }
    }

    return $method;
}

#  need a better name
sub _get_nonbasic_plot_modes {
    my @modes = qw/canape zscore prank ratio divergent categorical/;
    return wantarray ? @modes : \@modes;
}

#  mode is currently messy - we store hue/sat/grey in pne place
#  but use flags for the others
sub get_mode_as_string {
    my ($self) = @_;

    my $mode_string;
    foreach my $mode ($self->_get_nonbasic_plot_modes()) {
        my $check_method = "get_${mode}_mode";
        if ($self->$check_method) {
            $mode_string = $mode;
            last;
        }
    }
    $mode_string //= $self->get_mode;

    return $mode_string;
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
