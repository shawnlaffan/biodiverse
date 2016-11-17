#!/Users/jason/perl5/perlbrew/perls/perl-5.22.0/bin/perl

use strict;
use warnings;
use 5.010;
use File::Find::Rule;
use Path::Tiny qw(path);
use File::Slurp;
use Getopt::Long qw(GetOptions);
use Pod::Usage;

my @files;
my $dir  = "/usr/local/opt";

my $dyld_library_path = "DYLD_LIBRARY_PATH=inc";
my $ld_library_path = "LD_LIBRARY_PATH=inc";


# Need to remove these.
my $run_command_first_part;
my @libraries; 
my $add_files;
my @libs;
my $include_lib = "";

my $perl_location = `which perl`;
chomp $perl_location;

# Setup options.
my $man = 0;
my $help = 0;
my $remove = 0;
my $copydys = 0;
my $filename;
my $biodiverse_dir = "~/biodiverse/";
my $build_script = $biodiverse_dir . "etc/pp/build.pl";
my $script = $biodiverse_dir ."bin/BiodiverseGUI.pl";
my $output_dir = "~/Documents/Biodiverse.app/Contents/MacOS/";
my $icon = $biodiverse_dir . "bin/Biodiverse_icon.ico";

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
    'library|l=s' =>\@libraries
) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;

#print "$icon\n";
#print "$filename\n";
#print "$script\n";
#print "$build_script\n";
#print "$output_dir\n";
#print "$perl_location\n";

# Read in the dynamic libary file
# and put each line into an array.
if ($filename) {
    @libs = read_file(path($filename), chomp => 1);
}

# Function to get the absolute paths
# of the required dynamic libraries.
# Returns an array with this list.
# Prints to STDOUT any file not
# found.
sub find_dylibs {
    @files =  File::Find::Rule->file()
    ->extras({ follow => 1,follow_skip => 2 })
    ->name( @libs )
    ->in( @libraries );
    return @files;
}

# copy each required dynamic
# library to the bin dir.
sub copy_dylibs_to_bin_dir(){
    my @dy = find_dylibs();
    print "Copying dynamic libraries biodiverse/bin/\n";
    foreach $a (@dy){
        my $bindir = $biodiverse_dir . "bin/";
        `cp -p $a $bindir`;
        `chmod u+w $bindir*dylib`;
    }
}

# Remove old dynamic libraries
# from the biodiverse/bin directory.
sub remove_old_dylibs_from_bin_dir(){
    my $bindir = $biodiverse_dir . "bin/";
    print "Removing stale dynamic libraries.\n";
    `rm -fR $bindir.*dylib`;
}


# Create the dynamic library
# string for the final command line
# arguments.
sub lib_strings() {
    my @dyl = find_dylibs();
    foreach my $c (@dyl){
        $include_lib = "$include_lib -l $c";
    } 
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

sub create_command_line_string() {
    # Put all the variables together to 
    # form the first part of the build script.
    $run_command_first_part = "cd $biodiverse_dir\; $dyld_library_path $ld_library_path $perl_location $build_script -o $output_dir -s $script -i $icon --";

    $add_files = ' -a /usr/local/Cellar/gdk-pixbuf/2.36.0_2/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache\;loaders.cache -a /usr/local/Cellar/gdk-pixbuf/2.36.0_2/lib/gdk-pixbuf-2.0/2.10.0/loaders\;loaders';
}

sub run_build_mac_version() {
    my @args = ( "$run_command_first_part $include_lib $add_files" );
    exec { $args[0] } @args;
    #exec ($run_command_first_part $include_lib $add_files) or print STDERR "couldn't exec foo: $!";
    #print "$run_command_first_part $include_lib $add_files\n";
}

if ($remove){
    remove_old_dylibs_from_bin_dir()
}

if ($copydys){
    copy_dylibs_to_bin_dir();
}

if (@libraries){
    create_lib_paths();
}

create_command_line_string();
lib_strings();
run_build_mac_version();

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

=back

=head1 DESCRIPTION

mmb will take the supplied options and files and
build a machintosh version of BiodiverseGUI.

=cut

