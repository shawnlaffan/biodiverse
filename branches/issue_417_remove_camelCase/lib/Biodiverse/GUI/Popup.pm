package Biodiverse::GUI::Popup;

use strict;
use warnings;

use Data::Dumper;
use Carp;

use Gtk2;

our $VERSION = '0.19';

use English qw { -no_match_vars };

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::PopupObject; # defined at the bottom of this file

=head1

Implements the popup dialogs shown when cells on the grid
are clicked. They can be reused - meaning that instead of making a new dialog,
an existing one is "overwritten".

=head2

The dialog is given a hash of SOURCE_NAME => $function
When a source is selected, $function is called and passed a $popup parameter.
Other parameters can be passed by making $function a closure, eg:

  $sources->{LABELS} = sub { showLabels(@_, $basedata_ref, $element); } ;
  ($popup) is given as part of "@_"

$popup is of type Biodiverse::GUI::PopupObject and has methods
   setListModel   - shows the given GTK model as the output
   setValueColumn - puts the given model column onto the list's second column
                    This list's first column is the first model column


=cut

##########################################################
# Globals
##########################################################

use constant DLG_NAME => 'wndCellPopup';

# Stores information about available lists (all labels, neighbours, output lists)
# When a sources is selected the callback function will be called (with parameter CUSTOM)
# This will load up the actual data list
use constant SOURCES_MODEL_NAME => 0;
use constant SOURCES_MODEL_CALLBACK => 1;

# Data types that we can paste into the clipboard
use constant TYPE_TEXT => 1;
use constant TYPE_HTML => 2; # spreadsheet programs should understand HTML tables


#NOTE: we store the dialog's gladexml, not the actual widget
my %g_dialogs;      # Maps cell -> dialog

my $g_reuseDlg;     # Dialog to be reused next
my $g_reuseElement; # this dialog's cell

my $g_selectedSource = 2;     # name of previously selected source
my $g_lastReuse = 1;        # last state of the re-use checkbox


=head2

Parameters
=over 4
=item C<$element> element (cell) for which to show the popup
=item C<$neighbours>
    Possibly a ref to hash containing LABEL_HASH1, LABEL_HASH2, LABEL_HASH_ALL
    if undef will use get_labels_in_group_as_hash
=back
=cut

##########################################################
# New dialogs
##########################################################

# Shows or re-uses popup dialog for a given element
# $sources_ref points to a hash:
#   SOURCE_NAME => $function
sub showPopup {
    my $element = shift;
    my $sources_ref = shift;
    my $default_source = shift;
    my $dlgxml;

    # If already showing a dialog, close it
    if (exists $g_dialogs{$element}) {
        closeDialog($element);
    }
    else {
        if (defined $g_reuseDlg) {
            $dlgxml = $g_reuseDlg;
            delete $g_dialogs{$g_reuseElement};
            #print "[Popup] Reusing dialog which was for $g_reuseElement\n";
        }
        else {
            #print "[Popup] Making new labels dialog for $element\n";
            $dlgxml = makeDialog();
        }

        $g_dialogs{$element} = $dlgxml;
        loadDialog($dlgxml, $element, $sources_ref, $default_source);
    }
}

sub makeDialog {
    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $dlgxml = Gtk2::GladeXML->new($gui->getGladeFile, DLG_NAME);

    # Put it on top of main window
    $dlgxml->get_widget(DLG_NAME)->set_transient_for($gui->getWidget('wndMain'));

    # Set height to be 1/3 of screen
    #$dlgxml->get_widget(DLG_NAME)->resize(1, Gtk2::Gdk->screen_height() / 3);

    # Set up the combobox
    my $combo = $dlgxml->get_widget('comboSources');
    my $renderer = Gtk2::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, text => SOURCES_MODEL_NAME);

    # Set up the list
    my $list = $dlgxml->get_widget('lstData');

    my $nameRenderer = Gtk2::CellRendererText->new();
    my $valueRenderer = Gtk2::CellRendererText->new();
    my $colName = Gtk2::TreeViewColumn->new();
    my $colValue = Gtk2::TreeViewColumn->new();

    $colName->pack_start($nameRenderer, 1);
    $colValue->pack_start($valueRenderer, 1);
    $colName->add_attribute($nameRenderer, text => 0);

    $list->insert_column($colName, -1);
    $list->insert_column($colValue, -1);
    $list->set_headers_visible(0);

    # Save col/renderer so that we can choose different count columns
    $list->{colValue} = $colValue;
    $list->{valueRenderer} = $valueRenderer;

    return $dlgxml;
}


