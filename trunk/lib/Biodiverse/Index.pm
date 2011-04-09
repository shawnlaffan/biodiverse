package Biodiverse::Index;

#########################
#
#   ADAPTED FROM Sirca::Index, which was adapted from an older version of this file

#  a package to implement an indexing scheme for a Biodiverse::BaseData object.
#  this will normally be stored with each BaseStruct object that needs it, thus allowing multiple
#  indexes for a single BaseData object.
#  currently only indexes numeric fields - text fields are lumped into a single subindex.

#  NOTE:  it may be better to implement this using Tree:Simple or similar,
#         but I haven't nutted out how to use it most effectively.

#  This approach is not as flexible as it could be.  A pyramid structure may be better.
#
#  Need to add a multiplier to the index so it has at least some prespecified
#    significant digits - use the min and max to assess this

use strict;
use warnings;
use Carp;
use Biodiverse::Progress;

use Scalar::Util qw /blessed/;

our $VERSION = '0.16';

#use List::Util;
use POSIX qw /fmod ceil/;

#use base qw /Biodiverse::BaseData/;  #  CHEATING MOST HEINOUSLY WITH THE BASEDATA USE - need to put all distance stuff into spatialparams.pm
#use base qw /Sirca::Utilities/;
use base qw /Biodiverse::Common/;

#our %PARAMS = (JOIN_CHAR => ":",
#               QUOTES => "'"
#               );


