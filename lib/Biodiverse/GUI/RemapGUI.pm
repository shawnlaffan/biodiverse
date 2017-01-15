package Biodiverse::GUI::RemapGUI;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.99_006';

use Gtk2;
use Biodiverse::RemapGuesser qw/guess_remap/;
use English( -no_match_vars );

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Export;
use Biodiverse::ExportRemap qw/:all/;
use Ref::Util qw /:all/;

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
use constant EXPORT_CHECKBUTTON_TOOLTIP 
    => "Save the remapped data source to a file";
use constant IGNORE_CASE_TOOLTIP
    => "Treat case difference as punctuation rather than typos.";
use constant EDIT_DISTANCE_TOOLTIP
    => "New labels within this Levenshtein edit distance of an existing label will be detected as possible typos";

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

sub run_remap_gui {
    my $self = shift;
    my %args = @_;

    my $gui = $args{"gui"};
    my $datasource_being_remapped = $args{datasource_being_remapped} // undef;
    
    ####
    # get the available options to remap labels to

    my @sources = ();
    push @sources, @{ $gui->get_project()->get_base_data_list() };
    push @sources, @{ $gui->get_project()->get_phylogeny_list() };
    push @sources, @{ $gui->get_project()->get_matrix_list() };
    
    # Don't show the datasource being remapped as an option to remap
    # to. Only relevant for menu based remapping.
    if(defined $datasource_being_remapped) {
        my @fixed_sources = ();
        foreach my $source (@sources) {
            if ($source != $datasource_being_remapped) {
                push @fixed_sources, $source;
            }
        }
        @sources = @fixed_sources;
    }
    
    my @source_names;
    foreach my $source (@sources) {
        my $type = blessed $source;
        $type =~ s/^Biodiverse:://;
        push @source_names, "$type: " . $source->get_name;
    }

    # table to align the controls
    my $table = Gtk2::Table->new( 2, 3, 1 );

    ####
    # The data source selection combo box and its label
    my $data_source_combo = Gtk2::ComboBox->new_text;
    foreach my $option (@source_names) {
        $data_source_combo->append_text($option);
    }
    $data_source_combo->set_active(0);
    $data_source_combo->show_all;
    $data_source_combo->set_tooltip_text (
        'Choose a data source to remap the labels to.'
    );
    my $data_source_label =
      Gtk2::Label->new('Data source to remap the labels to:');

    $table->attach_defaults( $data_source_label, 0, 1, 0, 1 );
    $table->attach_defaults( $data_source_combo, 1, 2, 0, 1 );

    ####
    # The max_distance spinbutton and its label
    my $adjustment = Gtk2::Adjustment->new( 0,           0, 20, 1, 10, 0 );
    my $spinner    = Gtk2::SpinButton->new( $adjustment, 1, 0 );
    my $max_distance_label = Gtk2::Label->new('Maximum acceptable distance:');

    $spinner->set_tooltip_text(EDIT_DISTANCE_TOOLTIP);
    
    # my $tooltip    = Gtk2::Tooltips->new();
    # $tooltip->set_tip(
    #     $spinner,
    #       'New labels within this Levenshtein edit distance of an existing label '
    #     . " will be detected as possible typos.",
    # );

    ####
    # The case sensitivity checkbutton
    my $case_label = Gtk2::Label->new('Match case insensitively?');
    my $case_checkbutton = Gtk2::CheckButton->new();
    $case_checkbutton->set_active(0);
    $case_checkbutton->set_tooltip_text(IGNORE_CASE_TOOLTIP);

    $table->attach_defaults ($max_distance_label, 0, 1, 1, 2 );
    $table->attach_defaults ($spinner,            1, 2, 1, 2 );
    $table->attach_defaults ($case_label,         0, 1, 2, 3 );
    $table->attach_defaults ($case_checkbutton,   1, 2, 2, 3 );

    ####
    # The auto/manual checkbutton

    my $auto_checkbutton = Gtk2::CheckButton->new("Automatic remap");

    # sometimes we don't want to prompt for auto/manual so check the
    # flag for that
    if ( !$args{no_manual} ) {
        $auto_checkbutton->set_active(0);
        $auto_checkbutton->signal_connect(
            toggled => sub {
                $table->set_sensitive( !$table->get_sensitive );
            }
        );

        # start out disabled
        $table->set_sensitive(0);
    }

    ####
    # The dialog itself
    my $dlg = Gtk2::Dialog->new_with_buttons(
        'Remap labels?',
        undef, 'modal',
        'gtk-yes' => 'yes',
        'gtk-no'  => 'no',
    );

    ####
    # Pack everything in
    my $vbox = $dlg->get_content_area;

    my $hbox = Gtk2::HBox->new();
    if ( !$args{no_manual} ) {
        $hbox->pack_start( $auto_checkbutton, 0, 1, 0 );
    }
    $vbox->pack_start( $hbox,  0, 0, 0 );
    $vbox->pack_start( $table, 0, 0, 0 );

    # if there are no data sources available, disable the auto
    # remap options.    
    if( scalar @sources == 0 ) {
        $auto_checkbutton->set_active(0);
        $auto_checkbutton->set_sensitive(0);
    }

    $dlg->show_all;

    my $response = $dlg->run();

    my $remap_type;
    
    if ( $response eq "no" ) {
        $remap_type = "none";
    }
    elsif ( $response eq "yes" ) {

        # check the state of the checkbox
        if ( $args{no_manual} || $auto_checkbutton->get_active() ) {
            $remap_type = "auto";
        }
        else {
            $remap_type = "manual";
        }
    }
    else {
        say "[RemapGUI] Unknown dialog response: $response";
    }

    $dlg->destroy();

    my $max_distance = $spinner->get_value_as_int();
    my $ignore_case  = $case_checkbutton->get_active();

    my $choice = $sources[ $data_source_combo->get_active ];

    my %results = (
        remap_type        => $remap_type,
        datasource_choice => $choice,
        max_distance      => $max_distance,
        ignore_case       => $ignore_case,
    );

    return wantarray ? %results : \%results;
}

