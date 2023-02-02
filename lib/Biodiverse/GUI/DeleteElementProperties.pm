package Biodiverse::GUI::DeleteElementProperties;

use 5.010;
use strict;
use warnings;
use Carp;

our $VERSION = '4.1';

use Gtk2;
#use Biodiverse::RemapGuesser qw/guess_remap/;

use Biodiverse::GUI::GUIManager;

use Scalar::Util qw /blessed/;
use Sort::Key::Natural qw /natsort/;

use constant DEFAULT_DIALOG_HEIGHT => 500;
use constant DEFAULT_DIALOG_WIDTH  => 600;

use constant MODEL_CHECKED_COL => 0;
use constant MODEL_TEXT_COL    => 1;

sub new {
    my $class = shift;
    
    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $self = {
        gui     => $gui,
        project => $gui->get_project,
        scheduled_deletions => [],
    };
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
            bs_type     => 'label',
        );

    my $group_outer_vbox =
        $self->_build_deletion_panel(
            values_hash => \%group_props_hash,
            bs_type     => 'group',
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
        'gtk-cancel' => 'cancel',
        'gtk-apply'  => 'apply',
        #'gtk-close'  => 'close',
    );

    $dlg->set_default_size(DEFAULT_DIALOG_WIDTH, DEFAULT_DIALOG_HEIGHT);

    my $notebook = $self->build_main_notebook();
    
    my $content_area = $dlg->get_content_area;
    $content_area->pack_start( $notebook, 1, 1, 1 );

    $self->{dlg} = $dlg;
    $dlg->show_all;
    my $response = $dlg->run();
    delete $self->{dlg};
    $dlg->destroy();

    if ($response =~ /^(ok|apply)$/) {
        $self->on_clicked_apply;
    }
}


