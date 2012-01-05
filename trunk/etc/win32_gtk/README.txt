Compile Gtk2 for Perl under Win32 is a difficulty task. 
Gnome/Gtk suite is born to serve Linux world, however, warmheartedness persons complied libraries for Windows. Why not compile Gtk-perl to redound them?

Contact: vinocui@gmail.com

When I was first compiling gtk-perl for Windows, I spend 1 day or two to diagnostic where went wrong. library config file had to be modified, library name had to be modified...
This little tool just make things easier. However, essential manual task has to be done during the compilation.
I use StrawberryPerl as Perl environment since it has powerful dmake tool. 

STEPS)

Make directory modifications in file deploy.bat. Fill your StrawberryPerl PKG_CONFIG_PATH directory.

Run deploy.bat

Copy all contents under the generated ex directory to your StrawberryPerl/c/.

Run perl -MCPAN -e "install Glib";

Run perl -MCPAN -e "install Gtk2";

NOTE>>
   If anything goes wrong (99%) in the Glib or Gtk2 compiling time, just manually run 
   perl Makefile.PL
   dmake
   dmake install

   in cpan directory.
   the Cairo, Pango, Gtk2 may need manully compiliation.

TEST)

Try helloworld.pl to find whether things are going smoothly after Gtk2 has been successfully compiled and installed.

FAQ)
1) What do the scripts do?
   Download needed gnome win32 libs, dlls.
   Modify package config paths in file lib/pkgconfig/xxx.pc of each needed components like atk-dev_1.28.0, etc.

2) Is StrawberryPerl a MUST?
   No. The reason I choose StrawberryPerl is this distribution includes dmake chain and other useful GNU tools when building Perl modules under Windows.
   You can config Active Perl with the GNU tool chains but it may take long time.

NOTE:
It's not a easy thing to compile a Gtk2-perl under Win32. 
Think twice if you really want to write Window based scripts under Windows. 
Other wize, use it under Linux.


