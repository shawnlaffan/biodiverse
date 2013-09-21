package Biodiverse::Matrix;

#  package to handle matrices for Biodiverse objects
#  these are not matrices in the proper sense of the word, but are actually hash tables to provide easier linking
#  they are also double indexed - "by pair" and "by value by pair".

use strict;
use warnings;

our $VERSION = '0.18_007';

use English ( -no_match_vars );

use Carp;
use Data::Dumper;
use Scalar::Util qw /looks_like_number blessed/;
use List::Util qw /min max sum/;
use File::BOM qw /:subs/;

my $EMPTY_STRING = q{};

#  access the miscellaneous functions as methods
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
        OUTPFX               => 'BIODIVERSE',
        OUTSUFFIX            => 'bms',
        OUTSUFFIX_YAML       => 'bmy',
        TYPE                 => undef,
        QUOTES               => q{'},
        JOIN_CHAR            => q{:},  #  used for labels
        ELEMENT_COLUMNS      => [1,2],  #  default columns in input file to define the names (eg genus,species).  Should not be used as a list here.
        PARAM_CHANGE_WARN    => undef,
        CACHE_MATRIX_AS_TREE => 1,
        VAL_INDEX_PRECISION  => '%.2g'
    );

    $self->set_params (%PARAMS, %args);  #  load the defaults, with the rest of the args as params
    $self->set_default_params;  #  and any user overrides
    
    $self->{BYELEMENT} = undef;  #  values indexed by elements
    $self->{BYVALUE}   = undef;  #  elements indexed by value

    $self->set_param (NAME => $args{name}) if defined $args{name};

    warn "[MATRIX] WARNING: Matrix name not specified\n"
        if ! defined $self->get_param('NAME');

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
    #my $bd = $self->get_param ('BASEDATA_REF');
    #$bd->rename_output (object => $self, new_name => $name);

    # and now change ourselves   
    $self->set_param (NAME => $name);
    
}


#  avoid needless cloning of the basedata, but don't create the parameter if it is not already there
sub clone {
    my $self = shift;
    my %args = @_;
    
    my $bd;
    my $exists = $self->exists_param('BASEDATA_REF');
    if ($exists) {
        $bd = $self->get_param('BASEDATA_REF');
        $self->set_param(BASEDATA_REF => undef);
    }

    my $clone_ref = eval {
        $self->SUPER::clone(%args);
    };
    if ($EVAL_ERROR) {
        if ($exists) {
            $self->set_param(BASEDATA_REF => $bd);  #  put it back if needed
        }
        croak $EVAL_ERROR;
    }

    if ($exists) {
        $self->set_param(BASEDATA_REF => $bd);
        $clone_ref->set_param(BASEDATA_REF => $bd);
    }

    return $clone_ref;
}

sub duplicate {
    my $self = shift;
    my %args = @_;
    
    my $bd;
    my $exists = $self->exists_param('BASEDATA_REF');
    if ($exists) {
        $bd = $self->get_param('BASEDATA_REF');
        $self->set_param(BASEDATA_REF => undef);
    }

    my $params = eval {
        $self->SUPER::clone(data => $self->{PARAMS});
    };
    
    my $clone_ref = blessed ($self)->new(%$params);
    
    my $elements = $self->get_elements_ref;
    
    my $c_elements_ref = $clone_ref->get_elements_ref;
    @{$c_elements_ref}{keys %$elements} = values %$elements;
    
    

    if ($EVAL_ERROR) {
        if ($exists) {
            $self->set_param(BASEDATA_REF => $bd);  #  put it back if needed
        }
        croak $EVAL_ERROR;
    }

    if ($exists) {
        $self->set_param(BASEDATA_REF => $bd);
        $clone_ref->set_param(BASEDATA_REF => $bd);
    }

    return $clone_ref;
}

sub delete_value_index {
    my $self = shift;

    undef $self->{BYVALUE};
    delete $self->{BYVALUE};

    return $self;
}

