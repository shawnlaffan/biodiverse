package Biodiverse::GUI::Tabs::SpatialMatrix;
use strict;
use warnings;

use English ( -no_match_vars );

our $VERSION = '0.16';

use Gtk2;
use Carp;
use Scalar::Util qw /blessed looks_like_number/;

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Grid;
use Biodiverse::GUI::Overlays;
use Biodiverse::GUI::Project;

use Biodiverse::Matrix;  #  needed?
use Data::Dumper;

use base qw {
    Biodiverse::GUI::Tabs::Spatial
    Biodiverse::GUI::Tabs::Tab
};


my $NULL_STRING = q{};
my $elements_list_name = 'ELEMENTS';

##################################################
# Initialisation
##################################################

sub new {
    my $class = shift;
    my $matrix_ref = shift; # will be undef if none specified

    croak "argument matrix_ref not specified\n" if !$matrix_ref;
    
    my $self = {gui => Biodiverse::GUI::GUIManager->instance()};
    $self->{project} = $self->{gui}->getProject();
    bless $self, $class;

    my $bd = $matrix_ref->get_param('BASEDATA_REF');
    my $groups_ref = $bd->get_groups_ref;
    $self->{basedata_ref} = $bd;
    $self->{output_ref}   = $matrix_ref;
    $self->{groups_ref}   = $groups_ref;
    $self->{output_name}  = $matrix_ref->get_param('NAME');
    
    # handle pre v0.16 basestructs that didn't have this ref
    if (! $groups_ref->get_param('BASEDATA_REF')) {
        $groups_ref->set_param(BASEDATA_REF => $bd);
        $groups_ref->weaken_basedata_ref;
    }

    # Load _new_ widgets from glade 
    # (we can have many Analysis tabs open, for example. These have a different object/widgets)
    $self->{xmlPage}  = Gtk2::GladeXML->new($self->{gui}->getGladeFile, 'vpaneSpatial');
    $self->{xmlLabel} = Gtk2::GladeXML->new($self->{gui}->getGladeFile, 'hboxSpatialLabel');

    my $page  = $self->{xmlPage}->get_widget('vpaneSpatial');
    my $label = $self->{xmlLabel}->get_widget('hboxSpatialLabel');
    my $label_text = $self->{xmlLabel}->get_widget('lblSpatialName')->get_text;
    my $label_widget = Gtk2::Label->new ($label_text);
    $self->{tab_menu_label} = $label_widget;

    # Add to notebook
    $self->add_to_notebook (
        page         => $page,
        label        => $label,
        label_widget => $label_widget,
    );

    my ($elt_count, $completed);  #  used to control display

    croak "Only existing outputs can be displayed\n" if (not defined $groups_ref );

    #else {
        # We're being called to show an EXISTING output

        # Register as a tab for this output
        $self->registerInOutputsModel($matrix_ref, $self);
        
        $elt_count = $groups_ref  -> get_element_count;
        $completed = $groups_ref  -> get_param ('COMPLETED');
        $completed = 1 if not defined $completed;  #  backwards compatibility - old versions did not have this flag

        my $elements = $groups_ref->get_element_list_sorted;
        $self->{selected_element} = $elements->[0];
        
        print "[SpatialMatrix tab] Existing matrix output - " . $self->{output_name}
              . ". Part of Basedata set - "
              . ($self->{basedata_ref} -> get_param ('NAME') || "no name")
              . "\n";

        $self->queueSetPane(0.01);
        $self->{existing} = 1;
    #}

    # Initialise widgets
    $self->{title_widget} = $self->{xmlPage} ->get_widget('txtSpatialName');
    $self->{label_widget} = $self->{xmlLabel}->get_widget('lblSpatialName');
    
    $self->{title_widget}->set_text($self->{output_name} );
    $self->{label_widget}->set_text($self->{output_name} );


    #$self->{hover_neighbours} = 'Both';
    #$self->{xmlPage}->get_widget('comboNeighbours') ->set_active(3);
    $self->{xmlPage}->get_widget('comboSpatialStretch')->set_active(0);
    $self->{xmlPage}->get_widget('comboNeighbours') ->hide;
    $self->{xmlPage}->get_widget('comboColours')    ->set_active(0);
    $self->{xmlPage}->get_widget('colourButton')    ->set_color(
        Gtk2::Gdk::Color->new(65535,0,0)  # red
    ); 

    $self->set_plot_min_max_values;


    eval {
        $self->initGrid();
    };
    if ($EVAL_ERROR) {
        $self->{gui}->report_error ($EVAL_ERROR);
        $self->onClose;
    }


    #  CONVERT THIS TO A HASH BASED LOOP, as per Clustering.pm
    # Connect signals
    $self->{xmlLabel}->get_widget('btnSpatialClose')->signal_connect_swapped(clicked   => \&onClose,                 $self);
    $self->{xmlPage} ->get_widget('btnSpatialRun')  ->signal_connect_swapped(clicked   => \&onRun,                   $self);
    $self->{xmlPage} ->get_widget('btnOverlays')    ->signal_connect_swapped(clicked   => \&onOverlays,              $self);
    $self->{xmlPage} ->get_widget('txtSpatialName') ->signal_connect_swapped(changed   => \&onNameChanged,           $self);
    $self->{xmlPage} ->get_widget('comboAnalyses')  ->signal_connect_swapped(changed   => \&onActiveAnalysisChanged, $self);
    #$self->{xmlPage} ->get_widget('comboLists')     ->signal_connect_swapped(changed   => \&onActiveListChanged,     $self);
    $self->{xmlPage} ->get_widget('comboColours')   ->signal_connect_swapped(changed   => \&onColoursChanged,        $self);
    $self->{xmlPage} ->get_widget('comboSpatialStretch')->signal_connect_swapped(changed => \&onStretchChanged,      $self);

    $self->{xmlPage} ->get_widget('btnZoomIn')      ->signal_connect_swapped(clicked   => \&onZoomIn,                $self);
    $self->{xmlPage} ->get_widget('btnZoomOut')     ->signal_connect_swapped(clicked   => \&onZoomOut,               $self);
    $self->{xmlPage} ->get_widget('btnZoomFit')     ->signal_connect_swapped(clicked   => \&onZoomFit,               $self);
    $self->{xmlPage} ->get_widget('colourButton')   ->signal_connect_swapped(color_set => \&onColourSet,             $self);
    
    #  do some hiding
    my @to_hide = qw /
        comboLists
        comboNeighbours
        label_spatial_neighbours_combo
        frame_spatial_analysis_tree
        separatortoolitem4
        btnSpatialRun
        labelNbrSet1
        labelNbrSet2
        labelDefQuery1
    /;
    foreach my $w_name (@to_hide) {
        $self->{xmlPage}->get_widget($w_name)->hide;
    }

    $self->initOutputAnalysesCombo();
    

    $self -> set_frame_label_widget;

    print "[SpatialMatrix tab] - Loaded tab \n";


#  debug stuff
$self->{selected_list} = 'SUBELEMENTS';

    return $self;
}


