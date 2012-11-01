Heavy.pm.patch needs to be applied to
C:\strawberry\perl\vendor\lib\PAR\Heavy.pm
It causes DLLs to be extracted with their original names instead of CRCs.
Needed for GTK modules to work properly.

Makefile.PL.patch needs to be applied to PAR-Packer-1.013
This patch doesn't change the behaviour. It is just needed to make it build
under x86_64.
Derived from http://www.nntp.perl.org/group/perl.par/2012/03/msg5310.html

NOTE: The order is important. PAR-Packer needs to be (re)built/installed
      after Heavy.pm has been modified, since it gets embedded in some
      binaries.

The following DLLs from Strawberry Perl need
to be distributed with BiodiverseGUI.exe:

libstdc++-6.dll
libexpat-1__.dll

These files from the Biodiverse bin directory need to be included:
Biodiverse_icon.ico
glade/biodiverse.glade
glade/biodiverse.gladep

Of course, the win_gtk_builds\etc\win(32|64)\c tree also needs to be included.
The include directory can be omitted.