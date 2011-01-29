#!/usr/bin/perl -w
use strict;
use warnings;

use Test::More tests => 30;

local $| = 1;

use mylib;

use Biodiverse::BaseData;
use Biodiverse::SpatialParams;
use Biodiverse::TestHelpers qw {:basedata};

#  need to build these from tables
#  need to add more
my %conditions = (
    'sp_circle (radius => 10)' => 5,
    'sp_circle (radius => 20)' => 13,
    'sp_circle (radius => 30)' => 29,
    'sp_circle (radius => 40)' => 49,
    
    'sp_select_all()' => 10000,
    'sp_self_only()'  => 1,
    
    'sp_ellipse (major_radius => 40, minor_radius => 20)' => 25,
    'sp_ellipse (major_radius => 20, minor_radius => 20)' => 13,
    
    'sp_select_all() && ! sp_circle (radius => 10)' => 9995,
    '! sp_circle (radius => 10) && sp_select_all()' => 9995,
);


{
    my @res = (10, 10);
    my $bd = get_basedata_object(
	x_spacing  => $res[0],
	y_spacing  => $res[1],
	CELL_SIZES => \@res,
    );
    
    foreach my $i (1 .. 3) {
	while (my ($condition, $expected) = each %conditions) {
	    my $sp_params = Biodiverse::SpatialParams->new (
		conditions => $condition,
	    );
	
	    my $nbrs = $bd->get_neighbours (
		element => '495:495',
		spatial_params => $sp_params,
	    );
	
	    #print $nbrs;
	    
	    is (keys %$nbrs, $expected, $condition);
	}
	
	my @index_res;
	foreach my $r (@res) {
	    push @index_res, $r * $i;
	}
	$bd -> build_spatial_index (resolutions => [@index_res]);
    }
    
}

