#  wrapper for load_and_randomise.pl
#  Biodiverse appears to have a memory leak somewhere,
#  so this is a means of clearing the memory every couple of iterations
#   by restarting the prel process.

use strict;
use warnings;
use FindBin qw { $Bin };
use English qw { -no_match_vars };
use Carp;
use File::Spec;

use Path::Class;

#use lib Path::Class::dir ( $Bin, '..', 'lib')->stringify;
use rlib;

our $VERSION = '2.99_002';

#  are we running as a PerlApp executable?
my $perl_app_tool = $PerlApp::TOOL;

######################################


my $usage = "$0 <basedata file> <randomisation name> {runs [1]} "
            . "{iterations=[10]} {rest of args}\n";

if (! $perl_app_tool) {
    $usage = 'perl ' . $usage;
}

if (scalar @ARGV < 2) {
    print "Usage:\n$usage\n";
    exit;
}

my $in_file = shift @ARGV;
my $rand_name = shift @ARGV;
my $runs = shift @ARGV;
#my $iterations = shift @ARGV;
my @rest_of_args = @ARGV;

$rand_name = qq{"$rand_name"};  #  add quotes in case we have spaces

if (not defined $runs) {
    $runs = 1;
}
#if (not defined $iterations) {
#    $iterations = 10;
#}

$in_file = File::Spec->rel2abs($in_file);


my $script_name = 'load_and_randomise.pl';
my $script = File::Spec -> catfile ($FindBin::Bin, $script_name);

#  need to get it from the perlapp bindings?
if ($perl_app_tool eq 'PerlApp') {
    $script_name = 'load_and_randomise.exe';
    print "Extracting bound file $script_name\n";
    eval {
        $script = PerlApp::extract_bound_file ($script_name)
    };
    croak $EVAL_ERROR if $EVAL_ERROR;
}

#  if the script is a perl file then use perl,
#  otherwise it is probably an exe
my $cmd_pfx = ($script =~ /pl$/)
                ? 'perl'
                : q{};

my $success = 0;
foreach my $i (1 .. $runs) {

    print "Run $i, running\n";
    
    my $target_file = qq{"$in_file"};
    
    my @command = ($cmd_pfx, $script, $target_file, $rand_name, @rest_of_args);
    shift @command if !$cmd_pfx;

    print "@command\n";

    my $status = system (@command);
    
    if (! $status) {
        warn "Child process failed\n";
        exit;
    }
    else {
        $success ++;
    }
}

if (! $success) {
    exit;
}

1;
