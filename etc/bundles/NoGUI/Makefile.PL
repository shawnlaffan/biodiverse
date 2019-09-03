use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

require 5.016;

WriteMakefile(
    'NAME' => 'Task::Biodiverse::NoGUI',
    'VERSION_FROM' => 'lib/Task/Biodiverse/NoGUI.pm', # finds $VERSION
    ($] ge '5.005') ? (
        'AUTHOR' => 'Shawn Laffan (shawn.laffan@unsw.edu.au)',
        'ABSTRACT' => 'Task for Biodiverse dependencies for non-GUI use',
        )
    : (),
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/shawnlaffan/biodiverse.git',
                web  => 'http://purl.org/biodiverse',
            },
            bugtracker => {
                web => 'https://github.com/shawnlaffan/biodiverse/issues/',
            },
        },
    },
    PREREQ_PM => {
        "Data::DumpXML" => "0",
        "Math::Random::MT::Auto" => "6.21",
        "Text::CSV_XS" => "1.04",
        "DBD::XBase" => "0",
        "HTML::QuickTable" => "0",
        "YAML::Syck" => "1.29",
        "Clone" => "0.35",
        "Regexp::Common" => "0",
        "rlib" => "0",
        "Test::Lib" => "0",
        "parent" => "0",
        "Readonly" => "0",
        "URI::Escape::XS" => "0",
        "Statistics::Descriptive" => "3.0608",
        "Geo::Converter::dms2dd" => "0.05",
        "Text::Wrapper" => "0",
        "Exporter::Easy" => "0",
        "Exception::Class" => "0",
        "Math::Polygon" => "0",
        "File::BOM" => "0",
        "Math::Polygon" => "0",
        "Path::Class" => "0",
        "Tree::R" => "0",
        "Geo::ShapeFile" => "2.60",
        "Geo::Shapefile::Writer" => "0",
        "List::MoreUtils" => "0.425",
        "List::Util" => "1.45",
        "Class::Inspector" => "0",
        "autovivification" => "0.16",
        "List::BinarySearch" => "0.25",
        "List::BinarySearch::XS" => "0.09",
        "Spreadsheet::Read" => "0.60",
        "Spreadsheet::ReadSXC" => "0",
        "Spreadsheet::ParseExcel" => "0",
        "Spreadsheet::ParseXLSX" => "0",
        #  Data::Alias does not install post 5.22
        ($] lt '5.024' ? ("Data::Alias" => "0") : ()),  
        "Getopt::Long::Descriptive" => "0",
        "Sereal" => "3",
        "Cpanel::JSON::XS" => 3,
        "JSON::MaybeXS" => 1.003,
        "JSON::PP" => 0,
        "Sort::Naturally" => 0,
        "Sort::Key::Natural" => 0,
        "Text::Fuzzy" => 0,
        "Ref::Util" => "0.101",
        "Text::Levenshtein" => 0,
        "Data::Structure::Util" => 0,
        "Data::Compare" => 0,
        "Test::TempDir::Tiny" => "0.016",
        "Statistics::Sampler::Multinomial" => 0,
        "List::Unique::DeterministicOrder" => 0,
        "Geo::GDAL::FFI" => 0.07,
        "PkgConfig" => 0.21026,   #  version that works with PAR::Packer
    },
    BUILD_REQUIRES => {
        "Data::Section::Simple" => "0",
        "Test::Deep" => "0",
        "Test::NoWarnings" => "0",
        "Perl::Tidy" => "0",
        "Test::Most" => "0",
        "Devel::Symdump" => "0",
        "File::Compare" => "0",
        "Scalar::Util::Numeric" => "0",
    },
);
