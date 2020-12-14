package Biodiverse::GUI::CellPopup;

use 5.010;
use strict;
use warnings;

#use Data::Dumper;
use Carp;
use Scalar::Util qw /looks_like_number/;
use Sort::Key::Natural qw /natsort/;
use Ref::Util qw /is_ref is_arrayref is_hashref/;
use Biodiverse::Utilities qw/sort_list_with_tree_names_aa/;

our $VERSION = '3.1';

use Gtk2;

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Popup;
use Biodiverse::Indices;

# Information about neighbours
use constant LABELS_MODEL_NAME       => 0;
use constant LABELS_MODEL_COUNT_ALL  => 1;
use constant LABELS_MODEL_COUNT_SET1 => 2;
use constant LABELS_MODEL_COUNT_SET2 => 3;
use constant LABELS_MODEL_SET1       => 4; # whether label part of LABEL_HASH1
use constant LABELS_MODEL_SET2       => 5; # whether label part of LABEL_HASH2

use constant ELEMENTS_MODEL_NAME  => 0;
use constant ELEMENTS_MODEL_INNER => 1;
use constant ELEMENTS_MODEL_OUTER => 2;

=head1
Shows popup dialogs for cells in Spatial or Labels view
=cut
sub cell_clicked {
    my $element = shift;
    my $data = shift;

    # See top of Popup.pm
    my $sources = get_sources($element, $data);
    Biodiverse::GUI::Popup::show_popup($element, $sources);
}


# Adds appropriate sources (to the data sources combobox)
sub get_sources {
    my $element = shift;
    my $data    = shift;

    my %sources;

    if (blessed $data) {
        # Check if neighbours mode
        if (is_neighbours_mode($data)) {
            #print "[Cell popup] Adding neighbour lists\n";
            # Neighbour lists
    
            $sources{'Elements (set 1)'} = sub { show_neighbour_elements(@_, 'set1', $element, $data); };
            $sources{'Elements (set 2)'} = sub { show_neighbour_elements(@_, 'set2', $element, $data); };
            $sources{'Elements (all)'}   = sub { show_neighbour_elements(@_, 'all',  $element, $data); };
    
            $sources{'Labels (set 1)'} = sub { show_neighbour_labels(@_, 'set1', $element, $data); };
            $sources{'Labels (set 2)'} = sub { show_neighbour_labels(@_, 'set2', $element, $data); };
            $sources{'Labels (all)'}   = sub { show_neighbour_labels(@_, 'all',  $element, $data); };
            
            # Custom lists
            my @lists = $data->get_lists(element => $element);
            foreach my $name (@lists) {
                next if not defined $name;
                next if $name =~ /^_/; # leading underscore marks internal list
    
                #print "[Cell popup] Adding custom list $name\n";
                $sources{$name} = sub { show_output_list(@_, $name, $element, $data); };
            }
            
        }
        else {
            #print "[Cell popup] Adding all labels list\n";
            # All labels
            $sources{'Labels'}     = sub { show_all_labels (@_, $element, $data); };
            $sources{'Properties'} = sub { show_properties (@_, $element, $data); };
        }
    }
    else {
        #  do we ever get to this?  
        $sources{'Results'} = sub { show_list (@_); };
    }

    return \%sources;
}

##########################################################
# Neighbours
##########################################################

sub show_neighbour_elements {
    my $popup   = shift;    # anonymous arguments array (to use from signal handler)
    my $type    = shift;
    my $element = shift;
    my $data    = shift;

    # Create neighbours model if don't have one..
    if (not $popup->{neighbours_models}) {
        eval {
            $popup->{neighbours_models} = make_neighbours_model($element, $data);
        };
        
    }

    my $model = $popup->{neighbours_models}{elements};

    # Choose model to set
    my $new_model;
    if ($type eq 'set1') {
        # Central - filter the original model
        #print "[Cell popup] Setting elements model to filtered (set 1)\n";
        $new_model = Gtk2::TreeModelFilter->new($model);
        $new_model->set_visible_column(ELEMENTS_MODEL_INNER);
        $popup->set_list_model($new_model);
    }
    elsif ($type eq 'set2') {
        # Other - filter the original model
        #print "[Cell popup] Setting elements model to filtered (set 2)\n";
        $new_model = Gtk2::TreeModelFilter->new($model);
        $new_model->set_visible_column(ELEMENTS_MODEL_OUTER);
        $popup->set_list_model($new_model);
    }
    elsif ($type eq 'all') {
        # All - use original
        #print "[Cell popup] Setting elements model to original\n";
        $new_model = $model;
        $popup->set_list_model($new_model);
    }

    $popup->set_value_column(undef);
}

