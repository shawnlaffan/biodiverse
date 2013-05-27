package Biodiverse::GUI::ProgressDialog;

#
# Progress bar to show whilst doing long calculations
#

use strict;
use warnings;
use Glib qw (TRUE FALSE);
use Gtk2;
use Gtk2::GladeXML;
use Carp;
use Time::HiRes qw /tv_interval gettimeofday/;

require Biodiverse::Config;
my $progress_update_interval = $Biodiverse::Config::progress_update_interval;

our $VERSION = '0.18_006';

my $TRUE  = 'TRUE';
my $FALSE = 'FALSE';
my $NULL_STRING = q{};

use Biodiverse::GUI::GUIManager;
use Biodiverse::Exception;

no warnings 'redefine';


sub new {
    my $class    = shift;
    my $text     = shift || $NULL_STRING;
    my $progress = shift || 0;

    #  debug
    #use Devel::StackTrace;
    #my $trace = Devel::StackTrace->new;
    #print $trace->as_string; # like carp

    
    my $gui = Biodiverse::GUI::GUIManager->instance;

    # Load the widgets from Glade's XML
    my $glade_file = $gui->getGladeFile;
    Biodiverse::GUI::ProgressDialog::NotInGUI->throw
        if ! $glade_file;

    my $dlgxml = Gtk2::GladeXML->new($glade_file, 'wndProgress');
    my $dlg = $dlgxml->get_widget('wndProgress');
    $dlg->set_transient_for( $gui->getWidget('wndMain') );
    
    $dlg->set_position('GTK_WIN_POS_MOUSE');

    # Show the dialog
    #$dlg->set_modal(1);
    $dlg->show_all();
    #$dlg->present();  #  raise to top

    # Make object
    my $self = { dlgxml => $dlgxml, dlg => $dlg };
    bless $self, $class;
    
    #$dlg->signal_connect (
    #    'stop_pulsing'   => \&pulsate_stop,
    #    $self,
    #);

    $self->{progress_update_interval} = $progress_update_interval;

    my $widget = $self->{dlgxml}->get_widget('label');
    if ($widget) {
        $widget->set_markup($text);
    }
    $self->update ($text, 0, 1);

    #$self->{last_update_time} = [gettimeofday];

    return $self;
}

sub destroy {
    my $self = shift;
    
    $self->pulsate_stop;
    
    $self->{dlg}->destroy();
    
    return;
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
    
    return if $self->{last_update_time}
              && !(  tv_interval ($self->{last_update_time})
                    > $self->{progress_update_interval}
                   );

    $self->{last_update_time} = [gettimeofday];

    #$self->{dlg}->present;  #  raise to top

    # update dialog
    my $widget = $self->{dlgxml}->get_widget('label');
    if ($widget) {
        $widget->set_markup("<b>$text</b>");
    }

    my $bar = $self->{dlgxml}->get_widget('progressbar');
    
    if (not defined $bar) {
        Biodiverse::GUI::ProgressDialog::Cancel->throw(
            message  => "Progress bar closed, operation cancelled",
        );
    }
    
    $self->{pulse} = 0;
    
    $bar->set_fraction($progress);

    while (Gtk2->events_pending) { Gtk2->main_iteration(); }

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
    
    #$self -> update ($text, $progress);  #  We are avoiding pulsation for the moment...
    #return;

    if ($progress < 0 || $progress > 1) {
        Biodiverse::GUI::ProgressDialog::Bounds->throw(
            message  => "ERROR [ProgressDialog] progress is $progress (not between 0 & 1)",
        );
    }
    else {
        # update dialog
        my $widget = $self->{dlgxml}->get_widget('label');
        $widget -> set_markup("<b>$text</b>") if $widget;
        
        my $bar = $self->{dlgxml}->get_widget('progressbar');
        $bar -> set_pulse_step ($progress);
        #$bar -> pulse;
        
        if (not $self->{pulse}) {  #  only set this if we aren't already pulsing
            print "Starting pulse\n";
            $self->{pulse} = 1;
            my $x = Glib::Timeout -> add(10, \&pulse_progress_bar, [$self, $bar]);
            #my $x = Glib::Timeout -> add(100, sub {pulse_progress_bar ( $self )});
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
        #$p_bar -> set_pulse_step (0.1);
        $p_bar -> pulse;
        return TRUE;  #  keep going
    }
    
    #print "[PROGRESS BAR] Stop pulsing\n";
    
    return FALSE;
    
}

1;
