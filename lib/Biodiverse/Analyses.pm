#  base class for analyses to inherit from
package Biodiverse::Analyses;
use strict;
use warnings;
use 5.036;

our $VERSION = '5.0';

#  Keying by sha allows more general re-use by other code,
#  e.g. derived eq length trees have the same topology.
#  Such ranges are invariant for this basedata.
sub _get_cached_node_range_table_aa {
    my ($self, $tree, $want_lists) = @_;

    return if !defined $tree;

    my $cache = $self->get_cached_href ('get_node_range_hash');
    return if !keys %$cache;

    my $type = $want_lists ? 'return_lists' : 'return_scalars';

    my $sha = $tree->get_sha256_topology;

    no autovivification;
    return $cache->{$sha}{$type};
}

sub _set_cached_node_range_table_aa {
    my ($self, $href, $tree, $want_lists) = @_;

    return if !defined $tree;

    my $cache = $self->get_cached_href ('get_node_range_hash');

    my $type = $want_lists ? 'return_lists' : 'return_scalars';

    my $sha = $tree->get_sha256_topology;

    $cache->{$sha}{$type} = $href;
}

1;