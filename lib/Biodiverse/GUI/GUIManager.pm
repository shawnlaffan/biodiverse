package Biodiverse::GUI::GUIManager;

use strict;
use warnings;
use 5.010;

#use Data::Structure::Util qw /has_circular_ref get_refs/; #  hunting for circular refs

our $VERSION = '5.0';

#use Data::Dumper;
use Carp;
use Scalar::Util qw /blessed/;

use English ( -no_match_vars );

use FindBin qw ( $Bin );
use Path::Tiny qw /path/;
use Text::Wrapper;
use List::MoreUtils qw /first_index/;
use POSIX qw/fmod/;

require Biodiverse::Config;

require Biodiverse::GUI::Project;
require Biodiverse::GUI::BasedataImport;
require Biodiverse::GUI::MatrixImport;
require Biodiverse::GUI::PhylogenyImport;
require Biodiverse::GUI::OpenDialog;
require Biodiverse::GUI::Popup;
require Biodiverse::GUI::Exclusions;
require Biodiverse::GUI::Export;
require Biodiverse::GUI::Tabs::Outputs;
require Biodiverse::GUI::YesNoCancel;
use Biodiverse::GUI::ProgressDialog;
use Biodiverse::GUI::DeleteElementProperties;


require Biodiverse::BaseData;
require Biodiverse::Matrix;
require Biodiverse::GUI::RemapGUI;
require Biodiverse::Remap;


use Ref::Util qw { :all };

use parent qw /
    Biodiverse::Common
    Biodiverse::GUI::Manager::BaseDatas
    Biodiverse::GUI::Help
/;

##########################################################
# Construction
##########################################################
my $singleton;

BEGIN {
    $singleton = {
        project  => undef,    # Our subclass that inherits from the main Biodiverse object
        gladexml => undef,    # Main window widgets
        tabs => [],    # Stores refs to Tabs objects. In order of page index.
        progress_bars => undef,
        overlay_components => undef,
        test_val      => ''
    };
    bless $singleton, 'Biodiverse::GUI::GUIManager';
    $Biodiverse::Config::running_under_gui = 1;
}

sub instance {
    my $class = shift;
    return $singleton;
}

##########################################################
# Getters / Setters
##########################################################
sub get_version {
    return $VERSION;
}

sub set_glade_xml {
    my $self     = shift;
    my $gladexml = shift;
    $self->{gladexml} = $gladexml;

    return;
}

sub set_glade_file {
    my $self      = shift;
    my $gladefile = shift;
    $self->{gladefile} = $gladefile;

    return;
}

sub get_glade_file {
    my $self = shift;
    return $self->{gladefile};
}

sub set_gtk_ui_path {
    my $self        = shift;
    my $gtk_ui_path = shift;
    $self->{gtk_ui_path} = $gtk_ui_path;
    return;
}

sub get_gtk_ui_path {
    my $self = shift;
    return $self->{gtk_ui_path};
}

sub get_gtk_ui_file {
    my ( $self, $file ) = @_;
    return path( $self->get_gtk_ui_path, $file )->stringify();
}

# TODO: Temporary for conversion
sub get_object {
    my ( $self, $id ) = @_;
    return $self->{gladexml}->get_object($id);
}

sub get_status_bar {
    my $self = shift;
    return $self->get_object('statusbar');
}

sub get_notebook {
    my $self = shift;
    return $self->{notebook};
}

sub get_project {
    my $self = shift;
    return $self->{project};
}

sub get_base_data_output_model {
    my $self = shift;
    return $self->{basedata_output_model};
}

sub set_dirty {
    my $self = shift;
    $self->{project}->set_dirty;
    return;
}

#  A kludge to stop keyboard events triggering during exports
#  when a display tab is open.
#  Should look into trapping button-press-events
my $activate_keyboard_snooper = 1;

sub activate_keyboard_snooper {
    my $class = shift;
    my $val =
      scalar @_
      ? ( shift @_ )
      : 1;    #  true if no args passed, else take first value
    $activate_keyboard_snooper = !!$val;    #  binarise
}

sub keyboard_snooper_active {
    return $activate_keyboard_snooper;
}

# Progress bar handling.
# Lifecycle: nothing created on startup.  Subroutines will call add_progress_entry to
# add entries for tracking progress, as many may be active at any time.  When the first progress entry is added,
# the progress dialog will be created and shown.  When all progress entries are finished, the progress dialog
# is hidden (is it worth keeping open briefly or until closed?).
sub init_progress_window {
    my $self = shift;

    #say 'init_progress_window';

    if ( $self->{progress_bars} ) {
        say 'prog bars defined';
        croak 'call to init_progress_window when defined';
    }

    $self->{progress_bars} = {
        window         => undef,
        entry_box      => undef,
        dialog_objects => {},
        dialog_entries => {}
    };

    # create window
    my $window = Gtk3::Window->new;
    $window->set_transient_for( $self->get_object('wndMain') );
    $window->set_title('Progress');
    $window->set_default_size( 300, -1 );

    # do we need to track delete signals?
    $window->signal_connect(
        'delete-event' => \&progress_destroy_callback,
        $self
    );

    my $entry_box = Gtk3::VBox->new( 0, 5 );    # homogeneous, spacing
    $window->add($entry_box);

    $self->{progress_bars}->{window}    = $window;
    $self->{progress_bars}->{entry_box} = $entry_box;

    $window->show_all;
}

# called to add record to progress bar display
sub add_progress_entry {
    my ( $self, $dialog_obj, $title, $text, $progress ) = @_;

    # call init if not defined yet
    $self->init_progress_window if !$self->{progress_bars};

    # create new entry frame and widgets
    my $frame = Gtk3::Frame->new($title);
    $self->{progress_bars}->{entry_box}->pack_start( $frame, 0, 1, 0 );

    my $id = $dialog_obj->get_id;    # unique number for each, allows hashing
    $self->{progress_bars}->{dialog_objects}{$id} = $dialog_obj;
    $self->{progress_bars}->{dialog_entries}{$id} = $frame;

    #say "values " . Dumper($self->{progress_bars});

    my $frame_vbox = Gtk3::VBox->new;
    $frame->add($frame_vbox);
    $frame_vbox->set_border_width(3);

    my $label_widget = Gtk3::Label->new;
    $label_widget->set_line_wrap(1);
    $label_widget->set_markup($text);
    $frame_vbox->pack_start( $label_widget, 0, 0, 0 );

    my $progress_widget = Gtk3::ProgressBar->new;
    $frame_vbox->pack_start( $progress_widget, 0, 0, 0 );

# show the progress window
#  don't use present - it grabs the system focus and makes work in other windows impossible
#$self->{progress_bars}->{window}->present;
    $self->{progress_bars}->{window}->show_all;

    #say "Current progress bars: " . Dumper($self->{progress_bars});

    #$self->{progress_bars}->{id_to_entryframe}{$new_id}
    # return references to the id number, and label and progress widgets
    #return ($new_id, $label_widget, $progress_widget);
    return ( $label_widget, $progress_widget );
}

# called when a progress dialog finishes, to remove the entry from the display.  assume
# called from dialog
sub clear_progress_entry {
    my ( $self, $dialog_obj ) = @_;

    croak
'call to clear_progress_entry when not inited (possibly after window close)'
      if !$self->{progress_bars};

    croak 'invalid dialog obj given to clear_progress_entry'
      if !defined $dialog_obj;

    my $id = $dialog_obj->get_id;    # unique number for each, allows hashing

    #  sometimes the progress is not initialised, possibly due to threads?
    #  need a method for progress_bar attr
    return if !( defined $id && defined $dialog_obj->{progress_bar} );

    croak 'invalid dialog obj given to clear_progress_entry, can\'t read ID'
      if !defined $self->{progress_bars}->{dialog_objects}{$id};

    my $entry_frame = $self->{progress_bars}->{dialog_entries}{$id};

    # remove given entry.  assume valid widget provided, otherwise will fail
    $self->{progress_bars}->{entry_box}->remove($entry_frame);

    delete $self->{progress_bars}->{dialog_objects}{$id};
    delete $self->{progress_bars}->{dialog_entries}{$id};

    # if no active entries in progress dialog, hide it
    if ( !$self->{progress_bars}->{entry_box}->get_children
        || scalar $self->{progress_bars}->{entry_box}->get_children == 0 )
    {
        $self->{progress_bars}->{window}->hide;
    }

    #else {
    #  The resize below triggers Gtk critical warnings when minimised.
    #  We seem not to be able to detect when windows are minimised on Windows
    #  as state is always normal.
    #my $window = $self->{progress_bars}->{window};
    #$window = $self->get_object('wndMain');
    #my $state = $window->get_state;
    #warn "State is $state\n";
    #$self->{progress_bars}->{window}->resize(1,1);
    #}
}

# called when window closed, try to stop active process?
sub progress_destroy_callback {
    my ( $self_button, $event, $self_gui ) = @_;

    #say "callback values " . Dumper($self_gui->{progress_bars});

    say "progress_destroy_callback";

    # call destroy on each child object (?) (need to record each child obj)
    foreach
      my $dialog ( values %{ $self_gui->{progress_bars}->{dialog_objects} } )
    {
        $dialog->end_dialog();
    }

    # clear all progress bar info so re-creates window on next add
    $self_gui->{progress_bars} = undef;

    # send exception to stop operation in progress
    Biodiverse::GUI::ProgressDialog::Cancel->throw(
        message => "Progress bar closed, operation cancelled", );
}

sub show_progress {
    my $self = shift;

    if ( $self->{progress_bars} ) {
        $self->{progress_bars}->{window}->show_all;
    }
}

sub get_overlay_components {
    my ($self) = @_;
    return $self->{overlay_components} //= {};
}

sub set_overlay_components {
    my ($self, $components) = @_;
    $self->{overlay_components} = $components;
}

##########################################################
# Initialisation
##########################################################

my $dev_version_warning = <<"END_OF_DEV_WARNING"
This is a development version.

Features are subject to change and it is not guaranteed
to be backwards compatible with previous versions.

