#!/usr/bin/perl -w

#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use strict;
use warnings;
use English qw { -no_match_vars };

use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

#use Test::More tests => 5;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;
use Biodiverse::TestHelpers qw /:basedata/;

#  this needs work to loop around more of the expected variations
my @setup = (
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lat     => [1, 0],
            is_lon     => [0, 1],
        },
        expected => 'fail',
        message  => 'lat/lon out of bounds',
    },
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lat     => [1, 0],
        },
        expected => 'fail',
        message  => 'lat out of bounds',
    },
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lon     => [1, 0],
        },
        expected => 'fail',
        message  => 'lon out of bounds',
    },
    {
        args => {
            CELL_SIZES => [100000, 100000],
        },
        expected => 'pass',
    },
    {
        args => {
            CELL_SIZES => [100, 100],
        },
        expected => 'pass',
    },
);


{
    foreach my $this_run (@setup ) {
        my $expected = $this_run->{expected} || 'pass';  
        my $args     = $this_run->{args};

        my $string = Data::Dumper::Dumper $args;
        $string =~ s/[\s\n\r]//g;
        $string =~ s/^\$VAR1=//;
        $string =~ s/;$//;

        my $message  = $this_run->{message} || $string;

        my $bd = eval {
            get_basedata_object ( %$args, );
        };
        my $error = $EVAL_ERROR;

        if ($expected eq 'fail') {
            ok (defined $error, "Trapped error: $message");
        }
        else {
            ok (defined $bd,    "Imported: $message");
        }
    }
}


{
    # testing mins and maxes

    # the cells are indexed using their centroids, so the min bound for x_min being 1 will be 1.5


    my $bd = eval {
        get_basedata_object (
            x_spacing   => 1,
            y_spacing   => 1,
            CELL_SIZES  => [1, 1],
            x_max       => 100,
            y_max       => 100,
            x_min       => 1,
            y_min       => 1,
        );
    };

    $bd->save (filename => "bd_test_1.bds");

    my $bounds = $bd->get_coord_bounds;
    my $min_bounds = $bounds->{MIN};
    my $max_bounds = $bounds->{MAX};

    ok (@$min_bounds[0] == @$min_bounds[1], "min x and y are the same");
    ok (@$min_bounds[0] == 1.5, "min is correctly 1.5");
    ok (@$max_bounds[0] == @$max_bounds[1], "max bounds for x and y are the same");
    ok (@$max_bounds[0] == 100.5, "max is correctly 100.5");
}

{
    #  check values near zero are imported correctly
    #    - was getting issues with negative values one cell left/lower than
    #    they should have been for coords on the cell edge

    foreach my $min (-49, -49.5) {
        my $bd = eval {
            get_basedata_object (
                x_spacing  => 1,
                y_spacing  => 1,
                CELL_SIZES => [1, 1],
                x_max      => $min + 100,
                y_max      => $min + 100,
                x_min      => $min,
                y_min      => $min,
            );
        };
        
        $bd->save (filename => "bd_test_$min.bds");
    
        #  clunky...
        #my @groups = ('0.5:0.5', '-0.5:0.5', '0.5:-0.5', '-0.5:-0.5', '-1.5:-1.5');
        my @groups;
        my @axis_coords = (-1.5, -0.5, 0.5, 1.5);
        foreach my $i (@axis_coords) {
            foreach my $j (@axis_coords) {
                push @groups, "$i:$j";
            }
        }
        foreach my $group (@groups) {
            ok ($bd->exists_group(group => $group), "Group $group exists");
        }
        
        #  should also text the extents of the data set, min & max on each axis

        my $bounds = $bd->get_coord_bounds;
        my $min_bounds = $bounds->{MIN};
        my $max_bounds = $bounds->{MAX};

        # the cells are indexed by their centroids, so for both of these cases
        # the centroids of the x and y min will be -48.5

        # for -49, the max will be 51.5 
        # but for -49.5, the max will be 50.5

        my $correct_min = -48.5;
        my $correct_max = int($min+100)+0.5;

        ok (@$min_bounds[0] == $correct_min, "x_min is $correct_min");
        ok (@$min_bounds[1] == $correct_min, "y_min is $correct_min");

        ok (@$max_bounds[0] == $correct_max, "x_max is $correct_max");
        ok (@$max_bounds[1] == $correct_max, "y_max is $correct_max");
    }
    
}


