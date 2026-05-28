package Biodiverse::Common::IO;
use 5.036;
use warnings;

our $VERSION = '5.0';

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

sub get_gdal_feature_class_layer_from_path {
    my ($self, %args) = @_;

    my $filename = $args{file};

    my ($ds_name, $layer_name) = $self->_parse_gdal_dataset_layer_string_aa($filename);

    my $dataset = Geo::GDAL::FFI::Open($ds_name);
    if (!length $layer_name) {
        $layer_name = ($dataset->GetLayerNames)[0];
    }
    my $layer   = $dataset->GetLayer($layer_name);

    return $layer;
}

1;