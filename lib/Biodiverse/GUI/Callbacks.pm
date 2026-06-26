package Biodiverse::GUI::Callbacks;

use strict;
use warnings;

use English ( -no_match_vars );
use Ref::Util qw /is_arrayref/;

use Browser::Start qw( open_url );    #  needed for the about dialogue

our $VERSION = '5.99_001';

use constant FALSE => 0;
use constant TRUE  => 1;

use Gtk3;
#use Data::Dumper;
require Biodiverse::GUI::GUIManager;
require Biodiverse::GUI::Help;

#require Biodiverse::GUI::ParamEditor;
require Biodiverse::GUI::Tabs::Spatial;
require Biodiverse::GUI::Tabs::Clustering;
require Biodiverse::GUI::Tabs::Labels;
require Biodiverse::GUI::Tabs::Randomise;
require Biodiverse::GUI::Tabs::RegionGrower;
require Biodiverse::GUI::Tabs::SpatialMatrix;

##########################################################
# Quitting
##########################################################
sub on_wnd_main_delete_event {
    if ( Biodiverse::GUI::GUIManager->instance->close_project() ) {
        Gtk3->main_quit();
        return FALSE;
    }
    else {
        # Don't quit!
        return TRUE;
    }
}

sub on_quit_activate {
    on_wnd_main_delete_event();

    return;
}

##########################################################
# Factory method to generate the callbacks
# Adapted from Statistics::Descriptive _make_accessors method
##########################################################
sub _make_callbacks {
    my ( $pkg, %args ) = @_;

    no strict 'refs';
    while ( my ( $callback, $call_args ) = each %args ) {
        my $method = $call_args;
        my $meth_args = {};
        if (is_arrayref $method) {
            $method = $call_args->[0];
            $meth_args = $call_args->[1] || {};
        }

        *{ $pkg . "::" . $callback } = do {
            sub {
                eval {
                    my $gui = Biodiverse::GUI::GUIManager->instance;
                    $gui->$method(%$meth_args);
                };
                if ($EVAL_ERROR) {
                    report_error($EVAL_ERROR);
                }
            };
        };
    }

    return;
}

##########################################################
# Help
##########################################################

my %help_funcs = (
    on_help_viewer_activate                        => 'help_show_link_to_web_help',
    on_menu_list_calculations_and_indices_activate => 'help_show_calculations_and_indices',
    on_menu_quick_start_guide_activate             => 'help_show_quick_start_guide',
    on_menu_list_spatial_conditions_activate       => 'help_show_spatial_conditions',
    on_menu_release_notes_activate                 => 'help_show_release_notes',
    on_menu_help_citation_activate                 => 'help_show_citation',
    on_menu_check_for_updates                      => 'help_show_check_for_updates',
    on_menu_mailing_list_activate                  => 'help_show_mailing_list',
    on_menu_blog_activate                          => 'help_show_blog',
);

__PACKAGE__->_make_callbacks(%help_funcs);

sub on_about_activate {
    my $dlg = Gtk3::AboutDialog->new();
    my $gui = Biodiverse::GUI::GUIManager->instance;

    my $url = 'http://www.purl.org/biodiverse';

    $dlg->set(
        authors => [
            'Shawn Laffan',
            'Eugene Lubarsky',
            'Dan Rosauer',
            'Michael Zhou',
            'Anthony Knittel',
            'Luke Fitzpatrick',
        ],
        comments     => 'A tool for the spatial analysis of diversity.',
        name         => 'Biodiverse',
        program_name => 'Biodiverse',
        version      => $gui->get_version(),
        license      => $Biodiverse::Config::license,
        website      => $url,

        #locale  => $locale_text,
    );

    #  Need to override the default URL handler, on Windows at least
    $dlg->signal_connect(
        'activate-link' => sub {
            if ( $OSNAME eq 'MSWin32' ) {
                system( 'start', $url );
            }
            else {
                my $check_open = open_url ($url);
            }
            return 1;
        }
    );

#  Locale stuff should go into its own section - need to add a button
#use POSIX qw(locale_h);
#my $locale_text = "\n\n(Current perl numeric locale is: " . setlocale(LC_ALL) . ")\n";
#$dlg->add_button ('locale' => -20);  #  this goes on the end, not what we want

    $dlg->signal_connect( response => sub { $_[0]->destroy; 1 } );

    $dlg->run();
}

##########################################################
# Opening/Saving files
##########################################################

my %open_funcs = (
    on_open_activate    => 'do_open',
    on_new_activate     => 'do_new',
    on_save_activate    => 'do_save',
    on_save_as_activate => 'do_save_as',
);

__PACKAGE__->_make_callbacks(%open_funcs);

#
##########################################################
# Basedata, Matrices, Phylogenies
##########################################################

