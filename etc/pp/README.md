## Updating the exe icon ##

The PAR libs need to be updated to use the Biodiverse icon.
Other solutions using Win32::EXE result in a slew of warnings
when first running the program.

Before building PAR::Packer, copy the Biodiverse icon file into the 
PAR::Packer build folders as $(PAR_PACKER_SRC)\myldr\winres\pp.ico.

Then build with the usual Makefile/gmake process.


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
