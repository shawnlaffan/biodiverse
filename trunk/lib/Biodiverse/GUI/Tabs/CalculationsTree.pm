=head1 NAME

Analysis Tree

=head1 SYNOPSIS

Manages the tree that is used to select what spatial
analyses to perform in the Spatial and Clustering tabs

=cut

package Biodiverse::GUI::Tabs::CalculationsTree;
use strict;
use warnings;

use Scalar::Util qw /reftype/;

use Gtk2;
use Biodiverse::GUI::GUIManager;
use Biodiverse::Indices;

use Text::Wrapper;

our $VERSION = '0.18_006';

#use Readonly;
my $i;
use constant MODEL_NAME_COL        =>   $i || 0;
use constant MODEL_INDEX_COL       => ++$i;
use constant MODEL_DESCRIPTION_COL => ++$i;
use constant MODEL_FUNCTION_COL    => ++$i;
use constant MODEL_CHECKED_COL     => ++$i;
use constant MODEL_GRAYED_COL      => ++$i;
use constant MODEL_SHOW_CHECKBOX   => ++$i;

#print MODEL_NAME_COL, MODEL_DESCRIPTION_COL, MODEL_FUNCTION_COL;

my $EMPTY_STRING = q{};
my $SPACE        = q{ };

my $NAME_COLUMN_WIDTH = 26;
my $DESC_COLUMN_WIDTH = 90;


#use Smart::Comments;

sub initCalculationsTree {
    my $tree  = shift;
    my $model = shift;
    
    # First column - name/type with a checkbox
    my $colName       = Gtk2::TreeViewColumn->new();
    my $checkRenderer = Gtk2::CellRendererToggle->new();
    my $nameRenderer  = Gtk2::CellRendererText->new();
    $checkRenderer->signal_connect_swapped(toggled => \&onCalculationToggled, $model);

    $colName->pack_start($checkRenderer, 0);
    $colName->pack_start($nameRenderer,  1);
    $colName->add_attribute($checkRenderer, active       => MODEL_CHECKED_COL);
    $colName->add_attribute($checkRenderer, inconsistent => MODEL_GRAYED_COL);
    $colName->add_attribute($checkRenderer, visible      => MODEL_SHOW_CHECKBOX);
    $colName->add_attribute($nameRenderer,  text         => MODEL_NAME_COL);

    my $colIndex = Gtk2::TreeViewColumn->new();
    my $indexRenderer = Gtk2::CellRendererText->new();
    #$indexRenderer->set('wrap-mode' => 'word');  #  no effect?
    $colIndex->pack_start($indexRenderer, 1);
    $colIndex->add_attribute($indexRenderer, markup => MODEL_INDEX_COL);

    
    my $colDesc = Gtk2::TreeViewColumn->new();
    my $descRenderer = Gtk2::CellRendererText->new();
    $colDesc->pack_start($descRenderer, 1);
    $colDesc->add_attribute($descRenderer, markup => MODEL_DESCRIPTION_COL);
    
    $tree->insert_column($colName,  -1);
    $tree->insert_column($colIndex, -1);
    $tree->insert_column($colDesc,  -1);
    $tree->set_headers_visible(0);
    $tree->set_model( $model );
    
    $tree->signal_connect_swapped('row-collapsed' => \&onRowCollapsed, $tree);

    #  set vertical alignment of cells
    foreach my $renderer (
        $descRenderer,
        $indexRenderer,
        #$nameRenderer,
        #$checkRenderer
        ) {
        $renderer->set (yalign => 0);
    }
    
    return;
}

#  resize the contents - this reclaims unused horizontal space 
sub onRowCollapsed {
    my $tree = shift;
    
    $tree->columns_autosize();
    
    return;
}