sub new {
    my $class = shift;

    my %args = @_;
    #my %uc_args;
    #foreach my $key (keys %args) {  #  upper case them
    #    $uc_args{uc($key)} = $args{$key};
    #}
    
    #my $self = {};
    my $self = bless {}, $class;

    my %PARAMS = (
        JOIN_CHAR => q{:},
        QUOTES    => q{'},
    );
    $self -> set_param (%PARAMS);  #  set the defaults
    
    my $csv_object = $self -> get_csv_object (
        sep_char   => $self -> get_param ('JOIN_CHAR'),
        quote_char => $self -> get_param ('QUOTES'),
    );
    $self -> set_param (CSV_OBJECT => $csv_object);
    
    #my $parent = $self -> get_param ('PARENT') || confess "parent not specified\n";
    #$self -> weaken_param ('PARENT');  #  must weaken this
    
    $self -> build (@_);

    return $self;
}


sub build {
    my $self = shift;
    my %args = @_;
    
    #  what is the index resolution to be?
    my $resolutions = $args{resolutions} || croak "Index 'resolutions' not specified\n";
    my @resolutions = @$resolutions;
    foreach my $i (0 .. $#resolutions) {
        $resolutions[$i] = 0 if $resolutions[$i] < 0;  #  no negatives
    }
    
    print "[INDEX] Building index for resolution ", join (",", @resolutions), "\n";
    
    $self -> set_param (RESOLUTIONS => \@resolutions);
    
    #  this should be a ref to a hash with all the element IDs as keys and their coord arrays as values
    my $element_hash = $args{element_hash} || croak "Argument element_hash not specified\n";

    #  are we dealing with blessed objects or just coord array refs?  
    my @keys = keys %$element_hash;  #  will blow up if not a hash ref
    my $blessed = blessed $element_hash->{$keys[0]};

    #  get the bounds and the list of unique element columns
    my (%count, %bounds, %ihash);
    
    #  get the coord bounds
    foreach my $element (@keys) {

        my $coord_array     #  will blow up if no such method
            = eval {$element_hash->{$element} -> get_coord_array}  
            || $element_hash->{$element};

        foreach my $i (0 .. $#resolutions) {
            #print "COLUMNS: $column, $i\n";
            $ihash{$i}++;
            $count{$i}{$coord_array->[$i]}++;
            if ($resolutions[$i] == 0) {
                $bounds{max}[$i] = 0;
                $bounds{min}[$i] = 0;
            }
            elsif (not defined $bounds{max}[$i]) {  #  first use - initiate it (otherwise negative coords cause trouble)
                $bounds{max}[$i] = $coord_array->[$i];
                $bounds{min}[$i] = $coord_array->[$i];
            }
            else {
                $bounds{max}[$i] = $coord_array->[$i] if $coord_array->[$i] > $bounds{max}[$i];
                $bounds{min}[$i] = $coord_array->[$i] if $coord_array->[$i] < $bounds{min}[$i];
            }
        }
        
        #  and now we allocate this elements to the index hash
        my $index_key = $self -> snap_to_index (element_array => $coord_array);
        $self->{ELEMENTS}{$index_key}{$element} = $coord_array;
    }    
    
    #  and finally we calculate the minima and maxima for each index axis
    #  a value of undef indicates no indexing
    my (@minima, @maxima);
    foreach my $i (0 .. $#resolutions) {
        if ($resolutions[$i] > 0) {
            push (@minima, $bounds{min}[$i] - fmod ($bounds{min}[$i], $resolutions[$i]));
            push (@maxima, $bounds{max}[$i] - fmod ($bounds{max}[$i], $resolutions[$i]));
        }
        else {
            push (@minima, 0);
            push (@maxima, 0);
        }
    }

    $self -> set_param(MAXIMA => \@maxima);
    $self -> set_param(MINIMA => \@minima);

    print "[INDEX] Index bounds are: Max=[", join (", ", @maxima), "], Min=[", join (", ", @minima), "]\n";

    return;
}


sub snap_to_index {
    my $self = shift;
    my %args = @_;
    my $element_array = $args{element_array} || croak "element_array not specified\n";
    (ref ($element_array)) =~ /ARRAY/ || croak "element_array is not an array ref\n";

    my @columns = @$element_array;
    my @index_res = @{$self -> get_param('RESOLUTIONS')};

    my @index;
    foreach my $i (0 .. $#columns) {
        my $indexValue = 0;
        if ($index_res[$i] > 0) {  #  should update to avoid fmod
            $indexValue = $columns[$i] - fmod ($columns[$i], $index_res[$i]);
            $indexValue += $index_res[$i] if $columns[$i] < 0;
        }
        else {
            $indexValue = 0;
        }
        push @index, $indexValue;
    }

    if ($args{as_array}) {
        return wantarray ? @index : \@index;
    }

    my $csv_object = $self -> get_param ('CSV_OBJECT');
    #  this for backwards compatibility, as pre 0.10 versions didn't have this cached
    if (not defined $csv_object) {
        my $sep = $self -> get_param('JOIN_CHAR');
        my $quotes = $self -> get_param('QUOTES');
        $csv_object = $self -> get_csv_object (
            sep_char   => $sep,
            quote_char => $quotes
        );
    }

    my $index_key = $self -> list2csv (list => \@index, csv_object => $csv_object);

    return wantarray ? (index => $index_key) : $index_key;
}

sub delete_from_index {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};

    my $index_key = $self -> snap_to_index (@_);

    return if ! exists $self->{$index_key};

    $self->{ELEMENTS}{$index_key}{$element} = undef;  # free any refs
    delete $self->{ELEMENTS}{$index_key}{$element};

    #  clear this index key if it is empty
    if (keys %{$self->{ELEMENTS}{$index_key}} == 0) {
        delete $self->{ELEMENTS}{$index_key};
    }

    return;    
}

sub get_index_keys {
    my $self = shift;
    return wantarray ? keys %{$self->{ELEMENTS}} : [keys %{$self->{ELEMENTS}}];
}


sub element_exists {
    my $self = shift;
    my %args = @_;
    croak "Argument 'element' missing\n" if ! defined $args{element};
    return exists $self->{ELEMENTS}{$args{element}};
}

