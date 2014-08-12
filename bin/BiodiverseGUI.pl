#! /usr/bin/perl
#!perl

use strict;
use warnings;
use Carp;

use 5.010;

#no warnings 'redefine';
no warnings 'once';
use English qw { -no_match_vars };
our $VERSION = '0.99_002';

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

use Data::Dumper;
use Scalar::Util qw/blessed/;

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

#my $ic = Gtk2::IconTheme->new;
#$ic->prepend_search_path(File::Spec->catfile( $Bin, '..', 'gtk/share/icons' ));
#print join "\n", $ic->get_search_path;

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
        $gladefile = Path::Class::file ($ENV{PAR_TEMP}, 'inc', 'glade', 'biodiverse.glade')->stringify;
        if (-e $gladefile) {
            say "Using PAR glade file $gladefile";
            return $gladefile;
        }
        else {
            say "Cannot locate $gladefile";
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

    croak 'Cannot find glade file biodiverse.glade' if ! -e $gladefile;

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

        print "Using perlapp icon file\n";

        return $icon;
    }
    elsif ($ENV{PAR_0}) {  #  we are running under PAR
        $icon = Path::Class::file ($ENV{PAR_TEMP}, 'inc', 'Biodiverse_icon.ico')->stringify;
        if (-e $icon) {
            print "Using PAR icon file $icon\n";
            return $icon;
        }
        else {
            print "Cannot locate $icon\n";
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
