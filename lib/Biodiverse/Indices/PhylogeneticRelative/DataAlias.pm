package Biodiverse::Indices::PhylogeneticRelative::DataAlias;
use strict;
use warnings;

our $VERSION = '2.00';

use Data::Alias qw /alias/;

sub _calc_phylo_rpe1_inner {
    my ($self, %args) = @_;

    #  get the WE score for the set of terminal nodes in this neighbour set
    my $we;
    my $label_hash = $args{PHYLO_LABELS_ON_TRIMMED_TREE};
    alias my %weights = %{$args{ENDW_WTLIST}};

    foreach my $label (keys %$label_hash) {
        next if ! exists $weights{$label};  #  This should not happen.  Maybe should croak instead?
        #next if ! $tree->node_is_in_tree(node => $label);  #  list has already been filtered to trimmed tree
        $we += $weights{$label};
    }
    
    #  no explicit return for a bit of speed
    $we;
}


1;
