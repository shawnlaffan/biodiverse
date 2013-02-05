###! d:/strawberry/perl/bin/perl.exe

BEGIN {
	print "STARTING\n";
}

use Config;
$pc_config = $Config{"libpth"};

$pc_config =~ s/(.*)\s+.*/$1/;

#  skip this - variable seems to have no effect anyway?
#print "pc_config is $pc_config\n";
#if ( ! -d $pc_config){
#    print "where is your strawberry/c directory?[like: D:/strawberry/c]:";
#    $pc_config  = <>;
#}


#$pc_config =~ s/\\/\//g;
#$pc_config =~ s/\/lib//g;

$pc_dir = "ex/lib/pkgconfig";

die "no ex dir. run extract.pl first\n" if ( ! -d "ex");
opendir DH, $pc_dir;

my $file;
foreach $file (readdir DH){
    print "$file\n";
    if ($file =~ /.pc$/) {
	print "Modifying $file ...\n";
	open H, "$pc_dir" . "/" . $file;
	@l = <H>;
	close H;
	open H, ">$pc_dir" . "/" . $file;
	foreach $line (@l){
	    if ($line =~ /^prefix=/){
		print H "prefix=", $pc_config, "\n";
	    }
            else{
		if ($file eq "pangocairo.pc" && $line =~ /^Libs\:/ && $line !~ /Cairo.a$/){
		    chomp $line;
		    $line .= " \${prefix}/../perl/site/lib/auto/Cairo/Cairo.a\n";
		}
		print H $line;
	    }
	}
	close H;
    }
}
closedir DH;
