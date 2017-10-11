#  logic initially based on pp_simple.pl
#  Should cache the Module::Scandeps result
#  and then clean it up after using it.

use 5.020;
use warnings;
use strict;

use Carp;
use English qw / -no_match_vars/;

use Data::Dump       qw/ dd /;
use File::Which      qw( which );
use Capture::Tiny    qw/ capture /;
use List::Util       qw( uniq );
use File::Find::Rule qw/ rule find /;
use Path::Tiny       qw/ path /;
use Cwd              qw/ abs_path /;
use File::Temp       qw/ tempfile /;
use Module::ScanDeps;

use Config;

my $RE_DLL_EXT = qr/\.$Config::Config{so}/i;

#  messy arg handling - ideally would use a GetOpts variant that allows
#  pass through to pp without needing to set them after --
#  Should also trap any scandeps args (if diff from pp).
#  pp also allows multiple .pl files.
my $script_fullname = $ARGV[-1] or die 'no input file specified';
#  does not handle -x as a value for some other arg like --somearg -x
my $no_execute_flag = not grep {$_ eq '-x'} @ARGV;  

#  Try caching - scandeps will execute for us, and then we use a cache file
#  Nope, did not get it to work, so disable for now
#my @args_for_pp = grep {$_ ne '-x'} @ARGV;
my @args_for_pp = @ARGV;

my ($cache_fh, $cache_file);
#($cache_fh, $cache_file)
#  = tempfile( 'pp_autolink_cache_file_XXXXXX',
#               TMPDIR => 1
#            );

die "Script $script_fullname does not have a .pl extension"
  if !$script_fullname =~ /\.pl$/;

my @links = map {('--link' => $_)}
            get_autolink_list ($script_fullname, $no_execute_flag);

say 'Detected link list: ' . join ' ', @links;

my @command = (
    'pp',
    @links,
    #"--cachedeps=$cache_file",
    @args_for_pp,
);

#say join ' ', @command;
system @command;

#undef $cache_fh;
#unlink $cache_file;

sub get_autolink_list {
    my ($script, $no_execute_flag) = @_;

    my $OBJDUMP   = which('objdump')  or die "objdump not found";
    
    my $env_sep  = $OSNAME =~ /MSWin/i ? ';' : ':';
    my @exe_path = split $env_sep, $ENV{PATH};

    if ($OSNAME =~ /MSWin32/i) {
        #  skip anything under the C:\Windows folder
        my $system_root = $ENV{SystemRoot};
        @exe_path = grep {$_ !~ m|^\Q$system_root\E|i} @exe_path;
        #say "PATHS: " . join ' ', @exe_path;
    }
    #  what to skip for linux or mac?

    my @dlls = get_dep_dlls ($script, $no_execute_flag);
    
    #say join "\n", @dlls;
    
    my $re_skippers = get_dll_skipper_regexp();
    my %full_list;
    my %searched_for;
    my $iter = 0;

  DLL_CHECK:
    while (1) {
        $iter++;
        say "DLL check iter: $iter";
        #say join ' ', @dlls;
        my ( $stdout, $stderr, $exit ) = capture {
            system( $OBJDUMP, '-p', @dlls );
        };
        if( $exit ) {
            $stderr =~ s{\s+$}{};
            warn "(@dlls):$exit: $stderr ";
            exit;
        }
        @dlls = $stdout =~ /DLL.Name:\s*(\S+)/gmi;
        #  extra grep is wasteful but useful for debug 
        #  since we can easily disable it
        @dlls
          = sort
            grep {!exists $full_list{$_}}
            grep {$_ !~ /$re_skippers/}
            uniq
            @dlls;
        
        if (!@dlls) {
            say 'no more DLLs';
            last DLL_CHECK;
        }
        
        #say join "\n", @dlls;
        
        my @dll2;
        foreach my $file (@dlls) {
            next if $searched_for{$file};
            #  don't recurse
            my $rule = File::Find::Rule->new->maxdepth(1);
            $rule->file;
            #  need case insensitive match for Windows
            $rule->name (qr/^\Q$file\E$/i);
            $rule->start (@exe_path);
            #  don't search the whole path every time
          MATCH:
            while (my $f = $rule->match) {
                push @dll2, $f;
                last MATCH;
            }
    
            $searched_for{$file}++;
        }
        @dlls = uniq @dll2;
        my $key_count = keys %full_list;
        @full_list{@dlls} = (1) x @dlls;
        
        #  did we add anything new?
        last DLL_CHECK if $key_count == scalar keys %full_list;
    }
    
    my @l2 = sort keys %full_list;

    return wantarray ? @l2 : \@l2;
}

sub get_dll_skipper_regexp {
    #  PAR packs these automatically these days.
    my @skip = qw /
        perl5\d\d
        libstdc\+\+\-6
        libgcc_s_seh\-1
        libwinpthread\-1
    /;
    my $sk = join '|', @skip;
    my $qr_skip = qr /^(?:$sk)$RE_DLL_EXT$/;
    return $qr_skip;
}

#  find dependent dlls
#  could also adapt some of Module::ScanDeps::_compile_or_execute
#  as it handles more edge cases
sub get_dep_dlls {
    my ($script, $no_execute_flag) = @_;

    #  This is clunky:
    #  make sure $script/../lib is in @INC
    #  assume script is in a bin folder
    my $rlib_path = (path ($script)->parent->parent->stringify) . '/lib';
    #say "======= $rlib_path/lib ======";
    local @INC = (@INC, $rlib_path)
      if -d $rlib_path;
    
    my $deps_hash = scan_deps(
        files   => [ $script ],
        recurse => 1,
        execute => !$no_execute_flag,
        cache_file => $cache_file,
    );
    
    #my @lib_paths 
    #  = map {path($_)->absolute}
    #    grep {defined}  #  needed?
    #    @Config{qw /installsitearch installvendorarch installarchlib/};
    #say join ' ', @lib_paths;
    my @lib_paths
      = reverse sort {length $a <=> length $b}
        map {path($_)->absolute}
        @INC;

    my $paths = join '|', @lib_paths;
    my $inc_path_re = qr /^(\Q$paths\E)/i;
    #say $inc_path_re;

    my %dll_hash;
    foreach my $package (keys %$deps_hash) {
        #  could access {uses} directly, but this helps with debug
        my $details = $deps_hash->{$package};
        my $uses    = $details->{uses};
        next if !$uses;
        
        foreach my $dll (grep {$_ =~ $RE_DLL_EXT} @$uses) {
            my $dll_path = $deps_hash->{$package}{file};
            #  Remove trailing component of path after /lib/
            if (lc($dll_path) =~ $inc_path_re) {
                $dll_path = $1 . $dll;
            }
            else {
                #  fallback, get everything after /lib/
                $dll_path =~ s|(?<=/lib/).+?$||;
                $dll_path .= $dll;
            }
            #say $dll_path;
            croak "cannot find or read $dll_path for package $package"
              if not -r $dll_path;
            $dll_hash{$dll_path}++;
        }
    }
    
    my @dll_list = sort keys %dll_hash;
    return wantarray ? @dll_list : \@dll_list;
}
