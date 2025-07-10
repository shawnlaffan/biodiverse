package Biodiverse::Common;

#  a set of common functions for the Biodiverse library

use 5.036;
use strict;
use warnings;

use experimental qw/refaliasing for_list/;

use Carp;
use English ( -no_match_vars );

use constant ON_WINDOWS => ($OSNAME eq 'MSWin32');
use if ON_WINDOWS, 'Win32::LongPath';

#use Data::Dumper  qw /Dumper/;
use YAML::Syck ();
#use YAML::XS;
use Text::CSV_XS 1.52 ();
use Scalar::Util qw /blessed isweak reftype weaken/;
use List::MoreUtils qw /none/;
use List::Util qw /first/;
use Storable qw /nstore retrieve/;
use File::Basename qw( fileparse );
use Path::Tiny qw /path/;
use POSIX ();
use HTML::QuickTable ();
#use XBase;
#use MRO::Compat;
use Class::Inspector ();
use Ref::Util qw { is_arrayref is_hashref is_ref };
# use File::BOM ();

use Sereal::Encoder qw //;
use Sereal::Decoder qw //;

#  Need to avoid an OIO destroyed twice warning due
#  to HTTP::Tiny, which is used in Biodiverse::GUI::Help
#  but wrap it in an eval to avoid problems on threaded builds
BEGIN {
    eval 'use threads';
}

use Math::Random::MT::Auto ();

#use Regexp::Common qw /number/;

use Biodiverse::Progress;
use Biodiverse::Exception;

use Clone ();

use parent qw(
    Biodiverse::Common::Caching
    Biodiverse::Common::Params
    Biodiverse::Common::Metadata
    Biodiverse::Common::IO
    Biodiverse::Common::CSV
);

our $VERSION = '4.99_006';

my $EMPTY_STRING = q{};

sub clone {
    my $self = shift;
    my %args = @_;  #  only works with argument 'data' for now

    my ($cloneref, $e);

    if ((scalar keys %args) == 0) {
        #$cloneref = dclone($self);
        #$cloneref = Clone::clone ($self);
        #  Use Sereal because we are hitting CLone size limits
        #  https://rt.cpan.org/Public/Bug/Display.html?id=97525
        #  could use Sereal::Dclone for brevity
        my $encoder = Sereal::Encoder->new({
            undef_unknown => 1,  #  strip any code refs
        });
        my $decoder = Sereal::Decoder->new();
        eval {
            $decoder->decode ($encoder->encode($self), $cloneref);
        };
        $e = $EVAL_ERROR;
    }
    else {
        #$cloneref = dclone ($args{data});
        # Should also use Sereal here
        $cloneref = Clone::clone ($args{data});
    }

    croak $e if $e;

    return $cloneref;
}

sub rename_object {
    my $self = shift;
    my %args = @_;

    my $new_name = $args{name} // $args{new_name};
    my $old_name = $self->get_param ('NAME');

    $self->set_param (NAME => $new_name);

    my $type = blessed $self;

    print "Renamed $type '$old_name' to '$new_name'\n";

    return;
}

sub get_last_update_time {
    my $self = shift;
    return $self->get_param ('LAST_UPDATE_TIME');
}

sub set_last_update_time {
    my $self = shift;
    my $time = shift || time;
    $self->set_param (LAST_UPDATE_TIME => $time);

    return;
}

#  Orig should never have used a hash.  Oh well.
sub set_basedata_ref_aa {
    my ($self, $ref) = @_;
    $self->set_basedata_ref(BASEDATA_REF => $ref);
}

sub set_basedata_ref {
    my $self = shift;
    my %args = @_;

    $self->set_param (BASEDATA_REF => $args{BASEDATA_REF});
    $self->weaken_basedata_ref if defined $args{BASEDATA_REF};

    return;
}

sub get_basedata_ref {
    my $self = shift;

    my $bd = $self->get_param ('BASEDATA_REF');

    return $bd;
}


sub weaken_basedata_ref {
    my $self = shift;

    my $success;

    #  avoid memory leak probs with circular refs
    if ($self->exists_param ('BASEDATA_REF')) {
        $success = $self->weaken_param ('BASEDATA_REF');

        warn "[BaseStruct] Unable to weaken basedata ref\n"
            if ! $success;
    }

    return $success;
}


sub get_name {
    my $self = shift;
    return $self->get_param ('NAME');
}

#  allows for back-compat
sub get_cell_origins {
    my $self = shift;

    my $origins = $self->get_param ('CELL_ORIGINS');
    if (!defined $origins) {
        my $cell_sizes = $self->get_param ('CELL_SIZES');
        $origins = [(0) x scalar @$cell_sizes];
        $self->set_param (CELL_ORIGINS => $origins);
    }

    return wantarray ? @$origins : [@$origins];
}

sub get_cell_sizes {
    my $self = shift;

    my $sizes = $self->get_param ('CELL_SIZES');

    return if !$sizes;
    return wantarray ? @$sizes : [@$sizes];
}