# Creates a TreeView model of available calculations
sub makeCalculationsModel {
    my $base_ref   = shift;
    my $output_ref = shift;

    # Try to get a list of analyses that should be checked
    my $checkRef;
    if ($output_ref) {  #  the latter are for backwards compatibility
        $checkRef =    $output_ref->get_param('CALCULATIONS_REQUESTED')
                    or $output_ref->get_param('ANALYSES_REQUESTED')
                    or $output_ref->get_param('ANALYSES_RAN');
    }
    if (! defined $checkRef) {
        $checkRef = [$EMPTY_STRING] ;  # trap other cases
    }

    #print "[Spatial tab] Analyses ran - " . join (" ", @$checkRef) . "\n" if scalar @$checkRef;

    my @treestore_args = (
        'Glib::String',         # Name
        'Glib::String',         # Index
        'Glib::String',         # Description
        'Glib::String',         # Function
        'Glib::Boolean',        # Checked?
        'Glib::Boolean',        # Grayed? (if some children checked but not all)
        'Glib::Boolean',        # Show checkbox? (no if description "second line")
    );
    
    my $model = Gtk2::TreeStore->new( @treestore_args );
    
    #my $analysis_caller_ref = defined $output_ref ? $output_ref : $base_ref;
    #my %calculations = $analysis_caller_ref->get_calculations;
    my $indices = Biodiverse::Indices->new(BASEDATA_REF => $base_ref);
    my %calculations = $indices->get_calculations;

    my $name_wrapper = Text::Wrapper->new(columns => $NAME_COLUMN_WIDTH);
    my $desc_wrapper = Text::Wrapper->new(columns => $DESC_COLUMN_WIDTH);

    # Add the type row (eg: taxonomic, matrix) 
    foreach my $type (sort keys %calculations) {
        my $type_iter = $model->append(undef);
        $model->set(
            $type_iter,
            MODEL_NAME_COL,        $type,
            MODEL_CHECKED_COL,     0,
            MODEL_GRAYED_COL,      0,
            MODEL_SHOW_CHECKBOX,   1
        );

        my %calc_metadata;
        foreach my $func (@{$calculations{$type}}) {
            my %info = $indices->get_args (sub => $func);
            # If name unspecified then use the function name less the calc_
            my $name = $func;
            $name =~ s/^calc_//;
            $name = $info{name} || $name;
            $info{func} = $func;
            $calc_metadata{$name} = \%info;
        }

        # Add each analysis-function (eg: Jaccard, Endemism) row
        CALCULATION_NAME:
        foreach my $name (sort keys %calc_metadata) {
            my %info = %{$calc_metadata{$name}};

            # If description goes over one line,
            # we put the first line here and the next into a new row
            # but combine all the other lines into a single line and then rewrap.
            my $desc = $info{description} || $EMPTY_STRING;
            my ($d1, $dRest) = split(/\n/, $desc, 2);

            #  Rewrap the descriptions.
            #  Perl works on aliases so this will change the original strings.
            foreach my $string ($d1, $dRest) {
                next if ! defined $string;
                $string =~ s/\A\n//;
                $string =~ s/\n\z//;
                $string =~ s/\n/ /g;
                $string = $desc_wrapper->wrap($string);
                $string =~ s/\n\z//;
            }

            my @index_data = ();
            push @index_data, ['Indices:', $EMPTY_STRING];

            #  now loop over the indices to get their descriptions
            foreach my $index (sort keys %{$info{indices}}) {
                my $description = $info{indices}{$index}{description} || $EMPTY_STRING;
                $description =~ s/\n//g;  #  strip newlines
                $description = $desc_wrapper->wrap($description);
                $description =~ s/\n\z//;  #  strip trailing newlines
                #my @string = split ("\n", $description);

                push @index_data, [$index, $description];
            }

            my $func = $info{func};

            # Should it be checked? (yes, if it was on previous time)
            my $checked = member_of($func, $checkRef);

            # Add to model
            my $func_iter = $model->append($type_iter);
            $model->set(
                $func_iter,
                MODEL_NAME_COL,            $name,
                MODEL_CHECKED_COL,         $checked,
                MODEL_GRAYED_COL,          0,
                MODEL_DESCRIPTION_COL,     $d1,
                MODEL_FUNCTION_COL,        $func,
                MODEL_SHOW_CHECKBOX,       1
            );

            # Add multiline-description row
            if ($dRest) {
                my $desc_iter = $model->append($func_iter);
                $model->set(
                    $desc_iter,
                    MODEL_DESCRIPTION_COL, $dRest,
                    MODEL_SHOW_CHECKBOX,   0,
                );
            }
            
            #  add index descriptions
            foreach my $index_pair (@index_data) {
                my $index_iter = $model->append($func_iter);
                $model->set(
                    $index_iter,
                    MODEL_INDEX_COL,       $index_pair->[0],
                    MODEL_DESCRIPTION_COL, $index_pair->[1],
                    MODEL_SHOW_CHECKBOX,   0,
                );
            }
        }

        # Check it if all calculations are checked
        updateTypeCheckbox($model, $type_iter);
    }

    return $model;
}

