use strict;
use warnings;

use Test2::V0;

#  run first/early
# HARNESS-CATEGORY-IMMISCIBLE


#my @files;
use FindBin qw { $Bin };
use File::Spec;
use File::Find;

use Test::Lib;
use rlib;

#  need to move GUI modules into their own test file
BEGIN {
    if ($ENV{BD_TEST_GUI}) {
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
    return if !$ENV{BD_TEST_GUI} && $filename =~ m/GUI/;

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
    my $loaded = eval "require $file";
    ok $loaded, "Can load $file";
}

diag '';
diag 'Aliens:';
my %alien_versions;
my @aliens = qw /
      Alien::gdal   Alien::geos::af  Alien::sqlite
      Alien::proj   Alien::libtiff   Alien::spatialite
      Alien::freexl
/;
foreach my $alien (@aliens) {
    eval "require $alien; 1";
    if ($@) {
         diag "$alien not installed";
         next;
    }
    diag sprintf "%s: version: %s, install type: %s",
         $alien,
         $alien->version // 'unknown',
         $alien->install_type;
    $alien_versions{$alien} = $alien->version;
}

if ($alien_versions{'Alien::gdal'} ge 3) {
    if ($alien_versions{'Alien::proj'} lt 7) {
        diag 'Alien proj is <7 when gdal >=3';
    }
}
else {
    if ($alien_versions{'Alien::proj'} ge 7) {
        diag 'Alien proj is >=7 when gdal <3';
    }
}

my $locale_is_comma;
BEGIN {
    use POSIX qw /locale_h/;
    my $locale_values = localeconv();
    $locale_is_comma = $locale_values->{decimal_point} eq ','; 
}
use constant LOCALE_USES_COMMA_RADIX => $locale_is_comma;
diag "Radix char is "
   . (LOCALE_USES_COMMA_RADIX ? '' : 'not ')
   . 'a comma.';

done_testing();
