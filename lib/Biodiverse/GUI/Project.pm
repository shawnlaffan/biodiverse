package Biodiverse::GUI::Project;

use strict;
use warnings;
use 5.010;

use Path::Tiny qw /path/;

#use Data::Structure::Util qw /has_circular_ref get_refs/; #  hunting for circular refs

use Biodiverse::BaseData;
use Biodiverse::Common;
use Biodiverse::Matrix;
use Biodiverse::ReadNexus;

use Ref::Util qw { :all };

use English ( -no_match_vars );

our $VERSION = '4.99_009';

require Exporter;
use parent qw/Exporter Biodiverse::Common/;
our @EXPORT = qw(
  MODEL_BASEDATA
  MODEL_OUTPUT
  MODEL_ANALYSIS
  MODEL_TAB
  MODEL_OBJECT
  MODEL_BASEDATA_ROW
  MODEL_OUTPUT_TYPE
);

#use Storable ();

#use Geo::Shapelib;
use Geo::ShapeFile;
use Tie::RefHash;
use Scalar::Util qw /blessed/;

use Carp;

# Columns in the GTK Basedata-Output Model (for TreeViews and comboboxen)
use constant MODEL_BASEDATA => 0;    # basedata name
use constant MODEL_OUTPUT   => 1;    # output name
use constant MODEL_ANALYSIS => 2;    # available analysis output
use constant MODEL_TAB      => 3;    # scalar holding ref of open tab
use constant MODEL_OBJECT =>
  4;    # the basedata or output object represented by the row
use constant MODEL_BASEDATA_ROW => 5;   # TRUE if this is a basedata row.
                                        # Use to filter these out for comboboxes
use constant MODEL_OUTPUT_TYPE  => 6;   # Display the object type

sub new {
    my $class = shift;
    my %args  = @_;

    my $self = {};
    $self->{BASEDATA}    = [];
    $self->{MATRICES}    = [];
    $self->{PHYLOGENIES} = [];
    $self->{OVERLAYS}    = [];

    bless $self, $class;

    $self->select_matrix(undef);
    $self->select_phylogeny(undef);
    $self->select_base_data(undef);

    $self->set_params(
        OUTSUFFIX => 'bps',

        #OUTSUFFIX_XML => 'bpx',
        OUTSUFFIX_YAML => 'bpy',    #  deprecated
    );

    my $tmp;

    #  we have been passed a file argument - try to load it
    if ( $args{file} ) {
        $tmp = eval { $self->load_file( %args, ignore_suffix => 1 ) };
        if ($EVAL_ERROR) {
            $self->{gui}->report_error($EVAL_ERROR);
        }
        my $type = blessed($tmp);
        if ( $type eq blessed($self) ) {
            $self = $tmp;
            $tmp  = undef;
        }
    }

    $self->init();

    #  load any other valid objects if they were specified
    if ( defined $tmp ) {
        my $type = blessed $tmp;

        #if ($type eq blessed $self) {
        #    $self = $tmp;
        #}
        if ( $type eq 'Biodiverse::BaseData' ) {
            $self->add_base_data($tmp);
        }
        elsif ( $type eq 'Biodiverse::Matrix' ) {
            $self->add_matrix($tmp);
        }
        elsif ( $type eq 'Biodiverse::Tree' ) {
            $self->add_phylogeny($tmp);
        }
        else {
            croak "File $args{file} is not of correct type.\n It is "
              . blessed $tmp
              . " instead of "
              . blessed $self . "\n";
        }
    }

    return $self;
}

sub init {
    my $self = shift;
    $self->init_models();
    $self->init_overlay_hash();
    $self->clear_dirty();
}

sub save {
    my $self = shift;
    my %args = @_;

    # Make sure the callbacks/models/iterator hashes aren't saved
    # - they store pointers to memory!
    # Also don't save the shapefiles
    delete local $self->{callbacks};
    delete local $self->{iters};
    delete local $self->{models};
    delete local $self->{overlay_objects};

    my $tbl = eval {Biodiverse::GUI::Overlays::get_settings_table_from_grid()};
    warn $@ if $@;
    local $self->{OVERLAYS} = $tbl;

    #  make a copy so we don't interfere with the current display settings
    #  not needed if the code de-refs work properly
    #my $copy = $self->clone;
    my $copy = $self;    #  still debugging - leave as it was before

    #  SWL: now using a generic save method
    #    that handles all types
    my $file = $copy->save_to(%args);

    return $file;
}

sub get_base_data_output_model {
    my $self = shift;
    return $self->{models}{basedata_output_model};
}

sub get_basedata_model {
    my $self = shift;
    return $self->{models}{basedata_model};
}

sub get_matrix_model {
    my $self = shift;
    return $self->{models}{matrix_model};
}

sub get_phylogeny_model {
    my $self = shift;
    return $self->{models}{phylogeny_model};
}

sub init_models {
    my $self = shift;

# Output-Basedata model for Outputs TreeView
# BASEDATA
#   OUTPUT
#     Indices
# (tab) (object) (basedata row?)
#
# stored globally so don't have to set_model everything when a new project is loaded
    $self->{models}{basedata_output_model} =
      Biodiverse::GUI::GUIManager->instance->get_base_data_output_model;

    # Basedata model for combobox (based on above)
    $self->init_bd_filter_model;

    # Matrix/Phylogeny models for comboboxen
    $self->{models}{matrix_model} =
      Gtk3::ListStore->new( 'Glib::String', 'Glib::Scalar' );
    $self->{models}{phylogeny_model} =
      Gtk3::ListStore->new( 'Glib::String', 'Glib::Scalar' );

# We put all the iterator hashes separately because they must not be written out to XML
# (they contain pointers to real memory)
    $self->{iters}                  = {};
    $self->{iters}{basedata_iters}  = {};    # Maps basedata-ref  ->iterator
    $self->{iters}{matrix_iters}    = {};    # Maps matrix-ref    ->iterator
    $self->{iters}{phylogeny_iters} = {};    # Maps phylogeny-tree->iterator
    $self->{iters}{output_iters}    = {};    # Maps output-ref    ->iterator

    # Enable use of references as keys
    tie %{ $self->{iters}{basedata_iters} },  'Tie::RefHash';
    tie %{ $self->{iters}{matrix_iters} },    'Tie::RefHash';
    tie %{ $self->{iters}{phylogeny_iters} }, 'Tie::RefHash';
    tie %{ $self->{iters}{output_iters} },    'Tie::RefHash';

    $self->basedata_output_model_init();
    $self->matrix_model_init();
    $self->phylogeny_model_init();
    $self->update_gui_comboboxes();
}

