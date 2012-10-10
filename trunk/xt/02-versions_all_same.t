#!perl

#  make sure all biodiverse modules are of the same version

use strict;
use warnings;


use Test::More;

#my @files;
use FindBin qw { $Bin };
use File::Spec;
use File::Find;

use rlib;

#  list of files
our @files;

my $wanted = sub {
    # only operate on Perl modules
    return if $_ !~ m/\.pm$/;
    return if $File::Find::name !~ m/Biodiverse/;
    return if $File::Find::name =~ m/Bundle/;

    my $filename = $File::Find::name;
    $filename =~ s/\.pm$//;
    $filename =~ s/.+(Biodiverse.+)/$1/;
    $filename =~ s{/}{::}g;
    push @files, $filename;
};

my $lib_dir = File::Spec->catfile( $Bin, '..', 'lib' );
find ( $wanted,  $lib_dir );    

my $f1 = shift @files;
eval qq { require $f1 };
my $version = eval '$' . $f1 . q{::VERSION};

note ( "Testing Biodiverse $version, Perl $], $^X" );

while (my $file = shift @files) {
    eval qq{ require $file };
    my $this_version = eval '$' . $file . q{::VERSION};
    my $msg = "$file is $version";
    is ( $version, $this_version, $msg );
}

done_testing();
