#  logic based on pp_simple.pl

use 5.020;
use warnings;
use strict;
use Carp;

use Data::Dump       qw/ dd /;
use File::Which      qw( which );
use Capture::Tiny    qw/ capture /;
use List::Util       qw( uniq );
use File::Find::Rule qw/ rule find /;
use Storable         qw/ retrieve /;
use Path::Tiny       qw/ path /;

use Module::ScanDeps;

#my $PP        = which('pp')       or die "pp not found";
my $OBJDUMP   = which('objdump')  or die "objdump not found";

my @exe_path = grep {/berrybrew/} split ';', $ENV{PATH};

#  need to use GetOpts variant, and pass through any Module::ScanDeps args
my $script = $ARGV[0] or die 'no argument passed';
my $no_execute = $ARGV[1];

my $dll_files = get_dep_dlls ($script, $no_execute);
my @dlls = @$dll_files;

my $re_skippers = get_skipper_regexp();
my %full_list;
my %searched_for;
my $iter = 0;
while (1) {
    $iter++;
    say "Iter:  $iter";
    my( $stdout, $stderr, $exit ) = capture {
        system( $OBJDUMP, '-p', @dlls );
    };
    if( $exit ) {
        $stderr =~ s{\s+$}{};
        warn "(@dlls):$exit: $stderr ";
        exit;
    }
    @dlls = $stdout =~ /DLL.Name:\s*(\S+)/gmi;
    #  extra grep is wasteful but also useful for debug 
    #  since we can easily disable it
    @dlls
      = uniq
        sort
        grep {!exists $full_list{$_}}
        grep {$_ !~ /$re_skippers/}
        @dlls;
    say join ' ', @dlls;
    last if !@dlls;
    my @dll2;
    foreach my $file (@dlls) {
        next if $searched_for{$file};
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
        #my @check = grep {/$re_skippers/} @locs;
        push @dll2, @locs;
        $searched_for{$file}++;
    }
    @dlls = uniq @dll2;
    my $key_count = keys %full_list;
    @full_list{@dlls} = (1) x @dlls;
    last if $key_count == scalar keys %full_list;

    #say join ' ', @dlls;
}

say "\n==========\n\n";
my @l2 = map {('--link' => $_)} sort +(uniq keys %full_list);
say join " ", @l2;

#  Should really only need perl526 since we skip windows dir
#  in the search
sub get_skipper_regexp {
    my @skip = qw /
        KERNEL32.dll msvcrt.dll
        perl5\d\d.dll
        ADVAPI32.dll
        ole32.dll
        USER32.dll WINMM.dll WS2_32.dll
        SHELL32.dll
    /;
    my $sk = join '|', @skip;
    my $qr_skip = qr /$sk/;
    return $qr_skip;
}


sub get_dep_dlls {
    my ($script, $no_execute) = @_;
    
    my $deps_hash = scan_deps(
        files   => [ $script ],
        recurse => 1,
        execute => !$no_execute,
    );

    my %dll_hash;
    foreach my $package (keys %$deps_hash) {
        #  could get {uses} directly, but this helps with debug
        my $details = $deps_hash->{$package};
        my $uses = $details->{uses};
        next if !$uses;
        foreach my $dll (grep {/dll$/} @$uses) {
            my $dll_path = $deps_hash->{$package}{file};
            #  Remove trailing component after lib
            #  Clunky and likely to fail.
            $dll_path =~ s|(?<=/lib/).+?$||;
            $dll_path .= $dll;
            croak "cannot find $dll_path for package $package"
              if not -e $dll_path;
            $dll_hash{$dll_path}++;
        }
    }
    
    return [sort keys %dll_hash];
}
