package Biodiverse::Matrix::Base;
use strict;
use warnings;
use 5.010;

use Carp;
use English qw / -no_match_vars/;

use Scalar::Util qw /looks_like_number blessed/;
use List::Util qw /min max sum/;

our $VERSION = '3.1';

use Biodiverse::Exception;
use Ref::Util qw { :all };


my $EMPTY_STRING = q{};
my $lowmem_class = 'Biodiverse::Matrix::LowMem';
my $normal_class   = 'Biodiverse::Matrix';

use Biodiverse::Metadata::Export;
my $export_metadata_class = 'Biodiverse::Metadata::Export';

use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';

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

        return; #  if we get this far then the combination does not exist - cannot get the value
    }

    croak "[MATRICES] You seem to have added an extra result (value $exists) to" .
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
    my ($self, %args) = @_;

    my ($element1, $element2) = @args{'element1', 'element2'};

    Biodiverse::MissingArgument->throw ('element1 and/or element2 not defined')
      if ! (defined $element1 && defined $element2);

    #  avoid some excess hash lookups
    my $hash_ref = $self->{BYELEMENT};

    #  need to stop autovivification of element1 or 2
    no autovivification;
    return exists $hash_ref->{$element1}{$element2} ? 1
         : exists $hash_ref->{$element2}{$element1} ? 2
         : 0;
}

sub get_element_pair_count {
    my $self = shift;

    return 0 if ! exists $self->{BYELEMENT};

    my $elements = $self->{BYELEMENT};

    my $count = 0;
    foreach my $subhash (values %$elements) {
        $count += scalar keys %$subhash;
    }

    return $count;
}

#  clear all pairs containing this element.
#  should properly be delete_element, but it's already used
sub delete_all_pairs_with_element {  
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if ! defined $args{element};
    croak "element does not exist\n" if ! $self->element_is_in_matrix (element => $args{element});

    my $element = $args{element};

    my @deleted;    
    my @elements = $self->get_elements_as_array;
    my $delete_count = 0;
    foreach my $pair_el (@elements) {
        $delete_count += $self->delete_element (element1 => $pair_el, element2 => $element);
        $delete_count += $self->delete_element (element1 => $element, element2 => $pair_el);
    }

    return $delete_count;
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
        // croak "FILE NOT SPECIFIED in call to load_data\n";

    my $element_properties = $args{element_properties};
    my @label_columns      = @{$self->get_param('ELEMENT_COLUMNS')};
    my $values_start_col   = $self->get_param('MATRIX_STARTCOL') // ($label_columns[-1] + 1);

    my @orig_label_columns = @{$self->get_param('ELEMENT_COLUMNS')};

    my $label_col_count      = scalar @label_columns;
    my $orig_label_col_count = scalar @orig_label_columns;

    #  Does this really matter?
    #  It can never be triggered given they are set to be the same above
    warn '[MATRICES] WARNING: Different numbers of matrix columns '
        . "($label_col_count ) and cell snaps ($orig_label_col_count)\n"
      if $label_col_count != $orig_label_col_count;

    say "[MATRICES] INPUT MATRIX FILE: $file";

    my $IDcount = 0;
    my %label_list;
    my %label_in_matrix;
    my $out_sep_char   = $self->get_param('JOIN_CHAR');
    my $out_quote_char = $self->get_param('QUOTES');
    
    my $in_csv = $self->get_csv_object_using_guesswork (
        sep_char   => $args{sep_char},
        quote_char => $args{input_quote_char},
        fname      => $file,
        lines_to_use => 1,  #  only check the header, as nxm matrices aren't guaranteed to be symmetric
    );
    my $out_csv = $self->get_csv_object (
        sep_char   => $out_sep_char,
        quote_char => $out_quote_char,
    );

    my $lines_to_read_per_chunk = 50000;  #  needs to be a big matrix to go further than this

    my $fh = $self->get_file_handle (
        file_name => $file,
        use_bom   => 1,
    );

    my $lines = $self->get_next_line_set (
        file_handle         => $fh,
        target_line_count   => $lines_to_read_per_chunk,
        file_name           => $file,
        csv_object          => $in_csv,
    );

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

            next BY_LINE if $element_properties->get_element_exclude (element => $label);

            #  test include and exclude before remapping
            my $include = $element_properties->get_element_include (element => $label) // 1;
            next BY_LINE if !$include;

            if (defined $remapped_label) {
                $label = $remapped_label;
            }
        }

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

            if (defined $val && $blank_as_undef && $val eq $EMPTY_STRING) {
                $val = undef;
            }
            #  Skip if not defined, is blank or non-numeric.
            #  Need the first check because these are getting assigned in csv2list
            next BY_FIELD if !$undef_allowed && !defined $val;
            next BY_FIELD if defined $val && $val eq $EMPTY_STRING;  
            next BY_FIELD if defined $val && !$text_allowed && !looks_like_number ($val);

            my $label  = $label_list{$label_count};
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

