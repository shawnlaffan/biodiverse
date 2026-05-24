package Biodiverse::SpatialConditions::Polygons;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use experimental qw /refaliasing for_list isa/;

use Carp;
use English qw /-no_match_vars/;

use Math::Polygon ();
use Geo::ShapeFile 3.00 ();
use Tree::STR ();
use Scalar::Util qw /looks_like_number blessed/;
use List::Util qw /min max any/;
use Ref::Util qw /is_arrayref/;
use Path::Tiny qw /path/;
use Hash::Util::Set qw/keys_disjoint/;
use Geo::GDAL::FFI;

use Biodiverse::Metadata::SpatialConditions;

my $NULL_STRING = q{};

sub get_metadata_sp_point_in_poly {
    my $self = shift;

    my $example = <<~'END_SP_PINPOLY'
        # Is the neighbour coord in a square polygon?
        sp_point_in_poly (
            polygon => [[0,0],[0,1],[1,1],[1,0],[0,0]],
            point   => \@nbrcoord,
        )

        END_SP_PINPOLY
    ;

    my %metadata = (
        description =>
            "Select groups that occur within a user-defined polygon \n"
                . '(see sp_point_in_poly_shape for an alternative)',
        required_args      => [
            'polygon',           #  array of vertices, or a Math::Polygon object
        ],
        optional_args => [
            'point',      #  point to use
        ],
        index_no_use => 1,
        result_type  => 'always_same',
        example      => $example,
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_point_in_poly {
    my ($self, %args) = @_;

    my $vertices = $args{polygon};
    my $point = $args{point} // $self->get_current_coord_array;

    my $poly = $vertices isa 'Math::Polygon'
        ? $vertices
        : Math::Polygon->new( points => $vertices );

    return $poly->contains($point);
}

sub _get_shp_examples {
    my $examples = <<~'END_OF_SHP_EXAMPLES'
        # Is the neighbour coord in a shapefile?
        sp_point_in_poly_shape (
            file  => 'c:\biodiverse\data\coastline_lamberts',
            point => \@nbrcoord,
        );

        # Is the neighbour coord in a geopackage layer?
        sp_point_in_poly_shape (
            file  => 'c:/biodiverse/data/coastline.gpkg/layername',
            point => \@nbrcoord,
        );

        # Is the neighbour coord in a shapefile's second polygon (counting from 1)?
        sp_point_in_poly_shape (
            file      => 'c:\biodiverse\data\coastline_lamberts',
            field_val => 2,
            point     => \@nbrcoord,
        );

        # Is the neighbour coord in a polygon with value 2 in the OBJECT_ID field?
        sp_point_in_poly_shape (
            file       => 'c:\biodiverse\data\coastline_lamberts',
            field_name => 'OBJECT_ID',
            field_val  => 2,
            point      => \@nbrcoord,
        );
        END_OF_SHP_EXAMPLES
    ;
    return $examples;
}

sub get_metadata_sp_point_in_poly_shape {
    my $self = shift;

    my $examples = $self->_get_shp_examples;

    my $descr = <<~'EOD'
        Select groups that occur within a polygon or polygons from a geospatial
        feature data set such as a shapefile or geopackage layer
        EOD
    ;

    my %metadata = (
        description => $descr,
        required_args => [
            qw /file/,
        ],
        optional_args => [
            qw /point field_name field_val axes/,
        ],
        index_no_use => 1,
        result_type  => 'always_same',
        example => $examples,
        aggregate_substitute_method => {
            re_name => 'point_in_poly_shape',
            method  => '_aggregate_point_in_poly_shape',
        },
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_point_in_poly_shape {
    my ($self, %args) = @_;

    croak 'axes arg must have only two axes'
        if $args{axes} && is_arrayref $args{axes} && @{$args{axes}} != 2;

    \my @axes = $args{axes} // [0,1];

    my $point = $args{point} // $self->get_current_coord_array;

    my ($x_coord, $y_coord) = @{$point}[@axes];

    my $cached_results = $self->get_cache_sp_point_in_poly_shape(%args);
    my $point_string = join (':', $x_coord, $y_coord);

    return $cached_results->{$point_string}
        if defined $cached_results->{$point_string};

    #  if we get here then we've been passed a coord that is not one of the group centroids
    my $point_geom = Geo::GDAL::FFI::Geometry->new(WKT => "POINT ($x_coord $y_coord)");
    my ($fname, $lyrname) = $self->_parse_gdal_dataset_layer_string_aa ($args{file});
    my $ds = Geo::GDAL::FFI::Open($fname);
    my $filtered = $ds->ExecuteSQL (
        qq{SELECT * FROM "$lyrname"},
        $point_geom,
        'SQLite',
    );

    return $cached_results->{$point_string} = $filtered->GetFeatureCount(1);
}

sub _aggregate_point_in_poly_shape {
    my ($self, %args) = @_;

    #  no point continuing if no basedata
    my $bd = $self->get_basedata_ref // return;

    my $conditions = $self->get_conditions_nws;

    my $re = $self->get_regex (name => 'point_in_poly_shape');

    return if not $conditions =~ /$re/ms;

    my $negated          = $+{negated};
    my $method_args_hash = $self->get_param ('METHOD_ARG_HASHES');
    my $method_name      = $+{method};
    my $method_args_text = $+{args};
    my $method_args  = $method_args_hash->{$method_name . $method_args_text} // {};

    #  no aggregate if user specified the point to use
    return if defined $method_args->{point};

    \my @axes = $method_args->{axes} // [0,1];

    return if join (':', @axes) ne '0:1';  #  only axes 0,1 for now

    \my %cache = $self->get_cache_sp_point_in_poly_shape(%$method_args);

    my %intersects = $negated
        ? map {!$cache{$_} ? ($_ => 1) : ()} keys %cache
        : map { $cache{$_} ? ($_ => 1) : ()} keys %cache;

    #  The cache might have extras so filter down.
    #  Ordinarily we will have as many cache keys as we have groups.
    \my %gps = $bd->get_groups_ref->get_element_hash;
    if (keys %gps != keys %cache) {
        %intersects = map {exists $gps{$_} ? ($_ => 1) : ()} keys %intersects;
    }

    return wantarray ? %intersects : \%intersects;
}

sub vec_sp_point_in_poly_shape {
    my ($self, %args) = @_;

    #  no point continuing if no basedata
    my $bd = $self->get_basedata_ref // return;

    \my @axes = $args{axes} // [0,1];

    return if join (':', @axes) ne '0:1';  #  only axes 0,1 for now

    \my %cache = $self->get_cache_sp_point_in_poly_shape(%args);

    my %intersects = map { $cache{$_} ? ($_ => 1) : ()} keys %cache;

    #  The cache might have extras so filter down.
    #  Ordinarily we will have as many cache keys as we have groups.
    \my %gps = $bd->get_groups_ref->get_element_hash;
    if (keys %gps != keys %cache) {
        %intersects = map {exists $gps{$_} ? ($_ => 1) : ()} keys %intersects;
    }

    return $self->_aggregate_hash_to_pdl(\%intersects);
}

sub get_metadata_sp_points_in_same_poly_shape {
    my $self = shift;

    my $examples = <<~'END_EXAMPLES'
        #  define neighbour sets using a shapefile
        sp_points_in_same_poly_shape (file => 'path/to/a/shapefile')

        #  define neighbour sets using a layer called "somename" in a geopackage called file.gpkg
        sp_points_in_same_poly_shape (file => 'path/to/a/file.gpkg/somename')

        #  define neighbour sets using a layer called "somename" in a geodatabase called file.gdb
        sp_points_in_same_poly_shape (file => 'path/to/a/file.gdb/somename')

        #  return true when the neighbour coord is in the same
        #  polygon as an arbitrary point
        sp_points_in_same_poly_shape (
            file   => 'path/to/a/shapefile',
            point1 => [10,20],
        )

        #  reverse the axes
        sp_points_in_same_poly_shape (
            file => 'path/to/a/shapefile',
            axes => [1,0],
        )

        #  compare against the second and third axes of your data
        #  e.g. maybe you have time as the first basedata axis
        sp_points_in_same_poly_shape (
            file => 'path/to/a/shapefile',
            axes => [1,2],
        )

        END_EXAMPLES
    ;

    my %metadata = (
        description => 'Returns true when two points intersect the same polygon',
        required_args => [
            qw /file/,
        ],
        optional_args => [
            qw /point1 point2 axes/,
        ],
        index_no_use => 1,
        result_type  => 'non_overlapping',
        example => $examples,
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_points_in_same_poly_shape {
    my $self = shift;
    my %args = @_;
    my $h = $self->get_current_args;

    my $axes = $args{axes} || [0,1];

    my $point1 = $args{point1} // $h->{coord_array};
    my $point2 = $args{point2} // $h->{nbrcoord_array};

    my $x_coord1 = $point1->[$axes->[0]];
    my $y_coord1 = $point1->[$axes->[1]];
    my $x_coord2 = $point2->[$axes->[0]];
    my $y_coord2 = $point2->[$axes->[1]];

    my $cached_results = $self->get_cache_sp_points_in_same_poly_shape(%args);

    my $point_string1 = join (':', $x_coord1, $y_coord1, $x_coord2, $y_coord2);
    my $point_string2 = join (':', $x_coord2, $y_coord2, $x_coord1, $y_coord1);

    for my $point_string ($point_string1, $point_string2) {
        return $cached_results->{$point_string}
            if exists $cached_results->{$point_string};
    }
    #  always 1 if coord1 == coord2
    return $cached_results->{$point_string1} = 1
        if $x_coord1 == $x_coord2 && $y_coord1 == $y_coord2;

    my $vcache = $self->get_volatile_cache;

    \my %feature_cache = $vcache->get_cached_href($self->get_cache_name_sp_points_in_same_poly_shape(%args));

    my ($ds_name, $layername, $ds, $geometries) = @feature_cache{qw/ds_name layername ds geometries/};
    if (!$ds) {
        ($ds_name, $layername) = $self->_parse_gdal_dataset_layer_string_aa($args{file});
        $ds = Geo::GDAL::FFI::Open($ds_name);
    }

    state sub get_intersecting_features_hash {
        my ($ds, $layername, $x, $y) = @_;
        my $point_geom = Geo::GDAL::FFI::Geometry->new(WKT => "POINT ($x $y)");
        my $filtered = $ds->ExecuteSQL (
            qq{SELECT * FROM "$layername"},
            $point_geom,
            'SQLite',
        );
        my %h;
        while (my $feat = $filtered->GetNextFeature) {
            $h{$feat->GetFID}++;
        }
        return \%h;
    }

    \my %h1 = $feature_cache{filtered_data}{"$x_coord1:$y_coord1"}
        //= get_intersecting_features_hash ($ds, $layername, $x_coord1, $y_coord1);
    \my %h2 = $feature_cache{filtered_data}{"$x_coord2:$y_coord2"}
        //= get_intersecting_features_hash ($ds, $layername, $x_coord2, $y_coord2);

    my $intersection = (%h1 || %h2) ? !keys_disjoint (%h1, %h2) : 1;

    return $cached_results->{$point_string1} = $intersection || 0;
}

sub get_cache_name_sp_point_in_poly_shape {
    my ($self, %args) = @_;
    my $cache_name = join ':',
        'sp_point_in_poly_shape',
        $args{file},
        ($args{field_name} // $NULL_STRING),
        ($args{field_val}  // $NULL_STRING);
    return $cache_name;
}

sub get_cache_name_sp_points_in_same_poly_shape {
    my ($self, %args) = @_;
    my $cache_name = join ':',
        'sp_points_in_same_poly_shape',
        $args{file};
    return $cache_name;
}

sub get_cache_sp_point_in_poly_shape {
    my ($self, %args) = @_;

    my $cache_name = $self->get_cache_name_sp_point_in_poly_shape(%args);
    my $cached = $self->get_cached_value($cache_name);

    return $cached if $cached;

    my $poly_layer = $self->get_gdal_polygon_layer (%args);

    my $point_fc = $self->get_basedata_ref->get_groups_as_geopackage(as_points => 1, %args{axes});
    my $point_layer = $point_fc->GetLayerByIndex(0);

    #  initialise hash with one key per element
    my %intersection_hash;
    $point_layer->ResetReading;
    while (my $feature = $point_layer->GetNextFeature) {
        my $key = $feature->GetField('ELEMENT');
        $intersection_hash{$key} = 0;
    }

    #  now assign 1 to all intersecting features
    my $intersection = $point_layer->Intersection($poly_layer);
    while (my $feature = $intersection->GetNextFeature) {
        my $key = $feature->GetField('ELEMENT');
        $intersection_hash{$key}++;
    }

    $self->set_cached_value($cache_name => \%intersection_hash);

    return \%intersection_hash;
}

sub get_cache_sp_points_in_same_poly_shape {
    my $self = shift;
    my %args = @_;
    my $cache_name = $self->get_cache_name_sp_points_in_same_poly_shape(%args);
    my $cache = $self->get_cached_value_dor_set_default_href($cache_name);
    return $cache;
}

#  parse a filename with layer appended
sub _parse_gdal_dataset_layer_string_aa {
    my ($self, $fstring) = @_;

    if ($fstring =~ /\.gdbtable$/) {
        $fstring = path($fstring)->parent;
        croak "Invalid geodatabase $fstring" if $fstring !~ /\.gdb$/;
    }

    my $p = path ($fstring);

    my ($fname, $layer_name);
    if ($fstring =~ /\.shp$/) {
        $layer_name = $p->basename =~ s/.shp$//r;
        $fname      = $fstring;
    }
    else {
        $fname      = $p->parent->stringify;
        $layer_name = $p->basename;
    }

    return wantarray ? ($fname, $layer_name) : [$fname, $layer_name];
}

sub get_gdal_polygon_layer {
    my ($self, %args) = @_;

    my $filename = $args{file};

    if ($filename =~ /\.gdbtable$/) {
        $filename = path($filename)->parent;
        croak "Invalid geodatabase $filename" if $filename !~ /\.gdb$/;
    }

    my $vcache = $self->get_volatile_cache;

    my $field_name = $args{field_name};
    my $field_val  = $args{field_val};

    my $cache_name
        = join ':',
        'POLYGONS',
        $filename,
        ($field_name // $NULL_STRING),
        ($field_val  // $NULL_STRING);
    my $cached = $vcache->get_cached_value($cache_name);

    return $cached if $cached;

    my $p = path ($filename);

    my ($dataset, $layer, $layer_name);
    if ($filename =~ /\.shp$/) {
        $dataset    = Geo::GDAL::FFI::Open("$filename");
        $layer_name = $p->basename =~ s/.shp$//r;
        $layer      = $dataset->GetLayer();
    }
    else {
        my $ds;
        if ($p =~ /\.\w+$/) {
            $ds = "$p";
        }
        else {
            $ds = $p->parent->stringify;
            $layer_name = $p->basename;
        }
        $dataset = Geo::GDAL::FFI::Open($ds);

        if (!length $layer_name) {
            $layer_name = ($dataset->GetLayerNames)[0];
        }
        $layer = $dataset->GetLayerByName($layer_name);
    }

    if (defined $field_name || defined $field_val) {
        if (defined $field_name) {
            $layer = $dataset->ExecuteSQL(
                qq{SELECT * FROM "$layer_name" WHERE "$field_name" = "$field_val"},
                undef,
                'SQLite',
            );
        }
        else {
            croak "field_val value must be an integer if field_name is not passed, got $field_val"
                if !looks_like_number($field_val) || ($field_val - POSIX::floor ($field_val) != 0);
            #  User wants FID based selection.  We document that we count from 1
            #  so the offset is FID-1.
            my $offset = $field_val - 1;
            $layer = $dataset->ExecuteSQL(
                qq{SELECT * FROM "$layer_name" LIMIT 1 OFFSET $offset},
                undef,
                'SQLite',
            );
        }
    }

    $vcache->set_cached_value($cache_name => $layer);

    return $layer;
}

1;