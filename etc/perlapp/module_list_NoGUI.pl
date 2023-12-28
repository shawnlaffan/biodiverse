#  list of Biodiverse modules to ensure PerlApp gets them all when scanning this as a script
#  use the following under cygwin/*nix
#   egrep -h '^package' `find . -name '*.pm' -print`
#  then find and replace "package" with "use"

use Biodiverse::BaseData;
use Biodiverse::BaseStruct;
use Biodiverse::Cluster;
use Biodiverse::Common;
use Biodiverse::RegionGrower;
use Biodiverse::Config;
use Biodiverse::ElementProperties;
use Biodiverse::Exception;
use Biodiverse::Index;
use Biodiverse::Indices::Endemism;
use Biodiverse::Indices::GroupProperties;
use Biodiverse::Indices::HierarchicalLabels;
use Biodiverse::Indices::IEI;
use Biodiverse::Indices::Indices;
use Biodiverse::Indices::LabelProperties;
use Biodiverse::Indices::Matrix_Indices;
use Biodiverse::Indices::Numeric_Labels;
use Biodiverse::Indices::Phylogenetic;
use Biodiverse::Indices::Rarity;
use Biodiverse::Indices;
use Biodiverse::Matrix;
use Biodiverse::Progress;
use Biodiverse::Randomise;
use Biodiverse::ReadNexus;
use Biodiverse::RegionGrower;
use Biodiverse::Spatial;
use Biodiverse::SpatialParams::DefQuery;
use Biodiverse::SpatialParams;
use Biodiverse::Statistics;
use Biodiverse::TestHelpers;
use Biodiverse::Tree;
use Biodiverse::TreeNode;

