package Biodiverse::GUI::Canvas::Legend;
use strict;
use warnings;
use 5.036;

our $VERSION = '4.99_002';

use experimental qw/refaliasing declared_refs/;

use Carp qw /croak/;
use List::Util qw /min max/;
use List::MoreUtils qw/minmax firstidx/;
use Scalar::Util qw/weaken blessed/;
use POSIX qw /ceil/;

#  we do not inherit from Biodiverse::GUI::Canvas as we are called by it
use parent qw /Biodiverse::GUI::Legend/;
use parent qw /Biodiverse::Common::Caching/;

##########################################################
# Constants
##########################################################
# use constant BORDER_SIZE      => 20;
use constant LEGEND_WIDTH      => 20;
use constant X_LEGEND_OFFSET   => 2;
use constant X_LEGEND_TEXT_GAP => 4;
use constant Y_LEGEND_OFFSET   => 8;

use constant COLOUR_BLACK        => Gtk3::Gdk::RGBA::parse('black');
use constant COLOUR_WHITE        => Gtk3::Gdk::RGBA::parse('white');
use constant DARKEST_GREY_FRAC   => 0.2;
use constant LIGHTEST_GREY_FRAC  => 0.8;


#  refactor as state var inside a sub
#  supports state on lists (5.28)
my %canape_colour_hash = (
    0 => Gtk3::Gdk::RGBA::parse('lightgoldenrodyellow'),  #  non-sig, lightgoldenrodyellow
    1 => Gtk3::Gdk::RGBA::parse('red'),                   #  red, neo
    2 => Gtk3::Gdk::RGBA::parse('royalblue1'),            #  blue, palaeo
    3 => Gtk3::Gdk::RGBA::parse('#CB7FFF'),               #  purple, mixed
    4 => Gtk3::Gdk::RGBA::parse('darkorchid'),            #  deep purple, super ('#6A3d9A' is too dark)
);


