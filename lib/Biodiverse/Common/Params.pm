package Biodiverse::Common::Params;
use 5.036;
use strict;
use warnings;

our $VERSION = '4.99_006';

use Carp qw /croak/;
use Scalar::Util qw /blessed isweak reftype weaken/;

#  is this used anymore?
sub load_params {  # read in the parameters file, set the PARAMS subhash.
    my $self = shift;
    my %args = @_;

    open (my $fh, '<', $args{file}) || croak ("Cannot open $args{file}\n");

    local $/ = undef;
    my $data = <$fh>;
    $fh->close;

    my %params = eval ($data);
    $self->set_param(%params);

    return;
}

#  extremely hot path, so needs to be lean and mean, even if less readable
sub get_param {
    #  It's OK to have PARAMS hash entry,
    #  and newer perls have faster hash accesses
    #no autovivification;
    $_[0]->{PARAMS}{$_[1]};
}

#  sometimes we want a reference to the parameter to allow direct manipulation.
#  this is only really needed if it is a scalar, as lists are handled as refs already
sub get_param_as_ref {
    my $self = shift;
    my $param = shift;

    return if ! $self->exists_param ($param);

    my $value = $self->get_param ($param);
    #my $test_value = $value;  #  for debug
    if (not ref $value) {
        $value = \$self->{PARAMS}{$param};  #  create a ref if it is not one already
        #  debug checker
        #carp "issues in get_param_as_ref $value $test_value\n" if $$value ne $test_value;
    }

    return $value;
}

#  sometimes we only care if it exists, as opposed to its being undefined
sub exists_param {
    my $self = shift;
    my $param = shift;
    croak "param not specified\n" if !defined $param;

    my $x = exists $self->{PARAMS}{$param};
    return $x;
}

sub get_params_hash {
    my $self = shift;
    my $params = $self->{PARAMS};

    return wantarray ? %$params : $params;
}

#  set a single parameter
sub set_param {
    $_[0]->{PARAMS}{$_[1]} = $_[2];

    1;
}

#  Could use a slice for speed, but it's not used very often.
#  Could also return 1 if it is ever used in hot paths.
sub set_params {
    my $self = shift;
    my %args = @_;

    foreach my $param (keys %args) {
        $self->{PARAMS}{$param} = $args{$param};
    }

    return scalar keys %args;
}

sub delete_param {  #  just passes everything through to delete_params
    my $self = shift;
    $self->delete_params(@_);

    return;
}

#  sometimes we have a reference to an object we wish to make weak
sub weaken_param {
    my $self = shift;
    my $count = 0;

    foreach my $param (@_) {
        if (! exists $self->{PARAMS}{$param}) {
            croak "Cannot weaken param $param, it does not exist\n";
        }

        if (not isweak ($self->{PARAMS}{$param})) {
            weaken $self->{PARAMS}{$param};
            #print "[COMMON] Weakened ref to $param, $self->{PARAMS}{$param}\n";
        }
        $count ++;
    }

    return $count;
}

sub delete_params {
    my $self = shift;

    scalar delete @{$self->{PARAMS}}{@_};
}

#  an internal apocalyptic sub.  use only for destroy methods
sub _delete_params_all {
    my $self = shift;
    my $params = $self->{PARAMS};

    foreach my $param (keys %$params) {
        print "Deleting parameter $param\n";
        delete $params->{$param};
    }
    $params = undef;

    return;
}

sub print_params {
    my $self = shift;
    use Data::Dumper ();
    print Data::Dumper::Dumper ($self->{PARAMS});

    return;
}

sub increment_param {
    my ($self, $param, $value) = @_;
    $self->{PARAMS}{$param} += $value;
}


###  Disable this - user defined params have not been needed for a long time
###  In the original spec we could allow overrides for sep chars and the like
###  but that way leads to madness.
#  Load a hash of any user defined default params
our %user_defined_params;
#BEGIN {

#  load user defined indices, but only if the ignore flag is not set
#if (     exists $ENV{BIODIVERSE_DEFAULT_PARAMS}
#    && ! $ENV{BIODIVERSE_DEFAULT_PARAMS_IGNORE}) {
#    print "[COMMON] Checking and loading user defined globals";
#    my $x;
#    if (-e $ENV{BIODIVERSE_DEFAULT_PARAMS}) {
#        print " from file $ENV{BIODIVERSE_DEFAULT_PARAMS}\n";
#        local $/ = undef;
#        open (my $fh, '<', $ENV{BIODIVERSE_DEFAULT_PARAMS});
#        $x = eval (<$fh>);
#        close ($fh);
#    }
#else {
#    print " directly from environment variable\n";
#    $x = eval "$ENV{BIODIVERSE_DEFAULT_PARAMS}";
#}
#    if ($@) {
#        my $msg = "[COMMON] Problems with environment variable "
#                . "BIODIVERSE_DEFAULT_PARAMS "
#                . " - check the filename or syntax\n"
#                . $@
#                . "\n$ENV{BIODIVERSE_DEFAULT_PARAMS}\n";
#        croak $msg;
#    }
#    use Data::Dumper ();
#    print "Default parameters are:\n", Data::Dumper::Dumper ($x);
#
#    if (is_hashref($x)) {
#        @user_defined_params{keys %$x} = values %$x;
#    }
#}
#}

#  assign any user defined default params
#  a bit risky as it allows anything to be overridden
sub set_default_params {
    my $self = shift;
    my $package = ref ($self);

    return if ! exists $user_defined_params{$package};

    #  make a clone to avoid clashes with multiple objects
    #  receiving the same data structures
    my $params = $self->clone (data => $user_defined_params{$package});

    $self->set_params (%$params);

    return;
}


1;
