package Biodiverse::GUI::Manager::BaseDatas;

use strict;
use warnings;
use 5.022;

our $VERSION = '4.99_001';

use Carp;
use Scalar::Util qw /blessed/;

use English ( -no_match_vars );
use Readonly;

use FindBin qw ( $Bin );
use Path::Class ();
use Text::Wrapper;
use List::MoreUtils qw /first_index/;
use POSIX qw/fmod ceil/;


sub get_new_basedata_name {
    my $self = shift;
    my %args = @_;

    my $suffix = $args{suffix} || q{};

    my $bd = $self->{project}->get_selected_base_data();

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $bd->get_param('NAME');

    # If it ends with $suffix followed by a number then increment it
    if ( $name =~ /(.*$suffix)([0-9]+)$/ ) {
        $name = $1 . ( $2 + 1 );
    }
    else {
        $name .= $suffix . 1;
    }
    $txt_name->set_text($name);

    my $response = $dlg->run();
    my $chosen_name;
    if ( $response eq 'ok' ) {
        $chosen_name = $txt_name->get_text;
    }
    $dlg->destroy;

    return $chosen_name;
}

sub do_transpose_basedata {
    my $self = shift;

    my $new_name = $self->get_new_basedata_name( suffix => '_T' );

    return if not $new_name;

    my $bd   = $self->{project}->get_selected_base_data();
    my $t_bd = $bd->transpose;
    $t_bd->set_param( 'NAME' => $new_name );
    $self->{project}->add_base_data($t_bd);

    return;
}

sub do_basedata_reorder_axes {
    my $self = shift;

    my $new_name = $self->get_new_basedata_name( suffix => '_R' );
    return if not $new_name;

    my $bd = $self->{project}->get_selected_base_data();

    #  construct the label and group column settings
    my @lb_axes = 0 .. ( $bd->get_labels_ref->get_axis_count - 1 );
    my @lb_array;
    for my $i (@lb_axes) {
        push @lb_array, { name => "axis $i", id => $i };
    }

    my @gp_axes = 0 .. ( $bd->get_groups_ref->get_axis_count - 1 );
    my @gp_array;
    for my $i (@gp_axes) {
        push @gp_array, { name => "axis $i", id => $i };
    }

    my $column_settings = {
        groups => \@gp_array,
        labels => \@lb_array,
    };

    #  need to factor the reorder dialogues out of BasedataImport.pm
    my ( $dlgxml, $dlg ) =
      Biodiverse::GUI::BasedataImport::make_reorder_dialog( $self,
        $column_settings );
    my $response = $dlg->run();

    if ( $response ne 'ok' ) {
        $dlg->destroy;
        return;
    }

    my $params = Biodiverse::GUI::BasedataImport::fill_params($dlgxml);
    $dlg->destroy;

    my $new_bd = $bd->new_with_reordered_element_axes(%$params);
    $new_bd->set_param( NAME => $new_name );
    $self->{project}->add_base_data($new_bd);

    $self->set_dirty();

    return;
}


sub do_basedata_drop_axes {
    my $self = shift;

    my $new_name = $self->get_new_basedata_name( suffix => '_X' );
    return if not $new_name;

    my $bd = $self->{project}->get_selected_base_data();

    my $options = $self->run_axis_selector_dialog ($bd);

    return if !$options;

    my $to_drop = $options->{drop};
    return if !$to_drop || !@$to_drop;

    my $to_keep = $options->{keep};    
    croak "Cannot delete all axes from a basedata\n"
      if !$to_keep || !@$to_keep;

    my $type = $options->{type};
    $type =~ s/s$//;

    my $new_bd = $bd->clone (no_outputs => 1);
    #  do stuff here, currently one axis at a time
    #  make sure we work from the end
    #  (there are no negative $drop_i values in the GUI)
    foreach my $drop_i (reverse sort {$a <=> $b} @$to_drop) {
        $new_bd->drop_element_axis (
            type => $type,
            axis => $drop_i,
        );
    }

    $new_bd->set_param( NAME => $new_name );
    $self->{project}->add_base_data($new_bd);

    $self->set_dirty();

    return;
}

