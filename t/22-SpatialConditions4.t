use 5.010;
use strict;
use warnings;
use Carp;
use English qw{
    -no_match_vars
};

use rlib;
use Test2::V0;

use Biodiverse::TestHelpers qw{
    :basedata
    compare_arr_vals
};
use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;

use Data::Section::Simple qw{
    get_data_section
};

sub test_case {
    my %args = @_;

    my $bd            = $args{bd};       # basedata object
    my $cond          = $args{cond};     # spatial condition as string
    my $element       = $args{element};  # centre element
    my $count         = $args{count};    # amount of neighbours
    my $includes      = $args{includes}; # array of included cells as strings
    my $excludes      = $args{excludes}; # array of excluded cells as strings
    my $print_results = $args{print_results} || 0;

    my $spatial_params = Biodiverse::SpatialConditions->new (
        conditions => $cond,
    );

    my $neighbours = eval {
        $bd->get_neighbours (
            element        => $element,
            spatial_params => $spatial_params,
        );
    };

    croak $EVAL_ERROR if $EVAL_ERROR;

    if ($print_results) {
        use Data::Dumper;
        $Data::Dumper::Purity   = 1;
        $Data::Dumper::Terse    = 1;
        $Data::Dumper::Sortkeys = 1;

        my %gen_includes;
        my %gen_excludes;

        my @xdeltas = map { $_ * $bd->get_param('CELL_SIZES')->[0] } (-1..1);
        my @ydeltas = map { $_ * $bd->get_param('CELL_SIZES')->[1] } (-1..1);

        for my $neigh (keys %$neighbours) {
            # Check whether each of 9 adjacent cells are excluded.
            for my $dx (@xdeltas) { for my $dy (@ydeltas) {
                if ($dx == 0 && $dy == 0) {
                    next;
                }

                my $adj = transform_element (
                    element   => $neigh,
                    transform => [$dx, $dy, 1, 1]
                );

                if (!exists $neighbours->{$adj}) {
                    undef $gen_excludes{$adj};
                    undef $gen_includes{$neigh};
                }
            } }
        }

        print Dumper {
            count    => scalar keys %$neighbours,
            includes => [sort keys %gen_includes],
            excludes => [sort keys %gen_excludes]
        };
    }

    is scalar keys %$neighbours, $count,
       'The correct amount of neighbours was returned';

    verify_set_contents (
        set      => $neighbours,
        includes => $includes,
        excludes => $excludes
    );
}

=item run_case

Takes in name of the test (name), the test data as a hashref (data).

=cut

sub run_case {
    my %args = @_;

    my $k  = $args{name};
    my %v  = %{$args{data}};
    my $tf = $args{transform};

    my $bd = get_basedata_object_from_site_data (
        CELL_SIZES => [100000, 100000],
    );

    my $element = $v{element};

    print "Centre element is: $element\n";

    my @conds = @{$v{conds}};

    ok (@conds, "Test case $k actually contained conditions");

    while (my ($cond, $v1ref) = splice @conds, 0, 2) {
        my %v1 = %$v1ref;

        my ($includes, $excludes) = @v1{'includes', 'excludes'};

        subtest "Passed condition $cond" => sub { test_case (
            bd            => $bd,
            element       => $element,
            cond          => $cond,
            count         => $v1{count},
            includes      => $includes,
            excludes      => $excludes,
            print_results => 0,
        ) };
    }
}

my $data = get_data_section;

for my $k (sort keys %$data) {
    run_case (
        name => $k,
        data => eval $data->{$k},
    );
}

done_testing;

1;

__DATA__

