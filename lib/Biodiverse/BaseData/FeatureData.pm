package Biodiverse::BaseData::FeatureData;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use experimental qw /refaliasing declared_refs/;
use Geo::GDAL::FFI;
use Carp qw /croak/;

sub get_groups_as_geopackage {
    my ($self, %args) = @_;

    my @res = $self->get_cell_sizes;
    \my @axes = $args{axes} // [0,1];

    croak "Cannot calculate geopackage for a single axis"
        if @res == 1;
    croak "Cannot calculate geopackage for text axes"
        if $res[$axes[0]] < 0 || $res[$axes[1]] < 0;

    my $as_points = $args{as_points} // $args{as_point};

    croak "Cannot calculate geopackage for point axes"
        if $res[$axes[0]] == 0 || $res[$axes[1]] == 0;

    my $geometry_type = $as_points ? 'Point' : 'Polygon';

    my $cache_key = "${geometry_type}_axes_" . join ':', @axes;

    #  use the volatile cache to avoid issues with serialisation and GDAL objects
    my $vcache = $self->get_volatile_cache;
    my $cached_data = $vcache->get_cached_value_dor_set_default_href ('GROUP_COORDS_AS_GEOPACKAGE');

    if (my $cached = $cached_data->{$cache_key}) {
        return $cached;
    }

    \my @gp_names = $self->get_groups;
    my $gp = $self->get_groups_ref;

    my $ds_name = "/vsimem/BASEDATA_GROUPS_${self}.gpkg";
    my $gpkg
        = Geo::GDAL::FFI::GetDriver('GPKG')->Create ($ds_name);
    my $layer = $gpkg->CreateLayer({
        Name => ('group_coords_axes_'. join '_', @axes),
        GeometryType => $geometry_type,
        Options => {SPATIAL_INDEX => 'YES'},
        Fields => [
            {Name => 'ELEMENT', Type => 'String'},
            {Name => 'Axis0',   Type => 'Real'},
            {Name => 'Axis1',   Type => 'Real'},
        ],
    });

    my ($cx, $cy) = ($res[0] / 2, $res[1] / 2);

    if (!@gp_names) {
        my $wkt = $as_points ? "POINT EMPTY" : "POLYGON EMPTY";
        my $g = Geo::GDAL::FFI::Geometry->new(WKT => $wkt);
        my $f = Geo::GDAL::FFI::Feature->new($layer->GetDefn);
        $f->SetGeomField($g);
        $layer->CreateFeature($f);
    }
    else {
        foreach my $name (@gp_names) {
            my $coords = $gp->get_element_name_as_array_aa($name);
            my ($x, $y) = @$coords[@axes];
            my $wkt;
            if ($as_points) {
                $wkt = "POINT ($x $y)";
            }
            else {
                $wkt = sprintf(
                    "POLYGON ((%s %s, %s %s, %s %s, %s %s, %s %s))",
                    $x-$cx, $y-$cy,
                    $x-$cx, $y+$cy,
                    $x+$cx, $y+$cy,
                    $x+$cx, $y-$cy,
                    $x-$cx, $y-$cy,
                );
            }
            my $g = Geo::GDAL::FFI::Geometry->new(WKT => $wkt);
            my $f = Geo::GDAL::FFI::Feature->new($layer->GetDefn);
            $f->SetGeomField($g);
            $f->SetField(ELEMENT => $name);
            $f->SetField(Axis0 => $x);
            $f->SetField(Axis1 => $y);
            $layer->CreateFeature($f);
        }
    }

    return $cached_data->{$cache_key} = $gpkg;
}


1;