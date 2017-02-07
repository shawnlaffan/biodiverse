package Biodiverse::GUI::DeleteElementProperties;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.99_006';

use Gtk2;
use Biodiverse::RemapGuesser qw/guess_remap/;

use Biodiverse::GUI::GUIManager;

use Scalar::Util qw /blessed/;

use constant DEFAULT_DIALOG_HEIGHT => 600;
use constant DEFAULT_DIALOG_WIDTH => 600;


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

        my $tree = $self->build_tree_from_hash( hash => \%elements_to_values );
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

    # start by building the TreeModel
    my @treestore_args = (
        'Glib::String',     # Element
        'Glib::String',     # Value
        'Glib::Boolean',    # Delete?
        );

    my $model = Gtk2::TreeStore->new(@treestore_args);

    # fill model with content
    foreach my $key (keys %hash) {
        my $iter = $model->append(undef);
        $model->set(
            $iter,
            0, $key,
            1, $hash{$key},
            2, 0,
            );
    }

    # allow multi selections
    my $tree = Gtk2::TreeView->new($model);
    my $sel = $tree->get_selection();
    $sel->set_mode('multiple');

    my $element_column = Gtk2::TreeViewColumn->new();
    my $value_column = Gtk2::TreeViewColumn->new();
    my $delete_column = Gtk2::TreeViewColumn->new();
    
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

    $element_column->pack_start( $element_renderer, 0 );
    $value_column->pack_start( $value_renderer, 0 );
    $delete_column->pack_start( $delete_renderer, 0 );

    $element_column->add_attribute( $element_renderer,
                                     text => 0 );
    $value_column->add_attribute( $value_renderer,
                                     text => 1 );
    $delete_column->add_attribute( $delete_renderer,
                                     active => 2 );

    $tree->append_column($element_column);
    $tree->append_column($value_column);
    $tree->append_column($delete_column);

    $element_column->set_sort_column_id(0);
    $value_column->set_sort_column_id(1);
    $delete_column->set_sort_column_id(2);

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
    my $state = $model->get( $iter, 2 );
    $model->set( $iter, 2, !$state );
  
    # my $label = $model->get( $iter, ORIGINAL_LABEL_COL );

    # if ( !$state ) {
    #     $self->remove_exclusion($label);
    # }
    # else {
    #     $self->add_exclusion($label);
    # }
    # my $exclusions_ref = $self->get_exclusions();
    # my @exclusions     = @{$exclusions_ref};

    # #say "found label $label, @exclusions";

    return;


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
