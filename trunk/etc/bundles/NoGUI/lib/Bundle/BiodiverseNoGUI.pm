package Bundle::BiodiverseNoGUI;

use strict;
use warnings;

#use vars qw($VERSION);
our $VERSION = '0.16';



1;

__END__

=head1 NAME

Bundle::BiodiverseNoGUI - Bundle to install Biodiverse dependencies for non-GUI use

=head1 SYNOPSIS

  #  on Windows:
  perl -MCPAN -e 'install Bundle::BiodiverseNoGUI'
  
  #  on most other platforms:
  sudo perl -MCPAN -e 'install Bundle::BiodiverseNoGUI'

=head1 CONTENTS

Data::DumpXML

Math::Random::MT::Auto

Devel::Symdump

Text::CSV_XS

DBD::XBase

HTML::QuickTable

YAML::Syck

PadWalker

Clone

Regexp::Common

lib

mylib

parent

Readonly

URI::Escape::XS

Geo::Converter::dms2dd

Statistics::Descriptive

Text::Wrapper

Exporter::Easy

Exception::Class

Math::Polygon

Class::ISA

=head1 DESCRIPTION

Bundle file for Biodiverse dependencies for non-GUI use across all platforms.

See Bundle::Biodiverse for the additional libs needed by the GUI.

See L<http://www.purl.org/biodiverse> for more details about Biodiverse itself.  


=head1 AUTHOR

Shawn Laffan
