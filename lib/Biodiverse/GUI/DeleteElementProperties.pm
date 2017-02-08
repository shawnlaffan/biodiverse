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
use constant DELETE_COL  => $i || 0;
use constant PROPERTY_COL => ++$i;
use constant ELEMENT_COL  => ++$i;
use constant VALUE_COL     => ++$i;



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
    
    my %el_props_hash = $bd->get_all_element_properties();
    my %label_props_hash = %{$el_props_hash{labels}};
    my %group_props_hash = %{$el_props_hash{groups}};
    
    # break up into a hash mapping from the property name to a hash
    # mapping from element name to value
    %label_props_hash = $self->format_element_properties_hash( 
        props_hash => \%label_props_hash 
        );

    %group_props_hash = $self->format_element_properties_hash( 
        props_hash => \%group_props_hash 
        );

    my $dlg = Gtk2::Dialog->new_with_buttons(
        'Delete Element Properties', undef, 'modal', 'gtk-yes' => 'yes', 'gtk-no'  => 'no'
        );

    $dlg->set_default_size(DEFAULT_DIALOG_WIDTH, DEFAULT_DIALOG_HEIGHT);

    my $label_outer_vbox = 
        $self->_build_deletion_panel( values_hash => \%label_props_hash,
                                      basestruct  => "label",
                                    );

    my $group_outer_vbox =
        $self->_build_deletion_panel( values_hash => \%group_props_hash,
                                      basestruct  => "group",
                                    );
    

    my $notebook = Gtk2::Notebook->new;
    $notebook->append_page (
        $label_outer_vbox,
        "Labels",        
    );

    $notebook->append_page (
        $group_outer_vbox,
        "Groups",        
        );

    # we need to know what notebook page we're on when we choose to
    # delete something, so we know whether to add it to groups or
    # labels.
    $self->{notebook} = $notebook;
    
    my $content_area = $dlg->get_content_area;
    $content_area->pack_start( $notebook, 0, 0, 0 );
    
    $dlg->show_all;
    my $response = $dlg->run();
    $dlg->destroy();

    if($response eq "yes") {
        return wantarray ? %{$self->{to_delete}} : $self->{to_delete};
    }
    else {
        return wantarray ? () : {};
    }
}