sub set_frame_label_widget {
    my $self = shift;
    
    my $label = $self->{xmlPage}->get_widget('label_spatial_parameters');
    $label->hide;
    return;
    
    my $widget = Gtk2::ToggleButton->new_with_label('Parameters');
    $widget -> show;

    my $frame = $self->{xmlPage}->get_widget('frame_spatial_parameters');
    $frame -> set_label_widget ($widget);

    $widget->signal_connect_swapped (
        clicked => \&on_show_hide_parameters,
        $self,
    );
    $widget->set_active (0);
    $widget->set_has_tooltip (1);
    $widget->set_tooltip_text ('show/hide the parameters section');

    return;
}

sub on_show_hide_parameters {
    my $self = shift;
    return;

}


sub initGrid {
    my $self = shift;
    my $frame   = $self->{xmlPage}->get_widget('gridFrame');
    my $hscroll = $self->{xmlPage}->get_widget('gridHScroll');
    my $vscroll = $self->{xmlPage}->get_widget('gridVScroll');

#print "Initialising grid\n";

    # Use closure to automatically pass $self (which grid doesn't know)
    my $hover_closure = sub { $self->onGridHover(@_); };
    my $click_closure = sub {
        Biodiverse::GUI::CellPopup::cellClicked(
            $_[0],
            $self->{groups_ref},
        );
    };
    my $select_closure = sub {
        $self->on_cell_selected ( @_ );
    };

    $self->{grid} = Biodiverse::GUI::Grid->new(
        $frame,
        $hscroll,
        $vscroll,
        1,
        0,
        $hover_closure,
        $click_closure,
        $select_closure,
    );

    my $data = $self->{groups_ref};  #  should be the groups?
    my $elt_count = $data -> get_element_count;
    my $completed = $data -> get_param ('COMPLETED');
    #  backwards compatibility - old versions did not have this flag
    $completed = 1 if not defined $completed;  
    
    if (defined $data and $elt_count and $completed) {
        $self->{grid}->setBaseStruct ($data);
    }

    
    return;
}

