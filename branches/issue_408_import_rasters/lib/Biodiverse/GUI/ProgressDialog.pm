package Biodiverse::GUI::ProgressDialog;

#
# Progress bar to show whilst doing long calculations
#

use strict;
use warnings;
use 5.010;

use Glib qw (TRUE FALSE);
use Gtk2;
use Gtk2::GladeXML;
use Carp;
use Time::HiRes qw/tv_interval gettimeofday/;
use Data::Dumper;

require Biodiverse::Config;
my $progress_update_interval = $Biodiverse::Config::progress_update_interval;

our $VERSION = '0.19';

my $TRUE  = 'TRUE';
my $FALSE = 'FALSE';
my $NULL_STRING = q//;

use Biodiverse::GUI::GUIManager;
use Biodiverse::Exception;

no warnings 'redefine';

my $progress_next_id = 0;
my $progress_max_id = 32000; # fairly conservative int_max

sub new {
    my $class    = shift;
    my $text     = shift || $NULL_STRING;
    my $progress = shift || 0;
    my $title    = shift || $NULL_STRING;

    my $gui = Biodiverse::GUI::GUIManager->instance;

    # Load the widgets from Glade's XML - need a better method of detecting if we are run from a GUI
    my $glade_file = $gui->get_glade_file;
    Biodiverse::GUI::ProgressDialog::NotInGUI->throw
        if ! $glade_file;
    
    # Make object
    my $self = {
    	entry_frame => undef,
        label_widget => undef,
        progress_bar => undef,
        id => 0
    };
    bless $self, $class;
    
    # from progress bar singleton in GUI, request a new progress
    # instance and grab references to the widgets
    $self->{id} = $progress_next_id++;
    $progress_next_id = 0 if ($progress_next_id >= $progress_max_id);
    my ($label, $bar) = $gui->add_progress_entry($self, $title, $text, $progress);

    $self->{label_widget} = $label;
    $self->{progress_bar} = $bar;
    
    $self->{progress_update_interval} = $progress_update_interval;

    $self->update ($text, $progress);

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
    
    if (not defined $text) {
        $text = join "\n", scalar caller(), scalar caller(1), scalar caller(2), scalar caller(3);
    }
    
    if ($progress < 0 or $progress > 1) {
        Biodiverse::GUI::ProgressDialog::Bounds->throw(
            message  => "ERROR [ProgressDialog] progress is $progress (not between 0 & 1)",
        );
    }
    
    # get widgets and check if window closed
    my $label_widget = $self->{label_widget};
    my $bar = $self->{progress_bar};
    if (not defined $bar) {
    	say "update called when progress bar not defined, throwing";
        Biodiverse::GUI::ProgressDialog::Cancel->throw(
            message  => "Progress bar closed, operation cancelled",
        );
    }

    return if $self->{last_update_time}
              && !(  tv_interval ($self->{last_update_time})
                    > $self->{progress_update_interval}
                   );

    $self->{last_update_time} = [gettimeofday];

    #$self->{dlg}->present;  #  raise to top

    # update dialog
    if ($label_widget) {
        $label_widget->set_markup("<b>$text</b>");
    }

    $self->{pulse} = 0;

    $bar->set_fraction($progress);

    while (Gtk2->events_pending) { Gtk2->main_iteration(); }
    
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
    else {
        # update dialog
        my $label_widget = $self->{label_widget};
        if ($label_widget) {
            $label_widget->set_markup("<b>$text</b>");
        }

        my $bar = $self->{bar};
        $bar->set_pulse_step ($progress);
        #$bar->pulse;

        if (not $self->{pulse}) {  #  only set this if we aren't already pulsing
            print "Starting pulse\n";
            $self->{pulse} = 1;
            my $x = Glib::Timeout->add(10, \&pulse_progress_bar, [$self, $bar]);
            #my $x = Glib::Timeout->add(100, sub {pulse_progress_bar ( $self )});
            #my $y = $x;
        }

        # process Gtk events - does this do the right thing?
        while (Gtk2->events_pending) { Gtk2->main_iteration(); }

        #  bad idea this one.  It pulses without end.
        #Gtk2->main;
    }

    return;
}

sub pulsate_stop {
    my $self = shift;
    #$self->{pulse} = FALSE;
    $self->{pulse} = 0;
    
    return;
}

sub pulse_progress_bar {
    #my $self = shift;
    #my $p_bar = $self->{dlgxml}->get_widget('progressbar');
    #my $p_bar = shift;
    
    #print "  pulsing...\n";
    my $data = shift;
    my ($self, $p_bar) = @$data[0,1];
    
    #print "$self->{pulse}\t$p_bar\n";
    
    if ($self->{pulse} and defined $p_bar) {
        #print "     PULSING\n";
        #$p_bar->set_pulse_step (0.1);
        $p_bar->pulse;
        return TRUE;  #  keep going
    }
    
    #print "[PROGRESS BAR] Stop pulsing\n";
    
    return FALSE;    
}

1;
