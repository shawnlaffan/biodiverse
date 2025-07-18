package Biodiverse::GUI::Canvas::Tree;
use strict;
use warnings;
use 5.036;

our $VERSION = '4.99_007';

use experimental qw /refaliasing declared_refs for_list/;
use Glib qw/TRUE FALSE/;
use Gtk3;
use Scalar::Util qw /refaddr blessed/;
use List::Util qw /min max pairs uniq sum/;
use List::MoreUtils qw /minmax firstidx/;
use Ref::Util qw /is_coderef is_blessed_ref is_arrayref is_ref/;
use POSIX qw /floor/;
use Carp qw /croak confess/;
use Sort::Key qw /rnkeysort/;

use Biodiverse::GUI::Canvas::Tree::Index;
use Biodiverse::GUI::Canvas::ScreePlot;
use Biodiverse::Utilities qw/sort_list_with_tree_names_aa/;

use parent 'Biodiverse::GUI::Canvas';

use constant COLOUR_BLACK => Gtk3::Gdk::RGBA::parse('#000000000000');
use constant COLOUR_WHITE => Gtk3::Gdk::RGBA::parse('#FFFFFFFFFFFF');
use constant COLOUR_GRAY  => Gtk3::Gdk::RGBA::parse('#D2D2D2D2D2D2');
use constant COLOUR_RED   => Gtk3::Gdk::RGBA::parse('#FFFF00000000');

use constant COLOUR_PALETTE_OVERFLOW  => COLOUR_WHITE;
use constant COLOUR_OUTSIDE_SELECTION => COLOUR_WHITE;
use constant COLOUR_NOT_IN_TREE       => COLOUR_BLACK;
use constant COLOUR_LIST_UNDEF        => COLOUR_WHITE;

use constant DEFAULT_LINE_COLOUR      => COLOUR_BLACK;
use constant DEFAULT_LINE_COLOUR_RGB  => "#000000";
use constant DEFAULT_LINE_COLOUR_VERT => Gtk3::Gdk::RGBA::parse('#7F7F7F');  #  '#4D4D4D'

use constant PI => 3.1415927;


sub new {
    my ($class, %args) = @_;

    #  these should be handled by the parent and are here for porting reasons
    $args{map}             //= delete $args{grid};        # Grid.pm object of the dataset to link in
    $args{map_list_combo}  //= delete $args{list_combo};  # Combo for selecting how to colour the grid (based on spatial result or cluster)
    $args{map_index_combo} //= delete $args{index_combo}; # Combo for selecting how to colour the grid (which spatial result)

    #  default to on
    if (!exists $args{use_highlight_func}) {
        $args{use_highlight_func} = defined $args{highlight_func};
    }

    my $self = Biodiverse::GUI::Canvas->new (%args);
    #  rebless
    bless $self, $class;

    my $size = 1;
    $self->init_dims (
        xmin    => 0,
        ymin    => 0,
        xmax    => $size,
        ymax    => $size,
    );

    # starting off with the "clustering" view, not a spatial analysis
    $self->{sp_list}  = undef;
    $self->{sp_index} = undef;

    #  more leftovers fron Dendrogram.pm
    #  but not sure they are needed now?
    # clean up if we are a refresh - should also be the job of the caller
    # if (my $child = $frame->get_child) {
    #     $frame->remove( $child );
    # }
    # my $graph_frame = $self->{graph_frame};
    # if ($graph_frame) {
    #     if (my $child = $graph_frame->get_child) {
    #         $graph_frame->remove($child);
    #     }
    # }

    $self->init_legend(%args, parent => $self);

    # warn 'Tree is using default data';
    # $self->{data} = $self->get_data($args{ntips});
    # $self->init_plot_coords;
    # say join ' ', $self->get_data_extents;

    $self->{callbacks} = {
        plot   => sub {shift->draw(@_)},
        legend => sub {shift->get_legend->draw(@_)},
        # graph  => sub {shift->get_scree_plot->draw (@_))}
        graph  => sub {},
    };

    # Process changes for the map
    if (my $combo = $self->{map_index_combo}) {
        $combo->signal_connect_swapped(
            changed => \&on_map_index_combo_changed,
            $self,
        );
    }
    if (my $combo = $self->{map_list_combo}) {
        $combo->signal_connect_swapped (
            changed => \&on_map_list_combo_changed,
            $self
        );
    }

    return $self;
}

sub callback_order {
    my $self = shift;
    return (qw /plot legend graph/);
}

sub set_current_tree {
    my ($self, $tree, $plot_mode) = @_;

    $plot_mode //= 'length';

    if (!defined $tree) {
        $self->{data} = {};
        $self->{current_tree} = undef;
        $self->{plot_coords_generated} = undef;
        $self->{length_func} = undef;
        return;
    }

    state %mode_methods = (
        length => 'get_length',
        depth  => sub {1},
    );

    my $len_method = $self->{length_func}
        // $mode_methods{$plot_mode}
        // 'get_length';

    #  Don't needlessly regenerate the data
    return if defined $self->{current_tree}
        && refaddr($tree) == refaddr($self->{current_tree})
        && defined $self->{plot_mode}
        && $self->{plot_mode} eq $plot_mode;

    $self->{plot_mode} = $plot_mode;

    my $cache = $self->get_cached_value_dor_set_default_href('cached_data');
    if (my $data = $cache->{$tree}{$plot_mode}) {
        $self->{data} = $data;
        $self->{current_tree} = $tree;
        say "Using cached data to plot ", $tree->get_name, " using mode $plot_mode";
        return;
    }

    use Sort::Key qw /ikeysort rikeysort/;
    $tree->number_terminal_nodes;  #  need to keep this in a cache for easier cleanup
    my $terminals = $tree->get_terminal_node_refs;
    my @tips = ikeysort {$_->get_terminal_node_first_number} @$terminals;

    my $longest_path = 0;
    my $widest_path  = 0;  #  handle negative branch lengths as these can go past the root
    my %branch_hash;
    foreach my $node (@tips) {
        my $name = $node->get_name;
        my $len  = $node->$len_method;
        my $bref = $branch_hash{$name} = {
            name     => $name,
            node_ref => $node,
            ntips    => 0,
            length   => $len,
            parent   => $node->get_parent_name,
        };
        my $path = $bref->{path_to_root} = [$len];
        my $width = $len;
        my $parent = $node;
        while ($parent = $parent->get_parent) {
            my $parent_name = $bref->{parent} // $parent->get_name;
            $bref = $branch_hash{$parent_name} //= {
                node_ref => $parent,
                length   => $parent->$len_method,
                name     => $parent_name,
                parent   => $parent->get_parent_name,
            };
            my $this_len = $bref->{length};
            $len += $this_len;
            $width = $len if $len > $width;
            push @$path, $this_len;
            $bref->{ntips}++;
        }
        $longest_path = $len if $len > $longest_path;
        #  "width" allows for negative branch lengths which can send the root towards the centre
        $widest_path  = $width if $width > $widest_path;
    }

    my @roots = $tree->get_root_node_refs;  #  we can have multiple roots
    my $root_tree_node = $roots[0];
    my $root = $branch_hash{$root_tree_node->get_name};

    my %properties = (
        root         => $root,
        by_node      => \%branch_hash,
        tips         => \@tips,
        ntips        => scalar(@tips),
        longest_path => $longest_path,
        widest_path  => $widest_path,
    );

    $self->{data} = \%properties;
    $self->{current_tree} = $tree;
    # $self->{plot_mode} = $len_method;
    $self->{plot_coords_generated} = undef;

    $self->init_plot_coords;

    if ($self->{map_list_combo}) {
        $self->setup_map_list_model( scalar $tree->get_hash_lists() );
    }

    # TODO: Abstract this properly - but not sure it is used any more
    if (exists $self->{map_lists_ready_cb}) {
        $self->{map_lists_ready_cb}->($self->get_map_lists());
    }

    $cache->{$tree}{$plot_mode} = $self->{data};

    return;
}

