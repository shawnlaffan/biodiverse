package Biodiverse::GUI::ProgressDialog;

#
# Progress bar to show whilst doing long calculations
#

use strict;
use warnings;
use 5.010;

use Glib qw (TRUE FALSE);
use Gtk2;
use Carp;
use Time::HiRes qw/time/;
#use Data::Dumper;

require Biodiverse::Config;
my $progress_update_interval = $Biodiverse::Config::progress_update_interval;

our $VERSION = '3.99_002';

my $TRUE  = 'TRUE';
my $FALSE = 'FALSE';
my $NULL_STRING = q//;

use Biodiverse::GUI::GUIManager;
use Biodiverse::Exception;

no warnings 'redefine';

sub new {
    my $class    = shift;
    my $text     = shift || $NULL_STRING;
    my $progress = shift || 0;
    my $title    = shift || $NULL_STRING;

    my $gui = Biodiverse::GUI::GUIManager->instance;

    # Need a better method of detecting if we are run from a GUI
    my $check = $gui->get_gtk_ui_path;
    Biodiverse::GUI::ProgressDialog::NotInGUI->throw
        if ! $check;

    # Make object
    my $self = {
        label_widget => undef,
        progress_bar => undef,
        id => 0
    };
    bless $self, $class;

    # from progress bar singleton in GUI, request a new progress
    # instance and grab references to the widgets
    $self->{id} = "$self";  #  Stringified ref as unique id (avoids circularity).
                            #  Could just directly use the object's ref.
    my ($label, $bar) = $gui->add_progress_entry($self, $title, $text, $progress);

    $self->{label_widget} = $label;
    $self->{progress_bar} = $bar;

    $self->{progress_update_interval} = $progress_update_interval;

    $self->update ($text, $progress);

    #  set the last update time back so we always trigger on the first update
    $self->{last_update_time} = time - 2 * $progress_update_interval;

    return $self;
}

sub get_id {
    my $self = shift;
    return $self->{id};
}

sub end_dialog {
    my $self = shift;

    $self->pulsate_stop;

    #  sometimes we have already been destroyed when this is called
    #if ($self->{dlg}) {
    #    $self->{dlg}->destroy();
    #}

    # assume destroyed by method that created the progress bar, unlink from
    # gui display window
    my $gui = Biodiverse::GUI::GUIManager->instance;
    $gui->clear_progress_entry($self);

    foreach my $key (keys %$self) {
        #say "$key $self->{$key}";
        $self->{$key} = undef;
    }
}

sub destroy {
    my $self = shift;
    $self->end_dialog;

    return;
}


#  wrapper for the destroy method
sub destroy_callback {
    my ($widget, $event, $self) = @_;
    #say 'Destroy callback';
    return $self->destroy;
}

sub update {
    my ($self, $text, $progress) = @_;

    return if not defined $progress;  #  should croak?

    $progress >= 0 and $progress <= 1
      or Biodiverse::GUI::ProgressDialog::Bounds->throw(
          message =>
              "ERROR [ProgressDialog] progress is "
            . "$progress (not between 0 & 1)",
      );

    # check if window closed
    my $bar = $self->{progress_bar}
      // Biodiverse::GUI::ProgressDialog::Cancel->throw(
            message  => 'Progress bar closed, operation cancelled',
        );
    

    return if $self->{last_update_time}
              and time - $self->{last_update_time}
                    < $self->{progress_update_interval};

    $self->{last_update_time} = time;

    $text //= join "\n", scalar caller(), scalar caller(1), scalar caller(2), scalar caller(3);

    # update dialog
    $self->{label_widget}->set_markup("<b>$text</b>")
      if $self->{label_widget};

    $self->{pulse} = 0;

    $bar->set_fraction($progress);

    Gtk2->main_iteration while Gtk2->events_pending;

    Biodiverse::GUI::GUIManager->instance->show_progress;

    return;
}


#  set the progress bar to pulse.  sets a timer which calls the actual pulse sub
sub pulsate {
    my $self = shift;
    my $text = shift;
    my $progress = shift || 0.1; # fraction 0 .. 1
    return if not defined $progress;

    if (not defined $text) {
        $text = $NULL_STRING;
    }

    #$self->update ($text, $progress);  #  We are avoiding pulsation for the moment...
    #return;

    if ($progress < 0 || $progress > 1) {
        Biodiverse::GUI::ProgressDialog::Bounds->throw(
            message  => "ERROR [ProgressDialog] progress is $progress (not between 0 & 1)",
        );
    }

    # update dialog
    my $label_widget = $self->{label_widget};
    if ($label_widget) {
        $label_widget->set_markup("<b>$text</b>");
    }

    my $bar = $self->{progress_bar};
    $bar->set_pulse_step ($progress);
    $bar->show;
    #$bar->pulse;

    if (not $self->{pulse}) {  #  only set this if we aren't already pulsing
        print "Starting pulse\n";
        $self->{pulse} = 1;
        my $timer = Glib::Timeout->add(100, \&pulse_progress_bar, [$self, $bar]);
        #my $x = Glib::Timeout->add(100, sub {pulse_progress_bar ( $self )});
        #my $y = $x;
        $self->{pulse} = $timer;
        
        #my $t2 = Glib::Timeout->add(100, sub {say 't2t2t2'});
    }

    # process Gtk events - does this do the right thing?
    while (Gtk2->events_pending) { Gtk2->main_iteration(); }

    #  bad idea this one.  It pulses without end.
    #Gtk2->main;

    return;
}

sub pulsate_stop {
    my $self = shift;
    #$self->{pulse} = FALSE;
    $self->{pulse} = 0;

    return;
}

sub pulse_progress_bar {
    my $data = shift;
    my ($self, $p_bar) = @$data[0,1];

    print "$self->{pulse}\t$p_bar\n";

    if ($self->{pulse} and $p_bar) {
        #print "     PULSING\n";
        #$p_bar->set_pulse_step (0.1);
        $p_bar->pulse;
        
        #while (Gtk2->events_pending) { Gtk2->main_iteration(); }
        
        return 1;  #  keep going
    }

    print "[PROGRESS BAR] Stop pulsing\n";

    return 0;
}

1;