sub get_analysis_args_from_object {
    my $self = shift;
    my %args = @_;

    my $object = $args{object};

    my $get_copy = $args{get_copy} // 1;

    my $analysis_args;
    my $p_key;
    ARGS_PARAM:
    for my $key (qw/ANALYSIS_ARGS SP_CALC_ARGS/) {
        $analysis_args = $object->get_param ($key);
        $p_key = $key;
        last ARGS_PARAM if defined $analysis_args;
    }

    my $return_hash = $get_copy ? {%$analysis_args} : $analysis_args;

    my @results = (
        $p_key,
        $return_hash,
    );

    return wantarray ? @results : \@results;
}


#  Get the spatial conditions for this object if set
#  Allow for back-compat.
sub get_spatial_conditions {
    my $self = shift;

    my $conditions =  $self->get_param ('SPATIAL_CONDITIONS')
        // $self->get_param ('SPATIAL_PARAMS');

    return $conditions;
}

#  Get the def query for this object if set
sub get_def_query {
    my $self = shift;

    my $def_q =  $self->get_param ('DEFINITION_QUERY');

    return $def_q;
}


sub delete_spatial_index {
    my $self = shift;

    my $name = $self->get_param ('NAME');

    if ($self->get_param ('SPATIAL_INDEX')) {
        my $class = blessed $self;
        print "[$class] Deleting spatial index from $name\n";
        $self->delete_param('SPATIAL_INDEX');
        return 1;
    }

    return;
}

#  Text::CSV_XS seems to have cache problems that borks Clone::clone and YAML::Syck::to_yaml
sub clear_spatial_index_csv_object {
    my $self = shift;

    my $cleared;

    if (my $sp_index = $self->get_param ('SPATIAL_INDEX')) {
        $sp_index->delete_param('CSV_OBJECT');
        $sp_index->delete_cached_values (keys => ['CSV_OBJECT']);
        $cleared = 1;
    }

    return $cleared;
}



sub clear_spatial_condition_caches {
    my $self = shift;
    my %args = @_;

    eval {
        foreach my $sp (@{$self->get_spatial_conditions}) {
            $sp->delete_cached_values (keys => $args{keys});
        }
    };
    eval {
        my $def_query = $self->get_def_query;
        if ($def_query) {
            $def_query->delete_cached_values (keys => $args{keys});
        }
    };

    return;
}

#  print text to the log.
#  need to add a checker to not dump yaml if not being run by gui
#  CLUNK CLUNK CLUNK  - need to use the log4perl system
sub update_log {
    my $self = shift;
    my %args = @_;

    if ($self->get_param ('RUN_FROM_GUI')) {

        $args{type} = 'update_log';
        $self->dump_to_yaml (data => \%args);
    }
    else {
        print $args{text};
    }

    return;
}


sub get_tooltip_sparse_normal {
    my $self = shift;

    my $tool_tip =<<"END_MX_TOOLTIP"

Explanation:

A rectangular matrix is a row by column matrix.
Blank entries have an undefined value (no value).

Element,Axis_0,Axis_1,Label1,Label2,Label3
1.5:1.5,1.5,1.5,5,,2
1.5:2.5,1.5,2.5,,23,2
2.5:2.5,2.5,2.5,3,4,10

A non-symmetric one-value-per-line format is a list, and is analogous to a sparse matrix.
Undefined entries are not given.

Element,Axis_0,Axis_1,Key,Value
1.5:1.5,1.5,1.5,Label1,5
1.5:1.5,1.5,1.5,Label3,2
1.5:2.5,1.5,2.5,Label2,23
1.5:2.5,1.5,2.5,Label3,2
2.5:2.5,2.5,2.5,Label1,3
2.5:2.5,2.5,2.5,Label2,4
2.5:2.5,2.5,2.5,Label3,10

A symmetric one-value-per-line format has rows for the undefined values.

Element,Axis_0,Axis_1,Key,Value
1.5:1.5,1.5,1.5,Label1,5
1.5:1.5,1.5,1.5,Label2,
1.5:1.5,1.5,1.5,Label3,2


A non-symmetric normal matrix is useful for array lists, but can also be used with hash lists.
It has one row per element, with all the entries for that element listed sequentially on that line.

Element,Axis_0,Axis_1,Value
1.5:1.5,1.5,1.5,Label1,5,Label3,2
1.5:2.5,1.5,2.5,Label2,23,Label3,2

END_MX_TOOLTIP
    ;

    return $tool_tip;
}


