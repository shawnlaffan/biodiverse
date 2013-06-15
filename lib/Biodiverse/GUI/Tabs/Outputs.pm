package Biodiverse::GUI::Tabs::Outputs;
use strict;
use warnings;
use Carp;

use Scalar::Util qw { blessed };

use Gtk2;
use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;
use Biodiverse::GUI::Export;

use English ( -no_match_vars );

our $VERSION = '0.18_006';

use base qw {Biodiverse::GUI::Tabs::Tab};

sub new {
    my $class = shift;
    
    my $self = {gui => Biodiverse::GUI::GUIManager->instance};
    #weaken ($self->{gui}) if (not isweak ($self->{gui}));  #  avoid circular refs?
    bless $self, $class;

    # Load _new_ widgets from glade 
    # (we can have many Analysis tabs open, for example. These have a different object/widgets)
    $self->{xmlPage}  = Gtk2::GladeXML->new(
        $self->{gui}->getGladeFile,
        'hboxOutputsPage',
    );
    $self->{xmlLabel} = Gtk2::GladeXML->new(
        $self->{gui}->getGladeFile,
        'hboxOutputsLabel',
    );

    my $page  = $self->{xmlPage} ->get_widget('hboxOutputsPage');
    my $label = $self->{xmlLabel}->get_widget('hboxOutputsLabel');
    my $menu_label = Gtk2::Label->new ('Outputs tab');

    # Add to notebook
    $self->{notebook}   = $self->{gui}->getNotebook();
    $self->{notebook}->prepend_page_menu($page, $label, $menu_label);
    $self->{page}       = $page;
    $self->{gui}->addTab($self);
    

    $self->set_tab_reorderable($page);

    # Initialise the tree
    my $tree = $self->{xmlPage}->get_widget('outputsTree');
    
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
        my $textRenderer = Gtk2::CellRendererText->new();
        if ($column_type eq 'Type') {
            $textRenderer->set(style => 'italic');
        }
        $tree->insert_column_with_attributes(
            -1,
            $column_type,
            $textRenderer,
            text => $text,
        );
    }

    my $model = $self->{gui}->getProject->getBaseDataOutputModel();
    $tree->set_model( $model );
    $tree->columns_autosize;

    # Monitor for new rows, so that we can expand basedatas
    $model->signal_connect('row-inserted' => \&onRowInserted, $self);
    
    # Connect signals
    #$self->{xmlLabel}->get_widget("btnOutputsClose")->signal_connect_swapped(clicked => \&Tabs::Tab::onClose, $self);
    my $xml_page = $self->{xmlPage};
    $xml_page->get_widget('btnOutputsShow'  )->signal_connect_swapped(clicked => \&onShow,   $self);
    $xml_page->get_widget('btnOutputsExport')->signal_connect_swapped(clicked => \&onExport, $self);
    $xml_page->get_widget('btnOutputsDelete')->signal_connect_swapped(clicked => \&onDelete, $self);
    $xml_page->get_widget('btnOutputsRename')->signal_connect_swapped(clicked => \&onRename, $self);
    $xml_page->get_widget('btnOutputsDescribe')->signal_connect_swapped(clicked => \&onDescribe, $self);
    
    
    
    $tree->signal_connect_swapped('row-activated', \&onRowActivated, $self);
    $tree->get_selection->signal_connect_swapped(
        'changed',
        \&onRowChanged,
        $self,
    );
    $tree->signal_connect_swapped('row-collapsed' => \&onRowCollapsed, $self);

    print "[Outputs tab] Loaded tab - Outputs\n";

    return $self;
}

sub getType { return 'outputs'; }

sub getRemovable { return 0; } # output tab cannot be closed

