#!perl

#  make sure all biodiverse modules are of the same version

use strict;
use warnings;


use Test::More;

#my @files;
use FindBin qw { $Bin };
use File::Spec;
use File::Find;  #  should switch to use File::Next

use rlib;

use Biodiverse::BaseData;

#  list of files
our @files;

my $wanted = sub {
    # only operate on Perl modules
    return if $_ !~ m/\.pm$/;
    return if $File::Find::name !~ m/Biodiverse/;
    return if $File::Find::name =~ m/Bundle/;

    my $filename = $File::Find::name;
    $filename =~ s/\.pm$//;
    if ($filename =~ /((?:App\/)?Biodiverse.*)$/) {
        $filename = $1;
    }
    $filename =~ s{/}{::}g;
    push @files, $filename;
};

my $lib_dir = File::Spec->catfile( $Bin, '..', 'lib' );
find ( $wanted,  $lib_dir );

my $version = $Biodiverse::BaseData::VERSION;

note ( "Testing Biodiverse $version, Perl $], $^X" );

require App::Biodiverse;
my $blah = $App::Biodiverse::VERSION;

FILE:
while (my $file = shift @files) {
    my $loaded = eval qq{ require $file };
    my $msg_extra = q{};
    if (!$loaded) {
        $msg_extra = " (Unable to load $file).";
        diag "Unable to load $file, skipping";
        next FILE;
    }
    my $this_version = eval '$' . $file . q{::VERSION};
    my $msg = "$file is $version." . $msg_extra;
    is ( $this_version, $version, $msg );
}

done_testing();
