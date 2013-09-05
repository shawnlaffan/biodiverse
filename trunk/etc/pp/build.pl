#  Build a Biodiverse executable
#  Need to take arguments, and also work for any script
#  Also should take an output folder argument.

use 5.010;
use Config;
use File::Copy;
use Path::Class;
use English qw { -no_match_vars };
use Cwd;
use File::Basename;

use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'script=s',   'The input script', { required => 1 } ],
  [ 'out_folder|out_dir=s',  'The output directory where the binary will be written'],
  [ 'verbose|v!',            'Verbose building?', ],
  [],
  [ 'help',       "print usage message and exit" ],
);
 
if ($opt->help) {
    print($usage->text);
    exit;
}

my $script     = $opt->script;
my $out_folder = $opt->out_folder // cwd();
my $verbose    = $opt->verbose ? ' -v' : q{};

my $perlpath     = $Config{perlpath};
my $bits         = $Config{archname} =~ /x(?:86_)?64/ ? 64 : 32;
my $using_64_bit = $bits == 64;

my $script_fullname = Path::Class::file($script)->absolute;

my $output_binary = basename ($script_fullname, '.pl', qr/\.[^.]*$/);
$output_binary .= "_x$bits";

if ($OSNAME eq 'MSWin32') {
    #  needed for Windows exes
    my $lib_expat = $using_64_bit  ? 'libexpat-1__.dll' : 'libexpat-1_.dll';

    my $strawberry_base = Path::Class::dir ($perlpath)->parent->parent->parent;  #  clunky
    $c_bin = Path::Class::dir($strawberry_base, 'c', 'bin');

    for my $fname ($lib_expat, 'libgcc_s_sjlj-1.dll', 'libstdc++-6.dll') {
        my $source = Path::Class::file ($c_bin, $fname)->stringify;
        my $target = Path::Class::file ($out_folder, $fname)->stringify;

        copy ($source, $target) or die "Copy of $source failed: $!";
        say "Copied $source to $target";
    }

    $output_binary .= '.exe';
}

my $root_dir = Path::Class::file ($script)->dir->parent;

#  assume bin folder is at parent folder level
my $bin_folder = Path::Class::dir ($root_dir, 'bin');

my $icon_file  = Path::Class::file ($bin_folder, 'Biodiverse_icon.ico')->absolute;

#  clunky - should hunt for glade use in script?  
my $glade_arg = q{};
if ($script =~ 'BiodiverseGUI.pl') {
    my $glade_folder = Path::Class::dir ($bin_folder, 'glade')->absolute;
    $glade_arg = qq{-a "$glade_folder;glade"};
    #$glade_arg = "-a glade";
}

my $icon_file_base = basename ($icon_file);
my $icon_file_arg  = qq{-a "$icon_file;$icon_file_base"};

my $output_binary_fullpath = Path::Class::file ($out_folder, $output_binary)->absolute;

$ENV{BDV_PP_BUILDING}              = 1;
$ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;

my $cmd = "pp$verbose -B -z 9 -i $icon_file $glade_arg $icon_file_arg -x -o $output_binary_fullpath $script_fullname";

say $cmd;
system $cmd;
