#  Build a Biodiverse binary for OS X

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };

use Config;
use File::Copy;
use Path::Class;
use Cwd;
use Cwd 'abs_path';
use File::Basename;
use File::Find;
use File::BaseDir qw/xdg_data_dirs/;

use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'script|s=s',              'The input script', { required => 1 } ],
  [ 'out_folder|out_dir|o=s',  'The output directory where the binary will be written'],
  [ 'icon_file|i=s',           'The location of the icon file to use'],
  [ 'lib_paths|l=s@',          'Paths to search for dynamic libraries'],
  [ 'pixbuf_loaders|p=s',      'The pixbuf loaders directory'],
  [ 'pixbuf_query_loader|q=s', 'The pixbuf query loader'],
  [ 'hicolor|h=s',             'The hicolor shared directory'],
  [ 'verbose|v=i',              'Verbose building?', {default => 0} ],
  [ 'execute|x!',              'Execute the script to find dependencies?', {default => 1} ],
  [ '-', 'Any arguments after this will be passed through to pp'],
  [],
  [ 'help|?',       "print usage message and exit" ],
);

if ($opt->help) {
    print($usage->text);
    exit;
}

my $script            = $opt->script;
my $verbose           = $opt->verbose ? $opt->verbose : q{};
my $lib_paths         = $opt->lib_paths ? $opt->lib_paths : [q{/usr/local/opt}];
my $execute           = $opt->execute ? '-x' : q{};
my @pixbuf_loaders    = $opt->pixbuf_loaders? $opt->pixbuf_loaders : q{/usr/local/opt/gdk-pixbuf/lib/gdk-pixbuf-2.0/2.10.0/loaders}; # need a way of finding this.
my @pixbuf_query_loader     = $opt->pixbuf_query_loader? $opt->pixbuf_query_loader : q{/usr/local/bin/gdk-pixbuf-query-loaders}; # need a way of finding this.
my @hicolor           = $opt->hicolor? $opt->hicolor : q{/usr/local/share/icons/hicolor}; # need a way of finding this.
my @rest_of_pp_args   = @ARGV;

#die "Script file $script does not exist or is unreadable" if !-r $script;

#  assume bin folder is at parent folder level
my $script_root_dir = Path::Class::file ($script)->dir->parent;
my $root_dir = Path::Class::file ($0)->dir->parent->parent->parent;
say "Root dir is " . Path::Class::dir ($root_dir)->absolute->resolve;
my $bin_folder = Path::Class::dir ($script_root_dir, 'bin');
my $icon_file  = $opt->icon_file // Path::Class::file ($bin_folder, 'Biodiverse_icon.ico')->absolute->resolve;
say "Icon file is $icon_file";

my $out_folder   = $opt->out_folder // Path::Class::dir ($root_dir, 'etc','mmb','builds','Biodiverse.app','Contents','MacOS');

my $perlpath     = $EXECUTABLE_NAME;

my $script_fullname = Path::Class::file($script)->absolute;
my $output_binary = basename ($script_fullname, '.pl', qr/\.[^.]*$/);

if (!-d $out_folder) {
    die "$out_folder does not exist or is not a directory";
}

###########################################
#
# Add libraries
#
###########################################

#  File::BOM dep are otherwise not found
$ENV{BDV_PP_BUILDING}              = 1;
$ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;

my @links;

