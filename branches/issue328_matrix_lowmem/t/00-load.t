#!perl

use Test::More;

#my @files;
use FindBin qw { $Bin };
use File::Spec;
use File::Find;

use rlib;

#  list of files
our @files;

sub Wanted {
    # only operate on Perl modules
    return if $_ !~ m/\.pm$/;
    return if $File::Find::name !~ m/Biodiverse/;
    return if $File::Find::name =~ m/Task/;    #  ignore Task files
    return if $File::Find::name =~ m/Bundle/;  #  ignore Bundle files

    my $filename = $File::Find::name;
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
