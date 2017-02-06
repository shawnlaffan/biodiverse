package Biodiverse::GUI::DeleteElementProperties;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.99_006';

use Gtk2;
use Biodiverse::RemapGuesser qw/guess_remap/;

use Biodiverse::GUI::GUIManager;

use Scalar::Util qw /blessed/;

use constant DEFAULT_DIALOG_HEIGHT => 600;
use constant DEFAULT_DIALOG_WIDTH => 600;


sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

# given a basedata, run a dialog that shows all the element properties
# associated with the basedata, and allows the user to delete
# some. Then returns which element properties are to be deleted
# (details TBA) so the basedata itself can do the deleting.
sub run {
    my ( $self, %args ) = @_;
    my $bd = $args{basedata};

    say "LUKE: in run_delete_element_properties_gui";
    
    # first build up the data structures to populate the gui.

    my %el_props_hash = $bd->get_all_element_properties();

    say "el_props_hash:";
    use Data::Dumper;
    print Dumper(\%el_props_hash);
    

}
