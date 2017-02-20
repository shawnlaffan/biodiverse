package Biodiverse::GUI::RemapGUI;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.99_006';

use Gtk2;
use Biodiverse::RemapGuesser qw/guess_remap/;
use English( -no_match_vars );

use Carp;

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Export;
use Ref::Util qw /:all/;

use List::MoreUtils qw(first_index);

use Text::Levenshtein qw(distance);
use Scalar::Util qw /blessed/;

my $i;
use constant ORIGINAL_LABEL_COL => $i || 0;
use constant REMAPPED_LABEL_COL => ++$i;
use constant PERFORM_COL        => ++$i;
use constant EDIT_DISTANCE_COL  => ++$i;

# tooltips
use constant EXACT_MATCH_PANEL_TOOLTIP  => "";
use constant NOT_MATCHED_PANEL_TOOLTIP  => "";
use constant PUNCT_MATCH_PANEL_TOOLTIP  => "";
use constant TYPO_MATCH_PANEL_TOOLTIP   => "";
use constant LABEL_COLUMN_TOOLTIP
    => "These labels will remain unchanged";
use constant OLD_LABEL_COLUMN_TOOLTIP
    => "Matching label from selected data source";
use constant NEW_LABEL_COLUMN_TOOLTIP   
    => "Label to be remapped";
use constant USE_COLUMN_TOOLTIP
    => "Controls whether individual remappings will be performed";
use constant DISTANCE_COLUMN_TOOLTIP
    => "Number of character changes to get from the original label to the remapped label";
use constant COPY_BUTTON_TOOLTIP        
    => "Copy a comma separated representation of the selected rows to the clipboard";
use constant EXPORT_BUTTON_TOOLTIP 
    => "Save the remapped data source to a file";
use constant IGNORE_CASE_TOOLTIP
    => "Treat case differences as punctuation rather than typos.";
use constant EDIT_DISTANCE_TOOLTIP
    => "New labels within this Levenshtein edit distance of an existing label will be detected as possible typos";
use constant MANUAL_OPTION_TEXT => "From file";

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

