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

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::PopupObject;


sub add_graph {
    my $popup = shift;
    my $node_ref = shift;
    
    my $list_name = shift;
    say "Adding a graph to the popup for list $list_name";

    my $list_ref = $node_ref->get_list_ref(list => $list_name);

    my $canvas = $popup->{canvas};

    $canvas->set_label("Reset label for $list_name!");
    $canvas->show();
    
    $popup->set_canvas($canvas);

    
    return;
}
