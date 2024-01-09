package Biodiverse::GUI::Dendrogram;

use 5.010;
use strict;
use warnings;
no warnings 'recursion';
#use Data::Dumper;
use Carp;

use Time::HiRes qw /gettimeofday time/;

use Scalar::Util qw /weaken isweak blessed/;
use List::Util 1.29 qw /min pairs/;
use List::MoreUtils qw /firstidx/;

use Gtk2;
use Gnome2::Canvas;
use POSIX qw /ceil/; # for ceil()

our $VERSION = '4.99_001';

use Biodiverse::GUI::GUIManager;
use Biodiverse::TreeNode;
use Biodiverse::Utilities qw/sort_list_with_tree_names_aa/;
use Sort::Key qw/rnkeysort/;

##########################################################
# Rendering constants
##########################################################
use constant BORDER_FRACTION => 0.05; # how much of total-length are the left/right borders (combined!)
use constant BORDER_HT       => 0.025; #  how much of the total number of leaf nodes as a vertical border
use constant SLIDER_WIDTH    => 3; # pixels
use constant LEAF_SPACING    => 1; # arbitrary scale (length will be scaled to fit)

use constant HIGHLIGHT_WIDTH => 2; # width of highlighted horizontal lines (pixels)
use constant NORMAL_WIDTH    => 1;       # width of normal lines (pixels)

use constant COLOUR_BLACK => Gtk2::Gdk::Color->new(0,0,0);
use constant COLOUR_WHITE => Gtk2::Gdk::Color->new(255*257, 255*257, 255*257);
use constant COLOUR_GRAY  => Gtk2::Gdk::Color->new(210*257, 210*257, 210*257);
use constant COLOUR_RED   => Gtk2::Gdk::Color->new(255*257,0,0);

use constant COLOUR_PALETTE_OVERFLOW  => COLOUR_WHITE;
use constant COLOUR_OUTSIDE_SELECTION => COLOUR_WHITE;
use constant COLOUR_NOT_IN_TREE       => COLOUR_BLACK;
use constant COLOUR_LIST_UNDEF        => COLOUR_WHITE;

use constant DEFAULT_LINE_COLOUR      => COLOUR_BLACK;
use constant DEFAULT_LINE_COLOUR_RGB  => "#000000";
use constant DEFAULT_LINE_COLOUR_VERT => Gtk2::Gdk::Color->parse('#7F7F7F');  #  '#4D4D4D'

use constant HOVER_CURSOR => 'hand2';

##########################################################
# Construction
##########################################################

sub new {
    my $class = shift;
    my %args  = @_;

    my $main_frame      = $args{main_frame};  # GTK frame to add dendrogram
    my $graph_frame     = $args{graph_frame}; # GTK frame for the graph (below!)
    my $hscroll         = $args{hscroll};
    my $vscroll         = $args{vscroll};
    my $map             = $args{grid};        # Grid.pm object of the dataset to link in
    my $map_list_combo  = $args{list_combo};  # Combo for selecting how to colour the grid (based on spatial result or cluster)
    my $map_index_combo = $args{index_combo}; # Combo for selecting how to colour the grid (which spatial result)
    my $use_slider_to_select_nodes = !$args{no_use_slider_to_select_nodes};
    my $want_legend = $args{want_legend};

    my $grey = 0.9 * 255 * 257;

    my $self = {
        map                 => $map,
        map_index_combo     => $map_index_combo,
        map_list_combo      => $map_list_combo,
        num_clusters        => 6,
        zoom_fit            => 1,
        dragging            => 0,
        sliding             => 0,
        unscaled_slider_x   => 0,
        group_mode          => 'length',
        width_px            => 0,
        height_px           => 0,
        render_width        => 0,
        render_height       => 0,
        graph_height_px     => 0,
        use_slider_to_select_nodes => $use_slider_to_select_nodes,
        colour_not_in_tree  => Gtk2::Gdk::Color->new($grey, $grey, $grey),
        use_highlight_func  => 1, #  should we highlight?
    };

    #  callback functions 
    $self->{hover_func}      = $args{hover_func};      # when users move mouse over a cell
    $self->{highlight_func}  = $args{highlight_func};  # highlight elements    
    $self->{ctrl_click_func} = $args{ctrl_click_func}; # when users control-click on a cell
    $self->{click_func}      = $args{click_func};      # when users click on a cell
    $self->{select_func}     = $args{select_func};     # when users drag a selection rectangle on the background
    $self->{parent_tab}      = $args{parent_tab};

    if (my $basedata_ref = $args{basedata_ref}) {
        $self->{basedata_ref} = $basedata_ref;
        weaken $self->{basedata_ref};
    }

    if (defined $self->{parent_tab}) {
        weaken $self->{parent_tab} if !isweak ($self->{parent_tab});
        #  fixme
        #  there is too much back-and-forth between the tab and the tree
        $self->{parent_tab}->set_undef_cell_colour(COLOUR_LIST_UNDEF);  
    }


    # starting off with the "clustering" view, not a spatial analysis
    $self->{sp_list}  = undef;
    $self->{sp_index} = undef;
    bless $self, $class;
    
    foreach my $widget_name (qw /selector_toggle selector_colorbutton autoincrement_toggle/) {
        eval {
            #  use get_xmlpage_object from parent
            $self->{$widget_name}
              = $self->get_parent_tab->{xmlPage}->get_object($widget_name);
        };
    }

    #  also initialises it
    $self->increment_multiselect_colour(1);

    #  clean up if we are a refresh
    if (my $child = $main_frame->get_child) {
        $main_frame->remove( $child );
    }
    if (my $child = $graph_frame->get_child) {
        $graph_frame->remove( $child );
    }

    # Make and hook up the canvases
    $self->{canvas} = Gnome2::Canvas->new();
    $self->{graph}  = Gnome2::Canvas->new();
    $main_frame->add( $self->{canvas} );
    $graph_frame->add( $self->{graph} );
    $self->{canvas}->signal_connect_swapped (
        size_allocate => \&on_resize,
        $self,
    );
    $self->{graph}->signal_connect_swapped(
        size_allocate => \&on_graph_resize,
        $self,
    );

    # Set up custom scrollbars due to flicker problems whilst panning..
    $self->{hadjust} = Gtk2::Adjustment->new(0, 0, 1, 1, 1, 1);
    $self->{vadjust} = Gtk2::Adjustment->new(0, 0, 1, 1, 1, 1);

    $hscroll->set_adjustment( $self->{hadjust} );
    $vscroll->set_adjustment( $self->{vadjust} );

    $self->{hadjust}->signal_connect_swapped('value-changed', \&onHScroll, $self);
    $self->{vadjust}->signal_connect_swapped('value-changed', \&onVScroll, $self);

    # Set up canvas
    $self->{canvas}->set_center_scroll_region(0);
    $self->{canvas}->show;
    $self->{graph}->set_center_scroll_region(0);
    $self->{graph}->show;

    $self->{length_scale} = 1;
    $self->{height_scale} = 1;

    # Create background rectangle to receive mouse events for panning
    my $rect = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        y1 => 0,
        x2 => 1,
        y2 => 1,
        fill_color_gdk => COLOUR_WHITE,
        #fill_color => "blue",
        #outline_color_gdk   => COLOUR_BLACK,
    );

    $rect->lower_to_bottom();
    $self->{canvas}->root->signal_connect_swapped (event => \&on_background_event, $self);
    $self->{back_rect} = $rect;

    # Process changes for the map
    if ($map_index_combo) {
        $map_index_combo->signal_connect_swapped(
            changed => \&on_map_index_combo_changed,
            $self,
        );
    }
    if ($map_list_combo) {
        $map_list_combo->signal_connect_swapped (
            changed => \&on_map_list_combo_changed,
            $self
        );
    }
    
    # Create the Label legend if requested
    if ($want_legend) {
        my $legend = Biodiverse::GUI::Legend->new(
            canvas       => $self->{canvas},
            legend_mode  => 'Hue',  #  by default
            width_px     => $self->{width_px},
            height_px    => $self->{height_px},
        );
        #$legend->set_width(15);  # thinnish by default
        $self->set_legend ($legend);
        $self->update_legend;
    }

    $self->{drag_mode} = 'click';

    # Labels::initMatrixGrid will set $self->{page} (hacky}

    return $self;
}


sub get_tree_object {
    my $self = shift;
    return $self->{cluster};
}

sub get_parent_tab {
    my $self = shift;
    return $self->{parent_tab};
}

sub destroy {
    my $self = shift;

    say "[Dendrogram] Trying to clean up references";

    $self->{node_lines} = undef;
    delete $self->{node_lines};

    if ($self->{lines_group}) {
        $self->{lines_group}->destroy();
    }

    delete $self->{slider};

    delete $self->{hover_func}; #??? not sure if helps
    delete $self->{highlight_func}; #??? not sure if helps
    delete $self->{ctrl_click_func}; #??? not sure if helps
    delete $self->{click_func}; #??? not sure if helps

    delete $self->{lines_group}; #!!!! Without this, GnomeCanvas __crashes__
                                # Apparently, a reference cycle prevents it from being destroyed properly,
                                # and a bug makes it repaint in a half-dead state
    delete $self->{back_rect};

    #delete $self->{node_lines};
    delete $self->{canvas};
    delete $self->{graph};

    #  get the rest
    delete @$self{keys %$self};

    return;
}

#  makes it available outside the class
sub get_default_line_colour {
    DEFAULT_LINE_COLOUR();
}

##########################################################
# The Slider
##########################################################

sub make_slider {
    my $self = shift;

    # already exists?
    if ( $self->{slider} ) {
        $self->{slider}->show;
        $self->{graph_slider}->show;
        return;
    }

    $self->{slider} = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        y1 => 0,
        x2 => 1,
        y2 => 1,
        fill_color => 'blue',
    );
    $self->{slider}->signal_connect_swapped (event => \&on_slider_event, $self);

    # Slider for the graph at the bottom
    $self->{graph_slider} = Gnome2::Canvas::Item->new (
        $self->{graph}->root,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        y1 => 0,
        x2 => 1,
        y2 => 1,
        fill_color => 'blue',
    );
    $self->{graph_slider}->signal_connect_swapped (event => \&on_slider_event, $self);

    # Make the #Clusters textbox
    $self->{clusters_group} = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Group',
        x => 0,
        y => 0,
    );
    $self->{clusters_group}->lower_to_bottom();

    $self->{clusters_rect} = Gnome2::Canvas::Item->new (
        $self->{clusters_group},
        'Gnome2::Canvas::Rect',
        x1 => 0,
        y1 => 0,
        x2 => 0,
        y2 =>0,
        'fill-color' => 'blue',
    );

    $self->{clusters_text} = Gnome2::Canvas::Item->new (
        $self->{clusters_group},
        'Gnome2::Canvas::Text',
        x => 0,
        y => 0,
        anchor => 'nw',
        fill_color_gdk => COLOUR_WHITE,
    );

    return;
}

# Resize slider (after zooming)
sub reposition_sliders {
    my $self = shift;

    my $xoffset = $self->{centre_x} * $self->{length_scale} - $self->{width_px} / 2;
    my $slider_x = ($self->{unscaled_slider_x} * $self->{length_scale}) - $xoffset;

    #print "[reposition_sliders] centre_x=$self->{centre_x} length_scale=$self->{length_scale} unscaled_slider_x=$self->{unscaled_slider_x} width_px=$self->{width_px} slider_x=$slider_x\n";

    $self->{slider}->set(
        x1 => $slider_x,
        x2 => $slider_x + SLIDER_WIDTH,
        y2 => $self->{render_height},
    );

    $self->{graph_slider}->set(
        x1 => $slider_x,
        x2 => $slider_x + SLIDER_WIDTH,
        y2 => $self->{graph_height_units},
    );

    $self->reposition_clusters_textbox($slider_x);

    return;
}

