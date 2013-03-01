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
   { name => 'Spatial', type => 'spatial_params', default => '$D < 5' },
   { name => 'use_length', type => 'boolean', default => 1 } ]

=cut

use strict;
use warnings;
use Glib;
use Gtk2;

use Carp;
use English qw { -no_match_vars };

our $VERSION = '0.18_004';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::SpatialParams;
use Data::Dumper;

sub fill {
    my $params = shift;
    my $table = shift;
    my $dlgxml = shift;

    # Ask object for parameters metadata
    my @extract_closures;

    my $tooltip_group = Gtk2::Tooltips->new;

    my $row = 0;
    foreach my $param (@$params) {
        # Add to the table a label with the name and some widget
        #
        # The extractor will be called at the end to get the parameter value
        # It returns (param_name, value)
        
        my ($widget, $extractor) = generateWidget($param, $dlgxml);

        if ($widget) { # might not be putting into table (eg: using the filechooser)

            # Add an extra row
            my ($rows) = $table->get('n-rows');
            $rows++;
            $table->set('n-rows' => $rows);

            # Make the label
            my $label = Gtk2::Label->new;
            $label->set_alignment(0, 0.5);
            $label->set_text( $param->{label_text} || $param->{name} );

            $table->attach($label,  0, 1, $rows, $rows + 1, 'fill', [], 0, 0);
            $table->attach($widget, 1, 2, $rows, $rows + 1, 'fill', [], 0, 0);

            # Add a tooltip
            my $tip_text = $param->{tooltip};
            if ($tip_text) {
                $tooltip_group->set_tip($widget, $tip_text, undef);
            }
            #my $barry = exists $param->{sensitive} ? $param->{editable} : 1;
                        # widgets are sensitive unless explicitly told otherwise
            $widget -> set_sensitive (exists $param->{sensitive} ? $param->{sensitive} : 1);  

            $label->show;
            $widget->show;
        }

        push @extract_closures, $extractor;

    }
    
    $tooltip_group->enable();
    return \@extract_closures;
}

sub extract {
    my $extractors = shift;

    # We call all the extractor closures which get values from the widgets
    my @params;
    foreach my $extractor (@$extractors) {
        #print &$extractor();
        #print "\n";
        push @params, &$extractor();
    }
    return \@params;
}

# Generates widget + extractor for some parameter
sub generateWidget {
    my $param = $_[0];
    
    my $type = $param->{type};

    my @valid_choices = qw {
        file
        integer
        float
        boolean
        choice
        spatial_params
    };
    my %valid_choices_hash;
    @valid_choices_hash{@valid_choices} = (1) x scalar @valid_choices;
    
    croak "Unsupported parameter type $type\n"
        if ! exists $valid_choices_hash{$type};

    my $sub_name = 'generate_' . $type;
    
    my @results = eval "$sub_name (\@_)";
    croak "Unsupported parameter type $type\n" if $EVAL_ERROR;
    
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
    if (exists $param->{default}) {
        $combo->set_active($param->{default});
    }

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
    my $param = shift;
    my $dlgxml = shift;

    # The dialog already has a filechooser widget. We just return an extractor function
    my $chooser = $dlgxml->get_widget('filechooser');
    my $extract = sub { return ($param->{name}, $chooser->get_filename); };
    return (undef, $extract);
}

sub generate_integer {
    my $param = shift;
    
    my $default = $param->{default} || 0;
    my $incr    = $param->{increment} || 1;
    
    my $adj = Gtk2::Adjustment->new($default, 0, 10000000, $incr, $incr * 10, 0);
    my $spin = Gtk2::SpinButton->new($adj, $incr, 0);

    my $extract = sub { return ($param->{name}, $spin->get_value_as_int); };
    return ($spin, $extract);
}

sub generate_float {
    my $param = shift;
    
    my $default = $param->{default} || 0;
    my $digits  = $param->{digits} || 2;
    my $incr    = $param->{increment} || 0.1;

    my $adj = Gtk2::Adjustment->new($default,0, 10000000, $incr, $incr * 10, 0);
    my $spin = Gtk2::SpinButton->new($adj, $incr, $digits);

    my $extract = sub { return ($param->{name}, $spin->get_value); };
    return ($spin, $extract);
}

sub generate_boolean {
    my $param = shift;
    my $default = $param->{default} || 0;
    
    my $checkbox = Gtk2::CheckButton->new;
    $checkbox->set(active => $default);

    my $extract = sub { return ($param->{name}, $checkbox->get_active); };
    return ($checkbox, $extract);
}

sub generate_spatial_params {
    my $param = shift;
    my $default = $param->{default} || '';

    my $sp = Biodiverse::GUI::SpatialParams->new($default);

    my $extract = sub { return ($param->{name}, $sp->get_text); };
    return ($sp->get_widget, $extract);
}

#sub generate_text_one_line {
#    my $param = shift;
#    my $default = $param->{default};  #  defaults to undef
#
#    my $text_buffer = Gtk2::TextBuffer->new;
#    
#    # Text view
#    $text_buffer->set_text($default);
#    my $text_view = Gtk2::TextView->new_with_buffer($text_buffer);
#        
#    my $extract = sub { return ($param->{name}, $text_buffer->get_text); };
#    return ($text_view -> get_widget, $extract);
#
#}


1;
