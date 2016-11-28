package Biodiverse::GUI::AutoRemapGUI;

use 5.010;
use strict;
use warnings;
use Gtk2;
use Biodiverse::RemapGuesser qw/guess_remap/;
use English( -no_match_vars);

our $VERSION = '1.99_006';

use Biodiverse::GUI::GUIManager;



sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}



sub remap_dlg {
    my $self = shift;
    my $args = shift || {};
    my $DLG_NAME = "dlgAutoRemap";

    my $text = q{};
    if (defined $args->{header}) {
        #print "mode1\n";
        $text .= '<b>'
                . Glib::Markup::escape_text ($args->{header})
                . '</b>';
    }
    if (defined $args->{text}) {
        $text .= Glib::Markup::escape_text(
            $args->{text}
        );
    }

    my $gui = Biodiverse::GUI::GUIManager->instance;

    my $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file($gui->get_gtk_ui_file('dlgAutoRemap.ui'));
    my $dlg = $dlgxml->get_object($DLG_NAME);

    # Put it on top of main window
    $dlg->set_transient_for($gui->get_object('wndMain'));

    # set the text
    my $label = $dlgxml->get_object('lblText');

    
    $label->set_text("Remap labels?");
    $dlg->set_title ("Remap labels?");


    # Show the dialog
    my $response = $dlg->run();
    $dlg->destroy();

    $response = 'cancel' if $response eq 'delete-event';
    if (not ($response eq 'yes' or $response eq 'no' or $response eq 'cancel')) {
        die "not yes/no/cancel: $response";
    }

    my $auto = $dlgxml->get_object("chkAuto")->get_active();
   

    my %results = (
        response => $response,
        auto_remap => $auto,
        );
    
    return wantarray ? %results : \%results;

}



# given an array reference to a list of data source names (e.g. tree
# names, basedata names etc.), allows the user to select one and
# returns the index of the item selected (needs to be index to avoid
# name clashes)
sub run_select_autoremap_target {
    my $self = shift;
    my $args = shift || {};

    my @options = @{$args->{'options'}};
    
    my $combo = Gtk2::ComboBox->new_text;
    
    foreach my $option (@options) {
        $combo->append_text ($option);
    }

    $combo->set_active(0);
    $combo->show_all;
    $combo->set_tooltip_text ('Choose a data source to remap the labels to.');

    my $label = Gtk2::Label->new ('Choose a data source to remap the labels to:');

    my $dlg = Gtk2::Dialog->new_with_buttons (
        'Select Data Source',
        undef,
        'modal',
        'gtk-ok'     => 'ok',
    );


    my $labelTheSecond = Gtk2::Label->new ('Maximum acceptable distance:');

    my $adjustment = Gtk2::Adjustment->new(2, 0, 20, 1, 10, 0);
    my $spinner = Gtk2::SpinButton->new($adjustment, 1, 0);

    my $vbox = $dlg->get_content_area;
    
    my $hbox = Gtk2::HBox->new();
    $hbox->pack_start ($label, 0, 1, 0);
    $hbox->pack_start($combo, 0, 1, 10);
    $vbox->pack_start($hbox, 0, 0, 0);

    
    $hbox = Gtk2::HBox->new();
    $hbox->pack_start($labelTheSecond, 0, 1, 0);
    $hbox->pack_start($spinner, 0,1, 10);
    $vbox->pack_start($hbox, 0, 0, 0);    
    
    $dlg->show_all;

    my $response = $dlg->run();
    $dlg->destroy();



    my $max_distance = $spinner->get_value_as_int();;
    say "max_distance was $max_distance (from the spinner)";

    my %results = (
        selection => $combo->get_active,
        max_distance => $max_distance,
        );
    
    
    return wantarray ? %results : \%results;
}




sub run_autoremap_gui {
    my $self = shift;
    my %args = @_;

    my $gui = $args{"gui"};
    
    my $tree = $args{"data_source"};
    my @sources = ();
    push @sources, @{$gui->get_project()->get_base_data_list()};
    push @sources, @{$gui->get_project()->get_phylogeny_list()};
    push @sources, @{$gui->get_project()->get_matrix_list()};

    my @names;
    foreach my $source (@sources) {
        push @names, $source->get_param('NAME');
    }

    # select what data source they want to remap to
    my %selection_results = %{$self->run_select_autoremap_target({options => \@names})}; 

    my $choice = $sources[$selection_results{selection}];
    my $max_distance = $selection_results{max_distance};
    


    # actually do the remap
    my $guesser = Biodiverse::RemapGuesser->new();
    my %remap_results = $guesser->generate_auto_remap({
        "existing_data_source" => $choice,
            "new_data_source" => $tree,
            "max_distance" => $max_distance,
                                                      });
    my %remap = %{$remap_results{remap}};
    my $success = $remap_results{success};


    if($success) {
        # debug output and user message
        my $remap_text = "\n\n";
        say "[Phylogeny Import] Generated the following guessed remap:";
        
        # 5 is an arbitrary constant, seems enough to get a sense for the mapping.
        # is there a place where we put constant/configuration values?
        my $how_many_remaps_to_show_as_sample = 5;
        my $count = 0;
        foreach my $r (sort keys %remap) {
            $remap_text .= "$r -> $remap{$r}\n";
            say "$r -> $remap{$r}";
            last if ++$count >= $how_many_remaps_to_show_as_sample;
        }
        
        say "etc.";
        $remap_text .= "etc.\n\n";
        $remap_text .= "Accept this label remap?";
        
        my $accept_remap_dlg_response = Biodiverse::GUI::YesNoCancel->run({
            header      => 'Sample of automatically generated remap',
            text        => $remap_text,
            hide_cancel => 1,
                                                                          });

        if($accept_remap_dlg_response eq 'yes') {
            $guesser->perform_auto_remap({
                "remap_hash" => \%remap,
                    "data_source" => $tree,
                                         });
            
            say "Performed automatic remap.";
        }
        else {
            say "Declined automatic remap, no remap performed.";
        }
    }
    # we couldn't find a match that stayed under their max distance
    else {
        say "Remap failed with distance $max_distance.";

        my $failed_remap_response = Biodiverse::GUI::YesNoCancel->run({
            title       => 'Auto Remap Failed', 
            text        => "\nCouldn't generate a remap with max distance under $max_distance",
            hide_cancel => 1,
            yes_is_ok => 1,
            hide_no => 1,
           });



    }
}




