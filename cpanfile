requires "Class::Inspector";
requires "Clone", "0.35";
requires "Cpanel::JSON::XS", "3";
requires "DBD::XBase";
requires "Data::Structure::Util";
requires "Data::Compare";
#requires "Data::DumpXML";
requires "Exception::Class";
requires "Exporter::Easy";
#requires "FFI::Platypus::Declare";
requires "File::BOM";
requires "File::Find::Rule";
requires "Geo::Converter::dms2dd", "0.05";
requires "Geo::GDAL::FFI", 0.09;  #  this will pick up the aliens
requires "Geo::ShapeFile", "3.00",
requires "Getopt::Long::Descriptive";
requires "HTML::QuickTable";
requires "JSON::MaybeXS", "1.003";
requires "JSON::PP";
requires "List::MoreUtils", "0.425";
requires "List::Unique::DeterministicOrder";
requires "List::Util", "1.54";
requires "Math::Polygon";
requires "Math::Random::MT::Auto", "6.21";
requires "Path::Class";
requires "Readonly";
requires "Ref::Util";
requires "Ref::Util::XS";
requires "Regexp::Common";
requires "Sereal", "3";
requires "Sort::Key";
requires "Spreadsheet::ParseExcel";
requires "Spreadsheet::ParseXLSX";
requires "Spreadsheet::ParseODS";
requires "Spreadsheet::Read", "0.82";
requires "Spreadsheet::ReadSXC", "0.28";
requires "Statistics::Descriptive", "3.0608";
requires "Statistics::Sampler::Multinomial", '1.00';
requires "Text::CSV_XS", "1.04";
requires "Text::Fuzzy";
requires "Text::Wrapper";
requires "Tree::R";
requires "URI::Escape";
requires "URI::Escape::XS";
$^O eq 'MSWin32' ? (requires "Win32::LongPath") : ();
requires "YAML::Syck", "1.29";
requires "autovivification", "0.18";
requires "parent";
requires "rlib";
#requires "Math::AnyNum";  #  until we don't
requires "Statistics::Descriptive::PDL", "0.12";

suggests "Panda::Lib";
suggests "Data::Recursive";

#test_requires => sub {
    requires "Test::Lib";
    requires "Test::TempDir::Tiny";
    requires "Test2::Suite";
    $^O ne 'MSWin32' ? (suggests "Test2::Harness") : ();
    requires "Data::Section::Simple";
    #requires "Test::Deep";
    requires "Perl::Tidy";
    #requires "Test::Most";
    requires "Devel::Symdump";
    requires "File::Compare";
    requires "Scalar::Util::Numeric";
    requires "Test::TempDir::Tiny";
    requires 'Test::Deep::NoTest';
    #requires "Test::Exception";
    requires 'Alien::Build::Plugin::Fetch::Cache';
#};

feature 'GUI', 'GUI packages' => sub {
    requires 'Browser::Start';
    requires 'ExtUtils::Depends';
    requires 'ExtUtils::Depends'; 
    requires 'ExtUtils::PkgConfig';
    requires 'Glib';
    requires 'Gnome2::Canvas';
    requires 'Gtk2';
    requires 'HTTP::Tiny';
    requires 'IO::Socket::SSL';
    requires 'LWP::Simple';
    requires 'Pango';
};
