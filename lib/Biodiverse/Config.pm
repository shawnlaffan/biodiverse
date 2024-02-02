package Biodiverse::Config;
use 5.010;
use strict;
use warnings;

use Env qw /@PATH/;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

#  avoid redefined warnings due to
#  https://github.com/rurban/Cpanel-JSON-XS/issues/65
use JSON::PP ();

use Ref::Util qw { :all };

use English ( -no_match_vars );

our $VERSION = '4.99_002';

#use Exporter;
#use Devel::Symdump;

our @ISA = qw (Exporter);
our @EXPORT = qw /use_base add_lib_paths/;
#our %base_packages;

use Carp;
#use Data::Dumper qw /Dumper/;
use FindBin qw ( $Bin );
use Path::Tiny qw /path/;

#  These global vars need to be converted to subroutines.
#  update interval for progress bars  - need to check for tainting
our $progress_update_interval     = $ENV{BIODIVERSE_PROGRESS_INTERVAL}     || 0.3;
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
    if ($ENV{PAR_0}) {
        use Config;
        push @PATH, $ENV{PAR_TEMP};
    }
    #print $ENV{PATH};
};

#  update paths on Strawberry perls if needed
BEGIN {
    use Config;
    if (($Config{myuname} // '') =~ /strawberry/i) {
        #use Env qw /@PATH/;
        my $sbase = path($^X)->parent->parent->parent;
        my @non_null_paths = grep {defined} @PATH;  #  avoid undef path entries
        my %pexists;
        @pexists{@non_null_paths} = @non_null_paths;
        my @paths =
            grep {-e $_ && !exists $pexists{$_}}
                map {path($sbase, $_)}
                    ("/c/bin", "/perl/bin", "/perl/site/bin", "/perl/vendor/bin");
        if (@paths) {
            say "Strawberry perl detected, prepending its bin dirs to path";
            unshift @PATH, @paths;
        }
    }
    eval 'use Alien::GtkStack::Windows';
    if (!$EVAL_ERROR) {
        say "Added Alien::GtkStack::Windows bin dir to path";
    }
}

#  Ensure the bin dirs for the aliens are at the front
#  Crude, but we need to ensure we use the packaged aliens
#  See GH issue #795 - https://github.com/shawnlaffan/biodiverse/issues/795
#  An alternative approach is to elide the competing paths
#  but that could lead to other issues
BEGIN {
    #  we don't really need all of them, but...
    my @aliens = qw /
        Alien::gdal   Alien::geos::af  Alien::sqlite
        Alien::proj   Alien::libtiff   Alien::spatialite
        Alien::freexl
    /;
    foreach my $alien_lib (@aliens) {
        my $have_lib = eval "require $alien_lib";
        if ($have_lib && $alien_lib->install_type eq 'share') {
            unshift @PATH, $alien_lib->bin_dir;
        }
    }
    #say STDERR join ' ', @PATH;
}

#  Check for installed dependencies and warn if not present.
#  Useful when users are running off the source code install
#  and aren't tracking announcements.
#  Should loop this.
BEGIN {
    #  more general solution for anything new
    #  add modules as they are required
    my @reqd = qw /
    /;
    foreach my $module (@reqd) {
        if (not eval "require $module") {
            #say $@ if $@;
            my $feedback = <<"END_FEEDBACK"
Cannot locate the $module package.  
You probably need to install it using
  cpanm $module
at the command prompt.
See https://metacpan.org/pod/$module for more details about what it does.
END_FEEDBACK
  ;
            die $feedback;
        }
    }
}

#  add biodiverse lib paths so we get all the extensions
sub add_lib_paths {
    my $var = shift // 'BIODIVERSE_LIB';

    my @lib_paths;

    #  set user defined libs not collected by the perl interpreter,
    #  eg when using the perlapp exe file
    if ( defined $ENV{$var} ) {
        use Config;
        my @paths = grep {-d} split $Config{path_sep}, $ENV{$var};
        push @lib_paths, @paths;
    }

    return if !scalar @lib_paths;

    say "Adding $var paths to \@INC";
    say join q{ }, @lib_paths;

    #no warnings 'closure';
    eval 'use lib @lib_paths';

    return;
}

my @use_base_errors;

#  load all the relevant user defined libs into their respective packages
sub use_base {
    my $file = shift;
    my $use_envt_var;

    if (!defined $file) {
        if (exists $ENV{BIODIVERSE_EXTENSIONS}
            && ! $ENV{BIODIVERSE_EXTENSIONS_IGNORE}) {
            $file = $ENV{BIODIVERSE_EXTENSIONS};
        }
        else {
            print "[USE_BASE] No user defined extensions\n";
            return;
        }
    }
    my %check_packages;

    say "[USE_BASE] Checking and loading user modules";

    my $x;
    if (-e $file) {
        say "...from file $file";
        local $/ = undef;
        my $success = open (my $fh, '<', $file);
        croak "Unable to open extensions file $file\n"
            if ! $success;

        $x = eval (<$fh>);
        my $e = $EVAL_ERROR;
        if ($e) {
            warn "[USE_BASE] Problems with environment variable BIODIVERSE_EXTENSIONS - check the filename or contents\n";
            warn $EVAL_ERROR;
            warn "$file\n";
        }
        close ($fh);
    }
    else {
        warn "File $file does not exist\n";
        warn "Loading extensions directly from environment variable is not supported\n";
        warn "Nothing loaded\n";
    }

    @check_packages{keys %$x} = values %$x if is_hashref($x);

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
            if (my $e = $EVAL_ERROR) {
                #warn $e if $e;
                my $sep = 'in @INC';
                my @parts = split $sep, $e;
                push @use_base_errors, $parts[0] . $sep;
            }
        }
    }
    if (@use_base_errors) {
        push @use_base_errors, '@INC contains: ' . join ' ', @INC;
        warn join ("\n", @use_base_errors), "\n";
    }
    

    return;
}

add_lib_paths();
use_base();

#  should be extension load errors?
sub get_load_extension_errors {
    return wantarray ? @use_base_errors : [@use_base_errors];
}

#  need this for the pp build to work
use if $ENV{BDV_PP_BUILDING}, 'Biodiverse::Config::PARModules';


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

