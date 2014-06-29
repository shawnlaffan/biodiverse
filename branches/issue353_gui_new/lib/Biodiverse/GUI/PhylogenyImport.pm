<<<<<<< .mine
package Biodiverse::GUI::PhylogenyImport;
use 5.010;
use strict;
use warnings;
use English ( -no_match_vars );

use File::Basename;
use File::BOM qw / :subs /;

use Gtk2;
use Gtk2::GladeXML;
use Biodiverse::ReadNexus;
use Biodiverse::GUI::BasedataImport;
use Biodiverse::GUI::YesNoCancel;

our $VERSION = '0.99_001';

use Biodiverse::GUI::Project;

##################################################
# High-level procedure
##################################################

sub run {
    my $gui = shift;

    # Get format for tree import (initial dialog)
    # testing- call as yes/no/cancel
    my $response = Biodiverse::GUI::YesNoCancel->run({header => 'Use tabular tree format?'});
    return if $response eq 'cancel';

    my $use_tabular_format = $response eq 'yes';

    #########
    # 1. Get the name & NEXUS filename
    #########
    my $extensions = [
        ['nex', 'tre', 'nwk', 'phy'],
        'nex',
        'tre',
        'nwk',
        'phy',
        '*'
    ];
    if ($use_tabular_format) {  #  override
        $extensions = [
            ['txt', 'csv'],
            'txt',
            'csv',
            '*',
        ];
    }

    my ($name, $filename) = Biodiverse::GUI::OpenDialog::Run (
        'Import Tree from file',
        @$extensions,
    );

    return if not ($filename and $name);  #  drop out

    #########
    # 2. Make object
    #########
    my $phylogeny_ref = Biodiverse::ReadNexus->new;

    #########
    # 3. Possibly do Label remapping
    #########

    my %import_params;
    my $call_remap;
    my %tabular_column_labels = (
        TREENAME_COL       => 'Tree name', 
        LENGTHTOPARENT_COL => 'Length',
        NODENUM_COL        => 'Node number',
        NODENAME_COL       => 'Node name',
        PARENT_COL         => 'Parent node',
    );

    # Process fields produced by get_column_use.  The key of each import_fields entry 
    # will be the label passed to get_column_use, ie the text display of each field.
    # Create a different mapping from the identifier (eg NODENUM) to the column. 
    my %field_map;
    my $import_fields;
    if ($use_tabular_format) {
        # Piggy-back code here, a bit messy.
        # The get_remap_info call is used for identifying columns for table import,
        # as well as for re-map
        $call_remap = 1;
        my @column_fields = values %tabular_column_labels;
        $import_fields = get_column_use($gui, $filename, \@column_fields);

        my %labels_to_columns = reverse %tabular_column_labels;
        foreach my $field (keys %$import_fields) {
            my $arr_ref = $import_fields->{$field};
            my $h_ref = @$arr_ref[0];
            # find the column for this label
            $field_map{$labels_to_columns{$field}} = $h_ref->{id};
        }
        #say '';
    }

    my $remap_dlg_response = Biodiverse::GUI::YesNoCancel->run({
        header      => 'Remap tree labels?',
        hide_cancel => 1,
    });
    if ($remap_dlg_response eq 'yes') {
        my %remap_data = Biodiverse::GUI::BasedataImport::get_remap_info ($gui, $filename, 'label');

        #  now do something with them...
        my $remap;

        ###### check if we need to call remap (eg if tabular, and no remapping?) 
        if (defined $remap_data{file}) {
            $remap = Biodiverse::ElementProperties->new;
            $remap->import_data (
                %remap_data,
            );
        }
        $import_params{element_properties} = $remap;
        if (!defined $remap) {
            $import_params{use_element_properties} = undef;
        }
    }
    
    # process fields produced by get_column_use.  the key of each import_fields entry 
    # will be the label passed to get_column_use, ie the text display of each field.
    # create a different mapping from the identifier (eg NODENUM) to the column. 
    my %labels_to_columns = reverse %tabular_column_labels;
    #my %field_map;
    foreach my $field (keys %$import_fields) {
        my $arr_ref = $import_fields->{$field};
        my $h_ref = @$arr_ref[0];
        # find the column for this label
        $field_map{$labels_to_columns{$field}} = $h_ref->{id};
    }

    #########
    # 3. Load da tree
    #########
    my %import_args = (
        file => $filename,
        %import_params,
    );
    if ($use_tabular_format) {
        #  Looks partly redundant, but ensures %import_params takes precedence over column_map - needed?
        %import_args = (  
            file       => $filename,
            column_map => \%field_map,
            %import_params,
        );
    }

    eval {
        $phylogeny_ref->import_data (%import_args)
    };
    if ($EVAL_ERROR) {
        $gui->report_error ($EVAL_ERROR);
        return;
    }
    
    my $phylogeny_array = $phylogeny_ref->get_tree_array;

    my $tree_count = scalar @$phylogeny_array;
    my @names;
    foreach my $tree (@$phylogeny_array) {
        push @names, $tree->get_param ('NAME');
    }
    my $feedback =
          "[Phylogeny import] $tree_count trees parsed from $filename\nNames are: "
        . join ', ', @names;

    #########
    #  4.  add the phylogenies to the GUI
    #########
    $gui->get_project->add_phylogeny ($phylogeny_array);

    $gui->report_error (  #  not really an error...
        $feedback,
        'Import results'
    );

    #  SWL:  not sure why we return undef in scalar context
    return defined wantarray ? $phylogeny_ref : undef;
}

