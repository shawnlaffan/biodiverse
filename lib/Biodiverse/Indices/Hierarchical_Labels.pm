package Biodiverse::Indices::Hierarchical_Labels;

use strict;
use warnings;

use Scalar::Util qw /blessed/;
use Biodiverse::Progress;

our $VERSION = '3.00';

my $metadata_class = 'Biodiverse::Metadata::Indices';

######################################################
#
#  routines to analyse labels in relation to their hierarchies
#  an example would be comparing family, genus and species diversity
#

sub get_metadata_calc_hierarchical_label_ratios {
    my $self = shift;
    
    my $bd = $self->get_basedata_ref;
    
    my $column_count = eval {$bd->get_label_column_count} || 0;
    my %indices;
    if ($column_count) {
        for my $i (0 .. $column_count - 1) {  
            
            my $j = $i - 1;
            $indices{"HIER_A$i"}    = {description => "A score for level $i",  lumper => 0,};
            $indices{"HIER_B$i"}    = {description => "B score  for level $i", lumper => 0,};
            $indices{"HIER_C$i"}    = {description => "C score for level $i",  lumper => 0,};
            $indices{"HIER_ASUM$i"} = {description => "Sum of shared label sample counts, level $i", lumper => 0,};
            
            next if $i == 0;
            
            my $ij_text = "${i}_${j}";
            $indices{"HIER_ARAT$ij_text"}     = {description => "Ratio of A scores, (HIER_A$i / HIER_A$j)", lumper => 0,};
            $indices{"HIER_BRAT$ij_text"}     = {description => "Ratio of B scores, (HIER_B$i / HIER_B$j)", lumper => 0,};
            $indices{"HIER_CRAT$ij_text"}     = {description => "Ratio of C scores, (HIER_C$i / HIER_C$j)", lumper => 0,};
            $indices{"HIER_ASUMRAT$ij_text"}  = {
                description => "1 - Ratio of shared label sample counts, (HIER_ASUM$i / HIER_ASUM$j)",
                cluster     => 'NO_CACHE_ABC',  #  value is true, but allows a caveat
            };
        }
    }

    #my $levels = ($column_count - 1);
    my $desc = <<"END_H_DESC"
Analyse the diversity of labels using their hierarchical levels.
The A, B and C scores are the same as in the Label Counts analysis (calc_label_counts)
but calculated for each hierarchical level, e.g. for three axes one could have
A0 as the Family level, A1 for the Family:Genus level,
and A2 for the Family:Genus:Species level.
The number of indices generated depends on how many axes are used in the labels.
In this case there are $column_count.  Axes are numbered from zero
as the highest level in the hierarchy, so level 0 is the top level
of the hierarchy.
END_H_DESC
;
    
    my $ref = 'Jones and Laffan (2008) Trans Philol Soc '
            . 'https://doi.org/10.1111/j.1467-968X.2008.00209.x';

    my %metadata = (
        name            => 'Ratios of hierarchical labels',
        description     => $desc,
        type            => 'Hierarchical Labels',
        reference       => $ref,
        indices         => \%indices,
        pre_calc_global => 'get_basedatas_by_label_hierarchy',
        pre_calc        => 'calc_abc',  #  we need the element lists
        uses_nbr_lists  => 2,  #  how many sets of lists it must have
    );
    
    return $metadata_class->new(\%metadata);
}