sub get_current_tree {
    $_[0]->{current_tree};
}

sub get_data {
    $_[0]->{data};
}

sub get_branch_count {
    my ($self) = @_;
    my $data = $self->get_data // return 0;
    my $branches = $data->{by_node} // return 0;
    scalar %{$branches // {}};
}

sub _on_motion {
    my ($self, $widget, $event) = @_;

    return FALSE if $self->{mode} ne 'select';
    return FALSE if !$self->{plot_coords_generated};

    my ($x, $y) = $self->get_event_xy($event);

    my $current_cursor_name = $self->{motion_cursor_name} //= 'default';

    if ($self->get_show_slider) {
        my $slider = $self->get_slider_coords;
        \my @sb = $slider->{bounds};

        if ($self->{sliding}) {
            $slider->{x} = $x;
            my $w = ($sb[2] - $sb[0]) / 2;
            $sb[0] = $x - $w;
            $sb[2] = $x + $w;
            $slider->{x} = $x;

            $self->set_cursor_from_name ('sb_h_double_arrow');

            #  get the overlapping branches
            my @bres = $self->get_index->intersects_slider(@sb);
            $self->do_slider_intersection(\@bres);

            $self->get_parent_tab->queue_draw;
            return FALSE;
        }
        else {
            if ($self->coord_in_root_marker_bbox ($x, $y)) {
                #  on root marker box - same as slider for now
                $self->set_cursor_from_name ('pointer');
                $self->{motion_cursor_name} = 'pointer';
            }
            elsif ($x >= $sb[0] && $x < $sb[2] && $y >= $sb[1] && $y < $sb[3]) {
                #  on slider
                $self->set_cursor_from_name ('sb_h_double_arrow');
                # $self->set_cursor_from_name ('pointer');
                $self->{motion_cursor_name} = 'pointer';
                # return FALSE;
            }
            else {
                #  reset - needs to be in a conditional or we stop the slide
                $self->set_cursor_from_name ($current_cursor_name);
            }
        }

    }

    my @results;
    if ($self->coord_in_root_marker_bbox ($x, $y)) {
        @results = $self->{data}{root};
    }
    else {
        \@results = $self->get_index->query_point_nearest_y($x, $y);
    }
    if (@results) {
        if (my $f = $self->{hover_func}) {
            $f->($results[0]->{node_ref});
        }
        if ($self->use_highlight_func) {
            if (my $f = $self->{highlight_func}) {
                $f->($results[0]->{node_ref});
            }
        }
    }
    elsif (my $g = $self->{end_hover_func}) {
        $g->();
        $self->get_parent_tab->queue_draw;
    }

    #  should get cursor name from mode
    my $new_cursor_name = @results ? 'pointer' : 'default';
    if ($current_cursor_name ne $new_cursor_name) {
        #  change mouse style
        $self->set_cursor_from_name ($new_cursor_name);
        $self->{motion_cursor_name} = $new_cursor_name;
    }

    return FALSE;
}

sub coord_in_root_marker_bbox {
    my ($self, $x, $y) = @_;
    \my @rb = $self->{data}{root}{marker_bbox} // [];
    return $x >= $rb[0] && $x < $rb[2] && $y >= $rb[1] && $y < $rb[3];
}

sub do_slider_intersection {
    my ($self, $nodes) = @_;

    $self->{slider_intersection} = $nodes // [];

    return if $self->{no_use_slider_to_select_nodes};

    # Set up colouring
    #  these methods want tree nodes, not canvas branches
    my @colour_nodes = map {$_->{node_ref}} @$nodes;
    $self->recolour_normal (\@colour_nodes);

    return;
}

sub get_slider_intersection {
    $_[0]->{slider_intersection} // [];
}

sub get_index {
    my $self = shift;
    my $index = $self->{data}{box_index};

    #  we don't have the x-coords until the first time we are drawn
    return $index if $index && $self->{plot_coords_generated};

    $index = $self->{data}{box_index} = Biodiverse::GUI::Canvas::Tree::Index->new;
    $index->populate_from_tree($self);

    return $index;
}

sub _on_button_release {
    my ($self, $x, $y) = @_;

    delete $self->{sliding};

    return FALSE;
}

sub _select_while_not_selecting {
    my ($self, $widget, $x, $y) = @_;

    if ($self->get_show_slider && $self->{selecting}) {
        my $slider = $self->get_slider_coords;
        \my @b = $slider->{bounds};
        if ($x >= $b[0] && $x < $b[2] && $y >= $b[1] && $y < $b[3]) {
            $self->{sliding} = 1;
            # say 'SLIDER';

            $self->set_cursor_from_name ('pointer');

            $widget->queue_draw;
            return FALSE;
        }
    }

    # return FALSE if $x > $self->xmax || $y > $self->ymax;

    #  If in cloister mode we might not want to pass the undef,
    #  but that's probably best handled in the callback.
    if (my $f = $self->{click_func}) {
        my @branches;
        if ($self->coord_in_root_marker_bbox($x, $y)) {
            @branches = ($self->{data}{root});
        }
        else {
            @branches = $self->get_index->query_point_nearest_y($x, $y);
        }
        my $node_ref = @branches ? $branches[0]->{node_ref} : undef;
        $f->($node_ref);
        $self->queue_draw;
    }

    return FALSE;
}

sub _on_ctl_click {
    my ($self, $widget, $event) = @_;

    my ($x, $y) = $self->get_event_xy($event);

    # return FALSE if $x > $self->xmax || $y > $self->ymax || $x < $self->xmin || $y < $self->ymin;

    my $f = $self->{ctrl_click_func};

    my @branches;
    if ($self->coord_in_root_marker_bbox($x, $y)) {
        @branches = ($self->{data}{root});
    }
    else {
        @branches = $self->get_index->query_point_nearest_y($x, $y);
    }

    if ($f && @branches) {
        $f->($branches[0]->{node_ref});
    }

    return FALSE;
}

sub set_show_slider {
    my ($self, $bool) = @_;
    $self->{draw_slider} = !!$bool;
}

sub get_show_slider {
    my ($self) = @_;
    $self->{draw_slider} //= !0;
}

sub set_no_use_slider_to_select_nodes {
    my ($self, $bool) = @_;
    $self->{no_use_slider_to_select_nodes} = !!$bool;
}

sub get_slider_coords {
    my ($self) = @_;
    return $self->{slider_coords} //= {
        x  => 1,
        y0 => 0,
        y1 => 1,
    };
}

