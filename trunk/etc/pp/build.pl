#  Build a Biodiverse executable
#  Need to take arguments, and also work for any script
#  Also should take an output folder argument.

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };


use PAR::Packer;
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

    my @fnames = ($lib_expat, 'libgcc_s_sjlj-1.dll', 'libstdc++-6.dll', get_dll_list());
    #my @fnames = ($lib_expat);  #  should only need this with recent versions of PAR
    for my $fname (@fnames) {
        my $source = Path::Class::file ($c_bin, $fname)->stringify;
        my $target = Path::Class::file ($out_folder, $fname)->stringify;

        copy ($source, $target) or die "Copy of $source failed: $!";
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
    my @icon_args = ("exe_update.pl", "--icon=$icon_file", $output_binary_fullpath);
    say join ' ', @icon_args;
    system @icon_args;
}


sub get_dll_list {
    # possibly only works for 64 bit
    my @dlls_needed = qw /
        libeay32__.dll
        libexpat-1__.dll
        libgcc_s_sjlj-1.dll
        libgif-6__.dll
        libiconv-2__.dll
        libjpeg-8__.dll
        liblzma-5__.dll
        libpng15-15__.dll
        libpq__.dll
        libstdc++-6.dll
        libtiff-5__.dll
        libxml2-2__.dll
        ssleay32__.dll
        zlib1__.dll
    /;

    return @dlls_needed;
}

