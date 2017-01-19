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
my @test_subs = grep { $_ =~ 'main::test_' } $obj->functions();

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
sub test_punctuation_remap {
    my @separators = ( ' ', "\t", ':', '_', '.', '' );

    foreach my $sep1 (@separators) {

        # build the BaseData labels
        my @base_data_labels = ();
        for my $i ( 0 .. 10 ) {
            push( @base_data_labels, "genus" . $sep1 . "sp" . $i );
        }

        foreach my $sep2 (@separators) {
            my @tree_labels = ();

            # build the mismatched tree labels
            for my $i ( 0 .. 10 ) {
                push( @tree_labels, "genus" . $sep2 . "sp" . $i );
            }

            # guess the remap
            my $guesser = Biodiverse::RemapGuesser->new();

            my %remap_results = $guesser->guess_remap(
                {
                    existing_labels => \@base_data_labels,
                    new_labels      => \@tree_labels,
                    ignore_case     => 0,
                    max_distance    => 0,
                }
            );

            my $results = $remap_results{remap};

            # ensure the remapping was correct
            my $sep1_as_string = $sep1 eq "\t" ? '\t' : $sep1;
            my $sep2_as_string = $sep2 eq "\t" ? '\t' : $sep2;
            subtest "test_punctuation_remap '$sep1_as_string' -> '$sep2_as_string'" => sub {
                foreach my $i ( 1 .. 10 ) {
                    my $res_key  = "genus" . $sep2 . "sp" . $i;
                    my $expected = "genus" . $sep1 . "sp" . $i;
                    is(
                        $results->{ $res_key },
                        $expected,
                        "$res_key maps to $expected",
                    );
                }
            };
        }
    }
}

# make sure auto matching works with leading and trailing whitespace
sub test_border_whitespace {
    my @whitespace = ( " ", "  ", "   ", "\t" );

    foreach my $repetitions ( 0 .. 10 ) {
        my $starta = $whitespace[ rand @whitespace ];
        my $startb = $whitespace[ rand @whitespace ];
        my $enda   = $whitespace[ rand @whitespace ];
        my $endb   = $whitespace[ rand @whitespace ];

        # build the label lists
        my @base_data_labels = ();
        my @tree_labels      = ();
        for my $i ( 0 .. 10 ) {
            push( @base_data_labels, $starta . "genussp$i" . $enda );
            push( @tree_labels,      $startb . "genussp$i" . $endb );
        }

        my $guesser = Biodiverse::RemapGuesser->new();

        my %remap_results = $guesser->guess_remap(
            {
                existing_labels => \@base_data_labels,
                new_labels      => \@tree_labels,
                max_distance    => 0,

            }
        );

        my %results = %{ $remap_results{remap} };

        # ensure the remapping was correct
        subtest "test_border_whitespace_rep$repetitions" => sub {
            foreach my $i ( 1 .. 10 ) {
                is(
                    $results{ $startb . 'genussp' . $i . $endb },
                    $starta . 'genussp' . $i . $enda,
                    $startb
                      . "genussp$i"
                      . $endb
                      . " maps to "
                      . $starta
                      . "genussp$i"
                      . $enda
                );
            }
        }
    }
}

# make sure Genus:Species1 -> genus_species1 etc.
sub test_case_differences {

    # build the labels
    my @base_data_labels = ();
    my @tree_labels      = ();
    for my $i ( 0 .. 10 ) {
        push( @base_data_labels, "genus:sp$i" );
        push( @tree_labels,      "genus_sp$i" );
    }

    my $guesser = Biodiverse::RemapGuesser->new();

    my %remap_results = $guesser->guess_remap(
        {
            existing_labels => \@base_data_labels,
            new_labels      => \@tree_labels,
            max_distance    => 0,
            ignore_case     => 1,
        }
    );

    my %results = %{ $remap_results{remap} };

    # ensure the remapping was correct
    subtest test_case_differences => sub {
        foreach my $i ( 1 .. 10 ) {
            is(
                $results{ "genus_sp$i" },
                "genus:sp$i",
                "genus_sp$i maps to genus:sp$i"
            );
        }
    };
}

