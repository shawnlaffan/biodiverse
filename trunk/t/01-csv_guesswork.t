#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use rlib;

use Test::More;
use Test::Exception;

use English qw(
    -no_match_vars
);

#  just need something that inherits the csv handlers
use Biodiverse::BaseStruct;


test_mixed_sep_chars();
test_sep_char();


done_testing();


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