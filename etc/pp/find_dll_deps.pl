#  logic based on pp_simple.pl

use 5.020;
use warnings;
use strict;

use Data::Dump       qw/ dd /;
use File::Which      qw( which );
use Capture::Tiny    qw/ capture /;
use List::Util       qw( uniq );
use File::Find::Rule qw/ rule find /;
use Storable         qw/ retrieve /;
use Path::Tiny       qw/ path /;

our $PP        = which('pp')       or die "pp not installed ";
our $SCANDEPS  = which('scandeps') or die "scandeps not installed ";
our $OBJDUMP   = which('objdump') ;

my @exe_path = grep {/berrybrew/} split ';', $ENV{PATH};

#my @files = qw /dlls\s1sart_lgpl_2-2.dll dlls\s1sglib-2.0-0.dll/;
my $glob = $ARGV[0] or die 'no argument passed';
#my @files = glob 'dlls\s1s*';
#my @files = glob $glob;
my @dlls = File::Find::Rule->file()
                        ->name( '*.dll' )
                        ->in( $glob );

my %skippers = get_skippers();
my %full_list;

while (1) {
    my( $stdout, $stderr, $exit ) = capture {
        system( $OBJDUMP, '-p', @dlls );
    };
    if( $exit ) {
        $stderr =~ s{\s+$}{};
        warn "(@dlls):$exit: $stderr ";
        exit;
    }
    @dlls = $stdout =~ /DLL.Name:\s*(\S+)/gmi;
    @dlls = uniq sort grep {!exists $full_list{$_} && !exists $skippers{$_}} @dlls;
    say join ' ', @dlls;
    last if !@dlls;
    my @dll2;
    foreach my $file (@dlls) {
        my $rule = File::Find::Rule->new;
        $rule->or(
            $rule->new
                 ->directory
                 ->name('Windows')
                 ->prune
                 ->discard,
            $rule->new
                 ->maxdepth (1)  #  don't recurse
        );
        $rule->file;
        $rule->name ($file);
        my @locs = $rule->in ( @exe_path );
        #my @locs = File::Find::Rule->file()
        #                ->name( $file )
        #                ->in( @exe_path );
        push @dll2, @locs;
    }
    @dlls = uniq @dll2;
    my $key_count = keys %full_list;
    @full_list{@dlls} = (1) x @dlls;
    last if $key_count == scalar keys %full_list;

    #say join ' ', @dlls;
}

say join "\n", sort +(uniq keys %full_list);

#foreach my $file (keys %full_list) {
#    say dll_get_fullpath ( $file );
#}


sub dll_get_fullpath {
    my( $key ) = @_;
    my $short = lc path( $key )->basename; ## yuck
    return  $short ;
}


sub get_skippers {
    my @skip = qw /
        KERNEL32.dll msvcrt.dll
        perl526.dll
        ADVAPI32.dll
        ole32.dll
        USER32.dll WINMM.dll WS2_32.dll
        SHELL32.dll
    /;
    my %skippers;
    @skippers{@skip} = (1) x @skip;
    return %skippers;
}