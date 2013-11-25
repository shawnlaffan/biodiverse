use strict;
use warnings;
use 5.010;
use File::Find;

use Carp;

#script that takes a directory as argument and
#recursively finds all files in the directory and its sub-directories
#that contain camelCase subname declarations.

# Usage: "camel_subname_finder.pl ." 

#this script finds declarations only to keep it neat.

if (!@ARGV) {
    say "Usage: $0 dir";
    exit 0;
}


my $re_pfx = qr /
    (
          (?:sub\s+)
        | \&
        | (?:METHOD\s*=>\s*')
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

find(\&wanted, $ARGV[0]);

say 'Done';

exit 0;


sub wanted {
    return if ! -f $_;

    my @camels;
    push @camels,  "In file " . $File::Find::name . " :\n";

    open (my $fh, '<', $File::Find::name) or die "$! $File::Find::name";
    
    my $line_num = 1;
    
    while (my $line = <$fh>) {
        my $i = 0;
        foreach my $re (@re_camel) {
            if (my @matches = $line =~ /$re/) {
                my $new_line = $line;
                my $subname     = join q{}, @matches[1 .. $#matches];
                my $new_subname = $subname;

                for my $j (2 .. $#matches) {  #  $j==2 onwards are humps
                    my $old_text = $matches[$j];
                    my $new_text = '_' . lc $old_text;
                    $new_line    =~ s/$old_text/$new_text/;
                    $new_subname =~ s/$old_text/$new_text/;
                }

                croak "File $File::Find::name sub name $subname already has non-camel variant $new_subname at line $line_num\n"
                  if clashes ($File::Find::name, $new_subname);

                push (@camels, "Line $line_num: $subname\n");
                next;
            }
            $i++;
        }
        $line_num++;
    }
    close $fh;

    print @camels, "\n" if @camels > 1;
}

#  does the non-camel form already exist?
sub clashes {
    my ($file, $subname) = @_;

    return if ! -f $file;
    my $re_subname = qr /
        (?:^sub\s+)
        $subname\b
    /x;

    open (my $fh, '<', $file) or die "$! $file";
    while (my $line = <$fh>) {
        return 1 if $line =~ /$re_subname/;
    }
    close $fh;

    return;
}