sub init_bd_filter_model {
    my $self = shift;
    $self->{models}{basedata_model} =
        Gtk3::TreeModelFilter->new( $self->{models}{basedata_output_model} );
    $self->{models}{basedata_model}->set_visible_column(MODEL_BASEDATA_ROW);
}

sub clear_bd_filter_model {
    my $self = shift;
    Biodiverse::GUI::GUIManager->instance->set_basedata_model(undef);
    $self->{models}{basedata_model} = undef;
}

sub update_gui_comboboxes {
    my $self = shift;

    # Basedata
    my $gui = Biodiverse::GUI::GUIManager->instance;

    $gui->set_basedata_model( $self->{models}{basedata_model} );

    my $selected = $self->get_selected_base_data();

    if ($selected) {
        $self->select_base_data($selected); # this will update GUI combobox
    }

    # Matrix
    $gui->set_matrix_model( $self->{models}{matrix_model} );

    $selected = $self->get_selected_matrix();

    #if ($selected) {  #  always select so we get '(none)' for empties
    $self->select_matrix($selected);       # this will update GUI combobox
                                           #}

    # Phylogeny
    $gui->set_phylogeny_model( $self->{models}{phylogeny_model} );

    $selected = $self->get_selected_phylogeny();

    #if ($selected) {  #  always select so we get '(none)' for empties
    $self->select_phylogeny($selected);    # this will update GUI combobox
                                           #}

    $self->manage_empty_basedatas();
    $self->manage_empty_matrices();
    $self->manage_empty_phylogenies();
}

######################################################
## Whether there is unsaved ("dirty") data
######################################################

sub is_dirty {
    my $self = shift;
    return $self->{dirty};
}

sub clear_dirty {
    my $self = shift;
    $self->{dirty} = 0;
}

sub set_dirty {
    my $self = shift;
    $self->{dirty} = 1;
}

######################################################
## Maintenance of the GTK basedata-output model
## (this will automatically update all the treeviews)
######################################################

# Fills the Basedata-Output model with stored objects
sub basedata_output_model_init {
    my $self  = shift;
    my $model = $self->{models}{basedata_output_model};
    $model->clear();

    my $basedatas = $self->get_base_data_list();

    #print Data::Dumper::Dumper($basedatas);

    foreach my $basedata_ref ( @{$basedatas} ) {
        next if not defined $basedata_ref;

        #print "[Project] Loading basedata\n";

        my $basedata_iter = $self->basedata_row_add($basedata_ref);
        $self->basedata_add_outputs( $basedata_ref, $basedata_iter );
    }

    return;
}

sub basedata_add_outputs {
    my $self          = shift;
    my $basedata_ref  = shift;
    my $basedata_iter = shift;

    foreach my $output_ref ( $basedata_ref->get_output_refs_sorted_by_name() ) {

        # shouldn't have to do this, but sometimes do
        if ( !defined $output_ref->get_param('BASEDATA_REF') ) {
            $output_ref->set_param( BASEDATA_REF => $basedata_ref );
        }
        $output_ref->weaken_basedata_ref;    #  just in case

        $self->output_row_add( $basedata_iter, $output_ref );
        if ( blessed($output_ref) =~ /Spatial/ ) {
            $self->update_indices_rows($output_ref);
        }
    }

    return;
}

sub basedata_row_add {
    my $self         = shift;
    my $basedata_ref = shift;
    my $model        = $self->{models}{basedata_output_model};
    my $name         = $basedata_ref->get_param('NAME');

    #my $x = MODEL_OUTPUT_TYPE;
    #my $y = $model->get_n_columns;
    my $iter = $model->append(undef);    # new top-level row
    $model->set(
        $iter,
        MODEL_BASEDATA,     $name,        #  don't use fat commas with constants
        MODEL_OBJECT,       $basedata_ref,
        MODEL_BASEDATA_ROW, 1,

        #MODEL_OUTPUT_TYPE , 'BaseData',
    );

    #print "[Project] Model - added basedata row for $name\n";

    $self->{iters}{basedata_iters}{$basedata_ref} = $iter;
    return $iter;
}

# Add top-level row for an output
sub output_row_add {
    my $self          = shift;
    my $basedata_iter = shift;
    my $output_ref    = shift;

    my $model       = $self->{models}{basedata_output_model};
    my $name        = $output_ref->get_param('NAME');
    my $output_type = blessed $output_ref;
    $output_type =~ s/^Biodiverse:://;

    my $iter = $model->append($basedata_iter);
    $model->set(
        $iter,       MODEL_OUTPUT,       $name, MODEL_OBJECT,
        $output_ref, MODEL_BASEDATA_ROW, 0,     MODEL_OUTPUT_TYPE,
        $output_type,
    );

    #print "[Project] Model -    added output row for $name\n";

    $self->{iters}{output_iters}{$output_ref} = $iter;

    #print "[Project] - Outputs Model - Adding $output\n";
    return $iter;
}

# Add a row for each index that was calculated
sub update_indices_rows {
    my $self       = shift;
    my $output_ref = shift;
    my $iter       = $self->{iters}{output_iters}{$output_ref};
    my $model      = $self->{models}{basedata_output_model};

    # Find spatial results for first element (or first one that contains them)
    my @analyses;
    my $completed = $output_ref->get_param('COMPLETED');

    #  add rows if the analysis completed
    if ($completed) {
        my $elements = $output_ref->get_element_hash();
        my $first;    # = (keys %$elements)[0];
        my $i = 0;
        foreach my $key ( keys %$elements ) {

    #  must exist and have some results in it - somewhere else is auto-vivifying
            if ( exists $elements->{$key}{SPATIAL_RESULTS}
                and ( scalar keys %{ $elements->{$key}{SPATIAL_RESULTS} } ) )
            {
                $first = ( keys %$elements )[$i];
                last;    #  drop out
            }
            $i++;
            last if $i > 1000;    #  just check the first thousand
        }

        if ($first) {
            @analyses = keys( %{ $elements->{$first}{SPATIAL_RESULTS} } );
        }
    }

    # Delete all child rows
    while ( $model->iter_has_child($iter) ) {
        my $child_iter = $model->iter_nth_child( $iter, 0 );
        $model->remove($child_iter);
    }

    # Add child rows
    foreach my $analysis ( sort @analyses ) {

        my $child_iter = $model->append($iter);
        $model->set( $child_iter, MODEL_ANALYSIS, $analysis,
            MODEL_BASEDATA_ROW, 0 );

        #print "[Project] - Outputs Model- Adding analysis $analysis\n";
    }

    return;
}

######################################################
## Maintenance of the GTK matrix model
## (this will automatically update the GUI combobox)
######################################################

sub matrix_model_init {
    my $self   = shift;
    my $output = shift;

    my $matrices = $self->get_matrix_list();

    foreach my $matrix_ref ( @{$matrices} ) {
        next if not defined $matrix_ref;
        $self->matrix_row_add($matrix_ref);
    }

    $self->matrix_row_add_none;

    return;
}

sub matrix_row_add {
    my $self       = shift;
    my $matrix_ref = shift;
    return if !defined $matrix_ref;

    my $model = $self->{models}{matrix_model};

    my $iter = $model->append();
    $model->set( $iter, 0, $matrix_ref->get_param('NAME'), 1, $matrix_ref );
    $self->{iters}{matrix_iters}{$matrix_ref} = $iter;

    return;
}

sub matrix_row_add_none {
    my $self = shift;

    # Add the (none) entry - for Matrices we always want to have it
    my $model = $self->{models}{matrix_model};
    my $iter  = $model->append();
    $model->set( $iter, 0, '(none)', 1, undef );
    $self->{iters}{matrix_none} = $iter;

    return;
}

######################################################
## Maintenance of the GTK phylogeny model
## (this will automatically update the GUI combobox)
######################################################

sub phylogeny_model_init {
    my $self   = shift;
    my $output = shift;

    my $phylogenies = $self->get_phylogeny_list();

    foreach my $phylogeny_ref ( @{$phylogenies} ) {
        next if not defined $phylogeny_ref;
        $self->phylogeny_row_add($phylogeny_ref);
    }

    # Add the (none) entry - for Matrices we always want to have it
    my $model = $self->{models}{phylogeny_model};
    my $iter  = $model->append();
    $model->set( $iter, 0, '(none)', 1, undef );
    $self->{iters}{phylogeny_none} = $iter;

    return;
}

sub phylogeny_row_add {
    my $self          = shift;
    my $phylogeny_ref = shift;

    my $model = $self->{models}{phylogeny_model};

    my $iter = $model->append();
    $model->set( $iter, 0, $phylogeny_ref->get_param('NAME'),
        1, $phylogeny_ref );

    $self->{iters}{phylogeny_iters}{$phylogeny_ref} = $iter;

    return;
}
######################################################
## Adding/Removing/Selecting objects
######################################################

# Merely update the model
sub add_output {
    my $self         = shift;
    my $basedata_ref = shift;
    my $output_ref   = shift;

    # Add a row to the outputs model
    my $basedata_iter = $self->{iters}{basedata_iters}{$basedata_ref};

    #my $x = "$output_ref";
    #say "Adding output $x";
    my $iter = $self->get_output_iter($output_ref);
    if ( !defined $iter ) {    #  don't re-add it
        $self->output_row_add( $basedata_iter, $output_ref );
        $self->set_dirty();
    }

    return;
}

sub update_output_name {
    my $self       = shift;
    my $output_ref = shift;
    my $name       = $output_ref->get_param('NAME');

    print "[Project] Updating an output name to $name\n";

    #my $iter = $self->{iters}{output_iters}{$output_ref};
    #$self->{models}{basedata_output_model}->set($iter, MODEL_OUTPUT, $name);

    my $iter = $self->{iters}{output_iters}{$output_ref};
    if ( defined $iter ) {
        my $model = $self->{models}{basedata_output_model};

       #$self->{models}{basedata_output_model}->set($iter, MODEL_OUTPUT, $name);
        $model->set( $iter, MODEL_OUTPUT, $name );

        #$model->set_value ($iter, 1, $name);

        $self->set_dirty();
    }

    return;
}

