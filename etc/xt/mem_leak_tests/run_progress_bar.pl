use strict;
use warnings;
use lib '../../lib';

use Cwd;
use FindBin qw ( $Bin );

use English qw /-no_match_vars/;

use 5.010;

local $| = 1;

#  load up the user defined libs and settings
use Biodiverse::Config;

#  load Gtk
use Gtk3 qw/-init/;

use Gtk3::GladeXML;

use Biodiverse::GUI::ProgressDialog;

do {
    my $gladefile = get_gladefile();
    my $gladexml = eval {
        Gtk3::GladeXML->new( $gladefile, 'wndMain' );
    };
    croak $EVAL_ERROR if $EVAL_ERROR;
    $gladexml->signal_autoconnect_from_package('Biodiverse::GUI::Callbacks');
    
    # Initialise the GUI Manager object
    my $gui = Biodiverse::GUI::GUIManager->instance;
    $gui->set_glade_xml($gladexml);
    $gui->set_glade_file($gladefile);
    
    # Go!
    #Gtk3->main;
    
    my $max_iters = 10**7;
    $max_iters = 10;

    my $pbar_count = 500;
    
    for my $pp (1 .. $pbar_count) {
        my $progress = Biodiverse::GUI::ProgressDialog->new;
        for my $i (1 .. $max_iters) {
            my $text = '<b> text: </b>' . $i;
            $progress->update ($text, $i / $max_iters);
        }
        $progress->destroy;
        $progress = undef;
    }
    
    #$gui->destroy;
};

sub get_gladefile {
    my $gladefile = Path::Class::file( $Bin, '../../bin', 'glade', 'biodiverse.glade' )->stringify;
    return $gladefile;
};