# present dialog to determine usage for each column
# returns results map (see BasedataImport::get_remap_column_settings)
sub get_column_use {
    my $gui           = shift;
    my $tree_filename = shift;
    my $col_usages    = shift;

    my ($_file, $data_dir, $_suffixes) = fileparse($tree_filename);

    # Get header columns
    say "[GUI] Discovering columns from $tree_filename";
    my $line;

    open (my $fh, '<:via(File::BOM)', $tree_filename);
    while (<$fh>) { # get first non-blank line
        $line = $_;
        #$line =~ s/[\r\n]$//;
        chomp $line;
        last if $line;
    }
    $fh->close;

    my $sep = $gui->get_project->guess_field_separator (string => $line);
    my $eol = $gui->get_project->guess_eol (string => $line);
    my @headers_full = $gui->get_project->csv2list('string' => $line, sep_char => $sep, eol => $eol);
    # add non-blank columns with labels, and generic for blank columns
    my @headers;
    my $col_num = 0;
    foreach my $header (@headers_full) {
        my $this_label = $header // "col$col_num"; 
        $col_num++;
        push @headers, $this_label;
    }

    my ($dlg, $col_widgets) = Biodiverse::GUI::BasedataImport::make_remap_columns_dialog(
        \@headers,
        $gui->get_widget('wndMain'),
        [],
        $col_usages,
    );

    my ($column_settings, $response);

    # just show once, grab column usages, handle errors later
  RUN_DLG:
    while(1) {
        $response = $dlg->run();

        if ($response eq 'help') {
            explain_tabular_import_col_options($dlg);
            next RUN_DLG;
        }
        elsif ($response ne 'ok') {
            $dlg->destroy();
            die "Operation cancelled\n";
        }

        my @usages = ('Ignore');
        push @usages, @$col_usages;
        $column_settings = Biodiverse::GUI::BasedataImport::get_remap_column_settings(
            $col_widgets,
            \@usages,
        );

        # check each of the usage fields has been allocated
        foreach my $usage (@$col_usages) {
            say "checking $usage, " . $column_settings->{$usage};
            if (! $column_settings->{$usage}) {
                my $msg = Gtk2::MessageDialog->new(undef, "modal", "error", "close", "Please select one of each column usage type");
                $msg->run();
                $msg->destroy();
                $column_settings = undef;

                next RUN_DLG; 
            }
        }
        last RUN_DLG;
    }
    $dlg->destroy();

    return $column_settings; 
}

