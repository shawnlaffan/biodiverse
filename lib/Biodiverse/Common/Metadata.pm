package Biodiverse::Common::Metadata;
use 5.036;
use strict;
use warnings;

our $VERSION = '4.99_006';

use Carp qw /croak/;
use English ( -no_match_vars );
use Scalar::Util qw /blessed isweak reftype weaken/;
use List::MoreUtils qw /none/;
use List::Util qw /first/;

sub get_metadata {
    my $self = shift;
    my %args = @_;

    croak 'get_metadata called in list context'
        if wantarray;

    my $use_cache = !$args{no_use_cache};
    my ($cache, $metadata);
    my $subname = $args{sub};

    #  Some metadata depends on given arguments,
    #  and these could change across the life of an object.
    if (blessed ($self) && $use_cache) {
        $cache = $self->get_cached_metadata;
        $metadata = $cache->{$subname};
    }

    if (!$metadata) {
        $metadata = $self->get_args(@_);

        if (not blessed $metadata) {
            croak "metadata for $args{sub} is not blessed (caller is $self)\n";  #  only when debugging
            #$metadata = $metadata_class->new ($metadata);
        }
        if ($use_cache) {
            $cache->{$subname} = $metadata;
        }
    }

    return $metadata;
}

sub get_cached_metadata {
    my $self = shift;

    my $cache
        = $self->get_cached_value_dor_set_default_href ('METADATA_CACHE');
    #  reset the cache if the versions differ (typically they would be older),
    #  this ensures new options are loaded
    $cache->{__VERSION} //= 0;
    if ($cache->{__VERSION} ne $VERSION or $ENV{BD_NO_METADATA_CACHE}) {
        %$cache = ();
        $cache->{__VERSION} = $VERSION;
    }
    return $cache;
}

sub delete_cached_metadata {
    my $self = shift;

    delete $self->{_cache}{METADATA_CACHE};
}

#my $indices_wantarray = 0;
#  get the metadata for a subroutine
sub get_args {
    my $self = shift;
    my %args = @_;
    my $sub = $args{sub} || croak "sub not specified in get_args call\n";

    my $metadata_sub = "get_metadata_$sub";
    if (my ($package, $subname) = $sub =~ / ( (?:[^:]+ ::)+ ) (.+) /xms) {
        $metadata_sub = $package . 'get_metadata_' . $subname;
    }

    my $sub_args;

    #  use an eval to trap subs that don't allow the get_args option
    $sub_args = eval {$self->$metadata_sub (%args)};
    my $error = $EVAL_ERROR;

    if (blessed $error and $error->can('rethrow')) {
        $error->rethrow;
    }
    elsif ($error) {
        my $msg = '';
        if (!$self->can($metadata_sub)) {
            $msg = "cannot call method $metadata_sub for object $self\n"
        }
        elsif (!$self->can($sub)) {
            $msg = "cannot call method $sub for object $self, and thus its metadata\n"
        }
        elsif (not blessed $self) {
            #  trap a very old caller style, should not exist any more
            $msg = "get_args called in non-OO manner - this is deprecated.\n"
        }
        croak $msg . $error;
    }

    $sub_args //= {};

    #my $wa = wantarray;
    #$indices_wantarray ++ if $wa;
    #croak "get_args called in list context " if $wa;
    return wantarray ? %$sub_args : $sub_args;
}



1;
