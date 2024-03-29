use strict;
use warnings;

local $| = 1;

use rlib;
use Test2::V0;

use Biodiverse::TestHelpers qw{
    :runners
};

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_compare_dissim_matrix_values
        calc_matrix_stats
        calc_mx_rao_qe
    /],
    calc_topic_to_test => 'Matrix',
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'MXD_COUNT' => 26,
  'MXD_LIST1' => {
                   'Genus:sp20' => 1,
                   'Genus:sp26' => 1
                 },
  'MXD_LIST2' => {
                   'Genus:sp10' => 2,
                   'Genus:sp11' => 2,
                   'Genus:sp12' => 2,
                   'Genus:sp15' => 2,
                   'Genus:sp20' => 2,
                   'Genus:sp23' => 2,
                   'Genus:sp24' => 2,
                   'Genus:sp25' => 2,
                   'Genus:sp26' => 2,
                   'Genus:sp27' => 2,
                   'Genus:sp29' => 2,
                   'Genus:sp30' => 2,
                   'Genus:sp5'  => 2
                 },
  'MXD_MEAN'     => '0.0473457692307692',
  'MXD_VARIANCE' => '0.00253374386538462',
  'MX_KURT'       => '0.271825741525032',
  'MX_LABELS'     => {
                   'Genus:sp10' => 1,
                   'Genus:sp11' => 1,
                   'Genus:sp12' => 1,
                   'Genus:sp15' => 1,
                   'Genus:sp20' => 1,
                   'Genus:sp23' => 1,
                   'Genus:sp24' => 1,
                   'Genus:sp25' => 1,
                   'Genus:sp26' => 1,
                   'Genus:sp27' => 1,
                   'Genus:sp29' => 1,
                   'Genus:sp30' => 1,
                   'Genus:sp5'  => 1
                 },
  'MX_MAXVALUE'    => '0.07301',
  'MX_MEAN'        => '0.0457271428571428',
  'MX_MEDIAN'      => '0.04642',
  'MX_MINVALUE'    => '0.00794',
  'MX_N'           => 91,
  'MX_PCT05'       => '0.01828',
  'MX_PCT25'       => '0.04046',
  'MX_PCT75'       => '0.05669',
  'MX_PCT95'       => '0.06481',
  'MX_RANGE'       => '0.06507',
  'MX_RAO_QE'      => '0.0492446153846154',
  'MX_RAO_TLABELS' => {
                        'Genus:sp10' => '0.0769230769230769',
                        'Genus:sp11' => '0.0769230769230769',
                        'Genus:sp12' => '0.0769230769230769',
                        'Genus:sp15' => '0.0769230769230769',
                        'Genus:sp20' => '0.0769230769230769',
                        'Genus:sp23' => '0.0769230769230769',
                        'Genus:sp24' => '0.0769230769230769',
                        'Genus:sp25' => '0.0769230769230769',
                        'Genus:sp26' => '0.0769230769230769',
                        'Genus:sp27' => '0.0769230769230769',
                        'Genus:sp29' => '0.0769230769230769',
                        'Genus:sp30' => '0.0769230769230769',
                        'Genus:sp5'  => '0.0769230769230769'
                      },
  'MX_RAO_TN' => 169,
  'MX_SD'     => '0.0137632590847852',
  'MX_SKEW'   => '-0.694760452738312',
  'MX_VALUES' => [
                   '0.00794',
                   '0.01152',
                   '0.01598',
                   '0.01662',
                   '0.01761',
                   '0.01828',
                   '0.01834',
                   '0.01846',
                   '0.02118',
                   '0.02575',
                   '0.02795',
                   '0.03',
                   '0.03106',
                   '0.03182',
                   '0.03271',
                   '0.03497',
                   '0.03636',
                   '0.03703',
                   '0.03705',
                   '0.0382',
                   '0.03957',
                   '0.03983',
                   '0.04014',
                   '0.04046',
                   '0.04061',
                   '0.04106',
                   '0.04192',
                   '0.04203',
                   '0.04211',
                   '0.04222',
                   '0.04226',
                   '0.04237',
                   '0.04262',
                   '0.04298',
                   '0.04301',
                   '0.04325',
                   '0.04383',
                   '0.04422',
                   '0.04433',
                   '0.04445',
                   '0.04511',
                   '0.04533',
                   '0.04612',
                   '0.04628',
                   '0.04631',
                   '0.04642',
                   '0.04668',
                   '0.0474',
                   '0.04745',
                   '0.0478',
                   '0.04808',
                   '0.04845',
                   '0.04857',
                   '0.049',
                   '0.04913',
                   '0.05046',
                   '0.05074',
                   '0.05192',
                   '0.05201',
                   '0.05213',
                   '0.05219',
                   '0.05231',
                   '0.05237',
                   '0.05269',
                   '0.05334',
                   '0.05447',
                   '0.05604',
                   '0.05617',
                   '0.05669',
                   '0.05679',
                   '0.05736',
                   '0.05768',
                   '0.05775',
                   '0.05809',
                   '0.05874',
                   '0.05898',
                   '0.05982',
                   '0.05985',
                   '0.0599',
                   '0.06025',
                   '0.06114',
                   '0.06115',
                   '0.06123',
                   '0.06206',
                   '0.06402',
                   '0.0644',
                   '0.06481',
                   '0.06595',
                   '0.06672',
                   '0.06771',
                   '0.07301'
                 ]
}

@@ RESULTS_1_NBR_LISTS
{
  'MX_KURT'       => undef,
  'MX_LABELS'     => {
                   'Genus:sp20' => 1,
                   'Genus:sp26' => 1
                 },
  'MX_MAXVALUE'    => '0.06402',
  'MX_MEAN'        => '0.05565',
  'MX_MEDIAN'      => '0.05219',
  'MX_MINVALUE'    => '0.05074',
  'MX_N'           => 3,
  'MX_PCT05'       => '0.05074',
  'MX_PCT25'       => '0.05219',
  'MX_PCT75'       => '0.06402',
  'MX_PCT95'       => '0.06402',
  'MX_RANGE'       => '0.01328',
  'MX_RAO_QE'      => '0.083475',
  'MX_RAO_TLABELS' => {
                        'Genus:sp20' => '0.5',
                        'Genus:sp26' => '0.5'
                      },
  'MX_RAO_TN' => '4',
  'MX_SD'     => '0.00728479924225778',
  'MX_SKEW'   => '1.65517073625658',
  'MX_VALUES' => [
                   '0.05074',
                   '0.05219',
                   '0.06402'
                 ]
}
