#  Build a Biodiverse related executable

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };

#  make sure we get all the Strawberry libs
#  and pack Gtk3 libs
use PAR::Packer 1.036;    
use Module::ScanDeps 1.23;
BEGIN {
    eval 'use Win32::Exe' if $OSNAME eq 'MSWin32';
}

use App::PP::Autolink 2.07;

use Config;
use File::Copy;
use Path::Class;
use Cwd;
use File::Basename;
use File::Find::Rule;

use FindBin qw /$Bin/;

use 5.020;
use warnings;
use strict;
use Carp;

use Data::Dump       qw/ dd /;
use File::Which      qw( which );
use Capture::Tiny    qw/ capture /;
use List::Util       qw( uniq );
use File::Find::Rule qw/ rule find /;
use Path::Tiny       qw/ path /;
use Module::ScanDeps;

use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'script|s=s',             'The input script', { required => 1 } ],
  [ 'out_folder|out_dir|o=s', 'The output directory where the binary will be written'],
  [ 'icon_file|i=s',          'The location of the icon file to use'],
  [ 'verbose|v!',             'Verbose building?', ],
  [ 'execute|x!',             'Execute the script to find dependencies?', {default => 1} ],
  #[ 'gd!',                    'We are packing GD, get the relevant dlls'],
  [ '-', 'Any arguments after this will be passed through to pp'],
  [],
  [ 'help|?',       "print usage message and exit" ],
);

if ($opt->help) {
    print($usage->text);
    exit;
}

my $script     = $opt->script;
my $out_folder = $opt->out_folder // cwd();
my $verbose    = $opt->verbose ? $opt->verbose : q{};
my $execute    = $opt->execute ? '-x' : q{};
#my $PACKING_GD = $opt->gd;
my @rest_of_pp_args = @ARGV;

die "Script file $script does not exist or is unreadable" if !-r $script;

my $RE_DLL_EXT = qr/\.dll/i;

my $root_dir = Path::Class::file ($script)->dir->parent;

#  assume bin folder is at parent folder level
my $bin_folder = Path::Class::dir ($root_dir, 'bin');
say $bin_folder;
my $icon_file  = $opt->icon_file // Path::Class::file ($bin_folder, 'Biodiverse_icon.ico')->absolute;
#$icon_file = undef;  #  DEBUG

my $perlpath     = $EXECUTABLE_NAME;
my $bits         = $Config{archname} =~ /x(86_64|64)/ ? 64 : 32;
my $using_64_bit = $bits == 64;

my $script_fullname = Path::Class::file($script)->absolute;

my $output_binary = basename ($script_fullname, '.pl', qr/\.[^.]*$/);
#$output_binary .= "_x$bits";


if (!-d $out_folder) {
    die "$out_folder does not exist or is not a directory";
}


my @links;

if ($OSNAME eq 'MSWin32') {

    #@links = map {('--link' => $_)}
    #    get_autolink_list ($script_fullname);

    $output_binary .= '.exe';
}


#  clunky - should hunt for Gtk3 use in script?
my @ui_arg = ();
my @gtk_path_arg = ();
my @linkers;
if ($script =~ 'BiodiverseGUI.pl') {
    my $ui_dir = Path::Class::dir ($bin_folder, 'ui')->absolute;
    @ui_arg = ('-a', "$ui_dir;ui");
}

my $icon_file_base = $icon_file ? basename ($icon_file) : '';
my @icon_file_arg  = $icon_file ? ('-a', "$icon_file;$icon_file_base") : ();

my $output_binary_fullpath = Path::Class::file ($out_folder, $output_binary)->absolute;

$ENV{BDV_PP_BUILDING}              = 1;
$ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;
$ENV{BD_NO_GUI_DEV_WARN}           = 1;

my @cmd = (
    #$^X,
    #"$Bin/pp_autolink.pl",
    'pp_autolink',
    @linkers,
    ($verbose ? '-v' : ()),
    '-B',
    '-z',
    9,
    @ui_arg,
    @gtk_path_arg,
    @icon_file_arg,
    $execute,
    @rest_of_pp_args,
    '-o',
    $output_binary_fullpath,
    $script_fullname,
);
#if ($verbose) {
#    splice @cmd, 1, 0, $verbose;
#}


say "\nCOMMAND TO RUN:\n" . join ' ', @cmd;

system @cmd;

#  skip for now - exe_update.pl does not play nicely with PAR executables
if (0 && $OSNAME eq 'MSWin32' && $icon_file) {
    
    ###  ADD SOME OTHER OPTIONS:
    ###  Comments        CompanyName     FileDescription FileVersion
    #### InternalName    LegalCopyright  LegalTrademarks OriginalFilename
    #### ProductName     ProductVersion
    #perl -e "use Win32::Exe; $exe = Win32::Exe->new('myapp.exe'); $exe->set_single_group_icon('myicon.ico'); $exe->write;"
    my @embed_icon_args = ("exe_update.pl", "--icon=$icon_file", $output_binary_fullpath);
    say join ' ', @embed_icon_args;
    system @embed_icon_args;
}