sub show_neighbour_labels {
    my $popup   = shift;    # anonymous arguments array (to use from signal handler)
    my $type    = shift;
    my $element = shift;
    my $data    = shift;

    # Create neighbours model if don't have one..
    $popup->{neighbours_models} ||= make_neighbours_model($element, $data);

    my $model = $popup->{neighbours_models}{labels};

    # Choose model to set
    my $new_model;
    if ($type eq 'set1') {
        # Central - filter the original model
        #print "[Cell popup] Setting labels model to filtered (inner)\n";
        $new_model = Gtk2::TreeModelFilter->new($model);
        $new_model->set_visible_column(LABELS_MODEL_SET1);
        $popup->set_list_model($new_model);

        $popup->set_value_column(LABELS_MODEL_COUNT_SET1);
    }
    elsif ($type eq 'set2') {
        # Other - filter the original model
        #print "[Cell popup] Setting labels model to filtered (outer)\n";
        $new_model = Gtk2::TreeModelFilter->new($model);
        $new_model->set_visible_column(LABELS_MODEL_SET2);
        $popup->set_list_model($new_model);

        $popup->set_value_column(LABELS_MODEL_COUNT_SET2);
    }
    elsif ($type eq 'all') {
        # All - use original
        #print "[Cell popup] Setting labels model to original\n";
        $new_model = $model;
        $popup->set_list_model($new_model);

        $popup->set_value_column(LABELS_MODEL_COUNT_ALL);
    }

}

sub make_neighbours_model {
    my $element = shift;
    my $data = shift;
    my $labels_model = Gtk2::ListStore->new(
        'Glib::String',
        'Glib::Int',
        'Glib::Int',
        'Glib::Int',
        'Glib::Boolean',
        'Glib::Boolean',
    );
    my $elements_model = Gtk2::ListStore->new(
        'Glib::String',
        'Glib::Boolean',
        'Glib::Boolean',
    );
    my $iter;

    say "[Cell popup] Generating neighbours hashes for $element";

    my $neighbours = find_neighbours($element, $data);

    # Make elements model - DON'T USE FAT COMMAS WITH CONSTANTS
    foreach my $elt (@{ $neighbours->{element_list1} }) {
        $iter = $elements_model->append;
        $elements_model->set(
            $iter,
            ELEMENTS_MODEL_NAME,  $elt,
            ELEMENTS_MODEL_INNER, 1,
            ELEMENTS_MODEL_OUTER, 0,
        );
    }
    foreach my $elt (@{ $neighbours->{element_list2} }) {
        $iter = $elements_model->append;
        $elements_model->set(
            $iter,
            ELEMENTS_MODEL_NAME,  $elt,
            ELEMENTS_MODEL_INNER, 0,
            ELEMENTS_MODEL_OUTER, 1,
        );
    }

    # Make labels model
    my $label_hash1    = $neighbours->{label_hash1};
    my $label_hash2    = $neighbours->{label_hash2};
    my $label_hash_all = $neighbours->{label_hash_all};
    my ($in1, $in2);

    foreach my $label (sort_list_with_tree_names_aa ([keys %{$label_hash_all}])) {

        $in1 = exists $label_hash1->{$label} ? 1 : 0;
        $in2 = exists $label_hash2->{$label} ? 1 : 0;

        $iter = $labels_model->append;
        $labels_model->set(
            $iter,
            LABELS_MODEL_NAME,       $label,
            LABELS_MODEL_COUNT_ALL,  $label_hash_all->{$label},
            LABELS_MODEL_COUNT_SET1, $label_hash1->{$label},
            LABELS_MODEL_COUNT_SET2, $label_hash2->{$label},
            LABELS_MODEL_SET1,       $in1,
            LABELS_MODEL_SET2,       $in2,
        );
    }
    return {elements => $elements_model, labels => $labels_model};
}

##########################################################
# Labels
##########################################################

sub show_all_labels {
    my $popup   = shift;
    my $element = shift;
    my $data    = shift;
    my $bd      = $data->get_param ('BASEDATA_REF') || $data;
    my $labels_are_numeric = $bd->labels_are_numeric;

    if (not $popup->{labels_model}) {
        my $labels_hash = $bd->get_labels_in_group_as_hash_aa ($element);

        my $smp_counts_are_floats = eval {$bd->sample_counts_are_floats};
        my $num_type = $smp_counts_are_floats
            ? 'Glib::Double'
            : 'Glib::Int';

        my $model = Gtk2::ListStore->new(
            'Glib::String',
            $num_type,
        );
        
        my @labels = $labels_are_numeric
            ? sort {$a <=> $b} keys %$labels_hash
            : sort_list_with_tree_names_aa ([keys %$labels_hash]);

        foreach my $label (@labels) {

            my $count = $labels_hash->{$label};
            my $iter  = $model->append;
            $model->set(
                $iter,
                0 => $label,
                1 => $count
            );
        }
        $popup->{labels_model} = $model;
    }

    $popup->set_list_model($popup->{labels_model});
    $popup->set_value_column(1);

    return;
}

