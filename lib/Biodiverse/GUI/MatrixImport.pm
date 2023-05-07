package Biodiverse::GUI::MatrixImport;
use 5.010;
use strict;
use warnings;
use File::Basename;
use Carp;
use Ref::Util qw { :all };

use Gtk2;

our $VERSION = '4.99_001';

use Biodiverse::GUI::Project;
use Biodiverse::GUI::BasedataImport
  ;    #  needed for the remap dialogue - should shift that to its own package
use Biodiverse::ElementProperties;
use Biodiverse::Common;

##################################################
# High-level procedure
##################################################

sub run {
    my $gui          = shift;
    #  too many slows the GUI, and most are typically redundant
    my $max_hdr_cols = shift // 50;    

    #########
    #  We are using the "normal" approach from here on
    #
    # 1. Get the matrix name & filename
    #########

    my ( $name, $filename ) = Biodiverse::GUI::OpenDialog::Run(
        'Import Matrix',
        [ 'csv', 'txt' ],
        'csv', 'txt', '*'
    );

    return if !( $filename && defined $name );

    #  should we use a sparse or normal format
    my $response = run_combo_sparse_normal();

    return if !$response;

    my $use_sparse_format = $response eq 'sparse' ? 1 : 0;

    return import_sparse_format( $name, $filename, $gui, $max_hdr_cols )
      if $use_sparse_format;

    # Get header columns
    say "[GUI] Discovering columns from $filename";

    my $line;

    my $fh = Biodiverse::Common->get_file_handle (
        file_name => $filename,
        use_bom   => 1,
    );

  BY_LINE:
    while ( $line = <$fh> ) {    # get first non-blank line
        $line =~ s/[\r\n]+$//;   #  handle mixed line endings
        last BY_LINE if $line;
    }
    my $header = $line;

#  run line tests on the second line as the header can sometimes have one column
    $line = <$fh>;

    my $sep_char = $gui->get_project->guess_field_separator( string => $line );
    my $eol = $gui->get_project->guess_eol( string => $line );
    my @headers = $gui->get_project->csv2list(
        string   => $header,
        sep_char => $sep_char,
        eol      => $eol
    );

    # Add non-blank columns
    # check for empty fields in header and replace with generic
    my $col_num = 0;
    while ( $col_num <= $#headers ) {
        $headers[$col_num] = $headers[$col_num] // "anon_col$col_num";
        $col_num++;
        last if $col_num >= $max_hdr_cols;
    }

    # check data, if additional lines in data, append in column list.
    my $checklines = 5;    # arbitrary, but should be sufficient
    my $donelines  = 0;
  LINE:
    while ( my $thisline = <$fh> ) {
        last if $col_num >= $max_hdr_cols;    #  already maxed out

        $donelines++;

        last if $donelines > $checklines;

        my @thisline_cols = $gui->get_project->csv2list(
            string => $thisline,

            #quote_char  => $quotes,
            sep_char => $sep_char,
            eol      => $eol,
        );

        next LINE if $col_num >= $#thisline_cols;

        while ( $col_num <= $#thisline_cols ) {
            $headers[$col_num] = "anon_col$col_num";
            $col_num++;
        }
    }

    $fh->close;

    #  should really take care of this above
    if ( scalar @headers > $max_hdr_cols ) {
        @headers = @headers[ 0 .. $max_hdr_cols ];
    }

    #########
    # 2. Get column types
    #########

    my ( $dlg, $col_widgets ) =
      make_columns_dialog_normal( \@headers, $gui->get_object('wndMain') );
    my ($column_settings);

  GET_RESPONSE:
    while (1)
    { # Keep showing dialog until have at least one label & one matrix-start column
        $response = $dlg->run();

        last GET_RESPONSE if $response ne 'ok';

        $column_settings = get_column_settings( $col_widgets, \@headers );
        my $num_labels = @{ $column_settings->{labels} };
        my $num_start  = @{ $column_settings->{start} };

        last GET_RESPONSE if $num_start == 1 && $num_labels > 0;

        #  try again if we get to here
        my $msg = Gtk2::MessageDialog->new(
            undef,
            'modal',
            'error',
            'close',
'Please select at least one label and only one start-of-matrix column',
        );
        $msg->run();
        $msg->destroy();
        $column_settings = undef;
    }

    $dlg->destroy();

    return if !$column_settings;

    #########
    # 3. Add the matrix
    #########
    my $matrix_ref = Biodiverse::Matrix->new( NAME => $name );

    # Set parameters
    my @label_columns;
    my $matrix_start_column;

    foreach my $col ( @{ $column_settings->{labels} } ) {
        push( @label_columns, $col->{id} );
        say "[Matrix import] label column is $col->{id}";
    }
    $matrix_start_column = $column_settings->{start}[0]->{id};
    say "[Matrix import] start column is $matrix_start_column";

    $matrix_ref->set_param( 'ELEMENT_COLUMNS', \@label_columns );
    $matrix_ref->set_param( 'MATRIX_STARTCOL', $matrix_start_column );

    # Load file
    $matrix_ref->load_data(
        file               => $filename,
        #input_quotes       => $quotes,
        sep_char => $sep_char,
    );

    $gui->get_project->add_matrix($matrix_ref);

    # run the remapper
    $gui->do_remap(
        default_remapee => $gui->get_project->get_selected_matrix,
        check_first     => 1,
    );

    return $matrix_ref;
}

