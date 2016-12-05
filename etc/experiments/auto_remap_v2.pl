# new approach to auto remapping, keeping track of what kinds of matches we discover.

# takes a string, returns it with non word/digit characters replaced
# by underscores.
sub no_punct {
    #my $self = shift;
    my $str = shift;
    $str =~ s/[^\d\w]/_/g;
    return $str;
}



sub guess_remap {
    #my $self = shift;
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
	$no_punct_hash{no_punct($label)} = $label;
    }

    # look for no punct matches for each of the unmatched new labels
    my @punct_matches = ();
    my @unprocessed_new_labels = ();
    my %existing_labels_that_got_matched;
    foreach my $new_label (@new_labels) {
        if(exists($no_punct_hash{no_punct($new_label)})) {
            $remap{$new_label} = $no_punct_hash{no_punct($new_label)};
            push(@punct_matches, $new_label);
            $existing_labels_that_got_matched{$no_punct_hash{$new_label}} = 1;
        }
        else {
            push(@unprocessed_new_labels, $new_label);
        }
    }

    # now remove existing labels that were punct matched
    my @unprocessed_existing_labels = ();
    foreach my $existing_label (@existing_labels) {
        if(!exists($existing_labels_that_got_matched{$existing_label})) {
            push(@unprocessed_existing_labels, $existing_label);
        }
    }

    @new_labels = @unprocessed_new_labels;
    @existing_labels = @unprocessed_existing_labels;


    ################################################################
    # step 3: more complex mappings e.g. string distance can go here
    


    my %results = (
        remap => \%remap,
        exact_matches => \@exact_matches,
        punct_matches => \@punct_matches,
        not_matched => \@new_labels,
        );

    return wantarray ? %results : \%results;
}




# pass in the results of guess_remap, this builds and returns a string
# describing what happened
sub build_remap_stats {
    #my $self = shift;
    my $args = shift || {};
    my $stats = "";

    
    @exactMatches = @{$args->{exact_matches}};
    @punctMatches = @{$args->{punct_matches}};
    @notMatched = @{$args->{not_matched}};

    @exactMatchCount = ${$args->{exact_matches}};
    @punctMatchCount = ${$args->{punct_matches}};
    @notMatchedCount = ${$args->{not_matched}};
    
    
    $stats .= "Exact Matches: scalar(@exactMatches)\n";
    $stats .= "Punctuation Matches: $punctMatches\n";
    $stats .= "Not Matched: $notMatched\n";
    

    my %results = (
        stats_string => $stats,
        );
    return wantarray ? %results : \%results;
}





sub test_large_dataset {
    # build the labels
    my @base_data_labels = ();
    my @tree_labels = ();
    my $dataset_size = 20;

    for my $i (0..$dataset_size) {
	push(@base_data_labels, "genussp".$i);
	push(@tree_labels, "genussp".$i);
    }

    for my $i ($dataset_size..$dataset_size*2) {
	push(@base_data_labels, "genus_sp".$i);
	push(@tree_labels, "genus:sp".$i);
    }

    for my $i ($dataset_size*2..$dataset_size*3) {
	push(@base_data_labels, "genus_sp".$i);
	push(@tree_labels, "Genus_sp".$i);
    }


	    
    my $remap_results = guess_remap({
	"existing_labels" => \@base_data_labels, 
	    "new_labels" => \@tree_labels
    });


    my %remap = %{$remap_results->{remap}};

    foreach my $key (keys %remap) {
        #print "$key -> $remap{$key}\n";
    }


    my $remap_stats = build_remap_stats($remap_results);
    print $remap_stats->{stats_string};
    
}

test_large_dataset();