# dialog for picking which sources to remap, and what they get
# remapped to as well as properties such as case sensitivity and
# allowable edit distance.
# nomenclature: 'remapee'-> the thing that will undergo remapping
#               'controller' -> the thing that will control the remapping 
#                               e.g. another basedata, tree, matrix or a file.
# TODO put all string constants at the top of the file.
sub pre_remap_dlg {
    my $self = shift;
    my %args = @_;

    my $gui = $args{gui};

    ####
    # get the available options to remap labels to and from
    my @remapee_sources = (
        @{ $gui->get_project->get_base_data_list },
        @{ $gui->get_project->get_phylogeny_list },
        @{ $gui->get_project->get_matrix_list },
    );
    
    my @controller_sources = @remapee_sources;
    unshift @controller_sources, MANUAL_OPTION_TEXT;

    my $selected_basedata = $gui->get_project->get_selected_basedata;

    my $default_remapee
      = $args{default_remapee}
      // $selected_basedata
      // $remapee_sources[0];
    
    # table to align the controls
    my $table = Gtk2::Table->new( 5, 2, 1 );
    $table->set_homogeneous(0);
    $table->set_col_spacings(10);
    
    ####
    # The remapee data source selection combo box and its label, as
    # well as the controller combo box and its label.
    my $remapee_combo = Gtk2::ComboBox->new_text;
    my $controller_combo = Gtk2::ComboBox->new_text;

    foreach my $option (@remapee_sources) {
        $remapee_combo->append_text($self->object_to_name(obj => $option));
    }
    foreach my $option (@controller_sources) {
        $controller_combo->append_text($self->object_to_name(obj => $option));
    }

    my $index = first_index { $_ eq $default_remapee } @remapee_sources;
    $remapee_combo->set_active($index);
    $controller_combo->set_active(0);
    
    $remapee_combo->show_all;
    $controller_combo->show_all;

    $remapee_combo->set_tooltip_text ('Choose a data source to be remapped.');
    $remapee_combo->set_tooltip_text ('Choose a data source to remap to');
    my $remapee_label = Gtk2::Label->new('Data source that will be remapped:');
    my $controller_label = Gtk2::Label->new('Label source:');
    
    $table->attach_defaults( $remapee_label, 0, 1, 0, 1 );
    $table->attach_defaults( $remapee_combo, 1, 2, 0, 1 );
    $table->attach_defaults( $controller_label, 0, 1, 1, 2 );
    $table->attach_defaults( $controller_combo, 1, 2, 1, 2 );
    
    ####
    # The max_distance spinbutton and its label
    my $adjustment = Gtk2::Adjustment->new( 0,           0, 20, 1, 10, 0 );
    my $spinner    = Gtk2::SpinButton->new( $adjustment, 1, 0 );
    my $max_distance_label = Gtk2::Label->new('Maximum acceptable distance:');
    $spinner->set_tooltip_text(EDIT_DISTANCE_TOOLTIP);
    
    ####
    # The case sensitivity checkbutton
    my $case_label = Gtk2::Label->new('Match case insensitively?');
    my $case_checkbutton = Gtk2::CheckButton->new();
    $case_checkbutton->set_active(0);
    $case_checkbutton->set_tooltip_text(IGNORE_CASE_TOOLTIP);

    my $warning_label = Gtk2::Label->new('');
    my $span_leader   = '<span foreground="red">';
    my $span_ender    = '</span>';
    my $warning_text  =  $span_leader . $span_ender;
    $warning_label->set_markup ($warning_text);

    $table->attach_defaults ($max_distance_label, 0, 1, 2, 3 );
    $table->attach_defaults ($spinner,            1, 2, 2, 3 );
    $table->attach_defaults ($case_label,         0, 1, 3, 4 );
    $table->attach_defaults ($case_checkbutton,   1, 2, 3, 4 );
    $table->attach_defaults( $warning_label,      0, 2, 4, 5 );

    # make selecting the manual/file based remap option disable the
    # auto remap setting.
    my @auto_options = (
        $case_label, 
        $case_checkbutton, 
        $spinner,
        $max_distance_label,
    );

    # we start with manual as default
    foreach my $option (@auto_options) {
        $option->set_sensitive(0);
    }

    my $set_same_object_warning = sub {
        my $warning_text = '';
        if ($controller_sources[$controller_combo->get_active]
             eq $remapee_sources[$remapee_combo->get_active]) {
            $warning_text
              = 'Note: remapping an object to itself '
              . 'is pointless.';
        }
        $warning_label->set_markup (
            $span_leader . $warning_text . $span_ender
        );
    };
    my $basedata_has_outputs_warning = sub {
        my $remapee = $remapee_sources[$remapee_combo->get_active];
        if ($remapee->isa('Biodiverse::BaseData')
            && $remapee->get_output_ref_count) {
            $warning_text
              = "Warning: Cannot remap a basedata with outputs.\n"
              . "You can use the 'Duplicate without outputs'\n"
              . "menu option to create a 'clean' version.";
            $warning_label->set_markup (
                $span_leader . $warning_text . $span_ender
            );
        }
    };
    
    $controller_combo->signal_connect(
        changed => sub {
            my $sensitive = ($controller_combo->get_active == 0) ? 0 : 1;
            foreach my $option (@auto_options) {
                $option->set_sensitive($sensitive);
            }
            $set_same_object_warning->();
        }
    );
    $remapee_combo->signal_connect(
        changed => sub {
            $set_same_object_warning->();
            #  basedata warning overrides same object
            $basedata_has_outputs_warning->();
        }
    );

    #  trigger the warnings for the first display
    $set_same_object_warning->();
    $basedata_has_outputs_warning->();
    
    ####
    # The dialog itself
    my $dlg = Gtk2::Dialog->new_with_buttons(
        'Remap labels?',
        undef, 'modal',
        'gtk-ok' => 'ok',
        'gtk-cancel'  => 'cancel',
    );

    ####
    # Pack everything in
    my $vbox = $dlg->get_content_area;
    my $hbox = Gtk2::HBox->new();
    $vbox->pack_start( $hbox,  0, 0, 0 );
    $vbox->pack_start( $table, 0, 0, 0 );
    $dlg->show_all;
    my $response = $dlg->run();

    $dlg->destroy();


    # The dialog has now finished, process the response and figure out
    # what to return.
    my %results;


    if ( $response eq "ok" ) {
        my $remap_type = ($controller_combo->get_active == 0) ? "manual" : "auto";
        my $remapee = $remapee_sources[$remapee_combo->get_active];
        my $controller = $controller_sources[$controller_combo->get_active];
        
        say "Going to remap $remapee using $controller";
        
        %results = (
            remap_type              => $remap_type,
            remapee                 => $remapee,
            controller              => $controller,
            max_distance            => $spinner->get_value_as_int(),
            ignore_case             => $case_checkbutton->get_active(),
        );
    }
    else {
        %results = (remap_type => "none");
    }

    return wantarray ? %results : \%results;
}

# given a gui and a data source, perform an automatic remap
# including showing the remap analysis/breakdown dialog
sub post_auto_remap_dlg {
    my ($self, %args) = @_;
    my $remap_object = $args{remap_object};
    my $remap_hash = $remap_object->to_hash();
    
    croak "[RemapGUI.pm] No auto remap was generated in the remap_object" 
        if (!$remap_object->has_auto_remap);


    my %params = (remap => $remap_hash,);

    my @match_categories = ("exact_matches", "punct_matches", 
                            "typo_matches", "not_matched");
    
    foreach my $category (@match_categories) {
        $params{$category} = 
            $remap_object->get_match_category(category => $category);
    }
                            
    
    my $remap_results_response =
      $self->remap_results_dialog( %params );

    my $response = $remap_results_response->{response};
    
    # now build the remap we actually want to perform
    $remap_hash = $self->build_remap_hash_from_exclusions(
        %$remap_results_response,
        remap => $remap_hash,
        punct_matches => 
            $remap_object->get_match_category(category => "punct_matches"),
        punct_matches => 
            $remap_object->get_match_category(category => "typo_matches"),

        );

    $remap_object->import_from_hash(remap_hash => $remap_hash);
    
    if ( $response eq 'yes' ) {
        say "Performed automatic remap.";
        return 1;
    }
    else {
        say "Declined automatic remap, no remap performed.";
        return 0;
    }

}

