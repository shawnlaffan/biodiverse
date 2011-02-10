package Biodiverse::BaseStruct;

#  Package to provide generic methods for the
#  GROUPS and LABELS sub components of a Biodiverse object,
#  and also for the SPATIAL ones
#  These share the same structure, so should share methods.
#  In fact, all coordinate data are stored using this format.
#  Need to modify all the original BaseData stuff to
#  use lists instead of values at the top.

#  Need a mergeElements method

use strict;
use warnings;
use Carp;

use English ( -no_match_vars );

#use Data::DumpXML qw{dump_xml};
use Data::Dumper;
use Scalar::Util qw/looks_like_number/;
use File::Spec;
use File::Basename;
#use Time::HiRes qw /tv_interval gettimeofday/;
#use Biodiverse::Progress;

our $VERSION = '0.16';

#require Biodiverse::Config;
#my $progress_update_interval = $Biodiverse::Config::progress_update_interval;

my $EMPTY_STRING = q{};


use base qw ( Biodiverse::Common ); #  access the common functions as methods


sub new {
    my $class = shift;

    my $self = bless {}, $class;

    my %args = @_;
    
    # do we have a file to load from?
    my $file_loaded;
    if ( defined $args{file} ) {
        $self -> load_file( @_ );
    };
    return $file_loaded if defined $file_loaded;

    #  default parameters to load.  These will be overwritten if needed.
    my %params = (  
        OUTPFX              =>  'BIODIVERSE_BASESTRUCT',
        OUTSUFFIX           => 'bss',
        #OUTSUFFIX_XML      => "bsx",
        OUTSUFFIX_YAML      => 'bsy',
        TYPE                => undef,
        OUTPUT_QUOTE_CHAR   => q{"},
        OUTPUT_SEP_CHAR     => q{,},   #  used for output data strings
        QUOTES              => q{'},
        JOIN_CHAR           => q{:},   #  used for labels and groups
        #INDEX_CONTAINS     => 4,  #  average number of basestruct elements per index element
        PARAM_CHANGE_WARN   => undef,
    );

    #  load the defaults, with the rest of the args as params
    my @args_for = (%params, @_);
    $self -> set_params (@args_for);
    
    # predeclare the ELEMENT subhash (don't strictly need to do it...)
    $self->{ELEMENTS} = {};  
    
    #  avoid memory leak probs with circular refs
    $self -> weaken_basedata_ref;

    return $self;
}

sub rename {
    my $self = shift;
    my %args = @_;
    
    my $name = $args{new_name};
    if (not defined $name) {
        croak "[Basestruct] Argument 'new_name' not defined\n";
    }

    #  first tell the basedata object - No, leave that to the basedata object
    #my $bd = $self -> get_param ('BASEDATA_REF');
    #$bd -> rename_output (object => $self, new_name => $name);

    # and now change ourselves   
    $self -> set_param (NAME => $name);
    
}

#  metadata is bigger than the actual sub...
sub get_metadata_export {
    my $self = shift;

    #  get the available lists
    #my @lists = $self -> get_lists_for_export;

    #  need a list of export subs
    my %subs = $self -> get_subs_with_prefix (prefix => 'export_');

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

# export to a file
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

sub get_common_export_metadata {
    my $self = shift;
    
    #  get the available lists
    my @lists = $self -> get_lists_for_export;
    
    my $metadata = [
        {
            name => 'file',
            type => 'file'
        }, # GUI supports just one of these
        {
            name        => 'list',
            label_text  => 'List to export',
            type        => 'choice',
            choices     => \@lists,
            default     => 0
        }
    ];
    
    return wantarray ? @$metadata : $metadata;
}

sub get_table_export_metadata {
    my $self = shift;
    
    my @no_data_values = qw /undef 0 -9 -9999 -99999/;
    my @sep_chars
        = defined $ENV{BIODIVERSE_FIELD_SEPARATORS}
            ? @$ENV{BIODIVERSE_FIELD_SEPARATORS}
            : (',', 'tab', ';', 'space', ':');

    my @quote_chars = qw /" ' + $/;
    
    my $table_metadata_defaults = [
        {
            name       => 'symmetric',
            label_text => 'Force symmetric (matrix) format',
            tooltip    => 'Rectangular matrix, one row per element (group)',
            type       => 'boolean',
            default    => 1
        },
        {
            name       => 'one_value_per_line',
            label_text => "One value per line",
            tooltip    => 'Sparse matrix, repeats elements for each value',
            type       => 'boolean',
            default    => 0
        },
        {
            name       => 'sep_char',
            label_text => 'Field separator',
            tooltip    => 'Suggested options are comma for .csv files, tab for .txt files',
            type       => 'choice',
            choices    => \@sep_chars,
            default    => 0
        },
        {
            name       => 'quote_char',
            label_text => 'Quote character',
            tooltip    => 'For delimited text exports only',
            type       => 'choice',
            choices    => \@quote_chars,
            default    => 0
        },
        {
            name       => 'no_data_value',
            label_text => 'NoData value',
            tooltip    => 'Zero is not a safe value to use for nodata in most '
                        . 'cases, so be warned',
            type       => 'choice',
            choices    => \@no_data_values,
            default    => 0,
        },   
     ];

    return wantarray ? @$table_metadata_defaults : $table_metadata_defaults;
}

sub get_metadata_export_table_delimited_text {
    my $self = shift;
    
    my %args = (
        format => 'Delimited text',
        parameters => [
            $self -> get_common_export_metadata(),
            $self -> get_table_export_metadata()
        ],
    ); 
    
    return wantarray ? %args : \%args;
}

#  generic - should be factored out
sub export_table_delimited_text {
    my $self = shift;
    my %args = @_;
    
    my $table = $self -> to_table (symmetric => 1, %args);

    $self -> write_table_csv (%args, data => $table);
    
    return;
}

sub get_metadata_export_table_html {
    my $self = shift;
    
    my %args = (
        format => 'HTML table',
        parameters => [
            $self -> get_common_export_metadata(),
            $self -> get_table_export_metadata()
        ],
    ); 
    
    return wantarray ? %args : \%args;
}

sub export_table_html {
    my $self = shift;
    my %args = @_;
    
    my $table = $self -> to_table (%args, symmetric => 1);

    $self -> write_table_html (%args, data => $table);
    
    return;
}

sub get_metadata_export_table_xml {
    my $self = shift;

    
    my %args = (
        format => 'XML table',
        parameters => [
            $self -> get_common_export_metadata(),
            $self -> get_table_export_metadata()
        ],
    ); 
    
    return wantarray ? %args : \%args;
}

sub export_table_xml {
    my $self = shift;
    my %args = @_;
    
    my $table = $self -> to_table (%args, symmetric => 1);

    $self -> write_table_xml (%args, data => $table);
    
    return;
}

sub get_metadata_export_table_yaml {
    my $self = shift;
    
    my %args = (
        format => 'YAML table',
        parameters => [
            $self -> get_common_export_metadata(),
            $self -> get_table_export_metadata()
        ],
    ); 

    return wantarray ? %args : \%args;    
}

sub export_table_yaml {
    my $self = shift;
    my %args = @_;
    
    my $table = $self -> to_table (%args, symmetric => 1);

    $self -> write_table_yaml (%args, data => $table);
    
    return;
}

sub get_raster_export_metadata {
    my $self = shift;
    
    my @no_data_values = qw /undef 0 -9 -9999 -99999/;
    
    my $table_metadata_defaults = [ 
        {
            name        => 'no_data_value',
            label_text  => 'NoData value',
            tooltip    => 'Zero is not a safe value to use for nodata in most '
                        . 'cases, so be warned',
            type        => 'choice',
            choices     => \@no_data_values,
            default     => 0
        },   
    ];

    return wantarray ? @$table_metadata_defaults : $table_metadata_defaults;
}


sub get_metadata_export_ers {
    my $self = shift;
    
    my %args = (
        format => 'ER-Mapper BIL file',
        parameters => [
            $self -> get_common_export_metadata(),
            $self -> get_raster_export_metadata(),
        ],
    ); 

    return wantarray ? %args : \%args;
}

sub export_ers {
    my $self = shift;
    my %args = @_;
    
    my $table = $self -> to_table (%args, symmetric => 1);
    
    $self -> write_table_ers (%args, data => $table);
    
    return;
}


sub get_metadata_export_asciigrid {
    my $self = shift;
    
    my %args = (
        format => 'ArcInfo asciigrid files',
        parameters => [
            $self -> get_common_export_metadata(),
            $self -> get_raster_export_metadata(),
        ],
    ); 
    
    return wantarray ? %args : \%args;
}

sub export_asciigrid {
    my $self = shift;
    my %args = @_;
    
    my $table = $self -> to_table (%args, symmetric => 1);
    
    $self -> write_table_asciigrid (%args, data => $table);
    
    return;
}

sub get_metadata_export_floatgrid {
    my $self = shift;
    
    my %args = (
        format => 'ArcInfo floatgrid files',
        parameters => [
            $self -> get_common_export_metadata(),
            $self -> get_raster_export_metadata(),
        ],
    ); 
    
    return wantarray ? %args : \%args;
}

sub export_floatgrid {
    my $self = shift;
    my %args = @_;
    
    my $table = $self -> to_table (%args, symmetric => 1);
    
    $self -> write_table_floatgrid (%args, data => $table);
    
    return;
}


sub get_lists_for_export {
    my $self = shift;
    
    #  get the available lists
    my $lists = $self -> get_lists_across_elements (no_private => 1);
    
    #  sort appropriately
    my @lists;
    foreach my $list (sort @$lists) {
        next if $list =~ /^_/;
        
        if ($list eq 'SPATIAL_RESULTS') {
            unshift @lists, $list;  #  put at the front
        }
        else {
            push @lists, $list;  #  put at the end
        }
    }
    
    return wantarray ? @lists : \@lists;
}

#  handler for the available set of structures.
sub write_table {
    my $self = shift;
    my %args = @_;
    defined $args{file} || croak "file argument not specified\n";
    my $data = $args{data} || croak "data argument not specified\n";
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
    
    $args{file} = File::Spec->rel2abs ($args{file});
    
    #  now do stuff depending on what format was chosen, based on the suffix
    #my ($prefix, $suffix) = lc ($args{file}) =~ /(.*?)\.(.*?)$/;
    #if (! defined $suffix) {
    #    $suffix = "csv";  #  does not affect the actual file name, as it is not passed onwards
    #}
    
    #if ($suffix =~ /asc/i) {
    #    $self -> write_table_asciigrid (%args, symmetric => 1);
    #}
    #elsif ($suffix =~ /flt/i) {
    #    $self -> write_table_floatgrid (%args, symmetric => 1);
    #}
    #elsif ($suffix =~ /ers/i) {
    #    $self -> write_table_ers (%args, symmetric => 1);
    #}
    #else {
        $self -> SUPER::write_table (%args);
    #}
}

#  control whether a file is written symetrically or not
sub to_table {
    my $self = shift;
    my %args = @_;
    #  modify to make the default, rather than required
    #my $file = $args{file} || ($self->get_param('OUTPFX') . ".csv");  
    my $as_symmetric = $args{symmetric} || 0;
    
    croak "[BaseStruct] argument 'list' not specified\n"
      if !defined $args{list}; 

    my $list = $args{list};
    
    my $checkElements = $self -> get_element_list;
    #my $list_type = ref ($self->get_list_values (element => $checkElements->[0], list => $list));
    
    #  check if the file is symmetric or not.  Check the list type as well.
    my $last_contents_count = -1;
    my $is_asym = 0;
    my %list_keys;
    my $prev_list_keys;
    
    print "[BASESTRUCT] Checking elements for list contents\n";
    CHECK_ELEMENTS:
    foreach my $i (0 .. $#$checkElements) {  # sample the lot
        my $checkElement = $checkElements->[$i];
        last CHECK_ELEMENTS if ! defined $checkElement;
        
        my $values = $self -> get_list_values (element => $checkElement, list => $list);
        if ((ref $values) =~ /HASH/) {
            if (defined $prev_list_keys and $prev_list_keys != scalar keys %$values) {
                $is_asym ++;  #  This list is of different length from the previous.  Allows for zero length lists.
                last CHECK_ELEMENTS;
            }
            $prev_list_keys = scalar keys %$values if ! defined $prev_list_keys;
            @list_keys{keys %$values} = values %$values;
        }
        elsif ((ref $values) =~ /ARRAY/) {
            $is_asym = 1;  #  arrays are always treated as asymmetric
            last CHECK_ELEMENTS;
        }
        
        #  increment if not first check and keys differ from previous run
        $is_asym ++ if $i && $last_contents_count != scalar keys %list_keys;
        
        #  This list has different keys.
        #  Allows for lists of same length but different keys.
        last CHECK_ELEMENTS if $is_asym;
        
        $last_contents_count = scalar keys %list_keys;
    }
    
    my $data;
    
    if (! $as_symmetric and $is_asym) {
        print "[BASESTRUCT] Converting asymmetric data from $list "
              . "to asymmetric table\n";
        $data = $self -> to_table_asym (%args);
    }
    elsif ($as_symmetric && $is_asym) {
        print "[BASESTRUCT] Converting asymmetric data from $list "
              . "to symmetric table\n";
        $data = $self -> to_table_asym_as_sym (%args);
    }
    else {
        print "[BASESTRUCT] Converting symmetric data from $list "
              . "to symmetric table\n";
        $data = $self -> to_table_sym (%args);
    }
    
    return wantarray ? @$data : $data;
    
}

#  write parts of the object to a CSV file
#  assumes these are always hashes, which may blow
#  up in our faces later.  We'll fix it then
sub to_table_sym {  
    my $self = shift;
    my %args = @_;
    defined $args{list} || croak "list not defined\n";

    my @data;
    my @elements = sort $self->get_element_list;
    
    my $listHashRef = $self->get_hash_list_values(
        element => $elements[0],
        list    => $args{list},
    );
    my @print_order = sort keys %$listHashRef;

    #  need the number of element components for the header
    my @header = ('Element');  

    if (! $args{no_element_array}) {
        my $i = 0;
        #  get the number of element columns
        my $name_array =
          $self -> get_element_name_as_array (element => $elements[0]);
        
        foreach my $null (@$name_array) {  
            push (@header, 'Axis_' . $i);
            $i++;
        }
    }
    
    if ($args{one_value_per_line}) {
        push @header, qw /Key Value/;
    }
    else {
        push @header, @print_order;
    }
    push @data, \@header;

    #  now add the data to the array
    foreach my $element (@elements) {
        my @basic = ($element);
        if (! $args{no_element_array}) {
            push @basic,
              ($self -> get_element_name_as_array (element => $element));
        }
        
        my $listRef = $self->get_hash_list_values(
            element => $element,
            list    => $args{list},
        );

        #  we've built the hash, now print it out

        if ($args{one_value_per_line}) {  
            #  repeat the elements, once for each value or key/value pair
            foreach my $key (@print_order) {
                push @data, [@basic, $key, $listRef->{$key}];
            }
        }
        else {
            push @data, [@basic, @{$listRef}{@print_order}];
        }
    }

    return wantarray ? @data : \@data;
}


sub to_table_asym {  #  get the data as an asymmetric table
    my $self = shift;
    my %args = @_;
    defined $args{list} || croak "list not specified\n";
    my $list = $args{list}; 

    my @data;  #  2D array to hold the data
    my @elements = sort $self->get_element_list;

    push my @header, "ELEMENT";  #  need the number of element components for the header
    if (! $args{no_element_array}) {
        my $i = 0;
        foreach my $null (@{$self -> get_element_name_as_array (element => $elements[0])}) {  #  get the number of element columns
            push (@header, "Axis_$i");
            $i++;
        }
    }
    
    if ($args{one_value_per_line}) {
        push @header, qw /Key Value/;
    }
    else {
        push @header, "Value";
    }
    push @data, \@header;

    foreach my $element (@elements) {
        my @basic = ($element);
        push @basic, ($self->get_element_name_as_array (element => $element)) if ! $args{no_element_array};
        #  get_list_values returns a list reference in scalar context - could be a hash or an array
        my $list =  $self -> get_list_values (element => $element, list => $list);
        if ($args{one_value_per_line}) {  #  repeats the elements, once for each value or key/value pair
            if ((ref $list) =~ /ARRAY/) {
                foreach my $value (@$list) {
                    push @data, [@basic, $value];  #  preserve internal ordering - useful for extracting iteration based values
                }
            }
            elsif ((ref $list) =~ /HASH/) {
                my %hash = %$list;
                foreach my $key (sort keys %hash) {
                    push @data, [@basic, $key, $hash{$key}];
                }
            }
            #else {  #  we have a scale - probably undef so treat it as such
                #  atually, don't do anything for the moment.
            #}
        }
        else {
            my @line = @basic;
            if ((ref $list) =~ /ARRAY/) {
                push @line, @$list;  #  preserve internal ordering - useful for extracting iteration based values
            }
            elsif ((ref $list) =~ /HASH/) {
                my %hash = %$list;
                foreach my $key (sort keys %hash) {
                    push @line, ($key, $hash{$key});
                }
            }
            push @data, \@line;
        }
    }
    
    return wantarray ? @data : \@data;
}


sub to_table_asym_as_sym {  #  write asymmetric lists to a symmetric format
    my $self = shift;
    my %args = @_;
    defined $args{list} || croak "list not specified\n";
    my $list = $args{list}; 
    
    # Get all possible indices by sampling all elements
    # - this allows for asymmetric lists
    my $elements = $self -> get_element_hash();
    my %indices_hash;
    
    print "[BASESTRUCT] Getting keys...\n";
    BY_ELEMENT1:
    foreach my $elt (keys %$elements) {
            my $sub_list = $elements->{$elt}{$list};
            if ((ref $sub_list) =~ /ARRAY/) {
                @indices_hash{@$sub_list} = (undef) x scalar @$sub_list;
            }
            elsif ((ref $sub_list) =~ /HASH/) {
                @indices_hash{keys %$sub_list} = (undef) x scalar keys %$sub_list;
            }
    }
    my @print_order = sort keys %indices_hash;

    my @data;
    my @elements = sort keys %$elements;
    
    push my @header, "ELEMENT";  #  need the number of element components for the header
    if (! $args{no_element_array}) {
        my $i = 0;
        foreach my $null (@{$self->get_element_name_as_array(element => $elements[0])}) {  #  get the number of element columns
            push (@header, "Axis_$i");
            $i++;
        }
    }

    #push (@header, @print_order);
    if ($args{one_value_per_line}) {
        push @header, qw /Key Value/;
    }
    else {
        push @header, @print_order;
    }
    push @data, \@header;
    
    #  allows us to pass text "undef"
    my $no_data = defined $args{no_data} ? eval $args{no_data_value} : undef;  

    print "[BASESTRUCT] Processing elements...\n";
    
    BY_ELEMENT2:
    foreach my $element (@elements) {
        my @basic = ($element);
        push @basic, ($self->get_element_name_as_array (element => $element)) if ! $args{no_element_array};
        my $list = $self->get_hash_list_values (element => $element, list => $list);
        my %data_hash = %indices_hash;
        @data_hash{keys %data_hash} = ($no_data) x scalar keys %data_hash;  #  initialises with undef by default
        if ((ref $list) =~ /ARRAY/) {
            @data_hash{@$list} = (1) x scalar @$list;
        }
        elsif ((ref $list) =~ /HASH/) {
            @data_hash{keys %$list} = values %$list;
        }
        
        #  we've built the hash, now print it out
        if ($args{one_value_per_line}) {  #  repeats the elements, once for each value or key/value pair
            foreach my $key (@print_order) {
                push @data, [@basic, $key, $data_hash{$key}];
            }
        }
        else {
            push @data, [@basic, @data_hash{@print_order}];
        }
    }
    
    return wantarray ? @data : \@data;
}

#  write a table out as a series of ESRI asciigrid files, one per field based on row 0.
#  skip any that contain non-numeric values
sub write_table_asciigrid {
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";

    my $file = $args{file} || croak "file arg not specified\n";
    my ($name, $path, $suffix) = fileparse (File::Spec->rel2abs($file), '.asc', '.txt');
    $suffix = '.asc' if ! defined $suffix || $suffix eq q{};  #  clear off the trailing .asc and store it

    #  now process the generic stuff
    my $r = $self -> raster_export_process_args ( %args );

    my @min       = @{$r->{MIN}};
    my @max       = @{$r->{MAX}};
    my %data_hash = %{$r->{DATA_HASH}};
    my @precision = @{$r->{PRECISION}};
    my @band_cols = @{$r->{BAND_COLS}};
    my $header    =   $r->{HEADER};
    my $no_data   =   $r->{NODATA};
    my @res       = @{$r->{RESOLUTIONS}};

    my %coord_cols_hash = %{$r->{COORD_COLS_HASH}};

    
    my @fh;  #  file handles
    my @file_names;
    foreach my $i (@band_cols) {
        next if $coord_cols_hash{$i};  #  skip if it is a coordinate
        
        my $this_file = $name . "_" . $header->[$i];
        $this_file = $self->escape_filename (string => $this_file);

        my $filename = File::Spec->catfile ($path, $this_file);
        $filename .= $suffix;
        $file_names[$i] = $filename;

        my $fh;
        my $success = open ($fh, '>', $filename);
        croak "Cannot open $filename\n"
          if ! $success;
        
        $fh[$i] = $fh;
        print $fh "nrows ", int (0.5 + (($max[1] - $min[1]) / $res[1] + 1)), "\n";
        print $fh "ncols ", int (0.5 + (($max[0] - $min[0]) / $res[0] + 1)), "\n";
        print $fh "xllcenter $min[0]\n";
        print $fh "yllcenter $min[1]\n";
        print $fh "cellsize $res[0]\n";  #  CHEATING 
        print $fh "nodata $no_data\n";
    }

    my %coords;
    my @default_line = ($no_data x scalar @$header);
    for (my $y = $max[1]; $y >= $min[1]; $y -= $res[1]) {  #  y then x
        
        #  avoid float precision issues
        $y = $self -> set_precision (
            precision => "%.$precision[0]f",
            value     => $y
        );  
        
        for (my $x = $min[0]; $x <= $max[0]; $x += $res[0]) {
        
            $x = $self -> set_precision (
                precision => "%.$precision[0]f",
                value     => $x
            );
            
            my $coord_name = join (':', $x, $y);
            foreach my $i (@band_cols) {
                next if $coord_cols_hash{$i};  #  skip if it is a coordinate
                my $value = defined $data_hash{$coord_name}[$i]
                          ? $data_hash{$coord_name}[$i]
                          : $no_data;
                my $ofh = $fh[$i];
                print $ofh "$value ";
            }
        }
        #  end of lines
        foreach my $i (@band_cols) { 
            #next if $coord_cols_hash{$i};  #  skip if it is a coordinate
            my $fh = $fh[$i];
            print $fh "\n";
        }
    }
    
    FH:
    for (my $i = 0; $i <= $#fh; $i++) {
        my $fh = $fh[$i];

        next if ! defined $fh;

        if (close $fh) {
            print "[BASESTRUCT] Write to file $file_names[$i] successful\n";
        }
        else {
            print "[BASESTRUCT] Write to file $file_names[$i] failed\n";
        }

    }
    
    return;
}

#  write a table out as a series of ESRI floatgrid files,
#  one per field based on row 0.
#  Skip any fields that contain non-numeric values
sub write_table_floatgrid {
    my $self = shift;
    my %args = @_;
    
    my $data = $args{data} || croak "data arg not specified\n";
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
    
    my $file = $args{file} || croak "file arg not specified\n";
    my ($name, $path, $suffix) = fileparse (File::Spec->rel2abs($file), '.flt');
    $suffix = '.flt' if ! defined $suffix || $suffix eq q{};  #  clear off the trailing .flt and store it

    #  now process the generic stuff
    my $r = $self -> raster_export_process_args ( %args );

    my @min       = @{$r->{MIN}};
    my @max       = @{$r->{MAX}};
    my %data_hash = %{$r->{DATA_HASH}};
    my @precision = @{$r->{PRECISION}};
    my @band_cols = @{$r->{BAND_COLS}};
    my $header    =   $r->{HEADER};
    my $no_data   =   $r->{NODATA};
    my @res       = @{$r->{RESOLUTIONS}};

    my %coord_cols_hash = %{$r->{COORD_COLS_HASH}};


    #  are we LSB or MSB?
    my $is_little_endian = unpack( 'c', pack( 's', 1 ) );
    
    my @fh;  #  file handles
    my @file_names;
    foreach my $i (@band_cols) {
        #next if $coord_cols_hash{$i};  #  skip if it is a coordinate
        my $this_file = $name . "_" . $header->[$i];
        $this_file = $self->escape_filename (string => $this_file);

        my $filename = File::Spec->catfile ($path, $this_file);
        $filename .= $suffix;
        $file_names[$i] = $filename;

        my $fh;
        my $success = open ($fh, '>', $filename);
        croak "Cannot open $filename\n"
          if ! $success;
        
        binmode $fh;
        $fh[$i] = $fh;

        my $header_file = $filename;
        $header_file =~ s/$suffix$/\.hdr/;
        $success = open (my $fh_hdr, '>', $header_file);
        croak "Cannot open $header_file\n" if ! $success;

        print $fh_hdr 'nrows ', int (0.5 + (($max[1] - $min[1]) / $res[1] + 1)), "\n";
        print $fh_hdr 'ncols ', int (0.5 + (($max[0] - $min[0]) / $res[0] + 1)), "\n";
        print $fh_hdr "xllcenter $min[0]\n";
        print $fh_hdr "yllcenter $min[1]\n";
        print $fh_hdr "cellsize $res[0]\n"; 
        print $fh_hdr "nodata $no_data\n";
        print $fh_hdr 'BYTEORDER ',
                      ($is_little_endian ? 'LSBFIRST' : 'MSBFIRST'),
                      "\n";
        $fh_hdr -> close;
    }

    my %coords;
    my @default_line = ($no_data x scalar @$header);
    for (my $y = $max[1]; $y >= $min[1]; $y -= $res[1]) {  #  y then x

        #$y = sprintf "%.$precision[0]f", $y;  #  avoid float precision issues
        $y = $self -> set_precision (
            precision => "%.$precision[1]f",
            value     => $y,
        );

        for (my $x = $min[0]; $x <= $max[0]; $x += $res[0]) {

            #$x = sprintf "%.$precision[0]f", $x;
            $x = $self -> set_precision (
                precision => "%.$precision[0]f",
                value     => $x,
            );

            my $coord_name = join (':', $x, $y);
            foreach my $i (@band_cols) { 
                next if $coord_cols_hash{$i};  #  skip if it is a coordinate
                my $value = defined $data_hash{$coord_name}[$i]
                          ? $data_hash{$coord_name}[$i]
                          : $no_data;
                my $fh = $fh[$i];
                print $fh pack ('f', $value);
            }
        }
    }

    FH:
    for (my $i = 0; $i <= $#fh; $i++) {
        my $fh = $fh[$i];

        next FH if ! defined $fh;

        if (close $fh) {
            print "[BASESTRUCT] Write to file $file_names[$i] successful\n";
        }
        else {
            print "[BASESTRUCT] Write to file $file_names[$i] failed\n";
        }
    }
    
    return;
}

#  write a table out as an ER-Mapper ERS BIL file.
sub write_table_ers {
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
    my $file = $args{file} || croak "file arg not specified\n";

    my ($name, $path, $suffix)
        = fileparse (File::Spec->rel2abs($file), '.ers');

    #  add suffix if not specified
    if (!defined $suffix || $suffix eq q{}) {
        $suffix = '.ers';
    }

    #  now process the generic stuff
    my $r = $self -> raster_export_process_args ( %args );

    my @min       = @{$r->{MIN}};
    my @max       = @{$r->{MAX}};
    my %data_hash = %{$r->{DATA_HASH}};
    my @precision = @{$r->{PRECISION}};
    my @band_cols = @{$r->{BAND_COLS}};
    my $header    =   $r->{HEADER};
    my $no_data   =   $r->{NODATA};
    my @res       = @{$r->{RESOLUTIONS}};

    my %coord_cols_hash = %{$r->{COORD_COLS_HASH}};

    #my %stats;

    my $data_file = File::Spec->catfile ($path, $name);
    my $success = open (my $ofh, '>', $data_file);
    if (! $success) {
        croak "Could not open output file $data_file\n";
    }
    binmode $ofh;

    my ($ncols, $nrows) = (0, 0);
    for (my $y = $max[1]; $y >= $min[1]; $y -= $res[1]) {

        $y = $self -> set_precision (
            precision => "%.$precision[1]f",
            value     => $y,
        );

        $nrows ++;
        foreach my $band (@band_cols) {
            $ncols = 0;

            for (my $x = $min[0]; $x <= $max[0]; $x += $res[0]) {

                #$x = sprintf "%.$precision[0]f", $x;
                $x = $self -> set_precision (
                    precision => "%.$precision[0]f",
                    value     => $x,
                );

                my $ID = "$x:$y";
                my $value = $data_hash{$ID}[$band];

                if (not defined $value) {
                    $value = $no_data;
                    #$stats{$band}{NumberOfNullCells} ++;
                }

                eval {
                    print $ofh pack ('f', $value);
                };
                croak $EVAL_ERROR if $EVAL_ERROR;

                $ncols ++;
                #print "$ID, $value\n" if $band == $band_cols[0];
            }
        }
    }

    if (! close $ofh) {
        croak "Unable to write to $data_file\n";
    }
    else {
        print "[BASESTRUCT] Write to file $data_file successful\n";
    }

    #  are we LSB or MSB?
    my $is_little_endian = unpack( 'c', pack( 's', 1 ) );
    my $LSB_or_MSB = $is_little_endian ? "LSBFIRST" : "MSBFIRST";
    my $gm_time = (gmtime);
    $gm_time =~ s/(\d+)$/GMT $1/;  #  insert "GMT" before the year
    my $n_bands = scalar @band_cols;
    my @reg_coords = (
        #$min[0] - ($res[0] / 2),
        #$max[1] + ($res[1] / 2),
        $min[0], $max[1],
    );
    
    #  The RegistrationCell[XY] values should be 0.5,
    #  but 0 plots properly in ArcMap

    my $header_start =<<"END_OF_ERS_HEADER_START"
DatasetHeader Begin
\tVersion         = "5.5"
\tName		= "$name$suffix"
\tLastUpdated     = $gm_time
\tDataSetType     = ERStorage
\tDataType        = Raster
\tByteOrder       = $LSB_or_MSB
\tCoordinateSpace Begin
\t\tDatum           = "Unknown"
\t\tProjection      = "Unknown"
\t\tCoordinateType  = EN
\t\tRotation        = 0:0:0.0
\tCoordinateSpace End
\tRasterInfo Begin
\t\tCellType        = IEEE4BYTEREAL
\t\tNullCellValue = $no_data
\t\tCellInfo Begin
\t\t\tXdimension      = $res[0]
\t\t\tYdimension      = $res[1]
\t\tCellInfo End
\t\tNrOfLines       = $nrows
\t\tNrOfCellsPerLine        = $ncols
\t\tRegistrationCoord Begin
\t\t\tEastings        = $reg_coords[0]
\t\t\tNorthings       = $reg_coords[1]
\t\tRegistrationCoord End
\t\tRegistrationCellX  = 0
\t\tRegistrationCellY  = 0
\t\tNrOfBands       = $n_bands
END_OF_ERS_HEADER_START
;

    my @header = $header_start;
    
    #  add the band info
    foreach my $i (@band_cols) {
        push @header, (
            qq{\t\tBandId Begin},
            qq{\t\t\tValue           = "}
              . $self->escape_filename(string => $header->[$i])
              . qq{"},
            qq{\t\tBandId End},
        );
    }
    

    
    push @header, (
        "\tRasterInfo End",
        "DatasetHeader End"
    );
    
    my $header_file = File::Spec->catfile ($path, $name) . $suffix;
    open (my $header_fh, '>', $header_file)
      || croak "Could not open header file $header_file\n";

    print $header_fh join ("\n", @header), "\n";
    
    if (! close $header_fh) {
        croak "Unable to write to $header_file\n";
    }
    else {
        print "[BASESTRUCT] Write to file $header_file successful\n";
    }
    
    return;
}

#  This is here for posterity and to declutter write_table_ers.
#  It does not need to be used as any software
#  using the file will normally calculate teh stats itself.
#  It also needs to be interleaved with the other code if it is ever put back.
#sub ers_stats {
                #if (not defined $value) {
                #    $value = $no_data;
                #    #$stats{$band}{NumberOfNullCells} ++;
                #}
                #else {
                #    $stats{$band}{sum_x} += $value;
                #    $stats{$band}{sum_x_sqr} += $value ** 2;
                #    $stats{$band}{NumberOfNonNullCells} ++;
                #    $stats{$band}{MaximumValue} = defined $stats{$band}{MaximumValue}
                #        ? max ($stats{$band}{MaximumValue}, $value)
                #        : $value;
                #    $stats{$band}{MinimumValue} = defined $stats{$band}{MinimumValue}
                #        ? min ($stats{$band}{MinimumValue}, $value)
                #        : $value;
                #}

    ###  turn off stats for now - they can be calculated by using programs
    #  process the stats
    #my %stats_summary;
    #my @stats_types = qw /
    #    NumberOfNonNullCells
    #    NumberOfNullCells
    #    MeanValue
    #    MinimumValue
    #    MaximumValue
    #/;

    #my @means = (undef) x (scalar @res + 1);  #  first cols are coord stuff
    #foreach my $band (@band_cols) {
    #    $stats{$band}{MeanValue} = eval {
    #        $stats{$band}{sum_x} / $stats{$band}{NumberOfNullCells}
    #    };
    #    foreach my $type (@stats_types) {
    #        $stats_summary{$type} .= "$stats{$band}{$type}\t";
    #        if ($type eq 'MeanValue') {
    #            push @means, $stats{$band}{$type};
    #        }
    #    }
    #}


        ###  turn off stats
#    #  add the stats
#    my $stats_leader =<<"END_OF_ERS_STATS_LEADER"
#\t\tRegionInfo Begin
#\t\t\tType                = Polygon
#\t\t\tRegionName        = "All"
#\t\t\tRGBcolour Begin
#\t\t\t\tRed          = 65535
#\t\t\t\tGreen        = 65535
#\t\t\t\tBlue         = 65535
#\t\t\tRGBcolour End
#\t\t\tSubRegion        = {
#\t\t\t\t0        0
#\t\t\t\t0        $nrows
#\t\t\t\t$ncols        $nrows
#\t\t\t\t$ncols        0
#\t\t\t}
#\t\t\tStats Begin
#\t\t\t\tSubsampleRate        = 1
#\t\t\t\tNumberOfBands        = $n_bands
#END_OF_ERS_STATS_LEADER
#;
#
#    my @stats = ($stats_leader);
#    
#    foreach my $type (@stats_types) {
#        push @stats, (
#            "\t\t\t\t$type        = {",
#            "\t\t\t\t\t$stats_summary{$type}",
#            "\t\t\t\t}",
#        );
#    }
#
#    my $covariance = $self -> get_covariance_from_table (
#        data    => $data,
#        fields  => \@band_cols,
#        means   => \@means,
#        as_text => 1,
#        prefix  => "\t\t\t\t\t",
#    );
#
#    push @stats, (
#        "\t\t\t\tCovarianceMatrix\t= {",
#        $covariance,
#        "\t\t\t\t}",
#        "\t\t\tStats End",
#        "\t\tRegionInfo End",
#    );
#    
#    push @header, @stats;
#}

sub raster_export_process_args {
    my $self = shift;
    my %args = @_;
    my $data = $args{data};

    my @axes_to_use = (0,1);

    my $no_data = defined $args{no_data_value}
                ? eval $args{no_data_value}
                : undef;

    if (! defined $no_data) {
        $no_data = -9999 ;
        print "[BASESTRUCT] Overriding undefined no_data_value with -9999\n";
    }

    my @res = defined $args{resolutions}
            ? @{$args{resolutions}}
            : @{$self -> get_param ('CELL_SIZES')};

    #  check the resolutions.
    eval {
        $self->raster_export_test_axes_validity (
            resolutions => [@res[@axes_to_use]],
        );
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    my @coord_cols = $self->raster_export_get_coord_cols (%args);
    my %coord_cols_hash;
    @coord_cols_hash{@coord_cols} = @coord_cols;

    my $header = shift @$data;
    my $data_start_col = (scalar @res) + 1;  #  first three columns are ID, followed by coords
    my @band_cols = ($data_start_col .. $#$header);  

    my $res = $self->raster_export_process_table (
        data       => $data,
        coord_cols => \@coord_cols,
        res        => \@res,
    );
    
    #  add some more keys to $res
    $res->{HEADER}          = $header;
    $res->{BAND_COLS}       = \@band_cols;
    $res->{NODATA}          = $no_data;
    $res->{RESOLUTIONS}     = \@res; 
    $res->{COORD_COLS_HASH} = \%coord_cols_hash;

    return wantarray ? %$res : $res;
}


sub raster_export_test_axes_validity {
    my $self = shift;
    my %args = @_;
    my @resolutions = @{$args{resolutions}};
    
    my $i = 0;
    foreach my $r (@resolutions) {

        croak "[BASESTRUCT] Cannot export text axes to raster, axis $i\n"
          if $r < 0;

        croak "[BASESTRUCT] Cannot export point axes to raster, axis $i\n"
          if $r == 0;

        $i++;
    }
    
    return 1;
}

sub raster_export_get_coord_cols {
    my $self = shift;
    my %args = @_;

    my @coord_cols = defined $args{coord_cols} ? @{$args{coord_cols}} : (1,2);
    
    return wantarray ? @coord_cols : \@coord_cols;
}

sub raster_export_process_table {
    my $self = shift;
    my %args = @_;

    my $data = $args{data};
    my @coord_cols = @{$args{coord_cols}};
    my @res = @{$args{res}};

    #  loop through and get the min and max coords,
    #  as well as converting the array to a hash
    my @min = ( 10e20, 10e20);
    my @max = (-10e20,-10e20);
    my %data_hash;
    foreach my $line (@$data) {
        my @coord = @$line[@coord_cols];
        $min[0] = min ($min[0], $coord[0]);
        $min[1] = min ($min[1], $coord[1]);
        $max[0] = max ($max[0], $coord[0]);
        $max[1] = max ($max[1], $coord[1]);
        $data_hash{join (':', @coord)} = $line;
    }

    my @precision = (0, 0);
    #  check the first 1000 for precision
    #  - hopefully enough to allow for alternating 1, 1.5, 2 etc
    my $lines_to_check = $#$data < 1000 ? $#$data : 1000;
    
    LINE:
    foreach my $line (@$data[0 .. $lines_to_check]) {  

        my @coord = @$line[@coord_cols];

        COORD:
        foreach my $i (0 .. $#coord) {
            $coord[$i] =~ /\.(\d+)$/;
            my $val = $1;
            next COORD if !defined $val;

            my $len = length ($val);
            if ($precision[$i] < $len) {
                $precision[$i] = $len;
            }
        }
    }

    print "[BASESTRUCT] Data bounds are $min[0], $min[1], $max[0], $max[1]\n";
    print "[BASESTRUCT] Resolutions are $res[0], $res[1]\n";
    print "[BASESTRUCT] Coordinate precisions are $precision[0], $precision[1]\n";

    my %res = (
        MIN       => \@min,
        MAX       => \@max,
        DATA_HASH => \%data_hash,
        PRECISION => \@precision,
    );

    return wantarray ? %res : \%res;
}

#  get the covariance matrix for a table of values
sub get_covariance_from_table {
    my $self = shift;
    my %args = @_;

    my $data = $args{data};
    my $flds  = $args{fields};
    my $means = $args{means};

    my $prefix = $args{prefix};  #  for as_text

    if (! defined $flds) {
        my $first_line = $data->[0];
        $flds = [0.. $#$first_line];
    }
    
    my @sums;
    my @counts;
    
    foreach my $line (@$data) {
        my $ii = -1;

        PASS1:
        foreach my $i (@$flds) {
            $ii ++;
            next PASS1 if ! defined $line->[$i];

            my $jj = -1;

            PASS2:
            foreach my $j (@$flds) {
                $jj ++;
                next PASS2 if ! defined $line->[$j];
                $sums[$ii][$jj] += ($line->[$i] - $means->[$i]) * ($line->[$j] - $means->[$j]);
                $counts[$ii][$jj] ++;
            }
        }
    }

    my @covariance;
    
    foreach my $row (0 .. $#$flds) {
        foreach my $col (0 .. $#$flds) {
            $covariance[$row][$col] = $counts[$row][$col]
                ? $sums[$row][$col] / $counts[$row][$col]
                : 0;
        }
    }

    if ($args{as_text}) {
        my $string;
        foreach my $row (@covariance) {
            $string .= $prefix . join ("\t", @$row) . "\n";
        }
        $string =~ s/\n$//;  #  strip trailing newline
        return $string;
    }

    return wantarray ? @covariance : \@covariance;
}


#  convert the elements to a tree format, eg family - genus - species
#  won't make sense for many types of basedata, but oh well.  
sub to_tree {
    my $self = shift;
    my %args = @_;
    
    my $name = $args{name};
    if (not defined $name) {
        $name = $self -> get_param ('NAME') . "_AS_TREE";
    }
    my $tree = Biodiverse::Tree -> new (NAME => $name);
    
    my $elements = $self -> get_element_hash;
    
    my $quotes = $self -> get_param ('QUOTES');  #  for storage, not import
    my $el_sep = $self -> get_param ('JOIN_CHAR');
    my $csv_obj = $self -> get_csv_object (
        sep_char   => $el_sep,
        quote_char => $quotes,
    );
    
    foreach my $element (keys %$elements) {
        my @components = $self -> get_element_name_as_array (element => $element);
        #my @so_far;
        my @prev_names = ();
        #for (my $i = 0; $i <= $#components; $i++) {
        foreach my $i (0 .. $#components) {
            #$so_far[$i] = $components[$i];
            my $node_name = $self -> list2csv (
                csv_object  => $csv_obj,
                list        => [@components[0..$i]],
            );
            
            my $parent_name = $i ? $prev_names[$i-1] : undef;  #  no parent if at highest level
            
            if (not $tree -> node_is_in_tree (node => $node_name)) {
                my $node = $tree -> add_node (
                    name   => $node_name,
                    length => 1,
                );
                
                if ($parent_name) {
                    my $parent_node = $tree -> get_node_ref (node => $parent_name);
                    #  create the parent if need be - SHOULD NOT HAPPEN
                    #if (not defined $parent_node) {
                    #    $parent_node = $tree -> add_node (name => $parent_name, length => 1);
                    #}
                    #  now add the child with the element as the name so we can link properly to the basedata in labels tab
                    $node -> set_parent (parent => $parent_node);
                    $parent_node -> add_children (children => [$node]);
                }
            }
            #push @so_far, $node_name;
            $prev_names[$i] = $node_name;
        }
    }
    
    #  set a master root node of length zero if we have more than one.
    #  All the current root nodes will be its children
    my $root_nodes = $tree -> get_root_node_refs;
    #if (scalar @$root_nodes > 1) {
        my $root_node = $tree -> add_node (name => '0___', length => 0);
        $root_node -> add_children (children => [@$root_nodes]);
        foreach my $node (@$root_nodes) {
            $node -> set_parent (parent => $root_node);
        }
    #}
    
    $tree -> set_parents_below;  #  run a clean up just in case
    return $tree;
}



sub get_element_count {
    my $self = shift;
    my $el_hash = $self->{ELEMENTS};
    return scalar keys %$el_hash;
}

sub get_element_list {
    my $self = shift;
    return wantarray
            ? keys %{$self->{ELEMENTS}}
            : [keys %{$self->{ELEMENTS}}];
}

sub sort_by_axes {
    my $self = shift;
    my $a = shift;
    my $b = shift;
    
    my $axes = $self -> get_param ('CELL_SIZES');
    my $res = 0;
    my $a_array = $self->get_element_name_as_array (element => $a);
    my $b_array = $self->get_element_name_as_array (element => $b);
    foreach my $i (0 .. $#$axes) {
        $res = $axes->[$i] < 0
            ? $a_array->[$i] cmp $b_array->[$i]
            : $a_array->[$i] <=> $b_array->[$i];

        return $res if $res;
    }

    return $res;
};

#  get a list sorted by the axes
sub get_element_list_sorted {
    my $self = shift;
    my %args = @_;
    
    my @list = $args{list} ? @{$args{list}} : $self -> get_element_list;
    my @array = sort {$self -> sort_by_axes ($a, $b)} @list;

    return wantarray ? @array : \@array;
}



sub get_element_hash {
    my $self = shift;
    
    my $elements = $self->{ELEMENTS};
    
    return wantarray ? %$elements : $elements;
}

sub get_element_name_as_array {
    my $self = shift;
    my %args = @_;

    croak "element not specified\n"
      if !defined $args{element};
    
    my $element = $args{element};
    
    return $self -> get_array_list_values (
        element => $element,
        list    => '_ELEMENT_ARRAY',
    );
}

#  get a list of the unique values for one axis
sub get_unique_element_axis_values {
    my $self = shift;
    my %args = @_;
    
    my $axis = $args{axis};
    croak "get_unique_element_axis_values: axis arg not defined\n"
      if !defined $axis;
    
    my %values;
    
    ELEMENT:
    foreach my $element ($self -> get_element_list) {
        my $coord_array
          = $self->get_element_name_as_array (element => $element);

        croak "not enough axes\n" if !exists ($coord_array->[$axis]);

        $values{$coord_array->[$axis]} ++;
    }
    
    return wantarray ? keys %values : [keys %values];
}


#  get a coordinate for the element
#  allows us to handle text axes for display
sub get_element_name_coord {
    my $self = shift;
    my %args = @_;
    defined $args{element} || croak "element not specified\n";
    my $element = $args{element};
    
    my $values = $self -> get_array_list_values (element => $element, list => '_ELEMENT_COORD');
    
    if (! defined $values) {  #  doesn't exist, so generate it 
        $self -> generate_element_coords;
        $values = $self -> get_element_name_coord (element => $element);
    }
    
    return wantarray ? @$values : $values;
}

#  generate the coords
sub generate_element_coords {
    my $self = shift;
    
    $self -> delete_param ('AXIS_LIST_ORDER');  #  force recalculation for first one
    
    my @is_text;
    foreach my $element ($self -> get_element_list) {
        my $element_coord = [];  #  make a copy
        my $cell_sizes = $self -> get_param ('CELL_SIZES');
        my $element_array = $self -> get_array_list_values (element => $element, list => '_ELEMENT_ARRAY');
        
        foreach my $i (0 .. $#$cell_sizes) {
            if ($cell_sizes->[$i] >= 0) {
                $element_coord->[$i] = $element_array->[$i];
            }
            else {
                $element_coord->[$i] = $self -> get_text_axis_as_coord (axis => $i, text => $element_array->[$i]);
            }
        }
        $self->{ELEMENTS}{$element}{_ELEMENT_COORD} = $element_coord;
    }

    return 1;
}

sub get_text_axis_as_coord {
    my $self = shift;
    my %args = @_;
    my $axis = $args{axis};
    my $text = $args{text};
    
    #  store the axes as an array of hashes with value being the coord
    my $lists = $self -> get_param ('AXIS_LIST_ORDER') || [];
    
    if (! $args{recalculate} and defined $lists->[$axis]) {  #  we've already done it, so return what we have
        return $lists->[$axis]{$text};
    }
    
    my %this_axis;
    #  go through and get a list of all the axis text
    foreach my $element (sort $self -> get_element_list) {
        my $axes = $self -> get_element_name_as_array (element => $element);
            $this_axis{$axes->[$axis]}++;
    }
    #  assign a number based on the sort order.  "z" will be lowest, "a" will be highest
    @this_axis{reverse sort keys %this_axis} = (0 .. scalar keys %this_axis);
    $lists->[$axis] = \%this_axis;
    
    $self -> set_param (AXIS_LIST_ORDER => $lists);
    
    return $lists->[$axis]{$text};
}


sub get_sub_element_list {
    my $self = shift;
    my %args = @_;
    
    croak "element not specified\n"
        if ! defined $args{element};
    
    my $element = $args{element};
    
    return if ! exists $self->{ELEMENTS}{$element};
    return if ! exists $self->{ELEMENTS}{$element}{SUBELEMENTS};
    
    return wantarray ?  keys %{$self->{ELEMENTS}{$element}{SUBELEMENTS}}
                     : [keys %{$self->{ELEMENTS}{$element}{SUBELEMENTS}}]
                     ;
}

sub get_sub_element_hash {
    my $self = shift;
    my %args = (@_);
    
    croak "argument 'element' not specified\n"
        if ! defined $args{element};

    my $element = $args{element};

    #croak "element and/or subelement hash does not exist\n"

    if (exists $self->{ELEMENTS}{$element}
        && exists $self->{ELEMENTS}{$element}{SUBELEMENTS}) {

        my $hash = $self->{ELEMENTS}{$element}{SUBELEMENTS};
    
        return wantarray
            ? %$hash
            : $hash;
    }

    #  should really croak on this, but some calling code expects empty lists
    #  (which chould be changed)
    return wantarray ? () : {};
}

sub get_subelement_count {
    my $self = shift;
    
    my %args = @_;
    my $element = $args{element};  croak "argument 'element' not defined\n" if ! defined $element;
    my $sub_element = $args{sub_element};  croak "argument 'sub_element' not defined\n" if ! defined $sub_element;
    
    if (exists $self->{ELEMENTS}{$element} && exists $self->{ELEMENTS}{$element}{SUBELEMENTS}{$sub_element}) {
        return $self->{ELEMENTS}{$element}{SUBELEMENTS}{$sub_element};
    }
    else {
        return;
    }
    
}


#  add an element to a baseStruct object
sub add_element {  
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if ! defined $args{element};
    
    return if $self -> exists_element (@_);  #  don't re-create

    my $element = $args{element};
    my $quote_char = $self->get_param('QUOTES');
    my $elementListRef = $self->csv2list(
        string     => $element,
        sep_char   => $self->get_param('JOIN_CHAR'),
        quote_char => $quote_char,
        csv_object => $args{csv_object},
    );

    for (my $i = 0; $i <= $#$elementListRef; $i ++) {
        if (! defined $elementListRef->[$i]) {
            $elementListRef->[$i] = ($quote_char . $quote_char);
        }
    }

    $self->{ELEMENTS}{$element}{_ELEMENT_ARRAY} = $elementListRef;

    return;
}


sub add_sub_element {  #  add a subelement to a BaseStruct element.  create the element if it does not exist
    my $self = shift;
    my %args = (count => 1, @_);

    croak "element not specified\n" if ! defined $args{element};
    croak "subelement not specified\n" if ! defined $args{subelement};
    my $element = $args{element};
    my $subElement = $args{subelement};
    
    if (! exists $self->{ELEMENTS}{$element}) {
        $self -> add_element (
            element    => $element,
            csv_object => $args{csv_object},
        );
    }
    
    #  previous base_stats invalid - clear them if needed
    if (exists $self->{ELEMENTS}{$element}{BASE_STATS}) {
        delete $self->{ELEMENTS}{$element}{BASE_STATS};
    }

    $self->{ELEMENTS}{$element}{SUBELEMENTS}{$subElement} += $args{count};
    
    return;
}

#  delete the element, return a list of fully cleansed elements
sub delete_element {  
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if ! defined $args{element};

    my $element = $args{element};

    my @deletedSubElements =
        $self->get_sub_element_list(element => $element);

    %{$self->{ELEMENTS}{$element}{SUBELEMENTS}} = ();
    %{$self->{ELEMENTS}{$element}} = ();
    delete $self->{ELEMENTS}{$element};

    return wantarray ? @deletedSubElements : \@deletedSubElements;
}

#  remove a sub element label or group from within
#  a group or label element.
#  Usually called when deleting a group or label element
#  in a related object.
sub delete_sub_element {  
    my $self = shift;
    my %args = (@_);

    croak "element not specified\n" if ! defined $args{element};
    croak "subelement not specified\n" if ! defined $args{subelement};
    my $element = $args{element};
    my $subElement = $args{subelement};
    
    return if ! exists $self->{ELEMENTS}{$element};

    if (exists $self->{ELEMENTS}{$element}{BASE_STATS}) {
        delete $self->{ELEMENTS}{$element}{BASE_STATS}{REDUNDANCY};  #  gets recalculated if needed
        delete $self->{ELEMENTS}{$element}{BASE_STATS}{VARIETY};
        if (exists $self->{ELEMENTS}{$element}{BASE_STATS}{SAMPLECOUNT}) {
            $self->{ELEMENTS}{$element}{BASE_STATS}{SAMPLECOUNT} -= $self->{ELEMENTS}{$element}{SUBELEMENTS}{$subElement};
        }
    }
    if (exists $self->{ELEMENTS}{$element}{SUBELEMENTS}) {
        delete $self->{ELEMENTS}{$element}{SUBELEMENTS}{$subElement};
    }
}

sub exists_element {
    my $self = shift;
    my %args = @_;
    
    defined $args{element} || croak "element not specified\n";
    
    return exists $self->{ELEMENTS}{$args{element}};
}

sub exists_sub_element {
    my $self = shift;

    return if ! $self -> exists_element (@_);  #  no point going further if element doesn't exist
    
    my %args = @_;
    
    defined $args{element} || croak "Argument 'element' not specified\n";
    defined $args{subelement} || croak "Argument 'subelement' not specified\n";
    my $element = $args{element};
    my $subelement = $args{subelement};
    
    return if not exists $self->{ELEMENT}{$element}{SUBELEMENTS};  #  don't autovivify
    return exists $self->{ELEMENT}{$element}{SUBELEMENTS}{$subelement};
}

sub add_values {  #  add a set of values and their keys to a list in $element
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};
    delete $args{element};

    foreach my $key (keys %args) {  #  we could assign it directly, but this ensures everything is uppercase
        $self->{ELEMENTS}{$element}{uc($key)} = $args{$key};
    }
}

sub increment_values {  #  increment a set of values and their keys to a list in $element
    my $self = shift;
    my %args = @_;
    defined $args{element} || croak "element not specified";
    my $element = $args{element};
    delete $args{element};

    #  we could assign it directly, but this ensures everything is uppercase
    foreach my $key (keys %args) {  
        $self->{ELEMENTS}{$element}{uc($key)} += $args{$key};
    }

    return;
}

sub get_list_values {
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};
    my $list = $args{list};

    croak "List not defined\n" if ! defined $list;
    croak "Element does not exist\n" if ! exists $self->{ELEMENTS}{$element};
    return if ! exists $self->{ELEMENTS}{$element}{$list};

    return $self->{ELEMENTS}{$element}{$list} if ! wantarray;
    
    #  need to return correct type in list context
    return %{$self->{ELEMENTS}{$element}{$list}}
      if ref($self->{ELEMENTS}{$element}{$list}) =~ /HASH/;

    return sort @{$self->{ELEMENTS}{$element}{$list}}
      if ref($self->{ELEMENTS}{$element}{$list}) =~ /ARRAY/;
}

sub get_hash_list_values {
    my $self = shift;
    my %args = @_;
    
    my $element = $args{element};
    croak "element not specified\n" if not defined $element;

    my $list = $args{list};
    croak  "list not specified\n" if not defined $list;

    croak "element does not exist\n" if ! exists $self->{ELEMENTS}{$element};

    return if ! exists $self->{ELEMENTS}{$element}{$list};

    croak "list is not a hash\n"
      if ! ref($self->{ELEMENTS}{$element}{$list}) =~ /HASH/;

    return wantarray
        ? %{$self->{ELEMENTS}{$element}{$list}}
        : $self->{ELEMENTS}{$element}{$list};
}


sub get_array_list_values {
    my $self = shift;
    my %args = @_;
    
    my $element = $args{element};
    
    croak "Element not specified\n"
      if not defined $element;

    my $list = $args{list};
    croak  "List not specified\n"
      if not defined $list;

    croak "Element $element does not exist.  Do you need to rebuild the spatial index?\n"
      if ! exists $self->{ELEMENTS}{$element};
    
    return if ! exists $self->{ELEMENTS}{$element}{$list};
    
    croak "List is not an array\n"
      if ! ref($self->{ELEMENTS}{$element}{$list}) =~ /ARRAY/;

    return wantarray
        ? @{$self->{ELEMENTS}{$element}{$list}}
        : $self->{ELEMENTS}{$element}{$list};
}


#  does a list exist in an element?
#  if so then return its type
sub exists_list {
    my $self = shift;
    my %args = @_;
    
    croak "element not specified\n" if not defined $args{element};
    croak "list not specified\n" if not defined $args{list};
    
    if (exists $self->{ELEMENTS}{$args{element}}{$args{list}}) {
        return ref $self->{ELEMENTS}{$args{element}}{$args{list}};
    }

    return;
}


sub add_lists {
    my $self = shift;
    my %args = @_;
    
    croak "element not specified\n" if not defined $args{element};
    
    my $element = $args{element};
    
    delete $args{element};
    @{$self->{ELEMENTS}{$element}}{keys %args} = values %args;
    
    return;
}

sub add_to_array_lists {
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    
    my $element = $args{element};
    
    delete $args{element};
    foreach my $key (keys %args) {
        push @{$self->{ELEMENTS}{$element}{$key}}, @{$args{$key}};
    }
    
    return;
}

sub add_to_hash_list {
    my $self = shift;
    my %args = @_;

    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};

    defined $args{list} || croak "List not specified\n"; 
    my $list = $args{list};

    delete @args{qw /list element/};
    #  create it if not already there
    $self->{ELEMENTS}{$element}{$list} = {}
      if ! exists $self->{ELEMENTS}{$element}{$list};

    #  now add to it
    $self->{ELEMENTS}{$element}{$list}
      = {%{$self->{ELEMENTS}{$element}{$list}}, %args};
    
    return;
}

sub add_to_lists {  #  add to a list, create if not already there.
    my $self = shift;
    my %args = @_;
    
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};
    delete $args{element};
    
    my $use_ref = $args{use_ref};  #  set a direct ref?  currently overrides any previous values so take care
    delete $args{use_ref};  #  should it be in its own sub?
    
    while ((my $list_name, my $list_values) = each %args) {
        if ($use_ref) {
            $self->{ELEMENTS}{$element}{$list_name} = $list_values;
        }
        elsif ((ref $list_values) =~ /HASH/) {
            $self->{ELEMENTS}{$element}{$list_name} = {}
              if ! exists $self->{ELEMENTS}{$element}{$list_name};

            $self->{ELEMENTS}{$element}{$list_name}
              = {%{$self->{ELEMENTS}{$element}{$list_name}}, %{$list_values}};
        }
        elsif ((ref $list_values) =~ /ARRAY/) {
            $self->{ELEMENTS}{$element}{$list_name} = []
              if ! exists $self->{ELEMENTS}{$element}{$list_name};

            push @{$self->{ELEMENTS}{$element}{$list_name}}, @{$list_values};
        }
        else {
            croak "no valid list ref passed to add_to_lists, %args\n";
        }
    }
    
    return;
}

sub delete_lists {
    my $self = shift;
    my %args = @_;
    
    croak "element not specified\n" if not defined $args{element};
    croak "argument 'lists' not specified\n" if not defined $args{lists};
    
    my $element = $args{element};
    my $lists = $args{lists};
    croak "argument 'lists' is not an array ref\n" if not (ref $lists) =~ /ARRAY/;
    
    foreach my $list (@$lists) {
        delete $self->{ELEMENTS}{$element}{$list};
    }
    
    return;
}

sub get_lists {
    my $self = shift;
    my %args = @_;

    croak "[BaseStruct] element not specified\n"
      if not defined $args{element};
    croak "[BaseStruct] element $args{element} does not exist\n"
      if !$self->exists_element (@_);

    my $element = $args{element};
    
    my @list;
    foreach my $tmp (keys %{$self->{ELEMENTS}{$element}}) {
        push @list, $tmp if ref($self->{ELEMENTS}{$element}{$tmp}) =~ /ARRAY|HASH/;
    }
    
    return @list if wantarray;
    return \@list;
}

sub clear_lists_across_elements_cache {
    my $self = shift;
    $self -> set_param (LISTS_ACROSS_ELEMENTS => undef);
}


#  get a list of all the lists in all the elements
#  up to $args{max_search}
sub get_lists_across_elements {
    my $self = shift;
    my %args = @_;
    my $max_search = $args{max_search} || $self -> get_element_count;
    my $no_private = $args{no_private};
    my $rerun = $args{rerun};
    
    #my $progress_bar = Biodiverse::Progress->new();
    
    croak "max_search arg is negative\n" if $max_search < 0;
    
    #  get from cache
    my $cached_list = $self -> get_param ('LISTS_ACROSS_ELEMENTS');
    my $cached_list_max_search
        = $self -> get_param ('LISTS_ACROSS_ELEMENTS_LAST_MAX_SEARCH');

    my $last_update_time = $self -> get_last_update_time;

    if (!defined $last_update_time) {  #  store for next time
        $self->set_last_update_time (time - 10); # ensure older given time precision
    }

    my $last_cache_time
        = $self -> get_param ('LISTS_ACROSS_ELEMENTS_LAST_UPDATE_TIME')
          || time;

    my $time_diff = defined $last_update_time
                    ? $last_cache_time - $last_update_time
                    : -1;

    if (1 
        && defined $cached_list                     #  return cache
        && ! $rerun
        && defined $cached_list_max_search          #  if it exists and
        && $time_diff > 0                           #  was updated after $self
        && $cached_list_max_search >= $max_search   #  the max search was
        ) {                                         #  the same or bigger
        
        #print "[BASESTRUCT] Using cached list items\n";
        return (wantarray ? @$cached_list : $cached_list);   
    }
    
    #print "[BASESTRUCT] Searching for list items across $max_search elements\n";
    
    my $elements = $self -> get_element_hash;
    
    my %tmp_hash;
    my $count = 0;
    #my $timer = [gettimeofday];
    
    SEARCH_FOR_LISTS:
    foreach my $elt (keys %$elements) {
        
        my $list = $self -> get_hash_lists (element => $elt);
        if (scalar @$list) {
            @tmp_hash{@$list} = (1) x scalar @$list;
        }
        $count++;
        last SEARCH_FOR_LISTS if $count > $max_search;
    }
    
    #print join (':', keys %tmp_hash), "\n";
    
    #  remove private lists if needed
    if ($no_private) {
        foreach my $key (keys %tmp_hash) {
            if ($key =~ /^_/) {  #  not those starting with an underscore
                delete $tmp_hash{$key};
            }
        }
    }
    my @lists = keys %tmp_hash;
    
    #  cache
    $self->set_params (
        LISTS_ACROSS_ELEMENTS                  => \@lists,
        LISTS_ACROSS_ELEMENTS_LAST_MAX_SEARCH  => $max_search,
        LISTS_ACROSS_ELEMENTS_LAST_UPDATE_TIME => $last_cache_time,
    );

    #print join (':', keys %tmp_hash), "\n";

    return wantarray ? @lists : \@lists;
}

#  get a list of hash lists with numeric values in them
#  ignores undef values
sub get_numeric_hash_lists {  
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};
    
    my %lists;
    LIST:
    foreach my $list ($self -> get_hash_lists (element => $element)) {
        $lists{$list} = 1;
        foreach my $value (values %{$self->get_list_values(element => $element, list => $list)}) {
            next if ! defined $value ;
            if (! looks_like_number ($value)) {
                $lists{$list} = 0;
                next LIST;
            }
        }
    }
    
    return wantarray
            ? %lists
            : \%lists;
}


sub get_array_lists {
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};
    
    #  this will blow up anything expecting a list that is requesting non-existent elements - for debugging reasons
    return if ! $self -> exists_element (element => $args{element});
    
    my @list;
    foreach my $tmp (keys %{$self->{ELEMENTS}{$element}}) {
        push @list, $tmp if ref($self->{ELEMENTS}{$element}{$tmp}) =~ /ARRAY/;
    }
    return @list if wantarray;
    return \@list;
}

sub get_hash_lists {
    my $self = shift;
    my %args = @_;
    defined $args{element} || croak "Element not specified, get_hash_lists\n";
    my $element = $args{element}; 
    my @list;

    croak "Element does not exist\n" if ! $self -> exists_element (element => $element);
    #if ($self -> exists_element (element => $element)) {
        foreach my $tmp (keys %{$self->{ELEMENTS}{$element}}) {
            push @list, $tmp if ref($self->{ELEMENTS}{$element}{$tmp}) =~ /HASH/;
        }
    #}
    return wantarray ? @list : \@list;
}

sub get_list_ref {  #  return a reference to the specified list - allows for direct operation on its values
    my $self = shift;
    my %args = (
        autovivify => 1,
        @_,
    );

    croak "Argument 'list' not defined\n" if ! defined $args{list};
    croak "Argument 'element' not defined\n" if ! defined $args{element};
    
    croak "Element $args{element} does not exist"
      if ! $self -> exists_element (element => $args{element});
    
    my $el = $self->{ELEMENTS}{$args{element}};
    if (! exists $el->{$args{list}}) {
        return if ! $args{autovivify};  #  should croak?
        $el->{$args{list}} = {};  #  should we default to a hash?
    }
    return $el->{$args{list}};
}

sub get_sample_count {
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};
    
    return if ! $self -> exists_element (element => $args{element});

    my $count = 0;
    foreach my $subElement ($self->get_sub_element_list(element => $element)) {
        $count += $self->{ELEMENTS}{$element}{SUBELEMENTS}{$subElement};
    }

    return $count;
}

sub get_variety {
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};
    
    return if not $self -> exists_element (element => $args{element});
    #my $el = $self->{ELEMENTS}{$element};  #  for debug
    return scalar keys %{$self->{ELEMENTS}{$element}{SUBELEMENTS}};
}