# Makes a new BaseData object or adds an existing one
sub add_base_data {
    my $self         = shift;
    my $basedata_ref = shift;
    my $no_select    = shift;

    if ( not ref $basedata_ref ) {
        $basedata_ref = Biodiverse::BaseData->new(
            NAME       => $basedata_ref,
            CELL_SIZES => [],              #  default, gets overridden later
        );
    }

    push( @{ $self->{BASEDATA} }, $basedata_ref );

    # Add to model
    my $basedata_iter = $self->basedata_row_add($basedata_ref);
    $self->basedata_add_outputs( $basedata_ref, $basedata_iter );
    $self->manage_empty_basedatas();

    if ( not $no_select ) {
        $self->select_base_data($basedata_ref);
    }

    #  hack to avoid seg faults with csv objects
    $basedata_ref->get_groups_ref->delete_element_name_csv_object;
    $basedata_ref->get_labels_ref->delete_element_name_csv_object;

    $self->set_dirty();
    return $basedata_ref;
}

# Makes a new Matrix object or adds an existing one
sub add_matrix {
    my $self       = shift;
    my $matrix_ref = shift;
    my $no_select  = shift;

    croak "matrix argument is not blessed\n"
      if not blessed $matrix_ref;

    my %ref_hash;
    my $matrices = $self->{MATRICES} || [];
    @ref_hash{@$matrices} = (1) x scalar @$matrices;
    my $add_count;

    if ( !exists $ref_hash{$matrix_ref} ) {
        push @$matrices, $matrix_ref;
        $add_count++;
    }

    return if !$add_count;

    # update model
    $self->matrix_row_add($matrix_ref);
    $self->manage_empty_matrices();
    $self->select_matrix($matrix_ref) unless $no_select;

    $self->set_dirty();
    return $matrix_ref;
}

# Add a phylogeny object
sub add_phylogeny {
    my $self        = shift;
    my $phylogenies = shift;
    my $no_select = shift;
    
    if (!is_arrayref($phylogenies)) {
        $phylogenies = [$phylogenies];  #  make a scalar value an array
    }

    my %ref_hash;
    @ref_hash{ @{ $self->{PHYLOGENIES} } } = undef;
    my $add_count;

  TREE:
    foreach my $new_tree (@$phylogenies) {
        next TREE if exists $ref_hash{$new_tree};

        $add_count++;
        push @{ $self->{PHYLOGENIES} }, $new_tree;
    }

    return if !$add_count;    #  nothing added

    # update model
    foreach my $phylogeny_ref (@$phylogenies) {

#$phylogeny_ref->set_parents_below();  #  make sure we have the correct parental structure - dealt with by ReadNexus now.
        $phylogeny_ref->set_param( MAX_COLOURS => 1 )
          ;    #  underhanded, but gives us one colour when clicked on
        $self->phylogeny_row_add($phylogeny_ref);
        $self->manage_empty_phylogenies()
          ;    #  SWL: not sure if this should be in the loop
    }

    if ( !$no_select ) {
        $self->select_phylogeny( @{$phylogenies}[0] );   #  select the first one
    }

    $self->set_dirty();

    return;
}

sub select_base_data {
    my $self         = shift;
    my $basedata_ref = shift;

    $self->set_param( SELECTED_BASEDATA => $basedata_ref );

    return if !$basedata_ref;
    return if !$self->{models}{basedata_model};

    if ($basedata_ref) {

        my $iter = $self->{iters}{basedata_iters}{$basedata_ref};

        # $iter is from basedata-output model
        # Make it relative to the filtered basedata model
        if ( defined $iter) {
            $iter = $self->{models}{basedata_model}
              ->convert_child_iter_to_iter($iter);
            Biodiverse::GUI::GUIManager->instance->set_basedata_iter($iter);
        }
    }
    $self->call_selection_callbacks( 'basedata', $basedata_ref );

    return;
}

sub select_base_data_iter {
    my $self = shift;
    my $iter = shift;

    my $basedata_ref =
      $self->{models}{basedata_model}->get( $iter, MODEL_OBJECT );
    $self->select_base_data($basedata_ref);

    return;
}

sub select_matrix {
    my $self       = shift;
    my $matrix_ref = shift;

    $self->set_param( SELECTED_MATRIX => $matrix_ref );

    if ($matrix_ref) {
        Biodiverse::GUI::GUIManager->instance->set_matrix_iter(
            $self->{iters}{matrix_iters}{$matrix_ref} );
        $self->set_matrix_buttons(1);
    }
    elsif ( $self->{iters}{matrix_none} ) {
        Biodiverse::GUI::GUIManager->instance->set_matrix_iter(
            $self->{iters}{matrix_none} );
        $self->set_matrix_buttons(0);
    }
    $self->call_selection_callbacks( matrix => $matrix_ref );

    return;
}

sub select_matrix_iter {
    my $self = shift;
    my $iter = shift;

    my $matrix_ref = $self->{models}{matrix_model}->get( $iter, 1 );
    $self->select_matrix($matrix_ref);

    return;
}

sub select_phylogeny {
    my $self          = shift;
    my $phylogeny_ref = shift;

    $self->set_param( 'SELECTED_PHYLOGENY', $phylogeny_ref );

    if ($phylogeny_ref) {
        Biodiverse::GUI::GUIManager->instance->set_phylogeny_iter(
            $self->{iters}{phylogeny_iters}{$phylogeny_ref} );
        $self->set_phylogeny_buttons(1);
    }
    elsif ( $self->{iters}{phylogeny_none} ) {
        Biodiverse::GUI::GUIManager->instance->set_phylogeny_iter(
            $self->{iters}{phylogeny_none} );
        $self->set_phylogeny_buttons(0);
    }
    $self->call_selection_callbacks( 'phylogeny', $phylogeny_ref );

    return;
}

sub select_phylogeny_iter {
    my $self = shift;
    my $iter = shift;

    my $phylogeny_ref = $self->{models}{phylogeny_model}->get( $iter, 1 );
    $self->select_phylogeny($phylogeny_ref);

    return;
}

sub delete_base_data {
    my ($self, $bd) = @_;
    $bd ||= $self->get_selected_base_data;

    #  drop out if nothing here
    return 0 if !$bd;

    $self->delete_all_basedata_outputs($bd);

    # Remove from basedata list
    my $bd_array = $self->{BASEDATA};    #  use a ref to make reading easier
    my $found;
    foreach my $i ( 0 .. $#$bd_array ) {
        if ( $bd_array->[$i] eq $bd ) {
            splice( @$bd_array, $i, 1 );
            $found++;
            last;
        }
    }
    warn 'Basedata not found' if !$found;

    # $self->basedata_output_model_init;

    #  Go searching for the basedata ref.
    #  We used to use the stored iter but it segfaults under gtk3
    #  so work with a fresh one.
    my $model = $self->{models}{basedata_output_model};

    #  We need to clear and then rebuild the basedata model
    #  or we get seg faults.
    #  Possibly due to getting out of synch somewhere.
    $self->clear_bd_filter_model;

    my $iter = $model->get_iter_first;
    while ($iter) {
        my $ref = $model->get($iter, MODEL_OBJECT);
        if ($ref == $bd) {
            delete $self->{iters}{basedata_iters}{$bd};
            $model->remove($iter);
            last;
        }
        last if !$model->iter_next($iter);
    }
    $self->init_bd_filter_model;

    $self->manage_empty_basedatas();

    # Clear selection
    my $selected = $self->get_selected_base_data;
    if ( !defined $selected or $bd eq $selected ) {
        $self->set_param( SELECTED_BASEDATA => undef );

        #print "CLEARED SELECTED_BASEDATA\n";
    }

    #  clear its outputs
    #$basedata_ref->delete_all_outputs if defined $basedata_ref;

    # Select the first one remaining
    my $basedata_list = $self->get_base_data_list;
    my $first         = $basedata_list->[0];
    if ( defined $first ) {

        #print "[Project] Selecting basedata $first\n";
        $self->select_base_data($first);
    }
    $self->set_dirty();

    #  this is pretty underhanded, but it is not being freed somewhere
    #   so we will empty it instead to reduce the footprint
    #$basedata_ref->DESTROY;

#$self->dump_to_yaml (filename => 'circle3.yml', data => $self->get_base_data_list)

    return;
}

sub rename_base_data {

    #return;  #  TEMP TEMP

    my $self = shift;
    my $name = shift;    #TEMP TEMP ARG

    my $basedata_ref =
         shift
      || $self->get_selected_base_data()
      || return;         #  drop out if nothing here

    $basedata_ref->rename( name => $name );

    # Rename in model
    my $model = $self->{models}{basedata_output_model};
    my $iter = $model->get_iter_first;
    while ($iter) {
        my $ref = $model->get($iter, MODEL_OBJECT);
        if ($ref == $basedata_ref) {
            $model->set ($iter, 0, $name);
            last;
        }
        last if !$model->iter_next($iter);
    }

    $self->set_dirty();

    return;
}

sub rename_matrix {
    my $self = shift;
    my $name = shift;    #TEMP TEMP ARG
    my $ref =
         shift
      || $self->get_selected_matrix()
      || return;         #  drop out if nothing here

    $ref->rename_object( name => $name );

    # Rename in model
    if ( exists $self->{iters}{matrix_iters}{$ref} ) {
        my $iter = $self->{iters}{matrix_iters}{$ref};
        if ( defined $iter ) {
            my $model = $self->{models}{matrix_model};
            $model->set ( $iter, 0, $name );
        }
    }

    $self->set_dirty();

    return;
}

sub rename_phylogeny {

    #return;  #  TEMP TEMP

    my $self = shift;
    my $name = shift;    #TEMP TEMP ARG

    my $ref =
         shift
      || $self->get_selected_phylogeny()
      || return;         #  drop out if nothing here

    $ref->rename_object( name => $name );

    # Rename in model
    if ( exists $self->{iters}{phylogeny_iters}{$ref} ) {
        my $iter = $self->{iters}{phylogeny_iters}{$ref};
        if ( defined $iter ) {
            my $model = $self->{models}{phylogeny_model};
            $model->set ( $iter, 0, $name );
        }
    }

    $self->set_dirty();

    return;
}

sub delete_matrix {
    my $self = shift;
    my $matrix_ref = shift || $self->get_selected_matrix();

    # Clear selection
    my $selected = $self->get_selected_matrix;
    if ( $matrix_ref eq $selected ) {
        $self->set_param( 'SELECTED_MATRIX', undef );

        #print "CLEARED SELECTED_MATRIX\n";
    }

    # Remove from list
    foreach my $i ( 0 .. $#{ $self->{MATRICES} } ) {
        if ( $self->{MATRICES}[$i] eq $matrix_ref ) {
            splice( @{ $self->{MATRICES} }, $i, 1 );
            last;
        }
    }

    # Remove from model
    my $iter = $self->{iters}{matrix_iters}{$matrix_ref};
    if ( defined $iter ) {
        my $model = $self->{models}{matrix_model};
        $model->remove($iter);
        delete $self->{iters}{matrix_iters}{$matrix_ref};
    }
    $self->manage_empty_matrices();

    # Select the first one remaining
    my $first = @{ $self->get_matrix_list }[0];
    if ($first) {

        #print "[Project] Selecting matrix $first\n";
        $self->select_matrix($first);
    }

    $self->set_dirty();
}

sub delete_phylogeny {
    my $self = shift;
    my $phylogeny_ref = shift || $self->get_selected_phylogeny();

    # Clear selection
    my $selected = $self->get_selected_phylogeny;
    if ( $phylogeny_ref eq $selected ) {
        $self->set_param( 'SELECTED_PHYLOGENY', undef );

        #print "CLEARED SELECTED_PHYLOGENY $selected\n";
    }

    # Remove from list
    foreach my $i ( 0 .. $#{ $self->{PHYLOGENIES} } ) {
        if ( $self->{PHYLOGENIES}[$i] eq $phylogeny_ref ) {
            splice( @{ $self->{PHYLOGENIES} }, $i, 1 );
            last;
        }
    }

    # Remove from model
    my $iter = $self->{iters}{phylogeny_iters}{$phylogeny_ref};
    if ( defined $iter ) {
        my $model = $self->{models}{phylogeny_model};
        $model->remove($iter);
        delete $self->{iters}{phylogeny_iters}{$phylogeny_ref};
    }
    $self->manage_empty_phylogenies();

    # Select the first one remaining
    my $first = @{ $self->get_phylogeny_list }[0];
    if ($first) {

        #print "[Project] Selecting phylogeny $first\n";
        $self->select_phylogeny($first);
    }

    $self->set_dirty();
}

sub delete_output {
    my $self       = shift;
    my $output_ref = shift;

    # Remove from model
    my $iter = $self->{iters}{output_iters}{$output_ref};
    if ( defined $iter ) {
        my $model = $self->{models}{basedata_output_model};
        $model->remove($iter);
        delete $self->{iters}{output_iters}{$output_ref};

        $self->set_dirty();
    }

    return;
}

#  should probably be called set name or update name, as we assume it is already renamed
#  actually, we already have update_output_name which is very similar code
sub rename_output {
    my $self       = shift;
    my $output_ref = shift;
    my $name       = $output_ref->get_param('NAME');

    my $iter = $self->{iters}{output_iters}{$output_ref};
    if ( defined $iter ) {
        my $model = $self->{models}{basedata_output_model};
        $model->set_value( $iter, MODEL_OUTPUT, $name );

        $self->set_dirty();
    }

    return;
}

#  go through and clean them all up.
sub delete_all_basedata_outputs {
    my $self = shift;
    my $bd = shift || $self->get_selected_base_data || return 0;

    foreach my $output_ref ( $bd->get_output_refs ) {
        $self->delete_output($output_ref);
    }

    return;
}

# Make an output known to the Outputs tab so that it
# can switch to this tab if the user presses "Show"

sub register_in_outputs_model {
    my $self   = shift;
    my $object = shift;
    my $tabref = shift;    # either the relevant tab, or undef to deregister
    my $model = $self->get_base_data_output_model();

    # Find iter
    my $iter;
    my $iter_base = $model->get_iter_first();

    while ($iter_base) {

        my $iter_output = $model->iter_children($iter_base);
        while ($iter_output) {
            if ( $model->get( $iter_output, MODEL_OBJECT ) eq $object ) {
                $iter = $iter_output;
                last
                  ; #FIXME: do we have to look at other iter_bases, or does this iterate over entire level?
            }

            last if !$model->iter_next($iter_output);
        }

        last if $iter;    # break if found it
        last if !$model->iter_next($iter_base);
    }

    if ($iter) {
        $model->set( $iter, MODEL_TAB, $tabref );
        $self->{current_registration} = $object;
    }

    return;
}

####################################################
# Selection changed callbacks
####################################################
sub register_selection_callback {
    my $self    = shift;
    my $type    = shift;    # basedata / matrix / phylogeny
    my $closure = shift;

    if ( not exists $self->{callbacks}{$type} ) {
        $self->{callbacks}{$type} = {};
    }

    my $hash = $self->{callbacks}{$type};
    $hash->{$closure} = $closure;

    return;
}

sub delete_selection_callback {
    my $self    = shift;
    my $type    = shift;    # basedata / matrix / phylogeny
    my $closure = shift;

    my $hash = $self->{callbacks}{$type};
    if ( $hash && $closure ) {
        delete $hash->{$closure};
    }

    return;
}

sub call_selection_callbacks {
    my $self = shift;
    my $type = shift;    # basedata / matrix / phylogeny
    my @args = @_;

    my $hash = $self->{callbacks}{$type};

    return if !$hash;

    foreach my $callback ( values %$hash ) {
        $callback->(@args);
    }

    return;
}

####################################################
# Misc get functions
####################################################
sub get_base_data_list {
    my $self = shift;
    return $self->{BASEDATA};
}

sub get_matrix_list {
    my $self = shift;
    return $self->{MATRICES};
}

sub get_phylogeny_list {
    my $self = shift;
    return $self->{PHYLOGENIES};
}

sub get_selected_matrix {
    my $self = shift;
    return $self->get_param('SELECTED_MATRIX');
}

sub get_selected_phylogeny {
    my $self = shift;
    return $self->get_param('SELECTED_PHYLOGENY');
}

sub get_selected_basedata {
    my $self = shift;
    return $self->get_selected_base_data;
}

sub get_selected_base_data {
    my $self = shift;
    return $self->get_param('SELECTED_BASEDATA');
}

sub get_output_iter {
    my $self       = shift;
    my $output_ref = shift;

    return $self->{iters}{output_iters}{$output_ref};
}

sub get_base_data_iter {
    my $self = shift;
    my $ref  = shift;
    return if not defined $ref;

    my $iter = $self->{iters}{basedata_iters}{$ref};
    return if not defined $iter;

    # $iter is from basedata-output model
    # Make it relative to the filtered basedata model
    $iter = $self->{models}{basedata_model}->convert_child_iter_to_iter($iter);
    return $iter;
}

sub get_selected_base_data_iter {
    my $self = shift;
    my $ref  = $self->get_selected_base_data();
    return if not defined $ref;

    my $iter = $self->{iters}{basedata_iters}{$ref};
    return if not defined $iter;

    # $iter is from basedata-output model
    # Make it relative to the filtered basedata model
    $iter = $self->{models}{basedata_model}->convert_child_iter_to_iter($iter);
    return $iter;
}