sub loadDialog {
    my $dlgxml = shift;
    my $element = shift;
    my $sources_ref = shift;
    my $default_source = shift;

    #print Data::Dumper::Dumper($neighbours);
    #print Data::Dumper::Dumper(%g_dialogs);

    # Create pseudo-object hash to hold everything together
    my $popup = {};
    bless $popup, 'Biodiverse::GUI::PopupObject';

    $popup->{list} = $dlgxml->get_widget('lstData');
    $popup->{element} = $element;
    $popup->{sources_ref} = $sources_ref;

    # Create model of available sources
    my $sources_model = makeSourcesModel($sources_ref);
    #print "[Popup] Made source model\n";

    # Set up the combobox
    my $combo = $dlgxml->get_widget('comboSources');
    $combo->set_model($sources_model);

    my $selected_source =  findSelectedSource($sources_model, $g_selectedSource) # first use user-selected
                        || findSelectedSource($sources_model, $default_source) # then try default source
                        || $sources_model->get_iter_first;    # use first one otherwise
    $combo->set_active_iter($selected_source);

    # Set title
    $g_dialogs{$element}->get_widget(DLG_NAME)->set_title("Data for $element");

    # Load first thing
    onSourceChanged($combo, $popup);
    
    # Disconnect signals (dialog might be being reused)
    $dlgxml->get_widget('comboSources')->signal_handlers_disconnect_by_func(\&onSourceChanged);
    $dlgxml->get_widget('btnClose')->signal_handlers_disconnect_by_func(\&closeDialog);
    $dlgxml->get_widget(DLG_NAME)->signal_handlers_disconnect_by_func(\&closeDialog);
    $dlgxml->get_widget('btnCloseAll')->signal_handlers_disconnect_by_func(\&onCloseAll);
    $dlgxml->get_widget('btnCopy')->signal_handlers_disconnect_by_func(\&onCopy);
    $dlgxml->get_widget('chkReuse')->signal_handlers_disconnect_by_func(\&onReuseToggled);

    # Connect signals
    $dlgxml->get_widget('comboSources')->signal_connect(changed => \&onSourceChanged, $popup);
    $dlgxml->get_widget('btnClose')->signal_connect_swapped(clicked => \&closeDialog, $element);
    $dlgxml->get_widget(DLG_NAME)->signal_connect_swapped(delete_event => \&closeDialog, $element);
    $dlgxml->get_widget('btnCloseAll')->signal_connect_swapped(clicked => \&onCloseAll);
    $dlgxml->get_widget('btnCopy')->signal_connect_swapped(clicked => \&onCopy, $popup);

    # Set to last re-use state
    #print "[Popup] last reuse = $g_lastReuse\n";
    $dlgxml->get_widget('chkReuse')->set_active($g_lastReuse);
    $dlgxml->get_widget('chkReuse')->signal_connect(toggled => \&onReuseToggled, [$element, $dlgxml]);
    onReuseToggled($dlgxml->get_widget('chkReuse'),  [$element, $dlgxml]);
}

##########################################################
# Sources
##########################################################

# Adds appropriate options to the data sources combobox
sub makeSourcesModel {
    my $sources_ref = shift;

    my $sources_model = Gtk2::ListStore->new(
        'Glib::String',
        'Glib::Scalar',
        'Glib::Scalar',
    );
    my $iter;

    foreach my $source_name (sort keys %{$sources_ref}) {
        $iter = $sources_model->append;
        $sources_model->set($iter,
            SOURCES_MODEL_NAME,     $source_name,
            SOURCES_MODEL_CALLBACK, $sources_ref->{$source_name},
        );
    }


    return $sources_model;
}

sub findSelectedSource {
    my $sources_model = shift;
    my $search_name = shift || return;
    my $iter = $sources_model->get_iter_first;
    
    while ($iter) {

        my $name = $sources_model->get($iter, SOURCES_MODEL_NAME);
        last if ($name eq $search_name);

        $iter = $sources_model->iter_next($iter);
    }

    return $iter;
}


sub onSourceChanged {
    my $combo = shift;
    my $popup = shift;

    my $iter = $combo->get_active_iter;

    my ($name, $callback)
        = $combo->get_model->get(
            $iter,
            SOURCES_MODEL_NAME,
            SOURCES_MODEL_CALLBACK,
        );
    $g_selectedSource = $name;
    $popup->{listname} = $name;

    # Call the source-specific callback function (showList, showNeighbourLabels ...)
    &$callback($popup);
    
    return;
}



##########################################################
# Misc
##########################################################

sub closeDialog {
    my $element = shift;
    #print "[Popup] Closing labels dialog for $element\n";
    $g_dialogs{$element}->get_widget(DLG_NAME)->destroy();
    #print "[Popup] Dialogue destroyed\n";
    delete $g_dialogs{$element};
    
    #  don't tell me about an undef in the eq check below.
    no warnings 'uninitialized';

    if ($element eq $g_reuseElement) {
        $g_reuseDlg     = undef;
        $g_reuseElement = undef;
    }
    
    return;
}

