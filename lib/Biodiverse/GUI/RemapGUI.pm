package Biodiverse::GUI::RemapGUI;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.99_006';

use Gtk2;
use Biodiverse::RemapGuesser qw/guess_remap/;
use English( -no_match_vars );

use Biodiverse::GUI::GUIManager;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

sub run_remap_gui {
    my $self = shift;
    my %args = @_;

    my $gui = $args{"gui"};

    ####
    # get the available options to remap labels to
    # TODO don't allow remapping to yourself (doesn't hurt but just confuses things)
    my @sources = ();
    push @sources, @{ $gui->get_project()->get_base_data_list() };
    push @sources, @{ $gui->get_project()->get_phylogeny_list() };
    push @sources, @{ $gui->get_project()->get_matrix_list() };
    
    my @source_names;
    foreach my $source (@sources) {
        push @source_names, $source->get_param('NAME');
    }


    
    
    ####
    # The data source selection combo box and its label
    my $data_source_combo = Gtk2::ComboBox->new_text;
    foreach my $option (@source_names) {
        $data_source_combo->append_text($option);
    }
    $data_source_combo->set_active(0);
    $data_source_combo->show_all;
    $data_source_combo->set_tooltip_text('Choose a data source to remap the labels to.');
    $data_source_combo->set_sensitive(0);
    my $data_source_label =
      Gtk2::Label->new('Choose a data source to remap the labels to:');
    $data_source_label->set_sensitive(0);

    
    ####
    # The max_distance spinbutton and its label
    my $adjustment = Gtk2::Adjustment->new( 2, 0, 20, 1, 10, 0 );
    my $spinner = Gtk2::SpinButton->new( $adjustment, 1, 0 );
    $spinner->set_sensitive(0);
    my $max_distance_label = Gtk2::Label->new('Maximum acceptable distance:');
    $max_distance_label->set_sensitive(0);



    ####
    # The auto/manual checkbutton
    my $auto_checkbutton = Gtk2::CheckButton->new("Automatic remap");
    $auto_checkbutton->set_active(0);
    $auto_checkbutton->signal_connect(toggled => sub {
            $data_source_combo->set_sensitive(!$data_source_combo->get_sensitive);
            $spinner->set_sensitive(!$spinner->get_sensitive);
            $max_distance_label->set_sensitive(!$max_distance_label->get_sensitive);
            $data_source_label->set_sensitive(!$data_source_label->get_sensitive);

    });




    
    ####
    # The dialog itself
    my $dlg = Gtk2::Dialog->new_with_buttons( 'Remap labels?',
        undef, 'modal', 'gtk-yes' => 'yes', 'gtk-no' => 'no');


    ####
    # Pack everything in
    my $vbox = $dlg->get_content_area;

    my $hbox = Gtk2::HBox->new();
    $hbox->pack_start( $auto_checkbutton, 0, 1, 0 );
    $vbox->pack_start( $hbox,  0, 0, 0 );

    $hbox = Gtk2::HBox->new();    
    $hbox->pack_start( $data_source_label, 0, 1, 0 );
    $hbox->pack_start( $data_source_combo, 0, 1, 10 );
    $vbox->pack_start( $hbox,  0, 0, 0 );

    $hbox = Gtk2::HBox->new();
    $hbox->pack_start( $max_distance_label, 0, 1, 0 );
    $hbox->pack_start( $spinner,        0, 1, 10 );
    $vbox->pack_start( $hbox,           0, 0, 0 );


    
    $dlg->show_all;

    my $response = $dlg->run();

    my $remap_type;
    if($response eq "no") {
        $remap_type = "none";
    }
    elsif($response eq "yes") {
        # check the state of the checkbox
        if($auto_checkbutton->get_active()) {
            $remap_type = "auto";
        }
        else {
            $remap_type = "manual";
        }
    }
    else {
        say "[RemapGUI] Unknown dialog response: $response";        
    }

    
    $dlg->destroy();

    my $max_distance = $spinner->get_value_as_int();
    say "max_distance was $max_distance (from the spinner)";

    
    my $choice       = $sources[$data_source_combo->get_active];    
    
    

    my %results = (
        remap_type => $remap_type,
        datasource_choice => $choice,
        max_distance => $max_distance,
        );

    return wantarray ? %results : \%results;
}





# given a gui and a data source, perform an automatic remap
sub perform_remap {
    my $self = shift;
    my %args = @_;

    my $new_source    = $args{"new_source"};
    my $old_source    = $args{"old_source"};
    my $max_distance  = $args{"max_distance"};

    # actually do the remap
    my $guesser       = Biodiverse::RemapGuesser->new();
    my %remap_results = $guesser->generate_auto_remap(
        {
            "existing_data_source" => $old_source,
            "new_data_source"      => $new_source,
            "max_distance"         => $max_distance,
        }
    );
    
    my %remap       = %{ $remap_results{remap} };
    my $success     = $remap_results{success};
    my $statsString = $remap_results{stats};

    if ($success) {

        # debug output and user message
        my $remap_text = "\n\n";

        $remap_text .= $statsString;

        $remap_text .= "Accept this label remap?";

        my $accept_remap_dlg_response = Biodiverse::GUI::YesNoCancel->run(
            {
                header      => 'Sample of automatically generated remap',
                text        => $remap_text,
                hide_cancel => 1,
            }
        );

        if ( $accept_remap_dlg_response eq 'yes' ) {
            $guesser->perform_auto_remap(
                {
                    "remap_hash"  => \%remap,
                    "data_source" => $new_source,
                }
            );

            say "Performed automatic remap.";
        }
        else {
            say "Declined automatic remap, no remap performed.";
        }
    }

    # we couldn't find a match that stayed under their max distance
    else {
        say "Remap failed with distance $max_distance.";

        my $failed_remap_response = Biodiverse::GUI::YesNoCancel->run(
            {
                title => 'Auto Remap Failed',
                text =>
"\nCouldn't generate a remap with max distance under $max_distance",
                hide_cancel => 1,
                yes_is_ok   => 1,
                hide_no     => 1,
            }
        );

    }
}




