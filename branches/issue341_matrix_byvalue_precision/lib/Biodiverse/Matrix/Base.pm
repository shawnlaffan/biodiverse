package Biodiverse::Matrix::Base;
use strict;
use warnings;

use Carp;
use Scalar::Util qw /looks_like_number/;
use List::Util qw /min max sum/;
use File::BOM qw /:subs/;

use Biodiverse::Exception;

my $EMPTY_STRING = q{};

#  check if the matrix contains an element with any pair
sub element_is_in_matrix { 
    my $self = shift;
    my %args = @_;
    
    croak "element not defined\n" if ! defined $args{element};

    my $element = $args{element};
    
    return $self->{ELEMENTS}{$element} if exists $self->{ELEMENTS}{$element};
    return;
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
    my $exists = $self -> element_pair_exists (@_);
    if (! $exists) {
        if ($args{element1} eq $args{element2} and $self->element_is_in_matrix (element => $args{element1})) {
            return $self->get_param ('SELF_SIMILARITY');  #  defaults to undef
        }
        else {
            return; #  combination does not exist - cannot get the value
        }
    }
    elsif ($exists == 2) {  #  elements exist, but in different order - switch them
        $element1 = $args{element2};
        $element2 = $args{element1};
    }
    elsif ($exists == 1) {
        $element1 = $args{element1};
        $element2 = $args{element2};
    }
    else {
        croak   "[MATRICES] You seem to have added an extra result (value $exists) to" .
                " sub element_pair_exists.  What were you thinking?\n";
    }
    return $self->{BYELEMENT}{$element1}{$element2};
}

#  check an element pair exists, returning 1 if yes, 2 if yes, but in different order, undef otherwise
sub element_pair_exists {  
    my $self = shift;
    my %args = @_;

    Biodiverse::MissingArgument->throw ('element1 or element2 not defined')
      if ! defined $args{element1} || ! defined $args{element2};

    my $element1 = $args{element1};
    my $element2 = $args{element2};
    
    #  need to stop autovivification of element1 or 2
    if (exists $self->{BYELEMENT}{$element1}) {
        return 1 if exists $self->{BYELEMENT}{$element1}{$element2};
    }
    if (exists $self->{BYELEMENT}{$element2}) {
        return 2 if exists $self->{BYELEMENT}{$element2}{$element1};
    }
    return 0;
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

    my @label_columns = @{$self->get_param('ELEMENT_COLUMNS')};

    my @orig_label_columns = @{$self->get_param('ELEMENT_COLUMNS')};

    warn "[MATRICES] WARNING: Different numbers of matrix columns (".($#label_columns + 1).") and cell snaps (".($#orig_label_columns+1).")\n"
            if $#label_columns != $#orig_label_columns;

    my $values_start_col = ($self->get_param('MATRIX_STARTCOL') || $label_columns[-1] + 1);

    print "[MATRICES] INPUT MATRIX FILE: $file\n";
    open (my $fh1, '<:via(File::BOM)', $file) || croak "Could not open $file for reading\n";
    my $header = <$fh1>;  #  get header line
    $fh1->close;

    my $in_sep_char = $args{sep_char};
    if (! defined $in_sep_char) {
        $in_sep_char = $self -> guess_field_separator (string => $header);
    }
    my $eol = $self -> guess_eol (string => $header);

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
        $input_quote_char = $self -> guess_quote_char (string => \$whole_file);
        #  if all else fails...
        $input_quote_char = $self -> get_param ('QUOTES') if ! defined $input_quote_char;
    }

    my $IDcount = 0;
    my %labelList;
    my %labelInMatrix;
    my $out_sep_char = $self->get_param('JOIN_CHAR');
    my $out_quote_char = $self->get_param('QUOTES');
    
    my $in_csv = $self -> get_csv_object (
        sep_char    => $in_sep_char,
        quote_char  => $input_quote_char,
    );
    my $out_csv = $self -> get_csv_object (
        sep_char    => $out_sep_char,
        quote_char  => $out_quote_char,
    );
    
    my $lines_to_read_per_chunk = 50000;  #  needs to be a big matrix to go further than this

    open (my $fh, '<:via(File::BOM)', $file) || croak "Could not open $file for reading\n";

    my $lines = $self -> get_next_line_set (
        progress            => $args{progress_bar},
        file_handle         => $fh,
        target_line_count   => $lines_to_read_per_chunk,
        file_name           => $file,
        csv_object          => $in_csv,
    );

    #$fh -> close;
    
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
            $lines = $self -> get_next_line_set (
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

        if ($element_properties) {

            my $remapped_label
                = $element_properties -> get_element_remapped (element => $label);

            next BY_LINE if $element_properties -> get_element_exclude (element => $label);

            #  test include and exclude before remapping
            my $include = $element_properties -> get_element_include (element => $label);
            next BY_LINE if defined $include and not $include;

            if (defined $remapped_label) {
                $label = $remapped_label;
            }
        }
        
        #print "IDcount is $IDcount\n";

        $labelList{$IDcount} = $label;
        $labelInMatrix{$label}++;

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
            
            my $label = $labelList{$label_count};
            my $label2 = $labelList{$i};
            
            next BY_FIELD  #  skip if in the matrix and already defined
                if defined 
                    $self -> get_value (
                        element1 => $label,
                        element2 => $label2,
                    );

            $self -> add_element (
                element1 => $label,
                element2 => $label2,
                value    => $val,
            );
        }
        $label_count ++;
    }

    return;
}

sub numerically {$a <=> $b};

1;