sub rebuild_value_index {
    my $self = shift;
    
    #$self->delete_value_index;
    $self->{BYVALUE} = {};
    
    my @elements = $self->get_elements_as_array;
    
    EL1:
    foreach my $el1 (@elements) {
        EL2:
        foreach my $el2 (@elements) {
            #  we want pairs in their stored order
            next EL2
              if 1 != $self->element_pair_exists(element1 => $el1, element2 => $el2);

            my $val = $self->get_value (element1 => $el1, element2 => $el2);

            my $index_val = $self->get_value_index_key (value => $val);

            $self->{BYVALUE}{$index_val}{$el1}{$el2}++;
        }
    }

    return $self;
}

sub get_value_index_key {
    my $self = shift;
    my %args = @_;
    
    my $val = $args{value};
    
    my $index_val = $val;  #  should make this a method
    if (!defined $index_val) {
        $index_val = q{undef};
    }
    elsif (my $prec = $self->get_param ('VAL_INDEX_PRECISION')) {
        $index_val = sprintf $prec, $val;
    }
    
    return $index_val;
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
        my $desc = $self->get_param ($key);
        if ((ref $desc) =~ /ARRAY/) {
            $desc = join q{, }, @$desc;
        }
        push @description,
            ["$key:", $desc];
    }

    push @description, [
        'Element count: ',
        $self->get_element_count,
    ];

    push @description, [
        'Max value: ',
        $self->get_max_value,
    ];
    push @description, [
        'Min value: ',
        $self->get_min_value,
    ];
    push @description, [
        'Symmetric: ',
        ($self->is_symmetric ? 'yes' : 'no'),
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
    
    if ($self->get_param ('AS_TREE')) {  #  don't recalculate 
        return $self->get_param ('AS_TREE');
    }
    
    my $tree = Biodiverse::Cluster->new;
    $tree->set_param (
        'NAME' => ($args{name}
        || $self->get_param ('NAME') . "_AS_TREE"
        )
    );
    
    eval {
        $tree->cluster (
            %args,
            #  need to work on a clone, as it is a destructive approach
            cluster_matrix => $self->clone, 
        );
    };
    croak $EVAL_ERROR if $EVAL_ERROR;
    
    $self->set_param (AS_TREE => $tree);
    
    return $tree;
}

