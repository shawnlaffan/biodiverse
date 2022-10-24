package Biodiverse::Metadata::SpatialConditions;
use strict;
use warnings;
use 5.016;
use Carp;
use Readonly;
use Clone qw /clone/;

our $VERSION = '3.99_005';

use parent qw /Biodiverse::Metadata/;

my %methods_and_defaults = (
    description    => 'no_description',
    result_type    => 'no_type',
    index_max_dist => undef,
    shape_type     => 'unknown',
    example        => 'no_example',
    required_args  => [],
    optional_args  => [],
    index_no_use   => undef,
    use_euc_distance       => undef,
    use_euc_distances      => [],
    use_abs_euc_distances  => [],
    use_cell_distance      => undef,
    use_cell_distances     => [],
    use_abs_cell_distances => [],
);

sub _get_method_default_hash {
    return wantarray ? %methods_and_defaults : {%methods_and_defaults};
}


__PACKAGE__->_make_access_methods (\%methods_and_defaults);


1;
