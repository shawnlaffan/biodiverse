package Biodiverse::GUI::Popup;

use strict;
use warnings;

#use Data::Dumper;
use Carp;
use Biodiverse::Utilities qw/sort_list_with_tree_names_aa/;

use Gtk3;

our $VERSION = '4.99_008';

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


#NOTE: we store the dialog's xml, not the actual widget
my %g_dialogs;      # Maps cell -> dialog

my $g_reuse_dlg;     # Dialog to be reused next
my $g_reuse_element; # this dialog's cell

my $g_selected_source = 2;     # name of previously selected source
my $g_last_reuse = 1;        # last state of the re-use checkbox


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
sub show_popup {
    my $element = shift;
    my $sources_ref = shift;
    my $default_source = shift;
    my $dlgxml;

    # If already showing a dialog, close it
    if (exists $g_dialogs{$element}) {
        close_dialog($element);
    }
    else {
        if (defined $g_reuse_dlg) {
            $dlgxml = $g_reuse_dlg;
            delete $g_dialogs{$g_reuse_element};
            #print "[Popup] Reusing dialog which was for $g_reuse_element\n";
        }
        else {
            #print "[Popup] Making new labels dialog for $element\n";
            $dlgxml = make_dialog();
        }

        $g_dialogs{$element} = $dlgxml;
        load_dialog($dlgxml, $element, $sources_ref, $default_source);
    }
}

sub make_dialog {
    my $gui = Biodiverse::GUI::GUIManager->instance;

    my $dlgxml = Gtk3::Builder->new();
    $dlgxml->add_from_file($gui->get_gtk_ui_file('wndCellPopup.ui'));

    # Put it on top of main window
    $dlgxml->get_object(DLG_NAME)->set_transient_for($gui->get_object('wndMain'));

    # Set height to be 1/3 of screen
    #$dlgxml->get_object(DLG_NAME)->resize(1, Gtk3::Gdk->screen_height() / 3);

    # Set up the combobox
    my $combo = $dlgxml->get_object('comboSources');
    my $renderer = Gtk3::CellRendererText->new();
    $combo->pack_start($renderer, 1);
    $combo->add_attribute($renderer, text => SOURCES_MODEL_NAME);

    # Set up the list
    my $list = $dlgxml->get_object('lstData');

    my $name_renderer = Gtk3::CellRendererText->new();
    my $value_renderer = Gtk3::CellRendererText->new();
    my $col_name = Gtk3::TreeViewColumn->new();
    my $col_value = Gtk3::TreeViewColumn->new();

    $col_name->pack_start($name_renderer, 1);
    $col_value->pack_start($value_renderer, 1);
    $col_name->add_attribute($name_renderer, text => 0);

    $list->insert_column($col_name, -1);
    $list->insert_column($col_value, -1);
    $list->set_headers_visible(0);

    # Save col/renderer so that we can choose different count columns
    $list->{colValue} = $col_value;
    $list->{valueRenderer} = $value_renderer;

    return $dlgxml;
}


sub load_dialog {
    my $dlgxml  = shift;
    my $element = shift;
    my $sources_ref    = shift;
    my $default_source = shift;

    #print Data::Dumper::Dumper($neighbours);
    #print Data::Dumper::Dumper(%g_dialogs);

    # Create pseudo-object hash to hold everything together
    my $popup = {};
    bless $popup, 'Biodiverse::GUI::PopupObject';

    $popup->{list}    = $dlgxml->get_object('lstData');
    $popup->{element} = $element;
    $popup->{sources_ref} = $sources_ref;

    # Create model of available sources
    my $sources_model = make_sources_model($sources_ref);
    #print "[Popup] Made source model\n";

    # Set up the combobox
    my $combo = $dlgxml->get_object('comboSources');
    $combo->set_model($sources_model);

    my $selected_source =
           find_selected_source($sources_model, $g_selected_source) # first use user-selected
        || find_selected_source($sources_model, $default_source) # then try default source
        || $sources_model->get_iter_first;    # use first one otherwise
    $combo->set_active_iter($selected_source);

    # Set title
    $g_dialogs{$element}->get_object(DLG_NAME)->set_title("Data for $element");

    # Load first thing
    on_source_changed($combo, $popup);

    # Disconnect signals (dialog might be being reused)
    $dlgxml->get_object('comboSources')->signal_handlers_disconnect_by_func(\&on_source_changed);
    $dlgxml->get_object('btnClose')->signal_handlers_disconnect_by_func(\&close_dialog);
    $dlgxml->get_object(DLG_NAME)->signal_handlers_disconnect_by_func(\&close_dialog);
    $dlgxml->get_object('btnCloseAll')->signal_handlers_disconnect_by_func(\&on_close_all);
    $dlgxml->get_object('btnCopy')->signal_handlers_disconnect_by_func(\&on_copy);
    $dlgxml->get_object('chkReuse')->signal_handlers_disconnect_by_func(\&on_reuse_toggled);

    # Connect signals
    $dlgxml->get_object('comboSources')->signal_connect(changed => \&on_source_changed, $popup);
    $dlgxml->get_object('btnClose')->signal_connect_swapped(clicked => \&close_dialog, $element);
    $dlgxml->get_object(DLG_NAME)->signal_connect_swapped(delete_event => \&close_dialog, $element);
    $dlgxml->get_object('btnCloseAll')->signal_connect_swapped(clicked => \&on_close_all);
    $dlgxml->get_object('btnCopy')->signal_connect_swapped(clicked => \&on_copy, $popup);

    # Set to last re-use state
    #print "[Popup] last reuse = $g_last_reuse\n";
    $dlgxml->get_object('chkReuse')->set_active($g_last_reuse);
    $dlgxml->get_object('chkReuse')->signal_connect(toggled => \&on_reuse_toggled, [$element, $dlgxml]);
    on_reuse_toggled($dlgxml->get_object('chkReuse'),  [$element, $dlgxml]);
}

