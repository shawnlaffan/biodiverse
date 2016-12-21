package Biodiverse::ExportRemap;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.99_006';

use English( -no_match_vars );

use Glib;
use Gtk2;
use Cwd;


use Biodiverse::GUI::Export qw /:all/;


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

    # choose the filepath to export to
    my $gui = Biodiverse::GUI::GUIManager->instance;
    
    my $results = Biodiverse::GUI::Export::choose_file_location_dialog (
        gui => $gui,
        params => undef,
        selected_format => "CSV",
        );

    return if (!$results->{success});

    my $chooser = $results->{chooser};
    my $parameters_table = $results->{param_table};
    my $extractors = $results->{extractors};
    my $dlg = $results->{dlg};
    
    my $filename = $chooser->get_filename();
    $filename = Path::Class::File->new($filename)->stringify;  #  normalise the file name

    say "Found export filename $filename";
    
    $dlg->destroy;
    $gui->activate_keyboard_snooper (1);

}


1;
