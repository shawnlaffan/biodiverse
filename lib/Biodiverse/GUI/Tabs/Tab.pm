package Biodiverse::GUI::Tabs::Tab;
use strict;
use warnings;

our $VERSION = '0.16';

use Gtk2;
use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;
use Carp;


sub add_to_notebook {
    my $self = shift;
    my %args = @_;

    my $page = $args{page};
    my $label = $args{label};
    my $label_widget = $args{label_widget};

    $self->{notebook}   = $self->{gui}->getNotebook();
    $self->{notebook}->append_page_menu($page, $label, $label_widget);
    $self->{page}       = $page;
    $self->{gui}->addTab($self);
    $self->set_tab_reorderable($page);
    
    return;
}

sub getPageIndex {
    my $self = shift;
    my $page = shift || $self->{page};
    my $index = $self->{notebook}->page_num($page);
    return $index;
}

sub setPageIndex {
    my $self = shift;
    
    #  no-op now
    #$self->{page_index} = shift;
    
    return;
}

sub get_base_ref {
    my $self = shift;

    #  check all possibilities
    #  should really just have one
    foreach my $key (qw /base_ref basedata_ref selected_basedata_ref/) {
        if (exists $self->{$key}) {
            return $self->{$key};
        }
    }

    croak "Unable to access the base ref\n";
}

sub get_current_registration {
    my $self = shift;
    return $self->{current_registration};
}

sub update_current_registration {
    my $self = shift;
    my $object = shift;
    $self->{current_registration} = $object;
}

sub update_name {
    my $self = shift;
    my $new_name = shift;
    #$self->{current_registration} = $new_name;
    eval {$self->{label_widget} -> set_text ($new_name)};
    eval {$self->{title_widget} -> set_text ($new_name)};
    eval {$self->{tab_menu_label}->set_text ($new_name)};
    return;
}

sub remove {
    my $self = shift;
    if (exists $self->{current_registration}) {  #  deregister if necessary
        $self->{project}->registerInOutputsModel($self->{current_registration}, undef);
    }
    $self->{notebook}->remove_page( $self->getPageIndex );

    return;
}

sub set_tab_reorderable {
    my $self = shift;
    my $page = shift || $self->{page};

    $self->{notebook}->set_tab_reorderable($page, 1);

    return;
}

sub onClose {
    my $self = shift;
    $self->{gui}->removeTab($self);
    #print "[GUI] Closed tab - ", $self->getPageIndex(), "\n";
    return;
}

# Make ourselves known to the Outputs tab to that it
# can switch to this tab if the user presses "Show"
sub registerInOutputsModel {
    my $self = shift;
    my $output_ref = shift;
    my $tabref = shift; # either $self, or undef to deregister
    my $model = $self->{project} -> getBaseDataOutputModel();

    # Find iter
    my $iter;
    my $iter_base = $model->get_iter_first();

    while ($iter_base) {
        
        my $iter_output = $model->iter_children($iter_base);
        while ($iter_output) {
            if ($model->get($iter_output, MODEL_OBJECT) eq $output_ref) {
                $iter = $iter_output;
                last; #FIXME: do we have to look at other iter_bases, or does this iterate over entire level?
            }
            
            $iter_output = $model->iter_next($iter_output);
        }
        
        last if $iter; # break if found it
        $iter_base = $model->iter_next($iter_base);
    }

    if ($iter) {
        $model->set($iter, MODEL_TAB, $tabref);
        $self->{current_registration} = $output_ref;
    }
    
    return;
}

##########################################################
# Keyboard shortcuts
##########################################################

my $snooper_id;
my $handler_entered = 0;

# Called when user switches to this tab
#   installs keyboard-shortcut handler
sub setKeyboardHandler {
    my $self = shift;
    # Make CTRL-G activate the "go!" button (onRun)
    if ($snooper_id) {
        ##print "[Tab] Removing keyboard snooper $snooper_id\n";
        Gtk2->key_snooper_remove($snooper_id);
        $snooper_id = undef;
    }


    $snooper_id = Gtk2->key_snooper_install(\&hotkeyHandler, $self);
    ##print "[Tab] Installed keyboard snooper $snooper_id\n";
}

sub removeKeyboardHandler {
    my $self = shift;
    if ($snooper_id) {
        ##print "[Tab] Removing keyboard snooper $snooper_id\n";
        Gtk2->key_snooper_remove($snooper_id);
        $snooper_id = undef;
    }
}
    
# Processes keyboard shortcuts like CTRL-G = Go!
sub hotkeyHandler {
    my ($widget, $event, $self) = @_;
    my $retval;

    # stop recursion into onRun if shortcut triggered during processing
    #   (this happens because progress-dialogs pump events..)

    return 1 if ($handler_entered == 1);

    $handler_entered = 1;

    if ($event->type eq 'key-press') {
        # if CTL- key is pressed
        if ($event->state >= ['control-mask']) {
            my $keyval = $event->keyval;
            #print $keyval . "\n";
            
            # Go!
            if ((uc chr $keyval) eq 'G') {
                $self->onRun();
                $retval = 1; # stop processing
            }

            # Close tab (CTRL-W)
            elsif ((uc chr $keyval) eq 'W') {
                if ($self->getRemovable) {
                    $self->{gui}->removeTab($self);
                    $retval = 1; # stop processing
                }
            }

            # Change to next tab
            elsif ($keyval eq Gtk2::Gdk->keyval_from_name ('Tab')) {
                #  switch tabs
                #print "keyval is $keyval (tab), state is " . $event->state . "\n";
                my $page_index = $self->getPageIndex;
                $self->{gui}->switchTab (undef, $page_index + 1); #  go right
            }
            elsif ($keyval eq Gtk2::Gdk->keyval_from_name ('ISO_Left_Tab')) {
                #  switch tabs
                #print "keyval is $keyval (left tab), state is " . $event->state . "\n";
                my $page_index = $self->getPageIndex;
                $self->{gui}->switchTab (undef, $page_index - 1); #  go left
            }
        }
    }

    $handler_entered = 0;
    $retval = 0; # continue processing
    return $retval;
}

sub onRun {} # default for tabs that don't implement onRun

sub getRemovable { return 1; } # default - tabs removable


1;