# called internally by perform_remap
sub remap_results_dialog {
    my ( $self, %args ) = @_;
    my $remap = $args{remap};

    # most screens are at least 600 pixels high 
    # at least until the biodiverse mobile app is released...
    my $default_dialog_height = 600;
    my $default_dialog_width = 600;
    
    ###
    # Exact matches
    my @exact_matches = @{ $args{exact_matches} };
    my $exact_match_tree = $self->build_bland_tree( labels => \@exact_matches );
    my $exact_match_count = @exact_matches;
    my $exact_match_scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $exact_match_scroll->add($exact_match_tree);

    ###
    # Punctuation matches
    my @punct_matches = @{ $args{punct_matches} };

    # Build the punct_tree
    my $punct_tree = $self->build_punct_tree(
        remap         => $remap,
        punct_matches => \@punct_matches
    );

    my $punct_match_count = @punct_matches;

    my $punct_match_scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $punct_match_scroll->add($punct_tree);

    # 'use this category' checkbutton
    my $punct_match_checkbutton = Gtk2::CheckButton->new("Use this category?");
    $punct_match_checkbutton->set_active(1);
    $punct_match_checkbutton->signal_connect(
        toggled => sub {
            $punct_match_scroll->set_sensitive(
                !$punct_match_scroll->get_sensitive,
            );
            $punct_match_scroll->set_visible($punct_match_checkbutton->get_active),
        }
    );
    

    ###
    # Typo matches
    my @typo_matches = @{ $args{typo_matches} };

    # Build the typo_tree
    my $typo_tree = $self->build_typo_tree(
        remap        => $remap,
        typo_matches => \@typo_matches
    );

    my $typo_match_count = @typo_matches;


    my $typo_match_scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $typo_match_scroll->add($typo_tree);

    my $typo_match_checkbutton = Gtk2::CheckButton->new("Use this category?");
    $typo_match_checkbutton->set_active(1);
    $typo_match_checkbutton->signal_connect(
        toggled => sub {
            $typo_match_scroll->set_sensitive(
                !$typo_match_scroll->get_sensitive
            );
            $typo_match_scroll->set_visible($typo_match_checkbutton->get_active),
        }
    );

    ###
    # Not matched
    my @not_matched        = @{ $args{not_matched} };
    my $not_matched_tree   = $self->build_bland_tree ( labels => \@not_matched );
    my $not_matched_count  = @not_matched;
    my $not_matched_label  = Gtk2::Label->new("$not_matched_count Not Matched:");
    my $not_matched_scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $not_matched_scroll->add($not_matched_tree);

    ###
    # Accept label
    my $accept_remap_label = Gtk2::Label->new("Apply this remapping?");
 
    
    # 'copy selection to clipboard' button
    my $copy_button 
        = Gtk2::Button->new_with_label("Copy selected rows to clipboard");
    $copy_button->set_tooltip_text(COPY_BUTTON_TOOLTIP);
    
    $copy_button->signal_connect('clicked' => sub {
        $self->copy_selected_tree_data_to_clipboard(
            trees => [ $exact_match_tree,  $not_matched_tree, 
                       $punct_tree,        $typo_tree,],
            )
    });


    # export remap to file button
    my $export_button 
        = Gtk2::Button->new_with_label("Export remap to file.");
    $export_button->set_tooltip_text(EXPORT_BUTTON_TOOLTIP);
    
    $export_button->signal_connect('clicked' => sub {
        $remap = $self->build_remap_hash_from_exclusions(
            remap => $remap,
            punct_match_enabled => $punct_match_checkbutton->get_active,
            typo_match_enabled => $typo_match_checkbutton->get_active,
            exclusions => $self->get_exclusions,
            punct_matches => \@punct_matches,
            typo_matches => \@typo_matches,
            );

        my $remap_object = Biodiverse::Remap->new();
        $remap_object->import_from_hash(remap_hash => $remap);
        Biodiverse::GUI::Export::Run($remap_object);
    });

    ####
    # The dialog itself
    my $dlg = Gtk2::Dialog->new_with_buttons(
        'Remap results',
        undef, 'modal',
        'gtk-yes' => 'yes',
        'gtk-no'  => 'no'
        );

    $dlg->set_default_size($default_dialog_width, $default_dialog_height);

    ####
    # Packing
    my $vbox = $dlg->get_content_area;
    $vbox->set_homogeneous(0);
    $vbox->set_spacing(3);

    # build vboxes and frames for each of the main match types
    my @components = ($exact_match_scroll);
    my $exact_frame = $self->build_vertical_frame (
        label => "Exact Matches: $exact_match_count",
        padding => 10,
        components => [$exact_match_scroll],
        fill => [1],
        tooltip => EXACT_MATCH_PANEL_TOOLTIP,
        );
    
    my $not_matched_frame = $self->build_vertical_frame (
        label => "Not Matched: $not_matched_count",
        components => [$not_matched_scroll],
        padding => 10,
        fill => [1],
        tooltip => NOT_MATCHED_PANEL_TOOLTIP,
        );

    my $punct_frame = $self->build_vertical_frame (
        label => "Punctuation Matches: $punct_match_count ".
        "(labels within 'max distance' edits of an exact match)",
        padding => 0,
        components => [$punct_match_checkbutton, $punct_match_scroll],
        fill => [0, 1],
        tooltip => PUNCT_MATCH_PANEL_TOOLTIP,
        );

    my $typo_frame = $self->build_vertical_frame (
        label => "Possible Typos: $typo_match_count",
        components => [$typo_match_checkbutton, $typo_match_scroll],
        padding => 0,
        fill => [0, 1],
        tooltip => TYPO_MATCH_PANEL_TOOLTIP,
        );

    # put these vboxes in vpanes so we can resize
    my $vpaned1 = Gtk2::VPaned->new();
    my $vpaned2 = Gtk2::VPaned->new();
    my $vpaned3 = Gtk2::VPaned->new();

    $vpaned3->pack1($punct_frame, 1, 1);
    $vpaned3->pack2($typo_frame, 1, 1);
    $vpaned2->pack1($not_matched_frame, 1, 1);
    $vpaned2->pack2($vpaned3, 1, 1);
    $vpaned1->pack1($exact_frame, 1, 1);
    $vpaned1->pack2($vpaned2, 1, 1);

    # now put all of these into a scrolled window
    my $outer_scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $outer_scroll->add_with_viewport( $vpaned1 );
    
    $vbox->pack_start($outer_scroll, 1, 1, 0);
    $vbox->pack_start( $copy_button, 0, 0, 0 );
    $vbox->pack_start( $export_button, 0, 1, 0 );
    $vbox->pack_start( $accept_remap_label, 0, 1, 0 );

    
    $dlg->show_all;
   
    if (!$exact_match_count) {
        $exact_match_scroll->hide;
    }
    if (!$punct_match_count) {
        $punct_match_checkbutton->set_active(0);
        $punct_match_scroll->hide;
    }
    if (!$typo_match_count) {
        $typo_match_checkbutton->set_active(0);
        $typo_match_scroll->hide;
    }
    if (!$not_matched_count) {
        $not_matched_scroll->hide;
    }

    my $response = $dlg->run();

    $dlg->destroy();

    
    
    my %results = (
        response            => $response,
        punct_match_enabled => $punct_match_checkbutton->get_active,
        typo_match_enabled  => $typo_match_checkbutton->get_active,
        exclusions          => $self->get_exclusions,
    );

    return wantarray ? %results : \%results;
}

