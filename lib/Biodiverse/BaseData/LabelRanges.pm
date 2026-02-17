package Biodiverse::BaseData::LabelRanges;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use Carp qw /croak/;

use experimental qw /refaliasing declared_refs/;

use Geo::GDAL::FFI 0.15;
use List::Util qw /min max/;
use List::MoreUtils qw /minmax/;

sub get_label_range_circumcircle {
    my ($self, %args) = @_;
    use Biodiverse::Geometry::Circle;

    my $label = $args{label} // croak 'label arg not defined';
    my $axes  = $args{axes} // [0,1];

    my $cache_key = 'LABEL_RANGE_CIRCUMCIRCLE_' . join ':', $axes;
    my $cache = $self->get_cached_value_dor_set_default_href ($cache_key);

    my $circumcircle = $cache->{$label};

    return $circumcircle if defined $circumcircle;

    my $hull = $self->get_label_range_convex_hull(%args);
    my $pts  = $hull->GetPoints();
    $circumcircle = Biodiverse::Geometry::Circle->get_circumcircle ($pts->[0]);

    $cache->{$label} = $circumcircle;

    return $circumcircle;
}

#  could do the whole thing in GDAL if we created an in-memory geopackage
sub get_groups_in_label_range_circumcircle {
    my ($self, %args) = @_;
    my $label = $args{label};
    \my @axes  = $args{axes} // [0,1];

    my $cache_key = 'GROUPS_IN_LABEL_RANGE_CIRCUMCIRCLE_' . join ':', @axes;
    my $cache = $self->get_cached_value_dor_set_default_href ($cache_key);

    if (my $cached = $cache->{$label}) {
        return wantarray ? %$cached : $cached;
    }

    my $circle = $self->get_label_range_circumcircle(label => $label, axes => \@axes);

    my $in_circumcircle = $self->get_groups_in_circle (circle => $circle, axes => \@axes);

    $cache->{$label} = $in_circumcircle;

    return wantarray ? %$in_circumcircle : $in_circumcircle;
}


sub get_label_range_convex_hull {
    my ($self, %args) = @_;
    return $self->_get_label_range_hull (%args, is_concave => 0);
}

sub get_label_range_concave_hull {
    my ($self, %args) = @_;
    return $self->_get_label_range_hull (%args, is_concave => 1);
}

#  get a convex hull of the label's range
sub _get_label_range_hull {
    my ($self, %args) = @_;
    my $label = $args{label};
    \my @axes  = $args{axes} // [0,1];

    my @res = $self->get_cell_sizes;

    my $type = $args{is_concave} ? 'concave' : 'convex';

    croak "Cannot calculate $type hull on single axis"
        if @res == 1;
    croak "Cannot calculate $type hull on more than two axes"
        if @res > 2;
    croak "Cannot calculate $type hull on text axes"
        if $res[$axes[0]] < 0 || $res[$axes[1]] < 0;

    my $elements = $self->get_groups_with_label_as_hash_aa($label);

    my $gp = $self->get_groups_ref;

    my $c1 = $res[$axes[0]] / 2;
    my $c2 = $res[$axes[1]] / 2;

    #  this is here to be part of the caching
    #  a ratio of 0 causes issues similar to https://github.com/libgeos/geos/issues/1212
    #  ratios over 1 currently cause problems
    my @hull_args = $args{is_concave} ? (min (1, $args{ratio} || 0.0001), !!$args{allow_holes}) : ();

    my $cache_key = sprintf 'LABEL_RANGE_%s_HULL_AXES_%s_ARGS_%s',
        uc($type), join (':', @axes), join (':', @hull_args);
    my $cache = $self->get_cached_value_dor_set_default_href ($cache_key);

    my $hull;

    #  cache as wkt for now
    if (my $cached_wkt = $cache->{$label}) {
        return $cached_wkt if $args{as_wkt};
        $hull = Geo::GDAL::FFI::Geometry->new(WKT => $cached_wkt);
    }
    else {
        my $wkt;
        if (!%$elements) {
            $wkt = "POLYGON EMPTY";
            $hull = Geo::GDAL::FFI::Geometry->new(WKT => $wkt);
            $cache->{$label} = $wkt;
        }
        else {
            $wkt = "MULTIPOLYGON (";
            my $wkt_cache = $self->get_cached_value_dor_set_default_href ('ELEMENT_COORD_WKT_SNIPPETS');
            foreach my $el (keys %$elements) {
                $wkt .= $wkt_cache->{$el} //= do {
                    my $coords = $gp->get_element_name_as_array_aa($el);
                    my ($x, $y) = @$coords[@axes];
                    my ($x1, $x2) = ($x - $c1, $x + $c1);
                    my ($y1, $y2) = ($y - $c2, $y + $c2);
                    "(($x1 $y1, $x1 $y2, $x2 $y2, $x2 $y1, $x1 $y1)), ";
                };
            }
            $wkt =~ s/, $//;
            $wkt .= ')';

            my $g = Geo::GDAL::FFI::Geometry->new(WKT => $wkt);

            my $method = ucfirst ($type) . 'Hull';
            # $hull = $args{is_concave} ? $g : $g->$method(@hull_args);  #  debug
            $hull = $g->$method(@hull_args);
            $cache->{$label} = $hull->ExportToWKT;
        }

        #  save double conversion
        if ($args{as_wkt}) {
            return $cache->{$label};
        }
    }

    return $args{as_wkt} ? $hull->ExportToWKT : $args{as_json} ? $hull->ExportToJSON : $hull;
}

