package Biodiverse::Indices::LabelProperties;
use strict;
use warnings;

use Carp;

our $VERSION = '4.99_009';

use Ref::Util qw { :all };

use experimental 'for_list';

use Statistics::Descriptive::PDL 0.12;
my $stats_class = 'Statistics::Descriptive::PDL';
$stats_class = 'Statistics::Descriptive::PDL::SampleWeighted';
#  could be a method from the stats class
my $use_weighted_stats = $stats_class =~ /Weighted$/;


my $metadata_class = 'Biodiverse::Metadata::Indices';

sub get_metadata_get_lbp_stats_objects {
    my $self = shift;

    my $desc = 'Get the stats object for the label property values'
             . " across both neighbour sets\n";
    my %metadata = (
        description     => $desc,
        name            => 'Label property stats objects',
        type            => 'Element Properties',
        pre_calc        => ['calc_abc'],
        pre_conditions  => ['basedata_has_label_properties'],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            LBPROP_STATS_OBJECTS => {
                description => 'hash of stats objects for the property values',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_lbp_stats_objects {
    my $self = shift;
    my %args = @_;

    my $label_hash_all = $args{label_hash_all};

    my $bd = $self->get_basedata_ref;
    my $lb = $bd->get_labels_ref;

    my %stats_objects;
    my %data;
    #  process the properties and generate the stats objects
    foreach my $prop ($lb->get_element_property_keys) {
        my $key = $self->_get_lbprop_stats_hash_key(property => $prop);
        $stats_objects{$key} = $stats_class->new();
        $data{$prop} = undef;
    }

    #  loop over the labels and collect arrays of their elements.
    #  These are then added to the stats objects to save it
    #  recalculating all its stats each time.
    LABEL:
    foreach my $label (keys %$label_hash_all) {
        my $properties = $lb->get_element_properties (element => $label);

        next LABEL if !defined $properties;

        my $count = $label_hash_all->{$label};

        PROPERTY:
        foreach my ($prop, $value) (%$properties) {
            # my $value = $properties->{$prop};
            next PROPERTY if ! defined $value;

            if ($use_weighted_stats) {
                my $data_ref = $data{$prop} //= {};
                $data_ref->{$value} += $count;
            }
            else {
                my $data_ref = $data{$prop} //= [];
                #  allow for possible calc_abc3 dependency
                push @$data_ref, ($value) x $count;
            }
        }
    }

    ADD_DATA_TO_STATS_OBJECTS:
    foreach my $prop (sort keys %data) {
        my $stats_key = $self->_get_lbprop_stats_hash_key(property => $prop);
        $stats_objects{$stats_key}->add_data($data{$prop});
    }

    my %results = (
        LBPROP_STATS_OBJECTS => \%stats_objects,
    );

    return wantarray ? %results : \%results;
}

sub _get_lbprop_stats_hash_key {
    my $self = shift;
    my %args = @_;
    my $prop = $args{property};
    return 'LBPROP_STATS_' . $prop . '_DATA';
}

sub _get_lbprop_stats_hash_keynames {
    my $self = shift;

    my %keys;

    if (my $bd = $self->get_basedata_ref) {
        my $lb = $bd->get_labels_ref;

        #  what stats object names will we have?
        foreach my $prop ($lb->get_element_property_keys) {
            my $key = $self->_get_lbprop_stats_hash_key(property => $prop);
            $keys{$prop} = $key;
        }
    }

    return wantarray ? %keys : \%keys;
}

sub get_metadata_calc_lbprop_lists {
    my $self = shift;

    my $desc = 'Lists of the labels and their property values '
             . 'within the neighbour sets';

    my %indices;
    my %prop_hash_names = $self->_get_lbprop_stats_hash_keynames;
    foreach my $prop (keys %prop_hash_names) {
        my $l = $prop_hash_names{$prop};
        $l =~ s/STATS/LIST/;
        $l =~ s/_DATA$//;
        $indices{$l} = {
            description => 'List of data for property ' . $prop,
            type        => 'list',
        };
    }

    my %metadata = (
        description     => $desc,
        name            => 'Label property lists',
        type            => 'Element Properties',
        pre_calc        => ['_calc_abc_any'],
        uses_nbr_lists  => 1,
        indices         => \%indices,
    );

    return $metadata_class->new(\%metadata);
}

sub calc_lbprop_lists {
    my $self = shift;
    my %args = @_;

    my $bd = $self->get_basedata_ref;
    my $lb = $bd->get_labels_ref;

    my $label_hash = $args{label_hash_all};

    my %results;

  LABEL:
    foreach my $label (keys %$label_hash) {
        my $properties = $lb->get_element_properties (element => $label);

        next LABEL if ! defined $properties;

        foreach my $prop (keys %$properties) {
            my $key = 'LBPROP_LIST_' . $prop;
            
            $results{$key}{$label} = $properties->{$prop};
        }
    }

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_lbprop_data {
    my $self = shift;

    my $desc = 'Lists of the labels and their property values '
             . 'used in the label properties calculations';

    my %indices;
    my %prop_hash_names = $self->_get_lbprop_stats_hash_keynames;
    foreach my $prop (keys %prop_hash_names) {
        my $list_name = $prop_hash_names{$prop};
        $indices{$list_name} = {
            description => 'List of data for property ' . $prop,
            type        => 'list',
        };
    }

    my %metadata = (
        description     => $desc,
        name            => 'Label property data',
        type            => 'Element Properties',
        pre_calc        => ['get_lbp_stats_objects'],
        uses_nbr_lists  => 1,
        indices         => \%indices,
    );

    return $metadata_class->new(\%metadata);
}

sub calc_lbprop_data {
    my $self = shift;
    my %args = @_;

    #  just grab the hash from the precalc results
    my %objects = %{$args{LBPROP_STATS_OBJECTS}};
    my %results;

    foreach my $prop (keys %objects) {
        if ($use_weighted_stats) {
            my ($values, $wts) = $objects{$prop}->get_data;
            $results{$prop} = [ map {($values->[$_]) x $wts->[$_]} (0..$#$values) ];
        }
        else {
            $results{$prop} = [ $objects{$prop}->get_data ];
        }
    }

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_lbprop_hashes {
    my $self = shift;

    my $desc = 'Hashes of the labels and their property values '
             . 'used in the label properties calculations. '
             . 'Hash keys are the property values, '
             . 'hash values are the property value frequencies.';

    my %indices;
    my %prop_hash_names = $self->_get_lbprop_stats_hash_keynames;
    foreach my $prop (keys %prop_hash_names) {
        my $list_name = $prop_hash_names{$prop};
        $list_name =~ s/DATA$/HASH/;
        $indices{$list_name} = {
            description => 'Hash of values for property ' . $prop,
            type        => 'list',
        };
    }

    my %metadata = (
        description     => $desc,
        name            => 'Label property hashes',
        type            => 'Element Properties',
        pre_calc        => ['get_lbp_stats_objects'],
        uses_nbr_lists  => 1,
        indices         => \%indices,
    );
    
    #print Data::Dumper::Dump \%arguments;

    return $metadata_class->new(\%metadata);
}


#  data in hash form
sub calc_lbprop_hashes {
    my $self = shift;
    my %args = @_;

    #  just grab the hash from the precalc results
    my %objects = %{$args{LBPROP_STATS_OBJECTS}};
    my %results;

    foreach my $prop (keys %objects) {
        my $key = ($prop =~ s/DATA$/HASH/r);
        $results{$key} = $objects{$prop}->get_data_as_hash;
    }

    return wantarray ? %results : \%results;
}


my @stats     = qw /count mean min max median sum skewness kurtosis sd iqr/;
my @quantiles = qw /05 10 20 30 40 50 60 70 80 90 95/;

sub get_metadata_calc_lbprop_stats {
    my $self = shift;

    my $desc = "List of summary statistics for each label property across both neighbour sets\n";
    my $stats_list_text = '(' . join (q{ }, @stats) . ')';

    my %metadata = (
        description     => $desc,
        name            => 'Label property summary stats',
        type            => 'Element Properties',
        pre_calc        => ['get_lbp_stats_objects'],
        uses_nbr_lists  => 1,
        indices         => {
            LBPROP_STATS => {
                description => 'List of summary statistics ' . $stats_list_text,
                type        => 'list',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_lbprop_stats {
    my $self = shift;
    my %args = @_;

    #  just grab the hash from the precalc results
    my %objects = %{$args{LBPROP_STATS_OBJECTS}};
    my %res;

    foreach my $prop (keys %objects) {
        my $stats_object = $objects{$prop};
        my $pfx = $prop;
        $pfx =~ s/DATA$//;
        $pfx =~ s/^LBPROP_STATS_//;
        foreach my $stat (@stats) {
            my $stat_name = $stat;

            $res{$pfx . uc $stat_name} = eval {$stats_object->$stat};
        }
    }

    my %results = (LBPROP_STATS => \%res);

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_lbprop_quantiles {
    my $self = shift;

    my $desc = "List of quantiles for each label property across both neighbour sets\n";
    my $quantile_list_text = '(' . join (q{ }, @quantiles) . ')';

    my %metadata = (
        description     => $desc,
        name            => 'Label property quantiles',
        type            => 'Element Properties',
        pre_calc        => ['get_lbp_stats_objects'],
        uses_nbr_lists  => 1,
        indices         => {
            LBPROP_QUANTILES => {
                description => 'List of quantiles for the label properties: ' . $quantile_list_text,
                type        => 'list',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_lbprop_quantiles {
    my $self = shift;
    my %args = @_;

    #  just grab the hash from the precalc results
    my $objects = $args{LBPROP_STATS_OBJECTS};
    my %res;

    foreach my $prop (keys %$objects) {
        my $pfx = $prop;
        $pfx =~ s/DATA$/Q/;
        $pfx =~ s/^LBPROP_STATS_//;
        my @keys    = map {$pfx . $_} @quantiles;
        @res{@keys} = $objects->{$prop}->percentiles(@quantiles);
    }

    my %results = (LBPROP_QUANTILES => \%res);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_lbprop_gistar {
    my $self = shift;

    my $desc = 'List of Getis-Ord Gi* statistic for each label property across both neighbour sets';
    my $ref  = 'Getis and Ord (1992) Geographical Analysis. https://doi.org/10.1111/j.1538-4632.1992.tb00261.x';

    my %metadata = (
        description     => $desc,
        name            => 'Label property Gi* statistics',
        type            => 'Element Properties',
        pre_calc        => ['get_lbp_stats_objects'],
        pre_calc_global => [qw /_get_lbprop_global_summary_stats/],
        uses_nbr_lists  => 1,
        reference       => $ref,
        indices         => {
            LBPROP_GISTAR_LIST => {
                description => 'List of Gi* scores',
                type        => 'list',
                distribution => 'zscore',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_lbprop_gistar {
    my $self = shift;
    my %args = @_;

    my %res;

    my $global_hash   = $args{LBPROP_GLOBAL_SUMMARY_STATS};
    my %local_objects = %{$args{LBPROP_STATS_OBJECTS}};

    foreach my ($prop, $global_data) (%$global_hash) {
        #  bodgy - need generic method
        my $local_data = $local_objects{'LBPROP_STATS_' . $prop . '_DATA'};

        $res{$prop} = $self->_get_gistar_score(
            global_data => $global_data,
            local_data  => $local_data,
        );
    }

    my %results = (LBPROP_GISTAR_LIST => \%res);

    return wantarray ? %results : \%results;
}


sub get_metadata__get_lbprop_global_summary_stats {
    my $self = shift;
    
    my $descr = 'Global summary stats for label properties';

    my %metadata = (
        description     => $descr,
        name            => $descr,
        type            => 'Element Properties',
        indices         => {
            LBPROP_GLOBAL_SUMMARY_STATS => {
                description => $descr,
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub _get_lbprop_global_summary_stats {
    my $self = shift;

    my $bd = $self->get_basedata_ref;
    my $lb = $bd->get_labels_ref;
    my $hash = $lb->get_element_properties_summary_stats;

    my %results = (
        LBPROP_GLOBAL_SUMMARY_STATS => $hash,
    );

    return wantarray ? %results : \%results;
}

sub basedata_has_label_properties {
    my $self = shift;

    my $has_label_props = $self->get_cached_value ('BD_HAS_LABEL_PROPS');
    
    if (!defined $has_label_props) {
        my $bd = $self->get_basedata_ref;
        my $lb = $bd->get_labels_ref;
        my @keys = $lb->get_element_property_keys;
        $has_label_props = !!@keys;
        $self->set_cached_value (BD_HAS_LABEL_PROPS => $has_label_props);
     };

    return $has_label_props;
}

1;


__END__

=head1 NAME

Biodiverse::Indices::LabelProperties

=head1 SYNOPSIS

  use Biodiverse::Indices;

=head1 DESCRIPTION

Label property indices for the Biodiverse system.
It is inherited by Biodiverse::Indices and not to be used on it own.

See L<http://purl.org/biodiverse/wiki/Indices> for more details.

=head1 METHODS

=over

=item INSERT METHODS

=back

=head1 REPORTING ERRORS

Use the issue tracker at http://www.purl.org/biodiverse

=head1 COPYRIGHT

Copyright (c) 2010 Shawn Laffan. All rights reserved.  

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut
