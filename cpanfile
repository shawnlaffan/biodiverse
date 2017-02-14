
requires 'Geo::GDAL';
requires 'Ref::Util';
requires 'Scalar::Util::Numeric';
requires 'Task::Biodiverse::NoGUI', '1.0001';
requires 'Text::Fuzzy';
requires 'Text::Levenshtein';

requires "Data::DumpXML";
requires "Math::Random::MT::Auto", "6.21";
requires "Text::CSV_XS", "1.04";
requires "DBD::XBase";
requires "HTML::QuickTable";
requires "YAML::Syck", "1.29";
requires "Clone", "0.35";
requires "Regexp::Common";
requires "rlib";
requires "Test::Lib";
requires "parent";
requires "Readonly";
requires "URI::Escape::XS";
requires "Statistics::Descriptive", "3.0608";
requires "Geo::Converter::dms2dd", "0.05";
requires "Text::Wrapper";
requires "Exporter::Easy";
requires "Exception::Class";
requires "Math::Polygon";
requires "File::BOM";
requires "Math::Polygon";
requires "Path::Class";
requires "Tree::R";
requires "Geo::ShapeFile", "2.60",
requires "Geo::Shapefile::Writer";
requires "List::MoreUtils", "0.410",
requires "List::Util", "1.45";
requires "Class::Inspector";
requires "autovivification", "0.16";
requires "List::BinarySearch", "0.25";
requires "List::BinarySearch::XS", "0.09";
requires "Spreadsheet::Read", "0.60";
requires "Spreadsheet::ReadSXC";
requires "Spreadsheet::ParseExcel";
requires "Spreadsheet::ParseXLSX";
requires "Getopt::Long::Descriptive";
requires "Sereal", "3";
requires "Cpanel::JSON::XS", "3";
requires "JSON::MaybeXS", "1.003";
requires "Sort::Naturally";
requires "Text::Fuzzy";
requires "Ref::Util", "0.101";
requires "Text::Levenshtein";  #  should replace by Text::Fuzzy
requires "Data::Structure::Util";
requires "Data::Compare";
requires "Test::TempDir::Tiny";

#  Data::Alias does not install post 5.22
#  but cpanfile will (hopefully) just complain and keep going
#($] lt '5.024' ? ("Data::Alias", "0") : ()),
suggests "Data::Alias", "0";
suggests "Panda::Lib";

#  remove this once the to do list under issue #581 is completed
requires 'Browser::Open';

test_requires => sub {
    requires "Data::Section::Simple";
    requires "Test::Deep";
    requires "Test::NoWarnings";
    requires "Perl::Tidy";
    requires "Test::Most";
    requires "Devel::Symdump";
    requires "File::Compare";
    requires "Scalar::Util::Numeric";
    requires "Test::TempDir::Tiny"
};

feature 'GUI', 'GUI packages' => sub {
    requires 'ExtUtils::Depends'; 
    requires 'ExtUtils::PkgConfig';
    requires 'Glib';
    requires 'Gtk2';
    requires "Pango";
    #requires 'Gtk2::GladeXML';   
    requires 'Browser::Open';
    requires 'Gnome2::Canvas';
    requires 'ExtUtils::Depends';
    requires 'HTTP::Tiny';
    requires 'LWP::Simple';
};
