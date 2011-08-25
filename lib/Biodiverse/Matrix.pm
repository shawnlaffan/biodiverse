package Biodiverse::Matrix;

#  package to handle matrices for Biodiverse objects
#  these are not matrices in the proper sense of the word, but are actually hash tables to provide easier linking
#  they are also double indexed - "by pair" and "by value by pair".

use strict;
use warnings;

our $VERSION = '0.16';

use English ( -no_match_vars );

use Carp;
use Data::Dumper;
use Scalar::Util qw /looks_like_number/;
use File::BOM qw /:subs/;

my $EMPTY_STRING = q{};

#  access the miscellaneous functions as methods
use base qw /Biodiverse::Common/; 

sub new {
    my $class = shift;
    my %args = @_;
    
    my $self = bless {}, $class;
    

    # try to load from a file if the file arg is given
    my $file_loaded;
    $file_loaded = $self -> load_file (@_) if defined $args{file};
    return $file_loaded if defined $file_loaded;


    my %PARAMS = (
        OUTPFX               =>  'BIODIVERSE',
        OUTSUFFIX            => 'bms',
        OUTSUFFIX_YAML       => 'bmy',
        TYPE                 => undef,
        QUOTES               => q{'},
        JOIN_CHAR            => q{:},  #  used for labels
        ELEMENT_COLUMNS      => [1,2],  #  default columns in input file to define the names (eg genus,species).  Should not be used as a list here.
        PARAM_CHANGE_WARN    => undef,
        CACHE_MATRIX_AS_TREE => 1,
    );
    
    $self -> set_params (%PARAMS, @_);  #  load the defaults, with the rest of the args as params
    $self -> set_default_params;  #  and any user overrides

    
    $self->{BYELEMENT} = undef;  #  values indexed by elements
    $self->{BYVALUE} = undef;    #  elements indexed by value
    
    $self -> set_param (NAME => $args{name}) if defined $args{name};

    warn "[MATRIX] WARNING: Matrix name not specified\n"
        if ! defined $self -> get_param('NAME');

    return $self;
}

sub rename {
    my $self = shift;
    my %args = @_;
    
    my $name = $args{new_name};
    if (not defined $name) {
        croak "[Matrix] Argument 'new_name' not defined\n";
    }

    #  first tell the basedata object - No, leave that to the basedata object
    #my $bd = $self -> get_param ('BASEDATA_REF');
    #$bd -> rename_output (object => $self, new_name => $name);

    # and now change ourselves   
    $self -> set_param (NAME => $name);
    
}

#  need to flesh this out - total number of elements, symmetry, summary stats etc
sub describe {
    my $self = shift;
    
    my @description = (
        ['TYPE: ', blessed $self],
    );
    
    my @keys = qw /
        NAME
        JOIN_CHAR
        QUOTES
    /;

    foreach my $key (@keys) {
        my $desc = $self -> get_param ($key);
        if ((ref $desc) =~ /ARRAY/) {
            $desc = join q{, }, @$desc;
        }
        push @description,
            ["$key:", $desc];
    }

    push @description, [
        'Element count: ',
        $self -> get_element_count,
    ];

    push @description, [
        'Max value: ',
        $self -> get_max_value,
    ];
    push @description, [
        'Min value: ',
        $self -> get_min_value,
    ];
    push @description, [
        'Symmetric: ',
        ($self -> is_symmetric ? 'yes' : 'no'),
    ];

    
    my $description;
    foreach my $row (@description) {
        $description .= join "\t", @$row;
        $description .= "\n";
    }
    
    return wantarray ? @description : $description;
}


#  convert this matrix to a tree by clustering 
sub to_tree {
    my $self = shift;
    my %args = @_;
    $args{linkage_function} = $args{linkage_function} || 'link_average';
    
    if ($self -> get_param ('AS_TREE')) {  #  don't recalculate 
        return $self -> get_param ('AS_TREE');
    }
    
    my $tree = Biodiverse::Cluster -> new;
    $tree -> set_param (
        'NAME' => ($args{name}
        || $self -> get_param ('NAME') . "_AS_TREE"
        )
    );
    
    eval {
        $tree -> cluster (
            %args,
            #  need to work on a clone, as it is a destructive approach
            cluster_matrix => $self -> clone, 
        );
    };
    croak $EVAL_ERROR if $EVAL_ERROR;
    
    $self -> set_param (AS_TREE => $tree);
    
    return $tree;
}

#  wrapper for table conversions
#  should implement metadata
sub to_table {
    my $self = shift;
    my %args = @_;
    
    if ($args{type} eq 'sparse') {
        return $self -> to_table_sparse (@_);
    }
    else {
        return $self -> to_table_normal (@_);
    }
}

#  convert the matrix to a tabular array
sub to_table_normal {
    my $self = shift;
    my %args = (
        symmetric => 1,
        @_,
    );
    
    my @data;
    my @elements = sort $self -> get_elements_as_array;
    
    $data[0] = [q{}, @elements];  #  header line with blank leader
    my $i = 0;
    
    #  allow for both UL and LL to be specified
    my $ll_only = $args{lower_left}  && ! $args{upper_right};
    my $ur_only = $args{upper_right} && ! $args{lower_left}; 

    E1:
    foreach my $element1 (@elements) {
        $i++;
        $data[$i][0] = $element1;
        my $j = 0;
        
        E2:
        foreach my $element2 (@elements) {
            $j++;
            next E1 if $ll_only and $j > $i;
            next E2 if $ur_only and $j < $i;
            my $exists = $self -> element_pair_exists (
                element1 => $element1,
                element2 => $element2,
            );
            if (! $args{symmetric} && $exists == 1) {
                $data[$i][$j] = $self -> get_value (
                    element1 => $element1,
                    element2 => $element2,
                );
            }
            else {
                $data[$i][$j] = $self -> get_value (
                    element1 => $element1,
                    element2 => $element2,
                );
            }
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
    
    my @data;
    my @elements = sort $self -> get_elements_as_array;
    
    push @data, [qw /Row Column Value/];  #  header line
    
    my $i = 0;
    
    E1:
    foreach my $element1 (@elements) {
        $i++;
        #$data[$i][0] = $element1;
        my $j = 0;
        E2:
        foreach my $element2 (@elements) {
            $j++;
            next E1 if $args{lower_left}  and $j > $i;
            next E2 if $args{upper_right} and $j < $i;
            my $exists = $self -> element_pair_exists (
                element1 => $element1,
                element2 => $element2,
            );
            
            #  if we are symmetric then list it regardless, otherwise only if we have this exact pair-order
            if (($args{symmetric} and $exists) or $exists == 1) {
                my $value = $self -> get_value (
                    element1 => $element1,
                    element2 => $element2,
                );
                my $list = [$element1, $element2, $value];
                push @data, $list;
            }
        }
    }
    
    return wantarray ? @data : \@data;
}

#  this is almost identical to that in BaseStruct - refactor needed
sub get_metadata_export {
    my $self = shift;

    #  need a list of export subs
    my %subs = $self -> get_subs_with_prefix (prefix => 'export_');

    #  hunt through the other export subs and collate their metadata
    #  (not anymore)
    my @formats;
    my %format_labels;  #  track sub names by format label
    
    #  loop through subs and get their metadata
    my %params_per_sub;
    
    LOOP_EXPORT_SUB:
    foreach my $sub (sort keys %subs) {
        my %sub_args = $self -> get_args (sub => $sub);

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
    $self -> move_to_front_of_list (
        list => \@formats,
        item => 'Delimited text'
    );

    my %args = (
        parameters     => \%params_per_sub,
        format_choices => [{
                name        => 'format',
                label_text  => 'Format to use',
                type        => 'choice',
                choices     => \@formats,
                default     => 0
            },
        ],
        format_labels  => \%format_labels,
    ); 

    return wantarray ? %args : \%args;
}

sub export {
    my $self = shift;
    my %args = @_;
    
    #  get our own metadata...
    my %metadata = $self -> get_args (sub => 'export');
    
    my $sub_to_use
        = $metadata{format_labels}{$args{format}}
            || croak "Argument 'format' not specified\n";
    
    eval {$self -> $sub_to_use (%args)};
    croak $EVAL_ERROR if $EVAL_ERROR;
    
    return;
}

#  probably needs to be subdivided into normal and sparse
sub export_delimited_text {
    my $self = shift;
    my %args = @_;
    
    # add a .csv suffix if none present
    if (defined $args{file} and not $args{file} =~ /\.(.*)$/) {
        $args{file} = $args{file} . '.csv';
    }

    my $table = $self -> to_table (%args);
    eval {
        $self -> write_table (
            %args,
            data => $table
        )
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return;
}


sub get_metadata_export_delimited_text {
    my $self = shift;
    
    my @sep_chars = my @separators = defined $ENV{BIODIVERSE_FIELD_SEPARATORS}
                    ? @$ENV{BIODIVERSE_FIELD_SEPARATORS}
                    : (',', 'tab', ';', 'space', ":");
    my @quote_chars = qw /" ' + $/;
    
    my @formats = qw /normal sparse/;
    

    my %args = (
        format => 'Delimited text',
        parameters => [
            {
                name       => 'file',  # GUI supports just one of these
                type       => 'file'
            }, 
            {
                name       => 'type',
                label_text => 'output format',
                type       => 'choice',
                tooltip    => $self -> get_tooltip_sparse_normal,
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
        ]
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
END_MX_TOOLTIP
;

    return $tool_tip;
}


sub get_min_value {  #  get the minimum similarity value
    my $self = shift;
    my @array = sort numerically keys %{$self->{BYVALUE}};
    return $array[0];
}

sub get_max_value {  #  get the minimum similarity value
    my $self = shift;
    my @array = reverse sort numerically keys %{$self->{BYVALUE}};
    return $array[0];
}

#  crude summary stats.
#  Not using Biodiverse::Statistics due to memory issues
#  with large matrices and calculation of percentiles.
sub get_summary_stats {
    my $self = shift;
    
    my $n = $self->get_element_pair_count;
    my ($sumx, $sumx_sqr);
    my @percentile_targets = qw /2.5 5 95 97.5/;
    my @percentile_target_counts;
    foreach my $pct (@percentile_targets) {
        push @percentile_target_counts, $n * $pct / 100;  #  should floor it?
    }
    my %percentile_hash;

    my $count;

    my $values_hash = $self->{BYVALUE};
    BY_VALUE:
    foreach my $value (sort numerically keys %$values_hash) {
        my $hash = $values_hash->{$value};
        my $sub_count = scalar keys %$hash;
        $sumx += $value * $sub_count;
        $sumx_sqr += ($value ** 2) * $sub_count;
        $count += $sub_count;

        FIND_PCTL:
        foreach my $target (@percentile_target_counts) {
            last FIND_PCTL if $count < $target;
            my $percentile = shift @percentile_targets;
            $percentile_hash{$percentile} = $value;
            shift @percentile_target_counts;
        }
    }
    
    my $max = $self->get_max_value;
    my $min = $self->get_min_value;

    my %stats = (
        MAX => $self->get_max_value,
        MIN => $self->get_min_value,
        MEAN   => $sumx / $n,
        #SD     => undef,
        PCT025 => defined $percentile_hash{'2.5'}  ? $percentile_hash{'2.5'}  : $min,
        PCT975 => defined $percentile_hash{'97.5'} ? $percentile_hash{'97.5'} : $max,
        PCT05  => defined $percentile_hash{'5'}    ? $percentile_hash{'5'}    : $min,
        PCT95  => defined $percentile_hash{'95'}   ? $percentile_hash{'95'}   : $max,
    );
    
    return wantarray ? %stats : \%stats;
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

    if (! defined $args{value}) {
        warn "[Matrix] add_element Warning: Value not defined\n";
        return;
    }

    $self->{BYELEMENT}{$element1}{$element2} = $args{value};
    $self->{BYVALUE}{$args{value}}{$element1}{$element2}++;
    $self->{ELEMENTS}{$element1}++;  #  cache the component elements to save searching through the other lists later
    $self->{ELEMENTS}{$element2}++;  #  also keeps a count of the elements
    
    return;
}

sub delete_element {  #  should be called delete_element_pair, but need to find where it's used first
    my $self = shift;
    my %args = @_;
    croak "element1 or element2 not defined\n"
        if ! defined $args{element1}
            || ! defined $args{element2};

    my $element1 = $args{element1};
    my $element2 = $args{element2};
    my $exists = $self -> element_pair_exists (@_);

    if (! $exists) {
        #print "WARNING: element combination does not exist\n";
        return 0; #  combination does not exist - cannot delete it
    }
    elsif ($exists == 2) {  #  elements exist, but in different order - switch them
        #print "DELETE ELEMENTS SWITCHING $element1 $element2\n";
        $element1 = $args{element2};
        $element2 = $args{element1};
    }
    my $value = $self -> get_value (
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
        #undef $self->{ELEMENTS}{$element1};
        defined (delete $self->{ELEMENTS}{$element1})
            || warn "ISSUES $element1\n";
    }
    $self->{ELEMENTS}{$element2}--;
    if ($self->{ELEMENTS}{$element2} == 0) {
        #undef $self->{ELEMENTS}{$element2};
        defined (delete $self->{ELEMENTS}{$element2})
            || warn "ISSUES $element2\n";
    }
    
    return ($self -> element_pair_exists(@_)) ? undef : 1;  #  for debug
    return 1;  # return success if we get this far
}

#  check an element pair exists, returning 1 if yes, 2 if yes, but in different order, undef otherwise
sub element_pair_exists {  
    my $self = shift;
    my %args = @_;
    confess "element1 or element2 not defined\n" if ! defined $args{element1} || ! defined $args{element2};
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

#  check if the matrix contains an element with any pair
sub element_is_in_matrix { 
    my $self = shift;
    my %args = @_;
    
    croak "element not defined\n" if ! defined $args{element};

    my $element = $args{element};
    
    return $self->{ELEMENTS}{$element} if exists $self->{ELEMENTS}{$element};
    return;
}

sub is_symmetric {  #  check if the matrix is symmetric (each element has an equal number of entries)
    my $self = shift;
    
    my $prevCount = undef;
    foreach my $count (values %{$self->{ELEMENTS}}) {
        if (defined $prevCount) {
            return if $count != $prevCount;
        }
        $prevCount = $count;
    }
    return 1;  #  if we get this far then it is symmetric
}

sub get_value {  #  return the value of a pair of elements. argument checking is done by element_pair_exists.
    my $self = shift;
    my %args = @_;
    
    my ($element1, $element2);
    my $exists = $self -> element_pair_exists (@_);
    if (! $exists) {
        if ($args{element1} eq $args{element2} and $self -> element_is_in_matrix (element => $args{element1})) {
            return $self -> get_param ('SELF_SIMILARITY');  #  defaults to undef
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

sub get_elements {
    my $self = shift;

    return if ! exists $self->{ELEMENTS};
    return if (scalar keys %{$self->{ELEMENTS}}) == 0;

    return wantarray ? %{$self->{ELEMENTS}} : $self->{ELEMENTS};
}

sub get_elements_as_array {
    my $self = shift;
    return [keys %{$self->{ELEMENTS}}] if ! wantarray;
    return (keys %{$self->{ELEMENTS}});
}

sub get_element_count {
    my $self = shift;
    return 0 if ! exists $self->{ELEMENTS};
    return scalar keys %{$self->{ELEMENTS}};
}

sub get_element_pair_count {
    my $self = shift;

    my $count = 0;
    for my $value (values %{$self->{ELEMENTS}}) {
        $count += $value;
    }
    $count /= 2;  #  correct for double counting

    return $count;
}

sub get_elements_with_value {  #  returns a hash of the elements with $value
    my $self = shift;
    my %args = @_;
    
    croak "Value not specified in call to get_elements_with_value\n"
        if ! defined $args{value};
    
    my $value = $args{value};

    return if ! exists $self->{BYVALUE}{$value};
    return $self->{BYVALUE}{$value} if ! wantarray;
    return %{$self->{BYVALUE}{$value}};
}

sub get_element_values {  #  get all values associated with one element
    my $self = shift;
    my %args = @_;
    
    croak "element not specified (matrix)\n"  if ! defined $args{element};
    croak "matrix element does not exist\n" if ! $self -> element_is_in_matrix (element => $args{element});
    
    
    my @elements = $self -> get_elements_as_array;
    
    my %values;
    foreach my $el (@elements) {
        if ($self -> element_pair_exists (element1 => $el, element2 => $args{element})) {
            $values{$el} = $self -> get_value (element1 => $el, element2 => $args{element});
        }
    }
    
    return wantarray ? %values : \%values;    
}

#  clear all pairs containing this element.
#  should properly be delete_element, but it's already used
sub delete_all_pairs_with_element {  
    my $self = shift;
    my %args = @_;
    
    croak "element not specified\n" if ! defined $args{element};
    croak "element does not exist\n" if ! $self -> element_is_in_matrix (element => $args{element});
    
    my @elements = $self -> get_elements_as_array;
    foreach my $el (@elements) {
        if ($self -> element_pair_exists (
                element1 => $el,
                element2 => $args{element})
            ) {

            $self -> delete_element (
                element1 => $el,
                element2 => $args{element},
            );
        }
    }
    
    return;
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

    my $input_quotes = $args{input_quotes};
    if (! defined $input_quotes) {  #  guess the quotes character
        $input_quotes = $self -> guess_quote_char (string => \$whole_file);
        #  if all else fails...
        $input_quotes = $self -> get_param ('QUOTES') if ! defined $input_quotes;
    }

    my $IDcount = 0;
    my %labelList;
    my %labelInMatrix;
    my $out_sep_char = $self->get_param('JOIN_CHAR');
    my $out_quote_char = $self->get_param('QUOTES');
    
    my $in_csv = $self -> get_csv_object (
        sep_char    => $in_sep_char,
        quote_char  => $input_quotes
    );
    my $out_csv = $self -> get_csv_object (
        sep_char    => $out_sep_char,
        quote_char  => $out_quote_char
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
    my $text_allowed = $self -> get_param ('ALLOW_TEXT');
    my $label_count = 0;
    foreach my $flds_ref (@data) {
        
        BY_FIELD:
        foreach my $i (@cols_to_use) {
            #print "Using column $i\n";
            #  Skip if not defined.  Need the first check because these are getting assigned in csv2list
            next BY_FIELD if ! defined $flds_ref->[$i];
            next BY_FIELD if $flds_ref->[$i] eq $EMPTY_STRING;  
            next BY_FIELD if ! $text_allowed && ! looks_like_number ($flds_ref->[$i]);
            
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
                value    => $flds_ref->[$i],
            );
        }
        $label_count ++;
    }

    return;
}

sub numerically {$a <=> $b};

1;


__END__

=head1 NAME

Biodiverse::Matrix - Methods to build, access and control matrix data
for a Biodiverse project.

=head1 SYNOPSIS

  use Biodiverse::Matrix;

=head1 DESCRIPTION

Store a matrix of values (normally dissimilarity) in the Biodiverse
internal format. 

=head2 Assumptions

Assumes C<Biodiverse::Common> is in the @ISA list.

Almost all methods in the Biodiverse library use {keyword => value} pairs as a policy.
This means some of the methods may appear to contain unnecessary arguments,
but it makes everything else more consistent.

List methods return a list in list context, and a reference to that list
in scalar context.

=head1 Methods

These assume you have declared an object called $self of a type that
inherits these methods, normally:

=over 4

=item  $self = Biodiverse::Matrix->new;

=back



=over 5

=item $self = Biodiverse::Matrix->new (%params);

Create a new matrices object.

Optionally pass a hash of parameters to be set.

If %params contains an item 'file_xml' then it attempts to open the file
referred to and returns that as an object if successful
(see C<Biodiverse::Common::load_xml_file>).

=item $self->add_element('element1' => $element1, 'element2' => $element2, 'value' => $value);

Adds an element pair and their value to the object.

=item $self->delete_element ('element1' => $element1, 'element2' => $element2);

Deletes an element pair and their value from the matrix.

=item $self->element_pair_exists ('element1' => $element1, 'element2' => $element2);

Returns 1 if the pair exists in the specified order, 2 if they exist but are
transposed, and 0 if they do not exist.  The values 1 and 2 allow the
other methods to refer to the appropriate internal data structure
and would normally be treated as the same by standard users.

=item $self->get_element_count;

Returns a count of the number of elements along one side of the matrix.
This is not the count of the total number of entries, but this could
be calculated if one assumes it is symmetric, does not contain
diagonal elements and so forth.

=item $self->get_elements;

Returns a hash of the unique elements indexed in the matrix.

=item $self->get_elements_as_array;

Returns an array of the unique elements indexed in the matrix.

=item $self->get_elements_with_value('value' => $value);

Returns a hash of element pairs in the matrix that have the specified
value.

=item $self->get_min_value;

Returns the minimum value in the matrix.

=item $self->get_max_value;

Returns the maximum value in the matrix.

=item $self->get_value ('element1' => $element1, 'element2' => $element2);

Returns the value for element pair [$element1, $element2].

=item $self->load_data;

Import data from a file.  Assumes data are symmetric amongst other things.

Really messy.  Needs cleaning up. 

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

=item Version 0.09

May 2006.  Source libraries developed to the point where they can be
distributed.

=back

=cut
