## Packing Gtk2 libs ##

The Heavy.pm.patch needs to be applied to PAR\Heavy.pm

Original source is https://rt.cpan.org/Ticket/Attachment/1135201/597366/Heavy.pm.patch
but this version contains a second step.

The first change in the patch means DLLs will be extracted with their original
names instead of CRCs, and is needed for GTK modules to work properly.
This is not a perfect approach, hence the second part. 

The second part of the patch avoids duplicate DLL file names for
non-Gtk modules, as otherwise those with the same ending would all
refer to the same file, e.g. List::BinarySearch::XS, YAML::XS
and URI::Escape::XS would all try to use XS.dll.


## Icon ##

The PAR libs need to be updated to use the Biodiverse icon.
Other solutions using Win32::EXE result in a slew of warnings
when first running the program.

Before building PAR, copy the Biodiverse icon file into the PAR build folders 
as $(PAR_PACKER_SRC)\myldr\winres\pp.ico


### Alternate icon approach ###

Adapt this code as needed (from http://www.zewaren.net/site/?q=node/116).
It is for a makefile, but seemed to have no effect when run independently using dmake.
Running each command in sequence did work, though (tweaking as appropriate).

```
PERL_DIR = C:\strawberry_51613_x64\perl
PAR_PACKER_SRC = C:\strawberry_51613_x64\cpan\build\PAR-Packer-1.018-XUXam8

all:
    copy /Y C:\shawn\svn\biodiverse_trunk\bin\Biodiverse_icon.ico $(PAR_PACKER_SRC)\myldr\winres\pp.ico
    #copy /Y medias\jambon.rc $(PAR_PACKER_SRC)\myldr\winres\pp.rc
    del $(PAR_PACKER_SRC)\myldr\ppresource.coff
    cd /D $(PAR_PACKER_SRC)\myldr\ && perl Makefile.PL
    cd /D $(PAR_PACKER_SRC)\myldr\ && dmake boot.exe
    cd /D $(PAR_PACKER_SRC)\myldr\ && dmake Static.pm
    attrib -R $(PERL_DIR)\site\lib\PAR\StrippedPARL\Static.pm
    copy /Y $(PAR_PACKER_SRC)\myldr\Static.pm $(PERL_DIR)\site\lib\PAR\StrippedPARL\Static.pm
```    


## Redundant ##

Old info below.

The patches are redundant for current versions, and the build script has been updated to copy relevant files across.  


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