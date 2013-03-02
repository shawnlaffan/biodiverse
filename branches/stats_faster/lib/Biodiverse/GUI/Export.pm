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

our $VERSION = '0.18_004';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::ParametersTable;
use Biodiverse::GUI::YesNoCancel;


sub Run {
    my $object = shift;
    
    #  sometimes we get called on non-objects,
    #  eg if nothing is highlighted
    return if ! defined $object;  
    
    my $gui = Biodiverse::GUI::GUIManager->instance;

    # Load the widgets from Glade's XML
    #my $dlgxml = Gtk2::GladeXML->new($gui->getGladeFile, 'dlgExport');

    # Get the Parameters metadata
    my %args = $object -> get_args (sub => 'export');
    
    ###################
    # get the selected format
    
    my $format_choices = $args{format_choices};
    
    my $dlgxml = Gtk2::GladeXML->new($gui->getGladeFile, 'dlgImportParameters');
    my $format_dlg = $dlgxml->get_widget('dlgImportParameters');
    
    #my $format_dlg = $dlgxml->get_widget('dlgExport');
    $format_dlg->set_transient_for( $gui->getWidget('wndMain') );
    $format_dlg -> set_title ('Export parameters');
    
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
        $format_dlg -> destroy;
        return;
    }
    
    my $formats
      = Biodiverse::GUI::ParametersTable::extract($format_extractors);

    my $selected_format = $formats->[1];
    my $params = $args{parameters}{$selected_format};

    $format_dlg->destroy;

    #####################    
    #  and now get the params for the selected format
    $dlgxml = Gtk2::GladeXML->new($gui->getGladeFile, 'dlgExport');

    my $dlg = $dlgxml->get_widget('dlgExport');
    $dlg->set_transient_for( $gui->getWidget('wndMain') );
    $dlg -> set_title ("Export format: $selected_format");

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
    my $chooser = $dlgxml->get_widget('filechooser');
    my $filename = $chooser->get_filename();
    if ( (not -e $filename)
        || Biodiverse::GUI::YesNoCancel->run({
            header => "Overwrite file $filename?"})
                eq 'yes'
        ) {
        #  progress bar for some processes
        #my $progress = Biodiverse::GUI::ProgressDialog->new;
        
        eval {
            $object->export(
                format   => $selected_format,
                file     => $filename,
                @$params,
                #progress => $progress
            )
        };
        if ($EVAL_ERROR) {
            $gui -> report_error ($EVAL_ERROR);
        }
        
        #$progress -> destroy;  #  clean up the progress bar
    }
    else {
        goto RUN_DIALOG; # my first ever goto!
    }


    $dlg->destroy;
    
    return;
}


1;
