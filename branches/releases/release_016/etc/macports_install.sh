#!/usr/bin/sh

#  All the macports install commands in one script
#  It is simplest to run it under sudo, but you will be prompted for the 
#    password by the first command anyway.  

sudo port install p5-gtk2-gladexml
sudo port install p5-gnome2-canvas

sudo /opt/local/bin/perl -MCPAN -e 'install LWP::Simple'
sudo /opt/local/bin/perl -MCPAN -e 'install Bundle::BiodiverseNoGUI'
sudo /opt/local/bin/perl -MCPAN -e 'install Bundle::Biodiverse'
# repeat this command as one of the libs is not installed on the first go
sudo /opt/local/bin/perl -MCPAN -e 'install Bundle::BiodiverseNoGUI'
