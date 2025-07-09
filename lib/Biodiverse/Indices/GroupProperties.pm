#  Summarise the group properties for a sample.
#  This is almost the same as LabelProperties
#  - need to abstract them to reduce maintenance burden.

package Biodiverse::Indices::GroupProperties;
use strict;
use warnings;

use Carp;

our $VERSION = '4.99_006';

use experimental 'for_list';

use Statistics::Descriptive::PDL::SampleWeighted 0.11;
my $stats_class_weighted = 'Statistics::Descriptive::PDL::SampleWeighted';

my $metadata_class = 'Biodiverse::Metadata::Indices';


sub get_metadata_get_gpp_stats_objects {
    my $self = shift;

    my $desc = 'Get the stats object for the group property values'
             . " across both neighbour sets\n";
    my %metadata = (
        description     => $desc,
        name            => 'Group property stats objects',
        type            => 'Element Properties',
        pre_calc        => ['calc_element_lists_used'],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        pre_conditions => ['basedata_has_group_properties'],
        indices => {
            GPPROP_STATS_OBJECTS => {
                description => 'Hash of stats objects for the property values',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_gpp_stats_objects {
    my $self = shift;
    my %args = @_;

    my $element_list = $args{EL_LIST_ALL};

    my $bd = $self->get_basedata_ref;
    my $gp = $bd->get_groups_ref;

    my %stats_objects;
    my %data;
    #  process the properties and generate the stats objects
    foreach my $prop ($gp->get_element_property_keys) {
        my $key = $self->_get_gpprop_stats_hash_key(property => $prop);
        $stats_objects{$key} = $stats_class_weighted->new();
        $data{$prop} = {};
    }

    #  loop over the labels and collect arrays of their elements.
    #  These are then added to the stats objects to save it
    #  recalculating all its stats each time.
    my $count = 1;
    GROUP:
    foreach my $group (@$element_list) {
        my $properties = $gp->get_element_properties (element => $group);

        next GROUP if ! defined $properties;

        PROPERTY:
        foreach my ($prop, $value) (%$properties) {
            #my $value = $properties->{$prop};
            next PROPERTY if ! defined $value;

            my $data_ref = $data{$prop};
            $data_ref->{$value} += $count;
        }
    }
    
    ADD_DATA_TO_STATS_OBJECTS:
    foreach my $prop (keys %data) {
        my $stats_key = $self->_get_gpprop_stats_hash_key(property => $prop);
        my $stats = $stats_objects{$stats_key};
        my $data_ref = $data{$prop};
        $stats->add_data($data_ref);
    }

    my %results = (
        GPPROP_STATS_OBJECTS => \%stats_objects,
    );

    return wantarray ? %results : \%results;
}

sub _get_gpprop_stats_hash_key {
    my $self = shift;
    my %args = @_;
    my $prop = $args{property};
    return 'GPPROP_STATS_' . $prop . '_DATA';
}

sub _get_gpprop_names {
    my $self = shift;

    #  use a cache to save time on repeated lookups
    my $names = $self->get_cached_value('GPPROP_NAMES');

    if (! $names) {
        my $bd = $self->get_basedata_ref;
        my $gp = $bd->get_groups_ref;

        $names = $gp->get_element_property_keys;

        $self->set_cached_value (GPPROP_NAMES => $names);
    }    

    return wantarray ? @$names : $names;
}

sub _get_gpprop_stats_hash_keynames {
    my $self = shift;

    my %keys;

    if (my $bd = $self->get_basedata_ref) {
        my $gp = $bd->get_groups_ref;

        #  what stats object names will we have?
        foreach my $prop ($gp->get_element_property_keys) {
            my $key = $self->_get_gpprop_stats_hash_key(property => $prop);
            $keys{$prop} = $key;
        }
    }

    return wantarray ? %keys : \%keys;
}


sub get_metadata_calc_gpprop_lists {
    my $self = shift;

    my $desc = 'Lists of the groups and their property values '
             . 'used in the group properties calculations';

    my %indices;
    my %prop_hash_names = $self->_get_gpprop_stats_hash_keynames;
    foreach my $prop (keys %prop_hash_names) {
        $indices{$prop_hash_names{$prop}} = {
            description => 'List of values for property ' . $prop,
            type        => 'list',
        };
    }

    my %metadata = (
        description     => $desc,
        name            => 'Group property data',
        type            => 'Element Properties',
        pre_calc        => ['get_gpp_stats_objects'],
        uses_nbr_lists  => 1,
        indices         => \%indices,
    );

    return $metadata_class->new(\%metadata);
}

sub calc_gpprop_lists {
    my $self = shift;
    my %args = @_;

    #  just grab the hash from the precalc results
    my %objects = %{$args{GPPROP_STATS_OBJECTS}};
    #my %results = map {$_ => [$objects{$_}->get_data]} keys %objects;
    my %results;
    for my $prop (keys %objects) {
        my ($values, $wts) = $objects{$prop}->get_data;
        my @arr = map {($values->[$_]) x $wts->[$_]} (0..$#$values);
        $results{$prop} = \@arr;
    }

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_gpprop_hashes {
    my $self = shift;

    my $desc = 'Hashes of the groups and their property values '
             . 'used in the group properties calculations. '
             . 'Hash keys are the property values, '
             . 'hash values are the property value frequencies.';

    my %indices;
    my %prop_hash_names = $self->_get_gpprop_stats_hash_keynames;
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
        name            => 'Group property hashes',
        type            => 'Element Properties',
        pre_calc        => ['get_gpp_stats_objects'],
        uses_nbr_lists  => 1,
        indices         => \%indices,
    );

    return $metadata_class->new(\%metadata);
}


#  data in hash form
sub calc_gpprop_hashes {
    my $self = shift;
    my %args = @_;

    #  just grab the hash from the precalc results
    my %objects = %{$args{GPPROP_STATS_OBJECTS}};
    my %results;

    foreach my $prop (keys %objects) {
        my $key = ($prop =~ s/DATA$/HASH/r);
        $results{$key} = $objects{$prop}->get_data_as_hash;
    }

    return wantarray ? %results : \%results;
}


my @stats     = qw /count mean min max median sum sd iqr/;
my @quantiles = qw /05 10 20 30 40 50 60 70 80 90 95/;

sub get_metadata_calc_gpprop_stats {
    my $self = shift;

    my $desc = 'List of summary statistics for each group property across both neighbour sets';
    my $stats_list_text = '(' . join (q{ }, @stats) . ')';

    my %metadata = (
        description     => $desc,
        name            => 'Group property summary stats',
        type            => 'Element Properties',
        pre_calc        => ['get_gpp_stats_objects'],
        pre_conditions  => ['basedata_has_group_properties'],
        uses_nbr_lists  => 1,
        indices         =>  {
            GPPROP_STATS_LIST => {
                description => 'List of summary statistics ' . $stats_list_text,
                type        => 'list',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_gpprop_stats {
    my $self = shift;
    my %args = @_;

    #  just grab the hash from the precalc results
    my %objects = %{$args{GPPROP_STATS_OBJECTS}};
    my %res;

    foreach my $prop (keys %objects) {
        my $stats_object = $objects{$prop};
        my $pfx = $prop;
        $pfx =~ s/DATA$//;
        $pfx =~ s/^GPPROP_STATS_//;
        foreach my $stat (@stats) {
            my $stat_name = $stat;

            $res{$pfx . uc $stat_name} = eval {$stats_object->$stat};
        }
    }

    my %results = (GPPROP_STATS_LIST => \%res);

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_gpprop_quantiles {
    my $self = shift;

    my $desc = 'Quantiles for each group property across both neighbour sets';
    my $quantile_list_text = '(' . join (q{ }, @quantiles) . ')';

    my %metadata = (
        description     => $desc,
        name            => 'Group property quantiles',
        type            => 'Element Properties',
        pre_calc        => ['get_gpp_stats_objects'],
        pre_conditions  => ['basedata_has_group_properties'],
        uses_nbr_lists  => 1,
        indices         =>  {
            GPPROP_QUANTILE_LIST => {
                description => 'List of quantiles for the label properties ' . $quantile_list_text,
                type        => 'list',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_gpprop_quantiles {
    my $self = shift;
    my %args = @_;

    #  just grab the hash from the precalc results
    my $objects = $args{GPPROP_STATS_OBJECTS};
    my %res;

    foreach my $prop (keys %$objects) {
        my $pfx = ($prop =~ s/DATA$/Q/r);
        my @keys = map {$pfx . $_} @quantiles;
        @res{@keys} = $objects->{$prop}->percentiles(@quantiles);
    }

    my %results = (GPPROP_QUANTILE_LIST => \%res);

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_gpprop_gistar {
    my $self = shift;

    my $desc = 'List of Getis-Ord Gi* statistics for each group property across both neighbour sets';
    my $ref  = 'Getis and Ord (1992) Geographical Analysis. https://doi.org/10.1111/j.1538-4632.1992.tb00261.x';

    my %metadata = (
        description     => $desc,
        name            => 'Group property Gi* statistics',
        type            => 'Element Properties',
        pre_calc        => ['get_gpp_stats_objects'],
        pre_calc_global => [qw /_get_gpprop_global_summary_stats/],
        pre_conditions  => ['basedata_has_group_properties'],
        uses_nbr_lists  => 1,
        reference       => $ref,
        indices         => {
            GPPROP_GISTAR_LIST => {
                description => 'List of Gi* scores',
                type        => 'list',
                distribution => 'zscore',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_gpprop_gistar {
    my $self = shift;
    my %args = @_;

    my %res;

    my $global_hash   = $args{GPPROP_GLOBAL_SUMMARY_STATS};
    my %local_objects = %{$args{GPPROP_STATS_OBJECTS}};

    foreach my $prop (keys %$global_hash) {
        my $global_data = $global_hash->{$prop};
        #  bodgy - need generic method
        my $local_data = $local_objects{'GPPROP_STATS_' . $prop . '_DATA'};

        $res{$prop} = $self->_get_gistar_score(
            global_data => $global_data,
            local_data  => $local_data,
        );
    }

    my %results = (GPPROP_GISTAR_LIST => \%res);

    return wantarray ? %results : \%results;
}

#  run the actual Gi* calculation
sub _get_gistar_score {
    my $self = shift;
    my %args = @_;

    my $global_data = $args{global_data};
    my $local_data  = $args{local_data};

    my $sum = $local_data->sum;
    return if !defined $sum;

    my $n  = $global_data->{count};  #  these are hash values
    my $W  = $local_data->count;     #  these are objects
    my $S1 = $W;  #  binary weights here
    my $expected = $W * $global_data->{mean};

    my $numerator = $sum - $expected;
    my $sd = $global_data->{standard_deviation} // $global_data->{sd};

    my $denominator = $W
        ? $sd * sqrt (
                (($n * $S1) - $W ** 2)
                / ($n - 1)
            )
        : undef;

    my $res;
    if ($W) {
        $res = $denominator ? $numerator / $denominator : 0;
    }

    return $res;
}

sub get_metadata__get_gpprop_global_summary_stats {
    my $self = shift;
    
    my $descr = 'Global summary stats for group properties';

    my %metadata = (
        description     => $descr,
        name            => $descr,
        type            => 'Element Properties',
        indices         => {
            GPPROP_GLOBAL_SUMMARY_STATS => {
                description => $descr,
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub _get_gpprop_global_summary_stats {
    my $self = shift;

    my $bd = $self->get_basedata_ref;
    my $gp = $bd->get_groups_ref;
    my $hash = $gp->get_element_properties_summary_stats;
    
    my %results = (
        GPPROP_GLOBAL_SUMMARY_STATS => $hash,
    );
    
    return wantarray ? %results : \%results;
}

sub basedata_has_group_properties {
    my $self = shift;
    my @names = $self->_get_gpprop_names;
    return !!scalar @names;
}

1;


__END__

=head1 NAME

Biodiverse::Indices::GroupProperties

=head1 SYNOPSIS

  use Biodiverse::Indices;

=head1 DESCRIPTION

Group property indices for the Biodiverse system.
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
