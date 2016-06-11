package Biodiverse::GUI::ParametersTable;


=head1 NAME

Parameters Table



=head1 Overview

Code that fills a table with widgets for entry various parameter fields




=head1 Methods

=head2 fill

The widgets are generated from metadata passed to the fill function
which has arguments

=over 4

=item the metadata array-of-hashes

=item the GtkTable widget

=item an optional widget which contains a 'filechooser' widget
This is used by the type='file' widget

=back

This returns an array of "extractor" functions. They return (parameter name, value) arrays

=head2 extract

This just calls the extractor functions and combines the results

=head2 Supported widget types: See example below

  [{ name => 'file', type => 'file' }, # GUI supports just one of these
   { name => 'format', type => 'choice', choices => ['CSV', 'Newick'], default => 0 },
   { name => 'max_clusters', type => 'float', default => 20 },
   { name => 'increment', type => 'integer', default => 5 },
   { name => 'Spatial', type => 'spatial_conditions', default => '$D < 5' },
   { name => 'use_length', type => 'boolean', default => 1 } ]
Note - all need to be blessed now (needs to update help for this)
=cut

use strict;
use warnings;
use 5.010;

use Glib;
use Gtk2;
#use Text::Wrapper;

use Carp;
use English qw { -no_match_vars };

our $VERSION = '1.99_002';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::SpatialParams;
use Data::Dumper;


sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    return $self;
}

