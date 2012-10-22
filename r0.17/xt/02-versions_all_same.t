#!perl

#  make sure all biodiverse modules are of the same version

use strict;
use warnings;


use Test::More;

#my @files;
use FindBin qw { $Bin };
use File::Spec;
use File::Find;

use mylib;

#  list of files
our @files;

BEGIN {
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
    
    #my @files;
    my $lib_dir = File::Spec->catfile( $Bin, '..' );
    find ( $wanted,  $lib_dir );
    #print join q{ }, @files;
    #}
    
    
    my $f1 = shift @files;
    eval qq { require $f1 };
    my $version = eval '$' . $f1 . q{::VERSION};
    
    diag( "Testing Biodiverse $version, Perl $], $^X" );
    
    while (my $file = shift @files) {
        eval qq{ require $file };
        my $this_version = eval '$' . $file . q{::VERSION};
        my $msg = "$file is $version";
        is ( $version, $this_version, $msg );
    }

}

done_testing();
