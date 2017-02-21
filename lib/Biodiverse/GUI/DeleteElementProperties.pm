package Biodiverse::GUI::DeleteElementProperties;

use 5.010;
use strict;
use warnings;
use Carp;

our $VERSION = '1.99_006';

use Gtk2;
#use Biodiverse::RemapGuesser qw/guess_remap/;

use Biodiverse::GUI::GUIManager;

use Scalar::Util qw /blessed/;
use Sort::Naturally;

use constant DEFAULT_DIALOG_HEIGHT => 500;
use constant DEFAULT_DIALOG_WIDTH  => 600;

my $i;
use constant DELETE_COL   => $i || 0;
use constant PROPERTY_COL => ++$i;
use constant ELEMENT_COL  => ++$i;
use constant VALUE_COL    => ++$i;

sub new {
    my $class = shift;
    my $self = {
        gui => Biodiverse::GUI::GUIManager->instance()
    };
    $self->{project} = $self->{gui}->get_project();
    bless $self, $class;
    return $self;
}

# separated into a sub so we can call this to update the values after
# deleting something.
sub build_main_notebook {
    my ( $self, %args ) = @_;
    my $bd = $self->{bd};
    
    my %el_props_hash = $bd->get_all_element_properties();
    my %label_props_hash = %{$el_props_hash{labels}};
    my %group_props_hash = %{$el_props_hash{groups}};

    my $label_outer_vbox = 
        $self->_build_deletion_panel(
            values_hash => \%label_props_hash,
            basestruct  => 'label',
        );

    my $group_outer_vbox =
        $self->_build_deletion_panel(
            values_hash => \%group_props_hash,
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

    $self->{notebook} = $notebook;

    return $notebook;
}



sub run {
    my ( $self, %args ) = @_;
    my $bd = $args{basedata};
    $self->{bd} = $bd;

    my $dlg = Gtk2::Dialog->new_with_buttons(
        'Delete Element Properties',
        undef,
        'modal',
        #'gtk-cancel' => 'cancel',
        #'gtk-ok'     => 'ok',
        'gtk-close'  => 'close',
    );

    $dlg->set_default_size(DEFAULT_DIALOG_WIDTH, DEFAULT_DIALOG_HEIGHT);

    my $notebook = $self->build_main_notebook();
    
    my $content_area = $dlg->get_content_area;
    $content_area->pack_start( $notebook, 1, 1, 1 );

    $self->{dlg} = $dlg;
    $dlg->show_all;
    my $response = $dlg->run();
    $dlg->destroy();
}


# given a list, build a single column tree from it and return.
sub build_tree_from_list {
    my ($self, %args) = @_;
    my @list    = @{$args{list}};

    my $model = Gtk2::TreeStore->new(('Glib::String'));
    my $title = $args{ title } // '';
    
    # fill model with content
    foreach my $item (nsort @list) {
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
    my $values_hash = $args{values_hash};
    my $basestruct = $args{basestruct};
    
    # find all of the possible properties
    my %all_props;

    my @elements_list;
    foreach my $element (keys %$values_hash) {
        my $prop_to_value = $values_hash->{$element};

        # we only care about elements that
        # actually have properties.
        if (scalar keys %$prop_to_value) {
            push @elements_list, $element;
            @all_props{keys %$prop_to_value} = ();
        }
    }
    my @all_props = keys %all_props;

    my $properties_tree = 
        $self->build_tree_from_list(
            list  => \@all_props,
            title => "Properties",
        );

    $self->{$basestruct}{properties_tree} = $properties_tree;
    
    my $elements_tree =
        $self->build_tree_from_list(
            list  => \@elements_list,
            title => "Element",
        );

    $self->{basestruct}{elements_tree} = $elements_tree;

    my $hbox = Gtk2::HBox->new();
    $hbox->pack_start( $properties_tree, 1, 1, 0 );  
    $hbox->pack_start( $elements_tree, 1, 1, 0 );  
    
    my $scroll = Gtk2::ScrolledWindow->new( undef, undef );

    $scroll->add_with_viewport($hbox);

    my $vbox = Gtk2::VBox->new(); 
    $vbox->pack_start( $scroll, 1, 1, 0 ); 

    my $delete_properties_button =
        Gtk2::Button->new_with_label (
            "Delete selected properties from all elements"
        );

    $delete_properties_button->signal_connect(
        'clicked' => sub {
            $self->clicked_delete_button(
                tree => $properties_tree,
                type => 'property',
            );
        }
    );
    
    my $delete_elements_button =
        Gtk2::Button->new_with_label(
            "Delete all properties from selected elements"
        );

    $delete_elements_button->signal_connect(
        'clicked' => sub {
            $self->clicked_delete_button(
                tree => $elements_tree,
                type => 'element',
            );
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

    my $selected_one = 0;
    
    my %methods = (
        element => {
            label => 'delete_individual_label_properties_aa',
            group => 'delete_individual_group_properties_aa',
        },
        property => {
            label => 'delete_label_element_property_aa',
            group => 'delete_group_element_property_aa',
        },
    );
    
    # should probably just figure out what sub to use here.

    $selection->selected_foreach (
        sub {
            my ($model, $path, $iter) = @_;
            my $value = $model->get($iter, 0);

            no autovivification;

            $selected_one ||= 1;
            
            my $method = $methods{$type}{$basestruct};
            croak "No method for type $type and target $basestruct"
              if !defined $method;
            $bd->$method($value);
            
            #  seems not to be used
            push @{$self->{to_delete}{$basestruct}{$type}}, $value;
        }
    );

    if ($selected_one) {
        $self->{project}->set_dirty;
        #  clear the cache
        my $ref = $basestruct eq 'label'
          ? $bd->get_labels_ref
          : $bd->get_groups_ref;
        $ref->delete_cached_values;
    }

    my $new_notebook = $self->build_main_notebook();
    
    my $dlg = $self->{dlg};
    my $content_area = $dlg->get_content_area;

    my @children = $content_area->get_children;
    $content_area->remove($children[0]);

    #say "Current page is $current_page";
    
    $content_area->pack_start( $new_notebook, 1, 1, 1 );
    $self->{notebook} = $new_notebook;
    $dlg->show_all;
    $new_notebook->set_current_page($current_page);

    return;
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