# given a label and list of components, build a frame containing a
# vbox with the provided components. 'fill' is an array of booleans
# indicating whether the corresponding component should fill or not.
sub build_vertical_frame {
    my ($self, %args) = @_;

    my $vbox = Gtk2::VBox->new();
    my $components = $args{components};
    my $fill = $args{fill};
    my $padding = $args{padding};
    
    foreach my $i ( 0..scalar(@{$components})-1 ) {
        $vbox->pack_start( $components->[$i], $fill->[$i], 1, $padding );
    }

    my $frame = Gtk2::Frame->new( $args{label} );
    $frame->set_shadow_type('in');
    $frame->add($vbox);
    $frame->set_tooltip_text( $args{"tooltip"} );

    return $frame;
}

# build a one column tree containing labels from args{labels}
sub build_bland_tree {
    my ( $self, %args ) = @_;

    my @labels = @{ $args{labels} };

    # start by building the TreeModel
    my @treestore_args = (
        'Glib::String',    # Original value
    );

    my $model = Gtk2::TreeStore->new(@treestore_args);

    foreach my $label (@labels) {
        my $iter = $model->append(undef);
        $model->set( $iter, ORIGINAL_LABEL_COL, $label, );
    }

    my $tree = Gtk2::TreeView->new($model);
    my $sel = $tree->get_selection();
    $sel->set_mode('multiple');
    
    # make the columns for the tree and renderers to match up the
    # columns to the model data.
    my $column = Gtk2::TreeViewColumn->new();


    $self->add_header_and_tooltip_to_treeview_column (
        column       => $column,
        title_text   => 'Label',
        tooltip_text => LABEL_COLUMN_TOOLTIP,
        );
        
    my $renderer = Gtk2::CellRendererText->new();
    
    $column->pack_start( $renderer, 0 );

    # tell the renderer where to pull the data from
    $column->add_attribute( $renderer, text => ORIGINAL_LABEL_COL );

    $tree->append_column($column);

    $column->set_sort_column_id(ORIGINAL_LABEL_COL);

    return $tree;
}


# given the return values from remap_results_dialog, figures out a
# clean remap hash. Can also be used for 'live'
# exporting. (i.e. before the remap has been accepted)

# expects an args hash with a remap, punct_match_enabled,
# typo_match_enabled, puct_matches, typo_matches, exclusions
sub build_remap_hash_from_exclusions {
    my ($self, %args) = @_;
    my $remap = $args{remap};
    
    # remove parts which aren't enabled
    if ( !$args{punct_match_enabled} and $args{punct_matches}) {
        my @punct_matches = @{ $args{punct_matches} };
        foreach my $key (@punct_matches) {
            delete $remap->{$key};
            say "RemapGUI: deleted $key because it was punct matched";
        }
    }

    if ( !$args{typo_match_enabled} and $args{typo_matches}) {
        my @typo_matches = @{ $args{typo_matches} };
        foreach my $key (@typo_matches) {
            delete $remap->{$key};
            say "RemapGUI: deleted $key because it was typo matched";
        }
    }

    # remove specific exclusions
    my @exclusions = @{ $args{exclusions} };
    foreach my $key (@exclusions) {
        delete $remap->{$key};
        say "Deleted $key because it was excluded by the checkboxes.";
    }

    # remove exact matches and not matches here as well
    my @keys = keys %{$remap};
    foreach my $key (@keys) {
        if ($key eq $remap->{$key}) {
            delete $remap->{$key};
            say "Deleted $key because it mapped to itself.";
        }
    }

    return $remap;
}