#  need to test multidimensional data import, including text axes
TODO:
{
    local $TODO = 'need to test multidimensional data import, including text axes';

    is (0, 1, 'need to test multidimensional data import, including text axes');
}

#  rename labels
{
    my $bd = get_basedata_object_from_site_data(
        CELL_SIZES => [100000, 100000],
    );
    
    my $tmp_remap_file = write_data_to_temp_file (get_label_remap_data());
    my $fname = $tmp_remap_file->filename;
    my %lbprops_args = (
        input_element_cols    => [1,2],
        remapped_element_cols => [3,4],
    );

    my $lb_props = Biodiverse::ElementProperties->new;
    my $success = eval { $lb_props->import_data(%lbprops_args, file => $fname) };    
    diag $EVAL_ERROR if $EVAL_ERROR;
    
    ok ($success == 1, 'import label remap without error');

    my $lb = $bd->get_labels_ref;
    my %lb_expected_counts = (
        'Genus:sp1' => undef,
        'nominal_new_name:' => $lb->get_sample_count (element => 'Genus:sp11'),
    );

    my %expected_groups_with_labels = (
        'Genus:sp2' => {},
        'nominal_new_name:' => {$bd->get_groups_with_label_as_hash (label => 'Genus:sp11')},
    );

    foreach my $label (qw /Genus:sp1 Genus:sp2 Genus:sp18/) {
        $lb_expected_counts{'Genus:sp2'} += $lb->get_sample_count (element => $label);

        my %gps_with_label = $bd->get_groups_with_label_as_hash (label => $label);
        my $hashref = $expected_groups_with_labels{'Genus:sp2'};
        while (my ($gp, $count) = each %gps_with_label) {
            $hashref->{$gp} += $count;
        }
    }

    my $gp = $bd->get_groups_ref;
    my %gp_expected;
    foreach my $group ($gp->get_element_list) {
        $gp_expected{$group} = $gp->get_sample_count (element => $group);
    }
    
    eval {
        $bd->rename_labels (
            remap => $lb_props,
        );
    };
    my $e = $EVAL_ERROR;
    isnt ($e, undef, 'no eval errors assigning label properties');


    foreach my $label (sort keys %lb_expected_counts) {
        my $count = $lb->get_sample_count (element => $label);
        is ($count, $lb_expected_counts{$label}, "Got expected count for $label");
    }

    subtest 'Group counts are not affected by label rename' => sub {
        foreach my $group (keys %gp_expected) {
            is ($gp_expected{$group}, $gp->get_sample_count (element => $group), $group);
        }
    };
    
    subtest 'Renamed labels are in expected groups' => sub {
        while (my ($label, $hash) = each %expected_groups_with_labels) {
            my %observed_hash = $bd->get_groups_with_label_as_hash (label => $label);
            is_deeply ($hash, \%observed_hash, $label);
        }
    }
    
}

#  reordering of axes
REORDER:
{
    my $bd = eval {
            get_basedata_object (
                x_spacing  => 1,
                y_spacing  => 1,
                CELL_SIZES => [1, 1],
                x_max      => 100,
                y_max      => 100,
                x_min      => 0,
                y_min      => 0,
            );
        };
    
    my $new_bd = eval {
        $bd->new_with_reordered_element_axes (
            GROUP_COLUMNS => [1,0],
            LABEL_COLUMNS => [1,0],
        );
    };
    my $error = $EVAL_ERROR;

    ok (defined $new_bd,    "Reordered axes");

}


done_testing();


sub get_label_remap_data {
    return get_data_section('LABEL_REMAP');
}

1;

__DATA__

@@ LABEL_REMAP
id,gen_name_in,sp_name_in,gen_name_out,sp_name_out
1,Genus,sp1,Genus,sp2
10,Genus,sp18,Genus,sp2
2000,Genus,sp2,,
1,Genus,sp11,nominal_new_name,