sub show_properties {
    my $popup   = shift;
    my $element = shift;
    my $data    = shift;
    

    if (not $popup->{properties_model}) {
        my $bd  = $data->get_param ('BASEDATA_REF') || $data;

        my %properties;
        #  maybe we deleted it...
        if ($bd->get_groups_ref->exists_element (element => $element)) {
            %properties = $bd->get_groups_ref->get_list_values (
                element => $element,
                list    => 'PROPERTIES',
            );
        }

        #return if ! scalar keys %properties;  #  no properties to display

        my $model = Gtk2::ListStore->new(
            'Glib::String',
            'Glib::String',
        );

        foreach my $prop (natsort keys %properties) {

            my $count = $properties{$prop};
            my $iter  = $model->append;
            $model->set(
                $iter,
                0 => $prop,
                1 => $count
            );
        }
        $popup->{properties_model} = $model;
    }

    $popup->set_list_model($popup->{properties_model});
    $popup->set_value_column(1);

    return;
}

##########################################################
# Output list
##########################################################

sub show_output_list {
    my $popup = shift;
    my $name = shift;
    my $element = shift;
    my $data = shift;

    my $elts = $data->get_element_hash();
    my $list_ref = $elts->{$element}{$name};

    my $model = Gtk2::ListStore->new('Glib::String', 'Glib::String');

    if (is_hashref($list_ref)) {
        #  sort differently if list elements are numbers or text
        my $numeric = 1;
        foreach my $key (keys %$list_ref) {
            if (! looks_like_number ($key)) {
                $numeric = 0;
                last;
            }
        }
        #my $sort_sub = sub {$a cmp $b};
        #if ($numeric) {
        #    $sort_sub = sub {$a <=> $b};
        #}
        #my @keys = sort $sort_sub keys %$list_ref;
        
        my @keys = $numeric
            ? sort {$a <=> $b} keys %$list_ref
            : natsort keys %$list_ref;

        foreach my $key (@keys) {
            my $val = $list_ref->{$key} // "";  #  zeros are valid values
            #print "[Cell popup] Adding output hash entry $key\t\t$val\n";
            my $iter = $model->append;
            $model->set($iter,    0, $key ,  1, $val);
        }
    }
    elsif (is_listref($list_ref)) {
        my $numeric = 1;
        foreach my $key (@$list_ref) {
            if (! looks_like_number ($key)) {
                $numeric = 0;
                last;
            }
        }
        #my $sort_sub = sub {$a cmp $b};
        #if ($numeric) {
        #    $sort_sub = sub {$a <=> $b};
        #}
        #my @keys = sort $sort_sub @$list_ref;
        
        my @keys = $numeric
            ? sort {$a <=> $b} @$list_ref
            : natsort keys @$list_ref;

        foreach my $elt (@keys) {
            #print "[Cell popup] Adding output array entry $elt\n";
            my $iter = $model->append;
            $model->set($iter, 0, $elt, 1, '');
        }
    }

    $popup->set_value_column(1);
    $popup->set_list_model($model);
}  

##########################################################
# Neighbours
##########################################################

# Return whether to show the cell's neighbours
# Basically, yes - if data is a spatial output,
# no - if it's a basedata
sub is_neighbours_mode {
    my $data = shift;

    return $data->isa('Biodiverse::Spatial');
    #return (ref $data) =~ /Spatial/;
}

sub find_neighbours {
    my $element = shift;
    my $output_ref = shift;

    my $basedata_ref =  $output_ref->get_param('BASEDATA_REF') || $output_ref;

    my @exclude;
    my @nbr_list;
    my $parsed_spatial_conditions = $output_ref->get_spatial_conditions();
    my $sp_index = $output_ref->get_param ('SPATIAL_INDEX');
    my $search_blocks_ref = $output_ref->get_param ('INDEX_SEARCH_BLOCKS');

    foreach my $i (0 .. $#$parsed_spatial_conditions) {
        my $list_exists = $output_ref->exists_list (
            element => $element,
            list    => '_NBR_SET' . ($i+1),
        );
        if ($list_exists) {
            $nbr_list[$i] = $output_ref->get_list_values (
                element => $element,
                list    => '_NBR_SET' . ($i+1),
            );
        }
        else {
            $nbr_list[$i] = $basedata_ref->get_neighbours_as_array (
                element        => $element,
                spatial_params => $parsed_spatial_conditions->[$i],
                index          => $sp_index,
                index_offsets  => $search_blocks_ref->[$i],
                exclude_list   => \@exclude,
            );
            push @exclude, @{$nbr_list[$i]};
        }
    }

    my $indices_object = Biodiverse::Indices->new (BASEDATA_REF => $basedata_ref);
    my %ABC = $indices_object->calc_abc2(
        element_list1 => $nbr_list[0],
        element_list2 => $nbr_list[1],
    );
    $ABC{element_list1} = $nbr_list[0];
    $ABC{element_list2} = $nbr_list[1];
    
    return \%ABC;
}

1;

