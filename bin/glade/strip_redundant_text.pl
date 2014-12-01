
use 5.016;

use FindBin qw /$Bin/;

my $file = "$Bin/biodiverse.glade";

open(my $fh, '<', $file) or die "Cannot open $file";

local $/ = undef;
my $data = <$fh>;
$fh->close;
my $success = rename $file, "$file.bak";

die "Cannot rename $file" if !$success;

#  strip out any swapped cruft
my $count = $data =~ s/swapped="no"//g;
say $count;

#  we get excess placeholders creeping in
my $re_child_placeholder = qr {
    \s+<child>[\r\n]+
    \s+<placeholder/>[\r\n]+
    \s+</child>[\r\n]+
}x;

$count = $data =~ s/($re_child_placeholder)$re_child_placeholder+/$1/g;
say $count;

open(my $ofh, '>', $file) or die 'Cannot open output file';
print {$ofh} $data;
$ofh->close;

