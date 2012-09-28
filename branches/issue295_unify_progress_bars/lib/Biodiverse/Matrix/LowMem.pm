#  a low memory version of Biodiverse::Matrix, with less functionality to boot.  
package Biodiverse::Matrix::LowMem;
use strict;
use warnings;

use Carp;

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

    $self->{BYELEMENT}{$element1}{$element2} = $args{value};
    
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
    my $value = $self->get_value (
        element1 => $element1,
        element2 => $element2,
    );
    
    #print "DELETING $element1 $element2\n";
        
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
    delete $self->{BYVALUE}{$value}{$element1}{$element2}; # if exists $self->{BYVALUE}{$value}{$element1}{$element2};
    if (scalar keys %{$self->{BYVALUE}{$value}{$element1}} == 0) {
        #undef $self->{BYVALUE}{$value}{$element1};
        delete $self->{BYVALUE}{$value}{$element1};
        if (scalar keys %{$self->{BYVALUE}{$value}} == 0) {
            #undef $self->{BYVALUE}{$value};
            defined (delete $self->{BYVALUE}{$value})
                || warn "ISSUES BYVALUE $value $element1 $element2\n";
        }
    }
    #  decrement the ELEMENTS counts, deleting entry if now zero, as there are no more entries with this element
    $self->{ELEMENTS}{$element1}--;
    if ($self->{ELEMENTS}{$element1} == 0) {
        defined (delete $self->{ELEMENTS}{$element1})
            || warn "ISSUES $element1\n";
    }
    $self->{ELEMENTS}{$element2}--;
    if ($self->{ELEMENTS}{$element2} == 0) {
        defined (delete $self->{ELEMENTS}{$element2})
            || warn "ISSUES $element2\n";
    }
    
    #return ($self->element_pair_exists(@_)) ? undef : 1;  #  for debug
    return 1;  # return success if we get this far
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

=back

=head1 REPORTING ERRORS

http://code.google.com/p/biodiverse/issues/list

=head1 AUTHOR

Shawn Laffan

Shawn.Laffan@unsw.edu.au


=head1 COPYRIGHT

Copyright (c) 2006-2012 Shawn Laffan. All rights reserved.  This
program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.



=back

=cut
