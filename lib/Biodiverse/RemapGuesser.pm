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

# largest edit distance before user is shown a warning
use constant MAX_DISTANCE => 3;

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
    

    my @existing_labels = $first_source->get_labels();
    my @new_labels = $second_source->get_labels();


    my %remap_results = $self->guess_remap({
        "existing_labels" => \@existing_labels, 
            "new_labels" => \@new_labels
    });

    my %remap = %{$remap_results{remap}};
    my $furthest = $remap_results{furthest_dist};
    my $furthest_label = $remap_results{furthest_label};
    
    # do we warn the user about a 'bad' match?
    
    my $warn = ($furthest > MAX_DISTANCE) ? 1 : 0;
    #say "furthest: $furthest, warn: $warn";
    
    #foreach my $m (keys %remap) {
    #    my $mapped_to = $remap{$m};
    #    say "generate_auto_remap: $m -> $mapped_to";
    #}

    
    my %results = (
	remap => \%remap,
        warn => $warn,
        furthest_label => $furthest_label,
	);


    return wantarray ? %results : \%results;
}





    
# takes in two references to arrays of labels (existing_labels and new_labels)
# returns a hash mapping labels in the second list to labels in the first list
sub guess_remap {
    my $self = shift;
    my $args = shift || {};

    my $first_ref = $args->{"existing_labels"};
    my $second_ref = $args->{"new_labels"};
    
    my @first_labels = sort @{$first_ref};
    my @second_labels = sort @{$second_ref};


    # look for simple punctuation match
    my %quick_results = $self->attempt_quick_remap({
	"existing_labels" => \@first_labels,
        "new_labels" => \@second_labels,
            
    });
    
    if($quick_results{success}) {
	$quick_results{"quick"} = 1;
	say "[RemapGuesser] generated a quick remap";
	return wantarray ? %quick_results : \%quick_results;
    }

      
    my %remap;

    # assume that the labels have been uniformly deformed (i.e. they
    # differ according to a pattern (or at least by the same
    # distance))
    my $assume_uniform_deformation = 1;
    
    # also keep track of the furthest distance we have to accept,
    # and the mean distance, so we get an idea of how good this remap is.
    my $furthest_distance = 0;
    my $furthest_label = "";
    my $distance_sum = 0;

    
    my $accepted_distance;

    
    my $match_index;


    # if there are fewer labels in one list than the other, let the
    # smaller list be in control of selection
    my @chooser;
    my @chosen;
    my $swap;
    if(scalar(@first_labels) < scalar(@second_labels)) {
        say "[RemapGuesser]: Fewer existing labels, so let them choose.";
        @chooser = @first_labels;
        @chosen = @second_labels;
        $swap = 1;
    }
    else {
        say "[RemapGuesser]: The new labels get to choose.";
        @chooser = @second_labels;
        @chosen = @first_labels;
        $swap = 0;
    }


    foreach my $label (@chooser) {
        my $min_distance = distance($label, $chosen[0]);
        my $closest_label = $chosen[0];
	$match_index = 0;
	   
	# do the comparison ignoring leading and trailing
	# whitespace as this can cause match issues e.g. 'sp1 ' is
	# just as close to 'sp10' as 'sp1'
	my $stripped_label = $label;
	$stripped_label =~ s/^\s+|\s+$//g;
	
	# also do the comparison ignoring case because it seems
	# unlikely that someone would intentionally use case to
	# distinguish between labels, whereas having two versions
	# of the same data with different case conventions seems
	# more likely. e.g. GenusSpecies1 -> genus_species1
	$stripped_label = lc($stripped_label);

	
        # find the closest match
        foreach my $i (0..$#chosen) {
	    my $comparison_label = $chosen[$i];
	   
	    my $stripped_comparison_label = $comparison_label;
	    $stripped_comparison_label =~ s/^\s+|\s+$//g;

	    $stripped_comparison_label = lc($stripped_comparison_label);

            my $this_distance = distance($stripped_label, $stripped_comparison_label);
            if($this_distance <= $min_distance) {
                $min_distance = $this_distance;
                $closest_label = $comparison_label;
		$match_index = $i;

		# if we've previously accepted a match of this distance
		# and we're assuming uniform deformation, we can end the run here.
		if($assume_uniform_deformation && defined $accepted_distance
		   && $this_distance == $accepted_distance) {
		    last;
		}
            }
        }


        if($min_distance >= $furthest_distance) {
            $furthest_distance = $min_distance;
            $furthest_label = $label;
        }

        
	$distance_sum += $min_distance;
	$accepted_distance = $min_distance;
        $remap{$label} = $closest_label;

	# now remove the match we made from chosen
	splice(@chosen, $match_index, 1);
    }

    my $mean_distance;

    # need to check if it's 0 to protect from empty list being passed in
    if($#chooser != 0) {
	$mean_distance = $distance_sum/($#second_labels+1);
    }
    

    say "[RemapGuesser] generated a full remap";

    # we need to swap the keys and values if the existing labels
    # 'chose' from the new labels.
    if($swap) {
        $furthest_label = $remap{$furthest_label};

        my %hash2;
        while ((my $key, my $value) = each %remap) {
            $hash2{$value}=$key;
        }
        %remap=%hash2;
    }
    
    my %results = (
	quick => 0,
	furthest_dist => $furthest_distance,
        furthest_label => $furthest_label,
	mean_dist => $mean_distance,
	remap => \%remap,
	);
  
    #for my $k (keys %remap) {
    #    my $map = $remap{$k};
    #    say "guess_remap after: $k -> $map";
    #}

  
    return wantarray ? %results : \%results;
}



# tries to quickly match two lists of labels that differ only in
# punctuation/whitespace (not letters or digits)
sub attempt_quick_remap {
    my $class = shift;
    my $args = shift || {};
    
    my @first_labels = @{$args->{"existing_labels"}};
    my @second_labels = @{$args->{"new_labels"}};

    #say @first_labels;
    #say @second_labels;
    
    # create a hash mapping no punct to original string
    my %no_punct_lookup;
    for my $original (@first_labels) {
	my $fixed = $original;
	$fixed =~ s/[^\d\w]/_/g;
	$no_punct_lookup{$fixed} = $original;
    }
        

    # try to create a complete match
    my %remap;
    my $success = 1;
    foreach my $label (@second_labels) {
	my $no_punct = $label;
	$no_punct =~ s/[^\d\w]/_/g;

	if(exists $no_punct_lookup{$no_punct}) {
	    $remap{$label} = $no_punct_lookup{$no_punct};
	}
	else {
	    # couldn't find a match
	    $success = 0;
	    last;
 	}
    }


    #for my $k (keys %remap) {
        #my $map = $remap{$k};
        #say "attempt_quick_remap: $k -> $map";
    #}

    

    
    # TODO Implement tracking of furthest distance/label. Not really
    # important because if the quick match ignoring punctuation works,
    # the match is probably good anyway.
    my %results = (
	success => $success,
	remap => \%remap,
        furthest_dist => 0,
        furthest_label => "",
	);

    return wantarray ? %results : \%results;
}



1;
