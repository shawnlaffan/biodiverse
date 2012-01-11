package Bundle::Biodiverse;

use strict;
use warnings;

#use vars qw($VERSION);
our $VERSION = '0.16';


1;

__END__

=head1 NAME

Bundle::Biodiverse - Bundle to install Biodiverse dependencies.


=head1 SYNOPSIS

  #  on Windows:
  perl -MCPAN -e 'install Bundle::Biodiverse'
  
  #  on most other platforms:
  sudo perl -MCPAN -e 'install Bundle::Biodiverse'

=head1 CONTENTS

Bundle::BiodiverseNoGUI

Geo::ShapeFile

Tree::R

Gtk2::GladeXML

Browser::Open

LWP


=head1 DESCRIPTION

CPAN Bundle file for Biodiverse dependencies across all platforms.
This does not include the Gtk dependencies as they don't load cleanly on all platforms.

See L<http://www.purl.org/biodiverse> for more details about Biodiverse itself.  

=head1 AUTHOR

Shawn Laffan
