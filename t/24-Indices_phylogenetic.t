#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;

use rlib;
use Test::More;
use Data::Section::Simple qw{
    get_data_section
};

local $| = 1;

use Biodiverse::BaseData;
use Biodiverse::Indices;
use Biodiverse::TestHelpers qw{
    :basedata
    :runners
    :tree
};
    
# start with a subset
=for comment
# after calc_phylo_aed_t
    calc_phylo_mntd1
    calc_phylo_mntd3
    calc_pd_endemism
=cut

my $phylo_calcs_to_test = [qw/
    calc_phylo_aed_t
    calc_phylo_jaccard
    calc_phylo_s2
    calc_phylo_sorenson
    calc_pd
    calc_pe
    calc_taxonomic_distinctness
    calc_taxonomic_distinctness_binary
    calc_phylo_mpd_mntd1
    calc_phylo_mpd_mntd2
    calc_phylo_mpd_mntd3
/];
run_indices_phylogenetic($phylo_calcs_to_test, \&verify_results);
done_testing();

sub verify_results {
    my %args = @_;
    compare_hash_vals(
        hash_got => $args{results},
        hash_exp => scalar get_expected_results(nbr_list_count => $args{nbr_list_count})
    );
}

sub get_expected_results {
    my %args = @_;
    my $nbr_list_count = $args{nbr_list_count};
    
    my $data;
    if ($nbr_list_count >= 1 && $nbr_list_count <= 2) {
        $data = get_data_section('RESULTS_'.$nbr_list_count.'_NBR_LISTS');
    }
    else {
        croak 'Invalid value for argument nbr_list_count';
    }
    
    $data =~ s/\n+$//s;
    my %expected = split (/\s+/, $data);
    #  handle data that are copied and pasted from Biodiverse popup
    delete $expected{SPATIAL_RESULTS};  
    
    return wantarray ? %expected : \%expected;
}

1;

__DATA__

@@ RESULTS_1_NBR_LISTS
SPATIAL_RESULTS	3350000:850000
PD	1.49276923076923
PD_P	0.07047267380194
PD_P_per_taxon	0.03523633690097
PD_per_taxon	0.746384615384615
PE_WE	0.261858249294739
PE_WE_P	0.0123621592705162
PE_WE_SINGLE	0.261858249294739
PE_WE_SINGLE_P	0.0123621592705162
PHYLO_AED_T	0.35175641025641
PMPD1_MAX	1
PMPD1_MEAN	1
PMPD1_MIN	1
PMPD1_N	2
PMPD1_SD	0
PMPD2_MAX	1
PMPD2_MEAN	1
PMPD2_MIN	1
PMPD2_N	2
PMPD2_SD	0
PMPD3_MAX	1
PMPD3_MEAN	1
PMPD3_MIN	1
PMPD3_N	16
PMPD3_SD	0
PNTD1_MAX	1
PNTD1_MEAN	1
PNTD1_MIN	1
PNTD1_N	2
PNTD1_SD	0
PNTD2_MAX	1
PNTD2_MEAN	1
PNTD2_MIN	1
PNTD2_N	2
PNTD2_SD	0
PNTD3_MAX	1
PNTD3_MEAN	1
PNTD3_MIN	1
PNTD3_N	6
PNTD3_SD	0
TDB_DENOMINATOR	2
TDB_DISTINCTNESS	0.3413989234342
TDB_NUMERATOR	0.6827978468683
TDB_VARIATION	0
TD_DENOMINATOR	16
TD_DISTINCTNESS	0.3413989234342
TD_NUMERATOR	5.4623827749464
TD_VARIATION	0.8158725744540

@@ RESULTS_2_NBR_LISTS
SPATIAL_RESULTS	3350000:850000
PD	9.55665348225732
PD_P	0.451163454880595
PD_P_per_taxon	0.0322259610628996
PD_per_taxon	0.682618105875523
PE_WE	1.58308662511342
PE_WE_P	0.0747364998100494
PE_WE_SINGLE	1.02058686362188
PE_WE_SINGLE_P	0.0481812484100488
PHYLO_AED_T	2.46207976811201
PHYLO_JACCARD	0.8437979117308
PHYLO_S2	0
PHYLO_SORENSON	0.7298014078093
PMPD1_MAX	1.95985532713474
PMPD1_MEAN	1.70275738232872
PMPD1_MIN	0.5
PMPD1_N	182
PMPD1_SD	0.293830234111311
PMPD2_MAX	1.95985532713474
PMPD2_MEAN	1.68065889601647
PMPD2_MIN	0.5
PMPD2_N	440
PMPD2_SD	0.272218460873199
PMPD3_MAX	1.95985532713474
PMPD3_MEAN	1.65678662960988
PMPD3_MIN	0.5
PMPD3_N	6086
PMPD3_SD	0.219080210645172
PNTD1_MAX	1.86377675442101
PNTD1_MEAN	1.09027062122407
PNTD1_MIN	0.5
PNTD1_N	14
PNTD1_SD	0.368844918238016
PNTD2_MAX	1.86377675442101
PNTD2_MEAN	1.08197443720832
PNTD2_MIN	0.5
PNTD2_N	22
PNTD2_SD	0.296713670467583
PNTD3_MAX	1.86377675442101
PNTD3_MEAN	1.17079993908642
PNTD3_MIN	0.5
PNTD3_N	83
PNTD3_SD	0.261537668675783
TDB_DENOMINATOR	182
TDB_DISTINCTNESS	0.3851569529551
TDB_NUMERATOR	70.0985654378316
TDB_VARIATION	0.0344846899770
TD_DENOMINATOR	6086
TD_DISTINCTNESS	0.3129026181926
TD_NUMERATOR	1904.3253343203655
TD_VARIATION	8.1460755362307
