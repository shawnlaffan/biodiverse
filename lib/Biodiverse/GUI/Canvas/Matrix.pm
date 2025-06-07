package Biodiverse::GUI::Canvas::Matrix;
use strict;
use warnings;
use 5.036;

our $VERSION = '4.99_002';

use experimental qw /refaliasing declared_refs for_list/;
use Glib qw/TRUE FALSE/;
use List::Util qw /min max any/;
use List::MoreUtils qw /minmax/;
use POSIX qw /floor/;
use Carp qw /croak confess/;

use parent 'Biodiverse::GUI::Canvas::Grid';

sub new {
    my ($class, %args) = @_;

    my $self = $class->SUPER::new(%args);
    #  rebless
    bless $self, $class;

    my $row_labels = $self->get_row_labels // die 'row labels not set';
    my $size = @$row_labels;

    $self->{dims} = {
        xmin    => 0,
        ymin    => 0,
        xmax    => $size,
        ymax    => $size,
        xwidth  => $size,
        yheight => $size,
        xcen    => $size / 2,
        ycen    => $size / 2,
    };
    $self->{cellsizes} = [1, 1];
    $self->{ncells_x} = $size;
    $self->{ncells_y} = $size;
    $self->{size}     = $size;

    $self->{callbacks} = {
        map => sub {shift->draw_cells_cb (@_)},
    };

    $self->init_data;

    return $self;
}

sub callback_order {
    my $self = shift;
    return ('map');
}

sub plot_bottom_up {!!0};

sub set_row_labels {
    my ($self, $labels) = @_;
    die 'number of row labels does not match matrix grid'
        if defined $self->{size} && scalar @$labels != $self->{size};
    $self->{row_labels} = $labels;
}

sub set_col_labels {
    my ($self, $labels) = @_;
    die 'number of column labels does not match matrix grid'
        if defined $self->{size} && scalar @$labels != $self->{size};
    $self->{col_labels} = $labels;
}

sub get_row_labels {$_[0]->{row_labels}}
sub get_col_labels {$_[0]->{col_labels}}

sub get_size {
    $_[0]->{size};
}

sub init_data {
    my ($self) = @_;

    return $self->{data}
        if $self->{data};

    my %data;
    my @cellsizes = @{$self->{cellsizes}};  #  always (1,1)
    my $cell2     = 0.5;

    my $default_rgb = [(0.8) x 3];
    foreach my $col (0 .. $self->get_size-1) {
        foreach my $row (0 .. $self->get_size-1) {
            my $key = join ':', $col, $row;
            my ($x, $y) = $self->cell_to_map_centroid($col, $row);

            my $bounds = [ $x - $cell2, $y - $cell2, $x + $cell2, $y + $cell2 ];
            $data{$key}{coord} = [$x, $y];
            $data{$key}{bounds} = $bounds;
            $data{$key}{rect} = [ @$bounds[0, 1], @cellsizes ];
            $data{$key}{centroid} = [ $x, $y ];
            $data{$key}{rgb} = $default_rgb;
        }
    }

    return $self->{data} = \%data;
}

sub set_current_matrix {
    my ($self, $mx) = @_;

    if (!$mx) {
        $self->{current_matrix} = undef;
        return;
    }

    my $labels = $self->get_row_labels;
    \my %mx_element_hash = $mx->get_elements;

    my $have_overlap =  any {exists $mx_element_hash{$_}} @$labels;

    $self->{mx_overlaps} = $have_overlap;

    return if !$have_overlap;

    $self->{current_matrix} = $mx;
    my $legend = $self->get_legend;
    my $stats = $mx->get_summary_stats;
    $legend->set_stats ($stats);
    $legend->set_min_max ($stats->{MIN}, $stats->{MAX});
    $self->init_data;

    return;
}

sub get_current_matrix {
    my ($self) = @_;
    $self->{current_matrix};
}

sub current_matrix_overlaps {
    my ($self) = @_;
    return $self->{mx_overlaps};
}

sub draw_cells_cb {
    my ($self, @args) = @_;
    $self->init_data;
    return if !$self->{mx_overlaps};
    return if !$self->get_current_matrix;
    $self->SUPER::draw_cells_cb(@args);
    return;
}

sub recolour {
    my ($self) = @_;

    state @default_colour = ((0.8) x 3);

    my $mx = $self->get_current_matrix;
    return if !$mx;

    my $data = $self->{data};
    return if !keys %$data;

    my $legend = $self->legend;

    my $row_labels = $self->get_row_labels;
    my $col_labels = $self->get_col_labels;

    my $x = -1;
    for my $col_label (@$col_labels) {
        $x++;
        my $y = -1;
        ROW:
        for my $row_label (@$row_labels) {
            $y++;
            my $val = $mx->get_value (element1 => $col_label, element2 => $row_label);
            my @colour = defined $val
                ? $self->rgb_to_array($legend->get_colour($val))
                : @default_colour;
            $data->{"$x:$y"}->{rgb} = \@colour;
            # last ROW if $y == $x;  #  cannot skip as row and col label arrays can differ
            $data->{"$y:$x"}->{rgb} = \@colour;
        }
    }

    return;
}

sub _get_data {  #  dev only
    my $self = shift;
die 'should not be called';
    
    my %data;
    my $n = $self->{size};
    my @cellsizes = (1, 1);
    my $cell2     = 0.5;

    srand(12345);
    for my $row (0 .. $n - 1) {

        for my $col (0 .. $n - 1) {
            next if rand() < 0.15;
            last if $row == $col;

            foreach my $pair ([$col, $row], [$row, $col]) {
                my $key = join ':', @$pair;
                my ($x, $y) = $self->cell_to_map_centroid(@$pair);

                my $coord = $pair;
                my $bounds = [ $x - $cell2, $y - $cell2, $x + $cell2, $y + $cell2 ];
                my $val = $x + $y;
                $data{$key}{val} = $val;
                $data{$key}{coord} = [$x, $y];
                $data{$key}{bounds} = $bounds;
                $data{$key}{rect} = [ @$bounds[0, 1], @cellsizes ];
                $data{$key}{centroid} = [ $x, $y ];

                my $rgb = [ $col / $n, $row / $n, 0 ];
                $data{$key}{rgb} = $rgb;
                $data{$key}{rgb_orig} = [ @$rgb ];
            }
        }

    }

    # use DDP;
    # my @x = sort keys %data;
    # p @x;
    # my $x = $data{"1:0"};
    # p $x;

    return \%data;
}


1;
