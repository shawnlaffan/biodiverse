#  Build a Biodiverse related executable

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };

#  make sure we get all the Strawberry libs
#  and pack Gtk2 libs
use PAR::Packer 1.036;    
use Module::ScanDeps 1.23;
BEGIN {
    eval 'use Win32::Exe' if $OSNAME eq 'MSWin32';
}

use Config;
use File::Copy;
use Path::Class;
use Cwd;
use File::Basename;
use File::Find::Rule;


use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'script|s=s',             'The input script', { required => 1 } ],
  [ 'out_folder|out_dir|o=s', 'The output directory where the binary will be written'],
  [ 'icon_file|i=s',          'The location of the icon file to use'],
  [ 'verbose|v!',             'Verbose building?', ],
  [ 'execute|x!',             'Execute the script to find dependencies?', {default => 1} ],
  [ 'gd!',                    'We are packing GD, get the relevant dlls'],
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
my $PACKING_GD = $opt->gd;
my @rest_of_pp_args = @ARGV;

die "Script file $script does not exist or is unreadable" if !-r $script;


my $root_dir = Path::Class::file ($script)->dir->parent;

#  assume bin folder is at parent folder level
my $bin_folder = Path::Class::dir ($root_dir, 'bin');
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

    my $strawberry_base = Path::Class::dir ($perlpath)->parent->parent->parent;  #  clunky
    my $c_bin = Path::Class::dir($strawberry_base, 'c', 'bin');

    my @fnames = get_dll_list($c_bin);
    #  clunky - should have a gtk flag like for GD
    if ($script =~ 'BiodiverseGUI.pl') {
        push @fnames, get_sis_gtk_dll_list();
    }

    for my $fname (@fnames) {
        my $source = Path::Class::file ($fname)->stringify;
        my $fbase  = Path::Class::file ($fname)->basename;
        my $target = Path::Class::file ($out_folder, $fbase)->stringify;

        #copy ($source, $target) or die "Copy of $source to $target failed: $!";
        #say "Copied $source to $target";
        
        push @links, '--link', $source;
    }

    $output_binary .= '.exe';
}


#  clunky - should hunt for Gtk2 use in script?  
my @ui_arg = ();
my @gtk_path_arg = ();
if ($script =~ 'BiodiverseGUI.pl') {
    my $ui_dir = Path::Class::dir ($bin_folder, 'ui')->absolute;
    @ui_arg = ('-a', "$ui_dir;ui");
    
    #  get the Gtk2 stuff
    my $base = Path::Class::file($EXECUTABLE_NAME)
        ->parent
        ->parent
        ->subdir('site/lib/auto/Gtk2');
    foreach my $subdir (qw /share etc lib/) {
        my $source_dir = Path::Class::dir ($base, $subdir);
        my $dest_dir   = Path::Class::dir ('lib/auto/Gtk2', $subdir);
        push @gtk_path_arg, ('-a', "$source_dir;$dest_dir")
    }
}

my $icon_file_base = $icon_file ? basename ($icon_file) : '';
my @icon_file_arg  = $icon_file ? ('-a', "$icon_file;$icon_file_base") : ();


my $output_binary_fullpath = Path::Class::file ($out_folder, $output_binary)->absolute;

$ENV{BDV_PP_BUILDING}              = 1;
$ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;

my @cmd = (
    'pp',
    #$verbose,
    '-u',
    '-B',
    '-z',
    9,
    @ui_arg,
    @gtk_path_arg,
    @icon_file_arg,
    $execute,
    @links,
    @rest_of_pp_args,
    '-o',
    $output_binary_fullpath,
    $script_fullname,
);
if ($verbose) {
    splice @cmd, 1, 0, $verbose;
}


say join ' ', "\nCOMMAND TO RUN:\n", @cmd;

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


sub get_dll_list {
    my $folder = shift;

    #  we did used to get libgcc and libstd, but PAR::Packer 1.022 onwards includes them
    my @dll_pfx = qw /
        libeay   libexpat libgif   libiconv
        libjpeg  liblzma  libpng   libpq 
        libtiff  libxml2  ssleay32 zlib1
    /;
    if ($PACKING_GD) {
        my @extras = qw /
            libfreetype libgd libXpm
        /;
        push @dll_pfx, @extras;
    }

    #  maybe we should just pack the lot?
    my @files     = glob "$folder\\*.dll";
    my $regstr    = join '|', @dll_pfx;
    my $regmatch  = qr /$regstr/;
    my @dll_files = grep {$_ =~ $regmatch} @files;

    say $folder;
    #say join ' ', @files;
    #say $regmatch;
    say 'DLL files are: ', join ' ', @dll_files;

    return @dll_files;
}

#  find the set of gtk dlls installed into site/lib/auto
#  by sisyphusion.tk/ppm installs
#  only on windows
sub get_sis_gtk_dll_list {
    return if $OSNAME ne 'MSWin32';

    my $base = Path::Class::file($EXECUTABLE_NAME)
        ->parent
        ->parent
        ->subdir('site/lib/auto');

    my @files = File::Find::Rule->file()
                            ->name( 'lib*.dll' )
                            ->in( $base );
    @files = grep {$_ =~ /site.lib.auto/} @files;
    return @files;
}
