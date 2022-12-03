use strict;
use warnings;

local $| = 1;

use Test2::V0;
use rlib;

use English qw/-no_match_vars/;

use Text::CSV_XS;
use Biodiverse::Config;
use Biodiverse::TestHelpers qw /:utils/;

#  just need something that inherits the csv handlers
use Biodiverse::BaseStruct;


test_r_data_frame();
test_eol();
test_guesswork();
test_mixed_sep_chars();
test_sep_char();
test_escape_char();
test_unicode_filename();

done_testing();

sub test_unicode_filename {
    use utf8;
    use FindBin;
    my $fname = "$FindBin::Bin/data/años.txt";

    my $obj = Biodiverse::BaseStruct->new(name => 'x');

    #  A basic test, but we only care that it loads without exception here.
    #  There is more thorough testing in test_guesswork()
    my $csv = eval {
        $obj->get_csv_object_using_guesswork (fname => $fname);
    };
    is ($@, '', 'no exception when using unicode file name');
    is ($csv->sep_char, ',', 'got expected char');
}

sub test_eol {
    my $obj = Biodiverse::BaseStruct->new(name => 'x');

    my $eol;

    my $string = qq{a b,n m,k l\n"a b","n m","k l"};

    $eol = $obj->guess_eol(string => $string);

    is ($eol, "\n", 'got \n');
    
    $string = qq{a b,n m,k l\r\n"a b","n m","k l"\r\n};

    $eol = $obj->guess_eol(string => $string);

    is ($eol, "\r\n", 'got \r\n');

}

sub test_sep_char {
    my $obj = Biodiverse::BaseStruct->new(name => 'x');

    foreach my $sep (',', ' ') {
        my $string = join $sep, qw /a b c/;
    
        my $sep_char = $obj->guess_field_separator(string => $string);
    
        is ($sep_char, $sep, "field separator is '$sep'");
    }
}

sub test_escape_char {
    my $obj = Biodiverse::BaseStruct->new(name => 'x');

    my $sep = ',';
    my ($sep_char, $escape_char, $string);
    
    $string = qq{"h1","h2"\nr1c1,r1c2\n"col1","""col2"""\n};
    $sep_char = $obj->guess_field_separator(string => $string);
    is ($sep_char, $sep, qq{field separator is ',' when escape char is double quote char});
    $escape_char = $obj->guess_escape_char (string => $string);
    
    my $csv = Text::CSV_XS->new ({
        sep_char    => $sep_char,
        quote_char  => '"',
        escape_char => $escape_char,
    });
    my @fld_counts;
    foreach my $line (split "\n", $string) {
        my $status = $csv->parse ($line);
        my @flds = $csv->fields;
        push @fld_counts, scalar @flds;
    }
    is ([2,2,2], \@fld_counts, 'got expected field counts');
    
    #  now with \ as escape char
    $string = qq{"h1","h2"\nr1c1,r1c2\n"col1","[\\"col2\\"]"\n};
    $sep_char = $obj->guess_field_separator(string => $string);
    is ($sep_char, $sep, "field separator is , when escape char is \\");
    $escape_char = $obj->guess_escape_char (string => $string);
    
    $csv = Text::CSV_XS->new ({
        sep_char    => $sep_char,
        quote_char  => '"',
        escape_char => $escape_char,
    });
    @fld_counts = ();
    foreach my $line (split "\n", $string) {
        my $status = $csv->parse ($line);
        my @flds  = $csv->fields;
        push @fld_counts, scalar @flds;
    }
    is ([2,2,2], \@fld_counts, 'got expected field counts');
    
    $string = qq{"h1","h2"\nr1c1,r1c2\n"col1","col2\\\\"""\n};
    #$sep_char = $obj->guess_field_separator(string => $string);
    #is ($sep_char, $sep, "field separator is , when escape char is \\");
    $escape_char = $obj->guess_escape_char (string => $string);
    is ($escape_char, '"', 'got quote char of " when \\ is escaped');
}

sub test_mixed_sep_chars {
    my $obj = Biodiverse::BaseStruct->new(name => 'x');

    my $sep_char;

    #  comma is sep, but we have spaces
    my $string = qq{a b,n m,k l\n"a b","n m","k l"};

    $sep_char = $obj->guess_field_separator(string => $string, quote_char => q{"});

    is ($sep_char, ',', "got a comma");
    
    $string = qq{a b,n m,k l\na b,n m,k l};

    $sep_char = $obj->guess_field_separator(string => $string, quote_char => q{"});

    is ($sep_char, ' ', "got a space when there are more spaces than commas");

}

sub test_guesswork {
    my $obj = Biodiverse::BaseStruct->new(name => 'x');

    my $csv_got;
    my $csv_exp = $obj->get_csv_object(sep_char => ',', quote_char => '"', eol => "\n");

    #  comma is sep, but we have spaces
    my $string = qq{a b,n m,k l\n"a b","n m","k l"};

    $csv_got = $obj->get_csv_object_using_guesswork(string => $string);
    is ($csv_got, $csv_exp, 'get_csv_object_using_guesswork using string');

    my $filename = get_temp_file_path('biodiverseXXXX');
    open(my $fh, '>', $filename) or die "test_guesswork: Cannot open $filename\n";
    #  add some lines
    say {$fh} $string;
    say {$fh} $string;
    say {$fh} $string;
    $fh->close;

    $csv_got = $obj->get_csv_object_using_guesswork(fname => $filename);
    is ($csv_got, $csv_exp, 'get_csv_object_using_guesswork using file');

    $csv_exp = $obj->get_csv_object_using_guesswork(
        sep_char   => 'guess',
        quote_char => 'guess',
        eol        => 'guess',
        string     => $string,
    );
    is ($csv_got, $csv_exp, 'get_csv_object_using_guesswork using string and explicit guess args');

}

#  header has one less column than data
sub test_r_data_frame {
    my $obj = Biodiverse::BaseStruct->new(name => 'x');

    my $csv_got;
    my $csv_exp = $obj->get_csv_object(sep_char => ' ', quote_char => '"', eol => "\n");

    #  space is sep, but we have some commas
    my $string = qq{b,2 c,3 d,4\na,1 b2 c,3 d,4\na,1 b2 c,3 d,4\na1 b2 c3 d4\n};

    $csv_got = $obj->get_csv_object_using_guesswork (string => $string);

    is ($csv_got, $csv_exp, 'guesswork with r data frame style file');
}