##################################################
# Extracting information from widgets
##################################################

# Extract column types and sizes into lists that can be passed to the reorder dialog
#  NEED TO GENERALISE TO HANDLE ANY NUMBER
sub get_column_settings {
    my $cols    = shift;
    my $headers = shift;
    my $num     = @$cols;
    my ( @labels, @start );

    foreach my $i ( 0 .. ( $num - 1 ) ) {
        my $widgets = $cols->[$i];

        # widgets[0] - Ignore
        # widgets[1] - Label
        # widgets[2] - Matrix start

        if ( $widgets->[1]->get_active() ) {
            push( @labels, { name => $headers->[$i], id => $i } );

        }
        elsif ( $widgets->[2]->get_active() ) {
            push( @start, { name => $headers->[$i], id => $i } );
        }

    }

    return { start => \@start, labels => \@labels };
}

##################################################
# Column selection dialog
##################################################

# We have to dynamically generate the choose columns dialog since
# the number of columns is unknown
sub make_columns_dialog_normal {
    my $header       = shift;    # ref to column header array
    my $wnd_main     = shift;
    my $type_options = shift;    #  array of types

    if (not defined $type_options or !is_arrayref($type_options)) {
        $type_options = ['Ignore', 'Label', 'Matrix Start'];
    }

    my $num_columns = @$header;
    say "[GUI] Generating make columns dialog for $num_columns columns";

    # Make dialog
    my $dlg = Gtk2::Dialog->new(
        'Choose columns',
        $wnd_main, 'modal',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
    );

    my $label = Gtk2::Label->new(
        "<b>Select column types</b>\n(choose only one start matrix column)");
    $label->set_use_markup(1);
    $dlg->vbox->pack_start( $label, 0, 0, 0 );

    # Make table
    my $table = Gtk2::Table->new( 4, $num_columns + 1 );
    $table->set_row_spacings(5);

    #$table->set_col_spacings(20);

    # Make scroll window for table
    my $scroll = Gtk2::ScrolledWindow->new;
    $scroll->add_with_viewport($table);
    $scroll->set_policy( 'automatic', 'never' );
    $dlg->vbox->pack_start( $scroll, 1, 1, 5 );

    # Make header column
    $label = Gtk2::Label->new("<b>Column</b>");
    $label->set_use_markup(1);
    $label->set_alignment( 1, 0.5 );
    $table->attach_defaults( $label, 0, 1, 0, 1 );

    my $iter = 0;
    foreach my $type (@$type_options) {
        $iter++;
        $label = Gtk2::Label->new($type);
        $label->set_alignment( 1, 0.5 );
        $table->attach_defaults( $label, 0, 1, $iter, $iter + 1 );
    }

    # Add columns
    # use col_widgets to store the radio buttons, spinboxes
    my $col_widgets = [];
    foreach my $i ( 0 .. ( $num_columns - 1 ) ) {
        my $header_txt = "<i>$header->[$i]</i>";
        add_column( $col_widgets, $table, $i, $header_txt );
    }

    $dlg->set_resizable(1);
    $dlg->set_default_size( 500, 0 );
    $dlg->show_all();

    return ( $dlg, $col_widgets );
}

