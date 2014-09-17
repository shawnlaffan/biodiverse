package Biodiverse::GUI::Export;

#
# Generic export dialog, with dynamically generated parameters table
#

use strict;
use warnings;

use English ( -no_match_vars );

use Glib;
use Gtk2;
use Gtk2::GladeXML;
use Cwd;

our $VERSION = '0.99_004';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::ParametersTable;
use Biodiverse::GUI::YesNoCancel;


sub Run {
    my $object = shift;
    
    #  sometimes we get called on non-objects,
    #  eg if nothing is highlighted
    return if ! defined $object;  
    
    my $gui = Biodiverse::GUI::GUIManager->instance;

    #  stop keyboard events being applied to any open tabs
    $gui->activate_keyboard_snooper (0);

    # Get the Parameters metadata
    my %args = $object->get_args (sub => 'export');
    
    ###################
    # get the selected format
    
    my $format_choices = $args{format_choices};
    
    my $dlgxml = Gtk2::GladeXML->new($gui->get_glade_file, 'dlgImportParameters');
    my $format_dlg = $dlgxml->get_widget('dlgImportParameters');
    
    #my $format_dlg = $dlgxml->get_widget('dlgExport');
    $format_dlg->set_transient_for( $gui->get_widget('wndMain') );
    $format_dlg->set_title ('Export parameters');

    # Build widgets for parameters
    my $format_table = $dlgxml->get_widget('tableImportParameters');
    
    # (passing $dlgxml because generateFile uses existing glade widget on the dialog)
    my $format_extractors
        = Biodiverse::GUI::ParametersTable::fill(
            $format_choices,
            $format_table,
            $dlgxml,
    ); 

    # Show the dialog
    $format_dlg->show_all();

  RUN_FORMAT_DIALOG:
    my $format_response = $format_dlg->run();
    
    if ($format_response ne 'ok') {
        $format_dlg->destroy;
        return;
    }
    
    my $formats
      = Biodiverse::GUI::ParametersTable::extract($format_extractors);

    my $selected_format = $formats->[1];
    my $params = $args{parameters}{$selected_format};

    $format_dlg->destroy;

    #####################
    #  and now get the params for the selected format
    $dlgxml = Gtk2::GladeXML->new($gui->get_glade_file, 'dlgExport');

    my $dlg = $dlgxml->get_widget('dlgExport');
    $dlg->set_transient_for( $gui->get_widget('wndMain') );
    $dlg->set_title ("Export format: $selected_format");
    $dlg->set_modal (1);

    my $chooser = $dlgxml->get_widget('filechooser');
    $chooser->set_current_folder_uri(getcwd());
    # does not stop the keyboard events on open tabs
    #$chooser->signal_connect ('button-press-event' => sub {1});  

    # Build widgets for parameters
    my $table = $dlgxml->get_widget('tableParameters');
    # (passing $dlgxml because generateFile uses existing glade widget on the dialog)
    my $extractors
        = Biodiverse::GUI::ParametersTable::fill(
            $params,
            $table,
            $dlgxml
    );

    # Show the dialog
    $dlg->show_all();
    

  RUN_DIALOG:
    my $response = $dlg->run();

    if ($response ne 'ok') {
        $dlg->destroy;
        return;
    }
    
    # Export!
    $params = Biodiverse::GUI::ParametersTable::extract($extractors);
    my $filename = $chooser->get_filename();
    $filename = Path::Class::File->new($filename)->stringify;  #  normalise the file name
    if ( (not -e $filename)
        || Biodiverse::GUI::YesNoCancel->run({
            header => "Overwrite file $filename?"})
                eq 'yes'
        ) {

        eval {
            $object->export(
                format   => $selected_format,
                file     => $filename,
                @$params,
            )
        };
        if ($EVAL_ERROR) {
            $gui->activate_keyboard_snooper (1);
            $gui->report_error ($EVAL_ERROR);
        }
    }
    else {
        goto RUN_DIALOG; # my first ever goto!
    }


    $dlg->destroy;
    $gui->activate_keyboard_snooper (1);
    
    return;
}


1;

