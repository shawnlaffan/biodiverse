package Biodiverse::GUI::Overlays::Data;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use feature qw/postderef/;
use experimental qw/refaliasing/;

use Path::Tiny;
use Geo::GDAL::FFI;
use Ref::Util qw /is_arrayref/;

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
        # my $ds = Geo::GDAL::FFI::Open($db);
        # for my $i (0 .. $ds->GetLayerCount-1) {
        #     my $name = Geo::GDAL::FFI::OGR_L_GetName (Geo::GDAL::FFI::GDALDatasetGetLayer($$ds, $i));
        #     say $name;
        # }
        # my $x = $layer->GetFeature(1);
        # say $x;
    }

    return $layer;
}

sub load_data {
    my ($self, %args) = @_;

    my $lazy_load = $args{defer_loading};

    my $layer = $self->get_layer_object;

    $self->{extent} = $layer->GetExtent;
    $self->{type}   = $layer->GetDefn->GetGeomFieldDefn->GetType;
    my $is_multi_type = $self->{type} =~ /Multi/;

    #  Does the source start IDs at 0 or 1?   sqlite uses 1, hence geopackages do also.
    #  We use zero so need to correct for ones below.
    my $fid_base = $self->{fid_base} //= !eval {$layer->GetFeature(0)};

    my $id_array = $args{ids} // [0..$layer->GetFeatureCount()-1];

    \my @features = $self->{features} //= [];

    foreach my $id (@$id_array) {
        my $feature  = $layer->GetFeature($id + $fid_base);
        my $geom     = $feature->GetGeomField();
        #  get type at the geom  level as
        #  shapefile layers don't flag as multi
        my $type     = $geom->GetType;
        my $item = $features[$id] //= Biodiverse::GUI::Overlays::Geometry->new (
            extent => [@{$geom->GetEnvelope}[0,2,1,3]],  #  x1,y1,x2,y2
            id     => $id,
            type   => $type,
        );
        if (!($lazy_load && $item->{geometry})) {
            my $g = $geom->GetPoints (0, 0);  #  no Z or M
            $is_multi_type = $item->{type} =~ /Multi/;
            #  this way we have one structure for the plotting to handle
            $item->{geometry} = $is_multi_type ? $g : [ $g ];
        }
    }

    return;
}

sub reload_geometries {
    my ($self, $target_ids) = @_;

    my $layer = $self->get_layer_object;

    my $features = $self->get_features;

    $target_ids //= [0..$#$features];

    my $fid_base = $self->{fid_base};

    foreach my $id (@$target_ids) {
        my $item    = $features->[$id + $fid_base];
        my $feature = $layer->GetFeature($id);
        my $geom    = $feature->GetGeomField();
        $item->set_geometry ($geom->GetPoints(0,0));  #  no Z or M
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
