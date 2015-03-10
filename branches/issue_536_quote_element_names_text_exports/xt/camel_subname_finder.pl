use strict;
use warnings;
use 5.010;
use File::Find;

use Carp;
use Data::Dump;

#script that takes a directory as argument and
#recursively finds all files in the directory and its sub-directories
#that contain camelCase subname declarations.

# Usage: "camel_subname_finder.pl ." 

#this script finds declarations only to keep it neat.

if (!@ARGV) {
    say "Usage: $0 dir apply_changes";
    exit 0;
}

my $folder        = $ARGV[0];
my $do_edit_files = $ARGV[1];


my $re_pfx = qr /
    (
          (?:^sub\s+)          #  sub declarations
        | &(?:[a-zA-Z]+::])*   #  refs to fully qualified subs
        | (?:METHOD\s*=>\s*')  #  method declarations in Callbacks.pm
        | (?:->\s*)            #  method calls
    )
/x;

my $re_camel_sub1 = qr /
    $re_pfx
    ([a-z]+)
    ([A-Z][a-z]+)
    \b
/x;

my $re_camel_sub2 = qr /
    $re_pfx
    ([a-z]+)
    ([A-Z][a-z]+)
    ([A-Z][a-z]+)
    \b
/x;

my $re_camel_sub3 = qr /
    $re_pfx
    ([a-z]+)
    ([A-Z][a-z]+)
    ([A-Z][a-z]+)
    ([A-Z][a-z]+)
    \b
/x;

my $re_camel_sub4 = qr /
    $re_pfx
    ([a-z]+)
    ([A-Z][a-z]+)
    ([A-Z][a-z]+)
    ([A-Z][a-z]+)
    ([A-Z][a-z]+)
    \b
/x;


my @re_camel = ($re_camel_sub1, $re_camel_sub2, $re_camel_sub3, $re_camel_sub4);

find(\&wanted, $folder);

say 'Done';

exit 0;


sub wanted {
    return if ! -f $_;
    return if $File::Find::name =~ /\.bak$/;

    my %camels;
    my $current_hash = {};
    $camels{$File::Find::name} = $current_hash;

    open (my $fh, '<', $File::Find::name) or die "$! $File::Find::name";
    
    my $line_num = 1;
    
    while (my $line = <$fh>) {
        my $i = 0;
        foreach my $re (@re_camel) {
            if (my @matches = $line =~ /$re/) {
                my $new_line = $line;
                my $subname     = join q{}, @matches[1 .. $#matches];

                #  lowercase all the humps and prepend with underscores
                my $new_subname = $subname;
                $new_subname =~ s/([A-Z])/_\l$1/g;
                $new_line    =~ s/\b$subname\b/$new_subname/;

                my @clash_lines = clashes ($File::Find::name, $new_subname);
                croak "File $File::Find::name uses sub name $subname at line $line_num "
                        . "but already uses non-camel variant $new_subname\n"
                        . 'Check lines '
                        . join (q{ }, @clash_lines, "\n")
                  if scalar @clash_lines;

                $current_hash->{$subname} = $new_subname;
                next;
            }
            $i++;
        }
        $line_num++;
    }
    close $fh;

    if (scalar keys %$current_hash) {
        say $File::Find::name;
        dd $current_hash;
    }
    
    edit_files (\%camels);
}

#  is the non-camel form already in use?
sub clashes {
    my ($file, $subname) = @_;

    return if ! -f $file;

    open (my $fh, '<', $file) or die "$! $file";

    my @clash_lines;

    my $line_num = 0;
    while (my $line = <$fh>) {
        my $match = ($line =~ /\b$subname\b/);
        if ($match) {
            $match &&= not ($line =~ /\{\s*$subname\s*\}/);  #  skip hash keys
            $match &&= not ($line =~ /$subname\s*=>/);       #  skip hash key assignment
            $match &&= not ($line =~ /^=item/);              #  skip POD
            $match &&= not ($line =~ /[\$%@]$subname\b/);    #  skip variable names
            $match &&= not ($line =~ /->\s*$subname\b/);     #  skip method calls

            if ($match) {
                push @clash_lines, $line_num
            }
        }
        $line_num ++;
    }
    close $fh;

    return @clash_lines;
}


sub edit_files {
    my $changes_hash = shift // croak 'no changes hash passed';
    
    return if !$do_edit_files;

    use Config;
    my $perlpath = $Config{perlpath};
    
    foreach my $file (keys %$changes_hash) {
        my $changes = $changes_hash->{$file};
        while (my ($from, $to) = each %$changes ) {
            my $cmd = $perlpath . qq{ -pi.bak -e "s/$from/$to/g" } . $file;
            say $cmd;
            system $cmd;
        }
        
    }
    
}