# make sure Hipopotamus -> Hippopotamus etc.
sub test_typos {

    # build the labels
    my @base_data_labels = ();
    my @tree_labels      = ();

    push( @base_data_labels, "Hippopotamus" );
    push( @base_data_labels, "Horse" );
    push( @base_data_labels, "Dog" );

    push( @tree_labels, "Hipopotamus" );
    push( @tree_labels, "Hoarse" );
    push( @tree_labels, "Doge" );

    my $guesser = Biodiverse::RemapGuesser->new();

    my %remap_results = $guesser->guess_remap(
        {
            existing_labels => \@base_data_labels,
            new_labels      => \@tree_labels,
            max_distance    => 3,
            ignore_case     => 0,

        }
    );

    my %results = %{ $remap_results{remap} };

    # ensure the remapping was correct
    is( $results{"Hipopotamus"}, "Hippopotamus",
        "Hipopotamus -> Hippopotamus" );

    is( $results{"Hoarse"}, "Horse", "Hoarse -> Horse" );
    is( $results{"Doge"},   "Dog",   "Doge -> dog" );

}

# make sure it isn't too slow for a largish dataset
sub test_large_dataset {

    # build the labels
    my @base_data_labels = ();
    my @tree_labels      = ();

    # set this to a large value to test the time it takes
    # for now just set to 1 so the test results aren't flooded with this.
    my $dataset_size = 1;

    for my $i ( 0 .. $dataset_size ) {
        push( @base_data_labels, "genus:sp$i" );
        push( @tree_labels,      "genus_sp$i" );
    }

    my $guesser = Biodiverse::RemapGuesser->new();

    my %remap_results = $guesser->guess_remap(
        {
            existing_labels => \@base_data_labels,
            new_labels      => \@tree_labels,
            max_distance    => 0,

        }
    );

    my %results = %{ $remap_results{remap} };

    # ensure the remapping was correct
    subtest test_large_dataset => sub {
        foreach my $i ( 1 .. $dataset_size ) {
            is(
                $results{ "genus_sp$i" },
                "genus:sp$i",
                "genus_sp$i maps to genus:sp$i"
            );
        }
    };
}

# empty lists etc. etc.
sub test_edge_cases {
    my @base_data_labels = ();
    my @tree_labels      = ();

    # guess the remap

    eval {
        my $guesser = Biodiverse::RemapGuesser->new();

        my %remap_results = $guesser->guess_remap(
            {
                existing_labels => \@base_data_labels,
                new_labels      => \@tree_labels,
                max_distance    => 0,
            }
        );

        my %results = %{ $remap_results{remap} };
    };

    # should be no errors
    is( $@, "", "Handling empty lists." );

}

sub test_size_mismatch {

    # build the labels
    my @base_data_labels = ();
    my @tree_labels      = ();
    my $dataset_size     = 10;

    for my $i ( 0 .. $dataset_size ) {
        push( @base_data_labels, "genus:sp$i" );
    }

    for my $i ( 0 .. $dataset_size * 2 ) {
        push( @tree_labels, "genus_sp$i" );
    }

    my $guesser = Biodiverse::RemapGuesser->new();

    my %remap_results = $guesser->guess_remap(
        {
            existing_labels => \@base_data_labels,
            new_labels      => \@tree_labels,
            max_distance    => 0,

        }
    );

    my %results = %{ $remap_results{remap} };

    # ensure the remapping was correct
    subtest test_size_mismatch => sub {
        foreach my $i ( 1 .. $dataset_size ) {
            is(
                $results{ "genus_sp$i" },
                "genus:sp$i",
                "genus_sp$i maps to genus:sp$i",
            );
        }
    };
}

