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


    # we were able to generate a mapping under the distance threshold,
    # now show them what it is and let them choose which parts to keep
    if ($success) {
        my %remap_results_response = %{$self->remap_results_dialog(%remap_results)};
        my $response = $remap_results_response{response};


        # now build the remap we actually want to perform
        # remove parts which aren't enabled
        if(!$remap_results_response{punct_match_enabled}) {
            my @punct_matches = @{$remap_results{punct_matches}};
            foreach my $key (@punct_matches) {
                delete $remap{$key};
                say "RemapGUI: deleted $key because it was punct matched";
            }
        }

        # TODO we could probably remove exact matches and not matches here as well
            
        if ( $response eq 'yes' ) {
            $guesser->perform_auto_remap(
                remap => \%remap,
                new_source => $new_source,
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


# called internally by perform_remap
sub remap_results_dialog {
    my ($self, %args) = @_;
    my %remap = %{$args{remap}};

    
    ###
    # Exact matches
    my $exact_match_str = "";
    my @exact_matches = @{$args{exact_matches}};
    foreach my $match (@exact_matches) {
        $exact_match_str .= "$match\n";
    }

    my $exact_match_count = @exact_matches;

    
    my $exact_match_label = Gtk2::Label->new("$exact_match_count Exact Matches:");
    
    my $exact_match_buffer = Gtk2::TextBuffer->new();
    $exact_match_buffer->set_text($exact_match_str);
    my $exact_match_textview = Gtk2::TextView->new_with_buffer($exact_match_buffer);

    # if you set this to true, they can edit the textbox; could be
    # useful in the future for allowing full custom remapping here
    $exact_match_textview->set_editable(0);
    
    my $exact_match_scroll = Gtk2::ScrolledWindow->new(undef, undef);
    $exact_match_scroll->set_size_request(300, 100);
    $exact_match_scroll->add($exact_match_textview);



    ###
    # Punctuation matches
    my $punct_match_str = "";
    my @punct_matches = @{$args{punct_matches}};
    foreach my $match (@punct_matches) {
        $punct_match_str .= "$match -> $remap{$match}\n";
    }

    my $punct_match_count = @punct_matches;

    
    my $punct_match_label = Gtk2::Label->new("$punct_match_count Punct Matches:");
    
    my $punct_match_buffer = Gtk2::TextBuffer->new();
    $punct_match_buffer->set_text($punct_match_str);
    my $punct_match_textview = Gtk2::TextView->new_with_buffer($punct_match_buffer);

    # if you set this to true, they can edit the textbox; could be
    # useful in the future for allowing full custom remapping here
    $punct_match_textview->set_editable(0);
    
    my $punct_match_scroll = Gtk2::ScrolledWindow->new(undef, undef);
    $punct_match_scroll->set_size_request(300, 100);
    $punct_match_scroll->add($punct_match_textview);

    my $punct_match_checkbutton = Gtk2::CheckButton->new("Enable");
    $punct_match_checkbutton->set_active(1);
    $punct_match_checkbutton->signal_connect(toggled => sub {
        $punct_match_textview->set_sensitive(!$punct_match_textview->get_sensitive);
        $punct_match_label->set_sensitive(!$punct_match_label->get_sensitive);
    });




    ###
    # Not matched
    my $not_matched_str = "";
    my @not_matched = @{$args{not_matched}};
    foreach my $match (@not_matched) {
        $not_matched_str .= "$match\n";
    }

    my $not_matched_count = @not_matched;

    
    my $not_matched_label = Gtk2::Label->new("$not_matched_count Labels Not Matched:");
    
    my $not_matched_buffer = Gtk2::TextBuffer->new();
    $not_matched_buffer->set_text($not_matched_str);
    my $not_matched_textview = Gtk2::TextView->new_with_buffer($not_matched_buffer);

    # if you set this to true, they can edit the textbox; could be
    # useful in the future for allowing full custom remapping here
    $not_matched_textview->set_editable(0);
    
    my $not_matched_scroll = Gtk2::ScrolledWindow->new(undef, undef);
    $not_matched_scroll->set_size_request(300, 100);
    $not_matched_scroll->add($not_matched_textview);



    ###
    # Accept label
    my $accept_remap_label = Gtk2::Label->new("Perform this remapping?");

    
    
    ####
    # The dialog itself
    my $dlg = Gtk2::Dialog->new_with_buttons( 'Remap results',
        undef, 'modal', 'gtk-yes' => 'yes', 'gtk-no' => 'no');

    ####
    # Pack everything in
    my $vbox = $dlg->get_content_area;
    
    $vbox->pack_start( $exact_match_label, 0, 1, 0 );
    $vbox->pack_start( $exact_match_scroll, 0, 1, 0 );

    $vbox->pack_start( $punct_match_label, 0, 1, 0 );
    $vbox->pack_start( $punct_match_checkbutton, 0, 1, 0);
    $vbox->pack_start( $punct_match_scroll, 0, 1, 0 );


    
    $vbox->pack_start( $not_matched_label, 0, 1, 0 );
    $vbox->pack_start( $not_matched_scroll, 0, 1, 0 );

    $vbox->pack_start( $accept_remap_label, 10, 1, 10);

    
    $dlg->show_all;

    my $response = $dlg->run();
    my $punct_match_enabled = $punct_match_checkbutton->get_active;

    
    $dlg->destroy();

    my %results = (
        response => $response,
        punct_match_enabled => $punct_match_enabled,
        );
    
    return wantarray ? %results : \%results;

}