sub run_axis_selector_dialog {
    my ($self, $bd) = @_;

    $bd //= $self->{project}->get_selected_base_data();

    # are we attaching groups or labels?
    my $gui    = $self;                  #  copied code from elsewhere
    my $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file( $self->get_gtk_ui_file('dlgGroupsLabels.ui') );
    my $dlg = $dlgxml->get_object('dlgGroupsLabels');
    $dlg->set_transient_for( $gui->get_object('wndMain') );
    $dlg->set_modal(1);
    my $label = $dlgxml->get_object('label_dlg_groups_labels');
    $label->set_text('Drop group or label axes?');
    $dlg->set_title('Axis selector');
    my $response = $dlg->run();
    $dlg->destroy();

    return if not $response =~ /^(yes|no)$/;

    my $type = $response eq 'yes' ? 'labels' : 'groups';

    my $col_names_for_dialog = $type eq 'labels'
      ? [ 0 .. ( $bd->get_labels_ref->get_axis_count - 1 ) ]
      : [ 0 .. ( $bd->get_groups_ref->get_axis_count - 1 ) ];

    my @parameters;
    foreach my $i (@$col_names_for_dialog) {
        push @parameters,
            {
                name    => 'Axis_' . $i,
                type    => 'boolean',
                default => 0,
            };
    }
    use Biodiverse::Metadata::Parameter;
    my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';
    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file( $gui->get_gtk_ui_file('dlgImportParameters.ui') );
    $dlg = $dlgxml->get_object('dlgImportParameters');
    $dlg->set_title( 'Axes to drop' );

    # Build widgets for parameters
    my $table_name = 'tableImportParameters';
    my $table      = $dlgxml->get_object($table_name);

    # (passing $dlgxml because generateFile uses existing widget on the dialog)
    my $parameters_table = Biodiverse::GUI::ParametersTable->new;
    my $extractors = $parameters_table->fill( \@parameters, $table, $dlgxml );

    $dlg->show_all;
    $response = $dlg->run;
    $dlg->destroy;

    return wantarray ? () : {} if $response ne 'ok';

    my %properties_params = $parameters_table->extract($extractors);
    
    #  Reformat into drop/keep.
    #  If @keep is empty then we are trying
    #  to drop all axes, leading to badness. 
    my (@drop, @keep);
    foreach my $key (keys %properties_params) {
        my $i = $key;
        $i =~ s/^Axis_//;
        if ($properties_params{$key}) {  
            push @drop, $i;
        }
        else {
            push @keep, $i;
        }
    }
    my %results = (
        drop => \@drop,
        keep => \@keep,
        type => $type,
    );
    
    return wantarray? %results : \%results; 
}

sub do_basedata_attach_label_abundances_as_properties {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data();

    $bd->attach_label_abundances_as_properties;

    return;
}

sub do_basedata_attach_label_ranges_as_properties {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data();

    $bd->attach_label_ranges_as_properties;

    return;
}

sub do_basedata_attach_properties {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data();
    croak "Cannot add properties to Basedata with existing outputs\n"
      . "Use the Duplicate Without Outputs option to create a copy without deleting the outputs.\n"
      if $bd->get_output_ref_count;

    # are we attaching groups or labels?
    my $gui    = $self;                  #  copied code from elsewhere
    my $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file( $self->get_gtk_ui_file('dlgGroupsLabels.ui') );
    my $dlg = $dlgxml->get_object('dlgGroupsLabels');
    $dlg->set_transient_for( $gui->get_object('wndMain') );
    $dlg->set_modal(1);
    my $label = $dlgxml->get_object('label_dlg_groups_labels');
    $label->set_text('Group or label properties?');
    $dlg->set_title('Attach properties');
    my $response = $dlg->run();
    $dlg->destroy();

    return if not $response =~ /^(yes|no)$/;

    my $type = $response eq 'yes' ? 'labels' : 'groups';

    my %options = Biodiverse::GUI::BasedataImport::get_remap_info(
        gui              => $self,
        type             => $type,
        column_overrides => [qw /Input_element Property/],
    );

    return if !defined $options{file};

    my $props =
      Biodiverse::ElementProperties->new( name => 'assigning properties' );
    $props->import_data(%options);

    my $count = $bd->assign_element_properties(
        properties_object => $props,
        type              => $type,
    );

    #if ($count) {
        $self->set_dirty();
    #}

    my $summary_text = "Assigned properties to $count ${type}";
    my $summary_dlg  = Gtk2::MessageDialog->new(
        $self->{gui},
        'destroy-with-parent',
        'info',    # message type
        'ok',      # which set of buttons?
        $summary_text,
    );
    $summary_dlg->set_title('Assigned properties');

    $summary_dlg->run;
    $summary_dlg->destroy;

    return;
}