sub build_typo_tree {
    my ( $self, %args ) = @_;

    my @typo_matches = @{ $args{typo_matches} };
    my $remap        = $args{remap};

    # start by building the TreeModel
    my @treestore_args = (
        'Glib::String',     # Original value
        'Glib::String',     # Remapped value
        'Glib::Boolean',    # Checked?
        'Glib::String',     # Edit distance
    );

    my $typo_model = Gtk2::TreeStore->new(@treestore_args);

    # propagate model with content
    foreach my $match (@typo_matches) {
        my $iter = $typo_model->append(undef);

        # Lazy way of getting edit distance, ideally this wouldn't get
        # calculated in the middle of the gui.
        my $distance = distance( $match, $remap->{$match} );

        $typo_model->set(
            $iter,
            ORIGINAL_LABEL_COL, $match,
            REMAPPED_LABEL_COL, $remap->{$match},
            PERFORM_COL,        1,
            EDIT_DISTANCE_COL,  $distance,
        );
    }

    # allow multi selections
    my $typo_tree = Gtk2::TreeView->new($typo_model);
    my $sel = $typo_tree->get_selection();
    $sel->set_mode('multiple');
    
    # make the columns for the tree and renderers to match up the
    # columns to the model data.
    my $original_column = Gtk2::TreeViewColumn->new();
    my $remapped_column = Gtk2::TreeViewColumn->new();
    my $distance_column = Gtk2::TreeViewColumn->new();
    my $checkbox_column = Gtk2::TreeViewColumn->new();

    # headers and tooltips
    $self->add_header_and_tooltip_to_treeview_column (
        column       => $original_column,
        title_text   => 'Original Label',
        tooltip_text => NEW_LABEL_COLUMN_TOOLTIP,
        );

    $self->add_header_and_tooltip_to_treeview_column (
        column       => $remapped_column,
        title_text   => 'Remapped Label',
        tooltip_text => OLD_LABEL_COLUMN_TOOLTIP,
        );

    $self->add_header_and_tooltip_to_treeview_column (
        column       => $distance_column,
        title_text   => 'Edit Distance',
        tooltip_text => DISTANCE_COLUMN_TOOLTIP,
        );

    $self->add_header_and_tooltip_to_treeview_column (
        column       => $checkbox_column,
        title_text   => 'Use?',
        tooltip_text => USE_COLUMN_TOOLTIP,
        );

    # create and pack cell renderers
    my $original_renderer = Gtk2::CellRendererText->new();
    my $remapped_renderer = Gtk2::CellRendererText->new();
    my $distance_renderer = Gtk2::CellRendererText->new();
    my $checkbox_renderer = Gtk2::CellRendererToggle->new();

    my %data = (
        model => $typo_model,
        self  => $self,
    );
    $checkbox_renderer->signal_connect_swapped(
        toggled => \&on_remap_toggled,
        \%data
    );
        
    $original_column->pack_start( $original_renderer, 0 );
    $remapped_column->pack_start( $remapped_renderer, 0 );
    $distance_column->pack_start( $distance_renderer, 0 );
    $checkbox_column->pack_start( $checkbox_renderer, 0 );

    # tell the renderer where to pull the data from
    $original_column->add_attribute( $original_renderer,
        text => ORIGINAL_LABEL_COL );
    $remapped_column->add_attribute( $remapped_renderer,
        text => REMAPPED_LABEL_COL );
    $distance_column->add_attribute( $distance_renderer,
        text => EDIT_DISTANCE_COL );
    $checkbox_column->add_attribute( $checkbox_renderer,
        active => PERFORM_COL );

    $typo_tree->append_column($checkbox_column);
    $typo_tree->append_column($original_column);
    $typo_tree->append_column($remapped_column);
    $typo_tree->append_column($distance_column);

    $original_column->set_sort_column_id(ORIGINAL_LABEL_COL);
    $remapped_column->set_sort_column_id(REMAPPED_LABEL_COL);
    $distance_column->set_sort_column_id(EDIT_DISTANCE_COL);
    $checkbox_column->set_sort_column_id(PERFORM_COL);

    return $typo_tree;
}