#  handler for the available set of structures.
#  IS THIS CALLED ANYMORE?
sub write_table {
    my $self = shift;
    my %args = @_;
    defined $args{file} || croak "file argument not specified\n";
    my $data = $args{data} || croak "data argument not specified\n";
    is_arrayref($data) || croak "data arg must be an array ref\n";

    $args{file} = path($args{file})->absolute;

    #  now do stuff depending on what format was chosen, based on the suffix
    my (undef, $suffix) = lc ($args{file}) =~ /(.*?)\.(.*?)$/;
    if (! defined $suffix) {
        $suffix = 'csv';  #  does not affect the actual file name, as it is not passed onwards
    }

    if ($suffix =~ /csv|txt/i) {
        $self->write_table_csv (%args);
    }
    #elsif ($suffix =~ /dbf/i) {
    #    $self->write_table_dbf (%args);
    #}
    elsif ($suffix =~ /htm/i) {
        $self->write_table_html (%args);
    }
    elsif ($suffix =~ /yml/i) {
        $self->write_table_yaml (%args);
    }
    elsif ($suffix =~ /json/i) {
        $self->write_table_json (%args);
    }
    #elsif ($suffix =~ /shp/) {
    #    $self->write_table_shapefile (%args);
    #}
    elsif ($suffix =~ /mrt/i) {
        #  some humourless souls might regard this as unnecessary...
        warn "I pity the fool who thinks Mister T is a file format.\n";
        warn "[COMMON] Not a recognised suffix $suffix, using csv/txt format\n";
        $self->write_table_csv (%args, data => $data);
    }
    else {
        print "[COMMON] Not a recognised suffix $suffix, using csv/txt format\n";
        $self->write_table_csv (%args, data => $data);
    }
}