sub fill {
    my ($self, $params, $table, $dlgxml, $get_innards_hash) = @_;
    $get_innards_hash //= {};

    # Ask object for parameters metadata
    my (@extract_closures, @widgets, %label_widget_pairs, $debug_hbox);

    my $tooltip_group = Gtk2::Tooltips->new;

    my $row = 0;

  PARAM:
    foreach my $param (@$params) {
        # Add to the table a label with the name and some widget
        #
        # The extractor will be called after the dialogue is OK'd to get the parameter value
        # It returns (param_name, value)

        my ($widget, $extractor) = $self->generate_widget($param, $dlgxml, $get_innards_hash);

        if ($extractor) {
            push @extract_closures, $extractor;
            push @widgets, $widget;
        }

        next PARAM if !$widget;  # might not be putting into table (eg: using the filechooser)
        
        my $param_name = $param->{name};

        # Make the label
        my $label_text = $param->{label_text} // $param_name;
        chomp $label_text;
        my $label = Gtk2::Label->new ($label_text);
        $label->set_line_wrap(30);
        #my $label_text = $label_wrapper->wrap($param->{label_text} || $param->{name});
        $label->set_alignment(0, 0.5);
        #$label->set_text( $label_text );

        my $fill_flags = 'fill';
        if ($param->{type} =~ 'text') {
            $fill_flags = ['expand', 'fill']
        }
        if ($param->{type} eq 'comment') {
            #  reflow the label text
            $label_text =~ s/(?<=\w)\n(?!\n)/ /g;
            $label->set_text( $label_text );
            $widget = Gtk2::HBox->new;
        }

        $label_widget_pairs{$param_name} = [$label, $widget];

        my $rows = $table->get('n-rows');

        my $box_group_name = $param->get_box_group;
        my ($hbox, $added_hbox_row);
        if (defined $box_group_name) {
            if (!$self->{box_groups}{$box_group_name}) {
                # Add an extra row
                $rows++;
                $table->set('n-rows' => $rows);
                $added_hbox_row++;
                $hbox = $self->{box_groups}{$box_group_name} = Gtk2::HBox->new;
                if ($box_group_name eq 'Debug') {
                    $debug_hbox //= $hbox;
                }
                else {
                    my $l = Gtk2::Label->new ($box_group_name);
                    $l->set_alignment(0, 0.5);
                    $table->attach($l,  0, 1, $rows, $rows + 1, 'fill', [], 0, 0);
                    $table->attach($hbox, 1, 2, $rows, $rows + 1, $fill_flags, [], 0, 0);
                    $l->show;
                }
            }
            $hbox //= $self->{box_groups}{$box_group_name};
            $hbox->pack_start($label, 0, 0, 0);
            $hbox->pack_start($widget, 0, 0, 0);
            if ($box_group_name ne 'Debug'){
                $hbox->show_all;
            }
        }
        else {
            $rows++;
            $table->set('n-rows' => $rows);
            $table->attach($label,  0, 1, $rows, $rows + 1, 'fill', [], 0, 0);
            $table->attach($widget, 1, 2, $rows, $rows + 1, $fill_flags, [], 0, 0);
        }

        # Add a tooltip
        my $tip_text = $param->get_tooltip;
        if ($tip_text) {
            $tooltip_group->set_tip($widget, $tip_text, undef);
        }

        # widgets are sensitive unless explicitly told otherwise
        $widget->set_sensitive ($param->get_always_sensitive ? 1 : $param->get_sensitive // 1);

        $label->show;
        if ($param->{type} ne 'comment') {
            $widget->show_all;
        }
    }

    #  hack - make sure debug hbox is last in table
    if ($debug_hbox) {
        #$table->remove($debug_hbox);
        my $label = Gtk2::Label->new ('Debug');
        $label->set_line_wrap(30);
        $label->set_alignment(0, 0.5);

        my $rows = $table->get('n-rows');
        $rows++;
        $table->set('n-rows' => $rows);
        $table->attach($label,  0, 1, $rows, $rows + 1, 'fill', [], 0, 0);
        $table->attach($debug_hbox, 1, 2, $rows, $rows + 1, 'fill', [], 0, 0);
        $label->show;
        $debug_hbox->show_all;
    }

    #  hack for spatial conditions widgets so we don't show both edit views
    foreach my $object (values %$get_innards_hash) {
        next if !blessed $object;
        next if not (blessed $object) =~ /Spatial/;
        #  trigger a change
        my $text = $object->get_text;
        if (length $text) {
            $object->{buffer}->set_text ($text);
        }
        else {
            $object->{buffer}->set_text (' ');
            $object->{buffer}->set_text ($text);
        }
    }

    $tooltip_group->enable();

    $self->{extractors} = \@extract_closures;
    $self->{widgets}    = \@widgets;
    $self->{label_widget_pairs} = \%label_widget_pairs;
    return $self->{extractors};
}

sub get_label_widget_pairs_hash {
    my $self = shift;
    return $self->{label_widget_pairs};
}

sub extract {
    my ($self, $extractors) = @_;
    $extractors //= $self->{extractors};

    # We call all the extractor closures which get values from the widgets
    my @params;
    foreach my $extractor (@$extractors) {
        #print $extractor->();
        #print "\n";
        push @params, $extractor->();
    }
    return wantarray ? @params : \@params;
}

# Generates widget + extractor for some parameter
sub generate_widget {
    my ($self, @args) = @_;

    my $param = $args[0];
    my $type = $param->get_type;

    my @valid_choices = qw {
        file
        integer
        float
        boolean
        choice
        choice_index
        spatial_conditions
        comment
        text_one_line
        text
    };
    my %valid_choices_hash;
    @valid_choices_hash{@valid_choices} = (1) x scalar @valid_choices;

    croak "Unsupported parameter type $type\n"
        if ! exists $valid_choices_hash{$type};


    #return if $type eq 'comment';  #  no callback in this case

    my $sub_name = 'generate_' . $type;

    my @results = $self->$sub_name (@args);
    croak "Unsupported parameter type $type \n$EVAL_ERROR\n" if $EVAL_ERROR;

    return @results;
}

sub generate_choice {
    my ($self, $param) = @_;

    my $combo = Gtk2::ComboBox->new_text;

    # Fill the combo
    foreach my $choice (@{$param->{choices}}) {
                #print "Appending $choice\n";
        $combo->append_text($choice);
    }

    # select default
    my $default = $param->get_default // 0;
    $combo->set_active($default);

    # Extraction closure
    my $extract = sub {
        return ($param->{name}, $combo->get_active_text);
    };

    # Wrap inside an EventBox so that tooltips work
    my $ebox = Gtk2::EventBox->new;
    $ebox->add($combo);

    return ($ebox, $extract);
}

#  we want the index, not the text
sub generate_choice_index {
    my ($self, $param) = @_;

    my $combo = Gtk2::ComboBox->new_text;

    # Fill the combo
    foreach my $choice (@{$param->{choices}}) {
                #print "Appending $choice\n";
        $combo->append_text($choice);
    }

    # select default
    my $default = $param->get_default // 0;
    $combo->set_active($default);

    # Extraction closure
    my $extract = sub {
        return ($param->{name}, $combo->get_active);
    };

    # Wrap inside an EventBox so that tooltips work
    my $ebox = Gtk2::EventBox->new;
    $ebox->add($combo);

    return ($ebox, $extract);
}

sub generate_file {
    my ($self, $param, $dlgxml) = @_;

    # The dialog already has a filechooser widget. We just return an extractor function
    my $chooser = $dlgxml->get_object('filechooser');

    use Cwd;
    $chooser->set_current_folder_uri(getcwd());

    my $extract = sub { return ($param->{name}, $chooser->get_filename); };
    return (undef, $extract);
}

sub generate_comment {
    my ($self, $param) = @_;

    #  just a placeholder
    my $label = Gtk2::Label->new;
    $label->set_line_wrap(30);
    $label->set_selectable(1);

    return ($label, undef);
}


sub generate_integer {
    my ($self, $param) = @_;

    my $default = $param->get_default || 0;
    my $incr    = $param->get_increment || 1;
    my $min     = $param->get_min // 0;
    my $max     = $param->get_max // 10000000;

    my $adj = Gtk2::Adjustment->new($default, $min, $max, $incr, $incr * 10, 0);
    my $spin = Gtk2::SpinButton->new($adj, $incr, 0);

    my $extract = sub { return ($param->{name}, $spin->get_value_as_int); };
    return ($spin, $extract);
}

sub generate_float {
    my ($self, $param) = @_;

    my $default = $param->get_default || 0;
    my $digits  = $param->get_digits  || 2;
    my $incr    = $param->get_increment || 0.1;

    my $adj = Gtk2::Adjustment->new($default,0, 10000000, $incr, $incr * 10, 0);
    my $spin = Gtk2::SpinButton->new($adj, $incr, $digits);

    my $extract = sub { return ($param->get_name, $spin->get_value); };
    return ($spin, $extract);
}

sub generate_boolean {
    my ($self, $param) = @_;

    my $default = $param->get_default || 0;

    my $checkbox = Gtk2::CheckButton->new;
    $checkbox->set(active => $default);

    my $extract = sub { return ($param->get_name, $checkbox->get_active); };

    return ($checkbox, $extract);
}

sub generate_spatial_conditions {
    my ($self, $param) = @_;
    my $get_object_hash = pop;  # clunky way of getting the object back

    my $default = $param->get_default || '';

    my $sp = Biodiverse::GUI::SpatialParams->new(initial_text => $default);

    my $extract = sub { return ($param->{name}, $sp->get_text); };

    $get_object_hash->{$param->get_name} = $sp;

    return ($sp->get_object, $extract);
}

sub generate_text_one_line {
    my ($self, $param) = @_;
    my $default = $param->get_default // '';

    my $text_buffer = Gtk2::TextBuffer->new;

    # Text view
    $text_buffer->set_text($default);
    my $text_view = Gtk2::TextView->new_with_buffer($text_buffer);
    my $frame = Gtk2::Frame->new();
    $frame->add($text_view);

    my $extract = sub {
        my ($start, $end) = $text_buffer->get_bounds();
        my $text = $text_buffer->get_text($start, $end, 0);
        return ($param->{name}, $text);
    };

    return ($frame, $extract);
}

sub generate_text {
    my ($self, $param) = @_;
    my $default = $param->get_default // '';

    my $text_buffer = Gtk2::TextBuffer->new;

    # Text view
    $text_buffer->set_text($default);
    my $text_view = Gtk2::TextView->new_with_buffer($text_buffer);

    # Scrolled window for multi-line conditions
    my $scroll = Gtk2::ScrolledWindow->new;
    $scroll->set_policy('automatic', 'automatic');
    $scroll->set_shadow_type('in');
    $scroll->add( $text_view );


    my $extract = sub {
        my ($start, $end) = $text_buffer->get_bounds();
        my $text = $text_buffer->get_text($start, $end, 0);
        return ($param->{name}, $text);
    };

    return ($scroll, $extract);
}


1;
