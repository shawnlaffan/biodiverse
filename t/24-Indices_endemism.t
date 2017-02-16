#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;
use rlib;
use Test::Most;

use Biodiverse::TestHelpers qw{
    :runners
};

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_endemism_absolute
        calc_endemism_absolute_lists
        calc_endemism_central
        calc_endemism_central_hier_part
        calc_endemism_central_lists
        calc_endemism_central_normalised
        calc_endemism_whole
        calc_endemism_whole_hier_part
        calc_endemism_whole_lists
        calc_endemism_whole_normalised
    /],
    calc_topic_to_test => 'Endemism',
);

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'ENDC_CWE'      => '0.555555555555556',
  'ENDC_CWE_NORM' => '0.111111111111111',
  'ENDC_HPART_0'  => {
                      'Genus' => 1
                    },
  'ENDC_HPART_1' => {
                      'Genus:sp20' => '0.4',
                      'Genus:sp26' => '0.6'
                    },
  'ENDC_HPART_C_0' => {
                        'Genus' => 2
                      },
  'ENDC_HPART_C_1' => {
                        'Genus:sp20' => 1,
                        'Genus:sp26' => 1
                      },
  'ENDC_HPART_E_0' => {
                        'Genus' => '1'
                      },
  'ENDC_HPART_E_1' => {
                        'Genus:sp20' => '0.5',
                        'Genus:sp26' => '0.5'
                      },
  'ENDC_HPART_OME_0' => {
                          'Genus' => 0
                        },
  'ENDC_HPART_OME_1' => {
                          'Genus:sp20' => '0.1',
                          'Genus:sp26' => '-0.1'
                        },
  'ENDC_RANGELIST' => {
                        'Genus:sp20' => 9,
                        'Genus:sp26' => 3
                      },
  'ENDC_RICHNESS' => 2,
  'ENDC_SINGLE'   => '0.444444444444444',
  'ENDC_WE'       => '1.11111111111111',
  'ENDC_WE_NORM'  => '0.222222222222222',
  'ENDC_WTLIST'   => {
                     'Genus:sp20' => '0.444444444444444',
                     'Genus:sp26' => '0.666666666666667'
                   },
  'ENDW_CWE'      => '0.177227343568255',
  'ENDW_CWE_NORM' => '0.0354454687136509',
  'ENDW_HPART_0'  => {
                      'Genus' => 1
                    },
  'ENDW_HPART_1' => {
                      'Genus:sp1'  => '0.0350463985927291',
                      'Genus:sp10' => '0.0143940565648709',
                      'Genus:sp11' => '0.0164503503598524',
                      'Genus:sp12' => '0.0277954195735438',
                      'Genus:sp15' => '0.053737811175518',
                      'Genus:sp20' => '0.179126037251727',
                      'Genus:sp23' => '0.0161213433526554',
                      'Genus:sp24' => '0.080606716763277',
                      'Genus:sp25' => '0.134344527938795',
                      'Genus:sp26' => '0.26868905587759',
                      'Genus:sp27' => '0.080606716763277',
                      'Genus:sp29' => '0.0335861319846987',
                      'Genus:sp30' => '0.0191920754198278',
                      'Genus:sp5'  => '0.0403033583816385'
                    },
  'ENDW_HPART_C_0' => {
                        'Genus' => 14
                      },
  'ENDW_HPART_C_1' => {
                        'Genus:sp1'  => 1,
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
                        'Genus:sp5' => 1
                      },
  'ENDW_HPART_E_0' => {
                        'Genus' => '1'
                      },
  'ENDW_HPART_E_1' => {
                        'Genus:sp1'  => '0.0714285714285714',
                        'Genus:sp10' => '0.0714285714285714',
                        'Genus:sp11' => '0.0714285714285714',
                        'Genus:sp12' => '0.0714285714285714',
                        'Genus:sp15' => '0.0714285714285714',
                        'Genus:sp20' => '0.0714285714285714',
                        'Genus:sp23' => '0.0714285714285714',
                        'Genus:sp24' => '0.0714285714285714',
                        'Genus:sp25' => '0.0714285714285714',
                        'Genus:sp26' => '0.0714285714285714',
                        'Genus:sp27' => '0.0714285714285714',
                        'Genus:sp29' => '0.0714285714285714',
                        'Genus:sp30' => '0.0714285714285714',
                        'Genus:sp5'  => '0.0714285714285714'
                      },
  'ENDW_HPART_OME_0' => {
                          'Genus' => 0
                        },
  'ENDW_HPART_OME_1' => {
                          'Genus:sp1'  => '0.0363821728358423',
                          'Genus:sp10' => '0.0570345148637005',
                          'Genus:sp11' => '0.054978221068719',
                          'Genus:sp12' => '0.0436331518550276',
                          'Genus:sp15' => '0.0176907602530534',
                          'Genus:sp20' => '-0.107697465823155',
                          'Genus:sp23' => '0.055307228075916',
                          'Genus:sp24' => '-0.00917814533470555',
                          'Genus:sp25' => '-0.0629159565102235',
                          'Genus:sp26' => '-0.197260484449018',
                          'Genus:sp27' => '-0.00917814533470555',
                          'Genus:sp29' => '0.0378424394438727',
                          'Genus:sp30' => '0.0522364960087436',
                          'Genus:sp5'  => '0.0311252130469329'
                        },
  'ENDW_RANGELIST' => {
                        'Genus:sp1'  => 23,
                        'Genus:sp10' => 28,
                        'Genus:sp11' => 49,
                        'Genus:sp12' => 29,
                        'Genus:sp15' => 15,
                        'Genus:sp20' => 9,
                        'Genus:sp23' => 25,
                        'Genus:sp24' => 5,
                        'Genus:sp25' => 3,
                        'Genus:sp26' => 3,
                        'Genus:sp27' => 5,
                        'Genus:sp29' => 12,
                        'Genus:sp30' => 21,
                        'Genus:sp5'  => 10
                      },
  'ENDW_RICHNESS' => 14,
  'ENDW_SINGLE'   => '1.64948029386667',
  'ENDW_WE'       => '2.48118280995557',
  'ENDW_WE_NORM'  => '0.496236561991113',
  'ENDW_WTLIST'   => {
                     'Genus:sp1'  => '0.0869565217391304',
                     'Genus:sp10' => '0.0357142857142857',
                     'Genus:sp11' => '0.0408163265306122',
                     'Genus:sp12' => '0.0689655172413793',
                     'Genus:sp15' => '0.133333333333333',
                     'Genus:sp20' => '0.444444444444444',
                     'Genus:sp23' => '0.04',
                     'Genus:sp24' => '0.2',
                     'Genus:sp25' => '0.333333333333333',
                     'Genus:sp26' => '0.666666666666667',
                     'Genus:sp27' => '0.2',
                     'Genus:sp29' => '0.0833333333333333',
                     'Genus:sp30' => '0.0476190476190476',
                     'Genus:sp5'  => '0.1'
                   },
  'END_ABS1'         => 0,
  'END_ABS1_LIST'    => {},
  'END_ABS1_P'       => '0',
  'END_ABS2'         => 0,
  'END_ABS2_LIST'    => {},
  'END_ABS2_P'       => '0',
  'END_ABS_ALL'      => 0,
  'END_ABS_ALL_LIST' => {},
  'END_ABS_ALL_P'    => '0'
}

