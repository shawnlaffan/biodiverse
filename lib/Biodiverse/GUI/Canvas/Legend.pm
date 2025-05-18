package Biodiverse::GUI::Canvas::Legend;
use strict;
use warnings;
use 5.036;

use Carp qw /croak/;

use parent qw /Biodiverse::GUI::Canvas Biodiverse::GUI::Legend/;

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


#  refactor as state var inside a sub
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
    };
    bless $self, $class;
    # Get the width and height of the canvas.
    #my ($width, $height) = $self->{canvas}->c2w($width_px || 0, $height_px || 0);
    my $draw_size = $self->{drawable}->get_allocation();
    my ($width, $height) = ($draw_size->{width}, $draw_size->{height});

    # Create the legend rectangle.
    $self->{legend} = $self->make_rect();

    #  reverse might not be needed but ensures the array is the correct size from the start
    foreach my $i (reverse 0..3) {
        $self->{marks}{default}[$i] = $self->make_mark($self->{legend_marks}[$i]);
    }
    $self->{marks}{current} = $self->{marks}{default};

    return $self;
};

sub hide {
    $_[0]{show} = 0;
}

sub show {
    $_[0]{show} = 1;
}

sub get_width {
    return 1;

    my $self = shift;
    return $self->{back_rect_width} // LEGEND_WIDTH;
}

sub get_height {
    return 1;

    my $self = shift;
    return $self->{back_rect_height} // LEGEND_HEIGHT;
}

sub make_rect {
    my $self = shift;
    my ($width, $height);

    # Create and colour the legend according to the colouring
    # scheme specified by $self->{legend_mode}. Each colour
    # mode has a different range as specified by $height.
    # Once the legend is create it is scaled to the height
    # of the canvas in reposition and according to each
    # mode's scaling factor held in $self->{legend_scaling_factor}.

    warn 'Legend: Remember to re-enable add_row';

    if ($self->get_canape_mode) {

        ($width, $height) = ($self->get_width, 255);
        $self->{legend_height} = $height;

        my $n = (scalar keys %canape_colour_hash) - 1;
        foreach my $row (0..($height - 1)) {
            my $class = $n - int (0.5 + $n * $row / ($height - 1));
            my $colour = $self->get_colour_canape ($class);
            # $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->get_categorical_mode) {
        ($width, $height) = ($self->get_width, 255);
        $self->{legend_height} = $height;
        my $label_hash = $self->{categorical}{labels};

        my $n = (scalar keys %$label_hash) - 1;
        my @classes = sort {$a <=> $b} keys %$label_hash;
        $n = $#classes;
        foreach my $row (0..($height - 1)) {
            #  cat 0 at the top
            my $class_iter = $n - int (0.5 + $n * $row / ($height - 1));
            my $colour = $self->get_colour_categorical ($classes[$class_iter]);
            # $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->get_zscore_mode) {

        ($width, $height) = ($self->get_width, 255);
        $self->{legend_height} = $height;
        my @dummy_zvals = reverse (-2.6, -2, -1.7, 0, 1.7, 2, 2.6);

        foreach my $row (0..($height - 1)) {
            #  a clunky means of aligning the colours with the labels
            my $scaled =  $row / $height;
            if ($scaled > 0.5) {
                $scaled -= 0.05
            }
            elsif ($scaled < 0.5) {
                $scaled += 0.05
            }
            $scaled = min ($#dummy_zvals, max (0, $scaled));
            my $class = int (@dummy_zvals * $scaled);
            my $colour = $self->get_colour_zscore ($dummy_zvals[$class]);
            # $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->get_prank_mode) {
        #  cargo culted from above - need to refactor
        ($width, $height) = ($self->get_width, 255);
        $self->{legend_height} = $height;
        my @dummy_vals = reverse (0.001, 0.02, 0.04, 0.5, 0.951, 0.978, 0.991);

        foreach my $row (0..($height - 1)) {
            #  a clunky means of aligning the colours with the labels
            my $scaled =  $row / $height;
            if ($scaled > 0.5) {
                $scaled -= 0.05
            }
            elsif ($scaled < 0.5) {
                $scaled += 0.05
            }
            $scaled = min ($#dummy_vals, max (0, $scaled));
            my $class = int (@dummy_vals * $scaled);
            my $colour = $self->get_colour_prank ($dummy_vals[$class]);
            # $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->get_ratio_mode) {
        ($width, $height) = ($self->get_width, 180);
        $self->{legend_height} = $height;

        local $self->{log_mode} = 0; # hacky override

        my $mid = ($height - 1) / 2;
        foreach my $row (reverse 0..($height - 1)) {
            my $val = $row < $mid ? 1 / ($mid - $row) : $row - $mid;
            #  invert again so colours match legend text
            my $colour = $self->get_colour_ratio (1/$val, 1/$mid, $mid);
            # $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->get_divergent_mode) {
        ($width, $height) = ($self->get_width, 180);
        $self->{legend_height} = $height;

        local $self->{log_mode} = 0; # hacky override

        my $centre = ($height - 1) / 2;
        my $extreme = $height - $centre;

        #  ensure colours match plot since 0 is the top
        foreach my $row (reverse 0..($height - 1)) {
            my $colour = $self->get_colour_divergent ($centre - $row, -$extreme, $extreme);
            # $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->{legend_mode} eq 'Hue') {

        ($width, $height) = ($self->get_width, 180);
        $self->{legend_height} = $height;

        local $self->{log_mode} = 0; # hacky override

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_hue ($height - $row, 0, $height-1);
            # $self->add_row($self->{legend_colours_group}, $row, $colour);
        }

    }
    elsif ($self->{legend_mode} eq 'Sat') {

        ($width, $height) = ($self->get_width, 100);
        $self->{legend_height} = $height;

        local $self->{log_mode} = 0; # hacky override

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_saturation ($height - $row, 0, $height-1);
            # $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->{legend_mode} eq 'Grey') {

        ($width, $height) = ($self->get_width, 255);
        $self->{legend_height} = $height;

        local $self->{log_mode} = 0; # hacky override

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_grey ($height - $row, 0, $height-1);
            # $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    else {
        croak "Legend: Invalid colour system $self->{legend_mode}\n";
    }

    return;
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
