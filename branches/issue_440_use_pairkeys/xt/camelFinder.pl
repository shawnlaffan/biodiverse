use strict;
use warnings;
use File::Find;

#script that takes a directory as argument and recursively finds all files in the directory and its sub-directories
#that contain camelCase variable declarations.

# Usage: "camelFinder.pl ." 

#this script finds declarations only to keep it neat.

if (!@ARGV) {
    print "Usage: camelFinder dir";
    exit 0;
}

find(\&wanted, "$ARGV[0]");
exit 0;

sub wanted{
    return if ! -f $_;

    my @camels;
    push @camels,  "In file ".$File::Find::name." :\n";
    
    open(FILE, $_) or die "$! $File::Find::name";
    while (<FILE>) {
        push (@camels, "Line $.: $1\n") && next if /^\s*(my\s*[^\=]*[\$\@\&\%][a-z]+[A-Z].*)/;
    }
    close(FILE);
    
    print @camels, "\n" if @camels > 1;   
}