sub reposition_clusters_textbox {
    my $self = shift;
    my $slider_x = shift;

    # Adjust backing rectangle to fit over the text
    my ($w, $h) = $self->{clusters_text}->get('text-width', 'text-height');

    if ($slider_x + $w >= $self->{render_width}) { 
        # Move textbox to the left of the slider
        $self->{clusters_rect}->set(x1 => -1 * $w, y2 => $h);
        $self->{clusters_text}->set(anchor => 'ne');
    }
    else {
        # Textbox to the right of the slider
        $self->{clusters_rect}->set(x1 => $w, y2 => $h);
        $self->{clusters_text}->set(anchor => 'nw');
    }

    return;
}

sub on_slider_event {
    my ($self, $event, $item) = @_;

    if ($event->type eq 'enter-notify') {

        #print "Slider - enter\n";
        # Show #clusters
        $self->{clusters_group}->show;

        # Change the cursor
        my $cursor = Gtk2::Gdk::Cursor->new('sb-h-double-arrow');
        $self->{canvas}->window->set_cursor($cursor);
        $self->{graph}->window->set_cursor($cursor);

    }
    elsif ($event->type eq 'leave-notify') {

        #print "Slider - leave\n";
        # hide #clusters
        $self->{clusters_group}->hide;

        # Change cursor back to default
        $self->{canvas}->window->set_cursor($self->{cursor});
        $self->{graph}->window->set_cursor($self->{cursor});

    }
    elsif ( $event->type eq 'button-press') {

        #print "Slider - press\n";
        ($self->{pan_start_x}, $self->{pan_start_y}) = $event->coords;

        # Grab mouse
        $item->grab (
            [qw/pointer-motion-mask button-release-mask/],
            Gtk2::Gdk::Cursor->new ('fleur'),
            $event->time,
        );
        $self->{sliding} = 1;

    }
    elsif ( $event->type eq 'button-release') {

        #print "Slider - release\n";
        $item->ungrab ($event->time);
        $self->{sliding} = 0;

    }
    elsif ( $event->type eq 'motion-notify') {

        if ($self->{sliding}) {
            #print "Slider - slide\n";

            # Sliding..
            my ($x, $y) = $event->coords;

            # Clamp $x
            my $min_x = 0;
            my $max_x = $self->{width_px};

            if ($x < $min_x) {
                $x = $min_x ;
            }
            elsif ($x > $max_x) {
                $x = $max_x;
            }

            # Move slider and related graphics
            my $x2 = $x + SLIDER_WIDTH;
            $self->{slider}->        set(x1 => $x, x2 => $x2);
            $self->{graph_slider}->  set(x1 => $x, x2 => $x2);
            $self->{clusters_group}->set(x => $x2);

            # Calculate how far the slider is length-wise
            my $xoffset = $self->{centre_x}
                          * $self->{length_scale}
                          - $self->{width_px} / 2;

            $self->{unscaled_slider_x} = ($x + $xoffset) / $self->{length_scale};

            #print "[do_slider_move] x=$x pos=$self->{unscaled_slider_x}\n";

            $self->do_slider_move($self->{unscaled_slider_x});

            $self->reposition_clusters_textbox($x);

        }
        else {
            #print "Slider - motion\n";
        }
    }

    return 1;    
}

#  should we highlight it or not?
#  by default we switch the setting
sub set_use_highlight_func {
    my $self  = shift;
    my $value = shift;
    $value //= !$self->{use_highlight_func};
    $self->{use_highlight_func} = $value;

    return;
}

##########################################################
# Colouring
##########################################################

sub get_num_clusters {
    my $self = shift;
    return $self->{num_clusters} || 1;
}

sub set_num_clusters {
    my ($self, $number, $no_recolour) = @_;
    
    $self->{num_clusters} = $number || 1;
    # apply new setting
    if (!$no_recolour) {
        $self->recolour();
    }
    return;
}

# whether to colour by 'length' or 'depth'
sub set_group_mode {
    my $self = shift;
    $self->{group_mode} = shift;
    # apply new setting
    $self->recolour();
    return;
}

sub recolour {
    my $self = shift;

    if ($self->{colour_start_node}) {
        $self->do_colour_nodes_below($self->{colour_start_node});
    }

    return;
}

# Gets a hash of nodes which have been coloured
# Used by Spatial tab for getting an element's "cluster" (ie: coloured node that it's under)
#     hash of names (with refs as values)
sub get_cluster_node_for_element {
    my $self = shift;
    my $element = shift;
    return $self->{element_to_cluster}{$element};
}

sub get_palette_colorbrewer9 {
    # Set1 colour scheme from www.colorbrewer2.org
    no warnings 'qw';  #  we know the hashes are not comments
    return qw  '#E41A1C #377EB8 #4DAF4A #984EA3
                #FF7F00 #FFFF33 #A65628 #F781BF
                #999999';
}

sub get_palette_colorbrewer13 {
    # Paired colour scheme from colorbrewer, plus a dark grey
    #  note - this works poorly when 9 or fewer groups are selected
    no warnings 'qw';  #  we know the hashes are not comments
    return qw  '#A6CEE3 #1F78B4 #B2DF8A #33A02C
                #FB9A99 #E31A1C #FDBF6F #FF7F00
                #CAB2D6 #6A3D9A #FFFF99 #B15928
                #4B4B4B';
}

sub get_gdk_colors_colorbrewer9 {
    my $self = shift;
    my @colours
        = map {Gtk2::Gdk::Color->parse ($_)}
          $self->get_palette_colorbrewer9;
    return @colours;
}

sub get_gdk_colors_colorbrewer13 {
    my $self = shift;
    my @colours
        = map {Gtk2::Gdk::Color->parse ($_)}
          $self->get_palette_colorbrewer13;
    return @colours;
}

# Returns a list of colours to use for colouring however-many clusters
# returns STRING COLOURS
sub get_palette {
    my $self = shift;
    my $num_clusters = shift;
    #print "Choosing colour palette for $num_clusters clusters\n";

    return wantarray ? () : []
      if $num_clusters <= 0;  # trap bad numclusters

    my @colourset
        = $num_clusters <=  9 ? get_palette_colorbrewer9
        : $num_clusters <= 13 ? get_palette_colorbrewer13
        : (DEFAULT_LINE_COLOUR_RGB) x $num_clusters;

    #  return the relevant slice
    my @colours = @colourset[0 .. $num_clusters - 1]; 

    return wantarray ? @colours : \@colours;
}

sub get_palette_max_colours {
    my $self = shift;
    if (blessed ($self)
        and blessed ($self->{cluster})
        and defined $self->{cluster}->get_param ('MAX_COLOURS')) {

        return $self->{cluster}->get_param ('MAX_COLOURS');
    }

    return 13;  #  modify if more are added to the palettes.
}

# Finds which nodes the slider intersected and selects them for analysis
sub do_slider_move {
    my $self = shift;
    my $length_along = shift;

    #my $time = time();
    #return 1 if defined $self->{last_slide_time} &&
    #    ($time - $self->{last_slide_time}) < 0.2;

    # Find how far along the tree the slider is positioned
    # Saving slider position - to move it back in place after resize
    #print "[do_slider_move] Slider @ $length_along\n";

    # Find nodes that intersect the slides

    my $using_length = 1;
    if ($self->{plot_mode} eq 'length') {
        $length_along -= $self->{border_len};
        #FIXME: putting this fixes position errors, but don't understand how
        $length_along -= $self->{neg_len};
    }
    elsif ($self->{plot_mode} eq 'depth') {
        $length_along -= $self->{border_len};
        $length_along -= $self->{neg_len}; 
        $length_along = $self->{max_len} - $length_along;
        $using_length = 0;
    }
    else {
        croak "invalid plot mode: $self->{plot_mode}\n";
    }

    my $node_hash = $self->{tree_node}->group_nodes_below (
        target_value => $length_along,
        type         => $self->{plot_mode},
    );

    my @intersecting_nodes = values %$node_hash;

    # Update the slider textbox
    #   [Number of nodes intersecting]
    #   Above as percentage of total elements
    my $num_intersecting = scalar @intersecting_nodes;
    my $percent = sprintf('%.1f', $num_intersecting * 100 / $self->{num_nodes}); # round to 1 d.p.
    my $l_text  = sprintf('%.2f', $length_along);
    my $text = "$num_intersecting nodes\n$percent%\n"
                . ($using_length ? 'L' : 'D')
                . ": $l_text";
    $self->{clusters_text}->set( text => $text );

    # Highlight the lines in the dendrogram
    $self->clear_highlights;
    foreach my $node (values %$node_hash) {
        $self->highlight_node($node);
    }

    return if ! $self->{use_slider_to_select_nodes};

    # Set up colouring
    $self->assign_cluster_palette_colours(\@intersecting_nodes);
    $self->map_elements_to_clusters(\@intersecting_nodes);

    $self->recolour_cluster_elements();
    $self->recolour_cluster_lines(\@intersecting_nodes);
    $self->set_processed_nodes(\@intersecting_nodes);
    if ($self->{map}) {
        $self->{map}->update_legend;
    }

    #$self->{last_slide_time} = time;
    return;
}

sub toggle_use_slider_to_select_nodes {
    my $self = shift;

    $self->{use_slider_to_select_nodes} = ! $self->{use_slider_to_select_nodes};

    return;
}

sub set_use_slider_to_select_nodes {
    my ($self, $bool) = @_;

    $self->{use_slider_to_select_nodes} = !!$bool;

    return;
}

# Colours a certain number of nodes below
sub do_colour_nodes_below {
    my $self = shift;
    my $start_node = shift;

    #  Don't clear if we are multi-select - allows for mis-hits when
    #  selecting branches.
    return if !$start_node && $self->in_multiselect_mode;

    $self->{colour_start_node} = $start_node;

    my $num_clusters = $self->get_num_clusters;
    my $original_num_clusters = $num_clusters;
    my $excess_flag = 0;
    my $terminal_element_hash_ref;

    my @colour_nodes;

    if (defined $start_node) {

        # Get list of nodes to colour
        #print "[Dendrogram] Grouping...\n";
        my %node_hash = $start_node->group_nodes_below (
            num_clusters => $num_clusters,
            type => $self->{group_mode}
        );
        @colour_nodes = values %node_hash;
        #print "[Dendrogram] Done Grouping...\n";

        # FIXME: why loop instead of just grouping with
        # num_clusters => $self->get_palette_max_colours
        #  make sure we don't exceed the maximum number of colours
        while (scalar @colour_nodes > $self->get_palette_max_colours) {  
            $excess_flag = 1;

            # Group again with 1 fewer colours
            $num_clusters --;
            my %node_hash = $start_node->group_nodes_below (
                num_clusters => $num_clusters,
                type => $self->{group_mode},
            );
            @colour_nodes = values %node_hash;
        }
        $num_clusters = scalar @colour_nodes;  #not always the same, so make them equal now
        
        if ($self->in_multiselect_mode) {
            #  we need a hash of the terminals
            # (multiselect only has one node)
            $terminal_element_hash_ref = $colour_nodes[0]->get_terminal_elements;
        }

        #  keep the user informed of what happened
        if ($original_num_clusters != $num_clusters) {
            say "[Dendrogram] Could not colour requested number of clusters ($original_num_clusters)";

            if ($original_num_clusters < $num_clusters) {
                if ($excess_flag) {
                    printf "[Dendrogram] More clusters were requested (%d)"
                        . "than available colours (%d))\n",
                        $original_num_clusters,
                        $self->get_palette_max_colours;
                }
                else {
                    say "[Dendrogram] Requested number not feasible.  Returned $num_clusters.";
                }
            }
            else {
                say "[Dendrogram] Fewer clusters were identified ($num_clusters)";
            }
        }
    }
    elsif (!$self->in_multiselect_mode) {
        say "[Dendrogram] Clearing colouring";
    }
    
    # Set up colouring
    #print "num clusters = $num_clusters\n";
    $self->assign_cluster_palette_colours(\@colour_nodes);
    $self->map_elements_to_clusters(\@colour_nodes);

    $self->recolour_cluster_elements($terminal_element_hash_ref);
    $self->recolour_cluster_lines(\@colour_nodes);
    $self->set_processed_nodes(\@colour_nodes);
    if ($self->{map}) {
        $self->{map}->update_legend;
    }

    return;
}