sub do_basedata_attach_group_properties_from_rasters {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data();
    croak "Cannot add properties to Basedata with existing outputs\n"
      . "Use the Duplicate Without Outputs option to create a copy without deleting the outputs.\n"
      if $bd->get_output_ref_count;
    my @axes = $bd->get_cell_sizes;
    my $axis_count = @axes;
    croak "Can only add properties from rasters to a Basedata with an axis count of 2, you have $axis_count axes\n"
      if $axis_count != 2;

    
    my $dlg = Gtk2::FileChooserDialog->new(
        'Select one or more rasters',
        undef,
        'open',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
    );
    $dlg->set_select_multiple(1);

    my $filter = Gtk2::FileFilter->new();
    $filter->set_name("raster files");
    foreach my $extension (qw /tif tiff img asc flt/) {
        $filter->add_pattern("*.$extension");
    }
    $dlg->add_filter($filter);
    $dlg->set_modal(1);
    
    my $vbox = $dlg->get_content_area;

    my $checkbox  = Gtk2::CheckButton->new;
    my $chk_label = Gtk2::Label->new (
        'Add intermediate property basedatas to project?'
    );
    $chk_label->set_alignment(1, 0.5);

    my $checkbox_overlap  = Gtk2::CheckButton->new;
    my $chk_label_overlap = Gtk2::Label->new (
        'Fail when raster does not overlap with basedata?'
    );
    $chk_label_overlap->set_alignment(1, 0.5);

    my $tooltip_group = Gtk2::Tooltips->new;
    $tooltip_group->set_tip(
        $chk_label,
          'This can be useful to check the imported values, but also because you '
        . 'might want to run further analyses on these data.',
        undef,
    );
    $tooltip_group->set_tip(
        $chk_label_overlap,
          'Non-overlaps can occur if your data are in a different coordinate system '
        . 'from the property rasters.  Note that data from any rasters prior to the '
        . 'one that fails will be added.  If this is not set then extent mismatches '
        . 'are silently ignored.  ',
        undef,
    );
    
    foreach my $chk ([$chk_label, $checkbox], [$chk_label_overlap, $checkbox_overlap]) {
        my $hbox = Gtk2::HBox->new;
        $hbox->set_homogeneous (0);
        $hbox->pack_start ($chk->[0], 1, 1, 0);
        $hbox->pack_start ($chk->[1], 1, 1, 0);
        $vbox->pack_start ($hbox, 0, 1, 0);
        $hbox->show_all;    
    }

    my $stat_label = Gtk2::Label->new ('Summary stats');
    $vbox->pack_start ($stat_label, 0, 1, 0);
    $stat_label->show;
    
    my @stats
      = sort
        keys %{$bd->get_stats_for_assign_group_properties_from_rasters};
    my $target_cols = 3;
    my $target_rows = ceil scalar @stats / $target_cols;
    my $stat_table = Gtk2::Table->new($target_cols, $target_rows, 1);
    my %stat_checkboxes;
    my $col = -2;
    my $row = -1;
    my $cols_per_row = $target_cols * 2;  #  label and checkbox
    foreach my $stat (@stats) {
        $col+=2;
        $col %= $cols_per_row;
        if ($col == 0) {
            $row++;
        }
        my $checkbox  = Gtk2::CheckButton->new;
        my $chk_label = Gtk2::Label->new ($stat);
        $chk_label->set_alignment(1, 0.5);
        $stat_table->attach($chk_label, $col,   $col+1, $row, $row+1, [ 'shrink', 'fill' ], 'shrink', 0, 0 );
        $stat_table->attach($checkbox,  $col+1, $col+2, $row, $row+1, [ 'shrink', 'fill' ], 'shrink', 0, 0 );
        $stat_checkboxes{$stat} = $checkbox;
    }
    $stat_checkboxes{mean}->set_active(1);  #  default
    $stat_table->show_all;
    #  Trick the system into displaying the table centred like the others.
    #  There has to be a better way.
    my $hbox_t = Gtk2::HBox->new;
    $hbox_t->set_homogeneous (0);
    $hbox_t->pack_start (Gtk2::Label->new(' '), 1, 1, 0);
    $hbox_t->pack_start ($stat_table, 1, 1, 0);

    $vbox->pack_start ($hbox_t, 0, 1, 0);
    $vbox->show_all;
    
    my $response = $dlg->run;
    my @raster_list = $dlg->get_filenames();
    my $return_basedatas  = $checkbox->get_active;
    my $die_if_no_overlap = $checkbox_overlap->get_active;
    $dlg->destroy();

    return if $response ne 'ok';
    
    my $basedatas = $bd->assign_group_properties_from_rasters(
        rasters          => \@raster_list,
        return_basedatas => $return_basedatas,
        die_if_no_overlap => $die_if_no_overlap,
        stats => [grep {$stat_checkboxes{$_}->get_active} keys %stat_checkboxes],
    );

    if ($return_basedatas) {
        foreach my $bd (@$basedatas) {
            $self->get_project->add_base_data($bd);
        }
        #  reassert selection of $bd as current basedata
        #  otherwise things get out of synch
        $self->get_project->select_base_data ($bd);
    }

    $self->set_dirty();

    my $count = @raster_list;
    my $summary_text
      = "Assigned properties using $count rasters.\n\n"
      . "If not all properties are assigned then check "
      . "the respective extents and coordinate systems. "
      . "Adding the intermediate property basedatas to "
      . "the project can be an effective means of doing this.";
    my $summary_dlg = Gtk2::MessageDialog->new(
        $self->{gui},
        'destroy-with-parent',
        'info',    # message type
        'ok',      # which set of buttons?
        $summary_text,
    );
    $summary_dlg->set_title('Assigned properties');

    $summary_dlg->run;
    $summary_dlg->destroy;

    return;
}


