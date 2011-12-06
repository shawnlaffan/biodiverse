#! /usr/bin/perl
#!perl

use strict;
use warnings;

#no warnings 'redefine';
no warnings 'once';
use English qw { -no_match_vars };
our $VERSION = '0.16';

local $| = 1;

use File::Spec;
use File::Basename;
use Cwd;
use FindBin qw ( $Bin );

use Carp;

#  are we running as a PerlApp executable?
my $perl_app_tool = $PerlApp::TOOL;

#  add the lib folder if needed
use lib File::Spec->catfile( $Bin, '..', 'lib');
eval 'use mylib';

#use Blah::Blah;

#  load up the user defined libs
use Biodiverse::Config qw /use_base add_lib_paths/;
BEGIN {
    add_lib_paths();
    use_base();
}

#  load Gtk
use Gtk2;    # -init;
Gtk2->init;

use Gtk2::GladeXML;
use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Callbacks;


# Load filename specified in the arguments
my $numargs = scalar @ARGV;
my $filename;
my $caller_dir = cwd;    #  could cause drive problems

if ( $numargs == 1 ) {
    $filename = $ARGV[0];
    if ( $filename eq '--help' || $filename eq '-h' || $filename eq '/?' ) {
        usage();
    }
    elsif ( not( -e $filename and -r $filename ) ) {
        warn "  Error: Cannot read $filename\n";
        $filename = undef;

        #exit();
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
croak $EVAL_ERROR if $EVAL_ERROR;


###########################
# Create the UI


my $gladefile = get_gladefile();
my $gladexml = Gtk2::GladeXML->new( $gladefile, 'wndMain' );
$gladexml->signal_autoconnect_from_package('Biodiverse::GUI::Callbacks');

# Initialise the GUI Manager object
my $gui = Biodiverse::GUI::GUIManager->instance;
$gui->setGladeXML($gladexml);
$gui->setGladeFile($gladefile);
$gui->init();

if ( defined $filename ) {
    $filename = File::Spec->rel2abs($filename);
    my @file_path = fileparse($filename);
    chdir $file_path[1];
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
        print "Using perlapp glade file\n";
        return $gladefile;
    }

    #  get the glade file from ./glade or ./bin/glade
    $gladefile = File::Spec->catfile( $Bin, 'glade', 'biodiverse.glade' );
    if (! -e $gladefile) {
        $gladefile = File::Spec->catfile( $Bin, 'bin', 'glade', 'biodiverse.glade' );
    }
    if (! -e $gladefile) {  #  desperation
        $gladefile = File::Spec->catfile( $Bin, 'biodiverse.glade' );
    }

    croak 'Cannot find glade file biodiverse.glade' if ! -e $gladefile;

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

    $icon = File::Spec->catfile( $Bin, 'Biodiverse_icon.ico' );
    if (! -e $icon) {
        $icon = File::Spec->catfile( $Bin, 'bin', 'Biodiverse_icon.ico' );
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
