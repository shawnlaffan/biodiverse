package Biodiverse::BaseData::Exclusions;

use strict;
use warnings;
use 5.022;

our $VERSION = '5.0';

use Carp;
use Scalar::Util qw /looks_like_number blessed reftype/;
use Ref::Util qw { :all };


sub run_exclusions {
    my $self = shift;
    my %args = @_;

    croak "Cannot run exclusions on a baseData with existing outputs\n"
      if ( my @array = $self->get_output_refs );

    my $feedback =
        'The data initially fall into '
      . $self->get_group_count
      . ' groups with '
      . $self->get_label_count
      . " unique labels\n\n";

    my $orig_group_count = $self->get_group_count;

#  now we go through and delete any of the groups that are beyond our stated exclusion values
    my %exclusion_hash =
      $self->get_exclusion_hash(%args);    #  generate the exclusion hash

    $args{delete_empty_groups} //= $exclusion_hash{delete_empty_groups};
    $args{delete_empty_labels} //= $exclusion_hash{delete_empty_labels};

    #  $_[0] is $base_type_ref, $_[1] is $element
    my %test_callbacks = (
        minVariety => sub { $_[0]->get_variety( element => $_[1] ) <= $_[2] },
        maxVariety => sub { $_[0]->get_variety( element => $_[1] ) >= $_[2] },
        minSamples =>
          sub { $_[0]->get_sample_count( element => $_[1] ) <= $_[2] },
        maxSamples =>
          sub { $_[0]->get_sample_count( element => $_[1] ) >= $_[2] },
        minRedundancy =>
          sub { $_[0]->get_redundancy( element => $_[1] ) <= $_[2] },
        maxRedundancy =>
          sub { $_[0]->get_redundancy( element => $_[1] ) >= $_[2] },
    );

    my ( $label_regex, $label_regex_negate );
    if ( $exclusion_hash{LABELS}{regex} ) {
        my $re_text = $exclusion_hash{LABELS}{regex}{regex};
        my $re_modifiers = $exclusion_hash{LABELS}{regex}{modifiers} // q{};

        $label_regex        = eval qq{ qr /$re_text/$re_modifiers };
        $label_regex_negate = $exclusion_hash{LABELS}{regex}{negate};
    }

    my ( $label_check_list, $label_check_list_negate );
    if ( my $check_list = $exclusion_hash{LABELS}{element_check_list}{list} ) {
        $label_check_list = {};
        $label_check_list_negate =
          $exclusion_hash{LABELS}{element_check_list}{negate};
        if ( blessed $check_list)
        {    #  we have an object with a get_element_list method
            my $list = $check_list->get_element_list;
            @{$label_check_list}{@$list} = (1) x scalar @$list;
        }
        elsif (is_arrayref($check_list)) {
            @{$label_check_list}{@$check_list} = (1) x scalar @$check_list;
        }
        else {
            $label_check_list = $check_list;
        }
    }

    my $group_check_list;
    if ( my $definition_query = $exclusion_hash{GROUPS}{definition_query} ) {
        if ( !blessed $definition_query) {
            $definition_query =
              Biodiverse::SpatialConditions::DefQuery->new(
                conditions => $definition_query, );
        }
        my $groups        = $self->get_groups;
        my $element       = $groups->[0];
        my $defq_progress = Biodiverse::Progress->new( text => 'def query' );
        $group_check_list = $self->get_neighbours(
            element            => $element,
            spatial_conditions => $definition_query,
            is_def_query       => 1,
            progress           => $defq_progress,
        );
    }

    #  check the labels first, then the groups
    #  equivalent to range then richness
    my ( @delete_list, %tally );
    my $excluded = 0;

  BY_TYPE:
    foreach my $type ( 'LABELS', 'GROUPS' ) {

        my $other_type = $type eq 'GROUPS' ? 'LABELS' : 'GROUPS';

        my $base_type_ref = $self->{$type};

        my $cut_count     = 0;
        my $sub_cut_count = 0;
        @delete_list = ();

      BY_ELEMENT:
        foreach my $element ( $base_type_ref->get_element_list ) {

            #next if ! defined $element;  #  ALL SHOULD BE DEFINED

#  IGNORE NEXT CONDITION - sometimes we get an element called ''
#next if (not defined $element);  #  we got an empty list, so don't try anything

            my $failed_a_test = 0;

          BY_TEST:
            foreach my $test ( keys %test_callbacks ) {
                next BY_TEST if !defined $exclusion_hash{$type}{$test};

            #  old string eval approach
            #my $condition = $test_funcs{$test} . $exclusion_hash{$type}{$test};
            #my $check = eval $condition;

                my $callback = $test_callbacks{$test};
                my $chk      = $callback->(
                    $base_type_ref, $element, $exclusion_hash{$type}{$test}
                );

                next BY_TEST if !$chk;

                $failed_a_test = 1
                  ; #  if we get here we have failed a test, so drop out of the loop
                last BY_TEST;
            }

            if ( not $failed_a_test and $type eq 'LABELS' )
            {       #  label specific tests - need to generalise these
                if (
                    (
                        defined $exclusion_hash{$type}{max_range}
                        && $self->get_range( element => $element ) >=
                        $exclusion_hash{$type}{max_range}
                    )
                    || ( defined $exclusion_hash{$type}{min_range}
                        && $self->get_range( element => $element ) <=
                        $exclusion_hash{$type}{min_range} )
                  )
                {

                    $failed_a_test = 1;
                }
                if ( !$failed_a_test && $label_regex ) {
                    $failed_a_test = $element =~ $label_regex;
                    if ($label_regex_negate) {
                        $failed_a_test = !$failed_a_test;
                    }
                }
                if ( !$failed_a_test && $label_check_list ) {
                    $failed_a_test = exists $label_check_list->{$element};
                    if ($label_check_list_negate) {
                        $failed_a_test = !$failed_a_test;
                    }
                }
            }

            if ( !$failed_a_test && $type eq 'GROUPS' && $group_check_list ) {
                $failed_a_test = exists $group_check_list->{$element};
            }

            next BY_ELEMENT
              if not $failed_a_test;    #  no fails, so check next element

            $cut_count++;
            push( @delete_list, $element );
        }

        foreach my $element (@delete_list)
        {  #  having it out here means all are checked against the initial state
            $sub_cut_count += $self->delete_element(
                %args,
                type    => $type,
                element => $element,
            );
        }

        my $lctype       = lc $type;
        my $lc_othertype = lc $other_type;
        if ( $cut_count || $sub_cut_count ) {
            $feedback .= "Cut $cut_count $lctype on exclusion criteria, "
              . "deleting $sub_cut_count $lc_othertype in the process\n\n";
            $feedback .= sprintf
              "The data now fall into %d groups with %d unique labels\n\n",
              $self->get_group_count,
              $self->get_label_count;
            $tally{ $type . '_count' }       += $cut_count;
            $tally{ $other_type . '_count' } += $sub_cut_count;
            $excluded++;
        }
        else {
            $feedback .=
              "No $lctype excluded when checking $lctype criteria.\n";
        }
        print $feedback;
    }

    if ($excluded) {
        my $e_count = $self->get_param_as_ref('EXCLUSION_COUNT');
        if ( !defined $e_count ) {    #  create it if needed
            $self->set_param( EXCLUSION_COUNT => 1 );
        }
        else {                        # else increment it
            $$e_count++;
        }
    }

    #  now rebuild the index if need be
    if (    $orig_group_count != $self->get_group_count
        and $self->get_param('SPATIAL_INDEX') )
    {
        $self->rebuild_spatial_index();
    }

    $tally{feedback} = $feedback;
    return wantarray ? %tally : \%tally;
}

sub get_exclusion_hash {    #  get the exclusion_hash from the PARAMS
    my $self = shift;
    my %args = @_;

    my $exclusion_hash =
         $args{exclusion_hash}
      || $self->get_param('EXCLUSION_HASH')
      || {};

    return wantarray ? %$exclusion_hash : $exclusion_hash;
}


1;