#  wrapper for table conversions
#  should implement metadata
sub to_table {
    my $self = shift;
    my %args = @_;
    
    if ($args{type} eq 'sparse') {
        return $self->to_table_sparse (@_);
    }
    elsif ($args{type} eq 'gdm') {
        return $self->to_table_gdm (@_);
    }
    else {
        return $self->to_table_normal (@_);
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
    my @elements = sort $self->get_elements_as_array;
    
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
            my $exists = $self->element_pair_exists (
                element1 => $element1,
                element2 => $element2,
            );
            if (! $args{symmetric} && $exists == 1) {
                $data[$i][$j] = $self->get_value (
                    element1 => $element1,
                    element2 => $element2,
                );
            }
            else {
                $data[$i][$j] = $self->get_value (
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
    my @elements = sort $self->get_elements_as_array;

    my $lower_left  = $args{lower_left};
    my $upper_right = $args{upper_right};
    my $symmetric = $args{symmetric};
    
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
            next E1 if $lower_left  and $j > $i;
            next E2 if $upper_right and $j < $i;
            my $exists = $self->element_pair_exists (
                element1 => $element1,
                element2 => $element2,
            );
            
            #  if we are symmetric then list it regardless, otherwise only if we have this exact pair-order
            if ($exists == 1 || ($symmetric && $exists)) {
                my $value = $self->get_value (
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

sub to_table_gdm {
    my $self = shift;
    
    my %args = (
        symmetric => 1,
        @_,
    );
    
    my @data;
    my @elements = sort $self->get_elements_as_array;
    
    #  Get csv object from the basedata to crack the elements.
    #  Could cause trouble later on for matrices without basedata.
    my $bd = $self->get_param ('BASEDATA_REF');
    my $csv_object = $bd->get_csv_object (sep_char => $bd->get_param ('JOIN_CHAR'));
    
    push @data, [qw /x1 y1 x2 y2 Value/];  #  header line
    
    my $progress_bar = Biodiverse::Progress->new();
    my $to_do = scalar @elements;
    my $progress_pfx = "Converting matrix to table \n";
    
    my $i = 0;
    
    E1:
    foreach my $element1 (@elements) {
        $i++;
        my @element1 = $self->csv2list (string => $element1, csv_object => $csv_object);
        
        my $progress = $i / $to_do;
        $progress_bar->update (
            $progress_pfx . "(row $i / $to_do)",
            $progress,
        );

        my $j = 0;
        E2:
        foreach my $element2 (@elements) {
            $j++;
            next E1 if $args{lower_left}  and $j > $i;
            next E2 if $args{upper_right} and $j < $i;
            my $exists = $self->element_pair_exists (
                element1 => $element1,
                element2 => $element2,
            );

            #  if we are symmetric then list it regardless, otherwise only if we have this exact pair-order
            if (($args{symmetric} and $exists) or $exists == 1) {
                my $value = $self->get_value (
                    element1 => $element1,
                    element2 => $element2,
                );

                my @element2 = $self->csv2list (string => $element2, csv_object => $csv_object);
                my $list = [@element1[0,1], @element2[0,1], $value];
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
    my %metadata = $self->get_args (sub => 'export');
    
    my $format = $args{format};
    my $sub_to_use
        = $metadata{format_labels}{$format}
            || croak "Argument 'format => $format' not valid\n";
    
    eval {$self->$sub_to_use (%args)};
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

    my $table = $self->to_table (%args);
    eval {
        $self->write_table (
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
    
    my @formats = qw /normal sparse gdm/;
    

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

my $ludicrously_extreme_pos_val = 10 ** 20;
my $ludicrously_extreme_neg_val = -$ludicrously_extreme_pos_val;

sub get_min_value {  #  get the minimum similarity value
    my $self = shift;

    my $val_hash = $self->{BYVALUE};    
    my $min_key  = min keys %$val_hash;
    my $min      = $ludicrously_extreme_pos_val;
    
    my $element_hash = $val_hash->{$min_key};
    while (my ($el1, $hash_ref) = each %$element_hash) {
        foreach my $el2 (keys %$hash_ref) {
            my $val = $self->get_value (element1 => $el1, element2 => $el2);
            $min = min ($min, $val);
        }
    }

    return $min;
}

sub get_max_value {  #  get the minimum similarity value
    my $self = shift;

    my $val_hash = $self->{BYVALUE};    
    my $max_key  = max keys %$val_hash;
    my $max      = $ludicrously_extreme_neg_val;

    my $element_hash = $val_hash->{$max_key};
    while (my ($el1, $hash_ref) = each %$element_hash) {
        foreach my $el2 (keys %$hash_ref) {
            my $val = $self->get_value (element1 => $el1, element2 => $el2);
            $max = max ($max, $val);
        }
    }

    return $max;
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

    my $val = $args{value};
    if (! defined $val && ! $self->get_param('ALLOW_UNDEF')) {
        warn "[Matrix] add_element Warning: Value not defined and "
            . "ALLOW_UNDEF not set, not adding row $element1 col $element2.\n";
        return;
    }

    my $index_val = $self->get_value_index_key (value => $val);

    $self->{BYELEMENT}{$element1}{$element2} = $val;
    $self->{BYVALUE}{$index_val}{$element1}{$element2}++;
    $self->{ELEMENTS}{$element1}++;  #  cache the component elements to save searching through the other lists later
    $self->{ELEMENTS}{$element2}++;  #  also keeps a count of the elements
    
    return;
}

#  should be called delete_element_pair, but need to find where it's used first
sub delete_element {
    my $self = shift;
    my %args = @_;
    croak "element1 or element2 not defined\n"
        if   ! defined $args{element1}
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

    my $index_val = $self->get_value_index_key (value => $value);

    delete $self->{BYVALUE}{$index_val}{$element1}{$element2}; # if exists $self->{BYVALUE}{$value}{$element1}{$element2};
    if (scalar keys %{$self->{BYVALUE}{$index_val}{$element1}} == 0) {
        #undef $self->{BYVALUE}{$value}{$element1};
        delete $self->{BYVALUE}{$index_val}{$element1};
        if (scalar keys %{$self->{BYVALUE}{$index_val}} == 0) {
            #undef $self->{BYVALUE}{$value};
            defined (delete $self->{BYVALUE}{$index_val})
                || warn "ISSUES BYVALUE $index_val $value $element1 $element2\n";
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
    
    #return ($self->element_pair_exists(@_)) ? undef : 1;  #  for debug
    return 1;  # return success if we get this far
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



sub get_elements {
    my $self = shift;

    return if ! exists $self->{ELEMENTS};
    return if (scalar keys %{$self->{ELEMENTS}}) == 0;

    return wantarray ? %{$self->{ELEMENTS}} : $self->{ELEMENTS};
}

sub get_elements_ref {
    my $self = shift;

    return $self->{ELEMENTS} // do {$self->{ELEMENTS} = {}};
}

sub get_elements_as_array {
    my $self = shift;
    return wantarray
        ? keys %{$self->{ELEMENTS}}
        : [keys %{$self->{ELEMENTS}}];
}

sub get_element_count {
    my $self = shift;
    return 0 if ! exists $self->{ELEMENTS};
    return scalar keys %{$self->{ELEMENTS}};
}

sub get_element_pair_count {
    my $self = shift;

    #my $count = 0;
    #for my $value (values %{$self->{ELEMENTS}}) {
    #    $count += $value;
    #}
    my $count = sum values %{$self->{ELEMENTS}};
    $count /= 2;  #  correct for double counting
    #  IS THIS CORRECTION VALID?  We can have symmetric and non-symmetric matrices, so a:b and b:a
    #  It depends on how they are tracked, though.  

    return $count;
}

##  superceded by get_element_pairs_with_value - yes
#sub get_elements_with_value {  #  returns a hash of the elements with $value
#    my $self = shift;
#    my %args = @_;
#    
#    croak "Value not specified in call to get_elements_with_value\n"
#        if ! defined $args{value};
#    
#    my $value = $args{value};
#
#    return if ! exists $self->{BYVALUE}{$value};
#    return $self->{BYVALUE}{$value} if ! wantarray;
#    return %{$self->{BYVALUE}{$value}};
#}

sub get_element_pairs_with_value {
    my $self = shift;
    my %args = @_;

    my $val = $args{value};
    my $val_key = $val;
    if (my $prec = $self->get_param('VAL_INDEX_PRECISION')) {
        $val_key = sprintf $prec, $val;
    }

    my %results;

    my $val_hash = $self->{BYVALUE};
    my $element_hash = $val_hash->{$val_key};

    while (my ($el1, $hash_ref) = each %$element_hash) {
        foreach my $el2 (keys %$hash_ref) {
            my $value = $self->get_value (element1 => $el1, element2 => $el2);
            next if $val ne $value;  #  implicitly uses %.15f precision
            $results{$el1}{$el2} ++;
        }
    }

    return wantarray ? %results : \%results;    
}

sub get_element_values {  #  get all values associated with one element
    my $self = shift;
    my %args = @_;
    
    croak "element not specified (matrix)\n"  if ! defined $args{element};
    croak "matrix element does not exist\n" if ! $self->element_is_in_matrix (element => $args{element});

    my @elements = $self->get_elements_as_array;
    
    my %values;
    foreach my $el (@elements) {
        if ($self->element_pair_exists (element1 => $el, element2 => $args{element})) {
            $values{$el} = $self->get_value (element1 => $el, element2 => $args{element});
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
    croak "element does not exist\n" if ! $self->element_is_in_matrix (element => $args{element});
    
    my @elements = $self->get_elements_as_array;
    foreach my $el (@elements) {
        if ($self->element_pair_exists (
                element1 => $el,
                element2 => $args{element})
            ) {

            $self->delete_element (
                element1 => $el,
                element2 => $args{element},
            );
        }
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