sub add_column {
    my ( $col_widgets, $table, $col_id, $header ) = @_;

    # Column header
    #say "setting header '$header'";
    my $label = Gtk2::Label->new("<tt>$header</tt>");
    $label->set_use_markup(1);
    $label->set_padding( 2, 0 );

    # Type radio button
    my $radio1 = Gtk2::RadioButton->new( undef,   '' );    # Ignore
    my $radio2 = Gtk2::RadioButton->new( $radio1, '' );    # Label
    my $radio3 = Gtk2::RadioButton->new( $radio2, '' );    # Matrix start
    $radio1->set( 'can-focus', 0 );
    $radio2->set( 'can-focus', 0 );
    $radio3->set( 'can-focus', 0 );

    # Attach to table
    $table->attach_defaults( $label, $col_id + 1, $col_id + 2, 0, 1 );
    $table->attach(
        $radio1,
        $col_id + 1,
        $col_id + 2,
        1, 2, 'shrink', 'shrink', 0, 0
    );
    $table->attach(
        $radio2,
        $col_id + 1,
        $col_id + 2,
        2, 3, 'shrink', 'shrink', 0, 0
    );
    $table->attach(
        $radio3,
        $col_id + 1,
        $col_id + 2,
        3, 4, 'shrink', 'shrink', 0, 0
    );

    # Store widgets
    $col_widgets->[$col_id] = [ $radio1, $radio2, $radio3 ];
}

sub import_sparse_format {
    my ( $name, $filename, $gui, $max_hdr_cols ) = @_;

    return if !( $filename && defined $name );

    my $column_settings = Biodiverse::GUI::BasedataImport::get_remap_info(
        gui              => $gui,
        type             => 'matrix',
        get_dir_from     => $filename,
        filename         => $filename,
        other_properties => [qw/Row Column Value/],
        column_overrides => [qw/Row Column Value/],
        required_cols    => [qw/Row Column Value/],
    );

    #  nothing selected
    return if !scalar keys %$column_settings;

    #  do we need a remap table?
    my $remap;
    my $remap_response = Biodiverse::GUI::YesNoCancel->run(
        {
            title => 'Remap option',
            text  => 'Remap element names and set include/exclude?'
        }
    );

    return if lc $remap_response eq 'cancel';

    if ( lc $remap_response eq 'yes' ) {
        my %remap_data = Biodiverse::GUI::BasedataImport::get_remap_info(
            gui          => $gui,
            type         => 'remap',
            get_dir_from => $filename,
        );

        #  now do something with them...
        if ( $remap_data{file} ) {

            #my $file = $remap_data{file};
            $remap = Biodiverse::ElementProperties->new;
            $remap->import_data(%remap_data);
        }
    }

    #########
    # 3. Add the matrix
    #########
    my $matrix_ref = Biodiverse::Matrix->new( NAME => $name );

    # Set parameters

    my %mapping = (
        label_row_columns => 'row',
        label_col_columns => 'column',
        value_column      => 'value',
    );

    my %import_args;
    foreach my $coltype ( keys %mapping ) {
        my $option = $mapping{$coltype};
        my $aref = $import_args{$coltype} = [];
        my $cols = $column_settings->{$option};
        if (!is_ref($cols)) {
            $cols = [$cols]
        }
        foreach my $col (@$cols) {
            push( @$aref, $col );
        }
    }

    # Load file
    $matrix_ref->import_data_sparse(
        file               => $filename,
        element_properties => $remap,

        #csv_object         => $csv_object,
        %import_args,
    );

    $gui->get_project->add_matrix($matrix_ref);

    return $matrix_ref;
}

sub run_combo_sparse_normal {

    my $combo = Gtk2::ComboBox->new_text;
    $combo->append_text('normal');
    $combo->append_text('sparse');
    $combo->set_active(0);
    $combo->show_all;
    $combo->set_tooltip_text(
'Normal is an n by n symmetric matric while sparse is one row/column pair per line'
    );

    my $label = Gtk2::Label->new('Input file format');

    my $dlg = Gtk2::Dialog->new_with_buttons(
        'Input file format',
        undef,
        'modal',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
    );

    my $vbox = $dlg->get_content_area;
    $vbox->pack_start( $label, 0, 0, 0 );
    $vbox->pack_start( $combo, 0, 0, 0 );

    $dlg->show_all;

    my $response = $dlg->run();
    $dlg->destroy();

    return if lc($response) ne 'ok';

    return $combo->get_active_text;
}

1;
