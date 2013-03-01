package Biodiverse::GUI::OpenDialog;

#
# A FileChooserWidget but with a name field
#

use strict;
use warnings;
use File::Basename;
use Gtk2;
use Gtk2::GladeXML;

our $VERSION = '0.18_004';

use Biodiverse::GUI::GUIManager;

# Show the dialog. Params:
#   title
#   suffixes to use in the filter (OPTIONAL)
#     - can be array refs to let users choose a few types at once,
#       eg: ["csv", "txt"], "csv", "txt"
sub Run {
    my $title = shift;
    my @suffixes = @_;
    
    my $gui = Biodiverse::GUI::GUIManager->instance;

    # Load the widgets from Glade's XML
    my $dlgxml = Gtk2::GladeXML->new($gui->getGladeFile, 'dlgOpenWithName');
    my $dlg = $dlgxml->get_widget('dlgOpenWithName');
    $dlg->set_transient_for( $gui->getWidget('wndMain') );
    $dlg->set_title($title);

    # Connect file selected event - to automatically update name based on filename
    $dlgxml->get_widget('filechooser') -> signal_connect('selection-changed' => \&onFileSelection, $dlgxml);

    # Add filters
    foreach my $suffix (@suffixes) {
    
        my $filter = Gtk2::FileFilter->new();
        if ((ref $suffix) =~ /ARRAY/) {
            foreach my $suff (@$suffix) {
                $filter->add_pattern("*.$suff");
            }
            $filter->set_name(join (" and ", @$suffix) . " files");
        }
        else {
            $filter->add_pattern("*.$suffix");
            $filter->set_name("$suffix files");
        }

        $dlgxml->get_widget('filechooser') -> add_filter($filter);

    }

    # Show the dialog
    $dlg->set_modal(1);
    my $response = $dlg->run();

    my ($name, $filename);
    if ($response eq "ok") {
        # Save settings
        $name = $dlgxml->get_widget('txtName')->get_text();
        $filename = $dlgxml->get_widget('filechooser')->get_filename();
    }

    $dlg->destroy();
    return ($name, $filename);
}


# Automatically update name based on filename
sub onFileSelection {
    my $chooser = shift;
    my $dlgxml = shift;

    my $filename = $chooser->get_filename();
    if ($filename && -f $filename) {
    
        my($name, $dir, $suffix) = fileparse($filename, qr/\.[^.]*/);
        
        $dlgxml->get_widget('txtName')->set_text($name);
    }
}

1;
