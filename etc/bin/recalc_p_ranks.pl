use 5.016;

use rlib;

use Biodiverse::BaseData;

use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'glob=s',     'glob to find files', { required => 1 } ],
  #[ 'output_prefix|opfx=s', 'The output prefix for exported files', {required => 1}],
  #[ 'no_verify|n!', 'do not verify that the basedatas match', { default => 1} ],
  [],
  [ 'help',       "print usage message and exit" ],
);


my $glob = $opt->glob;
#my $opfx = $opt->output_prefix;
#my $no_verify = $opt->no_verify;

my @files = glob $glob;

die "No files found using $glob" if !@files;


foreach my $from_file (@files) {
    say "Recalculating from $from_file";

    my $bd = Biodiverse::BaseData->new(file => $from_file);
    my @outputs = $bd->get_output_refs;
    
    my @rand_names
      = map {$_->get_name}
        grep {$_->isa('Biodiverse::Randomise')} @outputs;
    
    foreach my $output_ref (@outputs) {
        #  hacky
        next if not $output_ref->isa ('Biodiverse::Spatial');
        foreach my $rand_name (@rand_names) {
            $output_ref->convert_comparisons_to_significances (
                result_list_name => $rand_name,
            );
        }
    }
    $bd->save_to (filename => $from_file);
}


