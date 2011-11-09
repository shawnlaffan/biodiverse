#  list of Biodiverse modules to ensure PerlApp gets them all when scanning this as a script
#  use the following under cygwin/*nix
#   egrep -h '^Package' `find . -name '*.pm' -print`
#  then find and replace

use Biodiverse::BaseData;
use Biodiverse::BaseStruct;
use Biodiverse::Cluster;
use Biodiverse::Common;
use Biodiverse::ElementProperties;
use Biodiverse::Index;
use Biodiverse::Indices;
use Biodiverse::Indices::Hierarchical_Labels;
use Biodiverse::Indices::IEI;
use Biodiverse::Indices::Indices;
use Biodiverse::Indices::Matrix_Indices;
use Biodiverse::Indices::Numeric_Labels;
use Biodiverse::Indices::Phylogenetic;
use Biodiverse::Indices::Endemism;
use Biodiverse::Indices::Rarity;
use Biodiverse::Indices::LabelProperties;
use Biodiverse::Indices::GroupProperties;
use Biodiverse::Matrix;
use Biodiverse::Randomise;
use Biodiverse::ReadNexus;
use Biodiverse::RegionGrower;
use Biodiverse::Spatial;
use Biodiverse::SpatialParams;
use Biodiverse::Tree;
use Biodiverse::TreeNode;
use Biodiverse::Config;

