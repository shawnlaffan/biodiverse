use 5.016;

use rlib;

use Biodiverse::BaseData;

use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'glob=s',     'glob to find files', { required => 1 } ],
  [ 'output_prefix|opfx=s', 'The output prefix for exported files', {required => 1}],
  [],
  [ 'help',       "print usage message and exit" ],
);


my $glob = $opt->glob;
my $opfx = $opt->output_prefix;

my @files = glob $glob;

die "No files found using $glob" if !@files;
die "Only one file found using $glob ($files[0])" if @files == 1;

my $first_bd = shift @files;
my $bd = Biodiverse::BaseData->new (file => $first_bd);

foreach my $from_file (@files) {
    say "Reintegrating from $from_file";

    my $from_bd = Biodiverse::BaseData->new(file => $from_file);
    $bd->reintegrate_after_parallel_randomisations (
        from => $from_bd,
    );
    
}

$bd->save_to (filename => $opfx);

