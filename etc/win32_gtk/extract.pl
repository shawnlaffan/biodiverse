#! d:/strawberry/perl/bin/perl.exe
use Archive::Zip;

$pkg_dir = "packages";
$ex_dir = "ex";

mkdir $ex_dir if ( ! -d $ex_dir);
opendir DH, $pkg_dir;
foreach $file (readdir DH){
    if ($file =~ /.zip$/) {
        print "Extracting $file ...\n";
        my $zip = Archive::Zip->new( $pkg_dir . "/" . $file );
        $zip->extractTree('', $ex_dir . "/");
    }
}