sub explain_tabular_import_col_options {
    my $parent = shift;

    my %explain = (
        Ignore        => 'There is no setting for this column.  '
                        . 'It will be ignored or its use will depend on your other settings.',
        Length        => 'This column contains the branch/node lengths.',
        'Tree name'   => 'This column contains the name of the tree '
                       . '(allowing multiple trees to be stored in and imported from one table).',
        'Node number' => 'Unique ID of the node within the tree.',
        'Node name'   => 'Name of the node.  Anonymous nodes are denoted by numbers '
                       . 'ending in three underscores, e.g. "36___", '
                       . 'and must be unique within the tree.',
    );

    Biodiverse::GUI::BasedataImport::show_expl_dialog (\%explain, $parent);

    return;
}

##################################################
# Load Label remap file
##################################################

# Asks user whether remap is required
#   returns (filename, in column, out column)
sub get_remap_info {
    my $gui = shift;
    my $tree_filename = shift;

    my ($_file, $data_dir, $_suffixes) = fileparse($tree_filename);

    # Get filename for the name-translation file
    my $filename = $gui->show_open_dialog('Select Label remap file', q{*}, $data_dir);
    return (undef, undef, undef) if not $filename;

    # Get header columns
    print "[GUI] Discovering columns from $filename\n";
    my $line;
    
    open (my $fh, '<:via(File::BOM)', $filename);
    while (<$fh>) { # get first non-blank line
        $line = $_;
        chomp $line;
        last if $line;
    }
    $fh->close;
    
    my $sep = $gui->get_project->guess_field_separator (string => $line);
    my $eol = $gui->get_project->guess_eol (string => $line);
    my @headers_full = $gui->get_project->csv2list('string' => $line, sep_char => $sep, eol => $eol);
    # add non-blank columns
    my @headers;
    foreach my $header (@headers_full) {
        push @headers, $header if $header;
    }

    my ($dlg, $col_widgets) = make_columns_dialog(\@headers, $gui->get_widget('wndMain'));
    my ($column_settings, $response);
    while (1) { # keep showing Dialog until have at least one Label & one matrix-start column
        $response = $dlg->run();
        if ($response eq 'ok') {
            $column_settings = get_column_settings($col_widgets, \@headers);
            my $num_in = @{$column_settings->{in}};
            my $num_out = @{$column_settings->{out}};

            if ($num_in != 1 || $num_out != 1) {
                my $msg = Gtk2::MessageDialog->new(undef, "modal", "error", "close", "Please select one input and one output column");
                $msg->run();
                $msg->destroy();
                $column_settings = undef;
            }
            else {
                last;
            }
        }
        else {
            last;
        }

    }
    $dlg->destroy();

    my $incol = $column_settings->{in}[0]->{id};
    my $outcol = $column_settings->{out}[0]->{id};
    return ($filename, $incol, $outcol);
}





##################################################
# extracting information from widgets
##################################################

# extract column types and sizes into lists that can be passed to the reorder Dialog
sub get_column_settings {
    my $cols = shift;
    my $headers = shift;
    my $num = @$cols;
    my (@incol, @outcol);

    foreach my $i (0..($num - 1)) {
        my $widgets = $cols->[$i];
        # widgets[0] - ignore
        # widgets[1] - in
        # widgets[2] - out

        if ($widgets->[1]->get_active()) {
            push (@incol, { name => $headers->[$i], id => $i });

        }
        elsif ($widgets->[2]->get_active()) {
            push (@outcol, { name => $headers->[$i], id => $i });
        }

    }

    return { in => \@incol, out => \@outcol };
}

##################################################
# column selection Dialog
##################################################

sub make_columns_dialog {
    # we have to dynamically generate the choose columns Dialog since
    # the number of columns is unknown

    my $header = shift; # ref to column header array
    my $wnd_main = shift;
    
    my $num_columns = @$header;
    print "[gui] generating make columns Dialog for $num_columns columns\n";

    # make Dialog
    my $dlg = Gtk2::Dialog->new("Choose columns", $wnd_main, "modal", "gtk-cancel", "cancel", "gtk-ok", "ok");
    my $label = Gtk2::Label->new("<b>Select column types</b>");
    $label->set_use_markup(1);
    $dlg->vbox->pack_start ($label, 0, 0, 0);

    # make table
    my $table = Gtk2::Table->new(4,$num_columns + 1);
    $table->set_row_spacings(5);
    #$table->set_col_spacings(20);

    # make scroll window for table
    my $scroll = Gtk2::ScrolledWindow->new;
    $scroll->add_with_viewport($table);
    $scroll->set_policy('automatic', 'never');
    $dlg->vbox->pack_start($scroll, 1, 1, 5);

    # make header column
    $label = Gtk2::Label->new("<b>Column</b>");
    $label->set_use_markup(1);
    $label->set_alignment(1, 0.5);
    $table->attach_defaults($label, 0, 1, 0, 1);

    $label = Gtk2::Label->new("ignore");
    $label->set_alignment(1, 0.5);
    $table->attach_defaults($label, 0, 1, 1, 2);

    $label = Gtk2::Label->new("in");
    $label->set_alignment(1, 0.5);
    $table->attach_defaults($label, 0, 1, 2, 3);

    $label = Gtk2::Label->new("out");
    $label->set_alignment(1, 0.5);
    $table->attach_defaults($label, 0, 1, 3, 4);

    # add columns
    # use col_widgets to store the radio buttons, spinboxes
    my $col_widgets = [];
    foreach my $i (0..($num_columns - 1)) {
        my $header = ${$header}[$i];
        add_column($col_widgets, $table, $i, $header);
    }

    $dlg->set_resizable(1);
    $dlg->set_default_size(500,0);
    $dlg->show_all();
    return ($dlg, $col_widgets);
}

sub add_column {
    my ($col_widgets, $table, $col_id, $header) = @_;

    # column header
    my $label = Gtk2::Label->new("<tt>$header</tt>");
    $label->set_use_markup(1);

    # type radio button
    my $radio1 = Gtk2::RadioButton->new(undef, '');        # ignore
    my $radio2 = Gtk2::RadioButton->new($radio1, '');    # in
    my $radio3 = Gtk2::RadioButton->new($radio2, '');    # out
    $radio1->set('can-focus', 0);
    $radio2->set('can-focus', 0);
    $radio3->set('can-focus', 0);

    # attack to table
    $table->attach_defaults($label, $col_id + 1, $col_id + 2, 0, 1);
    $table->attach($radio1, $col_id + 1, $col_id + 2, 1, 2, 'shrink', 'shrink', 0, 0);
    $table->attach($radio2, $col_id + 1, $col_id + 2, 2, 3, 'shrink', 'shrink', 0, 0);
    $table->attach($radio3, $col_id + 1, $col_id + 2, 3, 4, 'shrink', 'shrink', 0, 0);

    # Store widgets
    $col_widgets->[$col_id] = [$radio1, $radio2, $radio3];
}

1;
=======
package Biodiverse::GUI::PhylogenyImport;

use strict;
use warnings;
use English ( -no_match_vars );

use File::Basename;
use File::BOM qw / :subs /;

use Gtk2;
use Gtk2::GladeXML;
use Biodiverse::ReadNexus;
use Biodiverse::GUI::BasedataImport;
use Biodiverse::GUI::YesNoCancel;

our $VERSION = '0.19';

use Biodiverse::GUI::Project;

##################################################
# High-level procedure
##################################################

