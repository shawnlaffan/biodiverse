#!/usr/bin/perl -w
use strict;
use warnings;

local $| = 1;

use Carp;
use rlib;
use Test::More;
use Data::Dumper;
use Data::Section::Simple qw{
    get_data_section
};

use Biodiverse::BaseData;
use Biodiverse::Indices;
use Biodiverse::TestHelpers qw{
    :basedata
    :runners
    :tree
};

my $calcs_to_test = [qw/
    calc_phylo_mpd_mntd3
    calc_phylo_mpd_mntd2
    calc_phylo_mpd_mntd1
/];

run_indices_phylogenetic (
    calcs_to_test  => $calcs_to_test,
    calc_topic_to_test => 'PhyloCom Indices',
    get_expected_results => \&get_expected_results
);

done_testing;

# TODO: factor out
sub get_expected_results {
    my %args = @_;

    my $nbr_list_count = $args{nbr_list_count};

    croak "Invalid nbr list count\n"
        if $nbr_list_count != 1 && $nbr_list_count != 2;

    return \%{eval get_data_section("RESULTS_${nbr_list_count}_NBR_LISTS")};
}

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'PMPD1_MAX'  => '1.95985532713474',
  'PMPD1_MEAN' => '1.70275738232872',
  'PMPD1_MIN'  => '0.5',
  'PMPD1_N'    => 182,
  'PMPD1_SD'   => '0.293830234111311',
  'PMPD2_MAX'  => '1.95985532713474',
  'PMPD2_MEAN' => '1.68065889601647',
  'PMPD2_MIN'  => '0.5',
  'PMPD2_N'    => 440,
  'PMPD2_SD'   => '0.272218460873199',
  'PMPD3_MAX'  => '1.95985532713474',
  'PMPD3_MEAN' => '1.65678662960988',
  'PMPD3_MIN'  => '0.5',
  'PMPD3_N'    => 6086,
  'PMPD3_SD'   => '0.219080210645172',
  'PNTD1_MAX'  => '1.86377675442101',
  'PNTD1_MEAN' => '1.09027062122407',
  'PNTD1_MIN'  => '0.5',
  'PNTD1_N'    => 14,
  'PNTD1_SD'   => '0.368844918238016',
  'PNTD2_MAX'  => '1.86377675442101',
  'PNTD2_MEAN' => '1.08197443720832',
  'PNTD2_MIN'  => '0.5',
  'PNTD2_N'    => 22,
  'PNTD2_SD'   => '0.296713670467583',
  'PNTD3_MAX'  => '1.86377675442101',
  'PNTD3_MEAN' => '1.17079993908642',
  'PNTD3_MIN'  => '0.5',
  'PNTD3_N'    => 83,
  'PNTD3_SD'   => '0.261537668675783'
}

@@ RESULTS_1_NBR_LISTS
{
  'PMPD1_MAX'  => 1,
  'PMPD1_MEAN' => '1',
  'PMPD1_MIN'  => 1,
  'PMPD1_N'    => 2,
  'PMPD1_SD'   => '0',
  'PMPD2_MAX'  => 1,
  'PMPD2_MEAN' => '1',
  'PMPD2_MIN'  => 1,
  'PMPD2_N'    => 2,
  'PMPD2_SD'   => '0',
  'PMPD3_MAX'  => 1,
  'PMPD3_MEAN' => '1',
  'PMPD3_MIN'  => 1,
  'PMPD3_N'    => 16,
  'PMPD3_SD'   => '0',
  'PNTD1_MAX'  => 1,
  'PNTD1_MEAN' => '1',
  'PNTD1_MIN'  => 1,
  'PNTD1_N'    => 2,
  'PNTD1_SD'   => '0',
  'PNTD2_MAX'  => 1,
  'PNTD2_MEAN' => '1',
  'PNTD2_MIN'  => 1,
  'PNTD2_N'    => 2,
  'PNTD2_SD'   => '0',
  'PNTD3_MAX'  => 1,
  'PNTD3_MEAN' => '1',
  'PNTD3_MIN'  => 1,
  'PNTD3_N'    => 6,
  'PNTD3_SD'   => '0'
}
