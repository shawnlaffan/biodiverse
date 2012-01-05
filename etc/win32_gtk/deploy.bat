:: Based on the "gtk2-perl-compiler 0.1.0 by vinocui@gmail.com"
:: See http://code.google.com/p/gtk-perl-compiler/ for the original
:: shawnlaffan@gmail.com 05Jan2012

rem Edit these as appropriate
set PKG_CONFIG_PATH=.\c\lib\pkgconfig
set PATH=C:\Perl514_x64\bin;%PATH%

@perl download.pl
@perl extract.pl
@perl rename.pl
@perl modpc.pl

set PATH=.\ex\bin;%PATH%
set PKG_CONFIG_PATH=.\ex\lib\pkgconfig
:: @echo Add ex/bin to your path variable.
@echo Then run: 
@echo          perl -MCPAN -e "force install Glib"
@echo          perl -MCPAN -e "install Gtk2"
@echo          perl -MCPAN -e "install Gnome2::Canvas"
@echo          perl -MCPAN -e "install Gtk2::GladeXML"
@echo          perl -MCPAN -e "install Bundle::BiodiverseNoGUI"
@echo          perl -MCPAN -e "install Bundle::Biodiverse"
@echo
@echo and anything else it complains of
@echo If anything goes wrong, just go to your Strawberry/cpan directory, compile that module manually.
@echo Sometimes the CPAN module seems not pretty smart enough.
@echo Run "perl helloworld.pl", if a small window pops up without error, the Gtk2-perl has been successfully installed!
@echo Please post any problems to the Biodiverse Users mailing list
@echo http://groups.google.com/group/biodiverse-users
@pause