sub run {
    my $gui = shift;

    #########
    # 1. Get the name & NEXUS filename
    #########
    my ($name, $nexus_filename) = Biodiverse::GUI::OpenDialog::Run (
        'Import Tree from file',
        ['nex', 'tre', 'nwk', 'phy'],
        'nex',
        'tre',
        'nwk',
        'phy',
        '*',
    );

    return if not ($nexus_filename and $name);  #  drop out

    #########
    # 2. Make object
    #########
    my $phylogeny_ref = Biodiverse::ReadNexus->new;

    #########
    # 3. Possibly do Label remapping
    #########
    #my ($remap_filename, $incol, $outcol) = getRemapInfo($gui, $nexus_filename);
    #if ($remap_filename and defined $incol and defined $outcol) {
    #    print "[Phylogeny import] remapping from $remap_filename. in=$incol out=$outcol\n";
    #    $phylogeny_ref->load_label_remap (file => $remap_filename, in_col_num => $incol, out_col_num => $outcol);
    #}

    my %import_params;
    if (Biodiverse::GUI::YesNoCancel->run({header => 'Remap tree labels?'}) eq 'yes') {
        my %remap_data = Biodiverse::GUI::BasedataImport::getRemapInfo ($gui, $nexus_filename, 'label');
        #  now do something with them...
        my $remap;
        if ($remap_data{file}) {
            #my $file = $remap_data{file};
            $remap = Biodiverse::ElementProperties->new;
            $remap->import_data (#file => $file,
                           %remap_data,
                        );
        }
        $import_params{element_properties} = $remap;
        if (not defined $remap) {
            $import_params{use_element_properties} = undef;
        }
    }



    #########
    # 3. Load da tree
    #########
    #$phylogeny_ref->parse (file => $nexus_filename);
    eval {$phylogeny_ref->import_data (
        file => $nexus_filename,
        %import_params
    )};
    if ($EVAL_ERROR) {
        $gui->report_error ($EVAL_ERROR);
        return;
    }

    my $phylogeny_array = $phylogeny_ref->get_tree_array;
    
    my $tree_count = scalar @$phylogeny_array;
    my $feedback = "[Phylogeny import] $tree_count trees parsed from $nexus_filename\nNames are: ";
    my @names;
    foreach my $tree (@$phylogeny_array) {
        push @names, $tree->get_param ('NAME');
    }
    $feedback .= join (", ", @names);
    
    #########
    #  4.  add the phylogenies to the GUI
    #########
    $gui->getProject->addPhylogeny ($phylogeny_array);
    
    $gui->report_error (  #  not really an error...
        $feedback,
        'Import results'
    );

    return defined wantarray ? $phylogeny_ref : undef;

}

##################################################
# Load Label remap file
##################################################

# Asks user whether remap is required
#   returns (filename, in column, out column)
sub getRemapInfo {
    my $gui = shift;
    my $tree_filename = shift;

    my ($_file, $data_dir, $_suffixes) = fileparse($tree_filename);

    # Get filename for the name-translation file
    my $filename = $gui->showOpenDialog('Select Label remap file', q{*}, $data_dir);
    return (undef, undef, undef) if not $filename;

    # Get header columns
    print "[GUI] Discovering columns from $filename\n";
    my $line;
    
    open (my $fh, '<:via(File::BOM)', $filename);
    while (<$fh>) { # get first non-blank line
        $line = $_;
        chomp $line;
        last if $line;
    }
    $fh->close;
    
    my $sep = $gui->getProject->guess_field_separator (string => $line);
    my $eol = $gui->getProject->guess_eol (string => $line);
    my @headers_full = $gui->getProject->csv2list('string' => $line, sep_char => $sep, eol => $eol);
    # add non-blank columns
    my @headers;
    foreach my $header (@headers_full) {
        push @headers, $header if $header;
    }

    my ($dlg, $col_widgets) = makeColumnsDialog(\@headers, $gui->getWidget('wndMain'));
    my ($column_settings, $response);
    while (1) { # keep showing Dialog until have at least one Label & one matrix-start column
        $response = $dlg->run();
        if ($response eq 'ok') {
            $column_settings = getColumnSettings($col_widgets, \@headers);
            my $num_in = @{$column_settings->{in}};
            my $num_out = @{$column_settings->{out}};

            if ($num_in != 1 || $num_out != 1) {
                my $msg = Gtk2::MessageDialog->new(undef, "modal", "error", "close", "Please select one input and one output column");
                $msg->run();
                $msg->destroy();
                $column_settings = undef;
            }
            else {
                last;
            }
        }
        else {
            last;
        }

    }
    $dlg->destroy();

    my $incol = $column_settings->{in}[0]->{id};
    my $outcol = $column_settings->{out}[0]->{id};
    return ($filename, $incol, $outcol);
}


##################################################
# extracting information from widgets
##################################################

