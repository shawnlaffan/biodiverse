Heavy.pm.patch needs to be applied to
C:\strawberry\perl\vendor\lib\PAR\Heavy.pm
It causes DLLs to be extracted with their original names instead of CRCs.
Needed for GTK modules to work properly.

Makefile.PL.patch needs to be applied to PAR-Packer-1.013
This patch doesn't change the behaviour. It is just needed to make it build
under x86_64.
Derived from http://www.nntp.perl.org/group/perl.par/2012/03/msg5310.html

NOTE: The order is important. PAR-Packer needs to be (re)built/installed
      after Heavy.pm has been modified, since it gets embedded in some binaries.