package Biodiverse::BaseData::LabelRanges;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use Carp qw /croak/;

use experimental qw /refaliasing declared_refs/;

use Geo::GDAL::FFI;

#  get a convex hull of the label's range
sub get_label_range_convex_hull {
    my ($self, %args) = @_;
    my $label = $args{label};
    \my @axes  = $args{axes} // [0,1];

    my @res = $self->get_cell_sizes;

    croak "Cannot calculate convex hull on single axis"
        if @res == 1;
    croak "Cannot calculate convex hull on more than two axes"
        if @res > 2;
    croak "Cannot calculate convex hull on text axes"
        if $res[0] < 0 || $res[1] < 0;

    my $elements = $self->get_groups_with_label_as_hash_aa($label);

    # my $lb = $self->get_labels_ref;
    my $gp = $self->get_groups_ref;

    my $c1 = $res[0] / 2;
    my $c2 = $res[1] / 2;

    # my $pts = '';
    my $wkt = "MULTIPOLYGON (";
    foreach my $el (keys %$elements) {
        my $coords = $gp->get_element_name_as_array_aa($el);
        my ($x, $y) = @$coords[@axes];
        my ($x1, $x2) = ($x - $c1, $x + $c1);
        my ($y1, $y2) = ($y - $c2, $y + $c2);
        $wkt .= "(($x1 $y1, $x1 $y2, $x2 $y2, $x2 $y1, $x1 $y1)), ";
        # $pts .= "($x $y), ";
    }
    $wkt =~ s/, $//;
    $wkt .= ')';

    my $g = Geo::GDAL::FFI::Geometry->new(WKT => $wkt);
    my $hull = $g->ConvexHull;

    # say STDERR $pts;
    # say STDERR $wkt;

    return $args{as_wkt} ? $hull->ExportToWKT : $args{as_json} ? $hull->ExportToJSON : $hull;
}



1;