package Biodiverse::GUI::Overlays::Data;
use strict;
use warnings;
use 5.036;

use feature qw/postderef/;
use experimental qw/refaliasing/;

use Path::Tiny;
use Geo::GDAL::FFI;

use Biodiverse::GUI::Overlays::Geometry;

#  filebase matches Geo::Shapefile and makes some things easier later on
sub new {
    my ($class, $file) = @_;
    bless {filebase => $file}, $class // __PACKAGE__;
}

sub get_layer_object {
    my $self = shift;

    my $source = $self->{filebase};

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

    return $layer;
}

sub load_data {
    my ($self, %args) = @_;

    #  only one source permitted
    my $source = $self->{filebase} //= $args{source};
    my $lazy_load = $args{defer_loading};

    my $layer = $self->get_layer_object;

    # my $rtree = $self->{index} = Tree::R->new;

    $self->{extent} = $layer->GetExtent;

    my $id_array = $args{ids} // [0..$layer->GetFeatureCount()-1];

    \my @features = $self->{features} //= [];

    foreach my $id (@$id_array) {
        my $feature = $layer->GetFeature($id);
        my $geom = $feature->GetGeomField();
        # next if $geom->GetPointCount < 2;
        my $envelope = $geom->GetEnvelope;     #  x1,x2,y1,y2
        my $extent = [@{$envelope}[0,2,1,3]];  #  x1,y1,x2,y2
        say join ' ', ($id, @$extent);
        my $item = $features[$id] //= Biodiverse::GUI::Overlays::Geometry->new (
            extent   => $extent,
            id       => $id,
        );
        $item->{geometry} //= $lazy_load ? undef : $geom->GetPoints;
    }

    return;
}

sub reload_geometries {
    my ($self, $target_ids) = @_;

    my $layer = $self->get_layer_object;

    my $features = $self->get_features;

    $target_ids //= [0..$#$features];

    foreach my $id (@$target_ids) {
        my $item    = $features->[$id];
        my $feature = $layer->GetFeature($id);
        my $geom    = $feature->GetGeomField();
        $item->set_geometry ($geom->GetPoints);
    }

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
    my @need_to_load;
    foreach my $shape (@$shapes) {
        next if !($shape->xmin < $x2 && $shape->xmax > $x1 && $shape->ymin < $y2 && $shape->ymax > $y1);
        push @result, $shape;
        if (!defined $shape->get_geometry) {
            push @need_to_load, $shape->get_id;
        }
    }
    if (@need_to_load) {
        $self->load_data (ids => \@need_to_load);
    }

    return wantarray ? @result : \@result;
}



1;
