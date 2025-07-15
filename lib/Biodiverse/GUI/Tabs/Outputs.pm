package Biodiverse::GUI::Tabs::Outputs;
use 5.010;
use strict;
use warnings;
use Carp;

use Scalar::Util qw { blessed };

use Gtk3;
use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;
use Biodiverse::GUI::Export;

use English ( -no_match_vars );

our $VERSION = '4.99_007';

use parent qw {Biodiverse::GUI::Tabs::Tab};

sub new {
    my $class = shift;

    my $self = {gui => Biodiverse::GUI::GUIManager->instance};
    #weaken ($self->{gui}) if (not isweak ($self->{gui}));  #  avoid circular refs?
    bless $self, $class;

    # (we can have many Analysis tabs open, for example. These have a different object/widgets)
    $self->{xmlPage} = Gtk3::Builder->new();
    $self->{xmlPage}->add_from_file($self->{gui}->get_gtk_ui_file('hboxOutputsPage.ui'));
    $self->{xmlLabel} = Gtk3::Builder->new();
    $self->{xmlLabel}->add_from_file($self->{gui}->get_gtk_ui_file('hboxOutputsLabel.ui'));

    my $page  = $self->get_xmlpage_object('hboxOutputsPage');
    my $label = $self->{xmlLabel}->get_object('hboxOutputsLabel');
    my $menu_label = Gtk3::Label->new ('Outputs tab');

    # Add to notebook
    $self->{notebook}   = $self->{gui}->get_notebook();
    $self->{notebook}->prepend_page_menu($page, $label, $menu_label);
    $self->{page}       = $page;
    $self->{gui}->add_tab($self);


    $self->set_tab_reorderable($page);

    # Initialise the tree
    my $tree = $self->get_xmlpage_object('outputsTree');

    #  what columns to add to the tree?
    my %columns_hash = (
        Basedata => MODEL_BASEDATA,
        Output   => MODEL_OUTPUT,
        Indices  => MODEL_ANALYSIS,
        Type     => MODEL_OUTPUT_TYPE,
    );
    my @column_order = qw /Basedata Output Indices Type/;

    #while (my ($column_type, $text) = each %columns_hash) {
    foreach my $column_type (@column_order) {
        my $text = $columns_hash{$column_type};
        my $text_renderer = Gtk3::CellRendererText->new();
        if ($column_type eq 'Type') {
            $text_renderer->set(style => 'italic');
        }
        $tree->insert_column_with_attributes(
            -1,
            $column_type,
            $text_renderer,
            text => $text,
        );
    }

    my $model = $self->{gui}->get_project->get_base_data_output_model();
    $tree->set_model( $model );
    $tree->columns_autosize;

    # Monitor for new rows, so that we can expand basedatas
    $model->signal_connect('row-inserted' => \&on_row_inserted, $self);

    # Connect signals
    $self->get_xmlpage_object('btnOutputsShow'  )->signal_connect_swapped(clicked => \&on_show,   $self);
    $self->get_xmlpage_object('btnOutputsExport')->signal_connect_swapped(clicked => \&on_export, $self);
    $self->get_xmlpage_object('btnOutputsDelete')->signal_connect_swapped(clicked => \&on_delete, $self);
    $self->get_xmlpage_object('btnOutputsRename')->signal_connect_swapped(clicked => \&on_rename, $self);
    $self->get_xmlpage_object('btnOutputsDescribe')->signal_connect_swapped(clicked => \&on_describe, $self);



    $tree->signal_connect_swapped('row-activated', \&on_row_activated, $self);
    $tree->get_selection->signal_connect_swapped(
        'changed',
        \&on_row_changed,
        $self,
    );
    $tree->signal_connect_swapped('row-collapsed' => \&on_row_collapsed, $self);

    print "[Outputs tab] Loaded tab - Outputs\n";

    return $self;
}

sub get_type { return 'outputs'; }

sub get_removable { return 0; } # output tab cannot be closed

