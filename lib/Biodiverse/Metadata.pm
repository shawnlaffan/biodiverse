package Biodiverse::Metadata;
use 5.016;
use strict;
use warnings;
use Ref::Util qw { :all };

our $VERSION = '4.99_001';

sub new {
    my ($class, $data) = @_;
    $data //= {};
    
    my $self = bless $data, $class;
    return $self;
}


sub _make_access_methods {
    my ($pkg, $methods) = @_;
#print "Calling _make_access_methods for $pkg";
    no strict 'refs';
    foreach my $key (keys %$methods) {
        *{$pkg . '::' . 'get_' . $key} =
            do {
                sub {
                    my $self = shift;
                    return $self->{$key} // $self->get_default_value ($key);
                };
            };
        *{$pkg . '::' . 'set_' . $key} =
            do {
                sub {
                    my ($self, $val) = @_;
                    $self->{$key} = $val;
                };
            };
    }

    return;
}

sub get_default_value {
    my ($self, $key) = @_;

    #  set defaults - make sure they are new each time
    my %defaults = $self->_get_method_default_hash;
    my $default  = $defaults{$key};

    return $default if !defined $default or !is_ref ($default);

    if (is_arrayref($default)) {
        $default = [];
    }
    elsif (is_hashref($default)) {
        $default = {};
    }
    return $default;
}

sub clone {
    my $self = shift;

    my ($cloneref, $e);

    my $encoder = Sereal::Encoder->new({
        undef_unknown => 1,  #  strip any code refs
    });
    my $decoder = Sereal::Decoder->new();
    eval {
        $decoder->decode ($encoder->encode($self), $cloneref);
    };
    $e = $@;
    
    croak $e if $e;

    return $cloneref;
}

1;
