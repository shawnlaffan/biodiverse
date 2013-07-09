package Biodiverse::GUI::SpatialParams;

=head1 NAME

Spatial params



=head1 Overview

Class that implements the widgets for entering spatial params, with:
  * multi-line editing
  * syntax-check

=cut

use strict;
use warnings;

use English qw { -no_match_vars };

our $VERSION = '0.18_007';

use Glib;
use Gtk2;
use Biodiverse::GUI::GUIManager;
use Biodiverse::SpatialParams;
use Biodiverse::SpatialParams::DefQuery;

use base qw /Biodiverse::Common/;  #  need get/set_param

sub new {
    my $class = shift;
    my $initial_text = shift;
    my $start_hidden = shift;
    my $is_def_query = shift;

    my $text_buffer = Gtk2::TextBuffer->new;
    my $hbox = Gtk2::HBox->new(0,2);
    # Text view
    $text_buffer->set_text($initial_text);
    my $text_view = Gtk2::TextView->new_with_buffer($text_buffer);

    my $self = {
        buffer       => $text_buffer,
        hbox         => $hbox,
        text_view    => $text_view,
        is_def_query => $is_def_query,
    };
    bless $self, $class;

    # Syntax-check button
    my $syntax_button = Gtk2::Button->new;
    $syntax_button->set_image ( Gtk2::Image->new_from_stock('gtk-apply', 'button') );
    $syntax_button->signal_connect_swapped(clicked => \&onSyntaxCheck, $self);

    # Scrolled window
    my $scroll = Gtk2::ScrolledWindow->new;
    $scroll->set_policy('automatic', 'automatic');
    $scroll->set_shadow_type('in');
    $scroll->add( $text_view );
    
    #  show/hide button
    #my $check_button = Gtk2::CheckButton->new ();
    my $check_button = Gtk2::ToggleButton->new_with_label('-');
    #$check_button->set (yalign => 0);
    $self->{check_button} = $check_button;
    
    $check_button->signal_connect_swapped (
        clicked => \&on_show_hide,
        $self,
    );
    $check_button->set_active (1);
    $check_button->set_has_tooltip (1);
    #$check_button->set_tooltip_text ($self->get_show_hide_tooltip);
    
    $self->{hideable_widgets} = [$scroll, $syntax_button];

    
    # HBox
    $hbox->pack_start($check_button, 0, 0, 0);
    $hbox->pack_start($scroll, 1, 1, 0);
    $hbox->pack_end($syntax_button, 0, 0, 0);
    $hbox->show_all();
    
    if ($start_hidden) {  #  triggers callback to hide them
        $check_button->set_active (0);
    }

    return $self;
}

sub on_show_hide {
    my $self = shift;
    
    my $check_button = $self->{check_button};
    
    my $active = $check_button->get_active;
    my $showhide = $active
                    ? 'show'
                    : 'hide';

    foreach my $widget (@{$self->{hideable_widgets}}) {
        $widget->$showhide;
    }

    if ($active) {
        $check_button->set_label ('-');
    }
    else {
        $check_button->set_label ('+');
    }
    
    $check_button->set_tooltip_text ($self->get_show_hide_tooltip);

    return;
}

sub get_show_hide_tooltip {
    my $self = shift;
    
    my $check_button = $self->{check_button};
    my $active = $check_button->get_active;

    my $text;
    if ($active) {
        $text = 'Hide the edit and verify boxes to '
                . 'free up some screen real estate';
    }
    else {
        $text = 'Show the edit and verify boxes';
    }

    return $text;
}

sub syntax_check {
    my $self = shift;
    return $self->onSyntaxCheck(@_);
}

sub onSyntaxCheck {
    my $self = shift;
    my $show_ok = shift || 'ok';

    my $gui = Biodiverse::GUI::GUIManager->instance;

    my $expr  = $self->get_text;
    my $class = $self->{is_def_query}
                ? 'Biodiverse::SpatialParams::DefQuery'
                : 'Biodiverse::SpatialParams';
    my $spatial_params = eval {
        $class->new (conditions => $expr);
    };

    #  Get the baedata associated with this output.  If none then use the selected.
    my $bd = $self->get_param ('BASEDATA_REF') || $gui->getProject->getSelectedBaseData;
    my $result_hash = $spatial_params->verify (basedata => $bd);

    if (! ($result_hash->{ret} eq 'ok' and $show_ok eq 'no_ok')) {
        my $dlg = Gtk2::MessageDialog->new(
            $gui->getWidget('wndMain'),
            'destroy-with-parent',
            $result_hash->{type},
            'ok',
            $result_hash->{msg},
        );

        $dlg->run();
        $dlg->destroy();
    }
    return $result_hash->{ret};
}

sub get_widget {
    my $self = shift;
    return $self->{hbox};
}

sub get_text {
    my $self = shift;
    my $text_buffer = $self->{buffer};

    my ($start, $end) = $text_buffer->get_bounds();
    return $text_buffer->get_text($start, $end, 0);
}

sub get_text_view {
    my $self = shift;
    return $self->{text_view};
}

sub on_hide {
    my $self = shift;
    
    my $widget = $self->get_widget;
    $widget->hide;
    $self->{hidden} = 1;
    
    return;
}

sub on_show {
    my $self = shift;
    
    my $widget = $self->get_widget;
    $widget->show;
    $self->{hidden} = 0;
    
    return;
}

#sub get_copy_widget {
#    my $self = shift;
#    
#    my $widget = Gtk2::ComboBox->new;
#}

1;
