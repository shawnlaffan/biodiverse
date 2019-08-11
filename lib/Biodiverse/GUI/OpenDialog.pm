package Biodiverse::GUI::OpenDialog;

#
# A FileChooserWidget but with a name field
#

use strict;
use warnings;
use File::Basename;
use Gtk2;

use Cwd;

our $VERSION = '2.99_005';

use Biodiverse::GUI::GUIManager;
use Ref::Util qw { :all };

use Biodiverse::Common;

# Show the dialog. Params:
#   title
#   suffixes to use in the filter (OPTIONAL)
#     - can be array refs to let users choose a few types at once,
#       eg: ["csv", "txt"], "csv", "txt"
sub Run {
    my $title = shift;
    my @suffixes = @_;

    my $gui = Biodiverse::GUI::GUIManager->instance;

    my $builder = Gtk2::Builder->new();
    $builder->add_from_file($gui->get_gtk_ui_file('OpenWithName.ui'));
    my $dlg = $builder->get_object('dlgOpenWithName');

    $dlg->set_transient_for( $gui->get_object('wndMain') );
    $dlg->set_title($title);

    # Connect file selected event - to automatically update name based on filename
    my $chooser = $builder->get_object('filechooser');
    $chooser->signal_connect('selection-changed' => \&on_file_selection, $builder);
    $chooser->set_current_folder_uri(getcwd());
    $chooser->set_action('GTK_FILE_CHOOSER_ACTION_OPEN');

    # Add filters
    foreach my $suffix (@suffixes) {

        my $filter = Gtk2::FileFilter->new();
        if (is_arrayref($suffix)) {
            foreach my $suff (@$suffix) {
                $filter->add_pattern("*.$suff");
            }
            $filter->set_name(join (' and ', @$suffix) . ' files');
        }
        else {
            $filter->add_pattern("*.$suffix");
            $filter->set_name("$suffix files");
        }

        $chooser->add_filter($filter);
    }

    # Show the dialog
    $dlg->set_modal(1);
    my $response = $dlg->run();

    my ($name, $filename);
    if ($response eq "ok") {
        # Save settings
        $name = $builder->get_object('txtName')->get_text();
        $filename = $chooser->get_filename();
    }

    $dlg->destroy();
    return ($name, $filename);
}


# Automatically update name based on filename
sub on_file_selection {
    my $chooser = shift;
    my $builder = shift;

    my $filename = $chooser->get_filename();
    if ($filename && Biodiverse::Common->file_exists_aa ($filename)) {
    
        my($name, $dir, $suffix) = fileparse($filename, qr/\.[^.]*/);
        
        $builder->get_object('txtName')->set_text($name);
    }
}

1;

