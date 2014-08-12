#!/usr/bin/perl -w

package Biodiverse::Config;
use 5.010;
use strict;
use warnings;

use English ( -no_match_vars );

our $VERSION = '0.99_002';

#use Exporter;
#use Devel::Symdump;

our @ISA = qw (Exporter);
our @EXPORT = qw /use_base add_lib_paths/;
#our %base_packages;

use Carp;
use Data::Dumper qw /Dumper/;
use FindBin qw ( $Bin );
use Path::Class;

#  These global vars need to be converted to subroutines.
#  update interval for progress bars  - need to check for tainting
our $progress_update_interval     = $ENV{BIODIVERSE_PROGRESS_INTERVAL} || 0.3;
our $progress_update_interval_pct = $ENV{BIODIVERSE_PROGRESS_INTERVAL_PCT} || 5;
our $progress_no_use_gui          = $ENV{BIODIVERSE_PROGRESS_NO_USE_GUI} ? 1 : 0;

our $running_under_gui = 0;

our $license = << 'END_OF_LICENSE'
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.
END_OF_LICENSE
  ;

BEGIN {
    #  Add the gtk and gdal libs if using windows - brittle?
    #  Search up the tree until we find a dir of the requisite name
    #  and which contains a bin folder
    if ($OSNAME eq 'MSWin32') {
        #say "PAR_PROGNAME: $ENV{PAR_PROGNAME}";
        my $prog_name  = $ENV{PAR_PROGNAME} || $Bin;
        

        my @paths;
        use Config;
        my $use_x64 = $Config{archname} =~ /x(?:86_)?64/;
        my $gtk_dir  = $use_x64 ? 'gtk_win64'  : 'gtk_win32';  #  maybe should use ivsize?
        my $gdal_dir = $use_x64 ? 'gdal_win64' : 'gdal_win32';

        #  add the gtk and gdal bin dirs to the path
        foreach my $g_dir ($gtk_dir, $gdal_dir) {
            my $origin_dir = Path::Class::file($prog_name)->dir;

          ORIGIN_DIR:
            while ($origin_dir) {

                foreach my $inner_path (
                  Path::Class::dir($origin_dir, $g_dir,),
                  Path::Class::dir($origin_dir, $g_dir, 'c'),
                  ) {
                    #say "Checking $inner_path";
                    my $bin_path = Path::Class::dir($inner_path, 'bin');
                    if (-d $bin_path) {
                        #say "Adding $bin_path to the path";
                        push @paths, $bin_path;
                    }
                }
    
                my $old_dir = $origin_dir;
                $origin_dir = $origin_dir->parent;
                last ORIGIN_DIR if $old_dir eq $origin_dir;
            }
        }

        my $sep = ';';  #  should get from system, but this block only works on windows anyway
        say 'Prepending to path: ', join ' ', @paths;
        $ENV{PATH} = join $sep, @paths, $ENV{PATH};

    }
}


#  add biodiverse lib paths so we get all the extensions
#  should be a sub not a begin block
sub add_lib_paths {
    my $var = shift;

    if (! defined $var) {
        $var = 'BIODIVERSE_LIB';
    }

    my @lib_paths;

    #  set user defined libs not collected by the perl interpreter,
    #  eg when using the perlapp exe file
    if ( defined $ENV{$var} ) {
        my $sep = q{:};    #  path list separator for *nix systems

        if ( $OSNAME eq 'MSWin32' ) {
            $sep = q{;};
        }
        push @lib_paths, split $sep, $ENV{$var};
    }

    print "Adding $var paths\n";
    print join q{ }, @lib_paths, "\n";

    #no warnings 'closure';
    eval 'use lib @lib_paths';

    return;
}

#  load all the relevant user defined libs into their respective packages
sub use_base {
    my $file = shift;
    my $use_envt_var;

    if (!defined $file) {
        if (exists $ENV{BIODIVERSE_EXTENSIONS}
            && ! $ENV{BIODIVERSE_EXTENSIONS_IGNORE}) {
            $file = $ENV{BIODIVERSE_EXTENSIONS};
            $use_envt_var = 1;
        }
        else {
            print "[USE_BASE] No user defined extensions\n";
            return;
        }
    }
    my %check_packages;

    print "[USE_BASE] Checking and loading user modules";

    my $x;
    if (-e $file) {
        print " from file $file\n";
        local $/ = undef;
        my $success = open (my $fh, '<', $ENV{BIODIVERSE_EXTENSIONS});
        croak "Unable to open extensions file $ENV{BIODIVERSE_EXTENSIONS}\n"
            if ! $success;

        $x = eval (<$fh>);
        my $e = $EVAL_ERROR;
        if ($e) {
            warn "[USE_BASE] Problems with environment variable BIODIVERSE_EXTENSIONS - check the filename or syntax\n";
            warn $EVAL_ERROR;
            warn "$ENV{BIODIVERSE_EXTENSIONS}\n";
        }
        close ($fh);
    }
    elsif ($use_envt_var) {
        warn "Loading extensions directly from environment variable is deprecated\n";
        warn "Nothing loaded\n";
    }

    @check_packages{keys %$x} = values %$x if (ref $x) =~ /HASH/;

    foreach my $package (keys %check_packages) {
        my @packs = @{$check_packages{$package}};
        my $pack_list = join (q{ }, @packs);

        print "$package inherits from $pack_list\n";

        foreach my $pk (@packs) {
            croak "INVALID PACKAGE NAME $package"
              if not $package =~ /^[\w\d]+(?:::[\w\d]+)*$/;  #  pretty basic checking

            my $cmd = "package $package;\n"
                    . "use parent qw/$pk/;";
            eval $cmd;
            warn $EVAL_ERROR if $EVAL_ERROR;
        }
    }

    return;
}

add_lib_paths();
use_base();

#  need this for the pp build to work
if ($ENV{BDV_PP_BUILDING}) {
    use utf8;
    say 'Building pp file';
    say "using $0";
    use File::BOM qw / :subs /;          #  we need File::BOM.
    open my $fh, '<:via(File::BOM)', $0  #  just read ourselves
      or croak "Cannot open $Bin via File::BOM\n";
    $fh->close;

    #  exercise the unicode regexp matching - needed for the spatial conditions
    use 5.016;
    use feature 'unicode_strings';
    my $string = "sp_self_only () and \N{WHITE SMILING FACE}";
    $string =~ /\bsp_self_only\b/;
}


1;


__END__

=head1 NAME

Biodiverse::Config


=head1 DESCRIPTION

Configuration for the Biodiverse modules.

See http://purl.oclc.org/biodiverse for more details.

=head1 SYNOPSIS

  use Biodiverse::Config qw /use_base add_lib_paths/;
  BEGIN {
      add_lib_paths();
      use_base();
  }

=head1 METHODS and VARIABLES

=over

=item add_lib_paths()

Add the paths specified in C<$ENV{BIODIVERSE_LIB}> to @INC.
Also adds the Biodiverse lib folder if needed (using C<../lib>).

=item use_base()

Load user defined libs into the modules specified in the control file
specified in C<$ENV{BIODIVERSE_EXTENSIONS}>.
Set C<$ENV{BIODIVERSE_EXTENSIONS_IGNORE}> to 1 to not load the extensions.

=item my $update_interval = $Biodiverse::Config::progress_update_interval

Update frequency for the progress dialogue in the GUI.  Default is 0.3.

=back

=head1 AUTHOR

Shawn Laffan

=head1 License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut

