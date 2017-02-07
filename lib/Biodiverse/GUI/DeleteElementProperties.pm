package Biodiverse::GUI::DeleteElementProperties;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.99_006';

use Gtk2;
use Biodiverse::RemapGuesser qw/guess_remap/;

use Biodiverse::GUI::GUIManager;

use Scalar::Util qw /blessed/;

use constant DEFAULT_DIALOG_HEIGHT => 500;
use constant DEFAULT_DIALOG_WIDTH => 600;

my $i;
use constant PROPERTY_COL => $i || 0;
use constant ELEMENT_COL  => ++$i;
use constant VALUE_COL     => ++$i;
use constant DELETE_COL  => ++$i;



sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

# given a basedata, run a dialog that shows all the element properties
# associated with the basedata, and allows the user to delete
# some. Then returns which element properties are to be deleted
# (details TBA) so the basedata itself can do the deleting.
sub run {
    my ( $self, %args ) = @_;
    my $bd = $args{basedata};

    say "LUKE: in run_delete_element_properties_gui";
    
    # start by doing just the labels, add in the groups later.
    my %el_props_hash = $bd->get_all_element_properties();
    %el_props_hash = %{$el_props_hash{labels}};

    #say "el_props_hash:";
    #use Data::Dumper;
    #print Dumper(\%el_props_hash);

    # break up into a hash mapping from the property name to a hash
    # mapping from element name to value
    %el_props_hash = 
        $self->format_element_properties_hash( props_hash => \%el_props_hash );


    my $dlg = Gtk2::Dialog->new_with_buttons(
        'Delete Element Properties', undef, 'modal', 'gtk-yes' => 'yes', 'gtk-no'  => 'no'
        );

    $dlg->set_default_size(DEFAULT_DIALOG_WIDTH, DEFAULT_DIALOG_HEIGHT);

    ####
    # Packing
    my $vbox = Gtk2::VBox->new();
    
    # now start building the gui components and packing them in
    foreach my $property (keys %el_props_hash) {
        my %elements_to_values = %{$el_props_hash{$property}};
        my $count = scalar (keys %elements_to_values);

        my $scroll = Gtk2::ScrolledWindow->new( undef, undef );
        my $inner_vbox = Gtk2::VBox->new();

        say "building gui for $property";
        my $prop_info_label = 
            Gtk2::Label->new("Property: $property (applies to $count labels)");

        $vbox->pack_start( $prop_info_label, 0, 0, 0 );

        my $tree = $self->build_tree_from_hash( hash => \%elements_to_values,
                                                property => $property,
                                              );
        
        $inner_vbox->pack_start( $tree, 0, 0, 0 );

        $scroll->add_with_viewport($inner_vbox);

        $scroll->set_size_request(200, 100);
        $vbox->pack_start( $scroll, 0, 0, 0 );
    }

    my $outer_scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $outer_scroll->add_with_viewport($vbox);
    $outer_scroll->set_size_request(DEFAULT_DIALOG_WIDTH, DEFAULT_DIALOG_HEIGHT);
    
    my $outer_vbox = $dlg->get_content_area;
    $outer_vbox->pack_start( $outer_scroll, 0, 0, 0 );
    $outer_vbox->set_homogeneous(0);
    $outer_vbox->set_spacing(3);

    $dlg->show_all;
    my $response = $dlg->run();
    $dlg->destroy();
}


