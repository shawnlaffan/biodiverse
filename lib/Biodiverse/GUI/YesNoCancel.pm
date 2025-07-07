package Biodiverse::GUI::YesNoCancel;
use 5.010;

use strict;
use warnings;
use Gtk3;

use English ( -no_match_vars );

our $VERSION = '4.99_004';

use Biodiverse::GUI::GUIManager;

=head1
Implements a yes/no/cancel dialog

To use call in these ways

   Biodiverse::GUI::YesNoCancel->run({text => 'blah'}) or
   Biodiverse::GUI::YesNoCancel->run({header => 'titular', text => blah}) or
   Biodiverse::GUI::YesNoCancel->run({header => 'titular', text => blah, hide_yes => 1, hide_no => 1})
   Biodiverse::GUI::YesNoCancel->run({title => 'window_title', hide_cancel => 1})

You can hide all the buttons if you really want to.

it returns 'yes', 'no', or 'cancel'

=cut

##########################################################
# Globals
##########################################################

use constant DLG_NAME => 'dlgYesNoCancel';

sub run {
    my $cls = shift; #ignored
    my $args = shift || {};


    my $text = q{};
    if (defined $args->{header}) {
        #print "mode1\n";
        $text .= '<b>'
                . Glib::Markup::escape_text ($args->{header})
                . '</b>';
    }
    if (defined $args->{text}) {
        $text .= Glib::Markup::escape_text(
            $args->{text}
        );
    }

    my $gui = Biodiverse::GUI::GUIManager->instance;

    my $dlgxml = Gtk3::Builder->new();
    $dlgxml->add_from_file($gui->get_gtk_ui_file('dlgYesNoCancel.ui'));
    my $dlg = $dlgxml->get_object(DLG_NAME);

    # set the text
    my $label = $dlgxml->get_object('lblText');

    #  try with markup - need to escape all the bits
    eval { $label->set_markup($text) };
    if ($EVAL_ERROR) {  #  and then try without markup
        $label->set_text($text);
    }

    if ($args->{hide_yes}) {
        $dlgxml->get_object('btnYes')->hide;
    }
    if ($args->{hide_no}) {
        $dlgxml->get_object('btnNo')->hide;
    }
    if ($args->{hide_cancel}) {
        $dlgxml->get_object('btnCancel')->hide;
    }
    #  not yet... should add an OK button and hide by default
    if ($args->{yes_is_ok}) {
        $dlgxml->get_object('btnYes')->set_label ('OK');
    }
    if ($args->{title}) {
        $dlg->set_title ($args->{title});
    }
    
    my $main_window = $gui->get_object('wndMain');
    # Put it on top of main window
    $dlg->set_transient_for($main_window);
    #  and make it modal - sometimes we lose the dialog and have to kill the whole process
    $dlg->set_modal($main_window);
    
    ##  add timeout as sometimes the dialog is nowhere to be seen
    ##  -- the move call above avoids that?
    #my $starttime = time();
    #my $timed_out;
    #my $timeout_cb = sub {
    #    return 1 if !defined $default_response;
    #    return 1 if time() - $starttime < 1;
    #    #say 'VISIBLE: ' . $dlg->is_visible;
    #    say 'SCREEN DIMS: ' . Gtk3::Gdk->screen_width . ' ' . Gtk3::Gdk->screen_height;
    #    say 'MAIN WIN: ' . join ' ', $main_window->get_position ();
    #    say 'DLG  POS: ' . join ' ', $dlg->get_position ();
    #    $dlg->move ($main_window->get_position); sleep (10);
    #    $timed_out++;
    #    $dlg->destroy;
    #    0;
    #};
    #my $timer2 = Glib::Timeout->add(100, $timeout_cb);

    # Show the dialog
    my $response = $dlg->run();
    $dlg->destroy();

    $response = 'cancel' if $response eq 'delete-event';
    if (not ($response eq 'yes' or $response eq 'no' or $response eq 'cancel')) {
        die "not yes/no/cancel: $response";
    }

    #print "[YesNoCancel] - returning $response\n";
    return $response;
}



1;
