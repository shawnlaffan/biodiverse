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

# testing some basic 'off by one' type remappings
sub test_basic_examples {
    my @separators = (' ', "\t", ':', '_', '.', '');

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
	    my $guesser = Biodiverse::RemapGuesser->new();
	    
            my %remap_results = $guesser->guess_remap({
		"existing_labels" => \@base_data_labels, 
		"new_labels" => \@tree_labels
	    });

	    my %results = %{$remap_results{remap}};
	    
            # ensure the remapping was correct
            foreach my $i (1..10) {
                is($results{"genus".$sep2."sp".$i}, "genus".$sep1."sp".$i, 
                   "genus".$sep2."sp".$i." goes to "."genus".$sep1."sp".$i);
            }
        }
    }
}



# make sure auto matching works with leading and trailing whitespace
sub test_border_whitespace {
    my @whitespace = (" ", "  ", "   ", "\t", "\n", "\r");

    foreach my $repetitions (0..10) {
	my $starta = $whitespace[rand @whitespace];
	my $startb = $whitespace[rand @whitespace];
	my $enda = $whitespace[rand @whitespace];
	my $endb = $whitespace[rand @whitespace];

        # build the label lists
        my @base_data_labels = ();
	my @tree_labels = ();
	for my $i (0..10) {
            push(@base_data_labels, $starta."genussp$i".$enda);
	    push(@tree_labels, $startb."genussp$i".$endb);
        }


	my $guesser = Biodiverse::RemapGuesser->new();
	    
	my %remap_results = $guesser->guess_remap({
	    "existing_labels" => \@base_data_labels, 
	    "new_labels" => \@tree_labels
	});

	my %results = %{$remap_results{remap}};


	

	# ensure the remapping was correct
	foreach my $i (1..10) {
	    is($results{$startb."genussp$i".$endb}, $starta."genussp$i".$enda,
	       $startb."genussp$i".$endb." goes to ".$starta."genussp$i".$enda
	       );
	}
    }
}




# make sure Genus:Species1 -> genus_species1 etc.
sub test_case_differences {
    # build the labels
    my @base_data_labels = ();
    my @tree_labels = ();
    for my $i (0..10) {
	push(@base_data_labels, "Genus:Sp".$i);
	push(@tree_labels, "genus_sp".$i);
    }

    my $guesser = Biodiverse::RemapGuesser->new();
	    
    my %remap_results = $guesser->guess_remap({
	"existing_labels" => \@base_data_labels, 
	    "new_labels" => \@tree_labels
    });

    my %results = %{$remap_results{remap}};  
    
    # ensure the remapping was correct
    foreach my $i (1..10) {
	is($results{"genus_sp".$i}, "Genus:Sp".$i, 
	   "genus_sp".$i." goes to "."Genus:Sp".$i);
    }
}


# make sure it isn't too slow for a largish dataset
sub test_large_dataset {
    # build the labels
    my @base_data_labels = ();
    my @tree_labels = ();
    my $dataset_size = 1000;

    for my $i (0..$dataset_size) {
	push(@base_data_labels, "genus:sp".$i);
	push(@tree_labels, "genus_sp".$i);
    }
    
    # guess the remap
    my $guesser = Biodiverse::RemapGuesser->new();
	    
    my %remap_results = $guesser->guess_remap({
	"existing_labels" => \@base_data_labels, 
	    "new_labels" => \@tree_labels
    });

    my %results = %{$remap_results{remap}};

    
    # ensure the remapping was correct
    foreach my $i (1..$dataset_size) {
	is($results{"genus_sp".$i}, "genus:sp".$i, 
	   "genus_sp".$i." goes to "."genus:sp".$i);
    }


}

# empty lists etc. etc.
sub test_edge_cases {
    my @base_data_labels = ();
    my @tree_labels = ();
    # guess the remap
    
    eval {
	my $guesser = Biodiverse::RemapGuesser->new();
	    
	my %remap_results = $guesser->guess_remap({
		"existing_labels" => \@base_data_labels, 
		"new_labels" => \@tree_labels
	});

	my %results = %{$remap_results{remap}};
    };
    # should be no errors
    is($@, "", "Handling empty lists.");



}
