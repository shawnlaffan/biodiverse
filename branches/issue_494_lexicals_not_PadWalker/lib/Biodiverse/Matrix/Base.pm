package Biodiverse::Matrix::Base;
use strict;
use warnings;
use 5.010;

use Carp;
use Scalar::Util qw /looks_like_number blessed/;
use List::Util qw /min max sum/;
use File::BOM qw /:subs/;

our $VERSION = '0.99_005';

use Biodiverse::Exception;

my $EMPTY_STRING = q{};
my $lowmem_class = 'Biodiverse::Matrix::LowMem';
my $normal_class   = 'Biodiverse::Matrix';

#  check if the matrix contains an element with any pair
sub element_is_in_matrix { 
    my $self = shift;
    my %args = @_;

    my $element = $args{element}
      // croak "argument element not defined\n";

    return exists $self->{ELEMENTS}{$element};
}

#  syntactic sugar
sub set_value {
    my $self = shift;
    return $self->add_element (@_);
}

sub get_value {  #  return the value of a pair of elements. argument checking is done by element_pair_exists.
    my $self = shift;
    my %args = @_;
    
    my ($element1, $element2);
    my $exists = $args{pair_exists} || $self->element_pair_exists (@_);

    if ($exists == 1) {
        $element1 = $args{element1};
        $element2 = $args{element2};
        return $self->{BYELEMENT}{$element1}{$element2};
    }
    elsif ($exists == 2) {  #  elements exist, but in different order - switch them
        $element1 = $args{element2};
        $element2 = $args{element1};
        return $self->{BYELEMENT}{$element1}{$element2};
    }
    elsif (! $exists) {
        if ($args{element1} eq $args{element2}
            and $self->element_is_in_matrix (element => $args{element1})
            ) {
            return $self->get_param ('SELF_SIMILARITY');  #  defaults to undef
        }
        else {
            return; #  combination does not exist - cannot get the value
        }
    }

    croak   "[MATRICES] You seem to have added an extra result (value $exists) to" .
            " sub element_pair_exists.  What were you thinking?\n";
}

#  Same as get_value except it does not check for existence or self-similarity
#  and returns undef if nothing found
sub get_defined_value {
    my $self = shift;
    my %args = @_;
    
    no autovivification;

    my ($el_ref, $element1, $element2) = ($self->{BYELEMENT}, $args{element1}, $args{element2});

    return $el_ref->{$element1}{$element2} // $el_ref->{$element2}{$element1};
}

#  a bare metal version of get_defined_value
#  uses array args for speed, hence the _aa in the name
sub get_defined_value_aa {
    no autovivification;

    my $el_ref = $_[0]->{BYELEMENT};

    $el_ref->{$_[1]}{$_[2]} // $el_ref->{$_[2]}{$_[1]};
}



#  check an element pair exists, returning:
#  1 if yes,
#  2 if yes but in different order,
#  undef otherwise
sub element_pair_exists {  
    my $self = shift;
    my %args = @_;

    my ($element1, $element2) = @args{'element1', 'element2'};

    Biodiverse::MissingArgument->throw ('element1 and/or element2 not defined')
      if ! (defined $element1 && defined $element2);

    #  avoid some excess hash lookups
    my $hash_ref = $self->{BYELEMENT};

    #  need to stop autovivification of element1 or 2
    no autovivification;
    return 1 if exists $hash_ref->{$element1}{$element2};
    return 2 if exists $hash_ref->{$element2}{$element1};

    return 0;
}

#  pass-through method
sub get_elements_with_value {
    my $self = shift;
    return $self->get_element_pairs_with_value (@_);
}

sub import_data {
    my $self = shift;
    return $self->load_data (@_);
}


