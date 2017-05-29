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

sub add_graph {
    my $popup = shift;
    my $output_ref = shift;
    my $list_name = shift;
    my $element = shift;
    my $popupobj = shift;

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
            canvas => $canvas
        );
    }

    my $primary = $background->get_primary;
    if ($primary) {
        $primary->destroy();
    }

    $background->add_primary_layer(
        graph_values => $list_ref,
        canvas => $canvas
    );
    $popup->set_background($background);
    $popup->set_secondary($background->get_secondary);
    #$popup->set_graphpopup($popup);
    $popup->set_list_ref($list_ref);


    $canvas->show();
    #$popup->set_canvas($canvas);

    return;
}

sub add_secondary {
    my $self = shift;
    my $output_ref = shift;
    my $list_name = shift;
    my $element = shift;
    my $popupobj = shift;

    my $list_ref = $output_ref->get_list_ref (
        element => $element,
        list    => $list_name,
        );

    my $background = $popupobj->get_background;
    my $canvas = $popupobj->get_canvas;
    #my $list_ref = $self->{popup}->get_list_ref;
    my $secondary;

    say "[add_secondary]";

    # call graph update here if it exists.
    if ($background) {
        say "[add_secondary_plot_to_popup_graph] \$background: $background";
        say "[add_secondary_plot_to_popup_graph] \$canvas: $canvas";
        say "[add_secondary_plot_to_popup_graph] \$list_ref: $list_ref";
        $secondary = $background->add_secondary_layer (
            graph_values => $list_ref,
            canvas => $canvas
        );
    }
    $secondary->raise_to_top();
    $secondary->show();
    $popupobj->set_secondary($secondary);
}
