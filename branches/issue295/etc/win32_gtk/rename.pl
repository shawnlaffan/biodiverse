#! d:/strawberry/perl/bin/perl.exe
use File::Copy qw/cp/;

$lib_dir = "ex/lib";

die "no ex dir. run extract.pl first\n" if ( ! -d "ex");
opendir DH, $lib_dir;
foreach (readdir DH){
    if (/.dll.a$/){
	$dfile = $_;
	$dfile =~ s/.dll//;
	print "Renaming $_ to $dfile...\n";
	cp($lib_dir . "/" . $_ , $lib_dir . "/" . $dfile);
    }
}
closedir DH;
