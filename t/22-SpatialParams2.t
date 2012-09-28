#!/usr/bin/perl -w

use strict;
use warnings;
use Carp;
use English qw{
    -no_match_vars
};

use rlib;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::SpatialParams;
use Biodiverse::TestHelpers qw{
    :basedata
};

use Data::Dumper;
$Data::Dumper::Purity   = 1;
$Data::Dumper::Terse    = 1;
$Data::Dumper::Sortkeys = 1;

my $bd = get_basedata_object_from_site_data (CELL_SIZES => [100000, 100000]);

my $spatial_params = Biodiverse::SpatialParams->new (
    conditions => 'sp_circle (radius => 200000)'
);

my $neighbours = eval {
    $bd->get_neighbours (
        element        => '2550000:750000',
        spatial_params => $spatial_params,
    );
};

croak $EVAL_ERROR if $EVAL_ERROR;

print Dumper($neighbours);

1;
