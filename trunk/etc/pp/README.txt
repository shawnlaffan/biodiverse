Heavy.pm.patch needs to be applied to
C:\strawberry\perl\vendor\lib\PAR\Heavy.pm
It causes DLLs to be extracted with their original names instead of CRCs.
Needed for GTK modules to work properly.

Also need to add the following lines before the open is attempted.
This avoids duplicate DLL file names in modules ending in XS.  

### DIRTY HACK 
if (-e $filename && not $filename =~ /Glib|Gtk2|Gnome|Pango|Cairo/) {
    $filename .= $member->crc32String; #  kludge workaround
}

Makefile.PL.patch needs to be applied to PAR-Packer-1.013
This patch doesn't change the behaviour. It is just needed to make it build
under x86_64.
Derived from http://www.nntp.perl.org/group/perl.par/2012/03/msg5310.html
(It has been fixed upstream in PAR-Packer-1.014.)

NOTE: The order is important. PAR-Packer needs to be (re)built/installed
      after Heavy.pm has been modified, since it gets embedded in some
      binaries.

= The above is only relevant if you are not using the PPMs in ..\ppm\ppm516*

Run "..\etc\pp\build.bat" when you are in the bin directory to generate
BiodiverseGUI.exe.

The following DLLs from Strawberry Perl need
to be distributed with BiodiverseGUI.exe:

libstdc++-6.dll
libexpat-1__.dll

On 32-bit, libgcc_s_sjlj-1.dll, additionally needs to be distributed.

The win_gtk_builds\etc\win(32|64)\c tree also needs to be distributed as
"gtk".
The "include" directory can be omitted.