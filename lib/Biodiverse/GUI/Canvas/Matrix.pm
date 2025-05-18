package Biodiverse::GUI::Canvas::Matrix;
use strict;
use warnings;
use 5.036;

our $VERSION = '4.99_002';

use experimental qw /refaliasing declared_refs for_list/;
use Glib qw/TRUE FALSE/;
use List::Util qw /min max/;
use List::MoreUtils qw /minmax/;
use POSIX qw /floor/;
# use Data::Printer;
use Carp qw /croak confess/;

use parent 'Biodiverse::GUI::Canvas::Grid';

sub new {
    my ($class, %args) = @_;
    my $size = $args{size};
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
    $args{cellsizes} = [1, 1];
    $args{ncells_x} = $size;
    $args{ncells_y} = $size;

    my $self = Biodiverse::GUI::Canvas->new (%args);

    #  rebless
    bless $self, $class;

    $self->{callbacks} = {
        map => sub {shift->draw_cells_cb (@_)},
    };

    $self->{data} = $self->get_data();
    # say join ' ', $self->get_data_extents;

    return $self;
}

sub callback_order {
    my $self = shift;
    return ('map');
}

sub plot_bottom_up {!!0};

sub get_data {
    my $self = shift;

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
