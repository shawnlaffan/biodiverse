package Biodiverse::GUI::AutoRemapGUI;

use 5.010;
use strict;
use warnings;
use Gtk2;
use Biodiverse::RemapGuesser qw/guess_remap/;


our $VERSION = '1.99_006';

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
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
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
    );

    my $vbox = $dlg->get_content_area;
    $vbox->pack_start ($label, 0, 0, 0);
    $vbox->pack_start($combo, 0, 0, 0);

    $dlg->show_all;

    my $response = $dlg->run();
    $dlg->destroy();

    return if lc($response) ne 'ok';

    return $combo->get_active;
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
    my $choice = $sources[$self->run_select_autoremap_target({options => \@names})];
    
    
    my $guesser = Biodiverse::RemapGuesser->new();
    my %remap_results = $guesser->generate_auto_remap({
        "existing_data_source" => $choice,
            "new_data_source" => $tree,
                                                      });
    my %remap = %{$remap_results{remap}};
    

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




