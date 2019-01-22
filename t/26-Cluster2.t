#  These tests were taking about 40% of the
#  run time when in 26-Cluster.pm.
#  Moving them will hopefully speed up the
#  test suite on parallel runs.

use 5.010;
use strict;
use warnings;
use Carp;

use FindBin qw/$Bin/;
use Test::Lib;
use rlib;
use List::Util qw /first/;

use Test::More;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Test::More; # tests => 2;
use Test::Exception;

use Biodiverse::TestHelpers qw /:cluster :tree/;
use Biodiverse::Cluster;

my $default_prng_seed = 2345;
my @linkages = qw /
    link_average
    link_recalculate
    link_minimum
    link_maximum
    link_average_unweighted
/;


use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @subs = grep {$_ =~ 'main::test_'} $obj->functions();
#
#use Class::Inspector;
#my @subs = Class::Inspector->functions ('main::');

exit main( @ARGV );


sub main {
    my @args  = @_;

    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
                if not my $func = (__PACKAGE__->can( 'test_' . $name ) || __PACKAGE__->can( $name ));
            $func->();
        }
        done_testing;
        return 0;
    }

    foreach my $sub (sort @subs) {
        no strict 'refs';
        $sub->();
    }
    
    done_testing;
    return 0;
}

sub test_linkages_and_check_replication {
    cluster_test_linkages_and_check_replication (
        type          => 'Biodiverse::Cluster',
        linkage_funcs => \@linkages,
    );
}

sub test_linkages_and_check_mx_precision {
    cluster_test_linkages_and_check_mx_precision(type => 'Biodiverse::Cluster');
}

