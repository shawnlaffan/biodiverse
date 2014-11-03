use Test::NoTabs;

use strict;
use warnings;

local $| = 1;
use File::Spec;

#use FindBin qw { $Bin };
#
#my $bin_path = File::Spec->catfile ($Bin, qw{..}, 'bin');
#my $lib_path = File::Spec->catfile ($Bin, qw{..}, 'lib');
#
#all_perl_files_ok( $bin_path, $lib_path );

all_perl_files_ok( 'bin', 'lib', 't', 'xt' );