sub get_selected_matrix_iter {
    my $self = shift;
    my $ref  = $self->get_selected_matrix();
    return if not defined $ref;

    return $self->{iters}{matrix_iters}{$ref};
}

sub get_selected_phylogeny_iter {
    my $self = shift;
    my $ref  = $self->get_selected_phylogeny();
    return if not defined $ref;

    return $self->{iters}{phylogeny_iters}{$ref};
}

sub get_available_phylogeny_count {
    my $self = shift;

    my $phylogenies = $self->{PHYLOGENIES} // [];

    return scalar @$phylogenies;
}

# Handles the case of empty basedata/matrix models
#   adds or removes the "(none)" rows
#   selects (none) row if added one
#   disables/enables a list of buttons
sub manage_empty_model {
    my $self = shift;
    my %args = @_;

    my $model      = $args{model}   // croak 'badness';
    my $button_IDs = $args{widgets} // croak 'badness';
    my $type       = $args{type}    // croak 'badness';

    my ( $sensitive, $iter );
    my $first = $model->get_iter_first();

    # If model is empty
    if ( not defined $first ) {

        # Make a dummy model with "(none)"
        say "[Project] $type Model empty";

        $model = Gtk3::ListStore->new('Glib::String');
        $iter  = $model->append;
        $model->set( $iter, 0, '(none)' );

        # Select it
        my $method = 'set_' . $type . '_model';
        eval { Biodiverse::GUI::GUIManager->instance->$method($model); };
        warn $@ if $@;

        $method = 'set_' . $type . '_iter';
        eval { Biodiverse::GUI::GUIManager->instance->$method($iter); };
        warn $@ if $@;

        $sensitive = 0;
    }
    else {
        # Restore original model
        my $method = 'set_' . $type . '_model';
        eval { Biodiverse::GUI::GUIManager->instance->$method($model); };
        warn $@ if $@;

        $sensitive = 1;
    }

    # enable/disable buttons
    my $instance = Biodiverse::GUI::GUIManager->instance;
    foreach (@$button_IDs) {
        my $widget = $instance->get_object($_);
        warn "Widget $_ not found\n" if !defined $widget;
        next if !defined $widget;
        $widget->set_sensitive($sensitive);
    }
}

sub manage_empty_basedatas {
    my $self  = shift;
    my $model = $self->{models}{basedata_model};
    my $list  = [
        qw /
          btnBasedataDelete
          btnBasedataSave
          menu_basedata_delete
          menu_basedata_save
          menu_basedata_duplicate
          menu_basedata_duplicate_no_outputs
          menu_basedata_reduce_axis_resolutions
          menu_basedata_transpose
          menu_basedata_rename
          menu_basedata_describe
          menu_basedata_convert_labels_to_phylogeny
          menu_basedata_export_groups
          menu_basedata_export_labels
          menu_run_exclusions
          menu_view_labels
          menu_spatial
          menu_cluster
          menu_randomisation
          menu_regiongrower
          menu_index
          menu_basedata_auto_remap
          menu_delete_index
          menu_extract_embedded_trees
          menu_extract_embedded_matrices
          menu_trim_basedata_to_match_tree
          menu_trim_basedata_using_object
          menu_rename_basedata_labels
          menu_rename_basedata_groups
          menu_attach_basedata_properties
          menu_attach_basedata_group_properties_from_rasters
          menu_delete_element_properties
          menu_basedata_reorder_axes
          menu_basedata_drop_axes
          menu_binarise_basedata_elements
          menu_attach_ranges_as_properties
          menu_attach_abundances_as_properties
          menu_merge_basedatas
          /
    ];
    $self->manage_empty_model(
        model   => $model,
        widgets => $list,
        type    => 'basedata'
    );
    return;
}

sub manage_empty_matrices {
    my $self      = shift;
    my $sensitive = 1;

    if ( scalar( keys %{ $self->{iters}{matrix_iters} } ) == 0 ) {

        # (there are no matrix objects)
        $sensitive = 0;

        # make sure (none) is selected
        $self->select_matrix(undef);
    }

    $self->set_matrix_buttons($sensitive);

    return;
}

sub manage_empty_phylogenies {
    my $self      = shift;
    my $sensitive = 1;

    if ( scalar( keys %{ $self->{iters}{phylogeny_iters} } ) == 0 ) {

        # (there are no matrix objects)
        $sensitive = 0;

        # make sure (none) is selected
        $self->select_phylogeny(undef);
    }

    $self->set_phylogeny_buttons($sensitive);

    return;
}

# enable/disable buttons
sub set_matrix_buttons {
    my ( $self, $sensitive ) = @_;

    my $instance = Biodiverse::GUI::GUIManager->instance;
    foreach (
        qw /
        btnMatrixDelete
        btnMatrixSave
        menu_matrix_delete
        menu_matrix_save
        menu_matrix_rename
        menu_matrix_auto_remap
        menu_matrix_describe
        menu_matrix_export
        menu_trim_matrix_to_basedata
        convert_matrix_to_phylogeny
        /
      )
    {
        $instance->get_object($_)->set_sensitive($sensitive);
    }
}

# enable/disable buttons
# Really need to loop through the menu and operate on all but import and open
sub set_phylogeny_buttons {
    my ( $self, $sensitive ) = @_;

    my $instance = Biodiverse::GUI::GUIManager->instance;
    foreach (
        qw /
        btnPhylogenyDelete
        btnPhylogenySave
        menu_phylogeny_delete
        menu_phylogeny_save
        menu_phylogeny_rename
        menu_phylogeny_auto_remap
        menu_phylogeny_describe
        menu_convert_phylogeny_to_matrix
        menu_trim_tree_to_basedata
        menu_trim_tree_to_lca
        menu_merge_tree_knuckle_nodes
        menu_phylogeny_export
        menu_phylogeny_delete_cached_values
        menu_range_weight_tree_branches
        menu_equalise_tree_branches
        menu_rescale_tree_branches2
        menu_ladderise_tree
        /
      )
    {
        $instance->get_object($_)->set_sensitive($sensitive);
    }
}

