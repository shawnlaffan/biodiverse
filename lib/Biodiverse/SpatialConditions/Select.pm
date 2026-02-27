package Biodiverse::SpatialConditions::Select;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

use experimental qw /refaliasing for_list/;

use Carp;
use English qw /-no_match_vars/;

use Scalar::Util qw /looks_like_number/;
use List::Util qw /min/;

sub get_metadata_sp_select_all {
    my $self = shift;

    my %metadata = (
        description    => 'Select all elements as neighbours',
        result_type    => 'always_true',
        example        => 'sp_select_all() #  select every group',
        index_max_dist => -1,  #  search whole index if using this in a complex condition
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_all {
    return 1;    #  always returns true
}

sub get_metadata_sp_select_element {
    my $self = shift;

    my $example =<<~'END_SP_SELECT_ELEMENT'
        # match where the whole coordinate ID (element name)
        # is 'Biome1:savannah forest'
        sp_select_element (element => 'Biome1:savannah forest')
        END_SP_SELECT_ELEMENT
    ;

    my %metadata = (
        description => 'Select a specific element.  Basically the same as sp_match_text, but with optimisations enabled',
        index_max_dist => undef,

        required_args => [
            'element',  #  the element name
        ],
        optional_args => [
            'type',  #  nbr or proc to control use of nbr or processing groups
        ],
        index_no_use => 1,
        result_type  => 'always_same',
        example => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_element {
    my $self = shift;
    my %args = @_;

    delete $args{axes};  #  remove the axes arg if set

    my $comparator = $self->get_comparator_for_text_matching (%args);

    return $args{element} eq $comparator;
}

sub get_metadata_sp_select_sequence {
    my $self = shift;

    my $example = <<~'END_SEL_SEQ_EX'
        # Select every tenth group (groups are sorted alphabetically)
        sp_select_sequence (frequency => 10)

        #  Select every tenth group, starting from the third
        sp_select_sequence (frequency => 10, first_offset => 2)

        #  Select every tenth group, starting from the third last
        #  and working backwards
        sp_select_sequence (
            frequency     => 10,
            first_offset  =>  2,
            reverse_order =>  1,
        )
        END_SEL_SEQ_EX
    ;

    my %metadata = (
        description =>
            'Select a subset of all available neighbours based on a sample sequence '
                . '(note that groups are sorted south-west to north-east)',
        #  flag index dist if easy to determine
        index_max_dist => undef,
        #  frequency is how many groups apart they should be
        required_args      => [qw /frequency/],
        optional_args => [
            'first_offset',     #  the first offset, defaults to 0
            'use_cache',        #  a boolean flag, defaults to 1
            'reverse_order',    #  work from the other end
            'cycle_offset',
        ],
        index_no_use => 1,          #  turn the index off
        result_type  => 'subset',
        example      => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_sequence {
    my $self = shift;
    my %args = @_;

    my $h = $self->get_current_args;

    my $bd        = $args{caller_object} || $h->{basedata};
    my $coord_id1 = $h->{coord_id1};
    my $coord_id2 = $h->{coord_id2};

    my $verifying = $self->get_param('VERIFYING');

    my $spacing      = $args{frequency};
    my $cycle_offset = $args{cycle_offset} // 1;
    my $use_cache    = $args{use_cache} // 1;

    if ($args{clear_cache}) {
        $self->set_param(SP_SELECT_SEQUENCE_CLEAR_CACHE => 1);
    }

    my $ID                = join q{,}, @_;
    my $cache_gp_name     = 'SP_SELECT_SEQUENCE_CACHED_GROUP_LIST' . $ID;
    my $cache_nbr_name    = 'SP_SELECT_SEQUENCE_CACHED_NBRS' . $ID;
    my $cache_offset_name = 'SP_SELECT_SEQUENCE_LAST_OFFSET' . $ID;
    my $cache_last_coord_id_name = 'SP_SELECT_SEQUENCE_LAST_COORD_ID1' . $ID;

    #  inefficient - should put in metadata
    $self->set_param(NBR_CACHE_PFX => 'SP_SELECT_SEQUENCE_CACHED_NBRS');

    #  get the offset and increment if needed
    my $offset = $self->get_cached_value($cache_offset_name);

    #my $start_pos;

    my $last_coord_id1;
    if ( not defined $offset ) {
        $offset = $args{first_offset} || 0;

        #$start_pos = $offset;
    }
    else {    #  should we increment the offset?
        $last_coord_id1 = $self->get_cached_value($cache_last_coord_id_name);
        if ( defined $last_coord_id1 and $last_coord_id1 ne $coord_id1 ) {
            $offset++;
            if ( $cycle_offset and $offset >= $spacing ) {
                $offset = 0;
            }
        }
    }
    $self->set_cached_value( $cache_last_coord_id_name => $coord_id1 );
    $self->set_cached_value( $cache_offset_name        => $offset );

    my $cached_nbrs = $self->get_cached_value_dor_set_default_aa($cache_nbr_name, {});

    my $nbrs;
    if (    $use_cache
        and scalar keys %$cached_nbrs
        and exists $cached_nbrs->{$coord_id1} )
    {
        $nbrs = $cached_nbrs->{$coord_id1};
    }
    else {
        my @groups;
        my $cached_gps = $self->get_cached_value($cache_gp_name);
        if ( $use_cache and $cached_gps ) {
            @groups = @$cached_gps;
        }
        else {

            #  get in some order
            #  (should also put in a random option)

            if ( $args{reverse_order} ) {
                @groups = reverse $bd->get_groups_ref->get_element_list_sorted;
            }
            else {
                @groups = $bd->get_groups_ref->get_element_list_sorted;
            }

            if ( $use_cache and not $verifying ) {
                $self->set_cached_value( $cache_gp_name => \@groups );
            }
        }

        my $last_i = -1;
        for ( my $i = $offset; $i <= $#groups; $i += $spacing ) {
            my $ii = int $i;

            #print "$ii ";

            next if $ii == $last_i;    #  if we get spacings less than 1

            my $gp = $groups[$ii];

            #  should we skip this comparison?
            #next if ($args{ignore_after_use} and exists $cached_nbrs->{$gp});

            $nbrs->{$gp} = 1;
            $last_i = $ii;
        }

        #if ($use_cache and not $verifying) {
        if ( not $verifying ) {
            $cached_nbrs->{$coord_id1} = $nbrs;
        }
    }

    return defined $coord_id2 ? exists $nbrs->{$coord_id2} : 0;
}

#  get the list of cached nbrs - VERY BODGY needs generalising
sub get_cached_subset_nbrs {
    my $self = shift;
    my %args = @_;

    #  this sub only works for simple cases
    return
        if $self->get_result_type ne 'subset';

    my $cache_name;
    my $cache_pfx = $self->get_param('NBR_CACHE_PFX');
    #'SP_SELECT_SEQUENCE_CACHED_NBRS';    #  BODGE

    my %params = $self->get_params_hash;    #  find the cache name
    foreach my $param ( keys %params ) {
        next if not $param =~ /^$cache_pfx/;
        $cache_name = $param;
    }

    return if not defined $cache_name;

    my $cache     = $self->get_param($cache_name);
    my $sub_cache = $cache->{ $args{coord_id} };

    return wantarray ? %$sub_cache : $sub_cache;
}

sub clear_cached_subset_nbrs {
    my $self = shift;

    my $clear = $self->get_param('SP_SELECT_SEQUENCE_CLEAR_CACHE');
    return if ! $clear;

    my $cache_name;
    my $cache_pfx = 'SP_SELECT_SEQUENCE_CACHED';    #  BODGE

    my %params = $self->get_params_hash;    #  find the cache name
    foreach my $param ( keys %params ) {
        next if not $param =~ /^$cache_pfx/;
        $cache_name = $param;
        $self->delete_param ($cache_name);
    }

    return;
}


sub get_metadata_sp_select_block {
    my $self = shift;
    my %args = @_;

    my $example = <<~'END_SPSB_EX'
        # Select up to two groups per block with each block being 5 groups
        on a side where the group size is 100
        sp_select_block (size => 500, count => 2)

        #  Now do it non-randomly and start from the lower right
        sp_select_block (size => 500, count => 10, random => 0, reverse => 1)

        #  Rectangular block with user specified PRNG starting seed
        sp_select_block (size => [300, 500], count => 1, prng_seed => 454678)

        # Lower memory footprint (but longer running times for neighbour searches)
        sp_select_block (size => 500, count => 2, clear_cache => 1)
        END_SPSB_EX
    ;

    my %metadata = (
        description =>
            'Select a subset of all available neighbours based on a block sample sequence',
        #  flag index dist if easy to determine
        index_max_dist => ( looks_like_number $args{size} ? $args{size} : undef ),
        required_args      => [
            'size',           #  size of the block
        ],
        optional_args => [
            'count',          #  how many groups per block?
            'use_cache',      #  a boolean flag, defaults to 1
            'reverse_order',  #  work from the other end
            'random',         #  randomise within blocks?
            'prng_seed',      #  seed for the PRNG
        ],
        result_type  => 'complex',  #  need to make it a subset, but that part needs work
        example      => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_block {
    my $self = shift;
    my %args = @_;

    #  do stuff here
    my $h = $self->get_current_args;

    my $bd        = $args{caller_object} || $h->{basedata} || $self->get_basedata_ref;
    my $coord_id1 = $h->{coord_id1};
    my $coord_id2 = $h->{coord_id2};

    # my $verifying = $self->get_param('VERIFYING');

    my $frequency    = $args{count} // 1;
    my $size         = $args{size}; #  should be a function of cellsizes
    my $prng_seed    = $args{prng_seed};
    my $random       = $args{random} // 1;
    # my $use_cache    = $args{use_cache} // 1;

    if ($args{clear_cache}) {
        $self->set_param(SP_SELECT_BLOCK_CLEAR_CACHE => 1);
    }

    my $cache_sp_out_name   = 'SP_SELECT_BLOCK_CACHED_SP_OUT';
    my $cached_sp_list_name = 'SP_BLOCK_NBRS';

    #  generate the spatial output and get the relevant groups
    #  NEED TO USE THE PARENT DEF QUERY IF SET? Not if this is to calculate it...
    my $sp = $self->get_param ($cache_sp_out_name);
    my $prng;
    if (! $sp) {
        $sp = $self->get_spatial_output_sp_select_block (
            basedata_ref => $bd,
            size         => $size,
        );
        $self->set_param($cache_sp_out_name => $sp);
        $prng = $sp->initialise_rand(seed => $prng_seed);
        $sp->set_param(PRNG => $prng);
    }
    else {
        $prng = $sp->get_param ('PRNG');
    }

    my $nbrs = {};
    my @groups;

    if ( $sp->exists_list(list => $cached_sp_list_name, element => $coord_id1) ) {
        $nbrs = $sp->get_list_values (
            element => $coord_id1,
            list    => $cached_sp_list_name,
        );
    }
    else {
        my $these_nbrs = $sp->get_list_values (
            element => $coord_id1,
            list    => '_NBR_SET1',
        );
        my $sorted_nbrs = $sp->get_element_list_sorted(list => $these_nbrs);

        if ( $args{reverse_order} ) {
            $sorted_nbrs = [reverse @$sorted_nbrs];
        }
        if ($random) {
            $sorted_nbrs = $prng->shuffle($sorted_nbrs);
        }

        my $target = min (($frequency - 1), $#$sorted_nbrs);
        @groups = @$sorted_nbrs[0 .. $target];
        @$nbrs{@groups} = (1) x scalar @groups;

        foreach my $nbr (@$these_nbrs) {  #  cache it
            $sp->add_to_lists (
                element              => $nbr,
                $cached_sp_list_name => $nbrs,
                use_ref              => 1,
            );
        }
    }

    return defined $coord_id2 ? exists $nbrs->{$coord_id2} : 0;
}


sub get_spatial_output_sp_select_block {
    my $self = shift;
    my %args = @_;

    my $size = $args{size};

    my $bd = $args{basedata_ref} // $self->get_basedata_ref;
    my $sp = $bd->add_spatial_output (name => 'get nbrs for sp_select_block ' . time());
    $bd->delete_output(output => $sp, delete_basedata_ref => 0);

    #  add a null element to avoid some errors
    #$sp->add_element(group => 'null_group', label => 'null_label');

    my $spatial_conditions = ["sp_block (size => $size)"];

    $sp->run_analysis(
        calculations                  => [],
        override_valid_analysis_check => 1,
        spatial_conditions            => $spatial_conditions,
        #definition_query              => $definition_query,
        no_create_failed_def_query    => 1,  #  only want those that pass the def query
        calc_only_elements_to_calc    => 1,
        #basedata_ref                  => $bd,
    );

    return $sp;
}

1;