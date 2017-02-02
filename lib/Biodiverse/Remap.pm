package Biodiverse::Remap;

use strict;
use warnings;
use Carp;
use 5.016;

use Data::Dumper;
use Ref::Util qw { :all };


our $VERSION = '1.99_006';

use parent qw /Biodiverse::ElementProperties/;


# given a hash mapping from one set of labels to another, fills out
# this object with that remap.
sub populate_from_hash {
    my ($self, %args) = @_;
    my $hash = $args{remap_hash};

    # clear any previous remap.
    $self->delete_all_elements();

    my $quotes = "'";
    my $sep = ":";
    
    my $csv_out = $self->get_csv_object (
        sep_char => $sep,
        quote_char => $quotes,
        );

    foreach my $key (keys %$hash) {
        # create an element for this remap
        my @in_cols = ($key);

        my $element = $key;
        
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


# given a BaseData, Tree order Matrix ref, applies this remap to their
# labels. Updates the ref so doesn't need to return anything.
sub apply_to_data_source {
    my ($self, %args) = @_;
    my $source = $args{data_source};
    my $remap_hash = $self->to_hash;
    $source->remap_labels_from_hash( remap => $remap_hash );
}


sub populate_with_guessed_remap {
    my $self = shift;
    my $args = shift;

    my $new_source   = $args->{ new_source   };
    my $old_source   = $args->{ old_source   };
    my $max_distance = $args->{ max_distance };
    my $ignore_case  = $args->{ ignore_case  };

    # is there a list of sources whose labels we should combine?
    my $remapping_multiple_sources = is_arrayref($new_source);

    # actually do the remap
    my $guesser       = Biodiverse::RemapGuesser->new();
    my $remap_results = $guesser->generate_auto_remap(
        {
            existing_data_source       => $old_source,
            new_data_source            => $new_source,
            max_distance               => $max_distance,
            ignore_case                => $ignore_case,
            remapping_multiple_sources => $remapping_multiple_sources,
        }
        );
    
    my $remap       = $remap_results->{remap};
    
    $self->{ exact_matches } = $remap_results->{ exact_matches };
    $self->{ punct_matches } = $remap_results->{ punct_matches };
    $self->{ typo_matches  } = $remap_results->{ typo_matches  };
    $self->{ not_matched   } = $remap_results->{ not_matched   };
    
    $self->populate_from_hash( remap_hash => $remap );
    $self->dequote_all_elements();
    $self->{ has_auto_remap } = 1;
}


# have we generated an auto remap in this Remap object?
sub has_auto_remap {
    my ($self, %args) = @_;
    return $self->{ has_auto_remap };
}

# get exact matches, punct matches etc.
sub get_match_category {
    my ($self, %args) = @_;
    my $match_category = $args{category};
    
    return $self->{$match_category};
}


sub dequote_all_elements {
    my ($self, %args) = @_;
    my $old_hash = $self->to_hash();
    my %dequoted_hash = ();

    foreach my $key (keys %$old_hash) {
        my $new_key = $self->dequote_element( element    => $key,
                                              quote_char => "'",
                                            );

        my $new_val = $self->dequote_element( element    => $old_hash->{$key},
                                              quote_char => "'",
                                            );
        $dequoted_hash{$new_key} = $new_val;
    }

    
    $self->populate_from_hash(remap_hash => \%dequoted_hash);
}



# Importing mostly uses import_data from ElementProperties.pm
# procedure. But we also need to dequote the elements otherwise remaps
# involving colons will put quotes around each element. This causes a
# mismatch with basedata etc.
sub import_from_file {
    my($self, %args) = @_;
    $self->import_data(%args);
    $self->dequote_all_elements();
}
