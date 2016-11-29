package Biodiverse::RemapGuesser;

# guesses appropriate remappings between labels.
# canonical examples:
#     mapping "genus_species" to "genus species"
#             "genus:species" to "genus_species"
#             "Genus_species" to "genus:species" etc.

use 5.010;
use strict;
use warnings;

use Text::Levenshtein qw(distance);

our $VERSION = '1.99_006';


sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}


# given a remap hash and a data source, actually performs the remap.
sub perform_auto_remap {
    my $self = shift;
    my $args = shift || {};

    my %remap_hash = %{$args->{"remap_hash"}};
    my $data_source = $args->{"data_source"};

    
    $data_source->remap_labels_from_hash(remap=>\%remap_hash);
    return;
}


# takes a two references to trees/matrices/basedata and tries to map
# the first one to the second one.
sub generate_auto_remap {
    my $self = shift;
    my $args = shift || {};
    my $first_source = $args->{"existing_data_source"};
    my $second_source = $args->{"new_data_source"};
    my $max_distance = $args->{"max_distance"};

    my @existing_labels = $first_source->get_labels();
    my @new_labels = $second_source->get_labels();


    my $remap_results = $self->guess_remap({
        "existing_labels" => \@existing_labels, 
            "new_labels" => \@new_labels
    });

    my %remap = %{$remap_results->{remap}};
    my $furthest = $remap_results->{furthest_dist};
    my $furthest_label = $remap_results->{furthest_label};
    
    # do we warn the user about a 'bad' match?
    
    my $success = ($furthest > $max_distance) ? 0 : 1;
    #say "furthest: $furthest, warn: $warn";
    
    #foreach my $m (keys %remap) {
    #    my $mapped_to = $remap{$m};
    #    say "generate_auto_remap: $m -> $mapped_to";
    #}



    my $remap_stats = $self->build_remap_stats($remap_results);
    my $stats = $remap_stats->{stats_string};

    
    my %results = (
	remap => \%remap,
        success => $success,
        furthest_label => $furthest_label,
        stats => $stats,
	);


    return wantarray ? %results : \%results;
}


