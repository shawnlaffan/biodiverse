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

our $VERSION = '5.0';

use Glib;
use Gtk3;
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
    my $promise_current_label = $args{promise_current_label};

    my $hbox = Gtk3::HBox->new(0,2);
    
    # Text view
    my $text_buffer = Gtk3::TextBuffer->new;

    my $text_view = Gtk3::TextView->new_with_buffer($text_buffer);
    my $text_view_no_scroll = Gtk3::TextView->new_with_buffer($text_buffer);

    #  an expander has less visual impact than the previous approach
    my $expander = Gtk3::Expander->new('');

    my $self = {
        buffer                => $text_buffer,
        hbox                  => $hbox,
        text_view             => $text_view,
        is_def_query          => $is_def_query,
        expander              => $expander,
        current_text_view     => 'Frame',
        validated_conditions  => $condition_object, #  assumes it works
        promise_current_label => $promise_current_label,
    };
    bless $self, $class;

    # Syntax-check button
    my $syntax_button = Gtk3::Button->new;
    $syntax_button->set_image ( Gtk3::Image->new_from_stock('gtk-apply', 'button'));
    $syntax_button->signal_connect_swapped(clicked => \&on_syntax_check, $self);
    $syntax_button->set_tooltip_text('Check the validity of the spatial condition syntax');

    # Options button
    my $options_button = Gtk3::Button->new;
    $options_button->set_image ( Gtk3::Image->new_from_stock('gtk-properties', 'button'));
    $options_button->signal_connect_swapped(clicked => \&run_options_dialogue, $self);
    $options_button->set_tooltip_text('Control some of the processing options');

    my $tree_combo = $self->update_dendrogram_combo;
    $tree_combo->show_all;

    # Scrolled window for multi-line conditions
    my $scroll = Gtk3::ScrolledWindow->new;
    $scroll->set_policy('automatic', 'automatic');
    $scroll->set_shadow_type('in');
    $scroll->add( $text_view );

    # Framed text view for single-line conditions
    my $frame = Gtk3::Frame->new();
    $frame->add($text_view_no_scroll);

    my $hideable_widgets = [
        $scroll, $frame,
        $tree_combo,
        $options_button, $syntax_button,
    ];

    # HBox
    $hbox->pack_start($expander, 0, 0, 0);
    $hbox->pack_start($scroll, 1, 1, 0);
    $hbox->pack_start($frame, 1, 1, 0);
    $hbox->pack_start($tree_combo, 0, 1, 0);
    $hbox->pack_start($options_button, 0, 0, 0);
    $hbox->pack_end($syntax_button, 0, 0, 0);
    $hbox->show_all();

    $self->{tree_combo} = $tree_combo;

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
        my $visible = !$expander->get_expanded;
        foreach my $widget (@$hideable_widgets) {
            if (not $widget =~ 'Button|ComboBox' and not $widget =~ $self->{current_text_view}) {
                $widget->hide;  # hide the inactive textview regardless
            }
            else {
                $widget->set_visible($visible);
            }
        }
    };
    $expander->set_tooltip_text (
        'Show or hide the edit box and other widgets.  '
      . 'Use this to free up some screen real estate.'
    );
    $expander->signal_connect_swapped (
        activate => $expander_cb,
        $self,
    );
    $expander->set_expanded(!$start_hidden);

    my $visible = !$start_hidden;
    foreach my $widget (@$hideable_widgets) {
        if (not $widget =~ 'Button|ComboBox' and not $widget =~ $self->{current_text_view}) {
            $widget->hide;  # hide the inactive textview regardless
        }
        else {
            $widget->set_visible($visible);
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
            conditions            => $expr,
            basedata_ref          => $bd,
            promise_current_label => $self->{promise_current_label},
            tree_ref              => $self->get_tree_ref,
        );
    };
    #croak $EVAL_ERROR if $EVAL_ERROR;
    #croak "AAAAAAAAAARRRRRRGGGGHHHH" if !$spatial_conditions;

    my $result_hash = $spatial_conditions->verify;

    if (! ($result_hash->{ret} eq 'ok' and $show_ok eq 'no_ok')) {
        my $dlg = Gtk3::MessageDialog->new(
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
    return if !defined $conditions;
    # croak "Conditions not yet validated\n" if !defined $conditions;

    my $options = $self->get_options;
    $conditions->set_no_recycling_flag ($options->{no_recycling});
    $conditions->set_ignore_spatial_index_flag ($options->{ignore_spatial_index});

    return $conditions;
}

sub get_tree_ref {
    my $self = shift;

    my $combo = $self->{tree_combo};
    return if !$combo;

    my $iter = $combo->get_active_iter;
    my $tree_ref = $iter ? $combo->get_model->get($iter, 1) : undef;

    if ($tree_ref eq 'no tree') {
        $tree_ref = undef;
    }
    elsif ($tree_ref eq 'project') {
        my $gui = Biodiverse::GUI::GUIManager->instance;
        $tree_ref = $gui->get_project->get_selected_phylogeny;
    }

    return $tree_ref;
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

    my $dlg = Gtk3::Dialog->new (
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
    

    my $table = Gtk3::Table->new(2, 2, 0);
    $table->set_row_spacings(5);
    $table->set_col_spacings(20);

    my @tb_props = (['expand', 'fill'], 'shrink', 0, 0);
    my $tip_text;

    my $row = 0;
    my $sp_index_label    = Gtk3::Label->new ('Ignore spatial index?');
    my $sp_index_checkbox = Gtk3::CheckButton->new;
    $sp_index_checkbox->set_active ($options->{ignore_spatial_index});
    $table->attach($sp_index_label,    0, 1, $row, $row+1, @tb_props);
    $table->attach($sp_index_checkbox, 1, 2, $row, $row+1, @tb_props);
    $tip_text = 'Set this to on if the spatial condition does not work properly when the BaseData has a spatial index set.';
    foreach my $widget ($sp_index_label, $sp_index_checkbox) {
        $widget->set_has_tooltip(1);
        $widget->set_tooltip_text ($tip_text);
    }

    $row++;
    my $recyc_label = Gtk3::Label->new ('Turn off recycling?');
    my $recyc_checkbox = Gtk3::CheckButton->new;
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

sub update_dendrogram_combo {
    my $self = shift;

    my $combobox = Gtk3::ComboBox->new;

    my $renderer_text = Gtk3::CellRendererText->new();
    $combobox->pack_start($renderer_text, 1);
    $combobox->add_attribute($renderer_text, "text", 0);

    #  Clear the current entries.
    #  We need to load a new ListStore to avoid crashes due
    #  to them being destroyed somewhere in the refresh process
    #  (Not sure that is still the case)
    my $model = Gtk3::ListStore->new('Glib::String', 'Glib::Scalar');

    my @combo_items;

    my $output_ref = eval {$self->get_validated_conditions};
    if ($output_ref && $output_ref->can('get_tree_ref') && $output_ref->get_tree_ref) {
        my $iter = $model->append();
        $model->set( $iter, 0 => 'analysis', 1 =>  $output_ref->get_tree_ref);
        push @combo_items, 'analysis';
    }

    foreach my $option ('no tree', 'project') {
        my $iter = $model->append();
        $model->set( $iter, 0 => $option, 1 => $option );
        push @combo_items, $option;
    }

    my $list = Biodiverse::GUI::GUIManager->instance->get_project->get_phylogeny_list;
    foreach my $tree (@$list) {
        my $name = $tree->get_name;
        my $iter = $model->append();
        $model->set( $iter, 0 => $name, 1 => $tree );
    }

    $combobox->set_model ($model);

    state $tooltip = <<~'EOT';
        Choose the tree to use in the spatial conditions.

        The remainder of the options are the trees available at
        the project level.  Note that this set is not updated as
        trees are added to and removed from the project.
        Changes can be triggered by closing and reopening the tab.
        EOT
    ;

    $combobox->set_tooltip_text ($tooltip);
    $combobox->set_active(0);
    # $combobox->show_all;

    return $combobox;
}


1;

