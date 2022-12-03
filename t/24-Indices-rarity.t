use strict;
use warnings;

local $| = 1;

use rlib;
use Test2::V0;

use Biodiverse::TestHelpers qw{
    :runners
};

use Data::Section::Simple qw(get_data_section);

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


    test_indices();
    test_doubled_abundance();

    
    done_testing;
    return 0;
}

sub test_indices {
    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_rarity_central
            calc_rarity_central_lists
            calc_rarity_whole
            calc_rarity_whole_lists
        /],
        calc_topic_to_test => 'Rarity',
    );
}

sub test_doubled_abundance {
    
    my $exp1_text = get_data_section ('RESULTS_1_NBR_LISTS');
    my $exp2_text = get_data_section ('RESULTS_2_NBR_LISTS');
    
    my $exp1 = eval $exp1_text;
    my $exp2 = eval $exp2_text;

    #  these results will halve
    foreach my $key (qw /RAREW_CWE RAREW_WE RAREC_WE RAREC_CWE/) {
        $exp1->{$key} = $exp1->{$key} / 2;
        $exp2->{$key} = $exp2->{$key} / 2;
    }

    #  these also will halve
    foreach my $list_name (qw /RAREW_WTLIST RAREC_WTLIST/) {
        foreach my $key (keys %{$exp1->{$list_name}}) {
            $exp1->{$list_name}{$key} = $exp1->{$list_name}{$key} / 2;
        }
        foreach my $key (keys %{$exp2->{$list_name}}) {
            $exp2->{$list_name}{$key} = $exp2->{$list_name}{$key} / 2;
        }
    }

    #  the range list values will double
    foreach my $list_name (qw /RAREW_RANGELIST RAREC_RANGELIST/) {
        foreach my $key (keys %{$exp1->{$list_name}}) {
            $exp1->{$list_name}{$key} = $exp1->{$list_name}{$key} * 2;
        }
        foreach my $key (keys %{$exp2->{$list_name}}) {
            $exp2->{$list_name}{$key} = $exp2->{$list_name}{$key} * 2;
        }
    }

    my %expected_results_overlay = (
        1 => $exp1,
        2 => $exp2,
    );

    my $cb = sub {
        my %args = @_;
        my $bd = $args{basedata_ref};
        my $lb = $bd->get_labels_ref;

        #  add a new label to all of the groups to be sure we get coverage
        foreach my $label ($bd->get_labels) {  
            my $value = 2 * $bd->get_label_sample_count (element => $label);
            $lb->add_to_lists (
                element    => $label,
                PROPERTIES => {ABUNDANCE => $value},
            );
        }

        return;
    };

    run_indices_test1 (
        calcs_to_test  => [qw/
            calc_rarity_central
            calc_rarity_central_lists
            calc_rarity_whole
            calc_rarity_whole_lists
        /],
        calc_topic_to_test => 'Rarity',
        expected_results_overlay => \%expected_results_overlay,
        callbacks       => [$cb],
    );

    return;
}



done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'RAREC_CWE'       => '0.622119815668203',
  'RAREC_RANGELIST' => {
                         'Genus:sp20' => 31,
                         'Genus:sp26' => 7
                       },
  'RAREC_RICHNESS' => 2,
  'RAREC_WE'       => '1.24423963133641',
  'RAREC_WTLIST'   => {
                      'Genus:sp20' => '0.387096774193548',
                      'Genus:sp26' => '0.857142857142857'
                    },
  'RAREW_CWE'       => '0.151831533482874',
  'RAREW_RANGELIST' => {
                         'Genus:sp1'  => 64,
                         'Genus:sp10' => 153,
                         'Genus:sp11' => 328,
                         'Genus:sp12' => 151,
                         'Genus:sp15' => 54,
                         'Genus:sp20' => 31,
                         'Genus:sp23' => 174,
                         'Genus:sp24' => 23,
                         'Genus:sp25' => 9,
                         'Genus:sp26' => 7,
                         'Genus:sp27' => 36,
                         'Genus:sp29' => 53,
                         'Genus:sp30' => 103,
                         'Genus:sp5'  => 38
                       },
  'RAREW_RICHNESS' => 14,
  'RAREW_WE'       => '2.12564146876023',
  'RAREW_WTLIST'   => {
                      'Genus:sp1'  => '0.125',
                      'Genus:sp10' => '0.104575163398693',
                      'Genus:sp11' => '0.0274390243902439',
                      'Genus:sp12' => '0.0529801324503311',
                      'Genus:sp15' => '0.203703703703704',
                      'Genus:sp20' => '0.387096774193548',
                      'Genus:sp23' => '0.0114942528735632',
                      'Genus:sp24' => '0.0869565217391304',
                      'Genus:sp25' => '0.111111111111111',
                      'Genus:sp26' => '0.857142857142857',
                      'Genus:sp27' => '0.0277777777777778',
                      'Genus:sp29' => '0.0943396226415094',
                      'Genus:sp30' => '0.00970873786407767',
                      'Genus:sp5'  => '0.0263157894736842'
                    }
}

@@ RESULTS_1_NBR_LISTS
{
  'RAREC_CWE'       => '0.207373271889401',
  'RAREC_RANGELIST' => {
                         'Genus:sp20' => 31,
                         'Genus:sp26' => 7
                       },
  'RAREC_RICHNESS' => 2,
  'RAREC_WE'       => '0.414746543778802',
  'RAREC_WTLIST'   => {
                      'Genus:sp20' => '0.129032258064516',
                      'Genus:sp26' => '0.285714285714286'
                    },
  'RAREW_CWE'       => '0.207373271889401',
  'RAREW_RANGELIST' => {
                         'Genus:sp20' => 31,
                         'Genus:sp26' => 7
                       },
  'RAREW_RICHNESS' => 2,
  'RAREW_WE'       => '0.414746543778802',
  'RAREW_WTLIST'   => {
                      'Genus:sp20' => '0.129032258064516',
                      'Genus:sp26' => '0.285714285714286'
                    }
}
