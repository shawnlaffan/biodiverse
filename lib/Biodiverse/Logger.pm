package Biodiverse::Logger;
use strict;
use warnings;

our $VERSION = '6.99_001';

use Log::Any;
use Log::Any::Adapter ('Stdout');

our @ISA = qw (Exporter);
our @EXPORT_OK = qw /logger/;

our $logger = Log::Any->get_logger;

#  might not need this now
sub set_logger_adapter {
    my ($self, $adapter, $dispatcher) = @_;
    Log::Any::Adapter->set($adapter, dispatcher => $dispatcher);
}

sub set_logger {
    my ($self, $log_arg) = @_;
    $logger = $log_arg;
}

sub get_logger {
    $logger;
}

sub logger {
    $logger;
}


1;