#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;
use rlib;

use Test::More;
use Test::Exception;

use English qw/-no_match_vars/;

use Text::CSV_XS;
use Biodiverse::TestHelpers qw /:utils/;

#  just need something that inherits the csv handlers
use Biodiverse::BaseStruct;

test_r_data_frame();
test_eol();
test_guesswork();
test_mixed_sep_chars();
test_sep_char();


done_testing();


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
    is_deeply ($csv_got, $csv_exp, 'get_csv_object_using_guesswork using string');

    my $filename = get_temp_file_path('biodiverseXXXX');
    open(my $fh, '>', $filename) or die "test_guesswork: Cannot open $filename\n";
    #  add some lines
    say {$fh} $string;
    say {$fh} $string;
    say {$fh} $string;
    $fh->close;

    $csv_got = $obj->get_csv_object_using_guesswork(fname => $filename);
    is_deeply ($csv_got, $csv_exp, 'get_csv_object_using_guesswork using file');

    $csv_exp = $obj->get_csv_object_using_guesswork(
        sep_char   => 'guess',
        quote_char => 'guess',
        eol        => 'guess',
        string     => $string,
    );
    is_deeply ($csv_got, $csv_exp, 'get_csv_object_using_guesswork using string and explicit guess args');

}

#  header has one less column than data
sub test_r_data_frame {
    my $obj = Biodiverse::BaseStruct->new(name => 'x');

    my $csv_got;
    my $csv_exp = $obj->get_csv_object(sep_char => ' ', quote_char => '"', eol => "\n");

    #  space is sep, but we have some commas
    my $string = qq{b,2 c,3 d,4\na,1 b2 c,3 d,4\na,1 b2 c,3 d,4\na1 b2 c3 d4\n};

    $csv_got = $obj->get_csv_object_using_guesswork (string => $string);

    is_deeply ($csv_got, $csv_exp, 'guesswork with r data frame style file');
}
