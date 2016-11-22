#!/usr/bin/perl

# tests for the RemapGuessing tool
# structure for this file taken from other Biodiverse test files e.g. 13-Tree.t

use strict;
use warnings;

use Test::More;
use Biodiverse::RemapGuesser;

use List::Util qw(shuffle);

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @test_subs = grep{$_ =~ 'main::test_'} $obj->functions();

exit main();

sub main {
    foreach my $sub (@test_subs) {
        no strict 'refs';
        $sub->();
    }

    done_testing();
    return 0;
}


sub test_basic_examples {
    # testing some basic 'off by one' type remappings
    my @separators = (' ', '\t', ':', '_', '.', '');

    foreach my $sep1 (@separators) {
        # build the BaseData labels
        my @base_data_labels = ();
        for my $i (0..10) {
            push(@base_data_labels, "genus".$sep1."sp".$i);
        }

        foreach my $sep2 (@separators) {
            my @tree_labels = ();
            # build the mismatched tree labels
            for my $i (0..10) {
                push(@tree_labels, "genus".$sep2."sp".$i);
            }

            # guess the remap
            my %results = Biodiverse::RemapGuesser::guess_remap(\@base_data_labels, \@tree_labels);

            # ensure the remapping was correct
            foreach my $i (1..10) {
                is($results{"genus".$sep2."sp".$i}, "genus".$sep1."sp".$i, 
                   "genus".$sep2."sp".$i." goes to "."genus".$sep1."sp".$i);
            }
        }
    }
}





