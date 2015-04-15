#! /usr/bin/perl
#!perl

use strict;
use warnings;
use Carp;

use 5.010;

BEGIN {
    #  make sure menubars are visible when running under Ubuntu Unity
    $ENV{UBUNTU_MENUPROXY} = undef;  
}

#no warnings 'redefine';
no warnings 'once';
use English qw { -no_match_vars };
our $VERSION = '0.99_008';

local $OUTPUT_AUTOFLUSH = 1;

#use File::Basename;
use Cwd;
use FindBin qw ( $Bin );
use Path::Class ();

#  are we running as a PerlApp executable?
my $perl_app_tool = $PerlApp::TOOL;

#  add the lib folder if needed
use rlib;

say '@INC: ', join q{ }, @INC;

#  load up the user defined libs and settings
use Biodiverse::Config;
use Biodiverse::GUI::GUIManager;

#  load Gtk
use Gtk2 qw/-init/;

use Gtk2::GladeXML;
use Biodiverse::GUI::Callbacks;

# Load filename specified in the arguments
my $numargs = scalar @ARGV;
my $filename;
my $caller_dir = cwd;    #  could cause drive problems

if ( $numargs == 1 ) {
    $filename = $ARGV[0];
    if ( $filename eq '--help' || $filename eq '-h' || $filename eq '/?' ) {
        usage();
        exit;
    }
    elsif ( not( -e $filename and -r $filename ) ) {
        warn "  Error: Cannot read $filename\n";
        $filename = undef;
    }
}
elsif ( $numargs > 1 ) {
    usage();
}

use POSIX qw(locale_h);
# query the locale
my $locale = setlocale(LC_ALL);
print "\nCurrent perl numeric locale is: " . $locale . "\n\n";

#my $eval_result;

my $icon = get_iconfile();
my $eval_result = eval {
    Gtk2::Window->set_default_icon_from_file($icon)
};
#croak $EVAL_ERROR if $EVAL_ERROR;


###########################
# Create the UI


my $gladefile = get_gladefile();
my $gladexml = eval {
    Gtk2::GladeXML->new( $gladefile, 'wndMain' );
};
croak $EVAL_ERROR if $EVAL_ERROR;
$gladexml->signal_autoconnect_from_package('Biodiverse::GUI::Callbacks');

# Initialise the GUI Manager object
my $gui = Biodiverse::GUI::GUIManager->instance;
$gui->set_glade_xml($gladexml);
$gui->set_glade_file($gladefile);
$gui->init();

if ( defined $filename ) {
    $filename = Path::Class::file($filename)->absolute->stringify;
    $gui->open($filename);
}


# Go!
Gtk2->main;


#  go back home (unless it has been deleted while we were away)
$eval_result = eval { chdir($caller_dir) };
croak $EVAL_ERROR if $EVAL_ERROR;

exit;

################################################################################

sub usage {
    print STDERR << "END_OF_USAGE";
Biodiverse - A spatial analysis tool for species (and other) diversity.

usage: $0 <filename>

  filename: name of Biodiverse Project, BaseData, Tree or Matrix file to open\n
            (bps, bds, bts or bms extension)
END_OF_USAGE

    exit();
}

