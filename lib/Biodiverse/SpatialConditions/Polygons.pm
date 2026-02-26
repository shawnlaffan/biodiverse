package Biodiverse::SpatialConditions::Polygons;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use experimental qw /refaliasing for_list/;

use Carp;
use English qw /-no_match_vars/;

use Math::Polygon;
use Geo::ShapeFile 3.00;
use Tree::R;
use Scalar::Util qw /looks_like_number blessed/;
use List::MoreUtils qw /uniq/;
use List::Util qw /min max any/;
use Ref::Util qw { :all };

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
    my $self = shift;
    my %args = @_;
    my $h = $self->get_current_args;

    my $vertices = $args{polygon};
    my $point = $args{point};
    $point ||= eval {$self->is_def_query} ? $h->{coord_array} : $h->{nbrcoord_array};

    my $poly = (blessed ($vertices) || $NULL_STRING) eq 'Math::Polygon'
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

    my %metadata = (
        description =>
            'Select groups that occur within a polygon or polygons extracted from a shapefile',
        required_args => [
            qw /file/,
        ],
        optional_args => [
            qw /point field_name field_val axes no_cache/,
        ],
        index_no_use => 1,
        result_type  => 'always_same',
        example => $examples,
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_point_in_poly_shape {
    my $self = shift;
    my %args = @_;
    my $h = $self->get_current_args;

    my $no_cache = $args{no_cache};
    my $axes = $args{axes} || [0,1];

    my $point = $args{point} // ($self->is_def_query ? $h->{coord_array} : $h->{nbrcoord_array});

    my $x_coord = $point->[$axes->[0]];
    my $y_coord = $point->[$axes->[1]];

    my $cached_results = $self->get_cache_sp_point_in_poly_shape(%args);
    my $point_string = join (':', $x_coord, $y_coord);
    if (!$no_cache && exists $cached_results->{$point_string}) {
        return $cached_results->{$point_string};
    }

    my $polys = $self->get_polygons_from_shapefile (%args);

    my $pointshape = Geo::ShapeFile::Point->new(X => $x_coord, Y => $y_coord);

    my $rtree = $self->get_rtree_for_polygons_from_shapefile (%args, shapes => $polys);
    my $bd = $h->{basedata};
    my @cell_sizes = $bd->get_cell_sizes;
    my ($cell_x, $cell_y) = ($cell_sizes[$axes->[0]], $cell_sizes[$axes->[1]]);
    my @rect = (
        $x_coord - $cell_x / 2,
        $y_coord - $cell_y / 2,
        $x_coord + $cell_x / 2,
        $y_coord + $cell_y / 2,
    );

    my $rtree_polys = [];
    $rtree->query_partly_within_rect(@rect, $rtree_polys);

    #  need a progress dialogue for involved searches
    #my $progress = Biodiverse::Progress->new(text => 'Point in poly search');
    # my ($i, $target) = (1, scalar @$rtree_polys);

    foreach my $poly (@$rtree_polys) {
        #$progress->update(
        #    "Checking if point $point_string\nis in polygon\n$i of $target",
        #    $i / $target,
        #);
        if ($poly->contains_point($pointshape, 0)) {
            if (!$no_cache) {
                $cached_results->{$point_string} = 1;
            }
            return 1;
        }
    }

    if (!$no_cache) {
        $cached_results->{$point_string} = 0;
    }

    return;
}



sub get_metadata_sp_points_in_same_poly_shape {
    my $self = shift;

    my $examples = <<~'END_EXAMPLES'
        #  define neighbour sets using a shapefile
        sp_points_in_same_poly_shape (file => 'path/to/a/shapefile')

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
        description =>
            'Returns true when two points are within the same shapefile polygon',
        required_args => [
            qw /file/,
        ],
        optional_args => [
            qw /point1 point2 axes no_cache/,
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

    my $no_cache = $args{no_cache};
    my $axes = $args{axes} || [0,1];

    my $point1 = $args{point1} // $h->{coord_array};
    my $point2 = $args{point2} // $h->{nbrcoord_array};

    my $x_coord1 = $point1->[$axes->[0]];
    my $y_coord1 = $point1->[$axes->[1]];
    my $x_coord2 = $point2->[$axes->[0]];
    my $y_coord2 = $point2->[$axes->[1]];

    my $cached_results     = $self->get_cache_sp_points_in_same_poly_shape(%args);

    my $point_string1 = join (':', $x_coord1, $y_coord1, $x_coord2, $y_coord2);
    my $point_string2 = join (':', $x_coord2, $y_coord2, $x_coord1, $y_coord1);
    if (!$no_cache) {
        for my $point_string ($point_string1, $point_string2) {
            return $cached_results->{$point_string}
                if (exists $cached_results->{$point_string});
        }
    }

    my $polys = $self->get_polygons_from_shapefile (%args);

    my $pointshape1 = Geo::ShapeFile::Point->new(X => $x_coord1, Y => $y_coord1);
    my $pointshape2 = Geo::ShapeFile::Point->new(X => $x_coord2, Y => $y_coord2);

    my $rtree = $self->get_rtree_for_polygons_from_shapefile (%args, shapes => $polys);

    #  smaller rectangles than the cells so we don't overlap with nbrs - that causes grief later on
    # my ($dx, $dy) = ($cell_x / 4, $cell_y / 4);
    #  actually, we only search for centroids so pass a "point"-rect
    my ($dx, $dy) = (0,0);
    my @rect1 = (
        $x_coord1 - $dx,
        $y_coord1 - $dy,
        $x_coord1 + $dx,
        $y_coord1 + $dy,
    );
    my $rtree_polys1 = [];
    $rtree->query_partly_within_rect(@rect1, $rtree_polys1);

    my @rect2 = (
        $x_coord2 - $dx,
        $y_coord2 - $dy,
        $x_coord2 + $dx,
        $y_coord2 + $dy,
    );
    my $rtree_polys2 = [];
    $rtree->query_partly_within_rect(@rect2, $rtree_polys2);

    #  neither is in a polygon
    if (!@$rtree_polys1 && !@$rtree_polys2) {
        if (!$no_cache) {
            $cached_results->{$point_string1} = 1;
        }
        return 1;
    }

    #  get the list of common polys
    my @rtree_polys_common = grep {
        my $check = $_;
        List::MoreUtils::any {$_ eq $check} @$rtree_polys2
    } @$rtree_polys1;

    my $point1_str = join ':', $x_coord1, $y_coord1;
    my $point2_str = join ':', $x_coord2, $y_coord2;

    my $cached_pts_in_poly = $self->get_cache_points_in_shapepoly(%args);

    foreach my $poly (@rtree_polys_common) {
        my $poly_id     = $poly->shape_id();

        my $pt1_in_poly = $cached_pts_in_poly->{$poly_id}{$point1_str}
            //= $poly->contains_point($pointshape1, 0);

        my $pt2_in_poly = $cached_pts_in_poly->{$poly_id}{$point2_str}
            //= $poly->contains_point($pointshape2, 0);

        if ($pt1_in_poly || $pt2_in_poly) {
            my $result = $pt1_in_poly && $pt2_in_poly;
            if (!$no_cache) {
                $cached_results->{$point_string1} = $result;
            }
            return $result;
        }
    }

    if (!$no_cache) {
        $cached_results->{$point_string1} = 0;
    }

    return;
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

sub get_cache_points_in_shapepoly {
    my $self = shift;
    my %args = @_;

    my $cache_name = 'cache_' . $args{file};
    my $cache = $self->get_cached_value_dor_set_default_aa ($cache_name, {});
    return $cache;
}

sub get_cache_sp_point_in_poly_shape {
    my $self = shift;
    my %args = @_;
    my $cache_name = $self->get_cache_name_sp_point_in_poly_shape(%args);
    my $cache = $self->get_cached_value($cache_name, {});
    return $cache;
}

sub get_cache_sp_points_in_same_poly_shape {
    my $self = shift;
    my %args = @_;
    my $cache_name = $self->get_cache_name_sp_points_in_same_poly_shape(%args);
    my $cache = $self->get_cached_value_dor_set_default_href($cache_name);
    return $cache;
}

sub get_polygons_from_shapefile {
    my $self = shift;
    my %args = @_;

    my $file = $args{file};
    $file =~ s/\.(shp|shx|dbf)$//;

    my $field_name = $args{field_name};
    my $field_val  = $args{field_val};

    my $cache_name
        = join ':',
        'SHAPEPOLYS',
        $file,
        ($field_name // $NULL_STRING),
        ($field_val  // $NULL_STRING);
    my $cached = $self->get_cached_value($cache_name);

    return (wantarray ? @$cached : $cached) if $cached;

    my $shapefile = Geo::ShapeFile->new($file);

    my @shapes;
    if ((!defined $field_name || $field_name eq 'FID') && defined $field_val) {
        my $shape = $shapefile->get_shp_record($field_val);
        push @shapes, $shape;
    }
    else {
        my $progress_bar = Biodiverse::Progress->new(gui_only => 1);
        my $n_shapes = $shapefile->shapes();

        REC:
        for my $rec (1 .. $n_shapes) {  #  brute force search

            $progress_bar->update(
                "Processing $file\n" .
                    "Shape $rec of $n_shapes\n",
                $rec / $n_shapes,
            );

            #  get the lot
            if ((!defined $field_name || $field_name eq 'FID') && !defined $field_val) {
                push @shapes, $shapefile->get_shp_record($rec);
                next REC;
            }

            #  get all that satisfy the condition
            my %db = $shapefile->get_dbf_record($rec);
            my $is_num = looks_like_number ($db{$field_name});
            if ($is_num ? $field_val == $db{$field_name} : $field_val eq $db{$field_name}) {
                push @shapes, $shapefile->get_shp_record($rec);
                #last REC;
            }
        }
    }

    $self->set_cached_value($cache_name => \@shapes);

    return wantarray ? @shapes : \@shapes;
}

sub get_rtree_for_polygons_from_shapefile {
    my $self = shift;
    my %args = @_;

    my $shapes = $args{shapes};

    my $rtree_cache_name = $self->get_cache_name_rtree(%args);
    my $rtree = $self->get_cached_value($rtree_cache_name);

    if (!$rtree) {
        #print "Building R-Tree $rtree_cache_name\n";
        $rtree = $self->build_rtree_for_shapepolys (shapes => $shapes);
        $self->set_cached_value($rtree_cache_name => $rtree);
    }

    return $rtree;
}

sub get_cache_name_rtree {
    my ($self, %args) = @_;
    my $cache_name = join ':',
        'RTREE',
        $args{file},
        ($args{field} || $NULL_STRING),
        ($args{field_val} // $NULL_STRING);
    return $cache_name;
}

sub build_rtree_for_shapepolys {
    my ($self, %args) = @_;

    my $shapes = $args{shapes};

    my $rtree = Tree::R->new();
    foreach my $shape (@$shapes) {
        my @bbox = ($shape->x_min, $shape->y_min, $shape->x_max, $shape->y_max);
        $rtree->insert($shape, @bbox);
    }

    return $rtree;
}

1;