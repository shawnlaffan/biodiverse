#  Build a Biodiverse related executable

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };


use PAR::Packer;
use Module::ScanDeps 1.13;
BEGIN {
    eval 'use Win32::Exe' if $OSNAME eq 'MSWin32';
}

use Config;
use File::Copy;
use Path::Class;
use Cwd;
use File::Basename;

use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'script|s=s',             'The input script', { required => 1 } ],
  [ 'out_folder|out_dir|o=s', 'The output directory where the binary will be written'],
  [ 'icon_file|i=s',          'The location of the icon file to use'],
  [ 'verbose|v!',             'Verbose building?', ],
  [ 'execute|x!',             'Execute the script to find dependencies?', {default => 1} ],
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
my $execute    = $opt->execute ? ' -x' : q{};

die "Script file $script does not exist or is unreadable" if !-r $script;


my $root_dir = Path::Class::file ($script)->dir->parent;

#  assume bin folder is at parent folder level
my $bin_folder = Path::Class::dir ($root_dir, 'bin');
my $icon_file  = $opt->icon_file // Path::Class::file ($bin_folder, 'Biodiverse_icon.ico')->absolute;

my $perlpath     = $Config{perlpath};
my $bits         = $Config{archname} =~ /x(86_64|64)/ ? 64 : 32;
my $using_64_bit = $bits == 64;

my $script_fullname = Path::Class::file($script)->absolute;

my $output_binary = basename ($script_fullname, '.pl', qr/\.[^.]*$/);
$output_binary .= "_x$bits";


if (!-d $out_folder) {
    die "$out_folder does not exist or is not a directory";
}



if ($OSNAME eq 'MSWin32') {
    
    #  needed for Windows exes
    my $lib_expat = $using_64_bit  ? 'libexpat-1__.dll' : 'libexpat-1_.dll';

    my $strawberry_base = Path::Class::dir ($perlpath)->parent->parent->parent;  #  clunky
    my $c_bin = Path::Class::dir($strawberry_base, 'c', 'bin');

    #my @fnames = ($lib_expat, 'libgcc_s_sjlj-1.dll', 'libstdc++-6.dll', get_dll_list($c_bin));
    my @fnames = get_dll_list($c_bin);
    #my @fnames = ($lib_expat);  #  should only need this with recent versions of PAR
    for my $fname (@fnames) {
        my $source = Path::Class::file ($fname)->stringify;
        my $fbase  = Path::Class::file ($fname)->basename;
        my $target = Path::Class::file ($out_folder, $fbase)->stringify;

        copy ($source, $target) or die "Copy of $source to $target failed: $!";
        say "Copied $source to $target";
    }

    $output_binary .= '.exe';
}


#  clunky - should hunt for glade use in script?  
my $glade_arg = q{};
if ($script =~ 'BiodiverseGUI.pl') {
    my $glade_folder = Path::Class::dir ($bin_folder, 'glade')->absolute;
    $glade_arg = qq{-a "$glade_folder;glade"};
}

my $icon_file_base = basename ($icon_file);
my $icon_file_arg  = qq{-a "$icon_file;$icon_file_base"};

my $output_binary_fullpath = Path::Class::file ($out_folder, $output_binary)->absolute;

$ENV{BDV_PP_BUILDING}              = 1;
$ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;

my $cmd = "pp$verbose -B -z 9 $glade_arg $icon_file_arg $execute -o $output_binary_fullpath $script_fullname";
#  array form is better, but needs the args to be in list form, e.g. $glade_arg, $icon_file_arg
#  also need to filter empty args out of the list
#my @cmd = (
#    'pp',
#    #$verbose,
#    '-B',
#    '-z',
#    9,
#    $glade_arg,
#    $icon_file_arg,
#    $execute,
#    '-o',
#    $output_binary_fullpath,
#    $script_fullname,
#);
#if ($verbose) {
#    splice @cmd, 1, 0, $verbose;
#}
#say join ' ', @cmd;

say $cmd;
system $cmd;

if ($OSNAME eq 'MSWin32' && $icon_file) {
    my @embed_icon_args = ("exe_update.pl", "--icon=$icon_file", $output_binary_fullpath);
    say join ' ', @embed_icon_args;
    system @embed_icon_args;
}


sub get_dll_list {
    my $folder = shift;

    my @dll_pfx = qw /
        libeay   libexpat libgcc   libgif libiconv
        libjpeg  liblzma  libpng   libpq  libstdc
        libtiff  libxml2  ssleay32 zlib1
    /;

    my @files = glob "$folder\\*.dll";
    my $regstr   = join '|', @dll_pfx;
    my $regmatch = qr /$regstr/;
    my @dll_files = grep {$_ =~ $regmatch} @files;

    say $folder;
    say join ' ', @files;
    say $regmatch;
    say 'DLL files are: ', join ' ', @dll_files;

    return @dll_files;
}