To turn off this warning set an environment
variable called BD_NO_GUI_DEV_WARN to a true value.
END_OF_DEV_WARNING
  ;

sub init {
    my $self = shift;

    my $window = $self->get_object('wndMain');
    $self->{main_window} = $window;

    # title
    $window->set_title( 'Biodiverse ' . $self->get_version );

    # Notebook...
    my $notebook = $self->{notebook} = Gtk3::Notebook->new;
    $notebook->set_scrollable(1);

    $notebook->signal_connect_swapped( 'switch-page', \&on_switch_tab, $self, );
    $self->get_object('vbox1')->pack_start( $notebook, 1, 1, 0, );

    #  these seem not to get through to the tabs otherwise
    state %pass_through = map {$_ => 1} (qw /Left Right Up Down/);

    #  Keyboard tab switching.  switch_tab method handles wrapping.
    $window->signal_connect (key_press_event => sub {
        my ($widget, $event) = @_;
        # say $event->keyval;
        # say $event->state;
        # say Gtk3::Gdk::keyval_name($event->keyval);

        my $key_name = Gtk3::Gdk::keyval_name($event->keyval);
        if ($event->state >= [ 'control-mask' ]) {
            if ($key_name eq 'Tab') {
                $self->switch_tab(undef, $notebook->get_current_page + 1); #  go right
            }
            elsif ($key_name eq 'ISO_Left_Tab' && $event->state >= [ 'shift-mask' ]) {
                $self->switch_tab(undef, $notebook->get_current_page - 1); #  go left
            }
        }
        elsif ($pass_through{$key_name}) {
            my $tab = $self->get_active_tab;
            if (defined $tab && $tab->can ('hotkey_handler')) {  #  paranoia
                $tab->hotkey_handler (undef, $event);
            }
        }

        return 0;
    });

    $self->{notebook}->show();

    # Hook up the models
    $self->init_combobox('comboBasedata');
    $self->init_combobox('comboMatrices');
    $self->init_combobox('comboPhylogenies');

    # Make the basedata-output model
    # (global - so that new projects use the same one.
    # The output tab then automatically updates
    # whenever projects are reloaded)
    # see Project.pm
    $self->{basedata_output_model} = Gtk3::TreeStore->new(
        'Glib::String', 'Glib::String',  'Glib::String', 'Glib::Scalar',
        'Glib::Scalar', 'Glib::Boolean', 'Glib::String',
    );

    $self->do_new;

    # Show outputs tab
    Biodiverse::GUI::Tabs::Outputs->new();

    #  check if we had any errors when loading extensions
    my @load_extension_errors = Biodiverse::Config::get_load_extension_errors();
    if (@load_extension_errors) {
        my $count = scalar @load_extension_errors -
          1;    #  last item is @INC, so not an extension
        my $text = "Failed to load $count extensions\n" . join "\n",
          @load_extension_errors;
        $self->report_error($text);
    }

    #  warn if we are a dev version
    if ( $VERSION =~ /_/ && !$ENV{BD_NO_GUI_DEV_WARN} && !$ENV{BDV_PP_BUILDING} ) {
        say $dev_version_warning;
        my $dlg = Gtk3::MessageDialog->new( undef, 'modal', 'error', 'ok',
            $dev_version_warning, );

        $dlg->run;
        $dlg->destroy;
    }

    return;
}

sub get_main_window {
    my ($self) = @_;
    $self->{main_window} || $self->get_object('wndMain');
}

#sub progress_test {
#    my $self = shift;
#
#    my $dlg = Biodiverse::GUI::ProgressDialog->new;
#
#    #$dlg->update("0.5", 0.5);
#    #sleep(1);
#    #$dlg->update("0.5", 0.6);
#    #sleep(1);
#    $dlg->pulsate("pulsing first time", 0.7);
#    sleep(1); while (Gtk3->events_pending) { Gtk3->main_iteration(); }
#    sleep(1); while (Gtk3->events_pending) { Gtk3->main_iteration(); }
#    sleep(1); while (Gtk3->events_pending) { Gtk3->main_iteration(); }
#
#    sleep(1); $dlg->update("1/3", 0.1);
#    sleep(1); $dlg->update("2/3", 0.4);
#    sleep(1); $dlg->update("3/3", 0.7);
#
#    $dlg->pulsate("pulsing second time", 0.7);
#    sleep(1); while (Gtk3->events_pending) { Gtk3->main_iteration(); }
#    sleep(1); while (Gtk3->events_pending) { Gtk3->main_iteration(); }
#    sleep(1); while (Gtk3->events_pending) { Gtk3->main_iteration(); }
#
#    sleep(1); $dlg->update("1/3", 0.1);
#    sleep(1); $dlg->update("2/3", 0.4);
#    sleep(1); $dlg->update("3/3", 0.7);
#
#    $dlg->destroy;
#
#    return;
#}

sub init_combobox {
    my ( $self, $id ) = @_;

    my $combo    = $self->get_object($id);
    my $renderer = Gtk3::CellRendererText->new();
    $combo->pack_start( $renderer, 1 );
    $combo->add_attribute( $renderer, text => 0 );

    return;
}

# Called when Project is to be deleted
sub close_project {
    my $self = shift;

    return 1 if !defined $self->{project};

    #if (defined $self->{project}) {

    if ( $self->{project}->is_dirty() ) {

        # Show "Save changes?" dialog
        my $dlgxml = Gtk3::Builder->new();
        $dlgxml->add_from_file( $self->get_gtk_ui_file('dlgClose.ui') );
        my $dlg = $dlgxml->get_object('dlgClose');
        $dlg->set_transient_for( $self->get_object('wndMain') );
        $dlg->set_modal(1);
        my $response = $dlg->run();
        $dlg->destroy();

        # Check response
        if ( $response eq 'yes' ) {

            # Save
            return 0 if not $self->do_save();
        }
        elsif ( $response eq 'cancel' or $response ne 'no' ) {

            # Stop closing
            return 0;
        }    # otherwise "no" - don't save - go on
    }

    # Close all analysis tabs (ie: except output tab)
    my @to_remove = @{ $self->{tabs} };
    shift @to_remove;
    foreach my $tab ( reverse @to_remove ) {
        next if ( blessed $tab) =~ /Outputs$/;
        $self->remove_tab($tab);
    }

    # Close all label popups
    Biodiverse::GUI::Popup::on_close_all();

    $self->{project} = undef;

    #}

    return 1;
}

##########################################################
# Opening / Creating / Saving
##########################################################
sub do_open {

    # Show the file selection dialogbox
    my $self = shift;
    my $dlg =
      Gtk3::FileChooserDialog->new( 'Open Project', undef, 'open', 'gtk-cancel',
        'cancel', 'gtk-ok', 'ok', );
    my $filter;

    #  Abortive attempt to load any file.
    #  Need to generalise project opens in a major way to get it to work
    #my @patterns = qw{*.bps *.bds *.bts *.bms *};
    my @patterns  = ('*.bps');
    my @text_vals = (
        'Biodiverse project files',

        #'Biodiverse BaseData files',
        #'Biodiverse tree files',
        #'Biodiverse matrix files',
        #'All files',
    );

    foreach my $i ( 0 .. $#patterns ) {
        my $pattern = $patterns[$i];
        my $text    = $text_vals[$i];

        $filter = Gtk3::FileFilter->new();
        $filter->set_name($text);
        $filter->add_pattern($pattern);
        $dlg->add_filter($filter);
    }

    $dlg->set_modal(1);

    my $filename;
    if ( $dlg->run() eq 'ok' ) {
        $filename = $dlg->get_filename();
    }
    $dlg->destroy();

    if ( defined $filename ) {
        my $project = $self->open($filename);

        #return if (blessed ($project) ne 'Biodiverse::GUI::Project');
    }

    return;
}

sub open {
    my $self     = shift;
    my $filename = shift;

    my $object;

    if ( $filename =~ /bps$/ && $self->close_project() ) {
        print "[GUI] Loading Biodiverse data from $filename...\n";

        #  using generalised load method
        $object = $self->{project} =
          eval { Biodiverse::GUI::Project->new( file => $filename ) };
        croak $EVAL_ERROR if $EVAL_ERROR;

        # Must do this separately from new_from_xml because it'll otherwise
        # call the GUIManager but the {project} key won't be set yet
        #$self->{project}->init_models();
        if ( blessed $object eq 'Biodiverse::GUI::Project' ) {
            $self->{filename} = $filename;

            $self->update_title_bar;
        }
    }
    elsif ( defined $filename && $self->file_exists_aa ($filename) ) {
        state %methods = (
            bds => {
                class => 'Biodiverse::BaseData',
                meth  => 'add_base_data',
            },
            bts => {
                class => 'Biodiverse::Tree',
                meth  => 'add_phylogeny',
            },
            bms => {
                class => 'Biodiverse::Matrix',
                meth  => 'add_matrix',
            }
        );
        if ($filename =~ /\.(.+$)/) {
            my $suffix = $1;
            my $m = $methods{$suffix};
            my ($class, $method) = @$m{qw/class meth/};
            say STDERR "loading data from $filename";
            $object = $class->new(file => $filename);
            $self->{project}->$method($object);
        }
        croak "Unable to load object from $filename"
            if !defined $object;
    }

    return $object;
}

sub update_title_bar {
    my $self = shift;

    my $name = $self->{filename} || q{};

    my $title = 'Biodiverse ' . $self->get_version . '          ' . $name;

    $self->get_object('wndMain')->set_title($title);

    return;
}

sub do_new {
    my $self = shift;
    if ( $self->close_project() ) {
        $self->{project} = Biodiverse::GUI::Project->new();
        print "[GUI] Created new Biodiverse project\n";
        delete $self->{filename};
    }

    $self->update_title_bar;

    return;
}

