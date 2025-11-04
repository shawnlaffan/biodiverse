package Biodiverse::Indices::RWiBaLD;
use 5.010;
use strict;
use warnings;
use experimental qw/refaliasing declared_refs/;
use Ref::Util qw /is_hashref/;
use Carp qw/croak/;

our $VERSION = '5.0';

my $metadata_class = 'Biodiverse::Metadata::Indices';

use Statistics::Descriptive::PDL::Weighted;
my $stats_class = 'Statistics::Descriptive::PDL::Weighted';



my %rwibald_indices_metadata = (
    RWIBALD_DIFFS       => {
        description  => 'RWiBaLD scores (continuous differences)',
        type         => 'list',
        distribution => 'divergent',
    },
    RWIBALD_CODES       => {
        description  => 'RWiBaLD codes, 1=palaeo, 2=neo, 3=meso',
        type         => 'list',
        distribution => 'categorical',
        colours      => {
            0 => 'Bisque3', 3 => 'royalblue1',
            1 => 'red', 2 => 'Chartreuse4', # 'darkolivegreen',
        },
        labels       => {
            0 => 'other', 3 => 'palaeo',
            1 => 'neo', 2 => 'meso',
        },
    },
    RWIBALD_RR_DIFFS   => {
        description  => 'RWiBaLD scores for the range restricted subset (continuous differences)',
        type         => 'list',
        distribution => 'divergent',
    },
    RWIBALD_CODE_COUNTS => {
        description => 'Counts of branches in each RWiBaLD category',
        type        => 'list',
    },
    RWIBALD_METADATA    => {
        description => 'General metadata for the RWiBaLD calculations',
        type        => 'list',
    }
);


sub get_metadata_get_rwibald_global_lists {
    my %metadata = (
        name            =>  'Global RWiBaLD lists',
        description     =>  'Range weighted branch length differences for the full data set',
        type            =>  'Phylogenetic Endemism Indices',
        #  not all these precalcs are needed
        pre_calc_global => [ qw /
            get_node_range_hash
            get_trimmed_tree
            get_trimmed_tree_eq_branch_lengths_node_length_hash
        /],
        uses_nbr_lists  =>  1,  #  how many sets of lists it must have
    );

    return $metadata_class->new(\%metadata);
}

