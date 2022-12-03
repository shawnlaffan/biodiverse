#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.
use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };

use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

use Test2::V0;

use Biodiverse::TestHelpers qw /:basedata/;
use Biodiverse::BaseData;
use Biodiverse::ElementProperties;

my $bd = eval {
    get_basedata_object (
        x_spacing  => 1,
        y_spacing  => 1,
        CELL_SIZES => [1, 1],
        x_max      => 20,
        y_max      => 20,
        x_min      => 0,
        y_min      => 0,
        #label_generator => sub {return $_[0]},
    );
};

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
    

    test_def_query();
    test_delete_empties();
    
    done_testing;
    return 0;
}


sub test_def_query {
    #  need to automate this, and extend the testing
    my $bd2 = $bd->clone;
    #print $bd2->describe;
    my $exclusion_hash = {
        GROUPS => {
            definition_query => '$x < 10 && $y < 10',
        },
    };
    my $tally = eval {
        $bd2->run_exclusions (exclusion_hash => $exclusion_hash);
    };
    diag $@ if $@;
    is ($tally->{GROUPS_count}, 100, 'Deleted 100 groups using def query');
    is ($tally->{LABELS_count}, 100, 'Deleted 100 labels using def query');
}

sub test_delete_empties {
    my $bd2 = $bd->clone;
    #my $desc = $bd2->describe;

    my $exclusion_hash = {
        LABELS => {
            minVariety => 100,
        },
    };
    my $tally = eval {
        $bd2->run_exclusions (
            exclusion_hash      => $exclusion_hash,
            delete_empty_groups => 0,
        );
    };
    diag $@ if $@;
    #my $desc2 = $bd2->describe;
    is ($bd2->get_group_count, $bd->get_group_count, 'Deleted no groups using def query when empty groups are retained');
    is ($bd2->get_label_count, 0, 'Deleted all labels using def query');
    
    my $bd3 = $bd->clone;
    $exclusion_hash = {
        GROUPS => {
            minVariety => 100,
        },
    };
    $tally = eval {
        $bd3->run_exclusions (
            exclusion_hash      => $exclusion_hash,
            delete_empty_labels => 0,
        );
    };
    diag $@ if $@;
    is ($bd3->get_label_count, $bd->get_label_count, 'Deleted no labels using def query when empty labels are retained');
    is ($bd3->get_group_count, 0, 'Deleted all groups using def query');
    
}

1;
