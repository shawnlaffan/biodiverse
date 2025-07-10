package Biodiverse::Common::CSV;
use 5.036;
use strict;
use warnings;

our $VERSION = '4.99_006';

use Carp qw /croak/;
use English ( -no_match_vars );

my $EMPTY_STRING = q{};

sub list2csv {  #  return a csv string from a list of values
    my $self = shift;
    my %args = @_;

    my $csv_line = $args{csv_object}
        // $self->get_csv_object (
        quote_char => q{'},
        sep_char   => q{,},
        @_
    );

    return $csv_line->string
        if $csv_line->combine(@{$args{list}});

    croak "list2csv CSV combine() failed for some reason: "
        . ($csv_line->error_input // '')
        . ", line "
        . ($. // '')
        . "\n";

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
        # my @Fld = $csv_obj->fields;
        return wantarray ? ($csv_obj->fields) : [$csv_obj->fields];
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
    my $separator;

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
            $separator = $poss_chars[0];
        }
        else {  #  get the one that matches
            CHAR:
            foreach my $char (@poss_chars) {
                if ($checked{$char} == $sep_count{$char}) {
                    $separator = $char;
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
        $separator = (scalar @sorted && defined $sep_count{$sorted[0]})
            ? $sep_count{$sorted[0]}
            : $separators[0];  # default to first checked
    }

    $separator //= ',';

    #  need a better way of handling special chars - ord & chr?
    my $septext = ($separator =~ /\t/) ? '\t' : $separator;
    say "[COMMON] Guessed field separator as '$septext'";

    return $separator;
}

sub guess_escape_char {
    my $self = shift;
    my %args = @_;

    my $string = $args{string};
    $string = $$string if ref $string;

    my $quote_char = $args{quotes} // $self->guess_quote_char (@_);

    my $has_backslash = $string =~ /(\\+)$quote_char/s;
    #  even number of backslashes are self-escaping
    if (not ((length ($1 // '')) % 2)) {
        $has_backslash = 0;
    }
    return $has_backslash ? '\\' : $quote_char;
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
        my $fh2 = $self->get_file_handle (file_name => $fname, use_bom => 1);
        my $line_count = 0;
        #  get first 11 lines or 10,000 characters
        #  as some ALA files have 19,000 chars in the header line alone
        while (!$fh2->eof and ($line_count < 11 or length $first_char_set < 10000)) {
            $first_char_set .= $fh2->getline;
            $line_count++;
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

    $quote_char //= $self->guess_quote_char (string => $string, eol => $eol);
    #  if all else fails...
    $quote_char //= $self->get_param ('QUOTES');

    my $escape_char = $self->guess_escape_char (string => $string, quote_char => $quote_char);
    $escape_char //= $quote_char;

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
        escape_char => $escape_char,
    );

    return $csv_obj;
}

sub numerically {$a <=> $b};

sub min {$_[0] < $_[1] ? $_[0] : $_[1]};
sub max {$_[0] > $_[1] ? $_[0] : $_[1]};

1;
