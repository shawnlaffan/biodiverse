package Biodiverse::GUI::Canvas::Tree;
use strict;
use warnings;
use 5.036;

our $VERSION = '4.99_002';

use experimental qw /refaliasing declared_refs for_list/;
use Glib qw/TRUE FALSE/;
use Scalar::Util qw /refaddr/;
use List::Util qw /min max/;
use List::MoreUtils qw /minmax/;
use Ref::Util qw /is_coderef/;
use POSIX qw /floor/;
use Carp qw /croak confess/;
use Sort::Key qw /rnkeysort/;

use Biodiverse::GUI::Canvas::Tree::Index;

use parent 'Biodiverse::GUI::Canvas';

sub new {
    my ($class, %args) = @_;
    my $size = 1;
    $args{dims} = {
        xmin    => 0,
        ymin    => 0,
        xmax    => $size,
        ymax    => $size,
        xwidth  => $size,
        yheight => $size,
        xcen    => $size / 2,
        ycen    => $size / 2,
    };

    my $self = Biodiverse::GUI::Canvas->new (%args);

    #  rebless
    bless $self, $class;

    $self->init_legend(%args, parent => $self);

    # warn 'Tree is using default data';
    # $self->{data} = $self->get_data($args{ntips});
    # $self->init_plot_coords;
    # say join ' ', $self->get_data_extents;

    $self->{callbacks} = {
        plot => sub {shift->draw (@_)},
        #  update graph if present
    };

    return $self;
}

sub callback_order {
    my $self = shift;
    return ('plot');
}

sub set_current_tree {
    my ($self, $tree, $plot_mode) = @_;

    if (!defined $tree) {
        $self->{data} = {};
        $self->{current_tree} = undef;
        $self->{plot_coords_generated} = undef;
        return;
    }

    state %mode_methods = (
        length => 'get_length',
        depth  => sub {1},
    );

    #  future proofing: allow a code ref
    my $len_method
        = is_coderef($plot_mode)
        ? $plot_mode
        : $mode_methods{$plot_mode} // 'get_length';

    #  Don't needlessly regenerate the data
    return if defined $self->{current_tree}
        && refaddr($tree) == refaddr($self->{current_tree})
        && $self->{plot_mode} eq $len_method;

    use Sort::Key qw /ikeysort rikeysort/;
    $tree->number_terminal_nodes;  #  need to keep this in a cache for easier cleanup
    my $terminals = $tree->get_terminal_node_refs;
    my @tips = ikeysort {$_->get_value('TERMINAL_NODE_FIRST')} @$terminals;

    #  this could probably be optimised but we'll need to profile first
    my $longest_path = 0;
    my %branch_hash;
    foreach my $node (@tips) {
        my $name = $node->get_name;
        $branch_hash{$name}{name} = $name;
        $branch_hash{$name}{node_ref} = $node;
        $branch_hash{$name}{ntips}    = 0;
        my $len  = $node->$len_method;
        $branch_hash{$name}{length} = $len;
        my $path = $branch_hash{$name}{path_to_root} = [$len];  #  still needed?
        my $parent = $node;
        while ($parent = $parent->get_parent) {
            my $this_len = $parent->$len_method;
            $len += $this_len;
            push @$path, $this_len;
            my $parent_name = $parent->get_name;
            $branch_hash{$parent_name}{ntips}++;
            if (!$branch_hash{$parent_name}{node_ref}) {
                $branch_hash{$parent_name}{node_ref} = $parent;
                $branch_hash{$parent_name}{length}   = $this_len;
                $branch_hash{$parent_name}{name}     = $parent_name;
            }
        }
        $longest_path = $len if $len > $longest_path;
    }

    my @roots = $tree->get_root_node_refs;  #  we can have multiple roots
    my $root_tree_node = $roots[0];
    my $root = $branch_hash{$root_tree_node->get_name};

    my %properties = (
        root         => $root,
        by_node      => \%branch_hash,
        tips         => \@tips,
        ntips        => scalar (@tips),
        longest_path => $longest_path,
    );

    $self->{data} = \%properties;
    $self->{current_tree} = $tree;
    $self->{plot_mode} = $len_method;
    $self->{plot_coords_generated} = undef;

    $self->init_plot_coords;

    return;
}

sub get_current_tree {
    $_[0]->{current_tree};
}

