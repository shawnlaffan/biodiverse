
use 5.016;
use PAR;
use Archive::Zip;

my $par_file = 'C:/shawn/svn/bd_releases/biodiverse_0.99_004_win64/BiodiverseGUI_x64.exe';
my $zip = Archive::Zip->new($par_file);
my $glade_zipped = $zip->extractTree( 'glade', 'glade' );

print '';