sub do_delete_element_properties {
    my $self = shift;
    my $bd   = $self->{project}->get_selected_base_data;

    croak "Cannot delete properties from a basedata with existing outputs" 
        . " (try 'duplicate without outputs')" 
        if($bd->get_output_ref_count);
    
    my $delete_el_props_gui = Biodiverse::GUI::DeleteElementProperties->new();
    my $to_delete_hash = $delete_el_props_gui->run( basedata => $bd );
}

sub do_delete_basedata {
    my $self = shift;

    my $bd   = $self->{project}->get_selected_base_data;
    my $name = $bd->get_param('NAME');

    my $response = Biodiverse::GUI::YesNoCancel->run(
        {
            title => 'Confirmation dialogue',
            text  => "Delete BaseData $name?",
        }
    );

    return if lc($response) ne 'yes';

    my @tabs = @{ $self->{tabs} };
    my $i    = 0;
    foreach my $tab (@tabs) {
        next if ( blessed $tab) =~ /Outputs$/;
        if ( $tab->get_base_ref eq $bd ) {
            $tab->on_close;
        }
        $i++;
    }

    $self->{project}->delete_base_data();

    return;
}

sub do_rename_basedata {
    my $self = shift;
    my $bd   = $self->{project}->get_selected_base_data();

    # Show the Get Name dialog
    my ( $dlgxml, $dlg ) = $self->get_dlg_duplicate();
    $dlg->set_title('Rename Basedata object');
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $txt_name = $dlgxml->get_object('txtName');
    my $name     = $bd->get_param('NAME');

    $txt_name->set_text($name);

    my $response = $dlg->run();

    if ( $response eq 'ok' ) {
        my $chosen_name = $txt_name->get_text;
        $self->{project}->rename_base_data($chosen_name);

        my $tab_was_open;
        foreach my $tab ( @{ $self->{tabs} } ) {

            #  don't rename tabs which aren't label viewers
            #my $aa = (blessed $tab);
            next if !( ( blessed $tab) =~ /Labels$/ );

            my $reg_ref = eval { $tab->get_base_ref };

            if ( defined $reg_ref and $reg_ref eq $bd ) {
                $tab->update_name( 'Labels - ' . $chosen_name );
                $tab_was_open = 1;

                #  we could stop checking now,
                #  but this allows us to have data
                #  open in more than one tab
            }
        }
    }

    $dlg->destroy;

    return;
}

