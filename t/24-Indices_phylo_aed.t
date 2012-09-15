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

my $phylo_calcs_to_test = [qw/
    calc_phylo_aed
/];

run_indices_phylogenetic ($phylo_calcs_to_test, \&verify_results);
done_testing;

sub verify_results {
    my %args = @_;
    compare_hash_vals (
        hash_got => $args{results},
        hash_exp => get_expected_results (nbr_list_count => $args{nbr_list_count})
    );
}

sub get_expected_results {
    my %args = @_;
    my $nbr_list_count = $args{nbr_list_count};
    if ($nbr_list_count == 1) { return {
        'PHYLO_ED_LIST' => {
            'Genus:sp26' => '0.682552763166875',
            'Genus:sp20' => '0.682552763166875'
        },
        'PHYLO_AED_LIST' => {
            'Genus:sp26' => '0.207128205128205',
            'Genus:sp20' => '0.144628205128205'
        },
        'PHYLO_ES_LIST' => {
            'Genus:sp26' => '0.688503612046397',
            'Genus:sp20' => '0.688503612046397'
        }
    }; }
    elsif ($nbr_list_count == 2) { return {
        'PHYLO_ED_LIST'  => {
            'Genus:sp27' => '0.758106931866058',
            'Genus:sp12' => '0.678346653904325',
            'Genus:sp15' => '0.678240495563069',
            'Genus:sp23' => '0.557265280898026',
            'Genus:sp5'  => '0.688766811352542',
            'Genus:sp26' => '0.682552763166875',
            'Genus:sp20' => '0.682552763166875',
            'Genus:sp29' => '0.657918005249967',
            'Genus:sp24' => '0.615416143402958',
            'Genus:sp30' => '0.557265280898026',
            'Genus:sp25' => '0.615416143402958',
            'Genus:sp11' => '0.582924169600393',
            'Genus:sp10' => '0.80762333894188',
            'Genus:sp1'  => '0.678240495563069'
        },
        'PHYLO_AED_LIST'  => {
             'Genus:sp27' => '0.599310252633764',
             'Genus:sp12' => '0.050539886453687',
             'Genus:sp15' => '0.040524675881928',
             'Genus:sp23' => '0.148203607227373',
             'Genus:sp5'  => '0.386675699373672',
             'Genus:sp26' => '0.0627272750008093',
             'Genus:sp20' => '0.041893941667476',
             'Genus:sp29' => '0.0728869137531598',
             'Genus:sp24' => '0.305963938866254',
             'Genus:sp30' => '0.256899259401286',
             'Genus:sp25' => '0.368463938866254',
             'Genus:sp11' => '0.0494076062574589',
             'Genus:sp10' => '0.0281896757943279',
             'Genus:sp1'  => '0.0503930969345596'
        },
        'PHYLO_ES_LIST' => {
            'Genus:sp27' => '0.808752211567386',
            'Genus:sp12' => '0.740699957688393',
            'Genus:sp15' => '0.66656052363853',
            'Genus:sp23' => '0.506327788030815',
            'Genus:sp5'  => '0.677086839428004',
            'Genus:sp26' => '0.688503612046397',
            'Genus:sp20' => '0.688503612046397',
            'Genus:sp29' => '0.66964554863157',
            'Genus:sp24' => '0.616932918372087',
            'Genus:sp30' => '0.506327788030815',
            'Genus:sp25' => '0.616932918372087',
            'Genus:sp11' => '0.577872967365978',
            'Genus:sp10' => '0.830685020049678',
            'Genus:sp1'  => '0.66656052363853'
        }
    }; }
    else {
        croak 'Invalid nbr_list_count';
    }
}

1;