package Biodiverse::GUI::DeleteElementProperties;

use 5.010;
use strict;
use warnings;
use Carp;

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
    $self->{bd} = $bd;
    
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


# given a list, build a single column tree from it and return.
sub build_tree_from_list {
    my ($self, %args) = @_;
    my @list    = @{$args{list}};

    my $model = Gtk2::TreeStore->new(('Glib::String'));
    my $title = $args{ title } // '';
    
    # fill model with content
    foreach my $item (@list) {
        my $iter = $model->append(undef);
        $model->set($iter, 0, $item);
    }

    # allow multi selections
    my $tree = Gtk2::TreeView->new($model);
    my $sel = $tree->get_selection();
    $sel->set_mode('multiple');

    my $column = Gtk2::TreeViewColumn->new();
    $self->add_header_and_tooltip_to_treeview_column (
        column       => $column,
        title_text   => $title,
        tooltip_text => '',
        );
    
    my $renderer = Gtk2::CellRendererText->new();

    $column->pack_start( $renderer, 0 );
    $column->set_attributes( $renderer, text => 0 );
    $tree->append_column($column);
    $column->set_sort_column_id(0);

    return $tree;
}


sub _build_deletion_panel {
    my ($self, %args) = @_;
    my %hash = %{$args{values_hash}};
    my $basestruct = $args{basestruct};
    
    # find all of the possible properties
    my %all_props;

    my @elements_list;
    foreach my $element (keys %hash) {
        my %prop_to_value = %{$hash{$element}};
        foreach my $prop (keys %prop_to_value) {
            $all_props{$prop} = 1;
        }
        push @elements_list, $element;
    }
    my @all_props = keys %all_props;

    my $properties_tree = 
        $self->build_tree_from_list( list  => \@all_props,
                                     title => "Properties");

    my $elements_tree =
        $self->build_tree_from_list( list  => \@elements_list,
                                     title => "Element");
    

    my $hbox = Gtk2::HBox->new();
    $hbox->pack_start( $properties_tree, 1, 1, 0 );  
    $hbox->pack_start( $elements_tree, 1, 1, 0 );  
    
    my $scroll = Gtk2::ScrolledWindow->new( undef, undef );

    $scroll->add_with_viewport($hbox);

    my $vbox = Gtk2::VBox->new(); 
    $vbox->pack_start( $scroll, 1, 1, 0 ); 

    my $delete_properties_button =
        Gtk2::Button->new_with_label("Delete selected properties");

    $delete_properties_button->signal_connect(
        'clicked' => sub {
            $self->clicked_delete_button(tree => $properties_tree,
                                         type => 'property',);

        }
        );
    
    my $delete_elements_button =
        Gtk2::Button->new_with_label("Delete all properties of selected elements");

    $delete_elements_button->signal_connect(
        'clicked' => sub {
            $self->clicked_delete_button(tree => $elements_tree,
                                         type => 'element',);
        }
        );
    
    my $button_hbox = Gtk2::HBox->new();
    $button_hbox->pack_start( $delete_properties_button, 1, 0, 0 );
    $button_hbox->pack_start( $delete_elements_button, 1, 0, 0 );
    $vbox->pack_start( $button_hbox, 0, 0, 0 );
    
    return $vbox;
}


sub clicked_delete_button {
    my ($self, %args) = @_;
    my $type         = $args{type}; # element or property
    my $tree         = $args{tree};
    my $selection    = $tree->get_selection();
    
    my $notebook     = $self->{notebook};
    my $current_page = $notebook->get_current_page;
    my $basestruct   = ($current_page == 0) ? 'label' : 'group';
    my $bd           = $self->{bd};

    # should probably just figure out what sub to use here.
    
    $selection->selected_foreach (
        sub{
            my ($model, $path, $iter) = @_;
            my $value = $model->get($iter, 0);
            
            if($type eq 'element') {
                if($basestruct eq 'label') {
                    $bd->delete_individual_label_properties(el => $value);
                }
                else {
                    $bd->delete_individual_group_properties(el => $value);
                }
            }
            elsif($type eq 'property') {
                if($basestruct eq 'label') {
                    $bd->delete_label_element_property(prop => $value);
                }
                else {
                    $bd->delete_group_element_property(prop => $value);
                }

            }
            else {
                croak "Unknown type $type";
            }
            
            push @{$self->{to_delete}->{$basestruct}->{$type}}, $value;
        }
        );
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
