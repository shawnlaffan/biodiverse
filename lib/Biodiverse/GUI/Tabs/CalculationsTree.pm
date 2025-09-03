=head1 NAME

Analysis Tree

=head1 SYNOPSIS

Manages the tree that is used to select what spatial
analyses to perform in the Spatial and Clustering tabs

=cut

package Biodiverse::GUI::Tabs::CalculationsTree;
use strict;
use warnings;

use Gtk3;
use Biodiverse::GUI::GUIManager;
use Biodiverse::Indices;
use Ref::Util qw { :all };
use Text::Wrapper;

our $VERSION = '4.99_011';

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

my $NAME_COLUMN_WIDTH = 26;
my $DESC_COLUMN_WIDTH = 90;


#use Smart::Comments;

sub init_calculations_tree {
    my $tree  = shift;
    my $model = shift;
    
    # First column - name/type with a checkbox
    my $col_name       = Gtk3::TreeViewColumn->new();
    my $check_renderer = Gtk3::CellRendererToggle->new();
    my $name_renderer  = Gtk3::CellRendererText->new();
    $check_renderer->signal_connect_swapped(toggled => \&on_calculation_toggled, $model);

    $col_name->pack_start($check_renderer, 0);
    $col_name->pack_start($name_renderer,  1);
    $col_name->add_attribute($check_renderer, active       => MODEL_CHECKED_COL);
    $col_name->add_attribute($check_renderer, inconsistent => MODEL_GRAYED_COL);
    $col_name->add_attribute($check_renderer, visible      => MODEL_SHOW_CHECKBOX);
    $col_name->add_attribute($name_renderer,  text         => MODEL_NAME_COL);

    my $col_index = Gtk3::TreeViewColumn->new();
    my $index_renderer = Gtk3::CellRendererText->new();
    #$index_renderer->set('wrap-mode' => 'word');  #  no effect?
    $col_index->pack_start($index_renderer, 1);
    $col_index->add_attribute($index_renderer, markup => MODEL_INDEX_COL);

    
    my $col_desc = Gtk3::TreeViewColumn->new();
    my $desc_renderer = Gtk3::CellRendererText->new();
    $col_desc->pack_start($desc_renderer, 1);
    $col_desc->add_attribute($desc_renderer, markup => MODEL_DESCRIPTION_COL);
    
    $tree->insert_column($col_name,  -1);
    $tree->insert_column($col_index, -1);
    $tree->insert_column($col_desc,  -1);
    $tree->set_headers_visible(0);
    $tree->set_model( $model );
    
    $tree->signal_connect_swapped('row-collapsed' => \&on_row_collapsed, $tree);

    #  set vertical alignment of cells
    foreach my $renderer (
        $desc_renderer,
        $index_renderer,
        #$name_renderer,
        #$check_renderer
        ) {
        $renderer->set (yalign => 0);
    }
    
    return;
}

#  resize the contents - this reclaims unused horizontal space 
sub on_row_collapsed {
    my $tree = shift;
    
    $tree->columns_autosize();
    
    return;
}