sub do_save_as {

    # Show the file selection dialogbox (if no existing filename)
    my ( $self, $filename ) = @_;

    my $format;
    my $method = 'save_to_sereal';

    if ( !defined $filename ) {
        my @formats = ( 'new file format', 'old file format' );
        if ( $self->get_last_file_serialisation_format eq 'storable' ) {
            @formats = reverse @formats;
        }
        ( $filename, $format ) = $self->show_save_dialog(
            'Save Project',
            [ 'bps', 'bps' ],
            \@formats,
        );
        if ( $format =~ /old/ ) {
            $method = 'save_to_storable';
        }
    }

    if ( defined $filename ) {

        my $file = $self->{project}->save(
            filename => $filename,
            method   => $method,
        );

        say "[GUI] Saved Biodiverse project to $file";
        $self->{filename} = $file;

        my $title = 'Biodiverse ' . $self->get_version . '          ' . $file;
        $self->get_object('wndMain')->set_title($title);

        $self->{project}->clear_dirty();    # Mark as having no changes

        return 1;
    }

    return 0;
}

sub do_save {
    my $self = shift;

    return $self->do_save_as( $self->{filename} )
      if exists $self->{filename};

    return $self->do_save_as();
}

##########################################################
# Adding/Removing Matrices and Basedata
##########################################################
sub do_import {
    my $self = shift;

    eval { Biodiverse::GUI::BasedataImport::run($self); };
    if ($EVAL_ERROR) {
        $self->report_error($EVAL_ERROR);
    }

    return;
}

sub do_add_matrix {
    my $self = shift;

    eval { Biodiverse::GUI::MatrixImport::run($self); };
    if ($EVAL_ERROR) {
        $self->report_error($EVAL_ERROR);
    }

    return;
}

sub do_add_phylogeny {
    my $self = shift;

    eval { Biodiverse::GUI::PhylogenyImport::run($self); };
    if ($EVAL_ERROR) {
        $self->report_error($EVAL_ERROR);
    }

    return;
}

sub do_open_matrix {
    my $self   = shift;
    my $object = shift;

    if ( !$object ) {
        my ( $name, $filename ) =
          Biodiverse::GUI::OpenDialog::Run( 'Open Object', 'bms' );

        if ( defined $filename && $self->file_exists_aa ($filename) ) {
            $object = Biodiverse::Matrix->new( file => $filename );
            #  override the name if the user says to
            $object->set_param( NAME => $name );
        }
    }

    return if !$object;

    $self->{project}->add_matrix($object);

    return;
}

sub do_open_phylogeny {
    my $self   = shift;
    my $object = shift;

    if ( !$object ) {
        my ( $name, $filename ) =
          Biodiverse::GUI::OpenDialog::Run( 'Open Object', 'bts' );

        if ( defined $filename && $self->file_exists_aa ($filename) ) {
            $object = Biodiverse::Tree->new( file => $filename );
            #  override the name if the user says to
            $object->set_param( NAME => $name );
        }
    }

    return if !$object;

    $self->{project}->add_phylogeny($object);

    return;
}

sub do_open_basedata {
    my $self = shift;

    my ( $name, $filename ) =
      Biodiverse::GUI::OpenDialog::Run( 'Open Object', 'bds' );

    if ( defined $filename && $self->file_exists_aa ($filename) ) {
        my $object = Biodiverse::BaseData->new( file => $filename );
        croak "Unable to load basedata object from $filename"
          if !defined $object;
        #  override the name if the user says to
        $object->set_param( NAME => $name );
        $self->{project}->add_base_data($object);
    }

    return;
}


sub get_dlg_duplicate {
    my $self   = shift;
    my $dlgxml = Gtk3::Builder->new();
    $dlgxml->add_from_file( $self->get_gtk_ui_file('dlgDuplicate.ui') );
    return ( $dlgxml, $dlgxml->get_object('dlgDuplicate') );
}


sub do_rename_output {
    my $self      = shift;
    my $selection = shift;    #  should really get from system

    my $object = $selection->{output_ref};

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_title('Rename output');
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $object->get_param('NAME');

    $txt_name->set_text($name);

    my $response = $dlg->run();

    my $chosen_name = $txt_name->get_text;

    if ( $response eq 'ok' and $chosen_name ne $name ) {

        #my $chosen_name = $txt_name->get_text;

        #  Go find it in any of the open tabs and update it
        #  The update triggers a rename in the output tab, so
        #  we only need this if one is open.
        #  This is messy - really the tab callback should be
        #  adjusted to require an enter key or similar
        my $tab_was_open;
        foreach my $tab ( @{ $self->{tabs} } ) {
            my $reg_ref = $tab->get_current_registration;

            if ( defined $reg_ref and $reg_ref eq $object ) {
                $tab->update_name($chosen_name);
                $tab_was_open = 1;
                last
                  ; #  comment this line if we ever allow multiple tabs of the same output
            }
        }

        if ( not $tab_was_open ) {
            my $bd = $object->get_param('BASEDATA_REF');
            eval {
                $bd->rename_output(
                    output   => $object,
                    new_name => $chosen_name,
                );
            };
            if ($EVAL_ERROR) {
                $self->report_error($EVAL_ERROR);
            }
            else {
                $self->{project}->update_output_name($object);
            }
        }
    }
    $dlg->destroy;

    return;
}

sub do_rename_matrix {
    my $self = shift;
    my $ref  = $self->{project}->get_selected_matrix();

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_title('Rename matrix object');
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $ref->get_param('NAME');

    $txt_name->set_text($name);

    my $response = $dlg->run();

    if ( $response eq 'ok' ) {
        my $chosen_name = $txt_name->get_text;
        $self->{project}->rename_matrix( $chosen_name, $ref );
    }

    $dlg->destroy;

    return;
}

sub do_rename_phylogeny {

    #return;  # TEMP
    my $self = shift;
    my $ref  = $self->{project}->get_selected_phylogeny();

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_title('Rename tree object');
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $ref->get_param('NAME');

    $txt_name->set_text($name);

    my $response = $dlg->run();

    if ( $response eq 'ok' ) {
        my $chosen_name = $txt_name->get_text;
        $self->{project}->rename_phylogeny( $chosen_name, $ref );
    }

    $dlg->destroy;

    return;
}

# Generalised remapping, pass in the default remapee
sub do_remap {
    my ($self, %args) = @_;

    if ($args{check_first}) {
        my $default_target = $args{default_remapee};
        my $type
           = $default_target->isa('Biodiverse::BaseData') ? 'label'
           : $default_target->isa('Biodiverse::Tree')     ? 'node'
           : 'element';
        my $message  = "Remap the $type names?";
        my $response =
            Biodiverse::GUI::YesNoCancel->run( {
                header      => $message,
                hide_cancel => 1,
            } );
        return if $response ne 'yes';
    }

    # ask what type of remap, what is getting remapped to what etc.
    my $remap_gui = Biodiverse::GUI::RemapGUI->new();
    my $pre_remap_dlg_results 
       = $remap_gui->pre_remap_dlg (
            gui => $self, 
            default_remapee => $args{default_remapee}, 
    );

    my $remap_type = $pre_remap_dlg_results->{remap_type};
    my $remapee    = $pre_remap_dlg_results->{remapee};

    # check if the remapee is a basedata with outputs
    my $type = (blessed $remapee) // '';

    croak "Cannot remap elements of a Basedata with outputs.\n"
          . "You can use the 'Duplicate without outputs' menu "
          . "option to create a new version.\n"
        if ($type eq 'Biodiverse::BaseData' && $remapee->get_output_ref_count);

    my $want_to_perform_remap = 0;
    my $generated_remap = Biodiverse::Remap->new;

    croak "Unknown option $remap_type\n"
      if not $remap_type =~ /^(?:auto|manual)_from_file|auto|none$/;;

    if ( $remap_type =~ /(manual|auto)_from_file/ ) {  # load a remap file
        my $type = $1;  #  manual or auto
        my $col_defs = $type eq 'manual'
            ? ['Input_element', 'Remapped_element']
            : ['Input_element'];

        my %remap_data = Biodiverse::GUI::BasedataImport::get_remap_info(
            gui => $self,
            column_overrides => $col_defs,
            required_cols    => $col_defs,
        );

        if ( defined $remap_data{file} ) {
            $generated_remap->import_from_file( %remap_data, );

            if ($type =~ /auto/) {
                $remap_type = 'auto';
                $pre_remap_dlg_results->{controller} = $generated_remap;
            }

            # TODO add in a 'review' dialog here
            $want_to_perform_remap = 1; 
        }
    }
    #  no elsif here - we can set $remap_type to auto in the previous step
    if ( $remap_type eq "auto" ) {  # guess an automatic remap
        say "Started an auto remap";
        my $controller = $pre_remap_dlg_results->{controller};
        
        $pre_remap_dlg_results->{ new_source } = $remapee;
        $pre_remap_dlg_results->{ old_source } = $controller;
        $generated_remap->populate_with_guessed_remap( $pre_remap_dlg_results );

        # show them the remap and do exclusions etc.
        $want_to_perform_remap 
            = $remap_gui->post_auto_remap_dlg(remap_object => $generated_remap);
    }
    
    return if !$want_to_perform_remap;

    # regardless of how we got the remap, apply it in the same way
    my $cloned_ref = $remapee->clone();

    $generated_remap->apply_to_data_source( data_source => $cloned_ref );

    # add new data object to project and rename. We need to figure
    # out the correct functions based on the type of the remapee.
    my %blessed_to_function_name = (
        "Biodiverse::Tree"     => "phylogeny",
        "Biodiverse::BaseData" => "basedata",
        "Biodiverse::Matrix"   => "matrix",
    );
    
    my $function_name = $blessed_to_function_name{blessed($cloned_ref)};
    my $add_to_project_function;

    # the function names are frustratingly add_base_data and
    # do_rename_basedata so we have to fix that here.
    if ($function_name eq 'basedata') {
        $add_to_project_function = "add_base_data";
    }
    else {
        $add_to_project_function = "add_" . $function_name;
    }
    my $rename_function         = "do_rename_". $function_name;

    $self->get_project->$add_to_project_function( $cloned_ref );
    $self->$rename_function();

    return;
}

sub do_auto_remap_phylogeny {
    my $self = shift;
    my $default_remapee = $self->get_project()->get_selected_phylogeny();
    $self->do_remap( default_remapee => $default_remapee );
}

