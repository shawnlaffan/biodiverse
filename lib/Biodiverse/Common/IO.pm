package Biodiverse::Common::IO;
use 5.036;
use warnings;

our $VERSION = '6.99_001';

use Carp qw /croak/;

use Geo::GDAL::FFI;
use Path::Tiny qw /path/;

use English ( -no_match_vars );
use List::MoreUtils qw /none/;
use List::Util qw /first/;
use Storable qw /nstore retrieve/;
use File::BOM ();
use YAML::Syck ();
use Sereal::Encoder qw //;
use Sereal::Decoder qw //;
use File::Basename qw( fileparse );
use Path::Tiny qw /path/;
use Ref::Util qw/is_arrayref/;

use Biodiverse::Logger qw/logger/;

use constant ON_WINDOWS => ($OSNAME eq 'MSWin32');
use if ON_WINDOWS, 'Win32::LongPath';

my $EMPTY_STRING = q{};

#  parse a filename with layer appended
#  Not entirely bulletproof...
sub _parse_gdal_dataset_layer_string_aa {
    my ($self, $fstring) = @_;

    if ($fstring =~ /\.gdbtable$/) {
        $fstring = path($fstring)->parent;
        croak "Invalid geodatabase $fstring" if $fstring !~ /\.gdb$/;
    }

    my ($fname, $layer_name);

    my $p = path ($fstring);
    my $basename = $p->basename;
    if ($basename =~ /:/) {
        (undef, $layer_name) = split ':', $basename;
        $fstring =~ s/:$layer_name$//;
        $layer_name = undef if $layer_name eq '';
        $p = path ($fstring);  #  update
    }
    $fname = $fstring;

    #  Shapefiles can be passed without an extension in the spatial conditions
    #  as Geo::Shapefile, which was what we used, supports this.
    if (!$self->file_exists_aa($fname)) {
        foreach my $ext (qw/shz shp/) {
            if ($self->file_exists_aa("$fname.$ext")) {
                $fname .= ".$ext";
            }
        }
        $p = path($fname);
    }

    #  The shp layer name is its basename while shz files have layer names
    #  as the zip name can differ from the component shapefile.
    if ($fname =~ /\.shp$/) {
        $layer_name = $p->basename =~ s/.shp$//r;
    }

    return wantarray ? ($fname, $layer_name) : [$fname, $layer_name];
}

sub get_gdal_feature_class_layer_from_path {
    my ($self, %args) = @_;

    my $filename = $args{path};

    my ($ds_name, $layer_name) = $self->_parse_gdal_dataset_layer_string_aa($filename);

    my $gdal_args = $args{args};

    my $dataset = Geo::GDAL::FFI::Open($ds_name, $gdal_args);
    if (!length $layer_name) {
        $layer_name = ($dataset->GetLayerNames)[0];
    }
    my $layer   = $dataset->GetLayer($layer_name);

    return $layer;
}

#  generalised handler for file loading
#  works in a sequence, evaling until it gets one that works.
sub load_file {
    my $self = shift;
    my %args = @_;

    croak "Argument 'file' not defined, cannot load from file\n"
        if ! defined ($args{file});

    croak "File $args{file} does not exist or is not readable\n"
        if !$self->file_is_readable (file_name => $args{file});

    (my $suffix) = $args{file} =~ /(\..+?)$/;

    my @importer_funcs
        = $suffix =~ /s$/ ? qw /load_sereal_file load_storable_file/
        : $suffix =~ /y$/ ? qw /load_yaml_file/
        : qw /load_sereal_file load_storable_file/;

    my $object;
    my @errs;
    foreach my $func (@importer_funcs) {
        eval {$object = $self->$func (%args)};
        if ($@) {
            push @errs, "Trying $func:";
            push @errs, $EVAL_ERROR;
        }
        last if defined $object;
    }

    croak "Unable to open object file $args{file}\n"
        . join "\n", @errs
        if !$object;

    return $object;
}

