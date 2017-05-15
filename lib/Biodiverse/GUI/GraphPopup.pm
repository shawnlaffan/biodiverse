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

    $background->add_point_layer(
        graph_values => $list_ref,
        canvas => $canvas
    );

    $popup->set_background($background);

    $canvas->show();
    #$popup->set_canvas($canvas);

    return;
}
