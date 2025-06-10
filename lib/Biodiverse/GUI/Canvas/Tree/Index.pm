package Biodiverse::GUI::Canvas::Tree::Index;
use strict;
use warnings;
use 5.036;

our $VERSION = '4.99_002';

use Tree::R;
use POSIX qw /floor/;
use List::Util qw /min max reduce/;
use List::MoreUtils qw /minmax/;
use Time::HiRes qw /time/;
use experimental qw /refaliasing/;

sub new {
    my ($class) = @_;

    my $self = {};

    return bless $self, $class;
}

sub populate_from_tree {
    my ($self, $tree) = @_;

    my $branch_hash = $tree->{data}{by_node};
    my $line_width  = max ($tree->get_horizontal_line_width, 0.02);  #  need to tweak this
    my $lw2         = $self->{lw2} //= $line_width / 2;

    if ($self->{line_width} && ($line_width == $self->{line_width})) {
        say "Tree index: Line width unchanged ($line_width), not rebuilding";
        return $self;
    }

    local $| = 1;
    # say 'Sorting';
    #  add from the right - actually makes things worse
    # my @branches = sort {$a->{y} <=> $b->{y} || $a->{x_r} <=> $b->{x_r}} values %$branch_hash;
    my @branches = values %$branch_hash;
    # use DDP; p %$branch_hash;
    say sprintf 'Box index: Inserting %d branches', scalar @branches;

    my $start_time = time();
    my $nboxes = 50;
    my $box_size = 1 / $nboxes;

    # say 'generating';

    my %boxes;
    foreach my $branch (values %$branch_hash) {

        my ($x_l, $x_r) = minmax (@$branch{qw /x_l x_r/});  #  handle neg lens
        $x_l = 0 if $x_l < 0;  #  dirty and underhanded - should round off

        #  Maxima go one cell past the coord, partly to allow for
        #  floating point issues with the iterators below
        my $ymin = floor (($branch->{y} - $lw2) / $box_size) * $box_size;
        my $ymax = $box_size + floor (($branch->{y} + $lw2) / $box_size) * $box_size;
        my $xmin = floor ($x_l / $box_size) * $box_size;
        my $xmax = $box_size + floor ($x_r / $box_size) * $box_size;

        # say join ' ', $xmin, $ymin, $xmax, $ymax;
        # say join @$branch{qw /x_l x_r y/};

        my $x = $xmin;
        while ($x <= $xmax) {
            my $y = $ymin;
            while ($y <= $ymax) {
                my $key = "$x:$y";
                my $aref = $boxes{$key} //= [];
                push @$aref, $branch;
                $y += $box_size;
            }
            $x += $box_size;
        }
    }

    # use DDP; p %boxes;
    #  rtree with no empties
    my $rtree = Tree::R->new;
    foreach my $boxkey (keys %boxes) {
        my ($x, $y) = split ':', $boxkey;
        $rtree->insert($boxes{$boxkey}, $x, $y, $x + $box_size, $y + $box_size);
    }

    my $elapsed = time() - $start_time;
    # say "Done in $elapsed s";
    # say scalar keys %boxes;

    $self->{boxes} = \%boxes;
    $self->{rtree} = $rtree;
    $self->{line_width} = $line_width;

    return $self;
}

sub intersects_slider {
    my ($self, @b) = @_;

    my @results;
    $self->{rtree}->query_partly_within_rect(@b, \@results);

    my %bres_hash;
    foreach my $box (@results) {
        foreach my $branch (@$box) {
            next if $bres_hash{$branch->{name}};
            my ($x_l, $x_r) = minmax (@$branch{qw /x_l x_r/});  #  allow for negative branches
            if (max ($b[0], $x_l) <= min ($b[2], $x_r)) {
                # branch intersects slider
                $bres_hash{$branch->{name}} //= $branch;
            }
        }
    }
    #  exclude children if we have the parent
    my @bres2 = grep {!exists ($bres_hash{$_->{parent} // die "no parent for $_->{name}"})} values %bres_hash;

    return wantarray ? @bres2 : \@bres2;
}

sub query_point {
    my ($self, $x, $y) = @_;

    my @candidates;
    $self->{rtree}->query_point($x, $y, \@candidates);

    my $lw2 = $self->{lw2};

    my %bres_hash;
    foreach my $box (@candidates) {
        foreach my $branch (@$box) {
            my ($x_l, $x_r) = minmax (@$branch{qw /x_l x_r/});  #  allow for negative branches
            if ($x_l <= $x && $x_r >= $x && $y <= $branch->{y} + $lw2 && $y >= $branch->{y} - $lw2) {
                # branch intersects slider
                $bres_hash{$branch->{name}} //= $branch;
            }
        }
    }
    #  exclude children if we have the parent
    my @bres2 = grep {!exists $bres_hash{$_->{parent} // ''}} values %bres_hash;

    return wantarray ? @bres2 : \@bres2;
}

sub query_point_nearest_y {
    my ($self, $x, $y) = @_;

    \my @candidates = $self->query_point($x, $y);

    #  no need to filter if we have zero or one item
    return wantarray ? @candidates : \@candidates
        if @candidates <= 1;

    #  find the branch closest to $y
    my @bres2 = reduce {abs ($y - $a->{y}) < abs ($y - $b->{y}) ? $a : $b } @candidates;

    return wantarray ? @bres2 : \@bres2;
}

1;