# given a hash mapping from element names to values, make a gtk tree
# for it and return.
sub build_tree_from_hash {
    my ($self, %args) = @_;
    my %hash = %{$args{hash}};
    my $property = $args{property};
    
    # start by building the TreeModel
    my @treestore_args = (
        'Glib::Boolean',    # Delete
        'Glib::String',     # Property
        'Glib::String',     # Element
        'Glib::String',     # Value
        );

    my $model = Gtk2::TreeStore->new(@treestore_args);

    # fill model with content
    foreach my $key (keys %hash) {
        my $iter = $model->append(undef);
        $model->set(
            $iter,
            DELETE_COL,   0,
            PROPERTY_COL, $property,
            ELEMENT_COL,  $key,
            VALUE_COL,    $hash{$key},
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
        column       => $delete_column,
        title_text   => 'Delete',
        tooltip_text => '',
        );

    
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

    $delete_column->pack_start( $delete_renderer, 0 );
    $property_column->pack_start( $property_renderer, 0 );
    $element_column->pack_start( $element_renderer, 0 );
    $value_column->pack_start( $value_renderer, 0 );

    $property_column->add_attribute( $property_renderer,
                                    text => PROPERTY_COL );
    $element_column->add_attribute( $element_renderer,
                                     text => ELEMENT_COL );
    $value_column->add_attribute( $value_renderer,
                                     text => VALUE_COL );
    $delete_column->add_attribute( $delete_renderer,
                                     active => DELETE_COL );

    $tree->append_column($delete_column);
    $tree->append_column($property_column);
    $tree->append_column($element_column);
    $tree->append_column($value_column);

    $property_column->set_sort_column_id(PROPERTY_COL);
    $element_column->set_sort_column_id(ELEMENT_COL);
    $value_column->set_sort_column_id(VALUE_COL);
    $delete_column->set_sort_column_id(DELETE_COL);

    return $tree;
}


sub _build_deletion_panel {
    my ($self, %args) = @_;
    my %values_hash = %{$args{values_hash}};
    # group or label?
    my $basestruct = $args{basestruct};

    my $label_vbox = Gtk2::VBox->new();
    foreach my $property (keys %values_hash) {
        my %elements_to_values = %{$values_hash{$property}};
        my $count = scalar (keys %elements_to_values);

        my $label_scroll = Gtk2::ScrolledWindow->new( undef, undef );
        my $label_inner_vbox = Gtk2::VBox->new();

        my $label_prop_info_label = 
            Gtk2::Label->new(
                "Property: $property (applies to $count $basestruct"."s)"
            );

        my $delete_checkbutton 
            = Gtk2::CheckButton->new("Delete Property");
                 
        $label_vbox->pack_start( $label_prop_info_label, 0, 0, 0 );
        $label_vbox->pack_start( $delete_checkbutton, 0, 0, 0 );
        
        my $label_tree = 
            $self->build_tree_from_hash( hash => \%elements_to_values,
                                         property => $property,
            );
        
        $label_inner_vbox->pack_start( $label_tree, 0, 0, 0 );

        $label_scroll->add_with_viewport($label_inner_vbox);

        $label_scroll->set_size_request(200, 100);
        $label_vbox->pack_start( $label_scroll, 0, 0, 0 );

        $delete_checkbutton->set_active(0);
        $delete_checkbutton->signal_connect(
            toggled => sub {
                $label_tree->set_sensitive( !$label_tree->get_sensitive );
                if($label_tree->get_sensitive) {
                    # take everything off deletion
                    foreach my $element (keys %elements_to_values) {
                        $self->_remove_item_for_deletion (
                            property   => $property,
                            element    => $element,
                            basestruct => $basestruct,
                            );
                    }                     
                }
                else {
                    # add everything for deletion
                    foreach my $element (keys %elements_to_values) {
                        $self->_add_item_for_deletion (
                            property   => $property,
                            element    => $element,
                            basestruct => $basestruct,
                            );
                    }                     

                }
            }
         );
    }

    my $label_outer_scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $label_outer_scroll->add_with_viewport($label_vbox);
    $label_outer_scroll->set_size_request(DEFAULT_DIALOG_WIDTH, DEFAULT_DIALOG_HEIGHT);
    
    my $label_outer_vbox = Gtk2::VBox->new();
    $label_outer_vbox->pack_start( $label_outer_scroll, 0, 0, 0 );
    $label_outer_vbox->set_homogeneous(0);
    $label_outer_vbox->set_spacing(3);

    
    return $label_outer_vbox;
}



# handle deletion checkbox toggling
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

    # figure out if it's a group or label element property
    my $notebook = $self->{notebook};
    my $current_page = $notebook->get_current_page;
    my $basestruct = ($current_page == 0) ? "label" : "group";
    
    if ( !$state ) {
        $self->_add_item_for_deletion( 
            property   => $property,
            element    => $element,
            basestruct => $basestruct,
        );
    }
    else {
        $self->_remove_item_for_deletion( 
            property   => $property,
            element    => $element,
            basestruct => $basestruct,
        );
    }
}


sub _remove_item_for_deletion {
    my ($self, %args) = @_;
    my $property   = $args{ property   };
    my $element    = $args{ element    };
    # either group or label
    my $basestruct = $args{ basestruct };
    
    my $to_delete_hash = $self->{to_delete}->{$basestruct};

    my @old_array = @{$to_delete_hash->{$element}};

    # just delete first occurence (so that the exclusion checkboxes
    # still work)
    my @fixed_up_array;
    my $found = 0;
    foreach my $item (@old_array) {
        if(($item eq $property) and (!$found)) {
            $found = 1;
        }
        else {
            push @fixed_up_array, $item;
        }
    }


    if (scalar @fixed_up_array == 0) {
        delete $to_delete_hash->{$element};
    }
    else {
        $to_delete_hash->{$element} = \@fixed_up_array;
    }
    
    $self->{to_delete}->{$basestruct} = $to_delete_hash;  
}

sub _add_item_for_deletion {
    my ($self, %args) = @_;
    my $property   = $args{ property   };
    my $element    = $args{ element    };
    # either group or label
    my $basestruct = $args{ basestruct };
    
    my $to_delete_hash = $self->{to_delete}->{$basestruct};
    
    #if ( !grep( /^$property$/, @{$to_delete_hash->{$element}}) ) {
    push @{$to_delete_hash->{$element}}, $property;
    #}
    
    $self->{to_delete}->{$basestruct} = $to_delete_hash;
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
