package Biodiverse::GUI::Exclusions;

use strict;
use warnings;
use 5.010;
use English qw /-no_match_vars/;
use Carp;

use Gtk2;

our $VERSION = '4.0';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::ParametersTable;

=head1
Implements the Run Exclusions dialog

=cut

##########################################################
# Globals
##########################################################

use constant DLG_NAME => 'dlgRunExclusions';

# Maps dialog widgets into fields in BaseData's exclusionHash
#  should really build widget_map from %BaseData::exclusionHash
my %g_widget_map = (
    LabelsMaxVar        => ['LABELS', 'maxVariety'   ],
    LabelsMinVar        => ['LABELS', 'minVariety'   ],
    LabelsMaxSamp       => ['LABELS', 'maxSamples'   ],
    LabelsMinSamp       => ['LABELS', 'minSamples'   ],
    LabelsMaxRedundancy => ['LABELS', 'maxRedundancy'],
    LabelsMinRedundancy => ['LABELS', 'minRedundancy'],
    LabelsMaxRange      => ['LABELS', 'max_range'    ],
    LabelsMinRange      => ['LABELS', 'min_range'    ],

    GroupsMaxVar        => ['GROUPS', 'maxVariety'   ],
    GroupsMinVar        => ['GROUPS', 'minVariety'   ],
    GroupsMaxSamp       => ['GROUPS', 'maxSamples'   ],
    GroupsMinSamp       => ['GROUPS', 'minSamples'   ],
    GroupsMaxRedundancy => ['GROUPS', 'maxRedundancy'],
    GroupsMinRedundancy => ['GROUPS', 'minRedundancy'],
);

sub show_dialog {
    my $exclusions_hash = shift;

    my $gui = Biodiverse::GUI::GUIManager->instance;
    my $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file($gui->get_gtk_ui_file('dlgRunExclusions.ui'));
    my $dlg = $dlgxml->get_object(DLG_NAME);

    # Put it on top of main window
    $dlg->set_transient_for($gui->get_object('wndMain'));

    # Init the widgets
    foreach my $name (keys %g_widget_map) {
        my $checkbox = $dlgxml->get_object('chk' . $name);
        my $spinbutton = $dlgxml->get_object('spin' . $name);

        # Load initial value
        my $fields = $g_widget_map{$name};
        my $value = $exclusions_hash->{$fields->[0]}{$fields->[1]};

        if (defined $value) {
            $checkbox->set_active(1);
            $spinbutton->set_value($value);
        }
        else {
            $spinbutton->set_sensitive(0);
        }

        # Set up the toggle checkbox signals
        $checkbox->signal_connect(toggled => \&on_toggled, $spinbutton);
    }

    #  and the text matching
    my $label_filter_checkbox = $dlgxml->get_object('chk_enable_label_exclusion_regex');
    my @label_filter_widget_names = qw /
        Entry_label_exclusion_regex
        chk_label_exclusion_regex
        Entry_label_exclusion_regex_modifiers
    /;

    foreach my $widget_name (@label_filter_widget_names) {
        my $widget = $dlgxml->get_object($widget_name);

        $widget->set_sensitive(0);

        my $callback = sub {
            my ($checkbox, $option_widget) = @_;
            $option_widget->set_sensitive( $checkbox->get_active );
        };

        $label_filter_checkbox->signal_connect(toggled => $callback, $widget);
    }

    #  and the file list
    my $file_list_checkbox = $dlgxml->get_object('chk_label_exclude_use_file');
    my @file_list_filter_widget_names = qw /
        chk_label_exclusion_label_file
        filechooserbutton_exclusions
    /;

    foreach my $widget_name (@file_list_filter_widget_names ) {
        my $widget = $dlgxml->get_object($widget_name);

        $widget->set_sensitive(0);
        if ($widget_name =~ /chooser/) {  #  kludge
            use Cwd;
            $widget->set_current_folder_uri(getcwd());
        }

        my $callback = sub {
            my ($checkbox, $option_widget) = @_;
            $option_widget->set_sensitive( $checkbox->get_active );
        };

        $file_list_checkbox->signal_connect(toggled => $callback, $widget);
    }

    #  and the groups def query
    my $specs = { name => 'Definition_query', type => 'spatial_conditions', default => '' };
    bless $specs, 'Biodiverse::Metadata::Parameter';
    my $parameters_table = Biodiverse::GUI::ParametersTable->new;
    my ($defq_widget, $defq_extractor) = $parameters_table->generate_widget ($specs);
    my $groups_vbox = $dlgxml->get_object('vbox_group_exclusions_defq');
    $groups_vbox->pack_start ($defq_widget, 0, 0, 0);

    # Show the dialog
    my $response = $dlg->run();
    my $ret = 0;

    if ($response ne 'ok') {
        $dlg->destroy;
        return $ret;
    }

    $ret = 1;

    # Set fields
    foreach my $name (keys %g_widget_map) {
        my $checkbox   = $dlgxml->get_object('chk' . $name);
        my $spinbutton = $dlgxml->get_object('spin' . $name);

        my $fields = $g_widget_map{$name};
        if ($checkbox->get_active()) {
            my $value = $spinbutton->get_value();
            #  round any decimals to six places to avoid floating point issues.
            #  could cause trouble later on, but the GUI only allows two decimals now anyway...
            $value = sprintf ("%.6f", $value) if $value =~ /\./;
            $exclusions_hash->{$fields->[0]}{$fields->[1]} = $value;
        }
        else {
            delete $exclusions_hash->{$fields->[0]}{$fields->[1]};
        }
    }

    my $regex_widget = $dlgxml->get_object('Entry_label_exclusion_regex');
    my $regex        = $regex_widget->get_text;
    if ($label_filter_checkbox->get_active && length $regex) {

        my $regex_negate_widget = $dlgxml->get_object('chk_label_exclusion_regex');
        my $regex_negate        = $regex_negate_widget->get_active;

        my $regex_modifiers_widget = $dlgxml->get_object('Entry_label_exclusion_regex_modifiers');
        my $regex_modifiers        = $regex_modifiers_widget->get_text;

        $exclusions_hash->{LABELS}{regex}{regex}  = $regex;
        $exclusions_hash->{LABELS}{regex}{negate} = $regex_negate;
    }

    if ($file_list_checkbox->get_active) {
        my $negate_widget = $dlgxml->get_object('chk_label_exclusion_label_file');
        my $negate        = $negate_widget->get_active;
        my $file_widget   = $dlgxml->get_object('filechooserbutton_exclusions');
        my $filename      = $file_widget->get_filename;

        #  This has the side-effect of prompting the user for a filename if one was not specified.
        my %options = eval {
            Biodiverse::GUI::BasedataImport::get_remap_info (
                gui      => $gui,
                filename => $filename,
                column_overrides => ['Input_element'],
            );
        };
        if (my $e = $EVAL_ERROR) {
            $dlg->destroy();
            croak $e;
        }

        ##  now do something with them...
        if ($options{file}) {
            my $check_list = Biodiverse::ElementProperties->new;
            $check_list->import_data (%options);

            $exclusions_hash->{LABELS}{element_check_list}{list}   = $check_list;
            $exclusions_hash->{LABELS}{element_check_list}{negate} = $negate;
        }
    }

    my $defq = $defq_extractor->();
    if (defined $defq) {
        $exclusions_hash->{GROUPS}{definition_query} = $defq;
    }

    my $delete_empty_groups = $dlgxml->get_object('chk_excl_delete_empty_groups')->get_active;
    my $delete_empty_labels = $dlgxml->get_object('chk_excl_delete_empty_labels')->get_active;
    $exclusions_hash->{delete_empty_groups} = $delete_empty_groups || 0;
    $exclusions_hash->{delete_empty_labels} = $delete_empty_labels || 0;



    $dlg->destroy();
    return $ret;
}


sub on_toggled {
    my ($checkbox, $spinbutton) = @_;
    $spinbutton->set_sensitive( $checkbox->get_active );
}


1;