@@ CASE1
{
    'element'     => '3050000:750000',
    'conds'       => [
        'sp_match_text (text => "3050000", axis => 0, type => "nbr")' =>
        {
        'count' => 8,
        'excludes' => [
                        '2950000:-50000',
                        '2950000:150000',
                        '2950000:250000',
                        '2950000:350000',
                        '2950000:450000',
                        '2950000:50000',
                        '2950000:550000',
                        '2950000:650000',
                        '2950000:750000',
                        '2950000:850000',
                        '2950000:950000',
                        '3050000:-50000',
                        '3050000:450000',
                        '3050000:950000',
                        '3150000:-50000',
                        '3150000:150000',
                        '3150000:250000',
                        '3150000:350000',
                        '3150000:450000',
                        '3150000:50000',
                        '3150000:550000',
                        '3150000:650000',
                        '3150000:750000',
                        '3150000:850000',
                        '3150000:950000'
                      ],
        'includes' => [
                        '3050000:150000',
                        '3050000:250000',
                        '3050000:350000',
                        '3050000:50000',
                        '3050000:550000',
                        '3050000:650000',
                        '3050000:750000',
                        '3050000:850000'
                      ]
        },
        'sp_match_text (text => "3", axis => 0, type => "nbr")' =>
        {
        'count' => 0,
        'excludes' => [],
        'includes' => []
        },
        'sp_match_text (text => "50000", axis => 1, type => "nbr")' =>
        {
            'count' => 3,
            'excludes' => [
                        '2850000:-50000',
                        '2850000:150000',
                        '2850000:50000',
                        '2950000:-50000',
                        '2950000:150000',
                        '3050000:-50000',
                        '3050000:150000',
                        '3150000:-50000',
                        '3150000:150000',
                        '3250000:-50000',
                        '3250000:150000',
                        '3250000:50000'
                      ],
            'includes' => [
                        '2950000:50000',
                        '3050000:50000',
                        '3150000:50000'
                      ]
        },
        'sp_match_text (text => "Genus sp5")' =>
        {
            'count' => 0,
            'excludes' => [],
            'includes' => []
        },
        'sp_in_label_range (label => "Genus:sp1")' =>
          {
            'count' => 23,
            'excludes' => [],
            'includes' => [
                "3550000:1050000",
                "3450000:750000",
                "3750000:1350000",
                "3250000:2950000",
                "3350000:650000",
                "3450000:950000",
                "3550000:1450000",
                "3750000:1950000",
                "3850000:1450000",
                "3550000:1150000",
                "3550000:1050000",
                "3050000:650000",
                "3450000:850000",
                "3850000:1650000",
                "3250000:3050000",
                "3750000:1250000",
                "3350000:750000",
                "3850000:1750000",
                "3250000:650000",
                "3750000:2150000",
                "3850000:1850000",
                "3650000:2350000",
                "3450000:650000",
                "3650000:1150000",
            ],
          },
        'sp_in_label_range_convex_hull (label => "Genus:sp4")' =>
          {
            'count' => 8,
            'excludes' => [],
            'includes' => [
                "3550000:1950000",
                "3550000:2050000",
                "3550000:2150000",
                "3550000:2250000",
                "3650000:1950000",
                "3650000:2050000",
                "3750000:1950000",
                "3750000:2050000",
            ],
          },
        'sp_in_label_range_convex_hull (label => "not in data set")' =>
          {
            'count' => 0,
            'excludes' => [],
            'includes' => [
            ],
          },
          'sp_in_label_range_circumcircle (label => "Genus:sp4")' =>
          {
            'count' => 14,
            'excludes' => [],
            'includes' => [
                qw /
                    3450000:2050000 3450000:2150000 3550000:1950000
                    3550000:2050000 3550000:2150000 3550000:2250000
                    3650000:1850000 3650000:1950000 3650000:2050000
                    3650000:2350000 3750000:1950000 3750000:2050000
                    3750000:2150000 3850000:1950000
                /
            ],
          },
        'sp_in_label_range_circumcircle (label => "not in data set")' =>
          {
            'count' => 0,
            'excludes' => [],
            'includes' => [
            ],
          },
    ],
}

__END__