sub draw_slider {
    my ($self, $cx) = @_;

    return if !$self->get_show_slider;

    #  might only need the x coord
    my $slider_coords = $self->get_slider_coords;

    my ($x, $y0, $y1) = @{$slider_coords}{qw/x y0 y1/};

    my $disp = $self->{disp};
    my $line_width = $disp->width / 100;
    my $l2 = $line_width / 2;

    $cx->save;
    $cx->set_matrix ($self->get_tfm_mx);
    $cx->set_source_rgba(0, 0, 1, 0.5);
    $cx->move_to($x, 0);
    $cx->rectangle ($x - $l2, 0, $line_width, 1);
    $cx->fill;
    $cx->restore;

    $slider_coords->{bounds} = [
        $x - $l2, $y0,
        $x + $l2, $y1,
    ];

    if ($self->{sliding}) {
        # Update the slider textbox
        #  Cannot get Pango::Cairo to work so do it by hand.
        my $intersecting = $self->get_slider_intersection;
        my $num_intersecting = scalar @$intersecting;
        my @text = (
            "$num_intersecting branches ",
            sprintf('%.1f%% of total ', $num_intersecting * 100 / $self->get_branch_count), # round to 1 d.p.
            sprintf('%s frac: %.2f ', ($self->get_plot_mode eq 'depth' ? 'D' : 'L'), $x),
        );

        my $old_mx = $cx->get_matrix;
        #  needs to work in page units
        my @loc = $cx->user_to_device ($x, $y1);
        $cx->set_matrix($self->get_orig_tfm_matrix);

        my @offsets = @{$self->{px_offsets} // []};
        $loc[0] += $offsets[0];
        $loc[1] += $offsets[1];

        my $draw_size = $self->drawable->get_allocation();
        $loc[1] = $draw_size->{y};

        $cx->select_font_face("Sans", "normal", "bold");
        $cx->set_font_size( 12 );
        my $margin = 2;
        my @text_extents = map {$cx->text_extents($_)} @text;
        my $width   = max map {$_->{width}} @text_extents;
        my $rect_ht = sum map {$margin + $_->{height}} @text_extents;
        if ($loc[0] + $width > $draw_size->{width}) {
            $loc[0] -= $width;
        }

        $cx->move_to(@loc);
        $cx->set_source_rgba(0, 0, 1, 0.5);
        $cx->rectangle(@loc, $width, $rect_ht + $margin);
        $cx->fill;
        foreach my $t (@text) {
            my $extents = $cx->text_extents($t);
            my $height = $extents->{height} + $margin;
            $cx->move_to($loc[0], $loc[1] + $height);
            $cx->set_source_rgba(1, 1, 1, 0.5);
            $cx->show_text($t);
            $loc[1] += $height;
        }
        $cx->set_matrix($old_mx);
    };

    return;
}

#  branch line width in canvas units
sub get_horizontal_line_width {
    my ($self, $cx) = @_;

    my $ntips  = $self->{data}{ntips};

    my $line_width = $self->get_branch_line_width;

    #  A minimum of one pixel ensures branches are visible
    my $default = ($cx->device_to_user_distance(0,1))[1];

    if (!$ntips) {
        $line_width = 1;
    }
    elsif (!$line_width) {
        my $draw_size = $self->drawable->get_allocation();
        my $canvas_height = $draw_size->{height};

        #  how much of the tree (vertically) is visible due to zooming?
        my $scaler = ($cx->user_to_device_distance(0,$self->{dims}->height))[1];

        #  Calculate line width as a function of the plot height.
        #  The 3 allows a one branch gap under "ideal circumstances".
        $line_width = $canvas_height / ($scaler * $ntips * 3);
    }
    else  {  #  convert pixel to canvas
        $line_width *= $default;
    }

    return max ($default, $line_width);
}

#  ensure the vertical lines are the same as the horizontal ones
sub get_vertical_line_width {
    my ($self, $hline_width) = @_;

    my @scaling = $self->get_scale_factors;

    return ($hline_width // $self->get_horizontal_line_width) * $scaling[1] / $scaling[0];
}

sub x_scale {
    1 / $_[0]->{data}{widest_path}
}

sub y_scale {
    1 / $_[0]->{data}{ntips};
}

sub queue_draw {
    my ($self) = @_;
    $self->SUPER::queue_draw;  #  self
    $self->get_scree_plot->queue_draw;
}

sub draw {
    my ($self, $cx) = @_;

    return if !$self->get_current_tree;

    #  need to handle negative branches - these can push the rhs out past the root
    #  (or really the root inwards relative to the branches)

    my $data = $self->{data};
    my $root = $data->{root};
    my $node_hash = $data->{by_node};

    $self->init_plot_coords;

    # $cx->set_source_rgb(0.8, 0.8, 0.8);
    # $cx->rectangle (0, 0, 1, 1);
    # $cx->fill;

    my $h_line_width = $self->get_horizontal_line_width ($cx);
    my $v_line_width = $self->get_vertical_line_width ($h_line_width);

    \my %highlight_hash = $self->{branch_highlights} // {};
    \my %colour_hash    = $self->{branch_colours} // {};
    my $have_highlights = keys %highlight_hash;
    # say 'HAVE HIGHLIGHTS' if $have_highlights;
    my $default_branch_colour = $self->{default_branch_colour} // DEFAULT_LINE_COLOUR;
    my $default_highlight_colour
        = $have_highlights
        ? $self->{default_highlight_colour}
        : $default_branch_colour;

    my @h_colour = $self->rgb_to_array($default_branch_colour);
    my @v_colour = $self->rgb_to_array(DEFAULT_LINE_COLOUR_VERT);
    my $h_col_ref = \@h_colour;

    #   First the verticals.  Separated for speed as we avoid some repeated cairo calls.
    #   Plotted first so they go under the branches and don't overplot any colouring.
    \my @verticals = $data->{vertical_connectors};
    my @def_h_col
        = is_arrayref $default_highlight_colour
        ? (@$default_highlight_colour)
        : map {$default_highlight_colour->$_} qw /red green blue/;
    $cx->set_line_cap ('round');
    $cx->set_line_width($v_line_width);
    $cx->set_source_rgb ($have_highlights ? @def_h_col : @v_colour);
    foreach my \@vert (@verticals) {
        $cx->move_to($vert[0], $vert[1]);  #  first child
        $cx->line_to($vert[0], $vert[2]);  #  last child
    }
    $cx->stroke;

    $cx->set_line_cap ('butt');
    $cx->set_line_width($h_line_width);
    $cx->set_source_rgb(@h_colour);

    my $last_colour = $h_col_ref;
    my @highlights;
    BRANCH:
    foreach my ($name, $branch) (%$node_hash) {

        my ($x_l, $x_r, $y) = @{$branch}{qw/x_l x_r y/};

        #  Use colours from highlights if set.
        #  Highlights fall back to colour hash if true
        #  but not a colour or array ref.
        my $colour;
        if ($have_highlights) {
            if (exists $highlight_hash{$name}) {
                $colour = $highlight_hash{$name} // $default_branch_colour;
                #  Highlight using original colour if we are
                #  not some sort of reference.
                if (!is_ref($colour)) {
                    $colour = $colour_hash{$name};
                }
                push @highlights, [$x_l, $x_r, $y, $colour];
                next BRANCH;
            }
            $colour = $default_highlight_colour;
        }
        else {
            $colour = $colour_hash{$name};
        }
        $colour //= $h_col_ref;
        if ($colour ne $last_colour) {
            $cx->stroke;  #  paint the queue for the old colour
            $last_colour = $colour;
            #  should handle other ref types?
            my @col_array
                = is_blessed_ref($colour) ? ($colour->red, $colour->green, $colour->blue)
                : is_arrayref($colour) ? @$colour
                : @h_colour;
            $cx->set_source_rgb(@col_array);
        }

        $cx->move_to($x_r, $y);
        $cx->line_to($x_l, $y);

    }
    $cx->stroke;  #  paint the queued colours

    #  highlights above all others
    foreach my \@h_array (@highlights) {
        my ($x_l, $x_r, $y, $colour) = @h_array;
        $colour //= $h_col_ref;
        if ($colour ne $last_colour) {
            $cx->stroke;  #  paint the queued colours
            $last_colour = $colour;
            my @col_array
                = is_blessed_ref($colour) ? ($colour->red, $colour->green, $colour->blue)
                : is_arrayref($colour) ? @$colour
                : @h_colour;
            $cx->set_source_rgb(@col_array);
        }
        $cx->move_to($x_r, $y);
        $cx->line_to($x_l, $y);
    }
    $cx->stroke;  #  paint


    #  the root node gets a shape
    if (1) {
        my $ratio = $self->get_xy_scale_ratio;
        my $h_dist = 0.02;  #  should be user configurable
        my $v_dist = $h_dist * $ratio / 2;
        my @root_coord = ($root->{x_r}, $root->{y});
        my @bbox = (
            $root_coord[0],
            $root_coord[1]-$v_dist,
            $root_coord[0]+$h_dist,
            $root_coord[1]+$v_dist,
        );
        # @root_coord = $cx->device_to_user(@root_coord);
        # my $mx = $cx->get_matrix;
        # $cx->save;
        # # $cx->set_matrix($self->get_orig_tfm_matrix);
        # $cx->arc(@root_coord, $radius, 0, 2.0 * PI);
        $cx->move_to(@root_coord);
        $cx->line_to($bbox[2], $bbox[1]);
        $cx->line_to($bbox[2], $bbox[3]);
        $cx->line_to(@root_coord);
        #  sienna
        $cx->set_source_rgba(160 / 255, 82 / 255, 45 / 255, 0.4);
        $cx->fill;
        # $cx->set_matrix($mx);
        # $cx->restore;
        $root->{marker_bbox} = \@bbox;
    };

    $self->draw_slider($cx);

    return;
}

sub init_plot_coords {
    my ($self) = @_;

    return if $self->{plot_coords_generated};

    #  start with the y-coords
    my $tree = $self->get_current_tree;
    return if !$tree;

    my $data = $self->{data};
    \my %branch_hash = $data->{by_node};

    #  set the initial y-coord
    #  need to climb up the tree
    my @targets = map {$_->get_name} rikeysort {$_->get_depth} $tree->get_node_refs;
    foreach my $bname (@targets) {
        my $branch_ref = $branch_hash{$bname};
        my $node_ref   = $branch_ref->{node_ref};
        if (!$branch_ref->{ntips}) {
            $branch_ref->{children} = [];
            #  same as terminal_node_last for a tip
            $branch_ref->{_y} = $node_ref->get_terminal_node_first_number - 0.5;
        }
        else {
            my @children = map {$_->get_name} $node_ref->get_children;
            $branch_ref->{children} = \@children;
            #  average of first and last
            $branch_ref->{_y}
                = ($branch_hash{$children[0]}->{_y} + $branch_hash{$children[-1]}->{_y}) / 2;
        }
    }

    #  and now the x-coords
    my $root = $data->{root};
    my @branches = ($root);
    my $node_hash = $data->{by_node};

    my $x_scale  = $self->x_scale;
    my $y_scale  = $self->y_scale;

    $root->{x_r} //= $data->{longest_path} / $data->{widest_path};

    while (my $branch = shift @branches) {
        $branch->{y} = $branch->{_y} * $y_scale;

        my $length = $branch->{length} * $x_scale;
        my $x_r = $branch->{x_r};
        my $x_l = $branch->{x_l} //= $x_r - $length;

        my @children = map {$node_hash->{$_}} @{$branch->{children}};
        foreach my $child (@children) {
            $child->{x_r} = $x_l;
        }
        push @branches, @children;
    }

    #  now the verticals
    my @verticals;
    @branches = ($root);
    while (my $branch = shift @branches) {
        my @ch = map {$node_hash->{$_}} @{$branch->{children}};
        if (@ch) {
            my $x_r = $branch->{x_l};
            push @verticals, [$x_r, $ch[0]{y}, $ch[-1]{y}];
        }
        push @branches, @ch;
    }
    $self->{data}{vertical_connectors} = \@verticals;

    $self->{plot_coords_generated} = 1;

    #  trigger index generation
    my $box_index = $self->get_index;

    if (my $scree_plot = $self->get_scree_plot) {
        $scree_plot->init_plot_coords;
    }

    return;
}

sub init_y_coords {
    my ($self, $node, $current_y_ref) = @_;

    use constant LEAF_SPACING => 1;
    use constant BORDER_HT    => 0.025;

    my $data = $self->{data};
    $node //= $data->{root};
    if (!defined $current_y_ref) {
        #  ensure we centre, otherwise we are off-by-one
        my $x = 0.5 * LEAF_SPACING;
        $current_y_ref = \$x;
    }
    #  zero border ht now as we centre the tree vertically
    # $self->{border_ht} //= $data->{ntips} * BORDER_HT;
    $self->{border_ht} //= 0;


    if (!$node->{ntips}) {
        $node->{_y} = $$current_y_ref + $self->{border_ht};
        ${$current_y_ref} = $$current_y_ref + LEAF_SPACING;
    }
    else {
        my $y_sum = 0;
        my $count = 0;

        my $tree_node_ref = $node->{name};
        foreach my $child (map {$data->{by_node}{$_->get_name}} $tree_node_ref->get_children) {
            $self->init_y_coords($child, $current_y_ref);
            $y_sum += $child->{_y};
            $count++;
        }
        $node->{_y} = $y_sum / $count; # y-value is average of children's y values
    }

    return;
}


sub get_toy_data {
    my ($self, $ntips) = @_;

    $ntips //= 8;
    #  round up to next power of two for simplicity
    my $power = 1;
    while ($power < $ntips) {
        $power *= 2;
    }
    $ntips = $power;
    my $nbranches = $ntips * ($ntips - 1) / 2;

    srand (2345);

    #  generate some branches
    my @branches = (1);
    foreach my $i (@branches) {
        push @branches, (2*$i, 2*$i+1);
        last if scalar @branches >= $nbranches;
    }

    my %branch_hash;
    foreach my $branch (@branches) {
        my $parent = int ($branch / 2) || undef;
        $branch_hash{$branch} = {
            length   => rand(),
            parent   => $parent,
            children => [],
            name     => $branch,
        };
        if (defined $parent) {
            my $c = $branch_hash{$parent}{children} //= [];
            push @$c, $branch;
        }
    }
    my @tips = sort {$a<=>$b} grep {!scalar @{$branch_hash{$_}{children}}} keys %branch_hash;

    my $longest_path = 0;
    foreach my $tip (@tips) {
        $branch_hash{$tip}{ntips} = 0;
        my $len  = $branch_hash{$tip}{length};
        my $path = $branch_hash{$tip}{path_to_root} = [$len];
        my $parent = $tip;
        while ($parent = $branch_hash{$parent}{parent}) {
            my $this_len = $branch_hash{$parent}{length};
            $len += $this_len;
            push @$path, $this_len;
            $branch_hash{$parent}{ntips}++;
            # say "Parent is $parent, len is $len";
        }
        $longest_path = $len if $len > $longest_path;
    }

    my %tree = (
        root         => $branch_hash{1},
        by_node      => \%branch_hash,
        tips         => \@tips,
        ntips        => scalar @tips,
        longest_path => $longest_path,
    );

    return \%tree;
}

sub set_num_clusters {
    my ($self, $n, $no_recolour) = @_;

    my $current = $self->get_num_clusters // 0;
    if ($current != $n and !$no_recolour) {
        $self->{num_clusters} = $n;
        $self->recolour();
    }
    return;
}

sub get_num_clusters {
    my ($self) = @_;
    return $self->{num_clusters};
}

sub set_branch_line_width {
    my ($self, $val) = @_;
    $self->{branch_line_width} = $val // 0;
    return;
}

sub get_branch_line_width {
    $_[0]->{branch_line_width} //= 0;
}

##########################################################
# Drawing the tree
##########################################################

sub get_plot_mode {
    $_[0]->{plot_mode};
}

# whether to plot by 'length' or 'depth'
sub set_plot_mode {
    my ($self, $plot_mode) = @_;

    my $tree = $self->{current_tree};

    #  Much commented code due to porting across from Dendrogram.pm

    # Work out how to get the "length" based on mode
    if ($plot_mode eq 'length') {
        $self->{length_func} = 'get_length';
    }
    elsif ($plot_mode eq 'depth') {
        $self->{length_func} = sub {1};
    }
    elsif ($plot_mode =~ 'equal_length|range_weighted') {
        #  Create an alternate tree with the chosen properties.
        #  Use a cache for speed.
        #  Basedata will not change for lifetime of object
        #  as GUI does not support in-place deletions.
        my $gui_tree  = $self->get_parent_tab->get_current_tree;
        my $cache_key = "tree_for_plot_mode_${plot_mode}_from_${gui_tree}";
        my $cache = $self->get_cached_value_dor_set_default_href ($cache_key);
        my $alt_tree = $cache->{tree};
        my $callback = $cache->{callback};

        if (!defined $alt_tree) {
            #  alt_tree can be processed in both if-conditions below
            $alt_tree = $gui_tree;
            if ($plot_mode =~ 'equal_length') {
                $alt_tree = $alt_tree->clone_tree_with_equalised_branch_lengths;
            }
            if ($plot_mode =~ 'range_weighted') {
                my $bd = $self->get_parent_tab->get_base_ref;
                $alt_tree = $alt_tree->clone_without_caches;
                NODE:
                foreach my $node (rnkeysort {$_->get_depth} $alt_tree->get_node_refs) {
                    my $range = $node->get_node_range(basedata_ref => $bd);
                    $node->set_length_aa($range ? $node->get_length / $range : 0);
                }
            }
            #  return zero if not in the tree
            $callback = sub {
                my $node_ref = $alt_tree->get_node_ref_or_undef_aa($_[0]->get_name);
                return $node_ref ? $node_ref->get_length : 0;
            };
            $cache->{tree} = $alt_tree;
            $cache->{callback} = $callback;
        }
        $self->{length_func} = $callback;
    }
    else {
        die "Invalid cluster-plotting mode - $plot_mode";
    }

    $self->set_current_tree ($tree, $plot_mode);

    return;
}

# whether to group by 'length' or 'depth' for colouring
sub set_group_mode {
    my ($self, $mode) = @_;
    if ($mode ne $self->get_group_mode) {
        $self->{group_mode} = $mode;
        $self->recolour;
    }
    return;
}

sub get_group_mode {
    my ($self) = @_;
    $self->{group_mode} //= 'length';
}

sub set_branch_colours {
    my ($self, $branch_hash, $default_colour) = @_;

    $branch_hash //= {};

    #  do we want this?
    # $self->{default_branch_colour}
    #     = keys %$branch_hash
    #     ? ($default_colour // COLOUR_GRAY)
    #     : DEFAULT_LINE_COLOUR;
    # $self->{default_branch_colour} = $default_colour;

    $self->{branch_colours} = $branch_hash;

    return;
}

#  Highlights override colours, possibly also specifying the colour to use
#  Allows easier reversion to a previous colour set.
#  Highlights are also coloured last (or will be)
sub set_branch_highlights {
    my ($self, $branch_hash, $default_colour) = @_;

    $branch_hash //= {};

    #  Trigger a redraw when we clear.
    my $queue_draw
        = !scalar keys %$branch_hash
          && scalar keys %{$self->{branch_highlights} // {}};

    $self->{default_highlight_colour}
        = keys %$branch_hash
        ? ($default_colour // COLOUR_GRAY)
        : DEFAULT_LINE_COLOUR;

    $self->{branch_highlights} = $branch_hash;

    $self->queue_draw if $queue_draw;

    return;
}

#  a helper method
sub clear_highlights {
    $_[0]->set_branch_highlights ();
}

sub set_use_highlight_func {
    my ($self, $value) = @_;

    # Perhaps a bit clever but first
    # call sets to 1 if value is undef.
    $self->{use_highlight_func}
        = !!($value // !$self->{use_highlight_func});

    return;
}

sub use_highlight_func {
    $_[0]->{use_highlight_func};
}

# Colours the dendrogram lines with palette colours
sub recolour_cluster_lines {
    my ($self, $cluster_nodes, $no_colour_descendants, $default_colour) = @_;

    if ($self->in_multiselect_mode) {
        #  a different structure, handled below
        $cluster_nodes = $self->get_multiselect_node_array;
    }

    my ($colour_ref, $list_ref, $val);
    my %coloured_nodes;

    my $map = $self->{map};
    my $list_name    = $self->{analysis_list_name}  // '';
    my $list_index   = $self->{analysis_list_index} // '';
    my $colour_mode  = $self->get_cluster_colour_mode();

    my ($legend, @minmax_args, $colour_method);
    if ($colour_mode ne 'palette' and not $self->in_multiselect_mode) {
        $legend = $map->get_legend;
        $legend->set_colour_mode_from_list_and_index (
            list  => $list_name,
            index => $list_index,
        );
        @minmax_args = $legend->get_min_max;
        $colour_method = $legend->get_colour_method;
    }

    my %colour_hash;
    foreach my $ref (@$cluster_nodes) {
        #  copy as loop-aliasing messes up the multiselect array
        my $node_ref = $ref;

        my $node_name;
        if ($colour_mode eq 'palette') {
            $node_name = $node_ref->get_name;
            $colour_ref = $self->{node_palette_colours}{$node_name} || COLOUR_RED;
        }
        elsif ($self->in_multiselect_mode) {
            $colour_ref = $node_ref->[1];
            #  should be stored as strings for serialisation purposes
            if (defined $colour_ref && !blessed $colour_ref) {
                $colour_ref = Gtk3::Gdk::RGBA::parse ($colour_ref);
            };
            $node_ref   = $node_ref->[0];
            $node_name  = $node_ref->get_name;
        }
        elsif ($colour_mode eq 'list-values') {
            $node_name = $node_ref->get_name;

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

        $colour_hash{$node_name} = $colour_ref;

        # And also colour all nodes below
        # - don't cache on the tree as we can get recursion stack blow-outs
        # - https://github.com/shawnlaffan/biodiverse/issues/549
        # We could cache on $self if it were needed.
        if (!$no_colour_descendants) {
            my $descendants = $node_ref->get_all_descendants (cache => 0);
            @colour_hash{keys %$descendants} = ($colour_ref) x keys %$descendants;
        }

        $coloured_nodes{$node_name} = $node_ref; # mark as coloured
    }

    $self->set_branch_colours(\%colour_hash);

    if ($self->in_multiselect_mode) {
        $self->set_multiselect_colour_hash(\%colour_hash);
    }

    #  Might be worth skipping if we know the colours have not changed
    #  but that needs profiling first.
    if (keys %colour_hash) {
        my %for_cache
            = map {
                my $c = $colour_hash{$_};
                $_ => [ $c->red, $c->green, $c->blue ]
            } keys %colour_hash;
        $self->get_current_tree->set_most_recent_line_colours_aa (\%for_cache);
    }

    return \%colour_hash;
}


# Colours a certain number of nodes below a start node
sub do_colour_nodes_below {
    my ($self, $start_node) = @_;

    my $in_multiselect_mode = $self->in_multiselect_mode;

    #  Don't clear if we are multi-select - allows for mis-hits when
    #  selecting branches.
    return if !$start_node && $in_multiselect_mode;

    $self->{colour_start_node} = $start_node;

    my $num_clusters = $in_multiselect_mode ? 1 : $self->get_num_clusters;
    my $original_num_clusters = $num_clusters;
    my $excess_flag = 0;
    my $terminal_element_hash_ref;

    my @colour_nodes;

    if (defined $start_node) {

        # Get list of nodes to colour
        #print "[Dendrogram] Grouping...\n";
        my $node_hash = $in_multiselect_mode
            ? {$start_node->get_name => $start_node}
            : $start_node->group_nodes_below (
                num_clusters => $num_clusters,
                type => $self->{group_mode}
            );
        @colour_nodes = values %$node_hash;
        #print "[Dendrogram] Done Grouping...\n";

        # FIXME: why loop instead of just grouping with
        # num_clusters => $self->get_palette_max_colours
        #  make sure we don't exceed the maximum number of colours
        while (scalar @colour_nodes > $self->get_palette_max_colours) {
            $excess_flag = 1;

            # Group again with 1 fewer colours
            $num_clusters --;
            $node_hash = $start_node->group_nodes_below (
                num_clusters => $num_clusters,
                type => $self->{group_mode},
            );
            @colour_nodes = values %$node_hash;
        }
        $num_clusters = scalar @colour_nodes;  #not always the same, so make them equal now

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
    elsif (!$in_multiselect_mode) {
        say "[Dendrogram] Clearing colouring";
    }

    # Set up colouring
    #print "num clusters = $num_clusters\n";
    if (!$in_multiselect_mode) {
        # $self->assign_cluster_palette_colours(\@colour_nodes);
        # $self->map_elements_to_clusters(\@colour_nodes);
        #
        # $self->recolour_cluster_lines(\@colour_nodes);
        # $self->recolour_cluster_map($terminal_element_hash_ref);
        # $self->set_processed_nodes(\@colour_nodes);
        $self->recolour_normal(\@colour_nodes, $terminal_element_hash_ref);
    }
    else {
        $self->update_multiselect_colours(\@colour_nodes);
        $self->recolour_multiselect;
        $self->increment_multiselect_colour;
    }

    return;
}

#  a bad name, but not multiselect
sub recolour_normal {
    my ($self, $colour_nodes, $terminal_element_hash_ref) = @_;

    $self->assign_cluster_palette_colours($colour_nodes);
    $self->map_elements_to_clusters($colour_nodes);
    $self->recolour_cluster_lines($colour_nodes);
    $self->recolour_cluster_map($terminal_element_hash_ref);
    $self->set_processed_nodes($colour_nodes);

    return;
}

sub recolour_multiselect {
    my ($self) = @_;

    return if !$self->in_multiselect_mode;

    #  rebuilds the whole thing - could optimise later
    my $coloured_nodes = $self->get_multiselect_node_refs;
    $self->map_elements_to_clusters($coloured_nodes);

    $self->recolour_cluster_lines($coloured_nodes);
    $self->recolour_cluster_map();
    $self->set_processed_nodes($coloured_nodes);
    return;
}


# Colours the element map with colours for the established clusters
sub recolour_cluster_map {
    my ($self, $terminal_element_subset) = @_;

    my $map = $self->{map};
    return if not defined $map;

    my $list_name         = $self->{analysis_list_name}  // '';
    my $list_index        = $self->{analysis_list_index} // '';
    # my $analysis_min      = $self->{analysis_min};
    # my $analysis_max      = $self->{analysis_max};
    my $terminal_elements = $self->{terminal_elements};

    my $parent_tab = $self->{parent_tab};
    my $colour_for_undef = $parent_tab->get_undef_cell_colour;

    my $cluster_colour_mode = $self->get_cluster_colour_mode();
    my $colour_callback;  #  should just build a hash and pass that to the map

    if ($cluster_colour_mode eq 'palette') {
        # sets colours according to palette
        $colour_callback = sub {
            my $elt = shift;
            my $cluster_node = $self->{element_to_cluster_remap}{$elt};

            my $colour_ref
                = $cluster_node ? (
                $self->{node_palette_colours}{$cluster_node->get_name}
                    || COLOUR_PALETTE_OVERFLOW
            )
                : exists $terminal_elements->{$elt} ? COLOUR_OUTSIDE_SELECTION
                : $self->get_colour_not_in_tree;

            return $colour_ref;
        };
    }
    elsif ($self->in_multiselect_mode) {
        # my $multiselect_colour = $self->get_current_multiselect_colour;
        \my %multiselect_colour_hash = $self->get_multiselect_colour_hash;

        # sets colours according to multiselect palette - could be simplified
        $colour_callback = sub {
            my $elt = shift;

            return undef
                if    $terminal_element_subset
                    && !exists $terminal_element_subset->{$elt};

            my $cluster_node = $self->{element_to_cluster_remap}{$elt};

            return undef if !$cluster_node;

            return $multiselect_colour_hash{$elt} || COLOUR_OUTSIDE_SELECTION;
        };
    }
    elsif ($cluster_colour_mode eq 'list-values') {
        my $legend = $map->get_legend;
        #  these should already be set
        # $legend->set_colour_mode_from_list_and_index (
        #     list  => $list_name,
        #     index => $list_index,
        # );
        # my @minmax_args = ($analysis_min, $analysis_max);
        my @minmax_args = $legend->get_min_max;
        my $colour_method = $legend->get_colour_method;

        # sets colours according to (usually spatial)
        # list value for the element's cluster
        $colour_callback = sub {
            my $elt = shift;

            my $cluster_node = $self->{element_to_cluster_remap}{$elt};

            if ($cluster_node) {

                my $list_ref = $cluster_node->get_list_ref_aa ($list_name)
                    // return $colour_for_undef;

                my $val = $list_ref->{$list_index}
                    // return $colour_for_undef;

                return $legend->$colour_method ($val, @minmax_args);
            }

            return exists $terminal_elements->{$elt}
                ? COLOUR_OUTSIDE_SELECTION
                : $self->get_colour_not_in_tree;

        };
    }

    die "Invalid cluster colour mode $cluster_colour_mode\n"
        if !defined $colour_callback;

    $map->colour ($colour_callback);

    return;
}


sub get_processed_nodes {
    $_[0]->{processed_nodes}
}

sub set_processed_nodes {
    $_[0]->{processed_nodes} = $_[1];
}


sub set_cluster_colour_mode {
    my ($self, $mode, $fallback) = @_;

    my $prev_mode = $self->{cluster_colour_mode} // '';

    return if $mode eq $prev_mode;

    #  should not be needed now, but just in case
    if ($mode eq 'value') {
        warn 'set_cluster_colour_mode called with mode set to value';
        $mode = $fallback // die;
    }

    $self->{cluster_colour_mode} = $mode;

    if (!defined $mode or $mode =~ /palette|multi/) {
        $self->hide_legend;
    }

    #  Store the set of nodes to colour before we enter multi-select
    #  and reinstate after leaving.  Might only need the start node.
    if ($prev_mode =~ /multi/) {
        my $prev_nodes = delete $self->{multiselect}{prev_processed_nodes};
        $self->set_processed_nodes($prev_nodes);
        $self->{colour_start_node}
            = delete $self->{multiselect}{prev_colour_start_node};
        $self->{element_to_cluster_remap} = {};
    }
    elsif ($mode =~ /multi/) {
        $self->{multiselect}{prev_processed_nodes} = $self->get_processed_nodes;
        $self->{multiselect}{prev_colour_start_node} = $self->{colour_start_node};
        $self->{element_to_cluster_remap} = {};
    }

    return $mode;
}

sub get_cluster_colour_mode {
    my ($self) = @_;
    return $self->{cluster_colour_mode}
        // do {$self->set_cluster_colour_mode('palette')};
}

# Returns a list of colours to use for colouring however-many clusters
# returns STRING COLOURS
sub get_palette {
    my ($self, $num_clusters) = @_;
    #print "Choosing colour palette for $num_clusters clusters\n";

    return wantarray ? () : []
        if $num_clusters <= 0;  # trap bad numclusters

    my @colourset
        = $num_clusters <=  9 ? $self->get_gdk_colors_colorbrewer9
        : $num_clusters <= 13 ? $self->get_gdk_colors_colorbrewer13
        : (DEFAULT_LINE_COLOUR) x $num_clusters;

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
        = map {Gtk3::Gdk::RGBA::parse ($_)}
        $self->get_palette_colorbrewer9;
    return @colours;
}

sub get_gdk_colors_colorbrewer13 {
    my $self = shift;
    my @colours
        = map {Gtk3::Gdk::RGBA::parse ($_)}
        $self->get_palette_colorbrewer13;
    return @colours;
}

# Assigns palette-based colours to selected nodes
sub assign_cluster_palette_colours {
    my ($self, $cluster_nodes) = @_;

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

        my @sorted_clusters = @sort_by_firstnode{sort {$a <=> $b} keys %sort_by_firstnode};

        # assign colours
        $self->{node_palette_colours} = undef;  #  clear previous

        foreach my $k (0..$#sorted_clusters) {
            my $colour_ref = $palette[$k];
            if (!blessed $colour_ref) {
                $colour_ref = Gtk3::Gdk::RGBA::parse($colour_ref);
            }
            $self->{node_palette_colours}{$sorted_clusters[$k]->get_name} = $colour_ref;
        }
    }

    return;
}

sub get_multiselect_node_array {
    my ($self) = @_;
    my $array
        = $self->{multiselect}{node_array}
        //= $self->get_current_tree->get_cached_value_dor_set_default_aa (
            GUI_MULTISELECT_COLOUR_STORE => []
        );
    return $array;
}

sub get_multiselect_colour_hash {
    my ($self) = @_;
    $self->{multiselect}{node_colour_hash} //= {};
}

sub set_multiselect_colour_hash {
    my ($self, $hash) = @_;
    $self->{multiselect}{node_colour_hash} = ($hash // {});
}

sub get_multiselect_node_refs {
    my ($self) = @_;

    my $array = $self->get_multiselect_node_array;
    my @refs = map {$_->[0]} @$array;

    return wantarray ? @refs : \@refs;
}

sub update_multiselect_colours {
    my ($self, $cluster_nodes) = @_;

    my $node_array  = $self->get_multiselect_node_array;
    my $colour_ref  = $self->get_current_multiselect_colour;
    \my %colour_hash = $self->get_multiselect_colour_hash;

    #  need Gtk colours here
    if (defined $colour_ref && !blessed $colour_ref) {
        $colour_ref = Gtk3::Gdk::RGBA::parse($colour_ref);
    }
    @colour_hash{@$cluster_nodes} = ($colour_ref) x @$cluster_nodes;

    #  Store stringified versions as we store on the tree object
    #  and Gtk objects do not survive serialisation.
    my $colour_string = blessed $colour_ref ? $colour_ref->to_string : $colour_ref;
    push @$node_array, map { [$_, $colour_string] } @$cluster_nodes;

    $self->get_parent_tab->set_project_dirty;

    return;
}

# Gets a hash of nodes which have been coloured
# Used by Spatial tab for getting an element's "cluster" (ie: coloured node that it's under)
#     hash of names (with refs as values)
sub get_cluster_node_for_element {
    my ($self, $element) = @_;
    return $self->{element_to_cluster_remap}{$element};
}


sub map_elements_to_clusters {
    my ($self, $cluster_nodes) = @_;

    my %map;

    foreach my $node_ref (@$cluster_nodes) {
        my $terminal_elements = $node_ref->get_terminal_elements();
        @map{keys %$terminal_elements} = ($node_ref) x scalar keys %$terminal_elements;
    }

    $self->{element_to_cluster_remap} = \%map;

    return;
}


sub reset_multiselect_undone_stack {
    my $self = shift;
    $self->get_current_tree->set_cached_value (
        GUI_MULTISELECT_UNDONE_STACK => [],
    );
}

sub get_multiselect_undone_stack {
    my $self = shift;
    my $undone_stack = $self->get_current_tree->get_cached_value_dor_set_default_aa (
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

    return if !$self->in_multiselect_mode;

    #  should be a method
    $self->{element_to_cluster_remap} = {};

    $self->recolour_multiselect;
    $self->get_parent_tab->queue_draw;

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
    my $res = eval {$self->{autoincrement_toggle}->get_active};
    warn $@ if $@;
    return $res;
}

#  a wrapper method now
sub get_multiselect_colour_store {
    my $self = shift;
    return $self->get_multiselect_node_array;
}

sub get_current_multiselect_colour {
    my $self = shift;

    return if $self->in_multiselect_clear_mode;

    my $colour = eval {
        $self->{selector_colorbutton}->get_rgba;
    };

    return $colour;
}

sub set_current_multiselect_colour {
    my ($self, $colour) = @_;

    return if !defined $colour;  #  should we croak?

    eval {
        if ((blessed $colour // '') !~ /Gtk3::Gdk::RGBA/) {
            $colour = Gtk3::Gdk::RGBA::parse  ($colour);
        }
        $colour = $self->{selector_colorbutton}->set_rgba ($colour);
    };

    return $colour;
}

#  should be controlled by the parent tab
sub init_multiselect {
    my ($self) = @_;
    #  leftovers from Dendrogram.pm
    foreach my $widget_name (qw /selector_toggle selector_colorbutton autoincrement_toggle/) {
        eval {
            $self->{$widget_name}
                = $self->get_parent_tab->get_xmlpage_object($widget_name);
        };
        warn $@ if $@;
    }

    #  also initialises it
    $self->increment_multiselect_colour(1);

    return;
}

sub increment_multiselect_colour {
    my ($self, $force_increment) = @_;

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
        $self->{selector_colorbutton}->set_rgba ($colour);
    };

    $self->{last_multiselect_colour} = $colour;

    return;
}

# Highlights all nodes above and including the given node
sub highlight_path {
    my ($self, $node_ref, $node_colour) = @_;

    # set path to highlighted colour
    my %highlights;
    while ($node_ref) {
        my $name = $node_ref->get_name;
        # my $colour_ref =  $node_colour
        #     || $self->get_node_colour_aa ($node_ref->get_name)
        #     || DEFAULT_LINE_COLOUR;
        $highlights{$name} = 1;

        $node_ref = $node_ref->get_parent;
    }

    $self->set_branch_highlights(\%highlights);

    return;
}


##########################################################
# The map combobox business
# This is the one that selects how to colour the map
#  FIXME:  This should all be in Clustering.pm
##########################################################

# Provides list of results for tab to use as it sees fit
sub get_map_lists {
    my $self = shift;
    my $lists = scalar $self->{tree_node}->get_hash_lists();
    return [sort @$lists];
}

# Combo-box for the list of results (eg: REDUNDANCY or ENDC_SINGLE) to use for the map
sub setup_map_list_model {
    my ($self, $lists) = @_;

    my $combo = $self->{map_list_combo};

    #  some uses don't have the map list
    #  - need to clean up the logic and abstract such components to a different class
    return if !defined $combo;

    my $model = Gtk3::ListStore->new('Glib::String');
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

    my $model = Gtk3::ListStore->new('Glib::String');
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


sub get_colour_not_in_tree {
    my $self = shift;

    my $colour = eval {
        $self->get_parent_tab->get_excluded_cell_colour
    } || COLOUR_NOT_IN_TREE;

    return $colour;
}

#  FIXME - should be done by parent tab
# Change of list to display on the map
# Can either be the Cluster "list" (coloured by node) or a spatial analysis list
sub on_map_list_combo_changed {
    my ($self, $combo) = @_;
    $combo ||= $self->{map_list_combo};

    return if $combo->get_active < 0;

    my $iter  = $combo->get_active_iter;
    my $model = $combo->get_model;
    my $list  = $model->get($iter, 0);

    $self->{analysis_list_name}  = undef;
    $self->{analysis_list_index} = undef;
    $self->{analysis_min}        = undef;
    $self->{analysis_max}        = undef;

    #  multiselect hides it
    if ($self->{slider}) {
        eval {$self->{slider}->show};
        warn $@ if $@;
        # $self->{graph_slider}->show;
    }

    if ($list eq '<i>Cluster</i>') {
        # Selected cluster-palette-colouring mode

        $self->set_cluster_colour_mode('palette');

        $self->get_parent_tab->on_clusters_changed;

        my $processed_nodes = $self->get_processed_nodes;
        $self->recolour_cluster_lines($processed_nodes);
        #  not sure why we need to do this here
        $self->map_elements_to_clusters($processed_nodes);
        $self->recolour_cluster_map;

        # blank out the index combo
        $self->setup_map_index_model(undef);
    }
    elsif ($list eq '<i>User defined</i>') {
        if ($self->{slider}) {
            $self->{slider}->hide;
            # $self->{graph_slider}->hide;
        }

        $self->set_cluster_colour_mode('multiselect');

        $self->set_num_clusters (1, 'no_recolour');

        $self->replay_multiselect_store;

        # blank out the index combo
        $self->setup_map_index_model(undef);
    }
    else {

        $self->get_parent_tab->on_clusters_changed;

        # Selected analysis-colouring mode
        $self->{analysis_list_name} = $list;

        $self->setup_map_index_model($self->{current_tree}->get_list_ref(list => $list));
        $self->on_map_index_combo_changed;
    }

    return;
}

#  FIXME - should be done by parent tab
sub on_map_index_combo_changed {
    my ($self, $combo) = @_;
    $combo ||= $self->{map_index_combo};

    return if $combo->get_active < 0;

    my $index = undef;
    my $iter  = $combo->get_active_iter;

    if ($iter) {
        $index = $combo->get_model->get($iter, 0);
        $self->{analysis_list_index} = $index;

        # my $map = $self->{map};

        $self->set_cluster_colour_mode("list-values");
        $combo->show;
        $combo->set_sensitive(1);

        #  sets the min and max and triggers the recolour
        my @minmax = $self->get_parent_tab->set_plot_min_max_values;

        # $self->recolour;
        my $processed_nodes = $self->get_processed_nodes;
        $self->recolour_cluster_lines($processed_nodes);
        #  not sure why we need to do this here
        $self->map_elements_to_clusters($processed_nodes);
        $self->recolour_cluster_map;

    }
    else {
        $self->{analysis_list_index} = undef;
        $self->{analysis_min}        = undef;
        $self->{analysis_max}        = undef;
    }

    return;
}

sub recolour {
    my $self = shift;

    if ($self->{colour_start_node}) {
        $self->do_colour_nodes_below($self->{colour_start_node});
    }

    return;
}

###########################################
##
##  Graph stuff - we control the contents

sub set_graph_frame {
    my ($self, $frame) = @_;
    die "Graph frame is already set"
        if $self->{graph_frame};

    $self->{graph_frame} = $frame;
}

sub init_scree_plot {
    my ($self, %args) = @_;

    my $frame = delete $args{frame};
    $self->set_graph_frame ($frame);

    my $da = (delete $args{drawing_area}) || Gtk3::DrawingArea->new;
    $frame->set (expand => 1);  #  otherwise we shrink to not be visible
    $frame->add($da);

    my $graph = Biodiverse::GUI::Canvas::ScreePlot->new (
        %args,
        frame    => $frame,
        drawable => $da,
    );
    $graph->set_tree_canvas($self);

    $self->{scree_plot} = $graph;
}

sub get_scree_plot {
    my ($self) = @_;
    $self->{scree_plot};
}

sub show_all {
    my ($self) = @_;
    $self->SUPER::show_all;
    if (my $plot = $self->get_scree_plot) {
        $plot->show_all;
    }
}

1;
