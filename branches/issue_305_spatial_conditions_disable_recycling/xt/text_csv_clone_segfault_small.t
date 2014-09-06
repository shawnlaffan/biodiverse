#!/usr/bin/perl -w
use 5.010;
use strict;
use warnings;

use Text::CSV_XS;
use Clone;

$| = 1;

say 'Using Text::CSV_XS version ' . Text::CSV_XS->version;
say 'Using Clone version ' . $Clone::VERSION;

my $csv = Text::CSV_XS->new ({sep_char => ','});

say 'Cloning...';
my $clone1 = eval { Clone::clone $csv };
say 'Cloned before parsing';

$csv->parse ('a,b');
say 'Ran $csv->parse.';

say 'Cloning...';
my $clone2 = eval { Clone::clone $csv };
say 'Cloned after parsing';