#  import a sparse format file
#  Cargo culted from load_data, so some refactoring is in order
sub import_data_sparse {
    my $self = shift;
    my %args = @_;

    my $file = $args{file}
                || $self->get_param('FILE')
                || croak "FILE NOT SPECIFIED in call to load_data\n";

    my $element_properties = $args{element_properties};
    my @label_row_columns  = @{$args{label_row_columns}};
    my @label_col_columns  = @{$args{label_col_columns}};
    my $value_column       = $args{value_column};
    
    if (is_ref ($value_column)) {
        $value_column = $value_column->[0];  #  take the first if we are passed an array
    }

    say "[MATRICES] INPUT MATRIX FILE: $file";

    my $out_sep_char   = $self->get_param('JOIN_CHAR');
    my $out_quote_char = $self->get_param('QUOTES');

    my $in_csv = $self->get_csv_object_using_guesswork (
        quote_char => $args{input_quote_char},
        sep_char   => $args{sep_char},
        fname      => $file,
    );
    
    my $out_csv = $self->get_csv_object (
        sep_char   => $out_sep_char,
        quote_char => $out_quote_char,
    );

    my $lines_to_read_per_chunk = 50000;  #  needs to be a big matrix to go further than this

    #  Re-open the file as the header is often important to us
    #  (seeking back to zero causes probs between File::BOM and Text::CSV_XS)
    my $fh = $self->get_file_handle (
        file_name => $file,
        use_bom   => 1,
    );

    my $lines = $self->get_next_line_set (
        file_handle         => $fh,
        target_line_count   => $lines_to_read_per_chunk,
        file_name           => $file,
        csv_object          => $in_csv,
    );

    #  now we build the matrix, skipping values that are already in the matrix
    my $text_allowed   = $self->get_param ('ALLOW_TEXT');
    my $undef_allowed  = $self->get_param ('ALLOW_UNDEF');
    my $blank_as_undef = $self->get_param ('BLANK_AS_UNDEF');
    my $label_count    = 0;

    shift @$lines;  #  first one is the header, which we don't need here

    BY_LINE:
    while (my $flds_ref = shift @$lines) {

        if (scalar @$lines == 0) {
            $lines = $self->get_next_line_set (
                file_handle        => $fh,
                file_name          => $file,
                target_line_count  => $lines_to_read_per_chunk,
                csv_object         => $in_csv,
            );
        }

        next BY_LINE if scalar @$flds_ref == 0;  #  skip empty lines

        #  get the label for this row
        my @tmp = @$flds_ref[@label_row_columns];  #  build the row label from the relevant slice
        my $col_label = $self->list2csv (
            list       => \@tmp,
            csv_object => $out_csv,
        );
        @tmp = @$flds_ref[@label_col_columns];  #  build the col label from the relevant slice
        my $row_label = $self->list2csv (
            list       => \@tmp,
            csv_object => $out_csv,
        );
        $col_label = $self->dequote_element (element => $col_label, quote_char => $out_quote_char);
        $row_label = $self->dequote_element (element => $row_label, quote_char => $out_quote_char);

        if ($element_properties) {

            my $remapped_col_label = $element_properties->get_element_remapped (element => $col_label);
            my $remapped_row_label = $element_properties->get_element_remapped (element => $row_label);

            next BY_LINE if $element_properties->get_element_exclude (element => $col_label);
            next BY_LINE if $element_properties->get_element_exclude (element => $row_label);

            #  test include and exclude before remapping
            my $include =
                   ($element_properties->get_element_include (element => $col_label)
                &&  $element_properties->get_element_include (element => $row_label))
                // 1;
            next BY_LINE if !$include;

            if (defined $remapped_col_label) {
                $col_label = $remapped_col_label;
            }
            if (defined $remapped_row_label) {
                $col_label = $remapped_row_label;
            }
        }

        my $val = $flds_ref->[$value_column];

        next BY_LINE  #  skip if in the matrix and already defined
            if defined 
                $self->get_value (
                    element1 => $row_label,
                    element2 => $col_label,
                );

        $self->add_element (
            element1 => $row_label,  #  matches non-sparse import
            element2 => $col_label,
            value    => $val,
        );
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



#  wrapper for table conversions
#  should implement metadata
sub to_table {
    my $self = shift;
    my %args = @_;
    
    my $type = $args{type} // '';

    if ($type eq 'sparse') {
        return $self->to_table_sparse (%args);
    }
    elsif ($type eq 'gdm') {
        return $self->to_table_gdm (%args);
    }
    else {
        return $self->to_table_normal (%args);
    }
}

#  convert the matrix to a tabular array
sub to_table_normal {
    my $self = shift;
    my %args = (
        symmetric => 1,
        @_,
    );
    
    my $fh = $args{file_handle};
    my $out_csv_obj = $args{csv_object};
    if ($fh) {
        $out_csv_obj //= $self->get_csv_object_for_export (%args);
    }

    my $symmetric = $args{symmetric};
    #  allow for both UL and LL to be specified
    my $ll_only = $args{lower_left}  && ! $args{upper_right};
    my $ur_only = $args{upper_right} && ! $args{lower_left};

    my @data;
    my @elements = sort $self->get_elements_as_array;
    
    push @data, [q{}, @elements];  #  header line with blank leader
    my $i = 0;
    
    my $progress = Biodiverse::Progress->new(text => 'Converting matrix to table');
    my $to_do = scalar @elements;

    E1:
    foreach my $element1 (@elements) {
        $i++;
        my $j = 0;

        if ($fh) {
            while (@data) {
                my $line = shift @data;
                my $string = $self->list2csv(list => $line, csv_object => $out_csv_obj);
                say {$fh} $string;
            }
        }

        my @row;
        push @row, $element1;
        push @data, \@row;

        $progress->update (
            "Converting matrix to table\n(row $i / $to_do)",
            $i / $to_do,
        );
        
        E2:
        foreach my $element2 (@elements) {
            $j++;

            next E1 if $ll_only and $j > $i;
            next E2 if $ur_only and $j < $i;

            if (!$symmetric) {
                my $exists = $self->element_pair_exists (
                    element1 => $element1,
                    element2 => $element2,
                );
                if ($exists == 1) {
                    push @row, $self->get_value (
                        element1    => $element1,
                        element2    => $element2,
                        pair_exists => 1,
                    );
                }
            }
            else {
                push @row, $self->get_defined_value_aa ($element1, $element2);
            }
        }
    }

    if ($fh) {
        while (@data) {
            my $line = shift @data;
            my $string = $self->list2csv(list => $line, csv_object => $out_csv_obj);
            say {$fh} $string;
        }
    }

    return wantarray ? @data : \@data;
}

sub to_table_sparse {
    my $self = shift;
    
    my %args = (
        symmetric => 1,
        @_,
    );
    
    my $fh = $args{file_handle};
    my $out_csv_obj = $args{csv_object};
    if ($fh) {
        $out_csv_obj //= $self->get_csv_object_for_export (%args);
    }

    my @data;
    my @elements = sort $self->get_elements_as_array;
    
    my $progress_bar = Biodiverse::Progress->new();
    my $to_do        = scalar @elements;
    my $progress_pfx = "Converting matrix to GDM format table\n";

    my $ll_only   = $args{lower_left};
    my $ur_only   = $args{upper_right};
    my $symmetric = $args{symmetric};
    
    push @data, [qw /Row Column Value/];  #  header line
    
    my $i = 0;
    
    E1:
    foreach my $element1 (@elements) {
        $i++;
        my $j = 0;

        my $progress = $i / $to_do;
        $progress_bar->update (
            $progress_pfx . "(row $i / $to_do)",
            $progress,
        );

        if ($fh) {
            while (@data) {
                my $line = shift @data;
                my $string = $self->list2csv(list => $line, csv_object => $out_csv_obj);
                say {$fh} $string;
            }
        }

        E2:
        foreach my $element2 (@elements) {
            $j++;

            next E1 if $ll_only  and $j > $i;
            next E2 if $ur_only and $j < $i;

            my $exists = $self->element_pair_exists (
                element1 => $element1,
                element2 => $element2,
            );

            #  if we are symmetric then list it regardless, otherwise only if we have this exact pair-order
            if ($exists == 1 || ($symmetric && $exists)) {
                my $value = $self->get_value (
                    element1    => $element1,
                    element2    => $element2,
                    pair_exists => $exists,
                );
                my $list = [$element1, $element2, $value];
                push @data, $list;
            }
        }
    }
    
    if ($fh) {
        while (@data) {
            my $line = shift @data;
            my $string = $self->list2csv(list => $line, csv_object => $out_csv_obj);
            say {$fh} $string;
        }
    }

    return wantarray ? @data : \@data;
}

sub to_table_gdm {
    my $self = shift;
    
    my %args = (
        symmetric => 1,
        @_,
    );

    my $fh = $args{file_handle};
    my $out_csv_obj = $args{csv_object};
    if ($fh) {
        $out_csv_obj //= $self->get_csv_object_for_export (%args);
    }

    my $ll_only   = $args{lower_left};
    my $ur_only   = $args{upper_right};
    my $symmetric = $args{symmetric};

    my @data;
    my @elements = sort $self->get_elements_as_array;

    #  Get csv object from the basedata to crack the elements.
    #  Could cause trouble later on for matrices without basedata.
    my $el_csv_obj;
    if (my $bd = $self->get_param ('BASEDATA_REF')) {
        $el_csv_obj = $bd->get_csv_object (sep_char => $bd->get_param ('JOIN_CHAR'));
    }
    else {
        $el_csv_obj = $self->get_csv_object;
    }
    
    push @data, [qw /x1 y1 x2 y2 Value/];  #  header line
    
    my $progress_bar = Biodiverse::Progress->new();
    my $to_do        = scalar @elements;
    my $progress_pfx = "Converting matrix to GDM format table\n";
    
    my $i = 0;
    
    E1:
    foreach my $element1 (@elements) {
        $i++;
        my @element1 = $self->csv2list (string => $element1, csv_object => $el_csv_obj);
        
        my $progress = $i / $to_do;
        $progress_bar->update (
            $progress_pfx . "(row $i / $to_do)",
            $progress,
        );
        
        if ($fh) {
            while (@data) {
                my $line = shift @data;
                my $string = $self->list2csv(list => $line, csv_object => $out_csv_obj);
                say {$fh} $string;
            }
        }

        my $j = 0;
        E2:
        foreach my $element2 (@elements) {
            $j++;
            next E1 if $ll_only and $j > $i;
            next E2 if $ur_only and $j < $i;

            my $exists = $self->element_pair_exists (
                element1 => $element1,
                element2 => $element2,
            );

            #  if we are symmetric then list it regardless, otherwise only if we have this exact pair-order
            if (($symmetric and $exists) or $exists == 1) {
                my $value = $self->get_value (
                    element1    => $element1,
                    element2    => $element2,
                    pair_exists => $exists,
                );

                my @element2 = $self->csv2list (string => $element2, csv_object => $el_csv_obj);
                my $list = [@element1[0,1], @element2[0,1], $value];
                push @data, $list;
            }
        }
    }

    if ($fh) {
        while (@data) {
            my $line = shift @data;
            my $string = $self->list2csv(list => $line, csv_object => $out_csv_obj);
            say {$fh} $string;
        }
    }

    return wantarray ? @data : \@data;
}


#  this is almost identical to that in BaseStruct - refactor needed
sub get_metadata_export {
    my $self = shift;

    #  need a list of export subs
    my %subs = $self->get_subs_with_prefix (prefix => 'export_');

    #  hunt through the other export subs and collate their metadata
    #  (not anymore)
    my @formats;
    my %format_labels;  #  track sub names by format label
    
    #  loop through subs and get their metadata
    my %params_per_sub;
    
    LOOP_EXPORT_SUB:
    foreach my $sub (sort keys %subs) {
        my %sub_args = $self->get_args (sub => $sub);

        my $format = $sub_args{format};

        croak "Metadata item 'format' missing\n"
            if not defined $format;

        $format_labels{$format} = $sub;

        next LOOP_EXPORT_SUB
            if $sub_args{format} eq $EMPTY_STRING;

        $params_per_sub{$format} = $sub_args{parameters};

        my $params_array = $sub_args{parameters};

        push @formats, $format;
    }
    
    @formats = sort @formats;
    $self->move_to_front_of_list (
        list => \@formats,
        item => 'Delimited text'
    );

    my $format_choice = bless {
        name        => 'format',
        label_text  => 'Format to use',
        type        => 'choice',
        choices     => \@formats,
        default     => 0
    }, $parameter_metadata_class;

    my %metadata = (
        parameters     => \%params_per_sub,
        format_choices => [$format_choice],
        format_labels  => \%format_labels,
    ); 

    return $export_metadata_class->new (\%metadata);
}

sub export {
    my $self = shift;
    my %args = @_;
    
    #  get our own metadata...
    my $metadata = $self->get_metadata (sub => 'export');

    my $sub_to_use = $metadata->get_sub_name_from_format (%args);
    
    eval {$self->$sub_to_use (%args)};
    croak $EVAL_ERROR if $EVAL_ERROR;
    
    return;
}

#  probably needs to be subdivided into normal and sparse
sub export_delimited_text {
    my $self = shift;
    my %args = @_;
    
    my $filename = $args{filename} // $args{file};

    # add a .csv suffix if no extension present
    if (defined $filename and not $filename =~ /\.(.*)$/) {
        $filename = $filename . '.csv';
    }
    
    my $fh;
    #  allow control of $fh for test purposes
    if (!$args{_no_fh}) {
        $fh = $self->get_file_handle (
            file_name => $filename,
            mode      => '>',
        );
    }
    my $csv_obj = $self->get_csv_object_for_export (%args);

    my $table = $self->to_table (
        %args,
        file_handle => $fh,
        csv_object  => $csv_obj,
    );

    if (scalar @$table) {
        eval {
            $self->write_table (
                %args,
                file => $filename,
                data => $table
            )
        };
        croak $EVAL_ERROR if $EVAL_ERROR;
    }

    return;
}


sub get_metadata_export_delimited_text {
    my $self = shift;
    
    my @sep_chars = my @separators = defined $ENV{BIODIVERSE_FIELD_SEPARATORS}
                    ? @$ENV{BIODIVERSE_FIELD_SEPARATORS}
                    : (',', 'tab', ';', 'space', ":");
    my @quote_chars = qw /" ' + $/;
    
    my @formats = qw /normal sparse gdm/;
    
    my @parameters = (
        {
            name       => 'file',  # GUI supports just one of these
            type       => 'file'
        }, 
        {
            name       => 'type',
            label_text => 'output format',
            type       => 'choice',
            tooltip    => $self->get_tooltip_sparse_normal,
            choices    => \@formats,
            default    => 0
        },
        {
            name       => 'symmetric',
            label_text => 'Force output to be symmetric',
            type       => 'boolean',
            default    => 1
        },
        {
            name       => 'lower_left',
            label_text => 'Print lower left only',
            tooltip    => 'print lower left matrix',
            type       => 'boolean',
            default    => 0
        },
        {
            name       => 'upper_right',
            label_text => 'Print upper right only',
            tooltip    => 'print upper right matrix',
            type       => 'boolean',
            default    => 0
        },
        {
            name       => 'sep_char',
            label_text => 'Field separator',
            type       => 'choice',
            tooltip    => 'for text outputs',
            choices    => \@sep_chars,
            default    => 0,
        },
        {
            name       => 'quote_char',
            label_text => 'Quote character',
            type       => 'choice',
            tooltip    => 'for text outputs',
            choices    => \@quote_chars,
            default    => 0,
        },
    );

    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    my %args = (
        format => 'Delimited text',
        parameters => \@parameters,
    );
    
    return wantarray ? %args : \%args;
}

sub get_tooltip_sparse_normal {
    my $self = shift;
    
    my $tool_tip =<<"END_MX_TOOLTIP"
Normal format is a normal rectangular row by column matrix like:
\t,col1,col2
row1,value,value
row2,value,value

Sparse format is a list like:
\trow1,col1,value
\trow1,col2,value
\trow2,col2,value

GDM (Generalized Dissimilarity Modelling) format is
a sparse matrix but with the row and column
elements split into their component axes.  
\tx1,y1,x2,y2,value
\trow1_x1,row1_y1,row2_x2,row2_y2,value
\trow2_x1,row2_y1,row3_x2,row3_y2,value

Note that GDM supports only two axes (x and y) so only the
first two axes are exported.  

END_MX_TOOLTIP
;

    return $tool_tip;
}


sub trim {
    my $self = shift;
    my %args = @_;

    croak "neither trim nor keep args specified\n"
      if ! defined $args{keep} && ! defined $args{trim};

    my $data;
    my $keep = $args{keep};  #  keep only these (overrides trim)
    my $trim = $args{trim};  #  delete all of these
    if ($keep) {
        $trim = undef;
        $data = $keep;
        say "[MATRIX] Trimming elements using keep option";
    }
    else {
        $data = $trim;
        say "[MATRIX] Trimming elements using trim option";
    }

    croak "keep or trim argument is not a ref\n"
      if ! ref $data;

    my %keep_or_trim;

    if (blessed $data) {
      METHOD:
        foreach my $method (qw /get_named_nodes get_elements get_labels_as_hash/) {
            if ($data->can($method)) {
                %keep_or_trim = $data->$method;
                last METHOD;
            }
        }
    }
    elsif (is_arrayref($data)) {  #  convert to hash if needed
        @keep_or_trim{@$data} = (1) x scalar @$data;
    }
    elsif (is_hashref($data)) {
        %keep_or_trim = %$keep;
    }

    my $delete_count = 0;
    my $delete_sub_count = 0;
    
  ELEMENT:
    foreach my $element ($self->get_elements_as_array) {
        if ($keep) {    #  keep if in the list
            next ELEMENT if exists $keep_or_trim{$element};
        }
        elsif ($trim) { #  trim if not in the list  
            next ELEMENT if ! exists $keep_or_trim{$element};
        }

        $delete_sub_count +=
            $self->delete_all_pairs_with_element (
                element => $element,
            );
        $delete_count ++;
    }

    if ($delete_count) {
        say "Deleted $delete_count elements and $delete_sub_count pairs";
        $self->delete_cached_values;
    }

    my %results = (
        DELETE_COUNT     => $delete_count,
        DELETE_SUB_COUNT => $delete_sub_count,
    );

    return wantarray ? %results : \%results;
}

# wrapper around get_elements_as_array for the purpose of polymorphism in
# the auto-remap logic.
sub get_labels {
    my $self = shift;
    return $self->get_elements_as_array;
}


# takes a hash mapping names of elements currently in this matrix to
# desired names, renames elements accordingly.
sub remap_labels_from_hash {
    my $self       = shift;
    my %args       = @_;
    my $remap_hash = $args{remap};

    foreach my $old_name (keys %$remap_hash) {
        my $new_name = $remap_hash->{$old_name};

        next if !defined $new_name || $old_name eq $new_name;

        $self->rename_element(
            old_name => $old_name,
            new_name => $new_name,
        );
    }

    return;
}

# renames element 'old_name' to 'new_name'
sub rename_element {
    my $self = shift;
    my %args = @_;

    my $old_name = $args{old_name};
    my $new_name = $args{new_name};

    #say "Matrix: renaming $old_name to $new_name";

    my $all_elements = $self->get_elements_as_array;

    for my $element (@$all_elements) {
        my $exists = $self->element_pair_exists (
            element1 => $element,
            element2 => $old_name
        );

        next if !$exists;

        # pair is in correct order
        if ( $exists == 1 ) {
            my $value = $self->get_value(
                element1 => $element,
                element2 => $old_name
            );

            if ( $element eq $old_name ) {
                $self->add_element(
                    element1 => $new_name,
                    element2 => $new_name,
                    value    => $value
                );
                $self->delete_element(
                    element1 => $old_name,
                    element2 => $old_name
                );
            }
            else {
                $self->add_element(
                    element1 => $element,
                    element2 => $new_name,
                    value    => $value
                );
                $self->delete_element(
                    element1 => $element,
                    element2 => $old_name
                );
            }
            #  now make sure we check for the reverse
            $exists = $self->element_pair_exists (
                element1 => $element,
                element2 => $old_name
            );
        }
        if ( $exists == 2 ) {
            # pair is in other order
            my $value = $self->get_value(
                element1 => $old_name,
                element2 => $element,
            );
            $self->add_element(
                element1 => $new_name,
                element2 => $element,
                value    => $value
            );
            $self->delete_element(
                element1 => $old_name,
                element2 => $element
            );
        }
    }
    return;
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