sub load_data {
    my $self = shift;
    my %args = @_;
    my $file = $args{file}
                || $self->get_param('FILE')
                || croak "FILE NOT SPECIFIED in call to load_data\n";

    my $element_properties = $args{element_properties};

    my @label_columns      = @{$self->get_param('ELEMENT_COLUMNS')};
    my @orig_label_columns = @{$self->get_param('ELEMENT_COLUMNS')};

    my $label_col_count      = scalar @label_columns;
    my $orig_label_col_count = scalar @orig_label_columns;

    #  Does this really matter?
    #  It can never be triggered given they are set to be the same above
    warn '[MATRICES] WARNING: Different numbers of matrix columns '
        . "($label_col_count ) and cell snaps ($orig_label_col_count)\n"
      if $label_col_count != $orig_label_col_count;

    my $values_start_col = ($self->get_param('MATRIX_STARTCOL') || $label_columns[-1] + 1);

    say "[MATRICES] INPUT MATRIX FILE: $file";
    open (my $fh1, '<:via(File::BOM)', $file) || croak "Could not open $file for reading\n";
    my $header = <$fh1>;  #  get header line
    $fh1->close;

    my $in_sep_char = $args{sep_char};
    if (! defined $in_sep_char) {
        $in_sep_char = $self->guess_field_separator (string => $header);
    }
    my $eol = $self->guess_eol (string => $header);

    #  Re-open the file as the header is often important to us
    #  (seeking back to zero causes probs between File::BOM and Text::CSV_XS)
    open (my $fh2, '<:via(File::BOM)', $file) || croak "Could not open $file for reading\n";
    my $whole_file;
    do {
        local $/ = undef;  #  slurp whole file
        $whole_file = <$fh2>;
    };
    $fh2->close();  #  go back to the beginning

    my $input_quote_char = $args{input_quote_char};
    if (! defined $input_quote_char) {  #  guess the quotes character
        $input_quote_char = $self->guess_quote_char (string => \$whole_file);
        #  if all else fails...
        $input_quote_char = $self->get_param ('QUOTES') if ! defined $input_quote_char;
    }

    my $IDcount = 0;
    my %label_list;
    my %label_in_matrix;
    my $out_sep_char = $self->get_param('JOIN_CHAR');
    my $out_quote_char = $self->get_param('QUOTES');
    
    my $in_csv = $self->get_csv_object (
        sep_char    => $in_sep_char,
        quote_char  => $input_quote_char,
    );
    my $out_csv = $self->get_csv_object (
        sep_char    => $out_sep_char,
        quote_char  => $out_quote_char,
    );
    
    my $lines_to_read_per_chunk = 50000;  #  needs to be a big matrix to go further than this

    open (my $fh, '<:via(File::BOM)', $file) || croak "Could not open $file for reading\n";

    my $lines = $self->get_next_line_set (
        progress            => $args{progress_bar},
        file_handle         => $fh,
        target_line_count   => $lines_to_read_per_chunk,
        file_name           => $file,
        csv_object          => $in_csv,
    );

    #$fh->close;
    
    #  two pass system - one reads in the labels and data
    #  the other puts them into the matrix
    #  this allows for upper right matrices where we need to know the label
    #  and avoids convoluted calls to build labels when needed
    my @data;
    my @cols_to_use = ();
    my $valid_col_index = - 1;
    
    shift (@$lines);  #  first one is the header

    BY_LINE:
    while (my $flds_ref = shift @$lines) {

        if (scalar @$lines == 0) {
            $lines = $self->get_next_line_set (
                progress           => $args{progress_bar},
                file_handle        => $fh,
                file_name          => $file,
                target_line_count  => $lines_to_read_per_chunk,
                csv_object         => $in_csv,
            );
        }

        next BY_LINE if scalar @$flds_ref == 0;  #  skip empty lines

        $valid_col_index ++;

        #  get the label for this row
        my @tmp = @$flds_ref[@label_columns];  #  build the label from the relevant slice
        my $label = $self->list2csv (
            list       => \@tmp,
            csv_object => $out_csv,
        );
        $label = $self->dequote_element(element => $label, quote_char => $out_quote_char);

        if ($element_properties) {
            #  test include and exclude before remapping
            next BY_LINE
              if $element_properties->get_element_exclude (element => $label)
                || !$element_properties->get_element_include (element => $label);

            my $remapped_label
                = $element_properties->get_element_remapped (element => $label);

            if (defined $remapped_label) {
                $label = $remapped_label;
            }
        }

        #print "IDcount is $IDcount\n";

        $label_list{$IDcount} = $label;
        $label_in_matrix{$label}++;

        #  strip the leading labels and other data
        splice (@$flds_ref, 0, $values_start_col);  

        push @data, $flds_ref;
        push @cols_to_use, $valid_col_index;

        $IDcount++;
    }

    #  now we build the matrix, skipping lower left values if it is symmetric
    my $text_allowed   = $self->get_param ('ALLOW_TEXT');
    my $undef_allowed  = $self->get_param ('ALLOW_UNDEF');
    my $blank_as_undef = $self->get_param ('BLANK_AS_UNDEF');
    my $label_count    = 0;

    foreach my $flds_ref (@data) {
      BY_FIELD:
        foreach my $i (@cols_to_use) {
            my $val = $flds_ref->[$i];
#my $a = defined $val;  #  debug - hang a break on this
            if (defined $val && $blank_as_undef && $val eq $EMPTY_STRING) {
                $val = undef;
            }
            #  Skip if not defined, is blank or non-numeric.
            #  Need the first check because these are getting assigned in csv2list
            next BY_FIELD if !$undef_allowed && !defined $val;
            next BY_FIELD if defined $val && $val eq $EMPTY_STRING;  
            next BY_FIELD if defined $val && !$text_allowed && !looks_like_number ($val);

            my $label = $label_list{$label_count};
            my $label2 = $label_list{$i};
            
            next BY_FIELD  #  skip if in the matrix and already defined
                if defined 
                    $self->get_defined_value (
                        element1 => $label,
                        element2 => $label2,
                    );

            $self->add_element (
                element1 => $label,
                element2 => $label2,
                value    => $val,
            );
        }
        $label_count ++;
    }

    return;
}

#  convert to a Biodiverse::Matrix::LowMem object, if not one already
sub to_lowmem {
    my $self = shift;

    return $self if blessed ($self) eq $lowmem_class;

    $self->delete_value_index;
    bless $self, $lowmem_class;

    return $self;
}

sub to_normal {
    my $self = shift;

    return $self if blessed ($self) eq $normal_class;

    bless $self, $normal_class;
    $self->rebuild_value_index;

    return $self;
}

sub numerically {$a <=> $b};

1;


__END__

=head1 NAME

Biodiverse::Matrix::Base

=head1 SYNOPSIS

  use Biodiverse::Matrix::Base;

=head1 DESCRIPTION

TO BE FILLED IN

=head1 METHODS

=over

=item INSERT METHODS

=back

=head1 REPORTING ERRORS

Use the issue tracker at http://www.purl.org/biodiverse

=head1 COPYRIGHT

Copyright (c) 2012 Shawn Laffan. All rights reserved.  

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
