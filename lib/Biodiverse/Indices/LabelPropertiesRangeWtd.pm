package Biodiverse::Indices::LabelPropertiesRangeWtd;
use strict;
use warnings;

use Carp;

our $VERSION = '4.99_002';

my $metadata_class = 'Biodiverse::Metadata::Indices';

sub get_metadata_get_lbp_stats_objects_abc2 {
    my $self = shift;

    my $desc = 'Get the stats object for the property values'
             . " across both neighbour sets, local range weighted\n";
    my %metadata = (
        description     => $desc,
        name            => 'Label property stats objects, local range weighted',
        type            => 'Element Properties',
        pre_calc        => ['calc_abc2'],
        pre_conditions  => ['basedata_has_label_properties'],
        uses_nbr_lists  => 1,  #  how many sets of lists it must have
        indices => {
            LBPROP_STATS_OBJECTS_ABC2 => {
                description => 'hash of stats objects for the property values, local range weighted',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_lbp_stats_objects_abc2 {
    my $self = shift;
    my %args = @_;

    my $label_hash_all = $args{label_hash_all};
    
    my %init_results = $self->get_lbp_stats_objects (%args);

    my %results = (
        LBPROP_STATS_OBJECTS_ABC2 => $init_results{LBPROP_STATS_OBJECTS},
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_lbprop_hashes_abc2 {
    my $self = shift;

    my $desc = <<'END_OF_DESC'
Hashes of the labels and their property values
used in the local range weighted label properties calculations.
Hash keys are the property values,
hash values are the property value frequencies.
END_OF_DESC
  ;

    my %indices;
    my %prop_hash_names = $self->_get_lbprop_stats_hash_keynames;
    foreach my $prop (keys %prop_hash_names) {
        my $list_name = $prop_hash_names{$prop};
        $list_name =~ s/DATA$/HASH2/;
        $indices{$list_name} = {
            description => 'Hash of values for property ' . $prop,
            type        => 'list',
        };
    }

    my %metadata = (
        description     => $desc,
        name            => 'Label property hashes (local range weighted)',
        type            => 'Element Properties',
        pre_calc        => ['get_lbp_stats_objects_abc2'],
        uses_nbr_lists  => 1,
        indices         => \%indices,
    );

    return $metadata_class->new(\%metadata);
}


#  data in hash form
sub calc_lbprop_hashes_abc2 {
    my $self = shift;
    my %args = @_;

    #  just grab the hash from the precalc results
    my %objects = %{$args{LBPROP_STATS_OBJECTS_ABC2}};
    my %results;

    foreach my $prop (keys %objects) {
        my $key = ($prop =~ s/DATA$/HASH2/r);
        $results{$key} = $objects{$prop}->get_data_as_hash();
    }

    return wantarray ? %results : \%results;
}


my @stats     = qw /count mean min max median sum skewness kurtosis sd iqr/;
my @quantiles = qw /05 10 20 30 40 50 60 70 80 90 95/;

sub get_metadata_calc_lbprop_stats_abc2 {
    my $self = shift;

    my $desc = "List of summary statistics for each label property across both neighbour sets, weighted by local ranges\n";
    my $stats_list_text = '(' . join (q{ }, @stats) . ')';

    my %metadata = (
        description     => $desc,
        name            => 'Label property summary stats (local range weighted)',
        type            => 'Element Properties',
        pre_calc        => ['get_lbp_stats_objects_abc2'],
        pre_conditions  => ['basedata_has_label_properties'],
        uses_nbr_lists  => 1,
        indices         => {
            LBPROP_STATS_ABC2 => {
                description => 'List of summary statistics ' . $stats_list_text,
                type        => 'list',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_lbprop_stats_abc2 {
    my $self = shift;
    my %args = @_;

    #  just grab the hash from the precalc results
    my %objects = %{$args{LBPROP_STATS_OBJECTS_ABC2}};
    my %res;

    foreach my $prop (keys %objects) {
        my $stats_object = $objects{$prop};
        my $pfx = $prop;
        $pfx =~ s/DATA$//;
        $pfx =~ s/^LBPROP_STATS_//;
        foreach my $stat (@stats) {
            $res{$pfx . uc $stat} = eval {$stats_object->$stat};
        }
    }

    my %results = (LBPROP_STATS_ABC2 => \%res);

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_lbprop_quantiles_abc2 {
    my $self = shift;

    my $desc = "List of quantiles for each label property across both neighbour sets (local range weighted)\n";
    my $quantile_list_text = '(' . join (q{ }, @quantiles) . ')';

    my %metadata = (
        description     => $desc,
        name            => 'Label property quantiles (local range weighted)',
        type            => 'Element Properties',
        pre_calc        => ['get_lbp_stats_objects_abc2'],
        pre_conditions  => ['basedata_has_label_properties'],
        uses_nbr_lists  => 1,
        indices         => {
            LBPROP_QUANTILES_ABC2 => {
                description => 'List of quantiles for the label properties: ' . $quantile_list_text,
                type        => 'list',
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_lbprop_quantiles_abc2 {
    my $self = shift;
    my %args = @_;

    #  just grab the hash from the precalc results
    my $objects = $args{LBPROP_STATS_OBJECTS_ABC2};
    my %res;

    foreach my $prop (keys %$objects) {
        my $pfx = $prop;
        $pfx =~ s/DATA$/Q/;
        $pfx =~ s/^LBPROP_STATS_//;
        my @keys    = map {$pfx . $_} @quantiles;
        @res{@keys} = $objects->{$prop}->percentiles(@quantiles);
    }

    my %results = (LBPROP_QUANTILES_ABC2 => \%res);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_lbprop_gistar_abc2 {
    my $self = shift;

    my $desc = 'List of Getis-Ord Gi* statistic for each label property across both neighbour sets (local range weighted)';
    my $ref  = 'Getis and Ord (1992) Geographical Analysis. https://doi.org/10.1111/j.1538-4632.1992.tb00261.x';

    my %metadata = (
        description     => $desc,
        name            => 'Label property Gi* statistics (local range weighted)',
        type            => 'Element Properties',
        pre_calc        => ['get_lbp_stats_objects_abc2'],
        pre_calc_global => [qw /_get_lbprop_global_summary_stats_range_weighted/],
        pre_conditions  => ['basedata_has_label_properties'],
        uses_nbr_lists  => 1,
        reference       => $ref,
        indices         => {
            LBPROP_GISTAR_LIST_ABC2 => {
                description => 'List of Gi* scores',
                type        => 'list',
                distribution => 'zscore',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_lbprop_gistar_abc2 {
    my $self = shift;
    my %args = @_;

    my %res;

    my $global_hash   = $args{LBPROP_GLOBAL_SUMMARY_STATS_RANGE_WEIGHTED};
    my %local_objects = %{$args{LBPROP_STATS_OBJECTS_ABC2}};

    foreach my $prop (keys %$global_hash) {
        my $global_data = $global_hash->{$prop};
        #  bodgy - need generic method
        my $local_data = $local_objects{'LBPROP_STATS_' . $prop . '_DATA'};

        $res{$prop} = $self->_get_gistar_score(
            global_data => $global_data,
            local_data  => $local_data,
        );
    }

    my %results = (LBPROP_GISTAR_LIST_ABC2 => \%res);

    return wantarray ? %results : \%results;
}


sub get_metadata__get_lbprop_global_summary_stats_range_weighted {
    my $self = shift;
    
    my $descr = 'Global summary stats for label properties, weighted by their ranges';

    my %metadata = (
        description     => $descr,
        name            => $descr,
        type            => 'Element Properties',
        indices         => {
            LBPROP_GLOBAL_SUMMARY_STATS_RANGE_WEIGHTED => {
                description => $descr,
            }
        },
    );

    return $metadata_class->new(\%metadata);
}

sub _get_lbprop_global_summary_stats_range_weighted {
    my $self = shift;

    my $bd = $self->get_basedata_ref;
    my $lb = $bd->get_labels_ref;
    my $hash = $lb->get_element_properties_summary_stats (range_weighted => 1);

    my %results = (
        LBPROP_GLOBAL_SUMMARY_STATS_RANGE_WEIGHTED => $hash,
    );

    return wantarray ? %results : \%results;
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
