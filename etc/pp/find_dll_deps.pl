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
#use Config;

my $OBJDUMP   = which('objdump')  or die "objdump not found";

my @exe_path = split ';', $ENV{PATH};
#  skip anything under the Windows folder
@exe_path = grep {$_ !~ m|^[a-z]\:[/\\]windows|i} @exe_path;

my $RE_DLL_EXT = qr/\.dll/i;

#  need to use GetOpts variant, and pass through any Module::ScanDeps args
my $script = $ARGV[0] or die 'no argument passed';
my $no_execute = $ARGV[1];

my @dlls = get_dep_dlls ($script, $no_execute);

my $re_skippers = get_dll_skipper_regexp();
my %full_list;
my %searched_for;
my $iter = 0;
while (1) {
    $iter++;
    say "Iter:  $iter";
    say join ' ', @dlls;
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
      = sort
        grep {!exists $full_list{$_}}
        grep {$_ !~ /$re_skippers/}
        uniq
        @dlls;
    
    last if !@dlls;
    my @dll2;
    foreach my $file (@dlls) {
        next if $searched_for{$file};
        #  don't recurse
        my $rule = File::Find::Rule->new->maxdepth(1);
        $rule->file;
        $rule->name (qr/^\Q$file\E$/i);  #  case insensitive
        $rule->start (@exe_path);
      MATCH:
        while (my $f = $rule->match) {
            push @dll2, $f;
            #say "XXXX: $f";
            last MATCH;
        }

        $searched_for{$file}++;
    }
    @dlls = uniq @dll2;
    my $key_count = keys %full_list;
    @full_list{@dlls} = (1) x @dlls;
    #  did we add anything new?
    last if $key_count == scalar keys %full_list;

}

say "\n==========\n\n";
my @l2 = map {('--link' => $_)} sort +(uniq keys %full_list);
say join " ", @l2;

sub get_dll_skipper_regexp {
    #  used to be more here from windows folder
    #  but we avoid them in the first place now
    my @skip = qw /
        perl5\d\d
    /;
    my $sk = join '|', @skip;
    my $qr_skip = qr /^(?:$sk)$RE_DLL_EXT$/;
    return $qr_skip;
}

#  find dependent dlls
#  could also adapt some of Module::ScanDeps::_compile_or_execute
#  as it handles more edge cases
sub get_dep_dlls {
    my ($script, $no_execute) = @_;
    
    #  make sure $script/../lib is in @INC
    #  assume script is in a bin folder
    my $script_path = path ($script)->parent->parent->stringify;    
    #say "======= $script_path/lib ======";
    local @INC = (@INC, "$script_path/lib")
      if -d "$script_path/lib";

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
        foreach my $dll (grep {$_ =~ $RE_DLL_EXT} @$uses) {
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
    
    my @dll_list = sort keys %dll_hash;
    return wantarray ? @dll_list : \@dll_list;
}
