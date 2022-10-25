use strict;
use warnings;
use Carp;
use 5.010;
use Cwd;

use English qw { -no_match_vars };

BEGIN {
    $ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;
    $ENV{BIODIVERSE_EXTENSIONS} = q{};
}

use Biodiverse::Config;
use Biodiverse::BaseData;
use Biodiverse::Indices;
use Biodiverse::ElementProperties;
use Data::Dumper;
use File::Temp;

#use HTML::HashTable;
use HTML::QuickTable;

my $e;

my $bd = Biodiverse::BaseData->new (
    CELL_SIZES => [1,1],
);
$bd->add_element (                    
    label => 'a:b',
    group => '1:1',
    count => 1,
);
my $lb_ref = $bd->get_labels_ref;
$lb_ref->set_param (CELL_SIZES => [-1,-1]);

my $label_props = get_label_properties();
eval {
    $bd->assign_element_properties (
        type              => 'labels', # plural
        properties_object => $label_props,
    )
};
$e = $EVAL_ERROR;
warn $e if $e;

my $group_props = get_group_properties();
eval {
    $bd->assign_element_properties (
        type              => 'groups', # plural
        properties_object => $group_props,
    )
};
$e = $EVAL_ERROR;
warn $e if $e;

my $indices = Biodiverse::Indices->new(BASEDATA_REF => $bd);

my $html = $indices->get_calculation_metadata_as_markdown;

#  dirty hack
#$html =~ s/PhyloCom/!PhyloCom/;

#  The YAML version
#use YAML::Syck;
#my $yaml = YAML::Syck::Dump (\%analyses_hash);
#open (my $fh_yaml, '>', 'Indices.yaml');
#print $fh_yaml $yaml;
#close $fh_yaml;



use File::Basename;
my $version = $Biodiverse::Config::VERSION;

my $wiki_leader  = "# Indices available in Biodiverse \n";
   $wiki_leader .= '_Generated GMT '
                    . (gmtime)
                    . " using "
                    . basename ($0)
                    . ", Biodiverse version $version._\n";

my $intro_wiki = <<"END_OF_INTRO";

$wiki_leader

This is a listing of the indices available in Biodiverse,
ordered by the calculations used to generate them.
It is generated from the system metadata and contains all the 
information visible in the GUI, plus some additional details.

Most of the headings are self-explanatory.  For the others:
  * The *Subroutine* is the name of the subroutine used to call the function if you are using Biodiverse through a script.  
  * The *Index* is the name of the index in the SPATIAL_RESULTS list, or if it is its own list then this will be its name.  These lists can contain a variety of values, but are usually lists of labels with some value, for example the weights used in an endemism calculation.  The names of such lists typically end in "LIST", "ARRAY", "HASH", "LABELS" or "STATS". 
  * *Grouping?* states whether or not the index can be used to define the grouping for a cluster or region grower analysis.  A blank value means it cannot be used for either.
  * The *Minimum number of neighbour sets* dictates whether or not a calculation or index will be run.  If you specify only one neighbour set then all those calculations that require two sets will be dropped from the analysis.  (This is always the case for calculations applied to cluster nodes as there is only one neighbour set, defined by the set of groups linked to the terminal nodes below a cluster node).  Note that many of the calculations lump neighbour sets 1 and 2 together.  See the [SpatialConditions](SpatialConditions.md) page for more details on neighbour sets.

Note that calculations can provide different numbers of indices depending on the nature of the BaseData set used.
This currently applies to the hierarchically partitioned endemism calculations (both [central](#endemism-central-hierarchical-partition) and [whole](#endemism-whole-hierarchical-partition)) and [hierarchical labels](#hierarchical-labels).


END_OF_INTRO

my $wiki_text = $intro_wiki . $html;

#  Maybe insert hyperlinks later on, but need to handle overlapping heading
#  names like 'Endemism' and 'Endemism central'
#my @headings = $wiki_text =~ m/={2,3}(.+?)={2,3}/mgx;

#  hyperlink the Label counts text for now
$wiki_text =~ s/'Label counts'/\[Label counts\]\(#label-counts\)/g;

my $code_cogs = << 'END_CODE_COGS'
<img src="http://www.codecogs.com/images/poweredbycc.gif"
 width="102" height="34" vspace="5" border="0"
 alt="Powered by CodeCogs"
 style="background-color:white;"
/>
http://www.codecogs.com
END_CODE_COGS
;

$wiki_text .= $code_cogs;

$version =~ s/\.//g;
my $v = $version;

my $fname = "Indices_$v.md";
my $dir = cwd();

say "Writing to file $fname";

my $fh;
open ($fh, '>', $fname) || croak;

print $fh $wiki_text;
close $fh;

say 'done';

sub get_label_properties {
    my $data = <<'END_LABEL_PROPS'
ax1,ax2,exprop1,exprop2
a,b,1,1,1
END_LABEL_PROPS
  ;
  
    element_properties_from_string($data);
}

sub get_group_properties {
    my $data = <<'END_GP_PROPS'
ax1,ax2,gprop1,gprop2
1,1,1,1,1
END_GP_PROPS
  ;

    element_properties_from_string($data);
}

sub element_properties_from_string {
    my ($data) = @_;
    my $file = write_data_to_temp_file($data);
    my $props = Biodiverse::ElementProperties->new;

    # Get property column names and positions. First is 2.
    # Results in something like:
    # (LBPROP1 => 3, LBPROP2 => 4, ...)
    my $i = 2;
    $data =~ m/^(.*)$/m;
    my @prop_names = split ',', $1;
    my %prop_cols = map { $_ => $i++; } @prop_names[2..$#prop_names];

    my $success = eval { $props->import_data (
        input_element_cols    => [0,1],
        file                  => $file,
        %prop_cols, # Tell import_data which columns contain which properties
    ) };
    my $e = $EVAL_ERROR;
    warn $e if $e;

    return $props;
}

sub write_data_to_temp_file {
    my $data = shift;

    my $tmp_obj = File::Temp->new;
    my $fname = $tmp_obj->filename;
    print $tmp_obj $data;
    $tmp_obj->close;

    return $tmp_obj;
}
