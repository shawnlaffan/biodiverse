#!/usr/bin/perl -w
use strict;
use warnings;
use 5.010;

use Carp;
use English qw { -no_match_vars };

use Biodiverse::BaseData;

my $bd_in_file  = shift @ARGV;
my $bd_out_file = shift @ARGV;
my $out_file    = shift @ARGV;

croak "no basedata file specified" if !defined $bd_in_file;

my $bd = Biodiverse::BaseData->new(file => $bd_in_file);

# calc_gpprop_gistar assumes the basedata has group properties.
my $calculations = ['calc_gpprop_gistar', 'calc_endemism_central', 'calc_endemism_central_lists'];

#  we want to get at the values for one of the lists.
#my $list_to_collate = 'GPPROP_GISTAR_LIST';
my $list_to_collate = 'ENDC_WTLIST';
my @list_of_results;  # a list of results hashes


#  Analyse in order of range size.
#  Makes no real difference to the final results,
#  except if one extracts the results as one goes. 
my @labels = sort { $bd->get_range (element => $a) <=> $bd->get_range (element => $b) } $bd->get_labels;

foreach my $label (reverse @labels) {
    my $name = $label;
    my $sp = $bd->add_spatial_output(name => $name);
    my $cond = sprintf q{sp_in_label_range (label => '%s')}, $label;
    $sp->run_analysis (
        spatial_conditions => [$cond],
        definition_query   => $cond,  #  limit the results to those groups in $label's range
        calculations       => $calculations,
    );

    #  Get one of the groups in $label's range.
    #  The values are all the same, so just choose the first one.
    my $groups_in_range = $bd->get_groups_with_label (label => $label);
    my $group = $groups_in_range->[0];
    my $list_vals = $sp->get_list_values (element => $group, list => $list_to_collate);
    push @list_of_results, {$label => $list_vals};

    print "";  #  for debugger
}


$bd->save_to (filename => $bd_out_file);

#  convert @list_of_results into a html table
my @table;
my $first_row  = $list_of_results[0];
my ($null, $first_list) = each %$first_row;

my @header = sort keys %$first_list;
push @table, ['label', map {"$list_to_collate ($_)"} @header];

foreach my $this_hash (@list_of_results) {
    my ($label, $hash_ref) = each %$this_hash;
    push @table, [$label, @$hash_ref{@header}];
}

#my $t_table = transpose_array (\@table);
my $t_table = \@table;  #  don't transpose

my $qt = HTML::QuickTable->new;
my $html = $qt->render($t_table);
open (my $fh, '>', $out_file)
    || croak "Cannot open $out_file\n";
print {$fh} $html;
$fh->close;


say 'END';

sub transpose_array {
    my $array = shift;
    
    my $out_array;
    my $i = 0;
    foreach my $row (@$array) {
        my $j = 0;
        foreach my $value (@$row) {
            $out_array->[$j][$i] = $value;
            $j ++;
        }
        $i ++;
    }
    
    return $out_array;
}
