package Biodiverse::GUI::GraphPopup;

use strict;
use warnings;
use 5.010;

use Data::Dumper;
use Carp;
use Gnome2::Canvas;

use Gtk2;

our $VERSION = '1.99_006';

use English qw { -no_match_vars };

use Biodiverse::GUI::PopupObject;
use Biodiverse::GUI::CanvasGraph;

use constant COLOUR_RED         => Gtk2::Gdk::Color->new(255*257, 0, 0);
use constant COLOUR_LILAC       => Gtk2::Gdk::Color->new(200, 200, 255);

sub add_graph {
    my $popup = shift;
    my $output_ref = shift;
    my $list_name = shift;
    my $element = shift;
    my $popupobj = shift;
    my $max = shift;
    my $min = shift;

    my $list_ref = $output_ref->get_list_ref (
        element => $element,
        list    => $list_name,
        );

    my $canvas = $popup->get_canvas;
    my $canvasobj = $popupobj->get_canvas;


    if ($canvasobj) {
       $canvas = $canvasobj;
    }

    my $background = $popup->get_background;

    if ( ! $background ){
        $background = Biodiverse::GUI::CanvasGraph->new(
            canvas   => $canvas,
            popupobj => $popupobj
        );
    }

    my $primary = $background->get_primary;
    if ($primary) {
        $primary->destroy();
    }

    $background->add_primary_layer(
        graph_values => $list_ref,
        point_colour => COLOUR_LILAC,
        canvas       => $canvas,
        y_max          => $max,
        y_min          => $min
    );

    $popup->set_background($background);
    $popup->set_secondary($background->get_secondary);
    $popup->set_list_ref($list_ref);


    $canvas->show();

    return;
}

sub add_secondary {
    my $self = shift;
    my $output_ref = shift;
    my $list_name = shift;
    my $element = shift;
    my $popupobj = shift;
    my $max = shift;
    my $min = shift;

    my $secondary_element = $popupobj->get_secondary_element;
    no warnings qw(uninitialized);
    return if $element eq $secondary_element;

    my $list_ref = $output_ref->get_list_ref (
        element => $element,
        list    => $list_name,
        );


    my $background = $popupobj->get_background;
    my $canvas = $popupobj->get_canvas;
    my $secondary;

    #my $point_colour = Gtk2::Gdk::Color->new(255*257, 0, 0);
    #my $point_colour = Gtk2::Gdk::Color->parse('#7F7F7F');
    my $point_colour = 'red';

    # call graph update here if it exists.
    my $primary = $background->get_primary;
    $secondary = $background->get_secondary;

    if ($primary) {
        $secondary = $background->add_secondary_layer (
            graph_values => $list_ref,
            point_colour => $point_colour,
            canvas       => $canvas,
            y_max          => $max,
            y_min          => $min
        );
        $secondary->raise_to_top();
        $secondary->show();
        $popupobj->set_secondary($secondary);
        $popupobj->set_secondary_element($element);
    }
}
