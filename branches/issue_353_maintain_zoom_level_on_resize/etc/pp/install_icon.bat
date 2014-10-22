set PERL_DIR=C:\strawberry_51613_x64\perl
set PAR_PACKER_SRC=C:\strawberry_51613_x64\cpan\build\PAR-Packer-1.018-XUXam8
#set PAR_PACKER_SRC=C:\Users\shawn\.cpanm\work\1413669298.6540\PAR-Packer-1.022
set PAR_PACKER_SRC=C:\Users\shawn\.cpanm\work\1413679170.3976\PAR-Packer-1.022

set orig_folder=%~dp0

copy /Y C:\shawn\svn\biodiverse_trunk\bin\Biodiverse_icon.ico %PAR_PACKER_SRC%\myldr\winres\pp.ico
#copy /Y medias\jambon.rc $(PAR_PACKER_SRC)\myldr\winres\pp.rc
del %PAR_PACKER_SRC%\myldr\ppresource.coff
cd /D %PAR_PACKER_SRC%\myldr\ && perl Makefile.PL
cd /D %PAR_PACKER_SRC%\myldr\ && dmake boot.exe
cd /D %PAR_PACKER_SRC%\myldr\ && dmake Static.pm
attrib -R %PERL_DIR%\site\lib\PAR\StrippedPARL\Static.pm
copy /Y %PAR_PACKER_SRC%\myldr\Static.pm %PERL_DIR%\site\lib\PAR\StrippedPARL\Static.pm

cd /D %orig_folder%
