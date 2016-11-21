# Proof of concept program for the automatic remap idea
# https://github.com/shawnlaffan/biodiverse/issues/581

use Text::Levenshtein qw(distance);

my @base_data_labels = (
    "Genus_sp1",
    "Genus_sp2",
    "Genus_sp3",
    "Genus_sp4",
    "Genus_sp5",
    "Genus_sp6",
    "Genus_sp7",
    "Genus_sp8",
    "Genus_sp9",
    "Genus_sp10",
    );

my @tree_labels = (
    "genus:sp1",
    "genus:sp2",
    "genus:sp3",
    "genus:sp4",
    "genus:sp5",
    "genus:sp6",
    "genus:sp7",
    "genus:sp8",
    "genus:sp9",
    "genus:sp10",
    );


my ($furthest, $mean, %remap) = generate_remap_hash(\@base_data_labels, \@tree_labels);
foreach my $r (sort keys %remap) {
    print "$r -> $remap{$r}\n";
}
print "Furthest: $furthest\n";
print "Mean: $mean\n";



# takes in two references to arrays of labels
# returns a hash mapping labels in the second list to labels in the first list
# can be used to generate a remap table (Element Property Table)
sub generate_remap_hash {
    my ($first_ref, $second_ref) = @_;
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