# Returns whether an element is in some array-ref
sub member_of {
    my ($elem, $ref) = @_;

    #  sometimes we are passed a hash
    return exists $ref->{$elem}
      if (reftype ($ref) eq 'HASH');

    foreach my $member (@$ref) {
        return 1 if $elem eq $member;
    }

    return 0;
}

sub getCalculationsToRun {
    my $model = shift;
    my @toRun;

    # Retrieve all calculations with a check mark
    my $type_iter = $model->get_iter_first();
    while ($type_iter) {

        my $child_iter = $model->iter_nth_child($type_iter, 0);

        while ($child_iter) {
            my ($checked) = $model->get($child_iter, MODEL_CHECKED_COL);
            if ($checked) {
                my ($func) = $model->get($child_iter, MODEL_FUNCTION_COL);
                push (@toRun, $func);
            }
            $child_iter = $model->iter_next($child_iter);
        }

        $type_iter = $model->iter_next($type_iter);
    }
    return @toRun;
}

# Called to set the analysis type checkbox depending on whether all children are set
sub updateTypeCheckbox {
    my $model = shift;
    my $iter_top = shift || return;

    my $child_iter = $model->iter_nth_child($iter_top, 0);
    my $prevchecked = undef;
    my $check = 0;
    my $gray = 0; # will be set to 1 if have both checked & unchecked children

    # Look for any unchecked children
    while ($child_iter) {
        ($check) = $model->get($child_iter, MODEL_CHECKED_COL);
        if (defined $prevchecked && $prevchecked != $check) {
            $gray = 1;
            last;
        }
        $prevchecked = $check;
        $child_iter = $model->iter_next($child_iter);
    }

    $check = 0 if $gray == 1;

    $model->set($iter_top, MODEL_GRAYED_COL, $gray);
    $model->set($iter_top, MODEL_CHECKED_COL, $check);
}

# Called when the user clicks on a checkbox
sub onCalculationToggled {
    my $model = shift;
    my $path = shift;
    
    my $iter = $model->get_iter_from_string($path);

    # Flip state
    my $state  = $model->get($iter, MODEL_CHECKED_COL);
    my $grayed = $model->get($iter, MODEL_GRAYED_COL);

    if ($grayed == 1) {
        $state = 1; # if clicked on a grayed checkbox - make it selected
    }
    else {
        $state = not $state;
    }
    $model->set($iter, MODEL_CHECKED_COL, $state);
    $model->set($iter, MODEL_GRAYED_COL, 0);
    
    # Apply state to all child nodes
    my $child_iter = $model->iter_nth_child($iter, 0);
    while ($child_iter) {
        $model->set($child_iter, MODEL_CHECKED_COL, $state);
        $child_iter = $model->iter_next($child_iter);
    }

    # update state of any parent
    updateTypeCheckbox($model, $model->iter_parent($iter) );

    return;
}


1;