sub load_sereal_file {
    my $self = shift;  #  gets overwritten if the file passes the tests
    my %args = @_;

    croak "argument 'file' not defined\n"
        if !defined ($args{file});

    #my $suffix = $args{suffix} || $self->get_param('OUTSUFFIX') || $EMPTY_STRING;
    my $expected_suffix
        =  $args{suffix}
        // $self->get_param('OUTSUFFIX')
        // eval {$self->get_file_suffix}
        // $EMPTY_STRING;

    my $file = path($args{file})->absolute;
    croak "[BASEDATA] File $file does not exist\n"
        if !$self->file_exists_aa ($file);

    croak "[BASEDATA] File $file does not have the correct suffix\n"
        if !$args{ignore_suffix} && ($file !~ /\.$expected_suffix$/);

    #  load data from sereal file, ignores rest of the args
    use Sereal::Decoder ();
    my $decoder = Sereal::Decoder->new();

    my $string;

    my $fh = $self->get_file_handle (
        file_name => $file,
    );
    $fh->binmode;
    read $fh, $string, 100;  #  get first 100 chars for testing
    $fh->close;

    my $type = $decoder->looks_like_sereal($string);
    if ($type eq '') {
        logger->info("Not a Sereal document");
        croak "$file is not a Sereal document";
    }
    elsif ($type eq '0') {
        logger->info("Possibly utf8 encoded Sereal document");
        croak "Possibly utf8 encoded Sereal document"
            . "Won't open $file as a Sereal document";
    }
    else {
        logger->info("Sereal document version $type");
    }

    #  now get the whole file
    {
        local $/ = undef;
        my $fh1 = $self->get_file_handle (
            file_name => $file,
        );
        binmode $fh1;
        $string = <$fh1>;
    }

    #my $structure;
    #$self = $decoder->decode($string, $structure);
    eval {
        $decoder->decode($string, $self);
    };
    croak $@ if $@;

    $self->set_last_file_serialisation_format ('sereal');

    return $self;
}


sub load_storable_file {
    my $self = shift;  #  gets overwritten if the file passes the tests
    my %args = @_;

    croak "argument 'file' not defined\n"  if ! defined ($args{file});

    my $suffix = $args{suffix} || $self->get_param('OUTSUFFIX') || $EMPTY_STRING;

    my $file = path($args{file})->absolute;

    croak "Unicode file names not supported for Storable format,"
        . "please rename $file and try again\n"
        if !-e $file && $self->file_exists_aa ($file);

    croak "File $file does not exist\n"
        if !-e $file;

    croak "File $file does not have the correct suffix\n"
        if !$args{ignore_suffix} && ($file !~ /$suffix$/);

    #  attempt reconstruction of code refs -
    #  NOTE THAT THIS IS NOT YET SAFE FROM MALICIOUS DATA
    #local $Storable::Eval = 1;

    #  load data from storable file, ignores rest of the args
    #  could use fd_retrieve, but code does not pass all tests
    $self = retrieve($file);
    if ($Storable::VERSION le '2.15') {
        foreach my $fn (qw /weaken_parent_refs weaken_child_basedata_refs weaken_basedata_ref/) {
            $self->$fn if $self->can($fn);
        }
    }
    $self->set_last_file_serialisation_format ('storable');

    return $self;
}


sub load_yaml_file {
    croak 'Loading from a YAML file is no longer supported';
}

#  for backwards compatibility
*write = \&save_to;