sub get_groups_in_label_range_convex_hull {
    my ($self, %args) = @_;

    return $self->_get_groups_in_label_range_hull (%args, is_concave => 0);
}

sub get_groups_in_label_range_concave_hull {
    my ($self, %args) = @_;

    return $self->_get_groups_in_label_range_hull (%args, is_concave => 1);
}

#  could do the whole thing in GDAL if we created an in-memory geopackage
sub _get_groups_in_label_range_hull {
    my ($self, %args) = @_;
    my $label = $args{label};
    \my @axes  = $args{axes} // [0,1];

    my $type = $args{is_concave} ? 'concave' : 'convex';

    #  nasty and not future proof
    my $cache_key = sprintf 'GROUPS_IN_LABEL_RANGE_%s_HULL_AXES_%s_ARGS%s',
        uc($type),
        join (':', @axes),
        $args{is_concave} ? join ':', ($args{ratio} // 'undef', !!$args{allow_holes}) : '';
    my $cache = $self->get_cached_value_dor_set_default_href ($cache_key);

    #  cache as wkt for now
    if (my $cached = $cache->{$label}) {
        return wantarray ? %$cached : $cached;
    }

    #  inner subs will croak if axes etc are invalid,
    #  so no need to check here
    my $hull = $self->_get_label_range_hull(
        %args,
        as_wkt  => undef,
        as_json => undef,
    );

    my $in_hull = $self->get_groups_in_polygon(polygon => $hull, axes => \@axes);

    $cache->{$label} = $in_hull;

    return wantarray ? %$in_hull : $in_hull;
}

sub get_groups_in_polygon {
    my ($self, %args) = @_;

    my $polygon = $args{polygon} // croak 'polygon arg not passed';
    \my @axes  = $args{axes} // [0,1];

    return $self->get_groups_in_circle(circle => $polygon, axes => \@axes)
        if $polygon->isa('Biodiverse::Geometry::Circle');

    return wantarray ? () : {}
        if $polygon->IsEmpty;

    my $bbox = $polygon->GetEnvelope;
    my ($xmin, $xmax, $ymin, $ymax) = @$bbox;

    my $gp = $self->get_groups_ref;

    my $str_tree = $self->get_strtree_index (axes => \@axes);
    \my @groups = $str_tree->query_partly_within_rect ($xmin, $ymin, $xmax, $ymax);

    my %in_polygon;
    GP:
    foreach my $group (@groups) {
        my $coords = $gp->get_element_name_as_array_aa($group);
        my ($x, $y) = @$coords[@axes];

        next GP if $x < $xmin || $x > $xmax || $y < $ymin || $y > $ymax;

        my $wkt = "POINT($x $y)";
        my $point = Geo::GDAL::FFI::Geometry->new(WKT => $wkt);
        if ($point->Intersects($polygon)) {
            $in_polygon{$group}++;
        }
    }

    return wantarray ? %in_polygon : \%in_polygon;
}

sub get_groups_in_circle {
    my ($self, %args) = @_;

    my $circle = $args{circle} // croak 'circle arg not passed';
    \my @axes  = $args{axes} // [0,1];

    return wantarray ? () : {}
        if $circle->radius < 0;

    my ($xmin, $ymin, $xmax, $ymax) = $circle->bbox;

    my $gp = $self->get_groups_ref;

    my $str_tree = $self->get_strtree_index (axes => \@axes);
    \my @groups = $str_tree->query_partly_within_rect ($xmin, $ymin, $xmax, $ymax);

    my %in_circumcircle;
    # \my @groups = $self->get_groups;
    GP:
    foreach my $group (@groups) {
        my $coords = $gp->get_element_name_as_array_aa($group);
        my ($x, $y) = @$coords[@axes];

        next GP if $x < $xmin || $x > $xmax || $y < $ymin || $y > $ymax;

        next GP if !$circle->contains_point([$x,$y]);

        $in_circumcircle{$group}++;
    }

    return wantarray ? %in_circumcircle : \%in_circumcircle;
}

sub get_label_range_bbox_2d {
    my ($self, %args) = @_;
    my $label = $args{label} // croak 'label arg is undefined';

    return if !$self->exists_label_aa($label);

    my $bbox;

    #  could cache these also but then we need to wrangle args
    if ($args{convex_hull}) {
        my $hull = $self->get_label_range_convex_hull(%args);
        $bbox = [@{$hull->GetEnvelope}[0,2,1,3]];
    }
    elsif ($args{concave_hull}) {
        my $hull = $self->get_label_range_concave_hull(%args);
        $bbox = [@{$hull->GetEnvelope}[0,2,1,3]];
    }
    elsif ($args{circumcircle}) {
        my $circle = $self->get_label_range_circumcircle(%args);
        $bbox = $circle->bbox;
    }
    if ($bbox && $args{buffer_dist}) {
        my $buf = $args{buffer_dist};
        my @box = (
            $bbox->[0] - $buf,
            $bbox->[1] - $buf,
            $bbox->[2] + $buf,
            $bbox->[3] + $buf,
        );
        #  Does a -ve buffer cause an empty geometry?
        #  Return empty array if so.
        return [] if $buf < 0 && ($box[0] > $box[2]) || ($box[1] > $box[3]);
        $bbox = \@box;
    }
    return $bbox if $bbox;

    return if $self->get_group_axis_count != 2;

    my $cache_href
        = $self->get_cached_value_dor_set_default_href ('get_label_range_bbox_2d');

    #  in case we cache the other variants
    my $cache = $cache_href->{vanilla};
    return $cache->{$label} if $cache->{$label};

    my @res = $self->get_cell_sizes;
    my $c1 = $res[0] / 2;
    my $c2 = $res[1] / 2;

    my $groups = $self->get_groups_with_label_as_hash_aa($label);
    my (@x, @y);
    foreach my $gp (keys %$groups) {
        my ($x, $y) = $self->get_group_element_as_array_aa ($gp);
        my ($x1, $x2) = ($x - $c1, $x + $c1);
        my ($y1, $y2) = ($y - $c2, $y + $c2);
        push @x, ($x1, $x2);
        push @y, ($y1, $y2);
    }
    my @xx = minmax (@x);
    my @yy = minmax (@y);

    $bbox = $cache->{$label} = [$xx[0], $yy[0], $xx[1], $yy[1]];

    return wantarray ? @$bbox : $bbox;
}

1;
