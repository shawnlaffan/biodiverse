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
    
# takes in two references to arrays of labels (existing_labels and new_labels)
# returns a hash mapping labels in the second list to labels in the first list
# can be used to generate a remap table (Element Property Table)
sub guess_remap {
    my $self = shift;
    my $args = shift || {};

    my $first_ref = $args->{"existing_labels"};
    my $second_ref = $args->{"new_labels"};
    
    my @first_labels = @{$first_ref};
    my @second_labels = @{$second_ref};
    my %remap;

    # also keep track of the furthest distance we have to accept,
    # and the mean distance, so we get an idea of how good this remap is.
    my $furthest_distance = 0;
    my $distance_sum = 0;
    
    foreach my $label (@second_labels) {
        my $min_distance = distance($label, $first_labels[0]);
        my $closest_label = $first_labels[0];

        # find the closest match (will default to the last in case of a tie)
        foreach my $comparison_label (@first_labels) {
	    
	    # do the comparison ignoring leading and trailing
	    # whitespace as this can cause match issues e.g. 'sp1 ' is
	    # just as close to 'sp10' as 'sp1'
	    
	    my $stripped_label = $label;
	    my $stripped_comparison_label = $comparison_label;
	    $stripped_label =~ s/^\s+|\s+$//g;
	    $stripped_comparison_label =~ s/^\s+|\s+$//g;

            my $this_distance = distance($stripped_label, $stripped_comparison_label);
            if($this_distance <= $min_distance) {
                $min_distance = $this_distance;
                $closest_label = $comparison_label;
            }
        }

        $furthest_distance = $min_distance if($min_distance > $furthest_distance);
        $distance_sum += $min_distance;
        $remap{$label} = $closest_label;
    }

    my $mean_distance = $distance_sum/($#second_labels+1);
    return ($furthest_distance, $mean_distance, %remap);
}




1;
