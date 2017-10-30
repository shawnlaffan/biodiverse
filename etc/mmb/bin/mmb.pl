##!/Users/jason/perl5/perlbrew/perls/perl-5.22.0/bin/perl5.22.0

use strict;
use warnings;
use 5.010;
use File::Find::Rule;
use Path::Tiny qw(path);
use File::Slurp;
use Getopt::Long qw(GetOptions);
use Pod::Usage;
use File::Basename;
use File::Copy qw(copy);
use File::Spec::Functions;
use File::BaseDir qw/xdg_data_dirs/;

my @files = ();

my $dyld_library_path = "DYLD_LIBRARY_PATH=inc";
my $ld_library_path = "LD_LIBRARY_PATH=inc";


# Need to remove these.
my $run_command_first_part;
my $add_files;
my @dylibs = ();
my $include_lib = "";
my @founddylibs = ();

#my $perl_location = `which perl5.22.0`;
my $perl_location = $^X;
chomp $perl_location;

# Setup options.
my $man = 0;
my $help = 0;
my $remove = 0;
my $copydys = 0;
my $mime_dir;
my $filename;
my $verbose = 0;
my @libraries  = ('/usr/local/opt');
my $biodiverse_dir = catfile($ENV{"HOME"}, "biodiverse" );
my $biodiverse_bin_dir = catfile($ENV{"HOME"}, "biodiverse", "bin" );
my $build_script = catfile($biodiverse_dir, "etc", "pp", "build.pl");
my $script = catfile($biodiverse_dir, "bin", "BiodiverseGUI.pl");
my $output_dir = catfile($biodiverse_dir, "etc", "mmb", "builds", "Biodiverse.app", "Contents", "MacOS");
my $icon = catfile($biodiverse_dir, "bin", "Biodiverse_icon.ico");

GetOptions(
    'help|?' => \$help,
    'man'    => \$man,
    'biodir|b=s' => \$biodiverse_dir,
    'dylibs|d=s' => \$filename,
    'icon|i=s'   => \$icon,
    'script|s=s' => \$script,
    'build|u=s'  =>\$build_script,
    'output|o=s' =>\$output_dir,
    'remove|r'   =>\$remove,
    'copy|c'   =>\$copydys,
    'library|l=s' =>\@libraries,
    'verbose|v=s' =>\$verbose
) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;

# Read in the dynamic libary file
# and put each line into an array.
if ($filename) {
    @dylibs = read_file($filename, chomp =>1);
}

# Function to get the directory
# for mime types.
sub get_xdg_data_dirs(){
    my @xdg_data_dirs = xdg_data_dirs();
    foreach my $dir (@xdg_data_dirs){
        say "Checking for ${dir}/mime";
        if ( -d $dir . "/mime" ) {
            say 'Found it';
            $mime_dir = $dir. "/mime";
            last;
        }
    }
}

# Function to get the absolute paths
# of the required dynamic libraries.
# Returns an array with this list.
# Prints to STDOUT any file not
# found.
sub find_dylibs {
    my @path = shift;
    my @findlibs = shift;
    print "Finding dynamic libraries locations\n";
    #@dylibs = ('libgdal.dylib','libgobject-2.0.0.dylib');
    my @dylibs = ('libgdal.dylib', 'libgobject-2.0.0.dylib', 'libglib-2.0.0.dylib', 'libffi.6.dylib', 'libpango-1.0.0.dylib', 'libpangocairo-1.0.0.dylib', 'libcairo.2.dylib', 'libfreetype.6.dylib', 'libgthread-2.0.0.dylib', 'libpcre.1.dylib', 'libintl.8.dylib', 'libpangoft2-1.0.0.dylib', 'libharfbuzz.0.dylib', 'libfontconfig.1.dylib', 'libpixman-1.0.dylib', 'libpng16.16.dylib', 'libgtk-quartz-2.0.0.dylib', 'libgdk-quartz-2.0.0.dylib', 'libatk-1.0.0.dylib', 'libgdk_pixbuf-2.0.0.dylib', 'libgio-2.0.0.dylib', 'libgmodule-2.0.0.dylib', 'libssl.1.0.0.dylib', 'libcrypto.1.0.0.dylib', 'libgdal.20.dylib', 'libproj.12.dylib', 'libjson-c.2.dylib', 'libfreexl.1.dylib', 'libgeos_c.1.dylib', 'libgif.4.dylib', 'libjpeg.8.dylib', 'libgeotiff.2.dylib', 'libtiff.5.dylib', 'libspatialite.7.dylib', 'libxml2.2.dylib', 'libgeos-3.5.0.dylib', 'liblwgeom-2.1.5.dylib', 'libsqlite3.0.dylib', 'libgnomecanvas-2.0.dylib', 'libart_lgpl_2.2.dylib', 'libgailutil.18.dylib');
    @libraries = ('/usr/local/opt');

    foreach $a (@dylibs){
        my @file =  File::Find::Rule->file()
                                  ->extras({ follow => 1,follow_skip => 2 })
                                  ->name( "$a" )
                                  ->in( @libraries );
        push @founddylibs, @file;
        print "Found $a at @file\n" if ($verbose);
    }
}


# Test if dynamic library
# is a symbolic link
sub check_symbolic_link {
    # Get passed arguments
    my $alib = shift;

    # Check is the library is a symbolic link.
    # If it is return the original library name
    # but with the symbolic links name.
    if(-l $alib){
        return ($alib, $alib,readlink $alib);
    } else {
        return ($alib, $alib, basename $alib);
    }
}

# copy each required dynamic
# library to the bin dir.
sub copy_dylibs_to_bin_dir {
    my @dy = @founddylibs; #find_dylibs();
    print "Copying dynamic libraries biodiverse/bin/\n";
    foreach $a (@dy){
        my ($link, $orig, $newname) = check_symbolic_link($a);
        my $newlib = catfile($biodiverse_dir, "bin", $newname);
        copy $orig, $newlib or die "The copy operation failed: $!";
    }
}

# Remove old dynamic libraries
# from the biodiverse/bin directory.
sub remove_old_dylibs_from_bin_dir {
    my $bindir = $biodiverse_dir . "bin/";
    print "Removing stale dynamic libraries.\n";
    `rm -fR $bindir.*dylib`;
}


# Create the dynamic library
# string for the final command line
# arguments.
sub lib_strings {
    my @dyl = @founddylibs; #find_dylibs(@libraries,@dylibs);
    foreach my $c (@dyl){
        $include_lib = "$include_lib -l $c";
    } 
    print "[lib_strings] include_lib: $include_lib\n" if ($verbose);
}

# Create the DYLD_LIBRARY_PATH
# and LD_LIBRARY_PATH environmental
# variables.
sub create_lib_paths {
   foreach $b (@libraries){
        $dyld_library_path = $dyld_library_path . $b . ":";
        $ld_library_path = $ld_library_path . $b . ":";
    }
    #Messing handling of trailing ":"
    chop $dyld_library_path;
    chop $ld_library_path;
}

sub create_command_line_string {
    # Put all the variables together to 
    # form the first part of the build script.
    $run_command_first_part = "cd $biodiverse_dir\; $dyld_library_path $ld_library_path $perl_location $build_script -o $output_dir -s $script -i $icon --";

    $add_files = " -a /usr/local/Cellar/gdk-pixbuf/2.36.0_2/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache\\;loaders.cache -a /usr/local/Cellar/gdk-pixbuf/2.36.0_2/lib/gdk-pixbuf-2.0/2.10.0/loaders\\;loaders -a $mime_dir\\;mime -a /usr/local/share/icons\\;icons";
    print "[crete_command_line_string] run_command_first_part: $run_command_first_part\n" if ($verbose);
    print "[crete_command_line_string] add_files: $add_files\n" if ($verbose);
}

sub run_build_mac_version() {
    print "[run_build_mac_version]\n" if ($verbose);
    print "[run_build_mac_version] run_command_first_part include_lib add_files: $run_command_first_part $include_lib $add_files\n" if ($verbose);
    my $result = `$run_command_first_part $include_lib $add_files`;
    print "$result\n" if ($verbose);
}

sub build_dmg(){
    print "[build_dmg] Building dmg image...\n" if ($verbose);
    my $builddmg = catfile($biodiverse_dir, "etc", "mmb", "bin", "builddmg.pl" );
    print "[build_dmg] build_dmg: $builddmg\n" if ($verbose);
    my $build_results = `perl $builddmg`;
}

if ($remove){
    remove_old_dylibs_from_bin_dir()
}

if ($copydys){
    find_dylibs();
    copy_dylibs_to_bin_dir();
}

if (@libraries){
    create_lib_paths();
}

get_xdg_data_dirs();
create_command_line_string();
lib_strings();
run_build_mac_version();
build_dmg();

__END__

=head1 NAME

mmb - Make Macintosh Biodiverse

=head1 SYNOPSIS

mmb [options]

Options:
    --help
    --man
    --biodiverse_dir  BIODIVERSE_DIR
    --dylibs          DYNAMICLIBRARIES
    --icon	      ICON
    --script          SCRIPT
    --build_script    BUILDSCRIPT
    --output          OUTPUTDIR
    --remove
    --copy
    --verbose

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-biodiverse_dir>

Location of the biodiverse director.

=item B<-dylibs>

Location of the file containing the required dynamic library names.

=item B<-build>

Location of the biodiverse build script.

=item B<-script>

Location of the main biodiverse script BiodiverseGUI.pl.

=item B<-build>

Location of the biodiverse build script.

=item B<-output>

Location of where the macintosh script should be saved.

=item B<-remove>

If true remove old dynamic libraries in bin directory.

=item B<-copy>

If true copy dynamic libraries in bin directory.

=item B<-libpath>

Paths to libraries for environmental variables DYLD_LIBRARY_PATH and LD_LIBRARY_PATH.

=item B<-vabose>

Verbose mode.

=back

=head1 DESCRIPTION

mmb will take the supplied options and files and
build a machintosh version of BiodiverseGUI.

=cut