sub do_auto_remap_basedata {
    my $self = shift;
    my $default_remapee = $self->get_project->get_selected_basedata();
    $self->do_remap( default_remapee => $default_remapee );
}

sub do_auto_remap_matrix {
    my $self = shift;
    my $default_remapee = $self->get_project->get_selected_matrix();
    $self->do_remap( default_remapee => $default_remapee );
}

sub do_phylogeny_delete_cached_values {
    my $self = shift;

    my $object = $self->{project}->get_selected_phylogeny || return;
    $object->delete_all_cached_values;

    $self->set_dirty;

    return;
}

sub do_describe_basedata {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data;
    
    return if !$bd;

    my $description = $bd->describe;

    say $description;
    $self->show_describe_dialog($description);

    return;
}

sub do_describe_matrix {
    my $self = shift;

    my $mx = $self->{project}->get_selected_matrix;

    die "No matrix selected\n" if !defined $mx;

    my $description = $mx->describe;

    say $description;
    $self->show_describe_dialog($description);

    return;
}

sub do_describe_phylogeny {
    my $self = shift;

    my $tree = $self->{project}->get_selected_phylogeny;

    die "No tree selected\n" if !defined $tree;

    my $description = $tree->describe;

    $self->show_describe_dialog($description);

    return;
}

sub print_describe {
    my $self   = shift;
    my $object = shift;

    say "DESCRIBE OBJECT\n";
    return scalar $object->describe;
}

sub show_describe_dialog {
    my $self        = shift;
    my $description = shift;

    #  passed a string so disassemble it into an array
    if (!is_ref($description)) {
        my @desc = split "\n", $description;
        $description = [];
        foreach my $line (@desc) {
            my @line = split /\b:\s+/, $line;
            push @$description, \@line;
        }
    }

    my $table_widget;
    if (is_ref($description)) {
        my $row_count = scalar @$description;
        my $table = Gtk3::Table->new( $row_count, 2, 0);

        my $i = 0;
        foreach my $row (@$description) {
            my $j = 0;
            foreach my $col (@$row) {
                my $label = Gtk3::Label->new;
                $label->set_text($col);
                $label->set_selectable(1);
                $label->set_padding( 10, 10 );
                $table->attach_defaults( $label, $j, $j + 1, $i, $i + 1 );
                $j++;
            }
            $i++;
        }
        $table_widget = $table;

        my $window = Gtk3::Window->new('toplevel');
        $window->set_title('Description');
        $window->add($table_widget);
        $window->show_all;
    }
    else {
        my $dlg = Gtk3::MessageDialog->new(
            $self->{gui},
            'destroy-with-parent',
            'info',    # message type
            'ok',      # which set of buttons?
            $description,
        );

        $dlg->set_title('Description');

        if ($table_widget) {
            $dlg->attach($table_widget);
        }

        my $response = $dlg->run;
        $dlg->destroy;
    }

    return;
}

sub do_delete_matrix {
    my $self = shift;

    my $mx = $self->{project}->get_selected_matrix;

    croak "no selected matrix\n" if !defined $mx;

    my $name = $mx->get_param('NAME');

    my $response = Biodiverse::GUI::YesNoCancel->run(
        {
            title => 'Confirmation dialogue',
            text  => "Delete matrix $name?",
        }
    );

    return if lc($response) ne 'yes';

    $self->{project}->delete_matrix();

    return;
}

sub do_delete_phylogeny {
    my $self = shift;

    my $tree = $self->{project}->get_selected_phylogeny;
    my $name = $tree->get_param('NAME');

    my $response = Biodiverse::GUI::YesNoCancel->run(
        {
            title => 'Confirmation dialogue',
            text  => "Delete tree $name?",
        }
    );

    return if lc($response) ne 'yes';

    $self->{project}->delete_phylogeny();

    return;
}

sub do_save_matrix {
    my $self   = shift;
    my $object = $self->{project}->get_selected_matrix();
    $self->save_object($object);

    return;
}

sub do_save_basedata {
    my $self   = shift;
    my $object = $self->{project}->get_selected_base_data();
    $self->save_object($object);

    return;
}

sub do_save_phylogeny {
    my $self   = shift;
    my $object = $self->{project}->get_selected_phylogeny();
    $self->save_object($object);

    return;
}

sub do_duplicate_basedata {
    my $self = shift;

    my $object = $self->{project}->get_selected_base_data();

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $object->get_param('NAME');

    # If ends with a number increment it
    if ( $name =~ /(.*)([0-9]+)$/ ) {
        $name = $1 . ( $2 + 1 );
    }
    else {
        $name .= '1';
    }
    $txt_name->set_text($name);

    my $response = $dlg->run();
    if ( $response eq 'ok' ) {
        my $chosen_name = $txt_name->get_text;

        # This uses the dclone method from Storable
        my $cloned = $object->clone(@_);    #  pass on the args
        $cloned->set_param( NAME => $chosen_name
              || $object->get_param('NAME') . "_CLONED" );
        $self->{project}->add_base_data($cloned);
    }

    $dlg->destroy();

    $self->set_dirty;
    return;
}


sub do_export_groups {
    my $self = shift;

    my $base_ref = $self->{project}->get_selected_base_data();
    Biodiverse::GUI::Export::Run( $base_ref->get_groups_ref );

    return;
}

sub do_export_labels {
    my $self = shift;

    my $base_ref = $self->{project}->get_selected_base_data();
    Biodiverse::GUI::Export::Run( $base_ref->get_labels_ref );

    return;
}

sub do_export_matrix {
    my $self = shift;

    my $object = $self->{project}->get_selected_matrix || return;
    Biodiverse::GUI::Export::Run($object);

    return;
}

sub do_export_phylogeny {
    my $self = shift;

    my $object = $self->{project}->get_selected_phylogeny || return;
    Biodiverse::GUI::Export::Run($object);

    return;
}

# Saves an object in native format
sub save_object {
    my $self   = shift;
    my $object = shift;

    my $suffix_str  = $object->get_param('OUTSUFFIX');
    my $suffix_yaml = $object->get_param('OUTSUFFIX_YAML');

    my $method = 'save_to_sereal';

    my @formats = ( 'new file format', 'old file format' );
    if ( $object->get_last_file_serialisation_format eq 'storable' ) {
        @formats = reverse @formats;
    }

    my ( $filename, $format ) = $self->show_save_dialog(
        'Save Object',
        [ $suffix_str, $suffix_str, $suffix_yaml ],
        [ @formats,    'yaml format' ],
    );

    if ( $format =~ /^old / ) {
        $method = 'save_to_storable';
    }
    elsif ( $format =~ /^yaml / ) {
        $method = 'save_to_yaml';
    }

    if ( defined $filename ) {

        my ( $prefix, $suffix ) = $filename =~ /(.*?)\.(.+?)$/;
        $prefix //= $filename;

        $object->set_param( 'OUTPFX', $prefix );

        $object->save( filename => $filename, method => $method );
    }

    return;
}

##########################################################
# Base sets / Matrices combos
##########################################################

#  sometime we need to force this - is this ever used now?
sub set_active_iter {
    my $self  = shift;
    my $combo = shift;

    #  drop out if it is set
    return if $combo->get_active >= 0;

    #  loop over the iters and choose the one called none
    my $i = 0;
    while (1) {
        $combo->set_active_iter($i);
        my $iter = $combo->get_active_iter();
        return if $iter->get_text eq '(none)';
    }

    return;
}

sub set_basedata_model {
    my $self  = shift;
    my $model = shift;

    $self->get_object('comboBasedata')->set_model($model);

    return;
}

sub set_matrix_model {
    my $self  = shift;
    my $model = shift;

    my $widget = $self->get_object('comboMatrices')->set_model($model);

    return;
}

sub set_phylogeny_model {
    my $self  = shift;
    my $model = shift;

    $self->get_object('comboPhylogenies')->set_model($model);

    return;
}

sub set_basedata_iter {
    my $self = shift;
    my $iter = shift;

    my $combo = $self->get_object('comboBasedata');
    $combo->set_active_iter($iter);
    $self->{active_basedata} = $combo->get_model()->get_string_from_iter($iter);

    return;
}

sub set_matrix_iter {
    my $self = shift;
    my $iter = shift;

    my $combo = $self->get_object('comboMatrices');
    $combo->set_active_iter($iter);
    $self->{active_matrix} = $combo->get_model()->get_string_from_iter($iter);

    return;
}

sub set_phylogeny_iter {
    my $self = shift;
    my $iter = shift;

    my $combo = $self->get_object('comboPhylogenies');
    return if not $iter;
    croak "pyhlogeny iter undef\n" if not defined $iter;
    $combo->set_active_iter($iter);
    $self->{active_phylogeny} =
      $combo->get_model()->get_string_from_iter($iter);

    return;
}

sub do_basedata_changed {
    my $self  = shift;
    my $combo = $self->get_object('comboBasedata');
    my $active = $combo->get_active;

    #  sometimes combo is not active
    return if $active < 0;

    my $iter = $combo->get_active_iter();

    #  sometimes $iter is not defined when this sub is called.
    return if !defined $iter;

    my $model = $combo->get_model;
    return if !$model;

    my $text = eval {$model->get( $iter, 0 )} // '(none)';

  # FIXME: not sure how $self->{project} can be undefined - but it appears to be
    if (    defined $self->{project}
        and defined $self->{active_basedata}
        and $combo->get_model->get_string_from_iter($iter) ne
        $self->{active_basedata} )
    {
        $self->{project}->select_base_data_iter($iter)
          if not( $text eq '(none)' );
    }

    return;
}

