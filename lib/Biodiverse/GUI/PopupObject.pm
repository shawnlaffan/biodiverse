package Biodiverse::GUI::PopupObject;

use strict;
use warnings;
use 5.010;

our $VERSION = '2.00';

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

sub set_canvas {
    my $popup = shift;
    my $canvas = shift;

    # for the graph popups
    $popup->{canvas} = $canvas;
}

1;

