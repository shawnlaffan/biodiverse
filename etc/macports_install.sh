## THIS IS NOW REDUNDANT
## see the mac source installation instructions at
## https://github.com/shawnlaffan/biodiverse/wiki/InstallationMacOSSource

#!/usr/bin/sh

#  All the macports install commands in one script
#  It is simplest to run it under sudo, but you will be prompted for the 
#    password by the first command anyway.  

sudo port install p5-Gtk3-gladexml
sudo port install p5-gnome2-canvas
sudo port install gdal

sudo /opt/local/bin/perl -MCPAN -e 'install LWP::Simple'
sudo /opt/local/bin/perl -MCPAN -e 'install Task::Biodiverse::NoGUI'
sudo /opt/local/bin/perl -MCPAN -e 'install Task::Biodiverse'
# repeat this command as one of the libs is not installed on the first go
sudo /opt/local/bin/perl -MCPAN -e 'install Task::Biodiverse'
