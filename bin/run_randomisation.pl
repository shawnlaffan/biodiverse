#!/usr/bin/perl -w
use strict;
use warnings;
use 5.010;

use Data::Dumper qw/Dumper/;
use File::Spec;
use FindBin qw { $Bin };
use Carp;
use English qw { -no_match_vars };
use Path::Class;
use Scalar::Util qw /blessed/;

use rlib;

local $| = 1;

our $VERSION = '0.18_007';

use Biodiverse::Config;
use Biodiverse::BaseData;
use Biodiverse::Common;

use Getopt::Long;

my ($in_file, $rand_name, $print_usage);
my %rest_of_args;
my $iterations = 10;


GetOptions (
    "basedata|bd=s"  => \$in_file,
    "rand_name|r=s"  => \$rand_name,
    "iterations|iters|i:i" => \$iterations,
    "args:s{,}"      => \%rest_of_args,
    "help|h" => \$print_usage,
);


my @usage_array = (
    $0
    , '--basedata <file name>'
    , '--rand_name <randomisation name>'
    , '--iterations {iterations [default is 10]}'
    , '--args Rest of randomisation args as key=value pairs, with pairs separated by spaces'
    , '--help Print this usage and exit',
);

my $usage = join "\n", @usage_array;

if ($print_usage) {
    say $usage;
    exit (0);
}

if ($ENV{BDV_PP_BUILDING}) {
    say 'Building pp file';
    use File::BOM qw / :subs /;          #  we need File::BOM.
    open my $fh, '<:via(File::BOM)', $0  #  just read ourselves
      or croak "Cannot open $0 via File::BOM\n";
    $fh->close;
    exit ;
}

my $tmp_bd     = Biodiverse::BaseData->new();
my $extensions = join ('|', $tmp_bd->get_param('OUTSUFFIX'), $tmp_bd->get_param('OUTSUFFIX_YAML'));
my $re_valid   = qr/($extensions)$/i;
croak "$in_file does not have a valid BaseData extension ($extensions)\n" if not $in_file =~ $re_valid;

my $bd = Biodiverse::BaseData->new (file => $in_file);
if (! defined $bd) {
    warn "basedata $bd does not exist - check your path\n";
    exit;
}

my $rand = $bd->get_randomisation_output_ref (name => $rand_name)
        // $bd->add_randomisation_output     (name => $rand_name);


$iterations //= 10;

my $success = eval {
    $rand->run_analysis (
        save_checkpoint => 99,
        iterations      => $iterations,
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
