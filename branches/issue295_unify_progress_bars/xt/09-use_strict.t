use Test::Strict;
use Test::More;

use strict;
use warnings;

local $| = 1;
use File::Spec;

use English qw { -no_match_vars };

#  seems to not test properly under Win32
#  finds too many false positives
if ($OSNAME eq 'MSWin32') {
    plan skip_all => "Skipping use_strict tests due to false positives on $OSNAME";
}

all_perl_files_ok( ); # Syntax ok and use strict;

#
#use FindBin qw { $Bin };
#my $bin_path = File::Spec->catfile ($Bin, qw{..}, 'bin');
#my $lib_path = File::Spec->catfile ($Bin, qw{..}, 'lib');
#my $t_path   = File::Spec->catfile ($Bin, qw{..}, 't');
#
#all_perl_files_ok( $bin_path, $lib_path, $t_path ); # Syntax ok and use strict;
