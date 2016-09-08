package Biodiverse::GUI::Dendrogram;

use 5.010;
use strict;
use warnings;
no warnings 'recursion';
#use Data::Dumper;
use Carp;

use Time::HiRes qw /gettimeofday time/;

use Scalar::Util qw /weaken blessed/;
use List::Util 1.29 qw /min pairs/;
use List::MoreUtils qw /firstidx/;

use Gtk2;
use Gnome2::Canvas;
use POSIX; # for ceil()

our $VERSION = '1.99_005';

use Biodiverse::GUI::GUIManager;
use Biodiverse::TreeNode;

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
        use_slider_to_select_nodes => 1,
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
        weaken $self->{parent_tab};
        #  fixme
        #  there is too much back-and-forth between the tab and the tree
        $self->{parent_tab}->set_undef_cell_colour(COLOUR_LIST_UNDEF);  
    }


    # starting off with the "clustering" view, not a spatial analysis
    $self->{sp_list}  = undef;
    $self->{sp_index} = undef;
    bless $self, $class;
    
    foreach my $widget_name (qw /selector_toggle selector_colorbutton/) {
        eval {
            $self->{$widget_name}
              = $self->{parent_tab}->{xmlPage}->get_object($widget_name);
        };
    }

    #  also initialises it
    $self->increment_sequential_selection_colour(1);

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

    # Create background rectange to receive mouse events for panning
    my $rect = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        y1 => 0,
        x2 => 1,
        y2 => 1,
        fill_color_gdk => COLOUR_WHITE
        #fill_color => "blue",
    );

    $rect->lower_to_bottom();
    $self->{canvas}->root->signal_connect_swapped (event => \&on_background_event, $self);
    $self->{back_rect} = $rect;

    # Process changes for the map
    if ($map_index_combo) {
        $map_index_combo->signal_connect_swapped(
            changed => \&on_combo_map_index_changed,
            $self,
        );
    }
    if ($map_list_combo) {
        $map_list_combo->signal_connect_swapped (
            changed => \&on_map_list_combo_changed,
            $self
        );
    }

    $self->{drag_mode} = 'click';

    # Labels::initMatrixGrid will set $self->{page} (hacky}

    return $self;
}


sub get_tree_object {
    my $self = shift;
    return $self->{cluster};
}

#  
#sub DESTROY {
#    my $self = shift;
#    
#    no warnings "uninitialized";
#    
#    warn "[Dendrogram] Starting object cleanup\n";
#    
#    foreach my $key (keys %$self) {
#        if ((ref $self->{$key}) =~ '::') {
#            warn "Deleting $key - $self->{$key}\n";
#            $self->{$key}->DESTROY if $self->{$key}->can ('DESTROY');
#        }
#        delete $self->{$key};
#    }
#    $self = undef;
#    
#    warn "[Dendrogram] Completed object cleanup\n";
#}

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
    my $self = shift;
    $self->{num_clusters} = shift || 1;
    # apply new setting
    $self->recolour();
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

    #$self->{last_slide_time} = time;
    return;
}

sub toggle_use_slider_to_select_nodes {
    my $self = shift;

    $self->{use_slider_to_select_nodes} = ! $self->{use_slider_to_select_nodes};

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
            # (sequential only has one node)
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

    my $list_name         = $self->{analysis_list_name};
    my $list_index        = $self->{analysis_list_index};
    my $analysis_min      = $self->{analysis_min};
    my $analysis_max      = $self->{analysis_max};
    my $terminal_elements = $self->{terminal_elements};

    my $parent_tab = $self->{parent_tab};
    my $colour_for_undef = $parent_tab->get_undef_cell_colour;

    my $cluster_colour_mode = $self->{cluster_colour_mode};
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
        my $colour_for_sequential = $self->get_current_sequential_colour;

        # sets colours according to sequential palette
        $colour_callback = sub {
            my $elt = shift;

            return -1
              if    $terminal_element_subset
                 && !exists $terminal_element_subset->{$elt};

            my $cluster_node = $self->{element_to_cluster}{$elt};

            return -1 if !$cluster_node;

            return $colour_for_sequential || COLOUR_OUTSIDE_SELECTION;
            #COLOUR_PALETTE_OVERFLOW;
        };
    }
    elsif ($cluster_colour_mode eq 'list-values') {
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

                return $map->get_colour ($val, $analysis_min, $analysis_max);
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

    if ($cluster_colour_mode eq 'list-values') {
        $map->set_legend_min_max($analysis_min, $analysis_max);
    }

    return;
}

sub in_multiselect_mode {
    my $self = shift;
    return $self->{cluster_colour_mode} eq 'sequential';
}


