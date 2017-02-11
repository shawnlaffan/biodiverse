#!perl

use Test::More;

#my @files;
use FindBin qw { $Bin };
use File::Spec;
use File::Find;

use Test::Lib;
use rlib;

#  need to move GUI modules into their own test file
BEGIN {
    if (!$ENV{BD_NO_TEST_GUI}) {
        eval 'use Biodiverse::GUI::GUIManager';  #  trigger loading of Gtk libs on Windows
    }
}

#  list of files
our @files;

sub Wanted {
    # only operate on Perl modules
    return if $_ !~ m/\.pm$/;
    my $filename = $File::Find::name;
    
    return if $filename !~ m/Biodiverse/;
    return if $filename =~ m/Task/;    #  ignore Task files
    return if $filename =~ m/Bundle/;  #  ignore Bundle files
    #  avoid ref/data alias as only one works at a time
    return if $filename =~ m/(?:Data|Ref)Alias\.pm$/;
    #  ignore GUI files
    return if $ENV{BD_NO_TEST_GUI} && $filename =~ m/GUI/;

    $filename =~ s/\.pm$//;
    if ($filename =~ /((?:App\/)?Biodiverse.*)$/) {
        $filename = $1;
    }
    $filename =~ s{/}{::}g;
    push @files, $filename;
};


my $lib_dir = File::Spec->catfile( $Bin, '..', 'lib' );
find ( \&Wanted,  $lib_dir );


use Biodiverse::Config;
note ( "Testing Biodiverse $Biodiverse::Config::VERSION, Perl $], $^X" );

foreach my $file (@files) {
    use_ok ( $file );
}



done_testing();
