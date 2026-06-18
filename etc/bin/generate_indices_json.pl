use strict;
use warnings;
use 5.010;

use rlib;

use Biodiverse::Indices;

my $file = ($ARGV[0] // 'indices.json');

say "Exporting to $file";
open my $fh, '>', $file or die $!;
my $json = Biodiverse::Indices->get_calculation_metadata_as_json;
say {$fh} $json;
$fh->close;