sub get_redundancy {
    my $self = shift;
    my %args = @_;
    croak "element not specified\n" if not defined $args{element};
    my $element = $args{element};

    return if ! $self -> exists_element (element => $args{element});

    my $redundancy = eval {1 - $self -> get_variety (element => $element) / $self -> get_sample_count (element => $element)};
    
    return $redundancy;
}

#  calculate basestats for all elements - poss redundant now there are indices that do this
sub get_base_stats_all {
    
    my $self = shift;
    
    foreach my $element ($self->get_element_list) {
        $self->add_lists (
            element =>$element,
            BASE_STATS => $self->calc_base_stats(element =>$element)
        );
    }
    
    return;
}


sub get_metadata_get_base_stats {
    my $self = shift;

    #  types are for GUI's benefit - should really add a guessing routine instead
    my $types = [
        {VARIETY       => 'Int'},
        {SAMPLES       => 'Uint'},
        {REDUNDANCY    => 'Double'},
    ];

    my $property_keys = $self->get_element_property_keys;
    foreach my $property (@$property_keys) {
        push @$types, {$property => 'Double'};
    }

    return wantarray ? @$types : $types;
}


sub get_base_stats {  #  calculate basestats for a single element
    my $self = shift;
    my %args = @_;
    
    defined $args{element} || croak "element not specified\n";
    
    my $element = $args{element};
    
    my %stats = (
        VARIETY    => $self -> get_variety      (element => $element),
        SAMPLES    => $self -> get_sample_count (element => $element),
        REDUNDANCY => $self -> get_redundancy   (element => $element),
    );

    #  get all the user defined properties
    my $props = $self->get_list_ref (
        element    => $element,
        list       => 'PROPERTIES',
        autovivify => 0,
    );

    PROP:
    foreach my $prop (keys %$props) {
        #next PROP if $prop eq 'INCLUDE';
        #next PROP if $prop eq 'EXCLUDE';
        $stats{$prop} = $props->{$prop};
    }

    return wantarray ? %stats : \%stats;
}