sub initListsCombo {
    my $self = shift;
    return;

}

sub updateListsCombo {
    my $self = shift;
    return;
}


# Generates ComboBox model with analyses
# (Jaccard, Endemism, CMP_XXXX) that can be shown on the grid
sub makeOutputAnalysisModel {
    my $self = shift;
    
    my $matrix_ref = $self->{output_ref};
    my $element_array = $matrix_ref->get_elements_as_array;
    my $groups_ref = $self->{groups_ref};
    
    # Make model for combobox
    my $model = Gtk2::ListStore->new('Glib::String');
    foreach my $x (reverse $groups_ref->get_element_list_sorted(list => $element_array)) {
        my $iter = $model->append;
        #print ($model -> get($iter, 0), "\n") if defined $model -> get($iter, 0);    #debug
        $model->set($iter, 0, $x);
        #print ($model -> get($iter, 0), "\n") if defined $model -> get($iter, 0);      #debug
    }

    return $model;
}

# Generates ComboBox model with analyses
#  hidden 
sub makeListsModel {
    my $self = shift;
    my $output_ref = $self->{output_ref};

    my $lists = ('$elements_list_name');
 
    # Make model for combobox
    my $model = Gtk2::ListStore->new('Glib::String');
    foreach my $x (sort @$lists) {
        my $iter = $model->append;
        $model->set($iter, 0, $x);
    }

    return $model;
}


##################################################
# Misc interaction with rest of GUI
##################################################

sub getType {
    return "spatialmatrix";
}


##################################################
# Running analyses
##################################################
sub onRun {
    my $self = shift;

    print "[SpatialMatrix] Cannot run this analysis.  "
        . "Use a cluster analysis to generate the matrix\n";

    return;
}

##################################################
# Misc dialog operations
##################################################

sub on_cell_selected {
    my $self = shift;
    my $data = shift;

    my $element;
    if (scalar @$data == 1) {
        $element = $data->[0];
    }
    else {  #  get the first sorted element that is in the matrix
        my @sorted = $self->{groups_ref}->get_element_list_sorted (list => $data);
        CHECK_SORTED:
        while (defined ($element = shift @sorted)) {
            last CHECK_SORTED
              if $self->{output_ref}->element_is_in_matrix (element => $element);
        }
        
    }

    return if ! defined $element;
    return if $element eq $self->{selected_element};
    return if ! $self->{output_ref}->element_is_in_matrix (element => $element);

    #print "Element selected: $element\n";

    $self->{selected_element} = $element;

    my $combo = $self->{xmlPage}->get_widget('comboAnalyses');
    $combo->set_model($self->{output_analysis_model});  #  already have this?

    # Select the previous analysis (or the first one)
    my $iter = $self->{output_analysis_model}->get_iter_first();
    my $selected = $iter;
    
    BY_ITER:
    while ($iter) {
        my ($analysis) = $self->{output_analysis_model}->get($iter, 0);
        if ($self->{selected_element} && ($analysis eq $self->{selected_element}) ) {
            $selected = $iter;
            last BY_ITER; # break loop
        }
        $iter = $self->{output_analysis_model}->iter_next($iter);
    }

    if ($selected) {
        $combo->set_active_iter($selected);
    }
    $self->onActiveAnalysisChanged($combo);

    return;
}

