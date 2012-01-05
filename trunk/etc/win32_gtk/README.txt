Derived from http://code.google.com/p/gtk-perl-compiler/
Modified for Biodiverse dependencies (Gnome2::Canvas, Glade etc.)

STEPS)

Modify environment variables in deploy.bat as appropriate.

Run deploy.bat

Add 

Run perl -MCPAN -e "force install Glib";

Run perl -MCPAN -e "install Gtk2";

NOTE>>
   If anything goes wrong (99%) in the Glib or Gtk2 compiling time, just manually run 
   perl Makefile.PL
   dmake
   dmake install

   in cpan directory.
   the Cairo, Pango, Gtk2 may need manual compiliation.

TEST)

Try helloworld.pl to find whether things are going smoothly after Gtk2 has been successfully compiled and installed.

FAQ)
1) What do the scripts do?
   Download gnome win32 libs and dlls.
   Modify package config paths in file lib/pkgconfig/xxx.pc of each needed components like atk-dev_1.28.0, etc.

2) Is StrawberryPerl a MUST?
   No. The Biodiverse version is developed for ActivePerl.
   Make sure you install the mingw package first so you have a C compiler and dmake that work with that version of perl.
	ppm install mingw