sub get_element_property_keys {
    my $self = shift;

    my $res = {};

    my $elements = $self->get_element_list;

    return $res if ! scalar @$elements;

    #  cheat a bit and assume all have the same props (they should)    
    my %p = $self->get_element_properties(element => $elements->[0]);

    my @keys = keys %p;

    return wantarray ? @keys : \@keys;
}

sub get_element_properties {
    my $self = shift;
    my %args = @_;
    
    my $element = $args{element};
    croak "element argument not given\n" if ! defined $element;
    
    my $props = $self->get_list_ref (
        element    => $element,
        list       => 'PROPERTIES',
        autovivify => 0,
    )
    || {};  # or a blank hash
    
    my %p = %$props;  #  make a copy;
    delete @p{qw /INCLUDE EXCLUDE/};  #  don't want these
    
    return wantarray ? %p : \%p;
}


#  return true if the labels are all numeric
sub elements_are_numeric {
    my $self = shift;
    foreach my $element ($self->get_element_list) {
        return 0 if ! looks_like_number($element);
    }
    return 1;  # if we get this far then they must all be numbers
}

#  like elements_are_numeric, but checks each axis
#  this is all or nothing
sub element_arrays_are_numeric {
    my $self = shift;
    foreach my $element ($self->get_element_list) {
        my $array = $self -> get_element_name_as_array (element => $element);
        foreach my $iter (@$array) {
            return 0 if ! looks_like_number($iter);
        }
    }
    return 1;  # if we get this far then they must all be numbers
}


sub min {
    return $_[0] < $_[1] ? $_[0] : $_[1];
}

sub max {
    return $_[0] > $_[1] ? $_[0] : $_[1];
}



sub DESTROY {
    my $self = shift;
    #my $name = $self -> get_param ('NAME');
    #print "DESTROYING BASESTRUCT $name\n";
    #undef $name;
    my $success = $self -> set_param (BASEDATA_REF => undef);
    
    #$self -> _delete_params_all;
    
    foreach my $key (sort keys %$self) {  #  clear all the top level stuff
        #print "Deleting BS $key\n";
        #$self->{$key} = undef;
        delete $self->{$key};
    }
    undef %$self;
    
    #  let perl handle the rest
    return;
}

1;


__END__

=head1 NAME

Biodiverse::BaseStruct

=head1 SYNOPSIS

  use Biodiverse::BaseStruct;
  $object = Biodiverse::BaseStruct->new();

=head1 DESCRIPTION

TO BE FILLED IN

=head1 METHODS

=over

=item INSERT METHODS

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
