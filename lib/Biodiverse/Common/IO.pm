package Biodiverse::Common::IO;
use 5.036;
use warnings;

our $VERSION = '5.99_001';

use Carp qw /croak/;

use Geo::GDAL::FFI;
use Path::Tiny qw /path/;

#  parse a filename with layer appended
#  Not entirely bulletproof...
sub _parse_gdal_dataset_layer_string_aa {
    my ($self, $fstring) = @_;

    if ($fstring =~ /\.gdbtable$/) {
        $fstring = path($fstring)->parent;
        croak "Invalid geodatabase $fstring" if $fstring !~ /\.gdb$/;
    }

    my ($fname, $layer_name);

    my $p = path ($fstring);
    my $basename = $p->basename;
    if ($basename =~ /:/) {
        (undef, $layer_name) = split ':', $basename;
        $fstring =~ s/:$layer_name$//;
        $layer_name = undef if $layer_name eq '';
        $p = path ($fstring);  #  update
    }
    $fname = $fstring;

    #  Shapefiles can be passed without an extension in the spatial conditions
    #  as Geo::Shapefile, which was what we used, supports this.
    if (!$self->file_exists_aa($fname) && $self->file_exists_aa("$fname.shp")) {
        $fname .= '.shp';
        $p = path($fname);
    }

    if ($fname =~ /\.shp$/) {
        $layer_name = $p->basename =~ s/.shp$//r;
    }

    return wantarray ? ($fname, $layer_name) : [$fname, $layer_name];
}

sub get_gdal_feature_class_layer_from_path {
    my ($self, %args) = @_;

    my $filename = $args{path};

    my ($ds_name, $layer_name) = $self->_parse_gdal_dataset_layer_string_aa($filename);

    my $gdal_args = $args{args};

    my $dataset = Geo::GDAL::FFI::Open($ds_name, $gdal_args);
    if (!length $layer_name) {
        $layer_name = ($dataset->GetLayerNames)[0];
    }
    my $layer   = $dataset->GetLayer($layer_name);

    return $layer;
}

1;