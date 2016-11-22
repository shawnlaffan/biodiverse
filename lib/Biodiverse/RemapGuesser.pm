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
    my $furthestDistance = 0;
    my $distanceSum = 0;
    
    foreach my $label (@second_labels) {
        my $min_distance = distance($label, $first_labels[0]);
        my $closest_label = $first_labels[0];

        # find the closest match (will default to the last in case of a tie)
        foreach my $comparison_label (@first_labels) {
            my $this_distance = distance($label, $comparison_label);
            if($this_distance <= $min_distance) {
                $min_distance = $this_distance;
                $closest_label = $comparison_label;
            }
        }

        $furthestDistance = $min_distance if($min_distance > $furthestDistance);
        $distanceSum += $min_distance;
        $remap{$label} = $closest_label;
    }

    my $meanDistance = $distanceSum/($#second_labels+1);
    return ($furthestDistance, $meanDistance, %remap);
}




1;