# Called by grid when user hovers over a cell
# and when mouse leaves a cell (element undef)
sub onGridHover {
    my $self = shift;
    my $element = shift;

    return if ! defined $element;

    my $matrix_ref = $self->{output_ref};
    my $output_ref = $self->{groups_ref};
    my $text = '';
    
    my $bd_ref = $output_ref -> get_param ('BASEDATA_REF');

    if ($element) {
        no warnings 'uninitialized';  #  sometimes the selected_list or analysis is undefined
        # Update the Value label
        #my $elts = $output_ref -> get_element_hash();

        my $val = $matrix_ref->get_value (
            element1 => $element,
            element2 => $self->{selected_element},
        );

        $text = defined $val
            ? sprintf (
                '<b>%s</b> v <b>%s</b>, value: %.4f',  #  should list the index used
                $self->{selected_element},
                $element,
                $val,
            ) # round to 4 d.p.
            : '<b>Selected element: ' . $self->{selected_element} . '</b>'; 
        $self->{xmlPage}->get_widget('lblOutput')->set_markup($text);

    }
    
    return;
}


# Called by output tab to make us show some analysis
sub showAnalysis {
    my $self = shift;
    my $name = shift;

    # Reinitialising is a cheap way of showing 
    # the SPATIAL_RESULTS list (the default), and
    # selecting what we want

    #$self->{selected_index} = $name;
    #$self->updateListsCombo();
    $self->updateOutputAnalysesCombo();
    
    return;
}

sub onActiveAnalysisChanged {
    my $self  = shift;
    my $combo = shift
              ||  $self->{xmlPage}->get_widget('comboAnalyses');

    my $iter = $combo->get_active_iter() || return;
    my $element = $self->{output_analysis_model}->get($iter, 0);

    $self->{selected_element} = $element;

    #  This is redundant when only changing the element,
    #  but doesn;t take long and makes stretch changes easier.  
    $self->set_plot_min_max_values;  

    $self->recolour();

    return;
}

    
sub set_plot_min_max_values {
    my $self = shift;
    
    my $matrix_ref = $self->{output_ref};

    my $stats = $self->{stats};

    if (not $stats) {
        $stats = $matrix_ref->get_summary_stats;
        $self->{stats} = $stats;  #  store it
    }

    $self->{max} = $stats->{$self->{PLOT_STAT_MAX} || 'MAX'};
    $self->{min} = $stats->{$self->{PLOT_STAT_MIN} || 'MIN'};

    return;
}

sub recolour {
    my $self = shift;
    my ($max, $min) = ($self->{max} || 0, $self->{min} || 0);

    # callback function to get colour of each element
    my $grid = $self->{grid};
    return if not defined $grid;  #  if no grid then no need to colour.
    
    #my $elements_hash = $self->{groups_ref}->get_element_hash;
    my $matrix_ref    = $self->{output_ref};
    my $sel_element   = $self->{selected_element};

    my $colour_func = sub {
        my $elt = shift;
        if ($elt eq $sel_element) {  #  mid grey
            return $grid->getColourGrey (($min + $max + $max) / 3, $min, $max);
        }
        my $val = $matrix_ref->get_value (
            element1 => $elt,
            element2 => $sel_element,
        );
        return defined $val
            ? $grid->getColour($val, $min, $max)
            : undef;
    };

    $grid->colour($colour_func);
    $grid->setLegendMinMax($min, $max);
    
    return;
}


sub onNeighboursChanged {
    my $self = shift;
    return;
}

#  methods aren't inherited when called as GTK callbacks
#  so we have to manually inherit them using SUPER::
our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self)
                or croak "$self is not an object\n";

    my $method = $AUTOLOAD;
    $method =~ s/.*://;   # strip fully-qualified portion

    $method = 'SUPER::' . $method;
    return $self->$method (@_);
}

sub DESTROY {}  #  let the system handle destruction - need this for AUTOLOADER

1;
