package Biodiverse::GUI::Export;

#
# Generic export dialog, with dynamically generated parameters table
#

use strict;
use warnings;

use English ( -no_match_vars );

use Glib;
use Gtk2;
use Cwd;

use List::MoreUtils qw /any none/;

our $VERSION = '1.99_002';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::ParametersTable;
use Biodiverse::GUI::YesNoCancel;


sub Run {
    my $object = shift;
    my $selected_format = shift // '';

    #  sometimes we get called on non-objects,
    #  eg if nothing is highlighted
    return if ! defined $object;

    my $gui = Biodiverse::GUI::GUIManager->instance;

    #  stop keyboard events being applied to any open tabs
    $gui->activate_keyboard_snooper (0);

    # Get the Parameters metadata
    my $metadata = $object->get_metadata (sub => 'export');

    ###################
    # get the selected format

    my $format_choices = $metadata->get_format_choices;
    my $format_choice_array = $format_choices->[0]{choices};

    if (none {$_ eq $selected_format} @$format_choice_array) {
        #  get user preference if none passed as an arg
        
        my $dlgxml = Gtk2::Builder->new();
        $dlgxml->add_from_file($gui->get_gtk_ui_file('dlgImportParameters.ui'));
        my $format_dlg = $dlgxml->get_object('dlgImportParameters');

        $format_dlg->set_transient_for( $gui->get_object('wndMain') );
        $format_dlg->set_title ('Export parameters');

        # Build widgets for parameters
        my $format_table = $dlgxml->get_object('tableImportParameters');

        # (passing $dlgxml because generateFile uses existing widget on the dialog)
        my $parameters_table = Biodiverse::GUI::ParametersTable->new;
        my $format_extractors
            = $parameters_table->fill(
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
          = $parameters_table->extract($format_extractors);

        $selected_format = $formats->[1];

        $format_dlg->destroy;
    }

    #my $meta_params = $metadata->get_parameters;
    #my $params = $params->{$selected_format};  #  should be a method
    my $params = $metadata->get_parameters_for_format(format => $selected_format);

    #####################
    #  and now get the params for the selected format
    my $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file($gui->get_gtk_ui_file('dlgExport.ui'));

    my $dlg = $dlgxml->get_object('dlgExport');
    $dlg->set_transient_for( $gui->get_object('wndMain') );
    $dlg->set_title("Export format: $selected_format");
    $dlg->set_modal(1);

    my $chooser = $dlgxml->get_object('filechooser');
    $chooser->set_current_folder_uri(getcwd());
    # does not stop the keyboard events on open tabs
    #$chooser->signal_connect ('button-press-event' => sub {1});

    # Build widgets for parameters
    my $table = $dlgxml->get_object('tableParameters');
    # (passing $dlgxml because generateFile uses existing widget on the dialog)
    my $parameters_table = Biodiverse::GUI::ParametersTable->new;
    my $extractors
        = $parameters_table->fill(
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
        $gui->activate_keyboard_snooper (1);
        return;
    }

    # Export!
    $params = $parameters_table->extract($extractors);
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
