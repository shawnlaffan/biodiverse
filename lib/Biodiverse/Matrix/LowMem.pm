#  a low memory version of Biodiverse::Matrix, with less functionality to boot.  
package Biodiverse::Matrix::LowMem;
use strict;
use warnings;

use Carp;
use List::Util qw /min max/;

our $VERSION = '3.99_004';

use Biodiverse::Matrix;
use Biodiverse::Exception;

use parent qw /Biodiverse::Common Biodiverse::Matrix::Base/;

sub new {
    my $class = shift;
    my %args = @_;
    
    my $self = bless {}, $class;
    

    # try to load from a file if the file arg is given
    my $file_loaded;
    $file_loaded = $self->load_file (@_) if defined $args{file};
    return $file_loaded if defined $file_loaded;


    my %PARAMS = (
        OUTPFX               =>  'BIODIVERSE',
        OUTSUFFIX            => 'bms',
        OUTSUFFIX_YAML       => 'bmy',
        TYPE                 => undef,
        QUOTES               => q{'},
        JOIN_CHAR            => q{:},  #  used for labels
        ELEMENT_COLUMNS      => [1,2],
        PARAM_CHANGE_WARN    => undef,
        CACHE_MATRIX_AS_TREE => 1,
    );
    
    $self->set_params (%PARAMS, @_);  #  load the defaults, with the rest of the args as params
    $self->set_default_params;  #  and any user overrides

    $self->{BYELEMENT} = undef;  #  values indexed by elements
    
    $self->set_param (NAME => $args{name}) if defined $args{name};

    warn "[MATRIX] WARNING: Matrix name not specified\n"
        if ! defined $self->get_param('NAME');

    return $self;
}

sub element_is_in_matrix { 
    my $self = shift;
    my %args = @_;
    
    croak "element not defined\n" if ! defined $args{element};

    my $element = $args{element};

    return 1 if exists $self->{BYELEMENT}{$element};
    
    my $el_hash = $self->{BYELEMENT};
    foreach my $hashref (values %$el_hash) {
        return 1 if exists $hashref->{$element};
    }

    return;
}

sub add_element {  #  add an element pair to the object
    my $self = shift;
    my %args = @_;
    
    my $element1 = $args{element1};
    croak "Element1 not specified in call to add_element\n"
        if ! defined $element1;

    my $element2 = $args{element2};
    croak "Element2 not specified in call to add_element\n"
        if ! defined $element2;

    my $val = $args{value};
    if (! defined $val && ! $self->get_param('ALLOW_UNDEF')) {
        warn "[Matrix] add_element Warning: Value not defined and ALLOW_UNDEF not set, not adding row $element1 col $element2.\n";
        return;
    }

    $self->{BYELEMENT}{$element1}{$element2} = $val;
    
    return;
}

sub add_element_aa {  #  add an element pair to the object
    my ($self, $el1, $el2, $val) = @_;

    croak "Element1 not specified in call to add_element\n"
        if ! defined $el1;
    croak "Element2 not specified in call to add_element\n"
        if ! defined $el2;

    if (! defined $val && ! $self->get_param('ALLOW_UNDEF')) {
        warn "[Matrix] add_element Warning: Value not defined and ALLOW_UNDEF not set, not adding row $el1 col $el2.\n";
        return;
    }

    $self->{BYELEMENT}{$el1}{$el2} = $val;
    
    return;
}

sub delete_element {  #  should be called delete_element_pair, but need to find where it's used first
    my $self = shift;
    my %args = @_;
    croak "element1 or element2 not defined\n"
        if     ! defined $args{element1}
            || ! defined $args{element2};

    my $element1 = $args{element1};
    my $element2 = $args{element2};
    my $exists = $self->element_pair_exists (@_);

    if (! $exists) {
        #print "WARNING: element combination does not exist\n";
        return 0; #  combination does not exist - cannot delete it
    }
    elsif ($exists == 2) {  #  elements exist, but in different order - switch them
        #print "DELETE ELEMENTS SWITCHING $element1 $element2\n";
        $element1 = $args{element2};
        $element2 = $args{element1};
    }
    
    #  now we get to the cleanup, including the containing hashes if they are now empty
    #  all the undef - delete pairs are to ensure they get deleted properly
    #  the hash ref must be empty (undef) or it won't be deleted
    #  autovivification of $self->{BYELEMENT}{$element1} is avoided by $exists above
    delete $self->{BYELEMENT}{$element1}{$element2}; # if exists $self->{BYELEMENT}{$element1}{$element2};
    if (scalar keys %{$self->{BYELEMENT}{$element1}} == 0) {
        #print "Deleting BYELEMENT{$element1}\n";
        #undef $self->{BYELEMENT}{$element1};
        defined (delete $self->{BYELEMENT}{$element1})
            || warn "ISSUES BYELEMENT $element1 $element2\n";
    }

    return 1;  # return success if we get this far
}

my $ludicrously_large_pos_value = 10 ** 20;
my $ludicrously_large_neg_value = -$ludicrously_large_pos_value;

sub get_min_value {
    my $self = shift;

    my $min = $ludicrously_large_pos_value;
    my $elements = $self->{BYELEMENT};
    foreach my $hash (values %$elements) {
        $min = min ($min, values %$hash);
    }
    
    return $min;
}


sub get_max_value {
    my $self = shift;

    my $max = $ludicrously_large_neg_value;
    my $elements = $self->{BYELEMENT};
    foreach my $hash (values %$elements) {
        $max = max ($max, values %$hash);
    }
    
    return $max;
}


#  very inefficient
sub get_element_pairs_with_value {
    my $self = shift;
    my %args = @_;
    
    my $val = $args{value};

    my %results;

    my $element_hash = $self->{BYELEMENT};
    
    while (my ($el1, $hash_ref) = each %$element_hash) {
        foreach my $el2 (keys %$hash_ref) {
            my $value = $self->get_value (element1 => $el1, element2 => $el2);
            next if $val ne $value;
            $results{$el1}{$el2} ++;
        }
    }

    return wantarray ? %results : \%results;
}


sub get_elements_as_array {
    my $self = shift;

    my $elements_ref = $self->{BYELEMENT};

    my %elements;
    @elements{keys %$elements_ref} = undef;

    foreach my $hash (values %$elements_ref) {
        @elements{keys %$hash} = undef;
    }

    return wantarray
        ? keys %elements
        : [keys %elements];
}

#  will not work well in all cases
sub get_element_count {
    my $self = shift;

    return 0 if ! exists $self->{BYELEMENT};

    my %el_hash;
    
    my $elements = $self->{BYELEMENT};
    @el_hash{keys %$elements} = undef;

    foreach my $hash (values %$elements) {
        @el_hash{keys %$hash} = undef;
    }

    return scalar keys %el_hash;
}

1;



__END__

=head1 NAME

Biodiverse::Matrix::LowMem

=head1 SYNOPSIS

  use Biodiverse::Matrix::LowMem;
  my $mx = Biodiverse::Matrix::LowMem->new ();

=head1 DESCRIPTION

A low memory version of Biodiverse::Matrix (currently with fewer methods).

The difference from Biodiverse::Matrix is basically that this version
does not maintain extra lists
to track the values across the matrix elements, nor which elements
are in the matrix.  These must be derived from the data structure each time.

=head1 REPORTING ERRORS

https://github.com/shawnlaffan/biodiverse/issues

=head1 AUTHOR

Shawn Laffan

Shawn.Laffan@unsw.edu.au


=head1 COPYRIGHT

Copyright (c) 2006-2012 Shawn Laffan. All rights reserved.  This
program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut
