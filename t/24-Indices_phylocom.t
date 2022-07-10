use strict;
use warnings;

local $| = 1;

use rlib;
use Test2::V0;

use Biodiverse::TestHelpers qw{
    :runners :basedata
};

#  need to add a skip for this
note 'THE NRI/NTI RESULTS ARE FOR A 64 BIT PRNG - they will differ for a 32 bit PRNG';

my $element_list1 = ['3350000:850000'];
my $element_list2
    = [qw/
        3250000:850000
        3350000:750000
        3350000:950000
        3450000:850000
    /];

my $bd = get_basedata_object_from_site_data (CELL_SIZES => [100000,100000]);
$bd->add_element (
    group => $element_list1->[0],
    label => 'some random label not on the tree',
);


run_indices_test1 (
    calcs_to_test  => [qw/
        calc_phylo_mpd_mntd3
        calc_phylo_mpd_mntd2
        calc_phylo_mpd_mntd1
        calc_nri_nti_expected_values
        calc_nri_nti1
        calc_nri_nti2
        calc_nri_nti3
        calc_net_vpd
        calc_vpd_expected_values
    /],
    basedata_ref       => $bd,
    element_list1      => $element_list1,
    element_list2      => $element_list2,
    prng_seed          => 123456,
    nri_nti_iterations => 4999,
    calc_topic_to_test => 'PhyloCom Indices',
    generate_result_sets => 1,
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{   PHYLO_NRI1             => '-4.94066383117865',
    PHYLO_NRI2             => '-5.69651257849942',
    PHYLO_NRI3             => '-6.51303106778052',
    PHYLO_NRI_NTI_SAMPLE_N => 0,
    PHYLO_NRI_SAMPLE_MEAN  => '1.84720584828667',
    PHYLO_NRI_SAMPLE_SD    => '0.0292366513678574',
    PHYLO_NTI1             => '-1.92972984287523',
    PHYLO_NTI2             => '-1.99012205008653',
    PHYLO_NTI3             => '-1.34351535658904',
    PHYLO_NTI_SAMPLE_MEAN  => '1.35536101312117',
    PHYLO_NTI_SAMPLE_SD    => '0.137371763656886',
    PHYLO_NET_VPD          => '1.54473475565074',
    PHYLO_NET_VPD_SAMPLE_MEAN  => '0.0541986061454265',
    PHYLO_NET_VPD_SAMPLE_N     => 1557,
    PHYLO_NET_VPD_SAMPLE_SD    => '0.0204975161307071',
    PMPD1_MAX              => '1.95985532713474',
    PMPD1_MEAN             => '1.70275738232872',
    PMPD1_MIN              => '0.5',
    PMPD1_N                => 182,
    PMPD1_RMSD             => '1.72778602112414',
    PMPD1_VARIANCE         => '0.0858618317170414',
    PMPD2_MAX              => '1.95985532713474',
    PMPD2_MEAN             => '1.68065889601647',
    PMPD2_MIN              => '0.5',
    PMPD2_N                => 440,
    PMPD2_RMSD             => '1.70251249614779',
    PMPD2_VARIANCE         => '0.0739344747800827',
    PMPD3_MAX              => '1.95985532713474',
    PMPD3_MEAN             => '1.65678662960995',
    PMPD3_MIN              => '0.5',
    PMPD3_N                => 6086,
    PMPD3_RMSD             => '1.67120620763302',
    PMPD3_VARIANCE         => '0.0479882523768325',
    PNTD1_MAX              => '1.86377675442101',
    PNTD1_MEAN             => '1.09027062122407',
    PNTD1_MIN              => '0.5',
    PNTD1_N                => 14,
    PNTD1_RMSD             => '1.14674277360116',
    PNTD1_VARIANCE         => '0.126328961302151',
    PNTD2_MAX              => '1.86377675442101',
    PNTD2_MEAN             => '1.08197443720832',
    PNTD2_MIN              => '0.5',
    PNTD2_N                => 22,
    PNTD2_RMSD             => '1.12013655961468',
    PNTD2_VARIANCE         => '0.0840372294131477',
    PNTD3_MAX              => '1.86377675442101',
    PNTD3_MEAN             => '1.17079993908642',
    PNTD3_MIN              => '0.5',
    PNTD3_N                => 83,
    PNTD3_RMSD             => '1.19931244035734',
    PNTD3_VARIANCE         => '0.0675778322311065'
}


@@ RESULTS_1_NBR_LISTS
{   PHYLO_NRI1             => '-3.59966099911462',
    PHYLO_NRI2             => '-3.59966099911462',
    PHYLO_NRI3             => '-3.59966099911462',
    PHYLO_NRI_NTI_SAMPLE_N => 0,
    PHYLO_NRI_SAMPLE_MEAN  => '1.84720584828667',
    PHYLO_NRI_SAMPLE_SD    => '0.235357120710826',
    PHYLO_NTI1             => '-3.59966099911459',
    PHYLO_NTI2             => '-3.59966099911459',
    PHYLO_NTI3             => '-3.59966099911459',
    PHYLO_NTI_SAMPLE_MEAN  => '1.84720584828667',
    PHYLO_NTI_SAMPLE_SD    => '0.235357120710827',
    PHYLO_NET_VPD_SAMPLE_MEAN  => 0,
    PHYLO_NET_VPD_SAMPLE_N     => 101,
    PHYLO_NET_VPD_SAMPLE_SD    => 0,
    PHYLO_NET_VPD          => undef,
    PMPD1_MAX              => 1,
    PMPD1_MEAN             => '1',
    PMPD1_MIN              => '1',
    PMPD1_N                => 2,
    PMPD1_RMSD             => '1',
    PMPD1_VARIANCE         => 0,
    PMPD2_MAX              => 1,
    PMPD2_MEAN             => '1',
    PMPD2_MIN              => 1,
    PMPD2_N                => 2,
    PMPD2_RMSD             => '1',
    PMPD2_VARIANCE         => 0,
    PMPD3_MAX              => 1,
    PMPD3_MEAN             => '1',
    PMPD3_MIN              => 1,
    PMPD3_N                => 16,
    PMPD3_RMSD             => '1',
    PMPD3_VARIANCE         => 0,
    PNTD1_MAX              => '1',
    PNTD1_MEAN             => '1',
    PNTD1_MIN              => '1',
    PNTD1_N                => 2,
    PNTD1_RMSD             => '1',
    PNTD1_VARIANCE         => 0,
    PNTD2_MAX              => 1,
    PNTD2_MEAN             => '1',
    PNTD2_MIN              => 1,
    PNTD2_N                => 2,
    PNTD2_RMSD             => '1',
    PNTD2_VARIANCE         => 0,
    PNTD3_MAX              => 1,
    PNTD3_MEAN             => '1',
    PNTD3_MIN              => 1,
    PNTD3_N                => 6,
    PNTD3_RMSD             => '1',
    PNTD3_VARIANCE         => 0
}