# Creates a TreeView model of available calculations
sub make_calculations_model {
    my $base_ref   = shift;
    my $output_ref = shift;

    # Try to get a list of analyses that should be checked
    my $check_ref;
    if ($output_ref) {  #  the latter are for backwards compatibility
        $check_ref =    $output_ref->get_param('CALCULATIONS_REQUESTED')
                    or $output_ref->get_param('ANALYSES_REQUESTED')
                    or $output_ref->get_param('ANALYSES_RAN');
    }
    if (! defined $check_ref) {
        $check_ref = [$EMPTY_STRING] ;  # trap other cases
    }

    #print "[Spatial tab] Analyses ran - " . join (" ", @$check_ref) . "\n" if scalar @$check_ref;

    my @treestore_args = (
        'Glib::String',         # Name
        'Glib::String',         # Index
        'Glib::String',         # Description
        'Glib::String',         # Function
        'Glib::Boolean',        # Checked?
        'Glib::Boolean',        # Grayed? (if some children checked but not all)
        'Glib::Boolean',        # Show checkbox? (no if description "second line")
    );
    
    my $model = Gtk3::TreeStore->new( @treestore_args );
    
    #my $analysis_caller_ref = defined $output_ref ? $output_ref : $base_ref;
    #my %calculations = $analysis_caller_ref->get_calculations;
    my $indices = Biodiverse::Indices->new(BASEDATA_REF => $base_ref);
    my %calculations = $indices->get_calculations;

    # my $name_wrapper = Text::Wrapper->new(columns => $NAME_COLUMN_WIDTH);
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

        my (%calc_metadata, %funcs_and_names);
        foreach my $func (@{$calculations{$type}}) {
            my $info = $indices->get_metadata (sub => $func);
            # If name unspecified then use the function name less the calc_
            my $name = $func;
            $name =~ s/^calc_//;
            $name = $info->get_name || $name;
            #$info->{func} = $func;  #  DIRTY HACK
            $calc_metadata{$func}   = $info;
            $funcs_and_names{$func} = $name;
        }

        my @sorted_funcs = sort {$funcs_and_names{$a} cmp $funcs_and_names{$b}} keys %funcs_and_names;

        # Add each analysis-function (eg: Jaccard, Endemism) row
        CALCULATION_NAME:
        foreach my $func (@sorted_funcs) {
            my $info = $calc_metadata{$func};
            my $name = $info->get_name;

            # If description goes over one line,
            # we put the first line here and the next into a new row
            # but combine all the other lines into a single line and then rewrap.
            my $desc = $info->get_description || $EMPTY_STRING;
            my ($d1, $d_rest) = split(/\n/, $desc, 2);

            #  Rewrap the descriptions.
            #  Perl works on aliases so this will change the original strings.
            foreach my $string ($d1, $d_rest) {
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
            my %descr_hash = $info->get_index_description_hash;
            foreach my $index (sort keys %descr_hash) {
                my $description = $descr_hash{$index} || $EMPTY_STRING;
                $description =~ s/\n//g;  #  strip newlines
                $description = $desc_wrapper->wrap($description);
                $description =~ s/\n\z//;  #  strip trailing newlines
                #my @string = split ("\n", $description);

                push @index_data, [$index, $description];
            }
            if (!scalar keys %descr_hash) {
                if ($d_rest) {
                    $d_rest .= "\n";
                }
                $d_rest .= "<i>This calculation will generate no indices for this basedata</i>";
            }

            # Should it be checked? (yes, if it was on previous time)
            my $checked = member_of($func, $check_ref);

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
            if ($d_rest) {
                my $desc_iter = $model->append($func_iter);
                $model->set(
                    $desc_iter,
                    MODEL_DESCRIPTION_COL, $d_rest,
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
        update_type_checkbox($model, $type_iter);
    }

    return $model;
}

# Returns whether an element is in some array-ref
sub member_of {
    my ($elem, $ref) = @_;

    #  sometimes we are passed a hash
    return exists $ref->{$elem}
      if is_hashref($ref);

    foreach my $member (@$ref) {
        return 1 if $elem eq $member;
    }

    return 0;
}

sub get_calculations_to_run {
    my $model = shift;
    my @to_run;

    # Retrieve all calculations with a check mark
    my $type_iter = $model->get_iter_first();
    while ($type_iter) {

        my $child_iter = $model->iter_nth_child($type_iter, 0);

        while ($child_iter) {
            my ($checked) = $model->get($child_iter, MODEL_CHECKED_COL);
            if ($checked) {
                my ($func) = $model->get($child_iter, MODEL_FUNCTION_COL);
                push (@to_run, $func);
            }
            last if !$model->iter_next($child_iter);
        }

        last if !$model->iter_next($type_iter);
    }
    return @to_run;
}

# Called to set the analysis type checkbox depending on whether all children are set
sub update_type_checkbox {
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
        last if !$model->iter_next($child_iter);
    }

    $check = 0 if $gray == 1;

    $model->set($iter_top, MODEL_GRAYED_COL, $gray);
    $model->set($iter_top, MODEL_CHECKED_COL, $check);
}

# Called when the user clicks on a checkbox
sub on_calculation_toggled {
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
        last if !$model->iter_next($child_iter);
    }

    # update state of any parent
    update_type_checkbox($model, $model->iter_parent($iter) );

    return;
}


1;

