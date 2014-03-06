#!/usr/bin/perl

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}
use Test::More;

# Skip if doing a regular install
unless ( $ENV{AUTOMATED_TESTING} ) {
	plan( skip_all => "Author tests not required for installation" );
}

# Can we run the version tests
eval "use Test::MinimumVersion 0.007;";
if ( $@ ) {
	plan( skip_all => "Test::MinimumVersion not available" );
}

# Test minimum version
all_minimum_version_from_metayml_ok();
