Derived from http://code.google.com/p/gtk-perl-compiler/
Modified for Biodiverse dependencies (Gnome2::Canvas, Glade etc.)
Assumes you don't have a PPM repo you can just download them from.  
If you do then edit the download.pl file to only get the libraries you need (and their dependencies).

STEPS)

1.  Modify environment variables in deploy.bat as appropriate.

2.  Run deploy.bat

3.  Run perl -MCPAN -e "force install Glib";

4.  Run perl -MCPAN -e "install Gtk2";


NOTE>>
   If anything goes wrong (99%) then you will need to manually run the following in the relevant cpan subdirectory (probably in c:\perl\cpan, depending on your installation).

   perl Makefile.PL
   dmake
   dmake install

TEST)

Try running BiodiverseGUI.pl.

FAQ)
1) What do the scripts do?
   Download gnome win32 libs and dlls.
   Modify package config paths in file lib/pkgconfig/xxx.pc of each needed components like atk-dev_1.28.0, etc.

2) Is StrawberryPerl a MUST?
   No. The Biodiverse version is developed for ActivePerl.
   Make sure you install the mingw package first using ppm so you have a C compiler and dmake that work with that version of perl.
	ppm install mingw

