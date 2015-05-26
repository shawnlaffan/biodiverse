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

=item an optional GladeXML widget which contains a 'filechooser' widget
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

our $VERSION = '1.0_001';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::SpatialParams;
use Data::Dumper;

sub fill {
    my $params = shift;
    my $table  = shift;
    my $dlgxml = shift;

    # Ask object for parameters metadata
    my @extract_closures;

    my $tooltip_group = Gtk2::Tooltips->new;

    my $row = 0;
    
    #my $label_wrapper = Text::Wrapper->new(columns => 30);

  PARAM:
    foreach my $param (@$params) {
        # Add to the table a label with the name and some widget
        #
        # The extractor will be called after the dialogue is OK'd to get the parameter value
        # It returns (param_name, value)
#  debug
#use Scalar::Util qw /blessed/;
#if (!blessed $param) {
#    warn "Param not blessed";
#}
        my ($widget, $extractor) = generate_widget($param, $dlgxml);

        if ($extractor) {
            push @extract_closures, $extractor;
        }

        next PARAM if !$widget;  # might not be putting into table (eg: using the filechooser)

        # Add an extra row
        my ($rows) = $table->get('n-rows');
        $rows++;
        $table->set('n-rows' => $rows);

        # Make the label
        my $label = Gtk2::Label->new;
        $label->set_line_wrap(30);
        #my $label_text = $label_wrapper->wrap($param->{label_text} || $param->{name});
        my $label_text = $param->{label_text} || $param->{name};
        chomp $label_text;
        $label->set_alignment(0, 0.5);
        $label->set_text( $label_text );

        my $fill_flags = 'fill';
        if ($param->{type} =~ 'text') {
            $fill_flags = ['expand', 'fill']
        }

        if ($param->{type} eq 'comment') {
            #  reflow the label text
            $label_text =~ s/(?<=\w)\n(?!\n)/ /g;
            $label->set_text( $label_text );

            $table->attach($label,  0, 2, $rows, $rows + 1, 'fill', [], 0, 0);
        }
        else {
            $table->attach($label,  0, 1, $rows, $rows + 1, 'fill', [], 0, 0);
            $table->attach($widget, 1, 2, $rows, $rows + 1, $fill_flags, [], 0, 0);
        }

        # Add a tooltip
        my $tip_text = $param->get_tooltip;
        if ($tip_text) {
            $tooltip_group->set_tip($widget, $tip_text, undef);
        }

        # widgets are sensitive unless explicitly told otherwise
        $widget->set_sensitive (exists $param->{sensitive} ? $param->{sensitive} : 1);  

        $label->show;
        if ($param->{type} ne 'comment') {
            $widget->show;
        }
    }
    
    $table->show_all;  #  sometimes we have compound widgets not being shown

    $tooltip_group->enable();
    return \@extract_closures;
}

sub extract {
    my $extractors = shift;

    # We call all the extractor closures which get values from the widgets
    my @params;
    foreach my $extractor (@$extractors) {
        #print $extractor->();
        #print "\n";
        push @params, $extractor->();
    }
    return \@params;
}

# Generates widget + extractor for some parameter
sub generate_widget {
    my $param = $_[0];

    my $type = $param->get_type;

    my @valid_choices = qw {
        file
        integer
        float
        boolean
        choice
        spatial_conditions
        comment
        text_one_line
    };
    my %valid_choices_hash;
    @valid_choices_hash{@valid_choices} = (1) x scalar @valid_choices;

    croak "Unsupported parameter type $type\n"
        if ! exists $valid_choices_hash{$type};

    
    #return if $type eq 'comment';  #  no callback in this case

    my $sub_name = 'generate_' . $type;

    my @results = eval "$sub_name (\@_)";
    croak "Unsupported parameter type $type \n$EVAL_ERROR\n" if $EVAL_ERROR;

    return @results;
}

sub generate_choice {
    my $param = shift;

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

sub generate_file {
    my $param  = shift;
    my $dlgxml = shift;

    # The dialog already has a filechooser widget. We just return an extractor function
    my $chooser = $dlgxml->get_widget('filechooser');

    use Cwd;
    $chooser->set_current_folder_uri(getcwd());

    my $extract = sub { return ($param->{name}, $chooser->get_filename); };
    return (undef, $extract);
}

sub generate_comment {
    my $param  = shift;
    #my $dlgxml = shift;

    #  just a placeholder
    my $label = Gtk2::Label->new;
    $label->set_line_wrap(30);
    $label->set_selectable(1);

    return ($label, undef);
}


sub generate_integer {
    my $param = shift;

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
    my $param = shift;
    
    my $default = $param->get_default || 0;
    my $digits  = $param->get_digits  || 2;
    my $incr    = $param->get_increment || 0.1;

    my $adj = Gtk2::Adjustment->new($default,0, 10000000, $incr, $incr * 10, 0);
    my $spin = Gtk2::SpinButton->new($adj, $incr, $digits);

    my $extract = sub { return ($param->get_name, $spin->get_value); };
    return ($spin, $extract);
}

sub generate_boolean {
    my $param = shift;

    my $default = $param->get_default || 0;
    
    my $checkbox = Gtk2::CheckButton->new;
    $checkbox->set(active => $default);

    my $extract = sub { return ($param->get_name, $checkbox->get_active); };

    return ($checkbox, $extract);
}

sub generate_spatial_conditions {
    my $param = shift;

    my $default = $param->get_default || '';

    my $sp = Biodiverse::GUI::SpatialParams->new(initial_text => $default);

    my $extract = sub { return ($param->{name}, $sp->get_text); };

    return ($sp->get_widget, $extract);
}

sub generate_text_one_line {
    my $param = shift;
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


1;