sub do_basedata_reduce_axis_resolutions {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data();

    my $name = $bd->get_name;
    # If ends with a number increment it
    if ( $name =~ /(.*)([0-9]+)$/ ) {
        $name = $1 . ( $2 + 1 );
    }
    else {
        $name .= '1';
    }

    ###  NEED to generate:
    ###  the name field,
    ###  a table for the resolutions, and
    ###  a table for the origins.
    my $name_entry = Gtk2::Entry->new ();
    $name_entry->set_text ($name);
    my $name_label = Gtk2::Label->new ();
    $name_label->set_markup('<b>New name:</b> ');
    my $name_dlg = Gtk2::HBox->new;
    $name_dlg->pack_start ($name_label, 1, 1, 0);
    $name_dlg->pack_start ($name_entry, 1, 1, 0);

    my $resolution_label = Gtk2::Label->new;
    $resolution_label->set_markup (
        "\n<b>New resolutions</b>\n <i>Must be incremented by current axis sizes.</i>\n"
    );
    my ($resolution_table, $resolution_widgets)
      = $self->get_resolution_table_widget (
        basedata => $bd,
    );
    my $origin_label = Gtk2::Label->new;
    $origin_label->set_markup (
          "\n<b>New origins</b>\n"
        . "<i>Must be incremented by current axis sizes.\n"
        . "There is also little purpose in using values \n"
        . qq{exceeding the new cell sizes as these \n }
        . qq{are "snapping" values.</i>\n}
    );
    my ($origin_table, $origin_widgets)
      = $self->get_origin_table_widget (
        basedata => $bd,
    );

    my $dlg = Gtk2::Dialog->new (
        'Reduce basedata resolution',
        $self->get_object('wndMain'),
        'modal',
        'gtk-ok'       => 'ok',
        'gtk-cancel'   => 'cancel',
    );
    my $vbox = $dlg->get_content_area;
    $vbox->pack_start ($name_dlg, 1, 1, 0);
    #$vbox->pack_start (Gtk2::HSeparator->new, 1, 1, 0);
    my $align1 = Gtk2::Alignment->new(0, 0.5, 0, 0.25);
    $align1->add($resolution_label);
    $vbox->pack_start ($align1, 0, 0, 0);
    $vbox->pack_start ($resolution_table, 1, 1, 0);
    my $align2 = Gtk2::Alignment->new(0, 0.5, 0, 0.25);
    $align2->add($origin_label);
    $vbox->pack_start ($align2, 0, 0, 0);
    $vbox->pack_start ($origin_table, 1, 1, 0);
    $vbox->show_all();

    # Show the Get Name dialog
    $dlg->set_transient_for( $self->get_object('wndMain') );

    my $response = $dlg->run();
    if ($response ne 'ok') {
        $dlg->destroy;
        return;
    }
    
    my $chosen_name = $name_entry->get_text;
    my @cell_sizes   = map {$_->get_value} @$resolution_widgets;
    my @cell_origins = map {$_->get_value} @$origin_widgets;
    $dlg->destroy();

    my $cloned = $bd->clone_with_reduced_resolution (
        name         => $chosen_name,
        cell_sizes   => \@cell_sizes,
        cell_origins => \@cell_origins,
    );
    
    $self->{project}->add_base_data($cloned);
    $self->set_dirty;

    return;
}

