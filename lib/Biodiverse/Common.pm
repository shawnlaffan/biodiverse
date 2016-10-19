package Biodiverse::Common;

#  a set of common functions for the Biodiverse library

use strict;
use warnings;
use 5.010;

use Carp;
use English ( -no_match_vars );

use Data::DumpXML qw /dump_xml/;
use Data::Dumper  qw /Dumper/;
use YAML::Syck;
#use YAML::XS;
use Text::CSV_XS;
use Scalar::Util qw /weaken isweak blessed looks_like_number reftype/;
use List::MoreUtils qw /none/;
use List::Util qw /first/;
use Storable qw /nstore retrieve dclone/;
use File::Basename;
use Path::Class;
#use POSIX;  #  make all the POSIX functions available to the spatial parameters - do we still need this here?
use HTML::QuickTable;
#use XBase;
#use MRO::Compat;
use Class::Inspector;

#  Need to avoid an OIO destroyed twice warning due
#  to HTTP::Tiny, which is used in Biodiverse::GUI::Help
#  but wrap it in an eval to avoid problems on threaded builds
BEGIN {
    eval 'use threads';
}

use Math::Random::MT::Auto;  

#use Regexp::Common qw /number/;

use Biodiverse::Progress;
use Biodiverse::Exception;

require Clone;

our $VERSION = '1.99_006';

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
    return $self -> get_param ('LAST_UPDATE_TIME');
}

sub set_last_update_time {
    my $self = shift;
    my $time = shift || time;
    $self -> set_param (LAST_UPDATE_TIME => $time);
    
    return;
}

#  generalised handler for file loading
#  works in a sequence, evaling until it gets one that works.  
sub load_file {
    my $self = shift;
    my %args = @_;

    croak "Argument 'file' not defined, cannot load from file\n"
      if ! defined ($args{file});
      
    croak "File $args{file} does not exist or is not readable\n"
      if !-r $args{file};

    my $suffix = $args{file} =~ /\..+?$/;

    my @importer_funcs
      = $suffix =~ /s$/ ? qw /load_sereal_file load_storable_file/
      : $suffix =~ /y$/ ? qw /load_yaml_file/
      : qw /load_sereal_file load_storable_file load_yaml_file/;

    my $object;
    foreach my $func (@importer_funcs) {
        $object = eval {$self->$func (%args)};
        #warn $EVAL_ERROR if $EVAL_ERROR;
        last if defined $object;
    }

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

    my $file = Path::Class::file($args{file})->absolute;
    croak "[BASEDATA] File $file does not exist\n"
      if !-e $file;

    croak "[BASEDATA] File $file does not have the correct suffix\n"
       if !$args{ignore_suffix} && ($file !~ /\.$expected_suffix$/);

    #  load data from sereal file, ignores rest of the args
    use Sereal::Decoder;
    my $decoder = Sereal::Decoder->new();

    my $string;

    open my $fh, '<', $file or die 'Cannot open $file, $!';
    $fh->binmode;
    read $fh, $string, 100;  #  get first 100 chars for testing
    $fh->close;

    my $type = $decoder->looks_like_sereal($string);
    if ($type eq '') {
        say "Not a Sereal document";
        croak "$file is not a Sereal document";
    }
    elsif ($type eq '0') {
        say "Possibly utf8 encoded Sereal document";
        croak "Won't open $file as a Sereal document";
    }
    else {
        say "Sereal document version $type";
    }

    #  now get the whole file
    {
        local $/ = undef;
        open my $fh, '<', $file or die 'Cannot open $file';
        $string = <$fh>;
    }

    #my $structure;
    #$self = $decoder->decode($string, $structure);
    $decoder->decode($string, $self);

    $self->set_last_file_serialisation_format ('sereal');

    return $self;
}


sub load_storable_file {
    my $self = shift;  #  gets overwritten if the file passes the tests
    my %args = @_;

    croak "argument 'file' not defined\n"  if ! defined ($args{file});

    my $suffix = $args{suffix} || $self->get_param('OUTSUFFIX') || $EMPTY_STRING;

    my $file = Path::Class::file($args{file})->absolute;
    if (! -e $file) {
        croak "[BASEDATA] File $file does not exist\n";
    }

    if (!$args{ignore_suffix} && ($file !~ /$suffix$/)) {
        croak "[BASEDATA] File $file does not have the correct suffix\n";
    }

    #  attempt reconstruction of code refs -
    #  NOTE THAT THIS IS NOT YET SAFE FROM MALICIOUS DATA
    #local $Storable::Eval = 1;

    #  load data from storable file, ignores rest of the args
    $self = retrieve($file);
    if ($Storable::VERSION < 2.15) {
        foreach my $fn (qw /weaken_parent_refs weaken_child_basedata_refs weaken_basedata_ref/) {
            $self -> $fn if $self->can($fn);
        }
    }
    $self->set_last_file_serialisation_format ('storable');

    return $self;
}

#  REDUNDANT
sub __load_xml_file {
    my $self = shift;  #  gets overwritten if the file passes the tests
    my %args = @_;

    return if ! defined ($args{file});
    my $suffix = $args{suffix} || $self->get_param('OUTSUFFIX_XML');

    return if ! -e $args{file};
    return if ! ($args{file} =~ /$suffix$/);

    #  load data from bdx file, ignores rest of the args
    my $xml = Data::DumpXML::Parser->new;
    my $data = $xml->parsefile($args{file});
    $self = shift (@$data);  #  parsefile returns a list, we want the first (and only) element
    foreach my $fn (qw /weaken_parent_refs weaken_child_basedata_refs weaken_basedata_ref/) {
        $self -> $fn if $self->can($fn);
    }
    
    return $self;
}

sub load_yaml_file {
    my $self = shift;  #  gets overwritten if the file passes the tests
    my %args = @_;

    return if ! defined ($args{file});
    my $suffix = $args{suffix} || $self->get_param('OUTSUFFIX_YAML') || $EMPTY_STRING;

    return if ! -e $args{file};
    return if ! ($args{file} =~ /$suffix$/);

    #my $loaded = YAML::XS::LoadFile ($args{file});
    my $loaded = YAML::Syck::LoadFile ($args{file});

    #  yaml does not handle weak refs, so we need to put them back in
    foreach my $fn (qw /weaken_parent_refs weaken_child_basedata_refs weaken_basedata_ref/) {
        if ($loaded->can($fn)) {
            say $fn;
            eval {
                $loaded->$fn;
                1;
            };
            warn $EVAL_ERROR if $EVAL_ERROR;
        }
        #$self->$fn if $self->can($fn);
    }

    return $loaded;
}

sub load_data_dumper_file {
    my $self = shift;  #  gets overwritten if the file passes the tests
    my %args = @_;

    return if ! defined ($args{file});
    #my $suffix = $args{suffix} || $self->get_param('OUTSUFFIX_YAML') || $EMPTY_STRING;

    return if ! -e $args{file};
    #return if ! ($args{file} =~ /$suffix$/);

    my $data;
    {
        local $/ = undef;
        open(my $fh, '<', $args{file}) or die "Cannot open $args{file}\n";
        $data = <$fh>;
    }
    $self = eval $data;

    #  yaml does not handle waek refs, so we need to put them back in
    #foreach my $fn (qw /weaken_parent_refs weaken_child_basedata_refs weaken_basedata_ref/) {
    #    $self -> $fn if $self->can($fn);
    #}

    return $self;
}