# extract column types and sizes into lists that can be passed to the reorder Dialog
sub getColumnSettings {
    my $cols = shift;
    my $headers = shift;
    my $num = @$cols;
    my (@incol, @outcol);

    foreach my $i (0..($num - 1)) {
        my $widgets = $cols->[$i];
        # widgets[0] - ignore
        # widgets[1] - in
        # widgets[2] - out

        if ($widgets->[1]->get_active()) {
            push (@incol, { name => $headers->[$i], id => $i });

        }
        elsif ($widgets->[2]->get_active()) {
            push (@outcol, { name => $headers->[$i], id => $i });
        }

    }

    return { in => \@incol, out => \@outcol };
}

##################################################
# column selection Dialog
##################################################

sub makeColumnsDialog {
    # we have to dynamically generate the choose columns Dialog since
    # the number of columns is unknown

    my $header = shift; # ref to column header array
    my $wndMain = shift;

    my $num_columns = @$header;
    print "[gui] generating make columns Dialog for $num_columns columns\n";

    # make Dialog
    my $dlg = Gtk2::Dialog->new("Choose columns", $wndMain, "modal", "gtk-cancel", "cancel", "gtk-ok", "ok");
    my $label = Gtk2::Label->new("<b>Select column types</b>");
    $label->set_use_markup(1);
    $dlg->vbox->pack_start ($label, 0, 0, 0);

    # make table
    my $table = Gtk2::Table->new(4,$num_columns + 1);
    $table->set_row_spacings(5);
    #$table->set_col_spacings(20);

    # make scroll window for table
    my $scroll = Gtk2::ScrolledWindow->new;
    $scroll->add_with_viewport($table);
    $scroll->set_policy('automatic', 'never');
    $dlg->vbox->pack_start($scroll, 1, 1, 5);

    # make header column
    $label = Gtk2::Label->new("<b>Column</b>");
    $label->set_use_markup(1);
    $label->set_alignment(1, 0.5);
    $table->attach_defaults($label, 0, 1, 0, 1);

    $label = Gtk2::Label->new("ignore");
    $label->set_alignment(1, 0.5);
    $table->attach_defaults($label, 0, 1, 1, 2);

    $label = Gtk2::Label->new("in");
    $label->set_alignment(1, 0.5);
    $table->attach_defaults($label, 0, 1, 2, 3);

    $label = Gtk2::Label->new("out");
    $label->set_alignment(1, 0.5);
    $table->attach_defaults($label, 0, 1, 3, 4);

    # add columns
    # use col_widgets to store the radio buttons, spinboxes
    my $col_widgets = [];
    foreach my $i (0..($num_columns - 1)) {
        my $header = ${$header}[$i];
        addColumn($col_widgets, $table, $i, $header);
    }

    $dlg->set_resizable(1);
    $dlg->set_default_size(500,0);
    $dlg->show_all();
    return ($dlg, $col_widgets);
}

sub addColumn {
    my ($col_widgets, $table, $colId, $header) = @_;

    # column header
    my $label = Gtk2::Label->new("<tt>$header</tt>");
    $label->set_use_markup(1);

    # type radio button
    my $radio1 = Gtk2::RadioButton->new(undef, '');        # ignore
    my $radio2 = Gtk2::RadioButton->new($radio1, '');    # in
    my $radio3 = Gtk2::RadioButton->new($radio2, '');    # out
    $radio1->set('can-focus', 0);
    $radio2->set('can-focus', 0);
    $radio3->set('can-focus', 0);

    # attack to table
    $table->attach_defaults($label, $colId + 1, $colId + 2, 0, 1);
    $table->attach($radio1, $colId + 1, $colId + 2, 1, 2, 'shrink', 'shrink', 0, 0);
    $table->attach($radio2, $colId + 1, $colId + 2, 2, 3, 'shrink', 'shrink', 0, 0);
    $table->attach($radio3, $colId + 1, $colId + 2, 3, 4, 'shrink', 'shrink', 0, 0);

    # Store widgets
    $col_widgets->[$colId] = [$radio1, $radio2, $radio3];
}

1;
>>>>>>> .r2535
