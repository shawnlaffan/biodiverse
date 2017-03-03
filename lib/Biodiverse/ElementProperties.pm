package Biodiverse::ElementProperties;

use strict;
use warnings;
use Carp;
use Scalar::Util qw/looks_like_number/;
use File::BOM qw /:subs/;

use Biodiverse::Exception;

our $VERSION = '1.99_007';

use parent qw /Biodiverse::BaseStruct Biodiverse::Common/; #/
use Ref::Util qw { :all };


use Biodiverse::Metadata::Parameter;
my $parameter_metadata_class = 'Biodiverse::Metadata::Parameter';



our %PARAMS = (  #  default parameters to load.  These will be overwritten if needed.
    OUTPFX            =>  "BIODIVERSE_PROPERTIES",
    OUTSUFFIX         => 'bss',
    OUTSUFFIX_YAML    => 'bsy',
    TYPE              => undef,
    QUOTES            => q{'},
    OUTPUT_QUOTE_CHAR => q{"},
    OUTPUT_SEP_CHAR   => q{,},   #  used for output data strings
    JOIN_CHAR         => q{:},   #  used for labels
    PARAM_CHANGE_WARN => undef,
);


sub get_metadata_import_data {
    
    my @sep_chars = defined $ENV{BIODIVERSE_FIELD_SEPARATORS}
                  ? @$ENV{BIODIVERSE_FIELD_SEPARATORS}
                  : (',', 'tab', ';', 'space', ":");
    my @quote_chars = qw /" ' + $/; #"
    my @input_sep_chars = ('guess', @sep_chars);
    my @input_quote_chars = ('guess', @quote_chars);
    
    #  these parameters are only for the GUI, so are not a full set
    #  add options for range etc?
    my @parameters = (
        {
            name       => 'input_sep_char',
            label_text => "Input field separator",
            tooltip    => "Select character",
            type       => 'choice',
            choices    => \@input_sep_chars,
            default   => 0,
        },
        {
            name       => 'input_quote_char',
            label_text => "Input quote character",
            tooltip    => "Select character",
            type       => 'choice',
            choices    => \@input_quote_chars,
            default    => 0,
        },
    );
    for (@parameters) {
        bless $_, $parameter_metadata_class;
    }

    my %arg_hash = (
        parameters => \@parameters,
    ); 

    return wantarray ? %arg_hash : \%arg_hash;
}

sub import_data {
    my $self = shift;
    my %args = @_;
    
    croak "[ElementProperties] file arg not defined\n" if not defined $args{file};
    #return wantarray ? () : {} if not defined $args{file};
    
    my $file         = $args{file};
    my $input_quote_char = $args{input_quote_char};
    my $sep          = $args{input_sep_char};    
    
    my $in_cols      = $args{input_element_cols};

    if (not defined $in_cols) {
        Biodiverse::Args::ElPropInputCols->throw (
            message => "Need argument input_element_cols to be set\n",
        );
    }
    elsif (!is_arrayref($in_cols)) {
        Biodiverse::Args::ElPropInputCols->throw (
            message => "Input_element_cols is not an array ref\n",
        );
    }
    elsif (not scalar @$in_cols) {
        Biodiverse::Args::ElPropInputCols->throw (
            message => "Element properties need at least one input element column to be set\n"
        );
    }
    
    my $out_cols     = $args{remapped_element_cols} || [];
    
    #  need to make these generic
    #my $range_col = $args{range};
    #my $sample_count_col = $args{sample_count};
    
    my $include_cols = $args{include_cols};
    if (defined $include_cols) {
        if (!is_arrayref($include_cols)) {
            $include_cols = [$include_cols];
        }
    }
    
    my $exclude_cols = $args{exclude_cols};
    if (defined $exclude_cols) {
        if (!is_arrayref($exclude_cols)) {
            $exclude_cols = [$exclude_cols];
        }
    }
    
    #  clean up used args - the rest are properties to be set
    delete @args{
        qw /file
            input_element_cols
            remapped_element_cols
            get_args
            include_cols
            exclude_cols
            input_sep_char
            input_quote_char
            /};
    
    #  STARTING THE GENERIC APPROACH
    #  the rest of the args are properties to be set
    #  - a _very_ dirty way of doing things but allows laziness elsewhere in the system
    my %prop_cols;
    if (scalar keys %args) {
        foreach my $p (keys %args) {
            $prop_cols{uc $p} = $args{$p};  #  upper case them
        }
    }

    my $quotes = $self->get_param ('QUOTES');  #  for storage, not import
    my $el_sep = $self->get_param ('JOIN_CHAR');

    my $csv_in  = $self->get_csv_object_using_guesswork (
        fname      => $file,
        sep_char   => $sep,
        quote_char => $input_quote_char,
        %args,
    );
    my $csv_out = $self->get_csv_object (
        sep_char => $el_sep,
        quote_char => $quotes,
    );

    my $lines_to_read_per_chunk = 50000;

    open (my $fh, '<:via(File::BOM)', $file) || croak "Cannot open file $file\n";
    
    my $lines = $self->get_next_line_set (
        progress            => $args{progress_bar},
        file_handle         => $fh,
        target_line_count   => $lines_to_read_per_chunk,
        file_name           => $file,
        csv_object          => $csv_in,
    );
    
    shift @$lines;  #  remove header
    
    my @element_order;

    while (my $FldsRef = shift @$lines) {

        if (scalar @$lines == 0) {
            $lines = $self->get_next_line_set (
                progress           => $args{progress_bar},
                file_handle        => $fh,
                file_name          => $file,
                target_line_count  => $lines_to_read_per_chunk,
                csv_object         => $csv_in,
            );
        }

        my @in_cols = @$FldsRef[@$in_cols];
        my $element = $self->list2csv (
            list       => \@in_cols,
            csv_object => $csv_out,
        );
        if (scalar @in_cols <= 1) {
            $element = $self->dequote_element (
                element    => $element,
                quote_char => $quotes,
            );
        }

        my $hash;  #  list to store the properties

        #  create the element if needed
        my $element_existed = $self->exists_element (element => $element);
        if (not $element_existed) {
            $self->add_element (
                element    => $element,
                csv_object => $csv_out,
            );
            push @element_order, $element;
        }
        else {
            #  work with the existing poperties hash - this will override any set values
            $hash = $self->get_list_ref (
                element => $element,
                list    => 'PROPERTIES',
            );
        }

        my @remap = @$FldsRef[@$out_cols];
        my $remapped = scalar @remap
                    ? $self->list2csv (
                        list       => \@remap,
                        csv_object => $csv_out,
                    )
                    : undef;

        #  check the remap value is valid (need to test for quotes?)
        my $null_entry = $el_sep x scalar @remap;
        chop $null_entry;  #  a null is all sep chars, one fewer than we have columns
        $hash->{REMAP} = $remapped unless (
            ! defined $remapped or                      #  thar's nowt there
            scalar @remap && (length ($element) == 0) or  #  one column wide, but empty
            $remapped eq $null_entry or                 #  contains only the join char
            $remapped eq $element                       #  remapping to self, no need to store
        );

        my $include;
        if (defined $include_cols and scalar @$include_cols) {
            $include = 0;  #  default to not include

            INCLUDE_COLS:
            foreach my $col (@$include_cols) {
                if (defined $FldsRef->[$col]) {
                    $include = $FldsRef->[$col];
                    last INCLUDE_COLS if $include;  #  drop out if we hit a yes
                }
            }
        }

        my $exclude;
        if (defined $exclude_cols and scalar @$exclude_cols) {

            EXCLUDE_COLS:
            foreach my $col (@$exclude_cols) {
                if (defined $FldsRef->[$col]) {
                    $exclude = $FldsRef->[$col];
                    last EXCLUDE_COLS if $exclude;    # drop out if we hit a yes
                }
            }
        }

        foreach my $prop_name (%prop_cols) {
            my $col = $prop_cols{$prop_name};
            if (defined $col) {
                my $prop = $FldsRef->[$col] ;
                #  need to allow non-numeric, but need metadata for it
                #if (defined $prop and looks_like_number $prop) {
                #  allow undefined values
                if (!defined $prop or looks_like_number $prop) {
                    $hash->{$prop_name} = $prop;
                }
            }
        }

        $hash->{INCLUDE} = $include if defined $include_cols;
        $hash->{EXCLUDE} = $exclude if defined $exclude_cols;

        #  add the properties hash to the element,
        #  unless it was already there and we've already worked
        #  on it directly, or there are no props
        if (not $element_existed and scalar keys %$hash) {
            $self->add_to_lists (element => $element, PROPERTIES => $hash);
        }
    }
    
    #  go through and cleanup any multiple node links
    #  (eg remap to remap to remap)
    foreach my $element ($self->get_element_list) {
        my @remap_history;
        my %r_hash;
        my $props = $self->get_list_ref (element => $element, list => 'PROPERTIES');

        my $props_orig = $props;
        my $element_orig = $element;

        REMAP:
        while (exists $props->{REMAP} and defined $props->{REMAP}) {
            if (exists $r_hash{$element} or $element eq $props->{REMAP}) {
                warn "Circular remap for $element_orig via path " . join (' ', @remap_history) . "\n";
                last REMAP;  #  avoid circular remaps
            }
            $r_hash{$element}++;

            $element = $props->{REMAP};
            push @remap_history, $element;

            #  drop out if we have no props for this remapped element
            last REMAP if !$self->exists_element(element => $element);

            #  get the properties of this next remapped element
            $props = $self->get_list_ref (
                element => $element,
                list    => 'PROPERTIES',
            );

            if ($#remap_history == 10) {
                warn "[BASEDATA] Element remap of >=10 interchanges\n";
            }
            elsif ($#remap_history > 20) {
                my $r_h = join (q{ }, @remap_history);
                warn "[BASEDATA] Remap exceeds 20 interchanges\n"
                     . "You might want to check your table, or you are "
                     . "working with a really contested taxonomy\n"
                     . $r_h
                     . "\n";
            }
        }
        if (scalar @remap_history) {
            $props_orig->{REMAP} = $element;
        }
    }
    
    return 1;
}

sub get_element_properties {
    my $self = shift;
    my %args = @_;
    
    my $element = $args{element};
    
    #  return an empty list if nothing there
    return wantarray ? () : {}
      if not $self->exists_element (element => $element);

    #  remap the element name if need be
    my $props = $self->get_list_ref (element => $element, list => 'PROPERTIES');
    my $remap = $self->get_element_remapped (%args);
    if (defined $remap) {
        $props = $self->exists_element (element => $remap)
            ? $self->get_list_ref (element => $remap, list => 'PROPERTIES')
            : {};
    }

    return wantarray ? %$props : $props;
}


sub get_element_remapped {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element};

    #  return an empty list if nothing there
    return if not $self->exists_element (element => $element);

    #  get the properties
    my $props = $self->get_list_ref (element => $element, list => 'PROPERTIES');
    return $props->{REMAP};
}

sub get_element_exclude {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element};

    #  return an empty list if nothing there
    return if not $self->exists_element (element => $element);

    #  get the properties
    my $props = $self->get_list_ref (element => $element, list => 'PROPERTIES');
    return $props->{EXCLUDE};
}