# Assigns palette-based colours to selected nodes
sub assign_cluster_palette_colours {
    my $self = shift;
    my $cluster_nodes = shift;

    # don't set cluster colours if don't have enough palette values
    if (scalar @$cluster_nodes > $self->get_palette_max_colours()) {
        #print "[Dendrogram] not assigning palette colours (too many clusters)\n";

        # clear existing values
        foreach my $j (0..$#{$cluster_nodes}) {
            #$cluster_nodes->[$j]->set_cached_value(__gui_palette_colour => undef);
            $self->{node_palette_colours}{$cluster_nodes->[$j]->get_name} = undef;
        }

    }
    else {

        my @palette = $self->get_palette (scalar @$cluster_nodes);

        # so we sort them to make the colour order consistent
        my %sort_by_firstnode;
        my $i = 0;  #  in case we dont have numbered nodes
        foreach my $node_ref (@$cluster_nodes) {
            my $firstnode = ($node_ref->get_terminal_node_first_number // $i);
            $sort_by_firstnode{$firstnode} = $node_ref;
            $i++;
        }

        my @sorted_clusters = @sort_by_firstnode{sort numerically keys %sort_by_firstnode};

        # assign colours
        my $colour_ref;
        foreach my $k (0..$#sorted_clusters) {
            $colour_ref = Gtk2::Gdk::Color->parse($palette[$k]);
            #$sorted_clusters[$k]->set_cached_value(__gui_palette_colour => $colour_ref);
            $self->{node_palette_colours}{$sorted_clusters[$k]->get_name} = $colour_ref;
        }
    }

    return;
}

sub map_elements_to_clusters {
    my $self = shift;
    my $cluster_nodes = shift;

    my %map;

    foreach my $node_ref (@$cluster_nodes) {

        my $terminal_elements = $node_ref->get_terminal_elements();

        foreach my $elt (keys %$terminal_elements) {
            $map{ $elt } = $node_ref;
            #print "[map_elements_to_clusters] $elt->$node_ref\n";
        }

    }

    $self->{element_to_cluster} = \%map;

    return;
}

sub get_branch_line_width {
    my $self = shift;

    my $width = $self->{branch_line_width};
    if (!$width) {
        $width ||= eval {int ($self->{height_px} / $self->{tree_node}->get_terminal_element_count / 3)};
        $width ||= 1;
        $width = min (2, $width);
    }

    return $width;
}

sub set_branch_line_width {
    my ($self, $val) = @_;
    my $current = $self->get_branch_line_width;

    $val ||= 0;

    $self->{branch_line_width} = $val;

    if ($current != $val && $self->{tree_node}) {
        $self->render_tree;
    }
    
}

# Colours the element map with colours for the established clusters
sub recolour_cluster_elements {
    my $self = shift;
    my $terminal_element_subset = shift;

    my $map = $self->{map};
    return if not defined $map;

    my $list_name         = $self->{analysis_list_name}  // '';
    my $list_index        = $self->{analysis_list_index} // '';
    my $analysis_min      = $self->{analysis_min};
    my $analysis_max      = $self->{analysis_max};
    my $terminal_elements = $self->{terminal_elements};

    my $parent_tab = $self->{parent_tab};
    my $colour_for_undef = $parent_tab->get_undef_cell_colour;

    my $cluster_colour_mode = $self->get_cluster_colour_mode();
    my $colour_callback;

    if ($cluster_colour_mode eq 'palette') {
        # sets colours according to palette
        $colour_callback = sub {
            my $elt = shift;
            my $cluster_node = $self->{element_to_cluster}{$elt};
    
            if ($cluster_node) {
                my $colour_ref = $self->{node_palette_colours}{$cluster_node->get_name};
                return $colour_ref || COLOUR_PALETTE_OVERFLOW;
            }
            else {
                return exists $terminal_elements->{$elt}
                    ? COLOUR_OUTSIDE_SELECTION
                    : $self->get_colour_not_in_tree;
            }
    
            die "how did I get here?\n";
        };
    }
    elsif ($self->in_multiselect_mode) {
        my $multiselect_colour = $self->get_current_multiselect_colour;

        # sets colours according to multiselect palette
        $colour_callback = sub {
            my $elt = shift;

            return -1
              if    $terminal_element_subset
                 && !exists $terminal_element_subset->{$elt};

            my $cluster_node = $self->{element_to_cluster}{$elt};

            return -1 if !$cluster_node;

            return $multiselect_colour || COLOUR_OUTSIDE_SELECTION;
            #COLOUR_PALETTE_OVERFLOW;
        };
    }
    elsif ($cluster_colour_mode eq 'list-values') {
        my $legend = $map->get_legend;
        $legend->set_colour_mode_from_list_and_index (
            list  => $list_name,
            index => $list_index,
        );
        my @minmax_args = ($analysis_min, $analysis_max);
        my $colour_method = $legend->get_colour_method;

        # sets colours according to (usually spatial)
        # list value for the element's cluster
        $colour_callback = sub {
            my $elt = shift;

            my $cluster_node = $self->{element_to_cluster}{$elt};

            if ($cluster_node) {
                no autovivification;

                my $list_ref = $cluster_node->get_list_ref (list => $list_name)
                  // return $colour_for_undef;

                my $val = $list_ref->{$list_index}
                  // return $colour_for_undef;
                
                return $legend->$colour_method ($val, @minmax_args);
            }
            else {
                return exists $terminal_elements->{$elt}
                  ? COLOUR_OUTSIDE_SELECTION
                  : $self->get_colour_not_in_tree;
            }

            die "how did I get here?\n";
        };
    }

    die "Invalid cluster colour mode $cluster_colour_mode\n"
      if !defined $colour_callback;

    $map->colour ($colour_callback);

    #  now called elsewhere
    # if ($cluster_colour_mode eq 'list-values') {
    #     $map->set_legend_min_max($analysis_min, $analysis_max);
    #     $map->update_legend;
    # }

    return;
}

sub in_multiselect_mode {
    my $self = shift;
    my $mode = $self->get_cluster_colour_mode() // '';
    return $mode eq 'multiselect';
}

sub in_multiselect_clear_mode {
    my $self = shift;
    return ($self->get_cluster_colour_mode() // '')  eq 'multiselect'
      && eval {$self->{selector_toggle}->get_active};
}

sub enter_multiselect_clear_mode {
    my ($self, $no_store) = @_;
    eval {$self->{selector_toggle}->set_active (1)};
}

sub leave_multiselect_clear_mode {
    my $self = shift;
    eval {$self->{selector_toggle}->set_active (0)};
}

sub in_multiselect_autoincrement_colour_mode {
    my $self = shift;
    eval {$self->{autoincrement_toggle}->get_active};
}

sub clear_multiselect_colours_from_plot {
    my $self = shift;

    return if !$self->in_multiselect_mode;

    # temp override, as multiselect colour mode has side effects
    my $old_mode = $self->get_cluster_colour_mode();
    $self->set_cluster_colour_mode( value=>'palette' );
    #local $self->{cluster_colour_mode} = 'palette';
    
    my $colour_store = $self->get_multiselect_colour_store;
    if (@$colour_store) {
        my $tree = $self->get_tree_object;
        my @coloured_nodes = map {$tree->get_node_ref (node => $_->[0])} @$colour_store;
        #  clear current colouring
        #$self->recolour_cluster_elements;
        $self->recolour_cluster_lines (\@coloured_nodes);
    }

    $self->set_cluster_colour_mode( value=>$old_mode );

    return;
}

#  later we can get this from a cached value on the tree object
sub get_multiselect_colour_store {
    my $self = shift;
    my $tree = $self->get_tree_object;
    my $store
      = $tree->get_cached_value_dor_set_default_aa (
        GUI_MULTISELECT_COLOUR_STORE => [],
    );
    return $store;
}

sub store_multiselect_colour {
    my $self = shift;
    my @pairs = @_;  #  usually get only one name/colour pair

    return if $self->{multiselect_no_store};

    my $store = $self->get_multiselect_colour_store;

  PAIR:
    foreach my $pair (pairs @pairs) {
        #  don't store refs
        if (blessed $pair->[0]) {
            $pair->[0] = $pair->[0]->get_name;
        }
        #  don't store Gdk objects due to serialisation issues
        if (blessed $pair->[1]) {
            $pair->[1] = $pair->[1]->to_string;
        }

        ##  Don't store duplicates.
        ##  We get double triggers for some reason due to a
        ##  higher sub being called twice for each colour event
        next PAIR
          if scalar @$store
            &&  $store->[-1][0] eq $pair->[0]
            && ($store->[-1][1] // '') eq ($pair->[1] // '');

        push @$store, $pair;
    }

    #  reset the redo stack
    $self->reset_multiselect_undone_stack;
    $self->get_parent_tab->set_project_dirty;

    return;
}

sub get_current_multiselect_colour {
    my $self = shift;

    return if $self->in_multiselect_clear_mode;

    my $colour;
    eval {
        $colour = $self->{selector_colorbutton}->get_color;
    };

    return $colour;
}

sub set_current_multiselect_colour {
    my $self   = shift;
    my $colour = shift;

    return if !defined $colour;  #  should we croak?

    eval {
        if ((blessed $colour // '') !~ /Gtk2::Gdk::Color/) {
            $colour = Gtk2::Gdk::Color->parse  ($colour);
        }
        $colour = $self->{selector_colorbutton}->set_color ($colour);
    };

    return $colour;
}

sub increment_multiselect_colour {
    my $self = shift;
    my $force_increment = shift;
    
    return if !$force_increment
           && !$self->in_multiselect_mode;

    return if $self->in_multiselect_clear_mode;
    return if !$self->in_multiselect_autoincrement_colour_mode;

    my $colour = $self->get_current_multiselect_colour;

    my @colours = $self->get_gdk_colors_colorbrewer13;

    if (my $last_colour = $self->{last_multiselect_colour}) {
        my $i = firstidx {$last_colour->equal($_)} @colours;
        $i++;
        $i %= scalar @colours;
        $colour = $colours[$i];
    }
    else {
        $colour = $colours[0];
    }

    eval {
        $self->{selector_colorbutton}->set_color ($colour);
    };
    
    $self->{last_multiselect_colour} = $colour;
    
    return;
}

sub get_colour_not_in_tree {
    my $self = shift;
    
    my $colour = eval {
        $self->get_parent_tab->get_excluded_cell_colour
    } || COLOUR_NOT_IN_TREE;

    return $colour;
}


sub clear_node_colours {
    my $self = shift;
    
    $self->{node_colours_cache} = {};    

    my $tree = $self->get_tree_object();

    return if !$tree;

    foreach my $node ($tree->get_node_refs()) {
        $self->set_node_colour(
            node_name  => $node->get_name(),
            colour_ref => DEFAULT_LINE_COLOUR,
        );
    }

    return;
}

sub set_node_colour {
    my ($self, %args) = @_;
    my $colour_ref = $args{ colour_ref };
    my $node_name  = $args{ node_name  };

    # cache the colour
    $self->{node_colours_cache}{$node_name} = $colour_ref;

    #  needs profiling - we cache the nodes by name somewhere

    # also store it in the node for export purposes
    my $node_ref 
      = $self->get_tree_object->get_node_ref_aa($node_name);

    my $colour_string = $colour_ref
        ? $colour_ref->to_string 
        : DEFAULT_LINE_COLOUR_RGB;

    $node_ref->set_bootstrap_colour_aa ($colour_string);
}

# boolean: has a colour been set for a given node
sub node_has_colour {
    my ($self, %args) = @_;
    my $node_name = $args{node_name};
    return (exists $self->{node_colours_cache}{$node_name});
}

sub get_node_colour {
    my ($self, %args) = @_;
    my $node_name = $args{node_name};
    
    return $self->{node_colours_cache}{$node_name};
}

#  squeeze a little more performance 
sub get_node_colour_aa {
    $_[0]->{node_colours_cache}{$_[1]};
}

# convert from a colour_ref to whatever string format we want to use.
# not sure if this function should really be here but there's no
# general colour module?
#  could shift the logic into TreeNode.pm and have conditional usage
#  based on it fitting #RRRRGGGGBBBB
#  requires that we always store the string forms
sub get_proper_colour_format {
    my ($self, %args) = @_;
    my $colour_ref = $args{colour_ref};
    
    # of the form # RRRR GGGG BBBB (without spaces)
    my $long_form_string = $colour_ref->to_string();

    # the way colours are selected in the dendrogram only allows for 2
    # hex digits for each color. Unless this is change, we don't lose
    # precision by truncating two of the four digits for each colour
    # that are stored in the colour ref.
    my $proper_form_string = "#";
    my @wanted_indices = (1, 2, 5, 6, 9, 10);
    foreach my $index (@wanted_indices) {
        $proper_form_string .= substr($long_form_string, $index, 1);
    }

    return $proper_form_string;
}


# Colours the dendrogram lines with palette colours
sub recolour_cluster_lines {
    my $self = shift;
    my $cluster_nodes = shift;
    my $colour_descendents = !shift;  #  negate the arg

    my ($colour_ref, $line, $list_ref, $val);
    my %coloured_nodes;

    my $map = $self->{map};
    my $list_name    = $self->{analysis_list_name}  // '';
    my $list_index   = $self->{analysis_list_index} // '';
    my $analysis_min = $self->{analysis_min};
    my $analysis_max = $self->{analysis_max};
    my $colour_mode  = $self->get_cluster_colour_mode();

    my ($legend, @minmax_args, $colour_method);
    if ($colour_mode ne 'palette' and not $self->in_multiselect_mode) {
        $legend = $map->get_legend;
        $legend->set_colour_mode_from_list_and_index(
            list  => $list_name,
            index => $list_index,
        );
        @minmax_args = ($analysis_min, $analysis_max);
        $colour_method = $legend->get_colour_method;
    }

    foreach my $node_ref (@$cluster_nodes) {

        my $node_name = $node_ref->get_name;

        if ($colour_mode eq 'palette') {
            $colour_ref = $self->{node_palette_colours}{$node_name} || COLOUR_RED;
        }
        elsif ($self->in_multiselect_mode) {
            $colour_ref = $self->get_current_multiselect_colour;
            if ($colour_ref || $self->in_multiselect_clear_mode) {
                $self->store_multiselect_colour ($node_name => $colour_ref);
            }          
            
        }
        elsif ($colour_mode eq 'list-values') {

            $list_ref = $node_ref->get_list_ref (list => $list_name);
            $val = defined $list_ref
              ? $list_ref->{$list_index}
              : undef;  #  allows for missing lists

            $colour_ref = defined $val
              ? $legend->$colour_method ($val, @minmax_args)
              : undef;
        }
        else {
            die "unknown colouring mode $colour_mode\n";
        }

        $self->set_node_colour(
            colour_ref => $colour_ref,
            node_name  => $node_name,
        );
                        
        # if colour is undef then we're clearing back to default
        $colour_ref ||= DEFAULT_LINE_COLOUR;

        $line = $self->{node_lines}{$node_name};
        if ($line) {
            $line->set(fill_color_gdk => $colour_ref);
        }

        # And also colour all nodes below
        # - don't cache on the tree as we can get recursion stack blow-outs
        # - https://github.com/shawnlaffan/biodiverse/issues/549
        # We could cache on $self if it were needed.
        if ($colour_descendents) {
            my $descendants = $node_ref->get_all_descendants (cache => 0);
            foreach my $child_ref (values %$descendants) {
                $self->colour_line(
                    $child_ref,
                    $colour_ref,
                    \%coloured_nodes,
                );
            }
        }

        $coloured_nodes{$node_name} = $node_ref; # mark as coloured
    }

    if (!$self->in_multiselect_mode) {
        if ($self->{recolour_nodes}) {
            #print "[Dendrogram] Recolouring ", scalar keys %{ $self->{recolour_nodes} }, " nodes\n";
            # uncolour previously coloured nodes that aren't being coloured this time
          NODE:
            foreach my $node_name (keys %{ $self->{recolour_nodes} }) {
                next NODE if exists $coloured_nodes{$node_name};

                $self->{node_lines}->{$node_name}->set(fill_color_gdk => DEFAULT_LINE_COLOUR);
                $self->set_node_colour(
                    colour_ref => DEFAULT_LINE_COLOUR,
                    node_name  => $node_name,
                    );
          }

            #print "[Dendrogram] Recoloured nodes\n";
        }
        $self->{recolour_nodes} = \%coloured_nodes;
    }
    #else {
    #    my $href = $self->{recolour_nodes} //= {};
    #    @$href{keys %coloured_nodes} = values %coloured_nodes;
    #}
    return;
}

#  non-recursive version of colour_lines.
#  Assumes it is called for each of the relevant nodes
sub colour_line {
    my ($self, $node_ref, $colour_ref, $coloured_nodes) = @_;

    my $name = $node_ref->get_name;

    $self->set_node_colour (
        colour_ref => $colour_ref,
        node_name  => $name,
    );

    
    my $line = $self->{node_lines}->{$name};
    if ($line) {
        $self->{node_lines}->{$name}->set(fill_color_gdk => $colour_ref);
    }
    $coloured_nodes->{ $name } = $node_ref; # mark as coloured

    return;
}


sub colour_lines {
    my ($self, $node_ref, $colour_ref, $coloured_nodes) = @_;

    my $name = $node_ref->get_name;

    $self->set_node_colour (
        colour_ref => $colour_ref,
        node_name  => $name,
    );
    
    $self->{node_lines}->{$name}->set(fill_color_gdk => $colour_ref);
    $coloured_nodes->{ $name } = $node_ref; # mark as coloured

    foreach my $child_ref ($node_ref->get_children) {
        $self->colour_lines($child_ref, $colour_ref, $coloured_nodes);
    }

    return;
}


sub restore_line_colours {
    my $self = shift;

    if ($self->{recolour_nodes}) {

        my $colour_ref;
        foreach my $node_name (keys %{ $self->{recolour_nodes} }) {

            $colour_ref
               = $self->{node_palette_colours}{$node_name}
              // DEFAULT_LINE_COLOUR;
            # if colour is undef then we're clearing back to default

            $self->{node_lines}->{$node_name}->set(fill_color_gdk => $colour_ref);
        }
    }

    return;
}

sub get_processed_nodes {
    my $self = shift;
    return $self->{processed_nodes};
}

sub set_processed_nodes {
    my $self = shift;
    $self->{processed_nodes} = shift;

    return;
}

##########################################################
# The map combobox business
# This is the one that selects how to colour the map
##########################################################

# Provides list of results for tab to use as it sees fit
sub get_map_lists {
    my $self = shift;
    my $lists = scalar $self->{tree_node}->get_hash_lists();
    return [sort @$lists];
}

# Combo-box for the list of results (eg: REDUNDANCY or ENDC_SINGLE) to use for the map
sub setup_map_list_model {
    my $self  = shift;
    my $lists = shift;

    my $combo = $self->{map_list_combo};

    #  some uses don't have the map list
    #  - need to clean up the logic and abstract such components to a different class
    return if !defined $combo;  

    my $model = Gtk2::ListStore->new('Glib::String');
    my $iter;

    # Add all the analyses
    foreach my $list (sort @$lists) {
        #print "[Dendrogram] Adding map list $list\n";
        $iter = $model->append;
        $model->set($iter, 0, $list);
    }

    #  add the multiselect selector
    $iter = $model->insert(0);
    $model->set($iter, 0, '<i>User defined</i>');

    # Add & select, the "cluster" analysis (distinctive colour for every cluster)
    $iter = $model->insert(0);
    $model->set($iter, 0, '<i>Cluster</i>');
    
    if ($combo) {
        $combo->set_model($model);
        $combo->set_active_iter($iter);
    }

    return;
}

sub update_map_list_model {
    my $self = shift;
    
    $self->setup_map_list_model( scalar $self->{tree_node}->get_hash_lists() );    
}

# Provides list of map indices for tab to use as it sees fit.
# Context sensitive on currently selected map list.
# Is it used anywhere?
sub get_map_indices {
    my $self = shift;
    if (not defined $self->{analysis_list_name}) {
        return [];
    }

    my $list_ref = $self->{tree_node}->get_list_ref(
        list => $self->{analysis_list_name},
    );

    #  clunky - need to shift that method to a more general class
    return scalar sort_list_with_tree_names_aa ([keys %$list_ref]);
}

# Combo-box for analysis within the list of results (eg: REDUNDANCY or ENDC_SINGLE)
sub setup_map_index_model {
    my $self = shift;
    my $indices = shift;

    my $model = Gtk2::ListStore->new('Glib::String');
    my $combo = $self->{map_index_combo};
    
    return if !defined $combo;
    
    $combo->set_model($model);
    
    my $iter;

    # Add all the analyses
    if ($indices) { # can be undef if we want to clear the list (eg: selecting "Cluster" mode)

        # restore previously selected index for this list
        my $selected_index = $self->{selected_list_index}{$indices};
        my $selected_iter = undef;

        foreach my $key (sort_list_with_tree_names_aa ([keys %$indices])) {
            #print "[Dendrogram] Adding map analysis $key\n";
            $iter = $model->append;
            $model->set($iter, 0, $key);

            if (defined $selected_index && $selected_index eq $key) {
                $selected_iter = $iter;
            }
        }

        if ($selected_iter) {
            $self->{map_index_combo}->set_active_iter($selected_iter);
        }
        else {
            $self->{map_index_combo}->set_active_iter($model->get_iter_first);
        }
    }

    return;
}

sub _dump_line_colours {
    my ($self, $node_name) = @_;
    $node_name //= "120___";

    if ( $self->node_has_colour( node_name=>$node_name ) ) {
        my $caller = ( caller(1) )[3];
        my $caller_line = ( caller(1) )[2];
        $caller =~ s/Biodiverse::GUI::Dendrogram:://;
        print "$node_name ($caller, $caller_line): ";

        my $colour_ref = $self->get_node_colour_aa ($node_name);
        eval {
            say $colour_ref->to_string,
                ' ',
                $colour_ref->get_property ('fill-color-gdk')->to_string;
        };
    }
}

sub set_cluster_colour_mode {
    my ($self, %args) = @_;
    my $value = $args { value };
    $self->{cluster_colour_mode} = $value;
}

sub get_cluster_colour_mode {
    my ($self) = @_;
    my $value =  $self->{cluster_colour_mode};
    return $value;
}

# Change of list to display on the map
# Can either be the Cluster "list" (coloured by node) or a spatial analysis list
sub on_map_list_combo_changed {
    my $self  = shift;
    my $combo = shift || $self->{map_list_combo};

    my $iter  = $combo->get_active_iter;
    my $model = $combo->get_model;
    my $list  = $model->get($iter, 0);

    $self->{analysis_list_name}  = undef;
    $self->{analysis_list_index} = undef;
    $self->{analysis_min}        = undef;
    $self->{analysis_max}        = undef;
    
    #  multiselect hides it
    if ($self->{slider}) {
        $self->{slider}->show;
        $self->{graph_slider}->show;
    }

    if ($list eq '<i>Cluster</i>') {
        # Selected cluster-palette-colouring mode
        $self->clear_multiselect_colours_from_plot;

        $self->set_cluster_colour_mode(value => 'palette');

        $self->get_parent_tab->on_clusters_changed;

        $self->recolour_cluster_elements;
        $self->recolour_cluster_lines($self->get_processed_nodes);

        # blank out the index combo
        $self->setup_map_index_model(undef);
    }
    elsif ($list eq '<i>User defined</i>') {
        if ($self->{slider}) {
            $self->{slider}->hide;
            $self->{graph_slider}->hide;
        }

        $self->set_cluster_colour_mode(value => 'multiselect');
        
        $self->set_num_clusters (1, 'no_recolour');

        $self->replay_multiselect_store;

        # blank out the index combo
        $self->setup_map_index_model(undef);
    }
    else {
        $self->clear_multiselect_colours_from_plot;

        $self->get_parent_tab->on_clusters_changed;

        # Selected analysis-colouring mode
        $self->{analysis_list_name} = $list;

        $self->setup_map_index_model($self->{tree_node}->get_list_ref(list => $list));
        $self->on_map_index_combo_changed;
    }

    return;
}

#  this should be controlled by the parent tab, not the dendrogram
sub on_map_index_combo_changed {
    my $self  = shift;
    my $combo = shift || $self->{map_index_combo};

    my $index = undef;
    my $iter  = $combo->get_active_iter;

    if ($iter) {
        $index = $combo->get_model->get($iter, 0);
        $self->{analysis_list_index} = $index;

        my $map = $self->{map};

        my @minmax = $self->get_parent_tab->set_plot_min_max_values;

        # say "[Dendrogram] Setting grid to use index $index";
        #  must set this before legend min max
        $map->set_legend_colour_mode_from_list_and_index (
            list  => $self->{analysis_list_name},
            index => $self->{analysis_list_index},
        );
        $map->set_legend_min_max(@minmax);
        $self->get_parent_tab->on_colour_mode_changed;

        $self->set_cluster_colour_mode(value => "list-values");
        $self->recolour_cluster_elements();

        $self->recolour_cluster_lines($self->get_processed_nodes);

        $map->update_legend;
    }
    else {
        $self->{analysis_list_index} = undef;
        $self->{analysis_min}        = undef;
        $self->{analysis_max}        = undef;
    }

    return;
}


sub select_map_index {
    my ($self, $index) = @_;

    if (defined $index) {
        $self->{analysis_list_index} = $index;

        $self->get_parent_tab->recolour;

        my @minmax = $self->get_plot_min_max_values;
        $self->{analysis_min} = $minmax[0];
        $self->{analysis_max} = $minmax[1];

        #print "[Dendrogram] Setting grid to use (spatial) analysis $analysis\n";
        $self->set_cluster_colour_mode(value => 'list-values');
        $self->recolour_cluster_elements();

        $self->recolour_cluster_lines($self->get_processed_nodes);
    }
    else {
        $self->{analysis_list_index} = undef;
        $self->{analysis_min}        = undef;
        $self->{analysis_max}        = undef;
    }
}

sub set_plot_min_max_values {
    my $self = shift;
    my ($min, $max) = @_;

    $self->{analysis_min} = $min;
    $self->{analysis_max} = $max;

    return wantarray ? ($min, $max) : [$min, $max];
}

sub get_plot_min_max_values {
    my $self = shift;
    
    my ($min, $max) = ($self->{analysis_min}, $self->{analysis_max});
    if (not defined $min or not defined $max) {
        ($min, $max) = $self->get_parent_tab->get_plot_min_max_values;
    }
    
    my @minmax = ($min, $max);
    
    return wantarray ? @minmax : \@minmax;
}

sub reset_multiselect_undone_stack {
    my $self = shift;
    $self->get_tree_object->set_cached_value (
        GUI_MULTISELECT_UNDONE_STACK => [],
    );
}

sub get_multiselect_undone_stack {
    my $self = shift;
    my $undone_stack = $self->get_tree_object->get_cached_value_dor_set_default_aa (
        GUI_MULTISELECT_UNDONE_STACK => [],
    );
    return $undone_stack;
}

sub undo_multiselect_click {
    my ($self, $offset) = @_;

    return if !$self->in_multiselect_mode;

    #  convert zero to 1, or should we make noise?
    $offset ||= 1;

    croak "offset value should not be negative (got $offset)\n"
      if $offset < 0;

    my $colour_store = $self->get_multiselect_colour_store;

    #  don't splice an empty array
    return if !@$colour_store;

    #  splice off the end of colour store, assuming we are in undo mode
    my @undone = splice @$colour_store, -$offset;

    my $undone_stack = $self->get_multiselect_undone_stack;
    
    #  store in reverse order
    unshift @$undone_stack, reverse @undone;
    
    $self->replay_multiselect_store;
    $self->get_parent_tab->set_project_dirty;
}

sub redo_multiselect_click {
    my ($self, $offset) = @_;

    return if !$self->in_multiselect_mode;

    #  convert zero to 1, or should we make noise?
    $offset ||= 1;

    croak "offset value should not be negative (got $offset)\n"
      if $offset < 0;

    my $undone_stack = $self->get_multiselect_undone_stack;

    #  nothing to redo
    return if !@$undone_stack;

    my $colour_store = $self->get_multiselect_colour_store;

    my @undone = splice @$undone_stack, 0, min ($offset, scalar @$undone_stack);

    push @$colour_store, @undone;
    
    $self->replay_multiselect_store;
    $self->get_parent_tab->set_project_dirty;
}

sub replay_multiselect_store {
    my $self = shift;
    #my %args = @_;
    
    return if !$self->in_multiselect_mode;

    #  clear current colouring of elements
    #  this is a mess - we should not have to switch to palette mode for this to work
    $self->set_cluster_colour_mode( value=>'palette' );
    $self->{element_to_cluster}  = {};
    $self->{recolour_nodes}      = undef;
    $self->set_processed_nodes (undef);
    $self->recolour_cluster_elements;
    $self->set_cluster_colour_mode( value=>'multiselect' );

    #   The next bit of code probably does too much
    #   but getting it to work was not simple
    my $tree = $self->get_tree_object;
    my $node_ref_array = $tree->get_root_node_refs;

    #my $was_in_clear_mode = $self->in_multiselect_clear_mode;
    my $old_seq_sel_no_store = $self->{multiselect_no_store};
    $self->{multiselect_no_store} = 1;
    $self->enter_multiselect_clear_mode ('no_store');
    $self->map_elements_to_clusters ($node_ref_array);
    $self->recolour_cluster_lines ($node_ref_array);
    #if (!$was_in_clear_mode) {
        $self->leave_multiselect_clear_mode;
    #}
    $self->{multiselect_no_store} = $old_seq_sel_no_store;


    my $colour_store = $self->get_multiselect_colour_store;

    return if !@$colour_store;

    #  use a copy to avoid infinite recursion, as the
    #  ref can be appended to in one of the called subs
    my @pairs = @$colour_store;

    #  ensure recolouring works
    $self->map_elements_to_clusters (
        [map {$tree->get_node_ref (node => $_->[0])} @pairs]
    );

    foreach my $pair (@pairs) {
        $self->{multiselect_no_store} = 1;
        my $was_in_clear_mode = 0;
        my $node_ref = $tree->get_node_ref (node => $pair->[0]);
        $self->set_current_multiselect_colour ($pair->[1]);
        my $elements = $node_ref->get_terminal_elements;
        if (!defined $pair->[1]) {
            $was_in_clear_mode = 1;
            $self->enter_multiselect_clear_mode;
        }
        $self->recolour_cluster_elements ($elements);
        $self->set_processed_nodes ([$node_ref]);  #  clunky - poss needed because we call get_processed_nodes below?
        $self->recolour_cluster_lines($self->get_processed_nodes);
        if ($was_in_clear_mode) {
            $self->leave_multiselect_clear_mode;
        }
    }
    $self->{multiselect_no_store} = $old_seq_sel_no_store;

}

##########################################################
# Highlighting a path up the tree
##########################################################

# Remove any existing highlights
sub clear_highlights {
    my ($self, $new_colour) = @_;
    
    # set all nodes to recorded/default colour
    return if !$self->{highlighted_lines};

    foreach my $node_name (keys %{$self->{tree_node_name_hash}}) {
        # assume node has associated line
        my $line = $self->{node_lines}{$node_name};
        next if !$line;
        my $colour_ref
          =  $new_colour
            || $self->get_node_colour_aa ( $node_name )
            || DEFAULT_LINE_COLOUR;
        $line->set(fill_color_gdk => $colour_ref);
    }
    $self->{highlighted_lines} = undef;

    return;
}

sub highlight_node {
    my ($self, $node_ref, $node_colour) = @_;

    my $all_tree_node_names = $self->{tree_node_name_hash};

    # if first highlight, set all other nodes to grey
    if (! $self->{highlighted_lines}) {
        foreach my $node_name (keys %$all_tree_node_names) {
            # assume node has associated line
            my $line = $self->{node_lines}{$node_name};
            next if !$line;
            $line->set(fill_color_gdk => COLOUR_GRAY);
        }
    }

    # highlight this node/line by setting black
    my $node_name = $node_ref->get_name;
    #  avoid some unhandled exceptions when the mouse is
    #  hovering and the display is under construction
    if (my $line = $self->{node_lines}{$node_name}) {  

        my $colour_ref =  $node_colour 
                       || $self->get_node_colour_aa ($node_name)
                       || DEFAULT_LINE_COLOUR;

        $line->set(fill_color_gdk => $colour_ref);
        #$line->set(width_pixels => HIGHLIGHT_WIDTH);
        $line->raise_to_top;
        push @{$self->{highlighted_lines}}, $line;
    }

    return;
}

# Highlights all nodes above and including the given node
sub highlight_path {
    my ($self, $node_ref, $node_colour) = @_;

    # if first highlight, set all other nodes to grey
    if (! $self->{highlighted_lines}) {
        my $desc = $self->{tree_node_name_hash};
        foreach my $node_name (keys %$desc) {
            # assume node has associated line
            my $line = $self->{node_lines}->{$node_name};
            next if !$line;
            $line->set(fill_color_gdk => COLOUR_GRAY);
        }
    }

    # set path to highlighted colour
    while ($node_ref) {
        my $line = $self->{node_lines}->{$node_ref->get_name};
        my $colour_ref =  $node_colour 
                       || $self->get_node_colour_aa ($node_ref->get_name)
                       || DEFAULT_LINE_COLOUR;
        $line->set(fill_color_gdk => $colour_ref);
        #$line->set(width_pixels => HIGHLIGHT_WIDTH);
        $line->raise_to_top;
        push @{$self->{highlighted_lines}}, $line;

        $node_ref = $node_ref->get_parent;
    }

    return;
}

# Circles a node's terminal elements. Clear marks if $node undef
sub mark_elements {
    my $self = shift;
    my $node = shift;

    return if !$self->{map};

    my $terminal_elements = (defined $node) ? $node->get_terminal_elements : {};
    $self->{map}->mark_if_exists( $terminal_elements, 'circle' );
    $self->{map}->mark_if_exists( {}, 'minus');

    return;
}

##########################################################
# Tree operations
##########################################################

# Sometimes, tree lengths are negative and nodes get pushed back behind the root
# This will calculate how far they're pushed back so that we may render them
#
# Returns an absolute value or zero
sub get_max_negative_length {
    my $treenode = shift;
    my $min_length = 0;

    get_max_negative_length_inner($treenode, 0, \$min_length);
    if ($min_length < 0) {
        return -1 * $min_length;
    }
    else {
        return 0;
    }

    return;
}

sub get_max_negative_length_inner {
    my ($node, $cur_len, $min_length_ref) = @_;

    if (${$min_length_ref} > $cur_len) {
        ${$min_length_ref} = $cur_len;
    }
    foreach my $child ($node->get_children) {
        get_max_negative_length_inner($child, $cur_len + $node->get_length, $min_length_ref);
    }

    return;
}

sub initYCoords {
    my ($self, $tree) = @_;

    # This is passed by reference
    # Will be increased as each leaf is allocated coordinates
    my $current_y = 0;
    $self->initYCoordsInner($tree, \$current_y);

    return;
}

sub initYCoordsInner {
    my ($self, $node, $current_y_ref) = @_;

    if ($node->is_terminal_node) {

        $node->set_value('_y', $$current_y_ref + $self->{border_ht});
        ${$current_y_ref} = ${$current_y_ref} + LEAF_SPACING;

    }
    else {
        my $y_sum;
        my $count = 0;

        foreach my $child ($node->get_children) {
            $self->initYCoordsInner($child, $current_y_ref);
            $y_sum += $child->get_value('_y');
            $count++;
        }
        $node->set_value('_y', $y_sum / $count); # y-value is average of children's y values
    }

    return;
}


# These make an array out of the tree nodes
# sorted based on total length up to the node
#  (ie: excluding the node's own length)
sub make_total_length_array {
    my $self = shift;
    #my @array;
    my $lf = $self->{length_func};
    $lf = $self->{max_length_func};

    #make_total_length_array_inner($self->{tree_node}, 0, \@array, $lf);
    my $tree_ref = $self->{cluster};
    my $node_hash = $tree_ref->get_node_hash;
    my @array = values %$node_hash;

    my %cache;

    # Sort it
    @array = sort {
        ($cache{$a} //= $lf->($a))
          <=>
        ($cache{$b} //= $lf->($b))
        }
        @array;

    $self->{total_lengths_array} = \@array;

    return;
}

#sub make_total_length_array_inner {
#    my ($node, $length_so_far, $array, $lf) = @_;
#
#    $node->set_value(total_length_gui => $length_so_far);
#    push @{$array}, $node;
#
#    # Do the children
#    my $length_total = $lf->($node) + $length_so_far;
#    foreach my $child ($node->get_children) {
#        make_total_length_array_inner($child, $length_total, $array, $lf);
#    }
#
#    return;
#}

##########################################################
# Drawing the tree
##########################################################

# whether to plot by 'length' or 'depth'
sub set_plot_mode {
    my ($self, $plot_mode) = @_;

    $self->{plot_mode} = $plot_mode;

    # Work out how to get the "length" based on mode
    if ($plot_mode eq 'length') {
        $self->{length_func}       = sub {$_[0]->get_length};
        $self->{max_length_func}   = sub {$_[0]->get_max_total_length (cache => 1)};
        $self->{neg_length_func}   = \&get_max_negative_length;
        $self->{dist_to_root_func} = sub {$_[0]->get_distance_to_root_node};
    }
    elsif ($plot_mode eq 'depth') {
        $self->{length_func}       = sub { return 1; }; # each node is "1" depth level below the previous one
        $self->{max_length_func}   = sub {$_[0]->get_depth_below + 1};
        $self->{neg_length_func}   = sub { return 0; };
        $self->{dist_to_root_func} = sub {$_[0]->get_depth + 1};
    }
    elsif ($plot_mode =~ 'equal_length|range_weighted') {
        #  create a clone and wrap the methods
        my $tree = $self->get_parent_tab->get_current_tree;
        my $alt_tree = $tree;  #  can be proecssed in both if conditions below
        if ($plot_mode =~ 'equal_length') {
            $alt_tree = $alt_tree->clone_tree_with_equalised_branch_lengths;
        }
        if ($plot_mode =~ 'range_weighted') {
            my $bd = $self->get_parent_tab->get_base_ref;
            $alt_tree = $alt_tree->clone_without_caches;
            NODE:
            foreach my $node ( rnkeysort {$_->get_depth} $alt_tree->get_node_refs ) {
                my $range = $node->get_node_range( basedata_ref => $bd );
                $node->set_length_aa( $range ? $node->get_length / $range : 0 );
            }
        }
        #  We are passed nodes from the original tree, so use their names to
        #  look up the ref in the alt tree.
        $self->{length_func}       = sub {
            $alt_tree->get_node_ref_aa($_[0]->get_name)->get_length;
        };
        $self->{max_length_func}   = sub {
            $alt_tree->get_node_ref_aa($_[0]->get_name)->get_max_total_length (cache => 1);
        };
        $self->{neg_length_func}   = sub { return 0; };
        $self->{dist_to_root_func} = sub {
            $alt_tree->get_node_ref_aa($_[0]->get_name)->get_distance_to_root_node;
        };
    }
    else {
        die "Invalid cluster-plotting mode - $plot_mode";
    }

    # Work out dimensions in canvas units
    my $f = $self->{max_length_func};
    my $g = $self->{neg_length_func};
    my $ht = $self->{num_leaves} * LEAF_SPACING;
    $self->{unscaled_height} = $ht + $self->{border_ht} * 2;
    $self->{max_len}         = $f->($self->{tree_node}); # this is in (unscaled) cluster-length units
    $self->{neg_len}         = $g->($self->{tree_node});
    $self->{border_len}      = 0.5 * BORDER_FRACTION * ($self->{max_len} + $self->{neg_len}) / (1 - BORDER_FRACTION);
    $self->{unscaled_width}  = 2 * $self->{border_len} + $self->{max_len} + $self->{neg_len};

    #  These are in "tree coords" and the whole plotting process is based on them.
    #  As the plot is panned and zoomed these are updated to be at the centre of the plot.
    #  Everything else is then scaled from them.  
    $self->{centre_x} = $self->{unscaled_width} / 2;
    $self->{centre_y} = $self->{unscaled_height} / 2;

    $self->{unscaled_slider_x} = $self->{unscaled_width} - $self->{border_len} / 2;
    #print "[Dendrogram] slider position is $self->{unscaled_slider_x}\n";
    #
    #print "[Dendrogram] max len = " . $self->{max_len} . " neg len = " . $self->{neg_len} . "\n";
    #print "[Dendrogram] unscaled width: $self->{unscaled_width}, unscaled height: $self->{unscaled_height}\n";

    # Make sorted total length array to make slider and graph fast
    $self->make_total_length_array;

    # (redraw)
    $self->render_tree;
    $self->render_graph;
    $self->setup_scrollbars;
    $self->resize_background_rect;

    return;
}

# Sets a new tree to draw (TreeNode)
#   Performs once-off init such as getting number of leaves and
#   setting up the Y coords
sub set_cluster {
    my $self = shift;
    my $cluster = shift;
    my $plot_mode = shift; # (cluster) 'length' or 'depth'

    $self->{cluster} = $cluster;
    
    return if !defined $cluster;  #  trying to avoid warnings

    # Clear any palette colours
    delete $self->{node_colours_cache};
    $self->{node_palette_colours} = {};
    foreach my $node_ref (values %{$cluster->get_node_hash}) {
        #$node_ref->set_cached_value(__gui_palette_colour => undef);
        $self->{node_palette_colours}{$node_ref->get_name} = undef;
    }

    #  skip incomplete clusterings (where the tree was not built)
    my $completed = $cluster->get_param('COMPLETED') // 1;
    return if $completed != 1;

    $self->{tree_node} = $cluster->get_tree_ref;
    croak "No valid tree to plot\n" if !$self->{tree_node};
    
    $self->{tree_node_name_hash}
      = $self->{tree_node}->get_names_of_all_descendants_and_self;

    $self->{element_to_cluster}  = {};
    $self->{selected_list_index} = {};
    $self->set_cluster_colour_mode( value=>'palette' );
    $self->{recolour_nodes}      = undef;
    $self->set_processed_nodes (undef);

    #  number the nodes if needed
    if (! defined $self->{tree_node}->get_value ('TERMINAL_NODE_FIRST')) {
        $self->{tree_node}->number_terminal_nodes;
    }

    my $terminal_nodes_ref = $cluster->get_terminal_nodes();
    $self->{num_leaves}    = scalar (keys %{$terminal_nodes_ref});
    $self->{border_ht}     = $self->{num_leaves} * BORDER_HT;
    $self->{terminal_elements} = $cluster->get_tree_ref->get_terminal_elements();

    $self->{num_nodes} = $cluster->get_node_count;

    # Initialise Y coordinates
    $self->initYCoords($self->{tree_node});

    # Make slider
    $self->make_slider();

    # draw
    $self->set_plot_mode($plot_mode);

    # Initialise map analysis-selection comboboxen
    if ($self->{map_list_combo}) {
        $self->setup_map_list_model( scalar $self->{tree_node}->get_hash_lists() );
    }

    # TODO: Abstract this properly
    if (exists $self->{map_lists_ready_cb}) {
        $self->{map_lists_ready_cb}->($self->get_map_lists());
    }

    return;
}

sub clear {
    my $self = shift;

    $self->clear_highlights;
    if ($self->{cluster}) {
        $self->zoom_fit;  #  reset any zooming so we don't wreck any new tree plots
    }



    $self->{node_lines} = {};

    $self->clear_node_colours();
    
    delete $self->{unscaled_width};
    delete $self->{unscaled_height};
    delete $self->{tree_node};
    delete $self->{last_render_props_tree};
    delete $self->{last_render_props_graph};

    if ($self->{lines_group}) {
        $self->{lines_group}->destroy();
    }
    if ($self->{graph_group}) {
        $self->{graph_group}->destroy();
    }
    if ($self->{slider}) {
        $self->{slider}->hide;
    }
    if ($self->{graph_slider}) {
        $self->{graph_slider}->hide;
    }

    return;
}

# (re)draws the tree (...every time canvas is resized)
sub render_tree {
    my $self = shift;
    my $tree = $self->{tree_node};

    return if !($self->{render_width} && $self->{unscaled_width});

    my $render_props_tree = join ',', (
        $self->{unscaled_width},
        $self->{unscaled_height},
        $self->{render_width},
        $self->{render_height},
        $self->{length_func},
        $self->get_branch_line_width,
    );

    #  don't redraw needlessly
    return if $render_props_tree eq ($self->{last_render_props_tree} // '');
    $self->{last_render_props_tree} = $render_props_tree;

    #say $render_props_tree;
    
    # Remove any highlights. The lines highlightened are destroyed next,
    # and may cause a crash when they get unhighlighted
    $self->clear_highlights;

    $self->{node_lines} = {};

    # Delete any old nodes
    $self->{lines_group}->destroy() if $self->{lines_group};
    $self->{root_circle}->destroy() if $self->{root_circle};

    # Make group so we can transform everything together
    my $lines_group = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Group',
        x => 0,
        y => 0
    );
    $self->{lines_group} = $lines_group;

    my $legend = $self->get_legend;
    my $legend_width = $legend ? $legend->get_width : 0;
    
    # Scaling values to make the rendered tree render_width by render_height
    $self->{length_scale}
      = ($self->{render_width} - $legend_width)
        / ($self->{unscaled_width}  || 1);
    $self->{height_scale}
      = $self->{render_height}
      / ($self->{unscaled_height} || 1);

    #print "[Dendrogram] Length scale = $self->{length_scale} Height scale = $self->{height_scale}\n";

    # Recursive draw
    my $length_func = $self->{length_func};
    my $root_offset = $self->{render_width}
                      - $legend_width
                      #- $root_circ_diameter  #  using here causes issues with zoom and graph
                      - (  $self->{border_len}
                         + $self->{neg_len}
                         )
                      * $self->{length_scale};

    $self->draw_tree (
        root_offset => $root_offset,
        length_func => $length_func,
        length_scale => $self->{length_scale},
        height_scale => $self->{height_scale},
    );

    # Draw a circle to mark out the root node
    my $root_y = $tree->get_value('_y') * $self->{height_scale};
    my $root_circ_diameter = 0.5 * $self->{border_len} * $self->{length_scale};
    $self->{root_circle} = Gnome2::Canvas::Item->new (
        $self->{lines_group},
        'Gnome2::Canvas::Ellipse',
        x1 => $root_offset,
        y1 => $root_y + $root_circ_diameter / 2,
        x2 => $root_offset + $root_circ_diameter,
        y2 => $root_y - $root_circ_diameter / 2,
        fill_color => 'brown'
    );
    # Hook up the root-circle to the root!
    $self->{root_circle}->signal_connect_swapped (event => \&on_event, $self);
    $self->{root_circle}->{node} =  $tree; # Remember the root (for hovering, etc...)

    $lines_group->lower_to_bottom();
    $self->{root_circle}->lower_to_bottom();
    $self->{back_rect}->lower_to_bottom();

    if (0) {
        # Spent ages on this - not working - NO IDEA WHY!!

        # Draw an equilateral triangle to mark out the root node
        # Vertex pointing at the root, the up-down side half border_len behind
        my $perp_height = 0.5 * $self->{length_scale} *  $self->{border_len} / 1.732;  # 1.723 ~ sqrt(3)
        my $triangle_path = Gnome2::Canvas::PathDef->new;
        $triangle_path->moveto($root_offset, $root_y);
        $triangle_path->lineto($root_offset - 0.5 * $self->{border_len}, $root_y + $perp_height);
        $triangle_path->lineto($root_offset - 0.5 * $self->{border_len}, $root_y - $perp_height);
        $triangle_path->closepath();

        my $triangle = Gnome2::Canvas::Item->new (  $lines_group,
                                                    "Gnome2::Canvas::Shape",
                                                    fill_color => "green",
                                                    );
        $triangle->set_path_def($triangle_path);
    }

    #$self->restore_line_colours();

    return;
}

##########################################################
# The graph
# Shows what percentage of nodes lie to the left
##########################################################

sub render_graph {
    my $self = shift;
    my $lengths = $self->{total_lengths_array};

    return if !($self->{render_width} && $self->{unscaled_width});

    my $graph_height_units = $self->{graph_height_px};
    $self->{graph_height_units} = $graph_height_units;

    my $render_props_graph = join ',', (
        #$self->{graph_height_px},
        #$self->{render_width},
        $self->{unscaled_width},
        $self->{unscaled_height},
        $self->{render_width},
        $self->{render_height},
        $self->{length_func}
    );

    return if $render_props_graph eq ($self->{last_render_props_graph} // '');
    $self->{last_render_props_graph} = $render_props_graph;

    #say $render_props_graph;

    # Delete old lines
    if ($self->{graph_group}) {
        $self->{graph_group}->destroy();
    }

    # Make group so we can transform everything together
    my $graph_group = Gnome2::Canvas::Item->new (
        $self->{graph}->root,
        'Gnome2::Canvas::Group',
        x => 0,
        y => 0
    );
    $graph_group->lower_to_bottom();
    $self->{graph_group} = $graph_group;

    # Draw the graph from right-to-left
    #  starting from the top of the tree
    # Note: "length" here usually means length to the right of the node (towards root)
    my $max_len_func = $self->{max_length_func};
    my $start_length = 0;
    my $start_index  = 0;
    my $legend_width = 0;
    if (my $legend = $self->get_legend) {
        $legend_width = $legend->get_width;
    }
    my $current_x = $self->{render_width}
                    - $legend_width
                    - ($self->{border_len}
                       + $self->{neg_len}
                       )
                    * $self->{length_scale}
                    ;
    my $previous_y;
    my $y_offset; # this puts the lowest y-value at the bottom of the graph - no wasted space

    #my @num_lengths = map { $_->get_value('total_length_gui') } @$lengths;
    #print "[render_graph] lengths: @num_lengths\n";

    #for (my $i = 0; $i <= $#{$lengths}; $i++) {
  NODE:
    foreach my $i (0 .. $#{$lengths}) {

        my $this_length = $max_len_func->($lengths->[$i]) * $self->{length_scale};

        # Start a new segment. We do this if since a few nodes can "line up" and thus have the same length
        next NODE if $this_length <= $start_length;

        my $segment_length = ($this_length - $start_length);
        $start_length = $this_length;

        # Line height proportional to the percentage of nodes to the left of this one
        # At the start, it is max to give value zero - the y-axis goes top-to-bottom
        $y_offset = $y_offset || $#{$lengths};
        my $segment_y = ($i * $graph_height_units) / $y_offset;
        #print "[render_graph] segment_y=$segment_y current_x=$current_x\n";

        my $hline =  Gnome2::Canvas::Item->new (
            $graph_group,
            'Gnome2::Canvas::Line',
            points          => [$current_x - $segment_length, $segment_y, $current_x, $segment_y],
            fill_color_gdk  => COLOUR_BLACK,
            width_pixels    => NORMAL_WIDTH
        );

        # Now the vertical line
        if ($previous_y) {
            my $vline = Gnome2::Canvas::Item->new (
                $graph_group,
                'Gnome2::Canvas::Line',
                points          => [$current_x, $previous_y, $current_x, $segment_y],
                fill_color_gdk  => COLOUR_BLACK,
                width_pixels    => NORMAL_WIDTH
            );
        }

        $previous_y = $segment_y;
        $current_x -= $segment_length;

    }

    $self->{graph}->set_scroll_region(0, 0, $self->{render_width}, $graph_height_units);

    return;
}

sub resize_background_rect {
    my $self = shift;

    $self->{back_rect}->set(
        x2 => $self->{render_width},
        y2 => $self->{render_height},
    );
    $self->{back_rect}->lower_to_bottom();

    return;
}

##########################################################
# Drawing
##########################################################

sub draw_tree {
    my ($self, %args) = @_;
    my $root_offset  = $args{root_offset};
    my $length_func  = $args{length_func}
                     // $self->{length_func};
    my $length_scale = $args{length_scale};
    my $height_scale = $args{height_scale};
    my $line_width   = $args{line_width}
                     // $self->get_branch_line_width;
    my $dist_to_root_func = $args{dist_to_root_func}
                         // $self->{dist_to_root_func};

    my $tree_ref  = $self->{cluster};
    my $node_hash = $tree_ref->get_node_hash;
    
    #my $progress = Biodiverse::Progress->new (
    #    text => 'Plotting tree',
    #    gui_only => 1,
    #);
    my $num_nodes = keys %$node_hash;
    my $i = 0;
    
    say "Plotting tree with $num_nodes branches";

    foreach my $node_name (keys %$node_hash) {
        #  no progress - profiling suggests it chews up
        #  huge amounts of time on redrawing
        #$i++;
        #$progress->update (
        #    "Plotting tree node $i of $num_nodes",
        #    $i / $num_nodes,
        #);
        
        my $node = $node_hash->{$node_name};
        my $path_length  = $dist_to_root_func->($node);

        my $end_xpos   = $root_offset - $path_length * $length_scale;
        my $start_xpos = $end_xpos + $length_func->($node) * $length_scale;

        my $y = $node->get_value('_y') * $height_scale;
        my $colour_ref = $self->get_node_colour_aa ($node_name) || DEFAULT_LINE_COLOUR;

        # Draw our horizontal line
        my $line = $self->draw_line(
            [$start_xpos, $y, $end_xpos, $y],
            $colour_ref,
            $line_width,
        );
        $line->signal_connect_swapped (event => \&on_event, $self);
        $line->{node} =  $node; # Remember the node (for hovering, etc...)
    
        # Remember line (for colouring, etc...)
        $self->{node_lines}->{$node_name} = $line;
    
        my ($ymin, $ymax);
        #  should be able to use first and last child
        foreach my $child ($node->get_children) {
            my $child_y = $child->get_value ('_y') * $height_scale;
            $ymin = $child_y if ( (not defined $ymin) || $child_y < $ymin);
            $ymax = $child_y if ( (not defined $ymax) || $child_y > $ymax);
        }
    
        # Vertical line
        if (defined $ymin) { 
            $self->draw_line(
                [$end_xpos, $ymin, $end_xpos, $ymax],
                DEFAULT_LINE_COLOUR_VERT,
                NORMAL_WIDTH,
            );
        }
    }
    #return $y;
    
    return;
}

sub draw_line {
    my ($self, $vertices, $colour_ref, $line_width) = @_;

    $line_width //= NORMAL_WIDTH;

    my $line_style = ($vertices->[0] >= $vertices->[2])
      ? 'solid'
      : 'on-off-dash';

    return Gnome2::Canvas::Item->new (
        $self->{lines_group},
        'Gnome2::Canvas::Line',
        points => $vertices,
        fill_color_gdk => $colour_ref,
        line_style     => $line_style,
        width_pixels   => $line_width,
    );
}

##########################################################

# Call callback functions and mark elements under the node
# If clicked on, marks will be retained. If only hovered, they're
# cleared when user leaves node
sub on_event {
    my ($self, $event, $line) = @_;

    my $type = $event->type;

    # If not in click mode, pass through button events to background
    return 0 if ($event->type =~ m/^button-/ && $self->{drag_mode} ne 'click');

    my $node = $line->{node};
    my $f;

    if ($event->type eq 'enter-notify') {
        #print "enter - " . $node->get_name() . "\n";

        # Call client-defined callback function
        if (defined $self->{hover_func}) {
            $f = $self->{hover_func};
            $f->($node);
        }

        # Call client-defined callback function
        if (defined $self->{highlight_func}
            and $self->{use_highlight_func}
            and not $self->{click_line}) {

            $f = $self->{highlight_func};
            $f->($node);
        }

        #if (not $self->{click_line}) {
            #$self->{hover_line}->set(fill_color => 'black') if $self->{hover_line};
            #$line->set(fill_color => 'red') if (not $self->{click_line});
            #$self->{hover_line} = $line;
        #}

        # Change the cursor if we are in select mode
        if (!$self->{cursor}) {
            my $cursor;
            if ($self->in_multiselect_clear_mode) {
                $cursor = $self->get_hover_clear_cursor;
            }
            else {
                $cursor = Gtk2::Gdk::Cursor->new(HOVER_CURSOR);
            }
            $self->{canvas}->window->set_cursor($cursor);
        }
    }
    elsif ($event->type eq 'leave-notify') {
        #print "leave - " . $node->get_name() . "\n";

        # Call client-defined callback function
        if (defined $self->{hover_func}) {
            $f = $self->{hover_func};
            $f->(undef);
        }

        # Call client-defined callback function
        if (defined $self->{highlight_func} and not $self->{click_line}) {
            $f = $self->{highlight_func};
            $f->(undef);
        }

        #$line->set(fill_color => 'black') if (not $self->{click_line});

        # Change cursor back to default
        $self->{canvas}->window->set_cursor($self->{cursor});

    }
    elsif ($event->type eq 'button-press') {

        # If middle-click or control-click call Clustering tab's callback (show/Hide popup dialog)
        if ($event->button == 2 || ($event->button == 1 and $event->state >= [ 'control-mask' ]) ) {
            if (defined $self->{ctrl_click_func}) {
                $f = $self->{ctrl_click_func};
                $f->($node);
            }
        }
        # Left click - colour nodes
        elsif ($event->button == 1) {
            $self->do_colour_nodes_below($node);
            if (defined $self->{click_func}) {
                $f = $self->{click_func};
                $f->($node);
            }
            $self->increment_multiselect_colour;
        }
        # Right click - set marks semi-permanently
        elsif ($event->button == 3) {

            # Restore previously clicked/hovered line
            #$self->{click_line}->set(fill_color => 'black') if $self->{click_line};
            #$self->{hover_line}->set(fill_color => 'black') if $self->{hover_line};

            # Call client-defined callback function
            if (defined $self->{highlight_func}) {
                $f = $self->{highlight_func};
                $f->($node);
            }
            #$line->set(fill_color => 'red');
            $self->{click_line} = $line;
        }
    }

    return 1;    
}

# Implements panning the grid
sub on_background_event {
    my ($self, $event, $item) = @_;

    # Do everything with left clck now.
    if ($event->type =~ m/^button-/ && $event->button != 1) {
        return;
    }

    if ($event->type eq 'enter-notify') {
        $self->{page}->set_active_pane('dendrogram');
    }
    elsif ($event->type eq 'leave-notify') {
        $self->{page}->set_active_pane('');
    }
    elsif ( $event->type eq 'button-press') {
        if ($self->{drag_mode} eq 'click') {
            if (defined $self->{click_func}) {
                my $f = $self->{click_func};
                $f->();
            }
        }
        elsif ($self->{drag_mode} eq 'pan') {
            ($self->{drag_x}, $self->{drag_y}) = $event->coords;

            # Grab mouse
            $item->grab (
                [qw/pointer-motion-mask button-release-mask/],
                Gtk2::Gdk::Cursor->new ('fleur'),
                $event->time
            );
            $self->{dragging} = 1;
            $self->{dragged}  = 0;
        }
        elsif ($self->{drag_mode} eq 'select') {
            my ($x, $y) = $event->coords;

            $self->{sel_x} = $x;
            $self->{sel_y} = $y;

            # Grab mouse
            $item->grab (
                [qw/pointer-motion-mask button-release-mask/],
                Gtk2::Gdk::Cursor->new ('fleur'),
                $event->time,
            );
            $self->{selecting} = 1;

            $self->{sel_rect} = Gnome2::Canvas::Item->new (
                $self->{canvas}->root,
                'Gnome2::Canvas::Rect',
                x1 => $x,
                y1 => $y,
                x2 => $x,
                y2 => $y,

                fill_color_gdk    => undef,
                outline_color_gdk => COLOUR_BLACK,
                width_pixels      => 0,
            );
        }
    }
    elsif ( $event->type eq 'button-release') {
        if ($self->{drag_mode} eq 'pan') {
            $item->ungrab ($event->time);
            $self->{dragging} = 0;

            # FIXME: WHAT IS THIS (obsolete??)
            # If clicked without dragging, we also remove the element mark (see onEvent)
            if (not $self->{dragged}) {
                #$self->mark_elements(undef);
                if ($self->{click_line}) {
                    $self->{click_line}->set(fill_color => 'black');
                }
                $self->{click_line} = undef;
            }
        }
        elsif ($self->{selecting}) {
            $self->{sel_rect}->destroy;
            delete $self->{sel_rect};
            $item->ungrab ($event->time);
            $self->{selecting} = 0;

            # Establish the selection
            my ($x_start, $y_start) = ($self->{sel_x}, $self->{sel_y});
            my ($x_end, $y_end) = $event->coords;

            if (defined $self->{select_func}) {
                my $f = $self->{select_func};
                $f->([$x_start, $y_start, $x_end, $y_end]);
            }
        }
    }
    elsif ( $event->type eq 'motion-notify') {
        my ($x, $y) = $event->coords;

        if ($self->{dragging}) {
            # Work out how much we've moved away from last time
            my ($dx, $dy) = ($x - $self->{drag_x}, $y - $self->{drag_y});
            $self->{drag_x} = $x;
            $self->{drag_y} = $y;

            # Convert into scaled coords
            $self->{centre_x} = $self->{centre_x} * $self->{length_scale};
            $self->{centre_y} = $self->{centre_y} * $self->{height_scale};

            # Scroll
            $self->{centre_x} = $self->clamp (
                $self->{centre_x} - $dx,
                $self->{width_px} / 2,
                $self->{render_width} - $self->{width_px} / 2,
            ) ;
            $self->{centre_y} = $self->clamp (
                $self->{centre_y} - $dy,
                $self->{height_px} / 2,
                $self->{render_height} - $self->{height_px} / 2,
            );

            # Convert into world coords
            $self->{centre_x} = $self->{centre_x} / $self->{length_scale};
            $self->{centre_y} = $self->{centre_y} / $self->{height_scale};

            #print "[Pan] panned\n";
            $self->centre_tree();
            $self->update_scrollbars();

            $self->{dragged} = 1;
        }
        elsif ($self->{selecting}) {
            # Resize selection rectangle
            if ($self->{selecting}) {
                $self->{sel_rect}->set(x2 => $x, y2 => $y);
            }
        }
    }

    return 0;    
}

#FIXME: we render our canvases twice!! 
#  here and in the main dendrogram's on_resize()
#  as far as I remember, this was due to issues keeping both graphs in sync
sub on_graph_resize {
    my ($self, $size) = @_;
    $self->{graph_height_px} = $size->height;

    if (exists $self->{unscaled_width}) {
        $self->render_tree;
        $self->render_graph;
        $self->reposition_sliders;

        $self->centre_tree;
        $self->reposition_sliders;
        $self->setup_scrollbars;
    }

    return;
}

sub on_resize {
    my ($self, $size)  = @_;
    $self->{width_px}  = $size->width;
    $self->{height_px} = $size->height;

    #  for debugging
    #$self->{render_width} = $self->{width_px};
    #$self->{render_height} = $self->{height_px};

    my $resize_bk = 0;
    if ($self->{render_width} == 0 || $self->get_zoom_fit_flag) {
        $self->{render_width} = $size->width;
        $resize_bk = 1;
    }
    if ($self->{render_height} == 0 || $self->get_zoom_fit_flag) {
        $self->{render_height} = $size->height;
        $resize_bk = 1;
    }

    if ($resize_bk) {
        $self->resize_background_rect;
    }

    if (exists $self->{unscaled_width}) {

        #print "[on_resize] width px=$self->{width_px} render=$self->{render_width}\n";
        #print "[on_resize] height px=$self->{height_px} render=$self->{render_height}\n";

        $self->render_tree();
        $self->render_graph();
        $self->centre_tree();

        $self->reposition_sliders();

        $self->setup_scrollbars();

        # Set visible region
        $self->{canvas}->set_scroll_region(0, 0, $size->width, $size->height);
    }
    
    $self->update_legend;

    return;
}

sub clamp {
    my ($self, $val, $min, $max) = @_;
    return $min if $val < $min;
    return $max if $val > $max;
    return $val;
}

##########################################################
# Scrolling
##########################################################
sub setup_scrollbars {
    my $self = shift;
    return if not $self->{render_width};

    #say "[setupScrolllbars] render w:$self->{render_width} h:$self->{render_height}";
    #say "[setupScrolllbars]   px   w:$self->{width_px} h:$self->{height_px}";

    $self->{hadjust}->upper( $self->{render_width} );
    $self->{vadjust}->upper( $self->{render_height} );

    $self->{hadjust}->page_size( $self->{width_px} );
    $self->{vadjust}->page_size( $self->{height_px} );

    $self->{hadjust}->page_increment( $self->{width_px} / 2 );
    $self->{vadjust}->page_increment( $self->{height_px} / 2 );

    $self->{hadjust}->changed;
    $self->{vadjust}->changed;

    return;
}

sub update_scrollbars {
    my ($self, $scrollx, $scrolly) = @_;

    #say "[update_scrollbars] centre x:$self->{centre_x} y:$self->{centre_y}";
    #say "[update_scrollbars] scale  x:$self->{length_scale} y:$self->{height_scale}";

    $self->{hadjust}->set_value($self->{centre_x} * $self->{length_scale} - $self->{width_px} / 2);
    #say "[update_scrollbars] set hadjust to "
    #    . ($self->{centre_x} * $self->{length_scale} - $self->{width_px} / 2);

    $self->{vadjust}->set_value($self->{centre_y} * $self->{height_scale} - $self->{height_px} / 2);
    #say "[update_scrollbars] set vadjust to "
    #    . ($self->{centre_y} * $self->{height_scale} - $self->{height_px} / 2);

    return;
}

sub onHScroll {
    my $self = shift;

    if (not $self->{dragging}) {
        my $h = $self->{hadjust}->get_value;
        $self->{centre_x} = ($h + $self->{width_px} / 2) / $self->{length_scale};

        #say "[onHScroll] centre x:$self->{centre_x}";
        $self->centre_tree;
    }

    return;
}

sub onVScroll {
    my $self = shift;

    if (not $self->{dragging}) {
        my $v = $self->{vadjust}->get_value;
        $self->{centre_y} = ($v + $self->{height_px} / 2) / $self->{height_scale};

        #say "[onVScroll] centre y:$self->{centre_y}";
        $self->centre_tree;
    }

    return;
}

sub centre_tree {
    my $self = shift;
    return if !defined $self->{lines_group};
    return if !$self->{cluster}->get_total_tree_length;

    my $xoffset = $self->{centre_x} * $self->{length_scale} - $self->{width_px} / 2;
    my $yoffset = $self->{centre_y} * $self->{height_scale} - $self->{height_px} / 2;

    #say "[centre_tree] scroll xoffset=$xoffset  yoffset=$yoffset";

    my $matrix = [1,0,0,1, -1 * $xoffset, -1 * $yoffset];
    eval {$self->{lines_group}->affine_absolute($matrix)};
    $self->{back_rect}->affine_absolute($matrix);

    # for the graph only move sideways
    $matrix->[5] = 0;
    eval {$self->{graph_group}->affine_absolute($matrix)};

    $self->reposition_sliders();

    return;
}

##########################################################
# Zoom
##########################################################

sub zoom_in {
    my $self = shift;

    $self->{render_width}  = $self->{render_width} * 1.5;
    $self->{render_height} = $self->{render_height} * 1.5;

    $self->set_zoom_fit_flag(0);
    $self->post_zoom();

    return;
}

sub zoom_out {
    my $self = shift;

    $self->{render_width}  = $self->{render_width} / 1.5;
    $self->{render_height} = $self->{render_height} / 1.5;

    $self->set_zoom_fit_flag (0);
    $self->post_zoom();

    return;
}

sub zoom_fit {
    my $self = shift;
    $self->{render_width}  = $self->{width_px};
    $self->{render_height} = $self->{height_px};
    $self->set_zoom_fit_flag(1);
    $self->post_zoom();

    return;
}

sub set_zoom_fit_flag {
    my ($self, $zoom_fit) = @_;
    
    $self->{zoom_fit} = $zoom_fit;
}

sub get_zoom_fit_flag {
    my ($self) = @_;
    
    return $self->{zoom_fit};
}

sub post_zoom {
    my $self = shift;

    return if !$self->{cluster};

    $self->render_tree();
    $self->render_graph();
    $self->reposition_sliders();
    $self->resize_background_rect();

    # Convert into scaled coords
    $self->{centre_x} *= $self->{length_scale};
    $self->{centre_y} *= $self->{height_scale};

    # Scroll
    $self->{centre_x} = $self->clamp(
        $self->{centre_x},
        $self->{width_px} / 2,
        $self->{render_width} - $self->{width_px} / 2,
    );
    $self->{centre_y} = $self->clamp(
        $self->{centre_y},
        $self->{height_px} / 2,
        $self->{render_height} - $self->{height_px} / 2,
    );

    # Convert into world coords
    $self->{centre_x} /= $self->{length_scale};
    $self->{centre_y} /= $self->{height_scale};

    $self->centre_tree();
    $self->setup_scrollbars();
    $self->update_scrollbars();

    return;
}


sub get_hover_clear_cursor {
    my $self = shift;

    my $cursor = $self->{cursor_hover_clear};
    return $cursor if $cursor;

    my $icon_name = 'edit-clear';

    my $ic = Gtk2::IconTheme->new();
    my $pixbuf = eval {$ic->load_icon($icon_name, 16, 'no-svg')};
    if ($@) {
        warn $@;
    }
    else {
        my $window  = $self->{canvas}->window;
        my $display = $window->get_display;
        $cursor = Gtk2::Gdk::Cursor->new_from_pixbuf($display, $pixbuf, 0, 0);
        $self->{cursor_hover_clear} = $cursor;
    }

    return $cursor;
}

###  COPIED FROM grid.pm
sub get_legend {
    my $self = shift;
    return $self->{legend};
}

sub set_legend {
    my ($self, $legend) = @_;
    croak "legend arg not passed" if !defined $legend;
    $self->{legend} = $legend;
}

# Update the position and/or mode of the legend.
sub update_legend {
    my $self = shift;
    my $legend = $self->get_legend;
    
    return if !$legend;
    
    if ($self->{width_px} && $self->{height_px}) {
        $legend->make_rect;
        $legend->reposition($self->{width_px}, $self->{height_px});
    }
    
    return;
}

sub set_legend_mode {
    my $self = shift;
    my $mode = shift;

    my $legend = $self->get_legend;
    $legend->set_mode($mode);
    $self->colour_cells();
    
    return;
}

sub set_legend_gt_flag {
    my $self = shift;
    my $flag = shift;

    my $legend = $self->get_legend;
    $legend->set_gt_flag($flag);

    return;
}

sub set_legend_lt_flag {
    my $self = shift;
    my $flag = shift;

    my $legend = $self->get_legend;
    $legend->set_lt_flag($flag);

    return;
}


##########################################################
# Misc
##########################################################

sub numerically {$a <=> $b};

# Resize background rectangle which is dragged for panning
sub max {
    return ($_[0] > $_[1]) ? $_[0] : $_[1];
}

1;