sub do_convert_labels_to_phylogeny {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data;

    return if !defined $bd;

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $bd->get_param('NAME');

    # If ends with _T followed by a number then increment it
    #if ($name =~ /(.*_AS_TREE)([0-9]+)$/) {
    #$name = $1 . ($2 + 1)
    #}
    #else {
    $name .= '_AS_TREE';

    #}
    $txt_name->set_text($name);

    my $response = $dlg->run();
    if ( $response eq 'ok' ) {
        my $chosen_name = $txt_name->get_text;
        my $phylogeny = $bd->to_tree( name => $chosen_name );

        #$phylogeny->set_param (NAME => $chosen_name);
        if ( defined $phylogeny ) {

            #  now we add it if it is not already in the list
            # otherwise we select it
            my $phylogenies = $self->{project}->get_phylogeny_list;
            my $in_list     = 0;
            foreach my $ph (@$phylogenies) {
                if ( $ph eq $phylogeny ) {
                    $in_list = 1;
                    last;
                }
            }
            if ($in_list) {
                $self->{project}->select_phylogeny($phylogeny);
            }
            else {
                $self->{project}->add_phylogeny( $phylogeny, 0 );
            }
        }
    }
    $dlg->destroy;

    return;
}


sub dlg_no_selected_object {
    my $self = shift;
    my $object_type = shift // 'tree';
    
    Biodiverse::GUI::YesNoCancel->run(
        {
            header      => "no $object_type selected",
            hide_yes    => 1,
            hide_no     => 1,
            hide_cancel => 1,
        }
    );

    return 0;
}


#  Should probably rename this sub as it is being used for more purposes,
#  some of which do not involve trimming.
sub do_trim_matrix_to_basedata {
    my $self = shift;
    my %args = @_;

    my $mx = $self->{project}->get_selected_matrix;
    my $bd = $self->{project}->get_selected_base_data || return 0;

    return $self->dlg_no_selected_object ('matrix')
      if !defined $mx;
      
    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $mx->get_param('NAME');

    my $suffix = $args{suffix} || 'TRIMMED';

    # If ends with _TRIMMED followed by a number then increment it
    if ( $name =~ /(.*_$suffix)([0-9]+)$/ ) {
        $name = $1 . ( $2 + 1 );
    }
    else {
        $name .= "_${suffix}1";
    }
    $txt_name->set_text($name);

    my $response    = $dlg->run();
    my $chosen_name = $txt_name->get_text;

    $dlg->destroy;

    return if $response ne 'ok';    #  they chickened out

    my $new_mx = $mx->clone;
    $new_mx->delete_cached_values;

    if ( !$args{no_trim} ) {
        $new_mx->trim( keep => $bd );
    }

    $new_mx->set_param( NAME => $chosen_name );

    #  now we add it if it is not already in the list
    #  otherwise we select it
    my $matrices = $self->{project}->get_matrix_list;

    my $in_list = grep { $_ eq $new_mx } @$matrices;

    if ($in_list) {
        $self->{project}->select_matrix($new_mx);
    }
    else {
        $self->{project}->add_matrix( $new_mx, 0 );
    }

    return;
}

sub do_convert_matrix_to_phylogeny {
    my $self = shift;

    my $matrix_ref = $self->{project}->get_selected_matrix;

    return $self->dlg_no_selected_object ('matrix')
      if !defined $matrix_ref;

    my $phylogeny = $matrix_ref->get_param('AS_TREE');

    my $response = 'no';
    if ( defined $phylogeny ) {
        my $mx_name = $matrix_ref->get_param('NAME');
        my $ph_name = $phylogeny->get_param('NAME');
        $response = Biodiverse::GUI::YesNoCancel->run(
            {
                header => "$mx_name has already been converted.",
                text   => "Use cached tree $ph_name?"
            }
        );
        return if $response eq 'cancel';
    }

    if ( $response eq 'no' ) {    #  get a new one

        # Show the Get Name dialog
        my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
        $dlg->set_transient_for( $self->get_object('wndMain') );

        my $txt_name = $dlgxml->get_object('txtName');
        my $name     = $matrix_ref->get_param('NAME');

        # If ends with _T followed by a number then increment it
        if ( $name =~ /(.*_AS_TREE)([0-9]+)$/ ) {
            $name = $1 . ( $2 + 1 );
        }
        else {
            $name .= '_AS_TREE1';
        }
        $txt_name->set_text($name);

        $response = $dlg->run();

        if ( $response eq 'ok' ) {
            my $chosen_name = $txt_name->get_text;
            $matrix_ref->set_param( AS_TREE => undef )
              ;    #  clear the previous version

            eval {
                $phylogeny =
                  $matrix_ref->to_tree( linkage_function => 'link_average', );
            };
            if ($EVAL_ERROR) {
                $self->report_error($EVAL_ERROR);
                $dlg->destroy;
                return;
            }

            $phylogeny->set_param( NAME => $chosen_name );
            if ( $self->get_param('CACHE_MATRIX_AS_TREE') ) {
                $matrix_ref->set_param( AS_TREE => $phylogeny );
            }
        }
        $dlg->destroy;
    }

    #  now we add it if it is not already in the list
    #  otherwise we select it
    my $phylogenies = $self->{project}->get_phylogeny_list;
    my $in_list     = 0;
    foreach my $mx (@$phylogenies) {
        if ( $mx eq $phylogeny ) {
            $in_list = 1;
            last;
        }
    }
    if ($in_list) {
        $self->{project}->select_phylogeny($phylogeny);
    }
    else {
        $self->{project}->add_phylogeny( $phylogeny, 0 );
    }

    return;
}

sub do_convert_phylogeny_to_matrix {
    my $self      = shift;
    my $phylogeny = $self->{project}->get_selected_phylogeny;

    return $self->dlg_no_selected_object ('tree')
      if !defined $phylogeny;

    my $matrix_ref = $phylogeny->get_param('AS_MX');
    my $response   = 'no';
    if ( defined $matrix_ref ) {
        my $mx_name = $matrix_ref->get_param('NAME');
        my $ph_name = $phylogeny->get_param('NAME');
        $response = Biodiverse::GUI::YesNoCancel->run(
            {
                header => "$ph_name has already been converted",
                text   => "use cached tree $mx_name?"
            }
        );
        return 0 if $response eq 'cancel';
    }

    if ( $response eq 'no' ) {    #  get a new one
                                  # Show the Get Name dialog
        my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
        $dlg->set_transient_for( $self->get_object('wndMain') );

        my $txt_name = $dlgxml->get_object('txtName');
        my $name     = $phylogeny->get_param('NAME');

        # If ends with _AS_MX followed by a number then increment it
        if ( $name =~ /(.*_AS_MX)([0-9]+)$/ ) {
            $name = $1 . ( $2 + 1 );
        }
        else {
            $name .= '_AS_MX1';
        }
        $txt_name->set_text($name);

        $response = $dlg->run();
        my $chosen_name = $txt_name->get_text;
        $dlg->destroy;

        return if $response ne 'ok';

        eval { $matrix_ref = $phylogeny->to_matrix( name => $chosen_name, ); };
        if ($EVAL_ERROR) {
            $self->report_error($EVAL_ERROR);
            return;
        }

        if ( $phylogeny->get_param('CACHE_TREE_AS_MATRIX') ) {
            $phylogeny->set_param( AS_MX => $matrix_ref );
        }

    }

    return if !$matrix_ref;

    #  now we add it if it is not already in the list
    #  otherwise we select it
    my $matrices = $self->{project}->get_matrix_list;
    my $in_list  = 0;
    foreach my $mx (@$matrices) {
        if ( $mx eq $matrix_ref ) {
            $in_list = 1;
            last;
        }
    }
    if ($in_list) {
        $self->{project}->select_matrix($matrix_ref);
    }
    else {
        $self->{project}->add_matrix( $matrix_ref, 0 );
    }

    return;
}

sub do_range_weight_tree {
    my $self = shift;

    return $self->do_trim_tree_to_basedata(
        do_range_weighting => 1,
        suffix             => 'RW',
    );
}


#  Should probably rename this sub as it is being used for more purposes,
#  some of which do not involve trimming.
sub do_trim_tree_to_basedata {
    my $self = shift;
    my %args = @_;

    my $phylogeny = $self->{project}->get_selected_phylogeny;
    my $bd = $self->{project}->get_selected_base_data || return 0;

    return $self->dlg_no_selected_object ('tree')
      if !defined $phylogeny;

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_transient_for( $self->get_object('wndMain') );
    
    my $vbox = $dlg->get_content_area;
    my $checkbox  = Gtk3::CheckButton->new;
    my $chk_label = Gtk3::Label->new ('Trim to last common ancestor');
    my $hbox = Gtk3::HBox->new;
    $hbox->pack_start ($chk_label, 1, 1, 0);
    $hbox->pack_start ($checkbox, 1, 1, 0);
    $vbox->pack_start ($hbox, 1, 1, 0);
    $hbox->show_all;
    
    my $knuckle_checkbox  = Gtk3::CheckButton->new;
    my $knuckle_label = Gtk3::Label->new ('Merge single child nodes');
    my $khbox = Gtk3::HBox->new;
    $khbox->pack_start ($knuckle_label, 1, 1, 0);
    $khbox->pack_start ($knuckle_checkbox, 1, 1, 0);
    $vbox->pack_start ($khbox, 1, 1, 0);
    $khbox->show_all;

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $phylogeny->get_param('NAME');

    my $suffix = $args{suffix} || 'TRIMMED';

    # If ends with _TRIMMED followed by a number then increment it
    if ( $name =~ /(.*_$suffix)([0-9]+)$/ ) {
        $name = $1 . ( $2 + 1 );
    }
    else {
        $name .= "_${suffix}1";
    }
    $txt_name->set_text($name);

    my $response    = $dlg->run();
    my $chosen_name = $txt_name->get_text;

    $dlg->destroy;

    return if $response ne 'ok';    #  they chickened out

    my $new_tree = $phylogeny->clone;
    #$new_tree->delete_cached_values;  #  we use the caches so clear up at the end
    $new_tree->reset_total_length;  #  also handles each node
    
    my $trim_to_lca = $checkbox->get_active;
    my $merge_knuckle_nodes = $knuckle_checkbox->get_active;

    if ( !$args{no_trim} ) {
        $new_tree->trim (
            keep => scalar $bd->get_labels,
            trim_to_lca => $trim_to_lca,
        );
    }

    if ( $args{do_range_weighting} ) {
        foreach my $node ( $new_tree->get_node_refs ) {
            my $range = $node->get_node_range( basedata_ref => $bd );
            $node->set_length( length => $node->get_length / $range );
        }
        if ($trim_to_lca) {
            $new_tree->trim_to_last_common_ancestor;
        }
    }

    if ($merge_knuckle_nodes) {
        say "Merging knuckle nodes";
        my $merge_count = $new_tree->merge_knuckle_nodes;
        if ($merge_count) {
            say "Merged $merge_count knuckle nodes";
        }
        else {
            say "No knuckles found";
        }
        
    }

    #  clear the caches --after-- all the above method calls
    #  that use them internally
    $new_tree->delete_all_cached_values;

    $new_tree->set_param( NAME => $chosen_name );

    #  now we add it if it is not already in the list
    #  otherwise we select it
    my $phylogenies = $self->{project}->get_phylogeny_list;

    my $in_list = grep { $_ eq $new_tree } @$phylogenies;

    if ($in_list) {
        $self->{project}->select_phylogeny($new_tree);
    }
    else {
        $self->{project}->add_phylogeny( $new_tree, 0 );
    }

    return;
}

