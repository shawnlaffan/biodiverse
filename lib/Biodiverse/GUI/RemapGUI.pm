package Biodiverse::GUI::RemapGUI;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.99_006';

use Gtk2;
use Biodiverse::RemapGuesser qw/guess_remap/;
use English( -no_match_vars );

use Biodiverse::GUI::GUIManager;

use Text::Levenshtein qw(distance);

my $i;
use constant ORIGINAL_LABEL_COL => $i || 0;
use constant REMAPPED_LABEL_COL => ++$i;
use constant PERFORM_COL        => ++$i;
use constant EDIT_DISTANCE_COL  => ++$i;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

sub run_remap_gui {
    my $self = shift;
    my %args = @_;

    my $gui = $args{"gui"};

    ####
# get the available options to remap labels to
# TODO don't allow remapping to yourself (doesn't hurt but just confuses things)
    my @sources = ();
    push @sources, @{ $gui->get_project()->get_base_data_list() };
    push @sources, @{ $gui->get_project()->get_phylogeny_list() };
    push @sources, @{ $gui->get_project()->get_matrix_list() };

    my @source_names;
    foreach my $source (@sources) {
        push @source_names, $source->get_param('NAME');
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
    $data_source_combo->set_tooltip_text(
        'Choose a data source to remap the labels to.');
    my $data_source_label =
      Gtk2::Label->new('Data source to remap the labels to:');

    $table->attach_defaults( $data_source_label, 0, 1, 0, 1 );
    $table->attach_defaults( $data_source_combo, 1, 2, 0, 1 );

    ####
    # The max_distance spinbutton and its label
    my $adjustment = Gtk2::Adjustment->new( 0,           0, 20, 1, 10, 0 );
    my $spinner    = Gtk2::SpinButton->new( $adjustment, 1, 0 );
    my $tooltip    = Gtk2::Tooltips->new();
    my $max_distance_label = Gtk2::Label->new('Maximum acceptable distance:');
    $tooltip->set_tip( $max_distance_label,
"New labels within this many edits of an existing label will be detected as possible typos."
    );

    ####
    # The case sensitivity checkbutton
    my $case_checkbutton =
      Gtk2::CheckButton->new("Treat case difference as punctuation");
    $case_checkbutton->set_active(0);

    $table->attach_defaults( $max_distance_label, 0, 1, 1, 2 );
    $table->attach_defaults( $spinner,            1, 2, 1, 2 );
    $table->attach_defaults( $case_checkbutton,   0, 2, 2, 3 );

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
        'gtk-no'  => 'no'
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
sub perform_remap {
    my $self = shift;
    my $args = shift;

    my $new_source   = $args->{"new_source"};
    my $old_source   = $args->{"old_source"};
    my $max_distance = $args->{"max_distance"};
    my $ignore_case  = $args->{"ignore_case"};

    # actually do the remap
    my $guesser       = Biodiverse::RemapGuesser->new();
    my $remap_results = $guesser->generate_auto_remap(
        {
            "existing_data_source" => $old_source,
            "new_data_source"      => $new_source,
            "max_distance"         => $max_distance,
            "ignore_case"          => $ignore_case
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

            #say "RemapGUI: deleted $key because it was punct matched";
        }
    }

    if ( !$remap_results_response->{typo_match_enabled} ) {
        my @typo_matches = @{ $remap_results->{typo_matches} };
        foreach my $key (@typo_matches) {
            delete $remap->{$key};

            #say "RemapGUI: deleted $key because it was typo matched";
        }
    }

    # remove specific exclusions
    my @exclusions = @{ $remap_results_response->{exclusions} };
    foreach my $key (@exclusions) {
        delete $remap->{$key};

        #say "Deleted $key because it was excluded by the checkboxes.";
    }

    # TODO we could probably remove exact matches and not matches here as well

    if ( $response eq 'yes' ) {
        $guesser->perform_auto_remap(
            remap      => $remap,
            new_source => $new_source,
        );

        say "Performed automatic remap.";
    }
    else {
        say "Declined automatic remap, no remap performed.";
    }

}

# called internally by perform_remap
sub remap_results_dialog {
    my ( $self, %args ) = @_;
    my $remap = $args{remap};

    ###
    # Exact matches
    my @exact_matches = @{ $args{exact_matches} };
    my $exact_match_tree = $self->build_bland_tree( labels => \@exact_matches );
    my $exact_match_count = @exact_matches;
    my $exact_match_label =
      Gtk2::Label->new("$exact_match_count Exact Matches:");
    my $exact_match_scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $exact_match_scroll->set_size_request( 500, 100 );
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
    my $punct_match_label =
      Gtk2::Label->new("$punct_match_count Punct Matches:");

    my $punct_match_scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $punct_match_scroll->set_size_request( 500, 100 );
    $punct_match_scroll->add($punct_tree);

    my $punct_match_checkbutton = Gtk2::CheckButton->new("Use this category");
    $punct_match_checkbutton->set_active(1);
    $punct_match_checkbutton->signal_connect(
        toggled => sub {
            $punct_match_label->set_sensitive(
                !$punct_match_label->get_sensitive );
            $punct_match_scroll->set_sensitive(
                !$punct_match_scroll->get_sensitive );
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

    my $typo_match_label =
      Gtk2::Label->new(
"$typo_match_count Possible Typos: (labels within 'max distance' edits of an exact match)"
      );

    my $typo_match_scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $typo_match_scroll->set_size_request( 500, 100 );
    $typo_match_scroll->add($typo_tree);

    my $typo_match_checkbutton = Gtk2::CheckButton->new("Use this category");
    $typo_match_checkbutton->set_active(1);
    $typo_match_checkbutton->signal_connect(
        toggled => sub {
            $typo_match_label->set_sensitive(
                !$typo_match_label->get_sensitive );
            $typo_match_scroll->set_sensitive(
                !$typo_match_scroll->get_sensitive );
        }
    );

    ###
    # Not matched
    my @not_matched       = @{ $args{not_matched} };
    my $not_matched_tree  = $self->build_bland_tree( labels => \@not_matched );
    my $not_matched_count = @not_matched;
    my $not_matched_label = Gtk2::Label->new("$not_matched_count Not Matched:");
    my $not_matched_scroll = Gtk2::ScrolledWindow->new( undef, undef );
    $not_matched_scroll->set_size_request( 500, 100 );
    $not_matched_scroll->add($not_matched_tree);

    ###
    # Accept label
    my $accept_remap_label = Gtk2::Label->new("Perform this remapping?");

    ####
    # The dialog itself
    my $dlg = Gtk2::Dialog->new_with_buttons(
        'Remap results',
        undef, 'modal',
        'gtk-yes' => 'yes',
        'gtk-no'  => 'no'
    );

    ####
    # Pack everything in
    my $vbox = $dlg->get_content_area;

    my $exact_vbox = Gtk2::VBox->new();
    $exact_vbox->pack_start( $exact_match_label,  0, 1, 0 );
    $exact_vbox->pack_start( $exact_match_scroll, 0, 1, 0 );

    my $not_matched_vbox = Gtk2::VBox->new();
    $not_matched_vbox->pack_start( $not_matched_label,  0, 1, 0 );
    $not_matched_vbox->pack_start( $not_matched_scroll, 0, 1, 0 );

    my $punct_vbox = Gtk2::VBox->new();
    $punct_vbox->pack_start( $punct_match_label,       0, 1, 0 );
    $punct_vbox->pack_start( $punct_match_checkbutton, 0, 1, 0 );
    $punct_vbox->pack_start( $punct_match_scroll,      0, 1, 0 );

    my $typo_vbox = Gtk2::VBox->new();
    $typo_vbox->pack_start( $typo_match_label,       0, 1, 0 );
    $typo_vbox->pack_start( $typo_match_checkbutton, 0, 1, 0 );
    $typo_vbox->pack_start( $typo_match_scroll,      0, 1, 0 );

    $vbox->pack_start( $exact_vbox,           0,  1, 0 );
    $vbox->pack_start( Gtk2::HSeparator->new, 10, 1, 10 );
    $vbox->pack_start( $punct_vbox,           0,  1, 0 );
    $vbox->pack_start( Gtk2::HSeparator->new, 10, 1, 10 );
    $vbox->pack_start( $typo_vbox,            0,  1, 0 );
    $vbox->pack_start( Gtk2::HSeparator->new, 10, 1, 10 );
    $vbox->pack_start( $not_matched_vbox,     0,  1, 0 );
    $vbox->pack_start( $accept_remap_label,   10, 1, 10 );

    $dlg->show_all;

    my $response = $dlg->run();

    $dlg->destroy();

    my %results = (
        response            => $response,
        punct_match_enabled => $punct_match_checkbutton->get_active,

        #typo_match_enabled => $typo_match_checkbutton->get_active,
        exclusions => $self->get_exclusions,
    );

    return wantarray ? %results : \%results;

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

    # make the columns for the tree and renderers to match up the
    # columns to the model data.
    my $column = Gtk2::TreeViewColumn->new();

    $column->set_title("Label");
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

    foreach my $match (@typo_matches) {
        my $iter = $typo_model->append(undef);

        # Lazy way of getting edit distance, ideally this wouldn't get
        # calculated in the middle of the gui.
        my $distance = distance( $match, $remap->{$match} );

        $typo_model->set(
            $iter,
            ORIGINAL_LABEL_COL, $match,
            REMAPPED_LABEL_COL, $remap->{$match},
            PERFORM_COL,        1,                 # checkbox enabled by default
            EDIT_DISTANCE_COL,  $distance,
        );
    }

    my $typo_tree = Gtk2::TreeView->new($typo_model);

    # make the columns for the tree and renderers to match up the
    # columns to the model data.
    my $original_column = Gtk2::TreeViewColumn->new();
    my $remapped_column = Gtk2::TreeViewColumn->new();
    my $distance_column = Gtk2::TreeViewColumn->new();
    my $checkbox_column = Gtk2::TreeViewColumn->new();

    $original_column->set_title("Original Label");
    $remapped_column->set_title("Remapped Label");

    my $tooltip         = Gtk2::Tooltips->new();
    my $distance_header = Gtk2::Label->new('Edit Distance');
    $distance_header->show();
    $distance_column->set_widget($distance_header);
    $tooltip->set_tip( $distance_header,
"Number of character changes to get from the original label to the remapped label"
    );

    $checkbox_column->set_title("Use?");

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

    # make the columns for the tree and renderers to match up the
    # columns to the model data.
    my $original_column = Gtk2::TreeViewColumn->new();
    my $remapped_column = Gtk2::TreeViewColumn->new();
    my $checkbox_column = Gtk2::TreeViewColumn->new();
    $original_column->set_title("Original Label");
    $remapped_column->set_title("Remapped Label");
    $checkbox_column->set_title("Use?");

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