sub get_resolution_table_widget {
    my ($self, %args) = @_;
    my $bd = $args{basedata} // $self->{project}->get_selected_base_data();

    my @cellsize_array = $bd->get_cell_sizes;
    my @origins_array  = $bd->get_cell_origins;
        
    my %coord_bounds   = $bd->get_coord_bounds;

    my $table = Gtk2::Table->new (0, 0, 0);

    my $tooltip_group = Gtk2::Tooltips->new;

    my $rows = $table->get('n-rows');
    $rows++;

    my $incr_button = Gtk2::Button->new_with_label('Increment all');
    $table->attach( $incr_button, 0, 1, $rows, $rows + 1, 'shrink', [], 0, 0 );
    $tooltip_group->set_tip( $incr_button,
        'Increase all the axes by their default increments', undef, );
    my $decr_button = Gtk2::Button->new_with_label('Decrement all');
    $table->attach( $decr_button, 1, 2, $rows, $rows + 1, 'shrink', [], 0, 0 );
    $tooltip_group->set_tip( $decr_button,
        'Decrease all the axes by their default increments', undef, );

    my $i = -1;
    my @resolution_widgets;

  BY_AXIS:
    foreach my $cellsize (@cellsize_array) {
        $i++;

        my $is_text_axis = 0;

        my $init_value = $cellsize;

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

        $rows = $table->get('n-rows');
        $rows++;
        $table->set( 'n-rows' => $rows );

        # Make the label
        my $label = Gtk2::Label->new;
        $label->set_text($label_text);

        #  make the widget
        my $adj = Gtk2::Adjustment->new(
            $init_value, $min_val,   $max_val,
            $step_incr,  $page_incr, 0,
        );
        my $widget = Gtk2::SpinButton->new( $adj, $init_value, 10, );

        $table->attach( $label,  0, 1, $rows, $rows + 1, 'shrink', [], 0, 0 );
        $table->attach( $widget, 1, 2, $rows, $rows + 1, 'shrink', [], 0, 0 );

        push @resolution_widgets, $widget;

        # Add a tooltip
        my $tip_text = "Set the index size for axis $i\n"
          . "Middle click the arrows to change by $page_incr.\n";
        if ($is_text_axis) {
            $tip_text = "Text axis resolutions cannot be changed";
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

        $tooltip_group->set_tip( $widget, $tip_text, undef );
        $tooltip_group->set_tip( $label,  $tip_text, undef );

        if ($is_text_axis) {
            $widget->set_sensitive(0);
        }

        $label->show;
        $widget->show;
    }

    #  attach signal handlers
    my $j = -1;
    # ensure it is a valid multiple from origin
    foreach my $widget (@resolution_widgets) {
        $j++;
        $widget->signal_connect (
            'value-changed' => sub {
                my $val = $widget->get_value;
                #  Avoid fmod - it causes grief with 0.2 cell sizes
                #  prob due to floating point issues.
                #  Precision should be configurable...
                my $offset = ($val - $origins_array[$j])
                            / $cellsize_array[$j];
                if ($cellsize_array[$j] < 1) {
                    $offset = ($offset * 10e10 + 0.5) / 10e10;
                }
                $offset -= int $offset;
                #  effectively zero given cell size constraints
                if ($offset > 10e-10) {
                    $val -= $offset;
                    $widget->set_value ($val);
                }
                return;
            }
        );
    }
    $incr_button->signal_connect(
        clicked => sub {
            foreach my $widget (@resolution_widgets) {
                my $increment = $widget->get_adjustment->step_increment;
                $widget->set_value($widget->get_value + $increment);
            }
        },
    );
    $decr_button->signal_connect(
        clicked => sub {
            foreach my $widget (@resolution_widgets) {
                my $increment = $widget->get_adjustment->step_increment;
                $widget->set_value($widget->get_value - $increment);
            }
        },
    );
    
    return ($table, \@resolution_widgets);
}

#  lots of copy-paste here from get_resolution_table_widget,
#  but integrating the two is not simple
sub get_origin_table_widget {
    my ($self, %args) = @_;
    my $bd = $args{basedata} // $self->{project}->get_selected_base_data();

    my @cellsize_array = $bd->get_cell_sizes;
    my @origins_array  = $bd->get_cell_origins;
        
    my %coord_bounds   = $bd->get_coord_bounds;

    my $table = Gtk2::Table->new (0, 0, 0);

    my $tooltip_group = Gtk2::Tooltips->new;

    my $rows = $table->get('n-rows');
    $rows++;

    my $incr_button = Gtk2::Button->new_with_label('Increment all');
    $table->attach( $incr_button, 0, 1, $rows, $rows + 1, 'shrink', [], 0, 0 );
    $tooltip_group->set_tip( $incr_button,
        'Increase all the axes by their default increments', undef, );
    my $decr_button = Gtk2::Button->new_with_label('Decrement all');
    $table->attach( $decr_button, 1, 2, $rows, $rows + 1, 'shrink', [], 0, 0 );
    $tooltip_group->set_tip( $decr_button,
        'Decrease all the axes by their default increments', undef, );

    my $i = -1;
    my @resolution_widgets;

  BY_AXIS:
    foreach my $origin (@origins_array) {
        $i++;
        my $cellsize = $cellsize_array[$i];

        my $is_text_axis = 0;

        my $init_value = $origin;

        my $min_val   = -10E10;
        my $max_val   =  10E10;
        my $step_incr = $cellsize;

        if ( $cellsize == 0 ) {    #  allow some change for points
            #  avoid precision issues later on when predicting offsets
            $step_incr = 0 + sprintf "%.10f",
              ( $coord_bounds{MAX}[$i] - $coord_bounds{MIN}[$i] ) / 20;
        }
        elsif ( $cellsize < 0 ) {       #  allow no change for text
            $init_value   = 0;
            $min_val      = 0;
            $max_val      = 0;
            $is_text_axis = 1;
            $step_incr    = 0;
        }

        my $page_incr = $step_incr * 10;

        my $label_text = "Axis $i";

        $rows = $table->get('n-rows');
        $rows++;
        $table->set( 'n-rows' => $rows );

        # Make the label
        my $label = Gtk2::Label->new;
        $label->set_text($label_text);

        #  make the widget
        my $adj = Gtk2::Adjustment->new(
            $init_value, $min_val,   $max_val,
            $step_incr,  $page_incr, 0,
        );
        my $widget = Gtk2::SpinButton->new( $adj, $init_value, 10, );

        $table->attach( $label,  0, 1, $rows, $rows + 1, 'shrink', [], 0, 0 );
        $table->attach( $widget, 1, 2, $rows, $rows + 1, 'shrink', [], 0, 0 );

        push @resolution_widgets, $widget;

        # Add a tooltip
        my $tip_text = "Set the index size for axis $i\n"
          . "Middle click the arrows to change by $page_incr.\n";
        if ($is_text_axis) {
            $tip_text = "Text axis origins cannot be changed";
        }
        else {
            if ( $cellsize == 0 ) {
                $tip_text .=
                    "The default value and increment are calculated as 1/20th "
                  . "of the axis extent, rounded to the nearest 10 decimal places";
            }
            else {
                $tip_text .=
                  "The default value and increment are equal to "
                   . "the origin and cell size, respectively";
            }
        }

        $tooltip_group->set_tip( $widget, $tip_text, undef );
        $tooltip_group->set_tip( $label,  $tip_text, undef );

        if ($is_text_axis) {
            $widget->set_sensitive(0);
        }

        $label->show;
        $widget->show;
    }

    #  attach signal handlers - this could be factored out into a sub
    my $j = 0;
    # ensure it is a valid multiple from origin
    foreach my $widget (@resolution_widgets) {
        $widget->signal_connect (
            'value-changed' => sub {
                my $val = $widget->get_value;
                my $fmod = fmod (
                  ($val - $origins_array[$j]),
                  $cellsize_array[$j],
                );
                if ($fmod) {
                    $val -= $fmod;
                    $widget->set_value ($val);
                }
                return;
            }
        );
        $i++;
    }
    $incr_button->signal_connect(
        clicked => sub {
            foreach my $widget (@resolution_widgets) {
                my $increment = $widget->get_adjustment->step_increment;
                $widget->set_value($widget->get_value + $increment);
            }
        },
    );
    $decr_button->signal_connect(
        clicked => sub {
            foreach my $widget (@resolution_widgets) {
                my $increment = $widget->get_adjustment->step_increment;
                $widget->set_value($widget->get_value - $increment);
            }
        },
    );
    
    return ($table, \@resolution_widgets);
}

sub do_rename_basedata_labels {
    my $self = shift;
    $self->_do_rename_basedata_groups_or_labels('rename_labels');
}

sub do_rename_basedata_groups {
    my $self = shift;
    $self->_do_rename_basedata_groups_or_labels('rename_groups');
}

sub _do_rename_basedata_groups_or_labels {
    my ( $self, $method ) = @_;

    my $bd      = $self->{project}->get_selected_base_data();
    my %options = Biodiverse::GUI::BasedataImport::get_remap_info(
        gui              => $self,
        column_overrides => [qw /Input_element Remapped_element/],
    );

    ##  now do something with them...
    if ( $options{file} ) {

        #my $file = $options{file};
        my $check_list = Biodiverse::ElementProperties->new;
        $check_list->import_data(%options);
        $bd->$method( remap => $check_list );
    }

    $self->set_dirty;
    return;
}

sub do_merge_basedatas {
    my $self = shift;

    my $bd     = $self->get_project->get_selected_base_data;
    my $b_list = $self->get_project->get_base_data_list;
    my @basedatas =
      grep { $_ ne $bd && $bd->cellsizes_and_origins_match( from => $_ ) }
      @$b_list;
    my @names = map { $_->get_name } @basedatas;

    croak
"No valid basedatas to merge from (must have same cell sizes and origins)\n"
      if !scalar @names;

    #  now get the new length
    my $param = {
        name       => 'from',
        label_text => 'Basedata to merge into selected basedata',
        tooltip    => 'Labels and groups from this basedata will be merged '
          . 'into the selected basedata in the project',
        type    => 'choice_index',
        default => 0,
        choices => \@names,
    };
    bless $param, 'Biodiverse::Metadata::Parameter';

    my $dlgxml = Gtk2::Builder->new();
    $dlgxml->add_from_file( $self->get_gtk_ui_file('dlgImportParameters.ui') );
    my $param_dlg = $dlgxml->get_object('dlgImportParameters');

    #$param_dlg->set_transient_for( $self->get_object('wndMain') );
    $param_dlg->set_title('Select basedata');

    # Build widgets for parameters
    my $param_table = $dlgxml->get_object('tableImportParameters');

# (passing $dlgxml because generateFile uses existing glade widget on the dialog)
    my $parameters_table = Biodiverse::GUI::ParametersTable->new;
    my $param_extractors =
      $parameters_table->fill( [$param], $param_table, $dlgxml, );

    # Show the dialog
    $param_dlg->show_all();

    my $response = $param_dlg->run();

    if ( $response ne 'ok' ) {
        $param_dlg->destroy;
        return;
    }

    my $params = $parameters_table->extract($param_extractors);

    $param_dlg->destroy;

    my %args = @$params;

    my $from = $basedatas[ $args{from} ];

    $bd->merge( from => $from );

    $self->set_dirty;

    return;
}

sub do_binarise_basedata_elements {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data();
    return if !$bd;

    $bd->binarise_sample_counts;

    $self->set_dirty;
}

sub do_add_basedata_label_properties {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data();
    my %options =
      Biodiverse::GUI::BasedataImport::get_remap_info( gui => $self, );

    ##  now do something with them...
    if ( $options{file} ) {

        #my $file = $options{file};
        my $check_list = Biodiverse::ElementProperties->new;
        $check_list->import_data(%options);
        $bd->assign_element_properties(
            type              => 'labels',
            properties_object => $check_list,
        );
    }

    $self->set_dirty;
    return;
}

sub do_add_basedata_group_properties {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data();
    my %options =
      Biodiverse::GUI::BasedataImport::get_remap_info( gui => $self, );

    ##  now do something with them...
    if ( $options{file} ) {

        #my $file = $options{file};
        my $check_list = Biodiverse::ElementProperties->new;
        $check_list->import_data(%options);
        $bd->assign_element_properties(
            type              => 'groups',
            properties_object => $check_list,
        );
    }

    $self->set_dirty;
    return;
}


sub do_basedata_extract_embedded_trees {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data();

    return if !defined $bd;

    my @objects = $bd->get_embedded_trees;

    foreach my $object (@objects) {
        $self->do_open_phylogeny($object);
    }

    return;
}

sub do_basedata_extract_embedded_matrices {
    my $self = shift;

    my $bd = $self->{project}->get_selected_base_data();

    return if !defined $bd;

    my @objects = $bd->get_embedded_matrices;

    foreach my $object (@objects) {
        $self->do_open_matrix($object);
    }

    return;
}

sub do_basedata_trim_to_tree {
    my $self = shift;
    my %args = @_;      #  keep or trim flag

    my $bd   = $self->{project}->get_selected_base_data;
    my $tree = $self->{project}->get_selected_phylogeny;

    return if !defined $bd || !defined $tree;

    $self->do_trim_basedata( $bd, $tree, %args );

    return;
}

sub do_basedata_trim_to_matrix {
    my $self = shift;
    my %args = @_;      #  keep or trim flag

    my $bd = $self->{project}->get_selected_base_data;
    my $mx = $self->{project}->get_selected_matrix;

    return if !defined $bd || !defined $mx;

    $self->do_trim_basedata( $bd, $mx, %args );

    return;
}

sub do_trim_basedata {
    my $self = shift;
    my $bd   = shift;
    my $data = shift;
    my %args = @_;

    my %results = eval { $bd->trim( $args{option} => $data ); };
    if ($EVAL_ERROR) {
        $self->report_error($EVAL_ERROR);
        return;
    }

    my $label_count = $bd->get_label_count;
    my $group_count = $bd->get_group_count;
    my $name        = $bd->get_param('NAME');

    my $text =
        "Deleted $results{DELETE_COUNT} labels"
      . " and $results{DELETE_SUB_COUNT} groups. "
      . "$name has $label_count labels remaining across "
      . "$group_count groups.\n";

    $self->report_error( $text, 'Trim results', );

    if ( $results{DELETE_COUNT} ) {
        $self->set_dirty();
    }

    return;
}


1;
