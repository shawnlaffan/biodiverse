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
    $content_area->pack_start( $notebook, 1, 1, 1 );
    
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

    my %element_hash = %{$args{element_hash}};
    my @all_props    = @{$args{all_props}};

    # treat the element name just like an ordinary property
    unshift(@all_props, "Element");

    my @treestore_args;

    # each of the property columns
    foreach my $prop (@all_props) {
        push @treestore_args, 'Glib::Boolean';
        push @treestore_args, 'Glib::String';
    }

    my $model = Gtk2::TreeStore->new(@treestore_args);
    
    # fill model with content
    foreach my $element (keys %element_hash) {
        my $iter = $model->append(undef);
        my %props_to_values_hash = %{$element_hash{$element}};
        $props_to_values_hash{"Element"} = $element;

        my @model_args =($iter, 0, $element);
        my $i = 0;
        foreach my $prop (@all_props) {
            # the delete/don't delete checkbox
            push(@model_args, $i++);
            push(@model_args, 0);
            
            # the value
            push(@model_args, $i++);
            push(@model_args, $props_to_values_hash{$prop});
        }
        $model->set(@model_args);
    }

    # allow multi selections
    my $tree = Gtk2::TreeView->new($model);
    my $sel = $tree->get_selection();
    $sel->set_mode('multiple');

    my @columns;
    my @renderers;
    $i = 0;
    
    foreach my $prop (@all_props) {
        my $new_column = Gtk2::TreeViewColumn->new();
        push (@columns, $new_column);

        $self->add_header_and_tooltip_to_treeview_column (
            column       => $new_column,
            title_text   => $prop,
            tooltip_text => '',
            );
       
        my $checkbox_renderer = Gtk2::CellRendererToggle->new();

    #     my %data = (
    #         model         => $model,
    #         self          => $self,
    #         column_number => $i,
    #         );
    #     $checkbox_renderer->signal_connect_swapped(
    #         toggled => \&on_delete_toggled,
    #         \%data
    #         );
        
        my $new_renderer = Gtk2::CellRendererText->new();

        $new_column->pack_start( $checkbox_renderer, 0 );
        $new_column->set_attributes( $checkbox_renderer, active => $i++ );

        $new_column->pack_start( $new_renderer, 0 );
        $new_column->set_attributes( $new_renderer, text => $i++ );

        $tree->append_column($new_column);
        $new_column->set_sort_column_id($i);
    }
    
    return $tree;
}


# input hash is in format:
# 'Genus:sp8' => {
#     'RANGE' => 4,
#     'ABUNDANCE' => 10
# },
# 'Genus:sp21' => {
#     'RANGE' => 25,
#     'ABUNDANCE' => 180
# },
sub _build_deletion_panel {
    my ($self, %args) = @_;
    my %hash = %{$args{values_hash}};
    my $basestruct = $args{basestruct};
    
    # find all of the possible properties
    my %all_props;
    foreach my $element (keys %hash) {
        my %prop_to_value = %{$hash{$element}};
        foreach my $prop (keys %prop_to_value) {
            $all_props{$prop} = 1;
        }
    }
    my @all_props = keys %all_props;

    my $tree = $self->build_tree_from_hash( all_props    => \@all_props,
                                            element_hash => \%hash,
        );

    
    my $scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $scroll->add($tree);

    my $vbox = Gtk2::VBox->new();
    $vbox->pack_start( $scroll, 1, 1, 1 );
    
    return $vbox;
}

# handle deletion checkbox toggling
sub on_delete_toggled {
    my $args = shift;
    my $path = shift;

    my $model = $args->{model};
    my $self  = $args->{self};
    my $column_number = $args->{column_number};
    
    my $iter = $model->get_iter_from_string($path);

    # Flip state
    my $state = $model->get( $iter, $column_number );
    $model->set( $iter, $column_number, !$state );

    # my $property = $model->get( $iter, PROPERTY_COL );
    # my $element = $model->get( $iter, ELEMENT_COL );

    # figure out if it's a group or label element property
    # my $notebook = $self->{notebook};
    # my $current_page = $notebook->get_current_page;
    # my $basestruct = ($current_page == 0) ? "label" : "group";
    
    # if ( !$state ) {
    #     $self->_add_item_for_deletion( 
    #         property   => $property,
    #         element    => $element,
    #         basestruct => $basestruct,
    #     );
    # }
    # else {
    #     $self->_remove_item_for_deletion( 
    #         property   => $property,
    #         element    => $element,
    #         basestruct => $basestruct,
    #     );
    # }
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