##########################################################
# Sources
##########################################################

# Adds appropriate options to the data sources combobox
sub make_sources_model {
    my $sources_ref = shift;

    my $sources_model = Gtk3::ListStore->new(
        'Glib::String',
        'Glib::Scalar',
        'Glib::Scalar',
    );
    my $iter;

    foreach my $source_name (sort_list_with_tree_names_aa ([keys %{$sources_ref}])) {
        $iter = $sources_model->append;
        $sources_model->set($iter,
            SOURCES_MODEL_NAME,     $source_name,
            SOURCES_MODEL_CALLBACK, $sources_ref->{$source_name},
        );
    }


    return $sources_model;
}

sub find_selected_source {
    my $sources_model = shift;
    my $search_name = shift || return;
    my $iter = $sources_model->get_iter_first;

    my $found;
    while ($iter) {

        my $name = $sources_model->get($iter, SOURCES_MODEL_NAME);
        if ($name eq $search_name) {
            $found++;
            last;
        };

        last if !$sources_model->iter_next($iter);
    }

    return $found ? $iter : undef;
}


sub on_source_changed {
    my $combo = shift;
    my $popup = shift;

    if ($combo->get_active < 0) {
        $combo->set_active(0);
    }
    my $iter = $combo->get_active_iter;
    my ($name, $callback)
        = $combo->get_model->get(
            $iter,
            SOURCES_MODEL_NAME,
            SOURCES_MODEL_CALLBACK,
        );
    $g_selected_source = $name;
    $popup->{listname} = $name;

    # Call the source-specific callback function (showList, showNeighbourLabels ...)
    $callback->($popup);

    return;
}



##########################################################
# Misc
##########################################################

sub close_dialog {
    my $element = shift;
    #print "[Popup] Closing labels dialog for $element\n";
    $g_dialogs{$element}->get_object(DLG_NAME)->destroy();
    #print "[Popup] Dialogue destroyed\n";
    delete $g_dialogs{$element};

    #  don't tell me about an undef in the eq check below.
    no warnings 'uninitialized';

    if ($element eq $g_reuse_element) {
        $g_reuse_dlg     = undef;
        $g_reuse_element = undef;
    }

    return;
}

sub on_close_all {
    print "[Popup] Closing all labels dialogs\n";
    while ( (my $element, my $dlgxml) = each %g_dialogs) {
        $dlgxml->get_object(DLG_NAME)->destroy();
    }

    %g_dialogs = ();
    $g_reuse_dlg = undef;
    $g_reuse_element = undef;

    return;
}

sub on_reuse_toggled {
    my $button = shift;
    my $args = shift;

    my ($element, $dlgxml) = ($args->[0], $args->[1]);
    if ($button->get_active() ) {
        # Set to re-use
        # Clear old dialog's checkbox
        if (defined $g_reuse_dlg && $g_reuse_dlg != $dlgxml) {
            $g_reuse_dlg->get_object('chkReuse')->set_active(0);
        }

        # Set this dialog to be re-use target
        $g_reuse_dlg = $dlgxml;
        $g_reuse_element = $element;

        #print "[Popup] Set reuse dialog to be $element\n";
        $g_last_reuse = 1;
    }
    else {
        # Clear re-use dialog
        $g_reuse_dlg = undef;
        $g_reuse_element = undef;
        #print "[Popup] Cleared re-use dialog\n";
        $g_last_reuse = 0;
    }

    return;
}

##########################################################
# Copy
##########################################################

sub on_copy {
    my $popup = shift;

    my $clipboard = Gtk3::Clipboard::get(
        Gtk3::Gdk::Atom::intern('CLIPBOARD', Glib::FALSE)
    );

    my $text = get_text_for_clipboard ($popup);
    $clipboard->set_text($text);

    return;
}

sub get_text_for_clipboard {
    my $popup = shift;

    my $element = $popup->{element};
    my $list = $popup->{list};
    my $listname = $popup->{listname};
    my $model = $list->get_model();

    #   should not happen now as we copy to clipboard immediately
    if (!$model) {
        my $gui = Biodiverse::GUI::GUIManager->instance;
        my $e = "Unable to paste data.\nPopup has been closed so link with source data is lost\n";
        $gui->report_error($e);
        return;
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

    my $value_column = $popup->{value_column};

    my $text = defined $value_column ? "$listname\t$element\n" : "$listname\n";

    while ($iter) {
        my $name = $model->get($iter, 0);
        if (defined $value_column) {
            my $value = $model->get($iter, $value_column);
            $text .= "$name\t$value\n";
        }
        else {
            $text .= "$name\n";
        }
        last if !$model->iter_next($iter);
    }

    return $text;
}



1;