=head2 get_element_include

Get the value of the include field for an element. 
Returns C<undef> if none is set.

=cut

sub get_element_include {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element};
    
    #  return an empty list if nothing there
    return if not $self->exists_element (element => $element);

    #  get the properties
    my $props = $self->get_list_ref (element => $element, list => 'PROPERTIES');
    return $props->{INCLUDE};
}



sub get_element_sample_count {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element = $args{element};
    
    #  return an empty list if nothing there
    return if not $self->exists_element (element => $element);

    #  get the properties
    my $props = $self->get_list_ref (element => $element, list => 'PROPERTIES');
    return $props->{SAMPLE_COUNT};
}

sub get_element_range {
    my $self = shift;
    my %args = @_;
    
    no autovivification;

    my $element = $args{element};
    
    #  return an empty list if nothing there
    return if not $self->exists_element (element => $element);

    #  get the properties
    my $props = $self->get_list_ref (element => $element, list => 'PROPERTIES');
    return $props->{RANGE};
}

sub get_element_property {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $element  = $args{element};
    my $property = $args{property};
    croak "argument 'property' not defined\n" if not defined $property;

    #  return an empty list if nothing there
    return if not $self->exists_element (element => $element);

    #  get the properties
    my $props = $self->get_list_ref (element => $element, list => 'PROPERTIES');
    return $props->{$property};
}