sub new {
    my $class        = shift;
    my %args         = @_;

    my $canvas       = $args{drawable};
    my $legend_mode  = $args{legend_mode}  // 'Hue';

    my $self = {
        drawable     => $canvas,
        legend_mode  => $legend_mode,
        width_px     => LEGEND_WIDTH,
        hue          => $args{hue} // 0,
        parent       => $args{parent},
        show         => $args{show} // $args{show_legend} // 1,
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
    return $self->{width_px} ||= LEGEND_WIDTH;
}

sub draw {
    my ($self, $cx) = @_;

    return if !$self->is_visible;
    #  don't draw if no sensible labels
    return if $self->mode_is_continuous && !($self->get_stats || defined $self->{last_max});

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
    my $width = LEGEND_WIDTH;
    my $legend_height = $canvas_h / 1.1;
    # my $x_origin = $canvas_w - ($canvas_w - $canvas_w / 1.1) / 2 - $width;
    my $x_origin = $canvas_w - $width - X_LEGEND_OFFSET;
    my $centre_y = $canvas_h / 2;
    my $y_origin = $centre_y - $legend_height / 2;  # FIXME?

    my $colour_array = $data->{colours};
    if ($self->get_invert_colours) {
        #  reverse a copy
        $colour_array = [reverse @$colour_array];
    }
    my $row_height = $legend_height / @$colour_array;
    my $y = $y_origin;
    $cx->set_line_width(1);
    foreach my $colour (@$colour_array) {
        $cx->set_source_rgb(@$colour);
        $cx->rectangle ($x_origin, $y, $width, ceil($row_height));
        $cx->fill;
        # $cx->stroke;
        $y += $row_height;
    }

    my $label_array = $data->{labels};
    my $y_spacing = $legend_height / (@$label_array || 1);
    my @alignments;
    if (!@$label_array) {
        $label_array = $self->get_dynamic_labels;
        if ($self->get_categorical_mode) {
            #  need to recalc this since we have a new array
            $y_spacing = $legend_height / (@$label_array || 1);
        }
        else {
            # we want to label the corners for continuous dynamic types
            $y_spacing = $legend_height / (@$label_array - 1);
            $alignments[0] = 'U';
            $alignments[$#$label_array] = 'L'; #  align bottom
            # say join ' ', @$label_array;
        }
    }
    if (@$label_array) {
        $cx->select_font_face("Sans", "normal", "normal");
        $cx->set_font_size(12);
        my $x_gap_extents = $cx->text_extents ('n');  #  an en-space
        my $x_gap = $x_gap_extents->{width};
        # my $y_spacing = $row_height;  #  this only works for one label per row
        $y = $y_origin + $row_height / 2; #  centre on boxes
        my $i = -1;
        foreach my $label (@$label_array) {
            $i++;
            # say "$label will be plotted at $y";
            $cx->set_source_rgb(0, 0, 0);
            my $extents = $cx->text_extents ($label);
            my $alignment = $alignments[$i] // '';
            my $y_off
                = $alignment eq 'U' ?  $extents->{height} #  align vertical top
                : $alignment eq 'L' ?  $row_height - $extents->{height} / 2 #  vertical bottom
                : $extents->{height} / 2;                 #  vertical centre
            $cx->move_to(  #  right align with a small offset
                $x_origin - $extents->{width} - $x_gap,
                $y + $y_off,
            );
            $cx->show_text($label);
            $y += $y_spacing;
        }
    }

    #  now the outline - but was not used in Gtk2 version
    #  A no-op now but if we don't do it then a line is drawn
    #  to the mouse when hovering on cells.
    if (1) {
        $cx->set_source_rgb((0.5) x 3);
        $cx->set_line_width(2);
        my @rect = ($x_origin, $y_origin, $width, $legend_height);
        @rect = (0,0,0,0);  #  no-op
        $cx->rectangle(@rect);
        $cx->stroke;
    }

    $cx->set_matrix($orig_mx);

    return;
}

#  a no-op now
sub refresh_legend {
    1;
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
    my $cached_data = $self->get_cached_value_dor_set_default_href ('data');

    return $cached_data->{$mode_string}
        if $mode_string ne 'categorical' && $cached_data->{$mode_string};

    #  Now we generate rows of colours and labels that can be plotted later.

    my @colours;
    my @labels;
    if ($self->get_canape_mode) {
        #  special handling for CANAPE indices
        @labels = qw /Neo Non-Sig Palaeo Mixed Super/;
        state @canape_order = (4,3,2,0,1);  #  double check
        \my %canape_colour_hash = $self->get_canape_colour_hash;
        foreach my $class (@canape_order) {
            my $colour = $canape_colour_hash{$class};
            push @colours, [ $self->rgba_to_cairo($colour) ];
        }
    }
    elsif ($self->get_categorical_mode) {
        my $label_hash = $self->{categorical}{labels};
        # my $labels  = $indices_object->get_index_category_labels (index => $index) // {};
        # my $colours = $indices_object->get_index_category_colours (index => $index) // {};

        my @classes = sort {$a <=> $b} keys %$label_hash;
        foreach my $i (0..$#classes) {  #  might need to reverse this
            my $colour = $self->get_colour_categorical ($classes[$i]);
            push @colours, [ $self->rgba_to_cairo($colour) ];
        }
    }
    elsif ($self->get_zscore_mode) {
        @labels = ('<-2.58', '[-2.58,-1.96)', '[-1.96,-1.65)', '[-1.65,1.65]', '(1.65,1.96]', '(1.96,2.58]', '>2.58');
        my @dummy_zvals = reverse (-2.6, -2, -1.7, 0, 1.7, 2, 2.6);
        foreach my $i (0..$#dummy_zvals) {
            my $colour = $self->get_colour_zscore ($dummy_zvals[$i]);
            push @colours, [ $self->rgba_to_cairo($colour) ];
        }
    }
    elsif ($self->get_prank_mode) {
        @labels = ('<0.01', '<0.025', '<0.05', '[0.05,0.95]', '>0.95', '>0.975', '>0.99');
        my @dummy_vals = reverse (0.001, 0.02, 0.04, 0.5, 0.951, 0.978, 0.991);
        foreach my $i (0..$#dummy_vals) {
            my $colour = $self->get_colour_prank ($dummy_vals[$i]);
            push @colours, [ $self->rgba_to_cairo($colour) ];
        }
    }
    elsif ($self->get_ratio_mode) {

        local $self->{log_mode} = 0; # hacky override - still needed?

        my $height = 180;
        my $mid = ($height - 1) / 2;
        foreach my $row (reverse 1..$height) {
            my $val = $row < $mid ? 1 / ($mid - $row) : $row - $mid;
            # $val = $row / $mid;
            #  invert again so colours match legend text
            my $colour = $self->get_colour_ratio ($val, 1/$mid, $mid);
            push @colours, [ $self->rgba_to_cairo($colour) ];
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
            push @colours, [ $self->rgba_to_cairo($colour) ];
        }
    }
    elsif ($self->{legend_mode} eq 'Hue') {
        my $height = 180;

        local $self->{log_mode} = 0; # hacky override - still needed?

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_hue ($height - $row, 0, $height-1);
            push @colours, [ $self->rgba_to_cairo($colour) ];
        }
    }
    elsif ($self->{legend_mode} eq 'Sat') {
        my $height = 100;

        local $self->{log_mode} = 0; # hacky override

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_saturation ($height - $row, 0, $height-1);
            push @colours, [ $self->rgba_to_cairo($colour) ];
        }
    }
    elsif ($self->{legend_mode} eq 'Grey') {
        my $height = 255;

        local $self->{log_mode} = 0; # hacky override

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_grey ($height - $row, 0, $height-1);
            push @colours, [ $self->rgba_to_cairo($colour) ];
        }
    }
    else {
        croak "Legend: Invalid colour system $self->{legend_mode}\n";
    }

    my $results = { labels => \@labels, colours => \@colours };
    $cached_data->{$mode_string} = $results;
    $self->{rows_to_plot}        = $results;

    return $results;
}

#  flip the colour ranges if true
sub get_invert_colours {
    $_[0]->{invert_colours};
};

sub set_invert_colours {
    my ($self, $bool) = @_;
    $self->{invert_colours} = !!$bool;
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

sub get_colour_divergent {
    my ($self, $val, $min, $max) = @_;

    state $default_colour = Gtk3::Gdk::RGBA::parse('black');

    return $default_colour
        if ! (defined $max && defined $min);

    state $centre_colour = Gtk3::Gdk::RGBA::parse('#ffffbf');

    my $centre = 0;
    my $max_dist = max (abs($min), abs($max));

    return $centre_colour
        if $val == $centre || $max_dist == 0;

    my $colour;
    my @arr_cen = (0xff, 0xff, 0xbf);
    my @arr_hi  = (0x45, 0x75, 0xb4); # blue
    my @arr_lo  = (0xd7, 0x30, 0x27); # red

    if ($self->get_invert_colours) {
        @arr_lo  = (0x45, 0x75, 0xb4); # blue
        @arr_hi  = (0xd7, 0x30, 0x27); # red
    }

    $max_dist = abs $max_dist;
    my $pct = abs (($val - $centre) / $max_dist);

    if ($self->get_log_mode) {
        $pct = log (1 + 100 * $pct) / log (101);
    }

    #  handle out of range vals
    $pct = min (1, $pct);

    # interpolate between centre and extreme for each of R, G and B
    my @rgb
        = map {
        ($arr_cen[$_]
            + $pct
            * (($val < $centre ? $arr_hi[$_] : $arr_lo[$_]) - $arr_cen[$_])
        )} (0..2);

    $colour = Gtk3::Gdk::RGBA::parse(sprintf ('rgb(%d,%d,%d)', @rgb));
    return $colour;
}

sub get_colour_ratio {
    my ($self, $val, $min, $max) = @_;

    state $default_colour = Gtk3::Gdk::RGBA::parse('black');

    return $default_colour
        if ! (defined $min && defined $max);

    state $centre_colour = Gtk3::Gdk::RGBA::parse('#ffffbf');

    #  Perhaps should handle cases where min or max are zero,
    #  but those should not be passed anyway so an error is
    #  appropriate.
    my $extreme = exp (max (abs log $min, log $max));

    return $centre_colour
        if $val == 1 || $extreme == 1;

    # $min = 1 / $extreme;
    # $max = $extreme;

    #  simplify logic below
    if ($extreme < 1) {
        $extreme = 1 / $extreme;
    }

    my @arr_cen = (0xff, 0xff, 0xbf);
    my @arr_hi  = (0x45, 0x75, 0xb4); # blue
    my @arr_lo  = (0xd7, 0x30, 0x27); # red

    if ($self->get_invert_colours) {
        @arr_lo  = (0x45, 0x75, 0xb4); # blue
        @arr_hi  = (0xd7, 0x30, 0x27); # red
    }

    #  ensure fractions get correct scaling
    my $scaled = $val < 1 ? 1 / $val : $val;

    my $pct = abs (($scaled - 1) / abs ($extreme - 1));
    $pct = min ($pct, 1);  #  account for bounded ranges

    if ($self->get_log_mode) {
        $pct = log (1 + 100 * $pct) / log (101);
    }

    # interpolate between centre and extreme for each of R, G and B
    my @rgb
        = map {
        ($arr_cen[$_]
            + $pct
            * (($val < 1 ? $arr_hi[$_] : $arr_lo[$_]) - $arr_cen[$_])
        )} (0..2);

    return Gtk3::Gdk::RGBA::parse(sprintf ('rgb(%f,%f,%f)', @rgb));
}

#  get labels that are not constant,
#  e.g. from min and max or from categorical data
sub get_dynamic_labels {
    my ($self, %args) = @_;

    if ($self->get_categorical_mode) {
        \my %l_hash = $self->{categorical}{labels} // {};
        my @keys = sort {$a <=> $b} keys %l_hash;
        my @labels = @l_hash{@keys};
        return wantarray ? @labels : \@labels;
    }

    my @labels;
    my $stats = $self->get_stats // {};
    #  arbitrary defaults in case we are called before any stats are set
    my $max = $self->{last_max} // $stats->{MAX} // 2;
    my $min = $self->{last_min} // $stats->{MIN} // 1;
    if ($self->get_divergent_mode) {
        my $extent = max (abs($min), abs ($max));
        my $mid = 0;
        # my $mid2 = ($mid + $extent) / 2;
        @labels = (
            $mid - $extent,
            $mid - $extent / 2,
            $mid,
            $mid + $extent / 2,
            $mid + $extent
        );

        if ($self->get_log_mode) {
            my $pct = abs (($labels[-2] - $mid) / abs ($extent));
            $pct = log (1 + 100 * $pct) / log (101);
            # say "P2: $pct";
            $labels[-2] *= $pct;
            $pct = abs (($labels[1] - $mid) / abs ($extent));
            $pct = log (1 + 100 * $pct) / log (101);
            # say "P1: $pct";
            $labels[1] *= $pct;
        }
    }
    elsif ($self->get_ratio_mode) {
        my $max = exp (max (abs log $min, log $max)) // 1;
        my $mid = 1 + ($max - 1) / 2;

        @labels = (
            1 / $max,
            1 / $mid,
            1,
            $mid,
            $max
        );

        if ($self->get_log_mode) {
            my $pct = abs (($mid - 1) / abs ($max - 1));
            $pct = log (1 + 100 * $pct) / log (101);
            $labels[1]  = 1 / ($mid * $pct);
            $labels[-2] = $mid * $pct;
        }
    }
    else {
        #  basic variant for Hue, Sat and Grey
        my $n_labels = $args{n_labels} // 4;
        my $interval = ($max - $min) / ($n_labels - 1);
        if (!$self->get_log_mode) {
            for my $i (0 .. $n_labels - 2) {
                push @labels, $min + $i * $interval;
            }
        }
        else {
            #  should use a method for each transform
            #  (log and antilog)
            #  orig:
            #  $val = log (1 + 100 * ($val - $min) / ($max - $min)) / log (101);
            for my $i (0 .. $n_labels - 2) {
                my $log_step = log (101) * $i / ($n_labels - 1);
                push @labels, (exp($log_step) - 1) / 100 * ($max - $min) + $min;
            }
        }
        push @labels, $max;
    }

    #  labels are built "upside down", so correct for it here
    #  also set the precision
    @labels = reverse map {$self->format_number_for_legend($_)} @labels;

    #  Flag when data exceed legend range.
    #  Conditional because we do not always have stats,
    #  e.g. tree lists might only have min and max.
    if (keys %$stats) {
        if ($max < ($stats->{MAX} // $max)) {
            # $labels[0] = ">=$labels[0]";
            $labels[0] = "\x{2A7E}$labels[0]";
        }
        if ($min > ($stats->{MIN} // $min)) {
            # $labels[-1] = "<=$labels[-1]";
            $labels[-1] = "\x{2A7D}$labels[-1]";
        }
    }

    return wantarray ? @labels : \@labels;
}

sub format_number_for_legend {
    my ($self, $val) = @_;

    my $text = sprintf ('%.4f', $val); # round to 4 d.p.
    if ($text == 0) {
        $text = sprintf ('%.2e', $val);
    }
    if ($text == 0) {
        $text = 0;  #  make sure it is 0 and not 0.00e+000
    };
    return $text;
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

sub mode_is_continuous {
    my ($self) = @_;
    return $self->get_mode_as_string =~ /^(?:hue|sat|grey|ratio|divergent)/i;
}

sub set_stats {
    my ($self, $stats) = @_;
    $self->{current_index_stats} = $stats;
}

sub get_stats {
    $_[0]->{current_index_stats};
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

sub get_min_max {
    my ($self) = @_;
    my @minmax = ($self->{last_min}, $self->{last_max});
    return wantarray ? @minmax : \@minmax;
}

sub get_colour {
    my ($self, $val, $min, $max) = @_;

    state %colour_methods = (
        Hue  => 'get_colour_hue',
        Sat  => 'get_colour_saturation',
        Grey => 'get_colour_grey',
    );

    my $method = $colour_methods{$self->{legend_mode}};

    croak "Unknown colour system: $self->{legend_mode}\n"
        if !$method;

    #  slots need to be renamed
    $min //= $self->{last_min};
    $max //= $self->{last_max};

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

    return $self->$method($val, $min, $max);
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

sub set_log_mode {
    croak "boolean arg not passed"
        if @_ < 2;
    my ($self, $bool) = @_;

    return $self->{log_mode} = $bool ? 1 : 0;
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

sub get_colour_categorical {
    my ($self, $val) = @_;
    $val //= -1;  #  avoid undef key warnings
    my $colour_hash = $self->{categorical}{colours} //= {};
    my $colour = $colour_hash->{$val} || COLOUR_WHITE;
    #  should not need to do this
    if (!blessed $colour) {
        $colour = $colour_hash->{$val} = Gtk3::Gdk::RGBA::parse($colour);
    }
    return $colour;
}

sub get_colour_canape {
    my ($self, $val) = @_;
    $val //= -1;  #  avoid undef key warnings
    return $canape_colour_hash{$val} || COLOUR_WHITE;
}

#  colours from https://colorbrewer2.org/#type=diverging&scheme=RdYlBu&n=7
#  refactor as state var inside sub when we require a perl version that
#  supports state on lists (5.28)
my @zscore_colours
    = map {Gtk3::Gdk::RGBA::parse($_)}
    reverse ('#d73027', '#fc8d59', '#fee090', '#ffffbf', '#e0f3f8', '#91bfdb', '#4575b4');

sub get_colour_zscore {
    my ($self, $val) = @_;

    state $default_colour = Gtk3::Gdk::RGBA::parse('black');

    return $default_colour
        if not defined $val;

    #  returns -1 if not found, which will give us last item in @zscore_colours
    my $idx
        = firstidx {$val < 0 ? $val < $_ : $val <= $_}
        (-2.58, -1.96, -1.65, 1.65, 1.96, 2.58);

    if ($self->get_invert_colours) {
        $idx = $idx < 0 ? 0 : ($#zscore_colours - $idx);
    }

    return $zscore_colours[$idx];
}

#  same colours as the z-scores
sub get_colour_prank {
    my ($self, $val) = @_;

    state $default_colour = Gtk3::Gdk::RGBA::parse('black');

    return $default_colour
        if not defined $val;

    #  returns -1 if not found, which will give us last item in @zscore_colours
    my $idx
        = firstidx {$val < 0 ? $val < $_ : $val <= $_}
        (0.01, 0.025, 0.05, 0.95, 0.975, 0.99);

    if ($self->get_invert_colours) {
        $idx = $idx < 0 ? 0 : ($#zscore_colours - $idx);
    }

    return $zscore_colours[$idx];
}


sub get_colour_hue {
    my ($self, $val, $min, $max) = @_;
    # We use the following system:
    #   Linear interpolation between min...max
    #   HUE goes from 180 to 0 as val goes from min to max
    #   Saturation, Brightness are 1
    #
    state $default_colour = Gtk3::Gdk::RGBA::parse('black');
    my $hue;

    return $default_colour
        if ! defined $max || ! defined $min;

    if ($max != $min) {
        return $default_colour
            if ! defined $val;
        $hue = ($val - $min) / ($max - $min);
    }
    else {
        $hue = 0;
    }

    if ($self->get_invert_colours) {
        $hue = 1 - $hue;
    }

    $hue = 180 * min (1, max ($hue, 0));

    $hue = int(180 - $hue); # reverse 0..180 to 180..0 (this makes high values red)

    my ($r, $g, $b) = hsv_to_rgb($hue, 1, 1);

    return Gtk3::Gdk::RGBA::parse("rgb($r,$g,$b)");
}

sub get_colour_saturation {
    my ($self, $val, $min, $max) = @_;
    #   Linear interpolation between min...max
    #   SATURATION goes from 0 to 1 as val goes from min to max
    #   Hue is variable, Brightness 1
    state $default_colour = Gtk3::Gdk::RGBA::parse('black');

    return $default_colour
        if ! defined $val || ! defined $max || ! defined $min;

    my $sat;
    if ($max != $min) {
        $sat = ($val - $min) / ($max - $min);
    }
    else {
        $sat = 1;
    }
    $sat = min (1, max ($sat, 0));

    if ($self->get_invert_colours) {
        $sat = 1 - $sat;
    }

    my ($r, $g, $b) = hsv_to_rgb($self->{hue}, $sat, 1);

    return Gtk3::Gdk::RGBA::parse("rgb($r,$g,$b)");
}

sub get_colour_grey {
    my ($self, $val, $min, $max) = @_;

    state $default_colour = Gtk3::Gdk::RGBA::parse('black');

    return $default_colour
        if ! defined $val || ! defined $max || ! defined $min;

    my $sat;
    if ($max != $min) {
        $sat = ($val - $min) / ($max - $min);
    }
    else {
        $sat = 1;
    }

    if ($self->get_invert_colours) {
        $sat = 1 - $sat;
    }

    $sat *= 255;
    $sat = $self->rescale_grey($sat);  #  don't use all the shades
    # $sat *= 257;

    return Gtk3::Gdk::RGBA::parse("rgb($sat,$sat,$sat)");
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

#  a few factory methods
sub _make_nonbasic_methods {
    my ($pkg) = shift || __PACKAGE__;
    my @methods = _get_nonbasic_plot_modes();
    # print "Calling _make_access_methods for $pkg";
    no strict 'refs';
    foreach my $key (@methods) {
        my $method   = "get_${key}_mode";
        my $mode_key = "${key}_mode";
        # next if $pkg->can($method);  #  do not override
        *{"${pkg}::${method}"} =
            do {
                sub {
                    $_[0]->{$mode_key};
                };
            };
        $method = "set_${key}_mode_on";
        # say STDERR "==== Building $method in package $pkg";
        *{"${pkg}::${method}"} =
            do {
                sub {
                    my ($self) = @_;
                    my $prev_val = $self->{$mode_key};
                    $self->{$mode_key} = 1;
                    if (!$prev_val) {  #  update legend colours
                        $self->refresh_legend;
                    }
                    return 1;
                };
            };
        $method = "set_${key}_mode_off";
        # say STDERR "==== Building $method in package $pkg";
        *{"${pkg}::${method}"} =
            do {
                sub {
                    my ($self) = @_;
                    my $prev_val = $self->{$mode_key};
                    $self->{$mode_key} = 0;
                    $self->hide_current_marks;
                    if ($prev_val) {  #  give back our colours
                        $self->refresh_legend;
                    }
                    return 0;
                };
            };
        $method = "set_${key}_mode";
        my $mode_off_method = "set_${key}_mode_off";
        my $mode_on_method  = "set_${key}_mode_on";
        # say STDERR "==== Building $method in package $pkg";
        *{"${pkg}::${method}"} =
            do {
                sub {
                    my ($self, $bool) = @_;
                    my $method_name = $bool ? $mode_on_method : $mode_off_method;
                    $self->$method_name;
                    return $self->{$mode_key};
                };
            };
    }

    return;
}

_make_nonbasic_methods();


sub get_colour_for_undef {
    my $self = shift;
    my $colour_none = shift;

    return $self->{colour_none} // $self->set_colour_for_undef ($colour_none);
}

sub set_colour_for_undef {
    my ($self, $colour) = @_;

    $colour //= COLOUR_WHITE;

    croak "Colour argument must be a Gtk3::Gdk::RGBA or Gtk3::Gdk::Color object\n"
        if !($colour->isa('Gtk3::Gdk::Color') || $colour->isa('Gtk3::Gdk::RGBA'));

    return $self->{colour_none} = $colour;
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
