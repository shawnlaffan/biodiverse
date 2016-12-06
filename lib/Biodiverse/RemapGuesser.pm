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
use Biodiverse::Progress;

our $VERSION = '1.99_006';

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

# given a remap hash and a data source, actually performs the remap.
sub perform_auto_remap {
    my ( $self, %args ) = @_;

    my $remap_hash  = $args{remap};
    my $data_source = $args{new_source};

    $data_source->remap_labels_from_hash( remap => $remap_hash );
    return;
}

# takes a two references to trees/matrices/basedata and tries to map
# the first one to the second one.
sub generate_auto_remap {
    my $self          = shift;
    my $args          = shift || {};
    my $first_source  = $args->{existing_data_source};
    my $second_source = $args->{new_data_source};
    my $max_distance  = $args->{max_distance};
    my $ignore_case   = $args->{ignore_case};

    my @existing_labels = $first_source->get_labels();
    my @new_labels      = $second_source->get_labels();

    my $remap_results = $self->guess_remap(
        {
            existing_labels => \@existing_labels,
            new_labels      => \@new_labels,
            max_distance    => $max_distance,
            ignore_case     => $ignore_case,
        }
    );

    my $remap = $remap_results->{remap};


    my %results = (
        remap         => $remap,
        exact_matches => $remap_results->{exact_matches},
        punct_matches => $remap_results->{punct_matches},
        typo_matches  => $remap_results->{typo_matches},
        not_matched   => $remap_results->{not_matched},
    );

    return wantarray ? %results : \%results;
}