sub onCloseAll {
    print "[Popup] Closing all labels dialogs\n";
    while ( (my $element, my $dlgxml) = each %g_dialogs) {
        $dlgxml->get_widget(DLG_NAME)->destroy();
    }

    %g_dialogs = ();
    $g_reuseDlg = undef;
    $g_reuseElement = undef;
    
    return;
}

sub onReuseToggled {
    my $button = shift;
    my $args = shift;

    my ($element, $dlgxml) = ($args->[0], $args->[1]);
    if ($button->get_active() ) {
        # Set to re-use
        # Clear old dialog's checkbox
        if (defined $g_reuseDlg && $g_reuseDlg != $dlgxml) {
            $g_reuseDlg->get_widget('chkReuse')->set_active(0);
        }

        # Set this dialog to be re-use target
        $g_reuseDlg = $dlgxml;
        $g_reuseElement = $element;

        #print "[Popup] Set reuse dialog to be $element\n";
        $g_lastReuse = 1;
    }
    else {
        # Clear re-use dialog
        $g_reuseDlg = undef;
        $g_reuseElement = undef;
        #print "[Popup] Cleared re-use dialog\n";
        $g_lastReuse = 0;
    }
    
    return;
}

##########################################################
# Copy
##########################################################

sub onCopy {
    my $popup = shift;

    my $clipboard = Gtk2::Clipboard->get(Gtk2::Gdk->SELECTION_CLIPBOARD);

    # Add text and HTML (spreadsheet programs can read it) data to clipboard
    # We'll be called back when someone pastes
    eval {
        $clipboard->set_with_data (
            \&clipboard_get_func,
            \&clipboard_clear_func,
            $popup,
            {target=>'STRING',        info => TYPE_TEXT},
            {target=>'TEXT',          info => TYPE_TEXT},
            {target=>'COMPOUND_TEXT', info => TYPE_TEXT},
            {target=>'UTF8_STRING',   info => TYPE_TEXT},
            {target=>'text/plain',    info => TYPE_TEXT},
            {target=>'text/html',     info => TYPE_HTML},
        );
    };
    warn $EVAL_ERROR if $EVAL_ERROR;
    
    return;
}

sub clipboard_get_func {
    my $clipboard = shift;
    my $selection = shift;
    my $datatype = shift;
    my $popup = shift;

    #print "[Popup] Clipboard data request (type $datatype)\n";

    my $element  = $popup->{element};
    my $list     = $popup->{list};
    my $listname = $popup->{listname};
    my $model    = $list->get_model();
    my $text;

    if (! $model) {
        my $gui = Biodiverse::GUI::GUIManager->instance;
        my $e = "Unable to paste data.\nPopup has been closed so link with source data is lost\n";
        $gui->report_error($e);
        return;
    }

    # Start off with the "element" (ie: cell coordinates)
    if ($datatype == TYPE_HTML) {
        $text =<<'END_HTML_HEADER'
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">

        <head>
            <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
        </head>
        
        <body>
        
        <table>  
END_HTML_HEADER
;
        $text .= "<tr><td>$listname</td><td>$element</td></tr>";
    }
    else {
        $text = "$listname\t$element\n";
    }
    
    # Generate the text
    my $iter;
    eval {
        $iter = $model->get_iter_first();
    };
    if ($EVAL_ERROR) {
        my $gui = Biodiverse::GUI::GUIManager->instance;
        $gui->report_error($EVAL_ERROR);
        return;
    }

    while ($iter) {
        my $name = $model->get($iter, 0);
        my $value = '';

        if ($popup->{value_column}) {
            $value = $model->get($iter, $popup->{value_column});
        }

        if ($datatype == TYPE_TEXT) {
            $text .= "$name\t$value\n";
        }
        elsif ($datatype == TYPE_HTML) {
            $text .= "<tr><td>$name</td><td>$value</td></tr>\n";
        }
        $iter = $model->iter_next($iter);
    }

    if ($datatype == TYPE_HTML) {
        $text .= "</table></body></html>\n";
    }

    # Give the data..
    print "[Popup] Sending data for $element to clipboard\n";

    if ($datatype == TYPE_HTML) {
        my $atom = Gtk2::Gdk::Atom->intern('text/html');
        $selection->set($atom, 8, $text);
    }
    elsif ($datatype == TYPE_TEXT) {
        $selection->set_text($text);
    }

    return;
}

sub clipboard_clear_func {
    print "[Popup] Clipboard cleared\n";

    return;
}


1;