sub to_table {
    my $self = shift;
    $self->SUPER::to_table (list => 'PROPERTIES', @_);
}

1;


__END__


=head1 NAME

Biodiverse::ElementProperties - class to handle remap tables and 
element properties in a Biodiverse::BaseStruct object.

=head1 SYNOPSIS

  use Biodiverse::ElementProperties;

=head1 DESCRIPTION

Package to store and manipulate properties for Biodiverse elements
(typically when loading a Biodiverse::BaseData object).

It is handled as a Biodiverse::BaseStruct object to get at
all the list and existence handlers etc.

Input is a table of elements and properties for such things as remapped element names,
exclude and include flags, ranges and sample counts (thus far).

Note that if there are multiple remaps of the element name then the system
will take the last remap set.
e.g. if the following table is used then the properties used will be
from the last row (a is remapped to b, to c and then to d)

=over

  input,remapped,range,sample_count
  a,b,,10
  b,c,5,8
  c,d,,20

=back

=head1 METHODS

Note that any remap paths like the above are evaluated after loading the data,
and that it will stop evaluating if it encounters circular paths.

=head2 import_data

Load hash keys and their values from a file.
Later values in the file will override the earlier values, so beware...

    $self->import_data (
        file => 'filename',
        input_quote_char => q{'},
        input_sep_char => q{,},
        input_element_cols => [0,1],
        remapped_element_cols => [2,3],
    );


=head2 to_table

    my $table = $self->to_table();

Convert the whole file to a table. 
Just calls Biodiverse::BaseStruct::to_table using the C<PROPERTIES> lists.

=head2 get_element_properties

    my $props = $self->get_element_properties (element => 'barry');

Get the properties for an element. 
It will return the remapped properties if a remap is set.


=head2 get_element_remapped

    my $remapped = $self->get_element_remapped (element => 'barry');

Get the value of the remap field for an element. 
Returns C<undef> if none is set.

=head2 get_element_exclude

    my $exclude = $self->get_element_exclude (element => 'barry');

Get the value of the exclude field for an element. 
Returns C<undef> if none is set.

=head2 get_element_range

    my $range = $self->get_element_range (element => 'barry');

Get the value of an element property, identified by argument "property".
Returns C<undef> if it is not set.

=head2 get_element_sample_count

    my $count = $self->get_element_sample_count (element => 'barry');

Get the value of the sample count field for an element. 
Returns C<undef> if none is set.

=head1 AUTHOR

Shawn Laffan

=head1 LICENSE

LGPL

=head1 SEE ALSO

See http://www.purl.org/biodiverse for more details.