# takes a string, returns it with non word/digit characters replaced
# by underscores. args{ignore_case} controls whether case counts as
# 'punctuation'
sub no_punct {
    my ( $self, %args ) = @_;
    my $str = $args{str};

    if ( $args{ignore_case} ) {
        $str = lc($str);
    }

    $str =~ s/^['"]//;
    $str =~ s/['"]$//;
    $str =~ s/[^\d\w]//g;
    $str =~ s/[\_]//g;

    return $str;
}

# takes in two references to arrays of labels (existing_labels and new_labels)
# returns a hash mapping labels in the second list to labels in the first list
sub guess_remap {
    my $self = shift;
    my $args = shift || {};

    my @target_labels = sort @{ $args->{existing_labels} };
    my @from_labels   = sort @{ $args->{new_labels} };

    my $ignore_case = $args->{ignore_case};

    my %remap;
    
    my $progress = Biodiverse::Progress->new();

    ################################################################
    # step 1: find exact matches
    my @unprocessed_from_labels;
    my @exact_matches;
    my %target_labels_hash;
    @target_labels_hash{@target_labels} = undef;  # only need the keys

    my $progress_i = 0;
    my $n = scalar @from_labels;

    foreach my $from_label (@from_labels) {
        $progress_i ++;
        $progress->update ("Finding exact matches among $n entries", $progress_i / $n);

        if ( exists $target_labels_hash{$from_label} ) {
            $remap{$from_label} = $from_label;
            push @exact_matches, $from_label;
            delete $target_labels_hash{$from_label};
        }
        else {
            push @unprocessed_from_labels, $from_label;
        }
    }

    @from_labels = @unprocessed_from_labels;


    ################################################################
    # step 2: find punctuation-less matches e.g. a:b matches a_b
    # currently exempt from checking for the max distance

    # build the hash mapping punctuation-less existing labels to their
    # original value.
    my %no_punct_hash;
    foreach my $label (keys %target_labels_hash) {
        my $key = $self->no_punct(
            str => $label,
            ignore_case => $ignore_case,
        );
        $no_punct_hash{$key} = $label;
    }

    #say "no_punct_hash keys: ", keys %no_punct_hash;

    # look for no punct matches for each of the unmatched new labels
    my @punct_matches;
    @unprocessed_from_labels = ();
    my %existing_labels_that_got_matched;

    $progress_i = 0;
    $n = scalar @from_labels;
    foreach my $from_label (@from_labels) {
        $progress_i++;
        $progress->update ("Finding punctuation matches from $n labels", $progress_i / $n);

        my $key = $self->no_punct (
            str         => $from_label,
            ignore_case => $ignore_case,
        );
        #say "Looking in the no_punct_hash for $from_label";
        if (exists $no_punct_hash{$key}) {
            #say "Found it in there";
            $remap{$from_label} = $no_punct_hash{$key};
            push @punct_matches, $from_label;

            $existing_labels_that_got_matched{$key} = 1;
            delete $target_labels_hash{$key};
        }
        else {
            #say "Couldn't find it in there";
            push @unprocessed_from_labels, $from_label;
        }
    }

    

    ################################################################
    # step 3: edit distance based matching (try to catch typos).  For
    # each of the as yet unmatched new labels, find the closest match
    # in the old labels. If it is under the threshold, add it as a
    # match.

    my $max_distance = $args->{max_distance};
    my @typo_matches;
    my %ambiguous_matches;

    if ($max_distance) {
        @from_labels = @unprocessed_from_labels;
        @unprocessed_from_labels = ();

        $progress_i = 0;
        $n = scalar @from_labels;

        foreach my $from_label (@from_labels) {
            $progress_i++;
            $progress->update ("Distance matching $n labels", $progress_i / $n);
    
            my $min_distance = $max_distance;
            my @poss_matches;
    
            foreach my $target_label (keys %target_labels_hash) {
                my $distance = distance( $from_label, $target_label );
                next if $distance > $min_distance;
                my $subset = $poss_matches[$distance] //= [];
                push @$subset, $target_label;
                $min_distance = $distance;
            }
    
            my $match_subset = $poss_matches[$min_distance] // [];
    
            if ( scalar @$match_subset == 1) {
                my $min_label = $match_subset->[0];
    
                # we found a legitimate, unambiguous match
                $remap{$from_label} = $min_label;
    
                # for now, don't delete the match from existing labels,
                # because if we're trying to catch typos, there might be
                # multiple 'labels' (really typos) in the new data that
                # need to be remapped to the same label in the existing
                # data.
    
                push @typo_matches, $from_label;
            }
            else {
                if ( scalar @$match_subset > 1) {
                    $ambiguous_matches{$from_label} = $match_subset;
                }
                push @unprocessed_from_labels, $from_label;
            }
        }
    }

    #######################
    # There may be some 'not matched' strings which will cause
    # problems if they don't have a corresponding remap hash entry.
    # put them in the hash.
    @remap{@unprocessed_from_labels} = @unprocessed_from_labels;


    my %results = (
        remap         => \%remap,
        exact_matches => \@exact_matches,
        punct_matches => \@punct_matches,
        typo_matches  => \@typo_matches,
        not_matched   => \@unprocessed_from_labels,
        ambiguous_matches => \%ambiguous_matches,
    );

    return wantarray ? %results : \%results;
}


=pod

=head1 NAME

Biodiverse::RemapGuesser

=head1 SYNOPSIS

Generate remappings between slightly different sets of
strings. (e.g. labels for a newly imported tree and existing
basedata).

=head1 DESCRIPTION

There are four stages of matching. After each stage, any string that
was matched is removed. The next step runs only on the remaining
unmatched strings. 

The first stage looks for exact matches between the two sets of
strings. The second stage looks for strings differing only by
punctuation. This is done by removing all punctuation and finding
exact matches in this 'punctuation-less' state. The third stage looks
for matches which are within a specified edit distance. For example,
if the edit distance specified was 1, then Tyypo would match Typo but
not Tyyypo. The fourth and final stage places all remaining unmatched
labels into the 'not matched category'.

=head1 METHODS

=over

=item C<new>

Standard constructor for the RemapGuesser class.

=item C<perform_auto_remap>

Given a hash and a 'data source' (anything which implements
C<remap_labels_from_hash>, normally a C<BaseData>, C<Tree> or
C<Matrix>). The hash maps from the names of labels already in the data
source to the desired new label names. The data source's labels are
renamed according to the hash. e.g. The hash might contain Genus_sp1
=> GenusSp1. If there is a label named Genus_sp1 in the data source,
it will be renamed to GenusSp1.

=item C<generate_auto_remap>

Given two data sources (anything implementing C<get_labels()>), and a
number of configuration options, generates a hash mapping the labels
of one data source to the other. 

The C<first_source> argument is mapped to the C<second_source>
argument. The C<max_distance> argument controls the maximum acceptable
edit distance for two labels to be regarded as a match. (see class
description for explanation of matching process). The C<ignore_case>
argument specifying whether case is treated as punctuation. For
example, if this is true, GenusSp will match genussp in the
punctuation stage. This avoids the edit distance requirement which
would prevent case errors from being matched.

C<generate_auto_remap> returns a hash. C<remap> is a hash specifying
the complete mapping that was found. This can be passed into
C<perform_auto_remap> to actually carry out a remap. C<exact_matches>,
C<punct_matches>, C<typo_matches> and C<not_matched> are lists of
labels which were matched in the four stages of matching. (see class
description).

=item C<no_punct>

Given a string (C<args{str}>), returns it with no
punctuation. Anything outside the Perl \d and \w classes are
removed. Additionally, quotes and underscores are removed. If
C<args{ignore_case}> is true, the string is also converted to
lowercase.

=item C<guess_remap>

Given two lists of strings, generates a remap hash from the first to
the second using the four stage process described in the class
description section. Usually outside callers should use
generate_auto_remap instead of calling this function directly.

=back

=head1 REPORTING ERRORS

Use the issue tracker at http://www.purl.org/biodiverse

=head1 COPYRIGHT

Copyright (c) 2010 Shawn Laffan. All rights reserved.  

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut




1;