# Get lots of information about currently selected row
sub get_selection {
    my $self = shift;

    my $tree    = $self->get_xmlpage_object('outputsTree');
    my $project = $self->{gui}->get_project;

    return if not defined $project;

    my $model = $project->get_base_data_output_model();

    my $selection = $tree->get_selection();
    my $iter      = $selection->get_selected();
    return if not defined $iter;

    # If user clicked on an analysis subrow, we'll pass the
    # analysis name to the tab. The output's name is with the parent.
    my ($type, $basedata_ref, $output_ref, $analysis, $tab);
    my $parent = $model->iter_parent($iter);
    my $grandparent;
    $grandparent = $model->iter_parent($parent) if $parent;

    if (defined $grandparent) {
        #print "[Outputs tab] Clicked on analysis row\n";
        # Click on analysis row
        $type = 'analysis';

        $analysis     = $model->get($iter,        MODEL_ANALYSIS);
        $output_ref   = $model->get($parent,      MODEL_OBJECT);
        $tab          = $model->get($parent,      MODEL_TAB);
        $basedata_ref = $model->get($grandparent, MODEL_OBJECT);

    }
    elsif (defined $parent) {
        #print "[Outputs tab] Clicked on output row\n";
        # Click on output row
        $type = "output";

        $output_ref   = $model->get($iter,   MODEL_OBJECT);
        $tab          = $model->get($iter,   MODEL_TAB);
        $basedata_ref = $model->get($parent, MODEL_OBJECT);

    }
    else {
        #print "[Outputs tab] Clicked on basedata row\n";
        # Clicked on basedata row
        $type = 'basedata';

        $basedata_ref = $model->get($iter, MODEL_OBJECT);
    }

    my $hash_ref = {
        type         => $type,
        basedata_ref => $basedata_ref,
        output_ref   => $output_ref,
        analysis     => $analysis,
        tab          => $tab,
        iter         => $iter
    };

    return $hash_ref;
}

sub on_row_inserted {
    my ($model, $path, $iter, $self) = @_;

    # If an output row has been added, we expand the parent (basedata row)
    my $iter_parent = $model->iter_parent($iter);

    if ($iter_parent && ($model->get($iter_parent, MODEL_BASEDATA_ROW) == 1) ) {
        my $tree = $self->get_xmlpage_object('outputsTree');
        $tree->expand_row($model->get_path($iter_parent), 0);
    }

    return;
}

sub on_row_activated {
    my $self = shift;

    eval {
        $self->on_show();
    };
    if ($EVAL_ERROR) {
        $self->{gui}->report_error ($EVAL_ERROR);
    }

    return;
}

# Enable/disable buttons based on selected row
sub on_row_changed {
    my $self = shift;

    my $selected = $self->get_selection();
    my $type = $selected->{type};

    return if not defined $type;

    my $sensitive = $type eq 'output' || $type eq 'basedata';

    my @widget_name_array
        = qw /btnOutputsExport btnOutputsDelete btnOutputsRename/;

    foreach my $widget_name (@widget_name_array) {
        $self->get_xmlpage_object($widget_name)->set_sensitive($sensitive);
    }

    # If clicked on basedata, select it
    if ($type eq 'basedata') {
        $self->{gui}->get_project->select_base_data($selected->{basedata_ref}) ;
    }

    return;
}

#  resize the contents - this reclaims unused horizontal space
sub on_row_collapsed {
    my $self = shift;
    my $tree = $self->get_xmlpage_object('outputsTree');

    $tree->columns_autosize();

    return;
}

# Switch to the output's analysis tab or create a new one
sub on_show {
    my $self = shift;

    my $selected = $self->get_selection();

    # Show labels if double-clicked basedata row or we have nothing selected.
    # The latter happens when new projects are loaded or data are imported into an empty project.
    if (!defined $selected or $selected->{type} eq 'basedata') {
        my $labels = eval {Biodiverse::GUI::Tabs::Labels->new()};
        if ($EVAL_ERROR) {
            $self->{gui}->report_error ($EVAL_ERROR);
            return;
        }
    }

    # Otherwise, we only care about analysis rows
    return if !defined $selected || !defined $selected->{output_ref};

    my $output_ref = $selected->{output_ref};
    my $analysis   = $selected->{analysis};
    my $tab        = $selected->{tab};
    my $iter       = $selected->{iter}; # unused

    # Tabs should register themselves in the model
    if (defined $tab) {
        # Switch to it
        print "[Outputs tab] Switching to analysis tab\n";
        $self->{gui}->switch_tab($tab);
    }
    else {
        print "[Outputs tab] New analysis tab\n";
        my $type = ref($output_ref);

        eval {
            #  Spatials are a type of BaseStruct
            if ($type =~ /Spatial/) {
                $tab = Biodiverse::GUI::Tabs::Spatial->new($output_ref);
            }
            elsif ($type =~ /Cluster|Tree/) {
                $tab = Biodiverse::GUI::Tabs::Clustering->new($output_ref);
            }
            elsif ($type =~ /RegionGrower/) {
                $tab = Biodiverse::GUI::Tabs::RegionGrower->new($output_ref);
            }
            elsif ($type =~ /Randomis/) {
                $tab = Biodiverse::GUI::Tabs::Randomise->new($output_ref);
            }
            elsif ($type =~ /Matrix/) {
                $tab = Biodiverse::GUI::Tabs::SpatialMatrix->new($output_ref);
            }
            else {
                croak 'Outputs::on_show - unsupported output type ' . $type;
            }
        };
        if ($EVAL_ERROR) {
            $self->{gui}->report_error ($EVAL_ERROR);
            if ($tab) {
                $tab->on_close;
            }
            return;
        }
    }

    if (defined $analysis) {
        $tab->show_analysis($analysis);
    }

    return;
}