# given a hash mapping from element names to values, make a gtk tree
# for it and return.
sub build_tree_from_hash {
    my ($self, %args) = @_;
    my %hash = %{$args{hash}};
    my $property = $args{property};
    
    # start by building the TreeModel
    my @treestore_args = (
        'Glib::String',     # Property
        'Glib::String',     # Element
        'Glib::String',     # Value
        'Glib::Boolean',    # Delete
        );

    my $model = Gtk2::TreeStore->new(@treestore_args);

    # fill model with content
    foreach my $key (keys %hash) {
        my $iter = $model->append(undef);
        $model->set(
            $iter,
            PROPERTY_COL, $property,
            ELEMENT_COL,  $key,
            VALUE_COL,    $hash{$key},
            DELETE_COL,   0,
            );
    }

    # allow multi selections
    my $tree = Gtk2::TreeView->new($model);
    my $sel = $tree->get_selection();
    $sel->set_mode('multiple');

    my $property_column = Gtk2::TreeViewColumn->new();
    my $element_column = Gtk2::TreeViewColumn->new();
    my $value_column = Gtk2::TreeViewColumn->new();
    my $delete_column = Gtk2::TreeViewColumn->new();

    $self->add_header_and_tooltip_to_treeview_column (
        column       => $property_column,
        title_text   => 'Property',
        tooltip_text => '',
        );
    
    $self->add_header_and_tooltip_to_treeview_column (
        column       => $element_column,
        title_text   => 'Element',
        tooltip_text => '',
        );

    $self->add_header_and_tooltip_to_treeview_column (
        column       => $value_column,
        title_text   => 'Value',
        tooltip_text => '',
        );

    $self->add_header_and_tooltip_to_treeview_column (
        column       => $delete_column,
        title_text   => 'Delete',
        tooltip_text => '',
        );

    my $property_renderer = Gtk2::CellRendererText->new();
    my $element_renderer = Gtk2::CellRendererText->new();
    my $value_renderer = Gtk2::CellRendererText->new();
    my $delete_renderer = Gtk2::CellRendererToggle->new();

    my %data = (
        model => $model,
        self  => $self,
        );
    $delete_renderer->signal_connect_swapped(
        toggled => \&on_delete_toggled,
        \%data
        );

    $property_column->pack_start( $property_renderer, 0 );
    $element_column->pack_start( $element_renderer, 0 );
    $value_column->pack_start( $value_renderer, 0 );
    $delete_column->pack_start( $delete_renderer, 0 );

    $property_column->add_attribute( $property_renderer,
                                    text => PROPERTY_COL );
    $element_column->add_attribute( $element_renderer,
                                     text => ELEMENT_COL );
    $value_column->add_attribute( $value_renderer,
                                     text => VALUE_COL );
    $delete_column->add_attribute( $delete_renderer,
                                     active => DELETE_COL );

    $tree->append_column($property_column);
    $tree->append_column($element_column);
    $tree->append_column($value_column);
    $tree->append_column($delete_column);

    $property_column->set_sort_column_id(PROPERTY_COL);
    $element_column->set_sort_column_id(ELEMENT_COL);
    $value_column->set_sort_column_id(VALUE_COL);
    $delete_column->set_sort_column_id(DELETE_COL);

    return $tree;
}

# handle deletion checkbox toggling here
sub on_delete_toggled {
    my $args = shift;
    my $path = shift;

    my $model = $args->{model};
    my $self  = $args->{self};

    my $iter = $model->get_iter_from_string($path);

    # Flip state
    my $state = $model->get( $iter, DELETE_COL );
    $model->set( $iter, DELETE_COL, !$state );

    my $property = $model->get( $iter, PROPERTY_COL );
    my $element = $model->get( $iter, ELEMENT_COL );

    if ( !$state ) {
        $self->_add_item_for_deletion( 
            property => $property,
            element  => $element,
        );
    }
    else {
        $self->_remove_item_for_deletion( 
            property => $property,
            element  => $element,
        );
    }
}


# TODO also need to pass in whether it's a group/label when we
# implement that.
sub _remove_item_for_deletion {
    my ($self, %args) = @_;
    my $property = $args{ property };
    my $element  = $args{ element  };

    my $labels_to_delete_hash = $self->{to_delete}->{labels};

    my @fixed_up_array = @{$labels_to_delete_hash->{$element}};
    @fixed_up_array = grep { $_ ne  $property } @fixed_up_array;      

    if (scalar @fixed_up_array == 0) {
        delete $labels_to_delete_hash->{$element};
    }
    else {
        $labels_to_delete_hash->{$element} = \@fixed_up_array;
    }
    use Data::Dumper;
    print Dumper($labels_to_delete_hash);
    
    $self->{to_delete}->{labels} = $labels_to_delete_hash;  
}

sub _add_item_for_deletion {
    my ($self, %args) = @_;
    my $property = $args{ property };
    my $element  = $args{ element  };

    my $labels_to_delete_hash = $self->{to_delete}->{labels};
    push @{$labels_to_delete_hash->{$element}}, $property;

    use Data::Dumper;
    print Dumper($labels_to_delete_hash);
    
    $self->{to_delete}->{labels} = $labels_to_delete_hash;
}



# given a hash mapping from element name to a hash mapping from
# property name to value. Convert this to a hash mapping from property
# name to a hash mapping from element name to value.
sub format_element_properties_hash {
    my ($self, %args) = @_;
    my %old_hash = %{$args{props_hash}};
    my %new_hash;

    foreach my $element (keys %old_hash) {
        foreach my $prop (keys %{ $old_hash{$element} }) {
            my $value = $old_hash{$element}->{$prop};
            $new_hash{$prop}->{$element} = $value;
        }
    }

    # say "new_hash:";
    # use Data::Dumper;
    # print Dumper(\%new_hash);

    return wantarray ? %new_hash : \%new_hash;
}

# you can't just use set_tooltip_text for treeview columns for some
# reason, so this is a little helper function to do the rigmarole with
# making a label, tooltipping it and adding it to the column.
sub add_header_and_tooltip_to_treeview_column {
    my ($self, %args) = @_;
    my $column = $args{column};

    my $header = Gtk2::Label->new( $args{title_text} );
    $header->show();

    $column->set_widget($header);

    my $tooltip = Gtk2::Tooltips->new();
    $tooltip->set_tip( $header, $args{tooltip_text} );
}