sub test_size_mismatch2 {

    # build the labels
    my @base_data_labels = ();
    my @tree_labels      = ();
    my $dataset_size     = 10;

    for my $i ( 0 .. $dataset_size * 2 ) {
        push( @base_data_labels, "genus:sp$i" );
    }

    for my $i ( 0 .. $dataset_size ) {
        push( @tree_labels, "genus_sp$i" );
    }

    my $guesser = Biodiverse::RemapGuesser->new();

    my %remap_results = $guesser->guess_remap(
        {
            existing_labels => \@base_data_labels,
            new_labels      => \@tree_labels,
            max_distance    => 0,

        }
    );

    my %results = %{ $remap_results{remap} };

    # ensure the remapping was correct
    subtest test_size_mismatch2 => sub {
        foreach my $i ( 1 .. $dataset_size ) {
            is(
                $results{ "genus_sp$i" },
                "genus:sp$i",
                "genus_sp$i maps to genus:sp$i",
            );
        }
    };
}

# make sure multiple typos remap to the same correct label
sub test_multiple_remap {

    # build the labels
    my @base_data_labels = ();
    my @tree_labels      = ();

    push( @base_data_labels, "Hippopotamus" );

    push( @tree_labels, "Hipoppotamus" );
    push( @tree_labels, "Hipopotamus" );

    my $guesser = Biodiverse::RemapGuesser->new();

    my %remap_results = $guesser->guess_remap(
        {
            existing_labels => \@base_data_labels,
            new_labels      => \@tree_labels,
            max_distance    => 3,
            ignore_case     => 0,

        }
    );

    my %results = %{ $remap_results{remap} };

    # ensure the remapping was correct
    is( $results{"Hipopotamus"}, "Hippopotamus",
        "Hipopotamus -> Hippopotamus" );

    is( $results{"Hipoppotamus"},
        "Hippopotamus", "Hipopotamus -> Hippopotamus" );

}

# make sure the max distance cap is actually working
sub test_max_distance {

    # build the labels
    my @base_data_labels = (qw /first second third fourth/);
    my @tree_labels      = (qw /first seconda thirdaa fourthaaa/);

    my $guesser = Biodiverse::RemapGuesser->new();

    my %remap_results = $guesser->guess_remap(
        {
            existing_labels => \@base_data_labels,
            new_labels      => \@tree_labels,
            max_distance    => 2,
            ignore_case     => 0,

        }
    );

    my %results = %{ $remap_results{remap} };

    is( $results{first},   "first",  "first -> first" );
    is( $results{seconda}, "second", "seconda -> second" );
    is( $results{thirdaa}, "third",  "thirdaa -> third" );
    isnt( $results{fourthaaa}, "fourth", "fourthaaa does not map to fourth" );

}


# make sure the max distance cap is actually working
sub test_max_distance_ambiguous {

    # build the labels
    my @base_data_labels = (qw /first second thirda1 thirda2/);
    my @tree_labels      = (qw /first seconda thirdaa thirdab/);

    my $guesser = Biodiverse::RemapGuesser->new();

    my %remap_results = $guesser->guess_remap(
        {
            existing_labels => \@base_data_labels,
            new_labels      => \@tree_labels,
            max_distance    => 2,
            ignore_case     => 0,

        }
    );

    my $results = $remap_results{remap};

    is( $results->{first},   "first",   "first unchanged" );
    is( $results->{seconda}, "second",  "seconda -> second" );
    is( $results->{thirdaa}, "thirdaa", "thirdaa unchanged" );
    is( $results->{thirdab}, "thirdab", "thirdab unchanged " );

    my $expected_ambiguous = {
        thirdaa => ['thirda1', 'thirda2'],
        thirdab => ['thirda1', 'thirda2'],
    };

    # can't just compare the two using is_deeply because the order in
    # the list is unpredictable, causing the test to fail sometimes.
    # need to sort each individual list.
    my %actual = %{$remap_results{ambiguous_matches}};

    foreach my $key (keys %actual) {
        my @list = @{$actual{$key}};
        @list = sort @list;
        $actual{$key} = \@list;
    }
    
            
    is_deeply (
        \%actual,
        $expected_ambiguous,
        'got expected ambiguous matches for min distance 2'
    );
}