sub build_punct_tree {
    my ( $self, %args ) = @_;

    my @punct_matches = @{ $args{punct_matches} };
    my $remap         = $args{remap};

    # start by building the TreeModel
    my @treestore_args = (
        'Glib::String',     # Original value
        'Glib::String',     # Remapped value
        'Glib::Boolean',    # Checked?
    );

    my $punct_model = Gtk2::TreeStore->new(@treestore_args);

    foreach my $match (@punct_matches) {
        my $iter = $punct_model->append(undef);
        $punct_model->set(
            $iter,
            ORIGINAL_LABEL_COL, $match,
            REMAPPED_LABEL_COL, $remap->{$match},
            PERFORM_COL,        1                  # checkbox enabled by default
        );
    }

    my $punct_tree = Gtk2::TreeView->new($punct_model);
    my $sel = $punct_tree->get_selection();
    $sel->set_mode('multiple');

    
    # make the columns for the tree and renderers to match up the
    # columns to the model data.
    my $original_column = Gtk2::TreeViewColumn->new();
    my $remapped_column = Gtk2::TreeViewColumn->new();
    my $checkbox_column = Gtk2::TreeViewColumn->new();

    $self->add_header_and_tooltip_to_treeview_column (
        column       => $original_column,
        title_text   => 'Original Label',
        tooltip_text => NEW_LABEL_COLUMN_TOOLTIP,
        );

    $self->add_header_and_tooltip_to_treeview_column (
        column       => $remapped_column,
        title_text   => 'Remapped Label',
        tooltip_text => OLD_LABEL_COLUMN_TOOLTIP,
        );

    $self->add_header_and_tooltip_to_treeview_column (
        column       => $checkbox_column,
        title_text   => 'Use?',
        tooltip_text => USE_COLUMN_TOOLTIP,
        );

    my $original_renderer = Gtk2::CellRendererText->new();
    my $remapped_renderer = Gtk2::CellRendererText->new();
    my $checkbox_renderer = Gtk2::CellRendererToggle->new();

    my %data = (
        model => $punct_model,
        self  => $self,
    );

    $checkbox_renderer->signal_connect_swapped(
        toggled => \&on_remap_toggled,
        \%data
    );

    $original_column->pack_start( $original_renderer, 0 );
    $remapped_column->pack_start( $remapped_renderer, 0 );
    $checkbox_column->pack_start( $checkbox_renderer, 0 );
    
    # tell the renderer where to pull the data from
    $original_column->add_attribute( $original_renderer,
        text => ORIGINAL_LABEL_COL );
    $remapped_column->add_attribute( $remapped_renderer,
        text => REMAPPED_LABEL_COL );
    $checkbox_column->add_attribute( $checkbox_renderer,
        active => PERFORM_COL );

    $punct_tree->append_column($checkbox_column);
    $punct_tree->append_column($original_column);
    $punct_tree->append_column($remapped_column);

    $original_column->set_sort_column_id(ORIGINAL_LABEL_COL);
    $remapped_column->set_sort_column_id(REMAPPED_LABEL_COL);
    $checkbox_column->set_sort_column_id(PERFORM_COL);

    return $punct_tree;
}

sub add_exclusion {
    my ( $self, $exclusion ) = @_;

    my @exclusion_list = ();
    if ( exists $self->{exclusions} ) {
        @exclusion_list = @{ $self->{exclusions} };
    }

    push( @exclusion_list, $exclusion );
    $self->{exclusions} = \@exclusion_list;

    return;
}

sub get_exclusions {
    my $self = shift;

    my @exclusion_list = ();
    if ( exists $self->{exclusions} ) {
        @exclusion_list = @{ $self->{exclusions} };
    }

    return \@exclusion_list;
}

sub remove_exclusion {
    my ( $self, $exclusion ) = @_;

    my @exclusion_list = ();
    if ( exists $self->{exclusions} ) {
        @exclusion_list = @{ $self->{exclusions} };
    }

    @exclusion_list = grep { !( $_ eq $exclusion ) } @exclusion_list;
    $self->{exclusions} = \@exclusion_list;

    return;

}

# called when a checkbox is toggled
sub on_remap_toggled {
    my $args = shift;
    my $path = shift;

    my $model = $args->{model};
    my $self  = $args->{self};

    my $iter = $model->get_iter_from_string($path);

    # Flip state
    my $state = $model->get( $iter, PERFORM_COL );
    $model->set( $iter, PERFORM_COL, !$state );

    my $label = $model->get( $iter, ORIGINAL_LABEL_COL );

    if ( !$state ) {
        $self->remove_exclusion($label);
    }
    else {
        $self->add_exclusion($label);
    }
    my $exclusions_ref = $self->get_exclusions();
    my @exclusions     = @{$exclusions_ref};

    #say "found label $label, @exclusions";

    return;

}