# Makes a new name like "Ferns_Spatial3" which isn't already used (up to 1000)
sub make_new_output_name {
    my $self       = shift;
    my $source_ref = shift;    # BaseData object used to generate output
    my $type       = shift;    # eg: "Spatial"

    my @outputs = keys %{ $self->{iters}{output_iters} };
    @outputs = map { $_->get_param('NAME') } @outputs;

    my $source_name = $source_ref->get_param('NAME');
    my $prefix      = $source_name . "_" . $type;
    my $name;

    my $i = 0;
    while (1) {
        $name = $prefix . $i;
        last if !$self->member_of( $name, \@outputs );
        $i++;
        if ( $i > 1000 ) {
            $i = rand();    #  don't waste any more time
        }
    }

    return $name;
}

# Returns whether an element is in some array-ref
sub member_of {
    my ( $self, $elem, $array ) = @_;
    foreach my $member (@$array) {
        return 1 if $elem eq $member;
    }
    return 0;
}

# Get array of output refs for this basedata
# We could get them direct from the basedata object,
# but this keeps things in the same order as the rest
# of the GUI.
sub get_basedata_outputs {
    my $self = shift;
    my $ref = shift;

    return if !defined $ref;

    my $iter = $self->{iters}{basedata_iters}{$ref};
    my $model = $self->{models}{basedata_output_model};

    my $n_children = $model->iter_n_children($iter);
    my @arr;
    for my $i (0 .. $n_children - 1) {
        my $child_iter = $model->iter_nth_child($iter, $i);
        push @arr, $model->get($child_iter, MODEL_OBJECT);
    }

    return wantarray ? @arr : \@arr;
}

####################################################
# Overlays
####################################################

# We store the filenames in $self->{OVERLAYS}
# and the Geo::Shapelibs in $self->{overlay_objects}
# (which we don't want to save)

sub get_overlay_list {
    my $self = shift;
    return $self->{OVERLAYS};
}

sub overlay_is_valid {
    my ($self, %args) = @_;
    my $shapefile = $args{shapefile};

    croak 'shapefile arg undefined'
        if !defined $shapefile;

    my $overlays = $self->get_overlay_list;
    my @possibles
        = grep {$shapefile->{filebase} eq ($_->{name} =~ s/.shp$//r)}
          grep {$_->{plot_on_top} == $args{plot_on_top}}
          grep {$_->{type} eq $args{type}}
          @$overlays;

    return !!@possibles;
}

sub get_overlay_shape_object {
    my $self = shift;
    my $name = shift;

    if ( not defined $self->{overlay_objects}{$name} ) {

        say "[Project] Loading geospatial data";
        use Biodiverse::GUI::Overlays::Data;
        my $ggf = Biodiverse::GUI::Overlays::Data->new ($name);
        $ggf->load_data (defer_loading => 1);

        $self->{overlay_objects}{$name} = $ggf;
    }

    return $self->{overlay_objects}{$name};
}

sub delete_overlay {
    my ($self, $name, $array_iter) = @_;

    my $overlays = $self->{OVERLAYS};

    $name = path ($name);

    # Remove from list unless not found or possible
    $array_iter //= List::Util::first {path ($_) eq $name} @$overlays;
    return if $array_iter < 0 || $array_iter > $#$overlays;

    splice( @$overlays, $array_iter, 1 );

    # remove from hash if no longer needed
    if (!grep {path ($_->{name}) eq $name} @$overlays) {
        delete $self->{overlay_objects}{$name};
    }

    return;
}

sub add_overlay {
    my ($self, $entry) = @_;

    my $name = $entry->{name};

    $self->{overlay_objects}{$name} = undef;
    push @{ $self->{OVERLAYS} }, $entry;

    return;
}

sub update_overlay {
    my ($self, $iter, $data) = @_;

    my $array = $self->{OVERLAYS};
    return if abs ($iter) >= @$array;

    my $entry = $array->[$iter];
    @$entry{keys %$data} = values %$data;

    return;
}

# Called on startup - after engine loaded from file
sub init_overlay_hash {
    my $self = shift;

    my @existing_overlays;
    my @missing_overlays;

    foreach my $entry ( @{ $self->{OVERLAYS} } ) {
        #  older projects just stored the name
        my $name = is_hashref $entry ? $entry->{name} : $entry;
        my $db = path ($name)->parent;
        if ($db !~ m{\.(gpkg|gdb)}) {
            $db = $name;  #  shapefiles are not in databases
        }

        if ( Biodiverse::Common->file_is_readable (file_name => $db) ) {
            # Set hash entry to undef - will load on demand
            $self->{overlay_objects}{$name} = undef;
            push @existing_overlays, $entry;
        }
        else {
            say "[Project] Missing overlay: $name";
            push @missing_overlays, $name;
        }
    }

    # Replace list with available overlays
    $self->{OVERLAYS} = \@existing_overlays;

    # Tell user if any missing
    if ( scalar @missing_overlays > 0 ) {
        my $text =
"The following overlays are missing and have been removed from the project:\n";
        foreach my $name (@missing_overlays) {
            $text .= "  $name\n";
        }

        my $dialog = Gtk3::MessageDialog->new(
            undef, 'destroy-with-parent', 'warning',
            'ok', $text,
        );
        my $response = $dialog->run;
        $dialog->destroy;
    }

    return;
}

1;
