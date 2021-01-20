requires "Alien::Build";
requires 'Path::Class';
requires 'Sort::Key::Natural';
requires 'Ref::Util';
requires 'Text::Fuzzy';

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
requires "File::BOM";
requires "Math::Polygon";
requires "Path::Class";
requires "Tree::R";
requires "Geo::ShapeFile", "3.00",
requires "List::MoreUtils", "0.425",
requires "List::Util", "1.45";
requires "Class::Inspector";
requires "autovivification", "0.16";
requires "Spreadsheet::Read", "0.82";
requires "Spreadsheet::ReadSXC", "0.28";
requires "Spreadsheet::ParseExcel";
requires "Spreadsheet::ParseXLSX";
requires "Getopt::Long::Descriptive";
requires "Sereal", "3";
requires "Cpanel::JSON::XS", "3";
requires "JSON::MaybeXS", "1.003";
requires "Data::Compare";
requires "Test::TempDir::Tiny";
requires "Statistics::Sampler::Multinomial", '1.00';
requires "List::Unique::DeterministicOrder";

requires "FFI::Platypus::Declare";
requires "Geo::GDAL::FFI", 0.07;

suggests "Panda::Lib";
suggests "Data::Recursive";

#test_requires => sub {
requires "Test2::Suite";
$^O ne 'MSWin32' ? (requires "Test2::Harness") : ();
requires "Data::Section::Simple";
#requires "Test::Deep";
requires "Perl::Tidy";
#requires "Test::Most";
requires "Devel::Symdump";
requires "File::Compare";
requires "Scalar::Util::Numeric";
requires "Test::TempDir::Tiny";
#requires "Test::Exception";
#};

feature 'GUI', 'GUI packages' => sub {
    requires 'ExtUtils::Depends'; 
    requires 'ExtUtils::PkgConfig';
    requires 'Glib';
    requires 'Gtk2';
    requires "Pango";
    requires 'Browser::Start';
    requires 'Gnome2::Canvas';
    requires 'ExtUtils::Depends';
    requires 'HTTP::Tiny';
    requires 'LWP::Simple';
    requires 'IO::Socket::SSL';
};