#  trim to last common ancestor
sub do_trim_tree_to_lca {
    my $self = shift;
    my %args = @_;

    my $phylogeny = $self->{project}->get_selected_phylogeny;

    return $self->dlg_no_selected_object ('tree')
      if !defined $phylogeny;

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $phylogeny->get_param('NAME');

    my $suffix = $args{suffix} || '_lca';

    # If ends with _TRIMMED followed by a number then increment it
    if ( $name =~ /(.*_$suffix)([0-9]+)$/ ) {
        $name = $1 . ( $2 + 1 );
    }
    else {
        $name .= "_${suffix}1";
    }
    $txt_name->set_text($name);

    my $response    = $dlg->run();
    my $chosen_name = $txt_name->get_text;

    $dlg->destroy;

    return if $response ne 'ok';    #  they chickened out

    #  could be more efficient?
    my $new_tree = $phylogeny->clone;
    $new_tree->delete_cached_values;
    $new_tree->trim_to_last_common_ancestor;

    $new_tree->set_param( NAME => $chosen_name );

    #  now we add it if it is not already in the list
    #  otherwise we select it
    my $phylogenies = $self->{project}->get_phylogeny_list;

    my $in_list = grep { $_ eq $new_tree } @$phylogenies;

    if ($in_list) {
        $self->{project}->select_phylogeny($new_tree);
    }
    else {
        $self->{project}->add_phylogeny( $new_tree, 0 );
    }

    return;
}


#  too much duplicated code in here
sub do_tree_merge_knuckle_nodes {
    my $self = shift;
    my %args = @_;

    my $phylogeny = $self->{project}->get_selected_phylogeny;

    return $self->dlg_no_selected_object ('tree')
      if !defined $phylogeny;

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $phylogeny->get_param('NAME');

    my $suffix = $args{suffix} || '_noknuckles';

    # If ends with $suffix followed by a number then increment it
    if ( $name =~ /(.*_$suffix)([0-9]+)$/ ) {
        $name = $1 . ( $2 + 1 );
    }
    else {
        $name .= "_${suffix}1";
    }
    $txt_name->set_text($name);

    my $response    = $dlg->run();
    my $chosen_name = $txt_name->get_text;

    $dlg->destroy;

    return if $response ne 'ok';    #  they chickened out

    #  could be more efficient?
    my $new_tree = $phylogeny->clone;
    $new_tree->delete_cached_values;
    $new_tree->merge_knuckle_nodes;

    $new_tree->set_param( NAME => $chosen_name );

    #  now we add it if it is not already in the list
    #  otherwise we select it
    my $phylogenies = $self->{project}->get_phylogeny_list;

    my $in_list = grep { $_ eq $new_tree } @$phylogenies;

    if ($in_list) {
        $self->{project}->select_phylogeny($new_tree);
    }
    else {
        $self->{project}->add_phylogeny( $new_tree, 0 );
    }

    return;
}


sub do_tree_equalise_branch_lengths {
    my $self = shift;
    my %args = @_;

    my $phylogeny = $self->{project}->get_selected_phylogeny;

    return $self->dlg_no_selected_object ('tree')
      if !defined $phylogeny;

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $phylogeny->get_param('NAME');

    my $suffix = $args{suffix} || 'EQ';

    # If ends with _TRIMMED followed by a number then increment it
    if ( $name =~ /(.*_$suffix)([0-9]+)$/ ) {
        $name = $1 . ( $2 + 1 );
    }
    else {
        $name .= "_${suffix}1";
    }
    $txt_name->set_text($name);

    my $response    = $dlg->run();
    my $chosen_name = $txt_name->get_text;

    $dlg->destroy;

    return if $response ne 'ok';    #  they chickened out

    my $new_tree = $phylogeny->clone_tree_with_equalised_branch_lengths;

    $new_tree->set_param( NAME => $chosen_name );

    #  now we add it if it is not already in the list
    #  otherwise we select it
    my $phylogenies = $self->{project}->get_phylogeny_list;

    my $in_list = grep { $_ eq $new_tree } @$phylogenies;

    if ($in_list) {
        $self->{project}->select_phylogeny($new_tree);
    }
    else {
        $self->{project}->add_phylogeny( $new_tree, 0 );
    }

    return;
}

sub do_tree_rescale_branch_lengths {
    my $self = shift;
    my %args = @_;

    my $phylogeny = $self->{project}->get_selected_phylogeny;

    return $self->dlg_no_selected_object ('tree')
      if !defined $phylogeny;

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $phylogeny->get_param('NAME');

    my $suffix = $args{suffix} || 'RS';

    # If ends with $suffix followed by a number then increment it
    if ( $name =~ /(.*_$suffix)([0-9]+)$/ ) {
        $name = $1 . ( $2 + 1 );
    }
    else {
        $name .= "_${suffix}1";
    }
    $txt_name->set_text($name);

    my $response    = $dlg->run();
    my $chosen_name = $txt_name->get_text;

    $dlg->destroy;

    return if $response ne 'ok';    #  they chickened out

    #  now get the new length
    my $param = {
        name       => 'new_length',
        label_text => 'New length',
        tooltip    => 'New length of the longest path from root to tip.  '
          . 'All nodes are scaled linearly to this.  '
          . 'Increment is the current length, a value of 0 is converted to 1',
        type      => 'float',
        default   => 1,
        digits    => 10,
        increment => $phylogeny->get_longest_path_length_to_terminals,
    };
    bless $param, 'Biodiverse::Metadata::Parameter';

    $dlgxml = Gtk3::Builder->new();
    $dlgxml->add_from_file( $self->get_gtk_ui_file('dlgImportParameters.ui') );
    my $param_dlg = $dlgxml->get_object('dlgImportParameters');

    #$param_dlg->set_transient_for( $self->get_object('wndMain') );
    $param_dlg->set_title('Rescale options');

    # Build widgets for parameters
    my $param_table = $dlgxml->get_object('tableImportParameters');

# (passing $dlgxml because generateFile uses existing glade widget on the dialog)
    my $parameters_table = Biodiverse::GUI::ParametersTable->new;
    my $param_extractors =
      $parameters_table->fill( [$param], $param_table, $dlgxml, );

    # Show the dialog
    $param_dlg->show_all();

    $response = $param_dlg->run();

    if ( $response ne 'ok' ) {
        $param_dlg->destroy;
        return;
    }

    my $params = $parameters_table->extract($param_extractors);

    $param_dlg->destroy;

    my $new_length = $params->[-1];

    my $new_tree = $phylogeny->clone_tree_with_rescaled_branch_lengths(
        new_length => $new_length );

    $new_tree->set_param( NAME => $chosen_name );

    #  now we add it if it is not already in the list
    #  otherwise we select it
    my $phylogenies = $self->{project}->get_phylogeny_list;

    my $in_list = grep { $_ eq $new_tree } @$phylogenies;

    if ($in_list) {
        $self->{project}->select_phylogeny($new_tree);
    }
    else {
        $self->{project}->add_phylogeny( $new_tree, 0 );
    }

    return;
}

sub do_tree_ladderise {
    my $self = shift;
    my %args = @_;

    my $phylogeny = $self->{project}->get_selected_phylogeny;

    return $self->dlg_no_selected_object ('tree')
      if !defined $phylogeny;

    $phylogeny->ladderise;

    return;
}


sub do_matrix_changed {
    my $self  = shift;
    my $combo = $self->get_object('comboMatrices');

    return if $combo->get_active < 0;

    my $iter  = $combo->get_active_iter();

    #print "MATRIX CHANGE ITER IS $iter";
    #my ($text) = $combo->get_model->get($iter, 0);

    if (    defined $iter
        and defined $self->{project}
        and defined $self->{active_matrix}
        and $combo->get_model->get_string_from_iter($iter) ne
        $self->{active_matrix} )
    {
        #warn $text . "\n";
        $self->{project}->select_matrix_iter($iter);
    }

    return;
}

sub do_phylogeny_changed {
    my $self  = shift;
    my $combo = $self->get_object('comboPhylogenies');

    return if $combo->get_active < 0;

    my $iter  = $combo->get_active_iter();

    #my ($text) = $combo->get_model->get($iter, 0);

    if (    defined $iter
        and defined $self->{project}
        and defined $self->{active_phylogeny}
        and $combo->get_model->get_string_from_iter($iter) ne
        $self->{active_phylogeny} )
    {
        $self->{project}->select_phylogeny_iter($iter);
    }

    return;
}

##########################################################
# Tabs
##########################################################

sub add_tab {
    my $self = shift;
    my $tab  = shift;
    my $page = $tab->get_page_index;

    # Add tab to our array at the right position
    push @{ $self->{tabs} }, $tab;

    # Enable keyboard shortcuts (CTRL-G)
    $tab->set_keyboard_handler();

    # Switch to added tab
    $self->switch_tab($tab);

    return;
}