#  these methods need to be standardised so they can be autogenerated
#  using loops, thus shortening the code
my %data_funcs = (
    on_basedata_import      => 'do_import',
    on_matrix_import        => 'do_add_matrix',
    on_phylogeny_import     => 'do_add_phylogeny',
    on_basedata_delete      => 'do_delete_basedata',
    on_basedata_rename      => 'do_rename_basedata',
    on_matrix_rename        => 'do_rename_matrix',
    on_phylogeny_rename     => 'do_rename_phylogeny',
    on_phylogeny_auto_remap => 'do_auto_remap_phylogeny',
    on_do_remap             => 'do_remap',
    on_basedata_auto_remap  => 'do_auto_remap_basedata',
    on_matrix_auto_remap    => 'do_auto_remap_matrix',
    on_matrix_delete        => 'do_delete_matrix',
    on_phylogeny_delete     => 'do_delete_phylogeny',
    on_basedata_save        => 'do_save_basedata',
    on_basedata_describe    => 'do_describe_basedata',
    on_matrix_describe      => 'do_describe_matrix',
    on_phylogeny_describe   => 'do_describe_phylogeny',
    on_basedata_duplicate   => 'do_duplicate_basedata',
    on_basedata_duplicate_no_outputs      => ['do_duplicate_basedata', { no_outputs => 1 }],
    on_basedata_reduce_axis_resolutions   => 'do_basedata_reduce_axis_resolutions',
    on_basedata_export_groups             => 'do_export_groups',
    on_rename_basedata_labels             => 'do_rename_basedata_labels',
    on_rename_basedata_groups             => 'do_rename_basedata_groups',
    on_binarise_basedata_elements         => 'do_binarise_basedata_elements',
    on_basedata_export_labels             => 'do_export_labels',
    on_basedata_extract_embedded_trees    => 'do_basedata_extract_embedded_trees',
    on_basedata_extract_embedded_matrices => 'do_basedata_extract_embedded_matrices',
    on_basedata_trim_using_object         => ['do_basedata_trim_using_object', { option => 'keep' }],
    on_basedata_trim_to_match_tree        => ['do_basedata_trim_to_tree', { option => 'keep' }],
    on_basedata_attach_properties         => 'do_basedata_attach_properties',
    on_basedata_attach_group_properties_from_rasters  => 'do_basedata_attach_group_properties_from_rasters',
    on_basedata_attach_label_abundances_as_properties => 'do_basedata_attach_label_abundances_as_properties',
    on_basedata_attach_ranges_as_properties           => 'do_basedata_attach_label_ranges_as_properties',
    on_delete_element_properties          => 'do_delete_element_properties',
    on_merge_basedatas                    => 'do_merge_basedatas',
    on_matrix_save                        => 'do_save_matrix',
    on_phylogeny_save                     => 'do_save_phylogeny',
    on_basedata_open                      => 'do_open_basedata',
    on_matrix_open                        => 'do_open_matrix',
    on_phylogeny_open                     => 'do_open_phylogeny',
    on_combo_basedata_changed             => 'do_basedata_changed',
    on_combo_matrices_changed             => 'do_matrix_changed',
    on_combo_phylogenies_changed          => 'do_phylogeny_changed',
    on_convert_labels_to_phylogeny        => 'do_convert_labels_to_phylogeny',
    on_convert_matrix_to_phylogeny        => 'do_convert_matrix_to_phylogeny',
    on_convert_phylogeny_to_matrix        => 'do_convert_phylogeny_to_matrix',
    on_transpose_basedata                 => 'do_transpose_basedata',
    on_basedata_reorder_axes              => 'do_basedata_reorder_axes',
    on_basedata_drop_axes                 => 'do_basedata_drop_axes',
    on_trim_tree_to_basedata              => 'do_trim_tree_to_basedata',
    on_trim_tree_to_lca                   => 'do_trim_tree_to_lca',
    on_tree_merge_knuckle_nodes           => 'do_tree_merge_knuckle_nodes',
    on_trim_matrix_to_basedata            => 'do_trim_matrix_to_basedata',
    on_range_weight_tree                  => 'do_range_weight_tree',
    on_tree_equalise_branch_lengths       => 'do_tree_equalise_branch_lengths',
    on_tree_rescale_branch_lengths        => 'do_tree_rescale_branch_lengths',
    on_tree_ladderise                     => 'do_tree_ladderise',
    on_matrix_export                      => 'do_export_matrix',
    on_phylogeny_export                   => 'do_export_phylogeny',
    on_phylogeny_delete_cached_values     => 'do_phylogeny_delete_cached_values',
);

__PACKAGE__->_make_callbacks(%data_funcs);

##########################################################
# Tabs
##########################################################

sub _make_tab_callbacks {
    my ( $pkg, %args ) = @_;

    no strict 'refs';
    while ( my ( $callback, $class ) = each %args ) {

        *{ $pkg . '::' . $callback } = do {
            sub {
                eval { $class->new(); };
                if ($EVAL_ERROR) {
                    Biodiverse::GUI::GUIManager->instance->report_error(
                        $EVAL_ERROR);
                }
            };
        };
    }

    return;
}

my %tabs = (
    on_spatial_activate       => 'Biodiverse::GUI::Tabs::Spatial',
    on_cluster_activate       => 'Biodiverse::GUI::Tabs::Clustering',
    on_region_grower_activate => 'Biodiverse::GUI::Tabs::RegionGrower',
    on_randomise_activate     => 'Biodiverse::GUI::Tabs::Randomise',
    on_view_labels_activate   => 'Biodiverse::GUI::Tabs::Labels',
);

__PACKAGE__->_make_tab_callbacks(%tabs);

##########################################################
# Misc dialogs
##########################################################

my %misc_dialogs = (
    on_run_exclusions_activate        => 'do_run_exclusions',
    on_set_working_directory_activate => 'do_set_working_directory',
    on_index_activate                 => 'show_index_dialog',
    on_index_delete                   => 'delete_index',
);

__PACKAGE__->_make_callbacks(%misc_dialogs);

#  error reporting shouldn't be autogenerated as it isn't a callback

sub report_error {
    my $error = shift;
    my $gui   = Biodiverse::GUI::GUIManager->instance();
    $gui->report_error($error);
}

1;

