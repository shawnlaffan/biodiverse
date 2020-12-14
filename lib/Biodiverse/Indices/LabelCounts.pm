package Biodiverse::Indices::LabelCounts;

use strict;
use warnings;

our $VERSION = '3.1';

use Biodiverse::Statistics;

my $stats_class    = 'Biodiverse::Statistics';
my $metadata_class = 'Biodiverse::Metadata::Indices';


# should be a state var inside the sub?
my @QUANTILES;
for my $i (0 .. 100) {
    next if $i % 5;
    push @QUANTILES, $i;
}


sub get_metadata_calc_local_sample_count_quantiles {
    my $self = shift;
    
    my %indices = (
        ABC3_QUANTILES_ALL => {
            description     => 'List of quantiles for both neighbour sets',
            type            => 'list',
            uses_nbr_lists  => 2,
        },
        ABC3_QUANTILES_SET1 => {
            description     => 'List of quantiles for neighbour set 1',
            type            => 'list',
            uses_nbr_lists  => 1,
        },
        ABC3_QUANTILES_SET2 => {
            description     => 'List of quantiles for neighbour set 2',
            type            => 'list',
            uses_nbr_lists  => 2,
        },
    );

    my %metadata = (
        name            => 'Sample count quantiles',
        description     => "Quantiles of the sample counts across the neighbour sets.\n",
        indices         => \%indices,
        type            => 'Lists and Counts',
        pre_calc        => 'calc_abc3',
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
    );

    return $metadata_class->new(\%metadata);
}

sub calc_local_sample_count_quantiles {
    my $self = shift;
    my %args = @_;  #  rest of args into a hash

    my ($label_hash_all, $label_hash1, $label_hash2) =
      @args{qw /label_hash_all label_hash1 label_hash2/};

    my %results;

    my %type_hash = (
        ALL  => $label_hash_all,
    );
    #  avoid loops below
    #  SET1 as is the same as ALL when there is no SET2
    if (scalar keys %$label_hash2) {
        @type_hash{qw /SET1 SET2/} = ($label_hash1, $label_hash2);
    }

  SUFFIX:
    foreach my $type (sort keys %type_hash) {
        my $hash = $type_hash{$type};
        next SUFFIX if !scalar keys %$hash;
        my $type_key = 'ABC3_QUANTILES_' . $type;
        my $stats = $stats_class->new;
        $stats->add_data ([values %$hash]);
        foreach my $q (@QUANTILES) {
            my $hash_key = sprintf 'Q%03i', $q;
            $results{$type_key}{$hash_key} = scalar $stats->percentile($q)
        }
    }
    #  insert SET1 if it was not calculated
    if (!$type_hash{SET2}) {
        $results{ABC3_QUANTILES_SET1} = $results{ABC3_QUANTILES_ALL};
    }

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_label_count_quantile_position {
    #  needs to be clearer
    my $desc =  
        'Find the per-group percentile rank of all labels across both neighbour sets,  '
        . 'relative to the processing group. '
        . 'An absence is treated as a sample count of zero.';

    my %metadata = (
        name            => 'Rank relative sample counts per label',
        description     => $desc,
        indices         => {
            LABEL_COUNT_RANK_PCT => {
                description => q{List of percentile ranks for each label's sample count},
                type        => 'list',
            },
        },
        type            => 'Lists and Counts',
        pre_calc        => [qw /calc_element_lists_used calc_abc/],
        required_args   => ['processing_element'],
        uses_nbr_lists  => 1,
    );  

    return $metadata_class->new(\%metadata);
}

sub calc_label_count_quantile_position {
    my $self = shift;
    my %args = @_;

    my $bd = $self->get_basedata_ref;
    my $processing_element = $args{processing_element};

    my $proc_labels = $bd->get_labels_in_group_as_hash_aa ($processing_element);

    #  nbr sets might not include processing group, so make sure we get all labels
    my %labels_to_check = (%{$args{label_hash_all}}, %$proc_labels);

    #  build a hash of empty arrays
    my %label_count_arrays = map {$_ => []} keys %labels_to_check;

    my $el_array = $args{EL_LIST_ALL};

  ELEMENT:  #  don't include the processing group
    foreach my $el (grep {$_ ne $processing_element} @$el_array) {
        my $label_hash = $bd->get_labels_in_group_as_hash_aa ($el);

        foreach my $label (keys %label_count_arrays) {
            no autovivification;
            my $count = $label_hash->{$label} // 0;  # absence means zero
            my $array = $label_count_arrays{$label};
            push @$array, $count;
        }
    }

    my %positions;

  LABEL:
    foreach my $label (keys %label_count_arrays) {
        no autovivification;

        my $val_array = $label_count_arrays{$label};
        my $quant_pos;
        #  $label might not exist in the neighbours,
        #  or nbr set contains only the processing gp
        if (scalar @$val_array) {  
            my $target = $proc_labels->{$label} // 0;
            my $pos = grep { $_ < $target } @$val_array;
            $quant_pos = 100 * $pos / scalar @$val_array;
        }
        $positions{$label} = $quant_pos;
    }

    my %results = (
        LABEL_COUNT_RANK_PCT => \%positions,
    );

    return wantarray ? %results : \%results;
}


1;