sub on_export {
    my $self = shift;

    my $selected = $self->get_selection();
    my $object;
    $selected->{type} //= '';
    if ($selected->{type} eq 'output') {
        $object = $selected->{output_ref};
        say "[Outputs tab] Exporting output " . $object->get_name;
    }
    elsif ($selected->{type} eq 'basedata') {

        # Show "Save changes?" dialog
        my $gui = $self->{gui};
        my $dlgxml = Gtk3::Builder->new();
        $dlgxml->add_from_file($gui->get_gtk_ui_file('dlgGroupsLabels.ui'));

        my $dlg = $dlgxml->get_object('dlgGroupsLabels');
        $dlg->set_transient_for( $gui->get_object('wndMain') );
        $dlg->set_modal(1);
        my $response = $dlg->run();
        $dlg->destroy();

        # Check response
        if ($response eq 'yes') {
            $object = $selected->{basedata_ref}->get_labels_ref;
            print "[Outputs tab] Exporting basedata labels\n";
        }
        elsif ($response eq 'no') {
            $object = $selected->{basedata_ref}->get_groups_ref;
            print "[Outputs tab] Exporting basedata groups\n";
        }
        else {
            return; # closed dialog, or something
        }

    }

    Biodiverse::GUI::Export::Run($object);

    return;
}

sub on_rename {
    my $self = shift;

    my $selected = $self->get_selection();

    my $gui = $self->{gui};
    if (not defined $selected->{type}) {
        $selected->{type} = q{};
    }
    if ($selected->{type} eq 'basedata') {
        $gui->do_rename_basedata ($selected);
    }
    elsif ($selected->{type} eq 'output') {
        my $object = $selected->{output_ref};
        $gui->do_rename_output ($selected);
    }

    return;
}

sub on_describe {
    my $self = shift;

    my $gui = $self->{gui};
    $gui->do_describe_basedata ();

    return;
}


sub on_delete {
    my $self = shift;

    my $selected = $self->get_selection();
    return 0 if not defined $selected;

    my $basedata_ref = $selected->{basedata_ref};
    my $output_ref = $selected->{output_ref};
    my $tab = $selected->{tab};
    my $dialog = undef;

    if ($selected->{type} eq 'output') {
        $selected = undef;

        my $name = $output_ref->get_param('NAME');

        my $msg = "Delete output $name?";

        if (blessed ($output_ref) =~ /Randomise/) {
            $msg .= "\n(This will remove all results in "
                    . "Spatial and Cluster outputs).\n";
        }

        # Confirmation dialog
        $dialog = Gtk3::MessageDialog->new (
            $self->{gui}->get_object('wndMain'),
            'destroy-with-parent',
            'question',
            'yes-no',
            $msg
        );

        my $response = $dialog->run;
        $dialog->destroy;

        if ($response eq 'yes') {

            print "[Outputs tab] Deleting output $name\n";
            $self->{gui}->get_project->delete_output($output_ref); # delete from model

            # delete from basedata
            eval {   #  let basedata handle it
                $basedata_ref->delete_output (output => $output_ref)
            };
            if ($EVAL_ERROR) {
                $self->{gui}->report_error ($EVAL_ERROR);
            }

            # Close any tabs with this output
            if (defined $tab and (blessed $tab) !~ /Outputs$/) {
                $self->{gui}->remove_tab($tab);
            }
        }
    }
    elsif ($selected->{type} eq 'basedata') {
        $selected = undef;
        my $name = $basedata_ref->get_param('NAME');

        # Confirmation dialog
        $dialog = Gtk3::MessageDialog->new (
            $self->{gui}->get_object('wndMain'),
            'destroy-with-parent',
            'question',
            'yes-no',
            "Delete basedata $name?",
        );

        my $response = $dialog->run;
        $dialog->destroy;

        if ($response eq 'yes') {

            print "[Outputs tab] Deleting basedata $name\n";
            $self->{gui}->get_project->delete_base_data($basedata_ref);

            # Need to close any tabs associated with this basedata
            if (defined $tab) {
                $self->{gui}->remove_tab($tab);
            }
            my @tabs = @{ $self->{tabs} // [] };
            foreach my $tab (@tabs) {
                next if ( blessed $tab) =~ /Outputs$/;
                if ( $tab->get_base_ref eq $basedata_ref ) {
                    $tab->on_close;
                }
            }
        }

    }

    return;
}

#  ignore keyboard events for now (was triggering when exporting outputs)
sub on_bare_key {}

1;
