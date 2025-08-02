package Biodiverse::GUI::Overlays::Data;
use strict;
use warnings;
use 5.036;

use feature qw/postderef/;

use Path::Tiny;
use Geo::GDAL::FFI;

use Biodiverse::GUI::Overlays::Geometry;

#  filebase matches Geo::Shapefile and makes some things easier later on
sub new {
    my ($class, $file) = @_;
    bless {filebase => $file}, $class // __PACKAGE__;
}

sub load_data {
    my ($self, $source) = @_;

    #  only one source permitted
    $source = $self->{filebase} //= $source;

    my $p  = path ($source);
    my $db = $p->parent;
    my $layer_name = $p->basename;
    my $layer;
    if ($layer_name =~ /.shp$/) {
        $layer = Geo::GDAL::FFI::Open($source)->GetLayer();
    }
    else {
        $layer = Geo::GDAL::FFI::Open($db)->GetLayer($layer_name || 0);
    }

    # my $rtree = $self->{index} = Tree::R->new;

    $self->{extent} = $layer->GetExtent;

    my @features;
    while (my $feature = $layer->GetNextFeature) {
        my $geom = $feature->GetGeomField();
        # next if $geom->GetPointCount < 2;
        my $envelope = $geom->GetEnvelope;     #  x1,x2,y1,y2
        my $extent = [@{$envelope}[0,2,1,3]];  #  x1,y1,x2,y2
        my $item = Biodiverse::GUI::Overlays::Geometry->new (
            extent   => $extent,
            geometry => $geom->GetPoints,
        );
        # $rtree->insert($item, @$extent);

        push @features, $item;
    }

    $self->{features} = \@features;

    return;
}

sub get_features {
    my ($self) = @_;
    return wantarray ? $self->{features}->@* : $self->{features};
}

#  to be consistent with Geo::Shapefile
sub shapes_in_area {
    my ($self, $x1, $y1, $x2, $y2) = @_;

    my @result;
    my $shapes = $self->get_features;
    foreach my $shape (@$shapes) {
        next if !($shape->xmin < $x2 && $shape->xmax > $x1 && $shape->ymin < $y2 && $shape->ymax > $y1);
        push @result, $shape;
    }

    return wantarray ? @result : \@result;
}



1;
