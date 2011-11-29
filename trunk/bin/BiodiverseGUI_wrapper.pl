#! /usr/bin/perl
#!perl

use strict;
use warnings;
use Carp;

#no warnings 'redefine';
no warnings 'once';
use English qw { -no_match_vars };
our $VERSION = '0.16';

local $| = 1;

use FindBin qw ( $Bin );

#  are we running as a PerlApp executable?
my $perl_app_tool = $PerlApp::TOOL;

my $script_name = 'BiodiverseGUI.pl';
my $script = File::Spec->catfile ($FindBin::Bin, $script_name);
my @script = ('perl', $script);

my $success = system (@script, @ARGV);
if ($CHILD_ERROR) {
    report_error();
}


exit;


sub report_error {
    #  load Gtk
    use Gtk2;    # -init;
    Gtk2->init;
    
    my $icon = get_iconfile();
    my $eval_result = eval {
        Gtk2::Window->set_default_icon_from_file($icon)
    };
    #croak $EVAL_ERROR if $EVAL_ERROR;

    my $message = "Biodiverse has failed for some reason.\n"
                . "It probably ran out of memory\n"
                . "See http://code.google.com/p/biodiverse/wiki/FAQ#I_get_an_Out_of_memory_error";
    my $dlg = Gtk2::Dialog->new (
        'Error',
        undef,
        'destroy-with-parent',
        'gtk-ok' => 'none',
    );
    my $label = Gtk2::Label->new ($message);
    $dlg->vbox->pack_start ($label, 0, 0, 0);

    # Ensure that the dialog box is destroyed when the user responds.
    $dlg->signal_connect (response => \&cleanup_and_exit );

    $dlg->show_all;

    # Go!
    Gtk2->main;

    return;
}

sub cleanup_and_exit {
    $_[0]->destroy;
    exit;  #  nasty way of doing things, but otherwise the script never finishes properly
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