sub _on_motion {
    my ($self, $widget, $event, $ref_status) = @_;

    return FALSE if $self->{mode} ne 'select';
    return FALSE if !$self->{plot_coords_generated};

    my ($x, $y) = $self->get_event_xy($event);

    my $current_cursor_name = $self->{motion_cursor_name} //= 'default';

    if (!$self->{no_draw_slider}) {
        my $slider = $self->{slider_coords};
        \my @b = $slider->{bounds};

        if ($self->{sliding}) {
            $slider->{x} = $x;
            my $w = ($b[2] - $b[0]) / 2;
            $b[0] = $x - $w;
            $b[2] = $x + $w;
            $slider->{x} = $x;

            #  get the overlapping branches
            my @bres = $self->get_index->intersects_slider(@b);

            $self->set_cursor_from_name ('pointer');
            $widget->queue_draw;
            return FALSE;
        }
        else {
            if ($x >= $b[0] && $x < $b[2] && $y >= $b[1] && $y < $b[3]) {
                $self->set_cursor_from_name ('pointer');
                $self->{motion_cursor_name} = 'pointer';
                return FALSE;
            }
            else {
                #  reset - needs to be in a conditional or we stop the slide
                $self->set_cursor_from_name ($current_cursor_name);
            }
        }

    }

    \my @results = $self->get_index->query_point ($x, $y);

    #  should get cursor name from mode
    my $new_cursor_name = @results ? 'pointer' : 'default';
    if ($current_cursor_name ne $new_cursor_name) {
        #  change mouse style
        $self->set_cursor_from_name ($new_cursor_name);
        $self->{motion_cursor_name} = $new_cursor_name;
    }

    return FALSE;
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

    if (!$self->{no_draw_slider} && $self->{selecting}) {
        my $slider = $self->{slider_coords};
        \my @b = $slider->{bounds};
        if ($x >= $b[0] && $x < $b[2] && $y >= $b[1] && $y < $b[3]) {
            $self->{sliding} = 1;
            # say 'SLIDER';

            $self->set_cursor_from_name ('pointer');

            $widget->queue_draw;
            return FALSE;
        }
    }

    return FALSE if $x > $self->xmax || $y > $self->ymax;

    my @branches = $self->get_index->query_point_nearest_y ($x, $y);
    foreach my $branch (@branches) {
        say 'BT: ' . $branch->{name} if $branch;
    }

    return;
}

sub draw_slider {
    my ($self, $cx) = @_;

    return if $self->{no_draw_slider};

    #  might only need the x coord
    my $slider_coords
      = $self->{slider_coords} //= {
          x  => 1,
          y0 => 0,
          y1 => 1,
      };

    my ($x, $y0, $y1) = @{$slider_coords}{qw/x y0 y1/};

    my $line_width = ($y1 - $y0) / 100;  #  need to work on this

    $cx->set_source_rgb(0, 0, 1);
    $cx->move_to($x, 0);
    $cx->line_to($x, 1);
    $cx->stroke;

    $slider_coords->{bounds} = [
        $x - $line_width / 2, $y0,
        $x + $line_width / 2, $y1,
    ];

    if ($self->{sliding}) {
        my $text = 'ST';
        my $old_mx = $cx->get_matrix;
        #  needs to work in page units
        my @loc = $cx->user_to_device ($x, ($y1+$y0)/2);
        $cx->set_matrix($self->{orig_tfm_mx});
        $cx->set_source_rgb(0, 0, 1);
        $cx->select_font_face("Sans", "normal", "bold");
        $cx->set_font_size( 50 );
        $cx->move_to(@loc);
        $cx->show_text($text);
        $cx->stroke;
        $cx->set_matrix($old_mx);
    };

    return;
}

#  branch line width in canvas units
sub get_horizontal_line_width {
    my ($self) = @_;

    my $ntips  = $self->{data}{ntips};
    my $dims_h = $self->{dims};  #  full plot
    my $disp_h = $self->{disp};  #  current zoom
    my $dims_ymin = $dims_h->{ymin};
    my $dims_ymax = $dims_h->{ymax};
    my $disp_ymin = $disp_h->{ymin} // $dims_ymin;
    my $disp_ymax = $disp_h->{ymax} // $dims_ymax;

    my $line_width = $self->get_branch_line_width;
    if (!$ntips) {
        $line_width = 1;
    }
    elsif (!$line_width) {
        #  calculate it as a function of the plot height
        my $frac_displayed = ($disp_ymax - $disp_ymin) / ($dims_ymax - $dims_ymin);
        $frac_displayed = min(1, $frac_displayed); #  use dims if zoomed out
        $line_width = ($disp_ymax - $disp_ymin) / ($ntips * 3 * $frac_displayed);
    }
    else {  #  convert pixel to canvas
        my $drawable = $self->drawable;
        my $draw_size = $drawable->get_allocation();
        my $canvas_height = $draw_size->{height};
        $line_width /= $canvas_height;
    }

    return $line_width;
}

