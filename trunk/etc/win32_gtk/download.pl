#! d:/strawberry/perl/bin/perl.exe
use HTTP::Request;
use LWP::UserAgent;
require "lwp-download";

###########
## 
##  To do:  
##     1.  Use the Gtk+ bundle files for all except Glade and GnomeCanvas and their deps 
##         (although only Glade and GnomeCanvas need strictly be done since there are good ppms at sisyphusion.tk)
##     2.  Try for 64 builds.  Only really need to do GnomeCanvas since ppms exist for all others (sisyphusion.tk again)
## 
###########

#$wget = "utility/bin/wget.exe";
$base_url = "http://ftp.gnome.org/pub/gnome/binaries/win32";
$dep_url = "dependencies";
$g_canvas_url = "libgnomecanvas/2.30/";
$gtk_url = "gtk+/2.24";
$glade_url = "libglade/2.6/";
#$atk_url = "atk/1.32";
$libart_url = "libart_lgpl/2.3/";
$icon_theme_url = "gnome-icon-theme/2.24";

@pkgs_url = (
    "$gtk_url/gtk+-bundle_2.24.8-20111122_win32.zip",

    "$icon_theme_url/gnome-icon-theme-dev_2.24.0-1_win32.zip",
    "$icon_theme_url/gnome-icon-theme_2.24.0-1_win32.zip",

    "$dep_url/hicolor-icon-theme-dev_0.10-1_win32.zip",
    "$dep_url/hicolor-icon-theme_0.10-1_win32.zip",
    "$dep_url/libxml2-dev_2.7.7-1_win32.zip",
    "$dep_url/libxml2_2.7.7-1_win32.zip",

    "$g_canvas_url/libgnomecanvas-dev_2.30.1-1_win32.zip",
    "$g_canvas_url/libgnomecanvas_2.30.1-1_win32.zip",

    "$libart_url/libart-lgpl-dev_2.3.21-1_win32.zip",
    "$libart_url/libart-lgpl_2.3.21-1_win32.zip",

    "$glade_url/libglade-dev_2.6.4-1_win32.zip",
    "$glade_url/libglade_2.6.4-1_win32.zip",
    
    
    #"$atk_url/atk_1.32.0-2_win32.zip",
    #"$atk_url/atk-dev_1.32.0-2_win32.zip",
);

$pkg_dir = "packages";
mkdir $pkg_dir if( ! -d $pkg_dir );
foreach (@pkgs_url){
    $pkg_name = $_;	
    $pkg_name =~ s/(.*)(\/)(.*)$/$3/;

    if (-e "$pkg_dir/$pkg_name") {
        print "Already downloaded $pkg_name\n";
        next;
    }

    print "Getting ", $pkg_name, "...\n";

    &lwp_download($base_url . "/" . $_, $pkg_dir);
}

