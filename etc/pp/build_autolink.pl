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
use Path::Tiny qw /path/;
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
  [ 'script|s=s',     'The input script', { required => 1 } ],
  [ 'outfile|o=s',    'The name of the output binary or the directory where it will be written with a default name'],
  [ 'icon_file|i=s',  'The location of the icon file to use'],
  [ 'verbose|v!',     'Verbose building?', ],
  [ 'execute|x!',     'Execute the script to find dependencies?', {default => 1} ],
  #[ 'gd!',            'We are packing GD, get the relevant dlls'],
  [ '-', 'Any arguments after this will be passed through to pp'],
  [],
  [ 'help|?',       "print usage message and exit" ],
);

if ($opt->help) {
    print($usage->text);
    exit;
}

my $script     = $opt->script;
my $output_binary = $opt->outfile // cwd();
my $verbose    = $opt->verbose ? $opt->verbose : q{};
my $execute    = $opt->execute ? '-x' : q{};
#my $PACKING_GD = $opt->gd;
my @rest_of_pp_args = @ARGV;

die "Script file $script does not exist or is unreadable" if !-r $script;

my $out_folder = path ($output_binary);
if ($out_folder->is_dir) {
    $output_binary = path ($script)->basename ('.pl', qr/\.[^.]*$/);
    my $contents = path($script)->slurp;
    if ($contents =~ /^our\s+\$VERSION\s*=\s*['](.+)['];\s*$/m) {
        $output_binary .= "_$1";
    }
}
else {
    $out_folder = $out_folder->parent;
}

my $root_dir = Path::Class::file ($script)->dir->parent;

#  assume bin folder is at parent folder level
my $bin_folder = Path::Class::dir ($root_dir, 'bin');
say $bin_folder;
my $icon_file  = $opt->icon_file // Path::Class::file ($bin_folder, 'Biodiverse_icon.ico')->absolute;

my $script_fullname = path($script)->absolute;

if (!-d $out_folder) {
    die "$out_folder does not exist or is not a directory";
}

if ($OSNAME eq 'MSWin32' && $output_binary !~ /\.exe$/ ) {
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



