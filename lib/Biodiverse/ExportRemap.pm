package Biodiverse::ExportRemap;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.99_006';

use English( -no_match_vars );

use Glib;
use Gtk2;
use Cwd;

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::ParametersTable;
use Biodiverse::GUI::YesNoCancel;


sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}


# given a hash mapping from one set of labels to another, exports them
# to a csv file.
sub export_remap {
    my ($self, %args) = @_;
    my %remap = %{$args{remap}};
    
    say "\n\nexporting remap:";
    foreach my $key (sort keys %remap) {
        say "$key -> $remap{$key}";
    }

    # call into the Export system here

    
}


1;
