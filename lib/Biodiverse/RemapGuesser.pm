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
    my ($self, %args) = @_;

    my $remap_hash = $args{remap};
    my $data_source = $args{new_source};
    
    $data_source->remap_labels_from_hash( remap=>$remap_hash );
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
            "new_labels" => \@new_labels,
            "max_distance" => $max_distance,
    });

    my $remap = $remap_results->{remap};

  
    #my $success = ($furthest > $max_distance) ? 0 : 1;

    # TODO remove whole concept of 'success'
    # matches which exceed the distance just get 'not matched'
    my $success = 1;
    
    
    #foreach my $m (keys %remap) {
    #    my $mapped_to = $remap{$m};
    #    say "generate_auto_remap: $m -> $mapped_to";
    #}
   
    my %results = (
        remap => $remap,
        exact_matches => $remap_results->{exact_matches},
        punct_matches => $remap_results->{punct_matches},
        typo_matches => $remap_results->{typo_matches},
        not_matched => $remap_results->{not_matched},
        );

    return wantarray ? %results : \%results;
}


# Takes in a list of keys and a hash, returns a string showing a
# sample of how the list of keys is mapped in the hash.
 sub create_example_string {
     my ($self, %args) = @_;

     my $the_hash = $args{hash};
     my @the_keys = @{$args{keys}};

     my $sample_size = (2 > $#the_keys) ? scalar($#the_keys) : 2;
     if($sample_size < 0) {
         return "";
     }
    
     my $str = "\n(e.g. ";
     foreach my $i (0..$sample_size) {
         my $key = $the_keys[$i];
         my $value = $the_hash->{$key};
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





# takes a string, returns it with non word/digit characters replaced
# by underscores.
sub no_punct {
    my $self = shift;
    my $str = shift;
    #say "no_punct in: $str";
    $str =~ s/^['"]//;
    $str =~ s/['"]$//;
    $str =~ s/[^\d\w]/_/g;
    #say "no_punct out: $str";
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
    # currently exempt from checking for the max distance
    
    # build the hash mapping punctuation-less existing labels to their
    # original value.
    my %no_punct_hash;
    for my $label (@existing_labels) {
        $no_punct_hash{$self->no_punct($label)} = $label;
    }

    #say "no_punct_hash keys: ", keys %no_punct_hash;
    
    # look for no punct matches for each of the unmatched new labels
    my @punct_matches = ();
    @unprocessed_new_labels = ();
    my %existing_labels_that_got_matched;
    foreach my $new_label (@new_labels) {
        #say "Looking in the no_punct_hash for $new_label";
        if(exists($no_punct_hash{$self->no_punct($new_label)})) {
            #say "Found it in there";
            $remap{$new_label} = $no_punct_hash{$self->no_punct($new_label)};
            push(@punct_matches, $new_label);
            $existing_labels_that_got_matched{$no_punct_hash{$self->no_punct($new_label)}} = 1;
        }
        else {
            #say "Couldn't find it in there";
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
    # step 3: edit distance based matching (try to catch typos).  For
    # each of the as yet unmatched new labels, find the closest match
    # in the old labels. If it is under the threshold, add it as a
    # match.

    @unprocessed_new_labels = ();
    my $max_distance = $args->{max_distance};
    my @typo_matches = ();
    
    foreach my $new (@new_labels) {
        my $min_distance = $max_distance + 1;
        my $min_label = "";
        
        foreach my $old (@existing_labels) {
            my $distance = distance( $new, $old );
            if( $distance <= $min_distance ) {
                $min_distance = $distance;
                $min_label = $old;
            }
        }

        if($min_distance <= $max_distance) {
            # we found a legitimate match
            $remap{$new} = $min_label;

            # for now, don't delete the match from existing labels,
            # because if we're trying to catch typos, there might be
            # multiple 'labels' (really typos) in the new data that
            # need to be remapped to the same label in the existing
            # data.

            push( @typo_matches, $new );
        }
        else {
            push( @unprocessed_new_labels, $new );
        }        
    }
    


    @new_labels = @unprocessed_new_labels;

    

    #######################
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
        typo_matches => \@typo_matches,
        not_matched => \@new_labels,
        );

    return wantarray ? %results : \%results;
}



1;
