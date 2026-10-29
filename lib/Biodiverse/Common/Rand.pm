package Biodiverse::Common::Rand;
use 5.036;
use strict;
use warnings;

our $VERSION = '6.99_001';

use Carp qw /croak/;
use Scalar::Util qw/blessed/;

use English qw /-no_match_vars/;

#  Need to avoid an OIO destroyed twice warning due
#  to HTTP::Tiny, which is used in Biodiverse::GUI::Help
#  but wrap it in an eval to avoid problems on threaded builds
BEGIN {
    eval 'use threads';
}

use Math::Random::MT::Auto ();

use Biodiverse::Logger qw/logger/;

#  initialise the PRNG with an array of values, start from where we left off,
#     or use default if not specified
sub initialise_rand {
    my $self = shift;
    my %args = @_;
    my $seed  = $args{seed};
    my $state = (!$args{reseed} && blessed $self ? $self->get_param ('RAND_LAST_STATE') : 0)
        || $args{state};

    logger->info("[COMMON] Ignoring PRNG seed argument ($seed) because the PRNG state is defined")
        if defined $seed and defined $state;

    #  don't already have one, generate a new object using seed and/or state params.
    #  the system will initialise in the order of state and seed, followed by its own methods
    my $rand = eval {
        Math::Random::MT::Auto->new (
            seed  => $seed,
            state => $state,  #  will use this if it is defined
        );
    };
    my $e = $EVAL_ERROR;
    if (OIO->caught() && $e =~ 'Invalid state vector') {
        Biodiverse::PRNG::InvalidStateVector->throw (Biodiverse::PRNG::InvalidStateVector->description);
    }
    croak $e if $e;

    if (blessed ($self) && ! defined $self->get_param ('RAND_INIT_STATE')) {
        $self->store_rand_state_init (rand_object => $rand);
    }

    return $rand;
}

sub store_rand_state {  #  we cannot store the object itself, as it does not serialise properly using YAML
    my $self = shift;
    my %args = @_;

    croak "rand_object not specified correctly\n" if ! blessed $args{rand_object};

    my $rand = $args{rand_object};
    my @state = $rand->get_state;  #  make a copy - might reduce mem issues?
    croak "PRNG state not defined\n" if ! scalar @state;

    my $state = \@state;
    $self->set_param (RAND_LAST_STATE => $state);

    if (defined wantarray) {
        return wantarray ? @state : $state;
    }
}

#  Store the initial rand state (assumes it is called at the right time...)
sub store_rand_state_init {
    my $self = shift;
    my %args = @_;

    croak "rand_object not specified correctly\n" if ! blessed $args{rand_object};

    my $rand = $args{rand_object};
    my @state = $rand->get_state;

    my $state = \@state;

    $self->set_param (RAND_INIT_STATE => $state);

    if (defined wantarray) {
        return wantarray ? @state : $state;
    }
}


1;