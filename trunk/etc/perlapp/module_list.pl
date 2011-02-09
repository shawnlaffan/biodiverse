#  list of Biodiverse modules to ensure PerlApp gets them all when scanning this as a script
#  use the following under cygwin/*nix
#   egrep -h '^Package' `find . -name '*.pm' -print`
#  then find and replace

use Biodiverse::GUI::BasedataImport;
use Biodiverse::GUI::Callbacks;
use Biodiverse::GUI::CellPopup;
use Biodiverse::GUI::Dendrogram;
use Biodiverse::GUI::Exclusions;
use Biodiverse::GUI::Export;
use Biodiverse::GUI::Grid;
use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Help;
use Biodiverse::GUI::MatrixGrid;
use Biodiverse::GUI::MatrixImport;
use Biodiverse::GUI::OpenDialog;
use Biodiverse::GUI::Overlays;
use Biodiverse::GUI::ParametersTable;
use Biodiverse::GUI::PhylogenyImport;
use Biodiverse::GUI::Popup;
use Biodiverse::GUI::PopupObject;
use Biodiverse::GUI::ProgressDialog;
use Biodiverse::GUI::Project;
use Biodiverse::GUI::SpatialParams;
use Biodiverse::GUI::Tabs::AnalysisTree;
use Biodiverse::GUI::Tabs::Clustering;
use Biodiverse::GUI::Tabs::Labels;
use Biodiverse::GUI::Tabs::Outputs;
use Biodiverse::GUI::Tabs::Randomise;
use Biodiverse::GUI::Tabs::RegionGrower;
use Biodiverse::GUI::Tabs::Spatial;
use Biodiverse::GUI::Tabs::SpatialMatrix;
use Biodiverse::GUI::Tabs::Tab;
use Biodiverse::GUI::YesNoCancel;

