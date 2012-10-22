#!perl

use Test::More;

#my @files;
use FindBin qw { $Bin };
use File::Spec;
use File::Find;

use mylib;

#  list of files
our @files;

#BEGIN {
    sub Wanted {
        # only operate on Perl modules
        return if $_ !~ m/\.pm$/;
        return if $File::Find::name !~ m/Biodiverse/;
        return if $File::Find::name =~ m/Bundle/;  #  ignore bundle files
        
        my $filename = $File::Find::name;
        $filename =~ s/\.pm$//;
        $filename =~ s/.+(Biodiverse.+)/$1/;
        $filename =~ s{/}{::}g;
        push @files, $filename;
    };
    
    #my @files;
    my $lib_dir = File::Spec->catfile( $Bin, '..' );
    find ( \&Wanted,  $lib_dir );
    #print join q{ }, @files;
#}
    use Biodiverse::Config;
    diag( "Testing Biodiverse $Biodiverse::Config::VERSION, Perl $], $^X" );

    foreach my $file (@files) {
        use_ok ( $file );
    }
#}


done_testing();