#  ensure the vertical lines are the same as the horizontal ones
sub get_vertical_line_width {
    my ($self, $hline_width) = @_;

    my @scaling = $self->get_scale_factors;

    return ($hline_width // $self->get_horizontal_line_width) * $scaling[1] / $scaling[0];
}

sub x_scale {
    1 / $_[0]->{data}{longest_path}
}

sub y_scale {
    1 / $_[0]->{data}{ntips};
}

sub draw {
    my ($self, $cx) = @_;

    #  need to handle negative branches - these can push the rhs out past the root
    #  (or really the root inwards relative to the branches)

    my $data = $self->{data};
    my $root = $data->{root};
    my $node_hash = $data->{by_node};

    $self->init_plot_coords;

    $cx->set_source_rgb(0.8, 0.8, 0.8);
    $cx->rectangle (0, 0, 1, 1);
    $cx->fill;

    my $h_line_width = $self->get_horizontal_line_width;
    my $v_line_width = $self->get_vertical_line_width ($h_line_width);

    $cx->set_line_cap ('butt');

    foreach my $branch (values %$node_hash) {

        my ($x_r, $x_l, $y) = @{$branch}{qw/x_r x_l y/};

        $cx->set_line_width($h_line_width);

        #  mid-grey
        $cx->set_source_rgb(0.4, 0.4, 0.4);
        $cx->move_to($x_r, $y);
        $cx->line_to($x_l, $y);
        $cx->stroke;

        #  vertical connectors - will be more direct in biodiverse as they are objects already
        my @children = map {$node_hash->{$_}} @{$branch->{children}};
        if (@children) {
            $cx->set_line_cap ('round');
            $cx->set_line_width($v_line_width);
            $cx->move_to($x_l, $children[0]{y});  #  first child
            $cx->line_to($x_l, $children[-1]{y});  #  last child
            $cx->stroke;
            $cx->set_line_cap ('butt');
        }
    }

    $self->draw_slider($cx);

    return;
}

sub init_plot_coords {
    my ($self) = @_;

    return if $self->{plot_coords_generated};

    my $data = $self->{data};

    #  start with the y-coords
    my $tree = $self->get_current_tree;
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
            $branch_ref->{_y} = $node_ref->get_value('TERMINAL_NODE_FIRST') - 0.5;
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

    $root->{x_r} //= 1;

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

    $self->{plot_coords_generated} = 1;

    #  trigger index generation
    my $box_index = $self->get_index;

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
    my ($self, $n) = @_;
    $self->{num_clusters} = $n;
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
    my $tree = $self->{current_tree};

    #  Much commented code due to porting across from Dendrogram.pm

    # Work out how to get the "length" based on mode
    if ($plot_mode eq 'length') {
        #  handled in the plot method
        delete $self->{length_func};
    }
    elsif ($plot_mode eq 'depth') {
        delete $self->{length_func};
    }
    elsif ($plot_mode =~ 'equal_length|range_weighted') {
        #  Create an alternate tree with the chosen properties.
        #  Use a cache for speed.
        #  Basedata will not change for lifetime of object
        #  as GUI does not support in-place deletions.
        my $gui_tree  = $self->get_parent_tab->get_current_tree;
        my $cache_key = "tree_for_plot_mode_${plot_mode}_from_${gui_tree}";
        my $cache = $self->get_cached_value_dor_set_default_href ($cache_key);
        my $alt_tree  = $cache->{tree};

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
            my $func = sub {
                $alt_tree->get_node_ref_aa($_[0]->get_name)->get_length;
            };
            $self->{length_func} = $func;
            $plot_mode = $func;
            $cache->{tree} = $alt_tree;
            $cache->{plot_mode} = $plot_mode;
        }
        $plot_mode = $cache->{plot_mode};

        #  We are passed nodes from the original tree, so use their names to
        #  look up the ref in the alt tree.  Too complex now?
        #  don't use a state var as we cache on it and don't detect changes otherwise

    }
    else {
        die "Invalid cluster-plotting mode - $plot_mode";
    }

    $self->set_current_tree ($tree, $plot_mode);

    return;
}

1;
