package Biodiverse::ExportRemap;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.99_006';

use English( -no_match_vars );

use Carp;


use Biodiverse::GUI::Export qw /:all/;
use Biodiverse::ElementProperties;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

# given a hash mapping from one set of labels to another, puts them in
# a basestruct and then exports.
sub export_remap {
    my ($self, %args) = @_;
    my $remap = $args{remap};

    # build the basestruct ready for export
    my $ep = Biodiverse::ElementProperties->new;
    
    my $quotes = "'";
    my $sep = ":";
    
    my $csv_out = $ep->get_csv_object (
        sep_char => $sep,
        quote_char => $quotes,
    );

    foreach my $key (keys %$remap) {
        # create an element for this remapping
        my @in_cols = ($key);

        my $element = $ep->list2csv (
            list       => \@in_cols,
            csv_object => $csv_out,
            );

        #$element = $ep->dequote_element(element => $element, quote_char => $quotes);

        $ep->add_element (
            element    => $element,
            csv_object => $csv_out,
            );

        my $properties_hash;
        $properties_hash->{REMAP} = $remap->{$key};

        # create an include and exclude column just in case this is
        # required. e.g. for matrix remapping
        $properties_hash->{INCLUDE} = 1;
        $properties_hash->{EXCLUDE} = 0;

        $ep->add_to_lists (element => $element, PROPERTIES => $properties_hash);
    }

    Biodiverse::GUI::Export::Run( $ep );
}



1;
