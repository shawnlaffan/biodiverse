use 5.016;
use strict;
use warnings;

use JSON;

use rlib '../../lib';

use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;

my $bd = Biodiverse::BaseData->new (
    CELL_SIZES => [1,1],
);
$bd->add_element (                    
    label => 'a:b',
    group => '1:1',
    count => 1,
);
my $lb_ref = $bd->get_labels_ref;
$lb_ref->set_param (CELL_SIZES => [-1,-1]);


my $sp = Biodiverse::SpatialConditions->new(conditions => 1);

my $struct = $sp->get_conditions_metadata_as_struct;
my $json_obj = JSON->new->canonical(1)->pretty;

my $json = $json_obj->encode($struct);
# say $json;

my $fname = 'spatial_conditions.json';

open(my $fh, '>', $fname) or die "Cannot open $fname";
say {$fh} $json;
$fh->close;