sub calc_hierarchical_label_ratios {
    my $self = shift;
    my %args = @_;
    
    my $hierarchy = $args{BD_HIERARCHY};
    
    my %results;
    
    my @sum_a_keys;
    
    foreach my $i (0 .. $#$hierarchy) {
        no warnings qw /numeric uninitialized/;  #  divide by zero will return undef
                                                 #  undef will be treated as zero
        
        #my $bd = $hierarchy->[$i];
        my $xx = $self->calc_abc3 (
            element_list1 => $args{element_list1},
            element_list2 => $args{element_list2},
        );
        
        $results{'HIER_A' . $i} = $$xx{A};
        $results{'HIER_B' . $i} = $$xx{B};
        $results{'HIER_C' . $i} = $$xx{C};
        
        my $xx_a_keys = $self->get_shared_hash_keys (
            lists => [
                $xx->{label_hash1},
                $xx->{label_hash2}
            ]
        );
        $sum_a_keys[$i] = 0;
        foreach my $key (keys %$xx_a_keys) {
            $sum_a_keys[$i] += $xx->{label_hash_all}{$key};
        }
        
        $results{'HIER_ASUM' . $i} = $sum_a_keys[$i];
        
        next if $i == 0;
        
        my $j = $i - 1;
        
        $results{"HIER_ARAT$i\_$j"} = eval {$xx->{A} / $results{'HIER_A' . $j}};
        $results{"HIER_BRAT$i\_$j"} = eval {$xx->{B} / $results{'HIER_B' . $j}};
        $results{"HIER_CRAT$i\_$j"} = eval {$xx->{C} / $results{'HIER_C' . $j}};
        #  if the denominator is zero then we have no overlap
        #  between label lists -- make it a result of 1
        $results{"HIER_ASUMRAT$i\_$j"}
            = 1 - eval {$sum_a_keys[$i] / $sum_a_keys[$j]};
    }
    
    return wantarray ? %results : \%results;
    
}

sub get_metadata_get_basedatas_by_label_hierarchy {
    my $desc = << 'END_BDLH_DESCR'
Get a series of basedata objects, but with the labels reduced by one from the right.
The groups remain the same, as do the total sample counts.
END_BDLH_DESCR
  ;

    my %metadata = (
        name        => 'get_basedatas_by_label_hierarchy',
        description => '$desc',
        indices => {
            BD_HIERARCHY => {
                description => 'List of hierarchical basedatas',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_basedatas_by_label_hierarchy {
    my $self = shift;
    my %args = @_;
    
    my $progress_bar = Biodiverse::Progress->new();
    
    my $bd  = $self->get_basedata_ref;

    my $labels_ref = $bd->get_labels_ref;

    my $label_max_index = $bd->get_label_column_count - 1;

    my %results = (BD_HIERARCHY => []);
    return wantarray ? %results : \%results if ! $label_max_index;

    #  generate a set of new basedata objects
    foreach my $i (0 .. $label_max_index) {
        #  just to allow greater abstraction, eg we may extend the basedata types
        my $cell_sizes = $bd->get_cell_sizes;
        push @{$results{BD_HIERARCHY}}, blessed ($bd)->new (CELL_SIZES => $cell_sizes);  
    }

    my $targets = $results{BD_HIERARCHY};
    my $quote_char = $bd->get_param('QUOTES');

    my $progress_count = 0;
    my $to_do = $labels_ref->get_element_count;

    foreach my $label ($labels_ref->get_element_list) {
        my @element_array = $labels_ref->get_element_name_as_array (
            element => $label,
        );
        my %groups = $bd->get_groups_with_label_as_hash (label => $label);

        $progress_count++;
        $progress_bar->update (
            "Building hierarchical basedata\n"
            . "for label columns 0 to $label_max_index\n"
            . "($progress_count / $to_do)",
            $progress_count / $to_do
        );

        foreach my $group (keys %groups) {
            #  get the count of the original
            my $count = $groups{$group};

            foreach my $i (0 .. $label_max_index) {
                #  get the new label from the slice
                my $new_label = $bd->list2csv (
                    list => [@element_array[0..$i]]
                );

                $new_label = $self->dequote_element (
                    element    => $new_label,
                    quote_char => $quote_char,
                );

                #  now add this new label/group pair to the new basedata
                $targets->[$i]->add_element (
                    label => $new_label,
                    group => $group,
                    count => $count,
                );
            }
        }
    }
    
    return wantarray ? %results : \%results;
}


1;

__END__

=head1 NAME

Biodiverse::Indices::Hierarchical_Labels

=head1 SYNOPSIS

  use Biodiverse::Indices;


=head1 DESCRIPTION

Hierarchical label indices for the Biodiverse system.
It is inherited by Biodiverse::Indices and not to be used on it own.

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