# Get lots of information about currently selected row
sub getSelection {
    my $self = shift;

    my $tree    = $self->{xmlPage}->get_widget('outputsTree');
    my $project = $self->{gui}->getProject;
    
    return if not defined $project;
    
    my $model = $project->getBaseDataOutputModel();

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

sub onRowInserted {
    my ($model, $path, $iter, $self) = @_;

    # If an output row has been added, we expand the parent (basedata row)
    my $iter_parent = $model->iter_parent($iter);
    
    if ($iter_parent && ($model->get($iter_parent, MODEL_BASEDATA_ROW) == 1) ) {
        my $tree = $self->{xmlPage}->get_widget('outputsTree');
        $tree->expand_row($model->get_path($iter_parent), 0);
    }
    
    return;
}

sub onRowActivated {
    my $self = shift;
    
    eval {
        $self->onShow();
    };
    if ($EVAL_ERROR) {
        $self->{gui}->report_error ($EVAL_ERROR);
    }
    
    return;
}

# Enable/disable buttons based on selected row
sub onRowChanged {
    my $self = shift;

    my $selected = $self->getSelection();
    my $type = $selected->{type};
    
    return if not defined $type;

    my $sensitive = $type eq 'output' || $type eq 'basedata';

    my $xml_page = $self->{xmlPage};
    my @widget_name_array
        = qw /btnOutputsExport btnOutputsDelete btnOutputsRename/;
        
    foreach my $widget_name (@widget_name_array) {
        $xml_page->get_widget($widget_name)->set_sensitive($sensitive);
    }
    
    # If clicked on basedata, select it
    if ($type eq 'basedata') {
        $self->{gui}->getProject->selectBaseData($selected->{basedata_ref}) ;
    }
    
    return;
}

#  resize the contents - this reclaims unused horizontal space 
sub onRowCollapsed {
    my $self = shift;
    my $tree = $self->{xmlPage}->get_widget('outputsTree');
    
    $tree->columns_autosize();
    
    return;
}

# Switch to the output's analysis tab or create a new one
sub onShow {
    my $self = shift;

    my $selected = $self->getSelection();
    
    #  (was "return 0")
    return if not defined $selected;

    # If double-clicked basedata row, show labels
    if ($selected->{type} eq 'basedata') {
        my $labels = eval {Biodiverse::GUI::Tabs::Labels->new()};
        if ($EVAL_ERROR) {
            $self->{gui}->report_error ($EVAL_ERROR);
            return;
        }
    }

    # Otherwise, we only care about analysis rows
    return if not defined $selected->{output_ref};

    my $output_ref = $selected->{output_ref};
    my $analysis   = $selected->{analysis};
    my $tab        = $selected->{tab};
    my $iter       = $selected->{iter}; # unused

    # Tabs should register themselves in the model
    if (defined $tab) {
        # Switch to it
        print "[Outputs tab] Switching to analysis tab\n";
        $self->{gui}->switchTab($tab);
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
                croak 'Outputs::onShow - unsupported output type ' . $type;
            }
        };
        if ($EVAL_ERROR) {
            $self->{gui}->report_error ($EVAL_ERROR);
            if ($tab) {
                $tab->onClose;
            }
            return;
        }
    }

    if (defined $analysis) {
        $tab->showAnalysis($analysis);
    }
    
    return;
}

sub onExport {
    my $self = shift;

    my $selected = $self->getSelection();
    my $object;
    $selected->{type} = "" if ! defined $selected->{type};
    if ($selected->{type} eq 'output') {
        $object = $selected->{output_ref};    
        print "[Outputs tab] Exporting output\n";
    }
    elsif ($selected->{type} eq 'basedata') {

        # Show "Save changes?" dialog
        my $gui = $self->{gui};
        my $dlgxml = Gtk2::GladeXML->new($gui->getGladeFile, 'dlgGroupsLabels');
        my $dlg = $dlgxml->get_widget('dlgGroupsLabels');
        $dlg->set_transient_for( $gui->getWidget('wndMain') );
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

sub onRename {
    my $self = shift;

    my $selected = $self->getSelection();

    my $gui = $self->{gui};
    if (not defined $selected->{type}) {
        $selected->{type} = q{};
    }
    if ($selected->{type} eq 'basedata') {
        $gui->doRenameBasedata ($selected);
    }
    elsif ($selected->{type} eq 'output') {
        my $object = $selected->{output_ref};
        $gui->doRenameOutput ($selected);
    }

    return;
}

sub onDescribe {
    my $self = shift;

    my $gui = $self->{gui};
    $gui->doDescribeBasedata ();

    return;
}


sub onDelete {
    my $self = shift;

    my $selected = $self->getSelection();
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
        $dialog = Gtk2::MessageDialog->new (
            $self->{gui}->getWidget('wndMain'),
            'destroy-with-parent',
            'question',
            'yes-no',
            $msg
        );

        my $response = $dialog->run;
        $dialog->destroy;

        if ($response eq 'yes') {

            print "[Outputs tab] Deleting output $name\n";
            $self->{gui}->getProject->deleteOutput($output_ref); # delete from model

            # delete from basedata
            eval {   #  let basedata handle it
                $basedata_ref->delete_output (output => $output_ref)
            };  
            if ($EVAL_ERROR) {
                $self->{gui}->report_error ($EVAL_ERROR);
            }

            # Close any tabs with this output
            if (defined $tab and (blessed $tab) !~ /Outputs$/) {
                $self->{gui}->removeTab($tab);
            }
        }
    }
    elsif ($selected->{type} eq 'basedata') {
        $selected = undef;
        my $name = $basedata_ref->get_param('NAME');

        # Confirmation dialog
        $dialog = Gtk2::MessageDialog->new (
            $self->{gui}->getWidget('wndMain'),
            'destroy-with-parent',
            'question',
            'yes-no',
            "Delete basedata $name?",
        );
        
        my $response = $dialog->run;
        $dialog->destroy;

        if ($response eq 'yes') {
            
            print "[Outputs tab] Deleting basedata $name\n";
            $self->{gui}->getProject->deleteBaseData($basedata_ref);

            # Need to close any tabs associated with this basedata - currently am not doing that
            if (defined $tab) {
                $self->{gui}->removeTab($tab);
            }
        }

    }

    return;
}


1;
