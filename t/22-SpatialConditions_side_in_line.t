use strict;
use warnings;
use Carp;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;

use rlib;
use Test2::V0;

use Scalar::Util qw /looks_like_number/;
use Data::Dumper qw /Dumper/;

local $| = 1;

use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;
use Biodiverse::TestHelpers qw {:spatial_conditions};

#  need to build these from tables
#  need to add more
#  the ##1 notation is odd, but is changed for each test using regexes
my %conditions = (
    sides => {
        'sp_in_line_with()' => 30,
        'sp_in_line_with(vector_angle => 0)' => 30,
        'sp_in_line_with(vector_angle => Math::Trig::pip2)' => 30,
        'sp_in_line_with(vector_angle => Math::Trig::pip4)' => 30,
        'sp_in_line_with(vector_angle_deg => 0)'  => 30,
        'sp_in_line_with(vector_angle_deg => 45)' => 30,
        'sp_in_line_with(vector_angle_deg => 90)' => 30,
    },
);


exit main( @ARGV );

sub main {
    my @args  = @_;

    my @res_pairs = get_sp_cond_res_pairs_to_use (@args);
    my %conditions_to_run = get_sp_conditions_to_run (\%conditions, @args);

    foreach my $key (sort keys %conditions_to_run) {
        #diag $key;
        test_sp_cond_res_pairs ($conditions{$key}, \@res_pairs);
    }

    done_testing;
    return 0;
}