sub clear_sequential_colours_from_plot {
    my $self = shift;

    return if !$self->in_multiselect_mode;

    #  temp override, as sequential colour mode has side effects
    local $self->{cluster_colour_mode} = 'palette';
    
    my $colour_store = $self->get_sequential_colour_store;
    if (@$colour_store) {
        my $tree = $self->get_tree_object;
        my @coloured_nodes = map {$tree->get_node_ref (node => $_->[0])} @$colour_store;
        #  clear current colouring
        #$self->recolour_cluster_elements;
        $self->recolour_cluster_lines (\@coloured_nodes);
    }

    return;
}

#  later we can get this from a cached value on the tree object
sub get_sequential_colour_store {
    my $self = shift;
    my $tree = $self->get_tree_object;
    my $store = $tree->get_cached_value_dor_set_default_aa ('GUI_MULTISELECT_COLOUR_STORE', []);
    #my $store = ($self->{sequential_colour_store} //= []);
    return $store;
}

sub store_sequential_colour {
    my $self = shift;
    my @pairs = @_;  #  usually get only one name/colour pair

    my $store = $self->get_sequential_colour_store;

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

        #  we get double triggers for some reason due to a
        #  higher sub being called twice for each colour event
        if (!scalar @$store) {
            push @$store, $pair;
            next PAIR;
        }
        
        #  clear pre-existing (assumes we don't insert dups from other code locations)
        my $idx = firstidx {$_->[0] eq $pair->[0]} @$store;
        if ($idx != -1) {
            splice @$store, $idx, 1;
        }
        push @$store, $pair;
    }

    return;
}

sub get_current_sequential_colour {
    my $self = shift;

    my $colour;
    eval {
        if (!$self->{selector_toggle}->get_active) {
            $colour = $self->{selector_colorbutton}->get_color;
        }
    };

    return $colour;
}

