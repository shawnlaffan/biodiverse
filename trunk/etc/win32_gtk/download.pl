#! d:/strawberry/perl/bin/perl.exe
use HTTP::Request;
use LWP::UserAgent;
require "lwp-download";

#$wget = "utility/bin/wget.exe";
$base_url = "http://ftp.gnome.org/pub/gnome/binaries/win32";
$atk_url = "atk/1.30";
$dep_url = "dependencies";
$pango_url = "pango/1.28";
$glib_url = "glib/2.24";
$gtk_url = "gtk+/2.20";
$g_canvas_url = "libgnomecanvas/2.30/";
$glade_url = "libglade/2.6/";
$libart_url = "libart_lgpl/2.3/";
@pkgs_url = (
    "$dep_url/libxml2-dev_2.7.7-1_win32.zip",
    "$dep_url/libxml2_2.7.7-1_win32.zip",
    "$atk_url/atk_1.30.0-2_win32.zip",
    "$atk_url/atk-dev_1.30.0-2_win32.zip",
    "$dep_url/gettext-runtime_0.18.1.1-2_win32.zip",
    "$dep_url/gettext-runtime-dev_0.18.1.1-2_win32.zip",
    "$dep_url/cairo-dev_1.10.0-1_win32.zip",
    "$dep_url/cairo_1.10.0-1_win32.zip",
    "$dep_url/expat-dev_2.0.1-1_win32.zip",
    "$dep_url/expat_2.0.1-1_win32.zip",
    "$dep_url/fontconfig-dev_2.8.0-2_win32.zip",
    "$dep_url/fontconfig_2.8.0-2_win32.zip",
    "$dep_url/freetype-dev_2.4.2-1_win32.zip",
    "$dep_url/freetype_2.4.2-1_win32.zip",
    "$dep_url/pkg-config_0.23-3_win32.zip",
    "$dep_url/libpng-dev_1.4.3-1_win32.zip",
    "$dep_url/libpng_1.4.3-1_win32.zip",
    "$dep_url/zlib-dev_1.2.5-2_win32.zip",
    "$dep_url/zlib_1.2.5-2_win32.zip",
    "$glib_url/glib-dev_2.24.2-2_win32.zip",
    "$glib_url/glib_2.24.2-2_win32.zip",
    "$gtk_url/gtk+-dev_2.20.1-3_win32.zip",
    "$gtk_url/gtk+_2.20.1-3_win32.zip",
    "$pango_url/pango-dev_1.28.1-2_win32.zip",
    "$pango_url/pango_1.28.1-2_win32.zip",
    "$g_canvas_url/libgnomecanvas-dev_2.30.1-1_win32.zip",
    "$g_canvas_url/libgnomecanvas_2.30.1-1_win32.zip",
    "$glade_url/libglade-dev_2.6.4-1_win32.zip",
    "$glade_url/libglade_2.6.4-1_win32.zip",
    "$libart_url/libart-lgpl-dev_2.3.21-1_win32.zip",
    "$libart_url/libart-lgpl_2.3.21-1_win32.zip",
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

