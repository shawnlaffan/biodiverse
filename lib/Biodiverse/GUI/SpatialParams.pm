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
use Carp;

use English qw { -no_match_vars };

our $VERSION = '0.99_006';

use Glib;
use Gtk2;
use Biodiverse::GUI::GUIManager;
use Biodiverse::SpatialConditions;
use Biodiverse::SpatialConditions::DefQuery;

use parent qw /Biodiverse::Common/;  #  need get/set_param

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

    #  an expander has less visual impact than the previous approach
    my $expander = Gtk2::Expander->new();

    my $self = {
        buffer       => $text_buffer,
        hbox         => $hbox,
        text_view    => $text_view,
        is_def_query => $is_def_query,
        expander     => $expander,
    };
    bless $self, $class;

    # Syntax-check button
    my $syntax_button = Gtk2::Button->new;
    $syntax_button->set_image ( Gtk2::Image->new_from_stock('gtk-apply', 'button') );
    $syntax_button->signal_connect_swapped(clicked => \&on_syntax_check, $self);

    # Scrolled window
    my $scroll = Gtk2::ScrolledWindow->new;
    $scroll->set_policy('automatic', 'automatic');
    $scroll->set_shadow_type('in');
    $scroll->add( $text_view );
    
    my $hideable_widgets = [$scroll, $syntax_button];

    # HBox
    $hbox->pack_start($expander, 0, 0, 0);
    $hbox->pack_start($scroll, 1, 1, 0);
    $hbox->pack_end($syntax_button, 0, 0, 0);
    $hbox->show_all();


    my $expander_cb = sub {
        my $expand = !$expander->get_expanded;
        my $method = $expand ? 'show' : 'hide';
        foreach my $widget (@$hideable_widgets) {
            $widget->$method;
        }
    };
    $expander->set_tooltip_text ('Show or hide the edit and verify boxes.  Use this to free up some screen real estate.');
    $expander->signal_connect_swapped (
        activate => $expander_cb,
        $self,
    );
    $expander->set_expanded(!$start_hidden);
    my $method = $start_hidden ? 'hide' : 'show';
    foreach my $widget (@$hideable_widgets) {
        $widget->$method;
    }

    return $self;
}


sub syntax_check {
    my $self = shift;
    return $self->on_syntax_check(@_);
}

sub on_syntax_check {
    my $self = shift;
    my $show_ok = shift || 'ok';

    my $gui = Biodiverse::GUI::GUIManager->instance;

    my $expr  = $self->get_text;
    my $class = $self->{is_def_query}
                ? 'Biodiverse::SpatialConditions::DefQuery'
                : 'Biodiverse::SpatialConditions';

    #  Get the basedata associated with this output.  If none then use the selected.
    my $bd = $self->get_param ('BASEDATA_REF') || $gui->get_project->get_selected_base_data;

    my $spatial_conditions = eval {
        $class->new (
            conditions   => $expr,
            basedata_ref => $bd,
        );
    };
    #croak $EVAL_ERROR if $EVAL_ERROR;
    #croak "AAAAAAAAAARRRRRRGGGGHHHH" if !$spatial_conditions;

    my $result_hash = $spatial_conditions->verify;

    if (! ($result_hash->{ret} eq 'ok' and $show_ok eq 'no_ok')) {
        my $dlg = Gtk2::MessageDialog->new(
            $gui->get_widget('wndMain'),
            'destroy-with-parent',
            $result_hash->{type},
            'ok',
            $result_hash->{msg},
        );

        $dlg->run();
        $dlg->destroy();
    }
    elsif ($result_hash->{ret} eq 'ok') {
        $self->{validated_conditions} = $spatial_conditions;
    }

    return $result_hash->{ret};
}

sub get_validated_conditions {
    my $self = shift;
    return $self->{validated_conditions};
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


#sub get_copy_widget {
#    my $self = shift;
#    
#    my $widget = Gtk2::ComboBox->new;
#}

1;

