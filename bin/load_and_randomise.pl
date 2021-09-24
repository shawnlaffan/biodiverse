#!/usr/bin/perl -w
use strict;
use warnings;

use Data::Dumper qw/Dumper/;
use File::Spec;
use FindBin qw { $Bin };
use Carp;
use English qw { -no_match_vars };
use Path::Class;
use Scalar::Util qw /blessed/;

#use lib Path::Class::dir ( $Bin, '..', 'lib')->stringify;
use rlib;

local $| = 1;

our $VERSION = '3.99_001';

use Biodiverse::Config;

use Biodiverse::BaseData;
use Biodiverse::Common;


my $usage = "$0 <basedata file> <randomisation name> {iterations=[10]}\n";

if (scalar @ARGV < 2) {
    print $usage;
    exit;
}

my $in_file = shift @ARGV;
my $rand_name = shift @ARGV;

my %rest_of_args;
foreach my $arg (@ARGV) {
    my ($key, $value) = split (/=/, $arg);
    
    if (! defined $key || ! defined $value) {
        warn qq{Argument "$arg": not valid as a key=value pair\n};
        exit;
    }
    
    $rest_of_args{$key} = $value;
}

my $tmp_bd = Biodiverse::BaseData->new();
my $extensions = join ("|", $tmp_bd->get_param('OUTSUFFIX'), $tmp_bd->get_param('OUTSUFFIX_YAML'));
my $re_valid = qr/($extensions)$/i;
croak "$in_file does not have a valid BaseData extension ($extensions)\n" if not $in_file =~ $re_valid;

my $bd = Biodiverse::BaseData->new (file => $in_file);
if (! defined $bd) {
    warn "basedata $bd does not exist - check your path\n";
    exit;
}

my $rand = $bd->get_randomisation_output_ref (name => $rand_name);
if (not $rand) {
    $rand = $bd->add_randomisation_output (name => $rand_name);
}

if (! defined $rest_of_args{iterations}) {
    $rest_of_args{iterations} = 10;
}

my $success = eval {
    $rand->run_analysis (
        save_checkpoint => 99,
        %rest_of_args,
    );
};
if ($EVAL_ERROR) {
    report_error ($EVAL_ERROR);
    exit;
}


croak "Analysis not successful\n"
  if ! $success;

#  $success==2 means nothing ran
if ($success == 1) {
    eval {
        $bd->save (filename => $in_file);
        #die "checking";
    };
    if ($EVAL_ERROR) {
        report_error ($EVAL_ERROR);
        exit;
    }
}

exit $success;


sub report_error {
    my $error = shift;
    
    if (blessed $error) {
        warn $error->error, "\n\n", $error->trace->as_string, "\n";
        
    }
    else {
        warn $error;
    }
}
