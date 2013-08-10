#  Build a Biodiverse executable
#  Need to take arguments, and also work for any script
#  Also should take an output folder argument.

use 5.010;
use Config;
use File::Copy;
use Path::Class;

my $perlpath     = $Config{perlpath};
my $bits         = $Config{archname} =~ /x86/ ? 32 : 64;
my $using_64_bit = $bits == 64;

my $lib_expat = $using_64_bit  ? 'libexpat-1__.dll' : 'libexpat-1_.dll';

#  needed for Windows exes
my $strawberry_base = Path::Class::dir ($perlpath)->parent->parent->parent;  #  clunky
$c_bin = Path::Class::dir($strawberry_base, 'c', 'bin');

for my $fname ($lib_expat, 'libgcc_s_sjlj-1.dll', 'libstdc++-6.dll') {
    my $source = Path::Class::file ($c_bin, $fname);
    $source = $source->stringify;
    #say -e $source;
    copy ($source, $fname) or die "Copy of $source failed: $!";
    say "Copied $source to fname";
}

$ENV{BDV_PP_BUILDING}              = 1;
$ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;
my $verbosity = '-v';

system "pp $verbosity -B -z 9 -i Biodiverse_icon.ico -a glade -a Biodiverse_icon.ico -x -o BiodiverseGUI_x$bits.exe BiodiverseGUI.pl";
