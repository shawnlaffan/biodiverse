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

    # start by doing just the labels, add in the groups later.
    my %el_props_hash = $bd->get_all_element_properties();
    %el_props_hash = %{$el_props_hash{labels}};

    #say "el_props_hash:";
    #use Data::Dumper;
    #print Dumper(\%el_props_hash);

    # break up into a hash mapping from the property name to a hash
    # mapping from element name to value
    %el_props_hash = 
        $self->format_element_properties_hash( props_hash => \%el_props_hash );
    

}

# given a hash mapping from element name to a hash mapping from
# property name to value. Convert this to a hash mapping from property
# name to a hash mapping from element name to value.
sub format_element_properties_hash {
    my ($self, %args) = @_;
    my %old_hash = %{$args{props_hash}};
    my %new_hash;

    foreach my $element (keys %old_hash) {
        foreach my $prop (keys %{ $old_hash{$element} }) {
            my $value = $old_hash{$element}->{$prop};
            $new_hash{$prop}->{$element} = $value;
        }
    }

    # say "new_hash:";
    # use Data::Dumper;
    # print Dumper(\%new_hash);

    return wantarray ? %new_hash : \%new_hash;
}
