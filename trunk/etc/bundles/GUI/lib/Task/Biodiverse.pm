package Task::Biodiverse;

use strict;
use warnings;

our $VERSION = '0.16001';


1;

__END__

=head1 NAME

Bundle::Biodiverse - Bundle to install Biodiverse dependencies.


=head1 SYNOPSIS

  #  on Windows:
  perl -MCPAN -e 'install Task::Biodiverse'
  
  #  on most other platforms:
  sudo perl -MCPAN -e 'install Task::Biodiverse'


=head1 DESCRIPTION

Task to install Biodiverse dependencies across all platforms.
This does not include the Gtk dependencies as they don't load cleanly on all platforms.

See L<http://www.purl.org/biodiverse> for more details about Biodiverse itself.  

=head1 AUTHOR

Shawn Laffan