sub get_index_elements {
    my $self = shift;
    my %args = @_;
    if (! defined $args{element}) {
        croak "Argument 'element' not defined in call to get_index_elements\n";
    }
    if (defined $args{offset}) {  #  we have been given an index element with an offset, so return the elements from the offset
        #my $sep = $self -> get_param('JOIN_CHAR');
        #my $quotes = $self -> get_param('QUOTES');
        #
        #my $csv_object = $self -> get_csv_object (sep_char => $sep, quote_char => $quotes);
        
        my $csv_object = $self -> get_param ('CSV_OBJECT');
        #  this for backwards compatibility, as pre 0.10 versions didn't have this cached
        if (not defined $csv_object) {
            my $sep = $self -> get_param('JOIN_CHAR');
            my $quotes = $self -> get_param('QUOTES');
            $csv_object = $self -> get_csv_object (
                sep_char   => $sep,
                quote_char => $quotes,
            );
        }

        my @elements = ((ref $args{element}) =~ /ARRAY/)  #  is it an array already?
                        ? @{$args{element}}
                        : $self -> csv2list (string => $args{element}, csv_object => $csv_object)
                        ;
        my @offsets = ((ref $args{offset}) =~ /ARRAY/)  #  is it also an array already?
                        ? @{$args{offset}}
                        : $self -> csv2list (string => $args{offset}, csv_object => $csv_object)
                        ;
        for (my $i = 0; $i <= $#elements; $i++) {
            $elements[$i] += $offsets[$i];
        }
        $args{element} = $self -> list2csv(list => \@elements, csv_object => $csv_object);
    }
    
    if (! $self -> element_exists (element => $args{element})) {  #  check after any offset is applied
        return wantarray ? () : {}
    }
    return wantarray
            ? %{$self->{ELEMENTS}{$args{element}}}
            : $self->{ELEMENTS}{$args{element}};
}

sub get_index_elements_as_array {
    my $self = shift;
    my $tmpRef = $self -> get_index_elements (@_);
    return wantarray ? keys %{$tmpRef} : [keys %{$tmpRef}];
}