sub set_current_sequential_colour {
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

sub increment_sequential_selection_colour {
    my $self = shift;
    my $force_increment = shift;
    
    return if !$force_increment
            && !$self->in_multiselect_mode;

    return 
      if    $self->{selector_toggle}
         && $self->{selector_toggle}->get_active;

    my $colour = $self->get_current_sequential_colour;

    my @colours = $self->get_gdk_colors_colorbrewer9;

    if (my $last_colour = $self->{last_sequential_colour}) {
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
    
    $self->{last_sequential_colour} = $colour;
    
    return;
}

sub get_colour_not_in_tree {
    my $self = shift;
    
    my $colour = eval {$self->{parent_tab}->get_excluded_cell_colour} || COLOUR_NOT_IN_TREE;

    return $colour;
}


# Colours the dendrogram lines with palette colours
sub recolour_cluster_lines {
    my $self = shift;
    my $cluster_nodes = shift;

    my ($colour_ref, $line, $list_ref, $val);
    my %coloured_nodes;

    my $map = $self->{map};
    my $list_name    = $self->{analysis_list_name};
    my $list_index   = $self->{analysis_list_index};
    my $analysis_min = $self->{analysis_min};
    my $analysis_max = $self->{analysis_max};
    my $colour_mode  = $self->{cluster_colour_mode};

    foreach my $node_ref (@$cluster_nodes) {

        my $node_name = $node_ref->get_name;

        if ($colour_mode eq 'palette') {
            $colour_ref = $self->{node_palette_colours}{$node_name} || COLOUR_RED;
        }
        elsif ($self->in_multiselect_mode) {
            $colour_ref = $self->get_current_sequential_colour || COLOUR_BLACK;
            if ($colour_ref) {  #  should always be true, but just in case...
                $self->store_sequential_colour ($node_name, $colour_ref);
            }
        }
        elsif ($colour_mode eq 'list-values') {

            $list_ref = $node_ref->get_list_ref (list => $list_name);
            $val = defined $list_ref
              ? $list_ref->{$list_index}
              : undef;  #  allows for missing lists

            $colour_ref = defined $val
              ? $map->get_colour ($val, $analysis_min, $analysis_max)
              : undef;
        }
        else {
            die "unknown colouring mode $colour_mode\n";
        }

        $self->{node_colours_cache}{$node_name} = $colour_ref;
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
        foreach my $child_ref (values %{$node_ref->get_all_descendants (cache => 0)}) {
            $self->colour_line($child_ref, $colour_ref, \%coloured_nodes);
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
                $self->{node_colours_cache}{$node_name} = DEFAULT_LINE_COLOUR;
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
    $self->{node_colours_cache}{$name} = $colour_ref;

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
    $self->{node_colours_cache}{$name} = $colour_ref;

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

    #  add the sequential selector
    $iter = $model->insert(0);
    $model->set($iter, 0, '<i>Cloister</i>');
    
    # Add & select, the "cluster" analysis (distinctive colour for every cluster)
    $iter = $model->insert(0);
    $model->set($iter, 0, '<i>Cluster</i>');
    
    if ($combo) {
        $combo->set_model($model);
        $combo->set_active_iter($iter);
    }

    return;
}

# Provides list of map indices for tab to use as it sees fit.
# Context sensitive on currently selected map list.
sub get_map_indices {
    my $self = shift;
    if (not defined $self->{analysis_list_name}) {
        return [];
    }

    my $list_ref = $self->{tree_node}->get_list_ref(
        list => $self->{analysis_list_name},
    );

    return [keys %$list_ref];
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

        foreach my $key (sort keys %$indices) {
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

    if (   $list ne '<i>Cloister>/i>'
        && !$self->in_multiselect_mode) {
        #  clear the full set?
        
    }

    if ($list eq '<i>Cluster</i>') {
        # Selected cluster-palette-colouring mode
        $self->clear_sequential_colours_from_plot;

        $self->{cluster_colour_mode} = 'palette';

        $self->{parent_tab}->on_clusters_changed;

        $self->recolour_cluster_elements;
        $self->recolour_cluster_lines($self->get_processed_nodes);

        # blank out the index combo
        $self->setup_map_index_model(undef);
    }
    elsif ($list eq '<i>Cloister</i>') {
        #  clear current colouring
        $self->recolour_cluster_elements;
        #$self->recolour_cluster_lines($self->get_processed_nodes);
        $self->recolour_cluster_lines;

        $self->set_num_clusters (1);
        $self->{cluster_colour_mode} = 'sequential';

        my $colour_store = $self->get_sequential_colour_store;

        if (@$colour_store) {
            my $tree = $self->get_tree_object;
            #  copy to avoid infinite recursion,
            #  as the ref is appended in one of the called subs
            my @pairs = @$colour_store;

            #  ensure recolouring works
            $self->map_elements_to_clusters ([map {$tree->get_node_ref (node => $_->[0])} @pairs]);

            foreach my $pair (@pairs) {
                my $node_ref = $tree->get_node_ref (node => $pair->[0]);
                $self->set_current_sequential_colour ($pair->[1]);
                my $elements = $node_ref->get_terminal_elements;
                $self->recolour_cluster_elements ($elements);
                $self->set_processed_nodes ([$node_ref]);  #  clunky - poss needed because we call get_processed_nodes below?
                $self->recolour_cluster_lines($self->get_processed_nodes);
            }
        }
        else {
            $self->recolour_cluster_elements;
            $self->recolour_cluster_lines($self->get_processed_nodes);
        }

        if ($self->{recolour_nodes}) {
            $self->increment_sequential_selection_colour;
        }

        # blank out the index combo
        $self->setup_map_index_model(undef);
    }
    else {
        $self->clear_sequential_colours_from_plot;

        $self->{parent_tab}->on_clusters_changed;

        # Selected analysis-colouring mode
        $self->{analysis_list_name} = $list;

        $self->setup_map_index_model($self->{tree_node}->get_list_ref(list => $list));
        $self->on_combo_map_index_changed;
    }

    return;
}

#  this should be controlled by the parent tab, not the dendrogram
sub on_combo_map_index_changed {
    my $self  = shift;
    my $combo = shift || $self->{map_index_combo};

    my $index = undef;
    my $iter  = $combo->get_active_iter;

    if ($iter) {

        $index = $combo->get_model->get($iter, 0);
        $self->{analysis_list_index} = $index;

        $self->{parent_tab}->on_colour_mode_changed;

        my @minmax = $self->get_plot_min_max_values;
        $self->{analysis_min} = $minmax[0];
        $self->{analysis_max} = $minmax[1];

        #print "[Dendrogram] Setting grid to use (spatial) analysis $analysis\n";
        $self->{cluster_colour_mode} = 'list-values';
        $self->recolour_cluster_elements();

        $self->recolour_cluster_lines($self->get_processed_nodes);
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

        $self->{parent_tab}->recolour;

        my @minmax = $self->get_plot_min_max_values;
        $self->{analysis_min} = $minmax[0];
        $self->{analysis_max} = $minmax[1];

        #print "[Dendrogram] Setting grid to use (spatial) analysis $analysis\n";
        $self->{cluster_colour_mode} = 'list-values';
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

    return;
}

sub get_plot_min_max_values {
    my $self = shift;
    
    my ($min, $max) = ($self->{analysis_min}, $self->{analysis_max});
    if (not defined $min or not defined $max) {
        ($min, $max) = $self->{parent_tab}->get_plot_min_max_values;
    }
    
    my @minmax = ($min, $max);
    
    return wantarray ? @minmax : \@minmax;
}



##########################################################
# Highlighting a path up the tree
##########################################################

# Remove any existing highlights
sub clear_highlights {
    my $self = shift;
    
    # set all nodes to recorded/default colour
    return if !$self->{highlighted_lines};

    my @nodes_remaining
      = ($self->{tree_node}->get_name, keys %{$self->{tree_node}->get_names_of_all_descendants});

    foreach my $node_name (@nodes_remaining) {
        # assume node has associated line
        my $line = $self->{node_lines}->{$node_name};
        next if !$line;
        my $colour_ref = $self->{node_colours_cache}{$node_name} || DEFAULT_LINE_COLOUR;
        $line->set(fill_color_gdk => $colour_ref);
    }
    $self->{highlighted_lines} = undef;

    return;
}

sub highlight_node {
    my ($self, $node_ref, $node_colour) = @_;

    # if first highlight, set all other nodes to grey
    if (! $self->{highlighted_lines}) {
        my @nodes_remaining
          = ($self->{tree_node}->get_name, keys %{$self->{tree_node}->get_names_of_all_descendants});
        foreach my $node_name (@nodes_remaining) {
            # assume node has associated line
            my $line = $self->{node_lines}->{$node_name};
            next if !$line;
            $line->set(fill_color_gdk => COLOUR_GRAY);
        }
    }

    # highlight this node/line by setting black
    my $node_name = $node_ref->get_name;
    #  avoid some unhandled exceptions when the mouse is hovering and the display is under construction
    if (my $line = $self->{node_lines}->{$node_name}) {  
        my $colour_ref = $node_colour || $self->{node_colours_cache}{$node_name} || DEFAULT_LINE_COLOUR;
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
        my @nodes_remaining
          = ($self->{tree_node}->get_name, keys %{$self->{tree_node}->get_names_of_all_descendants});
        foreach my $node_name (@nodes_remaining) {
            # assume node has associated line
            my $line = $self->{node_lines}->{$node_name};
            next if !$line;
            $line->set(fill_color_gdk => COLOUR_GRAY);
        }
    }

    # set path to highlighted colour
    while ($node_ref) {
        my $line = $self->{node_lines}->{$node_ref->get_name};
        my $colour_ref = $node_colour || $self->{node_colours_cache}{$node_ref->get_name} || DEFAULT_LINE_COLOUR;
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
    my @array;
    my $lf = $self->{length_func};

    make_total_length_array_inner($self->{tree_node}, 0, \@array, $lf);

    my %cache;

    # Sort it
    @array = sort {
        ($cache{$a} // do {$cache{$a} = $a->get_value('total_length_gui')})
          <=>
        ($cache{$b} // do {$cache{$b} = $b->get_value('total_length_gui')})
        }
        @array;

    $self->{total_lengths_array} = \@array;

    return;
}

sub make_total_length_array_inner {
    my ($node, $length_so_far, $array, $lf) = @_;

    $node->set_value(total_length_gui => $length_so_far);
    push @{$array}, $node;

    # Do the children
    my $length_total = $lf->($node) + $length_so_far;
    foreach my $child ($node->get_children) {
        make_total_length_array_inner($child, $length_total, $array, $lf);
    }

    return;
}

##########################################################
# Drawing the tree
##########################################################

# whether to plot by 'length' or 'depth'
sub set_plot_mode {
    my ($self, $plot_mode) = @_;

    $self->{plot_mode} = $plot_mode;

    # Work out how to get the "length" based on mode
    if ($plot_mode eq 'length') {
        $self->{length_func}     = \&Biodiverse::TreeNode::get_length;
        $self->{max_length_func} = \&Biodiverse::TreeNode::get_max_total_length;
        $self->{neg_length_func} = \&get_max_negative_length;
    }
    elsif ($plot_mode eq 'depth') {
        $self->{length_func}     = sub { return 1; }; # each node is "1" depth level below the previous one
        $self->{max_length_func} = \&Biodiverse::TreeNode::get_depth_below;
        $self->{neg_length_func} = sub { return 0; };
    }
    #elsif ($plot_mode eq 'range_weighted') {  #  experimental - replaced by method to convert the tree's branch lengths
    #    #  need to get the node range table
    #    my $bd = $self->{basedata_ref};
    #    $self->{length_func}     = sub {my ($node, %args) = @_; return $node->get_length / $node->get_node_range (basedata_ref => $bd)};
    #    $self->{max_length_func} = \&Biodiverse::TreeNode::get_max_total_length;
    #    $self->{neg_length_func} = \&get_max_negative_length;
    #}
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

    $self->{element_to_cluster}  = {};
    $self->{selected_list_index} = {};
    $self->{cluster_colour_mode} = 'palette';
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
    $self->{node_colours_cache} = {};

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

    # Scaling values to make the rendered tree render_width by render_height
    $self->{length_scale} = $self->{render_width}  / ($self->{unscaled_width}  || 1);
    $self->{height_scale} = $self->{render_height} / ($self->{unscaled_height} || 1);

    #print "[Dendrogram] Length scale = $self->{length_scale} Height scale = $self->{height_scale}\n";

    # Recursive draw
    my $length_func = $self->{length_func};
    my $root_offset = $self->{render_width}
                      - ($self->{border_len} + $self->{neg_len})
                      * $self->{length_scale};

    $self->draw_node($tree, $root_offset, $length_func, $self->{length_scale}, $self->{height_scale});

    # Draw a circle to mark out the root node
    my $root_y = $tree->get_value('_y') * $self->{height_scale};
    my $diameter = 0.5 * $self->{border_len} * $self->{length_scale};
    $self->{root_circle} = Gnome2::Canvas::Item->new (
        $self->{lines_group},
        'Gnome2::Canvas::Ellipse',
        x1 => $root_offset,
        y1 => $root_y + $diameter / 2,
        x2 => $root_offset + $diameter,
        y2 => $root_y - $diameter / 2,
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
        $self->{render_width},
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
    my $start_length = $lengths->[0]->get_value('total_length_gui') * $self->{length_scale};
    my $start_index = 0;
    my $current_x = $self->{render_width}
                    - ($self->{border_len}
                       + $self->{neg_len}
                       )
                    * $self->{length_scale}
                    ;
    my $previous_y;
    my $y_offset; # this puts the lowest y-value at the bottom of the graph - no wasted space

    my @num_lengths = map { $_->get_value('total_length_gui') } @$lengths;
    #print "[render_graph] lengths: @num_lengths\n";

    #for (my $i = 0; $i <= $#{$lengths}; $i++) {
    foreach my $i (0 .. $#{$lengths}) {

        my $this_length = $lengths->[$i]->get_value('total_length_gui') * $self->{length_scale};

        # Start a new segment. We do this if since a few nodes can "line up" and thus have the same length
        if ($this_length > $start_length) {

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

sub draw_node {
    my ($self, $node, $current_xpos, $length_func, $length_scale, $height_scale, $line_width) = @_;

    return if !$node;

    $line_width //= $self->get_branch_line_width;

    my $node_name = $node->get_name;

    my $length = $length_func->($node) * $length_scale;
    my $new_current_xpos = $current_xpos - $length;
    my $y = $node->get_value('_y') * $height_scale;
    my $colour_ref = $self->{node_colours_cache}{$node_name} || DEFAULT_LINE_COLOUR;

    # Draw our horizontal line
    my $line = $self->draw_line(
        [$current_xpos, $y, $new_current_xpos, $y],
        $colour_ref,
        $line_width,
    );
    $line->signal_connect_swapped (event => \&on_event, $self);
    $line->{node} =  $node; # Remember the node (for hovering, etc...)

    # Remember line (for colouring, etc...)
    $self->{node_lines}->{$node_name} = $line;

    # Draw children
    my ($ymin, $ymax);
    my @arg_arr = ($new_current_xpos, $length_func, $length_scale, $height_scale, $line_width);

    foreach my $child ($node->get_children) {
        my $child_y = $self->draw_node($child, @arg_arr);

        $ymin = $child_y if ( (not defined $ymin) || $child_y < $ymin);
        $ymax = $child_y if ( (not defined $ymax) || $child_y > $ymax);
    }

    # Vertical line
    if (defined $ymin) { 
        $self->draw_line(
            [$new_current_xpos, $ymin, $new_current_xpos, $ymax],
            DEFAULT_LINE_COLOUR_VERT,
            NORMAL_WIDTH,
        );
    }
    return $y;
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
            my $cursor = Gtk2::Gdk::Cursor->new(HOVER_CURSOR);
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
            $self->increment_sequential_selection_colour;
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


##########################################################
# Misc
##########################################################

sub numerically {$a <=> $b};

# Resize background rectangle which is dragged for panning
sub max {
    return ($_[0] > $_[1]) ? $_[0] : $_[1];
}

1;
