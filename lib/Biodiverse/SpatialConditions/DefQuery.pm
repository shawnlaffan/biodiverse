package Biodiverse::SpatialConditions::DefQuery;

use warnings;
use strict;

use English qw ( -no_match_vars );

use Carp;

use parent qw /Biodiverse::SpatialConditions/;

our $VERSION = '5.0';

sub get_type {return 'definition query'};

sub is_def_query {return 1};

sub get_current_coord_id {
    my ($self, %args) = @_;

    #  most common case is called without args
    my $h = $self->get_current_args;
    return $h->{coord_id1}
        if !defined $args{type};

    my $type = $args{type};
    croak "Invalid type arg $type"
        if $type && !($type eq 'proc' || $type eq 'nbr');

    return $type eq 'proc'
        ? $h->{coord_id1}
        : $h->{coord_id2};
}

sub get_current_coord_array {
    my ($self, %args) = @_;

    #  most common case is called without args
    my $h = $self->get_current_args;
    return $h->{coord_array}
        if !defined $args{type};

    my $type = $args{type} // 'proc';
    croak "Invalid type arg $type" if !($type eq 'proc' || $type eq 'nbr');

    return $type eq 'proc'
        ? $h->{coord_array}
        : $h->{nbrcoord_array};
}

=head1 NAME

Biodiverse::SpatialConditions::DefQuery

=head1 SYNOPSIS

  use Biodiverse::SpatialConditions::DefQuery;
  $object = Biodiverse::SpatialConditions::DefQuery->new();

=head1 DESCRIPTION

This is just a special SpatialConditions object that allows better behaviour
as a definition query.  

It inherits from Biodiverse::SpatialConditions so has all of those methods.

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

1;
