#!/usr/bin/perl -w

#  Tests for basedata save and reload.
#  Assures us that the data can be serialised, saved out and then reloaded
#  without throwing an exception.

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };

use Scalar::Util qw /blessed unweaken/;
use Devel::Refcount qw /refcount/;

use rlib;

local $| = 1;

use Test::More;
use Test::Exception;

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;
use Biodiverse::TestHelpers qw /:basedata/;

exit main( @ARGV );

sub main {
    my @args = @_;
    
    my $bd = get_data_object();
    
    if (@args) {
        for my $name (@args) {
            die "No test method $name\n"
                if not my $func = (__PACKAGE__->can( 'test_' . $name ) or __PACKAGE__->can( $name ));
            $func->($bd);
        }
        done_testing;
        return 0;
    }

    #  do we get a consistent clone/saved version?
    test_save_and_reload($bd);

    done_testing;
    return 0;
}


sub get_data_object {
    #  generate one basedata for all tests
    my @cell_sizes = (10, 10);
    my $args = {
        CELL_SIZES => [@cell_sizes],
        name       => 'Test save, reload and clone',
        x_spacing => 1,
        y_spacing => 1,
        x_max     => 50,
        y_max     => 50,
        x_min     => 1,
        y_min     => 1,
        count     => 1,
    };
    my $bd = eval {
        get_basedata_object ( %$args, );
    };
    my $error = $EVAL_ERROR;

    my $defq = '$y > 45';
    
    my $cl = $bd->add_cluster_output (
        name => 'Cluster',
    );
    $cl->run_analysis(
        definition_query => $defq,
    );
    
    $cl->delete_params(qw /BASEDATA_REF RAND_LAST_STATE ORIGINAL_MATRICES RAND_INIT_STATE SPATIAL_CONDITIONS/);
    delete $cl->{MATRICES};
    $cl->delete_cached_values_below;

    
    #foreach my $ref (values %{$cl->{TREE_BY_NAME}}) {
    #    unweaken $ref->{_PARENT};
    #}

    diag "\nTree refcount is " . refcount $cl->{TREE};

    #$cl->{TREE_SPARE} = $cl->{TREE};

    diag "\nTree refcount is " . refcount $cl->{TREE};
    
    return $cl;
}

## only testing for errors at the moment (2013-06-10).
## need to develop more stringent tests, e.g. has same outputs, same groups etc

sub test_save_and_reload {
    my $bd = shift;

    my $class = blessed $bd;

    local $Data::Dumper::Purity    = 1;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Quotekeys = 0;

    foreach my $type (qw /sereal storable yaml data_dumper/) {
        my $save_method = "save_to_$type";
        my $load_method = "load_${type}_file";
        my $fname = $save_method;

        diag "using methods $save_method $load_method\n";

        lives_ok {
            $fname = $bd->$save_method(filename => $fname)
        } "Saved to file using $save_method";

        my $new_bd;
        lives_ok {
            $new_bd = $bd->$load_method(file => $fname, ignore_suffix => 1)
        } "Opened without exception thrown using $load_method";

    }

}




1;