# given the four trees, find what rows are selected, get the correct
# data and put it onto the clipboard.
sub copy_selected_tree_data_to_clipboard {
    my ($self, %args) = @_;
    my $trees = $args{trees};

    my @copy_strings = ();
    foreach my $tree (@{$trees}) { 
        my $selected_list = $self->get_comma_separated_selected_treeview_list ( 
            tree => $tree,
        );

        foreach my $row (@$selected_list) {
            push @copy_strings, $row;
        }
    }

    # if they've selected nothing, get everything
    if(scalar @copy_strings == 0) {
        say "Copying to clipboard -> copying everything.";
        
        foreach my $tree (@$trees) { 
            my $selected_list = $self->get_comma_separated_complete_treeview_list ( 
                tree => $tree,
            );
            foreach my $row (@$selected_list) {
                push @copy_strings, $row;
            }
        }
    }
   
    # Some tables don't contain all the fields. For consistency, we
    # want to leave missing fields as empty comma separated values
    # e.g. value1,value2,, rather than just value1,value2.
    

    # find out how many fields the biggest copy string uses.
    my $max_comma_count = 0;
    foreach my $copy_string (@copy_strings) {
        my $comma_count = $copy_string =~ tr/,//;
        $max_comma_count = $comma_count if( $comma_count > $max_comma_count ); 
    }

    # now pad out the other strings to use this many commas as well.
    my @new_copy_strings = ();
    foreach my $copy_string (@copy_strings) {
        push ( @new_copy_strings, 
               $self->pad_string_to_n_commas(str=>$copy_string, 
                                      num_commas=>$max_comma_count)
            );
    }
    @copy_strings = @new_copy_strings;
    
    # now add the appropriate number of headers on the front
    my @headers = ("original_label", "remapped_label",
                   "include", "edit_distance");

    my $header_string = join(",", @headers[0..$max_comma_count]);
    unshift @copy_strings, $header_string;

    my $copy_string = join("\n", @copy_strings);

    my $clipboard = Gtk2::Clipboard->get(Gtk2::Gdk->SELECTION_CLIPBOARD);
    $clipboard->set_text($copy_string);
    say "Copied following data to clipboard:\n$copy_string";
}


# used to add additional rows to comma separated strings with missing
# values. e.g. Value1,Value2 has to fit with Value1,Value2,Value3, so
# we add a comma to the end.
sub pad_string_to_n_commas {
    my ($self, %args) = @_;
    my $max_commas = $args{num_commas};
    my $str = $args{str};
    
    my $comma_count = $str =~ tr/,//;
    my $comma_delta = $max_commas - $comma_count;
    return $str if($comma_delta <= 0);

    $str .= ',' x $comma_delta;

    return $str;
}

# get selected rows of a treeview as comma separated strings.
sub get_comma_separated_selected_treeview_list {
    my ($self, %args) = @_;
    my $tree = $args{tree};

    my @value_list = ();
    
    my $selection = $tree->get_selection();
    my $model = $tree->get_model();
    my $columns = $model->get_n_columns();
    my (@pathlist) = $selection->get_selected_rows();

    foreach my $path (@pathlist) {
        my @column_data = ();
        my $tree_iter = $model->get_iter($path);

        foreach my $i (0..$columns-1) {
            my $value = $model->get_value($tree_iter, $i);
            push @column_data, $value
        }

        my $this_row = join (",", @column_data);
        push @value_list, $this_row;
    }
    
    return \@value_list;
}

# get all rows of a treeview as comma separated strings.
sub get_comma_separated_complete_treeview_list {
    my ($self, %args) = @_;
    
    my $tree = $args{tree};
    my $model = $tree->get_model();
    my $columns = $model->get_n_columns();
        
    my @value_list = ();

    my $iter = $model->get_iter_first();
    while(defined $iter) {
        my @column_data = ();
        
        foreach my $i (0..$columns-1) {
            my $value = $model->get_value($iter, $i);
            push @column_data, $value
        }

        my $this_row = join (",", @column_data);
        push @value_list, $this_row;

        $iter = $model->iter_next( $iter );
    }

    return \@value_list;
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


# given an object, returns a name suitable for printing
sub object_to_name {
    my ($self, %args) = @_;
    my $obj = $args{obj};

    my $type = blessed $obj;

    if($type) {
        $type =~ s/^Biodiverse:://;
        return "$type: " . $obj->get_name;
    }
    else {
        # we got passed a scalar/hash/array, just send it straight
        # back.
        return $obj;
    }
}


1;
