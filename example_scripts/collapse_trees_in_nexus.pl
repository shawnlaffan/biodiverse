use strict;
use warnings;
use 5.010;

use Carp;
use English qw { -no_match_vars };

local $| = 1;

use Biodiverse::Tree;
use Biodiverse::ReadNexus;

my $read_nexus = Biodiverse::ReadNexus->new();

my $in_file  = shift @ARGV;
my $out_file = shift @ARGV;
my $threshold = shift @ARGV // (2 / 3);

croak "no basedata file specified" if !defined $in_file;

open my $fh, '<', $in_file or croak "Cannot open $in_file";

my $fname = $out_file;
open my $ofh, '>', $fname
  or croak "cannot open $fname";


LINE:
while (defined (my $line = <$fh>)) {
    if ($line =~ /^tree\s+(\w+)\s*=\s*(.+)/) {
        my ($tree_name, $newick) = ($1, $2);
        
        say $tree_name;
    
        my $tree = Biodiverse::Tree->new (NAME => $tree_name);
        my $count = 0;
        my $node_count = \$count;
    
        $read_nexus->parse_newick (
            string          => $newick,
            tree            => $tree,
            node_count      => $node_count,
        );

        $tree->collapse_tree_below (target_value => $threshold);

        my $newick_trimmed = $tree->to_newick;
        $line = "tree $tree_name = $newick_trimmed;\n";
    }

    print { $ofh } $line;
}