sub get_rwibald_global_lists {
    my ($self, %args) = @_;

    my $tree = $args{trimmed_tree};

    \my %orig_lengths = $tree->get_node_length_hash;
    \my %ranges       = $args{node_range};
    \my %eq_lengths   = $args{TREE_REF_EQUALISED_BRANCHES_TRIMMED_NODE_LENGTH_HASH};

    my $range_threshold = $self->get_elbow_threshold(data => [map { 1 / $_ } grep {!!$_} values %ranges]);

    #  assumes ranges are equal area and based on unit size
    my %diffs
        = map {$_ => ($orig_lengths{$_} - $eq_lengths{$_}) / $ranges{$_}}
          keys %ranges;

    #my $abs_diff_thresh = $self->get_elbow_threshold(data => [map {abs $_} values %diffs], log => 0);
    # my $pos_threshold =  $abs_diff_thresh;
    # my $neg_threshold = -$abs_diff_thresh;

    my $pos_threshold = $self->get_elbow_threshold(data => [grep {$_ >= 0} values %diffs]);
    my $neg_threshold = $self->get_elbow_threshold(data => [grep {$_ <= 0} values %diffs]);

    my (%coded, %rwibald_diffs, %non_rwibald_diffs);

    foreach my $key (keys %diffs) {
        my $diff = $diffs{$key};
        if ((1 / $ranges{$key}) >= $range_threshold) {
            $rwibald_diffs{$key} = $diff;
            $coded{$key}
                = $diff <= $neg_threshold   ? 1  #  neo
                : $diff >= $pos_threshold   ? 3  #  palaeo
                : 2;                             #  meso
        }
        else {
            $non_rwibald_diffs{$key} = $diff;
            $coded{$key} = 0;
        }
    }

    # my $p = grep {$_ == 3} values %coded;
    # my $n = grep {$_ == 1} values %coded;
    # my $m = grep {$_ == 2} values %coded;
    # say "Neo:    $n\nMeso:   $m\nPalaeo: $p";

    my %results = (
        RWIBALD_DIFF_HASH_GLOBAL    => \%rwibald_diffs,
        NONRWIBALD_DIFF_HASH_GLOBAL => \%non_rwibald_diffs,
        RWIBALD_CODES_GLOBAL        => \%coded,
        RWIBALD_METADATA            => {
            range_thresh   => $range_threshold,
            neg_len_thresh => $neg_threshold,
            pos_len_thresh => $pos_threshold,
        }
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_rwibald {

    my $ref = 'Mishler et al. (in review)';

    my %metadata = (
        name            =>  'RWiBaLD',
        description     =>
              "Range weighted branch length differences.\n"
            . "Values are spatially constant, only the subsets change",
        type            =>  'Phylogenetic Endemism Indices',
        pre_calc        =>  [qw /calc_pd_node_list/],
        pre_calc_global =>  [qw /get_rwibald_global_lists/],
        uses_nbr_lists  =>  1,  #  how many sets of lists it must have
        indices         => {
            %rwibald_indices_metadata
        },
        reference       => $ref,
    );

    return $metadata_class->new(\%metadata);
}

sub calc_rwibald {
    my ($self, %args) = @_;

    \my %labels               = $args{PD_INCLUDED_NODE_LIST};
    \my %rwibald_codes_global = $args{RWIBALD_CODES_GLOBAL};
    \my %rwibald_diffs_global = $args{RWIBALD_DIFF_HASH_GLOBAL};
    \my %non_rwibald_diffs_global = $args{NONRWIBALD_DIFF_HASH_GLOBAL};

    #  just slice the global hash
    my %rwibald_codes = %rwibald_codes_global{keys %labels};
    my %rwibald_rr_diffs = %rwibald_diffs_global{keys %labels};
    my %rwibald_diffs
        = map {$_ => ($rwibald_diffs_global{$_} // $non_rwibald_diffs_global{$_})}
          keys %labels;

    my %counts;
    @counts{0..3} = (0) x 4;

    foreach my $code (values %rwibald_codes) {
        $counts{$code}++;
    }

    my %results = (
        RWIBALD_CODES       => \%rwibald_codes,
        RWIBALD_DIFFS       => \%rwibald_diffs,
        RWIBALD_RR_DIFFS    => \%rwibald_rr_diffs,
        RWIBALD_CODE_COUNTS => \%counts,
        RWIBALD_METADATA    => $args{RWIBALD_METADATA},
    );

    return wantarray ? %results : \%results;
}



sub get_elbow_threshold {
    my ($self, %args) = @_;

    use PDL::Lite;

    my $data = $args{data};
    if (is_hashref ($data)) {
        $data = [sort { $a <=> $b } values %$data];
    }
    else {
        $data = [ sort { $a <=> $b } @$data ];
    }

    croak "data is empty"
        if !@$data;

    my $x_coords = pdl( 0 .. $#$data );
    my $y_coords = pdl $data;

    if ($args{log}) {
        $y_coords->inplace->abs->log;
    }
# say $y_coords;
    #  first points
    my $x1 = 0;
    my $y1 = $y_coords->at(0);

    # normalize the line vector
    my $x_vec     = $x_coords - $x1;
    my $y_vec     = $y_coords - $y1;
    my $x_vec_max = $x_vec->at(-1);
    my $y_vec_max = $y_vec->at(-1);

    my $normaliser = sqrt( $x_vec_max**2 + $y_vec_max**2 );

    $x_vec_max = $x_vec_max / $normaliser;
    $y_vec_max = $y_vec_max / $normaliser;

    #  vectors from first point
    my $v_x = $x_coords - $x1;
    my $v_y = $y_coords - $y1;

    my $scalar_prod = $v_x * $x_vec_max + $v_y * $y_vec_max;

    my $vec_to_line_x = $v_x - $scalar_prod * $x_vec_max;
    my $vec_to_line_y = $v_y - $scalar_prod * $y_vec_max;

    # distance to line is the norm
    my $dist_to_line = sqrt( $vec_to_line_x**2 + $vec_to_line_y**2 );

    my $elbow_idx = PDL::which( $dist_to_line == $dist_to_line->max )->at(0);

    my $elbow = $data->[$elbow_idx];
    return $elbow;
}




1;