sub set_last_file_serialisation_format {
    my ($self, $format) = @_;

    croak "Invalid serialisation format name passed"
        if ($format // '') !~ /^(?:sereal|storable)$/;

    return $self->set_param(LAST_FILE_SERIALISATION_FORMAT => $format);
}

sub get_last_file_serialisation_format {
    my $self = shift;
    return $self->get_param('LAST_FILE_SERIALISATION_FORMAT') // 'sereal';
}

#  some objects have save methods, some do not
*save =  \&save_to;

sub save_to {
    my $self = shift;
    my %args = @_;
    my $file_name = delete $args{filename}
        || $args{OUTPFX}
        || $self->get_param('NAME')
        || $self->get_param('OUTPFX');

    croak "Argument 'filename' not specified\n" if ! defined $file_name;

    my $storable_suffix = $self->get_param ('OUTSUFFIX');
    my $yaml_suffix     = $self->get_param ('OUTSUFFIX_YAML');

    my @suffixes = ($storable_suffix, $yaml_suffix);

    my (undef, undef, $suffix) = fileparse ( $file_name, @suffixes );
    if ($suffix eq $EMPTY_STRING
        || ! defined $suffix
        || none  {$suffix eq $_} @suffixes
    ) {
        $suffix = $storable_suffix;
        $file_name .= '.' . $suffix;
    }

    my $tmp_file_name = $file_name . '.tmp';

    #my $method = $suffix eq $yaml_suffix ? 'save_to_yaml' : 'save_to_storable';
    my $method = delete $args{method};
    if (!defined $method) {
        my $last_fmt_is_sereal = $self->get_last_file_serialisation_format eq 'sereal';
        $method
            = $suffix eq $yaml_suffix ? 'save_to_yaml'
            : $last_fmt_is_sereal     ? 'save_to_sereal'
            : 'save_to_storable';
    }

    croak "Invalid save method name $method\n"
        if not $method =~ /^save_to_\w+$/;

    my $result = eval {$self->$method (filename => $tmp_file_name, %args)};
    croak $EVAL_ERROR if $EVAL_ERROR;

    logger->info("[COMMON] Renaming $tmp_file_name to $file_name ... ");
    my $success = rename ($tmp_file_name, $file_name);
    croak "Unable to rename $tmp_file_name to $file_name\n"
        if !$success;

    return $file_name;
}

#  Dump the whole object to a Sereal file.
sub save_to_sereal {
    my $self = shift;
    my %args = @_;

    my $file = $args{filename};
    if (! defined $file) {
        my $prefix = $args{OUTPFX} || $self->get_param('OUTPFX') || $self->get_param('NAME') || caller();
        $file = path($file || ($prefix . '.' . $self->get_param('OUTSUFFIX')));
    }
    $file = path($file)->absolute;

    logger->info("[COMMON] WRITING TO SEREAL FORMAT FILE $file");

    use Sereal::Encoder ();

    my $encoder = Sereal::Encoder->new({
        undef_unknown    => 1, #  strip any code refs
        protocol_version => 4, #  should be an argument
        freeze_callbacks => 1,
        compress         => $args{compress} // Sereal::Encoder::SRL_ZSTD,
    });

    open (my $fh, '>', $file) or die "Cannot open $file";
    binmode $fh;

    eval {
        print {$fh} $encoder->encode($self);
    };
    my $e = $EVAL_ERROR;

    $fh->close;

    croak $e if $e;

    return $file;
}


#  Dump the whole object to a Storable file.
#  Get the prefix from $self{PARAMS}, or some other default.
sub save_to_storable {
    my $self = shift;
    my %args = @_;

    my $file = $args{filename};
    if (! defined $file) {
        my $prefix = $args{OUTPFX} || $self->get_param('OUTPFX') || $self->get_param('NAME') || caller();
        $file = path($file || ($prefix . '.' . $self->get_param('OUTSUFFIX')));
    }
    $file = path($file)->absolute;

    logger->info("[COMMON] WRITING TO STORABLE FORMAT FILE $file");

    local $Storable::Deparse = 0;     #  for code refs
    local $Storable::forgive_me = 1;  #  don't croak on GLOBs, regexps etc.
    eval { nstore $self, $file };
    my $e = $EVAL_ERROR;
    croak $e if $e;

    return $file;
}


#  Dump the whole object to a yaml file.
#  Get the prefix from $self{PARAMS}, or some other default.
sub save_to_yaml {
    my $self = shift;
    my %args = @_;

    my $file = $args{filename};
    if (! defined $file) {
        my $prefix = $args{OUTPFX} || $self->get_param('OUTPFX') || $self->get_param('NAME') || caller();
        $file = path($file || ($prefix . "." . $self->get_param('OUTSUFFIX_YAML')));
    }
    $file = path($file)->absolute;

    logger->info("[COMMON] WRITING TO YAML FORMAT FILE $file");

    eval {YAML::Syck::DumpFile ($file, $self)};
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $file;
}

sub save_to_data_dumper {
    my $self = shift;
    my %args = @_;

    my $file = $args{filename};
    if (! defined $file) {
        my $prefix = $args{OUTPFX} || $self->get_param('OUTPFX') || $self->get_param('NAME') || caller();
        my $suffix = $self->get_param('OUTSUFFIX') || 'data_dumper';
        $file = path($file || ($prefix . '.' . $suffix));
    }
    $file = path($file)->absolute;

    logger->info("[COMMON] WRITING TO DATA DUMPER FORMAT FILE $file");

    use Data::Dumper ();
    open (my $fh, '>', $file);
    print {$fh} Dumper ($self);
    $fh->close;

    return $file;
}


#  dump a data structure to a yaml file.
sub dump_to_yaml {
    my $self = shift;
    my %args = @_;

    my $data = $args{data};

    if (defined $args{filename}) {
        my $file = path($args{filename})->absolute;
        logger->info("WRITING TO YAML FORMAT FILE $file");
        YAML::Syck::DumpFile ($file, $data);
    }
    else {
        print YAML::Syck::Dump ($data);
        print "...\n";
    }

    return $args{filename};
}

#  dump a data structure to a yaml file.
sub dump_to_json {
    my $self = shift;
    my %args = @_;

    #use Cpanel::JSON::XS;
    use JSON::MaybeXS ();

    my $data = $args{data};

    if (defined $args{filename}) {
        my $file = path($args{filename})->absolute;
        logger->info("WRITING TO JSON FILE $file");
        open (my $fh, '>', $file)
            or croak "Cannot open $file to write to, $!\n";
        print {$fh} JSON::MaybeXS::encode_json ($data);
        $fh->close;
    }
    else {
        print JSON::MaybeXS::encode_json ($data);
    }

    return $args{filename};
}


#  escape any special characters in a file name
#  just a wrapper around URI::Escape::XS::escape_uri
sub escape_filename {
    my $self = shift;
    my %args = @_;
    my $string = $args{string};

    croak "Argument 'string' undefined\n"
        if !defined $string;

    use URI::Escape::XS qw/uri_escape/;
    my $escaped_string;
    my @letters = split '', $string;
    foreach my $letter (@letters) {
        if ($letter =~ /\W/ && $letter !~ / /) {
            $letter = uri_escape ($letter);
        }
        $escaped_string .= $letter;
    }

    return $escaped_string;
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
        logger->info("[COMMON] Not a recognised suffix $suffix, using csv/txt format");
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
        logger->info("[COMMON] Write to file $file successful");
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

    use HTML::QuickTable ();
    my $qt = HTML::QuickTable->new();

    my $table = $qt->render($args{data});

    open my $fh, '>', $file;

    eval {
        print {$fh} $table;
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    if ($fh->close) {
        logger->info("[COMMON] Write to file $file successful")
    }
    else {
        croak "[COMMON] Write to file $file failed, unable to close file\n"
    }

    return;
}

sub get_shortpath_filename {
    my ($self, %args) = @_;

    my $file_name = $args{file_name}
        // croak 'file_name not specified';

    return $file_name if not ON_WINDOWS;

    my $short_path = $self->file_exists_aa($file_name) ? shortpathL ($file_name) : '';

    # die "unable to get short name for $file_name ($^E)"
    #   if $short_path eq '';

    return $short_path;
}

sub get_file_handle {
    my ($self, %args) = @_;

    my $file_name = $args{file_name}
        // croak 'file_name not specified';

    my $mode = $args{mode} // $args{layers};
    $mode ||= '<';
    if ($args{use_bom}) {
        $mode .= ':via(File::BOM)';
    }

    my $fh;

    if (ON_WINDOWS && !-e $file_name) {
        openL (\$fh, $mode, $file_name)
            or die ("unable to open $file_name ($^E)");
    }
    else {
        open $fh, $mode, $file_name
            or die "Unable to open $file_name, $!";
    }

    croak "CANNOT GET FILE HANDLE FOR $file_name\n"
        . "MODE IS $mode\n"
        if !$fh;

    return $fh;
}

sub file_exists_aa {
    $_[0]->file_exists (file_name => $_[1]);
}

sub file_exists {
    my ($self, %args) = @_;

    my $file_name = $args{file_name};

    return 1 if -e $file_name;

    if (ON_WINDOWS) {
        return testL ('e', $file_name);
    }

    return;
}

sub dir_exists_aa {
    my ($self, $dir) = @_;

    return 1 if -d $dir;

    return testL ('d', $dir)
        if ON_WINDOWS;

    return;
}

sub file_is_readable_aa {
    $_[0]->file_is_readable (file_name => $_[1]);
}

sub file_is_readable {
    my ($self, %args) = @_;

    my $file_name = $args{file_name};

    return 1 if -r $file_name;

    if (ON_WINDOWS) {
        #  Win32::LongPath always returns 1 for r
        return testL ('e', $file_name) && testL ('r', $file_name);
    }

    return;
}

sub get_file_size_aa {
    $_[0]->get_file_size (file_name => $_[1]);
}

sub get_file_size {
    my ($self, %args) = @_;

    my $file_name = $args{file_name};

    my $file_size;

    if (-e $file_name) {
        $file_size = -s $file_name;
    }
    elsif (ON_WINDOWS) {
        my $stat = statL ($file_name)
            or die ("unable to get stat for $file_name ($^E)");
        $file_size = $stat->{size};
    }
    else {
        croak "[BASEDATA] get_file_size $file_name DOES NOT EXIST OR CANNOT BE READ\n";
    }

    return $file_size;
}

sub unlink_file {
    my ($self, %args) = @_;
    my $file_name = $args{file_name}
        // croak 'file_name arg not specified';

    my $count = 0;
    if (ON_WINDOWS) {
        $count = unlinkL ($file_name) or die "unable to delete file ($^E)";
    }
    else {
        $count = unlink ($file_name) or die "unable to delete file ($^E)";
    }

    return $count;
}

sub get_book_struct_from_spreadsheet_file {
    my ($self, %args) = @_;

    #  Defer loading to run time for speed reasons,
    #  and it is not often used.
    require Spreadsheet::Read;

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
        $book = Spreadsheet::Read::ReadData($fh, parser => $extension);
    }
    else {
        #  sxc files and similar
        $book = Spreadsheet::Read::ReadData($file);
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

sub get_next_line_set {
    my $self = shift;
    my %args = @_;

    use Biodiverse::Progress;

    my $progress_bar        = Biodiverse::Progress->new (gui_only => 1);
    my $file_handle         = $args{file_handle};
    my $target_line_count   = $args{target_line_count};
    my $file_name           = $args{file_name}    || $EMPTY_STRING;
    my $size_comment        = $args{size_comment} || $EMPTY_STRING;
    my $csv                 = $args{csv_object};

    my $progress_pfx = "Loading next $target_line_count lines \n"
        . "of $file_name into memory\n"
        . $size_comment;

    $progress_bar->update ($progress_pfx, 0);

    #  now we read the lines
    my @lines;
    while (scalar @lines < $target_line_count) {
        my $line = $csv->getline ($file_handle);
        if (not $csv->error_diag) {
            push @lines, $line;
        }
        elsif (not $csv->eof) {
            logger->info($csv->error_diag, ', Skipping line ', scalar @lines, ' of chunk');
            $csv->SetDiag (0);
        }
        if ($csv->eof) {
            #$self->set_param (IMPORT_TOTAL_CHUNK_TEXT => $$chunk_count);
            #pop @lines if not defined $line;  #  undef returned for last line in some cases
            last;
        }
        $progress_bar->update (
            $progress_pfx,
            (scalar @lines / $target_line_count),
        );
    }

    return wantarray ? @lines : \@lines;
}

1;