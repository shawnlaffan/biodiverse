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

use App::PP::Autolink 2.04;

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


#  clunky - should hunt for Gtk2 use in script?  
my @ui_arg = ();
my @gtk_path_arg = ();
if ($script =~ 'BiodiverseGUI.pl') {
    my $ui_dir = Path::Class::dir ($bin_folder, 'ui')->absolute;
    @ui_arg = ('-a', "$ui_dir;ui");
    
    push @gtk_path_arg, get_sis_theme_stuff();
}

my $icon_file_base = $icon_file ? basename ($icon_file) : '';
my @icon_file_arg  = $icon_file ? ('-a', "$icon_file;$icon_file_base") : ();

#  make sure we get the aliens
#  last two might not be used long term
my @aliens = qw /
    Alien::gdal       Alien::geos::af
    Alien::proj       Alien::sqlite
    Alien::spatialite Alien::freexl
    Alien::libtiff    Alien::curl
/;
push @rest_of_pp_args, map {; '-M' => $_} @aliens;

my $output_binary_fullpath = Path::Class::file ($out_folder, $output_binary)->absolute;

$ENV{BDV_PP_BUILDING}              = 1;
$ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;

my @cmd = (
    #$^X,
    #"$Bin/pp_autolink.pl",
    'pp_autolink',
    ($verbose ? '-v' : ()),
    '-u',
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


sub get_sis_theme_stuff {
    return if $OSNAME ne 'MSWin32';

    #  get the Gtk2 stuff
    my $base = Path::Class::file($EXECUTABLE_NAME)
        ->parent
        ->parent
        ->subdir('site');
#say "Looking for Sis stuff under $base";
    my @path_args;
    my $sharedir = 'share';
    my $source_dir = Path::Class::dir ($base, $sharedir);
    my $dest_dir   = Path::Class::dir ($sharedir);
    push @path_args, ('-a', "$source_dir;$dest_dir");
    my $subdir = 'lib/auto/Cairo/etc';
    $source_dir = Path::Class::dir ($base, $subdir);
    $dest_dir   = Path::Class::dir ($subdir);
    push @path_args, ('-a', "$source_dir;$dest_dir");

    # packs libwimp.dll etc
    my $gtk2dir = 'lib/gtk-2.0';
    $source_dir = Path::Class::dir ($base, $gtk2dir);
    $dest_dir   = Path::Class::dir ($gtk2dir);
    push @path_args, ('-a', "$source_dir;$dest_dir");

    return @path_args;
}


sub get_autolink_list {
    my ($script, $no_execute_flag) = @_;

    my $OBJDUMP   = which('objdump')  or die "objdump not found";
    
    my $env_sep  = $OSNAME =~ /MSWin32/i ? ';' : ':';
    my @exe_path = split $env_sep, $ENV{PATH};

    if ($OSNAME =~ /MSWin32/i) {
        #  skip anything under the C:\Windows folder (or D:\ etc just to be sure)
        @exe_path = grep {$_ !~ m|^[a-z]\:[/\\]windows|i} @exe_path;
    }
    #  what to skip for linux or mac?

    my @dlls = get_dep_dlls ($script, $no_execute_flag);
    
    #say join "\n", @dlls;
    
    my $re_skippers = get_dll_skipper_regexp();
    my %full_list;
    my %searched_for;
    my $iter = 0;

  DLL_CHECK:
    while (1) {
        $iter++;
        say "DLL check iter: $iter";
        #say join ' ', @dlls;
        my ( $stdout, $stderr, $exit ) = capture {
            system( $OBJDUMP, '-p', @dlls );
        };
        if( $exit ) {
            $stderr =~ s{\s+$}{};
            warn "(@dlls):$exit: $stderr ";
            exit;
        }
        @dlls = $stdout =~ /DLL.Name:\s*(\S+)/gmi;
        #  extra grep is wasteful but useful for debug 
        #  since we can easily disable it
        @dlls
          = sort
            grep {!exists $full_list{$_}}
            grep {$_ !~ /$re_skippers/}
            uniq
            @dlls;
        
        if (!@dlls) {
            say 'no more DLLs';
            last DLL_CHECK;
        }
        
        #say join "\n", @dlls;
        
        my @dll2;
        foreach my $file (@dlls) {
            next if $searched_for{$file};
            #  don't recurse
            my $rule = File::Find::Rule->new->maxdepth(1);
            $rule->file;
            #  need case insensitive match for Windows
            $rule->name (qr/^\Q$file\E$/i);
            $rule->start (@exe_path);
            #  don't search the whole path every time
          MATCH:
            while (my $f = $rule->match) {
                push @dll2, $f;
                last MATCH;
            }
    
            $searched_for{$file}++;
        }
        @dlls = uniq @dll2;
        my $key_count = keys %full_list;
        @full_list{@dlls} = (1) x @dlls;
        
        #  did we add anything new?
        last DLL_CHECK if $key_count == scalar keys %full_list;
    }
    
    my @l2 = sort keys %full_list;

    return wantarray ? @l2 : \@l2;
}

sub get_dll_skipper_regexp {
    #  used to be more here from windows folder
    #  but we avoid them in the first place now
    #  PAR packs these automatically these days
    my @skip = qw /
        perl5\d\d
        libstdc\+\+\-6
    /;
    my $sk = join '|', @skip;
    my $qr_skip = qr /^(?:$sk)$RE_DLL_EXT$/;
    return $qr_skip;
}

#  find dependent dlls
#  could also adapt some of Module::ScanDeps::_compile_or_execute
#  as it handles more edge cases
sub get_dep_dlls {
    my ($script, $no_execute_flag) = @_;
    
    #  make sure $script/../lib is in @INC
    #  assume script is in a bin folder
    my $rlib_path = (path ($script)->parent->parent->stringify) . '/lib';
    #say "======= $rlib_path/lib ======";
    local @INC = (@INC, $rlib_path)
      if -d $rlib_path;
    
    my $deps_hash = scan_deps(
        files   => [ $script ],
        recurse => 1,
        execute => !$no_execute_flag,
    );

    my %dll_hash;
    foreach my $package (keys %$deps_hash) {
        #  could access {uses} directly, but this helps with debug
        my $details = $deps_hash->{$package};
        my $uses    = $details->{uses};
        next if !$uses;
        
        foreach my $dll (grep {$_ =~ $RE_DLL_EXT} @$uses) {
            my $dll_path = $deps_hash->{$package}{file};
            #  Remove trailing component of path after /lib/
            #  Clunky and likely to fail somewhere if we have x/lib/stuff/lib/lib.pm.
            #  Not sure how likely that is, though.
            #  Maybe check against entries in @INC?
            $dll_path =~ s|(?<=/lib/).+?$||;
            $dll_path .= $dll;
            croak "cannot find $dll_path for package $package"
              if not -e $dll_path;
            $dll_hash{$dll_path}++;
        }
    }
    
    my @dll_list = sort keys %dll_hash;
    return wantarray ? @dll_list : \@dll_list;
}