# given a list, build a single column tree from it and return.
sub build_tree_from_list {
    my ($self, %args) = @_;
    my $list = $args{list};

    my $model = Gtk2::TreeStore->new('Glib::Boolean', 'Glib::String');

    my $title = $args{ title } // '';
    
    # fill model with content
    foreach my $item (natsort @$list) {
        my $iter = $model->append(undef);
        $model->set($iter, 1, $item);
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
    
    my $text_renderer  = Gtk2::CellRendererText->new();
    my $check_renderer = Gtk2::CellRendererToggle->new();

    $column->pack_start( $check_renderer, 0);
    $column->pack_start( $text_renderer,  1 );
    $column->add_attribute( $check_renderer, active => 0 );
    $column->add_attribute( $text_renderer,  text => 1 );
    $tree->append_column($column);
    $column->set_sort_column_id(1);

    return ($tree, $model);
}

sub on_checkbox_toggled {
    my $model = shift;
    my $path  = shift;
    
    my $iter = $model->get_iter_from_string($path);

    # Flip state
    my $state = $model->get($iter, MODEL_CHECKED_COL);

    $model->set($iter, MODEL_CHECKED_COL, !$state);

    return;
}

sub _build_deletion_panel {
    my ($self, %args) = @_;
    my $values_hash = $args{values_hash};
    my $bs_type = $args{bs_type};
    
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

    my ($properties_tree, $properties_model) = 
        $self->build_tree_from_list(
            list  => \@all_props,
            title => "Properties",
        );

    $self->{$bs_type}{properties_tree} = $properties_tree;
    $self->{models}{$bs_type}{properties_tree} = $properties_model;
    
    my ($elements_tree, $elements_model) =
        $self->build_tree_from_list(
            list  => \@elements_list,
            title => "Elements",
        );

    $self->{$bs_type}{elements_tree} = $elements_tree;
    $self->{models}{$bs_type}{elements_tree} = $elements_model;

    my $hbox = Gtk2::HBox->new();
    $hbox->pack_start( $properties_tree, 1, 1, 0 );  
    $hbox->pack_start( $elements_tree, 1, 1, 0 );  
    
    my $scroll = Gtk2::ScrolledWindow->new( undef, undef );

    $scroll->add_with_viewport($hbox);

    my $vbox = Gtk2::VBox->new(); 
    $vbox->pack_start( $scroll, 1, 1, 0 ); 

    my $schedule_deletion_button =
        Gtk2::Button->new_with_label (
            "Schedule selected"
        );
    $schedule_deletion_button->set_tooltip_text (
        'Schedule deletions of selected properties from all elements, and all properties from selected elements'
    );

    $schedule_deletion_button->signal_connect(
        'clicked' => sub {
            $self->clicked_schedule_button(
                tree => $properties_tree,
                type => 'property',
                check => 1,
            );
            $self->clicked_schedule_button(
                tree => $elements_tree,
                type => 'element',
                check => 1,
            );
        }
    );
    
    my $unschedule_deletion_button =
        Gtk2::Button->new_with_label(
            "Unschedule selected"
        );
    $unschedule_deletion_button->set_tooltip_text (
        'Unschedule deletions of selected properties from all elements, and all properties from selected elements'
    );

    $unschedule_deletion_button->signal_connect(
        'clicked' => sub {
            $self->clicked_schedule_button(
                tree => $properties_tree,
                type => 'property',
                check => 0,
            );
            $self->clicked_schedule_button(
                tree => $elements_tree,
                type => 'element',
                check => 0,
            );
        }
    );
    
    my $button_hbox = Gtk2::HBox->new();
    $button_hbox->pack_start( $schedule_deletion_button, 1, 0, 0 );
    $button_hbox->pack_start( $unschedule_deletion_button, 1, 0, 0 );
    $vbox->pack_start( $button_hbox, 0, 0, 0 );
    
    my $clear_selections_button =
        Gtk2::Button->new_with_label(
            'Clear selections'
        );
    $clear_selections_button->set_tooltip_text (
        'Clear selections from lists (this does not uncheck the boxes)'
    );
    $button_hbox->pack_start( $clear_selections_button, 1, 0, 0 );

    $clear_selections_button->signal_connect(
        'clicked' => sub {
            $properties_tree->get_selection->unselect_all;
            $elements_tree->get_selection->unselect_all;
        }
    );
    
    
    my $helper_text = <<'END_HELPER_TEXT'
<i>Select properties to delete from all elements,
or elements that are to have all their properties deleted.

Items with checkboxes ticked are scheduled for deletion.

There is currently no option to delete single
properties from individual elements.

(note: labels and groups are types of element).</i>
END_HELPER_TEXT
;
    $helper_text =~ s/(?:\r?\n)(?![\r\n])/ /gs;
    my $helper_label = Gtk2::Label->new();
    $helper_label->set_width_chars (90);
    $helper_label->set_line_wrap (1);
    $helper_label->set_selectable (1);
    $helper_label->set_markup ($helper_text);
    $vbox->pack_start( $helper_label, 0, 0, 0 );
    
    return $vbox;
}


sub on_clicked_apply {
    my ($self, %args) = @_;

    my $bd           = $self->{bd};
    my $selected_one = 0;
    
    my %methods = (
        label => {
            elements_tree  => 'delete_individual_label_properties_aa',
            properties_tree => 'delete_label_element_property_aa',
        },
        group => {
            elements_tree  => 'delete_individual_group_properties_aa',
            properties_tree => 'delete_group_element_property_aa',            
        },
    );
    
    # should probably just figure out what sub to use here.
    #my $schedule = $self->{scheduled_deletions};
    my %bs_type_had_deletions;
    
    my $delete_count;
    
    foreach my $bs_type (keys %methods) {
        foreach my $tree_type (keys %{$methods{$bs_type}}) {
            #my $treeview = $self->{$bs_type}{$tree_type};
            #my $model = $treeview->get_model;
            my $model = $self->{models}{$bs_type}{$tree_type};
            my @targets;
            my $method = $methods{$bs_type}{$tree_type};
            my $iter = $model->get_iter_first();
            while ($iter) {
                my ($checked) = $model->get($iter, MODEL_CHECKED_COL);
                if ($checked) {
                    my ($text) = $model->get($iter, MODEL_TEXT_COL);
                    push (@targets, $text);
                }
                $iter = $model->iter_next($iter);
            }
            my $sub_delete_count;
            foreach my $target (@targets) {
                $bd->$method($target);
                $sub_delete_count ++;
            }
            if ($sub_delete_count) {
                $delete_count += $sub_delete_count;
                $bs_type_had_deletions{$bs_type}{$tree_type} += $sub_delete_count;
            }
        }
    }

    my $msg = 'No deletions scheduled';
    
    if ($delete_count) {
        $self->{project}->set_dirty;
        foreach my $type (keys %bs_type_had_deletions) {
            #  clear the cache
            my $ref = $type eq 'label'
              ? $bd->get_labels_ref
              : $bd->get_groups_ref;
            $ref->delete_cached_values;
        }
        my $fmt = <<"END_FMT"
Deleted:
all properties from %d labels,
%d properties from all labels,
all properties from %d groups,
%d properties from all groups.
END_FMT
  ;
        $msg = sprintf $fmt,
            ($bs_type_had_deletions{label}{elements_tree} // 0),
            ($bs_type_had_deletions{label}{properties_tree} // 0),
            ($bs_type_had_deletions{group}{elements_tree} // 0),
            ($bs_type_had_deletions{group}{properties_tree} // 0);
    }
    
    my $dlg = Gtk2::MessageDialog->new (
        undef, 'modal',
        'info', # message type
        'ok',
        $msg,
    );
    $dlg->run;
    $dlg->destroy;

    return;
}

sub clicked_schedule_button {
    my ($self, %args) = @_;
    my $type         = $args{type}; # element or property
    my $tree         = $args{tree};
    my $check        = $args{check};
    my $selection    = $tree->get_selection();

    my $notebook     = $self->{notebook};
    my $current_page = $notebook->get_current_page;
    my $bs_type      = ($current_page == 0) ? 'label' : 'group';
    my $bd           = $self->{bd};

    my $selected_one = 0;

    $selection->selected_foreach (
        sub {
            my ($model, $path, $iter) = @_;
            my $text  = $model->get($iter, MODEL_TEXT_COL);
            $model->set($iter, MODEL_CHECKED_COL, $check);
        }
    );


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
