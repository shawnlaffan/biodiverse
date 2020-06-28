#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use rlib;
use Test2::V0;

use Biodiverse::TestHelpers qw{
    :runners
};

=pod
=head1

24-Indices_pdendemism.t

Additional tests for calc_pd_endemism because the default data provided by
run_indices_test1 isn't sufficient to test it thoroughly.

=cut

run_indices_test1 (
    calcs_to_test => [qw/
        calc_pd_endemism
    /],
    element_list2 => [qw/
        2750000:850000
        2650000:750000
        2750000:750000
        2850000:750000
        2750000:650000
    /],
    #generate_result_sets => 1,
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   PD_ENDEMISM     => '0.666666666666667',
    PD_ENDEMISM_P   => '0.0314729038931334',
    PD_ENDEMISM_WTS => {
        '43___'      => '0.666666666666667',
        'Genus:sp28' => 0,
        'Genus:sp31' => 0
    }
}


@@ RESULTS_1_NBR_LISTS
{   PD_ENDEMISM     => undef,
    PD_ENDEMISM_P   => undef,
    PD_ENDEMISM_WTS => {}
}


