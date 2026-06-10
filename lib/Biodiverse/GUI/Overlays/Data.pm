package Biodiverse::GUI::Overlays::Data;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.99_001';

use feature qw/postderef/;
use experimental qw/refaliasing/;

use Path::Tiny;
use Geo::GDAL::FFI;
use Ref::Util qw /is_arrayref/;

use Biodiverse::GUI::Overlays::Geometry;

use parent 'Biodiverse::Common';

#  filebase matches Geo::Shapefile and makes some things easier later on
sub new {
    my ($class, $file) = @_;
    bless {filebase => $file}, $class // __PACKAGE__;
}

sub get_layer_object {
    my $self = shift;

    return $self->get_gdal_feature_class_layer_from_path (path => $self->{filebase});
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

    ID:
    foreach my $id (@$id_array) {
        my $feature  = $layer->GetFeature($id + $fid_base);
        my $is_empty;
        my $geom = eval {$feature->GetGeomField()};
        if (!defined $geom) {
            $geom = Geo::GDAL::FFI::Geometry->new(WKT => "$self->{type} EMPTY");
            $is_empty = 1;
        }

        #  get type at the geom level as
        #  shapefile layers don't flag as multi and can have a mix of multi and non-multi
        my $type = $geom->GetType;
        my $item = $features[$id] //= Biodiverse::GUI::Overlays::Geometry->new (
            extent => [@{$geom->GetEnvelope}[0,2,1,3]],  #  x1,y1,x2,y2
            id     => $id,
            type   => $type,
        );

        next ID if $lazy_load;

        if (!$item->{geometry}) {
            if ($is_empty) {
                $item->{geometry} = [];
            }
            else {
                $is_multi_type = $item->{type} =~ /Multi/;
                my $g = $geom->GetPoints(0, 0); #  no Z or M
                if ($item->{type} =~ /LineString$/) {
                    #  same depth as polygons to simplify downstream processing/plotting
                    $g = [ $g ];
                }
                #  this way we have one structure for the plotting to handle
                $item->{geometry} = $is_multi_type ? $g : [ $g ];
            }
        }
    }

    return;
}

#  this seems not to be triggered but still needs to match load_data behaviour
sub reload_geometries {
    my ($self, $target_ids) = @_;

    my $layer = $self->get_layer_object;

    my $features = $self->get_features;

    $target_ids //= [0..$#$features];

    my $fid_base = $self->{fid_base};

    foreach my $id (@$target_ids) {
        my $item    = $features->[$id + $fid_base];
        my $feature = $layer->GetFeature($id);
        my $geom    = eval {$feature->GetGeomField()} // Geo::GDAL::FFI::Geometry->new(WKT => "$self->{type} EMPTY");
        my $g;
        if ($geom->IsEmpty) {
            $g = [];
        }
        else {
            $g = $geom->GetPoints(0, 0);
            my $type = $geom->GetType;
            if ($type =~ /LineString$/) {
                $g = [ $g ];
            }
            if ($type =~ /Multi/) {
                $g = [ $g ];
            }
        }
        $item->set_geometry ($g);  #  no Z or M
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
