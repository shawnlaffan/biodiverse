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
          (?:^sub\s+)          #  sub declarations
        | &(?:[a-zA-Z]+::])*   #  refs to fully qualified subs
        | (?:METHOD\s*=>\s*')  #  method declarations in Callbacks.pm
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

                my @clash_lines = clashes ($File::Find::name, $new_subname);
                croak "File $File::Find::name uses sub name $subname at line $line_num "
                        . "but already uses non-camel variant $new_subname\n"
                        . 'Check lines '
                        . join (q{ }, @clash_lines, "\n")
                  if scalar @clash_lines;

                push (@camels, "Line $line_num: $subname\n");
                next;
            }
            $i++;
        }
        $line_num++;
    }
    close $fh;

    say @camels if scalar @camels > 1;
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
            $match &&= not ($line =~ /\{\s*$subname\s*\}/);  #  skup hash keys
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