# All the dynamic libraries to pack.
# Could change this to only include 
# the minimum set and then use 
# otools -L to find all dependancies.
my @dylibs = (
    'libgdal.20.dylib',          'libgobject-2.0.0.dylib', 
    'libglib-2.0.0.dylib',       'libffi.6.dylib', 
    'libpango-1.0.0.dylib',      'libpangocairo-1.0.0.dylib', 
    'libcairo.2.dylib',          'libfreetype.6.dylib', 
    'libgthread-2.0.0.dylib',    'libpcre.1.dylib', 
    'libintl.8.dylib',           'libpangoft2-1.0.0.dylib', 
    'libharfbuzz.0.dylib',       'libfontconfig.1.dylib', 
    'libpixman-1.0.dylib',       'libpng16.16.dylib', 
    'libgtk-quartz-2.0.0.dylib', 'libgdk-quartz-2.0.0.dylib', 
    'libatk-1.0.0.dylib',        'libgdk_pixbuf-2.0.0.dylib', 
    'libgio-2.0.0.dylib',        'libgmodule-2.0.0.dylib', 
    'libssl.1.0.0.dylib',        'libcrypto.1.0.0.dylib', 
    'libgdal.20.dylib',          'libproj.13.dylib', 
    'libjson-c.4.dylib',         'libfreexl.1.dylib', 
    'libgeos_c.1.dylib',         'libgif.7.dylib', 
    'libjpeg.9.dylib',           'libgeotiff.2.dylib', 
    'libtiff.5.dylib',           'libspatialite.7.dylib', 
    'libgeos-3.7.0.dylib',       'liblwgeom.dylib', 
    'libgnomecanvas-2.0.dylib',  'libart_lgpl_2.2.dylib', 
    'libgailutil.18.dylib',      'libfribidi.0.dylib',
    'libzstd.1.dylib',
    '/usr/local/Cellar/libxml2/2.9.6/lib/libxml2.2.dylib', 
    '/usr/local/Cellar/sqlite/3.21.0/lib/libsqlite3.0.dylib', 
    'libgraphite2.3.dylib',
);

# Find the absolute paths to each supplied
# dynamic library. Each library is supplied
# to pp with a -a and uses an alias. The alias
# packs the library at the top level of the 
# Par:Packer archive. This is where the 
# Biodiverse binary will be able to find it.
print "finding dynamic library paths\n";
for my $name (@dylibs){
    my $lib = find_dylib_in_path($name, @$lib_paths);
    my $filename = Path::Class::file ($name)->basename;
    push @links, '-a', "$lib\;../$filename";
    print "library $lib will be included as ../$filename\n" if ($verbose);
}

# Setup the paths to export
# as the environmental variables
# DYLD_LIBRARY_PATH and LD_LIBRARY_PATH.
# These are exported as temportary environmental variables
# when pp is run.
create_lib_paths();

# Use otools the get the name proper of the dynamic
# library.
sub get_name_from_dynamic_lib {
    my $lib = shift;
    
    my $name;

    chomp(my @ot = qx( otool -D $lib ));
    if ($? == 0) {
        $name = $ot[1];
        print "otool: library $lib has install name $name\n" if ($verbose);
    }
    return $name;
}

# Search for a dynamic library
# in the paths supplied. 
sub find_dylib_in_path {
    my ($file, @path) = @_;


    # If $file is an absolute path
    # then return with a fully resolved
    # file and path.
    #return get_name_from_dynamic_lib($file) if -f $file;
    return $file if -f $file;

    my $abs = "";
    my $dlext = $^O eq 'darwin' ? 'dylib' : $Config{dlext};
    # setup regular expressions variables
    # Example of patterns
    # Search pattern for finding dynamic libraries.
    #  <PREFIX><NAME><DELIMITER><VERSION><EXTENSION>
    # Examples:
    # for name without anything:               ffi
    # for name pattern prefix:name             libffi
    # for name pattern name:version:           ffi.6
    # for name pattern prefix:name:version:    libffi.6
    # for name pattern prefix:name:version:ext libffi.6.dylib
    for my $dir (@path) {
        next if (! -d $dir);
        $file  = substr $file, 0, -6 if $file =~ m/$dlext$/;
        find ({wanted => sub {return unless /^(lib)*$file(\.|-)[\d*\.]*\.$dlext$/; $abs = $File::Find::name}, follow=>1, follow_skip=>2 },$dir );
        find ({wanted => sub {return unless /^(lib)*$file\.$dlext$/; $abs = $File::Find::name}, follow=>1, follow_skip=>2 },$dir ) if ! $abs;
        return $abs if $abs;
        #print "could not file: $file\n" if (! $abs);
    }
    print "could not find file: $file\n" if (! $abs);
    return $abs;
}

