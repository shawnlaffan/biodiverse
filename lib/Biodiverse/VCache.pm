package Biodiverse::VCache;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

#  A cache object for volatile things like Geo::GDAL::FFI objects that do not survive serialisation
#  All it does is ensure the serialised object has no cache.
#  Since it is volatile a new instance is returned on freeze and thaw.

use parent 'Biodiverse::Common::Caching';

sub new {
    my $class = shift;
    bless {}, ref ($class) || $class;
}

sub FREEZE {
    my $self = shift;
    return {};
}

sub THAW {
    my ($class, $model) = @_;
    $class->new;
}

1;