sub switch_tab {
    my $self = shift;
    my $tab  = shift;    # Expecting the tab object
    my $page = shift;

    if ($tab) {
        $self->get_notebook->set_current_page( $tab->get_page_index );
    }
    else {
        my $last_page      = $self->get_notebook->get_nth_page(-1);
        my $max_page_index = $self->get_notebook->page_num($last_page);
        if ( $page > $max_page_index ) {
            $page = 0;
        }
        elsif ( $page < 0 ) {
            $page = $max_page_index;
        }
        $self->get_notebook->set_current_page($page);
    }

    return;
}

sub remove_tab {
    my $self = shift;
    my $tab  = shift;

    #  don't close the outputs tab
    return if ( blessed $tab) =~ /Outputs$/;

    # Remove tab from our array
    #  do we really need to store the tabs?
    my @tabs = @{ $self->{tabs} };
    my $i    = $#tabs;
    foreach my $check ( reverse @tabs ) {
        if ( $tab eq $check ) {
            splice( @{ $self->{tabs} }, $i, 1 );
        }
        $i--;
    }
    undef @tabs;

    $tab->remove_keyboard_handler();
    $tab->remove();

    return;
}

sub get_active_tab {
    my $self       = shift;

    my $page = $self->get_notebook->get_current_page;

    return if $page < 0;

    return $self->{tabs}[$page];
}

sub on_switch_tab {
    my $self       = shift;
    my $page       = shift;    #  passed by Gtk, not needed here
    my $page_index = shift;    #  passed by gtk

    foreach my $tab ( @{ $self->{tabs} } ) {
        next if $page_index != $tab->get_page_index;
        $tab->set_keyboard_handler();
        last;
    }

    return;
}

##########################################################
# Spatial index dialog
##########################################################

sub delete_index {
    my $self = shift;
    my $bd   = shift
      || $self->{project}->get_selected_base_data;

    my $result = $bd->delete_spatial_index;

    my $name = $bd->get_param('NAME');

    if ($result) {
        $self->set_dirty();
        $self->report_error( "BaseData $name: Spatial index deleted\n", q{}, );
    }
    else {
        $self->report_error(
            "BaseData $name: had no spatial index, so nothing deleted\n",
            q{}, );
    }

    return;
}

#  show the spatial index dialogue
#  need to add buttons to increment/decrement all by the step size
sub show_index_dialog {
    my $self = shift;

    my $gui = Biodiverse::GUI::GUIManager->instance;

    #  get an array of the cellsizes
    my $bd             = $self->{project}->get_selected_base_data;
    my @cellsize_array = $bd->get_cell_sizes;                      #  get a copy
    my %coord_bounds   = $bd->get_coord_bounds;

    #  get the current index
    my $used_index = $bd->get_param('SPATIAL_INDEX');
    my @resolutions;
    if ($used_index) {
        my $res_array = $used_index->get_param('RESOLUTIONS');
        @resolutions = @$res_array;
    }

    #  create the table and window
    #  we really should generate one from scratch...

    my $dlgxml = Gtk3::Builder->new();
    $dlgxml->add_from_file( $self->get_gtk_ui_file('dlgImportParameters.ui') );

    my $table = $dlgxml->get_object('tableImportParameters');

    my $dlg = $dlgxml->get_object('dlgImportParameters');
    $dlg->set_transient_for( $self->get_object('wndMain') );
    $dlg->set_title('Set index sizes');

    #  add the incr/decr buttons
    my $row = 0;
    my $incr_button = Gtk3::Button->new_with_label('Increment all');
    $table->attach( $incr_button, 0, $row, 1, 1 );
    $incr_button->set_tooltip_text(
        'Increase all the axes by their default increments'
    );
    # $row++;
    my $decr_button = Gtk3::Button->new_with_label('Decrement all');
    $table->attach( $decr_button, 1, $row, 1, 1 );
    $decr_button->set_tooltip_text(
        'Decrease all the axes by their default increments'
    );

    my $i = 0;
    my @resolution_widgets;

  BY_AXIS:
    foreach my $cellsize (@cellsize_array) {
        $row++;

        my $is_text_axis = 0;

        my $init_value = $used_index ? $resolutions[$i] : $cellsize * 2;

        my $min_val   = $cellsize;
        my $max_val   = 10E10;
        my $step_incr = $cellsize;

        if ( $cellsize == 0 ) {    #  allow some change for points
                #  avoid precision issues later on when predicting offsets
            $init_value = 0 + sprintf "%.10f",
              ( $coord_bounds{MAX}[$i] - $coord_bounds{MIN}[$i] ) / 20;
            $min_val   = 0;             #  should allow non-zero somehow
            $step_incr = $init_value;
        }
        elsif ( $cellsize < 0 ) {       #  allow no change for text
            $init_value   = 0;
            $min_val      = 0;
            $max_val      = 0;
            $is_text_axis = 1;
            $step_incr    = 0;
        }

        my $page_incr = $cellsize * 10;

        my $label_text = "Axis $i";

        # Make the label
        my $label = Gtk3::Label->new;
        $label->set_text($label_text);

        #  make the widget
        my $adj =
          Gtk3::Adjustment->new( $init_value, $min_val, $max_val, $step_incr,
            $page_incr, 0, );
        my $widget = Gtk3::SpinButton->new( $adj, $init_value, 10, );

        $table->attach( $label,  0, $row, 1, 1);
        $table->attach( $widget, 1, $row, 1, 1);

        push @resolution_widgets, $widget;

        # Add a tooltip
        my $tip_text = "Set the index size for axis $i\n"
          . "Middle click the arrows to change by $page_incr.\n";
        if ($is_text_axis) {
            $tip_text = "Text axes must be set to zero";
        }
        else {
            if ( $cellsize == 0 ) {
                $tip_text .=
                    "The default value and increment are calculated as 1/20th "
                  . "of the axis extent, rounded to the nearest 10 decimal places";
            }
            else {
                $tip_text .=
                  "The default value and increment are equal to the cell size";
            }
        }

        $widget->set_tooltip_text($tip_text);
        $label->set_tooltip_text($tip_text);

        if ($is_text_axis) {
            $widget->set_sensitive(0);
        }

        $label->show;
        $widget->show;

        $i++;
    }

    $incr_button->signal_connect(
        clicked => \&on_index_dlg_change_all,
        [ 1, undef, \@resolution_widgets ],
    );
    $decr_button->signal_connect(
        clicked => \&on_index_dlg_change_all,
        [ 0, undef, \@resolution_widgets ],
    );

    # Show the dialog
    $dlg->show_all();

    #$window->show_all;

    #  a kludge until we build the window and table ourselves
    $dlgxml->get_object('ImportParametersLabel')->hide;
    $dlgxml->get_object('lblDlgImportParametersNext')->set_label('OK');

  RUN_DIALOG:
    my $response = $dlg->run();

    if ( $response ne 'ok' ) {
        $dlg->destroy;
        return;
    }

    #my $use_index = $check_box->get_active;
    #if (! $use_index) {
    #    $self->report_error ('Spatial index deleted', q{});
    #    $bd->delete_spatial_index;
    #}
    #else {
    #  need to harvest all the widget values
    my @widget_values;
    foreach my $widget (@resolution_widgets) {
        push @widget_values, $widget->get_value;
    }

    my $join_text     = q{, };
    my $orig_res_text = join( $join_text, @resolutions );
    my $new_res_text  = join( $join_text, @widget_values );

    my $feedback = q{};
    if ( $new_res_text eq $orig_res_text ) {
        $feedback =
            "Resolutions unchanged, spatial index not rebuilt\n"
          . 'Delete the index and rebuild if you have imported '
          . 'new data since it was last built';
    }
    else {
        $bd->build_spatial_index( resolutions => [@widget_values] );
        $feedback = "Spatial index built using resolutions:\n" . $new_res_text;
    }

    print "[GUI] $feedback\n";
    Biodiverse::GUI::YesNoCancel->run(
        {
            text        => $feedback,
            title       => 'Feedback',
            hide_yes    => 0,
            hide_no     => 1,
            hide_cancel => 1,
            yes_is_ok   => 1,
        }
    );

    #}

    $dlg->destroy;

    return;
}

sub on_index_dlg_change_all {
    my $button     = shift;
    my $args_array = shift;

    my $incr = $args_array->[0];

    #my $check_box   = $args_array->[1];
    my $widgets = $args_array->[2];

    #  activate the checkbox
    #$check_box->set_active (1);

    #  and update the spinboxes
    foreach my $widget (@$widgets) {
        my $adj       = $widget->get_adjustment;
        my $increment = $adj->get_step_increment;
        my $value =
            $incr
          ? $widget->get_value + $increment
          : $widget->get_value - $increment;
        $widget->set_value($value);
    }

    return;
}

sub show_index_dialog_orig {
    my $self = shift;

    my $dlgxml = Gtk3::Builder->new();
    $dlgxml->add_from_file( $self->get_gtk_ui_file('dlgIndex.ui') );
    my $dlg = $dlgxml->get_object('dlgIndex');
    $dlg->set_transient_for( $self->get_object('wndMain') );
    $dlg->set_modal(1);

    # set existing settings
    my $base_ref = $self->get_project->get_selected_base_data();
    return if not defined $base_ref;

    my $cell_sizes = $base_ref->get_cell_sizes;

    my $used_index = $base_ref->get_param('SPATIAL_INDEX');
    $dlgxml->get_object('chkIndex')->set_active($used_index);
    my $spin = $dlgxml->get_object('spinContains');

    #my $step, $page) = $spin->get_increments;
    if ($used_index) {
        my $resolutions = $used_index->get_param('RESOLUTIONS');
        $spin->set_value( $resolutions->[0] );
        $spin->set_increments( $resolutions->[0], $resolutions->[0] * 10 );
    }
    else {
        #  default is zero for non-numeric axes
        my $cell1 = $cell_sizes->[0];
        $spin->set_value( $cell1 >= 0 ? $cell1 : 0 );
        $spin->set_increments( abs($cell1), abs( $cell1 * 10 ) );
    }

    my $response = $dlg->run();
    if ( $response eq 'ok' ) {

        my $use_index = $dlgxml->get_object('chkIndex')->get_active();
        if ($use_index) {

        #my $resolution = $dlgxml->get_object('spinContains')->get_value_as_int;
            my $resolution = $dlgxml->get_object('spinContains')->get_value;

  #  repeat the resolution for all cell sizes until the widget has more spinners
            my @resolutions = ($resolution) x scalar @$cell_sizes;

            #  override for any text fields
            foreach my $i ( 0 .. $#$cell_sizes ) {
                $resolutions[$i] = 0 if $cell_sizes->[$i] < 0;
            }

            $base_ref->build_spatial_index( resolutions => [@resolutions] );
        }
        else {
            print "[GUI] Index deleted\n";
            $base_ref->delete_spatial_index;
        }

    }

    $dlg->destroy();

    return;
}

