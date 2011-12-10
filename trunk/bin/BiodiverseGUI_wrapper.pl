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

print "Running Biodiverse via wrapper\n";

use FindBin qw ( $Bin );

#  are we running as a PerlApp executable?
my $perl_app_tool = $PerlApp::TOOL;

my $script_name = 'BiodiverseGUI.pl';
my $script = File::Spec->catfile ($FindBin::Bin, $script_name);
my @script = ('perl', $script);

use IPC::Open3;
use Symbol qw(gensym);
use IO::File;
my $out = gensym;
my $catcherr = gensym;

#  need to make sure that STDOUT goes to both the screen and the log file

my $pid = open3(gensym, ">&STDOUT", $catcherr, @script, @ARGV);
waitpid($pid, 0);

my $child_exit_status = $? >> 8;

if ($child_exit_status ) {
    my $err = "Child exit status is $child_exit_status\n\n";
    if ($catcherr) {
        seek $catcherr, 0, 0;
        while( <$catcherr> ) {
            $err .= $_;
        }
    }

    report_error($err);
}

exit;


sub report_error {
    my $error = shift;

    #if ($error == -1) {
    #    $error = 'Child process failed to start';
    #}
    #elsif ($error & 127) {
    #    $error = "Child process died with signal " . ($error & 127) . "\n";
    #}
    #
    if ($error =~ /memory/) {
        $error .= "\n\n"
                . "See http://code.google.com/p/biodiverse/wiki/FAQ#I_get_an_Out_of_memory_error\n";
    }
    elsif ($error =~ /Can't locate (\S+)/) {
        my $lib = $1;
        $lib =~ s{/}{::};
        $lib =~ s/\.pm$//;
        $error .= "\n\nYou probably need to install a dependency library called $lib.\n\n";
        $error .= "See the source code installation page for your operating system at "
                . "http://code.google.com/p/biodiverse/wiki/Installation";
    }

    #warn $error;

    #  load Gtk
    use Gtk2;    # -init;
    Gtk2->init;
    
    my $icon = get_iconfile();
    my $eval_result = eval {
        Gtk2::Window->set_default_icon_from_file($icon)
    };
    #croak $EVAL_ERROR if $EVAL_ERROR;

    my $message = "Biodiverse has failed with error.\n\n"
                . "$error\n";
    my $dlg = Gtk2::Dialog->new (
        'Error',
        undef,
        'destroy-with-parent',
        'gtk-ok' => 'none',
    );
    my $label = Gtk2::Label->new ($message);
    $label->set_selectable (1);
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
    Gtk2->main_quit();
    #exit;  #  nasty way of doing things, but otherwise the script never finishes properly
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
