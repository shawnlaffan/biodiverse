use strict;
use warnings;
use 5.010;

use rlib;

use Biodiverse::Randomise;

my $file = ($ARGV[0] // 'randomisations.json');

say "Exporting to $file";
open my $fh, '>', $file or die $!;
my $json = Biodiverse::Randomise->get_metadata_as_json;
say {$fh} $json;
$fh->close;
