#!/usr/bin/perl

use strict;
use warnings;
use 5.010;
use Getopt::Long qw(GetOptions);
use Pod::Usage;
use English qw { -no_match_vars };
use Cwd 'abs_path';
use File::Basename;
use File::Spec::Functions;
use FindBin;
use lib "$FindBin::Bin/../../../lib";
use Biodiverse::Config;

BEGIN {
    # Check to see if we are running on OS X.
    # and exit if we aren't.
    if ($OSNAME ne 'darwin') {die "error: requires darwin (OSX)."};
}

my $bio_version = $Biodiverse::Config::VERSION;
my $mac_build_version = 2;
my $help;
my $verbose;
my $man = 0;
my $output  = catfile($FindBin::Bin, "..", "builds", "Biodiverse-$bio_version-$mac_build_version.dmg");
my $input  = catfile($FindBin::Bin, "..", "images", "Biodiverse.dmg");
my $app = catfile($FindBin::Bin, "..", "builds", "Biodiverse.app");
my $mounted = "/Volumes/Biodiverse";

GetOptions(
    'help|?' => \$help,
    'man'    => \$man,
    'output|o=s' => \$output,
    'input|i=s' => \$input,
    'app|a=s' => \$app,
    'mounted|m=s' => \$mounted,
    'verbose|v=s' => \$verbose
) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;

sub mount_read_write_dmg() {
    # Mounted the supplied read/write dmg image.
    # Default is ../images/Biodiverse.dmg
    print "mounting $input\n";
    my @mount_args = ("hdiutil", "attach", "$input");
    system(@mount_args) == 0
        or die "system @mount_args failed: $?";
}

sub remove_app() {
    # Removes Biodiverse.app for the mounted read/write dmg image
    print "removing Biodiverse.app from $input\n";
    my @remove_app_args = ("rm", "-fR", "$mounted/Biodiverse.app");
    system(@remove_app_args) == 0
        or die "system @remove_app_args failed: $?";
}

sub remove_old_read_only_dmg() {
    # Removes the old read only dmg image.
    # Default is ../images/Biodiverse.dmg.
    print "removing  $output\n";
    my @remove_dmg_args = ("rm", "-fR", "$output");
    system(@remove_dmg_args) == 0
        or die "system @remove_dmg_args failed: $?";
}

sub copy_new_app() {
    # Copies the new Biodiverse.app to the mounted read/write dmg image.
    # Default is ../builds/Biodiverse.app.
    print "copy $app into $input\n";
    my @copy_app_args = ("cp", "-r", "$app" , "$mounted");
    system(@copy_app_args) == 0
        or die "system @copy_app_args failed: $?";
}

sub unmount_read_write_dmg() {
    # Unmounts the read/write dmg image.
    print "unmounting $input\n";
    my @detach_mounted_args = ("hdiutil", "detach", "$mounted");
    system(@detach_mounted_args) == 0
        or die "system @detach_mounted_args failed: $?";
}

sub create_new_dmg() {
    # Creates a new read only Biodiverse dmg image and saves it.
    # Default is ../builds/Biodiverse.dmg.
    print "creating $output as read only\n";
    my @convert_args = ("hdiutil", "convert", "-format", "UDRO", "-o", "$output", "$input" );
    system(@convert_args) == 0
        or die "system @convert_args failed: $?";
}

mount_read_write_dmg();
remove_app();
remove_old_read_only_dmg();
copy_new_app();
unmount_read_write_dmg();
create_new_dmg();

__END__

=head1 NAME

builddmg - Builds a read only Biodiverse dmg from the Biodiverse.app and an original read/write dmg image.

=head1 SYNOPSIS

builddmg [options]

Options:
    --help
    --man
    --output  OUTPUT
    --input   INPUT
    --app     APP
    --mounted MOUNTED

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-output>

Location of the output read only dmg image.

=item B<-input>

Location of the read/write input dmg image.

=item B<-app>

Location of Biodiverse.app to be included in the new dmg image.

=item B<-mounted>

Location of the mounted dmg image.

=back

=head1 DESCRIPTION

Builds a dmg image of Biodiverse.

=cut