sub get_gladefile {
    my $gladefile;

    #  get the one we're compiled with (if we're a perlapp exe file)
    if ( defined $perl_app_tool && $perl_app_tool eq 'PerlApp' ) {
        my $eval_result = eval {
            $gladefile = PerlApp::extract_bound_file('biodiverse.glade')
        };
        croak $EVAL_ERROR if $EVAL_ERROR;
        say 'Using perlapp glade file';
        return $gladefile;
    }
    elsif ($ENV{PAR_0}) {  #  we are running under PAR
        $gladefile = Path::Class::file ($ENV{PAR_TEMP}, 'inc', 'glade', 'biodiverse.glade');
        my $gladefile_str = $gladefile->stringify;
        if (-e $gladefile_str) {
            say "Using PAR glade file $gladefile";
            return $gladefile_str;
        }
        else {
            #  manually unpack the glade folder contents
            require Archive::Zip;

            my $glade_folder = $gladefile->dir;
            my $zip = Archive::Zip->new($ENV{PAR_PROGNAME}) or die "Unable to open $ENV{PAR_PROGNAME}";
            my $glade_zipped = $zip->extractTree( 'glade', $glade_folder );

            if (-e $gladefile && -s $gladefile_str) {
                say "Using PAR glade file $gladefile";
                return $gladefile_str;
            }
            else {
                say '=============';
                say "Cannot locate $gladefile";
                say 'This can happen if your temp directory is cleaned while '
                    . 'you are running Biodiverse.  Deleting the par temp directory '
                    . 'should fix this issue. (e.g. Temp\par-123456789abcdef in the path above).';
                say '=============';
            }
        }
    }

    #  get the glade file from ./glade or ./bin/glade
    $gladefile = Path::Class::file( $Bin, 'glade', 'biodiverse.glade' )->stringify;
    if (! -e $gladefile) {
        $gladefile = Path::Class::file( $Bin, 'bin', 'glade', 'biodiverse.glade' )->stringify;
    }
    if (! -e $gladefile) {  #  desperation
        $gladefile = Path::Class::file( $Bin, 'biodiverse.glade' )->stringify;
    }

    die 'Cannot find glade file biodiverse.glade' if ! -e $gladefile;

    say "Using $gladefile";

    return $gladefile;
}

sub get_iconfile {

    my $icon;

    if ( defined $perl_app_tool && $perl_app_tool eq 'PerlApp') {
        my $eval_result = eval {
            $icon = PerlApp::extract_bound_file('Biodiverse_icon.ico')
        };
        croak $EVAL_ERROR if $EVAL_ERROR;

        say "Using perlapp icon file";

        return $icon;
    }
    elsif ($ENV{PAR_0}) {  #  we are running under PAR
        $icon = Path::Class::file ($ENV{PAR_TEMP}, 'inc', 'Biodiverse_icon.ico');
        my $icon_str = $icon->stringify;
        if (-e $icon_str) {
            say "Using PAR icon file $icon";
            return $icon_str;
        }
        else {
            #  manually unpack the icon file
            require Archive::Zip;

            my $folder = $icon->dir;
            my $fname  = $icon->basename;
            my $zip = Archive::Zip->new($ENV{PAR_PROGNAME})
              or die "Unable to open $ENV{PAR_PROGNAME}";

            my $glade_zipped = $zip->extractMember ( $fname, $icon_str );

            if (-e $icon) {
                say "Using PAR icon file $icon";
                return $icon_str;
            }
            else {
                say "Cannot locate $icon in the PAR archive";
            }
        }
    }

    $icon = Path::Class::file( $Bin, 'Biodiverse_icon.ico' )->stringify;
    if (! -e $icon) {
        $icon = Path::Class::file( $Bin, 'bin', 'Biodiverse_icon.ico' )->stringify;
    }
    if ( ! -e $icon) {
        $icon = undef;
    }

    return $icon;
}


#  keep the console open if we have a failure
END {
    if ($?) {
        say "\n\n=====  Program terminated abnormally.  ====\n\n";
        say 'Press any key to continue.';
        <STDIN>;
    }
    #else {
        #$gui->destroy;  #  need to close the gui if we stay open always
    #}
}


__END__

=head1 NAME

BiodiverseGUI.pl

=head1 DESCRIPTION

A spatial analysis tool for researchers working on issues of species (and other) diversity

This is the main script to run the GUI.

See http://www.purl.org/biodiverse for more details.

=head1 SYNOPSIS

    perl BiodiverseGUI.pl projectfile.bps

    perl BiodiverseGUI.pl basedatafile.bds

    perl BiodiverseGUI.pl treefile.bts

    perl BiodiverseGUI.pl matrixfile.bms


=head1 AUTHOR

Shawn Laffan, Eugene Lubarsky and Dan Rosauer

=head1 LICENSE

    LGPL

=cut