##########################################################
# Misc
##########################################################

sub do_run_exclusions {
    my $self = shift;

    my $basedata = $self->{project}->get_selected_base_data();

    return if not defined $basedata;

    my @array = $basedata->get_output_refs;
    if ( scalar @array ) {
        my $text =
            "Cannot run exclusions on a BaseData object with existing outputs\n"
          . "Either delete the outputs or use 'File->Duplicate without outputs'"
          . " to create a new object\n";
        $self->report_error($text);
        return;
    }

    my $exclusions_hash = $basedata->get_param('EXCLUSION_HASH');
    if ( Biodiverse::GUI::Exclusions::show_dialog($exclusions_hash) ) {

        #print Data::Dumper::Dumper($exclusions_hash);
        my $tally = eval { $basedata->run_exclusions() };
        my $feedback = $tally->{feedback};
        if ($EVAL_ERROR) {
            $self->report_error($EVAL_ERROR);
            return;
        }
        my $dlg = Gtk3::Dialog->new(
            'Exclusion results',
            $self->get_object('wndMain'),
            'modal', 'gtk-ok' => 'ok',
        );
        my $text_widget = Gtk3::Label->new();
        $text_widget->set_alignment( 0, 1 );
        $text_widget->set_text($feedback);
        $text_widget->set_selectable(1);
        $dlg->get_content_area->pack_start( $text_widget, 0, 0, 0 );

        $dlg->show_all;
        $dlg->run;
        $dlg->destroy;

        $self->set_dirty();
    }

    return;
}

sub show_save_dialog {
    my ( $self, $title, $suffixes, $explanations ) = @_;
    my @suffixes = @$suffixes;
    my @explanations = @{ $explanations // [] };

    my $dlg = Gtk3::FileChooserDialog->new(
        $title,
        undef,
        'save',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
    );

    foreach my $i ( 0 .. $#suffixes ) {
        my $suffix = $suffixes[$i];
        my $expl   = $explanations[$i] // "$suffix files";
        my $filter = Gtk3::FileFilter->new();
        $filter->add_pattern("*.$suffix");
        $filter->set_name($expl);
        $dlg->add_filter($filter);
    }

    $dlg->set_modal(1);
    eval { $dlg->set_do_overwrite_confirmation(1); }; # GTK < 2.8 doesn't have this

    my ( $filename, $format );
    if ( $dlg->run() eq 'ok' ) {
        my $filter = $dlg->get_filter;
        $format   = $filter->get_name;
        $filename = $dlg->get_filename();
    }
    $dlg->destroy();

    return ( $filename, $format );
}

#FIXME merge with above
sub show_open_dialog {
    my $self = shift;
    my %args = @_;

    my $title       = $args{title};
    my $suffix      = $args{suffix};
    my $initial_dir = $args{initial_dir};

    my $dlg = Gtk3::FileChooserDialog->new(
        $title,
        undef,
        'open',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
    );
    if ( !defined $initial_dir ) {
        use Cwd;
        $initial_dir = getcwd();
    }
    $dlg->set_current_folder($initial_dir);

    my $filter = Gtk3::FileFilter->new();

    $filter->add_pattern("*.$suffix");
    $filter->set_name(".$suffix files");
    $dlg->add_filter($filter);
    $dlg->set_modal(1);

    my $filename;
    if ( $dlg->run() eq 'ok' ) {
        $filename = $dlg->get_filename();
    }
    $dlg->destroy();

    return $filename;
}

sub do_set_working_directory {
    my $self        = shift;
    my $title       = shift || "Select working directory";
    my $initial_dir = shift;

    my $dlg = Gtk3::FileChooserDialog->new(
        $title, undef, "open",
        "gtk-cancel",  "cancel",
        "gtk-ok",      'ok'
    );
    $dlg->set_action('select-folder');
    $dlg->set_current_folder($initial_dir) if $initial_dir;

    my $dir;
    if ( $dlg->run() eq 'ok' ) {
        $dir = $dlg->get_current_folder();
        print "[GUIMANAGER] Setting working directory to be $dir\n";
        chdir($dir);
    }
    $dlg->destroy;

    return $dir;
}

#  report an error using a dialog window
#  turning into general feedback - needs modification
sub report_error {
    my $self         = shift;
    my $error        = shift;    #  allows for error classes
    my $title        = shift;
    my $use_all_text = shift;

    if ( !defined $title ) {
        $title = 'PROCESSING ERRORS';
    }

    #use Data::Dumper;
    #print Dumper($error);
    my $e = $error;    # keeps a copy of the object

    if ( blessed $error
        and ( blessed $error) !~ /ProgressDialog::Cancel/
        and $error->can ('error')
        ) {
        warn $error->error, "\n", $error->trace->as_string, "\n";
    }
    elsif ( $title =~ /error/i ) {
        warn $error;
    }
    else {
        print $error;    #  might not be an error
    }

    #  and now strip out message from the error class
    if ( blessed $error) {
        $error = $error->message . "\n";
        if ( $e->{Error} ) {
            $error .= $e->{Error};    #  nasty hack at error internals
        }
    }
    my @error_array =
        $use_all_text
      ? $error
      : split( "\n", $error, 2 );

    if ( @error_array > 1 ) {
        my $text_wrapper = Text::Wrapper->new( columns => 80 );
        $error_array[1] = $text_wrapper->wrap( $error_array[1] );
    }

    my $show_details_value = -10;

    my $dlg = Gtk3::Dialog->new(
        $title,
        $self->get_object('wndMain'),
        'modal',
        'show details' => $show_details_value,
        'gtk-ok'       => 'ok',
    );
    my $text_widget       = Gtk3::Label->new();
    my $extra_text_widget = Gtk3::Label->new();

    foreach my $w ( $text_widget, $extra_text_widget ) {

        #$w->set_use_markup(1);
        $w->set_line_wrap(1);
        $w->set_width_chars(90);
        $w->set_alignment( 0, 0 );
        $w->set_selectable(1);
        $w->set_ellipsize('PANGO_ELLIPSIZE_END');
    }

    $text_widget->set_text( $error_array[0] );
    $extra_text_widget->set_text( $error_array[1]
          // 'There are no additional details' );

    my $check_button = Gtk3::ToggleButton->new_with_label('show details');
    $check_button->signal_connect_swapped(
        clicked => \&on_report_error_show_hide,
        $extra_text_widget,
    );
    $check_button->set_active(0);

    my $details_box = Gtk3::VBox->new( 1, 6 );
    $details_box->set_homogeneous(0);
    $details_box->pack_start( Gtk3::HSeparator->new(), 0, 0, 0 );

    #$details_box->pack_start($check_button, 0, 0, 0);
    my $scrolled_window = Gtk3::ScrolledWindow->new;
    $scrolled_window->add($extra_text_widget);
    $scrolled_window->set_propagate_natural_height(1);
    $details_box->pack_start( $scrolled_window, 1, 1, 0 );

    $dlg->get_content_area->pack_start( $text_widget, 0, 0, 0 );
    $dlg->get_content_area->pack_start( $details_box, 0, 0, 0 );

    $dlg->show_all;
    my $details_visible = 0;

    #$extra_text_widget->hide;
    $details_box->hide;
    $dlg->resize( 1, 1 );

    while (1) {
        my $response = $dlg->run;
        #  not sure whey we're being fed 'apply' as the value
        last if $response ne 'apply';
        if ($details_visible) {
            $dlg->resize( 1, 1 );
        }
        $details_visible = !$details_visible;
        $details_box->set_visible ($details_visible);
    }

    $dlg->destroy;

    return;
}

#  warn if the user tries to run a randomisation and the basedata already has outputs
sub warn_outputs_exist_if_randomisation_run {
    my $self    = shift;
    my $bd_name = shift;

    warn
"[GUI] Warning:  Creating cluster or spatial output when Basedata has existing randomisation outputs\n";

    my $header =
      "BaseData object $bd_name has one or more existing randomisations.\n";

    my $warning =
        "Any new analyses will not be synchronised with those randomisations.\n"
      . 'Continue?';

    my $response = Biodiverse::GUI::YesNoCancel->run(
        {
            text        => $warning,
            header      => $header,
            title       => 'WARNING',
            hide_cancel => 1,
        }
    );

    return $response;
}


sub update_open_tabs_after_randomisation {
    my ($self, %args) = @_;
    
    my $base_ref = $args{basedata_ref};
    croak 'basedata_ref arg not defined' if !defined $base_ref;
    my $list_prefix = $args{list_prefix};
    
    my $tab_array = $self->{tabs};
    
    foreach my $tab ( @$tab_array ) {
        next if ( blessed $tab ) =~ /Outputs$/;
        #  these have no lists that need to be updated
        next if ( blessed $tab ) =~ /Randomise|SpatialMatrix/;
        
        my $bd = $tab->get_base_ref;
        next if $base_ref ne $bd;
        
        $tab->update_display_list_combos (
            list_prefix => $list_prefix,
        );
    }
    
}



1;

__END__

=head1 NAME

Biodiverse::GUI::GUIManager

=head1 DESCRIPTION

Module containing methods to control the Biodiverse GUI.

=head1 AUTHOR

Eugene Lubarsky and Shawn Laffan

=head1 LICENSE

LGPL

=head1 SEE ALSO

See http://www.purl.org/biodiverse for more details.

=cut