@@ RESULTS_1_NBR_LISTS
{
  'ENDC_CWE'      => '0.222222222222222',
  'ENDC_CWE_NORM' => '0.222222222222222',
  'ENDC_HPART_0'  => {
                      'Genus' => 1
                    },
  'ENDC_HPART_1' => {
                      'Genus:sp20' => '0.25',
                      'Genus:sp26' => '0.75'
                    },
  'ENDC_HPART_C_0' => {
                        'Genus' => 2
                      },
  'ENDC_HPART_C_1' => {
                        'Genus:sp20' => 1,
                        'Genus:sp26' => 1
                      },
  'ENDC_HPART_E_0' => {
                        'Genus' => '1'
                      },
  'ENDC_HPART_E_1' => {
                        'Genus:sp20' => '0.5',
                        'Genus:sp26' => '0.5'
                      },
  'ENDC_HPART_OME_0' => {
                          'Genus' => 0
                        },
  'ENDC_HPART_OME_1' => {
                          'Genus:sp20' => '0.25',
                          'Genus:sp26' => '-0.25'
                        },
  'ENDC_RANGELIST' => {
                        'Genus:sp20' => 9,
                        'Genus:sp26' => 3
                      },
  'ENDC_RICHNESS' => 2,
  'ENDC_SINGLE'   => '0.444444444444444',
  'ENDC_WE'       => '0.444444444444444',
  'ENDC_WE_NORM'  => '0.444444444444444',
  'ENDC_WTLIST'   => {
                     'Genus:sp20' => '0.111111111111111',
                     'Genus:sp26' => '0.333333333333333'
                   },
  'ENDW_CWE'      => '0.222222222222222',
  'ENDW_CWE_NORM' => '0.222222222222222',
  'ENDW_HPART_0'  => {
                      'Genus' => 1
                    },
  'ENDW_HPART_1' => {
                      'Genus:sp20' => '0.25',
                      'Genus:sp26' => '0.75'
                    },
  'ENDW_HPART_C_0' => {
                        'Genus' => 2
                      },
  'ENDW_HPART_C_1' => {
                        'Genus:sp20' => 1,
                        'Genus:sp26' => 1
                      },
  'ENDW_HPART_E_0' => {
                        'Genus' => '1'
                      },
  'ENDW_HPART_E_1' => {
                        'Genus:sp20' => '0.5',
                        'Genus:sp26' => '0.5'
                      },
  'ENDW_HPART_OME_0' => {
                          'Genus' => 0
                        },
  'ENDW_HPART_OME_1' => {
                          'Genus:sp20' => '0.25',
                          'Genus:sp26' => '-0.25'
                        },
  'ENDW_RANGELIST' => {
                        'Genus:sp20' => 9,
                        'Genus:sp26' => 3
                      },
  'ENDW_RICHNESS' => 2,
  'ENDW_SINGLE'   => '0.444444444444444',
  'ENDW_WE'       => '0.444444444444444',
  'ENDW_WE_NORM'  => '0.444444444444444',
  'ENDW_WTLIST'   => {
                     'Genus:sp20' => '0.111111111111111',
                     'Genus:sp26' => '0.333333333333333'
                   },
  'END_ABS1'         => 0,
  'END_ABS1_LIST'    => {},
  'END_ABS1_P'       => '0',
  'END_ABS2'         => 0,
  'END_ABS2_LIST'    => {},
  'END_ABS2_P'       => undef,
  'END_ABS_ALL'      => 0,
  'END_ABS_ALL_LIST' => {},
  'END_ABS_ALL_P'    => '0'
}
