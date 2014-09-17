package Biodiverse::Indices::LabelCounts;

use strict;
use warnings;

our $VERSION = '0.99_004';

use Biodiverse::Statistics;

my $stats_class    = 'Biodiverse::Statistics';
my $metadata_class = 'Biodiverse::Metadata::Indices';


my @quantiles;
for my $i (0 .. 100) {
    next if $i % 5;
    push @quantiles, $i;
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
        SET1 => $label_hash1,
        SET2 => $label_hash2,
    );

  SUFFIX:
    foreach my $type (keys %type_hash) {
        my $hash = $type_hash{$type};
        next SUFFIX if ! scalar keys %$hash;
        my $type_key = 'ABC3_QUANTILES_' . $type;
        my $stats = $stats_class->new;
        $stats->add_data (values %$hash);
        foreach my $q (@quantiles) {
            my $hash_key = sprintf 'Q%03i', $q;
            $results{$type_key}{$hash_key} = scalar $stats->percentile($q)
        }
    }

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_label_count_quantile_position {
    my $desc =
        'Find the percentile rank of each label in the processing group '
      . 'across the respective label counts across both neighbour sets.  '
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
        pre_calc        => 'calc_element_lists_used',
        required_args   => ['processing_element'],
        uses_nbr_lists  => 1,
    );  

    return $metadata_class->new(\%metadata);
}

sub calc_label_count_quantile_position {
    my $self = shift;
    my %args = @_;

    my $bd = $self->get_basedata_ref;
    my $element = $args{processing_element};

    my $proc_labels = $bd->get_labels_in_group_as_hash (group => $element);

    my %label_counts;
    foreach my $label (keys %$proc_labels) {
        $label_counts{$label} = [];
    }
    my $el_array = $args{EL_LIST_ALL};

  ELEMENT:
    foreach my $el (@$el_array) {
        next ELEMENT if $el eq $element;  #  don't include ourselves

        my $label_hash = $bd->get_labels_in_group_as_hash (group => $el);
      LABEL:
        foreach my $label (keys %label_counts) {
            no autovivification;
            my $count = $label_hash->{$label} // 0;  # absence means zero
            my $array = $label_counts{$label};
            push @$array, $count;
        }
    }

    my %positions;

  LABEL:
    foreach my $label (keys %label_counts) {
        my $val_array = $label_counts{$label};
        my $quant_pos;
        if (scalar @$val_array) {  #  $label might not exist in the neighbours - can this happen since we assume zero?
            my $target = $proc_labels->{$label};
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
