package Biodiverse::BaseData;

#  package containing methods to access and store a Biodiverse BaseData object

use Carp;
use strict;
use warnings;
use Data::Dumper;
use POSIX qw {fmod};
use Scalar::Util qw /looks_like_number blessed reftype/;
use Time::HiRes qw /gettimeofday tv_interval/;
use IO::File;
use File::BOM qw /:subs/;
use Path::Class;
use POSIX qw /floor/;
use Geo::Converter::dms2dd qw {dms2dd};

use English qw { -no_match_vars };

#use Math::Random::MT::Auto qw /rand srand shuffle/;

use Biodiverse::BaseStruct;  #  main output goes to a Biodiverse::BaseStruct object
use Biodiverse::Cluster;  #  we use methods to control the cluster objects
use Biodiverse::Spatial;
use Biodiverse::RegionGrower;
use Biodiverse::Index;
use Biodiverse::Randomise;
use Biodiverse::Progress;
use Biodiverse::Indices;

our $VERSION = '0.18003';

use base qw {Biodiverse::Common};

#  how much input file to read in one go
our $input_file_chunk_size   = 10000000;
our $lines_to_read_per_chunk =    50000;

our $EMPTY_STRING = q{};
our $bytes_per_MB = 1056784;

sub new {
    my $class = shift;
    #my %self;
    
    #my $self = {};
    my $self = bless {}, $class;
    
    my %args = @_;
    
    # try to load from a file if the file arg is given
    if (defined $args{file}) {
        my $file_loaded;
        $file_loaded = $self->load_file (@_);
        return $file_loaded;
    }
    
    #  we got this far, so create a new and empty object
    
    my %exclusion_hash = (
        LABELS => {
            minVariety    => undef,
            maxVariety    => undef,
            minSamples    => undef,
            maxSamples    => undef,
            minRedundancy => undef,
            maxRedundancy => undef,
            min_range     => undef,
            max_range     => undef,
        },
        GROUPS => {
            minVariety    => undef,
            maxVariety    => undef,
            minSamples    => undef,
            maxSamples    => undef,
            minRedundancy => undef,
            maxRedundancy => undef,
        },
    );

    my %PARAMS = (  #  default parameters to load.
                    #  These will be overwritten if needed.
                    #  those commented out are redundant
        #NAME  =>  "BASEDATA",
        OUTSUFFIX           => 'bds',
        #OUTSUFFIX_XML      => 'bdx',
        OUTSUFFIX_YAML      => 'bdy',
        INPFX               => q{.},
        QUOTES              => q{'},  #  for Dan
        OUTPUT_QUOTE_CHAR   => q{"},
        JOIN_CHAR           => q{:},  #  used for labels
        NODATA              => undef,
        PARAM_CHANGE_WARN   => undef,
    );

    my %args_for = (%PARAMS, @_);
    my $x = $self->set_param (%args_for);
    
    #  create the groups and labels
    my %params_hash = $self->get_params_hash;
    my $name = $self->get_param ('NAME');
    $name = $EMPTY_STRING if not defined $name;
    $self->{GROUPS} = Biodiverse::BaseStruct->new(
        %params_hash,
        TYPE => 'GROUPS',
        NAME => $name . "_GROUPS",
        BASEDATA_REF => $self,
    );
    $self->{LABELS} = Biodiverse::BaseStruct->new(
        %params_hash,
        TYPE => 'LABELS',
        NAME => $name . "_LABELS",
        BASEDATA_REF => $self,
    );
    $self->{CLUSTER_OUTPUTS} = {};
    $self->{SPATIAL_OUTPUTS} = {};
    $self->{MATRIX_OUTPUTS}  = {};

    $self->set_param (EXCLUSION_HASH => \%exclusion_hash);
    
    %params_hash = ();  #  (vainly) hunting memory leaks

    return $self;
}

sub rename {
    my $self = shift;
    my %args = @_;
    
    croak "[BASEDATA] rename: argument name not supplied\n"
        if not defined $args{name};

    my $name = $self->get_param ('NAME');
    print "[BASEDATA] Renaming $name to $args{name}\n";

    $self->set_param (NAME => $args{name});
    
    return;
}

sub rename_output {
    my $self = shift;
    my %args = @_;
    
    my $object = $args{output};
    my $new_name = $args{new_name};
    my $name = $object->get_param ('NAME');
    my $hash_ref;
    
    if ((blessed $object) =~ /Spatial/) {
        print "[BASEDATA] Renaming spatial output $name to $new_name\n";
        $hash_ref = $self->{SPATIAL_OUTPUTS};
    }
    elsif ((blessed $object) =~ /Cluster|RegionGrower|Tree/) {
        print "[BASEDATA] Renaming cluster output $name to $new_name\n";
        $hash_ref = $self->{CLUSTER_OUTPUTS};
        
    }
    elsif ((blessed $object) =~ /Matrix/) {
        print "[BASEDATA] Renaming matrix output $name to $new_name\n";
        $hash_ref = $self->{MATRIX_OUTPUTS};
    }
    else {
        croak "[BASEDATA] Cannot rename this type of output: ",
                blessed ($object) || $EMPTY_STRING,
                "\n";
    }

    # only if it exists in this basedata
    if (exists $hash_ref->{$name}) {
        my $type = blessed $object;
        $type =~ s/.*://;

        croak "Cannot rename $type output $name to $new_name.  Name is already in use\n"
            if exists $hash_ref->{$new_name};

        $hash_ref->{$new_name} = $object;
        $hash_ref->{$name} = undef;
        delete $hash_ref->{$name};
        
        $object->rename (new_name => $new_name);
    }
    
    $object = undef;
    return;
}


#  define our own clone method for more control over what is cloned.
#  use the SUPER method (should be from Biodiverse::Common) for the components.
sub clone {
    my $self = shift;
    my %args = @_;
    my $cloneref;
    
    if ($args{no_outputs}) {  #  clone all but the outputs
        
        #  temporarily override the outputs - this is so much cleaner than before
        local $self->{SPATIAL_OUTPUTS} = {};
        local $self->{CLUSTER_OUTPUTS} = {};
        local $self->{RANDOMISATION_OUTPUTS} = {};
        local $self->{MATRIX_OUTPUTS} = {};
        $cloneref = $self->SUPER::clone ();
        
    }
    elsif ($args{no_elements}) {
        
        #  temporarily override the groups and labels so they aren't cloned
        local $self->{GROUPS}{ELEMENTS} = {};  # very dirty - basedata should not know about basestruct internals
        local $self->{LABELS}{ELEMENTS} = {};
        local $self->{SPATIAL_OUTPUTS} = {};
        local $self->{CLUSTER_OUTPUTS} = {};
        local $self->{RANDOMISATION_OUTPUTS} = {};
        local $self->{MATRIX_OUTPUTS} = {};
        $cloneref = $self->SUPER::clone ();
        
    }
    else {
        $cloneref = $self->SUPER::clone (%args);
    }
    
    #my $clone2 = $cloneref;  #  for testing purposes
    return $cloneref;
}

sub describe {
    my $self = shift;
    
    my @description = (
        ['TYPE: ', blessed $self],
    );

    my @keys = qw /
        NAME
        CELL_SIZES
        CELL_ORIGINS
        JOIN_CHAR
        QUOTES
        NUMERIC_LABELS
    /;

    foreach my $key (@keys) {
        my $desc = $self->get_param ($key);
        if ((ref $desc) =~ /ARRAY/) {
            $desc = join q{, }, @$desc;
        }
        push @description, [
            "$key:",
            $desc,
        ];
    }
    
    my $gp_count = $self->get_group_count;    
    my $lb_count = $self->get_label_count;
    my $sp_count = scalar @{$self->get_spatial_output_refs};
    my $cl_count = scalar @{$self->get_cluster_output_refs};
    my $rd_count = scalar @{$self->get_randomisation_output_refs};
    my $mx_count = scalar @{$self->get_matrix_output_refs};
    
    push @description, ['Group count:', $gp_count];
    push @description, ['Label count:', $lb_count];
    push @description, ['Spatial outputs:', $sp_count];
    push @description, ['Cluster outputs:', $cl_count];
    push @description, ['Randomisation outputs:', $rd_count];
    push @description, ['Matrix outputs:', $mx_count];

    push @description, [
        'Using spatial index:',
        ($self->get_param ('SPATIAL_INDEX') ? 'yes' : 'no'),
    ];

    my $ex_count = $self->get_param ('EXCLUSION_COUNT') || 0;
    push @description, ['Run exclusions count:', $ex_count];

    my $bounds = $self->get_coord_bounds;
    my $bnd_max = $bounds->{MAX};
    my $bnd_min = $bounds->{MIN};
    push @description, [
        'Group coord minima:',
        (join q{, }, @$bnd_min),
    ];
    push @description, [
        'Group coord maxima: ',
        (join q{, }, @$bnd_max),
    ];

    my $description;
    foreach my $row (@description) {
        $description .= join "\t", @$row;
        $description .= "\n";
    }
    
    return wantarray ? @description : $description;
}

sub get_coord_bounds {
    my $self = shift;

    #  do we use numeric or string comparison?
    my @numeric_comp;
    my @string_comp;
    my $cellsizes = $self->get_param ('CELL_SIZES');
    my $i = 0;
    foreach my $size (@$cellsizes) {
        if ($size < 0) {
            push @string_comp, $i;
        }
        else {
            push @numeric_comp, $i;
        }
        $i ++;
    }

    my (@min, @max);

    my $groups = $self->get_groups;
    my $gp = $self->get_groups_ref;

    my @coord0 = $gp->get_element_name_as_array (element => $groups->[0]);
    $i = 0;
    foreach my $axis (@coord0) {
        $min[$i] = $axis;
        $max[$i] = $axis;
        $i ++;
    }

    foreach my $gp_name (@$groups) {

        my @coord = $gp->get_element_name_as_array (element => $gp_name);

        foreach my $j (@string_comp) {
            my $axis = $coord[$j];
            $min[$j] = $axis if $axis lt $min[$j];
            $max[$j] = $axis if $axis gt $max[$j];
        }
        foreach my $j (@numeric_comp) {
            my $axis = $coord[$j];
            $min[$j] = $axis if $axis < $min[$j];
            $max[$j] = $axis if $axis > $max[$j];
        }

    }

    my %bounds = (
        MIN => \@min,
        MAX => \@max,
    );

    return wantarray ? %bounds : \%bounds;
}

#  return a new BaseData object with transposed GROUPS and LABELS.
#  all other results are ignored, as they will no longer make sense
sub transpose {
    my $self = shift;
    my %args = @_;

    #  create the new object.         retain the the current params
    my $params = $self->clone (  #  but clone to avoid ref clash problems
        data => scalar $self->get_params_hash
    );  

    my $new = Biodiverse::BaseData->new(%$params);
    my $name = $args{name} // ($new->get_param ('NAME') . "_T");

    $new->set_param (NAME => $name);

    #  get refs for the current object
    my $groups = $self->get_groups_ref->clone;
    my $labels = $self->get_labels_ref->clone;

    #  assign the transposed groups and labels
    #  no need to worry about parent refs, as they don't have any (yet)
    $new->{GROUPS} = $labels;
    $new->{LABELS} = $groups;
    
    #  set the correct cell sizes.
    #  The default is just in case, and may cause trouble later on
    my $cell_sizes = $labels->get_param ('CELL_SIZES') || [-1];
    $new->set_param (CELL_SIZES => [@$cell_sizes]);  #  make sure it's a copy

    return $new;
}

#  create a tree object from the labels
sub to_tree {
    my $self = shift;
    return $self->get_labels_ref->to_tree (@_);
}

#  get the embedded trees used in the outputs
sub get_embedded_trees {
    my $self = shift;
    
    my $outputs = $self->get_output_refs;
    my %tree_hash;  #  index by ref to allow for duplicates

    OUTPUT:
    foreach my $output (@$outputs) {
        next OUTPUT if !$output->can('get_embedded_tree');

        my $tree = $output->get_embedded_tree;
        if ($tree) {
            $tree_hash{$tree} = $tree;
        }
    }

    return wantarray ? values %tree_hash : [values %tree_hash];
}

#  get the embedded trees used in the outputs
sub get_embedded_matrices {
    my $self = shift;
    
    my $outputs = $self->get_output_refs;
    my %mx_hash;  #  index by ref to allow for duplicates

    OUTPUT:
    foreach my $output (@$outputs) {
        next OUTPUT if !$output->can('get_embedded_tree');

        my $mx = $output->get_embedded_matrix;
        if ($mx) {
            $mx_hash{$mx} = $mx;
        }
    }

    return wantarray ? values %mx_hash : [values %mx_hash];
}

#  weaken all the child refs to this basedata object
#  otherwise they are not properly deleted when this is deleted
sub weaken_child_basedata_refs {
    my $self = shift;
    foreach my $sub_ob ($self->get_spatial_output_refs, $self->get_cluster_output_refs) {
        $sub_ob->weaken_basedata_ref;
    }
    foreach my $sub_ob ($self->get_cluster_output_refs) {
        $sub_ob->weaken_parent_refs;  #  loop through tree and weaken the parent refs
    }
    #print $EMPTY_STRING;
    
    return;
}


#  get the basestats from the groups (or labels)
sub get_base_stats {
    my $self = shift;
    my %args = @_;
    my $type = uc($args{type}) || 'GROUPS';
    $type = 'GROUPS' if ($type !~ /GROUPS|LABELS/);
    
    return $self->{$type}->get_base_stats (@_);
}

sub get_metadata_get_base_stats {
    my $self = shift;
    my %args = @_;
    
    #  probably not needed, but doesn't hurt...
    my $type = uc($args{type}) || 'GROUPS';

    $type = 'GROUPS' if ($type !~ /GROUPS|LABELS/);
    
    return $self->{$type}->get_metadata_get_base_stats (@_);
}

sub get_metadata_import_data {
    my $self = shift;
    
    my @sep_chars = my @separators = defined $ENV{BIODIVERSE_FIELD_SEPARATORS}
                  ? @$ENV{BIODIVERSE_FIELD_SEPARATORS}
                  : (q{,}, 'tab', q{;}, 'space', q{:});
    my @input_sep_chars = ('guess', @sep_chars);
    
    my @quote_chars = qw /" ' + $/;
    my @input_quote_chars = ('guess', @quote_chars);
    
    #  these parameters are only for the GUI, so are not a full set
    my %arg_hash = (
        parameters => [
            #{ name => 'input_files', type => 'file' }, # not for the GUI
            { name       => 'use_label_properties',
              label_text => 'Set label properties and remap?',
              tooltip    => "Change label names, \n"
                          . "set range, sample count,\n"
                          . "set exclude and include flags at the label level etc.",
              type       => 'boolean',
              default    => 0,
            },
            { name       => 'use_group_properties',
              label_text => 'Set group properties and remap?',
              tooltip    => "Change group names, \n"
                          . "set exclude and include flags at the group level etc.",
              type       => 'boolean',
              default    => 0,
            },
            { name       => 'allow_empty_labels',
             label_text  => 'Allow labels with no groups?',
             tooltip     => "Retain labels with no groups.\n"
                          . "Requires a sample count column with value zero\n"
                          . "(undef is treated as 1).",
             type        => 'boolean',
             default     => 0,
            },
            { name       => 'allow_empty_groups',
              label_text => 'Allow empty groups?',
              tooltip    => "Retain groups with no labels.\n"
                          . "Requires a sample count column with value zero\n"
                          . "(undef is treated as 1).",
              type       => 'boolean',
              default    => 0,
            },
            { name       => 'input_sep_char',
              label_text => 'Input field separator',
              tooltip    => 'Select character',
              type       => 'choice',
              choices    => \@input_sep_chars,
              default    => 0,
            },
            { name       => 'input_quote_char',
              label_text => 'Input quote character',
              tooltip    => 'Select character',
              type       => 'choice',
              choices    => \@input_quote_chars,
              default    => 0,
            },
            { name       => 'data_in_matrix_form',
              label_text => 'Data are in matrix form?',
              tooltip    => 'Are the data in a form like a site by species matrix?',
              type       => 'boolean',
              default    => 0,
            },
            { name       => 'skip_lines_with_undef_groups',
              label_text => 'Skip lines with undef groups?',
              tooltip    => 'Turn off if some records have undefined/null '
                          . 'group values and should be skipped.  '
                          . 'Import will otherwise fail if they are found.',
              type       => 'boolean',
              default    => 1,
            },
            { name       => 'binarise_counts',
              label_text => 'Convert sample counts to binary?',
              tooltip    => 'Any non-zero sample count will be '
                          . "converted to a value of 1.  \n"
                          . 'Applies to each record, not to groups.',
              type       => 'boolean',
              default    => 0,
            },
        ]
    );
    
    return wantarray ? %arg_hash : \%arg_hash;
}

*load_data = \&import_data;

sub import_data {  #  load a data file into the selected BaseData object.
    #  Evolved from the (very) old Organise routine from the original anlayses.
    my $self = shift;
    my %args = @_;
    
    my $progress_bar = Biodiverse::Progress->new(gui_only => 1);
    
    if (not defined $args{input_files}) {
        $args{input_files}   = $self->get_param('INPUT_FILES');
        croak "Input files array not provided\n"
          if not $args{input_files};
    }
    if (not defined $args{label_columns}
        and defined $self->get_param('LABEL_COLUMNS')) {
        $args{label_columns} = $self->get_param('LABEL_COLUMNS');
    }
    if (not defined $args{group_columns}
        and defined $self->get_param('GROUP_COLUMNS')) {
        $args{group_columns} = $self->get_param('GROUP_COLUMNS');
    }

    #  disallow any cell_size, cell_origin or sample_count_columns overrides
    $args{cell_sizes}
        = $self->get_param('CELL_SIZES')
            || $args{cell_sizes}
            || croak "Cell sizes must be specified\n";

    $args{cell_origins}
        = $self->get_param('CELL_ORIGINS')
            || $args{cell_origins}
            || [];  #  default to an empty array which will be padded out below

    $args{cell_is_lat}
        = $self->get_param('CELL_IS_LAT')
            || $args{cell_is_lat}
            || [];

    $args{cell_is_lon}
        = $self->get_param('CELL_IS_LON')
            || $args{cell_is_lon}
            || [];

    $args{sample_count_columns}
        = $args{sample_count_columns}
            || $self->get_param('SAMPLE_COUNT_COLUMNS')
            || [];

    
    #  load the properties tables from the args, or use the ones we already have
    #  labels first
    my $label_properties;
    my $use_label_properties = $args{use_label_properties};
    if ($use_label_properties) {  # twisted - FIXFIXFIX
        $label_properties = $args{label_properties}
                            || $self->get_param ('LABEL_PROPERTIES');
        if ($args{label_properties}) {
            $self->set_param (LABEL_PROPERTIES => $args{label_properties});
        }
    }
    #  then groups
    my $group_properties;
    my $use_group_properties = $args{use_group_properties};
    if ($use_group_properties) {
        $group_properties = $args{group_properties}
                            || $self->get_param ('GROUP_PROPERTIES');
        if ($args{group_properties}) {
            $self->set_param (GROUP_PROPERTIES => $args{group_properties}) ;
        }
    }
    
    my $labels_ref = $self->get_labels_ref;
    my $groups_ref = $self->get_groups_ref;
    
    print "[BASEDATA] Loading from files "
            . join (q{ }, @{$args{input_files}})
            . "\n";

    my @label_columns        = @{$args{label_columns}};
    my @group_columns        = @{$args{group_columns}};
    my @cell_sizes           = @{$args{cell_sizes}};  
    my @cell_origins         = @{$args{cell_origins}};
    my @cell_is_lat_array    = @{$args{cell_is_lat}};
    my @cell_is_lon_array    = @{$args{cell_is_lon}};
    my @sample_count_columns = @{$args{sample_count_columns}};
    my $exclude_columns      = $args{exclude_columns};
    my $include_columns      = $args{include_columns};
    my $binarise_counts      = $args{binarise_counts};  #  make sample counts 1 or 0
    
    my $skip_lines_with_undef_groups = $args{skip_lines_with_undef_groups};
    
    #  check the cell sizes
    foreach my $size (@cell_sizes) {
        croak "Cell size $size is not numeric, you might need to check the locale\n"
            if ! looks_like_number ($size);
    }

    #  make them an array if they are a scalar
    #  if they are not an array or scalar then it is the caller's fault
    if (not defined reftype ($exclude_columns)
        or reftype ($exclude_columns) ne 'ARRAY') {

        if (defined $exclude_columns) {
            $exclude_columns = [$exclude_columns];
        }
        else {
            $exclude_columns = [];
        }
    }
    #  clear out any undef columns.  work from the end to make splicing easier
    foreach my $col (reverse 0 .. $#$exclude_columns) {
        splice (@$exclude_columns, $col, 1) if ! defined $$exclude_columns[$col];
    }
    if (not defined reftype ($include_columns) or reftype ($include_columns) ne 'ARRAY') {
        if (defined $include_columns) {
            $include_columns = [$include_columns];
        }
        else {
            $include_columns = [];
        }
    }
    #  clear out any undef columns
    foreach my $col (reverse 0 .. $#$include_columns) {
        splice (@$include_columns, $col, 1) if ! defined $$include_columns[$col];
    }

    #  now we guarantee we get the correct array lengths
    if ($#group_columns < $#cell_sizes) {
        splice (@cell_sizes, $#group_columns - $#cell_sizes);
        $self->set_param(CELL_SIZES => \@cell_sizes);
    }
    elsif ($#group_columns > $#cell_sizes) {
        push (@cell_sizes, (0) x ($#group_columns - $#cell_sizes));
    }
    if ($#group_columns < $#cell_origins) {
        splice (@cell_origins, $#group_columns - $#cell_origins);
        $self->set_param(CELL_ORIGINS => \@cell_origins);
    }
    #  pad with zeroes in case not enough origins are specified
    push (@cell_origins, (0) x ($#cell_sizes - $#cell_origins));  

    my @half_cellsize;  #  precalculate to save a few computations
    for (my $i = 0; $i <= $#cell_sizes; $i++) {
        $half_cellsize[$i] = $cell_sizes[$i] / 2;
    }

    my $quotes = $self->get_param ('QUOTES');  #  for storage, not import
    my $el_sep = $self->get_param ('JOIN_CHAR');

    #  for parsing lines to element components
    my %line_parse_args = (
        label_columns        => \@label_columns,
        group_columns        => \@group_columns,
        cell_sizes           => \@cell_sizes,
        half_cellsize        => \@half_cellsize,
        cell_origins         => \@cell_origins,
        sample_count_columns => \@sample_count_columns,
        exclude_columns      => $exclude_columns,
        include_columns      => $include_columns,
        label_properties     => $label_properties,
        use_label_properties => $use_label_properties,
        group_properties     => $group_properties,
        use_group_properties => $use_group_properties,
        allow_empty_groups   => $args{allow_empty_groups},
        allow_empty_labels   => $args{allow_empty_labels},
    );


    my $line_count_all_input_files = 0;
    my $orig_group_count = $self->get_group_count;

    #print "[BASEDATA] Input files to load are ", join (" ", @{$args{input_files}}), "\n";
    foreach my $file (@{$args{input_files}}) {
        $file = Path::Class::file($file)->absolute;
        print "[BASEDATA] INPUT FILE: $file\n";
        my $file_base = $file->basename;

        my $file_handle = IO::File->new;

        if (-e $file and -r $file) {
            $file_handle->open ($file, '<:via(File::BOM)');
        }
        else {
            croak "[BASEDATA] $file DOES NOT EXIST OR CANNOT BE READ - CANNOT LOAD DATA\n";
        }

        my $file_size_Mb
            = $self->set_precision (
                precision => "%.3f",
                value => (-s $file)
            )
            / $bytes_per_MB;

        my $input_binary = $args{binary};  #  a boolean flag for Text::CSV_XS
        if (not defined $input_binary) {
            $input_binary = 1;
        }

        #  Get the header line, assumes no binary chars in it.
        #  If there are then there is something really wrong with the file.
        my $header = $file_handle->getline;
        #  Could be futile - the read operator uses $/,
        #  although \r\n will be captured.
        #  Should really seek to end of file and then read back a few chars,
        #  assuming that's faster.
        my $eol = $self->guess_eol (string => $header);
        my $eol_char_len = length ($eol);

        #  for progress bar stuff
        my $size_comment
            = $file_size_Mb > 10
            ? "This could take a while\n"
              . "(it is still working if the progress bar is not moving)" 
            : $EMPTY_STRING;

        my $input_quote_char = $args{input_quote_char};
        #  guess the quotes character?
        if (not defined $input_quote_char or $input_quote_char eq 'guess') {  
            #  read in a chunk of the file
            my $first_10000_chars;

            my $fh2 = IO::File->new;
            $fh2->open ($file, '<:via(File::BOM)');
            my $count_chars = $fh2->read ($first_10000_chars, 10000);
            $fh2->close;

            #  Strip trailing chars until we get $eol at the end.
            #  Not perfect for CSV if embedded newlines, but it's a start.
            while (length $first_10000_chars) {
                last if ($first_10000_chars =~ /$eol$/);
                chop $first_10000_chars;
            }

            $input_quote_char = $self->guess_quote_char (string => \$first_10000_chars);
            #  if all else fails...
            if (! defined $input_quote_char) {
                $input_quote_char = $self->get_param ('QUOTES');
            }
        }

        my $sep = $args{input_sep_char};
        if (not defined $sep or $sep eq 'guess') {
            $sep = $self->guess_field_separator (
                string     => $header,
                quote_char => $input_quote_char,
            );
        }

        my $in_csv = $self->get_csv_object (
            sep_char   => $sep,
            quote_char => $input_quote_char,
            binary     => $input_binary,  #  NEED TO ENABLE OTHER CSV ARGS TO BE PASSED
        );
        my $out_csv = $self->get_csv_object (
            sep_char   => $el_sep,
            quote_char => $quotes,
        );

        my $lines = $self->get_next_line_set (
            file_handle        => $file_handle,
            file_name          => $file,
            target_line_count  => $lines_to_read_per_chunk,
            csv_object         => $in_csv,
        );

        #  parse the header line if we are using a matrix format file
        my $matrix_label_col_hash = {};
        if ($args{data_in_matrix_form}) {
            my $label_start_col = $args{label_start_col};
            my $label_end_col   = $args{label_end_col};
            #  if we've been passed an array then
            #  use the first one for the start and the last for the end
            #  - this can happen due to the way GUI::BasedataImport
            #  handles options and is something we need to clean
            #  up with better metadata
            if (ref $label_start_col) {
                $label_start_col = $label_start_col->[0];
            }
            if (ref $label_end_col) {  
                $label_end_col = $label_end_col->[-1];
            }
            my $header_array = $self->csv2list (
                csv_object => $in_csv,
                string     => $header,
            );
            $matrix_label_col_hash
                = $self->get_label_columns_for_matrix_import  (
                    csv_object       => $out_csv,
                    label_array      => $header_array,
                    label_start_col  => $label_start_col,
                    label_end_col    => $label_end_col,
                    %line_parse_args,
            );
        }
        
        
        my $line_count = scalar @$lines + 1; # count number of lines, incl header
        my $line_count_used_this_file = 1;  #  allow for headers
        my $line_num_end_prev_chunk = 1;
        

        my $line_num = 0;
        #my $line_num_end_last_chunk = 0;
        my $chunk_count = 0;
        #my $total_chunk_text = $self->get_param_as_ref ('IMPORT_TOTAL_CHUNK_TEXT');
        my $total_chunk_text = '>0';
        
        print "[BASEDATA] Line number: 1\n";
        print "[BASEDATA]  Chunk size $line_count lines\n";
        
        #  destroy @lines as we go, saves a bit of memory for big files
        #  keep going if we have lines to process or haven't hit the end of file
        BYLINE: while (scalar @$lines or not (eof $file_handle)) {
            $line_num ++;

            #  read next chunk if needed.
            #  section must be here in case we have an
            #  exclude on or near the last line of the chunk
            if (scalar @$lines == 0) {
                $lines = $self->get_next_line_set (
                    progress           => $progress_bar,
                    file_handle        => $file_handle,
                    file_name          => $file,
                    target_line_count  => $lines_to_read_per_chunk,
                    csv_object         => $in_csv,
                );

                $line_num_end_prev_chunk = $line_count;
                
                $line_count += scalar @$lines;

                #$chunk_count = $self->get_param ('IMPORT_CHUNK_COUNT') || 0;
                #$total_chunk_text = $self->get_param ('IMPORT_TOTAL_CHUNK_TEXT');
                #$total_chunk_text = ">$chunk_count" if not defined $$total_chunk_text;
                $chunk_count ++;
                $total_chunk_text
                    = $file_handle->eof ? $chunk_count : ">$chunk_count";
            }
            
            
            if ($line_num % 1000 == 0) { # progress information

                my $line_count_text
                    = eof ($file_handle)
                        ? " $line_count"
                        : ">$line_count";

                my $frac = eval {
                    ($line_num   - $line_num_end_prev_chunk) /
                    ($line_count - $line_num_end_prev_chunk)
                };
                $progress_bar->update(
                    "Loading $file_base\n" .
                    "Line $line_num of $line_count_text\n" .
                    "Chunk #$chunk_count",
                    $frac
                );

                if ($line_num % 10000 == 0) {
                    print "Loading $file_base line "
                          . "$line_num of $line_count_text, "
                          . "chunk $chunk_count\n" ;
                }
            }

            my $fields_ref = shift @$lines;

            #  skip blank lines or those that failed
            next BYLINE if not defined $fields_ref;
            next BYLINE if scalar @$fields_ref == 0;
            
            #  should we explicitly exclude or include this record?
            if (scalar @$exclude_columns) {
                foreach my $col (@$exclude_columns) {
                    next BYLINE if $fields_ref->[$col];  #  skip if any are true
                }
            }
            if (scalar @$include_columns) {
                my $incl = 0;
                
                CHECK_INCLUDE_COLS:
                foreach my $col (@$include_columns) {
                    next CHECK_INCLUDE_COLS if ! defined $col;
                    if ($fields_ref->[$col]) {
                        $incl = 1;
                    }
                    #  check no more if we get a true value
                    last CHECK_INCLUDE_COLS if $incl;
                }
                #print "not including \n$line" if ! $incl;
                next BYLINE if not $incl;  #  skip if none are to be kept
            }
        
        
            #  get the group for this row
            my @group;
            my $i = 0;
            foreach my $column (@group_columns) {  #  build the list of groups
                my $coord = $fields_ref->[$column];

                if ($cell_sizes[$i] >= 0) {
                    next BYLINE
                      if $skip_lines_with_undef_groups
                         and not defined $coord;

                    if ($cell_is_lat_array[$i]) {
                        my $lat_args = {
                            value  => $coord,
                            is_lat => 1,
                        };
                        $coord = eval {
                            dms2dd ($lat_args)
                        };
                        croak $EVAL_ERROR if $EVAL_ERROR;
                    }
                    elsif ($cell_is_lon_array[$i]) {
                        my $lon_args = {
                            value  => $coord,
                            is_lon => 1,
                        };
                        $coord = eval {
                            dms2dd ($lon_args)
                        };
                        croak $EVAL_ERROR if $EVAL_ERROR;
                    }
                    elsif (! looks_like_number ($coord)) {
                        #next BYLINE if $skip_lines_with_undef_groups;
                        
                        croak "[BASEDATA] Non-numeric group field in column $column"
                             . " ($coord), check your data or cellsize arguments.\n"
                             . "near line $line_num of file $file\n";
                    }
                }

                if ($cell_sizes[$i] > 0) {

                    #  allow for different snap value - shift before aggregation
                    my $tmp = $coord - $cell_origins[$i];

                    #  how many cells away from the origin are we?
                    #  snap to 10dp precision to avoid cellsize==0.1 issues
                    my $tmp_prec = $self->set_precision(
                        value     => $tmp / $cell_sizes[$i],
                        precision => '%.10f',
                    );
                    #my $offset = int (abs ($tmp_prec));
                    my $offset = floor ($tmp_prec);

                    #  which cell are we?
                    my $gp_val = $offset * $cell_sizes[$i];
                    
                    #  now assign the centre of the cell we are in
                    $gp_val += $half_cellsize[$i];

                    #  now shift the aggregated cell back to where it should be
                    $group[$i] = $gp_val + $cell_origins[$i];
                }
                else {
                    #  commented next check - don't trap undef text fields as they can be useful
                    #croak "Null field value for text field, column $i, line $line_num of file $file\n$_"
                    #        if ! defined $fields_ref->[$column];
                    
                    #  negative cell sizes denote non-numeric groups,
                    #  zero means keep the original values
                    $group[$i] = $coord;  
                }
                $i++;
            }

            my $group = $self->list2csv (
                list        => \@group,
                csv_object  => $out_csv,
            );

            #  remap it if needed
            if ($use_group_properties) {
                my $remapped = $group_properties->get_element_remapped (
                    element => $group,
                );

                #  test exclude and include before remapping
                next BYLINE if $group_properties->get_element_exclude (
                    element => $group,
                );

                my $include =  $group_properties->get_element_include (element => $group);
                if (defined $include and not $include) {
                    print "Skipping $group\n";
                    next BYLINE;
                }

                if (defined $remapped) {
                    $group = $remapped ;
                }
            }

            my %elements;
            if ($args{data_in_matrix_form}) {
                %elements =
                    $self->get_labels_from_line_matrix (
                        fields_ref      => $fields_ref,
                        csv_object      => $out_csv,
                        line_num        => $line_num,
                        file            => $file,
                        label_col_hash  => $matrix_label_col_hash,
                        %line_parse_args,
                    );
            }
            else {
                %elements =
                    $self->get_labels_from_line (
                        fields_ref      => $fields_ref,
                        csv_object      => $out_csv,
                        line_num        => $line_num,
                        file            => $file,
                        %line_parse_args,
                    );
            }

            
            ADD_ELEMENTS:
            while (my ($el, $count) = each %elements) {
                if (defined $count) {
                    next ADD_ELEMENTS
                      if $args{data_in_matrix_form}
                         && $count eq $EMPTY_STRING;
                         
                    next ADD_ELEMENTS
                      if $count == 0 and ! $args{allow_empty_groups};
                }
                else {  #  don't allow undef counts in matrices
                    next ADD_ELEMENTS
                      if $args{data_in_matrix_form};
                }
                $self->add_element (
                    %args,
                    label      => $el,
                    group      => $group,
                    count      => $count,
                    binary     => $binarise_counts,
                    csv_object => $out_csv,
                );
            }

            $line_count_used_this_file  ++;
            $line_count_all_input_files ++;
        }

        $file_handle->close;
        print "\tDONE (used $line_count_used_this_file of $line_count lines)\n";
    }

    #  add the range and sample_count to the label properties
    #  (actually it sets whatever properties are in the table)
    if ($use_label_properties) {
        $self->assign_element_properties (
            type              => 'labels',
            properties_object => $label_properties,
        );
    }
    #  add the group properties
    if ($use_group_properties) {
        $self->assign_element_properties (
            type              => 'groups',
            properties_object => $group_properties,
        );
    }

    # Set CELL_SIZE on the GROUPS BaseStruct
    $groups_ref->set_param (CELL_SIZES => $self->get_param('CELL_SIZES'));
    
    #  check if the labels are numeric (or still numeric)
    #  set flags and cell sizes accordingly
    if ($self->get_param('NUMERIC_LABELS')
        or not defined $self->get_param('NUMERIC_LABELS')
        ) {
        $self->set_param(      #  set a value from undef returns
            NUMERIC_LABELS => ($labels_ref->elements_are_numeric || 0)
        );  
    }

    my @label_cell_sizes;
    if ($labels_ref->element_arrays_are_numeric) {
        @label_cell_sizes = (0) x scalar @label_columns;  #  numbers
    }
    else {
        @label_cell_sizes = (-1) x scalar @label_columns;  #  text
    }
    $labels_ref->set_param (CELL_SIZES => \@label_cell_sizes);

    if ($labels_ref->get_element_count) {
        $labels_ref->generate_element_coords;
    }

    if ($groups_ref->get_element_count) {
        $groups_ref->generate_element_coords;
    }

    #  clear the rtree if one exists (used for plotting)
    $groups_ref->delete_param ('RTREE');

    #  clear this also
    $labels_ref->delete_param ('SAMPLE_COUNTS_ARE_FLOATS');
    $groups_ref->delete_param ('SAMPLE_COUNTS_ARE_FLOATS');

    #  now rebuild the index if need be
    if (    $orig_group_count != $self->get_group_count
        and $self->get_param ('SPATIAL_INDEX')
        ) {
        $self->rebuild_spatial_index();
    }


    return 1;  #  success
}

sub assign_element_properties {
    my $self = shift;
    my %args = @_;
    
    my $type = $args{type}
      or croak 'argument "type" not specified';
    my $prop_obj = $args{properties_object}
      or croak 'argument properties_object not given';
    
    croak "Cannot assign properties to a basedata with existing outputs"
      if $self->get_output_ref_count;

    my $method = 'get_' . $type . '_ref';
    my $gp_lb_ref = $self->$method;
    
    my $count = 0;
    
  ELEMENT_PROPS:
    foreach my $element ($prop_obj->get_element_list) {
        next ELEMENT_PROPS
          if ! $gp_lb_ref->exists_element (element => $element);

        my %props = $prop_obj->get_element_properties (element => $element);

        #  but don't add these ones
        delete @props{qw /INCLUDE EXCLUDE/};

        $gp_lb_ref->add_to_lists (
            element    => $element,
            PROPERTIES => \%props,
        );

        $count ++;
    }

    return $count;
}

sub rename_labels {
    my $self = shift;
    my %args = @_;
    
    croak "Cannot rename labels when basedata has existing outputs\n"
      if $self->get_output_ref_count;

    my $remap = $args{remap};

    LABEL:
    foreach my $label ($remap->get_element_list) {
        my $remapped
            = $remap->get_element_remapped (element => $label);

        next LABEL if !defined $remapped;

        $self->rename_label (label => $label, new_name => $remapped);
    }

    return;
}

sub rename_label {
    my $self = shift;
    my %args = @_;

    croak "Argument 'label' not specified\n"
      if !defined $args{label};
    croak "Argument 'new_name' not specified\n"
      if !defined $args{new_name};

    my $lb = $self->get_labels_ref;
    my $gp = $self->get_groups_ref;
    my $label = $args{label};
    my $new_name = $args{new_name};

    my @sub_elements = $lb->rename_element (element => $label, new_name => $new_name);
    foreach my $group (@sub_elements) {
        $gp->rename_subelement (
            element     => $group,
            sub_element => $label,
            new_name    => $new_name,
        );
    }

    print "[BASEDATA] Renamed $label to $new_name\n";

    return;
}


sub get_labels_from_line {
    my $self = shift;
    my %args = @_;
    
    #  these assignments look redundant, but this makes for cleaner code and
    #  the compiler should optimise it all away
    my $fields_ref           = $args{fields_ref};
    my $csv_object           = $args{csv_object};
    my $label_columns        = $args{label_columns};
    my $sample_count_columns = $args{sample_count_columns};
    my $label_properties     = $args{label_properties};
    my $use_label_properties = $args{use_label_properties};
    my $line_num             = $args{line_num};
    my $file                 = $args{file};

    #  return a set of results that are the label and its corresponding count value
    my %elements;

    #  get the label for this row  using a slice
    my @tmp = @$fields_ref[@$label_columns];
    my $label = $self->list2csv (
        list => \@tmp,
        csv_object => $csv_object,
    );
    
    #  remap it if needed
    if ($use_label_properties) {
        my $remapped
            = $label_properties->get_element_remapped (element => $label);

        #  test include and exclude before remapping
        return if $label_properties->get_element_exclude (element => $label);

        my $include = $label_properties->get_element_include (element => $label);    

        return if defined $include and not $include;

        $label = $remapped if defined $remapped;
    }


    #  get the sample count
    my $sample_count;
    foreach my $column (@$sample_count_columns) {
        my $col_value = $fields_ref->[$column];

        if ($args{allow_empty_groups} or $args{allow_empty_labels}) {
            return if not defined $col_value;  #  only skip undefined records
        }

        if (! looks_like_number ($col_value)) {  #  check the record if we get this far
            croak "[BASEDATA] Field $column in line $line_num "
                  . "does not look like a number, File $file\n";
        }
        $sample_count += $col_value;
    }
    
    #  set default count - should only get valid records if we get this far
    $sample_count = 1 if not defined $sample_count;
    
    #$elements{$label} = $sample_count if $sample_count;
    $elements{$label} = $sample_count;
    
    return wantarray ? %elements : \%elements;
}

#  parse a line from a matrix format file and return all the elements in it
sub get_labels_from_line_matrix {
    my $self = shift;
    my %args = @_;
    
    #return;  #  temporary drop out
    
    #  these assignments look redundant, but this makes for cleaner code and
    #  the compiler should optimise it all away
    my $fields_ref           = $args{fields_ref};
    my $csv_object           = $args{csv_object};
    my $label_array          = $args{label_array};
    my $label_properties     = $args{label_properties};
    my $use_label_properties = $args{use_label_properties};
    my $line_num             = $args{line_num};
    my $file                 = $args{file};
    my $label_col_hash       = $args{label_col_hash};

    #  these are superseded by $label_col_hash
    #my $label_start_col     = $args{label_start_col};
    #my $label_end_col       = $args{label_end_col} || $#$fields_ref;  #  not yet supported by GUI (03Oct2009)

    #  All we need to do is get a hash of the labels with their relevant column values
    #  Any processing of null or zero fields is handled by calling subs
    #  All label remapping has already been handled by get_label_columns_for_matrix_import (assuming it is not renamed)
    #  Could possibly check for zero count values, but that adds another loop which might slow things too much,
    #       even if using List::MoreUtils and its XS implementation
    
    my %elements;
    my @counts = @$fields_ref;
    #my @x = $fields_ref->[values %$label_col_hash];
    @elements{keys %$label_col_hash} = @$fields_ref[values %$label_col_hash];

    return wantarray ? %elements : \%elements;
    
}


#  process the header line and sort out which columns we want, and remap any if needed
sub get_label_columns_for_matrix_import {
    my $self = shift;
    my %args = @_;

    my $csv_object           = $args{csv_object};
    my $label_array          = $args{label_array};
    my $label_properties     = $args{label_properties};
    my $use_label_properties = $args{use_label_properties};

    my $label_start_col     = $args{label_start_col};
    my $label_end_col       = $args{label_end_col};
    if (! defined $label_end_col) {
        $label_end_col = $#$label_array;
    }

    my %label_hash;
    LABEL_COLS:
    for my $i ($label_start_col .. $label_end_col) {

        #  get the label for this row from the header
        my @tmp = $label_array->[$i];
        my $label = $self->list2csv (
            list       => \@tmp,
            csv_object => $csv_object,
        );

        #  remap it if needed
        if ($use_label_properties) {
            my $remapped = $label_properties->get_element_remapped (element => $label);
            
            #  text include and exclude before remapping
            next if $label_properties->get_element_exclude (element => $label);
            my $include = $label_properties->get_element_include (element => $label);
            if (defined $include) {
                next LABEL_COLS unless $include;
            }

            $label = $remapped if defined $remapped;
        }
        $label_hash{$label} = $i;
    }
    
    #  this will be a label/column hash which we can use to slice data from the matrix row arrays
    return wantarray ? %label_hash : \%label_hash;
}



sub labels_are_numeric {
    my $self = shift;
    return $self->get_param('NUMERIC_LABELS');
}

#  are the sample counts floats or ints?  
sub sample_counts_are_floats {
    my $self = shift;

    my $lb = $self->get_labels_ref;

    return $lb->sample_counts_are_floats;
}

sub add_element {  #  run some calls to the sub hashes
    my $self = shift;
    my %args = @_;

    my $label = $args{label};
    my $group = $args{group};
    my $count = $args{count} // 1;
    
    #  make count binary if asked to
    if ($args{binarise_counts}) {
        $count = $count ? 1 : 0;
    }

    my $gp_ref = $self->get_groups_ref;
    my $lb_ref = $self->get_labels_ref;

    if (not defined $label) {  #  one of these will break if neither label nor group is defined
        $gp_ref->add_element (
            element    => $group,
            csv_object => $args{csv_object},
        );
        return;
    }
    if (not defined $group) {
        $lb_ref->add_element (
            element    => $label,
            csv_object => $args{csv_object},
        );
        return;
    }
    
    if ($count) {
        #  add the labels and groups as element and subelement
        #  labels is the transpose of groups
        $gp_ref->add_sub_element (
            element    => $group,
            subelement => $label,
            count      => $count,
            csv_object => $args{csv_object},
        );
        $lb_ref->add_sub_element (
            element    => $label,
            subelement => $group,
            count      => $count,
            csv_object => $args{csv_object},
        );
    }
    else {
        if ($args{allow_empty_groups}) {
            $gp_ref->add_element (
                element    => $group,
                csv_object => $args{csv_object},
            );
        }
        if ($args{allow_empty_labels}) {
            $lb_ref->add_element (
                element    => $label,
                csv_object => $args{csv_object},
            );
        }
    }

    return;
}

sub get_group_element_as_array {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};
    croak "element not specified\n"
      if !defined $element;
    
    return $self->{GROUPS}->get_element_name_as_array(element => $element);
}

sub get_label_element_as_array {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};
    croak "element not specified\n"
      if !defined $element;

    return $self->get_labels_ref->get_element_name_as_array(element => $element);
}


#  reorder group and/or label axes
#  Clone the basedata and add the remapped elements
#  This avoids complexities with name clashes that an in-place
#  re-ordering would cause
sub new_with_reordered_element_axes {
    my $self = shift;
    my %args = @_;

    my $group_cols = $args{GROUP_COLUMNS};
    my $label_cols = $args{LABEL_COLUMNS};
    
    my $csv_object = $self->get_csv_object (
        quote_char => $self->get_param ('QUOTES'),
        sep_char   => $self->get_param ('JOIN_CHAR')
    );


    #  get the set of reordered labels
    my $lb = $self->get_labels_ref;
    my $lb_remapped = $lb->get_reordered_element_names (
        reordered_axes => $label_cols,
        csv_object     => $csv_object,
    );
    #  and the set of reordered groups
    my $gp = $self->get_groups_ref;
    my $gp_remapped = $gp->get_reordered_element_names (
        reordered_axes => $group_cols,
        csv_object     => $csv_object,
    );

    my $new_bd = $self->clone (no_elements => 1);

    foreach my $group ($gp->get_element_list) {
        my $new_group = $gp_remapped->{$group};
        foreach my $label ($self->get_labels_in_group (group => $group)) {
            my $new_label = $lb_remapped->{$label};
            if (not defined $new_label) {
                $new_label = $label;
            }

            my $count = $gp->get_subelement_count (
                element     => $group,
                sub_element => $label,
            );

            $new_bd->add_element (
                group => $new_group,
                label => $new_label,
                count => $count,
            );
        }
    }

    $self->transfer_label_properties (
        %args,
        receiver => $new_bd,
        remap    => $lb_remapped,
    );
    $self->transfer_group_properties (
        %args,
        receiver => $new_bd,
        remap    => $gp_remapped,
    );

    return $new_bd;
}

sub transfer_label_properties {
    my $self = shift;

    return $self->transfer_element_properties(@_, type => 'labels');
}

sub transfer_group_properties {
    my $self = shift;

    return $self->transfer_element_properties(@_, type => 'groups');
}


#  sometimes we have element properties defined like species ranges.
#  need to copy these across.
#  Push system - should it be pull (although it's only a semantic difference)
sub transfer_element_properties {
    my $self = shift;
    my %args = @_;
    
    my $to_bd = $args{receiver} || croak "Missing receiver argument\n";
    my $remap = $args{remap} || {};  #  remap hash

    my $progress_bar = Biodiverse::Progress->new();
    
    my $type = $args{type};
    croak "argument 'type => $type' is not valid (must be groups or labels)\n"
      if not ($type eq 'groups' or $type eq 'labels');
    my $get_ref_sub = $type eq 'groups' ? 'get_groups_ref' : 'get_labels_ref';

    my $elements_ref    = $self->$get_ref_sub;
    my $to_elements_ref = $to_bd->$get_ref_sub;

    my $name        = $self->get_param ('NAME');
    my $to_name     = $to_bd->get_param ('NAME');
    my $text        = "Transferring $type properties from $name to $to_name";

    my $total_to_do = $elements_ref->get_element_count;
    print "[BASEDATA] Transferring properties for $total_to_do $type\n";

    my $count = 0;
    my $i = -1;

    BY_ELEMENT:
    foreach my $element ($elements_ref->get_element_list) {
        $i++;
        my $progress = $i / $total_to_do;
        $progress_bar->update (
            "$text\n"
            . "(label $i of $total_to_do)",
            $progress
        );

        #  remap element if needed
        my $to_element = exists $remap->{$element} ? $remap->{$element} : $element;

        #  avoid working with those not in the receiver
        next BY_ELEMENT if not $to_elements_ref->exists_element (element => $to_element);

        my $props = $elements_ref->get_list_values (
            element => $element,
            list => 'PROPERTIES'
        );

        next BY_ELEMENT if ! defined $props;  #  none there

        $to_elements_ref->add_to_lists (
            element    => $to_element,
            PROPERTIES => {%$props},  #  make sure it's a copy so bad things don't happen
        );
        $count ++;
    }

    return $count;
}


sub run_exclusions {
    my $self = shift;
    my %args = @_;

    croak "Cannot run exclusions on a baseData with existing outputs\n"
      if (my @array = $self->get_output_refs);

    my $feedback = 'The data initially fall into '
          . $self->get_group_count
          . ' groups with '
          . $self->get_label_count
          . " unique labels\n\n";

    my $orig_group_count = $self->get_group_count;

    #  now we go through and delete any of the groups that are beyond our stated exclusion values
    my %exclusion_hash = $self->get_exclusion_hash;  #  generate the exclusion hash

    my %test_funcs = (
        minVariety    => '$base_type_ref->get_variety(element => $element) <= ',
        maxVariety    => '$base_type_ref->get_variety(element => $element) >= ',
        minSamples    => '$base_type_ref->get_sample_count(element => $element) <= ',
        maxSamples    => '$base_type_ref->get_sample_count(element => $element) >= ',
        minRedundancy => '$base_type_ref->get_redundancy(element => $element) <= ',
        maxRedundancy => '$base_type_ref->get_redundancy(element => $element) >= ',
    );

    my ($label_regex, $label_regex_negate);
    if ($exclusion_hash{LABELS}{regex}) {
        my $re_text = $exclusion_hash{LABELS}{regex}{regex};
        my $re_modifiers = $exclusion_hash{LABELS}{regex}{modifiers};

        $label_regex = eval qq{ qr /$re_text/$re_modifiers };
        $label_regex_negate = $exclusion_hash{LABELS}{regex}{negate};
    }

    my ($element_check_list, $element_check_list_negate);
    if (my $check_list = $exclusion_hash{LABELS}{element_check_list}{list}) {
        $element_check_list = {};
        $element_check_list_negate = $exclusion_hash{LABELS}{element_check_list}{negate};
        if (blessed $check_list) {  #  we have an object with a get_element_list method
            my $list = $check_list->get_element_list;
            @{$element_check_list}{@$list} = (1) x scalar @$list;
        }
        elsif (reftype $check_list eq 'ARRAY') {
            @{$element_check_list}{@$check_list} = (1) x scalar @$check_list;
        }
        else {
            $element_check_list = $check_list;
        }
    }

    #  check the labels first, then the groups
    #  equivalent to range then richness
    my @deleteList;
    
    my $excluded = 0;
    
    BY_TYPE:
    foreach my $type ('LABELS', 'GROUPS') {
        
        my $other_type = 'GROUPS';
        if ($type eq 'GROUPS') {
            $other_type = 'LABELS';
        }

        my $base_type_ref = $self->{$type};

        my $cutCount = 0;
        my $subCutCount = 0;
        @deleteList = ();
        
        BY_ELEMENT:
        foreach my $element ($base_type_ref->get_element_list) {
            #next if ! defined $element;  #  ALL SHOULD BE DEFINED

            #  IGNORE NEXT CONDITION - sometimes we get an element called ''
            #next if (not defined $element);  #  we got an empty list, so don't try anything

            my $failed_a_test = 0;
            
            BY_TEST:
            foreach my $test (keys %test_funcs) {
                next BY_TEST if ! defined $exclusion_hash{$type}{$test};
                
                my $condition = $test_funcs{$test} . $exclusion_hash{$type}{$test};
                
                my $check = eval $condition;
                
                next BY_TEST if ! $check;
                
                $failed_a_test = 1;  #  if we get here we have failed a test, so drop out of the loop
                last BY_TEST;
            }

            if (not $failed_a_test and $type eq 'LABELS') {  #  label specific tests - need to generalise these
                if ((defined $exclusion_hash{$type}{max_range}
                    && $self->get_range(element => $element) >= $exclusion_hash{$type}{max_range})
                    ||
                    (defined $exclusion_hash{$type}{min_range}
                    && $self->get_range(element => $element) <= $exclusion_hash{$type}{min_range})
                    ) {
                    
                    $failed_a_test = 1;
                }
                if (!$failed_a_test && $label_regex) {
                    $failed_a_test = $element =~ $label_regex;
                    if ($label_regex_negate) {
                        $failed_a_test = !$failed_a_test;
                    }
                }
                if (!$failed_a_test && $element_check_list) {
                    $failed_a_test = exists $element_check_list->{$element};
                    if ($element_check_list_negate) {
                        $failed_a_test = !$failed_a_test;
                    }
                }
            }

            next BY_ELEMENT if not $failed_a_test;  #  no fails, so check next element

            $cutCount++;
            push (@deleteList, $element);
        }

        foreach my $element (@deleteList) {  #  having it out here means all are checked against the initial state
            $subCutCount += $self->delete_element (type => $type, element => $element);
        }

        my $lctype = lc ($type);
        if ($cutCount || $subCutCount) {
            $feedback .=
                "Cut $cutCount $lctype on exclusion criteria, deleting $subCutCount "
                . lc($other_type)
                . " in the process\n\n";
            $feedback .=
                "The data now fall into "
                . $self->get_group_count .
                " groups with "
                . $self->get_label_count
                . " unique labels\n\n";

            $excluded ++;
        }
        else {
            $feedback .= "No $lctype excluded when checking $lctype criteria.\n";
        }
        print $feedback;
    }

    if ($excluded) {
        my $e_count = $self->get_param_as_ref ('EXCLUSION_COUNT');
        if (! defined $e_count) { #  create it if needed
            $self->set_param (EXCLUSION_COUNT => 1);
        }
        else {                    # else increment it
            $$e_count ++;
        }
    }
    
    #  now rebuild the index if need be
    if (    $orig_group_count != $self->get_group_count
        and $self->get_param ('SPATIAL_INDEX')
        ) {
        $self->rebuild_spatial_index();
    }

    return $feedback;
}

sub get_exclusion_hash {  #  get the exclusion_hash from the PARAMS
    my $self = shift;

    my $exclusion_hash = $self->get_param('EXCLUSION_HASH')
                      || {};
    
    return wantarray ? %$exclusion_hash : $exclusion_hash;
}

sub trim {
    my $self = shift;
    my %args = @_;
    
    my @outputs = $self->get_output_refs;
    croak "Cannot trim a basedata with existing outputs\n"
      if scalar @outputs;

    croak "neither trim nor keep args specified\n"
      if ! defined $args{keep} && ! defined $args{trim};
    
    my $data;
    my $keep = $args{keep};  #  keep only these (overrides trim)
    my $trim = $args{trim};  #  delete all of these
    if ($keep) {
        $trim = undef;
        $data = $keep;
        print "[BASEDATA] Trimming labels from basedata using keep option\n";
    }
    else {
        $data = $trim;
        print "[BASEDATA] Trimming labels from basedata using trim option\n";
    }

    croak "keep or trim argument is not a ref\n"
      if ! ref $data;

    my %keep_or_trim;

    if (blessed $data) {
        #  assume it is a tree or matrix if blessed
        METHOD:
        foreach my $method (qw /get_named_nodes get_elements/) {
            if ($data->can($method)) {
                %keep_or_trim = $data->$method;
                last METHOD;
            }
        }
    }
    elsif ((ref $keep) =~ /ARRAY/) {  #  convert to hash if needed
        @keep_or_trim{@$data} = 1 x scalar @$data;
    }
    
    my $delete_count = 0;
    my $delete_sub_count = 0;
    
    LABEL:
    foreach my $label ($self->get_labels) {
        if ($keep) {    #  keep if in the list
            next LABEL if exists $keep_or_trim{$label};
        }
        elsif ($trim) { #  trim if not in the list  
            next LABEL if ! exists $keep_or_trim{$label};
        }

        $delete_sub_count +=
            $self->delete_element (
                type    => 'LABELS',
                element => $label,
            );
        $delete_count ++;
    }

    my %results = (
        DELETE_COUNT     => $delete_count,
        DELETE_SUB_COUNT => $delete_sub_count,
    );

    return wantarray ? %results : \%results;
}

#  delete all occurrences of this label from the LABELS and GROUPS sub hashes
sub delete_element {  
    my $self = shift;
    my %args = @_;

    croak "Label or Group not specified in delete_element call\n"
        if ! defined $args{type};
    
    my $type = uc($args{type});
    croak "Invalid element type in call to delete_element, $type\n"
        if $type ne 'GROUPS' && $type ne 'LABELS';

    croak "Element not specified in delete_element call\n"
        if ! defined $args{element};
    my $element = $args{element};

    #  allows us to deal with both labels and groups
    my $other_type = $type eq 'GROUPS'
                        ? 'LABELS'
                        : 'GROUPS';  

    my $type_ref = $self->{$type};
    my $other_type_ref = $self->{$other_type};

    my $subelement_cut_count = 0;

    #  call the Biodiverse::BaseStruct::delete_element sub to clean the $type element
    my @deleted_subelements = $type_ref->delete_element (element => $element);
    #  could use it directly in the next loop, but this is more readable

    #  now we adjust those $other_type elements that have been affected (eg correct Label ranges etc).
    #  use the set of groups containing deleted labels that need correcting (or vice versa)
    foreach my $subelement (@deleted_subelements) {  
        #print "ELEMENT $element, SUBELEMENT $subelement\n";
        #  switch the element/subelement values as they are reverse indexed in $other_type
        $other_type_ref->delete_sub_element(
            element    => $subelement,
            subelement => $element,
        );
        if ($other_type_ref->get_variety(element => $subelement) == 0) {
            # we have wiped out all groups with this label
            # so we need to remove it from the data set
            $other_type_ref->delete_element(element => $subelement);
            $subelement_cut_count ++;
        }
    }

    return $subelement_cut_count;
}

#  delete a subelement from a label or a group
sub delete_sub_element {
    my $self = shift;
    my %args = @_;
    
    my $label = $args{label};
    my $group = $args{group};
    
    my $groups_ref = $self->get_groups_ref;
    my $labels_ref = $self->get_labels_ref;

    #my $orig_range = $labels_ref->get_variety (element => $label);
    #my $orig_richness = $groups_ref->get_richness (element => $group);    
    
    $labels_ref->delete_sub_element (
        element    => $label,
        subelement => $group,
    );
    $groups_ref->delete_sub_element (
        element    => $group,
        subelement => $label,
    );

    #  clean up if labels or groups are now empty
    #my $richness = $groups_ref->get_richness (element => $group);
    #my $range    = $labels_ref->get_variety (element => $label);;
    #
    if ($groups_ref->get_variety (element => $group) == 0) {
        $self->delete_element (
            type => 'GROUPS',
            element => $group,
        );
    }
    if ($labels_ref->get_variety (element => $label) == 0) {
        $self->delete_element (
            type => 'LABELS',
            element => $label,
        );
    }
    
    return;
}

sub get_redundancy {    #  A cheat method, assumes we want group redundancy by default,
                        # drops the call down to the GROUPS object
    my $self = shift;

    return $self->get_groups_ref->get_redundancy(@_);
}

sub get_diversity {  #  more cheat methods
    my $self = shift;

    return $self->get_groups_ref->get_variety(@_);
}

sub get_richness {
    my $self = shift;

    return $self->get_groups_ref->get_variety(@_);
}

sub get_label_sample_count {  
    my $self = shift;

    return $self->get_labels_ref->get_sample_count(@_);
}

sub get_group_sample_count {
    my $self = shift;

    return $self->get_groups_ref->get_sample_count(@_);
}

#  get the range as defined by the user,
#  or based on the variety of groups this labels occurs in
#  take the max if range is < variety
sub get_range {
    my $self = shift;
    
    my $labels_ref = $self->get_labels_ref;
    
    my $props = $labels_ref->get_list_values (@_, list => 'PROPERTIES');
    my %props;
    if ((ref $props) =~ /HASH/) {
        %props = %$props ; #  make a copy - avoid auto-viv.  break otherwise
    }
    
    my $variety = $labels_ref->get_variety (@_);
    
    my $range = $variety;
    if (defined $props{RANGE}) {
        $range = $props{RANGE} > $variety ? $props{RANGE} : $variety;
    }
    
    return $range;
}

#  for backwards compatibility
*get_range_shared = \&get_range_intersection;
*get_range_aggregated = \&get_range_union;

# get the shared range for a set of labels
#  should return the range in scalar context and the keys in list context
#  WARNING - does not work for ranges set externally.  
sub get_range_intersection {
    my $self = shift;
    my %args = @_;
    
    my $labels = $args{labels} || croak "[BaseData] get_range_intersection argument labels not specified\n";
    my $t = ref $labels;
    ref ($labels) =~ /ARRAY|HASH/ || croak "[BaseData] get_range_intersection argument labels not an array or hash ref\n";
    
    $labels = [keys %{$labels}] if (ref ($labels) =~ /HASH/);
    
    #  now loop through the labels and get the groups that contain all the species
    my $elements = {};
    foreach my $label (@$labels) {
        next if not $self->exists_label (label => $label);  #  skip if it does not exist
        my $res = $self->calc_abc (label_hash1 => $elements,
                                     label_hash2 => {$self->get_groups_with_label_as_hash (label => $label)}
                                    );
        #  delete those that are not shared (label_hash1 and label_hash2)
        my @tmp = delete @{$res->{label_hash_all}}{keys %{$res->{label_hash1}}};
        @tmp = delete @{$res->{label_hash_all}}{keys %{$res->{label_hash2}}};
        $elements = $res->{label_hash_all};
    }
    
    return wantarray
        ? (keys %$elements)
        : [keys %$elements];
}


#  get the aggregate range for a set of labels
sub get_range_union {
    my $self = shift;
    my %args = @_;

    my $labels = $args{labels};
    my $lref = ref $labels;

    croak "argument labels not specified\n" if not $labels;
    croak "argument labels not an array or hash ref"
      if not $lref =~ /ARRAY|HASH/;

    if ($lref =~ /HASH/) {
        $labels = [keys %$labels];
    }

    #  now loop through the labels and get the elements they occur in
    my %shared_elements;
    foreach my $label (@$labels) {
        next if not $self->exists_label (label => $label);  #  skip if it does not exist
        my $elements_now = $self->get_groups_with_label_as_hash (label => $label);
        next if (scalar keys %$elements_now) == 0;  #  empty hash - must be no groups with this label
        #  add these elements as a hash slice
        @shared_elements{keys %$elements_now} = values %$elements_now;
    }
    
    return wantarray
        ? (keys %shared_elements)
        : [keys %shared_elements];
}

sub get_groups {  #  get a list of the groups in the data set
    my $self = shift;
    my %args = @_;
    return $self->get_groups_ref->get_element_list;
}

sub get_labels { #  get a list of the labels in the selected BaseData
    my $self = shift;
    my %args = @_;
    return $self->get_labels_ref->get_element_list;
}

sub get_groups_with_label {  #  get a list of the groups that contain $label
    my $self = shift;
    my %args = @_;
    confess "Label not specified\n" if ! defined $args{label};
    return $self->get_labels_ref->get_sub_element_list (element => $args{label});
}

sub get_groups_with_label_as_hash {  #  get a hash of the groups that contain $label
    my $self = shift;
    my %args = @_;

    croak "Label not specified\n" if ! defined $args{label};

    if (! defined $args{use_elements}) {
        #  takes care of the wantarray stuff this way
        return $self->get_labels_ref->get_sub_element_hash (element => $args{label});
    }

    #  Not sure why the rest is here - is it used anywhere?
    #  violates the guide'ine that subs should do one thing only

    #  make a copy - don't want to delete the original
    my %results = $self->get_labels_ref->get_sub_element_hash (element => $args{label});

    #  get a list of keys we don't want
    no warnings 'uninitialized';  #  in case a list containing nulls is sent through
    my %sub_results = %results;
    delete @sub_results{@{$args{use_elements}}};

    #  now we delete those keys we don't want.  Twisted, but should work.
    delete @results{keys %sub_results};

    return wantarray
            ? %results
            : \%results;
}

#  get the complement of the labels in a group
#  - everything not in this group
sub get_groups_without_label {
    my $self = shift;

    my $groups = $self->get_groups_without_label_as_hash (@_);

    return wantarray ? keys %$groups : [keys %$groups];
}

sub get_groups_without_label_as_hash {
    my $self = shift;
    my %args = @_;

    croak "Label not specified\n"
        if ! defined $args{label};

    my $label_gps = $self->get_labels_ref->get_sub_element_hash (element => $args{label});

    my %groups = $self->get_groups_ref->get_element_hash;  #  make a copy

    delete @groups{keys %$label_gps};

    return wantarray ? %groups : \%groups;
}



sub get_labels_in_group {  #  get a list of the labels that occur in $group
    my $self = shift;
    my %args = @_;
    croak "Group not specified\n" if ! defined $args{group};
    return $self->get_groups_ref->get_sub_element_list(element => $args{group});
}

sub get_labels_in_group_as_hash {  #  get a hash of the labels that occur in $group
    my $self = shift;
    my %args = @_;
    croak "Group not specified\n" if ! defined $args{group};
    return $self->get_groups_ref->get_sub_element_hash(element => $args{group});
}

#  get the complement of the labels in a group
#  - everything not in this group
sub get_labels_not_in_group {
    my $self = shift;
    my %args = @_;
    croak "Group not specified\n" if ! defined $args{group};
    my $gp_labels = $self->get_groups_ref->get_sub_element_hash (element => $args{group});
    
    my %labels = $self->get_labels_ref->get_element_hash;  #  make a copy
    
    delete @labels{keys %$gp_labels};
    
    return wantarray ? keys %labels : [keys %labels];
}

sub get_label_count {
    my $self = shift;
    
    return $self->get_labels_ref->get_element_count;
}

#  get the number of columns used to build the labels
sub get_label_column_count {
    my $self = shift;

    my $labels_ref = $self->get_labels_ref;
    my @labels = $labels_ref->get_element_list;

    return 0 if not scalar @labels;
    
    my $label_columns =
      $labels_ref->get_element_name_as_array (element => $labels[0]);
    
    return scalar @$label_columns;
}

sub get_group_count {
    my $self = shift;

    return $self->get_groups_ref->get_element_count;
}

sub exists_group {
    my $self = shift;
    my %args = @_;
    return $self->get_groups_ref->exists_element (
        element => defined $args{group} ? $args{group} : $args{element}
    );
}

sub exists_label {
    my $self = shift;
    my %args = @_;
    return $self->get_labels_ref->exists_element (
        element => defined $args{label} ? $args{label} : $args{element}
    );
}

sub write_table {  #  still needed?
    my $self = shift;
    my %args = @_;
    croak "Type not specified\n" if ! defined $args{type};
    
    #  Just pass the args straight through
    $self->{$args{type}}->write_table(@_);  

    return;
}

#  is this still needed?
sub write_sub_elements_csv {  
    my $self = shift;
    my %args = @_;
    croak "Type not specified\n" if ! defined $args{type};
    my $data = $self->{$args{type}}->to_table (@_, list => 'SUBELEMENTS');
    $self->write_table (@_, data => $data);

    return;
}

sub get_groups_ref {
    my $self = shift;
    return $self->{GROUPS};
}

sub get_labels_ref {
    my $self = shift;
    return $self->{LABELS};
}

sub build_spatial_index {  #  builds GROUPS, not LABELS
    my $self = shift;

    #  need to get a hash of all the groups and their coords.
    my %groups;
    my $gp_object = $self->get_groups_ref;
    foreach my $gp ($self->get_groups) {
        $groups{$gp} = $gp_object->get_element_name_as_array (element => $gp);
    }
    
    my $index = Biodiverse::Index->new (@_, element_hash => \%groups);
    $self->set_param (SPATIAL_INDEX => $index);
    
    return;
}

sub delete_spatial_index {
    my $self = shift;
    
    my $name = $self->get_param ('NAME');

    if ($self->get_param ('SPATIAL_INDEX')) {
        print "[Basedata] Deleting spatial index from $name\n";
        $self->delete_param('SPATIAL_INDEX');
        return 1;
    }

    print "[Basedata] Unable to delete a spatial index that does not exist\n";

    return;
}

sub rebuild_spatial_index {
    my $self = shift;
    
    my $index = $self->get_param ('SPATIAL_INDEX');
    return if ! defined $index;
    
    my $resolutions = $index->get_param('RESOLUTIONS');
    $self->build_spatial_index (resolutions => $resolutions);
    
    return;
}

sub delete_output {
    my $self = shift;
    my %args = @_;

    my $object = $args{output};
    my $name = $object->get_param('NAME');

    my $type = blessed $object;
    $type =~ s/.*://; #  get the last part
    print "[BASEDATA] Deleting $type output $name\n";
    
    if ($type =~ /Spatial/) {
        $self->{SPATIAL_OUTPUTS}{$name} = undef;
        delete $self->{SPATIAL_OUTPUTS}{$name};
    }
    elsif ($type =~ /Cluster|Tree|RegionGrower/) {
        my $x = eval {$object->delete_cached_values_below};
        $self->{CLUSTER_OUTPUTS}{$name} = undef;
        delete $self->{CLUSTER_OUTPUTS}{$name};
    }
    elsif ($type =~ /Matrix/) {
        $self->{MATRIX_OUTPUTS}{$name} = undef;
        delete $self->{MATRIX_OUTPUTS}{$name};
    }
    elsif ($type =~ /Randomise/) {
        $self->do_delete_randomisation (@_);
    }
    else {
        croak "[BASEDATA] Cannot delete this type of output: ",
              blessed ($object) || $EMPTY_STRING,
              "\n";
    }
    
    if (!defined $args{delete_basedata_ref} || $args{delete_basedata_ref}) {
        $object->set_param (BASEDATA_REF => undef);  #  free its parent ref
    }
    $object = undef;  #  clear it

    return;
}

#  deletion of these is more complex than spatial and cluster outputs
sub do_delete_randomisation {
    my $self = shift;
    my %args = @_;
    
    my $object = $args{output};
    my $name = $object->get_param('NAME');
    
    print "[BASEDATA] Deleting randomisation output $name\n";
    
    #  loop over the spatial outputs and clear the lists
    BY_SPATIAL_OUTPUT:
    foreach my $sp_output ($self->get_spatial_output_refs) {
        my @lists = grep {$_ =~ /^$name>>/} $sp_output->get_lists_across_elements;
        unshift @lists, $name; #  for backwards compatibility

        BY_ELEMENT:
        foreach my $element ($sp_output->get_element_list) {
            $sp_output->delete_lists (
                lists   => \@lists,
                element => $element
            );
        }
    }
    
    #  and now the cluster outputs
    my @node_lists = (
        $name,
        $name . '_SPATIAL',  #  for backwards compat
        $name . '_ID_LDIFFS',
        $name . '_DATA',
    );


    BY_CLUSTER_OUTPUT:
    foreach my $cl_output ($self->get_cluster_output_refs) {
        my @lists = grep {$_ =~ /^$name>>/} $cl_output->get_list_names_below;
        my @lists_to_delete = (@node_lists, @lists);
        $cl_output->delete_lists_below (lists => \@lists_to_delete);
    }
    
    
    $self->{RANDOMISATION_OUTPUTS}{$name} = undef;
    delete $self->{RANDOMISATION_OUTPUTS}{$name};

    $object->set_param (BASEDATA_REF => undef);  #  free its parent ref
    
    return;
}


#  generic handler for adding outputs.
#  could eventually replace the specific forms
sub add_output {
    my $self = shift;
    my %args = @_;
    
    my $object = $args{object}
                || $args{type}
                || croak "[BASEDATA] No valid object or type arg specified, add_output\n";

    my $class = blessed ($object) || $object;
    if ($class =~ /spatial/i) {
        return $self->add_spatial_output (@_);
    }
    elsif ($class =~ /Cluster|RegionGrower/i) {
        return $self->add_cluster_output (@_);
    }
    elsif ($class =~ /randomisation/i) {
        return $self->add_randomisation_output (@_);
    }
    elsif ($class =~ /matrix/i) {
        return $self->add_matrix_output (@_);
    }
    
    #  if we get this far then we have problems
    croak "[BASEDATA] No valid object or type arg specified, add_output\n";
}

#  get refs to the spatial and cluster objects
sub get_output_refs {
    my $self = shift;

    my @refs = (
        $self->get_spatial_output_refs,
        $self->get_cluster_output_refs,
        $self->get_randomisation_output_refs,
        $self->get_matrix_output_refs,
    );

    return wantarray ? @refs : \@refs;    
}

sub get_output_ref_count {
    my $self = shift;

    my $refs = $self->get_output_refs;

    return scalar @$refs;
}

sub get_output_refs_sorted_by_name {
    my $self = shift;
    my @sorted = sort
        {$a->get_param('NAME') cmp $b->get_param('NAME')}
        $self->get_output_refs();
    
    return wantarray ? @sorted : \@sorted;
}

sub get_output_refs_of_class {
    my $self = shift;
    my %args = @_;
    
    my $class = blessed $args{class} // $args{class}
      or croak "argument class not specified\n";

    my @outputs;
    foreach my $ref ($self->get_output_refs) {
        next if ! (blessed ($ref) eq $class);
        push @outputs, $ref;
    };
    
    return wantarray ? @outputs : \@outputs;
}

sub delete_all_outputs {
    my $self = shift;
    
    foreach my $output ($self->get_output_refs) {
        $self->delete_output (output => $output);
    }
    
    return;
}


########################################################
#  methods to set, create and select the cluster outputs

sub add_cluster_output {
    my $self = shift;
    my %args = @_;
    
    my $object = $args{object};
    delete $args{object};  #  add an existing output
    
    my $class = $args{type} || 'Biodiverse::Cluster';
    my $name = $object ? $object->get_param('NAME') : $args{name};
    delete $args{name};

    croak "[BASEDATA] argument 'name' not specified\n"
        if ! defined $name;

    croak "[BASEDATA] Cannot replace existing cluster object $name. Use a different name.\n"
        if exists $self->{CLUSTER_OUTPUTS}{$name};
    
    if ($object) {
        #  check if it is the correct type, warn if not - caveat emptor if wrong type
        #  check is a bit underhanded, as it does not allow abstraction - clean up later if needed
        
        my $obj_class = blessed ($object);
        carp "[BASEDATA] Object is not of valid type ($class)"
            if not $class =~ /cluster|regiongrower/i;

        $object->set_param (BASEDATA_REF => $self);
        $object->weaken_basedata_ref;
    }
    else {  #  create a new object
        $object = $class->new (
            QUOTES       => $self->get_param('QUOTES'),
            JOIN_CHAR    => $self->get_param('JOIN_CHAR'),
            %args,
            NAME         => $name,  #  these two always over-ride user args (NAME can be an arg)
            BASEDATA_REF => $self,
        );
    }


    $self->{CLUSTER_OUTPUTS}{$name} = $object;

    return $object;
}

sub delete_cluster_output {
    my $self = shift;
    my %args = @_;
    croak "parameter 'name' not specified\n"
        if ! defined $args{name};

    #delete $self->{CLUSTER_OUTPUTS}{$args{name}};
    $self->delete_output (
        output => $self->{CLUSTER_OUTPUTS}{$args{name}},
    );

    return;
}

sub get_cluster_output_ref {  #  return the reference for a specified output
    my $self = shift;
    my %args = @_;

    return if ! exists $self->{CLUSTER_OUTPUTS}{$args{name}};

    return $self->{CLUSTER_OUTPUTS}{$args{name}};
}

sub get_cluster_output_refs {
    my $self = shift;
    return values %{$self->{CLUSTER_OUTPUTS}} if wantarray;
    return [values %{$self->{CLUSTER_OUTPUTS}}];
}

sub get_cluster_output_names {
    my $self = shift;
    return keys %{$self->{CLUSTER_OUTPUTS}} if wantarray;
    return [keys %{$self->{CLUSTER_OUTPUTS}}];
}

sub get_cluster_outputs {
    my $self = shift;
    return %{$self->{CLUSTER_OUTPUTS}} if wantarray;
    return {%{$self->{CLUSTER_OUTPUTS}}};
}

#  delete any cached values from the trees, eg _cluster_colour
#  allow more specific deletions by passing on the args
sub delete_cluster_output_cached_values {
    my $self = shift;
    print "[BASEDATA] Deleting cached values in cluster trees\n";
    foreach my $cluster ($self->get_cluster_output_refs) {
        $cluster->delete_cached_values_below (@_);
    }
    
    return;
}



########################################################
#  methods to set, create and select the current spatial object

sub add_spatial_output {
    my $self = shift;
    my %args = @_;
    
    croak "[BASEDATA] argument name not specified\n"
        if (! defined $args{name});
    
    my $class = 'Biodiverse::Spatial';
    my $name = $args{name};
    delete $args{name};
    
    croak "[BASEDATA] Cannot replace existing spatial object $name.  Use a different name.\n"
        if defined $self->{SPATIAL_OUTPUTS}{$name};

    my $object = $args{object};
    delete $args{object};  #  add an existing output

    if ($object) {
        #  check if it is the correct type, warn if not - caveat emptor if wrong type
        #  check is a bit underhanded, as it does not allow abstraction - clean up later if needed
        my $obj_class = blessed ($object);
        carp "[BASEDATA] Object is not of type $class"
            if $class ne $obj_class;
        
        $object->set_param (BASEDATA_REF => $self);
        $object->weaken_basedata_ref;
    }
    else {  #  create a new object
        $object = $class->new (
            QUOTES       => $self->get_param('QUOTES'),
            JOIN_CHAR    => $self->get_param('JOIN_CHAR'),
            %args,
            NAME         => $name,  #  these two always over-ride user args (NAME can be an arg)
            BASEDATA_REF => $self,
        );
    }

    $self->{SPATIAL_OUTPUTS}{$name} = $object;  #  add or replace (take care with the replace)

    return $object;
}

sub get_spatial_output_ref {  #  return the reference for a specified output
    my $self = shift;
    my %args = @_;

    return if ! exists $self->{SPATIAL_OUTPUTS}{$args{name}};

    return $self->{SPATIAL_OUTPUTS}{$args{name}};
}

sub get_spatial_output_list {
    my $self = shift;

    my @result = sort keys %{$self->{SPATIAL_OUTPUTS}};
    return wantarray ? @result : \@result;
}

sub delete_spatial_output {
    my $self = shift;
    my %args = @_;
    
    croak "parameter name not specified\n" if ! defined $args{name};
    #delete $self->{SPATIAL_OUTPUTS}{$args{name}};
    $self->delete_output (output => $self->{SPATIAL_OUTPUTS}{$args{name}});
    
    return;    
}

sub get_spatial_output_refs {
    my $self = shift;
    return wantarray
            ? values %{$self->{SPATIAL_OUTPUTS}}
            : [values %{$self->{SPATIAL_OUTPUTS}}];
}

sub get_spatial_output_names {
    my $self = shift;
    return wantarray
            ? keys %{$self->{SPATIAL_OUTPUTS}}
            : [keys %{$self->{SPATIAL_OUTPUTS}}];
}

sub get_spatial_outputs {
    my $self = shift;
    return wantarray
            ? %{$self->{SPATIAL_OUTPUTS}}
            : {%{$self->{SPATIAL_OUTPUTS}}};
}

########################################################
#  methods to set, create and select the current matrix output object

sub add_matrix_output {
    my $self = shift;
    my %args = @_;
    
    my $class = 'Biodiverse::Matrix';
    
    my $object = $args{object};
    delete $args{object};  #  add an existing output

    my $name;
    
    if ($object) {
        #  check if it is the correct type, warn if not - caveat emptor if wrong type
        #  check is a bit underhanded, as it does not allow abstraction - clean up later if needed
        my $obj_class = blessed ($object);
        carp "[BASEDATA] Object is not of type $class"
            if $class ne $obj_class;

        $name = $object->get_param('NAME');

        croak "[BASEDATA] Cannot replace existing matrix object $name.  Use a different name.\n"
            if defined $self->{MATRIX_OUTPUTS}{$name};

        $object->set_param (BASEDATA_REF => $self);
        $object->weaken_basedata_ref;
    }
    else {  #  create a new object
        croak "Creation of matrix new objects is not supported - they are added by the clustering system\n";
        
        croak "[BASEDATA] argument name not specified\n"
            if (! defined $args{name});

        $name = $args{name};
        delete $args{name};

        croak "[BASEDATA] Cannot replace existing matrix object $name.  Use a different name.\n"
            if defined $self->{MATRIX_OUTPUTS}{$name};

        $object = $class->new (
            QUOTES       => $self->get_param('QUOTES'),
            JOIN_CHAR    => $self->get_param('JOIN_CHAR'),
            %args,
            NAME         => $name,  #  these two always over-ride user args (NAME can be an arg)
            BASEDATA_REF => $self,
        );
    }

    $self->{MATRIX_OUTPUTS}{$name} = $object;  #  add or replace (take care with the replace)

    return $object;
}

sub get_matrix_output_ref {  #  return the reference for a specified output
    my $self = shift;
    my %args = @_;
    
    return if ! exists $self->{MATRIX_OUTPUTS}{$args{name}};
    
    return $self->{MATRIX_OUTPUTS}{$args{name}};
}

sub get_matrix_output_list {
    my $self = shift;
    my @result = sort keys %{$self->{MATRIX_OUTPUTS}};
    return wantarray ? @result : \@result;
}

sub delete_matrix_output {
    my $self = shift;
    my %args = @_;
    
    croak "parameter name not specified\n" if ! defined $args{name};
    #delete $self->{MATRIX_OUTPUTS}{$args{name}};
    $self->delete_output (output => $self->{MATRIX_OUTPUTS}{$args{name}});
    
    return;    
}

sub get_matrix_output_refs {
    my $self = shift;
    $self->_set_matrix_ouputs_hash;
    return wantarray
            ? values %{$self->{MATRIX_OUTPUTS}}
            : [values %{$self->{MATRIX_OUTPUTS}}];
}

sub get_matrix_output_names {
    my $self = shift;
    $self->_set_matrix_ouputs_hash;
    return wantarray
            ? keys %{$self->{MATRIX_OUTPUTS}}
            : [keys %{$self->{MATRIX_OUTPUTS}}];
}

sub get_matrix_outputs {
    my $self = shift;
    $self->_set_matrix_ouputs_hash;
    return wantarray
            ? %{$self->{MATRIX_OUTPUTS}}
            : {%{$self->{MATRIX_OUTPUTS}}};
}

sub _set_matrix_ouputs_hash {
    my $self = shift;
    if (! $self->{MATRIX_OUTPUTS}) {
        $self->{MATRIX_OUTPUTS} = {};
    }
}


########################################################
#  methods to set, create and select randomisation objects


sub add_randomisation_output {
    my $self = shift;
    my %args = @_;
    if (! defined $args{name}) {
        croak "[BASEDATA] argument name not specified\n";
        #return undef;
    }
    my $class = 'Biodiverse::Randomise';

    my $name = $args{name};
    delete $args{name};

    croak "[BASEDATA] Cannot replace existing randomisation object $name.  Use a different name.\n"
        if exists $self->{RANDOMISATION_OUTPUTS}{$name};

    my $object = $args{object};
    delete $args{object};  #  add an existing output

    if ($object) {
        #  check if it is the correct type, warn if not - caveat emptor if wrong type
        #  check is a bit underhanded, as it does not allow abstraction - clean up later if needed
        my $obj_class = blessed ($object);

        carp "[BASEDATA] Object is not of type $class"
          if $class ne $obj_class;

        $object->set_param (BASEDATA_REF => $self);
        $object->weaken_basedata_ref;
    }
    else {  #  create a new object
        $object = eval {
            $class->new (
                %args,
                NAME         => $name,  #  these two always over-ride user args (NAME can be an arg)
                BASEDATA_REF => $self,
            );
        };
        croak $EVAL_ERROR if $EVAL_ERROR;
    }
    
    $self->{RANDOMISATION_OUTPUTS}{$name} = $object;
    undef $object;
    return $self->{RANDOMISATION_OUTPUTS}{$name};
    #  fiddling to avoid SV leaks, possibly pointless
    #my $object2 = $object;
    #undef $object;
    #return $object2;
}

sub get_randomisation_output_ref {  #  return the reference for a specified output
    my $self = shift;
    my %args = @_;
    return undef if ! exists $self->{RANDOMISATION_OUTPUTS}{$args{name}};
    return $self->{RANDOMISATION_OUTPUTS}{$args{name}};
}

sub get_randomisation_output_list {
    my $self = shift;
    my @list = sort keys %{$self->{RANDOMISATION_OUTPUTS}};
    return wantarray ? @list : \@list;
}

sub delete_randomisation_output {
    my $self = shift;
    my %args = @_;
    croak "parameter name not specified\n" if ! defined $args{name};
    #delete $self->{SPATIAL_OUTPUTS}{$args{name}};
    $self->delete_output (output => $self->{RANDOMISATION_OUTPUTS}{$args{name}});

    return;
}

sub get_randomisation_output_refs {
    my $self = shift;
    return values %{$self->{RANDOMISATION_OUTPUTS}} if wantarray;
    return [values %{$self->{RANDOMISATION_OUTPUTS}}];
}

sub get_randomisation_output_names {
    my $self = shift;
    return keys %{$self->{RANDOMISATION_OUTPUTS}} if wantarray;
    return [keys %{$self->{RANDOMISATION_OUTPUTS}}];
}

sub get_randomisation_outputs {
    my $self = shift;
    return %{$self->{RANDOMISATION_OUTPUTS}} if wantarray;
    return {%{$self->{RANDOMISATION_OUTPUTS}}};
}

sub get_unique_randomisation_name {
    my $self = shift;
    
    my @names = $self->get_randomisation_output_names;
    my $prefix = 'Rand';
    
    my $max = 0;
    foreach my $name (@names) {
        my $num = $name =~ /$prefix(\d+)$/;
        $max = $num if $num > $max;
    }

    my $unique_name = $prefix . ($max + 1);
    
    return $unique_name;
}


########################################################
#  methods to get neighbours, parse parameters etc.

#  get the list of neighbours that satisfy the spatial condition
#  (or the set of elements that satisfy definition query)
sub get_neighbours {  
    my $self = shift;
    my %args = @_;
    
    my $progress = $args{progress};
    
    my $element1 = $args{element};
    croak "argument element not specified\n" if ! defined $element1;

    my $spatial_params = $args{spatial_params}
                       || $self->get_param ('SPATIAL_PARAMS')
                       || croak "[BASEDATA] No spatial params\n";
    my $index = $args{index};
    my $is_def_query = $args{is_def_query};  #  some processing changes if a def query
    my $cellsizes = $self->get_param ('CELL_SIZES');

    #  skip those elements that we want to ignore - allows us to avoid including
    #  element_list1 elements in these neighbours,
    #  therefore making neighbourhood parameter definitions easier.
    my %exclude_hash =
      $self->array_to_hash_keys (
        list  => $args{exclude_list},
        value => 1,
    );

    my $centre_coord_ref =
      $self->get_group_element_as_array (element => $element1);
    
    my $groupsRef = $self->get_groups_ref;

    my @compare_list;  #  get the list of possible neighbours - should allow this as an arg?
    if (not defined $args{index}) {
        @compare_list = $self->get_groups;
    }
    else {  #  we have a spatial index defined - get the possible list of neighbours
        my $element_array =
          $self->get_group_element_as_array (element => $element1);

        my $index_coord = $index->snap_to_index (
            element_array => $element_array,
            as_array      => 1,
        );
        foreach my $offset (keys %{$args{index_offsets}}) {
            #  need to get an array from the index to fit
            #  with the get_groups results
            push @compare_list,
              $index->get_index_elements_as_array (
                    element => $index_coord,
                    offset  => $offset
            );
        }
    }
    
    #  Do we have a shortcut where we don't have to deal
    #  with all of the comparisons? (messy at the moment)
    my $type_is_subset = $spatial_params->get_result_type eq 'subset'
                       ? 1
                       : undef;

    #print "$element1  Evaluating ", scalar @compare_list, " nbrs\n";

    my $target_comparisons = scalar @compare_list;
    my $i = 0;
    my %valid_nbrs;
    NBR:
    foreach my $element2 (sort @compare_list) {
        
        if ($progress) {
            $i ++;
            $progress->update(
                "Neighbour comparison $i of $target_comparisons\n",
                $i / $target_comparisons,
            );
        }

        #  some of the elements may be undefined based
        #  on calls to get_index_elements
        next NBR if not defined $element2;

        #  skip if in the exclusion list
        next NBR if exists $exclude_hash{$element2};

        #  warn and skip if already done
        if (exists $valid_nbrs{$element2}) {
            warn "[BaseData] get_neighbours: Double checking of $element2\n";
            next NBR;
        }

        #  make the neighbour coord available to the spatial_params
        my @coord =
           $self->get_group_element_as_array (element => $element2);
           
        my %eval_args;
        #  Reverse some args for def queries,
        #  partly for backwards compatibility,
        #  partly for cleaner logic.
        if ($is_def_query) {  
            %eval_args = (
                coord_array1 => \@coord,
                coord_id1    => $element2,
                coord_id2    => $element2,
            );
        }
        else {
            %eval_args = (
                coord_array1 => $centre_coord_ref,
                coord_array2 => \@coord,
                coord_id1    => $element1,
                coord_id2    => $element2,
            );
        }

        my $success = $spatial_params->evaluate (
            %eval_args,
            cellsizes     => $cellsizes,
            caller_object => $self,  #  pass self on by default
        );

        if ($type_is_subset) {  
            my $subset_nbrs = $spatial_params->get_cached_subset_nbrs (coord_id => $element1);
            if ($subset_nbrs) {
                %valid_nbrs = %$subset_nbrs;
                #print "Found ", scalar keys %valid_nbrs, " valid nbrs\n";
                delete @valid_nbrs{keys %exclude_hash};
                $spatial_params->clear_cached_subset_nbrs(coord_id => $element1);
                last NBR;
            }
        }

        #  skip if not a nbr
        next NBR if not $success;

        # If it has survived then it must be valid.
        #$valid_nbrs{$element2} = $spatial_params->get_param ('LAST_DISTS');  #  store the distances for possible later use
        $valid_nbrs{$element2} = 1;  #  don't store the dists - serious memory issues for large files
    }

    if ($args{as_array}) {
        return wantarray ? keys %valid_nbrs : [keys %valid_nbrs];
    }
    else {
        return wantarray ? %valid_nbrs : \%valid_nbrs;
    }
}

sub get_neighbours_as_array {
    my $self = shift;
    return $self->get_neighbours (@_, as_array => 1);
    
    #  commented old stuff, hopefully the new approach will save some shunting around of memory?
    #my @array = sort keys %{$self->get_neighbours(@_)};
    #return wantarray ? @array : \@array;  #  return reference in scalar context
}
    
    
##  get a list of spatial outputs with the same spatial params
##  Useful for faster nbr searching
#sub get_spatial_outputs_with_same_nbrs {
#    my $self = shift;
#    my %args = @_;
#    
#    my $compare = $args{compare_with} || croak "[BASEDATA] Nothing to compare with\n";
#    
#    my $sp_params = $compare->get_param ('SPATIAL_PARAMS');
#    my $def_query = $compare->get_param ('DEFINITION_QUERY');
#    if (defined $def_query && (length $def_query) == 0) {
#        $def_query = undef;
#    }
#    
#    my $def_conditions;
#    if (blessed $def_query) {
#        $def_conditions = $def_query->get_conditions_unparsed();
#    }
#
#    my %outputs = $self->get_spatial_outputs;
#    
#    LOOP_SP_OUTPUTS:
#    foreach my $output (values %outputs) {
#        next LOOP_SP_OUTPUTS if $output eq $compare;  #  skip the one to compare
#        
#        my $completed = $output->get_param ('COMPLETED');
#        next LOOP_SP_OUTPUTS if defined $completed and ! $completed;
#        
#        my $def_query_comp = $output->get_param ('DEFINITION_QUERY');
#        if (defined $def_query) {
#            #  only check further if both have def queries
#            next LOOP_SP_OUTPUTS if ! defined $def_query_comp;
#            
#            #  check their def queries match
#            my $def_conditions_comp = $def_query_comp->get_conditions_unparsed();
#            next LOOP_SP_OUTPUTS if $def_conditions_comp ne $def_conditions;
#        }
#        else {
#            #  skip if one is defined but the other is not
#            next LOOP_SP_OUTPUTS if defined $def_query_comp;
#        }
#        
#        my $sp_params_comp = $output->get_param ('SPATIAL_PARAMS');
#        
#        #  must have same number of conditions
#        next LOOP_SP_OUTPUTS if scalar @$sp_params_comp != scalar @$sp_params;
#        
#        my $i = 0;
#        LOOP_SP_CONDITIONS:
#        foreach my $sp_obj (@$sp_params_comp) {
#            if ($sp_params->[$i]->get_param ('CONDITIONS') ne $sp_obj->get_conditions_unparsed()) {
#                next LOOP_SP_OUTPUTS;
#            }
#            $i++;
#        }
#
#        #  if we get this far then we have a match
#        return $output;  #  we want to keep this one
#    }
#    
#    return;
#}

#  Modified version of get_spatial_outputs_with_same_nbrs.
#  Useful for faster nbr searching for spatial analyses, and matrix building for cluster analyses
#  It can eventually supplant that sub.
sub get_outputs_with_same_conditions {
    my $self = shift;
    my %args = @_;
    
    my $compare = $args{compare_with} || croak "[BASEDATA] compare_with argument not specified\n";
    
    my $sp_params = $compare->get_param ('SPATIAL_PARAMS');
    my $def_query = $compare->get_param ('DEFINITION_QUERY');
    if (defined $def_query && (length $def_query) == 0) {
        $def_query = undef;
    }
    
    my $def_conditions;
    if (blessed $def_query) {
        $def_conditions = $def_query->get_conditions_unparsed();
    }

    my $cluster_index = $compare->get_param ('CLUSTER_INDEX');

    my @outputs = $self->get_output_refs_of_class (class => $compare);

    LOOP_OUTPUTS:
    foreach my $output (@outputs) {
        next LOOP_OUTPUTS if $output eq $compare;  #  skip the one to compare

        my $completed = $output->get_param ('COMPLETED');
        next LOOP_OUTPUTS if defined $completed and ! $completed;
        
        my $def_query_comp = $output->get_param ('DEFINITION_QUERY');
        if (defined $def_query) {
            #  only check further if both have def queries
            next LOOP_OUTPUTS if ! defined $def_query_comp;

            #  check their def queries match
            my $def_conditions_comp = eval {$def_query_comp->get_conditions_unparsed()} // $def_query_comp;
            my $def_conditions_text = eval {$def_query->get_conditions_unparsed()}      // $def_query;
            next LOOP_OUTPUTS if $def_conditions_comp ne $def_conditions_text;
        }
        else {
            #  skip if one is defined but the other is not
            next LOOP_OUTPUTS if defined $def_query_comp;
        }

        my $sp_params_comp = $output->get_param ('SPATIAL_PARAMS') || [];

        #  must have same number of conditions
        next LOOP_OUTPUTS if scalar @$sp_params_comp != scalar @$sp_params;

        my $i = 0;
        foreach my $sp_obj (@$sp_params_comp) {
            next LOOP_OUTPUTS
              if ($sp_params->[$i]->get_param ('CONDITIONS') ne $sp_obj->get_conditions_unparsed());
            $i++;
        }

        #  if we are a cluster (or output with a cluster index, like a RegionGrower)
        next LOOP_OUTPUTS if defined $cluster_index && $cluster_index ne $output->get_param ('CLUSTER_INDEX');

        #  if we get this far then we have a match
        return $output;  #  we want to keep this one
    }

    return;
}


##  Get a list of cluster outputs with the same spatial params
##  and index parameters.
##  Useful for faster cluster building.
#sub get_cluster_outputs_with_same_index_and_nbrs {
#    my $self = shift;
#    my %args = @_;
#
#    my $compare = $args{compare_with} || croak "[BASEDATA] Nothing to compare with\n";
#
#    my $index     = $compare->get_param('CLUSTER_INDEX');
#    my $sp_params = $compare->get_param('SPATIAL_PARAMS');
#    my $def_query = $compare->get_param('DEFINITION_QUERY');
#    if (defined $def_query && (length $def_query) == 0) {
#        $def_query = undef;
#    }
#    
#    my $def_conditions;
#    if (blessed $def_query) {
#        $def_conditions = $def_query->get_conditions_unparsed();
#    }
#
#    my %outputs = $self->get_spatial_outputs;
#    
#    LOOP_OUTPUTS:
#    foreach my $output (values %outputs) {
#        next LOOP_OUTPUTS if $output eq $compare;  #  skip the one to compare
#
#        my $completed = $output->get_param ('COMPLETED');
#        next LOOP_OUTPUTS if defined $completed and not $completed;
#        next LOOP_OUTPUTS if $completed == 3;  #  matrix was dumped to file
#
#        my $index_comp = $output->get_param('CLUSTER_INDEX');
#        next LOOP_OUTPUTS if $index ne $index_comp;
#
#        my $def_query_comp = $output->get_param('DEFINITION_QUERY');
#        if (defined $def_query) {
#            #  only check further if both have def queries
#            next LOOP_OUTPUTS if ! defined $def_query_comp;
#            
#            #  check their def queries match
#            my $def_conditions_comp = $def_query_comp->get_conditions_unparsed();
#            next LOOP_OUTPUTS if $def_conditions_comp ne $def_conditions;
#        }
#        else {
#            #  skip if one is defined but the other is not
#            next LOOP_OUTPUTS if defined $def_query_comp;
#        }
#
#        my $sp_params_comp = $output->get_param('SPATIAL_PARAMS');
#
#        #  must have same number of conditions
#        next LOOP_OUTPUTS if scalar @$sp_params_comp != scalar @$sp_params;
#
#        my $i = 0;
#        LOOP_SP_CONDITIONS:
#        foreach my $sp_obj (@$sp_params_comp) {
#            if ($sp_params->[$i]->get_param('CONDITIONS') ne $sp_obj->get_conditions_unparsed()) {
#                next LOOP_SP_OUTPUTS;
#            }
#            $i++;
#        }
#
#        #  if we get this far then we have a match
#        return $output;  #  we want to keep this one
#    }
#
#    return;
#    
#}


sub numerically {$a <=> $b};


#  let the system handle it most of the time
sub DESTROY {
    my $self = shift;
    my $name = $self->get_param ('NAME') || $EMPTY_STRING;
    #print "DESTROYING BASEDATA $name\n";
    #$self->delete_all_outputs;  #  delete children which refer to this object
    #print "DELETED BASEDATA $name\n";
    
    #$self->_delete_params_all;
    
    foreach my $key (sort keys %$self) {  #  clear all the top level stuff
        #$self->{$key} = undef;
        #print "Deleting BD $key\n";
        delete $self->{$key};
    }
    undef %$self;
    #  let perl handle the rest
    
    return;
}


=head1 NAME

Biodiverse::BaseData

=head1 SYNOPSIS

  use Biodiverse::BaseData;
  $object = Biodiverse::BaseData->new();

=head1 DESCRIPTION

TO BE FILLED IN

=head1 METHODS

=over

=item NEED TO INSERT METHODS

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