sub set_basedata_ref {
    my $self = shift;
    my %args = @_;

    $self->set_param (BASEDATA_REF => $args{BASEDATA_REF});
    $self->weaken_basedata_ref;

    return;
}

sub get_basedata_ref {
    my $self = shift;

    my $bd = $self->get_param ('BASEDATA_REF')
           || Biodiverse::MissingBasedataRef->throw (
              message => 'Parameter BASEDATA_REF not set'
            );
    
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

#  is this used anymore?
sub load_params {  # read in the parameters file, set the PARAMS subhash.
    my $self = shift;
    my %args = @_;

    open (my $fh, '<', $args{file}) || croak ("Cannot open $args{file}\n");

    local $/ = undef;
    my $data = <$fh>;
    $fh -> close;
    
    my %params = eval ($data);
    $self -> set_param(%params);
    
    return;
}

#  extremely hot path, so needs to be lean and mean, even if less readable
sub get_param {
    no autovivification;
    $_[0]->{PARAMS}{$_[1]};
}

#  sometimes we want a reference to the parameter to allow direct manipulation.
#  this is only really needed if it is a scalar, as lists are handled as refs already
sub get_param_as_ref {
    my $self = shift;
    my $param = shift;

    return if ! $self->exists_param ($param);

    my $value = $self->get_param ($param);
    #my $test_value = $value;  #  for debug
    if (not ref $value) {
        $value = \$self->{PARAMS}{$param};  #  create a ref if it is not one already
        #  debug checker
        #carp "issues in get_param_as_ref $value $test_value\n" if $$value ne $test_value;
    }

    return $value;
}

#  sometimes we only care if it exists, as opposed to its being undefined
sub exists_param {
    my $self = shift;
    my $param = shift;
    croak "param not specified\n" if !defined $param;
    
    my $x = exists $self->{PARAMS}{$param};
    return $x;
}

sub get_params_hash {
    my $self = shift;
    my $params = $self->{PARAMS};
    
    return wantarray ? %$params : $params;
}

#  set a single parameter
sub set_param {
    $_[0]->{PARAMS}{$_[1]} = $_[2];

    1;
}

#  Could use a slice for speed, but it's not used very often.
#  Could also return 1 if it is ever used in hot paths.
sub set_params {
    my $self = shift;
    my %args = @_;

    foreach my $param (keys %args) {
        $self->{PARAMS}{$param} = $args{$param};
    }

    return scalar keys %args;
}

sub delete_param {  #  just passes everything through to delete_params
    my $self = shift;
    $self->delete_params(@_);

    return;
}

#  sometimes we have a reference to an object we wish to make weak
sub weaken_param {
    my $self = shift;
    my $count = 0;

    foreach my $param (@_) {
        if (! exists $self->{PARAMS}{$param}) {
            croak "Cannot weaken param $param, it does not exist\n";
        }

        if (not isweak ($self->{PARAMS}{$param})) {
            weaken $self->{PARAMS}{$param};
            #print "[COMMON] Weakened ref to $param, $self->{PARAMS}{$param}\n";
        }
        $count ++;
    }

    return $count;
}

sub delete_params {
    my $self = shift;

    my $count = 0;
    foreach my $param (@_) {  #  should only delete those that exist...
        if (delete $self->{PARAMS}{$param}) {
            $count ++;
            print "Deleted parameter $param from $self\n"
                if $self->get_param('PARAM_CHANGE_WARN');
        }
    }  #  inefficient, as we could use a hash slice to do all in one hit, but allows better feedback

    return $count;
}

#  an internal apocalyptic sub.  use only for destroy methods
sub _delete_params_all {
    my $self = shift;
    my $params = $self->{PARAMS};

    foreach my $param (keys %$params) {
        print "Deleting parameter $param\n";
        delete $params->{$param};
    }
    $params = undef;

    return;
}

sub print_params {
    my $self = shift;
    print Data::Dumper::Dumper ($self->{PARAMS});

    return;
}

sub increment_param {
    my ($self, $param, $value) = @_;
    $self->{PARAMS}{$param} += $value;
}

#  Load a hash of any user defined default params
our %user_defined_params;
BEGIN {

    #  load user defined indices, but only if the ignore flag is not set
    if (     exists $ENV{BIODIVERSE_DEFAULT_PARAMS}
        && ! $ENV{BIODIVERSE_DEFAULT_PARAMS_IGNORE}) {
        print "[COMMON] Checking and loading user defined globals";
        my $x;
        if (-e $ENV{BIODIVERSE_DEFAULT_PARAMS}) {
            print " from file $ENV{BIODIVERSE_DEFAULT_PARAMS}\n";
            local $/ = undef;
            open (my $fh, '<', $ENV{BIODIVERSE_DEFAULT_PARAMS});
            $x = eval (<$fh>);
            close ($fh);
        }
        else {
            print " directly from environment variable\n";
            $x = eval "$ENV{BIODIVERSE_DEFAULT_PARAMS}";
        }
        if ($@) {
            my $msg = "[COMMON] Problems with environment variable "
                    . "BIODIVERSE_DEFAULT_PARAMS "
                    . " - check the filename or syntax\n"
                    . $@
                    . "\n$ENV{BIODIVERSE_DEFAULT_PARAMS}\n";
            croak $msg;
        }
        print "Default parameters are:\n", Data::Dumper::Dumper ($x);

        if ((ref $x) =~ /HASH/) {
            @user_defined_params{keys %$x} = values %$x;
        }
    }
}

#  assign any user defined default params
#  a bit risky as it allows anything to be overridden
sub set_default_params {
    my $self = shift;
    my $package = ref ($self);
    
    return if ! exists $user_defined_params{$package};
    
    #  make a clone to avoid clashes with multiple objects
    #  receiving the same data structures
    my $params = $self->clone (data => $user_defined_params{$package});
    
    $self -> set_params (%$params);  
    
    return;
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
    
    my $name = $self->get_param ('NAME');
    my $cleared;

    if (my $sp_index = $self->get_param ('SPATIAL_INDEX')) {
        $sp_index->delete_param('CSV_OBJECT');
        $sp_index->delete_cached_values (keys => ['CSV_OBJECT']);
        $cleared = 1;
    }

    return $cleared;
}


#  set any value - allows user specified additions to the core stuff
sub set_cached_value {
    my $self = shift;
    my %args = @_;
    @{$self->{_cache}}{keys %args} = values %args;

    return;
}

sub set_cached_values {
    my $self = shift;
    $self->set_cached_value (@_);
}

#  hot path, so needs to be lean and mean, even if less readable
sub get_cached_value {
    return if ! exists $_[0]->{_cache}{$_[1]};
    return $_[0]->{_cache}{$_[1]};
}

#  dor means defined or - too obscure?
sub get_cached_value_dor_set_default_aa {
    no autovivification;
    $_[0]->{_cache}{$_[1]} //= $_[2];
}

sub get_cached_value_keys {
    my $self = shift;
    
    return if ! exists $self->{_cache};
    
    return wantarray
        ? keys %{$self->{_cache}}
        : [keys %{$self->{_cache}}];
}

sub delete_cached_values {
    my $self = shift;
    my %args = @_;
    
    return if ! exists $self->{_cache};

    my $keys = $args{keys} || $self->get_cached_value_keys;
    return if not defined $keys or scalar @$keys == 0;

    delete @{$self->{_cache}}{@$keys};
    delete $self->{_cache} if scalar keys %{$self->{_cache}} == 0;

    #  This was generating spurious warnings under test regime.
    #  It should be unnecesary anyway.
    #warn "Cache deletion problem\n$EVAL_ERROR\n"
    #  if $EVAL_ERROR;

    #warn "XXXXXXX "  . $self->get_name . "\n" if exists $self->{_cache};

    return;
}

sub delete_cached_value {
    my ($self, $key) = @_;
    no autovivification;
    delete $self->{_cache}{$key};
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

    if ($self -> get_param ('RUN_FROM_GUI')) {

        $args{type} = 'update_log';
        $self->dump_to_yaml (data => \%args);
    }
    else {
        print $args{text};
    }

    return;
}

#  for backwards compatibility
*write = \&save_to;

sub set_last_file_serialisation_format {
    my ($self, $format) = @_;

    croak "Invalid serialisation format name passed"
      if not ($format // '') =~ /^(?:sereal|storable)$/;

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
    my $file_name = $args{filename}
                    || $args{OUTPFX}
                    || $self->get_param('NAME')
                    || $self->get_param('OUTPFX');

    croak "Argument 'filename' not specified\n" if ! defined $file_name;

    my $storable_suffix = $self->get_param ('OUTSUFFIX');
    my $yaml_suffix     = $self->get_param ('OUTSUFFIX_YAML');

    my @suffixes = ($storable_suffix, $yaml_suffix);

    my ($null1, $null2, $suffix) = fileparse ( $file_name, @suffixes ); 
    if ($suffix eq $EMPTY_STRING
        || ! defined $suffix
        || none  {$suffix eq $_} @suffixes
        ) {
        $suffix = $storable_suffix;
        $file_name .= '.' . $suffix;
    }

    my $tmp_file_name = $file_name . '.tmp';

    #my $method = $suffix eq $yaml_suffix ? 'save_to_yaml' : 'save_to_storable';
    my $method = $args{method};
    if (!defined $method) {
        my $last_fmt_is_sereal = $self->get_last_file_serialisation_format eq 'sereal';
        $method
          = $suffix eq $yaml_suffix ? 'save_to_yaml'
          : $last_fmt_is_sereal     ? 'save_to_sereal' 
          : 'save_to_storable';
    }

    croak "Invalid save method name $method\n"
      if not $method =~ /^save_to_\w+$/;

    my $result = eval {$self->$method (filename => $tmp_file_name)};
    croak $EVAL_ERROR if $EVAL_ERROR;

    print "[COMMON] Renaming $tmp_file_name to $file_name ... ";
    my $success = rename ($tmp_file_name, $file_name);
    croak "Unable to rename $tmp_file_name to $file_name\n"
      if !$success;
    print "Done\n";

    return $file_name;
}

#  Dump the whole object to a Sereal file.
sub save_to_sereal {
    my $self = shift;
    my %args = @_;

    my $file = $args{filename};
    if (! defined $file) {
        my $prefix = $args{OUTPFX} || $self->get_param('OUTPFX') || $self->get_param('NAME') || caller();
        $file = Path::Class::file($file || ($prefix . '.' . $self->get_param('OUTSUFFIX')));
    }
    $file = Path::Class::file($file)->absolute;

    say "[COMMON] WRITING TO SEREAL FORMAT FILE $file";

    use Sereal::Encoder;

    my $encoder = Sereal::Encoder->new({
        undef_unknown => 1,  #  strip any code refs
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
        $file = Path::Class::file($file || ($prefix . '.' . $self->get_param('OUTSUFFIX')));
    }
    $file = Path::Class::file($file)->absolute;

    print "[COMMON] WRITING TO STORABLE FORMAT FILE $file\n";

    local $Storable::Deparse = 0;     #  for code refs
    local $Storable::forgive_me = 1;  #  don't croak on GLOBs, regexps etc.
    eval { nstore $self, $file };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $file;
}

#  Dump the whole object to an xml file.
#  Get the prefix from $self{PARAMS}, or some other default.
sub save_to_xml {  
    my $self = shift;
    my %args = @_;

    my $file = $args{filename};
    if (! defined $file) {
        my $prefix = $args{OUTPFX} || $self->get_param('OUTPFX') || $self->get_param('NAME') || caller();
        my $suffix = $self->get_param('OUTSUFFIX') || 'xml';
        $file = Path::Class::file($file || ($prefix . '.' . $suffix));
    }
    $file = Path::Class::file($file)->absolute;

    print "[COMMON] WRITING TO XML FORMAT FILE $file\n";

    open (my $fh, '>', $file);
    print $fh dump_xml ($self);
    $fh->close;

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
        $file = Path::Class::file($file || ($prefix . "." . $self->get_param('OUTSUFFIX_YAML')));
    }
    $file = Path::Class::file($file)->absolute;

    print "[COMMON] WRITING TO YAML FORMAT FILE $file\n";

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
        $file = Path::Class::file($file || ($prefix . '.' . $suffix));
    }
    $file = Path::Class::file($file)->absolute;

    print "[COMMON] WRITING TO DATA DUMPER FORMAT FILE $file\n";

    use Data::Dumper;
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
        my $file = Path::Class::file($args{filename})->absolute;
        say "WRITING TO YAML FORMAT FILE $file";
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
    use JSON::MaybeXS;

    my $data = $args{data};

    if (defined $args{filename}) {
        my $file = Path::Class::file($args{filename})->absolute;
        say "WRITING TO JSON FILE $file";
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

sub dump_to_xml {
    my $self = shift;
    my %args = @_;

    my $data = $args{data};

    my $file = $args{filename};
    if (defined $file) {
        $file = Path::Class::file($args{filename})->absolute;
        say "WRITING TO XML FORMAT FILE $file";
        open (my $fh, '>', $file);
        print $fh dump_xml ($data);
        $fh->close;
    }
    else {
        print dump_xml ($data);
    }

    return $file;
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
    
    return uri_escape ($string);
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
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";

    $args{file} = Path::Class::file($args{file})->absolute;

    #  now do stuff depending on what format was chosen, based on the suffix
    my ($prefix, $suffix) = lc ($args{file}) =~ /(.*?)\.(.*?)$/;
    if (! defined $suffix) {
        $suffix = 'csv';  #  does not affect the actual file name, as it is not passed onwards
    }

    if ($suffix =~ /csv|txt/i) {
        $self -> write_table_csv (%args);
    }
    #elsif ($suffix =~ /dbf/i) {
    #    $self -> write_table_dbf (%args);
    #}
    elsif ($suffix =~ /htm/i) {
        $self->write_table_html (%args);
    }
    elsif ($suffix =~ /xml/i) {
        $self->write_table_xml (%args);
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
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
    my $file = $args{file} || croak "file arg not specified\n";

    my $csv_obj = $self->get_csv_object_for_export (%args);

    open (my $fh, '>', $file)
        || croak "Could not open $file for writing\n";

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

    if ($fh -> close) {
        say "[COMMON] Write to file $file successful";
    }
    else {
        croak "[COMMON] Unable to close $file\n";
    };

    return;
}

#sub write_table_dbf {
#    my $self = shift;
#    my %args = @_;
#    my $data = $args{data} || croak "data arg not specified\n";
#    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
#    my $file = $args{file} || croak "file arg not specified\n";
#    
#    if (-e $file) {
#        print "[COMMON] $file exists - deleting... ";
#        if (! (unlink ($file))) {
#            print "COULD NOT DELETE FILE - check permissions and file locks\n";
#            return;
#        }
#        print "\n";
#    }
#    
#    my $header = shift (@$data);
#    
#    #  set up the field types
#    my @field_types = ("C", ("F") x $#$header);
#    my @field_lengths = (64, (20) x $#$header);
#    my @field_decimals = (undef, (10) x $#$header);
#    my %flds_to_check;
#    @flds_to_check{1 .. $#$header} = (undef) x $#$header;  #  need to check all bar the first field
#    
#    foreach my $record (@$data) {
#        foreach my $j (keys %flds_to_check) {
#            if (defined $record->[$j] and ! looks_like_number $record->[$j]) {  #  assume it's a character type
#                $field_types[$j] = "C";
#                $field_lengths[$j] = 64;
#                $field_decimals[$j] = undef;
#                delete $flds_to_check{$j};
#            }
#        }
#        last if ! scalar keys %flds_to_check;  #  they're all characters, drop out
#    }
#    
#    my $db = XBase -> create (name => $file,
#                              #version => 4,
#                              field_names => $header,
#                              field_types => \@field_types,
#                              field_lengths => \@field_lengths,  
#                              field_decimals => \@field_decimals,
#                              ) || die XBase->errstr;
#    
#    my $i = 0;
#    foreach my $record (@$data) {
#        $db -> set_record ($i, @$record);
#        $i++;
#    }
#    
#    if ($db -> close) {
#        print "[COMMON] Write to file $file successful\n";
#    }
#    else {
#        carp "[COMMON] Write to file $file failed\n";
#    };
#
#    
#}

sub write_table_xml {  #  dump the table to an xml file.
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
    my $file = $args{file} || croak "file arg not specified\n";

    if (-e $file) {
        print "[COMMON] $file exists - deleting... ";
        croak "COULD NOT OVERWRITE $file - check permissions and file locks\n"
            if ! unlink $file;
        print "\n";
    }

    open (my $fh, '>', $file);
    eval {
        print $fh dump_xml($data)
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    if ($fh -> close) {
        print "[COMMON] Write to file $file successful\n";
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
    (ref $data) =~ /ARRAY/ // croak "data arg must be an array ref\n";
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
    (ref $data) =~ /ARRAY/ // croak "data arg must be an array ref\n";
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

#sub write_table_shapefile {
#    carp "Shapefile export not supported due to bugs in shapelib library.\n";
#    return;
#    
#    my $self = shift;
#    my %args = @_;
#    my $data = $args{data} || croak "data arg not specified\n";
#    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
#    my $file = $args{file} || croak "file arg not specified\n";
#    
#    my $header = shift (@$data);
#    
#    my $shape = Geo::Shapelib -> new ({
#                                       Name => $file,
#                                       Shapetype => POINT,  #  point
#                                       FieldNames => $header,
#                                       FieldTypes => ['String', ('Double') x $#$header]
#                                       }
#                                      );
#    
#    my $i = 0;
#    foreach my $record (@$data) {
#        push @{$shape -> {Shapes}}, { Vertices => [[$record->[1],$record->[2],0,0]],
#                                      #ShapeId => $i,  #  for debug - normally set by code
#                                      #SHPType => POINT,
#                                      };
#        push @{$shape -> {ShapeRecords}}, $record;
#        $i++;
#        last if $i == 5;
#    }
#    $shape -> set_bounds;
#    #$shape -> dump;
#    $shape -> save;
#    $shape -> close;
#    
#}

sub write_table_html {
    my $self = shift;
    my %args = @_;
    my $data = $args{data} || croak "data arg not specified\n";
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
    my $file = $args{file} || croak "file arg not specified\n";

    my $qt = HTML::QuickTable -> new();

    my $table = $qt->render($args{data});

    open my $fh, '>', $file;

    eval {
        print {$fh} $table;
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    if ($fh -> close) {
        print "[COMMON] Write to file $file successful\n"
    }
    else {
        croak "[COMMON] Write to file $file failed, unable to close file\n"
    }

    return;
}

sub list2csv {  #  return a csv string from a list of values
    my $self = shift;
    my %args = (
        quote_char => q{'},
        sep_char   => q{,},
        @_,
    );

    my $csv_line = $args{csv_object}
      // $self->get_csv_object (@_);

    if ($csv_line->combine(@{$args{list}})) {
        return $csv_line->string;
    }
    else {
        croak "list2csv CSV combine() failed for some reason: "
              . $csv_line->error_input
              . ", line $.\n";
    }

    return;
}

#  return a list of values from a csv string
sub csv2list {
    my $self = shift;
    my %args = @_;

    my $csv_obj = $args{csv_object}
                // $self->get_csv_object (%args);

    my $string = $args{string};
    $string = $$string if ref $string;

    if ($csv_obj->parse($string)) {
        #print "STRING IS: $string";
        my @Fld = $csv_obj->fields;
        return wantarray ? @Fld : \@Fld;
    }
    else {
        $string //= '';
        if (length $string > 50) {
            $string = substr $string, 0, 50;
            $string .= '...';
        }
        local $. //= '';
        my $error_string = join (
            $EMPTY_STRING,
            "csv2list parse() failed\n",
            "String: $string\n",
            $csv_obj->error_diag,
            "\nline $.\nQuote Char is ",
            $csv_obj->quote_char,
            "\nsep char is ",
            $csv_obj->sep_char,
            "\n",
        );
        croak $error_string;
    }
}

#  csv_xs v0.41 will not ignore invalid args
#  - this is most annoying as we will have to update this list every time csv_xs is updated
my %valid_csv_args = (
    quote_char          => 1,
    escape_char         => 1,
    sep_char            => 1,
    eol                 => 1,
    always_quote        => 0,
    binary              => 0,
    keep_meta_info      => 0,
    allow_loose_quotes  => 0,
    allow_loose_escapes => 0,
    allow_whitespace    => 0,
    blank_is_undef      => 0,
    verbatim            => 0,
    empty_is_undef      => 1,
);

#  get a csv object to pass to the csv routines
sub get_csv_object {
    my $self = shift;
    my %args = (
        quote_char      => q{"},  #  set some defaults
        sep_char        => q{,},
        binary          => 1,
        blank_is_undef  => 1,
        quote_space     => 0,
        always_quote    => 0,
        #eol             => "\n",  #  comment out - use EOL on demand
        @_,
    );

    if (!exists $args{escape_char}) {
        $args{escape_char} //= $args{quote_char};
    }

    foreach my $arg (keys %args) {
        if (! exists $valid_csv_args{$arg}) {
            delete $args{$arg};
        }
    }

    my $csv = Text::CSV_XS->new({%args});

    croak Text::CSV_XS->error_diag ()
      if ! defined $csv;

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
        chop $el
    }

    return $el;
}


#############################################################
## 

#  convert an array to a hash, where the array values are keys and all the values are the same
#  empty arrays return an empty hash
#  if passed a hash, then it sends it straight back
#  croaks if passed a scalar
sub array_to_hash_keys_old {  #  clunky...
    my $self = shift;
    my %args = @_;
    exists $args{list} || croak "Argument 'list' not specified\n";
    my $list_ref = $args{list};

    if (! defined $list_ref) {
        return wantarray ? () : {};  #  return empty if $list_ref not defined
    }

    #  complain if it is a scalar
    croak "Argument 'list' is not an array ref - it is a scalar\n" if ! ref ($list_ref);

    my $value = $args{value};

    my %hash;
    if ((ref $list_ref) =~ /ARRAY/ && scalar @$list_ref) {  #  ref to array of non-zero length
        #  make a copy of the list so we don't wreck any lists used outside the function
        my @list = @{$list_ref};
        my $rebalance;
        if (scalar @list % 2) {  #  uneven non-zero count, better deal with it
            push @list, $value;  #  add a dud value to the end
            $rebalance = 1;
        }
        %hash = @list;
        shift @list;  #  get rid of the first key
        if ($rebalance) {  #  we don't want the dud value to appear as a key
            pop @list;
        }
        else {
            push @list, $value;  #  balance 
        }
        %hash = (%hash, @list);
    }
    elsif ((ref $list_ref) =~ /HASH/) {
        %hash = %$list_ref;
    }

    return wantarray ? %hash : \%hash;
}

#  make all the hash keys lowercase
sub lc_hash_keys {
    my $self = shift;
    my %args = @_;
    my $hash = $args{hash} || return {};  #  silently return an empty hash if none specified

    my $hash2 = {};  

    foreach my $key (keys %$hash) {
        $hash2->{lc($key)} = $hash->{$key};
    }

    return wantarray ? %$hash2 : $hash2;
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
    if ((ref $list_ref) =~ /ARRAY/ && scalar @$list_ref) {  #  ref to array of non-zero length
        @hash{@$list_ref} = ($value) x scalar @$list_ref;
    }
    elsif ((ref $list_ref) =~ /HASH/) {
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
    $list_ref = [values %$list_ref] if (ref $list_ref) =~ /HASH/;

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
    if ((ref $list_ref) =~ /ARRAY/ && scalar @$list_ref) {  #  ref to array of non-zero length
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

#  guess the field separator in a line
sub guess_field_separator {
    my $self = shift;
    my %args = @_;  #  these are passed straight through, except sep_char is overridden
    
    my $lines_to_use = $args{lines_to_use} // 10;

    my $string = $args{string};
    $string = $$string if ref $string;
    #  try a sequence of separators, starting with the default parameter
    my @separators = defined $ENV{BIODIVERSE_FIELD_SEPARATORS}  #  these should be globals set by use_base
                    ? @$ENV{BIODIVERSE_FIELD_SEPARATORS}
                    : (',', "\t", ';', q{ });
    my $eol = $args{eol} // $self->guess_eol(%args);

    my %sep_count;

    foreach my $sep (@separators) {
        next if ! length $string;
        #  skip if does not contain the separator
        #  - no point testing in this case
        next if ! ($string =~ /$sep/);  

        my $flds = eval {
            $self->csv2list (
                %args,
                sep_char => $sep,
                eol      => $eol,
            );
        };
        next if $EVAL_ERROR;  #  any errors mean that separator won't work

        if (scalar @$flds > 1) {  #  need two or more fields to result
            $sep_count{scalar @$flds} = $sep;
        }

    }

    my @str_arr = split $eol, $string;
    my $sep;

    if ($lines_to_use > 1 && @str_arr > 1) {  #  check the sep char works using subsequent lines
        %sep_count = reverse %sep_count;  #  should do it properly above
        my %checked;

      SEP:
        foreach my $sep (sort keys %sep_count) {
            #  check up to the first ten lines
            foreach my $string (@str_arr[1 .. min ($lines_to_use, $#str_arr)]) {
                my $flds = eval {
                    $self->csv2list (
                        %args,
                        sep_char => $sep,
                        eol      => $eol,
                        string   => $string,
                    );
                };
                if ($EVAL_ERROR) {  #  any errors mean that separator won't work
                    delete $checked{$sep};
                    next SEP;
                }
                $checked{$sep} //= scalar @$flds;
                if ($checked{$sep} != scalar @$flds) {
                    delete $checked{$sep};  #  count mismatch - remove
                    next SEP;
                }
            }
        }
        my @poss_chars = reverse sort {$checked{$a} <=> $checked{$b}} keys %checked;
        if (scalar @poss_chars == 1) {  #  only one option
            $sep = $poss_chars[0];
        }
        else {  #  get the one that matches
          CHAR:
            foreach my $char (@poss_chars) {
                if ($checked{$char} == $sep_count{$char}) {
                    $sep = $char;
                    last CHAR;
                }
            }
        }
    }
    else {
        #  now we sort the keys, take the highest and use it as the
        #  index to use from sep_count, thus giving us the most common
        #  sep_char
        my @sorted = reverse sort numerically keys %sep_count;
        $sep = (scalar @sorted && defined $sep_count{$sorted[0]})
            ? $sep_count{$sorted[0]}
            : $separators[0];  # default to first checked
    }

    $sep //= ',';

    #  need a better way of handling special chars - ord & chr?
    my $septext = ($sep =~ /\t/) ? '\t' : $sep;  
    say "[COMMON] Guessed field separator as '$septext'";

    return $sep;
}

sub guess_quote_char {
    my $self = shift;
    my %args = @_;  
    my $string = $args{string};
    $string = $$string if ref $string;
    #  try a sequence of separators, starting with the default parameter
    my @q_types = defined $ENV{BIODIVERSE_QUOTES}
                    ? @$ENV{BIODIVERSE_QUOTES}
                    : qw /" '/;
    my $eol = $args{eol} or $self->guess_eol(%args);
    #my @q_types = qw /' "/;

    my %q_count;

    foreach my $q (@q_types) {
        my @cracked = split ($q, $string);
        if ($#cracked and $#cracked % 2 == 0) {
            if (exists $q_count{$#cracked}) {  #  we have a tie so check for pairs
                my $prev_q = $q_count{$#cracked};
                #  override if we have e.g. "'...'" and $prev_q eq \'
                my $left  = $q . $prev_q;
                my $right = $prev_q . $q;
                my $l_count = () = $string =~ /$left/gs;
                my $r_count = () = $string =~ /$left.*?$right/gs;
                if ($l_count && $l_count == $r_count) {
                    $q_count{$#cracked} = $q;  
                }
            }
            else {
                $q_count{$#cracked} = $q;
            }
        }
    }

    #  now we sort the keys, take the highest and use it as the
    #  index to use from q_count, thus giving us the most common
    #  quotes character
    my @sorted = reverse sort numerically keys %q_count;
    my $q = (defined $sorted[0]) ? $q_count{$sorted[0]} : $q_types[0];
    say "[COMMON] Guessed quote char as $q";
    return $q;

    #  if we get this far then there is a quote issue to deal with
    #print "[COMMON] Could not guess quote char in $string.  Check the object QUOTES parameter and escape char in file\n";
    #return;
}

#  guess the end of line character in a string
#  returns undef if there are none of the usual suspects (\n, \r)
sub guess_eol {
    my $self = shift;
    my %args = @_;

    return if ! defined $args{string};

    my $string = $args{string};
    $string = $$string if ref ($string);

    my $pattern = $args{pattern} || qr/(?:\r\n|\n|\r)/;

    use feature 'unicode_strings';  #  needed?

    my %newlines;
    my @newlines_a = $string =~ /$pattern/g;
    foreach my $nl (@newlines_a) {
        $newlines{$nl}++;
    }

    my $eol;

    my @eols = keys %newlines;
    if (!scalar @eols) {
        $eol = "\n";
    }
    elsif (scalar @eols == 1) {
        $eol = $eols[0];
    }
    else {
        foreach my $e (@eols) {
            my $max_count = 0;
            if ($newlines{$e} > $max_count) {
                $eol = $e;
            }
        }
    }

    return $eol // "\n";
}


sub get_csv_object_using_guesswork {
    my $self = shift;
    my %args = @_;

    my $string = $args{string};
    my $fname  = $args{fname};
    #my $fh     = $args{fh};  #  should handle these

    my ($eol, $quote_char, $sep_char) = @args{qw/eol quote_char sep_char/};

    foreach ($eol, $quote_char, $sep_char) {
        if (($_ // '') eq 'guess') {
            $_ = undef;  # aliased, so applies to original
        }
    }

    if (defined $string && ref $string) {
        $string = $$string;
    }
    elsif (!defined $string) {
        croak "Both arguments 'string' and 'fname' not specified\n"
          if !defined $fname;

        my $first_char_set = '';

        #  read in a chunk of the file for guesswork
        my $fh2 = IO::File->new;
        $fh2->open ($fname, '<:via(File::BOM)');
        while (!$fh2->eof && length ($first_char_set) < 10000) {
            $first_char_set .= $fh2->getline;
        }
        $fh2->close;

        #  Strip trailing chars until we get a newline at the end.
        #  Not perfect for CSV if embedded newlines, but it's a start.
        if ($first_char_set =~ /\n/) {
            my $i = 0;
            while (length $first_char_set) {
                $i++;
                last if $first_char_set =~ /\n$/;
                #  Avoid infinite loops due to wide chars.
                #  Should fix it properly, though, since later stuff won't work.
                last if $i > 10000;
                chop $first_char_set;
            }
        }
        $string = $first_char_set;
    }

    $eol //= $self->guess_eol (string => $string);

    $quote_char //= $self->guess_quote_char (string => \$string, eol => $eol);
    #  if all else fails...
    $quote_char //= $self->get_param ('QUOTES');

    $sep_char //= $self->guess_field_separator (
        string     => $string,
        quote_char => $quote_char,
        eol        => $eol,
        lines_to_use => $args{lines_to_use},
    );

    my $csv_obj = $self->get_csv_object (
        %args,
        sep_char   => $sep_char,
        quote_char => $quote_char,
        eol        => $eol,
    );

    return $csv_obj;
}

sub get_next_line_set {
    my $self = shift;
    my %args = @_;

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
            say $csv->error_diag, ', Skipping line ', scalar @lines, ' of chunk';
            $csv->SetDiag (0);
        }
        if ($csv->eof) {
            #$self -> set_param (IMPORT_TOTAL_CHUNK_TEXT => $$chunk_count);
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

## a pass-through method
#sub get_metadata {
#    my $self = shift;
#    return $self->get_args(@_);
#}

sub get_metadata {
    my $self = shift;
    my %args = @_;

    croak 'get_metadata called in list context'
      if wantarray;
    
    my $use_cache = !$args{no_use_cache};
    my ($cache, $metadata);
    my $subname = $args{sub};
    
    #  Some metadata depends on given arguments,
    #  and these could change across the life of an object.
    if (blessed ($self) && $use_cache) {
        $cache = $self->get_cached_metadata;
        $metadata = $cache->{$subname};
    }

    if (!$metadata) {
        $metadata = $self->get_args(@_);

        if (not blessed $metadata) {
            croak "metadata for $args{sub} is not blessed (caller is $self)\n";  #  only when debugging
            #$metadata = $metadata_class->new ($metadata);
        }
        if ($use_cache) {
            $cache->{$subname} = $metadata;
        }
    }

    return $metadata;
}
    
sub get_cached_metadata {
    my $self = shift;

    my $cache
      = $self->get_cached_value_dor_set_default_aa ('METADATA_CACHE', {});
    return $cache;
}


#my $indices_wantarray = 0;
#  get the metadata for a subroutine
sub get_args {
    my $self = shift;
    my %args = @_;
    my $sub = $args{sub} || croak "sub not specified in get_args call\n";

    my $metadata_sub = "get_metadata_$sub";
    if (my ($package, $subname) = $sub =~ / ( (?:[^:]+ ::)+ ) (.+) /xms) {
        $metadata_sub = $package . 'get_metadata_' . $subname;
    }

    my $sub_args;

    #  use an eval to trap subs that don't allow the get_args option
    $sub_args = eval {$self->$metadata_sub (%args)};
    my $error = $EVAL_ERROR;

    if (blessed $error) {
        $error->rethrow;
    }
    elsif ($error) {
        my $msg = '';
        if (!$self->can($metadata_sub)) {
            $msg = "cannot call method $metadata_sub for object $self\n"
        }
        elsif (!$self->can($sub)) {
            $msg = "cannot call method $sub for object $self, and thus its metadata\n"
        }
        elsif (not blessed $self) {
            #  trap a very old caller style, should not exist any more
            $msg = "get_args called in non-OO manner - this is deprecated.\n"
        }
        croak $msg . $error;
    }

    $sub_args //= {};

#my $wa = wantarray;
#$indices_wantarray ++ if $wa;
#croak "get_args called in list context " if $wa;
    return wantarray ? %$sub_args : $sub_args;
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
    my $precision   = $args{precision} || [("%.10f") x scalar @$minima];
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
             (0 + $self->set_precision_aa ($value, $precision->[$depth])) <= $max;
             $value += $res) {

            my $val = 0 + $self -> set_precision_aa ($value, $precision->[$depth]);
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

sub get_surrounding_elements {  #  generate a list of values around a single point at a specified resolution
                              #  calculates the min and max and call getPossIndexValues
    my $self = shift;
    my %args = @_;
    my $coord_ref = $args{coord};
    my $resolutions = $args{resolutions};
    my $sep_char = $args{sep_char} || $self -> get_param('JOIN_CHAR') || $self -> get_param('JOIN_CHAR');
    my $distance = $args{distance} || 1; #  number of cells distance to check

    my (@minima, @maxima);
    #  precision snap them to make comparisons easier
    my $precision = $args{precision} || [('%.10f') x scalar @$coord_ref];

    foreach my $i (0..$#{$coord_ref}) {
        $minima[$i] = 0
            + $self->set_precision (
                precision => $precision->[$i],
                value     => $coord_ref->[$i] - ($resolutions->[$i] * $distance)
            );
        $maxima[$i] = 0
            + $self->set_precision (
                precision => $precision->[$i],
                value     => $coord_ref->[$i] + ($resolutions->[$i] * $distance)
            );
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
    my $list_reftype = reftype ($list);
    croak 'list arg must be a hash or array ref, not ' . ($list_reftype || 'undef') . "\n"
      if not (defined $list_reftype or $list_reftype =~ /ARRAY|HASH/);

    my @refs = ($list);  #  start with this
    my %flat_hash;

    foreach my $ref (@refs) {
        my $reftype = reftype $ref;
        if ($reftype eq 'ARRAY') {
            @flat_hash{@$ref} = (1) x scalar @$ref;
        }
        elsif ($reftype eq 'HASH') {
            foreach my $key (keys %$ref) {
                my $reftype2 = reftype ($ref->{$key});
                if (not $reftype2) {  #  not a ref, so must be a single level hash list
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
    croak "lists arg is not an array ref\n" if not (ref $lists) =~ /ARRAY/;

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
    my @state = $rand -> get_state;  #  make a copy - might reduce mem issues?
    croak "PRNG state not defined\n" if ! scalar @state;

    my $state = \@state;
    $self -> set_param (RAND_LAST_STATE => $state);

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
    my @state = $rand -> get_state;

    my $state = \@state;

    $self -> set_param (RAND_INIT_STATE => $state);

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
sub test_locale_numeric {
    my $self = shift;
    
    use warnings FATAL => qw ( numeric );
    
    my $x = 10.5;
    my $y = 10.1;
    my $x1 = sprintf ('%.10f', $x);
    my $y1 = sprintf ('%.10f', $y);
    $y1 = '10,1';
    my $correct_result = $x + $y;
    my $result = $x1 + $y1;
    
    use POSIX qw /locale_h/;
    my $locale = setlocale ('LC_NUMERIC');
    croak "$result != $correct_result, this could be a locale issue. "
            . "Current locale is $locale.\n"
        if $result != $correct_result;
    
    return 1;
}

use constant LOCALE_USES_COMMA_RADIX => (sprintf ('%.6f', 0.5) =~ /,/);

#  need to handle locale issues in string conversions using sprintf
sub set_precision {
    my $self = shift;
    my %args = @_;
    
    my $num = sprintf (($args{precision} // '%.10f'), $args{value});

    #  this is compiled away if false
    if (LOCALE_USES_COMMA_RADIX) {
        $num =~ s{,}{\.};  #  replace any comma with a decimal
    }

    return $num;
}

#  array args variant for more speed when needed
#  $_[0] is $self, and not used here
sub set_precision_aa {
    my $num = sprintf (($_[2] // '%.10f'), $_[1]);

    if (LOCALE_USES_COMMA_RADIX) {
        $num =~ s{,}{\.};  #  replace any comma with a decimal
    }

    #  explicit return takes time, and this is a heavy usage sub
    $num;
}

sub compare_lists_by_item {
    my $self = shift;
    my %args = @_;

    my $base_ref = $args{base_list_ref};
    my $comp_ref = $args{comp_list_ref};
    my $results  = $args{results_list_ref};

  COMP_BY_ITEM:
    foreach my $index (keys %$base_ref) {

        next COMP_BY_ITEM
            if    not defined $base_ref->{$index}
               or not exists  $comp_ref->{$index}
               or not defined $comp_ref->{$index};

        #  compare at 10 decimal place precision
        #  this also allows for serialisation which
        #     rounds the numbers to 15 decimals
        #  should really make the precision an option in the metadata
        my $base = $self->set_precision_aa ($base_ref->{$index}, '%.10f');
        my $comp = $self->set_precision_aa ($comp_ref->{$index}, '%.10f');

        #  make sure it gets a value of 0 if false
        my $increment = 0;
        if ($base > $comp) {
            $increment = 1;
        }

        #  for debug, but leave just in case
        #carp "$element, $op\n$comp\n$base  " . ($comp - $base) if $increment;  

        #   C is count passed
        #   Q is quantum, or number of comparisons
        #   P is the percentile rank amongst the valid comparisons,
        #      and has a range of [0,1]
        $results->{"C_$index"} += $increment;    
        $results->{"Q_$index"} ++;
        $results->{"P_$index"} =   $results->{"C_$index"}
                                 / $results->{"Q_$index"};

        #  track the number of ties
        if ($base == $comp) {
            $results->{"T_$index"} ++;
        }
    }
    
    return $results;
}


sub get_significance_from_comp_results {
    my $self = shift;
    my %args = @_;
    
    #  could alias this
    my $comp_list_ref = $args{comp_list_ref}
      // croak "comp_list_ref argument not specified\n";

    my $results_list_ref = $args{results_list_ref} // {};

    my (@sig_thresh_lo_1t, @sig_thresh_hi_1t, @sig_thresh_lo_2t, @sig_thresh_hi_2t);
    #  this is recalculated every call - cheap, but perhaps should be optimised or cached?
    if ($args{thresholds}) {
        @sig_thresh_lo_1t = sort {$a <=> $b} @{$args{thresholds}};
        @sig_thresh_hi_1t = map {1 - $_} @sig_thresh_lo_1t;
        @sig_thresh_lo_2t = map {$_ / 2} @sig_thresh_lo_1t;
        @sig_thresh_hi_2t = map {1 - ($_ / 2)} @sig_thresh_lo_1t;    
    }
    else {
        @sig_thresh_lo_1t = (0.01, 0.05);
        @sig_thresh_hi_1t = (0.99, 0.95);
        @sig_thresh_lo_2t = (0.005, 0.025);
        @sig_thresh_hi_2t = (0.995, 0.975);
    }

    foreach my $p_key (grep {$_ =~ /^P_/} keys %$comp_list_ref) {
        no autovivification;
        (my $index_name = $p_key) =~ s/^P_//;

        my $c_key = 'C_' . $index_name;
        my $t_key = 'T_' . $index_name;
        my $q_key = 'Q_' . $index_name;
        my $sig_1t_name = 'SIG_1TAIL_' . $index_name;
        my $sig_2t_name = 'SIG_2TAIL_' . $index_name;

        #  proportion observed higher than random
        my $p_high = $comp_list_ref->{$p_key};
        #  proportion observed lower than random 
        my $p_low
          =   ($comp_list_ref->{$c_key} + ($comp_list_ref->{$t_key} // 0))
            /  $comp_list_ref->{$q_key};

        $results_list_ref->{$sig_1t_name} = undef;
        $results_list_ref->{$sig_2t_name} = undef;
        
        if (my $sig_hi_1t = first {$p_high > $_} @sig_thresh_hi_1t) {
            $results_list_ref->{$sig_1t_name} = 1 - $sig_hi_1t;
            if (my $sig_hi_2t = first {$p_high > $_} @sig_thresh_hi_2t) {
                $results_list_ref->{$sig_2t_name} = 2 * (1 - $sig_hi_2t);
            }
        }
        elsif (my $sig_lo_1t = first {$p_low  < $_} @sig_thresh_lo_1t) {
            $results_list_ref->{$sig_1t_name} = -$sig_lo_1t;
            if (my $sig_lo_2t = first {$p_low  < $_} @sig_thresh_lo_2t) {
                $results_list_ref->{$sig_2t_name} = -2 * $sig_lo_2t;
            }
        }
    }

    return wantarray ? %$results_list_ref : $results_list_ref;
}

#  almost the same as get_significance_from_comp_results
sub get_sig_rank_threshold_from_comp_results {
    my $self = shift;
    my %args = @_;
    
    #  could alias this
    my $comp_list_ref = $args{comp_list_ref}
      // croak "comp_list_ref argument not specified\n";

    my $results_list_ref = $args{results_list_ref} // {};

    my (@sig_thresh_lo, @sig_thresh_hi);
    #  this is recalculated every call - cheap, but perhaps should be optimised or cached?
    if ($args{thresholds}) {
        @sig_thresh_lo = sort {$a <=> $b} @{$args{thresholds}};
        @sig_thresh_hi = map  {1 - $_}    @sig_thresh_lo;        
    }
    else {
        @sig_thresh_lo = (0.005, 0.01, 0.025, 0.05);
        @sig_thresh_hi = (0.995, 0.99, 0.975, 0.95);
    }

    foreach my $key (grep {$_ =~ /^C_/} keys %$comp_list_ref) {
        no autovivification;
        (my $index_name = $key) =~ s/^C_//;

        my $c_key = 'C_' . $index_name;
        my $t_key = 'T_' . $index_name;
        my $q_key = 'Q_' . $index_name;
        my $p_key = 'P_' . $index_name;

        #  proportion observed higher than random
        my $p_high = $comp_list_ref->{$p_key};
        #  proportion observed lower than random 
        my $p_low
          =   ($comp_list_ref->{$c_key} + ($comp_list_ref->{$t_key} // 0))
            /  $comp_list_ref->{$q_key};

        if (   my $sig_hi = first {$p_high > $_} @sig_thresh_hi) {
            $results_list_ref->{$index_name} = $sig_hi;
        }
        elsif (my $sig_lo = first {$p_low  < $_} @sig_thresh_lo) {
            $results_list_ref->{$index_name} = $sig_lo;
        }
        else {
            $results_list_ref->{$index_name} = undef;
        }
    }

    return wantarray ? %$results_list_ref : $results_list_ref;
}

sub get_sig_rank_from_comp_results {
    my $self = shift;
    my %args = @_;
    
    #  could alias this
    my $comp_list_ref = $args{comp_list_ref}
      // croak "comp_list_ref argument not specified\n";

    my $results_list_ref = $args{results_list_ref} // {};

    my ($sig_thresh_lo, $sig_thresh_hi);
    #  this is recalculated every call - cheap, but perhaps should be optimised or cached?
    if ($args{threshold}) {
        $sig_thresh_lo = $args{threshold};
        $sig_thresh_hi = 1 - $$sig_thresh_lo;
    }
    else {
        $sig_thresh_lo = 0.05;
        $sig_thresh_hi = 0.95;
    }

    foreach my $key (grep {$_ =~ /^C_/} keys %$comp_list_ref) {
        no autovivification;
        
        (my $index_name = $key) =~ s/^C_//;

        if (!defined $comp_list_ref->{$key}) {
            $results_list_ref->{$index_name} = undef;
            next;
        }

        #  proportion observed higher than random
        my $p_key  = 'P_' . $index_name;
        my $p_high = $comp_list_ref->{$p_key};

        if (   $p_high > $sig_thresh_hi) {
            $results_list_ref->{$index_name} = $p_high;
        }
        else {
            my $c_key = 'C_' . $index_name;
            my $t_key = 'T_' . $index_name;
            my $q_key = 'Q_' . $index_name;

            #  proportion observed lower than random 
            my $p_low
              =   ($comp_list_ref->{$c_key} + ($comp_list_ref->{$t_key} // 0))
                /  $comp_list_ref->{$q_key};

            $results_list_ref->{$index_name}
              = $p_low  < $sig_thresh_lo ? $p_low : undef;
        }
    }

    return wantarray ? %$results_list_ref : $results_list_ref;
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
#                           data => [Devel::Symdump -> arrays ($package)],
#                          },
#                hash  => {sigil => "%",
#                           data => [Devel::Symdump -> hashes ($package)],
#                          },
#                #scalars => {sigil => '$',
#                #           data => [Devel::Symdump -> hashes],
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

=item $self = $old_object -> clone;

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

Loads an object written using the Storable format.  Must satisfy the OUTSUFFIX parameter
for the object type being loaded.

=item  $self->write  (embed_source_data => 0, embed_matrix => 0,
                     embed_basedata => 0);

=item  $self->write2 (embed_source_data => 0, embed_matrix => 0,
                     embed_basedata => 0);

Dump the whole object to an xml file using the Storable package.
Get the filename prefix from argument OUTPFX, the parameter OUTPFX,
the parameter NAME or use BIODIVERSE if none of the others are defined.
The filename extension is taken from parameter OUTSUFFIX.
The embed arguments are used to
remove the references to the parent Biodiverse::BaseData object and
any Biodiverse::Matrix objects so they aren't included.  If these are set to
true then C<write()> calls C<write2()>, passing on all arguments.
C<embed_source_data> must be set for C<embed_basedata> and C<embed_matrix> to
have any effect.

=item  $self->load_xml_file (file => $filename);  DISABLED 

Loads an object written using the Data::DumpXML format.  Must satisfy the OUTSUFFIX parameter
for the object type being loaded.

=item  $self->write_xml  (embed_source_data => 0, embed_matrix => 0,
                     embed_basedata => 0);

=item  $self->write_xml2 (embed_source_data => 0, embed_matrix => 0,
                     embed_basedata => 0);

Dump the whole object to an xml file using Data::DumpXML.
Get the filename prefix from argument OUTPFX, the parameter OUTPFX,
the parameter NAME or use BIODIVERSE if none of the others are defined.
The filename extension is taken from parameter OUTSUFFIX_XML.
The embed arguments are used to
remove the references to the parent Biodiverse::BaseData object and
any Biodiverse::Matrix objects so they aren't included.  If these are set to
true then C<write_xml()> calls C<write_xml2()>, passing on all arguments.
C<embed_source_data> must be set for C<embed_basedata> and C<embed_matrix> to
have any effect.

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
