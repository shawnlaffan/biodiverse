package Biodiverse::GUI::PopupObject;

use strict;
use warnings;
use 5.010;

our $VERSION = '1.99_007';

use Gtk2;

##########################################################
# Small object for the popup dialog. Passed to sources for
# them to put their data onto the list
##########################################################

sub set_value_column {
    my $popup = shift;
    my $col = shift;
    my $list = $popup->{list};

    $list->{colValue}->clear_attributes($list->{valueRenderer}); #!!! This (bug?) cost me a lot of time
    $list->{colValue}->set_attributes($list->{valueRenderer}, text => $col) if $col;
    $popup->{value_column} = $col;
}

sub set_list_model {
    my $popup = shift;
    my $model = shift;
    $popup->{list}->set_model($model);
}

# for the graph popup
sub set_canvas {
    my $self = shift;
    my $canvas = shift;

    $self->{canvas} = $canvas;
}

# return the canvas
sub get_canvas {
    my $self = shift;
    my $popup = shift;

    return $self->{canvas};
}

# Store the backgound rectangle
sub set_background {
    my $self = shift;
    my $background = shift;

    $self->{background} = $background;
}

# return the background rectangle
sub get_background {
    my $self = shift;
    return $self->{background};
}

# Store the secondary plot group
sub set_secondary {
    my $self = shift;
    my $secondary = shift;

    $self->{secondary} = $secondary;
}

# return the secondary plot group
sub get_secondary {
    my $self = shift;
    return $self->{secondary};
}

# Store the graph popup
sub set_graphpopup {
    my $self = shift;
    my $graphpopup = shift;

    $self->{graphpopup} = $graphpopup;
}

# return the graph popup
sub get_graphpopup {
    my $self = shift;
    return $self->{graphpopup};
}

# Store the list ref
sub set_list_ref {
    my $self = shift;
    my $list_ref = shift;

    $self->{list_ref} = $list_ref;
}

# return the list ref
sub get_list_ref {
    my $self = shift;
    return $self->{list_ref};
}

# remove the secondary layer
sub clear_secondary {
    my $self = shift;
    my $secondary = shift;
    if ($secondary) {
        say "[clear_secondary] destroy \$secondary: $secondary";
        $secondary->destroy();
    }
}

1;