# Create the DYLD_LIBRARY_PATH
# and LD_LIBRARY_PATH environmental
# variables.
my $dyld_library_path = "DYLD_LIBRARY_PATH=inc:/System/Library/Frameworks/ImageIO.framework/Versions/A/Resources/:";
my $ld_library_path = "LD_LIBRARY_PATH=inc:/System/Library/Frameworks/ImageIO.framework/Versions/A/Resources/:";

sub create_lib_paths {
   for my $name (@$lib_paths){
        $dyld_library_path .= $name . ":" . "inc" . $name . ":";
        $ld_library_path   .= $name . ":" . "inc" . $name . ":";
    }

    chop $dyld_library_path;
    chop $ld_library_path;
    print "[create_lib_paths] \$dyld_library_path: $dyld_library_path\n" 
      if $verbose;
    print "[create_lib_paths] \$ld_library_path: $ld_library_path\n" 
      if $verbose;
}


#my @gdal_deps = qw /jpeg gif geotiff proc
#                  json-c pcre freexl spatialite
#/;
#
#my @glib_deps = qw //;


###########################################
#
# Add file section
#
###########################################
my @add_files;
my $mime_dir;

sub get_xdg_data_dirs(){
    my @xdg_data_dirs = xdg_data_dirs;
    for $a (@xdg_data_dirs){
        if ( -d $a . "/mime" ) {
            $mime_dir = $a . "/mime";
        }
    }
}
# Add the  mime types directory.
get_xdg_data_dirs();


for $a($mime_dir) {
    my $mime_dir_abs  = Path::Class::file ($a)->basename;
    push @add_files, ('-a', "$mime_dir\;$mime_dir_abs");  
}

# Add the pixbuf loaders directory
my $pixbuf_loaders_abs  = Path::Class::dir (@pixbuf_loaders)->basename;
push @add_files, ('-a', "@pixbuf_loaders\\;$pixbuf_loaders_abs/");  

# Add the pixbuf query loader
#$pixbuf_loader = Path::Class::file ('usr','local','bin','gdk-pixbuf-query-loaders')
my $pixbuf_loader_abs  = Path::Class::file (@pixbuf_query_loader)->basename;
push @add_files, ('-a', "@pixbuf_query_loader\;$pixbuf_loader_abs");  

# Add the hicolor directory
#my $hicolor_dir = Path::Class::dir ('usr','local','share','icons','hicolor')
my $hicolor_dir_abs  = Path::Class::dir (@hicolor)->basename;
push @add_files, ('-a', "@hicolor\;icons/$hicolor_dir_abs");

# Add the ui directory
my @ui_arg = ();

if ($script =~ 'BiodiverseGUI.pl') {
    my $ui_dir = Path::Class::dir ($bin_folder, 'ui')->absolute;
    @ui_arg = ('-a', "$ui_dir\;ui");
}

my $output_binary_fullpath = Path::Class::file ($out_folder, $output_binary)->absolute;

my $icon_file_base = $icon_file ? basename ($icon_file) : '';
my @icon_file_arg  = $icon_file ? ('-a', "$icon_file\;$icon_file_base") : ();

###########################################
#
# Run the constructed pp command. 
#
###########################################

# export the dynamic library paths environmental variables.
$ENV{DYLD_LIBRARY_PATH} = $dyld_library_path;
$ENV{LD_LIBRARY_PATH} = $ld_library_path;

my @cmd = (
    'pp',
    #$verbose,
    '-u',
    '-B',
    '-z',
    9,
    @ui_arg,
    @icon_file_arg,
    $execute,
    @links,
    @add_files,
    @rest_of_pp_args,
    '-o',
    $output_binary_fullpath,
    $script_fullname,
);

if ($verbose) {
    my @verbose_command = ("-v=$verbose");
    splice @cmd, 1, 0, @verbose_command;
}

say join ' ', "\nCOMMAND TO RUN:\n", @cmd;

system @cmd;


###########################################
#
# Build the dmg image. 
#
###########################################
sub build_dmg(){
    print "[build_dmg] Building dmg image...\n" if ($verbose);
    my $builddmg = Path::Class::dir ($root_dir, 'etc','mmb','bin', 'builddmg.pl' );
    print "[build_dmg] build_dmg: $builddmg\n" if ($verbose);
    my $build_results = `perl $builddmg`;
}

build_dmg();