sub get_csv_object_for_export {
    my $self = shift;
    my %args = @_;

    my $sep_char = $args{sep_char}
        || $self->get_param ('OUTPUT_SEP_CHAR')
        || q{,};

    my $quote_char = $args{quote_char}
        || $self->get_param ('OUTPUT_QUOTE_CHAR')
        || q{"};

    if ($quote_char =~ /space/) {
        $quote_char = "\ ";
    }
    elsif ($quote_char =~ /tab/) {
        $quote_char = "\t";
    }

    if ($sep_char =~ /space/) {
        $sep_char = "\ ";
    }
    elsif ($sep_char =~ /tab/) {
        $sep_char = "\t";
    }

    my $csv_obj = $self->get_csv_object (
        %args,
        sep_char   => $sep_char,
        quote_char => $quote_char,
    );

    return $csv_obj;
}

sub write_table_csv {
    my $self = shift;
    my %args = @_;
    my $data = $args{data} || croak "data arg not specified\n";
    is_arrayref($data) || croak "data arg must be an array ref\n";
    my $file = $args{file} || croak "file arg not specified\n";

    my $csv_obj = $self->get_csv_object_for_export (%args);

    my $fh = $self->get_file_handle (file_name => $file, mode => '>');

    eval {
        foreach my $line_ref (@$data) {
            my $string = $self->list2csv (  #  should pass csv object
                list       => $line_ref,
                csv_object => $csv_obj,
            );
            say {$fh} $string;
        }
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    if ($fh->close) {
        say "[COMMON] Write to file $file successful";
    }
    else {
        croak "[COMMON] Unable to close $file\n";
    };

    return;
}

sub write_table_yaml {  #  dump the table to a YAML file.
    my $self = shift;
    my %args = @_;

    my $data = $args{data} // croak "data arg not specified\n";
    is_arrayref($data) // croak "data arg must be an array ref\n";
    my $file = $args{file} // croak "file arg not specified\n";

    eval {
        $self->dump_to_yaml (
            %args,
            filename => $file,
        )
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return;
}

sub write_table_json {  #  dump the table to a JSON file.
    my $self = shift;
    my %args = @_;

    my $data = $args{data} // croak "data arg not specified\n";
    is_arrayref($data) // croak "data arg must be an array ref\n";
    my $file = $args{file} // croak "file arg not specified\n";

    eval {
        $self->dump_to_json (
            %args,
            filename => $file,
        )
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return;
}

sub write_table_html {
    my $self = shift;
    my %args = @_;
    my $data = $args{data} || croak "data arg not specified\n";
    is_arrayref($data) || croak "data arg must be an array ref\n";
    my $file = $args{file} || croak "file arg not specified\n";

    my $qt = HTML::QuickTable->new();

    my $table = $qt->render($args{data});

    open my $fh, '>', $file;

    eval {
        print {$fh} $table;
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    if ($fh->close) {
        print "[COMMON] Write to file $file successful\n"
    }
    else {
        croak "[COMMON] Write to file $file failed, unable to close file\n"
    }

    return;
}


#  csv can cause seg faults when reloaded
#  have not yet sorted out why
sub delete_element_name_csv_object {
    my ($self) = @_;

    state $cache_name = '_ELEMENT_NAME_CSV_OBJECT';
    $self->delete_cached_value ($cache_name);

    return;
}

sub get_element_name_csv_object {
    my ($self) = @_;

    state $cache_name = '_ELEMENT_NAME_CSV_OBJECT';
    my $csv = $self->get_cached_value ($cache_name);
    if (!$csv) {
        $csv = $self->get_csv_object (
            sep_char   => ($self->get_param('JOIN_CHAR') // ':'),
            quote_char => ($self->get_param('QUOTES') // q{'}),
        );
        $self->set_cached_value ($cache_name => $csv);
    }

    return $csv;
}


sub dequote_element {
    my $self = shift;
    my %args = @_;

    my $quotes = $args{quote_char};
    my $el     = $args{element};

    croak "quote_char argument is undefined\n"
        if !defined $quotes;
    croak "element argument is undefined\n"
        if !defined $el;

    if ($el =~ /^$quotes[^$quotes\s]+$quotes$/) {
        $el = substr ($el, 1);
        chop $el;
    }

    return $el;
}

sub array_to_hash_keys {
    my $self = shift;
    my %args = @_;
    exists $args{list} || croak "Argument 'list' not specified or undef\n";
    my $list_ref = $args{list};

    if (! defined $list_ref) {
        return wantarray ? () : {};  #  return empty if $list_ref not defined
    }

    #  complain if it is a scalar
    croak "Argument 'list' is not an array ref - it is a scalar\n" if ! ref ($list_ref);

    my $value = $args{value};

    my %hash;
    if (is_arrayref($list_ref) && scalar @$list_ref) {  #  ref to array of non-zero length
        @hash{@$list_ref} = ($value) x scalar @$list_ref;
    }
    elsif (is_hashref($list_ref)) {
        %hash = %$list_ref;
    }

    return wantarray ? %hash : \%hash;
}

#  sometimes we want to keep the values
sub array_to_hash_values {
    my $self = shift;
    my %args = @_;

    exists $args{list} || croak "Argument 'list' not specified or undef\n";
    my $list_ref = $args{list};

    if (! defined $list_ref) {
        return wantarray ? () : {};  #  return empty if $list_ref not defined
    }

    #  complain if it is a scalar
    croak "Argument 'list' is not an array ref - it is a scalar\n" if ! ref ($list_ref);
    $list_ref = [values %$list_ref] if is_hashref($list_ref);

    my $prefix = $args{prefix} // "data";

    my %hash;
    my $start = "0" x ($args{num_digits} || length $#$list_ref);  #  make sure it has as many chars as the end val
    my $end = defined $args{num_digits}
        ? sprintf ("%0$args{num_digits}s", $#$list_ref) #  pad with zeroes
        : $#$list_ref;
    my @keys;
    for my $suffix ("$start" .. "$end") {  #  a clunky way to build it, but the .. operator won't play with underscores
        push @keys, "$prefix\_$suffix";
    }
    if (is_arrayref($list_ref) && scalar @$list_ref) {  #  ref to array of non-zero length
        @hash{@keys} = $args{sort_array_lists} ? sort numerically @$list_ref : @$list_ref;  #  sort if needed
    }

    return wantarray ? %hash : \%hash;
}

#  get the intersection of two lists
sub get_list_intersection {
    my $self = shift;
    my %args = @_;

    my @list1 = @{$args{list1}};
    my @list2 = @{$args{list2}};

    my %exists;
    #@exists{@list1} = (1) x scalar @list1;
    #my @list = grep { $exists{$_} } @list2;
    @exists{@list1} = undef;
    my @list = grep { exists $exists{$_} } @list2;

    return wantarray ? @list : \@list;
}

#  move an item to the front of the list, splice it out of its first slot if found
#  should use List::MoreUtils::first_index
#  additional arg add_if_not_found allows it to be added anyway
#  works on a ref, so take care
sub move_to_front_of_list {
    my $self = shift;
    my %args = @_;

    my $list = $args{list} || croak "argument 'list' not defined\n";
    my $item = $args{item};

    if (not defined $item) {
        croak "argument 'item' not defined\n";
    }

    my $i = 0;
    my $found = 0;
    foreach my $iter (@$list) {
        if ($iter eq $item) {
            $found ++;
            last;
        }
        $i ++;
    }
    if ($args{add_if_not_found} || $found) {
        splice @$list, $i, 1;
        unshift @$list, $item;
    }

    return wantarray ? @$list : $list;
}


sub get_book_struct_from_spreadsheet_file {
    my ($self, %args) = @_;

    use Spreadsheet::Read qw( ReadData );

    my $book;
    my $file = $args{file_name}
        // croak 'file_name argument not passed';

    #  stringify any Path::Class etc objects
    $file = "$file";

    #  Could set second condition as a fallback if first parse fails
    #  but it seems to work pretty well in practice.
    if ($file =~ /\.xlsx$/ and $self->file_exists_aa($file)) {
        #  handle unicode on windows
        my $f = $self->get_shortpath_filename (file_name => $file);
        $book = $self->get_book_struct_from_xlsx_file (filename => $f);
    }
    elsif ($file =~ /\.(xlsx?|ods)$/) {
        #  we can use file handles for excel and ods
        my $extension = $1;
        my $fh = $self->get_file_handle (
            file_name => $file,
        );
        $book = ReadData($fh, parser => $extension);
    }
    else {
        #  sxc files and similar
        $book = ReadData($file);
        if (!$book && $self->file_exists_aa($file)) {
            croak "[BASEDATA] Failed to read $file with SpreadSheet.\n"
                . "If the file name contains non-ascii characters "
                . "then try renaming it using ascii only.\n";
        }
    }

    # assuming undef on fail
    croak "[BASEDATA] Failed to read $file as a SpreadSheet\n"
        if !defined $book;

    return $book;
}

sub get_book_struct_from_xlsx_file {
    my ($self, %args) = @_;
    my $file = $args{filename} // croak "filename arg not passed";

    require Excel::ValueReader::XLSX;
    my $reader = Excel::ValueReader::XLSX->new($file);
    my @sheet_names = $reader->sheet_names;
    my %sheet_ids;
    @sheet_ids{@sheet_names} = (1 .. @sheet_names);
    my $workbook = [
        {
            error  => undef,
            parser => "Excel::ValueReader::XLSX",
            sheet  => \%sheet_ids,
            sheets => scalar @sheet_names,
            type   => 'xlsx',
        },
    ];
    my $i;
    foreach my $sheet_name ($reader->sheet_names) {
        $i++;
        my $grid = $reader->values($sheet_name);
        my @t = ([]); #  first entry is empty
        foreach my $r (0 .. $#$grid) {
            my $row = $grid->[$r];
            foreach my $c (0 .. $#$row) {
                #  add 1 for array base 1
                $t[$c + 1][$r + 1] = $grid->[$r][$c];
            }
        }
        my $maxrow = @$grid;

        my $sheet = {
            label  => $sheet_name,
            cell   => \@t,
            maxrow => $maxrow,
            maxcol => $#t,
            minrow => 1,
            mincol => 1,
            indx   => 1,
            merged => [],
        };
        push @$workbook, $sheet;
    }
    return $workbook;
}

#  temp end block
#END {
#    warn "get_args called in list context $indices_wantarray times\n";
#}

sub get_poss_elements {  #  generate a list of values between two extrema given a resolution
    my $self = shift;
    my %args = @_;

    my $so_far      = [];  #  reference to an array of values
    #my $depth       = $args{depth} || 0;
    my $minima      = $args{minima};  #  should really be extrema1 and extrema2 not min and max
    my $maxima      = $args{maxima};
    my $resolutions = $args{resolutions};
    my $precision   = $args{precision} || [(10 ** 10) x scalar @$minima];
    my $sep_char    = $args{sep_char} || $self->get_param('JOIN_CHAR');

    #  need to add rule to cope with zero resolution

    foreach my $depth (0 .. $#$minima) {
        #  go through each element of @$so_far and append one of the values from this level
        my @this_depth;

        my $min = min ($minima->[$depth], $maxima->[$depth]);
        my $max = max ($minima->[$depth], $maxima->[$depth]);
        my $res = $resolutions->[$depth];

        #  need to fix the precision for some floating point comparisons
        for (my $value = $min;
            ($self->round_to_precision_aa ($value, $precision->[$depth])) <= $max;
            $value += $res) {

            my $val = $self->round_to_precision_aa ($value, $precision->[$depth]);
            if ($depth > 0) {
                foreach my $element (@$so_far) {
                    #print "$element . $sep_char . $value\n";
                    push @this_depth, $element . $sep_char . $val;
                }
            }
            else {
                push (@this_depth, $val);
            }
            last if $min == $max;  #  avoid infinite loop
        }

        $so_far = \@this_depth;
    }

    return $so_far;
}

#  generate a list of values around a single point at a specified resolution
#  calculates the min and max and call get_poss_index_values
sub get_surrounding_elements {
    my $self = shift;
    my %args = @_;
    my $coord_ref = $args{coord};
    my $resolutions = $args{resolutions};
    my $sep_char = $args{sep_char} || $self->get_param('JOIN_CHAR');
    my $distance = $args{distance} || 1; #  number of cells distance to check

    my (@minima, @maxima);
    #  precision snap them to make comparisons easier
    my $precision = $args{precision} || [(10 ** 10) x scalar @$coord_ref];

    foreach my $i (0..$#{$coord_ref}) {
        $minima[$i] = $precision->[$i]
            ? $self->round_to_precision_aa (
            $coord_ref->[$i] - ($resolutions->[$i] * $distance),
            $precision->[$i],
        )
            : $coord_ref->[$i] - ($resolutions->[$i] * $distance);
        $maxima[$i] = $precision->[$i]
            ? $self->round_to_precision_aa (
            $coord_ref->[$i] + ($resolutions->[$i] * $distance),
            $precision->[$i],
        )
            : $coord_ref->[$i] + ($resolutions->[$i] * $distance);
    }

    return $self->get_poss_elements (
        %args,
        minima      => \@minima,
        maxima      => \@maxima,
        resolutions => $resolutions,
        sep_char    => $sep_char,
    );
}

sub get_list_as_flat_hash {
    my $self = shift;
    my %args = @_;

    my $list = $args{list} || croak "[Common] Argument 'list' not specified\n";
    delete $args{list};  #  saves passing it onwards

    #  check the first one
    my $list_reftype = reftype ($list) // 'undef';
    croak "list arg must be a hash or array ref, not $list_reftype\n"
        if not (is_arrayref($list) or is_hashref($list));

    my @refs = ($list);  #  start with this
    my %flat_hash;

    foreach my $ref (@refs) {
        if (is_arrayref($ref)) {
            @flat_hash{@$ref} = (1) x scalar @$ref;
        }
        elsif (is_hashref($ref)) {
            foreach my $key (keys %$ref) {
                if (!is_ref($ref->{$key})) {  #  not a ref, so must be a single level hash list
                    $flat_hash{$key} = $ref->{$key};
                }
                else {
                    #  push this ref onto the stack
                    push @refs, $ref->{$key};
                    #  keep this branch key if needed
                    if ($args{keep_branches}) {
                        $flat_hash{$key} = $args{default_value};
                    }
                }
            }
        }
    }

    return wantarray ? %flat_hash : \%flat_hash;
}

#  invert a two level hash by keys
sub get_hash_inverted {
    my $self = shift;
    my %args = @_;

    my $list = $args{list} || croak "list not specified\n";

    my %inv_list;

    foreach my $key1 (keys %$list) {
        foreach my $key2 (keys %{$list->{$key1}}) {
            $inv_list{$key2}{$key1} = $list->{$key1}{$key2};  #  may as well keep the value - it may have meaning
        }
    }
    return wantarray ? %inv_list : \%inv_list;
}

#  a twisted mechanism to get the shared keys between a set of hashes
sub get_shared_hash_keys {
    my $self = shift;
    my %args = @_;

    my $lists = $args{lists};
    croak "lists arg is not an array ref\n" if !is_arrayref($lists);

    my %shared = %{shift @$lists};  #  copy the first one
    foreach my $list (@$lists) {
        my %tmp2 = %shared;  #  get a copy
        delete @tmp2{keys %$list};  #  get the set not in common
        delete @shared{keys %tmp2};  #  delete those not in common
    }

    return wantarray ? %shared : \%shared;
}


#  get a list of available subs (analyses) with a specified prefix
#  not sure why we return a hash - history is long ago...
sub get_subs_with_prefix {
    my $self = shift;
    my %args = @_;

    my $prefix = $args{prefix};
    croak "prefix not defined\n" if not defined $prefix;

    my $methods = Class::Inspector->methods ($args{class} or blessed ($self));

    my %subs = map {$_ => 1} grep {$_ =~ /^$prefix/} @$methods;

    return wantarray ? %subs : \%subs;
}

sub get_subs_with_prefix_as_array {
    my $self = shift;
    my $subs = $self->get_subs_with_prefix(@_);
    my @subs = keys %$subs;
    return wantarray ? @subs : \@subs;
}

#  initialise the PRNG with an array of values, start from where we left off,
#     or use default if not specified
sub initialise_rand {
    my $self = shift;
    my %args = @_;
    my $seed  = $args{seed};
    my $state = $self->get_param ('RAND_LAST_STATE')
        || $args{state};

    say "[COMMON] Ignoring PRNG seed argument ($seed) because the PRNG state is defined"
        if defined $seed and defined $state;

    #  don't already have one, generate a new object using seed and/or state params.
    #  the system will initialise in the order of state and seed, followed by its own methods
    my $rand = eval {
        Math::Random::MT::Auto->new (
            seed  => $seed,
            state => $state,  #  will use this if it is defined
        );
    };
    my $e = $EVAL_ERROR;
    if (OIO->caught() && $e =~ 'Invalid state vector') {
        Biodiverse::PRNG::InvalidStateVector->throw (Biodiverse::PRNG::InvalidStateVector->description);
    }
    croak $e if $e;

    if (! defined $self->get_param ('RAND_INIT_STATE')) {
        $self->store_rand_state_init (rand_object => $rand);
    }

    return $rand;
}

sub store_rand_state {  #  we cannot store the object itself, as it does not serialise properly using YAML
    my $self = shift;
    my %args = @_;

    croak "rand_object not specified correctly\n" if ! blessed $args{rand_object};

    my $rand = $args{rand_object};
    my @state = $rand->get_state;  #  make a copy - might reduce mem issues?
    croak "PRNG state not defined\n" if ! scalar @state;

    my $state = \@state;
    $self->set_param (RAND_LAST_STATE => $state);

    if (defined wantarray) {
        return wantarray ? @state : $state;
    }
}

#  Store the initial rand state (assumes it is called at the right time...)
sub store_rand_state_init {
    my $self = shift;
    my %args = @_;

    croak "rand_object not specified correctly\n" if ! blessed $args{rand_object};

    my $rand = $args{rand_object};
    my @state = $rand->get_state;

    my $state = \@state;

    $self->set_param (RAND_INIT_STATE => $state);

    if (defined wantarray) {
        return wantarray ? @state : $state;
    }
}

sub describe {
    my $self = shift;
    return if !$self->can('_describe');

    return $self->_describe;
}

#  find circular refs in the sub from which this is called,
#  or some level higher
#sub find_circular_refs {
#    my $self = shift;
#    my %args = @_;
#    my $level = $args{level} || 1;
#    my $label = $EMPTY_STRING;
#    $label = $args{label} if defined $args{label};
#    
#    use PadWalker qw /peek_my/;
#    use Data::Structure::Util qw /has_circular_ref get_refs/; #  hunting for circular refs
#    
#    my @caller = caller ($level);
#    my $caller = $caller[3];
#    
#    my $vars = peek_my ($level);
#    my $circular = has_circular_ref ( $vars );
#    if ( $circular ) {
#        warn "$label Circular $caller\n";
#    }
#    #else {  #  run silent unless there is a circular ref
#    #    print "$label NO CIRCULAR REFS FOUND IN $caller\n";
#    #}
#    
#}

sub find_circular_refs {
    my $self = shift;

    if (0) {  #  set to 0 to "turn it off"
        eval q'
                use Devel::Cycle;

                foreach my $ref (@_) {
                    print "testing circularity of $ref\n";
                    find_weakened_cycle($ref);
                }
                '
    }
}

#  locales with commas as the radix char can cause grief
#  and silently at that
#sub test_locale_numeric {
#    my $self = shift;
#    
#    use warnings FATAL => qw ( numeric );
#    
#    my $x = 10.5;
#    my $y = 10.1;
#    my $x1 = sprintf ('%.10f', $x);
#    my $y1 = sprintf ('%.10f', $y);
#    $y1 = '10,1';
#    my $correct_result = $x + $y;
#    my $result = $x1 + $y1;
#    
#    use POSIX qw /locale_h/;
#    my $locale = setlocale ('LC_NUMERIC');
#    croak "$result != $correct_result, this could be a locale issue. "
#            . "Current locale is $locale.\n"
#        if $result != $correct_result;
#    
#    return 1;
#}


#  need to handle locale issues in string conversions using sprintf
sub set_precision {
    my $self = shift;
    my %args = @_;

    my $num = sprintf (($args{precision} // '%.10f'), $args{value});
    #$num =~ s{,}{.};  #  replace any comma with a decimal due to locale woes - #GH774

    return $num;
}

#  array args variant for more speed when needed
#  $_[0] is $self, and not used here
sub set_precision_aa {
    my $num = sprintf (($_[2] // '%.10f'), $_[1]);
    #$num =~ s{,}{\.};  #  replace any comma with a dot due to locale woes - #GH774

    #  explicit return takes time, and this is a heavy usage sub
    $num;
}

use constant DEFAULT_PRECISION => 1e10;
sub round_to_precision_aa {
    $_[2]
        ? POSIX::round ($_[1] * $_[2]) / $_[2]
        : POSIX::round ($_[1] * DEFAULT_PRECISION) / DEFAULT_PRECISION;
}


#  use Devel::Symdump to hunt within a whole package
#sub find_circular_refs_in_package {
#    my $self = shift;
#    my %args = @_;
#    my $package = $args{package} || caller;
#    my $label = $EMPTY_STRING;
#    $label = $args{label} if defined $args{label};
#    
#    use Data::Structure::Util qw /has_circular_ref get_refs/; #  hunting for circular refs
#    use Devel::Symdump;
#    
#   
#    my %refs = (
#                array => {sigil => "@",
#                           data => [Devel::Symdump->arrays ($package)],
#                          },
#                hash  => {sigil => "%",
#                           data => [Devel::Symdump->hashes ($package)],
#                          },
#                #scalars => {sigil => '$',
#                #           data => [Devel::Symdump->hashes],
#                #          },
#                );
#
#    
#    foreach my $type (keys %refs) {
#        my $sigil = $refs{$type}{sigil};
#        my $data = $refs{$type}{data};
#        
#        foreach my $name (@$data) {
#            my $var_text = "\\" . $sigil . $name;
#            my $vars = eval {$var_text};
#            my $circular = has_circular_ref ( $vars );
#            if ( $circular ) {
#                warn "$label Circular $package\n";
#            }
#        }
#    }
#    
#}

#  hunt for circular refs using PadWalker
#sub find_circular_refs_above {
#    my $self = shift;
#    my %args = @_;
#    
#    #  how far up to go?
#    my $top_level = $args{top_level} || 1;
#    
#    use Data::Structure::Util qw /has_circular_ref get_refs/; #  hunting for circular refs
#    use PadWalker qw /peek_my/;
#
#
#    foreach my $level (0 .. $top_level) {
#        my $h = peek_my ($level);
#        foreach my $key (keys %$h) {
#            my $ref = ref ($h->{$key});
#            next if ref ($h->{$key}) =~ /GUI|Glib|Gtk/;
#            my $circular = eval {
#                has_circular_ref ( $h->{$key} )
#            };
#            if ($EVAL_ERROR) {
#                print $EMPTY_STRING;
#            }
#            if ( $circular ) {
#                warn "Circular $key, level $level\n";
#            }
#        }
#    }
#
#    return;
#}

sub rgb_12bit_to_8bit_aa {
    my ($self, $colour) = @_;

    return $colour if !defined $colour || $colour !~ /^#[a-fA-F\d]{12}$/;

    my $proper_form_string = "#";
    my @wanted_indices = (1, 2, 5, 6, 9, 10);
    foreach my $index (@wanted_indices) {
        $proper_form_string .= substr($colour, $index, 1);
    }

    return $proper_form_string;
}

sub rgb_12bit_to_8bit  {
    my ($self, %args) = @_;
    my $colour = $args{colour};

    #  only worry about #RRRRGGGGBBBB
    return $colour if !defined $colour || $colour !~ /^#[a-fA-F\d]{12}$/;

    return $self->rgb_12bit_to_8bit_aa ($colour);
}

#  make this a state var internal to the sub
#  when perl 5.28 is our min version
my @lgamma_arr = (0,0);
sub _get_lgamma_arr {
    my ($self, %args) = @_;
    my $n = $args{max_n};

    if (@lgamma_arr <= $n) {
        foreach my $i (@lgamma_arr .. $n) {
            $lgamma_arr[$i] = $lgamma_arr[$i-1] + log $i;
        }
    }

    return wantarray ? @lgamma_arr : \@lgamma_arr;
}


sub numerically {$a <=> $b};

sub min {$_[0] < $_[1] ? $_[0] : $_[1]};
sub max {$_[0] > $_[1] ? $_[0] : $_[1]};

1;  #  return true

__END__

=head1 NAME

Biodiverse::Common - a set of common functions for the Biodiverse library.  MASSIVELY OUT OF DATE

=head1 SYNOPSIS

  use Biodiverse::Common;

=head1 DESCRIPTION

This module provides basic functions used across the Biodiverse libraries.
These should be inherited by higher level objects through their @ISA
list.

=head2 Assumptions

Almost all methods in the Biodiverse library use {keyword => value} pairs as a policy.
This means some of the methods may appear to contain unnecessary arguments,
but it makes everything else more consistent.

List methods return a list in list context, and a reference to that list
in scalar context.

=head1 Methods

These assume you have declared an object called $self of a type that
inherits these methods, for example:

=over 4

=item  $self = Biodiverse::BaseData->new;

=back

or

=over 4

=item  $self = Biodiverse::Matrix->new;

=back

or want to clone an existing object

=over 4

=item $self = $old_object->clone;

(This uses the Storable::dclone method).

=back

=head2 Parameter stuff

The parameters are used to store necessary metadata about the object,
such as values used in its construction, references to parent objects
and hash tables of other values such as exclusion lists.  All parameters are
set in upper case, and forced into uppercase if needed.
There are no set parameters for each object type, but most include NAME,
OUTPFX and the like.  

=over 5

=item  $self->set_param(PARAMNAME => $param)

Set a single parameter.  For example,
"$self-E<gt>set_param(NAME => 'hernando')" will set the parameter NAME to the
value 'hernando'

Overwrites any previous entry without any warnings.

=item $self->load_params (file => $filename);

Set parameters from a file.

=item  $self->get_param($param);

Gets the value of a single parameter $param.  

=item  $self->delete_param(@params);

=item  $self->delete_params(@params);

Delete a list of parameters from the object's PARAMS hash.
They are actually the same thing, as delete_param calls delete_params,
passing on any arguments.

=item  $self->get_params_hash;

Returns the parameters hash.

=back

=head2 File read/write

=over 5

=item  $self->load_file (file => $filename);

Loads an object written using the Storable or Sereal format.
Must satisfy the OUTSUFFIX parameter
for the object type being loaded.

=back

=head2 General utilities

=over

=item $self->get_surrounding_elements (coord => \@coord, resolutions => \@resolutions, distance => 1, sep_char => $sep_char);

Generate a list of values around a single coordinate at a specified resolution
out to some resolution C<distance> (default 1).  The values are joined together
using $join_index.
Actually just calculates the minima and maxima and calls
C<$self->getPossIndexValues>.

=item $self->weaken_basedata_ref;

Weakens the reference to a parent BaseData object.  This stops memory
leakage problems due to circular references not being cleared out.
http://www.perl.com/pub/a/2002/08/07/proxyobject.html?page=1

=item $self->csv2list (string => $string, quote_char => "'", sep_char => ",");

convert a CSV string to a list.  Returns an array in list context,
and an array ref in scalar context.  Calls Text::CSV_XS and passes the
arguments onwards.

=item  $self->list2csv (list => \@list, quote_char => "'", sep_char => ",");

Convert a list to a CSV string using text::CSV_XS.  Must be passed a list reference.

=back

=head1 REPORTING ERRORS

https://github.com/shawnlaffan/biodiverse/issues

=head1 AUTHOR

Shawn Laffan

Shawn.Laffan@unsw.edu.au

=head1 COPYRIGHT

Copyright (c) 2006 Shawn Laffan. All rights reserved.  This
program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REVISION HISTORY

=over


=back

=cut