# given a gui and a data source, perform an automatic remap
# including showing the remap analysis/breakdown dialog
sub perform_remap {
    my $self = shift;
    my $args = shift;

    my $new_source   = $args->{ new_source   };
    my $old_source   = $args->{ old_source   };
    my $max_distance = $args->{ max_distance };
    my $ignore_case  = $args->{ ignore_case  };

    # is there a list of sources whose labels we should combine?
    my $remapping_multiple_sources = is_arrayref($new_source);

    # actually do the remap
    my $guesser       = Biodiverse::RemapGuesser->new();
    my $remap_results = $guesser->generate_auto_remap(
        {
            existing_data_source       => $old_source,
            new_data_source            => $new_source,
            max_distance               => $max_distance,
            ignore_case                => $ignore_case,
            remapping_multiple_sources => $remapping_multiple_sources,
        }
    );

    my $remap       = $remap_results->{remap};
    my $success     = $remap_results->{success};
    my $statsString = $remap_results->{stats};

    my $remap_results_response =
      $self->remap_results_dialog( %{$remap_results} );

    my $response = $remap_results_response->{response};


    
    # now build the remap we actually want to perform

    # remove parts which aren't enabled
    if ( !$remap_results_response->{punct_match_enabled} ) {
        my @punct_matches = @{ $remap_results->{punct_matches} };
        foreach my $key (@punct_matches) {
            delete $remap->{$key};
            say "RemapGUI: deleted $key because it was punct matched";
        }
    }

    if ( !$remap_results_response->{typo_match_enabled} ) {
        my @typo_matches = @{ $remap_results->{typo_matches} };
        foreach my $key (@typo_matches) {
            delete $remap->{$key};
            say "RemapGUI: deleted $key because it was typo matched";
        }
    }

    # remove specific exclusions
    my @exclusions = @{ $remap_results_response->{exclusions} };
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

    
    if ( $response eq 'yes' ) {
        
        # actually perform the remap on the data source
        if( $remapping_multiple_sources ) {
            foreach my $source (@$new_source) {
                $guesser->perform_auto_remap(
                    remap      => $remap,
                    new_source => $source,
                );
            }
        }
        else {
            $guesser->perform_auto_remap(
            remap      => $remap,
            new_source => $new_source,
            );
        }

        # possibly export the new remapping
        if( $remap_results_response->{export_results} ) {
            my $exporter = Biodiverse::ExportRemap->new();
            $exporter->export_remap ( remap => $remap );
        }

        
        
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

    ###
    # Export checkbox 
    my $export_checkbutton 
        = Gtk2::CheckButton->new("Export remapped data to new file");
    
    $export_checkbutton->set_active(0);
    $export_checkbutton->set_tooltip_text(EXPORT_CHECKBUTTON_TOOLTIP);
    
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
        label => "$exact_match_count Exact Matches",
        components => [$exact_match_scroll],
        fill => [1],
        tooltip => EXACT_MATCH_PANEL_TOOLTIP,
        );
    
    my $not_matched_frame = $self->build_vertical_frame (
        label => "$not_matched_count Not Matched",
        components => [$not_matched_scroll],
        fill => [1],
        tooltip => NOT_MATCHED_PANEL_TOOLTIP,
        );

    my $punct_frame = $self->build_vertical_frame (
        label => "$punct_match_count Punctuation Matches ".
                 "(labels within 'max distance' edits of an exact match)",
        components => [$punct_match_checkbutton, $punct_match_scroll],
        fill => [0, 1],
        tooltip => PUNCT_MATCH_PANEL_TOOLTIP,
        );

    my $typo_frame = $self->build_vertical_frame (
        label => "$typo_match_count Possible Typos",
        components => [$typo_match_checkbutton, $typo_match_scroll],
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
    $vbox->pack_start( $accept_remap_label, 0, 1, 0 );
    $vbox->pack_start( $export_checkbutton, 0, 1, 0 );

    
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

    my $response = $dlg->run();

    $dlg->destroy();

    
    
    my %results = (
        response            => $response,
        punct_match_enabled => $punct_match_checkbutton->get_active,
        typo_match_enabled  => $typo_match_checkbutton->get_active,
        export_results      => $export_checkbutton->get_active,
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
    
    foreach my $i ( 0..scalar(@{$components})-1 ) {
        $vbox->pack_start( $components->[$i], $fill->[$i], 1, 0 );
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

    my @copy_strings;
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
        
        foreach my $tree (@{$trees}) { 
            my $selected_list = $self->get_comma_separated_complete_treeview_list ( 
                tree => $tree,
            );
            foreach my $row (@$selected_list) {
                push @copy_strings, $row;
            }
        }
    }
    my $copy_string = join("\n", @copy_strings);
    my $clipboard = Gtk2::Clipboard->get(Gtk2::Gdk->SELECTION_CLIPBOARD);
    $clipboard->set_text($copy_string);
    say "Copied following data to clipboard:\n$copy_string";
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

1;
