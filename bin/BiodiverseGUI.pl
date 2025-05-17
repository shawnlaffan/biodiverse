use strict;
use warnings;
use Carp;

use 5.036;

#use File::Basename;
use Cwd;
use FindBin qw ( $Bin );
use Path::Class ();

BEGIN {
    #  make sure menubars are visible when running under Ubuntu Unity
    $ENV{UBUNTU_MENUPROXY} = undef;

    #  if running under PAR on a mac
    if ($^O eq 'darwin' && $ENV{PAR_0}) {
        say '++++';
        my $gdk_base = ("$ENV{PAR_TEMP}/inc/gdk-pixbuf-2.0/2.10.0");
        $ENV{GDK_PIXBUF_MODULEDIR}
          = Path::Class::file ($gdk_base, 'loaders');
        say "Setting GDK_PIXBUF_MODULEDIR to $ENV{GDK_PIXBUF_MODULEDIR}";
        say "BUT IT DOES NOT EXIST" if !-d $ENV{GDK_PIXBUF_MODULEDIR};
        my $gdk_cache_file
          = Path::Class::file ($gdk_base, 'loaders.cache');
        say "Setting GDK_PIXBUF_MODULE_FILE to $gdk_cache_file";
        $ENV{GDK_PIXBUF_MODULE_FILE} = $gdk_cache_file;
        $ENV{PATH} = "$ENV{PAR_TEMP}/inc:" . $ENV{PATH};
        use File::Which;
        my $loc = which ('gdk-pixbuf-query-loaders');
        say 'gdk-pixbuf-query-loaders is at ' . $loc;
        say 'running gdk-pixbuf-query-loaders system calls';
        my $cache = `$loc`;
        warn "system call to $loc failed: $?"
          if $?;
        system ('gdk-pixbuf-query-loaders', '--update-cache') == 0
          or warn "++++ could not update gdk-pixbuf-query-loaders cache: $?";
        say '++++';
    }
}



#no warnings 'redefine';
no warnings 'once';
use English qw { -no_match_vars };
our $VERSION = '4.99_002';

local $OUTPUT_AUTOFLUSH = 1;


#  add the lib folder if needed
use if !$ENV{PAR_0} => 'rlib';

say '@INC: ', join q{ }, @INC;

#  load up the user defined libs and settings
use Biodiverse::Config;
use Biodiverse::GUI::GUIManager;

say "\n\nUsing Biodiverse engine version $Biodiverse::Config::VERSION";

#  load Gtk
use Gtk3;
Gtk3::disable_setlocale; # leave LC_NUMERIC alone

# my $icontheme = Gtk3::IconTheme->new;
# use List::Util qw /uniq/;
# say join "\n", 'Icon themes: ', uniq $icontheme->get_search_path;
# say join "\n", 'Gtk3 RC files: ', Gtk3::Rc->get_default_files;

Gtk3->init;

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

## query the locale
#BEGIN {
    #use POSIX qw /locale_h/;
    #my $locale = setlocale(LC_ALL);
    #say "\nCurrent perl numeric locale is: $locale";
    #my $locale_values = localeconv();
    #if ($locale_values->{decimal_point} eq ',') {
    #    say 'Locale uses a comma as the decimal separator';
    #}
    my $num = sprintf "%.3f", 3.14;
    if ($num =~ /,/) {
        say 'Locale uses a comma as the decimal separator';
    }
#}


#my $eval_result;

my $icon = get_iconfile();
my $eval_result = eval {
    Gtk3::Window::set_default_icon_from_file($icon)
};
#croak $EVAL_ERROR if $EVAL_ERROR;


###########################
# Create the UI

my $gui = Biodiverse::GUI::GUIManager->instance;

my $ui_dir = get_ui_path();
$gui->set_gtk_ui_path($ui_dir);

my $builder = eval { get_main_window($gui); };
croak $EVAL_ERROR if $EVAL_ERROR;

my $user_data;
$builder->connect_signals($user_data, 'Biodiverse::GUI::Callbacks');

# Initialise the GUI Manager object
$gui->set_glade_xml($builder);

$gui->init();

if ( defined $filename ) {
    $filename = Path::Class::file($filename)->absolute->stringify;
    $gui->open($filename);
}

#  hack for exe building under github actions
if (!($^O eq 'darwin' && $ENV{BDV_PP_BUILDING})) {
    # Go!
    Gtk3->main;
}

#  go back home (unless it has been deleted while we were away)
$eval_result = eval { chdir($caller_dir) };
croak $EVAL_ERROR if $EVAL_ERROR;

exit;

################################################################################

sub get_main_window {
    my $gui = shift;
    my $dlgxml = Gtk3::Builder->new();
    $dlgxml->add_from_file($gui->get_gtk_ui_file('wndMain.ui'));
    return $dlgxml;
}

sub usage {
    print STDERR << "END_OF_USAGE";
Biodiverse - A spatial analysis tool for species (and other) diversity.

usage: $0 <filename>

  filename: name of Biodiverse Project, BaseData, Tree or Matrix file to open\n
            (bps, bds, bts or bms extension)
END_OF_USAGE

    exit();
}

sub get_ui_path {
    my $ui_path;

    #  get the one we're compiled with (if we're a PAR exe file)
    if ($ENV{PAR_0}) {  #  we are running under PAR
        $ui_path = Path::Class::file ($ENV{PAR_TEMP}, 'inc', 'ui');
        my $ui_path_str = $ui_path->stringify;
        say "Using PAR ui path: $ui_path";
        return $ui_path_str;
    }

    #  get the ui path relative to $Bin
    $ui_path = Path::Class::file( $Bin, 'ui' )->stringify;
    if (! -e $ui_path) {
        $ui_path = Path::Class::file( $Bin, 'bin', 'ui', )->stringify;
    }

    die 'Cannot find glade the ui directory' if ! -d $ui_path;

    say "Using ui files in $ui_path";

    return $ui_path;
}


sub get_iconfile {

    my $icon;

    if ($ENV{PAR_0}) {  #  we are running under PAR
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

            my $success = $zip->extractMember ( $fname, $icon_str );

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


=head1 AUTHORS

Shawn Laffan, Eugene Lubarsky, Dan Rosauer, Anthony Knittel, Michael Zhou,
Anderson Ku, Luke Fitzpatrick, Jason Mumbulla

=head1 LICENSE

    LGPL

=cut