#  snap a set of coords (or a single value) to the index
#  devised for predict_offsets but likely to have other uses
sub round_up_to_resolution {
    my $self = shift;
    my %args = @_;
    
    my $resolutions = $self -> get_param('RESOLUTIONS');
    
    my $values = $args{values};
    #  if not an array then make it one
    #  woe betide the soul who passes a hash...
    if ((ref $values) !~ /ARRAY/) {  
        $values = [($values) x scalar @$resolutions];
    }
    
    my $multipliers = $args{multipliers};
    $multipliers = 1 if not defined $multipliers;
    if ((ref $multipliers) !~ /ARRAY/) {  
        $multipliers = [($multipliers) x scalar @$resolutions];
    }
    
    foreach my $i (0 .. $#$values) {
        my $val = $values->[$i] * $multipliers->[$i];
        if ($resolutions->[$i] and $val > $resolutions->[$i]) {
            $val = $resolutions->[$i] * ceil ($val / $resolutions->[$i]);
        }
        else {
            $val = $resolutions->[$i];
        }
        $values->[$i] = $val;
    }
    
    return wantarray ? @$values : $values;
}

    
sub predict_offsets {  #  predict the maximum spatial distances needed to search based on the index entries
    my $self = shift;
    my %args = @_;
    if (! $args{spatial_params}) {
        croak "[INDEX] No spatial params object specified in predict_distances\n";
    }
    
    my $progress_text_pfx = $args{progress_text_pfx} || q{};
    
    #  Derive the full parameter set.  We may not need it, but just in case...
    #  (and it doesn't take overly long)
    #  should add it as an argument
    
    my $spatial_params = $args{spatial_params};
    my $conditions = $spatial_params -> get_conditions_unparsed();
    $self -> update_log (text => "[INDEX] PREDICTING SPATIAL INDEX NEIGHBOURS\n$conditions\n");
    

    my $csv_object = $self -> get_param ('CSV_OBJECT');
    #  this for backwards compatibility, as pre 0.10 versions didn't have this cached
    if (not defined $csv_object) {
        my $sep = $self -> get_param('JOIN_CHAR');
        my $quotes = $self -> get_param('QUOTES');
        $csv_object = $self -> get_csv_object (
            sep_char => $sep,
            quote_char => $quotes
        );
    }

    
    my $index_resolutions = $self -> get_param('RESOLUTIONS');
    my $minima = $self -> get_param('MINIMA');
    my $maxima = $self -> get_param('MAXIMA');
    my $cellsizes = $args{cellsizes};  #  needs to be passed if used
    my $poss_elements_ref;
    
    #  get the decimal precision of the index resolution (we get floating point to string problems lower down)
    #  also generate an array of the index ranges
    my @ranges;
    my @index_res_precision;
    foreach my $i (0 .. $#$minima) {
        $ranges[$i] = $maxima->[$i] - $minima->[$i];
        $index_resolutions->[$i] =~  /^(\d*\.){1}(\d*)/;  #  match after decimal will be $2
        my $decimal_len = length (defined $2 ? $2 : q{});
        $index_res_precision[$i] = "%.$decimal_len" . "f";  #  count the numbers at the end after the decimal place
    }
    
    my $subset_search_offsets;
    my $use_subset_search = $args{index_use_subset_search};
    my $using_cell_units = undef;
    my $subset_dist = $args{index_search_dist};
    #  insert a shortcut for no neighbours
    if ($spatial_params -> get_result_type eq 'self_only') {
        my $offsets = $self -> list2csv (
            list       => [0 x scalar @$index_resolutions],  #  all zeroes
            csv_object => $csv_object,
        );
        my %valid_offsets = ($offsets => $offsets);
        print "Done (and what's more I cheated)\n";
        return wantarray ? %valid_offsets : \%valid_offsets;
    }

    #elsif (my $i_dist = $spatial_params -> get_index_max_dist) {
    if (my $i_dist = $spatial_params -> get_index_max_dist) {
        print "[INDEX] Max search dist is $i_dist - using shortcut\n";
        $use_subset_search = 1;
        my $max_off = $self -> round_up_to_resolution (values => $i_dist);
        my $min_off = [];
        foreach my $i (0 .. $#$max_off) {
            #  snap to range of data - avoids crashes
            my $range = $maxima->[$i] - $minima->[$i];
            if ($max_off->[$i] > $range) {
                $max_off->[$i] = $range;
            }
            # minima will be the negated max, so we can get ranges like -2..2.
            $min_off->[$i] = -1 * $max_off->[$i];
        }
        my $offsets = $self -> get_poss_elements (
            minima      => $min_off,
            maxima      => $max_off,
            resolutions => $index_resolutions,
            precision   => \@index_res_precision,
        );
        my %offsets;
        @offsets{@$offsets} = @$offsets;
        return wantarray ? %offsets : \%offsets;
    }
    
    
    #  Build all possible index elements by default, as not all will exist for non-square data sets (most data sets)
    $poss_elements_ref = $self -> get_poss_elements (
        minima      => $minima,
        maxima      => $maxima,
        resolutions => $index_resolutions,
        precision   => \@index_res_precision,
    );


    #  generate the extrema
    my $extreme_elements_ref = $self -> get_poss_elements (
        minima      => $minima,
        maxima      => $maxima,
        resolutions => \@ranges,
        precision   => \@index_res_precision,
    );
    
    
    #  now we grab the first order neighbours around each of the extrema
    #  these will be used to check the index offsets
    #  (neighbours are needed to ensure we get all possible values)
    my %element_search_list;
    my %element_search_arrays;
    my %index_elements_to_search;
    my $total_elements_to_search;
    my $corner_case_count = 0;
    foreach my $element (@$extreme_elements_ref) {
        my $element_array = $self -> csv2list (
            string     => $element,
            csv_object => $csv_object,
        );
        my $nbrsRef = $self -> get_surrounding_elements (
            coord       => $element_array,
            resolutions => $index_resolutions,
            precision   => \@index_res_precision,
        );

        $element_search_list{$element} = $nbrsRef;
        $element_search_arrays{$element} = $element_array;

        if ($use_subset_search) {  #  only want to search a few nearby index cells
            #  do we want to go up or down?
            my @target;
            
            my $i = 0;
            foreach my $axis (@$element_array) {
                
                if ($axis == $minima->[$i]) {
                    $target[$i] = $minima->[$i] + $subset_search_offsets->[$i] + $index_resolutions->[$i];
                }
                else {
                    $target[$i] = $maxima->[$i] - $subset_search_offsets->[$i] - $index_resolutions->[$i];
                }
                $i++;
            }
            
            my $x = $self -> get_poss_elements (
                minima => $element_array,
                maxima => \@target,
                resolutions => $index_resolutions,
                precision => \@index_res_precision,
            );
            $index_elements_to_search{$element} = $x;
        }
        else {
            $index_elements_to_search{$element} = $poss_elements_ref;
        }
        
        $total_elements_to_search += scalar @$nbrsRef;
        $corner_case_count ++;
    }
  
    #  loop through each permutation of the index resolutions, dropping those
    #    that cannot fit into our neighbourhood
    #  this allows us to define an offset distance to search in the up and down directions
    #    (assuming the index is equal interval)
    #  start from each corner and search inwards to assess the index elements we need to search
    #  works from the eight neighbours of each corner to ensure we allow for data elements near the index boundaries.
    #  Keeps a track of those offsets that have already passed so it does not need to check them again.
    my %valid_index_offsets;
    my %offsets_checked;
    my (@min_offset, @max_offset);
    
    my $progress_bar = Biodiverse::Progress->new();
    my $to_do = $total_elements_to_search;
    my $resolutions_text = join (q{ }, @{$self -> get_param ('RESOLUTIONS')});
    my ($count, $printedProgress) = (0, -1);
    my %index_element_arrays;  #  keep a cache of the arrays to save converting them
    print "[INDEX] Case of $to_do: ";
    
    foreach my $extreme_element (keys %element_search_list) {  #  loop over the corner cases
        
        my $extreme_ref = $element_search_arrays{$extreme_element};
        
        #  loop over the 3x3 nbrs of the extreme element
        foreach my $check_element (@{$element_search_list{$extreme_element}}) {  
            my $check_ref;
            if (defined $index_element_arrays{$check_element}) {
                $check_ref = $index_element_arrays{$check_element};
            }
            else {
                $check_ref = $self -> csv2list(
                    string     => $check_element,
                    csv_object => $csv_object,
                );
                $index_element_arrays{$check_element} = $check_ref;  #  store it
            }

            #  update progress to GUI
            $count ++;
            #print "$count ";
            #if ($progress_bar) {
                my $progress = int (100 * $count / $to_do);
                my $p_text =   "$progress_text_pfx\n"
                             . "Predicting index offsets based on $corner_case_count corner cases " 
                             . "and their first order nbrs\n(index resolution: $resolutions_text)\n"
                             . ($count / $to_do);
                $progress_bar -> update ($p_text, $progress / 100) ;
            #}

            COMPARE: foreach my $element (@{$index_elements_to_search{$extreme_element}}) {
                #  evaluate current check element against the search nbrs for their related extreme element
                #   to see if they pass the conditions

                #  get it as an array ref
                my $element_ref;
                if (defined $index_element_arrays{$element}) {
                    $element_ref  = $index_element_arrays{$element};
                }
                else {
                    $element_ref = $self -> csv2list (
                        string => $element,
                        csv_object => $csv_object,
                    );
                    $index_element_arrays{$element} = $element_ref;  #  store it
                }

                #  get the correct offset (we are assessing the corners of the one we want)
                # need to snap to precision of the original index
                # or we get floating point difference problems
                my @list;
                foreach my $i (0 .. $#$extreme_ref) {
                    #push @list, sprintf ($index_res_precision[$i], $element_ref->[$i] - $extreme_ref->[$i]) + 0;
                    push @list,
                        0
                        + $self -> set_precision (
                            precision => $index_res_precision[$i],
                            value     => $element_ref->[$i] - $extreme_ref->[$i],
                        );
                }
                my $offsets = $self -> list2csv (
                    list        => \@list,
                    csv_object  => $csv_object,
                );
                
                $offsets_checked{$offsets} ++;
                
                #  skip it if it's already passed
                next if exists $valid_index_offsets{$offsets};
                
                #  might want to also check if it has already been checked and failed?
                #  No - there might be cases where it fails for one origin, but not for others

                #my $pass = 0;
                #next COMPARE if ! eval ($conditions);
                next COMPARE
                    if not $spatial_params -> evaluate (
                        coord_array1 => $check_ref,
                        coord_array2 => $element_ref,
                        cellsizes    => $cellsizes,
                    );

                $valid_index_offsets{$offsets}++;
            }  #  :COMPARE
        }
    }
    #print Data::Dumper::Dumper(\%valid_index_offsets);
    #print Data::Dumper::Dumper (\@min_offset);
    #print Data::Dumper::Dumper (\@max_offset);
    print "\nDone\n";
    
    return wantarray ? %valid_index_offsets : \%valid_index_offsets;
}


#sub numerically {$a <=> $b};
sub min {$_[0] < $_[1] ? $_[0] : $_[1]};
sub max {$_[0] > $_[1] ? $_[0] : $_[1]};


1;


__END__

=head1 NAME

Biodiverse::Index - Methods to build, access and control an index of elements
in a Biodiverse::BaseStruct object.  

=head1 SYNOPSIS

  use Biodiverse::Index;

=head1 DESCRIPTION

Store an index to the values contained in the containing object.  This is used
to reduce the processing time for sppatial operations, as only the relevant
index elements need be searched for neighbouring elements, as opposed to the
entire file each iteration.
The index is ordered using aggregated element keys, so it is a "flat" index.
The index keys are calculated using numerical aggregation.
The indexed elements are stored as hash tables within each index element.
This saves on memory, as perl indexes hash keys globally.
Storing them as an array would increase the memory burder substantially
for large files.


=head2 Assumptions

Assumes C<Biodiverse::Common> is in the @ISA list.

Almost all methods in the Biodiverse library use {keyword => value} pairs as a policy.
This means some of the methods may appear to contain unnecessary arguments,
but it makes everything else more consistent.

List methods return a list in list context, and a reference to that list
in scalar context.

CHANGES NEEDED

=head1 Methods

These assume you have declared an object called $self of a type that
inherits these methods, normally:

=over 4

=item  $self = Biodiverse::BaseStruct->new;

=back


=over 5

=item $self->build_index ('contains' => 4);

Builds the index.

The C<contains> argument is the average number of base
elements to be contained in each index key, and controls the resolutions
of the index axes.  If not specified then the default is 4.

Specifying different values may (or may not) speed up your processing.

=item  $self->delete_index;

Deletes the index.

=item $self->get_index_elements (element => $key, 'offset' => $offset);

Gets the elements contained in the index key $element as a hash.

If C<offset> is specified then it calculates an offset index key and
returns its contents.  If this does not exist then you will get C<undef>.

=item $self->get_index_elements_as_array (element => $key, 'offset' => $offset);

Gets the elements contained in the index key $element as an array.
Actually calls C<get_index_elements> and returns the keys.

=item $self->get_index_keys;

Returns an array of the index keys.

=item $self->index_element_exists (element => $element);

Returns 1 if C<element> is specified and exists.  Returns 0 otherwise.

=item $self->snap_to_index (element => $element);

Returns the container index key for an element.


=back

=head1 REPORTING ERRORS

I read my email frequently, so use that.  It should be pretty stable, though.

=head1 AUTHOR

Shawn Laffan

Shawn.Laffan@unsw.edu.au


=head1 COPYRIGHT

Copyright (c) 2006 Shawn Laffan. All rights reserved.  This
program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REVISION HISTORY

=over 5

=item Version 1

May 2006.  Source libraries developed to the point where they can be
distributed.

=back

=cut