# Function used by build_remap_stats. Takes in a list of keys and a
# hash, returns a string showing a sample of how the list of keys is
# mapped in the hash.
 sub create_example_string {
     my ($self, %args) = @_;

     my %the_hash = %{$args{hash}};
     my @the_keys = @{$args{keys}};

     my $sample_size = (2 > $#the_keys) ? scalar($#the_keys) : 2;
     if($sample_size < 0) {
         return "";
     }
    
     my $str = "\n(e.g. ";
     foreach my $i (0..$sample_size) {
         my $key = $the_keys[$i];
         my $value = $the_hash{$key};
         if($args{no_values}) {
             $str .= "$key, ";
         }
         else {
             $str .= "$key -> $value, ";
         }
     }
     $str .= ")";
     return $str;
}



# pass in the results of guess_remap, this builds and returns a string
# describing what happened
sub build_remap_stats {
    my $self = shift;
    my $args = shift || {};

    my $stats = "\n";

    my %remap = %{$args->{remap}};
   
    my @exact_matches = @{$args->{exact_matches}};
    my @punct_matches = @{$args->{punct_matches}};
    my @not_matched = @{$args->{not_matched}};
    
    my $exact_match_count = @{$args->{exact_matches}};
    my $punct_match_count = @{$args->{punct_matches}};
    my $not_matched_count = @{$args->{not_matched}};

    $stats .= "Exact Matches: $exact_match_count";
    $stats .= $self->create_example_string(hash => \%remap, keys => \@exact_matches);

    $stats .= "\n\nPunctuation Matches: $punct_match_count";
    $stats .= $self->create_example_string(hash => \%remap, keys => \@punct_matches);

    $stats .= "\n\nNot Matched: $not_matched_count";
    $stats .= $self->create_example_string(hash => \%remap, keys => \@not_matched, no_values=>1);

    $stats .= "\n\n";
       
    my %results = (
        stats_string => $stats,
        );
    
    return wantarray ? %results : \%results;
}



# takes a string, returns it with non word/digit characters replaced
# by underscores.
sub no_punct {
    my $self = shift;
    my $str = shift;
    $str =~ s/[^\d\w]/_/g;
    return $str;
}

    
# takes in two references to arrays of labels (existing_labels and new_labels)
# returns a hash mapping labels in the second list to labels in the first list
sub guess_remap {
    my $self = shift;
    my $args = shift || {};

    my @existing_labels = sort @{$args->{"existing_labels"}};
    my @new_labels = sort @{$args->{"new_labels"}};
    
    my %remap;

    ################################################################
    # step 1: find exact matches
    my @unprocessed_new_labels = ();
    my @exact_matches = ();
    my %existing_labels_hash = map {$_ => 1} @existing_labels;
    foreach my $new_label (@new_labels) {
        if(exists($existing_labels_hash{$new_label})) {
            $remap{$new_label} = $new_label;
            push(@exact_matches, $new_label);
        }
        else {
            push(@unprocessed_new_labels, $new_label);
        }
    }

    # and now remove any existing labels that were exact matched
    my @unprocessed_existing_labels = ();
    foreach my $existing_label (@existing_labels) {
        # we can just look in the keys since they were exact matches
        if(!exists($remap{$existing_label})) {
            push(@unprocessed_existing_labels, $existing_label);
        }
    }

    
    @new_labels = @unprocessed_new_labels;
    @existing_labels = @unprocessed_existing_labels;
   

    ################################################################
    # step 2: find punctuation-less matches e.g. a:b matches a_b 

    # build the hash mapping punctuation-less existing labels to their
    # original value.
    my %no_punct_hash;
    for my $label (@existing_labels) {
	$no_punct_hash{$self->no_punct($label)} = $label;
    }

    # look for no punct matches for each of the unmatched new labels
    my @punct_matches = ();
    @unprocessed_new_labels = ();
    my %existing_labels_that_got_matched;
    foreach my $new_label (@new_labels) {
        if(exists($no_punct_hash{$self->no_punct($new_label)})) {
            $remap{$new_label} = $no_punct_hash{$self->no_punct($new_label)};
            push(@punct_matches, $new_label);
            $existing_labels_that_got_matched{$no_punct_hash{$self->no_punct($new_label)}} = 1;
        }
        else {
            push(@unprocessed_new_labels, $new_label);
        }
    }

    # now remove existing labels that were punct matched
    @unprocessed_existing_labels = ();
    foreach my $existing_label (@existing_labels) {
        if(!exists($existing_labels_that_got_matched{$existing_label})) {
            push(@unprocessed_existing_labels, $existing_label);
        }
    }

    @new_labels = @unprocessed_new_labels;
    @existing_labels = @unprocessed_existing_labels;


    ################################################################
    # step 3: more complex mappings e.g. string distance can go here
    



    


    ################################################################
    # step 4: now figure out the max distance and corresponding 'max
    # string'
    my $max_distance = 0;
    my $max_label = "";
    for my $label (keys %remap) {
        my $distance = distance($label, $remap{$label});
        if($distance >= $max_distance) {
            $max_distance = $distance;
            $max_label = $label;
        }
    }



    # There may be some 'not matched' strings which will cause
    # problems if they don't have a corresponding remap hash entry.
    # put them in the hash.
    foreach my $label (@new_labels) {
        $remap{$label} = $label;
    }
    
        
    my %results = (
        remap => \%remap,
        exact_matches => \@exact_matches,
        punct_matches => \@punct_matches,
        not_matched => \@new_labels,
        furthest_dist => $max_distance,
        furthest_label => $max_label,
        );

    return wantarray ? %results : \%results;
}



1;
