package Biodiverse::Config::PARModules;
use strict;
use warnings;
use 5.016;

our $VERSION = '4.99_003';


use Carp;

use utf8;
say 'Building pp file';
say "using $0";
use File::BOM qw / :subs /;          #  we need File::BOM.
open my $fh, '<:via(File::BOM)', $0  #  just read ourselves
    or croak "Cannot open $0 via File::BOM\n";
$fh->close;

#  more File::BOM issues
require encoding;

#  exercise the unicode regexp matching - needed for the spatial conditions
use feature 'unicode_strings';
my $string = "sp_self_only () and \N{WHITE SMILING FACE}";
$string =~ /\bsp_self_only\b/;

#  load extra encode pages, except the extended ones (for now)
#  https://metacpan.org/pod/distribution/Encode/lib/Encode/Supported.pod#CJK:-Chinese-Japanese-Korean-Multibyte
use Encode::CN;
use Encode::JP;
use Encode::KR;
use Encode::TW;

#  Big stuff needs loading (poss not any more with PAR>1.08)
use Math::BigInt;

use Alien::gdal ();
use Alien::geos::af ();
use Alien::proj ();
use Alien::sqlite ();
#eval 'use Alien::spatialite';  #  might not have this one
#eval 'use Alien::freexl';      #  might not have this one

#  these are here for PAR purposes to ensure they get packed
#  Spreadsheet::Read calls them as needed
#  (not sure we need all of them, though)
use Spreadsheet::ParseODS 0.27;
use Spreadsheet::ReadSXC;
use Spreadsheet::ParseExcel;
use Spreadsheet::ParseXLSX;
use PerlIO::gzip;  #  used by ParseODS
# Excel::ValueReader::XLSX
use Excel::ValueReader::XLSX;
use Excel::ValueReader::XLSX::Backend;
use Excel::ValueReader::XLSX::Backend::Regex;
use Archive::Zip

#  GUI needs this for help,
#  so don't trigger for engine-only
eval 'use IO::Socket::SSL';

1;



=head1 NAME

Biodiverse::Config::PARModules


=head1 DESCRIPTION

Loads extra modules when using PAR::Packer.

Not for direct use.

=head1 SYNOPSIS


=head1 AUTHOR

Shawn Laffan

=head1 License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut

