package Task::Biodiverse;

use strict;
use warnings;

our $VERSION = '0.19';


1;

__END__

=head1 NAME

Task::Biodiverse - Task to install Biodiverse dependencies.


=head1 SYNOPSIS

  perl -MCPAN -e "install Task::Biodiverse"


=head1 DESCRIPTION

Task to install Biodiverse dependencies.
The L<Gnome2::Canvas> dependency does not install cleanly on all platforms so might
need to be manually installed.
See L<http://code.google.com/p/biodiverse/wiki/Installation> for more details for your platform.

See L<http://www.purl.org/biodiverse> for more details about Biodiverse itself.  

=head1 AUTHOR

Shawn Laffan
