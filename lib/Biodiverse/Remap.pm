package Biodiverse::Remap;

use strict;
use warnings;
use Carp;
use 5.016;

use Data::Dumper;

our $VERSION = '1.99_006';

use parent qw /Biodiverse::ElementProperties/;


# given a hash mapping from one set of labels to another, fills out
# this object with that remap.
sub populate_from_hash {
    my ($self, %args) = @_;
    my $hash = $args{remap_hash};

    # build the basestruct ready for export
    my $quotes = "'";
    my $sep = ":";
    
    my $csv_out = $self->get_csv_object (
        sep_char => $sep,
        quote_char => $quotes,
        );
    
    foreach my $key (keys %$hash) {
        # create an element for this remap
        my @in_cols = ($key);

        my $element = $self->list2csv (
            list       => \@in_cols,
            csv_object => $csv_out,
            );

        $self->add_element (
            element    => $element,
            csv_object => $csv_out,
            );

        my $properties_hash;
        $properties_hash->{REMAP} = $hash->{$key};

        $self->add_to_lists (element => $element, PROPERTIES => $properties_hash);
    }
}

# returns a hash of the remap this object represents.
sub to_hash {
    my ($self, %args) = @_;

    my %remap_hash = ();
    
    my $elements = $self->get_element_list;
    
    foreach my $element (@$elements) {
        my $remapped = $self->get_element_remapped(element => $element);
        $remap_hash{$element} = $remapped;
    }
    
    return wantarray ? %remap_hash : \%remap_hash;
}



# hopefully don't need a separate export sub, can just use
# BaseStruct::Export. Might need to set params a la line 22
# ElementProperties.pm. See ExportRemap.pm





# importing can just use import_data from ElementProperties.pm
# procedure for importing:
# my %remap_data;

# # no automatic remap, prompt for manual remap file
# %remap_data = Biodiverse::GUI::BasedataImport::get_remap_info(
#     gui          => $gui,
#     type         => 'label',
#     get_dir_from => $filename,
#     );


# #  now do something with them...
# my $remap;

# ###### check if we need to call remap (eg if tabular, and no remapping?)
# if ( defined $remap_data{file} ) {
#     $remap = Biodiverse::ElementProperties->new;
#     $remap->import_data( %remap_data, );
# }
# $import_params{element_properties} = $remap;
# if ( !defined $remap ) {
#     $import_params{use_element_properties} = undef;
# }
