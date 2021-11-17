package Biodiverse::GUI::SpatialParams;

=head1 NAME

Spatial params



=head1 Overview

Class that implements the widgets for entering spatial params, with:
  * multi-line editing
  * syntax-check

=cut

use 5.010;
use strict;
use warnings;
use Carp;

use English qw { -no_match_vars };

our $VERSION = '3.99_002';

use Glib;
use Gtk2;
use Biodiverse::GUI::GUIManager;
use Biodiverse::SpatialConditions;
use Biodiverse::SpatialConditions::DefQuery;

use parent qw /Biodiverse::Common/;  #  need get/set_param

sub new {
    my $class = shift;
    my %args = @_;

    my $initial_text = $args{initial_text} // '';
    my $start_hidden = $args{start_hidden};
    my $is_def_query = $args{is_def_query};
    my $condition_object = $args{condition_object};

    my $hbox = Gtk2::HBox->new(0,2);
    
    # Text view
    my $text_buffer = Gtk2::TextBuffer->new;

    my $text_view = Gtk2::TextView->new_with_buffer($text_buffer);
    my $text_view_no_scroll = Gtk2::TextView->new_with_buffer($text_buffer);

    #  an expander has less visual impact than the previous approach
    my $expander = Gtk2::Expander->new();

    my $self = {
        buffer       => $text_buffer,
        hbox         => $hbox,
        text_view    => $text_view,
        is_def_query => $is_def_query,
        expander     => $expander,
        current_text_view => 'Frame',
        validated_conditions => $condition_object, #  assumes it works
    };
    bless $self, $class;

    # Syntax-check button
    my $syntax_button = Gtk2::Button->new;
    $syntax_button->set_image ( Gtk2::Image->new_from_stock('gtk-apply', 'button'));
    $syntax_button->signal_connect_swapped(clicked => \&on_syntax_check, $self);
    $syntax_button->set_tooltip_text('Check the validity of the spatial condition syntax');

    # Options button
    my $options_button = Gtk2::Button->new;
    $options_button->set_image ( Gtk2::Image->new_from_stock('gtk-properties', 'button'));
    $options_button->signal_connect_swapped(clicked => \&run_options_dialogue, $self);
    $options_button->set_tooltip_text('Control some of the processing options');

    # Scrolled window for multi-line conditions
    my $scroll = Gtk2::ScrolledWindow->new;
    $scroll->set_policy('automatic', 'automatic');
    $scroll->set_shadow_type('in');
    $scroll->add( $text_view );

    # Framed text view for single-line conditions
    my $frame = Gtk2::Frame->new();
    $frame->add($text_view_no_scroll);

    my $hideable_widgets = [$scroll, $frame, $options_button, $syntax_button];

    # HBox
    $hbox->pack_start($expander, 0, 0, 0);
    $hbox->pack_start($scroll, 1, 1, 0);
    $hbox->pack_start($frame, 1, 1, 0);
    $hbox->pack_start($options_button, 0, 0, 0);
    $hbox->pack_end($syntax_button, 0, 0, 0);
    $hbox->show_all();

    my $cb_text_buffer = sub {
        if ($text_buffer->get_line_count > 1) {
            $scroll->show;
            $frame->hide;
            $text_view->grab_focus;
            $self->{current_text_view} = 'Scroll';
        }
        else {
            $scroll->hide;
            $frame->show;
            $text_view_no_scroll->grab_focus;
            $self->{current_text_view} = 'Frame';
        }
    };
    $text_buffer->signal_connect_swapped (
        changed => $cb_text_buffer,
    );
    $text_buffer->set_text($initial_text);
    $cb_text_buffer->();


    my $expander_cb = sub {
        my $expand = !$expander->get_expanded;
        my $method = $expand ? 'show' : 'hide';
        foreach my $widget (@$hideable_widgets) {
            if (not $widget =~ 'Button' and not $widget =~ $self->{current_text_view}) {
                $widget->hide;  # hide the inactive textview regardless
            }
            else {
                $widget->$method;
            }
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
        if (not $widget =~ 'Button' and not $widget =~ $self->{current_text_view}) {
            $widget->hide;  # hide the inactive textview regardless
        }
        else {
            $widget->$method;
        }
    }

    $hbox->set_no_show_all (1);

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
            $gui->get_object('wndMain'),
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

    my $conditions = $self->{validated_conditions};
    croak "Conditions not yet validated\n" if !defined $conditions;

    my $options = $self->get_options;
    $conditions->set_no_recycling_flag ($options->{no_recycling});
    $conditions->set_ignore_spatial_index_flag ($options->{ignore_spatial_index});

    return $conditions;
}

sub get_object {
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

sub run_options_dialogue {
    my $self = shift;

    my $dlg = Gtk2::Dialog->new (
        'Spatial conditions options',
        undef,
        'modal',
        'gtk-cancel' => 'cancel',
        'gtk-ok' => 'ok',
    );

    my $options = $self->{options};
    if (!$options) {
        my ($ignore_spatial_index, $no_recycling);
        if (my $cond_object = eval {$self->get_validated_conditions}) {
            $ignore_spatial_index = $cond_object->get_ignore_spatial_index_flag;
            $no_recycling = $cond_object->get_no_recycling_flag;
        }
        $self->{options} = {
            ignore_spatial_index => $ignore_spatial_index,
            no_recycling         => $no_recycling,
        };
        $options = $self->{options};
    }
    

    my $table = Gtk2::Table->new(2, 2);
    $table->set_row_spacings(5);
    $table->set_col_spacings(20);

    my @tb_props = (['expand', 'fill'], 'shrink', 0, 0);
    my $tip_text;

    my $row = 0;
    my $sp_index_label    = Gtk2::Label->new ('Ignore spatial index?');
    my $sp_index_checkbox = Gtk2::CheckButton->new;
    $sp_index_checkbox->set_active ($options->{ignore_spatial_index});
    $table->attach($sp_index_label,    0, 1, $row, $row+1, @tb_props);
    $table->attach($sp_index_checkbox, 1, 2, $row, $row+1, @tb_props);
    $tip_text = 'Set this to on if the spatial condition does not work properly when the BaseData has a spatial index set.';
    foreach my $widget ($sp_index_label, $sp_index_checkbox) {
        $widget->set_has_tooltip(1);
        $widget->set_tooltip_text ($tip_text);
    }

    $row++;
    my $recyc_label = Gtk2::Label->new ('Turn off recycling?');
    my $recyc_checkbox = Gtk2::CheckButton->new;
    $recyc_checkbox->set_active ($options->{no_recycling});
    $table->attach($recyc_label,    0, 1, $row, $row+1, @tb_props);
    $table->attach($recyc_checkbox, 1, 2, $row, $row+1, @tb_props);
    $tip_text = "Biodiverse tries to detect cases where it can recycle neighour sets and spatial results, and this can sometimes not work.\n"
     . 'Set this to on to stop Biodiverse checking for such cases.';
    foreach my $widget ($recyc_label, $recyc_checkbox) {
        $widget->set_has_tooltip(1);
        $widget->set_tooltip_text ($tip_text);
    }

    my $vbox = $dlg->get_content_area;
    $vbox->pack_start ($table, 0, 0, 0);
    $dlg->show_all;

    my $result = $dlg->run;

    if (lc($result) eq 'ok') {
        $options->{ignore_spatial_index} = $sp_index_checkbox->get_active;
        $options->{no_recycling}         = $recyc_checkbox->get_active;
    }

    $dlg->destroy;
    return;
}

sub get_options {
    my $self = shift;
    
    my $options = $self->{options} // {};
    
    return wantarray ? %$options : $options;
}


1;

