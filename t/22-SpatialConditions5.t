use 5.010;
use strict;
use warnings;
use Carp;
use English qw{
    -no_match_vars
};

use rlib;
use Test2::V0;

use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;
use Biodiverse::TestHelpers qw{
    :basedata
    compare_arr_vals
};



test_sp_group_not_empty();

done_testing;



sub test_sp_group_not_empty {

    my $bd = get_basedata_object_from_site_data (
        CELL_SIZES => [100000, 100000],
    );
    
    my $spatial_params = Biodiverse::SpatialConditions->new (
        conditions => 'sp_group_not_empty',
    );

    my @groups = $bd->get_groups();

    my $neighbours = eval {
        $bd->get_neighbours (
            element        => $groups[0],
            spatial_params => $spatial_params,
        );
    };
    
    is (scalar keys %$neighbours, scalar @groups, "Found correct number of non-empty groups");
    
    #  and now as a def query
    my $def_q = Biodiverse::SpatialConditions::DefQuery->new (
        conditions => 'sp_group_not_empty',
    );
    
    $neighbours = eval {
        $bd->get_neighbours (
            element        => $groups[0],
            spatial_params => $spatial_params,
            is_def_query   => 1,
        );
    };

    is (scalar keys %$neighbours, scalar @groups, "Found correct number of non-empty groups (def query)");
}




1;

__DATA__

